--!strict
-- Okno Tytuły (PanelKit, jak okno ulepszeń): wszystkie tytuły od zwykłych do mitycznych.
-- Zdobyte można założyć jednym kliknięciem, zablokowane pokazują, co zrobić, i pasek postępu.
-- U góry podgląd tytułu nad głową oraz przyciski „Auto (najlepszy)” i „Bez tytułu”.
-- Stan przychodzi z ProgressUpdate (Grzybopedia, Strażnicy, liczniki, wybór); warunki liczy Shared/Titles.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Titles = require(Shared.Titles)
local ProgressFeed = require(script.Parent.ProgressFeed)
local Localize = require(script.Parent.Localize)
local PanelKit = require(script.Parent.PanelKit)
local ShopLook = require(script.Parent.ShopLook)
local SideButtons = require(script.Parent.SideButtons)
local UiKit = require(script.Parent.UiKit)

local TitlePanel = {}

local OUTLINE = PanelKit.OUTLINE
local WIDTH, HEIGHT = 700, 510
local COLUMNS = 3
local CARD_H = 128
local SelectTitle = Remotes.get("SelectTitle")

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 110, 110)),
	ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 90)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(120, 240, 130)),
	ColorSequenceKeypoint.new(0.75, Color3.fromRGB(100, 200, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(230, 120, 255)),
})

local function rarityColor(rarity: string): Color3
	local c = Titles.RARITY_COLOR[rarity] or { 255, 255, 255 }
	return Color3.fromRGB(c[1], c[2], c[3])
end

local window = PanelKit.window({
	name = "Titles",
	parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	width = WIDTH,
	height = HEIGHT,
	ribbon = Color3.fromRGB(214, 84, 170),
	icon = "star",
	pillIcon = "check",
	pillColor = Color3.fromRGB(52, 38, 30),
})
local content = window.content

-- ===== Podgląd i przyciski u góry =====

local preview = Instance.new("Frame")
preview.Name = "Preview"
preview.Size = UDim2.new(1, -16, 0, 64)
preview.Position = UDim2.fromOffset(8, 4)
preview.BackgroundColor3 = PanelKit.BG_DARK
preview.ZIndex = 4
preview.Parent = content
PanelKit.corner(preview, UDim.new(0, 16))
PanelKit.stroke(preview, OUTLINE, 3)
ShopLook.shade(preview, Color3.fromRGB(170, 160, 152))
local previewHint = PanelKit.label(preview, "Hint", UDim2.new(1, -330, 0, 18), UDim2.fromOffset(16, 6), 14, PanelKit.MUTED, PanelKit.BODY_FONT)
previewHint.TextXAlignment = Enum.TextXAlignment.Left
previewHint.ZIndex = 5
local previewName = PanelKit.label(preview, "Name", UDim2.new(1, -330, 0, 32), UDim2.fromOffset(16, 26), 28)
previewName.TextXAlignment = Enum.TextXAlignment.Left
previewName.ZIndex = 5
UiKit.outline(previewName, 2.5)
local previewGradient = Instance.new("UIGradient")
previewGradient.Color = RAINBOW
previewGradient.Enabled = false
previewGradient.Parent = previewName

local function smallButton(name: string, color: Color3, x: number): (TextButton, UIStroke)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.fromOffset(150, 44)
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, x, 0.5, 0)
	button.Font = PanelKit.TITLE_FONT
	button.TextScaled = true
	button.TextColor3 = Color3.new(1, 1, 1)
	button.ZIndex = 6
	button.Parent = preview
	local buttonStroke = UiKit.button(button, color, { stroke = 3, radius = UDim.new(0, 12), gloss = true })
	buttonStroke.Color = OUTLINE
	ShopLook.button(button, if x < -100 then 3.2 else 3.9)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 18
	constraint.Parent = button
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = button
	return button, buttonStroke
end
local AUTO_ON = Color3.fromRGB(140, 86, 236)
local AUTO_OFF = Color3.fromRGB(96, 70, 52)
local autoButton = smallButton("Auto", AUTO_OFF, -170)
local noneButton = smallButton("None", AUTO_OFF, -12)

local hint = PanelKit.label(content, "Hint", UDim2.new(1, -20, 0, 18), UDim2.fromOffset(10, 74), 15, PanelKit.MUTED, PanelKit.BODY_FONT)

-- ===== Siatka tytułów =====

