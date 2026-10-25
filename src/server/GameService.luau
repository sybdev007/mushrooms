--!strict
-- Główna pętla gry po stronie serwera.
-- Serwer jest jedynym źródłem prawdy: olej, koszyk, monety i ulepszenia liczymy tutaj.
-- Klient tylko pokazuje stan i wysyła prośby (zbierz / sprzedaj / kup).

local MarketplaceService = game:GetService("MarketplaceService")
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
local ChaseService = require(script.Parent.ChaseService)
local HoardService = require(script.Parent.HoardService)
local World = script.Parent:WaitForChild("World")
local LeszyModel = require(World:WaitForChild("Leszy"))
local SkarbnikModel = require(World:WaitForChild("Skarbnik"))
local UtopiecModel = require(World:WaitForChild("Utopiec"))
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
	rescue: Rescue?, -- koszyk do uratowania za Robuxy (przez chwilę po zgaśnięciu latarni / złapaniu)
}

type Rescue = {
	items: { any }, -- wszystko, co gracz stracił
	reclaimed: { any }, -- z tego: grzyby strażnika (trafią do legowiska, jeśli nikt nie uratuje)
	guardian: string?,
	expiresAt: number,
	drop: () -> (), -- oddaje grzyby strażnika do legowiska (gdy nikt nie uratował)
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

-- Strażnicy skarbów: Leszy w lesie, Skarbnik w jaskini, Utopiec na bagnach.
-- Każdy ma te same zasady (ChaseService + HoardService), różnią się liczbami, modelem i komunikatami.
type GuardianDef = {
	settings: ChaseService.Settings,
	model: { build: (Instance, CFrame, boolean) -> Model, setAwake: (Model, boolean) -> () },
	woke: string,
	caught: string,
	gaveUp: string,
	escaped: string,
	hoardDrop: string,
	respawn: number,
}
local GUARDIANS: { [string]: GuardianDef } = {
	leszy = {
		settings = Config.Leszy,
		model = LeszyModel,
		woke = "MSG_LESZY_WOKE",
		caught = "MSG_CAUGHT",
		gaveUp = "MSG_LESZY_GAVE_UP",
		escaped = "MSG_ESCAPED",
		hoardDrop = "MSG_HOARD_DROP",
		respawn = Config.Grove.respawnSeconds,
	},
	skarbnik = {
		settings = Config.Skarbnik,
		model = SkarbnikModel,
		woke = "MSG_SKARBNIK_WOKE",
		caught = "MSG_CAUGHT_SKARBNIK",
		gaveUp = "MSG_SKARBNIK_GAVE_UP",
		escaped = "MSG_ESCAPED_SKARBNIK",
		hoardDrop = "MSG_HOARD_DROP_SKARBNIK",
		respawn = Config.Lair.respawnSeconds,
	},
	utopiec = {
		settings = Config.Utopiec,
		model = UtopiecModel,
		woke = "MSG_UTOPIEC_WOKE",
		caught = "MSG_CAUGHT_UTOPIEC",
		gaveUp = "MSG_UTOPIEC_GAVE_UP",
		escaped = "MSG_ESCAPED_UTOPIEC",
		hoardDrop = "MSG_HOARD_DROP_UTOPIEC",
		respawn = Config.UtopiecLair.respawnSeconds,
	},
}
local chasers: { [string]: ChaseService.Chaser } = {}
local hoards: { [string]: HoardService.Hoard } = {}

local function stopChases(player: Player)
	for _, chaser in chasers do
		chaser.stop(player)
	end
end

-- Nazwa strażnika, który goni gracza, albo nil
local function chasedBy(player: Player): string?
	for name, chaser in chasers do
		if chaser.isChased(player) then
			return name
		end
	end
	return nil
end

-- Strażnik pilnujący miejsca na grzyb (gniazdo, skarbiec, staw) albo nil
local function spotGuardian(spot: MapBuilder.Spot): string?
	if spot.grove then
		return "leszy"
	elseif spot.lair then
		return "skarbnik"
	end
	return spot.guardian
end

-- Światy za portalami: flaga w zapisie, warunek wejścia i komunikaty
type WorldGate = {
	flag: string,
	canEnter: (coins: number, unlocked: boolean?) -> boolean,
	unlockCoins: number,
	unlocked: string,
	enter: string,
	find: string,
	engulfed: string,
}
local WORLD_GATES: { [string]: WorldGate } = {
	cave = {
		flag = "caveUnlocked",
		canEnter = Economy.canEnterCave,
		unlockCoins = Config.Cave.unlockCoins,
		unlocked = "MSG_CAVE_UNLOCKED",
		enter = "MSG_CAVE_ENTER",
		find = "MSG_PORTAL_FIND",
		engulfed = "MSG_ENGULFED_CAVE",
	},
	swamp = {
		flag = "swampUnlocked",
		canEnter = Economy.canEnterSwamp,
		unlockCoins = Config.Swamp.unlockCoins,
		unlocked = "MSG_SWAMP_UNLOCKED",
		enter = "MSG_SWAMP_ENTER",
		find = "MSG_PORTAL_FIND_SWAMP",
		engulfed = "MSG_ENGULFED_SWAMP",
	},
}
local map: MapBuilder.MapInfo

local function stat(session: Session, id: string): number
	return Economy.upgradeStat(id, session.data.upgrades[id] or 0)
end

-- Deweloper: Studio, twórca gry albo konto z Config.DevUserIds (komenda /coins, panel DEV)
local function isDeveloper(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId then
		return true
	end
	return table.find(Config.DevUserIds, player.UserId) ~= nil
end

-- Koszyk + plecak górnika (ulepszenie z obozowiska w jaskini)
local function basketMax(session: Session): number
	return stat(session, "basket") + stat(session, "pack") + stat(session, "creel")
end

-- Mnożnik spalania oleju w świecie strefy (knot z jaskini albo z bagien)
-- Wysyp (kupiony za Robuxy) działa dla całego serwera; czas w os.time(), żeby klienci mogli odliczać
local boomUntil = 0

local function boomActive(): boolean
	return os.time() < boomUntil
end

-- Mnożnik szans na mutacje: Wysyp dla wszystkich, mikstura szczęścia dla kupującego
local function luckFactor(session: Session): number
	local luck = 1
	if boomActive() then
		luck *= Config.Boom.luck
	end
	if os.time() < session.data.luckUntil then
		luck *= Config.LuckPotion.luck
	end
	return luck
end

local function oilScale(session: Session, zone: number): number
	local upgrade = Economy.worldOilUpgrade(Economy.zoneWorld(zone))
	return if upgrade then stat(session, upgrade) else 1
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
		chased = chasedBy(session.player) ~= nil,
		chaser = chasedBy(session.player),
		caveUnlocked = data.caveUnlocked,
		swampUnlocked = data.swampUnlocked,
		luckUntil = data.luckUntil,
		boomUntil = boomUntil,
		dev = isDeveloper(session.player),
	})
