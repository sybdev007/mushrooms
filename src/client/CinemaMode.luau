--!strict
-- Tryb filmowy (tylko deweloperzy, panel DEV → 🎬 Tryb filmowy): czyste kadry do nagrań na TikToka i Shorts.
-- Gra nic tu nie liczy ani nie zapisuje; wszystko dzieje się tylko u nagrywającego (klient).
--
--   Czysty ekran: chowa cały interfejs (gra, Roblox, kursor, napisy nad głowami), a ty grasz normalnie.
--   Ujęcia: gotowe ruchy kamery. Przy postaci (orbita, spacer na kamerę, nisko od tyłu, dron, makro grzyba)
--     i przeloty nad miejscami (las, gniazdo Leszego, chatka, portal, skarbiec, staw) z teleportem przed startem.
--     Przed każdym ujęciem jest odliczanie 3-2-1 (wytnij je w montażu); kadr trzyma obiekt na środku,
--     więc wycięcie pionu 9:16 ze środka obrazu 16:9 daje ten sam kadr co nagranie w pionie.
--   Wygląd: naturalny / filmowy (głębia ostrości, poświata) / jaśniej (do ciemnych stref).
--
-- Klawisze (tylko dla deweloperów; panel DEV znika razem z interfejsem):
--   L – czysty ekran wł./wył.   K – zatrzymaj ujęcie / wyjdź z czystego ekranu
--   J – ramka 9:16 (do ustawienia kadru, przed nagraniem wyłącz)   U – powtórz ostatnie ujęcie

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CutsceneKit = require(script.Parent.CutsceneKit)

local CinemaMode = {}

local player = Players.LocalPlayer
local DevAction = Remotes.get("DevAction")

local COUNTDOWN = 3 -- sekundy odliczania przed ujęciem
local HOLD_END = 0.6 -- tyle kadr stoi po końcu ujęcia, zanim wróci interfejs
local LIGHT_COLOR = Color3.fromRGB(255, 210, 150)

type Ctx = {
	root: BasePart,
	heading: Vector3, -- kierunek, w który patrzyła postać na starcie (bez pionu)
	start: Vector3, -- pozycja postaci na starcie
	target: Vector3?, -- grzyb w ujęciu makro
	angle0: number, -- kąt startowy dla ujęć wokół obiektu
}

type Shot = {
	id: string,
	duration: number,
	fov: number,
	tp: string?, -- akcja DEV z teleportem przed ujęciem (przeloty nad miejscami)
	walk: boolean?, -- postać sama idzie prosto przed siebie
	hideCharacter: boolean?,
	light: boolean?, -- ciepłe światło przy kamerze (w ciemnych strefach latarnia gracza jest za daleko)
	smooth: number?, -- wygładzanie ruchu kamery za postacią (nil = dokładna ścieżka)
	macro: boolean?, -- szuka najbliższego grzyba
	frame: (t: number, ctx: Ctx) -> (CFrame, Vector3), -- kamera i punkt ostrości
}

local function smoothstep(a: number): number
	a = math.clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

local function look(eye: Vector3, at: Vector3): CFrame
	return CFrame.lookAt(eye, at)
end

local function lerp(a: Vector3, b: Vector3, t: number): Vector3
	return a + (b - a) * t
end

local function around(center: Vector3, angle: number, radius: number, height: number): Vector3
	return center + Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
end

-- Najazd kamery z `from` do `to` patrząc na `at`, z lekkim bujaniem na boki
local function pushIn(from: Vector3, to: Vector3, at: Vector3, duration: number): (number, Ctx) -> (CFrame, Vector3)
	return function(t: number, _ctx: Ctx)
		local a = smoothstep(t / duration)
		local eye = lerp(from, to, a) + Vector3.new(math.sin(t * 0.6) * 0.6, math.sin(t * 0.9) * 0.25, 0)
		return look(eye, at), at
	end
end

