--!strict
-- Interfejs budowany kodem, projektowany najpierw pod telefon:
-- duży przycisk ZBIERZ obok przycisku skoku, panel chatki na dole ekranu.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Localize = require(script.Parent.Localize)

export type State = {
	coins: number,
	oil: number,
	oilMax: number,
	basketCount: number,
	basketMax: number,
	basketValue: number,
	lanternRange: number,
	zone: number,
	upgrades: { [string]: number },
}

local Hud = {}

local COLORS = {
	panel = Color3.fromRGB(28, 24, 22),
	text = Color3.fromRGB(245, 235, 215),
	accent = Color3.fromRGB(255, 190, 90),
	oil = Color3.fromRGB(255, 170, 60),
	oilLow = Color3.fromRGB(220, 60, 40),
	button = Color3.fromRGB(70, 110, 60),
	buttonOff = Color3.fromRGB(70, 66, 60),
	pick = Color3.fromRGB(230, 150, 50),
}
local FONT = Enum.Font.GothamBold

local callbacks = {
	pick = {} :: { () -> () },
	sell = {} :: { () -> () },
	buy = {} :: { (string) -> () },
}

local lastState: State? = nil
local inCabin = true

local function corner(parent: Instance, radius: UDim?)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or UDim.new(0, 10)
	c.Parent = parent
end

