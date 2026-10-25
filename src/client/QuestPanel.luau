--!strict
-- Zadania na dziś (3 karty z postępem, nagrodą i jedną wymianą dziennie), premia za wszystkie trzy
-- i seria logowań (7 dni w kółko, 7. dzień z miksturą szczęścia). Nagrody przychodzą same.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Progress = require(Shared.Progress)
local Remotes = require(Shared.Remotes)
local Localize = require(script.Parent.Localize)
local SideButtons = require(script.Parent.SideButtons)
local UiKit = require(script.Parent.UiKit)
local UiScale = require(script.Parent.UiScale)

local QuestPanel = {}

local TITLE_FONT = Enum.Font.FredokaOne
local BODY_FONT = Enum.Font.GothamBold
local TEXT = Color3.fromRGB(252, 238, 210)
local MUTED = Color3.fromRGB(214, 188, 150)
local ACCENT = Color3.fromRGB(255, 214, 120)
local GREEN = Color3.fromRGB(150, 255, 150)
local PANEL = Color3.fromRGB(40, 28, 20)
local CARD = Color3.fromRGB(58, 42, 30)
local WIDTH, HEIGHT = 440, 430

local QuestReroll = Remotes.get("QuestReroll")

local gui = Instance.new("ScreenGui")
gui.Name = "Quests"
gui.ResetOnSpawn = false
gui.DisplayOrder = 6
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function text(parent: Instance, name: string, size: UDim2, position: UDim2, font: Enum.Font, maxSize: number, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = size
	l.Position = position
	l.BackgroundTransparency = 1
	l.TextColor3 = color or TEXT
	l.Font = font
	l.TextScaled = true
	l.RichText = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = maxSize
	c.Parent = l
	return l
end

local panel = Instance.new("Frame")
panel.Name = "QuestPanel"
panel.Size = UDim2.fromOffset(WIDTH, HEIGHT)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.BackgroundColor3 = PANEL
panel.Visible = false
panel.Parent = gui
corner(panel, 14)
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(200, 146, 74)
panelStroke.Thickness = 2
panelStroke.Parent = panel
local panelScale = Instance.new("UIScale")
panelScale.Parent = panel

UiKit.icon("scroll", panel, UDim2.fromOffset(34, 34), UDim2.fromOffset(12, 8))
local title = text(panel, "Title", UDim2.new(1, -110, 0, 26), UDim2.fromOffset(52, 8), TITLE_FONT, 24, ACCENT)
local timer = text(panel, "Timer", UDim2.new(1, -110, 0, 16), UDim2.fromOffset(52, 33), BODY_FONT, 13, MUTED)
local close = Instance.new("TextButton")
close.Name = "Close"
close.Size = UDim2.fromOffset(32, 32)
close.Position = UDim2.new(1, -42, 0, 10)
close.Text = ""
close.Parent = panel
UiKit.button(close, UiKit.COLORS.wood, { gloss = true, radius = UDim.new(0, 8) })
UiKit.icon("close", close, UDim2.fromOffset(22, 22), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))

