--!strict
-- Okno samouczka: pergamin w stylu gry. Woskowa pieczęć z ikoną w rogu, tytuł, tekst pisany
-- literka po literce, mini animacja po prawej (np. jak sprzedać grzyby), sekcja „Nagroda”,
-- kropki stron, strzałki ◀ ▶ w prawym dolnym rogu i „Pomiń”. Wjeżdża z podskokiem, wylatuje w górę.
--   TutorialWindow.show(pages, onClosed?)  – strony: { title, text, icon?, demo?, reward? }

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Audio = require(script.Parent.Audio)
local Localize = require(script.Parent.Localize)
local MushroomArt = require(script.Parent.MushroomArt)
local UiKit = require(script.Parent.UiKit)
local UiScale = require(script.Parent.UiScale)

local player = Players.LocalPlayer

local TutorialWindow = {}

export type Reward = { icon: string, title: string, text: string }
export type Page = {
	title: string,
	text: string,
	icon: string?,
	demo: string?,
	reward: Reward?,
}

local TITLE_FONT = Enum.Font.FredokaOne
local BODY_FONT = Enum.Font.GothamBold
local OUTLINE = UiKit.OUTLINE
local PAPER_TOP = Color3.fromRGB(252, 242, 214)
local PAPER_BOTTOM = Color3.fromRGB(236, 212, 164)
local INK = Color3.fromRGB(88, 52, 24)
local SEAL = Color3.fromRGB(196, 44, 40)
local GREEN = Color3.fromRGB(54, 190, 92)

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

