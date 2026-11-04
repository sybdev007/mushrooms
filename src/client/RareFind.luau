--!strict
-- Wielkie znalezisko w lesie: chwila, którą gracz zapamięta (i widzi, że trafił coś rzadkiego).
--   Epicki gatunek  -> błysk ekranu, dźwięk i duży napis „★ EPICKI! ★” z nazwą grzyba.
--   Legendarny gatunek, tęczowy albo kosmiczny grzyb -> karta na środku ekranu z promieniami,
--                      kręcącym się grzybem (kopia modelu z lasu w ViewportFrame), nazwą, mutacjami
--                      i wartością, do tego lekkie potrząśnięcie kamerą. Serwer ogłasza takie
--                      znalezisko całemu serwerowi (GameService.onPick, MSG_RARE_FIND).
-- Nic tu nie przyjmuje kliknięć: karta nie zasłania sterowania (np. w ucieczce przed strażnikiem).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Economy)
local Audio = require(script.Parent.Audio)
local Localize = require(script.Parent.Localize)
local MushroomView = require(script.Parent.MushroomView)
local MutationText = require(script.Parent.MutationText)
local PanelKit = require(script.Parent.PanelKit)
local ShopLook = require(script.Parent.ShopLook)
local UiKit = require(script.Parent.UiKit)
local UiScale = require(script.Parent.UiScale)

local RareFind = {}

export type Level = "epic" | "legendary"

local player = Players.LocalPlayer
local CARD_BG = Color3.fromRGB(34, 24, 52)
local VALUE_COLOR = Color3.fromRGB(255, 214, 70)

-- Jak wielkie jest znalezisko (nil = zwykłe, wystarczy „+N” nad grzybem)
function RareFind.level(species: string, variant: string?): Level?
	local classRank = MushroomView.classRank(species)
	if classRank >= 4 or Economy.variantRank(variant) >= 3 then
		return "legendary"
	elseif classRank == 3 then
		return "epic"
	end
	return nil
end

local function classColor(species: string): Color3
	local class = Economy.speciesClass(species)
	return Color3.fromRGB(class.color[1], class.color[2], class.color[3])
end

-- 480000 → „480 000”
local function formatNumber(value: number): string
	local text = tostring(math.floor(value + 0.5))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (formatted:gsub("^ ", ""))
end

local function speciesName(species: string): string
	local def = Economy.getSpecies(species)
	return if def then Localize.t(def.key) else species
end

-- ===== Warstwa na ekranie =====

local gui = Instance.new("ScreenGui")
gui.Name = "RareFind"
gui.ResetOnSpawn = false
gui.DisplayOrder = 9
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local flash = Instance.new("Frame")
flash.Name = "Flash"
flash.Size = UDim2.fromScale(1, 1)
flash.BackgroundColor3 = Color3.new(1, 1, 1)
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.Active = false
flash.Parent = gui

local function flashScreen(color: Color3, strength: number)
	flash.BackgroundColor3 = color
	flash.BackgroundTransparency = 1 - strength
	TweenService:Create(flash, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
end

-- Lekkie potrząśnięcie kamerą (po kamerze gry, więc nie walczy z jej sterowaniem)
local shakeUntil = 0
local function shakeCamera(seconds: number, strength: number)
	shakeUntil = os.clock() + seconds
	local name = "RareFindShake"
	RunService:UnbindFromRenderStep(name)
	RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, function()
		local left = shakeUntil - os.clock()
		local camera = Workspace.CurrentCamera
		if left <= 0 or not camera then
			RunService:UnbindFromRenderStep(name)
			return
		end
		local k = strength * (left / seconds)
		local t = os.clock() * 40
		camera.CFrame *= CFrame.new(math.noise(t, 1.3) * k, math.noise(t, 7.1) * k, 0)
	end)
end

-- ===== Epicki: napis przez ekran =====

local splash = Instance.new("Frame")
splash.Name = "Splash"
splash.AnchorPoint = Vector2.new(0.5, 0.5)
splash.Position = UDim2.fromScale(0.5, 0.33)
splash.Size = UDim2.fromOffset(560, 120)
splash.BackgroundTransparency = 1
splash.Visible = false
splash.Parent = gui
local splashScale = Instance.new("UIScale")
splashScale.Parent = splash
local splashTitle = PanelKit.label(splash, "Title", UDim2.new(1, 0, 0, 74), UDim2.fromOffset(0, 0), 66)
UiKit.outline(splashTitle, 4)
local splashGradient = Instance.new("UIGradient")
splashGradient.Rotation = 90
splashGradient.Parent = splashTitle
local splashName = PanelKit.label(splash, "Name", UDim2.new(1, 0, 0, 34), UDim2.fromOffset(0, 78), 30)
UiKit.outline(splashName, 3)

