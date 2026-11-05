--!strict
-- Karta zdobyczy: nowa wyjątkowa forma w Grzybopedii (Złoty i lepsze, grzyb strażnika, grzyb z kuźni;
-- decyduje serwer, Shared/Showcase.cardWorthy). U góry ekranu, nie blokuje chodzenia ani pościgu i sama
-- znika po Config.Showcase.cardSeconds. Obracający się model grzyba (ViewportFrame), nazwa w kolorze klasy,
-- rzadkość i wariant, cechy, wartość. Przycisk „Wystaw w gablocie” stawia grzyb na pierwszym wolnym
-- miejscu gabloty z dowolnego miejsca (ShowcaseService, op "quick"); bez wolnego miejsca karta podpowiada,
-- że miejsca kupuje się przy regale w ogródku.
-- Zdarzenie FindCard ma tylko tego jednego odbiorcę (zasada 4 w CLAUDE.md).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Economy = require(Shared:WaitForChild("Economy"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Audio = require(script.Parent.Audio)
local ClassColor = require(script.Parent.ClassColor)
local DisplayMushrooms = require(script.Parent.DisplayMushrooms)
local Localize = require(script.Parent.Localize)
local MushroomView = require(script.Parent.MushroomView)
local MutationText = require(script.Parent.MutationText)
local PanelKit = require(script.Parent.PanelKit)
local UiKit = require(script.Parent.UiKit)
local UiScale = require(script.Parent.UiScale)

local FindCard = {}

local player = Players.LocalPlayer
local WIDTH, HEIGHT = 380, 150
local TOP = 150 -- pod paskiem strefy, oleju i zapowiedzią nocy

local gui = Instance.new("ScreenGui")
gui.Name = "FindCard"
gui.ResetOnSpawn = false
gui.DisplayOrder = 20
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local card = Instance.new("Frame")
card.Name = "Card"
card.AnchorPoint = Vector2.new(0.5, 0)
card.Size = UDim2.fromOffset(WIDTH, HEIGHT)
card.BackgroundColor3 = Color3.fromRGB(26, 18, 40)
card.BackgroundTransparency = 0.05
card.Visible = false
card.Parent = gui
PanelKit.corner(card, UDim.new(0, 18))
local border = PanelKit.stroke(card, PanelKit.GOLD, 3)
local cardScale = Instance.new("UIScale")
cardScale.Parent = card

-- Model grzyba w okienku po lewej
local viewport = Instance.new("ViewportFrame")
viewport.Name = "Model"
viewport.Size = UDim2.fromOffset(126, 126)
viewport.Position = UDim2.fromOffset(12, 12)
viewport.BackgroundColor3 = Color3.fromRGB(44, 30, 64)
viewport.Ambient = Color3.fromRGB(190, 180, 210)
viewport.LightColor = Color3.fromRGB(255, 240, 220)
viewport.LightDirection = Vector3.new(-1, -1.5, -1)
viewport.Parent = card
PanelKit.corner(viewport, UDim.new(0, 14))
local world = Instance.new("WorldModel")
world.Parent = viewport
local camera = Instance.new("Camera")
camera.FieldOfView = 40
camera.Parent = viewport
viewport.CurrentCamera = camera

local LEFT = 150
local head = PanelKit.label(card, "Head", UDim2.new(1, -LEFT - 40, 0, 20), UDim2.fromOffset(LEFT, 12), 18, PanelKit.GOLD)
head.TextXAlignment = Enum.TextXAlignment.Left
local nameLabel = PanelKit.label(card, "Name", UDim2.new(1, -LEFT - 12, 0, 28), UDim2.fromOffset(LEFT, 32), 26)
nameLabel.TextXAlignment = Enum.TextXAlignment.Left
UiKit.outline(nameLabel, 2)
local badges = PanelKit.label(card, "Badges", UDim2.new(1, -LEFT - 12, 0, 16), UDim2.fromOffset(LEFT, 62), 14, PanelKit.MUTED, PanelKit.BODY_FONT)
badges.TextXAlignment = Enum.TextXAlignment.Left
local traits = PanelKit.label(card, "Traits", UDim2.new(1, -LEFT - 12, 0, 16), UDim2.fromOffset(LEFT, 79), 14, PanelKit.TEXT, PanelKit.BODY_FONT)
traits.TextXAlignment = Enum.TextXAlignment.Left
UiKit.outline(traits, 1)

local button = Instance.new("TextButton")
button.Name = "Show"
button.Size = UDim2.new(1, -LEFT - 12, 0, 36)
button.Position = UDim2.fromOffset(LEFT, 102)
button.BackgroundColor3 = UiKit.COLORS.green
button.AutoButtonColor = true
button.Text = ""
button.Parent = card
PanelKit.corner(button, UDim.new(0, 12))
PanelKit.stroke(button, PanelKit.OUTLINE, 2.5)
local buttonText = PanelKit.label(button, "Text", UDim2.new(1, -12, 1, -8), UDim2.fromOffset(6, 4), 18)
UiKit.outline(buttonText, 2)
local hint = PanelKit.label(card, "Hint", UDim2.new(1, -LEFT - 12, 0, 36), UDim2.fromOffset(LEFT, 102), 14, PanelKit.MUTED, PanelKit.BODY_FONT)
hint.TextWrapped = true
hint.TextXAlignment = Enum.TextXAlignment.Left

local close = Instance.new("TextButton")
close.Name = "Close"
close.Size = UDim2.fromOffset(28, 28)
close.AnchorPoint = Vector2.new(0.5, 0.5)
close.Position = UDim2.new(1, -4, 0, 4)
close.BackgroundColor3 = Color3.fromRGB(196, 44, 40)
close.Text = "X" -- FredokaOne nie ma znaku „✕”
close.TextScaled = true
close.Font = PanelKit.TITLE_FONT
close.TextColor3 = Color3.new(1, 1, 1)
close.ZIndex = 3
close.Parent = card
PanelKit.corner(close, UDim.new(1, 0))
PanelKit.stroke(close, PanelKit.OUTLINE, 2)

type Shown = { s: string, v: string?, x: { string }?, newSpecies: boolean?, value: number?, canShow: boolean? }

local current: Shown? = nil
local modelId: string? = nil
local token = 0
local spin = 0
local counter = 0

local function formatCoins(value: number): string
	local s = tostring(math.floor(value + 0.5))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (formatted:gsub("^ ", ""))
end

local function clearModel()
	if modelId then
		MushroomView.forget(modelId)
		modelId = nil
	end
end

local function hide()
	token += 1
	current = nil
	if not card.Visible then
		clearModel()
		return
	end
	local mine = token
	local tween = TweenService:Create(card, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(0.5, 0, 0, -HEIGHT - 20) })
	tween:Play()
	tween.Completed:Once(function()
		if token == mine then
			card.Visible = false
			clearModel()
		end
	end)
end

local function setButton(canShow: boolean)
	button.Visible = canShow
	hint.Visible = not canShow
	buttonText.Text = "🏆 " .. Localize.t("FINDCARD_SHOW")
	hint.Text = Localize.t("FINDCARD_FULL")
end

local function show(payload: Shown)
	clearModel()
	current = payload
	token += 1
	local mine = token
	counter += 1
	-- Model: ten sam wygląd co w lesie, tylko bez świateł (ViewportFrame i tak ich nie rysuje)
	local id = "findcard_" .. counter
	MushroomView.add({ { id = id, position = Vector3.zero, species = payload.s, variant = payload.v, tags = payload.x } }, {
		decorative = true,
		parent = world,
		grow = false,
		fit = Vector2.new(4, 5),
		glow = 0,
	})
	modelId = id
	spin = 0
	local def = Economy.getSpecies(payload.s)
	head.Text = "✨ " .. Localize.t(if payload.newSpecies then "FINDCARD_NEW_SPECIES" else "FINDCARD_NEW_FORM")
	nameLabel.Text = if def then Localize.t(def.key) else payload.s
	ClassColor.paint(nameLabel, payload.s)
	badges.Text = DisplayMushrooms.badges(payload.s, payload.v)
	local tagText = MutationText.rich(nil, payload.x)
	local value = tonumber(payload.value)
	traits.Text = (if tagText ~= "" then tagText .. "   " else "") .. (if value then "💰 " .. formatCoins(value) else "")
	setButton(payload.canShow == true)
	local class = Economy.speciesClass(payload.s)
	border.Color = Color3.fromRGB(class.color[1], class.color[2], class.color[3])
	-- Wjazd z góry
	card.Visible = true
	card.Position = UDim2.new(0.5, 0, 0, -HEIGHT - 20)
	TweenService:Create(card, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, math.floor(TOP * UiScale.get())),
	}):Play()
	Audio.play("levelup", { volume = 0.45 })
	task.delay(Config.Showcase.cardSeconds, function()
		if token == mine then
			hide()
		end
	end)
