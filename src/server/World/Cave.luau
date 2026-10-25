--!strict
-- Jaskinia: drugi świat za portalem w Gnieździe Leszego.
-- Obozowisko górników (bezpieczne, z olejem i skupem) → Kryształowe Korytarze →
-- Podziemne Jezioro → Otchłań. Wszystko z klocków, jak las: skalne ściany z głazów,
-- strop ze stalaktytami, świecące kryształy, tory kolejki, jezioro i szczeliny z lawą.
-- Strefy leżą wzdłuż osi +Z (Config.Zones z world = "cave"), daleko za lasem.

local CollectionService = game:GetService("CollectionService")
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Palette = require(script.Parent.Palette)
local Props = require(script.Parent.Props)

local Cave = {}

export type Api = {
	-- Szuka wolnego miejsca w prostokącie (jak w MapBuilder) i je zajmuje
	place: (rng: Random, x1: number, x2: number, z1: number, z2: number, radius: number) -> (number?, number?),
}

export type Rect = { x1: number, x2: number, z1: number, z2: number }

local VERTICAL = CFrame.Angles(0, 0, math.rad(90))

local FLOOR_COLORS: { [string]: Color3 } = {
	camp = Color3.fromRGB(84, 70, 58),
	crystal = Color3.fromRGB(58, 60, 78),
	lake = Color3.fromRGB(44, 58, 64),
	abyss = Color3.fromRGB(52, 34, 34),
}
local ROCK_COLORS: { [string]: { Color3 } } = {
	camp = { Color3.fromRGB(104, 90, 78), Color3.fromRGB(92, 80, 70), Color3.fromRGB(116, 100, 86) },
	crystal = { Color3.fromRGB(76, 78, 100), Color3.fromRGB(66, 68, 90), Color3.fromRGB(88, 86, 112) },
	lake = { Color3.fromRGB(58, 74, 82), Color3.fromRGB(50, 64, 72), Color3.fromRGB(68, 84, 90) },
	abyss = { Color3.fromRGB(66, 44, 44), Color3.fromRGB(56, 38, 40), Color3.fromRGB(78, 50, 46) },
}
local CRYSTAL_COLORS: { [string]: { Color3 } } = {
	camp = { Color3.fromRGB(255, 190, 90) },
	crystal = { Color3.fromRGB(90, 220, 255), Color3.fromRGB(170, 110, 255), Color3.fromRGB(120, 255, 230) },
	lake = { Color3.fromRGB(80, 200, 220), Color3.fromRGB(150, 240, 255) },
	abyss = { Color3.fromRGB(255, 70, 50), Color3.fromRGB(255, 140, 40) },
}
-- Ile ozdób w strefie
local RECIPES: { [string]: { stalactites: number, stalagmites: number, crystals: number, boulders: number, glow: number } } = {
	camp = { stalactites = 6, stalagmites = 2, crystals = 3, boulders = 4, glow = 2 },
	crystal = { stalactites = 16, stalagmites = 10, crystals = 22, boulders = 10, glow = 4 },
	lake = { stalactites = 14, stalagmites = 8, crystals = 10, boulders = 8, glow = 8 },
	abyss = { stalactites = 18, stalagmites = 12, crystals = 12, boulders = 14, glow = 0 },
}

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

local function decor(p: BasePart): BasePart
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	return p
end

