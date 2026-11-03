--!strict
-- Ekspedycja do Głębokich Komór (jaskinia): liczby i czysta logika (testy w Lune).
-- Plan: docs/plans/cave-expedition.md. W kodzie „Delve”, bo „wyprawa” (Expedition.luau) to wspólne latarnie.
--
-- Gracz bierze zlecenie z tablicy w Obozie (sam albo z ekipą do 4 osób), schodzi przez szczelinę w Otchłani
-- do własnej kopii trzech komór: Zawalony Chodnik → Zalana Komora (ognisko = znalezisko zabezpieczone)
-- → opcjonalnie Krypta Skarbnika po dodatkowe trofeum. Nagrody to relikty do kolekcji (zestawy, odłamki
-- z duplikatów, renowacja i oprawa za monety, regał w ogródku). Bez monet z komór i bez mnożników zarobków.
-- Relikty nie zależą od mikstury szczęścia ani Wysypu.

local Delve = {}

-- ===== Relikty =====

export type RelicDef = {
	id: string,
	set: string,
	rare: boolean,
	key: string, -- nazwa (GameStrings.csv)
	icon: string,
	color: { number },
}

Delve.SETS = { "miner", "deep" }
Delve.SET_KEYS = { miner = "DELVE_SET_MINER", deep = "DELVE_SET_DEEP" } :: { [string]: string }

Delve.RELICS = {
	{ id = "miner_pick", set = "miner", rare = false, key = "RELIC_MINER_PICK", icon = "⛏️", color = { 170, 140, 110 } },
	{ id = "miner_lamp", set = "miner", rare = false, key = "RELIC_MINER_LAMP", icon = "🪔", color = { 255, 190, 90 } },
	{ id = "miner_helmet", set = "miner", rare = false, key = "RELIC_MINER_HELMET", icon = "⛑️", color = { 230, 200, 80 } },
	{ id = "miner_map", set = "miner", rare = true, key = "RELIC_MINER_MAP", icon = "🗺️", color = { 120, 200, 230 } },
	{ id = "deep_geode", set = "deep", rare = false, key = "RELIC_DEEP_GEODE", icon = "🔮", color = { 255, 110, 70 } },
	{ id = "deep_pearl", set = "deep", rare = false, key = "RELIC_DEEP_PEARL", icon = "🦪", color = { 220, 230, 255 } },
	{ id = "deep_bell", set = "deep", rare = false, key = "RELIC_DEEP_BELL", icon = "🔔", color = { 255, 210, 90 } },
	{ id = "deep_fossil", set = "deep", rare = true, key = "RELIC_DEEP_FOSSIL", icon = "🍄", color = { 200, 120, 255 } },
} :: { RelicDef }

local BY_ID: { [string]: RelicDef } = {}
for _, def in Delve.RELICS do
	BY_ID[def.id] = def
end

function Delve.relic(id: string): RelicDef?
	return BY_ID[id]
end

function Delve.relicsOf(set: string): { RelicDef }
	local list = {}
	for _, def in Delve.RELICS do
		if def.set == set then
			table.insert(list, def)
		end
	end
	return list
end

-- Szansa zwykłego reliktu : rzadkiego w losowaniu z zestawu (3 zwykłe po 3, rzadki 1 → rzadki 1/10)
Delve.WEIGHT_COMMON = 3
Delve.WEIGHT_RARE = 1
-- Duplikat zamienia się w odłamki; z odłamków składa się brakujący relikt (ochrona przed pechem)
Delve.SHARDS_DUPLICATE = { common = 3, rare = 8 }
Delve.CRAFT_COST = { common = 12, rare = 30 }
-- Renowacja (zakurzony relikt → na regał) i oprawa (brąz / srebro / złoto): zlew monet, plan z 3.11
Delve.RESTORE_COST = { common = 50000, rare = 150000 }
Delve.FRAMES = {
	{ key = "DELVE_FRAME_1", coins = 500000, shards = 5 },
	{ key = "DELVE_FRAME_2", coins = 1500000, shards = 10 },
	{ key = "DELVE_FRAME_3", coins = 5000000, shards = 20 },
}
Delve.CRYPT_SHARDS = 4 -- premia z Krypty oprócz reliktu
Delve.HARD_SHARDS = 2 -- premia za trudniejszy stan komór (zawał, czuwający Skarbnik)

