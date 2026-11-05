--!strict
-- Ekspedycja do Głębokich Komór: dwa okna PanelKit.
--   * Tablica zleceń (przycisk przy tablicy w Obozie): trzy zlecenia z celem, stanem komór i nagrodą
--     (zlecenie dnia ze złotą plakietką), ranga ekspedytora, twoja ekipa albo ekipy innych do dołączenia.
--   * Kolekcja reliktów (z tablicy albo przy regale w ogródku): dwa zestawy po 4, odłamki, składanie,
--     renowacja (relikt staje na regale) i oprawa za monety.
-- Stan przychodzi z serwera (DelveState); przyciski tylko proszą (DelveAction), serwer wszystko sprawdza.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Delve = require(Shared:WaitForChild("Delve"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Localize = require(script.Parent.Localize)
local PanelKit = require(script.Parent.PanelKit)
local SettingsButtons = require(script.Parent.SettingsButtons)
local ShopLook = require(script.Parent.ShopLook)
local UiFx = require(script.Parent.UiFx)
local UiKit = require(script.Parent.UiKit)

local DelvePanel = {}

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local DelveAction = Remotes.get("DelveAction")

local TITLE_FONT = PanelKit.TITLE_FONT
local BODY_FONT = PanelKit.BODY_FONT
local OUTLINE = PanelKit.OUTLINE
local TEXT = PanelKit.TEXT
local MUTED = PanelKit.MUTED
local GOLD = PanelKit.GOLD
local GREEN = Color3.fromRGB(64, 190, 78)
local CHIP = Color3.fromRGB(50, 34, 24)
local KIND_COLOR: { [string]: Color3 } = {
	rubble = Color3.fromRGB(150, 104, 64),
	chest = Color3.fromRGB(70, 120, 150),
	samples = Color3.fromRGB(70, 150, 120),
}
local FRAME_COLOR = { Color3.fromRGB(196, 124, 64), Color3.fromRGB(200, 206, 214), Color3.fromRGB(255, 206, 64) }

local state: any = nil
local coins = 0

local function formatCoins(value: number): string
	local s = tostring(math.floor(value + 0.5))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (formatted:gsub("^ ", ""))
end

local function formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function button(parent: Instance, name: string, color: Color3, size: UDim2, position: UDim2, textSize: number): (TextButton, TextLabel)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = ""
	b.Size = size
	b.Position = position
	b.ZIndex = 4
	b.Parent = parent
	local s = UiKit.button(b, color, { gloss = true, radius = UDim.new(0, 12), stroke = 3 })
	s.Color = OUTLINE
	local label = PanelKit.label(b, "Text", UDim2.new(1, -12, 1, -8), UDim2.fromOffset(6, 4), textSize, Color3.new(1, 1, 1), TITLE_FONT)
	label.ZIndex = 6
	UiKit.outline(label, 2)
	return b, label
end

local function chip(parent: Instance, name: string, size: UDim2, position: UDim2, textSize: number, color: Color3?): TextLabel
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = position
	f.BackgroundColor3 = color or CHIP
	f.ZIndex = 4
	f.Parent = parent
	PanelKit.corner(f, UDim.new(0, 10))
	PanelKit.stroke(f, OUTLINE, 2)
	local l = PanelKit.label(f, "Text", UDim2.new(1, -12, 1, -4), UDim2.fromOffset(6, 2), textSize, TEXT, BODY_FONT)
	l.ZIndex = 5
	return l
end

local function setEnabled(b: TextButton, label: TextLabel, on: boolean, color: Color3)
	b.Active = on
	b.AutoButtonColor = on
	UiKit.recolor(b, if on then color else UiKit.COLORS.locked)
	label.TextTransparency = if on then 0 else 0.35
end

-- ===================== Tablica zleceń =====================

local BOARD_W, BOARD_H = 900, 560
local board = PanelKit.window({
	name = "DelveBoard",
	parent = playerGui,
	width = BOARD_W,
	height = BOARD_H,
	ribbon = Color3.fromRGB(150, 80, 50),
	icon = "scroll",
	pillIcon = "trophy",
	pillColor = Color3.fromRGB(70, 44, 30),
	displayOrder = 8,
})
local bc = board.content

local rankLine = PanelKit.label(bc, "Rank", UDim2.new(1, -200, 0, 22), UDim2.fromOffset(8, 2), 17, MUTED, BODY_FONT)
rankLine.TextXAlignment = Enum.TextXAlignment.Left
local collectionButton, collectionLabel = button(bc, "Collection", Color3.fromRGB(150, 90, 220), UDim2.fromOffset(180, 40), UDim2.new(1, -188, 0, -6), 18)

type OfferCard = {
	root: Frame,
	body: Frame,
	title: TextLabel,
	desc: TextLabel,
	modifier: TextLabel,
	reward: TextLabel,
	badge: Frame,
	badgeText: TextLabel,
	take: TextButton,
	takeLabel: TextLabel,
}
local offerCards: { OfferCard } = {}
local CARD_W, CARD_H = 280, 300
for i = 1, 3 do
	local root = Instance.new("Frame")
	root.Name = "Offer" .. i
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(CARD_W, CARD_H)
	root.Position = UDim2.fromOffset(8 + (i - 1) * (CARD_W + 14), 40)
	root.Parent = bc
	ShopLook.hover(root)
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Size = UDim2.fromScale(1, 1)
	body.BackgroundColor3 = PanelKit.CARD
	body.ClipsDescendants = true
	body.Parent = root
	PanelKit.corner(body, UDim.new(0, 20))
	PanelKit.stroke(root, OUTLINE, 3.5)
	PanelKit.corner(root, UDim.new(0, 20))
	local shade = Instance.new("UIGradient")
	shade.Rotation = 90
	shade.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 160, 150))
	shade.Parent = body
	ShopLook.halo(body, UDim2.new(0, CARD_W / 2, 0, 52), Color3.fromRGB(255, 220, 160), 140, false, 1)
	local icon = UiKit.icon("chest", body, UDim2.fromOffset(66, 66), UDim2.new(0.5, 0, 0, 52), Vector2.new(0.5, 0.5))
	icon.Name = "Icon"
	icon.ZIndex = 3
	UiFx.bob(icon, 3, 2.4 + i * 0.2)
	local title = PanelKit.label(body, "Title", UDim2.new(1, -16, 0, 30), UDim2.fromOffset(8, 92), 23, TEXT, TITLE_FONT)
	title.ZIndex = 3
	UiKit.outline(title, 2.5)
	ShopLook.title(title)
	local desc = PanelKit.label(body, "Desc", UDim2.new(1, -20, 0, 52), UDim2.fromOffset(10, 124), 14, MUTED, BODY_FONT)
	desc.TextWrapped = true
	desc.ZIndex = 3
	local modifier = chip(body, "Modifier", UDim2.new(1, -24, 0, 28), UDim2.fromOffset(12, 180), 15)
	local reward = chip(body, "Reward", UDim2.new(1, -24, 0, 28), UDim2.fromOffset(12, 212), 15, Color3.fromRGB(70, 46, 90))
	local take, takeLabel = button(body, "Take", GREEN, UDim2.new(1, -24, 0, 44), UDim2.new(0, 12, 1, -54), 20)
	UiFx.shine(take, 3 + i * 0.4)

	local badge = Instance.new("Frame")
	badge.Name = "Daily"
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.new(0.5, 0, 0, 0)
	badge.Size = UDim2.fromOffset(170, 28)
	badge.BackgroundColor3 = GOLD
	badge.Rotation = -3
	badge.ZIndex = 8
	badge.Visible = false
	badge.Parent = root
	PanelKit.corner(badge, UDim.new(0, 10))
	PanelKit.stroke(badge, OUTLINE, 3)
	UiFx.wiggle(badge, 3, 2.2)
	local badgeText = PanelKit.label(badge, "Text", UDim2.new(1, -10, 1, -6), UDim2.fromOffset(5, 3), 16, OUTLINE, TITLE_FONT)
	badgeText.ZIndex = 9

	local card: OfferCard = {
		root = root,
		body = body,
		title = title,
		desc = desc,
		modifier = modifier,
		reward = reward,
		badge = badge,
		badgeText = badgeText,
		take = take,
		takeLabel = takeLabel,
	}
	table.insert(offerCards, card)
	take.Activated:Connect(function()
		if not take.Active then
			UiKit.shake(body)
			return
		end
		UiFx.sound("ping", 0.5, 1.1)
		DelveAction:FireServer("take", i)
	end)
