--!strict
-- Wspólny wygląd przycisków i ikon interfejsu.
--   Ikony: arkusze PNG z Figmy (assets/ui-icons.png 5 x 4 i assets/ui-icons-2.png 5 x 2, pola po 204 px),
--   wycinane przez ImageRectOffset. Dopóki arkusz nie ma numeru obrazka w Config, pokazujemy emoji.
--   Przyciski: „cukierkowy” styl — jaśniejsza góra, ciemniejszy dół, gruba obwódka w kolorze
--   przycisku, połysk na górze i wciśnięcie przy kliknięciu.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)

local UiKit = {}

-- Kolejność pól w arkuszach (wiersz po wierszu), tak jak w ramkach „sprite/ui-icons” i
-- „sprite/ui-icons-2” w Figmie
local SHEETS = {
	{
		def = "UiIcons",
		order = {
			"coin", "mushroom", "basket", "lantern", "globe",
			"shop", "close", "sell", "oil", "bottle",
			"boots", "lock", "crystal", "pack", "rushwick",
			"creel", "rescue", "boom", "dry", "luck",
		},
	},
	{
		def = "UiIcons2",
		order = {
			"upgrade", "knife", "beds", "fertilizer", "coins",
			"check", "star", "chest", "moon", "sparkles",
		},
	},
}
-- nazwa ikony -> (numer arkusza, pole w arkuszu)
local LOOKUP: { [string]: { sheet: number, index: number } } = {}
for sheetIndex, def in SHEETS do
	for i, name in def.order do
		LOOKUP[name] = { sheet = sheetIndex, index = i - 1 }
	end
end

local FALLBACK: { [string]: string } = {
	coin = "💰", mushroom = "🍄", basket = "🧺", lantern = "🏮", globe = "🌐",
	shop = "🛒", close = "✕", sell = "💰", oil = "🛢️", bottle = "🛢️",
	boots = "🥾", lock = "🔒", crystal = "💎", pack = "🎒", rushwick = "🕯️",
	creel = "🧺", rescue = "💾", boom = "🍄", dry = "⚡", luck = "🍀",
	upgrade = "⬆️", knife = "🔪", beds = "🌱", fertilizer = "🧪", coins = "💰",
	check = "✅", star = "⭐", chest = "🧰", moon = "🌙", sparkles = "✨",
	book = "📖", scroll = "📜", trophy = "🏆", gift = "🎁", dice = "🎲",
	music = "🎵", sound = "🔊", soundOff = "🔇", invite = "👥",
}

UiKit.COLORS = {
	amber = Color3.fromRGB(240, 150, 40),
	green = Color3.fromRGB(46, 184, 96),
	wood = Color3.fromRGB(110, 74, 44),
	red = Color3.fromRGB(214, 72, 56),
	moss = Color3.fromRGB(78, 120, 58),
	locked = Color3.fromRGB(96, 82, 70),
}

type SheetDef = { sheet: string, cell: number, columns: number }

local function sheetDef(index: number): SheetDef?
	local def = (Config :: any)[SHEETS[index].def] :: SheetDef?
	if def and def.sheet ~= "" then
		return def
	end
	return nil
end

function UiKit.hasSheet(): boolean
	return sheetDef(1) ~= nil
end

-- Czy ikona ma obrazek (jej arkusz jest już wgrany)
function UiKit.hasImage(name: string): boolean
	local entry = LOOKUP[name]
	return entry ~= nil and sheetDef(entry.sheet) ~= nil
end

