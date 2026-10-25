--!strict
-- Sklep za Robuxy i wszystko, co z nim związane na ekranie:
--   przycisk 🛒 pod przełącznikiem języka i panel z kartami (Wysyp, mikstura, olej, suszenie),
--   szybki przycisk „+olej” przy pasku oleju, gdy w lesie robi się ciemno,
--   przycisk „Zachowaj grzyby” na czarnym ekranie po zgaśnięciu latarni lub złapaniu,
--   liczniki działającego Wysypu i mikstury szczęścia.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Localize = require(script.Parent.Localize)
local OddsPanel = require(script.Parent.OddsPanel)
local Purchases = require(script.Parent.Purchases)
local UiKit = require(script.Parent.UiKit)
local UiScale = require(script.Parent.UiScale)

local ShopPanel = {}

local player = Players.LocalPlayer
local TITLE_FONT = Enum.Font.FredokaOne
local BODY_FONT = Enum.Font.GothamBold
local PANEL = Color3.fromRGB(40, 28, 20)
local STROKE = Color3.fromRGB(200, 146, 74)
local TEXT = Color3.fromRGB(252, 238, 210)
local MUTED = Color3.fromRGB(214, 188, 150)
local BUY = Color3.fromRGB(70, 160, 70)
local ROBUX_GREEN = Color3.fromRGB(0, 176, 111)
-- Ikona z arkusza UiKit dla każdego produktu
local PRODUCT_ICONS = { rescue = "rescue", boom = "boom", oil = "bottle", harvest = "sell", luck = "luck" }

local gui = Instance.new("ScreenGui")
gui.Name = "Shop"
gui.ResetOnSpawn = false
gui.DisplayOrder = 4
gui.Parent = player:WaitForChild("PlayerGui")

-- Ratunek musi być nad czarnym ekranem HUD (DisplayOrder wyżej i bez wcięcia na pasek Robloxa)
local rescueGui = Instance.new("ScreenGui")
rescueGui.Name = "Rescue"
rescueGui.ResetOnSpawn = false
rescueGui.DisplayOrder = 30
rescueGui.IgnoreGuiInset = true
rescueGui.Parent = player:WaitForChild("PlayerGui")

local function corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 10)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3?, thickness: number?)
	local s = Instance.new("UIStroke")
	s.Color = color or STROKE
	s.Thickness = thickness or 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

local function text(parent: Instance, name: string, size: UDim2, position: UDim2, font: Enum.Font, maxSize: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = size
	l.Position = position
	l.BackgroundTransparency = 1
	l.TextColor3 = TEXT
	l.Font = font
	l.TextScaled = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = maxSize
	c.Parent = l
	return l
end

-- ===== Przycisk i panel sklepu =====

local shopButton = Instance.new("TextButton")
shopButton.Name = "ShopButton"
shopButton.Size = UDim2.fromOffset(70, 30)
shopButton.Text = ""
shopButton.Parent = gui
UiKit.button(shopButton, ROBUX_GREEN, { gloss = true })
UiKit.icon("shop", shopButton, UDim2.fromOffset(30, 30), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.55))
local shopButtonScale = shopButton:FindFirstChildOfClass("UIScale") :: UIScale

local panel = Instance.new("Frame")
panel.Name = "ShopPanel"
panel.Size = UDim2.fromOffset(360, 60 + #Config.ShopOrder * 72)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.BackgroundColor3 = PANEL
panel.BackgroundTransparency = 0.05
panel.Visible = false
panel.Parent = gui
corner(panel, 14)
stroke(panel)
local panelScale = Instance.new("UIScale")
panelScale.Parent = panel

local title = text(panel, "Title", UDim2.new(1, -150, 0, 36), UDim2.fromOffset(16, 10), TITLE_FONT, 26)
title.TextColor3 = Color3.fromRGB(255, 214, 120)
local close = Instance.new("TextButton")
close.Size = UDim2.fromOffset(32, 32)
close.Position = UDim2.new(1, -42, 0, 10)
close.Text = ""
close.Parent = panel
UiKit.button(close, UiKit.COLORS.wood, { gloss = true, radius = UDim.new(0, 8) })
UiKit.icon("close", close, UDim2.fromOffset(22, 22), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))

