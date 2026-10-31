--!strict
-- Ogródek do scenki kradzieży (samouczek). Budowany tylko u tego gracza, daleko od mapy, tak jak las
-- ze snu w intro: każde ujęcie jest zaplanowane, nic nie wchodzi w kadr i nic nie zależy od tego,
-- który ogródek ma gracz, jak jest obrócony ani co w nim rośnie.
-- Układ (lokalnie, w studach, y = 0 to ziemia): ogródek 22 x 22 wokół (0, 0), furtka pośrodku boku
-- z = -11, trzy grządki na z = 4 (środkowa czeka na nagrodę), skrzynia na monety przy furtce,
-- dwie latarnie, za ogródkiem ściana chatki z ciepłymi oknami, za płotem po stronie x < 0 duży krzak
-- (kryjówka złodzieja), dookoła las, świetliki i księżyc. Patrząc od furtki w głąb (+Z), strona x < 0
-- jest po prawej stronie ekranu.

local Workspace = game:GetService("Workspace")

local DreamForest = require(script.Parent.DreamForest)

local TheftStage = {}

TheftStage.ORIGIN = Vector3.new(3600, 0, -3600)
TheftStage.HALF = 11 -- połowa boku ogródka
TheftStage.GATE_HALF = 2.6 -- połowa szerokości furtki
TheftStage.BED_Z = 4 -- środek grządek
TheftStage.SOIL_Y = 0.62 -- wierzch ziemi na grządce
TheftStage.BUSH = Vector3.new(-16.5, 0, -4.5) -- krzak-kryjówka (lokalnie)

-- Punkt sceny: x w poprzek, z w głąb ogródka, y nad ziemią
function TheftStage.at(x: number, z: number, y: number?): Vector3
	return TheftStage.ORIGIN + Vector3.new(x, y or 0, z)
end

local at = TheftStage.at
local kit = DreamForest.kit
local part = kit.part

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local GROUND = rgb(44, 68, 42)
local GROUND_DARK = rgb(38, 58, 36)
local GRASS = rgb(76, 110, 56)
local GRAVEL = rgb(186, 168, 128)
local POST = rgb(104, 72, 48)
local RAIL = rgb(146, 102, 64)
local BED_WOOD = rgb(132, 92, 58)
local SOIL = rgb(80, 56, 38)
local SOIL_DARK = rgb(64, 44, 30)
local LOG = rgb(124, 86, 56)
local LOG_DARK = rgb(100, 70, 46)
local WINDOW = rgb(255, 190, 104)
local ROOF = rgb(84, 52, 44)
local STEM = rgb(236, 226, 204)
local FLOWERS = { rgb(236, 96, 96), rgb(250, 210, 90), rgb(180, 130, 240), rgb(255, 160, 200), rgb(250, 250, 240) }

-- Płot między dwoma punktami (lokalnie): słupki co ~2,8 studa i dwie żerdzie
local function fence(m: Model, from: Vector3, to: Vector3)
	local d = to - from
	local length = d.Magnitude
	local n = math.max(1, math.round(length / 2.8))
	for i = 0, n do
		local p = from + d * (i / n)
		part(m, Vector3.new(0.42, 3.2, 0.42), CFrame.new(at(p.X, p.Z, 1.6)), POST)
		part(m, Vector3.new(0.52, 0.16, 0.52), CFrame.new(at(p.X, p.Z, 3.27)), RAIL)
	end
	local mid = (from + to) / 2
	for _, y in { 1.15, 2.45 } do
		local c = at(mid.X, mid.Z, y)
		part(m, Vector3.new(0.22, 0.32, length), CFrame.lookAt(c, c + d.Unit), RAIL)
	end
end

