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
	"ProgressUpdate", -- Grzybopedia, zadania, seria logowań (ProgressService)
	"GardenView", -- stan grządek dla okna sadzenia (i czy je otworzyć)
	"CauldronResult", -- Halloween: co wypadło z kotła (okienko i dźwięk u gracza)
	"GiftResult", -- Zima: co wypadło z choinki (okienko i dźwięk u gracza)
	"ChestOffer", -- x2 skrzyni: okno „Witaj z powrotem”, karta po odbiorze, zakup po G, wypłata premii
	"AnnounceShow", -- ogłoszenie admina na środku ekranu (ze wszystkich serwerów, MessagingService)
	"DelveState", -- ekspedycja: zlecenia na tablicy, ekipa, postęp w komorach, kolekcja reliktów (i które okno otworzyć)
	-- klient -> serwer
	"PickMushroom",
	"SellBasket",
	"BuyUpgrade",
	"DevAction", -- panel DEV (serwer sprawdza, czy gracz jest deweloperem)
	"StudioPurchase", -- zakup produktu bez numeru (id = 0), działa tylko w Studio
	"QuestReroll", -- wymiana jednego zadania dziennie
	"QuestClaim", -- odbierz nagrodę: numer zadania, "bonus" (komplet) albo "login" (seria logowań)
	"SaveSettings", -- przyciski wyciszenia muzyki i dźwięków (zapisywane w danych gracza)
	"SelectTitle", -- wybór tytułu nad głową ("" = najlepszy automatycznie, "none" = bez tytułu)
	"TutorialStep", -- klient: skończyłem krok samouczka (serwer sprawdza, czy może przejść dalej)
	"GardenPlant", -- posadź grzyb z koszyka na wybranej grządce (przy zamianie stary wraca do koszyka)
	"GardenAuto", -- posadź najlepsze automatycznie
	"EquipSkin", -- skórki z eventów: załóż / zdejmij skórkę latarni albo nożyka (slot, id; "" = zwykła)
	"AdventOpen", -- Zima: otwórz dzisiejsze okienko kalendarza adwentowego
	"ChestClaim", -- x2 skrzyni: klient gotowy na okno powrotu / odbierz z okna powrotu (x2 = też kup)
	"AdminAnnounce", -- panel DEV: wyślij ogłoszenie na wszystkie serwery (serwer sprawdza dewelopera i filtruje tekst)
	"DelveAction", -- ekspedycja: weź / dołącz / opuść zlecenie, renowacja, oprawa, składanie reliktu
	"OwlCheck", -- gracz zamknął okno dołączenia do grupy Old Owl Studios: sprawdź członkostwo jeszcze raz
	"ForgeView", -- Kuźnia Grzybów: dostęp do przepisów, kolekcja, wynik połączenia (i czy otworzyć okno)
	"ForgeAction", -- Kuźnia Grzybów: połącz 3 grzyby z koszyka według przepisu
	"ShowcaseView", -- gablota w ogródku: miejsca, wystawy, co można wystawić (i czy otworzyć okno)
	"ShowcaseAction", -- gablota: kup miejsce, wystaw, zdejmij
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
