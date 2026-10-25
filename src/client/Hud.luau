--!strict
-- Interfejs budowany kodem, projektowany najpierw pod telefon.
-- Styl: ciemne drewno z bursztynową obwódką, kreskówkowa czcionka, ikony z Figmy (UiKit),
-- cukierkowe przyciski z połyskiem i wciśnięciem.
-- Duży okrągły przycisk ZBIERZ obok przycisku skoku, panel chatki na dole ekranu.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Localize = require(script.Parent.Localize)
local UiKit = require(script.Parent.UiKit)
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

local CARD_STROKE = UiKit.darker(Color3.fromRGB(70, 104, 54), 0.45)

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
languageButton.Size = UDim2.new(0, 70, 0, 30)
-- Pod panelem monet, bo prawy górny róg zajmuje lista graczy z monetami
languageButton.Position = UDim2.new(0, 12, 0, 96)
languageButton.Font = TITLE_FONT
languageButton.TextSize = 18
languageButton.TextXAlignment = Enum.TextXAlignment.Right
languageButton.Parent = gui
UiKit.button(languageButton, UiKit.COLORS.wood, { gloss = true })
UiKit.icon("globe", languageButton, UDim2.new(0, 26, 0, 26), UDim2.new(0, 5, 0.5, 0), Vector2.new(0, 0.5))
local languagePadding = Instance.new("UIPadding")
languagePadding.PaddingRight = UDim.new(0, 9)
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
-- Przycisk ma animację: po najechaniu (albo dotknięciu) ikona rośnie i robi obrót.
-- Panel ma zakładki światów (Las, Jaskinia, Bagna); kupować można w bezpiecznej strefie danego świata.

local UPGRADE_GREEN = Color3.fromRGB(70, 168, 86)
local upgradeButton = Instance.new("TextButton")
upgradeButton.Name = "UpgradesButton"
upgradeButton.Size = UDim2.fromOffset(96, 96)
upgradeButton.AnchorPoint = Vector2.new(1, 0.5)
upgradeButton.Position = UDim2.new(1, -12, 0.42, 0)
upgradeButton.Text = ""
upgradeButton.Parent = gui
UiKit.button(upgradeButton, UPGRADE_GREEN, { stroke = 3 })
local upgradeIcon = Instance.new("TextLabel")
upgradeIcon.Name = "Icon"
upgradeIcon.Size = UDim2.new(0.62, 0, 0.62, 0)
upgradeIcon.Position = UDim2.new(0.5, 0, 0.38, 0)
upgradeIcon.AnchorPoint = Vector2.new(0.5, 0.5)
upgradeIcon.BackgroundTransparency = 1
upgradeIcon.Text = "⬆️"
upgradeIcon.TextScaled = true
upgradeIcon.Font = TITLE_FONT
upgradeIcon.ZIndex = 3
upgradeIcon.Parent = upgradeButton
local upgradeIconScale = Instance.new("UIScale")
upgradeIconScale.Parent = upgradeIcon
local upgradeCaption = label("Caption", upgradeButton, UDim2.new(1, -8, 0.24, 0), UDim2.new(0, 4, 0.72, 0), TITLE_FONT, 18)
upgradeCaption.ZIndex = 3
local upgradeCaptionStroke = Instance.new("UIStroke")
upgradeCaptionStroke.Thickness = 1.5
upgradeCaptionStroke.Color = Color3.fromRGB(20, 60, 24)
upgradeCaptionStroke.Parent = upgradeCaption

local hoverTweens: { Tween } = {}
local function stopHover()
	for _, tween in hoverTweens do
		tween:Cancel()
	end
	table.clear(hoverTweens)
end
-- Ikona rośnie i robi pełny obrót (z lekkim przeskokiem na końcu), po zjechaniu wraca
local function hoverIn()
	stopHover()
	upgradeIcon.Rotation = 0
	local grow = TweenService:Create(upgradeIconScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.25 })
	local spin = TweenService:Create(upgradeIcon, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = 360 })
	table.insert(hoverTweens, grow)
	table.insert(hoverTweens, spin)
	grow:Play()
	spin:Play()
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

-- Panel ulepszeń na środku ekranu
local CARD_ROW_HEIGHT = 58
local PANEL_TOP = 96 -- nagłówek (48) + zakładki (40) + odstęp
local PANEL_BOTTOM = 34 -- podpowiedź na dole
local function panelHeight(rows: number): number
	return PANEL_TOP + rows * CARD_ROW_HEIGHT + PANEL_BOTTOM
