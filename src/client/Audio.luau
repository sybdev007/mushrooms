--!strict
-- Muzyka i efekty dźwiękowe. Numery dźwięków są w Config.Audio (puste = cisza, gra działa dalej).
--   Audio.music(name, fade?)  – płynnie przełącza muzykę w tle (stara cichnie, nowa narasta)
--   Audio.play(name, options?) – jednorazowy efekt (głośność, wysokość, losowa wysokość, pozycja w świecie)
--   Audio.duck(amount, time)   – na chwilę ścisza muzykę (np. przy ważnym efekcie)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local Audio = {}

type Def = { id: string, volume: number?, looped: boolean? }

local function def(group: string, name: string): Def?
	local audio = (Config :: any).Audio
	local list = audio and audio[group]
	local entry = list and list[name]
	if typeof(entry) == "string" then
		return if entry ~= "" then { id = entry } else nil
	elseif typeof(entry) == "table" and typeof(entry.id) == "string" and entry.id ~= "" then
		return entry :: Def
	end
	return nil
end

local musicGroup = Instance.new("SoundGroup")
musicGroup.Name = "Music"
musicGroup.Volume = 0.5
musicGroup.Parent = SoundService
local sfxGroup = Instance.new("SoundGroup")
sfxGroup.Name = "Effects"
sfxGroup.Volume = 0.8
sfxGroup.Parent = SoundService

local current: Sound? = nil
local currentName: string? = nil

function Audio.music(name: string?, fade: number?)
	if name == currentName then
		return
	end
	local time = fade or 1.5
	local old = current
	if old then
		local out = TweenService:Create(old, TweenInfo.new(time), { Volume = 0 })
		out.Completed:Connect(function()
			old:Destroy()
		end)
		out:Play()
	end
	current = nil
	currentName = name
	local entry = if name then def("music", name) else nil
	if not entry then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "Music_" .. (name :: string)
	sound.SoundId = entry.id
	sound.Looped = entry.looped ~= false
	sound.Volume = 0
	sound.SoundGroup = musicGroup
	sound.Parent = SoundService
	sound:Play()
	TweenService:Create(sound, TweenInfo.new(time), { Volume = entry.volume or 0.6 }):Play()
	current = sound
end

export type PlayOptions = {
	volume: number?,
	pitch: number?,
	jitter: number?, -- losowa zmiana wysokości (np. 0.08 = ±8%), żeby powtarzane dźwięki nie nudziły
	at: Vector3?, -- dźwięk w świecie (cichnie z odległością)
	duration: number?, -- długie nagrania (np. 60 s dudnienia) ucinamy po tylu sekundach, z wyciszeniem
}

function Audio.play(name: string, options: PlayOptions?): Sound?
	local entry = def("sfx", name)
	if not entry then
		return nil
	end
	local opts: PlayOptions = options or {}
	local sound = Instance.new("Sound")
	sound.Name = "Sfx_" .. name
	sound.SoundId = entry.id
	sound.Volume = (opts.volume or 1) * (entry.volume or 0.7)
	local jitter = opts.jitter or 0
	sound.PlaybackSpeed = (opts.pitch or 1) * (1 + (math.random() * 2 - 1) * jitter)
	sound.SoundGroup = sfxGroup
	if opts.at then
		local holder = Instance.new("Attachment")
		holder.WorldPosition = opts.at
		holder.Parent = Workspace.Terrain
		sound.RollOffMaxDistance = 80
		sound.Parent = holder
		sound.Ended:Connect(function()
			holder:Destroy()
		end)
	else
		sound.Parent = SoundService
		sound.Ended:Connect(function()
			sound:Destroy()
		end)
	end
	sound:Play()
	local duration = opts.duration
	if duration then
		task.delay(duration, function()
			if sound.Parent then
				local out = TweenService:Create(sound, TweenInfo.new(0.4), { Volume = 0 })
				out.Completed:Connect(function()
					sound:Destroy()
				end)
				out:Play()
			end
		end)
	end
	return sound
end

-- Pętla efektu (np. bicie serca, szum lasu); zwraca dźwięk, żeby dało się go zatrzymać
function Audio.loop(name: string, volume: number?): Sound?
	local entry = def("sfx", name)
	if not entry then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = "Loop_" .. name
	sound.SoundId = entry.id
	sound.Looped = true
	sound.Volume = (volume or 1) * (entry.volume or 0.7)
	sound.SoundGroup = sfxGroup
	sound.Parent = SoundService
	sound:Play()
	return sound
end

function Audio.stop(sound: Sound?, fade: number?)
	if not sound then
		return
	end
	local out = TweenService:Create(sound, TweenInfo.new(fade or 0.5), { Volume = 0 })
	out.Completed:Connect(function()
		sound:Destroy()
	end)
	out:Play()
end

function Audio.duck(amount: number, time: number)
	TweenService:Create(musicGroup, TweenInfo.new(0.15), { Volume = 0.5 * (1 - amount) }):Play()
	task.delay(time, function()
		TweenService:Create(musicGroup, TweenInfo.new(0.6), { Volume = 0.5 }):Play()
	end)
end

return Audio
