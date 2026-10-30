--!strict
-- Punkt startowy klienta: łączy HUD, grzyby, klimat, efekty i ostrzeżenia z wiadomościami serwera.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Economy = require(Shared:WaitForChild("Economy"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Localize = require(script.Parent.Localize)
local Hud = require(script.Parent.Hud)
local Audio = require(script.Parent.Audio)
local MushroomView = require(script.Parent.MushroomView)
local Atmosphere = require(script.Parent.Atmosphere)
local Effects = require(script.Parent.Effects)
local Warnings = require(script.Parent.Warnings)
local Signs = require(script.Parent.Signs)
local PortalView = require(script.Parent.PortalView)
local DevPanel = require(script.Parent.DevPanel)
local ShopPanel = require(script.Parent.ShopPanel)
local GardenPrompts = require(script.Parent.GardenPrompts)
local SellPanel = require(script.Parent.SellPanel)
local MerchantView = require(script.Parent.MerchantView)
-- Kolejność = kolejność dużych przycisków pod „Ulepszeniami”: (Halloween w czasie eventu), Zadania,
-- Grzybopedia, Tytuły
local _HalloweenPanel = require(script.Parent.HalloweenPanel)
local _CauldronView = require(script.Parent.CauldronView)
local _QuestPanel = require(script.Parent.QuestPanel)
local _AtlasPanel = require(script.Parent.AtlasPanel)
local _TitlePanel = require(script.Parent.TitlePanel)
local _SettingsButtons = require(script.Parent.SettingsButtons)
local PanelKit = require(script.Parent.PanelKit)

local _LeaderboardView = require(script.Parent.LeaderboardView)
local _TitleView = require(script.Parent.TitleView)
local ExpeditionView = require(script.Parent.ExpeditionView)
local DeathScreen = require(script.Parent.DeathScreen)
local OilView = require(script.Parent.OilView)
local Expedition = require(Shared:WaitForChild("Expedition"))
local IntroCutscene = require(script.Parent.IntroCutscene)
local Tutorial = require(script.Parent.Tutorial)
local LeszyAnimator = require(script.Parent.LeszyAnimator)
local GardenPanel = require(script.Parent.GardenPanel)
local DisplayMushrooms = require(script.Parent.DisplayMushrooms)
local FontFix = require(script.Parent.FontFix)

local player = Players.LocalPlayer

-- Skup i ogródek też blokują chodzenie, gdy są otwarte (dotyk na oknie ruszał postacią)
do
	local playerGui = player:WaitForChild("PlayerGui")
	for name, guiName in { Sell = "SellPanel", Garden = "GardenPanel" } do
		local found = playerGui:FindFirstChild(guiName)
		if found and found:IsA("ScreenGui") then
			PanelKit.watchModal(name, found)
		end
	end
end

local PickMushroom = Remotes.get("PickMushroom")
local lastCampShop: string? = nil
local SellBasket = Remotes.get("SellBasket")
local BuyUpgrade = Remotes.get("BuyUpgrade")

local LANTERN_BRIGHTNESS = 2 -- w najciemniejszej strefie; przy chatce latarnia świeci słabiej, żeby nie przepalać ścian
local LANTERN_GLASS = Color3.fromRGB(255, 206, 120)
local GHOST_GLASS = Color3.fromRGB(120, 255, 150) -- psikus z kotła: zielona latarnia duchów

local lanternRange = Economy.upgradeStat("lantern", 0)
local oil = Economy.upgradeStat("oil", 0)
local oilMax = oil
local chased = false
local chaser: string? = nil -- kto goni: "leszy" albo "skarbnik"
local targetId: string? = nil
local wasInCabin = true -- gracz zaczyna w chatce
local upgrades: { [string]: number } = {} -- poziomy ulepszeń (knoty zmniejszają spalanie oleju w swoich światach)

Signs.start()
PortalView.start()
GardenPrompts.start()
MerchantView.start()
LeszyAnimator.start()
GardenPanel.start()
DisplayMushrooms.start()
FontFix.start()

-- Skąd wylatują monety po sprzedaży (przycisk w panelu sprzedaży)
local sellShowerFrom: Vector2? = nil
local introStarted = false
SellPanel.onSell(function(indices, key, from)
	sellShowerFrom = from
	SellBasket:FireServer(indices, key)
end)
-- Tylko w Studio: testy samouczka otwierają panel sprzedaży atrybutem (narzędzia Studio nie klikają ProximityPrompt)
if RunService:IsStudio() then
	player:GetAttributeChangedSignal("DevOpenSell"):Connect(function()
		SellPanel.open()
	end)
end

Remotes.get("StateUpdate").OnClientEvent:Connect(function(state)
	lanternRange = state.lanternRange
	oil = state.oil
	oilMax = state.oilMax
	chased = state.chased == true
	chaser = state.chaser
	upgrades = state.upgrades
	PortalView.setUnlocked({ cave = state.caveUnlocked == true, swamp = state.swampUnlocked == true })
	DevPanel.setEnabled(state.dev == true)
	ShopPanel.update(state, Economy.isSafeZone(state.zone))
	-- Lista grzybów przychodzi tylko po zmianie koszyka
	if state.basket then
		SellPanel.setBasket(state.basket, state.basketKey)
		GardenPanel.setBasket(state.basket, state.basketKey)
	end
	Hud.update(state)
	OilView.update(state)
	-- Pierwsze wejście do gry: cutscenka ze złym snem, potem samouczek
	if state.tutorial == 0 and not IntroCutscene.isPlaying() and not introStarted then
		introStarted = true
		IntroCutscene.play(function()
			Remotes.get("TutorialStep"):FireServer(1)
		end)
	elseif state.tutorial ~= 0 then
		introStarted = false
	end
	Tutorial.update(state)
end)

Remotes.get("MushroomSync").OnClientEvent:Connect(function(list)
	MushroomView.add(list)
end)

-- Ikony mutacji, np. "🌈✨" (do napisu „+N” nad zebranym grzybem)
local function mutationIcons(variant: string?, tags: { string }?): string
	local icons = ""
	local def = Economy.getVariant(variant)
	if def then
		icons ..= def.icon
	end
	for _, id in tags or {} do
		local tag = Economy.getTag(id)
		if tag then
			icons ..= tag.icon
		end
	end
	return icons
end

-- Etykieta mutacji w języku gracza, np. " 🌈 Tęcza + ✨ Blask". Zaczyna się od spacji, a bez mutacji
-- jest pusta, więc szablony w CSV mają ją doklejoną bez odstępu ("{1}{2}!")
local function mutationLabel(mutation: { variant: string?, tags: { string }? }?): string
	if not mutation then
		return ""
	end
	local parts = {}
	local def = Economy.getVariant(mutation.variant)
	if def then
		table.insert(parts, def.icon .. " " .. Localize.t(def.key))
	end
	for _, id in mutation.tags or {} do
		local tag = Economy.getTag(id)
		if tag then
			table.insert(parts, tag.icon .. " " .. Localize.t(tag.key))
		end
	end
	return if #parts > 0 then " " .. table.concat(parts, " + ") else ""
end

Remotes.get("MushroomRemoved").OnClientEvent:Connect(function(id)
	-- Serwer usuwa grzyb tylko wtedy, gdy ten gracz go zebrał: czas na efekt
	local info = MushroomView.get(id)
	if info and Economy.isMimic(info.species) then
		-- Błędny ognik rozpływa się w zielonym dymie i chichocze
		Effects.wispTrick(info.position)
	elseif info then
		Effects.collect(
			info.position,
			MushroomView.capColor(info.species, info.variant),
			Economy.mushroomValue(info.species, info.variant, info.tags),
			Economy.variantRank(info.variant),
			mutationIcons(info.variant, info.tags)
		)
	end
	MushroomView.remove(id)
end)

local TOAST_KIND: { [string]: string } = {
	MSG_MUTATION = "gold",
	MSG_RARE_FIND = "gold",
	MSG_OIL_HALF = "warn",
	MSG_OIL_LOW = "warn",
	MSG_BASKET_FULL = "warn",
	MSG_NOT_ENOUGH = "warn",
	MSG_ENGULFED = "warn",
	MSG_LESZY_WOKE = "warn",
	MSG_SKARBNIK_WOKE = "warn",
	MSG_UTOPIEC_WOKE = "warn",
	MSG_HOARD_DROP_UTOPIEC = "gold",
	MSG_ESCAPED_SKARBNIK = "gold",
	MSG_ESCAPED_UTOPIEC = "gold",
	MSG_SWAMP_UNLOCKED = "gold",
	MSG_SWAMP_ENTER = "info",
	MSG_PORTAL_FIND_SWAMP = "warn",
	MSG_MIMIC = "warn",
	MSG_BOOM = "gold",
	MSG_LUCK = "gold",
	MSG_RESCUED = "gold",
	MSG_OIL_BOUGHT = "info",
	MSG_HARVEST = "gold",
	MSG_DAWN = "gold",
	MSG_NIGHT_FULL_MOON = "gold",
	MSG_NIGHT_BLOOD_MOON = "warn",
	MSG_NIGHT_MIST = "warn",
	MSG_PLANTED = "gold",
	MSG_PLANTED_SWAP = "gold",
	MSG_COLLECTED = "gold",
	MSG_OFFLINE_INCOME = "gold",
	MSG_GARDEN_FULL = "warn",
	MSG_NOTHING_TO_PLANT = "warn",
	MSG_POT_EMPTY = "warn",
	MSG_THIEF_RUNNING = "warn",
	MSG_LOOT_TAGGED = "warn",
	MSG_LOOT_DROPPED = "warn",
	MSG_LOOT_PLANTED = "gold",
	MSG_LOOT_DELIVERED = "gold",
	MSG_LOOT_RECOVERED = "gold",
	MSG_HOARD_DROP_SKARBNIK = "gold",
	MSG_ROBBED = "warn",
	MSG_RACK_ALERT = "warn",
	MSG_RACK_PROTECTED = "warn",
	MSG_OWNER_GUARDING = "warn",
	MSG_NO_RACK = "warn",
	MSG_ESCAPED = "gold",
	MSG_HOARD_DROP = "gold",
	MSG_PORTAL_LOCKED = "warn",
	MSG_PORTAL_FIND = "warn",
	MSG_CAVE_UNLOCKED = "gold",
	MSG_CAVE_ENTER = "info",
	MSG_PORTAL_HOME = "info",
	MSG_REFILL_HINT = "info",
	MSG_STOLE = "gold",
	MSG_ATLAS_NEW_SPECIES = "gold",
	MSG_ATLAS_NEW_FORM = "gold",
	MSG_ATLAS_TIER = "gold",
	MSG_BESTIARY_NEW = "gold",
	MSG_QUEST_DONE = "gold",
	MSG_QUESTS_ALL_DONE = "gold",
	MSG_QUESTS_NEW = "info",
	MSG_LOGIN_REWARD = "gold",
	MSG_LOGIN_REWARD_LUCK = "gold",
	MSG_SOLD_BONUS = "gold",
	MSG_GROUP_FORMED = "gold",
	MSG_DOWNED = "warn",
	MSG_PLAYER_DOWN = "warn",
	MSG_REVIVED = "gold",
	MSG_REVIVE_DONE = "gold",
	MSG_TITLE_NEW = "gold",
}

-- Komunikaty, po których gracz ląduje w chatce z czarnym ekranem: klucz -> tytuł
local BLACKOUT_TITLE: { [string]: string } = {
	MSG_ENGULFED = "ENGULF_TITLE",
	MSG_CAUGHT = "CAUGHT_TITLE",
	MSG_ENGULFED_CAVE = "ENGULF_TITLE_CAVE",
	MSG_CAUGHT_SKARBNIK = "CAUGHT_TITLE_SKARBNIK",
	MSG_CAUGHT_UTOPIEC = "CAUGHT_TITLE_UTOPIEC",
	MSG_ENGULFED_SWAMP = "ENGULF_TITLE_SWAMP",
}

Remotes.get("Notify").OnClientEvent:Connect(function(payload)
	local args = payload.args
	-- Okazja do uratowania koszyka: przycisk na czarnym ekranie, bez komunikatu
	if payload.key == "RESCUE_OFFER" then
		ShopPanel.offerRescue(tonumber(args and args[1]) or 0, tonumber(args and args[2]) or 10)
		return
	elseif payload.key == "MSG_RESCUED" then
		ShopPanel.hideRescue()
	end
	if payload.nameKey then
		-- Nazwa (grzyba, ulepszenia) zawsze jako {1}, dalsze argumenty przesuwają się na {2}, {3}...
		local localized = { Localize.t(payload.nameKey) }
		for _, value in args or {} do
			table.insert(localized, value)
		end
		args = localized
	end
	-- Mutacja zawsze jako ostatni argument (szablon w CSV wie, gdzie ją wstawić)
	if payload.mutation then
		local withLabel = table.clone(args or {})
		table.insert(withLabel, mutationLabel(payload.mutation))
		args = withLabel
	end
	local text = Localize.t(payload.key, args)
	local blackoutTitle = BLACKOUT_TITLE[payload.key]
	if blackoutTitle then
		DeathScreen.show(payload.key, Localize.t(blackoutTitle), text)
		Effects.engulf()
		return
	end
	Hud.toast(text, TOAST_KIND[payload.key])
	if payload.key == "MSG_LESZY_WOKE" or payload.key == "MSG_SKARBNIK_WOKE" or payload.key == "MSG_UTOPIEC_WOKE" then
		Effects.leszyWoke()
	elseif payload.key == "MSG_ROBBED" or payload.key == "MSG_RACK_ALERT" or payload.key == "MSG_THIEF_RUNNING" then
		Effects.play("engulf", 1.4, 0.5)
	elseif
		payload.key == "MSG_STOLE"
		or payload.key == "MSG_LOOT_PLANTED"
		or payload.key == "MSG_LOOT_RECOVERED"
		or string.sub(payload.key, 1, 11) == "MSG_ESCAPED"
	then
		Effects.play("upgrade", 1.2)
	end
	if payload.key == "MSG_SOLD" or payload.key == "MSG_COLLECTED" then
		Effects.sold()
		Hud.coinShower(tonumber(payload.args and payload.args[1]) or 0, if payload.key == "MSG_SOLD" then sellShowerFrom else nil)
		sellShowerFrom = nil
	elseif payload.key == "MSG_UPGRADED" then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			Effects.upgrade(root.Position)
		end
	end
end)

local function pick()
	local id = targetId
	if id then
		PickMushroom:FireServer(id)
	end
end

Hud.onPick(pick)
Hud.onBuy(function(upgradeId)
	BuyUpgrade:FireServer(upgradeId)
end)
Localize.onChanged(Hud.refreshTexts)

-- Klawiatura (E) i pad (X) robią to samo co przycisk ZBIERZ
ContextActionService:BindAction("PickMushroom", function(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		pick()
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.E, Enum.KeyCode.ButtonX)

-- Gdy kończy się olej, własna latarnia słabnie i płynnie drga (szum, a nie losowe skoki,
-- które wyglądały jak stroboskop), a szybka latarni w ręce ciemnieje.
local function updateLantern(character: Model, root: BasePart, oilFraction: number, darkness: number, time: number)
	local attachment = root:FindFirstChild("LanternAttachment")
	local light = attachment and attachment:FindFirstChild("Lantern")
	local hand = character:FindFirstChild("HandLantern")
	local glass = hand and hand:FindFirstChild("LanternGlass")

	local low = Config.OilLowFraction
	local strength = 1
	if oilFraction < low then
		strength = (0.35 + 0.65 * (oilFraction / low)) * (0.85 + 0.15 * math.noise(time * 4, 0.5))
	end
	if light and light:IsA("PointLight") then
		light.Brightness = LANTERN_BRIGHTNESS * (0.45 + 0.55 * darkness) * strength
	end
	if glass and glass:IsA("BasePart") then
		local ghostUntil = character:GetAttribute("GhostLantern")
		local base = if typeof(ghostUntil) == "number" and ghostUntil > os.time() then GHOST_GLASS else LANTERN_GLASS
		glass.Color = Color3.fromRGB(70, 40, 20):Lerp(base, math.clamp(strength, 0, 1))
	end
end

RunService.RenderStepped:Connect(function(dt)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and root and root:IsA("BasePart")) then
		return
	end
	local position = root.Position
	-- Strefę liczymy lokalnie, żeby mrok i panel reagowały od razu, bez czekania na serwer
	local zone = Economy.zoneIndexAt(position.Z)
	local zoneDef = Config.Zones[zone]
	-- Muzyka świata (las / jaskinia / bagna); cutscenki mają pierwszeństwo
	-- Halloween: nocą w lesie (i każdą Nocą Dziadów) halloweenowa muzyka
	local world = Economy.zoneWorld(zone)
	local night = Workspace:GetAttribute("CyclePhase") == "night"
	local spiritNight = night and Workspace:GetAttribute("CycleEvent") == "spirit_night"
	local halloweenMusic = Workspace:GetAttribute("Halloween") == true and night and (world == "forest" or spiritNight)
	Audio.playlist(if halloweenMusic then "halloween" else world)
	local oilFraction = if oilMax > 0 then math.clamp(oil / oilMax, 0, 1) else 1
	local now = os.clock()

	-- Mgła (zdarzenie nocy) skraca zasięg widzenia w mroku
	local eventDef = nil
	if Workspace:GetAttribute("CyclePhase") == "night" then
		local eventId = Workspace:GetAttribute("CycleEvent")
		for _, def in Config.Cycle.events do
			if def.id == eventId then
				eventDef = def
			end
		end
	end
	local sight = lanternRange * (if eventDef then eventDef.lantern else 1)
	local darkness = Atmosphere.update(zone, sight, dt)
	Effects.updateAmbient(darkness)
	Effects.updateParticles(position, zone)
	updateLantern(character, root, oilFraction, darkness, now)
	MushroomView.updateVisibility(position, sight, zoneDef.darkness)

	local safe = Economy.isSafeZone(zone)
	if safe then
		targetId = nil
		MushroomView.updateTarget(position, 0)
	else
		targetId = MushroomView.updateTarget(position, Config.PickRadiusClient)
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local speed = if humanoid then humanoid.WalkSpeed else Economy.upgradeStat("boots", 0)
	local oilUpgrade = Economy.worldOilUpgrade(zoneDef.world)
	-- Knot ze świata i wspólna wyprawa zmniejszają spalanie (baner „Wracaj!” liczy z tym samym)
	local worldScale = (if oilUpgrade then Economy.upgradeStat(oilUpgrade, upgrades[oilUpgrade] or 0) else 1)
		* Expedition.drain(ExpeditionView.group())
	local turnBack = Economy.shouldTurnBack(position.Z, speed, oil, worldScale)
	Warnings.update(dt, position, oilFraction, turnBack, zone, lanternRange, chased, chaser)
	local heartbeat = if not safe and oilFraction < Config.OilLowFraction then 1 - oilFraction / Config.OilLowFraction * 0.6 else 0
	Effects.setHeartbeat(if chased then 1 else heartbeat)

	-- Sprzedaż: w chatce przez rozmowę ze skupywaczem, w obozowiskach panel otwiera się w kręgu przy kramiku.
	-- Gdy gracz odejdzie, panel się zamyka.
	local shop = Economy.stationAt("shop", position.X, position.Z)
	local campShop = if shop and shop.world ~= "forest" then shop.world else nil
	if campShop and campShop ~= lastCampShop then
		SellPanel.open()
	end
	lastCampShop = campShop
	if SellPanel.isOpen() then
		local merchant = Config.Merchant
		local dx, dz = position.X - merchant.x, position.Z - merchant.z
		local nearMerchant = dx * dx + dz * dz <= (merchant.sellDistance - 1) ^ 2
		if not nearMerchant and not Economy.atStation("shop", position.X, position.Z, 1) then
			SellPanel.close()
		end
	end

	-- Po powrocie z niepełną latarnią: podpowiedź, gdzie jest olej (wnętrze chatki albo obozowisko)
	local inCabin = safe and (zoneDef.world == "cave" or position.Z < -13)
	if inCabin and not wasInCabin and oil < oilMax - 0.5 and not Economy.atStation("oil", position.X, position.Z) then
		Hud.toast(Localize.t("MSG_REFILL_HINT"), "info")
	end
	wasInCabin = inCabin
	Hud.setPick(targetId ~= nil, not safe)
end)
