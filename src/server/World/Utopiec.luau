--!strict
-- Utopiec: wodnik z polskich i śląskich legend. Przygarbiony żabi stwór o zielonej, cętkowanej skórze
-- z brodawkami, z jasnym brzuchem, wyłupiastymi świecącymi oczami i szerokim pyskiem pełnym ząbków.
-- Nosi czerwoną spiczastą czapkę i postrzępiony zielony frak, a z głowy i ramion zwisają mu wodorosty.
-- Ma długie ręce i błoniaste łapy; w lewej niesie odwrócony gliniany garnek, pod którym trzyma
-- dusze topielców (świeci na turkusowo). Kiedy się budzi, kapie z niego woda.
-- Klocki z pikselową kratką i szkielet jak u Leszego (RigBlocks): klient animuje chód, bieg i drzemkę.
-- Pivot leży na ziemi pod stopami, przód to -Z (jak w CFrame.lookAt).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local RigBlocks = require(script.Parent.RigBlocks)

local Utopiec = {}

Utopiec.EYE_COLOR = Color3.fromRGB(214, 255, 80)
Utopiec.EYE_SLEEP = Color3.fromRGB(70, 86, 34)

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local SKIN = rgb(88, 140, 72)
local SKIN_DARK = rgb(60, 104, 56)
local SPOT = rgb(42, 74, 44)
local WART = rgb(118, 164, 86)
local BELLY = rgb(198, 208, 140)
local BELLY_SHADE = rgb(170, 184, 118)
local COAT = rgb(38, 74, 70)
local COAT_EDGE = rgb(26, 54, 52)
local BUTTON = rgb(196, 160, 70)
local CAP = rgb(206, 52, 40)
local CAP_SHADE = rgb(158, 36, 30)
local EYE_WHITE = rgb(232, 228, 182)
local PUPIL = rgb(12, 12, 10)
local MOUTH = rgb(40, 18, 24)
local TOOTH = rgb(238, 234, 212)
local WEED = { rgb(64, 110, 46), rgb(90, 132, 50), rgb(46, 86, 44) }
local POT = rgb(150, 86, 52)
local POT_DARK = rgb(112, 62, 40)
local SOUL = rgb(140, 255, 220)
local WATER = rgb(150, 220, 230)