local list = Instance.new("ScrollingFrame")
list.Name = "List"
list.Size = UDim2.new(1, 0, 1, -100)
list.Position = UDim2.fromOffset(0, 98)
list.BackgroundColor3 = PanelKit.BG_DARK
list.BackgroundTransparency = 0.25
list.BorderSizePixel = 0
list.ScrollBarThickness = 8
list.ScrollBarImageColor3 = PanelKit.LINE
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.ZIndex = 4
list.Parent = content
PanelKit.corner(list, UDim.new(0, 16))
PanelKit.stroke(list, OUTLINE, 3)
local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.new(1 / COLUMNS, -10, 0, CARD_H)
grid.CellPadding = UDim2.fromOffset(10, 10)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = list
local listPad = Instance.new("UIPadding")
listPad.PaddingTop = UDim.new(0, 10)
listPad.PaddingBottom = UDim.new(0, 10)
listPad.PaddingLeft = UDim.new(0, 10)
listPad.PaddingRight = UDim.new(0, 6)
listPad.Parent = list

type Card = {
	def: Titles.TitleDef,
	frame: Frame,
	frameStroke: UIStroke,
	chip: TextLabel,
	name: TextLabel,
	how: TextLabel,
	bar: Frame,
	fill: Frame,
	barText: TextLabel,
	lock: GuiObject,
	equip: TextButton,
	halo: Frame,
}
local cards: { Card } = {}

for order, def in Titles.LIST do
	local color = rarityColor(def.rarity)
	local frame = Instance.new("Frame")
	frame.Name = def.id
	frame.LayoutOrder = order
	frame.BackgroundColor3 = PanelKit.CARD
	frame.ZIndex = 5
	frame.ClipsDescendants = true -- promienie zostają w karcie (jak w sklepie)
	frame.Parent = list
	PanelKit.corner(frame, UDim.new(0, 14))
	local frameStroke = PanelKit.stroke(frame, OUTLINE, 3)
	ShopLook.shade(frame, Color3.fromRGB(170, 160, 150))
	-- Promienie w kolorze rzadkości za nazwą (tylko zdobyte tytuły, render włącza)
	local halo = ShopLook.halo(frame, UDim2.new(0.5, 0, 0, 43), color, 120, def.rarity == "legendary" or def.rarity == "mythic", 5)
	halo.Visible = false
	if def.rarity == "mythic" then
		local g = Instance.new("UIGradient")
		g.Color = RAINBOW
		g.Rotation = 30
		g.Parent = frameStroke
	end

	-- Kolorowy pasek rzadkości u góry karty
	local chip = PanelKit.label(frame, "Rarity", UDim2.new(1, -16, 0, 20), UDim2.fromOffset(8, 6), 14, Color3.new(1, 1, 1))
	chip.BackgroundTransparency = 0
	chip.BackgroundColor3 = UiKit.darker(color, 0.25)
	chip.ZIndex = 6
	PanelKit.corner(chip, UDim.new(1, 0))
	UiKit.outline(chip, 1.5)

	local name = PanelKit.label(frame, "Name", UDim2.new(1, -16, 0, 26), UDim2.fromOffset(8, 30), 21, color)
	name.ZIndex = 6
	UiKit.outline(name, 2.5)
	if def.rarity == "mythic" then
		local g = Instance.new("UIGradient")
		g.Color = RAINBOW
		g.Parent = name
		name.TextColor3 = Color3.new(1, 1, 1)
	else
		-- Gradient jak tytuły kart sklepu, w kolorze rzadkości (jaśniej u góry)
		ShopLook.title(name, color:Lerp(Color3.new(1, 1, 1), 0.55), color)
	end
	local how = PanelKit.label(frame, "How", UDim2.new(1, -16, 0, 28), UDim2.fromOffset(8, 56), 13, PanelKit.MUTED, PanelKit.BODY_FONT)
	how.ZIndex = 6

	local bar, fill, barText = PanelKit.bar(frame, UDim2.new(1, -54, 0, 26), UDim2.new(0, 42, 1, -34), PanelKit.GOLD)
	local lock = UiKit.icon("lock", frame, UDim2.fromOffset(30, 30), UDim2.new(0, 8, 1, -36), Vector2.zero)
	lock.ZIndex = 7

	local equip = Instance.new("TextButton")
	equip.Name = "Equip"
	equip.Size = UDim2.new(1, -16, 0, 30)
	equip.Position = UDim2.new(0, 8, 1, -36)
	equip.Font = PanelKit.TITLE_FONT
	equip.TextScaled = true
	equip.TextColor3 = Color3.new(1, 1, 1)
	equip.ZIndex = 7
	equip.Parent = frame
	local equipStroke = UiKit.button(equip, UiKit.COLORS.green, { stroke = 2.5, radius = UDim.new(0, 10), gloss = true })
	equipStroke.Color = OUTLINE
	ShopLook.button(equip, 3 + (order % 5) * 0.45)
	ShopLook.hover(frame)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 17
	constraint.Parent = equip
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = equip

	cards[order] = {
		def = def,
		frame = frame,
		frameStroke = frameStroke,
		chip = chip,
		name = name,
		how = how,
		bar = bar,
		fill = fill,
		barText = barText,
		lock = lock,
		equip = equip,
		halo = halo,
	}
