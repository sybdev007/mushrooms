--!strict
-- Klimat zależny od strefy: mgła (Atmosphere), korekcja kolorów, poświata (Bloom) i niebo z gwiazdami.
-- Działa tylko lokalnie u gracza, więc każdy widzi mrok swojej strefy, nawet gdy inni stoją w chatce.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local Atmosphere = {}

local CHANGE_SPEED = 1.5 -- jak szybko klimat dopasowuje się do nowej strefy
-- Pora dnia na niebie: wieczór nocą, wschód słońca o świcie. Zegar idzie zawsze do przodu
-- (przez północ), CLOCK_SPEED godzin na sekundę, więc zmiana pory trwa ok. 2 sekund.
local NIGHT_CLOCK = 19
local DAWN_CLOCK = 6.4
local CLOCK_SPEED = 6
local currentClock = NIGHT_CLOCK
local SNAP = 0.002 -- poniżej tej różnicy przyjmujemy, że już jesteśmy u celu

-- Jasno (polana o zmierzchu) -> ciemno (jar w środku nocy)
local BRIGHT_AMBIENT = Color3.fromRGB(92, 86, 104)
local DARK_AMBIENT = Color3.fromRGB(8, 8, 16)
local BRIGHT_FOG = Color3.fromRGB(150, 120, 160)
local DARK_FOG = Color3.fromRGB(10, 12, 22)
local DARK_TINT = Color3.fromRGB(196, 210, 255)
-- Halloween, Noc Dziadów: fioletowa mgła i fioletowy odcień w mroku (dusze przodków)
local SPIRIT_FOG = Color3.fromRGB(58, 20, 78)
local SPIRIT_TINT = Color3.fromRGB(222, 190, 255)
local currentTint = DARK_TINT
local appliedTint = DARK_TINT

local function getOrCreate(className: string, name: string): Instance
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = Lighting
	return instance
end

-- Szablon miejsca w Studio wkłada do Lighting własne Atmosphere, Sky, Bloom, SunRays i DepthOfField.
-- Silnik używa tylko jednej mgły i jednego nieba, a dwa Bloomy się sumują: ciepła domyślna mgła
-- i podwójna poświata przepalały wnętrze chatki na pomarańczowo. Zostawiamy tylko nasze efekty.
local OWN_EFFECTS = {
	ForestAtmosphere = true,
	ForestColor = true,
	ForestBloom = true,
	ForestSky = true,
}

local function removeForeignEffect(child: Instance)
	if OWN_EFFECTS[child.Name] then
		return
	end
	if child:IsA("Atmosphere") or child:IsA("Sky") or child:IsA("PostEffect") then
		child:Destroy()
	end
end

for _, child in Lighting:GetChildren() do
	removeForeignEffect(child)
end
Lighting.ChildAdded:Connect(function(child)
	-- Odroczone, bo nie wolno niszczyć obiektu w trakcie dodawania go do rodzica
	task.defer(removeForeignEffect, child)
end)

local atmosphere = getOrCreate("Atmosphere", "ForestAtmosphere") :: Atmosphere
atmosphere.Offset = 0.05
atmosphere.Glare = 0
atmosphere.Decay = Color3.fromRGB(60, 50, 80)

local colorCorrection = getOrCreate("ColorCorrectionEffect", "ForestColor") :: ColorCorrectionEffect
local bloom = getOrCreate("BloomEffect", "ForestBloom") :: BloomEffect
-- Poświata tylko dla naprawdę jasnych rzeczy (neon, latarnie), nie dla oświetlonego drewna
bloom.Intensity = 0.45
bloom.Size = 24
bloom.Threshold = 1.25

local sky = getOrCreate("Sky", "ForestSky") :: Sky
sky.StarCount = 3500
sky.CelestialBodiesShown = true
sky.MoonAngularSize = 14

local currentDarkness = 0
local appliedDarkness = -1
local appliedRange = -1
-- Kolor mgły w mroku: nocny granat w lesie, w jaskini zależny od strefy (Config.Zones[].fog)
local currentFog = DARK_FOG
local appliedFog = DARK_FOG

