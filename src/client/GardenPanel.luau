--!strict
-- Okno sadzenia przy furtce własnego ogródka.
--   Po lewej grządki (siatka 3 x 3): posadzony grzyb z dochodem na minutę, wolna grządka, zamknięta grządka.
--   Po prawej grzyby z koszyka (z dochodem, jaki dawałyby po posadzeniu).
--   Grzyb przeciągasz na grządkę (albo klikasz grzyb, a potem grządkę). Na zajętej grządce grzyby się
--   zamieniają: stary idzie do sprzedaży (okno pokazuje za ile, zanim puścisz).
--   „Posadź najlepsze” robi to samo automatycznie. Serwer sprawdza każdy ruch (GardenService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Economy = require(ReplicatedStorage.Shared.Economy)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Audio = require(script.Parent.Audio)
local Localize = require(script.Parent.Localize)
local MushroomArt = require(script.Parent.MushroomArt)
local UiKit = require(script.Parent.UiKit)
local UiScale = require(script.Parent.UiScale)

type Item = Economy.BasketItem

local GardenPanel = {}

local player = Players.LocalPlayer
local TITLE_FONT = Enum.Font.FredokaOne
local BODY_FONT = Enum.Font.GothamBold
local OUTLINE = UiKit.OUTLINE
local CREAM = Color3.fromRGB(255, 248, 234)
local CREAM_LINE = Color3.fromRGB(232, 214, 182)
local SOIL = Color3.fromRGB(110, 74, 48)
local SOIL_DARK = Color3.fromRGB(84, 56, 38)
local SOIL_LOCKED = Color3.fromRGB(70, 62, 58)
local GREEN = Color3.fromRGB(54, 190, 92)
local ORANGE = Color3.fromRGB(246, 150, 40)
local GOLD = Color3.fromRGB(255, 214, 70)
local WINDOW_W, WINDOW_H = 760, 520
local BED = 112
local CARD_W, CARD_H = 104, 128

local basket: { Item } = {}
local basketKey = ""
local planted: { Item } = {}
local beds = 3
local maxBeds = 9
local fertilizer = 1
local selected: number? = nil -- indeks w koszyku
local guide = false -- samouczek: strzałka na pierwszy grzyb, potem na grządkę

local function t(key: string, args: { any }?): string
	return Localize.t(key, args)
end

local function corner(parent: Instance, radius: UDim?)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or UDim.new(0, 12)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function label(parent: Instance, size: UDim2, position: UDim2, font: Enum.Font, maxSize: number, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position
	l.Font = font
	l.TextScaled = true
	l.RichText = true
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.Text = ""
	l.Parent = parent
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = maxSize
	c.Parent = l
	return l
end

local function formatRate(rate: number): string
	if rate >= 100 then
		return string.format("+%d/min", math.floor(rate + 0.5))
	end
	return string.format("+%.1f/min", rate)
end

local function formatCoins(value: number): string
	local s = tostring(math.floor(value + 0.5))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (formatted:gsub("^ ", ""))
end

-- ===== Okno =====

local gui = Instance.new("ScreenGui")
gui.Name = "GardenPanel"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 6
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local dim = Instance.new("TextButton")
dim.Text = ""
dim.AutoButtonColor = false
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 0.5
dim.Parent = gui

local window = Instance.new("Frame")
window.Name = "Window"
window.Size = UDim2.fromOffset(WINDOW_W, WINDOW_H)
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.fromScale(0.5, 0.53)
window.BackgroundColor3 = CREAM
window.Parent = gui
corner(window, UDim.new(0, 26))
stroke(window, OUTLINE, 4)
local windowScale = Instance.new("UIScale")
windowScale.Parent = window

-- Wstążka w kolorze liścia z kiełkiem
local ribbon = Instance.new("Frame")
ribbon.Size = UDim2.fromOffset(280, 56)
ribbon.AnchorPoint = Vector2.new(0.5, 0.5)
ribbon.Position = UDim2.new(0.5, 0, 0, 0)
ribbon.BackgroundColor3 = Color3.fromRGB(86, 170, 70)
ribbon.ZIndex = 5
ribbon.Parent = window
corner(ribbon, UDim.new(0, 16))
stroke(ribbon, OUTLINE, 3.5)
local ribbonIcon = UiKit.icon("beds", ribbon, UDim2.fromOffset(64, 64), UDim2.new(0, -14, 0.5, -4), Vector2.new(0, 0.5))
ribbonIcon.ZIndex = 7
ribbonIcon.Rotation = -10
local title = label(ribbon, UDim2.new(1, -70, 1, -12), UDim2.fromOffset(56, 6), TITLE_FONT, 32)
title.ZIndex = 7
UiKit.outline(title, 3)

local close = Instance.new("TextButton")
close.Size = UDim2.fromOffset(52, 52)
close.AnchorPoint = Vector2.new(0.5, 0.5)
close.Position = UDim2.new(1, -12, 0, 6)
close.Text = ""
close.ZIndex = 5
close.Parent = window
local closeStroke = UiKit.button(close, UiKit.COLORS.red, { stroke = 3, radius = UDim.new(0, 14), gloss = true })
closeStroke.Color = OUTLINE
local closeIcon = UiKit.icon("close", close, UDim2.fromScale(0.72, 0.72), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
closeIcon.ZIndex = 6

-- Podpowiedź u góry (co robić)
local hintBar = Instance.new("Frame")
hintBar.Size = UDim2.new(1, -36, 0, 34)
hintBar.Position = UDim2.fromOffset(18, 38)
hintBar.BackgroundColor3 = Color3.new(1, 1, 1)
hintBar.Parent = window
corner(hintBar, UDim.new(0, 12))
stroke(hintBar, OUTLINE, 2.5)
local hint = label(hintBar, UDim2.new(1, -20, 1, -8), UDim2.fromOffset(10, 4), BODY_FONT, 17, Color3.fromRGB(60, 40, 24))

-- Lewa strona: grządki
local bedsBox = Instance.new("Frame")
bedsBox.Name = "Beds"
bedsBox.Size = UDim2.fromOffset(3 * BED + 2 * 10 + 24, 3 * BED + 2 * 10 + 24)
bedsBox.Position = UDim2.fromOffset(18, 84)
bedsBox.BackgroundColor3 = Color3.fromRGB(150, 196, 96)
bedsBox.Parent = window
corner(bedsBox, UDim.new(0, 20))
stroke(bedsBox, OUTLINE, 3)
local grassShade = Instance.new("UIGradient")
grassShade.Rotation = 90
grassShade.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 200, 200))
grassShade.Parent = bedsBox
local bedsPad = Instance.new("UIPadding")
bedsPad.PaddingLeft = UDim.new(0, 12)
bedsPad.PaddingTop = UDim.new(0, 12)
bedsPad.Parent = bedsBox
local bedsLayout = Instance.new("UIGridLayout")
bedsLayout.CellSize = UDim2.fromOffset(BED, BED)
bedsLayout.CellPadding = UDim2.fromOffset(10, 10)
bedsLayout.SortOrder = Enum.SortOrder.LayoutOrder
bedsLayout.Parent = bedsBox

-- Prawa strona: koszyk
local basketBox = Instance.new("Frame")
basketBox.Name = "Basket"
basketBox.Size = UDim2.new(1, -(18 + 3 * BED + 44 + 18 + 14), 0, 3 * BED + 44 - 44)
basketBox.Position = UDim2.fromOffset(18 + 3 * BED + 44 + 14, 84)
basketBox.BackgroundColor3 = Color3.fromRGB(240, 228, 204)
basketBox.Parent = window
corner(basketBox, UDim.new(0, 18))
stroke(basketBox, CREAM_LINE, 2.5)
local basketTitle = label(basketBox, UDim2.new(1, -20, 0, 24), UDim2.fromOffset(10, 6), TITLE_FONT, 22, Color3.fromRGB(110, 66, 34))
basketTitle.TextXAlignment = Enum.TextXAlignment.Left
local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, -8, 1, -38)
list.Position = UDim2.fromOffset(4, 34)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 8
list.ScrollBarImageColor3 = OUTLINE
list.ScrollBarImageTransparency = 0.5
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.Parent = basketBox
local listPad = Instance.new("UIPadding")
listPad.PaddingLeft = UDim.new(0, 8)
listPad.PaddingTop = UDim.new(0, 6)
listPad.PaddingBottom = UDim.new(0, 8)
listPad.Parent = list
local listLayout = Instance.new("UIGridLayout")
listLayout.CellSize = UDim2.fromOffset(CARD_W, CARD_H)
listLayout.CellPadding = UDim2.fromOffset(8, 8)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = list
local emptyText = label(basketBox, UDim2.new(1, -40, 0, 60), UDim2.new(0, 20, 0.45, 0), TITLE_FONT, 22, Color3.fromRGB(110, 66, 34))
emptyText.TextWrapped = true

