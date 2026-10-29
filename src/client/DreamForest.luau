--!strict
-- Las ze snu do cutscenki na start: budowany tylko u tego gracza, daleko od mapy (nie widać chatki).
-- Kręta ścieżka z kamieni, brzozy, świerki z klocków, okrągłe drzewa liściaste, krzaki, paprocie, kamienie,
-- powalony pień, kępki świecących grzybków i świetliki. Na końcu ścieżki polana na mityczny grzyb.
-- Drzewa stoją co najmniej 9 studów od środka ścieżki i poza polaną, więc Leszy w biegu w nic nie wchodzi.

local Workspace = game:GetService("Workspace")

local DreamForest = {}

DreamForest.ORIGIN = Vector3.new(-4200, 0, -4200)
DreamForest.GLADE_Z = 70
DreamForest.GLADE_R = 17

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function pathX(z: number): number
	return 3.5 * math.sin(z / 18)
end

-- Punkt na ścieżce (lokalne z, przesunięcie w bok) w świecie
function DreamForest.at(z: number, dx: number?): Vector3
	return DreamForest.ORIGIN + Vector3.new(pathX(z) + (dx or 0), 0, z)
end

local function part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local BIRCH = rgb(226, 222, 206)
local BIRCH_MARK = rgb(40, 38, 36)
local TRUNK = rgb(84, 60, 44)
local TRUNK_DARK = rgb(60, 44, 34)
local PINE = { rgb(40, 84, 56), rgb(34, 74, 52), rgb(48, 94, 60) }
local AUTUMN = { rgb(214, 120, 46), rgb(228, 168, 62), rgb(184, 76, 42), rgb(204, 146, 52) }
local LEAF = { rgb(58, 96, 52), rgb(72, 108, 56), rgb(48, 84, 50) }
local GROUND = rgb(46, 70, 42)
local PATH = rgb(196, 176, 132)
local ROCK = { rgb(118, 116, 110), rgb(98, 96, 92), rgb(134, 128, 120) }
local GLOW = { rgb(90, 220, 255), rgb(150, 120, 255), rgb(110, 255, 200) }

