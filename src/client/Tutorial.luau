--!strict
-- Samouczek po stronie klienta. Serwer pilnuje kroków (TutorialService), a ten moduł pokazuje:
--   • okna samouczka (TutorialWindow) z mini animacjami,
--   • kartę misji po lewej („Zbierz grzyby 2/5”) z paskiem postępu,
--   • drogę do celu: świecącą linię od gracza, strzałkę nad celem i strzałkę przy krawędzi ekranu,
--   • podświetlenie przycisku (reszta ekranu przyciemniona, wokół celu pulsujący pierścień i rączka),
--   • cutscenkę z kradzieżą w ogródku na koniec.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Audio = require(script.Parent.Audio)
local Hud = require(script.Parent.Hud)
local IntroCutscene = require(script.Parent.IntroCutscene)
local Localize = require(script.Parent.Localize)
local MushroomView = require(script.Parent.MushroomView)
local SellPanel = require(script.Parent.SellPanel)
local TutorialWindow = require(script.Parent.TutorialWindow)
local UiKit = require(script.Parent.UiKit)
local UiScale = require(script.Parent.UiScale)

local player = Players.LocalPlayer

local Tutorial = {}

local DONE = Config.Tutorial.done
local TITLE_FONT = Enum.Font.FredokaOne
local OUTLINE = UiKit.OUTLINE
local GOLD = Color3.fromRGB(255, 214, 70)

local function t(key: string, args: { any }?): string
	return Localize.t(key, args)
end

