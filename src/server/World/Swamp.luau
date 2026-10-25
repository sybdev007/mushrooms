--!strict
-- Bagna: trzeci świat, za portalem w Sztolni Skarbnika (od 1 000 000 monet).
-- Przystań na palach (bezpieczna, z olejem i skupem) → Trzęsawisko → Mokradła Ogników → Staw Utopca.
-- Otwarte nocne niebo, zielona mgła, kładka z desek środkiem bagien, rozlewiska z liliami,
-- wierzby płaczące, pałki wodne, martwe drzewa, unoszące się błędne ogniki i wyspa Utopca na stawie.
-- Strefy leżą wzdłuż osi +Z (Config.Zones z world = "swamp"), daleko za jaskinią.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Palette = require(script.Parent.Palette)
local Props = require(script.Parent.Props)
local Utopiec = require(script.Parent.Utopiec)

local Swamp = {}

export type Api = {
	place: (rng: Random, x1: number, x2: number, z1: number, z2: number, radius: number) -> (number?, number?),
}
export type Rect = { x1: number, x2: number, z1: number, z2: number }

local VERTICAL = CFrame.Angles(0, 0, math.rad(90))
local DECK_Y = 0.6 -- górna powierzchnia kładki i pomostów

local MUD: { [string]: Color3 } = {
	jetty = Color3.fromRGB(66, 70, 46),
	bog = Color3.fromRGB(58, 66, 40),
	wisps = Color3.fromRGB(44, 58, 44),
	pond = Color3.fromRGB(34, 46, 40),
}
local WATER = Color3.fromRGB(40, 70, 52)
local REED = Color3.fromRGB(110, 120, 60)
local CATTAIL = Color3.fromRGB(96, 60, 36)
local WILLOW = { Color3.fromRGB(70, 96, 52), Color3.fromRGB(84, 108, 58), Color3.fromRGB(60, 84, 50) }
local WISP_COLORS = { Color3.fromRGB(140, 255, 220), Color3.fromRGB(180, 255, 140), Color3.fromRGB(120, 200, 255) }

-- Ile czego w strefie
local RECIPES: { [string]: { willows: number, dead: number, reeds: number, pools: number, wisps: number, logs: number } } = {
	bog = { willows = 8, dead = 10, reeds = 22, pools = 6, wisps = 4, logs = 5 },
	wisps = { willows = 6, dead = 14, reeds = 18, pools = 6, wisps = 14, logs = 4 },
	pond = { willows = 6, dead = 12, reeds = 16, pools = 3, wisps = 8, logs = 3 },
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

local function swampZones(): { { index: number, zone: Config.ZoneDef } }
	local list = {}
	for index, zone in Config.Zones do
		if zone.world == "swamp" then
			table.insert(list, { index = index, zone = zone })
		end
	end
	return list
end

-- ===== Rozlewiska (wspólne dla budowy i rezerwacji, więc liczone z własnego ziarna) =====

local function poolRects(zone: Config.ZoneDef, zoneIndex: number): { Rect }
	local recipe = RECIPES[zone.id]
	if not recipe then
		return {}
	end
	local rng = Random.new(Config.SpotSeed * 7 + zoneIndex)
	local hw = Config.Swamp.halfWidth - 6
	local rects: { Rect } = {}
	for _ = 1, recipe.pools do
		local w, d = rng:NextNumber(10, 22), rng:NextNumber(10, 20)
		-- Po lewej albo prawej stronie kładki, nigdy na niej
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local cx = side * rng:NextNumber(Config.Swamp.boardwalkHalf + 3 + w / 2, hw - w / 2)
		local cz = rng:NextNumber(zone.startZ + 6 + d / 2, zone.endZ - 6 - d / 2)
		table.insert(rects, { x1 = cx - w / 2, x2 = cx + w / 2, z1 = cz - d / 2, z2 = cz + d / 2 })
	end
	return rects
end

-- Staw Utopca: duży okrągły staw z wyspą pośrodku (wyspa to legowisko)
local POND_RADIUS = 34

-- ===== Elementy =====

local function waterSheet(parent: Instance, rect: Rect)
	local w, d = rect.x2 - rect.x1, rect.z2 - rect.z1
	decor(make("Part", {
		Name = "Pool",
		Size = Vector3.new(w, 0.2, d),
		Position = Vector3.new((rect.x1 + rect.x2) / 2, 0.1, (rect.z1 + rect.z2) / 2),
		Color = WATER,
		Material = Enum.Material.Glass,
		Transparency = 0.2,
		Reflectance = 0.3,
		Parent = parent,
	}))
end

-- Liść lilii wodnej (czasem z kwiatem)
local function lilyPad(parent: Instance, x: number, z: number, rng: Random)
	local size = rng:NextNumber(1.4, 2.6)
	decor(make("Part", {
		Name = "LilyPad",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.08, size, size),
		CFrame = CFrame.new(x, 0.24, z) * VERTICAL,
		Color = Color3.fromRGB(70, 130, 60),
		Parent = parent,
	}))
	if rng:NextNumber() < 0.35 then
		decor(make("Part", {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.7, 0.5, 0.7),
			Position = Vector3.new(x + 0.2, 0.45, z),
			Color = Color3.fromRGB(255, 170, 210),
			Material = Enum.Material.Neon,
			Parent = parent,
		}))
	end
