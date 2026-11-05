--!strict
-- x2 skrzyni w ogródku (Config.ChestX2) po stronie gracza:
--   * okno „Witaj z powrotem” po wejściu, gdy skrzynia zarobiła pod nieobecność dość na ofertę (decyduje
--     serwer): zielone „Odbierz” (też X i kliknięcie obok) albo mieniące się „Odbierz x2” (odbiera i od
--     razu otwiera okno zakupu Robloxa). x2 podwaja tylko zarobek z nieobecności.
--   * plakietka „x2 [G]” nad własną skrzynią, gdy w skrzyni jest dość na ofertę (G = odbierz i kup x2)
--   * karta po odbiorze monet przy skrzyni (F): „OK” albo „Odbierz x2”. Najwyżej co Config.ChestX2.cardCooldown,
--     po kilku odmowach z rzędu koniec na sesję, da się ją wyłączyć („Nie pokazuj po odbiorze”) i znika,
--     gdy gracz odejdzie od skrzyni. Bez przyciemnienia i bez blokowania chodzenia.
-- Okno zakupu Robloxa otwieramy zawsze dopiero po kliknięciu albo klawiszu gracza.
-- Wygląd jak makiety w Figmie („Midnight Mushroom Hunt – Sklep i x2”).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local BillboardGuard = require(script.Parent.BillboardGuard)
local CutsceneKit = require(script.Parent.CutsceneKit)
local Localize = require(script.Parent.Localize)
local PanelKit = require(script.Parent.PanelKit)
local ShopLook = require(script.Parent.ShopLook)
local Purchases = require(script.Parent.Purchases)
local UiFx = require(script.Parent.UiFx)
local UiKit = require(script.Parent.UiKit)

local ChestOffers = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local ChestOffer = Remotes.get("ChestOffer")
local ChestClaim = Remotes.get("ChestClaim")
local SaveSettings = Remotes.get("SaveSettings")

local GOLD_TOP = Color3.fromRGB(255, 226, 122)
local AMBER = Color3.fromRGB(240, 150, 40)
local GREEN = UiKit.COLORS.green
local DARK = PanelKit.BG_DARK
local CARD_AWAY = 16 -- dalej od skrzyni (studs) = karta znika

-- ===== Liczby =====

local function spaced(value: number): string
	local s = tostring(math.floor(value + 0.5))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (formatted:gsub("^ ", ""))
end

-- Krótko: 1,2 mln / 184 tys. (PL) albo 1.2M / 184K (EN)
local function short(value: number): string
	local pl = Localize.getLocale() == "pl"
	local function one(x: number, suffix: string): string
		local text = if x < 10 then string.format("%.1f", x) else tostring(math.floor(x))
		text = text:gsub("%.0$", "")
		if pl then
			text = text:gsub("%.", ",")
		end
		return text .. suffix
	end
	if value >= 1e9 then
		return one(value / 1e9, if pl then " mld" else "B")
	elseif value >= 1e6 then
		return one(value / 1e6, if pl then " mln" else "M")
	elseif value >= 1e4 then
		return tostring(math.floor(value / 1e3)) .. (if pl then " tys." else "K")
	end
	return spaced(value)
end

local function duration(minutes: number): string
	local total = math.max(1, math.floor(minutes + 0.5))
	local hours = total // 60
	local rest = total % 60
	if hours == 0 then
		return rest .. " min"
	elseif rest == 0 then
		return hours .. " h"
	end
	return hours .. " h " .. rest .. " min"
end

-- ===== Klocki interfejsu =====

local function label(parent: Instance, size: UDim2, position: UDim2, maxSize: number, color: Color3, font: Enum.Font?, outline: number?): TextLabel
	local l = PanelKit.label(parent, "Label", size, position, maxSize, color, font)
	l.ZIndex = 5
	if outline then
		UiKit.outline(l, outline)
	end
	return l
end

