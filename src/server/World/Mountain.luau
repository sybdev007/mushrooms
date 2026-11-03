--!strict
-- Łysa Góra: czwarty świat, za portalem przy Stawie Utopca (od 10 000 000 monet).
-- Polana Zielarki (bezpieczna, z olejem i skupem) → Wiedźmi Las → Kotły Sabatu → Szczyt Łysej Góry.
-- Sabat czarownic w świetle pełni: krzywe czarne drzewa z kośćmi i amuletami, kotły z trującymi
-- oparami (Shared/Mountain.CAULDRONS), ogniska, miotły wbite w ziemię, krąg kamieni na szczycie
-- i chatka Baby Jagi na kurzej stopce (obraca ją klient, JagaHutView), za nią ogródek w płocie z kości.
-- Strefy leżą wzdłuż osi +Z (Config.Zones z world = "mountain"), daleko za bagnami.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
local MountainShared = require(ReplicatedStorage.Shared.Mountain)
local Palette = require(script.Parent.Palette)
local Props = require(script.Parent.Props)
local Jaga = require(script.Parent.Jaga)
local Backdrop = require(script.Parent.Backdrop)

local Mountain = {}

export type Api = {
	place: (rng: Random, x1: number, x2: number, z1: number, z2: number, radius: number) -> (number?, number?),
}
export type Rect = { x1: number, x2: number, z1: number, z2: number }

local TAU = math.pi * 2
local VERTICAL = CFrame.Angles(0, 0, math.rad(90))

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local GROUND: { [string]: Color3 } = {
	glade = rgb(58, 70, 44),
	witchwood = rgb(42, 38, 44),
	cauldrons = rgb(50, 44, 40),
	summit = rgb(78, 74, 82),
}
local GROUND_MATERIAL: { [string]: Enum.Material } = {
	glade = Enum.Material.Grass,
	witchwood = Enum.Material.Ground,
	cauldrons = Enum.Material.Ground,
	summit = Enum.Material.Slate,
}
local BARK = { rgb(34, 28, 34), rgb(44, 36, 42), rgb(30, 26, 30) }
local BONE = rgb(226, 218, 196)
local BONE_SHADE = rgb(190, 180, 156)
local SOCKET = rgb(24, 18, 22)
local CHARMS = { rgb(170, 90, 255), rgb(140, 255, 90), rgb(255, 120, 200) }
local STONE = { rgb(104, 100, 112), rgb(92, 88, 100), rgb(118, 112, 122) }
local POT = rgb(30, 28, 32)
local BREW = rgb(120, 230, 60)
local FIRE = rgb(255, 130, 40)
local STRAW = rgb(206, 170, 90)
local LEG = rgb(228, 168, 64)
local LEG_SHADE = rgb(196, 134, 46)
local CLAW = rgb(60, 52, 48)
local THATCH = rgb(96, 78, 52)
local GLOW_WINDOW = rgb(200, 255, 120)

-- Ile czego w strefie
type Recipe = {
	crooked: number, -- krzywe czarne drzewa (część z amuletami i kośćmi)
	pines: number, -- ciemne świerki
	rocks: number,
	stumps: number,
	bones: number,
	glow: number,
	tufts: number,
	brooms: number,
	bonfires: number,
}
local RECIPES: { [string]: Recipe } = {
	witchwood = { crooked = 20, pines = 10, rocks = 8, stumps = 5, bones = 6, glow = 6, tufts = 18, brooms = 3, bonfires = 0 },
	cauldrons = { crooked = 8, pines = 4, rocks = 6, stumps = 3, bones = 8, glow = 4, tufts = 10, brooms = 8, bonfires = 3 },
	summit = { crooked = 6, pines = 0, rocks = 14, stumps = 2, bones = 4, glow = 4, tufts = 6, brooms = 0, bonfires = 0 },
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

-- Walec od `from` do `to`
local function rod(parent: Instance, from: Vector3, to: Vector3, thickness: number, color: Color3, collide: boolean?): BasePart
	local p = make("Part", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new((to - from).Magnitude, thickness, thickness),
		CFrame = CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(0, math.rad(90), 0),
		Color = color,
		Parent = parent,
	})
	if not collide then
		decor(p)
	end
	return p
end