end

-- Kępa trzciny i pałek wodnych
local function reeds(parent: Instance, base: Vector3, rng: Random)
	local m = Instance.new("Model")
	m.Name = "Reeds"
	for _ = 1, rng:NextInteger(5, 9) do
		local pos = base + Vector3.new(rng:NextNumber(-1.4, 1.4), 0, rng:NextNumber(-1.4, 1.4))
		local height = rng:NextNumber(3, 6)
		local tilt = CFrame.Angles(math.rad(rng:NextNumber(-10, 10)), 0, math.rad(rng:NextNumber(-10, 10)))
		decor(make("Part", {
			Size = Vector3.new(0.15, height, 0.15),
			CFrame = CFrame.new(pos) * tilt * CFrame.new(0, height / 2, 0),
			Color = REED,
			Parent = m,
		}))
		if rng:NextNumber() < 0.5 then
			decor(make("Part", {
				Name = "Cattail",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(1, 0.4, 0.4),
				CFrame = CFrame.new(pos) * tilt * CFrame.new(0, height - 0.5, 0) * VERTICAL,
				Color = CATTAIL,
				Parent = m,
			}))
		end
	end
	m.Parent = parent
end

-- Wierzba płacząca: krzywy pień, rozłożysta korona i zwisające pasma liści
local function willow(parent: Instance, base: Vector3, rng: Random, scale: number)
	local m = Instance.new("Model")
	m.Name = "Willow"
	local height = 9 * scale
	local lean = CFrame.Angles(math.rad(rng:NextNumber(-6, 6)), 0, math.rad(rng:NextNumber(-6, 6)))
	make("Part", {
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, 1.6 * scale, 1.6 * scale),
		CFrame = CFrame.new(base) * lean * CFrame.new(0, height / 2, 0) * VERTICAL,
		Color = Palette.trunkDark,
		Parent = m,
	})
	local top = (CFrame.new(base) * lean * CFrame.new(0, height, 0)).Position
	local color = pick(WILLOW, rng)
	local crown = decor(make("Part", {
		Size = Vector3.new(11, 5, 11) * scale,
		Position = top + Vector3.new(0, 0.5, 0),
		Color = color,
		Parent = m,
	}))
	crown.CastShadow = true
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = crown
	-- Zwisające pasma: cienkie, długie klocki po obwodzie korony
	for k = 1, 14 do
		local angle = k / 14 * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
		local r = 5 * scale * rng:NextNumber(0.75, 1)
		local length = rng:NextNumber(4, 7.5) * scale
		decor(make("Part", {
			Name = "Strand",
			Size = Vector3.new(0.5, length, 0.5),
			Position = top + Vector3.new(math.cos(angle) * r, -length / 2 + 0.5, math.sin(angle) * r),
			Color = color:Lerp(Color3.fromRGB(40, 60, 30), 0.2),
			Parent = m,
		}))
	end
	m.Parent = parent
end

