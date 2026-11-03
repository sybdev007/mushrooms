--!strict
-- Łysa Góra: wspólna logika serwera i klienta (bez API Robloxa, testy w Lune).
-- Chatka Baby Jagi obraca się według czasu serwera (Workspace:GetServerTimeNow), więc serwer liczy,
-- czy chatka „patrzy” na gracza, a klient obraca model u siebie tą samą funkcją, bez przesyłania
-- setek części przez sieć. Kotły Sabatu stoją w stałych miejscach: serwer liczy z nich trujące opary
-- (szybsze spalanie oleju), a mapa i klient stawiają w tych samych miejscach kotły i dym.

local Config = require(script.Parent.Config)

local Mountain = {}

-- Chatka: obraca się ćwierć obrotu naraz. Zatrzymanie i obrót w jednej ćwiartce:
local QUARTER = (Config.JagaLair.turnSeconds or 14) / 4
local HOLD = 0.65 -- część ćwiartki, przez którą chatka stoi w miejscu (reszta to obrót)

local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

-- Kąt obrotu chatki (radiany, wokół osi Y) w chwili t (sekundy czasu serwera).
-- 0 = drzwi patrzą na -Z (w stronę ścieżki i nadchodzących graczy).
function Mountain.hutYaw(t: number): number
	local k = math.floor(t / QUARTER)
	local f = (t - k * QUARTER) / QUARTER
	local base = (k % 4) * math.pi / 2
	if f < HOLD then
		return base
	end
	return base + math.pi / 2 * smooth((f - HOLD) / (1 - HOLD))
end

-- Kierunek, w którym patrzą drzwi chatki (jak LookVector CFrame.Angles(0, yaw, 0))
function Mountain.doorDirection(yaw: number): Vector3
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end

-- Czy chatka w chwili t patrzy drzwiami na punkt `at` (np. gracza zrywającego Ziele)
function Mountain.hutWatching(t: number, at: Vector3): boolean
	local lair = Config.JagaLair
	local offset = Vector3.new(at.X - lair.centerX, 0, at.Z - lair.hutZ)
	if offset.Magnitude < 0.01 then
		return true
	end
	return Mountain.doorDirection(Mountain.hutYaw(t)):Dot(offset.Unit) >= lair.watchCone
end

-- Ile sekund Baba Jaga potrzebuje, żeby wylecieć (chatka patrzy = od razu)
function Mountain.jagaWakeDelay(t: number, at: Vector3): (number, boolean)
	local watched = Mountain.hutWatching(t, at)
	local jaga = Config.Jaga
	return if watched then jaga.wakeDelayWatched else jaga.wakeDelay, watched
end

-- ===== Kotły Sabatu =====

-- Stałe miejsca kotłów (x, z): z dala od ścieżki środkiem góry, żeby ścieżka była bezpieczna
Mountain.CAULDRONS = {
	{ x = -30, z = 3186 },
	{ x = 26, z = 3198 },
	{ x = -16, z = 3222 },
	{ x = 38, z = 3236 },
	{ x = -38, z = 3252 },
	{ x = 18, z = 3266 },
	{ x = -24, z = 3286 },
}

-- Czy punkt jest w trujących oparach któregoś kotła
function Mountain.inFumes(at: Vector3): boolean
	local radius = Config.Cauldrons.fumeRadius
	for _, spot in Mountain.CAULDRONS do
		local dx, dz = at.X - spot.x, at.Z - spot.z
		if dx * dx + dz * dz <= radius * radius then
			return true
		end
	end
	return false
end

-- Mnożnik spalania oleju w danym miejscu (opary = szybciej)
function Mountain.oilFactor(at: Vector3): number
	return if Mountain.inFumes(at) then Config.Cauldrons.fumeDrain else 1
end

-- ===== Kruki =====

-- Czy kruki polują w tej strefie (id strefy z Config.Zones)
function Mountain.ravenZone(zoneId: string?): boolean
	return zoneId ~= nil and Config.Ravens.zones[zoneId] == true
end

return Mountain
