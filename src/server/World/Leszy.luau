--!strict
-- Leszy: wysoki duch lasu z kory i mchu. Czaszka z brzozowej kory z głębokimi oczodołami, poroże z gałęzi
-- z liśćmi, mchowa broda i peleryna, huby na bokach, świecące grzybki na ramieniu, a w piersi, między
-- żebrami z gałęzi, świeci zielone serce. Długie łapy z palcami z gałązek, stopy z korzeni.
-- Klocki z pikselową kratką (ta sama tekstura co grzyby), żeby pasował do reszty świata.
--
-- Model ma szkielet (src/shared/LeszyRig.luau): każda część ma atrybut Limb i Rest, model ma stawy J_<kość>.
-- Klient animuje go co klatkę (chód, bieg, ryk), serwer przesuwa tylko część Root (pivot).
-- Ten sam model to uśpiony posąg w gnieździe, goniący potwór i aktor w cutscence.
-- Pivot leży na ziemi pod stopami, przód to -Z (jak w CFrame.lookAt).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Palette = require(script.Parent.Palette)

local Leszy = {}

Leszy.EYE_COLOR = Color3.fromRGB(255, 40, 30)
Leszy.EYE_SLEEP = Color3.fromRGB(90, 20, 18)
Leszy.HEART_COLOR = Color3.fromRGB(120, 255, 150)
Leszy.HEART_SLEEP = Color3.fromRGB(40, 90, 56)

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local BARK_DARK = rgb(56, 40, 30)
local BARK = rgb(84, 60, 42)
local BARK_LIGHT = rgb(116, 86, 58)
local RIB = rgb(126, 110, 94)
local MOSS = rgb(62, 102, 46)
local MOSS_LIGHT = rgb(94, 132, 58)
local LICHEN = rgb(146, 160, 98)
local BIRCH = rgb(208, 198, 174)
local BIRCH_SHADE = rgb(180, 168, 144)
local BIRCH_MARK = rgb(48, 42, 38)
local SOCKET = rgb(16, 10, 10)
local FUNGUS = rgb(204, 158, 98)
local FUNGUS_TOP = rgb(142, 90, 52)
local LEAF = { rgb(214, 120, 46), rgb(228, 168, 62), rgb(184, 76, 42), MOSS_LIGHT }

local VERTICAL = CFrame.Angles(0, 0, math.rad(90))
local TEXTURE = (Config :: any).VoxelNoise and (Config :: any).VoxelNoise.texture or ""
local FACES = { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right, Enum.NormalId.Top }

type Builder = { model: Model, root: BasePart }

-- Klocek należący do kości `limb` (cf w układzie modelu, pivot w (0, 0, 0))
local function block(b: Builder, name: string, limb: string, size: Vector3, cf: CFrame, color: Color3, options: { shape: Enum.PartType?, neon: boolean?, texture: number? }?): Part
	local o = options or {}
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = if o.neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
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
	p:SetAttribute("Limb", limb)
	p:SetAttribute("Rest", cf)
	-- Pikselowa kratka na większych klockach (jak na grzybach): piksel = 0,25 studa
	local transparency = o.texture
	if transparency and TEXTURE ~= "" and not o.neon then
		for _, face in FACES do
			local tex = Instance.new("Texture")
			tex.Texture = TEXTURE
			tex.Face = face
			tex.StudsPerTileU = 2
			tex.StudsPerTileV = 2
			tex.Transparency = transparency
			tex.Parent = p
		end
	end
	p.Parent = b.model
	return p
end

-- Gałąź-walec od punktu `from` w kierunku (yaw wokół pionu, tilt od pionu)
local function branch(b: Builder, limb: string, from: Vector3, yaw: number, tilt: number, length: number, thickness: number, color: Color3?): CFrame
	local dir = CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, -tilt)
	local cf = CFrame.new(from) * dir * CFrame.new(0, length / 2, 0)
	block(b, "Antler", limb, Vector3.new(length, thickness, thickness), cf * VERTICAL, color or Palette.deadWood, { shape = Enum.PartType.Cylinder })
	return cf * CFrame.new(0, length / 2, 0)
end

