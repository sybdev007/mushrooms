--!strict
-- Postęp poza samym zbieraniem: Grzybopedia (atlas), codzienne zadania, seria logowań
-- i tygodniowe wyniki do rankingów. Czysta logika bez Robloxa, testowana w Lune.
--
-- Zapis w danych gracza (DataService):
--   atlas  = { [gatunek] = maska bitów wariantów }: bit 1 zwykły, 2 srebrny, 4 złoty, 8 tęczowy
--   atlasDone = { "forest:2", ... } kamienie milowe, o których gracz już dostał komunikat
--   bestiary = { [strażnik] = { found, stolen, escaped, caught } } zakładka Strażnicy w Grzybopedii
--   daily  = { day, quests = { { id, n, done } }, rerolled, bonusDone }
--   streak = { day, count } ostatni odebrany dzień i długość serii
--   weekly = { week, steals, best } do rankingów (best = zakodowane najlepsze znalezisko)

local Config = require(script.Parent.Config)
local Economy = require(script.Parent.Economy)

local Progress = {}

-- ===== Grzybopedia =====

-- Strony księgi: po jednej na świat
Progress.PAGES = { "forest", "cave", "swamp" }

-- Progi każdej strony: wszystkie gatunki co najmniej w danej randze wariantu.
-- bonus = stały dodatek do ceny przy sprzedaży; każdy próg daje lepszy tytuł nad głową
-- (Odkrywca → Tropiciel → Znawca → Mistrz danego świata). Pokazuje się najlepszy zdobyty.
export type Tier = { rank: number, bonus: number, key: string, title: string? }
Progress.TIERS = {
	{ rank = 0, bonus = 0.03, key = "ATLAS_TIER_0", title = "TITLE_EXPLORER_" }, -- odkryj każdy gatunek
	{ rank = 1, bonus = 0.03, key = "ATLAS_TIER_1", title = "TITLE_TRACKER_" }, -- każdy co najmniej srebrny
	{ rank = 2, bonus = 0.05, key = "ATLAS_TIER_2", title = "TITLE_EXPERT_" }, -- złoty
	{ rank = 3, bonus = 0.10, key = "ATLAS_TIER_3", title = "TITLE_MASTER_" }, -- tęczowy
} :: { Tier }
-- Wszystkie strony na tęczę: tytuł ponad wszystkie
Progress.GRANDMASTER = "TITLE_GRANDMASTER"

local function bit(rank: number): number
	return 2 ^ rank
end

-- Gatunki na stronie świata, od najpłytszej strefy i najtańszego (bez błędnych ogników)
local pageCache: { [string]: { Config.SpeciesDef } } = {}
function Progress.pageSpecies(page: string): { Config.SpeciesDef }
	local cached = pageCache[page]
	if cached then
		return cached
	end
	local list = {}
	for _, species in Config.Species do
		if not species.mimic and Economy.zoneWorld(species.zone) == page then
			table.insert(list, species)
		end
	end
	table.sort(list, function(a, b)
		if a.zone ~= b.zone then
			return a.zone < b.zone
		end
		return a.value < b.value
	end)
	pageCache[page] = list
	return list
end

function Progress.pageOf(speciesId: string): string?
	local species = Economy.getSpecies(speciesId)
	if not species or species.mimic then
		return nil
	end
	return Economy.zoneWorld(species.zone)
end

-- Maska z zapisu; stare zapisy miały true (= znaleziony zwykły)
function Progress.mask(atlas: { [string]: any }, speciesId: string): number
	local value = atlas[speciesId]
	if value == true then
		return 1
	end
	return if typeof(value) == "number" then value else 0
end

function Progress.has(atlas: { [string]: any }, speciesId: string, rank: number): boolean
	return Progress.mask(atlas, speciesId) // bit(rank) % 2 == 1
end

