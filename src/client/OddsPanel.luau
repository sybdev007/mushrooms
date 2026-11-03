--!strict
-- Okno „Szanse na mutacje” (otwierane przyciskiem „Szanse” w sklepie; UI v2, makieta 02 w Figmie).
-- Mikstura szczęścia i Wysyp to płatne zwiększenie szans, więc gracz musi widzieć prawdziwe
-- procenty: zwykłe, tu i teraz (nożyk, głębokość strefy, zdarzenie nocy, Wysyp, mikstura)
-- oraz z miksturą. Liczy to samo Economy.luck / variantOdds / tagOdds, którego używa serwer.
-- Pigułka w rogu okna pokazuje twoje szczęście teraz (to samo pokazuje sklep: OddsPanel.luckText).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Cycle = require(ReplicatedStorage.Shared.Cycle)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Localize = require(script.Parent.Localize)
local PanelKit = require(script.Parent.PanelKit)
local UiFx = require(script.Parent.UiFx)
local UiKit = require(script.Parent.UiKit)

local OddsPanel = {}

local TITLE_FONT = PanelKit.TITLE_FONT
local BODY_FONT = PanelKit.BODY_FONT
local OUTLINE = PanelKit.OUTLINE
local TEXT = PanelKit.TEXT
local MUTED = PanelKit.MUTED
local GREEN = PanelKit.GREEN
local GOLD = PanelKit.GOLD

local ROW_H = 38
local ROW_GAP = 6
local COLUMN_W = 104
local rowCount = #Config.Variants + #Config.Tags
local WIDTH = 660
local TABLE_TOP = 64
local HEIGHT = 50 + TABLE_TOP + 24 + rowCount * (ROW_H + ROW_GAP) + 76

local window = PanelKit.window({
	name = "Odds",
	parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	width = WIDTH,
	height = HEIGHT,
	ribbon = PanelKit.VIOLET,
	icon = "sparkles",
	pillIcon = "luck",
	pillColor = Color3.fromRGB(36, 58, 28),
	displayOrder = 8,
})
local content = window.content

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- Skąd bierze się szczęście: nożyk ×1,2 · Wysyp ×1,5 …
local parts = PanelKit.label(content, "Parts", UDim2.new(1, -12, 0, 44), UDim2.fromOffset(6, 8), 15, MUTED, BODY_FONT)
parts.TextWrapped = true
parts.TextXAlignment = Enum.TextXAlignment.Left
parts.TextYAlignment = Enum.TextYAlignment.Top

-- Nagłówki kolumn
local function header(text: string, x: number, width: number, color: Color3, right: boolean): TextLabel
	local l = PanelKit.label(content, "Head", UDim2.fromOffset(width, 20), UDim2.new(if right then 1 else 0, x, 0, TABLE_TOP), 14, color, BODY_FONT)
	l.TextXAlignment = if right then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left
	l.Text = text
	return l
end
local headName = header("", 20, 220, MUTED, false)
local headBase = header("", -(COLUMN_W * 3 + 18), COLUMN_W, MUTED, true)
local headNow = header("", -(COLUMN_W * 2 + 18), COLUMN_W, GREEN, true)
local headPotion = header("", -(COLUMN_W + 18), COLUMN_W, GOLD, true)

type Row = { frame: Frame, dot: Frame, name: TextLabel, sub: TextLabel, base: TextLabel, now: TextLabel, potion: TextLabel }
local rows: { Row } = {}

