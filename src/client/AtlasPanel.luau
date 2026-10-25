--!strict
-- Grzybopedia: księga wszystkich grzybów w czterech formach (zwykła, srebrna, złota, tęczowa).
-- Odkryte formy są w kolorze, nieodkryte to czarne sylwetki, a nieznany gatunek ma nazwę „???”.
-- Strona = świat. Na dole progi strony z nagrodą (stały bonus do ceny, tytuł nad głową).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Progress = require(Shared.Progress)
local Remotes = require(Shared.Remotes)
local Localize = require(script.Parent.Localize)
local SideButtons = require(script.Parent.SideButtons)
local UiKit = require(script.Parent.UiKit)
local UiScale = require(script.Parent.UiScale)

local AtlasPanel = {}

local TITLE_FONT = Enum.Font.FredokaOne
local BODY_FONT = Enum.Font.GothamBold
local TEXT = Color3.fromRGB(252, 238, 210)
local MUTED = Color3.fromRGB(214, 188, 150)
local ACCENT = Color3.fromRGB(255, 214, 120)
local PANEL = Color3.fromRGB(40, 28, 20)
local CARD = Color3.fromRGB(58, 42, 30)
local WIDTH, HEIGHT = 540, 470
local ROW = 44

-- Kolory form w kolejności rang (0 zwykła → kolor kapelusza gatunku)
local FORM_COLORS: { [number]: Color3 } = {
	[1] = Color3.fromRGB(214, 224, 238),
	[2] = Color3.fromRGB(255, 205, 50),
	[3] = Color3.fromRGB(255, 110, 210),
}
local VARIANT_BY_RANK: { [number]: Config.VariantDef } = {}
for _, variant in Config.Variants do
	VARIANT_BY_RANK[variant.rank] = variant
end

local gui = Instance.new("ScreenGui")
gui.Name = "Atlas"
gui.ResetOnSpawn = false
gui.DisplayOrder = 6
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function text(parent: Instance, name: string, size: UDim2, position: UDim2, font: Enum.Font, maxSize: number, color: Color3?): TextLabel
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
	l.Parent = parent
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = maxSize
	c.Parent = l
	return l
end

local panel = Instance.new("Frame")
panel.Name = "AtlasPanel"
panel.Size = UDim2.fromOffset(WIDTH, HEIGHT)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.BackgroundColor3 = PANEL
panel.Visible = false
panel.Parent = gui
corner(panel, 14)
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(200, 146, 74)
panelStroke.Thickness = 2
panelStroke.Parent = panel
local panelScale = Instance.new("UIScale")
panelScale.Parent = panel

UiKit.icon("book", panel, UDim2.fromOffset(34, 34), UDim2.fromOffset(12, 8))
local title = text(panel, "Title", UDim2.new(1, -110, 0, 30), UDim2.fromOffset(52, 10), TITLE_FONT, 26, ACCENT)
local close = Instance.new("TextButton")
close.Name = "Close"
close.Size = UDim2.fromOffset(32, 32)
close.Position = UDim2.new(1, -42, 0, 10)
close.Text = ""
close.Parent = panel
UiKit.button(close, UiKit.COLORS.wood, { gloss = true, radius = UDim.new(0, 8) })
UiKit.icon("close", close, UDim2.fromOffset(22, 22), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))

-- Zakładki stron
local tabsFrame = Instance.new("Frame")
tabsFrame.Name = "Tabs"
tabsFrame.BackgroundTransparency = 1
tabsFrame.Size = UDim2.new(1, -24, 0, 30)
tabsFrame.Position = UDim2.fromOffset(12, 48)
tabsFrame.Parent = panel
local tabsGrid = Instance.new("UIGridLayout")
tabsGrid.CellSize = UDim2.new(1 / #Progress.PAGES, -6, 1, 0)
tabsGrid.CellPadding = UDim2.fromOffset(8, 0)
tabsGrid.SortOrder = Enum.SortOrder.LayoutOrder
tabsGrid.Parent = tabsFrame
local tabs: { [string]: TextButton } = {}
for index, page in Progress.PAGES do
	local tab = Instance.new("TextButton")
	tab.Name = "Tab_" .. page
	tab.LayoutOrder = index
	tab.Font = TITLE_FONT
	tab.TextScaled = true
	tab.Parent = tabsFrame
	UiKit.button(tab, UiKit.COLORS.wood, { radius = UDim.new(0, 8) })
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 5)
	pad.PaddingBottom = UDim.new(0, 5)
	pad.Parent = tab
	tabs[page] = tab
end

local summary = text(panel, "Summary", UDim2.new(1, -24, 0, 20), UDim2.fromOffset(12, 84), BODY_FONT, 14, MUTED)

