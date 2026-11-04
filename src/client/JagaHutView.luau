--!strict
-- Chatka Baby Jagi na kurzej stopce (tag "JagaHut", World/Mountain): klient obraca ją u siebie według
-- Shared/Mountain.hutYaw i czasu serwera, więc widzi to samo, co liczy serwer, a przez sieć nic nie leci.
-- Kiedy drzwi patrzą na ogródek, okna świecą mocniej, a snop światła spod drzwi robi się czerwony; gracz
-- w ogródku dostaje ostrzeżenie, że chatka go widzi (zerwanie Ziela wtedy budzi Jagę od razu).
-- Oś obrotu bierzemy z atrybutu Center, nie z GetPivot: przy StreamingEnabled model może dotrzeć
-- do klienta bez części Pivot i wtedy GetPivot zwraca (0, 0, 0), a chatka odleciałaby na środek mapy.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Mountain = require(ReplicatedStorage.Shared.Mountain)
local Hud = require(script.Parent.Hud)
local Localize = require(script.Parent.Localize)

local JagaHutView = {}

local FAR = 260
local SHAFT_CALM = ColorSequence.new(Color3.fromRGB(130, 220, 70))
local SHAFT_WATCH = ColorSequence.new(Color3.fromRGB(255, 70, 50))
local function shaftFade(start: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, start),
		NumberSequenceKeypoint.new(0.75, 0.8),
		NumberSequenceKeypoint.new(1, 1),
	})
end
local SHAFT_FADE_CALM = shaftFade(0.55)
local SHAFT_FADE_WATCH = shaftFade(0.3)
local WINDOW_CALM = 0.45
local WINDOW_WATCH = 0.05

type Entry = { model: Model, center: Vector3, glows: { BasePart } }
local entries: { [Model]: Entry } = {}
local lastWarn = 0

local function collectGlows(model: Model): { BasePart }
	local glows = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part:GetAttribute("WatchGlow") == true then
			table.insert(glows, part)
		end
	end
	return glows
end

local function track(instance: Instance)
	if not instance:IsA("Model") or entries[instance] then
		return
	end
	local center = instance:GetAttribute("Center")
	if typeof(center) ~= "Vector3" then
		return
	end
	entries[instance] = { model = instance, center = center, glows = {} }
end

for _, model in CollectionService:GetTagged("JagaHut") do
	track(model)
end
CollectionService:GetInstanceAddedSignal("JagaHut"):Connect(track)
CollectionService:GetInstanceRemovedSignal("JagaHut"):Connect(function(model)
	entries[model :: Model] = nil
end)

RunService.RenderStepped:Connect(function()
	local camera = Workspace.CurrentCamera
	if not camera or next(entries) == nil then
		return
	end
	local now = Workspace:GetServerTimeNow()
	local yaw = Mountain.hutYaw(now)
	local lair = Config.JagaLair
	local garden = Vector3.new(lair.centerX, 0, lair.centerZ)
	local watchingGarden = Mountain.hutWatching(now, garden)
	for model, entry in entries do
		if not model.Parent then
			entries[model] = nil
			continue
		end
		-- Bez części Pivot (oś nogi) nie obracamy: PivotTo liczyłby od złego punktu
		if not model.PrimaryPart or (entry.center - camera.CFrame.Position).Magnitude > FAR then
			continue
		end
		if #entry.glows == 0 then
			entry.glows = collectGlows(model)
		end
		-- Obrót wokół osi nogi (część Pivot stoi w środku stopy, w punkcie Center)
		model:PivotTo(CFrame.new(entry.center) * CFrame.Angles(0, yaw, 0))
		for _, part in entry.glows do
			local shaft = part:FindFirstChildWhichIsA("Beam")
			if shaft then
				shaft.Color = if watchingGarden then SHAFT_WATCH else SHAFT_CALM
				shaft.Transparency = if watchingGarden then SHAFT_FADE_WATCH else SHAFT_FADE_CALM
			else
				part.Transparency = if watchingGarden then WINDOW_WATCH else WINDOW_CALM
			end
		end
	end
	-- Gracz w ogródku, a chatka patrzy: ostrzeżenie (nie częściej niż co kilka sekund)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local offset = Vector3.new(root.Position.X - garden.X, 0, root.Position.Z - garden.Z)
		if offset.Magnitude < lair.radius and Mountain.hutWatching(now, root.Position) and os.clock() - lastWarn > 6 then
			lastWarn = os.clock()
			Hud.toast(Localize.t("MSG_HUT_WATCHING"), "warn")
		end
	end
end)

return JagaHutView
