--!strict
-- Wystrój na Zimę: choinka z prezentami przed gankiem (tu losuje się prezenty za płatki śniegu,
-- WinterService), bałwany przy chatce i przy ścieżce do lasu, kolorowe lampki pod daszkiem ganku.
-- GameService buduje go w czasie eventu (albo w podglądzie z panelu DEV) i usuwa po nim.
-- Śnieg na ziemi i drzewach oraz padający śnieg robi każdy klient u siebie (WinterFx).
-- Wszystko jest ozdobą: bez kolizji, bez dotyku i bez celowania (poza przyciskiem choinki).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local WinterDecor = {}

-- Choinka stoi tam, gdzie w Halloween stał kocioł (miejsce zarezerwowane w MapBuilder)
WinterDecor.TREE = Vector3.new(-13, 0, 0.5)

local NEEDLES = Color3.fromRGB(44, 110, 62)
local NEEDLES_DARK = Color3.fromRGB(32, 86, 50)
local TRUNK = Color3.fromRGB(104, 70, 44)
local SNOW = Color3.fromRGB(246, 250, 255)
local COAL = Color3.fromRGB(34, 32, 36)
local CARROT = Color3.fromRGB(240, 128, 40)
local STAR = Color3.fromRGB(255, 214, 80)
local BULBS = {
	Color3.fromRGB(255, 70, 70),
	Color3.fromRGB(255, 200, 60),
	Color3.fromRGB(80, 200, 255),
	Color3.fromRGB(120, 255, 130),
	Color3.fromRGB(255, 120, 220),
}
local WRAPS = {
	{ Color3.fromRGB(200, 40, 50), Color3.fromRGB(255, 214, 80) },
	{ Color3.fromRGB(40, 110, 200), Color3.fromRGB(250, 250, 255) },
	{ Color3.fromRGB(60, 150, 80), Color3.fromRGB(220, 40, 50) },
	{ Color3.fromRGB(150, 70, 190), Color3.fromRGB(255, 214, 80) },
}

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
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
	p.CastShadow = false
	p.Parent = parent
	return p
end

-- Ostrosłup z czterech CornerWedge (piętro choinki), wierzchołek nad `center`
local function cone(parent: Instance, center: Vector3, width: number, height: number, yaw: number, color: Color3)
	for i = 0, 3 do
		local p = Instance.new("CornerWedgePart")
		p.Name = "Needles"
		p.Size = Vector3.new(width / 2, height, width / 2)
		p.CFrame = CFrame.new(center + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, yaw + math.rad(90 * i), 0) * CFrame.new(-width / 4, 0, width / 4)
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
		p.Parent = parent
	end
end

local function groundAt(x: number, z: number, from: number, ignore: { Instance }): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local result = Workspace:Raycast(Vector3.new(x, from, z), Vector3.new(0, -from - 20, 0), params)
	return if result then result.Position.Y else nil
end

local function bulb(parent: Instance, position: Vector3, color: Color3, size: number)
	part(parent, "Bulb", Vector3.one * size, CFrame.new(position), color, Enum.Material.Neon, Enum.PartType.Ball)
end

-- Prezent: pudełko z krzyżem wstążki i kokardą na wierzchu
local function present(parent: Instance, cf: CFrame, size: Vector3, wrap: { Color3 })
	part(parent, "Present", size, cf * CFrame.new(0, size.Y / 2, 0), wrap[1])
	part(parent, "Ribbon", Vector3.new(size.X + 0.04, size.Y + 0.04, size.Z * 0.18), cf * CFrame.new(0, size.Y / 2, 0), wrap[2])
	part(parent, "Ribbon", Vector3.new(size.X * 0.18, size.Y + 0.04, size.Z + 0.04), cf * CFrame.new(0, size.Y / 2, 0), wrap[2])
	for _, side in { -1, 1 } do
		part(parent, "Bow", Vector3.new(size.X * 0.3, size.Y * 0.22, size.Z * 0.16), cf * CFrame.new(side * size.X * 0.14, size.Y + size.Y * 0.08, 0) * CFrame.Angles(0, 0, side * math.rad(25)), wrap[2])
	end
end

