--!strict
-- Okno Kuźni Grzybów (Moździerz Zielarki). Po lewej ekwipunek (grzyby z koszyka), po prawej trzy miejsca,
-- szanse i przycisk „Połącz za …”. Klik w grzyb wrzuca go do pierwszego wolnego miejsca, klik w miejsce
-- go wyjmuje. Po połączeniu bęben przeskakuje po trzech wrzuconych grzybach i zatrzymuje się na wyniku.
-- Podgląd liczy Shared/Forge, ale wynik losuje serwer (ForgeService); okno tylko go pokazuje.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Economy)
local Forge = require(Shared.Forge)
local Remotes = require(Shared.Remotes)
local Audio = require(script.Parent.Audio)
local ClassColor = require(script.Parent.ClassColor)
local Localize = require(script.Parent.Localize)
local MushroomArt = require(script.Parent.MushroomArt)
local MutationText = require(script.Parent.MutationText)
local PanelKit = require(script.Parent.PanelKit)
local UiKit = require(script.Parent.UiKit)

local ForgePanel = {}

type Item = Forge.Item

local WIDTH, HEIGHT = 780, 480
local INV_W = 300
local RIGHT_X = INV_W + 16
local RIGHT_W = 436
local SLOT_W, SLOT_H, SLOT_GAP = 132, 150, 20
local TILE_W, TILE_H = 64, 84
local RESULT_Y = 34 + SLOT_H + 12
local RESULT_H = 150
local BUTTON_Y = RESULT_Y + RESULT_H + 12
local REEL_STEPS = 15
local OUTLINE = PanelKit.OUTLINE
local GREEN = Color3.fromRGB(86, 186, 84)
local GREY = Color3.fromRGB(120, 108, 98)
local VIOLET = Color3.fromRGB(150, 110, 255)
local LOCKED = Color3.fromRGB(70, 52, 40)
local GOLD = PanelKit.GOLD
local BUST_COLOR = Color3.fromRGB(240, 140, 120)

-- Napis po animacji, jego kolor i dźwięk, według rodzaju wyniku z serwera
local OUTCOME_LOOK: { [string]: { key: string, color: Color3, sound: string } } = {
	bust = { key = "FORGE_OUT_BUST", color = Color3.fromRGB(235, 86, 70), sound = "crack" },
	normal = { key = "FORGE_OUT_NORMAL", color = Color3.fromRGB(150, 230, 120), sound = "shimmer" },
	lucky = { key = "FORGE_OUT_LUCKY", color = GOLD, sound = "levelup" },
	recipe = { key = "FORGE_OUT_RECIPE", color = Color3.fromRGB(190, 140, 255), sound = "levelup" },
	recipeLucky = { key = "FORGE_OUT_RECIPE_LUCKY", color = GOLD, sound = "levelup" },
	mythic = { key = "FORGE_OUT_MYTHIC", color = Color3.fromRGB(255, 70, 110), sound = "swell" },
	secret = { key = "FORGE_OUT_SECRET", color = Color3.fromRGB(236, 240, 255), sound = "swell" },
}

local basket: { Item } = {}
local basketKey = ""
local pendingBasket: { items: { Item }, key: string }? = nil -- stan z serwera, który przyszedł w czasie animacji
local coins = 0
local access: Forge.Access = {}
local found: { [string]: number } = {}
local chosen: { number } = {} -- indeksy koszyka w kolejności wrzucenia (najwyżej 3)
local sentInputs: { Item }? = nil -- kopie wrzuconych grzybów (do animacji, bo serwer już je zabrał)
local waiting = false
local revealing = false
local lastSent = 0
local shown: { item: Item, kind: string }? = nil -- ostatni wynik (widać go, dopóki nic nie wrzucisz)

local function t(key: string, args: { any }?): string
	return Localize.t(key, args)
end

local function formatCoins(value: number): string
	local s = tostring(math.floor(value + 0.5))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (formatted:gsub("^ ", ""))
end

-- Krótko na kafelku: 950, 1,2k, 35k, 2,4M
local function short(value: number): string
	local function one(x: number, suffix: string): string
		local text = if x < 10 then string.format("%.1f", x) else tostring(math.floor(x))
		text = text:gsub("%.0$", "")
		if Localize.getLocale() == "pl" then
			text = text:gsub("%.", ",")
		end
		return text .. suffix
	end
	if value >= 1e9 then
		return one(value / 1e9, "B")
	elseif value >= 1e6 then
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

