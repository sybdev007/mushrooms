--!strict
-- Duże przyciski okien pod przyciskiem „Ulepszenia” (prawa krawędź), w tym samym stylu:
-- kolorowy przycisk z napisem, duża ikona wystająca w lewo, klawisz w rogu i plakietka z liczbą.
-- Kolejność: 📜 Zadania, 📖 Grzybopedia, 🏷️ Tytuły (każde okno dodaje swój przycisk).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Localize = require(script.Parent.Localize)
local UiKit = require(script.Parent.UiKit)
local UiScale = require(script.Parent.UiScale)

local SideButtons = {}

local gui = Instance.new("ScreenGui")
gui.Name = "SideButtons"
gui.ResetOnSpawn = false
gui.DisplayOrder = 4
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local OUTLINE = UiKit.OUTLINE
local WIDTH = 176
local HEIGHT = 52
local GAP = 12
-- Przycisk „Ulepszenia” (Hud): środek na 42% wysokości ekranu, wysokość 60
local UPGRADES_HALF = 30

local column = Instance.new("Frame")
column.Name = "Column"
column.BackgroundTransparency = 1
column.AnchorPoint = Vector2.new(1, 0)
column.Size = UDim2.fromOffset(WIDTH, 0)
column.Parent = gui
local columnScale = Instance.new("UIScale")
columnScale.Parent = column

export type BadgeStyle = "alert" | "done" | "info"
export type Side = {
	root: Frame,
	button: TextButton,
	setBadge: (text: string, style: BadgeStyle?) -> (),
	onActivated: (callback: () -> ()) -> (),
}
export type Options = {
	name: string,
	icon: string,
	color: Color3,
	caption: string, -- klucz tłumaczenia napisu
	key: Enum.KeyCode?, -- skrót klawiszowy (pokazany w rogu, gdy jest klawiatura)
}

local BADGE_COLORS: { [string]: Color3 } = {
	alert = Color3.fromRGB(236, 52, 52),
	done = Color3.fromRGB(64, 186, 78),
	info = Color3.fromRGB(60, 44, 34),
}

local count = 0
-- Na telefonie (mały ekran) przyciski są kwadratami z samą ikoną, w rzędzie pod „Ulepszeniami”,
-- żeby nie wchodziły na ZBIERZ i przycisk skoku
local SQUARE = 56
type Laid = { root: Frame, caption: TextLabel, icon: GuiObject, index: number }
local laid: { Laid } = {}

local function layout()
	local scale = UiScale.get()
	local small = UiScale.isSmall()
	columnScale.Scale = scale
	for _, entry in laid do
		entry.caption.Visible = not small
		if small then
			entry.root.Size = UDim2.fromOffset(SQUARE, SQUARE)
			entry.root.Position = UDim2.fromOffset((entry.index - 1) * (SQUARE + GAP), 0)
			entry.icon.Size = UDim2.fromOffset(SQUARE - 8, SQUARE - 8)
			entry.icon.AnchorPoint = Vector2.new(0.5, 0.5)
			entry.icon.Position = UDim2.fromScale(0.5, 0.5)
		else
			entry.root.Size = UDim2.fromOffset(WIDTH, HEIGHT)
			entry.root.Position = UDim2.fromOffset(0, (entry.index - 1) * (HEIGHT + GAP))
			entry.icon.Size = UDim2.fromOffset(64, 64)
			entry.icon.AnchorPoint = Vector2.new(0, 0.5)
			entry.icon.Position = UDim2.new(0, -12, 0.5, -3)
		end
	end
	column.Size = if small
		then UDim2.fromOffset(count * (SQUARE + GAP) - GAP, SQUARE)
		else UDim2.fromOffset(WIDTH, count * (HEIGHT + GAP))
	column.Position = UDim2.new(1, -16, 0.42, math.floor((UPGRADES_HALF + 14) * scale))
end

