--!strict
-- Grzyby istnieją tylko na kliencie danego gracza (każdy ma własny las).
-- Serwer mówi, gdzie co rośnie, a ten moduł rysuje szare grzybki z klocków.

local Workspace = game:GetService("Workspace")

export type MushroomInfo = {
	id: string,
	position: Vector3,
	species: string,
	golden: boolean,
}

type Entry = {
	info: MushroomInfo,
	model: Model,
	parts: { BasePart },
	hidden: boolean,
}

local CAP_COLORS: { [string]: Color3 } = {
	honey = Color3.fromRGB(196, 150, 80),
	chanterelle = Color3.fromRGB(240, 170, 40),
	slippery_jack = Color3.fromRGB(150, 95, 45),
	bay_bolete = Color3.fromRGB(110, 70, 40),
	parasol = Color3.fromRGB(215, 195, 160),
	saffron_milk_cap = Color3.fromRGB(230, 110, 40),
	aspen_bolete = Color3.fromRGB(200, 70, 30),
	porcini = Color3.fromRGB(140, 90, 50),
	glowing_agaric = Color3.fromRGB(230, 40, 40),
}

local GLOWING = { glowing_agaric = true }
local GOLD = Color3.fromRGB(255, 205, 50)
local STEM = Color3.fromRGB(235, 225, 205)

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

local function makePart(name: string, shape: Enum.PartType, size: Vector3, cframe: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
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

local function buildModel(info: MushroomInfo): (Model, { BasePart })
	local model = Instance.new("Model")
	model.Name = info.id
	local base = info.position

	local stem = makePart(
		"Stem",
		Enum.PartType.Cylinder,
		Vector3.new(1.4, 0.7, 0.7),
		CFrame.new(base + Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		STEM
	)
	local capColor = if info.golden then GOLD else (CAP_COLORS[info.species] or Color3.fromRGB(160, 120, 80))
	local cap = makePart(
		"Cap",
		Enum.PartType.Ball,
		Vector3.new(1.8, 1.8, 1.8),
		CFrame.new(base + Vector3.new(0, 1.5, 0)),
		capColor
	)

	if info.golden or GLOWING[info.species] then
		cap.Material = Enum.Material.Neon
		local light = Instance.new("PointLight")
		light.Color = capColor
		light.Range = 8
		light.Brightness = 1.5
		light.Parent = cap
	end

	stem.Parent = model
	cap.Parent = model
	model.PrimaryPart = cap
	model.Parent = folder
	return model, { stem, cap }
end

function MushroomView.add(list: { MushroomInfo })
	for _, info in list do
		local old = entries[info.id]
		if old then
			old.model:Destroy()
		end
		local model, parts = buildModel(info)
		entries[info.id] = { info = info, model = model, parts = parts, hidden = false }
	end
end

function MushroomView.remove(id: string)
	local entry = entries[id]
	if entry then
		if highlight.Adornee == entry.model then
			highlight.Enabled = false
			highlight.Adornee = nil
		end
		entry.model:Destroy()
		entries[id] = nil
	end
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
function MushroomView.updateVisibility(position: Vector3, lanternRange: number, darkness: number)
	local visibleRange = if darkness >= 0.7 then lanternRange + 2 else math.huge
	for _, entry in entries do
		local glows = entry.info.golden or GLOWING[entry.info.species] == true
		local hidden = not glows and flatDistance(position, entry.info.position) > visibleRange
		if hidden ~= entry.hidden then
			entry.hidden = hidden
			for _, p in entry.parts do
				p.Transparency = if hidden then 1 else 0
			end
		end
	end
end

return MushroomView
