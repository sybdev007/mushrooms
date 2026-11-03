--!strict
-- Ekspedycja do Głębokich Komór (plan: docs/plans/cave-expedition.md, logika: Shared/Delve).
-- Serwer prowadzi cały przebieg: zlecenia na tablicy w Obozie, ekipę (solo albo do 4 osób, jawnie przez
-- tablicę), własną kopię komór dla każdej ekspedycji (DelveMap.buildCopy, budowana przy pierwszym użyciu),
-- cel w komorach, ognisko (nagroda raz na osobę, od razu do zapisu), Kryptę ze strażnikiem, osuwiska,
-- spalanie i tankowanie oleju w komorach oraz regał z odnowionymi reliktami w ogródku.
-- Klient dostaje stan przez DelveState i prosi przez DelveAction; nagrody przyznaje tylko serwer.
--
-- Zasady z review (3.11):
--   * olej: własne spalanie w komorach (Delve.drain), haki z olejem, zwykłe ukończenie bez kupowania oleju,
--   * znalezisko i trofeum to nie grzyby: siedzą w stanie ekspedycji i zajmują jedno miejsce w koszyku,
--     nagroda wypłaca się raz (flaga osoby), reconnect jej nie powtórzy; porażka = zwykłe pochłonięcie
--     (koszyk traci jak wszędzie, nie ma darmowego ubezpieczenia),
--   * ekipa ma jedną kopię komór i jeden stan komór; różne ekipy nigdy się nie spotykają.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Delve = require(ReplicatedStorage.Shared.Delve)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local World = script.Parent:WaitForChild("World")
local DelveMap = require(World:WaitForChild("DelveMap"))
local SkarbnikModel = require(World:WaitForChild("Skarbnik"))

local DelveService = {}

export type Api = {
	getData: (Player) -> any,
	notify: (Player, string, { any }?, string?) -> (),
	pushState: (Player) -> (),
	travel: (Player, CFrame, string?) -> (), -- przeniesienie (kończy pościg strażnika)
	campCFrame: () -> CFrame, -- obóz w jaskini
	engulf: (Player, string) -> (), -- złapany / zgasła latarnia (zwykłe zasady koszyka)
	addOil: (Player, number) -> (), -- zmiana oleju o część pełnej latarni (np. -0.15)
	isChased: (Player) -> boolean,
	basketFree: (Player) -> number, -- wolne miejsca w koszyku (bez miejsc zajętych przez ekspedycję)
	event: (Player, string, number?) -> (), -- ProgressService.event (liczniki, tytuły)
	wick: (Player) -> number, -- mnożnik knota jaskini (Kryształowy wkład)
}

type Member = {
	player: Player,
	inside: boolean, -- jest w komorach
	entered: boolean, -- zszedł choć raz
	done: boolean, -- wyszedł / pochłonięty: już nie wraca
	secured: boolean, -- dostał nagrodę za znalezisko
}

type Run = {
	id: number,
	slot: number,
	leader: Player,
	members: { Member },
	offer: Delve.Offer,
	state: string, -- "prepare" | "active"
	createdAt: number,
	startedAt: number,
	progress: number,
	objectiveDone: boolean,
	carrier: Player?, -- kto niesie znalezisko
	findShown: boolean, -- znalezisko leży (komuś zabrakło miejsca w koszyku)
	findAt: Vector3?,
	secured: boolean,
	blockageCleared: boolean,
	chestHide: number,
	cleared: { [number]: boolean },
	searched: { [number]: boolean },
	sampleOn: { [number]: boolean },
	doorOpen: boolean,
	cryptCarrier: Player?,
	cryptTaken: boolean,
	cryptSecured: boolean,
	nextRock: number,
	guardCF: CFrame,
	guardTarget: number,
	guardChase: Player?,
}

local api: Api
local rng = Random.new()
local DelveState = Remotes.get("DelveState")
local DelveAction = Remotes.get("DelveAction")

local entrances: DelveMap.Entrances
local copies: { [number]: DelveMap.Copy } = {}
local guards: { [number]: Model } = {}
local slotRun: { [number]: Run } = {}
local runs: { [number]: Run } = {}
local nextRunId = 0
local offers: { [Player]: { Delve.Offer } } = {}
local lastAction: { [Player]: number } = {}
local gardens: { Model } = {}

local BOARD_DISTANCE = 14
local PROMPT_SLACK = 4 -- serwer jest łagodniejszy od przycisku (opóźnienie sieci)
local GUARD_CATCH = 3

-- ===== Pomocnicze =====

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function today(): number
	return Delve.dayIndex(os.time())
end

local function saveOf(player: Player): Delve.Save?
	local data = api.getData(player)
	return if data then data.delve else nil
end

local function rankPoints(player: Player): number
	local data = api.getData(player)
	if not data then
		return 0
	end
	return (data.stats.delves or 0) + (data.stats.crypts or 0)
end

local function runOf(player: Player): (Run?, Member?)
	for _, run in runs do
		for _, member in run.members do
			if member.player == player and not member.done then
				return run, member
			end
		end
	end
	return nil, nil
end

local function activeMembers(run: Run): { Member }
	local list = {}
	for _, member in run.members do
		if not member.done then
			table.insert(list, member)
		end
	end
	return list
end

local function insideMembers(run: Run): { Member }
	local list = {}
	for _, member in run.members do
		if member.inside and not member.done then
			table.insert(list, member)
		end
	end
	return list
end

-- Lokalne x, z gracza w kopii jego ekspedycji
local function localOf(run: Run, position: Vector3): (number, number)
	local x0, z0 = Delve.slotOrigin(run.slot)
	return position.X - x0, position.Z - z0
end

local function near(player: Player, part: BasePart, distance: number): boolean
	local root = rootOf(player)
	return root ~= nil and (root.Position - part.Position).Magnitude <= distance + PROMPT_SLACK
end

