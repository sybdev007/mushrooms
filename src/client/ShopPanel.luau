--!strict
-- Sklep za Robuxy i wszystko, co z nim związane na ekranie (UI v2, makieta „Chatka Leszego” w Figmie):
--   przycisk „Sklep” w kolumnie pod „Ulepszeniami” (SideButtons) i okno sklepu z kartami produktów (Config.ShopOrder):
--     Wysyp (cały serwer, złota karta z biegnącym blaskiem), mikstura, olej, zbiory od razu.
--     Każda karta: promienie za ikoną, kołysząca się ikona, „żywa” informacja (działa / ile minut /
--     ile monet da teraz ogródek), zielony przycisk z ceną i przebiegającym błyskiem.
--   pigułka w rogu okna: twoje szczęście teraz (to samo, co w „Szansach”),
--   pasek na dole: bonusy społeczności (grupa Old Owl, znajomy na serwerze),
--   szybki przycisk „+olej” przy pasku oleju, gdy w lesie robi się ciemno,
--   karta „Zachowaj grzyby” na czarnym ekranie po zgaśnięciu latarni lub złapaniu (z paskiem czasu),
--   liczniki działającego Wysypu i mikstury szczęścia pod przyciskiem sklepu.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Localize = require(script.Parent.Localize)
local OddsPanel = require(script.Parent.OddsPanel)
local PanelKit = require(script.Parent.PanelKit)
local Purchases = require(script.Parent.Purchases)
local SideButtons = require(script.Parent.SideButtons)
local UiFx = require(script.Parent.UiFx)
local UiKit = require(script.Parent.UiKit)
local UiScale = require(script.Parent.UiScale)

local ShopPanel = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local TITLE_FONT = PanelKit.TITLE_FONT
local BODY_FONT = PanelKit.BODY_FONT
local OUTLINE = PanelKit.OUTLINE
local TEXT = PanelKit.TEXT
local MUTED = PanelKit.MUTED
local BUY = Color3.fromRGB(64, 190, 78)
local ROBUX_GREEN = Color3.fromRGB(0, 176, 111)
local SHOP_GREEN = Color3.fromRGB(58, 178, 84)
local CHIP_BG = Color3.fromRGB(50, 34, 24)
local GREEN_TEXT = PanelKit.GREEN
local GOLD_TEXT = PanelKit.GOLD
local ORANGE_TEXT = Color3.fromRGB(255, 170, 90)

local WIDTH = 880
local HEIGHT = 502
local CONTENT_W = WIDTH - 28
local CARD_GAP = 14
local CARD_H = 332

-- Wygląd karty: ikona z arkusza UiKit, kolor promieni i czy działa na cały serwer
type Look = { icon: string, accent: Color3, server: boolean }
local LOOKS: { [string]: Look } = {
	boom = { icon = "boom", accent = Color3.fromRGB(255, 200, 70), server = true },
	luck = { icon = "luck", accent = Color3.fromRGB(130, 240, 110), server = false },
	oil = { icon = "bottle", accent = Color3.fromRGB(255, 160, 70), server = false },
	harvest = { icon = "chest", accent = Color3.fromRGB(255, 222, 100), server = false },
}

-- ===== Pomocnicze =====

local function corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = if radius then UDim.new(0, radius) else UDim.new(1, 0)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = parent
	return s
end

local function shade(parent: Instance, bottom: Color3?)
	local g = Instance.new("UIGradient")
	g.Name = "Shade"
	g.Rotation = 90
	g.Color = ColorSequence.new(Color3.new(1, 1, 1), bottom or Color3.fromRGB(176, 166, 158))
	g.Parent = parent
end

local function formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function formatCoins(value: number): string
	local s = tostring(math.floor(value + 0.5))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (formatted:gsub("^ ", ""))
end

local function percentBonus(mult: number): string
	return string.format("+%d%%", math.floor((mult - 1) * 100 + 0.5))
end

