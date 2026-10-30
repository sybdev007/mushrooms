--!strict
-- Wystrój na Halloween (Noc Dziadów): voxelowe dynie ze świecącymi buziami i znicze przy chatce,
-- na ścieżce do lasu, w obozowisku w jaskini i na przystani na bagnach. GameService buduje go
-- w czasie eventu i usuwa po nim. Wszystko jest ozdobą: bez kolizji, bez dotyku i bez celowania.
-- Chatka jest centrum eventu: do tego jesienne liście, pajęczyny na ganku, girlanda z dyniowych
-- lampionów, przyziemna mgła wokół kotła, a w jaskini pajęczyny pod stropem, na bagnach znicze
-- wzdłuż kładki i duchy (tag "HalloweenGhost": unoszą się po stronie klienta, HalloweenFx).
-- W lesie jest też mały sekretny zakątek (stary cmentarzyk grzybiarzy, tag "HalloweenSecret").

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local HalloweenDecor = {}

local TEXTURE = (Config :: any).VoxelNoise and (Config :: any).VoxelNoise.texture or ""
local NOISE_FACES = { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right, Enum.NormalId.Top }

local ORANGE = Color3.fromRGB(196, 86, 16)
local ORANGE_DARK = Color3.fromRGB(140, 56, 12)
local STEM = Color3.fromRGB(70, 104, 40)
local GLOW = Color3.fromRGB(255, 214, 90)
local CANDLE_GLASS = Color3.fromRGB(200, 30, 36)
local CANDLE_LID = Color3.fromRGB(196, 160, 80)
local FLAME = Color3.fromRGB(255, 200, 80)

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = material ~= Enum.Material.Neon
	p.Parent = parent
	return p
end

local function texturize(p: BasePart, tile: number)
	if TEXTURE == "" then
		return
	end
	for _, face in NOISE_FACES do
		local t = Instance.new("Texture")
		t.Texture = TEXTURE
		t.Face = face
		t.StudsPerTileU = tile
		t.StudsPerTileV = tile
		t.Transparency = 0.45 -- delikatna kratka (pełna przepalała się w świetle chatki)
		t.Parent = p
	end
end

-- Dynia z wyciętą buzią. at = punkt na ziemi; buzia patrzy w stronę -Z układu `at`.
local function pumpkin(parent: Instance, at: CFrame, s: number)
	local m = Instance.new("Model")
	m.Name = "Pumpkin"
	local bodyH = s * 0.78
	local body = part(m, "Body", Vector3.new(s, bodyH, s), at * CFrame.new(0, s * 0.08 + bodyH / 2, 0), ORANGE)
	texturize(body, s)
	-- Schodkowe brzegi u dołu i u góry (jak kapelusze grzybów)
	part(m, "Bottom", Vector3.new(s * 0.82, s * 0.08, s * 0.82), at * CFrame.new(0, s * 0.04, 0), ORANGE_DARK)
	part(m, "Top", Vector3.new(s * 0.72, s * 0.1, s * 0.72), at * CFrame.new(0, s * 0.08 + bodyH + s * 0.05, 0), ORANGE)
	part(m, "Stem", Vector3.new(s * 0.16, s * 0.26, s * 0.16), at * CFrame.new(s * 0.03, s * 0.08 + bodyH + s * 0.2, 0) * CFrame.Angles(0, 0, math.rad(-12)), STEM)
	-- Bruzdy na bokach i z tyłu (z przodu jest buzia)
	local y = s * 0.08 + bodyH / 2
	for _, x in { -0.22, 0.22 } do
		part(m, "Rib", Vector3.new(s * 0.06, bodyH * 0.9, 0.04), at * CFrame.new(x * s, y, s / 2 + 0.01), ORANGE_DARK)
		part(m, "Rib", Vector3.new(0.04, bodyH * 0.9, s * 0.06), at * CFrame.new(s / 2 + 0.01, y, x * s), ORANGE_DARK)
		part(m, "Rib", Vector3.new(0.04, bodyH * 0.9, s * 0.06), at * CFrame.new(-s / 2 - 0.01, y, x * s), ORANGE_DARK)
	end
	-- Buzia: oczy-romby, trójkątny nos i zębaty uśmiech, świecące od środka
	local front = -s / 2 - 0.02
	for _, x in { -0.22, 0.22 } do
		part(m, "Eye", Vector3.new(s * 0.16, s * 0.16, 0.06), at * CFrame.new(x * s, y + s * 0.12, front) * CFrame.Angles(0, 0, math.rad(45)), GLOW, Enum.Material.Neon)
	end
	part(m, "Nose", Vector3.new(s * 0.08, s * 0.08, 0.06), at * CFrame.new(0, y - s * 0.01, front) * CFrame.Angles(0, 0, math.rad(45)), GLOW, Enum.Material.Neon)
	part(m, "Mouth", Vector3.new(s * 0.54, s * 0.13, 0.06), at * CFrame.new(0, y - s * 0.17, front), GLOW, Enum.Material.Neon)
	for _, x in { -0.12, 0.12 } do
		part(m, "Tooth", Vector3.new(s * 0.09, s * 0.06, 0.07), at * CFrame.new(x * s, y - s * 0.13, front - 0.01), ORANGE)
	end
	-- Światło przed buzią (w środku dyni przepalało ją na żółto): oświetla ziemię wokół, nie samą dynię
	local glow = part(m, "Glow", Vector3.new(0.2, 0.2, 0.2), at * CFrame.new(0, 0.2, -s * 1.1), GLOW)
	glow.Transparency = 1
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 140, 50)
	light.Range = 5 + s * 2
	light.Brightness = 0.6
	light.Parent = glow
	m.PrimaryPart = body
	m.Parent = parent