local function copyFor(slot: number): DelveMap.Copy
	local existing = copies[slot]
	if existing then
		return existing
	end
	local folder = Workspace:FindFirstChild("DelveCopies")
	if not folder then
		local created = Instance.new("Folder")
		created.Name = "DelveCopies"
		created.Parent = Workspace
		folder = created
	end
	local copy = DelveMap.buildCopy(folder :: Instance, slot, Random.new(900 + slot))
	copies[slot] = copy
	DelveService.connectCopy(copy)
	return copy
end

local function freeSlot(): number?
	for slot = 1, Delve.SLOTS do
		if not slotRun[slot] then
			return slot
		end
	end
	return nil
end

-- ===== Stan dla klienta =====

local function runPayload(run: Run, player: Player, member: Member?): any
	local names = {}
	for _, m in activeMembers(run) do
		table.insert(names, m.player.DisplayName)
	end
	local kind = Delve.kind(run.offer.kind)
	return {
		id = run.id,
		leader = run.leader.DisplayName,
		isLeader = run.leader == player,
		members = names,
		state = run.state,
		kind = run.offer.kind,
		set = run.offer.set,
		modifier = run.offer.modifier,
		daily = run.offer.daily,
		relic = run.offer.relic,
		progress = run.progress,
		goal = if kind then kind.goal else 1,
		blockageCleared = run.blockageCleared,
		objectiveDone = run.objectiveDone,
		carrying = run.carrier == player,
		carrier = if run.carrier then run.carrier.DisplayName else nil,
		findShown = run.findShown,
		secured = run.secured,
		mySecured = member ~= nil and member.secured,
		inside = member ~= nil and member.inside,
		doorOpen = run.doorOpen,
		cryptTaken = run.cryptTaken,
		cryptCarrying = run.cryptCarrier == player,
		cryptSecured = run.cryptSecured,
		expiresAt = if run.state == "prepare"
			then run.createdAt + Delve.PREPARE_SECONDS
			else run.startedAt + Delve.RUN_SECONDS,
	}
end

local function sendState(player: Player, open: string?)
	local data = api.getData(player)
	if not data then
		return
	end
	local points = rankPoints(player)
	local rank, nextGoal = Delve.rank(points)
	local run, member = runOf(player)
	local open_runs = {}
	for _, other in runs do
		if other.state == "prepare" and other ~= run and #activeMembers(other) < Delve.MAX_PARTY then
			table.insert(open_runs, {
				id = other.id,
				leader = other.leader.DisplayName,
				kind = other.offer.kind,
				modifier = other.offer.modifier,
				count = #activeMembers(other),
			})
		end
	end
	DelveState:FireClient(player, {
		open = open,
		offers = offers[player] or {},
		rank = rank,
		points = points,
		nextGoal = nextGoal,
		save = data.delve,
		today = today(),
		run = if run then runPayload(run, player, member) else nil,
		openRuns = open_runs,
		lanternSeconds = math.floor(Delve.lanternSeconds(api.wick(player))),
		caveUnlocked = data.caveUnlocked == true,
	})
end

local function sendRun(run: Run)
	for _, member in run.members do
		if member.player.Parent then
			sendState(member.player)
		end
	end
end

-- Lista otwartych ekip zmieniła się: odśwież tablicę wszystkim
local function broadcast()
	for _, player in Players:GetPlayers() do
		sendState(player)
	end
end

local function notifyRun(run: Run, key: string, args: { any }?, nameKey: string?)
	for _, member in activeMembers(run) do
		api.notify(member.player, key, args, nameKey)
	end
end

local function makeOffers(player: Player)
	local save = saveOf(player)
	if not save then
		return
	end
	local rank = Delve.rank(rankPoints(player))
	offers[player] = Delve.makeOffers(function()
		return rng:NextNumber()
	end, rank, today(), save.daily == today())
end

-- ===== Kopia komór: reset i przygotowanie =====

local function setPrompt(item: DelveMap.Interactive, on: boolean)
	item.prompt.Enabled = on
end

local function placeGuard(copy: DelveMap.Copy, cf: CFrame, moving: boolean)
	local guard = guards[copy.slot]
	if not guard then
		return
	end
	local root = guard.PrimaryPart
	if guard:GetAttribute("Rig") == true and root then
		root.CFrame = cf * root.PivotOffset:Inverse()
		guard:SetAttribute("Moving", moving)
	else
		guard:PivotTo(cf)
	end
end

local function resetCopy(copy: DelveMap.Copy)
	DelveMap.setShown(copy.blockage.model, true)
	setPrompt(copy.blockage, false)
	for _, item in copy.alcoves do
		DelveMap.setShown(item.model, true)
		setPrompt(item, false)
	end
	for _, item in copy.hides do
		DelveMap.setShown(item.model, true)
		setPrompt(item, false)
	end
	for _, item in copy.samples do
		DelveMap.setShown(item.model, false)
		setPrompt(item, false)
	end
	DelveMap.setShown(copy.find.model, false)
	setPrompt(copy.find, false)
	setPrompt(copy.bonfire, false)
	setPrompt(copy.exit, false)
	DelveMap.setShown(copy.door.model, true)
	setPrompt(copy.door, false)
	DelveMap.setShown(copy.relic, true)
	setPrompt(copy.altar, false)
	DelveMap.setFire(copy, false)
	DelveMap.setFlood(copy, false)
	placeGuard(copy, copy.guardHome, false)
end