-- Pigułka z tekstem o automatycznej szerokości (żywe informacje na kartach i u góry okna)
type Chip = { frame: Frame, label: TextLabel, icon: GuiObject? }
local function chip(parent: Instance, name: string, iconName: string?, height: number, textSize: number): Chip
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AutomaticSize = Enum.AutomaticSize.X
	frame.Size = UDim2.fromOffset(0, height)
	frame.BackgroundColor3 = CHIP_BG
	frame.Parent = parent
	corner(frame)
	stroke(frame, OUTLINE, 2.5)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, if iconName then height + 2 else 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = frame
	local icon: GuiObject? = nil
	if iconName then
		local made = UiKit.icon(iconName, frame, UDim2.fromOffset(height + 6, height + 6), UDim2.new(0, -height - 2, 0.5, 0), Vector2.new(0, 0.5))
		made.ZIndex = 3
		icon = made
	end
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromScale(0, 1)
	label.Font = TITLE_FONT
	label.TextSize = textSize
	label.TextColor3 = TEXT
	label.RichText = true
	label.Text = ""
	label.ZIndex = 3
	label.Parent = frame
	UiKit.outline(label, 1.5)
	return { frame = frame, label = label, icon = icon }
end

-- ===== HUD: przycisk sklepu, szybki olej, liczniki =====

local gui = Instance.new("ScreenGui")
gui.Name = "Shop"
gui.ResetOnSpawn = false
gui.DisplayOrder = 4
gui.Parent = playerGui

-- Ratunek musi być nad czarnym ekranem HUD (DisplayOrder wyżej i bez wcięcia na pasek Robloxa)
local rescueGui = Instance.new("ScreenGui")
rescueGui.Name = "Rescue"
rescueGui.ResetOnSpawn = false
rescueGui.DisplayOrder = 30
rescueGui.IgnoreGuiInset = true
rescueGui.Parent = playerGui

-- Przycisk sklepu w kolumnie pod „Ulepszeniami” (ten sam styl co Zadania i Grzybopedia).
-- ShopPanel ładuje się przed innymi oknami, więc sklep jest pierwszy w kolumnie.
local shopSide = SideButtons.add({
	name = "ShopButton",
	icon = "shop",
	color = ROBUX_GREEN,
	caption = "SHOP_TITLE",
})
UiFx.shine(shopSide.button, 4.5)

local oilButton = Instance.new("TextButton")
oilButton.Name = "QuickOil"
oilButton.Size = UDim2.fromOffset(86, 30)
oilButton.Font = TITLE_FONT
oilButton.TextScaled = true
oilButton.Visible = false
oilButton.Parent = gui
UiKit.button(oilButton, ROBUX_GREEN)
UiKit.icon("bottle", oilButton, UDim2.fromOffset(28, 28), UDim2.new(0, -26, 0.5, 0), Vector2.new(0, 0.5))
local oilPad = Instance.new("UIPadding")
oilPad.PaddingLeft = UDim.new(0, 30)
oilPad.PaddingRight = UDim.new(0, 6)
oilPad.PaddingTop = UDim.new(0, 5)
oilPad.PaddingBottom = UDim.new(0, 5)
oilPad.Parent = oilButton
local oilScale = oilButton:FindFirstChildOfClass("UIScale") :: UIScale
oilButton.Activated:Connect(function()
	Purchases.buy("oil")
end)

local timers = Instance.new("Frame")
timers.Name = "Timers"
timers.Size = UDim2.fromOffset(180, 66)
timers.BackgroundTransparency = 1
timers.Parent = gui
local timersScale = Instance.new("UIScale")
timersScale.Parent = timers
local timerLayout = Instance.new("UIListLayout")
timerLayout.Padding = UDim.new(0, 6)
timerLayout.Parent = timers
local boomPill = chip(timers, "Boom", "boom", 28, 17)
boomPill.label.TextColor3 = Color3.fromRGB(255, 210, 120)
boomPill.frame.Visible = false
local luckPill = chip(timers, "Luck", "luck", 28, 17)
luckPill.label.TextColor3 = Color3.fromRGB(160, 255, 150)
luckPill.frame.Visible = false

-- ===== Okno sklepu =====

local window = PanelKit.window({
	name = "ShopWindow",
	parent = playerGui,
	width = WIDTH,
	height = HEIGHT,
	ribbon = SHOP_GREEN,
	icon = "shop",
	pillIcon = "luck",
	pillColor = Color3.fromRGB(36, 58, 28),
	displayOrder = 7,
})
local content = window.content

