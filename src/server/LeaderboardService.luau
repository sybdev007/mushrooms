--!strict
-- Rankingi na tablicach przed chatką (OrderedDataStore, wspólne dla wszystkich serwerów):
--   richest — najbogatsi (monety teraz),
--   rare    — najcenniejsze znalezisko tygodnia (Progress.encodeFind: wartość + gatunek + wariant),
--   thieves — najwięcej doniesionych łupów z cudzych ogródków w tym tygodniu,
--   candy   — Halloween: najwięcej zebranych cukierków (stats.candy), tylko w czasie eventu i do
--             finalizacji (Config.Halloween.finalizeAt). Wysyłamy tylko wynik z POTWIERDZONEGO zapisu
--             profilu (DataService.confirmedCandy / onSaved), przez UpdateAsync z maksimum (stara sesja
--             nie obniży wyniku). Bez Studio, bez deweloperów (po UserId, też offline), bez kont
--             z Config.Halloween.rankingBanned. Moderacja zostawia w magazynie znacznik 0 („usunięty”):
--             każdy późniejszy albo opóźniony UpdateAsync go widzi i nie odtwarza wyniku, na żadnym
--             serwerze. Po końcu eventu cukierki już nie rosną (ProgressService.addCandy).
-- Tygodniowe tablice mają nowy magazyn co poniedziałek, więc same się zerują.
-- Studio i konta deweloperów (Config.DevUserIds) nie wysyłają wyników na żadną tablicę.
-- Wyniki trafiają do atrybutu "Entries" (JSON) na ekranie tablicy; rysuje je klient (LeaderboardView),
-- żeby tytuły i nazwy grzybów były w języku gracza.
-- Bez dostępu do DataStore (Studio bez API) tablice pokazują graczy z tego serwera; ranking cukierków
-- pokazuje wtedy ostatnią pobraną czołówkę świata (albo nic), bo nie zna moderacji z innych serwerów.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Progress = require(ReplicatedStorage:WaitForChild("Shared").Progress)
local Halloween = require(ReplicatedStorage:WaitForChild("Shared").Halloween)
local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local RunService = game:GetService("RunService")
local DataService = require(script.Parent.DataService)
local ScoreQueue = require(script.Parent.ScoreQueue)
local Boards = require(script.Parent:WaitForChild("World"):WaitForChild("Boards"))

type Data = DataService.Data

export type Api = {
	getData: (Player) -> Data?,
	canSave: (Player) -> boolean,
	isDeveloper: (Player) -> boolean,
}

local LeaderboardService = {}

local UPLOAD_SECONDS = 60 -- co tyle wysyłamy wyniki graczy (limity zapisów DataStore)
local REFRESH_SECONDS = 60 -- co tyle czytamy czołówkę
local TOP = 10
-- v2: czyste tablice na premierę (v1 miało wyniki z testów w Studio i kont deweloperów)
local STORE_PREFIX = "LanternForager_Top_v2_"

local KINDS = { "richest", "rare", "thieves", "candy" }
local WEEKLY: { [string]: boolean } = { rare = true, thieves = true }
local CANDY_STORE = "Halloween2026_Candy"
-- Tablice, które zapisujemy największym wynikiem (UpdateAsync) zamiast nadpisywać
local MONOTONIC: { [string]: boolean } = { candy = true }

local api: Api
local screens: { [string]: BasePart } = {}
local uploaded: { [Player]: { [string]: number } } = {}
local names: { [number]: string } = {}
local storeOk = true

-- Wynik gracza na danej tablicy (0 = nie wpisujemy)
local function scoreOf(data: Data, kind: string, week: number): number
	if kind == "richest" then
		return math.floor(data.coins)
	elseif kind == "candy" then
		return if Halloween.rankingOpen(os.time()) then math.floor(data.stats.candy) else 0
	end
	if data.weekly.week ~= week then
		return 0
	end
	return if kind == "rare" then data.weekly.best else data.weekly.steals
end

local function storeFor(kind: string, week: number): OrderedDataStore?
	local name = if kind == "candy" then CANDY_STORE else STORE_PREFIX .. kind .. (if WEEKLY[kind] then "_w" .. week else "")
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

local removed: { [number]: boolean } = {} -- konta usunięte z rankingu cukierków (pamięć tego serwera)
local REMOVED = 0 -- znacznik usunięcia w magazynie rankingu cukierków (prawdziwe wyniki są > 0)

-- Konto deweloperskie po samym UserId (działa też dla graczy offline przy czytaniu tablicy)
local function staffId(userId: number): boolean
	if game.CreatorType == Enum.CreatorType.User and userId == game.CreatorId then
		return true
	end
	return table.find(Config.DevUserIds, userId) ~= nil
end

local function candyAllowedId(userId: number): boolean
	return not removed[userId] and Halloween.rankingAllowed(userId, staffId(userId))
end