end

-- Losuje gatunek, wariant i cechy grzyba. countPity = to jest odrost po zebraniu
-- (początkowe rozstawienie lasu nie nabija gwarancji).
local function rollSpot(session: Session, spot: MapBuilder.Spot, countPity: boolean?): (string?, string?, { string }?)
	local species
	local guardian = spotGuardian(spot)
	if guardian then
		local list = Economy.guardianSpecies(guardian)
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
	local luck = luckFactor(session)
	local variant = Economy.rollVariant(session.rng:NextNumber(), if forced then 2 else nil, luck)
	if countPity then
		data.pity = if Economy.variantRank(variant) >= 2 then 0 else data.pity + 1
	end

	local tags: { string }? = nil
	for _, tag in Economy.tagsForZone(spot.zone) do
		if session.rng:NextNumber() < tag.chance * luck then
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

-- Latarnia zgasła albo strażnik złapał gracza: zabiera koszyk i wyrzuca gracza do chatki / obozu.
-- messageKey mówi klientowi, który ekran pokazać; guardian: kto złapał (jego grzyby wracają do legowiska).
local function engulf(session: Session, messageKey: string?, guardian: string?)
	stopChases(session.player)
	local basket = session.data.basket

	-- Strażnik odbiera swoje grzyby i odnosi je do legowiska, gdzie może je zabrać każdy
	local reclaimed: { HoardService.Item } = {}
	if guardian then
		for index = #basket, 1, -1 do
			if Economy.guardianOf(basket[index].s) == guardian then
				table.insert(reclaimed, table.remove(basket, index) :: any)
			end
		end
	end

	local lost = Economy.engulfLoss(#basket)
	local removed: { any } = table.clone(reclaimed)
	for _ = 1, lost do
		table.insert(removed, table.remove(basket))
	end
	lost += #reclaimed
	session.oil = stat(session, "oil")
	session.oilWarned = false
	session.oilHalfWarned = false
	-- W jaskini i na bagnach gracz budzi się w obozie swojego świata, a nie w chatce
	local root = getRoot(session.player)
	local world = if root then Economy.zoneWorld(Economy.zoneIndexAt(root.Position.Z)) else "forest"
	local worldInfo = map.worlds[world]
	local target = if worldInfo and worldInfo.camp then worldInfo.camp else map.spawnCFrame
	local character = session.player.Character
	if character then
		character:PivotTo(target)
	end
	session.zone = Economy.zoneIndexAt(target.Position.Z)
	local gate = WORLD_GATES[world]
	notify(session, messageKey or (if gate then gate.engulfed else "MSG_ENGULFED"), { lost })

	-- Grzyby strażnika trafiają do legowiska dopiero, gdy minie czas na uratowanie koszyka
	local function dropToHoard()
		local hoard = if guardian then hoards[guardian] else nil
		if #reclaimed > 0 and hoard and guardian then
			local placed = hoard.drop(reclaimed)
			if placed > 0 then
				-- Cały serwer wie, że w legowisku leży coś do zgarnięcia
				for _, other in sessions do
					notify(other, GUARDIANS[guardian].hoardDrop, { session.player.DisplayName, placed })
				end
			end
		end
	end

	-- Poprzednia okazja do ratunku przepada od razu (jej grzyby strażnika idą do legowiska)
	local previous = session.rescue
	if previous then
		session.rescue = nil
		previous.drop()
	end
	if #removed == 0 then
		return
	end
	local rescue: Rescue = {
		items = removed,
		reclaimed = reclaimed,
		guardian = guardian,
		expiresAt = os.clock() + Config.Rescue.serverSeconds,
		drop = dropToHoard,
	}
	session.rescue = rescue
	notify(session, "RESCUE_OFFER", { Economy.basketValue(removed :: any), Config.Rescue.buttonSeconds })
	task.delay(Config.Rescue.serverSeconds, function()
		if session.rescue == rescue then
			session.rescue = nil
			dropToHoard()
		end
	end)
end

-- Portale: wejście do świata (za strażnikiem poprzedniego świata), skrót na Placu Portali
-- i powrót z obozu do chatki
local function near(root: BasePart, point: Vector3?): boolean
	if not point then
		return false
	end
	local offset = root.Position - point
	return Vector3.new(offset.X, 0, offset.Z).Magnitude <= Config.Cave.portalRadius
end

local function travel(session: Session, character: Model, target: CFrame, message: string)
	-- Przejście przez portal kończy pościg (strażnicy nie opuszczają swojego świata)
	stopChases(session.player)
	character:PivotTo(target)
	session.zone = Economy.zoneIndexAt(target.Position.Z)
	notify(session, message)
end

local function checkPortals(session: Session, root: BasePart, now: number)
	local character = session.player.Character
	if not character then
		return
	end
	local data = session.data :: any
	for world, info in map.worlds do
		local gate = WORLD_GATES[world]
		if not gate or not info.camp then
			continue
		end
		if near(root, info.portal) then
			if gate.canEnter(data.coins, data[gate.flag]) then
				local first = not data[gate.flag]
				data[gate.flag] = true
				travel(session, character, info.camp, if first then gate.unlocked else gate.enter)
			elseif now - session.portalNoticeAt > 4 then
				session.portalNoticeAt = now
				notify(session, "MSG_PORTAL_LOCKED", { gate.unlockCoins })
			end
			return
		elseif near(root, info.shortcut) then
			if data[gate.flag] then
				travel(session, character, info.camp, gate.enter)
			elseif now - session.portalNoticeAt > 4 then
				session.portalNoticeAt = now
				notify(session, gate.find)
			end
			return
		elseif near(root, info.returnPortal) then
			travel(session, character, map.spawnCFrame, "MSG_PORTAL_HOME")
			return
		end
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
				session.oil -= Economy.oilDrain(zone, oilScale(session, zone)) * step
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
	stopChases(player)
	-- Wyszedł z niewykorzystaną okazją do ratunku: grzyby strażnika wracają do legowiska od razu
	local rescue = session.rescue
	if rescue then
		session.rescue = nil
		rescue.drop()
	end
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

	local guardian = spotGuardian(spot)
	local function regrow()
		-- Grzyb odrośnie później i może to być inny gatunek
		local speciesId, variant, tags = rollSpot(session, spot, true)
		state.visible = false
		local seconds = if guardian then GUARDIANS[guardian].respawn else Config.RespawnSeconds
		state.readyAt = now + seconds * (if boomActive() then Config.Boom.regrowFactor else 1)
		state.speciesId = speciesId or state.speciesId
		state.variant = variant
		state.tags = tags
		MushroomRemoved:FireClient(player, spotId)
	end

	-- Błędny ognik: udawał grzyb, a teraz kradnie olej z latarni
	if Economy.isMimic(state.speciesId) then
		local oilMax = stat(session, "oil")
		session.oil = math.max(session.oil - oilMax * Config.Swamp.mimicOilLoss, 1)
		regrow()
		notify(session, "MSG_MIMIC", { math.floor(Config.Swamp.mimicOilLoss * 100) })
		pushState(session)
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

	regrow()
	-- Grzyb z legowiska budzi jego strażnika
	local chaser = guardian and chasers[guardian]
	if guardian and chaser and chaser.startChase(player, spot.position) then
		notify(session, GUARDIANS[guardian].woke)
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

-- Panel DEV (przycisk 🛠 widoczny tylko dla deweloperów). Serwer sprawdza uprawnienia przy każdej akcji.
local DEV_TELEPORTS: { [string]: () -> CFrame? } = {
	tpCabin = function()
		return map.spawnCFrame
	end,
	tpPlaza = function()
		return CFrame.new(Config.Cave.shortcut.x, 4, Config.Cave.shortcut.z + 16)
	end,
	tpGrove = function()
		return CFrame.new(Config.Grove.centerX, 4, Config.Grove.centerZ - Config.Grove.radius - 8) * CFrame.Angles(0, math.pi, 0)
	end,
	tpPortal = function()
		return CFrame.new(Config.Cave.portal.x, 4, Config.Cave.portal.z - 12) * CFrame.Angles(0, math.pi, 0)
	end,
	tpCamp = function()
		local info = map.worlds.cave
		return info and info.camp
	end,
	tpAbyss = function()
		return CFrame.new(0, 4, Config.Zones[8].startZ + 10) * CFrame.Angles(0, math.pi, 0)
	end,
	tpLair = function()
		return CFrame.new(Config.Lair.centerX + 6, 4, Config.Lair.centerZ - Config.Lair.radius - 6) * CFrame.Angles(0, math.pi, 0)
	end,
	tpSwamp = function()
		local info = map.worlds.swamp
		return info and info.camp
	end,
	tpPond = function()
		local lair = Config.UtopiecLair
		return CFrame.new(lair.centerX + 4, 4, lair.centerZ - lair.radius - 10) * CFrame.Angles(0, math.pi, 0)
	end,
}

local function onDevAction(player: Player, action: unknown)
	local session = sessions[player]
	if not session or typeof(action) ~= "string" or not isDeveloper(player) then
		return
	end
	local data = session.data
	local teleport = DEV_TELEPORTS[action]
	if teleport then
		local target = teleport()
		local character = player.Character
		if target and character then
			stopChases(player)
			character:PivotTo(target)
			session.zone = Economy.zoneIndexAt(target.Position.Z)
		end
	elseif action == "coins10k" then
		data.coins += 10000
	elseif action == "coins100k" then
		data.coins += 100000
	elseif action == "coinsZero" then
		data.coins = 0
	elseif action == "caveUnlock" then
		data.caveUnlocked = true
	elseif action == "caveLock" then
		data.caveUnlocked = false
	elseif action == "swampUnlock" then
		data.swampUnlocked = true
	elseif action == "swampLock" then
		data.swampUnlocked = false
	elseif action == "coins1m" then
		data.coins += 1000000
	elseif action == "oilFull" then
		session.oil = stat(session, "oil")
	elseif action == "oilLow" then
		session.oil = stat(session, "oil") * 0.1
	elseif action == "upgradesMax" or action == "upgradesReset" then
		for id, def in Config.Upgrades do
			data.upgrades[id] = if action == "upgradesMax" then def.maxLevel else 0
		end
		session.oil = stat(session, "oil")
		applyCharacterStats(session)
		DryingService.refresh(player)
	elseif action == "basketClear" then
		table.clear(data.basket)
	else
		return
	end
	notify(session, "MSG_DEV_DONE", { action })
	pushState(session)
end

-- ===== Zakupy za Robuxy =====

-- Daje graczowi kupioną rzecz. Zwraca false, gdy nie da się jej teraz dać (Roblox spróbuje później,
-- a jeśli się nie uda, odda Robuxy).
local function grantProduct(session: Session, key: string): boolean
	local player = session.player
	local data = session.data
	if key == "rescue" then
		local rescue = session.rescue
		if not rescue or os.clock() > rescue.expiresAt then
			return false
		end
		session.rescue = nil
		for _, item in rescue.items do
			table.insert(data.basket, item)
		end
		notify(session, "MSG_RESCUED", { Economy.basketValue(rescue.items :: any) })
	elseif key == "boom" then
		boomUntil = math.max(os.time(), boomUntil) + Config.Boom.seconds
		-- Grzyby, które właśnie odrastają, też przyspieszają
		local now = os.clock()
		for _, other in sessions do
			for _, state in other.spots do
				if not state.visible and state.readyAt > now then
					state.readyAt = now + (state.readyAt - now) * Config.Boom.regrowFactor
				end
			end
			notify(other, "MSG_BOOM", { player.DisplayName, math.floor(Config.Boom.seconds / 60) })
			pushState(other)
		end
	elseif key == "oil" then
		session.oil = stat(session, "oil")
		session.oilWarned = false
		session.oilHalfWarned = false
		notify(session, "MSG_OIL_BOUGHT")
	elseif key == "dry" then
		if #data.drying == 0 then
			return false
		end
		-- Czas rozwieszenia cofamy tak, jakby grzyby wisiały już pełne 10 minut
		local driedAt = os.time() - Config.Drying.seconds
		for _, item in data.drying do
			item.t = math.min(item.t, driedAt)
		end
		DryingService.refresh(player)
		notify(session, "MSG_DRIED")
	elseif key == "luck" then
		data.luckUntil = math.max(os.time(), data.luckUntil) + Config.LuckPotion.seconds
		notify(session, "MSG_LUCK", { math.floor(Config.LuckPotion.seconds / 60) })
	else
		return false
	end
	pushState(session)
	return true
end

local productById: { [number]: string } = {}
for key, def in Config.Products do
	if def.id ~= 0 then
		productById[def.id] = key
	end
end

local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local session = player and sessions[player]
	local key = productById[receipt.ProductId]
	if not session or not key then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receipt.PurchaseId)
	-- Ten sam zakup może przyjść drugi raz (np. po zerwanym połączeniu): wtedy nic nie dajemy drugi raz
	if table.find(session.data.receipts, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	if not grantProduct(session, key) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	table.insert(session.data.receipts, purchaseId)
	while #session.data.receipts > 50 do
		table.remove(session.data.receipts, 1)
	end
	if session.canSave then
		task.spawn(DataService.save, session.player, session.data)
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Produkt bez numeru (id = 0) w Studio: dajemy go za darmo, żeby dało się testować przed utworzeniem
local function onStudioPurchase(player: Player, key: unknown)
	local session = sessions[player]
	if not session or typeof(key) ~= "string" or not RunService:IsStudio() then
		return
	end
	local def = Config.Products[key]
	if def and def.id == 0 then
		grantProduct(session, key)
	end
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

	-- Strażnicy: ten sam pościg, inne liczby i modele. Złapie = koszyk przepada, a jego grzyby
	-- wracają do legowiska, skąd każdy może je ukraść (zabranie znów go budzi).
	for name, def in GUARDIANS do
		local place = map.guardians[name]
		if not place then
			continue
		end
		chasers[name] = ChaseService.new({
			name = string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2),
			origin = place.origin,
			statue = place.statue,
			settings = def.settings,
			build = def.model.build,
			setAwake = def.model.setAwake,
			hooks = {
				onCaught = function(player: Player)
					local session = sessions[player]
					if session then
						engulf(session, def.caught, name)
					end
				end,
				onEscaped = function(player: Player)
					local session = sessions[player]
					if session then
						notify(session, def.escaped, { Economy.basketValue(session.data.basket) })
					end
				end,
				onGaveUp = function(player: Player)
					local session = sessions[player]
					if session then
						notify(session, def.gaveUp)
					end
				end,
			},
		})
		hoards[name] = HoardService.new(place.origin, name .. "Hoard", {
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
				local chaser = chasers[name]
				if chaser and chaser.startChase(player, place.origin) then
					notify(session, def.woke)
				end
				pushState(session)
				return true
			end,
		})
	end

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
	Remotes.get("DevAction").OnServerEvent:Connect(onDevAction)
	Remotes.get("StudioPurchase").OnServerEvent:Connect(onStudioPurchase)
	MarketplaceService.ProcessReceipt = processReceipt

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
