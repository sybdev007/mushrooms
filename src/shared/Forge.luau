--!strict
-- Kuźnia Grzybów (Moździerz Zielarki): wspólna logika serwera i klienta, bez API Robloxa (testy w Lune).
-- Klient liczy z tego podgląd w oknie, serwer to samo sprawdza jeszcze raz przy połączeniu.
-- Przepis (Config.Forge.recipes): slot i przyjmuje grzyb inputs[i].s, a jeśli jest inputs[i].tag,
-- grzyb musi mieć tę cechę. Wynik: gatunek przepisu, dokładnie dwie cechy przepisu, wariant = najsłabszy
-- wariant składników (z szansą Config.Forge.upgradeChance na rangę wyżej). Inne cechy składników przepadają.

local Config = require(script.Parent.Config)
local Economy = require(script.Parent.Economy)

local Forge = {}

export type Item = { s: string, v: string?, x: { string }?, d: number? }

export type Quote = {
	recipe: Config.ForgeRecipe,
	rank: number, -- ranga wariantu wyniku bez szczęścia
	upRank: number, -- ranga przy szczęściu (= rank, gdy już najwyższa)
	upChance: number, -- szansa na upRank (0, gdy rank jest najwyższa)
	tags: { string }, -- cechy wyniku (posortowane)
	fee: number,
	inputValue: number, -- ile byłyby warte 3 składniki przy sprzedaży
	value: number, -- ile jest wart wynik (zwykła ranga)
	upValue: number, -- ile jest wart wynik przy szczęściu
	lostTags: { string }, -- cechy składników, które nie przejdą na wynik
}

local byId: { [string]: Config.ForgeRecipe } = {}
for _, recipe in Config.Forge.recipes do
	byId[recipe.id] = recipe
end

function Forge.recipe(id: unknown): Config.ForgeRecipe?
	return if typeof(id) == "string" then byId[id] else nil
end

-- Cechy wyniku przepisu (wymagane cechy składników), posortowane, bez powtórzeń
function Forge.resultTags(recipe: Config.ForgeRecipe): { string }
	local tags = {}
	for _, input in recipe.inputs do
		if input.tag and not table.find(tags, input.tag) then
			table.insert(tags, input.tag)
		end
	end
	table.sort(tags)
	return tags
end

export type Access = { swampUnlocked: boolean?, mountainUnlocked: boolean?, jagaEscapes: number? }

-- Czy gracz ma już dostęp do przepisu. Zwraca też klucz tekstu z powodem, gdy nie.
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

-- Czy grzyb nadaje się do slotu `slot` przepisu. Zwraca klucz tekstu z powodem, gdy nie.
function Forge.fits(recipe: Config.ForgeRecipe, slot: number, item: Item?): (boolean, string?)
	local input = recipe.inputs[slot]
	if not input or not item then
		return false, "FORGE_WRONG_INPUT"
	end
	if item.s ~= input.s or Economy.isForgeOnly(item.s) then
		return false, "FORGE_WRONG_INPUT"
	end
	if item.d and item.d ~= 1 then
		return false, "FORGE_WRONG_INPUT"
	end
	for _, tag in (item.x or {}) :: { string } do
		-- Grzyby z eventów (dyniowe, Config.EventTags: strefa 0) nie wchodzą do kuźni: szkoda je zetrzeć
		local def = Economy.getTag(tag)
		if not def or def.zone == 0 then
			return false, "FORGE_NO_EVENT"
		end
	end
	if input.tag and not table.find(item.x or {}, input.tag) then
		return false, "FORGE_NEED_TAG"
	end
	return true, nil
end

-- Podgląd połączenia trzech grzybów (w kolejności slotów). nil + klucz powodu, gdy się nie da.
function Forge.quote(recipe: Config.ForgeRecipe, items: { Item }): (Quote?, string?)
	if #items ~= #recipe.inputs then
		return nil, "FORGE_WRONG_INPUT"
	end
	local rank = math.huge
	local inputValue = 0
	local lost = {}
	local tags = Forge.resultTags(recipe)
	for slot, item in items do
		local ok, reason = Forge.fits(recipe, slot, item)
		if not ok then
			return nil, reason
		end
		rank = math.min(rank, Economy.variantRank(item.v))
		inputValue += Economy.itemValue(item :: any)
		for _, tag in (item.x or {}) :: { string } do
			if not table.find(tags, tag) and not table.find(lost, tag) then
				table.insert(lost, tag)
			end
		end
	end
	local maxRank = Economy.maxVariantRank()
	local upRank = math.min(rank, maxRank) + (if rank < maxRank then 1 else 0)
	local fee = math.floor(recipe.fee * (Config.Forge.feeRank[rank] or 1) + 0.5)
	return {
		recipe = recipe,
		rank = rank,
		upRank = upRank,
		upChance = if upRank > rank then Config.Forge.upgradeChance else 0,
		tags = tags,
		fee = fee,
		inputValue = inputValue,
		value = Economy.mushroomValue(recipe.id, Economy.variantOfRank(rank), tags),
		upValue = Economy.mushroomValue(recipe.id, Economy.variantOfRank(upRank), tags),
		lostTags = lost,
	}, nil
end

-- Wynik połączenia. r z [0, 1): r < upChance = szczęście (ranga wyżej).
function Forge.result(quote: Quote, r: number): (Item, boolean)
	local lucky = quote.upChance > 0 and r < quote.upChance
	local rank = if lucky then quote.upRank else quote.rank
	return { s = quote.recipe.id, v = Economy.variantOfRank(rank), x = table.clone(quote.tags) }, lucky
end

-- Najtańszy pasujący grzyb z koszyka do slotu (bez już wybranych). Okno podpowiada go od razu,
-- żeby gracz nie zużył przypadkiem cennego okazu; droższy wybiera sam.
function Forge.cheapestFor(recipe: Config.ForgeRecipe, slot: number, basket: { Item }, taken: { [number]: boolean }): number?
	local best: number? = nil
	local bestValue = math.huge
	for index, item in basket do
		if not taken[index] and Forge.fits(recipe, slot, item) then
			local value = Economy.itemValue(item :: any)
			if value < bestValue then
				best, bestValue = index, value
			end
		end
	end
	return best
end

-- Wszystkie pasujące grzyby z koszyka do slotu, od najtańszego
function Forge.candidates(recipe: Config.ForgeRecipe, slot: number, basket: { Item }): { number }
	local list = {}
	for index, item in basket do
		if Forge.fits(recipe, slot, item) then
			table.insert(list, index)
		end
	end
	table.sort(list, function(a, b)
		return Economy.itemValue(basket[a] :: any) < Economy.itemValue(basket[b] :: any)
	end)
	return list
end

return Forge
