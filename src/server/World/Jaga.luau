--!strict
-- Baba Jaga: wiedźma ze słowiańskich baśni. Przygarbiona staruszka w czerwonej chuście w kwiaty,
-- z długim żelaznym nosem, siwymi kosmykami i jednym zębem, siedzi w drewnianym moździerzu, który
-- unosi się nad ziemią. Prawą ręką wiosłuje tłuczkiem, lewą ciągnie za sobą miotłę, która zamiata
-- ślady. Kiedy się budzi, oczy świecą na zielono, a spod moździerza sypie się pył i iskry.
-- Klocki z pikselową kratką jak inni strażnicy, ale bez szkieletu: nie chodzi, tylko leci
-- (ChaseService przesuwa cały model i dodaje lekkie kołysanie). Pivot na ziemi, przód to -Z.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Jaga = {}

Jaga.EYE_COLOR = Color3.fromRGB(170, 255, 90)
Jaga.EYE_SLEEP = Color3.fromRGB(60, 70, 40)

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local TEXTURE = (Config :: any).VoxelNoise and (Config :: any).VoxelNoise.texture or ""
local FACES = { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right, Enum.NormalId.Top }

local SKIN = rgb(196, 182, 150)
local SKIN_SHADE = rgb(164, 150, 122)
local WART = rgb(120, 140, 80)
local IRON = rgb(96, 98, 104)
local IRON_DARK = rgb(64, 66, 72)
local HAIR = rgb(206, 206, 200)
local SCARF = rgb(170, 36, 40)
local SCARF_DARK = rgb(124, 24, 30)
local FLOWER = rgb(236, 196, 70)
local DRESS = rgb(56, 44, 62)
local DRESS_DARK = rgb(40, 32, 46)
local APRON = rgb(120, 104, 70)
local WOOD = rgb(120, 82, 52)
local WOOD_DARK = rgb(86, 58, 38)
local WOOD_RIM = rgb(146, 104, 66)
local STRAW = rgb(206, 170, 90)
local STRAW_DARK = rgb(160, 126, 62)
local TOOTH = rgb(236, 226, 196)
local MOUTH = rgb(40, 18, 24)

local HOVER = 1.4 -- tak wysoko nad ziemią unosi się dno moździerza

