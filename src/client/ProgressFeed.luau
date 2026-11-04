--!strict
-- Jedno podłączenie do ProgressUpdate dla wszystkich okien (Halloween, Zima, Zadania, Grzybopedia, Tytuły).
--
-- Po co: serwer wysyła stan okien raz przy wejściu (potem tylko po zmianie). Jeśli przyjdzie, zanim
-- klient podłączy jakikolwiek odbiornik, Roblox trzyma go w kolejce i oddaje TYLKO pierwszemu
-- podłączonemu odbiornikowi. Gdy każde okno miało własne podłączenie, stan dostawało okno Halloween,
-- a Zadania, Grzybopedia i Tytuły zostawały puste z napisami „Label” (zwłaszcza przy pierwszym wejściu
-- na świeży serwer, gdy klient dłużej się wczytuje). Tu jest jedno podłączenie, które pamięta ostatni
-- stan i oddaje go każdemu oknu, także temu, które zapisze się później.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local ProgressFeed = {}

local last: any = nil
local listeners: { (any) -> () } = {}

Remotes.get("ProgressUpdate").OnClientEvent:Connect(function(payload: any)
	last = payload
	for _, listener in listeners do
		task.spawn(listener, payload) -- błąd w jednym oknie nie zatrzymuje pozostałych
	end
end)

-- Okno zapisuje się na stan; jeśli stan już przyszedł, dostaje go od razu
function ProgressFeed.subscribe(listener: (any) -> ())
	table.insert(listeners, listener)
	if last ~= nil then
		task.spawn(listener, last)
	end
end

return ProgressFeed
