--!strict
-- Wspólny wygląd dużych okien (jak panel ulepszeń): przyciemnienie za oknem, okno z ciemnego
-- drewna z grubą obwódką i jaśniejszą linią w środku, kolorowa wstążka z tytułem i ikoną na górze,
-- czerwony przycisk zamykania w rogu, pigułka z informacją po lewej i zakładki-pigułki.
-- Okno wskakuje z podskokiem, a kliknięcie obok je zamyka.

local TweenService = game:GetService("TweenService")

local UiKit = require(script.Parent.UiKit)

local PanelKit = {}

type Fit = { width: number, height: number, set: (number) -> () }
local windows: { Fit } = {}
-- Otwarte może być tylko jedno okno naraz: otwarcie jednego zamyka resztę (też panel ulepszeń w Hud)
local closers: { () -> () } = {}
local openListeners: { () -> () } = {}

PanelKit.OUTLINE = UiKit.OUTLINE
-- Tło okien: ciemne drewno (kremowe wyglądało w grze na białe), ciemniejsze ku dołowi
PanelKit.BG = Color3.fromRGB(88, 58, 38)
PanelKit.BG_DARK = Color3.fromRGB(62, 40, 27)
PanelKit.LINE = Color3.fromRGB(146, 104, 64)
PanelKit.CARD = Color3.fromRGB(116, 80, 52)
PanelKit.TEXT = Color3.fromRGB(255, 244, 222)
PanelKit.MUTED = Color3.fromRGB(226, 196, 156)
PanelKit.GOLD = Color3.fromRGB(255, 208, 72)
PanelKit.GREEN = Color3.fromRGB(122, 230, 96)
PanelKit.VIOLET = Color3.fromRGB(140, 86, 236)
PanelKit.TAB = Color3.fromRGB(74, 50, 34)
PanelKit.TAB_ON = Color3.fromRGB(140, 86, 236)
PanelKit.TITLE_FONT = Enum.Font.FredokaOne
PanelKit.BODY_FONT = Enum.Font.GothamBold

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
PanelKit.corner = corner
PanelKit.stroke = stroke

-- Napis z grubym obrysem (jak w kartach ulepszeń)
function PanelKit.label(parent: Instance, name: string, size: UDim2, position: UDim2, maxSize: number, color: Color3?, font: Enum.Font?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = size
	l.Position = position
	l.BackgroundTransparency = 1
	l.Font = font or PanelKit.TITLE_FONT
	l.TextColor3 = color or PanelKit.TEXT
	l.TextScaled = true
	l.RichText = true
	l.Parent = parent
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = maxSize
	c.Parent = l
	return l
end

-- Tło okna (też dla panelu ulepszeń): kolor i pionowy cień
function PanelKit.paint(frame: Frame)
	frame.BackgroundColor3 = PanelKit.BG
	local shade = frame:FindFirstChild("Shade")
	if not shade then
		local gradient = Instance.new("UIGradient")
		gradient.Name = "Shade"
		gradient.Rotation = 90
		gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(176, 170, 166))
		gradient.Parent = frame
	end
end

export type Window = {
	gui: ScreenGui,
	dim: TextButton,
	frame: Frame,
	scale: UIScale,
	title: TextLabel,
	close: TextButton,
	pill: Frame,
	pillText: TextLabel,
	content: Frame,
	isOpen: () -> boolean,
	setOpen: (boolean) -> (),
	onToggle: (callback: (boolean) -> ()) -> (),
}

export type WindowOptions = {
	name: string,
	parent: Instance,
	width: number,
	height: number,
	ribbon: Color3?, -- kolor wstążki z tytułem
	icon: string, -- ikona z arkusza UiKit na wstążce
	pillIcon: string?, -- ikona w pigułce po lewej (np. monety, płomień serii)
	pillColor: Color3?,
	displayOrder: number?,
}