local function tween(object: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local tw = TweenService:Create(object, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

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

-- ===== Warstwa samouczka =====

local gui = Instance.new("ScreenGui")
gui.Name = "Tutorial"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 25
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

-- Karta misji po lewej stronie ekranu
local tracker = Instance.new("Frame")
tracker.Name = "Mission"
tracker.Size = UDim2.fromOffset(290, 84)
tracker.AnchorPoint = Vector2.new(0, 0.5)
tracker.Position = UDim2.new(0, 16, 0.45, 0)
tracker.BackgroundColor3 = Color3.new(1, 1, 1)
tracker.Visible = false
tracker.Parent = gui
corner(tracker, UDim.new(0, 16))
stroke(tracker, OUTLINE, 3.5)
local trackerShade = Instance.new("UIGradient")
trackerShade.Rotation = 90
trackerShade.Color = ColorSequence.new(Color3.fromRGB(252, 242, 214), Color3.fromRGB(236, 212, 164))
trackerShade.Parent = tracker
local trackerScale = Instance.new("UIScale")
trackerScale.Parent = tracker
local trackerSeal = Instance.new("Frame")
trackerSeal.Size = UDim2.fromOffset(56, 56)
trackerSeal.AnchorPoint = Vector2.new(0.5, 0.5)
trackerSeal.Position = UDim2.fromOffset(6, 10)
trackerSeal.Rotation = -10
trackerSeal.BackgroundColor3 = Color3.fromRGB(196, 44, 40)
trackerSeal.ZIndex = 3
trackerSeal.Parent = tracker
corner(trackerSeal, UDim.new(1, 0))
stroke(trackerSeal, OUTLINE, 3)
local trackerIcon = UiKit.icon("mushroom", trackerSeal, UDim2.fromScale(0.64, 0.64), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
trackerIcon.ZIndex = 4
local trackerHead = Instance.new("TextLabel")
trackerHead.BackgroundTransparency = 1
trackerHead.Size = UDim2.new(1, -54, 0, 18)
trackerHead.Position = UDim2.fromOffset(40, 6)
trackerHead.Font = TITLE_FONT
trackerHead.TextScaled = true
trackerHead.TextXAlignment = Enum.TextXAlignment.Left
trackerHead.TextColor3 = Color3.fromRGB(196, 44, 40)
trackerHead.Parent = tracker
local trackerText = Instance.new("TextLabel")
trackerText.BackgroundTransparency = 1
trackerText.Size = UDim2.new(1, -54, 0, 30)
trackerText.Position = UDim2.fromOffset(40, 24)
trackerText.Font = TITLE_FONT
trackerText.TextScaled = true
trackerText.TextWrapped = true
trackerText.TextXAlignment = Enum.TextXAlignment.Left
trackerText.TextColor3 = Color3.fromRGB(88, 52, 24)
trackerText.Parent = tracker
local trackerTextSize = Instance.new("UITextSizeConstraint")
trackerTextSize.MaxTextSize = 22
trackerTextSize.Parent = trackerText
local trackerBar = Instance.new("Frame")
trackerBar.Size = UDim2.new(1, -54, 0, 12)
trackerBar.Position = UDim2.new(0, 40, 1, -22)
trackerBar.BackgroundColor3 = Color3.fromRGB(70, 46, 30)
trackerBar.Parent = tracker
corner(trackerBar, UDim.new(1, 0))
stroke(trackerBar, OUTLINE, 2)
local trackerFill = Instance.new("Frame")
trackerFill.Size = UDim2.fromScale(0, 1)
trackerFill.BackgroundColor3 = Color3.fromRGB(120, 220, 90)
trackerFill.Parent = trackerBar
corner(trackerFill, UDim.new(1, 0))

local lastMission = ""
local lastProgress = -1

local function setMission(icon: string?, textValue: string?, progress: number?)
	if not textValue then
		if tracker.Visible then
			tween(tracker, 0.3, { Position = UDim2.new(0, -320, 0.45, 0) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			task.delay(0.3, function()
				if lastMission == "" then
					tracker.Visible = false
				end
			end)
		end
		lastMission = ""
		return
	end
	trackerHead.Text = t("TUT_MISSION")
	trackerText.Text = textValue
	UiKit.setIcon(trackerIcon, icon or "mushroom")
	local p = math.clamp(progress or 0, 0, 1)
	trackerFill.Size = UDim2.fromScale(p, 1)
	trackerFill.BackgroundColor3 = if p >= 1 then GOLD else Color3.fromRGB(120, 220, 90)
	if textValue ~= lastMission then
		-- Nowa misja wjeżdża z lewej
		tracker.Visible = true
		tracker.Position = UDim2.new(0, -320, 0.45, 0)
		tween(tracker, 0.45, { Position = UDim2.new(0, 16, 0.45, 0) }, Enum.EasingStyle.Back)
		Audio.play("ping", { volume = 0.5 })
	elseif progress and progress ~= lastProgress then
		trackerScale.Scale = UiScale.get() * 1.08
		tween(trackerScale, 0.3, { Scale = UiScale.get() }, Enum.EasingStyle.Back)
	end
	lastMission = textValue
	lastProgress = progress or 0
end

-- ===== Droga do celu =====

local target: Vector3? = nil
local arrow = Instance.new("Model")
arrow.Name = "TutorialArrow"
do
	local function arrowPart(size: Vector3, cf: CFrame, class: string?): BasePart
		local p = Instance.new(class or "Part") :: BasePart
		p.Size = size
		p.CFrame = cf
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = GOLD
		p.Parent = arrow
		return p
	end
	local shaft = arrowPart(Vector3.new(0.6, 1.4, 0.6), CFrame.new(0, 1.6, 0))
	-- Grot z dwóch klinów skierowanych w dół
	arrowPart(Vector3.new(0.6, 1, 0.8), CFrame.new(0, 0.5, 0.4) * CFrame.Angles(math.rad(180), 0, 0), "WedgePart")
	arrowPart(Vector3.new(0.6, 1, 0.8), CFrame.new(0, 0.5, -0.4) * CFrame.Angles(math.rad(180), math.rad(180), 0), "WedgePart")
	arrow.PrimaryPart = shaft
end
local arrowFolder = Instance.new("Folder")
arrowFolder.Name = "Tutorial"
arrowFolder.Parent = Workspace

local beamTarget = Instance.new("Attachment")
beamTarget.Name = "TutorialTarget"
beamTarget.Parent = Workspace.Terrain
local beam = Instance.new("Beam")
beam.Name = "TutorialBeam"
beam.Attachment1 = beamTarget
beam.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120), Color3.fromRGB(255, 180, 60))
beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.8, 0.35), NumberSequenceKeypoint.new(1, 1) })
beam.LightEmission = 1
beam.Width0 = 0.5
beam.Width1 = 0.5
beam.FaceCamera = true
beam.Segments = 10
beam.Enabled = false
beam.Parent = Workspace.Terrain

