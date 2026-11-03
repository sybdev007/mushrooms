--!strict
-- Relikty na podestach w ogródkach (DelveService, tag "RelicDisplay"): u każdego gracza lokalnie
-- obracają się powoli i unoszą nad postumentem, a nad nimi wisi tabliczka z nazwą w języku gracza
-- (gwiazdki = oprawa, „zakurzony” = jeszcze do odnowienia). Daleko od kamery nic się nie rusza.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Localize = require(script.Parent.Localize)
local UiKit = require(script.Parent.UiKit)

local RelicDisplay = {}

local TAG = "RelicDisplay"
local SPIN_SPEED = 0.8 -- rad/s
local BOB = 0.18
local FAR = 90
local FRAME_COLORS = {
	[0] = Color3.fromRGB(255, 244, 222),
	[1] = Color3.fromRGB(240, 170, 110),
	[2] = Color3.fromRGB(225, 230, 240),
	[3] = Color3.fromRGB(255, 214, 90),
}

type Entry = { model: Model, base: CFrame, phase: number, label: TextLabel?, sub: TextLabel? }
local entries: { [Model]: Entry } = {}

local function refreshLabel(entry: Entry)
	local model = entry.model
	local key = model:GetAttribute("RelicKey")
	local frame = model:GetAttribute("Frame")
	local restored = model:GetAttribute("Restored") == true
	local tier = if typeof(frame) == "number" then frame else 0
	if entry.label then
		entry.label.Text = (if model:GetAttribute("Rare") == true then "★ " else "") .. (if typeof(key) == "string" then Localize.t(key) else "")
		entry.label.TextColor3 = if restored then FRAME_COLORS[tier] or FRAME_COLORS[0] else Color3.fromRGB(190, 186, 180)
	end
	if entry.sub then
		entry.sub.Text = if not restored then Localize.t("DELVE_STATUS_DUSTY") elseif tier > 0 then string.rep("◆", tier) else ""
	end
end

local function track(instance: Instance)
	if not instance:IsA("Model") or entries[instance] then
		return
	end
	local model = instance
	local core = model.PrimaryPart or model:WaitForChild("Core", 5)
	if not (core and core:IsA("BasePart")) then
		return
	end
	local entry: Entry = { model = model, base = model:GetPivot(), phase = math.random() * 6 }
	-- Tabliczka z nazwą nad reliktem
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "RelicName"
	billboard.Size = UDim2.fromOffset(170, 40)
	billboard.StudsOffset = Vector3.new(0, 1.9, 0)
	billboard.MaxDistance = 32
	billboard.LightInfluence = 0
	billboard.Adornee = core
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 22)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Parent = billboard
	UiKit.outline(label, 2)
	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Size = UDim2.new(1, 0, 0, 16)
	sub.Position = UDim2.fromOffset(0, 22)
	sub.Font = Enum.Font.GothamBold
	sub.TextScaled = true
	sub.TextColor3 = Color3.fromRGB(255, 214, 90)
	sub.Parent = billboard
	UiKit.outline(sub, 1.5)
	billboard.Parent = core
	entry.label = label
	entry.sub = sub
	entries[model] = entry
	refreshLabel(entry)
	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(Workspace) then
			entries[model] = nil
		end
	end)
end

for _, model in CollectionService:GetTagged(TAG) do
	task.spawn(track, model)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(function(model)
	task.spawn(track, model)
end)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(model)
	entries[model :: Model] = nil
end)
Localize.onChanged(function()
	for _, entry in entries do
		refreshLabel(entry)
	end
end)

RunService.RenderStepped:Connect(function()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	local t = os.clock()
	for model, entry in entries do
		if not model.Parent then
			entries[model] = nil
			continue
		end
		if (entry.base.Position - eye).Magnitude > FAR then
			continue
		end
		local spin = CFrame.Angles(0, t * SPIN_SPEED + entry.phase, 0)
		local lift = CFrame.new(0, math.sin(t * 1.6 + entry.phase) * BOB, 0)
		model:PivotTo(CFrame.new(entry.base.Position) * lift * spin)
	end
end)

return RelicDisplay