local function variantName(rank: number): string
	local def = Economy.getVariant(Economy.variantOfRank(rank))
	return if def then t(def.key) else t("ATLAS_FORM_NORMAL")
end

-- Ikonki wariantu i cech (np. "🌈🌿✨")
local function marks(item: Item): string
	local out = {}
	local variant = Economy.getVariant(item.v)
	if variant then
		table.insert(out, variant.icon)
	end
	for _, id in (item.x or {}) :: { string } do
		local tag = Economy.getTag(id)
		if tag then
			table.insert(out, tag.icon)
		end
	end
	return table.concat(out)
end

local function tagIcons(tags: { string }): string
	local out = {}
	for _, id in tags do
		local tag = Economy.getTag(id)
		if tag then
			table.insert(out, tag.icon)
		end
	end
	return table.concat(out, " ")
end

local function signature(item: Item?): string
	if not item then
		return ""
	end
	return string.format("%s|%s|%s|%s", item.s, item.v or "", table.concat((item.x or {}) :: { string }, ","), tostring(item.d or ""))
end

-- ===== Okno =====

local window = PanelKit.window({
	name = "Forge",
	parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	width = WIDTH,
	height = HEIGHT,
	ribbon = Color3.fromRGB(120, 80, 200),
	icon = "fertilizer",
	pillIcon = "coins",
	pillColor = Color3.fromRGB(52, 38, 30),
})
local content = window.content

local function isOpen(): boolean
	return window.isOpen()
end

-- Grzybek z aurą (MushroomArt) w ramce; bez arkusza emotka. Budowany od nowa tylko po zmianie grzyba.
-- Dzieci o nazwie "Keep" (np. znak zapytania) zostają.
local function drawArt(box: Frame, item: Item?, dim: boolean)
	local key = if item then signature(item) .. "|" .. tostring(dim) else ""
	if box:GetAttribute("ArtKey") == key then
		return
	end
	box:SetAttribute("ArtKey", key)
	for _, child in box:GetChildren() do
		if child.Name ~= "Keep" then
			child:Destroy()
		end
	end
	if not item then
		return
	end
	local still = function(): boolean
		return false
	end
	local art = MushroomArt.build(box, item :: any, { active = if dim then still else isOpen })
	if art then
		if dim then
			for _, d in art:GetDescendants() do
				if d:IsA("ImageLabel") then
					d.ImageTransparency = 0.6
				end
			end
		end
		return
	end
	local icon = PanelKit.label(box, "Icon", UDim2.fromScale(1, 1), UDim2.new(), 60)
	icon.Text = "🍄"
	icon.TextTransparency = if dim then 0.6 else 0
	icon.ZIndex = box.ZIndex + 1
end

local function artBox(parent: Instance, size: number, position: UDim2, anchor: Vector2?): Frame
	local box = Instance.new("Frame")
	box.Name = "Art"
	box.BackgroundTransparency = 1
	box.Size = UDim2.fromOffset(size, size)
	box.Position = position
	box.AnchorPoint = anchor or Vector2.zero
	box.ZIndex = 6
	box.Parent = parent
	return box
end

-- ----- Ekwipunek -----

local invHeader = PanelKit.label(content, "InventoryHeader", UDim2.fromOffset(INV_W, 22), UDim2.fromOffset(0, 34), 18, PanelKit.MUTED)
local inv = Instance.new("ScrollingFrame")
inv.Name = "Inventory"
inv.Size = UDim2.new(0, INV_W, 1, -62)
inv.Position = UDim2.fromOffset(0, 60)
inv.BackgroundColor3 = PanelKit.BG_DARK
inv.BackgroundTransparency = 0.25
inv.BorderSizePixel = 0
inv.ScrollBarThickness = 8
inv.ScrollBarImageColor3 = PanelKit.LINE
inv.CanvasSize = UDim2.new()
inv.AutomaticCanvasSize = Enum.AutomaticSize.Y
inv.ZIndex = 4
inv.Parent = content
PanelKit.corner(inv, UDim.new(0, 16))
PanelKit.stroke(inv, OUTLINE, 3)
local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.fromOffset(TILE_W, TILE_H)
grid.CellPadding = UDim2.fromOffset(5, 6)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = inv
local invPad = Instance.new("UIPadding")
invPad.PaddingTop = UDim.new(0, 8)
invPad.PaddingBottom = UDim.new(0, 8)
invPad.PaddingLeft = UDim.new(0, 8)
invPad.PaddingRight = UDim.new(0, 12)
invPad.Parent = inv
-- Pusty koszyk: napis na środku listy (poza siatką, żeby nie zajmował kafelka)
local invEmpty = PanelKit.label(content, "InventoryEmpty", UDim2.fromOffset(INV_W - 40, 80), UDim2.fromOffset(20, 120), 16, PanelKit.MUTED, PanelKit.BODY_FONT)
invEmpty.TextWrapped = true
invEmpty.ZIndex = 6

