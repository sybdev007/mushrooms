--!strict
-- Ekran wczytywania: tło z powolnym najazdem kamery, tytuł, pasek postępu z biegaczem, status etapu,
-- wskazówki i drobinki w powietrzu.
--   halloween: dynia toczy się po pasku (pyszczek migocze jak świeczka), z dyni sypią się iskry,
--              po niebie przelatują nietoperze, w górę lecą żarzące się iskierki
--   forest:    grzybek skacze po pasku i zostawia za sobą świecące kiełki, wokół świetliki
-- Moduł tylko rysuje: LoadingScreen.client podaje postęp (setTarget) i etap (setStage). Nie dotyka
-- postaci ani CoreGui, więc da się go też obejrzeć w Studio: require(...).preview("forest", 12).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local LoadingTheme = require(script.Parent:WaitForChild("LoadingTheme"))

local LoadingUI = {}

export type Handle = {
	gui: ScreenGui,
	setTarget: (progress: number) -> (),
	setStage: (stage: string) -> (),
	shown: () -> number,
	complete: () -> (),
	fadeOut: (toBlack: boolean, onBlack: (() -> ())?) -> (),
	destroy: () -> (),
}

local OUTLINE = Color3.fromRGB(43, 27, 18)
local CREAM = Color3.fromRGB(255, 244, 222)
local MUTED = Color3.fromRGB(236, 220, 198)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

-- Układ w pikselach ekranu 1280 x 720; UIScale skaluje całość do prawdziwego ekranu
local REF_W, REF_H = 1280, 720
-- Zwykły ekran: tylko nazwa gry, toczona dynia i pasek (bez iskier, nietoperzy, poświat i wskazówek)
local EFFECTS = false
local STACK_W, STACK_H = 640, 236
local BAR_W, BAR_H = 560, 26
local BAR_X = (STACK_W - BAR_W) / 2
local BAR_Y = 170

local PUMPKIN = 64
local PUMPKIN_LIFT = 17 / 256 -- środek dyni leży niżej niż środek komórki arkusza
local PUMPKIN_REACH = 0.36 -- od środka dyni do jej spodu (część rozmiaru)
local MUSHROOM = 70
local MUSHROOM_FOOT = 250 / 256 -- stopy grzybka w komórce arkusza

local FREDOKA = Font.fromEnum(Enum.Font.FredokaOne)
-- FredokaOne nie ma ą ę ś ź (tak samo robi FontFix w grze)
local NUNITO_HEAVY = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Heavy)
local NUNITO_BOLD = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Bold)

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function corner(parent: Instance, radius: UDim?)
	make("UICorner", { CornerRadius = radius or UDim.new(0.5, 0) }, parent)
end

