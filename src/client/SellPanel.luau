--!strict
-- Panel sprzedaży u skupywacza (i przy kramikach w obozowiskach).
-- Pokazuje grzyby z koszyka jako karty: kapelusz w kolorze gatunku albo mutacji, nazwa w kolorze klasy,
-- ikony mutacji i cena. Dotknięcie karty zaznacza ją, a przycisk na karcie sprzedaje tylko ją.
-- Na dole: „Zaznacz wszystko”, „Sprzedaj zaznaczone” i „Sprzedaj wszystko”.
-- Serwer dostaje indeksy z koszyka i odcisk koszyka, więc nie sprzeda innych grzybów, niż widział gracz.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Economy = require(ReplicatedStorage.Shared.Economy)
local Localize = require(script.Parent.Localize)
local MerchantLook = require(script.Parent.MerchantLook)
local MushroomArt = require(script.Parent.MushroomArt)
local UiKit = require(script.Parent.UiKit)
local UiScale = require(script.Parent.UiScale)

type Item = Economy.BasketItem

local SellPanel = {}

local TITLE_FONT = Enum.Font.FredokaOne
local BODY_FONT = Enum.Font.GothamBold
local OUTLINE = UiKit.OUTLINE
local THEME = {
	cream = Color3.fromRGB(255, 248, 234),
	creamLine = Color3.fromRGB(232, 214, 182),
	well = Color3.fromRGB(240, 228, 204),
	brown = Color3.fromRGB(110, 66, 34),
	cap = Color3.fromRGB(214, 52, 44),
	green = Color3.fromRGB(54, 190, 92),
	gold = Color3.fromRGB(246, 170, 40),
	locked = Color3.fromRGB(170, 156, 140),
	selected = Color3.fromRGB(150, 255, 110),
}
local GREETINGS = { "NPC_HELLO_1", "NPC_HELLO_2", "NPC_HELLO_3" }
local CARD_W, CARD_H = 120, 156
local WINDOW_W, WINDOW_H = 700, 500

local basket: { Item } = {}
local basketKey = ""
local selected: { [number]: boolean } = {}
local sellCallback: ((indices: { number }?, key: string, from: Vector2?) -> ())? = nil
local greetingKey = GREETINGS[1]
-- Samouczek: "one" = sprzedaj 1 grzyb jego ceną, "two" = zaznacz 2 i sprzedaj zaznaczone, "all" = sprzedaj wszystko.
-- Wtedy działa tylko to, co wskazuje strzałka (serwer i tak pilnuje tego samego).
local guide: string? = nil
local GUIDE_STEP = { one = 1, two = 2, all = 3 }

local function corner(parent: Instance, radius: UDim?)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or UDim.new(0, 12)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number): UIStroke
	local st = Instance.new("UIStroke")
	st.Color = color
	st.Thickness = thickness
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Parent = parent
	return st
end

local function shade(parent: Instance, bottom: number?)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	local b = bottom or 196
	g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(b, b, b))
	g.Parent = parent
end

