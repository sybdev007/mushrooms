--!strict
-- Prosty zapis postępu na DataStore.
-- Na prototyp wystarczy. Przed publikacją podmieńcie to na ProfileStore
-- (blokada sesji chroni przed duplikowaniem danych przy szybkim przeskakiwaniu serwerów).

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Progress = require(ReplicatedStorage.Shared.Progress)
local Titles = require(ReplicatedStorage.Shared.Titles)

export type Data = {
	version: number,
	coins: number,
	upgrades: { [string]: number },
	atlas: { [string]: number }, -- Grzybopedia: gatunek -> maska odkrytych wariantów (Progress)
	atlasDone: { string }, -- progi księgi, o których gracz już dostał komunikat ("forest:2")
	bestiary: { [string]: Progress.GuardianRecord }, -- zakładka Strażnicy: odkryci strażnicy i liczniki
	daily: Progress.Daily, -- dzisiejsze zadania
	streak: Progress.Streak, -- seria logowań
	weekly: Progress.Weekly, -- wyniki tego tygodnia do rankingów
	stats: Titles.Stats, -- liczniki z całej gry (tytuły, odznaki)
	titleChoice: string, -- wybrany tytuł ("" = najlepszy automatycznie, "none" = bez tytułu)
	titles: { string }?, -- tytuły, o których gracz dostał już komunikat (nil = stary zapis, bez komunikatów)
	badges: { string }, -- przyznane odznaki Robloxa (id z Config.Badges)
	settings: { music: boolean, sfx: boolean }, -- muzyka i dźwięki włączone
	basket: { Economy.BasketItem },
	planted: { Economy.PlantItem }, -- grzyby na grządkach w ogródku
	pot: number, -- monety z grządek czekające w skrzyni (z ułamkiem)
	incomeAt: number, -- os.time() ostatniego naliczenia dochodu (do dochodu offline)
	pity: number, -- odrosty od ostatniego Złota (albo lepszego), do gwarancji mutacji
	caveUnlocked: boolean, -- portal do jaskini raz otwarty zostaje otwarty
	swampUnlocked: boolean, -- to samo dla bagien
	luckUntil: number, -- os.time(), do kiedy działa mikstura szczęścia
	receipts: { string }, -- ostatnie obsłużone zakupy (Roblox może przysłać ten sam drugi raz)
	tutorial: number, -- krok samouczka (0 = cutscenka na start, Config.Tutorial.done = skończony)
}

local STORE_NAME = "LanternForager_Prototype_v1"
local DATA_VERSION = 4
local MAX_ATTEMPTS = 3

local DataService = {}

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[DataService] DataStore niedostępny:", result)
	end
end

local function keyFor(player: Player): string
	return "player_" .. player.UserId
end

function DataService.defaultData(): Data
	local upgrades = {}
	for id in Config.Upgrades do
		upgrades[id] = 0
	end
	return {
		version = DATA_VERSION,
		coins = Config.StartingCoins or 0,
		upgrades = upgrades,
		atlas = {},
		atlasDone = {},
		bestiary = {},
		daily = { day = -1, quests = {}, rerolled = false, bonusDone = false },
		streak = { day = -1, count = 0 },
		weekly = { week = -1, steals = 0, best = 0 },
		stats = Titles.emptyStats(),
		titleChoice = "",
		titles = {},
		badges = {},
		settings = { music = true, sfx = true },
		basket = {},
		planted = {},
		pot = 0,
		incomeAt = 0,
		pity = 0,
		caveUnlocked = false,
		swampUnlocked = false,
		luckUntil = 0,
		receipts = {},
		tutorial = 0,
	}
end

-- Mutacje z zapisu: tylko znane warianty i cechy, bez powtórzeń.
-- Zapisy sprzed wersji 3 miały g = true dla złotych grzybów: zamieniamy na wariant „gold”.
local function readMutations(item: any): (string?, { string }?)
	local variant: string? = nil
	if typeof(item.v) == "string" and Economy.getVariant(item.v) then
		variant = item.v
	elseif item.g == true then
		variant = "gold"
	end
	local tags: { string }? = nil
	if typeof(item.x) == "table" then
		local seen = {}
		for _, id in item.x do
			if typeof(id) == "string" and Economy.getTag(id) and not seen[id] then
				seen[id] = true
				tags = tags or {}
				table.insert(tags :: { string }, id)
			end
		end
	end
	return variant, tags
end

