--!strict
-- Znalezisko Nocy: raz na noc na serwerze w głębi lasu wyrasta jeden kosmiczny grzyb, widoczny dla
-- wszystkich (znacznik z tagiem "NightFind": grzyba rysuje każdy klient, DisplayMushrooms). Kto pierwszy
-- go zerwie (przycisk), niesie go nad głową, idzie wolniej i świeci; ma Config.NightFind.carrySeconds,
-- żeby dojść na polanę przy chatce. Doniesie = monety i trofeum (stats.nightFinds, tytuły 1/3/7/15).
-- Nie doniesie (czas, zniknięcie postaci, portal albo inna teleportacja, wyjście z gry) = przepada.
-- Na start bez odbierania przez innych. Czas i miejsca: Shared/NightFind.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Cycle = require(ReplicatedStorage.Shared.Cycle)
local Economy = require(ReplicatedStorage.Shared.Economy)
local NightFind = require(ReplicatedStorage.Shared.NightFind)
local Progress = require(ReplicatedStorage.Shared.Progress)
local Ledger = require(script.Parent.Ledger)

type MutationInfo = { variant: string?, tags: { string }? }

export type Api = {
	getData: (Player) -> any?,
	notify: (Player, string, { any }?, string?, MutationInfo?) -> (),
	pushState: (Player) -> (),
	applyStats: (Player) -> (), -- przelicza prędkość chodu (Znalezisko spowalnia)
	event: (Player, string, number?) -> (), -- ProgressService.event (licznik nightFinds, tytuły)
	rootOf: (Player) -> BasePart?,
	busy: (Player) -> boolean, -- niesie łup z ogródka albo leży bez latarni: nie może zerwać
	spots: { NightFind.Spot },
}

type Find = { model: Model, species: string, ground: Vector3, zone: number }
type Carrier = { player: Player, species: string, deadline: number, last: Vector3, lastAt: number, visuals: { Instance } }

local NightFindService = {}

local GOLD = Color3.fromRGB(255, 214, 90)
local COSMIC = Color3.fromRGB(150, 120, 255)
local PICK_RANGE = 10 -- serwer jest łagodniejszy niż przycisk przez opóźnienie sieci
-- Skok o więcej niż TELEPORT_STEP + TELEPORT_SPEED × czas od ostatniego sprawdzenia = teleport, nie chód
-- (GameService i tak woła drop przy portalach i śmierci; to tylko zabezpieczenie)
local TELEPORT_STEP = 20
local TELEPORT_SPEED = 60

local api: Api
local folder: Folder
local find: Find? = nil
local carrier: Carrier? = nil
local scheduledNight = -1
local spawnAt: number? = nil
local spawnedNight = -1

local function notifyAll(key: string, args: { any }?, nameKey: string?, except: Player?)
	for _, player in Players:GetPlayers() do
		if player ~= except then
			api.notify(player, key, args, nameKey)
		end
	end
end

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

