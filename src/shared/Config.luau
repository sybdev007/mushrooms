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
	world: string, -- "forest", "cave", "swamp" albo "mountain": osobne światy połączone portalem
	safe: boolean?, -- chatka / obozowisko: olej się nie pali, można tankować i handlować
	fog: { number }?, -- kolor mgły w mroku (domyślnie nocny granat lasu)
	fireflies: number?, -- świetliki (w jaskini: pyłki) na sekundę wokół gracza
	mist: number?, -- mgiełka przy ziemi
	halfWidth: number?, -- połowa szerokości tej strefy, gdy inna niż świata (Economy.zoneHalfWidth)
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
	puff: boolean?, -- purchawka: przy zerwaniu wypuszcza chmurę zarodników (tylko wygląd)
	forgeOnly: boolean?, -- powstaje tylko w Moździerzu Zielarki (Config.Forge): nie rośnie, nie da się go posadzić
	class: string?, -- klasa spoza wag (Config.SpecialClasses): "mythic" / "secret" (grzyby strażników z kuźni)
}

export type UpgradeDef = {
	key: string,
	base: number, -- wartość statystyki na poziomie 0
	step: number, -- przyrost na poziom
	maxLevel: number,
	costBase: number, -- koszt pierwszego poziomu
	costGrowth: number, -- mnożnik kosztu na każdy kolejny poziom
	shop: string?, -- gdzie się kupuje: "forest" (chatka, domyślnie) albo "cave" (obozowisko)
	worldCaps: { [string]: number }?, -- maks. kupiony poziom po odblokowaniu danego świata
	-- Łagodniejsza krzywa dla poziomów kolejnego świata: od poziomu lateFrom koszt rośnie o lateGrowth
	-- (zamiast costGrowth), licząc od ceny ostatniego poziomu przed progiem. Bez tego buty 16 kosztowałyby 178 mln.
	lateFrom: number?,
	lateGrowth: number?,
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
		-- Polana jest szersza niż las (ForestHalfWidth): z tyłu ogródków zostaje miejsce na drzewa z obrzeża
		halfWidth = 80,
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
	-- ===== Łysa Góra =====
	-- Sabat czarownic w świetle pełni: krzywy czarny las z krukami, polana kotłów z trującymi oparami
	-- i łysy szczyt z kręgiem kamieni, gdzie na kurzej stopce kręci się chatka Baby Jagi.
	{
		id = "glade",
		key = "ZONE_GLADE",
		startZ = 3000,
		endZ = 3040,
		oilDrain = 0,
		darkness = 0.5,
		spotCount = 0,
		treeCount = 0,
		world = "mountain",
		safe = true,
		fog = { 40, 26, 52 },
		fireflies = 8,
		mist = 2,
	},
	{
		id = "witchwood",
		key = "ZONE_WITCHWOOD",
		startZ = 3040,
		endZ = 3170,
		oilDrain = 8,
		darkness = 0.75,
		spotCount = 16,
		treeCount = 42,
		world = "mountain",
		fog = { 34, 18, 46 },
		fireflies = 10,
		mist = 6,
	},
	{
		id = "cauldrons",
		key = "ZONE_CAULDRONS",
		startZ = 3170,
		endZ = 3300,
		oilDrain = 11,
		darkness = 0.9,
		spotCount = 16,
		treeCount = 20,
		world = "mountain",
		fog = { 22, 40, 16 },
		fireflies = 6,
		mist = 9,
	},
	{
		id = "summit",
		key = "ZONE_SUMMIT",
		startZ = 3300,
		endZ = 3480,
		oilDrain = 14,
		darkness = 1.0,
		spotCount = 12,
		treeCount = 10,
		world = "mountain",
		fog = { 26, 22, 48 },
		fireflies = 4,
		mist = 8,
	},
} :: { ZoneDef }

-- Ulepszenie, które w danym świecie zmniejsza spalanie oleju (mnożnik 1 = bez zmian)
Config.WorldOilUpgrade = {
	cave = "crystal",
	swamp = "rushwick",
	mountain = "herbwick",
} :: { [string]: string }

-- Jaskinia: portal za Gniazdem Leszego, otwiera się graczom z co najmniej unlockCoins monet.
-- Raz otwarty zostaje otwarty (zapisywane), nawet gdy potem wydasz monety.
Config.Cave = {
	unlockCoins = 30000, -- ok. 55 min lasu (tools/economy_sim.luau), razem z maksymalnymi ulepszeniami lasu
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
	-- Ponad tęczowym, na wszystkich mapach: granatowy kapelusz w gwiazdach (cel do polowania, ok. +1,5% dochodu)
	{ id = "cosmic", key = "MUT_COSMIC", icon = "🌌", chance = 0.0008, mult = 20, rank = 4, color = { 70, 50, 170 } },
} :: { VariantDef }

Config.Tags = {
	{ id = "mossy", key = "MUT_MOSSY", icon = "🌿", zone = 3, chance = 0.08, mult = 1.5, color = { 110, 176, 72 } },
	{ id = "glowing", key = "MUT_GLOWING", icon = "✨", zone = 4, chance = 0.1, mult = 2, color = { 110, 255, 214 } },
	{ id = "crystal", key = "MUT_CRYSTAL", icon = "💎", zone = 7, chance = 0.1, mult = 2, color = { 120, 200, 255 } },
	{ id = "abyssal", key = "MUT_ABYSSAL", icon = "🔥", zone = 8, chance = 0.08, mult = 2.5, color = { 255, 90, 60 } },
	-- Łysa Góra: każda strefa ma swoją cechę
	{ id = "cursed", key = "MUT_CURSED", icon = "💀", zone = 15, chance = 0.09, mult = 2, color = { 160, 70, 220 } },
	{ id = "hexed", key = "MUT_HEXED", icon = "🔮", zone = 16, chance = 0.08, mult = 2.5, color = { 120, 240, 90 } },
	{ id = "moonlit", key = "MUT_MOONLIT", icon = "🌙", zone = 17, chance = 0.07, mult = 3, color = { 190, 210, 255 } },
} :: { TagDef }

-- Pogoda w ogródku (Shared/GardenWeather): po każdej nocy zdarzenie nocy może dać JEDNEMU grzybowi
-- w ogródku gracza swoją cechę (deszcz: Mech, pełnia: Księżycowy, mgła: Blask, krwawy księżyc: Krwawy).
-- Grzyb, który ma już którąś z tych cech, nic więcej od pogody nie dostanie (najwyżej jedna).
-- Noce, gdy gracza nie było, też się liczą (przy wejściu), ale najwyżej maxNights ostatnich.
-- Średnio ok. 1 nowa cecha na 11 nocy (~3,6 h gry albo nieobecności) na ogródek. Symulacja (te same
-- grzyby cały czas): dochód ogródka po 8 h x1,3, po 16 h x1,6, po doby x1,9, najwyżej ok. x2,2
-- (wszystkie z cechą). Gracze wymieniają grzyby na lepsze, więc w praktyce mniej.
Config.GardenWeather = {
	maxNights = 24, -- 8 h nieobecności, jak dochód offline (Config.Garden.offlineMinutes)
	events = {
		rain = { tag = "mossy", chance = 0.2 }, -- x1,5
		full_moon = { tag = "moonlit", chance = 0.08 }, -- x3, więc rzadziej
		mist = { tag = "glowing", chance = 0.15 }, -- x2
		blood_moon = { tag = "bloody", chance = 0.3 }, -- x3, a krwawy księżyc to tylko 6% nocy
	} :: { [string]: { tag: string, chance: number } },
}

