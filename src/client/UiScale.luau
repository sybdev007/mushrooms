--!strict
-- Wspólna skala interfejsu zależna od rozmiaru ekranu.
-- HUD jest zaprojektowany na ekran ok. 1000x560; na telefonie (np. 705x338) wszystko
-- zmniejsza się proporcjonalnie, żeby panel chatki nie zasłaniał połowy widoku.

local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

local UiScale = {}

local DESIGN_WIDTH = 1000
local DESIGN_HEIGHT = 560
local MIN_SCALE = 0.55
-- Roblox pokazuje mały przycisk skoku, gdy krótszy bok ekranu ma najwyżej tyle pikseli
local SMALL_SCREEN = 500

local function viewport(): Vector2
	local camera = Workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(DESIGN_WIDTH, DESIGN_HEIGHT)
end

-- Czysta funkcja, testowana w Lune
function UiScale.compute(size: Vector2): number
	return math.clamp(math.min(size.X / DESIGN_WIDTH, size.Y / DESIGN_HEIGHT), MIN_SCALE, 1)
end

function UiScale.isSmallScreen(size: Vector2): boolean
	return math.min(size.X, size.Y) <= SMALL_SCREEN
end

function UiScale.get(): number
	return UiScale.compute(viewport())
end

function UiScale.isSmall(): boolean
	return UiScale.isSmallScreen(viewport())
end

-- Wysokość paska Robloxa u góry ekranu (dla interfejsów z IgnoreGuiInset)
function UiScale.topInset(): number
	return GuiService:GetGuiInset().Y
end

function UiScale.onChanged(callback: () -> ())
	local connection: RBXScriptConnection? = nil
	local function watch()
		if connection then
			connection:Disconnect()
		end
		local camera = Workspace.CurrentCamera
		if camera then
			connection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(callback)
		end
		callback()
	end
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watch)
	watch()
end

return UiScale