-- Ziemia pod punktem (bez postaci graczy)
local function groundAt(position: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { folder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(position + Vector3.new(0, 6, 0), Vector3.new(0, -20, 0), params)
	return if hit then hit.Position else position
end

local function removeFind()
	if find then
		find.model:Destroy()
		find = nil
	end
end

local function speciesNear(zone: number): string
	for _ = 1, 20 do
		local species = Economy.rollSpecies(zone, math.random())
		if species and not species.mimic then
			return species.id
		end
	end
	return "porcini"
end

-- Znacznik Znaleziska w świecie (grzyba rysuje klient), z przyciskiem do zerwania
local function spawnAt_(ground: Vector3, zone: number)
	removeFind()
	local species = speciesNear(zone)
	local model = Instance.new("Model")
	model.Name = "NightFind"
	local root = part({ Name = "Root", Size = Vector3.new(1.6, 1.6, 1.6), Position = ground + Vector3.new(0, 0.8, 0), Transparency = 1 })
	root.Parent = model
	model.PrimaryPart = root
	-- Złoty krąg na ziemi: widać, gdzie rośnie, także w ciemności
	part({
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.06, 4.4, 4.4),
		CFrame = CFrame.new(ground + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = GOLD,
		Material = Enum.Material.Neon,
		Transparency = 0.45,
	}).Parent = model
	-- Słup światła ponad korony drzew: z daleka widać, gdzie szukać
	part({
		Name = "Beam",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(70, 0.7, 0.7),
		CFrame = CFrame.new(ground + Vector3.new(0, 35, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = GOLD,
		Material = Enum.Material.Neon,
		Transparency = 0.55,
	}).Parent = model
	local light = Instance.new("PointLight")
	light.Color = COSMIC
	light.Range = 14
	light.Brightness = 1.6
	light.Parent = root
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Pick"
	prompt.ActionText = "Pick"
	prompt.ObjectText = "Night Find"
	prompt.HoldDuration = Config.NightFind.pickHold
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = root
	CollectionService:AddTag(prompt, "NightFindPrompt")
	model:SetAttribute("Species", species)
	model:SetAttribute("Variant", Config.NightFind.variant)
	model:SetAttribute("Tags", "")
	model:SetAttribute("Ground", ground)
	model:SetAttribute("Fresh", true)
	CollectionService:AddTag(model, "NightFind")
	model.Parent = folder
	task.delay(3, function()
		if model.Parent then
			model:SetAttribute("Fresh", false)
		end
	end)
	find = { model = model, species = species, ground = ground, zone = zone }
	prompt.Triggered:Connect(function(player)
		NightFindService.pick(player)
	end)
	local zoneDef = Config.Zones[zone]
	notifyAll("MSG_NIGHTFIND_SPAWN", nil, if zoneDef then zoneDef.key else nil)
end

local function spawnRandom(): boolean
	local candidates = NightFind.candidates(api.spots)
	if #candidates == 0 then
		return false
	end
	local spot = candidates[math.random(1, #candidates)]
	-- Obok miejsca grzyba z lasu gracza (nie w nim)
	local angle = math.random() * math.pi * 2
	local ground = groundAt(spot.position + Vector3.new(math.cos(angle) * 2.4, 0, math.sin(angle) * 2.4))
	spawnAt_(ground, spot.zone)
	return true
end

-- ===== Niesienie =====

local function carryVisuals(player: Player): { Instance }
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not (character and head and head:IsA("BasePart")) then
		return {}
	end
	local orb = part({ Name = "NightFindOrb", Shape = Enum.PartType.Ball, Size = Vector3.new(1.3, 1.3, 1.3), Color = COSMIC, Material = Enum.Material.Neon })
	orb.Anchored = false
	orb.Massless = true
	orb.CFrame = head.CFrame * CFrame.new(0, 2, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = orb
	weld.Parent = orb
	local light = Instance.new("PointLight")
	light.Color = COSMIC
	light.Range = 16
	light.Brightness = 2
	light.Parent = orb
	local sparkles = Instance.new("Sparkles")
	sparkles.SparkleColor = GOLD
	sparkles.Parent = orb
	orb.Parent = character
	local highlight = Instance.new("Highlight")
	highlight.Name = "NightFindHighlight"
	highlight.FillColor = GOLD
	highlight.FillTransparency = 0.7
	highlight.OutlineColor = GOLD
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = character
	return { orb, highlight }
end

local function endCarry()
	local current = carrier
	if not current then
		return
	end
	carrier = nil
	for _, instance in current.visuals do
		instance:Destroy()
	end
	local character = current.player.Character
	if character then
		character:SetAttribute("NightFindUntil", nil)
	end
	if current.player.Parent then
		api.applyStats(current.player)
	end
end

local function fail()
	local current = carrier
	if not current then
		return
	end
	endCarry()
	notifyAll("MSG_NIGHTFIND_LOST", { current.player.DisplayName })
end

local function deliver()
	local current = carrier
	if not current then
		return
	end
	endCarry()
	local player = current.player
	local data = api.getData(player)
	if not data then
		return
	end
	local scale = Progress.rewardScale(data.caveUnlocked, data.swampUnlocked, data.mountainUnlocked)
	local coins = NightFind.reward(scale)
	Ledger.earn(player, data, coins, "Gameplay", "NightFind")
	api.event(player, "nightFind", 1)
	local def = Economy.getSpecies(current.species)
	api.notify(player, "MSG_NIGHTFIND_DONE", { coins, data.stats.nightFinds }, if def then def.key else nil, { variant = Config.NightFind.variant })
	notifyAll("MSG_NIGHTFIND_DELIVERED", { player.DisplayName }, nil, player)
	api.pushState(player)
end

-- Gracz zerwał Znalezisko (przycisk)
function NightFindService.pick(player: Player)
	local current = find
	if not current or carrier or api.busy(player) then
		return
	end
	local root = api.rootOf(player)
	local findRoot = current.model.PrimaryPart
	if not root or not findRoot or (root.Position - findRoot.Position).Magnitude > PICK_RANGE then
		return
	end
	removeFind()
	local seconds = Config.NightFind.carrySeconds
	carrier = {
		player = player,
		species = current.species,
		deadline = os.clock() + seconds,
		last = root.Position,
		lastAt = os.clock(),
		visuals = carryVisuals(player),
	}
	local character = player.Character
	if character then
		character:SetAttribute("NightFindUntil", Workspace:GetServerTimeNow() + seconds)
	end
	api.applyStats(player)
	api.notify(player, "MSG_NIGHTFIND_RUN", { math.floor(seconds / 60) })
	notifyAll("MSG_NIGHTFIND_TAKEN", { player.DisplayName }, nil, player)
end

-- Prędkość chodu (GameService mnoży przez nią): z Znaleziskiem wolniej
function NightFindService.speedFactor(player: Player): number
	return if carrier and carrier.player == player then Config.NightFind.speed else 1
end

-- Portal, śmierć albo teleport: Znalezisko przepada (GameService woła przed PivotTo)
function NightFindService.drop(player: Player)
	if carrier and carrier.player == player then
		fail()
	end
end

function NightFindService.isCarrying(player: Player): boolean
	return carrier ~= nil and carrier.player == player
end

-- ===== Pętla: kiedy wyrasta, czy niosący zdążył =====

local function step()
	local now = os.time()
	local phase = Cycle.at(now)
	if phase.phase == "night" then
		if scheduledNight ~= phase.index then
			scheduledNight = phase.index
			spawnAt = NightFind.spawnTime(phase.index, math.random(), now)
		end
		if spawnAt and now >= spawnAt and spawnedNight ~= phase.index and not find and not carrier and #Players:GetPlayers() > 0 then
			spawnedNight = phase.index
			spawnRandom()
		end
	elseif find then
		-- Świt: niezerwane Znalezisko znika do następnej nocy
		removeFind()
	end
	local current = carrier
	if current then
		local player = current.player
		local root = if player.Parent then api.rootOf(player) else nil
		if not root then
			fail()
			return
		end
		local position = root.Position
		local clock = os.clock()
		local moved = (position - current.last).Magnitude
		local teleported = moved > TELEPORT_STEP + TELEPORT_SPEED * (clock - current.lastAt)
		current.last = position
		current.lastAt = clock
		if teleported or not NightFind.inForest(position.Z) or clock > current.deadline then
			fail()
		elseif NightFind.delivered(position.Z) then
			deliver()
		end
	end
end

-- ===== Panel DEV (Studio) =====

-- Znalezisko od razu kilka kroków przed graczem (bez czekania na noc)
function NightFindService.devSpawn(player: Player)
	local root = api.rootOf(player)
	if not root then
		return
	end
	endCarry()
	local ahead = root.CFrame * CFrame.new(0, 0, -7)
	spawnAt_(groundAt(ahead.Position), Economy.zoneIndexAt(ahead.Position.Z))
end

-- Trofea na 0 (przywrócenie zapisu po teście)
function NightFindService.devReset(player: Player)
	local data = api.getData(player)
	if data then
		data.stats.nightFinds = 0
	end
end

function NightFindService.start(serviceApi: Api)
	api = serviceApi
	folder = Instance.new("Folder")
	folder.Name = "NightFind"
	folder.Parent = Workspace
	Players.PlayerRemoving:Connect(function(player: Player)
		if carrier and carrier.player == player then
			fail()
		end
	end)
	local function watch(player: Player)
		player.CharacterRemoving:Connect(function()
			if carrier and carrier.player == player then
				fail()
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	task.spawn(function()
		while true do
			task.wait(0.25)
			local ok, err = pcall(function()
				step()
			end)
			if not ok then
				warn("[NightFindService]", err)
			end
		end
	end)
end

return NightFindService
