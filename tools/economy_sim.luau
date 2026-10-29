-- Symulacja ekonomii: jak szybko gracz przechodzi przez gre przy rozsadnej grze.
-- Uruchom z katalogu projektu: lune run tools/economy_sim.luau
-- Laduje te same pliki co gra (Config, Economy, Progress). Model jest przyblizony:
--   wyprawa = dojscie do strefy, zbieranie az do pelnego koszyka albo granicy oleju, powrot, sprzedaz;
--   gracz wybiera strefe z najlepszymi monetami na minute i kupuje ulepszenia, ktore szybko sie zwracaja;
--   ogrodek: obsadzone grzadki najlepszymi grzybami (2x srednia strefy), 4% wartosci na minute.

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local function loadModule(path: string, env: { [string]: any }): any
	local source = fs.readFile(path)
	local chunk = luau.load(source, { debugName = path, environment = env })
	return chunk()
end

local Config = loadModule("src/shared/Config.luau", {})
local Economy = loadModule("src/shared/Economy.luau", {
	script = { Parent = { Config = Config } },
	require = function(module)
		return module
	end,
})
local Progress = loadModule("src/shared/Progress.luau", {
	script = { Parent = { Config = Config, Economy = Economy } },
	require = function(module)
		return module
	end,
})

-- Opcjonalnie: lune run tools/economy_sim.luau <monety na jaskinie> <monety na bagna>
local process = require("@lune/process")
if process.args[1] then
	Config.Cave.unlockCoins = tonumber(process.args[1])
end
if process.args[2] then
	Config.Swamp.unlockCoins = tonumber(process.args[2])
end

local WIDTH = { forest = Config.ForestHalfWidth * 2, cave = Config.Cave.halfWidth * 2, swamp = Config.Swamp.halfWidth * 2 }
local PICK_SECONDS = 0.6 -- schylenie sie i zerwanie
local SELL_SECONDS = 8 -- rozmowa ze skupem / kramik
local ROI_MINUTES = 12 -- kupuje ulepszenie, gdy zwroci sie w tylu minutach
local ECON = { "oil", "basket", "boots", "knife", "crystal", "pack", "rushwick", "creel", "beds", "fertilizer" }

type State = {
	levels: { [string]: number },
	cave: boolean,
	swamp: boolean,
	coins: number,
	minutes: number,
	earned: number,
}

local function stat(s: State, id: string): number
	return Economy.upgradeStat(id, s.levels[id] or 0)
end

local function basket(s: State): number
	return stat(s, "basket") + stat(s, "pack") + stat(s, "creel")
end

-- Srednia wartosc zerwanego grzyba w strefie (z mutacjami przy szczesciu z nozyka i glebokosci)
local function pickValue(s: State, zone: number): number
	local weight, sum = 0, 0
	for _, species in Economy.speciesForZone(zone) do
		if species.weight > 0 then
			weight += species.weight
			sum += species.weight * species.value
		end
	end
	if weight == 0 then
		return 0
	end
	local luck = Economy.luck({ knifeLevel = s.levels.knife or 0, zone = zone })
	local variantPart = 1
	for _, odds in Economy.variantOdds(luck) do
		local def = Economy.getVariant(odds.id)
		if def then
			variantPart += odds.chance * (def.mult - 1)
		end
	end
	local tagPart = 1
	for _, tag in Economy.tagsForZone(zone) do
		tagPart += Economy.tagOdds(tag, luck) * (tag.mult - 1)
	end
	return sum / weight * variantPart * tagPart
end

type Trip = { zone: number, coins: number, seconds: number, picks: number, perMinute: number }

-- Jedna wyprawa do strefy `target`
local function trip(s: State, target: number): Trip?
	local def = Config.Zones[target]
	if def.safe or def.spotCount == 0 then
		return nil
	end
	local world = def.world
	if (world == "cave" and not s.cave) or (world == "swamp" and not s.swamp) then
		return nil
	end
	local speed = stat(s, "boots")
	local oilMax = stat(s, "oil")
	local oilUpgrade = Economy.worldOilUpgrade(world)
	local scale = if oilUpgrade then stat(s, oilUpgrade) else 1
	-- Droga do strefy: bezpieczny kawalek bez oleju + strefy po drodze
	local timeIn = 50 / speed
	local oilIn = 0
	for index = 1, target - 1 do
		local zone = Config.Zones[index]
		if zone.world == world and not zone.safe then
			local seconds = (zone.endZ - zone.startZ) / speed
			timeIn += seconds
			oilIn += seconds * Economy.oilDrain(index, scale)
		end
	end
	local length = def.endZ - def.startZ
	local drain = Economy.oilDrain(target, scale)
	local half = length / 2 / speed * drain -- wejscie w glab strefy i wyjscie
	local oilForPicking = oilMax - oilIn - half - (oilIn + half) * Config.ReturnMargin
	if oilForPicking <= 0 then
		return nil
	end
	local secondsForPicking = oilForPicking / drain
	local between = 0.7 * math.sqrt(WIDTH[world] * length / def.spotCount) / speed + PICK_SECONDS
	local respawns = 1 + math.floor(secondsForPicking / Config.RespawnSeconds)
	local picks = math.min(basket(s), math.floor(secondsForPicking / between), def.spotCount * respawns)
	if picks <= 0 then
		return nil
	end
	local seconds = timeIn * 2 + length / speed + picks * between + oilMax / Config.OilRefillPerSecond + SELL_SECONDS
	local coins = picks * pickValue(s, target)
	return { zone = target, coins = coins, seconds = seconds, picks = picks, perMinute = coins / seconds * 60 }
