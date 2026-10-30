--!strict
-- Chatka grzybiarza z bali: ganek z ławką i doniczkami, dwuspadowy dach, komin z dymem, kamienny
-- kominek z gzymsem, lada skupu ze skupywaczem (NPC), kredens ze słoikami, kącik z beczką oleju,
-- stolik z lampką-muchomorem i suszarnia z grzybami. Na Halloween w środku pajęczyny i małe dynie.
-- Front patrzy w stronę lasu (+Z), drzwi na środku.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Palette = require(script.Parent.Palette)
local Props = require(script.Parent.Props)
local Merchant = require(script.Parent.Merchant)

local Cabin = {}

local VERTICAL = CFrame.Angles(0, 0, math.rad(90))
local ALONG_Z = CFrame.Angles(0, math.rad(90), 0) -- oś walca (X) obrócona wzdłuż Z

-- Wymiary (studs)
local HALF_W = 18 -- ściany boczne na x = ±18 (większa chatka: więcej miejsca przy ladzie)
local BACK_Z = -45
local FRONT_Z = -13
local FLOOR_TOP = 1
local LOG_D = 1.6
local LOG_STEP = 1.5
local ROWS = 9
local WALL_TOP = FLOOR_TOP + LOG_D / 2 + (ROWS - 1) * LOG_STEP + LOG_D / 2
local ROOF_ANGLE = math.rad(35)
-- Bale wystają za narożnik (zakładka jak w prawdziwym zrębie): do zewnętrznej krawędzi bala
-- z drugiej ściany i jeszcze kawałek dalej. Wcześniej kończyły się równo z nią i narożniki
-- wyglądały na niedokończone.
local CORNER = LOG_D / 2 + 0.7

local function make(className: string, props: { [string]: any }): BasePart
	local p = Instance.new(className) :: BasePart
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

local function decor(p: BasePart): BasePart
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	return p
end

local function logX(parent: Instance, x1: number, x2: number, y: number, z: number, diameter: number?): BasePart?
	if x2 - x1 < 0.5 then
		return nil
	end
	local d = diameter or LOG_D
	return make("Part", {
		Name = "Log",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(x2 - x1, d, d),
		Position = Vector3.new((x1 + x2) / 2, y, z),
		Color = Palette.log,
		Parent = parent,
	})
end

local function logZ(parent: Instance, z1: number, z2: number, y: number, x: number)
	if z2 - z1 < 0.5 then
		return
	end
	make("Part", {
		Name = "Log",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(z2 - z1, LOG_D, LOG_D),
		CFrame = CFrame.new(x, y, (z1 + z2) / 2) * ALONG_Z,
		Color = Palette.log,
		Parent = parent,
	})
end

-- Dzieli odcinek [a, b] na kawałki z pominięciem otworów (drzwi, okna)
local function segments(a: number, b: number, holes: { { number } }): { { number } }
	local result = {}
	local start = a
	table.sort(holes, function(h1, h2)
		return h1[1] < h2[1]
	end)
	for _, hole in holes do
		if hole[1] > start then
			table.insert(result, { start, math.min(hole[1], b) })
		end
		start = math.max(start, hole[2])
	end
	if start < b then
		table.insert(result, { start, b })
	end
	return result
end

local function rowY(row: number): number
	return FLOOR_TOP + LOG_D / 2 + row * LOG_STEP
end

-- outward: +1 lub -1 zależnie od tego, w którą stronę lokalnej osi Z jest dwór.
-- Z zewnątrz widać ciepłą szybkę, a od środka ciemne nocne niebo z krzyżem ramy
-- (sam neon raził w oczy, gdy gracz stał w chatce).
local function window(parent: Instance, cf: CFrame, width: number, height: number, outward: number)
	decor(make("Part", {
		Name = "WindowGlow",
		Size = Vector3.new(width, height, 0.2),
		CFrame = cf,
		Color = Palette.windowGlow,
		Material = Enum.Material.Neon,
		Parent = parent,
	}))
	local frame = Palette.plankDark
	for _, offset in { -height / 2, height / 2 } do
		decor(make("Part", { Size = Vector3.new(width + 0.6, 0.35, 0.6), CFrame = cf * CFrame.new(0, offset, 0), Color = frame, Parent = parent }))
	end
	decor(make("Part", { Size = Vector3.new(0.25, height, 0.4), CFrame = cf, Color = frame, Parent = parent }))
	decor(make("Part", { Size = Vector3.new(width, 0.25, 0.4), CFrame = cf, Color = frame, Parent = parent }))

	local inside = cf * CFrame.new(0, 0, -outward * 0.45)
	decor(make("Part", {
		Name = "WindowNight",
		Size = Vector3.new(width, height, 0.1),
		CFrame = inside,
		Color = Palette.windowNight,
		Material = Enum.Material.SmoothPlastic,
		Reflectance = 0.15,
		Parent = parent,
	}))
	local crossCf = cf * CFrame.new(0, 0, -outward * 0.55)
	decor(make("Part", { Size = Vector3.new(0.25, height, 0.15), CFrame = crossCf, Color = frame, Parent = parent }))
	decor(make("Part", { Size = Vector3.new(width, 0.25, 0.15), CFrame = crossCf, Color = frame, Parent = parent }))
end

local function buildWalls(m: Model)
	local doorHalf = 3
	local doorRows = 5 -- rzędy 0-4 mają otwór na drzwi
	local frontWindows = { { -14, -8 }, { 8, 14 } }
	local sideWindows = { { -38, -32 }, { -26, -20 } }

	for row = 0, ROWS - 1 do
		local y = rowY(row)
		local windowRow = row >= 2 and row <= 4

		-- Tył
		logX(m, -HALF_W - CORNER, HALF_W + CORNER, y, BACK_Z)

		-- Przód z drzwiami i oknami
		local holes = {}
		if row < doorRows then
			table.insert(holes, { -doorHalf, doorHalf })
		end
		if windowRow then
			for _, w in frontWindows do
				table.insert(holes, w)
			end
		end
		for _, seg in segments(-HALF_W - CORNER, HALF_W + CORNER, holes) do
			logX(m, seg[1], seg[2], y, FRONT_Z)
		end

		-- Boki (przesunięte o pół bala w górę, jak w prawdziwym zrębie)
		local sideY = y + LOG_STEP / 2
		if row < ROWS - 1 then
			for _, x in { -HALF_W, HALF_W } do
				local sideHoles = if windowRow then sideWindows else {}
				for _, seg in segments(BACK_Z - CORNER, FRONT_Z + CORNER, sideHoles) do
					logZ(m, seg[1], seg[2], sideY, x)
				end
			end
		end
	end

	-- Dolny bal ścian bocznych: boki są przesunięte o pół bala w górę, więc bez niego na dole boków
	-- zostawała szpara nad podłogą (bale „nie dochodziły do ziemi”)
	for _, x in { -HALF_W, HALF_W } do
		logZ(m, BACK_Z - CORNER, FRONT_Z + CORNER, rowY(0) - LOG_STEP / 2, x)
	end

	-- Okna: świecące szybki w otworach
	local windowY = rowY(3)
	local windowH = LOG_STEP * 3 - 0.2
	for _, w in frontWindows do
		window(m, CFrame.new((w[1] + w[2]) / 2, windowY, FRONT_Z), w[2] - w[1], windowH, 1)
	end
	for _, x in { -HALF_W, HALF_W } do
		-- Po obrocie ALONG_Z lokalne +Z wskazuje świat +X
		local outward = if x > 0 then 1 else -1
		for _, w in sideWindows do
			window(m, CFrame.new(x, windowY + LOG_STEP / 2, (w[1] + w[2]) / 2) * ALONG_Z, w[2] - w[1], windowH, outward)
		end
	end

	-- Futryna drzwi
	local doorTop = rowY(doorRows) - LOG_D / 2
	for _, side in { -1, 1 } do
		make("Part", {
			Size = Vector3.new(0.6, doorTop - FLOOR_TOP, 1.9),
			Position = Vector3.new(side * (doorHalf - 0.3), (doorTop + FLOOR_TOP) / 2, FRONT_Z),
			Color = Palette.plankDark,
			Parent = m,
		})
	end
	make("Part", {
		Size = Vector3.new(doorHalf * 2 + 0.6, 0.6, 1.9),
		Position = Vector3.new(0, doorTop - 0.1, FRONT_Z),
		Color = Palette.plankDark,
		Parent = m,
	})
end

-- Kamienna podmurówka pod ścianami: od ziemi do poziomu podłogi, z kamieni różnej długości i odcienia.
-- Bale stoją na niej, a nie wiszą nad gołą krawędzią podłogi.
local function buildFoundation(m: Model)
	local height = FLOOR_TOP
	local thick = LOG_D + 0.5
	local function run(a: number, b: number, place: (number, number) -> CFrame, along: string)
		local i = 0
		local pos = a
		while pos < b - 0.01 do
			local len = math.min(2.4 + (i % 3) * 0.7, b - pos)
			local mid = pos + len / 2
			local stoneH = height + (if i % 2 == 0 then 0.06 else -0.04)
			make("Part", {
				Name = "Foundation",
				Size = if along == "x" then Vector3.new(len - 0.06, stoneH, thick) else Vector3.new(thick, stoneH, len - 0.06),
				CFrame = place(mid, stoneH),
				Color = Palette.stone:Lerp(Color3.fromRGB(96, 90, 84), (i % 4) * 0.12),
				Material = Enum.Material.Slate,
				Parent = m,
			})
			pos += len
			i += 1
		end
	end
	local x1, x2 = -HALF_W - CORNER, HALF_W + CORNER
	local z1, z2 = BACK_Z - CORNER, FRONT_Z + CORNER
	for _, z in { BACK_Z, FRONT_Z } do
		run(x1, x2, function(mid, h)
			return CFrame.new(mid, h / 2, z)
		end, "x")
	end
	for _, x in { -HALF_W, HALF_W } do
		run(z1 + thick / 2, z2 - thick / 2, function(mid, h)
			return CFrame.new(x, h / 2, mid)
		end, "z")
	end
end

