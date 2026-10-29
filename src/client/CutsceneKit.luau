--!strict
-- Wspólne narzędzia do cutscenek (sen na start, kradzież w ogródku).
--   Scena: pasy kinowe, czerń, napisy, „Pomiń”, kamera z ujęciami i trzęsieniem, ukryty HUD, zamrożony gracz,
--          zapis i przywrócenie światła. Każde czekanie kończy się od razu, gdy gracz pominie scenę.
--   Aktorzy: klony awatara gracza (albo przebrany złodziej). Chodzą zwykłymi animacjami Robloxa, a do
--          wszystkiego innego (klęczenie, zrywanie, ocieranie potu, skradanie…) mają klipy z klatek kluczowych
--          (CutsceneClips). Klip nadpisuje stawy po kroku animacji, z płynnym wejściem i wyjściem.
--   Dymki: mowa i myśli nad głową aktora (tekst pisany literka po literce), wykrzyknik „!” i „?”.

local ContentProvider = game:GetService("ContentProvider")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Atmosphere = require(script.Parent.Atmosphere)
local Audio = require(script.Parent.Audio)
local Localize = require(script.Parent.Localize)
local UiKit = require(script.Parent.UiKit)

local player = Players.LocalPlayer

local Kit = {}

local TITLE_FONT = Enum.Font.FredokaOne
local OUTLINE = UiKit.OUTLINE

-- ===== Klipy (klatki kluczowe) =====
-- Klip: { length, loop?, keys = { { t, ease?, pose = { Staw = { rx, ry, rz, x, y, z } } } }, events = { { t, name } } }
-- Staw nieobecny w klatce trzyma wartość z poprzedniej klatki. Kąty w stopniach, przesunięcia w studach.

export type JointPose = { rx: number?, ry: number?, rz: number?, x: number?, y: number?, z: number? }
export type Key = { t: number, ease: string?, pose: { [string]: JointPose } }
export type Clip = { length: number, loop: boolean?, keys: { Key }, events: { { t: number, name: string } }? }

type Resolved = { t: number, ease: string, values: { [string]: { number } } }

local JOINTS = {
	"Root", "Waist", "Neck",
	"LeftShoulder", "LeftElbow", "LeftWrist", "RightShoulder", "RightElbow", "RightWrist",
	"LeftHip", "LeftKnee", "LeftAnkle", "RightHip", "RightKnee", "RightAnkle",
}

local resolvedCache: { [Clip]: { Resolved } } = {}

local function resolve(clip: Clip): { Resolved }
	local cached = resolvedCache[clip]
	if cached then
		return cached
	end
	local out: { Resolved } = {}
	local current: { [string]: { number } } = {}
	for _, joint in JOINTS do
		current[joint] = { 0, 0, 0, 0, 0, 0 }
	end
	for _, key in clip.keys do
		local values: { [string]: { number } } = {}
		for _, joint in JOINTS do
			local prev = current[joint]
			local p = key.pose[joint]
			local v = if p
				then { p.rx or prev[1], p.ry or prev[2], p.rz or prev[3], p.x or prev[4], p.y or prev[5], p.z or prev[6] }
				else { prev[1], prev[2], prev[3], prev[4], prev[5], prev[6] }
			values[joint] = v
			current[joint] = v
		end
		table.insert(out, { t = key.t, ease = key.ease or "smooth", values = values })
	end
	resolvedCache[clip] = out
	return out
end

local function ease(kind: string, a: number): number
	if kind == "linear" then
		return a
	elseif kind == "in" then
		return a * a
	elseif kind == "out" then
		return 1 - (1 - a) * (1 - a)
	elseif kind == "back" then
		-- przeskok za cel i powrót (sprężyste)
		local c = 1.9
		local x = a - 1
		return 1 + (c + 1) * x * x * x + c * x * x
	elseif kind == "snap" then
		return 1 - (1 - a) ^ 4
	end
	return a * a * (3 - 2 * a)
end

local function toCFrame(v: { number }): CFrame
	return CFrame.new(v[4], v[5], v[6]) * CFrame.Angles(math.rad(v[1]), math.rad(v[2]), math.rad(v[3]))
end

-- Poza klipu w chwili t (z pętlą, jeśli klip się zapętla)
local function sample(clip: Clip, t: number): { [string]: CFrame }
	local keys = resolve(clip)
	local time = if clip.loop then t % clip.length else math.clamp(t, 0, clip.length)
	local a, b = keys[1], keys[1]
	for i = 1, #keys do
		if keys[i].t <= time then
			a = keys[i]
			b = keys[i + 1] or (if clip.loop then keys[1] else keys[i])
		end
	end
	local span = b.t - a.t
	if clip.loop and b == keys[1] and a ~= b then
		span = clip.length - a.t + b.t
	end
	local alpha = if span > 0 then ease(b.ease, math.clamp((time - a.t) / span, 0, 1)) else 1
	local out: { [string]: CFrame } = {}
	for _, joint in JOINTS do
		local va, vb = a.values[joint], b.values[joint]
		local mixed = table.create(6)
		for i = 1, 6 do
			mixed[i] = va[i] + (vb[i] - va[i]) * alpha
		end
		out[joint] = toCFrame(mixed)
	end
	return out