local function light(parent: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
end

local function mountainZones(): { { index: number, zone: Config.ZoneDef } }
	local list = {}
	for index, zone in Config.Zones do
		if zone.world == "mountain" then
			table.insert(list, { index = index, zone = zone })
		end
	end
	return list
end

-- ===== Elementy =====

-- Czaszka z ciemnymi oczodołami (na płocie, na gałęziach, na kupkach kości)
local function skull(parent: Instance, at: CFrame, size: number, eyes: Color3?)
	decor(make("Part", { Name = "Skull", Size = Vector3.new(1, 0.9, 1) * size, CFrame = at, Color = BONE, Parent = parent }))
	decor(make("Part", { Size = Vector3.new(0.7, 0.35, 0.6) * size, CFrame = at * CFrame.new(0, -0.5 * size, -0.15 * size), Color = BONE_SHADE, Parent = parent }))
	for _, side in { -1, 1 } do
		local eye = decor(make("Part", {
			Size = Vector3.new(0.26, 0.24, 0.06) * size,
			CFrame = at * CFrame.new(side * 0.22 * size, 0.04 * size, -0.51 * size),
			Color = eyes or SOCKET,
			Material = if eyes then Enum.Material.Neon else Enum.Material.SmoothPlastic,
			Parent = parent,
		}))
		if eyes then
			eye.Transparency = 0.25
		end
	end
end

-- Krzywe czarne drzewo: pień z kilku wygiętych odcinków, gołe gałęzie do góry,
-- a na niektórych gałęziach wiszą kości, czaszki albo świecące amulety
local function crookedTree(parent: Instance, base: Vector3, rng: Random, scale: number, charms: boolean)
	local m = Instance.new("Model")
	m.Name = "CrookedTree"
	local bark = pick(BARK, rng)
	local point = base
	local thickness = 1.5 * scale
	local direction = Vector3.new(rng:NextNumber(-0.4, 0.4), 1, rng:NextNumber(-0.4, 0.4)).Unit
	local tips: { Vector3 } = {}
	for segment = 1, 4 do
		local length = rng:NextNumber(3, 4.4) * scale
		local nextPoint = point + direction * length
		rod(m, point, nextPoint, thickness, bark, segment <= 2)
		-- Kolejny odcinek skręca w inną stronę (pień jak z bajki)
		direction = (direction + Vector3.new(rng:NextNumber(-0.7, 0.7), 0.3, rng:NextNumber(-0.7, 0.7))).Unit
		point = nextPoint
		thickness *= 0.78
		if segment >= 2 then
			for _ = 1, rng:NextInteger(1, 2) do
				local branchDir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.3, 0.9), rng:NextNumber(-1, 1)).Unit
				local tip = point + branchDir * rng:NextNumber(2.4, 4) * scale
				rod(m, point, tip, thickness * 0.55, bark)
				table.insert(tips, tip)
			end
		end
	end
	table.insert(tips, point)
	if charms then
		for i, tip in tips do
			if rng:NextNumber() < 0.55 then
				local hangLength = rng:NextNumber(0.8, 1.8)
				local bottom = tip - Vector3.new(0, hangLength, 0)
				rod(m, tip, bottom, 0.06, rgb(70, 60, 50))
				local kind = (i + rng:NextInteger(0, 2)) % 3
				if kind == 0 then
					skull(m, CFrame.new(bottom - Vector3.new(0, 0.35, 0)) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0), 0.6, nil)
				elseif kind == 1 then
					rod(m, bottom - Vector3.new(0.3, 0.1, 0), bottom + Vector3.new(0.3, -0.7, 0), 0.16, BONE)
				else
					decor(make("Part", {
						Name = "Charm",
						Shape = Enum.PartType.Cylinder,
						Size = Vector3.new(0.1, 0.6, 0.6),
						CFrame = CFrame.new(bottom - Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0),
						Color = pick(CHARMS, rng),
						Material = Enum.Material.Neon,
						Transparency = 0.35,
						Parent = m,
					}))
				end
			end
		end
	end
	m.Parent = parent
end

-- Kupka kości z czaszką
local function bonePile(parent: Instance, base: Vector3, rng: Random)
	local m = Instance.new("Model")
	m.Name = "Bones"
	for _ = 1, rng:NextInteger(3, 5) do
		local angle = rng:NextNumber(0, TAU)
		local offset = Vector3.new(rng:NextNumber(-0.8, 0.8), 0.12, rng:NextNumber(-0.8, 0.8))
		local half = Vector3.new(math.cos(angle), 0, math.sin(angle)) * rng:NextNumber(0.6, 1.1)
		rod(m, base + offset - half, base + offset + half, 0.22, BONE)
	end
	skull(m, CFrame.new(base + Vector3.new(0, 0.42, 0)) * CFrame.Angles(0, rng:NextNumber(0, TAU), math.rad(rng:NextNumber(-20, 20))), 0.8, nil)
	m.Parent = parent
end

-- Miotła wbita w ziemię kijem do góry albo słomą do góry
local function broom(parent: Instance, base: Vector3, rng: Random)
	local m = Instance.new("Model")
	m.Name = "Broom"
	local lean = CFrame.Angles(math.rad(rng:NextNumber(-14, 14)), rng:NextNumber(0, TAU), math.rad(rng:NextNumber(-14, 14)))
	local cf = CFrame.new(base) * lean
	rod(m, cf.Position, (cf * CFrame.new(0, 5.2, 0)).Position, 0.22, Palette.log)
	decor(make("Part", { Size = Vector3.new(1.1, 1.6, 0.9), CFrame = cf * CFrame.new(0, 5.6, 0), Color = STRAW, Material = Enum.Material.Fabric, Parent = m }))
	decor(make("Part", { Size = Vector3.new(0.7, 0.3, 0.6), CFrame = cf * CFrame.new(0, 4.9, 0), Color = rgb(150, 110, 60), Parent = m }))
	m.Parent = parent
end

-- Ognisko sabatu: stożek z polan, płomienie, kamienie dookoła (kruki się do niego nie zbliżają)
local function bonfire(parent: Instance, base: Vector3, rng: Random)
	local m = Instance.new("Model")
	m.Name = "Bonfire"
	for i = 1, 6 do
		local angle = i / 6 * TAU
		local foot = base + Vector3.new(math.cos(angle) * 1.6, 0.1, math.sin(angle) * 1.6)
		rod(m, foot, base + Vector3.new(0, 2.6, 0), 0.45, Palette.log)
	end
	for i = 1, 10 do
		local angle = i / 10 * TAU
		decor(make("Part", {
			Size = Vector3.new(0.9, 0.5, 0.7),
			CFrame = CFrame.new(base + Vector3.new(math.cos(angle) * 2.6, 0.2, math.sin(angle) * 2.6)) * CFrame.Angles(0, -angle, 0),
			Color = pick(STONE, rng),
			Material = Enum.Material.Slate,
			Parent = m,
		}))
	end
	local core = decor(make("Part", { Name = "Flame", Size = Vector3.new(1.2, 1.8, 1.2), CFrame = CFrame.new(base + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, math.rad(45), 0), Color = FIRE, Material = Enum.Material.Neon, Transparency = 0.2, Parent = m }))
	local fire = Instance.new("Fire")
	fire.Size = 6
	fire.Heat = 9
	fire.Color = FIRE
	fire.SecondaryColor = rgb(255, 60, 20)
	fire.Parent = core
	light(core, rgb(255, 150, 70), 16, 1)
	CollectionService:AddTag(core, "SabbathFire")
	m.Parent = parent