end

-- Dół okna: twoja ekipa albo ekipy do dołączenia
local partyFrame = Instance.new("Frame")
partyFrame.Name = "Party"
partyFrame.Size = UDim2.new(1, -16, 0, 120)
partyFrame.Position = UDim2.new(0, 8, 0, 354)
partyFrame.BackgroundColor3 = PanelKit.BG_DARK
partyFrame.Parent = bc
PanelKit.corner(partyFrame, UDim.new(0, 16))
PanelKit.stroke(partyFrame, OUTLINE, 3)
local partyTitle = PanelKit.label(partyFrame, "Title", UDim2.new(1, -24, 0, 26), UDim2.fromOffset(12, 6), 19, GOLD, TITLE_FONT)
partyTitle.TextXAlignment = Enum.TextXAlignment.Left
UiKit.outline(partyTitle, 2)
local partyText = PanelKit.label(partyFrame, "Text", UDim2.new(1, -230, 0, 76), UDim2.fromOffset(12, 36), 15, TEXT, BODY_FONT)
partyText.TextWrapped = true
partyText.TextXAlignment = Enum.TextXAlignment.Left
partyText.TextYAlignment = Enum.TextYAlignment.Top
local leaveButton, leaveLabel = button(partyFrame, "Leave", UiKit.COLORS.red, UDim2.fromOffset(190, 34), UDim2.new(1, -202, 0, 36), 16)
leaveButton.Activated:Connect(function()
	DelveAction:FireServer("leave")
end)
-- Zaproszenie znajomego z Robloxa do gry (to samo okno co przycisk Invite)
local inviteButton, inviteLabel = button(partyFrame, "Invite", Color3.fromRGB(70, 130, 220), UDim2.fromOffset(190, 34), UDim2.new(1, -202, 0, 76), 16)
inviteButton.Visible = false
inviteButton.Activated:Connect(function()
	local prompt = (SettingsButtons :: any).promptInvite
	if prompt then
		prompt()
	end
end)

