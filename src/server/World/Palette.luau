--!strict
-- Kolory świata w jednym miejscu: jesienny las nocą, kreskówkowe low-poly.

local Palette = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

Palette.trunk = rgb(92, 64, 46)
Palette.trunkDark = rgb(66, 48, 38)
Palette.deadWood = rgb(78, 72, 68)
Palette.birchBark = rgb(232, 228, 214)
Palette.birchMark = rgb(44, 42, 40)

Palette.pine = { rgb(46, 94, 62), rgb(38, 82, 58), rgb(56, 104, 64), rgb(34, 72, 54) }
Palette.autumn = { rgb(214, 120, 46), rgb(228, 168, 62), rgb(184, 76, 42), rgb(204, 146, 52) }
Palette.birchLeaves = { rgb(222, 190, 74), rgb(196, 176, 70), rgb(170, 168, 72) }
Palette.bush = { rgb(58, 96, 52), rgb(72, 108, 56), rgb(48, 84, 50) }
Palette.fern = { rgb(68, 108, 60), rgb(82, 118, 62), rgb(60, 98, 56) }
Palette.grass = { rgb(86, 116, 60), rgb(100, 124, 62), rgb(74, 104, 56) }
Palette.rock = { rgb(128, 126, 120), rgb(106, 104, 100), rgb(140, 136, 128) }
Palette.moss = rgb(88, 124, 62)
Palette.stone = rgb(156, 146, 132)

-- Ziemia stref: od jasnej polany przy chatce po prawie czarny jar
Palette.ground = {
	rgb(84, 110, 62), -- chatka
	rgb(70, 98, 56), -- skraj lasu
	rgb(58, 88, 52), -- gęstwina
	rgb(38, 50, 42), -- mroczny jar
}
Palette.outerGround = rgb(44, 62, 44)

Palette.log = rgb(124, 86, 56)
Palette.logEnd = rgb(176, 132, 88)
Palette.plank = rgb(150, 106, 68)
Palette.plankDark = rgb(112, 78, 52)
Palette.roof = rgb(84, 52, 44)
Palette.roofEdge = rgb(64, 40, 34)
Palette.stoneChimney = rgb(118, 112, 106)
Palette.windowGlow = rgb(214, 150, 74) -- przyciemnione: neon od środka chatki raził w oczy
Palette.lanternGlow = rgb(255, 206, 120)
Palette.windowNight = rgb(28, 36, 66) -- okno widziane od środka chatki
Palette.metal = rgb(52, 50, 48)
Palette.signWood = rgb(138, 96, 60)
Palette.glowShroom = { rgb(90, 220, 255), rgb(150, 120, 255), rgb(110, 255, 200) }

function Palette.pick(list: { Color3 }, rng: Random): Color3
	return list[rng:NextInteger(1, #list)]
end

-- Przyciemnienie koloru w głębszych strefach (0 = bez zmian, 1 = mocno ciemniej)
function Palette.shade(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0.05, 0.06, 0.08), math.clamp(amount, 0, 1) * 0.55)
end

return Palette