end

-- Kocioł sabatu na trzech nogach nad ogniem, z bulgoczącym zielonym wywarem i trującym dymem
local function cauldron(parent: Instance, spot: { x: number, z: number }, rng: Random)
	local m = Instance.new("Model")
	m.Name = "Cauldron"
	local base = Vector3.new(spot.x, 0, spot.z)
	for i = 1, 3 do
		local angle = i / 3 * TAU + 0.3
		local foot = base + Vector3.new(math.cos(angle) * 2.4, 0, math.sin(angle) * 2.4)
		rod(m, foot, base + Vector3.new(math.cos(angle) * 1.6, 2.4, math.sin(angle) * 1.6), 0.35, POT, true)
	end
	make("Part", { Name = "Pot", Shape = Enum.PartType.Ball, Size = Vector3.new(4.6, 4.6, 4.6), Position = base + Vector3.new(0, 3.6, 0), Color = POT, Material = Enum.Material.Metal, Parent = m })
	make("Part", { Name = "Rim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 4.2, 4.2), CFrame = CFrame.new(base + Vector3.new(0, 5.6, 0)) * VERTICAL, Color = rgb(44, 42, 46), Material = Enum.Material.Metal, Parent = m })
	local brew = decor(make("Part", {
		Name = "Brew",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.12, 3.7, 3.7),
		CFrame = CFrame.new(base + Vector3.new(0, 5.82, 0)) * VERTICAL,
		Color = BREW,
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		Parent = m,
	}))
	light(brew, rgb(140, 255, 90), 12, 0.7)
	-- Bąble i trujące opary (zasięg chmury to Config.Cauldrons.fumeRadius)
	local bubbles = Instance.new("ParticleEmitter")
	bubbles.Name = "Bubbles"
	bubbles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	bubbles.Color = ColorSequence.new(rgb(170, 255, 110))
	bubbles.LightEmission = 0.6
	bubbles.Size = NumberSequence.new(0.5, 0.1)
	bubbles.Lifetime = NumberRange.new(0.5, 1)
	bubbles.Rate = 8
	bubbles.Speed = NumberRange.new(1, 2.5)
	bubbles.SpreadAngle = Vector2.new(25, 25)
	bubbles.EmissionDirection = Enum.NormalId.Right -- oś walca (X) patrzy w górę
	bubbles.Parent = brew
	local fumes = Instance.new("ParticleEmitter")
	fumes.Name = "Fumes"
	fumes.Texture = "rbxasset://textures/particles/smoke_main.dds"
	fumes.Color = ColorSequence.new(rgb(110, 200, 60), rgb(60, 110, 40))
	fumes.LightInfluence = 0.7
	fumes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 9) })
	fumes.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.75), NumberSequenceKeypoint.new(0.5, 0.82), NumberSequenceKeypoint.new(1, 1) })
	fumes.Lifetime = NumberRange.new(5, 8)
	fumes.Rate = 3
	fumes.Speed = NumberRange.new(1, 2.2)
	fumes.SpreadAngle = Vector2.new(70, 70)
	fumes.Acceleration = Vector3.new(0, -0.3, 0)
	fumes.EmissionDirection = Enum.NormalId.Right
	fumes.Parent = brew
	-- Ogień pod kotłem
	local flame = decor(make("Part", { Name = "Flame", Size = Vector3.new(1.4, 1.2, 1.4), CFrame = CFrame.new(base + Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, math.rad(45), 0), Color = FIRE, Material = Enum.Material.Neon, Transparency = 0.25, Parent = m }))
	light(flame, rgb(255, 140, 60), 8, 0.6)
	for i = 1, 4 do
		local angle = i / 4 * TAU + rng:NextNumber(-0.2, 0.2)
		rod(m, base + Vector3.new(math.cos(angle) * 1.4, 0.2, math.sin(angle) * 1.4), base + Vector3.new(-math.cos(angle) * 1.4, 0.2, -math.sin(angle) * 1.4), 0.4, Palette.log)
	end
	m:SetAttribute("FumeRadius", Config.Cauldrons.fumeRadius)
	CollectionService:AddTag(m, "SabbathCauldron")
	m.Parent = parent
end

-- Stojący kamień (menhir) z kręgu na szczycie
local function menhir(parent: Instance, base: Vector3, rng: Random, facing: number)
	local height = rng:NextNumber(7, 10)
	make("Part", {
		Name = "Menhir",
		Size = Vector3.new(2.6, height, 1.8),
		CFrame = CFrame.new(base + Vector3.new(0, height / 2 - 0.4, 0)) * CFrame.Angles(math.rad(rng:NextNumber(-6, 6)), facing, math.rad(rng:NextNumber(-6, 6))),
		Color = pick(STONE, rng),
		Material = Enum.Material.Slate,
		Parent = parent,
	})
end

-- Latarnia ze skrzynką i czaszką przy ścieżce (fioletowe, przygaszone światło)
local function skullLantern(parent: Instance, base: Vector3)
	local m = Instance.new("Model")
	m.Name = "SkullLantern"
	make("Part", { Size = Vector3.new(0.5, 6, 0.5), Position = base + Vector3.new(0, 3, 0), Color = Palette.trunkDark, Parent = m })
	skull(m, CFrame.new(base + Vector3.new(0, 6.5, 0)), 1.1, rgb(190, 120, 255))
	local glow = decor(make("Part", { Size = Vector3.new(0.4, 0.4, 0.4), Position = base + Vector3.new(0, 6.5, 0), Transparency = 1, Parent = m }))
	light(glow, rgb(190, 130, 255), 14, 0.7)
	m.Parent = parent
end

