--!strict
-- Tytuły nad głową: pełna lista, warunki zdobycia i wybór gracza (czysta logika, testy w Lune).
-- Tytuł zdobywa się za Grzybopedię (progi stron), za liczniki z całej gry (zebrane, sprzedane,
-- kradzieże, ucieczki, podniesieni kumple, posadzone, seria logowań) i za kilka wyczynów.
-- Gracz wybiera tytuł z listy zdobytych; bez wyboru nosi najlepszy (najwyższa rzadkość).
-- id = klucz tłumaczenia (tak jak dotąd, atrybut AtlasTitle niesie ten klucz).

local Config = require(script.Parent.Config)
local Progress = require(script.Parent.Progress)

local Titles = {}

export type Stats = {
	picked: number,
	sold: number,
	steals: number,
	escapes: number,
	revives: number,
	planted: number,
	deaths: number,
	bestStreak: number,
}

-- Liczniki z całej gry: rodzaj zdarzenia (jak w ProgressService.event) -> pole w Stats
Titles.EVENT_STAT = {
	pick = "picked",
	sell = "sold",
	steal = "steals",
	escape = "escapes",
	revive = "revives",
	plant = "planted",
	death = "deaths",
} :: { [string]: string }

function Titles.emptyStats(): Stats
	return { picked = 0, sold = 0, steals = 0, escapes = 0, revives = 0, planted = 0, deaths = 0, bestStreak = 0 }
end

-- Rzadkości od najsłabszej: kolor napisu nad głową i ramki w oknie (mityczny = tęcza)
Titles.RARITIES = { "common", "rare", "epic", "legendary", "mythic" }
Titles.RARITY_COLOR = {
	common = { 150, 230, 120 },
	rare = { 110, 190, 255 },
	epic = { 196, 126, 255 },
	legendary = { 255, 206, 64 },
	mythic = { 255, 140, 230 },
} :: { [string]: { number } }
local RARITY_RANK: { [string]: number } = {}
for index, rarity in Titles.RARITIES do
	RARITY_RANK[rarity] = index
end

export type TitleDef = {
	id: string,
	rarity: string,
	stat: string?, -- licznik ze Stats i cel
	goal: number?,
	atlas: { page: string, rank: number }?, -- próg strony Grzybopedii
	special: string?, -- "tutorial" | "grandmaster" | "rainbow" | "guardians"
}

export type Context = {
	atlas: { [string]: any },
	bestiary: { [string]: any },
	stats: Stats,
	tutorialDone: boolean,
}

-- Kolejność = kolejność w oknie (w każdej rzadkości od najłatwiejszego)
local LIST: { TitleDef } = {
	{ id = "TITLE_NEW", rarity = "common", special = "tutorial" },
	{ id = "TITLE_PICKER", rarity = "common", stat = "picked", goal = 100 },
	{ id = "TITLE_GARDENER", rarity = "common", stat = "planted", goal = 25 },
	{ id = "TITLE_UNLUCKY", rarity = "common", stat = "deaths", goal = 10 },
	{ id = "TITLE_THIEF", rarity = "rare", stat = "steals", goal = 1 },
	{ id = "TITLE_TRADER", rarity = "rare", stat = "sold", goal = 500 },
	{ id = "TITLE_LIFESAVER", rarity = "rare", stat = "revives", goal = 5 },
	{ id = "TITLE_REGULAR", rarity = "rare", stat = "bestStreak", goal = 7 },
	{ id = "TITLE_FORAGER", rarity = "epic", stat = "picked", goal = 2500 },
	{ id = "TITLE_ELUSIVE", rarity = "epic", stat = "escapes", goal = 10 },
	{ id = "TITLE_RAINBOW_HUNTER", rarity = "epic", special = "rainbow" },
	{ id = "TITLE_GUARDIAN_BANE", rarity = "legendary", special = "guardians" },
	{ id = "TITLE_MAGNATE", rarity = "legendary", stat = "sold", goal = 10000 },
	{ id = "TITLE_VETERAN", rarity = "legendary", stat = "bestStreak", goal = 30 },
	{ id = "TITLE_HARVESTER", rarity = "legendary", stat = "picked", goal = 20000 },
}
-- Tytuły z Grzybopedii: odkrywca (zwykły), tropiciel (rzadki), znawca (epicki), mistrz (legendarny)
local TIER_RARITY = { "common", "rare", "epic", "legendary" }
for index, tier in Progress.TIERS do
	if tier.title then
		for _, page in Progress.PAGES do
			table.insert(LIST, {
				id = tier.title .. string.upper(page),
				rarity = TIER_RARITY[index] or "rare",
				atlas = { page = page, rank = tier.rank },
			})
		end
	end