-- Wpisuje znalezisko. Zwraca: nowy wpis (ta forma pierwszy raz), nowy gatunek (pierwszy raz w ogóle)
function Progress.discover(atlas: { [string]: any }, speciesId: string, variant: string?): (boolean, boolean)
	if not Progress.pageOf(speciesId) then
		return false, false
	end
	local mask = Progress.mask(atlas, speciesId)
	local flag = bit(Economy.variantRank(variant))
	if mask // flag % 2 == 1 then
		atlas[speciesId] = mask -- przy okazji zamienia stare true na liczbę
		return false, false
	end
	atlas[speciesId] = mask + flag
	return true, mask == 0
end

-- Ile gatunków strony ma formę co najmniej tej rangi
function Progress.tierProgress(atlas: { [string]: any }, page: string, rank: number): (number, number)
	local list = Progress.pageSpecies(page)
	local count = 0
	for _, species in list do
		-- Maska >= 2^ranga = jest jakaś forma tej rangi albo rzadsza
		if Progress.mask(atlas, species.id) >= bit(rank) then
			count += 1
		end
	end
	return count, #list
end

function Progress.tierDone(atlas: { [string]: any }, page: string, rank: number): boolean
	local count, total = Progress.tierProgress(atlas, page, rank)
	return total > 0 and count >= total
end

-- Wpisy odkryte / wszystkie (gatunek x 4 formy) na stronie
function Progress.entries(atlas: { [string]: any }, page: string): (number, number)
	local found, total = 0, 0
	for _, species in Progress.pageSpecies(page) do
		local mask = Progress.mask(atlas, species.id)
		for rank = 0, 3 do
			total += 1
			if mask // bit(rank) % 2 == 1 then
				found += 1
			end
		end
	end
	return found, total
end

-- Ukończone progi jako "strona:ranga"
function Progress.milestones(atlas: { [string]: any }): { string }
	local list = {}
	for _, page in Progress.PAGES do
		for _, tier in Progress.TIERS do
			if Progress.tierDone(atlas, page, tier.rank) then
				table.insert(list, page .. ":" .. tier.rank)
			end
		end
	end
	return list
end

-- Stały dodatek do ceny przy sprzedaży (0.15 = +15%)
function Progress.atlasBonus(atlas: { [string]: any }): number
	local bonus = 0
	for _, page in Progress.PAGES do
		for _, tier in Progress.TIERS do
			if Progress.tierDone(atlas, page, tier.rank) then
				bonus += tier.bonus
			end
		end
	end
	return bonus
end

-- Najlepszy tytuł (klucz tłumaczenia) albo nil
function Progress.title(atlas: { [string]: any }): string?
	local all = true
	for _, page in Progress.PAGES do
		if not Progress.tierDone(atlas, page, 3) then
			all = false
		end
	end
	if all then
		return Progress.GRANDMASTER
	end
	-- Najwyższy próg z tytułem, przy remisie najgłębszy świat
	for i = #Progress.TIERS, 1, -1 do
		local tier = Progress.TIERS[i]
		if tier.title then
			for p = #Progress.PAGES, 1, -1 do
				local page = Progress.PAGES[p]
				if Progress.tierDone(atlas, page, tier.rank) then
					return tier.title .. string.upper(page)
				end
			end
		end
	end
	return nil
end

-- ===== Strażnicy (zakładka w Grzybopedii) =====
-- Strażnika poznaje się, gdy ukradnie mu się grzyb, którego pilnuje (zerwany w legowisku albo
-- zabrany ze skarbca). Do tego liczniki: ile razy ukradłeś, uciekłeś i dałeś się złapać.
-- Kolejność = kolejność kart w zakładce. key = klucz tłumaczenia (_TITLE, _LORE, _TIP to opisy).

export type GuardianDef = {
	id: string,
	world: string,
	key: string,
	chase: { speed: number, wakeDelay: number, catchRadius: number, giveUpSeconds: number },
	lair: { centerZ: number, respawnSeconds: number },
}
Progress.GUARDIANS = {
	{ id = "leszy", world = "forest", key = "BOSS_LESZY", chase = Config.Leszy, lair = Config.Grove },
	{ id = "skarbnik", world = "cave", key = "BOSS_SKARBNIK", chase = Config.Skarbnik, lair = Config.Lair },
	{ id = "utopiec", world = "swamp", key = "BOSS_UTOPIEC", chase = Config.Utopiec, lair = Config.UtopiecLair },
} :: { GuardianDef }

