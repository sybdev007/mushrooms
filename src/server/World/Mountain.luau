--!strict
-- Łysa Góra: czwarty świat, za portalem przy Stawie Utopca (od 10 000 000 monet).
-- Polana Zielarki (bezpieczna, z olejem i skupem) → Wiedźmi Las → Kotły Sabatu → Szczyt Łysej Góry.
-- Prawdziwa góra: ziemia z trójkątów (Shared/MountainTerrain) wznosi się od polany u stóp góry,
-- kamienna ścieżka wije się serpentynami w górę, krąg kamieni stoi na wyrównanym placu, a chatka
-- Baby Jagi na kurzej stopce na płaskim szczycie (obraca ją klient, JagaHutView). Z jednej strony
-- skalny grzbiet, z drugiej urwisko nad doliną z lasem, rzeką i światłami wioski, a za szczytem
-- góra opada w morze chmur. Sabat w świetle pełni: krzywe czarne drzewa z kośćmi i amuletami,
-- kotły z trującymi oparami (Shared/Mountain.CAULDRONS), zielony ogień sabatu, miotły w ziemi.
-- Strefy leżą wzdłuż osi +Z (Config.Zones z world = "mountain"), daleko za bagnami.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
local MountainShared = require(ReplicatedStorage.Shared.Mountain)
local Terrain = require(ReplicatedStorage.Shared.MountainTerrain)
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

-- Jaśniejsze niż w innych światach: noc na Łysej Górze jest księżycowa (zbocza mają być widać)
local GROUND: { [string]: Color3 } = {
	glade = rgb(58, 70, 44),
	witchwood = rgb(66, 58, 74),
	cauldrons = rgb(76, 66, 62),
	summit = rgb(106, 100, 114),
}
local GROUND_MATERIAL: { [string]: Enum.Material } = {
	glade = Enum.Material.Grass,
	witchwood = Enum.Material.Ground,
	cauldrons = Enum.Material.Ground,
	summit = Enum.Material.Slate,
}
local ROCK = { rgb(98, 92, 108), rgb(86, 82, 98), rgb(108, 102, 116) }
local VALLEY = rgb(30, 38, 34)
local VALLEY_TREES = { rgb(26, 40, 38), rgb(30, 46, 42), rgb(22, 34, 34), rgb(34, 44, 52) }
local CLOUDS = { rgb(58, 48, 86), rgb(66, 56, 96), rgb(52, 44, 80) } -- neon: chmury świecą księżycem
local PEAKS = { rgb(54, 46, 66), rgb(46, 40, 58), rgb(60, 52, 72) }
local PEAK_TOP = rgb(128, 118, 150)
local RIVER = rgb(34, 52, 92)
local VILLAGE_WINDOW = rgb(255, 186, 104)
local BARK = { rgb(34, 28, 34), rgb(44, 36, 42), rgb(30, 26, 30) }
local BONE = rgb(226, 218, 196)
local BONE_SHADE = rgb(190, 180, 156)
local SOCKET = rgb(24, 18, 22)
local CHARMS = { rgb(170, 90, 255), rgb(140, 255, 90), rgb(255, 120, 200) }
local STONE = { rgb(104, 100, 112), rgb(92, 88, 100), rgb(118, 112, 122) }
local POT = rgb(30, 28, 32)
local BREW = rgb(120, 230, 60)
local FIRE = rgb(255, 130, 40)
local GREEN_FIRE = rgb(120, 255, 90)
local GREEN_FIRE_EDGE = rgb(30, 150, 60)
local STRAW = rgb(206, 170, 90)
local LEG = rgb(228, 168, 64)
local LEG_SHADE = rgb(196, 134, 46)
local CLAW = rgb(60, 52, 48)
local THATCH = rgb(96, 78, 52)
local GLOW_WINDOW = rgb(130, 220, 70)

