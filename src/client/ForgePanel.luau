--!strict
-- Okno Kuźni Grzybów (Moździerz Zielarki) według projektu „Kuźnia Grzybów UI” (5.11). Po lewej opis z szansami,
-- runa z trójkątem i trzema miejscami oraz pasek z opłatą i przyciskiem, po prawej koszyk. Klik w grzyb w koszyku
-- wrzuca go do wolnego miejsca, klik w miejsce go wyjmuje. Po „Połącz”: ładowanie runy, zlot grzybów do środka,
-- bęben, błysk z falą i odsłonięcie wyniku z oceną na skali wkładu. Szanse i opłatę liczy Shared/Forge dla
-- tej konkretnej trójki, ale wynik losuje serwer (ForgeService); okno go tylko pokazuje.
-- Wszystko jest rysowane w układzie projektu (1280 × 720) i zmniejszone przez UIScale. Runy są z kresek,
-- bo czcionki Robloxa nie mają znaków runicznych. Ruch liczy jedna funkcja `step` (UiFx.animate) z fazy i czasu.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Forge = require(Shared.Forge)
local Remotes = require(Shared.Remotes)
local Audio = require(script.Parent.Audio)
local Localize = require(script.Parent.Localize)
local MushroomArt = require(script.Parent.MushroomArt)
local PanelKit = require(script.Parent.PanelKit)
local UiFx = require(script.Parent.UiFx)
local UiKit = require(script.Parent.UiKit)

local ForgePanel = {}

type Item = Forge.Item
type Phase = "idle" | "charge" | "converge" | "reel" | "flash" | "reveal"
type Fade = { { inst: Instance, prop: string, base: number } }

-- ===== Wymiary projektu =====

local K = 0.75 -- projekt 1280 × 720 w oknie 960 × 540
local W, H = 1280, 720
local SCENE_W, SCENE_H = 800, 452
local CENTER = Vector2.new(400, 226)
-- Trójkąt w układzie obracającej się runy (400 × 400, środek 200, 200)
local VERTS = { Vector2.new(200, 30), Vector2.new(53, 285), Vector2.new(347, 285) }
local RIG_CENTER = Vector2.new(200, 200)
local REEL_DELAYS = { 0.06, 0.06, 0.06, 0.065, 0.07, 0.075, 0.085, 0.095, 0.11, 0.125, 0.145, 0.17, 0.2, 0.24, 0.29, 0.35, 0.43 }
local NUMERALS = { "I", "II", "III" }

local TITLE = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.ExtraBold)
local BODY_BOLD = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Bold)

local C = {
	cardTop = Color3.fromHex("13221b"),
	cardBottom = Color3.fromHex("0e1a14"),
	line = Color3.fromHex("2b4337"),
	muted = Color3.fromHex("b7c8bc"),
	sub = Color3.fromHex("8fb09c"),
	dim = Color3.fromHex("7d9a8a"),
	gold = Color3.fromHex("f2d38a"),
	pale = Color3.fromHex("ffe9a8"),
	rune = Color3.fromHex("ffd884"),
	name = Color3.fromHex("fff1c9"),
	tile = Color3.fromHex("16221d"),
	tileEdge = Color3.fromHex("2c3d35"),
	tileText = Color3.fromHex("e3ece4"),
	locked = Color3.fromHex("101915"),
	cell = Color3.fromHex("0c1812"),
	empty = Color3.fromHex("4d6f5d"),
	slotEmpty = Color3.fromHex("0a140e"),
	sceneBg = Color3.fromHex("0c1712"),
	sceneMid = Color3.fromHex("1b3a2c"),
	hub = Color3.fromHex("0a140e"),
	buttonOff = Color3.fromHex("1b2a22"),
	buttonOffText = Color3.fromHex("6f8479"),
	buttonText = Color3.fromHex("1a1305"),
	badgeText = Color3.fromHex("10160f"),
	numeral = Color3.fromHex("241a05"),
	cosmic = Color3.fromHex("a68cff"),
}

-- Plakietki z szansami: tło, obwódka, napis (jak w projekcie)
local CHIP = {
	worse = { Color3.fromHex("2a2118"), Color3.fromHex("c08a54"), Color3.fromHex("e6b684") },
	similar = { Color3.fromHex("222219"), Color3.fromHex("efe8d2"), Color3.fromHex("efe8d2") },
	better = { Color3.fromHex("122a1c"), Color3.fromHex("5fd38a"), Color3.fromHex("7be3a2") },
	mutation = { Color3.fromHex("1f1a33"), Color3.fromHex("8f78ff"), Color3.fromHex("c9bbff") },
	recipe = { Color3.fromHex("2a2410"), Color3.fromHex("f2d38a"), Color3.fromHex("f2d38a") },
	rune = { Color3.fromHex("1a2420"), Color3.fromHex("7d9a8a"), Color3.fromHex("b7c8bc") },
}

-- Wynik z przepisu: kolor i napis na plakietce (progi runy mają swoje w Config.Forge.tiers)
local RECIPE_LOOK: { [string]: { key: string, color: Color3 } } = {
	recipe = { key = "FORGE_OUT_RECIPE", color = Color3.fromRGB(190, 140, 255) },
	recipeLucky = { key = "FORGE_OUT_RECIPE_LUCKY", color = PanelKit.GOLD },
	mythic = { key = "FORGE_OUT_MYTHIC", color = Color3.fromRGB(255, 70, 110) },
	secret = { key = "FORGE_OUT_SECRET", color = Color3.fromRGB(236, 240, 255) },
}
local REVEAL_SOUND: { [string]: string } = {
	bust = "crack",
	worse = "shimmer",
	similar = "shimmer",
	better = "levelup",
	great = "swell",
	recipe = "levelup",
	recipeLucky = "levelup",
	mythic = "swell",
	secret = "swell",
}

-- Runy z kresek w polu 6 × 10 (x1, y1, x2, y2 po kolei): zewnętrzny krąg ᚠᚢᚦᚨᚱᚲᚷᚹᚺᚾᛁᛃ, wewnętrzny ᛇᛈᛉᛊᛏᛒᛖᛗ
local OUTER_RUNES: { { number } } = {
	{ 1, 0, 1, 10, 1, 3, 5, 0, 1, 6, 5, 3 },
	{ 1, 10, 1, 0, 1, 0, 5, 4, 5, 4, 5, 10 },
	{ 1, 0, 1, 10, 1, 3, 5, 5, 5, 5, 1, 7 },
	{ 1, 0, 1, 10, 1, 0, 5, 3, 1, 4, 5, 7 },
	{ 1, 0, 1, 10, 1, 0, 5, 2.5, 5, 2.5, 1, 5, 1, 5, 5, 10 },
	{ 5, 2, 1, 5, 1, 5, 5, 8 },
	{ 0.5, 1, 5.5, 9, 5.5, 1, 0.5, 9 },
	{ 1, 0, 1, 10, 1, 0, 5, 2.5, 5, 2.5, 1, 5 },
	{ 1, 0, 1, 10, 5, 0, 5, 10, 1, 3, 5, 6 },
	{ 3, 0, 3, 10, 1, 3.5, 5, 6.5 },
	{ 3, 0, 3, 10 },
	{ 3, 1, 1, 3.5, 1, 3.5, 3, 6, 3, 4, 5, 6.5, 5, 6.5, 3, 9 },
}
local INNER_RUNES: { { number } } = {
	{ 3, 0, 3, 10, 3, 0, 5, 2, 3, 10, 1, 8 },
	{ 1, 0, 1, 10, 1, 1, 5, 4, 1, 9, 5, 6 },
	{ 3, 0, 3, 10, 3, 4, 0.5, 1, 3, 4, 5.5, 1 },
	{ 4.5, 0.5, 1.5, 4, 1.5, 4, 4.5, 6, 4.5, 6, 1.5, 9.5 },
	{ 3, 0, 3, 10, 3, 0, 0.5, 3, 3, 0, 5.5, 3 },
	{ 1, 0, 1, 10, 1, 0, 5, 2.5, 5, 2.5, 1, 5, 1, 5, 5, 7.5, 5, 7.5, 1, 10 },
	{ 0.5, 10, 0.5, 0, 0.5, 0, 3, 3, 3, 3, 5.5, 0, 5.5, 0, 5.5, 10 },
	{ 0.5, 10, 0.5, 0, 5.5, 10, 5.5, 0, 0.5, 0, 5.5, 5, 5.5, 0, 0.5, 5 },
}

-- ===== Teksty i liczby =====

local function t(key: string, args: { any }?): string
	return Localize.t(key, args)
end

local function decimal(text: string): string
	return if Localize.getLocale() == "pl" then (text:gsub("%.", ",")) else text
end

local function percent(chance: number, digits: number?): string
	return decimal(string.format("%." .. tostring(digits or 0) .. "f", chance * 100)) .. "%"
end

local function ratioText(ratio: number): string
	return decimal(if ratio >= 10 then string.format("%.0f", ratio) else string.format("%.2f", ratio)) .. "×"
end

local function formatCoins(value: number): string
	local s = tostring(math.floor(value + 0.5))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (formatted:gsub("^ ", ""))
end

