--!strict
-- Kuźnia Grzybów (Moździerz Zielarki): wspólna logika serwera i klienta, bez API Robloxa (testy w Lune).
-- Klient liczy z tego podgląd w oknie, serwer to samo sprawdza jeszcze raz i losuje wynik.
-- Zasady (Config.Forge): dowolne 3 grzyby z koszyka, mała opłata, bęben losuje skuchę / zwykły / szczęście.
--   skucha: losowy z wrzuconych, bez cech, z najsłabszym wariantem z trzech;
--   zwykły: losowy z wrzuconych (z jego wariantem) ze wszystkimi cechami trzech grzybów;
--   szczęście: jak zwykły, ale wariant o rangę wyżej.
-- Gdy trzy grzyby to ukryty przepis albo trójka strażników, zwykły i szczęście dają gatunek z kuźni
-- (wariant = najsłabszy z trzech, w szczęściu o rangę wyżej). Skucha zawsze działa tak samo.

local Config = require(script.Parent.Config)
local Economy = require(script.Parent.Economy)

local Forge = {}

Forge.SLOTS = 3

export type Item = { s: string, v: string?, x: { string }?, d: number? }
export type Access = { swampUnlocked: boolean?, mountainUnlocked: boolean?, jagaEscapes: number? }
export type Outcome = "bust" | "normal" | "lucky"
-- Co pasuje do trzech grzybów: gatunek wyniku i rodzaj ("recipe" | "mythic" | "secret")
export type Match = { id: string, kind: string }

export type Preview = {
	fee: number,
	inputValue: number, -- ile byłyby warte 3 grzyby przy sprzedaży (bez premii)
	bust: number, -- szansa na skuchę
	normal: number,
	lucky: number,
	minRank: number, -- najsłabszy wariant z trzech
	tags: { string }, -- połączone cechy (posortowane, bez powtórzeń)
	match: Match?,
}

local recipeById: { [string]: Config.ForgeRecipe } = {}
for _, recipe in Config.Forge.recipes do
	recipeById[recipe.id] = recipe
end
local specialById: { [string]: Config.ForgeSpecial } = {}
for _, special in Config.Forge.specials do
	specialById[special.id] = special
end

function Forge.recipe(id: unknown): Config.ForgeRecipe?
	return if typeof(id) == "string" then recipeById[id] else nil
end

function Forge.special(id: unknown): Config.ForgeSpecial?
	return if typeof(id) == "string" then specialById[id] else nil
end

-- Czy gracz ma już dostęp do ukrytego przepisu. Zwraca też klucz tekstu z powodem, gdy nie.
function Forge.unlocked(recipe: Config.ForgeRecipe, access: Access): (boolean, string?)
	if recipe.world == "mountain" and access.mountainUnlocked ~= true then
		return false, "FORGE_NEED_MOUNTAIN"
	end
	if access.swampUnlocked ~= true then
		return false, "FORGE_NEED_SWAMP"
	end
	if recipe.jaga and (access.jagaEscapes or 0) < 1 then
		return false, "FORGE_NEED_JAGA"
	end
	return true, nil
end

-- Czy grzyb można wrzucić do moździerza. Zwraca klucz tekstu z powodem, gdy nie.
function Forge.eligible(item: Item?): (boolean, string?)
	if not item or not Economy.getSpecies(item.s) then
		return false, "FORGE_WRONG_INPUT"
	end
	if Economy.isForgeOnly(item.s) then
		return false, "FORGE_NO_FORGE_ITEM"
	end
	if item.d and item.d ~= 1 then
		return false, "FORGE_NO_DRIED"
	end
	for _, tag in (item.x or {}) :: { string } do
		-- Grzyby z eventów (dyniowe, Config.EventTags: strefa 0) zostają w kolekcji
		local def = Economy.getTag(tag)
		if not def or def.zone == 0 then
			return false, "FORGE_NO_EVENT"
		end
	end
	return true, nil
end

local function hasTag(item: Item, tag: string): boolean
	return table.find((item.x or {}) :: { string }, tag) ~= nil
end

-- Wszystkie kolejności trzech grzybów (przepis nie zależy od kolejności wrzucenia)
local PERMS = { { 1, 2, 3 }, { 1, 3, 2 }, { 2, 1, 3 }, { 2, 3, 1 }, { 3, 1, 2 }, { 3, 2, 1 } }

local function recipeFits(recipe: Config.ForgeRecipe, items: { Item }): boolean
	for _, perm in PERMS do
		local ok = true
		for slot, input in recipe.inputs do
			local item = items[perm[slot]]
			if item.s ~= input.s or (input.tag ~= nil and not hasTag(item, input.tag)) then
				ok = false
				break
			end
		end
		if ok then
			return true
		end
	end
	return false
end

local function specialFits(special: Config.ForgeSpecial, items: { Item }): boolean
	for _, item in items do
		if Economy.variantRank(item.v) < special.minRank then
			return false
		end
	end
	for _, set in special.sets do
		local used: { [number]: boolean } = {}
		local ok = true
		for _, item in items do
			local at = table.find(set, item.s)
			if not at or used[at] then
				ok = false
				break
			end
			used[at] = true
		end
		if ok then
			return true
		end
	end
	return false
