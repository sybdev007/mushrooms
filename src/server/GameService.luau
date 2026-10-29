--!strict
-- Główna pętla gry po stronie serwera.
-- Serwer jest jedynym źródłem prawdy: olej, koszyk, monety i ulepszenia liczymy tutaj.
-- Klient tylko pokazuje stan i wysyła prośby (zbierz / sprzedaj / kup).

local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Remotes = require(Shared.Remotes)
local Cycle = require(Shared.Cycle)
local Expedition = require(Shared.Expedition)
local DataService = require(script.Parent.DataService)
local MapBuilder = require(script.Parent.MapBuilder)
local ChaseService = require(script.Parent.ChaseService)
local HoardService = require(script.Parent.HoardService)
local World = script.Parent:WaitForChild("World")
local LeszyModel = require(World:WaitForChild("Leszy"))
local SkarbnikModel = require(World:WaitForChild("Skarbnik"))
local UtopiecModel = require(World:WaitForChild("Utopiec"))
local HandTools = require(World:WaitForChild("HandTools"))
local GardenService = require(script.Parent.GardenService)
local ProgressService = require(script.Parent.ProgressService)
local TutorialService = require(script.Parent.TutorialService)
local LeaderboardService = require(script.Parent.LeaderboardService)

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
	basketKey: string?, -- odcisk koszyka ostatnio wysłanego klientowi
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
	group: number, -- ilu graczy idzie razem (wspólna wyprawa: ten gracz + sąsiedzi w promieniu)
	groupNoticeAt: number, -- kiedy ostatnio mówiliśmy „wspólna wyprawa” (żeby nie spamować)
	downedUntil: number?, -- latarnia zgasła i gracz czeka na podniesienie (os.clock końca)
	downed: { Instance }?, -- przycisk „Podnieś” i napis SOS nad głową
	debugGroupUntil: number?, -- panel DEV: udawana grupa 3 graczy do tej chwili (os.clock)
	tutorialSpots: { [string]: Vector3 }?, -- grzyby samouczka tego gracza (TutorialService)
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