-- Krótko na kafelku: 950, 1,2k, 35k, 2,4M
local function short(value: number): string
	local function one(x: number, suffix: string): string
		local text = if x < 10 then string.format("%.1f", x) else tostring(math.floor(x))
		text = text:gsub("%.0$", "")
		return decimal(text) .. suffix
	end
	if value >= 1e9 then
		return one(value / 1e9, "B")
	elseif value >= 1e6 then
		return one(value / 1e6, "M")
	elseif value >= 1e3 then
		return one(value / 1e3, "k")
	end
	return tostring(math.floor(value))
end

local function rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

local function speciesName(id: string): string
	local species = Economy.getSpecies(id)
	return if species then t(species.key) else id
end

-- Nazwa z ikonką wariantu („⭐ Prawdziwek”), bez odmiany przymiotników
local function itemName(item: Item): string
	local variant = Economy.getVariant(item.v)
	return (if variant then variant.icon .. " " else "") .. speciesName(item.s)
end

local function signature(item: Item?): string
	if not item then
		return ""
	end
	return string.format("%s|%s|%s|%s", item.s, item.v or "", table.concat((item.x or {}) :: { string }, ","), tostring(item.d or ""))
end

local function edgeColor(rank: number): Color3
	if rank <= 0 then
		return C.tileEdge
	elseif rank >= 4 then
		return C.cosmic
	end
	local variant = Economy.getVariant(Economy.variantOfRank(rank))
	return if variant then rgb(variant.color) else C.tileEdge
end

local function tierColor(kind: string): Color3
	local tier = Forge.tier(kind)
	if tier then
		return rgb(tier.color)
	end
	local look = RECIPE_LOOK[kind]
	return if look then look.color else C.rune
end

local function cubicBezier(x1: number, y1: number, x2: number, y2: number): (number) -> number
	local function curve(t0: number, a: number, b: number): number
		local u = 1 - t0
		return 3 * u * u * t0 * a + 3 * u * t0 * t0 * b + t0 * t0 * t0
	end
	local function slope(t0: number, a: number, b: number): number
		local u = 1 - t0
		return 3 * u * u * a + 6 * u * t0 * (b - a) + 3 * t0 * t0 * (1 - b)
	end
	return function(x: number): number
		local p = math.clamp(x, 0, 1)
		local s = p
		for _ = 1, 6 do
			local d = slope(s, x1, x2)
			if math.abs(d) < 1e-6 then
				break
			end
			s = math.clamp(s - (curve(s, x1, x2) - p) / d, 0, 1)
		end
		return curve(s, y1, y2)
	end
end
local RIG_EASE = cubicBezier(0.45, 0, 0.85, 0.55)
local CONVERGE_EASE = cubicBezier(0.6, 0, 0.9, 0.4)

-- ===== Klocki interfejsu =====

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for key, value in props do
		(inst :: any)[key] = value
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function at(x: number, y: number): UDim2
	return UDim2.fromOffset(x, y)
end

local function corner(parent: Instance, radius: UDim?)
	new("UICorner", { CornerRadius = radius or UDim.new(1, 0) }, parent)
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number?): UIStroke
	return new("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

local function frame(parent: Instance, name: string, position: UDim2, size: UDim2, color: Color3?, transparency: number?): Frame
	return new("Frame", {
		Name = name,
		Position = position,
		Size = size,
		BorderSizePixel = 0,
		BackgroundColor3 = color or Color3.new(1, 1, 1),
		BackgroundTransparency = if color then transparency or 0 else 1,
	}, parent)
end

local function label(parent: Instance, name: string, position: UDim2, size: UDim2, textSize: number, color: Color3, font: Font?, align: Enum.TextXAlignment?): TextLabel
	local l = new("TextLabel", {
		Name = name,
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		FontFace = font or BODY,
		TextColor3 = color,
		TextScaled = true,
		Text = "",
		TextXAlignment = align or Enum.TextXAlignment.Center,
	}, parent)
	new("UITextSizeConstraint", { MaxTextSize = textSize }, l)
	return l
end

local function card(parent: Instance, name: string, position: UDim2, size: UDim2): Frame
	local f = frame(parent, name, position, size, Color3.new(1, 1, 1))
	corner(f, UDim.new(0, 14))
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(C.cardTop, C.cardBottom) }, f)
	stroke(f, C.line, 1.5)
	return f
end

-- Elementy w kolorze runy (przy błysku i odsłonięciu przyjmują kolor wyniku)
local tintFrames: { Frame } = {}
local tintStrokes: { UIStroke } = {}

-- Kreska od a do b w układzie rodzica
local function segment(parent: Instance, a: Vector2, b: Vector2, thickness: number, color: Color3, transparency: number?): Frame
	local d = b - a
	local f = frame(parent, "Line", at((a.X + b.X) / 2, (a.Y + b.Y) / 2), at(d.Magnitude + thickness * 0.6, thickness), color, transparency)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Rotation = math.deg(math.atan2(d.Y, d.X))
	return f
end

local function direction(degrees: number): Vector2
	local a = math.rad(degrees)
	return Vector2.new(math.sin(a), -math.cos(a))
end

-- Przerywany okrąg z `count` kresek
local function dashRing(parent: Instance, center: Vector2, radius: number, count: number, length: number, thickness: number, color: Color3, transparency: number, tinted: boolean): { Frame }
	local dashes = {}
	for i = 0, count - 1 do
		local angle = i / count * 360
		local p = center + direction(angle) * radius
		local f = frame(parent, "Dash", at(p.X, p.Y), at(length, thickness), color, transparency)
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Rotation = angle
		if tinted then
			table.insert(tintFrames, f)
		end
		table.insert(dashes, f)
	end
	return dashes
end

local function rune(parent: Instance, glyph: { number }, center: Vector2, angle: number, height: number, transparency: number)
	local s = height / 10
	local box = frame(parent, "Rune", at(center.X, center.Y), at(6 * s, 10 * s))
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Rotation = angle
	for i = 1, #glyph, 4 do
		local line = segment(box, Vector2.new(glyph[i], glyph[i + 1]) * s, Vector2.new(glyph[i + 2], glyph[i + 3]) * s, math.max(1.3, s * 1.1), C.rune, transparency)
		table.insert(tintFrames, line)
	end
end

-- Zanikanie całej grupy: zapamiętuje przezroczystości z chwili budowy i mnoży je przez `alpha`
local function collect(root: Instance, skip: { Instance }?): Fade
	local out: Fade = {}
	local function skipped(inst: Instance): boolean
		for _, s in (skip or {}) :: { Instance } do
			if inst == s or inst:IsDescendantOf(s) then
				return true
			end
		end
		return false
	end
	local function add(inst: Instance)
		if skipped(inst) then
			return
		end
		if inst:IsA("UIStroke") then
			table.insert(out, { inst = inst, prop = "Transparency", base = inst.Transparency })
		elseif inst:IsA("GuiObject") then
			if inst.BackgroundTransparency < 1 then
				table.insert(out, { inst = inst, prop = "BackgroundTransparency", base = inst.BackgroundTransparency })
			end
			if inst:IsA("TextLabel") or inst:IsA("TextButton") then
				table.insert(out, { inst = inst, prop = "TextTransparency", base = inst.TextTransparency })
			elseif inst:IsA("ImageLabel") then
				table.insert(out, { inst = inst, prop = "ImageTransparency", base = inst.ImageTransparency })
			end
		end
	end
	add(root)
	for _, d in root:GetDescendants() do
		add(d)
	end
	return out
end

local function setAlpha(fade: Fade, alpha: number)
	for _, entry in fade do
		(entry.inst :: any)[entry.prop] = 1 - (1 - entry.base) * alpha
	end
end

-- ===== Okno =====

local window = PanelKit.window({
	name = "Forge",
	parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	width = math.floor(W * K),
	height = math.floor(H * K),
	ribbon = Color3.fromRGB(120, 80, 200),
	icon = "fertilizer",
	pillIcon = "coins",
	pillColor = C.cardTop,
})

local function isOpen(): boolean
	return window.isOpen()
end

-- Wygląd jak w projekcie: ciemnozielone tło, bez wstążki (tytuł jest w opisie)
do
	local f = window.frame
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	local shade = f:FindFirstChild("Shade")
	if shade and shade:IsA("UIGradient") then
		shade.Color = ColorSequence.new(Color3.fromHex("12261c"), Color3.fromHex("060d09"))
	end
	local outer = f:FindFirstChildOfClass("UIStroke")
	if outer then
		outer.Color = Color3.fromHex("050a07")
	end
	local inner = f:FindFirstChild("Inner")
	local innerStroke = if inner then inner:FindFirstChildOfClass("UIStroke") else nil
	if innerStroke then
		innerStroke.Color = C.line
	end
	local ribbon = window.title.Parent
	if ribbon and ribbon:IsA("GuiObject") then
		ribbon.Visible = false
	end
end

local root = frame(window.frame, "ForgeUI", at(0, 0), at(W, H))
root.ZIndex = 3
new("UIScale", { Scale = K }, root)

