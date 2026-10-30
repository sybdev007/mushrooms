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
	lair: boolean?, -- rośnie tylko w Skarbcu Skarbnika (koniec jaskini)
	guardian: string?, -- rośnie tylko w legowisku tego strażnika (np. "utopiec"); zerwanie go budzi
	mimic: boolean?, -- błędny ognik udający grzyb: zerwanie kradnie olej, nic nie trafia do koszyka
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
		startZ = -120, -- za chatką jest jeszcze Plac Portali
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
	{
		id = "mine",
		key = "ZONE_MINE",
		startZ = 1420,
		endZ = 1610, -- za skarbcem jest jeszcze portal na Bagna
		oilDrain = 7.5,
		darkness = 1.0,
		spotCount = 9,
		treeCount = 0,
		world = "cave",
		fog = { 34, 26, 8 },
		fireflies = 3,
		mist = 3,
	},
	-- ===== Bagna =====
	-- Otwarte niebo, gęsta zielona mgła, kładki na palach, błędne ogniki i Utopiec w stawie.
	{
		id = "jetty",
		key = "ZONE_JETTY",
		startZ = 2000,
		endZ = 2040,
		oilDrain = 0,
		darkness = 0.5,
		spotCount = 0,
		treeCount = 0,
		world = "swamp",
		safe = true,
		fog = { 30, 46, 30 },
		fireflies = 10,
		mist = 2,
	},
	{
		id = "bog",
		key = "ZONE_BOG",
		startZ = 2040,
		endZ = 2170,
		oilDrain = 6,
		darkness = 0.75,
		spotCount = 16,
		treeCount = 40,
		world = "swamp",
		fog = { 22, 40, 22 },
		fireflies = 16,
		mist = 6,
	},
	{
		id = "wisps",
		key = "ZONE_WISPS",
		startZ = 2170,
		endZ = 2300,
		oilDrain = 9,
		darkness = 0.9,
		spotCount = 16,
		treeCount = 45,
		world = "swamp",
		fog = { 14, 34, 30 },
		fireflies = 22,
		mist = 9,
	},
	{
		id = "pond",
		key = "ZONE_POND",
		startZ = 2300,
		endZ = 2440,
		oilDrain = 12,
		darkness = 1.0,
		spotCount = 10,
		treeCount = 40,
		world = "swamp",
		fog = { 8, 24, 20 },
		fireflies = 8,
		mist = 12,
	},
} :: { ZoneDef }

-- Ulepszenie, które w danym świecie zmniejsza spalanie oleju (mnożnik 1 = bez zmian)
Config.WorldOilUpgrade = {
	cave = "crystal",
	swamp = "rushwick",
} :: { [string]: string }

