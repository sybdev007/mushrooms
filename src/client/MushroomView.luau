--!strict
-- Grzyby istnieją tylko na kliencie danego gracza (każdy ma własny las).
-- Serwer mówi, gdzie co rośnie, a ten moduł rysuje grzyby: voxelowe, z klocków (schodkowy kapelusz,
-- kwadratowe kropki, piksele cienia i buzia na trzonie). Każdy gatunek ma swój kształt, grzyby wyrastają
-- z ziemi, złote i świecące lśnią i się unoszą, a rzadsze mają aury (zarodniki, krążące kostki, słup światła).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Localize = require(script.Parent.Localize)

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
	mimicLight: PointLight?, -- błędny ognik: światło drży nierówno (jedyna wskazówka dla uważnych)
	aura: any?, -- krążące kostki, słup światła i zarodniki rzadszych grzybów (typ Aura niżej)
	fxParts: { BasePart },
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
	-- Bagna
	bog_bell = { stemH = 1.6, stemD = 0.4, capW = 1.7, capH = 1.1, cap = rgb(120, 140, 70), stem = rgb(200, 200, 160) },
	peat_cap = { stemH = 1.0, stemD = 0.9, capW = 2.3, capH = 0.8, cap = rgb(110, 70, 50), stem = rgb(170, 140, 110), cluster = 3 },
	frog_stool = { stemH = 1.4, stemD = 0.6, capW = 2.2, capH = 0.9, cap = rgb(90, 210, 90), stem = rgb(230, 240, 200), spots = true },
	wisp_cap = { stemH = 1.8, stemD = 0.35, capW = 1.8, capH = 1.0, cap = rgb(140, 255, 220), stem = rgb(220, 255, 240), glow = true },
	-- Błędny ognik wygląda jak Ognik (ten sam kształt i kolor); zdradza go tylko niespokojne światło
	false_wisp = { stemH = 1.8, stemD = 0.35, capW = 1.8, capH = 1.0, cap = rgb(140, 255, 220), stem = rgb(220, 255, 240), glow = true },
	moon_lily = { stemH = 2.2, stemD = 0.4, capW = 2.6, capH = 0.6, cap = rgb(230, 230, 255), stem = rgb(240, 240, 250), glow = true },
	drowned_cap = { stemH = 2.0, stemD = 0.7, capW = 2.6, capH = 1.0, cap = rgb(60, 110, 120), stem = rgb(150, 190, 190), spots = true },
	bog_pearl = { stemH = 0.8, stemD = 0.8, capW = 1.8, capH = 1.6, cap = rgb(250, 250, 240), stem = rgb(220, 220, 210), glow = true, cluster = 3 },
	will_o_wisp = { stemH = 2.4, stemD = 0.4, capW = 2.2, capH = 1.4, cap = rgb(180, 255, 120), stem = rgb(220, 255, 200), glow = true, spots = true },
	-- Kielich Utopca: wysoki czerwony kielich, świeci jak latarnia na wysepce
	utopiec_chalice = { stemH = 2.6, stemD = 0.7, capW = 2.8, capH = 1.4, cap = rgb(255, 90, 70), stem = rgb(255, 210, 190), spots = true, glow = true, cluster = 3 },
	heart_of_mountain = { stemH = 2.0, stemD = 0.8, capW = 2.8, capH = 1.6, cap = rgb(255, 40, 90), stem = rgb(255, 180, 200), spots = true, glow = true, cluster = 3 },
}
local DEFAULT_SHAPE: Shape = { stemH = 1, stemD = 0.5, capW = 1.6, capH = 0.6, cap = rgb(160, 120, 80) }

local MOSS = rgb(110, 176, 72)
-- Halloween: dyniowy grzyb (cecha „pumpkin”)
local PUMPKIN = rgb(240, 128, 30)
local PUMPKIN_GLOW = rgb(255, 214, 90)
local PUMPKIN_STEM = rgb(70, 104, 40)

local function variantColor(variant: string?): Color3?
	local def = Economy.getVariant(variant)
	return if def then rgb(def.color[1], def.color[2], def.color[3]) else nil
end

local function hasTag(info: MushroomInfo, id: string): boolean
	return info.tags ~= nil and table.find(info.tags, id) ~= nil
end
local STEM = rgb(235, 225, 205)
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

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

-- Nazwa i klasa grzyba, na który celuje gracz (np. "Borowik · Rzadki" na niebiesko)
local targetTag = Instance.new("BillboardGui")
targetTag.Name = "TargetTag"
targetTag.Size = UDim2.fromOffset(180, 26)
targetTag.StudsOffset = Vector3.new(0, 3.2, 0)
targetTag.AlwaysOnTop = true
targetTag.LightInfluence = 0
targetTag.Enabled = false
-- BillboardGui z Adornee rysuje się tylko w PlayerGui albo pod częścią; w folderze w Workspace był niewidoczny
targetTag.ResetOnSpawn = false
targetTag.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
local targetLabel = Instance.new("TextLabel")
targetLabel.Size = UDim2.fromScale(1, 1)
targetLabel.BackgroundTransparency = 1
targetLabel.Font = Enum.Font.FredokaOne
targetLabel.TextScaled = true
targetLabel.Parent = targetTag
local targetStroke = Instance.new("UIStroke")
targetStroke.Thickness = 2
targetStroke.Color = Color3.fromRGB(30, 20, 12)
targetStroke.Parent = targetLabel
local targetId: string? = nil

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

-- ===== Voxelowe grzyby =====
-- Kapelusz z warstw klocków (schodkowa kopuła jak w grach z pikselami), ciemniejszy brzeg,
-- jaśniejszy czubek, kwadratowe kropki i „piksele” cienia na bokach; trzon z podstawką i buzią.
-- Wymiary klocków są zaokrąglane do jednego „voxela”, żeby wszystko wyglądało jak z kostek.