local SHOTS: { Shot } = {
	-- ===== Przy postaci =====
	{
		id = "orbit",
		duration = 20,
		fov = 50,
		smooth = 6,
		frame = function(t, ctx)
			local p = ctx.root.Position
			local eye = around(p, ctx.angle0 + t * 0.32, 9, 2.6)
			return look(eye, p + Vector3.new(0, 1.2, 0)), p
		end,
	},
	{
		id = "walkFront",
		duration = 12,
		fov = 45,
		walk = true,
		smooth = 5,
		frame = function(_t, ctx)
			local p = ctx.root.Position
			local eye = p + ctx.heading * 7.5 + Vector3.new(0, 2.2, 0)
			return look(eye, p + Vector3.new(0, 1.3, 0)), p
		end,
	},
	{
		id = "walkLow",
		duration = 12,
		fov = 55,
		walk = true,
		smooth = 5,
		frame = function(_t, ctx)
			local p = ctx.root.Position
			local eye = p - ctx.heading * 6.5 + Vector3.new(0, 1, 0)
			return look(eye, p + ctx.heading * 12 + Vector3.new(0, 2.5, 0)), p
		end,
	},
	{
		id = "drone",
		duration = 14,
		fov = 55,
		smooth = 8,
		frame = function(t, ctx)
			local p = ctx.root.Position
			local a = smoothstep(t / 14)
			local height = 5 + 50 * a
			local back = 3 + 7 * a
			local angle = ctx.angle0 + math.pi + t * 0.08
			local eye = p + Vector3.new(math.cos(angle) * back, height, math.sin(angle) * back)
			return look(eye, p), p
		end,
	},
	{
		id = "macro",
		duration = 10,
		fov = 40,
		hideCharacter = true,
		macro = true,
		frame = function(t, ctx)
			local target = ctx.target or ctx.start
			local a = smoothstep(t / 10)
			local angle = ctx.angle0 - 0.9 + 1.8 * a
			local radius = 3.4 - 0.9 * a
			local eye = around(target, angle, radius, 0.7 + 0.3 * a)
			return look(eye, target), target
		end,
	},
	-- ===== Przeloty nad miejscami (teleport przed startem, postać schowana) =====
	{
		id = "forest",
		duration = 24,
		fov = 60,
		tp = "tpCabin",
		hideCharacter = true,
		light = true,
		frame = function(t, _ctx)
			local z = 45 + 235 * smoothstep(t / 24)
			local x = math.sin(t * 0.35) * 7
			local eye = Vector3.new(x, 5.5 + math.sin(t * 0.5) * 0.8, z)
			local at = Vector3.new(x * 0.5, 3, z + 30)
			return look(eye, at), at
		end,
	},
	{
		id = "grove",
		duration = 12,
		fov = 55,
		tp = "tpGrove",
		hideCharacter = true,
		light = true,
		frame = pushIn(Vector3.new(0, 9, 385), Vector3.new(0, 5, 410), Vector3.new(0, 2, 425), 12),
	},
	{
		id = "cabin",
		duration = 16,
		fov = 50,
		tp = "tpCabin",
		hideCharacter = true,
		frame = function(t, _ctx)
			local center = Vector3.new(0, 0, -20)
			local a = smoothstep(t / 16)
			local angle = -0.6 + 1.2 * a
			local eye = center + Vector3.new(math.sin(angle) * 70, 26 - 6 * a, math.cos(angle) * 70)
			local at = center + Vector3.new(0, 3, 0)
			return look(eye, at), at
		end,
	},
	{
		id = "portal",
		duration = 10,
		fov = 55,
		tp = "tpPortal",
		hideCharacter = true,
		light = true,
		frame = pushIn(Vector3.new(8, 4, 442), Vector3.new(0, 3.5, 464), Vector3.new(0, 4, 476), 10),
	},
	{
		id = "lair",
		duration = 12,
		fov = 55,
		tp = "tpLair",
		hideCharacter = true,
		light = true,
		frame = pushIn(Vector3.new(10, 6, 1508), Vector3.new(0, 4, 1531), Vector3.new(0, 3, 1548), 12),
	},
	{
		id = "pond",
		duration = 12,
		fov = 55,
		tp = "tpPond",
		hideCharacter = true,
		light = true,
		frame = pushIn(Vector3.new(-12, 10, 2360), Vector3.new(0, 6, 2384), Vector3.new(0, 2, 2404), 12),
	},
}

local shotById: { [string]: Shot } = {}
for _, shot in SHOTS do
	shotById[shot.id] = shot
end

-- ===== Stan =====

local allowed = false
local clean = false -- czysty ekran (gra bez interfejsu)
local guideOn = false
local hideLabels = true
local LOOKS: { string } = { "film", "bright", "natural" }
local LOOK_NAMES: { [string]: string } = { film = "filmowy", bright = "jaśniej", natural = "naturalny" }
local lookIndex = 1

local running: Shot? = nil
local runToken = 0 -- każde nowe ujęcie / zatrzymanie unieważnia poprzednie
local lastShot: string? = nil

