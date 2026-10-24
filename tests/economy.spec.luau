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

test("las zabiera połowę koszyka (w dół)", function()
	eq(Economy.engulfLoss(0), 0)
	eq(Economy.engulfLoss(1), 0)
	eq(Economy.engulfLoss(5), 2)
	eq(Economy.engulfLoss(6), 3)
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
	end
end)

test("każdy klucz HUD_/MSG_ użyty w kodzie jest w CSV", function()
	local files = {
		"src/server/GameService.luau",
		"src/client/Hud.luau",
		"src/client/Main.client.luau",
	}
	for _, path in files do
		local source = fs.readFile(path)
		for key in string.gmatch(source, '"((%u+)_[%u_]+)"') do
			if string.sub(key, 1, 4) == "HUD_" or string.sub(key, 1, 4) == "MSG_" then
				check(csvKeys[key], path .. ": brak " .. key)
			end
		end
	end
end)

print(string.format("\n%d ok, %d błędów", passed, failed))
if failed > 0 then
	process.exit(1)
end
