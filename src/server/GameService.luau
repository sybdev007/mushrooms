--!strict
-- Główna pętla gry po stronie serwera.
-- Serwer jest jedynym źródłem prawdy: olej, koszyk, monety i ulepszenia liczymy tutaj.
-- Klient tylko pokazuje stan i wysyła prośby (zbierz / sprzedaj / kup).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Remotes = require(Shared.Remotes)
local DataService = require(script.Parent.DataService)
local MapBuilder = require(script.Parent.MapBuilder)

type SpotState = {
	speciesId: string,
	golden: boolean,
	readyAt: number,
	visible: boolean,
}

type Session = {
	player: Player,
	data: DataService.Data,
	canSave: boolean,
	oil: number,
	zone: number,
	oilWarned: boolean,
	oilHalfWarned: boolean,
	lastPick: number,
	lastAction: number,
	rng: Random,
	spots: { [string]: SpotState },
}

local TICK_SECONDS = 0.2
local AUTOSAVE_SECONDS = 120
local ACTION_COOLDOWN = 0.3
local LANTERN_ATTACHMENT = "LanternAttachment" -- klient szuka światła pod tą nazwą (migotanie przy końcu oleju)

local StateUpdate = Remotes.get("StateUpdate")
local MushroomSync = Remotes.get("MushroomSync")
local MushroomRemoved = Remotes.get("MushroomRemoved")
local Notify = Remotes.get("Notify")
local PickMushroom = Remotes.get("PickMushroom")
local SellBasket = Remotes.get("SellBasket")
local BuyUpgrade = Remotes.get("BuyUpgrade")

local GameService = {}

local sessions: { [Player]: Session } = {}
local map: MapBuilder.MapInfo

local function stat(session: Session, id: string): number
	return Economy.upgradeStat(id, session.data.upgrades[id] or 0)
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Strefa liczona z aktualnej pozycji. 0 = gracz nie ma postaci.
local function currentZone(session: Session): number
	local root = getRoot(session.player)
	if not root then
		return 0
	end
	return Economy.zoneIndexAt(root.Position.Z)
end

local function notify(session: Session, key: string, args: { any }?, nameKey: string?)
	Notify:FireClient(session.player, { key = key, args = args, nameKey = nameKey })
end

local LEADERSTAT_COINS = "💰" -- kolumna na liście graczy; emoji, żeby działała w obu językach

local function pushState(session: Session)
	local data = session.data
	local leaderstats = session.player:FindFirstChild("leaderstats")
	local coinsStat = leaderstats and leaderstats:FindFirstChild(LEADERSTAT_COINS)
	if coinsStat and coinsStat:IsA("IntValue") then
		coinsStat.Value = data.coins
	end
	StateUpdate:FireClient(session.player, {
		coins = data.coins,
		oil = math.max(session.oil, 0),
		oilMax = stat(session, "oil"),
		basketCount = #data.basket,
		basketMax = stat(session, "basket"),
		basketValue = Economy.basketValue(data.basket),
		lanternRange = stat(session, "lantern"),
		zone = session.zone,
		upgrades = table.clone(data.upgrades),
	})
end

local function rollSpot(session: Session, zone: number): (string?, boolean)
	local species = Economy.rollSpecies(zone, session.rng:NextNumber())
	if not species then
		return nil, false
	end
	return species.id, session.rng:NextNumber() < Config.GoldenChance
end

-- Wysyła klientowi grzyby, które właśnie odrosły
local function syncReadySpots(session: Session, now: number)
	local added = {}
	for id, state in session.spots do
		if not state.visible and now >= state.readyAt then
			local spot = map.spotById[id]
			if spot then
				state.visible = true
				table.insert(added, {
					id = id,
					position = spot.position,
					species = state.speciesId,
					golden = state.golden,
				})
			end
		end
	end
	if #added > 0 then
		MushroomSync:FireClient(session.player, added)
	end
end

