--!strict
-- Zimowy event (czysta logika bez Robloxa, testy w Lune). Liczby są w Config.Winter.
--   Oszronione grzyby: cecha „frost” (Config.EventTags), losowana tylko w czasie eventu.
--   Płatki śniegu: za sprzedane oszronione grzyby (zależnie od świata) i za zadania dnia; licznik
--   stats.snowflakes (zebrane łącznie) i kieszeń data.flakeBag (do wydania na choince).
--   Ścieżka nagród: progi płatków, nagrody przychodzą same (tytuły liczy Titles, resztę ProgressService).
--   Kalendarz adwentowy: od 1 do 24 grudnia po jednym prezencie dziennie (tylko dzisiejsze okienko).
--   Choinka z prezentami: losowanie prezentu albo psikusa za płatki (WinterService).
-- Przed startem eventu nic z tego nie widać: wszystko sprawdza Winter.active (serwer) albo atrybut
-- Workspace.Winter (klient), który ustawia GameService.

local Config = require(script.Parent.Config)
local Economy = require(script.Parent.Economy)

local Winter = {}

Winter.TAG = "frost"
Winter.TRACK = Config.Winter.track
Winter.SKINS = Config.Winter.skins
Winter.ADVENT = Config.Winter.advent
Winter.DAY = 86400

export type Item = { s: string, v: string?, x: { string }? }

-- Podgląd z panelu DEV (tylko w Studio, GameService): zima działa niezależnie od daty, a dzień
-- kalendarza można przestawić. Na serwerze gry zawsze false / nil.
Winter.forced = false
Winter.devDay = nil :: number?

function Winter.active(t: number): boolean
	local w = Config.Winter
	return Winter.forced or (t >= w.startsAt and t < w.endsAt)
end

-- Sekundy do końca eventu (0 = już po). W podglądzie przed startem: cały czas trwania.
function Winter.secondsLeft(t: number): number
	local w = Config.Winter
	return math.max(0, w.endsAt - math.max(t, w.startsAt))
end

-- Szansa, że grzyb wyrośnie oszroniony. Stała (szczęście jej nie zmienia), większa w czasie „Zamieci”.
function Winter.frostChance(t: number, boom: boolean?): number
	if not Winter.active(t) then
		return 0
	end
	return if boom then Config.Winter.boomFrostChance else Config.Winter.frostChance
end

-- Czy gatunek może być oszroniony (błędne ogniki nie: nic nie są warte i zdradzałyby się kolorem)
function Winter.canBeFrost(speciesId: string): boolean
	local species = Economy.getSpecies(speciesId)
	return species ~= nil and not species.mimic
end

function Winter.isFrost(item: Item): boolean
	return item.x ~= nil and table.find(item.x, Winter.TAG) ~= nil
end

-- Płatki za sprzedany grzyb: tylko oszroniony, więcej za głębsze światy
function Winter.flakesFor(item: Item): number
	if not Winter.isFrost(item) then
		return 0
	end
	local species = Economy.getSpecies(item.s)
	if not species or species.mimic then
		return 0
	end
	return Config.Winter.flakesByWorld[Economy.zoneWorld(species.zone)] or 1
end

function Winter.flakesForList(items: { any }): number
	local total = 0
	for _, item in items do
		total += Winter.flakesFor(item)
	end
	return total
end

-- Ile progów ścieżki gracz osiągnął przy tylu płatkach
function Winter.reached(flakes: number): number
	local count = 0
	for index, step in Winter.TRACK do
		if flakes >= step.flakes then
			count = index
		end
	end
	return count
end

-- Progi osiągnięte od ostatniego razu (claimed = ile już dostał). Nie zmienia zapisu.
function Winter.newSteps(claimed: number, flakes: number): { number }
	local list = {}
	for index = math.max(claimed, 0) + 1, Winter.reached(flakes) do
		table.insert(list, index)
	end
	return list
end

-- ===== Skórki (wspólna lista wszystkich eventów: Shared/Skins) =====

function Winter.getSkin(id: any): { slot: string, key: string, icon: string }?
	return if typeof(id) == "string" then Winter.SKINS[id] else nil
end

-- Próg ścieżki, który daje skórkę (nil = tylko z choinki)
function Winter.trackFlakesFor(skin: string): number?
	for _, step in Winter.TRACK do
		if step.kind == "skin" and step.id == skin then
			return step.flakes
		end
	end
	return nil
end

-- Czy gracz ma skórkę: z choinki (zapisana lista) albo z osiągniętego progu ścieżki
function Winter.ownsSkin(skins: { string }, flakes: number, skin: string): boolean
	if not Winter.SKINS[skin] then
		return false
	end
	if table.find(skins, skin) then
		return true
	end
	local need = Winter.trackFlakesFor(skin)
	return need ~= nil and flakes >= need
end

-- ===== Choinka z prezentami =====

export type Outcome = { id: string, weight: number, scale: number?, seconds: number?, amount: number?, skin: string?, trick: boolean? }

-- Wynik dla liczby r z [0, 1) według wag z Config.Winter.tree.outcomes
function Winter.rollGift(r: number): Outcome
	local outcomes = Config.Winter.tree.outcomes
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

-- Szansa na prezent (nie psikus), do opisu w oknie
function Winter.treatChance(): number
	local total, treats = 0, 0
	for _, outcome in Config.Winter.tree.outcomes do
		total += outcome.weight
		if not outcome.trick then
			treats += outcome.weight
		end
	end
	return if total > 0 then treats / total else 0
end

-- ===== Kalendarz adwentowy =====

-- Dzisiejsze okienko kalendarza (1..24) albo nil (przed eventem, po Wigilii, po evencie)
function Winter.adventDay(t: number): number?
	if Winter.devDay then
		return Winter.devDay
	end
	if not Winter.active(t) then
		return nil
	end
	local day = (t - Config.Winter.startsAt) // Winter.DAY + 1
	return if day >= 1 and day <= #Winter.ADVENT then day else nil
end

-- Sekundy do następnego okienka (północ UTC)
function Winter.secondsToNextDay(t: number): number
	return Winter.DAY - (t - Config.Winter.startsAt) % Winter.DAY
end

-- Czy dzisiejsze okienko można otworzyć (opened: numery otwartych dni)
function Winter.canOpen(opened: { number }, day: number?): boolean
	return day ~= nil and Winter.ADVENT[day] ~= nil and table.find(opened, day) == nil
end

return Winter
