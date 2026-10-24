--!strict
-- Czyste funkcje ekonomii: bez Instance, bez losowości z Robloxa.
-- Dzięki temu testy w tests/economy.spec.luau sprawdzają dokładnie ten sam kod co gra.

local Config = require(script.Parent.Config)

export type BasketItem = {
	s: string, -- id gatunku
	g: boolean, -- czy złota mutacja
	d: number?, -- mnożnik suszenia (grzyb ukradziony z suszarni); brak = świeży
}

export type DryingItem = {
	s: string,
	g: boolean,
	t: number, -- os.time(), kiedy grzyb zawisł na suszarni
}

local Economy = {}

local speciesById: { [string]: Config.SpeciesDef } = {}
local speciesByZone: { [number]: { Config.SpeciesDef } } = {}
local groveSpecies: { Config.SpeciesDef } = {}

for _, species in Config.Species do
	speciesById[species.id] = species
	if species.grove then
		table.insert(groveSpecies, species)
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
		if z < zones[index].endZ then
			return index
		end
	end
	return #zones
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

-- dried: mnożnik suszenia (1 = świeży). Wynik zaokrąglony do pełnej monety.
function Economy.mushroomValue(speciesId: string, golden: boolean, dried: number?): number
	local species = speciesById[speciesId]
	if not species then
		return 0
	end
	local value = species.value * (if golden then Config.GoldenMultiplier else 1) * (dried or 1)
	return math.floor(value + 0.5)
end

function Economy.basketValue(basket: { BasketItem }): number
	local sum = 0
	for _, item in basket do
		sum += Economy.mushroomValue(item.s, item.g, item.d)
	end
	return sum
end

-- ===== Suszarnia =====

-- Mnożnik wartości po `elapsed` sekundach suszenia: od 1 do (1 + bonus), liniowo
function Economy.dryMultiplier(elapsed: number): number
	local progress = math.clamp(elapsed / Config.Drying.seconds, 0, 1)
	return 1 + Config.Drying.bonus * progress
end

function Economy.dryProgress(elapsed: number): number
	return math.clamp(elapsed / Config.Drying.seconds, 0, 1)
end

function Economy.dryingValue(item: DryingItem, now: number): number
	return Economy.mushroomValue(item.s, item.g, Economy.dryMultiplier(now - item.t))
end

function Economy.rackValue(rack: { DryingItem }, now: number): number
	local sum = 0
	for _, item in rack do
		sum += Economy.dryingValue(item, now)
	end
	return sum
end

-- Indeks najcenniejszego grzyba na suszarni (to bierze złodziej). nil = pusta.
function Economy.mostValuableIndex(rack: { DryingItem }, now: number): number?
	local best: number? = nil
	local bestValue = -1
	for index, item in rack do
		local value = Economy.dryingValue(item, now)
		if value > bestValue then
			best = index
			bestValue = value
		end
	end
	return best
end

-- Które grzyby z koszyka zawiesić: najcenniejsze, najwyżej `free` sztuk. Zwraca indeksy koszyka.
function Economy.pickForDrying(basket: { BasketItem }, free: number): { number }
	local order = {}
	for index, item in basket do
		-- Ukradzione suszone grzyby już nie schną drugi raz
		if not item.d then
			table.insert(order, index)
		end
	end
	table.sort(order, function(a, b)
		local va = Economy.mushroomValue(basket[a].s, basket[a].g)
		local vb = Economy.mushroomValue(basket[b].s, basket[b].g)
		if va ~= vb then
			return va > vb
		end
		return a < b
	end)
	local result = {}
	for i = 1, math.min(free, #order) do
		table.insert(result, order[i])
	end
	return result
end

-- ===== Leszy =====

-- Czy gracz biegnący prosto z prędkością `speed` dobiegnie `distance` studs do chatki,
-- zanim dogoni go Leszy, który rusza z tego samego miejsca po Config.Leszy.wakeDelay sekundach.
function Economy.escapesLeszy(distance: number, speed: number): boolean
	local leszy = Config.Leszy
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
function Economy.returnOilNeeded(z: number, speed: number): number
	if speed <= 0 then
		return math.huge
	end
	local zones = Config.Zones
	local current = Economy.zoneIndexAt(z)
	local oil = 0
	for index = current, 2, -1 do
		local zone = zones[index]
		local from = if index == current then math.min(z, zone.endZ) else zone.endZ
		local distance = math.max(from - zone.startZ, 0)
		oil += distance / speed * zone.oilDrain
	end
	return oil
end

-- Czy już czas wracać: olej na powrót z zapasem przekracza to, co zostało w latarni
function Economy.shouldTurnBack(z: number, speed: number, oil: number): boolean
	if Economy.zoneIndexAt(z) == 1 then
		return false
	end
	return Economy.returnOilNeeded(z, speed) * Config.ReturnMargin >= oil
end

-- Ile grzybów las zabiera z koszyka, gdy zgaśnie latarnia
function Economy.engulfLoss(count: number): number
	return math.floor(count * Config.EngulfLossFraction)
end

return Economy
