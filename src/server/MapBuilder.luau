--!strict
-- Szara mapa z klocków, budowana kodem przy starcie serwera.
-- Gdy zrobicie prawdziwą mapę w Studio, nazwijcie folder w Workspace "Map"
-- i dodajcie w nim część "SpawnPoint" oraz folder "Spots" z częściami,
-- których atrybut "Zone" mówi, do której strefy należą. Wtedy builder nic nie buduje.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

export type Spot = {
	id: string,
	zone: number,
	position: Vector3,
}

export type MapInfo = {
	spawnCFrame: CFrame,
	spots: { Spot },
	spotById: { [string]: Spot },
}

local MapBuilder = {}

local ZONE_GROUND_COLORS = {
	Color3.fromRGB(120, 150, 90), -- chatka
	Color3.fromRGB(80, 120, 60), -- skraj lasu
	Color3.fromRGB(55, 85, 45), -- gęstwina
	Color3.fromRGB(35, 50, 35), -- mroczny jar
}

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

local function buildCabin(parent: Instance)
	local cabin = Instance.new("Model")
	cabin.Name = "Cabin"

	local floorColor = Color3.fromRGB(150, 110, 70)
	local wallColor = Color3.fromRGB(120, 85, 55)

	part({ Name = "Floor", Size = Vector3.new(36, 1, 28), Position = Vector3.new(0, 0.5, -24), Color = floorColor, Parent = cabin })
	part({ Name = "BackWall", Size = Vector3.new(36, 14, 1), Position = Vector3.new(0, 8, -38), Color = wallColor, Parent = cabin })
	part({ Name = "LeftWall", Size = Vector3.new(1, 14, 28), Position = Vector3.new(-18, 8, -24), Color = wallColor, Parent = cabin })
	part({ Name = "RightWall", Size = Vector3.new(1, 14, 28), Position = Vector3.new(18, 8, -24), Color = wallColor, Parent = cabin })
	part({
		Name = "Roof",
		Size = Vector3.new(40, 1, 32),
		Position = Vector3.new(0, 15.5, -24),
		Color = Color3.fromRGB(90, 55, 40),
		Parent = cabin,
	})

	-- Stół grzybiarza: tu w przyszłości stanie sprzedawca i suszarnia
	local stall = part({
		Name = "SellStall",
		Size = Vector3.new(10, 3, 4),
		Position = Vector3.new(0, 2.5, -32),
		Color = Color3.fromRGB(200, 160, 90),
		Parent = cabin,
	})

	local warm = Instance.new("PointLight")
	warm.Color = Color3.fromRGB(255, 190, 120)
	warm.Range = 40
	warm.Brightness = 2
	warm.Shadows = true
	warm.Parent = stall

	cabin.Parent = parent
end

local function buildTree(parent: Instance, position: Vector3, rng: Random, darkness: number)
	local height = rng:NextNumber(14, 26)
	local trunk = part({
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, rng:NextNumber(1.6, 2.6), rng:NextNumber(1.6, 2.6)),
		CFrame = CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(90, 65, 45),
		Material = Enum.Material.Wood,
		Parent = parent,
	})
	trunk.CastShadow = true

	local leafColor = Color3.fromRGB(60, 110, 55):Lerp(Color3.fromRGB(25, 45, 30), darkness)
	local crownSize = rng:NextNumber(8, 13)
	part({
		Name = "Crown",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(crownSize, crownSize, crownSize),
		Position = position + Vector3.new(0, height + crownSize * 0.25, 0),
		Color = leafColor,
		Material = Enum.Material.Grass,
		CanCollide = false,
		Parent = parent,
	})
end