-- Uzupełnia brakujące pola i odrzuca śmieci, żeby stary zapis nie wywalił gry
local function reconcile(raw: any): Data
	local data = DataService.defaultData()
	if typeof(raw) ~= "table" then
		return data
	end
	-- Samouczek: nowy gracz zaczyna od cutscenki, a stare zapisy (sprzed samouczka) mają go za sobą
	if typeof(raw.tutorial) == "number" then
		data.tutorial = math.clamp(math.floor(raw.tutorial), 0, Config.Tutorial.done)
	else
		data.tutorial = Config.Tutorial.done
	end
	if typeof(raw.coins) == "number" and raw.coins >= 0 then
		data.coins = math.floor(raw.coins)
	end
	if typeof(raw.upgrades) == "table" then
		for id, def in Config.Upgrades do
			local level = raw.upgrades[id]
			if typeof(level) == "number" then
				data.upgrades[id] = math.clamp(math.floor(level), 0, def.maxLevel)
			end
		end
	end
	if typeof(raw.atlas) == "table" then
		for id, found in raw.atlas do
			if typeof(id) == "string" and Economy.getSpecies(id) then
				-- Stare zapisy: true = znaleziony (zwykły); nowe: maska bitów 1..15
				local mask = if found == true then 1 elseif typeof(found) == "number" then math.clamp(math.floor(found), 0, 15) else 0
				if mask > 0 then
					data.atlas[id] = mask
				end
			end
		end
	end
	if typeof(raw.atlasDone) == "table" then
		for _, id in raw.atlasDone do
			if typeof(id) == "string" and #data.atlasDone < 64 then
				table.insert(data.atlasDone, id)
			end
		end
	end
	if typeof(raw.bestiary) == "table" then
		local function count(value: any): number
			return if typeof(value) == "number" then math.max(0, math.floor(value)) else 0
		end
		for _, def in Progress.GUARDIANS do
			local entry = raw.bestiary[def.id]
			if typeof(entry) == "table" then
				data.bestiary[def.id] = {
					found = entry.found == true,
					stolen = count(entry.stolen),
					escaped = count(entry.escaped),
					caught = count(entry.caught),
				}
			end
		end
	end
	local daily = raw.daily
	if typeof(daily) == "table" and typeof(daily.day) == "number" and typeof(daily.quests) == "table" then
		local quests = {}
		for _, q in daily.quests do
			if typeof(q) == "table" and typeof(q.id) == "string" and Progress.getQuest(q.id) and #quests < Progress.QUESTS_PER_DAY then
				local goal = (Progress.getQuest(q.id) :: Progress.QuestDef).goal
				local n = if typeof(q.n) == "number" then math.clamp(math.floor(q.n), 0, goal) else 0
				table.insert(quests, { id = q.id, n = n, done = q.done == true or n >= goal })
			end
		end
		data.daily = { day = math.floor(daily.day), quests = quests, rerolled = daily.rerolled == true, bonusDone = daily.bonusDone == true }
	end
	local streak = raw.streak
	if typeof(streak) == "table" and typeof(streak.day) == "number" and typeof(streak.count) == "number" then
		data.streak = { day = math.floor(streak.day), count = math.max(0, math.floor(streak.count)) }
	end
	local weekly = raw.weekly
	if typeof(weekly) == "table" and typeof(weekly.week) == "number" then
		data.weekly = {
			week = math.floor(weekly.week),
			steals = if typeof(weekly.steals) == "number" then math.max(0, math.floor(weekly.steals)) else 0,
			best = if typeof(weekly.best) == "number" then math.max(0, math.floor(weekly.best)) else 0,
		}
	end
	-- Liczniki z całej gry. Zapisy sprzed tytułów: kradzieże, ucieczki i złapania z zakładki Strażnicy
	if typeof(raw.stats) == "table" then
		local stats = data.stats :: any
		for key in stats do
			local value = raw.stats[key]
			if typeof(value) == "number" then
				stats[key] = math.max(0, math.floor(value))
			end
		end
	else
		for _, record in data.bestiary do
			data.stats.steals += record.stolen
			data.stats.escapes += record.escaped
			data.stats.deaths += record.caught
		end
	end
	data.stats.bestStreak = math.max(data.stats.bestStreak, data.streak.count)
	if typeof(raw.titleChoice) == "string" and (raw.titleChoice == "none" or Titles.get(raw.titleChoice)) then
		data.titleChoice = raw.titleChoice
	end
	if typeof(raw.titles) == "table" then
		local seen = {}
		for _, id in raw.titles do
			if typeof(id) == "string" and Titles.get(id) and not table.find(seen, id) then
				table.insert(seen, id)
			end
		end
		data.titles = seen
	else
		data.titles = nil
	end
	if typeof(raw.badges) == "table" then
		for _, id in raw.badges do
			if typeof(id) == "string" and #data.badges < 64 and not table.find(data.badges, id) then
				table.insert(data.badges, id)
			end
		end
	end
	if typeof(raw.settings) == "table" then
		data.settings.music = raw.settings.music ~= false
		data.settings.sfx = raw.settings.sfx ~= false
	end
	if typeof(raw.basket) == "table" then
		for _, item in raw.basket do
			if typeof(item) == "table" and typeof(item.s) == "string" and Economy.getSpecies(item.s) then
				-- d: mnożnik suszenia z dawnej suszarni (najwyżej 2x)
				local dried = if typeof(item.d) == "number" then math.clamp(item.d, 1, 2) else nil
				local variant, tags = readMutations(item)
				table.insert(data.basket, { s = item.s, v = variant, x = tags, d = dried })
			end
		end
	end
	local now = os.time()
	if typeof(raw.planted) == "table" then
		for _, item in raw.planted do
			if #data.planted >= Config.Garden.maxBeds then
				break
			end
			if typeof(item) == "table" and typeof(item.s) == "string" and Economy.getSpecies(item.s) and typeof(item.t) == "number" then
				local variant, tags = readMutations(item)
				local dried = if typeof(item.d) == "number" then math.clamp(item.d, 1, 2) else nil
				table.insert(data.planted, { s = item.s, v = variant, x = tags, d = dried, t = math.min(math.floor(item.t), now) })
			end
		end
	end
	-- Zapisy sprzed wersji 4 miały suszarnię: grzyby z niej sadzimy na grządkach
	-- (nadmiar ponad odblokowane grządki GardenService zamieni na monety w skrzyni).
	-- Suszenie się liczy: mnożnik zostaje zapisany w grzybie.
	if typeof(raw.drying) == "table" then
		for _, item in raw.drying do
			if #data.planted >= Config.Garden.maxBeds then
				break
			end
			if typeof(item) == "table" and typeof(item.s) == "string" and Economy.getSpecies(item.s) and typeof(item.t) == "number" then
				local variant, tags = readMutations(item)
				local dried = 1 + math.clamp((now - item.t) / 600, 0, 1)
				table.insert(data.planted, { s = item.s, v = variant, x = tags, d = dried, t = now })
			end
		end
	end
	if typeof(raw.pot) == "number" and raw.pot >= 0 then
		data.pot = raw.pot
	end
	if typeof(raw.incomeAt) == "number" then
		data.incomeAt = math.clamp(math.floor(raw.incomeAt), 0, now)
	end
	if typeof(raw.pity) == "number" then
		data.pity = math.clamp(math.floor(raw.pity), 0, Config.PityRolls)
	end
	data.caveUnlocked = raw.caveUnlocked == true
	data.swampUnlocked = raw.swampUnlocked == true
	if typeof(raw.luckUntil) == "number" then
		data.luckUntil = math.floor(raw.luckUntil)
	end
	if typeof(raw.receipts) == "table" then
		for _, id in raw.receipts do
			if typeof(id) == "string" and #data.receipts < 50 then
				table.insert(data.receipts, id)
			end
		end
	end
	return data