end

-- Znicz: czerwone szkło, złota pokrywka i płomyk w środku
local function candle(parent: Instance, at: CFrame, s: number)
	local m = Instance.new("Model")
	m.Name = "GraveCandle"
	part(m, "Base", Vector3.new(0.56, 0.1, 0.56) * s, at * CFrame.new(0, 0.05 * s, 0), Color3.fromRGB(70, 66, 72))
	local glass = part(m, "Glass", Vector3.new(0.48, 0.78, 0.48) * s, at * CFrame.new(0, (0.1 + 0.39) * s, 0), CANDLE_GLASS, Enum.Material.Glass)
	glass.Transparency = 0.3
	part(m, "Lid", Vector3.new(0.54, 0.1, 0.54) * s, at * CFrame.new(0, 0.93 * s, 0), CANDLE_LID, Enum.Material.Metal)
	local flame = part(m, "Flame", Vector3.new(0.14, 0.26, 0.14) * s, at * CFrame.new(0, 0.62 * s, 0), FLAME, Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 110, 70)
	light.Range = 5
	light.Brightness = 1
	light.Parent = flame
	m.PrimaryPart = glass
	m.Parent = parent
end

-- Kocioł „cukierek albo psikus”: żeliwny garnek na nóżkach nad ogniem, z bulgoczącym zielonym
-- wywarem. Przycisk (ProximityPrompt z tagiem "CauldronPrompt") obsługuje HalloweenService,
-- a teksty przycisku i napisu nad kotłem ustawia klient w języku gracza (CauldronView).
local IRON = Color3.fromRGB(40, 38, 46)
local IRON_LIGHT = Color3.fromRGB(70, 66, 80)
local BREW = Color3.fromRGB(120, 255, 90)
local function cauldron(parent: Instance, at: CFrame)
	local m = Instance.new("Model")
	m.Name = "Cauldron"
	-- Ognisko pod kotłem
	for k = 0, 3 do
		local log = part(m, "Log", Vector3.new(0.5, 0.5, 3), at * CFrame.Angles(0, k * math.pi / 4, 0) * CFrame.new(0, 0.25, 0), Color3.fromRGB(96, 62, 40), Enum.Material.Wood)
		log.CastShadow = false
	end
	part(m, "Embers", Vector3.new(1.4, 0.3, 1.4), at * CFrame.new(0, 0.55, 0), Color3.fromRGB(255, 120, 40), Enum.Material.Neon)
	local fire = Instance.new("Fire")
	fire.Size = 3
	fire.Heat = 6
	fire.Color = Color3.fromRGB(255, 140, 40)
	fire.SecondaryColor = Color3.fromRGB(255, 220, 90)
	fire.Parent = m:FindFirstChild("Embers")
	-- Nóżki i garnek z klocków (szerszy w środku, węższy przy dnie i przy brzegu)
	for k = 0, 2 do
		part(m, "Leg", Vector3.new(0.4, 1.3, 0.4), at * CFrame.Angles(0, k * 2 * math.pi / 3, 0) * CFrame.new(0, 0.65, -1.4), IRON)
	end
	part(m, "PotBottom", Vector3.new(2.4, 0.5, 2.4), at * CFrame.new(0, 1.35, 0), IRON)
	local belly = part(m, "PotBelly", Vector3.new(3.4, 1.4, 3.4), at * CFrame.new(0, 2.25, 0), IRON)
	texturize(belly, 3.4)
	part(m, "PotNeck", Vector3.new(3, 0.4, 3), at * CFrame.new(0, 3.15, 0), IRON)
	-- Brzeg z czterech belek (pełny klocek zakrywał wywar)
	for _, side in { -1, 1 } do
		part(m, "Rim", Vector3.new(3.6, 0.32, 0.32), at * CFrame.new(0, 3.5, side * 1.64), IRON_LIGHT, Enum.Material.Metal)
		part(m, "Rim", Vector3.new(0.32, 0.32, 3.6), at * CFrame.new(side * 1.64, 3.5, 0), IRON_LIGHT, Enum.Material.Metal)
	end
	for _, side in { -1, 1 } do
		part(m, "Handle", Vector3.new(0.3, 0.6, 0.3), at * CFrame.new(side * 1.95, 3.1, 0), IRON_LIGHT, Enum.Material.Metal)
	end
	local brew = part(m, "Brew", Vector3.new(3.0, 0.2, 3.0), at * CFrame.new(0, 3.46, 0), BREW, Enum.Material.Neon)
	-- Bąble i zielona para
	local bubbles = Instance.new("ParticleEmitter")
	bubbles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	bubbles.Color = ColorSequence.new(BREW, Color3.fromRGB(200, 255, 170))
	bubbles.LightEmission = 0.6
	bubbles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0.5) })
	bubbles.Transparency = NumberSequence.new(0.2, 1)
	bubbles.Lifetime = NumberRange.new(0.8, 1.4)
	bubbles.Speed = NumberRange.new(1, 2)
	bubbles.SpreadAngle = Vector2.new(25, 25)
	bubbles.Rate = 10
	bubbles.EmissionDirection = Enum.NormalId.Top
	bubbles.Parent = brew
	local steam = Instance.new("ParticleEmitter")
	steam.Texture = "rbxasset://textures/particles/smoke_main.dds"
	steam.Color = ColorSequence.new(Color3.fromRGB(150, 230, 140))
	steam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	steam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3) })
	steam.Lifetime = NumberRange.new(1.5, 2.5)
	steam.Speed = NumberRange.new(1.5, 2.5)
	steam.Rate = 4
	steam.EmissionDirection = Enum.NormalId.Top
	steam.Parent = brew
	local light = Instance.new("PointLight")
	light.Color = BREW
	light.Range = 10
	light.Brightness = 1
	light.Parent = brew
	-- Przycisk i napis nad kotłem
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CauldronPrompt"
	prompt.ActionText = "CAULDRON_ACTION"
	prompt.ObjectText = "CAULDRON_NAME"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0.3
	prompt.Parent = brew
	CollectionService:AddTag(prompt, "CauldronPrompt")
	local sign = Instance.new("BillboardGui")
	sign.Name = "CauldronSign"
	sign.Size = UDim2.fromOffset(240, 70)
	sign.StudsOffsetWorldSpace = Vector3.new(0, 3.6, 0)
	sign.MaxDistance = 70
	sign.LightInfluence = 0
	sign.Parent = brew
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(200, 255, 150)
	label.Text = "🎃"
	label.Parent = sign
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Color3.fromRGB(30, 20, 40)
	stroke.Parent = label
	CollectionService:AddTag(sign, "CauldronSign")
	m.PrimaryPart = belly
	m.Parent = parent
