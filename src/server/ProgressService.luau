--!strict
-- Grzybopedia, codzienne zadania, seria logowań i tygodniowe wyniki gracza.
-- Logika jest w Shared/Progress (testy), tu tylko podpięcie pod grę:
--   GameService woła ProgressService.found (grzyb trafił do koszyka) i ProgressService.event
--   (sprzedaż, ucieczka strażnikowi, kradzież, sadzenie, skrzynia, ulepszenie).
-- Nagrody za zadania i logowanie przychodzą same, bez klikania „odbierz”.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Progress = require(Shared.Progress)
local Remotes = require(Shared.Remotes)
local DataService = require(script.Parent.DataService)

type Data = DataService.Data
type MutationInfo = { variant: string?, tags: { string }? }

export type Api = {
	getData: (Player) -> Data?,
	notify: (Player, string, { any }?, string?, MutationInfo?) -> (),
	pushState: (Player) -> (),
}

local ProgressService = {}

local ProgressUpdate = Remotes.get("ProgressUpdate")
local QuestReroll = Remotes.get("QuestReroll")

local api: Api
local lastSent: { [Player]: string } = {}

local function scaleOf(data: Data): number
	return Progress.rewardScale(data.caveUnlocked, data.swampUnlocked)
end

local function grantLuck(data: Data, seconds: number)
	data.luckUntil = math.max(os.time(), data.luckUntil) + seconds
end

-- Tytuł nad głową: klient czyta atrybut i tłumaczy klucz (TitleView)
local function refreshTitle(player: Player, data: Data)
	-- Tytuł z Grzybopedii wygrywa; bez niego „Nowy” dla każdego, kto skończył samouczek
	local tutorial = data.tutorial
	local fallback = if typeof(tutorial) == "number" and tutorial >= Config.Tutorial.done then "TITLE_NEW" else ""
	player:SetAttribute("AtlasTitle", Progress.title(data.atlas) or fallback)
end

-- Stan dla klienta (okna Grzybopedii i zadań). Wysyłamy tylko, gdy coś się zmieniło.
local function send(player: Player, force: boolean?)
	local data = api.getData(player)
	if not data then
		return
	end
	local now = os.time()
	local scale = scaleOf(data)
	local quests = {}
	for _, state in data.daily.quests do
		local def = Progress.getQuest(state.id)
		if def then
			table.insert(quests, { id = state.id, n = state.n, goal = def.goal, done = state.done, reward = Progress.questReward(def, scale) })
		end
	end
	local payload = {
		atlas = data.atlas,
		bonus = Progress.atlasBonus(data.atlas),
		title = Progress.title(data.atlas),
		quests = quests,
		rerolled = data.daily.rerolled,
		bonusDone = data.daily.bonusDone,
		dailyBonus = math.floor(Progress.DAILY_BONUS.reward * scale),
		streak = data.streak.count,
		loginDay = (math.max(data.streak.count, 1) - 1) % #Progress.LOGIN_REWARDS + 1,
		scale = scale,
		day = data.daily.day,
		resetAt = now + Progress.secondsToNextDay(now),
	}
	-- Odcisk bez resetAt (zmienia się co sekundę, klient i tak liczy sam)
	local fingerprint = HttpService:JSONEncode({ payload.atlas, payload.quests, payload.rerolled, payload.streak, payload.day, scale })
	if not force and lastSent[player] == fingerprint then
		return
	end
	lastSent[player] = fingerprint
	ProgressUpdate:FireClient(player, payload)
end

-- Nagroda za dzisiejsze wejście (też o północy, gdy gracz akurat gra)
local function claimLogin(player: Player, data: Data)
	local today = Progress.dayIndex(os.time())
	local cycleDay = Progress.claimLogin(data.streak, today)
	if not cycleDay then
		return
	end
	local amount = math.floor(Progress.LOGIN_REWARDS[cycleDay] * scaleOf(data))
	data.coins += amount
	local luck = cycleDay == #Progress.LOGIN_REWARDS
	if luck then
		grantLuck(data, Progress.LOGIN_LUCK_SECONDS)
	end
	api.notify(player, if luck then "MSG_LOGIN_REWARD_LUCK" else "MSG_LOGIN_REWARD", {
		data.streak.count,
		amount,
		math.floor(Progress.LOGIN_LUCK_SECONDS / 60),
	})
	api.pushState(player)
end

local function newDay(player: Player, data: Data)
	local now = os.time()
	Progress.ensureWeek(data, Progress.weekIndex(now))
	if Progress.ensureDaily(data, Progress.dayIndex(now), player.UserId) then
		api.notify(player, "MSG_QUESTS_NEW")
	end
	claimLogin(player, data)
end

function ProgressService.join(player: Player)
	local data = api.getData(player)
	if not data then
		return
	end
	-- Komunikaty o progach księgi, które gracz zdobył przed tą wersją, nie są potrzebne
	if #data.atlasDone == 0 then
		data.atlasDone = Progress.milestones(data.atlas)
	end
	newDay(player, data)
	refreshTitle(player, data)
	send(player, true)
end

function ProgressService.leave(player: Player)
	lastSent[player] = nil
end