local function setupCopy(run: Run)
	local copy = copyFor(run.slot)
	resetCopy(copy)
	local collapse = run.offer.modifier == "collapse"
	copy.blockage.prompt.HoldDuration = if collapse then Delve.CLEAR_HOLD.collapse else Delve.CLEAR_HOLD.normal
	setPrompt(copy.blockage, true)
	if run.offer.kind == "rubble" then
		for _, item in copy.alcoves do
			setPrompt(item, true)
		end
	elseif run.offer.kind == "chest" then
		run.chestHide = rng:NextInteger(1, #copy.hides)
		for _, item in copy.hides do
			setPrompt(item, true)
		end
	elseif run.offer.kind == "samples" then
		-- 3 z 6 miejsc, zawsze przynajmniej jedna próbka za zawałem (żeby trzeba było go odgruzować)
		local order = {}
		for i = 1, #copy.samples do
			table.insert(order, i)
		end
		for i = #order, 2, -1 do
			local j = rng:NextInteger(1, i)
			order[i], order[j] = order[j], order[i]
		end
		local kind = Delve.kind("samples")
		local goal = if kind then kind.goal else 3
		local chosen = {}
		for i = 1, goal do
			chosen[order[i]] = true
		end
		local beyond = false
		for index in chosen do
			if Delve.SPOTS.samples[index].x > Delve.SPOTS.blockage then
				beyond = true
			end
		end
		if not beyond then
			-- Podmieniamy jedną próbkę na taką za zawałem
			for index in chosen do
				chosen[index] = nil
				break
			end
			for i, spot in Delve.SPOTS.samples do
				if spot.x > Delve.SPOTS.blockage and not chosen[i] then
					chosen[i] = true
					break
				end
			end
		end
		for index in chosen do
			run.sampleOn[index] = true
			DelveMap.setShown(copy.samples[index].model, true)
			setPrompt(copy.samples[index], true)
		end
	end
	DelveMap.setFlood(copy, run.offer.modifier == "flood")
	setPrompt(copy.bonfire, true)
	run.guardCF = copy.guardHome
	run.guardTarget = 2
end

-- ===== Koniec ekspedycji =====

local function closeRun(run: Run)
	if not runs[run.id] then
		return
	end
	runs[run.id] = nil
	if slotRun[run.slot] == run then
		slotRun[run.slot] = nil
	end
	local camp = api.campCFrame()
	for _, member in run.members do
		if member.inside and not member.done and member.player.Parent then
			api.travel(member.player, camp, "MSG_DELVE_CLOSED")
		end
		member.done = true
		member.inside = false
	end
	local copy = copies[run.slot]
	if copy then
		resetCopy(copy)
	end
	for _, member in run.members do
		if member.player.Parent then
			makeOffers(member.player)
		end
	end
	broadcast()
end

-- Osoba kończy ekspedycję (wyszła liną, zgasła, złapana, wyszła z gry)
local function memberLeaves(run: Run, member: Member, failed: boolean)
	if member.done then
		return
	end
	member.done = true
	member.inside = false
	local player = member.player
	-- Znalezisko i trofeum nie przepadają dla reszty ekipy: wracają na miejsce
	if run.carrier == player then
		run.carrier = nil
		local copy = copies[run.slot]
		if copy and run.findAt then
			run.findShown = true
			copy.find.part.Position = run.findAt
			DelveMap.setShown(copy.find.model, true)
			setPrompt(copy.find, true)
		end
	end
	if run.cryptCarrier == player then
		run.cryptCarrier = nil
		run.cryptTaken = false
		local copy = copies[run.slot]
		if copy then
			DelveMap.setShown(copy.relic, true)
			setPrompt(copy.altar, run.doorOpen)
		end
	end
	if run.guardChase == player then
		run.guardChase = nil
	end
	if failed and player.Parent and not member.secured then
		api.notify(player, "MSG_DELVE_FAILED")
	end
	if run.leader == player and run.state == "prepare" then
		-- Prowadzący zrezygnował przed zejściem: zlecenie przepada całej ekipie
		notifyRun(run, "MSG_DELVE_CANCELLED")
		closeRun(run)
		return
	end
	if #activeMembers(run) == 0 then
		closeRun(run)
		return
	end
	-- Nowy prowadzący, jeśli stary odszedł
	if run.leader == player then
		run.leader = activeMembers(run)[1].player
	end
	sendRun(run)
	if player.Parent then
		makeOffers(player)
		sendState(player)
	end
end

-- ===== Nagrody =====

-- Admin abuse: podwójne odłamki do tej chwili (os.time)
local shardBoostUntil = 0
function DelveService.setShardBoost(untilTime: number)
	shardBoostUntil = untilTime
end

local function grantRelic(player: Player, relicId: string, bonusShards: number)
	local save = saveOf(player)
	local def = Delve.relic(relicId)
	if not save or not def then
		return
	end
	local new, shards = Delve.grant(save, relicId)
	if os.time() < shardBoostUntil then
		-- Podwójne: drugi raz tyle samo za duplikat i premię
		save.shards += shards + bonusShards
		shards *= 2
		bonusShards *= 2
	end
	save.shards += bonusShards
	if new then
		api.notify(player, "MSG_DELVE_RELIC_NEW", nil, def.key)
	else
		api.notify(player, "MSG_DELVE_RELIC_DUP", { shards + bonusShards }, def.key)
	end
	if new and bonusShards > 0 then
		api.notify(player, "MSG_DELVE_SHARDS", { bonusShards })
	end
end

-- Ognisko: znalezisko zabezpieczone, każdy z ekipy w komorach dostaje swoją nagrodę (raz)
local function secure(run: Run)
	if run.secured then
		return
	end
	run.secured = true
	run.carrier = nil
	local copy = copyFor(run.slot)
	DelveMap.setFire(copy, true)
	setPrompt(copy.bonfire, false)
	setPrompt(copy.exit, true)
	setPrompt(copy.door, true)
	local modifier = Delve.modifier(run.offer.modifier)
	local bonus = if modifier and modifier.hard then Delve.HARD_SHARDS else 0
	for _, member in insideMembers(run) do
		if member.secured then
			continue
		end
		member.secured = true
		local player = member.player
		local save = saveOf(player)
		if not save then
			continue
		end
		local relicId: string?
		if run.offer.daily and run.offer.relic and save.daily ~= today() then
			relicId = run.offer.relic
			save.daily = today()
		else
			relicId = Delve.rollRelic(run.offer.set, rng:NextNumber())
		end
		api.notify(player, "MSG_DELVE_SECURED")
		if relicId then
			grantRelic(player, relicId, bonus)
		end
		api.event(player, "delve", 1)
	end
	sendRun(run)
end

-- Trofeum wyniesione z Krypty: każdy z ekipy w komorach dostaje relikt z losowego zestawu i odłamki
local function secureCrypt(run: Run)
	if run.cryptSecured then
		return
	end
	run.cryptSecured = true
	run.cryptCarrier = nil
	for _, member in insideMembers(run) do
		local set = Delve.SETS[rng:NextInteger(1, #Delve.SETS)]
		local relicId = Delve.rollRelic(set, rng:NextNumber())
		api.notify(member.player, "MSG_DELVE_CRYPT_DONE")
		if relicId then
			grantRelic(member.player, relicId, Delve.CRYPT_SHARDS)
		end
		api.event(member.player, "crypt", 1)
	end
	sendRun(run)
end

-- ===== Cel w komorach =====

-- Cel wykonany: znalezisko do koszyka (jedno miejsce) albo zostaje na ziemi, gdy brak miejsca
local function completeObjective(run: Run, player: Player, at: Vector3)
	if run.objectiveDone then
		return
	end
	run.objectiveDone = true
	run.findAt = at + Vector3.new(0, 1.2, 0)
	if api.basketFree(player) >= 1 then
		run.carrier = player
		api.notify(player, "MSG_DELVE_FOUND")
		notifyRun(run, "MSG_DELVE_FOUND_TEAM", { player.DisplayName })
	else
		local copy = copyFor(run.slot)
		run.findShown = true
		copy.find.part.Position = run.findAt :: Vector3
		DelveMap.setShown(copy.find.model, true)
		setPrompt(copy.find, true)
		api.notify(player, "MSG_DELVE_NO_ROOM")
	end
	api.pushState(player)
	sendRun(run)
end

-- Kto z ekipy w komorach nacisnął przycisk (inaczej nil)
local function actor(slot: number, player: Player, item: DelveMap.Interactive): (Run?, Member?)
	local run = slotRun[slot]
	if not run or run.state ~= "active" then
		return nil, nil
	end
	local found, member = runOf(player)
	if found ~= run or not member or not member.inside then
		return nil, nil
	end
	if not near(player, item.part, item.prompt.MaxActivationDistance) then
		return nil, nil
	end
	return run, member
end

function DelveService.connectCopy(copy: DelveMap.Copy)
	local slot = copy.slot
	copy.blockage.prompt.Triggered:Connect(function(player)
		local run = actor(slot, player, copy.blockage)
		if not run or run.blockageCleared then
			return
		end
		run.blockageCleared = true
		DelveMap.setShown(copy.blockage.model, false)
		setPrompt(copy.blockage, false)
		notifyRun(run, "MSG_DELVE_CLEARED")
		sendRun(run)
	end)
	for index, item in copy.alcoves do
		item.prompt.Triggered:Connect(function(player)
			local run = actor(slot, player, item)
			if not run or run.offer.kind ~= "rubble" or run.cleared[index] then
				return
			end
			run.cleared[index] = true
			run.progress += 1
			DelveMap.setShown(item.model, false)
			setPrompt(item, false)
			local kind = Delve.kind("rubble")
			if kind and run.progress >= kind.goal then
				completeObjective(run, player, item.part.Position)
			else
				notifyRun(run, "MSG_DELVE_PROGRESS", { run.progress, if kind then kind.goal else 3 })
				sendRun(run)
			end
		end)
	end
	for index, item in copy.hides do
		item.prompt.Triggered:Connect(function(player)
			local run = actor(slot, player, item)
			if not run or run.offer.kind ~= "chest" or run.searched[index] or run.objectiveDone then
				return
			end
			run.searched[index] = true
			setPrompt(item, false)
			if index == run.chestHide then
				run.progress = 1
				completeObjective(run, player, item.part.Position)
			else
				api.notify(player, "MSG_DELVE_EMPTY")
				sendRun(run)
			end
		end)
	end
	for index, item in copy.samples do
		item.prompt.Triggered:Connect(function(player)
			local run = actor(slot, player, item)
			if not run or run.offer.kind ~= "samples" or not run.sampleOn[index] then
				return
			end
			run.sampleOn[index] = nil
			run.progress += 1
			DelveMap.setShown(item.model, false)
			setPrompt(item, false)
			local kind = Delve.kind("samples")
			if kind and run.progress >= kind.goal then
				completeObjective(run, player, item.part.Position)
			else
				notifyRun(run, "MSG_DELVE_PROGRESS", { run.progress, if kind then kind.goal else 3 })
				sendRun(run)
			end
		end)
	end
	copy.find.prompt.Triggered:Connect(function(player)
		local run = actor(slot, player, copy.find)
		if not run or not run.findShown or run.carrier then
			return
		end
		if api.basketFree(player) < 1 then
			api.notify(player, "MSG_DELVE_NO_ROOM")
			return
		end
		run.findShown = false
		run.carrier = player
		DelveMap.setShown(copy.find.model, false)
		setPrompt(copy.find, false)
		api.notify(player, "MSG_DELVE_FOUND")
		api.pushState(player)
		sendRun(run)
	end)
	copy.bonfire.prompt.Triggered:Connect(function(player)
		local run = actor(slot, player, copy.bonfire)
		if not run or run.secured then
			return
		end
		if run.carrier ~= player then
			api.notify(player, if run.carrier then "MSG_DELVE_CARRIER_NEEDED" else "MSG_DELVE_NEED_FIND", if run.carrier then { (run.carrier :: Player).DisplayName } else nil)
			return
		end
		secure(run)
		api.pushState(player)
	end)
	copy.exit.prompt.Triggered:Connect(function(player)
		local run, member = actor(slot, player, copy.exit)
		if not run or not member or not run.secured then
			return
		end
		if run.cryptCarrier == player then
			api.notify(player, "MSG_DELVE_TROPHY_FIRST")
			return
		end
		api.travel(player, api.campCFrame(), "MSG_DELVE_BACK")
		memberLeaves(run, member, false)
		api.pushState(player)
	end)
	copy.door.prompt.Triggered:Connect(function(player)
		local run = actor(slot, player, copy.door)
		if not run or not run.secured or run.doorOpen then
			return
		end
		run.doorOpen = true
		DelveMap.setShown(copy.door.model, false)
		setPrompt(copy.door, false)
		setPrompt(copy.altar, true)
		-- Strażnik Krypty: model Skarbnika budujemy przy pierwszym otwarciu tej kopii
		if not guards[slot] then
			local ok, model = pcall(SkarbnikModel.build, copy.folder, copy.guardHome, true)
			if ok and model then
				model.Name = "CryptGuard"
				guards[slot] = model
			else
				warn("[DelveService] Strażnik Krypty się nie zbudował:", model)
			end
		end
		run.guardCF = copy.guardHome
		run.guardTarget = 2
		notifyRun(run, "MSG_DELVE_CRYPT_OPEN")
		sendRun(run)
	end)
	copy.altar.prompt.Triggered:Connect(function(player)
		local run = actor(slot, player, copy.altar)
		if not run or not run.doorOpen or run.cryptTaken or run.cryptSecured then
			return
		end
		if api.basketFree(player) < 1 then
			api.notify(player, "MSG_DELVE_NO_ROOM")
			return
		end
		run.cryptTaken = true
		run.cryptCarrier = player
		DelveMap.setShown(copy.relic, false)
		setPrompt(copy.altar, false)
		api.notify(player, "MSG_DELVE_TROPHY")
		api.pushState(player)
		sendRun(run)
	end)
end

-- ===== Wejście do komór =====

local function startRun(run: Run)
	run.state = "active"
	run.startedAt = os.time()
	run.nextRock = os.clock() + 4
	setupCopy(run)
	broadcast()
end

local function onPassage(player: Player)
	local run, member = runOf(player)
	if not run or not member then
		api.notify(player, "MSG_DELVE_NEED_CONTRACT")
		return
	end
	if member.inside then
		return
	end
	if not near(player, entrances.passage, entrances.passagePrompt.MaxActivationDistance) then
		return
	end
	if api.isChased(player) then
		api.notify(player, "MSG_DELVE_CHASED")
		return
	end
	if run.secured then
		api.notify(player, "MSG_DELVE_TOO_LATE")
		return
	end
	if run.state == "prepare" then
		startRun(run)
	end
	member.inside = true
	member.entered = true
	local spawn = copyFor(run.slot).spawn
	-- Komory leżą daleko w bok: najpierw wczytujemy je wokół miejsca lądowania (StreamingEnabled)
	pcall(player.RequestStreamAroundAsync, player, spawn.Position, 10)
	api.travel(player, spawn, "MSG_DELVE_ENTER")
	sendRun(run)
end

-- ===== Akcje z tablicy i kolekcji =====

local function nearBoard(player: Player): boolean
	return near(player, entrances.board, BOARD_DISTANCE)
end

-- Gdzie stoi regał gracza (jego ogródek), żeby odświeżyć relikty
local function refreshShelf(garden: Model)
	local shelf = garden:FindFirstChild("RelicShelf")
	if not shelf then
		return
	end
	local old = shelf:FindFirstChild("Relics")
	if old then
		old:Destroy()
	end
	local ownerId = garden:GetAttribute("OwnerUserId")
	local owner = if typeof(ownerId) == "number" and ownerId ~= 0 then Players:GetPlayerByUserId(ownerId) else nil
	local save = if owner then saveOf(owner) else nil
	if not save then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Relics"
	local frameColors = {
		[0] = Color3.fromRGB(112, 78, 52),
		[1] = Color3.fromRGB(196, 124, 64),
		[2] = Color3.fromRGB(200, 206, 214),
		[3] = Color3.fromRGB(255, 206, 64),
	}
	for index, def in Delve.RELICS do
		local state = save.relics[def.id]
		local slot = shelf:FindFirstChild("RelicSlot" .. index, true)
		if not (state and state.r and slot and slot:IsA("Attachment")) then
			continue
		end
		local base = slot.WorldCFrame
		local pedestal = Instance.new("Part")
		pedestal.Name = "Pedestal"
		pedestal.Anchored = true
		pedestal.CanCollide = false
		pedestal.CanQuery = false
		pedestal.Size = Vector3.new(1, 0.3, 0.9)
		pedestal.CFrame = base * CFrame.new(0, 0.15, 0)
		pedestal.Color = frameColors[state.f] or frameColors[0]
		pedestal.Material = if state.f >= 1 then Enum.Material.Metal else Enum.Material.Wood
		pedestal.Parent = folder
		local gem = Instance.new("Part")
		gem.Name = "Relic"
		gem.Shape = Enum.PartType.Ball
		gem.Anchored = true
		gem.CanCollide = false
		gem.CanQuery = false
		gem.Size = Vector3.new(0.75, 0.75, 0.75)
		gem.CFrame = base * CFrame.new(0, 0.75, 0)
		gem.Color = Color3.fromRGB(def.color[1], def.color[2], def.color[3])
		gem.Material = Enum.Material.Neon
		gem.Parent = folder
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(34, 34)
		billboard.StudsOffset = Vector3.new(0, 0.9, 0)
		billboard.MaxDistance = 40
		billboard.LightInfluence = 0
		local icon = Instance.new("TextLabel")
		icon.BackgroundTransparency = 1
		icon.Size = UDim2.fromScale(1, 1)
		icon.TextScaled = true
		icon.Text = def.icon
		icon.Parent = billboard
		billboard.Parent = gem
		if state.f >= 3 then
			local sparkle = Instance.new("Sparkles")
			sparkle.SparkleColor = Color3.fromRGB(255, 220, 120)
			sparkle.Parent = gem
		end
	end
	folder.Parent = shelf
end

local function refreshShelfOf(player: Player)
	for _, garden in gardens do
		if garden:GetAttribute("OwnerUserId") == player.UserId then
			refreshShelf(garden)
		end
	end
end

local function newRun(player: Player, slot: number, offer: Delve.Offer): Run
	nextRunId += 1
	return {
		id = nextRunId,
		slot = slot,
		leader = player,
		members = { { player = player, inside = false, entered = false, done = false, secured = false } },
		offer = table.clone(offer),
		state = "prepare",
		createdAt = os.time(),
		startedAt = 0,
		progress = 0,
		objectiveDone = false,
		findShown = false,
		secured = false,
		blockageCleared = false,
		chestHide = 1,
		cleared = {},
		searched = {},
		sampleOn = {},
		doorOpen = false,
		cryptTaken = false,
		cryptSecured = false,
		nextRock = 0,
		guardCF = CFrame.new(),
		guardTarget = 2,
	}
end

local function onAction(player: Player, action: unknown, arg: unknown)
	if typeof(action) ~= "string" then
		return
	end
	local now = os.clock()
	if now - (lastAction[player] or 0) < 0.3 then
		return
	end
	lastAction[player] = now
	local data = api.getData(player)
	if not data then
		return
	end
	local save: Delve.Save = data.delve

	if action == "take" then
		if typeof(arg) ~= "number" or not nearBoard(player) then
			return
		end
		if not data.caveUnlocked then
			return
		end
		if runOf(player) then
			api.notify(player, "MSG_DELVE_ALREADY")
			return
		end
		local list = offers[player]
		local offer = list and list[math.floor(arg)]
		if not offer then
			return
		end
		local slot = freeSlot()
		if not slot then
			api.notify(player, "MSG_DELVE_BUSY")
			return
		end
		local run = newRun(player, slot, offer)
		runs[run.id] = run
		slotRun[slot] = run
		api.notify(player, "MSG_DELVE_TAKEN")
		broadcast()
	elseif action == "join" then
		if typeof(arg) ~= "number" or not nearBoard(player) or not data.caveUnlocked then
			return
		end
		if runOf(player) then
			api.notify(player, "MSG_DELVE_ALREADY")
			return
		end
		local run = runs[math.floor(arg)]
		if not run or run.state ~= "prepare" or #activeMembers(run) >= Delve.MAX_PARTY then
			api.notify(player, "MSG_DELVE_JOIN_FAILED")
			sendState(player)
			return
		end
		table.insert(run.members, { player = player, inside = false, entered = false, done = false, secured = false })
		notifyRun(run, "MSG_DELVE_JOINED", { player.DisplayName })
		broadcast()
	elseif action == "leave" then
		local run, member = runOf(player)
		-- W komorach nie da się zrezygnować (inaczej byłby to darmowy powrót do obozu z pełnym koszykiem)
		if run and member and not member.inside then
			memberLeaves(run, member, false)
			broadcast()
		end
	elseif action == "restore" and typeof(arg) == "string" then
		local cost = Delve.canRestore(save, arg, data.coins)
		local def = Delve.relic(arg)
		if not cost or not def then
			return
		end
		data.coins -= cost
		save.relics[arg].r = true
		api.notify(player, "MSG_DELVE_RESTORED", nil, def.key)
		api.pushState(player)
		refreshShelfOf(player)
		sendState(player)
	elseif action == "frame" and typeof(arg) == "string" then
		local cost = Delve.canFrame(save, arg, data.coins)
		local _, shards = Delve.nextFrame(save, arg)
		local def = Delve.relic(arg)
		if not cost or not shards or not def then
			return
		end
		data.coins -= cost
		save.shards -= shards
		save.relics[arg].f += 1
		api.notify(player, "MSG_DELVE_FRAMED", nil, def.key)
		api.pushState(player)
		refreshShelfOf(player)
		sendState(player)
	elseif action == "craft" and typeof(arg) == "string" then
		local def = Delve.relic(arg)
		if not def or not Delve.craft(save, arg) then
			return
		end
		api.notify(player, "MSG_DELVE_CRAFTED", nil, def.key)
		sendState(player)
	elseif action == "state" then
		sendState(player)
	end
end

-- ===== Olej w komorach (GameService.tick) =====

-- Zmiana oleju na sekundę dla gracza w komorach (ujemna = spalanie, dodatnia = tankowanie przy haku);
-- nil = gracz nie jest w komorach (zwykłe zasady strefy). groupDrain: Expedition.drain(grupa).
function DelveService.oilDelta(player: Player, position: Vector3, oilMax: number, wick: number, groupDrain: number): number?
	if not Delve.isInside(position) then
		return nil
	end
	local run = runOf(player)
	local slot, lx, lz = Delve.locate(position)
	if not run or slot ~= run.slot then
		return -Delve.drain(oilMax, wick, false, groupDrain)
	end
	for _, hook in Delve.SPOTS.oil do
		local dx, dz = lx - hook.x, lz - hook.z
		if dx * dx + dz * dz <= Delve.REFILL_RADIUS * Delve.REFILL_RADIUS then
			return oilMax * Delve.REFILL_PER_SECOND
		end
	end
	local wet = Delve.wet(lx, position.Y - 3, run.offer.modifier == "flood")
	return -Delve.drain(oilMax, wick, wet, groupDrain)
end

-- Ile miejsc w koszyku zajmuje ekspedycja (niesione znalezisko i trofeum z Krypty)
function DelveService.reserved(player: Player): number
	local run = runOf(player)
	if not run then
		return 0
	end
	return (if run.carrier == player then 1 else 0) + (if run.cryptCarrier == player then 1 else 0)
end

-- Gracza pochłonęło (zgasła latarnia / złapał strażnik): koniec ekspedycji dla niego
function DelveService.onEngulf(player: Player)
	local run, member = runOf(player)
	if run and member and member.inside then
		memberLeaves(run, member, true)
	end
end

-- ===== Pętla: osuwiska, strażnik Krypty, wyniesienie trofeum, limity czasu =====

local function dropRock(run: Run, at: Vector3)
	local ring = Instance.new("Part")
	ring.Name = "RockWarning"
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.1, Delve.ROCK.radius * 2, Delve.ROCK.radius * 2)
	ring.CFrame = CFrame.new(at.X, Delve.FLOOR_Y + 0.08, at.Z) * CFrame.Angles(0, 0, math.rad(90))
	ring.Color = Color3.fromRGB(255, 70, 50)
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.45
	local copy = copies[run.slot]
	ring.Parent = if copy then copy.folder else Workspace
	-- Pył sypie się z sufitu jako ostrzeżenie
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(Color3.fromRGB(150, 130, 110))
	dust.Size = NumberSequence.new(0.6, 1.4)
	dust.Transparency = NumberSequence.new(0.5, 1)
	dust.Lifetime = NumberRange.new(0.8)
	dust.Rate = 30
	dust.Speed = NumberRange.new(0)
	dust.Acceleration = Vector3.new(0, -25, 0)
	local dustSource = Instance.new("Attachment")
	dustSource.Position = Vector3.new(Delve.CEILING - 1, 0, 0) -- oś X cylindra = pion
	dustSource.Parent = ring
	dust.Parent = dustSource
	task.delay(Delve.ROCK.warn, function()
		dust.Enabled = false
		local rock = Instance.new("Part")
		rock.Name = "FallingRock"
		rock.Anchored = true
		rock.CanCollide = false
		rock.CanQuery = false
		rock.Size = Vector3.new(2.6, 2.2, 2.6)
		rock.Color = Color3.fromRGB(104, 86, 70)
		rock.Material = Enum.Material.Slate
		rock.CFrame = CFrame.new(at.X, Delve.CEILING - 1.5, at.Z) * CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 3), 0)
		rock.Parent = ring.Parent
		local tween = TweenService:Create(rock, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			CFrame = CFrame.new(at.X, Delve.FLOOR_Y + 1.1, at.Z) * rock.CFrame.Rotation,
		})
		tween:Play()
		tween.Completed:Wait()
		if runs[run.id] then
			for _, member in insideMembers(run) do
				local root = rootOf(member.player)
				if root and Vector3.new(root.Position.X - at.X, 0, root.Position.Z - at.Z).Magnitude <= Delve.ROCK.radius then
					api.addOil(member.player, -Delve.ROCK.oilLoss)
					api.notify(member.player, "MSG_DELVE_ROCK", { math.floor(Delve.ROCK.oilLoss * 100) })
				end
			end
		end
		ring:Destroy()
		task.delay(1.5, function()
			rock:Destroy()
		end)
	end)
