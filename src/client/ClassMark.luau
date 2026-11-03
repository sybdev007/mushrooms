--!strict
-- Znak klasy grzyba: kolor + KSZTAŁT, żeby klasę dało się rozpoznać bez rozróżniania kolorów
-- (daltoniści, ciemny ekran telefonu). Ten sam znak stoi wszędzie, gdzie widać klasę:
-- karty w koszyku, sprzedaży i ogródku, Grzybopedia, napis nad grzybem w lesie, tabliczka grządki.
--   pospolity ● koło · niepospolity ▲ trójkąt · rzadki ■ kwadrat · epicki ◆ romb · legendarny ★ gwiazda

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Economy)
local UiKit = require(script.Parent.UiKit)

local ClassMark = {}

local GLYPHS: { [string]: string } = {
	common = "●",
	uncommon = "▲",
	rare = "■",
	epic = "◆",
	legendary = "★",
}
-- Znaki mają różną wielkość w czcionce: wyrównujemy je, żeby wyglądały na równe
local FIT: { [string]: number } = {
	common = 0.86,
	uncommon = 0.84,
	rare = 0.8,
	epic = 0.92,
	legendary = 1.05,
}

local function rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

function ClassMark.glyph(classId: string): string
	return GLYPHS[classId] or "●"
end

-- Znak klasy gatunku w kolorze klasy jako RichText: '<font color="#5AAAFF">■</font>'
function ClassMark.rich(speciesId: string): string
	local class = Economy.speciesClass(speciesId)
	local c = class.color
	return string.format('<font color="#%02X%02X%02X">%s</font>', c[1], c[2], c[3], ClassMark.glyph(class.id))
end

-- Sam znak (bez koloru) dla gatunku — do napisów, które już mają kolor klasy
function ClassMark.plain(speciesId: string): string
	return ClassMark.glyph(Economy.speciesClass(speciesId).id)
end

-- Znak jako osobny element: kolorowy kształt z ciemną obwódką, w rogu karty
function ClassMark.new(parent: Instance, speciesId: string, size: number, position: UDim2, anchor: Vector2?): TextLabel
	local class = Economy.speciesClass(speciesId)
	local label = Instance.new("TextLabel")
	label.Name = "ClassMark"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromOffset(size, size)
	label.Position = position
	label.AnchorPoint = anchor or Vector2.zero
	label.Font = Enum.Font.Arimo
	label.Text = ClassMark.glyph(class.id)
	label.TextScaled = true
	label.TextColor3 = rgb(class.color)
	label.ZIndex = 8
	label.Active = false
	label.Parent = parent
	UiKit.outline(label, math.max(1.5, size / 12))
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = math.floor(size * (FIT[class.id] or 0.9))
	constraint.Parent = label
	return label
end

return ClassMark