local function pick(list: { Color3 }, rng: Random): Color3
	return list[rng:NextInteger(1, #list)]
end

local function caveZones(): { { index: number, zone: Config.ZoneDef } }
	local list = {}
	for index, zone in Config.Zones do
		if zone.world == "cave" then
			table.insert(list, { index = index, zone = zone })
		end
	end
	return list
end

-- Ostrosłup z czterech CornerWedge (jak sosna w lesie). flip = wisi czubkiem w dół (stalaktyt).
local function spike(parent: Instance, base: Vector3, width: number, height: number, yaw: number, color: Color3, flip: boolean)
	local origin = CFrame.new(base + Vector3.new(0, if flip then -height / 2 else height / 2, 0))
	if flip then
		origin *= CFrame.Angles(math.pi, 0, 0)
	end
	for i = 0, 3 do
		local p = make("CornerWedgePart", {
			Size = Vector3.new(width / 2, height, width / 2),
			CFrame = origin * CFrame.Angles(0, yaw + math.rad(90 * i), 0) * CFrame.new(-width / 4, 0, width / 4),
			Color = color,
			Material = Enum.Material.Slate,
			Parent = parent,
		})
		if flip then
			decor(p)
		end
	end
end

-- Kępka kryształów: kilka wydłużonych, przechylonych bloków z neonu i jedno światło
local function crystalCluster(parent: Instance, base: Vector3, color: Color3, rng: Random, scale: number)
	local m = Instance.new("Model")
	m.Name = "Crystals"
	local first: BasePart? = nil
	for _ = 1, rng:NextInteger(3, 5) do
		local height = rng:NextNumber(2, 5) * scale
		local width = rng:NextNumber(0.6, 1.2) * scale
		local tilt = CFrame.Angles(math.rad(rng:NextNumber(-25, 25)), rng:NextNumber(0, math.pi * 2), math.rad(rng:NextNumber(-25, 25)))
		local offset = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * scale
		local p = decor(make("Part", {
			Size = Vector3.new(width, height, width),
			CFrame = CFrame.new(base + offset) * tilt * CFrame.new(0, height / 2 - 0.3, 0),
			Color = color,
			Material = Enum.Material.Neon,
			Transparency = 0.15,
			Parent = m,
		}))
		first = first or p
	end
	if first then
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 12 * scale
		light.Brightness = 0.9
		light.Parent = first
	end
	m.Parent = parent
end

local function boulder(parent: Instance, center: Vector3, size: number, color: Color3, rng: Random, collide: boolean)
	local p = make("Part", {
		Name = "Boulder",
		Size = Vector3.new(size * rng:NextNumber(0.8, 1.3), size * rng:NextNumber(0.7, 1.1), size * rng:NextNumber(0.8, 1.3)),
		CFrame = CFrame.new(center) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.4, 0.4)),
		Color = color,
		Material = Enum.Material.Slate,
		Parent = parent,
	})
	p.CanCollide = collide
end

-- ===== Portal =====

-- Rama portalu: siatka (mesh) wygenerowana w Studio z opisu „kamienny łuk porośnięty mchem
-- i grzybami”, zapisana jako asset (Config.Cave.portalMesh). Gdy siatki nie da się wczytać
-- (np. inne konto bez dostępu), stawiamy prosty łuk z kamieni.
local function meshFrame(parent: Instance, cf: CFrame): (boolean, number, number)
	local def = Config.Cave.portalMesh
	local ok, part = pcall(function()
		return InsertService:CreateMeshPartAsync(def.mesh, Enum.CollisionFidelity.Box, Enum.RenderFidelity.Automatic)
	end)
	if not ok or not part then
		warn("[Cave] Nie udało się wczytać siatki portalu, stawiam łuk z kamieni:", part)
		return false, 0, 0
	end
	local mesh = part :: MeshPart
	mesh.Name = "Frame"
	mesh.TextureID = def.texture
	mesh.Size = Vector3.new(def.size[1], def.size[2], def.size[3])
	mesh.CFrame = cf * CFrame.new(0, def.size[2] / 2, 0)
	mesh.Anchored = true
	-- Kolizja tylko na filarach (niewidzialne bloki), żeby otwór dało się przejść
	mesh.CanCollide = false
	mesh.CanQuery = false
	mesh.Parent = parent
	for _, side in { -1, 1 } do
		local pillar = make("Part", {
			Name = "PillarCollision",
			Size = Vector3.new(def.pillarWidth, def.size[2], def.size[3]),
			CFrame = cf * CFrame.new(side * (def.opening[1] / 2 + def.pillarWidth / 2), def.size[2] / 2, 0),
			Transparency = 1,
			Parent = parent,
		})
		pillar.CanQuery = false
	end
	return true, def.opening[1], def.opening[2]
