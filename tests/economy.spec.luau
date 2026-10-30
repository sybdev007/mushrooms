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

local Progress = loadModule("src/shared/Progress.luau", {
	script = { Parent = { Config = Config, Economy = Economy } },
	require = function(module)
		return module
	end,
})

local Titles = loadModule("src/shared/Titles.luau", {
	script = { Parent = { Config = Config, Progress = Progress } },
	require = function(module)
		return module
	end,
})

local Achievements = loadModule("src/shared/Achievements.luau", {
	script = { Parent = { Config = Config, Progress = Progress } },
	require = function(module)
		return module
	end,
})

local roblox = require("@lune/roblox")
local Expedition = loadModule("src/shared/Expedition.luau", { Vector3 = roblox.Vector3 })

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
	local lantern = Config.Upgrades.lantern
	eq(Economy.upgradeCost("lantern", 0), lantern.costBase, "pierwsza latarnia")
	eq(Economy.upgradeCost("lantern", 1), math.floor(lantern.costBase * lantern.costGrowth), "druga latarnia")
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
	for _, list in {
		{ order = Config.UpgradeOrder, shop = "forest" },
		{ order = Config.CaveUpgradeOrder, shop = "cave" },
		{ order = Config.SwampUpgradeOrder, shop = "swamp" },
	} do
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
	-- W świecie kolejna strefa jest warta ponad 1,6 raza więcej; pierwsza strefa nowego świata
	-- jest warta więcej niż ostatnia poprzedniego (bagna mają więcej grzybów na wyprawę, więc
	-- dochód i tak skacze mocniej, tools/economy_sim.luau)
	local previous: number? = nil
	for zone, def in Config.Zones do
		if not def.safe then
			if previous then
				local sameWorld = Config.Zones[previous].world == def.world
				check(average(zone) > average(previous) * (if sameWorld then 1.6 else 1.2), "strefa " .. def.id .. " za mało opłacalna")
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

-- Czy klucz jest w CSV (tablica csvKeys powstaje dopiero niżej, przy testach tłumaczeń)
local function csvHas(key: string): boolean
	return string.find(fs.readFile("src/localization/GameStrings.csv"), "\n" .. key .. ",", 1, true) ~= nil
end

print("Sprzedaż u skupywacza")
test("indeksy do sprzedaży: tylko liczby całkowite z koszyka, bez powtórzeń, malejąco", function()
	local valid = Economy.validSellIndices({ 1, 3, 2 }, 3)
	check(valid ~= nil, "poprawna lista odrzucona")
	eq(table.concat(valid :: { number }, ","), "3,2,1", "kolejność do usuwania")
	eq(Economy.validSellIndices({ 1, 1 }, 3), nil, "powtórzenie")
	eq(Economy.validSellIndices({ 0 }, 3), nil, "zero")
	eq(Economy.validSellIndices({ 4 }, 3), nil, "poza koszykiem")
	eq(Economy.validSellIndices({ 1.5 }, 3), nil, "ułamek")
	eq(Economy.validSellIndices({ "1" }, 3), nil, "tekst")
	eq(Economy.validSellIndices({}, 3), nil, "pusta lista")
	eq(Economy.validSellIndices("1", 3), nil, "nie tabela")
	eq(Economy.validSellIndices({ 1, 2, 3, 4 }, 3), nil, "więcej niż w koszyku")
end)

test("odcisk koszyka zmienia się, gdy zmieni się zawartość albo kolejność", function()
	local a = { { s = "porcini" }, { s = "honey", v = "gold" } }
	local b = { { s = "honey", v = "gold" }, { s = "porcini" } }
	check(Economy.basketKey(a) == Economy.basketKey({ { s = "porcini" }, { s = "honey", v = "gold" } }), "ten sam koszyk")
	check(Economy.basketKey(a) ~= Economy.basketKey(b), "kolejność")
	check(Economy.basketKey(a) ~= Economy.basketKey({ { s = "porcini" } }), "mniej grzybów")
	check(Economy.basketKey({ { s = "porcini", x = { "mossy" } } }) ~= Economy.basketKey({ { s = "porcini" } }), "cecha")
	eq(Economy.basketKey({}), "", "pusty")
end)

test("skupywacz stoi w chatce za ladą, a sprzedaż sięga do kręgu przed nią", function()
	local merchant = Config.Merchant
	check(merchant.x > -16 and merchant.x < 16 and merchant.z > -44.3 and merchant.z < -42, "skupywacz poza miejscem za ladą")
	local shop = Economy.station("shop", "forest")
	local distance = math.sqrt((shop.x - merchant.x) ^ 2 + (shop.z - merchant.z) ^ 2)
	check(distance + shop.radius <= merchant.sellDistance, "krąg przed ladą za daleko od skupywacza")
	check(merchant.promptDistance < merchant.sellDistance, "przycisk rozmowy dalej niż zasięg sprzedaży")
end)

print("Nożyk, klasy, głębokość")
test("nożyk: od zwykłych szans do co najmniej podwójnych, każdy poziom ma kolor", function()
	eq(Economy.upgradeStat("knife", 0), 1, "scyzoryk bez premii")
	local best = Economy.upgradeStat("knife", Config.Upgrades.knife.maxLevel)
	check(best >= 2 and best <= 3, "najlepszy nóż x" .. best)
	for level = 0, Config.Upgrades.knife.maxLevel do
		check(Config.KnifeColors[level] ~= nil, "brak koloru noża poz. " .. level)
	end
	-- Nawet z najlepszym nożem i krwawym księżycem tęcza zostaje rzadka
	local maxEvent = 1
	for _, event in Config.Cycle.events do
		maxEvent = math.max(maxEvent, event.luck)
	end
	local maxZone = 1
	for zone = 1, #Config.Zones do
		maxZone = math.max(maxZone, Economy.zoneLuck(zone))
	end
	local rainbow = Economy.luckyChance(Config.Variants[3].chance, math.min(best * maxEvent * maxZone, Config.LuckBalance.freeCap))
	check(rainbow < 0.1, string.format("tęcza przy maks. szczęściu: %.1f%%", rainbow * 100))
end)

test("głębokość: obozy x1, w każdym świecie głębiej = większa szansa", function()
	for index, zone in Config.Zones do
		if zone.safe then
			eq(Economy.zoneLuck(index), 1, "obóz " .. zone.id)
		end
	end
	eq(Economy.zoneLuck(2), 1, "skraj lasu")
	check(Economy.zoneLuck(3) > Economy.zoneLuck(2), "gęstwina")
	check(Economy.zoneLuck(4) > Economy.zoneLuck(3), "jar")
	for index = 2, #Config.Zones do
		local prev, zone = Config.Zones[index - 1], Config.Zones[index]
		if zone.world == prev.world and not zone.safe and not prev.safe then
			check(Economy.zoneLuck(index) > Economy.zoneLuck(index - 1), "strefa " .. zone.id)
		end
	end
end)

test("klasy: od pospolitych do legendarnych, każda ma tłumaczenie", function()
	eq(Economy.speciesClass("honey").id, "common", "opieńka")
	eq(Economy.speciesClass("chanterelle").id, "uncommon", "kurka")
	eq(Economy.speciesClass("slippery_jack").id, "rare", "maślak")
	eq(Economy.speciesClass("glowing_agaric").id, "epic", "świecący muchomor")
	eq(Economy.speciesClass("leszy_crown").id, "legendary", "korona Leszego")
	eq(Economy.speciesClass("nie_ma").id, "common", "nieznany")
	for _, class in Config.Classes do
		check(csvHas(class.key), "brak " .. class.key)
	end
end)

