--!strict
-- Przyciski w ogródkach (ProximityPrompt). Serwer tworzy je wszystkie wyłączone,
-- a tu włączamy lokalnie tylko te, które mają sens dla tego gracza:
--   własny ogródek  -> „Posadź grzyby” i „Odbierz monety” przy skrzyni
--   cudzy ogródek   -> „Wyrwij grzyb” (tylko gdy coś tam rośnie); zamiast tego „Najpierw 3 🍄 z lasu”,
--                      gdy złodziej musi jeszcze zebrać grzyby w lesie (atrybut gracza StealPicksLeft),
--                      albo „🛡️ Chroniony 0:45” z odliczaniem po kradzieży (atrybut ogródka ProtectedUntil)
-- Teksty przycisków są w języku gracza i zmieniają się razem z przełącznikiem EN/PL.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Localize = require(script.Parent.Localize)
local Purchases = require(script.Parent.Purchases)

local GardenPrompts = {}

local player = Players.LocalPlayer
local tracked: { [Model]: boolean } = {}

-- Sekundy ochrony ogródka, które zostały (0 = można kraść)
local function protectedLeft(rack: Model): number
	local untilTime = rack:GetAttribute("ProtectedUntil")
	if typeof(untilTime) ~= "number" then
		return 0
	end
	return math.max(0, untilTime - Workspace:GetServerTimeNow())
end

-- Tekst przycisku kradzieży: zwykły, „najpierw grzyby z lasu” albo ochrona z odliczaniem
local function stealText(rack: Model, key: string): string
	local left = player:GetAttribute("StealPicksLeft")
	if typeof(left) == "number" and left > 0 then
		return Localize.t("GARDEN_STEAL_FOREST", { left })
	end
	local seconds = protectedLeft(rack)
	if seconds > 0 then
		local total = math.ceil(seconds)
		return Localize.t("GARDEN_PROTECTED", { string.format("%d:%02d", total // 60, total % 60) })
	end
	return Localize.t(key)
end

local function promptsOf(rack: Model): { ProximityPrompt }
	local list = {}
	for _, descendant in rack:GetDescendants() do
		if descendant:IsA("ProximityPrompt") then
			table.insert(list, descendant)
		end
	end
	return list
end

local function refresh(rack: Model)
	local ownerId = rack:GetAttribute("OwnerUserId")
	local ownerName = rack:GetAttribute("OwnerName")
	local count = rack:GetAttribute("Count")
	local hasOwner = typeof(ownerId) == "number" and ownerId ~= 0
	local mine = hasOwner and ownerId == player.UserId
	local hasItems = typeof(count) == "number" and count > 0
	for _, prompt in promptsOf(rack) do
		local key = prompt:GetAttribute("TextKey")
		if typeof(key) == "string" then
			prompt.ActionText = if prompt:GetAttribute("Thief") == true then stealText(rack, key) else Localize.t(key)
		end
		if prompt:GetAttribute("X2") == true then
			-- G: odbierz x2, tylko we własnym ogródku i gdy w skrzyni jest dość na ofertę (ChestOffers)
			local product = rack:GetAttribute("X2Product")
			local ready = typeof(product) == "string" and product ~= "" and Purchases.available(product)
			prompt.Enabled = mine and ready
			prompt.ObjectText = if ready then Purchases.priceText(product :: string) else ""
		elseif prompt:GetAttribute("Owner") == true then
			prompt.Enabled = mine
			prompt.ObjectText = Localize.t("GARDEN_YOURS")
		elseif prompt:GetAttribute("Thief") == true then
			prompt.Enabled = hasOwner and not mine and hasItems
			prompt.ObjectText = Localize.t("GARDEN_OF", { if typeof(ownerName) == "string" then ownerName else "?" })
		end
	end
end

local function track(rack: Instance)
	if not rack:IsA("Model") or tracked[rack] then
		return
	end
	tracked[rack] = true
	for _, name in { "OwnerUserId", "OwnerName", "Count", "X2Product", "ProtectedUntil" } do
		rack:GetAttributeChangedSignal(name):Connect(function()
			refresh(rack)
		end)
	end
	-- Przyciski mogą dojść po suszarni (replikacja), wtedy też je ustawiamy
	rack.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("ProximityPrompt") then
			refresh(rack)
		end
	end)
	rack.Destroying:Connect(function()
		tracked[rack] = nil
	end)
	refresh(rack)
end

function GardenPrompts.start()
	-- Serwer oznacza każdy ogródek tagiem "GardenPlot"
	for _, rack in CollectionService:GetTagged("GardenPlot") do
		track(rack)
	end
	CollectionService:GetInstanceAddedSignal("GardenPlot"):Connect(track)
	Localize.onChanged(function()
		for rack in tracked do
			refresh(rack)
		end
	end)
	-- Złodziej zebrał grzyb w lesie albo właśnie ukradł: zmienia się tekst przycisku w cudzych ogródkach
	player:GetAttributeChangedSignal("StealPicksLeft"):Connect(function()
		for rack in tracked do
			refresh(rack)
		end
	end)
	-- Odliczanie ochrony na przycisku (tylko ogródki, które są teraz chronione, i jeszcze raz na końcu)
	task.spawn(function()
		local counting: { [Model]: boolean } = {}
		while true do
			task.wait(0.5)
			for rack in tracked do
				if protectedLeft(rack) > 0 then
					counting[rack] = true
					refresh(rack)
				elseif counting[rack] then
					counting[rack] = nil
					refresh(rack)
				end
			end
		end
	end)
	-- Ceny produktów przychodzą z Robloxa po chwili: wtedy napis przy „Odbierz x2” się poprawia
	task.delay(8, function()
		for rack in tracked do
			refresh(rack)
		end
	end)
end

return GardenPrompts
