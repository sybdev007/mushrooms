--!strict
-- Interfejs budowany kodem, projektowany najpierw pod telefon.
-- Styl: ciemne drewno z bursztynową obwódką, kreskówkowa czcionka, ikony z Figmy (UiKit),
-- cukierkowe przyciski z połyskiem i wciśnięciem.
-- Duży okrągły przycisk ZBIERZ obok przycisku skoku, panel chatki na dole ekranu.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Localize = require(script.Parent.Localize)
local UiKit = require(script.Parent.UiKit)
local PanelKit = require(script.Parent.PanelKit)
local UiScale = require(script.Parent.UiScale)

export type State = {
	coins: number,
	oil: number,
	oilMax: number,
	basketCount: number,
	basketMax: number,
	basketValue: number,
	lanternRange: number,
	zone: number,
	upgrades: { [string]: number },
}

local Hud = {}

local THEME = {
	panel = Color3.fromRGB(40, 28, 20),
	panelTransparency = 0.12,
	stroke = Color3.fromRGB(200, 146, 74),
	text = Color3.fromRGB(252, 238, 210),
	muted = Color3.fromRGB(214, 188, 150),
	accent = Color3.fromRGB(255, 202, 92),
	card = Color3.fromRGB(70, 104, 54),
	cardLocked = Color3.fromRGB(76, 64, 54),
	sell = Color3.fromRGB(214, 150, 50),
	oil = Color3.fromRGB(255, 170, 56),
	oilLight = Color3.fromRGB(255, 226, 120),
	oilLow = Color3.fromRGB(232, 64, 44),
	pick = Color3.fromRGB(236, 146, 46),
	gold = Color3.fromRGB(255, 214, 70),
	warn = Color3.fromRGB(255, 120, 90),
}
local TITLE_FONT = Enum.Font.FredokaOne
local BODY_FONT = Enum.Font.GothamBold

-- Nazwa ikony z arkusza UiKit dla każdego ulepszenia
local UPGRADE_ICONS = {
	lantern = "lantern",
	oil = "oil",
	basket = "basket",
	boots = "boots",
	lock = "lock",
	beds = "beds",
	fertilizer = "fertilizer",
	knife = "knife",
	crystal = "crystal",
	pack = "pack",
	rushwick = "rushwick",
	creel = "creel",
}

-- Karty w panelu: najpierw sklep w chatce, potem w obozowisku. Panel pokazuje tylko karty bieżącego sklepu.
local ALL_UPGRADES: { string } = table.clone(Config.UpgradeOrder)
for _, id in Config.CaveUpgradeOrder do
	table.insert(ALL_UPGRADES, id)
end
for _, id in Config.SwampUpgradeOrder do
	table.insert(ALL_UPGRADES, id)
end

local callbacks = {
	pick = {} :: { () -> () },
	buy = {} :: { (string) -> () },
}

local lastState: State? = nil

-- ===== Pomocnicze =====

local function corner(parent: Instance, radius: UDim?)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or UDim.new(0, 12)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3?, thickness: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color or THEME.stroke
	s.Thickness = thickness or 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function panel(name: string, parent: Instance, size: UDim2, position: UDim2, anchor: Vector2?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = position
	f.AnchorPoint = anchor or Vector2.zero
	f.BackgroundColor3 = THEME.panel
	f.BackgroundTransparency = THEME.panelTransparency
	f.Parent = parent
	corner(f)
	stroke(f)
	return f
end

local function label(name: string, parent: Instance, size: UDim2, position: UDim2, font: Enum.Font, maxSize: number): TextLabel
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

local function pop(target: GuiObject, amount: number?)
	local scale = target:FindFirstChildOfClass("UIScale")
	if not scale then
		local newScale = Instance.new("UIScale")
		newScale.Parent = target
		scale = newScale
	end
	local s = scale :: UIScale
	-- Panele mają skalę zależną od ekranu (atrybut Base), podskok liczymy względem niej
	local base = (s:GetAttribute("Base") :: number?) or 1
	s.Scale = base * (1 + (amount or 0.25))
	TweenService:Create(s, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = base }):Play()
end

local function bar(parent: Instance, size: UDim2, position: UDim2, color: Color3): (Frame, Frame)
	local back = Instance.new("Frame")
	back.Size = size
	back.Position = position
	back.BackgroundColor3 = Color3.fromRGB(20, 14, 10)
	back.BackgroundTransparency = 0.2
	back.ClipsDescendants = true
	back.Parent = parent
	corner(back, UDim.new(1, 0))
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = back
	corner(fill, UDim.new(1, 0))
	return back, fill
end

local function formatCoins(value: number): string
	local s = tostring(math.floor(value + 0.5))
	-- Spacje co trzy cyfry: 12 345
	local formatted = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (formatted:gsub("^ ", ""))
end

-- ===== Budowa interfejsu =====

local gui = Instance.new("ScreenGui")
gui.Name = "Hud"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

-- Monety i koszyk (lewy górny róg)
local stats = panel("Stats", gui, UDim2.new(0, 196, 0, 80), UDim2.new(0, 12, 0, 8))
local coinsIcon = UiKit.icon("coin", stats, UDim2.new(0, 34, 0, 34), UDim2.new(0, 8, 0, 4))
local coinsLabel = label("Coins", stats, UDim2.new(1, -52, 0, 30), UDim2.new(0, 46, 0, 6), TITLE_FONT, 26)
coinsLabel.TextXAlignment = Enum.TextXAlignment.Left
coinsLabel.TextColor3 = THEME.accent
local basketIcon = UiKit.icon("basket", stats, UDim2.new(0, 32, 0, 32), UDim2.new(0, 9, 0, 40))
local basketLabel = label("Basket", stats, UDim2.new(0, 60, 0, 22), UDim2.new(0, 46, 0, 40), TITLE_FONT, 20)
basketLabel.TextXAlignment = Enum.TextXAlignment.Left
local _, basketFill = bar(stats, UDim2.new(1, -112, 0, 10), UDim2.new(0, 104, 0, 47), Color3.fromRGB(150, 196, 90))

local languageButton = Instance.new("TextButton")
languageButton.Name = "Language"
-- Rząd pod panelem monet ma własną, większą wysokość (UiScale.ROW_HEIGHT), żeby dało się trafić palcem
languageButton.Size = UDim2.new(0, 88, 0, UiScale.ROW_HEIGHT)
-- Pod panelem monet, bo prawy górny róg zajmuje lista graczy z monetami
languageButton.Position = UDim2.new(0, 12, 0, 96)
languageButton.Font = TITLE_FONT
languageButton.TextSize = 22
languageButton.TextXAlignment = Enum.TextXAlignment.Right
languageButton.Parent = gui
UiKit.button(languageButton, UiKit.COLORS.wood, { gloss = true })
UiKit.icon("globe", languageButton, UDim2.new(0, 32, 0, 32), UDim2.new(0, 6, 0.5, 0), Vector2.new(0, 0.5))
local languagePadding = Instance.new("UIPadding")
languagePadding.PaddingRight = UDim.new(0, 11)
languagePadding.Parent = languageButton

-- Strefa i pasek oleju (środek u góry)
local top = Instance.new("Frame")
top.Name = "Top"
top.Size = UDim2.new(0, 300, 0, 66)
top.Position = UDim2.new(0.5, 0, 0, 8)
top.AnchorPoint = Vector2.new(0.5, 0)
top.BackgroundTransparency = 1
top.Parent = gui