local function bed(m: Model, x: number, z: number)
	local w, d, h = 4.4, 3.4, 0.75
	part(m, Vector3.new(w - 0.5, 0.56, d - 0.5), CFrame.new(at(x, z, TheftStage.SOIL_Y - 0.28)), SOIL, Enum.Material.Ground)
	for _, dz in { -0.7, 0, 0.7 } do
		part(m, Vector3.new(w - 0.9, 0.05, 0.22), CFrame.new(at(x, z + dz, TheftStage.SOIL_Y + 0.02)), SOIL_DARK, Enum.Material.Ground)
	end
	for _, side in { -1, 1 } do
		part(m, Vector3.new(w, h, 0.35), CFrame.new(at(x, z + side * (d / 2 - 0.175), h / 2)), BED_WOOD)
		part(m, Vector3.new(0.35, h, d - 0.7), CFrame.new(at(x + side * (w / 2 - 0.175), z, h / 2)), BED_WOOD)
	end
end

-- Mały grzybek z klocków (ozdoba bocznych grządek)
local function smallShroom(m: Model, x: number, z: number, cap: Color3, s: number)
	local base = at(x, z, TheftStage.SOIL_Y)
	part(m, Vector3.new(0.3, 0.7, 0.3) * s, CFrame.new(base + Vector3.new(0, 0.35 * s, 0)), STEM)
	part(m, Vector3.new(1.0, 0.32, 1.0) * s, CFrame.new(base + Vector3.new(0, 0.82 * s, 0)), cap)
	part(m, Vector3.new(0.62, 0.22, 0.62) * s, CFrame.new(base + Vector3.new(0, 1.06 * s, 0)), cap:Lerp(Color3.new(1, 1, 1), 0.18))
end

local function sprout(m: Model, x: number, z: number)
	local base = at(x, z, TheftStage.SOIL_Y)
	part(m, Vector3.new(0.12, 0.5, 0.12), CFrame.new(base + Vector3.new(0, 0.25, 0)), rgb(90, 140, 60))
	for _, side in { -1, 1 } do
		part(m, Vector3.new(0.36, 0.06, 0.2), CFrame.new(base + Vector3.new(side * 0.16, 0.48, 0)) * CFrame.Angles(0, 0, side * 0.4), rgb(110, 170, 70))
	end
end

-- Latarnia na słupku z ramieniem (ramię w stronę +X)
local function lanternPost(m: Model, x: number, z: number, height: number, range: number, brightness: number)
	part(m, Vector3.new(0.4, height, 0.4), CFrame.new(at(x, z, height / 2)), POST)
	part(m, Vector3.new(1.3, 0.2, 0.2), CFrame.new(at(x + 0.55, z, height - 0.1)), POST)
	local glass = part(m, Vector3.new(0.7, 0.9, 0.7), CFrame.new(at(x + 1.05, z, height - 0.8)), rgb(255, 214, 140), Enum.Material.Neon)
	part(m, Vector3.new(0.86, 0.14, 0.86), CFrame.new(at(x + 1.05, z, height - 0.3)), rgb(40, 36, 34), Enum.Material.Metal)
	part(m, Vector3.new(0.86, 0.12, 0.86), CFrame.new(at(x + 1.05, z, height - 1.3)), rgb(40, 36, 34), Enum.Material.Metal)
	local light = Instance.new("PointLight")
	light.Color = rgb(255, 196, 120)
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = glass
end

local function chest(m: Model, x: number, z: number, yaw: number)
	local c = CFrame.new(at(x, z)) * CFrame.Angles(0, math.rad(yaw), 0)
	part(m, Vector3.new(2.2, 1.2, 1.4), c * CFrame.new(0, 0.6, 0), rgb(120, 78, 44))
	part(m, Vector3.new(2.3, 0.45, 1.5), c * CFrame.new(0, 1.42, 0), rgb(146, 96, 54))
	for _, dx in { -0.75, 0.75 } do
		part(m, Vector3.new(0.18, 1.68, 1.54), c * CFrame.new(dx, 0.84, 0), rgb(214, 170, 60), Enum.Material.Metal)
	end
	part(m, Vector3.new(0.34, 0.4, 0.1), c * CFrame.new(0, 1.12, -0.76), rgb(240, 200, 80), Enum.Material.Metal)
	for i = 1, 5 do
		part(m, Vector3.new(0.12, 0.46, 0.46), c * CFrame.new(-0.62 + i * 0.21, 1.71 + (i % 2) * 0.05, 0.1) * CFrame.Angles(0, 0, math.rad(90)), rgb(255, 205, 60), Enum.Material.Metal, Enum.PartType.Cylinder)
	end