local hidden = false
local hiddenGuis: { ScreenGui } = {}
local hiddenBillboards: { [BillboardGui]: boolean } = {}
local billboardWatch: RBXScriptConnection? = nil
local savedPrompts: boolean? = nil
local effects: { Instance } = {}
local dof: DepthOfFieldEffect? = nil
local lightPart: Part? = nil

-- ===== Nasz interfejs: odliczanie, podpowiedzi, ramka 9:16 =====

local gui = Instance.new("ScreenGui")
gui.Name = "CinemaMode"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1000
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local countdownLabel = Instance.new("TextLabel")
countdownLabel.Name = "Countdown"
countdownLabel.AnchorPoint = Vector2.new(0.5, 0.5)
countdownLabel.Position = UDim2.fromScale(0.5, 0.5)
countdownLabel.Size = UDim2.fromOffset(240, 240)
countdownLabel.BackgroundTransparency = 1
countdownLabel.Font = Enum.Font.FredokaOne
countdownLabel.TextSize = 160
countdownLabel.TextColor3 = Color3.fromRGB(255, 244, 222)
countdownLabel.TextStrokeTransparency = 0.4
countdownLabel.Text = ""
countdownLabel.Visible = false
countdownLabel.Parent = gui

local toast = Instance.new("TextLabel")
toast.Name = "Toast"
toast.AnchorPoint = Vector2.new(0.5, 1)
toast.Position = UDim2.new(0.5, 0, 1, -40)
toast.Size = UDim2.fromOffset(620, 40)
toast.BackgroundColor3 = Color3.fromRGB(23, 16, 11)
toast.BackgroundTransparency = 0.2
toast.Font = Enum.Font.GothamBold
toast.TextSize = 18
toast.TextColor3 = Color3.fromRGB(255, 244, 222)
toast.Text = ""
toast.Visible = false
toast.Parent = gui
local toastCorner = Instance.new("UICorner")
toastCorner.CornerRadius = UDim.new(0, 10)
toastCorner.Parent = toast

local guide = Instance.new("Frame")
guide.Name = "Guide916"
guide.BackgroundTransparency = 1
guide.Size = UDim2.fromScale(1, 1)
guide.Visible = false
guide.Parent = gui
local leftBar = Instance.new("Frame")
leftBar.Name = "Left"
leftBar.BorderSizePixel = 0
leftBar.BackgroundColor3 = Color3.new(0, 0, 0)
leftBar.BackgroundTransparency = 0.45
leftBar.Parent = guide
local rightBar = leftBar:Clone()
rightBar.Name = "Right"
rightBar.Parent = guide
local safeFrame = Instance.new("Frame")
safeFrame.Name = "Safe"
safeFrame.BackgroundTransparency = 1
safeFrame.Parent = guide
local safeStroke = Instance.new("UIStroke")
safeStroke.Color = Color3.fromRGB(255, 208, 72)
safeStroke.Thickness = 2
safeStroke.Parent = safeFrame

local toastToken = 0
local function say(message: string, seconds: number?)
	toastToken += 1
	local token = toastToken
	gui.Enabled = true
	toast.Text = message
	toast.Visible = true
	task.delay(seconds or 2, function()
		if toastToken == token then
			toast.Visible = false
		end
	end)
end

local function layoutGuide()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local size = camera.ViewportSize
	local width = math.floor(size.Y * 9 / 16)
	local side = math.max(0, math.floor((size.X - width) / 2))
	leftBar.Size = UDim2.fromOffset(side, size.Y)
	leftBar.Position = UDim2.fromOffset(0, 0)
	rightBar.Size = UDim2.fromOffset(side, size.Y)
	rightBar.Position = UDim2.fromOffset(size.X - side, 0)
	safeFrame.Size = UDim2.fromOffset(math.min(width, size.X), size.Y)
	safeFrame.Position = UDim2.fromOffset(side, 0)
	leftBar.Visible = side > 0
	rightBar.Visible = side > 0
end

local function setGuide(on: boolean)
	guideOn = on
	layoutGuide()
	guide.Visible = on
	if on then
		gui.Enabled = true
	end
end

-- ===== Chowanie interfejsu =====

local function controls(): any
	local scripts = player:FindFirstChild("PlayerScripts")
	local module = scripts and scripts:FindFirstChild("PlayerModule")
	if not module then
		return nil
	end
	local ok, result = pcall(function()
		return (require(module :: ModuleScript) :: any):GetControls()
	end)
	return if ok then result else nil
end

