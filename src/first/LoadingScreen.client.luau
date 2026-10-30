--!strict
-- Własny ekran wczytywania zamiast domyślnego Robloxa. To pierwszy skrypt klienta (ReplicatedFirst).
--
-- Po co: gra ma StreamingEnabled, więc świat dochodzi do klienta kawałkami i postać potrafiła spaść
-- przez podłogę chatki, zanim ta się wczytała. Ekran zasłania wczytywanie, trzyma postać w miejscu
-- (kotwica tylko u tego klienta) aż pod nogami jest grunt, i dopiero potem oddaje grę.
--
-- Pasek liczy prawdziwe etapy (każdy ma swoją wagę):
--   connect  dane gry dotarły (game.Loaded)
--   world    mapa gotowa na serwerze (atrybut Workspace "MapReady"), postać jest, świat wokół niej
--            wczytany (RequestStreamAroundAsync), pod nogami jest grunt
--   assets   arkusze ikon i grzybków oraz krótkie dźwięki (ContentProvider:PreloadAsync)
--   save     zapis gracza wczytany: Main.client ustawia atrybut "IntroPending" po pierwszym stanie
-- Etapy o nieznanym czasie powoli „pełzną”, żeby pasek nie stał w miejscu.
--
-- Koniec: atrybut gracza "Loaded" = true. Nowy gracz (będzie intro) dostaje czarny ekran, z którego
-- startuje IntroCutscene (Main.client czeka na "Loaded"); reszta widzi grę po krótkim ściemnieniu.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local LoadingUI = require(script.Parent:WaitForChild("LoadingUI"))

local player = Players.LocalPlayer

local MIN_TIME = 2.5 -- krócej ekran tylko by mignął
local MAX_TIME = 45 -- awaryjnie: po tym czasie gra rusza mimo braków

local function setCoreGui(enabled: boolean)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, enabled)
	end)
end

local okUi, created = pcall(LoadingUI.new)
if not okUi then
	-- Bez ekranu gra i tak musi ruszyć (intro czeka na "Loaded")
	warn("[LoadingScreen] " .. tostring(created))
	player:SetAttribute("Loaded", true)
	return
end
local ui: LoadingUI.Handle = created
ReplicatedFirst:RemoveDefaultLoadingScreen()
setCoreGui(false)

-- ===== Postać stoi w miejscu, dopóki nie ma pod nią świata =====
local finished = false
local frozen: { BasePart } = {}

