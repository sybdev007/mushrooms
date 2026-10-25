--!strict
-- Rankingi na tablicach przed chatką (OrderedDataStore, wspólne dla wszystkich serwerów):
--   richest — najbogatsi (monety teraz),
--   rare    — najcenniejsze znalezisko tygodnia (Progress.encodeFind: wartość + gatunek + wariant),
--   thieves — najwięcej doniesionych łupów z cudzych ogródków w tym tygodniu.
-- Tygodniowe tablice mają nowy magazyn co poniedziałek, więc same się zerują.
-- Wyniki trafiają do atrybutu "Entries" (JSON) na ekranie tablicy; rysuje je klient (LeaderboardView),
-- żeby tytuły i nazwy grzybów były w języku gracza.
-- Bez dostępu do DataStore (Studio bez API) tablice pokazują graczy z tego serwera.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Progress = require(ReplicatedStorage:WaitForChild("Shared").Progress)
local DataService = require(script.Parent.DataService)
local Boards = require(script.Parent:WaitForChild("World"):WaitForChild("Boards"))

type Data = DataService.Data

export type Api = {
	getData: (Player) -> Data?,
}

local LeaderboardService = {}

local UPLOAD_SECONDS = 60 -- co tyle wysyłamy wyniki graczy (limity zapisów DataStore)
local REFRESH_SECONDS = 60 -- co tyle czytamy czołówkę
local TOP = 10
local STORE_PREFIX = "LanternForager_Top_v1_"

local KINDS = { "richest", "rare", "thieves" }
local WEEKLY: { [string]: boolean } = { rare = true, thieves = true }

local api: Api
local screens: { [string]: BasePart } = {}
local uploaded: { [Player]: { [string]: number } } = {}
local names: { [number]: string } = {}
local storeOk = true

-- Wynik gracza na danej tablicy (0 = nie wpisujemy)
local function scoreOf(data: Data, kind: string, week: number): number
	if kind == "richest" then
		return math.floor(data.coins)
	end
	if data.weekly.week ~= week then
		return 0
	end
	return if kind == "rare" then data.weekly.best else data.weekly.steals
end

local function storeFor(kind: string, week: number): OrderedDataStore?
	local name = STORE_PREFIX .. kind .. (if WEEKLY[kind] then "_w" .. week else "")
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(name)
	end)
	return if ok then result else nil
end

local function nameOf(userId: number): string
	local player = Players:GetPlayerByUserId(userId)
	if player then
		names[userId] = player.DisplayName
		return player.DisplayName
	end
	local cached = names[userId]
	if cached then
		return cached
	end
	local ok, result = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local name = if ok and typeof(result) == "string" then result else "#" .. userId
	names[userId] = name
	return name
end

local function upload(player: Player, force: boolean?, known: Data?)
	local data = known or api.getData(player)
	if not data or not storeOk then
		return
	end
	local week = Progress.weekIndex(os.time())
	local sent = uploaded[player] or {}
	uploaded[player] = sent
	for _, kind in KINDS do
		local score = scoreOf(data, kind, week)
		if score > 0 and (force or sent[kind] ~= score) then
			local store = storeFor(kind, week)
			if store then
				local ok, err = pcall(function()
					store:SetAsync(tostring(player.UserId), score)
				end)
				if ok then
					sent[kind] = score
				else
					warn("[Leaderboard] Zapis nieudany:", err)
					if string.find(tostring(err), "403", 1, true) or string.find(tostring(err), "Studio", 1, true) then
						storeOk = false
					end
					return
				end
			end
		end
	end
end

type Entry = { n: string, v: number, me: number }

-- Czołówka z DataStore albo (bez dostępu) z graczy na tym serwerze
local function topFor(kind: string, week: number): ({ Entry }, string)
	if storeOk then
		local store = storeFor(kind, week)
		if store then
			local ok, result = pcall(function()
				return store:GetSortedAsync(false, TOP):GetCurrentPage()
			end)
			if ok then
				local list = {}
				for _, row in result do
					local userId = tonumber(row.key) or 0
					table.insert(list, { n = nameOf(userId), v = row.value, me = userId })
				end
				return list, "global"
			end
			warn("[Leaderboard] Odczyt nieudany:", result)
			if string.find(tostring(result), "403", 1, true) or string.find(tostring(result), "Studio", 1, true) then
				storeOk = false
			end
		end
	end
	local list = {}
	for _, player in Players:GetPlayers() do
		local data = api.getData(player)
		local score = if data then scoreOf(data, kind, week) else 0
		if score > 0 then
			table.insert(list, { n = player.DisplayName, v = score, me = player.UserId })
		end
	end
	table.sort(list, function(a, b)
		return a.v > b.v
	end)
	while #list > TOP do
		table.remove(list)
	end
	return list, "server"
end

local function refresh()
	local week = Progress.weekIndex(os.time())
	for kind, screen in screens do
		local list, source = topFor(kind, week)
		screen:SetAttribute("Entries", HttpService:JSONEncode(list))
		screen:SetAttribute("Source", source)
		screen:SetAttribute("Week", week)
		screen:SetAttribute("UpdatedAt", os.time())
	end
end

-- Gracz wychodzi: ostatni wynik (dane podajemy wprost, bo sesji już nie ma)
function LeaderboardService.leave(player: Player, data: Data)
	upload(player, false, data)
	uploaded[player] = nil
end

function LeaderboardService.start(serviceApi: Api)
	api = serviceApi
	screens = Boards.build(Workspace)
	task.spawn(function()
		-- Pierwsze odczytanie od razu (tablice nie stoją puste do pierwszej minuty)
		refresh()
		local sinceUpload = 0
		while true do
			task.wait(REFRESH_SECONDS)
			sinceUpload += REFRESH_SECONDS
			if sinceUpload >= UPLOAD_SECONDS then
				sinceUpload = 0
				for _, player in Players:GetPlayers() do
					upload(player)
				end
			end
			refresh()
		end
	end)
end

-- Do panelu DEV: od razu wyślij i odśwież (bez czekania minuty)
function LeaderboardService.refreshNow()
	for _, player in Players:GetPlayers() do
		upload(player, true)
	end
	refresh()
end

return LeaderboardService
