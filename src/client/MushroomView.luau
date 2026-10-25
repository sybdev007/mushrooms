--!strict
-- Grzyby istnieją tylko na kliencie danego gracza (każdy ma własny las).
-- Serwer mówi, gdzie co rośnie, a ten moduł rysuje grzyby: każdy gatunek ma swój kształt,
-- wyrastają z ziemi, złote i świecące lśnią i lekko się unoszą.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Economy = require(ReplicatedStorage.Shared.Economy)

export type MushroomInfo = {
	id: string,
	position: Vector3,
	species: string,
	variant: string?, -- silver / gold / rainbow
	tags: { string }?, -- mossy / glowing
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
	rainbowParts: { BasePart }?, -- kapelusze tęczowego grzyba (kolor przechodzi przez tęczę)
	rainbowLight: PointLight?,
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
	-- Korona Leszego: wysoka, seledynowa, świeci z daleka jak przynęta
	leszy_crown = { stemH = 2.2, stemD = 0.6, capW = 2.6, capH = 1.1, cap = rgb(120, 255, 190), stem = rgb(200, 255, 230), spots = true, glow = true, cluster = 3 },
	-- Jaskinia: Kryształowe Korytarze
	cave_oyster = { stemH = 0.5, stemD = 0.45, capW = 2.0, capH = 0.35, cap = rgb(196, 200, 214), stem = rgb(220, 222, 230), cluster = 3 },
	crystal_cap = { stemH = 1.3, stemD = 0.45, capW = 1.7, capH = 0.9, cap = rgb(120, 210, 255), stem = rgb(200, 236, 255), glow = true },
	amethyst = { stemH = 1.6, stemD = 0.5, capW = 2.0, capH = 1.1, cap = rgb(170, 100, 255), stem = rgb(220, 200, 255), spots = true, glow = true },
	-- Podziemne Jezioro
	lake_cap = { stemH = 2.0, stemD = 0.35, capW = 2.4, capH = 0.5, cap = rgb(60, 170, 200), stem = rgb(170, 220, 230) },
	pearl = { stemH = 0.9, stemD = 0.7, capW = 1.6, capH = 1.4, cap = rgb(240, 236, 255), stem = rgb(230, 230, 240), glow = true },
	lantern_shroom = { stemH = 2.4, stemD = 0.5, capW = 2.2, capH = 1.3, cap = rgb(255, 200, 90), stem = rgb(255, 236, 190), glow = true },
	-- Otchłań
	ember = { stemH = 1.1, stemD = 0.6, capW = 1.9, capH = 0.8, cap = rgb(255, 110, 40), stem = rgb(90, 50, 40), spots = true, glow = true },
	obsidian = { stemH = 1.6, stemD = 0.9, capW = 2.4, capH = 1.0, cap = rgb(50, 40, 60), stem = rgb(70, 60, 80) },
	-- Sztolnia Skarbnika
	coal_cap = { stemH = 1.0, stemD = 0.8, capW = 2.0, capH = 0.9, cap = rgb(60, 58, 62), stem = rgb(90, 86, 90), spots = true },
	silver_vein = { stemH = 1.8, stemD = 0.5, capW = 2.1, capH = 0.8, cap = rgb(200, 214, 230), stem = rgb(220, 226, 236), cluster = 3 },
	gold_nugget = { stemH = 1.2, stemD = 0.9, capW = 2.2, capH = 1.2, cap = rgb(255, 196, 40), stem = rgb(240, 220, 160), glow = true },
	-- Złota Trufla Skarbnika: niska, okrągła, świeci złotem
	skarbnik_truffle = { stemH = 0.4, stemD = 1.2, capW = 2.4, capH = 2.0, cap = rgb(255, 220, 90), stem = rgb(200, 160, 60), spots = true, glow = true, cluster = 3 },
	heart_of_mountain = { stemH = 2.0, stemD = 0.8, capW = 2.8, capH = 1.6, cap = rgb(255, 40, 90), stem = rgb(255, 180, 200), spots = true, glow = true, cluster = 3 },
}
local DEFAULT_SHAPE: Shape = { stemH = 1, stemD = 0.5, capW = 1.6, capH = 0.6, cap = rgb(160, 120, 80) }

local MOSS = rgb(110, 176, 72)

local function variantColor(variant: string?): Color3?
	local def = Economy.getVariant(variant)
	return if def then rgb(def.color[1], def.color[2], def.color[3]) else nil
end

local function hasTag(info: MushroomInfo, id: string): boolean
	return info.tags ~= nil and table.find(info.tags, id) ~= nil
end
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

