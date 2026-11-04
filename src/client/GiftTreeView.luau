--!strict
-- Zima: choinka z prezentami po stronie gracza.
--   Teksty przycisku (ProximityPrompt z tagiem "GiftTreePrompt") i napisu nad choinką w języku gracza.
--   Wynik z serwera (GiftResult): okienko „Prezent!” / „Psikus!” z tym, co wypadło, i dźwięk.
--   Psikus „śnieżka”: śnieżka rozpryskuje się na ekranie (nic więcej się nie dzieje).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Audio = require(script.Parent.Audio)
local Localize = require(script.Parent.Localize)
local PanelKit = require(script.Parent.PanelKit)
local ShopLook = require(script.Parent.ShopLook)
local UiKit = require(script.Parent.UiKit)
local UiScale = require(script.Parent.UiScale)

local GiftTreeView = {}

local player = Players.LocalPlayer
local TREAT = Color3.fromRGB(46, 138, 96)
local TRICK = Color3.fromRGB(60, 112, 190)
local ICONS: { [string]: string } = {
	coins = "💰",
	luck = "🍀",
	flakes = "❄️",
	skin_lantern = "🧊",
	skin_knife = "🍬",
	skin_dupe = "💰",
	trick_snowman = "⛄",
	trick_frost = "🧊",
	trick_snowball = "❄️",
	trick_flurry = "🌨️",
}

-- ===== Teksty przy choince =====

local function localizePrompt(prompt: Instance)
	if prompt:IsA("ProximityPrompt") then
		prompt.ActionText = Localize.t("GIFT_ACTION", { Config.Winter.tree.cost })
		prompt.ObjectText = Localize.t("GIFT_NAME")
	end
end

local function localizeSign(sign: Instance)
	local label = sign:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = Localize.t("GIFT_SIGN")
	end
end

local function localizeAll()
	for _, prompt in CollectionService:GetTagged("GiftTreePrompt") do
		localizePrompt(prompt)
	end
	for _, sign in CollectionService:GetTagged("GiftTreeSign") do
		localizeSign(sign)
	end
end
CollectionService:GetInstanceAddedSignal("GiftTreePrompt"):Connect(localizePrompt)
CollectionService:GetInstanceAddedSignal("GiftTreeSign"):Connect(localizeSign)
Localize.onChanged(localizeAll)
task.defer(localizeAll)

-- ===== Okienko z wynikiem =====

local gui = Instance.new("ScreenGui")
gui.Name = "GiftTree"
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
PanelKit.stroke(card, PanelKit.OUTLINE, 4)
local shade = Instance.new("UIGradient")
shade.Rotation = 90
shade.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(180, 180, 180))
shade.Parent = card
local cardScale = Instance.new("UIScale")
cardScale.Parent = card

local treatHalo = ShopLook.halo(card, UDim2.fromOffset(62, 64), PanelKit.GOLD, 120, true, 1)
local trickHalo = ShopLook.halo(card, UDim2.fromOffset(62, 64), Color3.fromRGB(170, 220, 255), 120, true, 1)
trickHalo.Visible = false
local icon = PanelKit.label(card, "Icon", UDim2.fromOffset(96, 96), UDim2.fromOffset(14, 16), 80)
ShopLook.bob(icon, 4, 1.8)
local header = PanelKit.label(card, "Header", UDim2.new(1, -130, 0, 40), UDim2.fromOffset(116, 12), 34)
header.TextXAlignment = Enum.TextXAlignment.Left
UiKit.outline(header, 3)
ShopLook.title(header)
local body = PanelKit.label(card, "Body", UDim2.new(1, -130, 0, 44), UDim2.fromOffset(116, 52), 22)
body.TextXAlignment = Enum.TextXAlignment.Left
body.TextWrapped = true
UiKit.outline(body, 2)
local bagLine = PanelKit.label(card, "Bag", UDim2.new(1, -130, 0, 20), UDim2.fromOffset(116, 98), 16, Color3.fromRGB(200, 236, 255))
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
	treatHalo.Visible = not trick
	trickHalo.Visible = trick
	icon.Text = ICONS[id] or "🎁"
	header.Text = Localize.t(if trick then "GIFT_TRICK" else "GIFT_TREAT")
	local skinName = if typeof(result.skinKey) == "string" then Localize.t(result.skinKey) else ""
	body.Text = Localize.t("GIFT_" .. string.upper(id), { formatNumber(result.amount or 0), skinName })
	bagLine.Text = Localize.t("GIFT_BAG", { result.bag or 0 })
	local base = UiScale.get()
	card.Visible = true
	cardScale.Scale = base * 0.6
	TweenService:Create(cardScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = base }):Play()
	if not trick then
		UiKit.burst(gui, card.AbsolutePosition + card.AbsoluteSize / 2, 18, { Color3.fromRGB(255, 255, 255), PanelKit.GOLD, Color3.fromRGB(150, 220, 255) })
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

