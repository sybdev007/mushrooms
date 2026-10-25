--!strict
-- Tytuł z Grzybopedii nad głową gracza („Znawca Lasu”, „Arcygrzybiarz”), widoczny dla wszystkich.
-- Serwer zapisuje klucz tytułu w atrybucie gracza "AtlasTitle"; tu tłumaczymy go na język gracza.
-- BillboardGui trzymamy w PlayerGui z Adornee na głowie postaci.

local Players = game:GetService("Players")

local Localize = require(script.Parent.Localize)

local TitleView = {}

local folder = Instance.new("Folder")
folder.Name = "AtlasTitles"
folder.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

local labels: { [Player]: BillboardGui } = {}

local function update(target: Player)
	local key = target:GetAttribute("AtlasTitle")
	local character = target.Character
	local head = character and character:FindFirstChild("Head")
	local existing = labels[target]
	if typeof(key) ~= "string" or key == "" or not head then
		if existing then
			existing:Destroy()
			labels[target] = nil
		end
		return
	end
	local gui = existing
	if not gui then
		local created = Instance.new("BillboardGui")
		created.Name = "Title_" .. target.UserId
		created.Size = UDim2.fromOffset(220, 26)
		created.StudsOffset = Vector3.new(0, 2.4, 0)
		created.MaxDistance = 70
		created.AlwaysOnTop = false
		created.LightInfluence = 0
		created.ResetOnSpawn = false
		local text = Instance.new("TextLabel")
		text.Name = "Text"
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.FredokaOne
		text.TextScaled = true
		text.TextStrokeTransparency = 0.2
		text.TextStrokeColor3 = Color3.fromRGB(50, 30, 10)
		text.Parent = created
		created.Parent = folder
		labels[target] = created
		gui = created
	end
	local billboard = gui :: BillboardGui
	billboard.Adornee = head :: BasePart
	local text = billboard:FindFirstChild("Text") :: TextLabel
	text.Text = "📖 " .. Localize.t(key)
	-- Arcygrzybiarz tęczowo-złoty, mistrzowie złoci, znawcy srebrni
	text.TextColor3 = if key == "TITLE_GRANDMASTER"
		then Color3.fromRGB(255, 140, 230)
		elseif string.find(key, "MASTER", 1, true) then Color3.fromRGB(255, 214, 80)
		else Color3.fromRGB(214, 228, 240)
end

local function watch(target: Player)
	target:GetAttributeChangedSignal("AtlasTitle"):Connect(function()
		update(target)
	end)
	target.CharacterAdded:Connect(function(character)
		character:WaitForChild("Head", 10)
		update(target)
	end)
	update(target)
end

for _, target in Players:GetPlayers() do
	watch(target)
end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(function(target)
	local gui = labels[target]
	if gui then
		gui:Destroy()
		labels[target] = nil
	end
end)
Localize.onChanged(function()
	for target in labels do
		update(target)
	end
end)

return TitleView
