--!strict
-- Buduje mapę przy starcie serwera: polana z chatką, kręta ścieżka z latarniami,
-- bramy na granicach stref i las, który robi się coraz gęstszy i ciemniejszy.
--
-- Gdy zrobicie prawdziwą mapę w Studio, nazwijcie folder w Workspace "Map"
-- i dodajcie w nim część "SpawnPoint" oraz folder "Spots" z częściami,
-- których atrybut "Zone" mówi, do której strefy należą. Wtedy builder nic nie buduje.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
local World = script.Parent:WaitForChild("World")
local Palette = require(World:WaitForChild("Palette"))
local Props = require(World:WaitForChild("Props"))
local Cabin = require(World:WaitForChild("Cabin"))
local Grove = require(World:WaitForChild("Grove"))
local Garden = require(World:WaitForChild("Garden"))
local Cave = require(World:WaitForChild("Cave"))
local Swamp = require(World:WaitForChild("Swamp"))

export type Spot = {
	id: string,
	zone: number,
	position: Vector3,
	grove: boolean?, -- miejsce w Gnieździe Leszego (rośnie tam Korona Leszego)
	lair: boolean?, -- miejsce w Skarbcu Skarbnika (rośnie tam Złota Trufla)
	guardian: string?, -- miejsce w legowisku innego strażnika (np. "utopiec")
}

-- Świat za portalem: obóz (lądowanie), portal wejściowy, skrót na Placu Portali, portal powrotny
export type WorldInfo = {
	camp: CFrame?,
	portal: Vector3?,
	shortcut: Vector3?,
	returnPortal: Vector3?,
}

-- Legowisko strażnika: skąd rusza i jego uśpiony posąg
export type GuardianInfo = {
	origin: Vector3?,
	statue: Model?,
}

export type RackInfo = {
	id: number,
	model: Model,
}

export type MapInfo = {
	spawnCFrame: CFrame,
	spots: { Spot },
	spotById: { [string]: Spot },
	groveCenter: Vector3?, -- skąd rusza Leszy; nil = mapa bez gniazda
	leszyStatue: Model?,
	gardens: { RackInfo },
	campCFrame: CFrame?, -- obozowisko w jaskini; nil = mapa bez jaskini
	lairCenter: Vector3?, -- skąd rusza Skarbnik
	skarbnikStatue: Model?,
	portal: Vector3?, -- portal do jaskini (w lesie, za Gniazdem Leszego)
	shortcut: Vector3?, -- skrót do jaskini za chatką (dla tych, którzy ją już odkryli)
	returnPortal: Vector3?, -- portal powrotny w obozowisku
	worlds: { [string]: WorldInfo },
	guardians: { [string]: GuardianInfo },
}

-- Las to strefy z world = "forest"; jaskinię buduje World/Cave
local FOREST_ZONES: { number } = {}
for index, zone in Config.Zones do
	if zone.world == "forest" then
		table.insert(FOREST_ZONES, index)
	end