local function buildRoof(m: Model)
	local overhang = 1.6
	local run = HALF_W + overhang -- poziomo od kalenicy do okapu
	local width = run / math.cos(ROOF_ANGLE)
	local rise = run * math.tan(ROOF_ANGLE)
	local depth = (FRONT_Z - BACK_Z) + 6
	local centerZ = (FRONT_Z + BACK_Z) / 2
	-- Okap leży trochę nad ścianą, żeby dach zachodził na bale
	local eaveY = WALL_TOP - overhang * math.tan(ROOF_ANGLE) + 0.3
	local ridgeY = eaveY + rise

	for _, side in { -1, 1 } do
		make("Part", {
			Name = "Roof",
			Size = Vector3.new(width, 0.9, depth),
			CFrame = CFrame.new(side * run / 2, eaveY + rise / 2, centerZ) * CFrame.Angles(0, 0, -side * ROOF_ANGLE),
			Color = Palette.roof,
			Parent = m,
		})
		-- Ciemniejsza listwa na krawędzi okapu
		decor(make("Part", {
			Size = Vector3.new(0.8, 0.6, depth + 0.2),
			Position = Vector3.new(side * run, eaveY - 0.15, centerZ),
			Color = Palette.roofEdge,
			Parent = m,
		}))
	end
	make("Part", {
		Name = "Ridge",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(depth + 0.4, 1.2, 1.2),
		CFrame = CFrame.new(0, ridgeY + 0.3, centerZ) * ALONG_Z,
		Color = Palette.roofEdge,
		Parent = m,
	})

	-- Deski za balami szczytu: trójkąt aż pod kalenicę, żeby między ostatnim balem a dachem
	-- nie było dziury (bale szczytu kończą się, gdy robią się za krótkie)
	for _, z in { FRONT_Z, BACK_Z } do
		local inward = if z == FRONT_Z then -1 else 1
		for _, side in { -1, 1 } do
			-- Klin: pełna wysokość przy kalenicy (x = 0), zero przy ścianie bocznej.
			-- WedgePart bez obrotu ma pełną wysokość z tyłu (+Z), więc obracamy go +Z do środka.
			make("WedgePart", {
				Name = "GableBoard",
				Size = Vector3.new(0.4, ridgeY - WALL_TOP + 0.4, HALF_W),
				CFrame = CFrame.new(side * HALF_W / 2, (WALL_TOP + ridgeY + 0.4) / 2 - 0.2, z + inward * 0.35)
					* CFrame.Angles(0, if side > 0 then -math.pi / 2 else math.pi / 2, 0), -- wysoki bok klina (+Z) do kalenicy
				Color = Palette.plankDark,
				Parent = m,
			})
		end
	end

	-- Szczyty z coraz krótszych bali (z przodu i z tyłu)
	local y = WALL_TOP + LOG_D / 2 - 0.2
	while y < ridgeY - 0.6 do
		local half = HALF_W - (y - WALL_TOP) / math.tan(ROOF_ANGLE)
		if half < 0.8 then
			break
		end
		logX(m, -half, half, y, FRONT_Z)
		logX(m, -half, half, y, BACK_Z)
		y += LOG_STEP
	end
end

local function buildChimney(m: Model)
	local x, z = HALF_W - 4, BACK_Z - 1.6
	local top = WALL_TOP + 11
	local y = 0
	local i = 0
	while y < top do
		local h = 1.6
		make("Part", {
			Name = "ChimneyStone",
			Size = Vector3.new(3.2 + (i % 2) * 0.3, h, 2.6 + ((i + 1) % 2) * 0.3),
			Position = Vector3.new(x, y + h / 2, z),
			Color = Palette.stoneChimney:Lerp(Color3.new(0.3, 0.3, 0.3), (i % 3) * 0.12),
			Parent = m,
		})
		y += h
		i += 1
	end
	local cap = make("Part", {
		Size = Vector3.new(3.8, 0.6, 3.2),
		Position = Vector3.new(x, top + 0.3, z),
		Color = Color3.fromRGB(70, 66, 62),
		Parent = m,
	})
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(150, 150, 160))
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.5),
		NumberSequenceKeypoint.new(1, 6),
	})
	smoke.Lifetime = NumberRange.new(4, 6)
	smoke.Rate = 3
	smoke.Speed = NumberRange.new(2, 3)
	smoke.SpreadAngle = Vector2.new(12, 12)
	smoke.Acceleration = Vector3.new(0.6, 0.4, 0)
	smoke.RotSpeed = NumberRange.new(-20, 20)
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.Parent = cap
end

local function buildPorch(m: Model)
	local deckDepth = 6
	local deckZ = FRONT_Z + deckDepth / 2 + 0.6
	make("Part", {
		Name = "Deck",
		Size = Vector3.new(HALF_W * 2 + 2, 0.8, deckDepth),
		Position = Vector3.new(0, 0.6, deckZ),
		Color = Palette.plank,
		Parent = m,
	})
	-- Deski pokładu (ciemniejsze szczeliny)
	for x = -HALF_W, HALF_W, 2.4 do
		decor(make("Part", {
			Size = Vector3.new(0.12, 0.05, deckDepth - 0.2),
			Position = Vector3.new(x, 1.02, deckZ),
			Color = Palette.plankDark,
			Parent = m,
		}))
	end
	make("Part", {
		Name = "Step",
		Size = Vector3.new(6, 0.4, 1.6),
		Position = Vector3.new(0, 0.2, FRONT_Z + deckDepth + 1.4),
		Color = Palette.plankDark,
		Parent = m,
	})
	local postZ = FRONT_Z + deckDepth
	local roofY = WALL_TOP - 1.2
	for _, x in { -HALF_W, HALF_W } do
		make("Part", {
			Name = "PorchPost",
			Size = Vector3.new(0.8, roofY - 1, 0.8),
			Position = Vector3.new(x, (roofY + 1) / 2, postZ),
			Color = Palette.log,
			Parent = m,
		})
		Props.hangingLantern(m, Vector3.new(x * 0.82, roofY - 0.6, postZ - 0.4), 22)
	end
	-- Daszek ganku opadający w stronę lasu
	make("Part", {
		Name = "PorchRoof",
		Size = Vector3.new(HALF_W * 2 + 3, 0.6, deckDepth + 2.4),
		CFrame = CFrame.new(0, roofY + 0.9, FRONT_Z + deckDepth / 2 + 0.6) * CFrame.Angles(math.rad(12), 0, 0),
		Color = Palette.roof,
		Parent = m,
	})
	-- Szyld nad drzwiami, napis od strony lasu
	Props.signBoard(m, CFrame.new(0, rowY(6) + 0.3, FRONT_Z + 1.05), Vector3.new(11, 2.2, 0.3), "ZONE_CABIN", Enum.NormalId.Back)
end

-- ===== Wystrój wnętrza =====
-- Meble przy ścianach trzymają się co najmniej 0,2 studa od bali (lico ścian od środka:
-- x = ±17,2, tył z = -44,2, przód z = -13,8). Płaskie ściany mebli nie migoczą wtedy na balach,
-- a bale nigdzie nie giną za meblami. Żadna ozdoba nie nazywa się „Log” (po balach o tej nazwie
-- scenka kradzieży mierzy ściany chatki).
local WALL_IN = HALF_W - LOG_D / 2
local BACK_IN = BACK_Z + LOG_D / 2
local FRONT_IN = FRONT_Z - LOG_D / 2
local GAP = 0.2

local OAK = Color3.fromRGB(108, 72, 44)
local OAK_DARK = Color3.fromRGB(80, 53, 34)
local IRON = Color3.fromRGB(46, 44, 46)
local BRASS = Color3.fromRGB(214, 168, 72)
local OIL = Color3.fromRGB(255, 176, 60)
local SOOT = Color3.fromRGB(28, 22, 20)
local MORTAR = Color3.fromRGB(62, 57, 54)
local STONES = {
	Palette.stoneChimney,
	Color3.fromRGB(128, 120, 110),
	Color3.fromRGB(94, 90, 86),
	Color3.fromRGB(116, 104, 92),
}
local WICKER = Color3.fromRGB(176, 128, 70)
local PORCINI = { Color3.fromRGB(140, 84, 44), Color3.fromRGB(160, 102, 54), Color3.fromRGB(122, 74, 40) }
local CHANTERELLE = { Color3.fromRGB(240, 172, 52), Color3.fromRGB(228, 150, 40), Color3.fromRGB(250, 190, 70) }
local DRIED = { Color3.fromRGB(150, 110, 70), Color3.fromRGB(128, 92, 58), Color3.fromRGB(166, 128, 86), Color3.fromRGB(112, 80, 50) }

-- Kominek, stolik i gzyms (też dla dyń na Halloween)
local FIRE_X = HALF_W - 4.5
local FIRE_FACE = BACK_Z + 2.5 -- przód kamiennych filarów
local MANTEL_TOP = FLOOR_TOP + 5.75
local MANTEL_ITEMS_Z = FIRE_FACE + 0.2 -- rząd rzeczy na gzymsie (przed okapem kominowym)
local TABLE_AT = Vector3.new(8, FLOOR_TOP, -24)