end

-- ===== Stan =====

local state: any = nil
local seen: { [string]: boolean }? = nil -- zdobyte przy ostatnim otwarciu (plakietka NOWE)
local side = SideButtons.add({
	name = "TitleButton",
	icon = "star",
	color = Color3.fromRGB(214, 84, 170),
	caption = "TITLES_BUTTON",
	key = Enum.KeyCode.T,
})

local function context(): Titles.Context?
	if not state then
		return nil
	end
	local stats = Titles.emptyStats()
	if typeof(state.stats) == "table" then
		for key, value in state.stats do
			if typeof(value) == "number" then
				(stats :: any)[key] = value
			end
		end
	end
	return {
		atlas = if typeof(state.atlas) == "table" then state.atlas else {},
		bestiary = if typeof(state.bestiary) == "table" then state.bestiary else {},
		stats = stats,
		tutorialDone = state.tutorialDone == true,
		-- Tylko do okna (pokazać tytuły twórców); wybór i tak sprawdza serwer
		dev = Titles.isDev(Players.LocalPlayer.UserId),
	}
end

local function choice(): string
	return if state and typeof(state.titleChoice) == "string" then state.titleChoice else ""
end

-- Tytuły z eventu widać tylko w czasie eventu (atrybut serwera) albo gdy są już zdobyte
local EVENT_ATTRIBUTE: { [string]: string } = { halloween = "Halloween", winter = "Winter" }
local function eventActive(event: string): boolean
	local attribute = EVENT_ATTRIBUTE[event]
	return attribute ~= nil and Workspace:GetAttribute(attribute) == true
end

local function visible(def: Titles.TitleDef, earned: { [string]: boolean }): boolean
	-- Tytuły twórców gry (special "dev") widzą tylko ci, którzy je mają
	if def.special == "dev" then
		return earned[def.id] == true
	end
	return earned[def.id] == true or def.event == nil or eventActive(def.event)
end

-- Ile tytułów pokazujemy (bez tytułów z eventów, które nie trwają i nie są zdobyte)
local function visibleTotal(earned: { [string]: boolean }): number
	local total = 0
	for _, def in Titles.LIST do
		if visible(def, earned) then
			total += 1
		end
	end
	return total
end

local function refreshBadge(earned: { [string]: boolean })
	local count = 0
	local fresh = false
	for id in earned do
		count += 1
		if seen and not seen[id] then
			fresh = true
		end
	end
	if fresh then
		side.setBadge(Localize.t("BADGE_NEW"), "alert")
	else
		side.setBadge(string.format("%d/%d", count, visibleTotal(earned)), "info")
	end
end

local function chooseTitle(id: string)
	if not state then
		return
	end
	state.titleChoice = id
	SelectTitle:FireServer(id)
end