local zonePill = panel("Zone", top, UDim2.new(0, 220, 0, 28), UDim2.new(0.5, 0, 0, 0), Vector2.new(0.5, 0))
local zoneLabel = label("Text", zonePill, UDim2.new(1, -16, 1, -4), UDim2.new(0, 8, 0, 2), TITLE_FONT, 20)

local oilPanel = panel("Oil", top, UDim2.new(1, 0, 0, 32), UDim2.new(0, 0, 0, 34))
UiKit.icon("lantern", oilPanel, UDim2.new(0, 30, 0, 30), UDim2.new(0, 4, 0, 1))
local oilBack, oilFill = bar(oilPanel, UDim2.new(1, -46, 0, 18), UDim2.new(0, 38, 0, 7), THEME.oil)
local oilGradient = Instance.new("UIGradient")
oilGradient.Color = ColorSequence.new(THEME.oilLight, THEME.oil)
oilGradient.Parent = oilFill
local oilText = label("Text", oilBack, UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, 0), BODY_FONT, 14)
oilText.ZIndex = 3
local oilTextStroke = Instance.new("UIStroke")
oilTextStroke.Thickness = 1.5
oilTextStroke.Color = Color3.fromRGB(50, 24, 10)
oilTextStroke.Parent = oilText
local oilStroke = oilPanel:FindFirstChildOfClass("UIStroke") :: UIStroke

-- Okrągły przycisk ZBIERZ obok mobilnego przycisku skoku. Skok na dużych ekranach zajmuje
-- ok. 50-170 px od prawej i 90-210 px od dołu, więc stajemy obok, a nie nad nim.
local pickButton = Instance.new("TextButton")
pickButton.Name = "Pick"
pickButton.Size = UDim2.new(0, 112, 0, 112)
pickButton.Position = UDim2.new(1, -190, 1, -40)
pickButton.AnchorPoint = Vector2.new(1, 1)
pickButton.Text = ""
pickButton.Parent = gui
local pickStroke = UiKit.button(pickButton, THEME.pick, { gloss = true, radius = UDim.new(0.5, 0), stroke = 4 })
pickStroke.Color = Color3.fromRGB(255, 240, 200)
local pickScale = pickButton:FindFirstChildOfClass("UIScale") :: UIScale
-- Rozmiary w ułamkach, bo cały przycisk zmienia wielkość razem z ekranem
local pickIcon = UiKit.icon("mushroom", pickButton, UDim2.new(0.6, 0, 0.6, 0), UDim2.new(0.5, 0, 0.06, 0), Vector2.new(0.5, 0))
local pickCaption = label("Caption", pickButton, UDim2.new(1, -12, 0.2, 0), UDim2.new(0, 6, 0.66, 0), TITLE_FONT, 20)
local pickCaptionStroke = Instance.new("UIStroke")
pickCaptionStroke.Thickness = 1.5
pickCaptionStroke.Color = Color3.fromRGB(90, 40, 10)
pickCaptionStroke.Parent = pickCaption

-- ===== Ulepszenia: przycisk z prawej strony i panel z kartami =====
-- Przycisk: fioletowa pigułka z dużą strzałką wystającą w lewo, klawiszem [R] w rogu i czerwoną
-- kropką z liczbą ulepszeń, na które gracza stać. Po najechaniu strzałka rośnie i robi obrót,
-- a po przycisku przelatuje błysk. W spoczynku strzałka lekko podskakuje.
-- Panel: okno z ciemnego drewna z grubą obwódką, wstążka z tytułem, monety w lewym rogu, zamykanie w prawym.
-- Każde ulepszenie to wysoka kolorowa karta: duża ikona, opis, kropki poziomów, wartość „x1 » x1.25”
-- i przycisk z ceną. Najechanie unosi kartę, kliknięcie powiększa ikonę, zakup kręci nią i sypie iskry.

-- Tło okna jak w innych oknach gry (PanelKit): ciemne drewno; kremowe wyglądało w grze na białe
local CREAM_LINE = PanelKit.LINE
local OUTLINE = UiKit.OUTLINE
local VIOLET = Color3.fromRGB(140, 86, 236)
local BUY_GREEN = Color3.fromRGB(54, 190, 92)
local BUY_RED = Color3.fromRGB(214, 84, 66)
local BUY_GOLD = Color3.fromRGB(246, 182, 40)

-- Kolor karty każdego ulepszenia
local UPGRADE_COLORS: { [string]: Color3 } = {
	lantern = Color3.fromRGB(255, 160, 40),
	oil = Color3.fromRGB(232, 84, 64),
	basket = Color3.fromRGB(198, 132, 70),
	boots = Color3.fromRGB(64, 148, 240),
	knife = Color3.fromRGB(104, 124, 168),
	beds = Color3.fromRGB(70, 182, 84),
	fertilizer = Color3.fromRGB(138, 196, 56),
	lock = Color3.fromRGB(156, 96, 222),
	crystal = Color3.fromRGB(56, 196, 228),
	pack = Color3.fromRGB(122, 142, 72),
	rushwick = Color3.fromRGB(52, 164, 142),
	creel = Color3.fromRGB(172, 112, 62),
}
-- Jak pokazać wartość statystyki: mnożnik (x1.25), dodatek (+4) albo sekundy (3s)
local VALUE_PREFIX: { [string]: string } = { fertilizer = "x", knife = "x", crystal = "x", rushwick = "x", pack = "+", creel = "+" }
local VALUE_SUFFIX: { [string]: string } = { lock = "s" }

local function number(value: number): string
	if math.abs(value - math.round(value)) < 0.001 then
		return tostring(math.round(value))
	end
	local text = string.format("%.2f", value):gsub("0+$", "")
	return text
end

local function valueText(id: string, level: number): string
	local def = Config.Upgrades[id]
	local function one(at: number): string
		return (VALUE_PREFIX[id] or "") .. number(Economy.upgradeStat(id, at)) .. (VALUE_SUFFIX[id] or "")
	end
	if level >= def.maxLevel then
		return one(level)
	end
	return one(level) .. "  »  " .. one(level + 1)
end

-- Przycisk „Ulepszenia”: pojemnik (skalowany razem z ekranem) z przyciskiem, ikoną i plakietkami
local upgradeRoot = Instance.new("Frame")
upgradeRoot.Name = "UpgradesButton"
upgradeRoot.Size = UDim2.fromOffset(196, 60)
upgradeRoot.AnchorPoint = Vector2.new(1, 0.5)
upgradeRoot.Position = UDim2.new(1, -16, 0.42, 0)
upgradeRoot.BackgroundTransparency = 1
upgradeRoot.Parent = gui

local upgradeButton = Instance.new("TextButton")
upgradeButton.Name = "Button"
upgradeButton.Size = UDim2.fromScale(1, 1)
upgradeButton.Text = ""
upgradeButton.ClipsDescendants = true
upgradeButton.Parent = upgradeRoot
local upgradeStroke = UiKit.button(upgradeButton, VIOLET, { stroke = 3, radius = UDim.new(0, 16), gloss = true })
upgradeStroke.Color = OUTLINE
local upgradeCaption = label("Caption", upgradeButton, UDim2.new(1, -72, 0.7, 0), UDim2.new(0, 64, 0.15, 0), TITLE_FONT, 26)
upgradeCaption.TextXAlignment = Enum.TextXAlignment.Left
upgradeCaption.ZIndex = 3
UiKit.outline(upgradeCaption, 2.5)

