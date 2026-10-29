--!strict
-- Skarbnik: duch kopalni ze śląskich legend, strażnik podziemnych skarbów.
-- Stary, przygarbiony górnik-duch w czarnym galowym mundurze z mosiężnymi guzikami i naramiennikami,
-- w wysokim czaku z odznaką (skrzyżowane młotki) i zielonym pióropuszem. Blada, zielonkawa twarz,
-- krzaczaste brwi i długa siwa broda; oczy świecą na zielono. W prawej ręce kilof, w lewej latarnia
-- z zielonym, upiornym płomieniem, a u stóp zielona mgiełka, gdy się budzi.
-- Klocki z pikselową kratką i szkielet jak u Leszego (RigBlocks): klient animuje chód, bieg i drzemkę.
-- Ten sam model to uśpiony posąg w skarbcu, goniący duch i portret w Grzybopedii.
-- Pivot leży na ziemi pod stopami, przód to -Z (jak w CFrame.lookAt).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local RigBlocks = require(script.Parent.RigBlocks)

local Skarbnik = {}

Skarbnik.EYE_COLOR = Color3.fromRGB(120, 255, 140)
Skarbnik.EYE_SLEEP = Color3.fromRGB(30, 60, 34)

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local GHOST = rgb(110, 255, 150)
local COAT = rgb(30, 30, 38)
local COAT_EDGE = rgb(30, 58, 42) -- aksamitny kołnierz i wyłogi (ciemna zieleń)
local VISOR = rgb(14, 14, 18)
local BRASS = rgb(214, 170, 66)
local BRASS_DARK = rgb(150, 112, 42)
local TROUSER = rgb(22, 22, 28)
local BOOT = rgb(36, 28, 24)
local LEATHER = rgb(62, 42, 30)
local SKIN = rgb(170, 186, 172)
local SKIN_SHADE = rgb(132, 150, 136)
local NOSE = rgb(178, 160, 156)
local BEARD = rgb(228, 226, 216)
local BEARD_SHADE = rgb(188, 188, 178)
local SOCKET = rgb(12, 18, 14)
local PLUME = rgb(84, 214, 116)
local PLUME_LIGHT = rgb(150, 255, 170)
local IRON = rgb(112, 114, 122)
local IRON_DARK = rgb(78, 80, 88)
local WOOD = rgb(112, 78, 50)

