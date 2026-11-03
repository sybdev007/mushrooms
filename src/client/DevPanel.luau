--!strict
-- Panel DEV (UI v2, makiety 06/07 w Figmie): przycisk 🛠 pod przełącznikiem języka (lewy górny róg), widoczny tylko dla
-- deweloperów (Studio, twórca gry, Config.DevUserIds). Każdą akcję i tak sprawdza serwer (GameService).
--   lewa kolumna: kategorie z liczbą akcji (na żywej grze: ile z nich działa),
--   środek: wyszukiwarka i akcje w sekcjach; plakietka „na żywo” / „Studio” przy każdej akcji,
--     a na opublikowanej grze akcje tylko-Studio są szare (serwer i tak by je odrzucił),
--   prawa kolumna: stan konta i serwera, ostatnie akcje, ostrzeżenie o prawdziwych zapisach.
-- Akcje oznaczone jako niebezpieczne trzeba kliknąć dwa razy (drugi raz w ciągu 4 s).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Localize = require(script.Parent.Localize)
local PanelKit = require(script.Parent.PanelKit)
local UiFx = require(script.Parent.UiFx)
local UiKit = require(script.Parent.UiKit)
local UiScale = require(script.Parent.UiScale)

local DevPanel = {}

local player = Players.LocalPlayer
local DevAction = Remotes.get("DevAction")
local STUDIO = RunService:IsStudio()

type Action = { id: string, label: string, danger: boolean? }
type Section = { name: string, actions: { Action } }
type Category = { id: string, name: string, sections: { Section } }

