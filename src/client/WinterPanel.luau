--!strict
-- Okno Zimy (styl PanelKit, jak okno Halloween): płatki śniegu w kieszeni (pigułka), ścieżka nagród
-- za płatki zebrane łącznie (kafelki z progami i pasek), kalendarz adwentowy (24 okienka, otwiera się
-- tylko dzisiejsze), jak zdobywać płatki i skórki do założenia (zimowe i te z Halloween, które gracz ma).
-- Przycisk ❄️ pojawia się z prawej dopiero, gdy serwer włączy Zimę (atrybut Workspace.Winter), więc
-- przed 1 grudnia nic z tego nie widać. Nagrody ze ścieżki przychodzą same (ProgressService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Winter = require(Shared.Winter)
local Skins = require(Shared.Skins)
local Remotes = require(Shared.Remotes)
local Localize = require(script.Parent.Localize)
local PanelKit = require(script.Parent.PanelKit)
local ShopLook = require(script.Parent.ShopLook)
local SideButtons = require(script.Parent.SideButtons)
local UiKit = require(script.Parent.UiKit)

local WinterPanel = {}

local OUTLINE = PanelKit.OUTLINE
local ICE = Color3.fromRGB(70, 150, 220)
local BLUE = Color3.fromRGB(46, 92, 150)
local BLUE_DARK = Color3.fromRGB(28, 56, 96)
local GREEN = Color3.fromRGB(72, 150, 70)
local WIDTH, HEIGHT = 660, 800
local TILE_W, TILE_H, TILE_GAP = 94, 122, 10
local DOOR, DOOR_GAP = 42, 8

local function now(): number
	return Workspace:GetServerTimeNow()
end

-- Zima trwa (serwer ustawia atrybut; zanim go ustawi, liczymy z daty)
local function eventOn(): boolean
	local attr = Workspace:GetAttribute("Winter")
	if typeof(attr) == "boolean" then
		return attr
	end
	return Winter.active(now())
end

-- Dzisiejsze okienko kalendarza (0 = żadne)
local function adventToday(): number
	local attr = Workspace:GetAttribute("AdventDay")
	if typeof(attr) == "number" then
		return attr
	end
	return Winter.adventDay(now()) or 0
end

local window = PanelKit.window({
	name = "Winter",
	parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	width = WIDTH,
	height = HEIGHT,
	ribbon = ICE,
	icon = "snowflake",
	pillIcon = "snowflake",
	pillColor = BLUE_DARK,
})
local content = window.content

local timer = PanelKit.label(content, "Timer", UDim2.new(1, -40, 0, 20), UDim2.fromOffset(20, 2), 17, PanelKit.MUTED)

-- ===== Ścieżka nagród =====

type Tile = { frame: Frame, stroke: UIStroke, need: TextLabel, reward: TextLabel, check: GuiObject, icon: TextLabel, halo: Frame }
local tiles: { Tile } = {}
local track = Winter.TRACK
local rowWidth = #track * TILE_W + (#track - 1) * TILE_GAP
local rowX = math.floor((WIDTH - 28 - rowWidth) / 2)

for index, step in track do
	local frame = Instance.new("Frame")
	frame.Name = "Step" .. index
	frame.Size = UDim2.fromOffset(TILE_W, TILE_H)
	frame.Position = UDim2.fromOffset(rowX + (index - 1) * (TILE_W + TILE_GAP), 32)
	frame.BackgroundColor3 = BLUE
	frame.ZIndex = 4
	frame.Parent = content
	PanelKit.corner(frame, UDim.new(0, 16))
	local tileStroke = PanelKit.stroke(frame, OUTLINE, 3)
	ShopLook.shade(frame)
	ShopLook.hover(frame, 0.04)
	local halo = ShopLook.halo(frame, UDim2.new(0.5, 0, 0, 28), PanelKit.GOLD, 64, true, 5)
	halo.Visible = false
	local icon = PanelKit.label(frame, "Icon", UDim2.new(1, 0, 0, 44), UDim2.fromOffset(0, 6), 38)
	icon.Text = step.icon
	icon.ZIndex = 6
	ShopLook.bob(icon, 2.5, 2 + index * 0.12)
	local need = PanelKit.label(frame, "Need", UDim2.new(1, -8, 0, 22), UDim2.fromOffset(4, 50), 20, Color3.fromRGB(210, 240, 255))
	need.ZIndex = 6
	UiKit.outline(need, 2)
	local reward = PanelKit.label(frame, "Reward", UDim2.new(1, -10, 0, 42), UDim2.fromOffset(5, 74), 15)
	reward.TextWrapped = true
	reward.ZIndex = 6
	UiKit.outline(reward, 1.5)
	local check = UiKit.icon("check", frame, UDim2.fromOffset(30, 30), UDim2.new(1, 6, 0, -6), Vector2.new(1, 0))
	check.ZIndex = 8
	check.Visible = false
	tiles[index] = { frame = frame, stroke = tileStroke, need = need, reward = reward, check = check, icon = icon, halo = halo }
end

local BAR_Y = 32 + TILE_H + 14
local _, fill, barText = PanelKit.bar(content, UDim2.fromOffset(rowWidth, 30), UDim2.fromOffset(rowX, BAR_Y), ICE)

-- Każdy odcinek między progami ma tę samą długość (progi rosną nierówno)
local function trackFraction(flakes: number): number
	local previous = 0
	for index, step in track do
		if flakes < step.flakes then
			local part = (flakes - previous) / math.max(step.flakes - previous, 1)
			return ((index - 1) + part) / #track
		end
		previous = step.flakes
	end
	return 1
end

local SECTION_TOP = Color3.fromRGB(235, 248, 255)
local function sectionTitle(name: string, y: number): TextLabel
	local label = PanelKit.label(content, name, UDim2.new(1, -40, 0, 24), UDim2.fromOffset(20, y), 21, PanelKit.GOLD)
	label.TextXAlignment = Enum.TextXAlignment.Left
	UiKit.outline(label, 2)
	ShopLook.title(label, SECTION_TOP, Color3.fromRGB(150, 210, 255))
	return label
end

-- Ostatni stan od serwera (ProgressUpdate)
local state: any = nil

-- ===== Kalendarz adwentowy =====

local ADVENT_Y = BAR_Y + 30 + 16
local adventTitle = sectionTitle("AdventTitle", ADVENT_Y)
local COLUMNS = 12
local gridWidth = COLUMNS * DOOR + (COLUMNS - 1) * DOOR_GAP
local gridX = math.floor((WIDTH - 28 - gridWidth) / 2)
local AdventOpen = Remotes.get("AdventOpen")

type Door = { frame: TextButton, stroke: UIStroke, number: TextLabel, mark: TextLabel }
local doors: { Door } = {}
for day = 1, #Winter.ADVENT do
	local row = (day - 1) // COLUMNS
	local col = (day - 1) % COLUMNS
	local frame = Instance.new("TextButton")
	frame.Name = "Day" .. day
	frame.Text = ""
	frame.AutoButtonColor = false
	frame.Size = UDim2.fromOffset(DOOR, DOOR)
	frame.Position = UDim2.fromOffset(gridX + col * (DOOR + DOOR_GAP), ADVENT_Y + 30 + row * (DOOR + DOOR_GAP))
	frame.BackgroundColor3 = BLUE_DARK
	frame.ZIndex = 4
	frame.Parent = content
	PanelKit.corner(frame, UDim.new(0, 10))
	local doorStroke = PanelKit.stroke(frame, OUTLINE, 2.5)
	ShopLook.shade(frame)
	local number = PanelKit.label(frame, "Number", UDim2.new(1, -6, 0.6, 0), UDim2.fromOffset(3, 3), 20)
	number.Text = tostring(day)
	number.ZIndex = 6
	UiKit.outline(number, 1.5)
	local mark = PanelKit.label(frame, "Mark", UDim2.new(1, -6, 0.42, 0), UDim2.new(0, 3, 0.56, -2), 14)
	mark.ZIndex = 6
	frame.Activated:Connect(function()
		if day == adventToday() then
			AdventOpen:FireServer()
		end
	end)
	doors[day] = { frame = frame, stroke = doorStroke, number = number, mark = mark }
end

local ADVENT_BUTTON_Y = ADVENT_Y + 30 + 2 * (DOOR + DOOR_GAP) + 4
local openButton = Instance.new("TextButton")
openButton.Name = "OpenToday"
openButton.Size = UDim2.fromOffset(300, 42)
openButton.AnchorPoint = Vector2.new(0.5, 0)
openButton.Position = UDim2.new(0.5, 0, 0, ADVENT_BUTTON_Y)
openButton.Font = PanelKit.TITLE_FONT
openButton.TextScaled = true
openButton.ZIndex = 6
openButton.Parent = content
local openStroke = UiKit.button(openButton, UiKit.COLORS.green, { stroke = 2.5, radius = UDim.new(0, 12) })
openStroke.Color = OUTLINE
ShopLook.button(openButton, 4)
local openConstraint = Instance.new("UITextSizeConstraint")
openConstraint.MaxTextSize = 20
openConstraint.Parent = openButton
openButton.Activated:Connect(function()
	if openButton.Active then
		AdventOpen:FireServer()
	end
end)

-- ===== Jak zdobyć płatki =====

local HOW_Y = ADVENT_BUTTON_Y + 42 + 14
local howTitle = sectionTitle("HowTitle", HOW_Y)
local HOW_KEYS = { "WINTER_HOW_FROST", "WINTER_HOW_QUEST", "WINTER_HOW_TREE" }
local howLines: { TextLabel } = {}
for index in HOW_KEYS do
	local line = PanelKit.label(content, "How" .. index, UDim2.new(1, -40, 0, 34), UDim2.fromOffset(20, HOW_Y + 28 + (index - 1) * 38), 16, PanelKit.TEXT, PanelKit.BODY_FONT)
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.TextWrapped = true
	howLines[index] = line
end

-- ===== Skórki (zimowe i te z Halloween, które gracz ma) =====

local SKINS_Y = HOW_Y + 28 + #HOW_KEYS * 38 + 4
local skinsTitle = sectionTitle("SkinsTitle", SKINS_Y)
type SkinCard = { id: string, slot: string, frame: Frame, name: TextLabel, button: TextButton, icon: TextLabel }
local skinCards: { SkinCard } = {}
local EquipSkin = Remotes.get("EquipSkin")
local cardW = math.floor((WIDTH - 28 - 24 - 12) / 2)
-- Zimowe skórki zawsze (do zdobycia), z innych eventów tylko posiadane: karty w kolejności Skins.ORDER
local winterFirst: { string } = {}
for _, id in Skins.ORDER do
	if Skins.ALL[id].event == "winter" then
		table.insert(winterFirst, id)
	end
end
for _, id in Skins.ORDER do
	if Skins.ALL[id].event ~= "winter" then
		table.insert(winterFirst, id)
	end
end
for index, id in winterFirst do
	local def = Skins.ALL[id]
	local row = (index - 1) // 2
	local col = (index - 1) % 2
	local frame = Instance.new("Frame")
	frame.Name = "Skin_" .. id
	frame.Size = UDim2.fromOffset(cardW, 56)
	frame.Position = UDim2.fromOffset(12 + col * (cardW + 12), SKINS_Y + 28 + row * 64)
	frame.BackgroundColor3 = BLUE_DARK
	frame.ZIndex = 4
	frame.Parent = content
	PanelKit.corner(frame, UDim.new(0, 16))
	PanelKit.stroke(frame, OUTLINE, 3)
	ShopLook.shade(frame)
	ShopLook.hover(frame, 0.03)
	local skinIcon = PanelKit.label(frame, "Icon", UDim2.fromOffset(44, 44), UDim2.fromOffset(8, 6), 36)
	skinIcon.Text = def.icon
	skinIcon.ZIndex = 6
	ShopLook.bob(skinIcon, 3, 2.4 + index * 0.3)
	local name = PanelKit.label(frame, "Name", UDim2.new(1, -170, 1, -12), UDim2.fromOffset(56, 6), 18)
	name.TextXAlignment = Enum.TextXAlignment.Left
	-- Jedna linia: długa nazwa („Jack-o'-Lantern”) zmniejsza się zamiast łamać w środku słowa
	name.TextWrapped = false
	name.ZIndex = 6
	UiKit.outline(name, 2)
	local button = Instance.new("TextButton")
	button.Name = "Equip"
	button.Size = UDim2.fromOffset(104, 38)
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -10, 0.5, 0)
	button.Font = PanelKit.TITLE_FONT
	button.TextScaled = true
	button.ZIndex = 6
	button.Parent = frame
	local buttonStroke = UiKit.button(button, UiKit.COLORS.green, { stroke = 2.5, radius = UDim.new(0, 12) })
	buttonStroke.Color = OUTLINE
	ShopLook.button(button, 3 + index * 0.5)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 17
	constraint.Parent = button
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = button
	local card: SkinCard = { id = id, slot = def.slot, frame = frame, name = name, button = button, icon = skinIcon }
	button.Activated:Connect(function()
		if not state or not button.Active then
			return
		end
		local equipped = state.equipped and state.equipped[card.slot]
		EquipSkin:FireServer(card.slot, if equipped == card.id then "" else card.id)
	end)
	table.insert(skinCards, card)
end

-- ===== Stan =====

local side: SideButtons.Side? = nil

local function formatCoins(value: number): string
	local s = tostring(math.floor(value + 0.5))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (formatted:gsub("^ ", ""))
end

local function formatLeft(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 86400 then
		return Localize.t("HW_TIME_DAYS", { seconds // 86400, seconds // 3600 % 24 })
	elseif seconds >= 3600 then
		return Localize.t("HW_TIME_HOURS", { seconds // 3600, seconds // 60 % 60 })
	end
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- Płatki zebrane łącznie (ścieżka nagród) i w kieszeni (na choinkę)
local function flakesOf(): number
	local stats = state and state.stats
	return if stats and typeof(stats.snowflakes) == "number" then stats.snowflakes else 0
end

local function bagOf(): number
	return if state and typeof(state.flakeBag) == "number" then state.flakeBag else 0
end

local function opened(): { number }
	return if state and typeof(state.advent) == "table" then state.advent else {}
end

local function rewardText(step: any): string
	if step.kind == "title" and step.id then
		return Localize.t("HW_REWARD_TITLE", { Localize.t(step.id) })
	elseif step.kind == "luck" and step.seconds then
		return Localize.t("HW_REWARD_LUCK", { math.floor(step.seconds / 60) })
	elseif step.kind == "coins" and step.scale then
		local scale = if state and typeof(state.scale) == "number" then state.scale else 50
		return Localize.t("HW_REWARD_COINS", { formatCoins(step.scale * scale) })
	elseif step.kind == "skin" and step.id then
		local skin = Winter.getSkin(step.id)
		return if skin then Localize.t(skin.key) else "?"
	end
	return ""
end

local function renderAdvent()
	adventTitle.Text = Localize.t("ADVENT_TITLE", { #opened(), Config.Winter.adventTitle })
	local today = adventToday()
	local list = opened()
	-- Po Wigilii (dzisiaj = 0, a kalendarz już się zaczął) nieotwarte okienka przepadły
	local over = today == 0 and now() >= Config.Winter.startsAt
	for day, door in doors do
		local isOpen = table.find(list, day) ~= nil
		local isToday = day == today
		local missed = not isOpen and ((today > 0 and day < today) or over)
		door.frame.BackgroundColor3 = if isOpen then GREEN elseif isToday then Color3.fromRGB(214, 60, 70) elseif missed then Color3.fromRGB(70, 70, 84) else BLUE_DARK
		door.stroke.Color = if isToday and not isOpen then PanelKit.GOLD else OUTLINE
		door.stroke.Thickness = if isToday and not isOpen then 4 else 2.5
		door.number.TextTransparency = if missed then 0.5 else 0
		door.mark.Text = if isOpen then "✔" elseif isToday then "🎁" elseif missed then "✖" else ""
	end
	local reward = if today > 0 then Winter.ADVENT[today] else nil
	local canOpen = reward ~= nil and table.find(list, today) == nil
	openButton.Active = canOpen
	if canOpen then
		openButton.Text = Localize.t("ADVENT_OPEN", { today })
		UiKit.recolor(openButton, UiKit.COLORS.green)
	elseif today > 0 and today < #Winter.ADVENT then
		openButton.Text = Localize.t("ADVENT_NEXT", { formatLeft(Winter.secondsToNextDay(now())) })
		UiKit.recolor(openButton, UiKit.COLORS.locked)
	elseif today == 0 and now() < Config.Winter.startsAt then
		openButton.Text = Localize.t("ADVENT_SOON")
		UiKit.recolor(openButton, UiKit.COLORS.locked)
	else
		openButton.Text = Localize.t("ADVENT_DONE")
		UiKit.recolor(openButton, UiKit.COLORS.locked)
	end
end

local function renderSkins()
	skinsTitle.Text = Localize.t("WINTER_SKINS_TITLE")
	local owned = if state and typeof(state.skins) == "table" then state.skins else {}
	local equipped = if state and typeof(state.equipped) == "table" then state.equipped else {}
	local visible = 0
	for _, card in skinCards do
		local def = Skins.ALL[card.id]
		local has = table.find(owned, card.id) ~= nil
		local on = equipped[card.slot] == card.id
		-- Skórki z innych eventów: tylko te, które gracz już ma
		local show = has or def.event == "winter"
		card.frame.Visible = show
		if show then
			local row = visible // 2
			local col = visible % 2
			card.frame.Position = UDim2.fromOffset(12 + col * (cardW + 12), SKINS_Y + 28 + row * 64)
			visible += 1
		end
		card.name.Text = Localize.t(def.key)
		card.name.TextTransparency = if has then 0 else 0.35
		card.frame.BackgroundColor3 = if on then GREEN elseif has then BLUE else BLUE_DARK
		card.button.Active = has
		if has then
			card.button.Text = Localize.t(if on then "HW_SKIN_OFF" else "HW_SKIN_ON")
			UiKit.recolor(card.button, if on then Color3.fromRGB(236, 168, 32) else UiKit.COLORS.green)
		else
			local need = Winter.trackFlakesFor(card.id)
			card.button.Text = if need then Localize.t("WINTER_SKIN_LOCKED", { need }) else "🔒"
			UiKit.recolor(card.button, UiKit.COLORS.locked)
		end
	end
end

local function renderTimer()
	timer.Text = if eventOn()
		then Localize.t("WINTER_ENDS", { formatLeft(Winter.secondsLeft(now())) })
		else Localize.t("WINTER_ENDED")
end

local lastReached = -1

local function render()
	window.title.Text = Localize.t("WINTER_TITLE")
	local flakes = flakesOf()
	window.pillText.Text = tostring(bagOf())
	renderTimer()
	local reached = Winter.reached(flakes)
	for index, tile in tiles do
		local step = track[index]
		local done = index <= reached
		local nextOne = index == reached + 1
		tile.need.Text = string.format("%d ❄️", step.flakes)
		local text = rewardText(step)
		if step.flakes == Config.Winter.badgeFlakes then
			text ..= "\n" .. Localize.t("HW_REWARD_BADGE")
		end
		tile.reward.Text = text
		tile.check.Visible = done
		tile.frame.BackgroundColor3 = if done then GREEN elseif nextOne then Color3.fromRGB(70, 140, 210) else BLUE
		tile.stroke.Color = if nextOne then PanelKit.GOLD else OUTLINE
		tile.stroke.Thickness = if nextOne then 4 else 3
		tile.halo.Visible = nextOne
	end
	fill.Size = UDim2.fromScale(math.clamp(trackFraction(flakes), 0, 1), 1)
	local nextStep = track[reached + 1]
	barText.Text = if nextStep then Localize.t("WINTER_TRACK_PROGRESS", { flakes, nextStep.flakes }) else Localize.t("WINTER_TRACK_DONE", { flakes })
	if lastReached >= 0 and reached > lastReached and window.isOpen() then
		local tile = tiles[reached]
		if tile then
			UiKit.burst(window.gui, tile.frame.AbsolutePosition + tile.frame.AbsoluteSize / 2, 16, { Color3.fromRGB(255, 255, 255), PanelKit.GOLD, ICE })
		end
	end
	lastReached = reached

	howTitle.Text = Localize.t("WINTER_HOW_TITLE")
	local byWorld = Config.Winter.flakesByWorld
	howLines[1].Text = Localize.t("WINTER_HOW_FROST", { byWorld.forest, byWorld.cave, byWorld.swamp, byWorld.mountain })
	howLines[2].Text = Localize.t("WINTER_HOW_QUEST", { Config.Winter.questFlakes })
	howLines[3].Text = Localize.t("WINTER_HOW_TREE", { Config.Winter.tree.cost })
	renderAdvent()
	renderSkins()
end

-- Na przycisku: płatki w kieszeni, a gdy dzisiejsze okienko czeka: wykrzyknik
local function refreshBadge()
	if not side then
		return
	end
	local today = adventToday()
	if today > 0 and Winter.ADVENT[today] and table.find(opened(), today) == nil then
		side.setBadge("🎁", "alert")
		side.setAttention(true)
	else
		side.setBadge(tostring(bagOf()) .. "❄️", "info")
		side.setAttention(false)
	end
end

function WinterPanel.toggle()
	window.setOpen(not window.isOpen())
end

window.onToggle(function(open: boolean)
	if open then
		render()
		ShopLook.openSound()
		local items: { GuiObject } = {}
		for _, tile in tiles do
			table.insert(items, tile.frame)
		end
		for _, door in doors do
			table.insert(items, door.frame)
		end
		ShopLook.cascade(items, 0.015)
	end
end)

-- Przycisk dopiero, gdy Zima się zacznie (albo w podglądzie z panelu DEV); zostaje do końca sesji
local function ensureButton()
	if side or not eventOn() then
		return
	end
	local button = SideButtons.add({
		name = "WinterButton",
		icon = "snowflake",
		color = ICE,
		caption = "WINTER_BUTTON",
		key = Enum.KeyCode.H,
	})
	button.onActivated(WinterPanel.toggle)
	side = button
	refreshBadge()
end
ensureButton()
Workspace:GetAttributeChangedSignal("Winter"):Connect(ensureButton)
Workspace:GetAttributeChangedSignal("AdventDay"):Connect(function()
	refreshBadge()
	if window.isOpen() then
		renderAdvent()
	end
end)

Remotes.get("ProgressUpdate").OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	local before = #opened()
	state = payload
	refreshBadge()
	if window.isOpen() then
		render()
		-- Właśnie otwarte okienko: iskry nad nim
		local list = opened()
		if #list > before then
			local door = doors[list[#list]]
			if door then
				UiKit.burst(window.gui, door.frame.AbsolutePosition + door.frame.AbsoluteSize / 2, 14, { Color3.fromRGB(255, 255, 255), PanelKit.GOLD, Color3.fromRGB(255, 90, 90) })
			end
		end
	end
end)

Localize.onChanged(function()
	if window.isOpen() then
		render()
	end
end)

task.spawn(function()
	while true do
		task.wait(1)
		if window.isOpen() then
			renderTimer()
			renderAdvent()
		end
	end
end)

return WinterPanel
