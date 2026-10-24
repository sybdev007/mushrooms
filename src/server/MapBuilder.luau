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
local Rack = require(World:WaitForChild("Rack"))

export type Spot = {
	id: string,
	zone: number,
	position: Vector3,
	grove: boolean?, -- miejsce w Gnieździe Leszego (rośnie tam Korona Leszego)
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
	racks: { RackInfo },
}

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

local CLEARING_TREES = 34
local LANTERN_POSTS_Z = { 8, 30, 52, 74, 96 }
local PATH_END_Z = 125

-- ===== Pilnowanie, żeby rzeczy na siebie nie nachodziły =====

type Occupant = { x: number, z: number, r: number }
type Rect = { x1: number, x2: number, z1: number, z2: number }

local occupants: { Occupant } = {}
local reserved: { Rect } = {}

local function resetSpace()
	occupants = {}
	reserved = {}
end

local function isFree(x: number, z: number, r: number, ignorePath: boolean?): boolean
	for _, rect in reserved do
		if x + r > rect.x1 and x - r < rect.x2 and z + r > rect.z1 and z - r < rect.z2 then
			return false
		end
	end
	if not ignorePath and z < PATH_END_Z and z > -6 and math.abs(x - Props.pathX(z)) < 2.6 + r then
		return false
	end
	for _, o in occupants do
		local dx, dz = o.x - x, o.z - z
		local min = o.r + r
		if dx * dx + dz * dz < min * min then
			return false
		end
	end
	return true
end

local function occupy(x: number, z: number, r: number)
	table.insert(occupants, { x = x, z = z, r = r })
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
	accept: ((number, number) -> boolean)?
): (number?, number?)
	for _ = 1, 30 do
		local x = rng:NextNumber(x1, x2)
		local z = rng:NextNumber(z1, z2)
		if (not accept or accept(x, z)) and isFree(x, z, r) then
			return x, z
		end
	end
	return nil, nil
end

-- ===== Budowa =====

local function buildGround(parent: Instance)
	local halfWidth = Config.ForestHalfWidth
	for zoneIndex, zone in Config.Zones do
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
	local first = Config.Zones[1]
	local last = Config.Zones[#Config.Zones]
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

-- Gęsty rząd dużych drzew na brzegach mapy: zasłania niewidzialne ściany
local function buildBorder(parent: Instance, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "Border"
	local halfWidth = Config.ForestHalfWidth
	local first = Config.Zones[1]
	local last = Config.Zones[#Config.Zones]
	local function darknessAt(z: number): number
		return Config.Zones[math.max(2, Economy.zoneIndexAt(z))].darkness
	end
	-- Wewnętrzny rząd co ~11 studs, zewnętrzny (za ścianą, większe drzewa) co drugi raz.
	-- Mniej części = płynniej na telefonach; mgła i tak ukrywa dalsze drzewa.
	for _, side in { -1, 1 } do
		local z = first.startZ
		local i = 0
		while z < last.endZ do
			local dark = if z < first.endZ then 0.2 else darknessAt(z)
			Props.pine(folder, Vector3.new(side * (halfWidth - 3 + rng:NextNumber(-1.5, 1)), 0, z), rng:NextNumber(1.6, 2.1), rng, dark)
			if i % 2 == 0 then
				Props.pine(folder, Vector3.new(side * (halfWidth + 7 + rng:NextNumber(-2, 2)), 0, z + 5), rng:NextNumber(2.2, 2.8), rng, dark)
			end
			z += rng:NextNumber(10, 12)
			i += 1
		end
	end
	for _, edge in { { z = first.startZ + 3, dark = 0.2 }, { z = last.endZ - 3, dark = 1 } } do
		local x = -halfWidth
		while x < halfWidth do
			if edge.dark >= 1 and rng:NextNumber() < 0.4 then
				Props.deadTree(folder, Vector3.new(x, 0, edge.z), rng:NextNumber(1.3, 1.7), rng, edge.dark)
			else
				Props.pine(folder, Vector3.new(x, 0, edge.z + rng:NextNumber(-1.5, 1.5)), rng:NextNumber(1.6, 2.1), rng, edge.dark)
			end
			x += rng:NextNumber(7, 9)
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
		local x, z = findSpot(rng, -halfWidth, halfWidth, z1, z2, 4.5, accept)
		if x and z then
			local kind, scale = pickTree(recipe.trees, rng)
			TREE_BUILDERS[kind](folder, Vector3.new(x, 0, z), scale, rng, zone.darkness)
			occupy(x, z, 4.5 * scale)
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
	local halfWidth = Config.ForestHalfWidth - 8
	for zoneIndex, zone in Config.Zones do
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

-- Suszarnie na polanie, każda zwrócona do środka (ścieżki)
local function rackCFrame(plot: { x: number, z: number }): CFrame
	return CFrame.lookAt(Vector3.new(plot.x, 0, plot.z), Vector3.new(0, 0, plot.z))
end

local function buildRacks(parent: Instance): { RackInfo }
	local folder = Instance.new("Folder")
	folder.Name = "DryingRacks"
	local racks: { RackInfo } = {}
	for index, plot in Config.Drying.plots do
		local model = Rack.build(folder, rackCFrame(plot), Config.Drying.slots)
		model.Name = "DryingRack_" .. index
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
	-- Suszarnie: własne modele z folderu Map/DryingRacks albo nasze na domyślnych miejscach
	local racks: { RackInfo } = {}
	local racksFolder = map:FindFirstChild("DryingRacks")
	if racksFolder then
		for index, child in racksFolder:GetChildren() do
			if child:IsA("Model") and child.PrimaryPart then
				table.insert(racks, { id = index, model = child })
			end
		end
	else
		racks = buildRacks(map)
	end
	return {
		spawnCFrame = spawnPart.CFrame + Vector3.new(0, 3, 0),
		spots = spots,
		spotById = spotById,
		groveCenter = grove,
		racks = racks,
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
	for zoneIndex = 2, #Config.Zones do
		local zone = Config.Zones[zoneIndex]
		Props.gate(map, zone.startZ, zone.key)
		table.insert(reserved, { x1 = -9.5, x2 = 9.5, z1 = zone.startZ - 2.5, z2 = zone.startZ + 2.5 })
	end

	-- Suszarnie wokół chatki: wolne miejsce wokół każdej
	for _, plot in Config.Drying.plots do
		table.insert(reserved, { x1 = plot.x - 5, x2 = plot.x + 5, z1 = plot.z - 5, z2 = plot.z + 5 })
	end
	local racks = buildRacks(map)

	-- Gniazdo Leszego: w środku i za kręgiem (posąg) nic nie rośnie
	local center = groveCenter()
	local groveR = Config.Grove.radius
	table.insert(reserved, { x1 = center.X - groveR - 3, x2 = center.X + groveR + 3, z1 = center.Z - groveR - 5, z2 = center.Z + groveR + 8 })
	local leszyStatue = Grove.build(map, center, groveR, Random.new(Config.SpotSeed + 2))

	-- Ścieżka z latarniami od ganku w głąb skraju lasu
	local decorRng = Random.new(Config.SpotSeed + 1)
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
	for zoneIndex = 1, #Config.Zones do
		buildZoneDecor(map, zoneIndex, decorRng)
	end
	buildBorder(map, decorRng)

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
		racks = racks,
	}
end

return MapBuilder
