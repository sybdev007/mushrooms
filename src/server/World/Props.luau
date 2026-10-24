--!strict
-- Elementy świata składane z klocków Robloxa w stylu low-poly.
-- Każda funkcja dostaje rodzica, pozycję na ziemi (y = 0), skalę i generator losowy,
-- więc ten sam seed zawsze daje ten sam las.

local CollectionService = game:GetService("CollectionService")

local Palette = require(script.Parent.Palette)

local Props = {}

local TAU = math.pi * 2
local VERTICAL = CFrame.Angles(0, 0, math.rad(90)) -- oś walca (X) obrócona do pionu

local function make(className: string, props: { [string]: any }): BasePart
	local p = Instance.new(className) :: BasePart
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

local function model(name: string, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- Kawałek, który nie blokuje gracza ani nie rzuca cienia (liście, trawa, ozdoby)
local function decor(p: BasePart): BasePart
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	return p
end

-- Ostrosłup z czterech CornerWedge: wierzchołek nad `center`, podstawa w `center`.
-- Przesunięcie (-w/4, 0, +w/4) sprawdzone w Studio: przy innych znakach wychodzi korona z kolców.
local function pyramid(parent: Instance, center: Vector3, width: number, height: number, yaw: number, color: Color3)
	for i = 0, 3 do
		decor(make("CornerWedgePart", {
			Size = Vector3.new(width / 2, height, width / 2),
			CFrame = CFrame.new(center + Vector3.new(0, height / 2, 0))
				* CFrame.Angles(0, yaw + math.rad(90 * i), 0)
				* CFrame.new(-width / 4, 0, width / 4),
			Color = color,
			Parent = parent,
		})).CastShadow = true
	end
end

local function trunk(parent: Instance, base: Vector3, height: number, diameter: number, color: Color3): BasePart
	return make("Part", {
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = CFrame.new(base + Vector3.new(0, height / 2, 0)) * VERTICAL,
		Color = color,
		Parent = parent,
	})
end

local function ball(parent: Instance, center: Vector3, size: number, color: Color3): BasePart
	return decor(make("Part", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(size, size, size),
		Position = center,
		Color = color,
		Parent = parent,
	}))
end

function Props.pine(parent: Instance, base: Vector3, s: number, rng: Random, dark: number)
	local m = model("Pine", parent)
	trunk(m, base, 6 * s, 1.5 * s, Palette.shade(Palette.trunk, dark))
	local yaw = rng:NextNumber(0, TAU)
	local layers = {
		{ w = 10, h = 7, y = 2.5 },
		{ w = 7.8, h = 6, y = 6 },
		{ w = 5.4, h = 5.2, y = 9.4 },
	}
	for i, layer in layers do
		local color = Palette.shade(Palette.pick(Palette.pine, rng), dark)
		pyramid(m, base + Vector3.new(0, layer.y * s, 0), layer.w * s, layer.h * s, yaw + i * 0.4, color)
	end
end

function Props.birch(parent: Instance, base: Vector3, s: number, rng: Random, dark: number)
	local m = model("Birch", parent)
	local height = rng:NextNumber(14, 18) * s
	local diameter = 1.1 * s
	trunk(m, base, height, diameter, Palette.shade(Palette.birchBark, dark * 0.6))
	-- Czarne paski na korze brzozy
	for _ = 1, rng:NextInteger(3, 5) do
		local y = rng:NextNumber(1.5, height * 0.75)
		decor(make("Part", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(rng:NextNumber(0.2, 0.45) * s, diameter * 1.06, diameter * 1.06),
			CFrame = CFrame.new(base + Vector3.new(0, y, 0)) * VERTICAL,
			Color = Palette.birchMark,
			Parent = m,
		}))
	end
	for _ = 1, 3 do
		local offset = Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(-1.5, 1.5), rng:NextNumber(-2, 2)) * s
		local size = rng:NextNumber(5.5, 7.5) * s
		ball(m, base + Vector3.new(0, height - 1 * s, 0) + offset, size, Palette.shade(Palette.pick(Palette.birchLeaves, rng), dark)).CastShadow =
			true
	end
end

