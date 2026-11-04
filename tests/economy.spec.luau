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

local Social = loadModule("src/shared/Social.luau", {})

local Achievements = loadModule("src/shared/Achievements.luau", {
	script = { Parent = { Config = Config, Progress = Progress } },
	require = function(module)
		return module
	end,
})

local roblox = require("@lune/roblox")
local Expedition = loadModule("src/shared/Expedition.luau", { Vector3 = roblox.Vector3 })

-- Skórki eventów (Shared/Skins) z modułami Halloween i Winter, dla testów, które ładują serwer
local function loadSkins(): any
	local function req(module)
		return module
	end
	local cycle = loadModule("src/shared/Cycle.luau", { script = { Parent = { Config = Config } }, require = req })
	local halloween = loadModule("src/shared/Halloween.luau", { script = { Parent = { Config = Config, Cycle = cycle, Economy = Economy } }, require = req })
	local winter = loadModule("src/shared/Winter.luau", { script = { Parent = { Config = Config, Economy = Economy } }, require = req })
	return loadModule("src/shared/Skins.luau", { script = { Parent = { Halloween = halloween, Winter = winter } }, require = req })
end

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

test("zakładki zawierają własne ulepszenia i po jednej karcie wspólnych ulepszeń", function()
	local seen = {}
	for _, list in {
		{ order = Config.UpgradeOrder, shop = "forest" },
		{ order = Config.CaveUpgradeOrder, shop = "cave" },
		{ order = Config.SwampUpgradeOrder, shop = "swamp" },
		{ order = Config.MountainUpgradeOrder, shop = "mountain" },
	} do
		local inTab = {}
		for _, id in list.order do
			check(Config.Upgrades[id] ~= nil, "nieznane " .. id)
			check(not inTab[id], "duplikat w zakładce " .. id)
			inTab[id] = true
			if not Config.Upgrades[id].worldCaps then
				eq(Economy.upgradeShop(id), list.shop, "sklep " .. id)
			end
			seen[id] = true
		end
		for id, def in Config.Upgrades do
			if def.worldCaps then
				check(inTab[id] == true, "brak wspólnego ulepszenia " .. id .. " w " .. list.shop)
			end
		end
	end
	for id in Config.Upgrades do
		check(seen[id] == true, "brak w kolejności: " .. id)
	end
end)

print("Bramki ulepszeń")
local NEXT_WORLD = { forest = "cave", cave = "swamp", swamp = "mountain" }
for _, world in { "forest", "cave", "swamp", "mountain" } do
	for id, def in Config.Upgrades do
		if not def.worldCaps then
			continue
		end
		test("bramka " .. id .. " w " .. world, function()
			local cap = Economy.upgradeCap(id, world)
			local data = {
				coins = 1e12,
				upgrades = { [id] = cap - 1 },
				caveUnlocked = world ~= "forest",
				swampUnlocked = world == "swamp" or world == "mountain",
				mountainUnlocked = world == "mountain",
			}
			local price = Economy.upgradeCost(id, cap - 1)
			check(Economy.buyUpgrade(data, id, world), "ostatni poziom świata do kupienia")
			eq(data.upgrades[id], cap)
			eq(data.coins, 1e12 - price, "odjęta dokładna cena")
			local before = data.coins
			local ok, reason, required = Economy.buyUpgrade(data, id, world)
			check(not ok, "następny poziom odrzucony mimo monet")
			eq(reason, if world == "mountain" then "max" else "locked")
			if world ~= "mountain" then
				eq(required, NEXT_WORLD[world])
			end
			eq(data.coins, before, "odmowa nic nie kosztuje")
			eq(data.upgrades[id], cap, "odmowa nie zmienia poziomu")
		end)
	end
end

test("bramki mają rosnące limity i ostatni limit równy maksimum", function()
	for id, def in Config.Upgrades do
		if def.worldCaps then
			check(def.worldCaps.forest > 0 and def.worldCaps.forest < def.worldCaps.cave, id)
			check(def.worldCaps.cave < def.worldCaps.swamp, id)
			check(def.worldCaps.swamp < def.worldCaps.mountain, id)
			eq(def.worldCaps.mountain, def.maxLevel, id)
		end
	end
end)

test("zakup odrzuca nieodblokowany lub niewłaściwy obóz i zachowuje saldo", function()
	local data = { coins = 1e9, upgrades = { boots = 4, crystal = 0 }, caveUnlocked = false, swampUnlocked = false }
	local ok, reason = Economy.buyUpgrade(data, "boots", "cave")
	check(not ok and reason == "locked", "teleport do jaskini nie odblokowuje poziomu")
	data.caveUnlocked = true
	ok, reason = Economy.buyUpgrade(data, "boots", "forest")
	check(not ok and reason == "location", "nowy poziom wymaga nowego obozu")
	ok, reason = Economy.buyUpgrade(data, "boots", "swamp")
	check(not ok and reason == "location", "teleport do zamkniętych bagien")
	ok, reason = Economy.buyUpgrade(data, "crystal", "forest")
	check(not ok and reason == "location", "wkład pozostaje w jaskini")
	eq(data.coins, 1e9)
	check(Economy.buyUpgrade(data, "boots", "cave"), "zakup w jaskini")
end)

test("niższe globalne poziomy można dokupić w późniejszym obozie", function()
	local data = { coins = 1000, upgrades = { boots = 0 }, caveUnlocked = true, swampUnlocked = true }
	check(Economy.buyUpgrade(data, "boots", "swamp"), "pierwszy poziom na bagnach")
	eq(data.upgrades.boots, 1)
	eq(data.coins, 1000 - Config.Upgrades.boots.costBase)
end)

test("brak pieniędzy i błędne dane nie zmieniają stanu zakupu", function()
	local data = { coins = 0, upgrades = { boots = 0 } }
	local ok, reason = Economy.buyUpgrade(data, "boots", "forest")
	check(not ok and reason == "coins", "brak monet")
	check(not Economy.buyUpgrade(data, "unknown", "forest"), "nieznane ID")
	data.coins = 1e9
	data.upgrades.boots = 0.5
	check(not Economy.buyUpgrade(data, "boots", "forest"), "poziom ułamkowy")
	eq(data.coins, 1e9)
	eq(data.upgrades.boots, 0.5)
end)

test("migracja poziomów nie odbiera starego maksimum i nie daje nowych poziomów", function()
	local levels = Economy.upgradeLevelsFromSave({ boots = 8, oil = 10, basket = 10 })
	eq(levels.boots, 8)
	eq(levels.oil, 10)
	eq(levels.basket, 10)
	local data = { coins = 1e9, upgrades = levels, caveUnlocked = false, swampUnlocked = false }
	check(not Economy.buyUpgrade(data, "boots", "forest"), "stary poziom nie omija nowej bramki")
	eq(levels.boots, 8, "kupione 28 studs/s zostaje")
	for _, value in { math.huge, -math.huge, 0 / 0, "12" } do
		eq(Economy.upgradeLevelsFromSave({ boots = value }).boots, 0, "brak darmowego maksa ze śmieci")
	end
	eq(Economy.upgradeLevelsFromSave(nil).boots, 0)
	eq(Economy.upgradeLevelsFromSave({ boots = -2 }).boots, 0)
	eq(Economy.upgradeLevelsFromSave({ boots = 2.8 }).boots, 2)
	eq(Economy.upgradeLevelsFromSave({ boots = 999 }, 5).boots, 8, "v5 nie przyznaje nowych poziomów nawet ze śmieci")
	eq(Economy.upgradeLevelsFromSave({ boots = 12 }, 6).boots, 12, "v6 zachowuje nowe poziomy")
end)

test("DataService ładuje v5 jako v7 bez utraty ekwipunku i kupionych poziomów", function()
	local players = {}
	local signal = { Connect = function() return { Disconnect = function() end } end }
	local profile = {
		Data = {
			version = 5, coins = 43210, upgrades = { boots = 8, oil = 10, basket = 10 },
			caveUnlocked = false, swampUnlocked = false,
			basket = { { s = "honey", v = "gold" } },
			planted = { { s = "porcini", t = os.time() } },
			atlas = { honey = 7, porcini = 16, bay_bolete = 31, chanterelle = 40, parasol = -3 }, receipts = { "paid-before-migration" },
			pot = 123456, potMinutes = 240, luckUntil = os.time() + 1000,
		},
		OnSessionEnd = signal, OnAfterSave = signal,
		AddUserId = function() end,
	}
	local profileStore = { New = function() return { StartSessionAsync = function() return profile end } end }
	local packages = { WaitForChild = function() return profileStore end }
	local services = {
		Players = players,
		DataStoreService = { GetDataStore = function() return {} end },
		ReplicatedStorage = { Shared = { Config = Config, Economy = Economy, Progress = Progress, Titles = Titles, Social = Social, Skins = loadSkins(), Delve = loadModule("src/shared/Delve.luau", {}) } },
	}
	local DataService = loadModule("src/server/DataService.luau", {
		game = { GetService = function(_, name) return services[name] end },
		script = { Parent = { WaitForChild = function() return packages end } },
		require = function(module) return module end,
	})
	local migrated, canSave = DataService.load({ UserId = 1234, Parent = players })
	check(canSave, "profil otwarty")
	eq(migrated.version, 7)
	eq(migrated.coins, 43210)
	eq(migrated.upgrades.boots, 8)
	eq(migrated.upgrades.oil, 10)
	eq(migrated.upgrades.basket, 10)
	eq(migrated.caveUnlocked, false, "bez darmowego odblokowania")
	eq(migrated.swampUnlocked, false)
	eq(migrated.basket[1].s, "honey")
	eq(migrated.basket[1].v, "gold")
	eq(migrated.planted[1].s, "porcini")
	eq(migrated.atlas.honey, 7)
	eq(migrated.atlas.porcini, 16, "sam kosmiczny zostaje kosmicznym (bez dopisywania niższych form)")
	eq(migrated.atlas.bay_bolete, 31, "komplet 5 form")
	eq(migrated.atlas.chanterelle, 8, "nieznane bity odcięte")
	eq(migrated.atlas.parasol, nil, "ujemna maska odrzucona")
	eq(migrated.receipts[1], "paid-before-migration")
	eq(migrated.pot, 123456, "ponowna migracja nie obcina skrzyni v5")
	eq(migrated.potMinutes, 240)
	eq(migrated.luckUntil, profile.Data.luckUntil)
	local again = DataService.load({ UserId = 1234, Parent = players })
	eq(again.version, 7)
	eq(again.upgrades.boots, 8, "migracja idempotentna")
	eq(again.coins, 43210)
end)

test("obszar sklepu uwzględnia granice mapy i wysokość", function()
	eq(Economy.upgradeCampAt(0, 3, -10), "forest")
	eq(Economy.upgradeCampAt(0, 3, 1025), "cave")
	eq(Economy.upgradeCampAt(0, 3, 2024), "swamp")
	for _, pos in { { 500, 3, 1025 }, { 0, 500, 1025 }, { 0, 3, 1200 }, { 0, 3, -500 }, { math.huge, 3, 1025 } } do
		eq(Economy.upgradeCampAt(pos[1], pos[2], pos[3]), nil, "poza obozem")
	end
end)

for _, guardian in Progress.GUARDIANS do
	test("boss " .. guardian.id .. " daje się uciec bez odblokowania następnego świata", function()
		local cap = Economy.upgradeCap("boots", guardian.world)
		local first = Progress.bootsToEscape(guardian)
		check(first ~= nil and first <= cap, "brak dostępnego poziomu ucieczki")
		check(Economy.escapes(Progress.escapeDistance(guardian), Economy.upgradeStat("boots", cap), guardian.chase), "prędkość na limicie świata")
	end)