end

local function flower(m: Model, x: number, z: number, color: Color3)
	local base = at(x, z)
	part(m, Vector3.new(0.1, 0.9, 0.1), CFrame.new(base + Vector3.new(0, 0.45, 0)), rgb(70, 120, 56))
	part(m, Vector3.new(0.48, 0.48, 0.48), CFrame.new(base + Vector3.new(0, 0.98, 0)), color, nil, Enum.PartType.Ball)
end

-- Ściana chatki za ogródkiem: bale, dwa ciepłe okna, okap dachu
local function cabinWall(m: Model)
	local z = 18
	for i = 0, 6 do
		local y = 0.72 + i * 1.36
		part(m, Vector3.new(34, 1.46, 1.46), CFrame.new(at(0, z, y)), if i % 2 == 0 then LOG else LOG_DARK, nil, Enum.PartType.Cylinder)
	end
	for _, x in { -6.5, 6.5 } do
		part(m, Vector3.new(3.6, 2.8, 0.3), CFrame.new(at(x, z - 0.7, 4.4)), WINDOW, Enum.Material.Neon)
		part(m, Vector3.new(4.2, 0.35, 0.5), CFrame.new(at(x, z - 0.85, 5.95)), POST)
		part(m, Vector3.new(4.2, 0.35, 0.5), CFrame.new(at(x, z - 0.85, 2.85)), POST)
		part(m, Vector3.new(0.25, 2.8, 0.3), CFrame.new(at(x, z - 0.9, 4.4)), POST)
		part(m, Vector3.new(3.6, 0.25, 0.3), CFrame.new(at(x, z - 0.9, 4.4)), POST)
		local glow = part(m, Vector3.new(0.2, 0.2, 0.2), CFrame.new(at(x, z - 2.2, 4.4)), WINDOW)
		glow.Transparency = 1
		local light = Instance.new("PointLight")
		light.Color = WINDOW
		light.Range = 13
		light.Brightness = 0.9
		light.Shadows = false
		light.Parent = glow
	end
	part(m, Vector3.new(38, 0.8, 8), CFrame.new(at(0, z - 0.6, 11)) * CFrame.Angles(math.rad(-28), 0, 0), ROOF)
	part(m, Vector3.new(38.4, 0.5, 0.6), CFrame.new(at(0, z - 4.1, 9.2)), rgb(64, 40, 34))
end

-- Las dookoła: tylko poza ogródkiem, chatką, drogą od furtki i drogą ucieczki złodzieja
local function free(x: number, z: number): boolean
	if math.abs(x) < 15 and z > -15 and z < 15 then
		return false -- ogródek
	end
	if math.abs(x) < 22 and z > 12 and z < 27 then
		return false -- chatka
	end
	if math.abs(x) < 9 and z < -10 and z > -70 then
		return false -- droga od furtki
	end
	if x < -10 and x > -50 and z > -16 and z < 22 then
		return false -- krzak i ucieczka złodzieja
	end
	return true
end