-- Jaskinia: portal za Gniazdem Leszego, otwiera się graczom z co najmniej unlockCoins monet.
-- Raz otwarty zostaje otwarty (zapisywane), nawet gdy potem wydasz monety.
Config.Cave = {
	unlockCoins = 30000, -- ok. 40 min lasu po ulepszeniach (tools/economy_sim.luau); było 50 000
	halfWidth = 46, -- jaskinia jest węższa niż las
	ceiling = 34, -- wysokość stropu
	portal = { x = 0, z = 476 }, -- portal w lesie, kawałek za Gniazdem Leszego
	-- Skrót za chatką: działa tylko dla tych, którzy już raz doszli do portalu za Leszym.
	-- Stoi na widoku, żeby nowi gracze widzieli, że jest coś do odkrycia.
	shortcut = { x = 0, z = -92 },
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
-- Mikstura szczęścia i Wysyp (za Robuxy) zwiększają szanse, więc gracz widzi wszystkie procenty
-- w sklepie (przycisk „Szanse”, liczone przez Economy.variantOdds / Economy.tagOdds).
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

-- Cechy z eventów: nie losują się według strefy (Economy.tagsForZone), tylko w czasie eventu
-- (Shared/Halloween). Zostają w Economy.getTag, więc grzyby z eventu zachowują wartość w zapisie.
Config.EventTags = {
	{ id = "pumpkin", key = "MUT_PUMPKIN", icon = "🎃", zone = 0, chance = 0.06, mult = 2, color = { 255, 140, 30 } },
} :: { TagDef }

-- Im głębiej w świecie, tym częstsze mutacje: pierwsza niebezpieczna strefa x1, każda kolejna +DepthLuck
Config.DepthLuck = 0.3

-- Balans szczęścia (Economy.luck). Szczęście ×L działa jak L rzutów z najlepszym wynikiem.
-- Darmowe bonusy (nożyk × głębokość × noc) mają malejący zysk: razem zbliżają się do freeCap,
-- ale go nie przekraczają (np. surowe ×3,75 → ×2,6, surowe ×11,9 → ×3,9).
-- Płatne (Wysyp, mikstura) mnożą to w pełni, a całość ma twardy limit maxLuck.
Config.LuckBalance = { freeCap = 5, maxLuck = 8 }

-- Klasy grzybów według tego, jak często rosną w swojej strefie (waga w Config.Species).
-- Grzyby strażników (korony, trufle, kielichy) są zawsze legendarne.
export type ClassDef = { id: string, key: string, color: { number }, minWeight: number }
Config.Classes = {
	{ id = "common", key = "CLASS_COMMON", color = { 200, 200, 200 }, minWeight = 45 },
	{ id = "uncommon", key = "CLASS_UNCOMMON", color = { 110, 220, 110 }, minWeight = 25 },
	{ id = "rare", key = "CLASS_RARE", color = { 90, 170, 255 }, minWeight = 12 },
	{ id = "epic", key = "CLASS_EPIC", color = { 190, 110, 255 }, minWeight = 0 },
	{ id = "legendary", key = "CLASS_LEGENDARY", color = { 255, 170, 40 }, minWeight = -1 },
} :: { ClassDef }

-- ===== Dzień i noc =====
-- Cykl liczony z zegara (os.time), więc na wszystkich serwerach jest ta sama pora i to samo zdarzenie.
-- Noc: zbieranie, z losowym zdarzeniem. Świt: grzyby w całym lesie odrastają od nowa (reset).
export type NightEventDef = {
	id: string,
	key: string,
	icon: string,
	weight: number,
	luck: number, -- mnożnik szans na mutacje
	regrow: number, -- mnożnik czasu odrastania (mniej = szybciej)
	lantern: number, -- mnożnik zasięgu widzenia w mroku (mgła)
}
Config.Cycle = {
	nightSeconds = 1080, -- 18 minut nocy
	dawnSeconds = 120, -- 2 minuty świtu
	dawnDarkness = 0.35, -- o świcie mrok w strefach jest tyle razy słabszy
	events = {
		{ id = "calm", key = "EVENT_CALM", icon = "🌙", weight = 40, luck = 1, regrow = 1, lantern = 1 },
		{ id = "full_moon", key = "EVENT_FULL_MOON", icon = "🌕", weight = 22, luck = 1.5, regrow = 1, lantern = 1.15 },
		{ id = "rain", key = "EVENT_RAIN", icon = "🌧️", weight = 18, luck = 1, regrow = 0.5, lantern = 1 },
		{ id = "mist", key = "EVENT_MIST", icon = "🌫️", weight = 14, luck = 1.3, regrow = 1, lantern = 0.7 },
		{ id = "blood_moon", key = "EVENT_BLOOD_MOON", icon = "🩸", weight = 6, luck = 2.5, regrow = 0.8, lantern = 0.85 },
		-- Noc Dziadów: nie losuje się (waga 0), tylko co trzecia noc w czasie Halloween (Cycle.eventFor)
		{ id = "spirit_night", key = "EVENT_SPIRIT_NIGHT", icon = "👻", weight = 0, luck = 1.8, regrow = 0.75, lantern = 0.9 },
	} :: { NightEventDef },
}

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
	-- Sztolnia Skarbnika
	{ id = "coal_cap", key = "MUSH_COAL", zone = 9, value = 1500, weight = 50, cap = { 60, 58, 62 } },
	{ id = "silver_vein", key = "MUSH_SILVER_VEIN", zone = 9, value = 2100, weight = 35, cap = { 200, 214, 230 } },
	{ id = "gold_nugget", key = "MUSH_GOLD_NUGGET", zone = 9, value = 3200, weight = 15, cap = { 255, 196, 40 } },
	-- Skarbiec Skarbnika (koniec Sztolni): zerwanie budzi Skarbnika
	{ id = "skarbnik_truffle", key = "MUSH_SKARBNIK_TRUFFLE", zone = 9, value = 6000, weight = 0, cap = { 255, 220, 90 }, lair = true },
	-- Trzęsawisko
	{ id = "bog_bell", key = "MUSH_BOG_BELL", zone = 11, value = 4000, weight = 50, cap = { 120, 140, 70 } },
	{ id = "peat_cap", key = "MUSH_PEAT_CAP", zone = 11, value = 5500, weight = 35, cap = { 110, 70, 50 } },
	{ id = "frog_stool", key = "MUSH_FROG_STOOL", zone = 11, value = 7500, weight = 15, cap = { 90, 210, 90 } },
	-- Mokradła Ogników: prawdziwe ogniki i ich podróbki (błędne ogniki)
	{ id = "wisp_cap", key = "MUSH_WISP_CAP", zone = 12, value = 11000, weight = 45, cap = { 140, 255, 220 } },
	{ id = "moon_lily", key = "MUSH_MOON_LILY", zone = 12, value = 16000, weight = 25, cap = { 230, 230, 255 } },
	{ id = "false_wisp", key = "MUSH_WISP_CAP", zone = 12, value = 0, weight = 30, cap = { 140, 255, 220 }, mimic = true },
	-- Staw Utopca
	{ id = "drowned_cap", key = "MUSH_DROWNED_CAP", zone = 13, value = 15000, weight = 50, cap = { 60, 110, 120 } },
	{ id = "bog_pearl", key = "MUSH_BOG_PEARL", zone = 13, value = 21000, weight = 35, cap = { 250, 250, 240 } },
	{ id = "will_o_wisp", key = "MUSH_WILL_O_WISP", zone = 13, value = 32000, weight = 15, cap = { 180, 255, 120 } },
	-- Kielich Utopca (legowisko na stawie): zerwanie budzi Utopca
	{ id = "utopiec_chalice", key = "MUSH_UTOPIEC_CHALICE", zone = 13, value = 60000, weight = 0, cap = { 255, 90, 70 }, guardian = "utopiec" },
} :: { SpeciesDef }