-- Ścieżka z płaskich kamieni środkiem góry (od polany do chatki Baby Jagi)
local function stonePath(parent: Instance, fromZ: number, toZ: number, rng: Random)
	local m = Instance.new("Model")
	m.Name = "Path"
	local z = fromZ
	while z < toZ do
		local d = rng:NextNumber(2, 3)
		decor(make("Part", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, d, d * rng:NextNumber(0.8, 1)),
			CFrame = CFrame.new(rng:NextNumber(-0.8, 0.8), -0.04, z) * VERTICAL * CFrame.Angles(rng:NextNumber(0, TAU), 0, 0),
			Color = pick(STONE, rng):Lerp(GROUND.cauldrons, rng:NextNumber(0.2, 0.4)),
			Material = Enum.Material.Slate,
			Parent = m,
		}))
		z += rng:NextNumber(2.4, 3.2)
	end
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
			CFrame = CFrame.new(station.x + math.cos(angle) * station.radius, 0.03, station.z + math.sin(angle) * station.radius) * CFrame.Angles(0, -angle, 0),
			Color = color,
			Material = Enum.Material.Neon,
			Transparency = 0.3,
			Parent = parent,
		}))
	end
end

-- ===== Polana Zielarki (obóz) =====

-- Chatka zielarki: niska, z pęczkami ziół pod okapem
local function herbalistHut(parent: Instance, cf: CFrame)
	local m = Instance.new("Model")
	m.Name = "HerbalistHut"
	make("Part", { Name = "Walls", Size = Vector3.new(11, 7, 9), CFrame = cf * CFrame.new(0, 3.5, 0), Color = Palette.log, Material = Enum.Material.Wood, Parent = m })
	for _, side in { -1, 1 } do
		make("WedgePart", { Name = "Roof", Size = Vector3.new(12.4, 3.6, 5.6), CFrame = cf * CFrame.new(0, 8.8, side * 2.8) * CFrame.Angles(0, if side > 0 then 0 else math.pi, 0), Color = THATCH, Material = Enum.Material.Fabric, Parent = m })
	end
	make("Part", { Name = "Door", Size = Vector3.new(2.4, 4.6, 0.3), CFrame = cf * CFrame.new(0, 2.3, -4.55), Color = Palette.plankDark, Parent = m })
	local window = decor(make("Part", { Name = "Window", Size = Vector3.new(1.8, 1.6, 0.2), CFrame = cf * CFrame.new(3.4, 4.2, -4.55), Color = Palette.windowGlow, Material = Enum.Material.Neon, Transparency = 0.2, Parent = m }))
	light(window, Palette.lanternGlow, 12, 0.6)
	-- Pęczki ziół pod okapem
	for i = -4, 4, 2 do
		local herb = cf * CFrame.new(i, 6.4, -5.2)
		rod(m, herb.Position, (herb * CFrame.new(0, -0.6, 0)).Position, 0.06, rgb(80, 60, 40))
		decor(make("Part", { Size = Vector3.new(0.6, 1.1, 0.6), CFrame = herb * CFrame.new(0, -1.2, 0), Color = if i % 4 == 0 then rgb(96, 140, 70) else rgb(150, 120, 170), Material = Enum.Material.Grass, Parent = m }))
	end
	make("Part", { Name = "Chimney", Size = Vector3.new(1.6, 4, 1.6), CFrame = cf * CFrame.new(-3.6, 10, 1.6), Color = Palette.stoneChimney, Material = Enum.Material.Cobblestone, Parent = m })
	m.Parent = parent
end

local function buildGlade(parent: Instance, zone: Config.ZoneDef, rng: Random)
	local m = Instance.new("Model")
	m.Name = "HerbalistGlade"
	local function facingCentre(station: Config.StationDef): CFrame
		return CFrame.lookAt(Vector3.new(station.x, 0, station.z), Vector3.new(0, 0, station.z))
	end

	-- Olej: beczki z wiedźmim znakiem
	local oil = Economy.station("oil", "mountain")
	stationRing(m, oil, rgb(255, 186, 80))
	local oilCf = facingCentre(oil)
	for i, offset in { Vector3.new(-2.6, 0, 4.4), Vector3.new(0, 0, 4.8), Vector3.new(2.6, 0, 4.4) } do
		make("Part", {
			Name = "OilBarrel",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2.8, 2.2, 2.2),
			CFrame = oilCf * CFrame.new(offset + Vector3.new(0, 1.4, 0)) * VERTICAL * CFrame.Angles(i * 0.5, 0, 0),
			Color = rgb(84, 62, 46),
			Parent = m,
		})
	end
	for _, side in { -1, 1 } do
		make("Part", { Size = Vector3.new(0.4, 6.4, 0.4), CFrame = oilCf * CFrame.new(side * 3.4, 3.2, 3.6), Color = Palette.plankDark, Parent = m })
	end
	Props.signBoard(m, oilCf * CFrame.new(0, 6.6, 3.2), Vector3.new(7, 1.5, 0.3), "SIGN_OIL", Enum.NormalId.Front)
	Props.hangingLantern(m, (oilCf * CFrame.new(3.4, 6.2, 2.6)).Position, 16)

	-- Skup: kramik zielarki ze słojami i fioletowo-zielonym daszkiem
	local shop = Economy.station("shop", "mountain")
	stationRing(m, shop, rgb(170, 120, 255))
	local shopCf = facingCentre(shop)
	make("Part", { Name = "Counter", Size = Vector3.new(8, 3, 2), CFrame = shopCf * CFrame.new(0, 1.5, 5), Color = Palette.plankDark, Parent = m })
	make("Part", { Size = Vector3.new(8.6, 0.4, 2.4), CFrame = shopCf * CFrame.new(0, 3.2, 5), Color = Palette.plank, Parent = m })
	for i, x in { -3, -1.6, 0.2, 1.8, 3.2 } do
		decor(make("Part", {
			Name = "Jar",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.9 + (i % 2) * 0.3, 0.7, 0.7),
			CFrame = shopCf * CFrame.new(x, 3.85 + (i % 2) * 0.15, 5) * VERTICAL,
			Color = pick(CHARMS, rng),
			Material = Enum.Material.Glass,
			Transparency = 0.3,
			Parent = m,
		}))
	end
	for _, side in { -1, 1 } do
		make("Part", { Size = Vector3.new(0.5, 7.4, 0.5), CFrame = shopCf * CFrame.new(side * 4.2, 3.7, 4.2), Color = Palette.log, Parent = m })
		make("Part", { Size = Vector3.new(0.5, 7.4, 0.5), CFrame = shopCf * CFrame.new(side * 4.2, 3.7, 7.6), Color = Palette.log, Parent = m })
	end
	for i = 0, 5 do
		make("Part", {
			Size = Vector3.new(1.6, 0.3, 4.6),
			CFrame = shopCf * CFrame.new(-4 + i * 1.6, 7.6, 5.8) * CFrame.Angles(math.rad(14), 0, 0),
			Color = if i % 2 == 0 then rgb(100, 60, 140) else rgb(90, 140, 70),
			Material = Enum.Material.Fabric,
			Parent = m,
		})
	end
	Props.signBoard(m, shopCf * CFrame.new(0, 6.2, 3.95), Vector3.new(6.8, 1.4, 0.3), "SIGN_SHOP", Enum.NormalId.Front)
	Props.hangingLantern(m, (shopCf * CFrame.new(0, 7.2, 4.4)).Position, 18)

	-- Chatka zielarki i ognisko na środku polany
	local hw = Config.Mountain.halfWidth
	herbalistHut(m, CFrame.new(-hw + 14, 0, zone.startZ + 22) * CFrame.Angles(0, math.rad(70), 0))
	herbalistHut(m, CFrame.new(hw - 14, 0, zone.startZ + 24) * CFrame.Angles(0, math.rad(-70), 0))
	bonfire(m, Vector3.new(-8, 0, zone.startZ + 34), rng)
	for _, x in { -6, 6 } do
		Props.lanternPost(m, Vector3.new(x, 0, zone.endZ - 3), if x > 0 then math.pi else 0)
	end
	m.Parent = parent
