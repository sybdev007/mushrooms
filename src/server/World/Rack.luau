--!strict
-- Suszarnia gracza: drewniany podest z sześcioma osobnymi stanowiskami w dwóch rzędach
-- (tylny rząd stoi stopień wyżej, żeby było go widać zza przedniego).
-- Każde stanowisko ma płytkę "Pad<i>" i własną ramkę z poprzeczką, pod którą wisi grzyb
-- w miejscu Attachmentu "Slot<i>". Przód suszarni (lokalne -Z) patrzy na alejkę.
-- Grzyby, tabliczki z cenami i podświetlenie płytek dokłada DryingService.

local Palette = require(script.Parent.Palette)
local Props = require(script.Parent.Props)

local Rack = {}

local COLS = 3
local PAD = 3.2 -- bok płytki stanowiska
local GAP = 0.45
local STEP = 1 -- o tyle wyżej stoi tylny rząd
local FRAME_H = 3.8 -- wysokość ramki nad płytką

Rack.PAD_EMPTY = Color3.fromRGB(96, 70, 50)

local function make(m: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, collide: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Anchored = true
	p.CanCollide = collide ~= false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = m
	return p
end

function Rack.build(parent: Instance, cf: CFrame, slots: number): Model
	local m = Instance.new("Model")
	m.Name = "DryingRack"

	local rows = math.ceil(slots / COLS)
	local width = COLS * PAD + (COLS + 1) * GAP
	local depth = rows * PAD + (rows + 1) * GAP

	-- Rząd 1 to przód (bliżej alejki, lokalne -Z)
	local function rowZ(row: number): number
		return -depth / 2 + GAP + PAD / 2 + (row - 1) * (PAD + GAP)
	end
	local function rowTop(row: number): number
		return 0.5 + (row - 1) * STEP
	end

	-- Podest: osobny blok na każdy rząd, tylny wyższy
	for row = 1, rows do
		local top = rowTop(row)
		make(m, "Deck", Vector3.new(width, top, PAD + GAP * 2), cf * CFrame.new(0, top / 2, rowZ(row)), Palette.plankDark)
	end
	-- Ciemniejsza listwa na krawędzi każdego stopnia
	for row = 1, rows do
		make(m, "Trim", Vector3.new(width + 0.1, 0.18, 0.25), cf * CFrame.new(0, rowTop(row) - 0.09, rowZ(row) - PAD / 2 - GAP), Palette.roofEdge, false)
	end

	local index = 0
	for row = 1, rows do
		local top = rowTop(row)
		for col = 1, COLS do
			index += 1
			if index > slots then
				break
			end
			local x = -width / 2 + GAP + PAD / 2 + (col - 1) * (PAD + GAP)
			local z = rowZ(row)
			local base = cf * CFrame.new(x, top, z)

			-- Płytka stanowiska: kolor zmienia DryingService (pusta / zajęta / złota)
			local pad = make(m, "Pad" .. index, Vector3.new(PAD, 0.16, PAD), base * CFrame.new(0, 0.08, 0), Rack.PAD_EMPTY)
			pad.CanCollide = false

			-- Ramka: dwa słupki i poprzeczka, na poprzeczce sznurek do grzyba
			for _, side in { -1, 1 } do
				make(m, "SlotPost", Vector3.new(0.28, FRAME_H, 0.28), base * CFrame.new(side * (PAD / 2 - 0.25), FRAME_H / 2, PAD / 2 - 0.4), Palette.plank)
			end
			make(m, "SlotBar", Vector3.new(PAD - 0.2, 0.3, 0.3), base * CFrame.new(0, FRAME_H, PAD / 2 - 0.4), Palette.plank, false)
			local arm = make(m, "SlotArm", Vector3.new(0.18, 0.18, PAD / 2), base * CFrame.new(0, FRAME_H - 0.05, PAD / 4 - 0.4), Palette.plankDark, false)
			arm.CanQuery = false

			local attachment = Instance.new("Attachment")
			attachment.Name = "Slot" .. index
			-- Grzyb wisi nad środkiem płytki, pod ramieniem
			attachment.CFrame = pad.CFrame:ToObjectSpace(base * CFrame.new(0, FRAME_H - 0.65, 0))
			attachment.Parent = pad
		end
	end

	-- Słupek z latarnią w przednim rogu: suszarnie są widoczne nocą
	local postAt = cf * CFrame.new(width / 2 + 0.6, 0, -depth / 2)
	make(m, "LampPost", Vector3.new(0.4, 6.4, 0.4), postAt * CFrame.new(0, 3.2, 0), Palette.plankDark)
	Props.hangingLantern(m, (postAt * CFrame.new(0, 6.4, 0)).Position, 14)

	-- Niewidoczny punkt przed środkiem suszarni: przyciski akcji i tabliczka z właścicielem
	local hub = make(m, "Hub", Vector3.new(1, 1, 1), cf * CFrame.new(0, 2.4, -depth / 2 - 1.2), Palette.plank, false)
	hub.Transparency = 1
	hub.CanQuery = false

	m.PrimaryPart = hub
	m.Parent = parent
	return m
end

return Rack
