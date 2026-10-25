--!strict
-- Czyste funkcje ekonomii: bez Instance, bez losowości z Robloxa.
-- Dzięki temu testy w tests/economy.spec.luau sprawdzają dokładnie ten sam kod co gra.

local Config = require(script.Parent.Config)

export type BasketItem = {
	s: string, -- id gatunku
	v: string?, -- wariant (silver / gold / rainbow); brak = zwykły
	x: { string }?, -- cechy z miejsca (mossy, glowing)
	d: number?, -- mnożnik suszenia (zostało ze starej suszarni w zapisach); brak = zwykły
}

-- Grzyb posadzony na grządce: to samo co w koszyku plus czas posadzenia
export type PlantItem = {
	s: string,
	v: string?,
	x: { string }?,
	d: number?,
	t: number, -- os.time(), kiedy grzyb został posadzony
}

local Economy = {}

local speciesById: { [string]: Config.SpeciesDef } = {}
local speciesByZone: { [number]: { Config.SpeciesDef } } = {}
local groveSpecies: { Config.SpeciesDef } = {}
local lairSpecies: { Config.SpeciesDef } = {}
local guardianLists: { [string]: { Config.SpeciesDef } } = {}

for _, species in Config.Species do
	speciesById[species.id] = species
	if species.grove then
		table.insert(groveSpecies, species)
	elseif species.lair then
		table.insert(lairSpecies, species)
	elseif species.guardian then
		local list = guardianLists[species.guardian]
		if not list then
			list = {}
			guardianLists[species.guardian] = list
		end
		table.insert(list, species)
	else
		local list = speciesByZone[species.zone]
		if not list then
			list = {}
			speciesByZone[species.zone] = list
		end
		table.insert(list, species)
	end
end

-- Gatunki, które rosną tylko w Gnieździe Leszego
function Economy.groveSpecies(): { Config.SpeciesDef }
	return groveSpecies
end

function Economy.lairSpecies(): { Config.SpeciesDef }
	return lairSpecies
end

-- Grzyby z legowiska danego strażnika ("leszy", "skarbnik", "utopiec")
function Economy.guardianSpecies(guardian: string): { Config.SpeciesDef }
	if guardian == "leszy" then
		return groveSpecies
	elseif guardian == "skarbnik" then
		return lairSpecies
	end
	return guardianLists[guardian] or {}
end

-- Którego strażnika jest ten grzyb (nil = zwykły grzyb)
function Economy.guardianOf(speciesId: string): string?
	local species = speciesById[speciesId]
	if not species then
		return nil
	elseif species.grove then
		return "leszy"
	elseif species.lair then
		return "skarbnik"
	end
	return species.guardian
end

-- Błędny ognik: wygląda jak grzyb, ale zerwanie kradnie olej
function Economy.isMimic(speciesId: string): boolean
	local species = speciesById[speciesId]
	return species ~= nil and species.mimic == true
end

-- Ulepszenie zmniejszające spalanie oleju w danym świecie (nil w lesie)
function Economy.worldOilUpgrade(world: string): string?
	return Config.WorldOilUpgrade[world]
end

-- ===== Mutacje =====

local variantById: { [string]: Config.VariantDef } = {}
for _, variant in Config.Variants do
	variantById[variant.id] = variant
end
local tagById: { [string]: Config.TagDef } = {}
for _, tag in Config.Tags do
	tagById[tag.id] = tag
end
-- Od najrzadszego: losowanie sprawdza najpierw tęczę, potem złoto, potem srebro
local variantsRarestFirst = table.clone(Config.Variants)
table.sort(variantsRarestFirst, function(a, b)
	return a.rank > b.rank
end)

function Economy.getVariant(id: string?): Config.VariantDef?
	return if id then variantById[id] else nil
end

function Economy.getTag(id: string): Config.TagDef?
	return tagById[id]
end

function Economy.variantRank(id: string?): number
	local variant = Economy.getVariant(id)
	return if variant then variant.rank else 0
end

-- Wariant dla liczby r z [0, 1). minRank > 0 wymusza co najmniej taką rangę (gwarancja).
-- luck: mnożnik szans na warianty (Wysyp, mikstura szczęścia); 1 = zwykłe szanse
function Economy.rollVariant(r: number, minRank: number?, luck: number?): string?
	local floor = minRank or 0
	r /= math.max(luck or 1, 1)
	local acc = 0
	for _, variant in variantsRarestFirst do
		acc += variant.chance
		if r < acc and variant.rank >= floor then
			return variant.id
		end
	end
	if floor > 0 then
		-- Gwarancja: najpospolitszy wariant, który spełnia próg
		for i = #variantsRarestFirst, 1, -1 do
			local variant = variantsRarestFirst[i]
			if variant.rank >= floor then
				return variant.id
			end
		end
	end
	return nil
