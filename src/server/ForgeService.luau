--!strict
-- Kuźnia Grzybów: Moździerz Zielarki na Placu Portali (World/Forge). Gracz wrzuca dowolne 3 grzyby
-- z koszyka i płaci opłatę, a serwer w jednym kroku (bez czekania) losuje wynik runy, zabiera opłatę
-- i 3 grzyby i wkłada wynik do koszyka. Zasady i liczby: Shared/Forge, Config.Forge, docs/plans/kuznia.md.
-- Klient (ForgePanel) tylko pokazuje podgląd; wszystko sprawdzamy tu jeszcze raz.
-- Bezpieczeństwo jak przy sprzedaży: dane gracza żyją w jednej sesji ProfileStore, więc połączenie
-- jest atomowe w pamięci serwera i trafia do zapisu razem z resztą.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Forge = require(ReplicatedStorage.Shared.Forge)
local Progress = require(ReplicatedStorage.Shared.Progress)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Ledger = require(script.Parent.Ledger)

export type Hooks = {
	getData: (Player) -> any?,
	rootOf: (Player) -> BasePart?,
	busy: (Player) -> boolean, -- pościg, leży, ekspedycja: wtedy nie łączymy
	notify: (Player, string, { any }?, string?, any?) -> (),
	pushState: (Player) -> (),
	found: (Player, Forge.Item) -> (), -- wpis do Grzybopedii (strona kuźni)
	event: (Player, string, number) -> (), -- liczniki (tytuły, odznaki)
}

local ForgeService = {}

local REACH = 6 -- ile studs poza obwódką moździerza można jeszcze stać

-- Komunikat po połączeniu według rodzaju wyniku (próg runy albo przepis)
local MESSAGE: { [string]: string } = {
	bust = "MSG_FORGE_BUST",
	worse = "MSG_FORGE_DONE",
	similar = "MSG_FORGE_DONE",
	better = "MSG_FORGE_BETTER",
	great = "MSG_FORGE_GREAT",
	recipe = "MSG_FORGE_RECIPE",
	recipeLucky = "MSG_FORGE_RECIPE",
	mythic = "MSG_FORGE_MYTHIC",
	secret = "MSG_FORGE_SECRET",
}

