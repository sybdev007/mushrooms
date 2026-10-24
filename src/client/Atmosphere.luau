--!strict
-- Klimat zależny od strefy: mgła (Atmosphere), korekcja kolorów, poświata (Bloom) i niebo z gwiazdami.
-- Działa tylko lokalnie u gracza, więc każdy widzi mrok swojej strefy, nawet gdy inni stoją w chatce.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Atmosphere = {}

local CHANGE_SPEED = 1.5 -- jak szybko klimat dopasowuje się do nowej strefy
local SNAP = 0.002 -- poniżej tej różnicy przyjmujemy, że już jesteśmy u celu

-- Jasno (polana o zmierzchu) -> ciemno (jar w środku nocy)
local BRIGHT_AMBIENT = Color3.fromRGB(92, 86, 104)
local DARK_AMBIENT = Color3.fromRGB(8, 8, 16)
local BRIGHT_FOG = Color3.fromRGB(150, 120, 160)
local DARK_FOG = Color3.fromRGB(10, 12, 22)
local DARK_TINT = Color3.fromRGB(196, 210, 255)

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
	atmosphere.Color = BRIGHT_FOG:Lerp(DARK_FOG, d)
	atmosphere.Haze = 0.5 + 0.9 * d

	colorCorrection.Saturation = -0.04 - 0.3 * d
	colorCorrection.Contrast = 0.06 + 0.1 * d
	colorCorrection.TintColor = Color3.new(1, 1, 1):Lerp(DARK_TINT, d)
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

	-- Zapisujemy do Lighting tylko gdy coś się zmieniło. Wartości zmieniane o ułamki w każdej
	-- klatce zmuszały silnik do ciągłego przeliczania oświetlenia (migotanie i spadki klatek).
	if currentDarkness ~= appliedDarkness or lanternRange ~= appliedRange then
		apply(currentDarkness, lanternRange)
		appliedDarkness = currentDarkness
		appliedRange = lanternRange
	end
	return currentDarkness
end

return Atmosphere