-- Czy wynik tego gracza na tej tablicy wolno wysłać (ranking cukierków ma dodatkowe warunki).
-- Ze Studio i z kont deweloperów nic nie trafia do magazynu (monety z /coins, testy).
-- W Studio bez zapisu tablica i tak pokazuje graczy z serwera (topFor), żeby było co testować.
local function allowed(player: Player, kind: string, canSave: boolean): boolean
	if kind ~= "candy" then
		return RunService:IsStudio() or not staffId(player.UserId)
	end
	return canSave and not RunService:IsStudio() and candyAllowedId(player.UserId) and Halloween.rankingAllowed(player.UserId, api.isDeveloper(player))
end

-- Zapis wyniku cukierków: maksimum, chyba że wpis ma znacznik usunięcia albo konto jest wykluczone.
-- Funkcja w UpdateAsync może być wołana kilka razy (konflikt zapisów): za każdym razem widzi świeży stan.
local function writeCandy(store: OrderedDataStore, userId: number, score: number)
	store:UpdateAsync(tostring(userId), function(old)
		if typeof(old) == "number" and old <= REMOVED then
			return nil :: any -- usunięty przez moderację: nie odtwarzamy
		end
		if not candyAllowedId(userId) then
			return nil :: any
		end
		return math.max(if typeof(old) == "number" then old else 0, score)
	end)
end

-- Cukierki czekające na wysłanie (UserId → potwierdzony wynik), jeden worker (ScoreQueue). Nie zależą
-- od obiektu Player, więc nieudany zapis po wyjściu gracza ponawiamy co minutę aż do skutku, znacznika
-- usunięcia albo finalizacji.
local candyQueue = ScoreQueue.new(function(userId: number, score: number): ScoreQueue.Result
	local store = storeFor("candy", 0)
	if not storeOk or not store then
		return "stop"
	end
	local ok, err = pcall(function()
		writeCandy(store, userId, score)
	end)
	if ok then
		return "ok"
	end
	warn("[Leaderboard] Zapis cukierków nieudany (ponowimy):", err)
	if string.find(tostring(err), "403", 1, true) or string.find(tostring(err), "Studio", 1, true) then
		storeOk = false
		return "stop"
	end
	return "retry"
end, candyAllowedId)

local function queueCandy(userId: number, score: number)
	candyQueue.push(userId, score)
end

local function flushCandy()
	if not Halloween.rankingOpen(os.time()) or RunService:IsStudio() then
		candyQueue.clear()
		return
	end
	if storeOk then
		candyQueue.flush()
	end
end

