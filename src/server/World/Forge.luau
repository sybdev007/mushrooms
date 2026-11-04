--!strict
-- Moździerz Zielarki (Kuźnia Grzybów) z boku Placu Portali: duży kamienny moździerz z miedzianymi
-- obręczami i tłuczkiem, trzy miseczki na grzyby, pęczki ziół, zielono-fioletowa poświata wywaru.
-- Przycisk (ProximityPrompt z tagiem "LocalizedPrompt") otwiera okno kuźni (ForgeService, ForgePanel).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Palette = require(script.Parent.Palette)

local Forge = {}

local STONE = Color3.fromRGB(128, 122, 116)
local STONE_DARK = Color3.fromRGB(96, 90, 86)
local COPPER = Color3.fromRGB(184, 110, 64)
local WOOD = Color3.fromRGB(120, 82, 52)
local MOSS = Color3.fromRGB(96, 150, 70)
local BREW = Color3.fromRGB(150, 110, 255)
local RUNE = Color3.fromRGB(150, 255, 90)
local VERTICAL = CFrame.Angles(0, 0, math.rad(90))

local function part(parent: Instance, props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

local function decor(p: BasePart): BasePart
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	return p
end

-- Buduje moździerz w `at` (pivot na ziemi, przód z miseczkami = -Z). Zwraca model i przycisk.
function Forge.build(parent: Instance, at: CFrame): (Model, ProximityPrompt)
	local m = Instance.new("Model")
	m.Name = "HerbalistMortar"
	local base = part(m, { Name = "Base", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 7.2, 7.2), CFrame = at * CFrame.new(0, 0.4, 0) * VERTICAL, Color = STONE_DARK, Material = Enum.Material.Cobblestone })
	m.PrimaryPart = base
	-- Misa moździerza: szeroka u góry, węższa u dołu (trzy kamienne pierścienie)
	part(m, { Name = "Bowl", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, 4.2, 4.2), CFrame = at * CFrame.new(0, 1.5, 0) * VERTICAL, Color = STONE, Material = Enum.Material.Slate })
	part(m, { Name = "Bowl", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, 5, 5), CFrame = at * CFrame.new(0, 2.9, 0) * VERTICAL, Color = STONE, Material = Enum.Material.Slate })
	part(m, { Name = "Rim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 5.6, 5.6), CFrame = at * CFrame.new(0, 3.85, 0) * VERTICAL, Color = STONE_DARK, Material = Enum.Material.Slate })
	for _, y in { 1.9, 3.3 } do
		decor(part(m, { Name = "Band", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, if y > 2 then 5.12 else 4.32, if y > 2 then 5.12 else 4.32), CFrame = at * CFrame.new(0, y, 0) * VERTICAL, Color = COPPER, Material = Enum.Material.Metal }))
	end
	-- Wywar w środku: fioletowa poświata, iskry w kolorach run
	local brew = decor(part(m, { Name = "Brew", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 4.4, 4.4), CFrame = at * CFrame.new(0, 3.95, 0) * VERTICAL, Color = BREW, Material = Enum.Material.Neon, Transparency = 0.3 }))
	local glow = Instance.new("PointLight")
	glow.Color = BREW
	glow.Range = 14
	glow.Brightness = 0.9
	glow.Shadows = false
	glow.Parent = brew
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Spores"
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(RUNE, BREW)
	sparks.LightEmission = 0.8
	sparks.Size = NumberSequence.new(0.35, 0)
	sparks.Lifetime = NumberRange.new(1, 1.8)
	sparks.Rate = 6
	sparks.Speed = NumberRange.new(1, 2.4)
	sparks.SpreadAngle = Vector2.new(30, 30)
	sparks.EmissionDirection = Enum.NormalId.Right -- oś walca (X) patrzy w górę
	sparks.Parent = brew
	-- Tłuczek oparty o brzeg
	local pestle = decor(part(m, { Name = "Pestle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(5.6, 0.7, 0.7), CFrame = at * CFrame.new(1.2, 5.2, 0.6) * CFrame.Angles(0, 0, math.rad(62)), Color = WOOD, Material = Enum.Material.Wood }))
	decor(part(m, { Name = "PestleHead", Shape = Enum.PartType.Ball, Size = Vector3.new(1.3, 1.3, 1.3), CFrame = pestle.CFrame * CFrame.new(-2.6, 0, 0), Color = STONE, Material = Enum.Material.Slate }))
	-- Trzy miseczki na grzyby od strony gracza i świecąca runa przed każdą
	for i, x in { -2.6, 0, 2.6 } do
		local bowl = at * CFrame.new(x, 0.95, -4.2)
		decor(part(m, { Name = "Dish" .. i, Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 1.8, 1.8), CFrame = bowl * VERTICAL, Color = COPPER, Material = Enum.Material.Metal }))
		decor(part(m, { Name = "DishPost", Size = Vector3.new(0.4, 0.8, 0.4), CFrame = at * CFrame.new(x, 0.4, -4.2), Color = WOOD }))
		decor(part(m, { Name = "Rune", Size = Vector3.new(0.9, 0.06, 0.9), CFrame = at * CFrame.new(x, 0.05, -5.6) * CFrame.Angles(0, math.rad(45), 0), Color = RUNE, Material = Enum.Material.Neon, Transparency = 0.4 }))
	end
	-- Pęczki ziół i mech na podstawie
	for i = 1, 6 do
		local angle = i / 6 * math.pi * 2 + 0.4
		if math.cos(angle) > -0.2 or math.abs(math.sin(angle)) > 0.5 then
			decor(part(m, { Name = "Moss", Size = Vector3.new(1.2, 0.3, 0.9), CFrame = at * CFrame.new(math.cos(angle) * 3.2, 0.85, math.sin(angle) * 3.2) * CFrame.Angles(0, -angle, 0), Color = MOSS, Material = Enum.Material.Grass }))
		end
	end
	for _, side in { -1, 1 } do
		local post = at * CFrame.new(side * 4.6, 0, 1.4)
		part(m, { Name = "Post", Size = Vector3.new(0.5, 6.4, 0.5), CFrame = post * CFrame.new(0, 3.2, 0), Color = Palette.log })
		for k = 0, 2 do
			decor(part(m, { Name = "Herbs", Size = Vector3.new(0.5, 1.1, 0.5), CFrame = post * CFrame.new(0, 5.4 - k * 0.2, -0.45 - k * 0.1) * CFrame.Angles(math.rad(10), 0, 0), Color = if k == 1 then Color3.fromRGB(150, 120, 170) else Color3.fromRGB(96, 140, 70), Material = Enum.Material.Grass }))
		end
	end
	part(m, { Name = "Beam", Size = Vector3.new(9.8, 0.5, 0.6), CFrame = at * CFrame.new(0, 6.5, 1.4), Color = Palette.log })

	-- Tabliczka nad moździerzem (tekst w języku gracza: Signs)
	local sign = part(m, { Name = "Sign", Size = Vector3.new(6.4, 1.4, 0.3), CFrame = at * CFrame.new(0, 7.5, 1.4), Color = Palette.signWood, CanCollide = false })
	sign:SetAttribute("SignKey", "FORGE_TITLE")
	sign:SetAttribute("SignFace", Enum.NormalId.Front.Name)
	CollectionService:AddTag(sign, "LocalizedSign")

	-- Przycisk
	local anchor = decor(part(m, { Name = "PromptAnchor", Size = Vector3.new(1, 1, 1), CFrame = at * CFrame.new(0, 3, -3.4), Transparency = 1 }))
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Forge"
	prompt.ActionText = "Fuse"
	prompt.ObjectText = "Mortar"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Config.Forge.station.radius + 4
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt:SetAttribute("TextKey", "PROMPT_FORGE")
	prompt:SetAttribute("ObjectKey", "FORGE_TITLE")
	CollectionService:AddTag(prompt, "LocalizedPrompt")
	prompt.Parent = anchor

	m.Parent = parent
	return m, prompt
end

return Forge
