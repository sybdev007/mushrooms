--!strict
-- Panel sprzedaży u skupywacza (i przy kramikach w obozowiskach).
-- Pokazuje grzyby z koszyka jako karty: kapelusz w kolorze gatunku albo mutacji, nazwa w kolorze klasy,
-- ikony mutacji i cena. Dotknięcie karty zaznacza ją, a przycisk na karcie sprzedaje tylko ją.
-- Na dole: „Zaznacz wszystko”, „Sprzedaj zaznaczone” i „Sprzedaj wszystko”.
-- Serwer dostaje indeksy z koszyka i odcisk koszyka, więc nie sprzeda innych grzybów, niż widział gracz.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Economy = require(ReplicatedStorage.Shared.Economy)
local Localize = require(script.Parent.Localize)
local UiKit = require(script.Parent.UiKit)
local UiScale = require(script.Parent.UiScale)

type Item = Economy.BasketItem

local SellPanel = {}

local TITLE_FONT = Enum.Font.FredokaOne
local BODY_FONT = Enum.Font.GothamBold
local THEME = {
	panel = Color3.fromRGB(40, 28, 20),
	stroke = Color3.fromRGB(200, 146, 74),
	text = Color3.fromRGB(252, 238, 210),
	muted = Color3.fromRGB(214, 188, 150),
	accent = Color3.fromRGB(255, 202, 92),
	card = Color3.fromRGB(64, 46, 32),
	cardSelected = Color3.fromRGB(70, 104, 54),
	sell = Color3.fromRGB(214, 150, 50),
	green = Color3.fromRGB(46, 160, 80),
	locked = Color3.fromRGB(96, 82, 70),
}
local GREETINGS = { "NPC_HELLO_1", "NPC_HELLO_2", "NPC_HELLO_3" }
local CARD_W, CARD_H = 112, 132

local basket: { Item } = {}
local basketKey = ""
local selected: { [number]: boolean } = {}
local sellCallback: ((indices: { number }?, key: string, from: Vector2?) -> ())? = nil
local greetingKey = GREETINGS[1]

local function corner(parent: Instance, radius: UDim?)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or UDim.new(0, 12)
	c.Parent = parent
end

local function label(parent: Instance, name: string, size: UDim2, position: UDim2, font: Enum.Font, maxSize: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = size
	l.Position = position
	l.BackgroundTransparency = 1
	l.TextColor3 = THEME.text
	l.Font = font
	l.TextScaled = true
	l.RichText = true
	l.Text = ""
	l.Parent = parent
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = maxSize
	constraint.Parent = l
	return l
end

local function formatCoins(value: number): string
	local s = tostring(math.floor(value + 0.5))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (formatted:gsub("^ ", ""))
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function capColor(item: Item): Color3
	local variant = Economy.getVariant(item.v)
	if variant then
		return rgb(variant.color)
	end
	local species = Economy.getSpecies(item.s)
	return rgb(species and species.cap or { 160, 120, 80 })
end

local function mutationIcons(item: Item): string
	local icons = ""
	local variant = Economy.getVariant(item.v)
	if variant then
		icons ..= variant.icon
	end
	for _, id in item.x or {} do
		local tag = Economy.getTag(id)
		if tag then
			icons ..= tag.icon
		end
	end
	return icons
end

-- ===== Budowa okna =====

local gui = Instance.new("ScreenGui")
gui.Name = "SellPanel"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 5
gui.Enabled = false
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local window = Instance.new("Frame")
window.Name = "Window"
-- Stały rozmiar, a na mniejszych ekranach całość zmniejsza UIScale (tak jak resztę HUD)
window.Size = UDim2.fromOffset(680, 470)
window.Position = UDim2.fromScale(0.5, 0.5)
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.BackgroundColor3 = THEME.panel
window.BackgroundTransparency = 0.04
window.Parent = gui
corner(window, UDim.new(0, 18))
local windowStroke = Instance.new("UIStroke")
windowStroke.Color = THEME.stroke
windowStroke.Thickness = 3
windowStroke.Parent = window
local windowScale = Instance.new("UIScale")
windowScale.Parent = window

-- Nagłówek: portret skupywacza, imię i dymek z powitaniem
local portrait = Instance.new("Frame")
portrait.Name = "Portrait"
portrait.Size = UDim2.fromOffset(64, 64)
portrait.Position = UDim2.fromOffset(14, 12)
portrait.BackgroundColor3 = Color3.fromRGB(214, 52, 44)
portrait.Parent = window
corner(portrait, UDim.new(1, 0))
local portraitStroke = Instance.new("UIStroke")
portraitStroke.Color = Color3.new(1, 1, 1)
portraitStroke.Thickness = 3
portraitStroke.Parent = portrait
local face = label(portrait, "Face", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), TITLE_FONT, 44)
face.Text = "🧔"
local npcName = label(window, "Name", UDim2.new(0, 260, 0, 26), UDim2.fromOffset(88, 12), TITLE_FONT, 24)
npcName.TextXAlignment = Enum.TextXAlignment.Left
npcName.TextColor3 = THEME.accent
local bubble = Instance.new("Frame")
bubble.Name = "Bubble"
bubble.Size = UDim2.new(1, -160, 0, 30)
bubble.Position = UDim2.fromOffset(88, 42)
bubble.BackgroundColor3 = Color3.fromRGB(252, 238, 210)
bubble.Parent = window
corner(bubble, UDim.new(0, 10))
local speech = label(bubble, "Speech", UDim2.new(1, -16, 1, -6), UDim2.fromOffset(8, 3), BODY_FONT, 16)
speech.TextColor3 = Color3.fromRGB(60, 40, 24)
speech.TextXAlignment = Enum.TextXAlignment.Left