end

local function stoneFrame(parent: Instance, cf: CFrame): (number, number)
	local stone = Color3.fromRGB(96, 90, 104)
	local rng = Random.new(7)
	for _, side in { -1, 1 } do
		for level = 0, 4 do
			make("Part", {
				Size = Vector3.new(2.6, 2.4, 2.6),
				CFrame = cf * CFrame.new(side * 5, 1.2 + level * 2.3, 0) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0),
				Color = stone,
				Material = Enum.Material.Slate,
				Parent = parent,
			})
		end
	end
	for i = 0, 6 do
		local angle = math.pi * i / 6
		make("Part", {
			Size = Vector3.new(2.4, 2.4, 2.6),
			CFrame = cf * CFrame.new(math.cos(angle) * 5, 11.5 + math.sin(angle) * 3, 0) * CFrame.Angles(0, 0, angle),
			Color = stone,
			Material = Enum.Material.Slate,
			Parent = parent,
		})
	end
	return 7.4, 11
end

-- Portal: rama, wirujące światło w otworze, grzybki u stóp i szyld na słupkach obok
-- (osobno, żeby napis nigdy nie chował się w kamieniach ani w ścianie jaskini).
-- cf: środek portalu na ziemi, przodem (-LookVector) do nadchodzącego gracza.
-- tag: opcjonalny tag dla wiru (klient barwi wir skrótu zależnie od tego, czy gracz ma dostęp).
function Cave.portal(parent: Instance, cf: CFrame, signKey: string, color: Color3, tag: string?): Model
	local m = Instance.new("Model")
	m.Name = "Portal_" .. signKey
	local hasMesh, openW, openH = meshFrame(m, cf)
	if not hasMesh then
		openW, openH = stoneFrame(m, cf)
	end

	-- Wir: płaski świecący owal wypełniający otwór
	local swirl = decor(make("Part", {
		Name = "Swirl",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, openH, openW),
		CFrame = cf * CFrame.new(0, openH / 2 + 0.2, 0) * CFrame.Angles(0, math.rad(90), 0),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		Parent = m,
	}))
	if tag then
		CollectionService:AddTag(swirl, tag)
	end
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 22
	light.Brightness = 2
	light.Parent = swirl
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(0.5, 0)
	emitter.Lifetime = NumberRange.new(1, 2)
	emitter.Rate = 25
	emitter.Speed = NumberRange.new(1, 3)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Parent = swirl

	-- Świecące grzybki u stóp ramy, po obu stronach
	local rng = Random.new(11)
	for _, side in { -1, 1 } do
		Props.glowCluster(m, (cf * CFrame.new(side * (openW / 2 + 3.2), 0, -1.6)).Position, rng)
	end

	-- Szyld na dwóch słupkach z przodu, z boku ścieżki
	local signCf = cf * CFrame.new(openW / 2 + 5.5, 0, -3)
	for _, side in { -1, 1 } do
		make("Part", { Size = Vector3.new(0.4, 4.6, 0.4), CFrame = signCf * CFrame.new(side * 3.2, 2.3, 0), Color = Palette.log, Parent = m })
	end
	Props.signBoard(m, signCf * CFrame.new(0, 3.8, 0), Vector3.new(7.4, 1.6, 0.3), signKey, Enum.NormalId.Front)
	m.Parent = parent
	return m
end

-- ===== Obozowisko =====

local function tent(parent: Instance, cf: CFrame, color: Color3)
	-- Namiot z dwóch klinów opartych o siebie
	for _, side in { -1, 1 } do
		make("WedgePart", {
			Size = Vector3.new(5, 4, 2.6),
			CFrame = cf * CFrame.new(side * 1.3, 2, 0) * CFrame.Angles(0, if side == 1 then math.rad(-90) else math.rad(90), 0),
			Color = color,
			Material = Enum.Material.Fabric,
			Parent = parent,
		})
	end