local TERRAIN_THICKNESS = 3

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
}
local RECIPES: { [string]: Recipe } = {
	witchwood = { crooked = 22, pines = 10, rocks = 9, stumps = 5, bones = 6, glow = 6, tufts = 18, brooms = 3 },
	cauldrons = { crooked = 8, pines = 4, rocks = 7, stumps = 3, bones = 8, glow = 4, tufts = 10, brooms = 8 },
	summit = { crooked = 6, pines = 0, rocks = 16, stumps = 2, bones = 4, glow = 4, tufts = 6, brooms = 0 },
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

-- Punkt na ziemi góry
local function groundAt(x: number, z: number): Vector3
	return Vector3.new(x, Terrain.groundY(x, z), z)
end

-- Układ przechylony jak zbocze w danym miejscu (oś Y wzdłuż normalnej ziemi), obrócony o yaw
local function slopeFrame(position: Vector3, yaw: number): CFrame
	local nx, ny, nz = Terrain.normal(position.X, position.Z)
	local up = Vector3.new(nx, ny, nz)
	local look = CFrame.Angles(0, yaw, 0).LookVector
	local back = -(look - up * look:Dot(up)).Unit
	return CFrame.fromMatrix(position, up:Cross(back), up, back)
end

-- Podstawa rzeczy stojącej na zboczu: trochę w ziemi, żeby od strony spadku nie wisiała w powietrzu
local function footing(x: number, z: number, radius: number): Vector3
	return groundAt(x, z) - Vector3.new(0, 0.3 + Terrain.slope(x, z) * radius, 0)
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

-- Ognisko: stożek z polan, płomienie, kamienie dookoła (kruki się do niego nie zbliżają).
-- Ognisko zielarki na polanie pali się ciepło; ogniska sabatu zielonym ogniem, z iskrami,
-- a wielkie ognisko w kręgu kamieni jest dwa razy większe.
type FireKind = "warm" | "sabbath" | "great"
local function bonfire(parent: Instance, base: Vector3, rng: Random, kind: FireKind)
	local m = Instance.new("Model")
	m.Name = if kind == "warm" then "Bonfire" else "SabbathFire"
	local s = if kind == "great" then 1.7 else 1
	local green = kind ~= "warm"
	local function ground(offset: Vector3): Vector3
		local p = base + offset
		return if green then Vector3.new(p.X, Terrain.groundY(p.X, p.Z), p.Z) else p
	end
	for i = 1, 6 do
		local angle = i / 6 * TAU
		local foot = ground(Vector3.new(math.cos(angle) * 1.6 * s, 0, math.sin(angle) * 1.6 * s)) + Vector3.new(0, 0.1, 0)
		rod(m, foot, base + Vector3.new(0, 2.6 * s, 0), 0.45 * s, Palette.log)
	end
	for i = 1, (if kind == "great" then 14 else 10) do
		local angle = i / (if kind == "great" then 14 else 10) * TAU
		local at = ground(Vector3.new(math.cos(angle) * 2.6 * s, 0, math.sin(angle) * 2.6 * s))
		decor(make("Part", {
			Size = Vector3.new(0.9, 0.5, 0.7) * math.sqrt(s),
			CFrame = CFrame.new(at + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, -angle, 0),
			Color = pick(STONE, rng),
			Material = Enum.Material.Slate,
			Parent = m,
		}))
	end
	local core = decor(make("Part", {
		Name = "Flame",
		Size = Vector3.new(1.2, 1.8, 1.2) * s,
		CFrame = CFrame.new(base + Vector3.new(0, 1.2 * s, 0)) * CFrame.Angles(0, math.rad(45), 0),
		Color = if green then GREEN_FIRE else FIRE,
		Material = Enum.Material.Neon,
		Transparency = if green then 0.3 else 0.2,
		Parent = m,
	}))
	local fire = Instance.new("Fire")
	fire.Size = 6 * s
	fire.Heat = 9 * s
	fire.Color = if green then GREEN_FIRE else FIRE
	fire.SecondaryColor = if green then GREEN_FIRE_EDGE else rgb(255, 60, 20)
	fire.Parent = core
	light(core, if green then rgb(140, 255, 110) else rgb(255, 150, 70), 16 * s, if kind == "great" then 0.9 else 1)
	if green then
		-- Zielone iskry lecą wysoko w górę (widać je z daleka, z dołu góry)
		local sparks = Instance.new("ParticleEmitter")
		sparks.Name = "Sparks"
		sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparks.Color = ColorSequence.new(rgb(200, 255, 140), rgb(90, 255, 120))
		sparks.LightEmission = 1
		sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35 * s), NumberSequenceKeypoint.new(1, 0) })
		sparks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		sparks.Lifetime = NumberRange.new(1.4, 2.6)
		sparks.Rate = if kind == "great" then 14 else 6
		sparks.Speed = NumberRange.new(4, 8)
		sparks.SpreadAngle = Vector2.new(18, 18)
		sparks.Acceleration = Vector3.new(0, 2, 0)
		sparks.EmissionDirection = Enum.NormalId.Top
		sparks.Parent = core
	end
	CollectionService:AddTag(core, "SabbathFire")
	m.Parent = parent
end

-- Kocioł sabatu na trzech nogach nad ogniem, z bulgoczącym zielonym wywarem i trującym dymem
local function cauldron(parent: Instance, spot: { x: number, z: number }, rng: Random)
	local m = Instance.new("Model")
	m.Name = "Cauldron"
	local base = groundAt(spot.x, spot.z)
	for i = 1, 3 do
		local angle = i / 3 * TAU + 0.3
		local foot = groundAt(spot.x + math.cos(angle) * 2.4, spot.z + math.sin(angle) * 2.4) - Vector3.new(0, 0.2, 0)
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
	-- Opary przy ziemi rozlewają się na cały zasięg chmury, żeby było widać, gdzie lepiej nie stać
	local radius = Config.Cauldrons.fumeRadius
	local area = decor(make("Part", {
		Name = "FumeArea",
		Size = Vector3.new(radius * 2, 0.4, radius * 2),
		Position = base + Vector3.new(0, 0.7, 0),
		Transparency = 1,
		Parent = m,
	}))
	local ground = Instance.new("ParticleEmitter")
	ground.Name = "GroundFumes"
	ground.Shape = Enum.ParticleEmitterShape.Sphere -- spłaszczona przez rozmiar części: koło o promieniu chmury
	ground.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	ground.Texture = "rbxasset://textures/particles/smoke_main.dds"
	ground.Color = ColorSequence.new(rgb(130, 220, 80), rgb(70, 130, 45))
	ground.LightInfluence = 0.5
	ground.LightEmission = 0.2
	ground.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 5) })
	ground.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.8),
		NumberSequenceKeypoint.new(0.7, 0.84),
		NumberSequenceKeypoint.new(1, 1),
	})
	ground.Lifetime = NumberRange.new(4, 6)
	ground.Rate = 5
	ground.Speed = NumberRange.new(0.2, 0.6)
	ground.Rotation = NumberRange.new(0, 360)
	ground.RotSpeed = NumberRange.new(-15, 15)
	ground.EmissionDirection = Enum.NormalId.Top
	ground.Parent = area
	-- Ogień pod kotłem
	local flame = decor(make("Part", { Name = "Flame", Size = Vector3.new(1.4, 1.2, 1.4), CFrame = CFrame.new(base + Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, math.rad(45), 0), Color = FIRE, Material = Enum.Material.Neon, Transparency = 0.25, Parent = m }))
	light(flame, rgb(255, 140, 60), 8, 0.6)
	for i = 1, 4 do
		local angle = i / 4 * TAU + rng:NextNumber(-0.2, 0.2)
		rod(m, base + Vector3.new(math.cos(angle) * 1.4, 0.2, math.sin(angle) * 1.4), base + Vector3.new(-math.cos(angle) * 1.4, 0.2, -math.sin(angle) * 1.4), 0.4, Palette.log)
	end
	m:SetAttribute("FumeRadius", Config.Cauldrons.fumeRadius)
	-- Kocioł dociera do klienta w całości (klient przypina do wywaru bulgotanie, SabbathView)
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	CollectionService:AddTag(m, "SabbathCauldron")
	m.Parent = parent
end