local function buildModel(info: MushroomInfo): (Model, { BasePart }, boolean, { BasePart })
	local model = Instance.new("Model")
	model.Name = info.id
	local shape = SHAPES[info.species] or DEFAULT_SHAPE
	local rank = Economy.variantRank(info.variant)
	-- Blask, Kryształ i Żar (cechy z jaskini) świecą jak Blask w lesie
	local glowing = hasTag(info, "glowing") or hasTag(info, "crystal") or hasTag(info, "abyssal")
	local capColor = variantColor(info.variant) or shape.cap
	local neon = rank >= 2 or shape.glow == true or glowing
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

	-- Kapelusze (bez trzonów i kropek) dostają kolor i materiał wariantu
	local caps: { BasePart } = {}
	for _, p in parts do
		if p.Name == "Cap" then
			table.insert(caps, p)
			if rank == 1 then
				-- Srebro: metaliczny połysk zamiast świecenia
				p.Material = Enum.Material.Metal
				p.Reflectance = 0.3
			elseif glowing and rank == 0 and not shape.glow then
				-- Blask bez wariantu: kolor gatunku rozjaśniony w stronę seledynu
				p.Color = shape.cap:Lerp(rgb(110, 255, 214), 0.45)
			end
		end
	end

	-- Mech: zielone łaty na kapeluszu
	if hasTag(info, "mossy") then
		for k = 1, 3 do
			local angle = k * 2.1
			local patch = makePart("Moss", Vector3.new(0.5, 0.18, 0.5), mainCap.CFrame * CFrame.new(math.cos(angle) * 0.45, mainCap.Size.Y * 0.38, math.sin(angle) * 0.45), MOSS)
			patch.Parent = model
			table.insert(parts, patch)
		end
	end

	local light: PointLight? = nil
	if neon then
		local newLight = Instance.new("PointLight")
		newLight.Color = if glowing and rank < 2 then rgb(110, 255, 214) else capColor
		newLight.Range = if rank >= 2 then 10 else 8
		newLight.Brightness = 1.6
		newLight.Parent = mainCap
		light = newLight
	end
	if rank >= 1 then
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Texture = SPARKLE
		sparkles.Color = if rank == 3
			then ColorSequence.new({
				ColorSequenceKeypoint.new(0, rgb(255, 90, 90)),
				ColorSequenceKeypoint.new(0.33, rgb(255, 230, 80)),
				ColorSequenceKeypoint.new(0.66, rgb(90, 220, 255)),
				ColorSequenceKeypoint.new(1, rgb(200, 110, 255)),
			})
			else ColorSequence.new(capColor, Color3.new(1, 1, 1))
		sparkles.LightEmission = 1
		sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
		sparkles.Lifetime = NumberRange.new(0.8, 1.4)
		sparkles.Speed = NumberRange.new(0.5, 1.5)
		sparkles.SpreadAngle = Vector2.new(180, 180)
		-- Im rzadszy wariant, tym więcej iskier
		sparkles.Rate = ({ 3, 6, 14 })[rank] or 6
		sparkles.Parent = mainCap
	end

	model.PrimaryPart = mainCap
	model.Parent = folder
	-- Tęcza: kapelusze i światło zmieniają kolor w updateVisibility
	local rainbow = if rank == 3 then caps else {}
	if light and rank == 3 then
		light:SetAttribute("Rainbow", true)
	end
	return model, parts, neon or rank >= 1, rainbow
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
		local model, parts, animated, rainbow = buildModel(info)
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
			rainbowParts = if #rainbow > 0 then rainbow else nil,
			rainbowLight = model.PrimaryPart and model.PrimaryPart:FindFirstChildOfClass("PointLight") or nil,
		}
	end
end

-- Kolor kapelusza (do efektów przy zbieraniu)
function MushroomView.capColor(species: string, variant: string?): Color3
	return variantColor(variant) or (SHAPES[species] or DEFAULT_SHAPE).cap
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
		-- Tęczowy kapelusz przechodzi przez wszystkie kolory (tylko gdy gracz jest blisko)
		local rainbow = entry.rainbowParts
		if rainbow and not entry.hidden and flatDistance(position, entry.info.position) < 80 then
			local color = Color3.fromHSV((t * 0.35 + entry.phase) % 1, 0.65, 1)
			for _, p in rainbow do
				p.Color = color
			end
			local light = entry.rainbowLight
			if light then
				light.Color = color
			end
		end
		if glows and t >= entry.bobFrom and flatDistance(position, entry.info.position) < 120 then
			local bob = 0.18 * math.sin(t * 2 + entry.phase)
			entry.model:PivotTo(entry.basePivot * CFrame.new(0, bob, 0) * CFrame.Angles(0, math.sin(t * 0.7 + entry.phase) * 0.15, 0))
		end
	end
end

return MushroomView
