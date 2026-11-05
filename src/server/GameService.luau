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
local Halloween = require(Shared.Halloween)
local Skins = require(Shared.Skins)
local Winter = require(Shared.Winter)
local DataService = require(script.Parent.DataService)
local MapBuilder = require(script.Parent.MapBuilder)
local ChaseService = require(script.Parent.ChaseService)
local HoardService = require(script.Parent.HoardService)
local RavenService = require(script.Parent.RavenService)
local ForgeService = require(script.Parent.ForgeService)
local World = script.Parent:WaitForChild("World")
local LeszyModel = require(World:WaitForChild("Leszy"))
local SkarbnikModel = require(World:WaitForChild("Skarbnik"))
local UtopiecModel = require(World:WaitForChild("Utopiec"))
local JagaModel = require(World:WaitForChild("Jaga"))
local MountainShared = require(ReplicatedStorage.Shared.Mountain)
local MountainTerrain = require(ReplicatedStorage.Shared.MountainTerrain)
local HandTools = require(World:WaitForChild("HandTools"))
local HalloweenDecor = require(World:WaitForChild("HalloweenDecor"))
local WinterDecor = require(World:WaitForChild("WinterDecor"))
local GardenService = require(script.Parent.GardenService)
local ProgressService = require(script.Parent.ProgressService)
local TutorialService = require(script.Parent.TutorialService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local HalloweenService = require(script.Parent.HalloweenService)
local WinterService = require(script.Parent.WinterService)
local NightFindService = require(script.Parent.NightFindService)
local ShowcaseService = require(script.Parent.ShowcaseService)
local CommunityService = require(script.Parent.CommunityService)
local DelveService = require(script.Parent.DelveService)
local AnnounceService = require(script.Parent.AnnounceService)
local Ledger = require(script.Parent.Ledger)
local Analytics = require(script.Parent.Analytics)

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
	fumesNoticeAt: number, -- kiedy ostatnio ostrzegaliśmy o trujących oparach (Łysa Góra)
	rescue: Rescue?, -- koszyk do uratowania za Robuxy (przez chwilę po zgaśnięciu latarni / złapaniu)
	group: number, -- ilu graczy idzie razem (wspólna wyprawa: ten gracz + sąsiedzi w promieniu)
	groupNoticeAt: number, -- kiedy ostatnio mówiliśmy „wspólna wyprawa” (żeby nie spamować)
	joinedAt: number, -- os.clock() wejścia (analityka: po ilu minutach pierwsza sprzedaż itd.)
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
	jaga = {
		settings = Config.Jaga,
		model = JagaModel,
		woke = "MSG_JAGA_WOKE",
		caught = "MSG_CAUGHT_JAGA",
		gaveUp = "MSG_JAGA_GAVE_UP",
		escaped = "MSG_ESCAPED_JAGA",
		hoardDrop = "MSG_HOARD_DROP_JAGA",
		respawn = Config.JagaLair.respawnSeconds,
	},
}

local chasers: { [string]: ChaseService.Chaser } = {}
local hoards: { [string]: HoardService.Hoard } = {}
local ravens: RavenService.Ravens? = nil -- kruki Baby Jagi (Łysa Góra), start w init
local forge: { open: (Player) -> (), flush: (Player) -> () }? = nil -- Kuźnia Grzybów (Moździerz Zielarki), start w init

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
	mountain = {
		flag = "mountainUnlocked",
		canEnter = Economy.canEnterMountain,
		unlockCoins = Config.Mountain.unlockCoins,
		unlocked = "MSG_MOUNTAIN_UNLOCKED",
		enter = "MSG_MOUNTAIN_ENTER",
		find = "MSG_PORTAL_FIND_MOUNTAIN",
		engulfed = "MSG_ENGULFED_MOUNTAIN",
	},
}
local map: MapBuilder.MapInfo

local function stat(session: Session, id: string): number
	return Economy.upgradeStat(id, session.data.upgrades[id] or 0)
end

-- Analityka: kamień milowy (pierwsza sprzedaż, pierwsza śmierć...) z minutami od wejścia do gry
local function milestone(session: Session, name: string)
	Analytics.milestone(session.player, name, math.floor((os.clock() - session.joinedAt) / 60))
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
	-- Znalezisko i trofeum z ekspedycji zajmują po jednym miejscu, dopóki ich nie zabezpieczysz
	return stat(session, "basket") + stat(session, "pack") + stat(session, "creel") + stat(session, "witchbag") - DelveService.reserved(session.player)
end

-- Mnożnik spalania oleju w świecie strefy (knot z jaskini albo z bagien)
-- Wysyp (kupiony za Robuxy) działa dla całego serwera; czas w os.time(), żeby klienci mogli odliczać
local boomUntil = 0

local function boomActive(): boolean
	return os.time() < boomUntil
end

-- Wysyp dla tego gracza: serwerowy albo jego własny (produkt boomSolo)
local function soloBoomActive(session: Session): boolean
	return os.time() < session.data.soloBoomUntil
end
local function boomFor(session: Session): boolean
	return boomActive() or soloBoomActive(session)
end

-- Zdarzenie trwającej nocy (nil o świcie). Pętla dnia i nocy odświeża je co sekundę,
-- razem z wymuszeniami z panelu DEV (świt / noc teraz, Noc Dziadów teraz).
local liveEvent: Config.NightEventDef? = Cycle.activeEvent(os.time())
-- Halloween, panel DEV: „Dyniowy wysyp” (las odrasta, co drugi grzyb dyniowy) na czas jednego odrostu
local pumpkinBoom = false
-- Zima, panel DEV: „Zamieć” (las odrasta, co drugi grzyb oszroniony) na czas jednego odrostu
local frostBoom = false