-- Ekipa z gotowością: „Tom ✅, Miłosz 🚶” (✅ = przy szczelinie albo już w komorach)
local function crewText(run: any): string
	if typeof(run.crew) ~= "table" then
		return table.concat(run.members or {}, ", ")
	end
	local parts = {}
	for _, m in run.crew do
		table.insert(parts, tostring(m.name) .. " " .. (if m.ready then "✅" else "🚶"))
	end
	return table.concat(parts, ", ")
end

type JoinRow = { frame: Frame, text: TextLabel, join: TextButton, joinLabel: TextLabel, id: number }
local joinRows: { JoinRow } = {}
for i = 1, 3 do
	local row = Instance.new("Frame")
	row.Name = "Join" .. i
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, -24, 0, 26)
	row.Position = UDim2.fromOffset(12, 34 + (i - 1) * 28)
	row.Visible = false
	row.Parent = partyFrame
	local text = PanelKit.label(row, "Text", UDim2.new(1, -130, 1, 0), UDim2.fromOffset(0, 0), 15, TEXT, BODY_FONT)
	text.TextXAlignment = Enum.TextXAlignment.Left
	local join, joinLabel = button(row, "Join", GREEN, UDim2.fromOffset(118, 26), UDim2.new(1, -118, 0, 0), 14)
	local entry: JoinRow = { frame = row, text = text, join = join, joinLabel = joinLabel, id = 0 }
	join.Activated:Connect(function()
		DelveAction:FireServer("join", entry.id)
	end)
	table.insert(joinRows, entry)
end

local footer = PanelKit.label(bc, "Footer", UDim2.new(1, -16, 0, 36), UDim2.new(0, 8, 1, -40), 13, MUTED, BODY_FONT)
footer.TextWrapped = true

local function kindIcon(kind: string): string
	return if kind == "rubble" then "upgrade" elseif kind == "chest" then "chest" else "sparkles"
end

local function relicName(id: string?): string
	local def = if id then Delve.relic(id) else nil
	return if def then def.icon .. " " .. Localize.t(def.key) else ""
end