local CATEGORIES: { Category } = {
	{
		id = "player",
		name = "Gracz",
		sections = {
			{ name = "Monety", actions = {
				{ id = "coins10k", label = "+10 000 💰" },
				{ id = "coins100k", label = "+100 000 💰" },
				{ id = "coins1m", label = "+1 000 000 💰" },
				{ id = "coinsZero", label = "Zeruj monety" },
			} },
			{ name = "Koszyk i latarnia", actions = {
				{ id = "basketClear", label = "Opróżnij koszyk" },
				{ id = "basketFill", label = "Napełnij koszyk" },
				{ id = "oilFull", label = "Pełny olej" },
				{ id = "oilLow", label = "Olej 10%" },
			} },
			{ name = "Ulepszenia", actions = {
				{ id = "upgradesMax", label = "Ulepszenia MAX" },
				{ id = "upgradesReset", label = "Ulepszenia na 0" },
			} },
		},
	},
	{
		id = "teleports",
		name = "Teleporty",
		sections = {
			{ name = "Las", actions = {
				{ id = "tpCabin", label = "TP: chatka" },
				{ id = "tpPlaza", label = "TP: plac portali" },
				{ id = "tpGrove", label = "TP: gniazdo Leszego" },
				{ id = "tpPortal", label = "TP: portal w lesie" },
			} },
			{ name = "Jaskinia", actions = {
				{ id = "tpCamp", label = "TP: obozowisko" },
				{ id = "tpAbyss", label = "TP: Otchłań" },
				{ id = "tpLair", label = "TP: skarbiec Skarbnika" },
			} },
			{ name = "Bagna", actions = {
				{ id = "tpSwamp", label = "TP: przystań (bagna)" },
				{ id = "tpPond", label = "TP: staw Utopca" },
			} },
		},
	},
	{
		id = "world",
		name = "Świat i pora",
		sections = {
			{ name = "Pora dnia", actions = {
				{ id = "cycleDawn", label = "Świt teraz (60 s)" },
				{ id = "cycleNight", label = "Noc teraz (60 s)" },
			} },
			{ name = "Światy", actions = {
				{ id = "caveUnlock", label = "Odblokuj jaskinię" },
				{ id = "caveLock", label = "Zablokuj jaskinię" },
				{ id = "swampUnlock", label = "Odblokuj bagna" },
				{ id = "swampLock", label = "Zablokuj bagna" },
			} },
		},
	},
	{
		id = "garden",
		name = "Ogródek",
		sections = {
			{ name = "Skrzynia i x2", actions = {
				{ id = "pot20m", label = "Skrzynia: +20 min dochodu" },
				{ id = "away30m", label = "Powrót po 30 min (x2)" },
				{ id = "away3h", label = "Powrót po 3 h (x2)" },
			} },
		},
	},
	{
		id = "progress",
		name = "Postęp",
		sections = {
			{ name = "Grzybopedia", actions = {
				{ id = "atlasGold", label = "Księga: wszystko złote" },
				{ id = "atlasRainbow", label = "Księga: wszystko" },
				{ id = "atlasClear", label = "Księga: wyczyść" },
			} },
			{ name = "Strażnicy", actions = {
				{ id = "bestiaryNext", label = "Strażnicy: odkryj następnego" },
				{ id = "bestiaryClear", label = "Strażnicy: wyczyść" },
			} },
			{ name = "Zadania i rankingi", actions = {
				{ id = "questsDone", label = "Zadania: ukończ" },
				{ id = "questsNew", label = "Zadania: nowy dzień" },
				{ id = "boardsRefresh", label = "Rankingi: odśwież" },
			} },
		},
	},
	{
		id = "tutorial",
		name = "Samouczek",
		sections = {
			{ name = "Samouczek", actions = {
				{ id = "tutorialReset", label = "Samouczek od nowa" },
				{ id = "tutorialNext", label = "Samouczek: następny krok" },
				{ id = "tutorialSkip", label = "Pomiń samouczek" },
			} },
		},
	},
	{
		id = "expedition",
		name = "Wyprawy",
		sections = {
			{ name = "Wyprawy grupowe", actions = {
				{ id = "expeditionGroup", label = "Wyprawa: grupa x3 (60 s)" },
				{ id = "expeditionDown", label = "Wyprawa: zgaś mi latarnię" },
			} },
		},
	},
	{
		id = "halloween",
		name = "🎃 Halloween",
		sections = {
			{ name = "Wydarzenia (ogłaszane)", actions = {
				{ id = "spiritNight", label = "🎃 Noc Dziadów (10 min)" },
				{ id = "pumpkinBoom", label = "🎃 Dyniowy wysyp" },
			} },
			{ name = "Cukierki i kocioł", actions = {
				{ id = "candy50", label = "🎃 +50 cukierków" },
				{ id = "candyReset", label = "🎃 Cukierki na 0" },
				{ id = "cauldron", label = "🎃 Kocioł (5 🍬)" },
			} },
		},
	},
	{
		id = "danger",
		name = "Strefa zagrożenia",
		sections = {
			{ name = "Dwa kliknięcia · wyrzuca z gry", actions = {
				{ id = "resetSave", label = "⚠️ Wyzeruj MÓJ zapis", danger = true },
			} },
		},
	},
}

-- Czy akcja działa tutaj (serwer: wszystko w Studio; na żywo teleporty i Config.DevLiveActions)
local function liveOk(id: string): boolean
	return string.sub(id, 1, 2) == "tp" or Config.DevLiveActions[id] == true
end
local function allowed(id: string): boolean
	return STUDIO or liveOk(id)
end

-- ===== Wygląd =====

local OUTLINE = PanelKit.OUTLINE
local BG = Color3.fromRGB(31, 22, 16)
local NAV_BG = Color3.fromRGB(23, 16, 11)
local LINE = Color3.fromRGB(58, 42, 28)
local TEXT = PanelKit.TEXT
local MUTED = PanelKit.MUTED
local DIM = Color3.fromRGB(138, 114, 88)
local GOLD = PanelKit.GOLD
local GREEN = PanelKit.GREEN
local ACTION = Color3.fromRGB(86, 60, 40)
local DANGER = Color3.fromRGB(176, 52, 40)
local LIVE_BG = Color3.fromRGB(34, 56, 27)
local STUDIO_BG = Color3.fromRGB(52, 52, 52)

