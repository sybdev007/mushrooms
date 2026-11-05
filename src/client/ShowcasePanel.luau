--!strict
-- Okno gabloty w ogródku (przycisk przy regale, tylko właściciel). Po lewej regał: trzy półki (las,
-- jaskinia, bagna) po 6 miejsc; kupione miejsce pokazuje wystawiony grzyb albo „+”, następne do kupienia
-- cenę, dalsze kłódkę. Po prawej wszystko, co można wystawić: trofea ze Znaleziska Nocy i formy gatunków
-- z Grzybopedii (od najrzadszej). Klik w miejsce na półce, potem w grzyb z listy = wystaw.
-- Kupno miejsca: przycisk na dole, drugie kliknięcie potwierdza. Wszystko sprawdza serwer (ShowcaseService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Remotes = require(Shared.Remotes)
local Showcase = require(Shared.Showcase)
local Audio = require(script.Parent.Audio)
local ClassColor = require(script.Parent.ClassColor)
local Localize = require(script.Parent.Localize)
local MushroomArt = require(script.Parent.MushroomArt)
local PanelKit = require(script.Parent.PanelKit)
local UiKit = require(script.Parent.UiKit)

type Exhibit = Showcase.Exhibit
type SlotState = { state: string, price: number, item: Exhibit? }

local ShowcasePanel = {}

-- Cztery półki (las, jaskinia, bagna, Łysa Góra): okno wyższe, kafelki niższe. Na telefonie całe okno
-- zmniejsza PanelKit.fit, więc liczy się tylko, żeby wszystko zmieściło się w tych liczbach.
local WIDTH, HEIGHT = 860, 560
local TILE_W, TILE_H, GAP = 82, 84, 6
local ROW_STEP = 108
local RIGHT_X = 6 * TILE_W + 5 * GAP + 16
local OUTLINE = PanelKit.OUTLINE
local GREEN = Color3.fromRGB(86, 186, 84)
local GREY = Color3.fromRGB(120, 108, 98)
local LOCKED = Color3.fromRGB(70, 52, 40)
local GOLD = PanelKit.GOLD
local TROPHY = Color3.fromRGB(255, 214, 90)
local CONFIRM_SECONDS = 3

local slots: { SlotState } = {}
local options: { Exhibit } = {}
local nextSlot: number? = nil
local nextPrice: number? = nil
local reason: string? = nil
local coins = 0
local selected: number? = nil
local armedAt = 0 -- kiedy pierwszy raz kliknięto „Kup” (drugie kliknięcie w CONFIRM_SECONDS kupuje)
local status = ""

local function t(key: string, args: { any }?): string
	return Localize.t(key, args)
end

local function formatCoins(value: number): string
	local s = tostring(math.floor(value + 0.5))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (formatted:gsub("^ ", ""))
end

-- Krótko na kafelku: 16k, 1,6M, 51,2M
local function short(value: number): string
	local function one(x: number, suffix: string): string
		local text = if x < 10 or x ~= math.floor(x) then string.format("%.1f", x) else tostring(math.floor(x))
		text = text:gsub("%.0$", "")
		if Localize.getLocale() == "pl" then
			text = text:gsub("%.", ",")
		end
		return text .. suffix
	end
	if value >= 1e6 then
		return one(value / 1e6, "M")
	elseif value >= 1e3 then
		return one(value / 1e3, "k")
	end
	return tostring(math.floor(value))
end

local function speciesName(id: string): string
	local species = Economy.getSpecies(id)
	return if species then t(species.key) else id
end

local function variantIcon(item: Exhibit): string
	local variant = Economy.getVariant(item.v)
	return if variant then variant.icon else ""
end

local function signature(item: Exhibit?): string
	return if item then string.format("%s|%s|%s", item.s, item.v or "", tostring(item.t or "")) else ""
end

-- ===== Okno =====

local window = PanelKit.window({
	name = "Showcase",
	parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	width = WIDTH,
	height = HEIGHT,
	ribbon = Color3.fromRGB(150, 104, 60),
	icon = "chest",
	pillIcon = "coins",
	pillColor = Color3.fromRGB(52, 38, 30),
})
local content = window.content

local function isOpen(): boolean
	return window.isOpen()
end

local function drawArt(box: Frame, item: Exhibit?)
	local key = signature(item)
	if box:GetAttribute("ArtKey") == key then
		return
	end
	box:SetAttribute("ArtKey", key)
	box:ClearAllChildren()
	if not item then
		return
	end
	local art = MushroomArt.build(box, { s = item.s, v = item.v } :: any, { active = isOpen })
	if not art then
		local icon = PanelKit.label(box, "Icon", UDim2.fromScale(1, 1), UDim2.new(), 48)
		icon.Text = "🍄"
		icon.ZIndex = box.ZIndex + 1
	end
end

local function artBox(parent: Instance, size: number, y: number): Frame
	local box = Instance.new("Frame")
	box.Name = "Art"
	box.BackgroundTransparency = 1
	box.Size = UDim2.fromOffset(size, size)
	box.Position = UDim2.new(0.5, 0, 0, y)
	box.AnchorPoint = Vector2.new(0.5, 0)
	box.ZIndex = 6
	box.Parent = parent
	return box
end

-- ----- Regał -----

type SlotView = { card: TextButton, stroke: UIStroke, art: Frame, top: TextLabel, bottom: TextLabel }
local slotViews: { SlotView } = {}
local rowHeaders: { TextLabel } = {}

local render: () -> ()
local selectSlot: (number) -> ()

for series = 1, #Config.Showcase.series do
	local y = 30 + (series - 1) * ROW_STEP
	local header = PanelKit.label(content, "Row" .. series, UDim2.fromOffset(6 * TILE_W + 5 * GAP, 20), UDim2.fromOffset(0, y), 17, PanelKit.MUTED)
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.ZIndex = 5
	table.insert(rowHeaders, header)
	for k = 1, Config.Showcase.perSeries do
		local slot = (series - 1) * Config.Showcase.perSeries + k
		local card = Instance.new("TextButton")
		card.Name = "Slot" .. slot
		card.Text = ""
		card.AutoButtonColor = false
		card.Size = UDim2.fromOffset(TILE_W, TILE_H)
		card.Position = UDim2.fromOffset((k - 1) * (TILE_W + GAP), y + 22)
		card.BackgroundColor3 = PanelKit.CARD
		card.ZIndex = 4
		card.Parent = content
		PanelKit.corner(card, UDim.new(0, 12))
		local stroke = PanelKit.stroke(card, OUTLINE, 2)
		local art = artBox(card, 50, 4)
		local top = PanelKit.label(card, "Top", UDim2.new(1, -8, 0, 40), UDim2.fromOffset(4, 10), 30, PanelKit.MUTED)
		top.ZIndex = 7
		local bottom = PanelKit.label(card, "Bottom", UDim2.new(1, -6, 0, 26), UDim2.new(0, 3, 1, -29), 13, PanelKit.TEXT, PanelKit.BODY_FONT)
		bottom.TextWrapped = true
		bottom.ZIndex = 7
		card.Activated:Connect(function()
			selectSlot(slot)
		end)
		table.insert(slotViews, { card = card, stroke = stroke, art = art, top = top, bottom = bottom })
	end
end

-- ----- Kupno -----

local buyY = 30 + #Config.Showcase.series * ROW_STEP + 6
local buy = Instance.new("TextButton")
buy.Name = "Buy"
buy.Size = UDim2.fromOffset(270, 42)
buy.Position = UDim2.fromOffset(0, buyY)
buy.Font = PanelKit.TITLE_FONT
buy.TextScaled = true
buy.TextColor3 = Color3.new(1, 1, 1)
buy.ZIndex = 5
buy.Parent = content
UiKit.button(buy, GREEN, { stroke = 3, radius = UDim.new(0, 16), gloss = true })
UiKit.outline(buy, 2.5)
local buyPad = Instance.new("UIPadding")
buyPad.PaddingLeft = UDim.new(0, 12)
buyPad.PaddingRight = UDim.new(0, 12)
buyPad.Parent = buy
local buySize = Instance.new("UITextSizeConstraint")
buySize.MaxTextSize = 22
buySize.Parent = buy
local statusLabel = PanelKit.label(content, "Status", UDim2.fromOffset(6 * TILE_W + 5 * GAP - 284, 42), UDim2.fromOffset(284, buyY), 14, PanelKit.MUTED, PanelKit.BODY_FONT)
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextWrapped = true
statusLabel.ZIndex = 5

-- ----- Lista do wystawienia -----

local pickHeader = PanelKit.label(content, "PickHeader", UDim2.fromOffset(196, 22), UDim2.fromOffset(RIGHT_X, 30), 15, PanelKit.TEXT, PanelKit.BODY_FONT)
pickHeader.TextXAlignment = Enum.TextXAlignment.Left
pickHeader.TextWrapped = true
pickHeader.ZIndex = 5
local remove = Instance.new("TextButton")
remove.Name = "Remove"
remove.Size = UDim2.fromOffset(92, 28)
remove.Position = UDim2.new(1, -92, 0, 28)
remove.Font = PanelKit.TITLE_FONT
remove.TextScaled = true
remove.TextColor3 = Color3.new(1, 1, 1)
remove.ZIndex = 5
remove.Parent = content
UiKit.button(remove, Color3.fromRGB(196, 84, 70), { stroke = 2, radius = UDim.new(0, 10) })
UiKit.outline(remove, 1.5)
local removeSize = Instance.new("UITextSizeConstraint")
removeSize.MaxTextSize = 16
removeSize.Parent = remove

local list = Instance.new("ScrollingFrame")
list.Name = "Options"
list.Size = UDim2.new(1, -RIGHT_X, 1, -64)
list.Position = UDim2.fromOffset(RIGHT_X, 62)
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
local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.fromOffset(64, 84)
grid.CellPadding = UDim2.fromOffset(5, 6)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = list
local listPad = Instance.new("UIPadding")
listPad.PaddingTop = UDim.new(0, 8)
listPad.PaddingBottom = UDim.new(0, 8)
listPad.PaddingLeft = UDim.new(0, 8)
listPad.PaddingRight = UDim.new(0, 12)
listPad.Parent = list
-- Pusta lista: napis nad nią (poza siatką, żeby nie był komórką UIGridLayout)
local listEmpty = PanelKit.label(content, "Empty", UDim2.new(1, -RIGHT_X - 24, 0, 110), UDim2.fromOffset(RIGHT_X + 12, 90), 15, PanelKit.MUTED, PanelKit.BODY_FONT)
listEmpty.TextWrapped = true
listEmpty.ZIndex = 6
listEmpty.Visible = false

local optionButtons: { TextButton } = {}
local optionsKey: string? = nil

local function send(payload: { [string]: any })
	Remotes.get("ShowcaseAction"):FireServer(payload)
end

local function place(item: Exhibit)
	local slot = selected
	if not slot or not slots[slot] or slots[slot].state ~= "owned" then
		Audio.play("warn")
		status = t("SHOWCASE_PICK_SLOT")
		render()
		return
	end
	Audio.play("pick", { jitter = 0.08 })
	send({ op = "set", slot = slot, item = { s = item.s, v = item.v, t = item.t } })
	-- Od razu następne wolne miejsce (wystawianie kilku grzybów po kolei)
	for other = slot + 1, #slots do
		if slots[other].state == "owned" and not slots[other].item then
			selected = other
			break
		end
	end
end

local function rebuildOptions()
	for _, button in optionButtons do
		button:Destroy()
	end
	optionButtons = {}
	local key = {}
	for _, item in options do
		table.insert(key, signature(item))
	end
	optionsKey = table.concat(key, ";") .. Localize.getLocale()
	for index, item in options do
		local button = Instance.new("TextButton")
		button.Name = "Option" .. index
		button.LayoutOrder = index
		button.Text = ""
		button.AutoButtonColor = false
		button.BackgroundColor3 = PanelKit.CARD
		button.ZIndex = 5
		button.Parent = list
		PanelKit.corner(button, UDim.new(0, 12))
		PanelKit.stroke(button, if item.t then TROPHY else OUTLINE, if item.t then 2.5 else 2)
		local box = artBox(button, 48, 3)
		drawArt(box, item)
		local marks = PanelKit.label(button, "Marks", UDim2.new(1, -4, 0, 14), UDim2.fromOffset(2, 51), 12, PanelKit.TEXT, PanelKit.BODY_FONT)
		marks.Text = (if item.t then "✨" else "") .. variantIcon(item)
		marks.ZIndex = 7
		local nameLabel = PanelKit.label(button, "Name", UDim2.new(1, -4, 0, 16), UDim2.fromOffset(2, 65), 11, PanelKit.TEXT, PanelKit.BODY_FONT)
		nameLabel.Text = speciesName(item.s)
		ClassColor.paint(nameLabel, item.s)
		nameLabel.ZIndex = 7
		button.Activated:Connect(function()
			place(item)
		end)
		table.insert(optionButtons, button)
	end
end

-- ===== Rysowanie =====

render = function()
	if not isOpen() then
		return
	end
	window.title.Text = t("SHOWCASE_TITLE")
	window.pillText.Text = formatCoins(coins)

	for series, header in rowHeaders do
		local def = Config.Showcase.series[series]
		local owned = 0
		for k = 1, Config.Showcase.perSeries do
			local state = slots[(series - 1) * Config.Showcase.perSeries + k]
			if state and state.state == "owned" then
				owned += 1
			end
		end
		header.Text = def.icon .. " " .. t(def.key) .. "  ·  " .. owned .. "/" .. Config.Showcase.perSeries
	end

	for slot, view in slotViews do
		local state = slots[slot]
		local item = if state then state.item else nil
		local isSelected = selected == slot
		view.stroke.Color = if isSelected then GREEN elseif state and state.state == "next" then GOLD else OUTLINE
		view.stroke.Thickness = if isSelected then 3.5 elseif state and state.state == "next" then 2.5 else 2
		if not state then
			view.card.BackgroundColor3 = LOCKED
			view.top.Text = ""
			view.bottom.Text = ""
			drawArt(view.art, nil)
		elseif state.state == "owned" then
			view.card.BackgroundColor3 = PanelKit.CARD
			drawArt(view.art, item)
			if item then
				view.top.Text = ""
				view.bottom.Text = (if item.t then "✨ " else "") .. speciesName(item.s)
				ClassColor.paint(view.bottom, item.s)
			else
				view.top.Text = "+"
				view.top.TextColor3 = PanelKit.MUTED
				view.bottom.Text = t("SHOWCASE_EMPTY_SLOT")
				view.bottom.TextColor3 = PanelKit.MUTED
			end
		else
			view.card.BackgroundColor3 = LOCKED
			drawArt(view.art, nil)
			view.top.Text = "🔒"
			view.top.TextColor3 = PanelKit.MUTED
			if state.state == "world" then
				view.bottom.Text = t("SHOWCASE_LOCKED_WORLD")
				view.bottom.TextColor3 = PanelKit.MUTED
			else
				view.bottom.Text = "💰" .. short(state.price)
				view.bottom.TextColor3 = if state.state == "next" then GOLD else PanelKit.MUTED
			end
		end
	end

	-- Przycisk kupna
	local canBuy = false
	if nextSlot and nextPrice then
		local armed = os.clock() - armedAt < CONFIRM_SECONDS
		buy.Text = t(if armed then "SHOWCASE_BUY_CONFIRM" else "SHOWCASE_BUY", { formatCoins(nextPrice) })
		canBuy = coins >= nextPrice
		if not canBuy and status == "" then
			statusLabel.Text = t("SHOWCASE_NO_COINS", { formatCoins(nextPrice - coins) })
		end
	else
		buy.Text = t(if reason == "world" then "SHOWCASE_NEED_WORLD" else "SHOWCASE_FULL")
	end
	if status ~= "" then
		statusLabel.Text = status
	elseif canBuy or not nextSlot then
		statusLabel.Text = t("SHOWCASE_HINT")
	end
	UiKit.recolor(buy, if canBuy then GREEN else GREY)
	buy.Active = canBuy

	-- Lista
	local key = {}
	for _, item in options do
		table.insert(key, signature(item))
	end
	if optionsKey ~= table.concat(key, ";") .. Localize.getLocale() then
		rebuildOptions()
	end
	listEmpty.Visible = #options == 0
	listEmpty.Text = t("SHOWCASE_OPTIONS_EMPTY")
	local slot = selected
	local current = if slot and slots[slot] then slots[slot].item else nil
	pickHeader.Text = if slot then t("SHOWCASE_PICK_ITEM", { slot }) else t("SHOWCASE_OPTIONS", { #options })
	remove.Visible = current ~= nil
	remove.Text = t("SHOWCASE_REMOVE")
end

selectSlot = function(slot: number)
	local state = slots[slot]
	if not state then
		return
	end
	status = ""
	if state.state == "owned" then
		selected = slot
		Audio.play("click")
	elseif state.state == "next" then
		status = t("SHOWCASE_BUY_HINT")
		Audio.play("click")
	else
		Audio.play("warn")
		local mountain = Showcase.slotOf(slot) == 4
		status = t(if state.state == "world" then (if mountain then "SHOWCASE_MOUNTAIN_LOCKED" else "SHOWCASE_NEED_WORLD") else "SHOWCASE_BUY_ORDER")
	end
	render()
end

buy.Activated:Connect(function()
	if not buy.Active or not nextSlot then
		return
	end
	if os.clock() - armedAt >= CONFIRM_SECONDS then
		-- Pierwsze kliknięcie tylko pyta (drogie miejsca): drugie w ciągu kilku sekund kupuje
		armedAt = os.clock()
		Audio.play("click")
		render()
		task.delay(CONFIRM_SECONDS + 0.05, render)
		return
	end
	armedAt = 0
	Audio.play("coin")
	send({ op = "buy", slot = nextSlot })
end)

remove.Activated:Connect(function()
	local slot = selected
	if slot and slots[slot] and slots[slot].item then
		Audio.play("click")
		send({ op = "clear", slot = slot })
	end
end)

-- ===== Dane z serwera =====

Remotes.get("ShowcaseView").OnClientEvent:Connect(function(view: any, open: boolean)
	if typeof(view) ~= "table" then
		return
	end
	local fresh: { SlotState } = {}
	for index, raw in (if typeof(view.slots) == "table" then view.slots else {}) :: { any } do
		if typeof(raw) == "table" and index <= Showcase.TOTAL then
			fresh[index] = {
				state = if typeof(raw.state) == "string" then raw.state else "locked",
				price = if typeof(raw.price) == "number" then raw.price else 0,
				item = Showcase.readExhibit(raw.item),
			}
		end
	end
	slots = fresh
	options = {}
	for _, raw in (if typeof(view.options) == "table" then view.options else {}) :: { any } do
		local item = Showcase.readExhibit(raw)
		if item then
			table.insert(options, item)
		end
	end
	nextSlot = if typeof(view.next) == "number" then view.next else nil
	nextPrice = if typeof(view.nextPrice) == "number" then view.nextPrice else nil
	reason = if typeof(view.reason) == "string" then view.reason else nil
	coins = if typeof(view.coins) == "number" then view.coins else coins
	if open then
		-- Na start zaznaczone pierwsze wolne miejsce (albo pierwsze w ogóle)
		selected = nil
		for slot, state in slots do
			if state.state == "owned" and not state.item then
				selected = slot
				break
			end
		end
		status = ""
		window.setOpen(true)
	end
	render()
end)

window.onToggle(function(open: boolean)
	if open then
		render()
	else
		armedAt = 0
	end
end)

Localize.onChanged(function()
	render()
end)

function ShowcasePanel.setCoins(value: number)
	coins = value
	render()
end

return ShowcasePanel
