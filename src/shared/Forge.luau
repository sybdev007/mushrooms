--!strict
-- Kuźnia Grzybów (Moździerz Zielarki): wspólna logika serwera i klienta, bez API Robloxa (testy w Lune).
-- Klient liczy z tego podgląd w oknie (szanse, opłata), serwer to samo sprawdza jeszcze raz i losuje wynik.
-- Runa (Config.Forge): wkład = suma wartości trzech grzybów. Losowanie w czterech krokach:
--   1. próg (tiers) i cel w jego przedziale × wkład (logarytmicznie równomiernie);
--   2. wariant: szansa na mutację z gorąca wkładu, najwyżej o rangę ponad najlepszy grzyb wkładu; gdy w tej
--      randze żaden gatunek nie mieści się w progu, ranga rośnie, ale nie ponad najlepszy grzyb wkładu;
--   3. gatunek: jeden z `nearest` zwykłych gatunków gry o wartości najbliższej celowi (z cechami wkładu);
--   4. rodzaj wyniku = próg, w który naprawdę wpadł stosunek wartości wyniku do wkładu.
-- Ukryty przepis albo trójka strażników: z szansą recipeOdds.hit gatunek z kuźni, inaczej runa jak wyżej.
-- Podgląd liczy szanse rodzajów wyniku, szansę na mutację i średni wynik dla tej konkretnej trójki
-- (na siatce punktów w każdym progu), więc okno pokazuje to, co naprawdę może wypaść.

local Config = require(script.Parent.Config)
local Economy = require(script.Parent.Economy)

local Forge = {}

Forge.SLOTS = 3

export type Item = { s: string, v: string?, x: { string }?, d: number? }
export type Access = { swampUnlocked: boolean?, mountainUnlocked: boolean?, jagaEscapes: number? }
-- Co pasuje do trzech grzybów: gatunek wyniku i rodzaj ("recipe" | "mythic" | "secret")
export type Match = { id: string, kind: string }
-- Liczby z [0, 1) od serwera: przepis, próg, miejsce celu w progu, mutacja, wybór z najbliższych
export type Rolls = { recipe: number, tier: number, spread: number, mutation: number, pick: number }
export type Candidate = { s: string, value: number }

export type Preview = {
	fee: number,
	feeRaised: boolean, -- opłata podniesiona, bo średni wynik byłby wart prawie tyle co wkład z opłatą
	inputValue: number, -- wkład: ile byłyby warte 3 grzyby przy sprzedaży (bez premii)
	tags: { string }, -- cechy, które przejdą na wynik (posortowane)
	heat: number, -- gorąco wkładu 0..1
	minRank: number, -- najsłabszy wariant z trzech (przepisy)
	bestRank: number, -- najlepszy wariant z trzech
	cap: number, -- najwyższy wariant, jaki może wypaść
	mutationRanks: { number }, -- [ranga] = szansa wylosowania tej rangi (1..cap)
	match: Match?,
	recipeHit: number, -- szansa trafienia przepisu (0 bez przepisu)
	recipeLucky: number, -- z tego o rangę wyżej
	odds: { [string]: number }, -- szansa każdego rodzaju wyniku (id progów i "recipe"), razem 1
	mutation: number, -- szansa, że wynik ma wariant
	expected: number, -- średnia wartość wyniku
	ladder: { { Candidate } }, -- [ranga + 1] = gatunki z tym wariantem i cechami wkładu, rosnąco wartością
}

local TIERS = Config.Forge.tiers
local tierById: { [string]: Config.ForgeTier } = {}
local tierTotal = 0
for _, tier in TIERS do
	tierById[tier.id] = tier
	tierTotal += tier.chance
end

local recipeById: { [string]: Config.ForgeRecipe } = {}
for _, recipe in Config.Forge.recipes do
	recipeById[recipe.id] = recipe
end
local specialById: { [string]: Config.ForgeSpecial } = {}
for _, special in Config.Forge.specials do
	specialById[special.id] = special
end

-- Gatunki, z których runa wyłania wynik: zwykłe grzyby ze wszystkich światów (bez kuźni, strażników
-- i ogników-podróbek), od najtańszego
local POOL: { string } = {}
for _, species in Config.Species do
	if not species.forgeOnly and not species.mimic and Economy.guardianOf(species.id) == nil and species.value > 0 then
		table.insert(POOL, species.id)
	end