local function outline(parent: Instance, thickness: number, color: Color3?): UIStroke
	return make("UIStroke", {
		Color = color or OUTLINE,
		Thickness = thickness,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, parent)
end

local function tween(object: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local t = TweenService:Create(object, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function text(value: LoadingTheme.Text, locale: string): string
	return LoadingTheme.text(value, locale)
end

type Particle = {
	object: GuiObject,
	age: number,
	life: number,
	x: number,
	y: number,
	vx: number,
	vy: number,
	size: number,
	seed: number,
	kind: string,
}

function LoadingUI.new(themeId: string?, parent: Instance?): Handle
	local theme = LoadingTheme.get(themeId)
	local locale = LoadingTheme.locale()
	local textFont = if locale == "pl" then NUNITO_HEAVY else FREDOKA
	local sheet = LoadingTheme.SPRITES
	local hasSprites = sheet ~= ""
	local destroyed = false

	local function sprite(cell: string, props: { [string]: any }, into: Instance?): ImageLabel
		local position = LoadingTheme.CELLS[cell]
		local image = make("ImageLabel", {
			BackgroundTransparency = 1,
			Image = sheet,
			ImageRectOffset = position * LoadingTheme.CELL,
			ImageRectSize = Vector2.new(LoadingTheme.CELL, LoadingTheme.CELL),
		}, nil)
		for key, value in props do
			(image :: any)[key] = value
		end
		image.Parent = into
		return image
	end

	local gui: ScreenGui = make("ScreenGui", {
		Name = "LoadingScreen",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 100,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		AutoLocalize = false,
	})
	pcall(function()
		(gui :: any).ScreenInsets = Enum.ScreenInsets.None
	end)

	local root: Frame = make("Frame", {
		Name = "Root",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = theme.backdrop,
		BorderSizePixel = 0,
	}, gui)
	-- Delikatny gradient pod spodem, gdyby tło jeszcze się nie wczytało
	make("UIGradient", {
		Color = ColorSequence.new(theme.backdrop:Lerp(WHITE, 0.08), theme.backdrop:Lerp(BLACK, 0.5)),
		Rotation = 90,
	}, root)

	-- ===== Tło =====
	local art: ImageLabel = make("ImageLabel", {
		Name = "Art",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = theme.background,
		ScaleType = Enum.ScaleType.Crop,
		-- 0.999, nie 1: całkiem przezroczysty obrazek Roblox w ogóle nie pobiera (IsLoaded nigdy nie przyjdzie)
		ImageTransparency = 0.999,
		ZIndex = 1,
	}, root)
	local artScale = make("UIScale", { Scale = 1 }, art)
	-- Tło pojawia się, kiedy się wczyta. IsLoaded nie wysyła sygnału zmiany, więc sprawdza go pętla klatek.
	local artShown = theme.background == ""
	if EFFECTS and theme.background ~= "" then
		-- Powolny najazd i dryf (Ken Burns), żeby obraz żył
		TweenService:Create(artScale, TweenInfo.new(24, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.09 }):Play()
		TweenService:Create(art, TweenInfo.new(31, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = UDim2.fromScale(0.488, 0.508) }):Play()
	end

	-- Przyciemnienie: góra lekko, dół mocno (pod napisy), boki winieta
	local shade = make("Frame", { Name = "Shade", Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, BorderSizePixel = 0, ZIndex = 2 }, root)
	make("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45),
			NumberSequenceKeypoint.new(0.22, 0.9),
			NumberSequenceKeypoint.new(0.5, 0.86),
			NumberSequenceKeypoint.new(0.72, 0.45),
			NumberSequenceKeypoint.new(1, 0.08),
		}),
	}, shade)
	local vignette = make("Frame", { Name = "Vignette", Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, BorderSizePixel = 0, ZIndex = 2 }, root)
	make("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45),
			NumberSequenceKeypoint.new(0.2, 1),
			NumberSequenceKeypoint.new(0.8, 1),
			NumberSequenceKeypoint.new(1, 0.45),
		}),
	}, vignette)

	local particlesLayer = make("Frame", { Name = "Particles", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3 }, root)

	-- ===== Środek: tytuł, pasek, status =====
	local stack: Frame = make("Frame", {
		Name = "Stack",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.965),
		Size = UDim2.fromOffset(STACK_W, STACK_H),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, root)
	local stackScale = make("UIScale", {}, stack)

	if EFFECTS and hasSprites then
		sprite("glow", {
			Name = "TitleGlow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(STACK_W / 2, 36),
			Size = UDim2.fromOffset(560, 150),
			ImageColor3 = theme.glow,
			ImageTransparency = 0.7,
			ZIndex = 4,
		}, stack)
	end
	local title: TextLabel = make("TextLabel", {
		Name = "Title",
		Text = "Midnight Mushroom Hunt",
		FontFace = FREDOKA,
		TextScaled = true,
		TextColor3 = WHITE,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(STACK_W, 70),
		Position = UDim2.fromOffset(0, 72),
		ZIndex = 6,
	}, stack)
	make("UIGradient", { Color = ColorSequence.new(theme.titleTop, theme.titleBottom), Rotation = 90 }, title)
	make("UITextSizeConstraint", { MaxTextSize = 60 }, title)
	local titleStroke = outline(title, 5)
	make("UIGradient", { Color = ColorSequence.new(OUTLINE) }, titleStroke) -- obrys bez gradientu tytułu

	local badge: TextLabel = make("TextLabel", {
		Name = "Badge",
		Text = text(theme.badge, locale),
		FontFace = textFont,
		TextSize = 17,
		TextColor3 = CREAM,
		BackgroundColor3 = theme.badgeColor,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 28),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(STACK_W / 2, 72),
		ZIndex = 6,
	}, stack)
	corner(badge)
	badge.Visible = EFFECTS
	make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, badge)
	make("UIStroke", { Color = OUTLINE, Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, badge)

	-- Pasek
	local track: Frame = make("Frame", {
		Name = "Track",
		Position = UDim2.fromOffset(BAR_X, BAR_Y),
		Size = UDim2.fromOffset(BAR_W, BAR_H),
		BackgroundColor3 = theme.track,
		BorderSizePixel = 0,
		ZIndex = 6,
	}, stack)
	corner(track)
	outline(track, 3.5)
	make("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(140, 140, 140), WHITE), Rotation = 90 }, track)

	local fill: Frame = make("Frame", {
		Name = "Fill",
		Size = UDim2.fromOffset(BAR_H, BAR_H),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 7,
	}, track)
	corner(fill)
	make("UIGradient", { Color = ColorSequence.new(theme.fillFrom, theme.fillTo) }, fill)
	local gloss = make("Frame", {
		Name = "Gloss",
		Size = UDim2.new(1, -12, 0.36, 0),
		Position = UDim2.new(0, 6, 0.1, 0),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		ZIndex = 8,
	}, fill)
	corner(gloss)
	local shine = make("Frame", { Name = "Shine", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 9 }, fill)
	corner(shine)
	local shineGradient = make("UIGradient", {
		Rotation = 20,
		Offset = Vector2.new(-1, 0),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, 0.45),
			NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, shine)
	shine.Visible = EFFECTS
	TweenService:Create(shineGradient, TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, false, 0.6), { Offset = Vector2.new(1, 0) }):Play()

	local headGlow: ImageLabel? = nil
	if EFFECTS and hasSprites then
		headGlow = sprite("glow", {
			Name = "HeadGlow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(74, 74),
			ImageColor3 = theme.glow,
			ImageTransparency = 0.45,
			ZIndex = 10,
		}, track)
	end

	-- Biegacz: dynia albo grzybek (bez arkusza: emoji)
	local runnerSize = if theme.runner == "pumpkin" then PUMPKIN else MUSHROOM
	local halo: ImageLabel? = nil
	if EFFECTS and hasSprites then
		halo = sprite("glow", {
			Name = "RunnerHalo",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(runnerSize * 2.3, runnerSize * 2.3),
			ImageColor3 = theme.glow,
			ImageTransparency = 0.55,
			ZIndex = 5, -- za paskiem
		}, stack)
	end
	local shadow: GuiObject
	if hasSprites then
		shadow = sprite("glow", {
			Name = "RunnerShadow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(runnerSize * 0.9, runnerSize * 0.22),
			ImageColor3 = BLACK,
			ImageTransparency = 0.35,
			ZIndex = 11,
		}, stack)
	else
		shadow = make("Frame", {
			Name = "RunnerShadow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(runnerSize * 0.7, runnerSize * 0.14),
			BackgroundColor3 = BLACK,
			BackgroundTransparency = 0.6,
			BorderSizePixel = 0,
			ZIndex = 11,
		}, stack)
		corner(shadow)
	end
	local runner: Frame = make("Frame", {
		Name = "Runner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(runnerSize, runnerSize),
		BackgroundTransparency = 1,
		ZIndex = 12,
	}, stack)
	local body: GuiObject
	local glowLayer: ImageLabel? = nil
	if hasSprites then
		local isPumpkin = theme.runner == "pumpkin"
		body = sprite(if isPumpkin then "pumpkin" else "mushroom", {
			Name = "Body",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, if isPumpkin then 0.5 - PUMPKIN_LIFT else 0.5),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 13,
		}, runner)
		glowLayer = sprite(if isPumpkin then "pumpkinGlow" else "mushroomGlow", {
			Name = "Glow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 14,
		}, body)
	else
		body = make("TextLabel", {
			Name = "Body",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = theme.fallbackRunner,
			TextScaled = true,
			FontFace = FREDOKA,
			ZIndex = 13,
		}, runner)
	end

	-- Status etapu i procent
	local status: TextLabel = make("TextLabel", {
		Name = "Status",
		Text = "",
		FontFace = textFont,
		TextSize = 21,
		TextColor3 = CREAM,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(BAR_X + 6, BAR_Y + BAR_H + 9),
		Size = UDim2.fromOffset(BAR_W - 96, 26),
		ZIndex = 6,
	}, stack)
	outline(status, 2.5)
	local percent: TextLabel = make("TextLabel", {
		Name = "Percent",
		Text = "0%",
		FontFace = FREDOKA,
		TextSize = 23,
		TextColor3 = theme.titleTop,
		TextXAlignment = Enum.TextXAlignment.Right,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(BAR_X + BAR_W - 92, BAR_Y + BAR_H + 8),
		Size = UDim2.fromOffset(88, 28),
		ZIndex = 6,
	}, stack)
	outline(percent, 2.5)
	local tip: TextLabel = make("TextLabel", {
		Name = "Tip",
		Text = "",
		FontFace = NUNITO_BOLD,
		TextSize = 16,
		TextColor3 = MUTED,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(20, BAR_Y + BAR_H + 44),
		Size = UDim2.fromOffset(STACK_W - 40, 40),
		ZIndex = 6,
	}, stack)
	outline(tip, 2)
	tip.Visible = EFFECTS

	local black: Frame = make("Frame", {
		Name = "Black",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 50,
	}, gui)

	-- ===== Skala do ekranu =====
	local scale = 1
	local scaled = false
	local function rescale()
		local size = gui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		scaled = true
		scale = math.clamp(math.min(size.X / REF_W, size.Y / REF_H), 0.6, 1.8)
		-- Wąski ekran (telefon w pionie): całość musi się zmieścić w szerokości
		scale = math.min(scale, (size.X - 24) / STACK_W)
		stackScale.Scale = scale
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)

	-- ===== Wskazówki =====
	local tips = theme.tips
	local tipIndex = math.random(1, #tips)
	local function showTip()
		tip.Text = "💡 " .. text(tips[tipIndex], locale)
		tip.TextTransparency = 1
		tween(tip, 0.5, { TextTransparency = 0 })
	end
	task.spawn(function()
		while not destroyed do
			task.wait(5.5)
			if destroyed then
				break
			end
			tween(tip, 0.35, { TextTransparency = 1 })
			task.wait(0.4)
			tipIndex = tipIndex % #tips + 1
			if not destroyed then
				showTip()
			end
		end
	end)

	-- ===== Drobinki =====
	local particles: { Particle } = {}
	local function spawnParticle(kind: string, x: number, y: number, vx: number, vy: number, size: number, life: number, color: Color3)
		if not EFFECTS or #particles > 70 then
			return
		end
		local object: GuiObject
		if hasSprites then
			object = sprite("glow", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(size * 3, size * 3),
				ImageColor3 = color,
				ImageTransparency = 1,
				ZIndex = 3,
			}, particlesLayer)
		else
			object = make("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(size, size),
				BackgroundColor3 = color,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 3,
			}, particlesLayer)
			corner(object)
		end
		table.insert(particles, {
			object = object,
			age = 0,
			life = life,
			x = x,
			y = y,
			vx = vx,
			vy = vy,
			size = size,
			seed = math.random() * 100,
			kind = kind,
		})
	end

	local function setAlpha(object: GuiObject, alpha: number)
		if object:IsA("ImageLabel") then
			object.ImageTransparency = 1 - alpha
		else
			object.BackgroundTransparency = 1 - alpha
		end
	end

	-- Nietoperze (halloween): emoji przelatuje łukiem przez górę ekranu
	type Bat = { label: TextLabel, from: number, to: number, y: number, t: number, duration: number, size: number, seed: number }
	local bats: { Bat } = {}
	local nextBat = os.clock() + 1.5

	-- ===== Postęp i biegacz =====
	local target = 0
	local shownProgress = 0
	local stageId = ""
	local stageText = ""
	local done = false
	local runnerX = BAR_H / 2 -- startuje na początku paska (bez obrotu na pierwszej klatce)
	local roll = 0 -- kąt dyni (stopnie)
	local idleFor = 0
	local hopPhase = 0
	local hopHeight = 0
	local celebrate = 0 -- 0..1: radosny podskok na końcu
	local sproutsAt = 0.06
	local spawnAcc = 0
	local sparkAcc = 0
	local startedAt = os.clock()

	local function sprout(x: number)
		if not hasSprites then
			return
		end
		local cells = { "sproutCyan", "sproutGold", "sproutPink" }
		local size = math.random(20, 30)
		local s = sprite(cells[math.random(1, #cells)], {
			Name = "Sprout",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromOffset(BAR_X + x, BAR_Y + 4),
			Size = UDim2.fromOffset(size, size),
			Rotation = math.random(-10, 10),
			ZIndex = 10,
		}, stack)
		local pop = make("UIScale", { Scale = 0 }, s)
		tween(pop, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	end

	local lastTime = os.clock()
	local connection = RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local dt = math.min(now - lastTime, 0.1)
		lastTime = now
		if not scaled then
			rescale()
		end
		if not artShown and art.IsLoaded then
			artShown = true
			tween(art, 0.9, { ImageTransparency = 0 })
		end

		-- Pasek dogania cel płynnie, nigdy się nie cofa
		local diff = target - shownProgress
		if diff > 0 then
			local step = math.max(diff * (1 - math.exp(-dt * 3.5)), dt * 0.05)
			shownProgress = math.min(target, shownProgress + math.min(step, dt * 0.85))
		end
		local width = BAR_H + (BAR_W - BAR_H) * shownProgress
		fill.Size = UDim2.fromOffset(width, BAR_H)
		local headX = width - BAR_H / 2
		percent.Text = string.format("%d%%", math.floor(shownProgress * 100 + 0.0001))
		local pulse = 0.5 + 0.5 * math.sin(now * 3.2)
		if headGlow then
			headGlow.Position = UDim2.fromOffset(headX, BAR_H / 2)
			headGlow.ImageTransparency = 0.35 + 0.25 * pulse
		end

		-- Status z kropkami
		if stageText ~= "" then
			status.Text = if done then stageText else stageText .. string.rep(".", 1 + math.floor(now * 2.5) % 3)
		end

		-- Biegacz
		local moved = headX - runnerX
		runnerX = headX
		local speed = math.abs(moved) / math.max(dt, 1e-3)
		if speed > 4 then
			idleFor = 0
		else
			idleFor += dt
		end
		if celebrate > 0 then
			celebrate = math.max(0, celebrate - dt * 1.6)
		end
		local jump = math.sin(math.clamp(1 - celebrate, 0, 1) * math.pi) * (if celebrate > 0 then 38 else 0)

		local baseY = BAR_Y + 1
		local airborne = jump -- jak wysoko biegacz jest nad paskiem (cień maleje)
		if theme.runner == "pumpkin" then
			-- Toczy się: kąt z przebytej drogi; stojąc, wraca pyszczkiem do góry
			local radius = runnerSize * PUMPKIN_REACH
			roll += math.deg(moved / radius)
			if idleFor > 0.35 and celebrate == 0 then
				local upright = math.floor(roll / 360 + 0.5) * 360
				roll += (upright - roll) * math.min(1, dt * 4)
			end
			if celebrate > 0 then
				roll += dt * 720 * celebrate
			end
			runner.Rotation = roll
			runner.Position = UDim2.fromOffset(BAR_X + runnerX, baseY - radius - jump)
			if glowLayer then
				local flicker = math.noise(now * 7, 0.3) * 0.5 + math.noise(now * 17, 1.7) * 0.25
				glowLayer.ImageTransparency = math.clamp(0.12 + flicker * 0.5, 0, 0.6)
			end
		else
			-- Skacze, kiedy pasek idzie; stojąc oddycha
			local moving = idleFor < 0.25
			hopHeight += ((if moving then 1 else 0) - hopHeight) * math.min(1, dt * 6)
			hopPhase += dt * 9
			local hop = math.abs(math.sin(hopPhase)) * 13 * hopHeight
			local squash = (1 - math.min(1, math.abs(math.sin(hopPhase)) * 3)) * 0.14 * hopHeight
			local breathe = 0.025 * math.sin(now * 3) * (1 - hopHeight)
			body.Size = UDim2.fromScale(1 + squash - breathe * 0.5, 1 - squash + breathe)
			body.Position = UDim2.fromScale(0.5, 0.5 + (squash - breathe) * 0.5)
			runner.Rotation = math.sin(hopPhase * 0.5) * 7 * hopHeight + (if celebrate > 0 then math.sin(now * 20) * 10 * celebrate else 0)
			local foot = runnerSize * (MUSHROOM_FOOT - 0.5)
			runner.Position = UDim2.fromOffset(BAR_X + runnerX, baseY - foot - hop - jump)
			airborne += hop
			if glowLayer then
				glowLayer.ImageTransparency = 0.1 + 0.35 * (0.5 + 0.5 * math.sin(now * 2.4))
			end
			-- Kiełki rosną za grzybkiem
			while shownProgress >= sproutsAt and sproutsAt < 0.97 do
				sprout(math.max(BAR_H, BAR_H + (BAR_W - BAR_H) * sproutsAt - 18))
				sproutsAt += 0.065 + math.random() * 0.03
			end
		end
		local lift = math.clamp(1 - airborne / 55, 0.4, 1)
		shadow.Position = UDim2.fromOffset(BAR_X + runnerX, baseY)
		shadow.Size = UDim2.fromOffset(runnerSize * 0.9 * lift, runnerSize * 0.22 * lift)
		if halo then
			halo.Position = runner.Position
			halo.ImageTransparency = 0.5 + 0.2 * pulse
		end

		-- Drobinki w pikselach ekranu
		local screen = gui.AbsoluteSize
		if screen.X > 0 then
			spawnAcc += dt
			local rate = if theme.particleKind == "embers" then 0.09 else 0.22
			while spawnAcc > rate do
				spawnAcc -= rate
				local color = theme.particles[math.random(1, #theme.particles)]
				if theme.particleKind == "embers" then
					spawnParticle("ember", math.random() * screen.X, screen.Y + 10, (math.random() - 0.5) * 30, -(45 + math.random() * 80) * scale, (3 + math.random() * 4) * scale, 4 + math.random() * 3, color)
				else
					spawnParticle("firefly", math.random() * screen.X, screen.Y * (0.3 + math.random() * 0.65), 0, 0, (3 + math.random() * 3) * scale, 6 + math.random() * 4, color)
				end
			end
			-- Iskry spod toczącej się dyni
			if theme.runner == "pumpkin" and speed > 8 then
				sparkAcc += dt
				while sparkAcc > 0.06 do
					sparkAcc -= 0.06
					local stackPos = stack.AbsolutePosition
					local px = stackPos.X + (BAR_X + runnerX - runnerSize * 0.3) * scale
					local py = stackPos.Y + (baseY - 4) * scale
					spawnParticle("spark", px, py, -(30 + math.random() * 60) * scale, -(20 + math.random() * 50) * scale, (2 + math.random() * 2.5) * scale, 0.5 + math.random() * 0.4, theme.particles[math.random(1, #theme.particles)])
				end
			end
		end
		for i = #particles, 1, -1 do
			local p = particles[i]
			p.age += dt
			if p.age >= p.life or destroyed then
				p.object:Destroy()
				table.remove(particles, i)
				continue
			end
			local k = p.age / p.life
			local alpha
			if p.kind == "firefly" then
				p.vx += (math.noise(p.seed, now * 0.4) * 60 - p.vx) * dt
				p.vy += (math.noise(p.seed + 9, now * 0.4) * 40 - p.vy) * dt
				alpha = math.sin(k * math.pi) * (0.45 + 0.55 * math.max(0, math.sin(now * 3 + p.seed)))
			elseif p.kind == "spark" then
				p.vy += 120 * scale * dt
				alpha = 1 - k
			else
				p.vx += math.sin(now * 1.5 + p.seed) * 10 * dt
				alpha = math.sin(k * math.pi) * 0.9
			end
			p.x += p.vx * dt
			p.y += p.vy * dt
			p.object.Position = UDim2.fromOffset(p.x, p.y)
			setAlpha(p.object, alpha)
		end

		-- Nietoperze
		if EFFECTS and theme.bats and screen.X > 0 then
			if now >= nextBat then
				nextBat = now + 4 + math.random() * 5
				local leftToRight = math.random() < 0.5
				local size = (26 + math.random() * 18) * scale
				local label: TextLabel = make("TextLabel", {
					Text = "🦇",
					BackgroundTransparency = 1,
					TextScaled = true,
					FontFace = FREDOKA,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Size = UDim2.fromOffset(size, size),
					ZIndex = 3,
				}, particlesLayer)
				table.insert(bats, {
					label = label,
					from = if leftToRight then -60 else screen.X + 60,
					to = if leftToRight then screen.X + 60 else -60,
					y = screen.Y * (0.08 + math.random() * 0.3),
					t = 0,
					duration = 5 + math.random() * 3,
					size = size,
					seed = math.random() * 10,
				})
			end
			for i = #bats, 1, -1 do
				local bat = bats[i]
				bat.t += dt
				local k = bat.t / bat.duration
				if k >= 1 or destroyed then
					bat.label:Destroy()
					table.remove(bats, i)
					continue
				end
				local x = bat.from + (bat.to - bat.from) * k
				local y = bat.y + math.sin(k * math.pi * 2 + bat.seed) * 26 * scale - math.sin(k * math.pi) * 20 * scale
				bat.label.Position = UDim2.fromOffset(x, y)
				bat.label.Rotation = math.sin(now * 16 + bat.seed) * 10
				local flap = 0.82 + 0.18 * math.abs(math.sin(now * 14 + bat.seed))
				bat.label.Size = UDim2.fromOffset(bat.size, bat.size * flap)
			end
		end

		-- Tytuł lekko się unosi
		if EFFECTS then
			title.Position = UDim2.fromOffset(0, 72 + math.sin((now - startedAt) * 1.4) * 2.5)
		end
	end)

	local handle: Handle

	local function setStage(stage: string)
		if stage == stageId then
			return
		end
		stageId = stage
		local value = theme.stages[stage]
		stageText = if value then text(value, locale) else ""
		status.TextTransparency = 0.7
		tween(status, 0.3, { TextTransparency = 0 })
	end

	local function destroy()
		if destroyed then
			return
		end
		destroyed = true
		connection:Disconnect()
		gui:Destroy()
	end

	handle = {
		gui = gui,
		setTarget = function(progress: number)
			target = math.clamp(math.max(target, progress), 0, 1)
		end,
		setStage = setStage,
		shown = function(): number
			return shownProgress
		end,
		-- Pasek dobiega do końca, biegacz robi radosny podskok
		complete = function()
			target = 1
			local t0 = os.clock()
			while shownProgress < 0.999 and os.clock() - t0 < 3 and not destroyed do
				RunService.RenderStepped:Wait()
			end
			shownProgress = 1
			done = true
			setStage("done")
			celebrate = 1
			if hasSprites and not destroyed then
				local stackPos = stack.AbsolutePosition
				local px = stackPos.X + (BAR_X + runnerX) * scale
				local py = stackPos.Y + (BAR_Y - runnerSize * 0.5) * scale
				for _ = 1, 18 do
					local angle = math.random() * math.pi * 2
					local speed = (80 + math.random() * 140) * scale
					spawnParticle("spark", px, py, math.cos(angle) * speed, math.sin(angle) * speed - 60 * scale, (3 + math.random() * 3) * scale, 0.7 + math.random() * 0.4, theme.particles[math.random(1, #theme.particles)])
				end
			end
			task.wait(0.75)
		end,
		-- Ściemnienie. toBlack: ekran zostaje czarny (np. pod intro), inaczej czerń znika i widać grę.
		-- onBlack woła się, gdy ekran jest całkiem czarny.
		fadeOut = function(toBlack: boolean, onBlack: (() -> ())?)
			if destroyed then
				if onBlack then
					onBlack()
				end
				return
			end
			tween(black, 0.4, { BackgroundTransparency = 0 }, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
			task.wait(0.42)
			root.Visible = false
			if onBlack then
				onBlack()
			end
			if toBlack or destroyed then
				return
			end
			task.wait(0.15)
			tween(black, 0.8, { BackgroundTransparency = 1 }, Enum.EasingStyle.Sine)
			task.wait(0.82)
			destroy()
		end,
		destroy = destroy,
	}

	showTip()
	gui.Parent = parent or Players.LocalPlayer:WaitForChild("PlayerGui")
	rescale()
	return handle
end

-- Podgląd w Studio (pasek poleceń, model Client): ekran z udawanym postępem
function LoadingUI.preview(themeId: string?, seconds: number?)
	local ui = LoadingUI.new(themeId)
	local total = seconds or 10
	local stages = { "connect", "world", "assets", "save" }
	local t0 = os.clock()
	task.spawn(function()
		while os.clock() - t0 < total do
			local k = (os.clock() - t0) / total
			ui.setStage(stages[math.min(#stages, math.floor(k * #stages) + 1)])
			ui.setTarget(math.min(0.97, k * k * (3 - 2 * k)))
			task.wait(0.1)
		end
		ui.complete()
		ui.fadeOut(false)
	end)
	return ui
end

return LoadingUI
