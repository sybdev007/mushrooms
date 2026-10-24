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

local player = Players.LocalPlayer

local PickMushroom = Remotes.get("PickMushroom")
local SellBasket = Remotes.get("SellBasket")
local BuyUpgrade = Remotes.get("BuyUpgrade")

local LANTERN_BRIGHTNESS = 2 -- w najciemniejszej strefie; przy chatce latarnia świeci słabiej, żeby nie przepalać ścian
local CABIN_PANEL_MAX_Z = 4 -- ganek kończy się ok. z = -5, panel widać jeszcze kilka kroków dalej
local LANTERN_GLASS = Color3.fromRGB(255, 206, 120)

local lanternRange = Economy.upgradeStat("lantern", 0)
local oil = Economy.upgradeStat("oil", 0)
local oilMax = oil
local targetId: string? = nil

Signs.start()

Remotes.get("StateUpdate").OnClientEvent:Connect(function(state)
	lanternRange = state.lanternRange
	oil = state.oil
	oilMax = state.oilMax
	Hud.update(state)
end)

Remotes.get("MushroomSync").OnClientEvent:Connect(function(list)
	MushroomView.add(list)
end)

Remotes.get("MushroomRemoved").OnClientEvent:Connect(function(id)
	-- Serwer usuwa grzyb tylko wtedy, gdy ten gracz go zebrał: czas na efekt
	local info = MushroomView.get(id)
	if info then
		Effects.collect(
			info.position,
			MushroomView.capColor(info.species, info.golden),
			Economy.mushroomValue(info.species, info.golden),
			info.golden
		)
	end
	MushroomView.remove(id)
end)

local TOAST_KIND: { [string]: string } = {
	MSG_GOLDEN = "gold",
	MSG_OIL_HALF = "warn",
	MSG_OIL_LOW = "warn",
	MSG_BASKET_FULL = "warn",
	MSG_NOT_ENOUGH = "warn",
	MSG_ENGULFED = "warn",
}

Remotes.get("Notify").OnClientEvent:Connect(function(payload)
	local args = payload.args
	if payload.nameKey then
		args = { Localize.t(payload.nameKey) }
	end
	local text = Localize.t(payload.key, args)
	if payload.key == "MSG_ENGULFED" then
		Hud.engulf(Localize.t("ENGULF_TITLE"), text)
		Effects.engulf()
		return
	end
	Hud.toast(text, TOAST_KIND[payload.key])
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

	if zone == 1 then
		targetId = nil
		MushroomView.updateTarget(position, 0)
	else
		targetId = MushroomView.updateTarget(position, Config.PickRadiusClient)
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local speed = if humanoid then humanoid.WalkSpeed else Economy.upgradeStat("boots", 0)
	local turnBack = Economy.shouldTurnBack(position.Z, speed, oil)
	Warnings.update(dt, position, oilFraction, turnBack, zone, lanternRange)
	Effects.setHeartbeat(if zone ~= 1 and oilFraction < Config.OilLowFraction then 1 - oilFraction / Config.OilLowFraction * 0.6 else 0)

	-- Panel sprzedaży tylko przy chatce, żeby nie zasłaniał ekranu na całej polanie
	Hud.setInCabin(zone == 1 and position.Z < CABIN_PANEL_MAX_Z)
	Hud.setPick(targetId ~= nil, zone ~= 1)
end)