-- Błędny ognik: świecąca kula, która powoli unosi się i opada (tween na serwerze widzą wszyscy)
local function wisp(parent: Instance, position: Vector3, rng: Random)
	local color = pick(WISP_COLORS, rng)
	local orb = decor(make("Part", {
		Name = "Wisp",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.9, 0.9, 0.9),
		Position = position,
		Color = color,
		Material = Enum.Material.Neon,
		Parent = parent,
	}))
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 10
	light.Brightness = 1.5
	light.Parent = orb
	local trail = Instance.new("ParticleEmitter")
	trail.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	trail.Color = ColorSequence.new(color)
	trail.LightEmission = 1
	trail.Size = NumberSequence.new(0.4, 0)
	trail.Lifetime = NumberRange.new(0.6, 1)
	trail.Rate = 6
	trail.Speed = NumberRange.new(0.2, 0.6)
	trail.SpreadAngle = Vector2.new(180, 180)
	trail.Parent = orb
	local drift = position + Vector3.new(rng:NextNumber(-4, 4), rng:NextNumber(1, 2.5), rng:NextNumber(-4, 4))
	TweenService:Create(orb, TweenInfo.new(rng:NextNumber(3, 6), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Position = drift,
	}):Play()
end

-- Kładka z desek na palikach (deski wzdłuż, poprzeczki, paliki co kilka studs)
local function boardwalk(parent: Instance, fromZ: number, toZ: number, rng: Random)
	local m = Instance.new("Model")
	m.Name = "Boardwalk"
	local half = Config.Swamp.boardwalkHalf
	local z = fromZ
	while z < toZ do
		local length = math.min(10, toZ - z)
		for i = -1, 1 do
			make("Part", {
				Name = "Board",
				Size = Vector3.new(half * 2 / 3 - 0.1, 0.3, length - 0.1),
				Position = Vector3.new(i * half * 2 / 3, DECK_Y - 0.15, z + length / 2),
				Color = if (i + math.floor(z / 10)) % 2 == 0 then Palette.plank else Palette.plankDark,
				Parent = m,
			})
		end
		decor(make("Part", { Size = Vector3.new(half * 2 + 0.6, 0.25, 0.6), Position = Vector3.new(0, DECK_Y - 0.4, z + 0.3), Color = Palette.plankDark, Parent = m }))
		for _, side in { -1, 1 } do
			decor(make("Part", {
				Name = "Post",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(1.6, 0.45, 0.45),
				CFrame = CFrame.new(side * (half + 0.2), DECK_Y - 0.2, z + 0.3) * VERTICAL * CFrame.Angles(rng:NextNumber(-0.1, 0.1), 0, 0),
				Color = Palette.log,
				Parent = m,
			}))
		end
		z += length
	end
	m.Parent = parent
end

-- Chatka rybacka na palach
local function stiltHut(parent: Instance, cf: CFrame, color: Color3)
	local m = Instance.new("Model")
	m.Name = "StiltHut"
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			make("Part", { Size = Vector3.new(0.6, 4, 0.6), CFrame = cf * CFrame.new(sx * 3.2, 2, sz * 2.6), Color = Palette.log, Parent = m })
		end
	end
	make("Part", { Size = Vector3.new(8, 0.4, 7), CFrame = cf * CFrame.new(0, 4.2, 0), Color = Palette.plankDark, Parent = m })
	make("Part", { Size = Vector3.new(7, 4.6, 6), CFrame = cf * CFrame.new(0, 6.7, 0), Color = color, Parent = m })
	for _, side in { -1, 1 } do
		make("Part", {
			Size = Vector3.new(4.6, 0.4, 7.6),
			CFrame = cf * CFrame.new(side * 1.9, 9.8, 0) * CFrame.Angles(0, 0, math.rad(side * -32)),
			Color = Color3.fromRGB(110, 90, 50),
			Material = Enum.Material.Grass,
			Parent = m,
		})
	end
	local window = decor(make("Part", { Size = Vector3.new(1.6, 1.4, 0.1), CFrame = cf * CFrame.new(-1.4, 7, -3.05), Color = Palette.windowGlow, Material = Enum.Material.Neon, Parent = m }))
	local light = Instance.new("PointLight")
	light.Color = Palette.windowGlow
	light.Range = 12
	light.Brightness = 0.8
	light.Parent = window
	make("Part", { Size = Vector3.new(1.8, 3, 0.15), CFrame = cf * CFrame.new(1.4, 5.9, -3.05), Color = Palette.plankDark, Parent = m })
	m.Parent = parent
