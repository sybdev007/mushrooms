--!strict
-- Wspólne wyprawy po stronie gracza:
--   plakietka „🤝 Wyprawa ×2: olej −25% · światło +25%” obok paska oleju, gdy idzie się razem,
--   ekran „Latarnia zgasła!” z odliczaniem, gdy gracz czeka na podniesienie,
--   tekst przycisku „Podnieś” w języku gracza (i ukrycie go u samego leżącego).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Expedition = require(Shared.Expedition)
local Remotes = require(Shared.Remotes)
local Localize = require(script.Parent.Localize)
local UiScale = require(script.Parent.UiScale)

local ExpeditionView = {}

local player = Players.LocalPlayer
local TITLE_FONT = Enum.Font.FredokaOne

local gui = Instance.new("ScreenGui")
gui.Name = "Expedition"
gui.ResetOnSpawn = false
gui.DisplayOrder = 3
gui.Parent = player:WaitForChild("PlayerGui")

-- Plakietka wyprawy: po lewej stronie paska oleju (pasek ma 300 px, środek ekranu u góry)
local pill = Instance.new("TextLabel")
pill.Name = "GroupPill"
pill.AnchorPoint = Vector2.new(1, 0)
pill.Size = UDim2.fromOffset(250, 30)
pill.BackgroundColor3 = Color3.fromRGB(34, 60, 40)
pill.BackgroundTransparency = 0.1
pill.TextColor3 = Color3.fromRGB(190, 255, 170)
pill.Font = TITLE_FONT
pill.TextScaled = true
pill.Visible = false
pill.Parent = gui
local pillCorner = Instance.new("UICorner")
pillCorner.CornerRadius = UDim.new(0, 10)
pillCorner.Parent = pill
local pillStroke = Instance.new("UIStroke")
pillStroke.Color = Color3.fromRGB(150, 230, 120)
pillStroke.Thickness = 2
pillStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
pillStroke.Parent = pill
local pillPad = Instance.new("UIPadding")
pillPad.PaddingTop = UDim.new(0, 5)
pillPad.PaddingBottom = UDim.new(0, 5)
pillPad.PaddingLeft = UDim.new(0, 8)
pillPad.PaddingRight = UDim.new(0, 8)
pillPad.Parent = pill
local pillScale = Instance.new("UIScale")
pillScale.Parent = pill

-- Ekran „Latarnia zgasła”: przyciemnienie od brzegów, tytuł i odliczanie
local downedGui = Instance.new("ScreenGui")
downedGui.Name = "Downed"
downedGui.ResetOnSpawn = false
downedGui.DisplayOrder = 19
downedGui.IgnoreGuiInset = true
downedGui.Enabled = false
downedGui.Parent = player:WaitForChild("PlayerGui")
local shade = Instance.new("Frame")
shade.Size = UDim2.fromScale(1, 1)
shade.BackgroundColor3 = Color3.new(0, 0, 0)
shade.BackgroundTransparency = 0.35
shade.BorderSizePixel = 0
shade.Parent = downedGui
local vignette = Instance.new("UIGradient")
vignette.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.5, 0.6),
	NumberSequenceKeypoint.new(1, 0),
})
vignette.Parent = shade
local title = Instance.new("TextLabel")
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.fromScale(0.5, 0.32)
title.Size = UDim2.new(0.8, 0, 0, 56)
title.BackgroundTransparency = 1
title.Font = TITLE_FONT
title.TextScaled = true
title.TextColor3 = Color3.fromRGB(255, 120, 90)
title.TextStrokeTransparency = 0.3
title.Parent = downedGui
local hint = Instance.new("TextLabel")
hint.AnchorPoint = Vector2.new(0.5, 0.5)
hint.Position = UDim2.new(0.5, 0, 0.32, 52)
hint.Size = UDim2.new(0.8, 0, 0, 32)
hint.BackgroundTransparency = 1
hint.Font = TITLE_FONT
hint.TextScaled = true
hint.TextColor3 = Color3.fromRGB(255, 236, 200)
hint.TextStrokeTransparency = 0.3
hint.Parent = downedGui

local group = 1
local downedLeft: number? = nil
local pulse: Tween? = nil

local function render()
	if group > 1 then
		local oil, light = Expedition.bonusPercents(group)
		pill.Text = Localize.t("EXPEDITION_PILL", { group, oil, light })
	end
	pill.Visible = group > 1
	downedGui.Enabled = downedLeft ~= nil
	if downedLeft then
		title.Text = Localize.t("DOWNED_TITLE")
		hint.Text = Localize.t("DOWNED_HINT", { downedLeft })
	end
end

local function layout()
	local scale = UiScale.get()
	pillScale.Scale = scale
	pill.Position = UDim2.new(0.5, -math.floor(156 * scale), 0, 8 + math.floor(34 * scale))
end

Remotes.get("StateUpdate").OnClientEvent:Connect(function(state)
	local newGroup = tonumber(state.group) or 1
	local wasDowned = downedLeft ~= nil
	downedLeft = tonumber(state.downed)
	if newGroup > 1 and group <= 1 then
		-- Połączenie latarni: plakietka podskakuje
		pillScale.Scale = UiScale.get() * 1.25
		TweenService:Create(pillScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = UiScale.get() }):Play()
	end
	group = newGroup
	if downedLeft and not wasDowned then
		-- Ciemność pulsuje, jak gasnący płomień
		shade.BackgroundTransparency = 0.6
		local tween = TweenService:Create(shade, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
			BackgroundTransparency = 0.25,
		})
		tween:Play()
		pulse = tween
	elseif not downedLeft and pulse then
		pulse:Cancel()
		pulse = nil
	end
	render()
end)

-- Przycisk „Podnieś” na leżącym graczu: tekst w języku gracza; sam leżący go nie widzi
local function setupPrompt(instance: Instance)
	if not instance:IsA("ProximityPrompt") then
		return
	end
	instance.ActionText = Localize.t("REVIVE_ACTION")
	if instance:GetAttribute("OwnerUserId") == player.UserId then
		instance.Enabled = false
	end
end
for _, prompt in CollectionService:GetTagged("RevivePrompt") do
	setupPrompt(prompt)
end
CollectionService:GetInstanceAddedSignal("RevivePrompt"):Connect(setupPrompt)

Localize.onChanged(function()
	render()
	for _, prompt in CollectionService:GetTagged("RevivePrompt") do
		setupPrompt(prompt)
	end
end)
UiScale.onChanged(layout)
layout()

function ExpeditionView.group(): number
	return group
end

return ExpeditionView
