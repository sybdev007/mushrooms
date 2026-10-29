--!strict
-- Cutscenka na start gry (tylko przy pierwszym wejściu): zły sen w lesie.
--   1. Noc w lesie ze snu (osobny las, daleko od chatki). Gracz idzie ścieżką z latarnią, u góry pasek oleju.
--   2. Zauważa grzyba, przyklęka, wyrywa go, ogląda z bliska i wrzuca przez ramię do plecaka.
--   3. Między drzewami lśni tęczowy grzyb. Olej się kończy, latarnia zaczyna migać.
--   4. Gracz szarpie mitycznego grzyba trzy razy, ten w końcu puszcza, gracz ląduje na tyłku i unosi go nad głowę.
--   5. Latarnia: gracz podnosi ją do twarzy, potrząsa, płomień się krztusi i gaśnie. Ciemność, szepty.
--   6. W ciemności zapalają się czerwone oczy. Światło czerwienieje, Leszy się prostuje i ryczy.
--   7. Pościg ścieżką (kamera jedzie przed gracza), Leszy dudni za nim i dogania.
--   8. Rzut, ryk i natychmiastowa czerń. Cisza.
--   9. Poranek: gracz budzi się na bujanym fotelu na ganku: „Uff… to był tylko zły sen.” „Muszę pilnować oleju!”
--  10. Kamera pokazuje grzyba przy ścieżce: „Ooo… ale fajny grzyb!” i zaczyna się samouczek.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local LeszyRig = require(ReplicatedStorage.Shared.LeszyRig)
local Audio = require(script.Parent.Audio)
local Clips = require(script.Parent.CutsceneClips)
local DreamForest = require(script.Parent.DreamForest)
local Kit = require(script.Parent.CutsceneKit)
local Localize = require(script.Parent.Localize)
local MushroomView = require(script.Parent.MushroomView)
local UiKit = require(script.Parent.UiKit)

local IntroCutscene = {}

local TITLE_FONT = Enum.Font.FredokaOne
local OUTLINE = UiKit.OUTLINE

local at = DreamForest.at
local look = Kit.look
local tween = Kit.tween

local SOUNDS = {
	"dream", "eerie", "chase", "wake", "forest", "birds", "footstep", "pick", "shimmer", "rumble", "roar",
	"heartbeat", "sting", "gasp", "creak", "bubble", "whoosh", "blip", "ping", "warn", "boom", "flame", "tink",
	"whisper", "breath", "crack", "owl", "pant", "swell", "leaves",
}

local playing = false

function IntroCutscene.isPlaying(): boolean
	return playing
end

-- ===== Światło =====

local function setLight(preset: string, time: number)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	local color = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	local props: { [string]: any }
	local fog: { [string]: any }
	local tint: { [string]: any }
	if preset == "night" then
		-- Księżycowa noc: ciemno, ale postać, ścieżkę i drzewa dobrze widać
		props = { ClockTime = 0.2, Brightness = 1.7, Ambient = Color3.fromRGB(70, 78, 120), OutdoorAmbient = Color3.fromRGB(88, 96, 142) }
		fog = { Density = 0.34, Color = Color3.fromRGB(40, 48, 92), Haze = 1.2 }
		tint = { TintColor = Color3.fromRGB(198, 212, 255), Saturation = -0.1, Contrast = 0.14, Brightness = 0.02 }
	elseif preset == "dark" then
		-- Latarnia zgasła: prawie czarno, tylko zarysy
		props = { ClockTime = 0, Brightness = 0.2, Ambient = Color3.fromRGB(16, 16, 26), OutdoorAmbient = Color3.fromRGB(18, 18, 30) }
		fog = { Density = 0.55, Color = Color3.fromRGB(6, 6, 12), Haze = 0.4 }
		tint = { TintColor = Color3.fromRGB(170, 180, 255), Saturation = -0.4, Contrast = 0.25, Brightness = -0.06 }
	elseif preset == "danger" then
		props = { ClockTime = 0.2, Brightness = 1.1, Ambient = Color3.fromRGB(104, 30, 36), OutdoorAmbient = Color3.fromRGB(126, 36, 44) }
		fog = { Density = 0.42, Color = Color3.fromRGB(84, 14, 22), Haze = 1.5 }
		tint = { TintColor = Color3.fromRGB(255, 166, 166), Saturation = -0.05, Contrast = 0.28, Brightness = -0.03 }
	else -- poranek przy chatce
		props = { ClockTime = 7.3, Brightness = 1.3, Ambient = Color3.fromRGB(96, 84, 76), OutdoorAmbient = Color3.fromRGB(128, 112, 96) }
		fog = { Density = 0.26, Color = Color3.fromRGB(255, 214, 170), Haze = 0.6 }
		tint = { TintColor = Color3.fromRGB(255, 240, 220), Saturation = 0.08, Contrast = 0.05, Brightness = 0.02 }
	end
	local function apply(object: Instance?, values: { [string]: any })
		if not object then
			return
		end
		if time <= 0 then
			for k, v in values do
				(object :: any)[k] = v
			end
		else
			tween(object, time, values)
		end
	end
	apply(Lighting, props)
	apply(atmosphere, fog)
	apply(color, tint)
end

-- ===== Rekwizyty =====

-- Grzyb do ręki: klocki jak w świecie (kapelusz z warstw, nóżka). Pivot w miejscu chwytu (dół nóżki).
local function heldMushroom(mythic: boolean): Model
	local model = Instance.new("Model")
	model.Name = "HeldMushroom"
	local scale = if mythic then 1.2 else 1
	local function block(size: Vector3, y: number, color: Color3, neon: boolean, x: number?, z: number?): Part
		local p = Instance.new("Part")
		p.Size = size * scale
		p.CFrame = CFrame.new((x or 0) * scale, y * scale, (z or 0) * scale)
		p.Color = color
		p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Parent = model
		return p
	end
	local stem = block(Vector3.new(0.34, 0.7, 0.34), 0.35, Color3.fromRGB(238, 228, 204), false)
	local cap = block(Vector3.new(1.0, 0.3, 1.0), 0.82, if mythic then Color3.fromRGB(255, 120, 210) else Color3.fromRGB(240, 170, 40), mythic)
	block(Vector3.new(0.7, 0.22, 0.7), 1.06, if mythic then Color3.fromRGB(255, 200, 240) else Color3.fromRGB(214, 140, 30), mythic)
	if mythic then
		for _, d in { { 0.32, 0.2 }, { -0.28, -0.22 }, { 0.05, -0.36 } } do
			block(Vector3.new(0.16, 0.06, 0.16), 0.99, Color3.new(1, 1, 1), true, d[1], d[2])
		end
		local light = Instance.new("PointLight")
		light.Name = "Glow"
		light.Range = 14
		light.Brightness = 3
		light.Parent = cap
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Name = "Sparkles"
		sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkles.Rate = 24
		sparkles.Lifetime = NumberRange.new(0.5, 1)
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
	-- Pivot w dole nóżki (bez PrimaryPart, inaczej Roblox liczyłby pivot od środka nóżki)
	model.WorldPivot = CFrame.new(0, 0, 0)
	local _ = stem
	return model
