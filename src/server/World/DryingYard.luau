--!strict
-- Plac suszarni obok chatki: ubita ziemia, płot z żerdzi, brama z szyldem na końcu alejki
-- i ścieżka z kamieni od ganku do bramy. Same suszarnie stawia MapBuilder (World/Rack).

local Palette = require(script.Parent.Palette)
local Props = require(script.Parent.Props)

local DryingYard = {}

local VERTICAL = CFrame.Angles(0, 0, math.rad(90))
local POST_SPACING = 4
local GATE_HALF = 3.5
local DIRT = Color3.fromRGB(112, 88, 62)

export type Yard = { x1: number, x2: number, z1: number, z2: number, aisleX: number }

local function make(parent: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

local function post(parent: Instance, x: number, z: number, height: number)
	make(parent, {
		Name = "FencePost",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, 0.6, 0.6),
		CFrame = CFrame.new(x, height / 2, z) * VERTICAL,
		Color = Palette.log,
	})
end

-- Żerdzie płotu między dwoma punktami (na ziemi)
local function rails(parent: Instance, a: Vector3, b: Vector3)
	local length = (b - a).Magnitude
	if length < 0.5 then
		return
	end
	local mid = (a + b) / 2
	for _, y in { 1.2, 2.4 } do
		make(parent, {
			Name = "FenceRail",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(length, 0.32, 0.32),
			-- Walec leży wzdłuż osi X; obracamy go w kierunku odcinka
			CFrame = CFrame.lookAt(mid + Vector3.new(0, y, 0), b + Vector3.new(0, y, 0)) * CFrame.Angles(0, math.rad(90), 0),
			Color = Palette.logEnd,
		})
	end
end

-- Płot wzdłuż odcinka, z otworem [holeFrom, holeTo] mierzonym wzdłuż odcinka (albo bez)
local function fence(parent: Instance, a: Vector3, b: Vector3, holeFrom: number?, holeTo: number?)
	local length = (b - a).Magnitude
	local dir = (b - a).Unit
	local segments = {}
	if holeFrom and holeTo then
		table.insert(segments, { 0, holeFrom })
		table.insert(segments, { holeTo, length })
	else
		table.insert(segments, { 0, length })
	end
	for _, seg in segments do
		local from, to = seg[1], seg[2]
		if to - from > 0.5 then
			local count = math.max(1, math.floor((to - from) / POST_SPACING + 0.5))
			for i = 0, count do
				local p = a + dir * (from + (to - from) * i / count)
				post(parent, p.X, p.Z, 3.2)
			end
			rails(parent, a + dir * from, a + dir * to)
		end
	end
end

function DryingYard.build(parent: Instance, yard: Yard, porchFront: Vector3, rng: Random)
	local m = Instance.new("Model")
	m.Name = "DryingYard"
	local cx, cz = (yard.x1 + yard.x2) / 2, (yard.z1 + yard.z2) / 2
	local w, d = yard.x2 - yard.x1, yard.z2 - yard.z1

	-- Ubita ziemia na całym placu i jaśniejsza alejka na środku
	make(m, {
		Name = "YardGround",
		Size = Vector3.new(w, 0.2, d),
		Position = Vector3.new(cx, -0.02, cz),
		Color = DIRT,
		CanQuery = false,
	})
	make(m, {
		Name = "Aisle",
		Size = Vector3.new(7, 0.2, d - 4),
		Position = Vector3.new(yard.aisleX, 0.01, cz),
		Color = DIRT:Lerp(Palette.stone, 0.35),
		CanCollide = false,
		CanQuery = false,
	})

	-- Płot dookoła, z bramą w ścianie od strony lasu (z2), na wprost alejki
	local nw = Vector3.new(yard.x1, 0, yard.z1)
	local ne = Vector3.new(yard.x2, 0, yard.z1)
	local sw = Vector3.new(yard.x1, 0, yard.z2)
	local se = Vector3.new(yard.x2, 0, yard.z2)
	fence(m, nw, ne)
	fence(m, nw, sw)
	fence(m, ne, se)
	local gateFrom = yard.aisleX - GATE_HALF - yard.x1
	fence(m, sw, se, gateFrom, gateFrom + GATE_HALF * 2)

	-- Brama: dwa wyższe słupy, belka i szyld z napisem na zewnątrz placu (+Z)
	local height = 7.5
	for _, side in { -1, 1 } do
		local x = yard.aisleX + side * GATE_HALF
		make(m, {
			Name = "GatePost",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(height, 1, 1),
			CFrame = CFrame.new(x, height / 2, yard.z2) * VERTICAL,
			Color = Palette.log,
		})
		Props.hangingLantern(m, Vector3.new(x, height - 0.6, yard.z2 + 0.9), 16)
	end
	make(m, {
		Name = "GateBeam",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(GATE_HALF * 2 + 2, 0.9, 0.9),
		CFrame = CFrame.new(yard.aisleX, height - 0.3, yard.z2),
		Color = Palette.log,
	})
	-- Front szyldu (lokalne -Z) obrócony w stronę +Z, czyli do nadchodzącego gracza
	Props.signBoard(
		m,
		CFrame.new(yard.aisleX, height - 1.9, yard.z2 + 0.2) * CFrame.Angles(0, math.pi, 0),
		Vector3.new(6.4, 1.7, 0.3),
		"YARD_SIGN",
		Enum.NormalId.Front
	)

	-- Kamienna ścieżka od ganku łukiem do bramy (prosto przecięłaby róg placu)
	local gate = Vector3.new(yard.aisleX, 0, yard.z2 + 3)
	local bend = Vector3.new(yard.x2 + 2, 0, yard.z2 + 3)
	local from = porchFront
	local to = bend
	local length = (to - from).Magnitude
	local dist = 0
	while dist < length do
		local p = from:Lerp(to, dist / length)
		local size = rng:NextNumber(1.8, 2.6)
		make(m, {
			Name = "PathStone",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, size, size * rng:NextNumber(0.8, 1)),
			CFrame = CFrame.new(p.X + rng:NextNumber(-0.5, 0.5), -0.04, p.Z + rng:NextNumber(-0.5, 0.5)) * VERTICAL * CFrame.Angles(rng:NextNumber(0, math.pi * 2), 0, 0),
			Color = Palette.stone:Lerp(Palette.ground[1], rng:NextNumber(0.3, 0.5)),
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		})
		dist += rng:NextNumber(2.4, 3.1)
	end
	-- Drugi odcinek: wzdłuż płotu do bramy
	length = (gate - bend).Magnitude
	dist = 0
	while dist < length do
		local p = bend:Lerp(gate, dist / length)
		local size = rng:NextNumber(1.8, 2.6)
		make(m, {
			Name = "PathStone",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, size, size * rng:NextNumber(0.8, 1)),
			CFrame = CFrame.new(p.X + rng:NextNumber(-0.5, 0.5), -0.04, p.Z + rng:NextNumber(-0.5, 0.5)) * VERTICAL * CFrame.Angles(rng:NextNumber(0, math.pi * 2), 0, 0),
			Color = Palette.stone:Lerp(Palette.ground[1], rng:NextNumber(0.3, 0.5)),
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		})
		dist += rng:NextNumber(2.4, 3.1)
	end

	m.Parent = parent
end

return DryingYard