-- Znalezisko Nocy (Shared/NightFind, NightFindService): raz na noc na każdym serwerze w głębi lasu wyrasta
-- jeden kosmiczny grzyb, widoczny dla wszystkich. Kto pierwszy go zerwie, musi go donieść na polanę przy
-- chatce w carrySeconds, idąc wolniej i świecąc (inni widzą go i odliczanie nad głową). Na start bez
-- odbierania przez innych. Nagroda: trofeum do gabloty w ogródku (kosmiczna kopia z datą, Config.Showcase,
-- bez monet: gablota ma być zlewem na monety) i licznik stats.nightFinds z tytułami za 1, 3, 7 i 15 dostaw.
-- Nie doniesie (czas, śmierć, portal, teleport, wyjście z gry) = przepada do następnej nocy.
Config.NightFind = {
	delay = { 90, 360 }, -- tyle sekund po zapadnięciu nocy wyrasta (losowo z tego przedziału)
	minLeft = 300, -- nie wyrasta, gdy do świtu zostało mniej niż tyle sekund
	minZone = 3, -- najpłycej w tej strefie lasu (Config.Zones), żeby był kawałek drogi
	carrySeconds = 180,
	speed = 0.75, -- prędkość z Znaleziskiem względem zwykłej
	pickHold = 1.5, -- sekundy trzymania przycisku
	variant = "cosmic", -- jak wygląda: kosmiczny okaz jednego z rarePick najcenniejszych gatunków strefy
	rarePick = 3,
	titles = {
		{ id = "TITLE_NIGHT_FINDER", goal = 1, rarity = "rare" },
		{ id = "TITLE_NIGHT_COURIER", goal = 3, rarity = "epic" },
		{ id = "TITLE_NIGHT_HUNTER", goal = 7, rarity = "legendary" },
		{ id = "TITLE_NIGHT_LEGEND", goal = 15, rarity = "mythic" },
	},
}

-- Gablota w ogródku (Shared/Showcase, ShowcaseService, ShowcasePanel): półki pod bocznym płotem, na których
-- gracz wystawia kopie grzybów z Grzybopedii (każdą odkrytą formę gatunku) i trofea ze Znaleziska Nocy.
-- Wystawa to tylko ozdoba (bez dochodu i premii), widzą ją wszyscy na polanie. Zlew na monety po
-- wymaksowaniu ulepszeń: 3 serie (las, jaskinia, bagna) po perSeries miejsc, kupowane po kolei; k-te płatne
-- miejsce serii kosztuje priceUnits × skala nagród świata serii (Progress.rewardScale) × 2^(k−1):
-- las 16 000 … 128 000, jaskinia 320 000 … 10,24 mln, bagna 1,6 mln … 51,2 mln (razem ok. 121 mln).
-- Pierwsze freeSlots miejsc lasu są za darmo. Serie jaskini i bagien wymagają odblokowanego świata.
Config.Showcase = {
	perSeries = 6,
	freeSlots = 2,
	priceUnits = 10,
	series = {
		{ id = "forest", key = "SHOWCASE_SERIES_FOREST", icon = "🌲", color = { 120, 220, 110 } },
		{ id = "cave", key = "SHOWCASE_SERIES_CAVE", icon = "💎", color = { 110, 200, 255 }, unlock = "caveUnlocked" },
		{ id = "swamp", key = "SHOWCASE_SERIES_SWAMP", icon = "🐸", color = { 90, 230, 190 }, unlock = "swampUnlocked" },
		-- Łysa Góra (plan docs/plans/endgame-zlew.md): 5,2 / 10,4 / 20,8 / 41,6 / 83,2 / 166,4 mln = 327,6 mln
		{ id = "mountain", key = "SHOWCASE_SERIES_MOUNTAIN", icon = "⛰️", color = { 196, 140, 255 }, unlock = "mountainUnlocked" },
	} :: { { id: string, key: string, icon: string, color: { number }, unlock: string? } },
	maxTrophies = 40, -- tyle trofeów ze Znaleziska Nocy trzyma zapis (najstarsze wypadają)
	promptDistance = 8,
	-- Karta zdobyczy (FindCard): nowa forma w Grzybopedii od tej rangi wariantu (2 = Złoty) albo grzyb
	-- strażnika; z karty można od razu wystawić grzyb na wolnym miejscu gabloty (bez podchodzenia)
	cardRank = 2,
	cardSeconds = 8,
}

-- ===== Ofiara dla Leszego (plan docs/plans/endgame-zlew.md, punkt 2) =====
-- Kapliczka na Placu Portali (naprzeciw Moździerza Zielarki), tylko dla graczy z otwartą Łysą Górą.
-- Dobrowolny wydatek monet: suma rośnie w data.stats.leszyOffered, progi dają tytuły i obwódkę tabliczki
-- ogródka. Nic nie wypłaca, nie daje przedmiotów ani szczęścia. Serwer sprawdza kwotę, saldo, Górę,
-- odległość i limit jednej wpłaty na `cooldown` sekund (Shared/Shrine.check).
export type ShrineTier = { goal: number, title: string, rarity: string, glow: string? }
Config.Shrine = {
	position = { x = 17, z = -69 },
	reach = 12, -- tak blisko kapliczki trzeba stać, żeby wpłacić
	cooldown = 2, -- sekund między wpłatami jednego gracza
	unit = 1000000, -- wpłaty w pełnych milionach
	maxOffer = 1000000000, -- najwięcej na raz
	amounts = { 1000000, 10000000, 100000000, 1000000000 }, -- przyciski w oknie
	tiers = {
		{ goal = 100000000, title = "TITLE_LESZY_DONOR", rarity = "rare" },
		{ goal = 500000000, title = "TITLE_LESZY_PATRON", rarity = "epic" },
		{ goal = 1000000000, title = "TITLE_LESZY_SHRINE", rarity = "epic", glow = "amber" },
		{ goal = 5000000000, title = "TITLE_LESZY_LEGEND", rarity = "legendary", glow = "silver" },
		{ goal = 10000000000, title = "TITLE_LESZY_ETERNAL", rarity = "legendary", glow = "moon" },
		{ goal = 20000000000, title = "TITLE_LESZY_ANCIENT", rarity = "mythic" },
	} :: { ShrineTier },
	-- Obwódka imienia na tabliczce furtki ogródka (GardenService)
	glowColors = {
		amber = { 255, 170, 60 },
		silver = { 220, 230, 245 },
		moon = { 150, 190, 255 },
	} :: { [string]: { number } },
}

-- Cechy tylko z pogody w ogródku (nie losują się w lesie). Liczą się w wartości i zapisie (Economy.getTag).
Config.WeatherTags = {
	{ id = "bloody", key = "MUT_BLOODY", icon = "🩸", zone = 0, chance = 0, mult = 3, color = { 230, 50, 70 } },
} :: { TagDef }