end

-- ===== Scena =====

export type Actor = {
	model: Model,
	root: BasePart,
	humanoid: Humanoid,
	motors: { [string]: any }, -- Motor6D albo AnimationConstraint (oba mają Transform)
	written: { [string]: CFrame },
	tracks: { [string]: AnimationTrack },
	rootValue: CFrameValue,
	hip: number,
	clip: Clip?,
	clipStart: number,
	clipSpeed: number,
	clipWeight: number,
	clipTarget: number,
	clipFade: number,
	clipEvents: ((string) -> ())?,
	clipFired: { [number]: boolean },
	shake: number, -- drżenie tułowia (wysiłek)
	freeRoot: boolean, -- true = korzeń ustawia ktoś inny (np. bujany fotel)
	head: BasePart?,
	props: { Instance },
}

export type Scene = {
	cancelled: boolean,
	finished: boolean,
	gui: ScreenGui,
	fade: Frame,
	bars: { Frame },
	caption: TextLabel,
	subtitle: TextLabel,
	skip: TextButton,
	camera: CFrameValue,
	fov: NumberValue,
	cameraFn: (() -> CFrame)?,
	shake: number,
	actors: { Actor },
	connections: { RBXScriptConnection },
	cleanups: { () -> () },
	loops: { Sound },
	hiddenGuis: { ScreenGui },
	saved: { [Instance]: { [string]: any } },
	onFinish: (() -> ())?,
	phase: string,
	phaseStart: number,
}

local current: Scene? = nil

function Kit.isPlaying(): boolean
	return current ~= nil
end

function Kit.cancelled(s: Scene): boolean
	return s.cancelled
end

-- Do testów w Studio: atrybut gracza CutsceneFreeze = nazwa fazy zatrzymuje scenę (po CutsceneFreezeAfter s)
local function frozen(s: Scene): boolean
	local phase = player:GetAttribute("CutsceneFreeze")
	local after = player:GetAttribute("CutsceneFreezeAfter")
	return phase ~= nil and s.phase == phase and os.clock() - s.phaseStart >= (if typeof(after) == "number" then after else 1)
end

function Kit.phase(s: Scene, name: string)
	s.phase = name
	s.phaseStart = os.clock()
	s.gui:SetAttribute("Phase", name)
end

function Kit.wait(s: Scene, seconds: number): boolean
	local untilTime = os.clock() + seconds
	while os.clock() < untilTime or frozen(s) do
		if s.cancelled then
			return false
		end
		RunService.RenderStepped:Wait()
	end
	return not s.cancelled
end