end
local upgradePanel = panel("UpgradePanel", gui, UDim2.new(0.94, 0, 0, panelHeight(4)), UDim2.new(0.5, 0, 0.5, 0), Vector2.new(0.5, 0.5))
upgradePanel.Visible = false
upgradePanel.ZIndex = 10
local panelSize = Instance.new("UISizeConstraint")
panelSize.MaxSize = Vector2.new(620, panelHeight(4))
panelSize.Parent = upgradePanel
local upgradeTitle = label("Title", upgradePanel, UDim2.new(1, -120, 0, 36), UDim2.new(0, 60, 0, 8), TITLE_FONT, 30)
upgradeTitle.TextColor3 = THEME.accent
upgradeTitle.ZIndex = 11
local titleIcon = label("TitleIcon", upgradePanel, UDim2.fromOffset(36, 36), UDim2.fromOffset(14, 8), TITLE_FONT, 30)
titleIcon.Text = "⬆️"
titleIcon.ZIndex = 11
local closeUpgrades = Instance.new("TextButton")
closeUpgrades.Name = "Close"
closeUpgrades.Size = UDim2.fromOffset(40, 40)
closeUpgrades.Position = UDim2.new(1, -10, 0, 6)
closeUpgrades.AnchorPoint = Vector2.new(1, 0)
closeUpgrades.Text = ""
closeUpgrades.ZIndex = 11
closeUpgrades.Parent = upgradePanel
UiKit.button(closeUpgrades, UiKit.COLORS.red, { stroke = 2 })
UiKit.icon("close", closeUpgrades, UDim2.fromScale(0.7, 0.7), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))

-- Zakładki światów
local TABS = {
	{ world = "forest", key = "UPG_TAB_FOREST", icon = "🌲" },
	{ world = "cave", key = "UPG_TAB_CAVE", icon = "💎" },
	{ world = "swamp", key = "UPG_TAB_SWAMP", icon = "🐸" },
}
local tabBar = Instance.new("Frame")
tabBar.Name = "Tabs"
tabBar.Size = UDim2.new(1, -24, 0, 34)
tabBar.Position = UDim2.fromOffset(12, 52)
tabBar.BackgroundTransparency = 1
tabBar.ZIndex = 11
tabBar.Parent = upgradePanel
local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 8)
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
	UiKit.button(button, UiKit.COLORS.wood, { stroke = 2 })
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 18
	constraint.Parent = button
	tabButtons[tab.world] = button
end

local grid = Instance.new("Frame")
grid.Name = "Upgrades"
grid.Size = UDim2.new(1, -24, 1, -(PANEL_TOP + PANEL_BOTTOM))
grid.Position = UDim2.fromOffset(12, PANEL_TOP)
grid.BackgroundTransparency = 1
grid.ZIndex = 11
grid.Parent = upgradePanel
local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.new(0.5, -4, 0, CARD_ROW_HEIGHT - 8)
gridLayout.CellPadding = UDim2.new(0, 8, 0, 8)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = grid

local upgradeHint = label("Hint", upgradePanel, UDim2.new(1, -24, 0, 22), UDim2.new(0, 12, 1, -28), BODY_FONT, 15)
upgradeHint.TextColor3 = THEME.muted
upgradeHint.ZIndex = 11

local setUpgradesOpen: (boolean) -> ()
local applyTab: () -> ()
local render: () -> () -- zdefiniowane niżej, zakładki odświeżają przez nie panel

type Card = {
	button: TextButton,
	title: TextLabel,
	level: TextLabel,
	desc: TextLabel,
	cost: TextLabel,
	fill: Frame,
	stroke: UIStroke,
}
local cards: { [string]: Card } = {}

