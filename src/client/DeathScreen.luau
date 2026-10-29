--!strict
-- Ekran „pochłonięcia”: zamiast zwykłego czarnego ekranu.
--   1. Ciemność zamyka się kołem do środka (jak przesłona), z błyskiem w kolorze tego, kto złapał.
--   2. W ciemności świecą oczy: strażnik ma jedną dużą parę w swoim kolorze, las / jaskinia / bagno
--      wiele małych par, które mrugają.
--   3. Latarnia w środku migocze i gaśnie z dymkiem, tytuł spada z podskokiem, pod nim utracone grzyby,
--      a na dole rada, jak tego uniknąć następnym razem.
--   4. Koło otwiera się z powrotem na chatkę / obóz.
-- Między podtytułem a radą zostaje miejsce na przycisk „Zachowaj grzyby” (ShopPanel, 58% wysokości).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Localize = require(script.Parent.Localize)
local UiKit = require(script.Parent.UiKit)
local UiScale = require(script.Parent.UiScale)

local DeathScreen = {}

local OUTLINE = UiKit.OUTLINE
local HOLD = 3.1 -- tyle trwa pełna ciemność z napisami

type Look = { color: Color3, eyes: number, big: boolean, tips: string }
-- Kto pochłonął gracza: kolor, oczy i rodzaj rad
local LOOKS: { [string]: Look } = {
	MSG_CAUGHT = { color = Color3.fromRGB(120, 235, 90), eyes = 1, big = true, tips = "GUARD" },
	MSG_CAUGHT_SKARBNIK = { color = Color3.fromRGB(255, 170, 60), eyes = 1, big = true, tips = "GUARD" },
	MSG_CAUGHT_UTOPIEC = { color = Color3.fromRGB(90, 225, 235), eyes = 1, big = true, tips = "GUARD" },
	MSG_ENGULFED = { color = Color3.fromRGB(255, 226, 90), eyes = 7, big = false, tips = "OIL" },
	MSG_ENGULFED_CAVE = { color = Color3.fromRGB(200, 120, 255), eyes = 6, big = false, tips = "OIL" },
	MSG_ENGULFED_SWAMP = { color = Color3.fromRGB(140, 255, 170), eyes = 6, big = false, tips = "OIL" },
}
local TIP_COUNT = 3

local gui = Instance.new("ScreenGui")
gui.Name = "DeathScreen"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 25 -- pod przyciskiem ratunku (30), nad resztą interfejsu
gui.Enabled = false
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

-- Błysk w kolorze łapiącego
local tint = Instance.new("Frame")
tint.Name = "Tint"
tint.Size = UDim2.fromScale(1, 1)
tint.BorderSizePixel = 0
tint.BackgroundTransparency = 1
tint.ZIndex = 1
tint.Parent = gui

-- Przesłona: przezroczyste koło z ogromną czarną obwódką zakrywa wszystko poza kołem
local iris = Instance.new("Frame")
iris.Name = "Iris"
iris.AnchorPoint = Vector2.new(0.5, 0.5)
iris.Position = UDim2.fromScale(0.5, 0.5)
iris.BackgroundTransparency = 1
iris.ZIndex = 2
iris.Parent = gui
local irisCorner = Instance.new("UICorner")
irisCorner.CornerRadius = UDim.new(0.5, 0)
irisCorner.Parent = iris
local irisStroke = Instance.new("UIStroke")
irisStroke.Color = Color3.new(0, 0, 0)
irisStroke.Thickness = 2400
irisStroke.Parent = iris
-- Miękka krawędź koła
local soft = Instance.new("Frame")
soft.Name = "Soft"
soft.AnchorPoint = Vector2.new(0.5, 0.5)
soft.Position = UDim2.fromScale(0.5, 0.5)
soft.Size = UDim2.fromScale(1, 1)
soft.BackgroundTransparency = 1
soft.ZIndex = 2
soft.Parent = iris
local softCorner = Instance.new("UICorner")
softCorner.CornerRadius = UDim.new(0.5, 0)
softCorner.Parent = soft
local softStroke = Instance.new("UIStroke")
softStroke.Color = Color3.new(0, 0, 0)
softStroke.Thickness = 70
softStroke.Transparency = 0.45
softStroke.Parent = soft