-- Duża strzałka wystaje w lewo poza przycisk
local upgradeIcon = UiKit.icon("upgrade", upgradeRoot, UDim2.fromOffset(74, 74), UDim2.new(0, -14, 0.5, -4), Vector2.new(0, 0.5))
upgradeIcon.ZIndex = 5
local upgradeIconScale = Instance.new("UIScale")
upgradeIconScale.Parent = upgradeIcon
local iconRest = upgradeIcon.Position
TweenService:Create(upgradeIcon, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
	Position = iconRest + UDim2.fromOffset(0, -5),
}):Play()

-- Klawisz [R] w lewym górnym rogu (tylko gdy jest klawiatura)
local keycap = Instance.new("Frame")
keycap.Name = "Keycap"
keycap.Size = UDim2.fromOffset(30, 30)
keycap.Position = UDim2.fromOffset(-22, -16)
keycap.Rotation = -10
keycap.BackgroundColor3 = Color3.fromRGB(250, 250, 250)
keycap.ZIndex = 6
keycap.Parent = upgradeRoot
corner(keycap, UDim.new(0, 8))
stroke(keycap, OUTLINE, 2.5)
local keyShade = Instance.new("UIGradient")
keyShade.Rotation = 90
keyShade.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 205))
keyShade.Parent = keycap
local keyLabel = label("Key", keycap, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), TITLE_FONT, 20)
keyLabel.Text = "R"
keyLabel.TextColor3 = OUTLINE
keyLabel.ZIndex = 7
keycap.Visible = UserInputService.KeyboardEnabled

-- Czerwona kropka: na ile ulepszeń gracza stać
local badge = Instance.new("Frame")
badge.Name = "Badge"
badge.Size = UDim2.fromOffset(28, 28)
badge.AnchorPoint = Vector2.new(0.5, 0.5)
badge.Position = UDim2.new(1, -4, 0, 2)
badge.BackgroundColor3 = Color3.fromRGB(236, 52, 52)
badge.ZIndex = 7
badge.Visible = false
badge.Parent = upgradeRoot
corner(badge, UDim.new(1, 0))
stroke(badge, Color3.new(1, 1, 1), 2.5)
local badgeLabel = label("Count", badge, UDim2.new(1, -6, 1, -6), UDim2.fromOffset(3, 3), TITLE_FONT, 18)
badgeLabel.ZIndex = 8
local badgeScale = Instance.new("UIScale")
badgeScale.Parent = badge
TweenService:Create(badgeScale, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.15 }):Play()

local hoverTweens: { Tween } = {}
local function stopHover()
	for _, tween in hoverTweens do
		tween:Cancel()
	end
	table.clear(hoverTweens)
end
-- Ikona rośnie (bez obracania), po zjechaniu wraca
local function hoverIn()
	stopHover()
	upgradeIcon.Rotation = 0
	local grow = TweenService:Create(upgradeIconScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.25 })
	table.insert(hoverTweens, grow)
	grow:Play()
	UiKit.sweep(upgradeButton)
end
local function hoverOut()
	stopHover()
	local shrink = TweenService:Create(upgradeIconScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad), { Scale = 1 })
	table.insert(hoverTweens, shrink)
	shrink:Play()
	upgradeIcon.Rotation = 0
end
upgradeButton.MouseEnter:Connect(hoverIn)
upgradeButton.MouseLeave:Connect(hoverOut)

-- Przyciemnienie za panelem (kliknięcie obok zamyka panel)
local upgradeDim = Instance.new("TextButton")
upgradeDim.Name = "UpgradeDim"
upgradeDim.Size = UDim2.fromScale(1, 1)
upgradeDim.Text = ""
upgradeDim.AutoButtonColor = false
upgradeDim.BackgroundColor3 = Color3.new(0, 0, 0)
upgradeDim.BackgroundTransparency = 1
upgradeDim.Visible = false
upgradeDim.ZIndex = 9
upgradeDim.Parent = gui

-- Okno panelu
local CARD_W, CARD_H = 168, 266
local TOP_TABS, TOP_PLAIN = 108, 70 -- gdzie zaczynają się karty: z zakładkami i bez
local PANEL_W = 700
local function panelHeight(top: number): number
	return top + CARD_H + 10 + 22
end
local upgradePanel = Instance.new("Frame")
upgradePanel.Name = "UpgradePanel"
upgradePanel.Size = UDim2.fromOffset(PANEL_W, panelHeight(TOP_TABS))
upgradePanel.Position = UDim2.fromScale(0.5, 0.52)
upgradePanel.AnchorPoint = Vector2.new(0.5, 0.5)
PanelKit.paint(upgradePanel)
upgradePanel.Visible = false
upgradePanel.ZIndex = 10
upgradePanel.Active = true -- dotknięcie okna nie idzie dalej do gry
upgradePanel.Parent = gui
corner(upgradePanel, UDim.new(0, 26))
stroke(upgradePanel, OUTLINE, 4)
-- Wewnętrzna cienka linia, jak w kartach z gier
local innerLine = Instance.new("Frame")
innerLine.Name = "Inner"
innerLine.Size = UDim2.new(1, -14, 1, -14)
innerLine.Position = UDim2.fromOffset(7, 7)
innerLine.BackgroundTransparency = 1
innerLine.Parent = upgradePanel
corner(innerLine, UDim.new(0, 21))
stroke(innerLine, CREAM_LINE, 2)

-- Wstążka z tytułem
local ribbon = Instance.new("Frame")
ribbon.Name = "Ribbon"
ribbon.Size = UDim2.fromOffset(250, 56)
ribbon.AnchorPoint = Vector2.new(0.5, 0.5)
ribbon.Position = UDim2.new(0.5, 0, 0, 0)
ribbon.BackgroundColor3 = VIOLET
ribbon.ZIndex = 12
ribbon.Parent = upgradePanel
corner(ribbon, UDim.new(0, 16))
stroke(ribbon, OUTLINE, 3.5)
local ribbonShade = Instance.new("UIGradient")
ribbonShade.Rotation = 90
ribbonShade.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(196, 196, 196))
ribbonShade.Parent = ribbon
local upgradeTitle = label("Title", ribbon, UDim2.new(1, -70, 1, -12), UDim2.fromOffset(56, 6), TITLE_FONT, 34)
upgradeTitle.ZIndex = 13
UiKit.outline(upgradeTitle, 3)
local titleIcon = UiKit.icon("upgrade", ribbon, UDim2.fromOffset(62, 62), UDim2.new(0, -14, 0.5, -4), Vector2.new(0, 0.5))
titleIcon.Rotation = -12
titleIcon.ZIndex = 14

