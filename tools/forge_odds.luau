-- Szanse i opłacalność Kuźni Grzybów (Moździerz Zielarki), do sprawdzenia balansu (np. przez Codexa).
-- Uruchom z katalogu projektu: lune run tools/forge_odds.luau
-- Ładuje te same pliki co gra (Config, Economy, Shared/Forge). Wartości to cena sprzedaży bez premii
-- (Grzybopedia, x2), tak jak opłata w grze. Wskaźnik „EV/(wrzucone+opłata)”: średnia wartość wyniku
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

local function ratioOf(items: { any }): (number, any)
	local preview = Forge.preview(items, OPEN)
	return Forge.expectedValue(preview, items) / (preview.inputValue + preview.fee), preview
end

print("== Ustawienia ==")
local odds = Config.Forge.odds
print(string.format("skucha %.0f%%  zwykły %.0f%%  szczęście %.0f%%  opłata %.0f%% wartości (min %d), średni wynik najwyżej %.0f%% wkładu z opłatą", odds.bust * 100, (1 - odds.bust - odds.lucky) * 100, odds.lucky * 100, Config.Forge.feeShare * 100, Config.Forge.minFee, Config.Forge.maxReturn * 100))

print("\n== Ukryte przepisy: wynik/składniki (zwykłe) i EV/(wrzucone+opłata) po 125 kombinacjach rang ==")
for _, recipe in Config.Forge.recipes do
	local worst, sum, n, at = 0, 0, 0, ""
	local base = 0
	for r1 = 0, MAX_RANK do
		for r2 = 0, MAX_RANK do
			for r3 = 0, MAX_RANK do
				local ranks = { r1, r2, r3 }
				local items = {}
				for i, input in recipe.inputs do
					table.insert(items, { s = input.s, v = Economy.variantOfRank(ranks[i]), x = if input.tag then { input.tag } else nil })
				end
				local ratio, preview = ratioOf(items)
				if r1 + r2 + r3 == 0 then
					base = Economy.mushroomValue(recipe.id, nil, preview.tags) / preview.inputValue
				end
				sum += ratio
				n += 1
				if ratio > worst then
					worst, at = ratio, string.format("%d/%d/%d", r1, r2, r3)
				end
			end
		end
	end
	print(string.format("%-18s wartość %6d  wynik/składniki %.2f  EV średnio %.3f  najwyżej %.3f (rangi %s)", recipe.id, Economy.getSpecies(recipe.id).value, base, sum / n, worst, at))
end

print("\n== Trójki strażników (każdy co najmniej tęczowy) ==")
for _, special in Config.Forge.specials do
	for _, set in special.sets do
		local worst = 0
		for r1 = special.minRank, MAX_RANK do
			for r2 = special.minRank, MAX_RANK do
				for r3 = special.minRank, MAX_RANK do
					local items = { { s = set[1], v = Economy.variantOfRank(r1) }, { s = set[2], v = Economy.variantOfRank(r2) }, { s = set[3], v = Economy.variantOfRank(r3) } }
					worst = math.max(worst, (ratioOf(items)))
				end
			end
		end
		local rainbow = { { s = set[1], v = "rainbow" }, { s = set[2], v = "rainbow" }, { s = set[3], v = "rainbow" } }
		local r, preview = ratioOf(rainbow)
		print(string.format("%-11s %-50s tęcza: wrzucone %9d  wynik %9d  EV %.3f  najwyżej %.3f  szansa %.0f%%/próbę", special.id, table.concat(set, "+"), preview.inputValue, Economy.mushroomValue(special.id, "rainbow", nil), r, worst, (1 - odds.bust) * 100))
	end
end

-- Losowe koszyki: grzyby z jednej strefy jak z wyprawy (gatunek wg wag, wariant i cecha wg szans gry)
math.randomseed(20261104)
local function rollItem(zone: number): any?
	local species = Economy.rollSpecies(zone, math.random())
	if not species or species.mimic then
		return nil
	end
	local v = Economy.rollVariant(math.random())
	local x = nil
	for _, tag in Economy.tagsForZone(zone) do
		if math.random() < tag.chance then
			x = { tag.id }
		end
	end
	return { s = species.id, v = v, x = x }
end

