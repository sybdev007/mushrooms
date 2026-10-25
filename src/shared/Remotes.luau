--!strict
-- Jedno miejsce z nazwami wszystkich RemoteEventów.
-- Serwer je tworzy, klient na nie czeka.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	-- serwer -> klient
	"StateUpdate", -- stan gracza: monety, olej, koszyk, poziomy ulepszeń
	"MushroomSync", -- lista grzybów, które właśnie pojawiły się dla tego gracza
	"MushroomRemoved", -- grzyb zebrany (zniknął)
	"Notify", -- komunikat do pokazania na ekranie
	-- klient -> serwer
	"PickMushroom",
	"SellBasket",
	"BuyUpgrade",
	"DevAction", -- panel DEV (serwer sprawdza, czy gracz jest deweloperem)
}

local folder: Folder
if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
	end
	for _, name in NAMES do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

local Remotes = {}

function Remotes.get(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

return Remotes
