--!strict
-- Skarbnik: duch kopalni ze śląskich legend, strażnik podziemnych skarbów.
-- Przygarbiony stary górnik w długim czarnym płaszczu z kapturem, z siwą brodą do pasa,
-- w kasku z lampką, z kilofem na ramieniu i zieloną latarnią w ręce. Oczy świecą na zielono.
-- Ten sam model służy jako uśpiony posąg w skarbcu i jako goniący duch.
-- Pivot modelu leży na ziemi pod stopami, przód to -Z (jak w CFrame.lookAt).

local Palette = require(script.Parent.Palette)

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

-- Buduje Skarbnika stojącego w `at` (pivot na ziemi). awake = świecące oczy i latarnia.
function Skarbnik.build(parent: Instance, at: CFrame, awake: boolean): Model
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

-- Budzi albo usypia (posąg w skarbcu świeci oczami i latarnią, gdy ktoś jest goniony)
function Skarbnik.setAwake(m: Model, awake: boolean)
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