-- Mnożnik szans na mutacje: Wysyp dla wszystkich, mikstura szczęścia dla kupującego,
-- nożyk gracza, zdarzenie nocy (pełnia, krwawy księżyc) i głębokość strefy
local function luckFactor(session: Session, zone: number?): number
	local total = Economy.luck({
		knifeLevel = session.data.upgrades.knife or 0,
		zone = zone,
		event = Cycle.activeEvent(os.time()),
		boom = boomActive(),
		potion = os.time() < session.data.luckUntil,
	})
	return total
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
	-- Koszyk (lista grzybów do panelu sprzedaży) wysyłamy tylko po zmianie
	local key = Economy.basketKey(data.basket)
	local basketList = nil
	if session.basketKey ~= key then
		session.basketKey = key
		basketList = data.basket
	end
	StateUpdate:FireClient(session.player, {
		basket = basketList,
		basketKey = key,
		coins = data.coins,
		oil = math.max(session.oil, 0),
		oilMax = stat(session, "oil"),
		basketCount = #data.basket,
		basketMax = basketMax(session),
		basketValue = Economy.basketValue(data.basket),
		lanternRange = stat(session, "lantern") * Expedition.light(session.group),
		group = session.group,
		downed = if session.downedUntil then math.max(0, math.ceil(session.downedUntil - os.clock())) else nil,
		zone = session.zone,
		upgrades = table.clone(data.upgrades),
		chased = chasedBy(session.player) ~= nil,
		chaser = chasedBy(session.player),
		caveUnlocked = data.caveUnlocked,
		swampUnlocked = data.swampUnlocked,
		luckUntil = data.luckUntil,
		boomUntil = boomUntil,
		dev = isDeveloper(session.player),
		tutorial = data.tutorial,
		tutorialSell = TutorialService.sellRule(session :: any),
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
	local luck = luckFactor(session, spot.zone)
	local variant = Economy.rollVariant(session.rng:NextNumber(), if forced then 2 else nil, luck)
	if countPity then
		data.pity = if Economy.variantRank(variant) >= 2 then 0 else data.pity + 1
	end

	local tags: { string }? = nil
	for _, tag in Economy.tagsForZone(spot.zone) do
		if session.rng:NextNumber() < Economy.tagOdds(tag, luck) then
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
-- Latarnia w prawej ręce i nożyk w lewej (modele w World/HandTools). Przebudowujemy je,
-- gdy zmieni się poziom ulepszenia (okucia latarni, wygląd nożyka).
local function handOf(character: Model, side: string): (BasePart?, boolean)
	local hand = character:FindFirstChild(side .. "Hand") or character:FindFirstChild(side .. " Arm")
	if hand and hand:IsA("BasePart") then
		return hand, hand.Name == side .. " Arm"
	end
	return nil, false
end

local function attachHandLantern(character: Model, level: number)
	local existing = character:FindFirstChild("HandLantern")
	if existing and existing:GetAttribute("Tier") == HandTools.lanternTier(level) then
		return
	end
	if existing then
		existing:Destroy()
	end
	local hand, isR6 = handOf(character, "Right")
	if not hand then
		return
	end
	-- Pałąk w dłoni, latarnia wisi pod ręką
	local grip = hand.CFrame * CFrame.new(0, if isR6 then -1.05 else -0.12, 0)
	HandTools.lantern(level, grip, hand).Parent = character
end

local function attachHandKnife(character: Model, level: number)
	local existing = character:FindFirstChild("HandKnife")
	if existing and existing:GetAttribute("Level") == level then
		return
	end
	if existing then
		existing:Destroy()
	end
	local hand, isR6 = handOf(character, "Left")
	if not hand then
		return
	end
	-- Nóż trzymany luźno przy nodze: ostrze w dół i trochę na zewnątrz, grzbietem do tyłu.
	-- Kierunek liczymy od ustawienia postaci (osie dłoni różnią się między rigami), a do przodu
	-- go nie kierujemy, bo kamera stoi za graczem i ciało by go zasłaniało.
	local root = character:FindFirstChild("HumanoidRootPart")
	local basis = if root and root:IsA("BasePart") then root.CFrame else hand.CFrame
	local pos = (if isR6 then hand.Position - Vector3.new(0, 0.95, 0) else hand.Position - Vector3.new(0, 0.05, 0))
		- basis.RightVector * 0.15
	local direction = (Vector3.new(0, -0.85, 0) - basis.RightVector * 0.45 + basis.LookVector * 0.2).Unit
	local grip = CFrame.lookAt(pos, pos + direction, -basis.LookVector)
	HandTools.knife(level, grip, hand).Parent = character
end

local function applyCharacterStats(session: Session)
	local character = session.player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Złodziej niosący grzyb idzie wolniej (GardenService.speedFactor)
		humanoid.WalkSpeed = stat(session, "boots") * GardenService.speedFactor(session.player)
		-- Zgasła latarnia: gracz stoi w miejscu i czeka na kumpla
		if session.downedUntil then
			humanoid.WalkSpeed = 0
		end
		humanoid.JumpHeight = if session.downedUntil then 0 else 7.2
		humanoid.JumpPower = if session.downedUntil then 0 else 50
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
		-- Wspólna wyprawa świeci dalej; 60 to limit Robloxa dla PointLight
		lantern.Range = math.min(stat(session, "lantern") * Expedition.light(session.group), 60)
	end
	attachHandLantern(character, session.data.upgrades.lantern or 0)
	attachHandKnife(character, session.data.upgrades.knife or 0)
end

-- Latarnia zgasła albo strażnik złapał gracza: zabiera koszyk i wyrzuca gracza do chatki / obozu.
-- messageKey mówi klientowi, który ekran pokazać; guardian: kto złapał (jego grzyby wracają do legowiska).
local clearDowned: (Session) -> ()

local function engulf(session: Session, messageKey: string?, guardian: string?)
	clearDowned(session)
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

-- ===== Wspólne wyprawy i ratunek =====

local function setLanternRange(session: Session)
	local root = getRoot(session.player)
	local attachment = root and root:FindFirstChild(LANTERN_ATTACHMENT)
	local light = attachment and attachment:FindFirstChild("Lantern")
	if light and light:IsA("PointLight") then
		light.Range = math.min(stat(session, "lantern") * Expedition.light(session.group), 60)
	end
end

function clearDowned(session: Session)
	if not session.downedUntil then
		return
	end
	session.downedUntil = nil
	for _, instance in session.downed or {} do
		instance:Destroy()
	end
	session.downed = nil
	applyCharacterStats(session)
end

-- Ktoś, kto może przyjść z pomocą: inny gracz w pobliżu, któremu latarnia jeszcze świeci
local function helperNear(session: Session): boolean
	local root = getRoot(session.player)
	if not root then
		return false
	end
	for _, other in sessions do
		local otherRoot = getRoot(other.player)
		if other ~= session and otherRoot and not other.downedUntil then
			if (otherRoot.Position - root.Position).Magnitude <= Expedition.HELP_RADIUS then
				return true
			end
		end
	end
	return false
end

local function revive(session: Session, helper: Player)
	local helperSession = sessions[helper]
	if not session.downedUntil or not helperSession or helperSession == session or helperSession.downedUntil then
		return
	end
	local root, helperRoot = getRoot(session.player), getRoot(helper)
	if not (root and helperRoot) or (root.Position - helperRoot.Position).Magnitude > Expedition.REVIVE_DISTANCE + 3 then
		return
	end
	clearDowned(session)
	session.oil = stat(session, "oil") * Expedition.REVIVE_OIL
	session.oilHalfWarned = true
	notify(session, "MSG_REVIVED", { helper.DisplayName, math.floor(Expedition.REVIVE_OIL * 100) })
	notify(helperSession, "MSG_REVIVE_DONE", { session.player.DisplayName })
	ProgressService.event(helper, "revive", 1)
	pushState(session)
	pushState(helperSession)
end

-- Latarnia zgasła, ale ktoś jest w pobliżu: gracz stoi w mroku z sygnałem SOS, a kumpel ma
-- chwilę, żeby podejść i go podnieść (przycisk na postaci). Inaczej las pochłania jak zwykle.
local function startDowned(session: Session)
	local player = session.player
	local character = player.Character
	local root = getRoot(player)
	local head = character and character:FindFirstChild("Head")
	if not (character and root and head and head:IsA("BasePart")) then
		engulf(session)
		return
	end
	session.oil = 0
	session.downedUntil = os.clock() + Expedition.DOWN_SECONDS
	applyCharacterStats(session)

	-- Napis SOS nad głową, widoczny z daleka (także przez drzewa)
	local sos = Instance.new("BillboardGui")
	sos.Name = "SOS"
	sos.Size = UDim2.fromOffset(200, 40)
	sos.StudsOffset = Vector3.new(0, 3.2, 0)
	sos.AlwaysOnTop = true
	sos.MaxDistance = Expedition.HELP_RADIUS
	sos.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 90, 70)
	label.TextStrokeTransparency = 0.2
	label.Text = "🆘 " .. player.DisplayName
	label.Parent = sos
	sos.Parent = head

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RevivePrompt"
	prompt.ActionText = "Help up" -- klient podmienia na tekst w języku gracza (ExpeditionView)
	prompt.ObjectText = player.DisplayName
	prompt.HoldDuration = Expedition.REVIVE_HOLD
	prompt.MaxActivationDistance = Expedition.REVIVE_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt:SetAttribute("OwnerUserId", player.UserId)
	prompt.Parent = root
	prompt.Triggered:Connect(function(helper)
		revive(session, helper)
	end)
	CollectionService:AddTag(prompt, "RevivePrompt")
	session.downed = { sos, prompt }

	notify(session, "MSG_DOWNED", { Expedition.DOWN_SECONDS })
	for _, other in sessions do
		local otherRoot = getRoot(other.player)
		if other ~= session and otherRoot and (otherRoot.Position - root.Position).Magnitude <= Expedition.HELP_RADIUS then
			notify(other, "MSG_PLAYER_DOWN", { player.DisplayName })
		end
	end
	pushState(session)
end

-- Kto z kim idzie: gracze z żywą latarnią w niebezpiecznych strefach
local function updateGroups()
	local walkers: { Expedition.Walker } = {}
	for _, session in sessions do
		local root = getRoot(session.player)
		if root and not session.downedUntil and not Economy.isSafeZone(session.zone) then
			table.insert(walkers, { id = session, position = root.Position })
		end
	end
	local sizes = Expedition.groupSizes(walkers)
	local now = os.clock()
	for _, session in sessions do
		local size = sizes[session] or 1
		if session.debugGroupUntil and now < session.debugGroupUntil then
			size = math.max(size, 3)
		end
		if size ~= session.group then
			local formed = size > 1 and session.group <= 1
			session.group = size
			setLanternRange(session)
			if formed and now - session.groupNoticeAt > 30 then
				session.groupNoticeAt = now
				local oil, light = Expedition.bonusPercents(size)
				notify(session, "MSG_GROUP_FORMED", { oil, light })
			end
		end
	end
end

local function tick(step: number)
	local now = os.clock()
	updateGroups()
	for _, session in sessions do
		local root = getRoot(session.player)
		-- Czeka na podniesienie: olej nie spada, a gdy minie czas, las go pochłania
		if session.downedUntil then
			if now >= session.downedUntil then
				engulf(session)
			end
			pushState(session)
			continue
		end
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
				-- Wspólna wyprawa: połączone latarnie palą mniej
				session.oil -= Economy.oilDrain(zone, oilScale(session, zone)) * Expedition.drain(session.group) * step
				-- W samouczku latarnia nigdy nie gaśnie do końca (ostrzeżenia działają, Leszy nie łapie)
				if session.data.tutorial < Config.Tutorial.done then
					session.oil = math.max(session.oil, 1)
				end
				if not session.oilHalfWarned and session.oil <= oilMax * Config.OilWarnFraction then
					session.oilHalfWarned = true
					notify(session, "MSG_OIL_HALF")
				end
				if not session.oilWarned and session.oil <= oilMax * Config.OilLowFraction then
					session.oilWarned = true
					notify(session, "MSG_OIL_LOW")
				end
				if session.oil <= 0 then
					if helperNear(session) then
						startDowned(session)
					else
						engulf(session)
					end
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
	-- Nowa postać (reset, śmierć): stan „czeka na pomoc” przepada razem ze starą
	session.downedUntil = nil
	session.downed = nil
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
		group = 1,
		groupNoticeAt = 0,
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
	GardenService.assign(player)
	ProgressService.join(player)

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
	TutorialService.onJoin(session :: any)
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
	session.downedUntil = nil
	-- Wyszedł z niewykorzystaną okazją do ratunku: grzyby strażnika wracają do legowiska od razu
	local rescue = session.rescue
	if rescue then
		session.rescue = nil
		rescue.drop()
	end
	GardenService.release(player)
	ProgressService.leave(player)
	LeaderboardService.leave(player, session.data)
	saveSession(session)
end

-- Panel DEV: wymuszona pora na chwilę (do sprawdzania świtu bez czekania 18 minut)
local debugPhase: string? = nil
local debugUntil = 0

-- Komunikat na początek nocy, osobny dla każdego zdarzenia
local NIGHT_MESSAGES: { [string]: string } = {
	calm = "MSG_NIGHT_CALM",
	full_moon = "MSG_NIGHT_FULL_MOON",
	rain = "MSG_NIGHT_RAIN",
	mist = "MSG_NIGHT_MIST",
	blood_moon = "MSG_NIGHT_BLOOD_MOON",
}

-- Świt: las u każdego gracza odrasta od nowa (nowe gatunki i mutacje w tych samych miejscach).
-- Klient podmienia grzyby o tych samych id, więc nie trzeba ich osobno usuwać.
local function resetForest(nextEvent: Config.NightEventDef)
	local now = os.clock()
	for _, session in sessions do
		for id, state in session.spots do
			local spot = map.spotById[id]
			if spot then
				local speciesId, variant, tags = rollSpot(session, spot)
				state.speciesId = speciesId or state.speciesId
				state.variant = variant
				state.tags = tags
				state.visible = false
				state.readyAt = now
			end
		end
		syncReadySpots(session, now)
		notify(session, "MSG_DAWN", { nextEvent.icon }, nextEvent.key)
	end
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

	-- Grzyby samouczka mają własną obsługę
	if TutorialService.pick(session :: any, spotId) then
		return
	end

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
		local event = Cycle.activeEvent(os.time())
		state.readyAt = now
			+ seconds * (if boomActive() then Config.Boom.regrowFactor else 1) * (if event then event.regrow else 1)
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

	local item = { s = state.speciesId, v = state.variant, x = state.tags }
	table.insert(basket, item)
	ProgressService.found(player, item, "pick")

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

local function cooledDown(session: Session): boolean
	local now = os.clock()
	if now - session.lastAction < ACTION_COOLDOWN then
		return false
	end
	session.lastAction = now
	return true
end

-- Sprzedaż: u skupywacza w chatce albo przy kramiku w obozowisku
local function canSell(session: Session): boolean
	local root = getRoot(session.player)
	if not root then
		return false
	end
	local merchant = Config.Merchant
	local dx, dz = root.Position.X - merchant.x, root.Position.Z - merchant.z
	if dx * dx + dz * dz <= merchant.sellDistance * merchant.sellDistance then
		return true
	end
	return Economy.atStation("shop", root.Position.X, root.Position.Z, Config.StationTolerance)
end

-- indices: które grzyby z koszyka sprzedać (nil = wszystkie); key: odcisk koszyka, który widział klient
local function onSell(player: Player, indices: unknown, key: unknown)
	local session = sessions[player]
	if not session or not cooledDown(session) or not canSell(session) then
		return
	end
	local basket = session.data.basket
	if #basket == 0 then
		return
	end
	-- Samouczek: sprzedaż po kolei (jeden, dwa zaznaczone, wszystko) – inny sposób nie przejdzie
	if not TutorialService.canSell(session :: any, indices) then
		notify(session, "TUT_SELL_WRONG")
		session.basketKey = nil
		pushState(session)
		return
	end
	-- Koszyk zmienił się od czasu, gdy klient go pokazał: nic nie sprzedajemy, wysyłamy świeży
	if key ~= nil and key ~= Economy.basketKey(basket) then
		session.basketKey = nil
		pushState(session)
		return
	end
	local value = 0
	local count = 0
	if indices == nil then
		value = Economy.basketValue(basket)
		count = #basket
		table.clear(basket)
	else
		local valid = Economy.validSellIndices(indices, #basket)
		if not valid then
			return
		end
		for _, index in valid do
			value += Economy.itemValue(basket[index])
			table.remove(basket, index)
		end
		count = #valid
	end
	-- Ukończone strony Grzybopedii podnoszą cenę na stałe
	local bonus = ProgressService.sellBonus(player)
	value = math.floor(value * (1 + bonus))
	session.data.coins += value
	if bonus > 0 then
		notify(session, "MSG_SOLD_BONUS", { value, math.floor(bonus * 100 + 0.5) })
	else
		notify(session, "MSG_SOLD", { value })
	end
	ProgressService.event(player, "sell", count)
	TutorialService.onSold(session :: any)
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
		GardenService.refresh(player)
	elseif action == "tutorialReset" then
		TutorialService.reset(session :: any)
	elseif action == "tutorialNext" then
		local step = session.data.tutorial
		TutorialService.setStep(session :: any, if step >= 6 then Config.Tutorial.done else step + 1)
	elseif action == "tutorialSkip" then
		TutorialService.setStep(session :: any, Config.Tutorial.done)
	elseif action == "basketClear" then
		table.clear(data.basket)
	elseif action == "basketFill" then
		for zone = 1, 3 do
			for _ = 1, 3 do
				local species = Economy.rollSpecies(zone, math.random())
				if species and #data.basket < basketMax(session) then
					table.insert(data.basket, { s = species.id })
				end
			end
		end
	elseif action == "cycleDawn" or action == "cycleNight" then
		debugPhase = if action == "cycleDawn" then "dawn" else "night"
		debugUntil = os.time() + 60
	elseif action == "expeditionGroup" then
		session.debugGroupUntil = os.clock() + 60
	elseif action == "expeditionDown" then
		-- Jak zgaśnięcie latarni przy kumplu obok (bez kumpla czas minie i las pochłonie)
		task.defer(startDowned, session)
	elseif action == "boardsRefresh" then
		task.spawn(LeaderboardService.refreshNow)
	elseif not ProgressService.dev(player, action) then
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
		-- Butelka oleju podnosi też gracza, któremu zgasła latarnia i czeka na pomoc
		clearDowned(session)
		session.oil = stat(session, "oil")
		session.oilWarned = false
		session.oilHalfWarned = false
		notify(session, "MSG_OIL_BOUGHT")
	elseif key == "harvest" then
		if not GardenService.harvestNow(player) then
			return false
		end
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
	if not def or not cooledDown(session) then
		return
	end
	-- Samouczek: w kroku z ulepszeniem wolno kupić tylko olej
	if not TutorialService.canBuy(session :: any, upgradeId) then
		notify(session, "TUT_ONLY_OIL")
		return
	end
	-- Ulepszenia kupuje się w bezpiecznej strefie świata, do którego należą (leśne w chatce i na polanie,
	-- jaskiniowe w obozowisku). W lesie się nie da, bo ulepszenie oleju napełnia latarnię.
	local root = getRoot(player)
	local zone = if root then Economy.zoneIndexAt(root.Position.Z) else 0
	if not Economy.isSafeZone(zone) or Economy.zoneWorld(zone) ~= Economy.upgradeShop(upgradeId) then
		notify(session, "MSG_UPGRADE_WHERE")
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
		GardenService.refresh(player)
	end
	applyCharacterStats(session)
	notify(session, "MSG_UPGRADED", nil, def.key)
	ProgressService.event(player, "upgrade", 1)
	pushState(session)
	TutorialService.onBought(session :: any, upgradeId)
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
						ProgressService.guardianEvent(player, name, "caught")
					end
				end,
				onEscaped = function(player: Player)
					local session = sessions[player]
					if session then
						notify(session, def.escaped, { Economy.basketValue(session.data.basket) })
						ProgressService.event(player, "escape", 1)
						ProgressService.guardianEvent(player, name, "escape")
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
				ProgressService.found(player, item, "hoard")
				local chaser = chasers[name]
				if chaser and chaser.startChase(player, place.origin) then
					notify(session, def.woke)
				end
				pushState(session)
				return true
			end,
		})
	end

	-- Portrety do zakładki Strażnicy w Grzybopedii: przebudzone modele do klonowania w ViewportFrame
	-- (klient nie ma dostępu do budowniczych z serwera, a posągi na mapie mogą być poza streamingiem).
	-- W tle, bo siatki Skarbnika i Utopca wczytują się z sieci.
	task.spawn(function()
		if ReplicatedStorage:FindFirstChild("GuardianPortraits") then
			return
		end
		local folder = Instance.new("Folder")
		folder.Name = "GuardianPortraits"
		for name, def in GUARDIANS do
			local ok, err = pcall(function()
				local model = def.model.build(folder, CFrame.new(0, -600, 0), true)
				model.Name = name
			end)
			if not ok then
				warn("[GameService] Portret strażnika " .. name .. " się nie zbudował:", err)
			end
		end
		folder.Parent = ReplicatedStorage
	end)

	ProgressService.start({
		getData = function(player: Player)
			local session = sessions[player]
			return if session then session.data else nil
		end,
		notify = function(player: Player, key: string, args: { any }?, nameKey: string?, mutation: MutationInfo?)
			local session = sessions[player]
			if session then
				notify(session, key, args, nameKey, mutation)
			end
		end,
		pushState = function(player: Player)
			local session = sessions[player]
			if session then
				pushState(session)
			end
		end,
	})
	LeaderboardService.start({
		getData = function(player: Player)
			local session = sessions[player]
			return if session then session.data else nil
		end,
	})

	GardenService.start(map.gardens, {
		getData = function(player: Player)
			local session = sessions[player]
			return if session then session.data else nil
		end,
		basketMax = function(player: Player): number
			local session = sessions[player]
			return if session then basketMax(session) else 0
		end,
		notify = function(player: Player, key: string, args: { any }?, nameKey: string?, mutation: MutationInfo?)
			local session = sessions[player]
			if session then
				notify(session, key, args, nameKey, mutation)
			end
		end,
		pushState = function(player: Player)
			local session = sessions[player]
			if session then
				pushState(session)
			end
		end,
		applyStats = function(player: Player)
			local session = sessions[player]
			if session then
				applyCharacterStats(session)
			end
		end,
		onEvent = function(player: Player, kind: string, count: number?)
			ProgressService.event(player, kind, count)
			local session = sessions[player]
			if session then
				TutorialService.event(session :: any, kind)
			end
		end,
	})
	TutorialService.start({
		pushState = function(session: any)
			pushState(session)
		end,
		refreshTitle = function(session: any)
			ProgressService.refreshTitle(session.player)
		end,
		notify = function(session: any, key: string, args: { any }?)
			notify(session, key, args)
		end,
		basketMax = function(session: any): number
			return basketMax(session)
		end,
		stat = function(session: any, id: string): number
			return stat(session, id)
		end,
		rootOf = getRoot,
	})

	setupDevCommands()

	PickMushroom.OnServerEvent:Connect(onPick)
	SellBasket.OnServerEvent:Connect(onSell)
	BuyUpgrade.OnServerEvent:Connect(onBuy)
	Remotes.get("DevAction").OnServerEvent:Connect(onDevAction)
	Remotes.get("TutorialStep").OnServerEvent:Connect(function(player, step)
		local session = sessions[player]
		if not session or typeof(step) ~= "number" then
			return
		end
		-- Klient sam kończy tylko cutscenki; resztę kroków pilnuje serwer
		TutorialService.clientStep(session :: any, step)
	end)
	Remotes.get("StudioPurchase").OnServerEvent:Connect(onStudioPurchase)
	MarketplaceService.ProcessReceipt = processReceipt

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- Dzień i noc: pora z zegara (wspólna dla serwerów), atrybuty dla klientów, reset grzybów o świcie
	task.spawn(function()
		local lastPhase: string? = nil
		while true do
			local now = os.time()
			local phase = Cycle.at(now)
			if debugPhase and now < debugUntil then
				phase = table.clone(phase)
				phase.phase = debugPhase
				phase.endsAt = debugUntil
			end
			Workspace:SetAttribute("CyclePhase", phase.phase)
			Workspace:SetAttribute("CycleEndsAt", phase.endsAt)
			Workspace:SetAttribute("CycleEvent", phase.event.id)
			Workspace:SetAttribute("CycleNextEvent", phase.nextEvent.id)
			if lastPhase and lastPhase ~= phase.phase then
				if phase.phase == "dawn" then
					resetForest(phase.nextEvent)
				else
					local key = NIGHT_MESSAGES[phase.event.id] or "MSG_NIGHT_CALM"
					for _, session in sessions do
						notify(session, key)
					end
				end
			end
			lastPhase = phase.phase
			task.wait(1)
		end
	end)

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
