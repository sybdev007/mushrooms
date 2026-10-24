--!strict
-- Punkt startowy klienta: łączy HUD, widok grzybów i klimat z wiadomościami serwera.

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

local player = Players.LocalPlayer

local PickMushroom = Remotes.get("PickMushroom")
local SellBasket = Remotes.get("SellBasket")
local BuyUpgrade = Remotes.get("BuyUpgrade")

local lanternRange = Economy.upgradeStat("lantern", 0)
local targetId: string? = nil

Remotes.get("StateUpdate").OnClientEvent:Connect(function(state)
	lanternRange = state.lanternRange
	Hud.update(state)
end)

Remotes.get("MushroomSync").OnClientEvent:Connect(function(list)
	MushroomView.add(list)
end)

Remotes.get("MushroomRemoved").OnClientEvent:Connect(function(id)
	MushroomView.remove(id)
end)

Remotes.get("Notify").OnClientEvent:Connect(function(payload)
	local args = payload.args
	if payload.nameKey then
		args = { Localize.t(payload.nameKey) }
	end
	Hud.toast(Localize.t(payload.key, args))
	if payload.key == "MSG_ENGULFED" then
		Hud.fadeBlack()
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

RunService.RenderStepped:Connect(function(dt)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local position = root.Position
	-- Strefę liczymy też lokalnie, żeby mrok i panel reagowały od razu, bez czekania na serwer
	local zone = Economy.zoneIndexAt(position.Z)
	local zoneDef = Config.Zones[zone]

	Atmosphere.update(zone, lanternRange, dt)
	MushroomView.updateVisibility(position, lanternRange, zoneDef.darkness)

	if zone == 1 then
		targetId = nil
		MushroomView.updateTarget(position, 0)
	else
		targetId = MushroomView.updateTarget(position, Config.PickRadiusClient)
	end

	Hud.setInCabin(zone == 1)
	Hud.setPick(targetId ~= nil, zone ~= 1)
end)