end

local function campfire(parent: Instance, base: Vector3)
	for i = 0, 7 do
		local angle = i / 8 * math.pi * 2
		make("Part", {
			Size = Vector3.new(0.9, 0.6, 0.9),
			Position = base + Vector3.new(math.cos(angle) * 1.8, 0.3, math.sin(angle) * 1.8),
			Color = Palette.rock[1],
			Material = Enum.Material.Slate,
			Parent = parent,
		})
	end
	local embers = decor(make("Part", {
		Size = Vector3.new(2, 0.4, 2),
		Position = base + Vector3.new(0, 0.2, 0),
		Color = Color3.fromRGB(255, 120, 40),
		Material = Enum.Material.Neon,
		Parent = parent,
	}))
	local fire = Instance.new("ParticleEmitter")
	fire.Texture = "rbxasset://textures/particles/fire_main.dds"
	fire.Color = ColorSequence.new(Color3.fromRGB(255, 180, 80), Color3.fromRGB(255, 70, 30))
	fire.LightEmission = 1
	fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0.2) })
	fire.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	fire.Lifetime = NumberRange.new(0.7, 1.2)
	fire.Rate = 22
	fire.Speed = NumberRange.new(2, 3)
	fire.SpreadAngle = Vector2.new(15, 15)
	fire.EmissionDirection = Enum.NormalId.Top
	fire.Parent = embers
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 150, 70)
	light.Range = 24
	light.Brightness = 1.4
	light.Parent = embers
end

local function stationRing(parent: Instance, station: Config.StationDef, color: Color3)
	local pieces = 18
	local length = 2 * math.pi * station.radius / pieces * 0.6
	for i = 1, pieces do
		local angle = (i - 1) / pieces * math.pi * 2
		decor(make("Part", {
			Name = "StationRing_" .. station.kind,
			Size = Vector3.new(0.35, 0.06, length),
			CFrame = CFrame.new(station.x + math.cos(angle) * station.radius, 0.03, station.z + math.sin(angle) * station.radius)
				* CFrame.Angles(0, -angle, 0),
			Color = color,
			Material = Enum.Material.Neon,
			Transparency = 0.25,
			Parent = parent,
		}))
	end
end

