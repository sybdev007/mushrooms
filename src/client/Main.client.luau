--!strict
-- Punkt startowy klienta: łączy HUD, grzyby, klimat, efekty i ostrzeżenia z wiadomościami serwera.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Economy = require(Shared:WaitForChild("Economy"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Localize = require(script.Parent.Localize)
local Hud = require(script.Parent.Hud)
local MushroomView = require(script.Parent.MushroomView)
local Atmosphere = require(script.Parent.Atmosphere)
local Effects = require(script.Parent.Effects)
local Warnings = require(script.Parent.Warnings)
local Signs = require(script.Parent.Signs)
local PortalView = require(script.Parent.PortalView)
local DevPanel = require(script.Parent.DevPanel)
local RackPrompts = require(script.Parent.RackPrompts)

local player = Players.LocalPlayer

local PickMushroom = Remotes.get("PickMushroom")
local SellBasket = Remotes.get("SellBasket")
local BuyUpgrade = Remotes.get("BuyUpgrade")

local LANTERN_BRIGHTNESS = 2 -- w najciemniejszej strefie; przy chatce latarnia świeci słabiej, żeby nie przepalać ścian
local LANTERN_GLASS = Color3.fromRGB(255, 206, 120)

local lanternRange = Economy.upgradeStat("lantern", 0)
local oil = Economy.upgradeStat("oil", 0)
local oilMax = oil
local chased = false
local targetId: string? = nil
local wasInCabin = true -- gracz zaczyna w chatce
local caveScale = 1 -- ulepszenie „Kryształowy wkład”: mnożnik spalania oleju w jaskini

Signs.start()
PortalView.start()
RackPrompts.start()

Remotes.get("StateUpdate").OnClientEvent:Connect(function(state)
	lanternRange = state.lanternRange
	oil = state.oil
	oilMax = state.oilMax
	chased = state.chased == true
	caveScale = Economy.upgradeStat("crystal", state.upgrades.crystal or 0)
	PortalView.setUnlocked(state.caveUnlocked == true)
	DevPanel.setEnabled(state.dev == true)
	Hud.update(state)
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

-- Etykieta mutacji w języku gracza, np. "🌈 Tęcza + ✨ Blask"
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
	return table.concat(parts, " + ")
end

Remotes.get("MushroomRemoved").OnClientEvent:Connect(function(id)
	-- Serwer usuwa grzyb tylko wtedy, gdy ten gracz go zebrał: czas na efekt
	local info = MushroomView.get(id)
	if info then
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
	MSG_ROBBED = "warn",
	MSG_RACK_ALERT = "warn",
	MSG_RACK_FULL = "warn",
	MSG_NOTHING_TO_HANG = "warn",
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
}

-- Komunikaty, po których gracz ląduje w chatce z czarnym ekranem: klucz -> tytuł
local BLACKOUT_TITLE: { [string]: string } = {
	MSG_ENGULFED = "ENGULF_TITLE",
	MSG_CAUGHT = "CAUGHT_TITLE",
	MSG_ENGULFED_CAVE = "ENGULF_TITLE_CAVE",
}

Remotes.get("Notify").OnClientEvent:Connect(function(payload)
	local args = payload.args
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
		Hud.engulf(Localize.t(blackoutTitle), text)
		Effects.engulf()
		return
	end
	Hud.toast(text, TOAST_KIND[payload.key])
	if payload.key == "MSG_LESZY_WOKE" then
		Effects.leszyWoke()
	elseif payload.key == "MSG_ROBBED" or payload.key == "MSG_RACK_ALERT" then
		Effects.play("engulf", 1.4, 0.5)
	elseif payload.key == "MSG_STOLE" or payload.key == "MSG_ESCAPED" then
		Effects.play("upgrade", 1.2)
	end
	if payload.key == "MSG_SOLD" then
		Effects.sold()
		Hud.coinShower(tonumber(payload.args and payload.args[1]) or 0)
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
Hud.onSell(function()
	SellBasket:FireServer()
end)
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
		glass.Color = Color3.fromRGB(70, 40, 20):Lerp(LANTERN_GLASS, math.clamp(strength, 0, 1))
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
	local oilFraction = if oilMax > 0 then math.clamp(oil / oilMax, 0, 1) else 1
	local now = os.clock()

	local darkness = Atmosphere.update(zone, lanternRange, dt)
	Effects.updateAmbient(darkness)
	Effects.updateParticles(position, zone)
	updateLantern(character, root, oilFraction, darkness, now)
	MushroomView.updateVisibility(position, lanternRange, zoneDef.darkness)

	local safe = Economy.isSafeZone(zone)
	if safe then
		targetId = nil
		MushroomView.updateTarget(position, 0)
	else
		targetId = MushroomView.updateTarget(position, Config.PickRadiusClient)
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local speed = if humanoid then humanoid.WalkSpeed else Economy.upgradeStat("boots", 0)
	local turnBack = Economy.shouldTurnBack(position.Z, speed, oil, caveScale)
	Warnings.update(dt, position, oilFraction, turnBack, zone, lanternRange, chased)
	local heartbeat = if not safe and oilFraction < Config.OilLowFraction then 1 - oilFraction / Config.OilLowFraction * 0.6 else 0
	Effects.setHeartbeat(if chased then 1 else heartbeat)

	-- Panel sprzedaży i ulepszeń tylko w kręgu przy ladzie (w chatce albo w obozowisku)
	local shop = Economy.stationAt("shop", position.X, position.Z)
	Hud.setShop(if shop then shop.world else nil)

	-- Po powrocie z niepełną latarnią: podpowiedź, gdzie jest olej (wnętrze chatki albo obozowisko)
	local inCabin = safe and (zoneDef.world == "cave" or position.Z < -13)
	if inCabin and not wasInCabin and oil < oilMax - 0.5 and not Economy.atStation("oil", position.X, position.Z) then
		Hud.toast(Localize.t("MSG_REFILL_HINT"), "info")
	end
	wasInCabin = inCabin
	Hud.setPick(targetId ~= nil, not safe)
end)