local WIDTH = 1060
local HEIGHT = 610
local NAV_W = 230
local SIDE_W = 280

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
	s.Parent = parent
	return s
end

local function text(parent: Instance, name: string, size: UDim2, position: UDim2, maxSize: number, color: Color3?, font: Enum.Font?): TextLabel
	local l = PanelKit.label(parent, name, size, position, maxSize, color or TEXT, font or PanelKit.BODY_FONT)
	l.TextXAlignment = Enum.TextXAlignment.Left
	return l
end

local function pill(parent: Instance, label: string, bg: Color3, fg: Color3, height: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Pill"
	frame.AutomaticSize = Enum.AutomaticSize.X
	frame.Size = UDim2.fromOffset(0, height)
	frame.BackgroundColor3 = bg
	frame.Parent = parent
	corner(frame, 8)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = frame
	local l = Instance.new("TextLabel")
	l.Name = "Text"
	l.BackgroundTransparency = 1
	l.AutomaticSize = Enum.AutomaticSize.X
	l.Size = UDim2.fromScale(0, 1)
	l.Font = PanelKit.BODY_FONT
	l.TextSize = math.max(10, height - 8)
	l.TextColor3 = fg
	l.Text = label
	l.Parent = frame
	return frame
end

local gui = Instance.new("ScreenGui")
gui.Name = "DevPanel"
gui.ResetOnSpawn = false
gui.DisplayOrder = 9
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local toggle = Instance.new("TextButton")
toggle.Name = "Toggle"
toggle.Size = UDim2.fromOffset(70, 30)
toggle.Text = ""
toggle.Parent = gui
local toggleStroke = UiKit.button(toggle, PanelKit.VIOLET, { gloss = true })
toggleStroke.Color = OUTLINE
local toggleText = text(toggle, "Text", UDim2.new(1, -8, 1, -8), UDim2.fromOffset(4, 4), 16, Color3.new(1, 1, 1), PanelKit.TITLE_FONT)
toggleText.TextXAlignment = Enum.TextXAlignment.Center
toggleText.Text = "🛠 DEV"
toggleText.ZIndex = 4
UiKit.outline(toggleText, 1.5)
local toggleScale = toggle:FindFirstChildOfClass("UIScale") :: UIScale

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(WIDTH, HEIGHT)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.52)
panel.BackgroundColor3 = BG
panel.Visible = false
panel.Active = true
panel.ClipsDescendants = true
panel.Parent = gui
corner(panel, 18)
stroke(panel, Color3.fromRGB(107, 74, 44), 3)
local panelScale = Instance.new("UIScale")
panelScale.Parent = panel

-- ===== Lewa kolumna: kategorie =====

local nav = Instance.new("Frame")
nav.Name = "Nav"
nav.Size = UDim2.new(0, NAV_W, 1, 0)
nav.BackgroundColor3 = NAV_BG
nav.Parent = panel
local navLine = Instance.new("Frame")
navLine.Size = UDim2.new(0, 2, 1, 0)
navLine.Position = UDim2.new(1, -2, 0, 0)
navLine.BackgroundColor3 = LINE
navLine.BorderSizePixel = 0
navLine.Parent = nav

local logo = text(nav, "Logo", UDim2.fromOffset(160, 40), UDim2.fromOffset(18, 14), 34, GOLD, PanelKit.TITLE_FONT)
logo.Text = "DEV"
UiKit.outline(logo, 2.5)
UiFx.textGradient(logo, Color3.fromRGB(255, 244, 190), Color3.fromRGB(255, 176, 40))

