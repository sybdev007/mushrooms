--!strict
-- Granie ze znajomymi (czysta logika, testy w Lune; CommunityService robi resztę):
--   zaliczanie zaproszeń — gracz, który wszedł z czyjegoś zaproszenia (GetJoinData().ReferredByPlayerId),
--   liczy się zapraszającemu raz na zawsze (lista UserId w danych, z limitem). Licznik stats.invites
--   daje tytuł „Przewodnik”.

local Social = {}

Social.MAX_INVITED = 20 -- więcej nie trzeba pamiętać: tytuł jest za 3

-- Dopisuje zaproszonego, jeśli to ktoś nowy (nie sam zapraszający, nie po raz drugi, w limicie).
-- true = zaliczone (licznik +1).
function Social.creditInvite(invited: { number }, invitedId: number, referrerId: number): boolean
	if invitedId <= 0 or invitedId == referrerId or table.find(invited, invitedId) then
		return false
	end
	if #invited >= Social.MAX_INVITED then
		return false
	end
	table.insert(invited, invitedId)
	return true
end

-- Numer zapraszającego z danych wejścia (nil, gdy gracz wszedł sam)
function Social.referrer(joinData: any): number?
	if typeof(joinData) ~= "table" then
		return nil
	end
	local id = joinData.ReferredByPlayerId
	if typeof(id) == "number" and id > 0 and id == math.floor(id) then
		return id
	end
	return nil
end

return Social
