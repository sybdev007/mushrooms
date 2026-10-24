--!strict
-- Gniazdo Leszego na końcu Mrocznego Jaru: okrągła polana z mchu, krąg stojących kamieni,
-- świecące grzybki, tabliczka ostrzegawcza i uśpiony posąg Leszego za kręgiem.
-- Same grzyby „Korona Leszego” rysuje klient (jak wszystkie grzyby do zbierania).

local Palette = require(script.Parent.Palette)
local Props = require(script.Parent.Props)
local Leszy = require(script.Parent.Leszy)

local Grove = {}

local VERTICAL = CFrame.Angles(0, 0, math.rad(90))
local STONES = 9

local function make(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

-- Zwraca posąg Leszego, żeby serwer mógł mu zapalać oczy podczas pościgu
function Grove.build(parent: Instance, center: Vector3, radius: number, rng: Random): Model
	local m = Instance.new("Model")
	m.Name = "LeszyGrove"

	-- Okrągły dywan z ciemnego mchu
	make({
		Name = "MossCarpet",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, radius * 2, radius * 2),
		CFrame = CFrame.new(center + Vector3.new(0, 0.02, 0)) * VERTICAL,
		Color = Palette.shade(Palette.moss, 0.5),
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
		Parent = m,
	})

	-- Krąg stojących kamieni z przerwą od strony chatki (-Z), żeby było widać wejście
	for i = 1, STONES do
		local angle = (i - 0.5) / STONES * math.pi * 2
		local offset = Vector3.new(math.sin(angle), 0, math.cos(angle)) * radius
		-- Pomijamy kamień najbliżej -Z (wejście)
		if offset.Z > -radius * 0.9 then
			local height = rng:NextNumber(5, 8)
			make({
				Name = "Monolith",
				Size = Vector3.new(rng:NextNumber(2, 2.8), height, rng:NextNumber(1.4, 2)),
				CFrame = CFrame.lookAt(center + offset + Vector3.new(0, height / 2 - 0.4, 0), center + Vector3.new(0, height / 2, 0))
					* CFrame.Angles(rng:NextNumber(-0.08, 0.08), 0, rng:NextNumber(-0.1, 0.1)),
				Color = Palette.shade(Palette.pick(Palette.rock, rng), 0.6),
				Parent = m,
			})
			-- Świecące grzybki u stóp co drugiego kamienia
			if i % 2 == 0 then
				Props.glowCluster(m, center + offset * 0.86, rng)
			end
		end
	end

	-- Tabliczka przy wejściu, napis od strony nadchodzącego gracza
	local signPos = center + Vector3.new(4.5, 0, -radius - 2)
	make({ Name = "SignPost", Size = Vector3.new(0.5, 4, 0.5), Position = signPos + Vector3.new(0, 2, 0.3), Color = Palette.plankDark, Parent = m })
	Props.signBoard(m, CFrame.new(signPos + Vector3.new(0, 3.6, 0)) * CFrame.Angles(0, 0, math.rad(-6)), Vector3.new(6, 1.6, 0.3), "GROVE_SIGN", Enum.NormalId.Front)

	-- Uśpiony Leszy stoi za kręgiem i patrzy na polanę
	local statueAt = center + Vector3.new(0, 0, radius + 4)
	local statue = Leszy.build(m, CFrame.lookAt(statueAt, Vector3.new(center.X, 0, center.Z)), false)
	statue.Name = "LeszyStatue"

	m.Parent = parent
	return statue
end

return Grove