-- Stojący kamień (menhir) z kręgu na szczycie
local function menhir(parent: Instance, base: Vector3, rng: Random, facing: number)
	local height = rng:NextNumber(7, 10)
	make("Part", {
		Name = "Menhir",
		Size = Vector3.new(2.6, height, 1.8),
		CFrame = CFrame.new(base + Vector3.new(0, height / 2 - 0.6, 0)) * CFrame.Angles(math.rad(rng:NextNumber(-6, 6)), facing, math.rad(rng:NextNumber(-6, 6))),
		Color = pick(STONE, rng),
		Material = Enum.Material.Slate,
		Parent = parent,
	})
end

-- Latarnia ze skrzynką i czaszką przy ścieżce (fioletowe, przygaszone światło)
local function skullLantern(parent: Instance, base: Vector3)
	local m = Instance.new("Model")
	m.Name = "SkullLantern"
	make("Part", { Size = Vector3.new(0.5, 6.6, 0.5), Position = base + Vector3.new(0, 2.7, 0), Color = Palette.trunkDark, Parent = m })
	skull(m, CFrame.new(base + Vector3.new(0, 6.5, 0)), 1.1, rgb(190, 120, 255))
	local glow = decor(make("Part", { Size = Vector3.new(0.4, 0.4, 0.4), Position = base + Vector3.new(0, 6.5, 0), Transparency = 1, Parent = m }))
	light(glow, rgb(190, 130, 255), 14, 0.7)
	m.Parent = parent
end

-- Kierunek ścieżki (poziomo, długość 1) w miejscu z
local function pathDirection(z: number): Vector3
	local dx = Terrain.pathX(z + 0.5) - Terrain.pathX(z - 0.5)
	return Vector3.new(dx, 0, 1).Unit
end

-- Ścieżka z płaskich kamieni serpentynami w górę (od polany do chatki Baby Jagi). Kamienie leżą
-- co kilka kroków wzdłuż ścieżki, przechylone jak zbocze; na stromych odcinkach w poprzek ścieżki
-- leżą bale jak stopnie.
local function stonePath(parent: Instance, fromZ: number, toZ: number, rng: Random)
	local m = Instance.new("Model")
	m.Name = "Path"
	local z = fromZ
	local travelled = 0
	local nextStone = 0
	local nextStep = 0
	local previous = Vector3.new(Terrain.pathX(z), 0, z)
	while z < toZ do
		local x = Terrain.pathX(z)
		local here = Vector3.new(x, 0, z)
		travelled += (here - previous).Magnitude
		previous = here
		if travelled >= nextStone then
			local d = rng:NextNumber(2, 3)
			local at = groundAt(x + rng:NextNumber(-0.8, 0.8), z) - Vector3.new(0, 0.06, 0)
			decor(make("Part", {
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.3, d, d * rng:NextNumber(0.8, 1)),
				CFrame = slopeFrame(at, rng:NextNumber(0, TAU)) * VERTICAL,
				Color = pick(STONE, rng):Lerp(GROUND.cauldrons, rng:NextNumber(0.2, 0.4)),
				Material = Enum.Material.Slate,
				Parent = m,
			}))
			nextStone = travelled + rng:NextNumber(2.4, 3.2)
		end
		-- Stopnie z bali tam, gdzie ścieżka idzie stromo pod górę
		local forward = pathDirection(z)
		local rise = (Terrain.groundY(x + forward.X, z + forward.Z) - Terrain.groundY(x - forward.X, z - forward.Z)) / 2
		if rise > 0.2 and travelled >= nextStep then
			local across = Vector3.new(forward.Z, 0, -forward.X)
			local half = Config.Mountain.path + 0.6
			local a = groundAt(x - across.X * half, z - across.Z * half) + Vector3.new(0, 0.12, 0)
			local b = groundAt(x + across.X * half, z + across.Z * half) + Vector3.new(0, 0.12, 0)
			rod(m, a, b, 0.7, Palette.trunkDark)
			nextStep = travelled + 3.4
		end
		z += 0.5
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
		-- WedgePart bez obrotu jest najwyższy z tyłu (+Z): wysoki bok obracamy do kalenicy (środka)
		make("WedgePart", { Name = "Roof", Size = Vector3.new(12.4, 3.6, 5.6), CFrame = cf * CFrame.new(0, 8.8, side * 2.8) * CFrame.Angles(0, if side > 0 then math.pi else 0, 0), Color = THATCH, Material = Enum.Material.Fabric, Parent = m })
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
	bonfire(m, Vector3.new(-8, 0, zone.startZ + 34), rng, "warm")
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
		decor(make("WedgePart", { Name = "Roof", Size = Vector3.new(11.6, 4.4, 6), CFrame = houseCf * CFrame.new(0, 9.9, side * 3) * CFrame.Angles(0, if side > 0 then math.pi else 0, 0), Color = THATCH, Material = Enum.Material.Fabric, Parent = m }))
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
	-- Spojrzenie chatki: snop światła spod drzwi pada skosem na ziemię przed nią, więc widać, gdzie
	-- chatka patrzy (klient barwi go na czerwono, kiedy patrzy na ogródek). Beam zamiast SpotLight:
	-- w mroku szczytu światło punktowe ginęło w mgle, a snop widać z daleka.
	local eyeAt = (houseCf * CFrame.new(0, 3.4, -5.7)).Position
	local watch = decor(make("Part", {
		Name = "WatchLight",
		Size = Vector3.new(0.4, 0.4, 0.4),
		CFrame = CFrame.lookAt(eyeAt, eyeAt + Vector3.new(0, -0.8, -1)),
		Transparency = 1,
		Parent = m,
	}))
	watch:SetAttribute("WatchGlow", true)
	local from = Instance.new("Attachment")
	from.Name = "From"
	from.Parent = watch
	local to = Instance.new("Attachment")
	to.Name = "To"
	to.Position = Vector3.new(0, 0, -(floor + 3.4) / 0.62) -- do ziemi (spadek 0,8 na 1 = sinus ok. 0,62)
	to.Parent = watch
	local shaft = Instance.new("Beam")
	shaft.Attachment0 = from
	shaft.Attachment1 = to
	shaft.Width0 = 2.4
	shaft.Width1 = 10
	shaft.FaceCamera = true
	shaft.Segments = 1
	shaft.LightEmission = 1
	shaft.LightInfluence = 0
	shaft.Color = ColorSequence.new(GLOW_WINDOW)
	shaft.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(0.75, 0.8),
		NumberSequenceKeypoint.new(1, 1),
	})
	shaft.Parent = watch

	m:SetAttribute("Center", center)
	-- Cała chatka dociera do klienta naraz (inaczej klient mógłby obracać model bez osi nogi)
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	m.WorldPivot = CFrame.new(center)
	CollectionService:AddTag(m, "JagaHut")
	m.Parent = parent
	return m
