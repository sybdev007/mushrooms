-- Szanse i opłacalność Kuźni Grzybów (Moździerz Zielarki, runa), do sprawdzenia balansu.
-- Uruchom z katalogu projektu: lune run tools/forge_odds.luau
-- Ładuje te same pliki co gra (Config, Economy, Shared/Forge). Wartości to cena sprzedaży bez premii
-- (Grzybopedia, x2), tak jak opłata w grze. Wskaźnik „EV/(wkład+opłata)”: średnia wartość wyniku
-- podzielona przez to, co gracz oddaje; poniżej 1 = kuźnia średnio zjada monety (zamierzone).

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local function loadModule(path: string, env: { [string]: any }): any
	local chunk = luau.load(fs.readFile(path), { debugName = path, environment = env })
	return chunk()
end
local function req(module)
	return module
end

local Config = loadModule("src/shared/Config.luau", {})
local Economy = loadModule("src/shared/Economy.luau", { script = { Parent = { Config = Config } }, require = req })
local Forge = loadModule("src/shared/Forge.luau", { script = { Parent = { Config = Config, Economy = Economy } }, require = req })

local OPEN = { swampUnlocked = true, mountainUnlocked = true, jagaEscapes = 1 }
local MAX_RANK = Economy.maxVariantRank()
local F = Config.Forge

local function pct(x: number): string
	return string.format("%5.1f%%", x * 100)
end

local function grouped(preview: any): (number, number, number, number)
	local o = preview.odds
	return (o.bust or 0) + (o.worse or 0), o.similar or 0, (o.better or 0) + (o.great or 0), o.recipe or 0
end

local function describe(label: string, items: { any })
	local preview = Forge.preview(items, OPEN)
	if not preview then
		print(label, "nie da się")
		return
	end
	local worse, similar, better, recipe = grouped(preview)
	local ratio = preview.expected / (preview.inputValue + preview.fee)
	print(string.format(
		"%-34s wkład %9d  opłata %8d%s  gorszy %s podobny %s lepszy %s%s  mutacja %s  EV %.3f",
		label,
		preview.inputValue,
		preview.fee,
		if preview.feeRaised then "↑" else " ",
		pct(worse),
		pct(similar),
		pct(better),
		if recipe > 0 then "  przepis " .. pct(recipe) else "",
		pct(preview.mutation),
		ratio
	))
end

print("== Ustawienia ==")
local tierLine = {}
for _, tier in F.tiers do
	table.insert(tierLine, string.format("%s %.0f%% [%.2f; %.2f)", tier.id, tier.chance * 100, tier.lo, tier.hi))