type Tile = { button: TextButton, stroke: UIStroke, check: TextLabel, index: number }
local tiles: { Tile } = {}
local tilesKey: string? = nil

local toggle: (number) -> ()
local render: () -> ()

local function rebuildTiles()
	for _, tile in tiles do
		tile.button:Destroy()
	end
	tiles = {}
	tilesKey = basketKey
	local order = {}
	for index in basket do
		table.insert(order, index)
	end
	-- Najpierw te, które można wrzucić, od najcenniejszego
	table.sort(order, function(a, b)
		local ea = (Forge.eligible(basket[a]))
		local eb = (Forge.eligible(basket[b]))
		if ea ~= eb then
			return ea
		end
		local va, vb = Economy.itemValue(basket[a] :: any), Economy.itemValue(basket[b] :: any)
		if va ~= vb then
			return va > vb
		end
		return a < b
	end)
	for position, index in order do
		local item = basket[index]
		local ok = (Forge.eligible(item))
		local button = Instance.new("TextButton")
		button.Name = "Item" .. index
		button.LayoutOrder = position
		button.Text = ""
		button.AutoButtonColor = false
		button.BackgroundColor3 = if ok then PanelKit.CARD else LOCKED
		button.ZIndex = 5
		button.Parent = inv
		PanelKit.corner(button, UDim.new(0, 12))
		local stroke = PanelKit.stroke(button, OUTLINE, 2)
		local box = artBox(button, 50, UDim2.new(0.5, 0, 0, 3), Vector2.new(0.5, 0))
		drawArt(box, item, not ok)
		local icons = PanelKit.label(button, "Marks", UDim2.new(1, -4, 0, 13), UDim2.fromOffset(2, 53), 12, PanelKit.TEXT, PanelKit.BODY_FONT)
		icons.Text = marks(item)
		icons.ZIndex = 7
		local value = PanelKit.label(button, "Value", UDim2.new(1, -4, 0, 14), UDim2.fromOffset(2, 67), 13, if ok then GOLD else PanelKit.MUTED, PanelKit.BODY_FONT)
		value.Text = if ok then "💰" .. short(Economy.itemValue(item :: any)) else "🔒"
		value.ZIndex = 7
		local check = PanelKit.label(button, "Check", UDim2.fromOffset(22, 22), UDim2.new(1, -24, 0, 2), 18, GREEN)
		check.Text = "✔"
		check.ZIndex = 8
		check.Visible = false
		UiKit.outline(check, 2)
		button.Activated:Connect(function()
			toggle(index)
		end)
		table.insert(tiles, { button = button, stroke = stroke, check = check, index = index })
	end
end

-- ----- Trzy miejsca -----

