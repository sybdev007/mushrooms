--!strict
-- Halloween: kocioł „cukierek albo psikus” po stronie gracza.
--   Teksty przycisku (ProximityPrompt z tagiem "CauldronPrompt") i napisu nad kotłem w języku gracza.
--   Wynik z serwera (CauldronResult): okienko „Cukierek!” / „Psikus!” z tym, co wypadło, bąble i dźwięk.
--   Psikus „duch”: duch wyskakuje na cały ekran, błysk i trzęsienie kamery (nic więcej się nie dzieje).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Audio = require(script.Parent.Audio)
local Localize = require(script.Parent.Localize)
local PanelKit = require(script.Parent.PanelKit)
local UiKit = require(script.Parent.UiKit)
local UiScale = require(script.Parent.UiScale)

local CauldronView = {}

local player = Players.LocalPlayer
local TREAT = Color3.fromRGB(72, 168, 80)
local TRICK = Color3.fromRGB(120, 60, 190)
local ICONS: { [string]: string } = {
	coins = "💰",
	luck = "🍀",
	candy = "🍬",
	skin_lantern = "🏮",
	skin_knife = "🌙",
	skin_dupe = "💰",
	trick_pumpkin = "🎃",
	trick_ghostlight = "👻",
	trick_scare = "👻",
	trick_spirits = "👻",
}

-- ===== Teksty przy kotle =====

local function localizePrompt(prompt: Instance)
	if prompt:IsA("ProximityPrompt") then
		prompt.ActionText = Localize.t("CAULDRON_ACTION", { Config.Halloween.cauldron.cost })
		prompt.ObjectText = Localize.t("CAULDRON_NAME")
	end
end

local function localizeSign(sign: Instance)
	local label = sign:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		local progress = Workspace:GetAttribute("HalloweenGoal")
		local target = Workspace:GetAttribute("HalloweenGoalTarget")
		label.Text = Localize.t("CAULDRON_SIGN") .. "\n" .. Localize.t("CAULDRON_GOAL", {
			if typeof(progress) == "number" then progress else 0,
			if typeof(target) == "number" then target else Config.Halloween.goal.target,
		})
	end
end

local function localizeAll()
	for _, prompt in CollectionService:GetTagged("CauldronPrompt") do
		localizePrompt(prompt)
	end
	for _, sign in CollectionService:GetTagged("CauldronSign") do
		localizeSign(sign)
	end
end
CollectionService:GetInstanceAddedSignal("CauldronPrompt"):Connect(localizePrompt)
CollectionService:GetInstanceAddedSignal("CauldronSign"):Connect(localizeSign)
-- Pasek celu serwera nad kotłem odświeża się razem z postępem
Workspace:GetAttributeChangedSignal("HalloweenGoal"):Connect(function()
	for _, sign in CollectionService:GetTagged("CauldronSign") do
		localizeSign(sign)
	end
end)
Localize.onChanged(localizeAll)
task.defer(localizeAll)

-- ===== Okienko z wynikiem =====

local gui = Instance.new("ScreenGui")
gui.Name = "Cauldron"
gui.ResetOnSpawn = false
gui.DisplayOrder = 8
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local card = Instance.new("Frame")
card.Name = "Card"
card.Size = UDim2.fromOffset(440, 128)
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.Position = UDim2.fromScale(0.5, 0.26)
card.BackgroundColor3 = TREAT
card.Visible = false
card.Parent = gui
PanelKit.corner(card, UDim.new(0, 22))
local cardStroke = PanelKit.stroke(card, PanelKit.OUTLINE, 4)
local shade = Instance.new("UIGradient")
shade.Rotation = 90
shade.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(180, 180, 180))
shade.Parent = card
local cardScale = Instance.new("UIScale")
cardScale.Parent = card

local icon = PanelKit.label(card, "Icon", UDim2.fromOffset(96, 96), UDim2.fromOffset(14, 16), 80)
local header = PanelKit.label(card, "Header", UDim2.new(1, -130, 0, 40), UDim2.fromOffset(116, 12), 34)
header.TextXAlignment = Enum.TextXAlignment.Left
UiKit.outline(header, 3)
local body = PanelKit.label(card, "Body", UDim2.new(1, -130, 0, 44), UDim2.fromOffset(116, 52), 22)
body.TextXAlignment = Enum.TextXAlignment.Left
body.TextWrapped = true
UiKit.outline(body, 2)
local bagLine = PanelKit.label(card, "Bag", UDim2.new(1, -130, 0, 20), UDim2.fromOffset(116, 98), 16, PanelKit.GOLD)
bagLine.TextXAlignment = Enum.TextXAlignment.Left
UiKit.outline(bagLine, 1.5)

