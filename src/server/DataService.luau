--!strict
-- Zapis postępu przez ProfileStore (Packages/ProfileStore, MadStudio, licencja Apache 2.0).
-- Blokada sesji: dane gracza są otwarte tylko na jednym serwerze naraz, więc szybkie skakanie
-- między serwerami nie zduplikuje ani nie nadpisze postępu. Zapis co kilka minut i przy wyjściu.
-- Stare zapisy (zwykły DataStore z prototypu) przenoszą się same przy pierwszym wejściu.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Progress = require(ReplicatedStorage.Shared.Progress)
local Titles = require(ReplicatedStorage.Shared.Titles)
local Social = require(ReplicatedStorage.Shared.Social)

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
	invited: { number }, -- UserId graczy, którzy weszli z zaproszenia tego gracza (już zaliczeni, Social)
	-- muzyka i dźwięki włączone oraz głośność z suwaków (0..1); wyłączone = głośność 0
	settings: { music: boolean, sfx: boolean, musicVolume: number, sfxVolume: number },
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
	eventClaimed: number, -- Halloween: ile progów ścieżki nagród gracz już dostał (cukierki są w stats.candy)
	candyBag: number, -- Halloween: cukierki w kieszeni do wydania w kotle (stats.candy = zebrane łącznie)
	skins: { string }, -- skórki z kotła (te ze ścieżki nagród liczą się z cukierków)
	equipped: { lantern: string, knife: string }, -- założone skórki ("" = zwykła latarnia / nożyk)
	eventGoals: { day: number, seconds: number }, -- Halloween: sekundy mikstury z celów serwera dziś (limit dzienny)
	forest: Forest?, -- las gracza z ostatniej sesji (szybki powrót nie losuje lasu od nowa)
}

-- Las gracza: g = pokolenie lasu (numer świtu, Cycle), s = miejsce -> grzyb i kiedy jest gotowy (os.time)
export type ForestSpot = { s: string, v: string?, x: { string }?, t: number }
export type Forest = { g: number, s: { [string]: ForestSpot } }

local LEGACY_STORE_NAME = "LanternForager_Prototype_v1" -- stary zapis bez blokady sesji (tylko do przeniesienia)
local PROFILE_STORE_NAME = "LanternForager_Profiles_v1"
local DATA_VERSION = 4
local MAX_ATTEMPTS = 3

local DataService = {}

local ProfileStore = require(script.Parent:WaitForChild("Packages"):WaitForChild("ProfileStore")) :: any
local profileStore = ProfileStore.New(PROFILE_STORE_NAME, {})
local profiles: { [Player]: any } = {}
-- Ostatni potwierdzony zapis profilu (ProfileStore.LastSavedData) i kto chce o nim wiedzieć.
-- Ranking cukierków publikuje tylko to, co już na pewno leży w profilu (awaria nie zostawi w rankingu
-- wyniku, którego gracz nie ma).
local confirmed: { [Player]: any } = {}
local savedListeners: { (Player, any) -> () } = {}

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(LEGACY_STORE_NAME)
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
		invited = {},
		settings = { music = true, sfx = true, musicVolume = 1, sfxVolume = 1 },
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
		eventClaimed = 0,
		candyBag = 0,
		skins = {},
		equipped = { lantern = "", knife = "" },
		eventGoals = { day = -1, seconds = 0 },
		forest = nil,
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

