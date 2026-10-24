--!strict
-- Wszystko, co mówi graczowi „uważaj, kończy się olej”:
-- czerwona winieta na brzegach ekranu, baner „Wracaj do chatki!” ze strzałką i odległością,
-- oraz oczy Leszego, które błyskają w ciemności, gdy latarnia prawie gaśnie.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Localize = require(script.Parent.Localize)
local UiScale = require(script.Parent.UiScale)

local Warnings = {}

-- Punkt, do którego prowadzi strzałka: drzwi chatki
local CABIN_DOOR = Vector3.new(0, 0, -10)
local EYES_FRACTION = 0.15 -- poniżej tylu procent oleju w ciemnych strefach pojawiają się oczy

local gui = Instance.new("ScreenGui")
gui.Name = "Warnings"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 2
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

-- ===== Winieta =====
-- Cztery ramki z gradientem. Bez CanvasGroup: na słabszym sprzęcie (i w Studio przy braku pamięci GPU)
-- CanvasGroup ignorował przezroczystość i zalewał cały ekran na czerwono.

local vignette = Instance.new("Frame")
vignette.Name = "Vignette"
vignette.Size = UDim2.new(1, 0, 1, 0)
vignette.BackgroundTransparency = 1
vignette.Parent = gui

local edges: { Frame } = {}
local appliedVignette = -1

local function edge(size: UDim2, position: UDim2, rotation: number)
	local frame = Instance.new("Frame")
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = Color3.fromRGB(90, 6, 6)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = vignette
	table.insert(edges, frame)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = frame
end
edge(UDim2.new(1, 0, 0.3, 0), UDim2.new(0, 0, 0, 0), 90) -- góra
edge(UDim2.new(1, 0, 0.3, 0), UDim2.new(0, 0, 0.7, 0), -90) -- dół
edge(UDim2.new(0.22, 0, 1, 0), UDim2.new(0, 0, 0, 0), 0) -- lewo
edge(UDim2.new(0.22, 0, 1, 0), UDim2.new(0.78, 0, 0, 0), 180) -- prawo

-- ===== Baner „Wracaj!” =====

local banner = Instance.new("Frame")
banner.Name = "TurnBack"
banner.Size = UDim2.new(0, 300, 0, 64)
banner.Position = UDim2.new(0.5, 0, 0, 132)
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.BackgroundColor3 = Color3.fromRGB(120, 24, 18)
banner.BackgroundTransparency = 0.1
banner.Visible = false
banner.Parent = gui
local bannerCorner = Instance.new("UICorner")
bannerCorner.CornerRadius = UDim.new(0, 14)
bannerCorner.Parent = banner
local bannerStroke = Instance.new("UIStroke")
bannerStroke.Thickness = 2
bannerStroke.Color = Color3.fromRGB(255, 170, 120)
bannerStroke.Parent = banner
local bannerScale = Instance.new("UIScale")
bannerScale.Parent = banner

local arrow = Instance.new("TextLabel")
arrow.Name = "Arrow"
arrow.Size = UDim2.new(0, 48, 0, 48)
arrow.Position = UDim2.new(0, 10, 0.5, 0)
arrow.AnchorPoint = Vector2.new(0, 0.5)
arrow.BackgroundTransparency = 1
arrow.Text = "▲"
arrow.TextColor3 = Color3.fromRGB(255, 230, 180)
arrow.Font = Enum.Font.GothamBlack
arrow.TextScaled = true
arrow.Parent = banner

local bannerText = Instance.new("TextLabel")
bannerText.Name = "Text"
bannerText.Size = UDim2.new(1, -72, 0, 30)
bannerText.Position = UDim2.new(0, 64, 0, 6)
bannerText.BackgroundTransparency = 1
bannerText.TextColor3 = Color3.fromRGB(255, 244, 228)
bannerText.Font = Enum.Font.FredokaOne
bannerText.TextScaled = true
bannerText.TextXAlignment = Enum.TextXAlignment.Left
bannerText.Parent = banner

local distanceText = Instance.new("TextLabel")
distanceText.Name = "Distance"
distanceText.Size = UDim2.new(1, -72, 0, 22)
distanceText.Position = UDim2.new(0, 64, 0, 36)
distanceText.BackgroundTransparency = 1
distanceText.TextColor3 = Color3.fromRGB(255, 200, 170)
distanceText.Font = Enum.Font.GothamBold
distanceText.TextScaled = true
distanceText.TextXAlignment = Enum.TextXAlignment.Left
distanceText.Parent = banner

-- Baner tuż pod paskiem oleju; na telefonie HUD jest mniejszy, więc baner wędruje wyżej
local uiScale = 1
UiScale.onChanged(function()
	uiScale = UiScale.get()
	banner.Position = UDim2.new(0.5, 0, 0, UiScale.topInset() + 8 + math.floor(66 * uiScale) + 8)
end)