-- Zapis: bestiary[strażnik] = { found, stolen, escaped, caught }
export type GuardianRecord = { found: boolean, stolen: number, escaped: number, caught: number }
-- Zdarzenia z gry i licznik, który posuwają
local GUARDIAN_COUNTERS: { [string]: string } = { steal = "stolen", escape = "escaped", caught = "caught" }

local guardianById: { [string]: GuardianDef } = {}
for _, def in Progress.GUARDIANS do
	guardianById[def.id] = def
end
function Progress.getGuardian(id: string): GuardianDef?
	return guardianById[id]
end

function Progress.newGuardianRecord(): GuardianRecord
	return { found = false, stolen = 0, escaped = 0, caught = 0 }
end

-- Wpis strażnika (pusty, gdy gracz jeszcze go nie spotkał). Nie zmienia zapisu.
function Progress.guardianRecord(bestiary: { [string]: GuardianRecord }, id: string): GuardianRecord
	return bestiary[id] or Progress.newGuardianRecord()
end

-- Zdarzenie ze strażnikiem: "steal" (ukradziony grzyb, odkrywa wpis), "escape", "caught".
-- Zwraca true, gdy strażnik został właśnie odkryty.
function Progress.guardianEvent(bestiary: { [string]: GuardianRecord }, id: string, kind: string): boolean
	local counter = GUARDIAN_COUNTERS[kind]
	if not guardianById[id] or not counter then
		return false
	end
	local record = bestiary[id]
	if not record then
		record = Progress.newGuardianRecord()
		bestiary[id] = record
	end
	local counts = record :: any
	counts[counter] += 1
	if kind == "steal" and not record.found then
		record.found = true
		return true
	end
	return false
end

-- Odkryci / wszyscy
function Progress.guardiansFound(bestiary: { [string]: GuardianRecord }): (number, number)
	local found = 0
	for _, def in Progress.GUARDIANS do
		local record = bestiary[def.id]
		if record and record.found then
			found += 1
		end
	end
	return found, #Progress.GUARDIANS
end

-- Zapisy sprzed zakładki: kto ma w Grzybopedii grzyb strażnika, ten już go okradł
function Progress.migrateBestiary(bestiary: { [string]: GuardianRecord }, atlas: { [string]: any })
	for _, def in Progress.GUARDIANS do
		local record = bestiary[def.id]
		if not (record and record.found) then
			for _, species in Economy.guardianSpecies(def.id) do
				if Progress.mask(atlas, species.id) > 0 then
					record = record or Progress.newGuardianRecord()
					local found = record :: GuardianRecord
					found.found = true
					bestiary[def.id] = found
					break
				end
			end
		end
	end
end

-- Droga ucieczki: od środka legowiska do końca bezpiecznej strefy świata (chatka, obozowisko, przystań)
function Progress.safeZone(world: string): number?
	for index, zone in Config.Zones do
		if zone.world == world and zone.safe then
			return index
		end
	end
	return nil
end

function Progress.escapeDistance(def: GuardianDef): number
	local safe = Progress.safeZone(def.world)
	local safeEnd = if safe then Config.Zones[safe].endZ else 0
	return def.lair.centerZ - safeEnd
end

-- Najniższy poziom butów, na którym da się uciec z legowiska (nil = nie da się wcale)
function Progress.bootsToEscape(def: GuardianDef): number?
	local distance = Progress.escapeDistance(def)
	for level = 0, Config.Upgrades.boots.maxLevel do
		if Economy.escapes(distance, Economy.upgradeStat("boots", level), def.chase) then
			return level
		end
	end
	return nil
end

-- ===== Nagrody: skala według postępu gracza =====