-- Grzybek z aurą (MushroomArt); bez arkusza emotka. Budowany od nowa tylko po zmianie grzyba.
local function drawArt(box: Frame, item: Item?, dim: boolean)
	local key = if item then signature(item) .. "|" .. tostring(dim) else ""
	if box:GetAttribute("ArtKey") == key then
		return
	end
	box:SetAttribute("ArtKey", key)
	box:ClearAllChildren()
	if not item then
		return
	end
	local still = function(): boolean
		return false
	end
	local art = MushroomArt.build(box, item :: any, { active = if dim then still else isOpen })
	if art then
		if dim then
			for _, d in art:GetDescendants() do
				if d:IsA("ImageLabel") then
					d.ImageTransparency = 0.6
				end
			end
		end
		return
	end
	local icon = label(box, "Icon", at(0, 0), UDim2.fromScale(1, 1), 60, Color3.new(1, 1, 1))
	icon.Text = "🍄"
	icon.TextTransparency = if dim then 0.6 else 0
end

-- ----- Opis z szansami -----

type Chip = { frame: Frame, text: TextLabel, edge: UIStroke }

local function chip(parent: Instance, order: number): Chip
	local f = frame(parent, "Chip", at(0, 0), UDim2.new(0, 0, 0, 26), C.cardTop)
	f.AutomaticSize = Enum.AutomaticSize.X
	f.LayoutOrder = order
	corner(f)
	local edge = stroke(f, C.line, 1.5)
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, f)
	local text = new("TextLabel", {
		Name = "Text",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		FontFace = BODY,
		TextSize = 15,
		Text = "",
	}, f)
	return { frame = f, text = text, edge = edge }
end

local function paintChip(c: Chip, look: { Color3 }, text: string?)
	c.frame.Visible = text ~= nil
	c.frame.BackgroundColor3 = look[1]
	c.edge.Color = look[2]
	c.text.TextColor3 = look[3]
	c.text.Text = text or ""
end

local function buildAbout()
	local about = card(root, "About", at(32, 28), at(800, 104))
	local title = label(about, "Title", at(20, 12), at(430, 36), 28, C.gold, TITLE, Enum.TextXAlignment.Left)
	local desc = label(about, "Desc", at(20, 50), at(440, 44), 16, C.muted, BODY_BOLD, Enum.TextXAlignment.Left)
	desc.TextWrapped = true
	desc.TextYAlignment = Enum.TextYAlignment.Top
	local function row(y: number): Frame
		local r = frame(about, "Chips", at(466, y), at(318, 28))
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, r)
		return r
	end
	local odds = row(14)
	return {
		title = title,
		desc = desc,
		chips = { chip(odds, 1), chip(odds, 2), chip(odds, 3) },
		mutation = chip(row(56), 1),
	}
end
local aboutUi = buildAbout()

-- ----- Scena z runą -----

type Particle = { dot: Frame, left: number, top: number, size: number, delay: number, duration: number }

local function buildScene()
	local scene = frame(root, "Scene", at(32, 144), at(SCENE_W, SCENE_H), C.sceneBg)
	corner(scene, UDim.new(0, 14))
	stroke(scene, C.line, 1.5)
	scene.ClipsDescendants = true
	local stage = frame(scene, "Stage", at(0, 0), at(SCENE_W, SCENE_H))
	UiFx.glow(stage, 760, C.sceneMid, 0.7, 1)

	-- Zewnętrzny pierścień run
	local ringA = frame(stage, "RingOuter", at(CENTER.X, CENTER.Y), at(440, 440))
	ringA.AnchorPoint = Vector2.new(0.5, 0.5)
	ringA.ZIndex = 2
	local ca = Vector2.new(220, 220)
	dashRing(ringA, ca, 212, 110, 3, 1.5, C.rune, 0.3, true)
	local solid = frame(ringA, "Ring", at(220, 220), at(376, 376))
	solid.AnchorPoint = Vector2.new(0.5, 0.5)
	corner(solid)
	table.insert(tintStrokes, stroke(solid, C.rune, 1, 0.55))
	for i, glyph in OUTER_RUNES do
		local angle = (i - 1) * 30
		rune(ringA, glyph, ca + direction(angle) * 196, angle, 17, 0.1)
	end

	-- Drugi, przeciwny pierścień
	local ringB = frame(stage, "RingInner", at(CENTER.X, CENTER.Y), at(320, 320))
	ringB.AnchorPoint = Vector2.new(0.5, 0.5)
	ringB.ZIndex = 3
	local cb = Vector2.new(160, 160)
	dashRing(ringB, cb, 150, 39, 14, 1, C.rune, 0.5, true)
	for i, glyph in INNER_RUNES do
		local angle = (i - 1) * 45
		rune(ringB, glyph, cb + direction(angle) * 140, angle, 12, 0.4)
	end
	local ringFade = collect(ringA)
	for _, entry in collect(ringB) do
		table.insert(ringFade, entry)
	end

	-- Obracający się układ: trójkąt (miejsca dokłada buildSlots)
	local rig = frame(stage, "Rig", at(CENTER.X, CENTER.Y), at(400, 400))
	rig.AnchorPoint = Vector2.new(0.5, 0.5)
	rig.ZIndex = 4
	local tri = frame(rig, "Triangle", at(200, 200), at(400, 400))
	tri.AnchorPoint = Vector2.new(0.5, 0.5)
	local triScale = new("UIScale", {}, tri) :: UIScale
	local glowLines: { { line: Frame, strength: number } } = {}
	local glowSet: { [Instance]: boolean } = {}
	for i = 1, 3 do
		local a, b = VERTS[i], VERTS[i % 3 + 1]
		for _, spec in { { 18, 0.16 }, { 9, 0.3 } } do
			local glow = segment(tri, a, b, spec[1], C.rune, 1)
			table.insert(tintFrames, glow)
			table.insert(glowLines, { line = glow, strength = spec[2] })
			glowSet[glow] = true
		end
	end
	for i = 1, 3 do
		local a, b = VERTS[i], VERTS[i % 3 + 1]
		table.insert(tintFrames, segment(tri, a, b, 3, C.rune, 0))
		segment(tri, RIG_CENTER + (a - RIG_CENTER) * 0.94, RIG_CENTER + (b - RIG_CENTER) * 0.94, 1, Color3.fromHex("fff6d8"), 0.5)
		table.insert(tintFrames, segment(tri, RIG_CENTER + (a - RIG_CENTER).Unit * 85, a, 1, C.rune, 0.65))
	end
	local hub = frame(tri, "Hub", at(200, 200), at(170, 170), C.hub, 0.45)
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	corner(hub)
	table.insert(tintStrokes, stroke(hub, C.rune, 2.5))
	dashRing(tri, RIG_CENTER, 72, 56, 2, 1, C.rune, 0.3, true)
	-- Poświaty kresek mają własną siłę (zależy od fazy), więc nie są w zwykłym zanikaniu
	local triFade: Fade = {}
	for _, entry in collect(tri) do
		if not glowSet[entry.inst] then
			table.insert(triFade, entry)
		end
	end

	-- Środek runy: wkład przed połączeniem
	local center = frame(stage, "Center", at(CENTER.X, CENTER.Y), at(170, 170))
	center.AnchorPoint = Vector2.new(0.5, 0.5)
	center.ZIndex = 5
	local centerTitle = label(center, "Title", at(0, 36), at(170, 18), 15, C.sub, BODY)
	local centerValue = label(center, "Value", at(8, 56), at(154, 44), 34, C.pale, TITLE)
	local centerHint = label(center, "Hint", at(12, 104), at(146, 20), 15, C.sub, BODY_BOLD)

	-- Bęben w środku
	local reelGlow = UiFx.glow(stage, 250, C.rune, 0.45, 6)
	reelGlow.Position = at(CENTER.X, CENTER.Y)
	local reel = frame(stage, "Reel", at(CENTER.X, CENTER.Y), at(170, 170), Color3.fromHex("0f1f17"))
	reel.AnchorPoint = Vector2.new(0.5, 0.5)
	reel.ZIndex = 7
	corner(reel)
	local reelStroke = stroke(reel, C.rune, 3)
	local reelArt = frame(reel, "Art", at(85, 85), at(104, 104))
	reelArt.AnchorPoint = Vector2.new(0.5, 0.5)
	local reelScale = new("UIScale", {}, reelArt) :: UIScale

	-- Cząsteczki lecące w górę (jak w projekcie: 16 kropek, każda w swoim rytmie)
	local particleLayer = frame(stage, "Particles", at(0, 0), at(SCENE_W, SCENE_H))
	particleLayer.ZIndex = 8
	local particles: { Particle } = {}
	for i = 0, 15 do
		local size = 3 + i % 4
		local dot = frame(particleLayer, "Dot", at(0, 0), at(size, size), C.rune, 1)
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		corner(dot)
		table.insert(particles, {
			dot = dot,
			left = 40 + (i * 47) % 720,
			top = 380 - (i % 3) * 30,
			size = size,
			delay = (i * 0.37) % 2.4,
			duration = 2.4 + (i % 5) * 0.5,
		})
	end

	-- Błysk: rozbłysk w kolorze wyniku i dwie fale
	local flash = frame(stage, "Flash", at(0, 0), at(SCENE_W, SCENE_H))
	flash.ZIndex = 9
	local flashTint = UiFx.glow(flash, 980, C.rune, 0.75, 1)
	UiFx.glow(flash, 380, Color3.new(1, 1, 1), 0.95, 2)
	local function shock(thickness: number, color: Color3): (Frame, UIStroke, UIScale)
		local ring = frame(flash, "Shock", at(CENTER.X, CENTER.Y), at(200, 200))
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.ZIndex = 3
		corner(ring)
		return ring, stroke(ring, color, thickness), new("UIScale", {}, ring) :: UIScale
	end
	local shockA, shockAStroke, shockAScale = shock(4, C.rune)
	local shockB, shockBStroke, shockBScale = shock(2, Color3.new(1, 1, 1))

	return {
		stage = stage,
		ringA = ringA,
		ringB = ringB,
		ringFade = ringFade,
		rig = rig,
		tri = tri,
		triScale = triScale,
		glowLines = glowLines,
		triFade = triFade,
		center = center,
		centerTitle = centerTitle,
		centerValue = centerValue,
		centerHint = centerHint,
		centerFade = collect(center),
		reelGlow = reelGlow,
		reel = reel,
		reelStroke = reelStroke,
		reelArt = reelArt,
		reelScale = reelScale,
		particleLayer = particleLayer,
		particles = particles,
		flash = flash,
		flashTint = flashTint,
		-- Fale mają własną przezroczystość (liczoną w `step`), rozbłysk zanika całą grupą
		flashFade = collect(flash, { shockA, shockB }),
		shockAStroke = shockAStroke,
		shockAScale = shockAScale,
		shockBStroke = shockBStroke,
		shockBScale = shockBScale,
	}
