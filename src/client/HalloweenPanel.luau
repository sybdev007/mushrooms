--!strict
-- Okno eventu Halloween „Noc Dziadów” (styl PanelKit, jak Zadania): ile cukierków, ścieżka nagród
-- (pięć kafelków z progami i pasek), jak zdobywać cukierki i kiedy następna Noc Dziadów.
-- Przycisk 🎃 pojawia się z prawej tylko w czasie eventu. Nagrody przychodzą same (ProgressService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Halloween = require(Shared.Halloween)
local Remotes = require(Shared.Remotes)
local Localize = require(script.Parent.Localize)
local PanelKit = require(script.Parent.PanelKit)
local SideButtons = require(script.Parent.SideButtons)
local UiKit = require(script.Parent.UiKit)

local HalloweenPanel = {}

local OUTLINE = PanelKit.OUTLINE
local ORANGE = Color3.fromRGB(240, 128, 30)
local PURPLE = Color3.fromRGB(96, 52, 150)
local PURPLE_DARK = Color3.fromRGB(58, 32, 92)
local WIDTH, HEIGHT = 620, 480
local TILE_W, TILE_H, TILE_GAP = 104, 122, 12

local function now(): number
	return Workspace:GetServerTimeNow()
end

-- Event trwa (serwer ustawia atrybut; zanim go ustawi, liczymy z daty)
local function eventOn(): boolean
	local attr = Workspace:GetAttribute("Halloween")
	if typeof(attr) == "boolean" then
		return attr
	end
	return Halloween.active(now())
end

local window = PanelKit.window({
	name = "Halloween",
	parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	width = WIDTH,
	height = HEIGHT,
	ribbon = ORANGE,
	icon = "pumpkin",
	pillIcon = "candy",
	pillColor = PURPLE_DARK,
})
local content = window.content

local timer = PanelKit.label(content, "Timer", UDim2.new(1, -40, 0, 20), UDim2.fromOffset(20, 2), 17, PanelKit.MUTED)

-- ===== Ścieżka nagród =====

type Tile = { frame: Frame, stroke: UIStroke, need: TextLabel, reward: TextLabel, check: GuiObject, icon: TextLabel }
local tiles: { Tile } = {}
local track = Halloween.TRACK
local rowWidth = #track * TILE_W + (#track - 1) * TILE_GAP
local rowX = math.floor((WIDTH - 28 - rowWidth) / 2)

for index, step in track do
	local frame = Instance.new("Frame")
	frame.Name = "Step" .. index
	frame.Size = UDim2.fromOffset(TILE_W, TILE_H)
	frame.Position = UDim2.fromOffset(rowX + (index - 1) * (TILE_W + TILE_GAP), 32)
	frame.BackgroundColor3 = PURPLE
	frame.ZIndex = 4
	frame.Parent = content
	PanelKit.corner(frame, UDim.new(0, 16))
	local tileStroke = PanelKit.stroke(frame, OUTLINE, 3)
	local shade = Instance.new("UIGradient")
	shade.Rotation = 90
	shade.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(180, 180, 180))
	shade.Parent = frame

	local icon = PanelKit.label(frame, "Icon", UDim2.new(1, 0, 0, 44), UDim2.fromOffset(0, 6), 38)
	icon.Text = step.icon
	icon.ZIndex = 6
	local need = PanelKit.label(frame, "Need", UDim2.new(1, -8, 0, 22), UDim2.fromOffset(4, 50), 20, PanelKit.GOLD)
	need.ZIndex = 6
	UiKit.outline(need, 2)
	local reward = PanelKit.label(frame, "Reward", UDim2.new(1, -10, 0, 42), UDim2.fromOffset(5, 74), 15)
	reward.TextWrapped = true
	reward.ZIndex = 6
	UiKit.outline(reward, 1.5)
	local check = UiKit.icon("check", frame, UDim2.fromOffset(30, 30), UDim2.new(1, 6, 0, -6), Vector2.new(1, 0))
	check.ZIndex = 8
	check.Visible = false
	tiles[index] = { frame = frame, stroke = tileStroke, need = need, reward = reward, check = check, icon = icon }
end

