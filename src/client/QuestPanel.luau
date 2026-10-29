--!strict
-- Zadania na dziś w stylu okna ulepszeń (PanelKit): trzy kolorowe karty z dużą ikoną, grubym paskiem
-- postępu i nagrodą jak przycisk; kostka do wymiany jednego zadania dziennie; premia za komplet
-- i siedem kafelków serii logowań (7. dzień z miksturą szczęścia). Nagrody przychodzą same.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Progress = require(Shared.Progress)
local Remotes = require(Shared.Remotes)
local Localize = require(script.Parent.Localize)
local PanelKit = require(script.Parent.PanelKit)
local SideButtons = require(script.Parent.SideButtons)
local UiKit = require(script.Parent.UiKit)

local QuestPanel = {}

local OUTLINE = PanelKit.OUTLINE
local WIDTH, HEIGHT = 640, 500
local CARD_H = 86

local QuestReroll = Remotes.get("QuestReroll")

-- Kolor i ikona karty według rodzaju zadania
local QUEST_LOOK: { [string]: { color: Color3, icon: string } } = {
	pick = { color = Color3.fromRGB(226, 84, 64), icon = "mushroom" },
	pickMutated = { color = Color3.fromRGB(150, 92, 230), icon = "sparkles" },
	pickGold = { color = Color3.fromRGB(236, 168, 32), icon = "star" },
	sell = { color = Color3.fromRGB(64, 170, 88), icon = "coins" },
	escape = { color = Color3.fromRGB(60, 140, 232), icon = "boots" },
	steal = { color = Color3.fromRGB(200, 70, 120), icon = "sell" },
	plant = { color = Color3.fromRGB(84, 176, 72), icon = "beds" },
	collect = { color = Color3.fromRGB(196, 130, 56), icon = "chest" },
	upgrade = { color = Color3.fromRGB(120, 86, 220), icon = "upgrade" },
	discover = { color = Color3.fromRGB(176, 104, 54), icon = "book" },
	revive = { color = Color3.fromRGB(230, 96, 96), icon = "rescue" },
}
local DEFAULT_LOOK = { color = Color3.fromRGB(140, 110, 80), icon = "star" }

local window = PanelKit.window({
	name = "Quests",
	parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	width = WIDTH,
	height = HEIGHT,
	ribbon = Color3.fromRGB(64, 140, 220),
	icon = "scroll",
	pillIcon = "star",
	pillColor = Color3.fromRGB(70, 44, 92),
})
local content = window.content

local timer = PanelKit.label(content, "Timer", UDim2.new(1, -40, 0, 20), UDim2.fromOffset(20, 0), 17, PanelKit.MUTED)

-- ===== Karty zadań =====

type Card = {
	holder: Frame,
	body: Frame,
	bodyStroke: UIStroke,
	iconHolder: Frame,
	icon: GuiObject,
	label: TextLabel,
	fill: Frame,
	barText: TextLabel,
	reward: TextLabel,
	rewardPill: Frame,
	swap: TextButton,
	done: boolean,
}
local cards: { Card } = {}