end

-- Cechy, które mogą się pojawić w danej strefie
function Economy.tagsForZone(zone: number): { Config.TagDef }
	local list = {}
	for _, tag in Config.Tags do
		if tag.zone == zone then
			table.insert(list, tag)
		end
	end
	return list
end

-- Łączny mnożnik mutacji: wariant × (1 + Σ(cecha − 1))
function Economy.mutationMultiplier(variant: string?, tags: { string }?): number
	local def = Economy.getVariant(variant)
	local base = if def then def.mult else 1
	local bonus = 1
	for _, id in tags or {} do
		local tag = tagById[id]
		if tag then
			bonus += tag.mult - 1
		end
	end
	return base * bonus
end

-- Oczekiwany mnożnik losowego grzyba w strefie (do testów balansu)
function Economy.expectedMultiplier(zone: number): number
	local variantPart = 1
	for _, variant in Config.Variants do
		variantPart += variant.chance * (variant.mult - 1)
	end
	local tagPart = 1
	for _, tag in Economy.tagsForZone(zone) do
		tagPart += tag.chance * (tag.mult - 1)
	end
	return variantPart * tagPart
end

function Economy.getSpecies(id: string): Config.SpeciesDef?
	return speciesById[id]
end

function Economy.speciesForZone(zone: number): { Config.SpeciesDef }
	return speciesByZone[zone] or {}
end

-- Indeks strefy dla współrzędnej Z. Przed lasem = chatka, za lasem = ostatnia strefa.
function Economy.zoneIndexAt(z: number): number
	local zones = Config.Zones
	if z < zones[2].startZ then
		return 1
	end
	for index = 2, #zones do
		local zone = zones[index]
		if z < zone.startZ then
			return index - 1 -- przerwa między lasem a jaskinią należy do końca lasu
		end
		if z < zone.endZ then
			return index
		end
	end
	return #zones
end

-- Bezpieczna strefa (chatka, obozowisko): olej się nie pali, działa tankowanie i handel
function Economy.isSafeZone(index: number): boolean
	local zone = Config.Zones[index]
	return zone ~= nil and zone.safe == true
end

-- "forest" albo "cave"
function Economy.zoneWorld(index: number): string
	local zone = Config.Zones[index]
	return if zone then zone.world else "forest"
end

-- Ile oleju na sekundę pali się w strefie. caveScale: ulepszenie „Kryształowy wkład” (tylko w jaskini).
function Economy.oilDrain(index: number, caveScale: number?): number
	local zone = Config.Zones[index]
	if not zone then
		return 0
	end
	-- Mnożnik z ulepszenia świata (knot) działa poza lasem; caveScale to mnożnik dla świata tej strefy
	return zone.oilDrain * (if zone.world ~= "forest" then caveScale or 1 else 1)
end

-- Punkt, do którego wraca się w danym świecie (strzałka „Wracaj!”): drzwi chatki albo obozowisko
function Economy.homePoint(world: string): (number, number)
	if world == "cave" then
		return Config.Cave.camp.x, Config.Cave.camp.z
	elseif world == "swamp" then
		return Config.Swamp.camp.x, Config.Swamp.camp.z
	end
	return 0, -10
end

-- Wartość statystyki (np. zasięg latarni) na danym poziomie ulepszenia
function Economy.upgradeStat(id: string, level: number): number
	local def = Config.Upgrades[id]
	assert(def, "Nieznane ulepszenie: " .. id)
	return def.base + def.step * level
end

-- Koszt kupienia KOLEJNEGO poziomu. nil = poziom maksymalny.
function Economy.upgradeCost(id: string, level: number): number?
	local def = Config.Upgrades[id]
	assert(def, "Nieznane ulepszenie: " .. id)
	if level >= def.maxLevel then
		return nil
	end
	return math.floor(def.costBase * def.costGrowth ^ level + 0.5)
end