-- Choinka z bombkami, lampkami, gwiazdą i prezentami pod spodem; przycisk i napis nad nią
local function giftTree(parent: Instance, base: CFrame, rng: Random)
	local m = Instance.new("Model")
	m.Name = "GiftTree"
	local origin = base.Position
	part(m, "Trunk", Vector3.new(1.6, 1.4, 1.4), base * CFrame.new(0, 0.8, 0) * CFrame.Angles(0, 0, math.rad(90)), TRUNK, nil, Enum.PartType.Cylinder)
	-- Piętra igieł (od dołu), lekko obrócone względem siebie
	local tiers = { { 8, 4.6, 1.4 }, { 6.4, 4.2, 3.8 }, { 4.8, 3.6, 6.2 }, { 3.2, 3.2, 8.4 } }
	for index, tier in tiers do
		local width, height, y = tier[1], tier[2], tier[3]
		cone(m, origin + Vector3.new(0, y, 0), width, height, math.rad(index * 22), if index % 2 == 0 then NEEDLES_DARK else NEEDLES)
		-- Śnieg na brzegu piętra
		for i = 0, 3 do
			local a = math.rad(index * 22 + i * 90 + 45)
			local r = width * 0.5
			part(m, "Snow", Vector3.new(width * 0.35, 0.18, 0.5), CFrame.new(origin + Vector3.new(math.cos(a) * r * 0.62, y + 0.15, math.sin(a) * r * 0.62)) * CFrame.Angles(0, -a, 0), SNOW)
		end
	end
	-- Bombki na zboczach pięter
	for index, tier in tiers do
		local width, height, y = tier[1], tier[2], tier[3]
		for _ = 1, 5 do
			local a = rng:NextNumber(0, math.pi * 2)
			local t = rng:NextNumber(0.1, 0.6)
			local r = width * 0.5 * (1 - t) * 0.9
			local p = origin + Vector3.new(math.cos(a) * r, y + height * t, math.sin(a) * r)
			bulb(m, p, BULBS[rng:NextInteger(1, #BULBS)], 0.42 + (#tiers - index) * 0.04)
		end
	end
	-- Lampki: spirala od dołu do czubka
	local lights = 46
	for i = 0, lights - 1 do
		local t = i / lights
		local y = 1.6 + t * 9.6
		local r = 3.9 * (1 - t) + 0.4
		local a = t * math.pi * 2 * 4
		bulb(m, origin + Vector3.new(math.cos(a) * r, y, math.sin(a) * r), BULBS[i % #BULBS + 1], 0.24)
	end
	-- Gwiazda na czubku (ośmioramienna) ze światłem
	local starAt = base * CFrame.new(0, 12.2, 0)
	local core = part(m, "Star", Vector3.new(0.5, 0.5, 0.25), starAt, STAR, Enum.Material.Neon)
	for i = 0, 3 do
		local length = if i % 2 == 0 then 1.6 else 1.1
		part(m, "StarRay", Vector3.new(length, 0.26, 0.2), starAt * CFrame.Angles(0, 0, math.rad(i * 45)), STAR, Enum.Material.Neon)
	end
	local glow = Instance.new("PointLight")
	glow.Color = STAR
	glow.Range = 14
	glow.Brightness = 1.2
	glow.Shadows = false
	glow.Parent = core
	-- Ciepłe światło od lampek na śnieg wokół
	local warm = Instance.new("PointLight")
	warm.Color = Color3.fromRGB(255, 220, 170)
	warm.Range = 16
	warm.Brightness = 0.8
	warm.Shadows = false
	warm.Parent = m:FindFirstChild("Trunk")
	-- Prezenty pod choinką
	for i = 0, 6 do
		local a = math.rad(i * 51 + 10)
		local r = rng:NextNumber(3.2, 4.4)
		local size = Vector3.new(rng:NextNumber(0.9, 1.6), rng:NextNumber(0.7, 1.3), rng:NextNumber(0.9, 1.6))
		local at = CFrame.new(origin + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
		present(m, at, size, WRAPS[i % #WRAPS + 1])
	end
	-- Przycisk i napis nad choinką (tekst w języku gracza wstawia klient, GiftTreeView)
	local holder = part(m, "GiftTreeBase", Vector3.new(2, 2, 2), base * CFrame.new(0, 2, 0), TRUNK)
	holder.Transparency = 1
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GiftTreePrompt"
	prompt.ActionText = "GIFT_ACTION"
	prompt.ObjectText = "GIFT_NAME"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0.3
	prompt.Parent = holder
	CollectionService:AddTag(prompt, "GiftTreePrompt")
	local sign = Instance.new("BillboardGui")
	sign.Name = "GiftTreeSign"
	sign.Size = UDim2.fromOffset(240, 70)
	sign.StudsOffsetWorldSpace = Vector3.new(0, 12.5, 0)
	sign.MaxDistance = 80
	sign.LightInfluence = 0
	sign.Parent = holder
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(220, 245, 255)
	label.Text = "🎄"
	label.Parent = sign
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Color3.fromRGB(20, 30, 50)
	stroke.Parent = label
	CollectionService:AddTag(sign, "GiftTreeSign")
	m.PrimaryPart = holder
	m.Parent = parent
end

-- Bałwan: trzy kule, węgielki, marchewka, cylinder i szalik
local function snowman(parent: Instance, base: CFrame, s: number)
	local m = Instance.new("Model")
	m.Name = "Snowman"
	local sizes = { 2.4, 1.8, 1.3 }
	local y = 0
	for index, d in sizes do
		local size = d * s
		local center = y + size * 0.42
		part(m, if index == 3 then "Head" else "Body", Vector3.one * size, base * CFrame.new(0, center, 0), SNOW, nil, Enum.PartType.Ball)
		y = center + size * 0.42
	end
	local headSize = sizes[3] * s
	local head = base * CFrame.new(0, y - headSize * 0.42, 0)
	local front = head * CFrame.new(0, 0, -headSize * 0.47)
	for _, x in { -0.18, 0.18 } do
		part(m, "Eye", Vector3.one * headSize * 0.13, front * CFrame.new(x * headSize, headSize * 0.12, 0), COAL, nil, Enum.PartType.Ball)
	end
	part(m, "Nose", Vector3.new(headSize * 0.12, headSize * 0.12, headSize * 0.5), front * CFrame.new(0, 0, -headSize * 0.2), CARROT)
	-- Guziki na brzuchu
	local belly = base * CFrame.new(0, sizes[1] * s * 0.84 + sizes[2] * s * 0.42, 0)
	for i = -1, 1 do
		part(m, "Button", Vector3.one * 0.18 * s, belly * CFrame.new(0, i * sizes[2] * s * 0.22, -sizes[2] * s * 0.49), COAL, nil, Enum.PartType.Ball)
	end
	-- Szalik między brzuchem a głową
	local neck = base * CFrame.new(0, y - headSize * 0.86, 0)
	part(m, "Scarf", Vector3.new(headSize * 0.22, headSize * 0.95, headSize * 0.95), neck * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(200, 40, 50), nil, Enum.PartType.Cylinder)
	part(m, "ScarfEnd", Vector3.new(headSize * 0.22, headSize * 0.6, 0.12 * s), neck * CFrame.new(headSize * 0.25, -headSize * 0.32, -headSize * 0.45) * CFrame.Angles(0, 0, math.rad(-8)), Color3.fromRGB(200, 40, 50))
	-- Cylinder
	local hat = base * CFrame.new(0, y - headSize * 0.08, 0)
	part(m, "Brim", Vector3.new(0.1 * s, headSize * 0.95, headSize * 0.95), hat * CFrame.Angles(0, 0, math.rad(90)), COAL, nil, Enum.PartType.Cylinder)
	part(m, "Hat", Vector3.new(headSize * 0.55, headSize * 0.62, headSize * 0.62), hat * CFrame.new(0, headSize * 0.28, 0) * CFrame.Angles(0, 0, math.rad(90)), COAL, nil, Enum.PartType.Cylinder)
	m.Parent = parent
end

-- Girlanda lampek: zwis od a do b (łuk w dół o sag)
local function stringLights(parent: Instance, a: Vector3, b: Vector3, sag: number, count: number)
	local previous = a
	for i = 1, count do
		local t = i / count
		local p = a:Lerp(b, t) - Vector3.new(0, math.sin(t * math.pi) * sag, 0)
		local wire = part(parent, "Wire", Vector3.new(0.05, 0.05, (p - previous).Magnitude), CFrame.lookAt((p + previous) / 2, p), Color3.fromRGB(30, 40, 30))
		wire.Name = "Wire"
		if i < count then
			bulb(parent, p - Vector3.new(0, 0.12, 0), BULBS[i % #BULBS + 1], 0.26)
		end
		previous = p
	end
end

function WinterDecor.build(parent: Instance, _map: any): Folder
	local folder = Instance.new("Folder")
	folder.Name = "WinterDecor"
	local ignore: { Instance } = { folder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	local rng = Random.new(Config.SpotSeed + 41)
	-- Choinka przed gankiem
	local tree = WinterDecor.TREE
	local ty = groundAt(tree.X, tree.Z, 8, ignore)
	if ty and ty < 4 then
		giftTree(folder, CFrame.new(tree.X, ty, tree.Z), rng)
	end
	-- Bałwany: przy rogach ganku, przy choince i wzdłuż ścieżki do lasu
	for _, spot in {
		{ 15.4, -8, 0.9 },
		{ -17.6, -6.5, 0.75 },
		{ -7.2, 4.4, 0.6 },
		{ 6.5, 16, 0.8 },
		{ -6.8, 30, 0.7 },
	} do
		local y = groundAt(spot[1], spot[2], 8, ignore)
		if y and y < 4 then
			-- Bałwan patrzy w stronę ścieżki (x = 0)
			local at = Vector3.new(spot[1], y, spot[2])
			local look = Vector3.new(0, y, spot[2] + 4)
			snowman(folder, CFrame.lookAt(at, look) * CFrame.Angles(0, math.rad(rng:NextNumber(-15, 15)), 0), spot[3])
		end
	end
	-- Lampki pod daszkiem ganku (między słupkami ganku, dwa łuki jak girlanda w Halloween)
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
		local topY = posts[1].Position.Y + posts[1].Size.Y / 2 - 0.5
		local left = Vector3.new(posts[1].Position.X + 0.5, topY, posts[1].Position.Z)
		local right = Vector3.new(posts[2].Position.X - 0.5, topY, posts[2].Position.Z)
		local mid = (left + right) / 2
		stringLights(folder, left, mid - Vector3.new(4.5, 0, 0), 1.2, 12)
		stringLights(folder, mid + Vector3.new(4.5, 0, 0), right, 1.2, 12)
	end
	folder.Parent = parent
	return folder
end

-- Po evencie: nic do cofania na mapie (śnieg na drzewach i ziemi jest tylko u klientów)
function WinterDecor.remove(_map: any) end

return WinterDecor
