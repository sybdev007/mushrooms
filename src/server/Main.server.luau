--!strict
-- Punkt startowy serwera: zbuduj mapę, potem odpal pętlę gry.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- Postacie dopiero na gotową mapę. Budowa po drodze czeka (np. na modele z siatek), a gracz, który wszedł
-- w tym czasie, dostawał postać w powietrzu (0, 100, 0), bo punktu startu jeszcze nie było, i spadał.
Players.CharacterAutoLoads = false

local MapBuilder = require(script.Parent.MapBuilder)
local GameService = require(script.Parent.GameService)

local map = MapBuilder.build()
GameService.start(map)
Players.CharacterAutoLoads = true
for _, player in Players:GetPlayers() do
	if player.Character then
		player.Character:PivotTo(map.spawnCFrame) -- postać sprzed budowy: na punkt startu
	else
		task.spawn(function()
			player:LoadCharacter()
		end)
	end
end
-- Ekran wczytywania klienta (ReplicatedFirst/LoadingScreen) czeka na ten znak
Workspace:SetAttribute("MapReady", true)

print(string.format("[LanternForager] Serwer gotowy, miejsc na grzyby: %d", #map.spots))