-- Ozdoba: bez kolizji, dotyku, celowania i cienia (nie przeszkadza w chodzeniu ani kamerze)
local function prop(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	decor(p)
	p.Parent = parent
	return p
end

-- Mebel z kolizją (nie da się przez niego przejść)
local function solid(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): BasePart
	local p = prop(parent, name, size, cf, color, material, shape)
	p.CanCollide = true
	p.CanQuery = true
	p.CastShadow = true
	return p
end

-- Niewidzialna bryła zamiast kolizji wielu drobnych części (kamera przez nią przechodzi)
local function blocker(parent: Instance, name: string, size: Vector3, cf: CFrame)
	local p = prop(parent, name, size, cf, Color3.new(0, 0, 0))
	p.Transparency = 1
	p.CanCollide = true
end

local function ellipsoid(p: BasePart): BasePart
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- Rząd kamieni na zaprawie (przód i boki bryły od x1 do x2): kamienie wystają o kilka setnych
-- na przemian, a szpary między nimi pokazują ciemniejszą zaprawę
local function stoneRow(m: Model, x1: number, x2: number, y1: number, y2: number, zBack: number, zFront: number, widths: { number }, shade: number)
	local total = 0
	for _, w in widths do
		total += w
	end
	local span = x2 - x1 + 0.12
	local x = x1 - 0.06
	for i, w in widths do
		local width = w / total * span
		local jut = if (i + shade) % 2 == 0 then 0.05 else 0.09
		prop(
			m,
			"FireplaceStone",
			Vector3.new(width - 0.07, y2 - y1 - 0.07, zFront - zBack + jut),
			CFrame.new(x + width / 2, (y1 + y2) / 2, (zBack + zFront + jut) / 2),
			STONES[(i + shade) % #STONES + 1]
		)
		x += width
	end
end

-- Wiklinowy koszyk z pałąkiem, pełen grzybowych kapeluszy. base = środek dna.
local function basket(m: Model, base: Vector3, colors: { Color3 }, yaw: number)
	local cf = CFrame.new(base) * CFrame.Angles(0, yaw, 0)
	prop(m, "Basket", Vector3.new(0.7, 1.5, 1.5), cf * CFrame.new(0, 0.35, 0) * VERTICAL, WICKER, nil, Enum.PartType.Cylinder)
	prop(m, "BasketRim", Vector3.new(0.14, 1.6, 1.6), cf * CFrame.new(0, 0.66, 0) * VERTICAL, Color3.fromRGB(146, 100, 52), nil, Enum.PartType.Cylinder)
	local last: Vector3? = nil
	for k = 0, 6 do
		local angle = math.rad(180 - k * 30)
		local p = (cf * CFrame.new(math.cos(angle) * 0.72, 0.7 + math.sin(angle) * 0.75, 0)).Position
		if last then
			prop(m, "BasketHandle", Vector3.new(0.1, 0.1, (p - last).Magnitude + 0.04), CFrame.lookAt((last + p) / 2, p), Color3.fromRGB(146, 100, 52))
		end
		last = p
	end
	for k = 0, 4 do
		local offset = if k == 0 then Vector3.new(0, 0.82, 0) else Vector3.new(math.cos(k * 1.57 + 0.6) * 0.4, 0.76, math.sin(k * 1.57 + 0.6) * 0.4)
		ellipsoid(prop(m, "BasketCap", Vector3.new(0.62, 0.36, 0.62), cf * CFrame.new(offset) * CFrame.Angles(math.rad(k * 7), 0, math.rad(-k * 5)), colors[k % #colors + 1]))
	end
end

-- Kamienny kominek w prawym tylnym rogu: filary i nadproże z kamieni, okap kominowy aż pod
-- sufit z obrazkiem borowika, gruby gzyms na wspornikach, kamienne palenisko przed nim i ogień
-- na polanach ułożonych na żelaznych kozłach. Obok stos polan.
local function buildFireplace(m: Model)
	local fx = FIRE_X
	local back = BACK_Z - 0.6 -- tył chowa się w balach tylnej ściany
	local face = FIRE_FACE
	local firebox = BACK_IN + GAP -- tylna ścianka paleniska
	local openHalf = 1.6
	local pillarW = 1.55
	local outer = openHalf + pillarW
	local openTop = FLOOR_TOP + 3.3
	local mantelY = MANTEL_TOP - 0.55 -- spód gzymsu

	-- Filary i nadproże: rdzeń z zaprawy, na nim kamienie
	for side = -1, 1, 2 do
		local x1 = if side < 0 then fx - outer else fx + openHalf
		local x2 = x1 + pillarW
		solid(m, "Fireplace", Vector3.new(pillarW, mantelY - FLOOR_TOP, face - back), CFrame.new((x1 + x2) / 2, (FLOOR_TOP + mantelY) / 2, (back + face) / 2), MORTAR)
		local y = FLOOR_TOP
		for i, h in { 1.15, 0.95, 1.2, 1.0, 0.9 } do
			stoneRow(m, x1, x2, y, y + h, back, face, if i % 2 == 0 then { 0.55, 0.45 } else { 1 }, i + side)
			y += h
		end
	end
	solid(m, "Fireplace", Vector3.new(openHalf * 2, mantelY - openTop, face - back), CFrame.new(fx, (openTop + mantelY) / 2, (back + face) / 2), MORTAR)
	stoneRow(m, fx - openHalf + 0.12, fx + openHalf - 0.12, openTop, mantelY, back, face, { 1, 0.8, 1 }, 2)
	-- Ścięte górne rogi otworu (łuk)
	for side = -1, 1, 2 do
		prop(m, "FireplaceStone", Vector3.new(0.75, 0.75, face - back + 0.02), CFrame.new(fx + side * openHalf, openTop, (back + face + 0.02) / 2) * CFrame.Angles(0, 0, math.rad(45)), STONES[3])
	end
	-- Wnętrze paleniska: okopcona tylna ścianka i dno; niewidzialna bryła w otworze (nie wchodzi się w ogień)
	solid(m, "FireboxBack", Vector3.new(openHalf * 2, openTop - FLOOR_TOP, firebox - back), CFrame.new(fx, (FLOOR_TOP + openTop) / 2, (back + firebox) / 2), SOOT)
	local fz = (firebox + face) / 2
	prop(m, "FireboxFloor", Vector3.new(openHalf * 2, 0.08, face - firebox), CFrame.new(fx, FLOOR_TOP + 0.04, fz), SOOT)
	blocker(m, "FireboxBlocker", Vector3.new(openHalf * 2, openTop - FLOOR_TOP, face - firebox), CFrame.new(fx, (FLOOR_TOP + openTop) / 2, fz))
	-- Palenisko przed kominkiem
	solid(m, "Hearth", Vector3.new(outer * 2 + 0.6, 0.22, 1.8), CFrame.new(fx, FLOOR_TOP + 0.11, face + 0.9), STONES[2])

	-- Żelazne kozły i polana
	for _, dx in { -0.85, 0.85 } do
		prop(m, "Andiron", Vector3.new(0.18, 0.18, face - firebox - 0.2), CFrame.new(fx + dx, FLOOR_TOP + 0.22, fz), IRON, Enum.Material.Metal)
		prop(m, "Andiron", Vector3.new(0.18, 0.7, 0.18), CFrame.new(fx + dx, FLOOR_TOP + 0.43, face - 0.2), IRON, Enum.Material.Metal)
		prop(m, "Andiron", Vector3.new(0.3, 0.3, 0.3), CFrame.new(fx + dx, FLOOR_TOP + 0.86, face - 0.2), IRON, Enum.Material.Metal, Enum.PartType.Ball)
	end
	prop(m, "Embers", Vector3.new(2.3, 0.12, face - firebox - 0.4), CFrame.new(fx, FLOOR_TOP + 0.14, fz), Color3.fromRGB(255, 110, 40), Enum.Material.Neon)
	local wood = Color3.fromRGB(92, 60, 40)
	prop(m, "FireLog", Vector3.new(2.5, 0.5, 0.5), CFrame.new(fx, FLOOR_TOP + 0.56, fz - 0.3) * CFrame.Angles(0, math.rad(4), 0), wood, nil, Enum.PartType.Cylinder)
	prop(m, "FireLog", Vector3.new(2.3, 0.46, 0.46), CFrame.new(fx + 0.05, FLOOR_TOP + 0.54, fz + 0.25) * CFrame.Angles(0, math.rad(-5), 0), wood:Lerp(Color3.new(0, 0, 0), 0.15), nil, Enum.PartType.Cylinder)
	prop(m, "FireLog", Vector3.new(2.1, 0.42, 0.42), CFrame.new(fx - 0.1, FLOOR_TOP + 0.95, fz) * CFrame.Angles(0, math.rad(10), math.rad(6)), wood:Lerp(Color3.new(0, 0, 0), 0.3), nil, Enum.PartType.Cylinder)
	local core = prop(m, "FireCore", Vector3.new(2, 0.2, 0.8), CFrame.new(fx, FLOOR_TOP + 0.8, fz), Color3.fromRGB(255, 150, 60))
	core.Transparency = 1
	local flames = Instance.new("ParticleEmitter")
	flames.Name = "Flames"
	flames.Texture = "rbxasset://textures/particles/fire_main.dds"
	flames.Color = ColorSequence.new(Color3.fromRGB(255, 190, 90), Color3.fromRGB(255, 80, 30))
	flames.LightEmission = 1
	flames.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.15), NumberSequenceKeypoint.new(1, 0.2) })
	flames.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	flames.Lifetime = NumberRange.new(0.5, 0.9)
	flames.Rate = 22
	flames.Speed = NumberRange.new(1.3, 2.2)
	flames.SpreadAngle = Vector2.new(12, 12)
	flames.EmissionDirection = Enum.NormalId.Top
	flames.Parent = core
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Sparks"
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 210, 110), Color3.fromRGB(255, 120, 40))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.1)
	sparks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	sparks.Lifetime = NumberRange.new(0.7, 1.3)
	sparks.Rate = 3
	sparks.Speed = NumberRange.new(1.8, 3)
	sparks.SpreadAngle = Vector2.new(25, 25)
	sparks.Acceleration = Vector3.new(0, -1.5, 0)
	sparks.EmissionDirection = Enum.NormalId.Top
	sparks.Parent = core
	local fireLight = Instance.new("PointLight")
	fireLight.Color = Color3.fromRGB(255, 140, 60)
	fireLight.Range = 16
	fireLight.Brightness = 1.1
	fireLight.Parent = core

	-- Gruby gzyms na dwóch wspornikach (prawy koniec 0,2 przed ścianą)
	local mantelX1, mantelX2 = fx - outer - 0.55, WALL_IN - GAP
	solid(m, "Mantel", Vector3.new(mantelX2 - mantelX1, MANTEL_TOP - mantelY, face + 0.6 - (back + 1)), CFrame.new((mantelX1 + mantelX2) / 2, (mantelY + MANTEL_TOP) / 2, (back + 1 + face + 0.6) / 2), Palette.plankDark)
	for side = -1, 1, 2 do
		prop(m, "MantelBracket", Vector3.new(0.45, 0.75, 0.6), CFrame.new(fx + side * (outer - 0.45), mantelY - 0.375, face + 0.3), Palette.plankDark)
	end

	-- Okap kominowy aż pod sufit
	local breastHalf = 2.35
	local breastFront = face - 0.6
	solid(m, "Fireplace", Vector3.new(breastHalf * 2, WALL_TOP - MANTEL_TOP, breastFront - back), CFrame.new(fx, (MANTEL_TOP + WALL_TOP) / 2, (back + breastFront) / 2), MORTAR)
	local y = MANTEL_TOP
	for i, h in { 1.1, 1.2, 1.05, 1.15, 1.1, 1.2, 1.05 } do
		local top = math.min(y + h, WALL_TOP)
		stoneRow(m, fx - breastHalf, fx + breastHalf, y, top, back, breastFront, if i % 2 == 0 then { 1.4, 1.9, 1.4 } else { 2.3, 2.4 }, i)
		y = top
	end
	-- Obrazek w ramie: borowik pod księżycem
	local frame = CFrame.new(fx, FLOOR_TOP + 8.8, breastFront + 0.09 + 0.08)
	prop(m, "PictureFrame", Vector3.new(2.8, 2, 0.14), frame, Palette.plankDark)
	prop(m, "PictureCanvas", Vector3.new(2.4, 1.6, 0.05), frame * CFrame.new(0, 0, 0.08), Color3.fromRGB(38, 62, 58))
	prop(m, "PictureGrass", Vector3.new(2.4, 0.3, 0.04), frame * CFrame.new(0, -0.65, 0.12), Color3.fromRGB(56, 92, 52))
	prop(m, "PictureStem", Vector3.new(0.4, 0.62, 0.04), frame * CFrame.new(0, -0.3, 0.15), Color3.fromRGB(236, 222, 192))
	ellipsoid(prop(m, "PictureCap", Vector3.new(1.3, 0.62, 0.04), frame * CFrame.new(0, 0.08, 0.18), Color3.fromRGB(138, 86, 46)))
	ellipsoid(prop(m, "PictureMoon", Vector3.new(0.36, 0.36, 0.04), frame * CFrame.new(0.82, 0.5, 0.12), Color3.fromRGB(250, 232, 170)))

	-- Na gzymsie: dwie świeczki i złoty grzyb-trofeum
	for _, dx in { -2.75, 2.75 } do
		prop(m, "Candle", Vector3.new(0.9, 0.35, 0.35), CFrame.new(fx + dx, MANTEL_TOP + 0.45, MANTEL_ITEMS_Z) * VERTICAL, Color3.fromRGB(246, 236, 210), nil, Enum.PartType.Cylinder)
		prop(m, "CandleFlame", Vector3.new(0.25, 0.25, 0.25), CFrame.new(fx + dx, MANTEL_TOP + 1.05, MANTEL_ITEMS_Z), Color3.fromRGB(255, 190, 80), Enum.Material.Neon, Enum.PartType.Ball)
	end
	prop(m, "TrophyBase", Vector3.new(0.8, 0.5, 0.5), CFrame.new(fx, MANTEL_TOP + 0.4, MANTEL_ITEMS_Z) * VERTICAL, Color3.fromRGB(240, 200, 90), Enum.Material.Metal, Enum.PartType.Cylinder)
	ellipsoid(prop(m, "Trophy", Vector3.new(1.25, 0.8, 1.25), CFrame.new(fx, MANTEL_TOP + 1.1, MANTEL_ITEMS_Z), Color3.fromRGB(255, 205, 60), Enum.Material.Metal))

	-- Stos polan po lewej od kominka, czołami do pokoju
	local wx, wz = fx - outer - 1.7, firebox + 0.9
	for row, xs in { { -0.6, 0, 0.6 }, { -0.3, 0.3 }, { 0 } } do
		for _, dx in xs do
			local center = Vector3.new(wx + dx, FLOOR_TOP + 0.3 + (row - 1) * 0.52, wz)
			prop(m, "Firewood", Vector3.new(1.8, 0.58, 0.58), CFrame.new(center) * ALONG_Z, Palette.log, nil, Enum.PartType.Cylinder)
			prop(m, "FirewoodEnd", Vector3.new(0.04, 0.48, 0.48), CFrame.new(center + Vector3.new(0, 0, 0.91)) * ALONG_Z, Palette.logEnd, nil, Enum.PartType.Cylinder)
		end
	end
	blocker(m, "FirewoodBlocker", Vector3.new(1.9, 1.6, 1.9), CFrame.new(wx, FLOOR_TOP + 0.8, wz))