-- Górny pasek: działające bonusy (albo podpowiedź) i przycisk „Szanse”
local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.BackgroundTransparency = 1
topBar.Size = UDim2.new(1, 0, 0, 36)
topBar.Position = UDim2.fromOffset(0, 4)
topBar.Parent = content

local liveRow = Instance.new("Frame")
liveRow.Name = "Live"
liveRow.BackgroundTransparency = 1
liveRow.Size = UDim2.new(1, -150, 1, 0)
liveRow.Position = UDim2.fromOffset(6, 0)
liveRow.Parent = topBar
local liveLayout = Instance.new("UIListLayout")
liveLayout.FillDirection = Enum.FillDirection.Horizontal
liveLayout.VerticalAlignment = Enum.VerticalAlignment.Center
liveLayout.Padding = UDim.new(0, 12)
liveLayout.SortOrder = Enum.SortOrder.LayoutOrder
liveLayout.Parent = liveRow
local liveBoom = chip(liveRow, "Boom", "boom", 30, 17)
liveBoom.frame.LayoutOrder = 1
liveBoom.frame.BackgroundColor3 = Color3.fromRGB(40, 70, 30)
liveBoom.label.TextColor3 = GREEN_TEXT
local liveLuck = chip(liveRow, "Luck", "luck", 30, 17)
liveLuck.frame.LayoutOrder = 2
liveLuck.frame.BackgroundColor3 = Color3.fromRGB(78, 58, 18)
liveLuck.label.TextColor3 = GOLD_TEXT
local hint = PanelKit.label(liveRow, "Hint", UDim2.new(1, 0, 0, 22), UDim2.new(), 16, MUTED, BODY_FONT)
hint.TextXAlignment = Enum.TextXAlignment.Left
hint.LayoutOrder = 3
hint.AutomaticSize = Enum.AutomaticSize.None

local oddsButton = Instance.new("TextButton")
oddsButton.Name = "Odds"
oddsButton.Size = UDim2.fromOffset(132, 38)
oddsButton.AnchorPoint = Vector2.new(1, 0.5)
oddsButton.Position = UDim2.new(1, -4, 0.5, 0)
oddsButton.Text = ""
oddsButton.Parent = topBar
local oddsStroke = UiKit.button(oddsButton, UiKit.COLORS.wood, { radius = UDim.new(0, 12), stroke = 3, gloss = true })
oddsStroke.Color = OUTLINE
local oddsText = PanelKit.label(oddsButton, "Text", UDim2.new(1, -16, 1, -12), UDim2.fromOffset(8, 6), 19, TEXT)
UiKit.outline(oddsText, 2)
oddsText.ZIndex = 4
oddsButton.Activated:Connect(function()
	UiFx.sound("bubble", 0.4)
	-- Szanse otwierają się zamiast sklepu; zamknięcie Szans (X albo obok) wraca do sklepu
	OddsPanel.open(function()
		window.setOpen(true)
	end)
end)

-- Rząd kart
local row = Instance.new("Frame")
row.Name = "Cards"
row.BackgroundTransparency = 1
row.Size = UDim2.new(1, 0, 0, CARD_H)
row.Position = UDim2.fromOffset(0, 60)
row.Parent = content
local rowLayout = Instance.new("UIListLayout")
rowLayout.FillDirection = Enum.FillDirection.Horizontal
rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
rowLayout.Padding = UDim.new(0, CARD_GAP)
rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
rowLayout.Parent = row

type Card = {
	key: string,
	root: Frame,
	body: Frame,
	scale: UIScale,
	title: TextLabel,
	desc: TextLabel,
	info: Chip,
	badge: TextLabel,
	buy: TextButton,
	price: TextLabel,
	enabled: boolean,
}
local cards: { Card } = {}

