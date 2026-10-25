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

function Cycle.eventFor(index: number): Config.NightEventDef
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
	return events[#events]
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

return Cycle
