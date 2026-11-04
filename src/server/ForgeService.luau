--!strict
-- Kuźnia Grzybów: Moździerz Zielarki na Placu Portali (World/Forge). Gracz wybiera przepis i 3 grzyby
-- z koszyka, płaci opłatę, a serwer w jednym kroku (bez czekania) zabiera opłatę i 3 grzyby i wkłada do
-- koszyka 1 grzyb z kuźni. Zasady i liczby: Shared/Forge, Config.Forge, docs/plans/kuznia.md.
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

function ForgeService.start(station: Vector3, prompt: ProximityPrompt?, hooks: Hooks)
	local view = Remotes.get("ForgeView")
	local action = Remotes.get("ForgeAction")
	local nextAt: { [Player]: number } = {}
	local rng = Random.new()

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

	-- Stan okna u gracza: dostęp do przepisów i formy z kolekcji (maski Grzybopedii)
	local function send(player: Player, open: boolean, result: Forge.Item?, lucky: boolean?)
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
			lucky = lucky == true,
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
		if request.kind ~= "craft" then
			return
		end
		local now = os.clock()
		if now < (nextAt[player] or 0) then
			refuse(player, "FORGE_COOLDOWN", { math.ceil((nextAt[player] or 0) - now) })
			return
		end
		local data = hooks.getData(player)
		local recipe = Forge.recipe(request.recipe)
		local slots = request.slots
		if not data or not recipe or typeof(slots) ~= "table" or typeof(request.key) ~= "string" then
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
		local ok, reason = Forge.unlocked(recipe, access(data))
		if not ok then
			refuse(player, reason or "FORGE_WRONG_INPUT")
			return
		end
		-- Koszyk zmienił się od czasu, gdy okno go pokazało (kruk, sprzedaż...): nic nie robimy
		local basket = data.basket
		if request.key ~= Economy.basketKey(basket) then
			hooks.pushState(player)
			refuse(player, "FORGE_CHANGED")
			return
		end
		-- Dokładnie tyle różnych, poprawnych indeksów koszyka, ile slotów w przepisie
		local indices: { number } = {}
		for slot = 1, #recipe.inputs do
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
		local quote, why = Forge.quote(recipe, items)
		if not quote then
			refuse(player, why or "FORGE_WRONG_INPUT")
			return
		end
		if data.coins < quote.fee then
			refuse(player, "FORGE_NO_COINS", { quote.fee - data.coins })
			return
		end

		-- Połączenie: opłata, 3 składniki (od końca, żeby indeksy się nie przesuwały), wynik do koszyka
		data.coins -= quote.fee
		table.sort(indices, function(a, b)
			return a > b
		end)
		for _, index in indices do
			table.remove(basket, index)
		end
		local result, lucky = Forge.result(quote, rng:NextNumber())
		table.insert(basket, result)
		nextAt[player] = now + Config.Forge.cooldown

		hooks.event(player, "forge", 1)
		hooks.found(player, result)
		hooks.pushState(player)
		local species = Economy.getSpecies(result.s)
		hooks.notify(player, if lucky then "MSG_FORGE_LUCKY" else "MSG_FORGE_DONE", nil, species and species.key or nil, {
			variant = result.v,
			tags = result.x,
		})
		send(player, false, result, lucky)
	end)

	local self = {}
	-- Panel DEV / testy: otwórz okno kuźni z dowolnego miejsca
	function self.open(player: Player)
		send(player, true)
	end
	return self
end

return ForgeService
