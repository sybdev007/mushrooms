--!strict
-- Przycisk „Dołącz do grupy” w kolumnie SideButtons (grupa Old Owl Studios, Config.Community).
-- Otwiera robloxowe okno dołączenia do grupy, a po jego zamknięciu prosi serwer o ponowne sprawdzenie
-- (OwlCheck). Serwer ustawia atrybut "OwlMember": członek nie widzi przycisku.
-- Plakietka „+10%” przypomina, że członkowie mają więcej mutacji.

local GroupService = game:GetService("GroupService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Hud = require(script.Parent.Hud)
local Localize = require(script.Parent.Localize)
local SideButtons = require(script.Parent.SideButtons)

local CommunityButton = {}

local player = Players.LocalPlayer
local OwlCheck = Remotes.get("OwlCheck")

local side = SideButtons.add({
	name = "OwlButton",
	icon = "owl",
	color = Color3.fromRGB(122, 92, 200),
	caption = "OWL_JOIN_BUTTON",
})

local function percent(): string
	return string.format("+%d%%", math.floor((Config.Community.luck - 1) * 100 + 0.5))
end

local function render()
	-- Do odpowiedzi serwera (nil) przycisku nie pokazujemy, żeby członkom nie mignął
	side.root.Visible = player:GetAttribute("OwlMember") == false
	side.setBadge(percent() .. " 🍀", "done")
end

local busy = false
local function join()
	if busy then
		return
	end
	busy = true
	local ok, err = pcall(function()
		(GroupService :: any):PromptJoinAsync(Config.Community.groupId)
	end)
	if not ok then
		-- Okno się nie otworzyło (np. starszy klient): mówimy, gdzie szukać grupy
		warn("[CommunityButton]", err)
		Hud.toast(Localize.t("OWL_JOIN_FALLBACK"), "gold")
	end
	-- Serwer i tak sprawdzi sam: gracz mógł dołączyć albo zamknąć okno
	OwlCheck:FireServer()
	task.delay(Config.Community.recheckSeconds, function()
		busy = false
	end)
end

function CommunityButton.start()
	side.onActivated(join)
	player:GetAttributeChangedSignal("OwlMember"):Connect(render)
	render()
end

return CommunityButton
