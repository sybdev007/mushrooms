--!strict
-- Przyciski przy suszarniach (ProximityPrompt). Serwer tworzy je wszystkie wyłączone,
-- a tu włączamy lokalnie tylko te, które mają sens dla tego gracza:
--   własna suszarnia  -> „Rozwieś grzyby” i „Sprzedaj suszone”
--   cudza suszarnia   -> „Podkradnij” (tylko gdy coś na niej wisi)
-- Teksty przycisków są w języku gracza i zmieniają się razem z przełącznikiem EN/PL.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Localize = require(script.Parent.Localize)

local RackPrompts = {}

local player = Players.LocalPlayer
local tracked: { [Model]: boolean } = {}

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
			prompt.ActionText = Localize.t(key)
		end
		if prompt:GetAttribute("Owner") == true then
			prompt.Enabled = mine
			prompt.ObjectText = Localize.t("RACK_YOURS")
		elseif prompt:GetAttribute("Thief") == true then
			prompt.Enabled = hasOwner and not mine and hasItems
			prompt.ObjectText = Localize.t("RACK_OF", { if typeof(ownerName) == "string" then ownerName else "?" })
		end
	end
end

local function track(rack: Instance)
	if not rack:IsA("Model") or tracked[rack] then
		return
	end
	tracked[rack] = true
	for _, name in { "OwnerUserId", "OwnerName", "Count" } do
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

function RackPrompts.start()
	task.spawn(function()
		local map = Workspace:WaitForChild("Map")
		local folder = map:WaitForChild("DryingRacks", 30)
		if not folder then
			return
		end
		for _, rack in folder:GetChildren() do
			track(rack)
		end
		folder.ChildAdded:Connect(track)
	end)
	Localize.onChanged(function()
		for rack in tracked do
			refresh(rack)
		end
	end)
end

return RackPrompts
