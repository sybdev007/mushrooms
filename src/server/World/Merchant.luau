--!strict
-- Skupywacz grzybów w chatce, Pan Borowik: starszy grzybiarz w zielonej kurtce i fartuchu, z bujną
-- siwą brodą, okrągłymi okularami i kapeluszem-muchomorem. Stoi za ladą, przodem do wnętrza chatki,
-- ręce oparte o blat. Zaokrąglone kształty (siatki kul i walców), a nie klocki.
-- Ma przycisk rozmowy (ProximityPrompt „Merchant”), który otwiera u gracza panel sprzedaży,
-- i tabliczkę z imieniem. Teksty, mruganie, oddech i Ducha na Halloween dokłada klient
-- (src/client/MerchantView.luau, MerchantLook.luau).
-- Części głowy mają atrybut Head (portret w panelu skupu, ruch głowy), części nóg atrybut Legs (duch nóg
-- nie ma). Kopia bez przycisku leży w ReplicatedStorage.NpcPortraits.Merchant (portret w SellPanel).
-- Pivot modelu leży na podłodze pod stopami, przód to -Z (jak w CFrame.lookAt).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Merchant = {}

local SKIN = Color3.fromRGB(242, 196, 162)
local SKIN_SHADE = Color3.fromRGB(226, 172, 138)
local CHEEK = Color3.fromRGB(240, 146, 132)
local NOSE = Color3.fromRGB(234, 152, 122)
local BEARD = Color3.fromRGB(240, 238, 232)
local BEARD_SHADE = Color3.fromRGB(216, 212, 204)
local JACKET = Color3.fromRGB(74, 116, 66)
local JACKET_DARK = Color3.fromRGB(56, 90, 50)
local SHIRT = Color3.fromRGB(238, 228, 204)
local APRON = Color3.fromRGB(200, 160, 106)
local APRON_DARK = Color3.fromRGB(170, 132, 86)
local PANTS = Color3.fromRGB(94, 74, 58)
local BOOTS = Color3.fromRGB(66, 46, 34)
local BELT = Color3.fromRGB(62, 42, 30)
local GOLD = Color3.fromRGB(232, 194, 96)
local CAP = Color3.fromRGB(214, 50, 42)
local GILLS = Color3.fromRGB(240, 228, 208)
local EYE_WHITE = Color3.fromRGB(252, 250, 246)
local PUPIL = Color3.fromRGB(46, 32, 26)

