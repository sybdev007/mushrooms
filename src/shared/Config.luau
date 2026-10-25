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
	world: string, -- "forest" albo "cave": osobne światy połączone portalem
	safe: boolean?, -- chatka / obozowisko: olej się nie pali, można tankować i handlować
	fog: { number }?, -- kolor mgły w mroku (domyślnie nocny granat lasu)
	fireflies: number?, -- świetliki (w jaskini: pyłki) na sekundę wokół gracza
	mist: number?, -- mgiełka przy ziemi
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
	shop: string?, -- gdzie się kupuje: "forest" (chatka, domyślnie) albo "cave" (obozowisko)
}

local Config = {}

-- Las ciągnie się wzdłuż osi +Z od chatki. Indeks 1 to zawsze bezpieczna chatka.
-- Za lasem, daleko dalej na osi Z, leży Jaskinia (osobny świat, wejście przez portal za Leszym).
-- Strefy jaskini też idą wzdłuż +Z, więc cała logika stref (olej, mrok, powrót) działa tak samo.
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
		world = "forest",
		safe = true,
		fireflies = 5,
		mist = 0,
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
		world = "forest",
		fireflies = 9,
		mist = 0.5,
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
		world = "forest",
		fireflies = 12,
		mist = 2.5,
	},
	{
		id = "ravine",
		key = "ZONE_RAVINE",
		startZ = 300,
		endZ = 490, -- za Gniazdem Leszego jest jeszcze kawałek drogi do portalu jaskini
		oilDrain = 3.0,
		darkness = 1.0,
		spotCount = 10,
		treeCount = 95,
		world = "forest",
		fireflies = 4,
		mist = 6,
	},
	-- ===== Jaskinia =====
	{
		id = "camp",
		key = "ZONE_CAMP",
		startZ = 1000,
		endZ = 1040,
		oilDrain = 0,
		darkness = 0.55,
		spotCount = 0,
		treeCount = 0,
		world = "cave",
		safe = true,
		fog = { 40, 30, 22 },
		fireflies = 3,
		mist = 0,
	},
	{
		id = "crystal",
		key = "ZONE_CRYSTAL",
		startZ = 1040,
		endZ = 1160,
		oilDrain = 3.0,
		darkness = 0.8,
		spotCount = 16,
		treeCount = 0,
		world = "cave",
		fog = { 18, 22, 44 },
		fireflies = 6,
		mist = 0.5,
	},
	{
		id = "lake",
		key = "ZONE_LAKE",
		startZ = 1160,
		endZ = 1290,
		oilDrain = 4.5,
		darkness = 0.9,
		spotCount = 13,
		treeCount = 0,
		world = "cave",
		fog = { 10, 26, 34 },
		fireflies = 4,
		mist = 4,
	},
	{
		id = "abyss",
		key = "ZONE_ABYSS",
		startZ = 1290,
		endZ = 1420,
		oilDrain = 6.5,
		darkness = 1.0,
		spotCount = 10,
		treeCount = 0,
		world = "cave",
		fog = { 30, 8, 12 },
		fireflies = 2,
		mist = 7,
	},
} :: { ZoneDef }

-- Jaskinia: portal za Gniazdem Leszego, otwiera się graczom z co najmniej unlockCoins monet.
-- Raz otwarty zostaje otwarty (zapisywane), nawet gdy potem wydasz monety.
Config.Cave = {
	unlockCoins = 50000,
	halfWidth = 46, -- jaskinia jest węższa niż las
	ceiling = 34, -- wysokość stropu
	portal = { x = 0, z = 476 }, -- portal w lesie, kawałek za Gniazdem Leszego
	-- Skrót za chatką: działa tylko dla tych, którzy już raz doszli do portalu za Leszym.
	-- Stoi na widoku, żeby nowi gracze widzieli, że jest coś do odkrycia.
	shortcut = { x = 0, z = -47 },
	returnPortal = { x = 0, z = 1010 }, -- portal powrotny w obozowisku (prowadzi do chatki)
	camp = { x = 0, z = 1025 }, -- tu ląduje gracz po przejściu i po zgaśnięciu latarni w jaskini
	portalRadius = 4,
	-- Rama portali: kamienny łuk z mchem i muchomorami (siatka wygenerowana w Studio, asset na koncie Toma).
	-- size = rozmiar w studs, opening = szerokość i wysokość otworu, pillarWidth = grubość filaru do kolizji.
	portalMesh = {
		mesh = "rbxassetid://122151632379414",
		texture = "rbxassetid://77667100215068",
		size = { 17, 16, 6 },
		opening = { 9.6, 12 },
		pillarWidth = 3,
	},
}

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

