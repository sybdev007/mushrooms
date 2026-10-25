--!strict
-- Główna pętla gry po stronie serwera.
-- Serwer jest jedynym źródłem prawdy: olej, koszyk, monety i ulepszenia liczymy tutaj.
-- Klient tylko pokazuje stan i wysyła prośby (zbierz / sprzedaj / kup).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Remotes = require(Shared.Remotes)
local DataService = require(script.Parent.DataService)
local MapBuilder = require(script.Parent.MapBuilder)
local LeszyService = require(script.Parent.LeszyService)
local HoardService = require(script.Parent.HoardService)
local DryingService = require(script.Parent.DryingService)

type SpotState = {
	speciesId: string,
	variant: string?,
	tags: { string }?,
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
	portalNoticeAt: number, -- kiedy ostatnio mówiliśmy „portal zamknięty” (żeby nie spamować)
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

-- Koszyk + plecak górnika (ulepszenie z obozowiska w jaskini)
local function basketMax(session: Session): number
	return stat(session, "basket") + stat(session, "pack")
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

-- mutation: { variant, tags } do pokazania etykiet w języku gracza (klient je tłumaczy)
type MutationInfo = { variant: string?, tags: { string }? }

local function notify(session: Session, key: string, args: { any }?, nameKey: string?, mutation: MutationInfo?)
	Notify:FireClient(session.player, { key = key, args = args, nameKey = nameKey, mutation = mutation })
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
		basketMax = basketMax(session),
		basketValue = Economy.basketValue(data.basket),
		lanternRange = stat(session, "lantern"),
		zone = session.zone,
		upgrades = table.clone(data.upgrades),
		chased = LeszyService.isChased(session.player),
		caveUnlocked = data.caveUnlocked,
	})
end