function Props.oak(parent: Instance, base: Vector3, s: number, rng: Random, dark: number)
	local m = model("Oak", parent)
	local height = 7 * s
	trunk(m, base, height + 2 * s, 2.2 * s, Palette.shade(Palette.trunkDark, dark))
	for _ = 1, 7 do
		local offset = Vector3.new(rng:NextNumber(-3.6, 3.6), rng:NextNumber(-1.5, 3), rng:NextNumber(-3.6, 3.6)) * s
		local size = rng:NextNumber(4.2, 6.4) * s
		ball(m, base + Vector3.new(0, height + 3 * s, 0) + offset, size, Palette.shade(Palette.pick(Palette.autumn, rng), dark)).CastShadow =
			true
	end
end

function Props.deadTree(parent: Instance, base: Vector3, s: number, rng: Random, _dark: number)
	local m = model("DeadTree", parent)
	local height = rng:NextNumber(10, 15) * s
	trunk(m, base, height, 1.4 * s, Palette.deadWood)
	for _ = 1, rng:NextInteger(3, 5) do
		local length = rng:NextNumber(3.5, 6) * s
		local start = base + Vector3.new(0, rng:NextNumber(height * 0.45, height * 0.92), 0)
		make("Part", {
			Name = "Branch",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(length, 0.55 * s, 0.55 * s),
			CFrame = CFrame.new(start)
				* CFrame.Angles(0, rng:NextNumber(0, TAU), 0)
				* CFrame.Angles(0, 0, math.rad(rng:NextNumber(20, 50)))
				* CFrame.new(length / 2, 0, 0),
			Color = Palette.deadWood,
			CanCollide = false,
			Parent = m,
		})
	end
end

function Props.rock(parent: Instance, base: Vector3, s: number, rng: Random, dark: number)
	local m = model("Rock", parent)
	for i = 1, rng:NextInteger(1, 3) do
		local size = Vector3.new(rng:NextNumber(2, 4.5), rng:NextNumber(1.4, 3), rng:NextNumber(2, 4.5)) * s
		local offset = if i == 1 then Vector3.zero else Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2)) * s
		local cf = CFrame.new(base + offset + Vector3.new(0, size.Y * 0.3, 0))
			* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, TAU), rng:NextNumber(-0.3, 0.3))
		make("Part", {
			Size = size,
			CFrame = cf,
			Color = Palette.shade(Palette.pick(Palette.rock, rng), dark),
			Parent = m,
		})
		if rng:NextNumber() < 0.6 then
			decor(make("Part", {
				Size = Vector3.new(size.X * 0.75, 0.3, size.Z * 0.75),
				CFrame = cf * CFrame.new(0, size.Y / 2 + 0.05, 0),
				Color = Palette.shade(Palette.moss, dark),
				Parent = m,
			}))
		end
	end
end

function Props.bush(parent: Instance, base: Vector3, s: number, rng: Random, dark: number)
	local m = model("Bush", parent)
	for _ = 1, rng:NextInteger(2, 4) do
		local size = rng:NextNumber(2.6, 4.2) * s
		local offset = Vector3.new(rng:NextNumber(-1.6, 1.6), size * 0.3, rng:NextNumber(-1.6, 1.6)) * s
		ball(m, base + offset, size, Palette.shade(Palette.pick(Palette.bush, rng), dark))
	end
end

function Props.fern(parent: Instance, base: Vector3, s: number, rng: Random, dark: number)
	local m = model("Fern", parent)
	local color = Palette.shade(Palette.pick(Palette.fern, rng), dark)
	local count = rng:NextInteger(5, 7)
	local yaw0 = rng:NextNumber(0, TAU)
	for i = 1, count do
		local length = rng:NextNumber(2.4, 3.4) * s
		decor(make("Part", {
			Size = Vector3.new(0.8 * s, 0.1, length),
			CFrame = CFrame.new(base + Vector3.new(0, 0.25, 0))
				* CFrame.Angles(0, yaw0 + TAU * i / count, 0)
				* CFrame.Angles(math.rad(-rng:NextNumber(25, 45)), 0, 0)
				* CFrame.new(0, 0, length / 2),
			Color = color,
			Parent = m,
		}))
	end
end