local function round(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

-- Pas światła przesuwający się po przycisku co kilka sekund (przycisk przycina go do swoich krawędzi)
local function shimmer(button: GuiObject, every: number)
	button.ClipsDescendants = true
	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.BackgroundColor3 = Color3.new(1, 1, 1)
	shine.BorderSizePixel = 0
	shine.Size = UDim2.new(0.3, 0, 2.4, 0)
	shine.AnchorPoint = Vector2.new(0.5, 0.5)
	shine.Position = UDim2.fromScale(-0.4, 0.5)
	shine.Rotation = 25
	shine.ZIndex = 9
	shine.Active = false
	shine.Parent = button
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.45, 0.45),
		NumberSequenceKeypoint.new(0.55, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	fade.Parent = shine
	task.spawn(function()
		while shine.Parent do
			if button.Visible and button:IsDescendantOf(playerGui) then
				shine.Position = UDim2.fromScale(-0.4, 0.5)
				TweenService:Create(shine, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromScale(1.4, 0.5) }):Play()
			end
			task.wait(0.7 + every)
		end
	end)
end

-- Dwuliniowy przycisk: duży napis i podpis pod nim
type BigButton = { button: TextButton, title: TextLabel, sub: TextLabel }
local function bigButton(parent: Instance, size: UDim2, position: UDim2, premium: boolean): BigButton
	local button = Instance.new("TextButton")
	button.Name = if premium then "ClaimX2" else "Claim"
	button.Size = size
	button.Position = position
	button.Text = ""
	button.ZIndex = 4
	button.Parent = parent
	local stroke = UiKit.button(button, if premium then Color3.new(1, 1, 1) else GREEN, { gloss = true, radius = UDim.new(0, 16), stroke = 3 })
	stroke.Color = PanelKit.OUTLINE
	local titleColor = if premium then DARK else PanelKit.TEXT
	local title = label(button, UDim2.new(1, -16, 0.55, 0), UDim2.new(0, 8, 0.06, 0), 26, titleColor, PanelKit.TITLE_FONT, if premium then nil else 2.5)
	local sub = label(button, UDim2.new(1, -16, 0.3, 0), UDim2.new(0, 8, 0.62, 0), 15, if premium then DARK else Color3.new(1, 1, 1), PanelKit.BODY_FONT)
	if premium then
		-- Złoto przechodzące w bursztyn, delikatna poświata za przyciskiem i pas światła
		local shade = button:FindFirstChild("Shade")
		if shade and shade:IsA("UIGradient") then
			shade.Color = ColorSequence.new(GOLD_TOP, AMBER)
		end
		-- Poświata: pulsująca złota ramka pod przyciskiem (przycisk ma już swój UIStroke)
		local halo = Instance.new("Frame")
		halo.Name = "Halo"
		halo.BackgroundColor3 = PanelKit.GOLD
		halo.BackgroundTransparency = 0.6
		halo.Size = size + UDim2.fromOffset(14, 14)
		halo.Position = position - UDim2.fromOffset(7, 7)
		halo.ZIndex = 3
		halo.Parent = parent
		round(halo, 22)
		TweenService:Create(halo, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0.85 }):Play()
		button:GetPropertyChangedSignal("Visible"):Connect(function()
			halo.Visible = button.Visible
		end)
		shimmer(button, 2.2)
	end
	return { button = button, title = title, sub = sub }
end

-- Fioletowa naklejka „x2” na rogu złotego przycisku
local function sticker(parent: Instance, position: UDim2): Frame
	local s = Instance.new("Frame")
	s.Name = "Sticker"
	s.Size = UDim2.fromOffset(44, 44)
	s.Position = position
	s.Rotation = -10
	s.BackgroundColor3 = PanelKit.VIOLET
	s.ZIndex = 8
	s.Parent = parent
	round(s, 22)
	local stroke = Instance.new("UIStroke")
	stroke.Color = PanelKit.OUTLINE
	stroke.Thickness = 3
	stroke.Parent = s
	local l = label(s, UDim2.fromScale(0.8, 0.6), UDim2.fromScale(0.1, 0.2), 20, PanelKit.TEXT, PanelKit.TITLE_FONT, 2.5)
	l.Text = "x2"
	l.ZIndex = 9
	return s
