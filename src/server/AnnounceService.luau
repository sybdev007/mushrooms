--!strict
-- Ogłoszenia admina na środku ekranu, na WSZYSTKICH serwerach gry naraz (z miniaturką autora od pasa w górę).
-- Deweloper (Config.DevUserIds / Studio) pisze tekst w panelu DEV („📢 Ogłoszenie”) albo na czacie:
--   /ogloszenie Za 5 minut Krwawy księżyc!      (też /announce)
-- Serwer sprawdza uprawnienia, filtruje tekst filtrem Robloxa (wymóg dla tekstu pokazywanego innym),
-- i wysyła go przez MessagingService; każdy serwer pokazuje go swoim graczom (AnnounceShow).
-- Gdy MessagingService nie działa (np. Studio bez dostępu), ogłoszenie i tak pokazuje się na tym serwerze.

local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local TextService = game:GetService("TextService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local AnnounceService = {}

export type Api = {
	isDeveloper: (Player) -> boolean,
	notify: (Player, string, { any }?) -> (),
}

local TOPIC = "AdminAnnounce_v1"
local MAX_LENGTH = 140
local COOLDOWN = 5

local api: Api
local AnnounceShow = Remotes.get("AnnounceShow")
local lastSent: { [Player]: number } = {}
local seen: { [string]: boolean } = {} -- id ogłoszeń już pokazanych na tym serwerze (bez dubli)

local function show(id: string, text: string, from: string, userId: number)
	if seen[id] then
		return
	end
	seen[id] = true
	task.delay(120, function()
		seen[id] = nil
	end)
	AnnounceShow:FireAllClients({ text = text, from = from, userId = userId })
end

local function send(player: Player, raw: unknown)
	if typeof(raw) ~= "string" or not api.isDeveloper(player) then
		return
	end
	local text = string.gsub(raw, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	text = string.gsub(text, "[\r\n]+", " ")
	if text == "" then
		return
	end
	if utf8.len(text) and (utf8.len(text) :: number) > MAX_LENGTH then
		text = string.sub(text, 1, (utf8.offset(text, MAX_LENGTH + 1) or (#text + 1)) - 1)
	end
	local now = os.clock()
	if now - (lastSent[player] or -math.huge) < COOLDOWN then
		api.notify(player, "MSG_ANNOUNCE_WAIT", { COOLDOWN })
		return
	end
	lastSent[player] = now

	-- Filtr Robloxa: tekst dla wszystkich graczy
	local ok, filtered = pcall(function()
		local result = TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or typeof(filtered) ~= "string" then
		warn("[AnnounceService] filtr tekstu:", filtered)
		api.notify(player, "MSG_ANNOUNCE_FAILED")
		return
	end
	local id = HttpService:GenerateGUID(false)
	local payload = { id = id, t = filtered, n = player.DisplayName, u = player.UserId }
	local published = pcall(MessagingService.PublishAsync, MessagingService, TOPIC, payload)
	-- Ten serwer pokazuje od razu (wiadomość z MessagingService przyjdzie też tu, ale id się powtórzy)
	show(id, filtered, player.DisplayName, player.UserId)
	api.notify(player, if published then "MSG_ANNOUNCE_SENT" else "MSG_ANNOUNCE_LOCAL")
end

function AnnounceService.start(serviceApi: Api)
	api = serviceApi
	Remotes.get("AdminAnnounce").OnServerEvent:Connect(send)

	local folder = TextChatService:FindFirstChild("TextChatCommands") or TextChatService
	local command = Instance.new("TextChatCommand")
	command.Name = "DevAnnounce"
	command.PrimaryAlias = "/ogloszenie"
	command.SecondaryAlias = "/announce"
	command.Parent = folder
	command.Triggered:Connect(function(source: TextSource, message: string)
		local player = Players:GetPlayerByUserId(source.UserId)
		local text = string.match(message, "^%S+%s+(.+)$")
		if player and text then
			send(player, text)
		end
	end)

	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:SubscribeAsync(TOPIC, function(message)
				local data = message.Data
				if typeof(data) == "table" and typeof(data.id) == "string" and typeof(data.t) == "string" and typeof(data.n) == "string" then
					show(data.id, data.t, data.n, if typeof(data.u) == "number" then data.u else 0)
				end
			end)
		end)
		if not ok then
			warn("[AnnounceService] MessagingService niedostępny (ogłoszenia tylko na tym serwerze):", err)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastSent[player] = nil
	end)
end

return AnnounceService