local function upload(player: Player, force: boolean?, known: Data?, knownCanSave: boolean?)
	local data = known or api.getData(player)
	if not data or not storeOk then
		return
	end
	local canSave = if knownCanSave ~= nil then knownCanSave else api.canSave(player)
	local week = Progress.weekIndex(os.time())
	local sent = uploaded[player] or {}
	uploaded[player] = sent
	-- Cukierki: tylko to, co już na pewno zapisało się w profilu, przez kolejkę z ponawianiem
	if Halloween.rankingOpen(os.time()) and allowed(player, "candy", canSave) then
		queueCandy(player.UserId, DataService.confirmedCandy(player))
	end
	for _, kind in KINDS do
		local score = if kind == "candy" then 0 else scoreOf(data, kind, week)
		if score > 0 and (force or sent[kind] ~= score) and allowed(player, kind, canSave) and not RunService:IsStudio() then
			local store = storeFor(kind, week)
			if store then
				local ok, err = pcall(function()
					if MONOTONIC[kind] then
						writeCandy(store, player.UserId, score)
					else
						store:SetAsync(tostring(player.UserId), score)
					end
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
local lastCandy: { Entry }? = nil -- ostatnia udanie pobrana czołówka cukierków
local lastCandyAt = 0 -- kiedy (os.time) ją pobraliśmy

-- Bez kont wykluczonych lub usuniętych (także po pobraniu: moderacja w trakcie odczytu)
local function filterCandy(list: { Entry }): { Entry }
	local out = {}
	for _, entry in list do
		if candyAllowedId(entry.me) then
			table.insert(out, entry)
		end
	end
	return out
end

-- Czołówka z DataStore albo (bez dostępu) z graczy na tym serwerze
local function topFor(kind: string, week: number): ({ Entry }, string, number?)
	if storeOk then
		local store = storeFor(kind, week)
		if store then
			local ok, result = pcall(function()
				local list = {}
				if kind ~= "candy" then
					for _, row in store:GetSortedAsync(false, TOP):GetCurrentPage() do
						local userId = tonumber(row.key) or 0
						if not staffId(userId) then -- deweloperzy poza tablicami (też stare wpisy)
							table.insert(list, { n = nameOf(userId), v = row.value, me = userId })
						end
					end
					return list
				end
				-- Cukierki: bez znaczników usunięcia (minValue 1) i bez wykluczonych kont; jeśli
				-- czołówkę zajmują wykluczeni, czytamy kolejne strony (najwyżej kilka)
				local pages = store:GetSortedAsync(false, TOP, REMOVED + 1)
				for _ = 1, 5 do
					for _, row in pages:GetCurrentPage() do
						local userId = tonumber(row.key) or 0
						if #list < TOP and candyAllowedId(userId) then
							table.insert(list, { n = nameOf(userId), v = row.value, me = userId })
						end
					end
					if #list >= TOP or pages.IsFinished then
						break
					end
					pages:AdvanceToNextPageAsync()
				end
				return list
			end)
			if ok then
				if kind == "candy" then
					lastCandy = filterCandy(result :: any)
					lastCandyAt = os.time()
					return lastCandy :: any, "global", lastCandyAt
				end
				return result :: any, "global"
			end
			warn("[Leaderboard] Odczyt nieudany:", result)
			if string.find(tostring(result), "403", 1, true) or string.find(tostring(result), "Studio", 1, true) then
				storeOk = false
			end
		end
	end
	-- Cukierki bez dostępu do magazynu: ostatnia pobrana czołówka świata (nie budujemy listy z profili,
	-- bo nie znamy znaczników moderacji z innych serwerów)
	if kind == "candy" then
		if lastCandy then
			return filterCandy(lastCandy), "stale", lastCandyAt
		end
		return {}, "server"
	end
	local list = {}
	for _, player in Players:GetPlayers() do
		local data = api.getData(player)
		local score = if data then scoreOf(data, kind, week) else 0
		if score > 0 and allowed(player, kind, api.canSave(player)) then
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
		local list, source, updatedAt = topFor(kind, week)
		screen:SetAttribute("Entries", HttpService:JSONEncode(list))
		screen:SetAttribute("Source", source) -- "global", "server" albo "stale" (stara czołówka świata)
		screen:SetAttribute("Week", week)
		screen:SetAttribute("UpdatedAt", updatedAt or os.time())
	end
end

-- Gracz wychodzi: ostatni wynik (dane podajemy wprost, bo sesji już nie ma). Cukierki dojdą osobno,
-- dopiero po ostatnim zapisie profilu (onProfileSaved niżej).
function LeaderboardService.leave(player: Player, data: Data, canSave: boolean)
	upload(player, false, data, canSave)
	uploaded[player] = nil
end

-- Profil gracza się zapisał: do kolejki trafia wynik z tego zapisu (też po wyjściu z gry)
local function onProfileSaved(player: Player, saved: any)
	if not Halloween.rankingOpen(os.time()) or not allowed(player, "candy", true) then
		return
	end
	queueCandy(player.UserId, DataService.candyOf(saved))
	flushCandy()
end

-- Usuwa wynik z tablicy (moderacja): w magazynie zostaje znacznik 0, którego żaden zapis (też opóźniony
-- albo z innego serwera) nie nadpisze. Trwałe wykluczenie na przyszłość: Config.Halloween.rankingBanned.
-- W Studio nie działa (ten sam magazyn co gra na żywo). Zwraca, czy się udało.
function LeaderboardService.remove(kind: string, userId: number): boolean
	if kind ~= "candy" or RunService:IsStudio() then
		warn("[Leaderboard] Usuwanie wyników działa tylko w grze na żywo i tylko dla rankingu cukierków")
		return false
	end
	removed[userId] = true
	candyQueue.remove(userId)
	if lastCandy then
		lastCandy = filterCandy(lastCandy)
	end
	local store = storeFor(kind, 0)
	local ok = false
	if store then
		local success, err = pcall(function()
			store:SetAsync(tostring(userId), REMOVED)
		end)
		ok = success
		if not success then
			warn("[Leaderboard] Usunięcie nieudane:", err)
		end
	end
	refresh()
	return ok
end

function LeaderboardService.start(serviceApi: Api)
	api = serviceApi
	DataService.onSaved(onProfileSaved)
	-- Zamykanie serwera: ostatnia próba wysłania zaległych wyników (zapisy profili przy wyjściu
	-- wywołają onProfileSaved jeszcze przed końcem)
	game:BindToClose(function()
		-- Limit czasu liczony od początku (Roblox daje BindToClose najwyżej 30 s); wysyłanie leci w tle
		local deadline = os.clock() + 25
		task.wait(3)
		task.spawn(flushCandy)
		task.wait()
		while candyQueue.busy() and os.clock() < deadline do
			task.wait(0.5)
		end
	end)
	-- Tablica cukierków stoi od startu eventu do finalizacji
	screens = Boards.build(Workspace, { candy = Halloween.rankingOpen(os.time()) })
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
			flushCandy() -- też zaległe wyniki graczy, którzy już wyszli
			refresh()
		end
	end)
end

-- Do panelu DEV: od razu wyślij i odśwież (bez czekania minuty)
function LeaderboardService.refreshNow()
	for _, player in Players:GetPlayers() do
		upload(player, true)
	end
	flushCandy()
	refresh()
end

return LeaderboardService