end
print(table.concat(tierLine, "  "))
print(string.format("opłata %.0f%% (min %d), średni wynik najwyżej %.0f%% wkładu z opłatą, przepis %.0f%% (w tym %.0f%% wyżej), pula %d gatunków",
	F.feeShare * 100, F.minFee, F.maxReturn * 100, F.recipeOdds.hit * 100, F.recipeOdds.lucky * 100, #Forge.POOL))

print("\n== Przykładowe trójki ==")
local function g(s: string, v: string?, x: { string }?): any
	return { s = s, v = v, x = x }
end
describe("3 miodówki", { g("honey"), g("honey"), g("honey") })
describe("3 prawdziwki", { g("porcini"), g("porcini"), g("porcini") })
describe("złoty prawdziwek + 2 zwykłe", { g("porcini", "gold"), g("porcini"), g("porcini") })
describe("3 złote miodówki", { g("honey", "gold"), g("honey", "gold"), g("honey", "gold") })
describe("3 złote prawdziwki", { g("porcini", "gold"), g("porcini", "gold"), g("porcini", "gold") })
describe("projekt: złoty prawdz.+ametyst+perła", { g("porcini", "gold", { "glowing" }), g("amethyst", "silver", { "crystal" }), g("pearl", "gold") })
describe("3 tęczowe kurki", { g("chanterelle", "rainbow"), g("chanterelle", "rainbow"), g("chanterelle", "rainbow") })
describe("3 bagienne dzwonki", { g("bog_bell"), g("bog_bell"), g("bog_bell") })
describe("3 czapki wiedźmy", { g("witch_hat"), g("witch_hat"), g("witch_hat") })
describe("3 oczy nocy (szczyt cen)", { g("night_eye"), g("night_eye"), g("night_eye") })
describe("3 kosmiczne oczy nocy", { g("night_eye", "cosmic"), g("night_eye", "cosmic"), g("night_eye", "cosmic") })
describe("wiele cech (przegląd Codexa)", { g("night_eye", "rainbow"), g("ember", nil, { "mossy", "glowing", "crystal", "abyssal" }), g("earthstar", nil, { "cursed", "hexed", "moonlit" }) })

print("\n== Ukryte przepisy: EV/(wkład+opłata) po 125 kombinacjach rang ==")
for _, recipe in F.recipes do
	local worst, sum, n, raised = 0, 0, 0, 0
	for r1 = 0, MAX_RANK do
		for r2 = 0, MAX_RANK do
			for r3 = 0, MAX_RANK do
				local ranks = { r1, r2, r3 }
				local items = {}
				for i, input in recipe.inputs do
					table.insert(items, { s = input.s, v = Economy.variantOfRank(ranks[i]), x = if input.tag then { input.tag } else nil })
				end
				local preview = Forge.preview(items, OPEN) :: any
				local ratio = preview.expected / (preview.inputValue + preview.fee)
				sum += ratio
				n += 1
				worst = math.max(worst, ratio)
				if preview.feeRaised then
					raised += 1
				end
			end
		end
	end
	print(string.format("%-18s EV średnio %.3f  najwyżej %.3f  podniesiona opłata %d/125", recipe.id, sum / n, worst, raised))
end

print("\n== Losowe trójki z wypraw (rangi i cechy jak w lesie) ==")
math.randomseed(2026)
local rng = {
	NextNumber = function(_self): number
		return math.random()
	end,
	NextInteger = function(_self, a: number, b: number): number
		return math.random(a, b)
	end,
}
local function randomItem(): any
	local id = Forge.POOL[rng:NextInteger(1, #Forge.POOL)]
	local species = Economy.getSpecies(id)
	local rank = 0
	local r = rng:NextNumber()
	local acc = 0
	for k = MAX_RANK, 1, -1 do
		local variant = Economy.getVariant(Economy.variantOfRank(k))
		acc += variant.chance * 3 -- trochę częściej niż w lesie: do kuźni trafiają lepsze okazy
		if r < acc then
			rank = k
			break
		end
	end
	local x = {}
	for _, tag in Economy.tagsForZone(species.zone) do
		if rng:NextNumber() < tag.chance * 2 then
			table.insert(x, tag.id)
		end
	end
	return { s = id, v = Economy.variantOfRank(rank), x = if #x > 0 then x else nil }
end
local count, sumRatio, maxRatio, raised, sumMut = 4000, 0, 0, 0, 0
local sumWorse, sumSimilar, sumBetter = 0, 0, 0
local worstItems
local started = os.clock()
for _ = 1, count do
	local items = { randomItem(), randomItem(), randomItem() }
	local preview = Forge.preview(items, OPEN) :: any
	local ratio = preview.expected / (preview.inputValue + preview.fee)
	sumRatio += ratio
	if ratio > maxRatio then
		maxRatio, worstItems = ratio, items
	end
	if preview.feeRaised then
		raised += 1
	end
	sumMut += preview.mutation
	local worse, similar, better = grouped(preview)
	sumWorse += worse
	sumSimilar += similar
	sumBetter += better
end
local elapsed = os.clock() - started
print(string.format("%d trójek: EV średnio %.3f, najwyżej %.3f, podniesiona opłata %d, mutacja średnio %s", count, sumRatio / count, maxRatio, raised, pct(sumMut / count)))
print(string.format("średnio gorszy %s podobny %s lepszy %s; podgląd liczy się %.2f ms", pct(sumWorse / count), pct(sumSimilar / count), pct(sumBetter / count), elapsed / count * 1000))
if worstItems then
	local parts = {}
	for _, item in worstItems do
		table.insert(parts, string.format("%s/%s/%s", item.s, item.v or "-", table.concat(item.x or {}, "+")))
	end
	print("najwyższe EV: " .. table.concat(parts, ", "))
end

print("\n== Podgląd a prawdziwe losowanie (50 000 rzutów) ==")
local function check(label: string, items: { any })
	local preview = Forge.preview(items, OPEN) :: any
	local seen: { [string]: number } = {}
	local value, mutated = 0, 0
	local n = 50000
	for _ = 1, n do
		local result, kind = Forge.roll(preview, {
			recipe = rng:NextNumber(),
			tier = rng:NextNumber(),
			spread = rng:NextNumber(),
			mutation = rng:NextNumber(),
			pick = rng:NextNumber(),
		})
		local key = if kind == "recipeLucky" or kind == "mythic" or kind == "secret" then "recipe" else kind
		seen[key] = (seen[key] or 0) + 1
		value += Economy.itemValue(result)
		if result.v then
			mutated += 1
		end
	end
	local parts = {}
	for _, id in { "bust", "worse", "similar", "better", "great", "recipe" } do
		if (preview.odds[id] or 0) > 0 or (seen[id] or 0) > 0 then
			table.insert(parts, string.format("%s %s/%s", id, pct(preview.odds[id] or 0), pct((seen[id] or 0) / n)))
		end
	end
	print(string.format("%-26s %s  mutacja %s/%s  średnio %.0f/%.0f", label, table.concat(parts, "  "), pct(preview.mutation), pct(mutated / n), preview.expected, value / n))
end
check("3 prawdziwki", { g("porcini"), g("porcini"), g("porcini") })
check("projekt (3 z mutacją)", { g("porcini", "gold", { "glowing" }), g("amethyst", "silver", { "crystal" }), g("pearl", "gold") })
check("3 oczy nocy", { g("night_eye"), g("night_eye"), g("night_eye") })
check("przepis forge_mossbell", { g("bay_bolete", nil, { "mossy" }), g("porcini", nil, { "glowing" }), g("bog_bell") })
