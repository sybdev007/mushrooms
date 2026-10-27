--!strict
-- Pikselowe grzybki do interfejsu (karty w skupie): arkusz assets/mushroom-sprites.png z Config.MushroomSprites.
-- Każdy kształt to dwie warstwy: biała sylwetka kapelusza barwiona na kolor gatunku albo mutacji
-- i warstwa z obrysem, trzonem z buzią, kropkami i cieniami. Ostre piksele dzięki ResampleMode.Pixelated.
--
-- Aury według rzadkości (najwyższa z klasy gatunku i mutacji):
--   rzadki      – niebieska poświata, która lekko pulsuje
--   epicki      – fioletowa poświata, grzybek podskakuje, w górę lecą iskierki
--   legendarny  – złote promienie obracają się za grzybkiem, migoczą gwiazdki
--   srebrny     – srebrne błyski;  złoty – złote promienie i iskry
--   tęczowy (mityczny) – kapelusz mieni się tęczą, tęczowe promienie, pulsujący pierścień, tęczowe iskry
-- Cechy z miejsca dokładają swoje: świecący (turkusowy blask), kryształowy (błękitne iskry),
-- otchłanny (żar lecący w górę), omszały (zielone drobinki).
-- Wszystkie animacje liczy jedna pętla RenderStepped, tylko dla grzybków, które są widoczne.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)

type Item = Economy.BasketItem

local MushroomArt = {}

-- Kolejność pól w arkuszu (8 kolumn po 64 px), tak jak wypisuje tools/mushroom_sprites.py
local SHAPES = { "amanita", "bolete", "chanterelle", "cluster", "parasol", "oyster", "crystal", "bell", "puffball", "crown" }
local SHAPE_INDEX: { [string]: number } = {}
for i, name in SHAPES do
	SHAPE_INDEX[name] = (i - 1) * 2 -- pole kapelusza; warstwa wierzchnia jest zaraz po nim
end
local FX = { glow = 20, rays = 21, spark = 22, ring = 23 }

-- Kształt każdego gatunku (domyślnie borowik)
local SPECIES_SHAPE: { [string]: string } = {
	glowing_agaric = "amanita", heart_of_mountain = "amanita", frog_stool = "amanita", utopiec_chalice = "amanita",
	slippery_jack = "bolete", bay_bolete = "bolete", aspen_bolete = "bolete", porcini = "bolete",
	coal_cap = "bolete", peat_cap = "bolete", drowned_cap = "bolete",
	chanterelle = "chanterelle", saffron_milk_cap = "chanterelle", ember = "chanterelle",
	honey = "cluster", bog_bell = "cluster",
	parasol = "parasol", moon_lily = "parasol",
	cave_oyster = "oyster", lake_cap = "oyster",
	crystal_cap = "crystal", amethyst = "crystal", silver_vein = "crystal", gold_nugget = "crystal", obsidian = "crystal",
	lantern_shroom = "bell", wisp_cap = "bell", false_wisp = "bell", will_o_wisp = "bell",
	pearl = "puffball", bog_pearl = "puffball", skarbnik_truffle = "puffball",
	leszy_crown = "crown",
}

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 200, 60)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(110, 255, 110)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(80, 210, 255)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(190, 110, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 80)),
})

local TAG_PARTICLES: { [string]: { Color3 } } = {
	glowing = { Color3.fromRGB(110, 255, 214), Color3.fromRGB(220, 255, 245) },
	crystal = { Color3.fromRGB(120, 200, 255), Color3.fromRGB(230, 245, 255) },
	abyssal = { Color3.fromRGB(255, 90, 40), Color3.fromRGB(255, 190, 60) },
	mossy = { Color3.fromRGB(110, 190, 72), Color3.fromRGB(180, 230, 120) },
}

type SheetDef = { sheet: string, cell: number, columns: number }

local function sheet(): SheetDef?
	local def = (Config :: any).MushroomSprites :: SheetDef?
	if def and def.sheet ~= "" then
		return def
	end
	return nil
end

function MushroomArt.available(): boolean
	return sheet() ~= nil
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function capColor(item: Item): Color3
	local variant = Economy.getVariant(item.v)
	if variant then
		return rgb(variant.color)
	end
	local species = Economy.getSpecies(item.s)
	return rgb(species and species.cap or { 160, 120, 80 })
end
MushroomArt.capColor = capColor

