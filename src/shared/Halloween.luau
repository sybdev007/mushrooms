--!strict
-- Event Halloween „Noc Dziadów” (czysta logika bez Robloxa, testy w Lune). Liczby są w Config.Halloween.
--   Dyniowe grzyby: cecha „pumpkin” (Config.EventTags), losowana tylko w czasie eventu.
--   Cukierki: za sprzedane dyniowe grzyby (zależnie od świata) i za zadania dnia; licznik stats.candy.
--   Ścieżka nagród: progi cukierków, nagrody przychodzą same (tytuły liczy Titles, resztę ProgressService).
--   Noc Dziadów: zdarzenie nocy z Cycle.eventFor (co trzecia noc w czasie eventu).

local Config = require(script.Parent.Config)
local Cycle = require(script.Parent.Cycle)
local Economy = require(script.Parent.Economy)

local Halloween = {}

Halloween.TAG = "pumpkin"
Halloween.SPIRIT_NIGHT = "spirit_night"
Halloween.TRACK = Config.Halloween.track

export type Item = { s: string, v: string?, x: { string }? }

function Halloween.active(t: number): boolean
	local h = Config.Halloween
	return t >= h.startsAt and t < h.endsAt
end

-- Sekundy do końca eventu (0 = już po)
function Halloween.secondsLeft(t: number): number
	return math.max(0, Config.Halloween.endsAt - t)
end

-- Szansa, że grzyb wyrośnie dyniowy. Stała (szczęście jej nie zmienia, żeby cukierków nie było
-- za dużo na głębszych światach): zwykła, w Noc Dziadów albo w czasie „Dyniowego wysypu”.
function Halloween.pumpkinChance(t: number, eventId: string?, boom: boolean?): number
	if not Halloween.active(t) then
		return 0
	end
	local h = Config.Halloween
	if boom then
		return h.boomPumpkinChance
	elseif eventId == Halloween.SPIRIT_NIGHT then
		return h.spiritPumpkinChance
	end
	return h.pumpkinChance
end

-- Czy gatunek może być dyniowy (błędne ogniki nie: nic nie są warte i zdradzałyby się kolorem)
function Halloween.canBePumpkin(speciesId: string): boolean
	local species = Economy.getSpecies(speciesId)
	return species ~= nil and not species.mimic
end

function Halloween.isPumpkin(item: Item): boolean
	return item.x ~= nil and table.find(item.x, Halloween.TAG) ~= nil
end

-- Cukierki za sprzedany grzyb: tylko dyniowy, więcej za głębsze światy
function Halloween.candyFor(item: Item): number
	if not Halloween.isPumpkin(item) then
		return 0
	end
	local species = Economy.getSpecies(item.s)
	if not species or species.mimic then
		return 0
	end
	return Config.Halloween.candyByWorld[Economy.zoneWorld(species.zone)] or 1
end

function Halloween.candyForList(items: { any }): number
	local total = 0
	for _, item in items do
		total += Halloween.candyFor(item)
	end
	return total
end

-- Ile progów ścieżki gracz osiągnął przy tylu cukierkach
function Halloween.reached(candy: number): number
	local count = 0
	for index, step in Halloween.TRACK do
		if candy >= step.candy then
			count = index
		end
	end
	return count
end

-- Progi osiągnięte od ostatniego razu (claimed = ile już dostał). Nie zmienia zapisu.
function Halloween.newSteps(claimed: number, candy: number): { number }
	local list = {}
	for index = math.max(claimed, 0) + 1, Halloween.reached(candy) do
		table.insert(list, index)
	end
	return list
end

-- ===== Skórki =====

Halloween.SKINS = Config.Halloween.skins
Halloween.SLOTS = { "lantern", "knife" }

function Halloween.getSkin(id: any): { slot: string, key: string, icon: string }?
	return if typeof(id) == "string" then Halloween.SKINS[id] else nil
end

-- Próg ścieżki, który daje skórkę (nil = tylko z kotła)
function Halloween.trackCandyFor(skin: string): number?
	for _, step in Halloween.TRACK do
		if step.kind == "skin" and step.id == skin then
			return step.candy
		end
	end
	return nil
end

-- Czy gracz ma skórkę: z kotła (zapisana lista) albo z osiągniętego progu ścieżki
function Halloween.ownsSkin(skins: { string }, candy: number, skin: string): boolean
	if not Halloween.SKINS[skin] then
		return false
	end
	if table.find(skins, skin) then
		return true
	end
	local need = Halloween.trackCandyFor(skin)
	return need ~= nil and candy >= need
end

-- ===== Kocioł „cukierek albo psikus” =====

export type Outcome = { id: string, weight: number, scale: number?, seconds: number?, amount: number?, skin: string?, trick: boolean? }

-- Wynik dla liczby r z [0, 1) według wag z Config.Halloween.cauldron.outcomes
function Halloween.rollCauldron(r: number): Outcome
	local outcomes = Config.Halloween.cauldron.outcomes
	local total = 0
	for _, outcome in outcomes do
		total += outcome.weight
	end
	local target = math.clamp(r, 0, 0.999999) * total
	local acc = 0
	for _, outcome in outcomes do
		acc += outcome.weight
		if target < acc then
			return outcome
		end
	end
	return outcomes[1]
end

-- Szansa na nagrodę (nie psikus), do opisu w oknie
function Halloween.treatChance(): number
	local total, treats = 0, 0
	for _, outcome in Config.Halloween.cauldron.outcomes do
		total += outcome.weight
		if not outcome.trick then
			treats += outcome.weight
		end
	end
	return if total > 0 then treats / total else 0
end

-- Najbliższa Noc Dziadów: (start w os.time, czy już trwa). nil = w czasie eventu już żadnej nie będzie.
function Halloween.nextSpiritNight(t: number): (number?, boolean)
	local length = Cycle.length()
	local index = t // length
	for i = index, index + Config.Halloween.spiritEvery do
		if Cycle.eventFor(i).id == Halloween.SPIRIT_NIGHT then
			local start = i * length
			if t < start + Config.Cycle.nightSeconds then
				return start, t >= start
			end
		end
	end
	return nil, false
end

return Halloween