-- Mnożnik szans na mutacje: Wysyp dla wszystkich, mikstura szczęścia dla kupującego, bonus grupy,
-- nożyk gracza, zdarzenie nocy (pełnia, krwawy księżyc) i głębokość strefy
local function luckFactor(session: Session, zone: number?): number
	local total = Economy.luck({
		knifeLevel = session.data.upgrades.knife or 0,
		zone = zone,
		event = liveEvent,
		boom = boomActive(),
		soloBoom = soloBoomActive(session),
		potion = os.time() < session.data.luckUntil,
		member = CommunityService.isMember(session.player),
		friend = CommunityService.hasFriend(session.player),
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
		mountainUnlocked = data.mountainUnlocked,
		luckUntil = data.luckUntil,
		boomUntil = boomUntil,
		soloBoomUntil = data.soloBoomUntil,
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
		-- Pasek gwarancji Złota w HUD (atrybut, żeby nie wysyłać całego stanu przy każdym odroście)
		session.player:SetAttribute("Pity", data.pity)
	end

	local tags: { string }? = nil
	for _, tag in Economy.tagsForZone(spot.zone) do
		if session.rng:NextNumber() < Economy.tagOdds(tag, luck) then
			tags = tags or {}
			table.insert(tags :: { string }, tag.id)
		end
	end
	-- Halloween: dyniowy grzyb (stała szansa, niezależna od szczęścia), w każdym świecie
	if Halloween.canBePumpkin(species.id) then
		local chance = Halloween.pumpkinChance(os.time(), if liveEvent then liveEvent.id else nil, pumpkinBoom)
		if chance > 0 and session.rng:NextNumber() < chance then
			tags = tags or {}
			table.insert(tags :: { string }, Halloween.TAG)
		end
	end
	-- Zima: oszroniony grzyb (stała szansa, niezależna od szczęścia), w każdym świecie
	if Winter.canBeFrost(species.id) then
		local chance = Winter.frostChance(os.time(), frostBoom)
		if chance > 0 and session.rng:NextNumber() < chance then
			tags = tags or {}
			table.insert(tags :: { string }, Winter.TAG)
		end
	end
	return species.id, variant, tags
end

-- ===== Las z ostatniej sesji =====
-- Wyjście i szybki powrót losowały cały las od nowa, więc zamiast czekać na odrost wystarczyło się
-- przelogować. Teraz las gracza (gatunek, mutacje i kiedy będzie gotowy, w os.time) siedzi w profilu
-- (data.forest) i aktualizuje się przy każdej zmianie (na dysk trafia z autozapisem profilu i przy wyjściu).
-- Pokolenie lasu = numer ostatniego świtu: po świcie las i tak odrasta wszystkim od nowa.
-- Pokolenie z kalendarza (wspólne dla serwerów) i pokolenie, które ten serwer naprawdę wyhodował.
-- Różnią się, gdy przywołana Noc Dziadów przykryła świt: reset czeka do końca przywołania, a do tego
-- czasu zapis lasu i przywracanie używają tego samego, starszego pokolenia.
local serverGen = Cycle.generation(os.time())

local function forestGen(): number
	return serverGen
end

local function rememberSpot(session: Session, id: string, state: SpotState)
	local forest = session.data.forest
	if not forest then
		forest = { g = forestGen(), s = {} }
		session.data.forest = forest
	end
	;(forest :: any).s[id] = {
		s = state.speciesId,
		v = state.variant,
		x = state.tags,
		t = os.time() + math.max(0, math.ceil(state.readyAt - os.clock())),
	}
end

-- Czy zapisany grzyb pasuje do miejsca (strefa albo legowisko strażnika); inaczej losujemy od nowa
local function savedFits(spot: MapBuilder.Spot, speciesId: string): boolean
	local species = Economy.getSpecies(speciesId)
	if not species then
		return false
	end
	local guardian = spotGuardian(spot)
	if guardian then
		return Economy.guardianOf(speciesId) == guardian
	end
	return species.zone == spot.zone and Economy.guardianOf(speciesId) == nil
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

local function attachHandLantern(character: Model, level: number, skin: string)
	local existing = character:FindFirstChild("HandLantern")
	if existing and existing:GetAttribute("Tier") == HandTools.lanternTier(level) and (existing:GetAttribute("Skin") or "") == skin then
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
	HandTools.lantern(level, grip, hand, nil, skin).Parent = character
end

local function attachHandKnife(character: Model, level: number, skin: string)
	local existing = character:FindFirstChild("HandKnife")
	if existing and existing:GetAttribute("Level") == level and (existing:GetAttribute("Skin") or "") == skin then
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
	HandTools.knife(level, grip, hand, nil, skin).Parent = character
end

local function applyCharacterStats(session: Session)
	local character = session.player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Złodziej niosący grzyb i gracz ze Znaleziskiem Nocy idą wolniej
		humanoid.WalkSpeed = stat(session, "boots")
			* GardenService.speedFactor(session.player)
			* NightFindService.speedFactor(session.player)
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
	-- Skórki z eventów (tylko te, które gracz naprawdę ma)
	local data = session.data
	local function skinFor(slot: string): string
		local id = (data.equipped :: any)[slot] or ""
		return if id ~= "" and Skins.owns(data.skins, data.stats, id) then id else ""
	end
	attachHandLantern(character, data.upgrades.lantern or 0, skinFor("lantern"))
	attachHandKnife(character, data.upgrades.knife or 0, skinFor("knife"))
end

-- Latarnia zgasła albo strażnik złapał gracza: zabiera koszyk i wyrzuca gracza do chatki / obozu.
-- messageKey mówi klientowi, który ekran pokazać; guardian: kto złapał (jego grzyby wracają do legowiska).
local clearDowned: (Session) -> ()

local function engulf(session: Session, messageKey: string?, guardian: string?)
	clearDowned(session)
	-- Znalezisko Nocy przepada (inaczej śmierć byłaby najszybszą drogą do chatki)
	NightFindService.drop(session.player)
	-- W Głębokich Komorach: koniec ekspedycji dla gracza (zabezpieczone nagrody zostają)
	DelveService.onEngulf(session.player)
	stopChases(session.player)
	if ravens then
		ravens.forget(session.player)
	end
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
	if session.data.stats.deaths == 0 then
		milestone(session, "FirstDeath")
	end
	ProgressService.event(session.player, "death", 1) -- licznik do tytułu „Pechowiec”

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
	-- Przejście przez portal kończy pościg (strażnicy nie opuszczają swojego świata) i Znalezisko Nocy
	stopChases(session.player)
	NightFindService.drop(session.player)
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
				if first then
					milestone(session, "Unlock_" .. world)
				end
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
				-- Głębokie Komory (ekspedycja): własne spalanie, woda i haki z olejem (DelveService)
				local delveDelta = DelveService.oilDelta(session.player, root.Position, oilMax, oilScale(session, zone), Expedition.drain(session.group))
				if delveDelta then
					session.oil = math.min(oilMax, session.oil + delveDelta * step)
					if delveDelta > 0 then
						if session.oil > oilMax * Config.OilWarnFraction then
							session.oilHalfWarned = false
						end
						if session.oil > oilMax * Config.OilLowFraction then
							session.oilWarned = false
						end
					end
				else
					-- Wspólna wyprawa: połączone latarnie palą mniej. Łysa Góra: trujące opary z kotłów palą więcej.
					local fumes = 1
					if Config.Zones[zone] and Config.Zones[zone].world == "mountain" then
						fumes = MountainShared.oilFactor(root.Position)
						if fumes > 1 and now - session.fumesNoticeAt > 20 then
							session.fumesNoticeAt = now
							notify(session, "MSG_FUMES")
						end
					end
					session.oil -= Economy.oilDrain(zone, oilScale(session, zone)) * Expedition.drain(session.group) * fumes * step
				end
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
			-- Kruki Baby Jagi (tylko w swoich strefach Łysej Góry; tu też podnosi się upuszczone grzyby)
			if ravens and session.zone and not Economy.isSafeZone(session.zone) then
				ravens.step(session.player, session.zone, root, #session.data.basket, now)
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
	-- Nowa postać (reset, śmierć): stan „czeka na pomoc” przepada razem ze starą
	session.downedUntil = nil
	session.downed = nil
	session.oil = stat(session, "oil")
	session.oilWarned = false
	session.oilHalfWarned = false
	applyCharacterStats(session)
	pushState(session)
end

-- Krok wejścia gracza w osobnym xpcall: błąd trafia do konsoli serwera (F9 → Server) z pełnym śladem
local function joinStep(name: string, step: (Player) -> (), player: Player)
	local ok, err = (xpcall :: any)(step, debug.traceback, player)
	if not ok then
		warn(string.format("[GameService] %s dla %s się wysypał: %s", name, player.Name, tostring(err)))
	end
end

local function onPlayerAdded(player: Player)
	local data, canSave, kicked = DataService.load(player)
	if player.Parent == nil or kicked then
		return -- gracz wyszedł w trakcie wczytywania albo zapis się nie otworzył (wyrzucony)
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
		fumesNoticeAt = 0,
		group = 1,
		groupNoticeAt = 0,
		joinedAt = os.clock(),
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

	-- Każdy gracz ma własne grzyby: nikt nikomu nie wyzbiera wysypu. Szybki powrót (to samo
	-- pokolenie lasu) przywraca las z profilu razem z czasami odrostu; inaczej las losuje się od nowa.
	-- Zapis z tego samego albo nowszego pokolenia (inny serwer już wyhodował świt) wraca 1:1; zapis
	-- z przyszłości kalendarza to śmieci. Skakanie między serwerami nie daje więc nowego lasu.
	local gen = forestGen()
	local nowClock, nowTime = os.clock(), os.time()
	local saved = data.forest
	local fresh = saved ~= nil and Cycle.canRestore(saved.g, gen, nowTime)
	local savedSpots = if saved and fresh then saved.s else {}
	data.forest = { g = if saved and fresh then saved.g else gen, s = {} }
	for _, spot in map.spots do
		local entry = savedSpots[spot.id]
		local state: SpotState? = nil
		if entry and savedFits(spot, entry.s) then
			state = { speciesId = entry.s, variant = entry.v, tags = entry.x, readyAt = nowClock + math.max(0, entry.t - nowTime), visible = false }
		else
			local speciesId, variant, tags = rollSpot(session, spot)
			if speciesId then
				state = { speciesId = speciesId, variant = variant, tags = tags, readyAt = 0, visible = false }
			end
		end
		if state then
			session.spots[spot.id] = state
			rememberSpot(session, spot.id, state)
		end
	end

	sessions[player] = session
	player:SetAttribute("Pity", data.pity)
	-- Każdy system osobno: błąd w jednym (np. ogródek) nie może zatrzymać reszty wejścia. Wcześniej
	-- wtedy nie szło ProgressUpdate, a okna Zadań, Tytułów i Grzybopedii zostawały z napisami „Label”
	-- (HUD działał, bo pętla gry i tak wysyła stan), a postać nie dostawała ulepszeń.
	joinStep("GardenService.assign", GardenService.assign, player)
	joinStep("ProgressService.join", ProgressService.join, player)
	joinStep("CommunityService.join", CommunityService.join, player)

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
	-- Kuźnia: wpisy do Grzybopedii odłożone na czas animacji bębna, póki sesja jeszcze jest
	if forge then
		forge.flush(player)
	end
	sessions[player] = nil
	devSnapshots[player] = nil
	stopChases(player)
	if ravens then
		ravens.forget(player)
	end
	session.downedUntil = nil
	-- Wyszedł z niewykorzystaną okazją do ratunku: grzyby strażnika wracają do legowiska od razu
	local rescue = session.rescue
	if rescue then
		session.rescue = nil
		rescue.drop()
	end
	GardenService.release(player)
	ProgressService.leave(player)
	LeaderboardService.leave(player, session.data, session.canSave)
	-- Ostatni zapis i zwolnienie blokady sesji (ProfileStore)
	if session.canSave then
		DataService.release(player, session.data)
	end
end

-- Panel DEV: wymuszona pora na chwilę (do sprawdzania świtu bez czekania 18 minut)
local debugPhase: string? = nil
local debugUntil = 0
-- Panel DEV (admin abuse): zdarzenie nocy przywołane do tej chwili (os.time) — Noc Dziadów, pełnia,
-- krwawy księżyc, mgła, deszcz (Config.Cycle.events)
local summonUntil = 0
local summonEvent = Halloween.SPIRIT_NIGHT
-- Admin abuse dla całego serwera: id -> do kiedy (os.time). Klienci widzą je jako atrybuty Workspace
-- "Abuse_<id>" (baner z odliczaniem, AdminEvents). Żaden nie daje darmowego Wysypu ani mikstury.
local abuseUntil: { [string]: number } = {}
local function abuseActive(id: string): boolean
	return os.time() < (abuseUntil[id] or 0)
end

-- Budzi strażnika `name` dla gracza. Baba Jaga wylatuje od razu, kiedy jej chatka patrzy na złodzieja
-- (Shared/Mountain.hutWatching); inni strażnicy mają stałe opóźnienie z Config.
local function wakeGuardian(session: any, name: string, from: Vector3?)
	local chaser = chasers[name]
	if not chaser or abuseActive("sleep") then
		return
	end
	local wakeDelay: number? = nil
	local message = GUARDIANS[name].woke
	if name == "jaga" then
		local root = getRoot(session.player)
		if root then
			local delay, watched = MountainShared.jagaWakeDelay(Workspace:GetServerTimeNow(), root.Position)
			wakeDelay = delay
			if watched then
				message = "MSG_JAGA_WOKE_WATCHED"
			end
		end
	end
	if chaser.startChase(session.player, from, wakeDelay) then
		notify(session, message)
	end
end

-- Komunikat na początek nocy, osobny dla każdego zdarzenia
local NIGHT_MESSAGES: { [string]: string } = {
	calm = "MSG_NIGHT_CALM",
	full_moon = "MSG_NIGHT_FULL_MOON",
	rain = "MSG_NIGHT_RAIN",
	mist = "MSG_NIGHT_MIST",
	blood_moon = "MSG_NIGHT_BLOOD_MOON",
	spirit_night = "MSG_NIGHT_SPIRIT_NIGHT",
}

-- Świt: las u każdego gracza odrasta od nowa (nowe gatunki i mutacje w tych samych miejscach).
-- Klient podmienia grzyby o tych samych id, więc nie trzeba ich osobno usuwać.
-- Pokolenie zapisu nigdy się nie cofa (gracz z nowszego serwera zachowuje swój numer)
local function regrowForest(session: Session, now: number)
	local old = session.data.forest
	session.data.forest = { g = math.max(if old then old.g else 0, forestGen()), s = {} }
	for id, state in session.spots do
		local spot = map.spotById[id]
		if spot then
			local speciesId, variant, tags = rollSpot(session, spot)
			state.speciesId = speciesId or state.speciesId
			state.variant = variant
			state.tags = tags
			state.visible = false
			state.readyAt = now
			rememberSpot(session, id, state)
		end
	end
	syncReadySpots(session, now)
end

-- Świt z kalendarza: odnawia tylko graczy, którzy tego pokolenia jeszcze nie dostali (ktoś, kto
-- przyszedł z serwera, gdzie świt już był, zachowuje swój las i czasy odrostu)
local function resetForest(nextEvent: Config.NightEventDef, forced: boolean?)
	local now = os.clock()
	for _, session in sessions do
		local forest = session.data.forest
		if forced or Cycle.needsRegrow(if forest then forest.g else nil, forestGen()) then
			regrowForest(session, now)
			notify(session, "MSG_DAWN", { nextEvent.icon }, nextEvent.key)
		end
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
		local event = liveEvent
		state.readyAt = now
			+ seconds * (if boomFor(session) then Config.Boom.regrowFactor else 1) * (if event then event.regrow else 1)
		state.speciesId = speciesId or state.speciesId
		state.variant = variant
		state.tags = tags
		rememberSpot(session, spotId, state)
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
	-- Kradzież w ogródkach wymaga kilku grzybów z lasu od ostatniej kradzieży
	GardenService.onPick(player)

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
	-- Grzyb z legowiska budzi jego strażnika (chyba że admin uśpił strażników)
	if guardian then
		wakeGuardian(session, guardian, spot.position)
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
	local candy = 0 -- Halloween: cukierki za sprzedane dyniowe grzyby
	local flakes = 0 -- Zima: płatki śniegu za sprzedane oszronione grzyby
	if indices == nil then
		value = Economy.basketValue(basket)
		count = #basket
		candy = Halloween.candyForList(basket)
		flakes = Winter.flakesForList(basket)
		table.clear(basket)
	else
		local valid = Economy.validSellIndices(indices, #basket)
		if not valid then
			return
		end
		for _, index in valid do
			value += Economy.itemValue(basket[index])
			candy += Halloween.candyFor(basket[index])
			flakes += Winter.flakesFor(basket[index])
			table.remove(basket, index)
		end
		count = #valid
	end
	-- Ukończone strony Grzybopedii podnoszą cenę na stałe
	local bonus = ProgressService.sellBonus(player)
	value = math.floor(value * (1 + bonus))
	-- Admin abuse: podwójna sprzedaż na tym serwerze
	if abuseActive("sell") then
		value *= 2
	end
	local firstSale = session.data.stats.sold == 0
	Ledger.earn(player, session.data, value, "Gameplay", "Sell")
	if bonus > 0 then
		notify(session, "MSG_SOLD_BONUS", { value, math.floor(bonus * 100 + 0.5) })
	else
		notify(session, "MSG_SOLD", { value })
	end
	ProgressService.event(player, "sell", count)
	if firstSale then
		milestone(session, "FirstSale")
	end
	if candy > 0 and Halloween.active(os.time()) then
		ProgressService.addCandy(player, candy, "MSG_CANDY_SOLD")
		-- Wspólny cel serwera: tylko cukierki ze sprzedaży dyń
		HalloweenService.contribute(player, candy)
	end
	if flakes > 0 and Winter.active(os.time()) then
		ProgressService.addFlakes(player, flakes, "MSG_FLAKES_SOLD")
	end
	TutorialService.onSold(session :: any)
	pushState(session)
end

-- ===== Komendy deweloperskie =====

-- /coins 1000000 dodaje monety, /coins -500 odejmuje (bez liczby: +1000)
-- Moderacja rankingu cukierków (/rankremove i panel DEV): wynik usunięcia wraca do dewelopera
local function removeFromRanking(session: Session, userId: number)
	task.spawn(function()
		local ok = LeaderboardService.remove("candy", userId)
		notify(session, "MSG_DEV_DONE", { "rankremove " .. userId .. (if ok then " ok" else " FAILED (Studio?)") })
	end)
end

local function setupDevCommands()
	local folder = TextChatService:FindFirstChild("TextChatCommands") or TextChatService
	local command = Instance.new("TextChatCommand")
	command.Name = "DevCoins"
	command.PrimaryAlias = "/coins"
	command.Parent = folder
	command.Triggered:Connect(function(source: TextSource, text: string)
		local player = Players:GetPlayerByUserId(source.UserId)
		local session = player and sessions[player]
		if not (player and session and isDeveloper(player) and RunService:IsStudio()) then
			return
		end
		local amount = math.floor(tonumber(string.match(text, "^%S+%s+(%-?%d+)")) or 1000)
		session.data.coins = math.max(0, session.data.coins + amount)
		notify(session, "MSG_DEV_COINS", { amount })
		pushState(session)
	end)
	-- /rankremove 12345 usuwa wynik konta z rankingu cukierków (działa też na opublikowanej grze).
	-- Na stałe: dopisz UserId do Config.Halloween.rankingBanned.
	local remove = Instance.new("TextChatCommand")
	remove.Name = "DevRankRemove"
	remove.PrimaryAlias = "/rankremove"
	remove.Parent = folder
	remove.Triggered:Connect(function(source: TextSource, text: string)
		local player = Players:GetPlayerByUserId(source.UserId)
		local userId = tonumber(string.match(text, "^%S+%s+(%d+)"))
		local session = player and sessions[player]
		if player and session and userId and isDeveloper(player) then
			removeFromRanking(session, userId)
		end
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
	tpMountain = function()
		local info = map.worlds.mountain
		return info and info.camp
	end,
	tpCauldrons = function()
		local z = Config.Zones[16].startZ + 8
		return CFrame.new(0, MountainTerrain.groundY(0, z) + 4, z)
	end,
	tpSummit = function()
		local lair = Config.JagaLair
		local x, z = lair.centerX + 10, lair.hutZ - 24
		return CFrame.new(x, MountainTerrain.groundY(x, z) + 4, z)
	end,
	tpDelve = function()
		-- Przed szczeliną do Głębokich Komór (ściana Otchłani), twarzą do niej
		return CFrame.lookAt(Vector3.new(32, 4, 1398), Vector3.new(44, 4, 1398))
	end,
}

-- Na opublikowanej grze (nie w Studio) deweloper może tylko się teleportować, wyzerować własny zapis, odświeżyć rankingi,
-- usunąć wynik z rankingu i odpalić dwa ogłaszane wydarzenia „admin abuse” (Noc Dziadów, Dyniowy wysyp).
-- Wszystko, co zmienia monety, cukierki, ulepszenia, zadania, postęp albo porę dnia, działa tylko w Studio.
local LIVE_DEV_ACTIONS: { [string]: boolean } = Config.DevLiveActions
-- Studio: stan zapisu zapamiętany przed testem (np. kuźni) i przywracany po nim. Tylko w pamięci serwera.
local DEV_SNAPSHOT_KEYS = { "coins", "earned", "basket", "atlas", "atlasDone", "bestiary", "daily", "streak", "weekly", "stats", "titles" }
local devSnapshots: { [Player]: { [string]: any } } = {}
local function deepCopy(value: any): any
	if typeof(value) ~= "table" then
		return value
	end
	local out = {}
	for key, inner in value do
		out[key] = deepCopy(inner)
	end
	return out
end

local function devActionAllowed(action: string): boolean
	if RunService:IsStudio() then
		return true
	end
	return DEV_TELEPORTS[action] ~= nil or LIVE_DEV_ACTIONS[action] == true or string.match(action, "^rankingRemove:%d+$") ~= nil
end

local function onDevAction(player: Player, action: unknown)
	local session = sessions[player]
	if not session or typeof(action) ~= "string" or not isDeveloper(player) or not devActionAllowed(action) then
		return
	end
	local data = session.data
	local teleport = DEV_TELEPORTS[action]
	if teleport then
		local target = teleport()
		local character = player.Character
		if target and character then
			stopChases(player)
			NightFindService.drop(player)
			character:PivotTo(target)
			session.zone = Economy.zoneIndexAt(target.Position.Z)
		end
	elseif action == "delveStart" then
		-- Studio: od razu do komór z pierwszym zleceniem z tablicy
		DelveService.devStart(player)
	elseif action == "resetSave" then
		-- Cały zapis od zera (jak nowy gracz) i wyrzucenie z gry: po ponownym wejściu wszystko
		-- (ogródek, las, samouczek, okna) startuje czysto. Zostają tylko obsłużone zakupy (żeby Roblox
		-- nie dał ich drugi raz) i lista odznak (Roblox i tak ich nie odbiera).
		local fresh = DataService.defaultData()
		fresh.receipts = data.receipts
		fresh.badges = data.badges
		session.data = fresh
		session.basketKey = nil
		task.delay(0.5, function()
			if player.Parent then
				player:Kick("Zapis wyzerowany. Wejdź do gry ponownie. / Save reset. Please rejoin.")
			end
		end)
		return
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
	elseif action == "mountainUnlock" then
		data.mountainUnlocked = true
	elseif action == "mountainLock" then
		data.mountainUnlocked = false
	elseif action == "coins10m" then
		data.coins += 10000000
	elseif action == "ravenNow" then
		if ravens then
			ravens.devNow(player)
		end
	elseif action == "forgeOpen" then
		if forge then
			forge.open(player)
		end
	elseif action == "devSnapshot" then
		local snapshot = {}
		for _, key in DEV_SNAPSHOT_KEYS do
			snapshot[key] = deepCopy((data :: any)[key])
		end
		devSnapshots[player] = snapshot
	elseif action == "devRestore" then
		local snapshot = devSnapshots[player]
		if not snapshot then
			return
		end
		for _, key in DEV_SNAPSHOT_KEYS do
			(data :: any)[key] = deepCopy(snapshot[key])
		end
		session.basketKey = nil
	elseif action == "forgeKit" then
		-- Składniki do wszystkich ukrytych przepisów kuźni (zwykłe, z wymaganymi cechami); monety: coinsSet
		for _, recipe in Config.Forge.recipes do
			for _, input in recipe.inputs do
				if #data.basket < basketMax(session) then
					table.insert(data.basket, { s = input.s, x = if input.tag then { input.tag } else nil })
				end
			end
		end
	elseif action == "forgeKitGuardians" then
		-- Tęczowe grzyby czterech strażników (trójki na mitycznego i sekretnego)
		for _, id in { "leszy_crown", "skarbnik_truffle", "utopiec_chalice", "jaga_toadstool" } do
			if #data.basket < basketMax(session) then
				table.insert(data.basket, { s = id, v = "rainbow" })
			end
		end
	elseif action == "forgeReset" then
		-- Kolekcja kuźni od zera (testy w Studio na własnym zapisie): wpisy w Grzybopedii i licznik połączeń
		for _, species in Config.Species do
			if species.forgeOnly then
				data.atlas[species.id] = nil
			end
		end
		data.stats.forged = 0
		-- Tytuły kuźni znów „nowe” (lista widzianych tytułów), żeby komunikat o zdobyciu dało się przetestować
		local titles = data.titles
		if titles then
			for _, id in { "TITLE_FORGE_APPRENTICE", "TITLE_FORGE_MASTER", "TITLE_FERN_FLOWER", "TITLE_VELES" } do
				local at = table.find(titles, id)
				if at then
					table.remove(titles, at)
				end
			end
		end
	elseif string.match(action, "^gardenWeather:[%w_]+$") then
		-- Studio: noc z danym zdarzeniem daje cechę grzybowi w ogródku (pogoda w ogródku)
		GardenService.devWeather(player, string.sub(action, 15))
	elseif action == "gardenWeatherUndo" then
		GardenService.devWeatherUndo(player)
	elseif action == "nightFindSpawn" then
		-- Studio: Znalezisko Nocy kilka kroków przed graczem (bez czekania na noc)
		NightFindService.devSpawn(player)
	elseif action == "nightFindReset" then
		NightFindService.devReset(player)
		ProgressService.refreshTitle(player)
	elseif action == "showcaseReset" then
		-- Studio: gablota od zera (miejsca, wystawy, trofea), przywrócenie zapisu po teście
		ShowcaseService.devReset(player)
	elseif string.match(action, "^trophyForget:%d+$") then
		-- Studio: trofeum ze Znaleziska z testu (data os.time) znika z gabloty i licznika
		ShowcaseService.devForgetTrophy(player, tonumber(string.sub(action, 14)) or 0)
		ProgressService.refreshTitle(player)
	elseif action == "showcaseFill" then
		-- Studio: wszystkie miejsca kupione za darmo (podgląd pełnej gabloty)
		ShowcaseService.devFill(player)
	elseif string.match(action, "^coinsSet:%d+$") then
		-- Studio: przywrócenie salda po testach (devActionAllowed nie wpuszcza tego poza Studio)
		data.coins = tonumber(string.sub(action, 10)) or data.coins
	elseif string.match(action, "^luckSet:%d+$") then
		-- Studio: przywrócenie mikstury szczęścia po testach (os.time() końca, 0 = bez mikstury)
		data.luckUntil = tonumber(string.sub(action, 9)) or data.luckUntil
	elseif string.match(action, "^atlasForget:[%w_]+:%d$") then
		-- Studio: cofnięcie formy dodanej w teście (atlasForget:gatunek:ranga), bez ruszania innych form
		local id, rank = string.match(action, "^atlasForget:([%w_]+):(%d)$")
		local mask = data.atlas[id :: string]
		local shift: number = tonumber(rank) or 0
		if typeof(mask) == "number" then
			local left = bit32.band(mask, bit32.bnot(2 ^ shift))
			if left > 0 then
				data.atlas[id :: string] = left
			else
				data.atlas[id :: string] = nil
			end
		end
	elseif action == "jagaSummon" then
		-- Baba Jaga wylatuje od razu na gracza (test pościgu bez zrywania Ziela)
		local chaser = chasers.jaga
		local place = map.guardians.jaga
		if chaser and place and chaser.startChase(player, place.origin, 0.5) then
			notify(session, "MSG_JAGA_WOKE")
		end
	elseif action == "cosmicNear" then
		-- Grzyby w promieniu 40 studs od gracza stają się kosmiczne (podgląd wariantu i zbierania)
		local root = getRoot(player)
		if root then
			local changed = {}
			for id, state in session.spots do
				local spot = map.spotById[id]
				if spot and state.visible and (spot.position - root.Position).Magnitude <= 40 then
					state.variant = "cosmic"
					table.insert(changed, { id = id, position = spot.position, species = state.speciesId, variant = state.variant, tags = state.tags })
				end
			end
			if #changed > 0 then
				MushroomSync:FireClient(player, changed)
			end
		end
	elseif action == "coins1m" then
		data.coins += 1000000
	elseif action == "oilFull" then
		session.oil = stat(session, "oil")
	elseif action == "oilLow" then
		session.oil = stat(session, "oil") * 0.1
	elseif action == "upgradeGatesForest" or action == "upgradeGatesCave" or action == "upgradeGatesSwamp" or action == "upgradeGatesMountain" or action == "upgradeGatesLegacy" then
		-- devActionAllowed nie dopuszcza tych scenariuszy poza Studio.
		local world = if action == "upgradeGatesMountain" then "mountain" elseif action == "upgradeGatesSwamp" then "swamp" elseif action == "upgradeGatesCave" then "cave" else "forest"
		data.caveUnlocked = world ~= "forest"
		data.swampUnlocked = world == "swamp" or world == "mountain"
		data.mountainUnlocked = world == "mountain"
		data.coins = 100000000
		for _, id in { "boots", "oil", "basket" } do
			data.upgrades[id] = Economy.upgradeCap(id, world)
		end
		if action == "upgradeGatesLegacy" then
			data.upgrades.boots = 8
			data.upgrades.oil = 10
			data.upgrades.basket = 10
		end
		TutorialService.setStep(session :: any, Config.Tutorial.done)
		local info = map.worlds[world]
		local target = if info and info.camp then info.camp else map.spawnCFrame
		local character = player.Character
		if character then
			stopChases(player)
			NightFindService.drop(player)
			character:PivotTo(target)
			session.zone = Economy.zoneIndexAt(target.Position.Z)
		end
		session.oil = stat(session, "oil")
		applyCharacterStats(session)
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
	elseif action == "pot20m" then
		GardenService.devFill(player, 20)
	elseif action == "away30m" or action == "away3h" then
		-- Okno „Witaj z powrotem” od razu: tyle minut nieobecności
		GardenService.devAway(player, if action == "away3h" then 3 * 3600 else 30 * 60)
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
	elseif action == "spiritNight" then
		-- Admin abuse: Noc Dziadów na tym serwerze, z ogłoszeniem dla wszystkich
		summonUntil = os.time() + Config.Halloween.summonSeconds
		summonEvent = Halloween.SPIRIT_NIGHT
		Workspace:SetAttribute("Abuse_spirit_night", summonUntil)
		for _, other in sessions do
			notify(other, "MSG_SPIRIT_SUMMONED", { player.DisplayName, math.floor(Config.Halloween.summonSeconds / 60) })
		end
	elseif string.match(action, "^abuse") then
		-- Admin abuse (Config.AdminAbuse): ogłoszenie dla wszystkich i baner z odliczaniem u każdego
		local def = Config.AdminAbuse[action]
		if not def then
			return
		end
		local now = os.time()
		if def.kind == "stop" then
			-- Koniec wszystkich wydarzeń z panelu (też przywołanej nocy)
			table.clear(abuseUntil)
			summonUntil = 0
			for name in Workspace:GetAttributes() do
				if string.sub(name, 1, 6) == "Abuse_" then
					Workspace:SetAttribute(name, nil)
				end
			end
			for _, other in sessions do
				notify(other, "MSG_ABUSE_STOP", { player.DisplayName })
			end
			return
		elseif def.kind == "night" and def.event then
			summonEvent = def.event
			summonUntil = now + def.seconds
		elseif def.kind == "regrow" then
			for _, other in sessions do
				regrowForest(other, os.clock())
			end
		elseif def.kind == "sleep" then
			-- Strażnicy zasypiają: trwające pościgi się kończą, nowe nie ruszają
			for _, other in sessions do
				stopChases(other.player)
			end
		elseif def.kind == "shards" then
			DelveService.setShardBoost(now + def.seconds)
		end
		if def.seconds > 0 then
			abuseUntil[def.id] = now + def.seconds
			Workspace:SetAttribute("Abuse_" .. def.id, now + def.seconds)
		end
		for _, other in sessions do
			notify(other, "MSG_ABUSE_START", { player.DisplayName, math.ceil(def.seconds / 60) }, def.key)
		end
	elseif action == "pumpkinBoom" then
		-- Admin abuse: las wszystkich odrasta od nowa, co drugi grzyb dyniowy (jednorazowo)
		if not Halloween.active(os.time()) then
			return
		end
		pumpkinBoom = true
		local ok, err = pcall(function()
			for _, other in sessions do
				regrowForest(other, os.clock())
				notify(other, "MSG_PUMPKIN_BOOM", { player.DisplayName })
			end
		end)
		pumpkinBoom = false
		if not ok then
			warn("[GameService] Dyniowy wysyp:", err)
		end
	elseif action == "frostBoom" then
		-- Admin abuse: las wszystkich odrasta od nowa, co drugi grzyb oszroniony (jednorazowo)
		if not Winter.active(os.time()) then
			return
		end
		frostBoom = true
		local ok, err = pcall(function()
			for _, other in sessions do
				regrowForest(other, os.clock())
				notify(other, "MSG_FROST_BOOM", { player.DisplayName })
			end
		end)
		frostBoom = false
		if not ok then
			warn("[GameService] Zamieć:", err)
		end
	elseif action == "winterToggle" then
		-- Tylko Studio: podgląd Zimy przed datą (atrybut Workspace.Winter, wystrój, przycisk po wejściu)
		if not RunService:IsStudio() then
			return
		end
		Winter.forced = not Winter.forced
		Workspace:SetAttribute("Winter", Winter.active(os.time()))
	elseif action == "adventNext" then
		-- Tylko Studio: następny dzień kalendarza adwentowego (1..24 w kółko)
		if not RunService:IsStudio() then
			return
		end
		Winter.devDay = (Winter.devDay or Winter.adventDay(os.time()) or 0) % #Winter.ADVENT + 1
		Workspace:SetAttribute("AdventDay", Winter.devDay)
	elseif action == "expeditionGroup" then
		session.debugGroupUntil = os.clock() + 60
	elseif action == "expeditionDown" then
		-- Jak zgaśnięcie latarni przy kumplu obok (bez kumpla czas minie i las pochłonie)
		task.defer(startDowned, session)
	elseif action == "boardsRefresh" then
		task.spawn(LeaderboardService.refreshNow)
	elseif string.match(action, "^rankingRemove:%d+$") then
		-- Usuwa wynik z rankingu cukierków (znacznik w magazynie, nie wróci); trwale na przyszłość:
		-- Config.Halloween.rankingBanned
		local userId = tonumber(string.match(action, "%d+")) or 0
		removeFromRanking(session, userId)
	elseif not (ProgressService.dev(player, action) or HalloweenService.dev(player, action) or WinterService.dev(player, action)) then
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
		-- Dawca Wysypu: plakietka nad głową i iskierki (klient, BoomGiverView) do końca Wysypu.
		-- Kto dorzucił się wcześniej do tego samego Wysypu, zostaje Dawcą do jego nowego końca.
		for _, other in Players:GetPlayers() do
			local giverEnds = other:GetAttribute("BoomGiverUntil")
			if typeof(giverEnds) == "number" and giverEnds > os.time() then
				other:SetAttribute("BoomGiverUntil", boomUntil)
			end
		end
		player:SetAttribute("BoomGiverUntil", boomUntil)
		-- Grzyby, które właśnie odrastają, też przyspieszają
		local now = os.clock()
		for _, other in sessions do
			for id, state in other.spots do
				if not state.visible and state.readyAt > now then
					state.readyAt = now + (state.readyAt - now) * Config.Boom.regrowFactor
					rememberSpot(other, id, state) -- profil też ma krótszy termin
				end
			end
			notify(other, "MSG_BOOM", { player.DisplayName, math.floor(Config.Boom.seconds / 60) })
			pushState(other)
		end
	elseif key == "boomSolo" then
		-- Twój Wysyp: jak Wysyp, ale tylko dla kupującego. Odrastające grzyby przyspieszają raz
		-- (gdy Wysyp już działał, były przyspieszone wcześniej).
		local wasActive = boomFor(session)
		data.soloBoomUntil = math.max(os.time(), data.soloBoomUntil) + Config.Boom.seconds
		if not wasActive then
			local now = os.clock()
			for id, state in session.spots do
				if not state.visible and state.readyAt > now then
					state.readyAt = now + (state.readyAt - now) * Config.Boom.regrowFactor
					rememberSpot(session, id, state)
				end
			end
		end
		notify(session, "MSG_BOOM_SOLO", { math.floor(Config.Boom.seconds / 60) })
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
	elseif Economy.x2MinMinutes(key) then
		if not GardenService.grantX2(player, key) then
			return false
		end
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

-- Zakup jest „przyznany” dopiero, gdy zapis z jego numerem jest już w DataStore. Wcześniej, gdyby zapis
-- się nie udał (albo serwer padł), gracz zapłaciłby i nic nie dostał, a Roblox nie spróbowałby drugi raz.
-- Rzecz dajemy raz: numer zakupu ląduje w danych razem z nią, więc ponowna próba niczego nie dubluje.
local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local session = player and sessions[player]
	local key = productById[receipt.ProductId]
	if not key then
		warn("[GameService] Nieznany produkt w zakupie:", receipt.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- Bez wczytanego zapisu nie dajemy nic (Roblox spróbuje przy następnym wejściu)
	if not player or not session or not session.canSave then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receipt.PurchaseId)
	if not table.find(session.data.receipts, purchaseId) then
		if not grantProduct(session, key) then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		table.insert(session.data.receipts, purchaseId)
		while #session.data.receipts > 50 do
			table.remove(session.data.receipts, 1)
		end
	end
	if DataService.confirmSaved(player, session.data, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
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
	-- Sprawdzamy obszar obozu w trzech wymiarach i odblokowanie mapy. Nowy poziom
	-- globalnego ulepszenia wymaga obozu odpowiedniego świata lub późniejszego.
	local root = getRoot(player)
	local world = if root then Economy.upgradeCampAt(root.Position.X, root.Position.Y, root.Position.Z) else nil
	if not world then
		notify(session, "MSG_UPGRADE_WHERE")
		return
	end
	local level = session.data.upgrades[upgradeId] or 0
	local cost = Economy.upgradeCost(upgradeId, level) or 0
	local firstUpgrade = true
	for _, owned in session.data.upgrades do
		if owned > 0 then
			firstUpgrade = false
		end
	end
	local bought, reason, lockedWorld = Economy.buyUpgrade(session.data, upgradeId, world)
	if not bought then
		if reason == "locked" then
			notify(session, if lockedWorld == "cave" then "UPG_UNLOCK_CAVE" elseif lockedWorld == "mountain" then "UPG_UNLOCK_MOUNTAIN" else "UPG_UNLOCK_SWAMP")
		elseif reason == "location" then
			notify(session, if lockedWorld == "cave" then "UPG_BUY_CAVE" elseif lockedWorld == "swamp" then "UPG_BUY_SWAMP" elseif lockedWorld == "mountain" then "UPG_BUY_MOUNTAIN" else "MSG_UPGRADE_WHERE")
		elseif reason == "coins" then
			notify(session, "MSG_NOT_ENOUGH")
		end
		return
	end
	if upgradeId == "oil" then
		session.oil = stat(session, "oil")
	elseif upgradeId == "lock" or upgradeId == "chest" then
		GardenService.refresh(player)
	end
	applyCharacterStats(session)
	notify(session, "MSG_UPGRADED", nil, def.key)
	Ledger.spent(player, session.data, cost, "Shop", upgradeId)
	if firstUpgrade then
		milestone(session, "FirstUpgrade")
	end
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
			-- Baba Jaga leci nad zboczem Łysej Góry
			heightAt = if name == "jaga" then MountainTerrain.groundY else nil,
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
				wakeGuardian(session, name, place.origin)
				pushState(session)
				return true
			end,
		})
	end

	-- Kruki Baby Jagi: zabierają najtańszy grzyb (nigdy grzyba strażnika) i upuszczają go obok
	ravens = RavenService.start({
		takeCheapest = function(player: Player): RavenService.Item?
			local session = sessions[player]
			if not session then
				return nil
			end
			local basket = session.data.basket
			local best: number? = nil
			local bestValue = math.huge
			for index, item in basket do
				if Economy.guardianOf(item.s) == nil then
					local value = Economy.itemValue(item)
					if value < bestValue then
						best, bestValue = index, value
					end
				end
			end
			if not best then
				return nil
			end
			local item = table.remove(basket, best)
			pushState(session)
			return item :: any
		end,
		giveBack = function(player: Player, item: RavenService.Item): boolean
			local session = sessions[player]
			if not session then
				return false
			end
			local basket = session.data.basket
			if #basket >= basketMax(session) then
				return false
			end
			table.insert(basket, item :: any)
			pushState(session)
			return true
		end,
		notify = function(player: Player, key: string, args: { any }?)
			local session = sessions[player]
			if session then
				notify(session, key, args)
			end
		end,
		rootOf = getRoot,
	})

	-- Kuźnia Grzybów: Moździerz Zielarki na Placu Portali
	local forgeInfo = map.forge
	if forgeInfo then
		forge = ForgeService.start(forgeInfo.position, forgeInfo.prompt, {
			getData = function(player: Player): any?
				local session = sessions[player]
				return if session then session.data else nil
			end,
			rootOf = getRoot,
			busy = function(player: Player): boolean
				local session = sessions[player]
				return not session or session.downedUntil ~= nil or chasedBy(player) ~= nil or DelveService.reserved(player) > 0
			end,
			notify = function(player: Player, key: string, args: { any }?, nameKey: string?, mutation: any?)
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
			found = function(player: Player, item)
				ProgressService.found(player, item, "forge")
			end,
			event = function(player: Player, kind: string, amount: number)
				ProgressService.event(player, kind, amount)
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
		applyStats = function(player: Player)
			local session = sessions[player]
			if session then
				applyCharacterStats(session)
			end
		end,
	})
	WinterService.start({
		getData = function(player: Player)
			local session = sessions[player]
			return if session then session.data else nil
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
		applyStats = function(player: Player)
			local session = sessions[player]
			if session then
				applyCharacterStats(session)
			end
		end,
		refresh = function(player: Player)
			ProgressService.refresh(player)
		end,
	})
	HalloweenService.start({
		getData = function(player: Player)
			local session = sessions[player]
			return if session then session.data else nil
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
		applyStats = function(player: Player)
			local session = sessions[player]
			if session then
				applyCharacterStats(session)
			end
		end,
		refresh = function(player: Player)
			ProgressService.refresh(player)
		end,
		canSave = function(player: Player): boolean
			local session = sessions[player]
			return session ~= nil and session.canSave
		end,
	})
	CommunityService.start({
		getData = function(player: Player)
			local session = sessions[player]
			return if session then session.data else nil
		end,
		notify = function(player: Player, key: string, args: { any }?)
			local session = sessions[player]
			if session then
				notify(session, key, args)
			end
		end,
		pushState = function(player: Player)
			local session = sessions[player]
			if session then
				pushState(session)
			end
		end,
		canSave = function(player: Player): boolean
			local session = sessions[player]
			return session ~= nil and session.canSave
		end,
	})
	LeaderboardService.start({
		getData = function(player: Player)
			local session = sessions[player]
			return if session then session.data else nil
		end,
		canSave = function(player: Player): boolean
			local session = sessions[player]
			return session ~= nil and session.canSave
		end,
		isDeveloper = isDeveloper,
	})

	local gardenModels = {}
	for _, garden in map.gardens do
		table.insert(gardenModels, garden.model)
	end
	DelveService.start(gardenModels, {
		getData = function(player: Player)
			local session = sessions[player]
			return if session then session.data else nil
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
		travel = function(player: Player, target: CFrame, message: string?)
			local session = sessions[player]
			local character = player.Character
			if not (session and character) then
				return
			end
			stopChases(player)
			NightFindService.drop(player)
			character:PivotTo(target)
			session.zone = Economy.zoneIndexAt(target.Position.Z)
			if message then
				notify(session, message)
			end
		end,
		campCFrame = function(): CFrame
			local cave = map.worlds.cave
			return if cave and cave.camp then cave.camp else map.spawnCFrame
		end,
		engulf = function(player: Player, key: string)
			local session = sessions[player]
			if session then
				engulf(session, key)
			end
		end,
		addOil = function(player: Player, fraction: number)
			local session = sessions[player]
			if session then
				local oilMax = stat(session, "oil")
				-- Osuwisko nie zbija oleju poniżej 25% pełnej latarni (nie może samo zgasić latarni)
				session.oil = math.clamp(session.oil + oilMax * fraction, math.min(session.oil, oilMax * 0.25), oilMax)
				pushState(session)
			end
		end,
		isChased = function(player: Player): boolean
			return chasedBy(player) ~= nil
		end,
		basketFree = function(player: Player): number
			local session = sessions[player]
			return if session then basketMax(session) - #session.data.basket else 0
		end,
		event = function(player: Player, kind: string, amount: number?)
			ProgressService.event(player, kind, amount)
		end,
		wick = function(player: Player): number
			local session = sessions[player]
			return if session then stat(session, "crystal") else 1
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
		busyElsewhere = function(player: Player): boolean
			return NightFindService.isCarrying(player)
		end,
	})
	NightFindService.start({
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
		applyStats = function(player: Player)
			local session = sessions[player]
			if session then
				applyCharacterStats(session)
			end
		end,
		event = function(player: Player, kind: string, amount: number?)
			ProgressService.event(player, kind, amount)
		end,
		rootOf = getRoot,
		busy = function(player: Player): boolean
			local session = sessions[player]
			return not session or session.downedUntil ~= nil or GardenService.isCarrying(player)
		end,
		trophy = function(player: Player, item: { s: string, v: string?, t: number? }): boolean
			return ShowcaseService.addTrophy(player, item)
		end,
		spots = map.spots,
	})
	local gardenModels: { Model } = {}
	for _, rack in map.gardens do
		table.insert(gardenModels, rack.model)
	end
	ShowcaseService.start(gardenModels, {
		getData = function(player: Player)
			local session = sessions[player]
			return if session then session.data else nil
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
		rootOf = getRoot,
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
	-- Ogłoszenia admina na środku ekranu na wszystkich serwerach (panel DEV albo /ogloszenie)
	AnnounceService.start({
		isDeveloper = isDeveloper,
		notify = function(player: Player, key: string, args: { any }?)
			local session = sessions[player]
			if session then
				notify(session, key, args)
			end
		end,
	})

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
			local summoned = Cycle.getEvent(summonEvent)
			if now < summonUntil and summoned then
				phase = table.clone(phase)
				phase.phase = "night"
				phase.event = summoned
				phase.endsAt = summonUntil
			end
			liveEvent = if phase.phase == "night" then phase.event else nil
			-- Wygasłe wydarzenia z panelu DEV znikają z banera
			for name, value in Workspace:GetAttributes() do
				if string.sub(name, 1, 6) == "Abuse_" and (typeof(value) ~= "number" or value <= now) then
					Workspace:SetAttribute(name, nil)
				end
			end
			Workspace:SetAttribute("Halloween", Halloween.active(now))
			Workspace:SetAttribute("HalloweenEndsAt", Config.Halloween.endsAt)
			-- Zima: przed startem klient nic nie pokazuje (przycisk, tytuły, śnieg, muzyka)
			Workspace:SetAttribute("Winter", Winter.active(now))
			Workspace:SetAttribute("AdventDay", Winter.adventDay(now) or 0)
			Workspace:SetAttribute("CyclePhase", phase.phase)
			Workspace:SetAttribute("CycleEndsAt", phase.endsAt)
			Workspace:SetAttribute("CycleEvent", phase.event.id)
			Workspace:SetAttribute("CycleNextEvent", phase.nextEvent.id)
			-- Las odrasta raz na pokolenie z kalendarza, kiedy świt jest naprawdę widoczny (nie w czasie
			-- przywołanej nocy); wymuszony świt z panelu DEV (Studio) też odnawia las
			local forcedDawn = debugPhase == "dawn" and now < debugUntil and lastPhase ~= nil and lastPhase ~= "dawn"
			if Cycle.shouldRegrow(phase.phase, serverGen, now) or forcedDawn then
				serverGen = math.max(serverGen, Cycle.generation(now))
				resetForest(phase.nextEvent, forcedDawn)
			end
			if lastPhase and lastPhase ~= phase.phase and phase.phase ~= "dawn" then
				local key = NIGHT_MESSAGES[phase.event.id] or "MSG_NIGHT_CALM"
				for _, session in sessions do
					notify(session, key)
				end
			end
			lastPhase = phase.phase
			task.wait(1)
		end
	end)

	-- Halloween: dynie i znicze przy chatce, obozowisku i przystani (tylko w czasie eventu)
	task.spawn(function()
		local decor: Instance? = nil
		local failed = false
		while true do
			local on = Halloween.active(os.time())
			if on and not decor and not failed then
				local ok, result = pcall(HalloweenDecor.build, Workspace, map)
				if ok then
					decor = result
				else
					failed = true -- bez powtarzania co minutę tego samego błędu
					warn("[GameService] Wystrój Halloween:", result)
				end
			elseif not on and decor then
				decor:Destroy()
				decor = nil
			end
			task.wait(60)
		end
	end)

	-- Zima: choinka, bałwany, śnieg na ziemi i drzewach (tylko w czasie eventu albo w podglądzie z DEV)
	task.spawn(function()
		local decor: Instance? = nil
		local failed = false
		while true do
			local on = Winter.active(os.time())
			if on and not decor and not failed then
				local ok, result = pcall(WinterDecor.build, Workspace, map)
				if ok then
					decor = result
				else
					failed = true -- bez powtarzania tego samego błędu
					warn("[GameService] Wystrój Zimy:", result)
				end
			elseif not on and decor then
				pcall(WinterDecor.remove, map)
				decor:Destroy()
				decor = nil
			end
			task.wait(5)
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