end

-- Grudki ziemi i iskierki w miejscu zerwania
local function burstAt(where: Vector3, color: Color3, count: number)
	local holder = Instance.new("Attachment")
	holder.WorldPosition = where
	holder.Parent = Workspace.Terrain
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Rate = 0
	sparks.Lifetime = NumberRange.new(0.4, 0.9)
	sparks.Speed = NumberRange.new(3, 7)
	sparks.SpreadAngle = Vector2.new(70, 70)
	sparks.EmissionDirection = Enum.NormalId.Top
	sparks.Acceleration = Vector3.new(0, -10, 0)
	sparks.Size = NumberSequence.new(0.4, 0)
	sparks.LightEmission = 1
	sparks.Color = ColorSequence.new(color)
	sparks.Parent = holder
	sparks:Emit(count)
	local dirt = Instance.new("ParticleEmitter")
	dirt.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dirt.Rate = 0
	dirt.Lifetime = NumberRange.new(0.3, 0.6)
	dirt.Speed = NumberRange.new(2, 4)
	dirt.SpreadAngle = Vector2.new(60, 60)
	dirt.EmissionDirection = Enum.NormalId.Top
	dirt.Acceleration = Vector3.new(0, -14, 0)
	dirt.Size = NumberSequence.new(0.5, 0.1)
	dirt.Color = ColorSequence.new(Color3.fromRGB(92, 64, 40))
	dirt.Parent = holder
	dirt:Emit(math.ceil(count * 0.6))
	task.delay(1.5, function()
		holder:Destroy()
	end)
end

-- ===== Magia polany: mityczny grzyb =====
-- Zamiast kanciastego słupa: miękka tęczowa poświata, iskry płynące w górę, migotki wokół kapelusza,
-- świetliki z warkoczami krążące po spirali i pulsujące światło jak bicie serca.

type Glade = { folder: Folder, intensity: NumberValue, emitters: { ParticleEmitter }, burst: (number) -> () }

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 110, 130)),
	ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 110)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(120, 255, 170)),
	ColorSequenceKeypoint.new(0.75, Color3.fromRGB(110, 200, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 130, 255)),
})

