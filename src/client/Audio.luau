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

local MUSIC_VOLUME = 0.5
local SFX_VOLUME = 0.8
-- Suwaki w ustawieniach (SettingsButtons, zapis na serwerze): 0..1, 0 = wyciszone
local musicLevel = 1
local sfxLevel = 1
local musicOn = true
local sfxOn = true

-- Grupy dźwięków (Effects.luau też wkłada swoje dźwięki do grupy „Effects”, żeby wyciszanie działało)
local function group(name: string, volume: number): SoundGroup
	local existing = SoundService:FindFirstChild(name)
	if existing and existing:IsA("SoundGroup") then
		return existing
	end
	local created = Instance.new("SoundGroup")
	created.Name = name
	created.Volume = volume
	created.Parent = SoundService
	return created
end
local musicGroup = group("Music", MUSIC_VOLUME)
local sfxGroup = group("Effects", SFX_VOLUME)

-- Głośność z suwaków (SettingsButtons); zapisuje się na serwerze
function Audio.setMusicLevel(level: number)
	musicLevel = math.clamp(level, 0, 1)
	musicOn = musicLevel > 0
	musicGroup.Volume = MUSIC_VOLUME * musicLevel
end

function Audio.setSfxLevel(level: number)
	sfxLevel = math.clamp(level, 0, 1)
	sfxOn = sfxLevel > 0
	sfxGroup.Volume = SFX_VOLUME * sfxLevel
	-- Dźwięki z Effects.luau (ambient, zbieranie, monety) mają swoją grupę o pełnej głośności
	group("GameSoundsGroup", 1).Volume = sfxLevel
end

function Audio.getMusicLevel(): number
	return musicLevel
end

function Audio.getSfxLevel(): number
	return sfxLevel
end

-- Wł./wył. (dawne przełączniki): włączenie przywraca pełną głośność
function Audio.setMusicOn(on: boolean)
	Audio.setMusicLevel(if on then 1 else 0)
end

function Audio.setSfxOn(on: boolean)
	Audio.setSfxLevel(if on then 1 else 0)
end

function Audio.isMusicOn(): boolean
	return musicOn
end

function Audio.isSfxOn(): boolean
	return sfxOn
end

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

-- Wczytuje dźwięki z wyprzedzeniem (np. przed cutscenką), żeby grały od razu, bez opóźnienia
function Audio.preload(names: { string })
	local sounds = {}
	for _, name in names do
		local entry = def("sfx", name) or def("music", name)
		if entry then
			local sound = Instance.new("Sound")
			sound.SoundId = entry.id
			table.insert(sounds, sound)
		end
	end
	task.spawn(function()
		pcall(function()
			game:GetService("ContentProvider"):PreloadAsync(sounds)
		end)
		for _, sound in sounds do
			sound:Destroy()
		end
	end)
end

-- ===== Playlisty w grze =====
-- Audio.playlist("forest" / "cave" / "swamp") wybiera muzykę świata. Gra tylko wtedy, gdy nic innego
-- nie ustawiło muzyki przez Audio.music (cutscenki); Audio.music(nil) oddaje głos playliście.

local playlistName: string? = nil
local playlistSound: Sound? = nil
local playlistOf: string? = nil -- do jakiej playlisty należy grający utwór
local lastTrack: { [string]: string } = {}
local nextAt = 0

local function playlistTracks(name: string): { string }
	-- Halloween: osobna lista w Config.Halloween.playlist
	if name == "halloween" then
		local halloween = (Config :: any).Halloween
		return if halloween and typeof(halloween.playlist) == "table" then halloween.playlist else {}
	end
	local audio = (Config :: any).Audio
	local lists = audio and audio.playlists
	local list = lists and lists[name]
	return if typeof(list) == "table" then list else {}
end

local function fadeOutPlaylist(time: number)
	local sound = playlistSound
	playlistSound = nil
	playlistOf = nil
	if sound then
		local out = TweenService:Create(sound, TweenInfo.new(time), { Volume = 0 })
		out.Completed:Connect(function()
			sound:Destroy()
		end)
		out:Play()
	end
end

local function startTrack(name: string)
	local tracks = playlistTracks(name)
	if #tracks == 0 then
		return
	end
	-- Losowo, ale nie ten sam co ostatnio
	local pick = tracks[math.random(1, #tracks)]
	if #tracks > 1 then
		while pick == lastTrack[name] do
			pick = tracks[math.random(1, #tracks)]
		end
	end
	lastTrack[name] = pick
	local sound = Instance.new("Sound")
	sound.Name = "Playlist_" .. name
	sound.SoundId = pick
	sound.Looped = false
	sound.Volume = 0
	sound.SoundGroup = musicGroup
	sound.Parent = SoundService
	sound:Play()
	local volume = (Config :: any).Audio.playlistVolume or 0.45
	TweenService:Create(sound, TweenInfo.new(3), { Volume = volume }):Play()
	playlistSound = sound
	playlistOf = name
	sound.Ended:Connect(function()
		if playlistSound == sound then
			playlistSound = nil
			playlistOf = nil
			local gap = (Config :: any).Audio.playlistGap or { 6, 16 }
			nextAt = os.clock() + gap[1] + math.random() * (gap[2] - gap[1])
		end
		sound:Destroy()
	end)
end

function Audio.playlist(name: string?)
	playlistName = name
end

-- Co sekundę: czy coś innego gra, czy zmienił się świat, czy czas na następny utwór
task.spawn(function()
	while true do
		task.wait(1)
		local wanted = if currentName == nil then playlistName else nil
		if playlistSound and playlistOf ~= wanted then
			-- Inny świat albo cutscenka: obecny utwór gaśnie, nowy wejdzie od razu
			fadeOutPlaylist(2)
			nextAt = os.clock() + 1.5
		end
		if wanted and not playlistSound and os.clock() >= nextAt then
			startTrack(wanted)
		end
	end
end)

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
	if not musicOn then
		return
	end
	TweenService:Create(musicGroup, TweenInfo.new(0.15), { Volume = MUSIC_VOLUME * musicLevel * (1 - amount) }):Play()
	task.delay(time, function()
		if musicOn then
			TweenService:Create(musicGroup, TweenInfo.new(0.6), { Volume = MUSIC_VOLUME * musicLevel }):Play()
		end
	end)
end

return Audio