local function refreshTexts()
	bannerText.Text = "⚠ " .. Localize.t("HUD_TURN_BACK")
end
refreshTexts()
Localize.onChanged(refreshTexts)

-- ===== Oczy Leszego =====

local nextEyesAt = 0

local function spawnEyes(rootPosition: Vector3, lanternRange: number)
	local camera = Workspace.CurrentCamera
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		return
	end
	-- Gdzieś przed graczem, tuż za kręgiem światła, trochę w bok
	local angle = math.rad(math.random(-55, 55))
	local dir = CFrame.Angles(0, angle, 0):VectorToWorldSpace(flat.Unit)
	local distance = lanternRange + math.random(6, 12)
	local center = rootPosition + dir * distance + Vector3.new(0, math.random(25, 45) / 10, 0)
	local side = dir:Cross(Vector3.yAxis).Unit

	local model = Instance.new("Model")
	model.Name = "LeszyEyes"
	local eyes = {}
	for _, s in { -1, 1 } do
		local eye = Instance.new("Part")
		eye.Shape = Enum.PartType.Ball
		eye.Size = Vector3.new(0.32, 0.32, 0.32)
		eye.Position = center + side * 0.3 * s
		eye.Color = Color3.fromRGB(255, 40, 30)
		eye.Material = Enum.Material.Neon
		eye.Anchored = true
		eye.CanCollide = false
		eye.CanQuery = false
		eye.CanTouch = false
		eye.CastShadow = false
		eye.Transparency = 1
		eye.Parent = model
		table.insert(eyes, eye)
	end
	model.Parent = Workspace

	task.spawn(function()
		local fade = TweenInfo.new(0.5)
		for _, eye in eyes do
			TweenService:Create(eye, fade, { Transparency = 0 }):Play()
		end
		task.wait(1.4)
		-- Mrugnięcie
		for _, eye in eyes do
			eye.Transparency = 1
		end
		task.wait(0.12)
		for _, eye in eyes do
			eye.Transparency = 0
		end
		task.wait(0.9)
		for _, eye in eyes do
			TweenService:Create(eye, fade, { Transparency = 1 }):Play()
		end
		task.wait(0.6)
		model:Destroy()
	end)
end

-- ===== Aktualizacja co klatkę =====

local pulseTime = 0

-- oilFraction 0-1, turnBack: czy pokazać baner, zone: strefa gracza
function Warnings.update(dt: number, rootPosition: Vector3, oilFraction: number, turnBack: boolean, zone: number, lanternRange: number)
	pulseTime += dt

	-- Winieta: od 25% oleju w dół coraz mocniej, z pulsowaniem jak bicie serca
	local danger = 0
	if zone ~= 1 and oilFraction < Config.OilLowFraction then
		danger = 1 - oilFraction / Config.OilLowFraction
	end
	if turnBack then
		danger = math.max(danger, 0.25)
	end
	local pulse = 0.5 + 0.5 * math.sin(pulseTime * (4 + danger * 4))
	local strength = danger * (0.55 + 0.45 * pulse)
	local transparency = 1 - math.clamp(strength * 0.85, 0, 0.85)
	-- Zaokrąglamy, żeby nie zapisywać właściwości w każdej klatce bez potrzeby
	transparency = math.floor(transparency * 50 + 0.5) / 50
	if transparency ~= appliedVignette then
		appliedVignette = transparency
		for _, frame in edges do
			frame.BackgroundTransparency = transparency
		end
	end

	-- Baner ze strzałką do chatki
	banner.Visible = turnBack
	if turnBack then
		local toDoor = CABIN_DOOR - rootPosition
		local flatDir = Vector3.new(toDoor.X, 0, toDoor.Z)
		local camera = Workspace.CurrentCamera
		local forward = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
		local right = Vector3.new(camera.CFrame.RightVector.X, 0, camera.CFrame.RightVector.Z)
		if flatDir.Magnitude > 0.1 and forward.Magnitude > 0.01 then
			local d = flatDir.Unit
			arrow.Rotation = math.deg(math.atan2(d:Dot(right.Unit), d:Dot(forward.Unit)))
		end
		distanceText.Text = Localize.t("HUD_DISTANCE", { math.floor(flatDir.Magnitude / 3.5) }) -- 3,5 studs ≈ 1 m
		bannerScale.Scale = uiScale * (1 + 0.04 * math.sin(pulseTime * 6))
	end

	-- Oczy w ciemności, gdy latarnia prawie gaśnie
	if zone >= 3 and oilFraction < EYES_FRACTION and os.clock() >= nextEyesAt then
		nextEyesAt = os.clock() + math.random(50, 80) / 10
		spawnEyes(rootPosition, lanternRange)
	end
end

return Warnings