local function gladeMagic(s: Kit.Scene, center: Vector3): Glade
	local folder = Instance.new("Folder")
	folder.Name = "GladeMagic"
	folder.Parent = Workspace
	Kit.onCleanup(s, function()
		folder:Destroy()
	end)
	local intensity = Instance.new("NumberValue")
	intensity.Value = 1
	local function anchor(name: string, size: Vector3, cf: CFrame): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Transparency = 1
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = folder
		return p
	end
	local emitters: { ParticleEmitter } = {}
	local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
		local e = Instance.new("ParticleEmitter")
		e.LightEmission = 1
		e.LightInfluence = 0
		for k, v in props do
			(e :: any)[k] = v
		end
		e:SetAttribute("BaseRate", e.Rate)
		e.Parent = parent
		table.insert(emitters, e)
		return e
	end

	-- Poświata: miękkie, wolno obracające się obłoki światła wokół kapelusza
	local core = anchor("Core", Vector3.new(1, 1, 1), CFrame.new(center + Vector3.new(0, 1.6, 0)))
	emitter(core, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = RAINBOW,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(0.5, 6), NumberSequenceKeypoint.new(1, 7.5) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.86), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(2.4, 3.2),
		Rate = 4,
		Speed = NumberRange.new(0.1, 0.3),
		RotSpeed = NumberRange.new(-25, 25),
		Rotation = NumberRange.new(0, 360),
		SpreadAngle = Vector2.new(180, 180),
	})
	-- Migotki: małe gwiazdki zapalające się wokół kapelusza
	emitter(core, {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = RAINBOW,
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 0.45), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new(0.1, 1),
		Lifetime = NumberRange.new(0.5, 1.1),
		Rate = 22,
		Speed = NumberRange.new(0, 0.4),
		RotSpeed = NumberRange.new(-180, 180),
		Rotation = NumberRange.new(0, 360),
	})
	core.Size = Vector3.new(5, 3, 5)
	-- Iskry płynące z ziemi w górę (z koła wokół grzyba)
	local ground = anchor("Ground", Vector3.new(7, 0.2, 7), CFrame.new(center + Vector3.new(0, 0.15, 0)))
	emitter(ground, {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = RAINBOW,
		Shape = Enum.ParticleEmitterShape.Disc,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		EmissionDirection = Enum.NormalId.Top,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, 0.28), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(2.5, 4),
		Rate = 26,
		Speed = NumberRange.new(0.8, 2),
		SpreadAngle = Vector2.new(8, 8),
		Acceleration = Vector3.new(0, 0.5, 0),
		RotSpeed = NumberRange.new(-90, 90),
	})
	-- Mgiełka przy ziemi: ledwo widoczny kolorowy opar
	emitter(ground, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(200, 160, 255), Color3.fromRGB(140, 230, 255)),
		Shape = Enum.ParticleEmitterShape.Disc,
		EmissionDirection = Enum.NormalId.Top,
		Size = NumberSequence.new(3, 5),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.88), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(3, 4),
		Rate = 3,
		Speed = NumberRange.new(0.1, 0.3),
		RotSpeed = NumberRange.new(-10, 10),
	})
	-- Światło: tęczowe i pulsujące jak bicie serca
	local light = Instance.new("PointLight")
	light.Range = 20
	light.Brightness = 2.5
	light.Shadows = false
	light.Parent = core

	-- Świetliki z warkoczami po spiralach
	type Wisp = { part: Part, trail: Trail, radius: number, height: number, speed: number, phase: number, bob: number }
	local wisps: { Wisp } = {}
	for i = 1, 6 do
		local p = anchor("Wisp", Vector3.new(0.22, 0.22, 0.22), CFrame.new(center))
		p.Shape = Enum.PartType.Ball
		p.Material = Enum.Material.Neon
		p.Transparency = 0.05
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.11, 0)
		a0.Parent = p
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.11, 0)
		a1.Parent = p
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 0.9
		trail.FaceCamera = true
		trail.LightEmission = 1
		trail.LightInfluence = 0
		trail.MinLength = 0.02
		trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
		trail.Parent = p
		table.insert(wisps, {
			part = p,
			trail = trail,
			radius = 1.6 + (i % 3) * 0.7,
			height = 0.8 + (i % 4) * 0.55,
			speed = (if i % 2 == 0 then 1 else -1) * (1.1 + i * 0.12),
			phase = i * math.pi * 2 / 6,
			bob = 0.4 + (i % 2) * 0.3,
		})
	end
	local t0 = os.clock()
	table.insert(s.connections, RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		local k = intensity.Value
		for i, w in wisps do
			local a = t * w.speed + w.phase
			local r = w.radius * (0.8 + 0.2 * math.sin(t * 0.9 + i))
			local y = w.height + math.sin(t * 1.7 + i) * w.bob
			w.part.CFrame = CFrame.new(center + Vector3.new(math.cos(a) * r, y, math.sin(a) * r))
			local c = Color3.fromHSV((t * 0.18 + i / #wisps) % 1, 0.55, 1)
			w.part.Color = c
			w.trail.Color = ColorSequence.new(c)
			w.part.Transparency = 1 - k * 0.95
			w.trail.Enabled = k > 0.05
		end
		-- Bicie serca: dwa szybkie uderzenia, przerwa
		local beat = t % 1.6
		local pulse = math.exp(-((beat - 0.1) ^ 2) * 160) + 0.6 * math.exp(-((beat - 0.38) ^ 2) * 160)
		light.Color = Color3.fromHSV((t * 0.12) % 1, 0.5, 1)
		light.Brightness = (2 + pulse * 3.5) * k
		light.Range = 16 + pulse * 6
		for _, e in emitters do
			e.Rate = ((e:GetAttribute("BaseRate") :: number?) or 0) * k
		end
	end))
	local function burst(count: number)
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = RAINBOW
		e.LightEmission = 1
		e.LightInfluence = 0
		e.Shape = Enum.ParticleEmitterShape.Sphere
		e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new(0, 1)
		e.Lifetime = NumberRange.new(0.8, 1.6)
		e.Speed = NumberRange.new(6, 14)
		e.Drag = 3
		e.Acceleration = Vector3.new(0, 2, 0)
		e.RotSpeed = NumberRange.new(-200, 200)
		e.Rate = 0
		e.Parent = core
		e:Emit(count)
		local glow = Instance.new("ParticleEmitter")
		glow.Texture = "rbxasset://textures/particles/smoke_main.dds"
		glow.Color = RAINBOW
		glow.LightEmission = 1
		glow.Size = NumberSequence.new(2, 14)
		glow.Transparency = NumberSequence.new(0.5, 1)
		glow.Lifetime = NumberRange.new(0.7, 0.9)
		glow.Speed = NumberRange.new(0, 0)
		glow.Rate = 0
		glow.Parent = core
		glow:Emit(3)
	end
	return { folder = folder, intensity = intensity, emitters = emitters, burst = burst }
end

-- ===== Leszy =====

type LeszyState = { model: Model?, rig: LeszyRig.Rig?, cf: CFrameValue, anim: string, at: number, phase: number, lastSin: number, rise: number }

local function makeLeszy(s: Kit.Scene, where: CFrame): LeszyState
	local state: LeszyState = { model = nil, rig = nil, cf = Instance.new("CFrameValue"), anim = "crouch", at = os.clock(), phase = 0, lastSin = 0, rise = 1 }
	state.cf.Value = where
	local folder = ReplicatedStorage:FindFirstChild("CutsceneProps")
	local proto = folder and folder:FindFirstChild("Leszy")
	if not proto or not proto:IsA("Model") then
		return state
	end
	local leszy = proto:Clone()
	leszy:SetAttribute("Scripted", true) -- ten egzemplarz animuje scena, nie LeszyAnimator
	leszy:PivotTo(where)
	leszy.Parent = Workspace
	state.model = leszy
	state.rig = LeszyRig.new(leszy)
	Kit.onCleanup(s, function()
		if state.rig then
			LeszyRig.destroy(state.rig)
		end
		leszy:Destroy()
	end)
	-- Poza co klatkę: skulony / wstaje / ryczy / biegnie / rzuca się
	table.insert(s.connections, RunService.RenderStepped:Connect(function(dt)
		local rig = state.rig
		if not rig or not leszy.Parent then
			return
		end
		local now = os.clock()
		local age = now - state.at
		local speed = if state.anim == "run" or state.anim == "lunge" then 1 else 0
		state.phase += dt * (1.2 + speed * 7.4)
		local pose, hips = LeszyRig.gait(now, state.phase, speed)
		if state.anim == "crouch" or state.anim == "rise" then
			if state.anim == "rise" then
				state.rise = math.max(0, 1 - age / 1.7)
			end
			local k = state.rise * state.rise * (3 - 2 * state.rise)
			local p2, h2 = LeszyRig.crouch(1, now)
			pose, hips = LeszyRig.mix(pose, hips, p2, h2, k)
		elseif state.anim == "roar" then
			local p2, h2 = LeszyRig.roar(1, now)
			pose, hips = LeszyRig.mix(pose, hips, p2, h2, math.clamp(age / 0.3, 0, 1))
		elseif state.anim == "lunge" then
			local p2, h2 = LeszyRig.lunge(1)
			pose, hips = LeszyRig.mix(pose, hips, p2, h2, math.clamp(age / 0.3, 0, 1))
		end
		LeszyRig.apply(rig, state.cf.Value, pose, hips)
		if speed > 0 then
			local sn = math.sin(state.phase)
			if (sn > 0) ~= (state.lastSin > 0) then
				Audio.play("footstep", { volume = 1.4, pitch = 0.42, jitter = 0.06 })
				s.shake = math.max(s.shake, 0.25)
			end
			state.lastSin = sn
		end
	end))
	return state
end

local function leszyDo(state: LeszyState, anim: string)
	state.anim = anim
	state.at = os.clock()
end

local function leszyEyes(state: LeszyState, awake: boolean, time: number)
	local leszy = state.model
	if not leszy then
		return
	end
	for _, p in leszy:GetChildren() do
		if p.Name == "Eye" and p:IsA("BasePart") then
			if time <= 0 then
				p.Color = if awake then Color3.fromRGB(255, 40, 30) else Color3.fromRGB(30, 8, 8)
			else
				tween(p, time, { Color = if awake then Color3.fromRGB(255, 40, 30) else Color3.fromRGB(30, 8, 8) })
			end
		elseif p.Name == "Heart" and p:IsA("BasePart") then
			p.Color = if awake then Color3.fromRGB(120, 255, 150) else Color3.fromRGB(20, 40, 26)
			local glow = p:FindFirstChild("HeartLight")
			if glow and glow:IsA("PointLight") then
				glow.Brightness = if awake then 2.4 else 0
			end
		end
	end
	local head = leszy:FindFirstChild("Head")
	local light = head and head:FindFirstChild("EyeLight")
	if light and light:IsA("PointLight") then
		if time <= 0 then
			light.Brightness = if awake then 2.6 else 0
		else
			tween(light, time, { Brightness = if awake then 2.6 else 0, Range = 16 })
		end
	end
end

-- ===== Latarnia klona =====
-- Światło przenosimy na szybkę latarni w dłoni (miga razem z nią, gdy gracz ją podnosi)

type Lantern = { light: PointLight?, glass: BasePart?, oil: NumberValue, out: boolean }

local function lanternOf(actor: Kit.Actor): Lantern
	local hand = actor.model:FindFirstChild("HandLantern")
	local glass = hand and hand:FindFirstChild("LanternGlass", true)
	local state: Lantern = { light = nil, glass = if glass and glass:IsA("BasePart") then glass else nil, oil = Instance.new("NumberValue"), out = false }
	local holder: BasePart? = state.glass or (actor.model:FindFirstChild("RightHand") :: BasePart?)
	if holder then
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 196, 120)
		light.Range = 18
		light.Brightness = 2.4
		light.Shadows = true
		light.Parent = holder
		state.light = light
	end
	return state