-- Monety za zadanie / logowanie rosną z najdalszym odblokowanym światem:
-- dwukrotność najcenniejszego zwykłego grzyba w tym świecie.
function Progress.rewardScale(caveUnlocked: boolean, swampUnlocked: boolean): number
	local page = if swampUnlocked then "swamp" elseif caveUnlocked then "cave" else "forest"
	local best = 0
	for _, species in Progress.pageSpecies(page) do
		if not species.grove and not species.lair and not species.guardian then
			best = math.max(best, species.value)
		end
	end
	return math.max(50, best * 2)
end

-- ===== Codzienne zadania =====

export type QuestDef = { id: string, kind: string, goal: number, reward: number }
-- kind = rodzaj zdarzenia z gry (ProgressService.event); reward = mnożnik skali nagrody
Progress.QUESTS = {
	{ id = "pick", kind = "pick", goal = 30, reward = 1 },
	{ id = "pick_mutated", kind = "pickMutated", goal = 6, reward = 1.5 },
	{ id = "pick_gold", kind = "pickGold", goal = 1, reward = 2 },
	{ id = "sell", kind = "sell", goal = 40, reward = 1 },
	{ id = "escape", kind = "escape", goal = 1, reward = 2 },
	{ id = "steal", kind = "steal", goal = 1, reward = 2 },
	{ id = "plant", kind = "plant", goal = 3, reward = 1 },
	{ id = "collect", kind = "collect", goal = 3, reward = 1 },
	{ id = "upgrade", kind = "upgrade", goal = 2, reward = 1 },
	{ id = "discover", kind = "discover", goal = 1, reward = 1.5 },
	{ id = "revive", kind = "revive", goal = 1, reward = 2 }, -- podnieś kumpla, któremu zgasła latarnia
} :: { QuestDef }
Progress.QUESTS_PER_DAY = 3
-- Za wszystkie trzy: monety (x skala) i darmowa mikstura szczęścia na kilka minut
Progress.DAILY_BONUS = { reward = 2, luckSeconds = 300 }

local questById: { [string]: QuestDef } = {}
for _, quest in Progress.QUESTS do
	questById[quest.id] = quest
end
function Progress.getQuest(id: string): QuestDef?
	return questById[id]
end

-- Doba liczona od północy UTC (u nas 1:00 albo 2:00 w nocy)
function Progress.dayIndex(t: number): number
	return t // 86400
end

function Progress.secondsToNextDay(t: number): number
	return 86400 - t % 86400
end

-- Prosty deterministyczny generator (ten sam wynik w grze i w testach)
local function seeded(seed: number): () -> number
	local state = math.floor(seed) % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	local function step(): number
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
	-- Kilka pustych kroków: sąsiednie ziarna (dzień, gracz) dają wtedy zupełnie różne liczby
	for _ = 1, 4 do
		step()
	end
	return step
end

