--!strict
-- Panel DEV: przycisk 🛠 pod przełącznikiem języka, widoczny tylko dla deweloperów
-- (Studio, twórca gry, Config.DevUserIds). Każdą akcję i tak sprawdza serwer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local UiScale = require(script.Parent.UiScale)

local DevPanel = {}

local DevAction = Remotes.get("DevAction")

-- Kolejność = kolejność przycisków (po dwa w rzędzie)
local ACTIONS: { { id: string, label: string } } = {
	{ id = "coins10k", label = "+10 000 💰" },
	{ id = "coins100k", label = "+100 000 💰" },
	{ id = "coinsZero", label = "Zeruj monety" },
	{ id = "basketClear", label = "Opróżnij koszyk" },
	{ id = "caveUnlock", label = "Odblokuj jaskinię" },
	{ id = "caveLock", label = "Zablokuj jaskinię" },
	{ id = "upgradesMax", label = "Ulepszenia MAX" },
	{ id = "upgradesReset", label = "Ulepszenia na 0" },
	{ id = "oilFull", label = "Pełny olej" },
	{ id = "oilLow", label = "Olej 10%" },
	{ id = "tpCabin", label = "TP: chatka" },
	{ id = "tpPlaza", label = "TP: plac portali" },
	{ id = "tpGrove", label = "TP: gniazdo Leszego" },
	{ id = "tpPortal", label = "TP: portal w lesie" },
	{ id = "tpCamp", label = "TP: obozowisko" },
	{ id = "tpAbyss", label = "TP: Otchłań" },
}

local gui = Instance.new("ScreenGui")
gui.Name = "DevPanel"
gui.ResetOnSpawn = false
gui.DisplayOrder = 5
gui.Enabled = false
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local function corner(parent: Instance)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = parent
end

local toggle = Instance.new("TextButton")
toggle.Name = "Toggle"
toggle.Size = UDim2.fromOffset(52, 30)
toggle.BackgroundColor3 = Color3.fromRGB(60, 30, 80)
toggle.TextColor3 = Color3.fromRGB(255, 230, 255)
toggle.Font = Enum.Font.FredokaOne
toggle.TextSize = 16
toggle.Text = "🛠 DEV"
toggle.Parent = gui
corner(toggle)
local toggleScale = Instance.new("UIScale")
toggleScale.Parent = toggle

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(330, 4 + math.ceil(#ACTIONS / 2) * 40 + 4)
panel.BackgroundColor3 = Color3.fromRGB(30, 20, 40)
panel.BackgroundTransparency = 0.1
panel.Visible = false
panel.Parent = gui
corner(panel)
local panelScale = Instance.new("UIScale")
panelScale.Parent = panel
local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 6)
padding.PaddingLeft = UDim.new(0, 6)
padding.PaddingRight = UDim.new(0, 6)
padding.Parent = panel
local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.new(0.5, -4, 0, 34)
grid.CellPadding = UDim2.fromOffset(6, 6)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = panel

for order, action in ACTIONS do
	local button = Instance.new("TextButton")
	button.Name = action.id
	button.LayoutOrder = order
	button.BackgroundColor3 = if string.sub(action.id, 1, 2) == "tp" then Color3.fromRGB(50, 70, 110) else Color3.fromRGB(80, 50, 100)
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 14
	button.Text = action.label
	button.Parent = panel
	corner(button)
	button.Activated:Connect(function()
		DevAction:FireServer(action.id)
	end)
end

toggle.Activated:Connect(function()
	panel.Visible = not panel.Visible
end)

-- Pod przyciskiem języka (ten sam rachunek co w Hud.layout)
UiScale.onChanged(function()
	local scale = UiScale.get()
	toggleScale.Scale = scale
	panelScale.Scale = scale
	local y = 8 + math.floor(80 * scale) + 8 + math.floor(30 * scale) + 6
	toggle.Position = UDim2.fromOffset(12, y)
	panel.Position = UDim2.fromOffset(12, y + math.floor(36 * scale))
end)

function DevPanel.setEnabled(enabled: boolean)
	gui.Enabled = enabled
end

return DevPanel