end

-- ===== Okno „Witaj z powrotem” =====

local welcome = PanelKit.window({
	name = "WelcomeBack",
	parent = playerGui,
	width = 460,
	height = 300,
	ribbon = PanelKit.VIOLET,
	icon = "moon",
	displayOrder = 9,
})
local wFrame = welcome.frame
-- Za skrzynią złote promienie i poświata, skrzynia się kołysze (jak karty sklepu)
ShopLook.halo(wFrame, UDim2.fromOffset(92, 126), PanelKit.GOLD, 150, true, 3)
local chestIcon = UiKit.icon("chest", wFrame, UDim2.fromOffset(128, 128), UDim2.fromOffset(28, 62))
chestIcon.ZIndex = 4
ShopLook.bob(chestIcon, 4, 2.2)

local awayPill = Instance.new("Frame")
awayPill.Name = "Away"
awayPill.Size = UDim2.fromOffset(250, 28)
awayPill.Position = UDim2.fromOffset(172, 40)
awayPill.BackgroundColor3 = Color3.fromRGB(52, 38, 30)
awayPill.ZIndex = 4
awayPill.Parent = wFrame
round(awayPill, 14)
local awayIcon = UiKit.icon("moon", awayPill, UDim2.fromOffset(26, 26), UDim2.new(0, 4, 0.5, 0), Vector2.new(0, 0.5))
awayIcon.ZIndex = 5
local awayText = label(awayPill, UDim2.new(1, -40, 1, -8), UDim2.fromOffset(34, 4), 15, PanelKit.GREEN, PanelKit.BODY_FONT)
awayText.TextXAlignment = Enum.TextXAlignment.Left

local earnedTitle = label(wFrame, UDim2.fromOffset(264, 20), UDim2.fromOffset(174, 76), 15, PanelKit.MUTED, PanelKit.BODY_FONT)
earnedTitle.TextXAlignment = Enum.TextXAlignment.Left
local coinIcon = UiKit.icon("coin", wFrame, UDim2.fromOffset(44, 44), UDim2.fromOffset(172, 104))
coinIcon.ZIndex = 5
local amountText = label(wFrame, UDim2.fromOffset(220, 56), UDim2.fromOffset(222, 98), 48, PanelKit.GOLD, PanelKit.TITLE_FONT, 3.5)
amountText.TextXAlignment = Enum.TextXAlignment.Left
local ruleText = label(wFrame, UDim2.fromOffset(264, 18), UDim2.fromOffset(174, 160), 13, PanelKit.MUTED, PanelKit.BODY_FONT)
ruleText.TextXAlignment = Enum.TextXAlignment.Left

local wFree = bigButton(wFrame, UDim2.fromOffset(200, 64), UDim2.fromOffset(24, 204), false)
local wX2 = bigButton(wFrame, UDim2.fromOffset(200, 64), UDim2.fromOffset(236, 204), true)
local wSticker = sticker(wFrame, UDim2.fromOffset(408, 188))
ShopLook.button(wFree.button, 3.2)
ShopLook.button(wX2.button, 2.2)
ShopLook.title(amountText, Color3.fromRGB(255, 250, 210), PanelKit.GOLD)
local footText = label(wFrame, UDim2.fromOffset(412, 15), UDim2.fromOffset(24, 278), 12, Color3.fromRGB(201, 168, 130), PanelKit.BODY_FONT)

type Offer = { product: string, amount: number, minutes: number, pot: number?, away: number? }
local welcomeOffer: Offer? = nil

local function claimWelcome(x2: boolean)
	if not welcomeOffer then
		return
	end
	welcomeOffer = nil
	ChestClaim:FireServer("claim", x2)
	welcome.setOpen(false)