-- Dół: suma dochodu i „Posadź najlepsze”
local total = label(window, UDim2.fromOffset(3 * BED + 44, 34), UDim2.new(0, 18, 1, -56), TITLE_FONT, 26, Color3.fromRGB(70, 140, 50))
local auto = Instance.new("TextButton")
auto.Name = "Auto"
auto.Text = ""
auto.Size = UDim2.fromOffset(250, 52)
auto.AnchorPoint = Vector2.new(1, 1)
auto.Position = UDim2.new(1, -18, 1, -16)
auto.Parent = window
local autoStroke = UiKit.button(auto, GREEN, { stroke = 3, radius = UDim.new(0, 16), gloss = true })
autoStroke.Color = OUTLINE
local autoIcon = UiKit.icon("sparkles", auto, UDim2.fromOffset(44, 44), UDim2.new(0, 4, 0.5, 0), Vector2.new(0, 0.5))
autoIcon.ZIndex = 4
local autoText = label(auto, UDim2.new(1, -56, 1, -12), UDim2.fromOffset(50, 6), TITLE_FONT, 22)
autoText.ZIndex = 4
UiKit.outline(autoText, 2.5)

-- Ciągnięty grzyb (duch pod kursorem) i podpis zamiany nad grządką
local ghost = Instance.new("Frame")
ghost.Name = "Ghost"
ghost.Size = UDim2.fromOffset(84, 84)
ghost.AnchorPoint = Vector2.new(0.5, 0.5)
ghost.BackgroundTransparency = 1
ghost.Visible = false
ghost.ZIndex = 60
ghost.Parent = gui
local swapTag = Instance.new("TextLabel")
swapTag.Size = UDim2.fromOffset(170, 30)
swapTag.AnchorPoint = Vector2.new(0.5, 1)
swapTag.BackgroundColor3 = ORANGE
swapTag.Font = TITLE_FONT
swapTag.TextScaled = true
swapTag.TextColor3 = Color3.new(1, 1, 1)
swapTag.Visible = false
swapTag.ZIndex = 61
swapTag.Parent = gui
corner(swapTag, UDim.new(0, 10))
stroke(swapTag, OUTLINE, 2.5)
UiKit.outline(swapTag :: any, 2)