local function hideBillboard(b: BillboardGui)
	if b.Enabled then
		b.Enabled = false
		hiddenBillboards[b] = true
	end
end

local function setLabelsHidden(on: boolean)
	if on then
		for _, d in Workspace:GetDescendants() do
			if d:IsA("BillboardGui") then
				hideBillboard(d)
			end
		end
		local playerGui = player:FindFirstChild("PlayerGui")
		if playerGui then
			for _, d in playerGui:GetDescendants() do
				if d:IsA("BillboardGui") then
					hideBillboard(d)
				end
			end
		end
		if not billboardWatch then
			billboardWatch = Workspace.DescendantAdded:Connect(function(d)
				if d:IsA("BillboardGui") then
					task.defer(function()
						if hidden and hideLabels and d.Parent then
							hideBillboard(d)
						end
					end)
				end
			end)
		end
	else
		if billboardWatch then
			billboardWatch:Disconnect()
			billboardWatch = nil
		end
		for b in hiddenBillboards do
			if b.Parent then
				b.Enabled = true
			end
		end
		table.clear(hiddenBillboards)
	end
end

local function clearEffects()
	for _, e in effects do
		e:Destroy()
	end
	table.clear(effects)
	dof = nil
end

-- Efekty obrazu przy kamerze: znikają razem z trybem i nie ruszają ustawień światła gry (Atmosphere)
local function applyLook()
	clearEffects()
	local camera = Workspace.CurrentCamera
	local mode = LOOKS[lookIndex]
	if not camera or mode == "natural" then
		return
	end
	local depth = Instance.new("DepthOfFieldEffect")
	depth.Name = "CinemaDepth"
	depth.FarIntensity = 0.35
	depth.NearIntensity = 0.15
	depth.FocusDistance = 12
	depth.InFocusRadius = 8
	depth.Parent = camera
	dof = depth
	table.insert(effects, depth)
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "CinemaBloom"
	bloom.Intensity = 0.5
	bloom.Size = 24
	bloom.Threshold = 1.4
	bloom.Parent = camera
	table.insert(effects, bloom)
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "CinemaGrade"
	grade.Contrast = 0.08
	grade.Saturation = 0.12
	grade.Brightness = if mode == "bright" then 0.12 else 0.02
	grade.Parent = camera
	table.insert(effects, grade)
end

local function setHidden(on: boolean)
	if on == hidden then
		return
	end
	hidden = on
	if on then
		for _, g in player.PlayerGui:GetChildren() do
			if g:IsA("ScreenGui") and g ~= gui and g.Enabled then
				g.Enabled = false
				table.insert(hiddenGuis, g)
			end
		end
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
		end)
		pcall(function()
			StarterGui:SetCore("TopbarEnabled", false)
		end)
		UserInputService.MouseIconEnabled = false
		if hideLabels then
			setLabelsHidden(true)
		end
		applyLook()
	else
		for _, g in hiddenGuis do
			if g.Parent then
				g.Enabled = true
			end
		end
		table.clear(hiddenGuis)
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
		end)
		pcall(function()
			StarterGui:SetCore("TopbarEnabled", true)
		end)
		UserInputService.MouseIconEnabled = true
		setLabelsHidden(false)
		clearEffects()
	end
end

-- Inne moduły potrafią w trakcie włączyć swój interfejs (np. panel DEV przy każdej aktualizacji stanu)
local function keepHidden()
	for _, g in player.PlayerGui:GetChildren() do
		if g:IsA("ScreenGui") and g ~= gui and g.Enabled then
			g.Enabled = false
			if not table.find(hiddenGuis, g) then
				table.insert(hiddenGuis, g)
			end
		end
	end
	if hideLabels then
		for b in hiddenBillboards do
			if b.Enabled then
				b.Enabled = false
			end
		end
	end
end

local function setCharacterHidden(on: boolean)
	local character = player.Character
	if not character then
		return
	end
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			(d :: any).LocalTransparencyModifier = if on then 1 else 0
		end
	end
end

local function setLight(on: boolean)
	if on and not lightPart then
		local part = Instance.new("Part")
		part.Name = "CinemaLight"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 1
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		local light = Instance.new("PointLight")
		light.Range = 32
		light.Brightness = 1.4
		light.Color = LIGHT_COLOR
		light.Shadows = false
		light.Parent = part
		part.Parent = Workspace
		lightPart = part
	elseif not on and lightPart then
		lightPart:Destroy()
		lightPart = nil
	end
end