local function buildRow(index: number): Row
	local frame = Instance.new("Frame")
	frame.Name = "Row" .. index
	frame.Size = UDim2.new(1, 0, 0, ROW_H)
	frame.Position = UDim2.fromOffset(0, TABLE_TOP + 24 + (index - 1) * (ROW_H + ROW_GAP))
	frame.BackgroundColor3 = PanelKit.CARD
	frame.Parent = content
	PanelKit.corner(frame, UDim.new(0, 12))
	PanelKit.stroke(frame, OUTLINE, 2.5)
	local shade = Instance.new("UIGradient")
	shade.Rotation = 90
	shade.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(196, 188, 180))
	shade.Parent = frame

	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.Size = UDim2.fromOffset(20, 20)
	dot.AnchorPoint = Vector2.new(0, 0.5)
	dot.Position = UDim2.new(0, 12, 0.5, 0)
	dot.Parent = frame
	PanelKit.corner(dot, UDim.new(1, 0))
	PanelKit.stroke(dot, OUTLINE, 2.5)

	local name = PanelKit.label(frame, "Name", UDim2.fromOffset(150, 24), UDim2.new(0, 42, 0.5, -12), 20, TEXT, TITLE_FONT)
	name.TextXAlignment = Enum.TextXAlignment.Left
	UiKit.outline(name, 2)
	local sub = PanelKit.label(frame, "Sub", UDim2.fromOffset(100, 18), UDim2.new(0, 196, 0.5, -9), 13, MUTED, BODY_FONT)
	sub.TextXAlignment = Enum.TextXAlignment.Left

	local function value(x: number, color: Color3, font: Enum.Font): TextLabel
		local l = PanelKit.label(frame, "Value", UDim2.fromOffset(COLUMN_W, 24), UDim2.new(1, x, 0.5, -12), 19, color, font)
		UiKit.outline(l, 1.5)
		return l
	end
	return {
		frame = frame,
		dot = dot,
		name = name,
		sub = sub,
		base = value(-(COLUMN_W * 3 + 18), Color3.fromRGB(240, 222, 196), BODY_FONT),
		now = value(-(COLUMN_W * 2 + 18), GREEN, TITLE_FONT),
		potion = value(-(COLUMN_W + 18), GOLD, TITLE_FONT),
	}
end
for i = 1, rowCount do
	table.insert(rows, buildRow(i))
end

-- Wiersze wariantów od najpospolitszego (Srebro) do najrzadszego (Tęcza); złoto i tęcza błyszczą
do
	local variants = Economy.variantOdds(1)
	local index = 0
	for i = #variants, 1, -1 do
		index += 1
		local def = Economy.getVariant(variants[i].id)
		local r = rows[index]
		if def then
			r.dot.BackgroundColor3 = rgb(def.color)
			r.name.TextColor3 = Color3.new(1, 1, 1)
			if def.id == "rainbow" then
				r.dot.BackgroundColor3 = Color3.new(1, 1, 1)
				UiFx.rainbow(r.name, 0.3)
				UiFx.rainbow(r.dot, 0.3)
			elseif def.id == "gold" then
				UiFx.textGradient(r.name, Color3.fromRGB(255, 248, 200), Color3.fromRGB(255, 180, 30))
			else
				r.name.TextColor3 = rgb(def.color)
			end
		end
	end
	for _, tag in Config.Tags do
		index += 1
		local r = rows[index]
		r.dot.BackgroundColor3 = rgb(tag.color)
		r.name.TextColor3 = rgb(tag.color)
	end
end

local footer = PanelKit.label(content, "Footer", UDim2.new(1, -12, 0, 64), UDim2.new(0, 6, 1, -70), 12, MUTED, BODY_FONT)
footer.TextWrapped = true
footer.TextXAlignment = Enum.TextXAlignment.Left
footer.TextYAlignment = Enum.TextYAlignment.Top

local lastState: any = nil
local returnTo: (() -> ())? = nil

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

local function zoneName(index: number): string
	local zone = Config.Zones[index]
	return if zone then Localize.t(zone.key) else ""
end

local function luckInput(): Economy.LuckInput
	local state = lastState
	local now = os.time()
	return {
		knifeLevel = if state and state.upgrades then state.upgrades.knife or 0 else 0,
		zone = if state then state.zone else nil,
		-- Zdarzenie od serwera (uwzględnia Noc Dziadów przywołaną z panelu DEV)
		event = if Workspace:GetAttribute("CyclePhase") == "night" then Cycle.getEvent(Workspace:GetAttribute("CycleEvent")) else nil,
		boom = state ~= nil and (state.boomUntil or 0) > now,
		potion = state ~= nil and (state.luckUntil or 0) > now,
		member = Players.LocalPlayer:GetAttribute("OwlMember") == true,
		friend = Players.LocalPlayer:GetAttribute("FriendBonus") == true,
	}
end