local function cf(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

local function rot(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

-- Buduje Skarbnika stojącego w `at` (pivot na ziemi). awake = świecące oczy, jasna latarnia i mgiełka.
function Skarbnik.build(parent: Instance, at: CFrame, awake: boolean): Model
	local b = RigBlocks.new("Skarbnik", awake)
	local block = RigBlocks.block

	RigBlocks.joint(b, "Hips", Vector3.new(0, 4.2, 0))
	RigBlocks.joint(b, "Torso", Vector3.new(0, 4.7, 0))
	RigBlocks.joint(b, "Head", Vector3.new(0, 8.3, -0.2))

	-- ===== Biodra: pas z klamrą i poły munduru =====
	block(b, "Pelvis", "Hips", Vector3.new(2.6, 1.0, 1.7), cf(0, 4.3, 0), COAT, { texture = 0.6 })
	block(b, "Belt", "Hips", Vector3.new(2.75, 0.35, 1.85), cf(0, 4.85, 0), LEATHER)
	block(b, "Buckle", "Hips", Vector3.new(0.6, 0.45, 0.12), cf(0, 4.85, -0.95), BRASS)
	block(b, "CoatFront", "Hips", Vector3.new(2.8, 1.6, 0.25), cf(0, 3.75, -0.9) * rot(-4, 0, 0), COAT, { texture = 0.6 })
	block(b, "CoatTails", "Hips", Vector3.new(2.9, 2.5, 0.25), cf(0, 3.4, 0.95) * rot(-6, 0, 0), COAT, { texture = 0.6 })
	block(b, "TailEdge", "Hips", Vector3.new(2.92, 0.25, 0.28), cf(0, 2.2, 1.1) * rot(-6, 0, 0), COAT_EDGE)

	-- ===== Tułów: mundur z dwoma rzędami guzików, garb, naramienniki =====
	block(b, "Chest", "Torso", Vector3.new(2.9, 3.0, 1.9), cf(0, 6.4, 0), COAT, { texture = 0.6 })
	block(b, "Hump", "Torso", Vector3.new(2.4, 1.5, 0.6), cf(0, 7.4, 0.95) * rot(10, 0, 0), COAT, { texture = 0.6 })
	block(b, "Lapel", "Torso", Vector3.new(1.9, 2.6, 0.12), cf(0, 6.5, -0.98), COAT_EDGE)
	for _, x in { -0.75, 0.75 } do
		for _, y in { 5.3, 6.0, 6.7, 7.4 } do
			block(b, "Button", "Torso", Vector3.new(0.28, 0.28, 0.12), cf(x, y, -1.06), BRASS)
		end
	end
	block(b, "Collar", "Torso", Vector3.new(1.9, 0.5, 1.6), cf(0, 8.05, -0.05), COAT_EDGE)
	for _, side in { -1, 1 } do
		block(b, "Epaulette", "Torso", Vector3.new(1.0, 0.3, 1.3), cf(side * 1.45, 7.95, 0), BRASS)
		for _, z in { -0.45, 0, 0.45 } do
			block(b, "Fringe", "Torso", Vector3.new(0.14, 0.4, 0.14), cf(side * 1.9, 7.65, z), BRASS_DARK)
		end
	end

	-- ===== Głowa: blada twarz, brwi, nos, wąsy i broda =====
	block(b, "Neck", "Head", Vector3.new(0.9, 0.6, 0.9), cf(0, 8.4, -0.1), SKIN_SHADE)
	local head = block(b, "Head", "Head", Vector3.new(1.9, 2.0, 1.8), cf(0, 9.4, -0.25), SKIN, { texture = 0.75 })
	local eyeColor = if awake then Skarbnik.EYE_COLOR else Skarbnik.EYE_SLEEP
	for _, side in { -1, 1 } do
		block(b, "Socket", "Head", Vector3.new(0.6, 0.45, 0.1), cf(side * 0.45, 9.65, -1.16), SOCKET)
		block(b, "Eye", "Head", Vector3.new(0.36, 0.26, 0.08), cf(side * 0.45, 9.63, -1.2), eyeColor, { neon = true })
		block(b, "Brow", "Head", Vector3.new(0.75, 0.25, 0.3), cf(side * 0.45, 10.0, -1.12) * rot(0, 0, side * -12), BEARD)
		block(b, "Hair", "Head", Vector3.new(0.3, 0.9, 1.2), cf(side * 0.98, 9.3, 0), BEARD)
	end
	block(b, "Nose", "Head", Vector3.new(0.4, 0.6, 0.45), cf(0, 9.25, -1.3), NOSE)
	block(b, "Mustache", "Head", Vector3.new(1.5, 0.35, 0.3), cf(0, 8.85, -1.25), BEARD)
	block(b, "Beard", "Head", Vector3.new(1.7, 1.6, 0.5), cf(0, 8.0, -1.15), BEARD, { texture = 0.7 })
	block(b, "Beard", "Head", Vector3.new(1.2, 1.0, 0.45), cf(0, 6.9, -1.2), BEARD, { texture = 0.7 })
	block(b, "BeardTip", "Head", Vector3.new(0.6, 0.7, 0.4), cf(0, 6.15, -1.22), BEARD_SHADE)
	RigBlocks.light(head, "EyeLight", Skarbnik.EYE_COLOR, 16, if awake then 2 else 0)

	-- Czako z daszkiem, odznaką i pióropuszem
	block(b, "HatBand", "Head", Vector3.new(2.1, 0.35, 2.0), cf(0, 10.45, -0.2), COAT)
	block(b, "Hat", "Head", Vector3.new(1.75, 1.7, 1.75), cf(0, 11.4, -0.2), COAT, { texture = 0.6 })
	block(b, "HatTop", "Head", Vector3.new(1.95, 0.25, 1.95), cf(0, 12.3, -0.2), BRASS_DARK)
	block(b, "Visor", "Head", Vector3.new(1.8, 0.15, 0.8), cf(0, 10.35, -1.25) * rot(-12, 0, 0), VISOR)
	block(b, "BadgePlate", "Head", Vector3.new(0.7, 0.7, 0.06), cf(0, 11.35, -1.1), BRASS_DARK)
	block(b, "Hammer", "Head", Vector3.new(0.12, 0.8, 0.08), cf(0, 11.35, -1.15) * rot(0, 0, 40), BRASS)
	block(b, "Hammer", "Head", Vector3.new(0.12, 0.8, 0.08), cf(0, 11.35, -1.15) * rot(0, 0, -40), BRASS)
	for i, feather in { { -0.25, -18, 1.7 }, { 0, 0, 2.0 }, { 0.25, 18, 1.7 }, { -0.12, -8, 1.5 }, { 0.12, 8, 1.5 } } do
		local tilt = feather[2]
		local length = feather[3]
		local color = if i <= 3 then PLUME else PLUME_LIGHT
		block(b, "Plume", "Head", Vector3.new(0.26, length, 0.26), cf(feather[1], 12.4, -0.75) * rot(12, 0, tilt) * cf(0, length / 2, 0), color)
	end

	-- ===== Ręce: rękawy munduru, mosiężne mankiety, duże blade dłonie =====
	for _, side in { -1, 1 } do
		local tag = if side < 0 then "L" else "R"
		local upper, fore = "UpperArm" .. tag, "Forearm" .. tag
		RigBlocks.joint(b, upper, Vector3.new(side * 1.85, 7.6, 0))
		RigBlocks.joint(b, fore, Vector3.new(side * 2.05, 5.8, 0))
		block(b, "Sleeve", upper, Vector3.new(0.95, 2.1, 0.95), cf(side * 1.95, 6.75, 0) * rot(0, 0, side * 5), COAT, { texture = 0.6 })
		block(b, "Sleeve", fore, Vector3.new(0.85, 1.6, 0.85), cf(side * 2.1, 5.0, 0), COAT, { texture = 0.6 })
		block(b, "Cuff", fore, Vector3.new(0.95, 0.35, 0.95), cf(side * 2.12, 4.35, 0), COAT_EDGE)
		block(b, "CuffButton", fore, Vector3.new(0.2, 0.2, 0.1), cf(side * 2.12, 4.35, -0.5), BRASS)
		block(b, "Hand", fore, Vector3.new(0.9, 0.8, 0.9), cf(side * 2.15, 3.8, -0.05), SKIN)
		for _, dz in { -0.3, 0, 0.3 } do
			block(b, "Finger", fore, Vector3.new(0.22, 0.5, 0.22), cf(side * 2.2, 3.25, -0.05 + dz), SKIN_SHADE)
		end
	end
	-- Kilof w prawej ręce: trzonek w dół i do przodu, żelazny grot przy ziemi
	RigBlocks.rod(b, "Handle", "ForearmR", Vector3.new(2.15, 4.4, -0.15), Vector3.new(2.25, 0.9, -1.0), 0.26, WOOD)
	block(b, "PickHead", "ForearmR", Vector3.new(0.34, 0.34, 2.2), cf(2.25, 0.95, -1.0) * rot(14, 0, 0), IRON, { texture = 0.6 })
	block(b, "PickTip", "ForearmR", Vector3.new(0.22, 0.22, 0.5), cf(2.25, 0.82, -2.25) * rot(30, 0, 0), IRON_DARK)
	block(b, "PickTip", "ForearmR", Vector3.new(0.22, 0.22, 0.5), cf(2.25, 1.22, 0.2) * rot(-10, 0, 0), IRON_DARK)
	-- Latarnia w lewej ręce z upiornym płomieniem
	block(b, "LanternRing", "ForearmL", Vector3.new(0.1, 0.4, 0.4), cf(-2.15, 3.35, -0.1), BRASS)
	block(b, "LanternCap", "ForearmL", Vector3.new(0.75, 0.25, 0.75), cf(-2.15, 3.05, -0.1), BRASS_DARK)
	block(b, "LanternGlass", "ForearmL", Vector3.new(0.62, 0.85, 0.62), cf(-2.15, 2.5, -0.1), GHOST, { transparency = 0.55, material = Enum.Material.Glass })
	for _, corner in { { -0.3, -0.3 }, { 0.3, -0.3 }, { -0.3, 0.3 }, { 0.3, 0.3 } } do
		block(b, "LanternPost", "ForearmL", Vector3.new(0.1, 0.85, 0.1), cf(-2.15 + corner[1], 2.5, -0.1 + corner[2]), BRASS_DARK)
	end
	local flame = block(b, "Flame", "ForearmL", Vector3.new(0.28, 0.45, 0.28), cf(-2.15, 2.45, -0.1), GHOST, { neon = true })
	block(b, "LanternBase", "ForearmL", Vector3.new(0.8, 0.2, 0.8), cf(-2.15, 1.98, -0.1), BRASS_DARK)
	RigBlocks.light(flame, "FlameLight", GHOST, 18, if awake then 2.5 else 0.6)

	-- ===== Nogi: spodnie i wysokie buty =====
	for _, side in { -1, 1 } do
		local tag = if side < 0 then "L" else "R"
		local thigh, shin = "Thigh" .. tag, "Shin" .. tag
		RigBlocks.joint(b, thigh, Vector3.new(side * 0.75, 4.1, 0))
		RigBlocks.joint(b, shin, Vector3.new(side * 0.8, 2.1, 0))
		block(b, "Thigh", thigh, Vector3.new(1.05, 2.0, 1.1), cf(side * 0.8, 3.15, 0), TROUSER, { texture = 0.6 })
		block(b, "Knee", shin, Vector3.new(1.1, 0.5, 1.15), cf(side * 0.8, 2.1, 0), TROUSER)
		block(b, "Boot", shin, Vector3.new(0.98, 1.45, 1.02), cf(side * 0.82, 1.25, 0), BOOT, { texture = 0.6 })
		block(b, "BootTop", shin, Vector3.new(1.12, 0.3, 1.14), cf(side * 0.82, 1.95, 0), LEATHER)
		block(b, "Foot", shin, Vector3.new(1.1, 0.5, 1.75), cf(side * 0.82, 0.25, -0.32), BOOT)
	end

	-- Zielona mgiełka wokół stóp, gdy duch się budzi
	local feet = block(b, "Mist", "Hips", Vector3.new(0.2, 0.2, 0.2), cf(0, 0.4, 0), GHOST, { transparency = 1 })
	local mist = Instance.new("ParticleEmitter")
	mist.Name = "GhostMist"
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Color = ColorSequence.new(GHOST)
	mist.LightEmission = 0.8
	mist.Size = NumberSequence.new(1.5, 4)
	mist.Transparency = NumberSequence.new(0.5, 1)
	mist.Lifetime = NumberRange.new(1, 2)
	mist.Rate = 12
	mist.Speed = NumberRange.new(0.5, 1.5)
	mist.SpreadAngle = Vector2.new(180, 20)
	mist.Enabled = awake
	mist.Parent = feet

	return RigBlocks.finish(b, parent, at, (Config :: any).Skarbnik.speed or 25)
end

-- Budzi albo usypia (posąg w skarbcu świeci oczami i latarnią, gdy ktoś jest goniony)
function Skarbnik.setAwake(m: Model, awake: boolean)
	m:SetAttribute("Awake", awake)
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
		flameLight.Brightness = if awake then 2.5 else 0.6
	end
	local feet = m:FindFirstChild("Mist")
	local mist = feet and feet:FindFirstChild("GhostMist")
	if mist and mist:IsA("ParticleEmitter") then
		mist.Enabled = awake
	end
end

return Skarbnik
