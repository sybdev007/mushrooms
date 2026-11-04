--!strict
-- Zdarzenia do panelu analityki Robloxa (Creator Hub → Analytics), żeby widzieć, gdzie gracze odpadają
-- i skąd biorą się / na co idą monety. Każde wywołanie w pcall: analityka nigdy nie psuje gry.
--   lejek samouczka: Analytics.onboarding (kroki 1..8, LogOnboardingFunnelStepEvent)
--   kamienie milowe: Analytics.milestone („Milestone_FirstSale” itd., wartość = minuty od wejścia)
--   monety: Analytics.coins (LogEconomyEvent, waluta „Coins”, typ transakcji jak w
--     Enum.AnalyticsEconomyTransactionType: Gameplay, TimedReward, Onboarding, Shop, IAP)
-- Limity Robloxa: 20 typów transakcji, 100 SKU, 100 nazw własnych zdarzeń — trzymamy się małej listy.

local AnalyticsService = game:GetService("AnalyticsService")

local Analytics = {}

local CURRENCY = "Coins"

-- Kroki lejka samouczka (numer = krok w Creator Hub). Data.tutorial: 0 intro, 1 zbieranie, 2 sprzedaż,
-- 3 ulepszenie, 4 grzyby do ogródka, 5 sadzenie, 6 kradzież (cutscenka), Config.Tutorial.done koniec.
Analytics.ONBOARDING = {
	{ tutorial = 0, name = "Joined" },
	{ tutorial = 1, name = "Picking" },
	{ tutorial = 2, name = "Selling" },
	{ tutorial = 3, name = "Upgrading" },
	{ tutorial = 4, name = "GardenPicking" },
	{ tutorial = 5, name = "Planting" },
	{ tutorial = 6, name = "Theft" },
	{ tutorial = 100, name = "Done" },
}

local warned = false
local function safe(fn: () -> ())
	local ok, err: any = pcall(fn)
	if not ok and not warned then
		warned = true
		warn("[Analytics] " .. tostring(err))
	end
end

-- Gracz doszedł do kroku samouczka (wartość data.tutorial)
function Analytics.onboarding(player: Player, tutorialStep: number)
	for index, step in Analytics.ONBOARDING do
		if step.tutorial == tutorialStep then
			safe(function()
				AnalyticsService:LogOnboardingFunnelStepEvent(player, index, step.name)
			end)
			return
		end
	end
end

-- Pierwsza sprzedaż, pierwsze ulepszenie, pierwsza śmierć, otwarcie świata... (raz na konto: o tym,
-- czy to pierwszy raz, decyduje wywołujący na podstawie zapisu)
function Analytics.milestone(player: Player, name: string, minutes: number?)
	safe(function()
		AnalyticsService:LogCustomEvent(player, "Milestone_" .. name, minutes)
	end)
end

-- Monety: flow "source" (przychód) albo "sink" (wydatek), kwota zawsze dodatnia
function Analytics.coins(player: Player, flow: string, amount: number, balance: number, transaction: string, sku: string?)
	if amount <= 0 then
		return
	end
	safe(function()
		AnalyticsService:LogEconomyEvent(
			player,
			if flow == "sink" then Enum.AnalyticsEconomyFlowType.Sink else Enum.AnalyticsEconomyFlowType.Source,
			CURRENCY,
			amount,
			math.max(0, balance),
			transaction,
			sku or ""
		)
	end)
end

return Analytics
