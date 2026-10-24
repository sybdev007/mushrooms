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
	eq(Economy.zoneIndexAt(9999), 4, "za mapą")
end)

test("strefy są ciągłe i rosną w mroku i zużyciu oleju", function()
	local zones = Config.Zones
	for i = 2, #zones do
		eq(zones[i].startZ, zones[i - 1].endZ, "ciągłość strefy " .. i)
		check(zones[i].oilDrain > zones[i - 1].oilDrain, "zużycie oleju musi rosnąć w strefie " .. i)
		check(zones[i].darkness > zones[i - 1].darkness, "mrok musi rosnąć w strefie " .. i)
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

test("Config.UpgradeOrder zawiera każde ulepszenie dokładnie raz", function()
	local seen = {}
	for _, id in Config.UpgradeOrder do
		check(Config.Upgrades[id] ~= nil, "nieznane " .. id)
		check(not seen[id], "duplikat " .. id)
		seen[id] = true
	end
	for id in Config.Upgrades do
		check(seen[id] == true, "brak w kolejności: " .. id)
	end
end)

print("Grzyby")
test("każda strefa leśna ma grzyby, chatka nie ma", function()
	eq(#Economy.speciesForZone(1), 0, "chatka")
	for zone = 2, #Config.Zones do
		check(#Economy.speciesForZone(zone) > 0, "brak grzybów w strefie " .. zone)
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
	for zone = 3, #Config.Zones do
		check(average(zone) > average(zone - 1) * 2, "strefa " .. zone .. " za mało opłacalna")
	end
end)

test("wartość grzybów i koszyka", function()
	eq(Economy.mushroomValue("porcini", false), 75, "borowik")
	eq(Economy.mushroomValue("porcini", true), 225, "złoty borowik")
	eq(Economy.mushroomValue("nie_ma", false), 0, "nieznany")
	eq(Economy.basketValue({ { s = "honey", g = false }, { s = "chanterelle", g = true } }), 22, "koszyk")
end)

test("las zabiera cały koszyk", function()
	eq(Economy.engulfLoss(0), 0)
	eq(Economy.engulfLoss(1), 1)
	eq(Economy.engulfLoss(5), 5)
	eq(Economy.engulfLoss(35), 35)
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
		if not species.grove then
			best = math.max(best, species.value)
		end
	end
	for _, species in Economy.groveSpecies() do
		check(species.value > best, species.id .. " nieopłacalna przy takim ryzyku")
	end
end)

test("gniazdo leży w Mrocznym Jarze, w granicach mapy", function()
	local g = Config.Grove
	eq(Economy.zoneIndexAt(g.centerZ - g.radius), #Config.Zones, "przód kręgu")
	local last = Config.Zones[#Config.Zones]
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
	eq(Economy.dryingValue({ s = "porcini", g = false, t = 100 }, 100), 75, "świeży borowik")
	eq(Economy.dryingValue({ s = "porcini", g = false, t = 0 }, Config.Drying.seconds), 150, "suchy borowik")
	eq(Economy.dryingValue({ s = "honey", g = false, t = 0 }, half), 6, "opieńka w połowie (4 * 1.5)")
	eq(Economy.rackValue({ { s = "porcini", g = false, t = 0 }, { s = "honey", g = true, t = 0 } }, Config.Drying.seconds), 150 + 24, "suszarnia")
	eq(Economy.basketValue({ { s = "porcini", g = false, d = 2 } }), 150, "ukradziony suchy borowik w koszyku")
end)

test("złodziej bierze najcenniejszy grzyb", function()
	local rack = {
		{ s = "honey", g = false, t = 0 },
		{ s = "porcini", g = false, t = 500 },
		{ s = "aspen_bolete", g = false, t = 0 },
	}
	-- t=600: borowik 75 * (1 + 100/600) = 87,5, koźlarz suchy 50 * 2 = 100
	eq(Economy.mostValuableIndex(rack, 600), 3, "suchy koźlarz bije świeżego borowika")
	eq(Economy.mostValuableIndex({}, 0), nil, "pusta")
end)

test("na suszarnię idą najcenniejsze świeże grzyby, bez ukradzionych", function()
	local basket = {
		{ s = "honey", g = false },
		{ s = "porcini", g = false, d = 2 },
		{ s = "parasol", g = false },
		{ s = "chanterelle", g = true },
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
	local porcini = { s = "porcini", g = false, t = 0 }
	eq(Economy.dryRatePerMinute(porcini, 0), 75 * Config.Drying.bonus / minutes, "świeży borowik")
	eq(Economy.dryRatePerMinute(porcini, Config.Drying.seconds - 1), 75 * Config.Drying.bonus / minutes, "prawie suchy")
	eq(Economy.dryRatePerMinute(porcini, Config.Drying.seconds), 0, "suchy")
	eq(Economy.dryRatePerMinute({ s = "porcini", g = true, t = 0 }, 0), 225 * Config.Drying.bonus / minutes, "złoty")
	-- Suma zarobków przez cały czas suszenia = przyrost wartości
	local gained = Economy.dryRatePerMinute(porcini, 0) * minutes
	eq(math.floor(gained + 0.5), Economy.dryingValue(porcini, Config.Drying.seconds) - Economy.dryingValue(porcini, 0), "zgodność z wartością")
end)

test("plac suszarni: na polanie, obok chatki, suszarnie w środku i nie na alejce", function()
	local yard = Config.Drying.yard
	eq(Economy.zoneIndexAt(yard.z1), 1, "przód placu poza polaną")
	eq(Economy.zoneIndexAt(yard.z2), 1, "tył placu poza polaną")
	check(yard.x1 > -Config.ForestHalfWidth + 6, "plac wchodzi w drzewa na brzegu mapy")
	check(yard.x2 < -13 - 10, "plac za blisko chatki")
	check(yard.aisleX > yard.x1 + 8 and yard.aisleX < yard.x2 - 8, "alejka (i brama) za blisko płotu")
	-- Suszarnia ma 11,4 x 7,75 studs (+ słupek z latarnią): 7,75 w poprzek (oś X), 11,4 wzdłuż (oś Z)
	local halfDepth, halfWidth = 3.9, 6.3
	for i, plot in Config.Drying.plots do
		check(plot.x - halfDepth > yard.x1 + 1 and plot.x + halfDepth < yard.x2 - 1, "suszarnia " .. i .. " wystaje za płot (X)")
		check(plot.z - halfWidth > yard.z1 + 1 and plot.z + halfWidth < yard.z2 - 1, "suszarnia " .. i .. " wystaje za płot (Z)")
		check(math.abs(plot.x - yard.aisleX) - halfDepth >= 3, "suszarnia " .. i .. " na alejce")
		for j, other in Config.Drying.plots do
			if j > i and other.x == plot.x then
				check(math.abs(other.z - plot.z) >= halfWidth * 2 + 2, string.format("suszarnie %d i %d za blisko", i, j))
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
	check(roundTripOil(#Config.Zones, speed) < oil, "las za długi nawet na maks.")
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
		"src/server/World/DryingYard.luau",
		"src/server/DryingService.luau",
		"src/server/LeszyService.luau",
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