local shown = 0

local function showSplash(species: string, variant: string?, tags: { string }?)
	shown += 1
	local token = shown
	local color = classColor(species)
	local class = Economy.speciesClass(species)
	splashTitle.Text = "★ " .. MutationText.upper(Localize.t(class.key)) .. "! ★"
	-- Jaśniej u góry, pełny kolor klasy u dołu (wyraźny fiolet zamiast bladego różu)
	splashGradient.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.35), color:Lerp(Color3.new(0, 0, 0), 0.1))
	local mutations = MutationText.rich(variant, tags)
	splashName.Text = speciesName(species) .. (if mutations ~= "" then " · " .. mutations else "")
	splash.Visible = true
	splashTitle.TextTransparency = 0
	splashName.TextTransparency = 0
	splash.Position = UDim2.fromScale(0.5, 0.33)
	local base = UiScale.get()
	splashScale.Scale = base * 0.35
	TweenService:Create(splashScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = base }):Play()
	flashScreen(color, 0.3)
	UiKit.burst(gui, splash.AbsolutePosition + splash.AbsoluteSize / 2, 20, { color, Color3.new(1, 1, 1), Color3.fromRGB(255, 150, 240) })
	Audio.play("shimmer", { volume = 0.9 })
	Audio.play("levelup", { volume = 0.5, pitch = 1.15 })
	task.delay(1.6, function()
		if shown ~= token then
			return
		end
		local info = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(splash, info, { Position = UDim2.fromScale(0.5, 0.27) }):Play()
		TweenService:Create(splashTitle, info, { TextTransparency = 1 }):Play()
		TweenService:Create(splashName, info, { TextTransparency = 1 }):Play()
		task.delay(0.5, function()
			if shown == token then
				splash.Visible = false
			end
		end)
	end)
end

-- ===== Legendarny, tęczowy, kosmiczny: karta z grzybem =====

local card = Instance.new("Frame")
card.Name = "Card"
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.Position = UDim2.fromScale(0.5, 0.33)
card.Size = UDim2.fromOffset(500, 156)
card.BackgroundColor3 = CARD_BG
card.Visible = false
card.Parent = gui
PanelKit.corner(card, UDim.new(0, 22))
local cardStroke = PanelKit.stroke(card, Color3.new(1, 1, 1), 4)
ShopLook.shade(card, Color3.fromRGB(150, 140, 170))
local cardScale = Instance.new("UIScale")
cardScale.Parent = card

local haloHolder = Instance.new("Frame")
haloHolder.Name = "HaloHolder"
haloHolder.BackgroundTransparency = 1
haloHolder.Size = UDim2.fromScale(1, 1)
haloHolder.Parent = card
local halo: Frame? = nil

local viewport = Instance.new("ViewportFrame")
viewport.Name = "Mushroom"
viewport.Size = UDim2.fromOffset(132, 132)
viewport.Position = UDim2.fromOffset(12, 12)
viewport.BackgroundTransparency = 1
viewport.Ambient = Color3.fromRGB(190, 180, 200)
viewport.LightColor = Color3.new(1, 1, 1)
viewport.LightDirection = Vector3.new(-1, -1.5, -1)
viewport.ZIndex = 4
viewport.Parent = card
local viewCamera = Instance.new("Camera")
viewCamera.FieldOfView = 40
viewCamera.Parent = viewport
viewport.CurrentCamera = viewCamera

local cardTitle = PanelKit.label(card, "Title", UDim2.new(1, -170, 0, 46), UDim2.fromOffset(156, 14), 40)
cardTitle.TextXAlignment = Enum.TextXAlignment.Left
cardTitle.ZIndex = 5
UiKit.outline(cardTitle, 3)
local cardName = PanelKit.label(card, "Name", UDim2.new(1, -170, 0, 30), UDim2.fromOffset(156, 64), 26)
cardName.TextXAlignment = Enum.TextXAlignment.Left
cardName.ZIndex = 5
UiKit.outline(cardName, 2.5)
local cardValue = PanelKit.label(card, "Value", UDim2.new(1, -170, 0, 32), UDim2.fromOffset(156, 102), 28, VALUE_COLOR)
cardValue.TextXAlignment = Enum.TextXAlignment.Left
cardValue.ZIndex = 5
UiKit.outline(cardValue, 2.5)