end

-- Ukryty przepis albo trójka strażników pasująca do trzech grzybów (nil = zwykłe losowanie).
-- Przepis, do którego gracz nie ma jeszcze dostępu, nie działa (wtedy zwykłe losowanie).
function Forge.match(items: { Item }, access: Access): Match?
	if #items ~= Forge.SLOTS then
		return nil
	end
	for _, special in Config.Forge.specials do
		if specialFits(special, items) then
			local species = Economy.getSpecies(special.id)
			return { id = special.id, kind = if species and species.class then species.class else "mythic" }
		end
	end
	for _, recipe in Config.Forge.recipes do
		if Forge.unlocked(recipe, access) and recipeFits(recipe, items) then
			return { id = recipe.id, kind = "recipe" }
		end
	end
	return nil
end

-- Połączone cechy trzech grzybów
function Forge.unionTags(items: { Item }): { string }
	local tags = {}
	for _, item in items do
		for _, tag in (item.x or {}) :: { string } do
			if not table.find(tags, tag) then
				table.insert(tags, tag)
			end
		end
	end
	table.sort(tags)
	return tags
end

function Forge.fee(inputValue: number): number
	return math.max(Config.Forge.minFee, math.floor(inputValue * Config.Forge.feeShare + 0.5))
end

-- Podgląd połączenia trzech grzybów. nil + klucz powodu, gdy się nie da.
function Forge.preview(items: { Item }, access: Access): (Preview?, string?)
	if #items ~= Forge.SLOTS then
		return nil, "FORGE_NEED_ITEMS"
	end
	local inputValue = 0
	local minRank = math.huge
	for _, item in items do
		local ok, why = Forge.eligible(item)
		if not ok then
			return nil, why
		end
		inputValue += Economy.itemValue(item :: any)
		minRank = math.min(minRank, Economy.variantRank(item.v))
	end
	local odds = Config.Forge.odds
	return {
		fee = Forge.fee(inputValue),
		inputValue = inputValue,
		bust = odds.bust,
		normal = 1 - odds.bust - odds.lucky,
		lucky = odds.lucky,
		minRank = minRank,
		tags = Forge.unionTags(items),
		match = Forge.match(items, access),
	}, nil
end

function Forge.upRank(rank: number): number
	return math.min(rank + 1, Economy.maxVariantRank())
end

-- Rodzaj wyniku z liczby z [0, 1): [0, bust) skucha, [bust, bust + lucky) szczęście, reszta zwykły
function Forge.outcome(preview: Preview, r: number): Outcome
	if r < preview.bust then
		return "bust" :: Outcome
	elseif r < preview.bust + preview.lucky then
		return "lucky" :: Outcome
	end
	return "normal" :: Outcome
end

-- Wynik połączenia. rOutcome i rPick z [0, 1). Zwraca grzyb, rodzaj wyniku i numer wylosowanego grzyba.
function Forge.roll(preview: Preview, items: { Item }, rOutcome: number, rPick: number): (Item, Outcome, number)
	local outcome = Forge.outcome(preview, rOutcome)
	local pick = math.clamp(math.floor(rPick * #items) + 1, 1, #items)
	local picked = items[pick]
	if outcome == "bust" then
		return { s = picked.s, v = Economy.variantOfRank(preview.minRank) }, outcome, pick
	end
	local x = if #preview.tags > 0 then table.clone(preview.tags) else nil
	local match = preview.match
	if match then
		local rank = if outcome == "lucky" then Forge.upRank(preview.minRank) else preview.minRank
		return { s = match.id, v = Economy.variantOfRank(rank), x = x }, outcome :: Outcome, pick
	end
	local rank = Economy.variantRank(picked.v)
	if outcome == "lucky" then
		rank = Forge.upRank(rank)
	end
	return { s = picked.s, v = Economy.variantOfRank(rank), x = x }, outcome :: Outcome, pick
end

-- Średnia wartość wyniku (do testów i symulacji szans; okno pokazuje szanse, nie średnią)
function Forge.expectedValue(preview: Preview, items: { Item }): number
	local total = 0
	local n = #items
	-- Środek przedziału każdego wyniku: [0, bust) skucha, [bust, bust + lucky) szczęście, reszta zwykły
	local cases: { { chance: number, at: number } } = {
		{ chance = preview.bust, at = preview.bust / 2 },
		{ chance = preview.lucky, at = preview.bust + preview.lucky / 2 },
		{ chance = preview.normal, at = preview.bust + preview.lucky + preview.normal / 2 },
	}
	for pick = 1, n do
		local r = (pick - 0.5) / n
		for _, case in cases do
			if case.chance > 0 then
				local item = Forge.roll(preview, items, case.at, r)
				total += case.chance / n * Economy.itemValue(item :: any)
			end
		end
	end
	return total
end

return Forge