end
local sceneUi = buildScene()

-- ----- Odsłonięcie wyniku -----

local LOG_LO, LOG_SPAN = math.log(0.05), math.log(6 / 0.05)
local function scalePos(ratio: number): number
	return math.clamp((math.log(math.clamp(ratio, 0.05, 6)) - LOG_LO) / LOG_SPAN, 0, 1)
end

local function buildResult()
	local reveal = frame(sceneUi.stage, "Reveal", at(0, 0), at(SCENE_W, SCENE_H))
	reveal.ZIndex = 10
	local showBox = frame(reveal, "Show", at(34, 36), at(290, 380))
	local rays = UiFx.rays(showBox, { size = 420, color = C.rune, count = 4, speed = 20, transparency = 0.55, zIndex = 1, position = at(145, 190) })
	local shadow = frame(showBox, "Shadow", at(145, 321), at(210, 34), C.rune, 0.35)
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.ZIndex = 2
	corner(shadow)
	new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, shadow)
	local glow = UiFx.glow(showBox, 300, C.rune, 0.35, 3)
	glow.Position = at(145, 190)
	local pop = frame(showBox, "Pop", at(145, 190), at(250, 250))
	pop.AnchorPoint = Vector2.new(0.5, 0.5)
	pop.ZIndex = 4
	local popScale = new("UIScale", {}, pop) :: UIScale
	local spin = frame(pop, "Spin", at(125, 125), at(250, 250))
	spin.AnchorPoint = Vector2.new(0.5, 0.5)
	local art = frame(spin, "Art", at(0, 0), UDim2.fromScale(1, 1))

	local info = frame(reveal, "Info", at(358, 0), at(408, 452))
	local badge = frame(info, "Badge", at(0, 51), UDim2.new(0, 0, 0, 28), C.rune)
	badge.AutomaticSize = Enum.AutomaticSize.X
	corner(badge)
	new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, badge)
	local badgeText = new("TextLabel", {
		Name = "Text",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		FontFace = BODY,
		TextSize = 16,
		TextColor3 = C.badgeText,
		Text = "",
	}, badge) :: TextLabel
	local badgeRainbow = UiFx.rainbow(badge, 0.2)
	local name = label(info, "Name", at(0, 86), at(408, 42), 32, C.name, TITLE, Enum.TextXAlignment.Left)

	local function cell(x: number, y: number, valueFont: Font, valueSize: number): (TextLabel, TextLabel)
		local box = frame(info, "Cell", at(x, y), at(200, 62), C.cell)
		corner(box, UDim.new(0, 10))
		stroke(box, C.line, 1.5)
		local title = label(box, "Title", at(12, 7), at(180, 16), 14, C.sub, BODY, Enum.TextXAlignment.Left)
		local value = label(box, "Value", at(12, 25), at(180, 30), valueSize, C.pale, valueFont, Enum.TextXAlignment.Left)
		return title, value
	end
	local valueTitle, valueText = cell(0, 139, TITLE, 24)
	local inputTitle, inputText = cell(208, 139, TITLE, 24)
	local mutationTitle, mutationText = cell(0, 209, BODY, 19)
	local feeTitle, feeText = cell(208, 209, BODY, 19)
	local mutationRainbow = UiFx.rainbow(mutationText, 0.25)
	local tagsTitle = label(info, "TagsTitle", at(0, 283), at(408, 16), 14, C.sub, BODY, Enum.TextXAlignment.Left)
	local tagsRow = frame(info, "Tags", at(0, 305), at(408, 26))
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, tagsRow)

	-- Skala wkładu: progi runy w skali logarytmicznej od 0,05× do 6×
	local scaleTitle = label(info, "ScaleTitle", at(0, 343), at(408, 16), 14, C.sub, BODY, Enum.TextXAlignment.Left)
	local scaleBar = frame(info, "Scale", at(0, 365), at(408, 14))
	for i, tier in Config.Forge.tiers do
		local x0, x1 = scalePos(tier.lo), scalePos(tier.hi)
		local seg = frame(scaleBar, "Tier" .. i, UDim2.new(x0, if i > 1 then 1 else 0, 0, 0), UDim2.new(x1 - x0, if i > 1 then -2 else -1, 1, 0), rgb(tier.color))
		corner(seg, UDim.new(0, 4))
		if tier.id == "great" then
			UiFx.rainbow(seg, 0.15)
		end
	end
	local marker = frame(scaleBar, "Marker", at(0, -6), at(4, 26), Color3.new(1, 1, 1))
	marker.AnchorPoint = Vector2.new(0.5, 0)
	corner(marker, UDim.new(0, 2))
	stroke(marker, Color3.new(1, 1, 1), 3, 0.6)
	local ticks: { { label: TextLabel, mark: number } } = {}
	for _, mark in { 0.05, 0.4, 1, 2.5, 6 } do
		local tick = label(info, "Tick", UDim2.new(0, 408 * scalePos(mark), 0, 385), at(48, 16), 13, C.dim, BODY_BOLD)
		tick.AnchorPoint = Vector2.new(if mark == 0.05 then 0 elseif mark == 6 then 1 else 0.5, 0)
		tick.TextXAlignment = if mark == 0.05 then Enum.TextXAlignment.Left elseif mark == 6 then Enum.TextXAlignment.Right else Enum.TextXAlignment.Center
		table.insert(ticks, { label = tick, mark = mark })
	end

	return {
		reveal = reveal,
		showBox = showBox,
		rays = rays,
		shadow = shadow,
		glow = glow,
		pop = pop,
		popScale = popScale,
		spin = spin,
		art = art,
		info = info,
		badge = badge,
		badgeText = badgeText,
		badgeRainbow = badgeRainbow,
		name = name,
		valueTitle = valueTitle,
		valueText = valueText,
		inputTitle = inputTitle,
		inputText = inputText,
		mutationTitle = mutationTitle,
		mutationText = mutationText,
		mutationRainbow = mutationRainbow,
		feeTitle = feeTitle,
		feeText = feeText,
		tagsTitle = tagsTitle,
		tagsRow = tagsRow,
		scaleTitle = scaleTitle,
		marker = marker,
		ticks = ticks,
	}
end
local resultUi = buildResult()
local infoFade: Fade = {}

-- ----- Dolny pasek -----

local function buildBar()
	local bar = card(root, "Bar", at(32, 608), at(800, 84))
	local status = label(bar, "Status", at(18, 10), at(420, 64), 17, C.muted, BODY_BOLD, Enum.TextXAlignment.Left)
	status.TextWrapped = true
	local fuse = new("TextButton", {
		Name = "Fuse",
		Position = at(534, 13),
		Size = at(250, 58),
		AutoButtonColor = false,
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.new(1, 1, 1),
		FontFace = BODY,
		TextSize = 21,
		Text = "",
		TextColor3 = C.buttonText,
	}, bar) :: TextButton
	corner(fuse, UDim.new(0, 12))
	return {
		status = status,
		feeLabel = label(bar, "FeeTitle", at(440, 18), at(86, 16), 14, C.sub, BODY, Enum.TextXAlignment.Right),
		feeValue = label(bar, "Fee", at(430, 36), at(96, 28), 22, C.pale, TITLE, Enum.TextXAlignment.Right),
		fuse = fuse,
		fuseShade = new("UIGradient", { Rotation = 90 }, fuse) :: UIGradient,
		fuseGlow = stroke(fuse, C.rune, 3, 0.55),
	}
end
local barUi = buildBar()

-- ----- Koszyk -----