-- ===== Mutacje =====
-- Każdy grzyb ma najwyżej jeden WARIANT (losowany przy odrastaniu) i dowolną liczbę CECH
-- zależnych od miejsca. Wartość = baza × wariant × (1 + Σ(cecha − 1)) × suszenie.
-- Cechy się sumują, a nie mnożą, żeby ceny nie uciekały w kosmos jak w Grow a Garden.
-- Losowość jest tylko z gry (nic za Robuxy), więc nie trzeba publikować szans.
export type VariantDef = {
	id: string,
	key: string, -- etykieta w języku gracza (CSV)
	icon: string,
	chance: number,
	mult: number,
	rank: number, -- 1 = najpospolitszy; od rangi 2 wzwyż grzyb liczy się jako „rzadki”
	color: { number },
}

export type TagDef = {
	id: string,
	key: string,
	icon: string,
	zone: number, -- cecha pojawia się tylko w tej strefie
	chance: number,
	mult: number,
	color: { number },
}

Config.Variants = {
	{ id = "silver", key = "MUT_SILVER", icon = "🥈", chance = 0.06, mult = 1.5, rank = 1, color = { 214, 224, 238 } },
	{ id = "gold", key = "MUT_GOLD", icon = "⭐", chance = 0.025, mult = 3, rank = 2, color = { 255, 205, 50 } },
	{ id = "rainbow", key = "MUT_RAINBOW", icon = "🌈", chance = 0.004, mult = 8, rank = 3, color = { 255, 110, 210 } },
} :: { VariantDef }

Config.Tags = {
	{ id = "mossy", key = "MUT_MOSSY", icon = "🌿", zone = 3, chance = 0.08, mult = 1.5, color = { 110, 176, 72 } },
	{ id = "glowing", key = "MUT_GLOWING", icon = "✨", zone = 4, chance = 0.1, mult = 2, color = { 110, 255, 214 } },
	{ id = "crystal", key = "MUT_CRYSTAL", icon = "💎", zone = 7, chance = 0.1, mult = 2, color = { 120, 200, 255 } },
	{ id = "abyssal", key = "MUT_ABYSSAL", icon = "🔥", zone = 8, chance = 0.08, mult = 2.5, color = { 255, 90, 60 } },
} :: { TagDef }

-- Ukryta gwarancja: po tylu odrostach bez Złota (albo lepszego) następny grzyb jest co najmniej złoty
Config.PityRolls = 60
-- Od tej rangi znalezisko jest ogłaszane całemu serwerowi
Config.AnnounceRank = 3

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
	-- Kryształowe Korytarze
	{ id = "cave_oyster", key = "MUSH_CAVE_OYSTER", zone = 6, value = 110, weight = 50, cap = { 196, 200, 214 } },
	{ id = "crystal_cap", key = "MUSH_CRYSTAL_CAP", zone = 6, value = 170, weight = 35, cap = { 120, 210, 255 } },
	{ id = "amethyst", key = "MUSH_AMETHYST", zone = 6, value = 260, weight = 15, cap = { 170, 100, 255 } },
	-- Podziemne Jezioro
	{ id = "lake_cap", key = "MUSH_LAKE_CAP", zone = 7, value = 300, weight = 50, cap = { 60, 170, 200 } },
	{ id = "pearl", key = "MUSH_PEARL", zone = 7, value = 420, weight = 35, cap = { 240, 236, 255 } },
	{ id = "lantern_shroom", key = "MUSH_LANTERN_SHROOM", zone = 7, value = 600, weight = 15, cap = { 255, 200, 90 } },
	-- Otchłań
	{ id = "ember", key = "MUSH_EMBER", zone = 8, value = 700, weight = 50, cap = { 255, 110, 40 } },
	{ id = "obsidian", key = "MUSH_OBSIDIAN", zone = 8, value = 950, weight = 38, cap = { 50, 40, 60 } },
	{ id = "heart_of_mountain", key = "MUSH_HEART", zone = 8, value = 2200, weight = 12, cap = { 255, 40, 90 } },
} :: { SpeciesDef }