-- Strzałka przy krawędzi ekranu, gdy cel jest poza widokiem
local edge = UiKit.icon("upgrade", gui, UDim2.fromOffset(56, 56), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
edge.Visible = false
local distanceLabel = Instance.new("TextLabel")
distanceLabel.BackgroundTransparency = 1
distanceLabel.Size = UDim2.fromOffset(90, 26)
distanceLabel.AnchorPoint = Vector2.new(0.5, 0.5)
distanceLabel.Font = TITLE_FONT
distanceLabel.TextScaled = true
distanceLabel.TextColor3 = GOLD
distanceLabel.Visible = false
distanceLabel.Parent = gui
UiKit.outline(distanceLabel, 2.5)

local function setTarget(at: Vector3?)
	if at and target and (at - target).Magnitude < 0.1 then
		return
	end
	target = at
	arrow.Parent = if at then arrowFolder else nil
	beam.Enabled = at ~= nil
	if at then
		beamTarget.WorldPosition = at + Vector3.new(0, 0.4, 0)
		Audio.play("ping", { volume = 0.35 })
	end
	edge.Visible = false
	distanceLabel.Visible = false
end

-- ===== Podświetlenie przycisku =====

local spot = Instance.new("Frame")
spot.Name = "Spotlight"
spot.BackgroundTransparency = 1
spot.Size = UDim2.fromScale(1, 1)
spot.Visible = false
spot.Parent = gui
local veils: { Frame } = {}
for i = 1, 4 do
	local v = Instance.new("Frame")
	v.BackgroundColor3 = Color3.new(0, 0, 0)
	v.BackgroundTransparency = 0.45
	v.BorderSizePixel = 0
	v.Active = true -- klik obok celu nie przechodzi dalej
	v.Parent = spot
	veils[i] = v
end
local ring = Instance.new("Frame")
ring.BackgroundTransparency = 1
ring.AnchorPoint = Vector2.new(0.5, 0.5)
ring.Parent = spot
corner(ring, UDim.new(0, 20))
local ringStroke = stroke(ring, GOLD, 5)
local hand = Instance.new("TextLabel")
hand.BackgroundTransparency = 1
hand.Size = UDim2.fromOffset(54, 54)
hand.Text = "👆"
hand.TextScaled = true
hand.Rotation = -20
hand.Parent = spot
local hint = Instance.new("TextLabel")
hint.Size = UDim2.fromOffset(300, 64)
hint.BackgroundColor3 = Color3.fromRGB(252, 242, 214)
hint.Font = TITLE_FONT
hint.TextScaled = true
hint.TextWrapped = true
hint.TextColor3 = Color3.fromRGB(88, 52, 24)
hint.Parent = spot
corner(hint, UDim.new(0, 14))
stroke(hint, OUTLINE, 3)
local hintPad = Instance.new("UIPadding")
hintPad.PaddingLeft = UDim.new(0, 10)
hintPad.PaddingRight = UDim.new(0, 10)
hintPad.PaddingTop = UDim.new(0, 6)
hintPad.PaddingBottom = UDim.new(0, 6)
hintPad.Parent = hint

local spotTarget: GuiObject? = nil
local function setSpotlight(object: GuiObject?, textValue: string?)
	spotTarget = object
	spot.Visible = object ~= nil
	hint.Text = textValue or ""
	if object then
		Audio.play("whoosh", { volume = 0.4 })
	end
end

local function updateSpotlight()
	local object = spotTarget
	if not object then
		return
	end
	if not object.Visible or not object.Parent then
		spot.Visible = false
		return
	end
	spot.Visible = true
	local pad = 10
	-- Inne warstwy mogą zaczynać się niżej (pod paskiem Robloxa): przesunięcie to różnica ich początków
	local objectGui = object:FindFirstAncestorOfClass("ScreenGui")
	local offset = if objectGui then objectGui.AbsolutePosition - gui.AbsolutePosition else Vector2.zero
	local pos = object.AbsolutePosition + offset - Vector2.new(pad, pad)
	local size = object.AbsoluteSize + Vector2.new(pad * 2, pad * 2)
	local screen = gui.AbsoluteSize
	veils[1].Position = UDim2.fromOffset(0, 0)
	veils[1].Size = UDim2.fromOffset(screen.X, math.max(0, pos.Y))
	veils[2].Position = UDim2.fromOffset(0, pos.Y + size.Y)
	veils[2].Size = UDim2.fromOffset(screen.X, math.max(0, screen.Y - pos.Y - size.Y))
	veils[3].Position = UDim2.fromOffset(0, pos.Y)
	veils[3].Size = UDim2.fromOffset(math.max(0, pos.X), size.Y)
	veils[4].Position = UDim2.fromOffset(pos.X + size.X, pos.Y)
	veils[4].Size = UDim2.fromOffset(math.max(0, screen.X - pos.X - size.X), size.Y)
	local pulse = 1 + 0.06 * math.sin(os.clock() * 6)
	ring.Position = UDim2.fromOffset(pos.X + size.X / 2, pos.Y + size.Y / 2)
	ring.Size = UDim2.fromOffset(size.X * pulse, size.Y * pulse)
	ringStroke.Transparency = 0.2 * (1 - math.sin(os.clock() * 6))
	local bob = math.sin(os.clock() * 5) * 8
	hand.Position = UDim2.fromOffset(pos.X + size.X * 0.55, pos.Y + size.Y + bob - 6)
	-- Podpowiedź pod celem, jeśli się mieści (wtedy nie zasłania karty nad przyciskiem), inaczej nad nim
	local above = pos.Y + size.Y + 60 + 70 > screen.Y
	local hx = math.clamp(pos.X + size.X / 2 - 150, 10, screen.X - 310)
	hint.Position = UDim2.fromOffset(hx, if above then pos.Y - 80 else pos.Y + size.Y + 60)
end

-- ===== Konfetti =====

local function confetti(count: number?)
	local screen = gui.AbsoluteSize
	local colors = { Color3.fromRGB(255, 90, 90), Color3.fromRGB(255, 214, 70), Color3.fromRGB(110, 230, 120), Color3.fromRGB(90, 180, 255), Color3.fromRGB(200, 120, 255) }
	for i = 1, count or 60 do
		local piece = Instance.new("Frame")
		piece.BorderSizePixel = 0
		piece.BackgroundColor3 = colors[(i % #colors) + 1]
		piece.Size = UDim2.fromOffset(math.random(8, 14), math.random(12, 20))
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.Position = UDim2.fromOffset(screen.X / 2 + math.random(-60, 60), screen.Y * 0.4)
		piece.Rotation = math.random(0, 360)
		piece.ZIndex = 40
		piece.Parent = gui
		local x = math.random(0, screen.X)
		local up = TweenService:Create(piece, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset((x + screen.X / 2) / 2, screen.Y * (0.05 + math.random() * 0.25)),
		})
		up.Completed:Connect(function()
			local down = TweenService:Create(piece, TweenInfo.new(1.4 + math.random(), Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
				Position = UDim2.fromOffset(x, screen.Y + 30),
				Rotation = piece.Rotation + math.random(-540, 540),
			})
			down.Completed:Connect(function()
				piece:Destroy()
			end)
			down:Play()
		end)
		up:Play()
	end
	Audio.play("levelup", { volume = 0.6 })
end
Tutorial.confetti = confetti

-- ===== Cutscenka: kradzież w ogródku =====

local function myGarden(): Model?
	for _, model in CollectionService:GetTagged("GardenPlot") do
		if model:IsA("Model") and model:GetAttribute("OwnerUserId") == player.UserId then
			return model
		end
	end
	return nil
end

local function gardenHub(): BasePart?
	local garden = myGarden()
	local hub = garden and garden:FindFirstChild("Hub", true)
	return if hub and hub:IsA("BasePart") then hub else nil
end

local function playTheft(onDone: () -> ())
	local garden = myGarden()
	local character = player.Character
	local hub = gardenHub()
	if not garden or not character or not hub then
		onDone()
		return
	end
	local camera = Workspace.CurrentCamera
	local center = garden:GetPivot().Position
	local gate = hub.Position
	local inward = Vector3.new(center.X - gate.X, 0, center.Z - gate.Z)
	inward = if inward.Magnitude > 0.1 then inward.Unit else Vector3.new(0, 0, 1)
	local side = Vector3.new(-inward.Z, 0, inward.X)

	-- Złodziej: ciemny klon gracza z czerwoną opaską na oczach
	character.Archivable = true
	local thief = character:Clone()
	character.Archivable = false
	if not thief then
		onDone()
		return
	end
	thief.Name = "Thief"
	for _, d in thief:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Shirt") or d:IsA("Pants") or d:IsA("ShirtGraphic") or d:IsA("Accessory") or d:IsA("Decal") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Color = Color3.fromRGB(34, 30, 40)
			d.CanCollide = false
			d.CanQuery = false
		end
	end
	local humanoid = thief:FindFirstChildOfClass("Humanoid")
	local root = thief:FindFirstChild("HumanoidRootPart") :: BasePart?
	local head = thief:FindFirstChild("Head") :: BasePart?
	if not humanoid or not root or not head then
		thief:Destroy()
		onDone()
		return
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	root.Anchored = true
	local band = Instance.new("Part")
	band.Size = Vector3.new(head.Size.X + 0.08, head.Size.Y * 0.22, head.Size.Z + 0.08)
	band.Color = Color3.fromRGB(214, 40, 40)
	band.CanCollide = false
	band.Massless = true
	band.CFrame = head.CFrame * CFrame.new(0, head.Size.Y * 0.1, 0)
	band.Parent = thief
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = head
	weld.Part1 = band
	weld.Parent = band
	thief.Parent = Workspace
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	local function track(path: { string }): AnimationTrack?
		local node: Instance? = character:FindFirstChild("Animate")
		for _, name in path do
			node = node and node:FindFirstChild(name)
		end
		if node and node:IsA("Animation") then
			local ok, tr = pcall(function()
				return animator:LoadAnimation(node)
			end)
			return if ok then tr else nil
		end
		return nil
	end
	local walk = track({ "walk", "WalkAnim" })
	local run = track({ "run", "RunAnim" })

	local hip = humanoid.HipHeight + root.Size.Y / 2
	local start = gate - inward * 14 + side * 6
	local bed = gate + inward * 6
	local escape = gate - inward * 10 - side * 8
	local rootValue = Instance.new("CFrameValue")
	rootValue.Value = CFrame.lookAt(start + Vector3.new(0, hip, 0), bed + Vector3.new(0, hip, 0))
	local camValue = Instance.new("CFrameValue")
	camValue.Value = CFrame.lookAt(gate - inward * 10 + side * 14 + Vector3.new(0, 9, 0), gate + inward * 2)

	-- Łup: mały grzyb nad głową złodzieja
	local loot = Instance.new("Part")
	loot.Shape = Enum.PartType.Ball
	loot.Size = Vector3.new(2, 1.2, 2)
	loot.Color = Color3.fromRGB(255, 186, 70)
	loot.Material = Enum.Material.Neon
	loot.Anchored = true
	loot.CanCollide = false
	loot.Transparency = 1
	loot.Parent = Workspace

	-- Kinowe pasy i napis
	local scene = Instance.new("ScreenGui")
	scene.Name = "TheftScene"
	scene.IgnoreGuiInset = true
	scene.DisplayOrder = 45
	scene.Parent = player.PlayerGui
	local bars = {}
	for i, anchor in { 0, 1 } do
		local bar = Instance.new("Frame")
		bar.BackgroundColor3 = Color3.new(0, 0, 0)
		bar.BorderSizePixel = 0
		bar.AnchorPoint = Vector2.new(0, anchor)
		bar.Position = UDim2.fromScale(0, anchor)
		bar.Size = UDim2.new(1, 0, 0, 0)
		bar.Parent = scene
		bars[i] = bar
		tween(bar, 0.5, { Size = UDim2.new(1, 0, 0.11, 0) })
	end
	local shout = Instance.new("TextLabel")
	shout.BackgroundTransparency = 1
	shout.AnchorPoint = Vector2.new(0.5, 0.5)
	shout.Position = UDim2.fromScale(0.5, 0.2)
	shout.Size = UDim2.fromScale(0.7, 0.14)
	shout.Font = TITLE_FONT
	shout.TextScaled = true
	shout.TextColor3 = Color3.fromRGB(255, 80, 70)
	shout.Text = ""
	shout.Parent = scene
	UiKit.outline(shout, 4)
	local shoutScale = Instance.new("UIScale")
	shoutScale.Parent = shout

	local hidden = {}
	for _, g in player.PlayerGui:GetChildren() do
		if g:IsA("ScreenGui") and g ~= scene and g.Enabled then
			g.Enabled = false
			table.insert(hidden, g)
		end
	end
	local carrying = false
	local shake = 0
	local conn = RunService.RenderStepped:Connect(function(dt)
		if camera then
			camera.CameraType = Enum.CameraType.Scriptable
			local offset = CFrame.new()
			if shake > 0.01 then
				local k = os.clock() * 30
				offset = CFrame.Angles(math.noise(k, 1) * 0.04 * shake, math.noise(k, 2) * 0.04 * shake, 0)
				shake = math.max(0, shake - dt * 0.8)
			end
			camera.CFrame = camValue.Value * offset
		end
		root.CFrame = rootValue.Value
		if carrying then
			loot.CFrame = CFrame.new(root.Position + Vector3.new(0, 3.2, 0))
		end
	end)

	local function moveTo(at: Vector3, time: number, anim: AnimationTrack?, speed: number)
		if walk then
			walk:Stop(0.1)
		end
		if run then
			run:Stop(0.1)
		end
		if anim then
			anim:Play(0.1)
			anim:AdjustSpeed(speed)
		end
		local goal = at + Vector3.new(0, hip, 0)
		local dir = Vector3.new(goal.X - rootValue.Value.Position.X, 0, goal.Z - rootValue.Value.Position.Z)
		tween(rootValue, time, { Value = CFrame.lookAt(goal, goal + (if dir.Magnitude > 0 then dir else inward)) }, Enum.EasingStyle.Linear)
	end

	task.spawn(function()
		Audio.music("heist", 0.8)
		-- Złodziej skrada się do grządki
		moveTo(bed, 3.2, walk, 0.55)
		tween(camValue, 3.2, { Value = CFrame.lookAt(gate - inward * 3 + side * 9 + Vector3.new(0, 6, 0), bed) }, Enum.EasingStyle.Sine)
		for _ = 1, 4 do
			Audio.play("sneak", { volume = 0.6, jitter = 0.1 })
			task.wait(0.8)
		end
		-- Chwyta grzyba: alarm, czerwona poświata, napis
		if walk then
			walk:Stop(0.1)
		end
		loot.Transparency = 0
		carrying = true
		Audio.play("alarm", { duration = 2.4 })
		local glow = Instance.new("Highlight")
		glow.FillColor = Color3.fromRGB(255, 60, 60)
		glow.OutlineColor = Color3.fromRGB(255, 255, 255)
		glow.FillTransparency = 0.5
		glow.Parent = thief
		shout.Text = t("TUT_THIEF")
		shoutScale.Scale = 2
		tween(shoutScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		shake = 0.6
		task.wait(1)
		-- Ucieka… i potyka się o własne nogi
		Audio.music("chase", 0.3)
		moveTo(escape, 2.2, run, 1.3)
		tween(camValue, 2.2, { Value = CFrame.lookAt(escape + side * 7 + inward * 4 + Vector3.new(0, 5, 0), escape) }, Enum.EasingStyle.Sine)
		task.wait(1.4)
		if run then
			run:Stop(0.05)
		end
		Audio.music(nil, 0.1)
		Audio.play("boom")
		shake = 1
		local fallen = rootValue.Value * CFrame.new(0, -hip * 0.6, 0) * CFrame.Angles(math.rad(-80), 0, 0)
		tween(rootValue, 0.35, { Value = fallen }, Enum.EasingStyle.Bounce)
		carrying = false
		-- Grzyb wraca łukiem na grządkę
		local from = loot.Position
		local arcStart = os.clock()
		local arc = RunService.RenderStepped:Connect(function()
			local k = math.clamp((os.clock() - arcStart) / 1, 0, 1)
			local p = from:Lerp(bed + Vector3.new(0, 1, 0), k) + Vector3.new(0, math.sin(k * math.pi) * 6, 0)
			loot.CFrame = CFrame.new(p) * CFrame.Angles(k * 8, k * 5, 0)
		end)
		shout.Text = t("TUT_THIEF_FAIL")
		shoutScale.Scale = 1.6
		tween(shoutScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		task.wait(1.2)
		arc:Disconnect()
		Audio.play("pick")
		loot.Transparency = 1
		task.wait(0.8)
		-- Koniec sceny
		Audio.music("tutorial", 1.5)
		conn:Disconnect()
		thief:Destroy()
		loot:Destroy()
		for _, g in hidden do
			g.Enabled = true
		end
		if camera then
			camera.CameraType = Enum.CameraType.Custom
		end
		for _, bar in bars do
			tween(bar, 0.4, { Size = UDim2.new(1, 0, 0, 0) })
		end
		task.delay(0.5, function()
			scene:Destroy()
		end)
		onDone()
	end)
end

-- ===== Kroki =====

local stepNow = -2
local sellRule: string? = nil
local basketCount = 0
local basketMax = 5
local seen: { [string]: boolean } = {}
local busy = false -- trwa okno albo cutscenka

local function once(key: string): boolean
	if seen[key] then
		return false
	end
	seen[key] = true
	return true
end

local function window(pages: { TutorialWindow.Page }, after: (() -> ())?)
	busy = true
	setSpotlight(nil)
	TutorialWindow.show(pages, function()
		busy = false
		if after then
			after()
		end
	end)
end

local function nearestWithPrefix(prefix: string): Vector3?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local from = if root then root.Position else Vector3.zero
	local best: Vector3? = nil
	local bestDistance = math.huge
	for _, info in MushroomView.withPrefix(prefix) do
		local d = (info.position - from).Magnitude
		if d < bestDistance then
			bestDistance = d
			best = info.position
		end
	end
	return best
end

local function enterStep(step: number)
	setTarget(nil)
	setSpotlight(nil)
	Hud.setTutorialFocus(nil)
	if step == 1 then
		if once("s1") then
			window({
				{ title = t("TUT_WELCOME_T"), text = t("TUT_WELCOME"), icon = "mushroom" },
				{ title = t("TUT_PICK_T"), text = t("TUT_PICK"), icon = "basket", demo = "pick" },
			})
		end
	elseif step == 2 then
		if once("s2") then
			Hud.toast(t("TUT_FULL_TOAST"), "warn")
			Audio.play("full")
			window({
				{ title = t("TUT_FULL_T"), text = t("TUT_FULL"), icon = "basket", demo = "basket" },
				{ title = t("TUT_OIL_T"), text = t("TUT_OIL"), icon = "lantern", demo = "oil" },
			})
		end
	elseif step == 3 then
		SellPanel.close()
		confetti(30)
	elseif step == 4 then
		Hud.toggleUpgrades(false)
		confetti(50)
		if once("s4") then
			window({
				{ title = t("TUT_UPG_T"), text = t("TUT_UPG"), icon = "upgrade", demo = "upgrade" },
				{
					title = t("TUT_GARDEN_MISSION_T"),
					text = t("TUT_GARDEN_MISSION"),
					icon = "beds",
					reward = { icon = "coins", title = t("TUT_REWARD_COINS", { Config.Tutorial.reward }), text = t("TUT_REWARD_TEXT") },
				},
			})
		end
	elseif step == 5 then
		if once("s5") then
			window({
				{ title = t("TUT_PLANT_T"), text = t("TUT_PLANT"), icon = "beds", demo = "garden" },
			})
		end
	elseif step == 6 then
		if once("s6") then
			busy = true
			task.delay(1.5, function()
				playTheft(function()
					window({
						{ title = t("TUT_STEAL_T"), text = t("TUT_STEAL"), icon = "lock", demo = "steal" },
						{ title = t("TUT_STEAL2_T"), text = t("TUT_STEAL2"), icon = "chest" },
					}, function()
						confetti(90)
						window({
							{
								title = t("TUT_DONE_T"),
								text = t("TUT_DONE"),
								icon = "star",
								reward = { icon = "coins", title = t("TUT_REWARD_COINS", { Config.Tutorial.reward }), text = t("TUT_REWARD_TEXT") },
							},
						}, function()
							Remotes.get("TutorialStep"):FireServer(DONE)
						end)
					end)
				end)
			end)
		end
	end
end

-- Co klatkę: cel na mapie, misja i podświetlenia zależnie od kroku
local function update()
	local step = stepNow
	if step <= 0 or step >= DONE or IntroCutscene.isPlaying() then
		setTarget(nil)
		setSpotlight(nil)
		setMission(nil)
		return
	end
	if busy or TutorialWindow.isOpen() then
		return
	end
	if step == 1 then
		-- Cel: pełny koszyk albo wszystkie grzyby samouczka (gdy koszyk jest większy niż 5)
		local goal = math.max(1, math.min(basketMax, basketCount + #MushroomView.withPrefix("tut_")))
		setMission("mushroom", t("TUT_M_PICK", { basketCount, goal }), basketCount / goal)
		setTarget(nearestWithPrefix("tut_"))
	elseif step == 2 then
		setMission("sell", t("TUT_M_SELL"), 0)
		if SellPanel.isOpen() then
			-- W panelu prowadzi kupiec i strzałka (SellPanel.setGuide), tu nic nie zasłaniamy
			setTarget(nil)
		else
			setTarget(Vector3.new(Config.Merchant.x, 0, Config.Merchant.z + 5))
		end
	elseif step == 3 then
		setMission("upgrade", t("TUT_M_UPG"), 0)
		setTarget(nil)
		Hud.setTutorialFocus(Config.Tutorial.upgrade)
		if Hud.upgradesOpen() then
			setSpotlight(Hud.upgradeBuyButton(Config.Tutorial.upgrade), t("TUT_SPOT_BUY"))
		elseif not SellPanel.isOpen() then
			setSpotlight(Hud.upgradeButton(), t("TUT_SPOT_UPG"))
		end
	elseif step == 4 then
		local picked = #Config.Tutorial.gardenSpots - #MushroomView.withPrefix("tutg_")
		setMission("beds", t("TUT_M_GARDEN", { picked, #Config.Tutorial.gardenSpots }), picked / #Config.Tutorial.gardenSpots)
		setTarget(nearestWithPrefix("tutg_"))
	elseif step == 5 then
		setMission("beds", t("TUT_M_PLANT"), 0)
		local hub = gardenHub()
		setTarget(if hub then Vector3.new(hub.Position.X, 0, hub.Position.Z) else nil)
	elseif step == 6 then
		setMission("lock", t("TUT_M_STEAL"), 1)
		setTarget(nil)
	end
end

RunService.RenderStepped:Connect(function()
	update()
	updateSpotlight()
	-- Karta misji chowa się, kiedy otwarty jest panel sprzedaży albo ulepszeń (nachodziła na nie)
	if lastMission ~= "" then
		tracker.Visible = not (SellPanel.isOpen() or Hud.upgradesOpen())
	end
	-- Strzałka nad celem podskakuje i się kręci, linia biegnie od gracza
	local at = target
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if at and arrow.PrimaryPart then
		local now = os.clock()
		arrow:PivotTo(CFrame.new(at + Vector3.new(0, 3.2 + math.sin(now * 3) * 0.4, 0)) * CFrame.Angles(0, now * 2, 0) * CFrame.new(0, -1.6, 0))
		if root then
			local a0 = root:FindFirstChild("TutorialBeamStart") :: Attachment?
			if not a0 then
				local created = Instance.new("Attachment")
				created.Name = "TutorialBeamStart"
				created.Position = Vector3.new(0, -2.4, 0)
				created.Parent = root
				a0 = created
			end
			beam.Attachment0 = a0
			local distance = Vector3.new(at.X - root.Position.X, 0, at.Z - root.Position.Z).Magnitude
			-- Blisko celu linia gaśnie, żeby nie zasłaniała grzyba
			beam.Enabled = distance > 6
			local camera = Workspace.CurrentCamera
			if camera then
				local point, onScreen = camera:WorldToViewportPoint(at + Vector3.new(0, 2, 0))
				local screen = gui.AbsoluteSize
				if onScreen and point.X > 0 and point.X < screen.X and point.Y > 0 and point.Y < screen.Y then
					edge.Visible = false
					distanceLabel.Visible = distance > 8
					distanceLabel.Position = UDim2.fromOffset(point.X, point.Y - 30)
				else
					-- Cel poza ekranem: strzałka przy krawędzi wskazuje kierunek
					local center = screen / 2
					local dir = Vector2.new(point.X, point.Y) - center
					if point.Z < 0 then
						dir = -dir
					end
					if dir.Magnitude < 1 then
						dir = Vector2.new(0, 1)
					end
					local unit = dir.Unit
					local margin = 60
					local scaleX = (center.X - margin) / math.max(math.abs(unit.X), 0.001)
					local scaleY = (center.Y - margin) / math.max(math.abs(unit.Y), 0.001)
					local pos = center + unit * math.min(scaleX, scaleY)
					edge.Visible = true
					edge.Position = UDim2.fromOffset(pos.X, pos.Y)
					edge.Rotation = math.deg(math.atan2(unit.Y, unit.X)) + 90
					distanceLabel.Visible = true
					distanceLabel.Position = UDim2.fromOffset(pos.X - unit.X * 46, pos.Y - unit.Y * 46)
				end
				distanceLabel.Text = string.format("%d m", math.floor(distance + 0.5))
			end
		end
	else
		edge.Visible = false
		distanceLabel.Visible = false
	end
end)

UiScale.onChanged(function()
	trackerScale.Scale = UiScale.get()
end)
trackerScale.Scale = UiScale.get()

-- ===== API =====

function Tutorial.update(state: any)
	local step = if typeof(state.tutorial) == "number" then state.tutorial else DONE
	local previousCount = basketCount
	basketCount = state.basketCount or 0
	basketMax = state.basketMax or 5
	-- Sprzedaż krok po kroku: tryb panelu przychodzi od serwera
	sellRule = if step == 2 and typeof(state.tutorialSell) == "string" then state.tutorialSell else nil
	SellPanel.setGuide(sellRule)
	if step ~= stepNow then
		stepNow = step
		if step >= DONE then
			setTarget(nil)
			setSpotlight(nil)
			setMission(nil)
			Hud.setTutorialFocus(nil)
		elseif step > 0 and not IntroCutscene.isPlaying() then
			enterStep(step)
		end
	end
	-- Pierwszy zebrany grzyb: okno o plecaku
	if step == 1 and basketCount >= 1 and previousCount == 0 and once("firstpick") then
		Audio.play("levelup", { volume = 0.4 })
		window({
			{ title = t("TUT_BASKET_T"), text = t("TUT_BASKET"), icon = "basket", demo = "basket" },
		})
	end
end

-- Po cutscence na start (krok 1 przychodzi od serwera, kiedy scena się skończy)
function Tutorial.afterIntro()
	if stepNow == 1 then
		enterStep(1)
	end
end

return Tutorial