function PanelKit.window(options: WindowOptions): Window
	local gui = Instance.new("ScreenGui")
	gui.Name = options.name
	gui.ResetOnSpawn = false
	gui.DisplayOrder = options.displayOrder or 6
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = options.parent

	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.Visible = false
	dim.Parent = gui

	local frame = Instance.new("Frame")
	frame.Name = "Window"
	frame.Size = UDim2.fromOffset(options.width, options.height)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.53)
	frame.Visible = false
	frame.ZIndex = 2
	frame.Parent = gui
	PanelKit.paint(frame)
	corner(frame, UDim.new(0, 26))
	stroke(frame, PanelKit.OUTLINE, 4)
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	local inner = Instance.new("Frame")
	inner.Name = "Inner"
	inner.Size = UDim2.new(1, -14, 1, -14)
	inner.Position = UDim2.fromOffset(7, 7)
	inner.BackgroundTransparency = 1
	inner.Parent = frame
	corner(inner, UDim.new(0, 21))
	stroke(inner, PanelKit.LINE, 2)

	-- Wstążka z tytułem
	local ribbon = Instance.new("Frame")
	ribbon.Name = "Ribbon"
	ribbon.Size = UDim2.fromOffset(280, 56)
	ribbon.AnchorPoint = Vector2.new(0.5, 0.5)
	ribbon.Position = UDim2.fromScale(0.5, 0)
	ribbon.BackgroundColor3 = options.ribbon or PanelKit.VIOLET
	ribbon.ZIndex = 6
	ribbon.Parent = frame
	corner(ribbon, UDim.new(0, 16))
	stroke(ribbon, PanelKit.OUTLINE, 3.5)
	local ribbonShade = Instance.new("UIGradient")
	ribbonShade.Rotation = 90
	ribbonShade.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(196, 196, 196))
	ribbonShade.Parent = ribbon
	local title = PanelKit.label(ribbon, "Title", UDim2.new(1, -70, 1, -12), UDim2.fromOffset(56, 6), 32)
	title.ZIndex = 7
	UiKit.outline(title, 3)
	local titleIcon = UiKit.icon(options.icon, ribbon, UDim2.fromOffset(62, 62), UDim2.new(0, -14, 0.5, -4), Vector2.new(0, 0.5))
	titleIcon.Rotation = -12
	titleIcon.ZIndex = 8

	-- Pigułka z informacją w lewym górnym rogu
	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.Size = UDim2.fromOffset(128, 40)
	pill.Position = UDim2.fromOffset(26, -20)
	pill.BackgroundColor3 = options.pillColor or Color3.fromRGB(52, 38, 30)
	pill.ZIndex = 6
	pill.Parent = frame
	corner(pill, UDim.new(1, 0))
	stroke(pill, PanelKit.OUTLINE, 3)
	if options.pillIcon then
		local pillIcon = UiKit.icon(options.pillIcon, pill, UDim2.fromOffset(44, 44), UDim2.new(0, -18, 0.5, 0), Vector2.new(0, 0.5))
		pillIcon.ZIndex = 7
	end
	local pillText = PanelKit.label(pill, "Text", UDim2.new(1, -44, 1, -10), UDim2.fromOffset(32, 5), 22, PanelKit.GREEN)
	pillText.TextXAlignment = Enum.TextXAlignment.Left
	pillText.ZIndex = 7
	pill.Visible = options.pillIcon ~= nil

	-- Zamykanie w prawym górnym rogu
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Size = UDim2.fromOffset(52, 52)
	close.AnchorPoint = Vector2.new(0.5, 0.5)
	close.Position = UDim2.new(1, -12, 0, 6)
	close.Text = ""
	close.ZIndex = 6
	close.Parent = frame
	local closeStroke = UiKit.button(close, UiKit.COLORS.red, { stroke = 3, radius = UDim.new(0, 14), gloss = true })
	closeStroke.Color = PanelKit.OUTLINE
	local closeIcon = UiKit.icon("close", close, UDim2.fromScale(0.72, 0.72), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	closeIcon.ZIndex = 7
	close.MouseEnter:Connect(function()
		TweenService:Create(closeIcon, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Rotation = 90 }):Play()
	end)
	close.MouseLeave:Connect(function()
		TweenService:Create(closeIcon, TweenInfo.new(0.2), { Rotation = 0 }):Play()
	end)

	-- Miejsce na zawartość (pod wstążką, w środku obwódki)
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.new(1, -28, 1, -50)
	content.Position = UDim2.fromOffset(14, 38)
	content.ZIndex = 3
	content.Parent = frame

	local listeners: { (boolean) -> () } = {}
	local baseScale = 1
	local window: Window
	local function setOpen(open: boolean)
		if open == frame.Visible then
			return
		end
		if open then
			for _, closeOther in closers do
				closeOther()
			end
			for _, callback in openListeners do
				task.spawn(callback)
			end
		end
		frame.Visible = open
		dim.Visible = open
		if open then
			dim.BackgroundTransparency = 1
			TweenService:Create(dim, TweenInfo.new(0.2), { BackgroundTransparency = 0.45 }):Play()
			scale.Scale = baseScale * 0.85
			TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = baseScale }):Play()
		end
		for _, callback in listeners do
			task.spawn(callback, open)
		end
	end
	dim.Activated:Connect(function()
		setOpen(false)
	end)
	close.Activated:Connect(function()
		setOpen(false)
	end)

	window = {
		gui = gui,
		dim = dim,
		frame = frame,
		scale = scale,
		title = title,
		close = close,
		pill = pill,
		pillText = pillText,
		content = content,
		isOpen = function()
			return frame.Visible
		end,
		setOpen = setOpen,
		onToggle = function(callback: (boolean) -> ())
			table.insert(listeners, callback)
		end,
	}
	table.insert(closers, function()
		setOpen(false)
	end)
	-- Skala ekranu: okno ma się zmieścić na telefonie (PanelKit.fit)
	table.insert(windows, {
		width = options.width,
		height = options.height,
		set = function(value: number)
			baseScale = value
			scale.Scale = value
		end,
	})
	local camera = workspace.CurrentCamera
	if camera then
		PanelKit.fit(camera.ViewportSize)
	end
	return window