Config.Upgrades = {
	lantern = { key = "UPG_LANTERN", base = 14, step = 4, maxLevel = 8, costBase = 25, costGrowth = 1.6 },
	oil = { key = "UPG_OIL", base = 30, step = 12, maxLevel = 10, costBase = 20, costGrowth = 1.55 },
	basket = { key = "UPG_BASKET", base = 5, step = 3, maxLevel = 10, costBase = 15, costGrowth = 1.5 },
	boots = { key = "UPG_BOOTS", base = 16, step = 1.5, maxLevel = 8, costBase = 30, costGrowth = 1.65 },
	-- Kłódka ogródka: ile sekund złodziej musi trzymać przycisk, żeby wyrwać grzyb
	lock = { key = "UPG_LOCK", base = 2, step = 1, maxLevel = 6, costBase = 60, costGrowth = 1.7 },
	-- Grządki: ile grzybów można mieć posadzonych naraz (siatka 3 x 3 w ogródku)
	beds = { key = "UPG_BEDS", base = 3, step = 1, maxLevel = 6, costBase = 150, costGrowth = 2 },
	-- Nawóz: mnożnik dochodu z posadzonych grzybów
	fertilizer = { key = "UPG_FERTILIZER", base = 1, step = 0.25, maxLevel = 8, costBase = 250, costGrowth = 1.85 },
	-- Nożyk grzybiarza: mnożnik szans na mutacje (srebro, złoto, tęcza i cechy z miejsca)
	knife = { key = "UPG_KNIFE", base = 1, step = 0.25, maxLevel = 6, costBase = 300, costGrowth = 2.3 },
	-- Obozowisko w jaskini. Kryształowy wkład: mnożnik spalania oleju w jaskini (1 = bez zmian)
	crystal = { key = "UPG_CRYSTAL", base = 1, step = -0.1, maxLevel = 5, costBase = 8000, costGrowth = 1.8, shop = "cave" },
	-- Plecak górnika: tyle dodatkowych miejsc w koszyku
	pack = { key = "UPG_PACK", base = 0, step = 4, maxLevel = 6, costBase = 6000, costGrowth = 1.7, shop = "cave" },
	-- Przystań na bagnach. Knot z sitowia: mnożnik spalania oleju na bagnach
	rushwick = { key = "UPG_RUSHWICK", base = 1, step = -0.1, maxLevel = 6, costBase = 150000, costGrowth = 1.75, shop = "swamp" },
	-- Wiklinowy kosz: jeszcze więcej miejsca w koszyku
	creel = { key = "UPG_CREEL", base = 0, step = 5, maxLevel = 5, costBase = 120000, costGrowth = 1.7, shop = "swamp" },
} :: { [string]: UpgradeDef }

-- Kolejność przycisków ulepszeń: w chatce i w obozowisku w jaskini
Config.UpgradeOrder = { "lantern", "oil", "basket", "boots", "knife", "beds", "fertilizer", "lock" }

-- Wygląd nożyka w lewej ręce na kolejnych poziomach (0 = scyzoryk, 6 = kryształowy)
Config.KnifeColors = {
	[0] = { 150, 150, 150 },
	[1] = { 186, 190, 196 },
	[2] = { 214, 224, 238 },
	[3] = { 120, 200, 255 },
	[4] = { 255, 205, 50 },
	[5] = { 255, 130, 60 },
	[6] = { 200, 120, 255 },
}
Config.CaveUpgradeOrder = { "crystal", "pack" }
Config.SwampUpgradeOrder = { "rushwick", "creel" }

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
	{ kind = "oil", world = "forest", x = -13.6, z = -17.2, radius = 3.3 },
	{ kind = "shop", world = "forest", x = 0, z = -37.6, radius = 3.5 }, -- przed ladą, z NPC-skupywaczem
	-- Obozowisko w jaskini: skup po lewej, olej po prawej (patrząc w głąb jaskini), oba przodem do środka
	{ kind = "shop", world = "cave", x = 13, z = 1022, radius = 4 },
	{ kind = "oil", world = "cave", x = -13, z = 1022, radius = 3.6 },
	-- Przystań na bagnach: skup po lewej, olej po prawej (patrząc w głąb bagien)
	{ kind = "shop", world = "swamp", x = 15, z = 2022, radius = 4 },
	{ kind = "oil", world = "swamp", x = -15, z = 2022, radius = 3.6 },
} :: { StationDef }
Config.StationTolerance = 2 -- serwer jest łagodniejszy przez opóźnienie sieci