-- Cechy z eventów: nie losują się według strefy (Economy.tagsForZone), tylko w czasie eventu
-- (Shared/Halloween). Zostają w Economy.getTag, więc grzyby z eventu zachowują wartość w zapisie.
Config.EventTags = {
	{ id = "pumpkin", key = "MUT_PUMPKIN", icon = "🎃", zone = 0, chance = 0.06, mult = 2, color = { 255, 140, 30 } },
	{ id = "frost", key = "MUT_FROST", icon = "❄️", zone = 0, chance = 0.06, mult = 2, color = { 150, 220, 255 } }, -- Zima (Shared/Winter)
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

-- Klasy tylko dla grzybów z kuźni (SpeciesDef.class), poza listą wag powyżej (strażnicy dalej = ostatnia z Classes)
Config.SpecialClasses = {
	{ id = "mythic", key = "CLASS_MYTHIC", color = { 255, 70, 110 }, minWeight = -2 },
	{ id = "secret", key = "CLASS_SECRET", color = { 236, 240, 255 }, minWeight = -3 },
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
	{ id = "bog_bell", key = "MUSH_BOG_BELL", zone = 11, value = 2000, weight = 50, cap = { 120, 140, 70 } },
	{ id = "peat_cap", key = "MUSH_PEAT_CAP", zone = 11, value = 2800, weight = 35, cap = { 110, 70, 50 } },
	{ id = "frog_stool", key = "MUSH_FROG_STOOL", zone = 11, value = 3800, weight = 15, cap = { 90, 210, 90 } },
	-- Mokradła Ogników: prawdziwe ogniki i ich podróbki (błędne ogniki)
	{ id = "wisp_cap", key = "MUSH_WISP_CAP", zone = 12, value = 5500, weight = 45, cap = { 40, 220, 205 } },
	{ id = "moon_lily", key = "MUSH_MOON_LILY", zone = 12, value = 8000, weight = 25, cap = { 230, 230, 255 } },
	{ id = "false_wisp", key = "MUSH_WISP_CAP", zone = 12, value = 0, weight = 30, cap = { 40, 220, 205 }, mimic = true },
	-- Staw Utopca
	{ id = "drowned_cap", key = "MUSH_DROWNED_CAP", zone = 13, value = 7500, weight = 50, cap = { 60, 110, 120 } },
	{ id = "bog_pearl", key = "MUSH_BOG_PEARL", zone = 13, value = 10500, weight = 35, cap = { 250, 250, 240 } },
	{ id = "will_o_wisp", key = "MUSH_WILL_O_WISP", zone = 13, value = 16000, weight = 15, cap = { 180, 255, 120 } },
	-- Kielich Utopca (legowisko na stawie): zerwanie budzi Utopca
	{ id = "utopiec_chalice", key = "MUSH_UTOPIEC_CHALICE", zone = 13, value = 35000, weight = 0, cap = { 255, 90, 70 }, guardian = "utopiec" },
	-- Wiedźmi Las
	{ id = "witch_hat", key = "MUSH_WITCH_HAT", zone = 15, value = 9500, weight = 50, cap = { 236, 120, 40 } },
	{ id = "devil_morel", key = "MUSH_DEVIL_MOREL", zone = 15, value = 13000, weight = 35, cap = { 92, 58, 44 } },
	{ id = "raven_bracket", key = "MUSH_RAVEN_BRACKET", zone = 15, value = 19000, weight = 15, cap = { 70, 52, 96 } },
	-- Kotły Sabatu
	{ id = "sabbath_puffball", key = "MUSH_SABBATH_PUFFBALL", zone = 16, value = 15000, weight = 45, cap = { 196, 214, 150 }, puff = true },
	{ id = "devil_fingers", key = "MUSH_DEVIL_FINGERS", zone = 16, value = 21500, weight = 35, cap = { 226, 52, 60 } },
	{ id = "hex_cluster", key = "MUSH_HEX_CLUSTER", zone = 16, value = 31000, weight = 20, cap = { 120, 230, 70 } },
	-- Szczyt Łysej Góry
	{ id = "earthstar", key = "MUSH_EARTHSTAR", zone = 17, value = 26000, weight = 50, cap = { 176, 140, 104 } },
	{ id = "moon_hat", key = "MUSH_MOON_HAT", zone = 17, value = 36000, weight = 35, cap = { 196, 210, 240 } },
	{ id = "night_eye", key = "MUSH_NIGHT_EYE", zone = 17, value = 52000, weight = 15, cap = { 60, 40, 110 } },
	-- Ogródek Baby Jagi za chatką na kurzej stopce: zerwanie budzi Babę Jagę
	{ id = "jaga_toadstool", key = "MUSH_JAGA_TOADSTOOL", zone = 17, value = 115000, weight = 0, cap = { 150, 60, 210 }, guardian = "jaga" },
	-- Kuźnia Grzybów (Moździerz Zielarki): tylko z przepisów Config.Forge, zawsze na końcu listy (ranking
	-- tygodnia koduje gatunek numerem pozycji). Strefa = świat przepisu (tylko opis); w lesie nie rosną.
	{ id = "forge_mossbell", key = "MUSH_FORGE_MOSSBELL", zone = 11, value = 1050, weight = 0, cap = { 96, 170, 90 }, forgeOnly = true },
	{ id = "forge_emberpearl", key = "MUSH_FORGE_EMBERPEARL", zone = 13, value = 4700, weight = 0, cap = { 255, 120, 60 }, forgeOnly = true },
	{ id = "forge_glasscap", key = "MUSH_FORGE_GLASSCAP", zone = 12, value = 3800, weight = 0, cap = { 210, 240, 236 }, forgeOnly = true },
	{ id = "forge_runemorel", key = "MUSH_FORGE_RUNEMOREL", zone = 15, value = 39700, weight = 0, cap = { 120, 60, 170 }, forgeOnly = true },
	{ id = "forge_mooncoral", key = "MUSH_FORGE_MOONCORAL", zone = 16, value = 52600, weight = 0, cap = { 200, 214, 240 }, forgeOnly = true },
	{ id = "forge_eclipsestar", key = "MUSH_FORGE_ECLIPSESTAR", zone = 17, value = 36000, weight = 0, cap = { 90, 60, 150 }, forgeOnly = true },
	-- Z trzech tęczowych grzybów strażników (Config.Forge.specials): mityczny i sekretny
	{ id = "fern_flower", key = "MUSH_FERN_FLOWER", zone = 13, value = 50000, weight = 0, cap = { 255, 110, 40 }, forgeOnly = true, class = "mythic" },
	{ id = "veles_eye", key = "MUSH_VELES_EYE", zone = 17, value = 150000, weight = 0, cap = { 40, 80, 60 }, forgeOnly = true, class = "secret" },
} :: { SpeciesDef }

Config.Upgrades = {
	lantern = { key = "UPG_LANTERN", base = 14, step = 4, maxLevel = 8, costBase = 30, costGrowth = 1.9 },
	oil = { key = "UPG_OIL", base = 30, step = 12, maxLevel = 17, costBase = 20, costGrowth = 2.5, worldCaps = { forest = 8, cave = 11, swamp = 14, mountain = 17 }, lateFrom = 14, lateGrowth = 1.55 },
	basket = { key = "UPG_BASKET", base = 5, step = 3, maxLevel = 18, costBase = 15, costGrowth = 2.5, worldCaps = { forest = 6, cave = 10, swamp = 14, mountain = 18 }, lateFrom = 14, lateGrowth = 1.5 },
	boots = { key = "UPG_BOOTS", base = 16, step = 1.5, maxLevel = 16, costBase = 35, costGrowth = 2.8, worldCaps = { forest = 4, cave = 8, swamp = 12, mountain = 16 }, lateFrom = 12, lateGrowth = 1.55 },
	-- Kłódka ogródka: ile sekund złodziej musi trzymać przycisk, żeby wyrwać grzyb
	lock = { key = "UPG_LOCK", base = 2, step = 1, maxLevel = 6, costBase = 60, costGrowth = 1.7 },
	-- Grządki: ile grzybów można mieć posadzonych naraz (siatka 3 x 3 w ogródku)
	beds = { key = "UPG_BEDS", base = 3, step = 1, maxLevel = 6, costBase = 150, costGrowth = 2 },
	-- Nawóz: mnożnik dochodu z posadzonych grzybów
	fertilizer = { key = "UPG_FERTILIZER", base = 1, step = 0.25, maxLevel = 8, costBase = 250, costGrowth = 1.85 },
	-- Skrzynia w ogródku: mieści dochód z tylu godzin (2 h na start, 8 h na maksymalnym poziomie)
	chest = { key = "UPG_CHEST", base = 2, step = 1, maxLevel = 6, costBase = 20000, costGrowth = 2.6 },
	-- Nożyk grzybiarza: mnożnik szans na mutacje (srebro, złoto, tęcza i cechy z miejsca)
	knife = { key = "UPG_KNIFE", base = 1, step = 0.25, maxLevel = 6, costBase = 300, costGrowth = 2.3 },
	-- Obozowisko w jaskini. Kryształowy wkład: mnożnik spalania oleju w jaskini (1 = bez zmian)
	crystal = { key = "UPG_CRYSTAL", base = 1, step = -0.1, maxLevel = 5, costBase = 8000, costGrowth = 1.8, shop = "cave" },
	-- Plecak górnika: tyle dodatkowych miejsc w koszyku
	pack = { key = "UPG_PACK", base = 0, step = 4, maxLevel = 6, costBase = 6000, costGrowth = 1.7, shop = "cave" },
	-- Przystań na bagnach. Knot z sitowia: mnożnik spalania oleju na bagnach
	rushwick = { key = "UPG_RUSHWICK", base = 1, step = -0.1, maxLevel = 6, costBase = 200000, costGrowth = 1.75, shop = "swamp" },
	-- Wiklinowy kosz: jeszcze więcej miejsca w koszyku
	creel = { key = "UPG_CREEL", base = 0, step = 5, maxLevel = 5, costBase = 160000, costGrowth = 1.7, shop = "swamp" },
	-- Polana Zielarki na Łysej Górze. Ziołowy knot: mnożnik spalania oleju na Łysej Górze
	herbwick = { key = "UPG_HERBWICK", base = 1, step = -0.1, maxLevel = 6, costBase = 1200000, costGrowth = 1.6, shop = "mountain" },
	-- Torba Wiedźmy: jeszcze więcej miejsca w koszyku
	witchbag = { key = "UPG_WITCHBAG", base = 0, step = 5, maxLevel = 5, costBase = 1000000, costGrowth = 1.6, shop = "mountain" },
} :: { [string]: UpgradeDef }

-- Kolejność przycisków ulepszeń: w chatce i w obozowisku w jaskini
Config.UpgradeOrder = { "lantern", "oil", "basket", "boots", "knife", "beds", "fertilizer", "chest", "lock" }

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
Config.CaveUpgradeOrder = { "boots", "oil", "basket", "crystal", "pack" }
Config.SwampUpgradeOrder = { "boots", "oil", "basket", "rushwick", "creel" }
Config.MountainUpgradeOrder = { "boots", "oil", "basket", "herbwick", "witchbag" }

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
	radius = 4.2, -- korony leżą w kółku wokół środka gniazda (modele jak w lesie: DisplayMushrooms)
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
	-- Polana Zielarki na Łysej Górze: skup po lewej, olej po prawej (patrząc w górę)
	{ kind = "shop", world = "mountain", x = 15, z = 3022, radius = 4 },
	{ kind = "oil", world = "mountain", x = -15, z = 3022, radius = 3.6 },
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
-- oraz w prawdziwej grze dla tych kont.
Config.DevUserIds = {
	1293490018, -- Tom
	7532199310, -- Miłosz (MiloszCzempion13)
}

-- Akcje panelu DEV dozwolone na opublikowanej grze (poza Studio). Teleporty (id „tp…”) działają tam zawsze.
-- Wszystko inne (monety, cukierki, ulepszenia, zadania, postęp, pora dnia) działa tylko w Studio.
-- Tę samą listę czyta serwer (GameService sprawdza każdą akcję) i panel DEV (szare przyciski „Studio”).
Config.DevLiveActions = {
	boardsRefresh = true,
	resetSave = true, -- tylko własny zapis i tylko w dół (do zera), więc bezpieczne też na żywo
	spiritNight = true,
	pumpkinBoom = true,
	frostBoom = true, -- Zima: „Zamieć” (tylko w czasie eventu)
	forecastHint = true, -- podpowiedź Prognozy nocy od nowa (tylko własne ustawienie, nic nie daje)
} :: { [string]: boolean }

-- Admin abuse z panelu DEV: wydarzenia dla całego serwera, ogłaszane wszystkim, z banerem i odliczaniem.
-- Działają też na żywej grze. Celowo bez darmowego Wysypu i mikstury szczęścia (to płatne produkty).
-- kind: night = przywołane zdarzenie nocy (event z Config.Cycle.events), regrow = las odrasta wszystkim
-- teraz, sleep = strażnicy nie gonią, sell = podwójna sprzedaż, shards = podwójne odłamki w ekspedycji,
-- stop = koniec wszystkich.
export type AdminAbuseDef = { id: string, key: string, kind: string, seconds: number, event: string? }
Config.AdminAbuse = {
	abuseFullMoon = { id = "full_moon", key = "ABUSE_FULL_MOON", kind = "night", event = "full_moon", seconds = 600 },
	abuseBloodMoon = { id = "blood_moon", key = "ABUSE_BLOOD_MOON", kind = "night", event = "blood_moon", seconds = 600 },
	abuseMist = { id = "mist", key = "ABUSE_MIST", kind = "night", event = "mist", seconds = 600 },
	abuseRain = { id = "rain", key = "ABUSE_RAIN", kind = "night", event = "rain", seconds = 600 },
	abuseRegrow = { id = "regrow", key = "ABUSE_REGROW", kind = "regrow", seconds = 0 },
	abuseSleep = { id = "sleep", key = "ABUSE_SLEEP", kind = "sleep", seconds = 300 },
	abuseSell = { id = "sell", key = "ABUSE_SELL", kind = "sell", seconds = 600 },
	abuseShards = { id = "shards", key = "ABUSE_SHARDS", kind = "shards", seconds = 900 },
	abuseStop = { id = "stop", key = "ABUSE_STOP", kind = "stop", seconds = 0 },
} :: { [string]: AdminAbuseDef }
for action in Config.AdminAbuse do
	Config.DevLiveActions[action] = true
end
Config.DevLiveActions.announce = true -- ogłoszenie na środku ekranu na wszystkich serwerach (AnnounceService)

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

-- Łysa Góra: portal za Stawem Utopca, otwiera się graczom z co najmniej unlockCoins monet
-- (tylko z bagien, więc trzeba też mieć otwarte bagna). Symulator (tools/economy_sim.luau, 4.11):
-- bagna na maks. 5 h 42 min, góra otwarta 6 h 39 min, ulepszenia góry na maks. 9 h 12 min.
Config.Mountain = {
	unlockCoins = 10000000,
	halfWidth = 56,
	portal = { x = 44, z = 2418 }, -- z boku Stawu Utopca (staw zajmuje środek końca bagien)
	returnPortal = { x = 0, z = 3008 }, -- na Polanie Zielarki, prowadzi do chatki
	camp = { x = 0, z = 3024 }, -- tu ląduje gracz po przejściu i po zgaśnięciu latarni na górze
	path = 3.5, -- pół szerokości kamiennej ścieżki środkiem góry
}

-- Plac Portali za chatką: kamienny plac z miejscami na portale do kolejnych światów.
-- Środkowe miejsce zajmuje skrót do jaskini, boczne czekają na następne światy („Wkrótce”).
Config.PortalPlaza = {
	center = { x = 0, z = -84 },
	radius = 30,
	slots = { -24, 0, 24 }, -- x kolejnych portali; wszystkie stoją na z = Config.Cave.shortcut.z
	-- Który świat ma portal na którym miejscu (reszta to fundamenty „Wkrótce...”)
	worlds = { [0] = "cave", [-24] = "swamp", [24] = "mountain" } :: { [number]: string },
}

-- ===== Zakupy za Robuxy (developer products) =====
-- id: numer produktu z Creator Hub (Monetization → Developer Products). 0 = jeszcze nie utworzony:
-- w Studio przycisk i tak działa (serwer daje rzecz za darmo, żeby dało się testować),
-- w prawdziwej grze przycisk jest ukryty.
export type ProductDef = { id: number, key: string, icon: string, price: number? } -- price: cena do pokazania, zanim przyjdzie z Robloxa (i w Studio)
Config.Products = {
	rescue = { id = 3724758636, key = "PRODUCT_RESCUE", icon = "💾" }, -- uratuj koszyk po zgaśnięciu latarni / złapaniu
	boom = { id = 3724757048, key = "PRODUCT_BOOM", icon = "🍄" }, -- Wysyp dla całego serwera
	-- Twój Wysyp: to samo co Wysyp (Config.Boom), ale tylko dla kupującego. NA TEST: id = 0, więc w Studio
	-- „kupuje się” za darmo, a na żywej grze karta jest ukryta. Żeby wrzucić do sklepu: załóż produkt
	-- w Creator Hub (zwykły, nie Unlisted), wpisz tu jego numer, cena z Robloxa zastąpi `price`.
	boomSolo = { id = 0, key = "PRODUCT_BOOM_SOLO", icon = "🍄", price = 49 },
	oil = { id = 3724758135, key = "PRODUCT_OIL", icon = "🛢️" }, -- pełna latarnia od razu, w dowolnym miejscu
	harvest = { id = 3724757863, key = "PRODUCT_HARVEST", icon = "⚡" }, -- od razu dochód ogródka z Config.Garden.harvestMinutes
	luck = { id = 3724757551, key = "PRODUCT_LUCK", icon = "🍀" }, -- mikstura szczęścia: więcej mutacji
	-- x2 skrzyni w ogródku (Config.ChestX2): podwaja jeden odbiór. W Creator Hub ustaw je jako Unlisted
	-- (kupione poza grą nie miałyby czego podwoić) i z tymi cenami.
	x2s = { id = 0, key = "PRODUCT_X2", icon = "x2", price = 19 },
	x2m = { id = 0, key = "PRODUCT_X2", icon = "x2", price = 39 },
	x2l = { id = 0, key = "PRODUCT_X2", icon = "x2", price = 79 },
	x2xl = { id = 0, key = "PRODUCT_X2", icon = "x2", price = 149 },
} :: { [string]: ProductDef }

-- x2 skrzyni: po odbiorze monet ze skrzyni (albo w oknie „Witaj z powrotem”) gracz może za Robuxy dostać
-- drugi raz tyle samo. Cena zależy od tego, ile minut dochodu ogródka było w skrzyni (liczone przy
-- napełnianiu, więc nie da się tanio podwoić dużej skrzyni, sadząc drogi grzyb tuż przed odbiorem).
Config.ChestX2 = {
	minMinutes = 15, -- mniej minut w skrzyni = bez oferty
	tiers = {
		{ product = "x2s", fromMinutes = 15 },
		{ product = "x2m", fromMinutes = 40 },
		{ product = "x2l", fromMinutes = 120 },
		{ product = "x2xl", fromMinutes = 240 },
	},
	cardCooldown = 600, -- karta z ofertą po odbiorze przy skrzyni najwyżej co tyle sekund
	cardDeclines = 3, -- po tylu odmowach z rzędu karta nie wraca do końca sesji
	welcomeDelay = 2.5, -- okno „Witaj z powrotem” tyle sekund po pojawieniu się postaci
}
-- Kolejność kart w sklepie (ratunek ma własny przycisk na czarnym ekranie)
Config.ShopOrder = { "boom", "boomSolo", "luck", "oil", "harvest" }

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
	first_mushroom = 3569275503907076, -- pierwszy grzyb w koszyku
	cave = 2082056460324259, -- otwarty portal do jaskini
	swamp = 1696489879521185, -- otwarte bagna
	gold = 3766445876669935, -- pierwszy złoty grzyb
	rainbow = 1207892509814056, -- pierwszy tęczowy grzyb
	leszy = 4437565651201625, -- okradziony Leszy
	skarbnik = 3635009068161156, -- okradziony Skarbnik
	utopiec = 1005403357582209, -- okradziony Utopiec
	atlas_page = 2883145295440744, -- cała strona Grzybopedii odkryta
	grandmaster = 0, -- Arcygrzybiarz: cała księga tęczowa
	lifesaver = 3740386354746845, -- podniesiony kumpel
	streak7 = 4091627784779983, -- 7 dni logowania z rzędu
	halloween2026 = 1589520696458272, -- Halloween 2026: 100 cukierków w czasie eventu
	mountain = 3977568312918006, -- otwarta Łysa Góra
	jaga = 3897097733097783, -- okradziona Baba Jaga
	cosmic = 0, -- pierwszy kosmiczny grzyb
	forge_first = 511688787129005, -- pierwszy grzyb z Moździerza Zielarki
	forge_collection = 0, -- wszystkie gatunki z kuźni
	winter2026 = 0, -- Zima 2026: 100 płatków śniegu w czasie eventu
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
	finalizeAt = 1794787200, -- 2026-11-16 00:00 UTC: do tej chwili tablica rankingu stoi i przyjmuje zaległe wyniki
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
		duplicateScale = 3, -- skórka, którą już masz: monety (x skala nagród)
		outcomes = {
			{ id = "coins", weight = 28, scale = 1 },
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
	-- Wspólny cel serwera „Kocioł się gotuje”: cukierki ze sprzedaży dyń na tym serwerze pchają pasek.
	-- Nagroda: mikstura szczęścia proporcjonalna do wkładu (budżet celu = target × secondsPerCandy,
	-- niezależnie od tego, na ile kont rozłożono wkład), najwyżej maxPerGoal na cel i maxPerDay na konto
	-- dziennie (licznik w profilu, data.eventGoals). Szczęście nie zmienia szansy na dynie.
	goal = {
		target = 200,
		secondsPerCandy = 3,
		maxPerGoal = 600,
		maxPerDay = 1800,
	},
	-- Konta wykluczone z rankingu cukierków (testy, oszustwa): UserId. Deweloperzy (DevUserIds, twórca)
	-- są wykluczeni zawsze. Wykluczenie działa na każdej drodze publikacji wyniku.
	rankingBanned = {} :: { number },
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

-- ===== Zima (event, Shared/Winter) =====
-- Włącza się sama według daty (os.time, UTC); wcześniej nic z niej nie widać (bez przycisku, tytułów,
-- dekoracji i oszronionych grzybów). W tym czasie:
--   oszronione grzyby (cecha „frost” z Config.EventTags, x2 wartości) rosną w każdym świecie,
--   a sprzedane u skupywacza dają płatki śniegu (flakesByWorld: zależnie od świata grzyba);
--   płatki (licznik stats.snowflakes) prowadzą po ścieżce nagród (track), nagrody przychodzą same;
--   kalendarz adwentowy: od 1 do 24 grudnia jeden prezent dziennie (tylko dzisiejsze okienko);
--   choinka z prezentami przy chatce: wrzuca się płatki z kieszeni, wypada prezent albo psikus;
--   w lesie pada śnieg, drzewa i ziemia są oszronione, nocą gra zimowa muzyka.
-- Po evencie oszronione grzyby przestają rosnąć, a zdobyte tytuły, skórki i grzyby zostają.
Config.Winter = {
	startsAt = 1796083200, -- 2026-12-01 00:00 UTC
	endsAt = 1799280000, -- 2027-01-07 00:00 UTC (do Trzech Króli włącznie)
	frostChance = 0.06, -- szansa na oszroniony grzyb (stała, szczęście jej nie zmienia)
	boomFrostChance = 0.5, -- „Zamieć” z panelu DEV (jednorazowy odrost lasu wszystkim)
	flakesByWorld = { forest = 1, cave = 2, swamp = 3, mountain = 4 } :: { [string]: number },
	questFlakes = 2, -- za każde ukończone zadanie dnia w czasie eventu
	badgeFlakes = 100, -- odznaka Config.Badges.winter2026
	-- Ścieżka nagród (płatki zebrane łącznie, wydawanie na choince ich nie cofa).
	-- kind: "title" (tytuł z Titles, rarity), "luck" (mikstura na seconds), "skin" (skórka z skins)
	track = {
		{ flakes = 10, kind = "title", id = "TITLE_SNOWBALL", rarity = "rare", icon = "⛄" },
		{ flakes = 30, kind = "luck", seconds = 900, icon = "🍀" },
		{ flakes = 60, kind = "skin", id = "ice_lantern", icon = "🧊" },
		{ flakes = 100, kind = "title", id = "TITLE_FROST_SPIRIT", rarity = "epic", icon = "❄️" },
		{ flakes = 150, kind = "skin", id = "candy_cane", icon = "🍬" },
		{ flakes = 200, kind = "title", id = "TITLE_WINTER_KING", rarity = "legendary", icon = "👑" },
	} :: { { flakes: number, kind: string, id: string?, rarity: string?, seconds: number?, scale: number?, icon: string } },
	-- Skórki narzędzi w dłoni (zostają na zawsze, Shared/Skins). slot: która rzecz w dłoni się zmienia
	skins = {
		ice_lantern = { slot = "lantern", key = "SKIN_ICE_LANTERN", icon = "🧊" },
		candy_cane = { slot = "knife", key = "SKIN_CANDY_CANE", icon = "🍬" },
	} :: { [string]: { slot: string, key: string, icon: string } },
	-- Choinka z prezentami przy chatce: wrzuca się cost płatków (z kieszeni), wypada prezent
	-- albo nieszkodliwy psikus (tylko wygląd na chwilę, nic nie zabiera).
	tree = {
		cost = 5,
		cooldown = 1.5,
		duplicateScale = 3, -- skórka, którą już masz: monety (x skala nagród)
		outcomes = {
			{ id = "coins", weight = 28, scale = 1 },
			{ id = "luck", weight = 15, seconds = 300 },
			{ id = "flakes", weight = 6, amount = 12 }, -- tylko do kieszeni, ścieżki nie przesuwa
			{ id = "skin_lantern", weight = 4, skin = "ice_lantern" },
			{ id = "skin_knife", weight = 4, skin = "candy_cane" },
			{ id = "trick_snowman", weight = 12, seconds = 60, trick = true }, -- głowa bałwana
			{ id = "trick_frost", weight = 12, seconds = 120, trick = true }, -- latarnia świeci lodowym światłem
			{ id = "trick_snowball", weight = 10, trick = true }, -- śnieżka w ekran
			{ id = "trick_flurry", weight = 9, seconds = 45, trick = true }, -- śnieżyca wokół gracza
		} :: { { id: string, weight: number, scale: number?, seconds: number?, amount: number?, skin: string?, trick: boolean? } },
	},
	-- Kalendarz adwentowy: dzień 1 = startsAt (1 grudnia, UTC). Otworzyć można tylko dzisiejsze
	-- okienko (przegapione zostają zamknięte). coins: jednostki nagród (× Progress.rewardScale, w MONETACH),
	-- flakes: płatki do kieszeni i na ścieżkę, luck: sekundy mikstury szczęścia.
	advent = {
		{ coins = 2 },
		{ flakes = 5 },
		{ luck = 600 },
		{ coins = 3 },
		{ flakes = 6 },
		{ coins = 5 },
		{ luck = 600 },
		{ flakes = 6 },
		{ coins = 3 },
		{ flakes = 8 },
		{ luck = 900 },
		{ coins = 5 },
		{ flakes = 8 },
		{ coins = 3 },
		{ luck = 900 },
		{ flakes = 10 },
		{ coins = 4 },
		{ coins = 6 },
		{ flakes = 10 },
		{ luck = 1200 },
		{ coins = 5 },
		{ flakes = 12 },
		{ coins = 6 },
		{ coins = 10, flakes = 20 }, -- Wigilia
	} :: { { coins: number?, flakes: number?, luck: number? } },
	adventTitle = 12, -- tytuł TITLE_ADVENT za tyle otwartych okienek
	-- Muzyka nocą w lesie w czasie eventu. Licencjonowane: APM, DistroKid.
	playlist = {
		"rbxassetid://9046740461", -- Winter Holidays
		"rbxassetid://1838667764", -- Christmas Tree
		"rbxassetid://9046741231", -- Wrapping Gifts
		"rbxassetid://140347288034746", -- Winter Glow
		"rbxassetid://140732695067309", -- Cozy Future Christmas Lights
		"rbxassetid://140596895991475", -- Christmas Morning Magic
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
		-- Łysa Góra: wiedźmie i mroczne utwory, które już grają w innych światach (licencje sprawdzone)
		mountain = {
			"rbxassetid://120013530647101", -- Baba Yaga's Witch House Part 6
			"rbxassetid://1843408841", -- Tableau 7 – Ensorcellement
			"rbxassetid://88402307111260", -- Dark Woods
			"rbxassetid://71207032544256", -- Catacombs
			"rbxassetid://9125603091", -- coś się budzi (eerie)
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
		-- Łysa Góra (Pro Sound Effects): grzmot daleki i bliski, wiatr, gdy czarownica przemyka nad głową
		thunder = "rbxassetid://9120018172",
		thunderClose = "rbxassetid://9120019063",
		witchFly = "rbxassetid://9120698415",
	},
}

-- Ile sekund po zgaśnięciu latarni / złapaniu da się jeszcze uratować koszyk.
-- buttonSeconds: jak długo widać przycisk; serverSeconds: zapas na okno płatności Robloxa.
Config.Rescue = { buttonSeconds = 15, serverSeconds = 40 }

-- Wysyp: przez tyle sekund grzyby u wszystkich na serwerze odrastają szybciej i częściej mutują
Config.Boom = { seconds = 600, regrowFactor = 0.35, luck = 1.5 }

-- Mikstura szczęścia: przez tyle sekund mutacje u kupującego są dwa razy częstsze
Config.LuckPotion = { seconds = 900, luck = 2 }

-- Grupa Old Owl Studios (właściciel gry). Członek grupy ma +10% szczęścia na mutacje (liczone jak płatne
-- bonusy, w pełni), tytuł „Old Owl Member” i raz na konto paczkę powitalną: monety i miksturę szczęścia.
-- CommunityService sprawdza członkostwo na serwerze.
Config.Community = {
	groupId = 463484833,
	luck = 1.1,
	-- Monety w paczce: giftReward × Progress.rewardScale (jednostka nagród świata w MONETACH, w lesie 1600),
	-- tak jak nagroda za logowanie (0,5–3 jednostki). 1 = 1600 monet w lesie, więcej po jaskini i bagnach.
	giftReward = 1,
	giftLuckSeconds = 900,
	recheckSeconds = 10, -- najczęściej co tyle gracz może poprosić o ponowne sprawdzenie (po dołączeniu)
	friendLuck = 1.1, -- gdy na serwerze jest ktoś ze znajomych z Robloxa (obaj mają bonus)
	guideInvites = 3, -- tytuł „Przewodnik”: tylu graczy weszło z twojego zaproszenia
}

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
	speed = 25, -- studs/s; próg ucieczki sprawdza Progress.bootsToEscape i test bramki jaskini
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

-- ===== Chatka Baby Jagi =====
-- Wiedźma z polskich i słowiańskich baśni: lata w moździerzu, miotłą zamiata za sobą ślady, a jej
-- chatka stoi na kurzej stopce i sama się obraca. Ogródek z Zielem Baby Jagi jest za chatką na szczycie.
-- ===== Kuźnia Grzybów: Moździerz Zielarki na Placu Portali =====
-- Wersja 3 (runa, projekt „Kuźnia Grzybów UI” z 5.11): gracz wrzuca DOWOLNE 3 grzyby i płaci opłatę
-- (feeShare wkładu). Runa sumuje ich wartość (wkład), losuje próg (tiers: ułamek wkładu) i wyłania grzyb
-- ze wszystkich zwykłych gatunków gry o wartości najbliższej celowi (jeden z `nearest` najbliższych).
-- Wariant wyniku: szansa na mutację rośnie z „gorącem” wkładu (rangi i cechy trzech grzybów), a najlepszy
-- grzyb wkładu wyznacza górną granicę (o rangę wyżej). Cechy trzech grzybów przechodzą na wynik (maxTags).
-- Ukryte przepisy (recipes) i trójki strażników (specials) działają dalej: z szansą recipeOdds.hit dają
-- gatunek tylko z kuźni (wariant = najsłabszy z trzech, w recipeOdds.lucky o rangę wyżej), a w pozostałych
-- przypadkach runa losuje jak zwykle. Grzybów z kuźni nie da się posadzić ani wrzucić z powrotem.
export type ForgeTier = {
	id: string,
	key: string, -- nazwa progu (CSV)
	lo: number, -- cel losowany w przedziale [lo, hi) × wkład (logarytmicznie równomiernie)
	hi: number,
	chance: number,
	color: { number },
}
export type ForgeInput = { s: string, tag: string? }
export type ForgeRecipe = {
	id: string, -- id gatunku wyniku (forgeOnly)
	inputs: { ForgeInput }, -- trzy różne gatunki, kolejność wrzucenia bez znaczenia
	world: string, -- od jakiego świata przepis działa ("swamp" / "mountain")
	jaga: boolean?, -- działa dopiero po ucieczce przed Babą Jagą (bestiary.jaga.escaped)
}
export type ForgeSpecial = {
	id: string, -- id gatunku wyniku (forgeOnly, klasa mythic/secret)
	sets: { { string } }, -- dowolny z tych zestawów trzech gatunków (kolejność bez znaczenia)
	minRank: number, -- każdy grzyb co najmniej tej rangi wariantu (3 = tęczowy)
}
Config.Forge = {
	station = { x = -17, z = -69, radius = 7 }, -- moździerz stoi z boku Placu Portali
	cooldown = 6, -- sekund między połączeniami jednego gracza (animacja runy trwa ok. 5,5 s)
	revealDelay = 5.8, -- po tylu sekundach serwer wysyła komunikaty o wyniku (po odsłonięciu w oknie)
	-- Progi runy: wynik celuje w [lo, hi) × wkład. Średnio ok. 0,88 wkładu, więc z opłatą kuźnia zjada monety.
	tiers = {
		{ id = "bust", key = "FORGE_TIER_BUST", lo = 0.05, hi = 0.4, chance = 0.22, color = { 139, 143, 148 } },
		{ id = "worse", key = "FORGE_TIER_WORSE", lo = 0.4, hi = 0.85, chance = 0.36, color = { 192, 138, 84 } },
		{ id = "similar", key = "FORGE_TIER_SIMILAR", lo = 0.85, hi = 1.25, chance = 0.25, color = { 239, 232, 210 } },
		{ id = "better", key = "FORGE_TIER_BETTER", lo = 1.25, hi = 2.5, chance = 0.14, color = { 95, 211, 138 } },
		{ id = "great", key = "FORGE_TIER_GREAT", lo = 2.5, hi = 6, chance = 0.03, color = { 201, 139, 255 } },
	} :: { ForgeTier },
	nearest = 3, -- wynik to losowy z tylu gatunków najbliższych celowi
	maxTags = 4, -- najwyżej tyle cech przechodzi na wynik (najcenniejsze)
	-- Szansa na wariant rangi k (do górnej granicy): szansa z Config.Variants × (base + gorąco × gain[k]).
	-- Gorąco = Σ (ranga + tagHeat × liczba cech) trzech grzybów / heatFull, najwyżej 1.
	mutation = { base = 0.5, gain = { 4, 8, 20, 40 }, heatFull = 9, tagHeat = 0.5 },
	recipeOdds = { hit = 0.7, lucky = 0.08 }, -- przepis trafia w 70% (w tym 8% o rangę wyżej), reszta to runa
	-- Wskazówki do ukrytych przepisów (Forge.hints): co tyle połączeń w moździerzu Grzybopedia odsłania
	-- kolejny składnik (gatunek) nieodkrytego przepisu; trzeci składnik zostaje „❔” (szuka się go „Ciepło!”)
	hintEvery = 5,
	hintSlots = 2,
	feeShare = 0.08, -- opłata = taka część wartości trzech wrzuconych grzybów
	minFee = 5,
	-- Średni wynik nigdy nie przekracza tej części (wrzucone + opłata): gdy trójka może dać więcej, niż jest
	-- warta (przepisy, tanie grzyby z mutacjami), opłata rośnie do tej granicy (Forge.preview)
	maxReturn = 0.9,
	recipes = {
		{ id = "forge_mossbell", inputs = { { s = "bay_bolete", tag = "mossy" }, { s = "porcini", tag = "glowing" }, { s = "bog_bell" } }, world = "swamp" },
		{ id = "forge_emberpearl", inputs = { { s = "pearl", tag = "crystal" }, { s = "obsidian", tag = "abyssal" }, { s = "bog_pearl" } }, world = "swamp" },
		{ id = "forge_glasscap", inputs = { { s = "lantern_shroom", tag = "crystal" }, { s = "glowing_agaric", tag = "glowing" }, { s = "moon_lily" } }, world = "swamp" },
		{ id = "forge_runemorel", inputs = { { s = "witch_hat", tag = "cursed" }, { s = "hex_cluster", tag = "hexed" }, { s = "raven_bracket" } }, world = "mountain" },
		{ id = "forge_mooncoral", inputs = { { s = "sabbath_puffball", tag = "hexed" }, { s = "moon_hat", tag = "moonlit" }, { s = "night_eye" } }, world = "mountain" },
		{ id = "forge_eclipsestar", inputs = { { s = "heart_of_mountain", tag = "abyssal" }, { s = "earthstar", tag = "moonlit" }, { s = "night_eye" } }, world = "mountain", jaga = true },
	} :: { ForgeRecipe },
	-- Trzy różne grzyby strażników, każdy co najmniej tęczowy: bez Jagi = mityczny, z Jagą = sekretny
	specials = {
		{ id = "fern_flower", sets = { { "leszy_crown", "skarbnik_truffle", "utopiec_chalice" } }, minRank = 3 },
		{ id = "veles_eye", sets = {
			{ "jaga_toadstool", "leszy_crown", "skarbnik_truffle" },
			{ "jaga_toadstool", "leszy_crown", "utopiec_chalice" },
			{ "jaga_toadstool", "skarbnik_truffle", "utopiec_chalice" },
		}, minRank = 3 },
	} :: { ForgeSpecial },
}

Config.JagaLair = {
	centerX = 0,
	centerZ = 3440, -- środek ogródka (chatka stoi bliżej, na hutZ)
	hutZ = 3418,
	chaseFromZ = 3412, -- Jaga wylatuje spod drzwi chatki, czyli bliżej polany niż ogródek (Mountain.jagaOrigin)
	radius = 16,
	spots = 3,
	spotRadius = 5,
	respawnSeconds = 420,
	turnSeconds = 14, -- chatka robi pełny obrót w tyle sekund (z przerwami, patrz Mountain.hutFacing)
	watchCone = 0.55, -- iloczyn skalarny: chatka „patrzy” na gracza, gdy jest przed jej drzwiami
}

Config.Jaga = {
	-- Lata w moździerzu. Było 43 (szybciej niż buty 16 = 40): na zboczu, przy ognisku w kręgu kamieni
	-- i na kotłach gracz traci ok. 10% prędkości i Jaga doganiała go tuż przed polaną nawet na butach 16.
	-- Przy 36 butami 14+ ucieka się z zapasem także z tą stratą (symulacja w teście „Baba Jaga: zapas”).
	speed = 36,
	wakeDelay = 2.5, -- chatka odwrócona: Jaga potrzebuje chwili, żeby wylecieć
	wakeDelayWatched = 0.3, -- chatka patrzy na gracza: Jaga wylatuje od razu
	catchRadius = 4,
	giveUpSeconds = 55,
	-- O tyle studs bliżej polany niż środek ogródka startuje (spod drzwi chatki); Economy.escapes to odejmuje
	lead = Config.JagaLair.centerZ - Config.JagaLair.chaseFromZ,
}

-- Kruki Baby Jagi (Wiedźmi Las i Kotły): kruk wybiera gracza, nad nim cień, po chwili nurkuje.
-- Trafiony gubi najtańszy grzyb z koszyka; kruk upuszcza go kawałek dalej (można podnieść).
Config.Ravens = {
	zones = { witchwood = true, cauldrons = true },
	every = 9, -- co tyle sekund (średnio) kruk wybiera gracza w tych strefach
	warn = 1.5, -- tyle sekund widać cień przed nurkowaniem
	radius = 4, -- promień cienia (trafienie, gdy gracz jest w środku)
	dropDistance = 10, -- tak daleko kruk upuszcza grzyb
	dropSeconds = 45, -- tyle leży na ziemi, potem znika
}

-- Kotły Sabatu: trujące opary wokół kotłów. W chmurze olej pali się szybciej.
Config.Cauldrons = {
	count = 7,
	fumeRadius = 9,
	fumeDrain = 2, -- mnożnik spalania oleju w oparach
}

Config.Utopiec = {
	speed = 27.5, -- próg butów 8 (28); nowe poziomy bagienne dają dalszą przewagę
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
-- (także gdy jesteś offline, do limitu). Skrzynia mieści dochód z kilku godzin (ulepszenie Skrzynia):
-- pełna = grządki nic nie dokładają, aż właściciel odbierze monety. Tak samo w grze i offline, więc
-- siedzenie AFK nie daje więcej niż jedna pełna skrzynia, a powrót co kilka godzin się opłaca. Inni gracze mogą wyrwać ci posadzony grzyb, ale muszą go
-- donieść do swojego ogródka, niosąc go nad głową wolniej niż zwykle. Dogonisz złodzieja = grzyb wraca.
Config.Garden = {
	-- Prostokąt: szerokość wzdłuż płotu z furtką, głębokość od furtki do tylnego płotu (studs).
	-- Za furtką ścieżka i placyk z przyciskami, dalej żwirowy dziedziniec z grządkami (alejki co 3 study),
	-- pod tylnym płotem półka z reliktami (World/Garden).
	width = 28,
	depth = 36,
	maxBeds = 9, -- tyle grządek stoi w ogródku; odblokowane są pierwsze upgradeStat("beds")
	incomeRate = 0.04, -- posadzony grzyb daje co minutę taką część swojej wartości (oddaje się w 25 min)
	-- Offline: pełny dochód przez offlineFullMinutes, dalej offlineSlowRate dochodu, łącznie najwyżej
	-- offlineMinutes (8 h nieobecności = 2 h + 6 h × 25% = 3,5 h dochodu, o ile zmieści się w skrzyni)
	offlineFullMinutes = 120,
	offlineSlowRate = 0.25,
	offlineMinutes = 480,
	harvestMinutes = 30, -- produkt za Robuxy: tyle minut dochodu od razu
	-- Ochrona ogródka po kradzieży (sekundy): pierwsza kradzież 25 s, druga z rzędu 1 min, kolejne 2 min.
	-- Licznik kradzieży zeruje się, gdy właściciel wróci do swojego ogródka (Economy.stealProtection).
	stealProtection = { 25, 60, 120 },
	-- Złodziej musi zebrać tyle grzybów w lesie od wejścia do gry albo od swojej ostatniej kradzieży,
	-- żeby nie dało się tylko czekać przy ogródkach (Economy.stealPicksLeft)
	stealForestPicks = 5,
	thiefCooldown = 8, -- ten sam złodziej może kraść co tyle sekund
	guardRadius = 10, -- właściciel bliżej przycisków = nie da się kraść
	promptDistance = 6, -- przyciski na placyku (sadzenie, kradzież)
	chestPromptDistance = 5, -- odbiór ze skrzyni przy furtce
	shelfPromptDistance = 10, -- półka z reliktami (mierzone od środka półki, ma 21 studs)
	carry = {
		-- Prędkość złodzieja z łupem względem zwykłej, według rangi wariantu (0 = bez wariantu)
		speedByRank = { [0] = 0.85, [1] = 0.8, [2] = 0.7, [3] = 0.6, [4] = 0.55 },
		guardianSpeed = 0.6, -- korony, trufle i kielichy strażników są najcięższe
		tagRadius = 6, -- właściciel bliżej złodzieja = odbiera łup
		timeout = 60, -- po tylu sekundach łup wraca do właściciela
	},
	-- Ogródki na mapie (środki działek): po trzy z każdej strony chatki, furtką do środka polany (dwa
	-- ostatnie za chatką, po bokach Placu Portali). Furtki stoją przy x = ±27 i ±31; ogródek rośnie w głąb,
	-- w stronę lasu (polana jest tu szersza, Zones[1].halfWidth). Ile ogródków, tylu graczy ma grządki,
	-- więc rozmiar serwera w ustawieniach gry (Max Players) musi być taki sam: 6.
	plots = {
		{ x = -45, z = -30 },
		{ x = 45, z = -30 },
		{ x = -45, z = 10 },
		{ x = 45, z = 10 },
		{ x = -49, z = -62 }, -- trochę dalej od środka niż reszta: róg nie może wejść na okrągły bruk placu
		{ x = 49, z = -62 },
	},
}

return Config