end

-- Płomień: przy mało oleju realistycznie migocze (szum + nagłe przygaśnięcia), przy zerze gaśnie
local function updateLantern(lantern: Lantern)
	local oil = lantern.oil.Value
	local now = os.clock()
	local strength: number
	if lantern.out or oil <= 0.001 then
		strength = 0
	elseif oil < 0.3 then
		local low = oil / 0.3
		local flicker = 0.55 + 0.45 * math.noise(now * 9, 1.3)
		local dip = if math.noise(now * 3.1, 7.7) > 0.25 then 0.25 else 1 -- nagłe przygaśnięcia
		strength = math.clamp((0.3 + 0.7 * low) * flicker * dip + 0.05, 0, 1)
	else
		strength = 0.92 + 0.08 * math.noise(now * 5, 2.2)
	end
	if lantern.light then
		lantern.light.Brightness = 2.4 * strength
		lantern.light.Range = 8 + 10 * strength
	end
	if lantern.glass then
		lantern.glass.Color = Color3.fromRGB(36, 24, 16):Lerp(Color3.fromRGB(255, 206, 120), strength)
	end
end

-- ===== Pasek oleju na ekranie =====

local function oilGauge(s: Kit.Scene): (Frame, Frame)
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
	return frame, fill
end

-- ===== Scenariusz =====

local SMALL = at(28, 2.4)
local SMALL_STAND = at(26.1, 1.0)
local MYTHIC = at(DreamForest.GLADE_Z, 0)
local MYTHIC_STAND = at(DreamForest.GLADE_Z - 2.1, 0)
local LESZY_AT = at(86, 1)
local RUN_TO = at(22)

-- Grzyb wylatuje z dłoni łukiem do plecaka, maleje i znika z „pyk”
local function tossToBackpack(hero: Kit.Actor, m: Model)
	local start = m:GetPivot()
	for _, d in m:GetDescendants() do
		if d:IsA("WeldConstraint") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	local torso = hero.model:FindFirstChild("UpperTorso") :: BasePart?
	local t0 = os.clock()
	local arc: RBXScriptConnection? = nil
	arc = RunService.RenderStepped:Connect(function()
		local k = math.clamp((os.clock() - t0) / 0.45, 0, 1)
		local goal = if torso then (torso.CFrame * CFrame.new(0, 0.3, 0.9)).Position else start.Position
		local p = start.Position:Lerp(goal, k) + Vector3.new(0, math.sin(k * math.pi) * 2.2, 0)
		m:PivotTo(CFrame.new(p) * CFrame.Angles(k * 9, k * 4, 0))
		m:ScaleTo(math.max(0.05, 1 - k * 0.8))
		if k >= 1 then
			if arc then
				arc:Disconnect()
			end
			m:Destroy()
			Audio.play("blip", { volume = 0.7, pitch = 1.5 })
			burstAt(goal, Color3.fromRGB(255, 240, 180), 8)
		end
	end)
end