-- Losowanie gatunku w strefie. r to liczba z przedziału [0, 1).
function Economy.rollSpecies(zone: number, r: number): Config.SpeciesDef?
	local list = speciesByZone[zone]
	if not list or #list == 0 then
		return nil
	end
	local total = 0
	for _, species in list do
		total += species.weight
	end
	local target = r * total
	local acc = 0
	for _, species in list do
		acc += species.weight
		if target < acc then
			return species
		end
	end
	return list[#list]
end

-- variant / tags: mutacje, dried: mnożnik suszenia (1 = świeży). Wynik zaokrąglony do pełnej monety.
function Economy.mushroomValue(speciesId: string, variant: string?, tags: { string }?, dried: number?): number
	local species = speciesById[speciesId]
	if not species then
		return 0
	end
	local value = species.value * Economy.mutationMultiplier(variant, tags) * (dried or 1)
	return math.floor(value + 0.5)
end

function Economy.itemValue(item: BasketItem): number
	return Economy.mushroomValue(item.s, item.v, item.x, item.d)
end

function Economy.basketValue(basket: { BasketItem }): number
	local sum = 0
	for _, item in basket do
		sum += Economy.itemValue(item)
	end
	return sum
end

-- ===== Ogródek =====

-- Ile monet na minutę daje posadzony grzyb. fertilizer: mnożnik z ulepszenia Nawóz (1 = bez).
function Economy.plantIncome(item: BasketItem, fertilizer: number?): number
	return Economy.itemValue(item) * Config.Garden.incomeRate * (fertilizer or 1)
end

function Economy.gardenIncome(planted: { PlantItem }, fertilizer: number?): number
	local sum = 0
	for _, item in planted do
		sum += Economy.plantIncome(item, fertilizer)
	end
	return sum
end

-- Dochód za czas offline, najwyżej za Config.Garden.offlineMinutes
function Economy.offlineIncome(planted: { PlantItem }, fertilizer: number?, seconds: number): number
	local minutes = math.clamp(seconds / 60, 0, Config.Garden.offlineMinutes)
	return Economy.gardenIncome(planted, fertilizer) * minutes
end

local function extremeIndex(list: { BasketItem }, best: boolean): number?
	local found: number? = nil
	local foundValue = 0
	for index, item in list do
		local value = Economy.itemValue(item)
		if not found or (if best then value > foundValue else value < foundValue) then
			found = index
			foundValue = value
		end
	end
	return found
end

-- Indeks najcenniejszego posadzonego grzyba (to wyrywa złodziej). nil = pusto.
function Economy.mostValuableIndex(list: { BasketItem }): number?
	return extremeIndex(list, true)
end

-- Indeks najsłabszego posadzonego grzyba (ustępuje miejsca lepszemu). nil = pusto.
function Economy.weakestIndex(list: { BasketItem }): number?
	return extremeIndex(list, false)
end

-- Plan sadzenia z koszyka. Najpierw wolne grządki dostają najcenniejsze grzyby z koszyka,
-- potem lepszy grzyb z koszyka wypiera najsłabszy posadzony (ten jest sprzedawany).
-- Zwraca listę ruchów { basket = indeks w koszyku, replace = indeks grządki albo nil }.
-- Indeksy koszyka odnoszą się do koszyka sprzed zmian.
export type PlantMove = { basket: number, replace: number? }
function Economy.planPlanting(basket: { BasketItem }, planted: { PlantItem }, beds: number): { PlantMove }
	local order = {}
	for index in basket do
		table.insert(order, index)
	end
	table.sort(order, function(a, b)
		local va, vb = Economy.itemValue(basket[a]), Economy.itemValue(basket[b])
		if va ~= vb then
			return va > vb
		end
		return a < b
	end)
	local moves: { PlantMove } = {}
	-- Kopia wartości grządek, żeby planować wymiany bez ruszania prawdziwych danych
	local slots: { number } = {}
	for _, item in planted do
		table.insert(slots, Economy.itemValue(item))
	end
	for _, index in order do
		local value = Economy.itemValue(basket[index])
		if #slots < beds then
			table.insert(slots, value)
			table.insert(moves, { basket = index })
		else
			local weakest: number? = nil
			for slot, slotValue in slots do
				if not weakest or slotValue < slots[weakest] then
					weakest = slot
				end
			end
			if weakest and value > slots[weakest] then
				slots[weakest] = value
				table.insert(moves, { basket = index, replace = weakest })
			else
				break -- dalsze grzyby w koszyku są jeszcze słabsze
			end
		end
	end
	return moves
end

-- Mnożnik prędkości złodzieja niosącego ten grzyb (cięższy łup = wolniej)
function Economy.carrySpeed(item: BasketItem): number
	local carry = Config.Garden.carry
	local species = speciesById[item.s]
	if species and (species.grove or species.lair or species.guardian) then
		return carry.guardianSpeed
	end
	return carry.speedByRank[Economy.variantRank(item.v)] or carry.speedByRank[0]
end

-- ===== Leszy =====

-- Czy gracz biegnący prosto z prędkością `speed` dobiegnie `distance` studs do chatki,
-- zanim dogoni go Leszy, który rusza z tego samego miejsca po Config.Leszy.wakeDelay sekundach.
function Economy.escapesLeszy(distance: number, speed: number): boolean
	return Economy.escapes(distance, speed, Config.Leszy)
end

-- To samo dla dowolnego strażnika (Leszy, Skarbnik): ustawienia speed, wakeDelay, catchRadius
function Economy.escapes(distance: number, speed: number, leszy: { speed: number, wakeDelay: number, catchRadius: number }): boolean
	if speed <= 0 then
		return false
	end
	if leszy.speed <= speed then
		return true
	end
	-- Leszy w chwili t jest na L*(t - delay), gracz na v*t. Łapie, gdy różnica <= catchRadius.
	local catchTime = (leszy.speed * leszy.wakeDelay - leszy.catchRadius) / (leszy.speed - speed)
	return distance / speed < catchTime
end

-- Ile oleju zużyje powrót prosto do chatki z pozycji z przy danej prędkości chodu.
-- Liczy każdą strefę osobno, bo im głębiej, tym szybciej pali się olej.
-- W jaskini liczy drogę do obozowiska. caveScale: mnożnik spalania w jaskini (ulepszenie).
function Economy.returnOilNeeded(z: number, speed: number, caveScale: number?): number
	if speed <= 0 then
		return math.huge
	end
	local zones = Config.Zones
	local current = Economy.zoneIndexAt(z)
	local oil = 0
	for index = current, 1, -1 do
		local zone = zones[index]
		if zone.safe then
			break -- doszliśmy do chatki albo obozowiska
		end
		local from = if index == current then math.min(z, zone.endZ) else zone.endZ
		local distance = math.max(from - zone.startZ, 0)
		oil += distance / speed * Economy.oilDrain(index, caveScale)
	end
	return oil
end

-- Czy już czas wracać: olej na powrót z zapasem przekracza to, co zostało w latarni
function Economy.shouldTurnBack(z: number, speed: number, oil: number, caveScale: number?): boolean
	if Economy.isSafeZone(Economy.zoneIndexAt(z)) then
		return false
	end
	return Economy.returnOilNeeded(z, speed, caveScale) * Config.ReturnMargin >= oil
end

-- Ile grzybów las zabiera z koszyka, gdy zgaśnie latarnia
-- Stanowisko danego rodzaju, w którego kręgu stoi gracz ("oil" albo "shop"), albo nil.
-- Zwraca całą definicję, bo sklep w jaskini sprzedaje inne ulepszenia niż w chatce.
-- tolerance: zapas dla serwera (opóźnienie sieci).
function Economy.stationAt(kind: string, x: number, z: number, tolerance: number?): Config.StationDef?
	for _, station in Config.Stations do
		if station.kind == kind then
			local dx, dz = x - station.x, z - station.z
			local radius = station.radius + (tolerance or 0)
			if dx * dx + dz * dz <= radius * radius then
				return station
			end
		end
	end
	return nil
end

function Economy.atStation(kind: string, x: number, z: number, tolerance: number?): boolean
	return Economy.stationAt(kind, x, z, tolerance) ~= nil
end

-- Pierwsze stanowisko danego rodzaju w danym świecie (do budowy mapy)
function Economy.station(kind: string, world: string): Config.StationDef
	for _, station in Config.Stations do
		if station.kind == kind and station.world == world then
			return station
		end
	end
	error("Brak stanowiska " .. kind .. " w świecie " .. world)
end

-- Sklep: "forest" (chatka) albo "cave" (obozowisko); ulepszenie bez pola shop jest w chatce
function Economy.upgradeShop(id: string): string
	local def = Config.Upgrades[id]
	return if def and def.shop then def.shop else "forest"
end

-- Czy gracz może wejść do jaskini: raz otwarta zostaje otwarta
function Economy.canEnterCave(coins: number, unlocked: boolean?): boolean
	return unlocked == true or coins >= Config.Cave.unlockCoins
end

-- Bagna: tak samo, tylko z wyższym progiem
function Economy.canEnterSwamp(coins: number, unlocked: boolean?): boolean
	return unlocked == true or coins >= Config.Swamp.unlockCoins
end

-- Czy przedmiot z koszyka to korona z Gniazda Leszego (Leszy odbiera je, gdy złapie gracza)
function Economy.isGroveItem(speciesId: string): boolean
	local species = speciesById[speciesId]
	return species ~= nil and species.grove == true
end

-- Czy przedmiot z koszyka to Złota Trufla ze Skarbca Skarbnika
function Economy.isLairItem(speciesId: string): boolean
	local species = speciesById[speciesId]
	return species ~= nil and species.lair == true
end

function Economy.engulfLoss(count: number): number
	return math.floor(count * Config.EngulfLossFraction)
end

return Economy