-- „Szanse”: tabelka prawdziwych procentów na mutacje (mikstura i Wysyp są płatne, więc szanse są jawne)
local oddsButton = Instance.new("TextButton")
oddsButton.Name = "Odds"
oddsButton.Size = UDim2.fromOffset(84, 32)
oddsButton.Position = UDim2.new(1, -134, 0, 10)
oddsButton.Font = TITLE_FONT
oddsButton.TextScaled = true
oddsButton.Parent = panel
UiKit.button(oddsButton, UiKit.COLORS.wood, { radius = UDim.new(0, 8) })
local oddsPad = Instance.new("UIPadding")
oddsPad.PaddingTop = UDim.new(0, 6)
oddsPad.PaddingBottom = UDim.new(0, 6)
oddsPad.Parent = oddsButton
oddsButton.Activated:Connect(OddsPanel.toggle)

type Card = { frame: Frame, title: TextLabel, desc: TextLabel, buy: TextButton, key: string }
local cards: { Card } = {}

for index, key in Config.ShopOrder do
	local frame = Instance.new("Frame")
	frame.Name = "Card_" .. key
	frame.Size = UDim2.new(1, -24, 0, 64)
	frame.Position = UDim2.new(0, 12, 0, 52 + (index - 1) * 72)
	frame.BackgroundColor3 = Color3.fromRGB(64, 46, 32)
	frame.Parent = panel
	corner(frame)
	stroke(frame, Color3.fromRGB(110, 80, 52), 1.5)
	UiKit.icon(PRODUCT_ICONS[key] or "boom", frame, UDim2.fromOffset(50, 50), UDim2.fromOffset(6, 7))
	local cardTitle = text(frame, "Title", UDim2.new(1, -170, 0, 24), UDim2.fromOffset(60, 8), TITLE_FONT, 20)
	local desc = text(frame, "Desc", UDim2.new(1, -170, 0, 26), UDim2.fromOffset(60, 32), BODY_FONT, 13)
	desc.TextColor3 = MUTED
	desc.TextWrapped = true
	local buy = Instance.new("TextButton")
	buy.Name = "Buy"
	buy.Size = UDim2.fromOffset(92, 40)
	buy.Position = UDim2.new(1, -102, 0, 12)
	buy.Font = TITLE_FONT
	buy.TextScaled = true
	buy.Parent = frame
	UiKit.button(buy, BUY)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = buy
	buy.Activated:Connect(function()
		Purchases.buy(key)
	end)
	table.insert(cards, { frame = frame, title = cardTitle, desc = desc, buy = buy, key = key })
end

-- ===== Szybki olej przy pasku oleju =====

local oilButton = Instance.new("TextButton")
oilButton.Name = "QuickOil"
oilButton.Size = UDim2.fromOffset(86, 30)
oilButton.AnchorPoint = Vector2.new(0, 0)
oilButton.Font = TITLE_FONT
oilButton.TextScaled = true
oilButton.Visible = false
oilButton.Parent = gui
UiKit.button(oilButton, ROBUX_GREEN)
UiKit.icon("bottle", oilButton, UDim2.fromOffset(28, 28), UDim2.new(0, -26, 0.5, 0), Vector2.new(0, 0.5))
local oilPad = Instance.new("UIPadding")
oilPad.PaddingLeft = UDim.new(0, 30)
oilPad.PaddingRight = UDim.new(0, 6)
oilPad.PaddingTop = UDim.new(0, 5)
oilPad.PaddingBottom = UDim.new(0, 5)
oilPad.Parent = oilButton
local oilScale = oilButton:FindFirstChildOfClass("UIScale") :: UIScale
oilButton.Activated:Connect(function()
	Purchases.buy("oil")
end)