local function buildBasket()
	local box = card(root, "Basket", at(848, 28), at(400, 664))
	frame(box, "Line", at(0, 56), at(400, 1.5), C.line)
	local list = new("ScrollingFrame", {
		Name = "Inventory",
		Position = at(0, 58),
		Size = at(400, 604),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.line,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, box) :: ScrollingFrame
	new("UIGridLayout", { CellSize = at(112, 122), CellPadding = at(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 14),
		PaddingBottom = UDim.new(0, 14),
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 18),
	}, list)
	local veil = frame(box, "Veil", at(0, 58), at(400, 604), C.cardBottom, 1)
	veil.ZIndex = 5
	local empty = label(box, "Empty", at(40, 220), at(320, 80), 18, C.sub, BODY_BOLD)
	empty.TextWrapped = true
	return {
		title = label(box, "Title", at(18, 12), at(160, 32), 22, C.gold, TITLE, Enum.TextXAlignment.Left),
		info = label(box, "Info", at(150, 18), at(208, 20), 15, C.sub, BODY_BOLD, Enum.TextXAlignment.Right),
		list = list,
		veil = veil,
		empty = empty,
	}
end
local basketUi = buildBasket()

-- ===== Stan =====

local basket: { Item } = {}
local basketKey = ""
local pendingBasket: { items: { Item }, key: string }? = nil -- stan z serwera, który przyszedł w czasie łączenia
local coins = 0
local access: Forge.Access = {}
local found: { [string]: number } = {}
local chosen: { number } = {} -- indeksy koszyka w kolejności wrzucenia (najwyżej 3)
local phase: Phase = "idle"
local phaseAt = 0
local chargeAt = 0
local reelAt = 0
local token = 0
local waiting = false
local readyAt = 0 -- moździerz stygnie (Config.Forge.cooldown) do tej chwili
-- Wrzucone grzyby (serwer już je zabrał), wkład, opłata i szanse do animacji i karty wyniku
local sent: { items: { Item }, value: number, fee: number, preview: Forge.Preview }? = nil
local result: { item: Item, kind: string }? = nil
local revealColor = C.rune
local hint: { text: string, untilAt: number }? = nil
local cache: { key: string, preview: Forge.Preview? }? = nil

local function busy(): boolean
	return phase ~= "idle" and phase ~= "reveal"
end

local function chosenItems(): { Item }
	local items = {}
	for _, index in chosen do
		local item = basket[index]
		if item then
			table.insert(items, item)
		end
	end
	return items
end

-- Podgląd trójki z miejsc (liczony raz na zmianę grzybów)
local function currentPreview(): Forge.Preview?
	local items = chosenItems()
	if #items ~= Forge.SLOTS then
		return nil
	end
	local key = table.concat({
		signature(items[1]),
		signature(items[2]),
		signature(items[3]),
		tostring(access.swampUnlocked),
		tostring(access.mountainUnlocked),
		tostring(access.jagaEscapes),
	}, "/")
	if not cache or cache.key ~= key then
		cache = { key = key, preview = (Forge.preview(items, access)) }
	end
	return (cache :: any).preview
end

-- ----- Kafelki koszyka -----

type Tile = { button: TextButton, edge: UIStroke, rainbow: UIGradient?, badge: Frame, badgeText: TextLabel, index: number, rank: number }
local tiles: { Tile } = {}
local tilesKey: string? = nil

local toggle: (number) -> ()
local render: () -> ()

local function rebuildTiles()
	for _, tile in tiles do
		tile.button:Destroy()
	end
	tiles = {}
	tilesKey = basketKey
	local order = {}
	for index in basket do
		table.insert(order, index)
	end
	-- Najpierw te, które można wrzucić, od najcenniejszego
	table.sort(order, function(a, b)
		local ea = (Forge.eligible(basket[a]))
		local eb = (Forge.eligible(basket[b]))
		if ea ~= eb then
			return ea
		end
		local va, vb = Economy.itemValue(basket[a] :: any), Economy.itemValue(basket[b] :: any)
		if va ~= vb then
			return va > vb
		end
		return a < b
	end)
	for position, index in order do
		local item = basket[index]
		local ok = (Forge.eligible(item))
		local rank = Economy.variantRank(item.v)
		local button = new("TextButton", {
			Name = "Item" .. index,
			LayoutOrder = position,
			Text = "",
			AutoButtonColor = false,
			BorderSizePixel = 0,
			BackgroundColor3 = if ok then C.tile else C.locked,
		}, basketUi.list) :: TextButton
		corner(button, UDim.new(0, 12))
		local edge = stroke(button, edgeColor(rank), 2)
		local rainbow: UIGradient? = nil
		if rank == 3 then
			edge.Color = Color3.new(1, 1, 1)
			rainbow = UiFx.rainbow(edge, 0.2)
		end
		local art = frame(button, "Art", UDim2.new(0.5, 0, 0, 8), at(54, 54))
		art.AnchorPoint = Vector2.new(0.5, 0)
		drawArt(art, item, not ok)
		local name = label(button, "Name", at(5, 64), at(102, 18), 14, if ok then C.tileText else C.dim, BODY)
		name.Text = itemName(item)
		local value = label(button, "Value", at(5, 82), at(102, 16), 14, if ok then C.gold else C.dim, BODY)
		value.Text = if ok then "💰 " .. short(Economy.itemValue(item :: any)) else "🔒"
		local dots = frame(button, "Tags", at(0, 102), at(112, 10))
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 3),
		}, dots)
		for _, id in (item.x or {}) :: { string } do
			local tag = Economy.getTag(id)
			if tag then
				corner(frame(dots, "Dot", at(0, 0), at(9, 9), rgb(tag.color)))
			end
		end
		local badge = frame(button, "Badge", UDim2.new(1, 6, 0, -8), at(26, 26), C.rune)
		badge.AnchorPoint = Vector2.new(1, 0)
		badge.ZIndex = 3
		badge.Visible = false
		corner(badge)
		local numeral = label(badge, "Text", at(0, 2), at(26, 22), 15, C.numeral, TITLE)
		button.Activated:Connect(function()
			toggle(index)
		end)
		table.insert(tiles, { button = button, edge = edge, rainbow = rainbow, badge = badge, badgeText = numeral, index = index, rank = rank })
	end
end

-- ----- Trzy miejsca w rogach trójkąta -----

type SlotView = {
	holder: Frame,
	spinner: Frame,
	scale: UIScale,
	button: TextButton,
	ring: UIStroke,
	rainbow: UIGradient,
	dashes: Frame,
	art: Frame,
	numeral: TextLabel,
	drop: TextLabel,
	name: TextLabel,
	value: TextLabel,
	fade: Fade,
}
local RAINBOW_EDGE = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromHex("ff6b6b")),
	ColorSequenceKeypoint.new(0.25, Color3.fromHex("ffd93d")),
	ColorSequenceKeypoint.new(0.5, Color3.fromHex("6bff95")),
	ColorSequenceKeypoint.new(0.75, Color3.fromHex("6bc7ff")),
	ColorSequenceKeypoint.new(1, Color3.fromHex("c36bff")),
})

local function buildSlots(): { SlotView }
	local views: { SlotView } = {}
	for slot = 1, Forge.SLOTS do
		local v = VERTS[slot]
		local holder = frame(sceneUi.rig, "Slot" .. slot, at(v.X, v.Y), at(96, 96))
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.ZIndex = 3
		local scale = new("UIScale", {}, holder) :: UIScale
		local spinner = frame(holder, "Spin", at(48, 48), at(96, 96))
		spinner.AnchorPoint = Vector2.new(0.5, 0.5)
		local button = new("TextButton", {
			Name = "Slot",
			Size = at(96, 96),
			Text = "",
			AutoButtonColor = false,
			BorderSizePixel = 0,
			BackgroundColor3 = C.tile,
		}, spinner) :: TextButton
		corner(button)
		local ring = stroke(button, C.tileEdge, 3)
		local rainbow = new("UIGradient", { Enabled = false, Color = RAINBOW_EDGE }, ring) :: UIGradient
		local dashes = frame(button, "Dashes", at(0, 0), at(96, 96))
		dashRing(dashes, Vector2.new(48, 48), 47, 24, 6, 2, C.empty, 0, false)
		local art = frame(button, "Art", at(48, 48), at(64, 64))
		art.AnchorPoint = Vector2.new(0.5, 0.5)
		local numeral = label(button, "Numeral", at(0, 20), at(96, 30), 24, C.dim, TITLE)
		numeral.Text = NUMERALS[slot]
		local drop = label(button, "Drop", at(0, 52), at(96, 16), 13, C.dim, BODY)
		local name = label(spinner, "Name", at(-52, 104), at(200, 18), 14, C.tileText, BODY)
		local value = label(spinner, "Value", at(-52, 122), at(200, 16), 14, C.rune, BODY)
		UiKit.outline(name, 1.5, Color3.new(0, 0, 0))
		UiKit.outline(value, 1.5, Color3.new(0, 0, 0))
		button.Activated:Connect(function()
			if phase ~= "idle" or not chosen[slot] then
				return
			end
			table.remove(chosen, slot)
			Audio.play("click")
			render()
		end)
		table.insert(views, {
			holder = holder,
			spinner = spinner,
			scale = scale,
			button = button,
			ring = ring,
			rainbow = rainbow,
			dashes = dashes,
			art = art,
			numeral = numeral,
			drop = drop,
			name = name,
			value = value,
			fade = collect(holder, { art }),
		})
	end
	return views