function Props.grass(parent: Instance, base: Vector3, s: number, rng: Random, dark: number)
	local m = model("Grass", parent)
	local color = Palette.shade(Palette.pick(Palette.grass, rng), dark)
	for _ = 1, 4 do
		local height = rng:NextNumber(1, 1.8) * s
		decor(make("Part", {
			Size = Vector3.new(0.22 * s, height, 0.12),
			CFrame = CFrame.new(base + Vector3.new(rng:NextNumber(-0.5, 0.5), 0, rng:NextNumber(-0.5, 0.5)))
				* CFrame.Angles(0, rng:NextNumber(0, TAU), 0)
				* CFrame.Angles(math.rad(rng:NextNumber(-22, 22)), 0, math.rad(rng:NextNumber(-22, 22)))
				* CFrame.new(0, height / 2, 0),
			Color = color,
			Parent = m,
		}))
	end
end

function Props.log(parent: Instance, base: Vector3, s: number, rng: Random, dark: number)
	local m = model("FallenLog", parent)
	local length = rng:NextNumber(8, 12) * s
	local diameter = rng:NextNumber(1.6, 2.2) * s
	local cf = CFrame.new(base + Vector3.new(0, diameter * 0.4, 0)) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0)
	make("Part", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(length, diameter, diameter),
		CFrame = cf,
		Color = Palette.shade(Palette.trunk, dark),
		Parent = m,
	})
	for _, side in { -1, 1 } do
		decor(make("Part", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.12, diameter * 0.82, diameter * 0.82),
			CFrame = cf * CFrame.new(side * (length / 2 + 0.03), 0, 0),
			Color = Palette.shade(Palette.logEnd, dark),
			Parent = m,
		}))
	end
	decor(make("Part", {
		Size = Vector3.new(length * 0.6, 0.25, diameter * 0.6),
		CFrame = cf * CFrame.new(rng:NextNumber(-1, 1) * s, diameter / 2 - 0.05, 0),
		Color = Palette.shade(Palette.moss, dark),
		Parent = m,
	}))
end

function Props.stump(parent: Instance, base: Vector3, s: number, _rng: Random, dark: number)
	local m = model("Stump", parent)
	local height = 1.6 * s
	local diameter = 2.4 * s
	trunk(m, base, height, diameter, Palette.shade(Palette.trunk, dark))
	decor(make("Part", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, diameter * 0.85, diameter * 0.85),
		CFrame = CFrame.new(base + Vector3.new(0, height + 0.04, 0)) * VERTICAL,
		Color = Palette.shade(Palette.logEnd, dark),
		Parent = m,
	}))
end

-- Świecące grzybki do ozdoby (nie do zbierania). Jedno światło na kępę.
function Props.glowCluster(parent: Instance, base: Vector3, rng: Random)
	local m = model("GlowShrooms", parent)
	local color = Palette.pick(Palette.glowShroom, rng)
	local first: BasePart? = nil
	for _ = 1, rng:NextInteger(3, 5) do
		local pos = base + Vector3.new(rng:NextNumber(-1.2, 1.2), 0, rng:NextNumber(-1.2, 1.2))
		local height = rng:NextNumber(0.6, 1.4)
		decor(make("Part", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(height, 0.32, 0.32),
			CFrame = CFrame.new(pos + Vector3.new(0, height / 2, 0)) * VERTICAL,
			Color = Color3.fromRGB(220, 230, 240),
			Parent = m,
		}))
		local capSize = rng:NextNumber(1, 1.7)
		local cap = decor(make("Part", {
			Size = Vector3.new(capSize, capSize, capSize),
			Position = pos + Vector3.new(0, height, 0),
			Color = color,
			Material = Enum.Material.Neon,
			Parent = m,
		}))
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Scale = Vector3.new(1, 0.55, 1)
		mesh.Parent = cap
		first = first or cap
	end
	if first then
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 9
		light.Brightness = 1.2
		light.Parent = first
	end
end

