--!strict
-- Cutscenka na start gry (tylko przy pierwszym wejściu): zły sen.
--   1. Noc, las. Gracz idzie ścieżką z latarnią i zbiera grzyba.
--   2. W oddali lśni tęczowy, mityczny grzyb. Gracz go zrywa, ziemia drży.
--   3. Z ziemi wstaje Leszy, zapalają mu się oczy. Pościg ścieżką w stronę chatki.
--   4. Leszy łapie gracza: uderzenie, czerń, bicie serca.
--   5. Poranek. Gracz budzi się na bujanym fotelu na ganku: „Uff… to był tylko zły sen.”
--   6. Kamera pokazuje grzyba przy ścieżce: „Ooo… ale fajny grzyb!” i zaczyna się samouczek.
-- Wszystko dzieje się tylko u tego gracza: klon jego awatara, kamera, światło, napisy i dźwięk.
-- Przycisk „Pomiń” kończy scenę w każdej chwili (sprzątanie jest takie samo jak na końcu).

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local LeszyRig = require(ReplicatedStorage.Shared.LeszyRig)
local Atmosphere = require(script.Parent.Atmosphere)
local Audio = require(script.Parent.Audio)
local Localize = require(script.Parent.Localize)
local MushroomView = require(script.Parent.MushroomView)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer

local IntroCutscene = {}

local TITLE_FONT = Enum.Font.FredokaOne
local OUTLINE = UiKit.OUTLINE

local function pathX(z: number): number
	return 3 * math.sin(z / 16) -- ta sama krzywa co ścieżka z MapBuilder (Props.pathX)
end
local function onPath(z: number, dx: number?): Vector3
	return Vector3.new(pathX(z) + (dx or 0), 0, z)
end

-- ===== Stan sceny =====

type Scene = {
	cancelled: boolean,
	finished: boolean,
	clone: Model?,
	root: BasePart?,
	animator: Animator?,
	tracks: { [string]: AnimationTrack },
	leszy: Model?,
	leszyRig: LeszyRig.Rig?,
	leszyAnim: string, -- rise / stand / roar / run / lunge
	leszyAnimAt: number,
	leszyPhase: number,
	leszyLastSin: number,
	r15: boolean,
	motors: { [string]: any }, -- Motor6D albo AnimationConstraint (nowsze awatary), oba mają Transform
	posing: boolean, -- własna poza zbierania nadpisuje animacje
	effort: number, -- drżenie przy wyrywaniu mitycznego grzyba
	held: Model?,
	heldCap: BasePart?,
	heldRainbow: boolean,
	lanternLight: PointLight?,
	lanternGlass: BasePart?,
	oilGauge: Frame?,
	oilFill: Frame?,
	subtitle: TextLabel?,
	gui: ScreenGui,
	fade: Frame,
	bars: { Frame },
	skip: TextButton,
	caption: TextLabel,
	connections: { RBXScriptConnection },
	loops: { Sound },
	hiddenGuis: { ScreenGui },
	bubbles: { Instance },
	lighting: { [string]: any },
	shake: number,
	cameraCf: CFrame,
	fov: number,
	onDone: (() -> ())?,
}

local scene: Scene? = nil

local function cancelled(): boolean
	return scene == nil or (scene :: Scene).cancelled
end

-- Do testów w Studio: atrybut gracza CutsceneFreeze = "leszy" zatrzymuje scenę w tej fazie
-- (po CutsceneFreezeAfter sekundach od jej początku)
local phaseStart = 0
local function frozen(): boolean
	local s = scene
	local phase = player:GetAttribute("CutsceneFreeze")
	local after = player:GetAttribute("CutsceneFreezeAfter")
	return s ~= nil and phase ~= nil and s.gui:GetAttribute("Phase") == phase
		and os.clock() - phaseStart >= (if typeof(after) == "number" then after else 1)
end

-- Czekanie, które kończy się od razu, gdy gracz pominie scenę
local function wait(seconds: number): boolean
	local untilTime = os.clock() + seconds
	while os.clock() < untilTime or frozen() do
		if cancelled() then
			return false
		end
		RunService.RenderStepped:Wait()
	end
	return not cancelled()
end