local function buildCamp(parent: Instance)
	local m = Instance.new("Model")
	m.Name = "MinersCamp"
	local camp = Config.Cave.camp

	-- Stanowisko z olejem: beczki i wózek górniczy po lewej
	local oil = Economy.station("oil", "cave")
	stationRing(m, oil, Color3.fromRGB(255, 186, 80))
	for i, offset in { Vector3.new(-3.2, 0, -1.5), Vector3.new(-3.4, 0, 1), Vector3.new(-1.6, 0, 2.6) } do
		make("Part", {
			Name = "OilBarrel",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2.8, 2.2, 2.2),
			CFrame = CFrame.new(Vector3.new(oil.x, 1.4, oil.z) + offset) * VERTICAL * CFrame.Angles(i * 0.4, 0, 0),
			Color = Color3.fromRGB(96, 66, 44),
			Parent = m,
		})
	end
	Props.signBoard(m, CFrame.new(oil.x, 6.5, oil.z + 4.6), Vector3.new(6, 1.5, 0.3), "SIGN_OIL", Enum.NormalId.Front)
	for _, side in { -1, 1 } do
		make("Part", { Size = Vector3.new(0.4, 6, 0.4), Position = Vector3.new(oil.x + side * 2.8, 3, oil.z + 4.6), Color = Palette.plankDark, Parent = m })
	end

	-- Kramik skupu po prawej: lada, daszek, skrzynki
	local shop = Economy.station("shop", "cave")
	stationRing(m, shop, Color3.fromRGB(150, 226, 110))
	local counterZ = shop.z + 4.2
	make("Part", { Size = Vector3.new(8, 3, 2), Position = Vector3.new(shop.x, 1.5, counterZ), Color = Palette.plankDark, Parent = m })
	make("Part", { Size = Vector3.new(8.6, 0.4, 2.4), Position = Vector3.new(shop.x, 3.2, counterZ), Color = Palette.plank, Parent = m })
	for _, side in { -1, 1 } do
		make("Part", { Size = Vector3.new(0.5, 7, 0.5), Position = Vector3.new(shop.x + side * 4, 3.5, counterZ + 0.8), Color = Palette.log, Parent = m })
	end
	make("Part", {
		Size = Vector3.new(9.6, 0.4, 4),
		CFrame = CFrame.new(shop.x, 7.2, counterZ) * CFrame.Angles(math.rad(-12), 0, 0),
		Color = Color3.fromRGB(150, 60, 50),
		Material = Enum.Material.Fabric,
		Parent = m,
	})
	Props.signBoard(m, CFrame.new(shop.x, 5.6, counterZ - 1.1), Vector3.new(6.5, 1.4, 0.3), "SIGN_SHOP", Enum.NormalId.Front)
	for i, offset in { Vector3.new(5.6, 0, 0), Vector3.new(5.4, 2, 0.3), Vector3.new(-5.6, 0, 0.5) } do
		make("Part", {
			Name = "Crate",
			Size = Vector3.new(2, 2, 2),
			Position = Vector3.new(shop.x, 1, counterZ) + offset,
			Orientation = Vector3.new(0, i * 9, 0),
			Color = Palette.plank,
			Parent = m,
		})
	end

	-- Namioty, ognisko i latarnie na palach
	tent(m, CFrame.new(-17, 0, camp.z + 10) * CFrame.Angles(0, math.rad(20), 0), Color3.fromRGB(170, 130, 80))
	tent(m, CFrame.new(18, 0, camp.z + 10) * CFrame.Angles(0, math.rad(-25), 0), Color3.fromRGB(120, 140, 90))
	campfire(m, Vector3.new(0, 0, camp.z + 7))
	for _, pos in { Vector3.new(-8, 0, camp.z - 8), Vector3.new(8, 0, camp.z - 8), Vector3.new(-8, 0, camp.z + 12), Vector3.new(8, 0, camp.z + 12) } do
		Props.lanternPost(m, pos, if pos.X < 0 then 0 else math.pi)
	end
	m.Parent = parent
end

-- ===== Elementy stref =====

-- Tory kolejki górniczej wzdłuż środka od obozowiska przez Kryształowe Korytarze
local function buildRails(parent: Instance, fromZ: number, toZ: number)
	local m = Instance.new("Model")
	m.Name = "Rails"
	local length = toZ - fromZ
	for _, x in { -1.2, 1.2 } do
		decor(make("Part", { Size = Vector3.new(0.25, 0.25, length), Position = Vector3.new(x, 0.32, fromZ + length / 2), Color = Palette.metal, Material = Enum.Material.Metal, Parent = m }))
	end
	for z = fromZ + 1, toZ - 1, 3 do
		decor(make("Part", { Size = Vector3.new(3.6, 0.2, 0.7), Position = Vector3.new(0, 0.1, z), Color = Palette.plankDark, Parent = m }))
	end
	m.Parent = parent
end

-- Drewniana obudowa chodnika (dwa słupy i belka) z przygaszoną latarnią
local function mineFrame(parent: Instance, z: number)
	local m = Instance.new("Model")
	m.Name = "MineFrame"
	for _, side in { -1, 1 } do
		make("Part", { Size = Vector3.new(1, 12, 1), Position = Vector3.new(side * 7, 6, z), Color = Palette.log, Parent = m })
	end
	make("Part", { Size = Vector3.new(16, 1, 1.2), Position = Vector3.new(0, 12.4, z), Color = Palette.log, Parent = m })
	local glass = Props.hangingLantern(m, Vector3.new(4, 11.9, z), 14)
	local light = glass:FindFirstChildOfClass("PointLight")
	if light then
		light.Brightness = 0.7
	end
	m.Parent = parent
