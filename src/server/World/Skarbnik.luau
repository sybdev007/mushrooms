--!strict
-- Skarbnik: duch kopalni ze śląskich legend, strażnik podziemnych skarbów.
-- Stary górnik w czarnym mundurze z mosiężnymi guzikami i w wysokim czaku z pióropuszem,
-- z siwą brodą, kilofem i latarnią z zielonym płomieniem. Oczy świecą na zielono.
-- Model to siatka z teksturą wygenerowana w Studio (asset na koncie Toma); gdy nie da się jej
-- wczytać, składamy prostszego Skarbnika z klocków. Do siatki dokładamy niewidzialne punkty
-- ze światłem oczu i latarni oraz zieloną mgiełkę u stóp, które zapalają się, gdy się budzi.
-- Ten sam model służy jako uśpiony posąg w skarbcu i jako goniący duch.
-- Pivot modelu leży na ziemi pod stopami, przód to -Z (jak w CFrame.lookAt).

local InsertService = game:GetService("InsertService")

local Palette = require(script.Parent.Palette)

-- Siatka i tekstura Skarbnika oraz rozmiar w studs (proporcje z generatora: 5 x 5,44 x 2,68)
local MESH = {
	mesh = "rbxassetid://101040825190035",
	texture = "rbxassetid://135852801418456",
	size = Vector3.new(8.3, 9, 4.4),
}

local Skarbnik = {}

local VERTICAL = CFrame.Angles(0, 0, math.rad(90))

Skarbnik.EYE_COLOR = Color3.fromRGB(120, 255, 120)
Skarbnik.EYE_SLEEP = Color3.fromRGB(30, 60, 34)
local GHOST_FLAME = Color3.fromRGB(110, 255, 150)
local CLOAK = Color3.fromRGB(34, 32, 40)
local CLOAK_EDGE = Color3.fromRGB(54, 50, 62)
local BEARD = Color3.fromRGB(214, 210, 200)
local SKIN = Color3.fromRGB(150, 160, 150)
local HELMET = Color3.fromRGB(180, 140, 50)

local function part(m: Model, name: string, size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?, className: string?): BasePart
	local p = Instance.new(className or "Part") :: BasePart
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape and p:IsA("Part") then
		p.Shape = shape
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Parent = m
	return p
end