-- Wisząca latarnia: daszek, świecąca szybka, podstawa. Zwraca szybkę (do niej idzie światło).
local function hangingLantern(parent: Instance, top: Vector3, range: number): BasePart
	local metal = Palette.metal
	decor(make("Part", { Size = Vector3.new(0.12, 0.8, 0.12), Position = top + Vector3.new(0, -0.4, 0), Color = metal, Parent = parent }))
	decor(make("Part", { Size = Vector3.new(1.1, 0.25, 1.1), Position = top + Vector3.new(0, -0.9, 0), Color = metal, Parent = parent }))
	local glass = decor(make("Part", {
		Name = "Glass",
		Size = Vector3.new(0.8, 1, 0.8),
		Position = top + Vector3.new(0, -1.55, 0),
		Color = Palette.lanternGlow,
		Material = Enum.Material.Neon,
		Parent = parent,
	}))
	decor(make("Part", { Size = Vector3.new(1, 0.22, 1), Position = top + Vector3.new(0, -2.15, 0), Color = metal, Parent = parent }))
	local light = Instance.new("PointLight")
	light.Color = Palette.lanternGlow
	light.Range = range
	light.Brightness = 1.2
	light.Shadows = false
	light.Parent = glass
	return glass
end
Props.hangingLantern = hangingLantern

function Props.lanternPost(parent: Instance, base: Vector3, facing: number)
	local m = model("LanternPost", parent)
	local wood = Palette.plankDark
	make("Part", { Size = Vector3.new(0.6, 7, 0.6), Position = base + Vector3.new(0, 3.5, 0), Color = wood, Parent = m })
	local armCF = CFrame.new(base + Vector3.new(0, 6.8, 0)) * CFrame.Angles(0, facing, 0)
	decor(make("Part", { Size = Vector3.new(2.4, 0.35, 0.35), CFrame = armCF * CFrame.new(1, 0, 0), Color = wood, Parent = m }))
	hangingLantern(m, (armCF * CFrame.new(1.9, -0.15, 0)).Position, 18)
end

-- Napis lokalizowany po stronie klienta (patrz src/client/Signs.luau)
function Props.signBoard(parent: Instance, cf: CFrame, size: Vector3, signKey: string, face: Enum.NormalId): BasePart
	local board = make("Part", {
		Name = "Sign",
		Size = size,
		CFrame = cf,
		Color = Palette.signWood,
		CanCollide = false,
		Parent = parent,
	})
	board:SetAttribute("SignKey", signKey)
	board:SetAttribute("SignFace", face.Name)
	CollectionService:AddTag(board, "LocalizedSign")
	return board
end

-- Brama na granicy strefy: dwa słupy z bali, belka, szyld i dwie latarnie
function Props.gate(parent: Instance, z: number, signKey: string)
	local m = model("Gate_" .. signKey, parent)
	local halfSpan = 7
	local height = 10
	for _, side in { -1, 1 } do
		trunk(m, Vector3.new(side * halfSpan, 0, z), height, 1.4, Palette.log)
		hangingLantern(m, Vector3.new(side * (halfSpan - 1.6), height - 0.8, z), 16)
	end
	make("Part", {
		Name = "Beam",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(halfSpan * 2 + 3, 1.2, 1.2),
		Position = Vector3.new(0, height - 0.5, z),
		Color = Palette.log,
		Parent = m,
	})
	-- Szyld wisi na łańcuszkach pod belką, napis od strony nadchodzącego gracza (-Z)
	for _, side in { -1, 1 } do
		decor(make("Part", { Size = Vector3.new(0.12, 1.2, 0.12), Position = Vector3.new(side * 3, height - 1.6, z), Color = Palette.metal, Parent = m }))
	end
	Props.signBoard(m, CFrame.new(0, height - 3.2, z), Vector3.new(8, 2.2, 0.35), signKey, Enum.NormalId.Front)
end

-- Kamienie ścieżki wijącej się od chatki w głąb lasu
function Props.path(parent: Instance, fromZ: number, toZ: number, rng: Random)
	local m = model("Path", parent)
	local z = fromZ
	while z < toZ do
		local x = 3 * math.sin(z / 16) + rng:NextNumber(-0.6, 0.6)
		local d = rng:NextNumber(1.8, 2.8)
		decor(make("Part", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, d, d * rng:NextNumber(0.8, 1)),
			CFrame = CFrame.new(x, -0.04, z) * VERTICAL * CFrame.Angles(rng:NextNumber(0, TAU), 0, 0),
			Color = Palette.stone:Lerp(Palette.ground[2], rng:NextNumber(0.3, 0.5)),
			Parent = m,
		}))
		z += rng:NextNumber(2.4, 3.2)
	end
end

function Props.pathX(z: number): number
	return 3 * math.sin(z / 16)
end

return Props
