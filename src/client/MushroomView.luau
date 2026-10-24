--!strict
-- Grzyby istnieją tylko na kliencie danego gracza (każdy ma własny las).
-- Serwer mówi, gdzie co rośnie, a ten moduł rysuje grzyby: każdy gatunek ma swój kształt,
-- wyrastają z ziemi, złote i świecące lśnią i lekko się unoszą.

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

export type MushroomInfo = {
	id: string,
	position: Vector3,
	species: string,
	golden: boolean,
}

type Shape = {
	stemH: number,
	stemD: number,
	capW: number,
	capH: number,
	cap: Color3,
	stem: Color3?,
	spots: boolean?,
	glow: boolean?,
	cluster: number?,
}

type Entry = {
	info: MushroomInfo,
	model: Model,
	parts: { BasePart },
	hidden: boolean,
	animated: boolean,
	basePivot: CFrame,
	phase: number,
	bobFrom: number,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local SHAPES: { [string]: Shape } = {
	honey = { stemH = 0.9, stemD = 0.3, capW = 1.1, capH = 0.45, cap = rgb(196, 150, 80), cluster = 3 },
	chanterelle = { stemH = 0.7, stemD = 0.45, capW = 1.4, capH = 0.4, cap = rgb(240, 170, 40), stem = rgb(240, 186, 80) },
	slippery_jack = { stemH = 1.0, stemD = 0.55, capW = 1.8, capH = 0.7, cap = rgb(150, 95, 45), stem = rgb(232, 212, 150) },
	bay_bolete = { stemH = 1.2, stemD = 0.7, capW = 2.0, capH = 0.85, cap = rgb(110, 70, 40), stem = rgb(220, 200, 160) },
	parasol = { stemH = 2.6, stemD = 0.3, capW = 2.7, capH = 0.45, cap = rgb(215, 195, 160), stem = rgb(200, 180, 150) },
	saffron_milk_cap = { stemH = 0.8, stemD = 0.55, capW = 1.8, capH = 0.45, cap = rgb(230, 110, 40), stem = rgb(236, 140, 70) },
	aspen_bolete = { stemH = 1.8, stemD = 0.7, capW = 2.1, capH = 1.0, cap = rgb(205, 72, 30), stem = rgb(228, 222, 210) },
	porcini = { stemH = 1.4, stemD = 1.1, capW = 2.3, capH = 1.05, cap = rgb(140, 90, 50), stem = rgb(232, 218, 190) },
	glowing_agaric = { stemH = 1.6, stemD = 0.5, capW = 2.0, capH = 0.8, cap = rgb(230, 40, 40), spots = true, glow = true },
}
local DEFAULT_SHAPE: Shape = { stemH = 1, stemD = 0.5, capW = 1.6, capH = 0.6, cap = rgb(160, 120, 80) }

local GOLD = rgb(255, 205, 50)
local STEM = rgb(235, 225, 205)
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local VERTICAL = CFrame.Angles(0, 0, math.rad(90))

local MushroomView = {}

local folder = Instance.new("Folder")
folder.Name = "MyMushrooms"
folder.Parent = Workspace

local entries: { [string]: Entry } = {}

local highlight = Instance.new("Highlight")
highlight.FillTransparency = 0.6
highlight.FillColor = Color3.fromRGB(255, 230, 150)
highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
highlight.DepthMode = Enum.HighlightDepthMode.Occluded
-- Highlight bez Adornee podświetla swojego rodzica, czyli WSZYSTKIE grzyby, więc domyślnie wyłączony
highlight.Enabled = false
highlight.Parent = folder

local function makePart(name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

-- Jeden grzybek: trzon + kapelusz (spłaszczona kula przez SpecialMesh)
local function buildOne(model: Model, base: Vector3, shape: Shape, scale: number, capColor: Color3, neon: boolean, parts: { BasePart }): BasePart
	local stemH, stemD = shape.stemH * scale, shape.stemD * scale
	local capW, capH = shape.capW * scale, shape.capH * scale
	local stem = makePart("Stem", Vector3.new(stemH, stemD, stemD), CFrame.new(base + Vector3.new(0, stemH / 2, 0)) * VERTICAL, shape.stem or STEM)
	stem.Parent = model
	table.insert(parts, stem)

	local capCenter = base + Vector3.new(0, stemH, 0)
	local cap = makePart("Cap", Vector3.new(capW, capH * 2, capW), CFrame.new(capCenter), capColor)
	if neon then
		cap.Material = Enum.Material.Neon
	end
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = cap
	cap.Parent = model
	table.insert(parts, cap)

	if shape.spots then
		for k = 1, 6 do
			local theta = k * math.pi * 2 / 6 + (k % 2) * 0.4
			local phi = math.rad(if k % 2 == 0 then 35 else 58)
			local offset = Vector3.new(
				capW / 2 * math.sin(phi) * math.cos(theta),
				capH * math.cos(phi),
				capW / 2 * math.sin(phi) * math.sin(theta)
			)
			local spot = makePart("Spot", Vector3.new(0.26, 0.26, 0.26) * scale, CFrame.new(capCenter + offset), Color3.new(1, 1, 1))
			spot.Shape = Enum.PartType.Ball
			spot.Parent = model
			table.insert(parts, spot)
		end
	end
	return cap
end

local function buildModel(info: MushroomInfo): (Model, { BasePart }, boolean)
	local model = Instance.new("Model")
	model.Name = info.id
	local shape = SHAPES[info.species] or DEFAULT_SHAPE
	local capColor = if info.golden then GOLD else shape.cap
	local neon = info.golden or shape.glow == true
	local parts: { BasePart } = {}

	local mainCap: BasePart
	if shape.cluster then
		-- Opieńki rosną kępkami
		mainCap = buildOne(model, info.position, shape, 1.15, capColor, neon, parts)
		for k = 1, shape.cluster - 1 do
			local angle = k * 2.3
			local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * 0.7
			buildOne(model, info.position + offset, shape, 0.8, capColor, neon, parts)
		end
	else
		mainCap = buildOne(model, info.position, shape, 1, capColor, neon, parts)
	end

	if neon then
		local light = Instance.new("PointLight")
		light.Color = capColor
		light.Range = if info.golden then 10 else 8
		light.Brightness = 1.6
		light.Parent = mainCap
	end
	if info.golden then
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Texture = SPARKLE
		sparkles.Color = ColorSequence.new(GOLD, Color3.new(1, 1, 1))
		sparkles.LightEmission = 1
		sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
		sparkles.Lifetime = NumberRange.new(0.8, 1.4)
		sparkles.Speed = NumberRange.new(0.5, 1.5)
		sparkles.SpreadAngle = Vector2.new(180, 180)
		sparkles.Rate = 6
		sparkles.Parent = mainCap
	end

	model.PrimaryPart = mainCap
	model.Parent = folder
	return model, parts, neon
end

-- Grzyb wyrasta z ziemi: części startują schowane pod ziemią i wyskakują na swoje miejsce
local function growIn(parts: { BasePart })
	local info = TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	for _, p in parts do
		local final = p.CFrame
		p.CFrame = final - Vector3.new(0, 2.2, 0)
		TweenService:Create(p, info, { CFrame = final }):Play()
	end
end

function MushroomView.add(list: { MushroomInfo })
	for _, info in list do
		local old = entries[info.id]
		if old then
			old.model:Destroy()
		end
		local model, parts, animated = buildModel(info)
		-- Pozycję spoczynkową bierzemy przed animacją wyrastania (potem części są pod ziemią)
		local basePivot = model:GetPivot()
		growIn(parts)
		entries[info.id] = {
			info = info,
			model = model,
			parts = parts,
			hidden = false,
			animated = animated,
			basePivot = basePivot,
			phase = math.random() * math.pi * 2,
			bobFrom = os.clock() + 0.6, -- unoszenie dopiero po skończonym wyrastaniu
		}
	end
end

-- Kolor kapelusza (do efektów przy zbieraniu)
function MushroomView.capColor(species: string, golden: boolean): Color3
	if golden then
		return GOLD
	end
	return (SHAPES[species] or DEFAULT_SHAPE).cap
end

function MushroomView.get(id: string): MushroomInfo?
	local entry = entries[id]
	return entry and entry.info
end

function MushroomView.remove(id: string)
	local entry = entries[id]
	if not entry then
		return
	end
	if highlight.Adornee == entry.model then
		highlight.Enabled = false
		highlight.Adornee = nil
	end
	entries[id] = nil
	-- Krótki „podskok” do koszyka zamiast natychmiastowego zniknięcia
	local info = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, p in entry.parts do
		TweenService:Create(p, info, { CFrame = p.CFrame + Vector3.new(0, 1.6, 0), Transparency = 1 }):Play()
	end
	task.delay(0.25, function()
		entry.model:Destroy()
	end)
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Najbliższy widoczny grzyb w zasięgu. Podświetla go i zwraca jego id.
function MushroomView.updateTarget(position: Vector3, radius: number): string?
	local bestId: string? = nil
	local bestDistance = radius
	for id, entry in entries do
		if not entry.hidden then
			local distance = flatDistance(position, entry.info.position)
			if distance <= bestDistance then
				bestDistance = distance
				bestId = id
			end
		end
	end
	local target = bestId and entries[bestId]
	if target then
		highlight.Adornee = target.model
		highlight.Enabled = true
	else
		highlight.Enabled = false
		highlight.Adornee = nil
	end
	return bestId
end

-- W ciemnych strefach widać tylko grzyby w zasięgu latarni (świecące widać zawsze).
-- Przy okazji złote i świecące delikatnie się unoszą.
function MushroomView.updateVisibility(position: Vector3, lanternRange: number, darkness: number)
	local visibleRange = if darkness >= 0.7 then lanternRange + 2 else math.huge
	local t = os.clock()
	for _, entry in entries do
		local glows = entry.animated
		local hidden = not glows and flatDistance(position, entry.info.position) > visibleRange
		if hidden ~= entry.hidden then
			entry.hidden = hidden
			for _, p in entry.parts do
				p.Transparency = if hidden then 1 else 0
			end
		end
		if glows and t >= entry.bobFrom and flatDistance(position, entry.info.position) < 120 then
			local bob = 0.18 * math.sin(t * 2 + entry.phase)
			entry.model:PivotTo(entry.basePivot * CFrame.new(0, bob, 0) * CFrame.Angles(0, math.sin(t * 0.7 + entry.phase) * 0.15, 0))
		end
	end
end

return MushroomView