-- Pasek pod kafelkami: każdy odcinek między progami ma tę samą długość (progi rosną nierówno)
local _, fill, barText = PanelKit.bar(content, UDim2.fromOffset(rowWidth, 30), UDim2.fromOffset(rowX, 32 + TILE_H + 14), ORANGE)

local function trackFraction(candy: number): number
	local previous = 0
	for index, step in track do
		if candy < step.candy then
			local part = (candy - previous) / math.max(step.candy - previous, 1)
			return ((index - 1) + part) / #track
		end
		previous = step.candy
	end
	return 1
end

-- ===== Jak zdobyć cukierki =====

local HOW_Y = 32 + TILE_H + 14 + 30 + 16
local howTitle = PanelKit.label(content, "HowTitle", UDim2.new(1, -40, 0, 24), UDim2.fromOffset(20, HOW_Y), 21, PanelKit.GOLD)
howTitle.TextXAlignment = Enum.TextXAlignment.Left
UiKit.outline(howTitle, 2)

local HOW_KEYS = { "HW_HOW_PUMPKIN", "HW_HOW_QUEST", "HW_HOW_RISK" }
local howLines: { TextLabel } = {}
for index in HOW_KEYS do
	local line = PanelKit.label(content, "How" .. index, UDim2.new(1, -40, 0, 34), UDim2.fromOffset(20, HOW_Y + 28 + (index - 1) * 38), 16, PanelKit.TEXT, PanelKit.BODY_FONT)
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.TextWrapped = true
	howLines[index] = line
end