local function buildCard(order: number, key: string, width: number): Card
	local look = LOOKS[key] or LOOKS.oil
	local server = look.server

	-- Karta: przezroczysta ramka (ciemny obrys + plakietka nad krawędzią) i przycięte wnętrze
	local root = Instance.new("Frame")
	root.Name = "Card_" .. key
	root.BackgroundTransparency = 1
	root.Size = UDim2.new(0, width, 1, 0)
	root.LayoutOrder = order
	root.Parent = row
	corner(root, 22)
	stroke(root, OUTLINE, if server then 7 else 3.5)
	local scale = Instance.new("UIScale")
	scale.Parent = root

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Size = UDim2.fromScale(1, 1)
	body.BackgroundColor3 = if server then Color3.fromRGB(206, 132, 44) else PanelKit.CARD
	body.ClipsDescendants = true
	body.Parent = root
	corner(body, 22)
	shade(body, if server then Color3.fromRGB(150, 110, 90) else Color3.fromRGB(160, 150, 142))
	if server then
		UiFx.goldStroke(body, 4)
		UiFx.stripes(body, Color3.fromRGB(255, 240, 200), 0.88)
	end

	-- Ikona w kole, za nią promienie i poświata
	local ICON_Y = 88
	UiFx.rays(body, {
		size = 230,
		color = look.accent,
		count = 7,
		speed = if server then 34 else 14,
		transparency = if server then 0.3 else 0.62,
		position = UDim2.new(0.5, 0, 0, ICON_Y),
	})
	UiFx.glow(body, 150, look.accent, if server then 0.4 else 0.25).Position = UDim2.new(0.5, 0, 0, ICON_Y)
	local circle = Instance.new("Frame")
	circle.Name = "IconCircle"
	circle.Size = UDim2.fromOffset(104, 104)
	circle.AnchorPoint = Vector2.new(0.5, 0.5)
	circle.Position = UDim2.new(0.5, 0, 0, ICON_Y)
	circle.BackgroundColor3 = Color3.fromRGB(66, 42, 28)
	circle.ZIndex = 2
	circle.Parent = body
	corner(circle)
	stroke(circle, OUTLINE, 3.5)
	shade(circle, Color3.fromRGB(120, 110, 104))
	local icon = UiKit.icon(look.icon, circle, UDim2.fromOffset(84, 84), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	icon.ZIndex = 3
	UiFx.bob(icon, 4, 2.2 + order * 0.15)

	local title = PanelKit.label(body, "Title", UDim2.new(1, -18, 0, 48), UDim2.fromOffset(9, 146), 23, TEXT, TITLE_FONT)
	title.TextWrapped = true
	title.ZIndex = 3
	UiKit.outline(title, 2.5)
	UiFx.textGradient(title, Color3.new(1, 1, 1), Color3.fromRGB(255, 226, 150))

	local desc = PanelKit.label(body, "Desc", UDim2.new(1, -22, 0, 32), UDim2.fromOffset(11, 194), 13, if server then Color3.fromRGB(255, 240, 214) else MUTED, BODY_FONT)
	desc.TextWrapped = true
	desc.ZIndex = 3

	local info = chip(body, "Info", nil, 26, 15)
	info.frame.AnchorPoint = Vector2.new(0.5, 0)
	-- Pasek informacji kończy się na 256 px, przycisk zaczyna na 268 px (332 - 12 - 52)
	info.frame.Position = UDim2.new(0.5, 0, 0, 230)
	info.frame.ZIndex = 3

	local buy = Instance.new("TextButton")
	buy.Name = "Buy"
	buy.Text = ""
	buy.AnchorPoint = Vector2.new(0.5, 1)
	buy.Position = UDim2.new(0.5, 0, 1, -12)
	buy.Size = UDim2.new(1, -22, 0, 52)
	buy.ZIndex = 3
	buy.Parent = body
	local buyStroke = UiKit.button(buy, BUY, { gloss = true, radius = UDim.new(0, 15), stroke = 3 })
	buyStroke.Color = OUTLINE
	local price = PanelKit.label(buy, "Price", UDim2.new(1, -14, 1, -14), UDim2.fromOffset(7, 7), 28, Color3.new(1, 1, 1), TITLE_FONT)
	price.ZIndex = 5
	UiKit.outline(price, 2.5)
	UiFx.shine(buy, 2.4 + order * 0.4)

	-- Plakietka nad krawędzią karty: „CAŁY SERWER” (złota, kołysze się) albo „TYLKO TY”
	local badgeFrame = Instance.new("Frame")
	badgeFrame.Name = "Badge"
	badgeFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	badgeFrame.Position = UDim2.new(0.5, 0, 0, 0)
	badgeFrame.AutomaticSize = Enum.AutomaticSize.X
	badgeFrame.Size = UDim2.fromOffset(0, 28)
	badgeFrame.BackgroundColor3 = if server then PanelKit.GOLD else Color3.fromRGB(70, 48, 32)
	badgeFrame.Rotation = if server then -4 else 0
	badgeFrame.ZIndex = 6
	badgeFrame.Parent = root
	corner(badgeFrame, 10)
	stroke(badgeFrame, OUTLINE, 3)
	if server then
		shade(badgeFrame, Color3.fromRGB(230, 170, 60))
		UiFx.wiggle(badgeFrame, 3, 2.2)
	end
	local badgePad = Instance.new("UIPadding")
	badgePad.PaddingLeft = UDim.new(0, 12)
	badgePad.PaddingRight = UDim.new(0, 12)
	badgePad.Parent = badgeFrame
	local badge = Instance.new("TextLabel")
	badge.Name = "Text"
	badge.BackgroundTransparency = 1
	badge.AutomaticSize = Enum.AutomaticSize.X
	badge.Size = UDim2.fromScale(0, 1)
	badge.Font = TITLE_FONT
	badge.TextSize = 15
	badge.TextColor3 = if server then OUTLINE else MUTED
	badge.ZIndex = 7
	badge.Parent = badgeFrame

	local card: Card = {
		key = key,
		root = root,
		body = body,
		scale = scale,
		title = title,
		desc = desc,
		info = info,
		badge = badge,
		buy = buy,
		price = price,
		enabled = true,
	}

	-- Najechanie na kartę: lekkie powiększenie całej karty
	body.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.035 }):Play()
	end)
	body.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.18), { Scale = 1 }):Play()
	end)
	buy.Activated:Connect(function()
		if not card.enabled then
			UiFx.shake(body)
			UiFx.sound("warn", 0.3)
			return
		end
		UiFx.sound("ping", 0.5, 1.1)
		UiKit.burst(window.gui, buy.AbsolutePosition + buy.AbsoluteSize / 2, 12)
		Purchases.buy(key)
	end)
	return card