-- Nagłówek kolumn form
local FORM_X = 0.5 -- od tej części szerokości zaczynają się kolumny form
local header = Instance.new("Frame")
header.BackgroundTransparency = 1
header.Size = UDim2.new(1, -24, 0, 18)
header.Position = UDim2.fromOffset(12, 108)
header.Parent = panel
local headerCells: { TextLabel } = {}
for rank = 0, 3 do
	local cell = text(header, "Form" .. rank, UDim2.new((1 - FORM_X) / 4, 0, 1, 0), UDim2.new(FORM_X + rank * (1 - FORM_X) / 4, 0, 0, 0), BODY_FONT, 12, MUTED)
	cell.TextXAlignment = Enum.TextXAlignment.Center
	headerCells[rank + 1] = cell
end

local list = Instance.new("ScrollingFrame")
list.Name = "List"
list.Size = UDim2.new(1, -24, 0, HEIGHT - 128 - 150)
list.Position = UDim2.fromOffset(12, 128)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 6
list.ScrollBarImageColor3 = Color3.fromRGB(200, 146, 74)
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.Parent = panel
local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 4)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = list

-- Progi strony na dole
local tiersFrame = Instance.new("Frame")
tiersFrame.Name = "Tiers"
tiersFrame.BackgroundTransparency = 1
tiersFrame.Size = UDim2.new(1, -24, 0, 140)
tiersFrame.Position = UDim2.new(0, 12, 1, -146)
tiersFrame.Parent = panel
type TierRow = { label: TextLabel, reward: TextLabel, fill: Frame, check: TextLabel }
local tierRows: { TierRow } = {}
for index = 1, #Progress.TIERS do
	local y = (index - 1) * 34
	local check = text(tiersFrame, "Check", UDim2.fromOffset(22, 22), UDim2.fromOffset(0, y), TITLE_FONT, 20, ACCENT)
	check.TextXAlignment = Enum.TextXAlignment.Center
	local label = text(tiersFrame, "Label", UDim2.new(0.62, -28, 0, 18), UDim2.fromOffset(28, y), BODY_FONT, 14)
	local reward = text(tiersFrame, "Reward", UDim2.new(0.38, 0, 0, 18), UDim2.new(0.62, 0, 0, y), TITLE_FONT, 15, ACCENT)
	reward.TextXAlignment = Enum.TextXAlignment.Right
	local back = Instance.new("Frame")
	back.Size = UDim2.new(1, -28, 0, 6)
	back.Position = UDim2.fromOffset(28, y + 21)
	back.BackgroundColor3 = Color3.fromRGB(20, 14, 10)
	back.BorderSizePixel = 0
	back.Parent = tiersFrame
	corner(back, 3)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = ACCENT
	fill.BorderSizePixel = 0
	fill.Parent = back
	corner(fill, 3)
	tierRows[index] = { label = label, reward = reward, fill = fill, check = check }
end

-- ===== Stan =====

local atlas: { [string]: any } = {}
local current = "forest"
local hasNew = false -- nowe wpisy od ostatniego otwarcia (kropka na przycisku)

local button, badge = SideButtons.add("AtlasButton", "book", Color3.fromRGB(150, 90, 50))

local function percent(fraction: number): string
	return tostring(math.floor(fraction * 100 + 0.5))
end

local function formatCoins(value: number): string
	local s = tostring(math.floor(value + 0.5))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (formatted:gsub("^ ", ""))
end

local function rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

-- Komórka formy: ikona grzyba w kolorze formy albo czarna sylwetka
local function formCell(parent: Instance, species: Config.SpeciesDef, rank: number, found: boolean)
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new((1 - FORM_X) / 4, 0, 1, 0)
	holder.Position = UDim2.new(FORM_X + rank * (1 - FORM_X) / 4, 0, 0, 0)
	holder.Parent = parent
	local icon = UiKit.icon("mushroom", holder, UDim2.fromOffset(34, 34), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	local color = if rank == 0 then rgb(species.cap) else FORM_COLORS[rank]
	if icon:IsA("ImageLabel") then
		icon.ImageColor3 = if found then color else Color3.new(0, 0, 0)
		icon.ImageTransparency = if found then 0 else 0.55
		if found and rank == 3 then
			local rainbow = Instance.new("UIGradient")
			rainbow.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
				ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 230, 90)),
				ColorSequenceKeypoint.new(0.66, Color3.fromRGB(90, 220, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 110, 255)),
			})
			rainbow.Parent = icon
			icon.ImageColor3 = Color3.new(1, 1, 1)
		end
	elseif icon:IsA("TextLabel") then
		icon.Text = if found then "🍄" else "❔"
		icon.TextTransparency = if found then 0 else 0.5
	end
	if found and rank > 0 then
		local variant = VARIANT_BY_RANK[rank]
		if variant then
			-- Mała ikonka wariantu w rogu (⭐, 🌈…)
			local mark = text(holder, "Mark", UDim2.fromOffset(16, 16), UDim2.new(0.5, 8, 0.5, -18), BODY_FONT, 14)
			mark.Text = variant.icon
			mark.ZIndex = 5
		end
	end
end