type SlotView = { card: TextButton, stroke: UIStroke, title: TextLabel, info: TextLabel, art: Frame, empty: TextLabel }
local slotViews: { SlotView } = {}
for slot = 1, Forge.SLOTS do
	local x = RIGHT_X + (slot - 1) * (SLOT_W + SLOT_GAP)
	local card = Instance.new("TextButton")
	card.Name = "Slot" .. slot
	card.Text = ""
	card.AutoButtonColor = false
	card.Size = UDim2.fromOffset(SLOT_W, SLOT_H)
	card.Position = UDim2.fromOffset(x, 34)
	card.BackgroundColor3 = PanelKit.CARD
	card.ZIndex = 4
	card.Parent = content
	PanelKit.corner(card, UDim.new(0, 16))
	local stroke = PanelKit.stroke(card, OUTLINE, 2.5)
	local title = PanelKit.label(card, "Title", UDim2.new(1, -10, 0, 20), UDim2.fromOffset(5, 5), 16)
	title.ZIndex = 6
	local box = artBox(card, 72, UDim2.new(0.5, 0, 0, 27), Vector2.new(0.5, 0))
	local info = PanelKit.label(card, "Info", UDim2.new(1, -10, 0, 40), UDim2.new(0, 5, 1, -46), 13, PanelKit.TEXT, PanelKit.BODY_FONT)
	info.TextWrapped = true
	info.ZIndex = 6
	local empty = PanelKit.label(card, "Empty", UDim2.new(1, -16, 1, -16), UDim2.fromOffset(8, 8), 15, PanelKit.MUTED, PanelKit.BODY_FONT)
	empty.TextWrapped = true
	empty.ZIndex = 6
	card.Activated:Connect(function()
		if waiting or revealing or not chosen[slot] then
			return
		end
		table.remove(chosen, slot)
		Audio.play("click")
		render()
	end)
	table.insert(slotViews, { card = card, stroke = stroke, title = title, info = info, art = box, empty = empty })
	if slot < Forge.SLOTS then
		local plus = PanelKit.label(content, "Plus", UDim2.fromOffset(SLOT_GAP, 30), UDim2.fromOffset(x + SLOT_W, 34 + SLOT_H / 2 - 15), 26, GOLD)
		plus.Text = "+"
		plus.ZIndex = 5
	end
end

-- ----- Szanse i wynik -----

local resultBox = Instance.new("Frame")
resultBox.Name = "Result"
resultBox.Size = UDim2.fromOffset(RIGHT_W, RESULT_H)
resultBox.Position = UDim2.fromOffset(RIGHT_X, RESULT_Y)
resultBox.BackgroundColor3 = PanelKit.BG_DARK
resultBox.ZIndex = 4
resultBox.Parent = content
PanelKit.corner(resultBox, UDim.new(0, 16))
local resultStroke = PanelKit.stroke(resultBox, VIOLET, 2.5)
local reelArt = artBox(resultBox, 116, UDim2.fromOffset(12, 17))
local mystery = PanelKit.label(reelArt, "Keep", UDim2.fromScale(1, 1), UDim2.new(), 72, PanelKit.MUTED)
mystery.Text = "?"
mystery.ZIndex = 7

local TEXT_X = 140
local function line(name: string, y: number, height: number, maxSize: number, color: Color3, font: Enum.Font?): TextLabel
	local label = PanelKit.label(resultBox, name, UDim2.new(1, -TEXT_X - 10, 0, height), UDim2.fromOffset(TEXT_X, y), maxSize, color, font or PanelKit.BODY_FONT)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 6
	return label
end
local headLine = line("Head", 8, 24, 20, PanelKit.TEXT, PanelKit.TITLE_FONT)
local bustLine = line("Bust", 36, 20, 15, BUST_COLOR)
local normalLine = line("Normal", 60, 20, 15, PanelKit.TEXT)
local luckyLine = line("Lucky", 84, 20, 15, GOLD)
local valueLine = line("Value", 112, 18, 14, PanelKit.MUTED)

local banner = PanelKit.label(resultBox, "Banner", UDim2.new(1, -20, 0, 56), UDim2.new(0, 10, 0.5, -28), 46, GOLD)
banner.ZIndex = 20
banner.Visible = false
UiKit.outline(banner, 3)
local bannerScale = Instance.new("UIScale")
bannerScale.Parent = banner

-- ----- Przycisk -----

local fuse = Instance.new("TextButton")
fuse.Name = "Fuse"
fuse.Size = UDim2.fromOffset(262, 50)
fuse.Position = UDim2.fromOffset(RIGHT_X, BUTTON_Y)
fuse.Font = PanelKit.TITLE_FONT
fuse.TextScaled = true
fuse.TextColor3 = Color3.new(1, 1, 1)
fuse.ZIndex = 5
fuse.Parent = content
UiKit.button(fuse, GREEN, { stroke = 3, radius = UDim.new(0, 16), gloss = true })
UiKit.outline(fuse, 2.5)
local fusePad = Instance.new("UIPadding")
fusePad.PaddingLeft = UDim.new(0, 12)
fusePad.PaddingRight = UDim.new(0, 12)
fusePad.Parent = fuse
local fuseSize = Instance.new("UITextSizeConstraint")
fuseSize.MaxTextSize = 24
fuseSize.Parent = fuse
-- Podpowiedź obok przycisku z zapasem: przycisk rośnie przy najechaniu (UiKit)
local status = PanelKit.label(content, "Status", UDim2.fromOffset(RIGHT_W - 286, 50), UDim2.fromOffset(RIGHT_X + 286, BUTTON_Y), 15, PanelKit.MUTED, PanelKit.BODY_FONT)
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextWrapped = true

