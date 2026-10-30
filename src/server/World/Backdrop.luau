--!strict
-- Tło za granicą świata (las, bagna): za niewidzialnymi ścianami stoi gęsty pas drzew, za nim
-- ciemne sylwetki wyższych drzew, a dalej wzgórza (po bokach) i góry (na końcach świata).
-- Dzięki temu między drzewami na brzegu nie prześwituje pusta płyta ani niebo pod koronami,
-- a z końca lasu nie widać jaskini, która stoi dalej na tej samej osi Z.
-- Wszystko to ozdoba: bez kolizji, bez dotyku, bez cieni (taniej) i bez celowania.

local Backdrop = {}

export type Rect = { x1: number, x2: number, z1: number, z2: number }
export type Style = {
	name: string,
	ground: Color3?, -- płyta pod tłem (sięga daleko poza mapę); nil = świat ma już swoją
	near: (parent: Instance, base: Vector3, rng: Random) -> (), -- drzewo tuż za ścianą
	nearSpacing: number,
	far: (parent: Instance, base: Vector3, rng: Random) -> (), -- sylwetka w drugim rzędzie
	farthest: ((parent: Instance, base: Vector3, rng: Random) -> ())?, -- trzeci rząd (domyślnie jak drugi)
	farSpacing: number,
	hill: { Color3 }, -- wzgórza po bokach
	hillHeight: { number }, -- najniższe i najwyższe
	mountain: { Color3 }, -- góry na końcach świata
	mountainHeight: { number },
	ends: { boolean }?, -- które końce mają góry: { początek (z1), koniec (z2) }; domyślnie oba
}

local TAU = math.pi * 2

local function make(className: string, props: { [string]: any }): BasePart
	local p = Instance.new(className) :: BasePart
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end
Backdrop.make = make

-- Ostrosłup z czterech CornerWedge (jak korony sosen w Props): wierzchołek nad `center`
function Backdrop.cone(parent: Instance, center: Vector3, width: number, height: number, yaw: number, color: Color3)
	for i = 0, 3 do
		make("CornerWedgePart", {
			Size = Vector3.new(width / 2, height, width / 2),
			CFrame = CFrame.new(center + Vector3.new(0, height / 2, 0))
				* CFrame.Angles(0, yaw + math.rad(90 * i), 0)
				* CFrame.new(-width / 4, 0, width / 4),
			Color = color,
			Parent = parent,
		})
	end
end

