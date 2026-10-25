--!strict
-- Grządki w ogródku gracza: siatka podniesionych skrzyń z ziemią (3 x 3).
-- Każda skrzynia to część "Bed<i>" z Attachmentem "Slot<i>" na środku ziemi: tam rośnie posadzony grzyb.
-- Skrzynie ponad liczbę odblokowanych grządek gracza GardenService przyciemnia i zamyka kłódką.
-- Lokalne -Z grządek patrzy na furtkę.

local Palette = require(script.Parent.Palette)

local Beds = {}

local COLS = 3
local BED = 3.4 -- bok skrzyni
local GAP = 1.3
local HEIGHT = 0.9

Beds.SOIL = Color3.fromRGB(86, 60, 42)
Beds.SOIL_LOCKED = Color3.fromRGB(52, 44, 40)

local function make(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Zwraca szerokość całej siatki (żeby ogródek mógł rozmieścić resztę wokół)
function Beds.width(count: number): number
	local cols = math.min(COLS, count)
	return cols * BED + (cols - 1) * GAP
end

function Beds.build(parent: Instance, cf: CFrame, count: number): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Beds"
	local rows = math.ceil(count / COLS)
	local width = Beds.width(count)
	local depth = rows * BED + (rows - 1) * GAP

	for index = 1, count do
		local row = (index - 1) // COLS
		local col = (index - 1) % COLS
		local x = -width / 2 + BED / 2 + col * (BED + GAP)
		-- Pierwszy rząd najbliżej furtki
		local z = -depth / 2 + BED / 2 + row * (BED + GAP)
		local base = cf * CFrame.new(x, 0, z)

		-- Rama z desek i ziemia w środku
		make(folder, "BedFrame", Vector3.new(BED, HEIGHT, BED), base * CFrame.new(0, HEIGHT / 2, 0), Palette.plankDark)
		local soil = make(folder, "Bed" .. index, Vector3.new(BED - 0.5, 0.2, BED - 0.5), base * CFrame.new(0, HEIGHT + 0.02, 0), Beds.SOIL)
		soil.CanCollide = false
		soil.Material = Enum.Material.Slate
		-- Jaśniejsze listwy na rogach ramy
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local corner = make(folder, "BedCorner", Vector3.new(0.4, HEIGHT + 0.25, 0.4), base * CFrame.new(sx * (BED / 2 - 0.2), (HEIGHT + 0.25) / 2, sz * (BED / 2 - 0.2)), Palette.plank)
				corner.CanCollide = false
				corner.CanQuery = false
			end
		end

		local attachment = Instance.new("Attachment")
		attachment.Name = "Slot" .. index
		attachment.CFrame = soil.CFrame:ToObjectSpace(base * CFrame.new(0, HEIGHT + 0.12, 0))
		attachment.Parent = soil
	end

	folder.Parent = parent
	return folder
end

return Beds
