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

-- Rząd przycisków pod panelem monet: język, muzyka, dźwięki, zaproś. Wyższy niż reszta HUD, a na
-- telefonie zmniejsza się mniej, żeby dało się w niego trafić palcem. Pod nim leżą przycisk sklepu
-- (ShopPanel) i panel DEV, więc wszyscy liczą jego dół tak samo (rowBottom).
UiScale.ROW_HEIGHT = 40
local ROW_MIN_SMALL = 0.8

-- Czysta funkcja, testowana w Lune
function UiScale.computeRow(size: Vector2): number
	local scale = UiScale.compute(size)
	return if UiScale.isSmallScreen(size) then math.max(scale, ROW_MIN_SMALL) else scale
end

function UiScale.row(): number
	return UiScale.computeRow(viewport())
end

-- Góra rzędu: pod panelem monet (8 + 80 + 8 w skali HUD)
function UiScale.rowTop(): number
	return 8 + math.floor(80 * UiScale.get()) + 8
end

function UiScale.rowBottom(): number
	return UiScale.rowTop() + math.floor(UiScale.ROW_HEIGHT * UiScale.row())
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