local close = Instance.new("TextButton")
close.Name = "Close"
close.Size = UDim2.fromOffset(42, 42)
close.Position = UDim2.new(1, -12, 0, 12)
close.AnchorPoint = Vector2.new(1, 0)
close.Text = "✕"
close.Font = TITLE_FONT
close.TextScaled = true
close.TextColor3 = Color3.new(1, 1, 1)
close.Parent = window
UiKit.button(close, UiKit.COLORS.red, { stroke = 2 })

-- Lista grzybów
local list = Instance.new("ScrollingFrame")
list.Name = "List"
list.Size = UDim2.new(1, -28, 1, -164)
list.Position = UDim2.fromOffset(14, 86)
list.BackgroundColor3 = Color3.fromRGB(28, 20, 14)
list.BackgroundTransparency = 0.3
list.BorderSizePixel = 0
list.ScrollBarThickness = 6
list.ScrollBarImageColor3 = THEME.stroke
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.ScrollingDirection = Enum.ScrollingDirection.Y
list.Parent = window
corner(list, UDim.new(0, 12))
local listPadding = Instance.new("UIPadding")
listPadding.PaddingLeft = UDim.new(0, 8)
listPadding.PaddingRight = UDim.new(0, 8)
listPadding.PaddingTop = UDim.new(0, 8)
listPadding.PaddingBottom = UDim.new(0, 8)
listPadding.Parent = list
local listLayout = Instance.new("UIGridLayout")
listLayout.CellSize = UDim2.fromOffset(CARD_W, CARD_H)
listLayout.CellPadding = UDim2.fromOffset(8, 8)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = list

local empty = label(window, "Empty", UDim2.new(1, -60, 0, 40), UDim2.new(0, 30, 0.45, 0), TITLE_FONT, 22)
empty.TextColor3 = THEME.muted

-- Pasek na dole
local footer = Instance.new("Frame")
footer.Name = "Footer"
footer.Size = UDim2.new(1, -28, 0, 56)
footer.Position = UDim2.new(0, 14, 1, -68)
footer.BackgroundTransparency = 1
footer.Parent = window
local footerLayout = Instance.new("UIListLayout")
footerLayout.FillDirection = Enum.FillDirection.Horizontal
footerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
footerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
footerLayout.Padding = UDim.new(0, 10)
footerLayout.SortOrder = Enum.SortOrder.LayoutOrder
footerLayout.Parent = footer

local function footerButton(name: string, order: number, width: number, color: Color3): (TextButton, UIStroke)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.new(0, width, 1, 0)
	button.LayoutOrder = order
	button.Font = TITLE_FONT
	button.TextScaled = true
	button.RichText = true
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Parent = footer
	local stroke = UiKit.button(button, color, { stroke = 3 })
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 20
	constraint.Parent = button
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.Parent = button
	return button, stroke
end
local selectAll = footerButton("SelectAll", 1, 150, UiKit.COLORS.wood)
local sellSelected = footerButton("SellSelected", 2, 220, THEME.green)
local sellAll = footerButton("SellAll", 3, 210, THEME.sell)

-- ===== Karty =====

type Card = { button: TextButton, check: TextLabel, stroke: UIStroke }
local cards: { Card } = {}

local function selectedIndices(): { number }
	local result = {}
	for index in selected do
		if basket[index] then
			table.insert(result, index)
		end
	end
	table.sort(result)
	return result