end

-- Jeziorka w strefie jeziora: na bokach, ścieżka środkiem zostaje sucha
local function lakeRects(zone: Config.ZoneDef): { Rect }
	local hw = Config.Cave.halfWidth
	local midZ = (zone.startZ + zone.endZ) / 2
	return {
		{ x1 = -hw + 2, x2 = -10, z1 = zone.startZ + 12, z2 = midZ + 6 },
		{ x1 = 10, x2 = hw - 2, z1 = midZ - 10, z2 = zone.endZ - 14 },
	}
end

local function buildLake(parent: Instance, zone: Config.ZoneDef)
	for i, rect in lakeRects(zone) do
		local water = decor(make("Part", {
			Name = "Water_" .. i,
			Size = Vector3.new(rect.x2 - rect.x1, 0.2, rect.z2 - rect.z1),
			Position = Vector3.new((rect.x1 + rect.x2) / 2, 0.08, (rect.z1 + rect.z2) / 2),
			Color = Color3.fromRGB(30, 110, 140),
			Material = Enum.Material.Glass,
			Transparency = 0.25,
			Reflectance = 0.25,
			Parent = parent,
		}))
		water.CanCollide = false
		-- Delikatna poświata od dołu jeziora
		local glow = decor(make("Part", {
			Size = Vector3.new(rect.x2 - rect.x1 - 2, 0.05, rect.z2 - rect.z1 - 2),
			Position = water.Position - Vector3.new(0, 0.12, 0),
			Color = Color3.fromRGB(40, 170, 200),
			Material = Enum.Material.Neon,
			Transparency = 0.6,
			Parent = parent,
		}))
		local light = Instance.new("SurfaceLight")
		light.Face = Enum.NormalId.Top
		light.Color = Color3.fromRGB(80, 200, 230)
		light.Range = 10
		light.Brightness = 0.6
		light.Parent = glow
	end
end

