--!strict
-- Tabelka szans na mutacje (otwierana przyciskiem „Szanse” w sklepie).
-- Mikstura szczęścia i Wysyp to płatne zwiększenie szans, więc gracz musi widzieć prawdziwe
-- procenty: zwykłe, tu i teraz (nożyk, głębokość strefy, zdarzenie nocy, Wysyp, mikstura)
-- oraz z miksturą. Liczy to samo Economy.luck / variantOdds / tagOdds, którego używa serwer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Cycle = require(ReplicatedStorage.Shared.Cycle)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Localize = require(script.Parent.Localize)
local UiKit = require(script.Parent.UiKit)
local UiScale = require(script.Parent.UiScale)

local OddsPanel = {}

local TITLE_FONT = Enum.Font.FredokaOne
local BODY_FONT = Enum.Font.GothamBold
local TEXT = Color3.fromRGB(252, 238, 210)
local MUTED = Color3.fromRGB(214, 188, 150)
local ACCENT = Color3.fromRGB(255, 214, 120)
local GREEN = Color3.fromRGB(150, 255, 150)
local ROW_HEIGHT = 24
local WIDTH = 470

local gui = Instance.new("ScreenGui")
gui.Name = "Odds"
gui.ResetOnSpawn = false
gui.DisplayOrder = 6
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local rowCount = #Config.Variants + #Config.Tags
local HEIGHT = 112 + (rowCount + 1) * ROW_HEIGHT + 8 + 76

local panel = Instance.new("Frame")
panel.Name = "OddsPanel"
panel.Size = UDim2.fromOffset(WIDTH, HEIGHT)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.BackgroundColor3 = Color3.fromRGB(40, 28, 20)
panel.BackgroundTransparency = 0
panel.Visible = false
panel.Parent = gui
local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 14)
panelCorner.Parent = panel
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(200, 146, 74)
panelStroke.Thickness = 2
panelStroke.Parent = panel
local panelScale = Instance.new("UIScale")
panelScale.Parent = panel

local function text(name: string, size: UDim2, position: UDim2, font: Enum.Font, maxSize: number, color: Color3?): TextLabel
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
	l.Parent = panel
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = maxSize
	c.Parent = l
	return l
end

local title = text("Title", UDim2.new(1, -70, 0, 32), UDim2.fromOffset(16, 10), TITLE_FONT, 24, ACCENT)
local close = Instance.new("TextButton")
close.Name = "Close"
close.Size = UDim2.fromOffset(32, 32)
close.Position = UDim2.new(1, -42, 0, 10)
close.Text = ""
close.Parent = panel
UiKit.button(close, UiKit.COLORS.wood, { gloss = true, radius = UDim.new(0, 8) })
UiKit.icon("close", close, UDim2.fromOffset(22, 22), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))

-- „Twoje szczęście: ×3,8” i z czego się bierze
local luckLine = text("Luck", UDim2.new(1, -32, 0, 22), UDim2.fromOffset(16, 46), TITLE_FONT, 18, GREEN)
local partsLine = text("Parts", UDim2.new(1, -32, 0, 30), UDim2.fromOffset(16, 70), BODY_FONT, 12, MUTED)
partsLine.TextWrapped = true

-- Kolumny: nazwa | zwykle | teraz | z miksturą
local COLUMNS = { 0, 0.52, 0.68, 0.84 }
local TABLE_TOP = 108
local function cell(row: number, column: number, font: Enum.Font, color: Color3?): TextLabel
	local x = COLUMNS[column]
	local nextX = COLUMNS[column + 1] or 1
	local l = text(
		string.format("R%dC%d", row, column),
		UDim2.new(nextX - x, if column == 1 then -20 else -6, 0, ROW_HEIGHT - 4),
		UDim2.new(x, if column == 1 then 16 else 0, 0, TABLE_TOP + row * ROW_HEIGHT + 2),
		font,
		if row == 0 then 13 else 15,
		color
	)
	if column > 1 then
		l.TextXAlignment = Enum.TextXAlignment.Center
	end
	return l
end

-- Pasek pod nagłówkiem tabeli
local divider = Instance.new("Frame")
divider.Size = UDim2.new(1, -32, 0, 2)
divider.Position = UDim2.fromOffset(16, TABLE_TOP + ROW_HEIGHT)
divider.BackgroundColor3 = Color3.fromRGB(110, 80, 52)
divider.BorderSizePixel = 0
divider.Parent = panel

local header = { cell(0, 1, BODY_FONT, MUTED), cell(0, 2, BODY_FONT, MUTED), cell(0, 3, BODY_FONT, GREEN), cell(0, 4, BODY_FONT, ACCENT) }

type Row = { name: TextLabel, base: TextLabel, now: TextLabel, potion: TextLabel }
local rows: { Row } = {}
for row = 1, rowCount do
	table.insert(rows, {
		name = cell(row, 1, TITLE_FONT),
		base = cell(row, 2, BODY_FONT, MUTED),
		now = cell(row, 3, TITLE_FONT, GREEN),
		potion = cell(row, 4, TITLE_FONT, ACCENT),
	})
end

local footer = text("Footer", UDim2.new(1, -32, 0, 70), UDim2.fromOffset(16, HEIGHT - 78), BODY_FONT, 12, MUTED)
footer.TextWrapped = true
footer.TextYAlignment = Enum.TextYAlignment.Top

local lastState: any = nil