-- ===== Stan i rysowanie =====

local function chosenItems(): { Item }
	local items = {}
	for _, index in chosen do
		local item = basket[index]
		if item then
			table.insert(items, item)
		end
	end
	return items
end

-- Po zmianie koszyka: wrzucone grzyby szukamy po wyglądzie (indeksy mogły się przesunąć)
local function remapChosen(old: { Item })
	local fresh: { number } = {}
	for _, index in chosen do
		local wanted = signature(old[index])
		local hit: number? = nil
		if wanted ~= "" and signature(basket[index]) == wanted and not table.find(fresh, index) then
			hit = index
		elseif wanted ~= "" then
			for j, item in basket do
				if signature(item) == wanted and not table.find(fresh, j) then
					hit = j
					break
				end
			end
		end
		if hit then
			table.insert(fresh, hit)
		end
	end
	chosen = fresh
end

local function showMatchHead(preview: Forge.Preview)
	local match = preview.match
	if not match then
		headLine.Text = t("FORGE_HEAD_RANDOM")
		headLine.TextColor3 = PanelKit.TEXT
		return
	end
	if (found[match.id] or 0) > 0 then
		headLine.Text = t("FORGE_HEAD_KNOWN", { speciesName(match.id) })
		headLine.TextColor3 = ClassColor.of(match.id):Lerp(Color3.new(1, 1, 1), 0.2)
	else
		headLine.Text = t("FORGE_HEAD_SENSE")
		headLine.TextColor3 = Color3.fromRGB(200, 160, 255)
	end
end

