--!strict
-- Przyciski w rzędzie obok przełącznika języka (pod panelem monet): 📖 Grzybopedia, 📜 Zadania.
-- Rząd języka jest zawsze widoczny (sklep pod nim chowa się, gdy produkty nie mają numerów).

local Players = game:GetService("Players")

local UiKit = require(script.Parent.UiKit)
local UiScale = require(script.Parent.UiScale)

local SideButtons = {}

local gui = Instance.new("ScreenGui")
gui.Name = "SideButtons"
gui.ResetOnSpawn = false
gui.DisplayOrder = 4
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local WIDTH = 70
local HEIGHT = 30
local GAP = 6
local LANGUAGE_WIDTH = 70

type Entry = { button: TextButton, scale: UIScale, slot: number }
local entries: { Entry } = {}

local function layout()
	local scale = UiScale.get()
	-- Ten sam rachunek co w Hud.layout: panel monet (80) + odstęp, potem rząd języka
	local y = 8 + math.floor(80 * scale) + 8
	for _, entry in entries do
		entry.scale:SetAttribute("Base", scale)
		entry.scale.Scale = scale
		local x = 12 + math.floor((LANGUAGE_WIDTH + GAP) * scale) + math.floor((WIDTH + GAP) * scale) * (entry.slot - 1)
		entry.button.Position = UDim2.fromOffset(x, y)
	end
end

-- Dodaje przycisk w kolejnym miejscu rzędu: ikona z arkusza po lewej, krótki tekst po prawej
function SideButtons.add(name: string, icon: string, color: Color3): (TextButton, TextLabel)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.fromOffset(WIDTH, HEIGHT)
	button.Text = ""
	button.Parent = gui
	UiKit.button(button, color, { gloss = true })
	UiKit.icon(icon, button, UDim2.fromOffset(28, 28), UDim2.new(0, 3, 0.5, 0), Vector2.new(0, 0.5))
	local label = Instance.new("TextLabel")
	label.Name = "Badge"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -36, 1, -8)
	label.Position = UDim2.new(0, 32, 0, 4)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 252, 240)
	label.TextStrokeTransparency = 0.4
	label.TextStrokeColor3 = UiKit.darker(color, 0.65)
	label.Text = ""
	label.ZIndex = 4
	label.Parent = button
	local scale = button:FindFirstChildOfClass("UIScale") :: UIScale
	table.insert(entries, { button = button, scale = scale, slot = #entries + 1 })
	layout()
	return button, label
end

UiScale.onChanged(layout)

return SideButtons