-- Skupywacz w chatce: stoi za ladą. Sprzedaje się u niego (przycisk rozmowy), ulepszenia są pod
-- przyciskiem „Ulepszenia” i kupuje się je w bezpiecznej strefie świata, do którego należą.
Config.Merchant = {
	x = 0,
	z = -43.4,
	promptDistance = 9,
	sellDistance = 13, -- serwer: tak blisko skupywacza trzeba stać, żeby sprzedać
}

-- Komendy deweloperskie na czacie (np. /coins 1000000) działają w Studio
-- oraz w prawdziwej grze dla tych kont. Dopisz tu UserId Miłosza.
Config.DevUserIds = {
	1293490018, -- Tom
}

-- Bagna: portal za Skarbcem Skarbnika na końcu Sztolni, otwiera się graczom z co najmniej
-- unlockCoins monet (i tylko z jaskini, więc trzeba też mieć otwartą jaskinię).
Config.Swamp = {
	unlockCoins = 1000000,
	halfWidth = 60,
	portal = { x = 0, z = 1594 }, -- w Sztolni, za posągiem Skarbnika
	returnPortal = { x = 0, z = 2008 }, -- na przystani, prowadzi do chatki
	camp = { x = 0, z = 2024 }, -- tu ląduje gracz po przejściu i po zgaśnięciu latarni na bagnach
	boardwalkHalf = 3, -- kładka środkiem bagien (pół szerokości)
	-- Błędne ogniki: zerwanie zabiera taką część pełnego oleju
	mimicOilLoss = 0.35,
}

-- Plac Portali za chatką: kamienny plac z miejscami na portale do kolejnych światów.
-- Środkowe miejsce zajmuje skrót do jaskini, boczne czekają na następne światy („Wkrótce”).
Config.PortalPlaza = {
	center = { x = 0, z = -84 },
	radius = 30,
	slots = { -24, 0, 24 }, -- x kolejnych portali; wszystkie stoją na z = Config.Cave.shortcut.z
	-- Który świat ma portal na którym miejscu (reszta to fundamenty „Wkrótce...”)
	worlds = { [0] = "cave", [-24] = "swamp" } :: { [number]: string },
}

-- ===== Zakupy za Robuxy (developer products) =====
-- id: numer produktu z Creator Hub (Monetization → Developer Products). 0 = jeszcze nie utworzony:
-- w Studio przycisk i tak działa (serwer daje rzecz za darmo, żeby dało się testować),
-- w prawdziwej grze przycisk jest ukryty.
export type ProductDef = { id: number, key: string, icon: string }
Config.Products = {
	rescue = { id = 0, key = "PRODUCT_RESCUE", icon = "💾" }, -- uratuj koszyk po zgaśnięciu latarni / złapaniu
	boom = { id = 0, key = "PRODUCT_BOOM", icon = "🍄" }, -- Wysyp dla całego serwera
	oil = { id = 0, key = "PRODUCT_OIL", icon = "🛢️" }, -- pełna latarnia od razu, w dowolnym miejscu
	harvest = { id = 0, key = "PRODUCT_HARVEST", icon = "⚡" }, -- od razu dochód ogródka z Config.Garden.harvestMinutes
	luck = { id = 0, key = "PRODUCT_LUCK", icon = "🍀" }, -- mikstura szczęścia: więcej mutacji
} :: { [string]: ProductDef }
-- Kolejność kart w sklepie (ratunek ma własny przycisk na czarnym ekranie)
Config.ShopOrder = { "boom", "luck", "oil", "harvest" }