local function freeze(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if root and root:IsA("BasePart") and not finished then
		root.Anchored = true
		table.insert(frozen, root)
	end
end

local function unfreeze()
	finished = true
	for _, root in frozen do
		if root.Parent then
			root.Anchored = false
		end
	end
	table.clear(frozen)
end

local characterConnection = player.CharacterAdded:Connect(freeze)
if player.Character then
	task.spawn(freeze, player.Character)
end

-- ===== Etapy =====
type Stage = { weight: number, progress: number, done: boolean }
local stages: { [string]: Stage } = {
	connect = { weight = 0.25, progress = 0, done = false },
	world = { weight = 0.35, progress = 0, done = false },
	assets = { weight = 0.25, progress = 0, done = false },
	save = { weight = 0.15, progress = 0, done = false },
}
local ORDER = { "connect", "world", "assets", "save" }
local started = os.clock()

local function waitGameLoaded()
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
end

local function advance(stage: Stage, progress: number)
	stage.progress = math.max(stage.progress, progress)
end

task.spawn(function()
	waitGameLoaded()
	stages.connect.done = true
end)

task.spawn(function()
	local stage = stages.world
	waitGameLoaded()
	-- Serwer buduje mapę na starcie i daje znać atrybutem (Main.server)
	local t0 = os.clock()
	while Workspace:GetAttribute("MapReady") ~= true and os.clock() - t0 < 20 do
		task.wait(0.1)
	end
	advance(stage, 0.3)
	local character = player.Character or player.CharacterAdded:Wait()
	local root = character:WaitForChild("HumanoidRootPart", 15)
	advance(stage, 0.45)
	if root and root:IsA("BasePart") then
		-- StreamingEnabled: świat wokół postaci (chatka) musi dojść, zanim postać dostanie fizykę
		pcall(function()
			player:RequestStreamAroundAsync(root.Position, 15)
		end)
		advance(stage, 0.75)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.RespectCanCollide = true
		local t1 = os.clock()
		while os.clock() - t1 < 15 do
			local current = player.Character
			local currentRoot = current and current:FindFirstChild("HumanoidRootPart")
			if current and currentRoot and currentRoot:IsA("BasePart") then
				params.FilterDescendantsInstances = { current }
				if Workspace:Raycast(currentRoot.Position, Vector3.new(0, -60, 0), params) then
					break
				end
			end
			task.wait(0.15)
		end
	end
	stage.done = true
end)

task.spawn(function()
	local stage = stages.assets
	waitGameLoaded()
	-- Obrazki jako numer, dźwięki jako obiekt Sound (sam numer PreloadAsync bierze za obrazek
	-- i sypie błędami „Asset type does not match”)
	local list: { any } = {}
	local seen: { [string]: boolean } = {}
	local function add(id: any)
		if type(id) == "string" and id ~= "" and not seen[id] then
			seen[id] = true
			table.insert(list, id)
		end
	end
	local function addSound(id: any)
		if type(id) == "string" and id ~= "" and not seen[id] then
			seen[id] = true
			local sound = Instance.new("Sound")
			sound.SoundId = id
			table.insert(list, sound)
		end
	end
	local sharedFolder = ReplicatedStorage:WaitForChild("Shared", 15)
	local configModule = sharedFolder and sharedFolder:WaitForChild("Config", 15)
	if configModule and configModule:IsA("ModuleScript") then
		local ok, config = pcall(require, configModule)
		if ok and type(config) == "table" then
			local Config = config :: any
			for _, key in { "UiIcons", "UiIcons2", "MushroomSprites" } do
				local def = Config[key]
				if type(def) == "table" then
					add(def.sheet)
				end
			end
			if type(Config.VoxelNoise) == "table" then
				add(Config.VoxelNoise.texture)
			end
			local audio = Config.Audio
			if type(audio) == "table" and type(audio.sfx) == "table" then
				for _, id in audio.sfx do
					addSound(id)
				end
			end
		end
	end
	if #list == 0 then
		stage.done = true
		return
	end
	-- Wolne łącze nie trzyma całej gry przez jeden dźwięk: reszta dociągnie się w tle
	task.delay(12, function()
		stage.done = true
	end)
	local loaded = 0
	pcall(function()
		ContentProvider:PreloadAsync(list, function()
			loaded += 1
			advance(stage, loaded / #list)
		end)
	end)
	stage.done = true
end)

task.spawn(function()
	local stage = stages.save
	local t0 = os.clock()
	while player:GetAttribute("IntroPending") == nil and os.clock() - t0 < 30 do
		task.wait(0.1)
	end
	stage.done = true
end)

-- ===== Pasek =====
local function creep(stage: Stage, tau: number)
	if not stage.done then
		advance(stage, 0.85 * (1 - math.exp(-(os.clock() - started) / tau)))
	end
end

local function run()
	local shownStage = ""
	while true do
		creep(stages.connect, 2.5)
		creep(stages.world, 5)
		creep(stages.save, 4)
		local total = 0
		local allDone = true
		for _, id in ORDER do
			local stage = stages[id]
			total += stage.weight * (if stage.done then 1 else math.clamp(stage.progress, 0, 1))
			allDone = allDone and stage.done
		end
		ui.setTarget(math.min(total, 0.98))
		for _, id in ORDER do
			if not stages[id].done then
				if shownStage ~= id then
					shownStage = id
					ui.setStage(id)
				end
				break
			end
		end
		local elapsed = os.clock() - started
		if (allDone and elapsed >= MIN_TIME) or elapsed >= MAX_TIME then
			if not allDone then
				warn("[LoadingScreen] koniec czasu, nie doszły etapy:", stages.connect.done, stages.world.done, stages.assets.done, stages.save.done)
			end
			break
		end
		task.wait(0.05)
	end

	ui.complete()
	characterConnection:Disconnect()

	if player:GetAttribute("IntroPending") == true then
		-- Nowy gracz: ekran zostaje czarny, intro startuje z własnej czerni (CutsceneKit, gui „Cutscene”)
		ui.fadeOut(true, function()
			unfreeze()
			player:SetAttribute("Loaded", true)
		end)
		local playerGui = player:WaitForChild("PlayerGui")
		local t0 = os.clock()
		while not playerGui:FindFirstChild("Cutscene") and os.clock() - t0 < 6 do
			task.wait(0.05)
		end
		if not playerGui:FindFirstChild("Cutscene") then
			setCoreGui(true) -- intro nie ruszyło: oddajemy grę jak zwykle
		end
		ui.destroy()
	else
		ui.fadeOut(false, function()
			unfreeze()
			setCoreGui(true)
			player:SetAttribute("Loaded", true)
		end)
	end
end

local ok, err = pcall(run)
if not ok then
	warn("[LoadingScreen] " .. tostring(err))
	unfreeze()
	setCoreGui(true)
	player:SetAttribute("Loaded", true)
	ui.destroy()
end