local function render()
	title.Text = Localize.t("ATLAS_TITLE")
	for page, tab in tabs do
		local found, total = Progress.entries(atlas, page)
		tab.Text = string.format("%s  %d/%d", Localize.t("ATLAS_PAGE_" .. string.upper(page)), found, total)
		UiKit.recolor(tab, if page == current then Color3.fromRGB(196, 130, 50) else UiKit.COLORS.wood)
	end
	headerCells[1].Text = Localize.t("ATLAS_FORM_NORMAL")
	for rank = 1, 3 do
		local variant = VARIANT_BY_RANK[rank]
		headerCells[rank + 1].Text = if variant then variant.icon .. " " .. Localize.t(variant.key) else ""
	end

	local bonus = Progress.atlasBonus(atlas)
	local titleKey = Progress.title(atlas)
	summary.Text = Localize.t("ATLAS_SUMMARY", {
		percent(bonus),
		if titleKey then Localize.t(titleKey) else Localize.t("ATLAS_NO_TITLE"),
	})

	-- Wiersze gatunków
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for order, species in Progress.pageSpecies(current) do
		local mask = Progress.mask(atlas, species.id)
		local row = Instance.new("Frame")
		row.Name = species.id
		row.LayoutOrder = order
		row.Size = UDim2.new(1, -8, 0, ROW)
		row.BackgroundColor3 = CARD
		row.BorderSizePixel = 0
		row.Parent = list
		corner(row, 8)
		local class = Economy.speciesClass(species.id)
		local known = mask > 0
		local name = text(row, "Name", UDim2.new(FORM_X, -12, 0, 20), UDim2.fromOffset(10, 4), TITLE_FONT, 17)
		local info = text(row, "Info", UDim2.new(FORM_X, -12, 0, 14), UDim2.fromOffset(10, 25), BODY_FONT, 12, MUTED)
		if known then
			name.Text = Localize.t(species.key)
			name.TextColor3 = rgb(class.color)
			local zone = Config.Zones[species.zone]
			info.Text = string.format("%s · %s · 💰 %s", Localize.t(class.key), if zone then Localize.t(zone.key) else "", formatCoins(species.value))
		else
			name.Text = "???"
			name.TextColor3 = MUTED
			local zone = Config.Zones[species.zone]
			info.Text = if zone then Localize.t(zone.key) else ""
		end
		for rank = 0, 3 do
			formCell(row, species, rank, Progress.has(atlas, species.id, rank))
		end
	end

	-- Progi strony
	for index, tier in Progress.TIERS do
		local row = tierRows[index]
		local count, total = Progress.tierProgress(atlas, current, tier.rank)
		local done = total > 0 and count >= total
		row.check.Text = if done then "✔" else "○"
		row.check.TextColor3 = if done then Color3.fromRGB(150, 255, 150) else MUTED
		row.label.Text = string.format("%s  <font color=\"#D6BC96\">%d/%d</font>", Localize.t(tier.key), count, total)
		local reward = "+" .. percent(tier.bonus) .. "% " .. Localize.t("ATLAS_PRICE")
		if tier.title then
			reward ..= " · " .. Localize.t(tier.title .. string.upper(current))
		end
		row.reward.Text = reward
		row.reward.TextColor3 = if done then Color3.fromRGB(150, 255, 150) else ACCENT
		row.fill.Size = UDim2.new(if total > 0 then count / total else 0, 0, 1, 0)
		row.fill.BackgroundColor3 = if done then Color3.fromRGB(150, 255, 150) else ACCENT
	end
end

local function refreshBadge()
	local found, total = 0, 0
	for _, page in Progress.PAGES do
		local f, t = Progress.entries(atlas, page)
		found += f
		total += t
	end
	badge.Text = if hasNew then "NEW" else string.format("%d%%", if total > 0 then math.floor(found / total * 100) else 0)
	badge.TextColor3 = if hasNew then Color3.fromRGB(255, 236, 120) else Color3.fromRGB(255, 252, 240)
end

function AtlasPanel.toggle()
	panel.Visible = not panel.Visible
	if panel.Visible then
		hasNew = false
		refreshBadge()
		render()
	end
end

for page, tab in tabs do
	tab.Activated:Connect(function()
		current = page
		render()
	end)
end
button.Activated:Connect(AtlasPanel.toggle)
close.Activated:Connect(function()
	panel.Visible = false
end)

local knownEntries = -1
Remotes.get("ProgressUpdate").OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" or typeof(payload.atlas) ~= "table" then
		return
	end
	atlas = payload.atlas
	local count = 0
	for _, page in Progress.PAGES do
		count += (Progress.entries(atlas, page))
	end
	if knownEntries >= 0 and count > knownEntries and not panel.Visible then
		hasNew = true
	end
	knownEntries = count
	refreshBadge()
	if panel.Visible then
		render()
	end
end)

Localize.onChanged(function()
	refreshBadge()
	if panel.Visible then
		render()
	end
end)
UiScale.onChanged(function()
	panelScale.Scale = UiScale.get()
end)
refreshBadge()

return AtlasPanel
