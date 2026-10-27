--!strict
-- Samouczek po stronie serwera: pilnuje kroków (Config.Tutorial), stawia grzyby samouczka przy ścieżce
-- (tylko dla tego gracza, id "tut_N") i przesuwa gracza dalej, gdy naprawdę coś zrobił:
--   1 zbieranie → plecak pełny (wtedy olej spada nisko, ale tak, żeby na pewno wystarczył na powrót)
--   2 sprzedaż → koszyk sprzedany (dopłacamy brakujące monety do pierwszego ulepszenia oleju)
--   3 ulepszenie oleju → wolno kupić tylko je
--   4 zebranie grzybów do ogródka → 5 sadzenie → 6 kradzież (cutscenka u klienta) → koniec i nagroda
-- Klient sam może zgłosić tylko koniec cutscenek (0 → 1 i 6 → koniec).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local TutorialService = {}

local DONE = Config.Tutorial.done

export type Session = {
	player: Player,
	data: any,
	oil: number,
	tutorialSpots: { [string]: Vector3 }?,
}

export type Api = {
	pushState: (Session) -> (),
	notify: (Session, string, { any }?) -> (),
	basketMax: (Session) -> number,
	stat: (Session, string) -> number,
	rootOf: (Player) -> BasePart?,
}

local api: Api
local MushroomSync = Remotes.get("MushroomSync")
local MushroomRemoved = Remotes.get("MushroomRemoved")

local function spawnSpots(session: Session, prefix: string, list: { { number } })
	local spots = session.tutorialSpots or {}
	session.tutorialSpots = spots
	local sync = {}
	for i, xz in list do
		local id = prefix .. i
		local position = Vector3.new(xz[1], 0, xz[2])
		spots[id] = position
		table.insert(sync, { id = id, position = position, species = Config.Tutorial.species })
	end
	MushroomSync:FireClient(session.player, sync)
end

local function clearSpots(session: Session)
	for id in session.tutorialSpots or {} do
		MushroomRemoved:FireClient(session.player, id)
	end
	session.tutorialSpots = {}
end

-- Grzyby dla kroku, w którym gracz właśnie jest (np. po ponownym wejściu do gry)
local function spawnForStep(session: Session)
	local step = session.data.tutorial
	if step == 1 then
		-- Ile jeszcze brakuje do pełnego plecaka
		local missing = math.max(0, api.basketMax(session) - #session.data.basket)
		local list = {}
		for i = 1, math.min(missing, #Config.Tutorial.spots) do
			table.insert(list, Config.Tutorial.spots[i])
		end
		spawnSpots(session, "tut_", list)
	elseif step == 4 then
		spawnSpots(session, "tutg_", Config.Tutorial.gardenSpots)
	end
end

function TutorialService.setStep(session: Session, step: number)
	local data = session.data
	if data.tutorial == step then
		return
	end
	data.tutorial = step
	clearSpots(session)
	if step == 2 then
		-- Plecak pełny: olej spada nisko (ostrzeżenie), ale zostaje go na powrót do chatki
		session.oil = math.min(session.oil, Config.Tutorial.lowOil)
	elseif step == 3 then
		-- Gwarancja, że stać na pierwsze ulepszenie oleju
		local cost = Economy.upgradeCost(Config.Tutorial.upgrade, data.upgrades[Config.Tutorial.upgrade] or 0)
		if not cost then
			-- Zbiornik już na maksa (np. samouczek od nowa na starym koncie): ten krok nie ma sensu.
			-- Olej i tak się napełnia, jak po zakupie ulepszenia.
			session.oil = api.stat(session, "oil")
			TutorialService.setStep(session, 4)
			return
		end
		data.coins = math.max(data.coins, cost)
	elseif step == DONE then
		data.coins += Config.Tutorial.reward
		api.notify(session, "TUT_DONE_MSG", { Config.Tutorial.reward })
	end
	spawnForStep(session)
	api.pushState(session)
end

function TutorialService.onJoin(session: Session)
	session.tutorialSpots = {}
	spawnForStep(session)
end

function TutorialService.isTutorialSpot(spotId: string): boolean
	return string.sub(spotId, 1, 4) == "tut_" or string.sub(spotId, 1, 5) == "tutg_"
end

-- Zerwanie grzyba samouczka. Zwraca true, gdy to był grzyb samouczka (wtedy zwykła ścieżka nie działa).
function TutorialService.pick(session: Session, spotId: string): boolean
	if not TutorialService.isTutorialSpot(spotId) then
		return false
	end
	local spots = session.tutorialSpots
	local position = spots and spots[spotId]
	if not spots or not position then
		return true
	end
	local root = api.rootOf(session.player)
	if not root then
		return true
	end
	local offset = root.Position - position
	if Vector3.new(offset.X, 0, offset.Z).Magnitude > Config.PickRadiusServer then
		return true
	end
	local basket = session.data.basket
	if #basket >= api.basketMax(session) then
		api.notify(session, "MSG_BASKET_FULL")
		return true
	end
	spots[spotId] = nil
	table.insert(basket, { s = Config.Tutorial.species })
	MushroomRemoved:FireClient(session.player, spotId)
	local step = session.data.tutorial
	if step == 1 and (#basket >= api.basketMax(session) or next(spots) == nil) then
		TutorialService.setStep(session, 2)
	elseif step == 4 and next(spots) == nil then
		TutorialService.setStep(session, 5)
	else
		api.pushState(session)
	end
	return true
end

function TutorialService.onSold(session: Session)
	if session.data.tutorial == 2 and #session.data.basket == 0 then
		TutorialService.setStep(session, 3)
	end
end

-- W kroku 3 można kliknąć tylko ulepszenie oleju
function TutorialService.canBuy(session: Session, upgradeId: string): boolean
	return session.data.tutorial ~= 3 or upgradeId == Config.Tutorial.upgrade
end

function TutorialService.onBought(session: Session, upgradeId: string)
	if session.data.tutorial == 3 and upgradeId == Config.Tutorial.upgrade then
		TutorialService.setStep(session, 4)
	end
end

-- Zdarzenia z ogródka ("plant", "collect", "steal")
function TutorialService.event(session: Session, kind: string)
	if kind == "plant" and session.data.tutorial == 5 then
		TutorialService.setStep(session, 6)
	end
end

-- Kroki, które kończy sam klient (cutscenki)
function TutorialService.clientStep(session: Session, step: number)
	local current = session.data.tutorial
	if current == 0 and step == 1 then
		TutorialService.setStep(session, 1)
	elseif current == 6 and step == DONE then
		TutorialService.setStep(session, DONE)
	end
end

-- Panel DEV: samouczek od nowa (z pustym koszykiem, żeby dało się go przejść)
function TutorialService.reset(session: Session)
	table.clear(session.data.basket)
	session.data.tutorial = -1
	TutorialService.setStep(session, 0)
end

function TutorialService.start(serviceApi: Api)
	api = serviceApi
end

return TutorialService
