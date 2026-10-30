--!strict
-- Pora dnia liczona z zegara: na każdym serwerze ta sama noc, to samo zdarzenie i ten sam świt.
-- Czyste funkcje (bez API Robloxa), więc testy w Lune sprawdzają dokładnie ten kod.

local Config = require(script.Parent.Config)

export type Phase = {
	phase: string, -- "night" albo "dawn"
	index: number, -- numer cyklu (noc + świt)
	endsAt: number, -- os.time(), kiedy kończy się ta faza
	event: Config.NightEventDef, -- zdarzenie tej nocy (o świcie: tej, która właśnie minęła)
	nextEvent: Config.NightEventDef, -- zdarzenie następnej nocy (do prognozy)
}

local Cycle = {}

function Cycle.length(): number
	return Config.Cycle.nightSeconds + Config.Cycle.dawnSeconds
end

-- Liczba z [0, 1) zależna tylko od numeru cyklu (prosty generator liniowy, bez Random)
function Cycle.hash(index: number): number
	local x = (index * 1103515245 + 12345) % 2147483648
	x = (x * 1103515245 + 12345) % 2147483648
	return x / 2147483648
end

local eventById: { [string]: Config.NightEventDef } = {}
for _, event in Config.Cycle.events do
	eventById[event.id] = event
end

function Cycle.getEvent(id: any): Config.NightEventDef?
	return if typeof(id) == "string" then eventById[id] else nil
end

-- Halloween: co Config.Halloween.spiritEvery noc, która zaczyna się w czasie eventu, to Noc Dziadów
local function spiritNight(index: number): boolean
	local h = (Config :: any).Halloween
	if not h or index % h.spiritEvery ~= 0 then
		return false
	end
	local start = index * (Config.Cycle.nightSeconds + Config.Cycle.dawnSeconds)
	return start >= h.startsAt and start < h.endsAt
end

function Cycle.eventFor(index: number): Config.NightEventDef
	local spirit = eventById.spirit_night
	if spirit and spiritNight(index) then
		return spirit
	end
	local events = Config.Cycle.events
	local total = 0
	for _, event in events do
		total += event.weight
	end
	local target = Cycle.hash(index) * total
	local acc = 0
	for _, event in events do
		acc += event.weight
		if target < acc then
			return event
		end
	end
	return events[1] -- (nie zdarza się: hash < 1; ostatnia jest Noc Dziadów z wagą 0)
end

function Cycle.at(t: number): Phase
	local length = Cycle.length()
	local index = math.floor(t / length)
	local offset = t - index * length
	local night = Config.Cycle.nightSeconds
	if offset < night then
		return {
			phase = "night",
			index = index,
			endsAt = index * length + night,
			event = Cycle.eventFor(index),
			nextEvent = Cycle.eventFor(index + 1),
		}
	end
	return {
		phase = "dawn",
		index = index,
		endsAt = (index + 1) * length,
		event = Cycle.eventFor(index),
		nextEvent = Cycle.eventFor(index + 1),
	}
end

-- Zdarzenie, które teraz działa (o świcie żadne)
function Cycle.activeEvent(t: number): Config.NightEventDef?
	local phase = Cycle.at(t)
	return if phase.phase == "night" then phase.event else nil
end

-- Pokolenie lasu z kalendarza = numer ostatniego świtu (las odrasta wszystkim o świcie)
function Cycle.generation(t: number): number
	local phase = Cycle.at(t)
	return if phase.phase == "dawn" then phase.index else phase.index - 1
end

-- Serwer odnawia las, gdy widać świt (shownPhase po nadpisaniu przywołaną nocą) i kalendarz jest
-- już w nowszym pokoleniu niż las tego serwera. Przywołana noc przykrywająca świt odkłada reset.
function Cycle.shouldRegrow(shownPhase: string, serverGen: number, t: number): boolean
	return shownPhase == "dawn" and Cycle.generation(t) > serverGen
end

-- Zapisany las wraca 1:1, gdy jest z pokolenia serwera albo nowszego (inny serwer już miał świt),
-- ale nie z przyszłości kalendarza (śmieci w zapisie)
function Cycle.canRestore(savedGen: number, serverGen: number, t: number): boolean
	return savedGen >= serverGen and savedGen <= Cycle.generation(t)
end

-- Czy las gracza (zapisany z pokoleniem sessionGen) odnawia się przy resecie serwera do targetGen.
-- Gracz, który ten świt dostał już na innym serwerze, nie dostaje go drugi raz.
function Cycle.needsRegrow(sessionGen: number?, targetGen: number): boolean
	return sessionGen == nil or sessionGen < targetGen
end

return Cycle