-- Elipsoida (wzgórze, korona wierzby): klocek z siatką kuli
function Backdrop.blob(parent: Instance, center: Vector3, size: Vector3, color: Color3, material: Enum.Material?): BasePart
	local p = make("Part", {
		Size = size,
		Position = center,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local function pick(list: { Color3 }, rng: Random): Color3
	return list[rng:NextInteger(1, #list)]
end

-- Punkty co `spacing` (z drobnym rozrzutem) na obwodzie prostokąta odsuniętego o `offset`
local function ring(rect: Rect, offset: number, spacing: number, rng: Random, each: (Vector3, Vector3) -> ())
	local x1, x2 = rect.x1 - offset, rect.x2 + offset
	local z1, z2 = rect.z1 - offset, rect.z2 + offset
	local function line(from: Vector3, to: Vector3, outward: Vector3)
		local length = (to - from).Magnitude
		local direction = (to - from).Unit
		local t = rng:NextNumber(0, spacing * 0.5)
		while t < length do
			local jitter = outward * rng:NextNumber(-spacing * 0.25, spacing * 0.25)
			each(from + direction * t + jitter, outward)
			t += spacing * rng:NextNumber(0.8, 1.2)
		end
	end
	line(Vector3.new(x1, 0, z1), Vector3.new(x1, 0, z2), Vector3.new(-1, 0, 0))
	line(Vector3.new(x2, 0, z1), Vector3.new(x2, 0, z2), Vector3.new(1, 0, 0))
	line(Vector3.new(x1, 0, z1), Vector3.new(x2, 0, z1), Vector3.new(0, 0, -1))
	line(Vector3.new(x1, 0, z2), Vector3.new(x2, 0, z2), Vector3.new(0, 0, 1))
end

-- rect: grywalny prostokąt świata (na jego brzegach stoją niewidzialne ściany)
function Backdrop.build(parent: Instance, rect: Rect, style: Style, rng: Random): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Backdrop_" .. style.name
	local width, length = rect.x2 - rect.x1, rect.z2 - rect.z1
	local cx, cz = (rect.x1 + rect.x2) / 2, (rect.z1 + rect.z2) / 2

	-- Ziemia pod tłem: niżej niż ziemia świata, żeby nie migotały
	if style.ground then
		make("Part", {
			Name = "BackdropGround",
			Size = Vector3.new(width + 420, 1, length + 420),
			Position = Vector3.new(cx, -1.45, cz),
			Color = style.ground,
			Parent = folder,
		})
	end

	-- Pierwszy rząd: pełne drzewa tuż za ścianą (z bliska widać je w szczegółach)
	ring(rect, 7, style.nearSpacing, rng, function(base: Vector3)
		style.near(folder, base, rng)
	end)
	-- Drugi i trzeci rząd: wyższe sylwetki, przesunięte, żeby zasłaniały prześwity pierwszego
	ring(rect, 19, style.farSpacing, rng, function(base: Vector3)
		style.far(folder, base, rng)
	end)
	local farthest: (Instance, Vector3, Random) -> () = style.farthest or style.far
	ring(rect, 33, style.farSpacing * 1.15, rng, function(base: Vector3)
		farthest(folder, base, rng)
	end)

	-- Wzgórza po bokach (do połowy w ziemi), zasłaniają horyzont
	local hillMin, hillMax = style.hillHeight[1], style.hillHeight[2]
	for _, side in { -1, 1 } do
		local x = if side < 0 then rect.x1 - 72 else rect.x2 + 72
		local z = rect.z1 - 90
		while z < rect.z2 + 90 do
			local height = rng:NextNumber(hillMin, hillMax)
			local along = rng:NextNumber(80, 130)
			Backdrop.blob(folder, Vector3.new(x + side * rng:NextNumber(-8, 14), -height * 0.12, z + along / 2), Vector3.new(rng:NextNumber(70, 100), height * 2, along), pick(style.hill, rng))
			z += along * 0.7
		end
	end

	-- Góry na końcach świata: zasłaniają sąsiedni świat na tej samej osi
	local ends = style.ends or { true, true }
	local mountMin, mountMax = style.mountainHeight[1], style.mountainHeight[2]
	for index, edgeZ in { rect.z1, rect.z2 } do
		if ends[index] then
			local outward = if index == 1 then -1 else 1
			local x = rect.x1 - 120
			while x < rect.x2 + 120 do
				local height = rng:NextNumber(mountMin, mountMax)
				local base = height * rng:NextNumber(1.1, 1.5)
				local z = edgeZ + outward * (78 + rng:NextNumber(0, 30))
				Backdrop.cone(folder, Vector3.new(x + base / 2, -2, z), base, height, rng:NextNumber(0, TAU), pick(style.mountain, rng))
				x += base * 0.55
			end
			-- Między górami a lasem jeszcze rząd wzgórz, żeby nie było widać stóp gór
			local hx = rect.x1 - 60
			while hx < rect.x2 + 60 do
				local height = rng:NextNumber(hillMin, hillMax)
				local along = rng:NextNumber(70, 110)
				Backdrop.blob(folder, Vector3.new(hx + along / 2, -height * 0.12, edgeZ + outward * 58), Vector3.new(along, height * 2, rng:NextNumber(60, 80)), pick(style.hill, rng))
				hx += along * 0.7
			end
		end
	end

	-- Na wszelki wypadek: nic z tła nie koliduje, nie rzuca cieni i nie łapie promieni
	for _, descendant in folder:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CastShadow = false
		end
	end
	folder.Parent = parent
	return folder
end

return Backdrop