-- Profile kapeluszy: szerokość kolejnych warstw (od dołu) jako ułamek szerokości kapelusza
local PROFILES: { [string]: { number } } = {
	dome = { 1.0, 0.94, 0.82, 0.64, 0.38 },
	flat = { 1.0, 0.96, 0.84, 0.56 },
	funnel = { 0.42, 0.66, 0.88, 1.0 },
	parasol = { 1.0, 0.78, 0.3 },
	bell = { 1.0, 0.78, 0.72, 0.64, 0.5, 0.28 },
	ball = { 0.72, 0.94, 1.0, 1.0, 0.92, 0.66 },
}
local FORMS: { [string]: string } = {
	slippery_jack = "flat", bay_bolete = "flat", aspen_bolete = "flat", porcini = "flat", coal_cap = "flat",
	peat_cap = "flat", drowned_cap = "flat", obsidian = "flat", cave_oyster = "flat",
	chanterelle = "funnel", saffron_milk_cap = "funnel", ember = "funnel",
	parasol = "parasol", moon_lily = "parasol", lake_cap = "parasol",
	lantern_shroom = "bell", wisp_cap = "bell", false_wisp = "bell", will_o_wisp = "bell", bog_bell = "bell",
	pearl = "ball", bog_pearl = "ball", skarbnik_truffle = "ball",
	crystal_cap = "crystal", amethyst = "crystal", silver_vein = "crystal", gold_nugget = "crystal",
	leszy_crown = "crown",
}
local EYE = rgb(43, 27, 18)
local BLUSH = rgb(255, 150, 160)
-- Voxelowe grzyby są trochę większe od dawnych gładkich, żeby było widać klocki i buzie
local SIZE = 1.25
-- Tekstura „kratki”: półprzezroczyste ciemniejsze i jaśniejsze kwadraty, jeden na voxel
local NOISE = ((Config :: any).VoxelNoise and (Config :: any).VoxelNoise.texture or "") :: string
local NOISE_FACES = { Enum.NormalId.Top, Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }
local TEXTURED: { [string]: boolean } = { Cap = true, Stem = true, StemBase = true }

local function texturize(part: BasePart, u: number)
	if NOISE == "" then
		return
	end
	-- Na jasnych kolorach (złoto, biel) ciemne kratki wyglądały brudno, więc tam są delikatniejsze
	local _, sat, v = part.Color:ToHSV()
	local base = if v > 0.85 and sat < 0.9 then 0.35 else 0
	for _, face in NOISE_FACES do
		local t = Instance.new("Texture")
		t.Transparency = base
		t:SetAttribute("BaseT", base)
		t.Texture = NOISE
		t.Face = face
		-- Tekstura ma 8 x 8 kratek, więc jedna kratka = jeden voxel
		t.StudsPerTileU = u * 8
		t.StudsPerTileV = u * 8
		t.OffsetStudsU = math.random(0, 7) * u
		t.OffsetStudsV = math.random(0, 7) * u
		t.Parent = part
	end
end

local function darken(c: Color3, k: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), k)
end
local function lighten(c: Color3, k: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), k)
end