end

-- Zwraca dane i informację, czy wolno je potem zapisać.
-- Jeśli wczytanie się nie udało, NIE zapisujemy, żeby nie nadpisać prawdziwego postępu pustym.
function DataService.load(player: Player): (Data, boolean)
	local activeStore = store
	if not activeStore then
		return DataService.defaultData(), false
	end
	for attempt = 1, MAX_ATTEMPTS do
		local ok, result = pcall(function()
			return activeStore:GetAsync(keyFor(player))
		end)
		if ok then
			return reconcile(result), true
		end
		warn(string.format("[DataService] Wczytanie %s nieudane (próba %d): %s", player.Name, attempt, tostring(result)))
		-- Brak dostępu do API w Studio nie minie od ponawiania, a gracz czekałby kilka sekund.
		-- Roblox zgłasza go raz jako 403, raz jako 502 z tym samym opisem.
		local message = tostring(result)
		if string.find(message, "403", 1, true) or string.find(message, "Studio access to APIs is not allowed", 1, true) then
			break
		end
		task.wait(attempt)
	end
	return DataService.defaultData(), false
end

function DataService.save(player: Player, data: Data): boolean
	local activeStore = store
	if not activeStore then
		return false
	end
	for attempt = 1, MAX_ATTEMPTS do
		local ok, err = pcall(function()
			activeStore:UpdateAsync(keyFor(player), function()
				return data
			end)
		end)
		if ok then
			return true
		end
		warn(string.format("[DataService] Zapis %s nieudany (próba %d): %s", player.Name, attempt, tostring(err)))
		task.wait(attempt)
	end
	return false
end

return DataService