-- Strzałka samouczka
local arrow = UiKit.icon("upgrade", gui, UDim2.fromOffset(60, 60), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 1))
arrow.Rotation = 180
arrow.Visible = false
arrow.ZIndex = 70

-- ===== Grządki i karty =====

type Bed = { frame: TextButton, scale: UIScale, glow: UIStroke, index: number, state: string }
local bedFrames: { Bed } = {}
type Card = { frame: TextButton, scale: UIScale, stroke: UIStroke, index: number }
local cardFrames: { Card } = {}

local dragging: number? = nil
local dragStart: Vector2? = nil
local dragMoved = false
local hoverBed: Bed? = nil

local function centerOf(object: GuiObject): Vector2
	return object.AbsolutePosition + object.AbsoluteSize / 2
end

-- Grudki ziemi wylatujące z grządki
local function dirt(at: Vector2)
	UiKit.burst(gui, at, 12, { SOIL, SOIL_DARK, Color3.fromRGB(140, 100, 64), Color3.fromRGB(120, 200, 90) })
end

local function bedState(index: number): string
	if index > beds then
		return "locked"
	elseif index <= #planted then
		return "planted"
	end
	return "empty"
end

local function buildBed(index: number): Bed
	local state = bedState(index)
	local frame = Instance.new("TextButton")
	frame.Name = "Bed" .. index
	frame.Text = ""
	frame.AutoButtonColor = false
	frame.LayoutOrder = index
	frame.BackgroundColor3 = if state == "locked" then SOIL_LOCKED else SOIL
	frame.Parent = bedsBox
	corner(frame, UDim.new(0, 16))
	local glow = stroke(frame, OUTLINE, 3)
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	-- Zaorane rzędy w ziemi
	for row = 1, 3 do
		local furrow = Instance.new("Frame")
		furrow.BorderSizePixel = 0
		furrow.Size = UDim2.new(1, -20, 0, 6)
		furrow.Position = UDim2.new(0, 10, 0, 20 + row * 22)
		furrow.BackgroundColor3 = if state == "locked" then Color3.fromRGB(56, 50, 48) else SOIL_DARK
		furrow.Parent = frame
		corner(furrow, UDim.new(1, 0))
	end
	if state == "planted" then
		local item = planted[index]
		local art = Instance.new("Frame")
		art.Size = UDim2.fromOffset(78, 78)
		art.AnchorPoint = Vector2.new(0.5, 0)
		art.Position = UDim2.new(0.5, 0, 0, 2)
		art.BackgroundTransparency = 1
		art.ZIndex = 2
		art.Parent = frame
		MushroomArt.build(art, item, {
			active = function()
				return gui.Enabled
			end,
			stroke = glow,
		})
		local pill = Instance.new("Frame")
		pill.Size = UDim2.new(1, -14, 0, 24)
		pill.AnchorPoint = Vector2.new(0.5, 1)
		pill.Position = UDim2.new(0.5, 0, 1, -6)
		pill.BackgroundColor3 = OUTLINE
		pill.BackgroundTransparency = 0.25
		pill.ZIndex = 3
		pill.Parent = frame
		corner(pill, UDim.new(1, 0))
		local rate = label(pill, UDim2.new(1, -8, 1, -4), UDim2.fromOffset(4, 2), TITLE_FONT, 17, Color3.fromRGB(166, 240, 106))
		rate.ZIndex = 4
		rate.Text = formatRate(Economy.plantIncome(item, fertilizer))
	elseif state == "empty" then
		local plus = label(frame, UDim2.fromOffset(60, 60), UDim2.new(0.5, -30, 0.5, -34), TITLE_FONT, 54, Color3.fromRGB(255, 236, 200))
		plus.Text = "+"
		plus.TextTransparency = 0.35
		plus.ZIndex = 2
		local free = label(frame, UDim2.new(1, -10, 0, 20), UDim2.new(0, 5, 1, -26), TITLE_FONT, 16, Color3.fromRGB(255, 236, 200))
		free.Text = t("GP_EMPTY")
		free.ZIndex = 2
	else
		local lock = UiKit.icon("lock", frame, UDim2.fromOffset(46, 46), UDim2.new(0.5, 0, 0.42, 0), Vector2.new(0.5, 0.5))
		lock.ZIndex = 2
		local buy = label(frame, UDim2.new(1, -10, 0, 30), UDim2.new(0, 5, 1, -34), TITLE_FONT, 14, Color3.fromRGB(220, 210, 200))
		buy.TextWrapped = true
		buy.Text = t("GP_LOCKED")
		buy.ZIndex = 2
	end
	local bed: Bed = { frame = frame, scale = scale, glow = glow, index = index, state = state }
	return bed