-- Prostszy Skarbnik z klocków, gdy siatki nie da się wczytać
local function buildParts(parent: Instance, at: CFrame, awake: boolean): Model
	local m = Instance.new("Model")
	m.Name = "Skarbnik"

	local root = part(m, "Root", Vector3.new(2, 1, 2), CFrame.new(0, 0.5, 0), CLOAK)
	root.Transparency = 1

	-- Długi płaszcz rozszerzający się ku ziemi (kliny tworzą poły), w środku ciemność
	part(m, "Robe", Vector3.new(4.2, 6.5, 3), CFrame.new(0, 3.6, 0.2), CLOAK)
	for _, side in { -1, 1 } do
		part(m, "RobeFlap", Vector3.new(1.2, 6, 3.2), CFrame.new(side * 2.4, 3.1, 0.2) * CFrame.Angles(0, 0, math.rad(side * 8)), CLOAK_EDGE)
	end
	part(m, "Belt", Vector3.new(4.4, 0.5, 3.2), CFrame.new(0, 5.2, 0.2), Color3.fromRGB(70, 46, 30))
	part(m, "Buckle", Vector3.new(0.8, 0.6, 0.2), CFrame.new(0, 5.2, -1.45), HELMET).Material = Enum.Material.Metal

	-- Garb i ramiona
	part(m, "Shoulders", Vector3.new(4.6, 2.2, 3), CFrame.new(0, 7.8, 0.5) * CFrame.Angles(math.rad(12), 0, 0), CLOAK)

	-- Głowa wysunięta do przodu (przygarbiony), kaptur, broda do pasa
	local head = part(m, "Head", Vector3.new(1.9, 2, 1.8), CFrame.new(0, 9, -0.9), SKIN)
	part(m, "Hood", Vector3.new(2.7, 2.6, 2.6), CFrame.new(0, 9.3, -0.4), CLOAK, Enum.PartType.Ball)
	part(m, "Beard", Vector3.new(1.8, 3.6, 0.8), CFrame.new(0, 6.9, -1.6) * CFrame.Angles(math.rad(-8), 0, 0), BEARD)
	part(m, "Moustache", Vector3.new(2, 0.5, 0.5), CFrame.new(0, 8.5, -1.85), BEARD)
	part(m, "Nose", Vector3.new(0.5, 0.8, 0.6), CFrame.new(0, 8.95, -1.9), SKIN)

	-- Kask górnika z lampką
	part(m, "Helmet", Vector3.new(0.9, 2.4, 2.4), CFrame.new(0, 10.35, -0.8) * VERTICAL, HELMET, Enum.PartType.Cylinder).Material = Enum.Material.Metal
	part(m, "HelmetBrim", Vector3.new(0.2, 2.9, 2.9), CFrame.new(0, 9.95, -0.8) * VERTICAL, HELMET, Enum.PartType.Cylinder).Material = Enum.Material.Metal
	local lamp = part(m, "HelmetLamp", Vector3.new(0.6, 0.6, 0.4), CFrame.new(0, 10.4, -2), GHOST_FLAME)
	lamp.Material = Enum.Material.Neon

	local eyeColor = if awake then Skarbnik.EYE_COLOR else Skarbnik.EYE_SLEEP
	for _, side in { -1, 1 } do
		local eye = part(m, "Eye", Vector3.new(0.38, 0.38, 0.38), CFrame.new(side * 0.45, 9.2, -1.8), eyeColor, Enum.PartType.Ball)
		eye.Material = Enum.Material.Neon
		eye.CastShadow = false
	end
	local eyeLight = Instance.new("PointLight")
	eyeLight.Name = "EyeLight"
	eyeLight.Color = Skarbnik.EYE_COLOR
	eyeLight.Range = 16
	eyeLight.Brightness = if awake then 2 else 0
	eyeLight.Parent = head

	-- Prawa ręka z latarnią z zielonym płomieniem
	local rightArm = CFrame.new(2.4, 7.4, -0.4) * CFrame.Angles(math.rad(-35), 0, math.rad(-10)) * CFrame.new(0, -1.6, 0)
	part(m, "Arm", Vector3.new(3.4, 1, 1), rightArm * VERTICAL, CLOAK, Enum.PartType.Cylinder)
	local hand = rightArm * CFrame.new(0, -1.9, 0)
	part(m, "Hand", Vector3.new(0.8, 0.8, 0.8), hand, SKIN, Enum.PartType.Ball)
	local lanternTop = hand.Position + Vector3.new(0, -0.6, -0.2)
	part(m, "LanternHandle", Vector3.new(0.1, 0.6, 0.1), CFrame.new(lanternTop + Vector3.new(0, -0.3, 0)), Palette.metal)
	part(m, "LanternCap", Vector3.new(1, 0.25, 1), CFrame.new(lanternTop + Vector3.new(0, -0.7, 0)), Palette.metal)
	local flame = part(m, "Flame", Vector3.new(0.75, 1, 0.75), CFrame.new(lanternTop + Vector3.new(0, -1.3, 0)), GHOST_FLAME)
	flame.Material = Enum.Material.Neon
	part(m, "LanternBase", Vector3.new(0.95, 0.22, 0.95), CFrame.new(lanternTop + Vector3.new(0, -1.9, 0)), Palette.metal)
	local flameLight = Instance.new("PointLight")
	flameLight.Name = "FlameLight"
	flameLight.Color = GHOST_FLAME
	flameLight.Range = 20
	flameLight.Brightness = if awake then 2.5 else 0.4
	flameLight.Parent = flame

	-- Lewa ręka trzyma kilof opartym o ramię
	local leftArm = CFrame.new(-2.4, 7.4, -0.2) * CFrame.Angles(math.rad(-50), 0, math.rad(15)) * CFrame.new(0, -1.5, 0)
	part(m, "Arm", Vector3.new(3.2, 1, 1), leftArm * VERTICAL, CLOAK, Enum.PartType.Cylinder)
	local leftHand = leftArm * CFrame.new(0, -1.8, 0)
	part(m, "Hand", Vector3.new(0.8, 0.8, 0.8), leftHand, SKIN, Enum.PartType.Ball)
	local handle = CFrame.new(leftHand.Position) * CFrame.Angles(math.rad(-20), 0, math.rad(-35)) * CFrame.new(0, 1.8, 0)
	part(m, "PickHandle", Vector3.new(0.3, 5, 0.3), handle, Palette.log)
	local head1 = handle * CFrame.new(0, 2.4, 0)
	part(m, "PickHead", Vector3.new(3.4, 0.4, 0.4), head1 * CFrame.Angles(0, 0, math.rad(8)), Palette.metal).Material = Enum.Material.Metal

	m.PrimaryPart = root
	m.WorldPivot = CFrame.new()
	m:PivotTo(at)
	m.Parent = parent
	return m
end

-- Siatkę wczytujemy raz i potem klonujemy (każdy pościg ma własnego Skarbnika)
local template: MeshPart? = nil
local templateFailed = false