-- Monety w lewym górnym rogu
local coinPill = Instance.new("Frame")
coinPill.Name = "Coins"
coinPill.Size = UDim2.fromOffset(150, 40)
coinPill.Position = UDim2.fromOffset(34, -20)
coinPill.BackgroundColor3 = Color3.fromRGB(52, 38, 30)
coinPill.ZIndex = 12
coinPill.Parent = upgradePanel
corner(coinPill, UDim.new(1, 0))
stroke(coinPill, OUTLINE, 3)
local pillCoin = UiKit.icon("coin", coinPill, UDim2.fromOffset(46, 46), UDim2.new(0, -18, 0.5, 0), Vector2.new(0, 0.5))
pillCoin.ZIndex = 13
local pillCoins = label("Amount", coinPill, UDim2.new(1, -46, 1, -10), UDim2.fromOffset(34, 5), TITLE_FONT, 24)
pillCoins.TextXAlignment = Enum.TextXAlignment.Left
pillCoins.TextColor3 = Color3.fromRGB(150, 236, 96)
pillCoins.ZIndex = 13

-- Zamykanie w prawym górnym rogu (wystaje poza okno)
local closeUpgrades = Instance.new("TextButton")
closeUpgrades.Name = "Close"
closeUpgrades.Size = UDim2.fromOffset(52, 52)
closeUpgrades.AnchorPoint = Vector2.new(0.5, 0.5)
closeUpgrades.Position = UDim2.new(1, -12, 0, 6)
closeUpgrades.Text = ""
closeUpgrades.ZIndex = 12
closeUpgrades.Parent = upgradePanel
local closeStroke = UiKit.button(closeUpgrades, UiKit.COLORS.red, { stroke = 3, radius = UDim.new(0, 14), gloss = true })
closeStroke.Color = OUTLINE
local closeIcon = UiKit.icon("close", closeUpgrades, UDim2.fromScale(0.72, 0.72), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
closeIcon.ZIndex = 13
closeUpgrades.MouseEnter:Connect(function()
	TweenService:Create(closeIcon, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Rotation = 90 }):Play()
end)
closeUpgrades.MouseLeave:Connect(function()
	TweenService:Create(closeIcon, TweenInfo.new(0.2), { Rotation = 0 }):Play()
end)

-- Zakładki światów
local TABS = {
	{ world = "forest", key = "UPG_TAB_FOREST", icon = "🌲" },
	{ world = "cave", key = "UPG_TAB_CAVE", icon = "💎" },
	{ world = "swamp", key = "UPG_TAB_SWAMP", icon = "🐸" },
}
local tabBar = Instance.new("Frame")
tabBar.Name = "Tabs"
tabBar.Size = UDim2.new(1, -40, 0, 36)
tabBar.Position = UDim2.fromOffset(20, 40)
tabBar.BackgroundTransparency = 1
tabBar.ZIndex = 11
tabBar.Parent = upgradePanel
local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
tabLayout.Padding = UDim.new(0, 10)
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Parent = tabBar
local tabButtons: { [string]: TextButton } = {}
local selectedTab = "forest"
for order, tab in TABS do
	local button = Instance.new("TextButton")
	button.Name = "Tab_" .. tab.world
	button.Size = UDim2.new(0, 150, 1, 0)
	button.LayoutOrder = order
	button.Font = TITLE_FONT
	button.TextScaled = true
	button.TextColor3 = Color3.new(1, 1, 1)
	button.ZIndex = 12
	button.Parent = tabBar
	local tabStroke = UiKit.button(button, UiKit.COLORS.wood, { stroke = 2.5, radius = UDim.new(1, 0) })
	tabStroke.Color = OUTLINE
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 18
	constraint.Parent = button
	tabButtons[tab.world] = button
end

local upgradeHint = label("Hint", upgradePanel, UDim2.new(1, -60, 0, 22), UDim2.fromOffset(30, 80), TITLE_FONT, 18)
upgradeHint.ZIndex = 11

-- Karty w poziomym pasku z przewijaniem
local grid = Instance.new("ScrollingFrame")
grid.Name = "Upgrades"
grid.Size = UDim2.new(1, -28, 0, CARD_H + 22)
grid.Position = UDim2.fromOffset(14, TOP_TABS)
grid.BackgroundTransparency = 1
grid.BorderSizePixel = 0
grid.ScrollingDirection = Enum.ScrollingDirection.X
grid.AutomaticCanvasSize = Enum.AutomaticSize.X
grid.CanvasSize = UDim2.new()
grid.ScrollBarThickness = 8
grid.ScrollBarImageColor3 = OUTLINE
grid.ScrollBarImageTransparency = 0.5
grid.ElasticBehavior = Enum.ElasticBehavior.Always
grid.ZIndex = 11
grid.Parent = upgradePanel
local gridLayout = Instance.new("UIListLayout")
gridLayout.FillDirection = Enum.FillDirection.Horizontal
gridLayout.Padding = UDim.new(0, 12)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = grid
local gridPadding = Instance.new("UIPadding")
gridPadding.PaddingLeft = UDim.new(0, 8)
gridPadding.PaddingRight = UDim.new(0, 8)
gridPadding.Parent = grid

local setUpgradesOpen: (boolean) -> ()
local applyTab: () -> ()
local render: () -> () -- zdefiniowane niżej, zakładki odświeżają przez nie panel

type Card = {
	holder: Frame,
	body: TextButton,
	title: TextLabel,
	desc: TextLabel,
	value: TextLabel,
	icon: GuiObject,
	iconScale: UIScale,
	pips: Frame,
	buy: TextButton,
	buyStroke: UIStroke,
	buyIcon: GuiObject,
	cost: TextLabel,
	stroke: UIStroke,
	affordable: boolean,
	maxed: boolean,
	hover: boolean,
	titleScale: UIScale,
}
local cards: { [string]: Card } = {}

-- Samouczek: tylko to ulepszenie można kliknąć, reszta kart jest przyciemniona
local tutorialFocus: string? = nil

local CARD_REST = UDim2.fromOffset(0, 8)
local CARD_LIFT = UDim2.fromOffset(0, 0)

-- Ikona i napis karty rosną razem (bez obracania); drugi argument zostaje dla zgodności wywołań
local function iconTo(card: Card, scale: number, _rotation: number, time: number)
	card.icon.Rotation = 0
	TweenService:Create(card.iconScale, TweenInfo.new(time, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = scale }):Play()
	local titleScale = 1 + (scale - 1) * 0.6
	TweenService:Create(card.titleScale, TweenInfo.new(time, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = titleScale }):Play()
end

-- Kliknięcie: ikona podskakuje i wraca, z ikony wylatują iskierki
local function iconPop(card: Card, amount: number)
	card.iconScale.Scale = amount
	card.titleScale.Scale = 1 + (amount - 1) * 0.5
	iconTo(card, if card.hover then 1.18 else 1, 0, 0.45)
	local center = card.icon.AbsolutePosition + card.icon.AbsoluteSize / 2
	UiKit.burst(gui, center, 10, { Color3.fromRGB(255, 236, 140), Color3.fromRGB(255, 255, 255), card.body.BackgroundColor3:Lerp(Color3.new(1, 1, 1), 0.4) })
end

local function centerOf(object: GuiObject): Vector2
	return object.AbsolutePosition + object.AbsoluteSize / 2
end