end

wFree.button.Activated:Connect(function()
	claimWelcome(false)
end)
wX2.button.Activated:Connect(function()
	claimWelcome(true)
end)
-- X, kliknięcie obok i B na padzie zamykają okno: to też darmowy odbiór (nic nie przepada)
welcome.onToggle(function(open)
	if open then
		ShopLook.openSound()
	else
		claimWelcome(false)
	end
end)

local function showWelcome(offer: Offer)
	welcomeOffer = offer
	welcome.title.Text = Localize.t("X2_WELCOME_TITLE")
	awayText.Text = Localize.t("X2_AWAY", { duration((offer.away or 0) / 60) })
	earnedTitle.Text = Localize.t("X2_EARNED")
	UiFx.countTo(amountText, offer.amount, function(value)
		return "+" .. short(value)
	end, 0.9)
	ruleText.Text = Localize.t("X2_RULE")
	wFree.title.Text = Localize.t("X2_CLAIM")
	wFree.sub.Text = "+" .. short(offer.pot or offer.amount)
	wX2.title.Text = Localize.t("X2_CLAIM_X2")
	wX2.sub.Text = Localize.t("X2_MORE", { Purchases.priceText(offer.product), short(offer.amount) })
	footText.Text = Localize.t("X2_FOOT")
	-- Produkt bez numeru poza Studio (jeszcze nie założony w Creator Hub): samo darmowe „Odbierz” na środku
	local canBuy = Purchases.available(offer.product)
	wX2.button.Visible = canBuy
	wSticker.Visible = canBuy
	footText.Visible = canBuy
	wFree.button.Position = if canBuy then UDim2.fromOffset(24, 204) else UDim2.fromOffset(130, 204)
	welcome.setOpen(true)
end

-- ===== Karta po odbiorze przy skrzyni =====

local card = PanelKit.window({
	name = "ChestCard",
	parent = playerGui,
	width = 420,
	height = 300,
	ribbon = AMBER,
	icon = "chest",
	displayOrder = 8,
})
local cFrame = card.frame
ShopLook.halo(cFrame, UDim2.fromOffset(72, 100), Color3.fromRGB(255, 200, 90), 120, false, 3)
local cChest = UiKit.icon("chest", cFrame, UDim2.fromOffset(96, 96), UDim2.fromOffset(24, 52))
cChest.ZIndex = 4
ShopLook.bob(cChest, 3, 2.4)
local cCheck = UiKit.icon("check", cFrame, UDim2.fromOffset(36, 36), UDim2.fromOffset(92, 112))
cCheck.ZIndex = 5
local cTitle = label(cFrame, UDim2.fromOffset(250, 18), UDim2.fromOffset(140, 50), 15, PanelKit.MUTED, PanelKit.BODY_FONT)
cTitle.TextXAlignment = Enum.TextXAlignment.Left
local cAmount = label(cFrame, UDim2.fromOffset(260, 50), UDim2.fromOffset(138, 68), 42, PanelKit.GREEN, PanelKit.TITLE_FONT, 3)
cAmount.TextXAlignment = Enum.TextXAlignment.Left
local cMinutes = label(cFrame, UDim2.fromOffset(260, 18), UDim2.fromOffset(140, 122), 14, PanelKit.MUTED, PanelKit.BODY_FONT)
cMinutes.TextXAlignment = Enum.TextXAlignment.Left