local function label(parent: Instance, name: string, size: UDim2, position: UDim2, font: Enum.Font, maxSize: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = size
	l.Position = position
	l.BackgroundTransparency = 1
	l.TextColor3 = Color3.new(1, 1, 1)
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

-- Przyciemnienie za oknem; kliknięcie obok zamyka panel
local dim = Instance.new("TextButton")
dim.Name = "Dim"
dim.Size = UDim2.fromScale(1, 1)
dim.Text = ""
dim.AutoButtonColor = false
dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 0.5
dim.Parent = gui

local window = Instance.new("Frame")
window.Name = "Window"
-- Stały rozmiar, a na mniejszych ekranach całość zmniejsza UIScale (tak jak resztę HUD)
window.Size = UDim2.fromOffset(WINDOW_W, WINDOW_H)
window.Position = UDim2.fromScale(0.5, 0.53)
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.BackgroundColor3 = THEME.cream
window.Parent = gui
corner(window, UDim.new(0, 26))
stroke(window, OUTLINE, 4)
local windowScale = Instance.new("UIScale")
windowScale.Parent = window
local inner = Instance.new("Frame")
inner.Name = "Inner"
inner.Size = UDim2.new(1, -14, 1, -14)
inner.Position = UDim2.fromOffset(7, 7)
inner.BackgroundTransparency = 1
inner.Parent = window
corner(inner, UDim.new(0, 21))
stroke(inner, THEME.creamLine, 2)

-- Wstążka „Skup grzybów” w kolorze kapelusza muchomora, z białymi kropkami
local ribbon = Instance.new("Frame")
ribbon.Name = "Ribbon"
ribbon.Size = UDim2.fromOffset(270, 56)
ribbon.AnchorPoint = Vector2.new(0.5, 0.5)
ribbon.Position = UDim2.new(0.5, 0, 0, 0)
ribbon.BackgroundColor3 = THEME.cap
ribbon.ZIndex = 5
ribbon.Parent = window
corner(ribbon, UDim.new(0, 16))
stroke(ribbon, OUTLINE, 3.5)
shade(ribbon)
for i, spot in { { 0.08, 0.3, 10 }, { 0.92, 0.65, 12 }, { 0.84, 0.22, 7 }, { 0.16, 0.75, 7 } } do
	local dot = Instance.new("Frame")
	dot.Name = "Dot" .. i
	dot.Size = UDim2.fromOffset(spot[3], spot[3])
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(spot[1], spot[2])
	dot.BackgroundColor3 = Color3.new(1, 1, 1)
	dot.BackgroundTransparency = 0.15
	dot.ZIndex = 6
	dot.Parent = ribbon
	corner(dot, UDim.new(1, 0))
end
local roleTitle = label(ribbon, "Title", UDim2.new(1, -40, 1, -12), UDim2.fromOffset(20, 6), TITLE_FONT, 32)
roleTitle.ZIndex = 7
UiKit.outline(roleTitle, 3)

-- Nagłówek: portret skupywacza wystający nad okno, imię i dymek z powitaniem
local portrait = Instance.new("Frame")
portrait.Name = "Portrait"
portrait.Size = UDim2.fromOffset(84, 84)
portrait.Position = UDim2.fromOffset(18, -20)
portrait.BackgroundColor3 = THEME.cap
portrait.ZIndex = 5
portrait.Parent = window
corner(portrait, UDim.new(1, 0))
stroke(portrait, OUTLINE, 4)
shade(portrait, 170)
-- Twarz: prawdziwy Pan Borowik (kopia modelu z ReplicatedStorage.NpcPortraits w ViewportFrame),
-- na Halloween Duch. Emoji tylko na zapas, dopóki model nie dotrze.
local faceHolder = Instance.new("Frame")
faceHolder.Name = "FaceHolder"
faceHolder.BackgroundTransparency = 1
faceHolder.Size = UDim2.fromScale(1, 1)
faceHolder.ZIndex = 6
faceHolder.Parent = portrait
local faceScale = Instance.new("UIScale")
faceScale.Parent = faceHolder
local face = label(faceHolder, "Face", UDim2.fromScale(0.8, 0.8), UDim2.fromScale(0.1, 0.12), TITLE_FONT, 60)
face.Text = "🧔"
face.ZIndex = 6
local faceView = Instance.new("ViewportFrame")
faceView.Name = "FaceView"
faceView.Size = UDim2.fromScale(1, 1)
faceView.BackgroundTransparency = 1
faceView.Ambient = Color3.fromRGB(170, 160, 150)
faceView.LightColor = Color3.fromRGB(255, 240, 220)
faceView.LightDirection = Vector3.new(-0.35, -0.6, 1) -- światło od strony patrzącego (przód modelu to -Z)
faceView.ZIndex = 7
faceView.Parent = faceHolder
corner(faceView, UDim.new(1, 0))
local faceCamera = Instance.new("Camera")
faceCamera.FieldOfView = 30
faceCamera.Parent = faceView
faceView.CurrentCamera = faceCamera
local portraitGhost: boolean? = nil -- jaki portret teraz wisi (nil = jeszcze żaden)

local function refreshPortrait()
	local ghost = MerchantLook.isGhost()
	if portraitGhost == ghost then
		return
	end
	local folder = ReplicatedStorage:FindFirstChild("NpcPortraits")
	local source = folder and folder:FindFirstChild("Merchant")
	if not (source and source:IsA("Model")) then
		return
	end
	faceView:ClearAllChildren()
	faceCamera = Instance.new("Camera")
	faceCamera.FieldOfView = 30
	faceCamera.Parent = faceView
	faceView.CurrentCamera = faceCamera
	local model = source:Clone()
	if ghost then
		MerchantLook.setGhost(model, true, {}, true)
	end
	model.Parent = faceView
	local head = model:FindFirstChild("Head")
	local at = if head and head:IsA("BasePart") then head.Position else Vector3.new(0, 5.25, 0)
	-- Z przodu (przód modelu to -Z), trochę z boku i z góry; w kadrze kapelusz i broda
	local target = at + Vector3.new(0, 0.35, 0)
	faceCamera.CFrame = CFrame.lookAt(target + Vector3.new(1.1, 0.45, -6.2), target)
	-- Tło w kontraście do postaci: nocny granat dla niebieskiego ducha, ciepłe złoto dla zwykłego Pana Borowika
	portrait.BackgroundColor3 = if ghost then Color3.fromRGB(44, 60, 98) else Color3.fromRGB(255, 205, 120)
	face.Visible = false
	portraitGhost = ghost
end
local npcName = label(window, "Name", UDim2.new(0, 260, 0, 28), UDim2.fromOffset(112, 38), TITLE_FONT, 26)
npcName.TextXAlignment = Enum.TextXAlignment.Left
npcName.TextColor3 = THEME.brown
local bubble = Instance.new("Frame")
bubble.Name = "Bubble"
bubble.Size = UDim2.new(1, -200, 0, 36)
bubble.Position = UDim2.fromOffset(112, 70)
bubble.BackgroundColor3 = Color3.new(1, 1, 1)
bubble.Parent = window
corner(bubble, UDim.new(0, 12))
stroke(bubble, OUTLINE, 2.5)
bubble.ZIndex = 2
-- Ogonek dymka pod dymkiem (biały środek dymka zakrywa jego połowę)
local tail = Instance.new("Frame")
tail.Name = "Tail"
tail.Size = UDim2.fromOffset(14, 14)
tail.AnchorPoint = Vector2.new(0.5, 0.5)
tail.Position = UDim2.fromOffset(113, 88)
tail.Rotation = 45
tail.BackgroundColor3 = Color3.new(1, 1, 1)
tail.ZIndex = 1
tail.Parent = window
stroke(tail, OUTLINE, 2.5)
local speech = label(bubble, "Speech", UDim2.new(1, -20, 1, -8), UDim2.fromOffset(10, 4), BODY_FONT, 17)
speech.TextColor3 = Color3.fromRGB(60, 40, 24)
speech.TextXAlignment = Enum.TextXAlignment.Left
speech.ZIndex = 3

local close = Instance.new("TextButton")
close.Name = "Close"
close.Size = UDim2.fromOffset(52, 52)
close.AnchorPoint = Vector2.new(0.5, 0.5)
close.Position = UDim2.new(1, -12, 0, 6)
close.Text = ""
close.ZIndex = 5
close.Parent = window
local closeStroke = UiKit.button(close, UiKit.COLORS.red, { stroke = 3, radius = UDim.new(0, 14), gloss = true })
closeStroke.Color = OUTLINE
-- Ikona z arkusza (znaku „✕” nie ma w czcionce FredokaOne, więc tekst był pusty)
local closeIcon = UiKit.icon("close", close, UDim2.fromScale(0.72, 0.72), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
closeIcon.ZIndex = 6
close.MouseEnter:Connect(function()
	TweenService:Create(closeIcon, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Rotation = 90 }):Play()
end)
close.MouseLeave:Connect(function()
	TweenService:Create(closeIcon, TweenInfo.new(0.2), { Rotation = 0 }):Play()
end)

-- Lista grzybów w zagłębieniu okna
local well = Instance.new("Frame")
well.Name = "Well"
well.Size = UDim2.new(1, -36, 1, -210)
well.Position = UDim2.fromOffset(18, 120)
well.BackgroundColor3 = THEME.well
well.Parent = window
corner(well, UDim.new(0, 18))
stroke(well, THEME.creamLine, 2.5)
local list = Instance.new("ScrollingFrame")
list.Name = "List"
list.Size = UDim2.new(1, -8, 1, -8)
list.Position = UDim2.fromOffset(4, 4)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 8
list.ScrollBarImageColor3 = OUTLINE
list.ScrollBarImageTransparency = 0.5
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.ScrollingDirection = Enum.ScrollingDirection.Y
list.Parent = well
local listPadding = Instance.new("UIPadding")
listPadding.PaddingLeft = UDim.new(0, 10)
listPadding.PaddingRight = UDim.new(0, 10)
listPadding.PaddingTop = UDim.new(0, 12)
listPadding.PaddingBottom = UDim.new(0, 12)
listPadding.Parent = list
local listLayout = Instance.new("UIGridLayout")
listLayout.CellSize = UDim2.fromOffset(CARD_W, CARD_H)
listLayout.CellPadding = UDim2.fromOffset(10, 12)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = list

-- Pusty koszyk: duża ikona i napis
local emptyIcon = UiKit.icon("basket", well, UDim2.fromOffset(90, 90), UDim2.new(0.5, 0, 0.42, 0), Vector2.new(0.5, 0.5))
emptyIcon.Rotation = -8
local empty = label(well, "Empty", UDim2.new(1, -60, 0, 30), UDim2.new(0, 30, 0.62, 0), TITLE_FONT, 24)
empty.TextColor3 = THEME.brown

-- Pasek na dole
local footer = Instance.new("Frame")
footer.Name = "Footer"
footer.Size = UDim2.new(1, -36, 0, 60)
footer.Position = UDim2.new(0, 18, 1, -78)
footer.BackgroundTransparency = 1
footer.Parent = window
local footerLayout = Instance.new("UIListLayout")
footerLayout.FillDirection = Enum.FillDirection.Horizontal
footerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
footerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
footerLayout.Padding = UDim.new(0, 12)
footerLayout.SortOrder = Enum.SortOrder.LayoutOrder
footerLayout.Parent = footer

local function footerButton(name: string, order: number, width: number, color: Color3, iconName: string): (TextButton, TextLabel)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.new(0, width, 1, 0)
	button.LayoutOrder = order
	button.Text = ""
	button.ClipsDescendants = false
	button.Parent = footer
	local buttonStroke = UiKit.button(button, color, { stroke = 3, radius = UDim.new(0, 16), gloss = true })
	buttonStroke.Color = OUTLINE
	local icon = UiKit.icon(iconName, button, UDim2.fromOffset(50, 50), UDim2.new(0, -6, 0.5, -2), Vector2.new(0, 0.5))
	icon.ZIndex = 4
	local text = label(button, "Text", UDim2.new(1, -58, 1, -14), UDim2.fromOffset(48, 7), TITLE_FONT, 22)
	text.ZIndex = 4
	UiKit.outline(text, 2.5)
	return button, text
end
local selectAll, selectAllText = footerButton("SelectAll", 1, 180, UiKit.COLORS.wood, "check")
local sellSelected, sellSelectedText = footerButton("SellSelected", 2, 230, THEME.green, "coin")
local sellAll, sellAllText = footerButton("SellAll", 3, 220, THEME.gold, "coins")

-- ===== Karty =====

type Card = { button: TextButton, check: Frame, checkIcon: GuiObject, stroke: UIStroke, scale: UIScale, color: Color3, sellOne: TextButton }
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

-- Sprzedawane karty odlatują (kurczą się z obrotem), zanim serwer przyśle nowy koszyk
local function flyAway(indices: { number }?)
	for index, card in cards do
		if indices == nil or table.find(indices, index) then
			TweenService:Create(card.scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
			TweenService:Create(card.button, TweenInfo.new(0.3), { Rotation = math.random(-25, 25) }):Play()
		end
	end
end

local function requestSell(indices: { number }?, from: GuiObject)
	local callback = sellCallback
	if callback and #basket > 0 then
		flyAway(indices)
		UiKit.burst(gui, centerOf(from), 12, { Color3.fromRGB(255, 214, 70), Color3.fromRGB(255, 255, 255) })
		faceScale.Scale = 1.3
		TweenService:Create(faceScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
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
	selectAllText.Text = Localize.t(if allSelected then "SELL_UNSELECT_ALL" else "SELL_SELECT_ALL")
	sellSelectedText.Text = Localize.t("SELL_SELECTED", { #indices }) .. "<br/>" .. formatCoins(selectedValue)
	sellAllText.Text = Localize.t("SELL_ALL") .. "<br/>" .. formatCoins(Economy.basketValue(basket))
	local canSelected = #indices > 0 and (guide == nil or (guide == "two" and #indices == 2))
	local canAll = #basket > 0 and (guide == nil or guide == "all")
	sellSelected.Active = canSelected
	UiKit.recolor(sellSelected, if canSelected then THEME.green else THEME.locked)
	sellAll.Active = canAll
	UiKit.recolor(sellAll, if canAll then THEME.gold else THEME.locked)
	selectAll.Active = #basket > 0 and guide == nil
	UiKit.recolor(selectAll, if guide == nil then UiKit.COLORS.wood else THEME.locked)
	for _, button in { selectAll, sellSelected, sellAll } do
		local st = button:FindFirstChildOfClass("UIStroke")
		if st then
			st.Color = OUTLINE
		end
	end
	for index, card in cards do
		local on = selected[index] == true
		card.checkIcon.Visible = on
		card.check.BackgroundColor3 = if on then Color3.fromRGB(70, 200, 90) else Color3.new(1, 1, 1)
		card.check.BackgroundTransparency = if on then 0 else 0.35
		card.stroke.Color = if on then THEME.selected else OUTLINE
		card.stroke.Thickness = if on then 4.5 else 3
		TweenService:Create(card.scale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = if on then 1.04 else 1 }):Play()
		-- W samouczku przyciski cen działają tylko w kroku „sprzedaj jeden”
		local priceOn = guide == nil or guide == "one"
		UiKit.recolor(card.sellOne, if priceOn then THEME.green else THEME.locked)
		local st = card.sellOne:FindFirstChildOfClass("UIStroke")
		if st then
			st.Color = OUTLINE
		end
	end
end

local function buildCard(index: number, item: Item): Card
	local class = Economy.speciesClass(item.s)
	local classColor = rgb(class.color)
	local cardColor = classColor:Lerp(Color3.fromRGB(60, 40, 30), 0.18)

	local button = Instance.new("TextButton")
	button.Name = "Card" .. index
	button.Text = ""
	button.LayoutOrder = index
	button.AutoButtonColor = false
	button.BackgroundColor3 = cardColor
	button.Parent = list
	corner(button, UDim.new(0, 18))
	local cardStroke = stroke(button, OUTLINE, 3)
	shade(button)
	local scale = Instance.new("UIScale")
	scale.Parent = button

	-- Pikselowy grzybek z aurą według rzadkości (MushroomArt); bez arkusza – grzybek z ramek
	local artBox = Instance.new("Frame")
	artBox.Name = "ArtBox"
	artBox.Size = UDim2.fromOffset(82, 82)
	artBox.Position = UDim2.new(0.5, 0, 0, -4)
	artBox.AnchorPoint = Vector2.new(0.5, 0)
	artBox.BackgroundTransparency = 1
	artBox.ZIndex = 0 -- pod napisami karty
	artBox.Parent = button
	local artScale = Instance.new("UIScale")
	artScale.Parent = artBox
	local art: GuiObject? = MushroomArt.build(artBox, item, {
		active = function()
			return gui.Enabled
		end,
		stroke = cardStroke,
	})
	if not art then
		local glow = Instance.new("Frame")
		glow.Name = "Glow"
		glow.Size = UDim2.fromOffset(72, 72)
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.Position = UDim2.new(0.5, 0, 0, 44)
		glow.BackgroundColor3 = Color3.new(1, 1, 1)
		glow.BackgroundTransparency = 0.7
		glow.Parent = button
		corner(glow, UDim.new(1, 0))
		local drawn = Instance.new("Frame")
		drawn.Name = "Art"
		drawn.Size = UDim2.fromOffset(66, 56)
		drawn.Position = UDim2.new(0.5, 0, 0, 16)
		drawn.AnchorPoint = Vector2.new(0.5, 0)
		drawn.BackgroundTransparency = 1
		drawn.Parent = button
		local stem = Instance.new("Frame")
		stem.Size = UDim2.fromOffset(22, 28)
		stem.Position = UDim2.new(0.5, 0, 1, 0)
		stem.AnchorPoint = Vector2.new(0.5, 1)
		stem.BackgroundColor3 = Color3.fromRGB(246, 234, 210)
		stem.Parent = drawn
		corner(stem, UDim.new(0, 8))
		stroke(stem, OUTLINE, 2.5)
		local cap = Instance.new("Frame")
		cap.Size = UDim2.fromOffset(64, 34)
		cap.Position = UDim2.fromScale(0.5, 0)
		cap.AnchorPoint = Vector2.new(0.5, 0)
		cap.BackgroundColor3 = capColor(item)
		cap.ZIndex = 2
		cap.Parent = drawn
		corner(cap, UDim.new(0.5, 0))
		stroke(cap, OUTLINE, 2.5)
		for k, spot in { { 0.3, 0.35, 9 }, { 0.62, 0.28, 7 }, { 0.78, 0.6, 6 } } do
			local dot = Instance.new("Frame")
			dot.Name = "Spot" .. k
			dot.Size = UDim2.fromOffset(spot[3], spot[3])
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.Position = UDim2.fromScale(spot[1], spot[2])
			dot.BackgroundColor3 = Color3.new(1, 1, 1)
			dot.BackgroundTransparency = 0.25
			dot.ZIndex = 3
			dot.Parent = cap
			corner(dot, UDim.new(1, 0))
		end
		if Economy.variantRank(item.v) >= 2 then
			-- Złote i tęczowe kapelusze lśnią
			local shine = Instance.new("UIGradient")
			shine.Color = ColorSequence.new(Color3.new(1, 1, 1), capColor(item))
			shine.Rotation = 45
			shine.Parent = cap
		end
	end
	button.ClipsDescendants = true

	local mutation = label(button, "Mutation", UDim2.fromOffset(70, 20), UDim2.fromOffset(8, 6), TITLE_FONT, 18)
	mutation.TextXAlignment = Enum.TextXAlignment.Left
	mutation.Text = mutationIcons(item)
	mutation.ZIndex = 4

	local species = Economy.getSpecies(item.s)
	local name = label(button, "Name", UDim2.new(1, -10, 0, 20), UDim2.new(0, 5, 0, 76), TITLE_FONT, 18)
	name.Text = if species then Localize.t(species.key) else "?"
	UiKit.outline(name, 2)
	-- Klasa na ciemnej plakietce
	local classPill = Instance.new("Frame")
	classPill.Name = "ClassPill"
	classPill.Size = UDim2.new(1, -24, 0, 16)
	classPill.Position = UDim2.fromOffset(12, 97)
	classPill.BackgroundColor3 = OUTLINE
	classPill.BackgroundTransparency = 0.35
	classPill.Parent = button
	corner(classPill, UDim.new(1, 0))
	local classLabel = label(classPill, "Class", UDim2.new(1, -8, 1, -2), UDim2.fromOffset(4, 1), BODY_FONT, 12)
	classLabel.Text = Localize.t(class.key)
	classLabel.TextColor3 = classColor:Lerp(Color3.new(1, 1, 1), 0.35)

	-- Przycisk sprzedaży tylko tej karty, z ceną
	local sellOne = Instance.new("TextButton")
	sellOne.Name = "SellOne"
	sellOne.Text = ""
	sellOne.Size = UDim2.new(1, -14, 0, 30)
	sellOne.Position = UDim2.new(0.5, 0, 1, -6)
	sellOne.AnchorPoint = Vector2.new(0.5, 1)
	sellOne.Parent = button
	local sellStroke = UiKit.button(sellOne, THEME.green, { stroke = 2.5, radius = UDim.new(0, 10), gloss = true })
	sellStroke.Color = OUTLINE
	local coin = UiKit.icon("coin", sellOne, UDim2.fromOffset(26, 26), UDim2.new(0, 2, 0.5, 0), Vector2.new(0, 0.5))
	coin.ZIndex = 4
	local price = label(sellOne, "Price", UDim2.new(1, -34, 1, -8), UDim2.fromOffset(28, 4), TITLE_FONT, 18)
	price.Text = formatCoins(Economy.itemValue(item))
	price.ZIndex = 4
	UiKit.outline(price, 2)

	-- Kółko zaznaczenia w prawym górnym rogu (z ptaszkiem z arkusza)
	local check = Instance.new("Frame")
	check.Name = "Check"
	check.Size = UDim2.fromOffset(28, 28)
	check.Position = UDim2.new(1, -32, 0, 4)
	check.BackgroundColor3 = Color3.new(1, 1, 1)
	check.BackgroundTransparency = 0.35
	check.ZIndex = 4
	check.Parent = button
	corner(check, UDim.new(1, 0))
	stroke(check, OUTLINE, 2.5)
	local checkIcon = UiKit.icon("check", check, UDim2.fromScale(0.9, 0.9), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	checkIcon.ZIndex = 5
	checkIcon.Visible = false

	button.MouseEnter:Connect(function()
		cardStroke.Thickness = math.max(cardStroke.Thickness, 4)
		TweenService:Create(artBox, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Rotation = -8 }):Play()
		TweenService:Create(artScale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1.15 }):Play()
	end)
	button.MouseLeave:Connect(function()
		cardStroke.Thickness = if selected[index] then 4.5 else 3
		TweenService:Create(artBox, TweenInfo.new(0.2), { Rotation = 0 }):Play()
		TweenService:Create(artScale, TweenInfo.new(0.2), { Scale = 1 }):Play()
	end)
	button.Activated:Connect(function()
		-- Samouczek: zaznaczać wolno tylko w kroku „dwa zaznaczone” i tylko dwa pierwsze grzyby
		if guide ~= nil and not (guide == "two" and index <= 2) then
			UiKit.shake(button)
			return
		end
		selected[index] = if selected[index] then nil else true
		scale.Scale = 0.9
		refreshFooter()
		if selected[index] then
			UiKit.burst(gui, centerOf(check), 6)
		end
	end)
	sellOne.Activated:Connect(function()
		if guide ~= nil and guide ~= "one" then
			UiKit.shake(sellOne)
			return
		end
		requestSell({ index }, sellOne)
	end)
	return { button = button, check = check, checkIcon = checkIcon, stroke = cardStroke, scale = scale, color = cardColor, sellOne = sellOne }
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
	emptyIcon.Visible = #basket == 0
	empty.Text = Localize.t("SELL_EMPTY")
	refreshFooter()
end

-- Co mówi kupiec: powitanie albo (w samouczku) co teraz kliknąć
local function speechText(): string
	if guide and #basket > 0 then
		local key = if guide == "one" then "SELLTUT_ONE" elseif guide == "all" then "SELLTUT_ALL" elseif #selectedIndices() >= 2 then "SELLTUT_TWO" else "SELLTUT_PICK"
		return string.format("<font color=\"#C8342C\">%d/3</font>  %s", GUIDE_STEP[guide] or 1, Localize.t(key))
	end
	return Localize.t(if #basket == 0 then "NPC_EMPTY" else greetingKey)
end

local function refreshTexts()
	npcName.Text = Localize.t(if MerchantLook.isGhost() then "NPC_NAME_GHOST" else "NPC_NAME")
	roleTitle.Text = Localize.t("NPC_ROLE")
	speech.Text = speechText()
	rebuild()
end

-- ===== Przyciski =====

selectAll.Activated:Connect(function()
	if #basket == 0 then
		return
	end
	if guide ~= nil then
		UiKit.shake(selectAll)
		return
	end
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
	if #indices > 0 and (guide == nil or (guide == "two" and #indices == 2)) then
		requestSell(indices, sellSelected)
	else
		UiKit.shake(sellSelected)
	end
end)
sellAll.Activated:Connect(function()
	if #basket > 0 and (guide == nil or guide == "all") then
		requestSell(nil, sellAll)
	else
		UiKit.shake(sellAll)
	end
end)
close.Activated:Connect(function()
	SellPanel.close()
end)
dim.Activated:Connect(function()
	SellPanel.close()
end)

-- ===== Samouczek: strzałka i złota obwódka na tym, co trzeba kliknąć =====

local ring = Instance.new("Frame")
ring.Name = "GuideRing"
ring.BackgroundTransparency = 1
ring.AnchorPoint = Vector2.new(0.5, 0.5)
ring.Visible = false
ring.ZIndex = 50
ring.Parent = gui
corner(ring, UDim.new(0, 18))
local ringStroke = stroke(ring, Color3.fromRGB(255, 214, 70), 5)
local arrow = UiKit.icon("upgrade", gui, UDim2.fromOffset(64, 64), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 1))
arrow.Rotation = 180
arrow.Visible = false
arrow.ZIndex = 51
local lastTarget: GuiObject? = nil

local function guideTarget(): GuiObject?
	if not guide or #basket == 0 then
		return nil
	end
	if guide == "one" then
		local card = cards[1]
		return card and card.sellOne
	elseif guide == "two" then
		for index = 1, 2 do
			local card = cards[index]
			if card and not selected[index] then
				return card.check
			end
		end
		return sellSelected
	end
	return sellAll
end

RunService.RenderStepped:Connect(function()
	local target = if gui.Enabled then guideTarget() else nil
	ring.Visible = target ~= nil
	arrow.Visible = target ~= nil
	if not target then
		lastTarget = nil
		return
	end
	local now = os.clock()
	local center = target.AbsolutePosition + target.AbsoluteSize / 2
	local pulse = 1 + 0.08 * math.sin(now * 7)
	ring.Position = UDim2.fromOffset(center.X, center.Y)
	ring.Size = UDim2.fromOffset((target.AbsoluteSize.X + 14) * pulse, (target.AbsoluteSize.Y + 14) * pulse)
	ringStroke.Transparency = 0.25 * (1 - math.sin(now * 7))
	local bob = math.abs(math.sin(now * 5)) * 12
	arrow.Position = UDim2.fromOffset(center.X, target.AbsolutePosition.Y - 4 - bob)
	if target ~= lastTarget then
		-- Nowy cel: strzałka wskakuje, kupiec mówi następną rzecz
		lastTarget = target
		arrow.Size = UDim2.fromOffset(20, 20)
		TweenService:Create(arrow, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(64, 64) }):Play()
		speech.Text = speechText()
		bubble.BackgroundColor3 = Color3.fromRGB(255, 240, 160)
		TweenService:Create(bubble, TweenInfo.new(0.6), { BackgroundColor3 = Color3.new(1, 1, 1) }):Play()
	end
end)

-- ===== API =====

-- Tryb samouczka (nil = zwykły panel)
function SellPanel.setGuide(mode: string?)
	if mode == guide then
		return
	end
	guide = mode
	table.clear(selected)
	lastTarget = nil
	if gui.Enabled then
		speech.Text = speechText()
		refreshFooter()
	end
end

function SellPanel.onSell(callback: (indices: { number }?, key: string, from: Vector2?) -> ())
	sellCallback = callback
end

-- Nowa zawartość koszyka od serwera (tylko po zmianie)
function SellPanel.setBasket(items: { Item }, key: string)
	basket = items
	basketKey = key
	table.clear(selected)
	if gui.Enabled then
		speech.Text = speechText()
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
	refreshPortrait()
	refreshTexts()
	local base = UiScale.get()
	windowScale.Scale = base * 0.75
	TweenService:Create(windowScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = base }):Play()
	dim.BackgroundTransparency = 1
	TweenService:Create(dim, TweenInfo.new(0.25), { BackgroundTransparency = 0.5 }):Play()
	-- Karty wskakują jedna po drugiej
	for index, card in cards do
		TweenService:Create(card.scale, TweenInfo.new(0), { Scale = 0 }):Play()
		task.delay(0.03 * index, function()
			TweenService:Create(card.scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end)
	end
end

function SellPanel.close()
	gui.Enabled = false
end

Localize.onChanged(function()
	if gui.Enabled then
		refreshTexts()
	end
end)
-- Początek albo koniec Halloween przy otwartym panelu: portret i imię zmieniają się od razu
game:GetService("Workspace"):GetAttributeChangedSignal("Halloween"):Connect(function()
	if gui.Enabled then
		refreshPortrait()
		refreshTexts()
	end
end)
UiScale.onChanged(function()
	windowScale.Scale = UiScale.get()
end)

return SellPanel