function Kit.tween(object: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local t = TweenService:Create(object, TweenInfo.new(time, style or Enum.EasingStyle.Sine, direction or Enum.EasingDirection.InOut), props)
	t:Play()
	return t
end
local tween = Kit.tween

-- Ujęcie: kamera jedzie z `from` do `to` (albo stoi w `from`)
function Kit.shot(s: Scene, from: CFrame, to: CFrame?, time: number, fov: number?, style: Enum.EasingStyle?)
	s.cameraFn = nil
	s.camera.Value = from
	if fov then
		s.fov.Value = fov
	end
	if to then
		tween(s.camera, time, { Value = to }, style or Enum.EasingStyle.Sine)
	end
end

-- Kamera liczona co klatkę (np. jedzie przed biegnącym)
function Kit.follow(s: Scene, fn: () -> CFrame, fov: number?)
	s.cameraFn = fn
	if fov then
		s.fov.Value = fov
	end
end

function Kit.look(eye: Vector3, at: Vector3): CFrame
	return CFrame.lookAt(eye, at)
end

function Kit.fade(s: Scene, black: boolean, time: number, color: Color3?)
	if color then
		s.fade.BackgroundColor3 = color
	end
	tween(s.fade, time, { BackgroundTransparency = if black then 0 else 1 })
end

function Kit.flash(s: Scene, color: Color3, strength: number, time: number)
	s.fade.BackgroundColor3 = color
	s.fade.BackgroundTransparency = 1 - strength
	local t = tween(s.fade, time, { BackgroundTransparency = 1 })
	t.Completed:Connect(function()
		s.fade.BackgroundColor3 = Color3.new(0, 0, 0)
	end)
end

function Kit.letterbox(s: Scene, show: boolean, time: number)
	for _, bar in s.bars do
		tween(bar, time, { Size = UDim2.new(1, 0, if show then 0.11 else 0, 0) }, Enum.EasingStyle.Quad)
	end
end

function Kit.caption(s: Scene, text: string, show: boolean, time: number?)
	s.caption.Text = text
	local t = time or 0.8
	tween(s.caption, t, { TextTransparency = if show then 0 else 1 })
	local stroke = s.caption:FindFirstChildOfClass("UIStroke")
	if stroke then
		tween(stroke, t, { Transparency = if show then 0 else 1 })
	end
end

-- Napis na dole ekranu (nil = schowaj)
function Kit.subtitle(s: Scene, text: string?, color: Color3?)
	local label = s.subtitle
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if text then
		label.Text = text
		label.TextColor3 = color or Color3.fromRGB(255, 236, 200)
		local scale = label:FindFirstChildOfClass("UIScale") :: UIScale
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

-- Muzyka i pętle efektów, które scena wyłączy przy sprzątaniu
function Kit.loop(s: Scene, name: string, volume: number?): Sound?
	local sound = Audio.loop(name, volume)
	if sound then
		table.insert(s.loops, sound)
	end
	return sound
end

function Kit.stopLoops(s: Scene, fade: number?)
	for _, sound in s.loops do
		Audio.stop(sound, fade or 1)
	end
	table.clear(s.loops)
end

function Kit.onCleanup(s: Scene, fn: () -> ())
	table.insert(s.cleanups, fn)
end

-- Zapamiętuje właściwości (np. światła), żeby przywrócić je po scenie
function Kit.save(s: Scene, object: Instance?, props: { string })
	if not object then
		return
	end
	local saved = s.saved[object] or {}
	for _, name in props do
		if saved[name] == nil then
			saved[name] = (object :: any)[name]
		end
	end
	s.saved[object] = saved
end

-- ===== Interfejs sceny =====

local function buildGui(s: Scene)
	local gui = Instance.new("ScreenGui")
	gui.Name = "Cutscene"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	s.gui = gui

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
		table.insert(s.bars, bar)
	end

	local fade = Instance.new("Frame")
	fade.Name = "Fade"
	fade.Size = UDim2.fromScale(1, 1)
	fade.BackgroundColor3 = Color3.new(0, 0, 0)
	fade.BackgroundTransparency = 0
	fade.BorderSizePixel = 0
	fade.ZIndex = 5
	fade.Parent = gui
	s.fade = fade

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
	UiKit.outline(caption, 3).Transparency = 1
	s.caption = caption

	local sub = Instance.new("TextLabel")
	sub.Name = "Subtitle"
	sub.BackgroundTransparency = 1
	sub.AnchorPoint = Vector2.new(0.5, 0.5)
	sub.Position = UDim2.fromScale(0.5, 0.835)
	sub.Size = UDim2.fromScale(0.86, 0.065)
	sub.Font = TITLE_FONT
	sub.TextScaled = true
	sub.TextColor3 = Color3.fromRGB(255, 236, 200)
	sub.TextTransparency = 1
	sub.Text = ""
	sub.ZIndex = 6
	sub.Parent = gui
	local subSize = Instance.new("UITextSizeConstraint")
	subSize.MaxTextSize = 34
	subSize.Parent = sub
	UiKit.outline(sub, 3).Transparency = 1
	local subScale = Instance.new("UIScale")
	subScale.Parent = sub
	s.subtitle = sub

	local skip = Instance.new("TextButton")
	skip.Name = "Skip"
	skip.AnchorPoint = Vector2.new(1, 1)
	skip.Position = UDim2.new(1, -24, 1, 40)
	skip.Size = UDim2.fromOffset(150, 48)
	skip.Font = TITLE_FONT
	skip.TextSize = 24
	skip.Text = Localize.t("CUT_SKIP")
	skip.Visible = false
	skip.ZIndex = 8
	skip.Parent = gui
	local skipStroke = UiKit.button(skip, Color3.fromRGB(60, 46, 38), { stroke = 3, radius = UDim.new(1, 0), gloss = true })
	skipStroke.Color = OUTLINE
	UiKit.outline(skip, 2.5)
	s.skip = skip
end

-- ===== Dymki nad głową =====

local function bubbleFrame(s: Scene, think: boolean, width: number): (Frame, TextLabel, UIScale)
	local holder = Instance.new("Frame")
	holder.Name = if think then "Thought" else "Speech"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(width, 100)
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.ZIndex = 4
	holder.Parent = s.gui
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = holder
	local box = Instance.new("Frame")
	box.Name = "Box"
	box.Size = UDim2.new(1, 0, 1, -22)
	box.BackgroundColor3 = Color3.new(1, 1, 1)
	box.ZIndex = 4
	box.Parent = holder
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, if think then 40 else 18)
	c.Parent = box
	local st = Instance.new("UIStroke")
	st.Color = OUTLINE
	st.Thickness = 3.5
	st.Parent = box
	if think then
		-- Kółeczka prowadzące do głowy
		for i, size in { 18, 11 } do
			local dot = Instance.new("Frame")
			dot.Size = UDim2.fromOffset(size, size)
			dot.AnchorPoint = Vector2.new(0.5, 0)
			dot.Position = UDim2.new(0.5, -8 * i, 1, -22 + (i - 1) * 12)
			dot.BackgroundColor3 = Color3.new(1, 1, 1)
			dot.ZIndex = 4
			dot.Parent = holder
			local dc = Instance.new("UICorner")
			dc.CornerRadius = UDim.new(1, 0)
			dc.Parent = dot
			local ds = Instance.new("UIStroke")
			ds.Color = OUTLINE
			ds.Thickness = 3
			ds.Parent = dot
		end
	else
		-- Ogonek dymka (romb przykryty dołem dymka)
		local tail = Instance.new("Frame")
		tail.Size = UDim2.fromOffset(20, 20)
		tail.AnchorPoint = Vector2.new(0.5, 0.5)
		tail.Position = UDim2.new(0.5, 0, 1, -24)
		tail.Rotation = 45
		tail.BackgroundColor3 = Color3.new(1, 1, 1)
		tail.ZIndex = 3
		tail.Parent = holder
		local ts = Instance.new("UIStroke")
		ts.Color = OUTLINE
		ts.Thickness = 3.5
		ts.Parent = tail
		local cover = Instance.new("Frame")
		cover.Size = UDim2.fromOffset(30, 10)
		cover.AnchorPoint = Vector2.new(0.5, 1)
		cover.Position = UDim2.new(0.5, 0, 1, -22)
		cover.BackgroundColor3 = Color3.new(1, 1, 1)
		cover.BorderSizePixel = 0
		cover.ZIndex = 5
		cover.Parent = holder
	end
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.new(1, -24, 1, -36)
	text.Position = UDim2.fromOffset(12, 7)
	text.Font = TITLE_FONT
	text.TextScaled = true
	text.TextWrapped = true
	text.TextColor3 = Color3.fromRGB(46, 30, 20)
	text.Text = ""
	text.ZIndex = 6
	text.Parent = holder
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 30
	limit.Parent = text
	return holder, text, scale