end

-- Karty tylko dla produktów, które da się kupić (z numerem albo w Studio); zestaw się nie zmienia
do
	local keys = {}
	for _, key in Config.ShopOrder do
		if Purchases.available(key) then
			table.insert(keys, key)
		end
	end
	local count = math.max(#keys, 1)
	local width = math.min(220, math.floor((CONTENT_W - CARD_GAP * (count - 1)) / count))
	for order, key in keys do
		table.insert(cards, buildCard(order, key, width))
	end
end

-- Dolny pasek: bonusy społeczności (grupa, znajomy)
local footer = Instance.new("Frame")
footer.Name = "Social"
footer.Size = UDim2.new(1, 0, 0, 46)
footer.AnchorPoint = Vector2.new(0, 1)
footer.Position = UDim2.new(0, 0, 1, -6)
footer.BackgroundColor3 = PanelKit.BG_DARK
footer.Parent = content
corner(footer, 16)
stroke(footer, OUTLINE, 3)
local owlIcon = UiKit.icon("owl", footer, UDim2.fromOffset(40, 40), UDim2.new(0, 8, 0.5, 0), Vector2.new(0, 0.5))
owlIcon.ZIndex = 3
local social = PanelKit.label(footer, "Text", UDim2.new(1, -70, 1, -16), UDim2.fromOffset(56, 8), 17, MUTED, BODY_FONT)
social.TextXAlignment = Enum.TextXAlignment.Left

-- ===== Karta „Zachowaj grzyby” (czarny ekran) =====

local rescue = Instance.new("TextButton")
rescue.Name = "RescueCard"
rescue.Text = ""
rescue.AutoButtonColor = false
rescue.BackgroundTransparency = 1
rescue.Size = UDim2.fromOffset(470, 104)
rescue.AnchorPoint = Vector2.new(0.5, 0)
rescue.Position = UDim2.new(0.5, 0, 0.58, 0)
rescue.Visible = false
rescue.Parent = rescueGui
local rescueScale = Instance.new("UIScale")
rescueScale.Parent = rescue
-- Pulsująca złota poświata pod kartą (osobna warstwa: dzieci rysują się nad rodzicem)
local rescueHalo = Instance.new("Frame")
rescueHalo.Name = "Halo"
rescueHalo.AnchorPoint = Vector2.new(0.5, 0.5)
rescueHalo.Position = UDim2.fromScale(0.5, 0.5)
rescueHalo.Size = UDim2.new(1, 28, 1, 28)
rescueHalo.BackgroundColor3 = PanelKit.GOLD
rescueHalo.BackgroundTransparency = 0.72
rescueHalo.ZIndex = 1
rescueHalo.Active = false
rescueHalo.Parent = rescue
corner(rescueHalo, 34)
TweenService:Create(rescueHalo, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0.92 }):Play()
local rescueBody = Instance.new("Frame")
rescueBody.Name = "Body"
rescueBody.Size = UDim2.fromScale(1, 1)
rescueBody.BackgroundColor3 = Color3.fromRGB(128, 84, 44)
rescueBody.ZIndex = 2
rescueBody.Active = false
rescueBody.Parent = rescue
corner(rescueBody, 22)
shade(rescueBody, Color3.fromRGB(150, 130, 120))
UiFx.goldStroke(rescueBody, 4)
UiFx.stripes(rescueBody, Color3.fromRGB(255, 236, 190), 0.9)
-- Pulsuje samo wnętrze (własna UIScale), a skala ekranu i wskoczenie są na zewnętrznej ramce
UiFx.pulse(rescueBody, 0.02, 1.3)

