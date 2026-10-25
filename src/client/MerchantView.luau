--!strict
-- Skupywacz w chatce po stronie klienta: teksty przycisku rozmowy i tabliczki w języku gracza,
-- lekkie kołysanie i obracanie się w stronę gracza, a po rozmowie otwarcie panelu sprzedaży.
-- Model stoi na serwerze (World/Merchant.luau); ruch robimy tylko lokalnie, więc nic nie idzie przez sieć.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Localize = require(script.Parent.Localize)
local SellPanel = require(script.Parent.SellPanel)

local MerchantView = {}

local TURN_RANGE = 22 -- z tej odległości skupywacz odwraca się do gracza
local MAX_TURN = math.rad(55)

type Tracked = { model: Model, home: CFrame, prompt: ProximityPrompt?, name: TextLabel?, role: TextLabel?, yaw: number }
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
			home = instance:GetPivot(),
			prompt = if prompt and prompt:IsA("ProximityPrompt") then prompt else nil,
			name = if name and name:IsA("TextLabel") then name else nil,
			role = if role and role:IsA("TextLabel") then role else nil,
			yaw = 0,
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

	RunService.RenderStepped:Connect(function(dt)
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local t = os.clock()
		for _, entry in tracked do
			if typeof(entry) ~= "table" then
				continue
			end
			local home = entry.home
			-- Docelowy obrót: w stronę gracza, jeśli jest blisko i przed ladą, inaczej prosto
			local target = 0
			if root and root:IsA("BasePart") then
				local localPos = home:PointToObjectSpace(root.Position)
				local distance = Vector3.new(localPos.X, 0, localPos.Z).Magnitude
				if distance < TURN_RANGE and localPos.Z < 0 then
					target = math.clamp(math.atan2(-localPos.X, -localPos.Z), -MAX_TURN, MAX_TURN)
				end
			end
			entry.yaw += (target - entry.yaw) * math.clamp(dt * 4, 0, 1)
			-- Oddech: lekkie unoszenie i kołysanie
			local bob = math.sin(t * 2) * 0.05
			local sway = math.sin(t * 1.3) * 0.02
			entry.model:PivotTo(home * CFrame.new(0, bob, 0) * CFrame.Angles(0, entry.yaw, sway))
		end
	end)
end

return MerchantView