local spin: RBXScriptConnection? = nil

-- Kopia grzyba w okienku: bez snopu, kręgu na ziemi i kotwic (płaskie i duże), kamera krąży wokół
local function placeModel(model: Model?)
	if spin then
		spin:Disconnect()
		spin = nil
	end
	for _, child in viewport:GetChildren() do
		if child:IsA("Model") then
			child:Destroy()
		end
	end
	if not model then
		return
	end
	local min, max = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local name = d.Name
			if name == "Pillar" or string.sub(name, 1, 4) == "Ring" or d.Transparency >= 0.95 then
				d:Destroy()
			else
				local half = d.Size / 2
				min = min:Min(d.Position - half)
				max = max:Max(d.Position + half)
			end
		elseif d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Light") or d:IsA("Sound") or d:IsA("Trail") then
			d:Destroy()
		end
	end
	if min.X == math.huge then
		model:Destroy()
		return
	end
	model.Parent = viewport
	local center = (min + max) / 2
	local size = (max - min).Magnitude
	local distance = size * 1.45 + 1
	local start = os.clock()
	local function frame()
		local a = (os.clock() - start) * 1.6
		viewCamera.CFrame = CFrame.lookAt(center + Vector3.new(math.sin(a) * distance, size * 0.35, math.cos(a) * distance), center)
	end
	frame()
	spin = RunService.RenderStepped:Connect(frame)
end

local function showCard(species: string, variant: string?, tags: { string }?, value: number, snapshot: Model?)
	shown += 1
	local token = shown
	local variantRank = Economy.variantRank(variant)
	local legendaryClass = MushroomView.classRank(species) >= 4
	local accent = if variantRank >= 3 then MutationText.variantColor(variant) or classColor(species) else classColor(species)
	-- Tytuł: legendarna klasa albo wariant (tęcza, kosmos); drugi wiersz: nazwa z mutacjami
	if legendaryClass then
		local class = Economy.speciesClass(species)
		cardTitle.Text = string.format('<font color="#%s">★★ %s! ★★</font>', classColor(species):ToHex(), MutationText.upper(Localize.t(class.key)))
	else
		cardTitle.Text = MutationText.variantTitle(variant) .. "!"
	end
	local mutations = MutationText.rich(variant, tags)
	cardName.Text = speciesName(species) .. (if mutations ~= "" then " · " .. mutations else "")
	cardValue.Text = "+" .. formatNumber(value) .. " 💰"
	cardStroke.Color = accent
	if halo then
		halo:Destroy()
	end
	halo = ShopLook.halo(haloHolder, UDim2.fromOffset(78, 78), accent, 130, true, 1)
	placeModel(snapshot)

	card.Visible = true
	card.Position = UDim2.fromScale(0.5, 0.33)
	local base = UiScale.get()
	cardScale.Scale = base * 0.4
	TweenService:Create(cardScale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = base }):Play()
	flashScreen(accent, 0.45)
	shakeCamera(0.4, 0.35)
	UiKit.burst(gui, card.AbsolutePosition + card.AbsoluteSize / 2, 28, { accent, Color3.new(1, 1, 1), VALUE_COLOR })
	Audio.play("levelup", { volume = 0.9 })
	task.delay(0.15, function()
		Audio.play("shimmer", { volume = 1 })
	end)
	task.delay(3.4, function()
		if shown ~= token then
			return
		end
		local out = TweenService:Create(cardScale, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = base * 0.6 })
		out.Completed:Connect(function()
			if shown == token then
				card.Visible = false
				placeModel(nil)
			end
		end)
		out:Play()
	end)
end

-- Zebrany grzyb (Main.client, MushroomRemoved). snapshot: kopia modelu z lasu (MushroomView.snapshot)
function RareFind.show(species: string, variant: string?, tags: { string }?, value: number, snapshot: Model?)
	local level = RareFind.level(species, variant)
	if level == "legendary" then
		splash.Visible = false
		showCard(species, variant, tags, value, snapshot)
	else
		if snapshot then
			snapshot:Destroy()
		end
		if level == "epic" then
			card.Visible = false
			placeModel(nil)
			showSplash(species, variant, tags)
		end
	end
end

return RareFind
