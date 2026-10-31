--!strict
-- Ogródek gracza na polanie przy chatce: kwadrat trawy ogrodzony żerdziami, furtka z tabliczką
-- z imieniem właściciela, siatka grządek na grzyby, skrzynia na monety, kwiaty i krzaki.
-- Lokalne -Z ogródka to strona furtki (patrzy na ścieżkę przy chatce).
-- Zwraca model ogródka. GardenService szuka w nim: "OwnerSign" (imię na furtce),
-- "Hub" (przyciski sadzenia i kradzieży), "Chest" (monety z grządek) i grządek "Bed<i>".

local Palette = require(script.Parent.Palette)
local Props = require(script.Parent.Props)
local Beds = require(script.Parent.Beds)

local Garden = {}

local VERTICAL = CFrame.Angles(0, 0, math.rad(90))
local POST_SPACING = 3.6
local GATE_HALF = 2.6
local FENCE_H = 3
local GRASS = Color3.fromRGB(96, 128, 66)
local SOIL = Color3.fromRGB(92, 66, 46)
local GRAVEL = Color3.fromRGB(150, 134, 112)
local FLOWERS = {
	Color3.fromRGB(236, 96, 96),
	Color3.fromRGB(250, 210, 90),
	Color3.fromRGB(180, 130, 240),
	Color3.fromRGB(250, 160, 200),
	Color3.fromRGB(255, 244, 230),
}