end

-- Płot z kości wokół ogródka (czaszki z zielonymi oczami na co drugim palu) i grządki
local function buildGarden(parent: Instance, rng: Random)
	local lair = Config.JagaLair
	local center = Vector3.new(lair.centerX, Terrain.TOP, lair.centerZ)
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

-- ===== Ziemia góry =====

-- Wygląd trójkąta: kolor strefy, goła skała na stromiznach, ciemne dno doliny; każdy trójkąt
-- trochę inny odcień (widać ściany jak w low-poly)
local function terrainLook(center: Vector3, up: number, rng: Random): (Color3, Enum.Material)
	local color: Color3
	local material: Enum.Material
	if center.Y < Terrain.FLOOR + 6 then
		color, material = VALLEY, Enum.Material.Grass
	elseif up < 0.72 then
		color, material = pick(ROCK, rng), Enum.Material.Slate
	else
		local zoneId = "summit"
		local zone = Config.Zones[Economy.zoneIndexAt(math.clamp(center.Z, 3000, 3479))]
		if zone and zone.world == "mountain" then
			zoneId = zone.id
		end
		color, material = GROUND[zoneId] or GROUND.witchwood, GROUND_MATERIAL[zoneId] or Enum.Material.Ground
		if math.abs(center.X) > Terrain.HALF then
			-- Za ścianą: brzeg grzbietu i krawędź urwiska bardziej skaliste
			color = color:Lerp(ROCK[1], 0.45)
			material = Enum.Material.Slate
		end
	end
	return color:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.16)), material
end

-- Trójkąt z dwóch klinów (grubość pod spodem, wierzch dokładnie na płaszczyźnie trójkąta)
local function triangle(parent: Instance, a: Vector3, b: Vector3, c: Vector3, rng: Random)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local normal = ac:Cross(ab)
	if normal.Magnitude < 1e-4 then
		return
	end
	local right = normal.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local surface = if right.Y >= 0 then right else -right
	local shift = -surface * TERRAIN_THICKNESS / 2
	local color, material = terrainLook((a + b + c) / 3, surface.Y, rng)
	local function wedge(size: Vector3, cf: CFrame)
		local w = make("WedgePart", { Name = "Ground", Size = size, CFrame = cf, Color = color, Material = material, Parent = parent })
		w.CastShadow = false
	end
	wedge(Vector3.new(TERRAIN_THICKNESS, height, math.abs(ab:Dot(back))), CFrame.fromMatrix((a + b) / 2 + shift, right, up, back))
	wedge(Vector3.new(TERRAIN_THICKNESS, height, math.abs(ac:Dot(back))), CFrame.fromMatrix((a + c) / 2 + shift, -right, up, -back))
end