local function renderBoard()
	if not state then
		return
	end
	board.title.Text = Localize.t("DELVE_BOARD_TITLE")
	board.pillText.Text = Localize.t("DELVE_RANK_PILL", { state.rank })
	rankLine.Text = if state.nextGoal
		then Localize.t("DELVE_RANK_LINE", { state.rank, state.points, state.nextGoal, formatTime(state.lanternSeconds) })
		else Localize.t("DELVE_RANK_MAX", { state.rank, formatTime(state.lanternSeconds) })
	collectionLabel.Text = Localize.t("DELVE_COLLECTION_BUTTON")
	local run = state.run
	for i, card in offerCards do
		local offer = state.offers[i]
		card.root.Visible = offer ~= nil
		if not offer then
			continue
		end
		local kind = Delve.kind(offer.kind)
		local modifier = Delve.modifier(offer.modifier)
		card.body.BackgroundColor3 = KIND_COLOR[offer.kind] or PanelKit.CARD
		local icon = card.body:FindFirstChild("Icon")
		if icon and icon:IsA("GuiObject") then
			UiKit.setIcon(icon, kindIcon(offer.kind))
		end
		card.title.Text = if kind then Localize.t(kind.key) else offer.kind
		card.desc.Text = if kind then Localize.t(kind.desc) else ""
		card.modifier.Text = if modifier then modifier.icon .. " " .. Localize.t(modifier.key) .. (if modifier.hard then "  +" .. Delve.HARD_SHARDS .. " 💠" else "") else ""
		card.badge.Visible = offer.daily == true
		card.badgeText.Text = Localize.t("DELVE_DAILY_BADGE")
		card.reward.Text = if offer.daily
			then Localize.t("DELVE_REWARD_DAILY", { relicName(offer.relic) })
			else Localize.t("DELVE_REWARD_SET", { Localize.t(Delve.SET_KEYS[offer.set] or "") })
		local can = run == nil and state.caveUnlocked
		card.takeLabel.Text = if run then Localize.t("DELVE_TAKE_BUSY") else Localize.t("DELVE_TAKE")
		setEnabled(card.take, card.takeLabel, can, GREEN)
	end

	if run then
		local kind = Delve.kind(run.kind)
		partyTitle.Text = Localize.t("DELVE_YOUR_RUN", { if kind then Localize.t(kind.key) else run.kind })
		local left = run.expiresAt - os.time()
		local members = crewText(run)
		partyText.Text = if run.state == "prepare"
			then Localize.t("DELVE_PARTY_PREPARE", { members :: any, #run.members, Delve.MAX_PARTY, formatTime(left) })
			else Localize.t("DELVE_PARTY_ACTIVE", { members, formatTime(left) })
		leaveButton.Visible = run.state == "prepare"
		leaveLabel.Text = if run.isLeader then Localize.t("DELVE_CANCEL") else Localize.t("DELVE_LEAVE")
		inviteButton.Visible = run.state == "prepare" and #run.members < Delve.MAX_PARTY
		inviteLabel.Text = "👥 " .. Localize.t("DELVE_INVITE")
		for _, row in joinRows do
			row.frame.Visible = false
		end
		partyText.Visible = true
	else
		partyTitle.Text = Localize.t("DELVE_OPEN_RUNS")
		leaveButton.Visible = false
		inviteButton.Visible = false
		local list = state.openRuns or {}
		partyText.Visible = #list == 0
		partyText.Text = Localize.t("DELVE_NO_OPEN_RUNS")
		for i, row in joinRows do
			local entry = list[i]
			row.frame.Visible = entry ~= nil
			if entry then
				local kind = Delve.kind(entry.kind)
				local modifier = Delve.modifier(entry.modifier)
				row.id = entry.id
				row.text.Text = Localize.t("DELVE_OPEN_RUN_ROW", {
					entry.leader,
					if kind then Localize.t(kind.key) else entry.kind,
					if modifier then modifier.icon else "",
					entry.count,
					Delve.MAX_PARTY,
				})
				row.joinLabel.Text = Localize.t("DELVE_JOIN")
				setEnabled(row.join, row.joinLabel, state.caveUnlocked == true, GREEN)
			end
		end
	end
	footer.Text = Localize.t("DELVE_BOARD_FOOTER")
end

-- ===================== Kolekcja reliktów =====================

local COL_W, COL_H = 900, 580
local collection = PanelKit.window({
	name = "DelveCollection",
	parent = playerGui,
	width = COL_W,
	height = COL_H,
	ribbon = Color3.fromRGB(150, 90, 220),
	icon = "trophy",
	pillIcon = "crystal",
	pillColor = Color3.fromRGB(40, 50, 80),
	displayOrder = 8,
})
local cc = collection.content

type Tile = {
	def: Delve.RelicDef,
	body: Frame,
	stroke: UIStroke,
	icon: TextLabel,
	halo: Frame,
	name: TextLabel,
	status: TextLabel,
	action: TextButton,
	actionLabel: TextLabel,
	mode: string,
}
local tiles: { Tile } = {}
local setLabels: { [string]: TextLabel } = {}
local TILE_W, TILE_H = 206, 196
for row, set in Delve.SETS do
	local y = (row - 1) * (TILE_H + 44)
	local setLabel = PanelKit.label(cc, "Set_" .. set, UDim2.new(1, -16, 0, 26), UDim2.fromOffset(8, y), 20, GOLD, TITLE_FONT)
	setLabel.TextXAlignment = Enum.TextXAlignment.Left
	UiKit.outline(setLabel, 2)
	setLabels[set] = setLabel
	for col, def in Delve.relicsOf(set) do
		local body = Instance.new("Frame")
		body.Name = "Relic_" .. def.id
		body.Size = UDim2.fromOffset(TILE_W, TILE_H)
		body.Position = UDim2.fromOffset(8 + (col - 1) * (TILE_W + 12), y + 32)
		body.BackgroundColor3 = PanelKit.CARD
		body.Parent = cc
		body.ClipsDescendants = true
		ShopLook.hover(body)
		local halo = ShopLook.halo(body, UDim2.new(0.5, 0, 0, 38), Color3.fromRGB(def.color[1], def.color[2], def.color[3]), 110, def.rare, 1)
		halo.Visible = false
		PanelKit.corner(body, UDim.new(0, 16))
		local stroke = PanelKit.stroke(body, OUTLINE, 3)
		local shade = Instance.new("UIGradient")
		shade.Rotation = 90
		shade.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 160, 150))
		shade.Parent = body
		local icon = PanelKit.label(body, "Icon", UDim2.fromOffset(70, 60), UDim2.new(0.5, -35, 0, 8), 52, TEXT, TITLE_FONT)
		icon.Text = def.icon
		icon.ZIndex = 4
		ShopLook.bob(icon, 3, 2.2 + col * 0.15)
		local name = PanelKit.label(body, "Name", UDim2.new(1, -14, 0, 42), UDim2.fromOffset(7, 70), 17, TEXT, TITLE_FONT)
		name.TextWrapped = true
		name.ZIndex = 4
		UiKit.outline(name, 2)
		ShopLook.title(name)
		local status = PanelKit.label(body, "Status", UDim2.new(1, -14, 0, 22), UDim2.fromOffset(7, 112), 13, MUTED, BODY_FONT)
		status.ZIndex = 4
		local action, actionLabel = button(body, "Action", GREEN, UDim2.new(1, -16, 0, 44), UDim2.new(0, 8, 1, -52), 14)
		actionLabel.TextWrapped = true
		ShopLook.button(action, 2.6 + col * 0.4)
		local tile: Tile = {
			def = def,
			body = body,
			stroke = stroke,
			icon = icon,
			halo = halo,
			name = name,
			status = status,
			action = action,
			actionLabel = actionLabel,
			mode = "",
		}
		action.Activated:Connect(function()
			if not action.Active or tile.mode == "" then
				UiKit.shake(body)
				UiFx.sound("warn", 0.3)
				return
			end
			UiFx.sound("ping", 0.5, 1.2)
			UiKit.burst(collection.gui, action.AbsolutePosition + action.AbsoluteSize / 2, 10)
			DelveAction:FireServer(tile.mode, def.id)
		end)
		table.insert(tiles, tile)
	end