-- ===== Liczniki Wysypu i mikstury =====

local timers = Instance.new("Frame")
timers.Name = "Timers"
timers.Size = UDim2.fromOffset(170, 64)
timers.BackgroundTransparency = 1
timers.Parent = gui
local timersScale = Instance.new("UIScale")
timersScale.Parent = timers
local timerLayout = Instance.new("UIListLayout")
timerLayout.Padding = UDim.new(0, 4)
timerLayout.Parent = timers

local function timerPill(name: string, color: Color3, iconName: string): TextLabel
	local pill = Instance.new("TextLabel")
	pill.Name = name
	pill.Size = UDim2.fromOffset(170, 28)
	pill.BackgroundColor3 = PANEL
	pill.BackgroundTransparency = 0.15
	pill.TextColor3 = color
	pill.Font = TITLE_FONT
	pill.TextScaled = true
	pill.Visible = false
	pill.Parent = timers
	corner(pill, 8)
	stroke(pill, color, 1.5)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.PaddingLeft = UDim.new(0, 30)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = pill
	UiKit.icon(iconName, pill, UDim2.fromOffset(26, 26), UDim2.new(0, -28, 0.5, 0), Vector2.new(0, 0.5))
	return pill
end
local boomPill = timerPill("Boom", Color3.fromRGB(255, 200, 120), "boom")
local luckPill = timerPill("Luck", Color3.fromRGB(150, 255, 150), "luck")

-- ===== Ratunek koszyka =====

local rescue = Instance.new("TextButton")
rescue.Name = "RescueButton"
rescue.Size = UDim2.fromOffset(340, 64)
rescue.AnchorPoint = Vector2.new(0.5, 0)
rescue.Position = UDim2.new(0.5, 0, 0.58, 0)
rescue.Font = TITLE_FONT
rescue.TextScaled = true
rescue.RichText = true
rescue.Visible = false
rescue.Parent = rescueGui
local rescueStroke = UiKit.button(rescue, ROBUX_GREEN, { radius = UDim.new(0, 14), stroke = 4 })
rescueStroke.Color = Color3.fromRGB(200, 255, 220)
UiKit.icon("rescue", rescue, UDim2.fromOffset(54, 54), UDim2.new(0, -58, 0.5, 0), Vector2.new(0, 0.5))
local rescuePad = Instance.new("UIPadding")
rescuePad.PaddingTop = UDim.new(0, 8)
rescuePad.PaddingBottom = UDim.new(0, 8)
rescuePad.PaddingLeft = UDim.new(0, 64)
rescuePad.PaddingRight = UDim.new(0, 12)
rescuePad.Parent = rescue
local rescueScale = rescue:FindFirstChildOfClass("UIScale") :: UIScale
rescue.Activated:Connect(function()
	Purchases.buy("rescue")
end)

local rescueToken = 0
local rescueValue = 0
local rescueEnds = 0

-- ===== Logika =====

local boomUntil = 0
local luckUntil = 0
local oilFraction = 1
local inDanger = false

local function formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function formatCoins(value: number): string
	local s = tostring(math.floor(value + 0.5))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (formatted:gsub("^ ", ""))
end

-- Czy coś rośnie we własnym ogródku (wtedy karta „zbiory od razu” jest aktywna)
local function hasPlanted(): boolean
	for _, rack in CollectionService:GetTagged("GardenPlot") do
		if rack:GetAttribute("OwnerUserId") == player.UserId then
			local count = rack:GetAttribute("Count")
			return typeof(count) == "number" and count > 0
		end
	end
	return false
end