end

-- Kącik z olejem do latarni (stanowisko „oil” przy drzwiach): dębowa beczka na kozłach dnem do
-- lewej ściany, mosiężny kranik nad wiaderkiem ze świecącym olejem, w rogu stojąca baryłka
-- z butelkami oleju, przy ścianie dwa kanistry. Środek kręgu stanowiska zostaje wolny.
local function buildOilCorner(m: Model)
	local station = Economy.station("oil", "forest")
	local wall = -WALL_IN + GAP
	local z = station.z
	local length, diameter = 2.4, 2
	local x2 = wall + length -- przód beczki z kranikiem
	local axisY = FLOOR_TOP + 0.45 + diameter / 2
	local axis = CFrame.new(wall + length / 2, axisY, z)
	solid(m, "OilBarrel", Vector3.new(length, diameter, diameter), axis, OAK, nil, Enum.PartType.Cylinder)
	prop(m, "OilBarrelBelly", Vector3.new(1.3, diameter + 0.12, diameter + 0.12), axis, OAK, nil, Enum.PartType.Cylinder)
	for _, dx in { -0.95, -0.45, 0.45, 0.95 } do
		local d = if math.abs(dx) > 0.7 then diameter + 0.06 else diameter + 0.18
		prop(m, "OilHoop", Vector3.new(0.13, d, d), axis * CFrame.new(dx, 0, 0), IRON, Enum.Material.Metal, Enum.PartType.Cylinder)
	end
	prop(m, "OilBarrelHead", Vector3.new(0.05, diameter - 0.25, diameter - 0.25), CFrame.new(x2 + 0.02, axisY, z), OAK_DARK, nil, Enum.PartType.Cylinder)
	for _, dz in { -0.4, 0.4 } do
		prop(m, "OilBarrelStave", Vector3.new(0.04, diameter - 0.45, 0.05), CFrame.new(x2 + 0.05, axisY, z + dz), OAK)
	end
	for _, dx in { 0.55, length - 0.55 } do
		solid(m, "OilCradle", Vector3.new(0.4, 0.62, diameter * 0.9), CFrame.new(wall + dx, FLOOR_TOP + 0.31, z), OAK_DARK)
	end
	-- Kranik i kropla nad wiaderkiem
	local tapY = axisY - 0.35
	prop(m, "OilTap", Vector3.new(0.45, 0.22, 0.22), CFrame.new(x2 + 0.22, tapY, z), BRASS, Enum.Material.Metal, Enum.PartType.Cylinder)
	prop(m, "OilTap", Vector3.new(0.16, 0.32, 0.16), CFrame.new(x2 + 0.4, tapY - 0.2, z), BRASS, Enum.Material.Metal)
	prop(m, "OilTap", Vector3.new(0.08, 0.3, 0.1), CFrame.new(x2 + 0.26, tapY + 0.24, z), BRASS, Enum.Material.Metal)
	prop(m, "OilTap", Vector3.new(0.3, 0.08, 0.1), CFrame.new(x2 + 0.26, tapY + 0.41, z), BRASS, Enum.Material.Metal)
	ellipsoid(prop(m, "OilDrop", Vector3.new(0.1, 0.15, 0.1), CFrame.new(x2 + 0.4, tapY - 0.43, z), OIL, Enum.Material.Neon))
	local bucket = Vector3.new(x2 + 0.4, FLOOR_TOP, z)
	prop(m, "OilBucket", Vector3.new(0.6, 0.8, 0.8), CFrame.new(bucket + Vector3.new(0, 0.3, 0)) * VERTICAL, OAK, nil, Enum.PartType.Cylinder)
	prop(m, "OilBucketBand", Vector3.new(0.08, 0.84, 0.84), CFrame.new(bucket + Vector3.new(0, 0.45, 0)) * VERTICAL, IRON, Enum.Material.Metal, Enum.PartType.Cylinder)
	local oil = prop(m, "OilSurface", Vector3.new(0.04, 0.68, 0.68), CFrame.new(bucket + Vector3.new(0, 0.62, 0)) * VERTICAL, OIL, Enum.Material.Neon, Enum.PartType.Cylinder)
	local glow = Instance.new("PointLight")
	glow.Color = OIL
	glow.Range = 8
	glow.Brightness = 0.55
	glow.Parent = oil

	-- Stojąca baryłka w rogu przy drzwiach, na niej butelki z olejem
	local keg = Vector3.new(wall + 0.85, FLOOR_TOP, FRONT_IN - GAP - 0.85)
	solid(m, "OilKeg", Vector3.new(1.9, 1.6, 1.6), CFrame.new(keg + Vector3.new(0, 0.95, 0)) * VERTICAL, OAK, nil, Enum.PartType.Cylinder)
	for _, dy in { 0.4, 1.5 } do
		prop(m, "OilHoop", Vector3.new(0.12, 1.66, 1.66), CFrame.new(keg + Vector3.new(0, dy, 0)) * VERTICAL, IRON, Enum.Material.Metal, Enum.PartType.Cylinder)
	end
	prop(m, "OilKegLid", Vector3.new(0.05, 1.4, 1.4), CFrame.new(keg + Vector3.new(0, 1.92, 0)) * VERTICAL, OAK_DARK, nil, Enum.PartType.Cylinder)
	for i, offset in { Vector3.new(-0.3, 0, 0.25), Vector3.new(0.32, 0, -0.2) } do
		local base = keg + offset + Vector3.new(0, 1.95, 0)
		local h = if i == 1 then 0.62 else 0.5
		prop(m, "OilBottle", Vector3.new(h, 0.34, 0.34), CFrame.new(base + Vector3.new(0, h / 2, 0)) * VERTICAL, OIL, Enum.Material.Glass, Enum.PartType.Cylinder).Transparency = 0.35
		prop(m, "OilBottleGlow", Vector3.new(h * 0.7, 0.2, 0.2), CFrame.new(base + Vector3.new(0, h * 0.4, 0)) * VERTICAL, OIL, Enum.Material.Neon, Enum.PartType.Cylinder)
		prop(m, "OilBottleNeck", Vector3.new(0.22, 0.14, 0.14), CFrame.new(base + Vector3.new(0, h + 0.11, 0)) * VERTICAL, OIL, Enum.Material.Glass, Enum.PartType.Cylinder).Transparency = 0.35
		prop(m, "OilBottleCork", Vector3.new(0.1, 0.16, 0.16), CFrame.new(base + Vector3.new(0, h + 0.26, 0)) * VERTICAL, Color3.fromRGB(150, 110, 70), nil, Enum.PartType.Cylinder)
	end
	-- Dwa kanistry przy ścianie za beczką
	for i, at in { Vector3.new(wall + 0.45, FLOOR_TOP, z - 1.75), Vector3.new(wall + 1.2, FLOOR_TOP, z - 2) } do
		local can = CFrame.new(at) * CFrame.Angles(0, math.rad(i * 14 - 20), 0)
		prop(m, "OilCan", Vector3.new(0.6, 0.95, 0.85), can * CFrame.new(0, 0.475, 0), Color3.fromRGB(150, 52, 40), Enum.Material.Metal)
		prop(m, "OilCanCap", Vector3.new(0.12, 0.2, 0.2), can * CFrame.new(0.12, 1.01, -0.22) * VERTICAL, BRASS, Enum.Material.Metal, Enum.PartType.Cylinder)
		prop(m, "OilCanHandle", Vector3.new(0.1, 0.12, 0.42), can * CFrame.new(-0.08, 1.01, 0.12), IRON, Enum.Material.Metal)
	end
end

