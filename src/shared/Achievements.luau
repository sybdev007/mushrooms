--!strict
-- Osiągnięcia za odznaki Robloxa (czysta logika, testy w Lune). Numery odznak są w Config.Badges
-- (0 = odznaka jeszcze nie założona w Creator Hub, wtedy nic nie przyznajemy).

local Config = require(script.Parent.Config)
local Progress = require(script.Parent.Progress)

local Achievements = {}

export type Source = {
	atlas: { [string]: any },
	bestiary: { [string]: any },
	stats: { [string]: number },
	caveUnlocked: boolean,
	swampUnlocked: boolean,
}

-- Kolejność = kolejność w Creator Hub (i w docs/Odznaki.md)
Achievements.IDS = {
	"first_mushroom",
	"cave",
	"swamp",
	"gold",
	"rainbow",
	"leszy",
	"skarbnik",
	"utopiec",
	"atlas_page",
	"grandmaster",
	"lifesaver",
	"streak7",
}

local function anyForm(atlas: { [string]: any }, rank: number): boolean
	for _, species in Config.Species do
		if Progress.has(atlas, species.id, rank) then
			return true
		end
	end
	return false
end

local function anyPage(atlas: { [string]: any }, rank: number): boolean
	for _, page in Progress.PAGES do
		if Progress.tierDone(atlas, page, rank) then
			return true
		end
	end
	return false
end

local function allPages(atlas: { [string]: any }, rank: number): boolean
	for _, page in Progress.PAGES do
		if not Progress.tierDone(atlas, page, rank) then
			return false
		end
	end
	return true
end

-- Wszystkie osiągnięcia, które gracz ma (id -> true)
function Achievements.check(source: Source): { [string]: boolean }
	local done: { [string]: boolean } = {}
	local stats = source.stats
	done.first_mushroom = (stats.picked or 0) >= 1 or next(source.atlas) ~= nil
	done.cave = source.caveUnlocked
	done.swamp = source.swampUnlocked
	done.gold = anyForm(source.atlas, 2)
	done.rainbow = anyForm(source.atlas, 3)
	for _, def in Progress.GUARDIANS do
		done[def.id] = Progress.guardianRecord(source.bestiary :: any, def.id).found
	end
	done.atlas_page = anyPage(source.atlas, 0)
	done.grandmaster = allPages(source.atlas, 3)
	done.lifesaver = (stats.revives or 0) >= 1
	done.streak7 = (stats.bestStreak or 0) >= 7
	for id, value in done do
		if not value then
			done[id] = nil
		end
	end
	return done
end

-- Odznaki do przyznania: zdobyte, z numerem w Config.Badges i jeszcze nie przyznane
function Achievements.pending(done: { [string]: boolean }, awarded: { string }): { string }
	local result = {}
	local badges = (Config :: any).Badges or {}
	for _, id in Achievements.IDS do
		local badgeId = badges[id]
		if done[id] and typeof(badgeId) == "number" and badgeId > 0 and not table.find(awarded, id) then
			table.insert(result, id)
		end
	end
	return result
end

return Achievements
