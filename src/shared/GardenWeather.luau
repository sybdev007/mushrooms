--!strict
-- Pogoda w ogródku (czysta logika bez Robloxa, testy w Lune). Liczby są w Config.GardenWeather.
--   Po każdej nocy (o świcie) jej zdarzenie (Cycle.eventFor) może dać JEDNEMU grzybowi w ogródku gracza
--   cechę: deszcz Mech, pełnia Księżycowy, mgła Blask, krwawy księżyc Krwawy (tylko z pogody).
--   Grzyb z którąkolwiek z tych cech nic więcej od pogody nie dostanie, więc cechy się nie piętrzą.
--   Wynik zależy tylko od gracza, numeru nocy i zawartości ogródka (bez losowania przy każdym wejściu),
--   więc ponowne wejście do gry nie losuje nocy od nowa. Noce, gdy gracza nie było, liczą się przy
--   wejściu (najwyżej Config.GardenWeather.maxNights ostatnich).

local Config = require(script.Parent.Config)
local Cycle = require(script.Parent.Cycle)
local Economy = require(script.Parent.Economy)

local GardenWeather = {}

export type Item = { s: string, v: string?, x: { string }?, t: number? }
export type Result = { slot: number, tag: string, event: string }

-- Cechy, które daje pogoda (i które blokują następną)
GardenWeather.TAGS = {} :: { [string]: boolean }
for _, rule in Config.GardenWeather.events do
	GardenWeather.TAGS[rule.tag] = true
end

-- Numer ostatniej nocy, która już się skończyła (o świcie: ta, która właśnie minęła)
function GardenWeather.lastNight(t: number): number
	local phase = Cycle.at(t)
	return if phase.phase == "dawn" then phase.index else phase.index - 1
end

-- Czy grzyb może jeszcze dostać cechę od pogody
function GardenWeather.canGet(item: Item): boolean
	if Economy.isForgeOnly(item.s) then
		return false
	end
	local tags: { string } = item.x or {}
	for _, tag in tags do
		if GardenWeather.TAGS[tag] then
			return false
		end
	end
	return true
end

-- Liczba z [0, 1) zależna od gracza, nocy i „kanału” (bez Random: ta sama za każdym razem)
local function roll(userId: number, night: number, channel: number): number
	return Cycle.hash((night * 7 + channel) * 131 + userId % 1000003)
end

-- Co ta noc dała ogródkowi: grządka i cecha albo nil
function GardenWeather.rollNight(userId: number, night: number, planted: { Item }): Result?
	local event = Cycle.eventFor(night)
	local rule = Config.GardenWeather.events[event.id]
	if not rule or roll(userId, night, 1) >= rule.chance then
		return nil
	end
	local candidates = {}
	for slot, item in planted do
		if GardenWeather.canGet(item) then
			table.insert(candidates, slot)
		end
	end
	if #candidates == 0 then
		return nil
	end
	local pick = candidates[math.floor(roll(userId, night, 2) * #candidates) + 1]
	return { slot = pick, tag = rule.tag, event = event.id }
end

-- Noce do policzenia: od tej po ostatnio policzonej do upTo, najwyżej maxNights ostatnich
function GardenWeather.range(done: number, upTo: number): (number, number)
	local first = math.max(done + 1, upTo - Config.GardenWeather.maxNights + 1)
	return first, upTo
end

-- Policz noce po kolei i dopisz cechy do grzybów (zmienia planted). Zwraca listę zmian.
function GardenWeather.apply(userId: number, done: number, upTo: number, planted: { Item }): { Result }
	local results = {}
	local first, last = GardenWeather.range(done, upTo)
	for night = first, last do
		local result = GardenWeather.rollNight(userId, night, planted)
		if result then
			local item = planted[result.slot]
			local tags = table.clone(item.x or {})
			table.insert(tags, result.tag)
			item.x = tags
			table.insert(results, result)
		end
	end
	return results
end

-- Średnio ile nowych cech na noc (do opisu i testu balansu)
function GardenWeather.expectedPerNight(): number
	local total = 0
	for _, event in Config.Cycle.events do
		total += event.weight
	end
	local expected = 0
	for _, event in Config.Cycle.events do
		local rule = Config.GardenWeather.events[event.id]
		if rule then
			expected += event.weight / total * rule.chance
		end
	end
	return expected
end

return GardenWeather
