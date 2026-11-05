--!strict
-- Ofiara dla Leszego: czysta logika (testy w Lune). Liczby w Config.Shrine.
-- Suma wpłat żyje w data.stats.leszyOffered (Titles liczy z niej tytuły), wszystko inne wyliczamy z niej:
-- następny próg, obwódkę tabliczki ogródka, kamienie milowe analityki. Bez tokenów: gracz potwierdza
-- w oknie, a serwer sprawdza każdą wpłatę od nowa (Shrine.check).

local Config = require(script.Parent.Config)

local Shrine = {}

Shrine.LIMIT = 9007199254740991 -- 2^53 - 1: największa liczba całkowita, którą liczba w Luau trzyma dokładnie
Shrine.TIERS = Config.Shrine.tiers

-- Suma z zapisu: nieujemna, skończona, całkowita, do LIMIT; uszkodzona wartość = 0
function Shrine.readTotal(raw: any): number
	if typeof(raw) ~= "number" or raw ~= raw or raw < 0 or raw > Shrine.LIMIT or raw ~= math.floor(raw) then
		return 0
	end
	return raw
end

-- Kwota wpłaty: liczba w pełnych milionach od jednego miliona do Config.Shrine.maxOffer
function Shrine.validAmount(amount: any): boolean
	local s = Config.Shrine
	return typeof(amount) == "number"
		and amount == amount
		and amount >= s.unit
		and amount <= s.maxOffer
		and amount == math.floor(amount)
		and amount % s.unit == 0
end

export type Request = {
	amount: any, -- z sieci (klient), nic nie zakładamy
	coins: number,
	total: number,
	mountainUnlocked: boolean,
	distance: number?, -- od kapliczki (nil = brak postaci)
	canSave: boolean, -- profil otwarty i zapisywalny
	now: number,
	lastAt: number?, -- ostatnia wpłata tego gracza (os.clock)
}

-- Czy serwer przyjmuje wpłatę. Zwraca true albo false i klucz komunikatu (nil = odmowa bez komunikatu,
-- np. drugie kliknięcie w czasie cooldown).
function Shrine.check(req: Request): (boolean, string?)
	local s = Config.Shrine
	if not req.canSave then
		return false, "LESZY_OFFER_UNAVAILABLE"
	end
	if not req.mountainUnlocked then
		return false, "LESZY_OFFER_LOCKED"
	end
	if req.lastAt and req.now - req.lastAt < s.cooldown then
		return false, nil
	end
	if not req.distance or req.distance > s.reach then
		return false, "LESZY_OFFER_TOO_FAR"
	end
	if not Shrine.validAmount(req.amount) then
		return false, "LESZY_OFFER_LIMIT"
	end
	local amount = req.amount :: number
	if req.coins < amount then
		return false, "LESZY_OFFER_NO_COINS"
	end
	if req.total + amount > Shrine.LIMIT then
		return false, "LESZY_OFFER_UNAVAILABLE"
	end
	return true, nil
end

-- Następny próg (nil = wszystkie zdobyte)
function Shrine.nextGoal(total: number): number?
	for _, tier in Shrine.TIERS do
		if total < tier.goal then
			return tier.goal
		end
	end
	return nil
end

-- Obwódka tabliczki ogródka: najwyższy osiągnięty próg z obwódką (nil = bez)
function Shrine.glow(total: number): string?
	local best: string? = nil
	for _, tier in Shrine.TIERS do
		if total >= tier.goal and tier.glow then
			best = tier.glow
		end
	end
	return best
end

-- Krótka nazwa progu do analityki: 100M, 500M, 1B, 5B, 10B, 20B
function Shrine.label(goal: number): string
	if goal >= 1e9 then
		return string.format("%dB", goal // 1e9)
	end
	return string.format("%dM", goal // 1e6)
end

-- Progi przekroczone tą wpłatą (od before do after), od najniższego
function Shrine.crossed(before: number, after: number): { number }
	local list = {}
	for _, tier in Shrine.TIERS do
		if before < tier.goal and after >= tier.goal then
			table.insert(list, tier.goal)
		end
	end
	return list
end

return Shrine
