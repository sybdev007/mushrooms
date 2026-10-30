--!strict
-- Kolejka wyników do rankingu (UserId → najwyższy czekający wynik) z jednym workerem.
-- Czysty kod bez API Robloxa (testy w Lune):
--   push   — scala wynik (maksimum) i nic nie wysyła,
--   flush  — jeśli worker już działa, tylko zgłasza „jeszcze raz” i wraca; inaczej wysyła po kolei.
--            W danej chwili najwyżej jeden zapis na raz, więc spiętrzone wywołania nie mnożą żądań.
--   Błąd jednego wpisu nie blokuje następnych; wpis zostaje w kolejce do następnego flush.
--   Po udanym zapisie znika tylko wysłana wersja: nowszy wynik dodany w trakcie zostaje.

local ScoreQueue = {}

export type Result = "ok" | "retry" | "stop" -- stop = magazyn niedostępny (np. 403), przerwij przebieg
export type Queue = {
	push: (userId: number, score: number) -> (),
	flush: () -> (),
	remove: (userId: number) -> (),
	clear: () -> (),
	waiting: (userId: number) -> number?,
	busy: () -> boolean,
}

function ScoreQueue.new(write: (userId: number, score: number) -> Result, allowed: (userId: number) -> boolean): Queue
	local pending: { [number]: number } = {}
	local published: { [number]: number } = {}
	local running = false
	local again = false

	local function pass()
		for userId in table.clone(pending) do
			local score = pending[userId]
			if score == nil then
				continue -- usunięty w trakcie (moderacja)
			end
			if not allowed(userId) then
				pending[userId] = nil
				continue
			end
			local result = write(userId, score)
			if result == "ok" then
				published[userId] = math.max(published[userId] or 0, score)
				if pending[userId] == score then
					pending[userId] = nil
				end
			elseif result == "stop" then
				return
			end
		end
	end

	local queue = {} :: Queue

	function queue.push(userId: number, score: number)
		if score > 0 and score > (published[userId] or 0) then
			pending[userId] = math.max(pending[userId] or 0, score)
		end
	end

	function queue.flush()
		if running then
			again = true
			return
		end
		running = true
		local ok, err = pcall(function()
			repeat
				again = false
				pass()
			until not again
		end)
		running = false
		if not ok then
			warn("[ScoreQueue]", err)
		end
	end

	function queue.remove(userId: number)
		pending[userId] = nil
	end

	function queue.clear()
		table.clear(pending)
	end

	function queue.waiting(userId: number): number?
		return pending[userId]
	end

	function queue.busy(): boolean
		return running
	end

	return queue
end

return ScoreQueue
