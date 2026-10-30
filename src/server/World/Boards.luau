--!strict
-- Tablice rankingów na tylnej ścianie chatki (od strony Placu Portali): drewniana rama z daszkiem, ciemna tablica
-- (ekran z SurfaceGui rysuje klient: LeaderboardView) i dwie latarenki.
-- Ekrany mają tag "Leaderboard" i atrybut Kind; LeaderboardService wpisuje do nich wyniki.

local CollectionService = game:GetService("CollectionService")

local Cabin = require(script.Parent.Cabin)
local Palette = require(script.Parent.Palette)

local Boards = {}

export type Placement = {
	kind: string,
	position: Vector3,
	width: number,
	height: number,
	lift: number,
	rows: number,
	facing: Vector3?, -- w którą stronę patrzy tablica (domyślnie -Z, na Plac Portali)
	optional: boolean?, -- stoi tylko, gdy Boards.build dostanie dla niej true (np. ranking eventu)
}

-- Na zewnątrz tylnej ściany chatki, przodem do Placu Portali (-Z): każdy, kto idzie do portali,
-- przechodzi obok. Trzy tablice obok siebie od lewego narożnika do komina (komin stoi przy x = 14).
-- Patrząc od placu, +X jest po prawej.
local WALL_Z = Cabin.BACK_Z - 1.4
Boards.PLACEMENTS = {
	{ kind = "richest", position = Vector3.new(-13.5, 0, WALL_Z), width = 8.5, height = 10, lift = 2.4, rows = 8 },
	{ kind = "rare", position = Vector3.new(-3.5, 0, WALL_Z), width = 8.5, height = 10, lift = 2.4, rows = 8 },
	{ kind = "thieves", position = Vector3.new(6.5, 0, WALL_Z), width = 8.5, height = 10, lift = 2.4, rows = 8 },
	-- Halloween: ranking cukierków przy ścieżce do lasu, za ogródkami (nie stoi na przejściu między nimi),
	-- bokiem do ścieżki i lekko w stronę lasu: widać go, wracając z koszykiem do chatki
	{ kind = "candy", position = Vector3.new(-11, 0, 31), width = 8, height = 9, lift = 2, rows = 8, facing = Vector3.new(1, 0, 0.45), optional = true },
} :: { Placement }

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Wood
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function lantern(parent: Instance, cf: CFrame)
	local cage = part(parent, "Lantern", Vector3.new(0.9, 1.2, 0.9), cf, Color3.fromRGB(60, 50, 44), Enum.Material.Metal)
	cage.CanCollide = false
	local glow = part(parent, "Glow", Vector3.new(0.6, 0.8, 0.6), cf, Color3.fromRGB(255, 196, 92), Enum.Material.Neon)
	glow.CanCollide = false
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 190, 110)
	light.Range = 14
	light.Brightness = 1.4
	light.Shadows = false
	light.Parent = glow
end

-- Buduje jedną tablicę; zwraca ekran (część z SurfaceGui po stronie klienta)
local function buildBoard(parent: Instance, placement: Placement): BasePart
	local model = Instance.new("Model")
	model.Name = "Leaderboard_" .. placement.kind
	local w, h, lift = placement.width, placement.height, placement.lift
	-- Układ lokalny: przód tablicy patrzy na -Z świata (w stronę Placu Portali), tył przy ścianie
	local facing = placement.facing or Vector3.new(0, 0, -1)
	local base = CFrame.lookAt(placement.position, placement.position + facing.Unit)
	local centerY = lift + h / 2

	-- Słupy po bokach, aż do ziemi
	for _, side in { -1, 1 } do
		local x = side * (w / 2 + 0.5)
		part(model, "Post", Vector3.new(1, lift + h + 1.2, 1), base * CFrame.new(x, (lift + h + 1.2) / 2, 0), Palette.log)
		-- Kamień pod słupem
		local stone = part(model, "Stone", Vector3.new(1.8, 0.6, 1.8), base * CFrame.new(x, 0.3, 0), Palette.stone, Enum.Material.Slate)
		stone.CanCollide = false
		lantern(model, base * CFrame.new(x, lift + h + 0.2, -1.1))
	end
	-- Rama i daszek
	part(model, "Back", Vector3.new(w + 0.4, h + 0.4, 0.4), base * CFrame.new(0, centerY, 0.3), Palette.plankDark)
	part(model, "FrameTop", Vector3.new(w + 1.4, 0.6, 0.8), base * CFrame.new(0, lift + h + 0.3, 0), Palette.plank)
	part(model, "FrameBottom", Vector3.new(w + 1.4, 0.6, 0.8), base * CFrame.new(0, lift - 0.3, 0), Palette.plank)
	for _, side in { -1, 1 } do
		local roof = part(
			model,
			"Roof",
			Vector3.new(w + 3, 0.35, 1.8),
			base * CFrame.new(0, lift + h + 1.25, side * 0.55) * CFrame.Angles(side * math.rad(28), 0, 0),
			Palette.roof
		)
		roof.Material = Enum.Material.WoodPlanks
	end
	-- Mech na daszku dla klimatu
	local moss = part(model, "Moss", Vector3.new(w + 2.6, 0.25, 0.9), base * CFrame.new(0, lift + h + 1.75, 0), Palette.moss, Enum.Material.Grass)
	moss.CanCollide = false

	local screen = part(model, "Screen", Vector3.new(w, h, 0.2), base * CFrame.new(0, centerY, 0), Color3.fromRGB(34, 26, 20), Enum.Material.SmoothPlastic)
	screen.CanCollide = false
	screen:SetAttribute("Kind", placement.kind)
	screen:SetAttribute("Rows", placement.rows)
	CollectionService:AddTag(screen, "Leaderboard")

	model.PrimaryPart = screen
	model.Parent = parent
	return screen
end

function Boards.build(parent: Instance, optional: { [string]: boolean }?): { [string]: BasePart }
	local folder = Instance.new("Folder")
	folder.Name = "Leaderboards"
	local screens = {}
	for _, placement in Boards.PLACEMENTS do
		if not placement.optional or (optional and optional[placement.kind]) then
			screens[placement.kind] = buildBoard(folder, placement)
		end
	end
	folder.Parent = parent
	return screens
end

return Boards
