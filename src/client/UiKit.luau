--!strict
-- Wspólny wygląd przycisków i ikon interfejsu.
--   Ikony: jeden arkusz PNG z Figmy (assets/ui-icons.png, 5 x 4 pola po 204 px), wycinany przez
--   ImageRectOffset. Dopóki w Config.UiIcons.sheet nie ma numeru obrazka, pokazujemy emoji.
--   Przyciski: „cukierkowy” styl — jaśniejsza góra, ciemniejszy dół, gruba obwódka w kolorze
--   przycisku, połysk na górze i wciśnięcie przy kliknięciu.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)

local UiKit = {}

-- Kolejność pól w arkuszu (wiersz po wierszu), tak jak w ramce „sprite/ui-icons” w Figmie
local ORDER = {
	"coin", "mushroom", "basket", "lantern", "globe",
	"shop", "close", "sell", "oil", "bottle",
	"boots", "lock", "crystal", "pack", "rushwick",
	"creel", "rescue", "boom", "dry", "luck",
}
local INDEX: { [string]: number } = {}
for i, name in ORDER do
	INDEX[name] = i - 1
end

local FALLBACK: { [string]: string } = {
	coin = "💰", mushroom = "🍄", basket = "🧺", lantern = "🏮", globe = "🌐",
	shop = "🛒", close = "✕", sell = "💰", oil = "🛢️", bottle = "🛢️",
	boots = "🥾", lock = "🔒", crystal = "💎", pack = "🎒", rushwick = "🕯️",
	creel = "🧺", rescue = "💾", boom = "🍄", dry = "⚡", luck = "🍀",
	-- Tych nie ma jeszcze w arkuszu z Figmy: zawsze emoji
	beds = "🌱", fertilizer = "🧪", knife = "🔪",
	book = "📖", scroll = "📜", trophy = "🏆", gift = "🎁", dice = "🎲",
}

UiKit.COLORS = {
	amber = Color3.fromRGB(240, 150, 40),
	green = Color3.fromRGB(46, 184, 96),
	wood = Color3.fromRGB(110, 74, 44),
	red = Color3.fromRGB(214, 72, 56),
	moss = Color3.fromRGB(78, 120, 58),
	locked = Color3.fromRGB(96, 82, 70),
}

local function sheet(): string
	local def = Config.UiIcons
	return if def and def.sheet ~= "" then def.sheet else ""
end

function UiKit.hasSheet(): boolean
	return sheet() ~= ""
end