local function cf(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

local function rot(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

-- Buduje Utopca stojącego w `at` (pivot na ziemi). awake = świecące oczy i kapiąca woda.
function Utopiec.build(parent: Instance, at: CFrame, awake: boolean): Model
	local b = RigBlocks.new("Utopiec", awake)
	local block = RigBlocks.block

	RigBlocks.joint(b, "Hips", Vector3.new(0, 3.3, 0.2))
	RigBlocks.joint(b, "Torso", Vector3.new(0, 3.8, 0.2))
	RigBlocks.joint(b, "Head", Vector3.new(0, 7.1, -0.6))

	-- ===== Biodra i poły fraka =====
	block(b, "Pelvis", "Hips", Vector3.new(3.0, 1.2, 2.4), cf(0, 3.4, 0.2), SKIN, { texture = 0.55 })
	block(b, "CoatTails", "Hips", Vector3.new(3.2, 2.4, 0.25), cf(0, 2.9, 1.45) * rot(-8, 0, 0), COAT, { texture = 0.6 })
	for i, x in { -1.2, -0.4, 0.4, 1.2 } do
		block(b, "Tatter", "Hips", Vector3.new(0.5, 0.5 + (i % 2) * 0.35, 0.22), cf(x, 1.55 - (i % 2) * 0.15, 1.62) * rot(-8, 0, 0), COAT_EDGE)
	end

	-- ===== Tułów: gruszkowaty, jasny brzuch, frak na plecach =====
	block(b, "Body", "Torso", Vector3.new(3.6, 2.2, 2.8), cf(0, 4.9, 0.1), SKIN, { texture = 0.55 })
	block(b, "Chest", "Torso", Vector3.new(3.2, 1.8, 2.5), cf(0, 6.55, -0.15) * rot(-15, 0, 0), SKIN, { texture = 0.55 })
	block(b, "Belly", "Torso", Vector3.new(2.6, 2.6, 0.2), cf(0, 5.0, -1.32), BELLY, { texture = 0.7 })
	for _, y in { 4.3, 4.95, 5.6 } do
		block(b, "BellyLine", "Torso", Vector3.new(2.3, 0.12, 0.1), cf(0, y, -1.44), BELLY_SHADE)
	end
	block(b, "CoatBack", "Torso", Vector3.new(3.4, 3.4, 0.3), cf(0, 5.6, 1.45) * rot(-6, 0, 0), COAT, { texture = 0.6 })
	for _, side in { -1, 1 } do
		block(b, "CoatSide", "Torso", Vector3.new(0.3, 3.0, 2.6), cf(side * 1.82, 5.5, 0.25), COAT, { texture = 0.6 })
		block(b, "Lapel", "Torso", Vector3.new(0.7, 2.6, 0.2), cf(side * 1.5, 5.6, -1.3), COAT_EDGE)
		for _, y in { 5.0, 5.8 } do
			block(b, "Button", "Torso", Vector3.new(0.26, 0.26, 0.12), cf(side * 1.5, y, -1.42), BUTTON)
		end
		block(b, "Shoulder", "Torso", Vector3.new(1.2, 0.7, 1.6), cf(side * 1.7, 7.0, -0.1), SKIN_DARK, { texture = 0.55 })
		-- Wodorosty zwisające z ramion
		for i, dz in { -0.5, 0.1, 0.6 } do
			local length = 1.2 + i * 0.35
			block(b, "Weed", "Torso", Vector3.new(0.26, length, 0.2), cf(side * (1.95 + i * 0.05), 6.9 - length / 2, dz), WEED[i])
		end
		block(b, "Wart", "Torso", Vector3.new(0.3, 0.2, 0.3), cf(side * 1.5, 7.38, -0.4), WART)
		block(b, "Spot", "Torso", Vector3.new(0.45, 0.08, 0.45), cf(side * 1.9, 7.36, 0.2), SPOT)
	end

	-- ===== Głowa: szeroki żabi łeb, wyłupiaste oczy, pysk z ząbkami =====
	local head = block(b, "Head", "Head", Vector3.new(3.0, 1.6, 2.6), cf(0, 7.95, -0.95), SKIN, { texture = 0.55 })
	block(b, "Jaw", "Head", Vector3.new(2.8, 0.6, 2.4), cf(0, 7.0, -1.0), BELLY, { texture = 0.7 })
	block(b, "Mouth", "Head", Vector3.new(2.6, 0.16, 0.1), cf(0, 7.32, -2.24), MOUTH)
	for i, x in { -1.0, -0.6, -0.2, 0.2, 0.6, 1.0 } do
		block(b, "Tooth", "Head", Vector3.new(0.16, 0.26 + (i % 2) * 0.1, 0.12), cf(x, 7.18, -2.26), TOOTH)
	end
	for _, side in { -1, 1 } do
		block(b, "Nostril", "Head", Vector3.new(0.14, 0.1, 0.06), cf(side * 0.3, 8.15, -2.26), MOUTH)
		block(b, "EyeBall", "Head", Vector3.new(0.95, 0.95, 0.95), cf(side * 1.0, 8.75, -1.6), EYE_WHITE)
		block(b, "Eye", "Head", Vector3.new(0.55, 0.6, 0.12), cf(side * 1.0, 8.72, -2.1), if awake then Utopiec.EYE_COLOR else Utopiec.EYE_SLEEP, { neon = true })
		block(b, "Pupil", "Head", Vector3.new(0.12, 0.48, 0.06), cf(side * 1.0, 8.72, -2.17), PUPIL)
		block(b, "Lid", "Head", Vector3.new(1.05, 0.3, 1.0), cf(side * 1.0, 9.2, -1.6) * rot(0, 0, side * 14), SKIN_DARK)
		block(b, "Spot", "Head", Vector3.new(0.4, 0.08, 0.4), cf(side * 0.9, 8.76, -0.4), SPOT)
		block(b, "Wart", "Head", Vector3.new(0.22, 0.16, 0.22), cf(side * 1.3, 8.8, -0.9), WART)
	end
	RigBlocks.light(head, "EyeLight", Utopiec.EYE_COLOR, 16, if awake then 2.2 else 0)
	-- Wodorosty zamiast włosów, z tyłu i po bokach głowy
	for i, x in { -1.2, -0.6, 0, 0.6, 1.2 } do
		local length = 1.4 + (i % 3) * 0.45
		block(b, "Weed", "Head", Vector3.new(0.34, length, 0.26), cf(x, 8.3 - length / 2, 0.3), WEED[(i % #WEED) + 1])
	end
	-- Czerwona spiczasta czapka, przekrzywiona
	block(b, "CapBrim", "Head", Vector3.new(2.5, 0.22, 2.3), cf(0, 8.82, -0.4), CAP_SHADE)
	block(b, "Cap", "Head", Vector3.new(2.3, 0.65, 2.1), cf(0, 9.25, -0.35), CAP, { texture = 0.6 })
	block(b, "Cap", "Head", Vector3.new(1.6, 0.7, 1.5), cf(0.05, 9.9, -0.25) * rot(-6, 0, -5), CAP, { texture = 0.6 })
	block(b, "Cap", "Head", Vector3.new(1.0, 0.7, 0.95), cf(0.2, 10.5, -0.1) * rot(-12, 0, -12), CAP_SHADE)
	block(b, "CapTip", "Head", Vector3.new(0.5, 0.6, 0.5), cf(0.5, 10.95, 0.1) * rot(-18, 0, -30), CAP)

	-- ===== Ręce: długie, chude, błoniaste łapy =====
	for _, side in { -1, 1 } do
		local tag = if side < 0 then "L" else "R"
		local upper, fore = "UpperArm" .. tag, "Forearm" .. tag
		RigBlocks.joint(b, upper, Vector3.new(side * 2.0, 6.5, -0.2))
		RigBlocks.joint(b, fore, Vector3.new(side * 2.3, 4.4, -0.3))
		block(b, "Sleeve", upper, Vector3.new(0.95, 1.3, 0.95), cf(side * 2.05, 6.0, -0.2), COAT)
		block(b, "Arm", upper, Vector3.new(0.75, 2.2, 0.75), cf(side * 2.15, 5.3, -0.25) * rot(0, 0, side * 8), SKIN, { texture = 0.55 })
		block(b, "Elbow", fore, Vector3.new(0.8, 0.6, 0.8), cf(side * 2.3, 4.4, -0.3), SKIN_DARK)
		block(b, "Forearm", fore, Vector3.new(0.68, 2.0, 0.68), cf(side * 2.35, 3.45, -0.35), SKIN, { texture = 0.55 })
		block(b, "Palm", fore, Vector3.new(1.0, 0.35, 1.0), cf(side * 2.4, 2.35, -0.45), SKIN_DARK)
		for _, dz in { -0.32, 0, 0.32 } do
			block(b, "Finger", fore, Vector3.new(0.2, 0.9, 0.2), cf(side * 2.4, 1.8, -0.45 + dz), SKIN_DARK)
		end
		block(b, "Web", fore, Vector3.new(0.06, 0.6, 0.75), cf(side * 2.4, 1.95, -0.45), BELLY_SHADE, { transparency = 0.25 })
	end
	-- Garnek z duszami na sznurku w lewej łapie (odwrócony, światło spod spodu)
	RigBlocks.rod(b, "Cord", "ForearmL", Vector3.new(-2.4, 2.2, -0.45), Vector3.new(-2.4, 1.5, -0.45), 0.08, COAT_EDGE)
	block(b, "Pot", "ForearmL", Vector3.new(1.0, 0.8, 1.0), cf(-2.4, 1.1, -0.45), POT, { texture = 0.6 })
	block(b, "PotFoot", "ForearmL", Vector3.new(0.6, 0.15, 0.6), cf(-2.4, 1.55, -0.45), POT_DARK)
	block(b, "PotRim", "ForearmL", Vector3.new(1.1, 0.15, 1.1), cf(-2.4, 0.66, -0.45), POT_DARK)
	local soul = block(b, "Soul", "ForearmL", Vector3.new(0.75, 0.12, 0.75), cf(-2.4, 0.56, -0.45), SOUL, { neon = true })
	RigBlocks.light(soul, "SoulLight", SOUL, 10, 1.2)

	-- ===== Nogi: grube żabie uda, błoniaste stopy =====
	for _, side in { -1, 1 } do
		local tag = if side < 0 then "L" else "R"
		local thigh, shin = "Thigh" .. tag, "Shin" .. tag
		RigBlocks.joint(b, thigh, Vector3.new(side * 1.15, 3.2, 0.2))
		RigBlocks.joint(b, shin, Vector3.new(side * 1.3, 1.7, -0.1))
		block(b, "Thigh", thigh, Vector3.new(1.4, 1.8, 1.5), cf(side * 1.22, 2.5, 0.1) * rot(0, 0, side * 14), SKIN, { texture = 0.55 })
		block(b, "Spot", thigh, Vector3.new(0.08, 0.5, 0.5), cf(side * 1.95, 2.7, 0.2), SPOT)
		block(b, "Shin", shin, Vector3.new(1.0, 1.5, 1.1), cf(side * 1.35, 1.0, -0.05), SKIN_DARK, { texture = 0.55 })
		block(b, "Foot", shin, Vector3.new(1.5, 0.35, 2.0), cf(side * 1.4, 0.18, -0.55), SKIN_DARK)
		for _, dx in { -0.5, 0, 0.5 } do
			block(b, "Toe", shin, Vector3.new(0.28, 0.25, 0.9), cf(side * 1.4 + dx, 0.13, -1.85) * rot(0, -dx * 30, 0), SKIN_DARK)
		end
		block(b, "Web", shin, Vector3.new(1.3, 0.06, 0.8), cf(side * 1.4, 0.1, -1.75), BELLY_SHADE, { transparency = 0.25 })
	end

	-- Woda kapiąca z wodnika, gdy się budzi
	local drip = block(b, "Drip", "Torso", Vector3.new(0.2, 0.2, 0.2), cf(0, 6.0, 0), WATER, { transparency = 1 })
	local water = Instance.new("ParticleEmitter")
	water.Name = "Water"
	water.Color = ColorSequence.new(WATER)
	water.LightEmission = 0.4
	water.Size = NumberSequence.new(0.22, 0.05)
	water.Lifetime = NumberRange.new(0.6, 1)
	water.Rate = 22
	water.Speed = NumberRange.new(0.5, 1.5)
	water.SpreadAngle = Vector2.new(70, 70)
	water.Acceleration = Vector3.new(0, -20, 0)
	water.Enabled = awake
	water.Parent = drip

	return RigBlocks.finish(b, parent, at, (Config :: any).Utopiec.speed or 27.5)
end

-- Budzi albo usypia (posąg na wyspie świeci oczami, gdy ktoś jest goniony)
function Utopiec.setAwake(m: Model, awake: boolean)
	m:SetAttribute("Awake", awake)
	for _, child in m:GetChildren() do
		if child.Name == "Eye" and child:IsA("BasePart") then
			child.Color = if awake then Utopiec.EYE_COLOR else Utopiec.EYE_SLEEP
		end
	end
	local head = m:FindFirstChild("Head")
	local eyeLight = head and head:FindFirstChild("EyeLight")
	if eyeLight and eyeLight:IsA("PointLight") then
		eyeLight.Brightness = if awake then 2.2 else 0
	end
	local drip = m:FindFirstChild("Drip")
	local water = drip and drip:FindFirstChild("Water")
	if water and water:IsA("ParticleEmitter") then
		water.Enabled = awake
	end
end

return Utopiec