for index = 1, Progress.QUESTS_PER_DAY do
	local holder = Instance.new("Frame")
	holder.Name = "Quest" .. index
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, -16, 0, CARD_H)
	holder.Position = UDim2.fromOffset(8, 26 + (index - 1) * (CARD_H + 10))
	holder.ZIndex = 4
	holder.Parent = content

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Size = UDim2.fromScale(1, 1)
	body.BackgroundColor3 = DEFAULT_LOOK.color
	body.ZIndex = 4
	body.Parent = holder
	PanelKit.corner(body, UDim.new(0, 18))
	local bodyStroke = PanelKit.stroke(body, OUTLINE, 3.5)
	local shade = Instance.new("UIGradient")
	shade.Rotation = 90
	shade.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(186, 186, 186))
	shade.Parent = body

	-- Duża ikona w jaśniejszym kółku
	local iconHolder = Instance.new("Frame")
	iconHolder.Name = "IconHolder"
	iconHolder.Size = UDim2.fromOffset(66, 66)
	iconHolder.Position = UDim2.new(0, 10, 0.5, 0)
	iconHolder.AnchorPoint = Vector2.new(0, 0.5)
	iconHolder.BackgroundColor3 = Color3.new(1, 1, 1)
	iconHolder.BackgroundTransparency = 0.72
	iconHolder.ZIndex = 5
	iconHolder.Parent = body
	PanelKit.corner(iconHolder, UDim.new(1, 0))
	local icon = UiKit.icon("mushroom", iconHolder, UDim2.fromScale(0.86, 0.86), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	icon.ZIndex = 6

	local label = PanelKit.label(body, "Label", UDim2.new(1, -250, 0, 28), UDim2.fromOffset(88, 10), 22)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 6
	UiKit.outline(label, 2.5)
	local _, fill, barText = PanelKit.bar(body, UDim2.new(1, -250, 0, 26), UDim2.fromOffset(88, 46), PanelKit.GOLD)

	-- Nagroda jak przycisk z ceną
	local rewardPill = Instance.new("Frame")
	rewardPill.Name = "Reward"
	rewardPill.Size = UDim2.fromOffset(140, 42)
	rewardPill.AnchorPoint = Vector2.new(1, 0.5)
	rewardPill.Position = UDim2.new(1, -12, 0.5, 6)
	rewardPill.BackgroundColor3 = Color3.fromRGB(246, 182, 40)
	rewardPill.ZIndex = 6
	rewardPill.Parent = body
	PanelKit.corner(rewardPill, UDim.new(0, 12))
	PanelKit.stroke(rewardPill, OUTLINE, 3)
	local rewardShade = Instance.new("UIGradient")
	rewardShade.Rotation = 90
	rewardShade.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200))
	rewardShade.Parent = rewardPill
	local coin = UiKit.icon("coin", rewardPill, UDim2.fromOffset(34, 34), UDim2.new(0, -8, 0.5, 0), Vector2.new(0, 0.5))
	coin.ZIndex = 7
	local reward = PanelKit.label(rewardPill, "Text", UDim2.new(1, -36, 1, -10), UDim2.fromOffset(30, 5), 20)
	reward.ZIndex = 7
	UiKit.outline(reward, 2.5)

	-- Kostka: wymiana zadania (raz dziennie)
	local swap = Instance.new("TextButton")
	swap.Name = "Swap"
	swap.Size = UDim2.fromOffset(40, 40)
	swap.AnchorPoint = Vector2.new(0.5, 0.5)
	swap.Position = UDim2.new(1, -14, 0, 4)
	swap.Text = ""
	swap.ZIndex = 8
	swap.Parent = holder
	local swapStroke = UiKit.button(swap, Color3.fromRGB(250, 246, 236), { stroke = 3, radius = UDim.new(0, 12), gloss = true })
	swapStroke.Color = OUTLINE
	local dice = UiKit.icon("dice", swap, UDim2.fromScale(0.8, 0.8), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	dice.ZIndex = 9
	swap.MouseEnter:Connect(function()
		TweenService:Create(dice, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Rotation = 180 }):Play()
	end)
	swap.MouseLeave:Connect(function()
		TweenService:Create(dice, TweenInfo.new(0.2), { Rotation = 0 }):Play()
	end)
	swap.Activated:Connect(function()
		QuestReroll:FireServer(index)
		UiKit.shake(holder)
	end)

	cards[index] = {
		holder = holder,
		body = body,
		bodyStroke = bodyStroke,
		iconHolder = iconHolder,
		icon = icon,
		label = label,
		fill = fill,
		barText = barText,
		reward = reward,
		rewardPill = rewardPill,
		swap = swap,
		done = false,
	}
end

-- ===== Premia za komplet =====

local BONUS_Y = 26 + 3 * (CARD_H + 10)
local bonus = Instance.new("Frame")
bonus.Name = "Bonus"
bonus.Size = UDim2.new(1, -16, 0, 46)
bonus.Position = UDim2.fromOffset(8, BONUS_Y)
bonus.BackgroundColor3 = Color3.fromRGB(70, 44, 92)
bonus.ZIndex = 4
bonus.Parent = content
PanelKit.corner(bonus, UDim.new(0, 14))
PanelKit.stroke(bonus, OUTLINE, 3)
local bonusChest = UiKit.icon("chest", bonus, UDim2.fromOffset(54, 54), UDim2.new(0, -6, 0.5, -2), Vector2.new(0, 0.5))
bonusChest.ZIndex = 6
local bonusText = PanelKit.label(bonus, "Text", UDim2.new(1, -150, 1, -12), UDim2.fromOffset(56, 6), 19, PanelKit.GOLD)
bonusText.TextXAlignment = Enum.TextXAlignment.Left
bonusText.ZIndex = 6
UiKit.outline(bonusText, 2)
-- Trzy kropki: ile zadań z trzech już zrobionych
local bonusDots: { Frame } = {}
for i = 1, Progress.QUESTS_PER_DAY do
	local dot = Instance.new("Frame")
	dot.Size = UDim2.fromOffset(22, 22)
	dot.AnchorPoint = Vector2.new(1, 0.5)
	dot.Position = UDim2.new(1, -12 - (Progress.QUESTS_PER_DAY - i) * 28, 0.5, 0)
	dot.BackgroundColor3 = OUTLINE
	dot.ZIndex = 6
	dot.Parent = bonus
	PanelKit.corner(dot, UDim.new(1, 0))
	PanelKit.stroke(dot, OUTLINE, 2.5)
	bonusDots[i] = dot