local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function text(parent: Instance, name: string, size: UDim2, position: UDim2, maxSize: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = size
	l.Position = position
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextColor3 = Color3.fromRGB(255, 252, 240)
	l.TextScaled = true
	l.Parent = parent
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = maxSize
	c.Parent = l
	return l
end

function SideButtons.add(options: Options): Side
	count += 1
	local root = Instance.new("Frame")
	root.Name = options.name
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(WIDTH, HEIGHT)
	root.Position = UDim2.fromOffset(0, (count - 1) * (HEIGHT + GAP))
	root.Parent = column

	local button = Instance.new("TextButton")
	button.Name = "Button"
	button.Size = UDim2.fromScale(1, 1)
	button.Text = ""
	button.ClipsDescendants = true
	button.Parent = root
	local buttonStroke = UiKit.button(button, options.color, { stroke = 3, radius = UDim.new(0, 14), gloss = true })
	buttonStroke.Color = OUTLINE
	local caption = text(button, "Caption", UDim2.new(1, -66, 0.68, 0), UDim2.new(0, 58, 0.16, 0), 23)
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.ZIndex = 3
	UiKit.outline(caption, 2.5)

	-- Duża ikona wystaje w lewo poza przycisk i lekko się kołysze
	local icon = UiKit.icon(options.icon, root, UDim2.fromOffset(64, 64), UDim2.new(0, -12, 0.5, -3), Vector2.new(0, 0.5))
	icon.ZIndex = 5
	local iconScale = Instance.new("UIScale")
	iconScale.Parent = icon
	TweenService:Create(icon, TweenInfo.new(1.1 + count * 0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Rotation = 6,
	}):Play()

	-- Klawisz w lewym górnym rogu
	if options.key and UserInputService.KeyboardEnabled then
		local keycap = Instance.new("Frame")
		keycap.Name = "Keycap"
		keycap.Size = UDim2.fromOffset(26, 26)
		keycap.Position = UDim2.fromOffset(-18, -12)
		keycap.Rotation = -10
		keycap.BackgroundColor3 = Color3.fromRGB(250, 250, 250)
		keycap.ZIndex = 6
		keycap.Parent = root
		corner(keycap, UDim.new(0, 7))
		stroke(keycap, OUTLINE, 2.5)
		local keyLabel = text(keycap, "Key", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), 17)
		keyLabel.Text = string.sub(options.key.Name, 1, 1)
		keyLabel.TextColor3 = OUTLINE
		keyLabel.ZIndex = 7
	end

	-- Plakietka w prawym górnym rogu: „2/3”, „53%”, „NEW”
	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.AutomaticSize = Enum.AutomaticSize.X
	badge.Size = UDim2.fromOffset(28, 26)
	badge.AnchorPoint = Vector2.new(1, 0.5)
	badge.Position = UDim2.new(1, 10, 0, 2)
	badge.BackgroundColor3 = BADGE_COLORS.alert
	badge.ZIndex = 7
	badge.Visible = false
	badge.Parent = root
	corner(badge, UDim.new(1, 0))
	stroke(badge, Color3.new(1, 1, 1), 2.5)
	local badgePad = Instance.new("UIPadding")
	badgePad.PaddingLeft = UDim.new(0, 7)
	badgePad.PaddingRight = UDim.new(0, 7)
	badgePad.Parent = badge
	local badgeLabel = Instance.new("TextLabel")
	badgeLabel.Name = "Count"
	badgeLabel.BackgroundTransparency = 1
	badgeLabel.AutomaticSize = Enum.AutomaticSize.X
	badgeLabel.Size = UDim2.fromOffset(14, 26)
	badgeLabel.Font = Enum.Font.FredokaOne
	badgeLabel.TextSize = 17
	badgeLabel.TextColor3 = Color3.new(1, 1, 1)
	badgeLabel.ZIndex = 8
	badgeLabel.Parent = badge
	local badgeScale = Instance.new("UIScale")
	badgeScale.Parent = badge
	local pulse: Tween? = nil

	local side: Side
	local callbacks: { () -> () } = {}
	local function activate()
		TweenService:Create(iconScale, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Scale = 1.3 }):Play()
		task.delay(0.12, function()
			TweenService:Create(iconScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end)
		for _, callback in callbacks do
			task.spawn(callback)
		end
	end
	button.Activated:Connect(activate)
	button.MouseEnter:Connect(function()
		TweenService:Create(iconScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.18 }):Play()
		UiKit.sweep(button)
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(iconScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
	end)
	if options.key then
		ContextActionService:BindAction("Toggle" .. options.name, function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				activate()
			end
			return Enum.ContextActionResult.Sink
		end, false, options.key)
	end

	local function renderCaption()
		caption.Text = Localize.t(options.caption)
	end
	renderCaption()
	Localize.onChanged(renderCaption)

	table.insert(laid, { root = root, caption = caption, icon = icon, index = count })
	side = {
		root = root,
		button = button,
		setBadge = function(value: string, style: BadgeStyle?)
			local kind = style or "alert"
			badge.Visible = value ~= ""
			badgeLabel.Text = value
			badge.BackgroundColor3 = BADGE_COLORS[kind]
			-- Pulsuje tylko, gdy coś czeka na gracza
			if kind == "alert" and value ~= "" then
				if not pulse then
					local tween = TweenService:Create(badgeScale, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.15 })
					tween:Play()
					pulse = tween
				end
			elseif pulse then
				pulse:Cancel()
				pulse = nil
				badgeScale.Scale = 1
			end
		end,
		onActivated = function(callback: () -> ())
			table.insert(callbacks, callback)
		end,
	}
	layout()
	return side
end

UiScale.onChanged(layout)

return SideButtons