-- Noc Dziadów: fioletowa karta z odliczaniem
local spiritCard = Instance.new("Frame")
spiritCard.Name = "SpiritNight"
spiritCard.Size = UDim2.new(1, -24, 0, 56)
spiritCard.Position = UDim2.fromOffset(12, HOW_Y + 28 + #HOW_KEYS * 38 + 6)
spiritCard.BackgroundColor3 = PURPLE_DARK
spiritCard.ZIndex = 4
spiritCard.Parent = content
PanelKit.corner(spiritCard, UDim.new(0, 16))
local spiritStroke = PanelKit.stroke(spiritCard, OUTLINE, 3)
local spiritText = PanelKit.label(spiritCard, "Text", UDim2.new(1, -24, 1, -10), UDim2.fromOffset(12, 5), 19)
spiritText.TextWrapped = true
spiritText.ZIndex = 6
UiKit.outline(spiritText, 2)

-- ===== Stan =====

local state: any = nil
local side: SideButtons.Side? = nil
local spiritPulse: Tween? = nil

local function formatCoins(value: number): string
	local s = tostring(math.floor(value + 0.5))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (formatted:gsub("^ ", ""))
end

local function formatLeft(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 86400 then
		return Localize.t("HW_TIME_DAYS", { seconds // 86400, seconds // 3600 % 24 })
	elseif seconds >= 3600 then
		return Localize.t("HW_TIME_HOURS", { seconds // 3600, seconds // 60 % 60 })
	end
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function candyOf(): number
	local stats = state and state.stats
	return if stats and typeof(stats.candy) == "number" then stats.candy else 0
end

local function rewardText(step: any): string
	if step.kind == "title" and step.id then
		return Localize.t("HW_REWARD_TITLE", { Localize.t(step.id) })
	elseif step.kind == "luck" and step.seconds then
		return Localize.t("HW_REWARD_LUCK", { math.floor(step.seconds / 60) })
	elseif step.kind == "coins" and step.scale then
		local scale = if state and typeof(state.scale) == "number" then state.scale else 50
		return Localize.t("HW_REWARD_COINS", { formatCoins(step.scale * scale) })
	end
	return ""
end

local function renderSpirit()
	local t = now()
	local current = Workspace:GetAttribute("CyclePhase") == "night" and Workspace:GetAttribute("CycleEvent") == Halloween.SPIRIT_NIGHT
	if current then
		local endsAt = Workspace:GetAttribute("CycleEndsAt")
		local left = if typeof(endsAt) == "number" then endsAt - t else 0
		spiritText.Text = Localize.t("HW_SPIRIT_NOW", { formatLeft(left) })
		spiritCard.BackgroundColor3 = Color3.fromRGB(120, 60, 190)
	else
		local start = Halloween.nextSpiritNight(t)
		spiritText.Text = if start and eventOn()
			then Localize.t("HW_SPIRIT_NEXT", { formatLeft(start - t) })
			else Localize.t("HW_SPIRIT_NONE")
		spiritCard.BackgroundColor3 = PURPLE_DARK
	end
	if current and window.isOpen() and not spiritPulse then
		spiritStroke.Color = PanelKit.GOLD
		local tween = TweenService:Create(spiritStroke, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 5 })
		tween:Play()
		spiritPulse = tween
	elseif not current and spiritPulse then
		spiritPulse:Cancel()
		spiritPulse = nil
		spiritStroke.Thickness = 3
		spiritStroke.Color = OUTLINE
	end
end

local function renderTimer()
	timer.Text = if eventOn()
		then Localize.t("HW_ENDS", { formatLeft(Halloween.secondsLeft(now())) })
		else Localize.t("HW_ENDED")
end

local lastReached = -1

local function render()
	window.title.Text = Localize.t("HW_TITLE")
	local candy = candyOf()
	window.pillText.Text = tostring(candy)
	renderTimer()
	local reached = Halloween.reached(candy)
	for index, tile in tiles do
		local step = track[index]
		local done = index <= reached
		local nextOne = index == reached + 1
		tile.need.Text = string.format("%d 🍬", step.candy)
		local text = rewardText(step)
		if step.candy == Config.Halloween.badgeCandy then
			text ..= "\n" .. Localize.t("HW_REWARD_BADGE")
		end
		tile.reward.Text = text
		tile.check.Visible = done
		tile.frame.BackgroundColor3 = if done then Color3.fromRGB(72, 150, 70) elseif nextOne then Color3.fromRGB(150, 70, 190) else PURPLE
		tile.stroke.Color = if nextOne then PanelKit.GOLD else OUTLINE
		tile.stroke.Thickness = if nextOne then 4 else 3
	end
	fill.Size = UDim2.fromScale(math.clamp(trackFraction(candy), 0, 1), 1)
	local nextStep = track[reached + 1]
	barText.Text = if nextStep then string.format("%d / %d 🍬", candy, nextStep.candy) else Localize.t("HW_TRACK_DONE", { candy })
	-- Właśnie osiągnięty próg przy otwartym oknie: iskry nad kafelkiem
	if lastReached >= 0 and reached > lastReached and window.isOpen() then
		local tile = tiles[reached]
		if tile then
			UiKit.burst(window.gui, tile.frame.AbsolutePosition + tile.frame.AbsoluteSize / 2, 16, { ORANGE, PanelKit.GOLD, Color3.fromRGB(170, 100, 255) })
		end
	end
	lastReached = reached

	howTitle.Text = Localize.t("HW_HOW_TITLE")
	local byWorld = Config.Halloween.candyByWorld
	howLines[1].Text = Localize.t("HW_HOW_PUMPKIN", { byWorld.forest, byWorld.cave, byWorld.swamp })
	howLines[2].Text = Localize.t("HW_HOW_QUEST", { Config.Halloween.questCandy })
	howLines[3].Text = Localize.t("HW_HOW_RISK")
	renderSpirit()
end

local function refreshBadge()
	if side then
		side.setBadge(tostring(candyOf()) .. "🍬", "info")
	end
end

function HalloweenPanel.toggle()
	window.setOpen(not window.isOpen())
end

window.onToggle(function(open: boolean)
	if open then
		render()
	elseif spiritPulse then
		spiritPulse:Cancel()
		spiritPulse = nil
	end
end)

-- Przycisk tylko w czasie eventu (pierwszy w kolumnie: event jest teraz najważniejszy)
if eventOn() then
	local button = SideButtons.add({
		name = "HalloweenButton",
		icon = "pumpkin",
		color = ORANGE,
		caption = "HW_BUTTON",
		key = Enum.KeyCode.H,
	})
	button.onActivated(HalloweenPanel.toggle)
	side = button
end

Remotes.get("ProgressUpdate").OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	state = payload
	refreshBadge()
	if window.isOpen() then
		render()
	end
end)

Localize.onChanged(function()
	if window.isOpen() then
		render()
	end
end)

task.spawn(function()
	while true do
		task.wait(1)
		if window.isOpen() then
			renderTimer()
			renderSpirit()
		end
	end
end)

return HalloweenPanel
