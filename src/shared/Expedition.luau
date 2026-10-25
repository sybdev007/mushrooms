--!strict
-- Wspólne wyprawy: gracze blisko siebie w niebezpiecznej strefie łączą latarnie
-- (olej pali się wolniej, światło sięga dalej). Gdy komuś zgaśnie latarnia, a w pobliżu jest
-- ktoś, kto może pomóc, gracz nie znika od razu w mroku, tylko czeka chwilę na podniesienie.
-- Czysta logika (testy w Lune); podpięcie pod grę w GameService.

local Expedition = {}

Expedition.RADIUS = 20 -- tak blisko trzeba iść, żeby latarnie się połączyły (studs)
-- Według wielkości grupy (1 = sam): mnożnik spalania oleju i zasięgu światła
Expedition.DRAIN = { 1, 0.75, 0.65, 0.6 }
Expedition.LIGHT = { 1, 1.25, 1.4, 1.5 }

Expedition.DOWN_SECONDS = 15 -- tyle czasu ma kumpel, żeby podnieść gracza
Expedition.HELP_RADIUS = 150 -- ktoś musi być tak blisko, inaczej las pochłania od razu
Expedition.REVIVE_OIL = 0.3 -- po podniesieniu latarnia ma taką część oleju
Expedition.REVIVE_HOLD = 1.5 -- sekundy przytrzymania przycisku
Expedition.REVIVE_DISTANCE = 9

local function pick(list: { number }, size: number): number
	return list[math.clamp(math.floor(size), 1, #list)]
end

function Expedition.drain(size: number?): number
	return pick(Expedition.DRAIN, size or 1)
end

function Expedition.light(size: number?): number
	return pick(Expedition.LIGHT, size or 1)
end

export type Walker = { id: any, position: Vector3 }

-- Wielkość grupy każdego gracza: on sam + wszyscy w promieniu (liczymy sąsiadów bezpośrednich,
-- bez łańcuszków, żeby rozciągnięta kolejka nie dzieliła bonusu)
function Expedition.groupSizes(walkers: { Walker }, radius: number?): { [any]: number }
	local limit = radius or Expedition.RADIUS
	local sizes = {}
	for _, a in walkers do
		local count = 1
		for _, b in walkers do
			if a ~= b then
				local offset = a.position - b.position
				if Vector3.new(offset.X, 0, offset.Z).Magnitude <= limit then
					count += 1
				end
			end
		end
		sizes[a.id] = count
	end
	return sizes
end

-- Procent do pokazania w HUD: ile mniej oleju, ile więcej światła
function Expedition.bonusPercents(size: number): (number, number)
	return math.floor((1 - Expedition.drain(size)) * 100 + 0.5), math.floor((Expedition.light(size) - 1) * 100 + 0.5)
end

return Expedition