local function refreshTexts()
	title.Text = Localize.t("SHOP_TITLE")
	oddsButton.Text = "% " .. Localize.t("SHOP_ODDS")
	oilButton.Text = Purchases.priceText("oil")
	local anyCard = false
	local visibleIndex = 0
	for _, card in cards do
		local available = Purchases.available(card.key)
		card.frame.Visible = available
		if available then
			anyCard = true
			card.frame.Position = UDim2.new(0, 12, 0, 52 + visibleIndex * 72)
			visibleIndex += 1
		end
		local def = Config.Products[card.key]
		card.title.Text = Localize.t(def.key)
		card.desc.Text = Localize.t(def.key .. "_DESC")
		local enabled = card.key ~= "harvest" or hasPlanted()
		card.buy.Text = Purchases.priceText(card.key)
		card.buy.Active = enabled
		UiKit.recolor(card.buy, if enabled then BUY else UiKit.COLORS.locked)
	end
	panel.Size = UDim2.fromOffset(360, 60 + visibleIndex * 72)
	shopButton.Visible = anyCard
end

local function layout()
	local scale = UiScale.get()
	for _, s in { shopButtonScale, panelScale, oilScale, timersScale, rescueScale } do
		s:SetAttribute("Base", scale) -- UiKit wraca do tej skali po wciśnięciu
		s.Scale = scale
	end
	-- Pod przyciskiem języka (ten sam rachunek co w Hud.layout); panel DEV jest jeszcze niżej
	local y = 8 + math.floor(80 * scale) + 8 + math.floor(30 * scale) + 6
	shopButton.Position = UDim2.fromOffset(12, y)
	timers.Position = UDim2.fromOffset(12, y + math.floor(36 * scale) * 2 + 6)
	-- Obok paska oleju (środek u góry, pasek ma 300 px szerokości)
	oilButton.Position = UDim2.new(0.5, math.floor(156 * scale), 0, 8 + math.floor(34 * scale))
end
UiScale.onChanged(layout)

function ShopPanel.update(state: any, safeZone: boolean)
	OddsPanel.update(state)
	boomUntil = state.boomUntil or 0
	luckUntil = state.luckUntil or 0
	oilFraction = if state.oilMax and state.oilMax > 0 then state.oil / state.oilMax else 1
	inDanger = not safeZone
	oilButton.Visible = Purchases.available("oil") and inDanger and oilFraction < 0.4
end

-- Na czarnym ekranie: „Zachowaj grzyby (wartość) za R$”, przez kilka sekund z odliczaniem
function ShopPanel.offerRescue(value: number, seconds: number)
	if not Purchases.available("rescue") or value <= 0 then
		return
	end
	rescueToken += 1
	local token = rescueToken
	rescueValue = value
	rescueEnds = os.clock() + seconds
	rescue.Visible = true
	rescue.Size = UDim2.fromOffset(340, 64)
	TweenService:Create(rescue, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(380, 72) }):Play()
	task.delay(seconds, function()
		if rescueToken == token then
			rescue.Visible = false
		end
	end)
end

function ShopPanel.hideRescue()
	rescueToken += 1
	rescue.Visible = false
end

shopButton.Activated:Connect(function()
	panel.Visible = not panel.Visible
	refreshTexts()
end)
close.Activated:Connect(function()
	panel.Visible = false
end)
Localize.onChanged(refreshTexts)
refreshTexts()

-- Liczniki i odliczanie ratunku raz na ułamek sekundy
task.spawn(function()
	while true do
		local now = os.time()
		boomPill.Visible = boomUntil > now
		if boomPill.Visible then
			boomPill.Text = Localize.t("SHOP_BOOM_TIMER", { formatTime(boomUntil - now) })
		end
		luckPill.Visible = luckUntil > now
		if luckPill.Visible then
			luckPill.Text = Localize.t("SHOP_LUCK_TIMER", { formatTime(luckUntil - now) })
		end
		if rescue.Visible then
			local left = math.max(0, math.ceil(rescueEnds - os.clock()))
			rescue.Text = string.format(
				"%s  <font color=\"#FFF6C0\">%s 💰</font>  %s  (%d)",
				Localize.t("SHOP_RESCUE"),
				formatCoins(rescueValue),
				Purchases.priceText("rescue"),
				left
			)
		end
		if panel.Visible then
			refreshTexts()
		end
		task.wait(0.25)
	end
end)

return ShopPanel
