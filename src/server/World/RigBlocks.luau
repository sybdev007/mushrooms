--!strict
-- Wspólne klocki dla strażników ze szkieletem (Skarbnik, Utopiec), tak jak Leszy:
-- każda część ma atrybut Limb (kość) i Rest (położenie w pozie spoczynkowej), model ma stawy J_<kość>,
-- atrybut Rig i tag "LeszyRig", więc klient (LeszyAnimator) animuje chód, bieg i drzemkę posągu,
-- a serwer (ChaseService) przesuwa tylko część Root. Kości jak w Shared/LeszyRig:
-- Hips, Torso, Head, UpperArmL/R, ForearmL/R, ThighL/R, ShinL/R. Przód modelu to -Z, prawa ręka to +X.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local RigBlocks = {}

local TEXTURE = (Config :: any).VoxelNoise and (Config :: any).VoxelNoise.texture or ""
local FACES = { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right, Enum.NormalId.Top }

export type Builder = { model: Model, root: BasePart }
export type Options = {
	shape: Enum.PartType?,
	neon: boolean?,
	texture: number?, -- przezroczystość pikselowej kratki (jak na grzybach i Leszym)
	material: Enum.Material?,
	transparency: number?,
}

function RigBlocks.new(name: string, awake: boolean): Builder
	local m = Instance.new("Model")
	m.Name = name
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
	return { model = m, root = root }
end

-- Klocek należący do kości `limb` (cf w układzie modelu, pivot w (0, 0, 0) na ziemi)
function RigBlocks.block(b: Builder, name: string, limb: string, size: Vector3, cf: CFrame, color: Color3, options: Options?): Part
	local o: Options = options or {}
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = if o.neon then Enum.Material.Neon else (o.material or Enum.Material.SmoothPlastic)
	p.Transparency = o.transparency or 0
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
	if o.texture and TEXTURE ~= "" and not o.neon then
		for _, face in FACES do
			local tex = Instance.new("Texture")
			tex.Texture = TEXTURE
			tex.Face = face
			tex.StudsPerTileU = 2
			tex.StudsPerTileV = 2
			tex.Transparency = o.texture
			tex.Parent = p
		end
	end
	p.Parent = b.model
	return p
end

-- Walec (kij, trzonek, pnącze) od punktu `from` do `to`
function RigBlocks.rod(b: Builder, name: string, limb: string, from: Vector3, to: Vector3, thickness: number, color: Color3, options: Options?): Part
	local length = (to - from).Magnitude
	local mid = (from + to) / 2
	-- Oś walca to X: obracamy tak, żeby X patrzył od `from` do `to`
	local cf = CFrame.lookAt(mid, to) * CFrame.Angles(0, math.rad(90), 0)
	local o: Options = table.clone(options or {})
	o.shape = Enum.PartType.Cylinder
	return RigBlocks.block(b, name, limb, Vector3.new(length, thickness, thickness), cf, color, o)
end

function RigBlocks.joint(b: Builder, limb: string, at: Vector3)
	b.model:SetAttribute("J_" .. limb, at)
end

function RigBlocks.light(part: BasePart, name: string, color: Color3, range: number, brightness: number): PointLight
	local light = Instance.new("PointLight")
	light.Name = name
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Parent = part
	return light
end

-- Kończy model: pivot na ziemi pod stopami, ustawienie w `at`, tag do animacji.
-- runSpeed: prędkość pościgu (studs/s), przy której animacja to pełny bieg.
function RigBlocks.finish(b: Builder, parent: Instance, at: CFrame, runSpeed: number): Model
	local m = b.model
	m.PrimaryPart = b.root
	b.root.PivotOffset = b.root.CFrame:Inverse()
	m:SetAttribute("RunSpeed", runSpeed)
	m:PivotTo(at)
	CollectionService:AddTag(m, "LeszyRig")
	m.Parent = parent
	return m
end

return RigBlocks