local function applyIcon(image: ImageLabel, name: string)
	local index = INDEX[name] or 0
	local cell = Config.UiIcons.cell
	local columns = Config.UiIcons.columns
	image.Image = sheet()
	image.ImageRectOffset = Vector2.new((index % columns) * cell + 2, (index // columns) * cell + 2)
	image.ImageRectSize = Vector2.new(cell - 4, cell - 4)
end

-- Ikona: ImageLabel z arkusza albo emoji (TextLabel), gdy arkusza jeszcze nie ma
function UiKit.icon(name: string, parent: Instance, size: UDim2, position: UDim2, anchor: Vector2?): GuiObject
	local object: GuiObject
	if UiKit.hasSheet() and INDEX[name] ~= nil then
		local image = Instance.new("ImageLabel")
		image.ScaleType = Enum.ScaleType.Fit
		applyIcon(image, name)
		object = image
	else
		local label = Instance.new("TextLabel")
		label.Text = FALLBACK[name] or "⭐"
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = Color3.new(1, 1, 1)
		object = label
	end
	object.Name = "Icon"
	object.BackgroundTransparency = 1
	object.Size = size
	object.Position = position
	object.AnchorPoint = anchor or Vector2.zero
	object.ZIndex = 3
	object.Parent = parent
	return object
end

function UiKit.setIcon(object: GuiObject, name: string)
	if object:IsA("ImageLabel") then
		applyIcon(object, name)
	elseif object:IsA("TextLabel") then
		object.Text = FALLBACK[name] or "⭐"
	end
end

function UiKit.setIconTransparency(object: GuiObject, transparency: number)
	if object:IsA("ImageLabel") then
		object.ImageTransparency = transparency
	elseif object:IsA("TextLabel") then
		object.TextTransparency = transparency
	end
end

local function darker(color: Color3, amount: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, math.min(1, s * 1.1), v * (1 - amount))
end
UiKit.darker = darker

-- UIScale, którą dzielą: wciśnięcie, podskok (Hud.pop) i skala ekranu (atrybut Base)
local function scaleOf(target: GuiObject): UIScale
	local existing = target:FindFirstChildOfClass("UIScale")
	if existing then
		return existing
	end
	local created = Instance.new("UIScale")
	created.Parent = target
	return created
end

export type Style = {
	gloss: boolean?, -- połysk na górze (bez tekstu na przycisku wygląda najlepiej)
	radius: UDim?,
	stroke: number?,
}

-- Cukierkowy przycisk w kolorze `color`. Zwraca obwódkę (żeby dało się ją przygasić).
function UiKit.button(button: GuiButton, color: Color3, style: Style?): UIStroke
	local options: Style = style or {}
	button.BackgroundColor3 = color
	button.BackgroundTransparency = 0
	button.AutoButtonColor = false
	button.BorderSizePixel = 0

	local corner = button:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	corner.CornerRadius = options.radius or UDim.new(0, 10)
	corner.Parent = button

	local gradient = Instance.new("UIGradient")
	gradient.Name = "Shade"
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(235, 235, 235)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 190, 190)),
	})
	gradient.Parent = button

	local stroke = button:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = darker(color, 0.5)
	stroke.Thickness = options.stroke or 2.5
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = button

	if button:IsA("TextButton") then
		button.TextColor3 = Color3.fromRGB(255, 252, 240)
		button.TextStrokeColor3 = darker(color, 0.65)
		button.TextStrokeTransparency = 0.35
	end

	if options.gloss then
		local gloss = Instance.new("Frame")
		gloss.Name = "Gloss"
		gloss.BackgroundColor3 = Color3.new(1, 1, 1)
		gloss.BackgroundTransparency = 0.72
		gloss.BorderSizePixel = 0
		gloss.Size = UDim2.new(1, -10, 0.4, 0)
		gloss.Position = UDim2.new(0, 5, 0, 3)
		gloss.ZIndex = 2
		gloss.Active = false
		gloss.Parent = button
		local glossCorner = Instance.new("UICorner")
		glossCorner.CornerRadius = options.radius or UDim.new(0, 8)
		glossCorner.Parent = gloss
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new(0, 1)
		fade.Parent = gloss
	end

	-- Wciśnięcie i najechanie myszką
	local scale = scaleOf(button)
	local pressed = false
	local function base(): number
		return (scale:GetAttribute("Base") :: number?) or 1
	end
	local function to(value: number, time: number)
		TweenService:Create(scale, TweenInfo.new(time, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = value }):Play()
	end
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if button.Active then
				pressed = true
				TweenService:Create(scale, TweenInfo.new(0.06), { Scale = base() * 0.9 }):Play()
			end
		elseif input.UserInputType == Enum.UserInputType.MouseMovement and button.Active then
			stroke.Thickness = (options.stroke or 2.5) + 1
			gradient.Offset = Vector2.new(0, -0.15)
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if pressed then
				pressed = false
				to(base(), 0.25)
			end
		elseif input.UserInputType == Enum.UserInputType.MouseMovement then
			stroke.Thickness = options.stroke or 2.5
			gradient.Offset = Vector2.zero
			if pressed then
				pressed = false
				to(base(), 0.2)
			end
		end
	end)
	return stroke
end

-- Zmiana koloru przycisku już ostylowanego (np. karta stać / nie stać)
function UiKit.recolor(button: GuiButton, color: Color3)
	button.BackgroundColor3 = color
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = darker(color, 0.5)
	end
	if button:IsA("TextButton") then
		button.TextStrokeColor3 = darker(color, 0.65)
	end
end

return UiKit