local modeRow = Instance.new("Frame")
modeRow.Name = "Mode"
modeRow.BackgroundTransparency = 1
modeRow.Size = UDim2.new(1, -30, 0, 24)
modeRow.Position = UDim2.fromOffset(18, 58)
modeRow.Parent = nav
local modeLayout = Instance.new("UIListLayout")
modeLayout.FillDirection = Enum.FillDirection.Horizontal
modeLayout.Padding = UDim.new(0, 6)
modeLayout.Parent = modeRow
pill(modeRow, if STUDIO then "Studio" else "Na żywo", if STUDIO then Color3.fromRGB(90, 64, 18) else LIVE_BG, if STUDIO then GOLD else GREEN, 22)
pill(modeRow, "tylko moje konto", Color3.fromRGB(52, 36, 26), MUTED, 22)

local navList = Instance.new("Frame")
navList.Name = "List"
navList.BackgroundTransparency = 1
navList.Size = UDim2.new(1, -24, 1, -110)
navList.Position = UDim2.fromOffset(12, 98)
navList.Parent = nav
local navLayout = Instance.new("UIListLayout")
navLayout.Padding = UDim.new(0, 4)
navLayout.SortOrder = Enum.SortOrder.LayoutOrder
navLayout.Parent = navList

-- ===== Środek: pasek z wyszukiwarką i akcje =====

local main = Instance.new("Frame")
main.Name = "Main"
main.BackgroundTransparency = 1
main.Size = UDim2.new(1, -(NAV_W + SIDE_W), 1, 0)
main.Position = UDim2.fromOffset(NAV_W, 0)
main.Parent = panel

local heading = text(main, "Heading", UDim2.fromOffset(200, 34), UDim2.fromOffset(20, 18), 28, TEXT, PanelKit.TITLE_FONT)
UiKit.outline(heading, 2)

local search = Instance.new("TextBox")
search.Name = "Search"
search.Size = UDim2.new(1, -250, 0, 38)
search.Position = UDim2.fromOffset(230, 16)
search.BackgroundColor3 = Color3.fromRGB(18, 12, 8)
search.Font = PanelKit.BODY_FONT
search.TextSize = 15
search.TextColor3 = TEXT
search.PlaceholderColor3 = Color3.fromRGB(125, 102, 80)
search.PlaceholderText = "🔍  Szukaj akcji… (np. olej, tp)"
search.Text = ""
search.ClearTextOnFocus = false
search.TextXAlignment = Enum.TextXAlignment.Left
search.Parent = main
corner(search, 10)
stroke(search, LINE, 2)
local searchPad = Instance.new("UIPadding")
searchPad.PaddingLeft = UDim.new(0, 12)
searchPad.Parent = search

local scroll = Instance.new("ScrollingFrame")
scroll.Name = "Actions"
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.Size = UDim2.new(1, -24, 1, -78)
scroll.Position = UDim2.fromOffset(16, 68)
scroll.CanvasSize = UDim2.new()
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.ScrollBarThickness = 6
scroll.ScrollBarImageColor3 = Color3.fromRGB(107, 74, 44)
scroll.Parent = main
local scrollLayout = Instance.new("UIListLayout")
scrollLayout.Padding = UDim.new(0, 8)
scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
scrollLayout.Parent = scroll
local scrollPad = Instance.new("UIPadding")
scrollPad.PaddingTop = UDim.new(0, 4)
scrollPad.PaddingLeft = UDim.new(0, 4)
scrollPad.PaddingRight = UDim.new(0, 10)
scrollPad.PaddingBottom = UDim.new(0, 8)
scrollPad.Parent = scroll

-- ===== Prawa kolumna: stan, dziennik, ostrzeżenie =====

local side = Instance.new("Frame")
side.Name = "Side"
side.Size = UDim2.new(0, SIDE_W, 1, 0)
side.AnchorPoint = Vector2.new(1, 0)
side.Position = UDim2.fromScale(1, 0)
side.BackgroundColor3 = NAV_BG
side.Parent = panel
local sideLine = Instance.new("Frame")
sideLine.Size = UDim2.new(0, 2, 1, 0)
sideLine.BackgroundColor3 = LINE
sideLine.BorderSizePixel = 0
sideLine.Parent = side