-- Arkusz ikon interfejsu z Figmy (assets/ui-icons.png: 5 kolumn x 4 wiersze, pola po 204 px).
-- Po wgraniu obrazka do Robloxa wpisz tu "rbxassetid://NUMER"; pusty = ikony z emoji.
Config.UiIcons = { sheet = "rbxassetid://103916534276165", cell = 204, columns = 5 }
-- Drugi arkusz ikon (assets/ui-icons-2.png, ramka „sprite/ui-icons-2” w Figmie): ulepszenia, nożyk,
-- grządki, nawóz, monety, ptaszek, gwiazdka, skrzynia, księżyc, iskry. Pusty numer = emoji.
Config.UiIcons2 = { sheet = "rbxassetid://78510472231486", cell = 204, columns = 5 }
-- Pikselowe grzybki do kart w skupie (assets/mushroom-sprites.png z tools/mushroom_sprites.py): po dwie
-- warstwy na kształt i efekty aur. Pusty numer = stare grzybki z ramek.
Config.MushroomSprites = { sheet = "rbxassetid://136090318037259", cell = 64, columns = 8 }
-- Odznaki Robloxa (Creator Hub → Engagement → Badges, obrazki w assets/badges, opis w docs/Odznaki.md).
-- Wpisz numer odznaki po jej założeniu; 0 = odznaki jeszcze nie ma i gra jej nie przyznaje.
Config.Badges = {
	first_mushroom = 0, -- pierwszy grzyb w koszyku
	cave = 0, -- otwarty portal do jaskini
	swamp = 0, -- otwarte bagna
	gold = 0, -- pierwszy złoty grzyb
	rainbow = 0, -- pierwszy tęczowy grzyb
	leszy = 0, -- okradziony Leszy
	skarbnik = 0, -- okradziony Skarbnik
	utopiec = 0, -- okradziony Utopiec
	atlas_page = 0, -- cała strona Grzybopedii odkryta
	grandmaster = 0, -- Arcygrzybiarz: cała księga tęczowa
	lifesaver = 0, -- podniesiony kumpel
	streak7 = 0, -- 7 dni logowania z rzędu
	halloween2026 = 0, -- Halloween 2026: 100 cukierków w czasie eventu
} :: { [string]: number }
-- ===== Halloween: Noc Dziadów (event) =====
-- Włącza się sam według daty (os.time, UTC). W tym czasie:
--   dyniowe grzyby (cecha „pumpkin” z Config.EventTags, x2 wartości) rosną w każdym świecie,
--   a sprzedane u skupywacza dają cukierki (candyByWorld: zależnie od świata grzyba);
--   co trzecia noc to Noc Dziadów (więcej dyń, szczęścia i szybszy odrost);
--   cukierki (licznik stats.candy) prowadzą po ścieżce nagród (track), nagrody przychodzą same.
-- Po evencie dynie przestają rosnąć, a zdobyte tytuły i dyniowe grzyby zostają.
Config.Halloween = {
	startsAt = 1793232000, -- 2026-10-29 00:00 UTC
	endsAt = 1794268800, -- 2026-11-10 00:00 UTC (Halloween, Wszystkich Świętych, Zaduszki i weekend)
	spiritEvery = 3, -- co która noc w czasie eventu to Noc Dziadów (cykl 20 min, więc co godzinę)
	pumpkinChance = 0.06, -- szansa na dyniowy grzyb (stała, szczęście jej nie zmienia)
	spiritPumpkinChance = 0.18, -- w Noc Dziadów
	boomPumpkinChance = 0.5, -- „Dyniowy wysyp” z panelu DEV (jednorazowy odrost lasu wszystkim)
	summonSeconds = 600, -- „Noc Dziadów teraz” z panelu DEV
	candyByWorld = { forest = 1, cave = 2, swamp = 3 } :: { [string]: number },
	questCandy = 2, -- za każde ukończone zadanie dnia w czasie eventu
	badgeCandy = 100, -- odznaka Config.Badges.halloween2026
	-- Ścieżka nagród (cukierki zebrane łącznie, wydawanie w kotle ich nie cofa).
	-- kind: "title" (tytuł z Titles, rarity), "luck" (mikstura na seconds), "skin" (skórka z skins)
	track = {
		{ candy = 10, kind = "title", id = "TITLE_PUMPKINHEAD", rarity = "rare", icon = "🎃" },
		{ candy = 30, kind = "luck", seconds = 900, icon = "🍀" },
		{ candy = 60, kind = "skin", id = "pumpkin_lantern", icon = "🏮" },
		{ candy = 100, kind = "title", id = "TITLE_ANCESTRAL_SPIRIT", rarity = "epic", icon = "👻" },
		{ candy = 150, kind = "skin", id = "sickle", icon = "🌙" },
		{ candy = 200, kind = "title", id = "TITLE_PUMPKIN_KING", rarity = "legendary", icon = "👑" },
	} :: { { candy: number, kind: string, id: string?, rarity: string?, seconds: number?, scale: number?, icon: string } },
	-- Skórki narzędzi w dłoni (zostają na zawsze). slot: która rzecz w dłoni się zmienia
	skins = {
		pumpkin_lantern = { slot = "lantern", key = "SKIN_PUMPKIN_LANTERN", icon = "🏮" },
		sickle = { slot = "knife", key = "SKIN_SICKLE", icon = "🌙" },
	} :: { [string]: { slot: string, key: string, icon: string } },
	-- Kocioł „cukierek albo psikus” przy chatce: wrzuca się cost cukierków (z kieszeni),
	-- wypada nagroda albo nieszkodliwy psikus (tylko wygląd na chwilę, nic nie zabiera).
	cauldron = {
		cost = 5,
		cooldown = 1.5,
		duplicateScale = 4, -- skórka, którą już masz: monety (x skala nagród)
		outcomes = {
			{ id = "coins", weight = 28, scale = 1.5 },
			{ id = "luck", weight = 15, seconds = 300 },
			{ id = "candy", weight = 6, amount = 12 }, -- tylko do kieszeni, ścieżki nie przesuwa
			{ id = "skin_lantern", weight = 4, skin = "pumpkin_lantern" },
			{ id = "skin_knife", weight = 4, skin = "sickle" },
			{ id = "trick_pumpkin", weight = 12, seconds = 60, trick = true }, -- dynia na głowie
			{ id = "trick_ghostlight", weight = 12, seconds = 120, trick = true }, -- zielona latarnia duchów
			{ id = "trick_scare", weight = 10, trick = true }, -- duch wyskakuje na ekranie
			{ id = "trick_spirits", weight = 9, seconds = 45, trick = true }, -- dusze krążą wokół gracza
		} :: { { id: string, weight: number, scale: number?, seconds: number?, amount: number?, skin: string?, trick: boolean? } },
	},
	-- Muzyka nocą w lesie (i każdą Nocą Dziadów) w czasie eventu. Licencjonowane: APM, DistroKid.
	playlist = {
		"rbxassetid://1837467198", -- Night of the Ghouls
		"rbxassetid://1838592691", -- Halloween Night
		"rbxassetid://139190190976686", -- Halloween Music Box
		"rbxassetid://1836009626", -- Halloween Horrors Waltz
		"rbxassetid://130935065570387", -- Ghostly Masquerade Ball
		"rbxassetid://139960241205796", -- Sweet Scare
	},
}