Config.Upgrades = {
	lantern = { key = "UPG_LANTERN", base = 14, step = 4, maxLevel = 8, costBase = 25, costGrowth = 1.6 },
	oil = { key = "UPG_OIL", base = 30, step = 12, maxLevel = 10, costBase = 20, costGrowth = 1.55 },
	basket = { key = "UPG_BASKET", base = 5, step = 3, maxLevel = 10, costBase = 15, costGrowth = 1.5 },
	boots = { key = "UPG_BOOTS", base = 16, step = 1.5, maxLevel = 8, costBase = 30, costGrowth = 1.65 },
	-- Kłódka na suszarni: ile sekund złodziej musi trzymać przycisk kradzieży
	lock = { key = "UPG_LOCK", base = 2, step = 1, maxLevel = 6, costBase = 60, costGrowth = 1.7 },
	-- Obozowisko w jaskini. Kryształowy wkład: mnożnik spalania oleju w jaskini (1 = bez zmian)
	crystal = { key = "UPG_CRYSTAL", base = 1, step = -0.1, maxLevel = 5, costBase = 3000, costGrowth = 1.8, shop = "cave" },
	-- Plecak górnika: tyle dodatkowych miejsc w koszyku
	pack = { key = "UPG_PACK", base = 0, step = 4, maxLevel = 6, costBase = 2500, costGrowth = 1.7, shop = "cave" },
} :: { [string]: UpgradeDef }

-- Kolejność przycisków ulepszeń: w chatce i w obozowisku w jaskini
Config.UpgradeOrder = { "lantern", "oil", "basket", "boots", "lock" }
Config.CaveUpgradeOrder = { "crystal", "pack" }

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

-- Skarbiec Leszego: korony odebrane złapanym graczom leżą w środku gniazda
-- i może je zabrać każdy (pierwszy, który zdąży). Zabranie znów budzi Leszego.
Config.Hoard = {
	maxItems = 9, -- więcej się nie zmieści, nadmiar przepada
	radius = 2.6, -- korony leżą w kółku wokół środka gniazda
	takeDistance = 12, -- serwer sprawdza odległość gracza od korony
}

-- Stanowiska w chatce. Olej leje się tylko przy beczce, a sprzedaż i ulepszenia działają
-- tylko przy ladzie. x, z = środek kręgu na podłodze, radius = promień kręgu (studs).
export type StationDef = { kind: string, world: string, x: number, z: number, radius: number }
Config.Stations = {
	-- Chatka
	{ kind = "oil", world = "forest", x = -8.6, z = -17.2, radius = 3.3 },
	{ kind = "shop", world = "forest", x = -5, z = -28.2, radius = 4 },
	-- Obozowisko w jaskini
	{ kind = "oil", world = "cave", x = -13, z = 1022, radius = 3.6 },
	{ kind = "shop", world = "cave", x = 13, z = 1022, radius = 4 },
} :: { StationDef }
Config.StationTolerance = 2 -- serwer jest łagodniejszy przez opóźnienie sieci

-- Komendy deweloperskie na czacie (np. /coins 1000000) działają w Studio
-- oraz w prawdziwej grze dla tych kont. Dopisz tu UserId Miłosza.
Config.DevUserIds = {
	1293490018, -- Tom
}

-- Kamera: bez limitu dało się oddalić widok i oglądać las z góry
Config.CameraMaxZoom = 22

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
	promptDistance = 10,
	-- Każdy gracz ma własny ogródek z suszarnią: po cztery z każdej strony chatki,
	-- furtką do ścieżki prowadzącej do lasu. Ile ogródków, tylu graczy ma suszarnię,
	-- więc ustaw rozmiar serwera na tyle samo (8).
	gardenSize = 18,
	plots = {
		{ x = -38, z = -35 },
		{ x = 38, z = -35 },
		{ x = -38, z = -15 },
		{ x = 38, z = -15 },
		{ x = -38, z = 5 },
		{ x = 38, z = 5 },
		{ x = -38, z = 25 },
		{ x = 38, z = 25 },
	},
}

return Config