local rescueIcon = UiKit.icon("rescue", rescueBody, UDim2.fromOffset(78, 78), UDim2.new(0, 12, 0.5, 0), Vector2.new(0, 0.5))
rescueIcon.ZIndex = 4
UiFx.bob(rescueIcon, 3, 1.4)
local rescueTitle = PanelKit.label(rescueBody, "Title", UDim2.new(1, -250, 0, 34), UDim2.fromOffset(98, 12), 30, TEXT, TITLE_FONT)
rescueTitle.TextXAlignment = Enum.TextXAlignment.Left
rescueTitle.ZIndex = 4
UiKit.outline(rescueTitle, 3)
UiFx.textGradient(rescueTitle, Color3.new(1, 1, 1), Color3.fromRGB(255, 226, 150))
local rescueSub = PanelKit.label(rescueBody, "Sub", UDim2.new(1, -250, 0, 20), UDim2.fromOffset(98, 48), 16, Color3.fromRGB(255, 236, 200), BODY_FONT)
rescueSub.TextXAlignment = Enum.TextXAlignment.Left
rescueSub.ZIndex = 4
local rescueBar = Instance.new("Frame")
rescueBar.Name = "Timer"
rescueBar.Size = UDim2.new(1, -250, 0, 14)
rescueBar.Position = UDim2.fromOffset(98, 76)
rescueBar.BackgroundColor3 = OUTLINE
rescueBar.ZIndex = 4
rescueBar.Parent = rescueBody
corner(rescueBar)
local rescueFill = Instance.new("Frame")
rescueFill.Name = "Fill"
rescueFill.Size = UDim2.fromScale(1, 1)
rescueFill.BackgroundColor3 = Color3.new(1, 1, 1)
rescueFill.ZIndex = 5
rescueFill.Parent = rescueBar
corner(rescueFill)
local fillColor = Instance.new("UIGradient")
fillColor.Color = ColorSequence.new(Color3.fromRGB(255, 226, 90), Color3.fromRGB(255, 140, 40))
fillColor.Parent = rescueFill

-- Cena: wygląda jak zielony przycisk, ale klika się całą kartę
local rescuePrice = Instance.new("Frame")
rescuePrice.Name = "Price"
rescuePrice.Size = UDim2.fromOffset(132, 64)
rescuePrice.AnchorPoint = Vector2.new(1, 0.5)
rescuePrice.Position = UDim2.new(1, -16, 0.5, 0)
rescuePrice.BackgroundColor3 = BUY
rescuePrice.ZIndex = 4
rescuePrice.Parent = rescueBody
corner(rescuePrice, 16)
stroke(rescuePrice, OUTLINE, 3)
shade(rescuePrice)
UiFx.shine(rescuePrice, 1.6)
local rescuePriceText = PanelKit.label(rescuePrice, "Text", UDim2.new(1, -14, 1, -16), UDim2.fromOffset(7, 8), 30, Color3.new(1, 1, 1), TITLE_FONT)
rescuePriceText.ZIndex = 6
UiKit.outline(rescuePriceText, 2.5)
rescue.Activated:Connect(function()
	UiFx.sound("ping", 0.6, 1.1)
	Purchases.buy("rescue")
end)