local function setPips(card: Card, level: number, maxLevel: number)
	if #card.pips:GetChildren() - 1 ~= maxLevel then
		for _, child in card.pips:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		for i = 1, maxLevel do
			local pip = Instance.new("Frame")
			pip.Name = "Pip" .. i
			pip.LayoutOrder = i
			pip.Size = UDim2.fromOffset(12, 12)
			pip.ZIndex = 14
			pip.Parent = card.pips
			corner(pip, UDim.new(1, 0))
			stroke(pip, OUTLINE, 1.5)
		end
	end
	for _, child in card.pips:GetChildren() do
		if child:IsA("Frame") then
			local on = child.LayoutOrder <= level
			child.BackgroundColor3 = if on then Color3.fromRGB(255, 255, 255) else OUTLINE
			child.BackgroundTransparency = if on then 0 else 0.55
		end
	end
end

for order, id in ALL_UPGRADES do
	local color = UPGRADE_COLORS[id] or UiKit.COLORS.moss
	local holder = Instance.new("Frame")
	holder.Name = "Upgrade_" .. id
	holder.Size = UDim2.fromOffset(CARD_W, CARD_H + 10)
	holder.BackgroundTransparency = 1
	holder.LayoutOrder = order
	holder.ZIndex = 12
	holder.Parent = grid

	local body = Instance.new("TextButton")
	body.Name = "Card"
	body.Text = ""
	body.AutoButtonColor = false
	body.Size = UDim2.fromOffset(CARD_W, CARD_H)
	body.Position = CARD_REST
	body.BackgroundColor3 = color
	body.ZIndex = 12
	body.Parent = holder
	corner(body, UDim.new(0, 20))
	local cardStroke = stroke(body, OUTLINE, 3)
	local shade = Instance.new("UIGradient")
	shade.Rotation = 90
	shade.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(236, 236, 236)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(196, 196, 196)),
	})
	shade.Parent = body

	local title = label("Title", body, UDim2.new(1, -16, 0, 28), UDim2.fromOffset(8, 8), TITLE_FONT, 24)
	title.ZIndex = 14
	UiKit.outline(title, 2.5)
	local titleScale = Instance.new("UIScale")
	titleScale.Parent = title

	-- Jasne koło za ikoną
	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.Size = UDim2.fromOffset(108, 108)
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.new(0.5, 0, 0, 94)
	glow.BackgroundColor3 = Color3.new(1, 1, 1)
	glow.BackgroundTransparency = 0.72
	glow.ZIndex = 13
	glow.Parent = body
	corner(glow, UDim.new(1, 0))

	local icon = UiKit.icon(UPGRADE_ICONS[id] or "lantern", body, UDim2.fromOffset(96, 96), UDim2.new(0.5, 0, 0, 94), Vector2.new(0.5, 0.5))
	icon.ZIndex = 15
	local iconScale = Instance.new("UIScale")
	iconScale.Parent = icon

	local desc = label("Desc", body, UDim2.new(1, -12, 0, 36), UDim2.fromOffset(6, 146), BODY_FONT, 16)
	desc.TextWrapped = true
	desc.ZIndex = 14
	UiKit.outline(desc, 1.5)

	local pips = Instance.new("Frame")
	pips.Name = "Pips"
	pips.Size = UDim2.new(1, -16, 0, 14)
	pips.Position = UDim2.fromOffset(8, 186)
	pips.BackgroundTransparency = 1
	pips.ZIndex = 14
	pips.Parent = body
	local pipLayout = Instance.new("UIListLayout")
	pipLayout.FillDirection = Enum.FillDirection.Horizontal
	pipLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	pipLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	pipLayout.Padding = UDim.new(0, 3)
	pipLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pipLayout.Parent = pips

	local value = label("Value", body, UDim2.new(1, -16, 0, 24), UDim2.fromOffset(8, 202), TITLE_FONT, 22)
	value.ZIndex = 14
	UiKit.outline(value, 2.5)

	local buy = Instance.new("TextButton")
	buy.Name = "Buy"
	buy.Text = ""
	buy.Size = UDim2.new(1, -16, 0, 34)
	buy.AnchorPoint = Vector2.new(0.5, 1)
	buy.Position = UDim2.new(0.5, 0, 1, -7)
	buy.ZIndex = 14
	buy.Parent = body
	local buyStroke = UiKit.button(buy, BUY_GREEN, { stroke = 2.5, radius = UDim.new(0, 12), gloss = true })
	buyStroke.Color = OUTLINE
	local buyIcon = UiKit.icon("coin", buy, UDim2.fromOffset(30, 30), UDim2.new(0, 2, 0.5, 0), Vector2.new(0, 0.5))
	buyIcon.ZIndex = 16
	local cost = label("Cost", buy, UDim2.new(1, -40, 1, -8), UDim2.fromOffset(34, 4), TITLE_FONT, 22)
	cost.ZIndex = 16
	UiKit.outline(cost, 2)

	local card: Card = {
		holder = holder,
		body = body,
		title = title,
		desc = desc,
		value = value,
		icon = icon,
		iconScale = iconScale,
		pips = pips,
		buy = buy,
		buyStroke = buyStroke,
		buyIcon = buyIcon,
		cost = cost,
		stroke = cardStroke,
		affordable = false,
		maxed = false,
		hover = false,
		titleScale = titleScale,
	}
	cards[id] = card

	-- Najechanie: karta się unosi, ikona i napis rosną
	body.MouseEnter:Connect(function()
		card.hover = true
		TweenService:Create(body, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { Position = CARD_LIFT }):Play()
		cardStroke.Thickness = 4
		iconTo(card, 1.18, 0, 0.3)
	end)
	body.MouseLeave:Connect(function()
		card.hover = false
		TweenService:Create(body, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { Position = CARD_REST }):Play()
		cardStroke.Thickness = 3
		iconTo(card, 1, 0, 0.25)
	end)
	-- Kliknięcie w kartę: duża ikona i iskierki (podgląd), kupuje się przyciskiem z ceną
	body.Activated:Connect(function()
		iconPop(card, 1.35)
	end)
	-- Przyciemnienie karty w samouczku (gdy kupić można tylko inne ulepszenie)
	local veil = Instance.new("Frame")
	veil.Name = "TutorialVeil"
	veil.Size = UDim2.fromScale(1, 1)
	veil.BackgroundColor3 = Color3.new(0, 0, 0)
	veil.BackgroundTransparency = 0.45
	veil.Visible = false
	veil.ZIndex = 30
	veil.Parent = body
	corner(veil, UDim.new(0, 20))
	buy.Activated:Connect(function()
		if tutorialFocus and tutorialFocus ~= id then
			UiKit.shake(buy)
			return
		end
		if card.maxed then
			iconPop(card, 1.3)
			return
		end
		if not card.affordable then
			UiKit.shake(buy)
			iconTo(card, 0.85, 0, 0.15)
			task.delay(0.18, function()
				iconTo(card, if card.hover then 1.18 else 1, 0, 0.3)
			end)
			return
		end
		iconPop(card, 1.5)
		for _, callback in callbacks.buy do
			callback(id)
		end
	end)
end

-- Zakładki i otwieranie panelu ulepszeń
local TAB_HINTS: { [string]: string } = {
	forest = "UPG_HINT_FOREST",
	cave = "UPG_HINT_CAVE",
	swamp = "UPG_HINT_SWAMP",
}

local function tabUnlocked(world: string): boolean
	local state = lastState :: any
	if world == "forest" then
		return true
	elseif world == "cave" then
		return state ~= nil and state.caveUnlocked == true
	end
	return state ~= nil and state.swampUnlocked == true