local function refreshHidden()
	setHidden(clean or running ~= nil or countdownLabel.Visible)
	gui.Enabled = guideOn or toast.Visible or countdownLabel.Visible or hidden
end

-- ===== Ujęcia =====

local function humanoid(): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function rootPart(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function nearestMushroom(from: Vector3): Vector3?
	local folder = Workspace:FindFirstChild("MyMushrooms")
	if not folder then
		return nil
	end
	local best: Vector3? = nil
	local bestDistance = 35
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			local pivot = child:GetPivot().Position
			local distance = (pivot - from).Magnitude
			if distance < bestDistance then
				local ok, extents = pcall(function()
					return child:GetExtentsSize()
				end)
				local height = if ok then (extents :: Vector3).Y else 1
				best = pivot + Vector3.new(0, height * 0.45, 0)
				bestDistance = distance
			end
		end
	end
	return best
end

local function endShot(token: number)
	if token ~= runToken then
		return
	end
	local shot = running
	running = nil
	RunService:UnbindFromRenderStep("CinemaShot")
	local h = humanoid()
	local root = rootPart()
	if shot and shot.walk and h and root then
		h:MoveTo(root.Position)
	end
	local c = controls()
	if c then
		pcall(function()
			c:Enable()
		end)
	end
	setCharacterHidden(false)
	setLight(false)
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = 70
		if h then
			camera.CameraSubject = h
		end
	end
	if savedPrompts ~= nil then
		local value = savedPrompts
		savedPrompts = nil
		pcall(function()
			ProximityPromptService.Enabled = value
		end)
	end
	countdownLabel.Visible = false
	refreshHidden()
	if clean then
		applyLook() -- czysty ekran zostaje, efekty wracają do wybranego wyglądu
	end
end

-- Zatrzymuje trwające ujęcie albo odliczanie (nowy token unieważnia oba)
local function stopShot()
	if running then
		endShot(runToken)
	end
	runToken += 1
	countdownLabel.Visible = false
	refreshHidden()
end

local function countdown(token: number): boolean
	gui.Enabled = true
	countdownLabel.Visible = true
	refreshHidden() -- interfejs znika już na odliczanie, żeby początek nagrania był czysty
	for n = COUNTDOWN, 1, -1 do
		if token ~= runToken then
			return false
		end
		countdownLabel.Text = tostring(n)
		countdownLabel.TextTransparency = 0
		TweenService:Create(countdownLabel, TweenInfo.new(0.9), { TextTransparency = 0.6 }):Play()
		task.wait(1)
	end
	countdownLabel.Visible = false
	return token == runToken
end

local function playShot(id: string)
	local shot = shotById[id]
	if not shot or not allowed then
		return
	end
	if CutsceneKit.isPlaying() then
		say("Trwa cutscenka – poczekaj, aż się skończy")
		return
	end
	stopShot()
	runToken += 1
	local token = runToken
	lastShot = id
	if shot.tp then
		DevAction:FireServer(shot.tp)
	end
	local ok = countdown(token)
	if not ok then
		return
	end
	local root = rootPart()
	local camera = Workspace.CurrentCamera
	if not root or not camera then
		refreshHidden()
		say("Brak postaci – spróbuj jeszcze raz")
		return
	end
	local facing = root.CFrame.LookVector
	local heading = Vector3.new(facing.X, 0, facing.Z)
	heading = if heading.Magnitude > 0.01 then heading.Unit else Vector3.new(0, 0, 1)
	local ctx: Ctx = {
		root = root,
		heading = heading,
		start = root.Position,
		target = nil,
		angle0 = math.atan2(heading.Z, heading.X),
	}
	if shot.macro then
		local target = nearestMushroom(root.Position)
		if not target then
			refreshHidden()
			say("Brak grzyba w pobliżu (35 studs) – podejdź bliżej")
			return
		end
		ctx.target = target
		local away = root.Position - target
		ctx.angle0 = math.atan2(away.Z, away.X)
	end

	running = shot
	refreshHidden()
	pcall(function()
		savedPrompts = ProximityPromptService.Enabled
		ProximityPromptService.Enabled = false
	end)
	local c = controls()
	if c then
		pcall(function()
			c:Disable()
		end)
	end
	setCharacterHidden(shot.hideCharacter == true)
	setLight(shot.light == true)
	if dof and shot.macro then
		dof.FarIntensity = 0.75
		dof.NearIntensity = 0.4
		dof.InFocusRadius = 1.5
	end

	local h = humanoid()
	local walkTarget: Vector3? = nil
	local lastMoveTo = -math.huge
	local started = os.clock()
	local current: CFrame? = nil
	camera.CameraType = Enum.CameraType.Scriptable

	RunService:BindToRenderStep("CinemaShot", Enum.RenderPriority.Camera.Value + 10, function(dt: number)
		if token ~= runToken then
			return
		end
		local t = os.clock() - started
		local liveRoot = rootPart()
		if not liveRoot then
			endShot(token)
			return
		end
		ctx.root = liveRoot
		if shot.walk and h and t < shot.duration and os.clock() - lastMoveTo > 6 then
			-- MoveTo kończy się sam po ok. 8 s, więc co 6 s ponawiamy cel daleko przed postacią
			lastMoveTo = os.clock()
			walkTarget = liveRoot.Position + heading * 200
			h:MoveTo(walkTarget :: Vector3)
		end
		local target, focus = shot.frame(math.min(t, shot.duration), ctx)
		local smoothing = shot.smooth
		local cf: CFrame
		if current and smoothing then
			cf = (current :: CFrame):Lerp(target, 1 - math.exp(-dt * smoothing))
		else
			cf = target
		end
		current = cf
		local cam = Workspace.CurrentCamera
		if cam then
			cam.CameraType = Enum.CameraType.Scriptable
			cam.CFrame = cf
			cam.FieldOfView = shot.fov
		end
		if dof then
			dof.FocusDistance = math.max(0.5, (focus - cf.Position).Magnitude)
		end
		if lightPart then
			lightPart.CFrame = CFrame.new(cf.Position + cf.LookVector * 2)
		end
		if shot.hideCharacter then
			setCharacterHidden(true) -- nowe części (narzędzia, latarnia) też znikają
		end
		keepHidden()
		if t >= shot.duration + HOLD_END then
			endShot(token)
		end
	end)
end

-- ===== Czysty ekran =====

local function setClean(on: boolean)
	if not allowed and on then
		return
	end
	clean = on
	refreshHidden()
	if on then
		RunService:BindToRenderStep("CinemaClean", Enum.RenderPriority.Last.Value, function()
			if not running then
				keepHidden()
				if dof then
					local root = rootPart()
					local cam = Workspace.CurrentCamera
					if root and cam then
						dof.FocusDistance = math.max(1, (root.Position - cam.CFrame.Position).Magnitude)
					end
				end
			end
		end)
		say("Czysty ekran · L wyłącza · K wychodzi · J ramka 9:16", 2)
	else
		RunService:UnbindFromRenderStep("CinemaClean")
		if not running then
			say("Interfejs wrócił", 1.2)
		end
	end
end

-- ===== Wejście z panelu DEV i klawiszy =====

function CinemaMode.action(id: string)
	if not allowed then
		return
	end
	if string.sub(id, 1, 10) == "cine:shot:" then
		playShot(string.sub(id, 11))
	elseif id == "cine:clean" then
		setClean(not clean)
	elseif id == "cine:guide" then
		setGuide(not guideOn)
	elseif id == "cine:look" then
		lookIndex = lookIndex % #LOOKS + 1
		if hidden then
			applyLook()
		end
		say("Wygląd: " .. LOOK_NAMES[LOOKS[lookIndex]], 1.5)
	elseif id == "cine:labels" then
		hideLabels = not hideLabels
		if hidden then
			setLabelsHidden(hideLabels)
		end
		say(if hideLabels then "Napisy nad głowami: ukryte" else "Napisy nad głowami: widoczne", 1.5)
	elseif id == "cine:stop" then
		stopShot()
		setClean(false)
	elseif id == "cine:replay" then
		if lastShot then
			playShot(lastShot)
		end
	end
end

function CinemaMode.setAllowed(on: boolean)
	allowed = on
	if not on then
		stopShot()
		if clean then
			setClean(false)
		end
		setGuide(false)
	end
end

function CinemaMode.isActive(): boolean
	return clean or running ~= nil
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not allowed or input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end
	local key = input.KeyCode
	if key == Enum.KeyCode.L then
		setClean(not clean)
	elseif key == Enum.KeyCode.K then
		if running or countdownLabel.Visible then
			stopShot()
		elseif clean then
			setClean(false)
		end
	elseif key == Enum.KeyCode.J then
		setGuide(not guideOn)
	elseif key == Enum.KeyCode.U then
		if lastShot then
			playShot(lastShot)
		end
	end
end)

task.defer(function()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(layoutGuide)
	end
	layoutGuide()
end)

return CinemaMode