local function make(parent: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

local function decor(p: Part): Part
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

-- Niewidzialna, gładka ściana kolizji. Słupki i żerdzie płotu są tylko ozdobą: na cienkich walcach
-- fizyka Robloxa potrafiła zaklinować postać i wystrzelić ją w górę (zwłaszcza po skoku z góry na płot).
-- Na płaskim wierzchu takiej ściany da się normalnie stanąć albo z niej zeskoczyć.
local function collider(parent: Instance, name: string, size: Vector3, cf: CFrame)
	make(parent, {
		Name = name,
		Size = size,
		CFrame = cf,
		Transparency = 1,
		-- CanQuery zostaje włączone: Humanoid szuka podłoża raycastem i bez tego na wierzchu płotu
		-- „spadałby w miejscu”. Kamery to nie zasłania (kamera Robloxa pomija przezroczyste części).
		CanTouch = false,
		CastShadow = false,
	})
end

local function post(parent: Instance, at: Vector3, height: number, diameter: number)
	make(parent, {
		Name = "FencePost",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = CFrame.new(at + Vector3.new(0, height / 2, 0)) * VERTICAL,
		Color = Palette.log,
		CanCollide = false,
		CanTouch = false,
	})
end

-- Płot od a do b (punkty na ziemi): słupki co ok. POST_SPACING i dwie żerdzie
local function fence(parent: Instance, a: Vector3, b: Vector3)
	local length = (b - a).Magnitude
	if length < 0.5 then
		return
	end
	local count = math.max(1, math.floor(length / POST_SPACING + 0.5))
	for i = 0, count do
		post(parent, a:Lerp(b, i / count), FENCE_H, 0.5)
	end
	local mid = (a + b) / 2
	for _, y in { 1.1, 2.2 } do
		make(parent, {
			Name = "FenceRail",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(length, 0.28, 0.28),
			-- Walec leży wzdłuż osi X: lookAt kieruje -Z wzdłuż płotu, obrót o 90° kładzie na nim oś X
			CFrame = CFrame.lookAt(mid + Vector3.new(0, y, 0), b + Vector3.new(0, y, 0)) * CFrame.Angles(0, math.rad(90), 0),
			Color = Palette.logEnd,
			CanCollide = false,
			CanTouch = false,
		})
	end
	-- Jedna gładka ściana na cały odcinek (od ziemi do wierzchu słupków, z zapasem na końcach)
	collider(parent, "FenceCollider", Vector3.new(0.7, FENCE_H, length + 0.7), CFrame.lookAt(mid + Vector3.new(0, FENCE_H / 2, 0), b + Vector3.new(0, FENCE_H / 2, 0)))
end

local function flowerBed(parent: Instance, cf: CFrame, length: number, rng: Random)
	make(parent, {
		Name = "FlowerBed",
		Size = Vector3.new(length, 0.35, 1.6),
		CFrame = cf * CFrame.new(0, 0.12, 0),
		Color = SOIL,
		CanQuery = false,
	})
	local count = math.floor(length / 1.1)
	for i = 1, count do
		local x = -length / 2 + (i - 0.5) * length / count
		local top = cf * CFrame.new(x + rng:NextNumber(-0.2, 0.2), 0, rng:NextNumber(-0.35, 0.35))
		local height = rng:NextNumber(0.6, 1.1)
		decor(make(parent, {
			Name = "FlowerStem",
			Size = Vector3.new(0.12, height, 0.12),
			CFrame = top * CFrame.new(0, 0.3 + height / 2, 0),
			Color = Color3.fromRGB(70, 120, 56),
		}))
		decor(make(parent, {
			Name = "Flower",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * rng:NextNumber(0.5, 0.75),
			CFrame = top * CFrame.new(0, 0.3 + height, 0),
			Color = FLOWERS[rng:NextInteger(1, #FLOWERS)],
		}))
	end
end

-- Skrzynia na monety przy furtce: drewniana, z metalowymi okuciami i kupką monet na wieku
local function chest(parent: Instance, cf: CFrame): Part
	local metal = Palette.metal
	local body = make(parent, {
		Name = "Chest",
		Size = Vector3.new(2.6, 1.6, 1.8),
		CFrame = cf * CFrame.new(0, 0.8, 0),
		Color = Palette.plankDark,
	})
	make(parent, {
		Name = "ChestLid",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2.6, 1.8, 1.8),
		CFrame = cf * CFrame.new(0, 1.6, 0),
		Color = Palette.plank,
		CanCollide = false,
	})
	for _, x in { -0.9, 0.9 } do
		decor(make(parent, { Name = "ChestBand", Size = Vector3.new(0.22, 2.75, 1.9), CFrame = cf * CFrame.new(x, 1.25, 0), Color = metal }))
	end
	decor(make(parent, { Name = "ChestLock", Size = Vector3.new(0.5, 0.6, 0.2), CFrame = cf * CFrame.new(0, 1.3, -0.95), Color = Color3.fromRGB(230, 180, 60) }))
	for i = 1, 5 do
		decor(make(parent, {
			Name = "Coin",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.14, 0.6, 0.6),
			CFrame = cf * CFrame.new((i - 3) * 0.32, 2.55 + (i % 2) * 0.12, (i % 3 - 1) * 0.25) * VERTICAL,
			Color = Color3.fromRGB(255, 205, 60),
			Material = Enum.Material.Neon,
		}))
	end
	return body
end

-- cf: środek ogródka na ziemi, -Z w stronę furtki. size: bok kwadratu. beds: ile grządek zbudować.
function Garden.build(parent: Instance, cf: CFrame, size: number, beds: number, rng: Random): Model
	local m = Instance.new("Model")
	m.Name = "Garden"
	local half = size / 2

	-- Trawa ogródka, żwirowa dróżka od furtki do grządek
	make(m, {
		Name = "GardenGrass",
		Size = Vector3.new(size, 0.2, size),
		CFrame = cf * CFrame.new(0, -0.02, 0),
		Color = GRASS,
		CanQuery = false,
	})
	decor(make(m, {
		Name = "GardenPath",
		Size = Vector3.new(GATE_HALF * 2 - 0.4, 0.2, half - 6),
		CFrame = cf * CFrame.new(0, 0.01, -half + (half - 6) / 2),
		Color = GRAVEL,
	}))

	-- Płot z furtką pośrodku boku -Z
	local function at(x: number, z: number): Vector3
		return (cf * CFrame.new(x, 0, z)).Position
	end
	fence(m, at(-half, -half), at(-GATE_HALF, -half))
	fence(m, at(GATE_HALF, -half), at(half, -half))
	fence(m, at(-half, half), at(half, half))
	fence(m, at(-half, -half), at(-half, half))
	fence(m, at(half, -half), at(half, half))

	-- Furtka: dwa wyższe słupki, belka i tabliczka z imieniem (napis dokłada GardenService)
	local gateH = 11.2 -- wysoka brama (wcześniej 5,6)
	for _, side in { -1, 1 } do
		post(m, at(side * GATE_HALF, -half), gateH, 0.75)
		collider(m, "GateCollider", Vector3.new(0.95, gateH, 0.95), cf * CFrame.new(side * GATE_HALF, gateH / 2, -half))
	end
	make(m, {
		Name = "GateBeam",
		Size = Vector3.new(GATE_HALF * 2 + 1.2, 0.5, 0.5),
		CFrame = cf * CFrame.new(0, gateH - 0.25, -half),
		Color = Palette.log,
		CanCollide = false,
		CanTouch = false,
	})
	collider(m, "GateCollider", Vector3.new(GATE_HALF * 2 + 1.2, 0.6, 0.8), cf * CFrame.new(0, gateH - 0.25, -half))
	local sign = make(m, {
		Name = "OwnerSign",
		Size = Vector3.new(GATE_HALF * 2 - 0.2, 1.2, 0.22),
		CFrame = cf * CFrame.new(0, gateH - 1.2, -half - 0.1),
		Color = Palette.signWood,
		CanCollide = false,
	})
	Props.hangingLantern(m, at(GATE_HALF + 0.9, -half - 0.6) + Vector3.new(0, gateH - 0.3, 0), 18)

	-- Rabatki z kwiatami wzdłuż boków (w tylnej części, przód zostaje na skrzynię) i krzaki w rogach
	for _, side in { -1, 1 } do
		flowerBed(m, cf * CFrame.new(side * (half - 1.3), 0, 2.5) * CFrame.Angles(0, math.rad(90), 0), size - 12, rng)
		Props.bush(m, at(side * (half - 1.8), half - 1.8), rng:NextNumber(0.75, 0.95), rng, 0)
	end

	-- Kilka kamieni przed furtką, żeby było widać, którędy wejść
	for i = 1, 3 do
		local d = rng:NextNumber(1.5, 2.1)
		decor(make(m, {
			Name = "PathStone",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, d, d * 0.9),
			CFrame = cf * CFrame.new(rng:NextNumber(-0.4, 0.4), -0.04, -half - 0.6 - i * 2.2) * VERTICAL,
			Color = Palette.stone:Lerp(Palette.ground[1], rng:NextNumber(0.3, 0.5)),
		}))
	end

	-- Grządki w tylnej części ogródka
	Beds.build(m, cf * CFrame.new(0, 0, 3), beds)

	-- Skrzynia na monety po lewej od furtki (patrząc od wejścia), latarnia nad nią
	chest(m, cf * CFrame.new(-(half - 3.2), 0, -half + 3.2) * CFrame.Angles(0, math.rad(20), 0))

	-- Niewidoczny punkt między furtką a grządkami: przyciski sadzenia i kradzieży, tabliczka z dochodem
	local hub = make(m, {
		Name = "Hub",
		Size = Vector3.new(1, 1, 1),
		CFrame = cf * CFrame.new(0, 2.4, -half + 6.5),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
	})
	sign.Name = "OwnerSign"
	m.PrimaryPart = hub

	m.Parent = parent
	return m
end

return Garden
