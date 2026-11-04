--!strict
-- Łysa Góra: kształt góry. Ziemia to siatka trójkątów (serwer składa je z klinów, World/Mountain),
-- a te same liczby mówią serwerowi i klientowi, na jakiej wysokości leży ziemia w punkcie (x, z):
-- grzyby, kotły, kruki, Baba Jaga w pościgu, mgła przy ziemi. Bez API Robloxa (testy w Lune).
--
-- Kształt: Polana Zielarki u stóp góry (płaska, y = 0). Kamienna ścieżka wije się serpentynami przez
-- Wiedźmi Las, prosto przez pole Kotłów Sabatu, potem stromo do kręgu kamieni i na płaski szczyt
-- z chatką Baby Jagi. Po lewej za ścianą skalny grzbiet, po prawej urwisko nad doliną, a za szczytem
-- góra opada w morze chmur. Szczyt jest najwyżej, ponad chmurami.
--
-- Siatka: kolumny XS i wiersze ZS (gęściej przy ścieżce, rzadziej za ścianami). Każda komórka to dwa
-- trójkąty, a przekątna zmienia kierunek jak pola szachownicy. groundY liczy wysokość dokładnie na
-- tych trójkątach, więc grzyb stoi na tej samej ziemi, którą widać.

local Config = require(script.Parent.Config)
local Mountain = require(script.Parent.Mountain)

local Terrain = {}

local HALF = Config.Mountain.halfWidth + 1 -- niewidzialne ściany po bokach (x = ±57)
local GLADE_END = 3040 -- do tego miejsca polana jest płaska
local END_Z = 3480 -- koniec świata (ściana za ogródkiem Baby Jagi)
local CORRIDOR = Config.Mountain.path + 1 -- pół szerokości płaskiego pasa ścieżki

Terrain.HALF = HALF
Terrain.END_Z = END_Z
Terrain.FLOOR = -46 -- dno doliny pod urwiskami
Terrain.CLOUDS = 30 -- morze chmur (krąg kamieni i szczyt są nad nim)
Terrain.TOP = 60 -- płaski szczyt z chatką i ogródkiem
Terrain.CIRCLE_Y = 50 -- wyrównany plac kręgu kamieni

-- Kolumny i wiersze siatki. Kolumny ±57 leżą dokładnie na ścianach: tam zaczyna się urwisko i grzbiet.
Terrain.XS = { -150, -110, -84, -68, -57, -49, -41, -33, -25, -17, -8, 0, 8, 17, 25, 33, 41, 49, 57, 66, 80, 100, 130 }
Terrain.ZS = (function(): { number }
	-- Przy polanie rzadziej (środek polany jest płaski), w pasie gry co 10, za szczytem coraz rzadziej
	local rows = { 2930, 2948, 2964, 2978, 2990, 3002, 3014, 3026 }
	for z = GLADE_END, END_Z, 10 do
		table.insert(rows, z)
	end
	for _, z in { 3490, 3504, 3522, 3546, 3576, 3620 } do
		table.insert(rows, z)
	end
	return rows
end)()

local XS, ZS = Terrain.XS, Terrain.ZS

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function smoothstep(a: number, b: number, x: number): number
	if x <= a then
		return 0
	elseif x >= b then
		return 1
	end
	local t = (x - a) / (b - a)
	return t * t * (3 - 2 * t)
end

-- ===== Ścieżka =====

-- Wysokość osi ścieżki (z, y). Między punktami gładko (smoothstep), więc przy każdym punkcie ścieżka
-- na chwilę się wypłaszcza: bramy stref, krąg kamieni i szczyt stoją na płaskim.
local PROFILE = {
	{ 2900, 0 },
	{ GLADE_END, 0 },
	{ 3105, 11 },
	{ 3170, 22 },
	{ 3236, 30 },
	{ 3300, 38 },
	{ 3338, Terrain.CIRCLE_Y },
	{ 3366, Terrain.CIRCLE_Y },
	{ 3400, Terrain.TOP },
	{ 3466, Terrain.TOP },
	{ END_Z, Terrain.TOP + 2 },
}