-- Tekstura „kratki” na voxelowe grzyby w lesie (assets/voxel-noise.png). Pusta = gładkie klocki.
Config.VoxelNoise = { texture = "rbxassetid://77358626050293" }

-- ===== Samouczek =====
-- Kroki: 0 cutscenka (zły sen) → 1 zbieranie do pełnego plecaka → 2 sprzedaż → 3 ulepszenie oleju →
-- 4 zebranie grzybów do ogródka → 5 sadzenie → 6 kradzież (cutscenka + opis) → done.
-- Grzyby samouczka rosną przy ścieżce tylko dla tego gracza (id "tut_N"); 5 opieniek po 4 monety
-- daje dokładnie 20 monet, czyli tyle, ile kosztuje pierwsze ulepszenie oleju.
Config.Tutorial = {
	done = 100,
	species = "honey",
	-- x, z grzybów przy ścieżce (las zaczyna się od z = 40, bliżej chatki nie da się zbierać).
	-- Pierwszy widać z ganku w cutscence. Najdalszy to ok. 2,5 s marszu od polany, więc 7 oleju starcza z zapasem.
	spots = {
		{ 2.6, 48 }, { -3.1, 56 }, { -0.1, 64 }, { -5.1, 72 }, { -0.7, 80 },
	},
	gardenSpots = { { -1.6, 46 }, { 1.2, 58 }, { -5.1, 68 } },
	lowOil = 7, -- tyle oleju zostaje po zapełnieniu plecaka (mało, ale na pewno wystarczy na powrót)
	upgrade = "oil", -- jedyne ulepszenie, które można kliknąć w samouczku
	reward = 50, -- monety na koniec samouczka
}