local rescueToken = 0

-- ===== Logika =====

local boomUntil = 0
local luckUntil = 0
local oilFraction = 1
local inDanger = false

-- Własny ogródek: ile grzybów rośnie i ile zarabia na minutę (atrybuty od GardenService)
local function ownGarden(): (number, number)
	for _, rack in CollectionService:GetTagged("GardenPlot") do
		if rack:GetAttribute("OwnerUserId") == player.UserId then
			local count = rack:GetAttribute("Count")
			local rate = rack:GetAttribute("Rate")
			return if typeof(count) == "number" then count else 0, if typeof(rate) == "number" then rate else 0
		end
	end
	return 0, 0
end

local function setInfo(card: Card, text: string, color: Color3)
	card.info.label.Text = text
	card.info.label.TextColor3 = color
end

local function refreshCards(now: number)
	local planted, rate = ownGarden()
	for _, card in cards do
		local def = Config.Products[card.key]
		card.title.Text = Localize.t(def.key)
		card.desc.Text = Localize.t(def.key .. "_DESC")
		card.badge.Text = Localize.t(if LOOKS[card.key] and LOOKS[card.key].server then "SHOP_SERVER" else "SHOP_ONLY_YOU")
		card.price.Text = Purchases.priceText(card.key)
		local enabled = true
		if card.key == "boom" then
			if boomUntil > now then
				setInfo(card, "✓ " .. Localize.t("SHOP_ACTIVE", { formatTime(boomUntil - now) }), GREEN_TEXT)
			else
				setInfo(card, "⏱ " .. Localize.t("SHOP_MINUTES", { math.floor(Config.Boom.seconds / 60) }), TEXT)
			end
		elseif card.key == "luck" then
			if luckUntil > now then
				setInfo(card, "✓ " .. Localize.t("SHOP_ACTIVE", { formatTime(luckUntil - now) }), GOLD_TEXT)
			else
				setInfo(card, "⏱ " .. Localize.t("SHOP_MINUTES", { math.floor(Config.LuckPotion.seconds / 60) }), TEXT)
			end
		elseif card.key == "oil" then
			local pct = math.floor(oilFraction * 100 + 0.5)
			setInfo(card, "🏮 " .. Localize.t("SHOP_OIL_NOW", { pct }), if pct < 40 then ORANGE_TEXT else TEXT)
		elseif card.key == "harvest" then
			enabled = planted > 0
			if enabled then
				setInfo(card, Localize.t("SHOP_HARVEST_NOW", { formatCoins(rate * Config.Garden.harvestMinutes) }), GOLD_TEXT)
			else
				setInfo(card, Localize.t("SHOP_NEED_PLANTS"), ORANGE_TEXT)
			end
		end
		if enabled ~= card.enabled then
			card.enabled = enabled
			UiKit.recolor(card.buy, if enabled then BUY else UiKit.COLORS.locked)
			local s = card.buy:FindFirstChildOfClass("UIStroke")
			if s then
				s.Color = OUTLINE
			end
		end
	end
end

local function refreshWindow()
	local now = os.time()
	window.title.Text = Localize.t("SHOP_TITLE")
	oddsText.Text = "% " .. Localize.t("SHOP_ODDS")
	window.pillText.Text = OddsPanel.luckText()
	-- Działające bonusy u góry; bez nich podpowiedź
	liveBoom.frame.Visible = boomUntil > now
	liveBoom.label.Text = Localize.t("SHOP_BOOM_TIMER", { formatTime(boomUntil - now) })
	liveLuck.frame.Visible = luckUntil > now
	liveLuck.label.Text = Localize.t("SHOP_LUCK_TIMER", { formatTime(luckUntil - now) })
	hint.Visible = not (liveBoom.frame.Visible or liveLuck.frame.Visible)
	hint.Text = Localize.t("SHOP_HINT")
	refreshCards(now)
	-- Bonusy społeczności: zielone = masz, złote = do zdobycia
	local member = player:GetAttribute("OwlMember") == true
	local friend = player:GetAttribute("FriendBonus") == true
	local owl = Localize.t(if member then "SHOP_OWL_ON" else "SHOP_OWL_OFF", { percentBonus(Config.Community.luck) })
	local pal = Localize.t(if friend then "SHOP_FRIEND_ON" else "SHOP_FRIEND_OFF", { percentBonus(Config.Community.friendLuck) })
	social.Text = string.format(
		'<font color="%s">%s</font>   <font color="#8A7258">·</font>   <font color="%s">%s</font>',
		UiFx.hex(if member then GREEN_TEXT else GOLD_TEXT),
		owl,
		UiFx.hex(if friend then GREEN_TEXT else GOLD_TEXT),
		pal
	)
