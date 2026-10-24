--!strict
-- Chatka grzybiarza z bali: ganek, dwuspadowy dach, komin z dymem, kominek,
-- lada do sprzedaży i suszarnia z grzybami (zapowiedź przyszłej mechaniki).
-- Front patrzy w stronę lasu (+Z), drzwi na środku.

local Palette = require(script.Parent.Palette)
local Props = require(script.Parent.Props)

local Cabin = {}

local VERTICAL = CFrame.Angles(0, 0, math.rad(90))
local ALONG_Z = CFrame.Angles(0, math.rad(90), 0) -- oś walca (X) obrócona wzdłuż Z

-- Wymiary (studs)
local HALF_W = 13 -- ściany boczne na x = ±13
local BACK_Z = -35
local FRONT_Z = -13
local FLOOR_TOP = 1
local LOG_D = 1.6
local LOG_STEP = 1.5
local ROWS = 7
local WALL_TOP = FLOOR_TOP + LOG_D / 2 + (ROWS - 1) * LOG_STEP + LOG_D / 2
local ROOF_ANGLE = math.rad(35)

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

local function logX(parent: Instance, x1: number, x2: number, y: number, z: number, diameter: number?)
	if x2 - x1 < 0.5 then
		return
	end
	local d = diameter or LOG_D
	make("Part", {
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
	local doorHalf = 2.6
	local doorRows = 4 -- rzędy 0-3 mają otwór na drzwi
	local frontWindows = { { -10, -6 }, { 6, 10 } }
	local sideWindow = { -27, -21 }

	for row = 0, ROWS - 1 do
		local y = rowY(row)
		local windowRow = row == 2 or row == 3

		-- Tył
		logX(m, -HALF_W - 1, HALF_W + 1, y, BACK_Z)

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
		for _, seg in segments(-HALF_W - 1, HALF_W + 1, holes) do
			logX(m, seg[1], seg[2], y, FRONT_Z)
		end

		-- Boki (przesunięte o pół bala w górę, jak w prawdziwym zrębie)
		local sideY = y + LOG_STEP / 2
		if row < ROWS - 1 then
			for _, x in { -HALF_W, HALF_W } do
				local sideHoles = if windowRow then { sideWindow } else {}
				for _, seg in segments(BACK_Z - 1, FRONT_Z + 1, sideHoles) do
					logZ(m, seg[1], seg[2], sideY, x)
				end
			end
		end
	end

	-- Okna: świecące szybki w otworach
	local windowY = (rowY(2) + rowY(3)) / 2
	local windowH = LOG_STEP * 2 - 0.2
	for _, w in frontWindows do
		window(m, CFrame.new((w[1] + w[2]) / 2, windowY, FRONT_Z), w[2] - w[1], windowH, 1)
	end
	for _, x in { -HALF_W, HALF_W } do
		-- Po obrocie ALONG_Z lokalne +Z wskazuje świat +X
		local outward = if x > 0 then 1 else -1
		window(m, CFrame.new(x, windowY + LOG_STEP / 2, (sideWindow[1] + sideWindow[2]) / 2) * ALONG_Z, sideWindow[2] - sideWindow[1], windowH, outward)
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
	local top = WALL_TOP + 9
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
	Props.signBoard(m, CFrame.new(0, rowY(5) + 0.3, FRONT_Z + 1.05), Vector3.new(9, 1.9, 0.3), "ZONE_CABIN", Enum.NormalId.Back)
end

local function buildInterior(m: Model)
	-- Podłoga z desek, szersza niż ściany, żeby pod balami nie było szpary
	make("Part", {
		Name = "Floor",
		Size = Vector3.new(HALF_W * 2 + 2, 1, FRONT_Z - BACK_Z + 2),
		Position = Vector3.new(0, FLOOR_TOP - 0.5, (FRONT_Z + BACK_Z) / 2),
		Color = Palette.plank,
		Parent = m,
	})
	-- Dywanik
	decor(make("Part", {
		Size = Vector3.new(8, 0.08, 6),
		Position = Vector3.new(0, FLOOR_TOP + 0.04, -23),
		Color = Color3.fromRGB(150, 54, 44),
		Parent = m,
	}))

	-- Lada skupu grzybów przy tylnej ścianie
	make("Part", { Name = "Counter", Size = Vector3.new(10, 3, 2.6), Position = Vector3.new(-5, FLOOR_TOP + 1.5, BACK_Z + 2.4), Color = Palette.plankDark, Parent = m })
	make("Part", { Size = Vector3.new(10.6, 0.4, 3), Position = Vector3.new(-5, FLOOR_TOP + 3.2, BACK_Z + 2.4), Color = Palette.plank, Parent = m })
	-- Waga i kosz z grzybami na ladzie
	decor(make("Part", { Size = Vector3.new(1.6, 0.3, 1.6), Position = Vector3.new(-8, FLOOR_TOP + 3.55, BACK_Z + 2.4), Color = Palette.metal, Parent = m }))
	decor(make("Part", { Size = Vector3.new(0.3, 1.2, 0.3), Position = Vector3.new(-8, FLOOR_TOP + 4.1, BACK_Z + 2.4), Color = Palette.metal, Parent = m }))
	local basket = decor(make("Part", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.2, 2.2, 2.2),
		CFrame = CFrame.new(-3, FLOOR_TOP + 4, BACK_Z + 2.4) * VERTICAL,
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
	-- Skrzynki obok lady
	for i, offset in { Vector3.new(2.5, 0, 0), Vector3.new(2.6, 2.1, 0.2), Vector3.new(2.5, 0, 2.3) } do
		make("Part", {
			Name = "Crate",
			Size = Vector3.new(2, 2, 2),
			Position = Vector3.new(0, FLOOR_TOP + 1, BACK_Z + 2.4) + offset,
			Orientation = Vector3.new(0, i * 7, 0),
			Color = Palette.plank,
			Parent = m,
		})
	end

	-- Kominek
	local fx, fz = HALF_W - 4, BACK_Z + 1.4
	make("Part", { Name = "Fireplace", Size = Vector3.new(5, 5, 1.6), Position = Vector3.new(fx, FLOOR_TOP + 2.5, fz), Color = Palette.stoneChimney, Parent = m })
	decor(make("Part", { Size = Vector3.new(3, 2.4, 0.2), Position = Vector3.new(fx, FLOOR_TOP + 1.3, fz + 0.75), Color = Color3.fromRGB(20, 16, 14), Parent = m }))
	local embers = decor(make("Part", {
		Size = Vector3.new(2.2, 0.4, 0.3),
		Position = Vector3.new(fx, FLOOR_TOP + 0.3, fz + 0.9),
		Color = Color3.fromRGB(255, 120, 40),
		Material = Enum.Material.Neon,
		Parent = m,
	}))
	local fire = Instance.new("ParticleEmitter")
	fire.Texture = "rbxasset://textures/particles/fire_main.dds"
	fire.Color = ColorSequence.new(Color3.fromRGB(255, 170, 70), Color3.fromRGB(255, 80, 30))
	fire.LightEmission = 1
	fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0.2) })
	fire.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	fire.Lifetime = NumberRange.new(0.6, 1)
	fire.Rate = 18
	fire.Speed = NumberRange.new(1.5, 2.5)
	fire.SpreadAngle = Vector2.new(15, 15)
	fire.EmissionDirection = Enum.NormalId.Top
	fire.Parent = embers
	local fireLight = Instance.new("PointLight")
	fireLight.Color = Color3.fromRGB(255, 140, 60)
	fireLight.Range = 14
	fireLight.Brightness = 0.9
	fireLight.Parent = embers

	-- Suszarnia: dwa słupki, sznurki i grzyby na nitkach (przyszła mechanika suszenia)
	local rackX = HALF_W - 2.5
	for _, z in { -29, -18 } do
		make("Part", { Size = Vector3.new(0.4, 6, 0.4), Position = Vector3.new(rackX, FLOOR_TOP + 3, z), Color = Palette.plankDark, Parent = m })
	end
	for i, y in { 4.2, 5.6 } do
		decor(make("Part", { Size = Vector3.new(0.08, 0.08, 11), Position = Vector3.new(rackX, FLOOR_TOP + y, -23.5), Color = Color3.fromRGB(200, 190, 170), Parent = m }))
		for z = -28, -19, 1.5 do
			local cap = decor(make("Part", {
				Size = Vector3.new(0.7, 0.7, 0.7),
				Position = Vector3.new(rackX, FLOOR_TOP + y - 0.45, z + (i - 1) * 0.6),
				Color = Color3.fromRGB(150, 104, 60):Lerp(Color3.fromRGB(110, 70, 40), (z % 3) / 3),
				Parent = m,
			}))
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Scale = Vector3.new(1, 0.6, 1)
			mesh.Parent = cap
		end
	end

	-- Beczka z olejem do latarni przy drzwiach
	local barrel = make("Part", {
		Name = "OilBarrel",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3, 2.2, 2.2),
		CFrame = CFrame.new(-HALF_W + 2.2, FLOOR_TOP + 1.5, FRONT_Z - 2) * VERTICAL,
		Color = Color3.fromRGB(96, 66, 44),
		Parent = m,
	})
	for _, dy in { -0.9, 0.9 } do
		decor(make("Part", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.2, 2.3, 2.3),
			CFrame = barrel.CFrame * CFrame.new(dy, 0, 0),
			Color = Palette.metal,
			Parent = m,
		}))
	end

	-- Ciepłe światło pod sufitem
	local lamp = Props.hangingLantern(m, Vector3.new(0, WALL_TOP - 0.4, -24), 26)
	local light = lamp:FindFirstChildOfClass("PointLight")
	if light then
		light.Brightness = 0.9
		light.Shadows = true
	end
end

-- Buduje chatkę i zwraca CFrame miejsca startu (w środku, twarzą do drzwi i lasu)
function Cabin.build(parent: Instance): CFrame
	local m = Instance.new("Model")
	m.Name = "Cabin"
	buildInterior(m)
	buildWalls(m)
	buildRoof(m)
	buildChimney(m)
	buildPorch(m)
	m.Parent = parent
	-- Bliżej drzwi niż tylnej ściany, żeby kamera za plecami gracza nie wchodziła w bale
	return CFrame.new(0, FLOOR_TOP + 3, -20) * CFrame.Angles(0, math.pi, 0)
end

Cabin.FRONT_Z = FRONT_Z
Cabin.BACK_Z = BACK_Z
Cabin.HALF_W = HALF_W

return Cabin