end

-- ===== Seria logowań =====

local streakTitle = PanelKit.label(content, "StreakTitle", UDim2.new(1, -40, 0, 22), UDim2.fromOffset(20, BONUS_Y + 54), 19)
streakTitle.TextXAlignment = Enum.TextXAlignment.Left
UiKit.outline(streakTitle, 2)
local streakRow = Instance.new("Frame")
streakRow.BackgroundTransparency = 1
streakRow.Size = UDim2.new(1, -16, 0, 74)
streakRow.Position = UDim2.fromOffset(8, BONUS_Y + 80)
streakRow.ZIndex = 4
streakRow.Parent = content
local streakGrid = Instance.new("UIGridLayout")
streakGrid.CellSize = UDim2.new(1 / #Progress.LOGIN_REWARDS, -8, 1, 0)
streakGrid.CellPadding = UDim2.fromOffset(8, 0)
streakGrid.SortOrder = Enum.SortOrder.LayoutOrder
streakGrid.Parent = streakRow

type Day = { frame: Frame, stroke: UIStroke, day: TextLabel, amount: TextLabel, check: GuiObject, icon: GuiObject }
local days: { Day } = {}
for index = 1, #Progress.LOGIN_REWARDS do
	local frame = Instance.new("Frame")
	frame.LayoutOrder = index
	frame.BackgroundColor3 = PanelKit.TAB
	frame.ZIndex = 5
	frame.Parent = streakRow
	PanelKit.corner(frame, UDim.new(0, 12))
	local tileStroke = PanelKit.stroke(frame, OUTLINE, 3)
	local day = PanelKit.label(frame, "Day", UDim2.new(1, -6, 0, 16), UDim2.fromOffset(3, 3), 14, PanelKit.MUTED)
	day.ZIndex = 6
	local tileIcon = UiKit.icon(if index == #Progress.LOGIN_REWARDS then "luck" else "chest", frame, UDim2.fromOffset(32, 32), UDim2.new(0.5, 0, 0, 18), Vector2.new(0.5, 0))
	tileIcon.ZIndex = 6
	local amount = PanelKit.label(frame, "Amount", UDim2.new(1, -6, 0, 15), UDim2.new(0, 3, 1, -18), 13, PanelKit.GOLD)
	amount.ZIndex = 6
	UiKit.outline(amount, 1.5)
	local check = UiKit.icon("check", frame, UDim2.fromOffset(28, 28), UDim2.new(1, 4, 0, -4), Vector2.new(1, 0))
	check.ZIndex = 8
	check.Visible = false
	days[index] = { frame = frame, stroke = tileStroke, day = day, amount = amount, check = check, icon = tileIcon }
end
local streakHint = PanelKit.label(content, "StreakHint", UDim2.new(1, -40, 0, 18), UDim2.new(0, 20, 1, -20), 15, PanelKit.MUTED)

-- ===== Stan =====

local state: any = nil
local side = SideButtons.add({
	name = "QuestButton",
	icon = "scroll",
	color = Color3.fromRGB(64, 140, 220),
	caption = "QUESTS_BUTTON",
	key = Enum.KeyCode.Q,
})
local todayPulse: Tween? = nil

local function formatCoins(value: number): string
	local s = tostring(math.floor(value + 0.5))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (formatted:gsub("^ ", ""))
end

-- Krótko na kartach: 128 000 → 128K, 1 250 000 → 1.25M
local function shortCoins(value: number): string
	if value >= 1e6 then
		return (string.format("%.2fM", value / 1e6):gsub("%.?0+M$", "M"))
	elseif value >= 1e4 then
		return string.format("%dK", math.floor(value / 1000))
	end
	return formatCoins(value)
end

local function formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d:%02d", seconds // 3600, seconds // 60 % 60, seconds % 60)
end

local function refreshBadge()
	if not state then
		side.setBadge("")
		return
	end
	local done = 0
	for _, quest in state.quests do
		if quest.done then
			done += 1
		end
	end
	side.setBadge(string.format("%d/%d", done, #state.quests), if done >= #state.quests then "done" else "alert")
end

local function render()
	window.title.Text = Localize.t("QUESTS_TITLE")
	if not state then
		return
	end
	timer.Text = Localize.t("QUESTS_RESET", { formatTime(state.resetAt - os.time()) })
	window.pillText.Text = Localize.t("QUESTS_DAY", { state.streak })
	local doneCount = 0
	for index, card in cards do
		local quest = state.quests[index]
		card.holder.Visible = quest ~= nil
		if quest then
			local def = Progress.getQuest(quest.id)
			local look = (def and QUEST_LOOK[def.kind]) or DEFAULT_LOOK
			local wasDone = card.done
			card.done = quest.done
			if quest.done then
				doneCount += 1
			end
			card.body.BackgroundColor3 = if quest.done then Color3.fromRGB(72, 168, 80) else look.color
			UiKit.setIcon(card.icon, look.icon)
			card.label.Text = Localize.t("QUEST_" .. string.upper(quest.id), { quest.goal })
			card.fill.Size = UDim2.fromScale(math.clamp(quest.n / quest.goal, 0, 1), 1)
			card.fill.BackgroundColor3 = if quest.done then PanelKit.GREEN else PanelKit.GOLD
			card.barText.Text = string.format("%d/%d", quest.n, quest.goal)
			card.reward.Text = if quest.done then Localize.t("QUESTS_DONE") else shortCoins(quest.reward)
			card.rewardPill.BackgroundColor3 = if quest.done then PanelKit.GREEN else Color3.fromRGB(246, 182, 40)
			card.swap.Visible = not quest.done and not state.rerolled
			-- Właśnie ukończone przy otwartym oknie: karta podskakuje i sypią się iskry
			if quest.done and not wasDone and window.isOpen() then
				UiKit.burst(window.gui, card.rewardPill.AbsolutePosition + card.rewardPill.AbsoluteSize / 2, 14)
			end
		end
	end
	for i, dot in bonusDots do
		dot.BackgroundColor3 = if i <= doneCount then PanelKit.GREEN else OUTLINE
	end
	bonusText.Text = if state.bonusDone
		then Localize.t("QUESTS_BONUS_DONE")
		else Localize.t("QUESTS_BONUS", { shortCoins(state.dailyBonus), math.floor(Progress.DAILY_BONUS.luckSeconds / 60) })
	bonusText.TextColor3 = if state.bonusDone then PanelKit.GREEN else PanelKit.GOLD

	streakTitle.Text = Localize.t("QUESTS_STREAK", { state.streak })
	for index, day in days do
		local isToday = index == state.loginDay
		local claimed = index < state.loginDay
		day.day.Text = Localize.t("QUESTS_DAY", { index })
		day.amount.Text = shortCoins(Progress.LOGIN_REWARDS[index] * state.scale)
		day.frame.BackgroundColor3 = if isToday then PanelKit.VIOLET elseif claimed then Color3.fromRGB(60, 120, 64) else PanelKit.TAB
		day.stroke.Color = if isToday then PanelKit.GOLD else OUTLINE
		day.check.Visible = claimed or isToday
	end
	-- Dzisiejszy kafelek pulsuje obwódką
	if todayPulse then
		todayPulse:Cancel()
		todayPulse = nil
	end
	local today = days[state.loginDay]
	if today and window.isOpen() then
		today.stroke.Thickness = 3
		local tween = TweenService:Create(today.stroke, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 5 })
		tween:Play()
		todayPulse = tween
	end
	local nextDay = state.loginDay % #Progress.LOGIN_REWARDS + 1
	streakHint.Text = Localize.t("QUESTS_STREAK_HINT", { nextDay, formatCoins(Progress.LOGIN_REWARDS[nextDay] * state.scale) })
end

function QuestPanel.toggle()
	window.setOpen(not window.isOpen())
end

window.onToggle(function(open: boolean)
	if open then
		render()
	elseif todayPulse then
		todayPulse:Cancel()
		todayPulse = nil
	end
end)
side.onActivated(QuestPanel.toggle)

Remotes.get("ProgressUpdate").OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" or typeof(payload.quests) ~= "table" then
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

-- Odliczanie do nowych zadań
task.spawn(function()
	while true do
		task.wait(1)
		if window.isOpen() and state then
			timer.Text = Localize.t("QUESTS_RESET", { formatTime(state.resetAt - os.time()) })
		end
	end
end)

return QuestPanel