local function part(m: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
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
	p.Parent = m
	return p
end

-- Elipsoida o wymiarach `size`
local function ball(m: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = part(m, name, size, cf, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- Walec od punktu a do punktu b (ręce, nogi)
local function limb(m: Model, name: string, a: Vector3, b: Vector3, diameter: number, color: Color3, material: Enum.Material?): Part
	local direction = b - a
	local up = if math.abs(direction.Unit:Dot(Vector3.yAxis)) > 0.98 then Vector3.zAxis else Vector3.yAxis
	-- Oś walca to X części: obracamy kierunek patrzenia (-Z) na X
	local cf = CFrame.lookAt((a + b) / 2, b, up) * CFrame.Angles(0, math.pi / 2, 0)
	local p = part(m, name, Vector3.new(direction.Magnitude, diameter, diameter), cf, color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- Walec stojący (oś pionowa) o przekroju elipsy: siatka walca z SpecialMesh
local function disc(m: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = part(m, name, size, cf, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Cylinder
	mesh.Parent = p
	return p
end

local function mark(p: BasePart, attribute: string): BasePart
	p:SetAttribute(attribute, true)
	return p
end

-- Okrągła oprawka okularów z cienkich odcinków (Roblox nie ma pierścienia); środek na `center`, przodem do -Z
local function rim(m: Model, center: Vector3, radius: number)
	local pieces = 12
	for i = 1, pieces do
		local a0 = (i - 1) / pieces * math.pi * 2
		local a1 = i / pieces * math.pi * 2
		local p0 = center + Vector3.new(math.cos(a0) * radius, math.sin(a0) * radius, 0)
		local p1 = center + Vector3.new(math.cos(a1) * radius, math.sin(a1) * radius, 0)
		mark(limb(m, "GlassesRim", p0, p1, 0.055, GOLD, Enum.Material.Metal), "Head")
	end
end

-- Kropka na kapeluszu: spłaszczona kulka leżąca na powierzchni elipsoidy (środek c, półosie a i h)
local function capDot(m: Model, capCf: CFrame, a: number, h: number, polar: number, azimuth: number, size: number)
	local local_ = Vector3.new(a * math.sin(polar) * math.cos(azimuth), h * math.cos(polar), a * math.sin(polar) * math.sin(azimuth))
	local normal = Vector3.new(local_.X / (a * a), local_.Y / (h * h), local_.Z / (a * a)).Unit
	local at = capCf * CFrame.new(local_ + normal * 0.02)
	local worldNormal = capCf:VectorToWorldSpace(normal)
	-- Oś Y kropki wzdłuż normalnej powierzchni
	local cf = CFrame.lookAt(at.Position, at.Position + worldNormal) * CFrame.Angles(-math.pi / 2, 0, 0)
	mark(ball(m, "HatDot", Vector3.new(size, 0.1, size * 0.92), cf, Color3.new(1, 1, 1)), "Head")
end

local function buildBody(m: Model)
	-- Buty i nogawki (zza lady widać je tylko z boku)
	for _, side in { -1, 1 } do
		mark(ball(m, "Boot", Vector3.new(0.95, 0.62, 1.3), CFrame.new(side * 0.48, 0.3, -0.14), BOOTS, Enum.Material.Leather), "Legs")
		mark(limb(m, "Leg", Vector3.new(side * 0.48, 0.45, 0), Vector3.new(side * 0.5, 2.0, 0.02), 0.78, PANTS, Enum.Material.Fabric), "Legs")
	end
	-- Biodra, brzuszek w kurtce, kołnierzyk koszuli
	ball(m, "Hips", Vector3.new(2.05, 1.05, 1.5), CFrame.new(0, 2.05, 0), PANTS, Enum.Material.Fabric)
	ball(m, "Body", Vector3.new(2.36, 2.5, 1.84), CFrame.new(0, 3.2, 0), JACKET, Enum.Material.Fabric)
	ball(m, "Collar", Vector3.new(1.35, 0.5, 1.05), CFrame.new(0, 4.32, -0.02), SHIRT, Enum.Material.Fabric)
	-- Pasek ze złotą klamrą
	disc(m, "Belt", Vector3.new(2.3, 0.26, 1.78), CFrame.new(0, 2.38, 0), BELT, Enum.Material.Leather)
	part(m, "Buckle", Vector3.new(0.4, 0.32, 0.08), CFrame.new(0, 2.38, -0.9), GOLD, Enum.Material.Metal)
	-- Fartuch na brzuszku, kieszonka i grzybek wystający z kieszonki
	ball(m, "Apron", Vector3.new(1.85, 2.0, 0.5), CFrame.new(0, 2.85, -0.74), APRON, Enum.Material.Fabric)
	ball(m, "Pocket", Vector3.new(0.78, 0.5, 0.2), CFrame.new(0.32, 2.55, -0.98), APRON_DARK, Enum.Material.Fabric)
	limb(m, "PocketShroomStem", Vector3.new(0.46, 2.62, -1.0), Vector3.new(0.5, 2.98, -1.02), 0.14, GILLS)
	ball(m, "PocketShroomCap", Vector3.new(0.38, 0.2, 0.38), CFrame.new(0.5, 3.04, -1.02) * CFrame.Angles(0, 0, math.rad(-12)), CAP)
	-- Guziki kurtki nad fartuchem
	for i, y in { 3.95, 3.65 } do
		ball(m, "Button", Vector3.new(0.14, 0.14, 0.08), CFrame.new(0, y, -0.9 + i * 0.03), GOLD, Enum.Material.Metal)
	end

	-- Ramiona, łokcie, przedramiona i dłonie oparte o blat lady (blat na wysokości 3,4)
	for _, side in { -1, 1 } do
		local shoulder = Vector3.new(side * 1.16, 4.02, 0.05)
		local elbow = Vector3.new(side * 1.32, 3.38, -0.22)
		local wrist = Vector3.new(side * 0.98, 3.6, -1.06)
		ball(m, "Shoulder", Vector3.new(0.92, 0.9, 0.92), CFrame.new(shoulder), JACKET, Enum.Material.Fabric)
		limb(m, "UpperArm", shoulder, elbow, 0.66, JACKET, Enum.Material.Fabric)
		ball(m, "Elbow", Vector3.new(0.66, 0.66, 0.66), CFrame.new(elbow), JACKET_DARK, Enum.Material.Fabric)
		limb(m, "Forearm", elbow, wrist, 0.6, JACKET, Enum.Material.Fabric)
		limb(m, "Cuff", wrist + (elbow - wrist).Unit * 0.12, wrist - (elbow - wrist).Unit * 0.06, 0.66, SHIRT, Enum.Material.Fabric)
		ball(m, "Hand", Vector3.new(0.62, 0.4, 0.78), CFrame.new(side * 0.94, 3.6, -1.26) * CFrame.Angles(0, math.rad(side * 12), 0), SKIN)
		ball(m, "Thumb", Vector3.new(0.22, 0.2, 0.34), CFrame.new(side * 0.68, 3.66, -1.2) * CFrame.Angles(0, math.rad(side * 30), 0), SKIN)
	end
end

local function buildHead(m: Model): BasePart
	local y = 5.25
	local head = mark(ball(m, "Head", Vector3.new(1.56, 1.5, 1.46), CFrame.new(0, y, -0.05), SKIN), "Head")
	-- Uszy, policzki z rumieńcem i duży okrągły nos
	for _, side in { -1, 1 } do
		mark(ball(m, "Ear", Vector3.new(0.26, 0.44, 0.24), CFrame.new(side * 0.77, y, 0.02), SKIN_SHADE), "Head")
		mark(ball(m, "Cheek", Vector3.new(0.42, 0.32, 0.24), CFrame.new(side * 0.43, y - 0.22, -0.6), CHEEK), "Head")
	end
	mark(ball(m, "Nose", Vector3.new(0.5, 0.42, 0.44), CFrame.new(0, y - 0.12, -0.76), NOSE), "Head")

	-- Oczy: białko, źrenica, błysk; powieki (do mrugania) są niewidoczne, dopóki klient ich nie pokaże
	for _, side in { -1, 1 } do
		local eye = Vector3.new(side * 0.29, y + 0.15, -0.66)
		mark(ball(m, "EyeWhite", Vector3.new(0.27, 0.31, 0.12), CFrame.new(eye), EYE_WHITE), "Head")
		mark(ball(m, "Pupil", Vector3.new(0.15, 0.19, 0.08), CFrame.new(eye + Vector3.new(-side * 0.01, -0.01, -0.05)), PUPIL), "Head")
		mark(ball(m, "EyeShine", Vector3.new(0.07, 0.07, 0.03), CFrame.new(eye + Vector3.new(-side * 0.03, 0.05, -0.09)), Color3.new(1, 1, 1)), "Head")
		local lid = mark(ball(m, "Eyelid", Vector3.new(0.31, 0.34, 0.15), CFrame.new(eye + Vector3.new(0, 0, -0.03)), SKIN_SHADE), "Head")
		lid.Transparency = 1
		-- Krzaczaste brwi, zewnętrzne końce niżej (dobrotliwa mina)
		mark(ball(m, "Brow", Vector3.new(0.5, 0.17, 0.2), CFrame.new(side * 0.31, y + 0.42, -0.62) * CFrame.Angles(0, 0, math.rad(side * -14)), BEARD), "Head")
		-- Okrągłe okulary w złotej oprawce
		rim(m, eye + Vector3.new(0, 0, -0.14), 0.23)
		mark(limb(m, "GlassesArm", eye + Vector3.new(side * 0.23, 0.02, -0.12), Vector3.new(side * 0.74, y + 0.12, -0.05), 0.05, GOLD, Enum.Material.Metal), "Head")
	end
	mark(limb(m, "GlassesBridge", Vector3.new(-0.07, y + 0.2, -0.82), Vector3.new(0.07, y + 0.2, -0.82), 0.05, GOLD, Enum.Material.Metal), "Head")

	-- Wąsy z podkręconymi końcami i bujna broda w kilku kłębach
	for _, side in { -1, 1 } do
		mark(ball(m, "Mustache", Vector3.new(0.64, 0.27, 0.32), CFrame.new(side * 0.27, y - 0.33, -0.74) * CFrame.Angles(0, math.rad(side * 10), math.rad(side * -16)), BEARD), "Head")
		mark(ball(m, "MustacheCurl", Vector3.new(0.22, 0.22, 0.22), CFrame.new(side * 0.6, y - 0.29, -0.62), BEARD), "Head")
		mark(ball(m, "BeardSide", Vector3.new(0.62, 0.95, 0.72), CFrame.new(side * 0.6, y - 0.5, -0.22), BEARD_SHADE), "Head")
		-- Siwe włosy spod kapelusza
		mark(ball(m, "Hair", Vector3.new(0.5, 0.56, 0.9), CFrame.new(side * 0.64, y + 0.32, 0.22), BEARD), "Head")
	end
	mark(ball(m, "Hair", Vector3.new(1.34, 0.6, 0.62), CFrame.new(0, y + 0.28, 0.56), BEARD), "Head")
	mark(ball(m, "Beard", Vector3.new(1.58, 1.32, 1.0), CFrame.new(0, y - 0.72, -0.42), BEARD), "Head")
	mark(ball(m, "BeardTip", Vector3.new(1.06, 0.86, 0.76), CFrame.new(0, y - 1.26, -0.48), BEARD), "Head")

	-- Kapelusz-muchomor: czerwona kopuła z białymi kropkami, kremowe blaszki pod spodem, lekko na bakier
	local capCf = CFrame.new(0, y + 1.22, 0) * CFrame.Angles(0, 0, math.rad(-6))
	local capA, capH = 1.5, 0.64
	mark(ball(m, "HatCap", Vector3.new(capA * 2, capH * 2, capA * 2), capCf, CAP), "Head")
	mark(ball(m, "HatGills", Vector3.new(2.78, 0.2, 2.78), capCf * CFrame.new(0, -0.44, 0), GILLS), "Head")
	capDot(m, capCf, capA, capH, 0, 0, 0.5)
	for k = 1, 5 do
		capDot(m, capCf, capA, capH, math.rad(36), k / 5 * math.pi * 2 + 0.3, 0.42 - (k % 2) * 0.08)
	end
	for k = 1, 7 do
		capDot(m, capCf, capA, capH, math.rad(64), k / 7 * math.pi * 2, 0.36 - (k % 3) * 0.05)
	end
	return head
end

-- at: miejsce na podłodze, przód modelu patrzy wzdłuż -Z tego CFrame
function Merchant.build(parent: Instance, at: CFrame, promptDistance: number): Model
	local m = Instance.new("Model")
	m.Name = "Merchant"
	-- Cały naraz (StreamingEnabled): klient nie dostaje połowy postaci, a portret i Duch mają wszystkie części
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	local root = part(m, "Root", Vector3.new(2, 2, 1), CFrame.new(0, 3, 0), JACKET)
	root.Transparency = 1

	buildBody(m)
	local head = buildHead(m)

	m.PrimaryPart = root
	-- Pivot na podłodze pod stopami (model jest budowany wokół początku układu). WorldPivot nic tu
	-- nie daje, bo przy ustawionym PrimaryPart Roblox liczy pivot z PivotOffset tej części.
	root.PivotOffset = root.CFrame:Inverse()

	-- Portret do panelu skupu: kopia bez przycisku i tabliczki, w początku układu, przodem do -Z
	local portraits = ReplicatedStorage:FindFirstChild("NpcPortraits")
	if not portraits then
		portraits = Instance.new("Folder")
		portraits.Name = "NpcPortraits"
		portraits.Parent = ReplicatedStorage
	end
	local old = portraits:FindFirstChild("Merchant")
	if old then
		old:Destroy()
	end
	m:Clone().Parent = portraits

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
	-- Tabliczka nad głową, ale wysunięta do przodu (w stronę sali), bo skupywacz stoi tuż przy
	-- tylnej ścianie i szeroki napis wchodził w bale. StudsOffsetWorldSpace liczy się w osiach głowy,
	-- a przód to lokalne -Z, więc „do przodu” = ujemne Z. Kapelusz sięga ok. 1,9 nad środek głowy.
	tag.StudsOffsetWorldSpace = Vector3.new(0, 2.6, -2.6)
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

	m:PivotTo(at)
	CollectionService:AddTag(m, "Merchant")
	m.Parent = parent
	return m
end

return Merchant