end

local function headPoint(actor: Actor): Vector3
	local head = actor.head
	return if head then head.Position + Vector3.new(0, 1.6, 0) else actor.root.Position + Vector3.new(0, 3.6, 0)
end

-- Pozycja nad głową, ale zawsze w kadrze: nie wchodzi na czarne pasy ani za krawędź ekranu
-- (element ma AnchorPoint (0.5, 1), więc jego dół jest w punkcie y)
local function inFrame(s: Scene, element: GuiObject, x: number, y: number): UDim2
	local screen = s.gui.AbsoluteSize
	local top = if s.bars[1] then s.bars[1].AbsoluteSize.Y else 0
	local size = element.AbsoluteSize
	local margin = 10
	local minY = top + size.Y + margin
	local half = size.X / 2 + margin
	return UDim2.fromOffset(math.clamp(x, half, math.max(half, screen.X - half)), math.max(y, minY))
end

-- Dymek z mową albo myślą nad głową aktora; tekst pisze się literka po literce. fixed = stałe miejsce na ekranie.
function Kit.bubble(s: Scene, actor: Actor?, text: string, hold: number, think: boolean?, fixed: UDim2?, voice: number?): boolean
	local width = math.clamp(120 + (utf8.len(text) or 0) * 9, 200, 380)
	local holder, label, scale = bubbleFrame(s, think == true, width)
	local follow = RunService.RenderStepped:Connect(function()
		local cam = Workspace.CurrentCamera
		if fixed then
			holder.Position = fixed
		elseif actor and cam then
			local point, visible = cam:WorldToViewportPoint(headPoint(actor))
			holder.Visible = visible
			holder.Position = inFrame(s, holder, point.X, point.Y)
		end
	end)
	table.insert(s.connections, follow)
	Audio.play("bubble", { volume = 0.5 })
	tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	-- Pisanie po literce z cichym „blip” (wysokość głosu zależy od postaci)
	local count = 0
	for _, code in utf8.codes(text) do
		if s.cancelled then
			break
		end
		count += 1
		label.Text = label.Text .. utf8.char(code)
		if count % 2 == 0 then
			Audio.play("blip", { volume = 0.18, pitch = voice or 1.2, jitter = 0.08 })
		end
		task.wait(0.028)
	end
	local ok = Kit.wait(s, hold)
	tween(scale, 0.18, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	task.delay(0.2, function()
		follow:Disconnect()
		holder:Destroy()
	end)
	return ok
end

-- Duży wykrzyknik / znak zapytania nad głową (z podskokiem)
function Kit.mark(s: Scene, actor: Actor, symbol: string, color: Color3?)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromOffset(70, 80)
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Font = TITLE_FONT
	label.TextScaled = true
	label.Text = symbol
	label.TextColor3 = color or Color3.fromRGB(255, 70, 60)
	label.ZIndex = 7
	label.Parent = s.gui
	UiKit.outline(label, 4)
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = label
	local follow = RunService.RenderStepped:Connect(function()
		local cam = Workspace.CurrentCamera
		if cam then
			local point, visible = cam:WorldToViewportPoint(headPoint(actor) + Vector3.new(0, 0.6, 0))
			label.Visible = visible
			label.Position = inFrame(s, label, point.X, point.Y)
		end
	end)
	table.insert(s.connections, follow)
	tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	task.delay(1.1, function()
		tween(scale, 0.2, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.delay(0.25, function()
			follow:Disconnect()
			label:Destroy()
		end)
	end)
end

-- ===== Aktorzy =====

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

export type ActorOptions = {
	name: string?,
	keepLantern: boolean?, -- latarnia w prawej ręce (we śnie tak, w ogródku nie)
	thief: boolean?, -- przebranie złodzieja: czarna bluza, maska, czapka, worek
}

function Kit.actor(s: Scene, options: ActorOptions?): Actor?
	local o = options or {}
	local character = player.Character
	if not character then
		return nil
	end
	character.Archivable = true
	local clone = character:Clone()
	character.Archivable = false
	if not clone then
		return nil
	end
	clone.Name = o.name or "Actor"
	for _, d in clone:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.LocalTransparencyModifier = 0
		elseif d:IsA("Decal") then
			d.LocalTransparencyModifier = 0
		end
	end
	-- Nóż zawsze precz; latarnia tylko jeśli scena jej chce
	local knife = clone:FindFirstChild("HandKnife")
	if knife then
		knife:Destroy()
	end
	if not o.keepLantern then
		local lantern = clone:FindFirstChild("HandLantern")
		if lantern then
			lantern:Destroy()
		end
	end
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	local root = clone:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		clone:Destroy()
		return nil
	end
	-- Światło latarni gracza wisi przy korzeniu; w scenach świeci latarnia w dłoni (scena sama je ustawia)
	local attachment = root:FindFirstChild("LanternAttachment")
	if attachment then
		attachment:Destroy()
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.NameDisplayDistance = 0
	root.Anchored = true

	if o.thief then
		-- Ciemna bluza z kapturem, maska bandyty, czapka i worek na plecach
		for _, d in clone:GetDescendants() do
			if d:IsA("Shirt") or d:IsA("Pants") or d:IsA("ShirtGraphic") or d:IsA("Accessory") then
				d:Destroy()
			end
		end
		local skin = Color3.fromRGB(234, 184, 146)
		local hoodie = Color3.fromRGB(40, 38, 52)
		local trousers = Color3.fromRGB(28, 26, 34)
		for _, part in clone:GetChildren() do
			if part:IsA("BasePart") and part ~= root then
				local n = part.Name
				if n == "Head" or n:find("Hand") then
					part.Color = skin
				elseif n:find("Leg") or n:find("Foot") or n == "LowerTorso" then
					part.Color = trousers
				else
					part.Color = hoodie
				end
			end
		end
		local head = clone:FindFirstChild("Head") :: BasePart?
		local torso = (clone:FindFirstChild("UpperTorso") or clone:FindFirstChild("Torso")) :: BasePart?
		local function glue(name: string, size: Vector3, offset: CFrame, color: Color3, to: BasePart?, shape: Enum.PartType?)
			if not to then
				return
			end
			local p = Instance.new("Part")
			p.Name = name
			p.Size = size
			p.Color = color
			p.Material = Enum.Material.SmoothPlastic
			if shape then
				p.Shape = shape
			end
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Massless = true
			p.CFrame = to.CFrame * offset
			p.Parent = clone
			local w = Instance.new("WeldConstraint")
			w.Part0 = to
			w.Part1 = p
			w.Parent = p
		end
		if head then
			local hs = head.Size
			glue("Mask", Vector3.new(hs.X + 0.06, hs.Y * 0.24, hs.Z + 0.06), CFrame.new(0, hs.Y * 0.08, 0), Color3.fromRGB(20, 20, 24), head)
			glue("Beanie", Vector3.new(hs.X + 0.1, hs.Y * 0.32, hs.Z + 0.1), CFrame.new(0, hs.Y * 0.42, 0), Color3.fromRGB(196, 40, 40), head)
			glue("Pompom", Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, hs.Y * 0.68, 0), Color3.new(1, 1, 1), head, Enum.PartType.Ball)
			-- Oczy błyszczące spod maski
			for _, side in { -1, 1 } do
				glue("Eye", Vector3.new(0.16, 0.12, 0.05), CFrame.new(side * hs.X * 0.2, hs.Y * 0.08, -hs.Z / 2 - 0.04), Color3.new(1, 1, 1), head)
			end
			for _, d in head:GetChildren() do
				if d:IsA("Decal") and d.Name == "face" then
					d.Transparency = 0
				end
			end
		end
		if torso then
			local ts = torso.Size
			glue("Sack", Vector3.new(ts.X * 0.8, ts.Y * 0.9, ts.X * 0.7), CFrame.new(0, ts.Y * 0.1, ts.Z / 2 + ts.X * 0.3), Color3.fromRGB(176, 136, 86), torso, Enum.PartType.Ball)
		end
	end

	clone.Parent = Workspace
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	local tracks: { [string]: AnimationTrack } = {}
	for name, path in { walk = { "walk", "WalkAnim" }, run = { "run", "RunAnim" }, idle = { "idle", "Animation1" }, sit = { "sit", "SitAnim" } } do
		local id = animationId(character, path)
		if id then
			local anim = Instance.new("Animation")
			anim.AnimationId = id
			local ok, track = pcall(function()
				return animator:LoadAnimation(anim)
			end)
			if ok and track then
				track.Looped = true
				tracks[name] = track
			end
		end
	end
	local motors: { [string]: any } = {}
	for _, d in clone:GetDescendants() do
		if d:IsA("Motor6D") or d:IsA("AnimationConstraint") then
			motors[d.Name] = d
		end
	end
	local hip = if humanoid.RigType == Enum.HumanoidRigType.R15 then humanoid.HipHeight + root.Size.Y / 2 else 3
	local rootValue = Instance.new("CFrameValue")
	rootValue.Value = root.CFrame
	local actor: Actor = {
		model = clone,
		root = root,
		humanoid = humanoid,
		motors = motors,
		written = {},
		tracks = tracks,
		rootValue = rootValue,
		hip = hip,
		clip = nil,
		clipStart = 0,
		clipSpeed = 1,
		clipWeight = 0,
		clipTarget = 0,
		clipFade = 0.2,
		clipEvents = nil,
		clipFired = {},
		shake = 0,
		freeRoot = false,
		head = clone:FindFirstChild("Head") :: BasePart?,
		props = {},
	}
	table.insert(s.actors, actor)
	return actor
end

function Kit.place(actor: Actor, at: Vector3, facing: Vector3)
	local h = actor.hip
	local look = Vector3.new(facing.X, 0, facing.Z)
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	actor.rootValue.Value = CFrame.lookAt(at + Vector3.new(0, h, 0), at + Vector3.new(0, h, 0) + look.Unit)
end

function Kit.face(actor: Actor, toward: Vector3, time: number?)
	local p = actor.rootValue.Value.Position
	local dir = Vector3.new(toward.X - p.X, 0, toward.Z - p.Z)
	if dir.Magnitude < 0.01 then
		return
	end
	local goal = CFrame.lookAt(p, p + dir.Unit)
	if time and time > 0 then
		tween(actor.rootValue, time, { Value = goal }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	else
		actor.rootValue.Value = goal
	end
end

function Kit.track(actor: Actor, name: string?, speed: number?)
	for other, track in actor.tracks do
		if other ~= name and track.IsPlaying then
			track:Stop(0.2)
		end
	end
	if name then
		local track = actor.tracks[name]
		if track then
			if not track.IsPlaying then
				track:Play(0.2)
			end
			track:AdjustSpeed(speed or 1)
		end
	end
end

-- Idzie (albo biegnie) do punktu na ziemi; zwraca czas drogi
function Kit.move(actor: Actor, to: Vector3, time: number, anim: string?, speed: number?)
	local h = actor.hip
	local from = actor.rootValue.Value.Position
	local goal = to + Vector3.new(0, h, 0)
	local dir = Vector3.new(goal.X - from.X, 0, goal.Z - from.Z)
	if anim then
		Kit.track(actor, anim, speed)
	end
	if dir.Magnitude > 0.05 then
		tween(actor.rootValue, time, { Value = CFrame.lookAt(goal, goal + dir.Unit) }, Enum.EasingStyle.Linear)
	end
end

-- Klip z klatek kluczowych. weight = jak mocno nadpisuje animacje (1 = całkiem). events(name) przy zdarzeniach.
function Kit.clip(actor: Actor, clip: Clip?, options: { speed: number?, fade: number?, weight: number?, events: ((string) -> ())? }?)
	local o = options or {}
	if clip then
		actor.clip = clip
		actor.clipStart = os.clock()
		actor.clipSpeed = o.speed or 1
		actor.clipEvents = o.events
		actor.clipFired = {}
		actor.clipTarget = o.weight or 1
	else
		actor.clipTarget = 0
	end
	actor.clipFade = o.fade or 0.2
end

-- Rekwizyt przyklejony do części ciała (np. grzyb w dłoni). offset względem tej części.
function Kit.attach(actor: Actor, partName: string, model: Instance, offset: CFrame)
	local part = actor.model:FindFirstChild(partName)
	if not part or not part:IsA("BasePart") then
		return
	end
	local parts: { BasePart } = {}
	if model:IsA("BasePart") then
		table.insert(parts, model)
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	-- Model przesuwamy tak, żeby jego pivot był w miejscu offsetu, a potem spawamy
	if model:IsA("Model") then
		model:PivotTo(part.CFrame * offset)
	elseif model:IsA("BasePart") then
		model.CFrame = part.CFrame * offset
	end
	for _, p in parts do
		p.Anchored = false
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = part
		weld.Part1 = p
		weld.Parent = p
	end
	model.Parent = actor.model
	table.insert(actor.props, model)
end

-- Co klatkę po kroku animacji: klip nadpisuje stawy (z płynnym wejściem/wyjściem) + drżenie z wysiłku
local function poseActor(actor: Actor, dt: number)
	local step = if actor.clipFade > 0 then dt / actor.clipFade else 1
	if actor.clipWeight < actor.clipTarget then
		actor.clipWeight = math.min(actor.clipTarget, actor.clipWeight + step)
	elseif actor.clipWeight > actor.clipTarget then
		actor.clipWeight = math.max(actor.clipTarget, actor.clipWeight - step)
	end
	local clip = actor.clip
	local pose: { [string]: CFrame }? = nil
	if clip and actor.clipWeight > 0.001 then
		local t = (os.clock() - actor.clipStart) * actor.clipSpeed
		pose = sample(clip, t)
		-- Zdarzenia (np. „pop” przy wyrwaniu grzyba) odpalają się raz
		if clip.events and actor.clipEvents then
			for i, ev in clip.events do
				local passed = if clip.loop then (t % clip.length) >= ev.t and not actor.clipFired[i] else t >= ev.t and not actor.clipFired[i]
				if passed then
					actor.clipFired[i] = true
					task.spawn(actor.clipEvents, ev.name)
				end
				if clip.loop and (t % clip.length) < ev.t then
					actor.clipFired[i] = false
				end
			end
		end
	elseif actor.clipTarget == 0 and actor.clipWeight <= 0.001 then
		actor.clip = nil
	end
	local tremble = 0
	if actor.shake > 0.001 then
		tremble = math.noise(os.clock() * 30, 2.7) * 7 * actor.shake
	end
	for name, motor in actor.motors do
		-- Animator co klatkę zapisuje Transform; jeśli od naszego zapisu nic się nie zmieniło, żadna animacja
		-- nie rusza tego stawu i podstawą jest spoczynek (inaczej poza by się nakładała sama na siebie)
		local base: CFrame = motor.Transform
		local written = actor.written[name]
		if written and base == written then
			base = CFrame.new()
		end
		local out = base
		if pose then
			local target = pose[name]
			if target then
				out = base:Lerp(target, actor.clipWeight)
			end
		end
		if tremble ~= 0 and (name == "Waist" or name == "Neck" or name == "RightShoulder" or name == "LeftShoulder") then
			out = out * CFrame.Angles(math.rad(tremble), math.rad(tremble * 0.5), 0)
		end
		if out ~= base or written then
			motor.Transform = out
			actor.written[name] = out
		end
	end
end

-- ===== Początek i koniec sceny =====

local function setFrozen(frozen: boolean)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.Anchored = frozen
	end
	local module = player:FindFirstChild("PlayerScripts") and (player :: any).PlayerScripts:FindFirstChild("PlayerModule")
	if module then
		pcall(function()
			local controls = (require(module :: ModuleScript) :: any):GetControls()
			if frozen then
				controls:Disable()
			else
				controls:Enable()
			end
		end)
	end
end

local function hideCharacter(hidden: boolean)
	local character = player.Character
	if not character then
		return
	end
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			(d :: any).LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

function Kit.begin(sounds: { string }?): Scene
	local s: Scene = {
		cancelled = false,
		finished = false,
		gui = nil :: any,
		fade = nil :: any,
		bars = {},
		caption = nil :: any,
		subtitle = nil :: any,
		skip = nil :: any,
		camera = Instance.new("CFrameValue"),
		fov = Instance.new("NumberValue"),
		cameraFn = nil,
		shake = 0,
		actors = {},
		connections = {},
		cleanups = {},
		loops = {},
		hiddenGuis = {},
		saved = {},
		onFinish = nil,
		phase = "",
		phaseStart = os.clock(),
	}
	s.fov.Value = 70
	current = s
	buildGui(s)
	if sounds then
		Audio.preload(sounds)
	end
	-- Światło sceny zmienia się dowolnie, a na końcu wszystko wraca
	Kit.save(s, Lighting, { "ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "ExposureCompensation", "FogEnd", "FogColor" })
	Kit.save(s, Lighting:FindFirstChildOfClass("Atmosphere"), { "Density", "Color", "Haze", "Decay", "Glare" })
	Kit.save(s, Lighting:FindFirstChildOfClass("ColorCorrectionEffect"), { "TintColor", "Saturation", "Contrast", "Brightness" })
	Atmosphere.setPaused(true)
	for _, g in player.PlayerGui:GetChildren() do
		if g:IsA("ScreenGui") and g ~= s.gui and g.Enabled then
			g.Enabled = false
			table.insert(s.hiddenGuis, g)
		end
	end
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
	end)
	hideCharacter(true)
	setFrozen(true)

	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	table.insert(s.connections, RunService.RenderStepped:Connect(function(dt)
		local cam = Workspace.CurrentCamera
		if not cam then
			return
		end
		local offset = CFrame.new()
		if s.shake > 0.01 then
			local t = os.clock() * 30
			offset = CFrame.Angles(math.noise(t, 1) * 0.04 * s.shake, math.noise(t, 2) * 0.04 * s.shake, math.noise(t, 3) * 0.03 * s.shake)
			s.shake = math.max(0, s.shake - dt * 0.4)
		end
		cam.CameraType = Enum.CameraType.Scriptable
		local base = if s.cameraFn then s.cameraFn() else s.camera.Value
		cam.CFrame = base * offset
		cam.FieldOfView = s.fov.Value
		-- Inne moduły potrafią w trakcie włączyć swój interfejs (np. panel DEV przy każdej aktualizacji stanu)
		for _, g in player.PlayerGui:GetChildren() do
			if g:IsA("ScreenGui") and g ~= s.gui and g.Enabled and g.Name ~= "Cutscene" then
				g.Enabled = false
				if not table.find(s.hiddenGuis, g) then
					table.insert(s.hiddenGuis, g)
				end
			end
		end
		for _, actor in s.actors do
			if not actor.freeRoot and actor.root.Parent then
				actor.root.CFrame = actor.rootValue.Value
			end
		end
	end))
	table.insert(s.connections, RunService.Stepped:Connect(function(_, dt)
		for _, actor in s.actors do
			poseActor(actor, dt)
		end
	end))

	task.delay(1.5, function()
		if current == s and not s.cancelled then
			s.skip.Visible = true
			tween(s.skip, 0.4, { Position = UDim2.new(1, -24, 1, -24) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		end
	end)
	s.skip.Activated:Connect(function()
		Audio.play("click")
		Kit.finish(s)
	end)
	return s
end

-- Sprzątanie: wszystko wraca jak przed sceną. Wołane na końcu i przy „Pomiń”.
function Kit.finish(s: Scene)
	if s.finished then
		return
	end
	s.finished = true
	s.cancelled = true
	if current == s then
		current = nil
	end
	for _, c in s.connections do
		c:Disconnect()
	end
	Kit.stopLoops(s, 0.6)
	for _, fn in s.cleanups do
		pcall(fn)
	end
	for _, actor in s.actors do
		for _, track in actor.tracks do
			track:Stop(0)
		end
		actor.model:Destroy()
	end
	for object, props in s.saved do
		for name, value in props do
			pcall(function()
				(object :: any)[name] = value
			end)
		end
	end
	Atmosphere.setPaused(false)
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = 70
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
	for _, g in s.hiddenGuis do
		g.Enabled = true
	end
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
	end)
	hideCharacter(false)
	setFrozen(false)
	tween(s.fade, 0.8, { BackgroundTransparency = 1 })
	for _, bar in s.bars do
		tween(bar, 0.5, { Size = UDim2.new(1, 0, 0, 0) })
	end
	s.skip.Visible = false
	s.subtitle.Visible = false
	s.caption.Visible = false
	task.delay(1, function()
		s.gui:Destroy()
	end)
	local done = s.onFinish
	if done then
		task.spawn(done)
	end
end

-- Uruchamia scenariusz w osobnym wątku; po końcu (albo „Pomiń”) woła onDone
function Kit.run(s: Scene, script: (Scene) -> (), onDone: (() -> ())?)
	s.onFinish = onDone
	task.spawn(function()
		local ok, err = pcall(script, s)
		if not ok then
			warn("[Cutscene] " .. tostring(err))
		end
		Kit.finish(s)
	end)
end

-- Wczytuje modele/tekstury z wyprzedzeniem (np. świat snu), bez czekania
function Kit.preloadInstances(list: { Instance })
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
	end)
end

return Kit
