--!strict
-- Znalezisko Nocy (czysta logika bez Robloxa, testy w Lune). Liczby są w Config.NightFind.
--   Raz na noc na serwerze: kiedy wyrasta, gdzie (miejsca grzybów w głębi lasu, bez legowisk) i czy
--   niosący zdążył. Obiekty, przyciski i nagrody: NightFindService.

local Config = require(script.Parent.Config)
local Cycle = require(script.Parent.Cycle)
local Economy = require(script.Parent.Economy)

local NightFind = {}

export type Spot = { id: string, zone: number, position: Vector3, grove: boolean?, lair: boolean?, guardian: string? }

-- Kiedy tej nocy wyrasta Znalezisko (os.time) albo nil, gdy noc jest za krótka (serwer wstał późno)
-- r: liczba z [0, 1) (opóźnienie losowe), now: teraz
function NightFind.spawnTime(index: number, r: number, now: number): number?
	local length = Cycle.length()
	local nightStart = index * length
	local nightEnd = nightStart + Config.Cycle.nightSeconds
	local delay = Config.NightFind.delay
	local at = nightStart + delay[1] + math.floor(r * (delay[2] - delay[1]))
	at = math.max(at, now)
	if nightEnd - at < Config.NightFind.minLeft then
		return nil
	end
	return at
end

-- Miejsca, gdzie może wyrosnąć: zwykłe miejsca grzybów w lesie, od Config.NightFind.minZone
function NightFind.candidates(spots: { Spot }): { Spot }
	local list = {}
	for _, spot in spots do
		if
			not spot.grove
			and not spot.lair
			and not spot.guardian
			and spot.zone >= Config.NightFind.minZone
			and Economy.zoneWorld(spot.zone) == "forest"
			and not Economy.isSafeZone(spot.zone)
		then
			table.insert(list, spot)
		end
	end
	return list
end

-- Czy niosący jest już na polanie przy chatce: strefa 1, w jej szerokości i na wysokości ziemi
-- (review-petla P1: sam pas współrzędnej Z zaliczał też miejsca poza polaną, np. pod mapą)
NightFind.GROUND_Y = { -10, 40 }
function NightFind.delivered(position: Vector3): boolean
	local cabin = Config.Zones[1]
	return Economy.zoneIndexAt(position.Z) == 1
		and math.abs(position.X) <= (cabin.halfWidth or 80)
		and position.Y >= NightFind.GROUND_Y[1]
		and position.Y <= NightFind.GROUND_Y[2]
end

-- Ruch niosącego: „wiadro” dozwolonej drogi w poziomie. Co próbkę dolewa się prędkość × czas (z zapasem),
-- ruch je opróżnia; skok ponad zawartość to teleport. Pozycja dochodząca z lagiem naraz (kilka sekund
-- marszu w jednej próbce) mieści się, bo wiadro napełniało się, gdy stał; spadanie się nie liczy (pion).
-- Skutek: niosący nie dotrze do chatki szybciej niż ok. SPEED_MARGIN × jego prędkość chodu (postój
-- „na zapas” i skok nic nie dają: czekanie kosztuje tyle samo czasu co marsz).
-- Zwraca nową zawartość wiadra i czy to teleport.
NightFind.BUCKET_SECONDS = 3 -- najwyżej tyle sekund marszu na zapas (lag do ok. 3 s)
NightFind.SPEED_MARGIN = 1.25 -- skos, zjazd ze zbocza, zaokrąglenia
NightFind.JUMP_ALLOWANCE = 12 -- odrzut, wypchnięcie przez fizykę (jednorazowy dług, spłacany marszem)
function NightFind.moveCheck(bucket: number, speed: number, dt: number, moved: number): (number, boolean)
	local rate = math.max(speed, 1) * NightFind.SPEED_MARGIN
	local filled = math.min(bucket + rate * dt, rate * NightFind.BUCKET_SECONDS)
	if moved > filled + NightFind.JUMP_ALLOWANCE then
		return filled, true
	end
	-- Zapas na odrzut też się zużywa (wiadro schodzi poniżej zera), inaczej co próbkę dawałby darmowe studsy
	return filled - moved, false
end

-- Czy niosący jeszcze może dojść (nie wyszedł z lasu przez portal)
function NightFind.inForest(z: number): boolean
	return Economy.zoneWorld(Economy.zoneIndexAt(z)) == "forest"
end

-- Gatunek Znaleziska: jeden z Config.NightFind.rarePick najcenniejszych zwykłych gatunków strefy
-- (bez ogników, grzybów Gniazda, legowisk i kuźni). r: liczba z [0, 1).
function NightFind.pickSpecies(zone: number, r: number): string?
	local list = {}
	for _, species in Economy.speciesForZone(zone) do
		if not species.mimic and not species.grove and not species.lair and not species.guardian and not species.forgeOnly then
			table.insert(list, species)
		end
	end
	if #list == 0 then
		return nil
	end
	table.sort(list, function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.id < b.id
	end)
	local count = math.min(Config.NightFind.rarePick, #list)
	return list[math.clamp(math.floor(r * count) + 1, 1, count)].id
end

return NightFind
