--!strict
-- Utopiec: wodnik z polskich i śląskich legend. Przygarbiony, żabi staruszek o zielonej śliskiej
-- skórze i błoniastych łapach, w czerwonej spiczastej czapce i postrzępionym zielonym fraku
-- z wodorostami. Oczy świecą na żółto. Mieszka w stawie na końcu bagien i wciąga do wody.
-- Model to siatka z teksturą wygenerowana w Studio (asset na koncie Toma); gdy nie da się jej
-- wczytać, składamy prostszego Utopca z klocków. Do siatki dokładamy niewidzialne punkty
-- ze światłem oczu i kapiącą wodę, które włączają się, gdy się budzi.
-- Pivot modelu leży na ziemi pod stopami, przód to -Z (jak w CFrame.lookAt).

local InsertService = game:GetService("InsertService")

local Utopiec = {}

local MESH = {
	mesh = "rbxassetid://121760464290884",
	texture = "rbxassetid://104625246994716",
	size = Vector3.new(6.5, 8.5, 4.8), -- proporcje z generatora: 5 x 6,57 x 3,69
}

local EYE_COLOR = Color3.fromRGB(255, 230, 80)
local SLIME = Color3.fromRGB(120, 220, 140)
local SKIN = Color3.fromRGB(96, 150, 70)
local BELLY = Color3.fromRGB(210, 220, 150)
local COAT = Color3.fromRGB(50, 90, 50)
local CAP = Color3.fromRGB(220, 60, 40)

local function makePart(m: Model, name: string, size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
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

local function lightPoint(m: Model, name: string, offset: Vector3, color: Color3, range: number, brightness: number): BasePart
	local p = makePart(m, name, Vector3.new(0.2, 0.2, 0.2), CFrame.new(offset), color)
	p.Transparency = 1
	local light = Instance.new("PointLight")
	light.Name = "Light"
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Parent = p
	return p
end

-- Prostszy Utopiec z klocków, gdy siatki nie da się wczytać
local function buildParts(m: Model)
	makePart(m, "Body", Vector3.new(3.6, 3.4, 2.6), CFrame.new(0, 3, 0), COAT)
	makePart(m, "Belly", Vector3.new(2.4, 2.4, 0.4), CFrame.new(0, 2.9, -1.3), BELLY)
	makePart(m, "Head", Vector3.new(3.4, 2.2, 2.8), CFrame.new(0, 5.6, -0.3), SKIN, Enum.PartType.Ball)
	for _, side in { -1, 1 } do
		makePart(m, "EyeBump", Vector3.new(1, 1, 1), CFrame.new(side * 0.9, 6.5, -1.1), SKIN, Enum.PartType.Ball)
		makePart(m, "Leg", Vector3.new(0.9, 1.6, 0.9), CFrame.new(side * 1, 0.8, 0), SKIN)
		makePart(m, "Foot", Vector3.new(1.4, 0.3, 1.8), CFrame.new(side * 1, 0.15, -0.4), SKIN)
		makePart(m, "Arm", Vector3.new(0.7, 2.8, 0.7), CFrame.new(side * 2.2, 3, -0.2) * CFrame.Angles(0, 0, math.rad(side * 12)), SKIN)
	end
	makePart(m, "Cap", Vector3.new(1.6, 2.4, 1.6), CFrame.new(0, 7.6, -0.2), CAP)
end

local template: MeshPart? = nil
local templateFailed = false

local function meshTemplate(): MeshPart?
	if template or templateFailed then
		return template
	end
	local ok, result = pcall(function()
		return InsertService:CreateMeshPartAsync(MESH.mesh, Enum.CollisionFidelity.Box, Enum.RenderFidelity.Automatic)
	end)
	if ok and result then
		local meshPart = result :: MeshPart
		meshPart.TextureID = MESH.texture
		meshPart.Size = MESH.size
		meshPart.Anchored = true
		meshPart.CanCollide = false
		meshPart.CanTouch = false
		meshPart.CanQuery = false
		template = meshPart
	else
		templateFailed = true
		warn("[Utopiec] Nie udało się wczytać siatki, składam z klocków:", result)
	end
	return template
end

-- Buduje Utopca stojącego w `at` (pivot na ziemi). awake = świecące oczy i kapiąca woda.
function Utopiec.build(parent: Instance, at: CFrame, awake: boolean): Model
	local m = Instance.new("Model")
	m.Name = "Utopiec"
	local size = MESH.size
	local source = meshTemplate()
	if source then
		local body = source:Clone()
		body.Name = "Body"
		body.CFrame = CFrame.new(0, size.Y / 2, 0)
		body.Parent = m
	else
		buildParts(m)
	end

	lightPoint(m, "EyeGlow", Vector3.new(0, size.Y * 0.68, -size.Z * 0.45), EYE_COLOR, 16, if awake then 2.2 else 0)

	-- Woda i szlam kapiące z wodnika, gdy się budzi
	local drip = lightPoint(m, "Drip", Vector3.new(0, size.Y * 0.5, 0), SLIME, 12, if awake then 0.8 else 0)
	local water = Instance.new("ParticleEmitter")
	water.Name = "Water"
	water.Color = ColorSequence.new(SLIME)
	water.LightEmission = 0.5
	water.Size = NumberSequence.new(0.25, 0.05)
	water.Lifetime = NumberRange.new(0.6, 1)
	water.Rate = 18
	water.Speed = NumberRange.new(0.5, 1.5)
	water.SpreadAngle = Vector2.new(60, 60)
	water.Acceleration = Vector3.new(0, -20, 0)
	water.Enabled = awake
	water.Parent = drip

	local root = lightPoint(m, "Root", Vector3.new(0, 0.5, 0), SLIME, 0, 0)
	m.PrimaryPart = root
	m.WorldPivot = CFrame.new()
	m:PivotTo(at)
	m.Parent = parent
	return m
end

-- Budzi albo usypia (posąg na wyspie świeci oczami, gdy ktoś jest goniony)
function Utopiec.setAwake(m: Model, awake: boolean)
	local eyeGlow = m:FindFirstChild("EyeGlow")
	local eye = eyeGlow and eyeGlow:FindFirstChild("Light")
	if eye and eye:IsA("PointLight") then
		eye.Brightness = if awake then 2.2 else 0
	end
	local drip = m:FindFirstChild("Drip")
	if drip then
		local light = drip:FindFirstChild("Light")
		if light and light:IsA("PointLight") then
			light.Brightness = if awake then 0.8 else 0
		end
		local water = drip:FindFirstChild("Water")
		if water and water:IsA("ParticleEmitter") then
			water.Enabled = awake
		end
	end
end

return Utopiec