-- Jeden grzybek. origin: CFrame w miejscu wyrastania (obrócony losowo wokół pionu).
-- Zwraca środek kapelusza (do świateł i efektów).
local function buildOne(model: Model, origin: CFrame, shape: Shape, species: string, scale: number, capColor: Color3, neon: boolean, parts: { BasePart }, face: boolean): BasePart
	local capW, capH = shape.capW * scale * SIZE, shape.capH * scale * SIZE
	local stemH, stemD = shape.stemH * scale * SIZE, shape.stemD * scale * SIZE
	local u = math.clamp(capW / 7, 0.16, 0.42)
	local function snap(v: number): number
		return math.max(u, math.round(v / u) * u)
	end
	local form = FORMS[species] or "dome"
	local stemColor = shape.stem or STEM
	if form == "funnel" then
		stemColor = darken(capColor, 0.08)
	end

	local function add(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?): Part
		local p = makePart(name, size, origin * offset, color)
		if material then
			p.Material = material
		end
		if TEXTURED[name] then
			texturize(p, u)
		end
		p.Parent = model
		table.insert(parts, p)
		return p
	end

	-- Trzon z szerszą podstawką i ciemniejszym paskiem z jednej strony
	local sd = snap(stemD)
	local sh = math.max(u * 2, stemH)
	if form ~= "ball" then
		add("Stem", Vector3.new(sd, sh, sd), CFrame.new(0, sh / 2, 0), stemColor)
		add("StemShade", Vector3.new(0.04, sh * 0.96, sd * 0.4), CFrame.new(sd / 2 + 0.01, sh / 2, sd * 0.2), darken(stemColor, 0.12))
		add("StemBase", Vector3.new(snap(sd * 1.3), u, snap(sd * 1.3)), CFrame.new(0, u / 2, 0), darken(stemColor, 0.05))
	else
		add("Stem", Vector3.new(sd, u * 1.5, sd), CFrame.new(0, u * 0.75, 0), stemColor)
		sh = u * 1.2
	end

	-- Kapelusz z warstw
	local profile = PROFILES[form] or PROFILES.dome
	local capParts: { BasePart } = {}
	local bottom = if form == "ball" then sh else sh - math.min(capH * 0.3, u * 1.5)
	local material = if neon then Enum.Material.Neon else nil
	local top = bottom
	local center: BasePart
	if form == "crystal" then
		-- Kryształ: trzy pochylone kolumny zamiast kopuły
		local h = snap(capH * 1.6)
		local mid = add("Cap", Vector3.new(snap(capW * 0.42), h, snap(capW * 0.42)), CFrame.new(0, bottom + h / 2, 0) * CFrame.Angles(0, math.rad(45), 0), capColor, material)
		table.insert(capParts, mid)
		for _, side in { -1, 1 } do
			local sh2 = snap(h * 0.7)
			local shard = add("Cap", Vector3.new(snap(capW * 0.3), sh2, snap(capW * 0.3)), CFrame.new(side * capW * 0.3, bottom + sh2 / 2, 0) * CFrame.Angles(0, 0, math.rad(-side * 24)), lighten(capColor, 0.12))
			table.insert(capParts, shard)
		end
		add("Shine", Vector3.new(u * 0.5, h * 0.7, 0.04), CFrame.new(0, bottom + h * 0.55, 0) * CFrame.Angles(0, math.rad(45), 0) * CFrame.new(-capW * 0.1, 0, -capW * 0.21 - 0.02), lighten(capColor, 0.6), material)
		top = bottom + h
		center = mid
	else
		local layerH = math.max(u, snap(capH * (if form == "ball" then 1.7 else 1.25) / #profile))
		for i, frac in profile do
			local w = snap(capW * frac)
			local color = if i == 1 then darken(capColor, 0.18) elseif i == #profile then lighten(capColor, 0.14) else lighten(capColor, (i - 2) * 0.04)
			-- Świecące grzyby: neon tylko na czubku (i na kropkach), żeby reszta zachowała pikselową kratkę
			local layerMaterial = if material and i >= #profile then material else nil
			if material and not layerMaterial then
				color = lighten(color, 0.12)
			end
			local layer = add("Cap", Vector3.new(w, layerH, w), CFrame.new(0, top + layerH / 2, 0), color, layerMaterial)
			table.insert(capParts, layer)
			top += layerH
		end
		center = capParts[math.max(1, #capParts // 2)]

		-- Kurka: jaśniejszy środek lejka na górze
		if form == "funnel" then
			local tw = snap(capW * profile[#profile] * 0.7)
			add("Top", Vector3.new(tw, 0.04, tw), CFrame.new(0, top + 0.02, 0), lighten(capColor, 0.25), material)
		end

		-- Blaszki pod kapeluszem (ciemniejsza płytka)
		if form ~= "ball" and form ~= "funnel" then
			local gw = snap(capW * profile[1] * 0.8)
			add("Gills", Vector3.new(gw, 0.06, gw), CFrame.new(0, bottom - 0.03, 0), darken(stemColor, 0.2))
		end

		-- Kropki: kwadratowe, na bokach dolnych warstw i na czubku
		if shape.spots then
			local dot = u * 0.9
			local count = 0
			for i = 2, math.min(#profile - 1, 4) do
				local w = snap(capW * profile[i])
				local y = bottom + (i - 0.5) * layerH
				for k = 0, 3 do
					if (k + i) % 2 == 0 then
						local angle = k * math.pi / 2
						local lateral = (if (k + i) % 4 == 0 then 0.22 else -0.2) * w
						local off = CFrame.Angles(0, angle, 0) * CFrame.new(lateral, y, -w / 2 - 0.01)
						add("Spot", Vector3.new(dot, math.min(dot, layerH * 0.9), 0.06), off, Color3.new(1, 1, 1), material)
						count += 1
					end
				end
			end
			local tw = snap(capW * profile[#profile])
			for _, dx in { -0.22, 0.22 } do
				add("Spot", Vector3.new(dot, 0.06, dot), CFrame.new(dx * tw, top + 0.02, dx * tw * 0.6), Color3.new(1, 1, 1), material)
			end
		end

		-- „Piksele” cienia i blasku na bokach, jak na teksturze z kratki
		if scale >= 0.9 then
			for k = 0, 3 do
				local i = 1 + (k % math.max(1, #profile - 1))
				local w = snap(capW * profile[i])
				local y = bottom + (i - 0.5) * layerH
				local angle = k * math.pi / 2 + math.pi / 4
				local off = CFrame.Angles(0, math.round(angle / (math.pi / 2)) * math.pi / 2, 0) * CFrame.new(((k % 3) - 1) * w * 0.3, y, -w / 2 - 0.012)
				add("Pixel", Vector3.new(u, math.min(u, layerH * 0.9), 0.04), off, if k % 2 == 0 then darken(capColor, 0.14) else lighten(capColor, 0.2))
			end
		end

		-- Korona Leszego: trzy rogi z klocków na czubku
		if form == "crown" then
			local tw = snap(capW * profile[#profile - 1])
			for k, dx in { -0.42, 0, 0.42 } do
				local h = snap(capH * (if k == 2 then 1.1 else 0.8))
				local prong = add("Cap", Vector3.new(u, h, u), CFrame.new(dx * tw, top - layerH + h / 2, 0), lighten(capColor, 0.1), material)
				table.insert(capParts, prong)
				add("Spot", Vector3.new(u * 1.05, u * 0.6, u * 1.05), CFrame.new(dx * tw, top - layerH + h, 0), Color3.new(1, 1, 1), Enum.Material.Neon)
			end
		end
	end

	-- Buzia na trzonie (oczka, rumieńce); tylko na większych grzybach
	if face and sd >= 0.4 and sh >= 0.8 and form ~= "ball" then
		local y = math.min(sh * 0.55, bottom - u * 1.2)
		local z = -sd / 2 - 0.015
		local e = math.max(0.08, sd * 0.14)
		for _, side in { -1, 1 } do
			add("Eye", Vector3.new(e, e * 1.5, 0.03), CFrame.new(side * sd * 0.2, y, z), EYE)
			add("Blush", Vector3.new(e * 1.2, e * 0.7, 0.03), CFrame.new(side * sd * 0.36, y - e * 1.2, z), BLUSH)
		end
		add("Mouth", Vector3.new(e * 1.4, e * 0.5, 0.03), CFrame.new(0, y - e * 1.1, z), EYE)
	elseif face and form == "ball" then
		local r = snap(capW * 1.0) / 2
		local y = sh + (top - sh) * 0.45
		local e = math.max(0.1, capW * 0.07)
		for _, side in { -1, 1 } do
			add("Eye", Vector3.new(e, e * 1.5, 0.03), CFrame.new(side * capW * 0.15, y, -r - 0.015), EYE)
			add("Blush", Vector3.new(e * 1.2, e * 0.7, 0.03), CFrame.new(side * capW * 0.28, y - e * 1.2, -r - 0.015), BLUSH)
		end
	end

	center:SetAttribute("CapTop", top)
	return center
end

-- ===== Aury rzadszych grzybów =====
-- Rzadki: światło w kolorze klasy. Epicki: w górę lecą voxelowe zarodniki.
-- Legendarny: złote świetliki z warkoczami krążą wokół, z nieba pada miękki snop światła.
-- Złoty: krążące złote świetliki. Tęczowy (mityczny): tęczowy kapelusz, tęczowe świetliki, snop i zarodniki.
-- Do tego od rzadkiego wzwyż (i dla srebrnych, złotych, tęczowych) świecący krąg na ziemi w kolorze
-- rzadkości z falą, która co chwilę rozchodzi się od grzyba, a epicki dostaje niższy fioletowy snop.

type Aura = {
	orbit: { BasePart },
	orbitRadius: number,
	orbitHeight: number,
	orbitRainbow: boolean,
	pillar: BasePart?, -- niewidzialna kotwica snopu światła (promienie Beam + unoszące się iskry)
	beams: { Beam }?,
	motes: ParticleEmitter?,
	spores: { Color3 }?,
	nextSpore: number,
	capTop: number,
	ring: BasePart?, -- świecący krąg na ziemi
	ripple: BasePart?, -- fala rozchodząca się od grzyba
	ringSize: number,
	ringRainbow: boolean,
}

local CLASS_RANK: { [string]: number } = { common = 0, uncommon = 1, rare = 2, epic = 3, legendary = 4 }

-- Przezroczystość wzdłuż promienia: miękko od ziemi, najjaśniej nisko, zanika wysoko w górze
local function shaftFade(base: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.08, base),
		NumberSequenceKeypoint.new(0.45, base + (1 - base) * 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
end

-- Snop światła: kilka nałożonych promieni (zawsze zwróconych do kamery) o różnej szerokości daje miękkie
-- brzegi bez kanciastego słupa. Do tego iskierki płynące w górę.
local SHAFT_LAYERS = { { width = 1, base = 0.86 }, { width = 0.6, base = 0.78 }, { width = 0.28, base = 0.62 } }
local function buildShaft(model: Model, origin: CFrame, width: number, height: number, color: Color3): (BasePart, { Beam }, ParticleEmitter)
	local anchor = makePart("Pillar", Vector3.new(0.2, 0.2, 0.2), origin, color)
	anchor.Transparency = 1
	anchor:SetAttribute("BaseT", 1)
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, 0.2, 0)
	bottom.Parent = anchor
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, height, 0)
	top.Parent = anchor
	local beams: { Beam } = {}
	for _, layer in SHAFT_LAYERS do
		local beam = Instance.new("Beam")
		beam.Attachment0 = bottom
		beam.Attachment1 = top
		beam.FaceCamera = true
		beam.Width0 = width * layer.width
		beam.Width1 = width * layer.width * 1.6
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Color = ColorSequence.new(color)
		beam.Transparency = shaftFade(layer.base)
		beam.Segments = 1
		beam:SetAttribute("Base", layer.base)
		beam.Parent = anchor
		table.insert(beams, beam)
	end
	local motes = Instance.new("ParticleEmitter")
	motes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	motes.LightEmission = 1
	motes.LightInfluence = 0
	motes.Color = ColorSequence.new(color)
	motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.25, 0.32), NumberSequenceKeypoint.new(1, 0) })
	motes.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	motes.Lifetime = NumberRange.new(2.2, 3.4)
	motes.Rate = 10
	motes.Speed = NumberRange.new(1.4, 2.6)
	motes.SpreadAngle = Vector2.new(12, 12)
	motes.Acceleration = Vector3.new(0, 0.6, 0)
	motes.RotSpeed = NumberRange.new(-60, 60)
	motes.Rotation = NumberRange.new(0, 360)
	motes.EmissionDirection = Enum.NormalId.Top
	motes.Shape = Enum.ParticleEmitterShape.Disc
	motes.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	motes.Parent = anchor
	-- Kształt Disc w poziomie: iskry startują z koła wokół grzyba
	anchor.Size = Vector3.new(width * 1.4, 0.2, width * 1.4)
	anchor.Parent = model
	return anchor, beams, motes
end
local TAG_SPORES: { [string]: { Color3 } } = {
	glowing = { rgb(110, 255, 214), rgb(220, 255, 245) },
	crystal = { rgb(120, 200, 255), rgb(230, 245, 255) },
	abyssal = { rgb(255, 90, 40), rgb(255, 190, 60) },
	mossy = { rgb(110, 190, 72), rgb(180, 230, 120) },
	pumpkin = { rgb(255, 140, 30), rgb(255, 214, 90), rgb(120, 50, 170) },
}
local activeSpores = 0
local MAX_SPORES = 70

local function buildAura(model: Model, info: MushroomInfo, origin: CFrame, shape: Shape, capColor: Color3, capTop: number, fxParts: { BasePart }): (Aura?, Color3?)
	local class = Economy.speciesClass(info.species)
	local rank = CLASS_RANK[class.id] or 0
	local variant = info.variant
	local classColor = rgb(class.color[1], class.color[2], class.color[3])
	local aura: Aura = {
		orbit = {},
		orbitRadius = shape.capW * SIZE * 0.85 + 0.4,
		orbitHeight = capTop * 0.6,
		orbitRainbow = false,
		nextSpore = 0,
		capTop = capTop,
		ringSize = shape.capW * SIZE * 1.9 + 1,
		ringRainbow = variant == "rainbow",
	}
	local any = false
	local light: Color3? = if rank >= 2 then classColor else nil

	local orbitColor: Color3? = nil
	if rank >= 4 or variant == "gold" then
		orbitColor = rgb(255, 205, 60)
	end
	if variant == "rainbow" then
		orbitColor = Color3.new(1, 1, 1)
		aura.orbitRainbow = true
	end
	if orbitColor then
		local cube = math.clamp(shape.capW / 7, 0.16, 0.36)
		for k = 1, if variant == "rainbow" then 6 else 4 do
			local p = makePart("Orbit", Vector3.new(cube, cube, cube) * 1.3, origin, orbitColor)
			p.Shape = Enum.PartType.Ball
			p.Material = Enum.Material.Neon
			-- Warkocz za świetlikiem: smuga światła, która zanika
			local a0 = Instance.new("Attachment")
			a0.Position = Vector3.new(0, cube * 0.5, 0)
			a0.Parent = p
			local a1 = Instance.new("Attachment")
			a1.Position = Vector3.new(0, -cube * 0.5, 0)
			a1.Parent = p
			local trail = Instance.new("Trail")
			trail.Attachment0 = a0
			trail.Attachment1 = a1
			trail.Lifetime = 0.55
			trail.LightEmission = 1
			trail.LightInfluence = 0
			trail.FaceCamera = true
			trail.Color = ColorSequence.new(orbitColor)
			trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
			trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
			trail.Parent = p
			p.Parent = model
			p:SetAttribute("Index", k)
			table.insert(aura.orbit, p)
			table.insert(fxParts, p)
		end
		any = true
	end
	if rank >= 4 or variant == "rainbow" then
		-- Snop światła widoczny z daleka (miękkie promienie i iskry zamiast kanciastego słupa)
		local shaftColor = if variant == "rainbow" then rgb(255, 170, 235) else rgb(255, 214, 90)
		local pillar, beams, motes = buildShaft(model, origin, shape.capW * SIZE * 1.1 + 0.6, 18, shaftColor)
		aura.pillar = pillar
		aura.beams = beams
		aura.motes = motes
		any = true
	end
	-- Epicki: niższy snop w kolorze klasy, żeby było go widać z daleka w ciemnym lesie
	if rank == 3 and not aura.pillar then
		local pillar, beams, motes = buildShaft(model, origin, shape.capW * SIZE * 0.8 + 0.4, 9, lighten(classColor, 0.25))
		aura.pillar = pillar
		aura.beams = beams
		aura.motes = motes
		any = true
	end
	-- Krąg na ziemi w kolorze rzadkości (wariant wygrywa z klasą)
	local ringColor: Color3? = nil
	if variant == "rainbow" then
		ringColor = rgb(255, 170, 235)
	elseif variant == "gold" then
		ringColor = rgb(255, 205, 60)
	elseif variant == "silver" then
		ringColor = rgb(220, 232, 248)
	elseif rank >= 2 then
		ringColor = classColor
	end
	if ringColor then
		local d = aura.ringSize
		local flat = origin * CFrame.new(0, 0.06, 0) * CFrame.Angles(0, 0, math.rad(90))
		-- Delikatna poświata pod grzybem
		local ring = makePart("RingGlow", Vector3.new(0.05, d, d), flat, ringColor)
		ring.Shape = Enum.PartType.Cylinder
		ring.Material = Enum.Material.Neon
		ring.Transparency = 0.92
		ring:SetAttribute("BaseT", 0.92)
		ring.Parent = model
		table.insert(fxParts, ring)
		aura.ring = ring
		-- Pikselowy krąg z 8 świecących kawałków (w stylu kostek, z jakich jest świat)
		local radius = d / 2
		local segment = 2 * math.pi * radius / 8 * 0.62
		for k = 0, 7 do
			local angle = k * math.pi / 4 + math.pi / 8
			local piece = makePart("RingPiece", Vector3.new(segment, 0.1, 0.22), origin * CFrame.Angles(0, -angle, 0) * CFrame.new(0, 0.1, -radius), ringColor)
			piece.Material = Enum.Material.Neon
			piece.Transparency = 0.35
			piece:SetAttribute("BaseT", 0.35)
			piece.Parent = model
			table.insert(fxParts, piece)
		end
		-- Fala rozchodząca się od grzyba: tylko epickie, legendarne i warianty
		if rank >= 3 or variant ~= nil then
			local ripple = makePart("RingRipple", Vector3.new(0.04, d, d), flat * CFrame.new(0.02, 0, 0), ringColor)
			ripple.Shape = Enum.PartType.Cylinder
			ripple.Material = Enum.Material.Neon
			ripple.Transparency = 1
			ripple:SetAttribute("BaseT", 1)
			ripple.Parent = model
			table.insert(fxParts, ripple)
			aura.ripple = ripple
		end
		any = true
	end
	local spores: { Color3 }? = nil
	if rank == 3 then
		spores = { classColor, rgb(255, 150, 240), lighten(classColor, 0.5) }
	end
	if variant == "rainbow" then
		spores = { rgb(255, 80, 80), rgb(255, 210, 60), rgb(110, 255, 110), rgb(80, 210, 255), rgb(190, 110, 255) }
	end
	for _, tag in info.tags or {} do
		if not spores and TAG_SPORES[tag] then
			spores = TAG_SPORES[tag]
		end
	end
	if spores then
		aura.spores = spores
		any = true
	end
	return if any then aura else nil, light
end

-- Jeden zarodnik: kostka leci w górę, obraca się i znika
local function spawnSpore(origin: Vector3, aura: Aura)
	if activeSpores >= MAX_SPORES or not aura.spores then
		return
	end
	activeSpores += 1
	local colors = aura.spores
	local s = 0.12 + math.random() * 0.12
	local start = origin + Vector3.new((math.random() - 0.5) * aura.orbitRadius, aura.capTop * (0.4 + math.random() * 0.6), (math.random() - 0.5) * aura.orbitRadius)
	local p = makePart("Spore", Vector3.new(s, s, s), CFrame.new(start) * CFrame.Angles(math.random() * 3, math.random() * 3, 0), colors[math.random(1, #colors)])
	p.Material = Enum.Material.Neon
	p.Parent = folder
	local tween = TweenService:Create(p, TweenInfo.new(1.4 + math.random() * 0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		CFrame = CFrame.new(start + Vector3.new((math.random() - 0.5) * 1.2, 2.2 + math.random() * 1.5, (math.random() - 0.5) * 1.2)) * CFrame.Angles(math.random() * 6, math.random() * 6, 0),
		Transparency = 1,
		Size = Vector3.new(s, s, s) * 0.4,
	})
	tween.Completed:Connect(function()
		activeSpores -= 1
		p:Destroy()
	end)
	tween:Play()
end

-- Halloween: buzia wycięta w kapeluszu (oczy-romby i zębaty uśmiech, świecą) z przodu i z tyłu
-- oraz zielony ogonek na czubku. Kapelusz to warstwy klocków; buzia idzie na najszerszą warstwę
-- głównego grzyba (oczy na warstwę nad nią, jeśli jest dość szeroka).
local function pumpkinFace(model: Model, origin: CFrame, species: string, capTop: number, parts: { BasePart })
	local function add(name: string, size: Vector3, cf: CFrame, color: Color3, neon: boolean)
		local p = makePart(name, size, cf, color)
		if neon then
			p.Material = Enum.Material.Neon
		end
		p.Parent = model
		table.insert(parts, p)
	end
	-- Warstwy kapelusza głównego grzyba (kępka: małe grzybki stoją obok środka)
	local layers: { BasePart } = {}
	for _, p in parts do
		local offset = origin:PointToObjectSpace(p.Position)
		if p.Name == "Cap" and math.abs(offset.X) < 0.05 and math.abs(offset.Z) < 0.05 then
			table.insert(layers, p)
		end
	end
	table.sort(layers, function(a, b)
		return a.Position.Y < b.Position.Y
	end)
	local top = layers[#layers]
	local u = if top then top.Size.Y else 0.3
	add("PumpkinStem", Vector3.new(u, u * 1.6, u), origin * CFrame.new(u * 0.2, capTop + u * 0.7, 0) * CFrame.Angles(0, 0, math.rad(-14)), PUMPKIN_STEM, false)
	if FORMS[species] == "crystal" or #layers == 0 then
		return
	end
	local widest = 1
	for i, p in layers do
		if p.Size.X > layers[widest].Size.X + 0.01 then
			widest = i
		end
	end
	local mouthLayer = layers[widest]
	local above = layers[widest + 1]
	local eyeLayer = if above and above.Size.X >= mouthLayer.Size.X * 0.7 then above else mouthLayer
	local shared = eyeLayer == mouthLayer
	for _, side in { 0, math.pi } do
		local turn = CFrame.Angles(0, side, 0)
		local h = mouthLayer.Size.Y
		local w = mouthLayer.Size.X
		local mouthAt = mouthLayer.CFrame * turn * CFrame.new(0, if shared then -h * 0.22 else -h * 0.05, -mouthLayer.Size.Z / 2 - 0.03)
		local mouthH = h * (if shared then 0.36 else 0.5)
		add("PumpkinMouth", Vector3.new(w * 0.46, mouthH, 0.05), mouthAt, PUMPKIN_GLOW, true)
		for _, x in { -0.1, 0.1 } do
			add("PumpkinTooth", Vector3.new(w * 0.07, mouthH * 0.45, 0.06), mouthAt * CFrame.new(x * w, mouthH * 0.3, -0.01), mouthLayer.Color, false)
		end
		local eh = eyeLayer.Size.Y
		local ew = eyeLayer.Size.X
		local eye = math.min(eh * (if shared then 0.42 else 0.72), ew * 0.16)
		for _, x in { -0.2, 0.2 } do
			local eyeAt = eyeLayer.CFrame * turn * CFrame.new(x * ew, if shared then eh * 0.22 else 0, -eyeLayer.Size.Z / 2 - 0.03)
			add("PumpkinEye", Vector3.new(eye, eye, 0.05), eyeAt * CFrame.Angles(0, 0, math.rad(45)), PUMPKIN_GLOW, true)
		end
	end
end

local function buildModel(info: MushroomInfo): (Model, { BasePart }, boolean, { BasePart }, Aura?, { BasePart })
	local model = Instance.new("Model")
	model.Name = info.id
	local shape = SHAPES[info.species] or DEFAULT_SHAPE
	local rank = Economy.variantRank(info.variant)
	-- Blask, Kryształ i Żar (cechy z jaskini) świecą jak Blask w lesie
	local glowing = hasTag(info, "glowing") or hasTag(info, "crystal") or hasTag(info, "abyssal")
	local capColor = variantColor(info.variant) or shape.cap
	local neon = rank >= 2 or shape.glow == true or glowing
	if not (rank >= 1) and glowing and not shape.glow then
		-- Blask bez wariantu: kolor gatunku rozjaśniony w stronę seledynu
		capColor = shape.cap:Lerp(rgb(110, 255, 214), 0.45)
	end
	local pumpkin = hasTag(info, "pumpkin")
	if pumpkin and rank == 0 then
		capColor = PUMPKIN
	elseif pumpkin and rank < 3 then
		-- Srebrna / złota dynia: wciąż pomarańczowa, z odcieniem wariantu (tęczowa mieni się jak zawsze)
		capColor = PUMPKIN:Lerp(capColor, 0.4)
	end
	local parts: { BasePart } = {}
	local yaw = math.random() * math.pi * 2
	local origin = CFrame.new(info.position) * CFrame.Angles(0, yaw, 0)

	local mainCap: BasePart
	if shape.cluster then
		-- Kępka: duży grzyb z buzią i mniejsze obok
		mainCap = buildOne(model, origin, shape, info.species, 1.15, capColor, neon, parts, true)
		for k = 1, shape.cluster - 1 do
			local angle = k * 2.3
			local at = origin * CFrame.new(math.cos(angle) * 0.85 * SIZE, 0, math.sin(angle) * 0.85 * SIZE) * CFrame.Angles(0, angle, 0)
			buildOne(model, at, shape, info.species, 0.75, capColor, neon, parts, false)
		end
	else
		mainCap = buildOne(model, origin, shape, info.species, 1, capColor, neon, parts, true)
	end
	local capTop = (mainCap:GetAttribute("CapTop") :: number?) or shape.stemH + shape.capH

	-- Kapelusze dostają materiał wariantu; tęczowe zmieniają kolor w updateVisibility
	local caps: { BasePart } = {}
	for _, p in parts do
		if p.Name == "Cap" then
			table.insert(caps, p)
			if rank == 1 then
				-- Srebro: metaliczny połysk zamiast świecenia
				p.Material = Enum.Material.Metal
				p.Reflectance = 0.3
			end
		end
	end

	-- Mech: zielone kostki na kapeluszu
	if hasTag(info, "mossy") then
		local u = math.clamp(shape.capW * SIZE / 7, 0.16, 0.42)
		for k = 1, 3 do
			local angle = k * 2.1
			local patch = makePart("Moss", Vector3.new(u * 1.6, u * 0.5, u * 1.6), origin * CFrame.new(math.cos(angle) * shape.capW * SIZE * 0.22, capTop + u * 0.1, math.sin(angle) * shape.capW * SIZE * 0.22), MOSS)
			patch.Parent = model
			table.insert(parts, patch)
		end
	end

	if pumpkin then
		pumpkinFace(model, origin, info.species, capTop, parts)
	end

	local fxParts: { BasePart } = {}
	local aura, classLight = buildAura(model, info, origin, shape, capColor, capTop, fxParts)

	local light: PointLight? = nil
	if neon or classLight then
		local newLight = Instance.new("PointLight")
		newLight.Color = if neon then (if glowing and rank < 2 then rgb(110, 255, 214) else capColor) else classLight :: Color3
		newLight.Range = if rank >= 2 then 10 else 8
		newLight.Brightness = if neon then 1.6 else 0.9
		newLight.Parent = mainCap
		light = newLight
	elseif pumpkin then
		-- Dynia świeci od środka jak lampion
		local newLight = Instance.new("PointLight")
		newLight.Color = rgb(255, 150, 50)
		newLight.Range = 8
		newLight.Brightness = 1.3
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
	local rainbow = if rank == 3 then caps else {}
	if light and rank == 3 then
		light:SetAttribute("Rainbow", true)
	end
	return model, parts, neon or rank >= 1, rainbow, aura, fxParts
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
			-- Grzyb podmieniony (np. o świcie): napis nad nim trzeba zbudować od nowa
			if targetId == info.id then
				targetId = nil
			end
		end
		local model, parts, animated, rainbow, aura, fxParts = buildModel(info)
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
			mimicLight = if Economy.isMimic(info.species) then model:FindFirstChildWhichIsA("PointLight", true) else nil,
			aura = aura,
			fxParts = fxParts,
		}
	end
end

-- Kolor kapelusza (do efektów przy zbieraniu)
function MushroomView.capColor(species: string, variant: string?): Color3
	return variantColor(variant) or (SHAPES[species] or DEFAULT_SHAPE).cap
end

-- Grzyby, których id zaczyna się od `prefix` (np. "tut_" w samouczku)
function MushroomView.withPrefix(prefix: string): { MushroomInfo }
	local list = {}
	for id, entry in entries do
		if string.sub(id, 1, #prefix) == prefix then
			table.insert(list, entry.info)
		end
	end
	return list
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
	if targetId == id then
		targetId = nil
		targetTag.Enabled = false
		targetTag.Adornee = nil
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
		for _, child in p:GetChildren() do
			if child:IsA("Texture") then
				TweenService:Create(child, info, { Transparency = 1 }):Play()
			end
		end
	end
	for _, p in entry.fxParts do
		TweenService:Create(p, info, { Transparency = 1 }):Play()
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
		if targetId ~= bestId then
			-- Obwódka i napis w kolorze klasy grzyba
			local class = Economy.speciesClass(target.info.species)
			local color = rgb(class.color[1], class.color[2], class.color[3])
			local species = Economy.getSpecies(target.info.species)
			highlight.OutlineColor = color
			targetLabel.TextColor3 = color
			targetLabel.Text = (if species then Localize.t(species.key) else "?") .. " · " .. Localize.t(class.key)
			targetTag.Adornee = target.model.PrimaryPart
			targetTag.Enabled = true
		end
	else
		highlight.Enabled = false
		highlight.Adornee = nil
		targetTag.Enabled = false
		targetTag.Adornee = nil
	end
	targetId = bestId
	return bestId
end

-- W ciemnych strefach widać tylko grzyby w zasięgu latarni (świecące widać zawsze).
-- Przy okazji złote i świecące delikatnie się unoszą.
-- Cutscenka ogląda grzyby z innego miejsca niż stoi gracz (aury liczą odległość od tego punktu)
local viewer: Vector3? = nil
function MushroomView.setViewer(at: Vector3?)
	viewer = at
end

function MushroomView.updateVisibility(position: Vector3, lanternRange: number, darkness: number)
	position = viewer or position
	local visibleRange = if darkness >= 0.7 then lanternRange + 2 else math.huge
	local t = os.clock()
	for _, entry in entries do
		local glows = entry.animated
		local hidden = not glows and flatDistance(position, entry.info.position) > visibleRange
		if hidden ~= entry.hidden then
			entry.hidden = hidden
			for _, p in entry.parts do
				p.Transparency = if hidden then 1 else 0
				-- Tekstury rysują się niezależnie od przezroczystości części, więc chowamy je osobno
				for _, child in p:GetChildren() do
					if child:IsA("Texture") then
						child.Transparency = if hidden then 1 else ((child:GetAttribute("BaseT") :: number?) or 0)
					end
				end
			end
			for _, p in entry.fxParts do
				p.Transparency = if hidden then 1 else ((p:GetAttribute("BaseT") :: number?) or 0)
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
		local mimicLight = entry.mimicLight
		if mimicLight and not entry.hidden then
			mimicLight.Brightness = 1.6 * (0.25 + 0.75 * math.abs(math.noise(t * 5, entry.phase * 10)))
		end
		if glows and t >= entry.bobFrom and flatDistance(position, entry.info.position) < 120 then
			local bob = 0.18 * math.sin(t * 2 + entry.phase)
			entry.model:PivotTo(entry.basePivot * CFrame.new(0, bob, 0) * CFrame.Angles(0, math.sin(t * 0.7 + entry.phase) * 0.15, 0))
		end
		-- Aura: krążące kostki, pulsujący słup światła i zarodniki (tylko blisko gracza)
		local aura = entry.aura :: Aura?
		if aura and not entry.hidden then
			local distance = flatDistance(position, entry.info.position)
			if distance < 90 then
				local n = #aura.orbit
				for i, p in aura.orbit do
					local a = t * 1.4 + i * math.pi * 2 / n + entry.phase
					local at = entry.info.position + Vector3.new(math.cos(a) * aura.orbitRadius, aura.orbitHeight + math.sin(t * 2 + i) * 0.3, math.sin(a) * aura.orbitRadius)
					p.CFrame = CFrame.new(at)
					if aura.orbitRainbow then
						p.Color = Color3.fromHSV((t * 0.35 + i / n) % 1, 0.7, 1)
						local trail = p:FindFirstChildOfClass("Trail")
						if trail then
							trail.Color = ColorSequence.new(p.Color)
						end
					end
				end
				local beams = aura.beams
				if beams then
					-- Snop oddycha (delikatny puls), tęczowy przechodzi przez kolory od dołu do góry
					local pulse = 0.05 * math.sin(t * 2.2 + entry.phase)
					for i, beam in beams do
						local base = ((beam:GetAttribute("Base") :: number?) or 0.8) + pulse
						beam.Transparency = shaftFade(math.clamp(base, 0, 1))
						if aura.orbitRainbow then
							local h = (t * 0.15 + entry.phase + i * 0.05) % 1
							beam.Color = ColorSequence.new(Color3.fromHSV(h, 0.45, 1), Color3.fromHSV((h + 0.3) % 1, 0.45, 1))
						end
					end
					local motes = aura.motes
					if motes and aura.orbitRainbow then
						local h = (t * 0.2 + entry.phase) % 1
						motes.Color = ColorSequence.new(Color3.fromHSV(h, 0.5, 1), Color3.fromHSV((h + 0.5) % 1, 0.5, 1))
					end
				end
				-- Krąg oddycha, a fala co chwilę rozchodzi się od grzyba i gaśnie
				local ring, ripple = aura.ring, aura.ripple
				if ring then
					local breath = 0.5 + 0.5 * math.sin(t * 2.4 + entry.phase)
					ring.Transparency = 0.94 - 0.06 * breath
					if aura.ringRainbow then
						ring.Color = Color3.fromHSV((t * 0.35 + entry.phase) % 1, 0.55, 1)
					end
				end
				if ripple then
					local k = (t * 0.5 + entry.phase) % 1
					local size = aura.ringSize * (0.4 + k * 1.0)
					ripple.Size = Vector3.new(0.04, size, size)
					ripple.Transparency = 0.7 + 0.3 * k
					if aura.ringRainbow then
						ripple.Color = Color3.fromHSV((t * 0.35 + entry.phase) % 1, 0.55, 1)
					end
				end
				if aura.spores and distance < 50 and t >= aura.nextSpore then
					aura.nextSpore = t + 0.25 + math.random() * 0.3
					spawnSpore(entry.info.position, aura)
				end
			end
		end
	end
end

return MushroomView
