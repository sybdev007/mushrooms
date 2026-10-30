--!strict
-- Halloween po stronie gracza (tylko wygląd i dźwięk, nic nie zmienia w grze):
--   duchy z wystroju (tag "HalloweenGhost") unoszą się i kołyszą,
--   sekretny zakątek (tag "HalloweenSecret"): komunikat, kiedy gracz go pierwszy raz znajdzie (w tej sesji),
--   Noc Dziadów: plansza z tytułem na początku nocy, większy księżyc, zielone błędne ogniki krążące
--   wokół gracza i co jakiś czas szepty, sowa albo śmiech wiedźmy w oddali.
-- Mrok nocy się nie zmienia (Atmosphere), więc grzyby zostają tak samo czytelne jak zwykle.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Audio = require(script.Parent.Audio)
local Hud = require(script.Parent.Hud)
local Localize = require(script.Parent.Localize)

local HalloweenFx = {}

local player = Players.LocalPlayer

-- ===== Duchy =====

-- Pozycję spoczynkową bierzemy dopiero, gdy model ma swoją główną część (StreamingEnabled: części
-- dochodzą później, a pivot pustego modelu to środek świata)
type Ghost = { model: Model, base: CFrame?, phase: number }
local ghosts: { [Model]: Ghost } = {}

local function addGhost(instance: Instance)
	if instance:IsA("Model") and not ghosts[instance] then
		ghosts[instance] = { model = instance, base = nil, phase = math.random() * math.pi * 2 }
	end
end

-- ===== Sekretny zakątek =====

local secrets: { BasePart } = {}
local secretFound = false

local function addSecret(instance: Instance)
	if instance:IsA("BasePart") then
		table.insert(secrets, instance)
	end
end

-- ===== Noc Dziadów =====

local function spiritNight(): boolean
	return Workspace:GetAttribute("Halloween") == true
		and Workspace:GetAttribute("CyclePhase") == "night"
		and Workspace:GetAttribute("CycleEvent") == "spirit_night"
end

local gui = Instance.new("ScreenGui")
gui.Name = "HalloweenFx"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 6
gui.Parent = player:WaitForChild("PlayerGui")

local function titleLabel(size: number, y: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, y)
	label.Size = UDim2.new(0.9, 0, 0, size)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.TextTransparency = 1
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(30, 10, 40)
	stroke.Transparency = 1
	stroke.Parent = label
	return label
end

local title = titleLabel(70, 0.3, Color3.fromRGB(205, 170, 255))
local subtitle = titleLabel(30, 0.3 + 0.075, Color3.fromRGB(235, 225, 255))

local function fadeText(label: TextLabel, to: number, time: number)
	TweenService:Create(label, TweenInfo.new(time), { TextTransparency = to }):Play()
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, TweenInfo.new(time), { Transparency = to }):Play()
	end
end

local cardToken = 0
local function showCard()
	cardToken += 1
	local token = cardToken
	title.Text = "👻 " .. Localize.t("HW_SPIRIT_TITLE") .. " 👻"
	subtitle.Text = Localize.t("HW_SPIRIT_SUB")
	Audio.play("swell", { volume = 0.6 })
	fadeText(title, 0, 1.2)
	task.delay(0.4, fadeText, subtitle, 0, 1.2)
	task.delay(5, function()
		if cardToken == token then
			fadeText(title, 1, 1.5)
			fadeText(subtitle, 1, 1.5)
		end
	end)
end

-- Błędne ogniki: zielone światełka krążące wokół gracza
local wispFolder = Instance.new("Folder")
wispFolder.Name = "SpiritWisps"
wispFolder.Parent = Workspace
type Wisp = { part: Part, light: PointLight, seed: number }
local wisps: { Wisp } = {}
for i = 1, 4 do
	local p = Instance.new("Part")
	p.Name = "Wisp"
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(0.5, 0.5, 0.5)
	p.Material = Enum.Material.Neon
	p.Color = if i % 2 == 0 then Color3.fromRGB(140, 255, 170) else Color3.fromRGB(180, 150, 255)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	local light = Instance.new("PointLight")
	light.Color = p.Color
	light.Range = 9
	light.Brightness = 0
	light.Parent = p
	p.Parent = wispFolder
	table.insert(wisps, { part = p, light = light, seed = i * 13.7 })
