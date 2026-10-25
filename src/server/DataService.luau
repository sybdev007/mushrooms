--!strict
-- Prosty zapis postępu na DataStore.
-- Na prototyp wystarczy. Przed publikacją podmieńcie to na ProfileStore
-- (blokada sesji chroni przed duplikowaniem danych przy szybkim przeskakiwaniu serwerów).

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)

export type Data = {
	version: number,
	coins: number,
	upgrades: { [string]: number },
	atlas: { [string]: boolean }, -- odkryte gatunki (pod przyszły Atlas grzybów)
	basket: { Economy.BasketItem },
	drying: { Economy.DryingItem }, -- grzyby na suszarni (schną także offline)
	pity: number, -- odrosty od ostatniego Złota (albo lepszego), do gwarancji mutacji
}

local STORE_NAME = "LanternForager_Prototype_v1"
local DATA_VERSION = 3
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
		basket = {},
		drying = {},
		pity = 0,
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
			if typeof(id) == "string" and found == true and Economy.getSpecies(id) then
				data.atlas[id] = true
			end
		end
	end
	if typeof(raw.basket) == "table" then
		for _, item in raw.basket do
			if typeof(item) == "table" and typeof(item.s) == "string" and Economy.getSpecies(item.s) then
				-- d: mnożnik suszenia ukradzionego grzyba, w granicach tego, co daje suszarnia
				local dried = if typeof(item.d) == "number" then math.clamp(item.d, 1, 1 + Config.Drying.bonus) else nil
				local variant, tags = readMutations(item)
				table.insert(data.basket, { s = item.s, v = variant, x = tags, d = dried })
			end
		end
	end
	if typeof(raw.drying) == "table" then
		local now = os.time()
		for _, item in raw.drying do
			if #data.drying >= Config.Drying.slots then
				break
			end
			if typeof(item) == "table" and typeof(item.s) == "string" and Economy.getSpecies(item.s) and typeof(item.t) == "number" then
				local variant, tags = readMutations(item)
				table.insert(data.drying, { s = item.s, v = variant, x = tags, t = math.min(math.floor(item.t), now) })
			end
		end
	end
	if typeof(raw.pity) == "number" then
		data.pity = math.clamp(math.floor(raw.pity), 0, Config.PityRolls)
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