end

-- ===== Chatka Baby Jagi na kurzej stopce =====

-- Buduje chatkę (drzwiami do -Z) z pivotem w osi nogi. Klient obraca ją według Shared/Mountain.hutYaw.
local function buildHut(parent: Instance, center: Vector3): Model
	local m = Instance.new("Model")
	m.Name = "JagaHut"
	local pivot = decor(make("Part", { Name = "Pivot", Size = Vector3.new(1, 1, 1), Position = center, Transparency = 1, Parent = m }))
	m.PrimaryPart = pivot

	-- Kurza stopa: trzy palce do przodu, jeden do tyłu, pazury; łuskowata goleń do kolana i udo do domku
	local foot = center + Vector3.new(0, 0.5, 0)
	for _, angle in { -32, 0, 32 } do
		local dir = (CFrame.Angles(0, math.rad(angle), 0) * Vector3.new(0, 0, -1))
		local tip = foot + dir * 4.2
		rod(m, foot, tip, 0.9, LEG)
		decor(make("WedgePart", { Name = "Claw", Size = Vector3.new(0.6, 0.7, 1.0), CFrame = CFrame.lookAt(tip + dir * 0.45 - Vector3.new(0, 0.2, 0), tip + dir * 2), Color = CLAW, Parent = m }))
	end
	rod(m, foot, foot + Vector3.new(0, 0.3, 2.6), 0.8, LEG)
	decor(make("WedgePart", { Name = "Claw", Size = Vector3.new(0.55, 0.6, 0.9), CFrame = CFrame.lookAt(foot + Vector3.new(0, 0.1, 3.0), foot + Vector3.new(0, 0, 6)), Color = CLAW, Parent = m }))
	local knee = center + Vector3.new(0, 4.6, 1.4)
	rod(m, foot, knee, 1.4, LEG)
	for i = 1, 6 do
		-- Łuski na goleni
		local p = foot:Lerp(knee, i / 7)
		decor(make("Part", { Size = Vector3.new(1.5, 0.18, 1.5), CFrame = CFrame.lookAt(p, knee) * CFrame.Angles(math.rad(90), 0, 0), Color = LEG_SHADE, Parent = m }))
	end
	local hip = center + Vector3.new(0, 8.2, 0)
	rod(m, knee, hip, 2.4, rgb(150, 110, 90))
	-- Pióra na udzie
	for i = 1, 5 do
		local angle = i / 5 * TAU
		decor(make("WedgePart", {
			Size = Vector3.new(0.6, 1.6, 1),
			CFrame = CFrame.new(hip + Vector3.new(math.cos(angle) * 1.4, -1.4, math.sin(angle) * 1.4)) * CFrame.Angles(0, -angle, math.rad(180)),
			Color = rgb(200, 190, 170),
			Parent = m,
		}))
	end

	-- Domek z bali: podłoga na wysokości 8,5
	local floor = 8.5
	local houseCf = CFrame.new(center + Vector3.new(0, floor, 0))
	decor(make("Part", { Name = "Floor", Size = Vector3.new(10, 0.6, 10), CFrame = houseCf, Color = Palette.plankDark, Parent = m }))
	for row = 0, 6 do
		local y = 0.8 + row * 1.0
		for _, side in { -1, 1 } do
			decor(make("Part", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(10.4, 1.0, 1.0), CFrame = houseCf * CFrame.new(0, y, side * 4.6), Color = if row % 2 == 0 then Palette.log else Palette.trunk, Parent = m }))
			decor(make("Part", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(10.4, 1.0, 1.0), CFrame = houseCf * CFrame.new(side * 4.6, y, 0) * CFrame.Angles(0, math.rad(90), 0), Color = if row % 2 == 1 then Palette.log else Palette.trunk, Parent = m }))
		end
	end
	-- Dach ze strzechy z mchem i kominem
	for _, side in { -1, 1 } do
		decor(make("WedgePart", { Name = "Roof", Size = Vector3.new(11.6, 4.4, 6), CFrame = houseCf * CFrame.new(0, 9.9, side * 3) * CFrame.Angles(0, if side > 0 then 0 else math.pi, 0), Color = THATCH, Material = Enum.Material.Fabric, Parent = m }))
	end
	decor(make("Part", { Size = Vector3.new(11.8, 0.5, 0.8), CFrame = houseCf * CFrame.new(0, 12.15, 0), Color = rgb(70, 96, 52), Material = Enum.Material.Grass, Parent = m }))
	local chimney = decor(make("Part", { Name = "Chimney", Size = Vector3.new(1.6, 4, 1.6), CFrame = houseCf * CFrame.new(3, 11.8, 2), Color = Palette.stoneChimney, Material = Enum.Material.Cobblestone, Parent = m }))
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(rgb(120, 200, 90), rgb(80, 70, 90))
	smoke.LightInfluence = 0.7
	smoke.Size = NumberSequence.new(1.2, 4)
	smoke.Transparency = NumberSequence.new(0.5, 1)
	smoke.Lifetime = NumberRange.new(3, 5)
	smoke.Rate = 4
	smoke.Speed = NumberRange.new(2, 3)
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.Parent = chimney
	-- Drzwi z czaszką nad nimi (przód = -Z) i okna świecące na zielono
	decor(make("Part", { Name = "Door", Size = Vector3.new(2.6, 4.4, 0.3), CFrame = houseCf * CFrame.new(0, 2.5, -5.15), Color = Palette.plankDark, Parent = m }))
	decor(make("Part", { Size = Vector3.new(3.2, 0.4, 0.4), CFrame = houseCf * CFrame.new(0, 4.9, -5.2), Color = Palette.trunkDark, Parent = m }))
	skull(m, houseCf * CFrame.new(0, 5.6, -5.3), 1, GLOW_WINDOW)
	for _, x in { -3, 3 } do
		local window = decor(make("Part", { Name = "HutWindow", Size = Vector3.new(1.8, 1.6, 0.2), CFrame = houseCf * CFrame.new(x, 3.4, -5.12), Color = GLOW_WINDOW, Material = Enum.Material.Neon, Transparency = 0.25, Parent = m }))
		decor(make("Part", { Size = Vector3.new(0.18, 1.6, 0.24), CFrame = houseCf * CFrame.new(x, 3.4, -5.14), Color = Palette.trunkDark, Parent = m }))
		window:SetAttribute("WatchGlow", true)
	end
	local glow = decor(make("Part", { Name = "DoorGlow", Size = Vector3.new(0.4, 0.4, 0.4), CFrame = houseCf * CFrame.new(0, 3.4, -6.4), Transparency = 1, Parent = m }))
	light(glow, GLOW_WINDOW, 18, 0.8)
	-- Wiązka promienia z drzwi: widać, gdzie chatka patrzy (klient rozjaśnia, gdy patrzy na ogródek)
	local beam = decor(make("Part", {
		Name = "WatchBeam",
		Size = Vector3.new(7, 0.06, 18),
		CFrame = CFrame.new(center + Vector3.new(0, 0.08, -9)),
		Color = GLOW_WINDOW,
		Material = Enum.Material.Neon,
		Transparency = 0.86,
		Parent = m,
	}))
	beam:SetAttribute("WatchGlow", true)

	m:SetAttribute("Center", center)
	CollectionService:AddTag(m, "JagaHut")
	m.Parent = parent
	return m