print("Dzień i noc")
local Cycle = loadModule("src/shared/Cycle.luau", {
	script = { Parent = { Config = Config } },
	require = function(module)
		return module
	end,
})

test("cykl: noc, potem świt, potem następna noc", function()
	local length = Cycle.length()
	eq(length, Config.Cycle.nightSeconds + Config.Cycle.dawnSeconds, "długość")
	local start = 1000 * length
	eq(Cycle.at(start).phase, "night", "początek cyklu")
	eq(Cycle.at(start + Config.Cycle.nightSeconds - 1).phase, "night", "koniec nocy")
	eq(Cycle.at(start + Config.Cycle.nightSeconds).phase, "dawn", "świt")
	eq(Cycle.at(start + length - 1).phase, "dawn", "koniec świtu")
	eq(Cycle.at(start + length).phase, "night", "następna noc")
	eq(Cycle.at(start + 5).endsAt, start + Config.Cycle.nightSeconds, "koniec nocy")
	eq(Cycle.at(start + Config.Cycle.nightSeconds + 5).endsAt, start + length, "koniec świtu")
	eq(Cycle.activeEvent(start + Config.Cycle.nightSeconds + 1), nil, "o świcie bez zdarzenia")
end)

test("cykl: zdarzenie zależy tylko od numeru nocy, prognoza zgadza się z następną nocą", function()
	local length = Cycle.length()
	for index = 500, 520 do
		local night = Cycle.at(index * length + 10)
		eq(night.event.id, Cycle.at(index * length + 900).event.id, "ta sama noc")
		eq(night.nextEvent.id, Cycle.at((index + 1) * length + 10).event.id, "prognoza")
	end
end)