local function dream(s: Kit.Scene)
	-- Świat snu i aktor
	local forest = DreamForest.build()
	Kit.onCleanup(s, function()
		forest:Destroy()
	end)
	local hero = Kit.actor(s, { name = "DreamPlayer", keepLantern = true })
	if not hero then
		return
	end
	local lantern = lanternOf(hero)
	local gauge, fill = oilGauge(s)
	table.insert(s.connections, RunService.RenderStepped:Connect(function()
		updateLantern(lantern)
		local oil = lantern.oil.Value
		fill.Size = UDim2.fromScale(math.clamp(oil, 0, 1), 1)
		local low = oil < 0.25
		local flash = if low then 0.5 + 0.5 * math.sin(os.clock() * 12) else 0
		fill.BackgroundColor3 = Color3.fromRGB(255, 170, 56):Lerp(Color3.fromRGB(255, 50, 40), if low then 0.6 + 0.4 * flash else 0)
		gauge.Rotation = if low then math.sin(os.clock() * 40) * 1.5 * flash else 0
	end))
	MushroomView.setViewer(at(40))
	MushroomView.add({
		{ id = "cut_small", position = SMALL, species = "chanterelle" },
		{ id = "cut_mythic", position = MYTHIC, species = "glowing_agaric", variant = "rainbow" },
	})
	Kit.onCleanup(s, function()
		MushroomView.remove("cut_small")
		MushroomView.remove("cut_mythic")
		MushroomView.setViewer(nil)
	end)
	local glade = gladeMagic(s, MYTHIC)
	setLight("night", 0)
	Kit.place(hero, at(2, 0.3), Vector3.new(0, 0, 1))
	Kit.letterbox(s, true, 0.01)
	Kit.loop(s, "forest", 0.8)
	Audio.music("dream", 2)
	Kit.caption(s, Localize.t("CUT_TITLE"), true, 1.2)
	if not Kit.wait(s, 2.4) then
		return
	end
	Kit.caption(s, Localize.t("CUT_TITLE"), false, 0.8)
	Kit.fade(s, false, 1.6)

	-- 1. Spacer: kamera zjeżdża z koron drzew za gracza
	Kit.phase(s, "walk")
	Kit.move(hero, SMALL_STAND, 4.6, "walk", 0.95)
	Kit.shot(s, look(at(-8, 12) + Vector3.new(0, 24, 0), at(12) + Vector3.new(0, 2, 0)), look(at(14, 8) + Vector3.new(0, 4.5, 0), at(24) + Vector3.new(0, 2, 0)), 4.8, 55, Enum.EasingStyle.Quad)
	lantern.oil.Value = 0.46
	gauge.Visible = true
	tween(lantern.oil, 9, { Value = 0.27 }, Enum.EasingStyle.Linear)
	local steps = task.spawn(function()
		while not s.cancelled do
			Audio.play("footstep", { volume = 0.45, jitter = 0.12 })
			task.wait(0.42)
		end
	end)
	task.delay(2.2, function()
		if not s.cancelled then
			Audio.play("owl", { volume = 0.5 })
		end
	end)
	if not Kit.wait(s, 1.0) then
		return
	end
	Kit.subtitle(s, Localize.t("CUT_SUB_OIL"))
	if not Kit.wait(s, 3.6) then
		return
	end
	task.cancel(steps)
	Kit.subtitle(s, nil)

	-- 2. Zauważa grzyba
	Kit.phase(s, "notice")
	Kit.track(hero, "idle")
	Kit.face(hero, SMALL, 0.3)
	Kit.mark(s, hero, "!", Color3.fromRGB(255, 220, 80))
	Audio.play("ping", { volume = 0.6 })
	Kit.shot(s, look(SMALL_STAND + Vector3.new(-2.6, 3.4, -3.2), SMALL + Vector3.new(0, 0.8, 0)), look(SMALL_STAND + Vector3.new(-2.2, 3.0, -2.6), SMALL + Vector3.new(0, 0.9, 0)), 1.1, 50)
	if not Kit.wait(s, 1.0) then
		return
	end

	-- 3. Przyklęka i zrywa: kamera nisko z boku
	Kit.phase(s, "pick")
	local held: Model? = nil
	local side = (SMALL - SMALL_STAND).Unit:Cross(Vector3.yAxis)
	local mid = (SMALL + SMALL_STAND) / 2
	Kit.shot(s, look(mid + side * 11 + Vector3.new(0, 3.4, 0), mid + Vector3.new(0, 1.3, 0)), look(mid + side * 9.6 + Vector3.new(0, 3.0, 0), mid + Vector3.new(0, 1.6, 0)), 3.4, 48)
	Kit.clip(hero, Clips.pickKneel, {
		fade = 0.25,
		events = function(name)
			if name == "pop" then
				MushroomView.remove("cut_small")
				local m = heldMushroom(false)
				Kit.attach(hero, "LeftHand", m, CFrame.new(0, -0.5, -0.1))
				held = m
				Audio.play("pick", { jitter = 0.08 })
				burstAt(SMALL + Vector3.new(0, 0.5, 0), Color3.fromRGB(255, 226, 150), 16)
			elseif name == "sniff" then
				Audio.play("bubble", { volume = 0.4, pitch = 1.3 })
			end
		end,
	})
	if not Kit.wait(s, 3.3) then
		return
	end
	-- Rzut przez ramię do plecaka
	Kit.shot(s, look(SMALL_STAND + Vector3.new(4.5, 3.2, 3.5), SMALL_STAND + Vector3.new(0, 2.4, 0)), nil, 0, 50)
	Kit.clip(hero, Clips.toss, {
		fade = 0.1,
		events = function(name)
			if name == "toss" and held then
				local m = held
				held = nil
				tossToBackpack(hero, m)
			end
		end,
	})
	if not Kit.wait(s, 1.1) then
		return
	end
	Kit.clip(hero, nil, { fade = 0.3 })

	-- 4. Tęczowy blask w głębi lasu: gracz idzie za nim, latarnia zaczyna migać
	Kit.phase(s, "glimmer")
	Audio.music("eerie", 1.5)
	Audio.play("shimmer")
	Kit.face(hero, at(44), 0.4)
	Kit.move(hero, at(46, 0.3), 3.4, "walk", 1.0)
	Kit.follow(s, function()
		local p = hero.root.Position
		return look(p + Vector3.new(-2.2, 2.6, -5.5), MYTHIC + Vector3.new(0, 2, 0))
	end, 52)
	steps = task.spawn(function()
		while not s.cancelled do
			Audio.play("footstep", { volume = 0.45, jitter = 0.12 })
			task.wait(0.44)
		end
	end)
	tween(lantern.oil, 5.5, { Value = 0.12 }, Enum.EasingStyle.Linear)
	if not Kit.wait(s, 1.4) then
		return
	end
	Audio.play("warn", { volume = 0.6 })
	Kit.subtitle(s, Localize.t("CUT_SUB_LOW"), Color3.fromRGB(255, 130, 110))
	if not Kit.wait(s, 2.0) then
		return
	end
	-- Przeskok: gracz wchodzi na polanę z tęczowym grzybem
	Kit.subtitle(s, nil)
	Kit.place(hero, at(56, 0.2), Vector3.new(0, 0, 1))
	Kit.move(hero, MYTHIC_STAND, 2.0, "walk", 0.85)
	Kit.shot(s, look(MYTHIC + Vector3.new(6, 2.4, 3), at(58) + Vector3.new(0, 2, 0)), look(MYTHIC + Vector3.new(5.2, 2.2, 2.4), MYTHIC_STAND + Vector3.new(0, 2, 0)), 2.2, 52)
	if not Kit.wait(s, 2.0) then
		return
	end
	task.cancel(steps)
	Kit.track(hero, "idle")

	-- 5. Mityczny grzyb nie chce puścić
	Kit.phase(s, "mythic")
	local heldMythic: Model? = nil
	Kit.shot(s, look(MYTHIC + Vector3.new(-6.5, 2.4, -1.5), MYTHIC + Vector3.new(0, 1.4, -1.2)), look(MYTHIC + Vector3.new(-5.6, 2.2, -1.0), MYTHIC + Vector3.new(0, 1.6, -1.2)), 2.8, 50)
	Kit.clip(hero, Clips.pickMythic, {
		fade = 0.25,
		events = function(name)
			if name == "tug" then
				hero.shake = 1
				task.delay(0.3, function()
					hero.shake = 0
				end)
				Audio.play("crack", { volume = 0.4, pitch = 1.4, duration = 0.5 })
				s.shake = math.max(s.shake, 0.15)
			elseif name == "pop" then
				MushroomView.remove("cut_mythic")
				local m = heldMushroom(true)
				Kit.attach(hero, "LeftHand", m, CFrame.new(0, -0.5, -0.1))
				heldMythic = m
				Audio.play("pick")
				Audio.play("shimmer", { volume = 0.9 })
				Kit.flash(s, Color3.new(1, 1, 1), 0.75, 0.6)
				burstAt(MYTHIC + Vector3.new(0, 0.8, 0), Color3.fromRGB(255, 200, 255), 30)
				glade.burst(90)
				-- Magia polany gaśnie razem z wyrwaniem grzyba (zostaje tylko lekki ślad)
				tween(glade.intensity, 2.5, { Value = 0.12 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				s.shake = 0.4
				-- Po wyrwaniu kamera robi najazd na gracza z grzybem w górze
				Kit.shot(s, look(MYTHIC_STAND + Vector3.new(-3.6, 1.6, 4.2), MYTHIC_STAND + Vector3.new(0, 1.8, 0)), look(MYTHIC_STAND + Vector3.new(-2.6, 1.4, 3.2), MYTHIC_STAND + Vector3.new(0, 2.6, 0)), 2.0, 50)
			end
		end,
	})
	-- Tęczowy kolor grzyba w dłoni
	table.insert(s.connections, RunService.RenderStepped:Connect(function()
		local m = heldMythic
		if m and m.Parent then
			for _, p in m:GetChildren() do
				if p:IsA("BasePart") and p.Material == Enum.Material.Neon and p.Size.X > 0.5 then
					p.Color = Color3.fromHSV((os.clock() * 0.45) % 1, 0.55, 1)
					local glow = p:FindFirstChild("Glow")
					if glow and glow:IsA("PointLight") then
						glow.Color = p.Color
					end
				end
			end
		end
	end))
	if not Kit.wait(s, 4.2) then
		return
	end
	-- Chowa skarb do plecaka (w ciemności świecący grzyb w dłoni zasłaniałby kadr)
	Kit.clip(hero, Clips.toss, {
		fade = 0.15,
		events = function(name)
			if name == "toss" and heldMythic then
				local m = heldMythic
				heldMythic = nil
				tossToBackpack(hero, m)
			end
		end,
	})
	if not Kit.wait(s, 1.1) then
		return
	end

	-- 6. Latarnia gaśnie
	Kit.phase(s, "lantern")
	local flame: Sound? = nil
	Kit.follow(s, function()
		local cf = hero.root.CFrame
		return look((cf * CFrame.new(4.2, 2.0, -7.6)).Position, (cf * CFrame.new(0.3, 1.2, -0.3)).Position)
	end, 46)
	tween(lantern.oil, 3.2, { Value = 0.02 }, Enum.EasingStyle.Linear)
	Kit.clip(hero, Clips.lantern, {
		fade = 0.3,
		events = function(name)
			if name == "tink" then
				Audio.play("tink", { volume = 0.8, jitter = 0.05, duration = 0.7 })
			elseif name == "out" then
				lantern.out = true
				lantern.oil.Value = 0
				if flame then
					Audio.stop(flame, 0.15)
				end
				Audio.play("whoosh", { volume = 0.6, pitch = 0.55 })
				Audio.music(nil, 0.3)
				setLight("dark", 0.4)
				-- Grzyb też przygasa
				local m = heldMythic
				if m then
					for _, d in m:GetDescendants() do
						if d:IsA("PointLight") then
							tween(d, 1.5, { Brightness = 0.25, Range = 5 })
						elseif d:IsA("ParticleEmitter") then
							d.Rate = 3
						end
					end
				end
				Kit.subtitle(s, Localize.t("CUT_SUB_OUT"), Color3.fromRGB(200, 200, 255))
				task.delay(0.9, function()
					if not s.cancelled then
						Audio.play("whisper", { volume = 0.7, duration = 4 })
					end
				end)
			end
		end,
	})
	task.delay(0.9, function()
		if not s.cancelled and not lantern.out then
			flame = Audio.play("flame", { volume = 1.1, duration = 2.6 })
		end
	end)
	if not Kit.wait(s, 5.4) then
		return
	end
	Kit.subtitle(s, nil)

	-- 7. Oczy w ciemności, czerwień, Leszy się prostuje i ryczy
	Kit.phase(s, "eyes")
	local facing = (MYTHIC_STAND - LESZY_AT) * Vector3.new(1, 0, 1)
	local leszy = makeLeszy(s, CFrame.lookAt(LESZY_AT, LESZY_AT + facing.Unit))
	leszyEyes(leszy, false, 0)
	Kit.shot(s, look(MYTHIC_STAND + Vector3.new(-1.6, 3.2, -3.2), LESZY_AT + Vector3.new(0, 6, 0)), look(MYTHIC_STAND + Vector3.new(-1.2, 3.4, -1.6), LESZY_AT + Vector3.new(0, 7, 0)), 3.0, 40)
	Kit.loop(s, "heartbeat", 0.7)
	if not Kit.wait(s, 1.0) then
		return
	end
	Audio.play("swell", { volume = 0.9, duration = 4.5 })
	leszyEyes(leszy, true, 0.5)
	if not Kit.wait(s, 1.6) then
		return
	end
	Kit.subtitle(s, Localize.t("CUT_SUB_LESZY"), Color3.fromRGB(255, 110, 90))
	setLight("danger", 1.4)
	leszyDo(leszy, "rise")
	Audio.play("crack", { volume = 1, duration = 1.6 })
	Audio.play("rumble", { duration = 3 })
	Audio.play("breath", { volume = 0.8, duration = 3 })
	s.shake = 0.5
	Kit.shot(s, look(LESZY_AT + Vector3.new(-9, 2.5, -15), LESZY_AT + Vector3.new(0, 7, 0)), look(LESZY_AT + Vector3.new(-7, 3.5, -13), LESZY_AT + Vector3.new(0, 10, 0)), 1.9, 58)
	if not Kit.wait(s, 1.9) then
		return
	end
	Kit.subtitle(s, nil)
	leszyDo(leszy, "roar")
	Audio.play("roar")
	s.shake = 0.8
	Kit.shot(s, look(LESZY_AT + Vector3.new(-2.4, 12.8, -6.5), LESZY_AT + Vector3.new(0, 13, 0)), look(LESZY_AT + Vector3.new(-5, 6.5, -15), LESZY_AT + Vector3.new(0, 11, 0)), 0.9, 50, Enum.EasingStyle.Quart)
	if not Kit.wait(s, 1.4) then
		return
	end

	-- 8. Pościg: gracz się odwraca i ucieka, kamera jedzie przed nim
	Kit.phase(s, "chase")
	Kit.stopLoops(s, 0.5)
	Kit.loop(s, "heartbeat", 1)
	Kit.loop(s, "pant", 0.6)
	Audio.music("chase", 0.2)
	Kit.face(hero, RUN_TO, 0.2)
	Kit.clip(hero, Clips.recoil, { fade = 0.1 })
	if not Kit.wait(s, 0.45) then
		return
	end
	Kit.clip(hero, nil, { fade = 0.25 })
	Kit.move(hero, RUN_TO, 5.2, "run", 1.3)
	leszy.cf.Value = CFrame.lookAt(LESZY_AT, MYTHIC_STAND)
	leszyDo(leszy, "run")
	tween(leszy.cf, 5.2, { Value = CFrame.lookAt(at(27), RUN_TO) }, Enum.EasingStyle.Linear)
	local runDir = (RUN_TO - MYTHIC_STAND).Unit
	Kit.follow(s, function()
		local p = hero.root.Position
		local ahead = p + runDir * 7.5 + Vector3.new(0, 1.2, 0) + runDir:Cross(Vector3.yAxis) * 1.4
		return look(ahead, p - runDir * 5 + Vector3.new(0, 2.4, 0))
	end, 70)
	local crack = task.spawn(function()
		while not s.cancelled do
			Audio.play("footstep", { volume = 0.8, pitch = 1.2, jitter = 0.1 })
			task.wait(0.26)
		end
	end)
	if not Kit.wait(s, 2.2) then
		return
	end
	-- Przebitka z boku na dudniącego Leszego
	Kit.follow(s, function()
		local p = leszy.cf.Value.Position
		local sideways = runDir:Cross(Vector3.yAxis)
		return look(p + sideways * 13 + Vector3.new(0, 4, 0) + runDir * 2, p + Vector3.new(0, 7, 0))
	end, 60)
	Audio.play("roar", { volume = 0.7, pitch = 1.15, duration = 1.4 })
	if not Kit.wait(s, 1.1) then
		return
	end
	Kit.follow(s, function()
		local p = hero.root.Position
		local ahead = p + runDir * 6 + Vector3.new(0, 1.0, 0)
		return look(ahead, p - runDir * 5 + Vector3.new(0, 3, 0))
	end, 74)
	if not Kit.wait(s, 1.3) then
		return
	end

	-- 9. Złapany: rzut, ryk i natychmiastowa czerń (dźwięki są wczytane, więc grają bez opóźnienia)
	Kit.phase(s, "caught")
	leszyDo(leszy, "lunge")
	local caughtAt = hero.root.Position * Vector3.new(1, 0, 1) + Vector3.new(0, DreamForest.ORIGIN.Y, 0)
	tween(leszy.cf, 0.42, { Value = CFrame.lookAt(caughtAt - runDir * 2.6, caughtAt + runDir * 3) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	Kit.shot(s, look(caughtAt + runDir * 1.2 + Vector3.new(0, 2.8, 0), caughtAt - runDir * 4 + Vector3.new(0, 6, 0)), look(caughtAt + runDir * 0.6 + Vector3.new(0, 2.6, 0), caughtAt - runDir * 2.5 + Vector3.new(0, 7, 0)), 0.42, 88, Enum.EasingStyle.Quad)
	s.shake = 1
	if not Kit.wait(s, 0.3) then
		return
	end
	Audio.play("sting")
	Audio.play("roar", { volume = 1, pitch = 1.15, duration = 1.6 })
	if not Kit.wait(s, 0.12) then
		return
	end
	task.cancel(crack)
	Audio.music(nil, 0.05)
	s.fade.BackgroundTransparency = 0
	s.shake = 0
	gauge.Visible = false
	Kit.stopLoops(s, 1.4)
	if not Kit.wait(s, 2.4) then
		return
	end
	forest:Destroy()
	-- Leszy znika razem ze snem (inaczej jego kroki dalej trzęsą kamerą już na ganku)
	if leszy.model then
		leszy.model.Parent = nil
	end
	leszyDo(leszy, "crouch")
	MushroomView.remove("cut_small")
	MushroomView.remove("cut_mythic")
	for _, actor in s.actors do
		actor.model:Destroy()
	end
	table.clear(s.actors)
end

local function wake(s: Kit.Scene)
	-- 10. Poranek: gracz budzi się na bujanym fotelu na ganku
	Kit.phase(s, "wake")
	s.shake = 0
	setLight("morning", 0)
	local hero = Kit.actor(s, { name = "WakePlayer", keepLantern = true })
	if not hero then
		return
	end
	local chair = Workspace:FindFirstChild("RockingChair", true)
	local pivotAttr = chair and chair:GetAttribute("Pivot")
	local pivot = if typeof(pivotAttr) == "Vector3" then pivotAttr else Vector3.new(9.5, 1, -9.8)
	local seatY = pivot.Y + 1.6
	Kit.track(hero, "sit")
	hero.freeRoot = true
	local seat = CFrame.lookAt(Vector3.new(pivot.X, seatY + 0.9, pivot.Z + 0.1), Vector3.new(pivot.X, seatY + 0.9, pivot.Z + 10))
	local chairBase = if chair and chair:IsA("Model") then chair:GetPivot() else nil
	local rockStart = os.clock()
	table.insert(s.connections, RunService.RenderStepped:Connect(function()
		-- Bujanie: fotel i gracz kołyszą się razem wokół płóz
		local angle = math.rad(5) * math.sin((os.clock() - rockStart) * 1.8)
		local rock = CFrame.new(pivot) * CFrame.Angles(angle, 0, 0) * CFrame.new(-pivot)
		if chair and chair:IsA("Model") and chairBase then
			chair:PivotTo(rock * chairBase)
		end
		hero.root.CFrame = rock * seat
	end))
	Kit.onCleanup(s, function()
		if chair and chair:IsA("Model") and chairBase then
			chair:PivotTo(chairBase)
		end
	end)
	local blur = Instance.new("BlurEffect")
	blur.Name = "CutsceneBlur"
	blur.Size = 28
	blur.Parent = Lighting
	Kit.onCleanup(s, function()
		blur:Destroy()
	end)
	Kit.shot(s, look(Vector3.new(pivot.X - 4, seatY + 3, pivot.Z + 11), Vector3.new(pivot.X, seatY + 1.2, pivot.Z)), look(Vector3.new(pivot.X - 3, seatY + 2.4, pivot.Z + 8.5), Vector3.new(pivot.X, seatY + 1.6, pivot.Z)), 6, 50)
	Kit.loop(s, "birds", 0.7)
	Audio.play("gasp")
	Audio.music("wake", 2.5)
	Kit.fade(s, false, 1.6)
	tween(blur, 2.4, { Size = 0 })
	if not Kit.wait(s, 0.8) then
		return
	end
	-- Mruganie: dwa razy zaciemnienie i jasno
	for _ = 1, 2 do
		tween(s.fade, 0.12, { BackgroundTransparency = 0.2 })
		if not Kit.wait(s, 0.14) then
			return
		end
		tween(s.fade, 0.25, { BackgroundTransparency = 1 })
		if not Kit.wait(s, 0.45) then
			return
		end
	end
	Audio.play("creak", { volume = 0.6, duration = 2.5 })
	if not Kit.bubble(s, hero, Localize.t("CUT_DREAM"), 1.4, true) then
		return
	end
	-- Wniosek ze snu: bez oleju przychodzi Leszy
	if not Kit.bubble(s, hero, Localize.t("CUT_DREAM2"), 1.3, true) then
		return
	end

	-- 11. Kamera do grzyba przy ścieżce: „Ooo… ale fajny grzyb!”
	Kit.phase(s, "nice")
	local first = (Config :: any).Tutorial and (Config :: any).Tutorial.spots and (Config :: any).Tutorial.spots[1]
	local target = if first then Vector3.new(first[1], 0, first[2]) else Vector3.new(2, 0, 48)
	-- Prawdziwe grzyby samouczka pojawią się dopiero po scence, więc tu stoi jego sobowtór
	MushroomView.add({ { id = "cut_nice", position = target, species = Config.Tutorial.species } })
	MushroomView.setViewer(target)
	Kit.onCleanup(s, function()
		MushroomView.remove("cut_nice")
		MushroomView.setViewer(nil)
	end)
	Audio.play("ping")
	Kit.shot(s, look(Vector3.new(pivot.X - 3, seatY + 2.4, pivot.Z + 8.5), target), look(target + Vector3.new(-5, 4.2, -9), target + Vector3.new(0, 1, 0)), 2.2, 45, Enum.EasingStyle.Quart)
	if not Kit.wait(s, 2.3) then
		return
	end
	if not Kit.bubble(s, nil, Localize.t("CUT_NICE"), 1.3, true, UDim2.fromScale(0.25, 0.86)) then
		return
	end
	Kit.fade(s, true, 0.6)
	Kit.wait(s, 0.7)
end

function IntroCutscene.play(onDone: (() -> ())?)
	if playing then
		return
	end
	playing = true
	local s = Kit.begin(SOUNDS)
	-- Po scenie: gracz wstaje z fotela na ganku, przodem do lasu
	Kit.onCleanup(s, function()
		local character = Players.LocalPlayer.Character
		local chair = Workspace:FindFirstChild("RockingChair", true)
		local pivotAttr = chair and chair:GetAttribute("Pivot")
		local pivot = if typeof(pivotAttr) == "Vector3" then pivotAttr else Vector3.new(9.5, 1, -9.8)
		if character then
			local spot = pivot + Vector3.new(-2.5, 3, 2.5)
			character:PivotTo(CFrame.lookAt(spot, spot + Vector3.new(0, 0, 1)))
		end
	end)
	Kit.run(s, function(scene)
		dream(scene)
		if not scene.cancelled then
			wake(scene)
		end
	end, function()
		playing = false
		Audio.music(nil, 2) -- dalej gra playlista lasu
		if onDone then
			onDone()
		end
	end)
end

return IntroCutscene