end

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
	local cosmic = Config.Variants[4].chance
	local rainbow = Config.Variants[3].chance
	local gold = Config.Variants[2].chance
	local silver = Config.Variants[1].chance
	eq(Economy.rollVariant(0), "cosmic", "r=0")
	eq(Economy.rollVariant(cosmic - 1e-6), "cosmic", "koniec kosmicznego")
	eq(Economy.rollVariant(cosmic), "rainbow", "początek tęczy")
	eq(Economy.rollVariant(cosmic + rainbow - 1e-6), "rainbow", "koniec tęczy")
	eq(Economy.rollVariant(cosmic + rainbow), "gold", "początek złota")
	eq(Economy.rollVariant(cosmic + rainbow + gold - 1e-6), "gold", "koniec złota")
	eq(Economy.rollVariant(cosmic + rainbow + gold), "silver", "początek srebra")
	eq(Economy.rollVariant(cosmic + rainbow + gold + silver), nil, "zwykły")
	eq(Economy.rollVariant(0.99), nil, "zwykły (r~1)")
end)

test("gwarancja: wymuszona ranga daje co najmniej złoto", function()
	eq(Economy.rollVariant(0.99, 2), "gold", "zwykły -> złoto")
	eq(Economy.rollVariant(Config.Variants[4].chance + Config.Variants[3].chance + Config.Variants[2].chance + 0.001, 2), "gold", "srebro -> złoto")
	eq(Economy.rollVariant(Config.Variants[4].chance, 2), "rainbow", "tęcza zostaje tęczą")
	eq(Economy.rollVariant(0, 2), "cosmic", "kosmiczny zostaje kosmicznym")
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

test("dochód offline: pełny przez 2 h, potem 25% do 8 h", function()
	local planted = { { s = "porcini", t = 0 } }
	local perMinute = Economy.gardenIncome(planted)
	eq(Economy.offlineIncome(planted, 1, 60), perMinute, "minuta")
	eq(Economy.offlineMinutes(2 * 3600), 120, "2 h w pełni")
	eq(Economy.offlineMinutes(4 * 3600), 120 + 120 * 0.25, "4 h: dwie ostatnie za 25%")
	eq(Economy.offlineMinutes(8 * 3600), 210, "8 h = 3,5 h dochodu")
	eq(Economy.offlineMinutes(7 * 24 * 3600), 210, "tydzień = tyle co 8 h")
	eq(Economy.offlineIncome(planted, 1, 999999), perMinute * 210, "limit")
	eq(Economy.offlineIncome(planted, 1, -100), 0, "czas z przyszłości")
end)

test("x2 skrzyni: próg ceny według minut dochodu w skrzyni", function()
	eq(Economy.x2Product(14.9), nil, "za mało na ofertę")
	eq(Economy.x2Product(15), "x2s", "15 min")
	eq(Economy.x2Product(39.9), "x2s", "do 40 min")
	eq(Economy.x2Product(40), "x2m", "40 min")
	eq(Economy.x2Product(120), "x2l", "2 h")
	eq(Economy.x2Product(210), "x2l", "noc offline (3,5 h)")
	eq(Economy.x2Product(480), "x2xl", "8 h")
	eq(Economy.x2MinMinutes("x2m"), 40, "minimum progu")
	eq(Economy.x2MinMinutes("luck"), nil, "nie x2")
	local last = 0
	for _, tier in Config.ChestX2.tiers do
		local def = Config.Products[tier.product]
		check(def ~= nil, "produkt " .. tier.product)
		check(def.price ~= nil and def.price > last, "cena rośnie: " .. tier.product)
		last = def.price
	end
end)

test("skrzynia: pojemność w godzinach dochodu, pełna nic nie przyjmuje", function()
	local planted = { { s = "porcini", t = 0 } }
	local perMinute = Economy.gardenIncome(planted)
	local hours = Economy.upgradeStat("chest", 0)
	eq(hours, 2, "na start 2 h")
	eq(Economy.upgradeStat("chest", Config.Upgrades.chest.maxLevel), 8, "maks. 8 h")
	local capacity = Economy.potCapacity(planted, 1, hours)
	eq(capacity, perMinute * 120, "pojemność")
	eq(Economy.fillPot(0, 50, 100), 50, "dokłada")
	eq(Economy.fillPot(80, 50, 100), 100, "do pełna")
	eq(Economy.fillPot(100, 50, 100), 100, "pełna stoi")
	eq(Economy.fillPot(500, 50, 100), 500, "nadwyżki nie zabiera")
	eq(Economy.fillPot(0, 50, 0), 0, "pusty ogródek nic nie zbiera")
	-- AFK w grze przez dobę: najwyżej jedna pełna skrzynia
	local pot = 0
	for _ = 1, 24 * 60 do
		pot = Economy.fillPot(pot, perMinute, capacity)
	end
	eq(pot, capacity, "doba AFK = jedna skrzynia")
	-- Na 8 h nieobecności (3,5 h dochodu) wystarcza skrzynia od 4 h, czyli poziom 2
	check(Economy.potCapacity(planted, 1, Economy.upgradeStat("chest", 2)) >= Economy.offlineIncome(planted, 1, 8 * 3600), "4 h mieszczą noc")
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

test("kradzież: ochrona ogródka rośnie 25 s, 1 min, 2 min", function()
	local ladder = Config.Garden.stealProtection
	eq(ladder[1], 25)
	eq(ladder[2], 60)
	eq(ladder[3], 120)
	eq(Economy.stealProtection(1), 25, "pierwsza kradzież")
	eq(Economy.stealProtection(2), 60, "druga z rzędu")
	eq(Economy.stealProtection(3), 120, "trzecia")
	eq(Economy.stealProtection(9), 120, "dalej ostatni próg")
	eq(Economy.stealProtection(0), 25, "licznik nie schodzi poniżej pierwszego progu")
	for i = 2, #ladder do
		check(ladder[i] > ladder[i - 1], "progi rosną")
	end
	-- Kamper przy jednym ogródku (bez czasu na las): ile kradzieży w 10 minut, zamiast co 25 s
	local t, thefts = 0, 0
	while t < 600 do
		thefts += 1
		t += Economy.stealProtection(thefts)
	end
	check(thefts <= 7, "najwyżej 7 kradzieży w 10 min: " .. thefts)
end)

test("kradzież: najpierw grzyby z lasu", function()
	local need = Config.Garden.stealForestPicks
	eq(need, 5)
	eq(Economy.stealPicksLeft(0), need, "od wejścia do gry")
	eq(Economy.stealPicksLeft(need - 1), 1)
	eq(Economy.stealPicksLeft(need), 0, "może kraść")
	eq(Economy.stealPicksLeft(need + 10), 0)
	eq(Economy.stealPicksLeft(-3), need, "śmieci")
	for _, key in { "MSG_STEAL_FOREST", "GARDEN_STEAL_FOREST", "GARDEN_PROTECTED", "MSG_RACK_PROTECTED" } do
		check(csvHas(key), "tłumaczenie " .. key)
	end
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
	-- Furtka patrzy do środka polany (wzdłuż X): głębokość ogródka leży wzdłuż X, szerokość wzdłuż Z
	local halfX, halfZ = Config.Garden.depth / 2, Config.Garden.width / 2
	-- Przed dziedzińcem jest 11,5 studa na ścieżkę, skrzynię i placyk, za nim półka z reliktami (ok. 5)
	check(Config.Garden.depth >= 11.5 + 19.2 + 5, "ogródek za płytki na grządki i półkę")
	check(Config.Garden.width >= 19.2 + 6, "ogródek za wąski na dziedziniec z alejkami")
	-- Korona drzewa z obrzeża polany sięga do ok. halfWidth - 3 - 5,2 * 1,9
	local clearing = Economy.zoneHalfWidth(Config.Zones[1])
	check(clearing >= Config.ForestHalfWidth, "polana węższa niż las")
	local borderReach = clearing - 3 - 5.2 * 1.9
	for i, plot in Config.Garden.plots do
		eq(Economy.zoneIndexAt(plot.z - halfZ), 1, "ogródek " .. i .. " (przód) poza polaną")
		eq(Economy.zoneIndexAt(plot.z + halfZ), 1, "ogródek " .. i .. " (tył) poza polaną")
		check(math.abs(plot.x) + halfX < borderReach, "ogródek " .. i .. " pod drzewami z obrzeża")
		check(math.abs(plot.x) - halfX > 17, "ogródek " .. i .. " na chatce")
		-- Przed furtką (od strony środka) zostaje 7 studs wolnego miejsca, ścieżka do lasu biegnie przy x = 0
		check(math.abs(plot.x) - halfX - 7 > 4, "furtka ogródka " .. i .. " za blisko ścieżki")
		check(plot.z + halfZ < Config.Zones[2].startZ - 3, "ogródek " .. i .. " na bramie do lasu")
		for j, other in Config.Garden.plots do
			if j > i then
				local apart = math.abs(other.x - plot.x) >= halfX * 2 + 1 or math.abs(other.z - plot.z) >= halfZ * 2 + 1
				check(apart, string.format("ogródki %d i %d na sobie", i, j))
			end
		end
	end
	-- Na szerszej polanie da się kupować ulepszenia aż do ściany (obóz liczy szerokość strefy)
	eq(Economy.upgradeCampAt(clearing - 1, 3, -30), "forest", "obóz przy ścianie polany")
	eq(Economy.upgradeCampAt(clearing + 2, 3, -30), nil, "obóz za ścianą polany")
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
	local oil = Economy.upgradeStat("oil", Economy.upgradeCap("oil", "forest"))
	local speed = Economy.upgradeStat("boots", Economy.upgradeCap("boots", "forest"))
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
	-- Ogródek (prostokąt) nie może nachodzić na okrągły bruk placu (z zapasem na płot i kamienie przy furtce)
	local halfX, halfZ = Config.Garden.depth / 2, Config.Garden.width / 2
	for _, plot in Config.Garden.plots do
		local nearX = math.clamp(plaza.center.x, plot.x - halfX, plot.x + halfX)
		local nearZ = math.clamp(plaza.center.z, plot.z - halfZ, plot.z + halfZ)
		local distance = math.sqrt((nearX - plaza.center.x) ^ 2 + (nearZ - plaza.center.z) ^ 2)
		check(distance > plaza.radius + 2, "plac wchodzi na ogródek")
	end
	-- Ogródki nie nachodzą na siebie i nie stoją na chatce
	for i, a in Config.Garden.plots do
		check(math.abs(a.x) - halfX > 18 + 6, "ogródek za blisko chatki")
		check(math.abs(a.x) + halfX < Economy.zoneHalfWidth(Config.Zones[1]) - 6, "ogródek w ścianie mapy")
		for j, b in Config.Garden.plots do
			if i < j and math.abs(a.x - b.x) < Config.Garden.depth + 4 then
				check(math.abs(a.z - b.z) >= Config.Garden.width + 4, "ogródki nachodzą na siebie")
			end
		end
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
	local speed = Economy.upgradeStat("boots", Economy.upgradeCap("boots", "cave"))
	local scale = Economy.upgradeStat("rushwick", wickLevel)
	local oil = 0
	for zone = 11, deepest do
		local def = Config.Zones[zone]
		oil += 2 * (def.endZ - def.startZ) / speed * Economy.oilDrain(zone, scale)
	end
	return oil * Config.ReturnMargin
end

test("bagna: Trzęsawisko od razu, Staw dopiero z knotem z sitowia", function()
	local oil = Economy.upgradeStat("oil", Economy.upgradeCap("oil", "cave"))
	check(swampRoundTrip(11, 0) < oil, "trzęsawisko nieosiągalne po otwarciu bagien")
	check(swampRoundTrip(13, 0) > oil, "staw dostępny bez knota, brak progresu")
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

test("Utopiec: Kielichy tylko na wyspie, próg ucieczki pozostaje na butach 8", function()
	local lair = Config.UtopiecLair
	eq(Config.Zones[Economy.zoneIndexAt(lair.centerZ)].id, "pond", "wyspa poza stawem")
	check(lair.centerZ + lair.radius + 6 < Config.Zones[13].endZ, "posąg Utopca za ścianą bagien")
	local distance = lair.centerZ - Config.Zones[10].endZ
	check(not Economy.escapes(distance, Economy.upgradeStat("boots", 7), Config.Utopiec), "ucieczka za łatwa")
	check(Economy.escapes(distance, Economy.upgradeStat("boots", 8), Config.Utopiec), "brak ucieczki na dotychczasowej prędkości 28")
	for _, species in Economy.guardianSpecies("utopiec") do
		eq(Economy.guardianOf(species.id), "utopiec", species.id)
		-- Kielich wart ponad dwa razy więcej niż najlepszy zwykły grzyb bagien (inaczej nie warto ryzykować)
		local best = 0
		for _, other in Config.Species do
			if Economy.zoneWorld(other.zone) == "swamp" and not Economy.guardianOf(other.id) and not other.forgeOnly then
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

print("Tabliczki grządek (DisplayMushrooms)")
do
	-- Tłumaczenia z CSV i przełącznik języka, jak w grze (Localize)
	local strings: { [string]: { en: string, pl: string } } = {}
	for line in string.gmatch(fs.readFile("src/localization/GameStrings.csv"), "[^\n]+") do
		local cols = string.split(line, ",")
		if #cols == 5 then
			strings[cols[1]] = { en = cols[2], pl = cols[5] }
		end
	end
	local locale = "en"
	local Localize = {
		t = function(key: string): string
			local entry = strings[key]
			return if entry then entry[locale] else key
		end,
		getLocale = function(): string
			return locale
		end,
	}
	local function req(module)
		return module
	end
	local MutationText = loadModule("src/client/MutationText.luau", {
		game = { GetService = function() return { Shared = { Economy = Economy } } end },
		Color3 = roblox.Color3,
		script = { Parent = { Localize = Localize } },
		require = req,
	})
	local ClassColor = {
		of = function(id: string)
			local c = Economy.speciesClass(id).color
			return roblox.Color3.fromRGB(c[1], c[2], c[3])
		end,
		rich = function(_id: string, text: string): string
			return "<c>" .. text .. "</c>"
		end,
	}
	local services = {
		Players = { LocalPlayer = { WaitForChild = function() return {} end } },
		ReplicatedStorage = { Shared = { Economy = Economy } },
		CollectionService = {},
		Workspace = {},
	}
	local Display = loadModule("src/client/DisplayMushrooms.luau", {
		game = { GetService = function(_, name) return services[name] end },
		Color3 = roblox.Color3,
		UDim2 = roblox.UDim2,
		Vector2 = roblox.Vector2,
		Vector3 = roblox.Vector3,
		script = { Parent = { ClassColor = ClassColor, Localize = Localize, MushroomView = {}, MutationText = MutationText, UiKit = {}, UiScale = {} } },
		require = req,
	})
	local function plain(text: string): string
		return (string.gsub(text, "<[^>]+>", ""))
	end

	test("tabliczka: okaz bez wariantu (klasa tylko od rzadkiej)", function()
		eq(Display.badges("honey", nil), "", "pospolity bez oznaczeń")
		eq(Display.badges("porcini", nil), "", "niepospolity bez oznaczeń")
		local epic
		for _, species in Config.Species do
			if Economy.speciesClass(species.id).id == "epic" then
				epic = species.id
				break
			end
		end
		eq(plain(Display.badges(epic, nil)), "★ EPIC")
		eq(MutationText.traits(nil), "", "bez cech")
	end)

	test("tabliczka: tęczowy okaz z kilkoma cechami", function()
		eq(Economy.speciesClass("obsidian").id, "uncommon")
		eq(plain(Display.badges("obsidian", "rainbow")), "🌈 RAINBOW", "sam wariant, jak na przykładzie")
		eq(plain(MutationText.traits({ "abyssal", "hexed" })), "Abyssal · Hexed")
		locale = "pl"
		eq(plain(Display.badges("obsidian", "rainbow")), "🌈 TĘCZA", "polskie wielkie litery")
		eq(plain(MutationText.traits({ "abyssal", "hexed" })), "Żar Otchłani · Zaklęty")
		locale = "en"
	end)

	test("tabliczka: legendarny z wariantem i dochód z premiami", function()
		eq(plain(Display.badges("jaga_toadstool", "gold")), "★★ LEGENDARY · ⭐ GOLD")
		eq(plain(Display.badges("fern_flower", nil)), "★★★ MYTHIC", "mityczny z kuźni")
		-- Dochód na tabliczce to atrybut Rate od serwera: Economy.plantIncome z nawozem (bez zmian)
		local item = { s = "obsidian", v = "rainbow", x = { "abyssal", "hexed" } }
		local fertilizer = Economy.upgradeStat("fertilizer", 4)
		local rate = Economy.plantIncome(item, fertilizer)
		eq(rate, Economy.itemValue(item) * Config.Garden.incomeRate * fertilizer, "stawka ogródka")
		eq(Display.incomeText(3648), "+3 648 / min")
		eq(Display.incomeText(2.5), "+2.5 / min")
		locale = "pl"
		eq(Display.incomeText(2.5), "+2,5 / min", "przecinek po polsku")
		eq(Display.incomeText(1234567), "+1 234 567 / min")
		locale = "en"
	end)
end

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
	-- Rząd przycisków (język, muzyka, dźwięki, zaproś): na telefonie nie mniejszy niż 0,8
	eq(UiScale.computeRow(size(1920, 1080)), 1, "rząd: Full HD")
	eq(UiScale.computeRow(size(705, 338)), 0.8, "rząd: telefon poziomo nie maleje do 0,6")
	eq(UiScale.computeRow(size(1376, 1012)), UiScale.compute(size(1376, 1012)), "rząd: tablet jak reszta HUD")
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

test("Twój Wysyp: to samo szczęście co Wysyp serwera, a oba naraz się nie sumują", function()
	local server, serverParts = Economy.luck({ knifeLevel = 0, zone = nil, event = nil, boom = true, potion = false })
	local solo, soloParts = Economy.luck({ knifeLevel = 0, zone = nil, event = nil, boom = false, soloBoom = true, potion = false })
	local both, bothParts = Economy.luck({ knifeLevel = 0, zone = nil, event = nil, boom = true, soloBoom = true, potion = false })
	check(math.abs(solo - Config.Boom.luck) < 1e-9, "x1,5 jak Wysyp")
	eq(solo, server)
	eq(both, server, "dwa Wysypy to nadal jeden")
	eq(soloParts[1].key, "PRODUCT_BOOM_SOLO")
	eq(serverParts[1].key, "PRODUCT_BOOM")
	eq(#bothParts, 1)
	check(Config.Products.boomSolo ~= nil and Config.Products.boomSolo.id == 0, "na test: bez numeru produktu")
end)

test("grupa Old Owl Studios: +10% szczęścia w pełni, nawet przy limicie darmowych", function()
	local base = Economy.luck({ knifeLevel = 0, zone = nil, event = nil, boom = false, potion = false })
	local member, parts = Economy.luck({ knifeLevel = 0, zone = nil, event = nil, boom = false, potion = false, member = true })
	check(math.abs(member - base * Config.Community.luck) < 1e-9, "x1,1")
	eq(#parts, 1, "jedna część")
	eq(parts[1].key, "ODDS_OWL")
	local deep = Economy.luck({ knifeLevel = 8, zone = 4, event = nil, boom = false, potion = false })
	local deepMember = Economy.luck({ knifeLevel = 8, zone = 4, event = nil, boom = false, potion = false, member = true })
	check(deepMember > deep, "działa też przy limicie darmowych bonusów")
	check(deepMember <= Config.LuckBalance.maxLuck, "nie przebija maxLuck")
end)

test("paczka powitalna grupy: jak nagroda za logowanie, nie fortuna", function()
	for _, worlds in { { false, false }, { true, false }, { true, true } } do
		local scale = Progress.rewardScale(worlds[1], worlds[2])
		local gift = Progress.communityGift(worlds[1], worlds[2])
		check(gift > 0, "coś daje")
		-- nie więcej niż najlepsza nagroda za logowanie (7. dzień serii)
		check(gift <= Progress.LOGIN_REWARDS[#Progress.LOGIN_REWARDS] * scale, "najwyżej jak 7. dzień logowania: " .. gift)
	end
	eq(Progress.communityGift(false, false), Progress.rewardScale(false, false))
end)

test("tytuł Old Owl Member za dołączenie do grupy", function()
	local def = Titles.get("TITLE_OWL_MEMBER")
	check(def ~= nil, "jest na liście")
	local stats = Titles.emptyStats()
	eq(stats.owl, 0)
	local ctx = { atlas = {}, bestiary = {}, stats = stats, tutorialDone = false }
	check(not Titles.earned(ctx).TITLE_OWL_MEMBER, "bez grupy brak")
	Titles.count(stats, "owl", 1)
	check(Titles.earned(ctx).TITLE_OWL_MEMBER == true, "po dołączeniu jest")
end)

test("znajomy na serwerze: +10% szczęścia, razem z grupą się mnoży", function()
	local base = Economy.luck({ knifeLevel = 0, zone = nil, event = nil, boom = false, potion = false })
	local both, parts = Economy.luck({ knifeLevel = 0, zone = nil, event = nil, boom = false, potion = false, member = true, friend = true })
	check(math.abs(both - base * Config.Community.luck * Config.Community.friendLuck) < 1e-9, "x1,21")
	eq(#parts, 2)
	eq(parts[2].key, "ODDS_FRIEND")
end)

test("zaproszenia: każdy zaproszony raz, nie sam siebie, z limitem", function()
	local invited = {}
	check(Social.creditInvite(invited, 11, 99), "nowy się liczy")
	check(not Social.creditInvite(invited, 11, 99), "drugi raz nie")
	check(not Social.creditInvite(invited, 99, 99), "sam siebie nie")
	check(not Social.creditInvite(invited, 0, 99), "zły numer nie")
	for i = 1, Social.MAX_INVITED do
		Social.creditInvite(invited, 1000 + i, 99)
	end
	eq(#invited, Social.MAX_INVITED, "limit")
	eq(Social.referrer({ ReferredByPlayerId = 42 }), 42)
	eq(Social.referrer({ ReferredByPlayerId = 0 }), nil)
	eq(Social.referrer({ ReferredByPlayerId = "42" }), nil)
	eq(Social.referrer(nil), nil)
	eq(Social.referrer({}), nil)
end)

test("tytuł Przewodnik za zaproszonych", function()
	local stats = Titles.emptyStats()
	local ctx = { atlas = {}, bestiary = {}, stats = stats, tutorialDone = false }
	for _ = 1, Config.Community.guideInvites - 1 do
		Titles.count(stats, "invite", 1)
	end
	check(not Titles.earned(ctx).TITLE_GUIDE, "jeszcze nie")
	Titles.count(stats, "invite", 1)
	check(Titles.earned(ctx).TITLE_GUIDE == true, "jest")
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

test("głośność z suwaka: 0..1 co 5%, śmieci odrzucone", function()
	eq(Progress.normalizeVolume(0.5), 0.5, "0,5")
	eq(Progress.normalizeVolume(0.52), 0.5, "zaokrąglenie do 5%")
	eq(Progress.normalizeVolume(0.98), 1, "zaokrąglenie w górę")
	eq(Progress.normalizeVolume(-3), 0, "ujemna = 0")
	eq(Progress.normalizeVolume(7), 1, "za duża = 1")
	eq(Progress.normalizeVolume(0 / 0), nil, "NaN")
	eq(Progress.normalizeVolume(math.huge), nil, "nieskończoność")
	eq(Progress.normalizeVolume("0.5"), nil, "tekst")
	eq(Progress.normalizeVolume(nil), nil, "brak")
end)

test("każdy gatunek (poza błędnym ognikiem) jest na dokładnie jednej stronie", function()
	local seen = {}
	local pages = table.clone(Progress.PAGES)
	table.insert(pages, Progress.FORGE_PAGE)
	for _, page in pages do
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
	eq(Progress.bootsToEscape(Progress.getGuardian("utopiec") :: any), 8, "Utopiec dostępny na dotychczasowym poziomie 8")
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

test("seria logowań: Mrozik ratuje jeden opuszczony dzień, odnawia się co 7 dni serii", function()
	local streak = { day = 99, count = 5, freeze = 1 }
	eq(select(2, Progress.loginPreview(streak, 101)), 6, "podgląd z Mrozikiem")
	local cycle, frozen = Progress.claimLogin(streak, 101)
	eq(cycle, 6)
	eq(frozen, true, "Mrozik zużyty")
	eq(streak.count, 6)
	eq(streak.freeze, 0)
	-- Kolejna przerwa bez Mrozika zeruje
	local _, frozen2 = Progress.claimLogin(streak, 103)
	eq(frozen2, false)
	eq(streak.count, 1)
	-- Dwa opuszczone dni: Mrozik nie pomaga
	local long = { day = 99, count = 4, freeze = 1 }
	Progress.claimLogin(long, 102)
	eq(long.count, 1, "dwa dni przerwy")
	eq(long.freeze, 1, "Mrozik zostaje")
	-- 7. dzień serii daje Mrozika, najwyżej jeden naraz
	local week = { day = 99, count = 6, freeze = 0 }
	Progress.claimLogin(week, 100)
	eq(week.count, 7)
	eq(week.freeze, 1, "nowy Mrozik")
	local full = { day = 99, count = 13, freeze = 1 }
	Progress.claimLogin(full, 100)
	eq(full.freeze, Progress.FREEZE_MAX, "bez zapasu ponad limit")
	-- Stary zapis bez pola: brak Mrozika w tej funkcji (DataService daje jednego przy wczytaniu)
	local old = { day = 99, count = 3 }
	eq(select(2, Progress.claimLogin(old, 101)), false)
	eq(old.count, 1)
end)

test("zadania: nagroda czeka na odbiór, odbiera się raz, premia dopiero po komplecie", function()
	local daily = Progress.newDaily(3, 4)
	eq(Progress.claimQuest(daily, 1), nil, "niezrobione")
	local first = Progress.getQuest(daily.quests[1].id)
	Progress.questEvent(daily, first.kind, first.goal)
	check(daily.quests[1].done and not daily.quests[1].claimed, "zrobione, nieodebrane")
	eq(Progress.claimQuest(daily, 1), first, "odbiór")
	eq(Progress.claimQuest(daily, 1), nil, "drugi raz nic")
	check(not Progress.claimBonus(daily), "premia przed kompletem")
	for _, state in daily.quests do
		local def = Progress.getQuest(state.id)
		Progress.questEvent(daily, def.kind, def.goal)
	end
	check(daily.bonusDone and not daily.bonusClaimed, "komplet czeka")
	check(Progress.claimBonus(daily), "premia")
	check(not Progress.claimBonus(daily), "premia raz")
	eq(Progress.claimQuest(daily, 99), nil, "zły numer")
end)

test("logowanie: nagroda czeka do kliknięcia, podgląd zgadza się z odbiorem", function()
	local streak = { day = 99, count = 3 }
	check(Progress.loginReady(streak, 100), "nowy dzień = czeka")
	local cycle, count = Progress.loginPreview(streak, 100)
	eq(count, 4)
	eq(Progress.claimLogin(streak, 100), cycle, "podgląd = odbiór")
	check(not Progress.loginReady(streak, 100), "po odbiorze nie czeka")
	eq(select(2, Progress.loginPreview(streak, 103)), 1, "przerwa zeruje też w podglądzie")
	eq(select(1, Progress.loginPreview({ day = -1, count = 0 }, 5)), 1, "nowy gracz: dzień 1")
	local daily = Progress.newDaily(100, 1)
	eq(Progress.claimable(daily, streak, 100), 0)
	eq(Progress.claimable(daily, streak, 101), 1, "logowanie jutro")
	local def = Progress.getQuest(daily.quests[2].id)
	Progress.questEvent(daily, def.kind, def.goal)
	eq(Progress.claimable(daily, streak, 101), 2)
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
	for id in Config.Badges do
		Config.Badges[id] = 0 -- test niezależny od numerów już założonych odznak
	end
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

test("halloween: cel serwera dzieli wkład między cele", function()
	local target = H.goal.target
	local goal = Halloween.newGoal(1)
	local done
	done, goal = Halloween.contribute(goal, 100, target - 5, target)
	eq(#done, 0)
	eq(goal.progress, target - 5)
	-- 195 + 20 od nowego konta: do pierwszego celu idzie 5, do drugiego 15
	done, goal = Halloween.contribute(goal, 200, 20, target)
	eq(#done, 1)
	eq(done[1].id, 1)
	eq(done[1].contrib[200], 5, "do kończonego tylko reszta")
	eq(done[1].contrib[100], target - 5)
	eq(goal.id, 2)
	eq(goal.progress, 15)
	eq(goal.contrib[200], 15)
	eq(goal.contrib[100], nil, "stary wkład nie przechodzi")
	-- Jedna duża sprzedaż przez kilka progów
	done, goal = Halloween.contribute(goal, 300, target * 2 + 7, target)
	eq(#done, 2)
	eq(done[1].id, 2)
	eq(done[2].id, 3)
	eq(done[2].contrib[300], target)
	eq(goal.id, 4)
	eq(goal.progress, 22)
	-- Zero i ujemne nic nie robią
	done, goal = Halloween.contribute(goal, 1, -5, target)
	eq(#done, 0)
	eq(goal.progress, 22)
end)

test("halloween: nagroda za cel proporcjonalna i z limitem dziennym", function()
	local rules = H.goal
	eq(Halloween.goalReward(10, 0), 10 * rules.secondsPerCandy)
	eq(Halloween.goalReward(rules.target, 0), math.min(rules.target * rules.secondsPerCandy, rules.maxPerGoal))
	eq(Halloween.goalReward(100000, 0), rules.maxPerGoal, "limit na cel")
	eq(Halloween.goalReward(100000, rules.maxPerDay - 30), 30, "resztka limitu dnia")
	eq(Halloween.goalReward(100000, rules.maxPerDay), 0, "limit dnia wyczerpany")
	eq(Halloween.goalReward(0, 0), 0)
	-- Budżet celu nie rośnie od rozłożenia wkładu na wiele kont
	local solo = Halloween.goalReward(rules.target, 0)
	local split = 0
	for _ = 1, rules.target // 10 do
		split += Halloween.goalReward(10, 0)
	end
	check(split <= rules.target * rules.secondsPerCandy, "podział nie mnoży nagrody")
	check(solo <= split, "solo nie dostaje więcej niż grupa")
end)

test("halloween: ranking — kto i kiedy", function()
	check(not Halloween.rankingAllowed(5, true), "deweloper nigdy")
	check(Halloween.rankingAllowed(5, false), "zwykły gracz")
	table.insert(H.rankingBanned, 77)
	check(not Halloween.rankingAllowed(77, false), "wykluczony")
	table.remove(H.rankingBanned)
	check(H.finalizeAt > H.endsAt, "finalizacja po końcu eventu")
	check(Halloween.rankingOpen(H.endsAt + 10), "zaległe wyniki po końcu")
	check(not Halloween.rankingOpen(H.finalizeAt), "po finalizacji zamknięte")
	check(not Halloween.rankingOpen(H.startsAt - 1), "przed eventem")
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

-- ===== Zima: Zimowy Festiwal =====
print("Zima (Winter.luau)")
local Winter = loadModule("src/shared/Winter.luau", {
	script = { Parent = { Config = Config, Economy = Economy } },
	require = function(module)
		return module
	end,
})
local Skins = loadModule("src/shared/Skins.luau", {
	script = { Parent = { Halloween = Halloween, Winter = Winter } },
	require = function(module)
		return module
	end,
})
local W = Config.Winter

test("zima: okno eventu 1.12 - 6.01 (UTC) i ukrycie przed startem", function()
	eq(W.startsAt, 1796083200, "1 grudnia 2026 00:00 UTC")
	eq(W.endsAt, 1799280000, "7 stycznia 2027 00:00 UTC (6 stycznia włącznie)")
	check(W.startsAt >= Config.Halloween.endsAt, "po Halloween")
	check(not Winter.forced and Winter.devDay == nil, "podgląd z panelu DEV wyłączony")
	check(not Winter.active(W.startsAt - 1), "przed")
	check(Winter.active(W.startsAt), "start")
	check(Winter.active(W.endsAt - 1), "ostatnia sekunda")
	check(not Winter.active(W.endsAt), "po")
	-- Przed startem nic nie widać i nic się nie losuje
	local before = W.startsAt - 3600
	eq(Winter.frostChance(before, false), 0, "szron przed startem")
	eq(Winter.frostChance(before, true), 0, "Zamieć przed startem")
	eq(Winter.adventDay(before), nil, "kalendarz przed startem")
	eq(Winter.frostChance(W.endsAt, true), 0, "po evencie")
	eq(Winter.secondsLeft(W.endsAt + 50), 0)
	eq(Winter.secondsLeft(W.startsAt - 100), W.endsAt - W.startsAt, "przed startem: cały event")
	-- Podgląd w Studio włącza wszystko i daje się wyłączyć
	Winter.forced = true
	check(Winter.active(before), "podgląd")
	eq(Winter.frostChance(before, false), W.frostChance)
	Winter.forced = false
	check(not Winter.active(before), "po podglądzie")
end)

test("zima: szansa na szron i cecha frost", function()
	local t = W.startsAt + 100
	eq(Winter.frostChance(t, false), W.frostChance)
	eq(Winter.frostChance(t, true), W.boomFrostChance)
	check(W.boomFrostChance > W.frostChance, "Zamieć daje więcej")
	check(not Winter.canBeFrost("false_wisp"), "błędny ognik nie")
	check(Winter.canBeFrost("honey"), "opieńka tak")
	check(not Winter.canBeFrost("nie_ma_takiego"), "nieznany")
	local tag = Economy.getTag("frost")
	check(tag ~= nil, "getTag zna szron (zapis)")
	eq(Economy.mutationMultiplier(nil, { "frost" }), 2)
	for zone = 0, #Config.Zones do
		for _, def in Economy.tagsForZone(zone) do
			check(def.id ~= "frost", "strefa " .. zone)
		end
	end
	check(csvHas("MUT_FROST"), "tłumaczenie")
end)

test("zima: płatki zależnie od świata", function()
	local mountain
	for _, species in Config.Species do
		if Economy.zoneWorld(species.zone) == "mountain" and not species.mimic then
			mountain = species.id
			break
		end
	end
	check(mountain ~= nil, "gatunek z góry")
	eq(Winter.flakesFor({ s = "honey", x = { "frost" } }), W.flakesByWorld.forest)
	eq(Winter.flakesFor({ s = "cave_oyster", x = { "frost" } }), W.flakesByWorld.cave)
	eq(Winter.flakesFor({ s = "bog_bell", x = { "mossy", "frost" } }), W.flakesByWorld.swamp)
	eq(Winter.flakesFor({ s = mountain, x = { "frost" } }), W.flakesByWorld.mountain)
	eq(Winter.flakesFor({ s = "honey", x = { "pumpkin" } }), 0, "dynia to nie szron")
	eq(Winter.flakesFor({ s = "honey" }), 0, "bez cech")
	eq(Winter.flakesFor({ s = "false_wisp", x = { "frost" } }), 0, "ognik")
	eq(Winter.flakesForList({ { s = "honey", x = { "frost" } }, { s = "porcini" }, { s = "cave_oyster", x = { "frost" } } }), W.flakesByWorld.forest + W.flakesByWorld.cave)
	check(W.flakesByWorld.forest < W.flakesByWorld.cave and W.flakesByWorld.cave < W.flakesByWorld.swamp and W.flakesByWorld.swamp < W.flakesByWorld.mountain, "głębiej więcej")
end)

test("zima: ścieżka nagród, tytuły i odznaka", function()
	local track = Winter.TRACK
	for i = 2, #track do
		check(track[i].flakes > track[i - 1].flakes, "progi rosną")
	end
	eq(Winter.reached(0), 0)
	eq(Winter.reached(track[1].flakes - 1), 0)
	eq(Winter.reached(track[1].flakes), 1)
	eq(Winter.reached(track[#track].flakes + 999), #track)
	local steps = Winter.newSteps(0, track[3].flakes)
	eq(#steps, 3)
	eq(#Winter.newSteps(3, track[3].flakes), 0, "już odebrane")
	for _, step in track do
		if step.kind == "title" then
			local def = Titles.get(step.id)
			check(def ~= nil and def.stat == "snowflakes" and def.goal == step.flakes and def.event == "winter", "tytuł " .. tostring(step.id))
			check(csvHas(step.id :: string) and csvHas(step.id :: string .. "_HOW"), "tłumaczenie " .. tostring(step.id))
		else
			check(step.kind == "luck" or step.kind == "coins" or (step.kind == "skin" and Winter.getSkin(step.id) ~= nil), "nieznana nagroda " .. step.kind)
		end
	end
	local advent = Titles.get("TITLE_ADVENT")
	check(advent ~= nil and advent.stat == "advent" and advent.goal == W.adventTitle and advent.event == "winter", "tytuł za kalendarz")
	check(csvHas("TITLE_ADVENT") and csvHas("TITLE_ADVENT_HOW"), "tłumaczenie kalendarza")
	check(W.adventTitle <= #W.advent, "da się zdobyć")
	-- Liczniki
	local stats = Titles.emptyStats()
	eq(stats.snowflakes, 0)
	eq(stats.advent, 0)
	Titles.count(stats, "snowflake", track[1].flakes)
	eq(stats.snowflakes, track[1].flakes)
	Titles.count(stats, "advent", W.adventTitle)
	local ctx = { atlas = {}, bestiary = {}, stats = stats, tutorialDone = true }
	local earned = Titles.earned(ctx)
	check(earned.TITLE_SNOWBALL == true, "Śnieżka")
	check(earned.TITLE_ADVENT == true, "Strażnik Kalendarza")
	check(not earned.TITLE_WINTER_KING, "Król jeszcze nie")
	local source = { atlas = {}, bestiary = {}, stats = stats, caveUnlocked = false, swampUnlocked = false }
	check(not Achievements.check(source).winter2026, "odznaka jeszcze nie")
	stats.snowflakes = W.badgeFlakes
	check(Achievements.check(source).winter2026 == true, "odznaka")
	check(Config.Badges.winter2026 ~= nil, "miejsce na numer odznaki")
end)

test("zima: skórki (ścieżka, choinka, wspólna lista)", function()
	for id, def in Winter.SKINS do
		check(def.slot == "lantern" or def.slot == "knife", "slot " .. id)
		check(csvHas(def.key), "tłumaczenie " .. def.key)
		check(Skins.get(id) ~= nil and Skins.get(id).event == "winter", "na wspólnej liście " .. id)
		check(Halloween.SKINS[id] == nil, "id nie koliduje z Halloween " .. id)
	end
	local lanternAt = Winter.trackFlakesFor("ice_lantern")
	check(lanternAt ~= nil, "latarnia na ścieżce")
	check(not Winter.ownsSkin({}, (lanternAt :: number) - 1, "ice_lantern"), "jeszcze nie")
	check(Winter.ownsSkin({}, lanternAt :: number, "ice_lantern"), "z progu")
	check(Winter.ownsSkin({ "candy_cane" }, 0, "candy_cane"), "z choinki")
	check(not Winter.ownsSkin({ "pumpkin_lantern" }, 9999, "pumpkin_lantern"), "nie zimowa")
	-- Skins łączy oba eventy: każda skórka liczy się ze swojego licznika
	local stats = { candy = 0, snowflakes = lanternAt }
	check(Skins.owns({}, stats, "ice_lantern"), "zimowa z płatków")
	check(not Skins.owns({}, { candy = 9999, snowflakes = 0 }, "ice_lantern"), "cukierki nie dają zimowej")
	check(Skins.owns({ "sickle" }, stats, "sickle"), "halloweenowa z kotła")
	check(not Skins.owns({ "nope" }, stats, "nope"), "nieznana")
	local owned = Skins.owned({ "sickle" }, stats)
	eq(#owned, 2)
	eq(Skins.get(owned[1]).event, "halloween", "najpierw Halloween")
	eq(owned[2], "ice_lantern")
end)

test("zima: choinka z prezentami", function()
	local tree = W.tree
	local seen = {}
	for i = 0, 999 do
		local outcome = Winter.rollGift(i / 1000)
		seen[outcome.id] = (seen[outcome.id] or 0) + 1
		if outcome.skin then
			check(Winter.getSkin(outcome.skin) ~= nil, "skórka " .. outcome.id)
		end
	end
	for _, outcome in tree.outcomes do
		check((seen[outcome.id] or 0) > 0, "wypada " .. outcome.id)
		check(csvHas("GIFT_" .. string.upper(outcome.id)), "tłumaczenie " .. outcome.id)
	end
	check(csvHas("GIFT_SKIN_DUPE"), "tłumaczenie duplikatu")
	eq(Winter.rollGift(0).id, tree.outcomes[1].id)
	eq(Winter.rollGift(1).id, tree.outcomes[#tree.outcomes].id, "r = 1 nie wychodzi poza listę")
	local chance = Winter.treatChance()
	check(chance > 0.5 and chance < 0.75, "częściej prezent niż psikus: " .. chance)
	-- Płatki z choinki nie mogą się opłacać (wartość oczekiwana < koszt)
	local total, flakes = 0, 0
	for _, outcome in tree.outcomes do
		total += outcome.weight
		if outcome.id == "flakes" then
			flakes += outcome.weight * (outcome.amount or 0)
		end
	end
	check(flakes / total < tree.cost, "choinka nie mnoży płatków")
end)

test("zima: kalendarz adwentowy", function()
	eq(#Winter.ADVENT, 24, "24 okienka")
	for day, reward in Winter.ADVENT do
		check(reward.coins ~= nil or reward.flakes ~= nil or reward.luck ~= nil, "pusty dzień " .. day)
	end
	eq(Winter.adventDay(W.startsAt), 1, "1 grudnia")
	eq(Winter.adventDay(W.startsAt + Winter.DAY - 1), 1, "do północy UTC")
	eq(Winter.adventDay(W.startsAt + Winter.DAY), 2)
	eq(Winter.adventDay(W.startsAt + 23 * Winter.DAY + 5), 24, "Wigilia")
	eq(Winter.adventDay(W.startsAt + 24 * Winter.DAY), nil, "po Wigilii")
	eq(Winter.adventDay(W.endsAt + 5), nil, "po evencie")
	eq(Winter.secondsToNextDay(W.startsAt + 100), Winter.DAY - 100)
	check(Winter.canOpen({}, 3), "dzisiejsze")
	check(not Winter.canOpen({ 3 }, 3), "już otwarte")
	check(not Winter.canOpen({}, nil), "brak dnia")
	check(not Winter.canOpen({}, 25), "poza kalendarzem")
	-- Podgląd w Studio przestawia dzień
	Winter.devDay = 7
	eq(Winter.adventDay(W.startsAt - 5000), 7)
	Winter.devDay = nil
	eq(Winter.adventDay(W.startsAt - 5000), nil)
	for _, key in { "MSG_ADVENT_GIFT", "MSG_ADVENT_FLAKES", "MSG_ADVENT_LUCK", "MSG_ADVENT_COINS", "ADVENT_OPEN", "ADVENT_NEXT", "ADVENT_SOON", "ADVENT_DONE", "ADVENT_TITLE" } do
		check(csvHas(key), "tłumaczenie " .. key)
	end
end)

test("zima: ekran wczytywania sam przełącza motyw po dacie", function()
	local LoadingTheme = loadModule("src/first/LoadingTheme.luau", { Vector2 = roblox.Vector2, Color3 = roblox.Color3 })
	local byId = {}
	for _, entry in LoadingTheme.SCHEDULE do
		byId[entry.id] = entry
		check(LoadingTheme.themes[entry.id] ~= nil, "motyw " .. entry.id)
	end
	eq(byId.halloween.startsAt, Config.Halloween.startsAt, "daty Halloween jak w Config")
	eq(byId.halloween.endsAt, Config.Halloween.endsAt)
	eq(byId.winter.startsAt, W.startsAt, "daty Zimy jak w Config")
	eq(byId.winter.endsAt, W.endsAt)
	eq(LoadingTheme.ACTIVE, nil, "bez wymuszonego motywu")
	eq(LoadingTheme.activeAt(Config.Halloween.startsAt + 5), "halloween")
	eq(LoadingTheme.activeAt(Config.Halloween.endsAt), "forest", "po Halloween las")
	eq(LoadingTheme.activeAt(W.startsAt - 1), "forest", "przed Zimą las")
	eq(LoadingTheme.activeAt(W.startsAt), "winter")
	eq(LoadingTheme.activeAt(W.endsAt), "forest", "po Zimie las")
end)

test("zima: komunikaty i okno mają tłumaczenia", function()
	for _, key in {
		"MSG_FROST_BOOM", "MSG_FLAKES_SOLD", "MSG_FLAKES_QUEST", "MSG_WTRACK_LUCK", "MSG_WTRACK_COINS", "MSG_WTRACK_SKIN",
		"MSG_WINTER_WELCOME", "MSG_GIFT_NEED", "MSG_GIFT_SKIN_ALL", "GIFT_ACTION", "GIFT_NAME", "GIFT_SIGN", "GIFT_TREAT",
		"GIFT_TRICK", "GIFT_BAG", "WINTER_BUTTON", "WINTER_TITLE", "WINTER_ENDS", "WINTER_ENDED", "WINTER_TRACK_PROGRESS",
		"WINTER_TRACK_DONE", "WINTER_HOW_TITLE", "WINTER_HOW_FROST", "WINTER_HOW_QUEST", "WINTER_HOW_TREE",
		"WINTER_SKINS_TITLE", "WINTER_SKIN_LOCKED",
	} do
		check(csvHas(key), "brak " .. key)
	end
	check(Config.DevLiveActions.frostBoom == true, "Zamieć działa na żywo")
	check(Config.DevLiveActions.winterToggle == nil and Config.DevLiveActions.adventNext == nil, "podgląd tylko w Studio")
end)

test("las: pokolenia i przywołana Noc Dziadów", function()
	local length = Cycle.length()
	local index = 1000
	local nightStart = index * length
	local dawnStart = nightStart + Config.Cycle.nightSeconds
	local gen = Cycle.generation(nightStart + 10)
	eq(Cycle.generation(dawnStart + 1), gen + 1, "świt to nowe pokolenie")
	eq(Cycle.generation(dawnStart + length - 1), gen + 1, "do następnego świtu to samo")
	-- Zwykły świt: reset raz
	check(Cycle.shouldRegrow("dawn", gen, dawnStart + 1), "reset o świcie")
	check(not Cycle.shouldRegrow("dawn", gen + 1, dawnStart + 2), "drugi raz nie")
	-- Przywołana noc przykrywa świt: brak resetu, pokolenie serwera stare
	check(not Cycle.shouldRegrow("night", gen, dawnStart + 1), "przywołana noc odkłada reset")
	-- Przywołanie kończy się w połowie świtu: jeden reset
	check(Cycle.shouldRegrow("dawn", gen, dawnStart + 60), "reset po końcu przywołania")
	-- Przywołanie przykryło cały świt: reset dopiero o następnym świcie (raz)
	check(not Cycle.shouldRegrow("night", gen, dawnStart + length - 5), "w nocy bez resetu")
	check(Cycle.shouldRegrow("dawn", gen, dawnStart + length + 1), "następny świt")
	-- Przywracanie: ten sam albo nowszy zapis wraca, starszy i z przyszłości nie
	check(Cycle.canRestore(gen, gen, dawnStart - 5), "to samo pokolenie")
	check(Cycle.canRestore(gen + 1, gen, dawnStart + 5), "z serwera po świcie na serwer z przywołaną nocą")
	check(not Cycle.canRestore(gen, gen + 1, dawnStart + 5), "stary zapis po świcie")
	check(not Cycle.canRestore(gen + 1, gen, dawnStart - 5), "zapis z przyszłości")
	check(not Cycle.canRestore(gen + 50, gen, dawnStart + 5), "śmieci")
	-- Przejście między serwerami: A miał świt (gen+1), B z przywołaną nocą (gen) przywraca zapis,
	-- potem B dogania świt: gracz z A nie dostaje drugiego lasu, gracze B tak
	local savedA = gen + 1
	check(Cycle.canRestore(savedA, gen, dawnStart + 30), "B przywraca las z A")
	check(Cycle.shouldRegrow("dawn", gen, dawnStart + 60), "B dogania świt")
	check(not Cycle.needsRegrow(savedA, gen + 1), "gracz z A bez drugiego resetu")
	check(Cycle.needsRegrow(gen, gen + 1), "gracz B dostaje reset")
	check(Cycle.needsRegrow(nil, gen + 1), "brak zapisu")
end)

test("ranking: kolejka wyników z jednym workerem", function()
	local task = require("@lune/task")
	local ScoreQueue = loadModule("src/server/ScoreQueue.luau", { warn = print })
	local writes, inFlight, maxInFlight = {}, 0, 0
	local failOnce: { [number]: boolean } = { [3] = true }
	local banned: { [number]: boolean } = {}
	local queue = ScoreQueue.new(function(userId, score)
		inFlight += 1
		maxInFlight = math.max(maxInFlight, inFlight)
		task.wait(0.02) -- wolny DataStore
		inFlight -= 1
		if failOnce[userId] then
			failOnce[userId] = nil
			return "retry"
		end
		table.insert(writes, { userId, score })
		return "ok"
	end, function(userId)
		return not banned[userId]
	end)
	queue.push(1, 100)
	queue.push(2, 50)
	queue.push(3, 70)
	-- Spiętrzone wywołania (wyjścia graczy, pętla, zamykanie serwera) w trakcie zapisu
	task.spawn(queue.flush)
	task.spawn(queue.flush)
	queue.push(1, 150) -- nowszy wynik w trakcie
	task.spawn(queue.flush)
	task.wait(0.5)
	eq(maxInFlight, 1, "najwyżej jeden zapis naraz")
	check(not queue.busy(), "worker skończył")
	local best: { [number]: number } = {}
	local count1 = 0
	for _, w in writes do
		best[w[1]] = math.max(best[w[1]] or 0, w[2])
		if w[1] == 1 then
			count1 += 1
		end
	end
	eq(best[1], 150, "nowszy wynik nie przepadł")
	check(count1 <= 2, "bez powielania zapisów jednego konta")
	eq(best[2], 50)
	eq(queue.waiting(1), nil, "wysłane zniknęło z kolejki")
	-- Błąd jednego wpisu nie blokuje innych i wpis czeka na kolejną próbę
	eq(best[3], 70, "po ponowieniu w kolejnym przebiegu")
	-- Starszy wynik niż wysłany nie wraca do kolejki; usunięte/wykluczone konto nie jest wysyłane
	queue.push(1, 120)
	eq(queue.waiting(1), nil, "niższy niż opublikowany")
	queue.push(9, 10)
	banned[9] = true
	queue.flush()
	eq(queue.waiting(9), nil, "wykluczony wypada z kolejki")
	queue.push(8, 10)
	queue.remove(8)
	eq(queue.waiting(8), nil, "moderacja czyści kolejkę")
end)


-- ===== Ekspedycja do Głębokich Komór (Delve) =====
local Delve = loadModule("src/shared/Delve.luau", {})

test("ekspedycja: losowanie reliktu z zestawu trafia tylko w ten zestaw, rzadki ~1/10", function()
	local counts: { [string]: number } = {}
	for i = 0, 999 do
		local id = Delve.rollRelic("miner", (i + 0.5) / 1000)
		check(id ~= nil and Delve.relic(id).set == "miner", "z innego zestawu: " .. tostring(id))
		counts[id] = (counts[id] or 0) + 1
	end
	eq(counts.miner_map, 100, "rzadki 1 na 10")
	eq(counts.miner_pick, 300)
	eq(Delve.rollRelic("miner", 1), "miner_map", "skrajna liczba nie wypada poza listę")
	eq(Delve.rollRelic("nope", 0.5), nil)
end)

test("ekspedycja: duplikat daje odłamki, z odłamków składa się brakujący relikt", function()
	local save = Delve.emptySave()
	local new, shards = Delve.grant(save, "miner_pick")
	check(new and shards == 0, "pierwszy jest nowy")
	new, shards = Delve.grant(save, "miner_pick")
	check(not new and shards == 3, "zwykły duplikat = 3")
	new, shards = Delve.grant(save, "deep_fossil")
	new, shards = Delve.grant(save, "deep_fossil")
	eq(shards, 8, "rzadki duplikat = 8")
	eq(save.shards, 11)
	check(not Delve.craft(save, "miner_lamp"), "za mało odłamków (12)")
	save.shards = 12
	check(Delve.craft(save, "miner_lamp"), "składanie")
	eq(save.shards, 0)
	check(not Delve.craft(save, "miner_lamp"), "posiadanego nie składa się drugi raz")
	local _, none = Delve.grant(save, "nie_ma")
	eq(none, 0, "nieznany relikt nic nie daje")
end)

test("ekspedycja: renowacja i trzy oprawy kosztują monety i odłamki po kolei", function()
	local save = Delve.emptySave()
	Delve.grant(save, "deep_fossil")
	eq(Delve.canRestore(save, "deep_fossil", 149999), nil, "za mało monet")
	eq(Delve.canRestore(save, "deep_fossil", 150000), 150000)
	eq(Delve.canRestore(save, "miner_pick", 1e9), nil, "nieposiadany")
	eq(Delve.canFrame(save, "deep_fossil", 1e9), nil, "oprawa dopiero po renowacji")
	save.relics.deep_fossil.r = true
	eq(Delve.canRestore(save, "deep_fossil", 1e9), nil, "drugi raz się nie odnawia")
	save.shards = 4
	eq(Delve.canFrame(save, "deep_fossil", 1e9), nil, "brąz: 5 odłamków")
	save.shards = 100
	eq(Delve.canFrame(save, "deep_fossil", 1e9), 500000)
	save.relics.deep_fossil.f = 3
	eq(Delve.canFrame(save, "deep_fossil", 1e12), nil, "po złotej oprawie koniec")
	local total = 0
	for _, def in Delve.RELICS do
		total += Delve.restoreCost(def.id)
		for _, frame in Delve.FRAMES do
			total += frame.coins
		end
	end
	check(total > 50e6 and total < 100e6, "cała kolekcja to zlew rzędu 70 mln monet: " .. total)
end)

test("ekspedycja: zapis z DataStore przyjmuje tylko znane relikty i rozsądne liczby", function()
	local save = Delve.readSave({
		relics = { miner_pick = { r = true, f = 9 }, deep_pearl = { r = false, f = 2 }, hacked = { r = true, f = 3 }, [5] = {} },
		shards = -5,
		daily = 0 / 0,
	})
	eq(save.relics.miner_pick.f, 3, "oprawa przycięta")
	eq(save.relics.deep_pearl.f, 0, "bez renowacji bez oprawy")
	eq(save.relics.hacked, nil)
	eq(save.shards, 0)
	eq(save.daily, -1)
	eq(next(Delve.readSave(nil).relics), nil)
end)

test("ekspedycja: tablica ma trzy różne zlecenia, zlecenie dnia daje relikt dnia z właściwego zestawu", function()
	local seq = { 0.1, 0.9, 0.5, 0.2, 0.7, 0.99, 0.4 }
	local i = 0
	local function rand()
		i += 1
		return seq[(i - 1) % #seq + 1]
	end
	local offers = Delve.makeOffers(rand, 0, 100, false)
	eq(#offers, 3)
	local kinds, daily = {}, nil
	for _, offer in offers do
		kinds[offer.kind] = true
		check(Delve.modifier(offer.modifier).minRank <= 0, "trudny stan komór przy randze 0")
		if offer.daily then
			daily = offer
		end
	end
	check(kinds.rubble and kinds.chest and kinds.samples, "po jednym rodzaju")
	check(daily ~= nil and daily.relic == Delve.dailyRelic(100), "relikt dnia")
	eq(daily.set, Delve.relic(daily.relic).set)
	for _, offer in Delve.makeOffers(rand, 5, 100, true) do
		check(not offer.daily, "odebrane dziś = bez zlecenia dnia")
	end
	eq(Delve.dailyRelic(100), Delve.dailyRelic(100 + #Delve.RELICS), "relikt dnia krąży po całej liście")
end)

test("ekspedycja: olej w komorach starcza na kilka minut przy każdym poziomie ulepszeń", function()
	for _, oilMax in { 30, 90, 150 } do
		local perSecond = Delve.drain(oilMax, 1, false)
		eq(math.floor(oilMax / perSecond + 0.5), Delve.LANTERN_SECONDS, "pełna latarnia bez knota")
	end
	-- Maksymalny Kryształowy wkład (×0,5) podwaja czas; brodzenie w wodzie skraca
	eq(Delve.lanternSeconds(0.5), 480)
	check(Delve.drain(150, 1, true) > Delve.drain(150, 1, false) * 2, "woda pali szybciej")
	-- Dla porównania: w zwykłej Otchłani max latarnia z max wkładem to ~46 s (review Codexa)
	local abyss = Config.Zones[Economy.zoneIndexAt(1300)]
	check(150 / (abyss.oilDrain * 0.5) < 60, "Otchłań bez zmian")
	check(Delve.LANTERN_SECONDS >= 180, "odcinek między hakami to kilka minut")
end)

test("ekspedycja: komory leżą w Otchłani (świat jaskini), kopie nie nachodzą na siebie", function()
	for slot = 1, Delve.SLOTS do
		local x0, z0 = Delve.slotOrigin(slot)
		for _, section in Delve.SECTIONS do
			for _, z in { z0 - section.half, z0 + section.half } do
				local zone = Config.Zones[Economy.zoneIndexAt(z)]
				eq(zone.id, "abyss", "komory poza Otchłanią")
				check(Delve.isInside(roblox.Vector3.new(x0 + section.x1 + 1, 0, z)), "isInside")
			end
		end
		local found, lx = Delve.locate(roblox.Vector3.new(x0 + 100, 3, z0))
		eq(found, slot)
		eq(lx, 100)
		if slot > 1 then
			local prevX = Delve.slotOrigin(slot - 1)
			check(x0 - (prevX + 250) > 150, "odstęp większy niż zasięg pomocy (Expedition.HELP_RADIUS)")
		end
	end
	check(not Delve.isInside(roblox.Vector3.new(40, 3, 1395)), "zwykła Otchłań to nie komory")
	check(Delve.SLOT_X - 20 > Config.Cave.halfWidth + 60, "daleko od ścian jaskini")
	eq(Delve.sectionAt(Delve.SPOTS.blockage).id, "tunnel")
	eq(Delve.sectionAt(Delve.SPOTS.bonfire.x).id, "camp")
	eq(Delve.sectionAt(Delve.SPOTS.altar.x).id, "crypt")
	for _, hide in Delve.SPOTS.hides do
		eq(Delve.sectionAt(hide.x).id, "flooded")
	end
	check(Delve.wet(120, 0, false) and not Delve.wet(120, Delve.WALK_Y, true), "woda i kładki")
	check(Delve.wet(120, 2, true) and not Delve.wet(120, 2, false), "wysoka woda zalewa niższe miejsca")
	check(not Delve.wet(40, 0, true), "w Chodniku nie ma wody")
end)

test("ekspedycja: ranga z liczników, napisy reliktów i zleceń są w CSV", function()
	eq(Delve.rank(0), 0)
	local rank, nextGoal = Delve.rank(8)
	eq(rank, 2)
	eq(nextGoal, 15)
	eq(Delve.rank(1000), #Delve.RANKS)
	local csv = fs.readFile("src/localization/GameStrings.csv")
	local function has(key: string)
		check(string.find(csv, "\n" .. key .. ",", 1, true) ~= nil, "brak w CSV: " .. key)
	end
	for _, def in Delve.RELICS do
		has(def.key)
	end
	for _, def in Delve.KINDS do
		has(def.key)
		has(def.desc)
	end
	for _, def in Delve.MODIFIERS do
		has(def.key)
	end
	for _, key in Delve.SET_KEYS do
		has(key)
	end
	for _, section in Delve.SECTIONS do
		has(section.key)
	end
	for _, frame in Delve.FRAMES do
		has(frame.key)
	end
end)

-- ===== Kuźnia Grzybów (Moździerz Zielarki) =====

local Forge = loadModule("src/shared/Forge.luau", {
	script = { Parent = { Config = Config, Economy = Economy } },
	require = function(module)
		return module
	end,
})

local OPEN_ALL = { swampUnlocked = true, mountainUnlocked = true, jagaEscapes = 1 }

-- Grzyb przepisu o randze wariantu `rank` z samą wymaganą cechą
local function forgeInput(input: any, rank: number): any
	return { s = input.s, v = Economy.variantOfRank(rank), x = if input.tag then { input.tag } else nil }
end

test("kuźnia: ukryte przepisy i trójki strażników z istniejących gatunków, wyniki tylko z kuźni", function()
	eq(#Config.Forge.recipes, 6)
	local results = {}
	for _, recipe in Config.Forge.recipes do
		local out = Economy.getSpecies(recipe.id)
		check(out ~= nil and out.forgeOnly == true and out.class == nil, "przepis daje zwykły gatunek z kuźni: " .. recipe.id)
		check(not results[recipe.id], "jeden przepis na gatunek: " .. recipe.id)
		results[recipe.id] = true
		eq(#recipe.inputs, 3, recipe.id)
		check(recipe.world == "swamp" or recipe.world == "mountain", "świat przepisu: " .. recipe.id)
		local seen = {}
		for _, input in recipe.inputs do
			local species = Economy.getSpecies(input.s)
			check(species ~= nil and not species.forgeOnly, "składnik rośnie w świecie: " .. input.s)
			check(not seen[input.s], recipe.id .. ": trzy różne gatunki")
			seen[input.s] = true
			if input.tag then
				local tag = Economy.getTag(input.tag)
				check(tag ~= nil, "nieznana cecha " .. input.tag)
				eq(tag.zone, species.zone, input.s .. " z cechą " .. input.tag)
			end
		end
	end
	for _, special in Config.Forge.specials do
		local out = Economy.getSpecies(special.id)
		check(out ~= nil and out.forgeOnly == true and out.class ~= nil, "trójka strażników daje mityczny/sekretny: " .. special.id)
		check(not results[special.id], "jeden zestaw na gatunek: " .. special.id)
		results[special.id] = true
		eq(special.minRank, 3, "tęczowe")
		for _, set in special.sets do
			eq(#set, 3)
			local seen = {}
			for _, id in set do
				check(Economy.guardianOf(id) ~= nil, id .. " to grzyb strażnika")
				check(not seen[id], "trzech różnych strażników")
				seen[id] = true
			end
		end
	end
	eq(Economy.speciesClass("fern_flower").id, "mythic")
	eq(Economy.speciesClass("veles_eye").id, "secret")
	eq(Economy.speciesClass("utopiec_chalice").id, "legendary", "strażnicy dalej legendarni")
	for _, species in Config.Species do
		if species.forgeOnly then
			check(results[species.id] == true, "gatunek z kuźni bez przepisu: " .. species.id)
			eq(species.weight, 0, species.id .. " nie losuje się")
		end
	end
	local odds = Config.Forge.odds
	check(odds.bust > 0 and odds.lucky > 0 and odds.bust + odds.lucky < 1, "szanse skucha + szczęście < 100%")
end)

test("kuźnia: co można wrzucić do moździerza", function()
	eq((Forge.eligible({ s = "porcini", v = "gold", x = { "glowing" } })), true)
	eq(select(2, Forge.eligible({ s = "forge_mossbell" })), "FORGE_NO_FORGE_ITEM")
	eq(select(2, Forge.eligible({ s = "fern_flower", v = "rainbow" })), "FORGE_NO_FORGE_ITEM")
	eq(select(2, Forge.eligible({ s = "porcini", d = 1.5 })), "FORGE_NO_DRIED")
	eq((Forge.eligible({ s = "porcini", d = 1 })), true)
	eq(select(2, Forge.eligible({ s = "porcini", x = { "pumpkin" } })), "FORGE_NO_EVENT")
	eq(select(2, Forge.eligible({ s = "nope" })), "FORGE_WRONG_INPUT")
	eq(select(2, Forge.eligible(nil)), "FORGE_WRONG_INPUT")
	-- Grzyby strażników i błędne gatunki z lasu: można (to zwykłe grzyby w koszyku)
	eq((Forge.eligible({ s = "leszy_crown", v = "rainbow" })), true)
end)

test("kuźnia: ukryty przepis w dowolnej kolejności i tylko z dostępem do świata", function()
	local a, b, c = { s = "bay_bolete", x = { "mossy" } }, { s = "porcini", x = { "glowing" } }, { s = "bog_bell" }
	for _, order in { { a, b, c }, { c, b, a }, { b, c, a } } do
		local match = Forge.match(order, OPEN_ALL)
		check(match ~= nil and match.id == "forge_mossbell" and match.kind == "recipe", "przepis w każdej kolejności")
	end
	eq(Forge.match({ { s = "bay_bolete" }, b, c }, OPEN_ALL), nil, "bez wymaganej cechy")
	eq(Forge.match({ a, b, c }, {}), nil, "bez bagien przepis nie działa")
	local x = { s = "witch_hat", x = { "cursed" } }
	local y = { s = "hex_cluster", x = { "hexed" } }
	local z = { s = "raven_bracket" }
	eq(Forge.match({ x, y, z }, { swampUnlocked = true }), nil, "bez Łysej Góry")
	eq((Forge.match({ x, y, z }, { swampUnlocked = true, mountainUnlocked = true }) :: any).id, "forge_runemorel")
	local e1, e2, e3 = { s = "heart_of_mountain", x = { "abyssal" } }, { s = "earthstar", x = { "moonlit" } }, { s = "night_eye" }
	eq(Forge.match({ e1, e2, e3 }, { swampUnlocked = true, mountainUnlocked = true }), nil, "przed ucieczką Jadze")
	eq((Forge.match({ e1, e2, e3 }, OPEN_ALL) :: any).id, "forge_eclipsestar")
	-- Dodatkowe cechy nie przeszkadzają
	eq((Forge.match({ { s = "bay_bolete", v = "gold", x = { "mossy", "glowing" } }, b, c }, OPEN_ALL) :: any).id, "forge_mossbell")
end)

test("kuźnia: trzech tęczowych strażników = mityczny, z Babą Jagą = sekretny", function()
	local function g(id: string, v: string): any
		return { s = id, v = v }
	end
	local myth = Forge.match({ g("utopiec_chalice", "rainbow"), g("leszy_crown", "rainbow"), g("skarbnik_truffle", "cosmic") }, {})
	check(myth ~= nil and myth.id == "fern_flower" and myth.kind == "mythic", "Leszy + Skarbnik + Utopiec w tęczy")
	eq(Forge.match({ g("utopiec_chalice", "rainbow"), g("leszy_crown", "gold"), g("skarbnik_truffle", "rainbow") }, {}), nil, "złoty nie wystarczy")
	eq(Forge.match({ g("leszy_crown", "rainbow"), g("leszy_crown", "rainbow"), g("skarbnik_truffle", "rainbow") }, {}), nil, "trzech różnych")
	for _, set in { { "jaga_toadstool", "leszy_crown", "skarbnik_truffle" }, { "utopiec_chalice", "jaga_toadstool", "leszy_crown" }, { "skarbnik_truffle", "utopiec_chalice", "jaga_toadstool" } } do
		local secret = Forge.match({ g(set[1], "rainbow"), g(set[2], "rainbow"), g(set[3], "rainbow") }, {})
		check(secret ~= nil and secret.id == "veles_eye" and secret.kind == "secret", "z Jagą: sekretny " .. table.concat(set, "+"))
	end
end)

test("kuźnia: skucha, zwykły i szczęście (losowy z trzech, połączone cechy)", function()
	local items = {
		{ s = "porcini", v = "gold", x = { "glowing" } },
		{ s = "bay_bolete", v = "silver", x = { "mossy" } },
		{ s = "chanterelle" },
	}
	local preview = Forge.preview(items, OPEN_ALL)
	check(preview ~= nil, "podgląd")
	eq(preview.match, nil, "zwykłe losowanie")
	eq(preview.minRank, 0)
	eq(table.concat(preview.tags, ","), "glowing,mossy")
	eq(preview.fee, math.max(Config.Forge.minFee, math.floor(preview.inputValue * Config.Forge.feeShare + 0.5)))
	-- Granice szans
	eq(Forge.outcome(preview, 0), "bust")
	eq(Forge.outcome(preview, Config.Forge.odds.bust - 1e-9), "bust")
	eq(Forge.outcome(preview, Config.Forge.odds.bust), "lucky")
	eq(Forge.outcome(preview, Config.Forge.odds.bust + Config.Forge.odds.lucky), "normal")
	eq(Forge.outcome(preview, 0.999), "normal")
	-- Skucha: wylosowany (tu pierwszy), bez cech, najsłabszy wariant z trzech
	local bust, kind, pick = Forge.roll(preview, items, 0, 0)
	eq(kind, "bust")
	eq(pick, 1)
	eq(bust.s, "porcini")
	eq(bust.v, nil)
	eq(bust.x, nil)
	-- Zwykły: drugi grzyb ze swoim wariantem i wszystkimi cechami
	local normal, kind2, pick2 = Forge.roll(preview, items, 0.9, 0.5)
	eq(kind2, "normal")
	eq(pick2, 2)
	eq(normal.s, "bay_bolete")
	eq(normal.v, "silver")
	eq(table.concat(normal.x, ","), "glowing,mossy")
	-- Szczęście: trzeci grzyb, wariant o rangę wyżej
	local lucky, kind3, pick3 = Forge.roll(preview, items, Config.Forge.odds.bust, 0.99)
	eq(kind3, "lucky")
	eq(pick3, 3)
	eq(lucky.s, "chanterelle")
	eq(lucky.v, "silver")
	-- Kosmiczny wyżej nie skoczy
	local top = Forge.preview({ { s = "porcini", v = "cosmic" }, { s = "porcini", v = "cosmic" }, { s = "porcini", v = "cosmic" } }, OPEN_ALL)
	eq((Forge.roll(top :: any, { { s = "porcini", v = "cosmic" }, { s = "porcini", v = "cosmic" }, { s = "porcini", v = "cosmic" } }, 0.3, 0)).v, "cosmic")
	-- Za mało grzybów / zły grzyb
	eq(select(2, Forge.preview({ items[1], items[2] }, OPEN_ALL)), "FORGE_NEED_ITEMS")
	eq(select(2, Forge.preview({ items[1], items[2], { s = "forge_glasscap" } }, OPEN_ALL)), "FORGE_NO_FORGE_ITEM")
	eq(Forge.fee(0), Config.Forge.minFee)
end)

test("kuźnia: przepis i strażnicy dają gatunek z kuźni (wariant najsłabszy, w szczęściu wyżej), skucha nie", function()
	local items = { { s = "bay_bolete", v = "gold", x = { "mossy" } }, { s = "porcini", v = "rainbow", x = { "glowing" } }, { s = "bog_bell", v = "silver" } }
	local preview = Forge.preview(items, OPEN_ALL) :: any
	eq(preview.match.id, "forge_mossbell")
	local normal = Forge.roll(preview, items, 0.9, 0)
	eq(normal.s, "forge_mossbell")
	eq(normal.v, "silver")
	eq(table.concat(normal.x, ","), "glowing,mossy")
	local lucky = Forge.roll(preview, items, Config.Forge.odds.bust, 0)
	eq(lucky.s, "forge_mossbell")
	eq(lucky.v, "gold")
	local bust = Forge.roll(preview, items, 0, 0.5)
	eq(bust.s, "porcini", "skucha: losowy z wrzuconych")
	eq(bust.v, "silver")
	local guardians = { { s = "leszy_crown", v = "rainbow" }, { s = "skarbnik_truffle", v = "rainbow" }, { s = "utopiec_chalice", v = "cosmic" } }
	local gp = Forge.preview(guardians, {}) :: any
	eq(gp.match.kind, "mythic")
	eq((Forge.roll(gp, guardians, 0.9, 0)).s, "fern_flower")
	eq((Forge.roll(gp, guardians, 0.9, 0)).v, "rainbow")
	eq((Forge.roll(gp, guardians, Config.Forge.odds.bust, 0)).v, "cosmic")
end)

test("kuźnia: średnio nie zarabia — przepisy i strażnicy przy każdej randze, trójki jednego gatunku", function()
	local maxRank = Economy.maxVariantRank()
	local worst = 0
	local function checkSink(items: { any }, label: string)
		local preview = Forge.preview(items, OPEN_ALL)
		check(preview ~= nil, label .. ": podgląd")
		local ev = Forge.expectedValue(preview :: any, items)
		local ratio = ev / ((preview :: any).inputValue + (preview :: any).fee)
		worst = math.max(worst, ratio)
		check(ratio <= Config.Forge.maxReturn + 1e-6, string.format("%s: średni wynik %.0f > %.2f × (wrzucone + opłata) (%.3f)", label, ev, Config.Forge.maxReturn, ratio))
	end
	for _, recipe in Config.Forge.recipes do
		for r1 = 0, maxRank do
			for r2 = 0, maxRank do
				for r3 = 0, maxRank do
					local ranks = { r1, r2, r3 }
					local items = {}
					for slot, input in recipe.inputs do
						table.insert(items, forgeInput(input, ranks[slot]))
					end
					checkSink(items, recipe.id .. string.format(" %d/%d/%d", r1, r2, r3))
				end
			end
		end
	end
	for _, special in Config.Forge.specials do
		for _, set in special.sets do
			for r1 = 3, maxRank do
				for r2 = 3, maxRank do
					for r3 = 3, maxRank do
						checkSink({ { s = set[1], v = Economy.variantOfRank(r1) }, { s = set[2], v = Economy.variantOfRank(r2) }, { s = set[3], v = Economy.variantOfRank(r3) } }, special.id)
					end
				end
			end
		end
	end
	-- Trzy grzyby jednego gatunku i rangi, z cechami swojej strefy albo bez
	for _, species in Config.Species do
		if not species.forgeOnly and not species.mimic then
			local zoneTags = Economy.tagsForZone(species.zone)
			for rank = 0, maxRank do
				local v = Economy.variantOfRank(rank)
				checkSink({ { s = species.id, v = v }, { s = species.id, v = v }, { s = species.id, v = v } }, species.id .. " x3")
				if zoneTags[1] then
					local tag = zoneTags[1].id
					checkSink({ { s = species.id, v = v, x = { tag } }, { s = species.id, v = v, x = { tag } }, { s = species.id, v = v } }, species.id .. " x3 z cechą")
				end
			end
		end
	end
	check(worst > 0.5, string.format("najlepszy przypadek %.2f: kuźnia nie powinna być też zupełnie bez sensu", worst))
end)

test("kuźnia: wiele cech doklejonych do drogiego grzyba podnosi opłatę (przypadek z przeglądu Codexa)", function()
	local items = {
		{ s = "night_eye", v = "rainbow" },
		{ s = "ember", x = { "mossy", "glowing", "crystal", "abyssal" } },
		{ s = "earthstar", x = { "cursed", "hexed", "moonlit" } },
	}
	local preview = Forge.preview(items, OPEN_ALL) :: any
	check(preview ~= nil, "podgląd")
	eq(preview.match, nil)
	eq(#preview.tags, 7, "wszystkie cechy")
	eq(preview.feeRaised, true, "opłata podniesiona")
	check(preview.fee > Forge.fee(preview.inputValue), "wyższa niż 30% wkładu")
	local ratio = Forge.expectedValue(preview, items) / (preview.inputValue + preview.fee)
	check(ratio <= Config.Forge.maxReturn + 1e-6, string.format("EV %.3f", ratio))
	-- Zwykłe trójki płacą zwykłą opłatę
	local plain = { { s = "porcini", v = "gold", x = { "glowing" } }, { s = "bay_bolete", x = { "mossy" } }, { s = "chanterelle" } }
	local pp = Forge.preview(plain, OPEN_ALL) :: any
	eq(pp.feeRaised, false)
	eq(pp.fee, Forge.fee(pp.inputValue))
	-- Przepis z podstawowych składników też zwykła opłata
	local recipe = Config.Forge.recipes[1]
	local rItems = {}
	for _, input in recipe.inputs do
		table.insert(rItems, forgeInput(input, 0))
	end
	eq((Forge.preview(rItems, OPEN_ALL) :: any).feeRaised, false, "przepis bez podwyżki")
end)

test("kuźnia: gatunki z kuźni nie rosną, nie sadzą się i nie liczą do stron Grzybopedii", function()
	for zone = 1, #Config.Zones do
		for _, species in Economy.speciesForZone(zone) do
			check(not species.forgeOnly, "kuźnia w puli strefy " .. zone)
		end
		for i = 0, 999 do
			local species = Economy.rollSpecies(zone, i / 1000)
			check(species == nil or not species.forgeOnly, "wylosowano gatunek z kuźni w strefie " .. zone)
		end
	end
	local item = { s = "forge_glasscap", v = "gold", x = { "crystal", "glowing" } }
	eq(Economy.plantIncome(item), 0, "kuźnia nie daje dochodu z grządki")
	eq(#Economy.planPlanting({ item, { s = "fern_flower", v = "rainbow" } }, {}, 10), 0, "kuźni nie sadzimy")
	check(Economy.itemValue(item) > 0, "grzyb z kuźni da się sprzedać")
	for _, page in Progress.PAGES do
		for _, species in Progress.pageSpecies(page) do
			check(not species.forgeOnly, "kuźnia na stronie " .. page)
		end
	end
	eq(#Progress.pageSpecies(Progress.FORGE_PAGE), 8)
	eq(Progress.pageOf("fern_flower"), Progress.FORGE_PAGE)
	local atlas = {}
	for _, species in Progress.pageSpecies(Progress.FORGE_PAGE) do
		atlas[species.id] = 31
	end
	eq(Progress.atlasBonus(atlas), Progress.atlasBonus({}), "premia bez zmian")
	local found, total = Progress.forgeFound(atlas)
	eq(found, 6, "przepisy")
	eq(total, 6)
	local all, allTotal = Progress.forgeFound(atlas, true)
	eq(all, 8, "z mitycznym i sekretnym")
	eq(allTotal, 8)
	eq((Progress.forgeFound({ fern_flower = 1 })), 0, "mityczny nie liczy się do przepisów")
end)

test("kuźnia: tytuły, odznaki i napisy w CSV", function()
	local csv = fs.readFile("src/localization/GameStrings.csv")
	local function has(key: string)
		check(string.find(csv, "\n" .. key .. ",", 1, true) ~= nil, "brak w CSV: " .. key)
	end
	for _, species in Progress.pageSpecies(Progress.FORGE_PAGE) do
		has(species.key)
	end
	for _, class in Config.SpecialClasses do
		has(class.key)
	end
	for _, key in { "FORGE_TITLE", "PROMPT_FORGE", "ATLAS_PAGE_FORGE", "ATLAS_FORGE_SUMMARY", "ATLAS_FORGE_INFO", "ATLAS_HINT_RECIPE", "ATLAS_HINT_MYTHIC", "ATLAS_HINT_SECRET", "FORGE_NO_PLANT", "FORGE_WRONG_INPUT", "FORGE_NO_EVENT", "FORGE_NO_DRIED", "FORGE_NO_FORGE_ITEM", "FORGE_NO_COINS", "FORGE_COOLDOWN", "FORGE_UNSAFE", "FORGE_FAR", "FORGE_CHANGED", "FORGE_NEED_ITEMS" } do
		has(key)
	end
	for _, kind in { "BUST", "DONE", "LUCKY", "RECIPE", "MYTHIC", "SECRET" } do
		has("MSG_FORGE_" .. kind)
	end
	for _, kind in { "BUST", "NORMAL", "LUCKY", "RECIPE", "RECIPE_LUCKY", "MYTHIC", "SECRET" } do
		has("FORGE_OUT_" .. kind)
	end
	for _, id in { "TITLE_FORGE_APPRENTICE", "TITLE_FORGE_MASTER", "TITLE_FERN_FLOWER", "TITLE_VELES" } do
		has(id)
		has(id .. "_HOW")
	end
	check(Config.Badges.forge_first ~= nil and Config.Badges.forge_collection ~= nil, "odznaki kuźni w Config")
	-- Tytuły mitycznego i sekretnego liczą się z Grzybopedii
	local ctx = { atlas = { fern_flower = 8 }, stats = Titles.emptyStats(), bestiary = {} }
	local earned = Titles.earned(ctx :: any)
	eq(earned.TITLE_FERN_FLOWER, true)
	eq(earned.TITLE_VELES, nil)
end)

print(string.format("\n%d ok, %d błędów", passed, failed))
if failed > 0 then
	process.exit(1)
end