end

local function stationRing(parent: Instance, station: Config.StationDef, color: Color3)
	local pieces = 18
	local length = 2 * math.pi * station.radius / pieces * 0.6
	for i = 1, pieces do
		local angle = (i - 1) / pieces * math.pi * 2
		decor(make("Part", {
			Name = "StationRing_" .. station.kind,
			Size = Vector3.new(0.35, 0.06, length),
			CFrame = CFrame.new(station.x + math.cos(angle) * station.radius, DECK_Y + 0.03, station.z + math.sin(angle) * station.radius)
				* CFrame.Angles(0, -angle, 0),
			Color = color,
			Material = Enum.Material.Neon,
			Transparency = 0.25,
			Parent = parent,
		}))
	end
end

-- Przystań: szeroki pomost, dwie chatki na palach, stanowiska przodem do środka, latarnie
local function buildJetty(parent: Instance, zone: Config.ZoneDef)
	local m = Instance.new("Model")
	m.Name = "Jetty"
	local hw = Config.Swamp.halfWidth
	make("Part", {
		Name = "Deck",
		Size = Vector3.new(hw * 2 - 10, 0.4, zone.endZ - zone.startZ - 2),
		Position = Vector3.new(0, DECK_Y - 0.2, (zone.startZ + zone.endZ) / 2),
		Color = Palette.plank,
		Parent = m,
	})
	-- Szczeliny między deskami pomostu
	for x = -hw + 8, hw - 8, 2.4 do
		decor(make("Part", { Size = Vector3.new(0.12, 0.05, zone.endZ - zone.startZ - 2), Position = Vector3.new(x, DECK_Y + 0.01, (zone.startZ + zone.endZ) / 2), Color = Palette.plankDark, Parent = m }))
	end

	local function facingCentre(station: Config.StationDef): CFrame
		return CFrame.lookAt(Vector3.new(station.x, DECK_Y, station.z), Vector3.new(0, DECK_Y, station.z))
	end

	-- Olej: beczki na pomoście
	local oil = Economy.station("oil", "swamp")
	stationRing(m, oil, Color3.fromRGB(255, 186, 80))
	local oilCf = facingCentre(oil)
	for i, offset in { Vector3.new(-2.6, 0, 4.4), Vector3.new(0, 0, 4.8), Vector3.new(2.6, 0, 4.4) } do
		make("Part", {
			Name = "OilBarrel",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2.8, 2.2, 2.2),
			CFrame = oilCf * CFrame.new(offset + Vector3.new(0, 1.4, 0)) * VERTICAL * CFrame.Angles(i * 0.5, 0, 0),
			Color = Color3.fromRGB(96, 66, 44),
			Parent = m,
		})
	end
	for _, side in { -1, 1 } do
		make("Part", { Size = Vector3.new(0.4, 6.4, 0.4), CFrame = oilCf * CFrame.new(side * 3.4, 3.2, 3.6), Color = Palette.plankDark, Parent = m })
	end
	Props.signBoard(m, oilCf * CFrame.new(0, 6.6, 3.2), Vector3.new(7, 1.5, 0.3), "SIGN_OIL", Enum.NormalId.Front)
	Props.hangingLantern(m, (oilCf * CFrame.new(3.4, 6.2, 2.6)).Position, 16)

	-- Skup: łódź-kramik z daszkiem
	local shop = Economy.station("shop", "swamp")
	stationRing(m, shop, Color3.fromRGB(150, 226, 110))
	local shopCf = facingCentre(shop)
	make("Part", { Name = "Counter", Size = Vector3.new(8, 3, 2), CFrame = shopCf * CFrame.new(0, 1.5, 5), Color = Palette.plankDark, Parent = m })
	make("Part", { Size = Vector3.new(8.6, 0.4, 2.4), CFrame = shopCf * CFrame.new(0, 3.2, 5), Color = Palette.plank, Parent = m })
	for _, side in { -1, 1 } do
		make("Part", { Size = Vector3.new(0.5, 7.4, 0.5), CFrame = shopCf * CFrame.new(side * 4.2, 3.7, 4.2), Color = Palette.log, Parent = m })
		make("Part", { Size = Vector3.new(0.5, 7.4, 0.5), CFrame = shopCf * CFrame.new(side * 4.2, 3.7, 7.6), Color = Palette.log, Parent = m })
	end
	for i = 0, 5 do
		make("Part", {
			Size = Vector3.new(1.6, 0.3, 4.6),
			CFrame = shopCf * CFrame.new(-4 + i * 1.6, 7.6, 5.8) * CFrame.Angles(math.rad(14), 0, 0),
			Color = if i % 2 == 0 then Color3.fromRGB(60, 110, 70) else Color3.fromRGB(230, 214, 180),
			Material = Enum.Material.Fabric,
			Parent = m,
		})
	end
	Props.signBoard(m, shopCf * CFrame.new(0, 6.2, 3.95), Vector3.new(6.8, 1.4, 0.3), "SIGN_SHOP", Enum.NormalId.Front)
	Props.hangingLantern(m, (shopCf * CFrame.new(0, 7.2, 4.4)).Position, 18)

	-- Chatki na palach po bokach i łódka przycumowana do pomostu
	stiltHut(m, CFrame.new(-hw + 12, 0, zone.startZ + 30) * CFrame.Angles(0, math.rad(15), 0), Color3.fromRGB(120, 92, 64))
	stiltHut(m, CFrame.new(hw - 12, 0, zone.startZ + 31) * CFrame.Angles(0, math.rad(-18), 0), Color3.fromRGB(104, 84, 60))
	m.Parent = parent
