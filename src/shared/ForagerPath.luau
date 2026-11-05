--!strict
-- Ścieżka grzybiarza: cele po samouczku, aż do otwarcia Jaskini. Pokazuje je karta misji samouczka
-- (client/Tutorial), a serwer loguje osiągnięcie każdego celu do analityki (GameService.pushState).
-- Czysta logika bez Robloxa (testy w Lune). Postęp liczymy z istniejącego zapisu: bez nowych pól
-- i bez nagród, bo nagrodą jest to, do czego cel prowadzi (szybsze buty, korona, Jaskinia).
-- Bieżący cel = pierwszy niespełniony; cele spełnione wcześniej (np. przez starszych graczy) pomijamy.

local Config = require(script.Parent.Config)
local Progress = require(script.Parent.Progress)

local ForagerPath = {}

export type Context = {
	tutorialDone: boolean,
	caveUnlocked: boolean,
	coins: number,
	boots: number, -- poziom ulepszenia butów
	atlas: { [string]: any }?, -- Grzybopedia (Progress.mask)
	bestiary: { [string]: any }?, -- strażnicy (Progress.guardianRecord)
}

export type Goal = {
	id: string,
	key: string, -- tekst karty (CSV), z {1} = ile jest i {2} = ile trzeba
	icon: string, -- UiKit
	target: string?, -- dokąd prowadzi strzałka: "grove" (Gniazdo Leszego), "cave" (portal do Jaskini)
}

export type Status = { goal: Goal, index: number, have: number, need: number }

ForagerPath.SPECIES = 8 -- gatunków w Grzybopedii
-- Buty, na których da się uciec Leszemu z Gniazda (próg z Grzybopedii, Progress.bootsToEscape)
ForagerPath.BOOTS = Progress.bootsToEscape(Progress.getGuardian("leszy") :: any) or 1

ForagerPath.GOALS = {
	{ id = "boots", key = "PATH_BOOTS", icon = "boots" },
	{ id = "species", key = "PATH_SPECIES", icon = "book" },
	{ id = "mutation", key = "PATH_MUTATION", icon = "sparkles" },
	{ id = "crown", key = "PATH_CROWN", icon = "trophy", target = "grove" },
	{ id = "escape", key = "PATH_ESCAPE", icon = "lantern" },
	{ id = "cave", key = "PATH_CAVE", icon = "coins", target = "cave" },
} :: { Goal }

local function speciesCount(atlas: { [string]: any }): number
	local count = 0
	for id in atlas do
		if Progress.mask(atlas, id) > 0 then
			count += 1
		end
	end
	return count
end

-- Czy w Grzybopedii jest jakakolwiek forma z mutacją (ranga 1+, czyli bit wyższy niż zwykły grzyb)
local function hasMutation(atlas: { [string]: any }): boolean
	for id in atlas do
		if Progress.mask(atlas, id) >= 2 then
			return true
		end
	end
	return false
end

-- Ile jest i ile trzeba dla celu
function ForagerPath.progress(ctx: Context, id: string): (number, number)
	local atlas = ctx.atlas or {}
	if id == "boots" then
		return math.min(ctx.boots, ForagerPath.BOOTS), ForagerPath.BOOTS
	elseif id == "species" then
		return math.min(speciesCount(atlas), ForagerPath.SPECIES), ForagerPath.SPECIES
	elseif id == "mutation" then
		return if hasMutation(atlas) then 1 else 0, 1
	elseif id == "crown" or id == "escape" then
		local record = Progress.guardianRecord(ctx.bestiary or {}, "leszy")
		local value = if id == "crown" then record.stolen else record.escaped
		return math.min(value, 1), 1
	elseif id == "cave" then
		local need = Config.Cave.unlockCoins
		return if ctx.caveUnlocked then need else math.clamp(math.floor(ctx.coins), 0, need), need
	end
	return 0, 1
end

-- Bieżący cel albo nil (samouczek trwa, Jaskinia już otwarta albo wszystko zrobione)
function ForagerPath.current(ctx: Context): Status?
	if not ctx.tutorialDone or ctx.caveUnlocked then
		return nil
	end
	for index, goal in ForagerPath.GOALS do
		local have, need = ForagerPath.progress(ctx, goal.id)
		-- Jaskinię kończy dopiero otwarcie portalu (z pełną kwotą karta prowadzi do portalu)
		if have < need or goal.id == "cave" then
			return { goal = goal, index = index, have = have, need = need }
		end
	end
	return nil
end

-- Numer bieżącego celu (1..#GOALS), a po całej ścieżce #GOALS + 1. Do analityki: wzrost = cele zaliczone.
-- Przed końcem samouczka 0.
function ForagerPath.stage(ctx: Context): number
	if not ctx.tutorialDone then
		return 0
	end
	local status = ForagerPath.current(ctx)
	return if status then status.index else #ForagerPath.GOALS + 1
end

return ForagerPath
