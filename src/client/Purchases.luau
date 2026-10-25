--!strict
-- Zakupy za Robuxy po stronie gracza: okno płatności Robloxa i ceny produktów.
-- Produkt bez numeru (id = 0 w Config.Products) w Studio „kupuje się” za darmo, żeby dało się
-- testować; w prawdziwej grze takie przyciski są ukryte.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Purchases = {}

local StudioPurchase = Remotes.get("StudioPurchase")
local prices: { [string]: number } = {}

-- Czy produkt da się kupić (ma numer albo jesteśmy w Studio)
function Purchases.available(key: string): boolean
	local def = Config.Products[key]
	return def ~= nil and (def.id ~= 0 or RunService:IsStudio())
end

-- Cena do pokazania na przycisku: "49" (R$) albo "TEST" w Studio bez numeru produktu
function Purchases.priceText(key: string): string
	local def = Config.Products[key]
	if not def or def.id == 0 then
		return "TEST"
	end
	local price = prices[key]
	if price then
		return utf8.char(0xE002) .. " " .. tostring(price) -- ikonka Robuxa z czcionki Robloxa
	end
	return "R$"
end

function Purchases.buy(key: string)
	local def = Config.Products[key]
	if not def then
		return
	end
	if def.id ~= 0 then
		MarketplaceService:PromptProductPurchase(Players.LocalPlayer, def.id)
	elseif RunService:IsStudio() then
		StudioPurchase:FireServer(key)
	end
end

-- Ceny pobieramy raz, w tle (GetProductInfo czeka na sieć)
task.spawn(function()
	for key, def in Config.Products do
		if def.id ~= 0 then
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(def.id, Enum.InfoType.Product)
			end)
			if ok and info and typeof(info.PriceInRobux) == "number" then
				prices[key] = info.PriceInRobux
			end
		end
	end
end)

return Purchases