end

-- Wysokość ziemi (podłoga, ganek, kamienie) pod punktem; nil = nic tam nie ma
local function groundAt(x: number, z: number, from: number, ignore: { Instance }): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local result = Workspace:Raycast(Vector3.new(x, from, z), Vector3.new(0, -from - 20, 0), params)
	return if result then result.Position.Y else nil
end

type Spot = { x: number, z: number, kind: string, size: number, from: number? }

-- ===== Jesień, pajęczyny, girlanda, mgła, duchy =====

local LEAF_COLORS = {
	Color3.fromRGB(196, 92, 28),
	Color3.fromRGB(222, 140, 38),
	Color3.fromRGB(166, 52, 30),
	Color3.fromRGB(230, 182, 64),
	Color3.fromRGB(140, 70, 30),
}
local WEB = Color3.fromRGB(226, 228, 236)
local GHOST = Color3.fromRGB(226, 240, 255)
local GHOST_EYES = Color3.fromRGB(40, 30, 60)

-- Kupka liści płasko na ziemi (kilka kwadracików pod różnymi kątami)
local function leafPile(parent: Instance, at: Vector3, rng: Random)
	for _ = 1, rng:NextInteger(3, 6) do
		local size = rng:NextNumber(0.35, 0.7)
		local offset = Vector3.new(rng:NextNumber(-0.9, 0.9), 0.04, rng:NextNumber(-0.9, 0.9))
		part(parent, "Leaf", Vector3.new(size, 0.06, size), CFrame.new(at + offset) * CFrame.Angles(0, rng:NextNumber(0, math.pi), rng:NextNumber(-0.12, 0.12)), LEAF_COLORS[rng:NextInteger(1, #LEAF_COLORS)])
	end
end

-- Pajęczyna w rogu: `cf` = róg (oś -Z cf to kierunek, w który rozpina się sieć), size = zasięg nici
local function cobweb(parent: Instance, cf: CFrame, size: number)
	local m = Instance.new("Model")
	m.Name = "Cobweb"
	local strands = 5
	local points: { { Vector3 } } = {}
	for i = 0, strands - 1 do
		local angle = math.rad(-90 + i * 90 / (strands - 1))
		local dir = Vector3.new(math.cos(angle), math.sin(angle), 0)
		local from = cf.Position
		local to = (cf * CFrame.new(dir * size)).Position
		local strand = part(m, "Strand", Vector3.new(0.05, 0.05, (to - from).Magnitude), CFrame.lookAt((from + to) / 2, to), WEB)
		strand.Transparency = 0.35
		strand.CastShadow = false
		points[i + 1] = {}
		for k = 1, 3 do
			points[i + 1][k] = from:Lerp(to, k / 3.4)
		end
	end
	-- Poprzeczne nitki (pierścienie sieci)
	for k = 1, 3 do
		for i = 1, strands - 1 do
			local a, b = points[i][k], points[i + 1][k]
			local thread = part(m, "Ring", Vector3.new(0.04, 0.04, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), WEB)
			thread.Transparency = 0.45
			thread.CastShadow = false
		end
	end
	m.Parent = parent
end

-- Pająk na nitce zwisający z sufitu (top = punkt zaczepienia)
local function spider(parent: Instance, top: Vector3, drop: number)
	local thread = part(parent, "SpiderThread", Vector3.new(0.04, drop, 0.04), CFrame.new(top - Vector3.new(0, drop / 2, 0)), WEB)
	thread.Transparency = 0.4
	local body = top - Vector3.new(0, drop + 0.2, 0)
	part(parent, "Spider", Vector3.new(0.45, 0.35, 0.55), CFrame.new(body), Color3.fromRGB(28, 22, 30))
	for _, side in { -1, 1 } do
		for k = -1, 1 do
			part(parent, "SpiderLeg", Vector3.new(0.5, 0.06, 0.06), CFrame.new(body + Vector3.new(side * 0.4, -0.05, k * 0.18)) * CFrame.Angles(0, 0, side * 0.5), Color3.fromRGB(28, 22, 30))
		end
	end
	part(parent, "SpiderEye", Vector3.new(0.3, 0.08, 0.06), CFrame.new(body + Vector3.new(0, 0.05, -0.29)), Color3.fromRGB(255, 60, 60), Enum.Material.Neon)
end

-- Girlanda: sznurek z małymi lampionami-dyniami między dwoma punktami, z lekkim zwisem
local function garland(parent: Instance, a: Vector3, b: Vector3, sag: number, count: number)
	local last = a
	for i = 1, 12 do
		local t = i / 12
		local p = a:Lerp(b, t) - Vector3.new(0, math.sin(t * math.pi) * sag, 0)
		local rope = part(parent, "GarlandRope", Vector3.new(0.06, 0.06, (p - last).Magnitude), CFrame.lookAt((p + last) / 2, p), Color3.fromRGB(50, 36, 30))
		rope.CastShadow = false
		last = p
	end
	for i = 1, count do
		local t = i / (count + 1)
		local p = a:Lerp(b, t) - Vector3.new(0, math.sin(t * math.pi) * sag + 0.35, 0)
		local colors = { Color3.fromRGB(255, 140, 30), Color3.fromRGB(170, 90, 255), Color3.fromRGB(120, 255, 120) }
		local color = colors[(i - 1) % #colors + 1]
		local lamp = part(parent, "GarlandLamp", Vector3.new(0.5, 0.42, 0.5), CFrame.new(p), color, Enum.Material.Neon)
		lamp.CastShadow = false
		if i % 3 == 0 then
			local light = Instance.new("PointLight")
			light.Color = color
			light.Range = 7
			light.Brightness = 0.7
			light.Parent = lamp
		end
	end
end

-- Przyziemna mgła: miękkie kłęby dymu nisko nad ziemią w prostokącie (size.X x size.Z)
local function groundMist(parent: Instance, center: Vector3, size: Vector2, rate: number, color: Color3)
	local holder = part(parent, "GroundMist", Vector3.new(size.X, 0.5, size.Y), CFrame.new(center + Vector3.new(0, 0.6, 0)), color)
	holder.Transparency = 1
	local mist = Instance.new("ParticleEmitter")
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Shape = Enum.ParticleEmitterShape.Box
	mist.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	mist.Color = ColorSequence.new(color)
	mist.LightEmission = 0.15
	mist.LightInfluence = 0.6
	mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 8) })
	mist.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.86),
		NumberSequenceKeypoint.new(0.7, 0.88),
		NumberSequenceKeypoint.new(1, 1),
	})
	mist.Lifetime = NumberRange.new(8, 12)
	mist.Speed = NumberRange.new(0.2, 0.6)
	mist.SpreadAngle = Vector2.new(180, 5)
	mist.Rotation = NumberRange.new(0, 360)
	mist.RotSpeed = NumberRange.new(-8, 8)
	mist.Rate = rate
	mist.Parent = holder