-- Karty zadań
type Card = { frame: Frame, label: TextLabel, count: TextLabel, reward: TextLabel, fill: Frame, swap: TextButton, check: TextLabel }
local cards: { Card } = {}
for index = 1, Progress.QUESTS_PER_DAY do
	local frame = Instance.new("Frame")
	frame.Name = "Quest" .. index
	frame.Size = UDim2.new(1, -24, 0, 64)
	frame.Position = UDim2.fromOffset(12, 58 + (index - 1) * 72)
	frame.BackgroundColor3 = CARD
	frame.Parent = panel
	corner(frame, 10)
	local check = text(frame, "Check", UDim2.fromOffset(30, 30), UDim2.fromOffset(8, 8), TITLE_FONT, 26, MUTED)
	check.TextXAlignment = Enum.TextXAlignment.Center
	local label = text(frame, "Label", UDim2.new(1, -150, 0, 20), UDim2.fromOffset(44, 8), TITLE_FONT, 17)
	local reward = text(frame, "Reward", UDim2.new(1, -150, 0, 16), UDim2.fromOffset(44, 30), BODY_FONT, 13, ACCENT)
	local count = text(frame, "Count", UDim2.fromOffset(60, 16), UDim2.new(1, -164, 0, 30), BODY_FONT, 13, MUTED)
	count.TextXAlignment = Enum.TextXAlignment.Right
	local back = Instance.new("Frame")
	back.Size = UDim2.new(1, -144, 0, 6)
	back.Position = UDim2.fromOffset(44, 50)
	back.BackgroundColor3 = Color3.fromRGB(20, 14, 10)
	back.BorderSizePixel = 0
	back.Parent = frame
	corner(back, 3)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = ACCENT
	fill.BorderSizePixel = 0
	fill.Parent = back
	corner(fill, 3)
	local swap = Instance.new("TextButton")
	swap.Name = "Swap"
	swap.Size = UDim2.fromOffset(80, 34)
	swap.Position = UDim2.new(1, -90, 0.5, 0)
	swap.AnchorPoint = Vector2.new(0, 0.5)
	swap.Font = TITLE_FONT
	swap.TextScaled = true
	swap.Parent = frame
	UiKit.button(swap, UiKit.COLORS.wood, { radius = UDim.new(0, 8) })
	local swapPad = Instance.new("UIPadding")
	swapPad.PaddingTop = UDim.new(0, 7)
	swapPad.PaddingBottom = UDim.new(0, 7)
	swapPad.PaddingLeft = UDim.new(0, 26)
	swapPad.PaddingRight = UDim.new(0, 6)
	swapPad.Parent = swap
	UiKit.icon("dice", swap, UDim2.fromOffset(22, 22), UDim2.new(0, -22, 0.5, 0), Vector2.new(0, 0.5))
	swap.Activated:Connect(function()
		QuestReroll:FireServer(index)
	end)
	cards[index] = { frame = frame, label = label, count = count, reward = reward, fill = fill, swap = swap, check = check }
end

local bonusLine = text(panel, "Bonus", UDim2.new(1, -24, 0, 20), UDim2.fromOffset(12, 58 + 3 * 72 + 2), TITLE_FONT, 16, ACCENT)

