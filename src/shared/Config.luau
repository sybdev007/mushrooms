--!strict
-- Wszystkie liczby balansu w jednym miejscu.
-- Zmieniasz balans tutaj, a nie w kodzie systemów.
-- Ten moduł nie używa API Robloxa, więc da się go testować w Lune.

export type ZoneDef = {
	id: string,
	key: string, -- klucz tłumaczenia (src/localization/GameStrings.csv)
	startZ: number, -- strefa zaczyna się na tej współrzędnej Z (studs)
	endZ: number,
	oilDrain: number, -- ile oleju na sekundę zużywa latarnia w tej strefie
	darkness: number, -- 0 = jasno, 1 = całkowity mrok
	spotCount: number, -- ile miejsc na grzyby jest w strefie
	treeCount: number,
}

export type SpeciesDef = {
	id: string,
	key: string,
	zone: number, -- indeks strefy z Config.Zones
	value: number, -- cena za sztukę w monetach
	weight: number, -- szansa wylosowania względem innych grzybów w tej strefie
	cap: { number }, -- kolor kapelusza {r, g, b} (serwer rysuje nim grzyby na suszarniach)
	grove: boolean?, -- rośnie tylko w Gnieździe Leszego, nie losuje się w zwykłych miejscach
}

export type UpgradeDef = {
	key: string,
	base: number, -- wartość statystyki na poziomie 0
	step: number, -- przyrost na poziom
	maxLevel: number,
	costBase: number, -- koszt pierwszego poziomu
	costGrowth: number, -- mnożnik kosztu na każdy kolejny poziom
}

local Config = {}

-- Las ciągnie się wzdłuż osi +Z od chatki. Indeks 1 to zawsze bezpieczna chatka.
Config.Zones = {
	{
		id = "cabin",
		key = "ZONE_CABIN",
		startZ = -60,
		endZ = 40,
		oilDrain = 0,
		darkness = 0,
		spotCount = 0,
		treeCount = 0,
	},
	{
		id = "edge",
		key = "ZONE_EDGE",
		startZ = 40,
		endZ = 160,
		oilDrain = 1.0,
		darkness = 0.35,
		spotCount = 18,
		treeCount = 45,
	},
	{
		id = "thicket",
		key = "ZONE_THICKET",
		startZ = 160,
		endZ = 300,
		oilDrain = 1.8,
		darkness = 0.7,
		spotCount = 14,
		treeCount = 75,
	},
	{
		id = "ravine",
		key = "ZONE_RAVINE",
		startZ = 300,
		endZ = 460,
		oilDrain = 3.0,
		darkness = 1.0,
		spotCount = 10,
		treeCount = 95,
	},
} :: { ZoneDef }

Config.ForestHalfWidth = 70 -- las ma szerokość 2 * 70 studs
Config.OilRefillPerSecond = 25 -- tankowanie latarni w chatce
Config.OilWarnFraction = 0.5 -- pierwsze, spokojne ostrzeżenie: połowa oleju za tobą
Config.OilLowFraction = 0.25 -- pilne ostrzeżenie: latarnia zaczyna migać
-- „Wracaj teraz”: olej potrzebny na drogę do chatki × ten zapas >= olej w latarni
Config.ReturnMargin = 1.3

Config.PickRadiusClient = 8 -- z jakiej odległości klient podświetla grzyb
Config.PickRadiusServer = 12 -- serwer jest łagodniejszy przez opóźnienie sieci
Config.PickCooldown = 0.15 -- minimalny odstęp między zbiorami (anty-spam)
Config.RespawnSeconds = 90 -- po ilu sekundach grzyb odrasta w tym samym miejscu

Config.GoldenChance = 0.03 -- szansa na złotą mutację
Config.GoldenMultiplier = 3

Config.EngulfLossFraction = 1 -- jaką część koszyka zabiera las, gdy zgaśnie latarnia (1 = wszystko)

Config.StartingCoins = 0

Config.SpotSeed = 2026 -- ziarno losowania miejsc na grzyby (stała mapa)