-- Suszarnia przy prawej ścianie: dwa słupki w pełnej ścianie (nie przed oknami), belka, trzy
-- zwisające sznurki z nawleczonymi plasterkami suszonych grzybów i pęczki ziół na słupkach.
-- Pod spodem ława z koszykami świeżych grzybów.
local function buildDryingRack(m: Model)
	local x = WALL_IN - GAP - 0.45
	local z1, z2 = BACK_Z + 6.4, FRONT_Z - 6.6 -- okna prawej ściany: z -38..-32 i -26..-20
	local top = FLOOR_TOP + 7.6
	local rope = Color3.fromRGB(214, 200, 170)
	for _, z in { z1, z2 } do
		solid(m, "RackPost", Vector3.new(0.4, top - FLOOR_TOP, 0.4), CFrame.new(x, (FLOOR_TOP + top) / 2, z), Palette.plankDark)
		prop(m, "RackFoot", Vector3.new(0.5, 0.3, 1.3), CFrame.new(x, FLOOR_TOP + 0.15, z), Palette.plankDark)
		-- Pęczek ziół na gwoździu, od strony pokoju
		local hook = Vector3.new(x - 0.6, top - 0.35, z)
		prop(m, "HerbNail", Vector3.new(0.4, 0.06, 0.06), CFrame.new(hook + Vector3.new(0.2, 0, 0)), IRON, Enum.Material.Metal)
		prop(m, "HerbString", Vector3.new(0.04, 0.4, 0.04), CFrame.new(hook - Vector3.new(0, 0.2, 0)), rope)
		prop(m, "HerbStems", Vector3.new(0.6, 0.18, 0.18), CFrame.new(hook - Vector3.new(0, 0.6, 0)) * VERTICAL, Color3.fromRGB(110, 92, 56), nil, Enum.PartType.Cylinder)
		-- Listki rozchodzą się wachlarzem w dół od miejsca związania
		for k = 0, 5 do
			local leaf = CFrame.new(hook - Vector3.new(0, 0.85, 0)) * CFrame.Angles(0, k * math.pi / 3 + z, 0) * CFrame.Angles(math.rad(14 + (k % 2) * 9), 0, 0) * CFrame.new(0, -0.45, 0)
			prop(m, "HerbLeaf", Vector3.new(0.16, 0.95, 0.05), leaf, if k % 2 == 0 then Color3.fromRGB(86, 112, 58) else Color3.fromRGB(112, 124, 66))
		end
	end
	prop(m, "RackBeam", Vector3.new(0.36, 0.36, z2 - z1 + 0.7), CFrame.new(x, top + 0.18, (z1 + z2) / 2), Palette.plank)
	for row, h in { top - 0.6, top - 1.75, top - 2.9 } do
		local sag = 0.75
		local a = Vector3.new(x - 0.25, h, z1 + 0.25)
		local b = Vector3.new(x - 0.25, h, z2 - 0.25)
		local function at(t: number): Vector3
			return a:Lerp(b, t) - Vector3.new(0, math.sin(t * math.pi) * sag, 0)
		end
		local last = a
		for i = 1, 10 do
			local p = at(i / 10)
			prop(m, "RackCord", Vector3.new(0.05, 0.05, (p - last).Magnitude), CFrame.lookAt((last + p) / 2, p), rope)
			last = p
		end
		local count = 16
		for i = 1, count do
			local t = math.clamp((i - 0.5 + (row % 2) * 0.4) / count, 0.03, 0.97)
			local p = at(t)
			local d = 0.42 + ((i * 7 + row * 3) % 5) * 0.05
			local tilt = math.rad(((i * 13 + row * 5) % 21) - 10)
			prop(m, "DriedSlice", Vector3.new(0.12, d, d), CFrame.lookAt(p, at(math.min(t + 0.01, 1))) * CFrame.Angles(0, math.pi / 2 + tilt, 0), DRIED[(i + row) % #DRIED + 1], nil, Enum.PartType.Cylinder)
		end
	end

	-- Ława pod suszarnią
	local bx = WALL_IN - GAP - 0.7
	local bz1, bz2 = -34.2, -23.6
	local seatY = FLOOR_TOP + 1.5
	solid(m, "RackBench", Vector3.new(1.4, 0.26, bz2 - bz1), CFrame.new(bx, seatY - 0.13, (bz1 + bz2) / 2), Palette.plank)
	for _, z in { bz1 + 0.5, bz2 - 0.5 } do
		solid(m, "RackBenchLeg", Vector3.new(1.2, seatY - 0.26 - FLOOR_TOP, 0.3), CFrame.new(bx, (FLOOR_TOP + seatY - 0.26) / 2, z), Palette.plankDark)
	end
	prop(m, "RackBenchRail", Vector3.new(0.2, 0.2, bz2 - bz1 - 1.2), CFrame.new(bx, FLOOR_TOP + 0.45, (bz1 + bz2) / 2), Palette.plankDark)
	basket(m, Vector3.new(bx - 0.05, seatY, -32.4), PORCINI, 0.3)
	basket(m, Vector3.new(bx - 0.05, seatY, -28.9), CHANTERELLE, -0.4)
	basket(m, Vector3.new(bx - 0.05, seatY, -25.4), { PORCINI[1], CHANTERELLE[1], Palette.autumn[3] }, 1.2)
end

local function buildInterior(m: Model)
	local counterZ = BACK_Z + 3.4
	local midZ = (FRONT_Z + BACK_Z) / 2
	-- Podłoga z desek, szersza niż ściany, żeby pod balami nie było szpary
	make("Part", {
		Name = "Floor",
		Size = Vector3.new(HALF_W * 2 + 2, 1, FRONT_Z - BACK_Z + 2),
		Position = Vector3.new(0, FLOOR_TOP - 0.5, midZ),
		Color = Palette.plank,
		Parent = m,
	})
	-- Szczeliny między deskami podłogi
	for x = -HALF_W + 2, HALF_W - 2, 3 do
		decor(make("Part", {
			Size = Vector3.new(0.1, 0.04, FRONT_Z - BACK_Z - 1),
			Position = Vector3.new(x, FLOOR_TOP + 0.02, midZ),
			Color = Palette.plankDark,
			Parent = m,
		}))
	end
	-- Chodnik od drzwi do lady i duży okrągły dywan na środku
	decor(make("Part", {
		Name = "Runner",
		Size = Vector3.new(4, 0.06, FRONT_Z - counterZ - 4),
		Position = Vector3.new(0, FLOOR_TOP + 0.03, (FRONT_Z + counterZ) / 2 + 1),
		Color = Color3.fromRGB(150, 54, 44),
		Parent = m,
	}))
	for _, edge in { -1.8, 1.8 } do
		decor(make("Part", {
			Size = Vector3.new(0.3, 0.07, FRONT_Z - counterZ - 4),
			Position = Vector3.new(edge, FLOOR_TOP + 0.035, (FRONT_Z + counterZ) / 2 + 1),
			Color = Color3.fromRGB(232, 190, 92),
			Parent = m,
		}))
	end
	for i, d in { 11, 9.6, 8 } do
		decor(make("Part", {
			Name = "Rug",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.05 + i * 0.01, d, d),
			CFrame = CFrame.new(0, FLOOR_TOP + 0.02 + i * 0.01, midZ - 1) * VERTICAL,
			Color = ({ Color3.fromRGB(120, 70, 44), Color3.fromRGB(196, 132, 60), Color3.fromRGB(150, 54, 44) })[i],
			Parent = m,
		}))
	end

	-- Lada skupu grzybów na środku tylnej ściany, z frontem z desek i daszkiem-muchomorem
	local counterW = 14
	make("Part", { Name = "Counter", Size = Vector3.new(counterW, 3, 2.6), Position = Vector3.new(0, FLOOR_TOP + 1.5, counterZ), Color = Palette.plankDark, Parent = m })
	make("Part", { Size = Vector3.new(counterW + 0.6, 0.4, 3), Position = Vector3.new(0, FLOOR_TOP + 3.2, counterZ), Color = Palette.plank, Parent = m })
	for x = -counterW / 2 + 1, counterW / 2 - 1, 2 do
		decor(make("Part", { Size = Vector3.new(0.12, 2.6, 0.08), Position = Vector3.new(x, FLOOR_TOP + 1.5, counterZ + 1.32), Color = Palette.plank, Parent = m }))
	end
	-- Czerwony pas z białymi kropkami na froncie lady (jak kapelusz muchomora)
	decor(make("Part", { Size = Vector3.new(counterW, 0.7, 0.1), Position = Vector3.new(0, FLOOR_TOP + 2.55, counterZ + 1.36), Color = Color3.fromRGB(214, 52, 44), Parent = m }))
	for x = -counterW / 2 + 1.2, counterW / 2 - 1.2, 1.7 do
		decor(make("Part", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.06, 0.34, 0.34), CFrame = CFrame.new(x, FLOOR_TOP + 2.55, counterZ + 1.42) * ALONG_Z, Color = Color3.new(1, 1, 1), Parent = m }))
	end
	-- Waga i kosz z grzybami na ladzie
	decor(make("Part", { Size = Vector3.new(1.6, 0.3, 1.6), Position = Vector3.new(-5, FLOOR_TOP + 3.55, counterZ), Color = Palette.metal, Parent = m }))
	decor(make("Part", { Size = Vector3.new(0.3, 1.2, 0.3), Position = Vector3.new(-5, FLOOR_TOP + 4.1, counterZ), Color = Palette.metal, Parent = m }))
	decor(make("Part", { Size = Vector3.new(2.2, 0.15, 0.3), Position = Vector3.new(-5, FLOOR_TOP + 4.7, counterZ), Color = Palette.metal, Parent = m }))
	for _, dx in { -1, 1 } do
		decor(make("Part", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 0.9, 0.9), CFrame = CFrame.new(-5 + dx, FLOOR_TOP + 4.4, counterZ) * VERTICAL, Color = Palette.metal, Parent = m }))
	end
	for _, bx in { 4.5 } do
		local basket = decor(make("Part", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.2, 2.2, 2.2),
			CFrame = CFrame.new(bx, FLOOR_TOP + 4, counterZ) * VERTICAL,
			Color = Color3.fromRGB(170, 120, 60),
			Parent = m,
		}))
		for i = 1, 4 do
			local cap = decor(make("Part", {
				Size = Vector3.new(0.8, 0.8, 0.8),
				Position = basket.Position + Vector3.new((i % 2 - 0.5) * 0.9, 0.7, (i > 2 and 0.4 or -0.4)),
				Color = Palette.autumn[i],
				Parent = m,
			}))
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Scale = Vector3.new(1, 0.6, 1)
			mesh.Parent = cap
		end
	end
	-- Skrzynki po obu stronach lady
	-- (po prawej od lady zamiast skrzynki stoi teraz stos polan przy kominku)
	for i, offset in { Vector3.new(-9.5, 0, 0), Vector3.new(-9.4, 2.1, 0.2), Vector3.new(-9.5, 0, 2.4) } do
		make("Part", {
			Name = "Crate",
			Size = Vector3.new(2, 2, 2),
			Position = Vector3.new(0, FLOOR_TOP + 1, counterZ) + offset,
			Orientation = Vector3.new(0, i * 7, 0),
			Color = Palette.plank,
			Parent = m,
		})
	end

	buildFireplace(m)
	buildDryingRack(m)
	buildOilCorner(m)

	-- Belki pod dachem (tylko wystrój, kamera przez nie przechodzi)
	for z = BACK_Z + 6, FRONT_Z - 4, 8 do
		local beam = logX(m, -HALF_W, HALF_W, WALL_TOP - 0.4, z, 1.1)
		if beam then
			decor(beam)
		end
	end

	-- Ciepłe światło pod sufitem: główna lampa i dwie mniejsze
	local lamp = Props.hangingLantern(m, Vector3.new(0, WALL_TOP - 1.4, midZ), 30)
	local light = lamp:FindFirstChildOfClass("PointLight")
	if light then
		light.Brightness = 0.9
		light.Shadows = true
	end
	for _, x in { -9, 9 } do
		Props.hangingLantern(m, Vector3.new(x, WALL_TOP - 1.4, BACK_Z + 8), 18)
	end