end

local function buildCard(index: number, item: Item): Card
	local class = Economy.speciesClass(item.s)
	local classColor = Color3.fromRGB(class.color[1], class.color[2], class.color[3])
	local frame = Instance.new("TextButton")
	frame.Name = "Card" .. index
	frame.Text = ""
	frame.AutoButtonColor = false
	frame.LayoutOrder = index
	frame.BackgroundColor3 = classColor:Lerp(Color3.fromRGB(60, 40, 30), 0.18)
	frame.ClipsDescendants = true
	frame.Parent = list
	corner(frame, UDim.new(0, 16))
	local cardStroke = stroke(frame, OUTLINE, 3)
	local shade = Instance.new("UIGradient")
	shade.Rotation = 90
	shade.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(196, 196, 196))
	shade.Parent = frame
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	local art = Instance.new("Frame")
	art.Size = UDim2.fromOffset(70, 70)
	art.AnchorPoint = Vector2.new(0.5, 0)
	art.Position = UDim2.new(0.5, 0, 0, -2)
	art.BackgroundTransparency = 1
	art.Parent = frame
	MushroomArt.build(art, item, {
		active = function()
			return gui.Enabled
		end,
		stroke = cardStroke,
	})
	local species = Economy.getSpecies(item.s)
	local name = label(frame, UDim2.new(1, -8, 0, 18), UDim2.new(0, 4, 0, 66), TITLE_FONT, 16)
	name.Text = if species then t(species.key) else "?"
	name.ZIndex = 3
	UiKit.outline(name, 2)
	local pill = Instance.new("Frame")
	pill.Size = UDim2.new(1, -12, 0, 24)
	pill.AnchorPoint = Vector2.new(0.5, 1)
	pill.Position = UDim2.new(0.5, 0, 1, -6)
	pill.BackgroundColor3 = OUTLINE
	pill.BackgroundTransparency = 0.25
	pill.ZIndex = 3
	pill.Parent = frame
	corner(pill, UDim.new(1, 0))
	local rate = label(pill, UDim2.new(1, -8, 1, -4), UDim2.fromOffset(4, 2), TITLE_FONT, 16, Color3.fromRGB(166, 240, 106))
	rate.ZIndex = 4
	rate.Text = formatRate(Economy.plantIncome(item, fertilizer))
	return { frame = frame, scale = scale, stroke = cardStroke, index = index }