local function text(parent: Instance, name: string, size: UDim2, position: UDim2, font: Enum.Font, maxSize: number, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position
	l.Font = font
	l.TextScaled = true
	l.TextWrapped = true
	l.RichText = true
	l.TextColor3 = color
	l.Text = ""
	l.Parent = parent
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = maxSize
	c.Parent = l
	return l
end

local function tween(object: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local t = TweenService:Create(object, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

-- ===== Mini animacje (pętle w ramce demo) =====
-- Każda buduje się w `area` i kręci się, dopóki `alive()` zwraca true.

type Alive = () -> boolean

local function miniCard(parent: Instance, item: any, x: number, color: Color3): (Frame, TextButton)
	local card = Instance.new("Frame")
	card.Size = UDim2.fromOffset(62, 84)
	card.Position = UDim2.fromOffset(x, 18)
	card.BackgroundColor3 = color
	card.Parent = parent
	corner(card, UDim.new(0, 10))
	stroke(card, OUTLINE, 2.5)
	local box = Instance.new("Frame")
	box.BackgroundTransparency = 1
	box.Size = UDim2.fromOffset(44, 44)
	box.Position = UDim2.new(0.5, -22, 0, 4)
	box.Parent = card
	MushroomArt.build(box, item)
	local sell = Instance.new("TextButton")
	sell.Name = "Sell"
	sell.Text = ""
	sell.AutoButtonColor = false
	sell.Size = UDim2.new(1, -10, 0, 18)
	sell.Position = UDim2.new(0, 5, 1, -22)
	sell.Parent = card
	local st = UiKit.button(sell, GREEN, { stroke = 2, radius = UDim.new(0, 6) })
	st.Color = OUTLINE
	local scale = Instance.new("UIScale")
	scale.Parent = card
	return card, sell
end

local function cursor(parent: Instance): TextLabel
	local hand = Instance.new("TextLabel")
	hand.Name = "Cursor"
	hand.BackgroundTransparency = 1
	hand.Size = UDim2.fromOffset(34, 34)
	hand.AnchorPoint = Vector2.new(0.3, 0.1)
	hand.Text = "👆"
	hand.TextScaled = true
	hand.ZIndex = 20
	hand.Parent = parent
	local scale = Instance.new("UIScale")
	scale.Parent = hand
	return hand
end

local function moveCursor(hand: TextLabel, target: Vector2, time: number)
	tween(hand, time, { Position = UDim2.fromOffset(target.X, target.Y) }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
end

local function click(hand: TextLabel)
	local scale = hand:FindFirstChildOfClass("UIScale") :: UIScale
	scale.Scale = 0.75
	tween(scale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
	Audio.play("click", { volume = 0.4 })
end

local function sleep(seconds: number, alive: Alive): boolean
	local untilTime = os.clock() + seconds
	while os.clock() < untilTime do
		if not alive() then
			return false
		end
		RunService.RenderStepped:Wait()
	end
	return alive()
end

local function centerIn(area: GuiObject, object: GuiObject): Vector2
	return object.AbsolutePosition - area.AbsolutePosition + object.AbsoluteSize / 2
end

local function coinsUp(area: GuiObject, from: Vector2)
	for i = 1, 5 do
		local coin = UiKit.icon("coin", area, UDim2.fromOffset(18, 18), UDim2.fromOffset(from.X, from.Y), Vector2.new(0.5, 0.5))
		coin.ZIndex = 15
		local target = from + Vector2.new(math.random(-30, 30), -40 - math.random(0, 25))
		local t = tween(coin, 0.5 + i * 0.05, { Position = UDim2.fromOffset(target.X, target.Y), Rotation = math.random(-60, 60) })
		t.Completed:Connect(function()
			coin:Destroy()
		end)
	end
end

local DEMO_ITEMS = {
	{ s = "porcini" },
	{ s = "glowing_agaric", v = "gold" },
	{ s = "chanterelle" },
}
local DEMO_COLORS = { Color3.fromRGB(110, 190, 100), Color3.fromRGB(180, 110, 240), Color3.fromRGB(110, 170, 240) }

local function sellDemo(area: Frame, mode: string, alive: Alive)
	while alive() do
		for _, child in area:GetChildren() do
			if not child:IsA("UICorner") and not child:IsA("UIStroke") then
				child:Destroy()
			end
		end
		local cards = {}
		local sells = {}
		for i, item in DEMO_ITEMS do
			local card, sell = miniCard(area, item, 8 + (i - 1) * 70, DEMO_COLORS[i])
			cards[i] = card
			sells[i] = sell
		end
		-- Przyciski pod kartami: „Zaznaczone” i „Wszystko”
		local selected = Instance.new("TextButton")
		selected.Text = ""
		selected.Size = UDim2.fromOffset(92, 26)
		selected.Position = UDim2.fromOffset(16, 112)
		selected.Parent = area
		UiKit.button(selected, GREEN, { stroke = 2, radius = UDim.new(0, 8) }).Color = OUTLINE
		UiKit.icon("check", selected, UDim2.fromOffset(22, 22), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
		local all = Instance.new("TextButton")
		all.Text = ""
		all.Size = UDim2.fromOffset(92, 26)
		all.Position = UDim2.fromOffset(118, 112)
		all.Parent = area
		UiKit.button(all, Color3.fromRGB(246, 170, 40), { stroke = 2, radius = UDim.new(0, 8) }).Color = OUTLINE
		UiKit.icon("coins", all, UDim2.fromOffset(24, 24), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
		local hand = cursor(area)
		hand.Position = UDim2.fromOffset(200, 150)
		if not sleep(0.6, alive) then
			return
		end

		local function poof(i: number)
			local card = cards[i]
			coinsUp(area, centerIn(area, card))
			Audio.play("coin", { volume = 0.35, jitter = 0.1 })
			local scale = card:FindFirstChildOfClass("UIScale") :: UIScale
			tween(scale, 0.3, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			tween(card, 0.3, { Rotation = 25 })
		end

		if mode == "one" then
			moveCursor(hand, centerIn(area, sells[2]), 0.7)
			if not sleep(0.8, alive) then
				return
			end
			click(hand)
			poof(2)
		elseif mode == "selected" then
			for _, i in { 1, 3 } do
				moveCursor(hand, centerIn(area, cards[i]) - Vector2.new(0, 12), 0.6)
				if not sleep(0.7, alive) then
					return
				end
				click(hand)
				local mark = UiKit.icon("check", cards[i], UDim2.fromOffset(22, 22), UDim2.new(1, -22, 0, 0))
				mark.ZIndex = 5
				stroke(cards[i], Color3.fromRGB(150, 255, 110), 4)
			end
			moveCursor(hand, centerIn(area, selected), 0.6)
			if not sleep(0.7, alive) then
				return
			end
			click(hand)
			poof(1)
			poof(3)
		else
			moveCursor(hand, centerIn(area, all), 0.8)
			if not sleep(0.9, alive) then
				return
			end
			click(hand)
			for i = 1, 3 do
				poof(i)
			end
		end
		Audio.play("sell", { volume = 0.4 })
		if not sleep(1.6, alive) then
			return
		end
	end
end

-- Mała scenka: jedna ikona z podskokiem i podpisem (plecak, olej, ogródek, kradzież)
local function iconDemo(area: Frame, kind: string, alive: Alive)
	local icon = UiKit.icon(if kind == "oil" then "lantern" elseif kind == "garden" then "beds" elseif kind == "steal" then "lock" else "basket", area, UDim2.fromOffset(92, 92), UDim2.new(0.5, 0, 0.42, 0), Vector2.new(0.5, 0.5))
	local scale = Instance.new("UIScale")
	scale.Parent = icon
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, -40, 0, 16)
	bar.Position = UDim2.new(0, 20, 1, -30)
	bar.BackgroundColor3 = Color3.fromRGB(60, 40, 28)
	bar.Parent = area
	corner(bar, UDim.new(1, 0))
	stroke(bar, OUTLINE, 2)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = if kind == "oil" then Color3.fromRGB(255, 170, 56) elseif kind == "steal" then Color3.fromRGB(230, 70, 60) else Color3.fromRGB(150, 210, 90)
	fill.Parent = bar
	corner(fill, UDim.new(1, 0))
	local label = text(area, "Count", UDim2.new(1, -20, 0, 22), UDim2.new(0, 10, 0, 6), TITLE_FONT, 20, INK)
	while alive() do
		if kind == "oil" then
			-- Olej się wypala w lesie, a przy beczce w chatce wraca do pełna
			fill.Size = UDim2.fromScale(1, 1)
			label.Text = "100%"
			for k = 10, 1, -1 do
				fill.Size = UDim2.fromScale(k / 10, 1)
				label.Text = (k * 10) .. "%"
				fill.BackgroundColor3 = if k <= 3 then Color3.fromRGB(232, 64, 44) else Color3.fromRGB(255, 170, 56)
				if k <= 3 then
					Audio.play("warn", { volume = 0.15 })
				end
				if not sleep(0.28, alive) then
					return
				end
			end
			scale.Scale = 1.3
			tween(scale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
			tween(fill, 0.6, { Size = UDim2.fromScale(1, 1) })
			fill.BackgroundColor3 = Color3.fromRGB(255, 170, 56)
			label.Text = "100%"
		elseif kind == "garden" then
			-- Grządka: monety same lecą do skrzyni
			fill.Size = UDim2.fromScale(0, 1)
			for k = 1, 10 do
				fill.Size = UDim2.fromScale(k / 10, 1)
				label.Text = "+" .. k .. " 💰"
				coinsUp(area, Vector2.new(area.AbsoluteSize.X / 2, area.AbsoluteSize.Y * 0.4))
				if not sleep(0.3, alive) then
					return
				end
			end
		elseif kind == "steal" then
			-- Złodziej trzyma E: pasek kradzieży rośnie, kłódka go spowalnia
			label.Text = "E..."
			for k = 1, 20 do
				fill.Size = UDim2.fromScale(k / 20, 1)
				icon.Rotation = math.sin(k) * 8
				if not sleep(0.08, alive) then
					return
				end
			end
			Audio.play("alarm", { volume = 0.2, duration = 0.8 })
			label.Text = "!!!"
			scale.Scale = 1.35
			tween(scale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
		else
			-- Plecak zapełnia się grzybami 0/5 → 5/5 i robi się czerwony
			for k = 0, 5 do
				fill.Size = UDim2.fromScale(k / 5, 1)
				label.Text = k .. "/5"
				fill.BackgroundColor3 = if k == 5 then Color3.fromRGB(232, 64, 44) else Color3.fromRGB(150, 210, 90)
				scale.Scale = 1.15
				tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
				if k > 0 then
					Audio.play("pick", { volume = 0.3, pitch = 1 + k * 0.07 })
				end
				if not sleep(0.45, alive) then
					return
				end
			end
		end
		if not sleep(1.2, alive) then
			return
		end
	end
end

-- Zbieranie: grzybek, klawisz E, „pyk” i +1
local function pickDemo(area: Frame, alive: Alive)
	while alive() do
		for _, child in area:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local box = Instance.new("Frame")
		box.BackgroundTransparency = 1
		box.Size = UDim2.fromOffset(96, 96)
		box.Position = UDim2.new(0.5, -48, 0, 14)
		box.Parent = area
		local scale = Instance.new("UIScale")
		scale.Parent = box
		MushroomArt.build(box, { s = "honey" })
		local key = Instance.new("TextLabel")
		key.Size = UDim2.fromOffset(40, 40)
		key.Position = UDim2.new(0.5, -20, 1, -48)
		key.BackgroundColor3 = Color3.new(1, 1, 1)
		key.Text = "E"
		key.Font = TITLE_FONT
		key.TextScaled = true
		key.TextColor3 = OUTLINE
		key.Parent = area
		corner(key, UDim.new(0, 8))
		stroke(key, OUTLINE, 3)
		local keyScale = Instance.new("UIScale")
		keyScale.Parent = key
		if not sleep(0.8, alive) then
			return
		end
		keyScale.Scale = 0.8
		tween(keyScale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
		Audio.play("pick", { volume = 0.4 })
		tween(scale, 0.25, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		local plus = text(area, "Plus", UDim2.fromOffset(80, 34), UDim2.new(0.5, -40, 0, 40), TITLE_FONT, 30, Color3.fromRGB(150, 255, 110))
		plus.Text = "+1 🧺"
		UiKit.outline(plus, 2.5)
		tween(plus, 0.8, { Position = UDim2.new(0.5, -40, 0, 0), TextTransparency = 1 })
		if not sleep(1.4, alive) then
			return
		end
	end
end

-- Ulepszenie: karta z kropkami, które się zapełniają
local function upgradeDemo(area: Frame, alive: Alive)
	local icon = UiKit.icon("upgrade", area, UDim2.fromOffset(70, 70), UDim2.new(0.5, 0, 0, 44), Vector2.new(0.5, 0.5))
	local iconScale = Instance.new("UIScale")
	iconScale.Parent = icon
	local pips = Instance.new("Frame")
	pips.BackgroundTransparency = 1
	pips.Size = UDim2.new(1, -20, 0, 16)
	pips.Position = UDim2.new(0, 10, 0, 92)
	pips.Parent = area
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 4)
	layout.Parent = pips
	local dots = {}
	for i = 1, 8 do
		local d = Instance.new("Frame")
		d.Size = UDim2.fromOffset(14, 14)
		d.BackgroundColor3 = OUTLINE
		d.BackgroundTransparency = 0.5
		d.Parent = pips
		corner(d, UDim.new(1, 0))
		dots[i] = d
	end
	local label = text(area, "Value", UDim2.new(1, -20, 0, 26), UDim2.new(0, 10, 0, 114), TITLE_FONT, 24, INK)
	while alive() do
		for i = 1, 8 do
			dots[i].BackgroundTransparency = 0.5
			dots[i].BackgroundColor3 = OUTLINE
		end
		for i = 1, 8 do
			dots[i].BackgroundColor3 = Color3.fromRGB(255, 214, 70)
			dots[i].BackgroundTransparency = 0
			label.Text = "x" .. string.format("%.1f", 1 + i * 0.2)
			iconScale.Scale = 1.3
			icon.Rotation = -20
			tween(iconScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
			tween(icon, 0.3, { Rotation = 0 }, Enum.EasingStyle.Back)
			Audio.play("levelup", { volume = 0.15, pitch = 1 + i * 0.05 })
			if not sleep(0.45, alive) then
				return
			end
		end
		if not sleep(1, alive) then
			return
		end
	end
end

local function runDemo(area: Frame, kind: string, alive: Alive)
	if kind == "sellOne" then
		sellDemo(area, "one", alive)
	elseif kind == "sellSelected" then
		sellDemo(area, "selected", alive)
	elseif kind == "sellAll" then
		sellDemo(area, "all", alive)
	elseif kind == "pick" then
		pickDemo(area, alive)
	elseif kind == "upgrade" then
		upgradeDemo(area, alive)
	else
		iconDemo(area, kind, alive)
	end
end

-- ===== Okno =====

local current: ScreenGui? = nil

function TutorialWindow.isOpen(): boolean
	return current ~= nil
end

function TutorialWindow.show(pages: { Page }, onClosed: (() -> ())?)
	if current then
		current:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "TutorialWindow"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 30
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	current = gui

	local dim = Instance.new("TextButton")
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.Parent = gui
	tween(dim, 0.3, { BackgroundTransparency = 0.45 })

	-- Okno trzyma stały rozmiar, a UIScale zmniejsza je na małych ekranach
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(620, 430)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.52)
	root.Parent = gui
	local rootScale = Instance.new("UIScale")
	rootScale.Parent = root
	local base = UiScale.get()

	-- Druga kartka pod spodem (wygląda jak stos pergaminów)
	local under = Instance.new("Frame")
	under.Size = UDim2.fromScale(1, 1)
	under.Position = UDim2.fromOffset(8, 10)
	under.Rotation = 2.5
	under.BackgroundColor3 = Color3.fromRGB(214, 186, 136)
	under.Parent = root
	corner(under, UDim.new(0, 22))
	stroke(under, OUTLINE, 4)

	local paper = Instance.new("Frame")
	paper.Name = "Paper"
	paper.Size = UDim2.fromScale(1, 1)
	paper.Rotation = -1
	paper.BackgroundColor3 = Color3.new(1, 1, 1)
	paper.Parent = root
	corner(paper, UDim.new(0, 22))
	stroke(paper, OUTLINE, 4)
	local paperShade = Instance.new("UIGradient")
	paperShade.Rotation = 90
	paperShade.Color = ColorSequence.new(PAPER_TOP, PAPER_BOTTOM)
	paperShade.Parent = paper
	-- Ramka wewnątrz pergaminu i plamki „starego papieru”
	local inner = Instance.new("Frame")
	inner.BackgroundTransparency = 1
	inner.Size = UDim2.new(1, -20, 1, -20)
	inner.Position = UDim2.fromOffset(10, 10)
	inner.Parent = paper
	corner(inner, UDim.new(0, 16))
	stroke(inner, Color3.fromRGB(196, 158, 104), 2)
	for k, spot in { { 0.82, 0.18, 40 }, { 0.12, 0.8, 54 }, { 0.6, 0.86, 28 }, { 0.32, 0.12, 22 } } do
		local stain = Instance.new("Frame")
		stain.Name = "Stain" .. k
		stain.Size = UDim2.fromOffset(spot[3], spot[3])
		stain.AnchorPoint = Vector2.new(0.5, 0.5)
		stain.Position = UDim2.fromScale(spot[1], spot[2])
		stain.BackgroundColor3 = Color3.fromRGB(196, 150, 90)
		stain.BackgroundTransparency = 0.82
		stain.Parent = paper
		corner(stain, UDim.new(1, 0))
	end

	-- Woskowa pieczęć z ikoną tematu
	local seal = Instance.new("Frame")
	seal.Name = "Seal"
	seal.Size = UDim2.fromOffset(84, 84)
	seal.AnchorPoint = Vector2.new(0.5, 0.5)
	seal.Position = UDim2.fromOffset(18, 18)
	seal.Rotation = -12
	seal.BackgroundColor3 = SEAL
	seal.ZIndex = 5
	seal.Parent = root
	corner(seal, UDim.new(1, 0))
	stroke(seal, OUTLINE, 4)
	local sealShade = Instance.new("UIGradient")
	sealShade.Rotation = 120
	sealShade.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170))
	sealShade.Parent = seal
	local sealRing = Instance.new("Frame")
	sealRing.BackgroundTransparency = 1
	sealRing.Size = UDim2.new(1, -14, 1, -14)
	sealRing.Position = UDim2.fromOffset(7, 7)
	sealRing.ZIndex = 6
	sealRing.Parent = seal
	corner(sealRing, UDim.new(1, 0))
	stroke(sealRing, Color3.fromRGB(240, 120, 110), 2)
	local sealIcon = UiKit.icon("mushroom", seal, UDim2.fromScale(0.62, 0.62), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	sealIcon.ZIndex = 7

	-- Zawartość strony (przesuwana w bok przy zmianie strony)
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.new(1, -60, 1, -110)
	content.Position = UDim2.fromOffset(30, 26)
	content.ClipsDescendants = false
	content.Parent = paper

	local title = text(content, "Title", UDim2.new(1, -60, 0, 44), UDim2.fromOffset(60, 0), TITLE_FONT, 38, INK)
	title.TextXAlignment = Enum.TextXAlignment.Left
	-- Kreska pod tytułem z kropek
	local rule = Instance.new("Frame")
	rule.BackgroundColor3 = Color3.fromRGB(176, 130, 76)
	rule.BorderSizePixel = 0
	rule.Size = UDim2.new(1, -60, 0, 3)
	rule.Position = UDim2.fromOffset(60, 48)
	rule.Parent = content
	corner(rule, UDim.new(1, 0))

	local body = text(content, "Body", UDim2.new(1, 0, 0, 150), UDim2.fromOffset(0, 62), BODY_FONT, 21, INK)
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top

	local demoBox = Instance.new("Frame")
	demoBox.Name = "Demo"
	demoBox.Size = UDim2.fromOffset(226, 150)
	demoBox.AnchorPoint = Vector2.new(1, 0)
	demoBox.Position = UDim2.new(1, 0, 0, 62)
	demoBox.BackgroundColor3 = Color3.fromRGB(255, 250, 236)
	demoBox.ClipsDescendants = true
	demoBox.Parent = content
	corner(demoBox, UDim.new(0, 14))
	stroke(demoBox, OUTLINE, 3)

	local rewardBox = Instance.new("Frame")
	rewardBox.Name = "Reward"
	rewardBox.BackgroundTransparency = 1
	rewardBox.Size = UDim2.new(1, 0, 0, 80)
	rewardBox.Position = UDim2.new(0, 0, 1, -80)
	rewardBox.Parent = content
	local rewardHead = text(rewardBox, "Head", UDim2.new(1, 0, 0, 24), UDim2.fromOffset(0, 0), TITLE_FONT, 24, INK)
	rewardHead.TextXAlignment = Enum.TextXAlignment.Left
	local rewardIconBox = Instance.new("Frame")
	rewardIconBox.Size = UDim2.fromOffset(54, 54)
	rewardIconBox.Position = UDim2.fromOffset(0, 26)
	rewardIconBox.BackgroundColor3 = Color3.fromRGB(70, 46, 30)
	rewardIconBox.Parent = rewardBox
	corner(rewardIconBox, UDim.new(0, 10))
	stroke(rewardIconBox, Color3.fromRGB(240, 190, 90), 3)
	local rewardIcon = UiKit.icon("coins", rewardIconBox, UDim2.fromScale(0.85, 0.85), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	local rewardTitle = text(rewardBox, "Title", UDim2.new(1, -70, 0, 26), UDim2.fromOffset(66, 26), TITLE_FONT, 24, INK)
	rewardTitle.TextXAlignment = Enum.TextXAlignment.Left
	local rewardText = text(rewardBox, "Text", UDim2.new(1, -70, 0, 22), UDim2.fromOffset(66, 54), BODY_FONT, 17, Color3.fromRGB(130, 92, 56))
	rewardText.TextXAlignment = Enum.TextXAlignment.Left

	-- Stopka: kropki stron, ◀ ▶, „Pomiń”, przycisk „Dalej”
	local footer = Instance.new("Frame")
	footer.BackgroundTransparency = 1
	footer.Size = UDim2.new(1, -60, 0, 56)
	footer.Position = UDim2.new(0, 30, 1, -72)
	footer.Parent = paper
	local dots = Instance.new("Frame")
	dots.BackgroundTransparency = 1
	dots.Size = UDim2.fromOffset(160, 16)
	dots.Position = UDim2.new(0, 0, 0.5, -8)
	dots.Parent = footer
	local dotsLayout = Instance.new("UIListLayout")
	dotsLayout.FillDirection = Enum.FillDirection.Horizontal
	dotsLayout.Padding = UDim.new(0, 8)
	dotsLayout.Parent = dots
	local dotFrames = {}
	for i = 1, #pages do
		local d = Instance.new("Frame")
		d.Size = UDim2.fromOffset(14, 14)
		d.Parent = dots
		corner(d, UDim.new(1, 0))
		stroke(d, OUTLINE, 2)
		dotFrames[i] = d
	end
	dots.Visible = #pages > 1

	local skip = Instance.new("TextButton")
	skip.BackgroundTransparency = 1
	skip.Size = UDim2.fromOffset(110, 30)
	skip.Position = UDim2.new(0, 0, 0.5, 4)
	skip.Font = TITLE_FONT
	skip.TextSize = 18
	skip.TextColor3 = Color3.fromRGB(150, 110, 70)
	skip.TextXAlignment = Enum.TextXAlignment.Left
	skip.Text = Localize.t("TUT_SKIP")
	skip.Parent = footer
	skip.Visible = #pages > 1

	local function arrowButton(name: string, label: string, x: number): TextButton
		local b = Instance.new("TextButton")
		b.Name = name
		b.Size = UDim2.fromOffset(52, 46)
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, x, 0.5, 0)
		b.Font = TITLE_FONT
		b.TextScaled = true
		b.Text = label
		b.Parent = footer
		UiKit.button(b, Color3.fromRGB(150, 98, 56), { stroke = 3, radius = UDim.new(0, 12), gloss = true }).Color = OUTLINE
		return b
	end
	local nextButton = Instance.new("TextButton")
	nextButton.Name = "Next"
	nextButton.Size = UDim2.fromOffset(170, 50)
	nextButton.AnchorPoint = Vector2.new(1, 0.5)
	nextButton.Position = UDim2.new(1, 0, 0.5, 0)
	nextButton.Font = TITLE_FONT
	nextButton.TextScaled = true
	nextButton.Parent = footer
	UiKit.button(nextButton, GREEN, { stroke = 3, radius = UDim.new(0, 14), gloss = true }).Color = OUTLINE
	local nextPad = Instance.new("UIPadding")
	nextPad.PaddingTop = UDim.new(0, 8)
	nextPad.PaddingBottom = UDim.new(0, 8)
	nextPad.Parent = nextButton
	UiKit.outline(nextButton, 2.5)
	local prevButton = arrowButton("Prev", "<", -180)

	local page = 0
	local token = 0
	local closing = false

	local function close()
		if closing then
			return
		end
		closing = true
		token += 1
		Audio.play("whoosh", { volume = 0.5 })
		tween(rootScale, 0.3, { Scale = base * 0.6 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		tween(root, 0.3, { Position = UDim2.fromScale(0.5, 0.2), Rotation = 8 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		tween(dim, 0.3, { BackgroundTransparency = 1 })
		task.delay(0.32, function()
			gui:Destroy()
			if current == gui then
				current = nil
			end
			if onClosed then
				onClosed()
			end
		end)
	end

	local function showPage(index: number, direction: number)
		page = index
		token += 1
		local myToken = token
		local p = pages[index]
		local hasDemo = p.demo ~= nil
		local hasReward = p.reward ~= nil
		UiKit.setIcon(sealIcon, p.icon or "mushroom")
		title.Text = p.title
		body.Size = UDim2.new(if hasDemo then 1 else 1, if hasDemo then -246 else 0, 0, if hasReward then 150 else 230)
		demoBox.Visible = hasDemo
		rewardBox.Visible = hasReward
		if p.reward then
			rewardHead.Text = Localize.t("TUT_REWARD")
			UiKit.setIcon(rewardIcon, p.reward.icon)
			rewardTitle.Text = p.reward.title
			rewardText.Text = p.reward.text
		end
		for i, d in dotFrames do
			d.BackgroundColor3 = if i == index then Color3.fromRGB(255, 196, 60) else Color3.fromRGB(214, 186, 136)
			d.Size = if i == index then UDim2.fromOffset(18, 14) else UDim2.fromOffset(14, 14)
		end
		prevButton.Visible = index > 1
		local last = index == #pages
		nextButton.Text = if last then Localize.t("TUT_OK") else Localize.t("TUT_NEXT")
		UiKit.recolor(nextButton, if last then GREEN else Color3.fromRGB(236, 150, 40))
		local nextStroke = nextButton:FindFirstChildOfClass("UIStroke")
		if nextStroke then
			nextStroke.Color = OUTLINE
		end
		-- Wjazd treści z boku
		content.Position = UDim2.fromOffset(30 + direction * 40, 26)
		tween(content, 0.3, { Position = UDim2.fromOffset(30, 26) }, Enum.EasingStyle.Back)
		sealIcon.Rotation = -30
		tween(sealIcon, 0.4, { Rotation = 0 }, Enum.EasingStyle.Back)
		-- Demo od nowa
		for _, child in demoBox:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		if p.demo then
			local kind = p.demo
			task.spawn(function()
				runDemo(demoBox, kind, function()
					return token == myToken and gui.Parent ~= nil
				end)
			end)
		end
		-- Tekst literka po literce
		local letters = {}
		for _, code in utf8.codes(p.text) do
			table.insert(letters, utf8.char(code))
		end
		task.spawn(function()
			for i = 1, #letters do
				if token ~= myToken then
					return
				end
				body.Text = table.concat(letters, "", 1, i)
				if i % 3 == 0 and letters[i] ~= " " then
					Audio.play("blip", { volume = 0.25, jitter = 0.2 })
				end
				task.wait(0.012)
			end
		end)
	end

	nextButton.Activated:Connect(function()
		Audio.play("click", { volume = 0.5 })
		if page >= #pages then
			close()
		else
			showPage(page + 1, 1)
		end
	end)
	prevButton.Activated:Connect(function()
		Audio.play("click", { volume = 0.5 })
		if page > 1 then
			showPage(page - 1, -1)
		end
	end)
	skip.Activated:Connect(function()
		Audio.play("click", { volume = 0.5 })
		close()
	end)

	-- Wejście: kartka spada z obrotem i odbija się
	rootScale.Scale = base * 0.6
	root.Rotation = -10
	root.Position = UDim2.fromScale(0.5, 0.62)
	tween(rootScale, 0.45, { Scale = base }, Enum.EasingStyle.Back)
	tween(root, 0.45, { Rotation = 0, Position = UDim2.fromScale(0.5, 0.52) }, Enum.EasingStyle.Back)
	Audio.play("whoosh", { volume = 0.6 })
	-- Pieczęć wbija się na końcu
	seal.Size = UDim2.fromOffset(150, 150)
	seal.BackgroundTransparency = 1
	task.delay(0.3, function()
		tween(seal, 0.25, { Size = UDim2.fromOffset(84, 84), BackgroundTransparency = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.delay(0.25, function()
			Audio.play("boom", { volume = 0.12 })
		end)
	end)
	showPage(1, 0)
end

function TutorialWindow.close()
	if current then
		current:Destroy()
		current = nil
	end
end

return TutorialWindow