print("\n== Losowe trójki z wypraw (bez przepisów), 20 000 prób na świat ==")
for _, world in { "forest", "cave", "swamp", "mountain" } do
	local zones = {}
	for index, zone in Config.Zones do
		if Economy.zoneWorld(index) == world and not Economy.isSafeZone(index) then
			table.insert(zones, index)
		end
	end
	local ratios = {}
	local above = 0
	local best, bestItems = 0, nil
	while #ratios < 20000 do
		local items = {}
		while #items < 3 do
			local item = rollItem(zones[math.random(1, #zones)])
			if item then
				table.insert(items, item)
			end
		end
		local preview = Forge.preview(items, OPEN)
		if preview and not preview.match then
			local ratio = Forge.expectedValue(preview, items) / (preview.inputValue + preview.fee)
			table.insert(ratios, ratio)
			if ratio >= 1 then
				above += 1
			end
			if ratio > best then
				best, bestItems = ratio, items
			end
		end
	end
	table.sort(ratios)
	local mean = 0
	for _, r in ratios do
		mean += r
	end
	local function describe(items: { any }): string
		local out = {}
		for _, item in items do
			table.insert(out, item.s .. (if item.v then ":" .. item.v else "") .. (if item.x then "+" .. table.concat(item.x, "+") else ""))
		end
		return table.concat(out, ", ")
	end
	print(string.format("%-9s EV średnio %.3f  mediana %.3f  90%% %.3f  najwyżej %.3f  z zyskiem %.2f%%", world, mean / #ratios, ratios[#ratios // 2], ratios[math.floor(#ratios * 0.9)], best, above / #ratios * 100))
	if bestItems then
		print("          najlepsza: " .. describe(bestItems))
	end
end

-- Najlepszy „wzmacniacz”: drogi grzyb + dwa tanie z mocnymi cechami (dokładanie cech do drogiego)
print("\n== Dokładanie cech do drogiego grzyba (1 drogi + 2 tanie z cechą) ==")
local worstAmp, worstLabel = 0, ""
for _, species in Config.Species do
	if not species.forgeOnly and not species.mimic and not species.grove and not species.lair and not species.guardian then
		for rank = 0, MAX_RANK do
			for _, tagA in Config.Tags do
				for _, tagB in Config.Tags do
					if tagA.id < tagB.id then
						local cheapA = Economy.speciesForZone(tagA.zone)[1]
						local cheapB = Economy.speciesForZone(tagB.zone)[1]
						if cheapA and cheapB then
							local items = { { s = species.id, v = Economy.variantOfRank(rank) }, { s = cheapA.id, x = { tagA.id } }, { s = cheapB.id, x = { tagB.id } } }
							local preview = Forge.preview(items, OPEN)
							if preview and not preview.match then
								local ratio = Forge.expectedValue(preview, items) / (preview.inputValue + preview.fee)
								if ratio > worstAmp then
									worstAmp = ratio
									worstLabel = string.format("%s %s + %s(%s) + %s(%s)", species.id, Economy.variantOfRank(rank) or "zwykły", cheapA.id, tagA.id, cheapB.id, tagB.id)
								end
							end
						end
					end
				end
			end
		end
	end
end
print(string.format("najwyżej EV %.3f: %s", worstAmp, worstLabel))

-- Dawcy z wcześniej połączonymi cechami (przypadek z przeglądu Codexa, kuznia-szanse.md): bez podwyżki
-- opłaty EV wynosił 1,57; teraz opłata rośnie do granicy Config.Forge.maxReturn
print("\n== Dawcy z wieloma cechami (przegląd Codexa) ==")
do
	local items = {
		{ s = "night_eye", v = "rainbow" },
		{ s = "ember", x = { "mossy", "glowing", "crystal", "abyssal" } },
		{ s = "earthstar", x = { "cursed", "hexed", "moonlit" } },
	}
	local preview = Forge.preview(items, OPEN)
	local ev = Forge.expectedValue(preview, items)
	print(string.format("wrzucone %d  opłata %d (zwykła %d, podniesiona: %s)  średni wynik %d  EV %.3f (granica %.2f)", preview.inputValue, preview.fee, Forge.fee(preview.inputValue), tostring(preview.feeRaised), math.floor(ev), ev / (preview.inputValue + preview.fee), Config.Forge.maxReturn))
end

print("\n== Warianty z kuźni a z lasu (Grzybopedia) ==")
for rank = 1, MAX_RANK do
	local lower = Economy.getVariant(Economy.variantOfRank(rank - 1))
	local upper = Economy.getVariant(Economy.variantOfRank(rank)) :: any
	-- Trzy grzyby rangi rank-1 jednego gatunku: forma rangi rank tylko przy szczęściu
	local perAttempt = odds.lucky
	local inputsPerHit = 3 / perAttempt
	local natural = if lower then lower.chance / upper.chance else 1 / upper.chance
	print(string.format("%-8s z kuźni: %.0f grzybów rangi niżej na sztukę;  w lesie na jeden wypada średnio %.1f rangi niżej", upper.id, inputsPerHit, natural))
end