end
table.insert(LIST, { id = Progress.GRANDMASTER, rarity = "mythic", special = "grandmaster" })
-- W oknie: najpierw według rzadkości, w niej w kolejności z listy
local ORDER: { [string]: number } = {}
for index, def in LIST do
	ORDER[def.id] = index
end
table.sort(LIST, function(a, b)
	if a.rarity ~= b.rarity then
		return RARITY_RANK[a.rarity] < RARITY_RANK[b.rarity]
	end
	return ORDER[a.id] < ORDER[b.id]
end)
Titles.LIST = LIST

local BY_ID: { [string]: TitleDef } = {}
for _, def in LIST do
	BY_ID[def.id] = def
end

function Titles.get(id: string): TitleDef?
	return BY_ID[id]
end

function Titles.rarityRank(rarity: string): number
	return RARITY_RANK[rarity] or 0
end

local function hasRainbow(atlas: { [string]: any }): boolean
	for _, species in Config.Species do
		if Progress.has(atlas, species.id, 3) then
			return true
		end
	end
	return false
end

local function allGuardians(bestiary: { [string]: any }): boolean
	local found, total = Progress.guardiansFound(bestiary)
	return total > 0 and found >= total
end

local function allRainbow(atlas: { [string]: any }): boolean
	for _, page in Progress.PAGES do
		if not Progress.tierDone(atlas, page, 3) then
			return false
		end
	end
	return true
end

-- Postęp do tytułu: (ile, cel). Tytuły „tak/nie” mają cel 1.
function Titles.progress(def: TitleDef, ctx: Context): (number, number)
	if def.stat and def.goal then
		local value = (ctx.stats :: any)[def.stat]
		return math.min(if typeof(value) == "number" then value else 0, def.goal), def.goal
	elseif def.atlas then
		return Progress.tierProgress(ctx.atlas, def.atlas.page, def.atlas.rank)
	elseif def.special == "tutorial" then
		return if ctx.tutorialDone then 1 else 0, 1
	elseif def.special == "rainbow" then
		return if hasRainbow(ctx.atlas) then 1 else 0, 1
	elseif def.special == "guardians" then
		return Progress.guardiansFound(ctx.bestiary)
	elseif def.special == "grandmaster" then
		local done = 0
		for _, page in Progress.PAGES do
			if Progress.tierDone(ctx.atlas, page, 3) then
				done += 1
			end
		end
		return done, #Progress.PAGES
	end
	return 0, 1
end

function Titles.isEarned(def: TitleDef, ctx: Context): boolean
	if def.atlas then
		return Progress.tierDone(ctx.atlas, def.atlas.page, def.atlas.rank)
	elseif def.special == "guardians" then
		return allGuardians(ctx.bestiary)
	elseif def.special == "grandmaster" then
		return allRainbow(ctx.atlas)
	end
	local n, goal = Titles.progress(def, ctx)
	return goal > 0 and n >= goal
end

-- Wszystkie zdobyte tytuły (id -> true)
function Titles.earned(ctx: Context): { [string]: boolean }
	local result: { [string]: boolean } = {}
	for _, def in LIST do
		if Titles.isEarned(def, ctx) then
			result[def.id] = true
		end
	end
	return result
end

-- Najlepszy zdobyty: najwyższa rzadkość, przy remisie dalszy na liście (trudniejszy)
function Titles.best(earned: { [string]: boolean }): string?
	local best: TitleDef? = nil
	for _, def in LIST do
		if earned[def.id] then
			if not best or RARITY_RANK[def.rarity] >= RARITY_RANK[best.rarity] then
				best = def
			end
		end
	end
	return if best then best.id else nil
end

Titles.NONE = "none" -- wybór „bez tytułu”

-- Tytuł do pokazania: wybrany (jeśli wciąż zdobyty), inaczej najlepszy, inaczej nic ("")
function Titles.resolve(choice: string, earned: { [string]: boolean }): string
	if choice == Titles.NONE then
		return ""
	elseif choice ~= "" and earned[choice] then
		return choice
	end
	return Titles.best(earned) or ""
end

-- Dolicza zdarzenie do liczników (nieznane rodzaje ignoruje)
function Titles.count(stats: Stats, kind: string, amount: number?)
	local field = Titles.EVENT_STAT[kind]
	if field then
		local s = stats :: any
		s[field] = (s[field] or 0) + math.max(0, math.floor(amount or 1))
	end
end

-- Nowo zdobyte od ostatniego razu (do komunikatu „Nowy tytuł”); dopisuje je do seen
function Titles.newlyEarned(earned: { [string]: boolean }, seen: { string }): { string }
	local fresh = {}
	for _, def in LIST do
		if earned[def.id] and not table.find(seen, def.id) then
			table.insert(seen, def.id)
			table.insert(fresh, def.id)
		end
	end
	return fresh
end

return Titles