function Terrain.trailY(z: number): number
	if z <= PROFILE[1][1] then
		return PROFILE[1][2]
	end
	for i = 2, #PROFILE do
		local b = PROFILE[i]
		if z <= b[1] then
			local a = PROFILE[i - 1]
			return lerp(a[2], b[2], smoothstep(a[1], b[1], z))
		end
	end
	return PROFILE[#PROFILE][2]
end

-- Serpentyny: ścieżka skręca w lewo i w prawo, a przy bramach, w kręgu kamieni i na szczycie wraca
-- na x = 0. Kształt sin(2πt)·sin(πt): łagodnie wchodzi i wychodzi z zakrętu (bez załamań).
local BENDS = {
	{ z1 = GLADE_END, z2 = 3170, amp = 15 },
	{ z1 = 3300, z2 = 3338, amp = 9 },
	{ z1 = 3366, z2 = 3400, amp = -8 },
}
local S_PEAK = 4 / (3 * math.sqrt(3)) -- największa wartość sin(2πt)·sin(πt)

function Terrain.pathX(z: number): number
	for _, bend in BENDS do
		if z > bend.z1 and z < bend.z2 then
			local t = (z - bend.z1) / (bend.z2 - bend.z1)
			return bend.amp / S_PEAK * math.sin(2 * math.pi * t) * math.sin(math.pi * t)
		end
	end
	return 0
end

-- ===== Kształt (przed podziałem na trójkąty) =====

-- Pas gry (|x| ≤ HALF): oś ścieżki i zbocze w poprzek. Po lewej ziemia się wznosi, po prawej opada,
-- a pod szczytem opada w obie strony (szczyt to wierzchołek góry).
local function strip(x: number, z: number): number
	local y = Terrain.trailY(z)
	local d = x - Terrain.pathX(z)
	local ramp = smoothstep(GLADE_END, GLADE_END + 50, z) -- za polaną zbocze dopiero się zaczyna
	local leftSlope = lerp(0.09 + 0.03 * math.sin(z / 37), -0.11, smoothstep(3370, 3425, z))
	local rightSlope = 0.08 + 0.04 * math.sin(z / 23 + 1.3)
	if d < -CORRIDOR then
		y += (-d - CORRIDOR) * leftSlope * ramp
	elseif d > CORRIDOR then
		y -= (d - CORRIDOR) * rightSlope * ramp
	end
	return y
end

-- Grzbiet po lewej: ile wznosi się ponad krawędź pasa (przy polanie niżej), ale nigdy wyżej niż
-- RIDGE_CAP pod szczytem, żeby szczyt z chatką był najwyżej
local RIDGE_CAP = Terrain.TOP - 10
local function ridgeCrest(z: number, edge: number): number
	local rise = lerp(10, 15 + 4 * math.sin(z / 53), smoothstep(2990, 3080, z))
	return math.min(math.max(edge + 4, math.min(edge + rise, RIDGE_CAP)), Terrain.TOP - 6)
end

local function shape(x: number, z: number): number
	local zc = math.min(z, END_Z)
	local y: number
	if x < -HALF then
		-- Lewo: stromy brzeg od ściany do grzbietu (x ≈ -103), za grzbietem zbocze w dół do doliny.
		-- Pod szczytem grzbietu nie ma: zbocze opada w dolinę jak po prawej.
		local edge = strip(-HALF, zc)
		local fall = smoothstep(3345, 3435, zc)
		local crest = lerp(ridgeCrest(zc, edge), Terrain.FLOOR, fall)
		local t = (-HALF - x) / 46
		if t <= 1 then
			y = lerp(edge, crest, 1 - (1 - t) ^ 2)
		else
			y = lerp(crest, Terrain.FLOOR, smoothstep(1, 2.05, t))
		end
	elseif x > HALF then
		-- Prawo: urwisko od samej ściany, niżej łagodnieje i przechodzi w dno doliny
		local edge = strip(HALF, zc)
		local span = lerp(70, 44, smoothstep(GLADE_END, 3400, zc))
		local t = math.min((x - HALF) / span, 1)
		y = lerp(edge, Terrain.FLOOR, 1 - (1 - t) ^ 3)
	else
		y = strip(x, zc)
	end
	if z > END_Z then
		-- Za szczytem góra urywa się w morze chmur
		local t = math.min((z - END_Z) / 56, 1)
		y = lerp(y, Terrain.FLOOR, 1 - (1 - t) ^ 2.4)
	end
	return y
end

-- ===== Wyrównane miejsca =====

type Pad = { x: number, z: number, r: number, rz: number?, blend: number, y: number }

local pads: { Pad }? = nil

local function getPads(): { Pad }
	if pads then
		return pads
	end
	local list: { Pad } = {}
	-- Bramy stref (słupy po obu stronach ścieżki)
	for index, zone in Config.Zones do
		local previous = Config.Zones[index - 1]
		if zone.world == "mountain" and previous and previous.world == "mountain" then
			table.insert(list, { x = 0, z = zone.startZ, r = 9, blend = 7, y = Terrain.trailY(zone.startZ) })
		end
	end
	-- Kotły i ogniska (wysokość taka, jaka byłaby tam bez wyrównania)
	for _, spot in Mountain.CAULDRONS do
		table.insert(list, { x = spot.x, z = spot.z, r = 7, blend = 7, y = shape(spot.x, spot.z) })
	end
	for _, fire in Mountain.FIRES do
		if not fire.big then
			table.insert(list, { x = fire.x, z = fire.z, r = 5, blend = 6, y = shape(fire.x, fire.z) })
		end
	end
	-- Krąg kamieni i płaski szczyt (elipsa: chatka, ogródek, posąg Jagi, tablica)
	local circle = Mountain.STONE_CIRCLE
	table.insert(list, { x = circle.x, z = circle.z, r = circle.radius + 8, blend = 8, y = Terrain.CIRCLE_Y })
	local lair = Config.JagaLair
	table.insert(list, { x = lair.centerX, z = 3436, r = 28, rz = 36, blend = 12, y = Terrain.TOP })
	pads = list
	return list
end

-- Waga wyrównania (0..1) i wysokość placu w punkcie
local function padAt(x: number, z: number, y: number): (number, number)
	local strongest = 0
	for _, pad in getPads() do
		local dx, dz = x - pad.x, z - pad.z
		local outside: number
		if pad.rz then
			local q = math.sqrt((dx / pad.r) ^ 2 + (dz / pad.rz) ^ 2)
			outside = (q - 1) * math.min(pad.r, pad.rz)
		else
			outside = math.sqrt(dx * dx + dz * dz) - pad.r
		end
		local w = 1 - smoothstep(0, pad.blend, outside)
		if w > 0 then
			y = lerp(y, pad.y, w)
			strongest = math.max(strongest, w)
		end
	end
	return y, strongest
end

-- Drobne nierówności w wierzchołkach siatki (stały „los” z numeru wierzchołka): grudy na zboczu,
-- skały za ścianami. Ścieżka, place, polana i dno doliny zostają gładkie.
local function hash(i: number, j: number): number
	local n = (i * 73856093 + j * 19349663 + 83492791) % 2147483647
	n = (n * 16807) % 2147483647
	n = (n * 16807) % 2147483647
	return n / 2147483647
end

local function bump(i: number, j: number, x: number, z: number, y: number, padWeight: number): number
	local amp: number
	if math.abs(x) <= HALF and z <= END_Z then
		if z <= GLADE_END then
			return 0
		end
		amp = 1.1 * smoothstep(CORRIDOR + 1, CORRIDOR + 9, math.abs(x - Terrain.pathX(z)))
		-- Przy samej ścianie bez grud: krawędź urwiska i brzeg grzbietu są wspólne z sąsiednimi trójkątami
		if math.abs(x) >= HALF then
			amp = 0
		end
	else
		amp = 3.2
	end
	amp *= (1 - padWeight) * smoothstep(Terrain.FLOOR + 2, Terrain.FLOOR + 12, y)
	return (hash(i, j) - 0.5) * 2 * amp
end

-- ===== Siatka =====

local heights: { { number } }? = nil

local function getHeights(): { { number } }
	if heights then
		return heights
	end
	local rows: { { number } } = {}
	for j, z in ZS do
		local row = {}
		for i, x in XS do
			local y: number
			if z <= GLADE_END and math.abs(x) <= HALF then
				y = 0
			else
				local w: number
				y, w = padAt(x, z, shape(x, z))
				y += bump(i, j, x, z, y, w)
			end
			row[i] = y
		end
		rows[j] = row
	end
	heights = rows
	return rows
end

-- Wysokość wierzchołka siatki (kolumna i, wiersz j)
function Terrain.vertex(i: number, j: number): number
	return getHeights()[j][i]
end

-- Przekątna komórki (i, j): true = od (x0, z0) do (x1, z1), false = od (x1, z0) do (x0, z1)
function Terrain.diagonalAD(i: number, j: number): boolean
	return (i + j) % 2 == 0
end

-- Indeks i taki, że list[i] <= v < list[i + 1] (przycięty do siatki)
local function find(list: { number }, v: number): number
	if v <= list[1] then
		return 1
	elseif v >= list[#list] then
		return #list - 1
	end
	local lo, hi = 1, #list - 1
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		if list[mid] <= v then
			lo = mid
		else
			hi = mid - 1
		end
	end
	return lo
end

-- Wysokość ziemi i nachylenie (dy/dx, dy/dz) w punkcie, na tych samych trójkątach, które buduje serwer
local function sample(x: number, z: number): (number, number, number)
	x = math.clamp(x, XS[1], XS[#XS])
	z = math.clamp(z, ZS[1], ZS[#ZS])
	local i, j = find(XS, x), find(ZS, z)
	local h = getHeights()
	local x0, x1, z0, z1 = XS[i], XS[i + 1], ZS[j], ZS[j + 1]
	local dx, dz = x1 - x0, z1 - z0
	local u, v = (x - x0) / dx, (z - z0) / dz
	local hA, hB, hC, hD = h[j][i], h[j][i + 1], h[j + 1][i], h[j + 1][i + 1]
	if Terrain.diagonalAD(i, j) then
		if u >= v then
			return hA + (hB - hA) * u + (hD - hB) * v, (hB - hA) / dx, (hD - hB) / dz
		end
		return hA + (hC - hA) * v + (hD - hC) * u, (hD - hC) / dx, (hC - hA) / dz
	end
	if u + v <= 1 then
		return hA + (hB - hA) * u + (hC - hA) * v, (hB - hA) / dx, (hC - hA) / dz
	end
	return hD + (hC - hD) * (1 - u) + (hB - hD) * (1 - v), (hD - hC) / dx, (hD - hB) / dz
end

-- Wysokość ziemi w punkcie (x, z)
function Terrain.groundY(x: number, z: number): number
	local y = sample(x, z)
	return y
end

-- Normalna ziemi (wektor do góry, długość 1) jako trzy liczby
function Terrain.normal(x: number, z: number): (number, number, number)
	local _, gx, gz = sample(x, z)
	local length = math.sqrt(gx * gx + 1 + gz * gz)
	return -gx / length, 1 / length, -gz / length
end

-- Nachylenie: tangens kąta (0 = płasko, 1 = 45°)
function Terrain.slope(x: number, z: number): number
	local _, gx, gz = sample(x, z)
	return math.sqrt(gx * gx + gz * gz)
end

-- Czy punkt leży na górze (siatka), a nie poza nią
function Terrain.covers(x: number, z: number): boolean
	return x >= XS[1] and x <= XS[#XS] and z >= ZS[1] and z <= ZS[#ZS]
end

return Terrain
