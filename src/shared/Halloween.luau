--!strict
-- Event Halloween „Noc Dziadów” (czysta logika bez Robloxa, testy w Lune). Liczby są w Config.Halloween.
--   Dyniowe grzyby: cecha „pumpkin” (Config.EventTags), losowana tylko w czasie eventu.
--   Cukierki: za sprzedane dyniowe grzyby (zależnie od świata) i za zadania dnia; licznik stats.candy.
--   Ścieżka nagród: progi cukierków, nagrody przychodzą same (tytuły liczy Titles, resztę ProgressService).
--   Noc Dziadów: zdarzenie nocy z Cycle.eventFor (co trzecia noc w czasie eventu).

local Config = require(script.Parent.Config)
local Cycle = require(script.Parent.Cycle)
local Economy = require(script.Parent.Economy)

local Halloween = {}

Halloween.TAG = "pumpkin"
Halloween.SPIRIT_NIGHT = "spirit_night"
Halloween.TRACK = Config.Halloween.track

export type Item = { s: string, v: string?, x: { string }? }

function Halloween.active(t: number): boolean
	local h = Config.Halloween
	return t >= h.startsAt and t < h.endsAt
end

-- Sekundy do końca eventu (0 = już po)
function Halloween.secondsLeft(t: number): number
	return math.max(0, Config.Halloween.endsAt - t)
end

-- Szansa, że grzyb wyrośnie dyniowy. Stała (szczęście jej nie zmienia, żeby cukierków nie było
-- za dużo na głębszych światach): zwykła, w Noc Dziadów albo w czasie „Dyniowego wysypu”.
function Halloween.pumpkinChance(t: number, eventId: string?, boom: boolean?): number
	if not Halloween.active(t) then
		return 0
	end
	local h = Config.Halloween
	if boom then
		return h.boomPumpkinChance
	elseif eventId == Halloween.SPIRIT_NIGHT then
		return h.spiritPumpkinChance
	end
	return h.pumpkinChance
end

-- Czy gatunek może być dyniowy (błędne ogniki nie: nic nie są warte i zdradzałyby się kolorem)
function Halloween.canBePumpkin(speciesId: string): boolean
	local species = Economy.getSpecies(speciesId)
	return species ~= nil and not species.mimic
end

function Halloween.isPumpkin(item: Item): boolean
	return item.x ~= nil and table.find(item.x, Halloween.TAG) ~= nil
end

-- Cukierki za sprzedany grzyb: tylko dyniowy, więcej za głębsze światy
function Halloween.candyFor(item: Item): number
	if not Halloween.isPumpkin(item) then
		return 0
	end
	local species = Economy.getSpecies(item.s)
	if not species or species.mimic then
		return 0
	end
	return Config.Halloween.candyByWorld[Economy.zoneWorld(species.zone)] or 1
end

function Halloween.candyForList(items: { any }): number
	local total = 0
	for _, item in items do
		total += Halloween.candyFor(item)
	end
	return total
end

-- Ile progów ścieżki gracz osiągnął przy tylu cukierkach
function Halloween.reached(candy: number): number
	local count = 0
	for index, step in Halloween.TRACK do
		if candy >= step.candy then
			count = index
		end
	end
	return count
end

-- Progi osiągnięte od ostatniego razu (claimed = ile już dostał). Nie zmienia zapisu.
function Halloween.newSteps(claimed: number, candy: number): { number }
	local list = {}
	for index = math.max(claimed, 0) + 1, Halloween.reached(candy) do
		table.insert(list, index)
	end
	return list
end

-- Najbliższa Noc Dziadów: (start w os.time, czy już trwa). nil = w czasie eventu już żadnej nie będzie.
function Halloween.nextSpiritNight(t: number): (number?, boolean)
	local length = Cycle.length()
	local index = t // length
	for i = index, index + Config.Halloween.spiritEvery do
		if Cycle.eventFor(i).id == Halloween.SPIRIT_NIGHT then
			local start = i * length
			if t < start + Config.Cycle.nightSeconds then
				return start, t >= start
			end
		end
	end
	return nil, false
end

return Halloween
