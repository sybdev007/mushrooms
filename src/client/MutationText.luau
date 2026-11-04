--!strict
-- Nazwy mutacji w języku gracza i w ich kolorach (RichText), np. „Tęcza Mech”: tęcza litera po literze
-- w kolorach tęczy, reszta w kolorze z Config (Variants / Tags / EventTags). Do napisów nad grzybami
-- (ogródek, skarbiec, celownik w lesie) i do „+N” przy zbieraniu.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Economy)
local Localize = require(script.Parent.Localize)

local MutationText = {}

local function hex(c: Color3): string
	return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function colored(text: string, color: Color3): string
	return string.format('<font color="%s">%s</font>', hex(color), text)
end

-- Każda litera w innym kolorze tęczy
local function rainbow(text: string): string
	local letters = {}
	for _, code in utf8.codes(text) do
		table.insert(letters, utf8.char(code))
	end
	local out = {}
	for i, letter in letters do
		local hue = (i - 1) / math.max(#letters, 1) * 0.83
		table.insert(out, colored(letter, Color3.fromHSV(hue, 0.55, 1)))
	end
	return table.concat(out)
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- Kosmiczny: litery na zmianę w fiolecie, błękicie i różu
local COSMIC = { Color3.fromRGB(150, 120, 255), Color3.fromRGB(110, 170, 255), Color3.fromRGB(220, 160, 255) }
local function cosmic(text: string): string
	local out = {}
	local i = 0
	for _, code in utf8.codes(text) do
		i += 1
		table.insert(out, colored(utf8.char(code), COSMIC[(i - 1) % #COSMIC + 1]))
	end
	return table.concat(out)
end

-- "" gdy grzyb nie ma mutacji
function MutationText.rich(variant: string?, tags: { string }?): string
	local parts = {}
	local def = Economy.getVariant(variant)
	if def then
		local name = Localize.t(def.key)
		table.insert(parts, if def.id == "rainbow" then rainbow(name) elseif def.id == "cosmic" then cosmic(name) else colored(name, rgb(def.color)))
	end
	for _, id in (tags or {}) :: { string } do
		local tag = Economy.getTag(id)
		if tag then
			table.insert(parts, colored(Localize.t(tag.key), rgb(tag.color)))
		end
	end
	return table.concat(parts, " ")
end

-- Wielkie litery także dla polskich znaków (string.upper zmienia tylko a-z)
local POLISH_UPPER: { [string]: string } = { ["ą"] = "Ą", ["ć"] = "Ć", ["ę"] = "Ę", ["ł"] = "Ł", ["ń"] = "Ń", ["ó"] = "Ó", ["ś"] = "Ś", ["ź"] = "Ź", ["ż"] = "Ż" }
function MutationText.upper(text: string): string
	local out = string.upper(text)
	for lower, upper in POLISH_UPPER do
		out = (string.gsub(out, lower, upper))
	end
	return out
end

-- Nazwa wariantu wielkimi literami w jego kolorach („ZŁOTY”, tęcza litera po literze); "" bez wariantu
function MutationText.variantTitle(variant: string?): string
	local def = Economy.getVariant(variant)
	if not def then
		return ""
	end
	local name = MutationText.upper(Localize.t(def.key))
	return if def.id == "rainbow" then rainbow(name) elseif def.id == "cosmic" then cosmic(name) else colored(name, rgb(def.color))
end

-- Kolor wariantu (tęcza i kosmos: kolor ich poświaty); nil bez wariantu
function MutationText.variantColor(variant: string?): Color3?
	local def = Economy.getVariant(variant)
	if not def then
		return nil
	end
	if def.id == "rainbow" then
		return Color3.fromRGB(255, 170, 235)
	elseif def.id == "cosmic" then
		return COSMIC[1]
	end
	return rgb(def.color)
end

-- Napis nad grzybem (BillboardGui z jednym TextLabel z RichText i obwódką), bez rodzica
function MutationText.billboard(name: string, size: UDim2, maxDistance: number): (BillboardGui, TextLabel)
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Size = size
	gui.AlwaysOnTop = false -- jak tabliczki ogródka: grzyby i ściany go zasłaniają, nie świeci przez las
	gui.LightInfluence = 0
	gui.MaxDistance = maxDistance
	gui.ResetOnSpawn = false
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.RichText = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(30, 20, 12)
	stroke.Parent = label
	return gui, label
end

return MutationText