local cOk = Instance.new("TextButton")
cOk.Name = "Ok"
cOk.Size = UDim2.fromOffset(120, 60)
cOk.Position = UDim2.fromOffset(24, 156)
cOk.Text = ""
cOk.ZIndex = 4
cOk.Parent = cFrame
local okStroke = UiKit.button(cOk, PanelKit.CARD, { gloss = true, radius = UDim.new(0, 16), stroke = 3 })
okStroke.Color = PanelKit.OUTLINE
local okText = label(cOk, UDim2.new(1, -16, 0.6, 0), UDim2.new(0, 8, 0.2, 0), 26, PanelKit.TEXT, PanelKit.TITLE_FONT, 2.5)
okText.Text = "OK"
local cX2 = bigButton(cFrame, UDim2.fromOffset(240, 60), UDim2.fromOffset(156, 156), true)
sticker(cFrame, UDim2.fromOffset(372, 142))
ShopLook.button(cX2.button, 2.2)
local cLink = Instance.new("TextButton")
cLink.Name = "DontShow"
cLink.Size = UDim2.fromOffset(372, 18)
cLink.Position = UDim2.fromOffset(24, 272)
cLink.BackgroundTransparency = 1
cLink.Font = PanelKit.BODY_FONT
cLink.TextColor3 = Color3.fromRGB(201, 168, 130)
cLink.TextSize = 13
cLink.RichText = true
cLink.ZIndex = 4
cLink.Parent = cFrame

-- Progi x2 (Config.ChestX2.tiers): od ilu minut dochodu w skrzyni jaka cena; bieżący świeci na złoto
type Tier = { frame: Frame, stroke: UIStroke, top: TextLabel, price: TextLabel, product: string, minutes: number }
local tierTiles: { Tier } = {}
local tierRow = Instance.new("Frame")
tierRow.Name = "Tiers"
tierRow.BackgroundTransparency = 1
tierRow.Size = UDim2.fromOffset(372, 40)
tierRow.Position = UDim2.fromOffset(24, 226)
tierRow.ZIndex = 4
tierRow.Parent = cFrame
local tierLayout = Instance.new("UIListLayout")
tierLayout.FillDirection = Enum.FillDirection.Horizontal
tierLayout.Padding = UDim.new(0, 6)
tierLayout.SortOrder = Enum.SortOrder.LayoutOrder
tierLayout.Parent = tierRow
for order, tier in Config.ChestX2.tiers do
	local count = #Config.ChestX2.tiers
	local tile = Instance.new("Frame")
	tile.Name = "Tier_" .. tier.product
	tile.LayoutOrder = order
	tile.Size = UDim2.new(1 / count, -6 * (count - 1) / count, 1, 0)
	tile.BackgroundColor3 = Color3.fromRGB(52, 36, 26)
	tile.ZIndex = 4
	tile.Parent = tierRow
	round(tile, 10)
	local tileStroke = Instance.new("UIStroke")
	tileStroke.Color = PanelKit.OUTLINE
	tileStroke.Thickness = 2
	tileStroke.Parent = tile
	local top = label(tile, UDim2.new(1, -8, 0, 15), UDim2.fromOffset(4, 4), 12, PanelKit.MUTED, PanelKit.BODY_FONT)
	local price = label(tile, UDim2.new(1, -8, 0, 16), UDim2.fromOffset(4, 20), 14, PanelKit.TEXT, PanelKit.TITLE_FONT)
	table.insert(tierTiles, { frame = tile, stroke = tileStroke, top = top, price = price, product = tier.product, minutes = tier.fromMinutes })
end

local function showTiers(current: string)
	for _, tile in tierTiles do
		local on = tile.product == current
		tile.top.Text = Localize.t("X2_TIER", { duration(tile.minutes) })
		tile.price.Text = Purchases.priceText(tile.product)
		tile.stroke.Color = if on then PanelKit.GOLD else PanelKit.OUTLINE
		tile.stroke.Thickness = if on then 3 else 2
		tile.frame.BackgroundColor3 = if on then Color3.fromRGB(96, 70, 22) else Color3.fromRGB(52, 36, 26)
		tile.top.TextColor3 = if on then PanelKit.GOLD else PanelKit.MUTED
		tile.price.TextColor3 = if on then PanelKit.GOLD else PanelKit.TEXT
	end
end

local cardOffer: Offer? = nil
local lastCard = -math.huge
local declines = 0

