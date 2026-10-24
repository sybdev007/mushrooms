--!strict
-- Ciemność i mgła zależne od strefy. Działa tylko lokalnie u gracza,
-- więc każdy widzi mrok swojej strefy, nawet gdy inni stoją w chatce.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Atmosphere = {}

local BRIGHT_AMBIENT = Color3.fromRGB(125, 120, 130)
local DARK_AMBIENT = Color3.fromRGB(6, 6, 12)
local FOG_COLOR = Color3.fromRGB(12, 14, 22)
local CHANGE_SPEED = 1.5 -- jak szybko światło dopasowuje się do nowej strefy

local currentDarkness = 0

Lighting.FogColor = FOG_COLOR
Lighting.FogStart = 0

function Atmosphere.update(zone: number, lanternRange: number, dt: number): number
	local zoneDef = Config.Zones[zone] or Config.Zones[1]
	local target = zoneDef.darkness
	local alpha = math.clamp(dt * CHANGE_SPEED, 0, 1)
	currentDarkness += (target - currentDarkness) * alpha

	local d = currentDarkness
	Lighting.Ambient = BRIGHT_AMBIENT:Lerp(DARK_AMBIENT, d)
	Lighting.OutdoorAmbient = BRIGHT_AMBIENT:Lerp(DARK_AMBIENT, d)
	Lighting.Brightness = 2 * (1 - d)
	-- W najgłębszym mroku mgła zaczyna się tuż za kręgiem latarni
	local darkFog = math.max(lanternRange * 2.2, 30)
	Lighting.FogEnd = 500 + (darkFog - 500) * d
	return d
end

return Atmosphere