-- Szczęście tu i teraz jako tekst („×2,4”) — do pigułki w sklepie i w tym oknie
function OddsPanel.luckText(): string
	local luck = Economy.luck(luckInput())
	return times(luck)
end

local function render()
	window.title.Text = Localize.t("ODDS_TITLE")
	local input = luckInput()
	local potionActive = input.potion == true
	local luck, luckParts, raw = Economy.luck(input)
	-- Kolumna „z miksturą”: jeśli mikstura już działa, to te same szanse co teraz
	local potionInput = table.clone(input)
	potionInput.potion = true
	local potionLuck = Economy.luck(potionInput)

	window.pillText.Text = times(luck)
	local names = {}
	for _, part in luckParts do
		local label = if part.key == "ODDS_DEPTH" and input.zone then zoneName(input.zone) else Localize.t(part.key)
		table.insert(names, label .. " " .. times(part.mult))
	end
	local partsText = string.format('<font color="%s">%s</font>', UiFx.hex(GREEN), Localize.t("ODDS_YOUR_LUCK", { times(luck) }))
	partsText ..= "\n" .. (if #names > 0 then table.concat(names, "  ·  ") else Localize.t("ODDS_NO_BONUS"))
	if raw - luck > 0.01 then
		-- Malejący zysk / limit: pokazujemy, ile byłoby bez balansu
		partsText ..= "  " .. Localize.t("ODDS_CAPPED", { times(raw) })
	end
	parts.Text = partsText

	headName.Text = Localize.t("ODDS_MUTATION")
	headBase.Text = Localize.t("ODDS_BASE")
	headNow.Text = Localize.t("ODDS_NOW")
	headPotion.Text = if potionActive then Localize.t("ODDS_POTION_ON") else Localize.t("ODDS_POTION")

	local baseOdds = Economy.variantOdds(1)
	local nowOdds = Economy.variantOdds(luck)
	local potionOdds = Economy.variantOdds(potionLuck)
	local index = 0
	for i = #baseOdds, 1, -1 do
		index += 1
		local row = rows[index]
		local def = Economy.getVariant(baseOdds[i].id)
		if def then
			row.name.Text = def.icon .. " " .. Localize.t(def.key)
			row.sub.Text = times(def.mult)
		end
		row.base.Text = percent(baseOdds[i].chance)
		row.now.Text = percent(nowOdds[i].chance)
		row.potion.Text = percent(potionOdds[i].chance)
	end
	for _, tag in Config.Tags do
		index += 1
		local row = rows[index]
		row.name.Text = tag.icon .. " " .. Localize.t(tag.key)
		row.sub.Text = times(tag.mult) .. " · " .. zoneName(tag.zone)
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
	if window.isOpen() then
		render()
	end
end

-- Otwiera okno; `back` wywoła się po zamknięciu przez gracza (X albo kliknięcie obok), np. powrót do sklepu
function OddsPanel.open(back: (() -> ())?)
	returnTo = back
	render()
	window.setOpen(true)
	for i, row in rows do
		local scale = row.frame:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		scale.Parent = row.frame
		UiFx.popIn(scale, 1, 0.7, 0.03 * i)
	end
end

function OddsPanel.toggle()
	if window.isOpen() then
		window.setOpen(false)
	else
		OddsPanel.open(nil)
	end
end

-- Powrót tylko po zamknięciu przez gracza; gdy okno zamyka inne okno (PanelKit), nie wracamy
local function closedByPlayer()
	local back = returnTo
	returnTo = nil
	if back then
		task.defer(back)
	end
end
window.close.Activated:Connect(closedByPlayer)
window.dim.Activated:Connect(closedByPlayer)
window.onToggle(function(open)
	if not open then
		task.defer(function()
			-- Zamknięte nie przez gracza (inne okno): zapominamy powrót
			if not window.isOpen() then
				returnTo = nil
			end
		end)
	end
end)

Localize.onChanged(function()
	if window.isOpen() then
		render()
	end
end)

-- Zdarzenie nocy i liczniki zmieniają się same, więc otwarte okno odświeża się co sekundę
task.spawn(function()
	while true do
		task.wait(1)
		if window.isOpen() then
			render()
		end
	end
end)

return OddsPanel