local function pickQuests(seed: number, count: number, exclude: { [string]: boolean }): { string }
	local pool = {}
	for _, quest in Progress.QUESTS do
		if not exclude[quest.id] then
			table.insert(pool, quest.id)
		end
	end
	local nextNumber = seeded(seed)
	local chosen = {}
	for _ = 1, math.min(count, #pool) do
		local index = math.floor(nextNumber() * #pool) + 1
		table.insert(chosen, table.remove(pool, index) :: string)
	end
	return chosen
end

export type QuestState = { id: string, n: number, done: boolean }
export type Daily = { day: number, quests: { QuestState }, rerolled: boolean, bonusDone: boolean }

-- Każdy gracz ma swój zestaw na dany dzień (nie wszyscy naraz muszą kraść)
function Progress.newDaily(day: number, userId: number): Daily
	local quests = {}
	for _, id in pickQuests(day * 7919 + userId, Progress.QUESTS_PER_DAY, {}) do
		table.insert(quests, { id = id, n = 0, done = false })
	end
	return { day = day, quests = quests, rerolled = false, bonusDone = false }
end

-- Nowy dzień = nowe zadania. Zwraca true, gdy zestaw się zmienił.
function Progress.ensureDaily(data: { daily: Daily }, day: number, userId: number): boolean
	if data.daily.day == day and #data.daily.quests > 0 then
		return false
	end
	data.daily = Progress.newDaily(day, userId)
	return true
end

-- Zdarzenie z gry. Zwraca ukończone teraz zadania i czy właśnie skończyły się wszystkie.
function Progress.questEvent(daily: Daily, kind: string, amount: number?): ({ QuestDef }, boolean)
	local completed = {}
	for _, state in daily.quests do
		local def = questById[state.id]
		if def and def.kind == kind and not state.done then
			state.n = math.min(def.goal, state.n + (amount or 1))
			if state.n >= def.goal then
				state.done = true
				table.insert(completed, def)
			end
		end
	end
	local allDone = false
	if #completed > 0 and not daily.bonusDone then
		allDone = true
		for _, state in daily.quests do
			if not state.done then
				allDone = false
			end
		end
		if allDone then
			daily.bonusDone = true
		end
	end
	return completed, allDone
end

-- Raz dziennie można wymienić jedno nieukończone zadanie na inne
function Progress.reroll(daily: Daily, index: number, userId: number): boolean
	local state = daily.quests[index]
	if daily.rerolled or not state or state.done then
		return false
	end
	local exclude = {}
	for _, other in daily.quests do
		exclude[other.id] = true
	end
	local replacement = pickQuests(daily.day * 104729 + userId * 31 + index, 1, exclude)[1]
	if not replacement then
		return false
	end
	daily.quests[index] = { id = replacement, n = 0, done = false }
	daily.rerolled = true
	return true
end

function Progress.questReward(def: QuestDef, scale: number): number
	return math.floor(def.reward * scale)
end

-- ===== Seria logowań =====

-- Mnożniki skali nagrody za kolejne dni serii (7. dzień: dodatkowo mikstura szczęścia)
Progress.LOGIN_REWARDS = { 0.5, 0.75, 1, 1.25, 1.5, 2, 3 }
Progress.LOGIN_LUCK_SECONDS = 600

export type Streak = { day: number, count: number }

-- Odbiór nagrody za dzisiejsze wejście. Zwraca dzień w cyklu 1..7 albo nil, gdy już odebrana.
-- Przerwa dłuższa niż dzień zaczyna serię od nowa.
function Progress.claimLogin(streak: Streak, today: number): number?
	if streak.day == today then
		return nil
	end
	streak.count = if streak.day == today - 1 then streak.count + 1 else 1
	streak.day = today
	return (streak.count - 1) % #Progress.LOGIN_REWARDS + 1
end

-- ===== Tydzień (rankingi) =====

-- Tydzień od poniedziałku 00:00 UTC (1 stycznia 1970 był czwartkiem)
function Progress.weekIndex(t: number): number
	return (t - 4 * 86400) // 604800
end

export type Weekly = { week: number, steals: number, best: number }

function Progress.ensureWeek(data: { weekly: Weekly }, week: number): boolean
	if data.weekly.week == week then
		return false
	end
	data.weekly = { week = week, steals = 0, best = 0 }
	return true
end

-- Znalezisko jako jedna liczba do OrderedDataStore: wartość * 1000 + gatunek * 10 + ranga wariantu.
-- Większa liczba = cenniejsze, a z reszty da się odczytać, co to był za grzyb.
local speciesIndex: { [string]: number } = {}
for index, species in Config.Species do
	speciesIndex[species.id] = index
end

function Progress.encodeFind(speciesId: string, variant: string?, value: number): number
	local index = speciesIndex[speciesId] or 0
	return math.floor(value) * 1000 + index * 10 + Economy.variantRank(variant)
end

function Progress.decodeFind(score: number): (number, string?, number)
	local rest = score % 1000
	local species = Config.Species[rest // 10]
	return score // 1000, if species then species.id else nil, rest % 10
end

return Progress
