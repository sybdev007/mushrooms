--!strict
-- Znalezisko Nocy po stronie gracza (serwer: NightFindService, grzyba rysuje DisplayMushrooms):
--   przycisk „Zerwij” przy Znalezisku w języku gracza;
--   napis „✨ Znalezisko Nocy” nad nim, widoczny z daleka (razem ze słupem światła z serwera);
--   nad głową niosącego (atrybut postaci NightFindUntil, czas serwera) odliczanie, które widzą wszyscy;
--   u niosącego pasek pod środkiem HUD: „Donieś do chatki! 2:41 · jeszcze 180 m”.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Localize = require(script.Parent.Localize)
local PanelKit = require(script.Parent.PanelKit)
local UiKit = require(script.Parent.UiKit)
local UiScale = require(script.Parent.UiScale)

local NightFindView = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local GOLD = Color3.fromRGB(255, 214, 90)
local HUD_TOP = 108 -- pod paskiem strefy i oleju (Hud: Top 8 + 94) i zapowiedzią nocy
local CABIN_Z = Config.Zones[2].startZ -- polana przy chatce kończy się tutaj

local function clock(seconds: number): string
	local total = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", total // 60, total % 60)
end

local function textBillboard(name: string, size: UDim2, textSize: number): (BillboardGui, TextLabel)
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Size = size
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = PanelKit.TITLE_FONT
	label.TextSize = textSize
	label.TextColor3 = GOLD
	label.Parent = gui
	UiKit.outline(label, 2)
	return gui, label
end

-- ===== Przycisk i napis nad Znaleziskiem =====

local prompts: { [ProximityPrompt]: boolean } = {}
local markerLabels: { [Instance]: BillboardGui } = {}

local function refreshPrompt(prompt: ProximityPrompt)
	prompt.ActionText = Localize.t("NIGHTFIND_ACTION")
	prompt.ObjectText = Localize.t("NIGHTFIND_NAME")
end

local function promptAdded(instance: Instance)
	if instance:IsA("ProximityPrompt") then
		prompts[instance] = true
		refreshPrompt(instance)
	end
end

local function markerAdded(marker: Instance)
	if markerLabels[marker] or not marker:IsA("Model") then
		return
	end
	local root = marker.PrimaryPart or marker:WaitForChild("Root", 10)
	if not (root and root:IsA("BasePart")) or not marker.Parent then
		return
	end
	local gui, label = textBillboard("NightFindLabel", UDim2.fromOffset(220, 30), 22)
	gui.Adornee = root
	gui.StudsOffset = Vector3.new(0, 7.5, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 600
	label.Text = "✨ " .. Localize.t("NIGHTFIND_NAME")
	gui.Parent = playerGui
	markerLabels[marker] = gui
end

local function markerRemoved(marker: Instance)
	local gui = markerLabels[marker]
	if gui then
		markerLabels[marker] = nil
		gui:Destroy()
	end
end

-- ===== Niosący: odliczanie nad głową (widzą wszyscy) =====

type CarrierLabel = { gui: BillboardGui, label: TextLabel }
local carrierLabels: { [Model]: CarrierLabel } = {}

local function untilOf(character: Model?): number?
	local value = character and character:GetAttribute("NightFindUntil")
	return if typeof(value) == "number" then value else nil
end

local function updateCarriers(now: number)
	local seen: { [Model]: boolean } = {}
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local untilTime = untilOf(character)
		local head = character and character:FindFirstChild("Head")
		if other ~= player and character and untilTime and head and head:IsA("BasePart") then
			seen[character] = true
			local entry: CarrierLabel? = carrierLabels[character]
			if entry and entry.gui.Adornee ~= head then
				entry.gui:Destroy()
				entry = nil
			end
			if not entry then
				local gui, label = textBillboard("NightFindCarrier", UDim2.fromOffset(120, 28), 20)
				gui.Adornee = head
				gui.StudsOffset = Vector3.new(0, 4.6, 0)
				gui.MaxDistance = 250
				gui.Parent = playerGui
				local created = { gui = gui, label = label }
				carrierLabels[character] = created
				entry = created
			end
			if entry then
				entry.label.Text = "✨ " .. clock(untilTime - now)
			end
		end
	end
	for character, entry in carrierLabels do
		if not seen[character] then
			carrierLabels[character] = nil
			entry.gui:Destroy()
		end
	end
end

-- ===== Pasek u niosącego =====

local gui = Instance.new("ScreenGui")
gui.Name = "NightFindHud"
gui.ResetOnSpawn = false
gui.DisplayOrder = 3
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local bar = Instance.new("Frame")
bar.Name = "Bar"
bar.AnchorPoint = Vector2.new(0.5, 0)
bar.Size = UDim2.fromOffset(360, 34)
bar.BackgroundColor3 = Color3.fromRGB(26, 16, 44)
bar.BackgroundTransparency = 0.1
bar.Visible = false
bar.Parent = gui
PanelKit.corner(bar, UDim.new(1, 0))
PanelKit.stroke(bar, GOLD, 2)
local barScale = Instance.new("UIScale")
barScale.Parent = bar
local barText = PanelKit.label(bar, "Text", UDim2.new(1, -20, 1, -6), UDim2.fromOffset(10, 3), 18, GOLD, PanelKit.TITLE_FONT)
UiKit.outline(barText, 2)

local function layout()
	local scale = UiScale.get()
	barScale.Scale = scale
	bar.Position = UDim2.new(0.5, 0, 0, math.floor(HUD_TOP * scale))
end
layout()
UiScale.onChanged(layout)

local function updateBar(now: number)
	local character = player.Character
	local untilTime = untilOf(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (untilTime and root and root:IsA("BasePart")) then
		bar.Visible = false
		return
	end
	local meters = math.max(0, math.floor(root.Position.Z - CABIN_Z))
	barText.Text = "✨ " .. Localize.t("NIGHTFIND_HUD", { clock(untilTime - now), tostring(meters) })
	bar.Visible = true
end

function NightFindView.start()
	CollectionService:GetInstanceAddedSignal("NightFindPrompt"):Connect(promptAdded)
	CollectionService:GetInstanceRemovedSignal("NightFindPrompt"):Connect(function(instance)
		prompts[instance :: ProximityPrompt] = nil
	end)
	for _, instance in CollectionService:GetTagged("NightFindPrompt") do
		promptAdded(instance)
	end
	CollectionService:GetInstanceAddedSignal("NightFind"):Connect(function(marker)
		task.spawn(markerAdded, marker)
	end)
	CollectionService:GetInstanceRemovedSignal("NightFind"):Connect(markerRemoved)
	for _, marker in CollectionService:GetTagged("NightFind") do
		task.spawn(markerAdded, marker)
	end
	Localize.onChanged(function()
		for prompt in prompts do
			refreshPrompt(prompt)
		end
		for _, label in markerLabels do
			local text = label:FindFirstChildOfClass("TextLabel")
			if text then
				text.Text = "✨ " .. Localize.t("NIGHTFIND_NAME")
			end
		end
	end)
	task.spawn(function()
		while true do
			local now = Workspace:GetServerTimeNow()
			updateCarriers(now)
			updateBar(now)
			task.wait(0.2)
		end
	end)
end

return NightFindView
