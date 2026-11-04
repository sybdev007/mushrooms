--!strict
-- Skórki narzędzi w dłoni ze wszystkich eventów (Config.Halloween.skins, Config.Winter.skins).
-- Zapis: data.skins (wylosowane w kotle albo na choince) i data.equipped (slot -> id, "" = zwykła rzecz).
-- Skórki ze ścieżek nagród liczą się z liczników: stats.candy (Halloween), stats.snowflakes (Zima).
-- Wygląd w dłoni rysuje World/HandTools (po id skórki).

local Halloween = require(script.Parent.Halloween)
local Winter = require(script.Parent.Winter)

export type SkinDef = { slot: string, key: string, icon: string, event: string }
export type Counters = { candy: number?, snowflakes: number? }

local Skins = {}

Skins.SLOTS = { "lantern", "knife" }
Skins.ALL = {} :: { [string]: SkinDef }
-- Kolejność w oknach: najpierw Halloween, potem Zima, w obrębie eventu według id
Skins.ORDER = {} :: { string }

local function register(event: string, list: { [string]: { slot: string, key: string, icon: string } })
	local ids = {}
	for id, def in list do
		Skins.ALL[id] = { slot = def.slot, key = def.key, icon = def.icon, event = event }
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		table.insert(Skins.ORDER, id)
	end
end
register("halloween", Halloween.SKINS)
register("winter", Winter.SKINS)

function Skins.get(id: any): SkinDef?
	return if typeof(id) == "string" then Skins.ALL[id] else nil
end

-- Czy gracz ma skórkę (z losowania albo z progu ścieżki swojego eventu)
function Skins.owns(skins: { string }, stats: Counters, id: string): boolean
	local def = Skins.ALL[id]
	if not def then
		return false
	elseif def.event == "winter" then
		return Winter.ownsSkin(skins, stats.snowflakes or 0, id)
	end
	return Halloween.ownsSkin(skins, stats.candy or 0, id)
end

-- Wszystkie skórki gracza, w kolejności Skins.ORDER
function Skins.owned(skins: { string }, stats: Counters): { string }
	local list = {}
	for _, id in Skins.ORDER do
		if Skins.owns(skins, stats, id) then
			table.insert(list, id)
		end
	end
	return list
end

return Skins