local function cf(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

local function rot(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

type Options = { shape: Enum.PartType?, neon: boolean?, texture: number?, material: Enum.Material?, transparency: number? }

local function block(m: Model, name: string, size: Vector3, at: CFrame, color: Color3, options: Options?): Part
	local o: Options = options or {}
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = at
	p.Color = color
	p.Material = if o.neon then Enum.Material.Neon else (o.material or Enum.Material.SmoothPlastic)
	p.Transparency = o.transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if o.shape then
		p.Shape = o.shape
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = not o.neon
	if o.texture and TEXTURE ~= "" and not o.neon then
		for _, face in FACES do
			local tex = Instance.new("Texture")
			tex.Texture = TEXTURE
			tex.Face = face
			tex.StudsPerTileU = 2
			tex.StudsPerTileV = 2
			tex.Transparency = o.texture
			tex.Parent = p
		end
	end
	p.Parent = m
	return p
end

-- Walec od `from` do `to` (tłuczek, kij miotły, pasma włosów)
local function rod(m: Model, name: string, from: Vector3, to: Vector3, thickness: number, color: Color3, options: Options?): Part
	local length = (to - from).Magnitude
	local o: Options = table.clone(options or {})
	o.shape = Enum.PartType.Cylinder
	return block(m, name, Vector3.new(length, thickness, thickness), CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(0, math.rad(90), 0), color, o)
end

-- Buduje Babę Jagę w moździerzu w `at` (pivot na ziemi). awake = świecące oczy, pył i iskry.
function Jaga.build(parent: Instance, at: CFrame, awake: boolean): Model
	local m = Instance.new("Model")
	m.Name = "BabaJaga"
	m:SetAttribute("Awake", awake)
	local root = block(m, "Root", Vector3.new(2, 1, 2), cf(0, 0.5, 0), WOOD, { transparency = 1 })
	m.PrimaryPart = root

	local base = HOVER
	-- ===== Moździerz: gruby drewniany kubeł z obręczami =====
	local vertical = CFrame.Angles(0, 0, math.rad(90))
	block(m, "MortarBottom", Vector3.new(0.6, 2.6, 2.6), cf(0, base + 0.3, 0) * vertical, WOOD_DARK, { shape = Enum.PartType.Cylinder, texture = 0.6 })
	block(m, "Mortar", Vector3.new(2.8, 3.6, 3.6), cf(0, base + 1.9, 0) * vertical, WOOD, { shape = Enum.PartType.Cylinder, texture = 0.55 })
	block(m, "MortarRim", Vector3.new(0.45, 4.0, 4.0), cf(0, base + 3.35, 0) * vertical, WOOD_RIM, { shape = Enum.PartType.Cylinder })
	for _, y in { base + 1.1, base + 2.6 } do
		block(m, "Hoop", Vector3.new(0.25, 3.72, 3.72), cf(0, y, 0) * vertical, IRON_DARK, { shape = Enum.PartType.Cylinder })
	end
	-- Wnętrze (ciemne) widać zza pleców
	block(m, "MortarInside", Vector3.new(0.1, 3.3, 3.3), cf(0, base + 3.5, 0) * vertical, WOOD_DARK, { shape = Enum.PartType.Cylinder })

	-- ===== Tułów: przygarbiona, w ciemnej sukni z fartuchem, garb z tyłu =====
	local body = base + 3.4
	block(m, "Dress", Vector3.new(2.4, 1.6, 2.0), cf(0, body + 0.7, 0.2), DRESS, { texture = 0.55 })
	block(m, "Apron", Vector3.new(1.8, 1.3, 0.15), cf(0, body + 0.6, -0.85) * rot(-8, 0, 0), APRON, { texture = 0.6 })
	block(m, "Chest", Vector3.new(2.2, 1.3, 1.8), cf(0, body + 1.9, -0.05) * rot(-18, 0, 0), DRESS, { texture = 0.55 })
	block(m, "Hump", Vector3.new(1.8, 1.2, 1.0), cf(0, body + 2.2, 0.9) * rot(-30, 0, 0), DRESS_DARK, { texture = 0.6 })
	-- Chusta na ramionach (trójkąt na plecach) w kwiaty
	block(m, "Shawl", Vector3.new(2.6, 0.5, 2.1), cf(0, body + 2.6, 0.15) * rot(-14, 0, 0), SCARF, { texture = 0.55 })
	block(m, "ShawlBack", Vector3.new(1.8, 1.4, 0.2), cf(0, body + 1.9, 1.05) * rot(-10, 0, 0), SCARF, { texture = 0.55 })
	for i, x in { -0.8, 0, 0.8 } do
		block(m, "Flower", Vector3.new(0.3, 0.3, 0.08), cf(x, body + 1.8 + (i % 2) * 0.3, 1.16) * rot(-10, 0, 0), FLOWER)
	end

	-- ===== Głowa: chusta zawiązana pod brodą, żelazny haczykowaty nos, jeden ząb =====
	local headY = body + 3.4
	local head = block(m, "Head", Vector3.new(1.7, 1.6, 1.6), cf(0, headY, -0.55) * rot(-12, 0, 0), SKIN, { texture = 0.6 })
	block(m, "Chin", Vector3.new(0.9, 0.55, 0.6), cf(0, headY - 0.85, -1.15) * rot(25, 0, 0), SKIN_SHADE)
	block(m, "Mouth", Vector3.new(0.8, 0.12, 0.08), cf(0, headY - 0.45, -1.38), MOUTH)
	block(m, "Tooth", Vector3.new(0.14, 0.24, 0.08), cf(0.18, headY - 0.53, -1.4), TOOTH)
	-- Nos: z trzech klocków, opada w dół
	block(m, "Nose", Vector3.new(0.38, 0.38, 0.7), cf(0, headY + 0.05, -1.55) * rot(-10, 0, 0), IRON, { material = Enum.Material.Metal })
	block(m, "Nose", Vector3.new(0.32, 0.32, 0.6), cf(0, headY - 0.12, -2.05) * rot(-28, 0, 0), IRON, { material = Enum.Material.Metal })
	block(m, "NoseTip", Vector3.new(0.26, 0.36, 0.3), cf(0, headY - 0.42, -2.3) * rot(-55, 0, 0), IRON_DARK, { material = Enum.Material.Metal })
	block(m, "Wart", Vector3.new(0.2, 0.2, 0.2), cf(0.5, headY + 0.1, -1.38), WART)
	for _, side in { -1, 1 } do
		block(m, "Brow", Vector3.new(0.6, 0.16, 0.2), cf(side * 0.45, headY + 0.48, -1.32) * rot(0, 0, side * -16), HAIR)
		block(m, "Eye", Vector3.new(0.32, 0.26, 0.1), cf(side * 0.42, headY + 0.25, -1.38), if awake then Jaga.EYE_COLOR else Jaga.EYE_SLEEP, { neon = true })
		-- Siwe kosmyki spod chusty
		rod(m, "Hair", Vector3.new(side * 0.85, headY + 0.4, -0.7), Vector3.new(side * 1.05, headY - 1.1, -0.4), 0.22, HAIR)
		rod(m, "Hair", Vector3.new(side * 0.75, headY + 0.2, -0.2), Vector3.new(side * 1.0, headY - 1.3, 0.1), 0.2, HAIR)
	end
	local eyeLight = Instance.new("PointLight")
	eyeLight.Name = "EyeLight"
	eyeLight.Color = Jaga.EYE_COLOR
	eyeLight.Range = 14
	eyeLight.Brightness = if awake then 1.6 else 0
	eyeLight.Shadows = false
	eyeLight.Parent = head
	-- Chusta na głowie: czapa i węzeł pod brodą
	block(m, "Scarf", Vector3.new(2.0, 1.2, 1.9), cf(0, headY + 0.75, -0.35) * rot(-12, 0, 0), SCARF, { texture = 0.55 })
	block(m, "ScarfSide", Vector3.new(2.05, 1.4, 1.1), cf(0, headY - 0.1, 0.0) * rot(-12, 0, 0), SCARF_DARK, { texture = 0.6 })
	block(m, "Knot", Vector3.new(0.6, 0.45, 0.45), cf(0, headY - 1.25, -0.95), SCARF_DARK)
	for _, side in { -1, 1 } do
		block(m, "KnotEnd", Vector3.new(0.3, 0.7, 0.2), cf(side * 0.3, headY - 1.65, -0.95) * rot(0, 0, side * 20), SCARF)
	end
	for i, x in { -0.6, 0.2, 0.7 } do
		block(m, "Flower", Vector3.new(0.28, 0.08, 0.28), cf(x, headY + 1.36, -0.3 + i * 0.2), FLOWER)
	end

	-- ===== Ręce: prawa wiosłuje tłuczkiem, lewa trzyma miotłę za plecami =====
	for _, side in { -1, 1 } do
		block(m, "Sleeve", Vector3.new(0.75, 1.5, 0.75), cf(side * 1.3, body + 1.9, -0.3) * rot(30, 0, side * 12), DRESS_DARK, { texture = 0.6 })
		block(m, "Hand", Vector3.new(0.55, 0.55, 0.55), cf(side * 1.5, body + 1.2, -0.95), SKIN_SHADE)
	end
	-- Tłuczek: gruby kij wbity w powietrze jak wiosło
	rod(m, "Pestle", Vector3.new(1.55, body + 3.2, -1.3), Vector3.new(1.9, base - 0.6, 0.2), 0.42, WOOD_RIM, { texture = 0.6 })
	block(m, "PestleHead", Vector3.new(0.8, 0.9, 0.8), cf(1.93, base - 0.9, 0.35), WOOD_DARK, { texture = 0.6 })
	-- Miotła: kij od lewej dłoni do tyłu, wiązka słomy przy ziemi
	local stickFrom = Vector3.new(-1.5, body + 1.2, -0.9)
	local stickTo = Vector3.new(-1.9, 0.9, 4.2)
	rod(m, "Broom", stickFrom, stickTo, 0.24, WOOD)
	local bristles = CFrame.lookAt(stickTo, stickTo + (stickTo - stickFrom).Unit)
	block(m, "Bristles", Vector3.new(1.1, 0.8, 1.6), bristles * cf(0, 0, -0.7), STRAW, { texture = 0.6 })
	block(m, "BristleTie", Vector3.new(0.8, 0.6, 0.2), bristles * cf(0, 0, 0.15), STRAW_DARK)
	block(m, "BristleEnd", Vector3.new(1.4, 0.4, 0.5), bristles * cf(0, -0.1, -1.5), STRAW_DARK)

	-- Pył i iskry spod moździerza (tylko gdy leci)
	local dust = block(m, "Dust", Vector3.new(0.3, 0.3, 0.3), cf(0, base - 0.2, 0), WOOD, { transparency = 1 })
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Smoke"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(rgb(110, 100, 120), rgb(60, 50, 70))
	smoke.LightInfluence = 0.8
	smoke.Size = NumberSequence.new(1.2, 3)
	smoke.Transparency = NumberSequence.new(0.5, 1)
	smoke.Lifetime = NumberRange.new(0.8, 1.4)
	smoke.Rate = 18
	smoke.Speed = NumberRange.new(1, 2.5)
	smoke.EmissionDirection = Enum.NormalId.Bottom
	smoke.Enabled = awake
	smoke.Parent = dust
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Sparks"
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(rgb(190, 255, 110), rgb(255, 180, 80))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.35, 0)
	sparks.Lifetime = NumberRange.new(0.4, 0.8)
	sparks.Rate = 14
	sparks.Speed = NumberRange.new(2, 5)
	sparks.SpreadAngle = Vector2.new(40, 40)
	sparks.EmissionDirection = Enum.NormalId.Bottom
	sparks.Enabled = awake
	sparks.Parent = dust

	m:PivotTo(at)
	m.Parent = parent
	return m
end

-- Budzi albo usypia (Jaga drzemiąca w moździerzu przy chatce otwiera oczy, gdy ktoś jest goniony)
function Jaga.setAwake(m: Model, awake: boolean)
	m:SetAttribute("Awake", awake)
	for _, child in m:GetChildren() do
		if child.Name == "Eye" and child:IsA("BasePart") then
			child.Color = if awake then Jaga.EYE_COLOR else Jaga.EYE_SLEEP
		end
	end
	local head = m:FindFirstChild("Head")
	local eyeLight = head and head:FindFirstChild("EyeLight")
	if eyeLight and eyeLight:IsA("PointLight") then
		eyeLight.Brightness = if awake then 1.6 else 0
	end
	local dust = m:FindFirstChild("Dust")
	if dust then
		for _, emitter in dust:GetChildren() do
			if emitter:IsA("ParticleEmitter") then
				emitter.Enabled = awake
			end
		end
	end
end

return Jaga