-- Pełna czerń, gdy koło się zamknie (obwódka ma swój limit na bardzo dużych ekranach)
local black = Instance.new("Frame")
black.Name = "Black"
black.Size = UDim2.fromScale(1, 1)
black.BackgroundColor3 = Color3.new(0, 0, 0)
black.BorderSizePixel = 0
black.BackgroundTransparency = 1
black.ZIndex = 3
black.Parent = gui

local content = Instance.new("Frame")
content.Name = "Content"
content.Size = UDim2.fromScale(1, 1)
content.BackgroundTransparency = 1
content.ZIndex = 4
content.Parent = gui
local contentScale = Instance.new("UIScale")
contentScale.Parent = content

local function text(name: string, size: UDim2, position: UDim2, maxSize: number, font: Enum.Font?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = size
	l.Position = position
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.BackgroundTransparency = 1
	l.Font = font or Enum.Font.FredokaOne
	l.TextScaled = true
	l.RichText = true
	l.TextColor3 = Color3.new(1, 1, 1)
	l.ZIndex = 7
	l.Parent = content
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = maxSize
	c.Parent = l
	return l
end

local title = text("Title", UDim2.new(0.9, 0, 0, 64), UDim2.fromScale(0.5, 0.45), 56)
local titleStroke = UiKit.outline(title, 4)
local titleScale = Instance.new("UIScale")
titleScale.Parent = title
local subtitle = text("Subtitle", UDim2.new(0.8, 0, 0, 30), UDim2.fromScale(0.5, 0.515), 26, Enum.Font.GothamBold)
subtitle.TextColor3 = Color3.fromRGB(230, 206, 180)
local subtitleStroke = UiKit.outline(subtitle, 2)

local tip = Instance.new("Frame")
tip.Name = "Tip"
tip.AnchorPoint = Vector2.new(0.5, 0.5)
tip.Position = UDim2.fromScale(0.5, 0.84)
tip.Size = UDim2.fromOffset(560, 54)
tip.BackgroundColor3 = Color3.fromRGB(46, 32, 24)
tip.ZIndex = 6
tip.Parent = content
local tipCorner = Instance.new("UICorner")
tipCorner.CornerRadius = UDim.new(0, 16)
tipCorner.Parent = tip
local tipStroke = Instance.new("UIStroke")
tipStroke.Color = OUTLINE
tipStroke.Thickness = 3
tipStroke.Parent = tip
local tipIcon = UiKit.icon("lantern", tip, UDim2.fromOffset(44, 44), UDim2.new(0, -10, 0.5, 0), Vector2.new(0, 0.5))
tipIcon.ZIndex = 8
local tipText = Instance.new("TextLabel")
tipText.Name = "Text"
tipText.BackgroundTransparency = 1
tipText.Size = UDim2.new(1, -60, 1, -10)
tipText.Position = UDim2.fromOffset(44, 5)
tipText.Font = Enum.Font.GothamBold
tipText.TextScaled = true
tipText.RichText = true
tipText.TextColor3 = Color3.fromRGB(255, 236, 200)
tipText.TextXAlignment = Enum.TextXAlignment.Left
tipText.ZIndex = 8
tipText.Parent = tip
local tipConstraint = Instance.new("UITextSizeConstraint")
tipConstraint.MaxTextSize = 18
tipConstraint.Parent = tipText

-- Latarnia nad tytułem: migocze i gaśnie
local lantern = UiKit.icon("lantern", content, UDim2.fromOffset(96, 96), UDim2.fromScale(0.5, 0.34), Vector2.new(0.5, 0.5))
lantern.ZIndex = 7
local glow = Instance.new("Frame")
glow.Name = "Glow"
glow.AnchorPoint = Vector2.new(0.5, 0.5)
glow.Position = UDim2.fromScale(0.5, 0.34)
glow.Size = UDim2.fromOffset(150, 150)
glow.BackgroundColor3 = Color3.fromRGB(255, 190, 80)
glow.BackgroundTransparency = 1
glow.ZIndex = 6
glow.Parent = content
local glowCorner = Instance.new("UICorner")
glowCorner.CornerRadius = UDim.new(0.5, 0)
glowCorner.Parent = glow

local eyesLayer = Instance.new("Frame")
eyesLayer.Name = "Eyes"
eyesLayer.Size = UDim2.fromScale(1, 1)
eyesLayer.BackgroundTransparency = 1
eyesLayer.ZIndex = 5
eyesLayer.Parent = gui

local token = 0

local function setTransparency(value: number)
	title.TextTransparency = value
	titleStroke.Transparency = value
	subtitle.TextTransparency = value
	subtitleStroke.Transparency = value
	tip.BackgroundTransparency = value
	tipStroke.Transparency = value
	tipText.TextTransparency = value
	UiKit.setIconTransparency(tipIcon, value)
end

local function tween(target: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local t = TweenService:Create(target, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

-- Para oczu: dwa świecące owale, które mrugają (skalowanie w pionie)
local function eyePair(position: UDim2, width: number, color: Color3, delay: number, current: number)
	local pair = Instance.new("Frame")
	pair.Name = "Pair"
	pair.AnchorPoint = Vector2.new(0.5, 0.5)
	pair.Position = position
	pair.Size = UDim2.fromOffset(width * 3, width)
	pair.BackgroundTransparency = 1
	pair.ZIndex = 5
	pair.Parent = eyesLayer
	local eyes: { Frame } = {}
	for side = 0, 1 do
		local eye = Instance.new("Frame")
		eye.AnchorPoint = Vector2.new(0.5, 0.5)
		eye.Position = UDim2.fromScale(if side == 0 then 0.2 else 0.8, 0.5)
		eye.Size = UDim2.fromOffset(width, 0)
		eye.BackgroundColor3 = color
		eye.BorderSizePixel = 0
		eye.Rotation = if side == 0 then 12 else -12
		eye.ZIndex = 5
		eye.Parent = pair
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = eye
		local halo = Instance.new("UIStroke")
		halo.Color = color
		halo.Thickness = math.max(2, width * 0.18)
		halo.Transparency = 0.55
		halo.Parent = eye
		table.insert(eyes, eye)
	end
	task.delay(delay, function()
		if token ~= current then
			return
		end
		for _, eye in eyes do
			tween(eye, 0.25, { Size = UDim2.fromOffset(width, width * 0.55) }, Enum.EasingStyle.Back)
		end
		-- Mrugnięcie
		task.wait(0.6 + math.random() * 0.8)
		if token ~= current then
			return
		end
		for _, eye in eyes do
			tween(eye, 0.08, { Size = UDim2.fromOffset(width, 2) })
		end
		task.wait(0.12)
		if token ~= current then
			return
		end
		for _, eye in eyes do
			tween(eye, 0.12, { Size = UDim2.fromOffset(width, width * 0.55) })
		end
	end)
end

-- Dymek nad zgaszoną latarnią
local function smoke(current: number)
	for i = 1, 5 do
		task.delay(i * 0.12, function()
			if token ~= current then
				return
			end
			local puff = Instance.new("Frame")
			puff.AnchorPoint = Vector2.new(0.5, 0.5)
			puff.Position = UDim2.new(0.5, math.random(-8, 8), 0.34, -30)
			puff.Size = UDim2.fromOffset(14, 14)
			puff.BackgroundColor3 = Color3.fromRGB(150, 150, 150)
			puff.BackgroundTransparency = 0.35
			puff.ZIndex = 8
			puff.Parent = content
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0.5, 0)
			c.Parent = puff
			local rise = tween(puff, 1.1, {
				Position = UDim2.new(0.5, math.random(-30, 30), 0.34, -90),
				Size = UDim2.fromOffset(34, 34),
				BackgroundTransparency = 1,
			}, Enum.EasingStyle.Sine)
			rise.Completed:Connect(function()
				puff:Destroy()
			end)
		end)
	end
end

-- Miejsca na małe oczy: dookoła, z dala od napisów w środku
local EYE_SPOTS = {
	Vector2.new(0.12, 0.2), Vector2.new(0.86, 0.16), Vector2.new(0.2, 0.62), Vector2.new(0.8, 0.66),
	Vector2.new(0.08, 0.42), Vector2.new(0.93, 0.44), Vector2.new(0.3, 0.12), Vector2.new(0.7, 0.1),
	Vector2.new(0.16, 0.8), Vector2.new(0.86, 0.84),
}

function DeathScreen.show(key: string, titleText: string, subtitleText: string)
	token += 1
	local current = token
	local look = LOOKS[key] or LOOKS.MSG_ENGULFED
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local full = math.max(viewport.X, viewport.Y) * 1.3
	contentScale.Scale = UiScale.get()

	for _, child in eyesLayer:GetChildren() do
		child:Destroy()
	end
	gui.Enabled = true
	title.Text = titleText
	title.TextColor3 = look.color:Lerp(Color3.fromRGB(255, 80, 60), if look.big then 0.25 else 0.6)
	subtitle.Text = subtitleText
	tipText.Text = Localize.t("DEATH_TIP_" .. look.tips .. "_" .. math.random(1, TIP_COUNT))
	setTransparency(1)
	UiKit.setIconTransparency(lantern, 1)
	if lantern:IsA("ImageLabel") then
		lantern.ImageColor3 = Color3.new(1, 1, 1)
	end
	glow.BackgroundTransparency = 1

	-- 1. Błysk i zamykające się koło
	tint.BackgroundColor3 = look.color
	tint.BackgroundTransparency = 0.55
	tween(tint, 0.6, { BackgroundTransparency = 1 })
	black.BackgroundTransparency = 1
	iris.Size = UDim2.fromOffset(full, full)
	irisStroke.Transparency = 0
	softStroke.Transparency = 0.45
	tween(iris, 0.45, { Size = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(0.42, function()
		if token == current then
			black.BackgroundTransparency = 0
		end
	end)

	-- 2. Oczy w ciemności
	if look.big then
		eyePair(UDim2.fromScale(0.5, 0.17), 46, look.color, 0.5, current)
	else
		local spots = table.clone(EYE_SPOTS)
		for i = 1, look.eyes do
			local spot = table.remove(spots, math.random(1, #spots)) :: Vector2
			eyePair(UDim2.fromScale(spot.X, spot.Y), math.random(14, 22), look.color, 0.5 + i * 0.18, current)
		end
	end

	-- 3. Latarnia migocze i gaśnie, potem tytuł, podtytuł i rada
	task.delay(0.45, function()
		if token ~= current then
			return
		end
		UiKit.setIconTransparency(lantern, 0)
		glow.BackgroundTransparency = 0.75
		for _ = 1, 4 do
			task.wait(0.07 + math.random() * 0.08)
			if token ~= current then
				return
			end
			glow.BackgroundTransparency = 0.75 + math.random() * 0.25
			UiKit.setIconTransparency(lantern, math.random() * 0.5)
		end
		glow.BackgroundTransparency = 1
		UiKit.setIconTransparency(lantern, 0.35)
		if lantern:IsA("ImageLabel") then
			lantern.ImageColor3 = Color3.fromRGB(90, 80, 80)
		end
		smoke(current)
		titleScale.Scale = 1.7
		title.TextTransparency = 0
		titleStroke.Transparency = 0
		tween(titleScale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
		task.wait(0.25)
		if token ~= current then
			return
		end
		tween(subtitle, 0.3, { TextTransparency = 0 })
		tween(subtitleStroke, 0.3, { Transparency = 0 })
		task.wait(0.35)
		if token ~= current then
			return
		end
		tween(tip, 0.3, { BackgroundTransparency = 0.1 })
		tween(tipStroke, 0.3, { Transparency = 0 })
		tween(tipText, 0.3, { TextTransparency = 0 })
		UiKit.setIconTransparency(tipIcon, 0)
	end)

	-- 4. Koło otwiera się na chatkę / obóz
	task.delay(0.45 + HOLD, function()
		if token ~= current then
			return
		end
		for _, label in { title, subtitle, tipText } do
			tween(label, 0.5, { TextTransparency = 1 })
		end
		tween(titleStroke, 0.5, { Transparency = 1 })
		tween(subtitleStroke, 0.5, { Transparency = 1 })
		tween(tip, 0.5, { BackgroundTransparency = 1 })
		tween(tipStroke, 0.5, { Transparency = 1 })
		UiKit.setIconTransparency(tipIcon, 1)
		UiKit.setIconTransparency(lantern, 1)
		for _, pair in eyesLayer:GetChildren() do
			for _, eye in pair:GetChildren() do
				if eye:IsA("Frame") then
					tween(eye, 0.3, { BackgroundTransparency = 1 })
				end
			end
		end
		task.wait(0.35)
		if token ~= current then
			return
		end
		black.BackgroundTransparency = 1
		iris.Size = UDim2.fromOffset(0, 0)
		tween(iris, 0.9, { Size = UDim2.fromOffset(full, full) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(softStroke, 0.9, { Transparency = 1 })
		task.wait(0.95)
		if token == current then
			gui.Enabled = false
		end
	end)
end

return DeathScreen
