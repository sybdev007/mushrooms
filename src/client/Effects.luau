--!strict
-- Dźwięki i efekty: ambient zależny od mroku, świetliki i mgła wokół gracza,
-- wybuch iskierek i „+6” przy zbieraniu, monety, ulepszenia.
-- Wszystko lokalne u gracza, nic nie idzie przez sieć.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Sounds = require(ReplicatedStorage.Shared.Sounds)

local Effects = {}

local PARTICLES_BY_RANK = { 20, 32, 60 } -- iskry przy zbieraniu: Srebro, Złoto, Tęcza

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

-- ===== Dźwięki =====

local soundFolder = Instance.new("Folder")
soundFolder.Name = "GameSounds"
soundFolder.Parent = SoundService

local cache: { [string]: Sound } = {}

local function getSound(name: string): Sound?
	local cached = cache[name]
	if cached then
		return cached
	end
	local def = Sounds[name]
	if not def then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = "rbxassetid://" .. def.id
	sound.Volume = def.volume
	sound.Looped = def.looped == true
	sound.PlaybackSpeed = def.speed or 1
	sound.Parent = soundFolder
	cache[name] = sound
	return sound
end

-- Jednorazowy dźwięk; kopia, żeby kilka mogło grać naraz
function Effects.play(name: string, pitch: number?, volumeScale: number?)
	local base = getSound(name)
	if not base then
		return
	end
	local sound = base:Clone()
	sound.PlaybackSpeed = pitch or 1
	sound.Volume = base.Volume * (volumeScale or 1)
	sound.Parent = soundFolder
	sound:Play()
	Debris:AddItem(sound, 6)
end

local function setLoopVolume(name: string, volume: number)
	local sound = getSound(name)
	if not sound then
		return
	end
	local def = Sounds[name]
	sound.Volume = def.volume * volume
	if volume > 0.01 and not sound.IsPlaying then
		sound:Play()
	elseif volume <= 0.01 and sound.IsPlaying then
		sound:Stop()
	end
end

-- Ambient: świerszcze przy chatce i na skraju, w głębi coraz więcej upiornego wiatru
function Effects.updateAmbient(darkness: number)
	local deep = math.clamp((darkness - 0.3) / 0.7, 0, 1)
	setLoopVolume("ambientEdge", 1 - deep * 0.85)
	setLoopVolume("ambientDeep", deep)
end

-- Bicie serca przy końcu oleju (0 = cisza, 1 = pełna głośność)
function Effects.setHeartbeat(intensity: number)
	setLoopVolume("heartbeat", math.clamp(intensity, 0, 1))
	local sound = cache["heartbeat"]
	if sound then
		sound.PlaybackSpeed = 1 + math.clamp(intensity, 0, 1) * 0.35
	end
end

-- ===== Cząsteczki wokół gracza =====

local function holder(name: string, size: Vector3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = size
	p.Parent = Workspace
	return p
end

local fireflyHolder = holder("FireflyArea", Vector3.new(70, 10, 70))
local mistHolder = holder("MistArea", Vector3.new(80, 1, 80))

local fireflies = Instance.new("ParticleEmitter")
fireflies.Texture = SPARKLE
fireflies.Shape = Enum.ParticleEmitterShape.Box
fireflies.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
fireflies.Color = ColorSequence.new(Color3.fromRGB(220, 255, 120), Color3.fromRGB(255, 220, 90))
fireflies.LightEmission = 1
fireflies.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.15),
	NumberSequenceKeypoint.new(0.5, 0.35),
	NumberSequenceKeypoint.new(1, 0.15),
})
fireflies.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.2, 0.1),
	NumberSequenceKeypoint.new(0.5, 0.6),
	NumberSequenceKeypoint.new(0.75, 0.05),
	NumberSequenceKeypoint.new(1, 1),
})
fireflies.Lifetime = NumberRange.new(4, 7)
fireflies.Speed = NumberRange.new(0.3, 0.9)
fireflies.SpreadAngle = Vector2.new(180, 180)
fireflies.RotSpeed = NumberRange.new(-30, 30)
fireflies.Rate = 0
fireflies.Parent = fireflyHolder

local mist = Instance.new("ParticleEmitter")
mist.Texture = SMOKE
mist.Shape = Enum.ParticleEmitterShape.Box
mist.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
mist.Color = ColorSequence.new(Color3.fromRGB(150, 165, 190))
mist.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.3, 0.82),
	NumberSequenceKeypoint.new(0.7, 0.82),
	NumberSequenceKeypoint.new(1, 1),
})
mist.Size = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 7),
	NumberSequenceKeypoint.new(1, 14),
})
mist.Lifetime = NumberRange.new(7, 10)
mist.Speed = NumberRange.new(0.3, 0.8)
mist.SpreadAngle = Vector2.new(180, 10)
mist.RotSpeed = NumberRange.new(-8, 8)
mist.Rate = 0
mist.Parent = mistHolder