local function tween(object: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local t = TweenService:Create(object, TweenInfo.new(time, style or Enum.EasingStyle.Sine, direction or Enum.EasingDirection.InOut), props)
	t:Play()
	return t
end

-- ===== Kamera =====
-- Kamera jedzie od ujęcia do ujęcia; w każdej klatce dokładamy trzęsienie (scene.shake)

local cameraValue = Instance.new("CFrameValue")
local fovValue = Instance.new("NumberValue")

local function shot(from: CFrame, to: CFrame?, time: number, fov: number?, style: Enum.EasingStyle?)
	cameraValue.Value = from
	if fov then
		fovValue.Value = fov
	end
	if to then
		tween(cameraValue, time, { Value = to }, style or Enum.EasingStyle.Sine)
	end
end

local function look(eye: Vector3, at: Vector3): CFrame
	return CFrame.lookAt(eye, at)
end

-- ===== Klon gracza =====

local function animationId(character: Model, path: { string }): string?
	local node: Instance? = character:FindFirstChild("Animate")
	for _, name in path do
		node = node and node:FindFirstChild(name)
	end
	if node and node:IsA("Animation") then
		return node.AnimationId
	end
	return nil
end

local function makeClone(s: Scene)
	local character = player.Character
	if not character then
		return
	end
	character.Archivable = true
	local clone = character:Clone()
	character.Archivable = false
	if not clone then
		return
	end
	clone.Name = "DreamPlayer"
	for _, d in clone:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
		end
	end
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	local root = clone:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		clone:Destroy()
		return
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	root.Anchored = true
	clone.Parent = Workspace
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	s.clone = clone
	s.root = root
	s.animator = animator
	s.r15 = humanoid.RigType == Enum.HumanoidRigType.R15
	for _, d in clone:GetDescendants() do
		if d:IsA("Motor6D") or d:IsA("AnimationConstraint") then
			s.motors[d.Name] = d
		end
	end
	-- Latarnia klona: w śnie miga i gaśnie, kiedy kończy się olej
	local attachment = root:FindFirstChild("LanternAttachment")
	local light = attachment and attachment:FindFirstChild("Lantern")
	s.lanternLight = if light and light:IsA("PointLight") then light else nil
	local hand = clone:FindFirstChild("HandLantern")
	local glass = hand and hand:FindFirstChild("LanternGlass", true)
	s.lanternGlass = if glass and glass:IsA("BasePart") then glass else nil
	local ids = {
		walk = animationId(character, { "walk", "WalkAnim" }),
		run = animationId(character, { "run", "RunAnim" }),
		idle = animationId(character, { "idle", "Animation1" }),
		sit = animationId(character, { "sit", "SitAnim" }),
	}
	for name, id in ids do
		if id then
			local anim = Instance.new("Animation")
			anim.AnimationId = id
			local ok, track = pcall(function()
				return animator:LoadAnimation(anim)
			end)
			if ok and track then
				track.Looped = name ~= "sit" or true
				s.tracks[name] = track
			end
		end
	end
end

local function play(s: Scene, name: string, speed: number?)
	for other, track in s.tracks do
		if other ~= name and track.IsPlaying then
			track:Stop(0.2)
		end
	end
	local track = s.tracks[name]
	if track then
		if not track.IsPlaying then
			track:Play(0.2)
		end
		track:AdjustSpeed(speed or 1)
	end
end

-- Wysokość biodra nad ziemią (żeby klon stał na ścieżce, a nie w niej)
local function hipHeight(s: Scene): number
	local clone = s.clone
	local humanoid = clone and clone:FindFirstChildOfClass("Humanoid")
	local root = s.root
	if humanoid and root then
		if humanoid.RigType == Enum.HumanoidRigType.R15 then
			return humanoid.HipHeight + root.Size.Y / 2
		end
		return 3
	end
	return 3
end

local rootValue = Instance.new("CFrameValue")

local function placeAt(s: Scene, at: Vector3, facing: Vector3)
	local h = hipHeight(s)
	rootValue.Value = CFrame.lookAt(at + Vector3.new(0, h, 0), at + Vector3.new(facing.X, h, facing.Z))
end

local function moveTo(s: Scene, at: Vector3, time: number, anim: string, speed: number?)
	local h = hipHeight(s)
	local from = rootValue.Value.Position
	local target = at + Vector3.new(0, h, 0)
	local dir = Vector3.new(target.X - from.X, 0, target.Z - from.Z)
	play(s, anim, speed)
	if dir.Magnitude > 0.05 then
		tween(rootValue, time, { Value = CFrame.lookAt(target, target + dir) }, Enum.EasingStyle.Linear)
	end
end

-- Schylenie po grzyba: biodro w dół i pochylenie do przodu, potem z powrotem
local function crouch(s: Scene, down: boolean)
	local base = rootValue.Value
	local h = hipHeight(s)
	if down then
		play(s, "idle")
		tween(rootValue, 0.35, { Value = base * CFrame.new(0, -h * 0.35, 0) * CFrame.Angles(math.rad(-28), 0, 0) }, Enum.EasingStyle.Quad)
	else
		local p = base.Position
		local look = base.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		local standing = Vector3.new(p.X, 0, p.Z) + Vector3.new(0, h, 0)
		-- Pozycję liczymy od ziemi, a kierunek z płaskiego wektora przodu
		local ground = Vector3.new(p.X, Workspace.CurrentCamera and 0 or 0, p.Z)
		tween(rootValue, 0.3, { Value = CFrame.lookAt(ground + Vector3.new(0, h, 0), ground + Vector3.new(0, h, 0) + (if flat.Magnitude > 0 then flat.Unit else Vector3.new(0, 0, -1))) }, Enum.EasingStyle.Quad)
		local _ = standing
	end
end

-- ===== Zbieranie: własna poza (R15) i grzyb w dłoni =====
-- Kucnięcie, ręka do grzyba, potem grzyb przed twarzą (ogląda) albo wysoko nad głową (mityczny).
-- Motor6D.Transform ustawiamy po kroku animacji (Stepped), a na czas pozy animacje są zatrzymane.

local pickValue = Instance.new("NumberValue") -- 1 = przykucnięty, ręka przy ziemi
local liftValue = Instance.new("NumberValue") -- 1 = grzyb przed twarzą
local highValue = Instance.new("NumberValue") -- 1 = grzyb wysoko nad głową

local function rxd(d: number): CFrame
	return CFrame.Angles(math.rad(d), 0, 0)
end
local function rzd(d: number): CFrame
	return CFrame.Angles(0, 0, math.rad(d))
end

local function poseClone(s: Scene)
	if not s.posing then
		return
	end
	local k, l, h = pickValue.Value, liftValue.Value, highValue.Value
	local tremble = s.effort * math.noise(os.clock() * 28, 4.2) * 7
	local function set(name: string, cf: CFrame)
		local motor = s.motors[name]
		if motor then
			motor.Transform = cf
		end
	end
	set("Root", CFrame.new(0, -1.0 * k, 0) * rxd(-6 * k))
	set("Waist", rxd(-30 * k + 8 * h + tremble))
	set("Neck", rxd(-24 * k + 16 * l + 26 * h))
	set("RightHip", rxd(80 * k))
	set("LeftHip", rxd(66 * k))
	set("RightKnee", rxd(-112 * k))
	set("LeftKnee", rxd(-98 * k))
	set("RightAnkle", rxd(32 * k))
	set("LeftAnkle", rxd(32 * k))
	set("RightShoulder", rxd(64 * k * (1 - l) + 92 * l * (1 - h) + 172 * h + tremble) * rzd(-6 * l))
	set("RightElbow", rxd(18 * k + 58 * l * (1 - h) + 6 * h))
	set("RightWrist", rxd(-10 * l))
	set("LeftShoulder", rxd(20 * k + 12 * l) * rzd(-16 * k - 28 * h))
	set("LeftElbow", rxd(26 * k + 20 * l))
end

local function beginPose(s: Scene)
	s.posing = true
	for _, track in s.tracks do
		if track.IsPlaying then
			track:Stop(0.15)
		end
	end
end

local function endPose(s: Scene)
	s.posing = false
	for _, motor in s.motors do
		motor.Transform = CFrame.new()
	end
	pickValue.Value, liftValue.Value, highValue.Value = 0, 0, 0
	s.effort = 0
end

local function dropMushroom(s: Scene)
	if s.held then
		s.held:Destroy()
	end
	s.held = nil
	s.heldCap = nil
	s.heldRainbow = false
end

-- Grzyb w prawej dłoni (stopka w pięści, kapelusz za palcami)
local function holdMushroom(s: Scene, mythic: boolean)
	dropMushroom(s)
	local clone = s.clone
	local hand = clone and (clone:FindFirstChild("RightHand") or clone:FindFirstChild("Right Arm"))
	if not clone or not hand or not hand:IsA("BasePart") then
		return
	end
	local scale = if mythic then 1.15 else 1
	local model = Instance.new("Model")
	model.Name = "HeldMushroom"
	local function piece(size: Vector3, offset: number, color: Color3, neon: boolean): Part
		local p = Instance.new("Part")
		p.Size = size * scale
		p.CFrame = hand.CFrame * CFrame.new(0, -hand.Size.Y / 2 - offset * scale, 0)
		p.Color = color
		p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.Anchored = false
		p.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hand
		weld.Part1 = p
		weld.Parent = p
		return p
	end
	piece(Vector3.new(0.3, 0.62, 0.3), 0.18, Color3.fromRGB(238, 228, 204), false)
	local cap = piece(Vector3.new(0.86, 0.36, 0.86), 0.62, if mythic then Color3.fromRGB(255, 120, 200) else Color3.fromRGB(150, 92, 52), mythic)
	piece(Vector3.new(0.62, 0.2, 0.62), 0.84, if mythic then Color3.new(1, 1, 1) else Color3.fromRGB(122, 74, 42), mythic)
	if mythic then
		local light = Instance.new("PointLight")
		light.Range = 12
		light.Brightness = 2.5
		light.Parent = cap
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkles.Rate = 26
		sparkles.Lifetime = NumberRange.new(0.5, 0.9)
		sparkles.Speed = NumberRange.new(1, 2.5)
		sparkles.SpreadAngle = Vector2.new(180, 180)
		sparkles.Size = NumberSequence.new(0.35, 0)
		sparkles.LightEmission = 1
		sparkles.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 90)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 230, 90)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(90, 220, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 120, 255)),
		})
		sparkles.Parent = cap
	end
	model.Parent = clone
	s.held = model
	s.heldCap = cap
	s.heldRainbow = mythic