render = function()
	if not isOpen() then
		return
	end
	window.title.Text = t("FORGE_TITLE")
	window.pillText.Text = formatCoins(coins)

	-- Ekwipunek
	if tilesKey ~= basketKey and not revealing then
		rebuildTiles()
	end
	local eligible = 0
	for _, item in basket do
		if Forge.eligible(item) then
			eligible += 1
		end
	end
	invHeader.Text = t("FORGE_INVENTORY", { eligible, #basket })
	invEmpty.Visible = #basket == 0
	invEmpty.Text = t("FORGE_INVENTORY_EMPTY")
	for _, tile in tiles do
		local inSlot = table.find(chosen, tile.index) ~= nil
		tile.check.Visible = inSlot
		tile.stroke.Color = if inSlot then GREEN else OUTLINE
		tile.stroke.Thickness = if inSlot then 3 else 2
	end

	-- Miejsca
	local items = chosenItems()
	for slot, view in slotViews do
		local item = items[slot]
		view.empty.Visible = item == nil
		view.title.Visible = item ~= nil
		view.info.Visible = item ~= nil
		if item then
			view.title.Text = speciesName(item.s)
			ClassColor.paint(view.title, item.s)
			local mutations = MutationText.rich(item.v, item.x)
			view.info.Text = (if mutations ~= "" then mutations .. "\n" else "") .. "💰 " .. formatCoins(Economy.itemValue(item :: any))
			drawArt(view.art, item, false)
		else
			view.empty.Text = t("FORGE_SLOT_PICK")
			drawArt(view.art, nil, false)
		end
		if not revealing then
			view.stroke.Color = OUTLINE
			view.stroke.Thickness = 2.5
		end
	end

	-- Szanse albo ostatni wynik
	local preview = if #items == Forge.SLOTS then Forge.preview(items, access) else nil
	local current = shown
	if revealing then
		-- bęben kręci się w animacji (reveal), napisy czekają
	elseif current and #items == 0 then
		local item = current.item
		local look = OUTCOME_LOOK[current.kind] or OUTCOME_LOOK.normal
		mystery.Visible = false
		drawArt(reelArt, item, false)
		headLine.Text = speciesName(item.s)
		headLine.TextColor3 = ClassColor.of(item.s):Lerp(Color3.new(1, 1, 1), 0.2)
		bustLine.Text = t(look.key)
		bustLine.TextColor3 = look.color
		local mutations = MutationText.rich(item.v, item.x)
		normalLine.Text = if mutations ~= "" then mutations else t("FORGE_NO_TRAITS")
		luckyLine.Text = "💰 " .. formatCoins(Economy.itemValue(item :: any))
		valueLine.Text = t("FORGE_AGAIN")
		resultStroke.Color = look.color
	elseif preview then
		mystery.Visible = true
		drawArt(reelArt, nil, false)
		showMatchHead(preview)
		local tags = tagIcons(preview.tags)
		bustLine.Text = t("FORGE_LINE_BUST", { math.floor(preview.bust * 100 + 0.5), variantName(preview.minRank) } :: { any })
		bustLine.TextColor3 = BUST_COLOR
		normalLine.Text = t("FORGE_LINE_NORMAL", { math.floor(preview.normal * 100 + 0.5), if tags ~= "" then tags else "—" } :: { any })
		luckyLine.Text = t("FORGE_LINE_LUCKY", { math.floor(preview.lucky * 100 + 0.5) })
		valueLine.Text = t("FORGE_INPUT_VALUE", { formatCoins(preview.inputValue) })
		resultStroke.Color = VIOLET
	else
		mystery.Visible = true
		drawArt(reelArt, nil, false)
		headLine.Text = t("FORGE_HEAD_EMPTY")
		headLine.TextColor3 = PanelKit.TEXT
		bustLine.Text = t("FORGE_RULE_1")
		bustLine.TextColor3 = PanelKit.MUTED
		normalLine.Text = t("FORGE_RULE_2")
		luckyLine.Text = t("FORGE_RULE_3")
		valueLine.Text = ""
		resultStroke.Color = VIOLET
	end

	-- Przycisk
	local ready = false
	if waiting or revealing then
		fuse.Text = t("FORGE_WORKING")
		status.Text = ""
	elseif not preview then
		fuse.Text = t("FORGE_NEED_THREE")
		status.Text = t("FORGE_HINT_PICK")
	else
		fuse.Text = t("FORGE_COST", { formatCoins(preview.fee) })
		if coins < preview.fee then
			status.Text = t("FORGE_NO_COINS", { formatCoins(preview.fee - coins) })
		else
			ready = true
			status.Text = t("FORGE_HINT_REMOVE")
		end
	end
	UiKit.recolor(fuse, if ready then GREEN else GREY)
	fuse.Active = ready
end

toggle = function(index: number)
	if waiting or revealing then
		return
	end
	local at = table.find(chosen, index)
	if at then
		table.remove(chosen, at)
		Audio.play("click")
	else
		local ok, why = Forge.eligible(basket[index])
		if not ok then
			Audio.play("warn")
			status.Text = t(why or "FORGE_WRONG_INPUT")
			return
		end
		if #chosen >= Forge.SLOTS then
			Audio.play("warn")
			return
		end
		table.insert(chosen, index)
		shown = nil
		Audio.play("pick", { jitter = 0.08 })
	end
	render()
end

local function applyBasket(items: { Item }, key: string)
	local old = basket
	basket = items
	basketKey = key
	if #chosen > 0 then
		remapChosen(old)
	end
end

-- ===== Animacja wyniku =====

local function showBanner(text: string, color: Color3)
	banner.Text = text
	banner.TextColor3 = color
	banner.TextTransparency = 0
	banner.Visible = true
	bannerScale.Scale = 0.4
	TweenService:Create(bannerScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local shownText = text
	task.delay(1.4, function()
		if banner.Text ~= shownText then
			return
		end
		local fade = TweenService:Create(banner, TweenInfo.new(0.4), { TextTransparency = 1 })
		fade.Completed:Connect(function()
			if banner.Text == shownText then
				banner.Visible = false
			end
		end)
		fade:Play()
	end)
end

local function reveal(result: Item, kind: string, pick: number)
	local inputs = sentInputs
	sentInputs = nil
	revealing = true
	waiting = false
	render()
	task.spawn(function()
		mystery.Visible = false
		headLine.Text = t("FORGE_ROLLING")
		headLine.TextColor3 = PanelKit.TEXT
		bustLine.Text = ""
		normalLine.Text = ""
		luckyLine.Text = ""
		valueLine.Text = ""
		if inputs and #inputs == Forge.SLOTS then
			-- Bęben skacze po trzech wrzuconych grzybach, zwalnia i staje na wylosowanym (pick)
			for step = 1, REEL_STEPS do
				local slot = ((pick - 1) - (REEL_STEPS - step)) % Forge.SLOTS + 1
				for other, view in slotViews do
					view.stroke.Color = if other == slot then GOLD else OUTLINE
					view.stroke.Thickness = if other == slot then 4 else 2.5
				end
				drawArt(reelArt, inputs[slot], false)
				Audio.play("tink", { volume = 0.35, pitch = 0.9 + step * 0.03 })
				task.wait(0.05 + (step / REEL_STEPS) ^ 2 * 0.3)
			end
			task.wait(0.25)
		end
		-- Wynik: przemiana w grzyb z kuźni (przepis, mityczny, sekretny) albo utrata cech przy skusze
		local look = OUTCOME_LOOK[kind] or OUTCOME_LOOK.normal
		drawArt(reelArt, result, false)
		shown = { item = result, kind = kind }
		chosen = {}
		revealing = false
		local fresh = pendingBasket
		if fresh then
			pendingBasket = nil
			applyBasket(fresh.items, fresh.key)
		end
		render()
		Audio.play(look.sound)
		if kind == "mythic" or kind == "secret" then
			Audio.play("levelup")
		end
		local sparks = if kind == "bust" then 0 elseif kind == "mythic" or kind == "secret" then 48 elseif kind == "normal" then 18 else 32
		if sparks > 0 then
			UiKit.burst(resultBox, Vector2.new(70, 75), sparks, { look.color, VIOLET, Color3.fromRGB(150, 255, 90) })
		else
			UiKit.shake(resultBox)
		end
		showBanner(t(look.key), look.color)
	end)
end

-- ===== Akcje =====

fuse.Activated:Connect(function()
	if waiting or revealing or not fuse.Active or #chosen ~= Forge.SLOTS then
		return
	end
	local inputs = {}
	for _, index in chosen do
		table.insert(inputs, table.clone(basket[index]))
	end
	sentInputs = inputs
	waiting = true
	render()
	Audio.play("cauldron", { volume = 0.8, duration = 2 })
	Remotes.get("ForgeAction"):FireServer({ kind = "fuse", slots = table.clone(chosen), key = basketKey })
	-- Serwer zawsze odpowiada (wynik albo powód), ale gdyby odpowiedź zginęła, przycisk nie zostaje zablokowany
	local sentAt = os.clock()
	lastSent = sentAt
	task.delay(6, function()
		if waiting and lastSent == sentAt then
			waiting = false
			sentInputs = nil
			local fresh = pendingBasket
			if fresh then
				pendingBasket = nil
				applyBasket(fresh.items, fresh.key)
			end
			render()
		end
	end)
end)

-- ===== Dane z serwera =====

Remotes.get("ForgeView").OnClientEvent:Connect(function(view: any, open: boolean)
	if typeof(view) ~= "table" then
		return
	end
	access = if typeof(view.access) == "table" then view.access else {}
	found = if typeof(view.found) == "table" then view.found else {}
	if typeof(view.result) == "table" and typeof(view.kind) == "string" then
		local pick = if typeof(view.pick) == "number" then math.clamp(view.pick, 1, Forge.SLOTS) else 1
		reveal(view.result, view.kind, pick)
	elseif waiting then
		-- Odmowa (powód przyszedł komunikatem): grzyby zostają w miejscach
		waiting = false
		sentInputs = nil
		local fresh = pendingBasket
		if fresh then
			pendingBasket = nil
			applyBasket(fresh.items, fresh.key)
		end
	end
	if open then
		window.setOpen(true)
	end
	render()
end)

window.onToggle(function(open: boolean)
	if open then
		render()
	elseif not revealing and not waiting then
		chosen = {}
		shown = nil
	end
end)

Localize.onChanged(function()
	tilesKey = nil -- krótkie liczby na kafelkach zależą od języka
	render()
end)

ForgePanel.render = render

function ForgePanel.setBasket(items: { Item }, key: string)
	if revealing or waiting then
		-- Wynik pokaże się po animacji; nowy koszyk przyjmujemy dopiero wtedy
		pendingBasket = { items = items, key = key }
		return
	end
	applyBasket(items, key)
	render()
end

function ForgePanel.setCoins(value: number)
	coins = value
	render()
end

return ForgePanel
