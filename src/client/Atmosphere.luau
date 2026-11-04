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
local SPIRIT_FOG = Color3.fromRGB(104, 40, 150)
local SPIRIT_TINT = Color3.fromRGB(206, 168, 255)
local currentTint = DARK_TINT
local appliedTint = DARK_TINT

-- Łysa Góra: fioletowa noc z wielkim księżycem tuż nad szczytem. Szerokość geograficzna 100 i północ
-- stawiają księżyc nisko na +Z, dokładnie za szczytem z chatką (z polany wisi nad górą), a o świcie
-- słońce wschodzi zza góry. Mgła rzadsza niż w lesie (widać dolinę, morze chmur i dalekie szczyty),
-- a w mroku zostaje fioletowa poświata księżyca, żeby było widać zbocza i serpentyny.
local MOUNTAIN_LATITUDE = 100
local MOUNTAIN_NIGHT_CLOCK = 0
local MOUNTAIN_MOON_SIZE = 24
local MOUNTAIN_STARS = 5000
local MOUNTAIN_BRIGHT_AMBIENT = Color3.fromRGB(130, 116, 164)
local MOUNTAIN_DARK_AMBIENT = Color3.fromRGB(100, 84, 142)
local MOUNTAIN_FOG = Color3.fromRGB(104, 66, 144)
local MOUNTAIN_DECAY = Color3.fromRGB(120, 50, 160)
local MOUNTAIN_TINT = Color3.fromRGB(214, 198, 255)
local FOREST_DECAY = Color3.fromRGB(60, 50, 80)
local FOREST_MOON_SIZE = 14
local FOREST_STARS = 3500
local defaultLatitude = (Lighting.GeographicLatitude :: number)
local skyMountain: boolean? = nil -- nil = jeszcze nie ustawione

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
	MountainFlash = true, -- błysk pioruna na Łysej Górze (MountainSky)
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
atmosphere.Decay = FOREST_DECAY

local colorCorrection = getOrCreate("ColorCorrectionEffect", "ForestColor") :: ColorCorrectionEffect
local bloom = getOrCreate("BloomEffect", "ForestBloom") :: BloomEffect
-- Poświata tylko dla naprawdę jasnych rzeczy (neon, latarnie), nie dla oświetlonego drewna. Słabsza
-- i węższa niż kiedyś (0,45 / 24 / 1,25): przy grupach neonów (złote grzyby, podest z reliktami,
-- skarbiec Skarbnika) zlewała się w białe plamy (test 4.11).
bloom.Intensity = 0.3
bloom.Size = 16
bloom.Threshold = 1.5

local sky = getOrCreate("Sky", "ForestSky") :: Sky
sky.StarCount = FOREST_STARS
sky.CelestialBodiesShown = true
sky.MoonAngularSize = FOREST_MOON_SIZE

local currentDarkness = 0
local appliedDarkness = -1
local appliedRange = -1
-- Kolor mgły w mroku: nocny granat w lesie, w jaskini zależny od strefy (Config.Zones[].fog)
local currentFog = DARK_FOG
local appliedFog = DARK_FOG

local function apply(d: number, lanternRange: number)
	local mountain = skyMountain == true
	local bright = if mountain then MOUNTAIN_BRIGHT_AMBIENT else BRIGHT_AMBIENT
	local dark = if mountain then MOUNTAIN_DARK_AMBIENT else DARK_AMBIENT
	Lighting.Ambient = bright:Lerp(dark, d)
	Lighting.OutdoorAmbient = bright:Lerp(dark, d)
	-- Na górze świeci księżyc zza szczytu: zbocza mają światło z jednej strony, a krawędzie poświatę
	Lighting.Brightness = if mountain then 0.6 * (1 - d) + 1.6 else 1.1 * (1 - d) + 0.05
	Lighting.EnvironmentDiffuseScale = 0.6 * (1 - d)
	Lighting.EnvironmentSpecularScale = 0.4 * (1 - d)

	-- Gęstość mgły rośnie z mrokiem, a słabsza latarnia oznacza gęstszą mgłę w ciemności.
	-- Uwaga: powyżej ok. 0,5 mgła zasłania nawet postać i krąg latarni (sprawdzone w Studio przy 0,7).
	local lanternFactor = math.clamp((40 - lanternRange) / 30, 0, 1)
	if mountain then
		-- Rzadsza, fioletowa mgła: z góry widać dolinę i morze chmur; strefa (np. zielone Kotły) lekko ją barwi
		atmosphere.Density = 0.24 + 0.02 * d + 0.03 * d * lanternFactor
		atmosphere.Haze = 0.6
		atmosphere.Color = MOUNTAIN_FOG:Lerp(currentFog, 0.3)
	else
		atmosphere.Density = 0.28 + 0.14 * d + 0.05 * d * lanternFactor
		atmosphere.Haze = 0.5 + 0.9 * d
		atmosphere.Color = BRIGHT_FOG:Lerp(currentFog, d)
	end
	atmosphere.Decay = if mountain then MOUNTAIN_DECAY else FOREST_DECAY

	colorCorrection.Saturation = if mountain then -0.02 - 0.12 * d else -0.04 - 0.3 * d
	colorCorrection.Contrast = 0.06 + 0.1 * d
	colorCorrection.TintColor = Color3.new(1, 1, 1):Lerp(if mountain then MOUNTAIN_TINT else currentTint, d)
end

-- Niebo świata: na Łysej Górze księżyc za szczytem, więcej gwiazd; gdzie indziej jak dawniej
local function setWorldSky(mountain: boolean, dawn: boolean)
	if skyMountain == mountain then
		return
	end
	skyMountain = mountain
	Lighting.GeographicLatitude = if mountain then MOUNTAIN_LATITUDE else defaultLatitude
	sky.MoonAngularSize = if mountain then MOUNTAIN_MOON_SIZE else FOREST_MOON_SIZE
	sky.StarCount = if mountain then MOUNTAIN_STARS else FOREST_STARS
	-- Przejście przez portal: niebo od razu w porze tego świata (bez kręcenia gwiazdami)
	currentClock = if dawn then DAWN_CLOCK elseif mountain then MOUNTAIN_NIGHT_CLOCK else NIGHT_CLOCK
	Lighting.ClockTime = currentClock
	appliedDarkness = -1
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
	local mountain = zoneDef.world == "mountain"
	setWorldSky(mountain, dawn)

	local targetClock = if dawn then DAWN_CLOCK elseif mountain then MOUNTAIN_NIGHT_CLOCK else NIGHT_CLOCK
	local diff = (targetClock - currentClock) % 24
	if diff > 0.001 then
		currentClock = (currentClock + math.min(diff, dt * CLOCK_SPEED)) % 24
		Lighting.ClockTime = currentClock
	end
	local fog = zoneDef.fog
	local spirit = not dawn and Workspace:GetAttribute("CycleEvent") == "spirit_night"
	local targetFog = if fog then Color3.fromRGB(fog[1], fog[2], fog[3]) else DARK_FOG
	if spirit then
		targetFog = targetFog:Lerp(SPIRIT_FOG, 0.9)
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
