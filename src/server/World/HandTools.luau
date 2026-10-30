--!strict
-- Modele w dłoniach grzybiarza: latarnia (prawa ręka) i nożyk grzybiarski (lewa ręka).
--
-- Latarnia: kuta rama, szybki z bursztynowego szkła, płomyk w środku i mały muchomor na czubku.
-- Okucia zmieniają się z poziomem ulepszenia latarni: żelazo → mosiądz → złoto.
-- Część z płomieniem nazywa się "LanternGlass" (klient przyciemnia ją, gdy kończy się olej).
--
-- Nożyk: każdy poziom ulepszenia ma własny wygląd, od czerwonego scyzoryka po kryształowy
-- nóż z fioletową poświatą. Od 1. poziomu klasyczny nóż grzybiarza z zakrzywionym ostrzem
-- i pędzelkiem na końcu rączki, od 4. świecąca krawędź i iskry.
--
-- Wszystko z prostych części (spawane do ręki, bez kolizji i masy), żeby pasowało do stylu
-- świata i dało się kolorować per poziom.

local HandTools = {}

local VERTICAL = CFrame.Angles(0, 0, math.rad(90)) -- oś walca (X) pionowo

local function part(parent: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function wedge(parent: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): WedgePart
	local p = Instance.new("WedgePart")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = false
	p.Parent = parent
	return p
end

-- Kula spłaszczona (kapelusz grzyba, płomień) przez SpecialMesh
local function blob(parent: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = part(parent, name, size, cf, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- Powiększa model względem punktu chwytu, potem spawa wszystkie części do ręki
-- (albo zostawia je zakotwiczone, gdy to podgląd)
local function attach(model: Model, weldTo: BasePart?, base: CFrame, scale: number)
	model.WorldPivot = base
	if scale ~= 1 then
		model:ScaleTo(scale)
	end
	for _, child in model:GetDescendants() do
		if child:IsA("BasePart") then
			if weldTo then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = weldTo
				weld.Part1 = child
				weld.Parent = child
			else
				child.Anchored = true
			end
		end
	end
end

-- ===== Latarnia =====

type Trim = { metal: Color3, dark: Color3, material: Enum.Material }
local TRIMS: { Trim } = {
	{ metal = Color3.fromRGB(74, 70, 66), dark = Color3.fromRGB(44, 42, 40), material = Enum.Material.Metal }, -- kute żelazo
	{ metal = Color3.fromRGB(196, 146, 70), dark = Color3.fromRGB(120, 84, 40), material = Enum.Material.Metal }, -- mosiądz
	{ metal = Color3.fromRGB(255, 206, 90), dark = Color3.fromRGB(176, 120, 30), material = Enum.Material.Metal }, -- złoto
}

function HandTools.lanternTier(level: number): number
	return if level >= 6 then 3 elseif level >= 3 then 2 else 1
end

-- base: punkt chwytu (górny pałąk), latarnia wisi w dół wzdłuż -Y
function HandTools.lantern(level: number, base: CFrame, weldTo: BasePart?, scale: number?, skin: string?): Model
	if skin == "pumpkin_lantern" then
		return HandTools.pumpkinLantern(level, base, weldTo, scale)
	end
	local trim = TRIMS[HandTools.lanternTier(level)]
	local m = Instance.new("Model")
	m.Name = "HandLantern"
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x, y, z)
	end

	-- Pałąk: poprzeczka w dłoni i dwa ramiona do daszka
	part(m, "Bail", Vector3.new(0.3, 0.05, 0.05), at(0, 0, 0), trim.dark, trim.material)
	for _, side in { -1, 1 } do
		part(m, "BailArm", Vector3.new(0.05, 0.24, 0.05), at(side * 0.17, -0.1, 0) * CFrame.Angles(0, 0, side * math.rad(-22)), trim.dark, trim.material)
	end

	-- Muchomorek na czubku zamiast zwykłej gałki
	part(m, "FinialStem", Vector3.new(0.07, 0.08, 0.08), at(0, -0.2, 0) * VERTICAL, Color3.fromRGB(246, 236, 214), nil, Enum.PartType.Cylinder)
	blob(m, "FinialCap", Vector3.new(0.26, 0.14, 0.26), at(0, -0.14, 0), Color3.fromRGB(226, 52, 40))
	for _, dot in { { 0.06, 0.02 }, { -0.05, -0.06 }, { -0.04, 0.07 }, { 0.02, -0.02 } } do
		blob(m, "FinialDot", Vector3.new(0.045, 0.025, 0.045), at(dot[1], -0.085, dot[2]), Color3.fromRGB(255, 250, 240))
	end

	-- Daszek: dwa stopnie i okap
	part(m, "RoofTop", Vector3.new(0.12, 0.3, 0.3), at(0, -0.27, 0) * VERTICAL, trim.metal, trim.material, Enum.PartType.Cylinder)
	part(m, "Roof", Vector3.new(0.1, 0.5, 0.5), at(0, -0.35, 0) * VERTICAL, trim.metal, trim.material, Enum.PartType.Cylinder)
	part(m, "Eave", Vector3.new(0.6, 0.06, 0.6), at(0, -0.42, 0), trim.dark, trim.material)

	-- Klatka: cztery słupki, środkowe pręty na szybkach, szkło i płomień
	local cageY, cageH = -0.73, 0.56
	for _, x in { -0.24, 0.24 } do
		for _, z in { -0.24, 0.24 } do
			part(m, "Post", Vector3.new(0.06, cageH, 0.06), at(x, cageY, z), trim.dark, trim.material)
		end
	end
	for i = 0, 3 do
		local face = at(0, cageY, 0) * CFrame.Angles(0, i * math.pi / 2, 0) * CFrame.new(0, 0, -0.235)
		part(m, "Bar", Vector3.new(0.03, cageH, 0.03), face, trim.dark, trim.material)
		part(m, "BarCross", Vector3.new(0.44, 0.03, 0.03), face, trim.dark, trim.material)
	end
	local glass = part(m, "Pane", Vector3.new(0.44, cageH - 0.02, 0.44), at(0, cageY, 0), Color3.fromRGB(255, 196, 110), Enum.Material.Glass)
	glass.Transparency = 0.5
	-- Płomień: zewnętrzna poświata (tę część przyciemnia klient, gdy brakuje oleju) i jasny rdzeń
	part(m, "Wick", Vector3.new(0.05, 0.08, 0.08), at(0, cageY - 0.2, 0) * VERTICAL, Color3.fromRGB(40, 30, 24), nil, Enum.PartType.Cylinder)
	local flame = blob(m, "LanternGlass", Vector3.new(0.24, 0.36, 0.24), at(0, cageY - 0.02, 0), Color3.fromRGB(255, 190, 90), Enum.Material.Neon)
	flame.Transparency = 0.1
	blob(m, "FlameCore", Vector3.new(0.1, 0.16, 0.1), at(0, cageY - 0.07, 0), Color3.fromRGB(255, 248, 210), Enum.Material.Neon)

	-- Podstawa: płyta, miseczka i cztery nóżki
	part(m, "Floor", Vector3.new(0.58, 0.07, 0.58), at(0, cageY - cageH / 2 - 0.03, 0), trim.dark, trim.material)
	part(m, "Dish", Vector3.new(0.08, 0.46, 0.46), at(0, cageY - cageH / 2 - 0.1, 0) * VERTICAL, trim.metal, trim.material, Enum.PartType.Cylinder)
	for _, x in { -0.2, 0.2 } do
		for _, z in { -0.2, 0.2 } do
			part(m, "Foot", Vector3.new(0.08, 0.08, 0.08), at(x, cageY - cageH / 2 - 0.15, z), trim.dark, trim.material, Enum.PartType.Ball)
		end
	end

	m:SetAttribute("Tier", HandTools.lanternTier(level))
	attach(m, weldTo, base, scale or 1.35)
	return m
end

-- Halloween: dyniowa latarnia (skórka). Kuty pałąk, haczyk i dynia z wyciętą, świecącą buzią
-- z przodu i z tyłu. Usta z przodu nazywają się "LanternGlass" (klient przyciemnia je przy końcu oleju).
local PUMPKIN = Color3.fromRGB(226, 110, 24)
local PUMPKIN_DARK = Color3.fromRGB(168, 70, 14)
local PUMPKIN_GLOW = Color3.fromRGB(255, 200, 80)
function HandTools.pumpkinLantern(level: number, base: CFrame, weldTo: BasePart?, scale: number?): Model
	local trim = TRIMS[HandTools.lanternTier(level)]
	local m = Instance.new("Model")
	m.Name = "HandLantern"
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x, y, z)
	end
	part(m, "Bail", Vector3.new(0.3, 0.05, 0.05), at(0, 0, 0), trim.dark, trim.material)
	for _, side in { -1, 1 } do
		part(m, "BailArm", Vector3.new(0.05, 0.22, 0.05), at(side * 0.13, -0.09, 0) * CFrame.Angles(0, 0, side * math.rad(-30)), trim.dark, trim.material)
	end
	part(m, "Hook", Vector3.new(0.12, 0.05, 0.05), at(0, -0.2, 0), trim.metal, trim.material)
	part(m, "Stem", Vector3.new(0.09, 0.14, 0.09), at(0.02, -0.27, 0) * CFrame.Angles(0, 0, math.rad(-10)), Color3.fromRGB(70, 104, 40))
	-- Dynia: środek i dwa „płaty” na krzyż, żeby z klocków wyszła okrągła
	local y = -0.58
	part(m, "Body", Vector3.new(0.6, 0.48, 0.6), at(0, y, 0), PUMPKIN)
	part(m, "LobeX", Vector3.new(0.68, 0.4, 0.46), at(0, y, 0), PUMPKIN_DARK)
	part(m, "LobeZ", Vector3.new(0.46, 0.4, 0.68), at(0, y, 0), PUMPKIN_DARK)
	part(m, "Top", Vector3.new(0.42, 0.06, 0.42), at(0, y + 0.27, 0), PUMPKIN)
	part(m, "Bottom", Vector3.new(0.42, 0.06, 0.42), at(0, y - 0.27, 0), PUMPKIN_DARK)
	for _, turn in { 0, math.pi } do
		local face = at(0, y, 0) * CFrame.Angles(0, turn, 0) * CFrame.new(0, 0, -0.345)
		for _, x in { -0.12, 0.12 } do
			part(m, "Eye", Vector3.new(0.1, 0.1, 0.03), face * CFrame.new(x, 0.08, 0) * CFrame.Angles(0, 0, math.rad(45)), PUMPKIN_GLOW, Enum.Material.Neon)
		end
		part(m, if turn == 0 then "LanternGlass" else "Mouth", Vector3.new(0.3, 0.08, 0.03), face * CFrame.new(0, -0.1, 0), PUMPKIN_GLOW, Enum.Material.Neon)
		for _, x in { -0.06, 0.06 } do
			part(m, "Tooth", Vector3.new(0.045, 0.04, 0.035), face * CFrame.new(x, -0.075, -0.003), PUMPKIN)
		end
	end
	m:SetAttribute("Tier", HandTools.lanternTier(level))
	m:SetAttribute("Skin", "pumpkin_lantern")
	attach(m, weldTo, base, scale or 1.35)
	return m
end

-- ===== Nożyk =====

type KnifeStyle = {
	handle: Color3,
	handleMaterial: Enum.Material?,
	bands: Color3?, -- obręcze na rączce
	bolster: Color3?, -- pierścień między rączką a ostrzem
	blade: Color3,
	bladeMaterial: Enum.Material,
	bladeTransparency: number?,
	edge: Color3?, -- świecąca krawędź (Neon)
	curved: boolean, -- ostrze zakrzywione do góry jak w nożu grzybiarza
	short: boolean?, -- krótkie ostrze scyzoryka
	brush: boolean, -- pędzelek na końcu rączki (do czyszczenia grzybów)
	gem: Color3?, -- kamień w głowicy zamiast pędzelka
	cross: boolean?, -- biały krzyżyk na rączce scyzoryka
	sparkle: Color3?, -- iskry z ostrza
	light: Color3?,
}

local WOOD_LIGHT = Color3.fromRGB(214, 170, 112)
local WOOD_WALNUT = Color3.fromRGB(112, 70, 44)
local STEEL = Color3.fromRGB(192, 198, 206)

local KNIVES: { [number]: KnifeStyle } = {
	-- 0: czerwony scyzoryk z krzyżykiem
	[0] = { handle = Color3.fromRGB(200, 40, 36), blade = Color3.fromRGB(170, 174, 180), bladeMaterial = Enum.Material.Metal, curved = false, short = true, brush = false, cross = true },
	-- 1: klasyczny nóż grzybiarza: jasne drewno, zakrzywione ostrze, pędzelek
	[1] = { handle = WOOD_LIGHT, handleMaterial = Enum.Material.Wood, blade = STEEL, bladeMaterial = Enum.Material.Metal, curved = true, brush = true },
	-- 2: orzech, mosiężne okucie, polerowane ostrze
	[2] = { handle = WOOD_WALNUT, handleMaterial = Enum.Material.Wood, bolster = Color3.fromRGB(206, 156, 72), bands = Color3.fromRGB(206, 156, 72), blade = Color3.fromRGB(226, 232, 240), bladeMaterial = Enum.Material.Metal, curved = true, brush = true },
	-- 3: lazurowy: granatowa rączka, srebro i niebieski kamień
	[3] = { handle = Color3.fromRGB(36, 52, 96), bolster = Color3.fromRGB(214, 224, 238), bands = Color3.fromRGB(214, 224, 238), blade = Color3.fromRGB(200, 222, 240), bladeMaterial = Enum.Material.Metal, edge = Color3.fromRGB(120, 200, 255), curved = true, brush = false, gem = Color3.fromRGB(80, 170, 255) },
	-- 4: złoty ze świecącą krawędzią
	[4] = { handle = Color3.fromRGB(40, 30, 28), bolster = Color3.fromRGB(255, 206, 80), bands = Color3.fromRGB(255, 206, 80), blade = Color3.fromRGB(255, 200, 70), bladeMaterial = Enum.Material.Metal, edge = Color3.fromRGB(255, 236, 140), curved = true, brush = true, gem = nil, sparkle = Color3.fromRGB(255, 226, 120), light = Color3.fromRGB(255, 210, 110) },
	-- 5: ognisty: ciemna stal, żarząca się krawędź i iskry
	[5] = { handle = Color3.fromRGB(90, 24, 20), bolster = Color3.fromRGB(60, 56, 54), bands = Color3.fromRGB(255, 130, 60), blade = Color3.fromRGB(60, 56, 58), bladeMaterial = Enum.Material.Metal, edge = Color3.fromRGB(255, 120, 40), curved = true, brush = false, gem = Color3.fromRGB(255, 90, 40), sparkle = Color3.fromRGB(255, 140, 50), light = Color3.fromRGB(255, 120, 50) },
	-- 6: ametystowy kryształ z fioletową poświatą
	[6] = { handle = Color3.fromRGB(226, 230, 240), handleMaterial = Enum.Material.Metal, bolster = Color3.fromRGB(170, 100, 255), bands = Color3.fromRGB(170, 100, 255), blade = Color3.fromRGB(190, 130, 255), bladeMaterial = Enum.Material.Glass, bladeTransparency = 0.25, edge = Color3.fromRGB(220, 160, 255), curved = true, brush = false, gem = Color3.fromRGB(200, 120, 255), sparkle = Color3.fromRGB(220, 170, 255), light = Color3.fromRGB(190, 120, 255) },
}

local function sparkles(host: BasePart, color: Color3)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Sparkle"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.08), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new(0.1, 1)
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Rate = 6
	emitter.Speed = NumberRange.new(0.2, 0.6)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, 0.8, 0)
	emitter.Parent = host
