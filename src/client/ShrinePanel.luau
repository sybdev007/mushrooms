--!strict
-- Ofiara dla Leszego: okno przy kapliczce na Placu Portali (serwer: ShrineService, logika: Shared/Shrine).
-- Pokazuje łączną sumę, następny próg i tytuły za progi (✅ zdobyte), cztery przyciski kwot
-- (1 / 10 / 100 mln / 1 mld) i okienko potwierdzenia z saldem po wpłacie. Bez „wszystko”.
-- Klient tylko prosi (ShrineAction); kwotę, saldo, Górę, odległość i odstęp między wpłatami sprawdza
-- serwer. Stan przychodzi przez ShrineView (jedyny odbiorca tego zdarzenia, zasada 4).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Shrine = require(Shared:WaitForChild("Shrine"))
local Audio = require(script.Parent.Audio)
local Localize = require(script.Parent.Localize)
local PanelKit = require(script.Parent.PanelKit)
local UiKit = require(script.Parent.UiKit)

local ShrinePanel = {}

local WIDTH, HEIGHT = 560, 440
local GREEN = Color3.fromRGB(86, 186, 84)
local GREY = Color3.fromRGB(120, 108, 98)
local MOSS = Color3.fromRGB(70, 120, 60)

local total = 0
local nextGoal: number? = nil
local coins = 0
local unlocked = false
local available = true
local pending: number? = nil -- kwota w okienku potwierdzenia

local function t(key: string, args: { any }?): string
	return Localize.t(key, args)
end

local function formatCoins(value: number): string
	local s = string.format("%.0f", value)
	local formatted = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (formatted:gsub("^ ", ""))
end

-- Krótko: 1 mln, 100 mln, 1 mld (po angielsku 1M, 100M, 1B)
local function short(value: number): string
	local pl = Localize.getLocale() == "pl"
	if value >= 1e9 then
		return string.format("%g", value / 1e9) .. (if pl then " mld" else "B")
	end
	return string.format("%g", value / 1e6) .. (if pl then " mln" else "M")
end

local window = PanelKit.window({
	name = "LeszyShrine",
	parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	width = WIDTH,
	height = HEIGHT,
	ribbon = MOSS,
	icon = "moon",
	pillIcon = "coins",
	pillColor = Color3.fromRGB(40, 52, 34),
})
local content = window.content

local totalLabel = PanelKit.label(content, "Total", UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 26), 24, PanelKit.GOLD)
UiKit.outline(totalLabel, 2)
local nextLabel = PanelKit.label(content, "Next", UDim2.new(1, 0, 0, 22), UDim2.fromOffset(0, 58), 17, PanelKit.MUTED, PanelKit.BODY_FONT)

-- Nagrody za progi
local rewardRows: { TextLabel } = {}
for i, tier in Config.Shrine.tiers do
	local row = PanelKit.label(content, "Reward" .. i, UDim2.new(1, -20, 0, 22), UDim2.fromOffset(10, 86 + (i - 1) * 24), 16, PanelKit.TEXT, PanelKit.BODY_FONT)
	row.TextXAlignment = Enum.TextXAlignment.Left
	row:SetAttribute("Goal", tier.goal)
	table.insert(rewardRows, row)
end

