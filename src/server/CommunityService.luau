--!strict
-- Grupa Old Owl Studios (Config.Community): kto jest członkiem i nagrody za dołączenie.
--   Członkostwo sprawdzamy na serwerze przy wejściu i na prośbę klienta po oknie „Dołącz do grupy”
--   (zdalne OwlCheck, najczęściej co recheckSeconds). Wynik trafia do atrybutu gracza "OwlMember"
--   (klient chowa przycisk i liczy tabelkę szans), a GameService bierze go do szczęścia.
--   Paczka powitalna raz na konto: licznik stats.owl (0 -> 1) daje też tytuł „Old Owl Member”.
--   Kto wyjdzie z grupy, traci +10% szczęścia; tytuł i paczka zostają.

local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Progress = require(ReplicatedStorage.Shared.Progress)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local ProgressService = require(script.Parent.ProgressService)

type Data = DataService.Data

export type Api = {
	getData: (Player) -> Data?,
	notify: (Player, string, { any }?) -> (),
	pushState: (Player) -> (),
	canSave: (Player) -> boolean,
}

local CommunityService = {}

local OwlCheck = Remotes.get("OwlCheck")

local api: Api
local members: { [Player]: boolean } = {}
local lastCheck: { [Player]: number } = {}

function CommunityService.isMember(player: Player): boolean
	return members[player] == true
end

-- true / false, albo nil, gdy Roblox nie odpowiedział (wtedy zostaje poprzedni stan)
local function fetch(player: Player): boolean?
	local groupId = Config.Community.groupId
	-- GetGroupsAsync pyta na bieżąco; IsInGroupAsync (zapas) może pamiętać wynik z wejścia na serwer
	local ok, groups = pcall(function()
		return GroupService:GetGroupsAsync(player.UserId)
	end)
	if ok and typeof(groups) == "table" then
		for _, group in groups :: { any } do
			if typeof(group) == "table" and group.Id == groupId then
				return true
			end
		end
		return false
	end
	local fallbackOk, inGroup = pcall(function()
		return player:IsInGroupAsync(groupId)
	end)
	return if fallbackOk then inGroup == true else nil
end

-- Paczka powitalna (raz na konto). Tylko gdy dane się zapisują, żeby nie dało się jej brać w kółko.
local function welcome(player: Player): boolean
	local data = api.getData(player)
	if not data or (data.stats.owl or 0) >= 1 or not api.canSave(player) then
		return false
	end
	local coins = math.floor(Config.Community.giftCoins * Progress.rewardScale(data.caveUnlocked, data.swampUnlocked))
	data.coins += coins
	data.luckUntil = math.max(os.time(), data.luckUntil) + Config.Community.giftLuckSeconds
	api.notify(player, "MSG_OWL_WELCOME", { coins, math.floor(Config.Community.giftLuckSeconds / 60) })
	ProgressService.event(player, "owl", 1) -- tytuł „Old Owl Member” i komunikat „Nowy tytuł”
	api.pushState(player)
	return true
end

local function check(player: Player, asked: boolean)
	local member = fetch(player)
	if member == nil or not player.Parent then
		return
	end
	local was = members[player] == true
	members[player] = member
	player:SetAttribute("OwlMember", member)
	if member then
		local gifted = welcome(player)
		if asked and not gifted and not was then
			api.notify(player, "MSG_OWL_THANKS")
		end
		if not was then
			api.pushState(player) -- szczęście w tabelce szans
		end
	elseif asked then
		api.notify(player, "MSG_OWL_NOT_YET")
	end
end

-- GameService woła po ProgressService.join (dane gracza już są)
function CommunityService.join(player: Player)
	lastCheck[player] = os.clock()
	task.spawn(check, player, false)
end

function CommunityService.leave(player: Player)
	members[player] = nil
	lastCheck[player] = nil
end

function CommunityService.start(serviceApi: Api)
	api = serviceApi
	OwlCheck.OnServerEvent:Connect(function(player: Player)
		local now = os.clock()
		if now - (lastCheck[player] or -math.huge) < Config.Community.recheckSeconds then
			return
		end
		lastCheck[player] = now
		check(player, true)
	end)
	Players.PlayerRemoving:Connect(CommunityService.leave)
end

return CommunityService