end

-- Wyspa Utopca na środku stawu: trawiasta wysepka, krąg pałek, zatopiona łódź, posąg na kamieniu.
-- Zwraca posąg.
local function buildPond(parent: Instance, rng: Random): Model
	local lair = Config.UtopiecLair
	local center = Vector3.new(lair.centerX, 0, lair.centerZ)
	local m = Instance.new("Model")
	m.Name = "UtopiecPond"
	-- Ciemna woda stawu i poświata z głębi
	decor(make("Part", {
		Name = "PondWater",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, POND_RADIUS * 2, POND_RADIUS * 2),
		CFrame = CFrame.new(center + Vector3.new(0, 0.12, 0)) * VERTICAL,
		Color = Color3.fromRGB(24, 60, 50),
		Material = Enum.Material.Glass,
		Transparency = 0.15,
		Reflectance = 0.35,
		Parent = m,
	}))
	local glow = decor(make("Part", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.05, POND_RADIUS * 2 - 4, POND_RADIUS * 2 - 4),
		CFrame = CFrame.new(center + Vector3.new(0, 0.04, 0)) * VERTICAL,
		Color = Color3.fromRGB(40, 160, 120),
		Material = Enum.Material.Neon,
		Transparency = 0.7,
		Parent = m,
	}))
	local deep = Instance.new("PointLight")
	deep.Color = Color3.fromRGB(60, 200, 150)
	deep.Range = 30
	deep.Brightness = 0.8
	deep.Parent = glow
	-- Wysepka
	make("Part", {
		Name = "Island",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, lair.radius * 2, lair.radius * 2),
		CFrame = CFrame.new(center + Vector3.new(0, 0.2, 0)) * VERTICAL,
		Color = Color3.fromRGB(64, 92, 50),
		Material = Enum.Material.Grass,
		Parent = m,
	})
	for i = 0, 15 do
		local angle = i / 16 * math.pi * 2
		reeds(m, center + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (lair.radius - 0.5), rng)
	end
	for _ = 1, 22 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(lair.radius + 2, POND_RADIUS - 2)
		lilyPad(m, center.X + math.cos(angle) * r, center.Z + math.sin(angle) * r, rng)
	end
	-- Zatopiona łódź przy brzegu wyspy
	local boatCf = CFrame.new(center + Vector3.new(lair.radius + 6, 0, 4)) * CFrame.Angles(math.rad(-12), math.rad(30), math.rad(18))
	make("Part", { Name = "BoatHull", Size = Vector3.new(3.4, 1.4, 9), CFrame = boatCf * CFrame.new(0, 0.3, 0), Color = Palette.plankDark, Parent = m })
	make("WedgePart", { Size = Vector3.new(3.4, 1.4, 2.4), CFrame = boatCf * CFrame.new(0, 0.3, -5.7) * CFrame.Angles(0, math.pi, 0), Color = Palette.plankDark, Parent = m })
	-- Tabliczka ostrzegawcza na kładce przed stawem
	local signZ = center.Z - POND_RADIUS - 2
	for _, side in { -1, 1 } do
		make("Part", { Size = Vector3.new(0.4, 4.6, 0.4), Position = Vector3.new(center.X + 8 + side * 4.2, 2.3, signZ + 0.4), Color = Palette.log, Parent = m })
	end
	Props.signBoard(m, CFrame.new(center.X + 8, 3.8, signZ), Vector3.new(9.6, 2.2, 0.3), "SIGN_POND", Enum.NormalId.Front)
	-- Posąg Utopca na omszałym kamieniu z tyłu wyspy, twarzą do kładki
	local rockPos = center + Vector3.new(0, 0, lair.radius - 3)
	make("Part", {
		Name = "Pedestal",
		Size = Vector3.new(6, 2.2, 5),
		CFrame = CFrame.new(rockPos + Vector3.new(0, 1.3, 0)) * CFrame.Angles(0, math.rad(8), 0),
		Color = Color3.fromRGB(80, 92, 74),
		Material = Enum.Material.Slate,
		Parent = m,
	})
	m.Parent = parent
	local statuePos = rockPos + Vector3.new(0, 2.4, 0)
	return Utopiec.build(parent, CFrame.lookAt(statuePos, statuePos - Vector3.new(0, 0, 1)), false)