function ForgeService.start(station: Vector3, prompt: ProximityPrompt?, hooks: Hooks)
	local view = Remotes.get("ForgeView")
	local action = Remotes.get("ForgeAction")
	local nextAt: { [Player]: number } = {}
	local rng = Random.new()
	-- Grzybopedia, liczniki i komunikaty po animacji bębna (inaczej „NOWY” przy Grzybopedii i Tytułach
	-- zdradza wynik). Przy wyjściu z gry flush() robi je od razu, przed ostatnim zapisem.
	local pending: { [Player]: { () -> () } } = {}

	local function later(player: Player, fn: () -> ())
		local list = pending[player]
		if not list then
			list = {}
			pending[player] = list
		end
		table.insert(list, fn)
		task.delay(Config.Forge.revealDelay, function()
			local current = pending[player]
			local at = if current then table.find(current, fn) else nil
			if current and at then
				table.remove(current, at)
				fn()
			end
		end)
	end

	local function flush(player: Player)
		local list = pending[player]
		pending[player] = nil
		for _, fn in (list or {}) :: { () -> () } do
			fn()
		end
	end

	local function near(player: Player): boolean
		local root = hooks.rootOf(player)
		if not root then
			return false
		end
		local offset = root.Position - station
		return Vector3.new(offset.X, 0, offset.Z).Magnitude <= Config.Forge.station.radius + REACH
	end

	local function access(data: any): Forge.Access
		return {
			swampUnlocked = data.swampUnlocked == true,
			mountainUnlocked = data.mountainUnlocked == true,
			jagaEscapes = Progress.guardianRecord(data.bestiary, "jaga").escaped,
		}
	end

	-- Stan okna u gracza: dostęp do przepisów i formy z kolekcji (maski Grzybopedii), a po połączeniu
	-- wynik z rodzajem (do animacji runy)
	local function send(player: Player, open: boolean, result: Forge.Item?, kind: string?)
		local data = hooks.getData(player)
		if not data then
			return
		end
		local found: { [string]: number } = {}
		for _, species in Progress.pageSpecies(Progress.FORGE_PAGE) do
			found[species.id] = Progress.mask(data.atlas, species.id)
		end
		view:FireClient(player, {
			access = access(data),
			found = found,
			result = result,
			kind = kind,
			readyIn = math.max(0, (nextAt[player] or 0) - os.clock()),
		}, open)
	end

	if prompt then
		prompt.Triggered:Connect(function(player: Player)
			if near(player) then
				send(player, true)
			end
		end)
	end

	-- Tylko w Studio: testy otwierają okno atrybutem (narzędzia Studio nie klikają ProximityPrompt)
	if RunService:IsStudio() then
		local function watch(player: Player)
			player:GetAttributeChangedSignal("DevOpenForge"):Connect(function()
				send(player, true)
			end)
		end
		for _, player in Players:GetPlayers() do
			watch(player)
		end
		Players.PlayerAdded:Connect(watch)
	end
	Players.PlayerRemoving:Connect(function(player)
		nextAt[player] = nil
		pending[player] = nil
	end)

	local function refuse(player: Player, key: string, args: { any }?)
		hooks.notify(player, key, args)
		send(player, false)
	end

	action.OnServerEvent:Connect(function(player: Player, payload: unknown)
		if typeof(payload) ~= "table" then
			return
		end
		local request = payload :: any
		if request.kind ~= "fuse" then
			return
		end
		local now = os.clock()
		if now < (nextAt[player] or 0) then
			refuse(player, "FORGE_COOLDOWN", { math.ceil((nextAt[player] or 0) - now) })
			return
		end
		local data = hooks.getData(player)
		local slots = request.slots
		if not data or typeof(slots) ~= "table" or typeof(request.key) ~= "string" then
			return
		end
		if not near(player) then
			refuse(player, "FORGE_FAR")
			return
		end
		if hooks.busy(player) then
			refuse(player, "FORGE_UNSAFE")
			return
		end
		-- Koszyk zmienił się od czasu, gdy okno go pokazało (kruk, sprzedaż...): nic nie robimy
		local basket = data.basket
		if request.key ~= Economy.basketKey(basket) then
			hooks.pushState(player)
			refuse(player, "FORGE_CHANGED")
			return
		end
		-- Dokładnie trzy różne, poprawne indeksy koszyka (w kolejności wrzucenia)
		local indices: { number } = {}
		for slot = 1, Forge.SLOTS do
			local index = (slots :: any)[slot]
			if typeof(index) ~= "number" or index ~= math.floor(index) or index < 1 or index > #basket or table.find(indices, index) then
				refuse(player, "FORGE_WRONG_INPUT")
				return
			end
			table.insert(indices, index)
		end
		local items: { Forge.Item } = {}
		for _, index in indices do
			table.insert(items, basket[index])
		end
		local preview, why = Forge.preview(items, access(data))
		if not preview then
			refuse(player, why or "FORGE_WRONG_INPUT")
			return
		end
		if data.coins < preview.fee then
			refuse(player, "FORGE_NO_COINS", { preview.fee - data.coins })
			return
		end

		-- Połączenie: opłata, 3 grzyby (od końca, żeby indeksy się nie przesuwały), wynik do koszyka
		local result, kind = Forge.roll(preview, {
			recipe = rng:NextNumber(),
			tier = rng:NextNumber(),
			spread = rng:NextNumber(),
			mutation = rng:NextNumber(),
			pick = rng:NextNumber(),
		})
		Ledger.spend(player, data, preview.fee, "Gameplay", "Forge")
		table.sort(indices, function(a, b)
			return a > b
		end)
		for _, index in indices do
			table.remove(basket, index)
		end
		table.insert(basket, result)
		nextAt[player] = now + Config.Forge.cooldown

		hooks.pushState(player)
		send(player, false, result, kind)
		-- Grzybopedia, tytuły i komunikat po animacji runy w oknie (ForgePanel), żeby nie zdradzały wyniku
		local species = Economy.getSpecies(result.s)
		local key = MESSAGE[kind] or "MSG_FORGE_DONE"
		later(player, function()
			hooks.event(player, "forge", 1)
			hooks.found(player, result)
			hooks.notify(player, key, nil, species and species.key or nil, { variant = result.v, tags = result.x })
		end)
	end)

	local self = {}
	-- Panel DEV / testy: otwórz okno kuźni z dowolnego miejsca
	function self.open(player: Player)
		send(player, true)
	end
	-- Wyjście z gry: odłożone wpisy (Grzybopedia, liczniki) od razu, zanim dane trafią do zapisu
	self.flush = flush
	return self
end

return ForgeService