end

-- Duszek z klocków: zaokrąglona góra, falisty dół, czarne oczy i „o” ust. Unosi go klient (tag).
local function ghost(parent: Instance, at: Vector3, s: number, rng: Random)
	local m = Instance.new("Model")
	m.Name = "Ghost"
	local face = CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local body = part(m, "Body", Vector3.new(1.4, 1.6, 1.2) * s, face, GHOST, Enum.Material.SmoothPlastic)
	body.Transparency = 0.25
	local head = part(m, "Head", Vector3.new(1.1, 0.5, 1) * s, face * CFrame.new(0, 1.05 * s, 0), GHOST)
	head.Transparency = 0.25
	for i = -1, 1 do
		local tail = part(m, "Tail", Vector3.new(0.4, 0.45, 1) * s, face * CFrame.new(i * 0.48 * s, -1.0 * s - (i % 2) * 0.12 * s, 0), GHOST)
		tail.Transparency = 0.3
	end
	for _, x in { -0.3, 0.3 } do
		part(m, "Eye", Vector3.new(0.22, 0.3, 0.06) * s, face * CFrame.new(x * s, 0.35 * s, -0.62 * s), GHOST_EYES)
	end
	part(m, "Mouth", Vector3.new(0.24, 0.24, 0.06) * s, face * CFrame.new(0, -0.05 * s, -0.62 * s), GHOST_EYES)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(170, 210, 255)
	light.Range = 8
	light.Brightness = 0.8
	light.Parent = body
	m.PrimaryPart = body
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- klient dostaje całego ducha naraz (unosi go HalloweenFx)
	CollectionService:AddTag(m, "HalloweenGhost")
	m.Parent = parent