end
Forge.POOL = POOL

function Forge.recipe(id: unknown): Config.ForgeRecipe?
	return if typeof(id) == "string" then recipeById[id] else nil
end

function Forge.special(id: unknown): Config.ForgeSpecial?
	return if typeof(id) == "string" then specialById[id] else nil
end

function Forge.tier(id: string): Config.ForgeTier?
	return tierById[id]
end

-- Próg, w który wpada stosunek wartości wyniku do wkładu
function Forge.tierOf(ratio: number): Config.ForgeTier
	for _, tier in TIERS do
		if ratio < tier.hi then
			return tier
		end
	end
	return TIERS[#TIERS]
end

local function tierOfRoll(r: number): Config.ForgeTier
	local at = r * tierTotal
	local acc = 0
	for _, tier in TIERS do
		acc += tier.chance
		if at < acc then
			return tier
		end
	end
	return TIERS[#TIERS]
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

-- Ukryty przepis albo trójka strażników pasująca do trzech grzybów (nil = sama runa).
-- Przepis, do którego gracz nie ma jeszcze dostępu, nie działa (wtedy sama runa).
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

-- Połączone cechy trzech grzybów (posortowane, bez powtórzeń)
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

-- Cechy, które przejdą na wynik: najwyżej maxTags najcenniejszych z trzech grzybów
function Forge.resultTags(items: { Item }): { string }
	local tags = Forge.unionTags(items)
	local limit = Config.Forge.maxTags
	if #tags <= limit then
		return tags
	end
	local function mult(id: string): number
		local def = Economy.getTag(id)
		return if def then def.mult else 1
	end
	table.sort(tags, function(a, b)
		if mult(a) ~= mult(b) then
			return mult(a) > mult(b)
		end
		return a < b
	end)
	local kept = table.move(tags, 1, limit, 1, {})
	table.sort(kept)
	return kept
end

-- Gorąco wkładu: rangi wariantów i cechy trzech grzybów (0..1)
function Forge.heat(items: { Item }): number
	local rules = Config.Forge.mutation
	local points = 0
	for _, item in items do
		points += Economy.variantRank(item.v) + rules.tagHeat * #((item.x or {}) :: { string })
	end
	return math.min(1, points / rules.heatFull)
end

-- [ranga] = szansa wariantu tej rangi przy danym gorącu, od srebra do górnej granicy; razem najwyżej 1
function Forge.mutationOdds(heat: number, cap: number): { number }
	local rules = Config.Forge.mutation
	local odds: { number } = {}
	local total = 0
	for rank = 1, cap do
		local variant = Economy.getVariant(Economy.variantOfRank(rank))
		local gain = rules.gain[rank] or rules.gain[#rules.gain]
		local chance = if variant then variant.chance * (rules.base + heat * gain) else 0
		odds[rank] = chance
		total += chance
	end
	if total > 1 then
		for rank = 1, cap do
			odds[rank] /= total
		end
	end
	return odds
end

local function mutationRank(odds: { number }, r: number): number
	local acc = 0
	for rank = #odds, 1, -1 do
		acc += odds[rank]
		if r < acc then
			return rank
		end
	end
	return 0
end

function Forge.fee(inputValue: number): number
	return math.max(Config.Forge.minFee, math.floor(inputValue * Config.Forge.feeShare + 0.5))
end

function Forge.upRank(rank: number): number
	return math.min(rank + 1, Economy.maxVariantRank())
end

-- Drabina wyników: dla każdej rangi do `cap` wszystkie gatunki z tym wariantem i cechami, rosnąco wartością
local function ladderFor(cap: number, tags: { string }): { { Candidate } }
	local ladder: { { Candidate } } = {}
	local x = if #tags > 0 then tags else nil
	for rank = 0, cap do
		local variant = Economy.variantOfRank(rank)
		local list: { Candidate } = {}
		for _, id in POOL do
			table.insert(list, { s = id, value = Economy.mushroomValue(id, variant, x) })
		end
		table.sort(list, function(a, b)
			if a.value ~= b.value then
				return a.value < b.value
			end
			return a.s < b.s
		end)
		ladder[rank + 1] = list
	end
	return ladder
end

-- `count` gatunków z drabiny najbliższych celowi (odległość w skali logarytmicznej), od najbliższego
local function nearest(list: { Candidate }, target: number, count: number): { Candidate }
	local lo, hi = 1, #list + 1
	while lo < hi do
		local mid = (lo + hi) // 2
		if list[mid].value < target then
			lo = mid + 1
		else
			hi = mid
		end
	end
	local left, right = lo - 1, lo
	local out: { Candidate } = {}
	while #out < count and (left >= 1 or right <= #list) do
		local useLeft: boolean
		if left < 1 then
			useLeft = false
		elseif right > #list then
			useLeft = true
		else
			useLeft = math.log(target / list[left].value) <= math.log(list[right].value / target)
		end
		if useLeft then
			table.insert(out, list[left])
			left -= 1
		else
			table.insert(out, list[right])
			right += 1
		end
	end
	return out
end

-- Ranga i najbliższe gatunki dla celu: wylosowana ranga, chyba że nawet najcenniejszy gatunek z tym
-- wariantem nie sięga progu (drogi wkład z mutacjami). Wtedy ranga rośnie, najwyżej do najlepszego grzyba wkładu.
local function choose(preview: Preview, rank: number, target: number, tier: Config.ForgeTier): (number, { Candidate })
	local floor = preview.inputValue * tier.lo
	local top = math.max(rank, preview.bestRank)
	local r = rank
	while r < top do
		local ladder = preview.ladder[r + 1]
		if ladder[#ladder].value >= floor then
			break
		end
		r += 1
	end
	return r, nearest(preview.ladder[r + 1], target, Config.Forge.nearest)
end

local function targetFor(inputValue: number, tier: Config.ForgeTier, spread: number): number
	return inputValue * tier.lo * (tier.hi / tier.lo) ^ math.clamp(spread, 0, 1)
end

-- Szanse rodzajów wyniku, szansa na wariant i średnia wartość samej runy (bez przepisu)
local function runaStats(preview: Preview): ({ [string]: number }, number, number)
	local inputValue = preview.inputValue
	local odds: { [string]: number } = {}
	for _, tier in TIERS do
		odds[tier.id] = 0
	end
	local rankChance: { [number]: number } = { [0] = 1 }
	for rank, chance in preview.mutationRanks do
		rankChance[rank] = chance
		rankChance[0] -= chance
	end
	-- Liczone dokładnie (było 12 punktów na próg, co zaniżało średnią i przy dwóch przepisach dawało
	-- zwrot ponad maxReturn). Cel jest równomierny w skali logarytmicznej, ranga wyniku zależy tylko od
	-- progu (choose), a zbiór `count` najbliższych gatunków to okno kolejnych pozycji drabiny, które
	-- przesuwa się tylko w średniej geometrycznej wartości list[i] i list[i + count]. Dzielimy więc
	-- przedział celu w tych punktach i każdy odcinek liczymy z wagą równą jego długości.
	local count = Config.Forge.nearest
	local mutation, expected = 0, 0
	for _, tier in TIERS do
		local lnLo, lnHi = math.log(inputValue * tier.lo), math.log(inputValue * tier.hi)
		for rolled = 0, preview.cap do
			local rolledChance = rankChance[rolled] or 0
			if rolledChance > 0 then
				local w = tier.chance / tierTotal * rolledChance
				local rank = choose(preview, rolled, inputValue * tier.lo, tier)
				local list = preview.ladder[rank + 1]
				local cuts = { lnLo }
				for i = 1, #list - count do
					local cut = (math.log(list[i].value) + math.log(list[i + count].value)) / 2
					if cut > lnLo and cut < lnHi then
						table.insert(cuts, cut)
					end
				end
				table.sort(cuts)
				table.insert(cuts, lnHi)
				for k = 1, #cuts - 1 do
					local span = (cuts[k + 1] - cuts[k]) / (lnHi - lnLo)
					if span > 0 then
						local picks = nearest(list, math.exp((cuts[k] + cuts[k + 1]) / 2), count)
						local share = w * span / #picks
						for _, candidate in picks do
							local id = Forge.tierOf(candidate.value / inputValue).id
							odds[id] += share
							expected += share * candidate.value
						end
					end
				end
				if rank > 0 then
					mutation += w
				end
			end
		end
	end
	return odds, mutation, expected
end

-- Podgląd połączenia trzech grzybów. nil + klucz powodu, gdy się nie da.
function Forge.preview(items: { Item }, access: Access): (Preview?, string?)
	if #items ~= Forge.SLOTS then
		return nil, "FORGE_NEED_ITEMS"
	end
	local inputValue = 0
	local minRank, bestRank = math.huge, 0
	for _, item in items do
		local ok, why = Forge.eligible(item)
		if not ok then
			return nil, why
		end
		inputValue += Economy.itemValue(item :: any)
		local rank = Economy.variantRank(item.v)
		minRank = math.min(minRank, rank)
		bestRank = math.max(bestRank, rank)
	end
	local cap = math.min(Economy.maxVariantRank(), bestRank + 1)
	local heat = Forge.heat(items)
	local tags = Forge.resultTags(items)
	local match = Forge.match(items, access)
	local hit = if match then Config.Forge.recipeOdds.hit else 0
	local lucky = if match then Config.Forge.recipeOdds.lucky else 0
	local preview: Preview = {
		fee = Forge.fee(inputValue),
		feeRaised = false,
		inputValue = inputValue,
		tags = tags,
		heat = heat,
		minRank = minRank,
		bestRank = bestRank,
		cap = cap,
		mutationRanks = Forge.mutationOdds(heat, cap),
		match = match,
		recipeHit = hit,
		recipeLucky = lucky,
		odds = {},
		mutation = 0,
		expected = 0,
		ladder = ladderFor(cap, tags),
	}
	local odds, mutation, expected = runaStats(preview)
	local runa = 1 - hit
	for id, chance in odds do
		preview.odds[id] = chance * runa
	end
	preview.mutation = mutation * runa
	preview.expected = expected * runa
	if match then
		local x = if #tags > 0 then tags else nil
		local up = Forge.upRank(minRank)
		preview.odds.recipe = hit
		preview.expected += (hit - lucky) * Economy.mushroomValue(match.id, Economy.variantOfRank(minRank), x)
			+ lucky * Economy.mushroomValue(match.id, Economy.variantOfRank(up), x)
		preview.mutation += (if minRank > 0 then hit - lucky else 0) + (if up > 0 then lucky else 0)
	end
	-- Kuźnia nie może zarabiać: gdy średni wynik przekroczyłby maxReturn × (wkład + opłata), opłata rośnie
	local floor = math.ceil(preview.expected / Config.Forge.maxReturn - inputValue)
	if floor > preview.fee then
		preview.fee = floor
		preview.feeRaised = true
	end
	return preview, nil
end

-- Wynik połączenia z liczb od serwera. Zwraca grzyb i rodzaj wyniku (id progu albo rodzaj przepisu:
-- "recipe" / "recipeLucky" / "mythic" / "secret").
function Forge.roll(preview: Preview, rolls: Rolls): (Item, string)
	local x = if #preview.tags > 0 then table.clone(preview.tags) else nil
	local match = preview.match
	if match and rolls.recipe < preview.recipeHit then
		local lucky = rolls.recipe < preview.recipeLucky
		local rank = if lucky then Forge.upRank(preview.minRank) else preview.minRank
		local kind = if match.kind == "recipe" then (if lucky then "recipeLucky" else "recipe") else match.kind
		return { s = match.id, v = Economy.variantOfRank(rank), x = x }, kind
	end
	local tier = tierOfRoll(rolls.tier)
	local target = targetFor(preview.inputValue, tier, rolls.spread)
	local rank, list = choose(preview, mutationRank(preview.mutationRanks, rolls.mutation), target, tier)
	local pick = list[math.clamp(math.floor(rolls.pick * #list) + 1, 1, #list)]
	return { s = pick.s, v = Economy.variantOfRank(rank), x = x }, Forge.tierOf(pick.value / preview.inputValue).id
end

return Forge
