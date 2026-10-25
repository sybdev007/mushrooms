-- Testy logiki gry poza Robloxem. Uruchom z katalogu projektu: lune run tests/economy.spec.luau
-- Ładujemy dokładnie te same pliki co gra, podmieniając tylko `script` i `require`.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local function loadModule(path: string, env: { [string]: any }): any
	local source = fs.readFile(path)
	local chunk = luau.load(source, { debugName = path, environment = env })
	return chunk()
end

local Config = loadModule("src/shared/Config.luau", {})
local Economy = loadModule("src/shared/Economy.luau", {
	script = { Parent = { Config = Config } },
	require = function(module)
		return module
	end,
})

local passed, failed = 0, 0

local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("  ok   " .. name)
	else
		failed += 1
		print("  FAIL " .. name .. "\n       " .. tostring(err))
	end
end

local function eq(actual: any, expected: any, message: string?)
	if actual ~= expected then
		error(string.format("%s: oczekiwano %s, jest %s", message or "eq", tostring(expected), tostring(actual)), 2)
	end
end

local function check(condition: boolean, message: string)
	if not condition then
		error(message, 2)
	end
end

print("Strefy")
test("zoneIndexAt na granicach stref", function()
	eq(Economy.zoneIndexAt(-50), 1, "chatka")
	eq(Economy.zoneIndexAt(39.9), 1, "tuż przed lasem")
	eq(Economy.zoneIndexAt(40), 2, "początek skraju lasu")
	eq(Economy.zoneIndexAt(159.9), 2, "koniec skraju lasu")
	eq(Economy.zoneIndexAt(160), 3, "początek gęstwiny")
	eq(Economy.zoneIndexAt(300), 4, "początek jaru")
	eq(Economy.zoneIndexAt(600), 4, "między lasem a jaskinią = koniec jaru")
	eq(Economy.zoneIndexAt(1000), 5, "obozowisko")
	eq(Economy.zoneIndexAt(9999), #Config.Zones, "za jaskinią")
end)

test("strefy są ciągłe i rosną w mroku i zużyciu oleju", function()
	local zones = Config.Zones
	for i = 2, #zones do
		if zones[i].world ~= zones[i - 1].world or zones[i].safe then
			continue -- nowy świat zaczyna się od bezpiecznego obozowiska
		end
		eq(zones[i].startZ, zones[i - 1].endZ, "ciągłość strefy " .. i)
		check(zones[i].oilDrain > zones[i - 1].oilDrain, "zużycie oleju musi rosnąć w strefie " .. i)
		-- Mrok rośnie, aż dojdzie do całkowitej ciemności (1)
		check(zones[i].darkness > zones[i - 1].darkness or zones[i].darkness == 1, "mrok musi rosnąć w strefie " .. i)
	end
end)

print("Ulepszenia")
test("koszty i wartości ulepszeń", function()
	eq(Economy.upgradeCost("lantern", 0), 25, "pierwsza latarnia")
	eq(Economy.upgradeCost("lantern", 1), 40, "druga latarnia")
	eq(Economy.upgradeCost("lantern", Config.Upgrades.lantern.maxLevel), nil, "maks. poziom")
	eq(Economy.upgradeStat("lantern", 0), 14, "zasięg startowy")
	eq(Economy.upgradeStat("basket", 2), 11, "koszyk poz. 2")
end)

test("koszt każdego ulepszenia rośnie z poziomem", function()
	for id, def in Config.Upgrades do
		local previous = 0
		for level = 0, def.maxLevel - 1 do
			local cost = Economy.upgradeCost(id, level)
			check(cost ~= nil and cost > previous, id .. " poz. " .. level)
			previous = cost
		end
	end
end)

test("latarnia nie przekracza limitu PointLight (60)", function()
	local def = Config.Upgrades.lantern
	check(Economy.upgradeStat("lantern", def.maxLevel) <= 60, "zasięg ponad 60")
end)

test("UpgradeOrder + CaveUpgradeOrder zawierają każde ulepszenie dokładnie raz, każde w swoim sklepie", function()
	local seen = {}
	for _, list in { { order = Config.UpgradeOrder, shop = "forest" }, { order = Config.CaveUpgradeOrder, shop = "cave" } } do
		for _, id in list.order do
			check(Config.Upgrades[id] ~= nil, "nieznane " .. id)
			check(not seen[id], "duplikat " .. id)
			eq(Economy.upgradeShop(id), list.shop, "sklep " .. id)
			seen[id] = true
		end
	end
	for id in Config.Upgrades do
		check(seen[id] == true, "brak w kolejności: " .. id)
	end
end)

print("Grzyby")
test("każda strefa poza chatką i obozowiskiem ma grzyby", function()
	for zone, def in Config.Zones do
		if def.safe then
			eq(#Economy.speciesForZone(zone), 0, def.id)
		else
			check(#Economy.speciesForZone(zone) > 0, "brak grzybów w strefie " .. def.id)
		end
	end
end)

test("rollSpecies trafia w wagi", function()
	eq(Economy.rollSpecies(2, 0).id, "honey", "r=0")
	eq(Economy.rollSpecies(2, 0.49).id, "honey", "r=0.49")
	eq(Economy.rollSpecies(2, 0.5).id, "chanterelle", "r=0.5")
	eq(Economy.rollSpecies(2, 0.9999).id, "slippery_jack", "r~1")
	eq(Economy.rollSpecies(1, 0.5), nil, "chatka")
end)

test("głębsza strefa jest warta więcej", function()
	local function average(zone: number): number
		local total, weights = 0, 0
		for _, species in Economy.speciesForZone(zone) do
			total += species.value * species.weight
			weights += species.weight
		end
		return total / weights
	end
	-- W każdym świecie kolejna strefa jest warta ponad dwa razy więcej; jaskinia startuje wyżej niż koniec lasu
	local previous: number? = nil
	for zone, def in Config.Zones do
		if not def.safe then
			if previous then
				check(average(zone) > average(previous) * 1.6, "strefa " .. def.id .. " za mało opłacalna")
			end
			previous = zone
		end
	end
end)

test("wartość grzybów i koszyka", function()
	eq(Economy.mushroomValue("porcini"), 75, "borowik")
	eq(Economy.mushroomValue("porcini", "gold"), 225, "złoty borowik")
	eq(Economy.mushroomValue("nie_ma"), 0, "nieznany")
	eq(Economy.basketValue({ { s = "honey" }, { s = "chanterelle", v = "gold" } }), 22, "koszyk")
end)

test("las zabiera cały koszyk", function()
	eq(Economy.engulfLoss(0), 0)
	eq(Economy.engulfLoss(1), 1)
	eq(Economy.engulfLoss(5), 5)
	eq(Economy.engulfLoss(35), 35)
end)

print("Mutacje")
test("wariant: progi od najrzadszego, bez wariantu powyżej sumy szans", function()
	local rainbow = Config.Variants[3].chance
	local gold = Config.Variants[2].chance
	local silver = Config.Variants[1].chance
	eq(Economy.rollVariant(0), "rainbow", "r=0")
	eq(Economy.rollVariant(rainbow - 1e-6), "rainbow", "koniec tęczy")
	eq(Economy.rollVariant(rainbow), "gold", "początek złota")
	eq(Economy.rollVariant(rainbow + gold - 1e-6), "gold", "koniec złota")
	eq(Economy.rollVariant(rainbow + gold), "silver", "początek srebra")
	eq(Economy.rollVariant(rainbow + gold + silver), nil, "zwykły")
	eq(Economy.rollVariant(0.99), nil, "zwykły (r~1)")
end)

test("gwarancja: wymuszona ranga daje co najmniej złoto", function()
	eq(Economy.rollVariant(0.99, 2), "gold", "zwykły -> złoto")
	eq(Economy.rollVariant(Config.Variants[3].chance + Config.Variants[2].chance + 0.001, 2), "gold", "srebro -> złoto")
	eq(Economy.rollVariant(0, 2), "rainbow", "tęcza zostaje tęczą")
	check(Config.PityRolls >= 20 and Config.PityRolls <= 120, "gwarancja za częsta albo za rzadka")
end)

test("warianty: rzadsze są cenniejsze, szanse sensowne", function()
	local total = 0
	for i, variant in Config.Variants do
		total += variant.chance
		eq(variant.rank, i, "kolejność rang " .. variant.id)
		if i > 1 then
			local prev = Config.Variants[i - 1]
			check(variant.chance < prev.chance, variant.id .. " nie rzadszy od " .. prev.id)
			check(variant.mult > prev.mult, variant.id .. " nie cenniejszy od " .. prev.id)
		end
	end
	check(total < 0.15, "za dużo mutacji, przestaną być wyjątkowe")
end)

test("cechy sumują się, wariant mnoży całość", function()
	eq(Economy.mutationMultiplier(nil, nil), 1, "bez mutacji")
	eq(Economy.mutationMultiplier("gold", nil), 3, "złoto")
	eq(Economy.mutationMultiplier(nil, { "mossy" }), 1.5, "mech")
	eq(Economy.mutationMultiplier(nil, { "mossy", "glowing" }), 2.5, "mech + blask = 1 + 0,5 + 1")
	eq(Economy.mutationMultiplier("rainbow", { "glowing" }), 16, "tęcza z blaskiem")
	eq(Economy.mutationMultiplier("nieznany", { "nieznana" }), 1, "śmieci z zapisu")
	eq(Economy.mushroomValue("porcini", "rainbow", { "glowing" }), 1200, "tęczowy borowik z blaskiem")
	eq(Economy.mushroomValue("porcini", "gold", nil, 2), 450, "złoty borowik suchy")
end)

test("cechy rosną tylko w swoich strefach, głębiej więcej zysku", function()
	eq(#Economy.tagsForZone(1), 0, "chatka")
	eq(#Economy.tagsForZone(2), 0, "skraj lasu")
	check(#Economy.tagsForZone(3) > 0, "gęstwina bez cech")
	check(#Economy.tagsForZone(4) > 0, "jar bez cech")
	-- Głębiej w każdym świecie co najmniej tyle samo mutacji (pierwsza strefa jaskini zaczyna od nowa)
	for _, ids in { { 2, 3, 4 }, { 6, 7, 8 } } do
		for i = 2, #ids do
			check(Economy.expectedMultiplier(ids[i]) > Economy.expectedMultiplier(ids[i - 1]), "strefa " .. ids[i] .. " nie daje więcej mutacji")
		end
	end
end)

test("średnio mutacje dodają kilka-kilkanaście procent, a nie mnożą ekonomii", function()
	for zone = 2, #Config.Zones do
		local m = Economy.expectedMultiplier(zone)
		check(m > 1.05 and m < 1.4, string.format("strefa %d: średni mnożnik %.3f", zone, m))
	end
end)

test("każda mutacja ma tłumaczenie i ikonę", function()
	local csv = fs.readFile("src/localization/GameStrings.csv")
	for _, def in Config.Variants do
		check(string.find(csv, "\n" .. def.key .. ",", 1, true) ~= nil, "brak " .. def.key)
		check(def.icon ~= "", "brak ikony " .. def.id)
	end
	for _, def in Config.Tags do
		check(string.find(csv, "\n" .. def.key .. ",", 1, true) ~= nil, "brak " .. def.key)
		check(def.icon ~= "", "brak ikony " .. def.id)
	end
end)

print("Gniazdo Leszego")
test("Korona Leszego rośnie tylko w gnieździe", function()
	local grove = Economy.groveSpecies()
	check(#grove >= 1, "brak gatunków gniazda")
	for zone = 1, #Config.Zones do
		for _, species in Economy.speciesForZone(zone) do
			check(not species.grove, species.id .. " z gniazda losuje się w zwykłej strefie")
		end
		for r = 0, 0.99, 0.01 do
			local rolled = Economy.rollSpecies(zone, r)
			check(rolled == nil or not rolled.grove, "rollSpecies zwrócił grzyb z gniazda")
		end
	end
end)

test("korona jest warta więcej niż najdroższy zwykły grzyb", function()
	local best = 0
	for _, species in Config.Species do
		if not species.grove and Economy.zoneWorld(species.zone) == "forest" then
			best = math.max(best, species.value)
		end
	end
	for _, species in Economy.groveSpecies() do
		check(species.value > best, species.id .. " nieopłacalna przy takim ryzyku")
	end
end)

test("gniazdo leży w Mrocznym Jarze, w granicach mapy", function()
	local g = Config.Grove
	eq(Config.Zones[Economy.zoneIndexAt(g.centerZ - g.radius)].id, "ravine", "przód kręgu")
	local last = Config.Zones[4]
	check(g.centerZ + g.radius + 8 < last.endZ, "posąg za ścianą mapy")
	check(math.abs(g.centerX) + g.radius < Config.ForestHalfWidth - 6, "krąg za szeroki")
end)

-- Droga z gniazda do polany (strefa 1 kończy się na zones[2].startZ)
local groveDistance = Config.Grove.centerZ - Config.Zones[2].startZ

test("bez butów Leszy łapie, z pełnymi butami da się uciec", function()
	check(not Economy.escapesLeszy(groveDistance, Economy.upgradeStat("boots", 0)), "ucieczka bez ulepszeń")
	check(Economy.escapesLeszy(groveDistance, Economy.upgradeStat("boots", Config.Upgrades.boots.maxLevel)), "brak ucieczki na maks.")
end)

test("jest próg butów, od którego ucieczka się udaje (cel: poziom 2-5)", function()
	local first: number? = nil
	for level = 0, Config.Upgrades.boots.maxLevel do
		if Economy.escapesLeszy(groveDistance, Economy.upgradeStat("boots", level)) then
			first = level
			break
		end
	end
	check(first ~= nil, "nie da się uciec na żadnym poziomie")
	check((first :: number) >= 2 and (first :: number) <= 5, "próg ucieczki: poziom " .. tostring(first))
end)

test("escapesLeszy: szybszy gracz zawsze ucieka, krótsza droga pomaga", function()
	eq(Economy.escapesLeszy(10000, Config.Leszy.speed + 0.1), true, "szybszy od Leszego")
	eq(Economy.escapesLeszy(10000, Config.Leszy.speed), true, "równy Leszemu")
	eq(Economy.escapesLeszy(5, 16), true, "tuż przy polanie")
	eq(Economy.escapesLeszy(100, 0), false, "stoi w miejscu")
end)

print("Suszarnia")
test("mnożnik suszenia rośnie od 1 do 1 + bonus", function()
	eq(Economy.dryMultiplier(0), 1, "świeży")
	eq(Economy.dryMultiplier(-50), 1, "czas z przyszłości")
	eq(Economy.dryMultiplier(Config.Drying.seconds / 2), 1 + Config.Drying.bonus / 2, "w połowie")
	eq(Economy.dryMultiplier(Config.Drying.seconds), 1 + Config.Drying.bonus, "suchy")
	eq(Economy.dryMultiplier(Config.Drying.seconds * 10), 1 + Config.Drying.bonus, "nie rośnie w nieskończoność")
end)

test("wartość suszonego grzyba i suszarni", function()
	local half = Config.Drying.seconds / 2
	eq(Economy.dryingValue({ s = "porcini", t = 100 }, 100), 75, "świeży borowik")
	eq(Economy.dryingValue({ s = "porcini", t = 0 }, Config.Drying.seconds), 150, "suchy borowik")
	eq(Economy.dryingValue({ s = "honey", t = 0 }, half), 6, "opieńka w połowie (4 * 1.5)")
	eq(Economy.rackValue({ { s = "porcini", t = 0 }, { s = "honey", v = "gold", t = 0 } }, Config.Drying.seconds), 150 + 24, "suszarnia")
	eq(Economy.basketValue({ { s = "porcini", d = 2 } }), 150, "ukradziony suchy borowik w koszyku")
end)

test("złodziej bierze najcenniejszy grzyb", function()
	local rack = {
		{ s = "honey", t = 0 },
		{ s = "porcini", t = 500 },
		{ s = "aspen_bolete", t = 0 },
	}
	-- t=600: borowik 75 * (1 + 100/600) = 87,5, koźlarz suchy 50 * 2 = 100
	eq(Economy.mostValuableIndex(rack, 600), 3, "suchy koźlarz bije świeżego borowika")
	eq(Economy.mostValuableIndex({}, 0), nil, "pusta")
end)

test("na suszarnię idą najcenniejsze świeże grzyby, bez ukradzionych", function()
	local basket = {
		{ s = "honey" },
		{ s = "porcini", d = 2 },
		{ s = "parasol" },
		{ s = "chanterelle", v = "gold" },
	}
	local chosen = Economy.pickForDrying(basket, 2)
	eq(#chosen, 2, "liczba")
	eq(chosen[1], 3, "kania (24) pierwsza")
	eq(chosen[2], 4, "złota kurka (18) druga")
	eq(#Economy.pickForDrying(basket, 10), 3, "ukradziony suchy borowik zostaje w koszyku")
	eq(#Economy.pickForDrying(basket, 0), 0, "brak miejsca")
end)

test("miejsca na suszarnie nie wchodzą na chatkę ani ścieżkę", function()
	for i, plot in Config.Drying.plots do
		check(math.abs(plot.x) >= 10, "suszarnia " .. i .. " na ścieżce")
		local onCabin = math.abs(plot.x) < 19 and plot.z > -42 and plot.z < -1
		check(not onCabin, "suszarnia " .. i .. " w chatce")
		eq(Economy.zoneIndexAt(plot.z), 1, "suszarnia " .. i .. " poza polaną")
	end
end)

test("zarobek na minutę: stały podczas suszenia, zero po wyschnięciu", function()
	local minutes = Config.Drying.seconds / 60
	local porcini = { s = "porcini", t = 0 }
	eq(Economy.dryRatePerMinute(porcini, 0), 75 * Config.Drying.bonus / minutes, "świeży borowik")
	eq(Economy.dryRatePerMinute(porcini, Config.Drying.seconds - 1), 75 * Config.Drying.bonus / minutes, "prawie suchy")
	eq(Economy.dryRatePerMinute(porcini, Config.Drying.seconds), 0, "suchy")
	eq(Economy.dryRatePerMinute({ s = "porcini", v = "gold", t = 0 }, 0), 225 * Config.Drying.bonus / minutes, "złoty")
	-- Suma zarobków przez cały czas suszenia = przyrost wartości
	local gained = Economy.dryRatePerMinute(porcini, 0) * minutes
	eq(math.floor(gained + 0.5), Economy.dryingValue(porcini, Config.Drying.seconds) - Economy.dryingValue(porcini, 0), "zgodność z wartością")
end)

test("ogródki: na polanie, obok chatki, bez nachodzenia na siebie, drzewa z obrzeża i ścieżkę", function()
	local half = Config.Drying.gardenSize / 2
	-- Suszarnia (11,4 x 7,75) musi się zmieścić z grządkami po bokach
	check(half >= 8.5, "ogródek za mały na suszarnię i grządki")
	-- Korona drzewa z obrzeża sięga do ok. halfWidth - 3 - 5,2 * 1,9
	local borderReach = Config.ForestHalfWidth - 3 - 5.2 * 1.9
	for i, plot in Config.Drying.plots do
		eq(Economy.zoneIndexAt(plot.z - half), 1, "ogródek " .. i .. " (przód) poza polaną")
		eq(Economy.zoneIndexAt(plot.z + half), 1, "ogródek " .. i .. " (tył) poza polaną")
		check(math.abs(plot.x) + half < borderReach, "ogródek " .. i .. " pod drzewami z obrzeża")
		check(math.abs(plot.x) - half > 17, "ogródek " .. i .. " na chatce")
		-- Przed furtką (od strony środka) zostaje 7 studs wolnego miejsca, ścieżka do lasu biegnie przy x = 0
		check(math.abs(plot.x) - half - 7 > 4, "furtka ogródka " .. i .. " za blisko ścieżki")
		check(plot.z + half < Config.Zones[2].startZ - 3, "ogródek " .. i .. " na bramie do lasu")
		for j, other in Config.Drying.plots do
			if j > i then
				local apart = math.abs(other.x - plot.x) >= half * 2 + 1 or math.abs(other.z - plot.z) >= half * 2 + 1
				check(apart, string.format("ogródki %d i %d na sobie", i, j))
			end
		end
	end
end)

test("kłódka: złodziej trzyma przycisk dłużej z każdym poziomem", function()
	eq(Economy.upgradeStat("lock", 0), 2, "bez kłódki")
	check(Economy.upgradeStat("lock", Config.Upgrades.lock.maxLevel) <= 10, "kradzież nie może trwać wieczność")
end)

print("Balans")
test("pierwszy pełny koszyk wystarcza na najtańsze ulepszenie", function()
	local cheapestFish = math.huge
	for _, species in Economy.speciesForZone(2) do
		cheapestFish = math.min(cheapestFish, species.value)
	end
	local firstBasket = Economy.upgradeStat("basket", 0) * cheapestFish
	local cheapestUpgrade = math.huge
	for id in Config.Upgrades do
		cheapestUpgrade = math.min(cheapestUpgrade, Economy.upgradeCost(id, 0))
	end
	check(firstBasket >= cheapestUpgrade, string.format("koszyk %d < ulepszenie %d", firstBasket, cheapestUpgrade))
end)

-- Ile oleju kosztuje wyprawa do końca strefy `deepest` i powrót, idąc prosto
local function roundTripOil(deepest: number, speed: number): number
	local oil = 0
	for zone = 2, deepest do
		local def = Config.Zones[zone]
		oil += 2 * (def.endZ - def.startZ) / speed * def.oilDrain
	end
	return oil
end

test("na start da się przejść skraj lasu, ale nie Mroczny Jar", function()
	local oil = Economy.upgradeStat("oil", 0)
	local speed = Economy.upgradeStat("boots", 0)
	check(roundTripOil(2, speed) < oil, "skraj lasu nieosiągalny na start")
	local toRavine = roundTripOil(3, speed) -- dojście do jaru i powrót
	check(toRavine > oil, "jar dostępny bez ulepszeń, brak progresu")
end)

test("z pełnymi ulepszeniami da się przejść cały las", function()
	local oil = Economy.upgradeStat("oil", Config.Upgrades.oil.maxLevel)
	local speed = Economy.upgradeStat("boots", Config.Upgrades.boots.maxLevel)
	check(roundTripOil(4, speed) < oil, "las za długi nawet na maks.")
end)

-- Wyprawa z obozowiska do końca strefy jaskini i powrót, z ulepszeniem kryształowego knota
local function caveRoundTrip(deepest: number, speed: number, crystalLevel: number): number
	local scale = Economy.upgradeStat("crystal", crystalLevel)
	local oil = 0
	for zone = 6, deepest do
		local def = Config.Zones[zone]
		oil += 2 * (def.endZ - def.startZ) / speed * Economy.oilDrain(zone, scale)
	end
	return oil * Config.ReturnMargin
end

test("jaskinia: z maks. leśnymi ulepszeniami do Jeziora tak, do końca Otchłani dopiero z knotem", function()
	local oil = Economy.upgradeStat("oil", Config.Upgrades.oil.maxLevel)
	local speed = Economy.upgradeStat("boots", Config.Upgrades.boots.maxLevel)
	check(caveRoundTrip(7, speed, 0) < oil, "jezioro nieosiągalne po otwarciu jaskini")
	check(caveRoundTrip(8, speed, 0) > oil, "otchłań dostępna bez knota, brak progresu")
	check(caveRoundTrip(8, speed, Config.Upgrades.crystal.maxLevel) < oil, "otchłań nieosiągalna nawet z knotem")
end)

test("portal leśny stoi wyraźnie za gniazdem, skrót za chatką na polanie", function()
	local g = Config.Grove
	check(Config.Cave.portal.z - (g.centerZ + g.radius) >= 30, "portal za blisko gniazda")
	check(Config.Cave.portal.z + 6 < Config.Zones[4].endZ, "portal w ścianie na końcu lasu")
	eq(Economy.zoneIndexAt(Config.Cave.shortcut.z), 1, "skrót poza polaną")
	check(Config.Cave.shortcut.z < -80 and Config.Cave.shortcut.z > Config.Zones[1].startZ + 10, "skrót nie stoi daleko za chatką")
	-- Plac Portali mieści się na polanie, za chatką i za ogródkami
	local plaza = Config.PortalPlaza
	check(plaza.center.z - plaza.radius > Config.Zones[1].startZ + 4, "plac za ścianą mapy")
	check(plaza.center.z + plaza.radius < -35 - 5, "plac wchodzi na chatkę")
	for _, plot in Config.Drying.plots do
		check(plot.z - Config.Drying.gardenSize / 2 > plaza.center.z + plaza.radius, "plac wchodzi na ogródek")
	end
	check(table.find(plaza.slots, Config.Cave.shortcut.x) ~= nil, "skrót nie stoi na miejscu na portal")
end)

test("Skarbnik: skarbiec w Sztolni, ucieczka do obozowiska dopiero na prawie maks. butach", function()
	local lair = Config.Lair
	eq(Config.Zones[Economy.zoneIndexAt(lair.centerZ - lair.radius)].id, "mine", "przód skarbca")
	check(lair.centerZ + lair.radius + 8 < Config.Zones[#Config.Zones].endZ, "posąg Skarbnika za ścianą jaskini")
	local campEnd = Config.Zones[5].endZ
	local distance = lair.centerZ - campEnd
	check(not Economy.escapes(distance, Economy.upgradeStat("boots", 4), Config.Skarbnik), "ucieczka przed Skarbnikiem za łatwa")
	check(Economy.escapes(distance, Economy.upgradeStat("boots", Config.Upgrades.boots.maxLevel), Config.Skarbnik), "brak ucieczki na maks. butach")
	for _, species in Economy.lairSpecies() do
		check(species.value > 3200, species.id .. " nieopłacalna przy takim ryzyku")
		eq(Economy.isLairItem(species.id), true, species.id)
	end
	eq(Economy.isLairItem("leszy_crown"), false, "korona to nie trufla")
	for zone = 1, #Config.Zones do
		local rolled = Economy.rollSpecies(zone, 0.999)
		check(rolled == nil or not rolled.lair, "trufla losuje się w zwykłej strefie")
	end
end)

test("jaskinia: do końca Sztolni da się dojść z maks. knotem", function()
	local oil = Economy.upgradeStat("oil", Config.Upgrades.oil.maxLevel)
	local speed = Economy.upgradeStat("boots", Config.Upgrades.boots.maxLevel)
	local scale = Economy.upgradeStat("crystal", Config.Upgrades.crystal.maxLevel)
	local need = 0
	for zone = 6, #Config.Zones do
		local def = Config.Zones[zone]
		need += 2 * (def.endZ - def.startZ) / speed * Economy.oilDrain(zone, scale)
	end
	check(need * Config.ReturnMargin < oil, "sztolnia za daleko: " .. need)
end)

test("portal: zamknięty poniżej progu, otwarty od progu i potem już zawsze", function()
	local need = Config.Cave.unlockCoins
	eq(Economy.canEnterCave(need - 1, false), false, "poniżej progu")
	eq(Economy.canEnterCave(need, false), true, "próg")
	eq(Economy.canEnterCave(0, true), true, "raz otwarty")
end)

test("jaskinia leży za lasem, strefy jaskini idą po kolei i obozowisko jest bezpieczne", function()
	local forestEnd = Config.Zones[4].endZ
	local previousEnd: number? = nil
	for index, zone in Config.Zones do
		if zone.world == "cave" then
			check(zone.startZ > forestEnd + 100, zone.id .. " za blisko lasu")
			if previousEnd then
				eq(zone.startZ, previousEnd, zone.id .. " nie styka się z poprzednią")
			end
			previousEnd = zone.endZ
			eq(Economy.zoneWorld(Economy.zoneIndexAt((zone.startZ + zone.endZ) / 2)), "cave", zone.id)
			eq(Economy.zoneIndexAt((zone.startZ + zone.endZ) / 2), index, zone.id .. " indeks")
		end
	end
	local camp = Config.Cave.camp
	check(Economy.isSafeZone(Economy.zoneIndexAt(camp.z)), "obozowisko nie jest bezpieczne")
	check(Economy.isSafeZone(Economy.zoneIndexAt(Config.Cave.returnPortal.z)), "portal powrotny poza obozowiskiem")
	eq(Config.Zones[Economy.zoneIndexAt(Config.Cave.portal.z)].id, "ravine", "portal leśny poza jarem")
	eq(Economy.returnOilNeeded(camp.z, 16), 0, "w obozowisku nic nie trzeba")
	-- Z głębi jaskini liczymy drogę do obozowiska, nie do chatki
	local fromCrystal = Economy.returnOilNeeded(1100, 20)
	check(math.abs(fromCrystal - 60 / 20 * Config.Zones[6].oilDrain) < 0.001, "powrót w jaskini: " .. fromCrystal)
end)

print("Powrót do chatki")
test("returnOilNeeded: zero w chatce, rośnie z głębokością", function()
	eq(Economy.returnOilNeeded(0, 16), 0, "chatka")
	eq(Economy.returnOilNeeded(40, 16), 0, "granica lasu")
	-- 80 studs w skraju (1.0/s) przy 16 studs/s = 5 oleju
	eq(Economy.returnOilNeeded(120, 16), 5, "skraj lasu")
	-- cała gęstwina 140 studs * 1.8 / 16 = 15.75 + cały skraj 120/16 = 7.5
	eq(Economy.returnOilNeeded(300, 16), 23.25, "koniec gęstwiny")
	check(Economy.returnOilNeeded(400, 16) > Economy.returnOilNeeded(300, 16), "jar droższy niż gęstwina")
	check(Economy.returnOilNeeded(200, 28) < Economy.returnOilNeeded(200, 16), "szybsze buty = mniej oleju")
end)

test("shouldTurnBack: nigdy w chatce, ostrzega z zapasem", function()
	eq(Economy.shouldTurnBack(-20, 16, 0), false, "chatka, nawet bez oleju")
	local need = Economy.returnOilNeeded(120, 16)
	eq(Economy.shouldTurnBack(120, 16, need * 2), false, "dużo oleju")
	eq(Economy.shouldTurnBack(120, 16, need * Config.ReturnMargin - 0.01), true, "olej ledwo na powrót z zapasem")
	eq(Economy.shouldTurnBack(120, 16, need), true, "olej dokładnie na powrót")
end)

test("progi ostrzeżeń są w dobrej kolejności", function()
	check(Config.OilWarnFraction > Config.OilLowFraction, "50% przed 25%")
	check(Config.ReturnMargin > 1, "zapas na powrót > 1")
end)

print("Tłumaczenia")
local csvKeys: { [string]: boolean } = {}
do
	local csv = fs.readFile("src/localization/GameStrings.csv")
	local first = true
	for line in string.gmatch(csv, "[^\r\n]+") do
		if first then
			first = false
		else
			local columns = string.split(line, ",")
			local key = columns[1]
			test("wiersz " .. key .. " ma EN i PL", function()
				eq(#columns, 5, "liczba kolumn (przecinek w tekście?)")
				check(columns[2] ~= "", "brak tekstu EN")
				check(columns[5] ~= "", "brak tekstu PL")
			end)
			csvKeys[key] = true
		end
	end
end

test("każdy klucz z Config jest w CSV", function()
	for _, zone in Config.Zones do
		check(csvKeys[zone.key], "brak " .. zone.key)
	end
	for _, species in Config.Species do
		check(csvKeys[species.key], "brak " .. species.key)
	end
	for _, def in Config.Upgrades do
		check(csvKeys[def.key], "brak " .. def.key)
		check(csvKeys[def.key .. "_DESC"], "brak opisu " .. def.key .. "_DESC")
	end
end)

test("każdy klucz HUD_/MSG_/ENGULF_/ZONE_ użyty w kodzie jest w CSV", function()
	local files = {
		"src/server/GameService.luau",
		"src/client/Hud.luau",
		"src/client/Main.client.luau",
		"src/client/Warnings.luau",
		"src/client/Signs.luau",
		"src/server/World/Props.luau",
		"src/server/World/Cabin.luau",
		"src/server/World/Grove.luau",
		"src/server/World/Garden.luau",
		"src/server/DryingService.luau",
		"src/server/ChaseService.luau",
		"src/client/RackPrompts.luau",
	}
	for _, path in files do
		local source = fs.readFile(path)
		for key in string.gmatch(source, '"((%u+)_[%u_]+)"') do
			local prefix = string.match(key, "^(%u+)_")
			local checked = { HUD = true, MSG = true, ENGULF = true, ZONE = true, RACK = true, CAUGHT = true, GROVE = true, YARD = true }
			if checked[prefix] then
				check(csvKeys[key], path .. ": brak " .. key)
			end
		end
	end
end)

-- Ładuje prawdziwy src/client/Localize.luau z podstawionymi usługami Robloxa.
-- Wpisy mają kształt jak z LocalizationTable:GetEntries() (Key, Source, Values).
local function loadLocalize(playerLocale: string): any
	local csv = fs.readFile("src/localization/GameStrings.csv")
	local robloxEntries = {}
	local first = true
	for line in string.gmatch(csv, "[^\r\n]+") do
		if first then
			first = false
		else
			local c = string.split(line, ",")
			table.insert(robloxEntries, { Key = c[1], Source = c[2], Context = c[3], Example = c[4], Values = { ["pl-pl"] = c[5] } })
		end
	end
	local stringsTable = {
		IsA = function(_, className)
			return className == "LocalizationTable"
		end,
		GetEntries = function()
			return robloxEntries
		end,
	}
	local services = {
		LocalizationService = {
			RobloxLocaleId = "en-us",
			WaitForChild = function(_, name)
				return if name == "GameStrings" then stringsTable else nil
			end,
		},
		Players = { LocalPlayer = { LocaleId = playerLocale } },
	}
	return loadModule("src/client/Localize.luau", {
		game = {
			GetService = function(_, name)
				return services[name]
			end,
		},
		warn = function(...)
			error("Localize ostrzegł: " .. table.concat({ ... }, " "))
		end,
		task = { spawn = function(fn)
			fn()
		end },
	})
end

print("Odczyt tłumaczeń w grze (Localize.luau)")
test("angielski gracz dostaje angielskie teksty, nie klucze", function()
	local Localize = loadLocalize("en-us")
	eq(Localize.getLocale(), "en", "język")
	eq(Localize.t("HUD_PICK"), "COLLECT")
	eq(Localize.t("HUD_COINS", { 42 }), "Coins: 42")
	eq(Localize.t("HUD_BASKET", { 3, 5 }), "Basket: 3/5")
	eq(Localize.t("ZONE_CABIN"), "Forager's Cabin")
end)

test("polski gracz dostaje polskie teksty", function()
	local Localize = loadLocalize("pl-pl")
	eq(Localize.getLocale(), "pl", "język")
	eq(Localize.t("HUD_PICK"), "ZBIERZ")
	eq(Localize.t("HUD_COINS", { 42 }), "Monety: 42")
	eq(Localize.t("MUSH_GLOWING"), "Świecący Muchomor")
end)

test("przełącznik zmienia język i woła odświeżenie", function()
	local Localize = loadLocalize("en-us")
	local refreshed = 0
	Localize.onChanged(function()
		refreshed += 1
	end)
	Localize.toggle()
	eq(Localize.t("HUD_PICK"), "ZBIERZ", "po przełączeniu na PL")
	Localize.toggle()
	eq(Localize.t("HUD_PICK"), "COLLECT", "po powrocie na EN")
	eq(refreshed, 2, "odświeżenia HUD")
end)

test("nieobsługiwany język gracza = angielski, nieznany klucz = klucz", function()
	local Localize = loadLocalize("de-de")
	eq(Localize.getLocale(), "en", "niemiecki")
	eq(Localize.t("NIE_MA_TAKIEGO"), "NIE_MA_TAKIEGO")
	eq(Localize.t("HUD_COINS"), "Coins: {1}", "brak argumentu zostaje widoczny")
end)

print("Stanowiska w chatce i skarbiec Leszego")

test("stanowiska leżą w chatce i w obozowisku, nie nachodzą na siebie ani na miejsce startu", function()
	local oil, shop = Economy.station("oil", "forest"), Economy.station("shop", "forest")
	for _, station in Config.Stations do
		local name = station.world .. "/" .. station.kind
		if station.world == "forest" then
			-- Wnętrze chatki: x od -12 do 12, z od -34 do -14 (ściany z bali mają grubość)
			assert(station.x - station.radius >= -12.3 and station.x + station.radius <= 12.3, name .. " wystaje w bok")
			assert(station.z - station.radius >= -34.3 and station.z + station.radius <= -13.5, name .. " wystaje przez ścianę")
		else
			assert(Economy.isSafeZone(Economy.zoneIndexAt(station.z)), name .. " poza obozowiskiem")
			assert(math.abs(station.x) + station.radius < Config.Cave.halfWidth, name .. " w ścianie jaskini")
		end
	end
	local campOil, campShop = Economy.station("oil", "cave"), Economy.station("shop", "cave")
	local campDistance = math.sqrt((campOil.x - campShop.x) ^ 2 + (campOil.z - campShop.z) ^ 2)
	assert(campDistance > campOil.radius + campShop.radius + Config.StationTolerance * 2, "kręgi w obozowisku za blisko")
	eq(Economy.atStation("shop", Config.Cave.camp.x, Config.Cave.camp.z), false, "lądowanie w obozowisku przy kramiku")
	eq(Economy.atStation("oil", Config.Cave.camp.x, Config.Cave.camp.z), false, "lądowanie w obozowisku przy beczkach")
	local distance = math.sqrt((oil.x - shop.x) ^ 2 + (oil.z - shop.z) ^ 2)
	assert(distance > oil.radius + shop.radius + Config.StationTolerance * 2, "kręgi za blisko siebie: " .. distance)
	-- Gracz startuje w (0, -20): nie powinien od razu stać w żadnym kręgu
	eq(Economy.atStation("oil", 0, -20), false, "start przy beczce")
	eq(Economy.atStation("shop", 0, -20), false, "start przy ladzie")
end)

test("atStation: środek tak, brzeg tak, za kręgiem nie, tolerancja serwera", function()
	local shop = Economy.station("shop", "forest")
	eq((Economy.stationAt("shop", shop.x, shop.z) :: any).world, "forest", "świat sklepu")
	eq(Economy.atStation("shop", shop.x, shop.z), true, "środek")
	eq(Economy.atStation("shop", shop.x + shop.radius, shop.z), true, "brzeg")
	eq(Economy.atStation("shop", shop.x + shop.radius + 1, shop.z), false, "za kręgiem")
	eq(Economy.atStation("shop", shop.x + shop.radius + 1, shop.z, Config.StationTolerance), true, "z tolerancją")
	eq(Economy.atStation("nie_ma", 0, 0), false, "nieznane stanowisko")
end)

test("Leszy odbiera tylko korony z gniazda", function()
	eq(Economy.isGroveItem("leszy_crown"), true, "korona")
	eq(Economy.isGroveItem("porcini"), false, "borowik")
	eq(Economy.isGroveItem("nie_ma"), false, "nieznany")
	assert(Config.Hoard.maxItems >= 3, "skarbiec mieści przynajmniej jedno pełne gniazdo")
end)

test("kamera nie oddala się tak, żeby widzieć las z góry", function()
	assert(Config.CameraMaxZoom >= 12 and Config.CameraMaxZoom <= 30, "zoom " .. Config.CameraMaxZoom)
end)

print("Skala interfejsu (UiScale.luau)")

local UiScale = loadModule("src/client/UiScale.luau", {
	game = {
		GetService = function(_, name)
			return { Name = name }
		end,
	},
})

local function size(x: number, y: number)
	return { X = x, Y = y }
end

test("pełna skala na komputerze, mniejsza na telefonie, z dolną granicą", function()
	eq(UiScale.compute(size(1920, 1080)), 1, "Full HD")
	eq(UiScale.compute(size(1000, 560)), 1, "rozmiar projektowy")
	local phone = UiScale.compute(size(705, 338))
	assert(phone > 0.59 and phone < 0.61, "Galaxy A06: " .. phone)
	eq(UiScale.compute(size(300, 150)), 0.55, "dolna granica")
end)

test("mały ekran = krótszy bok do 500 px (wtedy Roblox daje mały przycisk skoku)", function()
	eq(UiScale.isSmallScreen(size(705, 338)), true, "telefon poziomo")
	eq(UiScale.isSmallScreen(size(338, 705)), true, "telefon pionowo")
	eq(UiScale.isSmallScreen(size(1376, 1012)), false, "tablet")
	eq(UiScale.isSmallScreen(size(1920, 1080)), false, "komputer")
end)

print(string.format("\n%d ok, %d błędów", passed, failed))
if failed > 0 then
	process.exit(1)
end
