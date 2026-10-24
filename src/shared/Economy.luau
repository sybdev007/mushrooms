--!strict
-- Czyste funkcje ekonomii: bez Instance, bez losowości z Robloxa.
-- Dzięki temu testy w tests/economy.spec.luau sprawdzają dokładnie ten sam kod co gra.

local Config = require(script.Parent.Config)

export type BasketItem = {
	s: string, -- id gatunku
	g: boolean, -- czy złota mutacja
}

local Economy = {}

local speciesById: { [string]: Config.SpeciesDef } = {}
local speciesByZone: { [number]: { Config.SpeciesDef } } = {}

for _, species in Config.Species do
	speciesById[species.id] = species
	local list = speciesByZone[species.zone]
	if not list then
		list = {}
		speciesByZone[species.zone] = list
	end
	table.insert(list, species)
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

function Economy.mushroomValue(speciesId: string, golden: boolean): number
	local species = speciesById[speciesId]
	if not species then
		return 0
	end
	return species.value * (if golden then Config.GoldenMultiplier else 1)
end

function Economy.basketValue(basket: { BasketItem }): number
	local sum = 0
	for _, item in basket do
		sum += Economy.mushroomValue(item.s, item.g)
	end
	return sum
end

-- Ile grzybów las zabiera z koszyka, gdy zgaśnie latarnia
function Economy.engulfLoss(count: number): number
	return math.floor(count * Config.EngulfLossFraction)
end

return Economy