local function label(name: string, parent: Instance, size: UDim2, position: UDim2, anchor: Vector2?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = size
	l.Position = position
	l.AnchorPoint = anchor or Vector2.zero
	l.BackgroundColor3 = COLORS.panel
	l.BackgroundTransparency = 0.25
	l.TextColor3 = COLORS.text
	l.Font = FONT
	l.TextScaled = true
	l.Text = ""
	l.Parent = parent
	corner(l)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 24
	constraint.Parent = l
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = l
	return l
end

local function button(name: string, parent: Instance, size: UDim2, position: UDim2, anchor: Vector2?): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = size
	b.Position = position
	b.AnchorPoint = anchor or Vector2.zero
	b.BackgroundColor3 = COLORS.button
	b.TextColor3 = COLORS.text
	b.Font = FONT
	b.TextScaled = true
	b.RichText = true
	b.AutoButtonColor = true
	b.Parent = parent
	corner(b)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 22
	constraint.Parent = b
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = b
	return b
end

-- ===== Budowa interfejsu =====

local gui = Instance.new("ScreenGui")
gui.Name = "Hud"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local coinsLabel = label("Coins", gui, UDim2.new(0, 190, 0, 34), UDim2.new(0, 12, 0, 8))
coinsLabel.TextColor3 = COLORS.accent
coinsLabel.TextXAlignment = Enum.TextXAlignment.Left

local basketLabel = label("Basket", gui, UDim2.new(0, 190, 0, 30), UDim2.new(0, 12, 0, 48))
basketLabel.TextXAlignment = Enum.TextXAlignment.Left

local languageButton = button("Language", gui, UDim2.new(0, 56, 0, 34), UDim2.new(1, -12, 0, 8), Vector2.new(1, 0))
languageButton.BackgroundColor3 = COLORS.panel

-- Strefa i pasek oleju na środku u góry
local topFrame = Instance.new("Frame")
topFrame.Name = "Top"
topFrame.Size = UDim2.new(0, 300, 0, 58)
topFrame.Position = UDim2.new(0.5, 0, 0, 8)
topFrame.AnchorPoint = Vector2.new(0.5, 0)
topFrame.BackgroundTransparency = 1
topFrame.Parent = gui

local zoneLabel = label("Zone", topFrame, UDim2.new(1, 0, 0, 28), UDim2.new(0, 0, 0, 0))

local oilBack = Instance.new("Frame")
oilBack.Name = "OilBar"
oilBack.Size = UDim2.new(1, 0, 0, 24)
oilBack.Position = UDim2.new(0, 0, 0, 32)
oilBack.BackgroundColor3 = COLORS.panel
oilBack.BackgroundTransparency = 0.25
oilBack.ClipsDescendants = true
oilBack.Parent = topFrame
corner(oilBack)

local oilFill = Instance.new("Frame")
oilFill.Name = "Fill"
oilFill.Size = UDim2.new(1, 0, 1, 0)
oilFill.BackgroundColor3 = COLORS.oil
oilFill.BorderSizePixel = 0
oilFill.Parent = oilBack
corner(oilFill)

local oilText = Instance.new("TextLabel")
oilText.Name = "Text"
oilText.Size = UDim2.new(1, 0, 1, 0)
oilText.BackgroundTransparency = 1
oilText.TextColor3 = COLORS.text
oilText.TextStrokeTransparency = 0.4
oilText.Font = FONT
oilText.TextScaled = true
oilText.ZIndex = 2
oilText.Text = ""
oilText.Parent = oilBack
local oilTextConstraint = Instance.new("UITextSizeConstraint")
oilTextConstraint.MaxTextSize = 16
oilTextConstraint.Parent = oilText

-- Przycisk ZBIERZ: na lewo od mobilnego przycisku skoku. Skok na dużych ekranach zajmuje
-- ok. 50-170 px od prawej i 90-210 px od dołu, więc stajemy obok, a nie nad nim.
local pickButton = button("Pick", gui, UDim2.new(0, 110, 0, 110), UDim2.new(1, -190, 1, -40), Vector2.new(1, 1))
pickButton.BackgroundColor3 = COLORS.pick
corner(pickButton, UDim.new(0.5, 0))
local pickStroke = Instance.new("UIStroke")
pickStroke.Thickness = 3
pickStroke.Color = Color3.fromRGB(255, 240, 200)
pickStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
pickStroke.Parent = pickButton

-- Panel chatki: sprzedaż i ulepszenia
local cabinPanel = Instance.new("Frame")
cabinPanel.Name = "CabinPanel"
cabinPanel.Size = UDim2.new(0.92, 0, 0, 180)
cabinPanel.Position = UDim2.new(0.5, 0, 1, -16)
cabinPanel.AnchorPoint = Vector2.new(0.5, 1)
cabinPanel.BackgroundColor3 = COLORS.panel
cabinPanel.BackgroundTransparency = 0.2
cabinPanel.Parent = gui
corner(cabinPanel, UDim.new(0, 14))
local panelSize = Instance.new("UISizeConstraint")
panelSize.MaxSize = Vector2.new(560, 180)
panelSize.Parent = cabinPanel
local panelPadding = Instance.new("UIPadding")
panelPadding.PaddingLeft = UDim.new(0, 8)
panelPadding.PaddingRight = UDim.new(0, 8)
panelPadding.PaddingTop = UDim.new(0, 8)
panelPadding.PaddingBottom = UDim.new(0, 8)
panelPadding.Parent = cabinPanel

local sellButton = button("Sell", cabinPanel, UDim2.new(1, 0, 0, 46), UDim2.new(0, 0, 0, 0))
sellButton.Text = ""
sellButton.BackgroundColor3 = Color3.fromRGB(180, 120, 40)

local grid = Instance.new("Frame")
grid.Name = "Upgrades"
grid.Size = UDim2.new(1, 0, 1, -54)
grid.Position = UDim2.new(0, 0, 0, 54)
grid.BackgroundTransparency = 1
grid.Parent = cabinPanel
local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.new(0.5, -4, 0.5, -4)
gridLayout.CellPadding = UDim2.new(0, 8, 0, 8)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = grid

local upgradeButtons: { [string]: TextButton } = {}
for order, id in Config.UpgradeOrder do
	local b = button("Upgrade_" .. id, grid, UDim2.new(), UDim2.new())
	b.Text = "" -- zanim przyjdzie stan z serwera, zamiast domyślnego „Button”
	b.LayoutOrder = order
	upgradeButtons[id] = b
	b.Activated:Connect(function()
		for _, callback in callbacks.buy do
			callback(id)
		end
	end)
end

-- Komunikaty
local toastLabel = label("Toast", gui, UDim2.new(0.8, 0, 0, 40), UDim2.new(0.5, 0, 0, 78), Vector2.new(0.5, 0))
toastLabel.Visible = false
toastLabel.TextColor3 = COLORS.accent

-- Zaciemnienie, gdy las pochłonie gracza
local blackout = Instance.new("Frame")
blackout.Name = "Blackout"
blackout.Size = UDim2.new(1, 0, 1, 0)
blackout.BackgroundColor3 = Color3.new(0, 0, 0)
blackout.BackgroundTransparency = 1
blackout.ZIndex = 10
blackout.Active = false
blackout.Parent = gui

-- ===== Logika =====

local toastToken = 0

local function render()
	languageButton.Text = Localize.t("HUD_LANGUAGE")
	pickButton.Text = Localize.t("HUD_PICK")

	local state = lastState
	if not state then
		return
	end

	coinsLabel.Text = Localize.t("HUD_COINS", { state.coins })
	basketLabel.Text = Localize.t("HUD_BASKET", { state.basketCount, state.basketMax })

	local zoneDef = Config.Zones[state.zone] or Config.Zones[1]
	zoneLabel.Text = Localize.t(zoneDef.key)

	local fraction = if state.oilMax > 0 then math.clamp(state.oil / state.oilMax, 0, 1) else 0
	oilFill.Size = UDim2.new(fraction, 0, 1, 0)
	oilFill.BackgroundColor3 = if fraction < Config.OilLowFraction then COLORS.oilLow else COLORS.oil
	oilText.Text = string.format("%s  %d/%d", Localize.t("HUD_OIL"), math.ceil(state.oil), state.oilMax)

	if state.basketCount > 0 then
		sellButton.Text = Localize.t("HUD_SELL", { state.basketValue })
		sellButton.AutoButtonColor = true
		sellButton.BackgroundTransparency = 0
	else
		sellButton.Text = Localize.t("HUD_SELL_EMPTY")
		sellButton.AutoButtonColor = false
		sellButton.BackgroundTransparency = 0.5
	end

	for id, b in upgradeButtons do
		local def = Config.Upgrades[id]
		local level = state.upgrades[id] or 0
		local cost = Economy.upgradeCost(id, level)
		local title = string.format("<b>%s</b>  %s", Localize.t(def.key), Localize.t("HUD_LEVEL", { level }))
		if cost then
			b.Text = title .. "\n" .. Localize.t("HUD_COST", { cost })
			local affordable = state.coins >= cost
			b.BackgroundColor3 = if affordable then COLORS.button else COLORS.buttonOff
		else
			b.Text = title .. "\n" .. Localize.t("HUD_MAX")
			b.BackgroundColor3 = COLORS.buttonOff
		end
	end
end

function Hud.update(state: State)
	lastState = state
	render()
end

function Hud.refreshTexts()
	render()
end

function Hud.setInCabin(value: boolean)
	if value ~= inCabin then
		inCabin = value
		cabinPanel.Visible = value
	end
end

function Hud.setPick(enabled: boolean, visible: boolean)
	pickButton.Visible = visible
	pickButton.BackgroundTransparency = if enabled then 0 else 0.6
	pickButton.TextTransparency = if enabled then 0 else 0.4
	pickStroke.Transparency = if enabled then 0 else 0.7
end

function Hud.toast(text: string)
	toastToken += 1
	local token = toastToken
	toastLabel.Text = text
	toastLabel.Visible = true
	task.delay(2.5, function()
		if toastToken == token then
			toastLabel.Visible = false
		end
	end)
end

function Hud.fadeBlack()
	blackout.BackgroundTransparency = 0
	TweenService:Create(blackout, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		BackgroundTransparency = 1,
	}):Play()
end

function Hud.onPick(callback: () -> ())
	table.insert(callbacks.pick, callback)
end

function Hud.onSell(callback: () -> ())
	table.insert(callbacks.sell, callback)
end

function Hud.onBuy(callback: (string) -> ())
	table.insert(callbacks.buy, callback)
end

pickButton.Activated:Connect(function()
	for _, callback in callbacks.pick do
		callback()
	end
end)

sellButton.Activated:Connect(function()
	for _, callback in callbacks.sell do
		callback()
	end
end)

languageButton.Activated:Connect(function()
	Localize.toggle()
end)

Hud.setPick(false, false)
render()

return Hud