-- Losuje gatunek, wariant i cechy grzyba. countPity = to jest odrost po zebraniu
-- (początkowe rozstawienie lasu nie nabija gwarancji).
local function rollSpot(session: Session, spot: MapBuilder.Spot, countPity: boolean?): (string?, string?, { string }?)
	local species
	if spot.grove then
		local list = Economy.groveSpecies()
		species = list[session.rng:NextInteger(1, math.max(#list, 1))]
	else
		species = Economy.rollSpecies(spot.zone, session.rng:NextNumber())
	end
	if not species then
		return nil, nil, nil
	end

	-- Gwarancja: po Config.PityRolls odrostach bez Złota (albo lepszego) wymuszamy co najmniej Złoto
	local data = session.data
	local forced = countPity and data.pity >= Config.PityRolls
	local variant = Economy.rollVariant(session.rng:NextNumber(), if forced then 2 else nil)
	if countPity then
		data.pity = if Economy.variantRank(variant) >= 2 then 0 else data.pity + 1
	end

	local tags: { string }? = nil
	for _, tag in Economy.tagsForZone(spot.zone) do
		if session.rng:NextNumber() < tag.chance then
			tags = tags or {}
			table.insert(tags :: { string }, tag.id)
		end
	end
	return species.id, variant, tags
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
					variant = state.variant,
					tags = state.tags,
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

-- Latarnia zgasła albo Leszy złapał gracza: las zabiera część koszyka i wyrzuca gracza do chatki.
-- messageKey mówi klientowi, który ekran pokazać (MSG_ENGULFED albo MSG_CAUGHT).
local function engulf(session: Session, messageKey: string?)
	LeszyService.stop(session.player)
	local basket = session.data.basket

	-- Leszy odbiera swoje korony i odnosi je do gniazda, gdzie może je zabrać każdy
	local reclaimed: { HoardService.Item } = {}
	if messageKey == "MSG_CAUGHT" then
		for index = #basket, 1, -1 do
			if Economy.isGroveItem(basket[index].s) then
				table.insert(reclaimed, table.remove(basket, index) :: any)
			end
		end
	end

	local lost = Economy.engulfLoss(#basket)
	for _ = 1, lost do
		table.remove(basket)
	end
	lost += #reclaimed
	session.oil = stat(session, "oil")
	session.oilWarned = false
	session.oilHalfWarned = false
	-- W jaskini gracz budzi się w obozowisku, a nie w chatce na drugim końcu świata
	local root = getRoot(session.player)
	local inCave = root ~= nil and Economy.zoneWorld(Economy.zoneIndexAt(root.Position.Z)) == "cave"
	local target = if inCave and map.campCFrame then map.campCFrame else map.spawnCFrame
	local character = session.player.Character
	if character then
		character:PivotTo(target)
	end
	session.zone = Economy.zoneIndexAt(target.Position.Z)
	local defaultKey = if inCave then "MSG_ENGULFED_CAVE" else "MSG_ENGULFED"
	notify(session, messageKey or defaultKey, { lost })

	if #reclaimed > 0 then
		local placed = HoardService.drop(reclaimed)
		if placed > 0 then
			-- Cały serwer wie, że w gnieździe leży coś do zgarnięcia
			for _, other in sessions do
				notify(other, "MSG_HOARD_DROP", { session.player.DisplayName, placed })
			end
		end
	end
end

-- Portale: w lesie za Leszym (do jaskini, od Config.Cave.unlockCoins monet) i w obozowisku (do chatki)
local function near(root: BasePart, point: Vector3?): boolean
	if not point then
		return false
	end
	local offset = root.Position - point
	return Vector3.new(offset.X, 0, offset.Z).Magnitude <= Config.Cave.portalRadius
end

local function checkPortals(session: Session, root: BasePart, now: number)
	local character = session.player.Character
	if not character then
		return
	end
	if near(root, map.portal) and map.campCFrame then
		local data = session.data
		if Economy.canEnterCave(data.coins, data.caveUnlocked) then
			local first = not data.caveUnlocked
			data.caveUnlocked = true
			-- Ucieczka przez portal kończy pościg (Leszy nie wchodzi do jaskini)
			LeszyService.stop(session.player)
			character:PivotTo(map.campCFrame)
			session.zone = Economy.zoneIndexAt(map.campCFrame.Position.Z)
			notify(session, if first then "MSG_CAVE_UNLOCKED" else "MSG_CAVE_ENTER")
		elseif now - session.portalNoticeAt > 4 then
			session.portalNoticeAt = now
			notify(session, "MSG_PORTAL_LOCKED", { Config.Cave.unlockCoins })
		end
	elseif near(root, map.shortcut) and map.campCFrame then
		if session.data.caveUnlocked then
			LeszyService.stop(session.player)
			character:PivotTo(map.campCFrame)
			session.zone = Economy.zoneIndexAt(map.campCFrame.Position.Z)
			notify(session, "MSG_CAVE_ENTER")
		elseif now - session.portalNoticeAt > 4 then
			session.portalNoticeAt = now
			notify(session, "MSG_PORTAL_FIND")
		end
	elseif near(root, map.returnPortal) then
		character:PivotTo(map.spawnCFrame)
		session.zone = 1
		notify(session, "MSG_PORTAL_HOME")
	end
end

local function tick(step: number)
	local now = os.clock()
	for _, session in sessions do
		local root = getRoot(session.player)
		if root then
			local zone = Economy.zoneIndexAt(root.Position.Z)
			session.zone = zone
			local oilMax = stat(session, "oil")
			if Economy.isSafeZone(zone) then
				-- Olej leje się tylko przy beczce; na polanie / w obozie latarnia nie traci, ale się nie napełnia
				if Economy.atStation("oil", root.Position.X, root.Position.Z, Config.StationTolerance) then
					session.oil = math.min(oilMax, session.oil + Config.OilRefillPerSecond * step)
				end
				-- Ostrzeżenia wracają dopiero, gdy olej znów spadnie poniżej progu
				if session.oil > oilMax * Config.OilWarnFraction then
					session.oilHalfWarned = false
				end
				if session.oil > oilMax * Config.OilLowFraction then
					session.oilWarned = false
				end
			else
				session.oil -= Economy.oilDrain(zone, stat(session, "crystal")) * step
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
		if root then
			checkPortals(session, root, now)
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
		portalNoticeAt = 0,
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
		local speciesId, variant, tags = rollSpot(session, spot)
		if speciesId then
			session.spots[spot.id] = { speciesId = speciesId, variant = variant, tags = tags, readyAt = 0, visible = false }
		end
	end

	sessions[player] = session
	DryingService.assign(player)

	-- Bez limitu dało się oddalić kamerę i oglądać las z góry. Zoom = kamera przysuwa się,
	-- gdy coś (korony drzew) zasłania postać, zamiast robić je przezroczystymi.
	player.CameraMaxZoomDistance = Config.CameraMaxZoom
	player.DevCameraOcclusionMode = Enum.DevCameraOcclusionMode.Zoom

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
	LeszyService.stop(player)
	DryingService.release(player)
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
	if #basket >= basketMax(session) then
		notify(session, "MSG_BASKET_FULL")
		return
	end

	table.insert(basket, { s = state.speciesId, v = state.variant, x = state.tags })
	session.data.atlas[state.speciesId] = true

	-- Komunikat tylko o rzadkich znaleziskach (Złoto+ albo dwie mutacje naraz), żeby nie spamować;
	-- o zwykłym srebrze czy mchu mówi już kolorowe „+N” nad grzybem
	local species = Economy.getSpecies(state.speciesId)
	local rank = Economy.variantRank(state.variant)
	local mutationCount = (if state.variant then 1 else 0) + #(state.tags or {})
	if rank >= 2 or mutationCount >= 2 then
		local mult = Economy.mutationMultiplier(state.variant, state.tags)
		notify(session, "MSG_MUTATION", { string.format("%g", mult) }, species and species.key or nil, {
			variant = state.variant,
			tags = state.tags,
		})
	end
	-- Tęcza: ogłoszenie dla całego serwera (wiadomo, czyją suszarnię warto potem odwiedzić)
	if rank >= Config.AnnounceRank then
		for _, other in sessions do
			if other ~= session then
				notify(other, "MSG_RARE_FIND", { player.DisplayName }, species and species.key or nil, {
					variant = state.variant,
					tags = state.tags,
				})
			end
		end
	end

	-- Grzyb odrośnie później i może to być inny gatunek
	local speciesId, variant, tags = rollSpot(session, spot, true)
	state.visible = false
	state.readyAt = now + (if spot.grove then Config.Grove.respawnSeconds else Config.RespawnSeconds)
	state.speciesId = speciesId or state.speciesId
	state.variant = variant
	state.tags = tags

	MushroomRemoved:FireClient(player, spotId)
	-- Korona Leszego budzi właściciela gniazda
	if spot.grove and LeszyService.startChase(player, spot.position) then
		notify(session, "MSG_LESZY_WOKE")
	end
	pushState(session)
end

local function canAct(session: Session): boolean
	local now = os.clock()
	if now - session.lastAction < ACTION_COOLDOWN then
		return false
	end
	session.lastAction = now
	-- Sprzedaż i ulepszenia tylko przy ladzie w chatce
	local root = getRoot(session.player)
	return root ~= nil and Economy.atStation("shop", root.Position.X, root.Position.Z, Config.StationTolerance)
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

-- ===== Komendy deweloperskie =====

local function isDeveloper(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return true
	end
	return table.find(Config.DevUserIds, player.UserId) ~= nil
end

-- /coins 1000000 dodaje monety, /coins -500 odejmuje (bez liczby: +1000)
local function setupDevCommands()
	local folder = TextChatService:FindFirstChild("TextChatCommands") or TextChatService
	local command = Instance.new("TextChatCommand")
	command.Name = "DevCoins"
	command.PrimaryAlias = "/coins"
	command.Parent = folder
	command.Triggered:Connect(function(source: TextSource, text: string)
		local player = Players:GetPlayerByUserId(source.UserId)
		local session = player and sessions[player]
		if not (player and session and isDeveloper(player)) then
			return
		end
		local amount = math.floor(tonumber(string.match(text, "^%S+%s+(%-?%d+)")) or 1000)
		session.data.coins = math.max(0, session.data.coins + amount)
		notify(session, "MSG_DEV_COINS", { amount })
		pushState(session)
	end)
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
	-- Ulepszenia z obozowiska kupuje się tylko tam, z chatki tylko w chatce
	local root = getRoot(player)
	local station = root and Economy.stationAt("shop", root.Position.X, root.Position.Z, Config.StationTolerance)
	if not station or station.world ~= Economy.upgradeShop(upgradeId) then
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
	elseif upgradeId == "lock" then
		DryingService.refresh(player)
	end
	applyCharacterStats(session)
	notify(session, "MSG_UPGRADED", nil, def.key)
	pushState(session)
end

function GameService.start(mapInfo: MapBuilder.MapInfo)
	map = mapInfo

	LeszyService.start(map.groveCenter, map.leszyStatue, {
		onCaught = function(player: Player)
			local session = sessions[player]
			if session then
				engulf(session, "MSG_CAUGHT")
			end
		end,
		onEscaped = function(player: Player)
			local session = sessions[player]
			if session then
				notify(session, "MSG_ESCAPED", { Economy.basketValue(session.data.basket) })
			end
		end,
		onGaveUp = function(player: Player)
			local session = sessions[player]
			if session then
				notify(session, "MSG_LESZY_GAVE_UP")
			end
		end,
	})

	HoardService.start(map.groveCenter, {
		take = function(player: Player, item: HoardService.Item): boolean
			local session = sessions[player]
			if not session then
				return false
			end
			local basket = session.data.basket
			if #basket >= basketMax(session) then
				notify(session, "MSG_BASKET_FULL")
				return false
			end
			table.insert(basket, { s = item.s, v = item.v, x = item.x })
			session.data.atlas[item.s] = true
			if LeszyService.startChase(player, map.groveCenter) then
				notify(session, "MSG_LESZY_WOKE")
			end
			pushState(session)
			return true
		end,
	})

	DryingService.start(map.racks, {
		getData = function(player: Player)
			local session = sessions[player]
			return if session then session.data else nil
		end,
		basketMax = function(player: Player): number
			local session = sessions[player]
			return if session then basketMax(session) else 0
		end,
		notify = function(player: Player, key: string, args: { any }?, nameKey: string?)
			local session = sessions[player]
			if session then
				notify(session, key, args, nameKey)
			end
		end,
		pushState = function(player: Player)
			local session = sessions[player]
			if session then
				pushState(session)
			end
		end,
	})

	setupDevCommands()

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