end
local FOREST_FIRST = Config.Zones[FOREST_ZONES[1]]
local FOREST_LAST = Config.Zones[FOREST_ZONES[#FOREST_ZONES]]

type Builder = (Instance, Vector3, number, Random, number) -> ()

local MapBuilder = {}

-- Co rośnie w której strefie: rodzaj drzewa z wagą i zakresem skali, ilość drobiazgów
local TREE_BUILDERS: { [string]: Builder } = {
	pine = Props.pine,
	birch = Props.birch,
	oak = Props.oak,
	deadTree = Props.deadTree,
}
local PROP_BUILDERS: { [string]: Builder } = {
	rock = Props.rock,
	bush = Props.bush,
	fern = Props.fern,
	grass = Props.grass,
	log = Props.log,
	stump = Props.stump,
}
local PROP_RADIUS = { rock = 3, bush = 2.6, fern = 2, grass = 0.8, log = 4, stump = 1.8 }
local PROP_ORDER = { "log", "rock", "stump", "bush", "fern", "grass" }

type TreeMix = { { kind: string, weight: number, min: number, max: number } }
type Recipe = { trees: TreeMix, props: { [string]: number }, glow: number }

local RECIPES: { [number]: Recipe } = {
	[1] = { -- polana wokół chatki
		trees = {
			{ kind = "birch", weight = 4, min = 0.9, max = 1.2 },
			{ kind = "oak", weight = 3, min = 0.9, max = 1.2 },
			{ kind = "pine", weight = 3, min = 1, max = 1.3 },
		},
		props = { rock = 4, bush = 6, fern = 6, grass = 40, stump = 3 },
		glow = 0,
	},
	[2] = { -- skraj lasu: jasno, brzozy i jesienne dęby
		trees = {
			{ kind = "birch", weight = 4, min = 0.9, max = 1.25 },
			{ kind = "oak", weight = 3, min = 0.9, max = 1.2 },
			{ kind = "pine", weight = 3, min = 0.9, max = 1.3 },
		},
		props = { rock = 10, bush = 14, fern = 14, grass = 45, log = 4, stump = 5 },
		glow = 0,
	},
	[3] = { -- gęstwina: sosny, krzaki, paprocie
		trees = {
			{ kind = "pine", weight = 6, min = 1, max = 1.5 },
			{ kind = "oak", weight = 2.5, min = 1, max = 1.3 },
			{ kind = "birch", weight = 1.5, min = 1, max = 1.3 },
		},
		props = { rock = 14, bush = 22, fern = 28, grass = 30, log = 7, stump = 6 },
		glow = 5,
	},
	[4] = { -- mroczny jar: martwe drzewa, skały, świecące grzyby
		trees = {
			{ kind = "pine", weight = 5, min = 1.1, max = 1.7 },
			{ kind = "deadTree", weight = 4, min = 1, max = 1.4 },
			{ kind = "birch", weight = 1, min = 0.9, max = 1.2 },
		},
		props = { rock = 26, bush = 8, fern = 18, grass = 10, log = 9, stump = 8 },
		glow = 14,
	},
}

-- Promień korony drzewa przy skali 1 (studs). Drzewa stoją tak, żeby korony się nie stykały;
-- krzaki, paprocie i grzyby mogą rosnąć pod koroną, byle nie w pniu.
local CANOPY: { [string]: number } = { pine = 5.2, birch = 5, oak = 6.8, deadTree = 4.5 }
local TRUNK = 1.3

local CLEARING_TREES = 50
local LANTERN_POSTS_Z = { 8, 30, 52, 74, 96 }
local PATH_END_Z = 125

-- ===== Pilnowanie, żeby rzeczy na siebie nie nachodziły =====

-- r: zajęty promień (dla drzew: korona), trunk: promień pnia (tylko drzewa)
type Occupant = { x: number, z: number, r: number, trunk: number? }
type Rect = { x1: number, x2: number, z1: number, z2: number }

local occupants: { Occupant } = {}
local reserved: { Rect } = {}

local function resetSpace()
	occupants = {}
	reserved = {}
end

-- trunk podany = sprawdzamy drzewo: jego korona (r) nie może wejść na koronę innego drzewa
-- ani na zarezerwowane miejsca, a do krzaków i grzybów liczy się tylko pień.
local function isFree(x: number, z: number, r: number, trunk: number?): boolean
	for _, rect in reserved do
		if x + r > rect.x1 and x - r < rect.x2 and z + r > rect.z1 and z - r < rect.z2 then
			return false
		end
	end
	local self = trunk or r
	if z < PATH_END_Z and z > -6 and math.abs(x - Props.pathX(z)) < 2.6 + self then
		return false
	end
	for _, o in occupants do
		local dx, dz = o.x - x, o.z - z
		local min
		if o.trunk and not trunk then
			min = o.trunk + r -- krzak przy pniu
		elseif trunk and not o.trunk then
			min = o.r + trunk -- pień przy krzaku albo grzybie
		else
			min = o.r + r -- korona przy koronie, krzak przy krzaku
		end
		if dx * dx + dz * dz < min * min then
			return false
		end
	end
	return true
end

local function occupy(x: number, z: number, r: number, trunk: number?)
	table.insert(occupants, { x = x, z = z, r = r, trunk = trunk })
end

local function pickTree(mix: TreeMix, rng: Random): (string, number)
	local total = 0
	for _, t in mix do
		total += t.weight
	end
	local roll = rng:NextNumber() * total
	for _, t in mix do
		roll -= t.weight
		if roll <= 0 then
			return t.kind, rng:NextNumber(t.min, t.max)
		end
	end
	local last = mix[#mix]
	return last.kind, rng:NextNumber(last.min, last.max)
end

-- Szuka wolnego miejsca w prostokącie. accept() pozwala dodać własny warunek.
local function findSpot(
	rng: Random,
	x1: number,
	x2: number,
	z1: number,
	z2: number,
	r: number,
	accept: ((number, number) -> boolean)?,
	trunk: number?
): (number?, number?)
	for _ = 1, 30 do
		local x = rng:NextNumber(x1, x2)
		local z = rng:NextNumber(z1, z2)
		if (not accept or accept(x, z)) and isFree(x, z, r, trunk) then
			return x, z
		end
	end
	return nil, nil
end

-- ===== Budowa =====

local function buildGround(parent: Instance)
	local halfWidth = Config.ForestHalfWidth
	for _, zoneIndex in FOREST_ZONES do
		local zone = Config.Zones[zoneIndex]
		local length = zone.endZ - zone.startZ
		local ground = Instance.new("Part")
		ground.Name = "Ground_" .. zone.id
		ground.Anchored = true
		ground.Size = Vector3.new(halfWidth * 2, 2, length)
		ground.Position = Vector3.new(0, -1, zone.startZ + length / 2)
		ground.Color = Palette.ground[zoneIndex] or Palette.outerGround
		ground.Material = Enum.Material.SmoothPlastic
		ground.TopSurface = Enum.SurfaceType.Smooth
		ground.Parent = parent
	end
	-- Ziemia za brzegiem mapy (niżej, żeby nie migotała z ziemią stref)
	local outer = Instance.new("Part")
	outer.Name = "OuterGround"
	outer.Anchored = true
	outer.Size = Vector3.new(1400, 1, 1400)
	outer.Position = Vector3.new(0, -1.2, 200)
	outer.Color = Palette.outerGround
	outer.Material = Enum.Material.SmoothPlastic
	outer.TopSurface = Enum.SurfaceType.Smooth
	outer.CanCollide = false
	outer.Parent = parent
end

local function buildWalls(parent: Instance)
	local halfWidth = Config.ForestHalfWidth
	local first = FOREST_FIRST
	local last = FOREST_LAST
	local totalLength = last.endZ - first.startZ
	local centerZ = first.startZ + totalLength / 2
	local function wall(size: Vector3, position: Vector3)
		local w = Instance.new("Part")
		w.Name = "InvisibleWall"
		w.Anchored = true
		w.Transparency = 1
		w.Size = size
		w.Position = position
		w.Parent = parent
	end
	for _, side in { -1, 1 } do
		wall(Vector3.new(2, 60, totalLength), Vector3.new(side * (halfWidth + 1), 30, centerZ))
	end
	for _, z in { first.startZ - 1, last.endZ + 1 } do
		wall(Vector3.new(halfWidth * 2, 60, 2), Vector3.new(0, 30, z))
	end
end

-- Rząd dużych drzew na brzegach mapy: zasłania niewidzialne ściany.
-- Drzewa stoją korona przy koronie (bez nachodzenia), więc rząd wygląda jak gęsta ściana lasu.
-- Stawiamy je przed resztą lasu i zajmujemy ich miejsce, żeby las wewnątrz omijał obrzeże.
local function buildBorder(parent: Instance, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "Border"
	local halfWidth = Config.ForestHalfWidth
	local first = FOREST_FIRST
	local last = FOREST_LAST
	local function darknessAt(z: number): number
		return if z < first.endZ then 0.2 else Config.Zones[math.max(2, Economy.zoneIndexAt(z))].darkness
	end
	local GAP = 0.3

	-- Pnie nie mogą stać w miejscach zarezerwowanych (gniazdo, chatka); korony mogą nad nimi wisieć
	local function free(x: number, z: number, canopy: number): boolean
		for _, rect in reserved do
			if x + TRUNK > rect.x1 and x - TRUNK < rect.x2 and z + TRUNK > rect.z1 and z - TRUNK < rect.z2 then
				return false
			end
		end
		for _, o in occupants do
			local dx, dz = o.x - x, o.z - z
			-- Korona nie wchodzi na inne korony; grzyby i krzaki mogą być pod nią
			local min = if o.trunk then o.r + canopy else o.r + TRUNK
			if dx * dx + dz * dz < min * min then
				return false
			end
		end
		return true
	end

	local function plant(kind: string, x: number, z: number, scale: number, dark: number): boolean
		local canopy = CANOPY[kind] * scale
		if not free(x, z, canopy) then
			return false
		end
		TREE_BUILDERS[kind](folder, Vector3.new(x, 0, z), scale, rng, dark)
		occupy(x, z, canopy, TRUNK * scale)
		return true
	end

	-- Przód i tył mapy (w poprzek), potem boki (wzdłuż); narożniki zajmuje ten, kto pierwszy
	for _, edge in { { z = first.startZ + 3, dead = false }, { z = last.endZ - 3, dead = true } } do
		local x = -halfWidth + 2
		while x < halfWidth - 2 do
			local kind = if edge.dead and rng:NextNumber() < 0.4 then "deadTree" else "pine"
			local scale = rng:NextNumber(1.5, 1.9)
			local canopy = CANOPY[kind] * scale
			plant(kind, x + canopy, edge.z, scale, darknessAt(edge.z))
			x += canopy * 2 + GAP
		end
	end
	for _, side in { -1, 1 } do
		local z = first.startZ
		while z < last.endZ do
			local scale = rng:NextNumber(1.5, 1.9)
			local canopy = CANOPY.pine * scale
			if plant("pine", side * (halfWidth - 3), z + canopy, scale, darknessAt(z)) then
				z += canopy * 2 + GAP
			else
				z += 2 -- miejsce zajęte (narożnik): szukamy dalej
			end
		end
	end
	folder.Parent = parent
end

local function buildZoneDecor(parent: Instance, zoneIndex: number, rng: Random)
	local zone = Config.Zones[zoneIndex]
	local recipe = RECIPES[zoneIndex]
	if not recipe then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Decor_" .. zone.id
	local halfWidth = Config.ForestHalfWidth - 6
	local z1, z2 = zone.startZ + 2, zone.endZ - 2
	local accept: ((number, number) -> boolean)? = nil
	local treeCount = zone.treeCount
	if zoneIndex == 1 then
		-- Polana: drzewa tylko poza elipsą wokół chatki i ścieżki
		treeCount = CLEARING_TREES
		accept = function(x: number, z: number): boolean
			local ex, ez = x / 30, (z + 14) / 38
			return ex * ex + ez * ez > 1
		end
	end

	for _ = 1, treeCount do
		-- Najpierw gatunek i rozmiar, bo od nich zależy, ile miejsca zajmuje korona
		local kind, scale = pickTree(recipe.trees, rng)
		local canopy = CANOPY[kind] * scale
		local trunk = TRUNK * scale
		local x, z = findSpot(rng, -halfWidth, halfWidth, z1, z2, canopy, accept, trunk)
		if x and z then
			TREE_BUILDERS[kind](folder, Vector3.new(x, 0, z), scale, rng, zone.darkness)
			occupy(x, z, canopy, trunk)
		end
	end

	for _, kind in PROP_ORDER do
		local count = recipe.props[kind] or 0
		local radius = PROP_RADIUS[kind]
		for _ = 1, count do
			local x, z = findSpot(rng, -halfWidth, halfWidth, z1, z2, radius, if kind == "grass" then nil else accept)
			if x and z then
				PROP_BUILDERS[kind](folder, Vector3.new(x, 0, z), rng:NextNumber(0.85, 1.25), rng, zone.darkness)
				occupy(x, z, radius)
			end
		end
	end

	for _ = 1, recipe.glow do
		local x, z = findSpot(rng, -halfWidth, halfWidth, z1, z2, 2)
		if x and z then
			Props.glowCluster(folder, Vector3.new(x, 0, z), rng)
			occupy(x, z, 2)
		end
	end

	folder.Parent = parent
end

local function buildSpots(rng: Random): { Spot }
	local spots: { Spot } = {}
	for zoneIndex, zone in Config.Zones do
		local halfWidth = (
			if zone.world == "cave" then Config.Cave.halfWidth
			elseif zone.world == "swamp" then Config.Swamp.halfWidth
			else Config.ForestHalfWidth
		) - 8
		for i = 1, zone.spotCount do
			local x, z = findSpot(rng, -halfWidth, halfWidth, zone.startZ + 6, zone.endZ - 6, 3)
			if x and z then
				occupy(x, z, 3)
				table.insert(spots, {
					id = string.format("%s_%d", zone.id, i),
					zone = zoneIndex,
					position = Vector3.new(x, 0, z),
				})
			end
		end
	end
	return spots
end

-- Gniazdo Leszego: miejsca na korony w kole wokół środka
local function groveCenter(): Vector3
	return Vector3.new(Config.Grove.centerX, 0, Config.Grove.centerZ)
end

local function buildGroveSpots(): { Spot }
	local spots: { Spot } = {}
	local center = groveCenter()
	for i = 1, Config.Grove.spots do
		local angle = (i - 1) / Config.Grove.spots * math.pi * 2 + math.pi / Config.Grove.spots
		local position = center + Vector3.new(math.sin(angle), 0, math.cos(angle)) * Config.Grove.spotRadius
		occupy(position.X, position.Z, 3)
		table.insert(spots, { id = "grove_" .. i, zone = Economy.zoneIndexAt(position.Z), position = position, grove = true })
	end
	return spots
end

-- Skarbiec Skarbnika: miejsca na Złote Trufle w kole wokół środka (jak w gnieździe Leszego)
local function lairCenter(): Vector3
	return Vector3.new(Config.Lair.centerX, 0, Config.Lair.centerZ)
end

local function buildLairSpots(): { Spot }
	local spots: { Spot } = {}
	local center = lairCenter()
	for i = 1, Config.Lair.spots do
		local angle = (i - 1) / Config.Lair.spots * math.pi * 2 + math.pi / Config.Lair.spots
		local position = center + Vector3.new(math.sin(angle), 0, math.cos(angle)) * Config.Lair.spotRadius
		occupy(position.X, position.Z, 3)
		table.insert(spots, { id = "lair_" .. i, zone = Economy.zoneIndexAt(position.Z), position = position, lair = true })
	end
	return spots
end

-- Wysepka Utopca: Kielichy rosną w kole na trawie (wyspa jest trochę nad wodą)
local ISLAND_TOP = 0.6
local function buildUtopiecSpots(): { Spot }
	local spots: { Spot } = {}
	local lair = Config.UtopiecLair
	local center = Vector3.new(lair.centerX, ISLAND_TOP, lair.centerZ)
	for i = 1, lair.spots do
		local angle = (i - 1) / lair.spots * math.pi * 2 + math.pi / lair.spots
		local position = center + Vector3.new(math.sin(angle), 0, math.cos(angle)) * lair.spotRadius
		occupy(position.X, position.Z, 3)
		table.insert(spots, { id = "utopiec_" .. i, zone = Economy.zoneIndexAt(position.Z), position = position, guardian = "utopiec" })
	end
	return spots
end

-- Ogródki graczy po bokach chatki, każdy furtką w stronę środka polany (x = 0)
local function gardenCFrame(plot: { x: number, z: number }): CFrame
	return CFrame.lookAt(Vector3.new(plot.x, 0, plot.z), Vector3.new(0, 0, plot.z))
end

local function reserveGardens()
	local half = Config.Garden.size / 2
	for _, plot in Config.Garden.plots do
		-- Ogródek z zapasem i miejsce przed furtką (od strony środka polany)
		local toward = if plot.x < 0 then 1 else -1
		local x1 = math.min(plot.x - half - 2, plot.x + toward * (half + 7))
		local x2 = math.max(plot.x + half + 2, plot.x + toward * (half + 7))
		table.insert(reserved, { x1 = x1, x2 = x2, z1 = plot.z - half - 2, z2 = plot.z + half + 2 })
	end
end

local function buildGardens(parent: Instance): { RackInfo }
	local folder = Instance.new("Folder")
	folder.Name = "Gardens"
	local rng = Random.new(Config.SpotSeed + 3)
	local racks: { RackInfo } = {}
	for index, plot in Config.Garden.plots do
		local model = Garden.build(folder, gardenCFrame(plot), Config.Garden.size, Config.Garden.maxBeds, rng)
		model.Name = "Garden_" .. index
		table.insert(racks, { id = index, model = model })
	end
	folder.Parent = parent
	return racks
end

local function readExistingMap(map: Folder): MapInfo?
	local spawnPart = map:FindFirstChild("SpawnPoint")
	local spotsFolder = map:FindFirstChild("Spots")
	if not (spawnPart and spawnPart:IsA("BasePart") and spotsFolder) then
		return nil
	end
	local spots: { Spot } = {}
	local grove: Vector3? = nil
	for i, child in spotsFolder:GetChildren() do
		local zone = child:GetAttribute("Zone")
		if child:IsA("BasePart") and typeof(zone) == "number" then
			-- Atrybut Grove = true: miejsce na Koronę Leszego (Leszy rusza z pierwszego takiego miejsca)
			local isGrove = child:GetAttribute("Grove") == true
			table.insert(spots, { id = "custom_" .. i, zone = zone, position = child.Position, grove = isGrove })
			if isGrove and not grove then
				grove = child.Position
			end
			child.Transparency = 1
			child.CanCollide = false
		end
	end
	local spotById = {}
	for _, spot in spots do
		spotById[spot.id] = spot
	end
	local racks: { RackInfo } = {}
	-- Własne ogródki z folderu Map/Gardens (modele z PrimaryPart "Hub" i grządkami Slot<i>)
	local racksFolder = map:FindFirstChild("Gardens")
	if racksFolder then
		for index, child in racksFolder:GetChildren() do
			if child:IsA("Model") and child.PrimaryPart then
				table.insert(racks, { id = index, model = child })
			end
		end
	else
		racks = buildGardens(map)
	end
	return {
		spawnCFrame = spawnPart.CFrame + Vector3.new(0, 3, 0),
		spots = spots,
		spotById = spotById,
		groveCenter = grove,
		gardens = racks,
		worlds = {}, -- własna mapa nie ma jaskini ani bagien
		guardians = { leszy = { origin = grove } },
	}
end

-- Usuwa to, co wkłada szablon Baseplate w Studio, a co psuje naszą mapę
local function removeTemplateLeftovers()
	-- Domyślna płyta leży na tej samej wysokości co nasza ziemia (y = 0).
	-- Dwie powierzchnie w jednym miejscu walczą o widoczność i tekstury migoczą.
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate:Destroy()
	end
	-- Szablon ma też własny SpawnLocation na środku polany. Roblox losuje między punktami
	-- odrodzenia, więc gracz czasem pojawiał się przed chatką, odwrócony od lasu.
	-- Nasz punkt leży w folderze Map, więc bezpośrednie dzieci Workspace można usunąć.
	for _, child in Workspace:GetChildren() do
		if child:IsA("SpawnLocation") then
			child:Destroy()
		end
	end
end

-- Kamienie ścieżki po łamanej (od ganku za chatkę na Plac Portali)
local function stonePath(parent: Instance, points: { Vector3 }, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "PlazaPath"
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local length = (b - a).Magnitude
		local step = 0
		while step < length do
			local p = a:Lerp(b, step / length) + Vector3.new(rng:NextNumber(-0.6, 0.6), 0, rng:NextNumber(-0.6, 0.6))
			local d = rng:NextNumber(1.8, 2.8)
			local stone = Instance.new("Part")
			stone.Shape = Enum.PartType.Cylinder
			stone.Anchored = true
			stone.CanCollide = false
			stone.CanQuery = false
			stone.CastShadow = false
			stone.Material = Enum.Material.SmoothPlastic
			stone.Size = Vector3.new(0.3, d, d * rng:NextNumber(0.8, 1))
			stone.CFrame = CFrame.new(p.X, -0.04, p.Z) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(rng:NextNumber(0, math.pi * 2), 0, 0)
			stone.Color = Palette.stone:Lerp(Palette.ground[1], rng:NextNumber(0.3, 0.5))
			stone.Parent = folder
			step += rng:NextNumber(2.4, 3.2)
		end
	end
	folder.Parent = parent
end

-- Plac Portali: okrągły bruk, latarnie dookoła, skrót do jaskini na środku i fundamenty pod kolejne portale.
-- Zwraca pozycję skrótu.
local function buildPortalPlaza(parent: Instance, rng: Random): { [string]: Vector3 }
	local plaza = Config.PortalPlaza
	local center = Vector3.new(plaza.center.x, 0, plaza.center.z)
	local folder = Instance.new("Folder")
	folder.Name = "PortalPlaza"
	table.insert(reserved, { x1 = center.X - plaza.radius - 2, x2 = center.X + plaza.radius + 2, z1 = center.Z - plaza.radius + 4, z2 = center.Z + plaza.radius })

	local paving = Instance.new("Part")
	paving.Name = "Paving"
	paving.Shape = Enum.PartType.Cylinder
	paving.Anchored = true
	paving.CanCollide = false
	paving.CastShadow = false
	paving.Size = Vector3.new(0.2, plaza.radius * 2, plaza.radius * 2)
	paving.CFrame = CFrame.new(center + Vector3.new(0, -0.02, 0)) * CFrame.Angles(0, 0, math.rad(90))
	paving.Color = Palette.stone:Lerp(Palette.ground[1], 0.35)
	paving.Material = Enum.Material.Cobblestone
	paving.Parent = folder

	-- Latarnie na obwodzie placu
	for _, degrees in { 25, 155, 205, 245, 295, 335 } do
		local angle = math.rad(degrees)
		local pos = center + Vector3.new(math.cos(angle) * (plaza.radius - 2), 0, math.sin(angle) * (plaza.radius - 2))
		Props.lanternPost(folder, pos, math.atan2(-(center.Z - pos.Z), center.X - pos.X))
	end

	local z = Config.Cave.shortcut.z
	local shortcuts: { [string]: Vector3 } = {}
	local SHORTCUT_LOOK: { [string]: { sign: string, color: Color3 } } = {
		cave = { sign = "SIGN_PORTAL_SHORTCUT", color = Color3.fromRGB(160, 90, 255) },
		swamp = { sign = "SIGN_PORTAL_SHORTCUT_SWAMP", color = Color3.fromRGB(90, 230, 140) },
	}
	for _, x in plaza.slots do
		-- Z chatki idzie się na plac w stronę -Z, więc przód portali patrzy na +Z
		local cf = CFrame.new(x, 0, z) * CFrame.Angles(0, math.pi, 0)
		local world = plaza.worlds[x]
		local look = world and SHORTCUT_LOOK[world]
		if world and look then
			local portalModel = Cave.portal(folder, cf, look.sign, look.color, "ShortcutSwirl")
			local swirl = portalModel:FindFirstChild("Swirl")
			if swirl then
				swirl:SetAttribute("World", world)
				swirl:SetAttribute("OpenColor", look.color)
			end
			shortcuts[world] = Vector3.new(x, 0, z)
		else
			-- Fundament pod przyszły portal z tabliczką „Wkrótce...”
			local base = Instance.new("Part")
			base.Name = "PortalFoundation"
			base.Shape = Enum.PartType.Cylinder
			base.Anchored = true
			base.Size = Vector3.new(0.8, 12, 12)
			base.CFrame = CFrame.new(x, 0.4, z) * CFrame.Angles(0, 0, math.rad(90))
			base.Color = Color3.fromRGB(110, 104, 118)
			base.Material = Enum.Material.Slate
			base.Parent = folder
			for _, side in { -1, 1 } do
				local post = Instance.new("Part")
				post.Anchored = true
				post.Size = Vector3.new(0.4, 4, 0.4)
				post.Position = Vector3.new(x + side * 2.6, 2.8, z + 4.6) -- za tabliczką, żeby nie zasłaniać napisu
				post.Color = Palette.log
				post.Parent = folder
			end
			Props.signBoard(folder, CFrame.new(x, 4.2, z + 5) * CFrame.Angles(0, math.pi, 0), Vector3.new(6, 1.4, 0.3), "SIGN_PORTAL_SOON", Enum.NormalId.Front)
		end
	end
	folder.Parent = parent

	-- Ścieżka z ganku wzdłuż boku chatki na plac
	stonePath(parent, {
		Vector3.new(Cabin.HALF_W + 4, 0, Cabin.FRONT_Z + 4),
		Vector3.new(Cabin.HALF_W + 4, 0, Cabin.BACK_Z - 4),
		Vector3.new(6, 0, center.Z + plaza.radius - 2),
	}, rng)
	return shortcuts
end

function MapBuilder.build(): MapInfo
	removeTemplateLeftovers()

	local existing = Workspace:FindFirstChild("Map")
	if existing and existing:IsA("Folder") then
		local info = readExistingMap(existing)
		if info then
			return info
		end
		warn("[MapBuilder] Folder Map nie ma SpawnPoint/Spots, buduję mapę od nowa")
		existing:Destroy()
	end

	resetSpace()
	local map = Instance.new("Folder")
	map.Name = "Map"

	buildGround(map)
	buildWalls(map)

	-- Chatka i jej otoczenie są zarezerwowane, żeby nic tam nie wyrosło
	local spawnCFrame = Cabin.build(map)
	table.insert(reserved, { x1 = -Cabin.HALF_W - 4, x2 = Cabin.HALF_W + 4, z1 = Cabin.BACK_Z - 5, z2 = Cabin.FRONT_Z + 10 })

	-- Bramy na początku każdej strefy leśnej
	for i = 2, #FOREST_ZONES do
		local zone = Config.Zones[FOREST_ZONES[i]]
		Props.gate(map, zone.startZ, zone.key)
		table.insert(reserved, { x1 = -9.5, x2 = 9.5, z1 = zone.startZ - 2.5, z2 = zone.startZ + 2.5 })
	end

	-- Ogródki graczy z suszarniami po obu stronach chatki
	reserveGardens()
	local racks = buildGardens(map)

	local decorRng = Random.new(Config.SpotSeed + 1)

	-- Gniazdo Leszego: w środku i za kręgiem (posąg) nic nie rośnie
	local center = groveCenter()
	local groveR = Config.Grove.radius
	table.insert(reserved, { x1 = center.X - groveR - 3, x2 = center.X + groveR + 3, z1 = center.Z - groveR - 5, z2 = center.Z + groveR + 8 })
	local leszyStatue = Grove.build(map, center, groveR, Random.new(Config.SpotSeed + 2))

	-- Portal do jaskini za gniazdem, napisem w stronę nadchodzącego gracza
	local portalDef = Config.Cave.portal
	local portal = Vector3.new(portalDef.x, 0, portalDef.z)
	table.insert(reserved, { x1 = portal.X - 8, x2 = portal.X + 8, z1 = portal.Z - 5, z2 = FOREST_LAST.endZ })
	Cave.portal(map, CFrame.new(portal), "SIGN_PORTAL", Color3.fromRGB(160, 90, 255))

	-- Plac Portali za chatką: skrót do jaskini (działa dla tych, którzy już tam byli) i miejsca na kolejne światy
	local shortcuts = buildPortalPlaza(map, decorRng)

	-- Jaskinia i bagna: najpierw rezerwacje (obozy, ścieżki, woda), żeby grzyby nie wyrosły w wodzie
	for _, rect in Cave.reservedRects() do
		table.insert(reserved, rect)
	end
	for _, rect in Swamp.reservedRects() do
		table.insert(reserved, rect)
	end
	-- Portal na bagna w Sztolni, za skarbcem Skarbnika
	local swampPortalDef = Config.Swamp.portal
	local swampPortal = Vector3.new(swampPortalDef.x, 0, swampPortalDef.z)
	table.insert(reserved, { x1 = swampPortal.X - 16, x2 = swampPortal.X + 16, z1 = swampPortal.Z - 6, z2 = swampPortal.Z + 12 })

	-- Ścieżka z latarniami od ganku w głąb skraju lasu

	Props.path(map, Cabin.FRONT_Z + 9, PATH_END_Z, decorRng)
	for i, z in LANTERN_POSTS_Z do
		local side = if i % 2 == 0 then 1 else -1
		local x = Props.pathX(z) + side * 3.4
		Props.lanternPost(map, Vector3.new(x, 0, z), if side == 1 then math.pi else 0)
		occupy(x, z, 2)
	end

	-- Grzyby najpierw (stałe ziarno), potem las omija je szerokim łukiem
	local spots = buildSpots(Random.new(Config.SpotSeed))
	for _, spot in buildGroveSpots() do
		table.insert(spots, spot)
	end
	for _, spot in buildLairSpots() do
		table.insert(spots, spot)
	end
	for _, spot in buildUtopiecSpots() do
		table.insert(spots, spot)
	end
	-- Obrzeże przed lasem: las wewnątrz omija korony obrzeża
	buildBorder(map, decorRng)
	for _, zoneIndex in FOREST_ZONES do
		buildZoneDecor(map, zoneIndex, decorRng)
	end

	local placeApi = {
		place = function(rng: Random, x1: number, x2: number, z1: number, z2: number, radius: number)
			local x, z = findSpot(rng, x1, x2, z1, z2, radius)
			if x and z then
				occupy(x, z, radius)
			end
			return x, z
		end,
	}
	local campCFrame, skarbnikStatue = Cave.build(map, Random.new(Config.SpotSeed + 5), placeApi)
	Cave.portal(map, CFrame.new(swampPortal), "SIGN_PORTAL_SWAMP", Color3.fromRGB(90, 230, 140))

	local swampCamp, utopiecStatue = Swamp.build(map, Random.new(Config.SpotSeed + 9), placeApi)
	local swampReturnDef = Config.Swamp.returnPortal
	local swampReturn = Vector3.new(swampReturnDef.x, 0.6, swampReturnDef.z)
	Cave.portal(map, CFrame.new(swampReturn) * CFrame.Angles(0, math.pi, 0), "SIGN_PORTAL_HOME", Color3.fromRGB(255, 190, 90))
	local returnDef = Config.Cave.returnPortal
	local returnPortal = Vector3.new(returnDef.x, 0, returnDef.z)
	-- Z obozowiska idzie się do portalu w stronę -Z, więc napis patrzy na +Z
	Cave.portal(map, CFrame.new(returnPortal) * CFrame.Angles(0, math.pi, 0), "SIGN_PORTAL_HOME", Color3.fromRGB(255, 190, 90))

	-- Miejsce startu: w chatce, twarzą do drzwi i lasu
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "SpawnPoint"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(5, 0.2, 5)
	spawn.CFrame = CFrame.new(spawnCFrame.Position.X, 1.1, spawnCFrame.Position.Z) * spawnCFrame.Rotation
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CanTouch = false
	spawn.Parent = map

	map.Parent = Workspace

	local spotById = {}
	for _, spot in spots do
		spotById[spot.id] = spot
	end

	return {
		spawnCFrame = spawnCFrame,
		spots = spots,
		spotById = spotById,
		groveCenter = center,
		leszyStatue = leszyStatue,
		gardens = racks,
		campCFrame = campCFrame,
		lairCenter = lairCenter(),
		skarbnikStatue = skarbnikStatue,
		portal = portal,
		shortcut = shortcuts.cave,
		returnPortal = returnPortal,
		worlds = {
			cave = { camp = campCFrame, portal = portal, shortcut = shortcuts.cave, returnPortal = returnPortal },
			swamp = { camp = swampCamp, portal = swampPortal, shortcut = shortcuts.swamp, returnPortal = swampReturn },
		},
		guardians = {
			leszy = { origin = center, statue = leszyStatue },
			skarbnik = { origin = lairCenter(), statue = skarbnikStatue },
			utopiec = { origin = Vector3.new(Config.UtopiecLair.centerX, 0, Config.UtopiecLair.centerZ), statue = utopiecStatue },
		},
	}
end

return MapBuilder
