--!strict
-- Geometria ogródków graczy (czysta matematyka bez API Robloxa, testy w Lune).
-- Działki stoją sześciokątem wokół Placu Ogródków (Config.Garden.plaza), każda furtką do środka placu.
-- Układ działki jak w World/Garden: lokalne -Z to strona furtki, lokalne X to bok z furtką (width),
-- głębokość (depth) idzie od furtki do tylnego płotu. MapBuilder buduje z tego CFrame i rezerwacje.

local Config = require(script.Parent.Config)

local GardenLayout = {}

export type Plot = { x: number, z: number }
export type Rect = { x1: number, x2: number, z1: number, z2: number }

-- Placyk z przyciskami (Hub) stoi tyle studs za furtką (World/Garden: PLAZA_FROM_GATE)
GardenLayout.HUB_FROM_GATE = 7

-- Jednostkowy kierunek od środka działki do środka placu: tam patrzy furtka (lokalne -Z)
function GardenLayout.facing(plot: Plot): (number, number)
	local plaza = Config.Garden.plaza
	local dx, dz = plaza.x - plot.x, plaza.z - plot.z
	local length = math.sqrt(dx * dx + dz * dz)
	if length < 1e-6 then
		return 0, -1
	end
	return dx / length, dz / length
end

-- Punkt działki (lx w bok, lz w głąb; ujemne lz = w stronę furtki) we współrzędnych świata.
-- Tak samo jak CFrame.lookAt(środek, środek placu): prawa strona = (-fz, fx), lokalne +Z = -facing.
function GardenLayout.toWorld(plot: Plot, lx: number, lz: number): (number, number)
	local fx, fz = GardenLayout.facing(plot)
	return plot.x - lx * fz - lz * fx, plot.z + lx * fx - lz * fz
end

-- Punkt świata w układzie działki (odwrotność toWorld)
function GardenLayout.toLocal(plot: Plot, x: number, z: number): (number, number)
	local fx, fz = GardenLayout.facing(plot)
	local dx, dz = x - plot.x, z - plot.z
	return -dx * fz + dz * fx, -(dx * fx + dz * fz)
end

-- Narożniki prostokąta działki powiększonego o margin, z dodatkowym miejscem front przed furtką
function GardenLayout.corners(plot: Plot, margin: number, front: number?): { { x: number, z: number } }
	local halfW = Config.Garden.width / 2 + margin
	local back = Config.Garden.depth / 2 + margin
	local fore = -(Config.Garden.depth / 2 + margin + (front or 0))
	local points = {}
	for _, corner in { { -halfW, fore }, { halfW, fore }, { halfW, back }, { -halfW, back } } do
		local x, z = GardenLayout.toWorld(plot, corner[1], corner[2])
		table.insert(points, { x = x, z = z })
	end
	return points
end

-- Prostokąt osiowy obejmujący obróconą działkę (rezerwacja miejsca w MapBuilder)
function GardenLayout.bounds(plot: Plot, margin: number, front: number?): Rect
	local rect = { x1 = math.huge, x2 = -math.huge, z1 = math.huge, z2 = -math.huge }
	for _, p in GardenLayout.corners(plot, margin, front) do
		rect.x1 = math.min(rect.x1, p.x)
		rect.x2 = math.max(rect.x2, p.x)
		rect.z1 = math.min(rect.z1, p.z)
		rect.z2 = math.max(rect.z2, p.z)
	end
	return rect
end

-- Czy punkt (x, z) leży na działce powiększonej o margin (z miejscem front przed furtką)
function GardenLayout.contains(plot: Plot, x: number, z: number, margin: number, front: number?): boolean
	local lx, lz = GardenLayout.toLocal(plot, x, z)
	local halfW = Config.Garden.width / 2 + margin
	local back = Config.Garden.depth / 2 + margin
	local fore = -(Config.Garden.depth / 2 + margin + (front or 0))
	return math.abs(lx) <= halfW and lz >= fore and lz <= back
end

-- Środek furtki i placyku z przyciskami (Hub) we współrzędnych świata
function GardenLayout.gate(plot: Plot): (number, number)
	return GardenLayout.toWorld(plot, 0, -Config.Garden.depth / 2)
end

function GardenLayout.hub(plot: Plot): (number, number)
	return GardenLayout.toWorld(plot, 0, -Config.Garden.depth / 2 + GardenLayout.HUB_FROM_GATE)
end

-- Ścieżki na plac: łamana od brzegu bruku przez szczelinę między działkami do punktu entrance.to.
-- outer = jak daleko od środka placu ścieżka idzie prosto szczeliną (za narożnikami działek).
function GardenLayout.entrancePath(entrance: { angle: number, to: { x: number, z: number } }): { { x: number, z: number } }
	local plaza = Config.Garden.plaza
	local angle = math.rad(entrance.angle)
	local dx, dz = math.cos(angle), math.sin(angle)
	local outer = plaza.radius + Config.Garden.depth / 2 - 6
	return {
		{ x = plaza.x + dx * (plaza.paving - 2), z = plaza.z + dz * (plaza.paving - 2) },
		{ x = plaza.x + dx * outer, z = plaza.z + dz * outer },
		{ x = entrance.to.x, z = entrance.to.z },
	}
end

-- Najkrótsza odległość punktu od odcinka a–b (testy ścieżek i rezerwacje)
function GardenLayout.segmentDistance(px: number, pz: number, ax: number, az: number, bx: number, bz: number): number
	local abx, abz = bx - ax, bz - az
	local lengthSq = abx * abx + abz * abz
	local t = if lengthSq > 0 then math.clamp(((px - ax) * abx + (pz - az) * abz) / lengthSq, 0, 1) else 0
	local cx, cz = ax + abx * t - px, az + abz * t - pz
	return math.sqrt(cx * cx + cz * cz)
end

return GardenLayout