end

local function refreshHighlights()
	for _, card in cardFrames do
		local on = selected == card.index or dragging == card.index
		card.stroke.Color = if on then Color3.fromRGB(150, 255, 110) else OUTLINE
		card.stroke.Thickness = if on then 5 else 3
	end
	local holding = selected ~= nil or dragging ~= nil
	for _, bed in bedFrames do
		if bed.state ~= "locked" then
			bed.glow.Color = if holding then (if bed.state == "empty" then Color3.fromRGB(150, 255, 110) else ORANGE) else OUTLINE
			bed.glow.Thickness = if holding then 4 else 3
		end
	end
end

local function rebuild()
	for _, bed in bedFrames do
		bed.frame:Destroy()
	end
	for _, card in cardFrames do
		card.frame:Destroy()
	end
	table.clear(bedFrames)
	table.clear(cardFrames)
	for index = 1, maxBeds do
		table.insert(bedFrames, buildBed(index))
	end
	for index, item in basket do
		table.insert(cardFrames, buildCard(index, item))
	end
	if selected and not basket[selected] then
		selected = nil
	end
	emptyText.Visible = #basket == 0
	emptyText.Text = t("GP_BASKET_EMPTY")
	basketTitle.Text = t("GP_BASKET", { #basket })
	total.Text = t("GP_TOTAL", { formatRate(Economy.gardenIncome(planted :: any, fertilizer)) })
	title.Text = t("GARDEN_YOURS")
	autoText.Text = t("GP_AUTO")
	hint.Text = t(if #basket == 0 then "GP_HINT_EMPTY" elseif selected then "GP_HINT_BED" else "GP_HINT")
	UiKit.recolor(auto, if #basket > 0 then GREEN else Color3.fromRGB(170, 156, 140))
	autoStroke.Color = OUTLINE
	refreshHighlights()
end

-- Sadzenie: animacja od razu (grządka podskakuje, grudki ziemi), a stan i tak przyjdzie od serwera
local function plantOn(bed: Bed, index: number)
	if bed.state == "locked" then
		UiKit.shake(bed.frame)
		Audio.play("warn", { volume = 0.5 })
		return
	end
	local item = basket[index]
	if not item then
		return
	end
	local slot = if bed.state == "planted" then bed.index else #planted + 1
	bed.scale.Scale = 0.85
	TweenService:Create(bed.scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	dirt(centerOf(bed.frame))
	Audio.play("plant", { duration = 1.2, volume = 0.9 })
	if bed.state == "planted" then
		Audio.play("coin", { volume = 0.6 })
		UiKit.burst(gui, centerOf(bed.frame), 10)
	end
	selected = nil
	Remotes.get("GardenPlant"):FireServer(index, slot, basketKey)
end

local function bedAt(position: Vector2): Bed?
	for _, bed in bedFrames do
		local p, s = bed.frame.AbsolutePosition, bed.frame.AbsoluteSize
		if position.X >= p.X and position.X <= p.X + s.X and position.Y >= p.Y and position.Y <= p.Y + s.Y then
			return bed
		end
	end
	return nil
end

local function wireBed(bed: Bed)
	bed.frame.Activated:Connect(function()
		if selected then
			plantOn(bed, selected)
		elseif bed.state == "locked" then
			UiKit.shake(bed.frame)
		end
	end)
	bed.frame.MouseEnter:Connect(function()
		if bed.state ~= "locked" then
			TweenService:Create(bed.scale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1.05 }):Play()
		end
	end)
	bed.frame.MouseLeave:Connect(function()
		TweenService:Create(bed.scale, TweenInfo.new(0.2), { Scale = 1 }):Play()
	end)
end

local function wireCard(card: Card)
	card.frame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = card.index
			dragStart = Vector2.new(input.Position.X, input.Position.Y)
			dragMoved = false
			refreshHighlights()
		end
	end)
	card.frame.MouseEnter:Connect(function()
		TweenService:Create(card.scale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1.06 }):Play()
	end)
	card.frame.MouseLeave:Connect(function()
		TweenService:Create(card.scale, TweenInfo.new(0.2), { Scale = 1 }):Play()
	end)
end

local function wireAll()
	for _, bed in bedFrames do
		wireBed(bed)
	end
	for _, card in cardFrames do
		wireCard(card)
	end
end

local function fullRebuild()
	rebuild()
	wireAll()
end

-- Przeciąganie: duch grzyba idzie za kursorem, grządka pod nim świeci (zielono = wolna, pomarańczowo = zamiana)
UserInputService.InputChanged:Connect(function(input)
	if not gui.Enabled or not dragging then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local position = Vector2.new(input.Position.X, input.Position.Y)
	if dragStart and (position - dragStart).Magnitude > 10 and not dragMoved then
		dragMoved = true
		for _, child in ghost:GetChildren() do
			child:Destroy()
		end
		local item = basket[dragging]
		if item then
			MushroomArt.build(ghost, item, {
				active = function()
					return gui.Enabled
				end,
			})
		end
		ghost.Visible = true
		Audio.play("blip", { volume = 0.4 })
	end
	if dragMoved then
		-- Pozycja wejścia jest w tym samym układzie co AbsolutePosition okna (pod paskiem Robloxa)
		ghost.Position = UDim2.fromOffset(position.X, position.Y)
		ghost.Rotation = math.sin(os.clock() * 10) * 8
		local bed = bedAt(position)
		hoverBed = bed
		if bed and bed.state == "planted" then
			local item = planted[bed.index]
			swapTag.Visible = true
			swapTag.Text = t("GP_SWAP", { formatCoins(Economy.itemValue(item)) })
			swapTag.Position = UDim2.fromOffset(centerOf(bed.frame).X, bed.frame.AbsolutePosition.Y - 4)
		else
			swapTag.Visible = false
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if not dragging then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local index = dragging
	dragging = nil
	ghost.Visible = false
	swapTag.Visible = false
	if dragMoved then
		local bed = hoverBed
		if bed then
			plantOn(bed, index)
		end
	else
		-- Zwykłe kliknięcie: zaznacz grzyb (drugie kliknięcie odznacza)
		selected = if selected == index then nil else index
		hint.Text = t(if selected then "GP_HINT_BED" else "GP_HINT")
		Audio.play("click", { volume = 0.5 })
	end
	hoverBed = nil
	dragMoved = false
	refreshHighlights()
end)

auto.Activated:Connect(function()
	if #basket == 0 then
		UiKit.shake(auto)
		return
	end
	for _, bed in bedFrames do
		if bed.state ~= "locked" then
			dirt(centerOf(bed.frame))
		end
	end
	Audio.play("plant", { duration = 1.2 })
	Remotes.get("GardenAuto"):FireServer()
end)

local function closePanel()
	gui.Enabled = false
	selected = nil
	dragging = nil
	ghost.Visible = false
	swapTag.Visible = false
end
close.Activated:Connect(closePanel)
dim.Activated:Connect(closePanel)

-- Strzałka samouczka: najpierw na pierwszy grzyb, a gdy jest wybrany – na grządkę
RunService.RenderStepped:Connect(function()
	local target: GuiObject? = nil
	if gui.Enabled and guide and #basket > 0 then
		if selected or dragging then
			for _, bed in bedFrames do
				if bed.state == "empty" then
					target = bed.frame
					break
				end
			end
			if not target and bedFrames[1] and bedFrames[1].state ~= "locked" then
				target = bedFrames[1].frame
			end
		elseif cardFrames[1] then
			target = cardFrames[1].frame
		end
	end
	arrow.Visible = target ~= nil
	if target then
		local bob = math.abs(math.sin(os.clock() * 5)) * 12
		arrow.Position = UDim2.fromOffset(centerOf(target).X, target.AbsolutePosition.Y - 2 - bob)
	end
end)

-- ===== API =====

function GardenPanel.start()
	Remotes.get("GardenView").OnClientEvent:Connect(function(view, open)
		planted = view.planted or {}
		beds = view.beds or 3
		maxBeds = view.maxBeds or 9
		fertilizer = view.fertilizer or 1
		if open then
			GardenPanel.open()
		elseif gui.Enabled then
			fullRebuild()
		end
	end)
	Localize.onChanged(function()
		if gui.Enabled then
			fullRebuild()
		end
	end)
	UiScale.onChanged(function()
		windowScale.Scale = UiScale.get()
	end)
end

function GardenPanel.setBasket(items: { Item }, key: string)
	basket = items
	basketKey = key
	if gui.Enabled then
		fullRebuild()
	end
end

function GardenPanel.isOpen(): boolean
	return gui.Enabled
end

function GardenPanel.open()
	selected = nil
	gui.Enabled = true
	fullRebuild()
	local base = UiScale.get()
	windowScale.Scale = base * 0.75
	TweenService:Create(windowScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = base }):Play()
	-- Grządki wskakują jedna po drugiej
	for i, bed in bedFrames do
		bed.scale.Scale = 0
		task.delay(0.03 * i, function()
			TweenService:Create(bed.scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end)
	end
	Audio.play("whoosh", { volume = 0.4 })
end

function GardenPanel.close()
	closePanel()
end

function GardenPanel.setGuide(on: boolean)
	guide = on
end

return GardenPanel