Config.Species = {
	-- Skraj lasu
	{ id = "honey", key = "MUSH_HONEY", zone = 2, value = 4, weight = 50, cap = { 196, 150, 80 } },
	{ id = "chanterelle", key = "MUSH_CHANTERELLE", zone = 2, value = 6, weight = 35, cap = { 240, 170, 40 } },
	{ id = "slippery_jack", key = "MUSH_SLIPPERY_JACK", zone = 2, value = 9, weight = 15, cap = { 150, 95, 45 } },
	-- Gęstwina
	{ id = "bay_bolete", key = "MUSH_BAY_BOLETE", zone = 3, value = 16, weight = 50, cap = { 110, 70, 40 } },
	{ id = "parasol", key = "MUSH_PARASOL", zone = 3, value = 24, weight = 32, cap = { 215, 195, 160 } },
	{ id = "saffron_milk_cap", key = "MUSH_SAFFRON", zone = 3, value = 34, weight = 18, cap = { 230, 110, 40 } },
	-- Mroczny Jar
	{ id = "aspen_bolete", key = "MUSH_ASPEN", zone = 4, value = 50, weight = 55, cap = { 205, 72, 30 } },
	{ id = "porcini", key = "MUSH_PORCINI", zone = 4, value = 75, weight = 38, cap = { 140, 90, 50 } },
	{ id = "glowing_agaric", key = "MUSH_GLOWING", zone = 4, value = 160, weight = 7, cap = { 230, 40, 40 } },
	-- Gniazdo Leszego (na końcu Jaru): zerwanie budzi Leszego
	{ id = "leszy_crown", key = "MUSH_LESZY_CROWN", zone = 4, value = 220, weight = 0, cap = { 120, 255, 190 }, grove = true },
} :: { SpeciesDef }

Config.Upgrades = {
	lantern = { key = "UPG_LANTERN", base = 14, step = 4, maxLevel = 8, costBase = 25, costGrowth = 1.6 },
	oil = { key = "UPG_OIL", base = 30, step = 12, maxLevel = 10, costBase = 20, costGrowth = 1.55 },
	basket = { key = "UPG_BASKET", base = 5, step = 3, maxLevel = 10, costBase = 15, costGrowth = 1.5 },
	boots = { key = "UPG_BOOTS", base = 16, step = 1.5, maxLevel = 8, costBase = 30, costGrowth = 1.65 },
	-- Kłódka na suszarni: ile sekund złodziej musi trzymać przycisk kradzieży
	lock = { key = "UPG_LOCK", base = 2, step = 1, maxLevel = 6, costBase = 60, costGrowth = 1.7 },
} :: { [string]: UpgradeDef }

-- Kolejność przycisków ulepszeń w chatce
Config.UpgradeOrder = { "lantern", "oil", "basket", "boots", "lock" }

-- ===== Gniazdo Leszego =====
-- Polana na końcu Mrocznego Jaru z kręgiem kamieni i grzybami „Korona Leszego”.
-- Zerwanie takiego grzyba budzi Leszego, który goni gracza aż do chatki.
Config.Grove = {
	centerX = 0,
	centerZ = 425,
	radius = 16, -- krąg kamieni; w środku nic nie rośnie poza grzybami gniazda
	spots = 3,
	spotRadius = 6, -- grzyby leżą na okręgu o tym promieniu wokół środka
	respawnSeconds = 240, -- każdy gracz ma własne korony, odrastają wolniej niż zwykłe grzyby
}

Config.Leszy = {
	speed = 22, -- studs/s; gracz na butach poz. 3 (20,5) jeszcze ucieka z gniazda, na poz. 2 już nie
	wakeDelay = 2, -- tyle sekund Leszy się budzi, zanim ruszy
	catchRadius = 4, -- z tej odległości łapie
	giveUpSeconds = 45, -- dłużej nie goni (np. gracz utknął za kamieniem)
}

-- ===== Suszarnie przed chatką =====
-- Każdy gracz dostaje suszarnię. Grzyby schną i zyskują na wartości,
-- ale inni gracze mogą je podkraść, gdy właściciel nie pilnuje.
Config.Drying = {
	slots = 6,
	seconds = 600, -- po tylu sekundach grzyb jest w pełni suchy (schnie też, gdy gracz jest offline)
	bonus = 1, -- w pełni suchy grzyb jest wart (1 + bonus) razy więcej
	stealCooldown = 25, -- po kradzieży suszarnia jest chroniona przez tyle sekund
	thiefCooldown = 8, -- ten sam złodziej może kraść co tyle sekund
	promptDistance = 9,
	-- Miejsca na suszarnie na polanie wokół chatki. Ile miejsc, tylu graczy ma suszarnię,
	-- więc ustaw rozmiar serwera w ustawieniach gry na tyle samo (8).
	plots = {
		{ x = -22, z = -28 },
		{ x = 22, z = -28 },
		{ x = -24, z = -8 },
		{ x = 24, z = -8 },
		{ x = -22, z = 12 },
		{ x = 22, z = 12 },
		{ x = -13, z = 28 },
		{ x = 13, z = 28 },
	},
}

return Config
