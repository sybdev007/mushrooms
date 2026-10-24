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
local SNAP = 0.002 -- poniżej tej różnicy przyjmujemy, że już jesteśmy u celu

local currentDarkness = 0
local appliedDarkness = -1
local appliedRange = -1

Lighting.FogColor = FOG_COLOR
Lighting.FogStart = 0

local function apply(d: number, lanternRange: number)
	Lighting.Ambient = BRIGHT_AMBIENT:Lerp(DARK_AMBIENT, d)
	Lighting.OutdoorAmbient = BRIGHT_AMBIENT:Lerp(DARK_AMBIENT, d)
	Lighting.Brightness = 2 * (1 - d)
	-- W najgłębszym mroku mgła zaczyna się tuż za kręgiem latarni
	local darkFog = math.max(lanternRange * 2.2, 30)
	Lighting.FogEnd = 500 + (darkFog - 500) * d
end

function Atmosphere.update(zone: number, lanternRange: number, dt: number): number
	local zoneDef = Config.Zones[zone] or Config.Zones[1]
	local target = zoneDef.darkness

	if math.abs(target - currentDarkness) < SNAP then
		currentDarkness = target
	else
		local alpha = math.clamp(dt * CHANGE_SPEED, 0, 1)
		currentDarkness += (target - currentDarkness) * alpha
	end

	-- Zapisujemy do Lighting tylko gdy coś się zmieniło. Wcześniej wartości zmieniały się
	-- o ułamki w każdej klatce w nieskończoność, co zmuszało silnik do ciągłego
	-- przeliczania oświetlenia i cieni (migotanie i spadki klatek).
	if currentDarkness ~= appliedDarkness or lanternRange ~= appliedRange then
		apply(currentDarkness, lanternRange)
		appliedDarkness = currentDarkness
		appliedRange = lanternRange
	end
	return currentDarkness
end

return Atmosphere