-- Latarnia trzymana w prawej ręce (tylko wygląd: światło wisi w LanternAttachment).
-- Szybka nazywa się "LanternGlass", żeby klient mógł ją przyciemniać przy końcu oleju.
local function attachHandLantern(character: Model)
	if character:FindFirstChild("HandLantern") then
		return
	end
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if not (hand and hand:IsA("BasePart")) then
		return
	end
	local model = Instance.new("Model")
	model.Name = "HandLantern"
	local isR6 = hand.Name == "Right Arm"
	local top = hand.CFrame * CFrame.new(0, if isR6 then -1.2 else -0.25, 0)
	local metal = Color3.fromRGB(52, 50, 48)
	local function piece(name: string, size: Vector3, offsetY: number, color: Color3, material: Enum.Material?): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = top * CFrame.new(0, offsetY, 0)
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Massless = true
		p.CastShadow = false
		p.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hand
		weld.Part1 = p
		weld.Parent = p
		return p
	end
	piece("Handle", Vector3.new(0.08, 0.5, 0.08), -0.25, metal)
	piece("Cap", Vector3.new(0.75, 0.18, 0.75), -0.55, metal)
	piece("LanternGlass", Vector3.new(0.55, 0.7, 0.55), -1, Color3.fromRGB(255, 206, 120), Enum.Material.Neon)
	piece("Base", Vector3.new(0.7, 0.16, 0.7), -1.42, metal)
	model.Parent = character
end

local function applyCharacterStats(session: Session)
	local character = session.player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = stat(session, "boots")
	end
	local root = getRoot(session.player)
	if root then
		-- Światło wisi przed głową, a nie w środku postaci. Gdy było w HumanoidRootPart,
		-- ręce i nogi rzucały cienie na ziemię przy każdym kroku i obraz migotał.
		local attachment = root:FindFirstChild(LANTERN_ATTACHMENT)
		if not (attachment and attachment:IsA("Attachment")) then
			local newAttachment = Instance.new("Attachment")
			newAttachment.Name = LANTERN_ATTACHMENT
			newAttachment.Position = Vector3.new(0, 2.2, -1.6)
			newAttachment.Parent = root
			attachment = newAttachment
		end
		local existing = (attachment :: Attachment):FindFirstChild("Lantern")
		local lantern: PointLight
		if existing and existing:IsA("PointLight") then
			lantern = existing
		else
			lantern = Instance.new("PointLight")
			lantern.Name = "Lantern"
			lantern.Color = Color3.fromRGB(255, 205, 140)
			lantern.Brightness = 2
			lantern.Shadows = true
			lantern.Parent = attachment
		end
		lantern.Range = math.min(stat(session, "lantern"), 60) -- 60 to limit Robloxa dla PointLight
	end
	attachHandLantern(character)
end

