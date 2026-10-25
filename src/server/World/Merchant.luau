--!strict
-- Skupywacz grzybów w chatce: starszy grzybiarz w zielonej kurtce i fartuchu, z siwą brodą
-- i kapeluszem w kształcie muchomora. Stoi za ladą, przodem do wnętrza chatki.
-- Ma przycisk rozmowy (ProximityPrompt „Merchant”), który otwiera u gracza panel sprzedaży,
-- i tabliczkę z imieniem. Teksty dokłada klient (src/client/MerchantView.luau) w języku gracza.
-- Pivot modelu leży na podłodze pod stopami, przód to -Z (jak w CFrame.lookAt).

local CollectionService = game:GetService("CollectionService")

local Merchant = {}

local VERTICAL = CFrame.Angles(0, 0, math.rad(90))

local SKIN = Color3.fromRGB(240, 196, 160)
local JACKET = Color3.fromRGB(72, 110, 64)
local APRON = Color3.fromRGB(196, 168, 120)
local PANTS = Color3.fromRGB(70, 56, 46)
local BEARD = Color3.fromRGB(222, 218, 210)
local CAP = Color3.fromRGB(214, 52, 44)
local BOOTS = Color3.fromRGB(52, 38, 30)

local function part(m: Model, name: string, size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.Parent = m
	return p
end

local function sphere(m: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = part(m, name, size, cf, color)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	if material then
		p.Material = material
	end
	return p
end

-- at: miejsce na podłodze, przód modelu patrzy wzdłuż -Z tego CFrame
function Merchant.build(parent: Instance, at: CFrame, promptDistance: number): Model
	local m = Instance.new("Model")
	m.Name = "Merchant"

	local root = part(m, "Root", Vector3.new(2, 2, 1), CFrame.new(0, 3, 0), JACKET)
	root.Transparency = 1
	root.CanQuery = false

	-- Nogi i buty
	for _, side in { -1, 1 } do
		part(m, "Leg", Vector3.new(0.8, 2, 0.8), CFrame.new(side * 0.45, 1.2, 0), PANTS)
		part(m, "Boot", Vector3.new(0.9, 0.5, 1.1), CFrame.new(side * 0.45, 0.25, -0.1), BOOTS)
	end

	-- Tułów: kurtka, fartuch z kieszonką i pasek
	part(m, "Body", Vector3.new(2.1, 2.3, 1.2), CFrame.new(0, 3.35, 0), JACKET)
	part(m, "Apron", Vector3.new(1.6, 2.4, 0.12), CFrame.new(0, 3.05, -0.62), APRON)
	part(m, "Pocket", Vector3.new(0.7, 0.45, 0.06), CFrame.new(0, 2.7, -0.7), APRON:Lerp(Color3.new(0, 0, 0), 0.15))
	part(m, "Belt", Vector3.new(2.15, 0.22, 1.25), CFrame.new(0, 2.35, 0), BOOTS)

	-- Ręce oparte o ladę (lekko do przodu)
	for _, side in { -1, 1 } do
		local arm = CFrame.new(side * 1.3, 3.6, -0.2) * CFrame.Angles(math.rad(35), 0, math.rad(side * 6)) * CFrame.new(0, -0.7, 0)
		part(m, "Arm", Vector3.new(0.6, 1.8, 0.6), arm, JACKET)
		sphere(m, "Hand", Vector3.new(0.62, 0.62, 0.62), arm * CFrame.new(0, -1, 0), SKIN)
	end

	-- Głowa: twarz, nos, oczy, siwa broda i wąsy
	local head = sphere(m, "Head", Vector3.new(1.5, 1.5, 1.4), CFrame.new(0, 5.25, 0), SKIN)
	sphere(m, "Nose", Vector3.new(0.38, 0.32, 0.34), CFrame.new(0, 5.2, -0.72), SKIN:Lerp(Color3.fromRGB(220, 120, 100), 0.35))
	for _, side in { -1, 1 } do
		sphere(m, "Eye", Vector3.new(0.17, 0.2, 0.08), CFrame.new(side * 0.3, 5.45, -0.66), Color3.fromRGB(30, 24, 20))
		part(m, "Brow", Vector3.new(0.36, 0.09, 0.08), CFrame.new(side * 0.31, 5.66, -0.65) * CFrame.Angles(0, 0, math.rad(side * -8)), BEARD)
		sphere(m, "Mustache", Vector3.new(0.5, 0.2, 0.2), CFrame.new(side * 0.22, 5.02, -0.7) * CFrame.Angles(0, 0, math.rad(side * -18)), BEARD)
	end
	sphere(m, "Beard", Vector3.new(1.3, 1.1, 0.8), CFrame.new(0, 4.6, -0.42), BEARD)

	-- Kapelusz-muchomor: czerwony kapelusz z białymi kropkami na krótkiej nóżce
	part(m, "HatStem", Vector3.new(0.5, 1.15, 1.15), CFrame.new(0, 5.95, 0) * VERTICAL, Color3.fromRGB(236, 228, 212), Enum.PartType.Cylinder)
	local cap = sphere(m, "HatCap", Vector3.new(2.5, 1.1, 2.5), CFrame.new(0, 6.3, 0), CAP)
	for k = 1, 7 do
		local angle = k * math.pi * 2 / 7
		local ring = if k % 2 == 0 then 0.55 else 0.85
		sphere(m, "HatDot", Vector3.new(0.3, 0.12, 0.3), cap.CFrame * CFrame.new(math.cos(angle) * ring, 0.42 - (ring - 0.55) * 0.35, math.sin(angle) * ring), Color3.new(1, 1, 1))
	end
	sphere(m, "HatDot", Vector3.new(0.34, 0.12, 0.34), cap.CFrame * CFrame.new(0, 0.55, 0), Color3.new(1, 1, 1))

	-- Przycisk rozmowy i tabliczka z imieniem
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "MerchantPrompt"
	prompt.ActionText = "NPC_SELL"
	prompt.ObjectText = "NPC_NAME"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.MaxActivationDistance = promptDistance
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.Parent = root

	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	tag.Size = UDim2.fromOffset(180, 46)
	tag.StudsOffset = Vector3.new(0, 2.2, 0)
	tag.MaxDistance = 40
	tag.LightInfluence = 0
	tag.Parent = head
	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.Size = UDim2.new(1, 0, 0.58, 0)
	name.BackgroundTransparency = 1
	name.TextColor3 = Color3.fromRGB(255, 236, 190)
	name.Font = Enum.Font.FredokaOne
	name.TextScaled = true
	name.Text = ""
	name.Parent = tag
	local role = Instance.new("TextLabel")
	role.Name = "Role"
	role.Size = UDim2.new(1, 0, 0.42, 0)
	role.Position = UDim2.fromScale(0, 0.58)
	role.BackgroundTransparency = 1
	role.TextColor3 = Color3.fromRGB(150, 226, 110)
	role.Font = Enum.Font.GothamBold
	role.TextScaled = true
	role.Text = ""
	role.Parent = tag
	for _, label in { name, role } do
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Color3.fromRGB(50, 30, 16)
		stroke.Parent = label
	end

	m.PrimaryPart = root
	-- Pivot na podłodze pod stopami (model jest budowany wokół początku układu). WorldPivot nic tu
	-- nie daje, bo przy ustawionym PrimaryPart Roblox liczy pivot z PivotOffset tej części.
	root.PivotOffset = root.CFrame:Inverse()
	m:PivotTo(at)
	CollectionService:AddTag(m, "Merchant")
	m.Parent = parent
	return m
end

return Merchant
