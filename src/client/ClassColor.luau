--!strict
-- Klasa grzyba pokazana kolorem NAZWY (bez osobnych znaków ● ▲ ■ ◆ ★, decyzja Toma 3.11):
-- nazwa gatunku w gradiencie koloru klasy (karty w koszyku, skupie, ogródku, Grzybopedia, tabliczki grządek,
-- napis nad grzybem w lesie). Pospolity szary, niepospolity zielony, rzadki niebieski, epicki fiolet,
-- legendarny złoto — kolory z Config (Economy.speciesClass).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Economy)
local UiFx = require(script.Parent.UiFx)

local ClassColor = {}

local WHITE = Color3.new(1, 1, 1)

function ClassColor.of(speciesId: string): Color3
	local c = Economy.speciesClass(speciesId).color
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- Napis (np. nazwa gatunku) w gradiencie koloru klasy: jaśniej u góry, pełny kolor u dołu
function ClassColor.paint(label: TextLabel, speciesId: string)
	local color = ClassColor.of(speciesId)
	label.TextColor3 = WHITE
	local existing = label:FindFirstChildOfClass("UIGradient")
	if existing then
		existing:Destroy()
	end
	UiFx.textGradient(label, color:Lerp(WHITE, 0.55), color:Lerp(WHITE, 0.08))
end

-- Tekst w kolorze klasy jako RichText (do napisów złożonych z kilku części)
function ClassColor.rich(speciesId: string, text: string): string
	return string.format('<font color="%s">%s</font>', UiFx.hex(ClassColor.of(speciesId):Lerp(WHITE, 0.15)), text)
end

return ClassColor