-- Latarnia zgasła: las zabiera część koszyka i wyrzuca gracza do chatki
local function engulf(session: Session)
	local basket = session.data.basket
	local lost = Economy.engulfLoss(#basket)
	for _ = 1, lost do
		table.remove(basket)
	end
	session.oil = stat(session, "oil")
	session.oilWarned = false
	session.oilHalfWarned = false
	local character = session.player.Character
	if character then
		character:PivotTo(map.spawnCFrame)
	end
	session.zone = 1
	notify(session, "MSG_ENGULFED", { lost })
end

local function tick(step: number)
	local now = os.clock()
	for _, session in sessions do
		local root = getRoot(session.player)
		if root then
			local zone = Economy.zoneIndexAt(root.Position.Z)
			session.zone = zone
			local oilMax = stat(session, "oil")
			if zone == 1 then
				session.oil = math.min(oilMax, session.oil + Config.OilRefillPerSecond * step)
				session.oilWarned = false
				session.oilHalfWarned = false
			else
				session.oil -= Config.Zones[zone].oilDrain * step
				if not session.oilHalfWarned and session.oil <= oilMax * Config.OilWarnFraction then
					session.oilHalfWarned = true
					notify(session, "MSG_OIL_HALF")
				end
				if not session.oilWarned and session.oil <= oilMax * Config.OilLowFraction then
					session.oilWarned = true
					notify(session, "MSG_OIL_LOW")
				end
				if session.oil <= 0 then
					engulf(session)
				end
			end
		end
		syncReadySpots(session, now)
		pushState(session)
	end
end

local function onCharacterAdded(session: Session, character: Model)
	character:WaitForChild("HumanoidRootPart", 10)
	character:WaitForChild("Humanoid", 10)
	if sessions[session.player] ~= session then
		return
	end
	session.oil = stat(session, "oil")
	session.oilWarned = false
	session.oilHalfWarned = false
	applyCharacterStats(session)
	pushState(session)
end

local function onPlayerAdded(player: Player)
	local data, canSave = DataService.load(player)
	if player.Parent == nil then
		return -- gracz wyszedł w trakcie wczytywania
	end

	local session: Session = {
		player = player,
		data = data,
		canSave = canSave,
		oil = 0,
		zone = 1,
		oilWarned = false,
		oilHalfWarned = false,
		lastPick = 0,
		lastAction = 0,
		rng = Random.new(),
		spots = {},
	}
	session.oil = stat(session, "oil")

	-- Lista graczy w prawym górnym rogu pokazuje monety wszystkich na serwerze
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local coinsStat = Instance.new("IntValue")
	coinsStat.Name = LEADERSTAT_COINS
	coinsStat.Value = data.coins
	coinsStat.Parent = leaderstats
	leaderstats.Parent = player

	-- Każdy gracz ma własne grzyby: nikt nikomu nie wyzbiera wysypu
	for _, spot in map.spots do
		local speciesId, golden = rollSpot(session, spot.zone)
		if speciesId then
			session.spots[spot.id] = { speciesId = speciesId, golden = golden, readyAt = 0, visible = false }
		end
	end

	sessions[player] = session

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(session, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, session, player.Character)
	end

	if not canSave then
		notify(session, "MSG_NO_SAVE")
	end
	syncReadySpots(session, os.clock())
	pushState(session)
end

local function saveSession(session: Session)
	if session.canSave then
		DataService.save(session.player, session.data)
	end
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	sessions[player] = nil
	saveSession(session)
end

local function onPick(player: Player, spotId: unknown)
	local session = sessions[player]
	if not session or typeof(spotId) ~= "string" then
		return
	end
	local now = os.clock()
	if now - session.lastPick < Config.PickCooldown then
		return
	end
	session.lastPick = now

	local state = session.spots[spotId]
	local spot = map.spotById[spotId]
	if not state or not spot or not state.visible then
		return
	end
	local root = getRoot(player)
	if not root then
		return
	end
	local offset = root.Position - spot.position
	if Vector3.new(offset.X, 0, offset.Z).Magnitude > Config.PickRadiusServer then
		return
	end

	local basket = session.data.basket
	if #basket >= stat(session, "basket") then
		notify(session, "MSG_BASKET_FULL")
		return
	end

	table.insert(basket, { s = state.speciesId, g = state.golden })
	session.data.atlas[state.speciesId] = true

	if state.golden then
		local species = Economy.getSpecies(state.speciesId)
		notify(session, "MSG_GOLDEN", nil, species and species.key or nil)
	end

	-- Grzyb odrośnie później i może to być inny gatunek
	local speciesId, golden = rollSpot(session, spot.zone)
	state.visible = false
	state.readyAt = now + Config.RespawnSeconds
	state.speciesId = speciesId or state.speciesId
	state.golden = golden

	MushroomRemoved:FireClient(player, spotId)
	pushState(session)
end

local function canAct(session: Session): boolean
	local now = os.clock()
	if now - session.lastAction < ACTION_COOLDOWN then
		return false
	end
	session.lastAction = now
	return currentZone(session) == 1
end

local function onSell(player: Player)
	local session = sessions[player]
	if not session or not canAct(session) then
		return
	end
	local basket = session.data.basket
	if #basket == 0 then
		return
	end
	local value = Economy.basketValue(basket)
	session.data.coins += value
	table.clear(basket)
	notify(session, "MSG_SOLD", { value })
	pushState(session)
end

local function onBuy(player: Player, upgradeId: unknown)
	local session = sessions[player]
	if not session or typeof(upgradeId) ~= "string" then
		return
	end
	local def = Config.Upgrades[upgradeId]
	if not def or not canAct(session) then
		return
	end
	local level = session.data.upgrades[upgradeId] or 0
	local cost = Economy.upgradeCost(upgradeId, level)
	if not cost then
		return
	end
	if session.data.coins < cost then
		notify(session, "MSG_NOT_ENOUGH")
		return
	end
	session.data.coins -= cost
	session.data.upgrades[upgradeId] = level + 1
	if upgradeId == "oil" then
		session.oil = stat(session, "oil")
	end
	applyCharacterStats(session)
	notify(session, "MSG_UPGRADED", nil, def.key)
	pushState(session)
end

function GameService.start(mapInfo: MapBuilder.MapInfo)
	map = mapInfo

	PickMushroom.OnServerEvent:Connect(onPick)
	SellBasket.OnServerEvent:Connect(onSell)
	BuyUpgrade.OnServerEvent:Connect(onBuy)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= TICK_SECONDS then
			local step = accumulator
			accumulator = 0
			tick(step)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_SECONDS)
			for _, session in sessions do
				task.spawn(saveSession, session)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for _, session in sessions do
			pending += 1
			task.spawn(function()
				saveSession(session)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return GameService