end

-- Świecący przerywany krąg na podłodze: tu trzeba stanąć, żeby skorzystać ze stanowiska
local function stationRing(m: Model, name: string, color: Color3)
	local station = Economy.station(name, "forest")
	local pieces = 18
	local length = 2 * math.pi * station.radius / pieces * 0.6
	for i = 1, pieces do
		local angle = (i - 1) / pieces * math.pi * 2
		local position = Vector3.new(station.x + math.cos(angle) * station.radius, FLOOR_TOP + 0.03, station.z + math.sin(angle) * station.radius)
		decor(make("Part", {
			Name = "StationRing_" .. name,
			Size = Vector3.new(0.35, 0.06, length),
			-- Odcinek ustawiony stycznie do okręgu
			CFrame = CFrame.new(position) * CFrame.Angles(0, -angle, 0),
			Color = color,
			Material = Enum.Material.Neon,
			Transparency = 0.25,
			Parent = m,
		}))
	end
end

-- Stanowiska: beczka z olejem przy drzwiach i lada skupu z ulepszeniami
local function buildStations(m: Model)
	stationRing(m, "oil", Color3.fromRGB(255, 186, 80))
	stationRing(m, "shop", Color3.fromRGB(150, 226, 110))
	-- Szyld nad ladą na tylnej ścianie, napisem do środka chatki (wysoko, nad kapeluszem skupywacza)
	-- (wyżej niż kiedyś: nowy Pan Borowik ma wyższy kapelusz i jego tabliczka z imieniem wisi wyżej)
	Props.signBoard(m, CFrame.new(Config.Merchant.x, FLOOR_TOP + 11, BACK_Z + 1), Vector3.new(9, 1.9, 0.3), "SIGN_SHOP", Enum.NormalId.Back)
	-- Skupywacz za ladą, przodem do wnętrza
	local merchant = Config.Merchant
	local at = Vector3.new(merchant.x, FLOOR_TOP, merchant.z)
	Merchant.build(m, CFrame.lookAt(at, at + Vector3.new(0, 0, 1)), merchant.promptDistance)
	-- Szyld nad beczką na lewej ścianie
	Props.signBoard(m, CFrame.new(-HALF_W + 1, FLOOR_TOP + 5.4, Economy.station("oil", "forest").z), Vector3.new(0.3, 1.4, 5.6), "SIGN_OIL", Enum.NormalId.Right)
end

local function jar(m: Model, base: Vector3, color: Color3): BasePart
	decor(make("Part", {
		Name = "Jar",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.9, 0.7, 0.7),
		CFrame = CFrame.new(base + Vector3.new(0, 0.45, 0)) * VERTICAL,
		Color = Color3.fromRGB(200, 230, 240),
		Material = Enum.Material.Glass,
		Transparency = 0.45,
		Parent = m,
	}))
	decor(make("Part", {
		Name = "JarLid",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.14, 0.74, 0.74),
		CFrame = CFrame.new(base + Vector3.new(0, 0.95, 0)) * VERTICAL,
		Color = Palette.metal,
		Parent = m,
	}))
	-- Mały świecący grzybek w słoiku
	local cap = decor(make("Part", {
		Name = "JarShroom",
		Size = Vector3.new(0.42, 0.42, 0.42),
		Position = base + Vector3.new(0, 0.55, 0),
		Color = color,
		Material = Enum.Material.Neon,
		Parent = m,
	}))
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 0.6, 1)
	mesh.Parent = cap
	return cap
end