function TheftStage.build(): Model
	local m = Instance.new("Model")
	m.Name = "TheftStage"
	local rnd = Random.new(2611)
	local half = TheftStage.HALF
	local gate = TheftStage.GATE_HALF

	-- Ziemia, ciemniejsze plamy, trawa ogródka i żwirowe dróżki
	part(m, Vector3.new(360, 2, 360), CFrame.new(at(0, 30, -1)), GROUND, Enum.Material.Grass)
	for _ = 1, 30 do
		local x, z = rnd:NextNumber(-110, 110), rnd:NextNumber(-90, 130)
		if free(x, z) then
			part(m, Vector3.new(rnd:NextNumber(6, 16), 0.1, rnd:NextNumber(6, 16)), CFrame.new(at(x, z, 0.02)) * CFrame.Angles(0, rnd:NextNumber(0, 3), 0), GROUND_DARK, Enum.Material.Grass)
		end
	end
	part(m, Vector3.new(half * 2, 0.12, half * 2), CFrame.new(at(0, 0, 0.06)), GRASS, Enum.Material.Grass)
	part(m, Vector3.new(gate * 2 - 0.6, 0.14, 8.6), CFrame.new(at(0, -half + 4.3, 0.08)), GRAVEL, Enum.Material.Sand)
	local z = -half - 1.6
	while z > -60 do
		local p = at(rnd:NextNumber(-0.5, 0.5), z, 0.08)
		local size = rnd:NextNumber(2.2, 3.0)
		part(m, Vector3.new(0.22, size, size * 0.8), CFrame.new(p) * CFrame.Angles(0, rnd:NextNumber(0, 3), math.rad(90)), GRAVEL, Enum.Material.Sand, Enum.PartType.Cylinder)
		z -= rnd:NextNumber(2.4, 3.1)
	end

	-- Płot z furtką i furtka: wyższe słupki, belka, deska
	fence(m, Vector3.new(-half, 0, -half), Vector3.new(-gate, 0, -half))
	fence(m, Vector3.new(gate, 0, -half), Vector3.new(half, 0, -half))
	fence(m, Vector3.new(-half, 0, half), Vector3.new(half, 0, half))
	fence(m, Vector3.new(-half, 0, -half), Vector3.new(-half, 0, half))
	fence(m, Vector3.new(half, 0, -half), Vector3.new(half, 0, half))
	for _, side in { -1, 1 } do
		part(m, Vector3.new(0.72, 5.4, 0.72), CFrame.new(at(side * gate, -half, 2.7)), POST)
	end
	part(m, Vector3.new(gate * 2 + 1.2, 0.5, 0.5), CFrame.new(at(0, -half, 5.15)), RAIL)
	part(m, Vector3.new(gate * 2 - 0.5, 0.9, 0.18), CFrame.new(at(0, -half - 0.05, 4.25)), rgb(170, 122, 76))
	-- Na desce furtki mały czerwony grzybek
	part(m, Vector3.new(0.24, 0.42, 0.08), CFrame.new(at(0, -half - 0.16, 4.02)), STEM)
	part(m, Vector3.new(0.72, 0.3, 0.08), CFrame.new(at(0, -half - 0.16, 4.34)), rgb(214, 60, 48))

	-- Grządki: środkowa pusta (tu rośnie nagroda), boczne z małymi grzybkami i kiełkami
	for _, x in { -6.2, 0, 6.2 } do
		bed(m, x, TheftStage.BED_Z)
	end
	smallShroom(m, -7.1, TheftStage.BED_Z - 0.6, rgb(214, 60, 48), 0.9)
	smallShroom(m, -5.3, TheftStage.BED_Z + 0.7, rgb(150, 96, 56), 0.75)
	sprout(m, -6.4, TheftStage.BED_Z + 0.9)
	smallShroom(m, 5.4, TheftStage.BED_Z + 0.5, rgb(170, 110, 220), 0.8)
	smallShroom(m, 7.0, TheftStage.BED_Z - 0.4, rgb(240, 170, 50), 0.85)
	sprout(m, 6.0, TheftStage.BED_Z - 0.9)

	-- Skrzynia na monety przy furtce, latarnie przy furtce i przy grządkach
	chest(m, 7.6, -7.4, -25)
	lanternPost(m, 3.5, -half - 1.3, 4.8, 20, 1.3)
	lanternPost(m, -3.6, TheftStage.BED_Z + 3.4, 4.6, 16, 1.4)

	-- Kwiaty wzdłuż płotu w środku
	for i = 0, 7 do
		local zz = -8 + i * 2.4
		flower(m, -half + 0.9, zz, FLOWERS[i % #FLOWERS + 1])
		flower(m, half - 0.9, zz + 1.1, FLOWERS[(i + 2) % #FLOWERS + 1])
	end
	for i = 0, 5 do
		flower(m, -8 + i * 3.2, half - 0.9, FLOWERS[(i + 4) % #FLOWERS + 1])
	end

	cabinWall(m)

	-- Krzak-kryjówka złodzieja za płotem i drzewo za nim
	local b = TheftStage.BUSH
	for _, piece in { { 0, 0, 3.7 }, { 1.4, 1.3, 3.1 }, { -1.1, 1.4, 2.9 }, { 0.5, -1.3, 2.8 }, { 2.1, -0.5, 2.5 } } do
		local r = piece[3]
		part(m, Vector3.new(r, r * 0.82, r), CFrame.new(at(b.X + piece[1], b.Z + piece[2], r * 0.34)), if r > 3.5 then rgb(56, 92, 50) else rgb(66, 104, 54), nil, Enum.PartType.Ball)
	end
	kit.leafy(m, at(b.X - 4.5, b.Z - 5), rnd)
	kit.fern(m, at(b.X + 2.6, b.Z + 2.2), rnd)

	-- Las
	local placed, tries = 0, 0
	while placed < 120 and tries < 3000 do
		tries += 1
		local x, zz = rnd:NextNumber(-95, 95), rnd:NextNumber(-95, 120)
		if free(x, zz) then
			local roll = rnd:NextNumber()
			local p = at(x, zz)
			if roll < 0.35 then
				kit.spruce(m, p, rnd)
			elseif roll < 0.7 then
				kit.leafy(m, p, rnd)
			else
				kit.birch(m, p, rnd)
			end
			placed += 1
		end
	end
	for _ = 1, 60 do
		local x, zz = rnd:NextNumber(-40, 40), rnd:NextNumber(-45, 40)
		if free(x, zz) then
			local roll = rnd:NextNumber()
			if roll < 0.4 then
				kit.bush(m, at(x, zz), rnd)
			elseif roll < 0.75 then
				kit.fern(m, at(x, zz), rnd)
			else
				kit.rock(m, at(x, zz), rnd)
			end
		end
	end
	for i, p in { { -20, 26 }, { 19, -18 }, { -24, -22 }, { 24, 8 }, { 12, 30 } } do
		kit.glowShrooms(m, at(p[1], p[2]), rnd, i % 2 == 1)
	end

	-- Świetliki nad ogródkiem i przy krzaku
	for _, spot in { { 0, 2, 22 }, { -16, -4, 14 } } do
		local cloud = part(m, Vector3.new(spot[3], 5, spot[3]), CFrame.new(at(spot[1], spot[2], 4)), Color3.new(0, 0, 0))
		cloud.Transparency = 1
		local flies = Instance.new("ParticleEmitter")
		flies.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		flies.Rate = 5
		flies.Lifetime = NumberRange.new(4, 7)
		flies.Speed = NumberRange.new(0.2, 0.7)
		flies.SpreadAngle = Vector2.new(180, 180)
		flies.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, 0.2), NumberSequenceKeypoint.new(0.8, 0.2), NumberSequenceKeypoint.new(1, 0) })
		flies.LightEmission = 1
		flies.Color = ColorSequence.new(rgb(220, 255, 140))
		flies.Parent = cloud
	end

	-- Księżyc z poświatą nad chatką
	part(m, Vector3.new(16, 16, 16), CFrame.new(at(-38, 150, 92)), rgb(255, 246, 210), Enum.Material.Neon, Enum.PartType.Ball)
	local halo = part(m, Vector3.new(30, 30, 30), CFrame.new(at(-38, 152, 92)), rgb(200, 210, 255), Enum.Material.Neon, Enum.PartType.Ball)
	halo.Transparency = 0.88

	m.Parent = Workspace
	return m
end

return TheftStage