end

-- Krzywy nagrobek z kamienia z krzyżykiem
local function gravestone(parent: Instance, at: CFrame, s: number)
	local stone = Color3.fromRGB(110, 108, 118)
	local tilt = at * CFrame.Angles(0, 0, math.rad(8))
	part(parent, "Grave", Vector3.new(1.6, 2.2, 0.4) * s, tilt * CFrame.new(0, 1.1 * s, 0), stone, Enum.Material.Slate)
	part(parent, "GraveTop", Vector3.new(1.3, 0.3, 0.42) * s, tilt * CFrame.new(0, 2.3 * s, 0), stone, Enum.Material.Slate)
	part(parent, "GraveCross", Vector3.new(0.14, 0.7, 0.05) * s, tilt * CFrame.new(0, 1.5 * s, -0.22 * s), Color3.fromRGB(70, 68, 76))
	part(parent, "GraveCross", Vector3.new(0.45, 0.14, 0.05) * s, tilt * CFrame.new(0, 1.65 * s, -0.22 * s), Color3.fromRGB(70, 68, 76))
	part(parent, "Mound", Vector3.new(1.6, 0.25, 2.6) * s, at * CFrame.new(0, 0.12 * s, -1.6 * s), Color3.fromRGB(70, 50, 36), Enum.Material.Ground)
end

local function placeOnGround(x: number, z: number, from: number, ignore: { Instance }): Vector3?
	local y = groundAt(x, z, from, ignore)
	return if y then Vector3.new(x, y, z) else nil
end

-- Sekretny zakątek: stary cmentarzyk grzybiarzy przy zachodniej ścianie Skraju Lasu
HalloweenDecor.SECRET = Vector3.new(-62, 0, 110)