-- Kredens zielarza na lewej ścianie, w pełnej ścianie między oknami: dół z szufladami, na blacie
-- i dwóch półkach słoiki ze świecącymi grzybkami, moździerz, na górze gzyms. Pod tylnym oknem
-- okuta skrzynia z koszykiem borowików.
local function buildHutch(m: Model)
	local wall = -WALL_IN + GAP
	local z1, z2 = -31.7, -26.3 -- okna lewej ściany: z -38..-32 i -26..-20
	local zc, w = (z1 + z2) / 2, z2 - z1
	local lowTop = FLOOR_TOP + 2.8
	local lowDepth = 1.6
	solid(m, "Hutch", Vector3.new(lowDepth, lowTop - FLOOR_TOP, w), CFrame.new(wall + lowDepth / 2, (FLOOR_TOP + lowTop) / 2, zc), Palette.plankDark)
	solid(m, "HutchTop", Vector3.new(lowDepth + 0.25, 0.2, w + 0.3), CFrame.new(wall + (lowDepth + 0.25) / 2, lowTop + 0.1, zc), Palette.plank)
	prop(m, "HutchPlinth", Vector3.new(0.06, 0.22, w - 0.1), CFrame.new(wall + lowDepth + 0.03, FLOOR_TOP + 0.11, zc), Color3.fromRGB(70, 48, 32))
	for _, y in { FLOOR_TOP + 0.85, FLOOR_TOP + 2.05 } do
		for _, dz in { -w / 4, w / 4 } do
			prop(m, "HutchDrawer", Vector3.new(0.08, 1, w / 2 - 0.35), CFrame.new(wall + lowDepth + 0.04, y, zc + dz), Palette.plank)
			prop(m, "HutchKnob", Vector3.new(0.22, 0.22, 0.22), CFrame.new(wall + lowDepth + 0.16, y, zc + dz), BRASS, Enum.Material.Metal, Enum.PartType.Ball)
		end
	end
	-- Górna część: plecy, boki, dwie półki i gzyms
	local upDepth = 1.1
	local upBottom = lowTop + 0.2
	local upTop = FLOOR_TOP + 9
	local upMid = (upBottom + upTop) / 2
	prop(m, "HutchBack", Vector3.new(0.1, upTop - upBottom, w - 0.2), CFrame.new(wall + 0.05, upMid, zc), Palette.plankDark)
	for _, z in { z1 + 0.1, z2 - 0.1 } do
		solid(m, "HutchSide", Vector3.new(upDepth, upTop - upBottom, 0.2), CFrame.new(wall + upDepth / 2, upMid, z), Palette.plank)
	end
	local levels = { upBottom, FLOOR_TOP + 5, FLOOR_TOP + 7 }
	for i = 2, #levels do
		prop(m, "HutchShelf", Vector3.new(upDepth, 0.16, w - 0.4), CFrame.new(wall + upDepth / 2, levels[i] - 0.08, zc), Palette.plank)
	end
	prop(m, "HutchCrown", Vector3.new(upDepth + 0.4, 0.3, w + 0.4), CFrame.new(wall + (upDepth + 0.4) / 2, upTop + 0.15, zc), Palette.plankDark)
	prop(m, "HutchCrownTrim", Vector3.new(upDepth + 0.2, 0.16, w + 0.2), CFrame.new(wall + (upDepth + 0.2) / 2, upTop - 0.08, zc), Palette.plank)
	-- Słoiki: po cztery na blacie i na każdej półce
	local jarColors = {
		Color3.fromRGB(110, 255, 214),
		Color3.fromRGB(255, 120, 200),
		Color3.fromRGB(150, 120, 255),
		Color3.fromRGB(255, 200, 80),
	}
	local glowing: BasePart? = nil
	for level, y in levels do
		for k = 1, 4 do
			local shroom = jar(m, Vector3.new(wall + 0.55, y, zc + (k - 2.5) * 1.15), jarColors[(k + level) % #jarColors + 1])
			if level == 2 and k == 2 then
				glowing = shroom
			end
		end
	end
	if glowing then
		local shelfLight = Instance.new("PointLight")
		shelfLight.Color = Color3.fromRGB(170, 220, 255)
		shelfLight.Range = 8
		shelfLight.Brightness = 0.6
		shelfLight.Parent = glowing
	end
	-- Moździerz z tłuczkiem z przodu blatu
	local mortar = Vector3.new(wall + 1.4, upBottom, z2 - 1.1)
	prop(m, "Mortar", Vector3.new(0.4, 0.62, 0.62), CFrame.new(mortar + Vector3.new(0, 0.2, 0)) * VERTICAL, Color3.fromRGB(150, 144, 136), nil, Enum.PartType.Cylinder)
	prop(m, "Pestle", Vector3.new(0.75, 0.13, 0.13), CFrame.new(mortar + Vector3.new(0.05, 0.55, 0.05)) * CFrame.Angles(0, 0, math.rad(70)), Color3.fromRGB(176, 140, 100), nil, Enum.PartType.Cylinder)

	-- Okuta skrzynia pod tylnym oknem
	local cz = -35
	local chestDepth = 1.5
	local chestX = wall + chestDepth / 2
	solid(m, "Chest", Vector3.new(chestDepth, 1.3, 3), CFrame.new(chestX, FLOOR_TOP + 0.65, cz), OAK)
	prop(m, "ChestLid", Vector3.new(chestDepth + 0.12, 0.3, 3.12), CFrame.new(chestX + 0.03, FLOOR_TOP + 1.45, cz), OAK_DARK)
	for _, dz in { -1, 1 } do
		prop(m, "ChestBand", Vector3.new(chestDepth + 0.16, 1.62, 0.16), CFrame.new(chestX + 0.04, FLOOR_TOP + 0.83, cz + dz), IRON, Enum.Material.Metal)
	end
	prop(m, "ChestLock", Vector3.new(0.1, 0.34, 0.3), CFrame.new(wall + chestDepth + 0.1, FLOOR_TOP + 1.2, cz), BRASS, Enum.Material.Metal)
	basket(m, Vector3.new(chestX + 0.05, FLOOR_TOP + 1.6, cz - 0.3), PORCINI, 1.4)
end

-- ===== Halloween w chatce =====
-- Lekko: pajęczyny w rogach pod sufitem, pająk na nitce spod belki i trzy małe dynie (dwie na
-- gzymsie kominka, jedna na stoliku). Dynie w tym samym stylu co w HalloweenDecor (voxelowe,
-- ze świecącą buzią). Budowane tylko w czasie eventu (atrybut Workspace „Halloween”).
local HALLOWEEN_FOLDER = "HalloweenInterior"
local WEB = Color3.fromRGB(230, 230, 236)
local PUMPKIN = Color3.fromRGB(196, 86, 16)
local PUMPKIN_DARK = Color3.fromRGB(140, 56, 12)
local PUMPKIN_GLOW = Color3.fromRGB(255, 214, 90)

-- Płaska sieć po przekątnej rogu: nici od rogu w dół (wzdłuż krawędzi ścian) i w głąb pokoju
local function cobweb(parent: Instance, corner: Vector3, inward: Vector3, size: number)
	local cf = CFrame.fromMatrix(corner, Vector3.new(inward.X, 0, inward.Z).Unit, Vector3.yAxis)
	local strands = 5
	local rings: { { Vector3 } } = {}
	for i = 0, strands - 1 do
		local angle = math.rad(-90 + i * 90 / (strands - 1))
		local to = (cf * CFrame.new(math.cos(angle) * size, math.sin(angle) * size, 0)).Position
		prop(parent, "WebStrand", Vector3.new(0.05, 0.05, (to - corner).Magnitude), CFrame.lookAt((corner + to) / 2, to), WEB).Transparency = 0.35
		rings[i + 1] = {}
		for k = 1, 3 do
			rings[i + 1][k] = corner:Lerp(to, k / 3.4)
		end
	end
	for k = 1, 3 do
		for i = 1, strands - 1 do
			local a, b = rings[i][k], rings[i + 1][k]
			prop(parent, "WebRing", Vector3.new(0.04, 0.04, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), WEB).Transparency = 0.45
		end
	end
end

-- Pająk zwisający na nitce (top = punkt zaczepienia), oczami w stronę drzwi
local function spider(parent: Instance, top: Vector3, drop: number)
	prop(parent, "SpiderThread", Vector3.new(0.04, drop, 0.04), CFrame.new(top - Vector3.new(0, drop / 2, 0)), WEB).Transparency = 0.4
	local body = CFrame.new(top - Vector3.new(0, drop + 0.2, 0)) * CFrame.Angles(0, math.pi, 0)
	local black = Color3.fromRGB(28, 22, 30)
	prop(parent, "Spider", Vector3.new(0.45, 0.35, 0.55), body, black)
	for _, side in { -1, 1 } do
		for k = -1, 1 do
			prop(parent, "SpiderLeg", Vector3.new(0.5, 0.06, 0.06), body * CFrame.new(side * 0.4, -0.05, k * 0.18) * CFrame.Angles(0, 0, side * 0.5), black)
		end
	end
	prop(parent, "SpiderEye", Vector3.new(0.3, 0.08, 0.06), body * CFrame.new(0, 0.05, -0.29), Color3.fromRGB(255, 60, 60), Enum.Material.Neon)
end

-- Mała dynia z wyciętą buzią; at = punkt na blacie, buzia patrzy w stronę -Z układu `at`
local function miniPumpkin(parent: Instance, at: CFrame, s: number)
	local bodyH = s * 0.78
	local y = s * 0.08 + bodyH / 2
	prop(parent, "PumpkinBody", Vector3.new(s, bodyH, s), at * CFrame.new(0, y, 0), PUMPKIN)
	prop(parent, "PumpkinBottom", Vector3.new(s * 0.82, s * 0.08, s * 0.82), at * CFrame.new(0, s * 0.04, 0), PUMPKIN_DARK)
	prop(parent, "PumpkinTop", Vector3.new(s * 0.72, s * 0.1, s * 0.72), at * CFrame.new(0, s * 0.08 + bodyH + s * 0.05, 0), PUMPKIN)
	prop(parent, "PumpkinStem", Vector3.new(s * 0.16, s * 0.26, s * 0.16), at * CFrame.new(s * 0.03, s * 0.08 + bodyH + s * 0.2, 0) * CFrame.Angles(0, 0, math.rad(-12)), Color3.fromRGB(70, 104, 40))
	for _, x in { -0.22, 0.22 } do
		prop(parent, "PumpkinRib", Vector3.new(s * 0.06, bodyH * 0.9, 0.04), at * CFrame.new(x * s, y, s / 2 + 0.01), PUMPKIN_DARK)
	end
	local front = -s / 2 - 0.02
	for _, x in { -0.22, 0.22 } do
		prop(parent, "PumpkinEye", Vector3.new(s * 0.16, s * 0.16, 0.05), at * CFrame.new(x * s, y + s * 0.12, front) * CFrame.Angles(0, 0, math.rad(45)), PUMPKIN_GLOW, Enum.Material.Neon)
	end
	prop(parent, "PumpkinMouth", Vector3.new(s * 0.54, s * 0.13, 0.05), at * CFrame.new(0, y - s * 0.17, front), PUMPKIN_GLOW, Enum.Material.Neon)
end

local function buildHalloween(folder: Folder)
	local y = WALL_TOP - 1.2
	cobweb(folder, Vector3.new(-WALL_IN + 0.15, y, BACK_IN + 0.15), Vector3.new(1, 0, 1), 2.4)
	cobweb(folder, Vector3.new(-WALL_IN + 0.15, y, FRONT_IN - 0.15), Vector3.new(1, 0, -1), 2)
	cobweb(folder, Vector3.new(WALL_IN - 0.15, y, FRONT_IN - 0.15), Vector3.new(-1, 0, -1), 2)
	cobweb(folder, Vector3.new(WALL_IN - 0.15, y, BACK_IN + 0.15), Vector3.new(-1, 0, 1), 1.2)
	-- Spod belki nad lewą częścią pokoju (belki: z = -39, -31, -23, -15, spód na 13,65)
	spider(folder, Vector3.new(-7, WALL_TOP - 0.4 - 0.55, BACK_Z + 14), 2.6)
	-- Buzie w stronę drzwi (+Z)
	local toDoor = Vector3.new(0, 0, 1)
	for _, dx in { -1.5, 1.5 } do
		local at = Vector3.new(FIRE_X + dx, MANTEL_TOP, MANTEL_ITEMS_Z)
		miniPumpkin(folder, CFrame.lookAt(at, at + toDoor) * CFrame.Angles(0, math.rad(dx * 6), 0), 0.8)
	end
	local onTable = TABLE_AT + Vector3.new(0.95, 2.7, -0.6)
	miniPumpkin(folder, CFrame.lookAt(onTable, onTable + toDoor) * CFrame.Angles(0, math.rad(-20), 0), 0.6)
end

local function setHalloween(m: Model, on: boolean)
	local existing = m:FindFirstChild(HALLOWEEN_FOLDER)
	if on and not existing then
		local folder = Instance.new("Folder")
		folder.Name = HALLOWEEN_FOLDER
		buildHalloween(folder)
		folder.Parent = m
	elseif not on and existing then
		existing:Destroy()
	end
end

-- Wystrój: kredens ze słoikami i skrzynia na lewej ścianie, stolik z lampką-muchomorem i stołkami,
-- ławka i doniczki z kwiatami na ganku
local function buildDecor(m: Model)
	buildHutch(m)

	-- Okrągły stolik z lampką-muchomorem i dwa stołki (po prawej, z dala od drogi do lady)
	local tableAt = TABLE_AT
	make("Part", { Name = "TableLeg", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.4, 0.5, 0.5), CFrame = CFrame.new(tableAt + Vector3.new(0, 1.2, 0)) * VERTICAL, Color = Palette.plankDark, Parent = m })
	make("Part", { Name = "TableTop", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 3.4, 3.4), CFrame = CFrame.new(tableAt + Vector3.new(0, 2.5, 0)) * VERTICAL, Color = Palette.plank, Parent = m })
	prop(m, "TableCloth", Vector3.new(0.05, 3.6, 3.6), CFrame.new(tableAt + Vector3.new(0, 2.675, 0)) * VERTICAL, Color3.fromRGB(168, 58, 48), nil, Enum.PartType.Cylinder)
	prop(m, "TableDoily", Vector3.new(0.04, 1.5, 1.5), CFrame.new(tableAt + Vector3.new(0, 2.71, 0)) * VERTICAL, Color3.fromRGB(240, 230, 210), nil, Enum.PartType.Cylinder)
	-- Otwarta książka (atlas grzybów) i kubek herbaty
	local book = CFrame.new(tableAt + Vector3.new(0.7, 2.7, 0.75)) * CFrame.Angles(0, math.rad(28), 0)
	prop(m, "BookCover", Vector3.new(1.2, 0.05, 0.8), book * CFrame.new(0, 0.025, 0), Color3.fromRGB(112, 40, 40))
	for _, side in { -1, 1 } do
		prop(m, "BookPages", Vector3.new(0.56, 0.07, 0.72), book * CFrame.new(side * 0.29, 0.085, 0) * CFrame.Angles(0, 0, math.rad(side * -4)), Color3.fromRGB(244, 236, 214))
	end
	local mug = tableAt + Vector3.new(-0.8, 2.7, -0.5)
	prop(m, "Mug", Vector3.new(0.5, 0.42, 0.42), CFrame.new(mug + Vector3.new(0, 0.25, 0)) * VERTICAL, Color3.fromRGB(86, 120, 168), nil, Enum.PartType.Cylinder)
	prop(m, "MugTea", Vector3.new(0.03, 0.34, 0.34), CFrame.new(mug + Vector3.new(0, 0.51, 0)) * VERTICAL, Color3.fromRGB(110, 62, 30), nil, Enum.PartType.Cylinder)
	prop(m, "MugHandle", Vector3.new(0.08, 0.3, 0.2), CFrame.new(mug + Vector3.new(0.26, 0.25, 0)), Color3.fromRGB(86, 120, 168))
	-- Stołki: siedzisko na trzech rozstawionych nóżkach
	for _, dx in { -2.4, 2.4 } do
		local stool = tableAt + Vector3.new(dx, 0, 0.4)
		solid(m, "Stool", Vector3.new(0.26, 1.3, 1.3), CFrame.new(stool + Vector3.new(0, 1.27, 0)) * VERTICAL, Palette.plankDark, nil, Enum.PartType.Cylinder)
		for k = 0, 2 do
			local angle = math.rad(k * 120 + 30)
			local foot = stool + Vector3.new(math.cos(angle) * 0.52, 0, math.sin(angle) * 0.52)
			local hip = stool + Vector3.new(math.cos(angle) * 0.36, 1.15, math.sin(angle) * 0.36)
			prop(m, "StoolLeg", Vector3.new(0.16, 0.16, (hip - foot).Magnitude), CFrame.lookAt((foot + hip) / 2, hip), Palette.plankDark)
		end
	end
	decor(make("Part", { Name = "LampStem", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.7, 0.3, 0.3), CFrame = CFrame.new(tableAt + Vector3.new(0, 3, 0)) * VERTICAL, Color = Color3.fromRGB(236, 228, 212), Parent = m }))
	local lampCap = decor(make("Part", {
		Name = "LampCap",
		Size = Vector3.new(1.2, 0.8, 1.2),
		Position = tableAt + Vector3.new(0, 3.45, 0),
		Color = Color3.fromRGB(230, 60, 50),
		Material = Enum.Material.Neon,
		Parent = m,
	}))
	local lampMesh = Instance.new("SpecialMesh")
	lampMesh.MeshType = Enum.MeshType.Sphere
	lampMesh.Parent = lampCap
	local lampLight = Instance.new("PointLight")
	lampLight.Color = Color3.fromRGB(255, 150, 120)
	lampLight.Range = 9
	lampLight.Brightness = 0.7
	lampLight.Parent = lampCap

	-- Ganek: ławka po lewej od drzwi i doniczki z kwiatami przy schodkach
	local deckTop = 1
	local benchZ = FRONT_Z + 2.2
	make("Part", { Name = "BenchSeat", Size = Vector3.new(4.5, 0.35, 1.3), Position = Vector3.new(-11, deckTop + 1.1, benchZ), Color = Palette.plank, Parent = m })
	make("Part", { Name = "BenchBack", Size = Vector3.new(4.5, 1.2, 0.25), Position = Vector3.new(-11, deckTop + 1.9, benchZ - 0.55), Color = Palette.plank, Parent = m })
	for _, dx in { -1.9, 1.9 } do
		make("Part", { Name = "BenchLeg", Size = Vector3.new(0.3, 1, 1.1), Position = Vector3.new(-11 + dx, deckTop + 0.5, benchZ), Color = Palette.plankDark, Parent = m })
	end
	-- Bujany fotel po prawej od drzwi, przodem do lasu: tu gracz budzi się po złym śnie (cutscenka)
	local chair = Instance.new("Model")
	chair.Name = "RockingChair"
	local cx, cz = 9.5, FRONT_Z + 3.2
	local seat = make("Part", { Name = "Seat", Size = Vector3.new(2.4, 0.3, 2.2), Position = Vector3.new(cx, deckTop + 1.45, cz), Color = Palette.plank, Parent = chair })
	make("Part", { Name = "Back", Size = Vector3.new(2.4, 2.6, 0.25), CFrame = CFrame.new(cx, deckTop + 2.8, cz - 1.15) * CFrame.Angles(math.rad(-12), 0, 0), Color = Palette.plank, Parent = chair })
	for _, dy in { 0.6, 1.2, 1.8 } do
		decor(make("Part", { Size = Vector3.new(2.5, 0.16, 0.3), CFrame = CFrame.new(cx, deckTop + 1.5 + dy, cz - 1.0 - dy * 0.2) * CFrame.Angles(math.rad(-12), 0, 0), Color = Palette.plankDark, Parent = chair }))
	end
	for _, side in { -1, 1 } do
		local x = cx + side * 1.15
		make("Part", { Name = "Arm", Size = Vector3.new(0.3, 0.2, 2.2), Position = Vector3.new(x, deckTop + 2.25, cz + 0.05), Color = Palette.plankDark, Parent = chair })
		for _, dz in { -0.9, 0.9 } do
			make("Part", { Name = "Leg", Size = Vector3.new(0.25, 1.2, 0.25), Position = Vector3.new(x, deckTop + 0.85, cz + dz), Color = Palette.plankDark, Parent = chair })
		end
		make("Part", { Name = "ArmPost", Size = Vector3.new(0.22, 0.8, 0.22), Position = Vector3.new(x, deckTop + 1.85, cz + 0.95), Color = Palette.plankDark, Parent = chair })
		-- Płozy: trzy odcinki ułożone w łuk
		for k, angle in { -14, 0, 14 } do
			local dz = (k - 2) * 1.05
			make("Part", { Name = "Rocker", Size = Vector3.new(0.3, 0.22, 1.15), CFrame = CFrame.new(x, deckTop + 0.2 + math.abs(dz) * 0.12, cz + dz) * CFrame.Angles(math.rad(angle), 0, 0), Color = Palette.log, Parent = chair })
		end
	end
	-- Poduszka w kratkę
	decor(make("Part", { Name = "Cushion", Size = Vector3.new(2.1, 0.2, 1.9), Position = Vector3.new(cx, deckTop + 1.7, cz + 0.05), Color = Color3.fromRGB(176, 60, 50), Parent = chair }))
	chair.PrimaryPart = seat
	chair:SetAttribute("Pivot", Vector3.new(cx, deckTop, cz))
	chair.Parent = m

	local flowerColors = { Color3.fromRGB(236, 96, 96), Color3.fromRGB(250, 210, 90), Color3.fromRGB(180, 130, 240) }
	for side = -1, 1, 2 do
		local pot = Vector3.new(side * 5, deckTop, FRONT_Z + 5.2)
		make("Part", { Name = "Pot", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.1, 1.2, 1.2), CFrame = CFrame.new(pot + Vector3.new(0, 0.55, 0)) * VERTICAL, Color = Color3.fromRGB(180, 96, 60), Parent = m })
		for k = 1, 3 do
			local angle = k * 2.1
			local flower = pot + Vector3.new(math.cos(angle) * 0.3, 1.5 + k * 0.08, math.sin(angle) * 0.3)
			decor(make("Part", { Name = "Flower", Shape = Enum.PartType.Ball, Size = Vector3.new(0.5, 0.5, 0.5), Position = flower, Color = flowerColors[k], Parent = m }))
			decor(make("Part", { Name = "FlowerStem", Size = Vector3.new(0.1, 0.6, 0.1), Position = flower - Vector3.new(0, 0.4, 0), Color = Color3.fromRGB(70, 120, 56), Parent = m }))
		end
	end
