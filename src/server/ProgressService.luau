--!strict
-- Grzybopedia, codzienne zadania, seria logowań i tygodniowe wyniki gracza.
-- Logika jest w Shared/Progress (testy), tu tylko podpięcie pod grę:
--   GameService woła ProgressService.found (grzyb trafił do koszyka) i ProgressService.event
--   (sprzedaż, ucieczka strażnikowi, kradzież, sadzenie, skrzynia, ulepszenie).
-- Nagrody za zadania, premię za komplet i serię logowań gracz odbiera sam (przycisk w oknie Zadań,
-- przycisk Zadania miga, gdy coś czeka). Zrobione zadanie nie przepada do końca dnia.

local BadgeService = game:GetService("BadgeService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Progress = require(Shared.Progress)
local Remotes = require(Shared.Remotes)
local Achievements = require(Shared.Achievements)
local Titles = require(Shared.Titles)
local Halloween = require(Shared.Halloween)
local Winter = require(Shared.Winter)
local Skins = require(Shared.Skins)
local Showcase = require(Shared.Showcase)
local DataService = require(script.Parent.DataService)
local Ledger = require(script.Parent.Ledger)

type Data = DataService.Data
type MutationInfo = { variant: string?, tags: { string }? }

export type Api = {
	getData: (Player) -> Data?,
	notify: (Player, string, { any }?, string?, MutationInfo?) -> (),
	pushState: (Player) -> (),
	applyStats: (Player) -> (), -- przebudowa latarni i nożyka w dłoni (skórki)
}

local ProgressService = {}

local ProgressUpdate = Remotes.get("ProgressUpdate")
local QuestReroll = Remotes.get("QuestReroll")
local QuestClaim = Remotes.get("QuestClaim")
local SelectTitle = Remotes.get("SelectTitle")
local SaveSettings = Remotes.get("SaveSettings")
local AdventOpen = Remotes.get("AdventOpen")
local FindCard = Remotes.get("FindCard")

-- Ustawienia dźwięku jako atrybuty gracza (klient czyta je w SettingsButtons)
local function applySettings(player: Player, data: Data)
	player:SetAttribute("MusicOn", data.settings.music)
	player:SetAttribute("SfxOn", data.settings.sfx)
	player:SetAttribute("MusicVolume", data.settings.musicVolume)
	player:SetAttribute("SfxVolume", data.settings.sfxVolume)
	player:SetAttribute("X2Card", data.settings.x2Card)
end

local api: Api
local lastSent: { [Player]: string } = {}
local lastAdvent: { [Player]: number } = {} -- ostatnie otwarcie okienka kalendarza (os.clock)

local function scaleOf(data: Data): number
	return Progress.rewardScale(data.caveUnlocked, data.swampUnlocked, data.mountainUnlocked)
end

local function grantLuck(data: Data, seconds: number)
	data.luckUntil = math.max(os.time(), data.luckUntil) + seconds
end

local function titleContext(data: Data): Titles.Context
	local tutorial = data.tutorial
	return {
		atlas = data.atlas,
		bestiary = data.bestiary,
		stats = data.stats,
		tutorialDone = typeof(tutorial) == "number" and tutorial >= Config.Tutorial.done,
	}
end

-- Odznaki Robloxa za osiągnięcia (tylko te z numerem w Config.Badges). Przyznane zapisujemy,
-- żeby nie pytać Robloxa co chwilę; w trakcie przyznawania drugi raz nie próbujemy.
local awarding: { [Player]: { [string]: boolean } } = {}
-- Nowsza nazwa metody to AwardBadgeAsync; starsze wersje Robloxa mają tylko AwardBadge
local awardBadge: any = (function()
	local ok, method = pcall(function()
		return (BadgeService :: any).AwardBadgeAsync
	end)
	return if ok and method then method else (BadgeService :: any).AwardBadge
end)()
local function checkBadges(player: Player, data: Data)
	local done = Achievements.check({
		atlas = data.atlas,
		bestiary = data.bestiary,
		stats = data.stats :: any,
		caveUnlocked = data.caveUnlocked,
		swampUnlocked = data.swampUnlocked,
		mountainUnlocked = data.mountainUnlocked,
	})
	local busy = awarding[player]
	if not busy then
		busy = {}
		awarding[player] = busy
	end
	for _, id in Achievements.pending(done, data.badges) do
		if not busy[id] then
			busy[id] = true
			local badgeId = (Config :: any).Badges[id] :: number
			task.spawn(function()
				local ok, has = pcall(BadgeService.UserHasBadgeAsync, BadgeService, player.UserId, badgeId)
				if ok and not has then
					ok, has = pcall(awardBadge, BadgeService, player.UserId, badgeId)
				end
				if ok and has and not table.find(data.badges, id) then
					table.insert(data.badges, id)
				elseif not ok then
					warn("[ProgressService] odznaka", id, has)
				end
				-- Po nieudanej próbie spróbujemy przy następnym zdarzeniu
				task.delay(if ok then 0 else 60, function()
					if awarding[player] then
						awarding[player][id] = nil
					end
				end)
			end)
		end
	end
end

-- Tytuł nad głową: klient czyta atrybut i tłumaczy klucz (TitleView).
-- Wybrany przez gracza z listy zdobytych, a bez wyboru najlepszy. Nowo zdobyte: komunikat.
local function refreshTitle(player: Player, data: Data)
	local earned = Titles.earned(titleContext(data))
	local seen = data.titles
	if seen then
		for _, id in Titles.newlyEarned(earned, seen) do
			-- „Nowy” po samouczku bez komunikatu (samouczek kończy się swoim)
			if id ~= "TITLE_NEW" then
				api.notify(player, "MSG_TITLE_NEW", nil, id)
			end
		end
	else
		-- Stary zapis: tytuły zdobyte wcześniej bez komunikatów
		local fresh = {}
		Titles.newlyEarned(earned, fresh)
		data.titles = fresh
	end
	player:SetAttribute("AtlasTitle", Titles.resolve(data.titleChoice, earned))
	checkBadges(player, data)
end

-- Skórki, które gracz ma (z kotła, z choinki i ze ścieżek nagród)
local function ownedSkins(data: Data): { string }
	return Skins.owned(data.skins, data.stats)
end

-- Stan dla klienta (okna Grzybopedii i zadań). Wysyłamy tylko, gdy coś się zmieniło.
local function send(player: Player, force: boolean?)
	local data = api.getData(player)
	if not data then
		return
	end
	local now = os.time()
	local today = Progress.dayIndex(now)
	local loginNextDay, loginNextCount = Progress.loginPreview(data.streak, today)
	local scale = scaleOf(data)
	local quests = {}
	for _, state in data.daily.quests do
		local def = Progress.getQuest(state.id)
		if def then
			table.insert(quests, {
				id = state.id,
				n = state.n,
				goal = def.goal,
				done = state.done,
				claimed = state.claimed,
				reward = Progress.questReward(def, scale),
			})
		end
	end
	local payload = {
		atlas = data.atlas,
		bestiary = data.bestiary,
		bonus = Progress.atlasBonus(data.atlas),
		title = Progress.title(data.atlas),
		quests = quests,
		rerolled = data.daily.rerolled,
		bonusDone = data.daily.bonusDone,
		bonusClaimed = data.daily.bonusClaimed,
		dailyBonus = math.floor(Progress.DAILY_BONUS.reward * scale),
		streak = data.streak.count,
		freeze = data.streak.freeze or 0,
		loginDay = (math.max(data.streak.count, 1) - 1) % #Progress.LOGIN_REWARDS + 1,
		-- Nagroda za dzisiejsze wejście czeka na odbiór: który to dzień cyklu i seria po odbiorze
		loginReady = Progress.loginReady(data.streak, today),
		loginNextDay = loginNextDay,
		loginNextCount = loginNextCount,
		claimable = Progress.claimable(data.daily, data.streak, today),
		scale = scale,
		day = data.daily.day,
		resetAt = now + Progress.secondsToNextDay(now),
		stats = data.stats,
		titleChoice = data.titleChoice,
		tutorialDone = titleContext(data).tutorialDone,
		eventClaimed = data.eventClaimed,
		candyBag = data.candyBag,
		skins = ownedSkins(data),
		equipped = data.equipped,
		winterClaimed = data.winterClaimed,
		flakeBag = data.flakeBag,
		advent = data.advent,
	}
	-- Odcisk bez resetAt (zmienia się co sekundę, klient i tak liczy sam). Gdyby JSONEncode nie
	-- przełknął danych (np. śmieci w zapisie), wysyłamy i tak: okna bez stanu pokazują „Label”.
	local encoded, fingerprint = pcall(HttpService.JSONEncode, HttpService, {
		payload.atlas,
		payload.bestiary,
		payload.quests,
		payload.rerolled,
		payload.bonusDone,
		payload.bonusClaimed,
		payload.loginReady,
		payload.streak,
		payload.day,
		scale,
		payload.stats,
		payload.titleChoice,
		payload.tutorialDone,
		payload.eventClaimed,
		payload.candyBag,
		payload.skins :: any,
		payload.equipped :: any,
		payload.winterClaimed,
		payload.flakeBag,
		payload.advent :: any,
	})
	if not encoded then
		warn("[ProgressService] Odcisk stanu się nie policzył dla " .. player.Name .. ": " .. tostring(fingerprint))
		fingerprint = tostring(os.clock())
	end
	if not force and lastSent[player] == fingerprint then
		return
	end
	lastSent[player] = fingerprint
	ProgressUpdate:FireClient(player, payload)
end

-- Progi ścieżki nagród osiągnięte od ostatniego razu. Tytuły liczy Titles (stats.candy),
-- tu dajemy resztę: miksturę szczęścia i monety.
local function grantTrack(player: Player, data: Data)
	local steps = Halloween.newSteps(data.eventClaimed, data.stats.candy)
	for _, index in steps do
		local step = Halloween.TRACK[index]
		if step.kind == "luck" and step.seconds then
			grantLuck(data, step.seconds)
			api.notify(player, "MSG_TRACK_LUCK", { math.floor(step.seconds / 60) })
		elseif step.kind == "coins" and step.scale then
			local coins = math.floor(step.scale * scaleOf(data))
			Ledger.earn(player, data, coins, "Gameplay", "EventTrack")
			api.notify(player, "MSG_TRACK_COINS", { coins })
		elseif step.kind == "skin" and step.id then
			-- Nowa skórka: od razu w dłoni, jeśli w tym miejscu nie ma innej
			local skin = Halloween.getSkin(step.id)
			if skin then
				local equipped = data.equipped :: any
				if equipped[skin.slot] == "" then
					equipped[skin.slot] = step.id
					api.applyStats(player)
				end
				api.notify(player, "MSG_TRACK_SKIN", nil, skin.key)
			end
		end
		data.eventClaimed = index
	end
	if #steps > 0 then
		api.pushState(player)
		send(player)
	end
end

-- Zima: progi ścieżki płatków osiągnięte od ostatniego razu (tytuły liczy Titles ze stats.snowflakes)
local function grantWinterTrack(player: Player, data: Data)
	local steps = Winter.newSteps(data.winterClaimed, data.stats.snowflakes)
	for _, index in steps do
		local step = Winter.TRACK[index]
		if step.kind == "luck" and step.seconds then
			grantLuck(data, step.seconds)
			api.notify(player, "MSG_WTRACK_LUCK", { math.floor(step.seconds / 60) })
		elseif step.kind == "coins" and step.scale then
			local coins = math.floor(step.scale * scaleOf(data))
			Ledger.earn(player, data, coins, "Gameplay", "WinterTrack")
			api.notify(player, "MSG_WTRACK_COINS", { coins })
		elseif step.kind == "skin" and step.id then
			-- Nowa skórka: od razu w dłoni, jeśli w tym miejscu nie ma innej
			local skin = Winter.getSkin(step.id)
			if skin then
				local equipped = data.equipped :: any
				if equipped[skin.slot] == "" then
					equipped[skin.slot] = step.id
					api.applyStats(player)
				end
				api.notify(player, "MSG_WTRACK_SKIN", nil, skin.key)
			end
		end
		data.winterClaimed = index
	end
	if #steps > 0 then
		api.pushState(player)
		send(player)
	end
end

-- Nagroda za dzisiejsze wejście: gracz odbiera ją przyciskiem w oknie Zadań
local function claimLogin(player: Player, data: Data)
	local today = Progress.dayIndex(os.time())
	local cycleDay, frozen = Progress.claimLogin(data.streak, today)
	if not cycleDay then
		return
	end
	if frozen then
		api.notify(player, "MSG_STREAK_FROZEN", { data.streak.count })
	end
	local amount = math.floor(Progress.LOGIN_REWARDS[cycleDay] * scaleOf(data))
	Ledger.earn(player, data, amount, "TimedReward", "LoginStreak")
	data.stats.bestStreak = math.max(data.stats.bestStreak, data.streak.count)
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
	if Progress.loginReady(data.streak, Progress.dayIndex(now)) then
		local cycleDay = Progress.loginPreview(data.streak, Progress.dayIndex(now))
		api.notify(player, "MSG_LOGIN_READY", { cycleDay })
	end
end

-- Krok wejścia w osobnym xpcall: błąd jednego kroku nie blokuje reszty ani wysłania stanu okien
local function joinStep(player: Player, name: string, step: () -> ())
	local ok, err = (xpcall :: any)(step, debug.traceback)
	if not ok then
		warn(string.format("[ProgressService] join/%s dla %s: %s", name, player.Name, tostring(err)))
	end
end

function ProgressService.join(player: Player)
	local data = api.getData(player)
	if not data then
		return
	end
	joinStep(player, "migrate", function()
		-- Komunikaty o progach księgi, które gracz zdobył przed tą wersją, nie są potrzebne
		if #data.atlasDone == 0 then
			data.atlasDone = Progress.milestones(data.atlas)
		end
		-- Strażnicy okradzeni przed zakładką Strażnicy (bez komunikatu)
		Progress.migrateBestiary(data.bestiary, data.atlas)
	end)
	joinStep(player, "newDay", function()
		newDay(player, data)
	end)
	joinStep(player, "title", function()
		refreshTitle(player, data)
	end)
	joinStep(player, "settings", function()
		applySettings(player, data)
	end)
	-- Progi ścieżki z poprzedniej wizyty, których nagrody nie przyszły (np. wyjście w złym momencie)
	joinStep(player, "tracks", function()
		grantTrack(player, data)
		grantWinterTrack(player, data)
	end)
	if Halloween.active(os.time()) then
		api.notify(player, "MSG_HALLOWEEN_WELCOME")
	elseif Winter.active(os.time()) then
		api.notify(player, "MSG_WINTER_WELCOME")
	end
	send(player, true)
end

function ProgressService.leave(player: Player)
	lastSent[player] = nil
	lastAdvent[player] = nil
	awarding[player] = nil
end

-- Zdarzenie z gry, które może posunąć zadania (kind jak w Progress.QUESTS)
function ProgressService.event(player: Player, kind: string, amount: number?)
	local data = api.getData(player)
	if not data then
		return
	end
	local completed, allDone = Progress.questEvent(data.daily, kind, amount)
	-- Nagroda czeka na odbiór w oknie Zadań (przycisk miga)
	if allDone then
		api.notify(player, "MSG_QUESTS_ALL_READY")
	elseif #completed > 0 then
		api.notify(player, "MSG_QUEST_READY")
	end
	if kind == "steal" then
		data.weekly.steals += amount or 1
	end
	-- Liczniki z całej gry: tytuły i odznaki
	if Titles.EVENT_STAT[kind] then
		Titles.count(data.stats, kind, amount)
		refreshTitle(player, data)
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

-- Zdarzenie ze strażnikiem (kind jak w Progress.guardianEvent: "steal", "escape", "caught").
-- GameService woła je z pościgu (ucieczka, złapanie); kradzież liczy się sama w ProgressService.found.
function ProgressService.guardianEvent(player: Player, guardian: string, kind: string)
	local data = api.getData(player)
	if not data then
		return
	end
	local def = Progress.getGuardian(guardian)
	if def and Progress.guardianEvent(data.bestiary, guardian, kind) then
		api.notify(player, "MSG_BESTIARY_NEW", nil, def.key)
		refreshTitle(player, data) -- „Postrach Strażników” i odznaki za okradzionych strażników
	end
	send(player)
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
		-- Z kuźni ForgeService woła to dopiero po animacji bębna (Config.Forge.revealDelay)
		api.notify(player, if newSpecies then "MSG_ATLAS_NEW_SPECIES" else "MSG_ATLAS_NEW_FORM", nil, species and species.key or nil, {
			variant = item.v,
		})
		if source ~= "forge" then
			ProgressService.event(player, "discover", 1)
		end
		-- Wyjątkowa zdobycz: karta z modelem i przyciskiem „Wystaw w gablocie” (client/FindCard)
		if Showcase.cardWorthy(item) then
			local save = data.showcase
			FindCard:FireClient(player, {
				s = item.s,
				v = item.v,
				x = item.x,
				newSpecies = newSpecies,
				value = Economy.itemValue(item :: any),
				canShow = save ~= nil and Showcase.firstEmpty(save) ~= nil,
			})
		end
		checkMilestones(player, data)
	end
	-- Grzyb strażnika (z legowiska albo ze skarbca) = kradzież, pierwsza odkrywa go w zakładce Strażnicy
	local guardian = Economy.guardianOf(item.s)
	if guardian and source ~= "forge" then
		ProgressService.guardianEvent(player, guardian, "steal")
	end
	-- Najlepsze znalezisko tygodnia (ranking): tylko grzyby znalezione w lesie, nie z kuźni
	if source ~= "forge" then
		local now = os.time()
		Progress.ensureWeek(data, Progress.weekIndex(now))
		local score = Progress.encodeFind(item.s, item.v, Economy.itemValue(item :: any))
		if score > data.weekly.best then
			data.weekly.best = score
		end
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

-- ===== Halloween =====

-- Cukierki z Halloween (sprzedane dynie, zadania). key = komunikat z liczbą i sumą (nil = bez komunikatu)
function ProgressService.addCandy(player: Player, amount: number, key: string?)
	local data = api.getData(player)
	-- Cukierki tylko w czasie eventu, z każdego źródła (ranking zamyka się dokładnie przy końcu)
	if not data or amount <= 0 or not Halloween.active(os.time()) then
		return
	end
	if key then
		api.notify(player, key, { amount, data.stats.candy + amount })
	end
	data.candyBag += amount
	-- Licznik, tytuły z cukierków i odznaka (Titles.EVENT_STAT.candy)
	ProgressService.event(player, "candy", amount)
	grantTrack(player, data)
end

-- ===== Zima =====

-- Płatki śniegu (sprzedane oszronione grzyby, zadania, kalendarz). key = komunikat z liczbą i sumą
-- (nil = bez komunikatu). Tylko w czasie eventu.
function ProgressService.addFlakes(player: Player, amount: number, key: string?)
	local data = api.getData(player)
	if not data or amount <= 0 or not Winter.active(os.time()) then
		return
	end
	if key then
		api.notify(player, key, { amount, data.stats.snowflakes + amount })
	end
	data.flakeBag += amount
	-- Licznik, tytuły z płatków i odznaka (Titles.EVENT_STAT.snowflake)
	ProgressService.event(player, "snowflake", amount)
	grantWinterTrack(player, data)
end

-- Kalendarz adwentowy: otwiera dzisiejsze okienko (raz dziennie, przegapione zostają zamknięte)
local function openAdvent(player: Player)
	local data = api.getData(player)
	local now = os.clock()
	if not data or now - (lastAdvent[player] or 0) < 0.5 then
		return
	end
	lastAdvent[player] = now
	local day = Winter.adventDay(os.time())
	if not day or not Winter.canOpen(data.advent, day) then
		return
	end
	local reward = Winter.ADVENT[day]
	table.insert(data.advent, day)
	local coins = if reward.coins then math.floor(reward.coins * scaleOf(data)) else 0
	if coins > 0 then
		Ledger.earn(player, data, coins, "TimedReward", "Advent")
	end
	if reward.luck then
		grantLuck(data, reward.luck)
	end
	if coins > 0 and reward.flakes then
		api.notify(player, "MSG_ADVENT_GIFT", { day, coins, reward.flakes })
	elseif reward.flakes then
		api.notify(player, "MSG_ADVENT_FLAKES", { day, reward.flakes })
	elseif reward.luck then
		api.notify(player, "MSG_ADVENT_LUCK", { day, math.floor(reward.luck / 60) })
	else
		api.notify(player, "MSG_ADVENT_COINS", { day, coins })
	end
	-- Tytuł za otwarte okienka (Titles.EVENT_STAT.advent), płatki na ścieżkę i do kieszeni
	ProgressService.event(player, "advent", 1)
	if reward.flakes then
		ProgressService.addFlakes(player, reward.flakes)
	end
	api.pushState(player)
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
		table.clear(data.bestiary)
		refreshTitle(player, data)
	elseif action == "bestiaryNext" then
		-- Odkrywa kolejnego strażnika z komunikatem, jakby gracz go właśnie okradł
		for _, def in Progress.GUARDIANS do
			if not Progress.guardianRecord(data.bestiary, def.id).found then
				ProgressService.guardianEvent(player, def.id, "steal")
				break
			end
		end
	elseif action == "bestiaryClear" then
		table.clear(data.bestiary)
	elseif action == "questsDone" then
		for _, state in data.daily.quests do
			local def = Progress.getQuest(state.id)
			if def then
				ProgressService.event(player, def.kind, def.goal)
			end
		end
	elseif action == "candy50" then
		ProgressService.addCandy(player, 50, "MSG_CANDY_SOLD")
	elseif action == "candyReset" then
		data.stats.candy = 0
		data.candyBag = 0
		data.eventClaimed = 0
		table.clear(data.skins)
		data.equipped.lantern = ""
		data.equipped.knife = ""
		api.applyStats(player)
		refreshTitle(player, data)
	elseif string.match(action, "^candySet:%d+:%d+$") then
		-- Testy: ustawia cukierki zebrane i w kieszeni (np. przywrócenie zapisu po teście kotła)
		local total, bag = string.match(action, "^candySet:(%d+):(%d+)$")
		data.stats.candy = tonumber(total) or 0
		data.candyBag = tonumber(bag) or 0
		data.eventClaimed = Halloween.reached(data.stats.candy)
		refreshTitle(player, data)
		api.applyStats(player)
	elseif action == "flakes50" then
		ProgressService.addFlakes(player, 50, "MSG_FLAKES_SOLD")
	elseif action == "winterReset" then
		-- Zima od nowa: płatki, ścieżka, kalendarz i skórki z Zimy (skórki z Halloween zostają)
		data.stats.snowflakes = 0
		data.stats.advent = 0
		data.flakeBag = 0
		data.winterClaimed = 0
		table.clear(data.advent)
		for i = #data.skins, 1, -1 do
			if Winter.getSkin(data.skins[i]) then
				table.remove(data.skins, i)
			end
		end
		for slot, id in data.equipped :: any do
			if Winter.getSkin(id) then
				(data.equipped :: any)[slot] = ""
			end
		end
		api.applyStats(player)
		refreshTitle(player, data)
	elseif string.match(action, "^flakesSet:%d+:%d+$") then
		-- Testy: ustawia płatki zebrane i w kieszeni (np. przywrócenie zapisu po teście choinki)
		local total, bag = string.match(action, "^flakesSet:(%d+):(%d+)$")
		data.stats.snowflakes = tonumber(total) or 0
		data.flakeBag = tonumber(bag) or 0
		data.winterClaimed = Winter.reached(data.stats.snowflakes)
		refreshTitle(player, data)
		api.applyStats(player)
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

-- Odbiór nagrody z okna Zadań: numer zadania, "bonus" (premia za komplet) albo "login" (seria logowań)
local lastClaim: { [Player]: number } = {}
local function onClaim(player: Player, what: unknown)
	local data = api.getData(player)
	if not data then
		return
	end
	local now = os.clock()
	if now - (lastClaim[player] or 0) < 0.25 then
		return
	end
	lastClaim[player] = now
	-- Po północy najpierw nowy dzień (stare zadania i tak przepadają razem z dniem)
	if data.daily.day ~= Progress.dayIndex(os.time()) then
		newDay(player, data)
	end
	local scale = scaleOf(data)
	if typeof(what) == "number" then
		local def = Progress.claimQuest(data.daily, math.floor(what))
		if not def then
			return
		end
		local reward = Progress.questReward(def, scale)
		Ledger.earn(player, data, reward, "TimedReward", "Quest")
		api.notify(player, "MSG_QUEST_DONE", { reward })
		-- Halloween: każde zadanie dnia daje też cukierki
		if Halloween.active(os.time()) then
			ProgressService.addCandy(player, Config.Halloween.questCandy, "MSG_CANDY_QUEST")
		end
		-- Zima: każde zadanie dnia daje też płatki śniegu
		if Winter.active(os.time()) then
			ProgressService.addFlakes(player, Config.Winter.questFlakes, "MSG_FLAKES_QUEST")
		end
	elseif what == "bonus" then
		if not Progress.claimBonus(data.daily) then
			return
		end
		local bonus = math.floor(Progress.DAILY_BONUS.reward * scale)
		Ledger.earn(player, data, bonus, "TimedReward", "QuestBonus")
		grantLuck(data, Progress.DAILY_BONUS.luckSeconds)
		api.notify(player, "MSG_QUESTS_ALL_DONE", { bonus, math.floor(Progress.DAILY_BONUS.luckSeconds / 60) })
	elseif what == "login" then
		if not Progress.loginReady(data.streak, Progress.dayIndex(os.time())) then
			return
		end
		claimLogin(player, data)
		refreshTitle(player, data)
	else
		return
	end
	api.pushState(player)
	send(player)
end

-- Wybór tytułu z okna Tytuły: tylko zdobyty, "" = najlepszy automatycznie, "none" = bez tytułu
local function onSelectTitle(player: Player, id: unknown)
	local data = api.getData(player)
	if not data or typeof(id) ~= "string" then
		return
	end
	if id ~= "" and id ~= Titles.NONE and not Titles.earned(titleContext(data))[id] then
		return
	end
	data.titleChoice = id
	refreshTitle(player, data)
	send(player)
end

function ProgressService.start(serviceApi: Api)
	api = serviceApi
	QuestReroll.OnServerEvent:Connect(onReroll)
	QuestClaim.OnServerEvent:Connect(onClaim)
	AdventOpen.OnServerEvent:Connect(openAdvent)
	Players.PlayerRemoving:Connect(function(player)
		lastClaim[player] = nil
	end)
	SelectTitle.OnServerEvent:Connect(onSelectTitle)
	SaveSettings.OnServerEvent:Connect(function(player: Player, key: unknown, value: unknown)
		local data = api.getData(player)
		if not data then
			return
		end
		local settings = data.settings
		if (key == "music" or key == "sfx") and typeof(value) == "boolean" then
			-- Dawny przełącznik wł./wył.: włączenie bez głośności przywraca pełną
			if key == "music" then
				settings.music = value
				if value and settings.musicVolume <= 0 then
					settings.musicVolume = 1
				end
			else
				settings.sfx = value
				if value and settings.sfxVolume <= 0 then
					settings.sfxVolume = 1
				end
			end
			applySettings(player, data)
		elseif key == "x2Card" and typeof(value) == "boolean" then
			settings.x2Card = value
			applySettings(player, data)
		elseif key == "musicVolume" or key == "sfxVolume" then
			-- Suwak: 0..1 co 5%, śmieci odrzucamy; 0 = wyłączone
			local volume = Progress.normalizeVolume(value)
			if volume then
				if key == "musicVolume" then
					settings.musicVolume = volume
					settings.music = volume > 0
				else
					settings.sfxVolume = volume
					settings.sfx = volume > 0
				end
				applySettings(player, data)
			end
		end
	end)
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

-- Odświeża okna (Halloween: kieszeń z cukierkami, skórki)
function ProgressService.refresh(player: Player)
	send(player)
end

-- Po końcu samouczka (tytuł „Nowy”)
function ProgressService.refreshTitle(player: Player)
	local data = api.getData(player)
	if data then
		refreshTitle(player, data)
	end
end

return ProgressService