-- 480000 → „480 000”
local function formatNumber(value: any): string
	if typeof(value) ~= "number" then
		return tostring(value)
	end
	local text = tostring(math.floor(value + 0.5))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (formatted:gsub("^ ", ""))
end

local shown = 0
local function showCard(result: { [string]: any })
	shown += 1
	local token = shown
	local id = tostring(result.id)
	local trick = string.sub(id, 1, 6) == "trick_"
	card.BackgroundColor3 = if trick then TRICK else TREAT
	cardStroke.Color = PanelKit.OUTLINE
	icon.Text = ICONS[id] or "🎃"
	header.Text = Localize.t(if trick then "CAULDRON_TRICK" else "CAULDRON_TREAT")
	local skinName = if typeof(result.skinKey) == "string" then Localize.t(result.skinKey) else ""
	body.Text = Localize.t("CAULDRON_" .. string.upper(id), { formatNumber(result.amount or 0), skinName })
	bagLine.Text = Localize.t("CAULDRON_BAG", { result.bag or 0 })
	local base = UiScale.get()
	card.Visible = true
	cardScale.Scale = base * 0.6
	TweenService:Create(cardScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = base }):Play()
	if not trick then
		UiKit.burst(gui, card.AbsolutePosition + card.AbsoluteSize / 2, 18, { Color3.fromRGB(255, 140, 30), PanelKit.GOLD, Color3.fromRGB(150, 255, 110) })
	end
	task.delay(2.8, function()
		if shown ~= token then
			return
		end
		local out = TweenService:Create(cardScale, TweenInfo.new(0.2), { Scale = base * 0.7 })
		out.Completed:Connect(function()
			if shown == token then
				card.Visible = false
			end
		end)
		out:Play()
	end)
end

-- ===== Psikus: duch na ekranie =====

local flash = Instance.new("Frame")
flash.Name = "Flash"
flash.Size = UDim2.fromScale(1, 1)
flash.BackgroundColor3 = Color3.fromRGB(230, 240, 255)
flash.BackgroundTransparency = 1
flash.Visible = false
flash.ZIndex = 5
flash.Parent = gui
local ghost = Instance.new("TextLabel")
ghost.Name = "Ghost"
ghost.AnchorPoint = Vector2.new(0.5, 0.5)
ghost.Position = UDim2.fromScale(0.5, 0.5)
ghost.Size = UDim2.fromScale(0.5, 0.7)
ghost.BackgroundTransparency = 1
ghost.Text = "👻"
ghost.TextScaled = true
ghost.TextTransparency = 1
ghost.Visible = false
ghost.ZIndex = 6
ghost.Parent = gui
local ghostScale = Instance.new("UIScale")
ghostScale.Parent = ghost

local function scare()
	Audio.play("witch", { volume = 1.2 })
	Audio.play("sting", { volume = 0.8 })
	flash.Visible = true
	ghost.Visible = true
	flash.BackgroundTransparency = 0.2
	ghost.TextTransparency = 0
	ghostScale.Scale = 0.2
	TweenService:Create(ghostScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.15 }):Play()
	TweenService:Create(flash, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
	-- Trzęsienie kamery przez chwilę (przesunięcie po kamerze gracza, potem wraca samo)
	local camera = Workspace.CurrentCamera
	local started = os.clock()
	local connection: RBXScriptConnection? = nil
	connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		if t > 0.5 or not camera then
			if connection then
				connection:Disconnect()
			end
			return
		end
		local power = (0.5 - t) * 0.6
		camera.CFrame *= CFrame.new((math.random() - 0.5) * power, (math.random() - 0.5) * power, 0)
	end)
	task.delay(0.9, function()
		local fade = TweenService:Create(ghost, TweenInfo.new(0.35), { TextTransparency = 1 })
		fade.Completed:Connect(function()
			ghost.Visible = false
			flash.Visible = false
		end)
		fade:Play()
	end)
end

Remotes.get("CauldronResult").OnClientEvent:Connect(function(result)
	if typeof(result) ~= "table" then
		return
	end
	Audio.play("cauldron", { volume = 0.9, duration = 1.6 })
	local id = tostring(result.id)
	if id == "trick_scare" then
		scare()
		task.delay(0.9, showCard, result)
		return
	end
	if string.sub(id, 1, 6) == "trick_" then
		Audio.play("witch", { volume = 0.9 })
	else
		Audio.play("shimmer", { volume = 0.8 })
	end
	showCard(result)
end)

return CauldronView