end

-- Buduje chatkę i zwraca CFrame miejsca startu (w środku, twarzą do drzwi i lasu)
-- Bale ułożone jeden nad drugim działają w Robloxie jak drabina: postać wspina się po ścianie
-- na dach. Niewidzialne płaskie płyty na całą grubość ścian (i wokół komina) zasłaniają szczeliny
-- między balami, więc ściana jest gładka z obu stron. W ścianie frontowej zostaje otwór na drzwi.
local function buildClimbGuards(m: Model)
	local thickness = LOG_D + 0.2
	local top = WALL_TOP + 0.5
	local function guard(size: Vector3, position: Vector3)
		make("Part", {
			Name = "ClimbGuard",
			Size = size,
			Position = position,
			Transparency = 1,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Parent = m,
		})
	end
	local width = HALF_W * 2 + 2.4
	local height = top - FLOOR_TOP + 1
	local centerY = FLOOR_TOP - 1 + height / 2
	-- Tył i boki w całości
	guard(Vector3.new(width, height, thickness), Vector3.new(0, centerY, BACK_Z))
	for _, x in { -HALF_W, HALF_W } do
		guard(Vector3.new(thickness, height, FRONT_Z - BACK_Z + 2.4), Vector3.new(x, centerY, (FRONT_Z + BACK_Z) / 2))
	end
	-- Przód: po obu stronach drzwi, nad drzwiami nadproże
	local doorHalf = 3
	local doorTop = rowY(5) - LOG_D / 2
	local sideWidth = width / 2 - doorHalf
	for _, side in { -1, 1 } do
		guard(Vector3.new(sideWidth, height, thickness), Vector3.new(side * (doorHalf + sideWidth / 2), centerY, FRONT_Z))
	end
	guard(Vector3.new(doorHalf * 2, top - doorTop, thickness), Vector3.new(0, (top + doorTop) / 2, FRONT_Z))
	-- Komin z kamieni na przemian szerszych i węższych też był drabiną
	local chimneyTop = WALL_TOP + 11
	guard(Vector3.new(4, chimneyTop, 3.4), Vector3.new(HALF_W - 4, chimneyTop / 2, BACK_Z - 1.6))

	-- Dach: złodziej z cudzym grzybem wskakiwał na dach (z płotu ogródka, daszku ganku albo
	-- ozdób) i przechodził nim na drugą stronę chatki. Niewidzialny słup nad całą chatką z gankiem
	-- i kominem zaczyna się tuż pod okapem i sięga wysoko w niebo: ma pionowe, gładkie boki,
	-- więc nie da się na nim stanąć ani dostać na dach. W środku chatki i na ganku jest wyżej
	-- niż głowa skaczącej postaci, więc nikomu nie przeszkadza.
	local eaveY = WALL_TOP - 1.6 * math.tan(ROOF_ANGLE) + 0.3
	local bottom = eaveY - 0.1 -- skacząca postać w chatce sięga głową ok. 13,8; okap ~13,8, a stanąć pod nim się nie da
	local blockTop = 160
	local x1, x2 = -HALF_W - 3, HALF_W + 3
	local z1, z2 = BACK_Z - 4.5, FRONT_Z + 9
	make("Part", {
		Name = "RoofBlocker",
		Size = Vector3.new(x2 - x1, blockTop - bottom, z2 - z1),
		Position = Vector3.new((x1 + x2) / 2, (bottom + blockTop) / 2, (z1 + z2) / 2),
		Transparency = 1,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = m,
	})
end

function Cabin.build(parent: Instance): CFrame
	local m = Instance.new("Model")
	m.Name = "Cabin"
	buildInterior(m)
	buildStations(m)
	buildDecor(m)
	buildFoundation(m)
	buildWalls(m)
	buildRoof(m)
	buildChimney(m)
	buildPorch(m)
	buildClimbGuards(m)
	m.Parent = parent
	-- Wystrój Halloween w środku: włącza się i wyłącza razem z eventem (atrybut ustawia GameService)
	local function syncHalloween()
		if m.Parent then
			setHalloween(m, Workspace:GetAttribute("Halloween") == true)
		end
	end
	syncHalloween()
	Workspace:GetAttributeChangedSignal("Halloween"):Connect(syncHalloween)
	-- Bliżej drzwi niż tylnej ściany, żeby kamera za plecami gracza nie wchodziła w bale
	return CFrame.new(0, FLOOR_TOP + 3, -20) * CFrame.Angles(0, math.pi, 0)
end

Cabin.FRONT_Z = FRONT_Z
Cabin.BACK_Z = BACK_Z
Cabin.HALF_W = HALF_W

return Cabin