end

-- Zamyka wszystkie okna PanelKit (np. gdy otwiera się panel ulepszeń)
function PanelKit.closeAll()
	for _, closeOne in closers do
		closeOne()
	end
end

-- Wywoływane, gdy otwiera się którekolwiek okno PanelKit (panel ulepszeń się wtedy chowa)
function PanelKit.onOpen(callback: () -> ())
	table.insert(openListeners, callback)
end

-- Dopasowanie wszystkich okien do ekranu (wywołuje się przy zmianie rozmiaru ekranu)
function PanelKit.fit(viewport: Vector2)
	for _, entry in windows do
		local fit = math.min(1, (viewport.X - 40) / entry.width, (viewport.Y - 90) / entry.height)
		entry.set(math.max(fit, 0.45))
	end
end

-- Zakładki-pigułki w rzędzie. Zwraca przyciski po id i funkcję zaznaczenia.
function PanelKit.tabs(parent: Instance, ids: { string }, width: number): ({ [string]: TextButton }, (string) -> ())
	local bar = Instance.new("Frame")
	bar.Name = "Tabs"
	bar.Size = UDim2.new(1, 0, 0, 36)
	bar.BackgroundTransparency = 1
	bar.ZIndex = 4
	bar.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = bar
	local buttons: { [string]: TextButton } = {}
	for order, id in ids do
		local button = Instance.new("TextButton")
		button.Name = "Tab_" .. id
		button.Size = UDim2.new(0, width, 1, 0)
		button.LayoutOrder = order
		button.Font = PanelKit.TITLE_FONT
		button.TextScaled = true
		button.TextColor3 = Color3.new(1, 1, 1)
		button.ZIndex = 5
		button.Parent = bar
		local tabStroke = UiKit.button(button, PanelKit.TAB, { stroke = 2.5, radius = UDim.new(1, 0) })
		tabStroke.Color = PanelKit.OUTLINE
		local constraint = Instance.new("UITextSizeConstraint")
		constraint.MaxTextSize = 17
		constraint.Parent = button
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 8)
		pad.PaddingRight = UDim.new(0, 8)
		pad.Parent = button
		buttons[id] = button
	end
	local function select(id: string)
		for other, button in buttons do
			UiKit.recolor(button, if other == id then PanelKit.TAB_ON else PanelKit.TAB)
			local tabStroke = button:FindFirstChildOfClass("UIStroke")
			if tabStroke then
				tabStroke.Color = PanelKit.OUTLINE
			end
		end
	end
	return buttons, select
end

-- Gruby pasek postępu z napisem w środku („12/30”)
function PanelKit.bar(parent: Instance, size: UDim2, position: UDim2, color: Color3): (Frame, Frame, TextLabel)
	local back = Instance.new("Frame")
	back.Name = "Bar"
	back.Size = size
	back.Position = position
	back.BackgroundColor3 = Color3.fromRGB(34, 22, 16)
	back.ZIndex = 5
	back.Parent = parent
	corner(back, UDim.new(1, 0))
	stroke(back, PanelKit.OUTLINE, 2.5)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = color
	fill.ZIndex = 6
	fill.Parent = back
	corner(fill, UDim.new(1, 0))
	local shine = Instance.new("UIGradient")
	shine.Rotation = 90
	shine.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190))
	shine.Parent = fill
	local text = PanelKit.label(back, "Text", UDim2.new(1, -10, 1, -4), UDim2.fromOffset(5, 2), 16)
	text.ZIndex = 7
	UiKit.outline(text, 2)
	return back, fill, text
end

-- Okna same dopasowują się do ekranu (telefon, zmiana rozmiaru okna)
task.defer(function()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			PanelKit.fit(camera.ViewportSize)
		end)
	end
end)

return PanelKit