end

local function refreshHud()
	oilButton.Text = Purchases.priceText("oil")
	shopSide.root.Visible = #cards > 0
end

local devShown = false

local function layout()
	local scale = UiScale.get()
	for _, s in { oilScale, timersScale, rescueScale } do
		s:SetAttribute("Base", scale) -- UiKit i UiFx wracają do tej skali po wciśnięciu / pulsie
		s.Scale = scale
	end
	-- Pod rzędem przycisku języka (UiScale.rowBottom); u deweloperów niżej, pod przyciskiem 🛠 DEV
	local y = UiScale.rowBottom() + 6
	timers.Position = UDim2.fromOffset(12, y + (if devShown then math.floor(36 * scale) + 4 else 0))
	-- Obok paska oleju (środek u góry, pasek ma 300 px szerokości)
	oilButton.Position = UDim2.new(0.5, math.floor(156 * scale), 0, 8 + math.floor(34 * scale))
end
UiScale.onChanged(layout)

function ShopPanel.update(state: any, safeZone: boolean)
	OddsPanel.update(state)
	if (state.dev == true) ~= devShown then
		devShown = state.dev == true
		layout()
	end
	boomUntil = state.boomUntil or 0
	luckUntil = state.luckUntil or 0
	oilFraction = if state.oilMax and state.oilMax > 0 then state.oil / state.oilMax else 1
	inDanger = not safeZone
	oilButton.Visible = Purchases.available("oil") and inDanger and oilFraction < 0.4
end

-- Na czarnym ekranie: karta „Zachowaj grzyby” z wartością koszyka, ceną i paskiem czasu
function ShopPanel.offerRescue(value: number, seconds: number)
	if not Purchases.available("rescue") or value <= 0 then
		return
	end
	rescueToken += 1
	local token = rescueToken
	rescueTitle.Text = Localize.t("SHOP_RESCUE")
	rescueSub.Text = Localize.t("SHOP_RESCUE_SUB", { formatCoins(value) })
	rescuePriceText.Text = Purchases.priceText("rescue")
	rescue.Visible = true
	UiFx.popIn(rescueScale, (rescueScale:GetAttribute("Base") :: number?) or 1, 0.4)
	UiFx.sound("whoosh", 0.4)
	rescueFill.Size = UDim2.fromScale(1, 1)
	TweenService:Create(rescueFill, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) }):Play()
	task.delay(seconds, function()
		if rescueToken == token then
			rescue.Visible = false
		end
	end)
end

function ShopPanel.hideRescue()
	rescueToken += 1
	rescue.Visible = false
end

shopSide.onActivated(function()
	if window.isOpen() then
		window.setOpen(false)
		return
	end
	refreshWindow()
	window.setOpen(true)
end)
window.onToggle(function(open)
	if not open then
		return
	end
	UiFx.sound("whoosh", 0.35)
	-- Karty wskakują po kolei
	for i, card in cards do
		UiFx.popIn(card.scale, 1, 0.55, 0.06 * i)
	end
end)
Localize.onChanged(function()
	refreshHud()
	refreshWindow()
end)
refreshHud()
refreshWindow()

-- Liczniki raz na ułamek sekundy
task.spawn(function()
	while true do
		local now = os.time()
		boomPill.frame.Visible = boomUntil > now
		if boomPill.frame.Visible then
			boomPill.label.Text = Localize.t("SHOP_BOOM_TIMER", { formatTime(boomUntil - now) })
		end
		luckPill.frame.Visible = luckUntil > now
		if luckPill.frame.Visible then
			luckPill.label.Text = Localize.t("SHOP_LUCK_TIMER", { formatTime(luckUntil - now) })
		end
		if window.isOpen() then
			refreshWindow()
		end
		task.wait(0.25)
	end
end)

return ShopPanel