end
local colFooter = PanelKit.label(cc, "Footer", UDim2.new(1, -16, 0, 40), UDim2.new(0, 8, 1, -44), 13, MUTED, BODY_FONT)
colFooter.TextWrapped = true

local function renderCollection()
	if not state then
		return
	end
	local save = state.save
	collection.title.Text = Localize.t("DELVE_COLLECTION_TITLE")
	collection.pillText.Text = Localize.t("DELVE_SHARDS_PILL", { save.shards })
	for _, set in Delve.SETS do
		local owned, total = 0, 0
		for _, def in Delve.relicsOf(set) do
			total += 1
			if save.relics[def.id] then
				owned += 1
			end
		end
		setLabels[set].Text = Localize.t("DELVE_SET_LINE", { Localize.t(Delve.SET_KEYS[set]) :: any, owned, total })
	end
	for _, tile in tiles do
		local def = tile.def
		local relic = save.relics[def.id]
		tile.name.Text = Localize.t(def.key) .. (if def.rare then " ★" else "")
		tile.icon.TextTransparency = if relic then 0 else 0.75
		tile.halo.Visible = relic ~= nil and relic.r
		tile.body.BackgroundColor3 = if relic and relic.r then Color3.fromRGB(def.color[1], def.color[2], def.color[3]):Lerp(PanelKit.CARD, 0.55) else PanelKit.CARD
		tile.stroke.Color = if relic and relic.f > 0 then FRAME_COLOR[relic.f] else OUTLINE
		tile.stroke.Thickness = if relic and relic.f > 0 then 4 else 3
		if not relic then
			local cost = Delve.craftCost(def.id) or 0
			tile.status.Text = Localize.t("DELVE_STATUS_MISSING")
			tile.mode = "craft"
			tile.actionLabel.Text = Localize.t("DELVE_CRAFT", { cost })
			setEnabled(tile.action, tile.actionLabel, save.shards >= cost, Color3.fromRGB(110, 120, 220))
		elseif not relic.r then
			local cost = Delve.restoreCost(def.id) or 0
			tile.status.Text = Localize.t("DELVE_STATUS_DUSTY")
			tile.mode = "restore"
			tile.actionLabel.Text = Localize.t("DELVE_RESTORE", { formatCoins(cost) })
			setEnabled(tile.action, tile.actionLabel, coins >= cost, GREEN)
		elseif relic.f < #Delve.FRAMES then
			local frame = Delve.FRAMES[relic.f + 1]
			tile.status.Text = if relic.f == 0 then Localize.t("DELVE_STATUS_RESTORED") else Localize.t(Delve.FRAMES[relic.f].key)
			tile.mode = "frame"
			tile.actionLabel.Text = Localize.t("DELVE_FRAME", { Localize.t(frame.key) :: any, formatCoins(frame.coins), frame.shards })
			setEnabled(tile.action, tile.actionLabel, coins >= frame.coins and save.shards >= frame.shards, Color3.fromRGB(220, 160, 50))
		else
			tile.status.Text = Localize.t(Delve.FRAMES[#Delve.FRAMES].key)
			tile.mode = ""
			tile.actionLabel.Text = Localize.t("DELVE_DONE")
			setEnabled(tile.action, tile.actionLabel, false, GREEN)
		end
	end
	colFooter.Text = Localize.t("DELVE_COLLECTION_FOOTER")
end

local function cascadeTiles()
	local list: { GuiObject } = {}
	for _, tile in tiles do
		table.insert(list, tile.body)
	end
	ShopLook.openSound()
	ShopLook.cascade(list, 0.03)
end

collectionButton.Activated:Connect(function()
	renderCollection()
	collection.setOpen(true)
	cascadeTiles()
end)

-- ===================== Wejście =====================

local function render()
	if board.isOpen() then
		renderBoard()
	end
	if collection.isOpen() then
		renderCollection()
	end
end

function DelvePanel.setState(payload: any)
	state = payload
	if payload.open == "board" then
		renderBoard()
		board.setOpen(true)
		ShopLook.openSound()
		for i, card in offerCards do
			local existing = card.root:FindFirstChildOfClass("UIScale")
			local scale = if existing then existing else Instance.new("UIScale")
			scale.Parent = card.root
			UiFx.popIn(scale, 1, 0.7, 0.05 * i)
		end
	elseif payload.open == "collection" then
		renderCollection()
		collection.setOpen(true)
		cascadeTiles()
	else
		render()
	end
end

-- Monety z StateUpdate (czy stać na renowację i oprawę)
function DelvePanel.setCoins(value: number)
	if value ~= coins then
		coins = value
		if collection.isOpen() then
			renderCollection()
		end
	end
end

Localize.onChanged(render)
-- Odliczanie czasu zlecenia na tablicy
task.spawn(function()
	while true do
		task.wait(1)
		if board.isOpen() and state and state.run then
			renderBoard()
		end
	end
end)

return DelvePanel
