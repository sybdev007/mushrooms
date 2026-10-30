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

-- "" gdy grzyb nie ma mutacji
function MutationText.rich(variant: string?, tags: { string }?): string
	local parts = {}
	local def = Economy.getVariant(variant)
	if def then
		local name = Localize.t(def.key)
		table.insert(parts, if def.id == "rainbow" then rainbow(name) else colored(name, rgb(def.color)))
	end
	for _, id in (tags or {}) :: { string } do
		local tag = Economy.getTag(id)
		if tag then
			table.insert(parts, colored(Localize.t(tag.key), rgb(tag.color)))
		end
	end
	return table.concat(parts, " ")
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