end

-- Iskierki w miejscu zerwanego grzyba
local function burstAt(at: Vector3, color: Color3, count: number)
	local holder = Instance.new("Attachment")
	holder.WorldPosition = at
	holder.Parent = Workspace.Terrain
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Speed = NumberRange.new(3, 6)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -6, 0)
	emitter.Size = NumberSequence.new(0.4, 0)
	emitter.LightEmission = 1
	emitter.Color = ColorSequence.new(color)
	emitter.Parent = holder
	emitter:Emit(count)
	task.delay(1.5, function()
		holder:Destroy()
	end)
end

-- Całe zerwanie: kucnięcie → grzyb znika z ziemi i jest w dłoni → wstaje z grzybem przed twarzą (albo nad głową)
local function pickUp(s: Scene, id: string, at: Vector3, mythic: boolean): boolean
	if not s.r15 then
		-- Starszy awatar (R6): bez własnej pozy, tylko schylenie całego ciała
		crouch(s, true)
		if not wait(0.5) then
			return false
		end
		MushroomView.remove(id)
		Audio.play("pick", { jitter = 0.08 })
		holdMushroom(s, mythic)
		crouch(s, false)
		return wait(0.5)
	end
	beginPose(s)
	tween(pickValue, 0.45, { Value = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if not wait(0.45) then
		return false
	end
	if mythic then
		-- Siedzi mocno: szarpie, aż puści
		s.effort = 1
		Audio.play("rumble", { volume = 0.4, duration = 0.9 })
		if not wait(0.8) then
			return false
		end
		s.effort = 0
	end
	MushroomView.remove(id)
	holdMushroom(s, mythic)
	Audio.play("pick", { jitter = 0.08 })
	burstAt(at + Vector3.new(0, 0.6, 0), if mythic then Color3.fromRGB(255, 200, 255) else Color3.fromRGB(255, 226, 150), if mythic then 40 else 14)
	tween(pickValue, 0.5, { Value = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	tween(liftValue, 0.5, { Value = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	if mythic then
		tween(highValue, 0.55, { Value = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end
	return wait(0.55)
end

-- Grzyb ląduje w plecaku: ręka za plecy, grzyb znika z „pyk”
local function stash(s: Scene): boolean
	tween(liftValue, 0.3, { Value = 0 }, Enum.EasingStyle.Quad)
	if not wait(0.28) then
		return false
	end
	dropMushroom(s)
	Audio.play("blip", { volume = 0.6, pitch = 1.3 })
	endPose(s)
	return true
end

-- ===== Leszy =====

local function makeLeszy(s: Scene, at: CFrame)
	local folder = ReplicatedStorage:FindFirstChild("CutsceneProps")
	local proto = folder and folder:FindFirstChild("Leszy")
	if not proto or not proto:IsA("Model") then
		return
	end
	local leszy = proto:Clone()
	-- Tego Leszego animuje scena (LeszyAnimator go pomija)
	leszy:SetAttribute("Scripted", true)
	leszy:PivotTo(at)
	leszy.Parent = Workspace
	s.leszy = leszy
	s.leszyRig = LeszyRig.new(leszy)
	s.leszyAnim = "rise"
	s.leszyAnimAt = os.clock()
end

local function leszyDo(s: Scene, kind: string)
	s.leszyAnim = kind
	s.leszyAnimAt = os.clock()
end

local function leszyEyes(s: Scene, awake: boolean)
	local leszy = s.leszy
	if not leszy then
		return
	end
	for _, part in leszy:GetChildren() do
		if part.Name == "Eye" and part:IsA("BasePart") then
			part.Color = if awake then Color3.fromRGB(255, 40, 30) else Color3.fromRGB(90, 20, 18)
		elseif part.Name == "Heart" and part:IsA("BasePart") then
			tween(part, 0.4, { Color = if awake then Color3.fromRGB(120, 255, 150) else Color3.fromRGB(40, 90, 56) })
			local glow = part:FindFirstChild("HeartLight")
			if glow and glow:IsA("PointLight") then
				tween(glow, 0.4, { Brightness = if awake then 2.4 else 0.3 })
			end
		end
	end
	local head = leszy:FindFirstChild("Head")
	local light = head and head:FindFirstChild("EyeLight")
	if light and light:IsA("PointLight") then
		tween(light, 0.4, { Brightness = if awake then 2.2 else 0, Range = 14 })
	end
end

local leszyValue = Instance.new("CFrameValue")

-- Poza Leszego w tej klatce (wołane z pętli kamery)
local function animateLeszy(s: Scene, dt: number)
	local rig = s.leszyRig
	if not s.leszy or not rig then
		return
	end
	local now = os.clock()
	local age = now - s.leszyAnimAt
	local kind = s.leszyAnim
	local speed = if kind == "run" or kind == "lunge" then 1 else 0
	s.leszyPhase += dt * (1.2 + speed * 7.4)
	local pose, hips = LeszyRig.gait(now, s.leszyPhase, speed)
	if kind == "rise" then
		-- Wyłazi z ziemi skulony i powoli się prostuje
		local k = 1 - math.clamp((age - 0.4) / 1.8, 0, 1)
		k = k * k * (3 - 2 * k)
		local p2, h2 = LeszyRig.crouch(1, now)
		pose, hips = LeszyRig.mix(pose, hips, p2, h2, k)
	elseif kind == "roar" then
		local p2, h2 = LeszyRig.roar(1, now)
		pose, hips = LeszyRig.mix(pose, hips, p2, h2, math.clamp(age / 0.3, 0, 1))
	elseif kind == "lunge" then
		local p2, h2 = LeszyRig.lunge(1)
		pose, hips = LeszyRig.mix(pose, hips, p2, h2, math.clamp(age / 0.35, 0, 1))
	end
	LeszyRig.apply(rig, leszyValue.Value, pose, hips)
	-- Ciężkie kroki w biegu: łupnięcie i drgnięcie kamery
	if speed > 0 then
		local sn = math.sin(s.leszyPhase)
		if (sn > 0) ~= (s.leszyLastSin > 0) then
			Audio.play("footstep", { volume = 1.3, pitch = 0.42, jitter = 0.06 })
			s.shake = math.max(s.shake, 0.22)
		end
		s.leszyLastSin = sn
	end
end

-- ===== Światło =====

local function setLighting(s: Scene, preset: string, time: number)
	local atmosphere = Lighting:FindFirstChild("ForestAtmosphere")
	local color = Lighting:FindFirstChild("ForestColor")
	local props: { [string]: any }
	local fog: { [string]: any }
	local tint: { [string]: any }
	if preset == "night" then
		-- Księżycowa noc: ciemno, ale postać, ścieżkę i drzewa dobrze widać
		props = { ClockTime = 0.2, Brightness = 1.6, Ambient = Color3.fromRGB(70, 76, 118), OutdoorAmbient = Color3.fromRGB(86, 94, 140) }
		fog = { Density = 0.32, Color = Color3.fromRGB(44, 52, 96), Haze = 1.1 }
		tint = { TintColor = Color3.fromRGB(200, 214, 255), Saturation = -0.15, Contrast = 0.12, Brightness = 0.02 }
	elseif preset == "danger" then
		props = { ClockTime = 0.2, Brightness = 1.2, Ambient = Color3.fromRGB(96, 34, 40), OutdoorAmbient = Color3.fromRGB(120, 40, 48) }
		fog = { Density = 0.4, Color = Color3.fromRGB(80, 18, 26), Haze = 1.5 }
		tint = { TintColor = Color3.fromRGB(255, 170, 170), Saturation = -0.1, Contrast = 0.25, Brightness = -0.03 }
	else -- poranek
		props = { ClockTime = 7.3, Brightness = 1.3, Ambient = Color3.fromRGB(96, 84, 76), OutdoorAmbient = Color3.fromRGB(128, 112, 96) }
		fog = { Density = 0.26, Color = Color3.fromRGB(255, 214, 170), Haze = 0.6 }
		tint = { TintColor = Color3.fromRGB(255, 240, 220), Saturation = 0.08, Contrast = 0.05, Brightness = 0.02 }
	end
	if time <= 0 then
		for k, v in props do
			(Lighting :: any)[k] = v
		end
		if atmosphere then
			for k, v in fog do
				(atmosphere :: any)[k] = v
			end
		end
		if color then
			for k, v in tint do
				(color :: any)[k] = v
			end
		end
	else
		tween(Lighting, time, props)
		if atmosphere then
			tween(atmosphere, time, fog)
		end
		if color then
			tween(color, time, tint)
		end
	end
	local _ = s
end

-- ===== Interfejs sceny: pasy kinowe, czerń, napis, chmurka, „Pomiń” =====

local function buildGui(): (ScreenGui, Frame, { Frame }, TextButton, TextLabel)
	local gui = Instance.new("ScreenGui")
	gui.Name = "Cutscene"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	local bars = {}
	for i, anchor in { 0, 1 } do
		local bar = Instance.new("Frame")
		bar.Name = "Bar" .. i
		bar.BackgroundColor3 = Color3.new(0, 0, 0)
		bar.BorderSizePixel = 0
		bar.AnchorPoint = Vector2.new(0, anchor)
		bar.Position = UDim2.fromScale(0, anchor)
		bar.Size = UDim2.new(1, 0, 0, 0)
		bar.ZIndex = 2
		bar.Parent = gui
		table.insert(bars, bar)
	end

	local fade = Instance.new("Frame")
	fade.Name = "Fade"
	fade.Size = UDim2.fromScale(1, 1)
	fade.BackgroundColor3 = Color3.new(0, 0, 0)
	fade.BackgroundTransparency = 0
	fade.BorderSizePixel = 0
	fade.ZIndex = 5
	fade.Parent = gui

	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.BackgroundTransparency = 1
	caption.AnchorPoint = Vector2.new(0.5, 0.5)
	caption.Position = UDim2.fromScale(0.5, 0.5)
	caption.Size = UDim2.fromScale(0.8, 0.12)
	caption.Font = TITLE_FONT
	caption.TextScaled = true
	caption.TextColor3 = Color3.fromRGB(255, 236, 200)
	caption.TextTransparency = 1
	caption.Text = ""
	caption.ZIndex = 6
	caption.Parent = gui
	local captionSize = Instance.new("UITextSizeConstraint")
	captionSize.MaxTextSize = 54
	captionSize.Parent = caption
	local captionStroke = UiKit.outline(caption, 3)
	captionStroke.Transparency = 1

	local skip = Instance.new("TextButton")
	skip.Name = "Skip"
	skip.AnchorPoint = Vector2.new(1, 1)
	skip.Position = UDim2.new(1, -24, 1, -24)
	skip.Size = UDim2.fromOffset(150, 48)
	skip.Font = TITLE_FONT
	skip.TextSize = 24
	skip.Text = ""
	skip.Visible = false
	skip.ZIndex = 8
	skip.Parent = gui
	local skipStroke = UiKit.button(skip, Color3.fromRGB(60, 46, 38), { stroke = 3, radius = UDim.new(1, 0), gloss = true })
	skipStroke.Color = OUTLINE
	return gui, fade, bars, skip, caption
end

local function setCaption(s: Scene, text: string, show: boolean, time: number?)
	s.caption.Text = text
	local t = time or 0.8
	tween(s.caption, t, { TextTransparency = if show then 0 else 1 })
	local stroke = s.caption:FindFirstChildOfClass("UIStroke")
	if stroke then
		tween(stroke, t, { Transparency = if show then 0 else 1 })
	end
end

-- Napis na dole ekranu (nad dolnym pasem) – krótkie zdania, które tłumaczą, co się dzieje
local function buildSubtitle(s: Scene)
	local label = Instance.new("TextLabel")
	label.Name = "Subtitle"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.835)
	label.Size = UDim2.fromScale(0.86, 0.065)
	label.Font = TITLE_FONT
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 236, 200)
	label.TextTransparency = 1
	label.Text = ""
	label.ZIndex = 6
	label.Parent = s.gui
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 34
	limit.Parent = label
	local stroke = UiKit.outline(label, 3)
	stroke.Transparency = 1
	s.subtitle = label
end

local function subtitle(s: Scene, text: string?, color: Color3?)
	local label = s.subtitle
	if not label then
		return
	end
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if text then
		label.Text = text
		label.TextColor3 = color or Color3.fromRGB(255, 236, 200)
		local scale = label:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		scale.Parent = label
		scale.Scale = 1.15
		tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		tween(label, 0.25, { TextTransparency = 0 })
		if stroke then
			tween(stroke, 0.25, { Transparency = 0 })
		end
	else
		tween(label, 0.4, { TextTransparency = 1 })
		if stroke then
			tween(stroke, 0.4, { Transparency = 1 })
		end
	end
end

-- Pasek oleju w śnie (u góry, pod pasem kinowym): spada, miga na czerwono, a przy zerze latarnia gaśnie
local oilValue = Instance.new("NumberValue")

local function buildOilGauge(s: Scene)
	local frame = Instance.new("Frame")
	frame.Name = "Oil"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0.125, 0)
	frame.Size = UDim2.fromOffset(300, 46)
	frame.BackgroundColor3 = Color3.fromRGB(44, 32, 26)
	frame.BackgroundTransparency = 0.1
	frame.Visible = false
	frame.ZIndex = 3
	frame.Parent = s.gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = OUTLINE
	stroke.Thickness = 3
	stroke.Parent = frame
	local icon = UiKit.icon("lantern", frame, UDim2.fromOffset(36, 36), UDim2.new(0, 8, 0.5, 0), Vector2.new(0, 0.5))
	icon.ZIndex = 4
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(50, 10)
	label.Size = UDim2.fromOffset(70, 26)
	label.Font = TITLE_FONT
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 220, 160)
	label.Text = Localize.t("HUD_OIL")
	label.ZIndex = 4
	label.Parent = frame
	local back = Instance.new("Frame")
	back.Position = UDim2.fromOffset(124, 13)
	back.Size = UDim2.fromOffset(162, 20)
	back.BackgroundColor3 = Color3.fromRGB(22, 14, 10)
	back.ZIndex = 4
	back.Parent = frame
	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(1, 0)
	backCorner.Parent = back
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0.5, 1)
	fill.BackgroundColor3 = Color3.fromRGB(255, 170, 56)
	fill.ZIndex = 5
	fill.Parent = back
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill
	s.oilGauge = frame
	s.oilFill = fill
end

-- Co klatkę: pasek i latarnia klona zależnie od oleju
local function updateOil(s: Scene)
	local oil = oilValue.Value
	local now = os.clock()
	local fill = s.oilFill
	if fill then
		fill.Size = UDim2.fromScale(math.clamp(oil, 0, 1), 1)
		local low = oil < 0.25
		local flash = if low then 0.5 + 0.5 * math.sin(now * 12) else 0
		fill.BackgroundColor3 = Color3.fromRGB(255, 170, 56):Lerp(Color3.fromRGB(255, 50, 40), if low then 0.6 + 0.4 * flash else 0)
		local gauge = s.oilGauge
		if gauge then
			gauge.Rotation = if low then math.sin(now * 40) * 1.5 * flash else 0
		end
	end
	local strength = 1
	if oil <= 0.001 then
		strength = 0
	elseif oil < 0.25 then
		strength = (0.35 + 0.65 * oil / 0.25) * (0.55 + 0.45 * math.noise(now * 7, 1.3) + 0.2)
	end
	local light = s.lanternLight
	if light then
		light.Brightness = 2.2 * math.clamp(strength, 0, 1.2)
	end
	local glass = s.lanternGlass
	if glass then
		glass.Color = Color3.fromRGB(40, 26, 18):Lerp(Color3.fromRGB(255, 206, 120), math.clamp(strength, 0, 1))
	end
end

local function letterbox(s: Scene, show: boolean, time: number)
	for _, bar in s.bars do
		tween(bar, time, { Size = UDim2.new(1, 0, if show then 0.11 else 0, 0) }, Enum.EasingStyle.Quad)
	end
end

local function fadeTo(s: Scene, black: boolean, time: number)
	tween(s.fade, time, { BackgroundTransparency = if black then 0 else 1 })
end

-- Chmurka z myślą nad głową klona, tekst pisany literka po literce
local function thought(s: Scene, text: string, hold: number, fixed: UDim2?): boolean
	local clone = s.clone
	local head = clone and clone:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return wait(hold)
	end
	-- Chmurka to zwykła ramka na ekranie, przypięta co klatkę do punktu nad głową
	-- (BillboardGui nie zawsze się rysuje, a tak wygląda tak samo na każdym ekranie)
	local holder = Instance.new("Frame")
	holder.Name = "Thought"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(300, 130)
	holder.AnchorPoint = Vector2.new(0, 1)
	holder.ZIndex = 4
	holder.Parent = s.gui
	local bill = holder
	local follow = RunService.RenderStepped:Connect(function()
		local cam = Workspace.CurrentCamera
		if fixed then
			holder.Position = fixed
		elseif cam and head.Parent then
			local point, visible = cam:WorldToViewportPoint(head.Position + Vector3.new(0, 1.4, 0))
			holder.Visible = visible
			holder.Position = UDim2.fromOffset(point.X + 10, point.Y)
		end
	end)
	table.insert(s.connections, follow)
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = holder
	-- Kółeczka prowadzące do chmurki
	for i, size in { 14, 22 } do
		local dot = Instance.new("Frame")
		dot.Size = UDim2.fromOffset(size, size)
		dot.Position = UDim2.new(0, 8 + i * 14, 1, -size - (i - 1) * 16)
		dot.BackgroundColor3 = Color3.new(1, 1, 1)
		dot.Parent = holder
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = dot
		local st = Instance.new("UIStroke")
		st.Color = OUTLINE
		st.Thickness = 3
		st.Parent = dot
	end
	-- Chmurka z „bąbli” na brzegach
	local cloud = Instance.new("Frame")
	cloud.Size = UDim2.new(1, -40, 1, -46)
	cloud.Position = UDim2.fromOffset(30, 0)
	cloud.BackgroundColor3 = Color3.new(1, 1, 1)
	cloud.Parent = holder
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0, 40)
	cc.Parent = cloud
	local cs = Instance.new("UIStroke")
	cs.Color = OUTLINE
	cs.Thickness = 3.5
	cs.Parent = cloud
	for k = 1, 4 do
		local puff = Instance.new("Frame")
		puff.Size = UDim2.fromOffset(52, 52)
		puff.AnchorPoint = Vector2.new(0.5, 0.5)
		puff.Position = UDim2.new(k / 5, 0, 0, 4)
		puff.BackgroundColor3 = Color3.new(1, 1, 1)
		puff.ZIndex = 0
		puff.Parent = cloud
		local pc = Instance.new("UICorner")
		pc.CornerRadius = UDim.new(1, 0)
		pc.Parent = puff
		local ps = Instance.new("UIStroke")
		ps.Color = OUTLINE
		ps.Thickness = 3.5
		ps.Parent = puff
	end
	local cover = Instance.new("Frame")
	cover.Size = UDim2.new(1, -8, 1, -8)
	cover.Position = UDim2.fromOffset(4, 4)
	cover.BackgroundColor3 = Color3.new(1, 1, 1)
	cover.BorderSizePixel = 0
	cover.ZIndex = 2
	cover.Parent = cloud
	local cvc = Instance.new("UICorner")
	cvc.CornerRadius = UDim.new(0, 36)
	cvc.Parent = cover
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -24, 1, -12)
	label.Position = UDim2.fromOffset(12, 6)
	label.Font = TITLE_FONT
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(70, 44, 26)
	label.Text = ""
	label.ZIndex = 3
	label.Parent = cloud
	local size = Instance.new("UITextSizeConstraint")
	size.MaxTextSize = 30
	size.Parent = label

	Audio.play("bubble", { jitter = 0.05 })
	tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	if not wait(0.3) then
		return false
	end
	-- Tekst literka po literce (UTF-8: litery polskie mają po 2 bajty)
	local letters = {}
	for _, code in utf8.codes(text) do
		table.insert(letters, utf8.char(code))
	end
	for i = 1, #letters do
		label.Text = table.concat(letters, "", 1, i)
		if i % 2 == 0 and letters[i] ~= " " then
			Audio.play("blip", { volume = 0.5, jitter = 0.15 })
		end
		if not wait(0.035) then
			return false
		end
	end
	if not wait(hold) then
		return false
	end
	tween(scale, 0.25, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	task.delay(0.3, function()
		follow:Disconnect()
		bill:Destroy()
	end)
	return true
end

-- Zamrożenie postaci gracza: zakotwiczony korzeń i sterowanie wyłączone (jeśli jest PlayerModule)
local function setFrozen(frozen: boolean)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.Anchored = frozen
	end
	local module = player.PlayerScripts:FindFirstChild("PlayerModule")
	if module and module:IsA("ModuleScript") then
		pcall(function()
			local controls = (require(module) :: any):GetControls()
			if frozen then
				controls:Disable()
			else
				controls:Enable()
			end
		end)
	end
end

-- ===== Sprzątanie =====

local function cleanup(s: Scene)
	for _, c in s.connections do
		c:Disconnect()
	end
	for _, sound in s.loops do
		Audio.stop(sound, 0.6)
	end
	for _, t in s.tracks do
		t:Stop(0)
	end
	if s.clone then
		s.clone:Destroy()
	end
	for _, b in s.bubbles do
		b:Destroy()
	end
	if s.leszy then
		s.leszy:Destroy()
	end
	if s.leszyRig then
		LeszyRig.destroy(s.leszyRig)
		s.leszyRig = nil
	end
	dropMushroom(s)
	pickValue.Value, liftValue.Value, highValue.Value = 0, 0, 0
	MushroomView.remove("cut_small")
	MushroomView.remove("cut_mythic")
	MushroomView.remove("cut_nice")
	MushroomView.setViewer(nil)
	-- Światło wraca do stanu sprzed sceny, a dalej prowadzi je Atmosphere
	for k, v in s.lighting do
		pcall(function()
			(Lighting :: any)[k] = v
		end)
	end
	Atmosphere.setPaused(false)
	local blur = Lighting:FindFirstChild("CutsceneBlur")
	if blur then
		blur:Destroy()
	end
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = 70
	end
	for _, g in s.hiddenGuis do
		g.Enabled = true
	end
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
	end)
	local character = player.Character
	if character then
		for _, d in character:GetDescendants() do
			if d:IsA("BasePart") or d:IsA("Decal") then
				(d :: any).LocalTransparencyModifier = 0
			end
		end
		-- Gracz stoi przed fotelem na ganku, twarzą do lasu (tam czeka pierwszy grzyb)
		local chair = Workspace:FindFirstChild("RockingChair", true)
		local pivot = chair and chair:GetAttribute("Pivot")
		if typeof(pivot) == "Vector3" then
			character:PivotTo(CFrame.lookAt(pivot + Vector3.new(-2.5, 3, 2.5), pivot + Vector3.new(-2.5, 3, 30)))
		end
	end
	setFrozen(false)
	tween(s.fade, 0.8, { BackgroundTransparency = 1 })
	letterbox(s, false, 0.6)
	task.delay(1, function()
		s.gui:Destroy()
	end)
end

local function finish(s: Scene)
	if s.finished then
		return
	end
	s.finished = true
	s.cancelled = true
	scene = nil
	cleanup(s)
	Audio.music("tutorial", 2)
	if s.onDone then
		task.spawn(s.onDone)
	end
end

-- ===== Scenariusz =====

local SMALL = onPath(84, 1.8)
local MYTHIC = onPath(106, -0.6)
local LESZY_RISE = onPath(118, 5)

local function run(s: Scene)
	local camera = Workspace.CurrentCamera
	-- Start: czerń, pasy kinowe, napis
	letterbox(s, true, 0.01)
	makeClone(s)
	MushroomView.setViewer(Vector3.new(0, 0, 95))
	MushroomView.add({
		{ id = "cut_small", position = SMALL, species = "porcini" },
		{ id = "cut_mythic", position = MYTHIC, species = "glowing_agaric", variant = "rainbow" },
	})
	setLighting(s, "night", 0)
	placeAt(s, onPath(66), Vector3.new(0, 0, 1))
	table.insert(s.loops, Audio.loop("forest", 0.8) :: Sound)
	Audio.music("dream", 2)
	setCaption(s, Localize.t("CUT_TITLE"), true, 1.2)
	if not wait(2.4) then
		return
	end
	setCaption(s, Localize.t("CUT_TITLE"), false, 0.8)
	fadeTo(s, false, 1.6)

	phaseStart = os.clock()
	s.gui:SetAttribute("Phase", "walk")
	-- 1. Spacer ścieżką z latarnią, kamera z boku powoli jedzie za graczem. U góry pasek oleju, który spada.
	moveTo(s, onPath(82, 0.8), 5.2, "walk", 0.9)
	shot(look(onPath(62, 11) + Vector3.new(0, 5.5, 0), onPath(70) + Vector3.new(0, 2, 0)), look(onPath(76, 10) + Vector3.new(0, 4, 0), onPath(82) + Vector3.new(0, 1.5, 0)), 5.4, 50)
	local steps = task.spawn(function()
		while not cancelled() do
			Audio.play("footstep", { volume = 0.5, jitter = 0.12 })
			task.wait(0.42)
		end
	end)
	oilValue.Value = 0.45
	if s.oilGauge then
		s.oilGauge.Visible = true
	end
	tween(oilValue, 7, { Value = 0.26 }, Enum.EasingStyle.Linear)
	if not wait(0.9) then
		return
	end
	subtitle(s, Localize.t("CUT_SUB_OIL"))
	if not wait(3.2) then
		return
	end
	subtitle(s, nil)
	if not wait(1.1) then
		return
	end

	phaseStart = os.clock()
	s.gui:SetAttribute("Phase", "pick")
	-- Zbiera grzybka: zbliżenie z boku, kuca, zrywa, ogląda i chowa do plecaka
	task.cancel(steps)
	shot(look(SMALL + Vector3.new(6.5, 3.2, 4.5), SMALL + Vector3.new(-0.6, 1.6, -1.2)), look(SMALL + Vector3.new(5.4, 2.8, 3.2), SMALL + Vector3.new(-0.6, 2, -1.2)), 2.8, 50)
	if not pickUp(s, "cut_small", SMALL, false) then
		return
	end
	if not wait(0.6) then
		return
	end
	if not stash(s) then
		return
	end
	if not wait(0.25) then
		return
	end

	phaseStart = os.clock()
	s.gui:SetAttribute("Phase", "mythic")
	-- 2. W oddali lśni tęczowy grzyb: kamera zza pleców, muzyka gęstnieje, latarnia zaczyna migać
	Audio.music("eerie", 1.5)
	Audio.play("shimmer")
	shot(look(onPath(80, -1.5) + Vector3.new(0, 3.4, -1), MYTHIC + Vector3.new(0, 1.5, 0)), look(onPath(88, -1.2) + Vector3.new(0, 2.6, 0), MYTHIC + Vector3.new(0, 1.2, 0)), 4.2, 45)
	moveTo(s, MYTHIC - Vector3.new(0, 0, 1.6), 4, "walk", 0.75)
	steps = task.spawn(function()
		while not cancelled() do
			Audio.play("footstep", { volume = 0.45, jitter = 0.12 })
			task.wait(0.5)
		end
	end)
	tween(oilValue, 4, { Value = 0.1 }, Enum.EasingStyle.Linear)
	if not wait(1.2) then
		return
	end
	Audio.play("warn", { volume = 0.7 })
	subtitle(s, Localize.t("CUT_SUB_LOW"), Color3.fromRGB(255, 130, 110))
	if not wait(2.8) then
		return
	end
	task.cancel(steps)
	subtitle(s, nil)

	phaseStart = os.clock()
	s.gui:SetAttribute("Phase", "grab")
	-- Wyrywa go z wysiłkiem i unosi nad głowę: błysk, iskry
	shot(look(MYTHIC + Vector3.new(-8, 3.2, 5.5), MYTHIC + Vector3.new(0, 1.8, -1.4)), look(MYTHIC + Vector3.new(-6.8, 2.6, 4.6), MYTHIC + Vector3.new(0, 3.2, -1.4)), 2.6, 54)
	if not pickUp(s, "cut_mythic", MYTHIC, true) then
		return
	end
	Audio.play("boom", { volume = 0.6 })
	s.fade.BackgroundColor3 = Color3.new(1, 1, 1)
	s.fade.BackgroundTransparency = 0.25
	tween(s.fade, 0.5, { BackgroundTransparency = 1 })
	if not wait(0.9) then
		return
	end
	s.fade.BackgroundColor3 = Color3.new(0, 0, 0)
	-- Latarnia gaśnie: ostatnie mrugnięcia i ciemność
	Audio.music(nil, 0.4)
	tween(oilValue, 0.6, { Value = 0 }, Enum.EasingStyle.Quad)
	if not wait(0.6) then
		return
	end
	Audio.play("whoosh", { volume = 0.5, pitch = 0.6 })
	subtitle(s, Localize.t("CUT_SUB_OUT"), Color3.fromRGB(255, 130, 110))
	tween(highValue, 0.8, { Value = 0 }, Enum.EasingStyle.Quad)
	tween(liftValue, 0.8, { Value = 0.5 }, Enum.EasingStyle.Quad)
	setLighting(s, "danger", 1.2)
	if not wait(1.2) then
		return
	end
	Audio.play("rumble", { duration = 3 })
	s.shake = 0.35
	subtitle(s, Localize.t("CUT_SUB_LESZY"), Color3.fromRGB(255, 110, 90))
	if not wait(1.2) then
		return
	end

	phaseStart = os.clock()
	s.gui:SetAttribute("Phase", "leszy")
	-- 3. Leszy wyłazi z ziemi skulony i się prostuje
	subtitle(s, nil)
	makeLeszy(s, CFrame.lookAt(LESZY_RISE - Vector3.new(0, 13, 0), MYTHIC - Vector3.new(0, 13, 0)))
	leszyValue.Value = CFrame.lookAt(LESZY_RISE - Vector3.new(0, 13, 0), Vector3.new(MYTHIC.X, -13, MYTHIC.Z))
	tween(leszyValue, 2.2, { Value = CFrame.lookAt(LESZY_RISE, Vector3.new(MYTHIC.X, 0, MYTHIC.Z)) }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	shot(look(LESZY_RISE + Vector3.new(-8, 2, -13), LESZY_RISE + Vector3.new(0, 7, 0)), look(LESZY_RISE + Vector3.new(-6.5, 2.6, -11), LESZY_RISE + Vector3.new(0, 10.5, 0)), 2.6, 60)
	s.shake = 0.5
	if not wait(2.2) then
		return
	end
	phaseStart = os.clock()
	s.gui:SetAttribute("Phase", "eyes")
	-- Zbliżenie na twarz: oczy i serce zapłoną, ryk z rękami w górze
	shot(look(LESZY_RISE + Vector3.new(-2.4, 12.8, -6.5), LESZY_RISE + Vector3.new(0, 13, 0)), nil, 0, 40)
	s.shake = 0.15
	if not wait(0.5) then
		return
	end
	leszyEyes(s, true)
	leszyDo(s, "roar")
	Audio.play("roar")
	s.shake = 0.7
	-- Kamera odskakuje, żeby było widać całą sylwetkę z łapami w górze
	shot(look(LESZY_RISE + Vector3.new(-2.4, 12.8, -6.5), LESZY_RISE + Vector3.new(0, 13, 0)), look(LESZY_RISE + Vector3.new(-5, 6.5, -15), LESZY_RISE + Vector3.new(0, 11, 0)), 0.9, 52, Enum.EasingStyle.Quart)
	if not wait(1.3) then
		return
	end

	phaseStart = os.clock()
	s.gui:SetAttribute("Phase", "chase")
	-- 4. Pościg: gracz biegnie ścieżką do chatki z grzybem w ręce, Leszy dudni za nim i dogania
	endPose(s)
	Audio.music("chase", 0.3)
	table.insert(s.loops, Audio.loop("heartbeat", 0.9) :: Sound)
	s.shake = 0.12
	local runFrom = MYTHIC - Vector3.new(0, 0, 1.6)
	placeAt(s, runFrom, Vector3.new(0, 0, -1))
	local runTo = onPath(76)
	moveTo(s, runTo, 5, "run", 1.25)
	leszyValue.Value = CFrame.lookAt(LESZY_RISE, runFrom)
	leszyDo(s, "run")
	tween(leszyValue, 5, { Value = CFrame.lookAt(onPath(81), runTo) }, Enum.EasingStyle.Linear)
	shot(look(runFrom + Vector3.new(1.5, 2.6, -6), runFrom + Vector3.new(0, 2.2, 2)), look(runTo + Vector3.new(1.5, 2.8, -6.5), runTo + Vector3.new(0, 3, 3)), 5, 72, Enum.EasingStyle.Linear)
	local crack = task.spawn(function()
		while not cancelled() do
			Audio.play("footstep", { volume = 0.8, pitch = 1.2, jitter = 0.1 })
			task.wait(0.26)
		end
	end)
	if not wait(4.2) then
		return
	end

	phaseStart = os.clock()
	s.gui:SetAttribute("Phase", "caught")
	-- Złapany: Leszy rzuca się z łapami do przodu, uderzenie, czerń
	leszyDo(s, "lunge")
	tween(leszyValue, 0.5, { Value = CFrame.lookAt(runTo + Vector3.new(0, 0, 1.5), runTo - Vector3.new(0, 0, 3)) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	shot(look(runTo + Vector3.new(0.5, 3.2, -4), runTo + Vector3.new(0, 4.5, 3)), look(runTo + Vector3.new(0.3, 3, -2.6), runTo + Vector3.new(0, 5.5, 3)), 0.6, 85, Enum.EasingStyle.Quad)
	s.shake = 1
	if not wait(0.6) then
		return
	end
	task.cancel(crack)
	Audio.music(nil, 0.1)
	Audio.play("sting")
	s.fade.BackgroundTransparency = 0
	s.shake = 0
	if s.oilGauge then
		s.oilGauge.Visible = false
	end
	dropMushroom(s)
	if not wait(1.6) then
		return
	end
	for _, sound in s.loops do
		Audio.stop(sound, 1.2)
	end
	table.clear(s.loops)
	if not wait(1.2) then
		return
	end

	phaseStart = os.clock()
	s.gui:SetAttribute("Phase", "wake")
	-- 5. Poranek: gracz budzi się na bujanym fotelu
	if s.leszy then
		s.leszy:Destroy()
		s.leszy = nil
	end
	setLighting(s, "morning", 0)
	oilValue.Value = 1
	local chair = Workspace:FindFirstChild("RockingChair", true)
	local pivotAttr = chair and chair:GetAttribute("Pivot")
	local pivot = if typeof(pivotAttr) == "Vector3" then pivotAttr else Vector3.new(9.5, 1, -9.8)
	local seatY = pivot.Y + 1.6
	play(s, "sit")
	rootValue.Value = CFrame.lookAt(Vector3.new(pivot.X, seatY + 0.9, pivot.Z + 0.1), Vector3.new(pivot.X, seatY + 0.9, pivot.Z + 10))
	local chairBase = if chair and chair:IsA("Model") then chair:GetPivot() else nil
	local rockStart = os.clock()
	table.insert(s.connections, RunService.RenderStepped:Connect(function()
		-- Bujanie: fotel i gracz kołyszą się razem wokół płóz
		local angle = math.rad(5) * math.sin((os.clock() - rockStart) * 1.8)
		local rock = CFrame.new(pivot) * CFrame.Angles(angle, 0, 0) * CFrame.new(-pivot)
		if chair and chair:IsA("Model") and chairBase then
			chair:PivotTo(rock * chairBase)
		end
		if s.root then
			s.root.CFrame = rock * CFrame.lookAt(Vector3.new(pivot.X, seatY + 0.9, pivot.Z + 0.1), Vector3.new(pivot.X, seatY + 0.9, pivot.Z + 10))
		end
	end))
	-- Fotel przestaje się bujać po scenie (wraca na miejsce)
	table.insert(s.connections, {
		Disconnect = function()
			if chair and chair:IsA("Model") and chairBase then
				chair:PivotTo(chairBase)
			end
		end,
	} :: any)
	rootValue.Value = rootValue.Value -- klon ustawia pętla bujania
	local blur = Instance.new("BlurEffect")
	blur.Name = "CutsceneBlur"
	blur.Size = 28
	blur.Parent = Lighting
	shot(look(Vector3.new(pivot.X - 4, seatY + 3, pivot.Z + 11), Vector3.new(pivot.X, seatY + 1.2, pivot.Z)), look(Vector3.new(pivot.X - 3, seatY + 2.4, pivot.Z + 8.5), Vector3.new(pivot.X, seatY + 1.6, pivot.Z)), 6, 50)
	table.insert(s.loops, Audio.loop("birds", 0.7) :: Sound)
	Audio.play("gasp")
	Audio.music("wake", 2.5)
	fadeTo(s, false, 1.8)
	tween(blur, 2.4, { Size = 0 })
	-- Mruganie: dwa razy zaciemnienie i jasno
	if not wait(0.8) then
		return
	end
	for _ = 1, 2 do
		tween(s.fade, 0.12, { BackgroundTransparency = 0.2 })
		if not wait(0.14) then
			return
		end
		tween(s.fade, 0.25, { BackgroundTransparency = 1 })
		if not wait(0.45) then
			return
		end
	end
	Audio.play("creak", { volume = 0.6, duration = 2.5 })
	if not thought(s, Localize.t("CUT_DREAM"), 1.6) then
		return
	end
	-- Wniosek ze snu: bez oleju przychodzi Leszy
	if not thought(s, Localize.t("CUT_DREAM2"), 1.5) then
		return
	end

	phaseStart = os.clock()
	s.gui:SetAttribute("Phase", "nice")
	-- 6. Kamera leci do grzyba przy ścieżce: „Ooo… ale fajny grzyb!”
	local first = (Config :: any).Tutorial and (Config :: any).Tutorial.spots and (Config :: any).Tutorial.spots[1]
	local target = if first then Vector3.new(first[1], 0, first[2]) else onPath(48, 2)
	-- Prawdziwe grzyby samouczka pojawią się dopiero po scence, więc tu stoi jego sobowtór
	MushroomView.add({ { id = "cut_nice", position = target, species = Config.Tutorial.species } })
	MushroomView.setViewer(target)
	Audio.play("ping")
	shot(look(Vector3.new(pivot.X - 3, seatY + 2.4, pivot.Z + 8.5), target), look(target + Vector3.new(-5, 4.2, -9), target + Vector3.new(0, 1, 0)), 2.2, 45, Enum.EasingStyle.Quart)
	if not wait(2.3) then
		return
	end
	if not thought(s, Localize.t("CUT_NICE"), 1.4, UDim2.fromScale(0.08, 0.86)) then
		return
	end
	fadeTo(s, true, 0.6)
	if not wait(0.7) then
		return
	end
	if camera then
		camera.CameraType = Enum.CameraType.Custom
	end
	finish(s)
end

-- ===== API =====

function IntroCutscene.isPlaying(): boolean
	return scene ~= nil
end

function IntroCutscene.play(onDone: (() -> ())?)
	if scene then
		return
	end
	local gui, fade, bars, skip, caption = buildGui()
	local s: Scene = {
		cancelled = false,
		finished = false,
		tracks = {},
		gui = gui,
		fade = fade,
		bars = bars,
		skip = skip,
		caption = caption,
		connections = {},
		loops = {},
		hiddenGuis = {},
		bubbles = {},
		lighting = {
			ClockTime = Lighting.ClockTime,
			Brightness = Lighting.Brightness,
			Ambient = Lighting.Ambient,
			OutdoorAmbient = Lighting.OutdoorAmbient,
		},
		shake = 0,
		cameraCf = CFrame.new(),
		fov = 70,
		onDone = onDone,
		leszyAnim = "stand",
		leszyAnimAt = 0,
		leszyPhase = 0,
		leszyLastSin = 0,
		r15 = false,
		motors = {},
		posing = false,
		effort = 0,
		heldRainbow = false,
	}
	buildSubtitle(s)
	buildOilGauge(s)
	scene = s
	Atmosphere.setPaused(true)
	-- Bez HUD-u, listy graczy i czatu; postać gracza niewidoczna i nieruchoma
	for _, g in player.PlayerGui:GetChildren() do
		if g:IsA("ScreenGui") and g ~= gui and g.Enabled then
			g.Enabled = false
			table.insert(s.hiddenGuis, g)
		end
	end
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
	end)
	local character = player.Character
	if character then
		for _, d in character:GetDescendants() do
			if d:IsA("BasePart") or d:IsA("Decal") then
				(d :: any).LocalTransparencyModifier = 1
			end
		end
	end
	-- Postać stoi w miejscu przez całą scenę (bez sterowania)
	setFrozen(true)
	pcall(function()
		player:RequestStreamAroundAsync(Vector3.new(0, 0, 90))
	end)

	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	-- Kamera w każdej klatce: ujęcie + trzęsienie, które samo słabnie
	table.insert(s.connections, RunService.RenderStepped:Connect(function(dt)
		local cam = Workspace.CurrentCamera
		if not cam then
			return
		end
		local shake = s.shake
		local offset = CFrame.new()
		if shake > 0.01 then
			local t = os.clock() * 30
			offset = CFrame.Angles(math.noise(t, 1) * 0.04 * shake, math.noise(t, 2) * 0.04 * shake, math.noise(t, 3) * 0.03 * shake)
			s.shake = math.max(0, shake - dt * 0.35)
		end
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = cameraValue.Value * offset
		-- Inne moduły potrafią włączyć swój interfejs w trakcie (np. panel DEV co aktualizację stanu)
		for _, g in player.PlayerGui:GetChildren() do
			if g:IsA("ScreenGui") and g ~= s.gui and g.Enabled then
				g.Enabled = false
				if not table.find(s.hiddenGuis, g) then
					table.insert(s.hiddenGuis, g)
				end
			end
		end
		cam.FieldOfView = fovValue.Value
		local root = s.root
		if root and not s.finished then
			-- Na fotelu klona ustawia pętla bujania
			local chairing = s.tracks.sit and s.tracks.sit.IsPlaying
			if not chairing then
				root.CFrame = rootValue.Value
			end
		end
		animateLeszy(s, dt)
		updateOil(s)
		-- Mityczny grzyb w dłoni mieni się kolorami tęczy
		local cap = s.heldCap
		if cap and s.heldRainbow then
			cap.Color = Color3.fromHSV((os.clock() * 0.45) % 1, 0.55, 1)
			local light = cap:FindFirstChildOfClass("PointLight")
			if light then
				light.Color = cap.Color
			end
		end
	end))
	-- Własna poza zbierania nadpisuje animacje po ich kroku
	table.insert(s.connections, RunService.Stepped:Connect(function()
		poseClone(s)
	end))

	skip.Text = Localize.t("CUT_SKIP")
	task.delay(1.5, function()
		if scene == s then
			skip.Visible = true
			skip.Position = UDim2.new(1, -24, 1, 40)
			tween(skip, 0.4, { Position = UDim2.new(1, -24, 1, -24) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		end
	end)
	skip.Activated:Connect(function()
		Audio.play("click")
		finish(s)
	end)

	task.spawn(function()
		run(s)
		if not s.finished and not s.cancelled then
			finish(s)
		end
	end)
end

return IntroCutscene