end

local function unlockedTabCount(): number
	local count = 0
	for _, tab in TABS do
		if tabUnlocked(tab.world) then
			count += 1
		end
	end
	return count
end

applyTab = function()
	local count = 0
	for id, card in cards do
		local visible = Economy.upgradeShop(id) == selectedTab
		card.holder.Visible = visible
		if visible then
			count += 1
		end
	end
	-- Zakładki tylko wtedy, gdy jest z czego wybierać
	local withTabs = unlockedTabCount() > 1
	tabBar.Visible = withTabs
	local top = if withTabs then TOP_TABS else TOP_PLAIN
	upgradeHint.Position = UDim2.fromOffset(30, top - 30)
	grid.Position = UDim2.fromOffset(14, top)
	-- Okno tak szerokie, ile kart ma ta zakładka (najwyżej PANEL_W, dalej przewijanie)
	local width = math.clamp(count * (CARD_W + 12) + 44, 460, PANEL_W)
	upgradePanel.Size = UDim2.fromOffset(width, panelHeight(top))
	grid.CanvasPosition = Vector2.zero
	for world, button in tabButtons do
		UiKit.recolor(button, if world == selectedTab then VIOLET else UiKit.COLORS.wood)
		local tabStroke = button:FindFirstChildOfClass("UIStroke")
		if tabStroke then
			tabStroke.Color = OUTLINE
		end
	end
end

-- Karty wjeżdżają od dołu jedna po drugiej
local function cardsEnter()
	local index = 0
	for _, id in ALL_UPGRADES do
		local card = cards[id]
		if card.holder.Visible then
			index += 1
			card.body.Position = UDim2.fromOffset(0, 60)
			card.iconScale.Scale = 0.4
			task.delay(index * 0.045, function()
				TweenService:Create(card.body, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = CARD_REST }):Play()
				TweenService:Create(card.iconScale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end)
		end
	end
end

setUpgradesOpen = function(open: boolean)
	if open == upgradePanel.Visible then
		return
	end
	upgradePanel.Visible = open
	upgradeDim.Visible = open
	PanelKit.setModal("Upgrades", open) -- na telefonie postać nie chodzi, gdy wybierasz ulepszenia
	if open then
		PanelKit.closeAll() -- jedno okno naraz (zadania, Grzybopedia, tytuły)
		-- Na start zakładka świata, w którym gracz jest teraz
		local state = lastState
		local world = if state then Economy.zoneWorld(state.zone) else "forest"
		selectedTab = if tabUnlocked(world) then world else "forest"
		applyTab()
		render()
		upgradeDim.BackgroundTransparency = 1
		TweenService:Create(upgradeDim, TweenInfo.new(0.25), { BackgroundTransparency = 0.5 }):Play()
		pop(upgradePanel, -0.25)
		cardsEnter()
	end
end

for world, button in tabButtons do
	button.Activated:Connect(function()
		if selectedTab ~= world then
			selectedTab = world
			applyTab()
			render()
			cardsEnter()
		end
		pop(button, 0.08)
	end)
end
upgradeButton.Activated:Connect(function()
	-- Na telefonie nie ma najechania, więc animacja przy dotknięciu
	hoverIn()
	task.delay(0.6, hoverOut)
	setUpgradesOpen(not upgradePanel.Visible)
end)
closeUpgrades.Activated:Connect(function()
	setUpgradesOpen(false)
end)
upgradeDim.Activated:Connect(function()
	setUpgradesOpen(false)
end)

PanelKit.onOpen(function()
	setUpgradesOpen(false)
end)

-- Klawisz R (i Y na padzie) otwiera i zamyka panel ulepszeń
ContextActionService:BindAction("ToggleUpgrades", function(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		hoverIn()
		task.delay(0.6, hoverOut)
		setUpgradesOpen(not upgradePanel.Visible)
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.R, Enum.KeyCode.ButtonY)

-- Teksty panelu, podpowiedź, gdzie można kupować, i liczba ulepszeń na kropce przycisku
local function renderUpgradePanel(state: State)
	upgradeCaption.Text = Localize.t("UPG_BUTTON")
	upgradeTitle.Text = Localize.t("UPG_TITLE")
	pillCoins.Text = formatCoins(state.coins)
	for _, tab in TABS do
		local button = tabButtons[tab.world]
		button.Text = tab.icon .. " " .. Localize.t(tab.key)
		button.Visible = tabUnlocked(tab.world)
	end
	local here = Economy.isSafeZone(state.zone) and Economy.zoneWorld(state.zone) == selectedTab
	upgradeHint.Text = if here then Localize.t("UPG_HINT_HERE") else Localize.t(TAB_HINTS[selectedTab] or "UPG_HINT_FOREST")
	upgradeHint.TextColor3 = if here then PanelKit.MUTED else Color3.fromRGB(255, 130, 110)

	local affordable = 0
	for _, id in ALL_UPGRADES do
		if tabUnlocked(Economy.upgradeShop(id)) then
			local cost = Economy.upgradeCost(id, state.upgrades[id] or 0)
			if cost and state.coins >= cost then
				affordable += 1
			end
		end
	end
	badge.Visible = affordable > 0
	badgeLabel.Text = tostring(affordable)
end

-- Komunikaty wysuwane z góry
local toast = panel("Toast", gui, UDim2.new(0, 420, 0, 46), UDim2.new(0.5, 0, 0.3, 0), Vector2.new(0.5, 0.5))
toast.Visible = false
local toastMax = Instance.new("UISizeConstraint")
toastMax.MaxSize = Vector2.new(420, 46)
toastMax.Parent = toast
toast.Size = UDim2.new(0.9, 0, 0, 46)
local toastLabel = label("Text", toast, UDim2.new(1, -20, 1, -8), UDim2.new(0, 10, 0, 4), TITLE_FONT, 22)
local toastStroke = toast:FindFirstChildOfClass("UIStroke") :: UIStroke

-- Ekran pochłonięcia przez las
local blackout = Instance.new("Frame")
blackout.Name = "Blackout"
blackout.Size = UDim2.new(1, 0, 1, 0)
blackout.BackgroundColor3 = Color3.new(0, 0, 0)
blackout.BackgroundTransparency = 1
blackout.ZIndex = 20
blackout.Active = false
blackout.Parent = gui
local blackoutTitle = label("Title", blackout, UDim2.new(0.8, 0, 0, 60), UDim2.new(0.1, 0, 0.4, 0), TITLE_FONT, 48)
blackoutTitle.TextColor3 = Color3.fromRGB(220, 60, 50)
blackoutTitle.TextTransparency = 1
blackoutTitle.ZIndex = 21
local blackoutSub = label("Sub", blackout, UDim2.new(0.8, 0, 0, 30), UDim2.new(0.1, 0, 0.4, 66), BODY_FONT, 24)
blackoutSub.TextColor3 = THEME.muted
blackoutSub.TextTransparency = 1
blackoutSub.ZIndex = 21

-- ===== Logika =====

local toastToken = 0
local toastY = 200 -- środek komunikatu pod banerem „Wracaj!”, ustawiany w layout()
local shownCoins = 0
local coinsValue = Instance.new("NumberValue")
local lowPulse: Tween? = nil


coinsValue.Changed:Connect(function(value)
	coinsLabel.Text = formatCoins(value)
end)

local function setOilLow(low: boolean)
	if low and not lowPulse then
		oilStroke.Color = THEME.oilLow
		local tween = TweenService:Create(oilStroke, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
			Thickness = 4,
		})
		tween:Play()
		lowPulse = tween
		oilGradient.Color = ColorSequence.new(Color3.fromRGB(255, 140, 90), THEME.oilLow)
	elseif not low and lowPulse then
		lowPulse:Cancel()
		lowPulse = nil
		oilStroke.Thickness = 2
		oilStroke.Color = THEME.stroke
		oilGradient.Color = ColorSequence.new(THEME.oilLight, THEME.oil)
	end