-- Ile świetlików i mgły w której strefie
local FIREFLY_RATE = { 5, 9, 12, 4 }
local MIST_RATE = { 0, 0.5, 2.5, 6 }

function Effects.updateParticles(rootPosition: Vector3, zone: number)
	fireflyHolder.Position = Vector3.new(rootPosition.X, 4, rootPosition.Z + 10)
	mistHolder.Position = Vector3.new(rootPosition.X, 0.6, rootPosition.Z + 8)
	fireflies.Rate = FIREFLY_RATE[zone] or 0
	mist.Rate = MIST_RATE[zone] or 0
end

-- ===== Efekty jednorazowe =====

local function burst(position: Vector3, color: Color3, count: number, speed: number)
	local p = holder("Burst", Vector3.new(0.5, 0.5, 0.5))
	p.Position = position
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLE
	emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	emitter.LightEmission = 0.9
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new(0, 0.6)
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(speed * 0.6, speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 4
	emitter.Acceleration = Vector3.new(0, -6, 0)
	emitter.Rate = 0
	emitter.Parent = p
	emitter:Emit(count)
	Debris:AddItem(p, 1.5)
end

local function floatingText(position: Vector3, text: string, color: Color3)
	local anchor = holder("FloatingText", Vector3.new(0.2, 0.2, 0.2))
	anchor.Position = position
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 120, 0, 50)
	gui.StudsOffset = Vector3.new(0, 1.5, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Color3.fromRGB(40, 24, 10)
	stroke.Parent = label
	local info = TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, info, { StudsOffset = Vector3.new(0, 4.5, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1 }):Play()
	TweenService:Create(stroke, info, { Transparency = 1 }):Play()
	Debris:AddItem(anchor, 1.3)
end

-- rank: 0 zwykły, 1 srebro, 2 złoto, 3 tęcza; icons: ikony mutacji do napisu
function Effects.collect(position: Vector3, color: Color3, value: number, rank: number, icons: string?)
	local top = position + Vector3.new(0, 1.5, 0)
	local particles = if rank > 0 then PARTICLES_BY_RANK[rank] or 14 else 14
	burst(top, color, particles, 8 + rank * 2)
	local textColor = if rank >= 3
		then Color3.fromRGB(255, 150, 230)
		elseif rank == 2 then Color3.fromRGB(255, 214, 70)
		elseif rank == 1 then Color3.fromRGB(220, 232, 250)
		else Color3.fromRGB(255, 244, 220)
	local prefix = if icons and icons ~= "" then icons .. " " else ""
	floatingText(top, prefix .. "+" .. tostring(value), textColor)
	Effects.play("pick", if rank >= 2 then 1.25 else 0.92 + math.random() * 0.2)
	if rank >= 2 then
		Effects.play("upgrade", if rank >= 3 then 1.6 else 1.35)
	end
	if rank >= 3 then
		task.delay(0.15, Effects.play, "upgrade", 1.9, 0.8)
	end
end

-- Złoty pierścień rozchodzący się po podłodze wokół gracza (jak „level up”)
local function shockwave(position: Vector3, color: Color3)
	local ring = Instance.new("Part")
	ring.Name = "UpgradeRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.25
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Size = Vector3.new(0.15, 2, 2)
	-- Walec leży na boku: oś X w górę
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = Workspace
	TweenService:Create(ring, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.15, 16, 16),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 0.8)
end

function Effects.upgrade(rootPosition: Vector3)
	local gold = Color3.fromRGB(255, 210, 110)
	burst(rootPosition + Vector3.new(0, 1, 0), gold, 40, 14)
	shockwave(rootPosition - Vector3.new(0, 2.8, 0), gold)
	Effects.play("upgrade")
end

function Effects.sold()
	Effects.play("coins")
	task.delay(0.12, Effects.play, "coins", 1.15, 0.7)
end

function Effects.engulf()
	Effects.play("engulf")
end

-- Leszy się budzi: niskie, zwolnione szepty lasu
function Effects.leszyWoke()
	Effects.play("engulf", 0.6, 1.3)
	task.delay(0.4, Effects.play, "engulf", 0.45, 1)
end

return Effects