-- ===== Psikus: śnieżka w ekran =====

local splat = Instance.new("Frame")
splat.Name = "Snowball"
splat.AnchorPoint = Vector2.new(0.5, 0.5)
splat.Size = UDim2.fromScale(0.42, 0.42)
splat.SizeConstraint = Enum.SizeConstraint.RelativeYY
splat.BackgroundColor3 = Color3.fromRGB(250, 252, 255)
splat.BackgroundTransparency = 1
splat.Visible = false
splat.ZIndex = 5
splat.Parent = gui
PanelKit.corner(splat, UDim.new(1, 0))
local splatScale = Instance.new("UIScale")
splatScale.Parent = splat
-- Grudki śniegu wokół rozprysku
local crumbs: { Frame } = {}
for i = 1, 8 do
	local crumb = Instance.new("Frame")
	crumb.Name = "Crumb"
	crumb.AnchorPoint = Vector2.new(0.5, 0.5)
	local a = math.rad(i * 45 + 12)
	local r = 0.5 + (i % 3) * 0.08
	crumb.Position = UDim2.fromScale(0.5 + math.cos(a) * r, 0.5 + math.sin(a) * r)
	crumb.Size = UDim2.fromScale(0.16 + (i % 2) * 0.08, 0.16 + (i % 2) * 0.08)
	crumb.BackgroundColor3 = Color3.fromRGB(240, 246, 255)
	crumb.BackgroundTransparency = 1
	crumb.ZIndex = 5
	crumb.Parent = splat
	PanelKit.corner(crumb, UDim.new(1, 0))
	table.insert(crumbs, crumb)
end

local function snowball()
	Audio.play("pat", { volume = 1 })
	splat.Position = UDim2.fromScale(0.35 + math.random() * 0.3, 0.35 + math.random() * 0.25)
	splat.Visible = true
	splat.BackgroundTransparency = 0.05
	for _, crumb in crumbs do
		crumb.BackgroundTransparency = 0.1
	end
	splatScale.Scale = 0.3
	TweenService:Create(splatScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(1.2, function()
		local info = TweenInfo.new(1.4)
		TweenService:Create(splat, info, { BackgroundTransparency = 1, Position = splat.Position + UDim2.fromScale(0, 0.08) }):Play()
		for _, crumb in crumbs do
			TweenService:Create(crumb, info, { BackgroundTransparency = 1 }):Play()
		end
		task.delay(1.5, function()
			splat.Visible = false
		end)
	end)
end

Remotes.get("GiftResult").OnClientEvent:Connect(function(result)
	if typeof(result) ~= "table" then
		return
	end
	local id = tostring(result.id)
	if id == "trick_snowball" then
		snowball()
		task.delay(0.6, showCard, result)
		return
	end
	if string.sub(id, 1, 6) == "trick_" then
		Audio.play("surprise", { volume = 0.8 })
	else
		Audio.play("shimmer", { volume = 0.8 })
	end
	showCard(result)
end)

return GiftTreeView
