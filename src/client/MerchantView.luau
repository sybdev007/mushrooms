--!strict
-- Skupywacz w chatce po stronie klienta: teksty przycisku rozmowy i tabliczki w języku gracza,
-- a po rozmowie otwarcie panelu sprzedaży. Stoi w miejscu (obracanie się za graczem przesuwało
-- tabliczkę z imieniem w ścianę). Model stoi na serwerze (World/Merchant.luau).

local CollectionService = game:GetService("CollectionService")

local Localize = require(script.Parent.Localize)
local SellPanel = require(script.Parent.SellPanel)

local MerchantView = {}

type Tracked = { model: Model, prompt: ProximityPrompt?, name: TextLabel?, role: TextLabel? }
local tracked: { [Model]: Tracked } = {}

local function refreshTexts(entry: Tracked)
	if entry.prompt then
		entry.prompt.ActionText = Localize.t("NPC_SELL")
		entry.prompt.ObjectText = Localize.t("NPC_NAME")
	end
	if entry.name then
		entry.name.Text = Localize.t("NPC_NAME")
	end
	if entry.role then
		entry.role.Text = Localize.t("NPC_ROLE")
	end
end

local function track(instance: Instance)
	if not instance:IsA("Model") or tracked[instance] then
		return
	end
	tracked[instance] = true :: any -- zajęte, zanim dotrą części
	-- Tag przychodzi razem z pustym modelem, a części (przycisk, głowa z tabliczką) docierają później
	task.spawn(function()
		local root = instance:WaitForChild("Root", 15)
		local head = instance:WaitForChild("Head", 15)
		local prompt = root and root:WaitForChild("MerchantPrompt", 15)
		local tag = head and head:WaitForChild("NameTag", 15)
		local name = tag and tag:WaitForChild("Name", 5)
		local role = tag and tag:WaitForChild("Role", 5)
		if instance.Parent == nil then
			tracked[instance] = nil
			return
		end
		local entry: Tracked = {
			model = instance,
			prompt = if prompt and prompt:IsA("ProximityPrompt") then prompt else nil,
			name = if name and name:IsA("TextLabel") then name else nil,
			role = if role and role:IsA("TextLabel") then role else nil,
		}
		tracked[instance] = entry
		refreshTexts(entry)
		if entry.prompt then
			entry.prompt.Triggered:Connect(function()
				SellPanel.open()
			end)
		end
	end)
	instance.Destroying:Connect(function()
		tracked[instance] = nil
	end)
end

function MerchantView.start()
	for _, model in CollectionService:GetTagged("Merchant") do
		track(model)
	end
	CollectionService:GetInstanceAddedSignal("Merchant"):Connect(track)
	Localize.onChanged(function()
		for _, entry in tracked do
			if typeof(entry) == "table" then
				refreshTexts(entry)
			end
		end
	end)
end

return MerchantView