-- Stałe miejsca. Buzie dyń patrzą na `face` (środek ścieżki albo obozu).
local function spots(): { { list: { Spot }, face: (x: number, z: number) -> Vector3 } }
	local caveCamp = Config.Cave.camp
	local swampCamp = Config.Swamp.camp
	local pathX = function(z: number): number
		return 3 * math.sin(z / 16) -- jak Props.pathX
	end
	return {
		{
			-- Chatka: ganek (przy drzwiach i na rogach), schodek, lada skupywacza
			list = {
				{ x = -4.6, z = -8.2, kind = "pumpkin", size = 2.2 },
				{ x = 4.6, z = -8.2, kind = "pumpkin", size = 2.2 },
				{ x = -6.2, z = -7.6, kind = "candle", size = 1 },
				{ x = -6.9, z = -8.6, kind = "candle", size = 0.8 },
				{ x = 6.2, z = -7.6, kind = "candle", size = 1 },
				{ x = 6.9, z = -8.6, kind = "candle", size = 0.8 },
				{ x = -15.4, z = -8, kind = "pumpkin", size = 2.6 },
				{ x = 15.4, z = -8, kind = "pumpkin", size = 2.6 },
				{ x = -14.2, z = -9.2, kind = "pumpkin", size = 1.5 },
				{ x = 14.2, z = -9.2, kind = "pumpkin", size = 1.5 },
				{ x = -3.9, z = -5.2, kind = "candle", size = 1 },
				{ x = 3.9, z = -5.2, kind = "candle", size = 1 },
				{ x = -6, z = -40.4, kind = "pumpkin", size = 1.4, from = 9 },
				{ x = 6, z = -40.4, kind = "candle", size = 0.9, from = 9 },
			},
			face = function(x: number, _z: number): Vector3
				return Vector3.new(x * 0.4, 0, 6)
			end,
		},
		{
			-- Ścieżka do lasu (latarnie stoją na z = 8 i 30) i brama Skraju Lasu
			list = {
				{ x = pathX(1) - 2.6, z = 1, kind = "pumpkin", size = 1.6 },
				{ x = pathX(4) + 2.6, z = 4, kind = "candle", size = 1 },
				{ x = pathX(15) + 2.7, z = 15, kind = "pumpkin", size = 1.8 },
				{ x = pathX(19) - 2.6, z = 19, kind = "candle", size = 1 },
				{ x = pathX(23) - 2.7, z = 23, kind = "pumpkin", size = 1.4 },
				{ x = pathX(26) + 2.6, z = 26, kind = "candle", size = 1 },
				{ x = -6.4, z = 36.5, kind = "pumpkin", size = 2.4 },
				{ x = 6.4, z = 36.5, kind = "pumpkin", size = 2.4 },
				{ x = -5, z = 35.6, kind = "candle", size = 1 },
				{ x = 5, z = 35.6, kind = "candle", size = 1 },
			},
			face = function(_x: number, z: number): Vector3
				return Vector3.new(pathX(z), 0, z)
			end,
		},
		{
			-- Obozowisko w jaskini (ognisko na z + 7, kramik i beczka na x = ±13)
			list = {
				{ x = -6.5, z = caveCamp.z + 2, kind = "pumpkin", size = 2 },
				{ x = 6.5, z = caveCamp.z + 2, kind = "pumpkin", size = 2 },
				{ x = -3.2, z = caveCamp.z + 9.6, kind = "candle", size = 1 },
				{ x = 3.2, z = caveCamp.z + 9.6, kind = "candle", size = 1 },
				{ x = -8, z = caveCamp.z + 12, kind = "pumpkin", size = 1.5 },
				{ x = 8, z = caveCamp.z + 12, kind = "pumpkin", size = 1.5 },
			},
			face = function(_x: number, z: number): Vector3
				return Vector3.new(0, 0, z)
			end,
		},
		{
			-- Przystań na bagnach (kramik i beczka na x = ±15)
			list = {
				{ x = -7.5, z = swampCamp.z + 1, kind = "pumpkin", size = 2 },
				{ x = 7.5, z = swampCamp.z + 1, kind = "pumpkin", size = 2 },
				{ x = -9, z = swampCamp.z + 3, kind = "candle", size = 1 },
				{ x = 9, z = swampCamp.z + 3, kind = "candle", size = 1 },
				{ x = -5.5, z = swampCamp.z + 7, kind = "candle", size = 0.8 },
				{ x = 5.5, z = swampCamp.z + 7, kind = "candle", size = 0.8 },
			},
			face = function(_x: number, z: number): Vector3
				return Vector3.new(0, 0, z)
			end,
		},
	}
end