-- Ziemia z trójkątów (te same, co liczy Shared/MountainTerrain), płaska polana, dno doliny i ściany
local function buildGround(parent: Instance, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "Terrain"
	local XS, ZS = Terrain.XS, Terrain.ZS
	local gladeEnd = 3040
	local function vertex(i: number, j: number): Vector3
		return Vector3.new(XS[i], Terrain.vertex(i, j), ZS[j])
	end
	local function skip(t: { Vector3 }): boolean
		-- Polana ma własną płaską ziemię, a dno doliny przykrywa jedna płyta
		local glade, floor = true, true
		for _, v in t do
			if not (v.Y == 0 and math.abs(v.X) <= Terrain.HALF and v.Z <= gladeEnd) then
				glade = false
			end
			if v.Y > Terrain.FLOOR + 0.01 then
				floor = false
			end
		end
		return glade or floor
	end
	for j = 1, #ZS - 1 do
		for i = 1, #XS - 1 do
			local a, b, c, d = vertex(i, j), vertex(i + 1, j), vertex(i, j + 1), vertex(i + 1, j + 1)
			if a.Y == b.Y and a.Y == c.Y and a.Y == d.Y then
				-- Płaska komórka (place, płaskowyż): jeden klocek zamiast czterech klinów
				if not skip({ a, b, c, d }) then
					local color, material = terrainLook((a + d) / 2, 1, rng)
					local p = make("Part", {
						Name = "Ground",
						Size = Vector3.new(b.X - a.X, TERRAIN_THICKNESS, c.Z - a.Z),
						Position = Vector3.new((a.X + b.X) / 2, a.Y - TERRAIN_THICKNESS / 2, (a.Z + c.Z) / 2),
						Color = color,
						Material = material,
						Parent = folder,
					})
					p.CastShadow = false
				end
			else
				local pair: { { Vector3 } } = if Terrain.diagonalAD(i, j) then { { a, b, d }, { a, d, c } } else { { a, b, c }, { b, d, c } }
				for _, t in pair do
					if not skip(t) then
						triangle(folder, t[1], t[2], t[3], rng)
					end
				end
			end
		end
	end
	-- Polana: płaska trawa od początku świata do pierwszej bramy
	local z1 = ZS[1]
	make("Part", {
		Name = "Ground_glade",
		Size = Vector3.new(Terrain.HALF * 2, 2, gladeEnd - z1),
		Position = Vector3.new(0, -1, (z1 + gladeEnd) / 2),
		Color = GROUND.glade,
		Material = GROUND_MATERIAL.glade,
		Parent = folder,
	})
	-- Dno doliny pod urwiskami (las, rzeka i wioska stoją na nim)
	decor(make("Part", {
		Name = "ValleyFloor",
		Size = Vector3.new(1700, 2, 1800),
		Position = Vector3.new(60, Terrain.FLOOR - 1, 3380),
		Color = VALLEY,
		Material = Enum.Material.Grass,
		Parent = folder,
	}))
	-- Niewidzialne ściany: wysokie, bo ziemia sięga ponad 60 studs
	local zones = mountainZones()
	local first, last = zones[1].zone, zones[#zones].zone
	local hw = Config.Mountain.halfWidth
	local totalLength = last.endZ - first.startZ
	local centerZ = first.startZ + totalLength / 2
	local function wall(size: Vector3, position: Vector3)
		local w = make("Part", { Name = "InvisibleWall", Size = size, Position = position, Transparency = 1, Parent = folder })
		w.CanQuery = false
	end
	for _, side in { -1, 1 } do
		wall(Vector3.new(2, 280, totalLength + 4), Vector3.new(side * (hw + 1), 100, centerZ))
	end
	for _, z in { first.startZ - 1, last.endZ + 1 } do
		wall(Vector3.new(hw * 2 + 4, 280, 2), Vector3.new(0, 100, z))
	end
	folder.Parent = parent
end

-- ===== Brzegi świata =====

-- Krzywy płot z pali nad urwiskiem (czaszki na co czwartym palu patrzą na ścieżkę)
local function fence(parent: Instance, from: Vector3, to: Vector3, rng: Random)
	local count = math.max(1, math.floor((to - from).Magnitude / 8))
	local inward = Vector3.new(-math.sign(from.X), 0, 0)
	if math.abs(from.X - to.X) > math.abs(from.Z - to.Z) then
		inward = Vector3.new(0, 0, -1)
	end
	local previous: Vector3? = nil
	for k = 0, count do
		local p = from:Lerp(to, k / count)
		local base = groundAt(p.X, p.Z)
		local lean = CFrame.Angles(math.rad(rng:NextNumber(-7, 7)), 0, math.rad(rng:NextNumber(-7, 7)))
		local top = (CFrame.new(base) * lean * CFrame.new(0, rng:NextNumber(2.6, 3.4), 0)).Position
		rod(parent, base - Vector3.new(0, 0.8, 0), top, 0.45, Palette.trunkDark)
		if previous then
			rod(parent, previous - Vector3.new(0, 0.6, 0), top - Vector3.new(0, 0.6, 0), 0.22, Palette.log)
		end
		if k % 4 == 2 then
			skull(parent, CFrame.lookAt(top + Vector3.new(0, 0.42, 0), top + Vector3.new(0, 0.42, 0) + inward), 0.8, nil)
		end
		previous = top
	end
end

local function buildEdges(parent: Instance, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "Edges"
	local hw = Config.Mountain.halfWidth
	local zones = mountainZones()
	local first, last = zones[1].zone, zones[#zones].zone
	-- Brzeg pod grzbietem: krzywe drzewa i skały tuż przy ścianie, wyżej na stoku drugi rząd
	local z = first.startZ
	while z < last.endZ - 4 do
		local x = -(hw - 2) + rng:NextNumber(-1.5, 1.5)
		if rng:NextNumber() < 0.7 then
			crookedTree(folder, footing(x, z, 1), rng, rng:NextNumber(1.3, 1.8), false)
		else
			Props.rock(folder, footing(x, z, 2), rng:NextNumber(1.4, 2), rng, 0.6)
		end
		if z < 3400 and rng:NextNumber() < 0.65 then
			local x2 = -(hw + 6) - rng:NextNumber(0, 16)
			local z2 = z + rng:NextNumber(-3, 3)
			crookedTree(folder, footing(x2, z2, 1.5), rng, rng:NextNumber(1.4, 2.1), false)
		end
		z += rng:NextNumber(7, 11)
	end
	-- Po drugiej stronie drzewa tylko przy polanie; dalej płot nad urwiskiem, żeby widać było dolinę
	z = first.startZ
	while z < first.endZ do
		crookedTree(folder, footing(hw - 2 + rng:NextNumber(-1.5, 1.5), z, 1), rng, rng:NextNumber(1.3, 1.8), false)
		z += rng:NextNumber(7, 11)
	end
	fence(folder, Vector3.new(hw - 0.8, 0, first.endZ + 4), Vector3.new(hw - 0.8, 0, last.endZ - 3), rng)
	-- Za ogródkiem i pod szczytem po drugiej stronie zbocze też opada w chmury
	fence(folder, Vector3.new(-hw + 2, 0, last.endZ - 1.5), Vector3.new(hw - 2, 0, last.endZ - 1.5), rng)
	fence(folder, Vector3.new(-(hw - 0.8), 0, 3418), Vector3.new(-(hw - 0.8), 0, last.endZ - 3), rng)
	-- Rząd drzew na początku świata (za polaną)
	local x = -hw
	while x < hw do
		crookedTree(folder, Vector3.new(x, 0, first.startZ - 2), rng, rng:NextNumber(1.3, 1.8), false)
		x += rng:NextNumber(8, 11)
	end
	-- Skalne iglice na grzbiecie: postrzępiona sylwetka na tle nieba (słup skały ze spiczastym czubem)
	z = 3050
	while z < 3370 do
		local cx = -rng:NextNumber(88, 112)
		local base = groundAt(cx, z)
		local height = rng:NextNumber(10, 22)
		local width, depth = rng:NextNumber(5, 8), rng:NextNumber(4, 7)
		local color = pick(ROCK, rng)
		local frame = CFrame.new(base) * CFrame.Angles(math.rad(rng:NextNumber(-10, 10)), rng:NextNumber(0, TAU), math.rad(rng:NextNumber(-10, 10)))
		decor(make("Part", {
			Name = "Spire",
			Size = Vector3.new(width, height, depth),
			CFrame = frame * CFrame.new(0, height / 2 - 2, 0),
			Color = color,
			Material = Enum.Material.Slate,
			Parent = folder,
		}))
		-- Czub z dwóch klinów (jak dach), wyższy na jedną stronę
		local peak = height * rng:NextNumber(0.45, 0.8)
		for _, side in { -1, 1 } do
			decor(make("WedgePart", {
				Name = "Spire",
				Size = Vector3.new(width, peak, depth / 2),
				CFrame = frame * CFrame.new(0, height - 2 + peak / 2, side * depth / 4) * CFrame.Angles(0, if side > 0 then math.pi else 0, 0),
				Color = color,
				Material = Enum.Material.Slate,
				Parent = folder,
			}))
		end
		z += rng:NextNumber(26, 44)
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
	for _, fire in MountainShared.FIRES do
		if not fire.big and fire.z >= zone.startZ and fire.z < zone.endZ then
			bonfire(folder, groundAt(fire.x, fire.z), rng, "sabbath")
		end
	end
	for i = 1, recipe.crooked do
		local scale = rng:NextNumber(0.9, 1.3)
		local x, z = api.place(rng, -hw, hw, z1, z2, 2.4 * scale)
		if x and z then
			crookedTree(folder, footing(x, z, 1.2), rng, scale, i % 2 == 0)
		end
	end
	for _ = 1, recipe.pines do
		local x, z = api.place(rng, -hw, hw, z1, z2, 2.4)
		if x and z then
			Props.pine(folder, footing(x, z, 1.2), rng:NextNumber(1, 1.4), rng, 0.85)
		end
	end
	for _ = 1, recipe.rocks do
		local x, z = api.place(rng, -hw, hw, z1, z2, 2.5)
		if x and z then
			Props.rock(folder, footing(x, z, 2), rng:NextNumber(0.8, 1.4), rng, zone.darkness * 0.6)
		end
	end
	for _ = 1, recipe.stumps do
		local x, z = api.place(rng, -hw, hw, z1, z2, 1.8)
		if x and z then
			Props.stump(folder, footing(x, z, 1.2), rng:NextNumber(0.8, 1.2), rng, zone.darkness * 0.6)
		end
	end
	for _ = 1, recipe.bones do
		local x, z = api.place(rng, -hw, hw, z1, z2, 1.6)
		if x and z then
			bonePile(folder, groundAt(x, z), rng)
		end
	end
	for _ = 1, recipe.brooms do
		local x, z = api.place(rng, -hw, hw, z1, z2, 1.2)
		if x and z then
			broom(folder, footing(x, z, 0.3), rng)
		end
	end
	for _ = 1, recipe.glow do
		local x, z = api.place(rng, -hw, hw, z1, z2, 1.6)
		if x and z then
			Props.glowCluster(folder, footing(x, z, 0.6), rng)
		end
	end
	for _ = 1, recipe.tufts do
		local x, z = api.place(rng, -hw, hw, z1, z2, 0.8)
		if x and z then
			Props.grass(folder, footing(x, z, 0.4), rng:NextNumber(0.9, 1.3), rng, 0.7)
		end
	end
	folder.Parent = parent
end

-- Krąg kamieni na wyrównanym placu (ścieżka przechodzi przez środek): ołtarz z runą po jednej
-- stronie ścieżki, wielkie zielone ognisko sabatu po drugiej
local function buildStoneCircle(parent: Instance, rng: Random)
	local circle = MountainShared.STONE_CIRCLE
	local m = Instance.new("Model")
	m.Name = "StoneCircle"
	local center = Vector3.new(circle.x, Terrain.CIRCLE_Y, circle.z)
	for i = 1, 10 do
		local angle = (i - 0.5) / 10 * TAU
		local dir = Vector3.new(math.sin(angle), 0, math.cos(angle))
		-- Bez kamieni na ścieżce (przód i tył kręgu)
		if math.abs(dir.X) > 0.3 then
			local at = center + dir * circle.radius
			menhir(m, groundAt(at.X, at.Z), rng, -angle)
		end
	end
	make("Part", { Name = "Altar", Size = Vector3.new(4, 1.6, 2.6), Position = center + Vector3.new(7, 0.8, 0), Color = pick(STONE, rng), Material = Enum.Material.Slate, Parent = m })
	local rune = decor(make("Part", { Name = "Rune", Size = Vector3.new(2.2, 0.06, 1.4), Position = center + Vector3.new(7, 1.63, 0), Color = rgb(190, 110, 255), Material = Enum.Material.Neon, Transparency = 0.35, Parent = m }))
	light(rune, rgb(190, 120, 255), 12, 0.6)
	for _, fire in MountainShared.FIRES do
		if fire.big then
			bonfire(m, groundAt(fire.x, fire.z), rng, "great")
		end
	end
	m.Parent = parent
end

-- Miejsca, gdzie nic nie może wyrosnąć: polana, ścieżka (serpentyny), kotły, ogniska, krąg kamieni,
-- chatka i ogródek
function Mountain.reservedRects(): { Rect }
	local rects: { Rect } = {}
	local half = Config.Mountain.path + 1
	for _, entry in mountainZones() do
		local zone = entry.zone
		if zone.safe then
			table.insert(rects, { x1 = -Config.Mountain.halfWidth, x2 = Config.Mountain.halfWidth, z1 = zone.startZ - 4, z2 = zone.endZ + 2 })
		else
			local z = zone.startZ
			while z < zone.endZ do
				local z2 = math.min(z + 4, zone.endZ)
				local xa, xb = Terrain.pathX(z), Terrain.pathX(z2)
				table.insert(rects, { x1 = math.min(xa, xb) - half, x2 = math.max(xa, xb) + half, z1 = z, z2 = z2 })
				z = z2
			end
			table.insert(rects, { x1 = -9.5, x2 = 9.5, z1 = zone.startZ - 2.5, z2 = zone.startZ + 2.5 })
		end
	end
	for _, spot in MountainShared.CAULDRONS do
		table.insert(rects, { x1 = spot.x - 4, x2 = spot.x + 4, z1 = spot.z - 4, z2 = spot.z + 4 })
	end
	for _, fire in MountainShared.FIRES do
		local r = if fire.big then 5 else 3.5
		table.insert(rects, { x1 = fire.x - r, x2 = fire.x + r, z1 = fire.z - r, z2 = fire.z + r })
	end
	local circle = MountainShared.STONE_CIRCLE
	table.insert(rects, { x1 = circle.x - circle.radius - 2, x2 = circle.x + circle.radius + 2, z1 = circle.z - circle.radius - 2, z2 = circle.z + circle.radius + 2 })
	local lair = Config.JagaLair
	table.insert(rects, { x1 = lair.centerX - lair.radius - 2, x2 = lair.centerX + lair.radius + 2, z1 = lair.hutZ - 8, z2 = lair.centerZ + lair.radius + 2 })
	return rects
end

-- ===== Widok z góry: dolina, chmury, dalekie szczyty =====

local MOUNTAIN_HILLS = { rgb(34, 28, 40), rgb(40, 32, 46), rgb(30, 26, 36) }
local MOUNTAIN_PEAKS = { rgb(48, 42, 58), rgb(40, 36, 52), rgb(56, 48, 64) }

-- Czy w (x, z) jest już dno doliny (poza górą albo na jej dole)
local function inValley(x: number, z: number): boolean
	return not Terrain.covers(x, z) or Terrain.groundY(x, z) <= Terrain.FLOOR + 1
end

local function blob(parent: Instance, center: Vector3, size: Vector3, color: Color3, transparency: number?): BasePart
	local p = Backdrop.blob(parent, center, size, color)
	p.Transparency = transparency or 0
	return p
end

local function buildScenery(parent: Instance, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "Scenery"
	local hw = Config.Mountain.halfWidth
	local zones = mountainZones()
	local first, last = zones[1].zone, zones[#zones].zone

	-- Za polaną (początek świata) zwykłe tło: drzewa, wzgórza i góry zasłaniają bagna
	Backdrop.build(folder, { x1 = -hw - 1, x2 = hw + 1, z1 = first.startZ - 3, z2 = last.endZ + 3 }, {
		name = "Mountain",
		near = function(f: Instance, base: Vector3, treeRng: Random)
			if treeRng:NextNumber() < 0.6 then
				crookedTree(f, base, treeRng, treeRng:NextNumber(1.5, 2), false)
			else
				Props.pine(f, base, treeRng:NextNumber(1.4, 1.9), treeRng, 0.95)
			end
		end,
		nearSpacing = 10,
		far = function(f: Instance, base: Vector3, treeRng: Random)
			local s = treeRng:NextNumber(1.8, 2.6)
			Backdrop.cone(f, base + Vector3.new(0, 4 * s, 0), 7 * s, 12 * s, treeRng:NextNumber(0, TAU), rgb(22, 26, 28))
		end,
		farSpacing = 10,
		hill = MOUNTAIN_HILLS,
		hillHeight = { 30, 52 },
		mountain = MOUNTAIN_PEAKS,
		mountainHeight = { 45, 75 },
		ends = { true, false },
		lines = { x1 = false, x2 = false, z1 = true, z2 = false },
		groundY = Terrain.groundY,
	}, rng)

	-- Las w dolinie: ciemne korony widziane z góry
	local function forest(x1: number, x2: number, z1: number, z2: number, count: number)
		for _ = 1, count do
			local x, z = rng:NextNumber(x1, x2), rng:NextNumber(z1, z2)
			if inValley(x, z) then
				local w = rng:NextNumber(14, 30)
				local h = rng:NextNumber(10, 18)
				blob(folder, Vector3.new(x, Terrain.FLOOR + h * 0.3, z), Vector3.new(w, h, w * rng:NextNumber(0.8, 1.2)), pick(VALLEY_TREES, rng))
			end
		end
	end
	forest(70, 420, 2930, 3700, 90)
	forest(-320, 320, 3540, 3900, 50)
	forest(-420, -150, 3000, 3700, 40)

	-- Rzeka wijąca się dnem doliny (lekko świeci w świetle księżyca)
	local points = {
		Vector3.new(60, 0, 3900),
		Vector3.new(120, 0, 3700),
		Vector3.new(160, 0, 3520),
		Vector3.new(240, 0, 3360),
		Vector3.new(200, 0, 3200),
		Vector3.new(270, 0, 3040),
		Vector3.new(340, 0, 2900),
	}
	for k = 1, #points - 1 do
		local p0 = points[math.max(k - 1, 1)]
		local p1, p2 = points[k], points[k + 1]
		local p3 = points[math.min(k + 2, #points)]
		local previous = p1
		for step = 1, 6 do
			local t = step / 6
			local t2, t3 = t * t, t * t * t
			-- Catmull-Rom: gładka linia przez punkty
			local p = (p1 * 2 + (p2 - p0) * t + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 + (p1 * 3 - p0 - p2 * 3 + p3) * t3) * 0.5
			local length = (p - previous).Magnitude
			if length > 0.1 then
				decor(make("Part", {
					Name = "River",
					Size = Vector3.new(rng:NextNumber(5, 7), 0.3, length + 3),
					CFrame = CFrame.lookAt((previous + p) / 2, p) + Vector3.new(0, Terrain.FLOOR + 0.25, 0),
					Color = RIVER,
					Material = Enum.Material.Neon,
					Transparency = 0.5,
					Parent = folder,
				}))
			end
			previous = p
		end
	end

	-- Wioska w dole: kilka chałup z ciepłymi okienkami (z góry widać tylko światełka)
	for _ = 1, 9 do
		local at = Vector3.new(rng:NextNumber(230, 290), Terrain.FLOOR, rng:NextNumber(3120, 3220))
		local cf = CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0)
		decor(make("Part", { Size = Vector3.new(6, 4, 5), CFrame = cf * CFrame.new(0, 2, 0), Color = rgb(40, 32, 30), Parent = folder }))
		decor(make("WedgePart", { Size = Vector3.new(6.4, 2.4, 2.8), CFrame = cf * CFrame.new(0, 5.2, -1.3), Color = rgb(52, 38, 34), Parent = folder }))
		decor(make("WedgePart", { Size = Vector3.new(6.4, 2.4, 2.8), CFrame = cf * CFrame.new(0, 5.2, 1.3) * CFrame.Angles(0, math.pi, 0), Color = rgb(52, 38, 34), Parent = folder }))
		decor(make("Part", { Size = Vector3.new(1.2, 1.1, 0.2), CFrame = cf * CFrame.new(rng:NextNumber(-1.6, 1.6), 2.2, -2.55), Color = VILLAGE_WINDOW, Material = Enum.Material.Neon, Parent = folder }))
	end

	-- Morze chmur pod szczytem: daleko po bokach góry i za nią (z kręgu kamieni i ze szczytu patrzy się
	-- na nie z góry; niżej na zboczu widać pod nimi dolinę). Każda chmura to płaska podstawa i kilka
	-- kłębów na wierzchu; neon, bo w nocy chmury świecą światłem księżyca.
	local function cloud(center: Vector3, size: number)
		local color = pick(CLOUDS, rng)
		local base = blob(folder, center, Vector3.new(size, size * rng:NextNumber(0.1, 0.14), size * rng:NextNumber(0.6, 0.85)), color, rng:NextNumber(0.45, 0.6))
		base.Material = Enum.Material.Neon
		for _ = 1, rng:NextInteger(1, 3) do
			local puff = size * rng:NextNumber(0.3, 0.5)
			local at = center + Vector3.new(rng:NextNumber(-0.3, 0.3) * size, puff * 0.12, rng:NextNumber(-0.2, 0.2) * size)
			local p = blob(folder, at, Vector3.new(puff, puff * rng:NextNumber(0.3, 0.45), puff * rng:NextNumber(0.7, 1)), color, rng:NextNumber(0.5, 0.65))
			p.Material = Enum.Material.Neon
		end
	end
	local function clouds(x1: number, x2: number, z1: number, z2: number, count: number)
		for _ = 1, count do
			local x, z = rng:NextNumber(x1, x2), rng:NextNumber(z1, z2)
			local y = Terrain.CLOUDS + rng:NextNumber(-3, 3)
			-- Chmura nie wchodzi w zbocze góry
			if not Terrain.covers(x, z) or Terrain.groundY(x, z) < y - 12 then
				cloud(Vector3.new(x, y, z), rng:NextNumber(60, 130))
			end
		end
	end
	clouds(150, 650, 3260, 3950, 34)
	clouds(-460, 460, 3540, 4100, 40)
	clouds(-560, -180, 3260, 3950, 20)

	-- Dalekie szczyty za morzem chmur (blade wierzchołki w świetle księżyca)
	for _, peak in {
		{ -300, 3760, 96 },
		{ -150, 3900, 118 },
		{ 30, 3980, 104 },
		{ 190, 3880, 112 },
		{ 330, 3770, 92 },
		{ -420, 3640, 84 },
		{ 440, 3640, 80 },
	} do
		local height = peak[3]
		local base = Vector3.new(peak[1], Terrain.FLOOR - 2, peak[2])
		local width = height * rng:NextNumber(1.2, 1.5)
		local yaw = rng:NextNumber(0, TAU)
		Backdrop.cone(folder, base, width, height, yaw, pick(PEAKS, rng))
		Backdrop.cone(folder, base + Vector3.new(0, height * 0.72, 0), width * 0.28, height * 0.28, yaw, PEAK_TOP)
	end
	folder.Parent = parent
end

-- Buduje Łysą Górę. Zwraca CFrame polany (tu ląduje gracz) i Babę Jagę drzemiącą przy chatce.
function Mountain.build(parent: Instance, rng: Random, api: Api): (CFrame, Model)
	local folder = Instance.new("Folder")
	folder.Name = "Mountain"
	buildGround(folder, rng)
	buildEdges(folder, rng)
	local zones = mountainZones()
	for index, entry in zones do
		local zone = entry.zone
		if zone.safe then
			buildGlade(folder, zone, rng)
		else
			if index > 1 then
				Props.gate(folder, zone.startZ, zone.key, Terrain.groundY(0, zone.startZ))
			end
			buildZoneDecor(folder, zone, rng, api)
		end
	end
	local lair = Config.JagaLair
	stonePath(folder, zones[1].zone.endZ - 1, lair.hutZ - 6, rng)
	-- Latarnie z czaszkami przy ścieżce, na zmianę po obu stronach (z dala od bram stref)
	local side = 1
	local travelled = 0
	local nextLantern = 20
	local z = zones[1].zone.endZ
	local previous = Vector3.new(Terrain.pathX(z), 0, z)
	while z < lair.hutZ - 20 do
		local here = Vector3.new(Terrain.pathX(z), 0, z)
		travelled += (here - previous).Magnitude
		previous = here
		if travelled >= nextLantern then
			local nearGate = false
			for _, entry in zones do
				if math.abs(entry.zone.startZ - z) < 6 then
					nearGate = true
				end
			end
			local circle = MountainShared.STONE_CIRCLE
			if not nearGate and math.abs(z - circle.z) > circle.radius + 3 then
				local forward = pathDirection(z)
				local across = Vector3.new(forward.Z, 0, -forward.X)
				local at = here + across * side * (Config.Mountain.path + 1.6)
				skullLantern(folder, footing(at.X, at.Z, 0.3))
				side = -side
				nextLantern = travelled + 34
			end
		end
		z += 0.5
	end
	buildStoneCircle(folder, rng)
	buildHut(folder, Vector3.new(lair.centerX, Terrain.TOP, lair.hutZ))
	buildGarden(folder, rng)
	-- Tabliczka ostrzegawcza przed chatką
	local signZ = lair.hutZ - 14
	local signY = Terrain.groundY(9, signZ)
	for _, s in { -1, 1 } do
		local post = groundAt(9 + s * 4.2, signZ + 0.4)
		make("Part", { Size = Vector3.new(0.4, 5.4, 0.4), Position = Vector3.new(post.X, post.Y + 1.9, post.Z), Color = Palette.log, Parent = folder })
	end
	Props.signBoard(folder, CFrame.new(9, signY + 3.8, signZ), Vector3.new(9.6, 2.2, 0.3), "SIGN_HUT", Enum.NormalId.Front)
	buildScenery(folder, rng)
	folder.Parent = parent
	-- Baba Jaga drzemie w moździerzu obok chatki (posąg; budzi się, kiedy ktoś ukradnie jej Ziele)
	local statueAt = Vector3.new(lair.centerX + 9, Terrain.TOP, lair.hutZ - 3)
	local statue = Jaga.build(parent, CFrame.lookAt(statueAt, statueAt - Vector3.new(0, 0, 17)), false)
	statue.Name = "JagaStatue"
	local camp = Config.Mountain.camp
	return CFrame.new(camp.x, 3, camp.z) * CFrame.Angles(0, math.pi, 0), statue
end

-- Skąd wylatuje Baba Jaga w pościgu: spod drzwi chatki (na płaskim szczycie)
function Mountain.jagaOrigin(): Vector3
	local lair = Config.JagaLair
	return Vector3.new(lair.centerX, Terrain.TOP, lair.hutZ - 6)
end

return Mountain