-- Szczeliny z lawą w Otchłani: świecące pęknięcia w podłodze i iskry
local function buildLavaCracks(parent: Instance, zone: Config.ZoneDef, rng: Random, api: Api)
	local hw = Config.Cave.halfWidth - 4
	for i = 1, 14 do
		local x, z = api.place(rng, -hw, hw, zone.startZ + 4, zone.endZ - 4, 2.5)
		if x and z then
			local crack = decor(make("Part", {
				Name = "LavaCrack",
				Size = Vector3.new(rng:NextNumber(0.5, 0.9), 0.08, rng:NextNumber(5, 10)),
				CFrame = CFrame.new(x, 0.04, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
				Color = Color3.fromRGB(255, 100, 30),
				Material = Enum.Material.Neon,
				Parent = parent,
			}))
			if i % 3 == 0 then
				local sparks = Instance.new("ParticleEmitter")
				sparks.Texture = "rbxasset://textures/particles/fire_main.dds"
				sparks.Color = ColorSequence.new(Color3.fromRGB(255, 140, 50))
				sparks.LightEmission = 1
				sparks.Size = NumberSequence.new(0.4, 0)
				sparks.Lifetime = NumberRange.new(0.8, 1.6)
				sparks.Rate = 6
				sparks.Speed = NumberRange.new(2, 4)
				sparks.EmissionDirection = Enum.NormalId.Top
				sparks.Parent = crack
				local light = Instance.new("PointLight")
				light.Color = Color3.fromRGB(255, 110, 40)
				light.Range = 10
				light.Brightness = 1
				light.Parent = crack
			end
		end
	end
end

-- Ściany z głazów po bokach i na końcach, strop nad całą jaskinią
local function buildShell(parent: Instance, rng: Random)
	local hw = Config.Cave.halfWidth
	local height = Config.Cave.ceiling
	local folder = Instance.new("Folder")
	folder.Name = "Shell"
	local zones = caveZones()
	local first = zones[1].zone
	local last = zones[#zones].zone

	for _, entry in zones do
		local zone = entry.zone
		local length = zone.endZ - zone.startZ
		make("Part", {
			Name = "Floor_" .. zone.id,
			Size = Vector3.new(hw * 2 + 30, 2, length),
			Position = Vector3.new(0, -1, zone.startZ + length / 2),
			Color = FLOOR_COLORS[zone.id] or FLOOR_COLORS.crystal,
			Material = Enum.Material.Slate,
			Parent = folder,
		})
		make("Part", {
			Name = "Ceiling_" .. zone.id,
			Size = Vector3.new(hw * 2 + 30, 4, length),
			Position = Vector3.new(0, height + 2, zone.startZ + length / 2),
			Color = (ROCK_COLORS[zone.id] or ROCK_COLORS.crystal)[2],
			Material = Enum.Material.Slate,
			Parent = folder,
		})
		-- Głazy wzdłuż boków, w trzech warstwach aż pod strop
		local colors = ROCK_COLORS[zone.id] or ROCK_COLORS.crystal
		for _, side in { -1, 1 } do
			local z = zone.startZ
			while z < zone.endZ do
				for level = 0, 2 do
					local size = rng:NextNumber(9, 14)
					boulder(folder, Vector3.new(side * (hw + 4 + rng:NextNumber(-1.5, 1.5) - level), 4 + level * 11, z), size, pick(colors, rng), rng, level == 0)
				end
				z += rng:NextNumber(7, 10)
			end
		end
	end

	-- Ściany na początku i końcu jaskini
	for _, edge in { { z = first.startZ - 3, id = first.id }, { z = last.endZ + 3, id = last.id } } do
		local colors = ROCK_COLORS[edge.id] or ROCK_COLORS.crystal
		local x = -hw - 4
		while x < hw + 4 do
			for level = 0, 2 do
				boulder(folder, Vector3.new(x, 4 + level * 11, edge.z), rng:NextNumber(10, 14), pick(colors, rng), rng, true)
			end
			x += rng:NextNumber(8, 10)
		end
	end

	-- Niewidzialne ściany, żeby nikt nie przecisnął się między głazami
	local totalLength = last.endZ - first.startZ
	local centerZ = first.startZ + totalLength / 2
	local function wall(size: Vector3, position: Vector3)
		local w = make("Part", { Name = "InvisibleWall", Size = size, Position = position, Transparency = 1, Parent = folder })
		w.CanQuery = false
	end
	for _, side in { -1, 1 } do
		wall(Vector3.new(2, height + 4, totalLength), Vector3.new(side * (hw + 1), height / 2, centerZ))
	end
	for _, z in { first.startZ - 1, last.endZ + 1 } do
		wall(Vector3.new(hw * 2, height + 4, 2), Vector3.new(0, height / 2, z))
	end
	folder.Parent = parent
end

local function buildZoneDecor(parent: Instance, zone: Config.ZoneDef, rng: Random, api: Api)
	local recipe = RECIPES[zone.id]
	if not recipe then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Decor_" .. zone.id
	local hw = Config.Cave.halfWidth - 4
	local rocks = ROCK_COLORS[zone.id] or ROCK_COLORS.crystal
	local crystals = CRYSTAL_COLORS[zone.id] or CRYSTAL_COLORS.crystal
	local height = Config.Cave.ceiling
	local z1, z2 = zone.startZ + 3, zone.endZ - 3

	-- Stalaktyty wiszą ze stropu, więc nie zajmują miejsca na ziemi
	for _ = 1, recipe.stalactites do
		local width = rng:NextNumber(2.5, 5)
		spike(folder, Vector3.new(rng:NextNumber(-hw, hw), height, rng:NextNumber(z1, z2)), width, width * rng:NextNumber(2, 3.5), rng:NextNumber(0, math.pi), pick(rocks, rng), true)
	end
	for _ = 1, recipe.stalagmites do
		local width = rng:NextNumber(2, 4)
		local x, z = api.place(rng, -hw, hw, z1, z2, width / 2 + 1)
		if x and z then
			spike(folder, Vector3.new(x, 0, z), width, width * rng:NextNumber(1.8, 3), rng:NextNumber(0, math.pi), pick(rocks, rng), false)
		end
	end
	for _ = 1, recipe.boulders do
		local size = rng:NextNumber(2.5, 5)
		local x, z = api.place(rng, -hw, hw, z1, z2, size / 2 + 0.5)
		if x and z then
			boulder(folder, Vector3.new(x, size * 0.3, z), size, pick(rocks, rng), rng, true)
		end
	end
	for _ = 1, recipe.crystals do
		local x, z = api.place(rng, -hw, hw, z1, z2, 2.2)
		if x and z then
			crystalCluster(folder, Vector3.new(x, 0, z), pick(crystals, rng), rng, rng:NextNumber(0.8, 1.4))
		end
	end
	for _ = 1, recipe.glow do
		local x, z = api.place(rng, -hw, hw, z1, z2, 2)
		if x and z then
			Props.glowCluster(folder, Vector3.new(x, 0, z), rng)
		end
	end

	if zone.id == "crystal" then
		for z = zone.startZ + 20, zone.endZ - 10, 30 do
			mineFrame(folder, z)
		end
	elseif zone.id == "lake" then
		buildLake(folder, zone)
	elseif zone.id == "abyss" then
		buildLavaCracks(folder, zone, rng, api)
	end
	folder.Parent = parent
end

-- Miejsca, gdzie nic nie może stanąć ani wyrosnąć (obozowisko, ścieżka, jeziorka)
function Cave.reservedRects(): { Rect }
	local rects: { Rect } = {}
	for _, entry in caveZones() do
		local zone = entry.zone
		if zone.safe then
			table.insert(rects, { x1 = -Config.Cave.halfWidth, x2 = Config.Cave.halfWidth, z1 = zone.startZ - 4, z2 = zone.endZ + 2 })
		else
			-- Środek zostaje wolny, żeby dało się przejść (tory, brama strefy)
			table.insert(rects, { x1 = -2.6, x2 = 2.6, z1 = zone.startZ, z2 = zone.endZ })
			table.insert(rects, { x1 = -9.5, x2 = 9.5, z1 = zone.startZ - 2.5, z2 = zone.startZ + 2.5 })
		end
		if zone.id == "lake" then
			for _, rect in lakeRects(zone) do
				table.insert(rects, rect)
			end
		elseif zone.id == "crystal" then
			for z = zone.startZ + 20, zone.endZ - 10, 30 do
				table.insert(rects, { x1 = -8.5, x2 = 8.5, z1 = z - 1.5, z2 = z + 1.5 }) -- słupy obudowy chodnika
			end
		end
	end
	return rects
end

-- Buduje całą jaskinię. Miejsca na grzyby wyznacza MapBuilder (wspólne zajmowanie miejsca).
-- Zwraca CFrame obozowiska: tu ląduje gracz po wejściu przez portal i po zgaśnięciu latarni.
function Cave.build(parent: Instance, rng: Random, api: Api): CFrame
	local folder = Instance.new("Folder")
	folder.Name = "Cave"
	buildShell(folder, rng)
	buildCamp(folder)
	for index, entry in caveZones() do
		local zone = entry.zone
		if index > 1 then
			Props.gate(folder, zone.startZ, zone.key)
		end
		buildZoneDecor(folder, zone, rng, api)
	end
	local zones = caveZones()
	buildRails(folder, zones[1].zone.startZ + 2, zones[2].zone.endZ)
	folder.Parent = parent
	local camp = Config.Cave.camp
	return CFrame.new(camp.x, 3, camp.z) -- twarzą w głąb jaskini (+Z)
		* CFrame.Angles(0, math.pi, 0)
end

return Cave