end
local slotViews = buildSlots()

-- ===== Rysowanie stanu =====

local function setRuneColor(color: Color3)
	for _, f in tintFrames do
		f.BackgroundColor3 = color
	end
	for _, s in tintStrokes do
		s.Color = color
	end
	for _, p in sceneUi.particles do
		p.dot.BackgroundColor3 = color
	end
end

local function recolorGlow(holder: Frame, color: Color3)
	for _, ring in holder:GetChildren() do
		if ring:IsA("Frame") then
			ring.BackgroundColor3 = color
		end
	end
end

local function renderChips(preview: Forge.Preview?)
	local chips = aboutUi.chips
	local match = preview and preview.match
	if preview and match then
		local text = if (found[match.id] or 0) > 0
			then t("FORGE_CHIP_RECIPE", { speciesName(match.id), percent(preview.recipeHit) })
			else t("FORGE_CHIP_SENSE", { percent(preview.recipeHit) })
		paintChip(chips[1], CHIP.recipe, text)
		paintChip(chips[2], CHIP.rune, t("FORGE_CHIP_RUNE", { percent(1 - preview.recipeHit) }))
		paintChip(chips[3], CHIP.rune, nil)
	else
		local odds: { [string]: number } = {}
		if preview then
			odds = preview.odds
		else
			for _, tier in Config.Forge.tiers do
				odds[tier.id] = tier.chance
			end
		end
		local worse = (odds.bust or 0) + (odds.worse or 0)
		local better = (odds.better or 0) + (odds.great or 0)
		paintChip(chips[1], CHIP.worse, t("FORGE_CHIP_WORSE", { percent(worse) }))
		paintChip(chips[2], CHIP.similar, t("FORGE_CHIP_SIMILAR", { percent(odds.similar or 0) }))
		paintChip(chips[3], CHIP.better, t("FORGE_CHIP_BETTER", { percent(better) }))
	end
	paintChip(aboutUi.mutation, CHIP.mutation, t("FORGE_CHIP_MUTATION", { if preview then percent(preview.mutation, 1) else "–" }))
end

local function renderSlots()
	-- W czasie łączenia miejsca pokazują wysłane grzyby (koszyk z serwera już ich nie ma)
	local items = if sent and phase ~= "idle" then sent.items else chosenItems()
	for slot, view in slotViews do
		local item = items[slot]
		local rank = if item then Economy.variantRank(item.v) else 0
		view.dashes.Visible = item == nil
		view.numeral.Visible = item == nil
		view.drop.Visible = item == nil
		view.drop.Text = t("FORGE_SLOT_DROP")
		view.button.BackgroundColor3 = if item then C.tile else C.slotEmpty
		view.button.BackgroundTransparency = if item then 0 else 0.3
		view.ring.Transparency = if item then 0 else 1
		view.ring.Color = if rank == 3 then Color3.new(1, 1, 1) else edgeColor(rank)
		view.rainbow.Enabled = rank == 3
		view.name.Visible = item ~= nil
		view.value.Visible = item ~= nil
		if item then
			view.name.Text = itemName(item)
			view.value.Text = formatCoins(Economy.itemValue(item :: any))
		end
		drawArt(view.art, item, false)
		-- Wygląd się zmienił: przezroczystości do zanikania zapamiętujemy od nowa
		view.fade = collect(view.holder, { view.art })
	end
end

local function renderInventory()
	if tilesKey ~= basketKey and phase == "idle" then
		rebuildTiles()
	end
	local count = 0
	for _, item in basket do
		if Forge.eligible(item) then
			count += 1
		end
	end
	local picked = if sent and phase ~= "idle" then Forge.SLOTS else #chosen
	basketUi.info.Text = t("FORGE_BASKET_INFO", { count, picked })
	basketUi.empty.Visible = #basket == 0
	basketUi.empty.Text = t("FORGE_INVENTORY_EMPTY")
	basketUi.veil.BackgroundTransparency = if busy() then 0.45 else 1
	for _, tile in tiles do
		local slot = table.find(chosen, tile.index)
		local inSlot = slot ~= nil and phase == "idle"
		tile.badge.Visible = inSlot
		tile.badgeText.Text = if slot then NUMERALS[slot] else ""
		if tile.rainbow then
			tile.rainbow.Enabled = not inSlot
		end
		tile.edge.Color = if inSlot then C.rune elseif tile.rank == 3 then Color3.new(1, 1, 1) else edgeColor(tile.rank)
		tile.edge.Thickness = if inSlot then 3 else 2
	end
end

local function renderButton(preview: Forge.Preview?)
	local fuse = barUi.fuse
	local active = false
	if phase == "reveal" then
		fuse.Text = t("FORGE_COLLECT")
		barUi.fuseShade.Color = ColorSequence.new(Color3.fromHex("8ff0b3"), Color3.fromHex("3fbf72"))
		active = true
	elseif busy() or waiting then
		fuse.Text = t("FORGE_FUSING")
	else
		fuse.Text = t("FORGE_FUSE")
		active = preview ~= nil and coins >= preview.fee and os.clock() >= readyAt
		barUi.fuseShade.Color = ColorSequence.new(Color3.fromHex("ffe49a"), Color3.fromHex("e5a93a"))
	end
	fuse.Active = active
	barUi.fuseShade.Enabled = active
	fuse.BackgroundColor3 = if active then Color3.new(1, 1, 1) else C.buttonOff
	fuse.TextColor3 = if active then C.buttonText else C.buttonOffText
	barUi.fuseGlow.Transparency = if active then 0.5 else 1
end

local function statusText(preview: Forge.Preview?): string
	local now = os.clock()
	if hint and now < hint.untilAt then
		return hint.text
	end
	if phase == "reveal" then
		return t("FORGE_STATUS_DONE")
	elseif busy() or waiting then
		return t("FORGE_STATUS_BUSY")
	end
	local picked = #chosenItems()
	if picked == 0 then
		return t("FORGE_STATUS_PICK", { Config.Forge.maxTags })
	elseif not preview then
		return t("FORGE_STATUS_MORE", { picked, Forge.SLOTS - picked })
	elseif coins < preview.fee then
		return t("FORGE_NO_COINS", { formatCoins(preview.fee - coins) })
	elseif now < readyAt then
		return t("FORGE_COOLDOWN", { math.ceil(readyAt - now) })
	end
	local match = preview.match
	if match then
		if (found[match.id] or 0) > 0 then
			return t("FORGE_STATUS_RECIPE", { speciesName(match.id), percent(preview.recipeHit), percent(preview.recipeLucky) })
		end
		return t("FORGE_STATUS_SENSE")
	end
	-- Wkład droższy niż wszystko, co rośnie: runa prawie zawsze odda mniej
	if (preview.odds.similar or 0) + (preview.odds.better or 0) + (preview.odds.great or 0) < 0.05 then
		return t("FORGE_STATUS_TOO_RICH")
	end
	return t("FORGE_STATUS_READY")
end

render = function()
	if not isOpen() then
		return
	end
	window.title.Text = t("FORGE_TITLE")
	window.pillText.Text = formatCoins(coins)
	aboutUi.title.Text = t("FORGE_TITLE")
	aboutUi.desc.Text = t("FORGE_DESC")
	basketUi.title.Text = t("FORGE_BASKET")
	sceneUi.centerTitle.Text = t("FORGE_INPUT")
	resultUi.valueTitle.Text = t("FORGE_RES_VALUE")
	resultUi.inputTitle.Text = t("FORGE_RES_INPUT")
	resultUi.mutationTitle.Text = t("FORGE_RES_MUTATION")
	resultUi.feeTitle.Text = t("FORGE_RES_FEE")
	resultUi.tagsTitle.Text = t("FORGE_RES_TAGS")
	resultUi.scaleTitle.Text = t("FORGE_RES_SCALE")
	for _, tick in resultUi.ticks do
		tick.label.Text = decimal(string.format("%g", tick.mark)) .. "×"
	end

	renderInventory()
	-- W czasie zlotu miejsca znikają: ich wygląd (i zapamiętane przezroczystości) zmieniamy tylko przed nim
	if phase == "idle" or phase == "charge" then
		renderSlots()
	end
	local preview = if phase == "idle" then currentPreview() else nil
	local during = sent ~= nil and phase ~= "idle"
	-- W czasie łączenia i przy wyniku plakietki pokazują szanse wysłanej trójki
	renderChips(if preview then preview elseif sent and during then sent.preview else nil)
	-- Wkład w środku runy (też przy jednym i dwóch grzybach) i opłata
	local inputValue = 0
	for _, item in chosenItems() do
		inputValue += Economy.itemValue(item :: any)
	end
	sceneUi.centerValue.Text = formatCoins(if sent and during then sent.value else inputValue)
	sceneUi.centerHint.Text = t(if preview or during then "FORGE_CENTER_READY" else "FORGE_CENTER_PICK")
	local fee = if preview then preview.fee elseif sent and during then sent.fee else nil
	local base = if preview then preview.inputValue elseif sent and during then sent.value else 0
	barUi.feeLabel.Text = t("FORGE_FEE", { percent(if fee and base > 0 then fee / base else Config.Forge.feeShare) })
	barUi.feeValue.Text = if fee then formatCoins(fee) else "–"
	barUi.status.Text = statusText(preview)
	renderButton(preview)
