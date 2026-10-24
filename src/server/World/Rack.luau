--!strict
-- Drewniana suszarnia na grzyby przed chatką: dwa słupki, daszek, dwa sznurki.
-- Miejsca na grzyby to Attachmenty "Slot1".."SlotN" w części "Beam".
-- Grzyby na sznurkach i napis z właścicielem dokłada DryingService.

local Palette = require(script.Parent.Palette)

local Rack = {}

local WIDTH = 7
local HEIGHT = 5.2

local function make(m: Model, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = m
	return p
end

function Rack.build(parent: Instance, cf: CFrame, slots: number): Model
	local m = Instance.new("Model")
	m.Name = "DryingRack"

	for _, side in { -1, 1 } do
		make(m, "Post", Vector3.new(0.5, HEIGHT, 0.5), cf * CFrame.new(side * WIDTH / 2, HEIGHT / 2, 0), Palette.plankDark)
	end
	local beam = make(m, "Beam", Vector3.new(WIDTH + 0.8, 0.4, 0.4), cf * CFrame.new(0, HEIGHT - 0.2, 0), Palette.plankDark)
	beam.CanCollide = false

	-- Daszek z desek, żeby suszarnia czytała się z daleka
	local roof = make(m, "Roof", Vector3.new(WIDTH + 1.6, 0.3, 2.6), cf * CFrame.new(0, HEIGHT + 0.5, 0) * CFrame.Angles(math.rad(-10), 0, 0), Palette.roof)
	roof.CanCollide = false

	-- Dwa sznurki, po połowie miejsc na każdym
	local perRow = math.ceil(slots / 2)
	local rows = { HEIGHT - 1.1, HEIGHT - 2.6 }
	for _, y in rows do
		local rope = make(m, "Rope", Vector3.new(WIDTH, 0.08, 0.08), cf * CFrame.new(0, y, 0), Color3.fromRGB(200, 190, 170))
		rope.CanCollide = false
		rope.CanQuery = false
		rope.CastShadow = false
	end
	local index = 0
	for row, y in rows do
		for i = 1, perRow do
			index += 1
			if index > slots then
				break
			end
			local x = -WIDTH / 2 + WIDTH * i / (perRow + 1) + (row - 1) * 0.5
			local attachment = Instance.new("Attachment")
			attachment.Name = "Slot" .. index
			-- Pozycja względem belki
			attachment.CFrame = beam.CFrame:ToObjectSpace(cf * CFrame.new(x, y - 0.5, 0))
			attachment.Parent = beam
		end
	end

	-- Niewidoczny punkt dla przycisków akcji (ProximityPrompt) i tabliczki z właścicielem
	local hub = make(m, "Hub", Vector3.new(1, 1, 1), cf * CFrame.new(0, 2.5, 0), Palette.plank)
	hub.Transparency = 1
	hub.CanCollide = false
	hub.CanQuery = false

	-- Skrzynka pod suszarnią
	make(m, "Crate", Vector3.new(2, 1.2, 1.4), cf * CFrame.new(-1.6, 0.6, 0.6) * CFrame.Angles(0, math.rad(8), 0), Palette.plank)

	m.PrimaryPart = hub
	m.Parent = parent
	return m
end

return Rack
