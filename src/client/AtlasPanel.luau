--!strict
-- Grzybopedia w stylu okna ulepszeń (PanelKit): księga wszystkich grzybów w czterech formach
-- (zwykła, srebrna, złota, tęczowa). Odkryte formy to pikselowe grzybki z aurą (MushroomArt),
-- nieodkryte to czarne sylwetki, a nieznany gatunek ma nazwę „???”.
-- Strona = świat. Po prawej progi strony z nagrodą (stały bonus do ceny, tytuł nad głową).
-- Ostatnia zakładka to Strażnicy (BestiaryPage): opis każdego strażnika, odkrywany kradzieżą jego grzyba.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Progress = require(Shared.Progress)
local Remotes = require(Shared.Remotes)
local BestiaryPage = require(script.Parent.BestiaryPage)
local Localize = require(script.Parent.Localize)
local MushroomArt = require(script.Parent.MushroomArt)
local PanelKit = require(script.Parent.PanelKit)
local SideButtons = require(script.Parent.SideButtons)
local UiKit = require(script.Parent.UiKit)

local AtlasPanel = {}

local OUTLINE = PanelKit.OUTLINE
local WIDTH, HEIGHT = 720, 520
local ROW = 66
local TILE = 54
local SIDE_W = 214 -- kolumna progów po prawej
local GUARDIANS_TAB = "guardians"
-- Zakładki: strony świata, a na końcu Strażnicy
local TAB_IDS = table.clone(Progress.PAGES)
table.insert(TAB_IDS, GUARDIANS_TAB)

-- Kolor tła kafelka formy (ranga 0 = zwykła)
local FORM_TILE: { [number]: Color3 } = {
	[0] = Color3.fromRGB(72, 50, 34),
	[1] = Color3.fromRGB(84, 92, 108),
	[2] = Color3.fromRGB(118, 90, 30),
	[3] = Color3.fromRGB(104, 52, 112),
}
local VARIANT_BY_RANK: { [number]: Config.VariantDef } = {}
for _, variant in Config.Variants do
	VARIANT_BY_RANK[variant.rank] = variant
end
-- Kolory progów: odkrywca, tropiciel, znawca, mistrz
local TIER_COLORS = {
	Color3.fromRGB(84, 160, 72),
	Color3.fromRGB(120, 140, 170),
	Color3.fromRGB(220, 160, 40),
	Color3.fromRGB(196, 90, 200),
}

local window = PanelKit.window({
	name = "Atlas",
	parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	width = WIDTH,
	height = HEIGHT,
	ribbon = Color3.fromRGB(206, 120, 52),
	icon = "book",
	pillIcon = "coins",
	pillColor = Color3.fromRGB(52, 38, 30),
})
local content = window.content

local tabs, selectTab = PanelKit.tabs(content, TAB_IDS, 156)
local summary = PanelKit.label(content, "Summary", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(10, 42), 16, PanelKit.MUTED, PanelKit.BODY_FONT)

-- ===== Lista gatunków (lewa część) =====

local LIST_W = WIDTH - 28 - SIDE_W - 12
local FORM_X = LIST_W - 4 * (TILE + 6) - 20 -- od tego piksela zaczynają się kafelki form

local header = Instance.new("Frame")
header.Name = "Header"
header.BackgroundTransparency = 1
header.Size = UDim2.fromOffset(LIST_W, 18)
header.Position = UDim2.fromOffset(0, 66)
header.ZIndex = 4
header.Parent = content
local headerCells: { TextLabel } = {}
for rank = 0, 3 do
	local cell = PanelKit.label(header, "Form" .. rank, UDim2.fromOffset(TILE + 6, 18), UDim2.fromOffset(FORM_X + rank * (TILE + 6) - 3, 0), 13, PanelKit.MUTED, PanelKit.BODY_FONT)
	cell.ZIndex = 4
	headerCells[rank + 1] = cell
end

local list = Instance.new("ScrollingFrame")
list.Name = "List"
list.Size = UDim2.new(0, LIST_W, 1, -92)
list.Position = UDim2.fromOffset(0, 88)
list.BackgroundColor3 = PanelKit.BG_DARK
list.BackgroundTransparency = 0.25
list.BorderSizePixel = 0
list.ScrollBarThickness = 8
list.ScrollBarImageColor3 = PanelKit.LINE
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.ZIndex = 4
list.Parent = content
PanelKit.corner(list, UDim.new(0, 16))
PanelKit.stroke(list, OUTLINE, 3)
local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 6)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = list
local listPad = Instance.new("UIPadding")
listPad.PaddingTop = UDim.new(0, 8)
listPad.PaddingBottom = UDim.new(0, 8)
listPad.PaddingLeft = UDim.new(0, 8)
listPad.PaddingRight = UDim.new(0, 14)
listPad.Parent = list