-- Przyciski kwot
local amountButtons: { TextButton } = {}
local BUTTON_W, BUTTON_GAP = 120, 10
local rowX = (WIDTH - 28 - (#Config.Shrine.amounts * BUTTON_W + (#Config.Shrine.amounts - 1) * BUTTON_GAP)) / 2
for i, amount in Config.Shrine.amounts do
	local b = Instance.new("TextButton")
	b.Name = "Amount" .. i
	b.Size = UDim2.fromOffset(BUTTON_W, 46)
	b.Position = UDim2.fromOffset(rowX + (i - 1) * (BUTTON_W + BUTTON_GAP), 236)
	b.Font = PanelKit.TITLE_FONT
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Parent = content
	UiKit.button(b, GREEN, { stroke = 3, radius = UDim.new(0, 14), gloss = true })
	UiKit.outline(b, 2.5)
	local size = Instance.new("UITextSizeConstraint")
	size.MaxTextSize = 22
	size.Parent = b
	b:SetAttribute("Amount", amount)
	table.insert(amountButtons, b)
end
local hint = PanelKit.label(content, "Hint", UDim2.new(1, -20, 0, 60), UDim2.fromOffset(10, 292), 15, PanelKit.MUTED, PanelKit.BODY_FONT)
hint.TextWrapped = true

-- Okienko potwierdzenia (na wierzchu okna)
local confirm = Instance.new("Frame")
confirm.Name = "Confirm"
confirm.Size = UDim2.new(1, -40, 0, 170)
confirm.Position = UDim2.fromOffset(20, 110)
confirm.BackgroundColor3 = PanelKit.BG_DARK
confirm.ZIndex = 20
confirm.Visible = false
confirm.Parent = content
PanelKit.corner(confirm, UDim.new(0, 16))
PanelKit.stroke(confirm, PanelKit.GOLD, 3)
local confirmText = PanelKit.label(confirm, "Text", UDim2.new(1, -24, 0, 90), UDim2.fromOffset(12, 10), 20, PanelKit.TEXT)
confirmText.TextWrapped = true
confirmText.ZIndex = 21
local function smallButton(name: string, color: Color3, x: number): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = UDim2.new(0.5, -18, 0, 46)
	b.Position = UDim2.new(x, 12 - x * 12, 1, -58)
	b.Font = PanelKit.TITLE_FONT
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.ZIndex = 21
	b.Parent = confirm
	UiKit.button(b, color, { stroke = 3, radius = UDim.new(0, 14) })
	UiKit.outline(b, 2.5)
	local size = Instance.new("UITextSizeConstraint")
	size.MaxTextSize = 20
	size.Parent = b
	return b
end
local cancelButton = smallButton("Cancel", Color3.fromRGB(150, 70, 60), 0)
local acceptButton = smallButton("Accept", GREEN, 0.5)

local function render()
	if not window.isOpen() then
		return
	end
	window.title.Text = t("LESZY_OFFER_TITLE")
	window.pillText.Text = formatCoins(coins)
	totalLabel.Text = t("LESZY_OFFER_TOTAL", { formatCoins(total) })
	nextLabel.Text = if nextGoal then t("LESZY_OFFER_NEXT", { formatCoins(nextGoal) }) else t("LESZY_OFFER_ALL_REWARDS")
	for i, tier in Config.Shrine.tiers do
		local reached = total >= tier.goal
		local row = rewardRows[i]
		row.Text = (if reached then "✅ " else "• ") .. short(tier.goal) .. " · " .. t(tier.title)
		row.TextColor3 = if reached then Color3.fromRGB(150, 235, 120) else PanelKit.TEXT
	end
	local canOffer = unlocked and available
	for _, b in amountButtons do
		local amount = b:GetAttribute("Amount") :: number
		b.Text = short(amount)
		local ok = canOffer and coins >= amount
		UiKit.recolor(b, if ok then GREEN else GREY)
		b.Active = ok
	end
	hint.Text = if not available then t("LESZY_OFFER_UNAVAILABLE")
		elseif not unlocked then t("LESZY_OFFER_LOCKED")
		else t("LESZY_OFFER_LIMIT")
	local amount = pending
	confirm.Visible = amount ~= nil
	if amount then
		confirmText.Text = t("LESZY_OFFER_CONFIRM", { formatCoins(amount), formatCoins(math.max(0, coins - amount)) })
		cancelButton.Text = t("LESZY_OFFER_CANCEL")
		acceptButton.Text = t("LESZY_OFFER_ACCEPT")
	end
end

for _, b in amountButtons do
	b.Activated:Connect(function()
		local amount = b:GetAttribute("Amount")
		if not b.Active or typeof(amount) ~= "number" then
			Audio.play("warn")
			return
		end
		pending = amount
		Audio.play("click")
		render()
	end)
end
cancelButton.Activated:Connect(function()
	pending = nil
	render()
end)
acceptButton.Activated:Connect(function()
	local amount = pending
	pending = nil
	if amount and coins >= amount then
		Remotes.get("ShrineAction"):FireServer(amount)
		Audio.play("levelup", { volume = 0.5 })
	end
	render()
end)

Remotes.get("ShrineView").OnClientEvent:Connect(function(view: any, open: boolean)
	if typeof(view) ~= "table" then
		return
	end
	total = Shrine.readTotal(view.total)
	nextGoal = if typeof(view.nextGoal) == "number" then view.nextGoal else nil
	coins = if typeof(view.coins) == "number" then view.coins else coins
	unlocked = view.unlocked == true
	available = view.available ~= false
	if open then
		pending = nil
		window.setOpen(true)
	end
	render()
end)

window.onToggle(function(open: boolean)
	if open then
		render()
	else
		-- Zamknięcie okna porzuca niepotwierdzoną kwotę
		pending = nil
	end
end)
Localize.onChanged(render)

return ShrinePanel