end

-- Pora dnia przed nazwą strefy: "🌕 12:34 · " nocą (ikona zdarzenia), "🌅 1:20 · " o świcie
local function cycleText(): string
	local phase = Workspace:GetAttribute("CyclePhase")
	local endsAt = Workspace:GetAttribute("CycleEndsAt")
	if typeof(phase) ~= "string" or typeof(endsAt) ~= "number" then
		return ""
	end
	local left = math.max(0, math.floor(endsAt - Workspace:GetServerTimeNow()))
	local clock = string.format("%d:%02d", left // 60, left % 60)
	if phase == "dawn" then
		return "🌅 " .. clock .. " · "
	end
	local eventId = Workspace:GetAttribute("CycleEvent")
	for _, def in Config.Cycle.events do
		if def.id == eventId then
			return def.icon .. " " .. clock .. " · "
		end
	end
	return "🌙 " .. clock .. " · "
end

render = function()
	languageButton.Text = Localize.t("HUD_LANGUAGE")
	pickCaption.Text = Localize.t("HUD_PICK")

	local state = lastState
	if not state then
		return
	end

	basketLabel.Text = string.format("%d/%d", state.basketCount, state.basketMax)
	basketFill.Size = UDim2.new(if state.basketMax > 0 then math.clamp(state.basketCount / state.basketMax, 0, 1) else 0, 0, 1, 0)
	basketFill.BackgroundColor3 = if state.basketCount >= state.basketMax then THEME.warn else Color3.fromRGB(150, 196, 90)

	local zoneDef = Config.Zones[state.zone] or Config.Zones[1]
	zoneLabel.Text = cycleText() .. Localize.t(zoneDef.key)

	local fraction = if state.oilMax > 0 then math.clamp(state.oil / state.oilMax, 0, 1) else 0
	oilFill.Size = UDim2.new(fraction, 0, 1, 0)
	oilText.Text = string.format("%s  %d/%d", Localize.t("HUD_OIL"), math.ceil(state.oil), state.oilMax)
	setOilLow(not Economy.isSafeZone(state.zone) and fraction < Config.OilLowFraction)

	renderUpgradePanel(state)

	for id, card in cards do
		local def = Config.Upgrades[id]
		local level = state.upgrades[id] or 0
		local cost = Economy.upgradeCost(id, level)
		card.title.Text = Localize.t(def.key)
		card.desc.Text = Localize.t(def.key .. "_DESC")
		card.value.Text = valueText(id, level)
		setPips(card, level, def.maxLevel)
		card.maxed = cost == nil
		card.affordable = cost ~= nil and state.coins >= (cost :: number)
		if cost then
			card.cost.Text = formatCoins(cost)
			UiKit.recolor(card.buy, if card.affordable then BUY_GREEN else BUY_RED)
			UiKit.setIcon(card.buyIcon, "coin")
		else
			card.cost.Text = Localize.t("HUD_MAX")
			UiKit.recolor(card.buy, BUY_GOLD)
			UiKit.setIcon(card.buyIcon, "star")
		end
		card.buyStroke.Color = OUTLINE
		local veil = card.body:FindFirstChild("TutorialVeil")
		if veil and veil:IsA("Frame") then
			veil.Visible = tutorialFocus ~= nil and tutorialFocus ~= id
		end
	end
end

function Hud.update(state: State)
	local previous = lastState
	lastState = state
	if previous then
		if state.coins ~= previous.coins then
			TweenService:Create(coinsValue, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { Value = state.coins }):Play()
			if state.coins > previous.coins then
				pop(coinsLabel, 0.3)
				pop(coinsIcon, 0.4)
			end
		end
		if state.basketCount > previous.basketCount then
			pop(basketIcon, 0.35)
		end
		-- Kupione ulepszenie: ikona podskakuje, karta błyska złotem, sypią się iskry i wylatuje „+1”
		for id, card in cards do
			local level = state.upgrades[id] or 0
			if level > (previous.upgrades[id] or 0) and upgradePanel.Visible and card.holder.Visible then
				card.iconScale.Scale = 1.6
				iconTo(card, if card.hover then 1.18 else 1, 0, 0.6)
				card.stroke.Color = THEME.gold
				card.stroke.Thickness = 6
				TweenService:Create(card.stroke, TweenInfo.new(0.9, Enum.EasingStyle.Quad), { Color = OUTLINE, Thickness = 3 }):Play()
				UiKit.burst(gui, centerOf(card.icon), 14)
				local pip = card.pips:FindFirstChild("Pip" .. level)
				if pip and pip:IsA("GuiObject") then
					pop(pip, 1.2)
				end
				local plus = label("Plus", gui, UDim2.fromOffset(120, 40), UDim2.fromOffset(0, 0), TITLE_FONT, 34)
				local from = centerOf(card.icon)
				plus.AnchorPoint = Vector2.new(0.5, 0.5)
				plus.Position = UDim2.fromOffset(from.X, from.Y - 40)
				plus.Text = "+1"
				plus.TextColor3 = Color3.fromRGB(150, 255, 110)
				plus.ZIndex = 60
				UiKit.outline(plus, 3)
				local rise = TweenService:Create(plus, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Position = UDim2.fromOffset(from.X, from.Y - 110),
					TextTransparency = 1,
				})
				rise.Completed:Connect(function()
					plus:Destroy()
				end)
				rise:Play()
			end
		end
	else
		coinsValue.Value = state.coins
		coinsLabel.Text = formatCoins(state.coins)
	end
	shownCoins = state.coins
	render()
end

function Hud.refreshTexts()
	render()
end

-- Panel ulepszeń: przycisk z prawej strony ekranu otwiera go i zamyka
function Hud.toggleUpgrades(open: boolean?)
	setUpgradesOpen(if open == nil then not upgradePanel.Visible else open)
end

function Hud.upgradesOpen(): boolean
	return upgradePanel.Visible
end

-- Dla samouczka: przycisk „Ulepszenia”, przycisk kupna danej karty i blokada innych kart
function Hud.upgradeButton(): GuiObject
	return upgradeButton
end

function Hud.upgradeBuyButton(id: string): GuiObject?
	local card = cards[id]
	return card and card.buy
end

function Hud.setTutorialFocus(id: string?)
	-- Samouczek woła to co klatkę; przerysowujemy tylko przy zmianie
	if id == tutorialFocus then
		return
	end
	tutorialFocus = id
	render()
end

-- Panel monet i koszyka w lewym górnym rogu oraz pasek oleju (do podświetlania w samouczku)
function Hud.statsPanel(): GuiObject
	return stats