function HalloweenDecor.build(parent: Instance, _map: any): Folder
	local folder = Instance.new("Folder")
	folder.Name = "HalloweenDecor"
	local ignore: { Instance } = { folder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	local rng = Random.new(Config.SpotSeed + 31)
	for _, group in spots() do
		for _, spot in group.list do
			local y = groundAt(spot.x, spot.z, spot.from or 8, ignore)
			if y and y < 6 then
				local target = group.face(spot.x, spot.z)
				local position = Vector3.new(spot.x, y, spot.z)
				local look = Vector3.new(target.X, y, target.Z)
				local at = if (look - position).Magnitude > 0.1 then CFrame.lookAt(position, look) else CFrame.new(position)
				-- Mały losowy obrót, żeby nie stały jak od linijki
				at *= CFrame.Angles(0, math.rad(rng:NextNumber(-12, 12)), 0)
				if spot.kind == "pumpkin" then
					pumpkin(folder, at, spot.size)
				else
					candle(folder, at, spot.size)
				end
			end
		end
	end
	-- Kocioł na trawie przed gankiem, po lewej od schodka (patrząc od lasu: po prawej)
	local cx, cz = -9.5, -0.5
	local cy = groundAt(cx, cz, 8, ignore)
	if cy and cy < 4 then
		cauldron(folder, CFrame.new(cx, cy, cz) * CFrame.Angles(0, math.rad(20), 0))
	end

	-- ===== Chatka: centrum eventu =====
	-- Dynie wokół kotła i przy płotach ogródków
	for _, spot in {
		{ -13.2, 1.8, 1.7 }, { -12.4, -2.8, 1.2 }, { -6.2, 2.6, 1.3 }, { -7.4, -3.2, 0.9 },
		{ -21, 9.6, 1.4 }, { 21, 9.6, 1.4 }, { -21, -30, 1.4 }, { 21, -30, 1.4 },
	} do
		local at = placeOnGround(spot[1], spot[2], 8, ignore)
		if at and at.Y < 4 then
			pumpkin(folder, CFrame.lookAt(at, Vector3.new(cx, at.Y, cz + 6)) * CFrame.Angles(0, math.rad(rng:NextNumber(-15, 15)), 0), spot[3])
		end
	end
	for _, spot in { { -11.6, 3.2 }, { -7.8, 2.4 }, { -12.6, -4.2 } } do
		local at = placeOnGround(spot[1], spot[2], 8, ignore)
		if at and at.Y < 4 then
			candle(folder, CFrame.new(at), 0.9)
		end
	end
	-- Jesienne liście na polanie przed chatką (poza ścieżką)
	local leaves = Instance.new("Folder")
	leaves.Name = "Leaves"
	leaves.Parent = folder
	for _ = 1, 70 do
		local x = rng:NextNumber(-26, 26)
		local z = rng:NextNumber(-6, 36)
		if math.abs(x - 3 * math.sin(z / 16)) > 3 then
			local at = placeOnGround(x, z, 6, ignore)
			if at and at.Y < 1.5 then
				leafPile(leaves, at, rng)
			end
		end
	end
	-- Girlanda z lampionów pod daszkiem ganku (między słupkami) i pajęczyny w rogach ganku
	local map = Workspace:FindFirstChild("Map")
	local posts: { BasePart } = {}
	if map then
		for _, d in map:GetDescendants() do
			if d:IsA("BasePart") and d.Name == "PorchPost" then
				table.insert(posts, d)
			end
		end
	end
	if #posts == 2 then
		table.sort(posts, function(a, b)
			return a.Position.X < b.Position.X
		end)
		local topY = posts[1].Position.Y + posts[1].Size.Y / 2 - 0.6
		local left = Vector3.new(posts[1].Position.X + 0.5, topY, posts[1].Position.Z)
		local right = Vector3.new(posts[2].Position.X - 0.5, topY, posts[2].Position.Z)
		local mid = (left + right) / 2
		-- Dwa łuki, żeby nie zasłaniały szyldu nad drzwiami
		garland(folder, left, mid - Vector3.new(4.5, 0, 0), 1.6, 5)
		garland(folder, mid + Vector3.new(4.5, 0, 0), right, 1.6, 5)
		-- Pajęczyna w kącie między słupkiem a daszkiem: zaczepiona pod daszkiem przy wewnętrznej
		-- stronie słupka, rozpięta w dół i do środka ganku, od strony lasu
		for _, post in posts do
			local inward = if post.Position.X < 0 then 1 else -1
			local top = post.Position.Y + post.Size.Y / 2 - 0.05
			local at = CFrame.new(post.Position.X + inward * (post.Size.X / 2 + 0.02), top, post.Position.Z + post.Size.Z / 2 + 0.05)
			cobweb(folder, if inward > 0 then at else at * CFrame.Angles(0, math.pi, 0), 2.6)
		end
	end
	-- Przyziemna mgła wokół kotła i przed gankiem
	groundMist(folder, Vector3.new(cx, 0, cz), Vector2.new(12, 10), 1.2, Color3.fromRGB(150, 120, 190))
	groundMist(folder, Vector3.new(0, 0, 4), Vector2.new(30, 12), 1.5, Color3.fromRGB(140, 130, 180))

	-- ===== Jaskinia: pajęczyny w rogach drewnianych odrzwi kopalni i pająki pod belkami =====
	-- Strop jaskini jest wysoko (ok. 34 studów), więc sieci wiszą na odrzwiach (MineFrame: słupy na
	-- x = ±7, belka na wysokości ok. 12) w chodnikach najbliżej obozowiska
	local cave = if map then map:FindFirstChild("Cave") else nil
	local frames: { Model } = {}
	if cave then
		for _, d in cave:GetDescendants() do
			if d:IsA("Model") and d.Name == "MineFrame" then
				local position = d:GetPivot().Position
				if position.Z > Config.Cave.camp.z and position.Z < Config.Cave.camp.z + 160 then
					table.insert(frames, d)
				end
			end
		end
	end
	for index, frame in frames do
		local cf, size = frame:GetBoundingBox()
		local beamBottom = cf.Position.Y + size.Y / 2 - 1.05
		local inner = size.X / 2 - 1.5
		for _, side in { -1, 1 } do
			if (index + (if side > 0 then 1 else 0)) % 2 == 0 or rng:NextNumber() < 0.4 then
				local corner = cf * CFrame.new(side * inner, 0, 0)
				local at = CFrame.new(corner.Position.X, beamBottom, corner.Position.Z) * CFrame.Angles(0, if side > 0 then math.pi else 0, 0)
				cobweb(folder, at, rng:NextNumber(2.2, 3))
			end
		end
		if rng:NextNumber() < 0.7 then
			local top = (cf * CFrame.new(rng:NextNumber(-3, 1), 0, 0)).Position
			spider(folder, Vector3.new(top.X, beamBottom, top.Z), rng:NextNumber(2, 4))
		end
	end

	-- ===== Bagna: znicze wzdłuż kładki i duchy nad wodą =====
	local swamp = Config.Swamp.camp
	for i = 1, 8 do
		local z = swamp.z + 10 + i * 9
		local x = swamp.x + (if i % 2 == 0 then 3.4 else -3.4)
		local at = placeOnGround(x, z, 8, ignore)
		if at and at.Y < 6 then
			candle(folder, CFrame.new(at), 0.8)
		end
	end
	for _, spot in { { -14, 30 }, { 16, 46 }, { -20, 70 }, { 12, 88 }, { -8, 110 } } do
		local at = placeOnGround(swamp.x + spot[1], swamp.z + spot[2], 8, ignore)
		if at and at.Y < 6 then
			ghost(folder, at + Vector3.new(0, 3.5, 0), rng:NextNumber(0.9, 1.3), rng)
		end
	end

	-- ===== Sekretny zakątek w lesie =====
	local secret = HalloweenDecor.SECRET
	local center = placeOnGround(secret.X, secret.Z, 10, ignore)
	if center and center.Y < 4 then
		local corner = Instance.new("Folder")
		corner.Name = "SecretCorner"
		corner.Parent = folder
		local facing = Vector3.new(secret.X + 10, center.Y, secret.Z)
		for i, offset in { Vector3.new(-1.5, 0, -4), Vector3.new(-2.5, 0, 0), Vector3.new(-1.5, 0, 4) } do
			local at = placeOnGround(center.X + offset.X, center.Z + offset.Z, 10, ignore)
			if at then
				gravestone(corner, CFrame.lookAt(at, facing + offset) * CFrame.Angles(0, math.rad(i * 7 - 14), 0), 1)
				candle(corner, CFrame.new(at + Vector3.new(1.4, 0, -1.2)), 0.8)
			end
		end
		pumpkin(corner, CFrame.lookAt(center + Vector3.new(2, 0, 0), facing), 1.6)
		for _ = 1, 8 do
			local at = placeOnGround(center.X + rng:NextNumber(-4, 4), center.Z + rng:NextNumber(-6, 6), 10, ignore)
			if at then
				leafPile(corner, at, rng)
			end
		end
		ghost(corner, center + Vector3.new(-1, 4.2, 0), 1.2, rng)
		groundMist(corner, center, Vector2.new(10, 14), 0.8, Color3.fromRGB(150, 200, 170))
		-- Niewidzialny znacznik: klient pokazuje komunikat, kiedy gracz go znajdzie
		local marker = part(corner, "SecretMarker", Vector3.new(1, 1, 1), CFrame.new(center + Vector3.new(0, 2, 0)), GHOST)
		marker.Transparency = 1
		CollectionService:AddTag(marker, "HalloweenSecret")
		-- Znicz do zapalenia przy środkowym nagrobku: tytuł „Halloween 2026” (HalloweenService)
		local lightAt = placeOnGround(center.X - 0.6, center.Z, 10, ignore) or center
		local holder = part(corner, "GraveyardCandle", Vector3.new(1.2, 1.2, 1.2), CFrame.new(lightAt + Vector3.new(0, 0.8, 0)), GHOST)
		holder.Transparency = 1
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "LightCandle"
		prompt.ActionText = "Light a candle"
		prompt.ObjectText = "Graveyard"
		prompt.HoldDuration = 1.2
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("TextKey", "PROMPT_LIGHT_CANDLE")
		prompt:SetAttribute("ObjectKey", "OBJ_GRAVEYARD")
		CollectionService:AddTag(prompt, "LocalizedPrompt")
		CollectionService:AddTag(prompt, "GraveyardPrompt")
		prompt.Parent = holder
	end
	folder.Parent = parent
	return folder
end

return HalloweenDecor