local who = text(side, "Who", UDim2.new(1, -36, 0, 28), UDim2.fromOffset(18, 18), 22, TEXT, PanelKit.TITLE_FONT)
who.Text = player.Name
UiKit.outline(who, 2)

type Kv = { key: TextLabel, value: TextLabel }
local kvs: { Kv } = {}
for i = 1, 8 do
	local y = 54 + (i - 1) * 28
	local k = text(side, "K" .. i, UDim2.new(0.5, -18, 0, 20), UDim2.fromOffset(18, y), 14, MUTED)
	local v = text(side, "V" .. i, UDim2.new(0.5, -18, 0, 20), UDim2.new(0.5, 0, 0, y), 14, TEXT)
	v.TextXAlignment = Enum.TextXAlignment.Right
	local rule = Instance.new("Frame")
	rule.BorderSizePixel = 0
	rule.BackgroundColor3 = Color3.fromRGB(46, 34, 24)
	rule.Size = UDim2.new(1, -36, 0, 1)
	rule.Position = UDim2.fromOffset(18, y + 24)
	rule.Parent = side
	table.insert(kvs, { key = k, value = v })
end

local logTitle = text(side, "LogTitle", UDim2.new(1, -36, 0, 18), UDim2.fromOffset(18, 286), 13, DIM)
logTitle.Text = "OSTATNIE AKCJE"
local logBox = Instance.new("Frame")
logBox.Name = "Log"
logBox.Size = UDim2.new(1, -36, 0, 150)
logBox.Position = UDim2.fromOffset(18, 308)
logBox.BackgroundColor3 = Color3.fromRGB(18, 12, 8)
logBox.Parent = side
corner(logBox, 10)
local logPad = Instance.new("UIPadding")
logPad.PaddingTop = UDim.new(0, 8)
logPad.PaddingLeft = UDim.new(0, 10)
logPad.PaddingRight = UDim.new(0, 8)
logPad.Parent = logBox
local logLayout = Instance.new("UIListLayout")
logLayout.Padding = UDim.new(0, 4)
logLayout.SortOrder = Enum.SortOrder.LayoutOrder
logLayout.Parent = logBox

local warn = Instance.new("Frame")
warn.Name = "Warn"
warn.Size = UDim2.new(1, -36, 0, 100)
warn.Position = UDim2.new(0, 18, 1, -116)
warn.BackgroundColor3 = Color3.fromRGB(58, 42, 16)
warn.Parent = side
corner(warn, 10)
stroke(warn, Color3.fromRGB(122, 90, 26), 2)
local warnText = text(warn, "Text", UDim2.new(1, -20, 1, -16), UDim2.fromOffset(10, 8), 13, Color3.fromRGB(255, 217, 154))
warnText.TextWrapped = true
warnText.TextYAlignment = Enum.TextYAlignment.Top
warnText.Text = if STUDIO
	then "⚠️ Studio z dostępem do API zapisuje do PRAWDZIWYCH DataStore i rankingów. Akcje zmieniają tylko twoje konto."
	else "Szare akcje działają tylko w Studio — serwer i tak je odrzuci (Config.DevLiveActions). Teleporty działają zawsze."

-- ===== Przyciski akcji =====

type Entry = { action: Action, category: Category, section: Section }
local entries: { Entry } = {}
for _, category in CATEGORIES do
	for _, section in category.sections do
		for _, action in section.actions do
			table.insert(entries, { action = action, category = category, section = section })
		end
	end
end

local logLines: { string } = {}
local function addLog(line: string)
	table.insert(logLines, 1, line)
	while #logLines > 7 do
		table.remove(logLines)
	end
	for _, child in logBox:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	for i, entry in logLines do
		local l = text(logBox, "Line", UDim2.new(1, 0, 0, 16), UDim2.new(), 13, MUTED)
		l.LayoutOrder = i
		l.Text = entry
		l.TextTransparency = math.min(0.6, (i - 1) * 0.1)
	end