end

local AMBIENT = { "whisper", "owl", "witch", "swell" }
local nextAmbient = 0
local wasSpirit = false
local wispAlpha = 0 -- 0..1: ogniki płynnie się pojawiają i znikają
local NORMAL_MOON = 14
local SPIRIT_MOON = 26

local function update(dt: number)
	local now = os.clock()
	-- Duchy
	for model, ghost in ghosts do
		if not model.Parent then
			ghosts[model] = nil
			continue
		end
		local base = ghost.base
		if not base then
			if not model.PrimaryPart then
				continue
			end
			base = model:GetPivot()
			ghost.base = base
		end
		local bob = math.sin(now * 1.3 + ghost.phase) * 0.6
		local sway = math.sin(now * 0.7 + ghost.phase) * 0.25
		model:PivotTo((base :: CFrame) * CFrame.new(0, bob, 0) * CFrame.Angles(0, sway, math.sin(now * 1.1 + ghost.phase) * 0.08))
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local position = if root and root:IsA("BasePart") then root.Position else nil

	-- Sekret
	if position and not secretFound then
		for i = #secrets, 1, -1 do
			local marker = secrets[i]
			if not marker.Parent then
				table.remove(secrets, i)
			elseif (marker.Position - position).Magnitude < 12 then
				secretFound = true
				Audio.play("shimmer", { volume = 0.8 })
				Hud.toast(Localize.t("HW_SECRET_FOUND"), "gold")
				break
			end
		end
	end

	-- Noc Dziadów
	local spirit = spiritNight()
	if spirit ~= wasSpirit then
		wasSpirit = spirit
		local sky = Lighting:FindFirstChild("ForestSky")
		if sky and sky:IsA("Sky") then
			TweenService:Create(sky, TweenInfo.new(3), { MoonAngularSize = if spirit then SPIRIT_MOON else NORMAL_MOON }):Play()
		end
		if spirit then
			showCard()
			nextAmbient = now + 12
		end
	end
	wispAlpha = math.clamp(wispAlpha + (if spirit and position then dt else -dt) * 0.5, 0, 1)
	for _, wisp in wisps do
		local p = wisp.part
		if wispAlpha <= 0 or not position then
			p.Transparency = 1
			wisp.light.Brightness = 0
			continue
		end
		local t = now * 0.25
		local angle = t + wisp.seed + math.noise(t, wisp.seed) * 2
		local radius = 10 + math.noise(wisp.seed, t * 0.7) * 6
		local height = 2.5 + math.noise(t * 1.3, wisp.seed + 5) * 2
		p.Position = (position :: Vector3) + Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
		local flicker = 0.7 + 0.3 * math.noise(now * 3, wisp.seed)
		p.Transparency = 1 - 0.85 * wispAlpha * flicker
		wisp.light.Brightness = 1.2 * wispAlpha * flicker
	end
	if spirit and now >= nextAmbient then
		nextAmbient = now + 20 + math.random() * 20
		Audio.play(AMBIENT[math.random(1, #AMBIENT)], { volume = 0.35 })
	end
end

function HalloweenFx.start()
	CollectionService:GetInstanceAddedSignal("HalloweenGhost"):Connect(addGhost)
	for _, instance in CollectionService:GetTagged("HalloweenGhost") do
		addGhost(instance)
	end
	CollectionService:GetInstanceAddedSignal("HalloweenSecret"):Connect(addSecret)
	for _, instance in CollectionService:GetTagged("HalloweenSecret") do
		addSecret(instance)
	end
	RunService.RenderStepped:Connect(update)
end

return HalloweenFx
