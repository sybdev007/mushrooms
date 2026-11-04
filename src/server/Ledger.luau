--!strict
-- Jedno miejsce na monety z gry: przychód podnosi też data.earned (ranking „najbogatsi” liczy monety
-- zarobione w ogóle, więc wydawanie w kuźni czy na relikty nie spycha gracza w dół tablicy), a każdy
-- ruch trafia do analityki (Analytics.coins). Monety z panelu DEV omijają Ledger.
-- Typy transakcji (Enum.AnalyticsEconomyTransactionType): Gameplay, TimedReward, Onboarding, Shop, IAP.

local Analytics = require(script.Parent.Analytics)

local Ledger = {}

export type Wallet = { coins: number, earned: number }

-- Przychód: dodaje monety i liczy je do zarobionych
function Ledger.earn(player: Player, data: Wallet, amount: number, transaction: string, sku: string?)
	local value = math.floor(amount)
	if value <= 0 then
		return
	end
	data.coins += value
	data.earned += value
	Analytics.coins(player, "source", value, data.coins, transaction, sku)
end

-- Wydatek: zabiera monety (wywołujący sprawdził, że stać)
function Ledger.spend(player: Player, data: Wallet, amount: number, transaction: string, sku: string?)
	local value = math.floor(amount)
	if value <= 0 then
		return
	end
	data.coins -= value
	Analytics.coins(player, "sink", value, data.coins, transaction, sku)
end

-- Wydatek już odjęty gdzie indziej (np. Economy.buyUpgrade): tylko analityka
function Ledger.spent(player: Player, data: Wallet, amount: number, transaction: string, sku: string?)
	Analytics.coins(player, "sink", math.floor(amount), data.coins, transaction, sku)
end

return Ledger