end

local function clock(): string
	local t = os.date("*t")
	return string.format("%02d:%02d", t.hour, t.min)
end

local function actionButton(parent: Instance, action: Action, order: number): TextButton
	local ok = allowed(action.id)
	local button = Instance.new("TextButton")
	button.Name = action.id
	button.Text = ""
	button.LayoutOrder = order
	button.Parent = parent
	local color = if not ok then Color3.fromRGB(60, 52, 46) elseif action.danger then DANGER else ACTION
	local s = UiKit.button(button, color, { radius = UDim.new(0, 10), stroke = 2 })
	s.Color = if action.danger then Color3.fromRGB(122, 42, 32) else OUTLINE
	button.Active = ok
	local label = text(button, "Label", UDim2.new(1, -78, 1, -10), UDim2.fromOffset(10, 5), 15, if action.danger then Color3.fromRGB(255, 200, 190) else TEXT)
	label.TextWrapped = true
	label.ZIndex = 4
	label.Text = action.label
	local badge = pill(button, if liveOk(action.id) then "na żywo" else "Studio", if liveOk(action.id) then LIVE_BG else STUDIO_BG, if liveOk(action.id) then GREEN else Color3.fromRGB(176, 176, 176), 18)
	badge.AnchorPoint = Vector2.new(1, 0.5)
	badge.Position = UDim2.new(1, -8, 0.5, 0)
	badge.ZIndex = 4
	if not ok then
		label.TextTransparency = 0.5
		badge.BackgroundTransparency = 0.3
	end
	local armedAt = -math.huge
	button.Activated:Connect(function()
		if not ok then
			UiFx.shake(button)
			addLog("✕ " .. clock() .. " · " .. action.label .. " — tylko Studio")
			return
		end
		if action.danger and os.clock() - armedAt > 4 then
			armedAt = os.clock()
			label.Text = "Na pewno? Kliknij jeszcze raz"
			UiFx.sound("warn", 0.4)
			task.delay(4, function()
				label.Text = action.label
			end)
			return
		end
		armedAt = -math.huge
		DevAction:FireServer(action.id)
		UiFx.sound("blip", 0.5, 1.2)
		UiKit.burst(gui, button.AbsolutePosition + button.AbsoluteSize / 2, 6)
		addLog("✓ " .. clock() .. " · " .. action.label)
	end)
	return button
end

local function sectionBlock(name: string, actions: { Action }, order: number)
	local title = text(scroll, "Section", UDim2.new(1, 0, 0, 18), UDim2.new(), 13, DIM)
	title.Text = name -- bez string.upper: psuje polskie litery (działa tylko na ASCII)
	title.LayoutOrder = order * 2
	local grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.Size = UDim2.fromScale(1, 0)
	grid.LayoutOrder = order * 2 + 1
	grid.Parent = scroll
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(1 / 3, -6, 0, 50)
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	for i, action in actions do
		actionButton(grid, action, i)
	end
end

local function clearScroll()
	for _, child in scroll:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- ===== Kategorie =====

type NavItem = { frame: TextButton, bar: Frame, label: TextLabel, dot: Frame, category: Category }
local navItems: { NavItem } = {}
local current: Category = CATEGORIES[1]

local function countOf(category: Category): (number, number)
	local total, ok = 0, 0
	for _, section in category.sections do
		for _, action in section.actions do
			total += 1
			if allowed(action.id) then
				ok += 1
			end
		end
	end
	return ok, total
end