local function meshTemplate(): MeshPart?
	if template or templateFailed then
		return template
	end
	local ok, result = pcall(function()
		return InsertService:CreateMeshPartAsync(MESH.mesh, Enum.CollisionFidelity.Box, Enum.RenderFidelity.Automatic)
	end)
	if ok and result then
		local meshPart = result :: MeshPart
		meshPart.TextureID = MESH.texture
		meshPart.Size = MESH.size
		meshPart.Anchored = true
		meshPart.CanCollide = false
		meshPart.CanTouch = false
		meshPart.CanQuery = false
		template = meshPart
	else
		templateFailed = true
		warn("[Skarbnik] Nie udało się wczytać siatki, składam z klocków:", result)
	end
	return template
end

-- Niewidzialny punkt na światło (oczy, latarnia), w układzie modelu
local function lightPoint(m: Model, name: string, offset: Vector3, color: Color3, range: number, brightness: number): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.CFrame = CFrame.new(offset)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Parent = m
	local light = Instance.new("PointLight")
	light.Name = "Light"
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Parent = p
	return p
end

-- Buduje Skarbnika stojącego w `at` (pivot na ziemi). awake = świecące oczy, latarnia i mgiełka.
function Skarbnik.build(parent: Instance, at: CFrame, awake: boolean): Model
	local source = meshTemplate()
	if not source then
		return buildParts(parent, at, awake)
	end
	local m = Instance.new("Model")
	m.Name = "Skarbnik"
	local size = MESH.size
	local body = source:Clone()
	body.Name = "Body"
	body.CFrame = CFrame.new(0, size.Y / 2, 0)
	body.Parent = m

	-- Oczy pod rondem czaka, latarnia w prawej ręce (po lewej stronie, gdy patrzymy na niego z przodu)
	lightPoint(m, "EyeGlow", Vector3.new(0, size.Y * 0.6, -size.Z * 0.45), Skarbnik.EYE_COLOR, 16, if awake then 2 else 0)
	lightPoint(m, "LanternGlow", Vector3.new(-size.X * 0.42, size.Y * 0.26, -size.Z * 0.2), GHOST_FLAME, 20, if awake then 2.5 else 0.6)

	-- Zielona mgiełka wokół stóp, gdy duch się budzi
	local feet = lightPoint(m, "Mist", Vector3.new(0, 0.4, 0), GHOST_FLAME, 10, 0)
	local mist = Instance.new("ParticleEmitter")
	mist.Name = "GhostMist"
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Color = ColorSequence.new(GHOST_FLAME)
	mist.LightEmission = 0.8
	mist.Size = NumberSequence.new(1.5, 4)
	mist.Transparency = NumberSequence.new(0.5, 1)
	mist.Lifetime = NumberRange.new(1, 2)
	mist.Rate = 12
	mist.Speed = NumberRange.new(0.5, 1.5)
	mist.SpreadAngle = Vector2.new(180, 20)
	mist.Enabled = awake
	mist.Parent = feet

	local root = lightPoint(m, "Root", Vector3.new(0, 0.5, 0), GHOST_FLAME, 0, 0)
	m.PrimaryPart = root
	m.WorldPivot = CFrame.new()
	m:PivotTo(at)
	m.Parent = parent
	return m
end

-- Budzi albo usypia (posąg w skarbcu świeci oczami i latarnią, gdy ktoś jest goniony)
function Skarbnik.setAwake(m: Model, awake: boolean)
	-- Wersja z siatki: światła w niewidzialnych punktach i mgiełka
	local eyeGlow = m:FindFirstChild("EyeGlow")
	if eyeGlow then
		local eye = eyeGlow:FindFirstChild("Light")
		if eye and eye:IsA("PointLight") then
			eye.Brightness = if awake then 2 else 0
		end
		local lanternGlow = m:FindFirstChild("LanternGlow")
		local lantern = lanternGlow and lanternGlow:FindFirstChild("Light")
		if lantern and lantern:IsA("PointLight") then
			lantern.Brightness = if awake then 2.5 else 0.6
		end
		local feet = m:FindFirstChild("Mist")
		local mist = feet and feet:FindFirstChild("GhostMist")
		if mist and mist:IsA("ParticleEmitter") then
			mist.Enabled = awake
		end
		return
	end
	-- Wersja z klocków
	for _, child in m:GetChildren() do
		if child.Name == "Eye" and child:IsA("BasePart") then
			child.Color = if awake then Skarbnik.EYE_COLOR else Skarbnik.EYE_SLEEP
		end
	end
	local head = m:FindFirstChild("Head")
	local eyeLight = head and head:FindFirstChild("EyeLight")
	if eyeLight and eyeLight:IsA("PointLight") then
		eyeLight.Brightness = if awake then 2 else 0
	end
	local flame = m:FindFirstChild("Flame")
	local flameLight = flame and flame:FindFirstChild("FlameLight")
	if flameLight and flameLight:IsA("PointLight") then
		flameLight.Brightness = if awake then 2.5 else 0.4
	end
end

return Skarbnik