end

local function stepRocks(run: Run, now: number)
	if now < run.nextRock then
		return
	end
	local collapse = run.offer.modifier == "collapse"
	run.nextRock = now + (if collapse then Delve.ROCK.everyCollapse else Delve.ROCK.every) * rng:NextNumber(0.8, 1.25)
	local targets = {}
	for _, member in insideMembers(run) do
		local root = rootOf(member.player)
		if root then
			local lx = localOf(run, root.Position)
			local section = Delve.sectionAt(lx)
			if section and section.id == "tunnel" then
				table.insert(targets, root.Position)
			end
		end
	end
	if #targets == 0 then
		return
	end
	-- Kamień pada tam, gdzie gracz właśnie stoi (albo kawałek dalej, gdy idzie): trzeba odskoczyć
	local target = targets[rng:NextInteger(1, #targets)]
	dropRock(run, target + Vector3.new(rng:NextNumber(-1.2, 1.2), 0, rng:NextNumber(-1.2, 1.2)))
end

local function stepGuard(run: Run, dt: number)
	if not run.doorOpen or not guards[run.slot] then
		return
	end
	local copy = copyFor(run.slot)
	local watch = run.offer.modifier == "watch"
	local guard = Delve.GUARD
	local speed = (if watch then guard.speedWatch else guard.speed) + (if run.cryptCarrier then guard.carryBonus else 0)
	local position = run.guardCF.Position
	local x0, z0 = Delve.slotOrigin(run.slot)

	-- Kogo widzi (gracze w Krypcie, poza wnękami)
	local chase = run.guardChase
	if chase then
		local root = rootOf(chase)
		local lx, lz = 0, 0
		if root then
			lx, lz = localOf(run, root.Position)
		end
		if not root or lx < Delve.SPOTS.cryptDoor + 0.5 or Delve.inNiche(lx, lz) then
			run.guardChase = nil -- uciekł za drzwi albo schował się we wnęce
			chase = nil
		end
	end
	if not chase then
		for _, member in insideMembers(run) do
			local root = rootOf(member.player)
			if root then
				local lx, lz = localOf(run, root.Position)
				if lx >= Delve.SPOTS.cryptDoor + 0.5 and not Delve.inNiche(lx, lz) then
					local offset = Vector3.new(root.Position.X - position.X, 0, root.Position.Z - position.Z)
					if offset.Magnitude > 0.01 and Delve.guardSees(offset, run.guardCF.LookVector, watch) then
						run.guardChase = member.player
						api.notify(member.player, "MSG_DELVE_SPOTTED")
						break
					end
				end
			end
		end
		chase = run.guardChase
	end

	local target: Vector3
	if chase then
		local root = rootOf(chase)
		target = if root then Vector3.new(root.Position.X, position.Y, root.Position.Z) else position
		speed *= 1.25
	else
		local point = Delve.SPOTS.patrol[run.guardTarget]
		target = Vector3.new(x0 + point.x, position.Y, z0 + point.z)
		if (target - position).Magnitude < 0.6 then
			run.guardTarget = run.guardTarget % #Delve.SPOTS.patrol + 1
		end
	end
	local toTarget = target - position
	local distance = toTarget.Magnitude
	if distance > 0.05 then
		local move = math.min(speed * dt, distance)
		position += toTarget.Unit * move
	end
	-- Strażnik nie wychodzi z Krypty
	local minX = x0 + Delve.SPOTS.cryptDoor + 2
	position = Vector3.new(math.max(position.X, minX), position.Y, position.Z)
	run.guardCF = if distance > 0.1 then CFrame.lookAt(position, Vector3.new(target.X, position.Y, target.Z)) else CFrame.new(position) * run.guardCF.Rotation
	placeGuard(copy, run.guardCF, distance > 0.1)

	if chase then
		local root = rootOf(chase)
		if root and Vector3.new(root.Position.X - position.X, 0, root.Position.Z - position.Z).Magnitude <= GUARD_CATCH then
			run.guardChase = nil
			api.engulf(chase, "MSG_DELVE_CAUGHT") -- wywoła onEngulf (koniec ekspedycji dla złapanego)
		end
	end
end

local secondTimer = 0
local function step(dt: number)
	local now = os.clock()
	secondTimer += dt
	local everySecond = secondTimer >= 1
	if everySecond then
		secondTimer = 0
	end
	for _, run in runs do
		if run.state == "active" then
			stepRocks(run, now)
			stepGuard(run, dt)
			-- Trofeum za drzwiami Krypty = wyniesione
			local carrier = run.cryptCarrier
			if carrier then
				local root = rootOf(carrier)
				if root and localOf(run, root.Position) < Delve.SPOTS.cryptDoor - 1.5 then
					secureCrypt(run)
					api.pushState(carrier)
				end
			end
		end
		if everySecond then
			local t = os.time()
			if run.state == "prepare" and t > run.createdAt + Delve.PREPARE_SECONDS then
				notifyRun(run, "MSG_DELVE_EXPIRED")
				closeRun(run)
			elseif run.state == "active" and t > run.startedAt + Delve.RUN_SECONDS then
				notifyRun(run, "MSG_DELVE_TIMEOUT")
				closeRun(run)
			end
		end
	end
	-- Ktoś w komorach bez ekspedycji (np. zakończona): z powrotem do obozu
	if everySecond then
		for _, player in Players:GetPlayers() do
			local root = rootOf(player)
			if root and Delve.isInside(root.Position) then
				local run, member = runOf(player)
				if not run or not member or not member.inside then
					api.travel(player, api.campCFrame(), nil)
				end
			end
		end
	end
end

-- ===== Start =====

function DelveService.start(gardenModels: { Model }, serviceApi: Api)
	api = serviceApi
	entrances = DelveMap.buildEntrances(Workspace:FindFirstChild("Map") or Workspace)
	entrances.boardPrompt.Triggered:Connect(function(player)
		if not near(player, entrances.board, BOARD_DISTANCE) then
			return
		end
		local data = api.getData(player)
		if not data then
			return
		end
		if not offers[player] then
			makeOffers(player)
		end
		sendState(player, "board")
	end)
	entrances.passagePrompt.Triggered:Connect(onPassage)

	gardens = gardenModels
	for _, garden in gardens do
		local shelf = garden:FindFirstChild("RelicShelf")
		local board = shelf and shelf:FindFirstChild("ShelfBoard")
		if board and board:IsA("BasePart") then
			local p = Instance.new("ProximityPrompt")
			p.Name = "ShelfPrompt"
			p.ActionText = "DELVE_PROMPT_SHELF"
			p:SetAttribute("TextKey", "DELVE_PROMPT_SHELF")
			-- GardenPrompts włącza go lokalnie tylko właścicielowi ogródka (atrybut Owner)
			p:SetAttribute("Owner", true)
			p.Enabled = false
			p.KeyboardKeyCode = Enum.KeyCode.F
			p.GamepadKeyCode = Enum.KeyCode.ButtonY
			p.MaxActivationDistance = 8
			p.RequiresLineOfSight = false
			p.Parent = board
			p.Triggered:Connect(function(player)
				if garden:GetAttribute("OwnerUserId") ~= player.UserId then
					api.notify(player, "MSG_DELVE_SHELF_OTHER")
					return
				end
				if not offers[player] then
					makeOffers(player)
				end
				sendState(player, "collection")
			end)
		end
		garden:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
			-- Dane właściciela wczytują się chwilę po przydziale ogródka
			task.delay(1, refreshShelf, garden)
		end)
	end

	DelveAction.OnServerEvent:Connect(onAction)
	Players.PlayerRemoving:Connect(function(player)
		local run, member = runOf(player)
		if run and member then
			memberLeaves(run, member, false)
		end
		offers[player] = nil
		lastAction[player] = nil
	end)
	RunService.Heartbeat:Connect(step)
end

-- Panel DEV: od razu przenieś do komór z gotowym zleceniem (tylko Studio)
function DelveService.devStart(player: Player)
	if not runOf(player) then
		makeOffers(player)
		local data = api.getData(player)
		if not data then
			return
		end
		local slot = freeSlot()
		if not slot then
			return
		end
		local offer = (offers[player] or {})[1]
		if not offer then
			return
		end
		local created = newRun(player, slot, offer)
		runs[created.id] = created
		slotRun[slot] = created
	end
	local found, member = runOf(player)
	if found and member and not member.inside then
		if found.state == "prepare" then
			startRun(found)
		end
		member.inside = true
		member.entered = true
		local spawn = copyFor(found.slot).spawn
		pcall(player.RequestStreamAroundAsync, player, spawn.Position, 10)
		api.travel(player, spawn, "MSG_DELVE_ENTER")
		sendRun(found)
	end
end

return DelveService