end

function HandTools.knifeStyle(level: number): KnifeStyle
	return KNIVES[math.clamp(level, 0, 6)]
end

-- base: środek chwytu w dłoni; nóż leży wzdłuż -Z (ostrze do przodu), góra ostrza to +Y
function HandTools.knife(level: number, base: CFrame, weldTo: BasePart?, scale: number?, skin: string?): Model
	if skin == "sickle" then
		return HandTools.sickle(level, base, weldTo, scale)
	end
	local style = HandTools.knifeStyle(level)
	local m = Instance.new("Model")
	m.Name = "HandKnife"

	-- Rączka: od z = +0.26 (koniec) do z = -0.16 (okucie)
	local handleLength = 0.42
	local handleCenter = base * CFrame.new(0, 0, 0.05)
	part(m, "Handle", Vector3.new(0.14, 0.15, handleLength), handleCenter, style.handle, style.handleMaterial)
	-- Zaokrąglenie spodu rączki (wygodny chwyt)
	part(m, "HandleBelly", Vector3.new(handleLength - 0.06, 0.14, 0.14), handleCenter * CFrame.new(0, -0.04, 0) * CFrame.Angles(0, math.rad(90), 0), style.handle, style.handleMaterial, Enum.PartType.Cylinder)
	if style.bands then
		for _, z in { -0.08, 0.16 } do
			part(m, "Band", Vector3.new(0.155, 0.165, 0.03), base * CFrame.new(0, 0, z), style.bands, Enum.Material.Metal)
		end
	end
	if style.cross then
		part(m, "CrossV", Vector3.new(0.145, 0.07, 0.02), base * CFrame.new(0, 0.005, 0.05), Color3.new(1, 1, 1))
		part(m, "CrossH", Vector3.new(0.145, 0.02, 0.07), base * CFrame.new(0, 0.005, 0.05), Color3.new(1, 1, 1))
	end
	-- Nity
	for _, z in { -0.02, 0.12 } do
		part(m, "Rivet", Vector3.new(0.16, 0.035, 0.035), base * CFrame.new(0, 0.02, z) * CFrame.Angles(0, 0, 0), Color3.fromRGB(220, 220, 226), Enum.Material.Metal, Enum.PartType.Cylinder)
	end

	-- Koniec rączki: pędzelek z włosia albo kamień w głowicy
	local back = base * CFrame.new(0, 0, 0.26)
	if style.brush then
		part(m, "BrushBand", Vector3.new(0.15, 0.15, 0.05), back * CFrame.new(0, 0, 0.02), Color3.fromRGB(60, 50, 44), Enum.Material.Metal)
		-- Włosie szersze niż rączka i rozczapierzone; materiał trawy daje włóknisty wygląd
		part(m, "Brush", Vector3.new(0.17, 0.17, 0.15), back * CFrame.new(0, 0, 0.12), Color3.fromRGB(226, 196, 140), Enum.Material.Grass)
		part(m, "BrushTip", Vector3.new(0.2, 0.2, 0.05), back * CFrame.new(0, 0, 0.2), Color3.fromRGB(196, 160, 104), Enum.Material.Grass)
	end
	if style.gem then
		local pommel = style.bolster or style.handle
		part(m, "Pommel", Vector3.new(0.16, 0.16, 0.05), back * CFrame.new(0, 0, if style.brush then -0.03 else 0.01), pommel, Enum.Material.Metal)
		if not style.brush then
			local gem = part(m, "Gem", Vector3.new(0.12, 0.12, 0.12), back * CFrame.new(0, 0, 0.07), style.gem, Enum.Material.Glass, Enum.PartType.Ball)
			gem.Transparency = 0.15
			blob(m, "GemGlow", Vector3.new(0.06, 0.06, 0.06), back * CFrame.new(0, 0, 0.07), style.gem, Enum.Material.Neon)
		end
	end

	-- Okucie między rączką a ostrzem
	local front = base * CFrame.new(0, 0, -0.16)
	part(m, "Bolster", Vector3.new(0.16, 0.18, 0.05), front, style.bolster or Color3.fromRGB(150, 150, 156), Enum.Material.Metal)

	-- Ostrze: grzbiet u góry (+Y), krawędź tnąca na dole. Nóż grzybiarza ma czubek zagięty
	-- do góry (haczyk), scyzoryk krótkie proste ostrze.
	local bladeHeight = 0.13
	local straight = if style.short then 0.22 else 0.3
	local start = front * CFrame.new(0, 0.01, -0.025)
	local seg1 = start * CFrame.new(0, 0, -straight / 2)
	local function bladePart(name: string, size: Vector3, cf: CFrame): Part
		local p = part(m, name, size, cf, style.blade, style.bladeMaterial)
		p.Transparency = style.bladeTransparency or 0
		p.Reflectance = if style.bladeMaterial == Enum.Material.Metal then 0.15 else 0
		return p
	end
	local mainBlade = bladePart("Blade", Vector3.new(0.035, bladeHeight, straight), seg1)
	local tipBase = start * CFrame.new(0, 0, -straight)
	if style.curved then
		-- Zakrzywiona końcówka: krótszy odcinek pod kątem do góry i czubek z klina
		local bend = tipBase * CFrame.Angles(math.rad(32), 0, 0)
		local curveLength = 0.15
		bladePart("BladeCurve", Vector3.new(0.035, bladeHeight * 0.85, curveLength), bend * CFrame.new(0, -0.005, -curveLength / 2))
		-- Klin bez obrotu ma pełną wysokość z tyłu (+Z) i schodzi do zera z przodu przy spodzie;
		-- obrócony do góry nogami daje szpic u góry, czyli haczyk noża grzybiarza
		local tip = wedge(m, "BladeTip", Vector3.new(0.035, bladeHeight * 0.85, 0.12), bend * CFrame.new(0, -0.005, -curveLength - 0.06) * CFrame.Angles(0, 0, math.pi), style.blade, style.bladeMaterial)
		tip.Transparency = style.bladeTransparency or 0
		if style.edge then
			local edge = part(m, "Edge", Vector3.new(0.045, 0.025, straight), seg1 * CFrame.new(0, -bladeHeight / 2, 0), style.edge, Enum.Material.Neon)
			edge.Transparency = 0.05
			part(m, "EdgeCurve", Vector3.new(0.045, 0.025, curveLength), bend * CFrame.new(0, -bladeHeight * 0.425 - 0.005, -curveLength / 2), style.edge, Enum.Material.Neon)
		end
	else
		-- Prosty czubek scyzoryka
		local tip = wedge(m, "BladeTip", Vector3.new(0.035, bladeHeight, 0.1), tipBase * CFrame.new(0, 0, -0.05), style.blade, style.bladeMaterial)
		tip.Transparency = style.bladeTransparency or 0
	end
	-- Fuller: ciemniejszy rowek wzdłuż ostrza (od 2. poziomu)
	if level >= 2 then
		part(m, "Fuller", Vector3.new(0.04, 0.022, straight * 0.7), seg1 * CFrame.new(0, 0.03, 0.02), style.blade:Lerp(Color3.new(0, 0, 0), 0.25), style.bladeMaterial)
	end

	if style.sparkle then
		sparkles(mainBlade, style.sparkle)
	end
	if style.light then
		local light = Instance.new("PointLight")
		light.Color = style.light
		light.Range = 5
		light.Brightness = 0.8
		light.Shadows = false
		light.Parent = mainBlade
	end

	m:SetAttribute("Level", level)
	attach(m, weldTo, base, scale or 1.7)
	return m