end

-- ===== Fazy łączenia =====

local function setPhase(next: Phase)
	phase = next
	phaseAt = os.clock()
	local before = next == "idle" or next == "charge" or next == "converge"
	sceneUi.center.Visible = before
	sceneUi.reel.Visible = next == "reel" or next == "flash"
	sceneUi.reelGlow.Visible = sceneUi.reel.Visible
	sceneUi.flash.Visible = next == "flash"
	resultUi.reveal.Visible = next == "reveal"
	sceneUi.particleLayer.Visible = next == "charge" or next == "converge" or next == "reveal"
	for slot, view in slotViews do
		view.holder.Visible = before
		view.holder.Position = at(VERTS[slot].X, VERTS[slot].Y)
		view.scale.Scale = 1
		setAlpha(view.fade, 1)
		view.art.Visible = true
	end
	if next == "idle" or next == "charge" then
		setRuneColor(C.rune)
		setAlpha(sceneUi.centerFade, 1)
		setAlpha(sceneUi.ringFade, 1)
	end
	if next == "charge" then
		chargeAt = phaseAt
	elseif next == "reel" then
		reelAt = phaseAt
	elseif next == "flash" then
		setRuneColor(revealColor)
		recolorGlow(sceneUi.flashTint, revealColor)
		sceneUi.shockAStroke.Color = revealColor
		sceneUi.shockAStroke.Transparency = 1
		sceneUi.shockBStroke.Transparency = 1
		setAlpha(sceneUi.flashFade, 0)
	elseif next == "reveal" then
		setAlpha(infoFade, 0)
	end
	render()
end

local function applyPending()
	local fresh = pendingBasket
	if not fresh then
		return
	end
	pendingBasket = nil
	local old = basket
	basket = fresh.items
	basketKey = fresh.key
	if #chosen > 0 then
		-- Wrzucone grzyby szukamy po wyglądzie (indeksy mogły się przesunąć)
		local kept: { number } = {}
		for _, index in chosen do
			local wanted = signature(old[index])
			for j, item in basket do
				if wanted ~= "" and signature(item) == wanted and not table.find(kept, j) then
					table.insert(kept, j)
					break
				end
			end
		end
		chosen = kept
	end
end

local function finish()
	token += 1
	waiting = false
	sent = nil
	result = nil
	setPhase("idle")
	applyPending()
	render()
end

local function collectResult()
	if phase ~= "reveal" then
		return
	end
	chosen = {}
	Audio.play("coin", { volume = 0.6 })
	finish()
end

local function setReel(item: Item)
	drawArt(sceneUi.reelArt, item, false)
	local value = if sent then sent.value else 1
	local color = rgb(Forge.tierOf(Economy.itemValue(item :: any) / math.max(1, value)).color)
	sceneUi.reelStroke.Color = color
	recolorGlow(sceneUi.reelGlow, color)
end