local function image(parent: Instance, name: string, cell: number, size: UDim2, pixelated: boolean): ImageLabel
	local def = sheet() :: SheetDef
	local label = Instance.new("ImageLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Image = def.sheet
	label.ImageRectOffset = Vector2.new((cell % def.columns) * def.cell, (cell // def.columns) * def.cell)
	label.ImageRectSize = Vector2.new(def.cell, def.cell)
	label.Size = size
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.ResampleMode = if pixelated then Enum.ResamplerMode.Pixelated else Enum.ResamplerMode.Default
	label.Parent = parent
	return label
end

-- ===== Poziom efektów =====

export type Fx = {
	glow: Color3?,
	pulse: boolean,
	bob: boolean,
	rays: Color3?,
	rainbow: boolean,
	ring: boolean,
	particles: { Color3 }?,
	twinkle: Color3?,
}

-- Ranga do aury: 0 zwykły, 1 niepospolity, 2 rzadki, 3 epicki, 4 legendarny
local CLASS_RANK: { [string]: number } = { common = 0, uncommon = 1, rare = 2, epic = 3, legendary = 4 }

function MushroomArt.effects(item: Item): Fx
	local fx: Fx = { pulse = false, bob = false, rainbow = false, ring = false }
	local class = Economy.speciesClass(item.s)
	local rank = CLASS_RANK[class.id] or 0
	local classColor = rgb(class.color)
	if rank == 1 then
		fx.glow = classColor
	elseif rank == 2 then
		fx.glow = classColor
		fx.pulse = true
	elseif rank == 3 then
		fx.glow = classColor
		fx.pulse = true
		fx.bob = true
		fx.particles = { classColor, Color3.fromRGB(255, 150, 240) }
	elseif rank >= 4 then
		fx.glow = Color3.fromRGB(255, 200, 80)
		fx.pulse = true
		fx.bob = true
		fx.rays = Color3.fromRGB(255, 196, 60)
		fx.twinkle = Color3.fromRGB(255, 240, 160)
	end
	local variant = item.v
	if variant == "silver" then
		fx.twinkle = Color3.fromRGB(235, 245, 255)
		fx.glow = fx.glow or Color3.fromRGB(214, 224, 238)
	elseif variant == "gold" then
		fx.rays = Color3.fromRGB(255, 205, 50)
		fx.glow = Color3.fromRGB(255, 214, 90)
		fx.twinkle = Color3.fromRGB(255, 245, 180)
		fx.bob = true
	elseif variant == "rainbow" then
		fx.rainbow = true
		fx.ring = true
		fx.rays = Color3.new(1, 1, 1)
		fx.glow = Color3.fromRGB(255, 160, 230)
		fx.pulse = true
		fx.bob = true
		fx.particles = { Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 210, 60), Color3.fromRGB(110, 255, 110), Color3.fromRGB(80, 210, 255), Color3.fromRGB(190, 110, 255) }
		fx.twinkle = Color3.new(1, 1, 1)
	end
	for _, tag in item.x or {} do
		local colors = TAG_PARTICLES[tag]
		if colors and not fx.particles then
			fx.particles = colors
		end
		if tag == "glowing" then
			fx.glow = fx.glow or colors[1]
			fx.pulse = true
		end
	end
	return fx
end

-- ===== Grzybek z aurą =====

type Handle = {
	root: Frame,
	sprite: Frame,
	fx: Fx,
	glow: ImageLabel?,
	rays: ImageLabel?,
	ring: ImageLabel?,
	capGradient: UIGradient?,
	strokeGradient: UIGradient?,
	active: () -> boolean,
	seed: number,
	nextParticle: number,
	nextTwinkle: number,
}
local handles: { [Handle]: boolean } = {}
local loop: RBXScriptConnection? = nil

local function particle(handle: Handle, colors: { Color3 }, rising: boolean)
	local root = handle.root
	local size = root.AbsoluteSize.X
	if size <= 0 then
		return
	end
	local p = image(root, "Particle", FX.spark, UDim2.fromOffset(0, 0), true)
	local px = math.random(2, 8)
	p.Size = UDim2.fromOffset(px, px)
	p.ZIndex = root.ZIndex + 3
	p.ImageColor3 = colors[math.random(1, #colors)]
	local x = 0.2 + math.random() * 0.6
	if rising then
		p.Image = ""
		p.BackgroundTransparency = 0
		p.BackgroundColor3 = p.ImageColor3
		p.BorderSizePixel = 0
		p.Position = UDim2.fromScale(x, 0.85)
		local tween = TweenService:Create(p, TweenInfo.new(0.9 + math.random() * 0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Position = UDim2.fromScale(x + (math.random() - 0.5) * 0.3, 0.05),
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(px // 2, px // 2),
		})
		tween.Completed:Connect(function()
			p:Destroy()
		end)
		tween:Play()
	else
		-- Migocząca gwiazdka w losowym miejscu wokół grzybka
		local s = math.random(8, 14)
		p.Size = UDim2.fromOffset(0, 0)
		p.Position = UDim2.fromScale(0.1 + math.random() * 0.8, 0.1 + math.random() * 0.6)
		p.Rotation = math.random(0, 45)
		local grow = TweenService:Create(p, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(s, s) })
		local shrink = TweenService:Create(p, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = UDim2.fromOffset(0, 0) })
		grow.Completed:Connect(function()
			shrink:Play()
		end)
		shrink.Completed:Connect(function()
			p:Destroy()
		end)
		grow:Play()
	end
end

local function step()
	local now = os.clock()
	for handle in handles do
		if not handle.root.Parent then
			handles[handle] = nil
			continue
		end
		if not handle.active() then
			continue
		end
		local t = now + handle.seed
		local fx = handle.fx
		if handle.glow then
			local pulse = if fx.pulse then 0.5 + 0.5 * math.sin(t * 3) else 0.5
			handle.glow.ImageTransparency = 0.45 - pulse * 0.3
			handle.glow.Size = UDim2.fromScale(1.35 + pulse * 0.15, 1.35 + pulse * 0.15)
		end
		if handle.rays then
			handle.rays.Rotation = (t * 25) % 360
		end
		if handle.ring then
			local k = (t * 0.8) % 1
			handle.ring.Size = UDim2.fromScale(0.8 + k * 0.8, 0.8 + k * 0.8)
			handle.ring.ImageTransparency = k
		end
		if handle.capGradient then
			handle.capGradient.Offset = Vector2.new(((t * 0.35) % 2) - 1, 0)
		end
		if handle.strokeGradient then
			handle.strokeGradient.Rotation = (t * 90) % 360
		end
		if fx.bob then
			handle.sprite.Position = UDim2.new(0.5, 0, 0.5, math.round(math.sin(t * 2.6) * 2))
			handle.sprite.Rotation = math.sin(t * 1.7) * 3
		end
		if fx.particles and now >= handle.nextParticle then
			handle.nextParticle = now + 0.25 + math.random() * 0.25
			particle(handle, fx.particles, true)
		end
		if fx.twinkle and now >= handle.nextTwinkle then
			handle.nextTwinkle = now + 0.5 + math.random() * 0.7
			particle(handle, { fx.twinkle }, false)
		end
	end
end

export type Options = {
	active: (() -> boolean)?,
	stroke: UIStroke?, -- obwódka karty: przy tęczowych grzybach też mieni się tęczą
}

-- Buduje grzybka z aurą w `parent` (wypełnia go całego). Zwraca ramkę albo nil, gdy arkusza jeszcze nie ma.
function MushroomArt.build(parent: GuiObject, item: Item, options: Options?): Frame?
	if not sheet() then
		return nil
	end
	local opts: Options = options or {}
	local shape = SPECIES_SHAPE[item.s] or "bolete"
	local fx = MushroomArt.effects(item)

	local root = Instance.new("Frame")
	root.Name = "MushroomArt"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = parent.ZIndex
	root.Parent = parent

	local handle: Handle = {
		root = root,
		sprite = root, -- podmienione niżej
		fx = fx,
		active = opts.active or function()
			return true
		end,
		seed = math.random() * 10,
		nextParticle = 0,
		nextTwinkle = 0,
	}

	if fx.rays then
		local rays = image(root, "Rays", FX.rays, UDim2.fromScale(1.7, 1.7), false)
		rays.ImageColor3 = fx.rays
		rays.ImageTransparency = 0.15
		rays.ZIndex = root.ZIndex
		if fx.rainbow then
			local g = Instance.new("UIGradient")
			g.Color = RAINBOW
			g.Parent = rays
		end
		handle.rays = rays
	end
	if fx.glow then
		local glow = image(root, "Glow", FX.glow, UDim2.fromScale(1.4, 1.4), false)
		glow.ImageColor3 = fx.glow
		glow.ImageTransparency = 0.35
		glow.ZIndex = root.ZIndex
		handle.glow = glow
	end
	if fx.ring then
		local ring = image(root, "Ring", FX.ring, UDim2.fromScale(1, 1), false)
		ring.ZIndex = root.ZIndex + 1
		local g = Instance.new("UIGradient")
		g.Color = RAINBOW
		g.Rotation = 45
		g.Parent = ring
		handle.ring = ring
	end

	local sprite = Instance.new("Frame")
	sprite.Name = "Sprite"
	sprite.BackgroundTransparency = 1
	sprite.Size = UDim2.fromScale(1, 1)
	sprite.AnchorPoint = Vector2.new(0.5, 0.5)
	sprite.Position = UDim2.fromScale(0.5, 0.5)
	sprite.ZIndex = root.ZIndex + 2
	sprite.Parent = root
	handle.sprite = sprite

	local cap = image(sprite, "Cap", SHAPE_INDEX[shape], UDim2.fromScale(1, 1), true)
	cap.ImageColor3 = capColor(item)
	cap.ZIndex = root.ZIndex + 2
	if fx.rainbow then
		cap.ImageColor3 = Color3.new(1, 1, 1)
		local g = Instance.new("UIGradient")
		g.Color = RAINBOW
		g.Parent = cap
		handle.capGradient = g
	end
	local over = image(sprite, "Over", SHAPE_INDEX[shape] + 1, UDim2.fromScale(1, 1), true)
	over.ZIndex = root.ZIndex + 3

	if fx.rainbow and opts.stroke then
		opts.stroke.Color = Color3.new(1, 1, 1)
		local g = Instance.new("UIGradient")
		g.Color = RAINBOW
		g.Parent = opts.stroke
		handle.strokeGradient = g
	end

	if fx.glow or fx.rays or fx.ring or fx.bob or fx.particles or fx.twinkle or fx.rainbow then
		handles[handle] = true
		if not loop then
			loop = RunService.RenderStepped:Connect(step)
		end
	end
	return root
end

return MushroomArt