end

local function centerOf(object: GuiObject): Vector2
	return object.AbsolutePosition + object.AbsoluteSize / 2
end

local function requestSell(indices: { number }?, from: GuiObject)
	local callback = sellCallback
	if callback and #basket > 0 then
		callback(indices, basketKey, centerOf(from))
	end
end

local function refreshFooter()
	local indices = selectedIndices()
	local selectedValue = 0
	for _, index in indices do
		selectedValue += Economy.itemValue(basket[index])
	end
	local allSelected = #indices == #basket and #basket > 0
	selectAll.Text = Localize.t(if allSelected then "SELL_UNSELECT_ALL" else "SELL_SELECT_ALL")
	sellSelected.Text = Localize.t("SELL_SELECTED", { #indices }) .. "  💰" .. formatCoins(selectedValue)
	sellAll.Text = Localize.t("SELL_ALL") .. "  💰" .. formatCoins(Economy.basketValue(basket))
	local canSelected = #indices > 0
	sellSelected.Active = canSelected
	UiKit.recolor(sellSelected, if canSelected then THEME.green else THEME.locked)
	sellAll.Active = #basket > 0
	UiKit.recolor(sellAll, if #basket > 0 then THEME.sell else THEME.locked)
	for index, card in cards do
		local on = selected[index] == true
		card.check.Text = if on then "✓" else ""
		card.check.BackgroundColor3 = if on then THEME.green else Color3.fromRGB(30, 22, 16)
		card.button.BackgroundColor3 = if on then THEME.cardSelected else THEME.card
		local classColor = card.stroke:GetAttribute("ClassColor")
		card.stroke.Color = if on
			then Color3.fromRGB(160, 230, 120)
			elseif typeof(classColor) == "Color3" then classColor
			else THEME.stroke
	end
end

local function buildCard(index: number, item: Item): Card
	local button = Instance.new("TextButton")
	button.Name = "Card" .. index
	button.Text = ""
	button.LayoutOrder = index
	button.AutoButtonColor = false
	button.BackgroundColor3 = THEME.card
	button.Parent = list
	corner(button, UDim.new(0, 12))
	local class = Economy.speciesClass(item.s)
	local classColor = rgb(class.color)
	local stroke = Instance.new("UIStroke")
	stroke.Color = classColor
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke:SetAttribute("ClassColor", classColor)
	stroke.Parent = button

	-- Mały grzybek z ramek: kapelusz (półkole) i trzon
	local art = Instance.new("Frame")
	art.Name = "Art"
	art.Size = UDim2.fromOffset(56, 44)
	art.Position = UDim2.new(0.5, 0, 0, 8)
	art.AnchorPoint = Vector2.new(0.5, 0)
	art.BackgroundTransparency = 1
	art.Parent = button
	local stem = Instance.new("Frame")
	stem.Size = UDim2.fromOffset(16, 22)
	stem.Position = UDim2.new(0.5, 0, 1, 0)
	stem.AnchorPoint = Vector2.new(0.5, 1)
	stem.BackgroundColor3 = Color3.fromRGB(236, 226, 206)
	stem.Parent = art
	corner(stem, UDim.new(0, 6))
	local cap = Instance.new("Frame")
	cap.Size = UDim2.fromOffset(52, 28)
	cap.Position = UDim2.fromScale(0.5, 0)
	cap.AnchorPoint = Vector2.new(0.5, 0)
	cap.BackgroundColor3 = capColor(item)
	cap.Parent = art
	corner(cap, UDim.new(0.5, 0))
	local capStroke = Instance.new("UIStroke")
	capStroke.Color = Color3.fromRGB(30, 20, 12)
	capStroke.Thickness = 1.5
	capStroke.Parent = cap
	if Economy.variantRank(item.v) >= 2 then
		-- Złote i tęczowe kapelusze lśnią
		local shine = Instance.new("UIGradient")
		shine.Color = ColorSequence.new(Color3.new(1, 1, 1), capColor(item))
		shine.Rotation = 45
		shine.Parent = cap
	end

	local icons = mutationIcons(item)
	local mutation = label(button, "Mutation", UDim2.fromOffset(60, 18), UDim2.fromOffset(6, 4), TITLE_FONT, 16)
	mutation.TextXAlignment = Enum.TextXAlignment.Left
	mutation.Text = icons

	local species = Economy.getSpecies(item.s)
	local name = label(button, "Name", UDim2.new(1, -8, 0, 18), UDim2.new(0, 4, 0, 56), TITLE_FONT, 15)
	name.Text = if species then Localize.t(species.key) else "?"
	local classLabel = label(button, "Class", UDim2.new(1, -8, 0, 13), UDim2.new(0, 4, 0, 74), BODY_FONT, 12)
	classLabel.Text = Localize.t(class.key)
	classLabel.TextColor3 = classColor
	local price = label(button, "Price", UDim2.new(1, -8, 0, 16), UDim2.new(0, 4, 0, 88), TITLE_FONT, 15)
	price.Text = "💰 " .. formatCoins(Economy.itemValue(item))
	price.TextColor3 = THEME.accent

	-- Przycisk sprzedaży tylko tej karty
	local sellOne = Instance.new("TextButton")
	sellOne.Name = "SellOne"
	sellOne.Size = UDim2.new(1, -16, 0, 22)
	sellOne.Position = UDim2.new(0.5, 0, 1, -6)
	sellOne.AnchorPoint = Vector2.new(0.5, 1)
	sellOne.Font = TITLE_FONT
	sellOne.TextScaled = true
	sellOne.TextColor3 = Color3.new(1, 1, 1)
	sellOne.Text = Localize.t("SELL_ONE")
	sellOne.Parent = button
	UiKit.button(sellOne, THEME.sell, { stroke = 2 })
	local sellConstraint = Instance.new("UITextSizeConstraint")
	sellConstraint.MaxTextSize = 14
	sellConstraint.Parent = sellOne

	-- Kółko zaznaczenia w prawym górnym rogu
	local check = label(button, "Check", UDim2.fromOffset(22, 22), UDim2.new(1, -26, 0, 4), TITLE_FONT, 16)
	check.BackgroundTransparency = 0
	check.BackgroundColor3 = Color3.fromRGB(30, 22, 16)
	corner(check, UDim.new(1, 0))
	local checkStroke = Instance.new("UIStroke")
	checkStroke.Color = Color3.fromRGB(200, 200, 200)
	checkStroke.Thickness = 1.5
	checkStroke.Parent = check

	button.Activated:Connect(function()
		selected[index] = if selected[index] then nil else true
		local scale = button:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		scale.Parent = button
		scale.Scale = 0.94
		TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		refreshFooter()
	end)
	sellOne.Activated:Connect(function()
		requestSell({ index }, sellOne)
	end)
	return { button = button, check = check, stroke = stroke }
end

local function rebuild()
	for _, card in cards do
		card.button:Destroy()
	end
	table.clear(cards)
	for index, item in basket do
		cards[index] = buildCard(index, item)
	end
	empty.Visible = #basket == 0
	empty.Text = Localize.t("SELL_EMPTY")
	refreshFooter()
end

local function refreshTexts()
	npcName.Text = Localize.t("NPC_NAME")
	speech.Text = Localize.t(if #basket == 0 then "NPC_EMPTY" else greetingKey)
	rebuild()
end

-- ===== Przyciski =====

selectAll.Activated:Connect(function()
	local all = #selectedIndices() == #basket
	table.clear(selected)
	if not all then
		for index in basket do
			selected[index] = true
		end
	end
	refreshFooter()
end)
sellSelected.Activated:Connect(function()
	local indices = selectedIndices()
	if #indices > 0 then
		requestSell(indices, sellSelected)
	end
end)
sellAll.Activated:Connect(function()
	requestSell(nil, sellAll)
end)
close.Activated:Connect(function()
	SellPanel.close()
end)

-- ===== API =====

function SellPanel.onSell(callback: (indices: { number }?, key: string, from: Vector2?) -> ())
	sellCallback = callback
end

-- Nowa zawartość koszyka od serwera (tylko po zmianie)
function SellPanel.setBasket(items: { Item }, key: string)
	basket = items
	basketKey = key
	table.clear(selected)
	if gui.Enabled then
		speech.Text = Localize.t(if #basket == 0 then "NPC_EMPTY" else greetingKey)
		rebuild()
	end
end

function SellPanel.isOpen(): boolean
	return gui.Enabled
end

function SellPanel.open()
	if gui.Enabled then
		return
	end
	greetingKey = GREETINGS[math.random(1, #GREETINGS)]
	table.clear(selected)
	gui.Enabled = true
	refreshTexts()
	local base = UiScale.get()
	windowScale.Scale = base * 0.9
	TweenService:Create(windowScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = base }):Play()
end

function SellPanel.close()
	gui.Enabled = false
end

Localize.onChanged(function()
	if gui.Enabled then
		refreshTexts()
	end
end)
UiScale.onChanged(function()
	windowScale.Scale = UiScale.get()
end)

return SellPanel