local function randomReelItem(): Item
	return { s = Forge.POOL[math.random(1, #Forge.POOL)] }
end

-- Karta wyniku (budowana przed błyskiem, żeby błysk miał już kolor wyniku)
local function buildReveal(item: Item, kind: string)
	local ui = resultUi
	-- Przezroczystości karty z poprzedniego wyniku wracają do pełnych, zanim zapamiętamy je od nowa
	setAlpha(infoFade, 1)
	local inputValue = if sent then sent.value else 1
	local value = Economy.itemValue(item :: any)
	local ratio = value / math.max(1, inputValue)
	local tier = Forge.tier(kind)
	local look = RECIPE_LOOK[kind]
	revealColor = tierColor(kind)
	local headline = if tier then t(tier.key) elseif look then t(look.key) else kind
	ui.badgeText.Text = headline .. " · " .. ratioText(ratio)
	local rainbowBadge = kind == "great" or kind == "mythic" or kind == "secret"
	ui.badgeRainbow.Enabled = rainbowBadge
	ui.badge.BackgroundColor3 = if rainbowBadge then Color3.new(1, 1, 1) else revealColor
	ui.name.Text = speciesName(item.s)
	ui.valueText.Text = formatCoins(value)
	ui.inputText.Text = formatCoins(inputValue)
	ui.feeText.Text = formatCoins(if sent then sent.fee else 0)
	local variant = Economy.getVariant(item.v)
	ui.mutationRainbow.Enabled = variant ~= nil and variant.rank == 3
	if variant then
		ui.mutationText.Text = t(variant.key) .. " ×" .. decimal(tostring(variant.mult))
		ui.mutationText.TextColor3 = if variant.rank == 3 then Color3.new(1, 1, 1) elseif variant.rank >= 4 then C.cosmic else rgb(variant.color)
	else
		ui.mutationText.Text = t("FORGE_RES_NO_VARIANT")
		ui.mutationText.TextColor3 = C.muted
	end
	for _, child in ui.tagsRow:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local tags = (item.x or {}) :: { string }
	for order, id in tags do
		local tag = Economy.getTag(id)
		if tag then
			paintChip(chip(ui.tagsRow, order), { C.cell, rgb(tag.color), rgb(tag.color) }, tag.icon .. " " .. t(tag.key))
		end
	end
	if #tags == 0 then
		paintChip(chip(ui.tagsRow, 1), { C.cell, C.cell, C.dim }, t("FORGE_RES_NO_TAGS"))
	end
	ui.marker.Position = UDim2.new(scalePos(ratio), 0, 0, -6)
	recolorGlow(ui.rays, revealColor)
	recolorGlow(ui.glow, revealColor)
	ui.shadow.BackgroundColor3 = revealColor
	drawArt(ui.art, item, false)
	infoFade = collect(ui.info)
end

local function runFuse()
	token += 1
	local mine = token
	local function alive(): boolean
		return token == mine
	end
	task.spawn(function()
		setPhase("charge")
		Audio.play("cauldron", { volume = 0.8, duration = 2 })
		task.wait(1.1)
		if not alive() then
			return
		end
		setPhase("converge")
		Audio.play("whoosh", { volume = 0.7 })
		task.wait(0.8)
		if not alive() then
			return
		end
		setPhase("reel")
		-- Serwer odpowiada od razu; gdyby odpowiedź zginęła, po chwili wracamy do wyboru grzybów
		local giveUp = os.clock() + 5
		while not result do
			if not alive() then
				return
			end
			if os.clock() > giveUp then
				finish()
				return
			end
			setReel(randomReelItem())
			task.wait(0.06)
		end
		local final = result :: { item: Item, kind: string }
		for i, delay in REEL_DELAYS do
			task.wait(delay)
			if not alive() then
				return
			end
			setReel(if i == #REEL_DELAYS then final.item else randomReelItem())
			Audio.play("tink", { volume = 0.35, pitch = 0.9 + i * 0.03 })
		end
		task.wait(0.55)
		if not alive() then
			return
		end
		buildReveal(final.item, final.kind)
		setPhase("flash")
		Audio.play("boom", { volume = 0.45 })
		task.wait(0.55)
		if not alive() then
			return
		end
		setPhase("reveal")
		Audio.play(REVEAL_SOUND[final.kind] or "shimmer")
		if final.kind == "great" or final.kind == "mythic" or final.kind == "secret" then
			Audio.play("levelup")
		end
		if final.kind ~= "bust" then
			UiKit.burst(resultUi.showBox, Vector2.new(145, 190), if final.kind == "great" then 40 else 22, { revealColor, C.rune, Color3.new(1, 1, 1) })
		end
	end)
end

-- ===== Ruch (co klatkę, tylko gdy okno jest otwarte) =====

local motion = {
	angleA = 0,
	angleB = 0,
	speedA = 9,
	speedB = -6.5,
	last = os.clock(),
	ringAlpha = 1,
	triAlpha = -1,
	triGlow = -1,
	centerAlpha = 1,
	infoAlpha = -1,
}
local SHAKE = { Vector2.new(0, 0), Vector2.new(-7, 3), Vector2.new(6, -4), Vector2.new(-4, -3), Vector2.new(3, 4), Vector2.new(0, 0) }

local function setTri(alpha: number, glow: number)
	if motion.triAlpha == alpha and motion.triGlow == glow then
		return
	end
	motion.triAlpha, motion.triGlow = alpha, glow
	setAlpha(sceneUi.triFade, alpha)
	local strength = math.clamp(glow / 30, 0, 1)
	for _, entry in sceneUi.glowLines do
		entry.line.BackgroundTransparency = 1 - entry.strength * strength * alpha
	end
end

local function stepRings(dt: number, since: number)
	local wantA, wantB = 9, -6.5
	if phase == "charge" then
		wantA, wantB = 327, -225
	elseif phase == "converge" or phase == "reel" then
		wantA, wantB = 800, -600
	elseif phase == "flash" or phase == "reveal" then
		wantA, wantB = 6, -6.5
	end
	local follow = 1 - math.exp(-dt * 5)
	motion.speedA += (wantA - motion.speedA) * follow
	motion.speedB += (wantB - motion.speedB) * follow
	motion.angleA = (motion.angleA + motion.speedA * dt) % 360
	motion.angleB = (motion.angleB + motion.speedB * dt) % 360
	sceneUi.ringA.Rotation = motion.angleA
	sceneUi.ringB.Rotation = motion.angleB
	local ringAlpha = if phase == "reveal" then math.max(0.28, 1 - since / 0.5 * 0.72) else 1
	if ringAlpha ~= motion.ringAlpha then
		motion.ringAlpha = ringAlpha
		setAlpha(sceneUi.ringFade, ringAlpha)
	end
end

-- Układ z trójkątem: kołysanie, przy ładowaniu trzy obroty; miejsca oddychają, potem zlatują do środka
local function stepRig(now: number, since: number)
	local rigRotation, rigOffset = 0, 0
	if phase == "idle" then
		local w = now * math.pi * 2 / 6
		rigRotation = -1.2 * math.cos(w)
		rigOffset = -3 * (1 - math.cos(w))
	elseif phase == "charge" or phase == "converge" then
		rigRotation = 1080 * RIG_EASE((now - chargeAt) / 2)
	end
	sceneUi.rig.Rotation = rigRotation
	sceneUi.rig.Position = at(CENTER.X, CENTER.Y + rigOffset)

	local triAlpha, triSize = 1, 1
	if phase == "reel" or phase == "flash" then
		local s = now - reelAt
		triAlpha = math.max(0, 1 - s / 0.45)
		triSize = 1 - 0.7 * math.min(1, s / 0.6)
	elseif phase == "reveal" then
		triAlpha, triSize = 0, 0.3
	end
	sceneUi.tri.Visible = triAlpha > 0
	if triAlpha > 0 then
		setTri(triAlpha, if phase == "charge" then 22 elseif phase == "converge" then 30 else 9)
		sceneUi.triScale.Scale = triSize
	end

	for slot, view in slotViews do
		view.spinner.Rotation = -rigRotation
		if phase == "charge" then
			view.scale.Scale = 1 + 0.035 * (1 - math.cos(since * math.pi * 4))
			view.ring.Color = C.rune
			view.ring.Thickness = 4
		elseif phase == "converge" then
			local p = CONVERGE_EASE(since / 0.8)
			local v = VERTS[slot]
			local pos = v + (RIG_CENTER - v) * p
			view.holder.Position = at(pos.X, pos.Y)
			view.scale.Scale = 1 - 0.8 * p
			setAlpha(view.fade, 1 - p)
			view.art.Visible = p < 0.8
		elseif view.ring.Thickness ~= 3 then
			view.ring.Thickness = 3
		end
	end

	local centerAlpha = if phase == "converge" then math.max(0, 1 - since / 0.4) else 1
	if centerAlpha ~= motion.centerAlpha then
		motion.centerAlpha = centerAlpha
		setAlpha(sceneUi.centerFade, centerAlpha)
	end
	sceneUi.reelScale.Scale = if phase == "reel" then 1 + 0.035 * math.sin(now * 45) else 1
end

local function stepParticles(now: number)
	if not sceneUi.particleLayer.Visible then
		return
	end
	local start = if phase == "reveal" then phaseAt else chargeAt
	for _, p in sceneUi.particles do
		local age = now - start - p.delay
		if age < 0 then
			p.dot.BackgroundTransparency = 1
		else
			local k = (age % p.duration) / p.duration
			local alpha = if k < 0.15 then k / 0.15 else 1 - (k - 0.15) / 0.85
			local size = p.size * (0.6 + 0.5 * k)
			p.dot.Position = at(p.left, p.top - 260 * k)
			p.dot.Size = at(size, size)
			p.dot.BackgroundTransparency = 1 - alpha
		end
	end
end

-- Błysk: dwie fale, rozbłysk i potrząśnięcie sceną
local function stepFlash(since: number)
	local stage = sceneUi.stage
	if phase ~= "flash" then
		if stage.Position ~= at(0, 0) then
			stage.Position = at(0, 0)
		end
		return
	end
	local a = math.min(1, since / 0.8)
	sceneUi.shockAScale.Scale = 0.3 + 2.9 * (1 - (1 - a) ^ 2)
	sceneUi.shockAStroke.Transparency = 0.05 + 0.95 * a
	local b = math.clamp((since - 0.1) / 1, 0, 1)
	sceneUi.shockBScale.Scale = 0.3 + 2.9 * (1 - (1 - b) ^ 2)
	sceneUi.shockBStroke.Transparency = if since < 0.1 then 1 else 0.05 + 0.95 * b
	local q = since / 0.55
	setAlpha(sceneUi.flashFade, if q < 0.18 then q / 0.18 else math.max(0, 1 - (q - 0.18) / 0.82))
	local s = math.clamp(since / 0.45, 0, 1) * (#SHAKE - 1)
	local i = math.min(#SHAKE - 2, math.floor(s))
	local offset = SHAKE[i + 1]:Lerp(SHAKE[i + 2], s - i)
	stage.Position = at(offset.X, offset.Y)
end

-- Odsłonięcie: podskok grzyba, obrót jak karta, opis wjeżdża z prawej
local function stepReveal(since: number)
	if phase ~= "reveal" then
		return
	end
	local ui = resultUi
	local p = math.min(1, since / 0.7)
	local scale, rotation
	if p < 0.6 then
		local e = 1 - (1 - p / 0.6) ^ 2
		scale, rotation = 0.25 + 0.85 * e, -10 + 12 * e
	else
		local e = (p - 0.6) / 0.4
		scale, rotation = 1.1 - 0.1 * e, 2 - 2 * e
	end
	ui.popScale.Scale = scale
	ui.pop.Rotation = rotation
	ui.spin.Size = at(250 * math.max(0.12, math.abs(math.cos(since * math.pi / 3))), 250)
	local q = math.clamp((since - 0.35) / 0.6, 0, 1)
	local e = 1 - (1 - q) ^ 3
	ui.info.Position = at(358 + 30 * (1 - e), 0)
	if e ~= motion.infoAlpha then
		motion.infoAlpha = e
		setAlpha(infoFade, e)
	end
end

UiFx.animate(root, root, function(now: number)
	local dt = math.min(0.1, now - motion.last)
	motion.last = now
	local since = now - phaseAt
	stepRings(dt, since)
	stepRig(now, since)
	stepParticles(now)
	stepFlash(since)
	stepReveal(since)
end)

-- ===== Akcje =====

toggle = function(index: number)
	if phase ~= "idle" then
		return
	end
	local slot = table.find(chosen, index)
	if slot then
		table.remove(chosen, slot)
		Audio.play("click")
	else
		local ok, why = Forge.eligible(basket[index])
		if not ok then
			Audio.play("warn")
			hint = { text = t(why or "FORGE_WRONG_INPUT"), untilAt = os.clock() + 3 }
			task.delay(3.05, render)
			render()
			return
		end
		if #chosen >= Forge.SLOTS then
			Audio.play("warn")
			return
		end
		table.insert(chosen, index)
		Audio.play("pick", { jitter = 0.08 })
	end
	hint = nil
	render()
end

barUi.fuse.Activated:Connect(function()
	if phase == "reveal" then
		collectResult()
		return
	end
	if phase ~= "idle" or waiting or not barUi.fuse.Active then
		return
	end
	local preview = currentPreview()
	if not preview or coins < preview.fee then
		return
	end
	local inputs = {}
	for _, item in chosenItems() do
		table.insert(inputs, table.clone(item))
	end
	sent = { items = inputs, value = preview.inputValue, fee = preview.fee, preview = preview }
	waiting = true
	result = nil
	hint = nil
	Remotes.get("ForgeAction"):FireServer({ kind = "fuse", slots = table.clone(chosen), key = basketKey })
	runFuse()
end)

-- ===== Dane z serwera =====

Remotes.get("ForgeView").OnClientEvent:Connect(function(view: any, open: boolean)
	if typeof(view) ~= "table" then
		return
	end
	access = if typeof(view.access) == "table" then view.access else {}
	found = if typeof(view.found) == "table" then view.found else {}
	if typeof(view.readyIn) == "number" and view.readyIn > 0 then
		readyAt = os.clock() + view.readyIn
		task.delay(view.readyIn + 0.05, render)
	end
	if typeof(view.result) == "table" and typeof(view.kind) == "string" then
		if waiting then
			result = { item = view.result, kind = view.kind }
			waiting = false
		end
	elseif waiting then
		-- Odmowa (powód przyszedł komunikatem): grzyby zostają w miejscach
		finish()
	end
	if open then
		window.setOpen(true)
	end
	render()
end)

window.onToggle(function(open: boolean)
	if open then
		motion.last = os.clock()
		render()
	elseif phase == "reveal" then
		chosen = {}
		finish()
	elseif phase == "idle" then
		chosen = {}
	end
end)

Localize.onChanged(function()
	tilesKey = nil -- krótkie liczby i nazwy na kafelkach zależą od języka
	render()
end)

setPhase("idle")

ForgePanel.render = render

function ForgePanel.setBasket(items: { Item }, key: string)
	pendingBasket = { items = items, key = key }
	-- W czasie łączenia nowy koszyk (już z wynikiem) przyjmujemy dopiero przy „Zbierz do koszyka”
	if phase == "idle" and not waiting then
		applyPending()
		render()
	end
end

function ForgePanel.setCoins(value: number)
	coins = value
	render()
end

return ForgePanel