local function showCategory(category: Category)
	current = category
	search.Text = ""
	heading.Text = category.name
	clearScroll()
	for i, section in category.sections do
		sectionBlock(section.name, section.actions, i)
	end
	scroll.CanvasPosition = Vector2.zero
	for _, item in navItems do
		local on = item.category == category
		item.frame.BackgroundTransparency = if on then 0 else 1
		item.bar.Visible = on
		item.dot.BackgroundColor3 = if item.category.id == "danger" then UiKit.COLORS.red elseif on then GOLD else Color3.fromRGB(107, 84, 64)
		item.label.TextColor3 = if item.category.id == "danger" then Color3.fromRGB(255, 154, 138) elseif on then TEXT else MUTED
	end
end

for order, category in CATEGORIES do
	local ok, total = countOf(category)
	local item = Instance.new("TextButton")
	item.Name = category.id
	item.Text = ""
	item.AutoButtonColor = false
	item.LayoutOrder = if category.id == "danger" then 999 else order
	item.Size = UDim2.new(1, 0, 0, 38)
	item.BackgroundColor3 = Color3.fromRGB(58, 40, 24)
	item.BackgroundTransparency = 1
	item.Parent = navList
	corner(item, 10)
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Size = UDim2.new(0, 4, 1, -12)
	bar.Position = UDim2.fromOffset(0, 6)
	bar.BackgroundColor3 = GOLD
	bar.BorderSizePixel = 0
	bar.Visible = false
	bar.Parent = item
	corner(bar, 2)
	local dot = Instance.new("Frame")
	dot.Size = UDim2.fromOffset(8, 8)
	dot.AnchorPoint = Vector2.new(0, 0.5)
	dot.Position = UDim2.new(0, 14, 0.5, 0)
	dot.Parent = item
	corner(dot)
	local label = text(item, "Name", UDim2.new(1, -86, 0, 20), UDim2.new(0, 32, 0.5, -10), 16, MUTED)
	label.Text = category.name
	local count = text(item, "Count", UDim2.fromOffset(48, 18), UDim2.new(1, -54, 0.5, -9), 13, DIM)
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.Text = if STUDIO then tostring(total) else string.format("%d / %d", ok, total)
	if not STUDIO and ok == 0 then
		item.AutoButtonColor = false
		label.TextTransparency = 0.45
		count.TextTransparency = 0.45
	end
	item.MouseEnter:Connect(function()
		if current ~= category then
			item.BackgroundTransparency = 0.6
		end
	end)
	item.MouseLeave:Connect(function()
		if current ~= category then
			item.BackgroundTransparency = 1
		end
	end)
	item.Activated:Connect(function()
		UiFx.sound("blip", 0.35)
		showCategory(category)
	end)
	table.insert(navItems, { frame = item, bar = bar, label = label, dot = dot, category = category })
end

