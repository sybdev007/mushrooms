--!strict
-- Gablota w ogródku (czysta logika bez Robloxa, testy w Lune). Liczby w Config.Showcase.
--   Miejsca 1..TOTAL idą seriami (las, jaskinia, bagna) po perSeries; gracz kupuje je po kolei.
--   Wystawa = kopia formy gatunku z Grzybopedii (atlas) albo trofeum ze Znaleziska Nocy (z datą).
--   Zapis: showcase = { n = posiadane miejsca, items = { ["slot"] = Exhibit } }, trophies = { Exhibit }.
--   Klucze slotów są napisami, bo DataStore nie zapisze tablicy z dziurami.

local Config = require(script.Parent.Config)
local Economy = require(script.Parent.Economy)
local Progress = require(script.Parent.Progress)

local Showcase = {}

export type Exhibit = { s: string, v: string?, t: number? } -- t: data trofeum (os.time), tylko ze Znaleziska
export type Save = { n: number, items: { [string]: Exhibit } }
export type Flags = { caveUnlocked: boolean, swampUnlocked: boolean }

local PER = Config.Showcase.perSeries
Showcase.TOTAL = PER * #Config.Showcase.series

-- Seria i miejsce w serii (1..perSeries)
function Showcase.slotOf(slot: number): (number, number)
	return (slot - 1) // PER + 1, (slot - 1) % PER + 1
end

-- Skala nagród świata serii (las 1600, jaskinia 32 000, bagna 160 000)
function Showcase.seriesScale(series: number): number
	return Progress.rewardScale(series >= 2, series >= 3, false)
end

-- Cena miejsca (0 = darmowe)
function Showcase.price(slot: number): number
	local series, k = Showcase.slotOf(slot)
	local free = if series == 1 then Config.Showcase.freeSlots else 0
	if k <= free then
		return 0
	end
	return Config.Showcase.priceUnits * Showcase.seriesScale(series) * 2 ^ (k - free - 1)
end

-- Czy gracz ma świat tej serii
function Showcase.seriesOpen(series: number, flags: Flags): boolean
	local def = Config.Showcase.series[series]
	if not def then
		return false
	end
	local unlock = def.unlock
	return unlock == nil or (flags :: any)[unlock] == true
end

-- Następne miejsce do kupienia: numer i cena albo nil i powód ("full" = wszystko kupione,
-- "world" = najpierw odblokuj świat tej serii)
function Showcase.nextSlot(save: Save, flags: Flags): (number?, number?, string?)
	local slot = save.n + 1
	if slot > Showcase.TOTAL then
		return nil, nil, "full"
	end
	local series = Showcase.slotOf(slot)
	if not Showcase.seriesOpen(series, flags) then
		return nil, nil, "world"
	end
	return slot, Showcase.price(slot), nil
end

function Showcase.emptySave(): Save
	return { n = Config.Showcase.freeSlots, items = {} }
end

local function finite(x: any): boolean
	return typeof(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

-- Jedna wystawa z zapisu albo z sieci: tylko znane gatunki i warianty
function Showcase.readExhibit(raw: any): Exhibit?
	if typeof(raw) ~= "table" or typeof(raw.s) ~= "string" or not Economy.getSpecies(raw.s) then
		return nil
	end
	local variant: string? = nil
	if raw.v ~= nil then
		if typeof(raw.v) ~= "string" or not Economy.getVariant(raw.v) then
			return nil
		end
		variant = raw.v
	end
	local t: number? = if finite(raw.t) and raw.t > 0 then math.floor(raw.t) else nil
	return { s = raw.s, v = variant, t = t }
end

function Showcase.readSave(raw: any): Save
	local save = Showcase.emptySave()
	if typeof(raw) ~= "table" then
		return save
	end
	if finite(raw.n) then
		save.n = math.clamp(math.floor(raw.n), Config.Showcase.freeSlots, Showcase.TOTAL)
	end
	if typeof(raw.items) == "table" then
		for key, value in raw.items do
			local slot = tonumber(key)
			local exhibit = Showcase.readExhibit(value)
			if slot and slot == math.floor(slot) and slot >= 1 and slot <= save.n and exhibit then
				save.items[tostring(slot)] = exhibit
			end
		end
	end
	return save
end

function Showcase.readTrophies(raw: any): { Exhibit }
	local list: { Exhibit } = {}
	if typeof(raw) ~= "table" then
		return list
	end
	for _, value in raw do
		local exhibit = Showcase.readExhibit(value)
		if exhibit and exhibit.t and #list < Config.Showcase.maxTrophies then
			table.insert(list, exhibit)
		end
	end
	return list
end

-- Nowe trofeum na początek listy (najnowsze pierwsze); nadmiar najstarszych wypada
function Showcase.addTrophy(trophies: { Exhibit }, exhibit: Exhibit)
	table.insert(trophies, 1, exhibit)
	while #trophies > Config.Showcase.maxTrophies do
		table.remove(trophies)
	end
end

local function sameExhibit(a: Exhibit, b: Exhibit): boolean
	return a.s == b.s and (a.v or "") == (b.v or "") and (a.t or 0) == (b.t or 0)
end
Showcase.same = sameExhibit

-- Czy gracz może to wystawić: forma odkryta w Grzybopedii albo jego trofeum
function Showcase.allowed(atlas: { [string]: any }, trophies: { Exhibit }, exhibit: Exhibit): boolean
	if exhibit.t then
		for _, trophy in trophies do
			if sameExhibit(trophy, exhibit) then
				return true
			end
		end
		return false
	end
	return Economy.getSpecies(exhibit.s) ~= nil and Progress.has(atlas, exhibit.s, Economy.variantRank(exhibit.v))
end

-- Wszystko, co gracz może wystawić: trofea (najnowsze), potem formy z Grzybopedii od najrzadszej
function Showcase.options(atlas: { [string]: any }, trophies: { Exhibit }): { Exhibit }
	local list: { Exhibit } = {}
	for _, trophy in trophies do
		table.insert(list, { s = trophy.s, v = trophy.v, t = trophy.t })
	end
	local forms: { Exhibit } = {}
	for _, species in Config.Species do
		local mask = Progress.mask(atlas, species.id)
		if mask > 0 then
			for rank = 4, 0, -1 do
				if Progress.has(atlas, species.id, rank) then
					table.insert(forms, { s = species.id, v = Economy.variantOfRank(rank) })
				end
			end
		end
	end
	table.sort(forms, function(a, b)
		local ra, rb = Economy.variantRank(a.v), Economy.variantRank(b.v)
		if ra ~= rb then
			return ra > rb
		end
		local sa, sb = Economy.getSpecies(a.s), Economy.getSpecies(b.s)
		local va, vb = if sa then sa.value else 0, if sb then sb.value else 0
		if va ~= vb then
			return va > vb
		end
		return a.s < b.s
	end)
	for _, form in forms do
		table.insert(list, form)
	end
	return list
end

-- Pierwsze wolne posiadane miejsce albo nil
function Showcase.firstEmpty(save: Save): number?
	for slot = 1, save.n do
		if not save.items[tostring(slot)] then
			return slot
		end
	end
	return nil
end

-- Wydatki na całą serię (testy, symulacje)
function Showcase.seriesCost(series: number): number
	local total = 0
	for k = 1, PER do
		total += Showcase.price((series - 1) * PER + k)
	end
	return total
end

return Showcase