local function applyIcon(image: ImageLabel, name: string)
	local entry = LOOKUP[name] or LOOKUP.coin
	local def = sheetDef(entry.sheet) :: SheetDef
	image.Image = def.sheet
	image.ImageRectOffset = Vector2.new((entry.index % def.columns) * def.cell + 2, (entry.index // def.columns) * def.cell + 2)
	image.ImageRectSize = Vector2.new(def.cell - 4, def.cell - 4)
end

-- Ikona: ImageLabel z arkusza albo emoji (TextLabel), gdy arkusza jeszcze nie ma
function UiKit.icon(name: string, parent: Instance, size: UDim2, position: UDim2, anchor: Vector2?): GuiObject
	local object: GuiObject
	if UiKit.hasImage(name) then
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
	if object:IsA("ImageLabel") and UiKit.hasImage(name) then
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

-- ===== Wspólne efekty kreskówkowego interfejsu =====

UiKit.OUTLINE = Color3.fromRGB(43, 27, 18)

-- Gruba ciemna obwódka wokół tekstu (jak napisy w grach-symulatorach)
function UiKit.outline(label: TextLabel | TextButton, thickness: number?, color: Color3?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Thickness = thickness or 2
	stroke.Color = color or UiKit.OUTLINE
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	return stroke
end

-- Wybuch iskierek w punkcie `at` (współrzędne ekranu, jak AbsolutePosition) na warstwie `layer`
function UiKit.burst(layer: Instance, at: Vector2, count: number?, colors: { Color3 }?)
	local palette = colors or { Color3.fromRGB(255, 232, 110), Color3.fromRGB(255, 255, 255), Color3.fromRGB(140, 240, 120) }
	local n = count or 10
	for i = 1, n do
		local spark = Instance.new("Frame")
		spark.Name = "Spark"
		local size = math.random(8, 14)
		spark.Size = UDim2.fromOffset(size, size)
		spark.AnchorPoint = Vector2.new(0.5, 0.5)
		spark.Position = UDim2.fromOffset(at.X, at.Y)
		spark.Rotation = 45
		spark.BorderSizePixel = 0
		spark.BackgroundColor3 = palette[(i - 1) % #palette + 1]
		spark.ZIndex = 50
		spark.Parent = layer
		local stroke = Instance.new("UIStroke")
		stroke.Color = UiKit.OUTLINE
		stroke.Thickness = 1.5
		stroke.Parent = spark
		local angle = (i / n) * math.pi * 2 + math.random() * 0.5
		local distance = math.random(50, 95)
		local target = at + Vector2.new(math.cos(angle) * distance, math.sin(angle) * distance)
		local tween = TweenService:Create(spark, TweenInfo.new(0.55, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(target.X, target.Y),
			Size = UDim2.fromOffset(0, 0),
			Rotation = 45 + math.random(-120, 120),
		})
		tween.Completed:Connect(function()
			spark:Destroy()
		end)
		tween:Play()
	end
end

-- Potrząśnięcie w bok (np. gdy nie stać na ulepszenie)
function UiKit.shake(target: GuiObject)
	local origin = target:GetAttribute("ShakeOrigin")
	if typeof(origin) ~= "UDim2" then
		origin = target.Position
		target:SetAttribute("ShakeOrigin", origin)
	end
	local base = origin :: UDim2
	task.spawn(function()
		for _, dx in { -8, 7, -5, 4, -2, 0 } do
			target.Position = base + UDim2.fromOffset(dx, 0)
			task.wait(0.04)
		end
		target.Position = base
	end)
end

-- Błysk przesuwający się po przycisku (biały pas po skosie). Przycisk musi mieć ClipsDescendants.
function UiKit.sweep(target: GuiObject)
	local band = Instance.new("Frame")
	band.Name = "Sweep"
	band.Size = UDim2.new(0.35, 0, 2, 0)
	band.AnchorPoint = Vector2.new(0.5, 0.5)
	band.Position = UDim2.fromScale(-0.3, 0.5)
	band.Rotation = 20
	band.BorderSizePixel = 0
	band.BackgroundColor3 = Color3.new(1, 1, 1)
	band.BackgroundTransparency = 0.55
	band.ZIndex = 4
	band.Parent = target
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	fade.Parent = band
	local tween = TweenService:Create(band, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { Position = UDim2.fromScale(1.3, 0.5) })
	tween.Completed:Connect(function()
		band:Destroy()
	end)
	tween:Play()
end

return UiKit
