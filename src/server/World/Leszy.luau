--!strict
-- Leszy: wysoki duch lasu z kory i mchu, z porożem z gałęzi i czerwonymi oczami.
-- Ten sam model służy jako uśpiony posąg w gnieździe i jako goniący potwór.
-- Pivot modelu leży na ziemi pod stopami, przód to -Z (jak w CFrame.lookAt).

local Palette = require(script.Parent.Palette)

local Leszy = {}

local VERTICAL = CFrame.Angles(0, 0, math.rad(90))

Leszy.EYE_COLOR = Color3.fromRGB(255, 40, 30)
Leszy.EYE_SLEEP = Color3.fromRGB(90, 20, 18)

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
	p.CanQuery = false
	p.Parent = m
	return p
end

-- Gałąź od punktu `from` w kierunku podanym kątami (yaw wokół pionu, tilt od pionu)
local function branch(m: Model, from: Vector3, yaw: number, tilt: number, length: number, thickness: number)
	local dir = CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, -tilt)
	-- Walec leży wzdłuż osi X; obracamy go do pionu i pochylamy
	local cf = CFrame.new(from) * dir * CFrame.new(0, length / 2, 0) * VERTICAL
	part(m, "Antler", Vector3.new(length, thickness, thickness), cf, Palette.deadWood, Enum.PartType.Cylinder)
end

-- Buduje Leszego stojącego w `at` (pivot na ziemi). awake = czerwone, świecące oczy.
function Leszy.build(parent: Instance, at: CFrame, awake: boolean): Model
	local m = Instance.new("Model")
	m.Name = "Leszy"
	local bark = Palette.trunkDark
	local moss = Palette.moss

	local root = part(m, "Root", Vector3.new(2, 1, 2), CFrame.new(0, 0.5, 0), bark)
	root.Transparency = 1

	-- Nogi jak dwa pnie
	for _, side in { -1, 1 } do
		part(m, "Leg", Vector3.new(5, 1.4, 1.4), CFrame.new(side * 1.1, 2.5, 0) * VERTICAL, bark, Enum.PartType.Cylinder)
		-- Korzenie zamiast stóp
		part(m, "Root", Vector3.new(1.8, 0.5, 2.4), CFrame.new(side * 1.2, 0.25, -0.4), bark)
	end

	-- Tułów z kory, z mchem na ramionach
	part(m, "Body", Vector3.new(3.8, 5, 2.4), CFrame.new(0, 7, 0), bark)
	part(m, "Chest", Vector3.new(3, 2.4, 0.5), CFrame.new(0, 7.6, -1.25), Palette.trunk)
	for _, side in { -1, 1 } do
		part(m, "Moss", Vector3.new(1.8, 0.6, 2.6), CFrame.new(side * 1.6, 9.6, 0), moss)
	end

	-- Długie ręce do kolan, z palcami z gałązek
	for _, side in { -1, 1 } do
		local shoulder = Vector3.new(side * 2.4, 9.2, 0)
		local armCf = CFrame.new(shoulder) * CFrame.Angles(math.rad(12), 0, math.rad(side * 10)) * CFrame.new(0, -3.2, 0)
		part(m, "Arm", Vector3.new(6.4, 0.9, 0.9), armCf * VERTICAL, bark, Enum.PartType.Cylinder)
		local hand = armCf * CFrame.new(0, -3.2, 0)
		for finger = -1, 1 do
			local fcf = hand * CFrame.Angles(math.rad(20), math.rad(finger * 25), 0) * CFrame.new(0, -0.9, 0)
			part(m, "Finger", Vector3.new(1.8, 0.28, 0.28), fcf * VERTICAL, Palette.deadWood, Enum.PartType.Cylinder)
		end
	end

	-- Głowa: wydłużona czaszka z kory, broda z mchu
	local head = part(m, "Head", Vector3.new(2.4, 2.8, 2.2), CFrame.new(0, 11, -0.2), Palette.deadWood)
	part(m, "Beard", Vector3.new(1.8, 1.6, 0.6), CFrame.new(0, 9.7, -1.1), moss)

	local eyeColor = if awake then Leszy.EYE_COLOR else Leszy.EYE_SLEEP
	for _, side in { -1, 1 } do
		local eye = part(m, "Eye", Vector3.new(0.45, 0.45, 0.45), CFrame.new(side * 0.55, 11.3, -1.3), eyeColor, Enum.PartType.Ball)
		eye.Material = Enum.Material.Neon
		eye.CastShadow = false
	end
	local light = Instance.new("PointLight")
	light.Name = "EyeLight"
	light.Color = Leszy.EYE_COLOR
	light.Range = 14
	light.Brightness = if awake then 2 else 0
	light.Parent = head

	-- Poroże z gałęzi
	for _, side in { -1, 1 } do
		local base = Vector3.new(side * 0.8, 12.2, -0.2)
		branch(m, base, 0, side * math.rad(25), 3.2, 0.35)
		local tip = base + Vector3.new(side * 1.35, 2.9, 0)
		branch(m, tip, 0, side * math.rad(55), 1.8, 0.25)
		branch(m, tip, 0, side * math.rad(-5), 1.6, 0.25)
		branch(m, base + Vector3.new(side * 0.6, 1.4, 0), math.rad(side * 40), side * math.rad(70), 1.5, 0.22)
	end

	m.PrimaryPart = root
	m.WorldPivot = CFrame.new()
	m:PivotTo(at)
	m.Parent = parent
	return m
end

-- Budzi albo usypia oczy (posąg w gnieździe świeci, gdy ktoś jest goniony)
function Leszy.setAwake(m: Model, awake: boolean)
	for _, child in m:GetChildren() do
		if child.Name == "Eye" and child:IsA("BasePart") then
			child.Color = if awake then Leszy.EYE_COLOR else Leszy.EYE_SLEEP
		end
	end
	local head = m:FindFirstChild("Head")
	local light = head and head:FindFirstChild("EyeLight")
	if light and light:IsA("PointLight") then
		light.Brightness = if awake then 2 else 0
	end
end

return Leszy
