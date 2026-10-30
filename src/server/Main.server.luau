--!strict
-- Punkt startowy serwera: zbuduj mapę, potem odpal pętlę gry.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- Postacie dopiero na gotową mapę. Budowa po drodze czeka (np. na modele z siatek), a gracz, który wszedł
-- w tym czasie, dostawał postać w powietrzu (0, 100, 0), bo punktu startu jeszcze nie było, i spadał.
Players.CharacterAutoLoads = false

-- Punkt startu w chatce od pierwszej chwili: niewidzialna platforma w miejscu, gdzie potem stoi podłoga.
-- Gdyby ktoś mimo wszystko dostał postać przed końcem budowy, stanie na niej, a nie spadnie z nieba.
-- Leży w folderze (MapBuilder usuwa tylko punkty startu leżące luzem w Workspace, z szablonu Baseplate).
local earlyFolder = Instance.new("Folder")
earlyFolder.Name = "EarlySpawn"
local early = Instance.new("SpawnLocation")
early.Name = "EarlySpawn"
early.Anchored = true
early.Neutral = true
early.Duration = 0
early.Size = Vector3.new(6, 1, 6)
early.CFrame = CFrame.new(0, 0.5, -20) -- środek chatki (Cabin.build: start na z = -20, podłoga na y = 1)
early.Transparency = 1
early.CanTouch = false
early.Parent = earlyFolder
earlyFolder.Parent = Workspace

local MapBuilder = require(script.Parent.MapBuilder)
local GameService = require(script.Parent.GameService)

local map = MapBuilder.build()
GameService.start(map)
Players.CharacterAutoLoads = true
earlyFolder:Destroy() -- mapa ma już swój punkt startu (SpawnPoint w chatce)
for _, player in Players:GetPlayers() do
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character and humanoid and humanoid.Health > 0 then
		character:PivotTo(map.spawnCFrame) -- postać sprzed budowy: na punkt startu
	else
		-- Bez postaci albo zginęła w trakcie budowy (przy wyłączonym CharacterAutoLoads nikt by jej nie wskrzesił)
		task.spawn(function()
			player:LoadCharacter()
		end)
	end
end
-- Ekran wczytywania klienta (ReplicatedFirst/LoadingScreen) czeka na ten znak
Workspace:SetAttribute("MapReady", true)

print(string.format("[LanternForager] Serwer gotowy, miejsc na grzyby: %d", #map.spots))