local function apply(d: number, lanternRange: number)
	Lighting.Ambient = BRIGHT_AMBIENT:Lerp(DARK_AMBIENT, d)
	Lighting.OutdoorAmbient = BRIGHT_AMBIENT:Lerp(DARK_AMBIENT, d)
	Lighting.Brightness = 1.1 * (1 - d) + 0.05
	Lighting.EnvironmentDiffuseScale = 0.6 * (1 - d)
	Lighting.EnvironmentSpecularScale = 0.4 * (1 - d)

	-- Gęstość mgły rośnie z mrokiem, a słabsza latarnia oznacza gęstszą mgłę w ciemności.
	-- Uwaga: powyżej ok. 0,5 mgła zasłania nawet postać i krąg latarni (sprawdzone w Studio przy 0,7).
	local lanternFactor = math.clamp((40 - lanternRange) / 30, 0, 1)
	atmosphere.Density = 0.28 + 0.14 * d + 0.05 * d * lanternFactor
	atmosphere.Color = BRIGHT_FOG:Lerp(currentFog, d)
	atmosphere.Haze = 0.5 + 0.9 * d

	colorCorrection.Saturation = -0.04 - 0.3 * d
	colorCorrection.Contrast = 0.06 + 0.1 * d
	colorCorrection.TintColor = Color3.new(1, 1, 1):Lerp(currentTint, d)
end

-- Cutscenka sama ustawia światło: na ten czas Atmosphere nic nie zapisuje do Lighting,
-- a po wznowieniu od razu przywraca klimat strefy
local paused = false
function Atmosphere.setPaused(value: boolean)
	paused = value
	if not value then
		appliedDarkness = -1
		currentClock = (Lighting.ClockTime :: number)
	end
end

function Atmosphere.update(zone: number, lanternRange: number, dt: number): number
	if paused then
		return currentDarkness
	end
	local zoneDef = Config.Zones[zone] or Config.Zones[1]
	local dawn = Workspace:GetAttribute("CyclePhase") == "dawn"
	-- O świcie mrok w lesie słabnie (w jaskini nie ma słońca)
	local target = zoneDef.darkness * (if dawn and zoneDef.world ~= "cave" then Config.Cycle.dawnDarkness else 1)

	local targetClock = if dawn then DAWN_CLOCK else NIGHT_CLOCK
	local diff = (targetClock - currentClock) % 24
	if diff > 0.001 then
		currentClock = (currentClock + math.min(diff, dt * CLOCK_SPEED)) % 24
		Lighting.ClockTime = currentClock
	end
	local fog = zoneDef.fog
	local spirit = not dawn and Workspace:GetAttribute("CycleEvent") == "spirit_night"
	local targetFog = if fog then Color3.fromRGB(fog[1], fog[2], fog[3]) else DARK_FOG
	if spirit then
		targetFog = targetFog:Lerp(SPIRIT_FOG, 0.75)
	end
	local fogAlpha = math.clamp(dt * CHANGE_SPEED, 0, 1)
	currentFog = currentFog:Lerp(targetFog, fogAlpha)
	if (Vector3.new(currentFog.R, currentFog.G, currentFog.B) - Vector3.new(targetFog.R, targetFog.G, targetFog.B)).Magnitude < SNAP then
		currentFog = targetFog
	end
	local targetTint = if spirit then SPIRIT_TINT else DARK_TINT
	currentTint = currentTint:Lerp(targetTint, fogAlpha)
	if (Vector3.new(currentTint.R, currentTint.G, currentTint.B) - Vector3.new(targetTint.R, targetTint.G, targetTint.B)).Magnitude < SNAP then
		currentTint = targetTint
	end

	if math.abs(target - currentDarkness) < SNAP then
		currentDarkness = target
	else
		local alpha = math.clamp(dt * CHANGE_SPEED, 0, 1)
		currentDarkness += (target - currentDarkness) * alpha
	end

	-- Zapisujemy do Lighting tylko gdy coś się zmieniło. Wartości zmieniane o ułamki w każdej
	-- klatce zmuszały silnik do ciągłego przeliczania oświetlenia (migotanie i spadki klatek).
	if currentDarkness ~= appliedDarkness or lanternRange ~= appliedRange or currentFog ~= appliedFog or currentTint ~= appliedTint then
		apply(currentDarkness, lanternRange)
		appliedDarkness = currentDarkness
		appliedRange = lanternRange
		appliedFog = currentFog
		appliedTint = currentTint
	end
	return currentDarkness
end

return Atmosphere