end

button.Activated:Connect(function()
	local shown = current
	if not shown then
		return
	end
	Remotes.get("ShowcaseAction"):FireServer({ op = "quick", item = { s = shown.s, v = shown.v } })
	Audio.play("ping", { volume = 0.5 })
	hide()
end)
close.Activated:Connect(hide)

local function layout()
	cardScale.Scale = UiScale.get()
	if card.Visible and current then
		card.Position = UDim2.new(0.5, 0, 0, math.floor(TOP * UiScale.get()))
	end
end

function FindCard.start()
	gui.Parent = player:WaitForChild("PlayerGui")
	layout()
	UiScale.onChanged(layout)
	Remotes.get("FindCard").OnClientEvent:Connect(function(payload: any)
		if typeof(payload) == "table" and typeof(payload.s) == "string" and Economy.getSpecies(payload.s) then
			show(payload)
		end
	end)
	-- Kamera krąży wokół grzyba
	RunService.RenderStepped:Connect(function(dt)
		if not card.Visible then
			return
		end
		spin += dt * 0.9
		local target = Vector3.new(0, 2.3, 0)
		camera.CFrame = CFrame.lookAt(target + Vector3.new(math.sin(spin) * 8.5, 1.6, math.cos(spin) * 8.5), target)
	end)
end

return FindCard