end

-- Płot z kości wokół ogródka (czaszki z zielonymi oczami na co drugim palu) i grządki
local function buildGarden(parent: Instance, rng: Random)
	local lair = Config.JagaLair
	local center = Vector3.new(lair.centerX, 0, lair.centerZ)
	local m = Instance.new("Model")
	m.Name = "JagaGarden"
	-- Grządki z ciemnej ziemi
	for row = -1, 1 do
		decor(make("Part", { Size = Vector3.new(lair.radius * 1.3, 0.25, 2.4), CFrame = CFrame.new(center + Vector3.new(0, 0.1, row * 4.2)), Color = rgb(52, 36, 30), Material = Enum.Material.Ground, Parent = m }))
	end
	-- Płot: przerwy po bokach i od strony chatki (wejścia do ogródka)
	local posts = 40
	for i = 1, posts do
		local angle = i / posts * TAU
		local dir = Vector3.new(math.sin(angle), 0, math.cos(angle))
		local gap = math.abs(dir.X) > 0.94 or dir.Z < -0.96
		if not gap then
			local at = center + dir * lair.radius
			local height = rng:NextNumber(3.2, 4.2)
			make("Part", { Name = "FencePost", Shape = Enum.PartType.Cylinder, Size = Vector3.new(height, 0.5, 0.5), CFrame = CFrame.new(at + Vector3.new(0, height / 2, 0)) * VERTICAL, Color = BONE, Parent = m })
			if i % 2 == 0 then
				skull(m, CFrame.lookAt(at + Vector3.new(0, height + 0.45, 0), center + Vector3.new(0, height + 0.45, -1000)), 0.9, if i % 4 == 0 then rgb(150, 255, 90) else nil)
			end
		end
	end
	m.Parent = parent
end

-- ===== Skorupa świata =====