local function hideCard(declined: boolean)
	if declined and cardOffer then
		declines += 1
	end
	cardOffer = nil
	card.setOpen(false)
end

cOk.Activated:Connect(function()
	hideCard(true)
end)
card.onToggle(function(open)
	if open then
		-- Karta nie przyciemnia ekranu i nie blokuje chodzenia (odejście od skrzyni ją zamyka)
		card.dim.Visible = false
		PanelKit.setModal("ChestCard", false)
	elseif cardOffer then
		hideCard(true)
	end
end)
cX2.button.Activated:Connect(function()
	local offer = cardOffer
	if offer then
		declines = 0
		cardOffer = nil
		card.setOpen(false)
		Purchases.buy(offer.product)
	end
end)
cLink.Activated:Connect(function()
	SaveSettings:FireServer("x2Card", false)
	hideCard(false)
end)

local function ownChest(): BasePart?
	for _, model in CollectionService:GetTagged("GardenPlot") do
		if model:GetAttribute("OwnerUserId") == player.UserId then
			local chest = model:FindFirstChild("Chest", true)
			if chest and chest:IsA("BasePart") then
				return chest
			end
		end
	end
	return nil
end

local function showCard(offer: Offer)
	if not Purchases.available(offer.product) or player:GetAttribute("X2Card") == false or declines >= Config.ChestX2.cardDeclines then
		return
	end
	if os.clock() - lastCard < Config.ChestX2.cardCooldown or welcome.isOpen() then
		return
	end
	lastCard = os.clock()
	cardOffer = offer
	card.title.Text = Localize.t("X2_CHEST_TITLE")
	cTitle.Text = Localize.t("X2_COLLECTED")
	UiFx.countTo(cAmount, offer.amount, function(value)
		return "+" .. short(value)
	end, 0.7)
	showTiers(offer.product)
	cMinutes.Text = Localize.t("X2_MINUTES", { duration(offer.minutes) })
	cX2.title.Text = Localize.t("X2_CLAIM_X2")
	cX2.sub.Text = Localize.t("X2_MORE", { Purchases.priceText(offer.product), short(offer.amount) })
	cLink.Text = "<u>" .. Localize.t("X2_DONT_SHOW") .. "</u>"
	card.setOpen(true)
end

-- Odejście od skrzyni zamyka kartę
task.spawn(function()
	while true do
		task.wait(0.5)
		if cardOffer then
			local chest = ownChest()
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if chest and root and root:IsA("BasePart") and (root.Position - chest.Position).Magnitude > CARD_AWAY then
				hideCard(false)
			end
		end
	end
end)

-- ===== Plakietka „x2 [G]” nad własną skrzynią =====

local tag = Instance.new("BillboardGui")
tag.Name = "ChestX2Tag"
tag.Size = UDim2.fromOffset(104, 40)
tag.StudsOffset = Vector3.new(0, 5.8, 0)
tag.MaxDistance = 45
tag.AlwaysOnTop = false
tag.LightInfluence = 0
tag.Enabled = false
tag.ResetOnSpawn = false
tag.Parent = playerGui
local pill = Instance.new("Frame")
pill.Name = "Pill"
pill.Size = UDim2.fromScale(1, 1)
pill.BackgroundColor3 = Color3.new(1, 1, 1)
pill.Parent = tag
round(pill, 20)
local pillStroke = Instance.new("UIStroke")
pillStroke.Color = PanelKit.OUTLINE
pillStroke.Thickness = 2.5
pillStroke.Parent = pill
local pillShade = Instance.new("UIGradient")
pillShade.Rotation = 90
pillShade.Color = ColorSequence.new(GOLD_TOP, Color3.fromRGB(240, 176, 48))
pillShade.Parent = pill
local pillText = label(pill, UDim2.new(0.5, 0, 0.8, 0), UDim2.new(0.08, 0, 0.1, 0), 26, DARK, PanelKit.TITLE_FONT)
pillText.Text = "x2"
local keyChip = Instance.new("Frame")
keyChip.Name = "Key"
keyChip.Size = UDim2.fromOffset(30, 30)
keyChip.AnchorPoint = Vector2.new(1, 0.5)
keyChip.Position = UDim2.new(1, -6, 0.5, 0)
keyChip.BackgroundColor3 = DARK
keyChip.Parent = pill
round(keyChip, 8)
local keyText = label(keyChip, UDim2.fromScale(0.8, 0.8), UDim2.fromScale(0.1, 0.1), 18, PanelKit.TEXT, PanelKit.TITLE_FONT)
keyText.Text = "G"
shimmer(pill, 4)