-- ===== Progi strony (prawa kolumna) =====

local side = Instance.new("Frame")
side.Name = "Tiers"
side.BackgroundTransparency = 1
side.Size = UDim2.new(0, SIDE_W, 1, -70)
side.Position = UDim2.new(1, -SIDE_W, 0, 66)
side.ZIndex = 4
side.Parent = content
local sideLayout = Instance.new("UIListLayout")
sideLayout.Padding = UDim.new(0, 7)
sideLayout.SortOrder = Enum.SortOrder.LayoutOrder
sideLayout.Parent = side

type TierCard = { frame: Frame, stroke: UIStroke, label: TextLabel, fill: Frame, barText: TextLabel, reward: TextLabel, check: GuiObject }
local tierCards: { TierCard } = {}
for index = 1, #Progress.TIERS do
	local frame = Instance.new("Frame")
	frame.Name = "Tier" .. index
	frame.LayoutOrder = index
	frame.Size = UDim2.new(1, 0, 0, 98)
	frame.BackgroundColor3 = TIER_COLORS[index] or PanelKit.CARD
	frame.ZIndex = 5
	frame.Parent = side
	PanelKit.corner(frame, UDim.new(0, 14))
	local tierStroke = PanelKit.stroke(frame, OUTLINE, 3)
	local shade = Instance.new("UIGradient")
	shade.Rotation = 90
	shade.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(180, 180, 180))
	shade.Parent = frame
	local label = PanelKit.label(frame, "Label", UDim2.new(1, -16, 0, 34), UDim2.fromOffset(8, 5), 16)
	label.ZIndex = 6
	UiKit.outline(label, 2)
	local _, fill, barText = PanelKit.bar(frame, UDim2.new(1, -16, 0, 22), UDim2.fromOffset(8, 42), PanelKit.GOLD)
	local reward = PanelKit.label(frame, "Reward", UDim2.new(1, -16, 0, 22), UDim2.fromOffset(8, 70), 15, PanelKit.GOLD)
	reward.ZIndex = 6
	UiKit.outline(reward, 2)
	local check = UiKit.icon("check", frame, UDim2.fromOffset(32, 32), UDim2.new(1, 8, 0, -8), Vector2.new(1, 0))
	check.ZIndex = 8
	check.Visible = false
	tierCards[index] = { frame = frame, stroke = tierStroke, label = label, fill = fill, barText = barText, reward = reward, check = check }
end

-- Zakładka Strażnicy zajmuje miejsce listy i progów
local guardiansPage = BestiaryPage.new(content, UDim2.new(1, 0, 1, -70), UDim2.fromOffset(0, 66))

-- ===== Stan =====

local atlas: { [string]: any } = {}
local bestiary: { [string]: Progress.GuardianRecord } = {}
local current = "forest"
local hasNew = false -- nowe wpisy od ostatniego otwarcia (kropka na przycisku)
local newGuardian: string? = nil -- strażnik odkryty od ostatniego otwarcia: okno otworzy się na nim

local sideButton = SideButtons.add({
	name = "AtlasButton",
	icon = "book",
	color = Color3.fromRGB(206, 120, 52),
	caption = "ATLAS_BUTTON",
	key = Enum.KeyCode.B,
})

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

local function isActive(): boolean
	return window.isOpen()
end

-- Czarna sylwetka zamiast grzybka (forma jeszcze nieznaleziona): bez aury, przyciemniony obrazek
local function silhouette(art: Frame)
	for _, child in art:GetDescendants() do
		if child:IsA("ImageLabel") then
			if child.Name == "Cap" or child.Name == "Over" then
				child.ImageColor3 = Color3.new(0, 0, 0)
				child.ImageTransparency = 0.45
			else
				child.Visible = false
			end
		elseif child:IsA("UIGradient") then
			child.Enabled = false
		end
	end
end