end

-- Halloween: sierp (skórka nożyka). Ciemna rączka z pomarańczowymi obręczami i dynią w głowicy,
-- ostrze wygięte w półksiężyc ze świecącą pomarańczową krawędzią od środka łuku.
function HandTools.sickle(level: number, base: CFrame, weldTo: BasePart?, scale: number?): Model
	local m = Instance.new("Model")
	m.Name = "HandKnife"
	local handleColor = Color3.fromRGB(70, 46, 34)
	part(m, "Handle", Vector3.new(0.13, 0.14, 0.42), base * CFrame.new(0, 0, 0.05), handleColor, Enum.Material.Wood)
	for _, z in { -0.1, 0.18 } do
		part(m, "Band", Vector3.new(0.145, 0.155, 0.03), base * CFrame.new(0, 0, z), Color3.fromRGB(240, 128, 30), Enum.Material.Metal)
	end
	part(m, "Pommel", Vector3.new(0.16, 0.14, 0.14), base * CFrame.new(0, 0, 0.3), PUMPKIN)
	part(m, "PommelStem", Vector3.new(0.04, 0.06, 0.04), base * CFrame.new(0, 0.09, 0.3), Color3.fromRGB(70, 104, 40))
	part(m, "Bolster", Vector3.new(0.15, 0.17, 0.05), base * CFrame.new(0, 0, -0.17), Color3.fromRGB(60, 56, 64), Enum.Material.Metal)

	-- Łuk ostrza w płaszczyźnie YZ układu chwytu: środek łuku nad i przed rączką
	local center = Vector3.new(0, 0.26, -0.42)
	local radius = 0.34
	local from, to = math.rad(-52), math.rad(-245)
	local steps = 9
	local blade = Color3.fromRGB(70, 68, 78)
	local glow = Color3.fromRGB(255, 150, 50)
	local function point(angle: number): Vector3
		return center + Vector3.new(0, radius * math.sin(angle), radius * math.cos(angle))
	end
	local first: BasePart? = nil
	for i = 0, steps - 1 do
		local a = from + (to - from) * i / steps
		local b = from + (to - from) * (i + 1) / steps
		local pa, pb = point(a), point(b)
		local mid = (pa + pb) / 2
		local outward = (mid - center).Unit
		local height = 0.13 - 0.09 * (i / (steps - 1)) -- ostrze zwęża się ku czubkowi
		local length = (pb - pa).Magnitude + 0.02
		local segment_cf = CFrame.lookAt(mid, pb, outward)
		local segment = part(m, "Blade", Vector3.new(0.035, height, length), base * segment_cf * CFrame.new(0, height * 0.2, 0), blade, Enum.Material.Metal)
		segment.Reflectance = 0.15
		first = first or segment
		-- Krawędź tnąca od środka łuku
		part(m, "Edge", Vector3.new(0.045, 0.022, length), base * segment_cf * CFrame.new(0, -height * 0.3, 0), glow, Enum.Material.Neon)
	end
	if first then
		local light = Instance.new("PointLight")
		light.Color = glow
		light.Range = 5
		light.Brightness = 0.7
		light.Shadows = false
		light.Parent = first
	end
	m:SetAttribute("Level", level)
	m:SetAttribute("Skin", "sickle")
	attach(m, weldTo, base, scale or 1.7)
	return m
end

return HandTools