-- Seria logowań: 7 kółek z nagrodami
local streakTitle = text(panel, "StreakTitle", UDim2.new(1, -24, 0, 20), UDim2.fromOffset(12, 58 + 3 * 72 + 30), TITLE_FONT, 17)
local streakRow = Instance.new("Frame")
streakRow.BackgroundTransparency = 1
streakRow.Size = UDim2.new(1, -24, 0, 64)
streakRow.Position = UDim2.fromOffset(12, 58 + 3 * 72 + 54)
streakRow.Parent = panel
local streakGrid = Instance.new("UIGridLayout")
streakGrid.CellSize = UDim2.new(1 / #Progress.LOGIN_REWARDS, -6, 1, 0)
streakGrid.CellPadding = UDim2.fromOffset(6, 0)
streakGrid.SortOrder = Enum.SortOrder.LayoutOrder
streakGrid.Parent = streakRow
type Day = { frame: Frame, day: TextLabel, amount: TextLabel, stroke: UIStroke }
local days: { Day } = {}
for index = 1, #Progress.LOGIN_REWARDS do
	local frame = Instance.new("Frame")
	frame.LayoutOrder = index
	frame.BackgroundColor3 = CARD
	frame.Parent = streakRow
	corner(frame, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(110, 80, 52)
	stroke.Thickness = 1.5
	stroke.Parent = frame
	local day = text(frame, "Day", UDim2.new(1, -4, 0, 16), UDim2.fromOffset(2, 4), BODY_FONT, 12, MUTED)
	day.TextXAlignment = Enum.TextXAlignment.Center
	UiKit.icon(if index == #Progress.LOGIN_REWARDS then "luck" else "gift", frame, UDim2.fromOffset(22, 22), UDim2.new(0.5, 0, 0, 20), Vector2.new(0.5, 0))
	local amount = text(frame, "Amount", UDim2.new(1, -4, 0, 14), UDim2.new(0, 2, 1, -17), BODY_FONT, 11, ACCENT)
	amount.TextXAlignment = Enum.TextXAlignment.Center
	days[index] = { frame = frame, day = day, amount = amount, stroke = stroke }
end
local streakHint = text(panel, "StreakHint", UDim2.new(1, -24, 0, 16), UDim2.new(0, 12, 1, -24), BODY_FONT, 13, MUTED)

-- ===== Stan =====

local state: any = nil
local button, badge = SideButtons.add("QuestButton", "scroll", Color3.fromRGB(70, 120, 170))

local function formatCoins(value: number): string
	local s = tostring(math.floor(value + 0.5))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (formatted:gsub("^ ", ""))
end

local function formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d:%02d", seconds // 3600, seconds // 60 % 60, seconds % 60)
end

local function refreshBadge()
	if not state then
		badge.Text = ""
		return
	end
	local done = 0
	for _, quest in state.quests do
		if quest.done then
			done += 1
		end
	end
	badge.Text = string.format("%d/%d", done, #state.quests)
	badge.TextColor3 = if done >= #state.quests then GREEN else Color3.fromRGB(255, 252, 240)
end

local function render()
	title.Text = Localize.t("QUESTS_TITLE")
	if not state then
		return
	end
	timer.Text = Localize.t("QUESTS_RESET", { formatTime(state.resetAt - os.time()) })
	for index, card in cards do
		local quest = state.quests[index]
		card.frame.Visible = quest ~= nil
		if quest then
			card.label.Text = Localize.t("QUEST_" .. string.upper(quest.id), { quest.goal })
			card.reward.Text = "💰 " .. formatCoins(quest.reward)
			card.count.Text = string.format("%d/%d", quest.n, quest.goal)
			card.fill.Size = UDim2.new(math.clamp(quest.n / quest.goal, 0, 1), 0, 1, 0)
			card.fill.BackgroundColor3 = if quest.done then GREEN else ACCENT
			card.check.Text = if quest.done then "✅" else "•"
			card.check.TextColor3 = if quest.done then GREEN else MUTED
			card.swap.Visible = not quest.done and not state.rerolled
			card.swap.Text = Localize.t("QUESTS_REROLL")
			card.label.TextColor3 = if quest.done then GREEN else TEXT
		end
	end
	bonusLine.Text = if state.bonusDone
		then Localize.t("QUESTS_BONUS_DONE")
		else Localize.t("QUESTS_BONUS", { formatCoins(state.dailyBonus), math.floor(Progress.DAILY_BONUS.luckSeconds / 60) })
	bonusLine.TextColor3 = if state.bonusDone then GREEN else ACCENT

	streakTitle.Text = Localize.t("QUESTS_STREAK", { state.streak })
	for index, day in days do
		local isToday = index == state.loginDay
		local claimed = index <= state.loginDay
		day.day.Text = Localize.t("QUESTS_DAY", { index })
		day.amount.Text = formatCoins(Progress.LOGIN_REWARDS[index] * state.scale)
		day.frame.BackgroundColor3 = if isToday then Color3.fromRGB(110, 76, 36) elseif claimed then Color3.fromRGB(52, 70, 40) else CARD
		day.stroke.Color = if isToday then ACCENT else Color3.fromRGB(110, 80, 52)
		day.stroke.Thickness = if isToday then 3 else 1.5
	end
	local nextDay = state.loginDay % #Progress.LOGIN_REWARDS + 1
	streakHint.Text = Localize.t("QUESTS_STREAK_HINT", { nextDay, formatCoins(Progress.LOGIN_REWARDS[nextDay] * state.scale) })
end

function QuestPanel.toggle()
	panel.Visible = not panel.Visible
	if panel.Visible then
		render()
	end
end

button.Activated:Connect(QuestPanel.toggle)
close.Activated:Connect(function()
	panel.Visible = false
end)

Remotes.get("ProgressUpdate").OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" or typeof(payload.quests) ~= "table" then
		return
	end
	state = payload
	refreshBadge()
	if panel.Visible then
		render()
	end
end)

Localize.onChanged(function()
	if panel.Visible then
		render()
	end
end)
UiScale.onChanged(function()
	panelScale.Scale = UiScale.get()
end)

-- Odliczanie do nowych zadań
task.spawn(function()
	while true do
		task.wait(1)
		if panel.Visible and state then
			timer.Text = Localize.t("QUESTS_RESET", { formatTime(state.resetAt - os.time()) })
		end
	end
end)

return QuestPanel