-- Skończona liczba (odrzuca NaN i ±nieskończoność, które przechodzą typeof == "number")
local function finite(x: any): boolean
	return typeof(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end
DataService.finite = finite

-- Najdłuższy sensowny czas oczekiwania na odrost zapisanego grzyba (z zapasem na mnożniki nocy)
local MAX_SPOT_WAIT = 3600

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
	if typeof(raw.invited) == "table" then
		for _, id in raw.invited do
			if finite(id) and id > 0 and id == math.floor(id) and #data.invited < Social.MAX_INVITED and not table.find(data.invited, id) then
				table.insert(data.invited, id)
			end
		end
	end
	if typeof(raw.settings) == "table" then
		data.settings.music = raw.settings.music ~= false
		data.settings.sfx = raw.settings.sfx ~= false
		data.settings.musicVolume = Progress.normalizeVolume(raw.settings.musicVolume) or 1
		data.settings.sfxVolume = Progress.normalizeVolume(raw.settings.sfxVolume) or 1
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
	if finite(raw.luckUntil) then
		data.luckUntil = math.floor(raw.luckUntil)
	end
	if typeof(raw.eventClaimed) == "number" then
		data.eventClaimed = math.clamp(math.floor(raw.eventClaimed), 0, #Config.Halloween.track)
	end
	-- Kieszeń z cukierkami: zapisy sprzed kotła mają tyle, ile zebrały
	if typeof(raw.candyBag) == "number" then
		data.candyBag = math.max(0, math.floor(raw.candyBag))
	else
		data.candyBag = data.stats.candy
	end
	if typeof(raw.skins) == "table" then
		for _, id in raw.skins do
			if typeof(id) == "string" and Config.Halloween.skins[id] and not table.find(data.skins, id) then
				table.insert(data.skins, id)
			end
		end
	end
	if typeof(raw.equipped) == "table" then
		for slot in data.equipped do
			local id = raw.equipped[slot]
			local def = if typeof(id) == "string" then Config.Halloween.skins[id] else nil
			if def and def.slot == slot then
				(data.equipped :: any)[slot] = id
			end
		end
	end
	local goals = raw.eventGoals
	-- Dzień w rozsądnym zakresie (do jutra wg UTC), zużyty czas 0..dzienny limit
	if typeof(goals) == "table" and finite(goals.day) and finite(goals.seconds) then
		local day = math.floor(goals.day)
		if day >= 0 and day <= Progress.dayIndex(now) + 1 then
			data.eventGoals = { day = day, seconds = math.clamp(math.floor(goals.seconds), 0, Config.Halloween.goal.maxPerDay) }
		end
	end
	-- Las z ostatniej sesji: tylko znane gatunki, warianty i cechy (resztę las wylosuje od nowa)
	local forest = raw.forest
	if typeof(forest) == "table" and finite(forest.g) and forest.g >= 0 and typeof(forest.s) == "table" then
		local spots: { [string]: ForestSpot } = {}
		local count = 0
		for id, entry in forest.s do
			if count >= 600 then
				break
			end
			if typeof(id) == "string" and #id <= 64 and typeof(entry) == "table" and typeof(entry.s) == "string" and Economy.getSpecies(entry.s) and finite(entry.t) then
				local variant, tags = readMutations(entry)
				-- Za odległy termin przycinamy do najdłuższego czekania (nie dajemy darmowego odrostu)
				spots[id] = { s = entry.s, v = variant, x = tags, t = math.min(math.floor(entry.t), now + MAX_SPOT_WAIT) }
				count += 1
			end
		end
		data.forest = { g = math.floor(forest.g), s = spots }
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

-- Stary zapis z prototypu (zwykły DataStore). nil = gracz nie miał zapisu; error = nie udało się odczytać.
local function loadLegacy(player: Player): any
	local activeStore = store
	if not activeStore then
		return nil
	end
	for attempt = 1, MAX_ATTEMPTS do
		local ok, result = pcall(function()
			return activeStore:GetAsync(keyFor(player))
		end)
		if ok then
			return result
		end
		warn(string.format("[DataService] Odczyt starego zapisu %s nieudany (próba %d): %s", player.Name, attempt, tostring(result)))
		local message = tostring(result)
		if string.find(message, "403", 1, true) or string.find(message, "Studio access to APIs is not allowed", 1, true) then
			break
		end
		task.wait(attempt)
	end
	error("legacy load failed")
end

-- Zwraca dane i informację, czy wolno je potem zapisać.
-- Jeśli sesji nie udało się otworzyć, NIE zapisujemy, żeby nie nadpisać prawdziwego postępu pustym.
function DataService.load(player: Player): (Data, boolean)
	local ok, profile = pcall(function()
		return profileStore:StartSessionAsync(keyFor(player), {
			Cancel = function()
				return player.Parent ~= Players -- wyszedł, zanim dane się otworzyły
			end,
		})
	end)
	if not ok or not profile then
		if not ok then
			warn("[DataService] Nie udało się otworzyć danych", player.Name, profile)
		end
		return DataService.defaultData(), false
	end
	profile:AddUserId(player.UserId) -- RODO / prośby o usunięcie danych

	local raw: any = profile.Data
	if typeof(raw) ~= "table" or raw.version == nil then
		-- Nowy profil: przenosimy stary zapis z prototypu (jeśli był)
		local legacyOk, legacy = pcall(loadLegacy, player)
		if not legacyOk then
			-- Nie wiemy, czy gracz miał postęp: nie zakładamy pustego profilu
			profile:EndSession()
			return DataService.defaultData(), false
		end
		raw = legacy
	end
	local data = reconcile(raw)
	profile.Data = data

	if player.Parent ~= Players then
		profile:EndSession()
		return data, false
	end
	-- Dane otwarte na innym serwerze (np. gracz wszedł drugi raz): ten serwer już ich nie zapisze
	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		if player.Parent == Players then
			player:Kick("Twoje dane zostały otwarte na innym serwerze. Wejdź do gry ponownie. / Your data was opened on another server. Please rejoin.")
		end
	end)
	confirmed[player] = profile.LastSavedData
	profile.OnAfterSave:Connect(function(lastSaved: any)
		confirmed[player] = lastSaved
		for _, listener in savedListeners do
			task.spawn(listener, player, lastSaved)
		end
		if not profile:IsActive() then
			confirmed[player] = nil -- ostatni zapis po wyjściu
		end
	end)
	profiles[player] = profile
	return data, true
end

-- Cukierki zebrane łącznie w danym zapisie profilu (0, gdy brak albo śmieci)
function DataService.candyOf(saved: any): number
	local stats = if typeof(saved) == "table" then saved.stats else nil
	local candy = if typeof(stats) == "table" then stats.candy else nil
	return if finite(candy) and candy > 0 then math.floor(candy) else 0
end

-- Cukierki według ostatniego potwierdzonego zapisu profilu
function DataService.confirmedCandy(player: Player): number
	return DataService.candyOf(confirmed[player])
end

-- Wywoływane po każdym udanym zapisie profilu (też ostatnim, po wyjściu gracza)
function DataService.onSaved(listener: (Player, any) -> ())
	table.insert(savedListeners, listener)
end

-- Zapis od razu (zakup, wyjście); poza tym ProfileStore zapisuje sam co kilka minut
function DataService.save(player: Player, data: Data): boolean
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return false
	end
	profile.Data = data
	profile:Save()
	return true
end

-- Gracz wyszedł: ostatni zapis i zwolnienie blokady sesji
function DataService.release(player: Player, data: Data)
	local profile = profiles[player]
	profiles[player] = nil
	if profile and profile:IsActive() then
		profile.Data = data
		profile:EndSession()
	end
end

return DataService