-- Zdarzenie z gry, które może posunąć zadania (kind jak w Progress.QUESTS)
function ProgressService.event(player: Player, kind: string, amount: number?)
	local data = api.getData(player)
	if not data then
		return
	end
	local completed, allDone = Progress.questEvent(data.daily, kind, amount)
	if #completed > 0 then
		local scale = scaleOf(data)
		for _, def in completed do
			local reward = Progress.questReward(def, scale)
			data.coins += reward
			api.notify(player, "MSG_QUEST_DONE", { reward })
		end
		if allDone then
			local bonus = math.floor(Progress.DAILY_BONUS.reward * scale)
			data.coins += bonus
			grantLuck(data, Progress.DAILY_BONUS.luckSeconds)
			api.notify(player, "MSG_QUESTS_ALL_DONE", { bonus, math.floor(Progress.DAILY_BONUS.luckSeconds / 60) })
		end
		api.pushState(player)
	end
	if kind == "steal" then
		data.weekly.steals += amount or 1
	end
	send(player)
end

-- Nowe progi stron Grzybopedii: komunikat raz na próg, potem tytuł nad głową
local function checkMilestones(player: Player, data: Data)
	for _, milestone in Progress.milestones(data.atlas) do
		if not table.find(data.atlasDone, milestone) then
			table.insert(data.atlasDone, milestone)
			local page, rank = string.match(milestone, "^(%a+):(%d)$")
			local tier = Progress.TIERS[(tonumber(rank) or 0) + 1]
			if page and tier then
				api.notify(player, "MSG_ATLAS_TIER", { math.floor(tier.bonus * 100 + 0.5) }, "ATLAS_PAGE_" .. string.upper(page))
			end
		end
	end
	refreshTitle(player, data)
end

-- Grzyb trafił do koszyka. source: "pick" (zerwany w lesie) albo "hoard" (z legowiska strażnika)
function ProgressService.found(player: Player, item: { s: string, v: string?, x: { string }? }, source: string)
	local data = api.getData(player)
	if not data then
		return
	end
	-- Grzybopedia
	local newEntry, newSpecies = Progress.discover(data.atlas, item.s, item.v)
	if newEntry then
		local species = Economy.getSpecies(item.s)
		api.notify(player, if newSpecies then "MSG_ATLAS_NEW_SPECIES" else "MSG_ATLAS_NEW_FORM", nil, species and species.key or nil, {
			variant = item.v,
		})
		ProgressService.event(player, "discover", 1)
		checkMilestones(player, data)
	end
	-- Najlepsze znalezisko tygodnia (ranking)
	local now = os.time()
	Progress.ensureWeek(data, Progress.weekIndex(now))
	local score = Progress.encodeFind(item.s, item.v, Economy.itemValue(item :: any))
	if score > data.weekly.best then
		data.weekly.best = score
	end
	-- Zadania
	if source == "pick" then
		ProgressService.event(player, "pick", 1)
		if item.v or (item.x and #item.x > 0) then
			ProgressService.event(player, "pickMutated", 1)
		end
		if Economy.variantRank(item.v) >= 2 then
			ProgressService.event(player, "pickGold", 1)
		end
	end
	send(player)
end

-- Dodatek do ceny przy sprzedaży z ukończonych stron Grzybopedii (0.11 = +11%)
function ProgressService.sellBonus(player: Player): number
	local data = api.getData(player)
	return if data then Progress.atlasBonus(data.atlas) else 0
end

-- Panel DEV: sprawdzanie księgi i zadań bez godzin grania
function ProgressService.dev(player: Player, action: string): boolean
	local data = api.getData(player)
	if not data then
		return false
	end
	if action == "atlasGold" or action == "atlasRainbow" then
		-- Złota forma każdego gatunku (tęcza: wszystkie formy), komunikaty o progach jak w grze
		for _, page in Progress.PAGES do
			for _, species in Progress.pageSpecies(page) do
				Progress.discover(data.atlas, species.id, "gold")
				if action == "atlasRainbow" then
					for _, variant in { "silver", "rainbow" } do
						Progress.discover(data.atlas, species.id, variant)
					end
				end
			end
		end
		checkMilestones(player, data)
	elseif action == "atlasClear" then
		table.clear(data.atlas)
		table.clear(data.atlasDone)
		refreshTitle(player, data)
	elseif action == "questsDone" then
		for _, state in data.daily.quests do
			local def = Progress.getQuest(state.id)
			if def then
				ProgressService.event(player, def.kind, def.goal)
			end
		end
	elseif action == "questsNew" then
		-- Jakby był nowy dzień: nowe zadania i nagroda za kolejny dzień serii
		data.daily.day = -1
		data.streak.day = Progress.dayIndex(os.time()) - 1
		newDay(player, data)
	else
		return false
	end
	send(player, true)
	return true
end

local function onReroll(player: Player, index: unknown)
	local data = api.getData(player)
	if not data or typeof(index) ~= "number" then
		return
	end
	if Progress.reroll(data.daily, math.floor(index), player.UserId) then
		send(player)
	end
end

function ProgressService.start(serviceApi: Api)
	api = serviceApi
	QuestReroll.OnServerEvent:Connect(onReroll)
	-- Północ (UTC): nowe zadania i nagroda za kolejny dzień serii dla tych, którzy akurat grają
	task.spawn(function()
		while true do
			task.wait(15)
			for _, player in Players:GetPlayers() do
				local data = api.getData(player)
				if data and data.daily.day ~= Progress.dayIndex(os.time()) then
					newDay(player, data)
					send(player)
				end
			end
		end
	end)
end

-- Po końcu samouczka (tytuł „Nowy”)
function ProgressService.refreshTitle(player: Player)
	local data = api.getData(player)
	if data then
		refreshTitle(player, data)
	end
end

return ProgressService