-- ===== Dźwięk =====
-- Numery dźwięków z Creator Store (rbxassetid://...). Pusty = cisza w tym miejscu.
-- Muzyka i większość efektów to licencjonowane biblioteki Robloxa (APM, Pro Sound Effects);
-- dźwięki interfejsu i memowe to darmowe uploady społeczności (mogą kiedyś zniknąć – wtedy cisza).
-- Pełna lista z uzasadnieniem: docs/Muzyka i SFX do Lantern Forager.md
-- Numery dźwięków (rbxassetid://...). Pusty = cisza w tym miejscu. Szczegóły i źródła: reports/ w repo.
Config.Audio = {
	music = {
		dream = "rbxassetid://9042880599", -- sen: spokojny, tajemniczy las nocą
		eerie = "rbxassetid://9125603091", -- mityczny grzyb świeci, coś się budzi
		chase = "rbxassetid://9043770732", -- pościg Leszego
		wake = "rbxassetid://9039609965", -- poranek przy chatce po złym śnie
		tutorial = "rbxassetid://9041810309", -- lekka pętla do samouczka i sklepu
		heist = "rbxassetid://9044410283", -- skradanie się złodzieja w ogródku
		clues = "rbxassetid://9042776045", -- komiczne skradanie (Looking For Clues)
		hall = "rbxassetid://1839900676", -- In the Hall of the Mountain King (pogoń za złodziejem)
	},
	-- Muzyka w grze: każdy świat ma swoją playlistę, utwory lecą w losowej kolejności (bez powtórki pod rząd),
	-- z płynnym przejściem i chwilą samego otoczenia między nimi. Licencjonowane: APM, DistroKid, Too Lost.
	playlists = {
		forest = {
			"rbxassetid://9042880599", -- Mountain Lion Lullaby (flet)
			"rbxassetid://9039954349", -- Gentle Folk
			"rbxassetid://9039609965", -- The Old Patchwork Quilt (harfa i gitara)
			"rbxassetid://9041810309", -- Stomping Floors (wesoły folk)
			"rbxassetid://1837777641", -- Lightly Magical
			"rbxassetid://9039974099", -- Moonlight (tajemniczo)
			"rbxassetid://81454116918887", -- Forest Night Flute
		},
		cave = {
			"rbxassetid://1840777445", -- Worlds Of Darkness
			"rbxassetid://1836590190", -- Held Under
			"rbxassetid://1837470310", -- Negative 35
			"rbxassetid://1843789538", -- Rhythm Drone 50
			"rbxassetid://1843821342", -- Tension Repeat Drones 22
			"rbxassetid://134532910241071", -- Quiet Cavern
			"rbxassetid://71207032544256", -- Catacombs
		},
		swamp = {
			"rbxassetid://120013530647101", -- Baba Yaga's Witch House Part 6
			"rbxassetid://124064284287798", -- Hollowtide
			"rbxassetid://9038855633", -- Deep Sea Research (bulgoczące tło)
			"rbxassetid://1843408841", -- Tableau 7 – Ensorcellement
			"rbxassetid://135327241053061", -- Cradle of Shadows
			"rbxassetid://88402307111260", -- Dark Woods
			"rbxassetid://128108081922306", -- The Cryptids are Close
		},
	},
	playlistVolume = 0.45,
	playlistGap = { 6, 16 }, -- sekundy ciszy (samo otoczenie) między utworami
	sfx = {
		forest = "rbxassetid://9112764040", -- szum lasu nocą (pętla)
		birds = "rbxassetid://9112831284", -- ptaki o poranku (pętla)
		footstep = "rbxassetid://9114518233",
		pick = "rbxassetid://79662193870612", -- zerwanie grzyba („pyk”)
		shimmer = "rbxassetid://135385970610304", -- mityczny grzyb lśni
		rumble = "rbxassetid://9112823563", -- ziemia drży
		roar = "rbxassetid://9113980319", -- ryk Leszego
		heartbeat = "rbxassetid://9043365842", -- bicie serca (pętla)
		sting = "rbxassetid://138524319910012", -- złapany! (uderzenie)
		cauldron = "rbxassetid://9120305560", -- bulgot kotła (Halloween)
		witch = "rbxassetid://9065926843", -- śmiech wiedźmy: psikus z kotła
		gasp = "rbxassetid://9125572450", -- przebudzenie
		creak = "rbxassetid://9120829478", -- skrzypienie bujanego fotela
		bubble = "rbxassetid://109359226723492", -- chmurka z myślą
		whoosh = "rbxassetid://9120718279", -- okno samouczka wjeżdża
		blip = "rbxassetid://9120300066", -- pisanie tekstu literka po literce
		ping = "rbxassetid://127036696152728", -- strzałka / cel
		full = "rbxassetid://98180814011947", -- plecak pełny
		warn = "rbxassetid://98180814011947", -- mało oleju
		coin = "rbxassetid://9113848418",
		sell = "rbxassetid://90531793028786", -- sprzedaż („ka-ching”)
		levelup = "rbxassetid://99980076888596", -- ulepszenie
		click = "rbxassetid://88442833509532",
		plant = "rbxassetid://9120633824", -- sadzenie w ogródku
		alarm = "rbxassetid://1842379470", -- ktoś kradnie
		sneak = "rbxassetid://9113532211", -- złodziej się skrada
		boom = "rbxassetid://6308606116", -- memowy akcent
		flame = "rbxassetid://9114462806", -- płomień w latarni się krztusi (Flame Flutter 2)
		tink = "rbxassetid://9119945318", -- stuknięcie w szkło latarni
		surprise = "rbxassetid://9045132884", -- komiczny akcent przy „Hej!” (APM Country Romp Hit)
		loony = "rbxassetid://1847459769", -- komiczny hit przy wywrotce złodzieja
		whisper = "rbxassetid://9043347008", -- szepty w ciemności
		breath = "rbxassetid://9114226397", -- ciężki oddech Leszego
		crack = "rbxassetid://9120818969", -- trzask drewna i korzeni
		owl = "rbxassetid://9117181540", -- sowa w oddali
		pant = "rbxassetid://9125573009", -- zdyszany oddech w biegu
		pat = "rbxassetid://9120863506", -- klepnięcie w ziemię
		swell = "rbxassetid://9114353056", -- złowrogie narastanie
		leaves = "rbxassetid://9116248055", -- szelest liści
		slide = "rbxassetid://9119198140", -- gwizdek ślizgowy (złodziej przeskakuje płot)
		scratch = "rbxassetid://9118086936", -- zgrzyt płyty, gdy gracz przyłapuje złodzieja
		dig = "rbxassetid://9114105633", -- grzebanie w ziemi przy sadzeniu
		tiptoe = "rbxassetid://9120062717", -- kroki na paluszkach po trawie
		bodyfall = "rbxassetid://9113469292", -- upadek na ziemię
		grow = "rbxassetid://1842312856", -- dzwoneczki, gdy grzyb wyrasta (APM, glockenspiel)
	},
}

-- Ile sekund po zgaśnięciu latarni / złapaniu da się jeszcze uratować koszyk.
-- buttonSeconds: jak długo widać przycisk; serverSeconds: zapas na okno płatności Robloxa.
Config.Rescue = { buttonSeconds = 15, serverSeconds = 40 }

-- Wysyp: przez tyle sekund grzyby u wszystkich na serwerze odrastają szybciej i częściej mutują
Config.Boom = { seconds = 600, regrowFactor = 0.35, luck = 1.5 }

-- Mikstura szczęścia: przez tyle sekund mutacje u kupującego są dwa razy częstsze
Config.LuckPotion = { seconds = 900, luck = 2 }

-- Kamera: bez limitu dało się oddalić widok i oglądać las z góry
Config.CameraMaxZoom = 22

-- ===== Skarbiec Skarbnika =====
-- Na końcu Sztolni, w jaskini. Skarbnik to duch kopalni ze śląskich legend: pilnuje skarbów
-- pod ziemią. Zerwanie Złotej Trufli budzi go i goni gracza aż do obozowiska.
Config.Lair = {
	centerX = 0,
	centerZ = 1548,
	radius = 13,
	spots = 3,
	spotRadius = 5,
	respawnSeconds = 300,
}

Config.Skarbnik = {
	speed = 25, -- studs/s; ucieka się dopiero na prawie maksymalnych butach
	wakeDelay = 2.5,
	catchRadius = 4,
	giveUpSeconds = 50,
}

-- ===== Legowisko Utopca =====
-- Wodnik z polskich i śląskich legend: zielony, mokry, w czerwonej czapeczce, mieszka w stawie
-- i wciąga do wody. Pilnuje Kielichów Utopca na wysepce pośrodku stawu na końcu bagien.
Config.UtopiecLair = {
	centerX = 0,
	centerZ = 2404,
	radius = 14,
	spots = 3,
	spotRadius = 5,
	respawnSeconds = 360,
}

Config.Utopiec = {
	speed = 27.5, -- ucieka się tylko na maksymalnych butach (28)
	wakeDelay = 0.6, -- wyskakuje ze stawu prawie od razu
	catchRadius = 4,
	giveUpSeconds = 55,
}

Config.Leszy = {
	speed = 22, -- studs/s; gracz na butach poz. 3 (20,5) jeszcze ucieka z gniazda, na poz. 2 już nie
	wakeDelay = 2, -- tyle sekund Leszy się budzi, zanim ruszy
	catchRadius = 4, -- z tej odległości łapie
	giveUpSeconds = 45, -- dłużej nie goni (np. gracz utknął za kamieniem)
}

-- ===== Ogródki graczy (jak w Steal an Egg) =====
-- Przynosisz grzyb z lasu i sadzisz go na grządce: od tej chwili co minutę sypie monety do skrzyni
-- (także gdy jesteś offline, do limitu). Inni gracze mogą wyrwać ci posadzony grzyb, ale muszą go
-- donieść do swojego ogródka, niosąc go nad głową wolniej niż zwykle. Dogonisz złodzieja = grzyb wraca.
Config.Garden = {
	size = 26, -- bok ogródka (studs)
	maxBeds = 9, -- tyle grządek stoi w ogródku; odblokowane są pierwsze upgradeStat("beds")
	incomeRate = 0.04, -- posadzony grzyb daje co minutę taką część swojej wartości (oddaje się w 25 min)
	offlineMinutes = 120, -- dochód offline najwyżej za tyle minut
	harvestMinutes = 30, -- produkt za Robuxy: tyle minut dochodu od razu
	stealCooldown = 25, -- po kradzieży ogródek jest chroniony przez tyle sekund
	thiefCooldown = 8, -- ten sam złodziej może kraść co tyle sekund
	guardRadius = 10, -- właściciel bliżej przycisków = nie da się kraść
	promptDistance = 10,
	carry = {
		-- Prędkość złodzieja z łupem względem zwykłej, według rangi wariantu (0 = bez wariantu)
		speedByRank = { [0] = 0.85, [1] = 0.8, [2] = 0.7, [3] = 0.6 },
		guardianSpeed = 0.6, -- korony, trufle i kielichy strażników są najcięższe
		tagRadius = 6, -- właściciel bliżej złodzieja = odbiera łup
		timeout = 60, -- po tylu sekundach łup wraca do właściciela
	},
	-- Ogródki na mapie: po dwa z każdej strony chatki, furtką do środka polany.
	-- Ile ogródków, tylu graczy ma grządki, więc ustaw rozmiar serwera na tyle samo (4).
	plots = {
		{ x = -40, z = -30 },
		{ x = 40, z = -30 },
		{ x = -40, z = 10 },
		{ x = 40, z = 10 },
	},
}

return Config