local function keyLabel(): string?
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return nil -- na telefonie przycisk przy skrzyni się stuka
	elseif last.Name:find("Gamepad") then
		return "R1"
	end
	return "G"
end

local function refreshTag()
	local chest = ownChest()
	local model = chest and chest:FindFirstAncestorWhichIsA("Model")
	while model and not CollectionService:HasTag(model, "GardenPlot") do
		model = model:FindFirstAncestorWhichIsA("Model")
	end
	local product = model and model:GetAttribute("X2Product")
	local ready = chest ~= nil and typeof(product) == "string" and product ~= "" and Purchases.available(product)
	-- Skrzynia wypadła ze streamingu = plakietka gaśnie (bez tego wisiałaby przed chatką)
	BillboardGuard.bind(tag, chest, ready)
	local key = keyLabel()
	keyChip.Visible = key ~= nil
	keyText.Text = key or ""
	pillText.Size = if key then UDim2.new(0.5, 0, 0.8, 0) else UDim2.new(0.84, 0, 0.8, 0)
end

-- ===== Wiadomości z serwera =====

ChestOffer.OnClientEvent:Connect(function(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	local kind = payload.kind
	local product = payload.product
	if typeof(product) ~= "string" or not Config.Products[product] then
		return
	end
	if kind == "welcome" then
		showWelcome({
			product = product,
			amount = tonumber(payload.earned) or 0,
			minutes = tonumber(payload.minutes) or 0,
			pot = tonumber(payload.pot),
			away = tonumber(payload.away),
		})
	elseif kind == "claimed" then
		if payload.buy == true then
			Purchases.buy(product)
		end
	elseif kind == "collect" then
		local offer = { product = product, amount = tonumber(payload.amount) or 0, minutes = tonumber(payload.minutes) or 0 }
		if payload.buy == true then
			Purchases.buy(product) -- G przy skrzyni: gracz sam poprosił o x2
		else
			showCard(offer)
		end
	elseif kind == "paid" then
		hideCard(false)
	end
	refreshTag()
end)

function ChestOffers.start()
	-- Plakietka nad skrzynią śledzi atrybut X2Product ogródka (serwer odświeża go co kilka sekund)
	task.spawn(function()
		while true do
			refreshTag()
			task.wait(1)
		end
	end)
	-- Okno powrotu: dopiero po ekranie wczytywania, z postacią na mapie i bez cutscenki
	task.spawn(function()
		local started = os.clock()
		while player:GetAttribute("Loaded") ~= true and os.clock() - started < 60 do
			if os.clock() - started > 3 and not playerGui:FindFirstChild("LoadingScreen") then
				break
			end
			task.wait(0.2)
		end
		if not player.Character then
			player.CharacterAdded:Wait()
		end
		task.wait(Config.ChestX2.welcomeDelay)
		while CutsceneKit.isPlaying() do
			task.wait(0.5)
		end
		ChestClaim:FireServer("ready")
	end)
end

-- W Studio: podgląd bez czekania na serwer
if RunService:IsStudio() then
	player:GetAttributeChangedSignal("DevChestPreview"):Connect(function()
		showWelcome({ product = "x2l", amount = 1_200_000, minutes = 168, pot = 1_350_000, away = 5 * 3600 + 12 * 60 })
	end)
end

return ChestOffers