-- Wyszukiwarka: akcje ze wszystkich kategorii, których nazwa zawiera wpisany tekst
search:GetPropertyChangedSignal("Text"):Connect(function()
	local query = string.lower(search.Text)
	if query == "" then
		if heading.Text ~= current.name then
			showCategory(current)
		end
		return
	end
	heading.Text = "Wyniki"
	clearScroll()
	local found: { Action } = {}
	for _, entry in entries do
		if string.find(string.lower(entry.action.label), query, 1, true) or string.find(string.lower(entry.action.id), query, 1, true) then
			table.insert(found, entry.action)
		end
	end
	if #found == 0 then
		local none = text(scroll, "None", UDim2.new(1, 0, 0, 24), UDim2.new(), 15, MUTED)
		none.Text = "Brak akcji dla „" .. search.Text .. "”"
	else
		sectionBlock(string.format("%d wyników", #found), found, 1)
	end
end)

-- ===== Stan konta i serwera =====

local lastState: any = nil

local function formatCoins(value: number): string
	local s = tostring(math.floor(value + 0.5))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (formatted:gsub("^ ", ""))
end

local function renderSide()
	local state = lastState
	local now = os.time()
	local rows: { { string } } = {}
	if state then
		table.insert(rows, { "Monety", formatCoins(state.coins or 0) })
		local zone = state.zone and Config.Zones[state.zone]
		table.insert(rows, { "Strefa", if zone then Localize.t(zone.key) else "—" })
		table.insert(rows, { "Koszyk", string.format("%d / %d", state.basketCount or 0, state.basketMax or 0) })
		local oil = if state.oilMax and state.oilMax > 0 then math.floor(state.oil / state.oilMax * 100 + 0.5) else 0
		table.insert(rows, { "Olej", oil .. "%" })
		local boom = (state.boomUntil or 0) - now
		table.insert(rows, { "Wysyp", if boom > 0 then string.format("%d:%02d", boom // 60, boom % 60) else "—" })
	end
	local phase = Workspace:GetAttribute("CyclePhase")
	local ends = Workspace:GetAttribute("CycleEndsAt")
	local left = if typeof(ends) == "number" then math.max(0, ends - now) else nil
	local phaseName = if phase == "night" then "Noc" elseif phase == "dawn" then "Świt" else tostring(phase or "—")
	table.insert(rows, { "Pora", if left then string.format("%s · %d:%02d", phaseName, left // 60, left % 60) else phaseName })
	table.insert(rows, { "Gracze", string.format("%d / %d", #Players:GetPlayers(), Players.MaxPlayers) })
	table.insert(rows, { "Tryb", if STUDIO then "Studio" else "Na żywo" })
	for i, kv in kvs do
		local row = rows[i]
		kv.key.Text = if row then row[1] else ""
		kv.value.Text = if row then row[2] else ""
	end
end

-- ===== Otwieranie, skala, położenie =====

local function setOpen(open: boolean)
	if open == panel.Visible then
		return
	end
	panel.Visible = open
	PanelKit.setModal("DevPanel", open)
	if open then
		renderSide()
		UiFx.popIn(panelScale, (panelScale:GetAttribute("Base") :: number?) or 1, 0.85)
		UiFx.sound("whoosh", 0.3)
	end
end

toggle.Activated:Connect(function()
	setOpen(not panel.Visible)
end)

local closeButton = Instance.new("TextButton")
closeButton.Name = "Close"
closeButton.Size = UDim2.fromOffset(40, 40)
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -12, 0, 12)
closeButton.Text = ""
closeButton.ZIndex = 5
closeButton.Parent = panel
local closeStroke = UiKit.button(closeButton, UiKit.COLORS.red, { radius = UDim.new(0, 12), stroke = 2.5, gloss = true })
closeStroke.Color = OUTLINE
UiKit.icon("close", closeButton, UDim2.fromScale(0.7, 0.7), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5)).ZIndex = 6
closeButton.Activated:Connect(function()
	setOpen(false)
end)
who.Size = UDim2.new(1, -86, 0, 28)

local function fit()
	local scale = UiScale.get()
	toggleScale:SetAttribute("Base", scale)
	toggleScale.Scale = scale
	-- Okno mieści się na ekranie (telefon): nie większe niż ekran minus margines
	local camera = Workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local panelFit = math.clamp(math.min((viewport.X - 40) / WIDTH, (viewport.Y - 70) / HEIGHT), 0.45, 1)
	panelScale:SetAttribute("Base", panelFit)
	panelScale.Scale = panelFit
	-- Pod rzędem przycisku języka (sklep jest teraz w kolumnie po prawej); liczniki Wysypu są pod nim
	local y = UiScale.rowBottom() + 6
	toggle.Position = UDim2.fromOffset(12, y)
end
UiScale.onChanged(fit)
task.defer(function()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end
	fit()
end)

showCategory(CATEGORIES[1])

task.spawn(function()
	while true do
		task.wait(0.5)
		if panel.Visible then
			renderSide()
		end
	end
end)

function DevPanel.setEnabled(enabled: boolean)
	gui.Enabled = enabled
	if not enabled then
		setOpen(false)
	end
end

function DevPanel.update(state: any)
	lastState = state
end

return DevPanel