end

function Hud.oilPanel(): GuiObject
	return oilPanel
end

local pickPulse: Tween? = nil
local pickEnabled: boolean? = nil

function Hud.setPick(enabled: boolean, visible: boolean)
	pickButton.Visible = visible
	if enabled == pickEnabled then
		return
	end
	pickEnabled = enabled
	pickButton.BackgroundTransparency = if enabled then 0 else 0.55
	UiKit.setIconTransparency(pickIcon, if enabled then 0 else 0.5)
	pickCaption.TextTransparency = if enabled then 0 else 0.4
	pickStroke.Transparency = if enabled then 0 else 0.7
	if enabled then
		pickScale.Scale = 1.12
		local tween = TweenService:Create(pickScale, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
			Scale = 1.04,
		})
		tween:Play()
		pickPulse = tween
	elseif pickPulse then
		pickPulse:Cancel()
		pickPulse = nil
		pickScale.Scale = 1
	end
end

-- kind: "info" (zwykły), "gold" (złoty grzyb), "warn" (olej, koszyk)
function Hud.toast(text: string, kind: string?)
	toastToken += 1
	local token = toastToken
	toastLabel.Text = text
	toastStroke.Color = if kind == "gold" then THEME.gold elseif kind == "warn" then THEME.warn else THEME.stroke
	toastLabel.TextColor3 = if kind == "gold" then THEME.gold elseif kind == "warn" then Color3.fromRGB(255, 200, 180) else THEME.text
	toast.Visible = true
	toast.Position = UDim2.new(0.5, 0, 0, toastY - 16)
	TweenService:Create(toast, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, toastY),
	}):Play()
	task.delay(2.6, function()
		if toastToken == token then
			toast.Visible = false
		end
	end)
end

function Hud.engulf(title: string, subtitle: string)
	blackout.BackgroundTransparency = 0
	blackoutTitle.Text = title
	blackoutSub.Text = subtitle
	blackoutTitle.TextTransparency = 0
	blackoutSub.TextTransparency = 0
	local info = TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.4)
	TweenService:Create(blackout, info, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(blackoutTitle, info, { TextTransparency = 1 }):Play()
	TweenService:Create(blackoutSub, info, { TextTransparency = 1 }):Play()
end

-- Deszcz monet po sprzedaży: wyskakują z przycisku „Sprzedaj” i lecą do licznika w rogu.
-- Każda moneta, która doleci, podbija ikonę, więc licznik „łapie” je jedna po drugiej.
-- from: punkt na ekranie, z którego wylatują monety (np. przycisk sprzedaży); domyślnie środek ekranu
function Hud.coinShower(value: number, from: Vector2?)
	local coinCount = math.clamp(math.ceil(value / 4), 5, 16)
	local start = from or gui.AbsoluteSize / 2
	local to = coinsIcon.AbsolutePosition + coinsIcon.AbsoluteSize / 2
	for index = 1, coinCount do
		local coin = UiKit.icon("coin", gui, UDim2.fromOffset(30, 30), UDim2.fromOffset(start.X, start.Y), Vector2.new(0.5, 0.5))
		coin.Name = "FlyingCoin"
		coin.ZIndex = 30
		coin.Rotation = math.random(-25, 25)

		local angle = math.random() * math.pi * 2
		local radius = math.random(40, 100)
		local scatter = start + Vector2.new(math.cos(angle) * radius, math.sin(angle) * radius * 0.6 - 30)
		TweenService:Create(coin, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(scatter.X, scatter.Y),
		}):Play()
		task.delay(0.3 + index * 0.045, function()
			local fly = TweenService:Create(coin, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.fromOffset(to.X, to.Y),
				Size = UDim2.fromOffset(20, 20),
				Rotation = 0,
			})
			fly.Completed:Connect(function()
				coin:Destroy()
				pop(coinsIcon, 0.18)
			end)
			fly:Play()
		end)
	end
end

function Hud.onPick(callback: () -> ())
	table.insert(callbacks.pick, callback)
end

function Hud.onBuy(callback: (string) -> ())
	table.insert(callbacks.buy, callback)
end

function Hud.getShownCoins(): number
	return shownCoins
end

pickButton.Activated:Connect(function()
	for _, callback in callbacks.pick do
		callback()
	end
end)

languageButton.Activated:Connect(function()
	Localize.toggle()
end)

-- ===== Układ zależny od ekranu =====

local placePickByJump: () -> ()

local function layoutScale(target: GuiObject, scale: number)
	local uiScale = target:FindFirstChildOfClass("UIScale")
	if not uiScale then
		local created = Instance.new("UIScale")
		created.Parent = target
		uiScale = created
	end
	local s = uiScale :: UIScale
	s:SetAttribute("Base", scale)
	s.Scale = scale
end

-- Na telefonie: ZBIERZ dokładnie na lewo od prawdziwego przycisku skoku Robloxa (jego miejsce
-- zależy od telefonu i wcięć ekranu), z odstępem, i z dołem równo z dołem skoku
local function jumpButton(): GuiObject?
	local touch = gui.Parent and gui.Parent:FindFirstChild("TouchGui")
	local frame = touch and touch:FindFirstChild("TouchControlFrame")
	local jump = frame and frame:FindFirstChild("JumpButton")
	return if jump and jump:IsA("GuiObject") then jump else nil
end

placePickByJump = function()
	local jump = jumpButton()
	if not jump or not jump.Visible or jump.AbsoluteSize.X <= 0 then
		return
	end
	local at = jump.AbsolutePosition - gui.AbsolutePosition
	pickButton.Position = UDim2.fromOffset(math.floor(at.X - 12), math.floor(at.Y + jump.AbsoluteSize.Y))
end

local function layout()
	local scale = UiScale.get()
	for _, target in { stats, top, upgradePanel, upgradeRoot, toast } do
		layoutScale(target, scale)
	end
	-- Rząd przycisków ma własną skalę (na telefonie większą niż reszta HUD)
	layoutScale(languageButton, UiScale.row())
	languageButton.Position = UDim2.new(0, 12, 0, UiScale.rowTop())
	-- Pasek oleju (66) + baner „Wracaj!” (64) + odstępy, potem połowa wysokości komunikatu
	toastY = math.floor(8 + 66 * scale + 8 + 64 * scale + 12 + 23 * scale)
	if not toast.Visible then
		toast.Position = UDim2.new(0.5, 0, 0, toastY)
	end

	-- ZBIERZ zawsze obok przycisku skoku: na małych ekranach skok jest mniejszy i niżej
	local size = math.floor(112 * math.max(scale, 0.62))
	pickButton.Size = UDim2.fromOffset(size, size)
	pickButton.Position = if UiScale.isSmall() then UDim2.new(1, -112, 1, -14) else UDim2.new(1, -190, 1, -40)
	placePickByJump()
	-- „Ulepszenia” przy prawej krawędzi, nad przyciskami ZBIERZ i skoku
	upgradeRoot.Position = UDim2.new(1, -16, 0.42, 0)
end
UiScale.onChanged(layout)
-- Przycisk skoku pojawia się później i zmienia miejsce (obrót telefonu): sprawdzamy co chwilę
task.spawn(function()
	while true do
		task.wait(1)
		placePickByJump()
	end
end)

Hud.setPick(false, false)
render()

return Hud