local function buildShell(parent: Instance, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "Shell"
	local hw = Config.Mountain.halfWidth
	local zones = mountainZones()
	local first, last = zones[1].zone, zones[#zones].zone
	for _, entry in zones do
		local zone = entry.zone
		local length = zone.endZ - zone.startZ
		make("Part", {
			Name = "Ground_" .. zone.id,
			Size = Vector3.new(hw * 2 + 40, 2, length),
			Position = Vector3.new(0, -1, zone.startZ + length / 2),
			Color = GROUND[zone.id] or GROUND.witchwood,
			Material = GROUND_MATERIAL[zone.id] or Enum.Material.Ground,
			Parent = folder,
		})
	end
	-- Ściana z krzywych drzew i skał po bokach i na końcach (za nią niewidzialne ściany)
	for _, side in { -1, 1 } do
		local z = first.startZ
		while z < last.endZ do
			if rng:NextNumber() < 0.7 then
				crookedTree(folder, Vector3.new(side * (hw - 2 + rng:NextNumber(-1.5, 1.5)), 0, z), rng, rng:NextNumber(1.3, 1.8), false)
			else
				Props.rock(folder, Vector3.new(side * (hw - 3), 0, z), rng:NextNumber(1.4, 2), rng, 0.6)
			end
			z += rng:NextNumber(7, 11)
		end
	end
	for _, edgeZ in { first.startZ - 2, last.endZ + 2 } do
		local x = -hw
		while x < hw do
			crookedTree(folder, Vector3.new(x, 0, edgeZ), rng, rng:NextNumber(1.3, 1.8), false)
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

local function buildZoneDecor(parent: Instance, zone: Config.ZoneDef, rng: Random, api: Api)
	local recipe = RECIPES[zone.id]
	if not recipe then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Decor_" .. zone.id
	local hw = Config.Mountain.halfWidth - 8
	local z1, z2 = zone.startZ + 4, zone.endZ - 4
	-- Na szczycie dekoracje nie wchodzą na krąg kamieni ani do ogródka
	if zone.id == "summit" then
		z2 = Config.JagaLair.hutZ - 12
	end

	if zone.id == "cauldrons" then
		for _, spot in MountainShared.CAULDRONS do
			cauldron(folder, spot, rng)
		end
	end
	for _ = 1, recipe.bonfires do
		local x, z = api.place(rng, -hw, hw, z1, z2, 4)
		if x and z then
			bonfire(folder, Vector3.new(x, 0, z), rng)
		end
	end
	for i = 1, recipe.crooked do
		local scale = rng:NextNumber(0.9, 1.3)
		local x, z = api.place(rng, -hw, hw, z1, z2, 2.4 * scale)
		if x and z then
			crookedTree(folder, Vector3.new(x, 0, z), rng, scale, i % 2 == 0)
		end
	end
	for _ = 1, recipe.pines do
		local x, z = api.place(rng, -hw, hw, z1, z2, 2.4)
		if x and z then
			Props.pine(folder, Vector3.new(x, 0, z), rng:NextNumber(1, 1.4), rng, 0.85)
		end
	end
	for _ = 1, recipe.rocks do
		local x, z = api.place(rng, -hw, hw, z1, z2, 2.5)
		if x and z then
			Props.rock(folder, Vector3.new(x, 0, z), rng:NextNumber(0.8, 1.4), rng, zone.darkness * 0.6)
		end
	end
	for _ = 1, recipe.stumps do
		local x, z = api.place(rng, -hw, hw, z1, z2, 1.8)
		if x and z then
			Props.stump(folder, Vector3.new(x, 0, z), rng:NextNumber(0.8, 1.2), rng, zone.darkness * 0.6)
		end
	end
	for _ = 1, recipe.bones do
		local x, z = api.place(rng, -hw, hw, z1, z2, 1.6)
		if x and z then
			bonePile(folder, Vector3.new(x, 0, z), rng)
		end
	end
	for _ = 1, recipe.brooms do
		local x, z = api.place(rng, -hw, hw, z1, z2, 1.2)
		if x and z then
			broom(folder, Vector3.new(x, 0, z), rng)
		end
	end
	for _ = 1, recipe.glow do
		local x, z = api.place(rng, -hw, hw, z1, z2, 1.6)
		if x and z then
			Props.glowCluster(folder, Vector3.new(x, 0, z), rng)
		end
	end
	for _ = 1, recipe.tufts do
		local x, z = api.place(rng, -hw, hw, z1, z2, 0.8)
		if x and z then
			Props.grass(folder, Vector3.new(x, 0, z), rng:NextNumber(0.9, 1.3), rng, 0.7)
		end
	end
	folder.Parent = parent
end

-- Krąg kamieni na szczycie (ścieżka przechodzi przez środek), z ołtarzem z runą
local STONE_CIRCLE = { z = 3352, radius = 13 }
local function buildStoneCircle(parent: Instance, rng: Random)
	local m = Instance.new("Model")
	m.Name = "StoneCircle"
	local center = Vector3.new(0, 0, STONE_CIRCLE.z)
	for i = 1, 10 do
		local angle = (i - 0.5) / 10 * TAU
		local dir = Vector3.new(math.sin(angle), 0, math.cos(angle))
		-- Bez kamieni na ścieżce (przód i tył kręgu)
		if math.abs(dir.X) > 0.3 then
			menhir(m, center + dir * STONE_CIRCLE.radius, rng, -angle)
		end
	end
	make("Part", { Name = "Altar", Size = Vector3.new(4, 1.6, 2.6), Position = center + Vector3.new(7, 0.8, 0), Color = pick(STONE, rng), Material = Enum.Material.Slate, Parent = m })
	local rune = decor(make("Part", { Name = "Rune", Size = Vector3.new(2.2, 0.06, 1.4), Position = center + Vector3.new(7, 1.63, 0), Color = rgb(190, 110, 255), Material = Enum.Material.Neon, Transparency = 0.35, Parent = m }))
	light(rune, rgb(190, 120, 255), 12, 0.6)
	m.Parent = parent
end

-- Miejsca, gdzie nic nie może wyrosnąć: polana, ścieżka, kotły, krąg kamieni, chatka i ogródek
function Mountain.reservedRects(): { Rect }
	local rects: { Rect } = {}
	local half = Config.Mountain.path + 1
	for _, entry in mountainZones() do
		local zone = entry.zone
		if zone.safe then
			table.insert(rects, { x1 = -Config.Mountain.halfWidth, x2 = Config.Mountain.halfWidth, z1 = zone.startZ - 4, z2 = zone.endZ + 2 })
		else
			table.insert(rects, { x1 = -half, x2 = half, z1 = zone.startZ, z2 = zone.endZ })
			table.insert(rects, { x1 = -9.5, x2 = 9.5, z1 = zone.startZ - 2.5, z2 = zone.startZ + 2.5 })
		end
	end
	for _, spot in MountainShared.CAULDRONS do
		table.insert(rects, { x1 = spot.x - 4, x2 = spot.x + 4, z1 = spot.z - 4, z2 = spot.z + 4 })
	end
	table.insert(rects, { x1 = -STONE_CIRCLE.radius - 2, x2 = STONE_CIRCLE.radius + 2, z1 = STONE_CIRCLE.z - STONE_CIRCLE.radius - 2, z2 = STONE_CIRCLE.z + STONE_CIRCLE.radius + 2 })
	local lair = Config.JagaLair
	table.insert(rects, { x1 = lair.centerX - lair.radius - 2, x2 = lair.centerX + lair.radius + 2, z1 = lair.hutZ - 8, z2 = lair.centerZ + lair.radius + 2 })
	return rects
end

-- ===== Tło za ścianami =====

local MOUNTAIN_HILLS = { rgb(34, 28, 40), rgb(40, 32, 46), rgb(30, 26, 36) }
local MOUNTAIN_PEAKS = { rgb(48, 42, 58), rgb(40, 36, 52), rgb(56, 48, 64) }

local function buildBackdrop(parent: Instance, rng: Random)
	local hw = Config.Mountain.halfWidth
	local zones = mountainZones()
	local first, last = zones[1].zone, zones[#zones].zone
	Backdrop.build(parent, { x1 = -hw - 1, x2 = hw + 1, z1 = first.startZ - 3, z2 = last.endZ + 3 }, {
		name = "Mountain",
		ground = rgb(36, 32, 40),
		near = function(folder: Instance, base: Vector3, treeRng: Random)
			if treeRng:NextNumber() < 0.6 then
				crookedTree(folder, base, treeRng, treeRng:NextNumber(1.5, 2), false)
			else
				Props.pine(folder, base, treeRng:NextNumber(1.4, 1.9), treeRng, 0.95)
			end
		end,
		nearSpacing = 10,
		far = function(folder: Instance, base: Vector3, treeRng: Random)
			-- Sylwetka świerka
			local s = treeRng:NextNumber(1.8, 2.6)
			Backdrop.cone(folder, base + Vector3.new(0, 4 * s, 0), 7 * s, 12 * s, treeRng:NextNumber(0, TAU), rgb(22, 26, 28))
		end,
		farSpacing = 10,
		hill = MOUNTAIN_HILLS,
		hillHeight = { 30, 52 },
		mountain = MOUNTAIN_PEAKS,
		mountainHeight = { 80, 130 },
	}, rng)
end

-- Buduje Łysą Górę. Zwraca CFrame polany (tu ląduje gracz) i Babę Jagę drzemiącą przy chatce.
function Mountain.build(parent: Instance, rng: Random, api: Api): (CFrame, Model)
	local folder = Instance.new("Folder")
	folder.Name = "Mountain"
	buildShell(folder, rng)
	local zones = mountainZones()
	for index, entry in zones do
		local zone = entry.zone
		if zone.safe then
			buildGlade(folder, zone, rng)
		else
			if index > 1 then
				Props.gate(folder, zone.startZ, zone.key)
			end
			buildZoneDecor(folder, zone, rng, api)
		end
	end
	local lair = Config.JagaLair
	stonePath(folder, zones[1].zone.endZ - 1, lair.hutZ - 6, rng)
	-- Latarnie z czaszkami przy ścieżce, na zmianę po obu stronach (z dala od bram stref)
	local side = 1
	for z = zones[1].zone.endZ + 20, lair.hutZ - 20, 36 do
		local nearGate = false
		for _, entry in zones do
			if math.abs(entry.zone.startZ - z) < 6 then
				nearGate = true
			end
		end
		if not nearGate then
			skullLantern(folder, Vector3.new(side * (Config.Mountain.path + 1.4), 0, z))
			side = -side
		end
	end
	buildStoneCircle(folder, rng)
	buildHut(folder, Vector3.new(lair.centerX, 0, lair.hutZ))
	buildGarden(folder, rng)
	-- Tabliczka ostrzegawcza przed chatką
	local signZ = lair.hutZ - 14
	for _, s in { -1, 1 } do
		make("Part", { Size = Vector3.new(0.4, 4.6, 0.4), Position = Vector3.new(9 + s * 4.2, 2.3, signZ + 0.4), Color = Palette.log, Parent = folder })
	end
	Props.signBoard(folder, CFrame.new(9, 3.8, signZ), Vector3.new(9.6, 2.2, 0.3), "SIGN_HUT", Enum.NormalId.Front)
	buildBackdrop(folder, rng)
	folder.Parent = parent
	-- Baba Jaga drzemie w moździerzu obok chatki (posąg; budzi się, kiedy ktoś ukradnie jej Ziele)
	local statue = Jaga.build(parent, CFrame.lookAt(Vector3.new(lair.centerX + 9, 0, lair.hutZ - 3), Vector3.new(lair.centerX + 9, 0, lair.hutZ - 20)), false)
	statue.Name = "JagaStatue"
	local camp = Config.Mountain.camp
	return CFrame.new(camp.x, 3, camp.z) * CFrame.Angles(0, math.pi, 0), statue
end

-- Skąd wylatuje Baba Jaga w pościgu: spod drzwi chatki
function Mountain.jagaOrigin(): Vector3
	local lair = Config.JagaLair
	return Vector3.new(lair.centerX, 0, lair.hutZ - 6)
end

return Mountain