-- Gałązka zwisająca w dół (palce, pnącza): od `from` w dół z odchyleniem
local function twig(b: Builder, limb: string, name: string, from: Vector3, pitch: number, roll: number, length: number, thickness: number, color: Color3)
	local cf = CFrame.new(from) * CFrame.Angles(pitch, 0, roll) * CFrame.new(0, -length / 2, 0)
	block(b, name, limb, Vector3.new(length, thickness, thickness), cf * VERTICAL, color, { shape = Enum.PartType.Cylinder })
end

local function setJoint(m: Model, limb: string, at: Vector3)
	m:SetAttribute("J_" .. limb, at)
end

-- Buduje Leszego stojącego w `at` (pivot na ziemi). awake = czerwone oczy i jasne serce.
function Leszy.build(parent: Instance, at: CFrame, awake: boolean): Model
	local m = Instance.new("Model")
	m.Name = "Leszy"
	m:SetAttribute("Rig", true)
	m:SetAttribute("Awake", awake)

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(2, 1, 2)
	root.CFrame = CFrame.new(0, 0.5, 0)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.Parent = m
	local b: Builder = { model = m, root = root }

	-- Stawy (układ modelu)
	setJoint(m, "Hips", Vector3.new(0, 5.3, 0))
	setJoint(m, "Torso", Vector3.new(0, 6.1, 0))
	setJoint(m, "Head", Vector3.new(0, 11.0, -0.1))

	-- ===== Biodra =====
	block(b, "Pelvis", "Hips", Vector3.new(3.2, 1.4, 2.1), CFrame.new(0, 5.5, 0), BARK_DARK, { texture = 0.5 })
	block(b, "Loin", "Hips", Vector3.new(2.4, 1.5, 0.3), CFrame.new(0, 4.55, -1.05) * CFrame.Angles(math.rad(-6), 0, 0), MOSS, { texture = 0.55 })
	block(b, "Loin", "Hips", Vector3.new(2.8, 1.8, 0.3), CFrame.new(0, 4.45, 1.05) * CFrame.Angles(math.rad(6), 0, 0), MOSS, { texture = 0.55 })
	for i, x in { -0.8, 0.1, 0.9 } do
		block(b, "Strand", "Hips", Vector3.new(0.3, 0.9 + i * 0.15, 0.2), CFrame.new(x, 3.5, -1.15), MOSS_LIGHT)
	end

	-- ===== Tułów =====
	block(b, "Belly", "Torso", Vector3.new(3.4, 2.6, 2.2), CFrame.new(0, 7.3, 0.1), BARK, { texture = 0.5 })
	block(b, "Chest", "Torso", Vector3.new(4.4, 2.7, 2.8), CFrame.new(0, 9.6, 0.1), BARK, { texture = 0.5 })
	-- Klatka z gałęzi, a za nią świecące serce
	local heart = block(b, "Heart", "Torso", Vector3.new(1.3, 1.3, 0.4), CFrame.new(0, 9.05, -1.38), if awake then Leszy.HEART_COLOR else Leszy.HEART_SLEEP, { neon = true })
	local heartLight = Instance.new("PointLight")
	heartLight.Name = "HeartLight"
	heartLight.Color = Leszy.HEART_COLOR
	heartLight.Range = 10
	heartLight.Brightness = if awake then 1.6 else 0.3
	heartLight.Parent = heart
	block(b, "Cavity", "Torso", Vector3.new(2.3, 2.2, 0.3), CFrame.new(0, 9.05, -1.18), SOCKET)
	for i, y in { 8.25, 8.75, 9.25, 9.75 } do
		local w = 2.6 - math.abs(i - 2.5) * 0.25
		block(b, "Rib", "Torso", Vector3.new(w, 0.24, 0.34), CFrame.new(0, y, -1.66) * CFrame.Angles(0, 0, math.rad((i % 2) * 4 - 2)), RIB)
	end
	block(b, "Sternum", "Torso", Vector3.new(0.3, 2.1, 0.4), CFrame.new(0, 9.0, -1.7), RIB)
	-- Żłobienia kory
	for _, x in { -1.25, -0.45, 0.5, 1.2 } do
		block(b, "Ridge", "Torso", Vector3.new(0.26, 2.2, 0.2), CFrame.new(x, 7.3, -1.0), BARK_DARK)
		block(b, "Ridge", "Torso", Vector3.new(0.26, 4.6, 0.2), CFrame.new(x * 1.2, 8.4, 1.55), BARK_DARK)
	end
	-- Mech na ramionach, porost na wierzchu
	for _, side in { -1, 1 } do
		block(b, "Moss", "Torso", Vector3.new(1.9, 0.8, 3.0), CFrame.new(side * 1.55, 11.05, 0.1), MOSS, { texture = 0.55 })
		block(b, "Lichen", "Torso", Vector3.new(0.7, 0.4, 0.7), CFrame.new(side * 1.9, 11.6, -0.6), LICHEN)
		block(b, "Lichen", "Torso", Vector3.new(0.5, 0.35, 0.5), CFrame.new(side * 1.2, 11.55, 0.9), LICHEN)
	end
	-- Mchowa peleryna z plecami i zwisające pasma
	block(b, "Mantle", "Torso", Vector3.new(4.3, 3.0, 0.5), CFrame.new(0, 9.4, 1.65) * CFrame.Angles(math.rad(5), 0, 0), MOSS, { texture = 0.55 })
	for i, x in { -1.7, -0.8, 0.1, 0.9, 1.7 } do
		block(b, "Strand", "Torso", Vector3.new(0.35, 1.2 + (i % 3) * 0.45, 0.3), CFrame.new(x, 7.3 - (i % 3) * 0.2, 1.85), if i % 2 == 0 then MOSS_LIGHT else LICHEN)
	end
	-- Huby na bokach
	for _, h in { { -1.95, 7.7, -0.3, 1.2 }, { -1.9, 7.1, 0.3, 0.8 }, { 2.4, 9.1, 0.6, 1.0 }, { 2.35, 8.6, -0.2, 0.7 } } do
		local side = if h[1] < 0 then -1 else 1
		local w = h[4]
		block(b, "Fungus", "Torso", Vector3.new(w * 0.9, 0.22, w * 0.8), CFrame.new(h[1] + side * w * 0.3, h[2], h[3]), FUNGUS)
		block(b, "Fungus", "Torso", Vector3.new(w * 0.8, 0.14, w * 0.7), CFrame.new(h[1] + side * w * 0.3, h[2] + 0.17, h[3]), FUNGUS_TOP)
	end
	-- Świecące grzybki na prawym ramieniu
	for i, g in { { 1.95, 11.45, 0.55, 0.62 }, { 2.4, 11.4, -0.15, 0.42 }, { 1.4, 11.45, 1.0, 0.38 } } do
		local color = Palette.glowShroom[(i - 1) % #Palette.glowShroom + 1]
		block(b, "GlowStem", "Torso", Vector3.new(0.18, 0.45, 0.18), CFrame.new(g[1], g[2] + 0.2, g[3]), BIRCH)
		local cap = block(b, "GlowCap", "Torso", Vector3.new(g[4], g[4] * 0.42, g[4]), CFrame.new(g[1], g[2] + 0.5, g[3]), color, { neon = true })
		if i == 1 then
			local light = Instance.new("PointLight")
			light.Color = color
			light.Range = 7
			light.Brightness = 0.9
			light.Parent = cap
		end
	end

	-- ===== Głowa =====
	block(b, "Neck", "Head", Vector3.new(1.3, 1.0, 1.3), CFrame.new(0, 11.4, 0), BARK_DARK, { texture = 0.5 })
	local head = block(b, "Head", "Head", Vector3.new(2.5, 2.7, 2.3), CFrame.new(0, 12.9, -0.35), BIRCH, { texture = 0.72 })
	-- Brzozowe plamy na czaszce
	for _, mark in { { -0.7, 13.95, 0.7 }, { 0.65, 12.25, 0.6 }, { -0.85, 12.0, 0.4 }, { 0.75, 14.0, 0.45 } } do
		block(b, "Mark", "Head", Vector3.new(mark[3], 0.14, 0.06), CFrame.new(mark[1], mark[2], -1.52), BIRCH_MARK)
	end
	for _, side in { -1, 1 } do
		block(b, "Mark", "Head", Vector3.new(0.06, 0.14, 0.8), CFrame.new(side * 1.27, 13.4, -0.2), BIRCH_MARK)
		block(b, "Mark", "Head", Vector3.new(0.06, 0.12, 0.5), CFrame.new(side * 1.27, 12.4, 0.3), BIRCH_MARK)
	end
	block(b, "Brow", "Head", Vector3.new(2.7, 0.45, 0.7), CFrame.new(0, 13.6, -1.35), BARK_DARK, { texture = 0.5 })
	block(b, "Nose", "Head", Vector3.new(0.42, 0.95, 0.4), CFrame.new(0, 12.55, -1.62), BIRCH_SHADE)
	local eyeColor = if awake then Leszy.EYE_COLOR else Leszy.EYE_SLEEP
	for _, side in { -1, 1 } do
		block(b, "Socket", "Head", Vector3.new(0.78, 0.68, 0.14), CFrame.new(side * 0.6, 13.05, -1.52), SOCKET)
		block(b, "Eye", "Head", Vector3.new(0.42, 0.36, 0.12), CFrame.new(side * 0.6, 13.02, -1.58), eyeColor, { neon = true })
	end
	block(b, "Jaw", "Head", Vector3.new(2.0, 0.7, 1.5), CFrame.new(0, 11.65, -1.0), BARK_DARK, { texture = 0.5 })
	block(b, "Mouth", "Head", Vector3.new(1.6, 0.22, 0.1), CFrame.new(0, 12.0, -1.56), SOCKET)
	for _, x in { -0.6, -0.2, 0.2, 0.6 } do
		block(b, "Tooth", "Head", Vector3.new(0.17, 0.38, 0.17), CFrame.new(x, 11.93 + math.abs(x) * 0.08, -1.62), BIRCH)
	end
	-- Broda z mchu i porostu
	block(b, "Beard", "Head", Vector3.new(2.1, 1.7, 0.6), CFrame.new(0, 10.85, -1.35), MOSS, { texture = 0.55 })
	for i, x in { -0.75, 0, 0.75 } do
		block(b, "Strand", "Head", Vector3.new(0.34, 1.0 + (i % 2) * 0.5, 0.28), CFrame.new(x, 9.6 - (i % 2) * 0.25, -1.45), if i == 2 then LICHEN else MOSS_LIGHT)
	end
	local light = Instance.new("PointLight")
	light.Name = "EyeLight"
	light.Color = Leszy.EYE_COLOR
	light.Range = 14
	light.Brightness = if awake then 2 else 0
	light.Parent = head
	-- Poroże z gałęzi, z liśćmi na końcach i zwisającym mchem
	for _, side in { -1, 1 } do
		local base = Vector3.new(side * 0.85, 14.1, -0.3)
		local tip = branch(b, "Head", base, 0, side * math.rad(25), 3.2, 0.36)
		local a = branch(b, "Head", tip.Position, 0, side * math.rad(58), 1.9, 0.26)
		local c = branch(b, "Head", tip.Position, 0, side * math.rad(-6), 1.7, 0.26)
		local d = branch(b, "Head", base + Vector3.new(side * 0.6, 1.4, 0), math.rad(side * 40), side * math.rad(72), 1.5, 0.22)
		for i, at in { a.Position, c.Position, d.Position } do
			block(b, "Leaf", "Head", Vector3.new(0.55, 0.22, 0.55), CFrame.new(at) * CFrame.Angles(0, math.rad(30 * i * side), math.rad(15 * side)), LEAF[(i + (if side > 0 then 1 else 0)) % #LEAF + 1])
		end
		twig(b, "Head", "Strand", tip.Position + Vector3.new(side * -0.3, -0.6, 0), 0, 0, 1.1, 0.18, MOSS_LIGHT)
	end
	for i = 1, 6 do
		local angle = math.rad(i * 60 + 15)
		block(b, "Leaf", "Head", Vector3.new(0.6, 0.22, 0.6), CFrame.new(math.cos(angle) * 1.0, 14.3, -0.35 + math.sin(angle) * 0.9) * CFrame.Angles(math.rad(12), angle, 0), LEAF[i % #LEAF + 1])
	end

	-- ===== Ręce (długie, do kolan) =====
	for _, side in { -1, 1 } do
		local tag = if side < 0 then "L" else "R"
		local upper, fore = "UpperArm" .. tag, "Forearm" .. tag
		setJoint(m, upper, Vector3.new(side * 2.45, 10.5, 0))
		setJoint(m, fore, Vector3.new(side * 2.8, 7.6, 0))
		block(b, "Arm", upper, Vector3.new(1.1, 3.0, 1.1), CFrame.new(side * 2.65, 9.05, 0) * CFrame.Angles(0, 0, math.rad(side * 6)), BARK, { texture = 0.5 })
		block(b, "Moss", upper, Vector3.new(1.3, 0.55, 1.3), CFrame.new(side * 2.55, 10.05, 0), MOSS)
		block(b, "Elbow", fore, Vector3.new(1.2, 0.8, 1.2), CFrame.new(side * 2.8, 7.6, 0), BARK_DARK)
		block(b, "Forearm", fore, Vector3.new(0.95, 3.0, 0.95), CFrame.new(side * 2.9, 6.0, -0.05), BARK, { texture = 0.5 })
		block(b, "Hand", fore, Vector3.new(1.2, 0.9, 1.1), CFrame.new(side * 2.95, 4.2, -0.1), BARK_DARK, { texture = 0.5 })
		for i, offset in { -0.42, -0.14, 0.14, 0.42 } do
			local spread = (i - 2.5) * 0.12
			twig(b, fore, "Finger", Vector3.new(side * (2.95 + offset * 0.4), 3.85, -0.1 + offset * 0.6), math.rad(-14), side * spread, 1.8, 0.22, Palette.deadWood)
		end
		twig(b, fore, "Vine", Vector3.new(side * 3.4, 6.6, 0.25), 0, 0, 1.5, 0.22, MOSS_LIGHT)
	end

	-- ===== Nogi jak pnie, stopy z korzeni =====
	for _, side in { -1, 1 } do
		local tag = if side < 0 then "L" else "R"
		local thigh, shin = "Thigh" .. tag, "Shin" .. tag
		setJoint(m, thigh, Vector3.new(side * 1.1, 5.2, 0))
		setJoint(m, shin, Vector3.new(side * 1.15, 2.6, 0))
		block(b, "Thigh", thigh, Vector3.new(1.55, 2.8, 1.55), CFrame.new(side * 1.15, 3.95, 0), BARK, { texture = 0.5 })
		block(b, "Knee", shin, Vector3.new(1.6, 0.8, 1.6), CFrame.new(side * 1.15, 2.6, -0.05), BARK_DARK)
		block(b, "Shin", shin, Vector3.new(1.35, 2.2, 1.35), CFrame.new(side * 1.2, 1.4, 0.05), BARK, { texture = 0.5 })
		block(b, "Moss", shin, Vector3.new(1.0, 0.8, 0.25), CFrame.new(side * 1.2, 1.7, -0.72), MOSS)
		block(b, "Foot", shin, Vector3.new(1.9, 0.6, 2.6), CFrame.new(side * 1.2, 0.3, -0.45), BARK_DARK, { texture = 0.5 })
		for _, dx in { -0.6, 0, 0.6 } do
			block(b, "Toe", shin, Vector3.new(0.42, 0.4, 1.1), CFrame.new(side * 1.2 + dx, 0.2, -1.95) * CFrame.Angles(math.rad(-8), math.rad(-dx * 25), 0), BARK)
		end
	end

	m.PrimaryPart = root
	-- Pivot na podłodze pod stopami (model jest budowany wokół początku układu). WorldPivot nic tu
	-- nie daje, bo przy ustawionym PrimaryPart Roblox liczy pivot z PivotOffset tej części.
	root.PivotOffset = root.CFrame:Inverse()
	m:PivotTo(at)
	CollectionService:AddTag(m, "LeszyRig")
	m.Parent = parent
	return m
end

-- Budzi albo usypia oczy i serce (posąg w gnieździe świeci, gdy ktoś jest goniony)
function Leszy.setAwake(m: Model, awake: boolean)
	m:SetAttribute("Awake", awake)
	for _, child in m:GetChildren() do
		if child.Name == "Eye" and child:IsA("BasePart") then
			child.Color = if awake then Leszy.EYE_COLOR else Leszy.EYE_SLEEP
		elseif child.Name == "Heart" and child:IsA("BasePart") then
			child.Color = if awake then Leszy.HEART_COLOR else Leszy.HEART_SLEEP
			local glow = child:FindFirstChild("HeartLight")
			if glow and glow:IsA("PointLight") then
				glow.Brightness = if awake then 1.6 else 0.3
			end
		end
	end
	local head = m:FindFirstChild("Head")
	local light = head and head:FindFirstChild("EyeLight")
	if light and light:IsA("PointLight") then
		light.Brightness = if awake then 2 else 0
	end
end

return Leszy