for order, id in ALL_UPGRADES do
	local button = Instance.new("TextButton")
	button.Name = "Upgrade_" .. id
	button.Text = ""
	button.LayoutOrder = order
	button.Parent = grid
	local cardStroke = UiKit.button(button, THEME.card, { stroke = 2 })
	cardStroke.Color = CARD_STROKE

	UiKit.icon(UPGRADE_ICONS[id] or "lantern", button, UDim2.new(0, 38, 0, 38), UDim2.new(0, 3, 0.5, 0), Vector2.new(0, 0.5))
	local title = label("Title", button, UDim2.new(1, -112, 0, 20), UDim2.new(0, 44, 0, 4), TITLE_FONT, 18)
	title.TextXAlignment = Enum.TextXAlignment.Left
	local level = label("Level", button, UDim2.new(0, 64, 0, 16), UDim2.new(1, -68, 0, 6), BODY_FONT, 13)
	level.TextXAlignment = Enum.TextXAlignment.Right
	level.TextColor3 = THEME.muted
	local desc = label("Desc", button, UDim2.new(1, -118, 0, 16), UDim2.new(0, 44, 0, 25), BODY_FONT, 13)
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextColor3 = THEME.muted
	local cost = label("Cost", button, UDim2.new(0, 70, 0, 20), UDim2.new(1, -74, 0, 24), TITLE_FONT, 17)
	cost.TextXAlignment = Enum.TextXAlignment.Right
	cost.TextColor3 = THEME.accent
	local _, fill = bar(button, UDim2.new(1, -52, 0, 5), UDim2.new(0, 44, 1, -10), Color3.fromRGB(190, 230, 140))

	cards[id] = { button = button, title = title, level = level, desc = desc, cost = cost, fill = fill, stroke = cardStroke }
	button.Activated:Connect(function()
		pop(button, 0.08)
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

applyTab = function()
	local count = 0
	for id, card in cards do
		local visible = Economy.upgradeShop(id) == selectedTab
		card.button.Visible = visible
		if visible then
			count += 1
		end
	end
	-- Panel tak wysoki, ile rzędów kart ma ta zakładka
	local rows = math.max(1, math.ceil(count / 2))
	upgradePanel.Size = UDim2.new(0.94, 0, 0, panelHeight(rows))
	panelSize.MaxSize = Vector2.new(620, panelHeight(rows))
	for world, button in tabButtons do
		UiKit.recolor(button, if world == selectedTab then UPGRADE_GREEN else UiKit.COLORS.wood)
	end
end

setUpgradesOpen = function(open: boolean)
	if open == upgradePanel.Visible then
		return
	end
	upgradePanel.Visible = open
	if open then
		-- Na start zakładka świata, w którym gracz jest teraz
		local state = lastState
		local world = if state then Economy.zoneWorld(state.zone) else "forest"
		selectedTab = if tabUnlocked(world) then world else "forest"
		applyTab()
		pop(upgradePanel, 0.06)
	end
end

for world, button in tabButtons do
	button.Activated:Connect(function()
		selectedTab = world
		applyTab()
		pop(button, 0.08)
		render()
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

-- Teksty panelu i podpowiedź, gdzie można kupować
local function renderUpgradePanel(state: State)
	upgradeCaption.Text = Localize.t("UPG_BUTTON")
	upgradeTitle.Text = Localize.t("UPG_TITLE")
	for _, tab in TABS do
		local button = tabButtons[tab.world]
		button.Text = tab.icon .. " " .. Localize.t(tab.key)
		button.Visible = tabUnlocked(tab.world)
	end
	local here = Economy.isSafeZone(state.zone) and Economy.zoneWorld(state.zone) == selectedTab
	upgradeHint.Text = if here then Localize.t("UPG_HINT_HERE") else Localize.t(TAB_HINTS[selectedTab] or "UPG_HINT_FOREST")
	upgradeHint.TextColor3 = if here then THEME.muted else THEME.warn
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

local function formatCoins(value: number): string
	local s = tostring(math.floor(value + 0.5))
	-- Spacje co trzy cyfry: 12 345
	local formatted = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (formatted:gsub("^ ", ""))
end

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
		card.level.Text = Localize.t("HUD_LEVEL_OF", { level, def.maxLevel })
		card.desc.Text = Localize.t(def.key .. "_DESC")
		card.fill.Size = UDim2.new(level / def.maxLevel, 0, 1, 0)
		if cost then
			local affordable = state.coins >= cost
			card.cost.Text = formatCoins(cost) .. " 💰"
			card.cost.TextColor3 = if affordable then THEME.accent else THEME.muted
			card.button.BackgroundColor3 = if affordable then THEME.card else THEME.cardLocked
			card.stroke.Transparency = if affordable then 0 else 0.8
		else
			card.cost.Text = Localize.t("HUD_MAX")
			card.cost.TextColor3 = THEME.gold
			card.button.BackgroundColor3 = THEME.cardLocked
			card.stroke.Transparency = 0.8
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
		-- Kupione ulepszenie: karta podskakuje i błyska złotem
		for id, card in cards do
			if (state.upgrades[id] or 0) > (previous.upgrades[id] or 0) then
				pop(card.button, 0.12)
				card.stroke.Color = THEME.gold
				card.stroke.Thickness = 4
				TweenService:Create(card.stroke, TweenInfo.new(0.8, Enum.EasingStyle.Quad), {
					Color = CARD_STROKE,
					Thickness = 2,
				}):Play()
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

local function layout()
	local scale = UiScale.get()
	for _, target in { stats, languageButton, top, upgradePanel, upgradeButton, toast } do
		layoutScale(target, scale)
	end
	languageButton.Position = UDim2.new(0, 12, 0, 8 + math.floor(80 * scale) + 8)
	-- Pasek oleju (66) + baner „Wracaj!” (64) + odstępy, potem połowa wysokości komunikatu
	toastY = math.floor(8 + 66 * scale + 8 + 64 * scale + 12 + 23 * scale)
	if not toast.Visible then
		toast.Position = UDim2.new(0.5, 0, 0, toastY)
	end

	-- ZBIERZ zawsze obok przycisku skoku: na małych ekranach skok jest mniejszy i niżej
	local size = math.floor(112 * math.max(scale, 0.62))
	pickButton.Size = UDim2.fromOffset(size, size)
	pickButton.Position = if UiScale.isSmall() then UDim2.new(1, -112, 1, -14) else UDim2.new(1, -190, 1, -40)
	-- „Ulepszenia” przy prawej krawędzi, nad przyciskami ZBIERZ i skoku
	upgradeButton.Position = UDim2.new(1, -12, 0.42, 0)
end
UiScale.onChanged(layout)

Hud.setPick(false, false)
render()

return Hud