local function birch(parent: Instance, at: Vector3, rnd: Random)
	local h = rnd:NextNumber(13, 20)
	local w = rnd:NextNumber(1.1, 1.6)
	part(parent, Vector3.new(h, w, w), CFrame.new(at + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), BIRCH, nil, Enum.PartType.Cylinder)
	for i = 1, 4 do
		local y = rnd:NextNumber(1.5, h - 2)
		part(parent, Vector3.new(w * 0.6, 0.18, 0.08), CFrame.new(at + Vector3.new(0, y, 0)) * CFrame.Angles(0, rnd:NextNumber(0, math.pi * 2), 0) * CFrame.new(0, 0, -w / 2), BIRCH_MARK)
		local _ = i
	end
	for _ = 1, 3 do
		local r = rnd:NextNumber(5, 8)
		local color = AUTUMN[rnd:NextInteger(1, #AUTUMN)]
		part(parent, Vector3.new(r, r, r), CFrame.new(at + Vector3.new(rnd:NextNumber(-2, 2), h + rnd:NextNumber(-2, 1.5), rnd:NextNumber(-2, 2))), color, nil, Enum.PartType.Ball)
	end
end

-- Świerk z trzech coraz mniejszych, obróconych klocków (pasuje do voxelowych grzybów)
local function spruce(parent: Instance, at: Vector3, rnd: Random)
	local scale = rnd:NextNumber(0.9, 1.5)
	part(parent, Vector3.new(1.2, 4 * scale, 1.2), CFrame.new(at + Vector3.new(0, 2 * scale, 0)), TRUNK_DARK)
	local y = 3 * scale
	local size = 9 * scale
	local color = PINE[rnd:NextInteger(1, #PINE)]
	local spin = rnd:NextNumber(0, math.pi / 2)
	for i = 1, 4 do
		local layer = size * (1 - (i - 1) * 0.22)
		local height = 3.2 * scale
		part(parent, Vector3.new(layer, height, layer), CFrame.new(at + Vector3.new(0, y + height / 2, 0)) * CFrame.Angles(0, spin + i * 0.4, 0), color)
		y += height * 0.78
	end
	part(parent, Vector3.new(1.2 * scale, 2.2 * scale, 1.2 * scale), CFrame.new(at + Vector3.new(0, y + 1, 0)), color)
end

local function leafy(parent: Instance, at: Vector3, rnd: Random)
	local h = rnd:NextNumber(8, 12)
	part(parent, Vector3.new(h, 1.8, 1.8), CFrame.new(at + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), TRUNK, nil, Enum.PartType.Cylinder)
	for _ = 1, 4 do
		local r = rnd:NextNumber(6, 10)
		part(parent, Vector3.new(r, r * 0.85, r), CFrame.new(at + Vector3.new(rnd:NextNumber(-3, 3), h + rnd:NextNumber(-1, 3), rnd:NextNumber(-3, 3))), LEAF[rnd:NextInteger(1, #LEAF)], nil, Enum.PartType.Ball)
	end
end

local function bush(parent: Instance, at: Vector3, rnd: Random)
	for _ = 1, 3 do
		local r = rnd:NextNumber(2.2, 3.8)
		part(parent, Vector3.new(r, r * 0.8, r), CFrame.new(at + Vector3.new(rnd:NextNumber(-1.2, 1.2), r * 0.3, rnd:NextNumber(-1.2, 1.2))), LEAF[rnd:NextInteger(1, #LEAF)], nil, Enum.PartType.Ball)
	end
end

local function fern(parent: Instance, at: Vector3, rnd: Random)
	for i = 1, 5 do
		local angle = i * 1.25 + rnd:NextNumber(-0.2, 0.2)
		part(parent, Vector3.new(0.3, 0.12, 2.2), CFrame.new(at + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, angle, 0) * CFrame.Angles(math.rad(35), 0, 0) * CFrame.new(0, 0, -1), LEAF[rnd:NextInteger(1, #LEAF)])
	end
end

local function rock(parent: Instance, at: Vector3, rnd: Random)
	local s = rnd:NextNumber(1.2, 3)
	part(parent, Vector3.new(s * 1.3, s * 0.8, s), CFrame.new(at + Vector3.new(0, s * 0.3, 0)) * CFrame.Angles(rnd:NextNumber(-0.3, 0.3), rnd:NextNumber(0, 3), rnd:NextNumber(-0.3, 0.3)), ROCK[rnd:NextInteger(1, #ROCK)], Enum.Material.Slate)
end

-- Kępka małych świecących grzybków (z jednym światłem na kępkę)
local function glowShrooms(parent: Instance, at: Vector3, rnd: Random, withLight: boolean)
	local color = GLOW[rnd:NextInteger(1, #GLOW)]
	for _ = 1, rnd:NextInteger(3, 5) do
		local p = at + Vector3.new(rnd:NextNumber(-1.2, 1.2), 0, rnd:NextNumber(-1.2, 1.2))
		local h = rnd:NextNumber(0.4, 0.9)
		part(parent, Vector3.new(0.2, h, 0.2), CFrame.new(p + Vector3.new(0, h / 2, 0)), rgb(230, 226, 210))
		local capW = rnd:NextNumber(0.5, 0.9)
		part(parent, Vector3.new(capW, capW * 0.4, capW), CFrame.new(p + Vector3.new(0, h + capW * 0.15, 0)), color, Enum.Material.Neon)
	end
	if withLight then
		local holder = part(parent, Vector3.new(0.2, 0.2, 0.2), CFrame.new(at + Vector3.new(0, 1, 0)), color)
		holder.Transparency = 1
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 10
		light.Brightness = 1.2
		light.Parent = holder
	end
end

local function clearOf(local3: Vector3): boolean
	local z = local3.Z
	local dx = math.abs(local3.X - pathX(z))
	if z > -40 and z < 120 and dx < 9 then
		return false
	end
	local glade = Vector3.new(0, 0, DreamForest.GLADE_Z)
	if (Vector3.new(local3.X, 0, z) - glade).Magnitude < DreamForest.GLADE_R then
		return false
	end
	return true
end

function DreamForest.build(): Model
	local model = Instance.new("Model")
	model.Name = "DreamForest"
	local o = DreamForest.ORIGIN
	local rnd = Random.new(4242)

	-- Ziemia, ciemniejsze plamy i kamienna ścieżka
	part(model, Vector3.new(420, 2, 420), CFrame.new(o + Vector3.new(0, -1, 40)), GROUND, Enum.Material.Grass)
	for _ = 1, 40 do
		local p = Vector3.new(rnd:NextNumber(-120, 120), 0.02, rnd:NextNumber(-60, 160))
		part(model, Vector3.new(rnd:NextNumber(6, 16), 0.1, rnd:NextNumber(6, 16)), CFrame.new(o + p) * CFrame.Angles(0, rnd:NextNumber(0, 3), 0), rgb(38, 58, 36), Enum.Material.Grass)
	end
	local z = -40
	while z < 120 do
		local p = DreamForest.at(z, rnd:NextNumber(-0.6, 0.6)) + Vector3.new(0, 0.08, 0)
		local size = rnd:NextNumber(2.4, 3.4)
		part(model, Vector3.new(0.25, size, size * 0.8), CFrame.new(p) * CFrame.Angles(0, rnd:NextNumber(0, 3), math.rad(90)), PATH, Enum.Material.Sand, Enum.PartType.Cylinder)
		z += rnd:NextNumber(2.4, 3.2)
	end
	-- Polana: miękka trawa jaśniejsza od reszty, krąg kamieni
	part(model, Vector3.new(0.2, DreamForest.GLADE_R * 2, DreamForest.GLADE_R * 2), CFrame.new(o + Vector3.new(0, 0.04, DreamForest.GLADE_Z)) * CFrame.Angles(0, 0, math.rad(90)), rgb(58, 86, 50), Enum.Material.Grass, Enum.PartType.Cylinder)
	for i = 1, 14 do
		local a = i / 14 * math.pi * 2
		rock(model, o + Vector3.new(math.cos(a) * (DreamForest.GLADE_R - 1), 0, DreamForest.GLADE_Z + math.sin(a) * (DreamForest.GLADE_R - 1)), rnd)
	end

	-- Drzewa: gęsto po bokach ścieżki, rzadziej dalej
	local placed = 0
	local tries = 0
	while placed < 170 and tries < 4000 do
		tries += 1
		local local3 = Vector3.new(rnd:NextNumber(-90, 90), 0, rnd:NextNumber(-50, 170))
		if clearOf(local3) then
			local near = math.abs(local3.X - pathX(local3.Z)) < 26
			if near or rnd:NextNumber() < 0.45 then
				local roll = rnd:NextNumber()
				local at = o + local3
				if roll < 0.38 then
					birch(model, at, rnd)
				elseif roll < 0.75 then
					spruce(model, at, rnd)
				else
					leafy(model, at, rnd)
				end
				placed += 1
			end
		end
	end
	-- Podszyt przy ścieżce
	for _ = 1, 140 do
		local local3 = Vector3.new(rnd:NextNumber(-40, 40), 0, rnd:NextNumber(-40, 130))
		local dx = math.abs(local3.X - pathX(local3.Z))
		if dx > 3.5 then
			local roll = rnd:NextNumber()
			if roll < 0.35 and dx > 6 then
				bush(model, o + local3, rnd)
			elseif roll < 0.75 then
				fern(model, o + local3, rnd)
			else
				rock(model, o + local3, rnd)
			end
		end
	end
	-- Powalony pień przy ścieżce
	part(model, Vector3.new(12, 2.2, 2.2), CFrame.new(DreamForest.at(44, 7) + Vector3.new(0, 1.1, 0)) * CFrame.Angles(0, math.rad(70), 0), TRUNK, Enum.Material.Wood, Enum.PartType.Cylinder)
	-- Świecące grzybki (kilka ze światłem)
	for i = 1, 16 do
		local zz = rnd:NextNumber(-10, 110)
		local side = if rnd:NextNumber() < 0.5 then -1 else 1
		local p = DreamForest.at(zz, side * rnd:NextNumber(4, 11))
		glowShrooms(model, p, rnd, i % 3 == 0)
	end

	-- Świetliki nad ścieżką i polaną
	for _, zz in { 10, 40, 70 } do
		local cloud = part(model, Vector3.new(40, 6, 40), CFrame.new(DreamForest.at(zz) + Vector3.new(0, 4, 0)), rgb(0, 0, 0))
		cloud.Transparency = 1
		local flies = Instance.new("ParticleEmitter")
		flies.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		flies.Rate = 7
		flies.Lifetime = NumberRange.new(4, 7)
		flies.Speed = NumberRange.new(0.2, 0.8)
		flies.SpreadAngle = Vector2.new(180, 180)
		flies.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, 0.22), NumberSequenceKeypoint.new(0.8, 0.22), NumberSequenceKeypoint.new(1, 0) })
		flies.LightEmission = 1
		flies.Color = ColorSequence.new(rgb(220, 255, 140))
		flies.Parent = cloud
	end

	model.Parent = Workspace
	return model
end

return DreamForest