local function buildForest(parent: Instance): { Spot }
	local rng = Random.new(Config.SpotSeed)
	local spots: { Spot } = {}
	local halfWidth = Config.ForestHalfWidth

	for zoneIndex, zone in Config.Zones do
		local length = zone.endZ - zone.startZ
		part({
			Name = "Ground_" .. zone.id,
			Size = Vector3.new(halfWidth * 2, 2, length),
			Position = Vector3.new(0, -1, zone.startZ + length / 2),
			Color = ZONE_GROUND_COLORS[zoneIndex] or Color3.fromRGB(60, 60, 60),
			Material = Enum.Material.Grass,
			Parent = parent,
		})

		-- Słupki na granicy strefy, żeby było widać, że wchodzisz głębiej
		if zoneIndex > 1 then
			for _, side in { -1, 1 } do
				local post = part({
					Name = "ZonePost",
					Size = Vector3.new(1, 8, 1),
					Position = Vector3.new(side * (halfWidth - 3), 4, zone.startZ),
					Color = Color3.fromRGB(255, 200, 90),
					Material = Enum.Material.Neon,
					Parent = parent,
				})
				post.CastShadow = false
			end
		end

		local zoneSpots: { Vector3 } = {}
		for i = 1, zone.spotCount do
			local position = Vector3.new(
				rng:NextNumber(-halfWidth + 6, halfWidth - 6),
				0,
				rng:NextNumber(zone.startZ + 6, zone.endZ - 6)
			)
			table.insert(zoneSpots, position)
			table.insert(spots, {
				id = string.format("%s_%d", zone.id, i),
				zone = zoneIndex,
				position = position,
			})
		end

		local trees = Instance.new("Folder")
		trees.Name = "Trees_" .. zone.id
		trees.Parent = parent
		local placed = 0
		local attempts = 0
		while placed < zone.treeCount and attempts < zone.treeCount * 10 do
			attempts += 1
			local position = Vector3.new(
				rng:NextNumber(-halfWidth + 3, halfWidth - 3),
				0,
				rng:NextNumber(zone.startZ + 3, zone.endZ - 3)
			)
			-- Nie stawiaj drzewa na grzybie ani na środkowej ścieżce przy wejściu
			local blocked = math.abs(position.X) < 5 and position.Z < zone.startZ + 20
			for _, spot in zoneSpots do
				if (spot - position).Magnitude < 5 then
					blocked = true
					break
				end
			end
			if not blocked then
				buildTree(trees, position, rng, zone.darkness)
				placed += 1
			end
		end
	end

	-- Niewidzialne ściany wokół mapy
	local first = Config.Zones[1]
	local last = Config.Zones[#Config.Zones]
	local totalLength = last.endZ - first.startZ
	local centerZ = first.startZ + totalLength / 2
	local wallProps: { [string]: any } = { Transparency = 1, CanCollide = true, Parent = parent }
	for _, side in { -1, 1 } do
		local wall = part(wallProps)
		wall.Name = "SideWall"
		wall.Size = Vector3.new(2, 60, totalLength)
		wall.Position = Vector3.new(side * (halfWidth + 1), 30, centerZ)
	end
	for _, z in { first.startZ - 1, last.endZ + 1 } do
		local wall = part(wallProps)
		wall.Name = "EndWall"
		wall.Size = Vector3.new(halfWidth * 2, 60, 2)
		wall.Position = Vector3.new(0, 30, z)
	end

	return spots
end

local function readExistingMap(map: Folder): MapInfo?
	local spawnPart = map:FindFirstChild("SpawnPoint")
	local spotsFolder = map:FindFirstChild("Spots")
	if not (spawnPart and spawnPart:IsA("BasePart") and spotsFolder) then
		return nil
	end
	local spots: { Spot } = {}
	for i, child in spotsFolder:GetChildren() do
		local zone = child:GetAttribute("Zone")
		if child:IsA("BasePart") and typeof(zone) == "number" then
			table.insert(spots, { id = "custom_" .. i, zone = zone, position = child.Position })
			child.Transparency = 1
			child.CanCollide = false
		end
	end
	local spotById = {}
	for _, spot in spots do
		spotById[spot.id] = spot
	end
	return { spawnCFrame = spawnPart.CFrame + Vector3.new(0, 3, 0), spots = spots, spotById = spotById }
end

function MapBuilder.build(): MapInfo
	local existing = Workspace:FindFirstChild("Map")
	if existing and existing:IsA("Folder") then
		local info = readExistingMap(existing)
		if info then
			return info
		end
		warn("[MapBuilder] Folder Map nie ma SpawnPoint/Spots, buduję szarą mapę od nowa")
		existing:Destroy()
	end

	local map = Instance.new("Folder")
	map.Name = "Map"

	buildCabin(map)
	local spots = buildForest(map)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "SpawnPoint"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.Position = Vector3.new(0, 1.5, -18)
	spawn.Color = Color3.fromRGB(170, 130, 90)
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = map

	map.Parent = Workspace

	local spotById = {}
	for _, spot in spots do
		spotById[spot.id] = spot
	end

	return {
		spawnCFrame = spawn.CFrame + Vector3.new(0, 3, 0),
		spots = spots,
		spotById = spotById,
	}
end

return MapBuilder