local function percent(chance: number): string
	local value = chance * 100
	local s = if value >= 10 or value == math.floor(value)
		then string.format("%.0f%%", value)
		elseif value >= 1 then string.format("%.1f%%", value)
		else string.format("%.2f%%", value)
	s = s:gsub("(%.%d-)0+%%$", "%1%%"):gsub("%.%%$", "%%")
	return if Localize.getLocale() == "pl" then (s:gsub("%.", ",")) else s
end

local function times(mult: number): string
	local s = string.format("×%.2f", mult):gsub("0+$", ""):gsub("%.$", "")
	return if Localize.getLocale() == "pl" then (s:gsub("%.", ",")) else s
end

local function colorHex(rgb: { number }): string
	return string.format("#%02X%02X%02X", rgb[1], rgb[2], rgb[3])
end

local function zoneName(index: number): string
	local zone = Config.Zones[index]
	return if zone then Localize.t(zone.key) else ""
end

local function render()
	title.Text = Localize.t("ODDS_TITLE")
	local state = lastState
	local now = os.time()
	local potionActive = state ~= nil and (state.luckUntil or 0) > now
	local input: Economy.LuckInput = {
		knifeLevel = if state and state.upgrades then state.upgrades.knife or 0 else 0,
		zone = if state then state.zone else nil,
		-- Zdarzenie od serwera (uwzględnia Noc Dziadów przywołaną z panelu DEV)
		event = if Workspace:GetAttribute("CyclePhase") == "night" then Cycle.getEvent(Workspace:GetAttribute("CycleEvent")) else nil,
		boom = state ~= nil and (state.boomUntil or 0) > now,
		potion = potionActive,
		member = Players.LocalPlayer:GetAttribute("OwlMember") == true,
		friend = Players.LocalPlayer:GetAttribute("FriendBonus") == true,
	}
	local luck, parts, raw = Economy.luck(input)
	-- Kolumna „z miksturą”: jeśli mikstura już działa, to te same szanse co teraz
	local potionInput = table.clone(input)
	potionInput.potion = true
	local potionLuck = Economy.luck(potionInput)

	luckLine.Text = Localize.t("ODDS_YOUR_LUCK", { times(luck) })
	local names = {}
	for _, part in parts do
		local label = if part.key == "ODDS_DEPTH" and input.zone then zoneName(input.zone) else Localize.t(part.key)
		table.insert(names, label .. " " .. times(part.mult))
	end
	partsLine.Text = if #names > 0 then table.concat(names, "  ·  ") else Localize.t("ODDS_NO_BONUS")
	if raw - luck > 0.01 then
		-- Malejący zysk / limit: pokazujemy, ile byłoby bez balansu
		partsLine.Text ..= "\n" .. Localize.t("ODDS_CAPPED", { times(raw) })
	end

	header[1].Text = Localize.t("ODDS_MUTATION")
	header[2].Text = Localize.t("ODDS_BASE")
	header[3].Text = Localize.t("ODDS_NOW")
	header[4].Text = if potionActive then Localize.t("ODDS_POTION_ON") else Localize.t("ODDS_POTION")

	local baseOdds = Economy.variantOdds(1)
	local nowOdds = Economy.variantOdds(luck)
	local potionOdds = Economy.variantOdds(potionLuck)
	local index = 0
	-- Warianty od najpospolitszego (Srebro) do najrzadszego (Tęcza)
	for i = #baseOdds, 1, -1 do
		index += 1
		local row = rows[index]
		local def = Economy.getVariant(baseOdds[i].id)
		if def then
			row.name.Text = string.format('<font color="%s">%s %s</font> <font size="11" color="#D6BC96">%s</font>', colorHex(def.color), def.icon, Localize.t(def.key), times(def.mult))
		end
		row.base.Text = percent(baseOdds[i].chance)
		row.now.Text = percent(nowOdds[i].chance)
		row.potion.Text = percent(potionOdds[i].chance)
	end
	for _, tag in Config.Tags do
		index += 1
		local row = rows[index]
		row.name.Text = string.format(
			'<font color="%s">%s %s</font> <font size="11" color="#D6BC96">%s · %s</font>',
			colorHex(tag.color),
			tag.icon,
			Localize.t(tag.key),
			times(tag.mult),
			zoneName(tag.zone)
		)
		row.base.Text = percent(Economy.tagOdds(tag, 1))
		-- „Teraz” dla cechy liczymy z głębokością jej własnej strefy (tam rośnie)
		local tagInput = table.clone(input)
		tagInput.zone = tag.zone
		local tagPotion = table.clone(tagInput)
		tagPotion.potion = true
		row.now.Text = percent(Economy.tagOdds(tag, (Economy.luck(tagInput))))
		row.potion.Text = percent(Economy.tagOdds(tag, (Economy.luck(tagPotion))))
	end

	footer.Text = Localize.t("ODDS_FOOTER", { Config.PityRolls })
end

function OddsPanel.update(state: any)
	lastState = state
	if panel.Visible then
		render()
	end
end

function OddsPanel.toggle()
	panel.Visible = not panel.Visible
	if panel.Visible then
		render()
	end
end

close.Activated:Connect(function()
	panel.Visible = false
end)
Localize.onChanged(function()
	if panel.Visible then
		render()
	end
end)
UiScale.onChanged(function()
	panelScale.Scale = UiScale.get()
end)

-- Zdarzenie nocy i liczniki zmieniają się same, więc otwarta tabelka odświeża się co sekundę
task.spawn(function()
	while true do
		task.wait(1)
		if panel.Visible then
			render()
		end
	end
end)

return OddsPanel