end

local function bestTrip(s: State): Trip?
	local best: Trip? = nil
	for index in Config.Zones do
		local t = trip(s, index)
		if t and (not best or t.perMinute > best.perMinute) then
			best = t
		end
	end
	return best
end

-- Ogrodek: obsadzone grzadki (najlepsze grzyby ~2x srednia najlepszej strefy)
local function gardenPerMinute(s: State, t: Trip?): number
	if not t then
		return 0
	end
	return stat(s, "beds") * pickValue(s, t.zone) * 2 * Config.Garden.incomeRate * stat(s, "fertilizer")
end

local function income(s: State): number
	local t = bestTrip(s)
	return (if t then t.perMinute else 0) + gardenPerMinute(s, t)
end

local function shopOpen(s: State, id: string): boolean
	local shop = Economy.upgradeShop(id)
	return shop == "forest" or (shop == "cave" and s.cave) or (shop == "swamp" and s.swamp)
end

local function fmtTime(minutes: number): string
	if minutes < 60 then
		return string.format("%d min", math.floor(minutes + 0.5))
	end
	return string.format("%dh %02dmin", minutes // 60, math.floor(minutes % 60))
end

local function fmt(n: number): string
	local s = tostring(math.floor(n + 0.5))
	return (s:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", ""))
end

local s: State = { levels = {}, cave = false, swamp = false, coins = 0, minutes = 0, earned = 0 }
for id in Config.Upgrades do
	s.levels[id] = 0
end

local milestones = {}
local flags: { [string]: boolean } = {}
local function mark(text: string)
	local t = bestTrip(s)
	table.insert(milestones, string.format("%9s  %-46s  %8s/min  strefa %s", fmtTime(s.minutes), text, fmt(income(s)), if t then Config.Zones[t.zone].id else "-"))
end
mark("start")

local bought = 0
local firstBuy = true
for _ = 1, 200000 do
	local t = bestTrip(s)
	assert(t, "brak strefy do zbierania")
	local minutes = t.seconds / 60
	local gain = t.coins + gardenPerMinute(s, t) * minutes
	s.coins += gain
	s.earned += gain
	s.minutes += minutes

	-- Odblokowanie swiatow: trzeba miec monety przy portalu
	if not s.cave and s.coins >= Config.Cave.unlockCoins then
		s.cave = true
		mark("jaskinia otwarta (" .. fmt(Config.Cave.unlockCoins) .. ")")
	end
	if s.cave and not s.swamp and s.coins >= Config.Swamp.unlockCoins then
		s.swamp = true
		mark("bagna otwarte (" .. fmt(Config.Swamp.unlockCoins) .. ")")
	end

	-- Zakupy: najszybciej zwracajace sie ulepszenie
	while true do
		local base = income(s)
		local pick: string? = nil
		local pickRoi = math.huge
		-- Patrzy do 3 poziomów naprzód (jeden poziom oleju bywa za mały, żeby dojść do głębszej strefy)
		for _, id in ECON do
			local cost = Economy.upgradeCost(id, s.levels[id])
			if cost and shopOpen(s, id) and cost <= s.coins then
				local start = s.levels[id]
				local total = 0
				for ahead = 1, 3 do
					local step = Economy.upgradeCost(id, s.levels[id])
					if not step then
						break
					end
					total += step
					s.levels[id] += 1
					local gainRate = income(s) - base
					local roi = if gainRate > 0 then total / gainRate else math.huge
					if roi < pickRoi then
						pick, pickRoi = id, roi
					end
					local _ = ahead
				end
				s.levels[id] = start
			end
		end
		-- Odkladanie na kolejny swiat: tylko zakupy, ktore zwracaja sie bardzo szybko
		-- Tanie ulepszenia (mniej niż 2 minuty zarobku) gracz i tak kupuje, nawet gdy mało dają
		if not pick or pickRoi > ROI_MINUTES then
			pick = nil
			for _, id in ECON do
				local cost = Economy.upgradeCost(id, s.levels[id])
				-- Na bagnach nie ma już na co odkładać: kupuje wszystko, na co stać
				if cost and shopOpen(s, id) and cost <= s.coins and (cost < base * 2 or s.swamp) then
					pick = id
					break
				end
			end
			if not pick then
				break
			end
		end
		s.coins -= Economy.upgradeCost(pick, s.levels[pick]) :: number
		s.levels[pick] += 1
		bought += 1
		if firstBuy then
			firstBuy = false
			mark("pierwsze ulepszenie (" .. pick .. ")")
		end
	end

	-- Wszystko w lesie na maks.
	local function allMax(ids: { string }): boolean
		for _, id in ids do
			if Economy.upgradeCost(id, s.levels[id]) then
				return false
			end
		end
		return true
	end
	if not flags.forestEcon and allMax({ "oil", "basket", "boots" }) then
		flags.forestEcon = true
		mark("olej, koszyk i buty na maks.")
	end
	if not flags.caveEcon and s.cave and allMax({ "crystal", "pack" }) then
		flags.caveEcon = true
		mark("ulepszenia jaskini na maks.")
	end
	if not flags.swampEcon and s.swamp and allMax({ "rushwick", "creel" }) then
		flags.swampEcon = true
		mark("ulepszenia bagien na maks.")
	end
	if not flags.allEcon and allMax(ECON) then
		flags.allEcon = true
		mark("wszystkie ulepszenia dochodowe na maks.")
		break
	end
	if s.minutes > 12 * 60 then
		mark("koniec symulacji (12 h)")
		break
	end
end

print("Przebieg gry (model):")
for _, line in milestones do
	print(line)
end
print(string.format("\nKupionych poziomow: %d, zarobione razem: %s", bought, fmt(s.earned)))

-- Strefy przy kilku poziomach ulepszen: monety na minute, grzyby na wyprawe, dlugosc wyprawy
print("\nStrefy (monety/min | grzyby na wyprawe | minuty wyprawy):")
for _, stage in {
	{ name = "start", levels = {} },
	{ name = "las polowa", levels = { oil = 5, basket = 5, boots = 4 } },
	{ name = "las max", levels = { oil = 10, basket = 10, boots = 8, knife = 3 } },
	{ name = "jaskinia+", levels = { oil = 10, basket = 10, boots = 8, knife = 6, crystal = 5, pack = 6 } },
	{ name = "bagna max", levels = { oil = 10, basket = 10, boots = 8, knife = 6, crystal = 5, pack = 6, rushwick = 6, creel = 5 } },
} do
	local probe: State = { levels = {}, cave = true, swamp = true, coins = 0, minutes = 0, earned = 0 }
	for id in Config.Upgrades do
		probe.levels[id] = (stage.levels :: any)[id] or 0
	end
	local parts = {}
	for index, zone in Config.Zones do
		local t = trip(probe, index)
		if t then
			table.insert(parts, string.format("%s %s|%d|%.1f", zone.id, fmt(t.perMinute), t.picks, t.seconds / 60))
		elseif not zone.safe then
			table.insert(parts, zone.id .. " x")
		end
	end
	print(string.format("  %-11s %s", stage.name, table.concat(parts, "  ")))
end

-- Porownanie: nagrody z zadan i logowania wzgledem zarobku na minute w kazdym swiecie
print("\nNagrody dzienne a dochod (zadanie = 1x skala, komplet = 2x, 7. dzien serii = 3x):")
for _, stage in {
	{ name = "las", cave = false, swamp = false, levels = { oil = 4, basket = 4, boots = 3 } },
	{ name = "jaskinia", cave = true, swamp = false, levels = { oil = 10, basket = 10, boots = 8, crystal = 3, pack = 3, knife = 3 } },
	{ name = "bagna", cave = true, swamp = true, levels = { oil = 10, basket = 10, boots = 8, crystal = 5, pack = 6, knife = 6, rushwick = 3, creel = 2 } },
} do
	local probe: State = { levels = {}, cave = stage.cave, swamp = stage.swamp, coins = 0, minutes = 0, earned = 0 }
	for id in Config.Upgrades do
		probe.levels[id] = (stage.levels :: any)[id] or 0
	end
	local scale = Progress.rewardScale(stage.cave, stage.swamp)
	local perMinute = income(probe)
	print(string.format("  %-9s dochod %8s/min | zadanie %7s (= %.1f min gry) | komplet %7s | dzien 7: %7s",
		stage.name, fmt(perMinute), fmt(scale), scale / perMinute, fmt(scale * Progress.DAILY_BONUS.reward), fmt(scale * 3)))
end

-- Ceny ulepszen: suma do maksimum
print("\nKoszt wszystkich poziomow:")
for _, id in { "lantern", "oil", "basket", "boots", "knife", "beds", "fertilizer", "lock", "crystal", "pack", "rushwick", "creel" } do
	local total, level = 0, 0
	while true do
		local cost = Economy.upgradeCost(id, level)
		if not cost then
			break
		end
		total += cost
		level += 1
	end
	print(string.format("  %-10s %2d poziomow  %12s  (ostatni %s)", id, level, fmt(total), fmt(Economy.upgradeCost(id, level - 1) or 0)))
end