local function render()
	window.title.Text = Localize.t("TITLES_TITLE")
	hint.Text = Localize.t("TITLES_HINT")
	autoButton.Text = Localize.t("TITLES_AUTO")
	noneButton.Text = Localize.t("TITLES_NONE")
	local ctx = context()
	if not ctx then
		return
	end
	local earned = Titles.earned(ctx)
	local current = Titles.resolve(choice(), earned)
	local chosen = choice()
	local count = 0
	for _ in earned do
		count += 1
	end
	window.pillText.Text = string.format("%d/%d", count, visibleTotal(earned))

	-- Podgląd: tak jak nad głową
	previewHint.Text = Localize.t("TITLES_EQUIPPED")
	local currentDef = Titles.get(current)
	previewName.Text = if currentDef then Localize.t(current) else "—"
	previewName.TextColor3 = if currentDef then rarityColor(currentDef.rarity) else PanelKit.MUTED
	previewGradient.Enabled = currentDef ~= nil and currentDef.rarity == "mythic"
	UiKit.recolor(autoButton, if chosen == "" then AUTO_ON else AUTO_OFF)
	UiKit.recolor(noneButton, if chosen == Titles.NONE then AUTO_ON else AUTO_OFF)

	-- Tytuły z eventu: przed i po evencie widać tylko zdobyte (niezdobytych nie da się wtedy zdobyć)
	for _, card in cards do
		local def = card.def
		local has = earned[def.id] == true
		local equipped = has and def.id == current
		card.frame.Visible = visible(def, earned)
		card.chip.Text = Localize.t("RARITY_" .. string.upper(def.rarity))
		card.name.Text = Localize.t(def.id)
		local n, goal = Titles.progress(def, ctx)
		-- Duże cele (Ofiara dla Leszego: 100 000 000) ze spacjami, żeby dało się je przeczytać
		local goalText: any = if goal >= 10000
			then (string.format("%.0f", goal):reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", ""))
			else goal
		card.how.Text = Localize.t(def.id .. "_HOW", { goalText })
		card.frame.BackgroundColor3 = if equipped then Color3.fromRGB(70, 118, 60) elseif has then PanelKit.CARD else Color3.fromRGB(64, 44, 31)
		if def.rarity ~= "mythic" then
			card.frameStroke.Color = if equipped then PanelKit.GOLD elseif has then rarityColor(def.rarity) else OUTLINE
		end
		card.name.TextTransparency = if has then 0 else 0.35
		card.halo.Visible = has
		card.bar.Visible = not has
		card.lock.Visible = not has
		card.equip.Visible = has
		if not has then
			card.fill.Size = UDim2.fromScale(if goal > 0 then math.clamp(n / goal, 0, 1) else 0, 1)
			card.barText.Text = string.format("%d/%d", n, goal)
		else
			card.equip.Text = if equipped then "✔ " .. Localize.t("TITLES_EQUIPPED") else Localize.t("TITLES_EQUIP")
			UiKit.recolor(card.equip, if equipped then Color3.fromRGB(236, 168, 32) else UiKit.COLORS.green)
			card.equip.Active = not equipped
		end
	end
	refreshBadge(earned)
end

for _, card in cards do
	card.equip.Activated:Connect(function()
		if not state then
			return
		end
		chooseTitle(card.def.id)
		render()
		UiKit.burst(window.gui, card.equip.AbsolutePosition + card.equip.AbsoluteSize / 2, 12)
		local scale = card.frame:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		scale.Parent = card.frame
		scale.Scale = 1.08
		TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end)
end
autoButton.Activated:Connect(function()
	chooseTitle("")
	render()
end)
noneButton.Activated:Connect(function()
	chooseTitle(Titles.NONE)
	render()
end)

function TitlePanel.toggle()
	window.setOpen(not window.isOpen())
end

window.onToggle(function(open: boolean)
	if open then
		-- Otwarcie = gracz widział wszystkie zdobyte (plakietka NOWE znika)
		local ctx = context()
		if ctx then
			seen = Titles.earned(ctx)
		end
		render()
		-- Pierwsze karty wskakują po kolei (jak w sklepie); reszta listy od razu
		ShopLook.openSound()
		local shown: { GuiObject } = {}
		for _, card in cards do
			if card.frame.Visible and #shown < 12 then
				table.insert(shown, card.frame)
			end
		end
		ShopLook.cascade(shown, 0.035)
	end
end)
side.onActivated(TitlePanel.toggle)

ProgressFeed.subscribe(function(payload)
	if typeof(payload) ~= "table" or typeof(payload.atlas) ~= "table" then
		return
	end
	state = payload
	local ctx = context() :: Titles.Context
	local earned = Titles.earned(ctx)
	-- Pierwsza paczka po wejściu: wszystko, co już było, nie jest „nowe”
	if not seen then
		seen = earned
	end
	if window.isOpen() then
		seen = earned
		render()
	else
		refreshBadge(earned)
	end
end)

Localize.onChanged(function()
	if window.isOpen() then
		render()
	end
end)

return TitlePanel