end

-- ===== Skorupa świata =====

local function buildShell(parent: Instance, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "Shell"
	local hw = Config.Swamp.halfWidth
	local zones = swampZones()
	local first, last = zones[1].zone, zones[#zones].zone
	for _, entry in zones do
		local zone = entry.zone
		local length = zone.endZ - zone.startZ
		make("Part", {
			Name = "Mud_" .. zone.id,
			Size = Vector3.new(hw * 2 + 40, 2, length),
			Position = Vector3.new(0, -1, zone.startZ + length / 2),
			Color = MUD[zone.id] or MUD.bog,
			Material = Enum.Material.Mud,
			Parent = folder,
		})
	end
	-- Ściana z martwych drzew i trzcin po bokach i na końcach (za nią niewidzialne ściany)
	for _, side in { -1, 1 } do
		local z = first.startZ
		while z < last.endZ do
			Props.deadTree(folder, Vector3.new(side * (hw - 2 + rng:NextNumber(-1.5, 1.5)), 0, z), rng:NextNumber(1.4, 1.9), rng, 0.6)
			reeds(folder, Vector3.new(side * (hw - 6), 0, z + 4), rng)
			z += rng:NextNumber(8, 12)
		end
	end
	for _, edgeZ in { first.startZ - 2, last.endZ + 2 } do
		local x = -hw
		while x < hw do
			Props.deadTree(folder, Vector3.new(x, 0, edgeZ), rng:NextNumber(1.4, 1.9), rng, 0.6)
			x += rng:NextNumber(8, 11)
		end
	end
	local totalLength = last.endZ - first.startZ
	local centerZ = first.startZ + totalLength / 2
	local function wall(size: Vector3, position: Vector3)
		local w = make("Part", { Name = "InvisibleWall", Size = size, Position = position, Transparency = 1, Parent = folder })
		w.CanQuery = false
	end
	for _, side in { -1, 1 } do
		wall(Vector3.new(2, 60, totalLength), Vector3.new(side * (hw + 1), 30, centerZ))
	end
	for _, z in { first.startZ - 1, last.endZ + 1 } do
		wall(Vector3.new(hw * 2, 60, 2), Vector3.new(0, 30, z))
	end
	folder.Parent = parent
end

local function buildZoneDecor(parent: Instance, zone: Config.ZoneDef, zoneIndex: number, rng: Random, api: Api)
	local recipe = RECIPES[zone.id]
	if not recipe then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Decor_" .. zone.id
	local hw = Config.Swamp.halfWidth - 8
	local z1, z2 = zone.startZ + 4, zone.endZ - 4

	for _, rect in poolRects(zone, zoneIndex) do
		waterSheet(folder, rect)
		for _ = 1, 4 do
			lilyPad(folder, rng:NextNumber(rect.x1 + 1, rect.x2 - 1), rng:NextNumber(rect.z1 + 1, rect.z2 - 1), rng)
		end
		reeds(folder, Vector3.new(rect.x1, 0, rect.z1), rng)
		reeds(folder, Vector3.new(rect.x2, 0, rect.z2), rng)
	end
	for _ = 1, recipe.willows do
		local scale = rng:NextNumber(0.9, 1.3)
		local x, z = api.place(rng, -hw, hw, z1, z2, 2.5 * scale)
		if x and z then
			willow(folder, Vector3.new(x, 0, z), rng, scale)
		end
	end
	for _ = 1, recipe.dead do
		local x, z = api.place(rng, -hw, hw, z1, z2, 2)
		if x and z then
			Props.deadTree(folder, Vector3.new(x, 0, z), rng:NextNumber(0.9, 1.4), rng, zone.darkness)
		end
	end
	for _ = 1, recipe.reeds do
		local x, z = api.place(rng, -hw, hw, z1, z2, 1.6)
		if x and z then
			reeds(folder, Vector3.new(x, 0, z), rng)
		end
	end
	for _ = 1, recipe.logs do
		local x, z = api.place(rng, -hw, hw, z1, z2, 2.5)
		if x and z then
			Props.log(folder, Vector3.new(x, 0, z), rng:NextNumber(0.9, 1.3), rng, zone.darkness)
		end
	end
	for _ = 1, recipe.wisps do
		wisp(folder, Vector3.new(rng:NextNumber(-hw, hw), rng:NextNumber(2.5, 5), rng:NextNumber(z1, z2)), rng)
	end
	folder.Parent = parent
end

-- Miejsca, gdzie nic nie może wyrosnąć: przystań, kładka, rozlewiska, staw Utopca
function Swamp.reservedRects(): { Rect }
	local rects: { Rect } = {}
	local half = Config.Swamp.boardwalkHalf + 1
	for _, entry in swampZones() do
		local zone = entry.zone
		if zone.safe then
			table.insert(rects, { x1 = -Config.Swamp.halfWidth, x2 = Config.Swamp.halfWidth, z1 = zone.startZ - 4, z2 = zone.endZ + 2 })
		else
			table.insert(rects, { x1 = -half, x2 = half, z1 = zone.startZ, z2 = zone.endZ })
			table.insert(rects, { x1 = -9.5, x2 = 9.5, z1 = zone.startZ - 2.5, z2 = zone.startZ + 2.5 })
			for _, rect in poolRects(zone, entry.index) do
				table.insert(rects, rect)
			end
		end
	end
	local lair = Config.UtopiecLair
	table.insert(rects, {
		x1 = lair.centerX - POND_RADIUS,
		x2 = lair.centerX + POND_RADIUS,
		z1 = lair.centerZ - POND_RADIUS - 4,
		z2 = lair.centerZ + POND_RADIUS,
	})
	return rects
end

-- Buduje bagna. Zwraca CFrame przystani (tu ląduje gracz) i posąg Utopca.
function Swamp.build(parent: Instance, rng: Random, api: Api): (CFrame, Model)
	local folder = Instance.new("Folder")
	folder.Name = "Swamp"
	buildShell(folder, rng)
	local zones = swampZones()
	for index, entry in zones do
		local zone = entry.zone
		if zone.safe then
			buildJetty(folder, zone)
		else
			if index > 1 then
				Props.gate(folder, zone.startZ, zone.key)
			end
			buildZoneDecor(folder, zone, entry.index, rng, api)
		end
	end
	-- Kładka od przystani do wyspy Utopca
	local lair = Config.UtopiecLair
	boardwalk(folder, zones[1].zone.endZ - 1, lair.centerZ - lair.radius + 1, rng)
	local statue = buildPond(folder, rng)
	folder.Parent = parent
	local camp = Config.Swamp.camp
	return CFrame.new(camp.x, DECK_Y + 3, camp.z) * CFrame.Angles(0, math.pi, 0), statue
end

return Swamp