test("cykl: zdarzenia trafiają się mniej więcej zgodnie z wagami", function()
	local counts: { [string]: number } = {}
	local total, weightSum = 20000, 0
	for _, event in Config.Cycle.events do
		weightSum += event.weight
	end
	for index = 1, total do
		local id = Cycle.eventFor(index).id
		counts[id] = (counts[id] or 0) + 1
	end
	for _, event in Config.Cycle.events do
		local share = (counts[event.id] or 0) / total
		local expected = event.weight / weightSum
		check(math.abs(share - expected) < 0.03, string.format("%s: %.3f zamiast %.3f", event.id, share, expected))
		check(csvHas(event.key), "brak " .. event.key)
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

print("Ogródek")
test("dochód z grządki: część wartości na minutę, nawóz go mnoży", function()
	local rate = Config.Garden.incomeRate
	eq(Economy.plantIncome({ s = "porcini" }), 75 * rate, "borowik")
	eq(Economy.plantIncome({ s = "porcini", v = "gold" }), 225 * rate, "złoty borowik")
	eq(Economy.plantIncome({ s = "porcini" }, 2), 75 * rate * 2, "z nawozem x2")
	eq(Economy.gardenIncome({ { s = "porcini", t = 0 }, { s = "honey", t = 0 } }), (75 + 4) * rate, "ogródek")
	eq(Economy.gardenIncome({}), 0, "pusty")
	-- Grzyb ma się zwrócić w rozsądnym czasie: dłużej niż jedna wyprawa, krócej niż godzina
	local payback = 1 / rate
	check(payback >= 10 and payback <= 60, string.format("zwrot po %.0f min", payback))
end)

test("dochód offline jest ograniczony", function()
	local planted = { { s = "porcini", t = 0 } }
	local perMinute = Economy.gardenIncome(planted)
	eq(Economy.offlineIncome(planted, 1, 60), perMinute, "minuta")
	eq(Economy.offlineIncome(planted, 1, 999999), perMinute * Config.Garden.offlineMinutes, "limit")
	eq(Economy.offlineIncome(planted, 1, -100), 0, "czas z przyszłości")
end)

test("sadzenie: wolne grządki dostają najcenniejsze grzyby z koszyka", function()
	local basket = { { s = "honey" }, { s = "porcini" }, { s = "parasol" }, { s = "chanterelle", v = "gold" } }
	local moves = Economy.planPlanting(basket, {}, 2)
	eq(#moves, 2, "liczba")
	eq(moves[1].basket, 2, "borowik (75) pierwszy")
	eq(moves[2].basket, 3, "kania (24) druga")
	eq(moves[1].replace, nil, "bez wymiany")
	eq(#Economy.planPlanting({}, {}, 3), 0, "pusty koszyk")
end)

test("sadzenie: lepszy grzyb wypiera najsłabszy posadzony, gorszy nie", function()
	local planted = { { s = "porcini", t = 0 }, { s = "honey", t = 0 }, { s = "parasol", t = 0 } }
	local moves = Economy.planPlanting({ { s = "chanterelle" }, { s = "aspen_bolete" } }, planted, 3)
	eq(#moves, 1, "tylko jedna wymiana")
	eq(moves[1].basket, 2, "koźlarz (50)")
	eq(moves[1].replace, 2, "wypiera opieńkę (4)")
	-- Kurka (6) jest słabsza od każdego posadzonego po wymianie (24, 50, 75), więc zostaje w koszyku
	local mixed = Economy.planPlanting({ { s = "honey" }, { s = "porcini" } }, { { s = "parasol", t = 0 } }, 2)
	eq(#mixed, 1, "borowik na wolną grządkę, opieńka (4) nie wypiera kani (24)")
	eq(mixed[1].basket, 2, "borowik")
	eq(mixed[1].replace, nil, "bez wymiany")
end)

test("złodziej bierze najcenniejszy, wymiana zaczyna od najsłabszego", function()
	local planted = { { s = "honey", t = 0 }, { s = "porcini", t = 0 }, { s = "aspen_bolete", v = "gold", t = 0 } }
	eq(Economy.mostValuableIndex(planted), 3, "złoty koźlarz (150) bije borowika (75)")
	eq(Economy.weakestIndex(planted), 1, "opieńka")
	eq(Economy.mostValuableIndex({}), nil, "pusto")
end)

test("łup spowalnia: im rzadszy, tym wolniej, korony strażników najwolniej", function()
	local plain = Economy.carrySpeed({ s = "porcini" })
	local gold = Economy.carrySpeed({ s = "porcini", v = "gold" })
	local rainbow = Economy.carrySpeed({ s = "porcini", v = "rainbow" })
	check(plain < 1, "zwykły łup nie spowalnia")
	check(gold < plain and rainbow < gold, "rzadszy nie jest cięższy")
	eq(Economy.carrySpeed({ s = "leszy_crown" }), Config.Garden.carry.guardianSpeed, "korona Leszego")
	-- Właściciel z butami o poziom gorszymi i tak dogoni złodzieja z najzwyklejszym łupem
	for level = 1, Config.Upgrades.boots.maxLevel do
		local thief = Economy.upgradeStat("boots", level) * plain
		check(thief < Economy.upgradeStat("boots", level - 1), "poziom " .. level .. ": złodzieja nie da się dogonić")
	end
end)

test("grządki: od kilku na start do pełnej siatki ogródka", function()
	local first = Economy.upgradeStat("beds", 0)
	local last = Economy.upgradeStat("beds", Config.Upgrades.beds.maxLevel)
	check(first >= 2 and first <= 4, "na start " .. first)
	eq(last, Config.Garden.maxBeds, "maks. = tyle, ile stoi w ogródku")
	check(Economy.upgradeStat("fertilizer", 0) == 1, "nawóz bez ulepszenia")
end)

test("ogródki: na polanie, obok chatki, bez nachodzenia na siebie, drzewa z obrzeża i ścieżkę", function()
	local half = Config.Garden.size / 2
	-- Siatka grządek 3 x 3 (12,8 studs) musi się zmieścić z rabatkami po bokach
	check(half >= 12, "ogródek za mały na grządki")
	-- Korona drzewa z obrzeża sięga do ok. halfWidth - 3 - 5,2 * 1,9
	local borderReach = Config.ForestHalfWidth - 3 - 5.2 * 1.9
	for i, plot in Config.Garden.plots do
		eq(Economy.zoneIndexAt(plot.z - half), 1, "ogródek " .. i .. " (przód) poza polaną")
		eq(Economy.zoneIndexAt(plot.z + half), 1, "ogródek " .. i .. " (tył) poza polaną")
		check(math.abs(plot.x) + half < borderReach, "ogródek " .. i .. " pod drzewami z obrzeża")
		check(math.abs(plot.x) - half > 17, "ogródek " .. i .. " na chatce")
		-- Przed furtką (od strony środka) zostaje 7 studs wolnego miejsca, ścieżka do lasu biegnie przy x = 0
		check(math.abs(plot.x) - half - 7 > 4, "furtka ogródka " .. i .. " za blisko ścieżki")
		check(plot.z + half < Config.Zones[2].startZ - 3, "ogródek " .. i .. " na bramie do lasu")
		for j, other in Config.Garden.plots do
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
	for _, plot in Config.Garden.plots do
		check(plot.z - Config.Garden.size / 2 > plaza.center.z + plaza.radius, "plac wchodzi na ogródek")
	end
	check(table.find(plaza.slots, Config.Cave.shortcut.x) ~= nil, "skrót nie stoi na miejscu na portal")
end)

test("Skarbnik: skarbiec w Sztolni, ucieczka do obozowiska dopiero na prawie maks. butach", function()
	local lair = Config.Lair
	eq(Config.Zones[Economy.zoneIndexAt(lair.centerZ - lair.radius)].id, "mine", "przód skarbca")
	check(lair.centerZ + lair.radius + 8 < Config.Zones[9].endZ, "posąg Skarbnika za ścianą jaskini")
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
	for zone = 6, 9 do
		local def = Config.Zones[zone]
		need += 2 * (def.endZ - def.startZ) / speed * Economy.oilDrain(zone, scale)
	end
	check(need * Config.ReturnMargin < oil, "sztolnia za daleko: " .. need)
end)

print("Zakupy za Robuxy")

test("szczęście (Wysyp, mikstura) mnoży szanse na warianty", function()
	-- r tuż ponad szansą Tęczy: bez szczęścia nic rzadkiego, z ×2 już Tęcza
	local rainbow = 0
	for _, v in Config.Variants do
		if v.id == "rainbow" then
			rainbow = v.chance
		end
	end
	local r = rainbow * 1.5
	check(Economy.rollVariant(r, nil, 1) ~= "rainbow", "bez szczęścia")
	eq(Economy.rollVariant(r, nil, 2), "rainbow", "z miksturą")
	eq(Economy.rollVariant(0.999, nil, 0.5), Economy.rollVariant(0.999), "szczęście < 1 nic nie psuje")
	check(Config.Boom.regrowFactor > 0 and Config.Boom.regrowFactor < 1, "wysyp przyspiesza odrost")
	check(Config.Rescue.serverSeconds > Config.Rescue.buttonSeconds, "serwer czeka dłużej niż widać przycisk")
end)

test("każdy produkt ma nazwę i opis po angielsku i polsku, sklep zna każdy produkt", function()
	local entries = {}
	for line in string.gmatch(fs.readFile("src/localization/GameStrings.csv"), "[^\n]+") do
		local key = string.match(line, "^([^,]+),")
		if key then
			entries[key] = true
		end
	end
	for id, def in Config.Products do
		check(entries[def.key] == true, "brak tekstu " .. def.key)
		check(entries[def.key .. "_DESC"] == true, "brak opisu " .. def.key)
		check(def.id >= 0, "zły numer produktu " .. id)
	end
	for _, id in Config.ShopOrder do
		check(Config.Products[id] ~= nil, "sklep zna nieistniejący produkt " .. id)
	end
end)

print("Bagna")

-- Wyprawa z przystani do końca strefy bagien i powrót, z knotem z sitowia
local function swampRoundTrip(deepest: number, wickLevel: number): number
	local speed = Economy.upgradeStat("boots", Config.Upgrades.boots.maxLevel)
	local scale = Economy.upgradeStat("rushwick", wickLevel)
	local oil = 0
	for zone = 11, deepest do
		local def = Config.Zones[zone]
		oil += 2 * (def.endZ - def.startZ) / speed * Economy.oilDrain(zone, scale)
	end
	return oil * Config.ReturnMargin
end

test("bagna: Trzęsawisko od razu, głębiej dopiero z knotem z sitowia, staw na maks.", function()
	local oil = Economy.upgradeStat("oil", Config.Upgrades.oil.maxLevel)
	check(swampRoundTrip(11, 0) < oil, "trzęsawisko nieosiągalne po otwarciu bagien")
	check(swampRoundTrip(12, 0) > oil, "mokradła dostępne bez knota, brak progresu")
	check(swampRoundTrip(13, Config.Upgrades.rushwick.maxLevel) < oil, "staw nieosiągalny nawet z knotem")
end)

test("bagna: próg wejścia, strefy po kolei, przystań bezpieczna, portal w Sztolni za skarbcem", function()
	local need = Config.Swamp.unlockCoins
	eq(Economy.canEnterSwamp(need - 1, false), false, "poniżej progu")
	eq(Economy.canEnterSwamp(need, false), true, "próg")
	eq(Economy.canEnterSwamp(0, true), true, "raz otwarte")
	check(need > Config.Cave.unlockCoins * 10, "bagna za tanie względem jaskini")
	eq(Config.Zones[Economy.zoneIndexAt(Config.Swamp.portal.z)].id, "mine", "portal na bagna poza Sztolnią")
	check(Config.Swamp.portal.z > Config.Lair.centerZ + Config.Lair.radius + 8, "portal wchodzi na skarbiec")
	check(Config.Swamp.portal.z + 6 < Config.Zones[9].endZ, "portal w ścianie Sztolni")
	check(Economy.isSafeZone(Economy.zoneIndexAt(Config.Swamp.camp.z)), "przystań nie jest bezpieczna")
	check(Economy.isSafeZone(Economy.zoneIndexAt(Config.Swamp.returnPortal.z)), "portal powrotny poza przystanią")
	eq(Economy.zoneWorld(Economy.zoneIndexAt(2100)), "swamp", "świat bagien")
	eq(Economy.zoneIndexAt(1800), 9, "między jaskinią a bagnami = koniec Sztolni")
	local x, z = Economy.homePoint("swamp")
	eq(x, Config.Swamp.camp.x, "dom na bagnach x")
	eq(z, Config.Swamp.camp.z, "dom na bagnach z")
	eq(Economy.worldOilUpgrade("swamp"), "rushwick", "knot na bagnach")
	eq(Economy.worldOilUpgrade("forest"), nil, "w lesie bez knota")
end)

test("błędne ogniki: wyglądają jak Ognik, nic nie są warte i nie budzą strażnika", function()
	eq(Economy.isMimic("false_wisp"), true, "ognik")
	eq(Economy.isMimic("wisp_cap"), false, "prawdziwy ognik")
	eq(Economy.mushroomValue("false_wisp"), 0, "wartość")
	eq((Economy.getSpecies("false_wisp") :: any).key, (Economy.getSpecies("wisp_cap") :: any).key, "ta sama nazwa")
	eq(Economy.guardianOf("false_wisp"), nil, "strażnik")
	check(Config.Swamp.mimicOilLoss > 0 and Config.Swamp.mimicOilLoss < 0.5, "kara za ognik")
end)

test("Utopiec: Kielichy tylko na wyspie, ucieczka tylko na maks. butach", function()
	local lair = Config.UtopiecLair
	eq(Config.Zones[Economy.zoneIndexAt(lair.centerZ)].id, "pond", "wyspa poza stawem")
	check(lair.centerZ + lair.radius + 6 < Config.Zones[13].endZ, "posąg Utopca za ścianą bagien")
	local distance = lair.centerZ - Config.Zones[10].endZ
	check(not Economy.escapes(distance, Economy.upgradeStat("boots", Config.Upgrades.boots.maxLevel - 1), Config.Utopiec), "ucieczka za łatwa")
	check(Economy.escapes(distance, Economy.upgradeStat("boots", Config.Upgrades.boots.maxLevel), Config.Utopiec), "brak ucieczki na maks.")
	for _, species in Economy.guardianSpecies("utopiec") do
		eq(Economy.guardianOf(species.id), "utopiec", species.id)
		-- Kielich wart ponad dwa razy więcej niż najlepszy zwykły grzyb bagien (inaczej nie warto ryzykować)
		local best = 0
		for _, other in Config.Species do
			if Economy.zoneWorld(other.zone) == "swamp" and not Economy.guardianOf(other.id) then
				best = math.max(best, other.value)
			end
		end
		check(species.value > best * 2, species.id .. " nieopłacalny przy takim ryzyku")
	end
	check(#Economy.guardianSpecies("utopiec") > 0, "brak Kielicha")
	eq(Economy.guardianOf("leszy_crown"), "leszy", "korona")
	eq(Economy.guardianOf("skarbnik_truffle"), "skarbnik", "trufla")
	for zone = 1, #Config.Zones do
		for k = 0, 9 do
			local rolled = Economy.rollSpecies(zone, k / 10)
			check(rolled == nil or Economy.guardianOf(rolled.id) == nil, "grzyb strażnika losuje się w zwykłej strefie")
		end
	end
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
		"src/server/GardenService.luau",
		"src/server/ChaseService.luau",
		"src/client/GardenPrompts.luau",
		"src/client/SellPanel.luau",
		"src/client/MerchantView.luau",
	}
	for _, path in files do
		local source = fs.readFile(path)
		for key in string.gmatch(source, '"((%u+)_[%u_]+)"') do
			local prefix = string.match(key, "^(%u+)_")
			local checked = { HUD = true, MSG = true, ENGULF = true, ZONE = true, RACK = true, CAUGHT = true, GROVE = true, GARDEN = true, NPC = true, SELL = true, UPG = true }
			if checked[prefix] then
				check(csvKeys[key], path .. ": brak " .. key)
			end
		end
	end
end)

test("każdy stały klucz w Localize.t(...) jest w CSV", function()
	for _, dir in { "src/client", "src/server", "src/server/World" } do
		for _, name in fs.readDir(dir) do
			local path = dir .. "/" .. name
			if string.sub(name, -5) == ".luau" and fs.isFile(path) then
				local source = fs.readFile(path)
				for key in string.gmatch(source, 'Localize%.t%("([%u%d_]+)"%s*[,)]') do
					check(csvKeys[key], path .. ": brak " .. key)
				end
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
			-- Wnętrze chatki: x od -17 do 17, z od -44 do -14 (ściany z bali mają grubość)
			assert(station.x - station.radius >= -17.3 and station.x + station.radius <= 17.3, name .. " wystaje w bok")
			assert(station.z - station.radius >= -44.3 and station.z + station.radius <= -13.5, name .. " wystaje przez ścianę")
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

print("Tabelka szans (Economy.luck, variantOdds, tagOdds)")

test("bez bonusów szanse w tabelce = szanse z Config", function()
	for _, odd in Economy.variantOdds(1) do
		local def = Economy.getVariant(odd.id)
		check(math.abs(odd.chance - def.chance) < 1e-9, odd.id)
	end
end)

test("tabelka zgadza się z prawdziwym losowaniem", function()
	for _, luck in { 1, 2, 3.75, 40 } do
		local counts: { [string]: number } = {}
		local n = 200000
		for i = 0, n - 1 do
			local id = Economy.rollVariant((i + 0.5) / n, nil, luck)
			if id then
				counts[id] = (counts[id] or 0) + 1
			end
		end
		local total = 0
		for _, odd in Economy.variantOdds(luck) do
			total += odd.chance
			check(math.abs((counts[odd.id] or 0) / n - odd.chance) < 1e-4, odd.id .. " przy szczęściu " .. luck)
		end
		check(total <= 1 + 1e-9, "suma ponad 100%")
	end
end)

test("mikstura podwaja szczęście, części mnożą się w całość", function()
	local base = Economy.luck({ knifeLevel = 2, zone = nil, event = nil, boom = false, potion = false })
	local withPotion, parts = Economy.luck({ knifeLevel = 2, zone = nil, event = nil, boom = true, potion = true })
	check(math.abs(withPotion - base * Config.LuckPotion.luck * Config.Boom.luck) < 1e-9, "iloczyn")
	eq(#parts, 3, "nożyk + Wysyp + mikstura")
	local plain, none = Economy.luck({ knifeLevel = 0, zone = nil, event = nil, boom = false, potion = false })
	eq(plain, 1)
	eq(#none, 0, "bez bonusów pusta lista")
end)

test("szansa na cechę nie przekracza 100%", function()
	for _, tag in Config.Tags do
		eq(Economy.tagOdds(tag, 1), tag.chance)
		eq(Economy.tagOdds(tag, 1000), 1)
	end
end)

print("Balans szczęścia (Config.LuckBalance)")

local function worstCase(boom: boolean, potion: boolean): number
	local maxEvent = Config.Cycle.events[1]
	for _, event in Config.Cycle.events do
		if event.luck > maxEvent.luck then
			maxEvent = event
		end
	end
	local deepest = 1
	for zone = 1, #Config.Zones do
		if Economy.zoneLuck(zone) > Economy.zoneLuck(deepest) then
			deepest = zone
		end
	end
	return (Economy.luck({ knifeLevel = Config.Upgrades.knife.maxLevel, zone = deepest, event = maxEvent, boom = boom, potion = potion }))
end

test("darmowe bonusy nie przekraczają freeCap, całość nie przekracza maxLuck", function()
	check(worstCase(false, false) < Config.LuckBalance.freeCap, "darmowe x" .. worstCase(false, false))
	check(worstCase(true, true) <= Config.LuckBalance.maxLuck, "wszystko x" .. worstCase(true, true))
end)

test("przy maksymalnym szczęściu złoto i tęcza zostają rzadkie, cechy nie są pewne", function()
	local luck = worstCase(true, true)
	local odds = Economy.variantOdds(luck)
	local rainbow, goldOrBetter = 0, 0
	for _, odd in odds do
		local rank = Economy.variantRank(odd.id)
		if rank >= 3 then
			rainbow += odd.chance
		end
		if rank >= 2 then
			goldOrBetter += odd.chance
		end
	end
	check(rainbow < 0.05, string.format("tęcza %.1f%%", rainbow * 100))
	check(goldOrBetter < 0.25, string.format("złoto+ %.1f%%", goldOrBetter * 100))
	for _, tag in Config.Tags do
		check(Economy.tagOdds(tag, luck) < 0.75, tag.id)
	end
end)

test("mikstura zawsze się opłaca (co najmniej x1,5 szczęścia, chyba że trafiamy w limit)", function()
	for level = 0, Config.Upgrades.knife.maxLevel do
		for _, event in Config.Cycle.events do
			local input = { knifeLevel = level, zone = 4, event = event, boom = false, potion = false }
			local without = Economy.luck(input)
			input.potion = true
			local with = Economy.luck(input)
			check(with >= math.min(without * 1.5, Config.LuckBalance.maxLuck) - 1e-9, "nożyk " .. level .. " " .. event.id)
		end
	end
end)

print("Grzybopedia (Progress)")

test("każdy gatunek (poza błędnym ognikiem) jest na dokładnie jednej stronie", function()
	local seen = {}
	for _, page in Progress.PAGES do
		for _, species in Progress.pageSpecies(page) do
			check(not seen[species.id], "dwa razy: " .. species.id)
			seen[species.id] = true
		end
	end
	for _, species in Config.Species do
		eq(seen[species.id] == true, not species.mimic, species.id)
	end
end)

test("odkrycia: nowy wpis, nowy gatunek, stare true z zapisu", function()
	local atlas: { [string]: any } = { honey = true }
	local newEntry, newSpecies = Progress.discover(atlas, "honey", nil)
	check(not newEntry and not newSpecies, "zwykły miód już był")
	eq(atlas.honey, 1, "true zamienione na maskę")
	newEntry, newSpecies = Progress.discover(atlas, "honey", "gold")
	check(newEntry and not newSpecies, "złoty miód to nowy wpis")
	newEntry, newSpecies = Progress.discover(atlas, "porcini", "silver")
	check(newEntry and newSpecies, "pierwszy prawdziwek")
	check(Progress.has(atlas, "honey", 2) and not Progress.has(atlas, "honey", 1), "maska")
	local fake, _ = Progress.discover(atlas, "false_wisp", nil)
	check(not fake, "błędny ognik nie trafia do księgi")
end)

test("progi strony: złoty liczy się też do srebrnego progu, bonus i tytuł", function()
	local atlas: { [string]: any } = {}
	for _, species in Progress.pageSpecies("forest") do
		Progress.discover(atlas, species.id, "gold")
	end
	check(Progress.tierDone(atlas, "forest", 0), "odkryte")
	check(Progress.tierDone(atlas, "forest", 1), "srebro albo lepiej")
	check(Progress.tierDone(atlas, "forest", 2), "złoto")
	check(not Progress.tierDone(atlas, "forest", 3), "tęczy brak")
	local expected = Progress.TIERS[1].bonus + Progress.TIERS[2].bonus + Progress.TIERS[3].bonus
	check(math.abs(Progress.atlasBonus(atlas) - expected) < 1e-9, "bonus")
	eq(Progress.title(atlas), "TITLE_EXPERT_FOREST")
	eq(#Progress.milestones(atlas), 3)
	local found, total = Progress.entries(atlas, "forest")
	eq(found, #Progress.pageSpecies("forest"))
	eq(total, #Progress.pageSpecies("forest") * 4)
end)

test("pełna księga daje arcytytuł i rozsądny bonus", function()
	local atlas: { [string]: any } = {}
	for _, page in Progress.PAGES do
		for _, species in Progress.pageSpecies(page) do
			Progress.discover(atlas, species.id, "rainbow")
		end
	end
	eq(Progress.title(atlas), Progress.GRANDMASTER)
	local bonus = Progress.atlasBonus(atlas)
	check(bonus > 0.3 and bonus <= 1, "bonus " .. bonus)
end)

print("Strażnicy w Grzybopedii (Progress)")

test("każdy strażnik ma grzyby, świat z bezpieczną strefą i teksty EN/PL", function()
	for _, def in Progress.GUARDIANS do
		check(#Economy.guardianSpecies(def.id) > 0, def.id .. " niczego nie pilnuje")
		for _, species in Economy.guardianSpecies(def.id) do
			eq(Economy.guardianOf(species.id), def.id, species.id)
			eq(Economy.zoneWorld(species.zone), def.world, species.id .. " w innym świecie")
		end
		check(Progress.safeZone(def.world) ~= nil, def.id .. ": świat bez bezpiecznej strefy")
		check(Progress.escapeDistance(def) > 0, def.id .. ": legowisko przed bezpieczną strefą")
		check(csvHas("ATLAS_PAGE_" .. string.upper(def.world)), "brak strony " .. def.world)
		for _, suffix in { "", "_TITLE", "_LORE", "_TIP" } do
			check(csvHas(def.key .. suffix), "brak " .. def.key .. suffix)
		end
	end
	for _, key in { "ATLAS_PAGE_GUARDIANS", "MSG_BESTIARY_NEW", "BESTIARY_SUMMARY", "BESTIARY_LOCKED", "BESTIARY_RECORD" } do
		check(csvHas(key), "brak " .. key)
	end
end)

test("strażnika odkrywa dopiero kradzież, liczniki rosną osobno", function()
	local bestiary = {}
	eq(Progress.guardianEvent(bestiary, "leszy", "escape"), false, "ucieczka nie odkrywa")
	eq(Progress.guardianEvent(bestiary, "leszy", "caught"), false, "złapanie nie odkrywa")
	eq(Progress.guardianRecord(bestiary, "leszy").found, false, "jeszcze nieznany")
	eq(Progress.guardianEvent(bestiary, "leszy", "steal"), true, "pierwsza kradzież odkrywa")
	eq(Progress.guardianEvent(bestiary, "leszy", "steal"), false, "druga już nie")
	local record = Progress.guardianRecord(bestiary, "leszy")
	eq(record.stolen, 2, "kradzieże")
	eq(record.escaped, 1, "ucieczki")
	eq(record.caught, 1, "złapania")
	eq(Progress.guardianEvent(bestiary, "smok", "steal"), false, "nieznany strażnik")
	eq(Progress.guardianEvent(bestiary, "skarbnik", "taniec"), false, "nieznane zdarzenie")
	eq(bestiary.skarbnik, nil, "nieznane zdarzenie nie tworzy wpisu")
	local found, total = Progress.guardiansFound(bestiary)
	eq(found, 1, "odkryci")
	eq(total, #Progress.GUARDIANS, "wszyscy")
end)

test("stare zapisy: grzyb strażnika w Grzybopedii = strażnik już okradziony", function()
	local bestiary = {}
	local atlas = { [Economy.guardianSpecies("skarbnik")[1].id] = 4 }
	Progress.migrateBestiary(bestiary, atlas)
	eq(Progress.guardianRecord(bestiary, "skarbnik").found, true, "Skarbnik z księgi")
	eq(Progress.guardianRecord(bestiary, "leszy").found, false, "Leszy bez korony w księdze")
	eq(Progress.guardianRecord(bestiary, "skarbnik").stolen, 0, "liczniki od zera")
end)

test("próg butów do ucieczki rośnie ze światem i zgadza się z testami pościgu", function()
	local previous = -1
	for _, def in Progress.GUARDIANS do
		local level = Progress.bootsToEscape(def)
		check(level ~= nil, def.id .. ": nie da się uciec na żadnych butach")
		check((level :: number) > previous, def.id .. ": łatwiejszy niż poprzedni strażnik")
		previous = level :: number
	end
	eq(Progress.bootsToEscape(Progress.getGuardian("utopiec") :: any), Config.Upgrades.boots.maxLevel, "Utopiec tylko na maks.")
	eq(Progress.escapeDistance(Progress.getGuardian("leszy") :: any), groveDistance, "droga ucieczki przed Leszym")
end)

print("Codzienne zadania i seria logowań (Progress)")

test("trzy różne zadania, ten sam dzień = ten sam zestaw, inny gracz = zwykle inny", function()
	local a = Progress.newDaily(20000, 111)
	local b = Progress.newDaily(20000, 111)
	eq(#a.quests, Progress.QUESTS_PER_DAY)
	local ids = {}
	for i, q in a.quests do
		check(not ids[q.id], "powtórzone zadanie")
		ids[q.id] = true
		eq(q.id, b.quests[i].id, "deterministycznie")
		check(Progress.getQuest(q.id) ~= nil, "znane zadanie")
	end
	local differ = false
	for user = 1, 20 do
		local other = Progress.newDaily(20000, user)
		if other.quests[1].id ~= a.quests[1].id then
			differ = true
		end
	end
	check(differ, "różni gracze mają różne zestawy")
end)

test("postęp, ukończenie i bonus za wszystkie trzy (tylko raz)", function()
	local daily = Progress.newDaily(1, 1)
	local lastAll = false
	for _, state in daily.quests do
		local def = Progress.getQuest(state.id)
		local completed, allDone = Progress.questEvent(daily, def.kind, def.goal + 5)
		check(#completed >= 1, "ukończone " .. def.id)
		eq(state.n, def.goal, "postęp nie wychodzi ponad cel")
		lastAll = allDone
	end
	check(lastAll, "wszystkie trzy")
	local _, again = Progress.questEvent(daily, daily.quests[1].id, 1)
	check(not again, "bonus tylko raz")
end)

test("wymiana zadania raz dziennie, nie ukończonego, bez powtórek", function()
	local daily = Progress.newDaily(5, 9)
	local before = daily.quests[2].id
	check(Progress.reroll(daily, 2, 9), "pierwsza wymiana")
	check(daily.quests[2].id ~= before, "inne zadanie")
	local ids = {}
	for _, q in daily.quests do
		check(not ids[q.id], "powtórka po wymianie")
		ids[q.id] = true
	end
	check(not Progress.reroll(daily, 1, 9), "druga wymiana tego dnia")
	local fresh = Progress.newDaily(6, 9)
	fresh.quests[1].done = true
	check(not Progress.reroll(fresh, 1, 9), "ukończonego nie wymieniamy")
end)

test("nowy dzień = nowe zadania", function()
	local data = { daily = Progress.newDaily(10, 3) }
	check(not Progress.ensureDaily(data, 10, 3), "ten sam dzień")
	check(Progress.ensureDaily(data, 11, 3), "następny dzień")
	eq(data.daily.day, 11)
end)

test("seria logowań: dzień po dniu rośnie, przerwa zeruje, 7 dni w kółko", function()
	local streak = { day = 0, count = 0 }
	eq(Progress.claimLogin(streak, 100), 1)
	eq(Progress.claimLogin(streak, 100), nil, "drugi raz tego samego dnia")
	for day = 101, 106 do
		Progress.claimLogin(streak, day)
	end
	eq(streak.count, 7)
	eq(Progress.claimLogin(streak, 107), 1, "po 7 dniach od nowa w cyklu")
	eq(streak.count, 8, "ale seria trwa")
	eq(Progress.claimLogin(streak, 110), 1, "przerwa")
	eq(streak.count, 1)
end)

test("nagrody rosną z odblokowanym światem", function()
	local forest = Progress.rewardScale(false, false)
	local cave = Progress.rewardScale(true, false)
	local swamp = Progress.rewardScale(true, true)
	check(forest < cave and cave < swamp, "skala")
	check(forest >= 50, "minimum")
end)

print("Rankingi tygodniowe (Progress)")

test("tydzień zaczyna się w poniedziałek", function()
	-- 2026-10-26 to poniedziałek
	local monday = 1792972800
	eq(Progress.weekIndex(monday), Progress.weekIndex(monday + 6 * 86400 + 86399), "cały tydzień")
	eq(Progress.weekIndex(monday) - 1, Progress.weekIndex(monday - 1), "niedziela to poprzedni")
end)

test("zakodowane znalezisko: większa wartość wygrywa, da się odczytać gatunek i wariant", function()
	local a = Progress.encodeFind("porcini", "gold", 225)
	local b = Progress.encodeFind("honey", "rainbow", 32)
	check(a > b, "droższe wyżej")
	local value, species, rank = Progress.decodeFind(a)
	eq(value, 225)
	eq(species, "porcini")
	eq(rank, 2)
	local data = { weekly = { week = 1, steals = 3, best = a } }
	check(Progress.ensureWeek(data, 2), "nowy tydzień")
	eq(data.weekly.steals, 0)
end)

print("Wspólne wyprawy (Expedition)")

test("większa grupa = mniej oleju i więcej światła, z limitem", function()
	for size = 2, 6 do
		check(Expedition.drain(size) <= Expedition.drain(size - 1), "olej " .. size)
		check(Expedition.light(size) >= Expedition.light(size - 1), "światło " .. size)
	end
	eq(Expedition.drain(1), 1)
	eq(Expedition.light(1), 1)
	eq(Expedition.drain(10), Expedition.DRAIN[#Expedition.DRAIN], "ponad listę: najlepszy bonus")
	local oil, light = Expedition.bonusPercents(2)
	eq(oil, 25)
	eq(light, 25)
end)

test("grupa liczy tylko sąsiadów w promieniu (bez łańcuszków)", function()
	local V = roblox.Vector3.new
	local sizes = Expedition.groupSizes({
		{ id = "a", position = V(0, 0, 0) },
		{ id = "b", position = V(15, 0, 0) },
		{ id = "c", position = V(30, 0, 0) },
		{ id = "d", position = V(200, 0, 0) },
	}, 20)
	eq(sizes.a, 2, "a z b")
	eq(sizes.b, 3, "b z a i c")
	eq(sizes.c, 2, "c z b, nie z a")
	eq(sizes.d, 1, "sam")
end)

test("ratunek: kumpel ma rozsądny czas i dostaje się olej na powrót", function()
	check(Expedition.DOWN_SECONDS >= 8 and Expedition.DOWN_SECONDS <= 30, "czas")
	check(Expedition.REVIVE_OIL > 0 and Expedition.REVIVE_OIL < 1, "olej")
	check(Expedition.REVIVE_DISTANCE < Expedition.RADIUS, "trzeba podejść blisko")
end)

-- ===== Tytuły =====

local function titleCtx(stats: any?, atlas: any?, bestiary: any?, tutorialDone: boolean?): any
	local full = Titles.emptyStats()
	for key, value in stats or {} do
		full[key] = value
	end
	return { atlas = atlas or {}, bestiary = bestiary or {}, stats = full, tutorialDone = tutorialDone == true }
end

test("tytuły: każdy ma tłumaczenie, rzadkość i unikalne id", function()
	local csv = fs.readFile("src/localization/GameStrings.csv")
	local seen = {}
	for _, def in Titles.LIST do
		check(not seen[def.id], "powtórzony " .. def.id)
		seen[def.id] = true
		check(Titles.RARITY_COLOR[def.rarity] ~= nil, "rzadkość " .. def.id)
		check(string.find(csv, "\n" .. def.id .. ",", 1, true) ~= nil, "brak w CSV: " .. def.id)
		check(string.find(csv, "\n" .. def.id .. "_HOW,", 1, true) ~= nil, "brak opisu w CSV: " .. def.id .. "_HOW")
	end
	check(#Titles.LIST >= 25, "co najmniej 25 tytułów")
end)

test("tytuły: lista od zwykłych do mitycznych", function()
	local last = 0
	for _, def in Titles.LIST do
		local rank = Titles.rarityRank(def.rarity)
		check(rank >= last, "kolejność przy " .. def.id)
		last = rank
	end
end)

test("tytuły: liczniki i najlepszy tytuł", function()
	local ctx = titleCtx({}, {}, {}, true)
	local earned = Titles.earned(ctx)
	check(earned.TITLE_NEW, "po samouczku Nowy")
	eq(Titles.best(earned), "TITLE_NEW")
	Titles.count(ctx.stats, "pick", 99)
	check(not Titles.earned(ctx).TITLE_PICKER, "99 to za mało")
	Titles.count(ctx.stats, "pick", 1)
	check(Titles.earned(ctx).TITLE_PICKER, "100 zebranych")
	Titles.count(ctx.stats, "steal")
	earned = Titles.earned(ctx)
	check(earned.TITLE_THIEF, "pierwsza kradzież")
	eq(Titles.best(earned), "TITLE_THIEF", "rzadki wygrywa ze zwykłym")
	Titles.count(ctx.stats, "nieznane", 5)
	Titles.count(ctx.stats, "death", 3)
	eq(ctx.stats.deaths, 3)
end)

test("tytuły: wybór gracza tylko ze zdobytych", function()
	local earned = { TITLE_NEW = true, TITLE_THIEF = true }
	eq(Titles.resolve("TITLE_NEW", earned), "TITLE_NEW", "wybrany zwykły zostaje")
	eq(Titles.resolve("TITLE_MAGNATE", earned), "TITLE_THIEF", "niezdobyty = najlepszy")
	eq(Titles.resolve("", earned), "TITLE_THIEF", "auto = najlepszy")
	eq(Titles.resolve("", {}), "", "nic")
	eq(Titles.resolve(Titles.NONE, earned), "", "bez tytułu")
end)

test("tytuły: Grzybopedia daje tytuły stron i Arcygrzybiarza", function()
	local atlas = {}
	for _, species in Progress.pageSpecies("forest") do
		Progress.discover(atlas, species.id, nil)
	end
	local earned = Titles.earned(titleCtx({}, atlas))
	check(earned.TITLE_EXPLORER_FOREST, "odkrywca lasu")
	check(not earned.TITLE_EXPLORER_CAVE, "jaskinia jeszcze nie")
	for _, page in Progress.PAGES do
		for _, species in Progress.pageSpecies(page) do
			for _, variant in { "silver", "gold", "rainbow" } do
				Progress.discover(atlas, species.id, variant)
			end
		end
	end
	earned = Titles.earned(titleCtx({}, atlas))
	check(earned.TITLE_GRANDMASTER and earned.TITLE_RAINBOW_HUNTER, "wszystko tęczowe")
	eq(Titles.best(earned), "TITLE_GRANDMASTER")
	local n, goal = Titles.progress(Titles.get("TITLE_GRANDMASTER"), titleCtx({}, atlas))
	eq(n, goal)
end)

test("tytuły: nowe zdobyte tylko raz", function()
	local seen = { "TITLE_NEW" }
	local fresh = Titles.newlyEarned({ TITLE_NEW = true, TITLE_PICKER = true }, seen)
	eq(#fresh, 1)
	eq(fresh[1], "TITLE_PICKER")
	eq(#Titles.newlyEarned({ TITLE_NEW = true, TITLE_PICKER = true }, seen), 0)
end)

-- ===== Odznaki =====

test("odznaki: każde osiągnięcie ma wpis w Config.Badges", function()
	for _, id in Achievements.IDS do
		check(typeof(Config.Badges[id]) == "number", "brak " .. id)
	end
	for id in Config.Badges do
		check(table.find(Achievements.IDS, id) ~= nil, "nieznane " .. id)
	end
end)

test("odznaki: osiągnięcia z postępu gracza", function()
	local source = { atlas = {}, bestiary = {}, stats = Titles.emptyStats(), caveUnlocked = false, swampUnlocked = true }
	local done = Achievements.check(source)
	check(not done.first_mushroom and not done.cave, "nic jeszcze")
	check(done.swamp, "bagna")
	source.stats.picked = 1
	source.stats.bestStreak = 7
	Progress.discover(source.atlas, Config.Species[1].id, "gold")
	done = Achievements.check(source)
	check(done.first_mushroom and done.gold and done.streak7, "grzyb, złoty, seria")
	check(not done.rainbow, "tęczy brak")
	-- Bez numerów odznak nic nie czeka na przyznanie
	local saved = table.clone(Config.Badges)
	eq(#Achievements.pending(done, {}), 0)
	Config.Badges.gold = 123
	Config.Badges.swamp = 456
	local pending = Achievements.pending(done, { "swamp" })
	eq(#pending, 1)
	eq(pending[1], "gold")
	for id, value in saved do
		Config.Badges[id] = value
	end
end)

-- ===== Halloween: Noc Dziadów =====
print("Halloween (Halloween.luau)")
local Halloween = loadModule("src/shared/Halloween.luau", {
	script = { Parent = { Config = Config, Cycle = Cycle, Economy = Economy } },
	require = function(module)
		return module
	end,
})
local H = Config.Halloween

test("halloween: okno eventu", function()
	check(not Halloween.active(H.startsAt - 1), "przed")
	check(Halloween.active(H.startsAt), "start")
	check(Halloween.active(H.endsAt - 1), "ostatnia sekunda")
	check(not Halloween.active(H.endsAt), "po")
	check(H.endsAt > H.startsAt, "koniec po starcie")
	eq(Halloween.secondsLeft(H.endsAt + 50), 0)
end)

test("halloween: Noc Dziadów co trzecią noc tylko w czasie eventu", function()
	local length = Cycle.length()
	local first = math.ceil(H.startsAt / length)
	local last = math.floor((H.endsAt - 1) / length)
	local spirits = 0
	for index = first, last do
		local isSpirit = Cycle.eventFor(index).id == "spirit_night"
		eq(isSpirit, index % H.spiritEvery == 0, "noc " .. index)
		if isSpirit then
			spirits += 1
		end
	end
	check(spirits >= 100, "dużo Nocy Dziadów w czasie eventu: " .. spirits)
	-- Poza eventem nigdy (waga 0)
	for index = first - 3000, first - 1 do
		check(Cycle.eventFor(index).id ~= "spirit_night", "przed eventem " .. index)
	end
	for index = last + 1, last + 3000 do
		check(Cycle.eventFor(index).id ~= "spirit_night", "po evencie " .. index)
	end
	local def = Cycle.getEvent("spirit_night")
	check(def ~= nil and def.weight == 0 and def.luck > 1 and def.regrow < 1, "zdarzenie w Config")
	eq(Cycle.getEvent("nope"), nil)
end)

test("halloween: szansa na dynię", function()
	local t = H.startsAt + 100
	eq(Halloween.pumpkinChance(H.startsAt - 1, nil, false), 0, "przed eventem")
	eq(Halloween.pumpkinChance(H.endsAt, "spirit_night", true), 0, "po evencie")
	eq(Halloween.pumpkinChance(t, nil, false), H.pumpkinChance)
	eq(Halloween.pumpkinChance(t, "full_moon", false), H.pumpkinChance)
	eq(Halloween.pumpkinChance(t, "spirit_night", false), H.spiritPumpkinChance)
	eq(Halloween.pumpkinChance(t, nil, true), H.boomPumpkinChance)
	check(H.spiritPumpkinChance > H.pumpkinChance, "w Noc Dziadów więcej")
	check(not Halloween.canBePumpkin("false_wisp"), "błędny ognik nie")
	check(Halloween.canBePumpkin("honey"), "opieńka tak")
end)

test("halloween: cecha dyniowa liczy się w wartości i nie losuje się ze strefy", function()
	local tag = Economy.getTag("pumpkin")
	check(tag ~= nil, "getTag zna dynię (zapis)")
	eq(Economy.mutationMultiplier(nil, { "pumpkin" }), 2)
	eq(Economy.mutationMultiplier("gold", { "pumpkin", "mossy" }), 3 * 2.5)
	for zone = 0, #Config.Zones do
		for _, t in Economy.tagsForZone(zone) do
			check(t.id ~= "pumpkin", "strefa " .. zone)
		end
	end
	check(csvHas("MUT_PUMPKIN"), "tłumaczenie")
end)

test("halloween: cukierki zależnie od świata", function()
	eq(Halloween.candyFor({ s = "honey", x = { "pumpkin" } }), H.candyByWorld.forest)
	eq(Halloween.candyFor({ s = "cave_oyster", x = { "pumpkin" } }), H.candyByWorld.cave)
	eq(Halloween.candyFor({ s = "bog_bell", x = { "mossy", "pumpkin" } }), H.candyByWorld.swamp)
	eq(Halloween.candyFor({ s = "honey", x = { "mossy" } }), 0, "bez dyni")
	eq(Halloween.candyFor({ s = "honey" }), 0, "bez cech")
	eq(Halloween.candyFor({ s = "false_wisp", x = { "pumpkin" } }), 0, "ognik")
	eq(Halloween.candyForList({ { s = "honey", x = { "pumpkin" } }, { s = "porcini" }, { s = "pearl", x = { "pumpkin" } } }), H.candyByWorld.forest + H.candyByWorld.cave)
end)

test("halloween: ścieżka nagród", function()
	local track = Halloween.TRACK
	for i = 2, #track do
		check(track[i].candy > track[i - 1].candy, "progi rosną")
	end
	eq(Halloween.reached(0), 0)
	eq(Halloween.reached(track[1].candy - 1), 0)
	eq(Halloween.reached(track[1].candy), 1)
	eq(Halloween.reached(track[#track].candy + 999), #track)
	local steps = Halloween.newSteps(0, track[3].candy)
	eq(#steps, 3)
	eq(steps[1], 1)
	eq(#Halloween.newSteps(3, track[3].candy), 0, "już odebrane")
	eq(#Halloween.newSteps(1, track[2].candy + 1), 1)
	-- Każdy tytuł ze ścieżki jest w Titles, z celem równym progowi
	for _, step in track do
		if step.kind == "title" then
			local def = Titles.get(step.id)
			check(def ~= nil and def.stat == "candy" and def.goal == step.candy and def.event == "halloween", "tytuł " .. tostring(step.id))
		else
			check(step.kind == "luck" or step.kind == "coins" or (step.kind == "skin" and Halloween.getSkin(step.id) ~= nil), "nieznana nagroda " .. step.kind)
		end
	end
end)

test("halloween: tytuły i odznaka za cukierki", function()
	local stats = Titles.emptyStats()
	eq(stats.candy, 0)
	Titles.count(stats, "candy", 12)
	eq(stats.candy, 12)
	local ctx = { atlas = {}, bestiary = {}, stats = stats, tutorialDone = true }
	local earned = Titles.earned(ctx)
	check(earned.TITLE_PUMPKINHEAD == true, "Dyniogłowy")
	check(not earned.TITLE_ANCESTRAL_SPIRIT, "Duch jeszcze nie")
	local source = { atlas = {}, bestiary = {}, stats = stats, caveUnlocked = false, swampUnlocked = false }
	check(not Achievements.check(source).halloween2026, "odznaka jeszcze nie")
	stats.candy = H.badgeCandy
	check(Achievements.check(source).halloween2026 == true, "odznaka")
	check(Titles.earned(ctx).TITLE_ANCESTRAL_SPIRIT == true, "Duch Dziadów")
end)

test("halloween: skórki ze ścieżki i z kotła", function()
	local lanternAt = Halloween.trackCandyFor("pumpkin_lantern")
	check(lanternAt ~= nil, "latarnia jest na ścieżce")
	check(not Halloween.ownsSkin({}, (lanternAt :: number) - 1, "pumpkin_lantern"), "jeszcze nie")
	check(Halloween.ownsSkin({}, lanternAt :: number, "pumpkin_lantern"), "z progu")
	check(Halloween.ownsSkin({ "sickle" }, 0, "sickle"), "z kotła")
	check(not Halloween.ownsSkin({ "nope" }, 9999, "nope"), "nieznana")
	for id, def in Halloween.SKINS do
		check(def.slot == "lantern" or def.slot == "knife", "slot " .. id)
		check(csvHas(def.key), "tłumaczenie " .. def.key)
	end
end)

test("halloween: kocioł", function()
	local cauldron = H.cauldron
	local seen = {}
	for i = 0, 999 do
		local outcome = Halloween.rollCauldron(i / 1000)
		seen[outcome.id] = (seen[outcome.id] or 0) + 1
		if outcome.skin then
			check(Halloween.getSkin(outcome.skin) ~= nil, "skórka " .. outcome.id)
		end
	end
	for _, outcome in cauldron.outcomes do
		check((seen[outcome.id] or 0) > 0, "wypada " .. outcome.id)
		check(csvHas("CAULDRON_" .. string.upper(outcome.id)), "tłumaczenie " .. outcome.id)
	end
	eq(Halloween.rollCauldron(0).id, cauldron.outcomes[1].id)
	eq(Halloween.rollCauldron(1).id, cauldron.outcomes[#cauldron.outcomes].id, "r = 1 nie wychodzi poza listę")
	local chance = Halloween.treatChance()
	check(chance > 0.5 and chance < 0.75, "częściej nagroda niż psikus: " .. chance)
	-- Cukierki z kotła nie mogą się opłacać (wartość oczekiwana < koszt)
	local total, candy = 0, 0
	for _, outcome in cauldron.outcomes do
		total += outcome.weight
		if outcome.id == "candy" then
			candy += outcome.weight * (outcome.amount or 0)
		end
	end
	check(candy / total < cauldron.cost, "kocioł nie mnoży cukierków")
end)

test("halloween: najbliższa Noc Dziadów", function()
	local length = Cycle.length()
	local index = math.ceil(H.startsAt / length / H.spiritEvery) * H.spiritEvery
	local start = index * length
	local at, now = Halloween.nextSpiritNight(start - 30)
	eq(at, start, "zaraz się zacznie")
	eq(now, false)
	at, now = Halloween.nextSpiritNight(start + 60)
	eq(at, start, "trwa")
	eq(now, true)
	at, now = Halloween.nextSpiritNight(start + Config.Cycle.nightSeconds + 5)
	eq(at, start + H.spiritEvery * length, "o świcie: następna")
	eq(now, false)
	eq((Halloween.nextSpiritNight(H.endsAt + 10)), nil, "po evencie żadnej")
end)

print(string.format("\n%d ok, %d błędów", passed, failed))
if failed > 0 then
	process.exit(1)
end
