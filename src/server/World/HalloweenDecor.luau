--!strict
-- Wystrój na Halloween (Noc Dziadów): voxelowe dynie ze świecącymi buziami i znicze przy chatce,
-- na ścieżce do lasu, w obozowisku w jaskini i na przystani na bagnach. GameService buduje go
-- w czasie eventu i usuwa po nim. Wszystko jest ozdobą: bez kolizji, bez dotyku i bez celowania.

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
	sign.Size = UDim2.fromOffset(220, 44)
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
	folder.Parent = parent
	return folder
end

return HalloweenDecor