local function tier(def: RelicDef): string
	return if def.rare then "rare" else "common"
end

-- ===== Zapis =====

export type RelicState = { r: boolean, f: number } -- r = odnowiony (stoi na regale), f = oprawa 0..3
export type Save = {
	relics: { [string]: RelicState }, -- tylko posiadane
	shards: number,
	daily: number, -- dzień (UTC), w którym gracz odebrał zlecenie dnia; -1 = nigdy
}

function Delve.emptySave(): Save
	return { relics = {}, shards = 0, daily = -1 }
end

local function finite(x: any): boolean
	return typeof(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

-- Zapis z DataStore: tylko znane relikty, liczby w zakresie
function Delve.readSave(raw: any): Save
	local save = Delve.emptySave()
	if typeof(raw) ~= "table" then
		return save
	end
	if typeof(raw.relics) == "table" then
		for id, state in raw.relics do
			if typeof(id) == "string" and BY_ID[id] and typeof(state) == "table" then
				local frame = if finite(state.f) then math.clamp(math.floor(state.f), 0, #Delve.FRAMES) else 0
				local restored = state.r == true
				save.relics[id] = { r = restored, f = if restored then frame else 0 }
			end
		end
	end
	if finite(raw.shards) then
		save.shards = math.clamp(math.floor(raw.shards), 0, 100000)
	end
	if finite(raw.daily) then
		save.daily = math.max(-1, math.floor(raw.daily))
	end
	return save
end

-- ===== Losowanie i nagrody =====

-- roll: liczba 0..1 (Random:NextNumber albo math.random w testach)
function Delve.rollRelic(set: string, roll: number): string?
	local list = Delve.relicsOf(set)
	local total = 0
	for _, def in list do
		total += if def.rare then Delve.WEIGHT_RARE else Delve.WEIGHT_COMMON
	end
	if total <= 0 then
		return nil
	end
	local target = math.clamp(roll, 0, 0.999999) * total
	for _, def in list do
		target -= if def.rare then Delve.WEIGHT_RARE else Delve.WEIGHT_COMMON
		if target < 0 then
			return def.id
		end
	end
	return list[#list].id
end

-- Dodaje relikt do kolekcji. Zwraca (nowy?, ile odłamków za duplikat)
function Delve.grant(save: Save, id: string): (boolean, number)
	local def = BY_ID[id]
	if not def then
		return false, 0
	end
	if save.relics[id] then
		local shards = Delve.SHARDS_DUPLICATE[tier(def)]
		save.shards += shards
		return false, shards
	end
	save.relics[id] = { r = false, f = 0 }
	return true, 0
end

function Delve.craftCost(id: string): number?
	local def = BY_ID[id]
	return if def then Delve.CRAFT_COST[tier(def)] else nil
end

-- Składanie brakującego reliktu z odłamków
function Delve.craft(save: Save, id: string): boolean
	local cost = Delve.craftCost(id)
	if not cost or save.relics[id] or save.shards < cost then
		return false
	end
	save.shards -= cost
	save.relics[id] = { r = false, f = 0 }
	return true
end

function Delve.restoreCost(id: string): number?
	local def = BY_ID[id]
	return if def then Delve.RESTORE_COST[tier(def)] else nil
end

-- Renowacja za monety: zwraca koszt (do odjęcia przez wołającego) albo nil, gdy nie można
function Delve.canRestore(save: Save, id: string, coins: number): number?
	local state = save.relics[id]
	local cost = Delve.restoreCost(id)
	if not state or state.r or not cost or coins < cost then
		return nil
	end
	return cost
end

-- Kolejna oprawa: (monety, odłamki) albo nil
function Delve.nextFrame(save: Save, id: string): (number?, number?)
	local state = save.relics[id]
	if not state or not state.r then
		return nil, nil
	end
	local frame = Delve.FRAMES[state.f + 1]
	if not frame then
		return nil, nil
	end
	return frame.coins, frame.shards
end

function Delve.canFrame(save: Save, id: string, coins: number): number?
	local cost, shards = Delve.nextFrame(save, id)
	if not cost or not shards or coins < cost or save.shards < shards then
		return nil
	end
	return cost
end

-- Czy zestaw jest kompletny (wszystkie relikty posiadane)
function Delve.setComplete(save: Save, set: string): boolean
	for _, def in Delve.relicsOf(set) do
		if not save.relics[def.id] then
			return false
		end
	end
	return true
end

-- ===== Ranga ekspedytora (z liczników: zabezpieczone ekspedycje + wyniesione trofea z Krypty) =====

Delve.RANKS = { 3, 8, 15, 25, 40 } -- tyle punktów na rangę 1..5

function Delve.rank(points: number): (number, number?)
	local rank = 0
	for index, goal in Delve.RANKS do
		if points >= goal then
			rank = index
		end
	end
	return rank, Delve.RANKS[rank + 1]
end

-- ===== Zlecenia =====

export type KindDef = { id: string, key: string, desc: string, goal: number }
Delve.KINDS = {
	{ id = "rubble", key = "DELVE_KIND_RUBBLE", desc = "DELVE_KIND_RUBBLE_DESC", goal = 3 }, -- odgruzuj 3 zawały
	{ id = "chest", key = "DELVE_KIND_CHEST", desc = "DELVE_KIND_CHEST_DESC", goal = 1 }, -- znajdź skrzynię (4 kryjówki)
	{ id = "samples", key = "DELVE_KIND_SAMPLES", desc = "DELVE_KIND_SAMPLES_DESC", goal = 3 }, -- 3 świecące próbki
} :: { KindDef }

export type ModifierDef = { id: string, key: string, icon: string, minRank: number, hard: boolean }
-- Stan komór na tę ekspedycję; trudniejsze odblokowuje ranga i dają premię odłamków
Delve.MODIFIERS = {
	{ id = "calm", key = "DELVE_MOD_CALM", icon = "🕯️", minRank = 0, hard = false },
	{ id = "flood", key = "DELVE_MOD_FLOOD", icon = "🌊", minRank = 0, hard = false }, -- wysoka woda
	{ id = "collapse", key = "DELVE_MOD_COLLAPSE", icon = "🪨", minRank = 1, hard = true }, -- częstsze osuwiska
	{ id = "watch", key = "DELVE_MOD_WATCH", icon = "👁️", minRank = 2, hard = true }, -- czuwający Skarbnik
} :: { ModifierDef }

function Delve.kind(id: string): KindDef?
	for _, def in Delve.KINDS do
		if def.id == id then
			return def
		end
	end
	return nil
end

function Delve.modifier(id: string): ModifierDef?
	for _, def in Delve.MODIFIERS do
		if def.id == id then
			return def
		end
	end
	return nil
end

export type Offer = {
	kind: string,
	set: string,
	modifier: string,
	daily: boolean, -- zlecenie dnia: nagrodą jest konkretny relikt dnia
	relic: string?, -- relikt dnia
}

function Delve.dayIndex(t: number): number
	return t // 86400
end

-- Relikt dnia: ten sam dla wszystkich graczy danego dnia (UTC)
function Delve.dailyRelic(day: number): string
	return Delve.RELICS[day % #Delve.RELICS + 1].id
end

-- Trzy zlecenia na tablicy: po jednym każdego rodzaju, losowy zestaw i stan komór (z dozwolonych dla rangi).
-- Jedno z nich jest zleceniem dnia, jeśli gracz go dziś nie odebrał. rand(): liczba 0..1.
function Delve.makeOffers(rand: () -> number, rank: number, day: number, dailyDone: boolean): { Offer }
	local mods = {}
	for _, def in Delve.MODIFIERS do
		if rank >= def.minRank then
			table.insert(mods, def.id)
		end
	end
	local offers: { Offer } = {}
	for _, kind in Delve.KINDS do
		table.insert(offers, {
			kind = kind.id,
			set = Delve.SETS[math.clamp(math.floor(rand() * #Delve.SETS) + 1, 1, #Delve.SETS)],
			modifier = mods[math.clamp(math.floor(rand() * #mods) + 1, 1, #mods)],
			daily = false,
		})
	end
	if not dailyDone then
		local relic = Delve.dailyRelic(day)
		local def = BY_ID[relic]
		local pick = offers[math.clamp(math.floor(rand() * #offers) + 1, 1, #offers)]
		pick.daily = true
		pick.relic = relic
		pick.set = def.set
	end
	return offers
end

-- ===== Komory: położenie i olej =====
-- Każda ekspedycja (solo albo ekipa) dostaje własną kopię komór, daleko w bok od jaskini (oś X),
-- ale w zakresie Z Otchłani: świat = jaskinia (budzi w obozie, mrok i muzyka jaskini), a różne
-- ekipy nigdy się nie spotkają (odstęp większy niż zasięg pomocy i łączenia latarni).

Delve.SLOTS = 6 -- tyle kopii, ilu graczy mieści serwer
Delve.SLOT_X = 400 -- x początku pierwszej kopii
Delve.SLOT_SPACING = 450 -- odstęp między kopiami (~200 studs) > zasięg pomocy kumpla (150)
Delve.CENTER_Z = 1360 -- środek komór (Otchłań: 1290–1420)
Delve.FLOOR_Y = 0
Delve.CEILING = 18
Delve.MAX_PARTY = 4
Delve.PREPARE_SECONDS = 600 -- przyjęte zlecenie czeka na zejście najwyżej tyle
Delve.RUN_SECONDS = 1500 -- ekspedycja kończy się sama po tylu sekundach (zabezpieczone nagrody zostają)

-- Odcinki wzdłuż X (od początku kopii) i ich połowa szerokości (Z)
export type Section = { id: string, key: string, x1: number, x2: number, half: number }
Delve.SECTIONS = {
	{ id = "hall", key = "DELVE_HALL", x1 = 0, x2 = 18, half = 9 },
	{ id = "tunnel", key = "DELVE_TUNNEL", x1 = 18, x2 = 92, half = 7 },
	{ id = "flooded", key = "DELVE_FLOODED", x1 = 92, x2 = 172, half = 22 },
	{ id = "camp", key = "DELVE_BONFIRE", x1 = 172, x2 = 190, half = 9 },
	{ id = "crypt", key = "DELVE_CRYPT", x1 = 190, x2 = 250, half = 18 },
} :: { Section }

-- Ważne miejsca (lokalne x, z względem początku kopii i CENTER_Z)
Delve.SPOTS = {
	spawn = { x = 6, z = 0 },
	blockage = 50, -- zawał w poprzek Chodnika (do odgruzowania zawsze)
	oil = { { x = 10, z = -6 }, { x = 97, z = -4 }, { x = 178, z = 5 } }, -- haki z olejem (tankowanie)
	alcoves = { { x = 30, z = 4.5 }, { x = 66, z = -4.5 }, { x = 82, z = 4.5 } }, -- zawały pod ścianą (zlecenie „rubble”)
	hides = { { x = 112, z = 16 }, { x = 130, z = -17 }, { x = 150, z = 15 }, { x = 160, z = -12 } }, -- kryjówki skrzyni
	samples = { { x = 26, z = -5.5 }, { x = 42, z = 5.5 }, { x = 74, z = 5.5 }, { x = 104, z = -12 }, { x = 140, z = 2 }, { x = 166, z = 18 } },
	bonfire = { x = 180, z = 0 },
	exit = { x = 185, z = -7 }, -- lina w górę (powrót do obozu)
	cryptDoor = 190,
	altar = { x = 244, z = 0 },
	-- Krypta: filary w dwóch rzędach, wnęki przy ścianach (tam strażnik nie widzi), trasa obchodu
	pillars = { 200, 210, 220, 230, 240 },
	niches = { { x1 = 203, x2 = 208, z = 1 }, { x1 = 223, x2 = 228, z = 1 }, { x1 = 213, x2 = 218, z = -1 }, { x1 = 233, x2 = 238, z = -1 } },
	patrol = { { x = 198, z = 0 }, { x = 236, z = 0 }, { x = 236, z = 11 }, { x = 214, z = 11 }, { x = 214, z = -11 }, { x = 236, z = -11 }, { x = 236, z = 0 } },
}

Delve.WATER_Y = 1.4 -- poziom wody w Zalanej Komorze (wysoka woda: FLOOD_Y)
Delve.FLOOD_Y = 2.6
Delve.WALK_Y = 3 -- wierzch kładek
Delve.WATER_DRAIN = 2.5 -- brodzenie w wodzie pali olej szybciej

-- Pełna latarnia w komorach starcza na tyle sekund (bez względu na poziom ulepszenia oleju), a knot
-- jaskini (Kryształowy wkład) wydłuża ten czas. Haki z olejem są na wejściu, w Zalanej Komorze i przy ognisku.
Delve.LANTERN_SECONDS = 240
Delve.REFILL_RADIUS = 4.5
Delve.REFILL_PER_SECOND = 0.25 -- część pełnej latarni na sekundę przy haku

function Delve.slotOrigin(slot: number): (number, number)
	return Delve.SLOT_X + (slot - 1) * Delve.SLOT_SPACING, Delve.CENTER_Z
end

-- Czy punkt jest w którejś kopii komór (poza zwykłą jaskinią)
function Delve.isInside(position: Vector3): boolean
	return position.X >= Delve.SLOT_X - 20
		and position.X <= Delve.SLOT_X + (Delve.SLOTS - 1) * Delve.SLOT_SPACING + 270
		and math.abs(position.Z - Delve.CENTER_Z) <= 40
end

-- Kopia (1..SLOTS) i lokalne x, z punktu; nil poza komorami
function Delve.locate(position: Vector3): (number?, number, number)
	if not Delve.isInside(position) then
		return nil, 0, 0
	end
	local slot = math.clamp(math.floor((position.X - Delve.SLOT_X + 30) / Delve.SLOT_SPACING) + 1, 1, Delve.SLOTS)
	local x0, z0 = Delve.slotOrigin(slot)
	return slot, position.X - x0, position.Z - z0
end

function Delve.sectionAt(localX: number): Section?
	for _, section in Delve.SECTIONS do
		if localX >= section.x1 and localX < section.x2 then
			return section
		end
	end
	return nil
end

-- Spalanie oleju na sekundę w komorach. oilMax: pełna latarnia gracza; wick: mnożnik knota jaskini
-- (Kryształowy wkład, 1 → 0,5); inWater: brodzi w wodzie; group: mnożnik wspólnej wyprawy (Expedition.drain).
function Delve.drain(oilMax: number, wick: number, inWater: boolean, group: number?): number
	local base = oilMax / Delve.LANTERN_SECONDS * math.clamp(wick, 0.3, 1)
	return base * (if inWater then Delve.WATER_DRAIN else 1) * (group or 1)
end

-- Ile sekund wystarczy pełna latarnia (do opisu na tablicy)
function Delve.lanternSeconds(wick: number): number
	return Delve.LANTERN_SECONDS / math.clamp(wick, 0.3, 1)
end

-- Czy stopy gracza są w wodzie (feetY: wysokość stóp, flood: wysoka woda)
function Delve.wet(localX: number, feetY: number, flood: boolean): boolean
	local section = Delve.sectionAt(localX)
	if not section or section.id ~= "flooded" then
		return false
	end
	return feetY < (if flood then Delve.FLOOD_Y else Delve.WATER_Y) - 0.2
end

-- Czy gracz chowa się we wnęce Krypty (strażnik go nie widzi)
function Delve.inNiche(localX: number, localZ: number): boolean
	for _, niche in Delve.SPOTS.niches do
		if localX >= niche.x1 and localX <= niche.x2 and localZ * niche.z >= 13.5 then
			return true
		end
	end
	return false
end

-- Czy strażnik Krypty widzi gracza: blisko z każdej strony albo dalej w stożku przed sobą
-- (offset: od strażnika do gracza, płasko; look: kierunek patrzenia; watch: czuwający Skarbnik)
function Delve.guardSees(offset: Vector3, look: Vector3, watch: boolean): boolean
	local distance = offset.Magnitude
	local guard = Delve.GUARD
	if distance <= guard.near then
		return true
	end
	if distance > (if watch then guard.sightWatch else guard.sight) then
		return false
	end
	return offset.Unit:Dot(look.Unit) >= guard.cone
end

-- ===== Zagrożenia =====

Delve.ROCK = { every = 3.5, everyCollapse = 2, warn = 1.2, radius = 3.5, oilLoss = 0.15 } -- osuwiska w Chodniku
Delve.CLEAR_HOLD = { normal = 4, collapse = 6, alcove = 2.5 } -- przytrzymanie przy zawałach (s)
Delve.GUARD = { speed = 9, speedWatch = 13, carryBonus = 2, sight = 11, sightWatch = 15, near = 4.5, cone = 0.35 }

return Delve
