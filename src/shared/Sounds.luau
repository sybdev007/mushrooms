--!strict
-- Dźwięki z Creator Store Robloxa. Głównie licencjonowane biblioteki (ProSoundEffects, APM),
-- które działają w każdej grze. Każdy ID sprawdzony w Studio (wczytuje się, ma długość).

export type SoundDef = {
	id: number,
	volume: number,
	looped: boolean?,
	speed: number?,
}

local Sounds: { [string]: SoundDef } = {
	ambientEdge = { id = 9112764023, volume = 0.25, looped = true }, -- świerszcze nocą (ProSoundEffects)
	ambientDeep = { id = 9114625414, volume = 0.35, looped = true }, -- upiorny wiatr (ProSoundEffects)
	heartbeat = { id = 9043365842, volume = 0.6, looped = true }, -- bicie serca 96 BPM (APM)
	pick = { id = 9117848644, volume = 0.6 }, -- pyknięcie przy zbieraniu (ProSoundEffects)
	coins = { id = 1169755927, volume = 0.55 }, -- monety przy sprzedaży
	upgrade = { id = 4612374495, volume = 0.5 }, -- dzwoneczek przy ulepszeniu i złotym grzybie
	engulf = { id = 9114170094, volume = 0.7 }, -- szepty, gdy las pochłania gracza (ProSoundEffects)
}

return Sounds