-- Kafelek formy: pikselowy grzybek w kolorze formy albo czarna sylwetka
local function formTile(parent: Instance, species: Config.SpeciesDef, rank: number, found: boolean)
	local tile = Instance.new("Frame")
	tile.Name = "Form" .. rank
	tile.Size = UDim2.fromOffset(TILE, TILE)
	tile.AnchorPoint = Vector2.new(0, 0.5)
	tile.Position = UDim2.new(0, FORM_X + rank * (TILE + 6) - 8, 0.5, 0)
	tile.BackgroundColor3 = if found then FORM_TILE[rank] else Color3.fromRGB(40, 28, 20)
	tile.ZIndex = 6
	tile.Parent = parent
	PanelKit.corner(tile, UDim.new(0, 12))
	local tileStroke = PanelKit.stroke(tile, OUTLINE, 2.5)
	if found and rank > 0 then
		local variant = VARIANT_BY_RANK[rank]
		if variant then
			tileStroke.Color = rgb(variant.color)
		end
	end
	local box = Instance.new("Frame")
	box.Name = "Art"
	box.BackgroundTransparency = 1
	box.Size = UDim2.fromScale(0.86, 0.86)
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.ZIndex = 7
	box.Parent = tile
	local variant = VARIANT_BY_RANK[rank]
	local item: any = { s = species.id, v = if rank > 0 and variant then variant.id else nil }
	local art = MushroomArt.build(box, item, {
		active = if found then isActive else function()
			return false
		end,
		stroke = if found then tileStroke else nil,
	})
	if art then
		if not found then
			silhouette(art)
		end
		return
	end
	-- Bez arkusza grzybków: ikona z arkusza UI w kolorze formy
	local icon = UiKit.icon("mushroom", box, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	icon.ZIndex = 8
	local color = if rank == 0 then rgb(species.cap) elseif variant then rgb(variant.color) else Color3.new(1, 1, 1)
	if icon:IsA("ImageLabel") then
		icon.ImageColor3 = if found then color else Color3.new(0, 0, 0)
		icon.ImageTransparency = if found then 0 else 0.55
	elseif icon:IsA("TextLabel") then
		icon.Text = if found then "🍄" else "❔"
		icon.TextTransparency = if found then 0 else 0.5
	end
end

local function render()
	window.title.Text = Localize.t("ATLAS_TITLE")
	for page, tab in tabs do
		local found, total
		if page == GUARDIANS_TAB then
			found, total = Progress.guardiansFound(bestiary)
		else
			found, total = Progress.entries(atlas, page)
		end
		tab.Text = string.format("%s %d/%d", Localize.t("ATLAS_PAGE_" .. string.upper(page)), found, total)
	end
	selectTab(current)
	window.pillText.Text = "+" .. percent(Progress.atlasBonus(atlas)) .. "%"

	local onGuardians = current == GUARDIANS_TAB
	header.Visible = not onGuardians
	list.Visible = not onGuardians
	side.Visible = not onGuardians
	guardiansPage.setActive(onGuardians and window.isOpen())
	if onGuardians then
		local found, total = Progress.guardiansFound(bestiary)
		summary.Text = Localize.t("BESTIARY_SUMMARY", { found, total })
		guardiansPage.render(bestiary)
		return
	end
	headerCells[1].Text = Localize.t("ATLAS_FORM_NORMAL")
	for rank = 1, 3 do
		local variant = VARIANT_BY_RANK[rank]
		headerCells[rank + 1].Text = if variant then Localize.t(variant.key) else ""
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
		local class = Economy.speciesClass(species.id)
		local known = mask > 0
		local row = Instance.new("Frame")
		row.Name = species.id
		row.LayoutOrder = order
		row.Size = UDim2.new(1, 0, 0, ROW)
		row.BackgroundColor3 = if known then PanelKit.CARD else Color3.fromRGB(70, 48, 33)
		row.ZIndex = 5
		row.Parent = list
		PanelKit.corner(row, UDim.new(0, 14))
		PanelKit.stroke(row, OUTLINE, 2.5)
		-- Pasek w kolorze klasy po lewej
		local stripe = Instance.new("Frame")
		stripe.Name = "Stripe"
		stripe.Size = UDim2.new(0, 8, 1, -16)
		stripe.Position = UDim2.fromOffset(8, 8)
		stripe.BackgroundColor3 = if known then rgb(class.color) else Color3.fromRGB(96, 74, 56)
		stripe.ZIndex = 6
		stripe.Parent = row
		PanelKit.corner(stripe, UDim.new(1, 0))

		local nameWidth = FORM_X - 34
		local name = PanelKit.label(row, "Name", UDim2.fromOffset(nameWidth, 24), UDim2.fromOffset(24, 9), 20)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.ZIndex = 6
		UiKit.outline(name, 2)
		local info = PanelKit.label(row, "Info", UDim2.fromOffset(nameWidth, 18), UDim2.fromOffset(24, 37), 14, PanelKit.MUTED, PanelKit.BODY_FONT)
		info.TextXAlignment = Enum.TextXAlignment.Left
		info.ZIndex = 6
		local zone = Config.Zones[species.zone]
		if known then
			name.Text = Localize.t(species.key)
			name.TextColor3 = rgb(class.color):Lerp(Color3.new(1, 1, 1), 0.25)
			info.Text = string.format("%s · %s · 💰 %s", Localize.t(class.key), if zone then Localize.t(zone.key) else "", formatCoins(species.value))
		else
			name.Text = "???"
			name.TextColor3 = PanelKit.MUTED
			info.Text = if zone then Localize.t(zone.key) else ""
		end
		for rank = 0, 3 do
			formTile(row, species, rank, Progress.has(atlas, species.id, rank))
		end
	end

	-- Progi strony
	for index, tier in Progress.TIERS do
		local card = tierCards[index]
		local count, total = Progress.tierProgress(atlas, current, tier.rank)
		local done = total > 0 and count >= total
		card.label.Text = Localize.t(tier.key)
		card.fill.Size = UDim2.fromScale(if total > 0 then math.clamp(count / total, 0, 1) else 0, 1)
		card.fill.BackgroundColor3 = if done then PanelKit.GREEN else PanelKit.GOLD
		card.barText.Text = string.format("%d/%d", count, total)
		local reward = "+" .. percent(tier.bonus) .. "% " .. Localize.t("ATLAS_PRICE")
		if tier.title then
			reward ..= " · " .. Localize.t(tier.title .. string.upper(current))
		end
		card.reward.Text = reward
		card.reward.TextColor3 = if done then PanelKit.GREEN else PanelKit.GOLD
		card.check.Visible = done
		card.stroke.Color = if done then PanelKit.GREEN else OUTLINE
	end
end

local function refreshBadge()
	local found, total = 0, 0
	for _, page in Progress.PAGES do
		local f, t = Progress.entries(atlas, page)
		found += f
		total += t
	end
	if hasNew then
		sideButton.setBadge(Localize.t("BADGE_NEW"), "alert")
	else
		sideButton.setBadge(string.format("%d%%", if total > 0 then math.floor(found / total * 100) else 0), "info")
	end
end

function AtlasPanel.toggle()
	if window.isOpen() then
		window.setOpen(false)
		return
	end
	-- Nowy strażnik od ostatniego otwarcia: od razu jego karta
	if newGuardian then
		current = GUARDIANS_TAB
		guardiansPage.select(newGuardian)
		newGuardian = nil
	end
	hasNew = false
	refreshBadge()
	window.setOpen(true)
end

window.onToggle(function(open: boolean)
	if open then
		render()
	else
		guardiansPage.setActive(false)
	end
end)

for page, tab in tabs do
	tab.Activated:Connect(function()
		if current ~= page then
			current = page
			list.CanvasPosition = Vector2.zero
			render()
		end
	end)
end
sideButton.onActivated(AtlasPanel.toggle)

local knownEntries = -1
local knownGuardians: { [string]: boolean }? = nil
Remotes.get("ProgressUpdate").OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" or typeof(payload.atlas) ~= "table" then
		return
	end
	atlas = payload.atlas
	bestiary = if typeof(payload.bestiary) == "table" then payload.bestiary else {}
	-- Strażnicy odkryci od poprzedniej paczki (pierwsza paczka po wejściu to tylko stan)
	local foundNow: { [string]: boolean } = {}
	for _, def in Progress.GUARDIANS do
		if Progress.guardianRecord(bestiary, def.id).found then
			foundNow[def.id] = true
			if knownGuardians and not knownGuardians[def.id] and not window.isOpen() then
				hasNew = true
				newGuardian = def.id
			end
		end
	end
	knownGuardians = foundNow
	local count = 0
	for _, page in Progress.PAGES do
		count += (Progress.entries(atlas, page))
	end
	if knownEntries >= 0 and count > knownEntries and not window.isOpen() then
		hasNew = true
	end
	knownEntries = count
	refreshBadge()
	if window.isOpen() then
		render()
	end
end)

Localize.onChanged(function()
	refreshBadge()
	if window.isOpen() then
		render()
	end
end)
refreshBadge()

return AtlasPanel
