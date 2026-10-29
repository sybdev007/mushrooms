--!strict
-- Cutscenka z kradzieżą (samouczek, po pierwszym posadzeniu grzyba):
--   1. Gracz klepie ziemię przy grządce, wstaje, ociera pot z czoła: „Gotowe! Teraz po olej i w las.” i odchodzi.
--   2. Przebitka zza rogu chatki: wychyla się złodziej w czapce z pomponem i masce. „Hehe… ładne grzybki…”
--   3. Skrada się na paluszkach jak w kreskówce, rozgląda się, „ćśś”, kuca przy grządce i szarpie grzyba.
--   4. Gracz wraca: „Hej! Zostaw to!”. Złodziej podskakuje ze strachu, ucieka, wywraca się na twarz, zwiewa.
--   5. Gracz przegania go machaniem ręki: „I nie wracaj!” i otrzepuje dłonie. Potem okno z wyjaśnieniem kradzieży.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Audio = require(script.Parent.Audio)
local Clips = require(script.Parent.CutsceneClips)
local Kit = require(script.Parent.CutsceneKit)
local Localize = require(script.Parent.Localize)

local TheftCutscene = {}

local player = Players.LocalPlayer
local look = Kit.look

local SOUNDS = { "clues", "hall", "sneak", "pat", "plant", "gasp", "bubble", "blip", "surprise", "loony", "boom", "footstep", "crack", "whoosh", "leaves", "coin" }

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function myGarden(): Model?
	for _, model in CollectionService:GetTagged("GardenPlot") do
		if model:IsA("Model") and model:GetAttribute("OwnerUserId") == player.UserId then
			return model
		end
	end
	return nil
end

-- Grzyb posadzony najbliżej podanego miejsca (żeby nim potrząsać, gdy złodziej szarpie)
local function plantedNear(garden: Model, where: Vector3): Model?
	local folder = garden:FindFirstChild("Planted")
	local best: Model? = nil
	local bestDistance = 6
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("Model") then
				local d = (flat(child:GetPivot().Position) - flat(where)).Magnitude
				if d < bestDistance then
					bestDistance = d
					best = child
				end
			end
		end
	end
	return best
end

local function scenario(s: Kit.Scene, garden: Model)
	local hub = garden.PrimaryPart or garden:FindFirstChild("Hub", true)
	if not hub or not hub:IsA("BasePart") then
		return
	end
	local gate = flat(hub.Position)
	-- Grządki: środek ogródka i pierwsza grządka (tam rośnie posadzony grzyb)
	local slots: { Vector3 } = {}
	for i = 1, 9 do
		local slot = garden:FindFirstChild("Slot" .. i, true)
		if slot and slot:IsA("Attachment") then
			table.insert(slots, flat(slot.WorldPosition))
		end
	end
	if #slots == 0 then
		return
	end
	local center = Vector3.zero
	for _, p in slots do
		center += p
	end
	center /= #slots
	local inward = flat(center - gate)
	inward = if inward.Magnitude > 0.1 then inward.Unit else Vector3.new(0, 0, 1)
	local side = inward:Cross(Vector3.yAxis)
	-- Grządka najbliżej furtki (żeby złodziej miał blisko, a kamera widziała wszystko)
	local bed = slots[1]
	for _, p in slots do
		if (p - gate).Magnitude < (bed - gate).Magnitude then
			bed = p
		end
	end
	local plant = plantedNear(garden, bed)
	local plantBase = if plant then plant:GetPivot() else nil
	Kit.onCleanup(s, function()
		if plant and plantBase and plant.Parent then
			plant:PivotTo(plantBase)
		end
	end)
	local standPlayer = bed - inward * 2 + side * 0.6
	local exit = gate - inward * 14 + Vector3.new(0, 0, 8)

	-- Róg chatki najbliżej furtki: złodziej chowa się za ścianą, która NIE patrzy na furtkę,
	-- i wychyla się zza rogu w stronę ogródka
	local cabin = Workspace:FindFirstChild("Map") and (Workspace :: any).Map:FindFirstChild("Cabin")
	local corner = gate - inward * 18 + side * 10
	local hide = corner + side * 2
	local peekDir = -side
	local out = corner - side * 3
	if cabin and cabin:IsA("Model") then
		local cf, size = cabin:GetBoundingBox()
		local middle = flat(cf.Position)
		local best: Vector3? = nil
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local c = flat(middle + Vector3.new(sx * size.X / 2, 0, sz * size.Z / 2))
				if not best or (c - gate).Magnitude < (best - gate).Magnitude then
					best = c
				end
			end
		end
		corner = best :: Vector3
		local ox = if corner.X > middle.X then 1 else -1
		local oz = if corner.Z > middle.Z then 1 else -1
		local toGate = gate - corner
		if math.abs(toGate.X) >= math.abs(toGate.Z) then
			-- Furtka z boku: chowa się za przednią/tylną ścianą
			hide = corner + Vector3.new(-ox * 2, 0, oz * 2.4)
			peekDir = Vector3.new(ox, 0, 0)
			out = corner + Vector3.new(ox * 3, 0, oz * 2.4)
		else
			-- Furtka z przodu/tyłu: chowa się za boczną ścianą
			hide = corner + Vector3.new(ox * 2.4, 0, -oz * 2)
			peekDir = Vector3.new(0, 0, oz)
			out = corner + Vector3.new(ox * 2.4, 0, oz * 3)
		end
	end
	local away = (hide - corner) - peekDir * peekDir:Dot(hide - corner)
	away = if away.Magnitude > 0.01 then away.Unit else side
	-- Złodziej wychyla się w prawo, więc jego prawa strona patrzy w stronę wyjścia zza rogu
	local thiefFacing = Vector3.yAxis:Cross(peekDir)

	local hero = Kit.actor(s, { name = "Gardener" })
	local thief = Kit.actor(s, { name = "Thief", thief = true })
	if not hero or not thief then
		return
	end
	Kit.place(hero, standPlayer, bed - standPlayer)
	Kit.place(thief, hide, thiefFacing)

	-- 1. Sadzenie skończone: klepie ziemię, ociera pot
	Kit.phase(s, "plant")
	Kit.letterbox(s, true, 0.01)
	Kit.shot(s, look(bed + side * 7 - inward * 5 + Vector3.new(0, 4.5, 0), bed + Vector3.new(0, 1.2, 0)), look(bed + side * 6 - inward * 4 + Vector3.new(0, 3.8, 0), bed + Vector3.new(0, 1.4, 0)), 3, 55)
	Kit.fade(s, false, 0.8)
	Kit.clip(hero, Clips.patSoil, {
		fade = 0.2,
		events = function(name)
			if name == "pat" then
				Audio.play("pat", { volume = 0.7, jitter = 0.1 })
			end
		end,
	})
	if not Kit.wait(s, 2.2) then
		return
	end
	Kit.shot(s, look(standPlayer + (bed - standPlayer).Unit * 5 + side * 1.5 + Vector3.new(0, 3, 0), standPlayer + Vector3.new(0, 2.6, 0)), nil, 0, 48)
	Kit.clip(hero, Clips.wipeSweat, {
		fade = 0.15,
		events = function(name)
			if name == "sweat" then
				-- Kropla potu odlatuje z czoła
				local head = hero.head
				if head then
					local drop = Instance.new("Part")
					drop.Shape = Enum.PartType.Ball
					drop.Size = Vector3.new(0.3, 0.3, 0.3)
					drop.Color = Color3.fromRGB(150, 210, 255)
					drop.Material = Enum.Material.Glass
					drop.Transparency = 0.2
					drop.CanCollide = false
					drop.CanQuery = false
					drop.CanTouch = false
					drop.Anchored = true
					drop.CFrame = head.CFrame * CFrame.new(0.4, 0.6, -0.4)
					drop.Parent = Workspace
					local start = drop.Position
					local t0 = os.clock()
					local fly: RBXScriptConnection? = nil
					fly = RunService.RenderStepped:Connect(function()
						local k = (os.clock() - t0) / 0.6
						drop.Position = start + head.CFrame.RightVector * k * 1.6 + Vector3.new(0, math.sin(k * math.pi) * 0.8 - k * 1.2, 0)
						if k >= 1 then
							if fly then
								fly:Disconnect()
							end
							drop:Destroy()
						end
					end)
				end
				Audio.play("whoosh", { volume = 0.3, pitch = 1.6 })
			elseif name == "sigh" then
				Audio.play("gasp", { volume = 0.5, pitch = 0.8 })
			end
		end,
	})
	if not Kit.wait(s, 2.0) then
		return
	end
	if not Kit.bubble(s, hero, Localize.t("CUT2_DONE"), 1.1, false, nil, 1.15) then
		return
	end
	Kit.clip(hero, nil, { fade = 0.3 })
	Kit.move(hero, gate - inward * 2, 2.0, "walk", 1)
	if not Kit.wait(s, 1.6) then
		return
	end
	Kit.move(hero, exit, 2.4, "walk", 1)

	-- 2. Zza rogu chatki: złodziej się wychyla
	Kit.phase(s, "peek")
	Audio.music("clues", 0.6)
	local peekEye = hide + peekDir * 6 + away * 1.5 + Vector3.new(0, 2.4, 0)
	Kit.shot(s, look(peekEye, hide + Vector3.new(0, 2.6, 0) + peekDir * 1.2), look(peekEye - peekDir * 0.8, hide + Vector3.new(0, 2.8, 0) + peekDir * 1.2), 3.2, 46)
	Kit.clip(thief, Clips.peek, { fade = 0.2 })
	Audio.play("leaves", { volume = 0.5, duration = 1.2 })
	if not Kit.wait(s, 2.0) then
		return
	end
	if not Kit.bubble(s, thief, Localize.t("CUT2_THIEF"), 1.0, false, nil, 0.75) then
		return
	end

	-- 3. Skradanie na paluszkach
	Kit.phase(s, "sneak")
	Kit.track(thief, nil)
	Kit.clip(thief, Clips.sneak, {
		fade = 0.25,
		events = function(name)
			if name == "step" then
				Audio.play("sneak", { volume = 0.7, jitter = 0.15 })
			end
		end,
	})
	Kit.face(thief, out, 0.2)
	Kit.move(thief, out, 3.2, nil)
	Kit.follow(s, function()
		local p = thief.root.Position
		local dir = flat(out - hide)
		dir = if dir.Magnitude > 0.1 then dir.Unit else Vector3.new(1, 0, 0)
		local sideways = dir:Cross(Vector3.yAxis)
		return look(p + sideways * 8 + dir * 2 + Vector3.new(0, 1.2, 0), p + Vector3.new(0, 0.4, 0))
	end, 50)
	if not Kit.wait(s, 3.2) then
		return
	end
	-- Przeskok: złodziej przy furtce, rozgląda się i robi „ćśś”
	local sneakFrom = gate - inward * 3 + side * 1.5
	local tugAt = bed - inward * 1.6 - side * 0.4
	Kit.place(thief, sneakFrom, inward)
	Kit.clip(thief, Clips.lookAround, {
		fade = 0.15,
		events = function(name)
			if name == "shh" then
				Audio.play("whoosh", { volume = 0.2, pitch = 2 })
			end
		end,
	})
	Kit.shot(s, look(gate + inward * 4 + side * 4 + Vector3.new(0, 2.6, 0), sneakFrom + Vector3.new(0, 2.4, 0)), nil, 0, 50)
	if not Kit.wait(s, 2.2) then
		return
	end
	Kit.clip(thief, Clips.sneak, {
		fade = 0.15,
		events = function(name)
			if name == "step" then
				Audio.play("sneak", { volume = 0.7, jitter = 0.15 })
			end
		end,
	})
	Kit.move(thief, tugAt, 2.6, nil)
	Kit.shot(s, look(bed + side * 6 + inward * 2 + Vector3.new(0, 3, 0), sneakFrom + Vector3.new(0, 1.8, 0)), look(bed + side * 5 + inward * 2 + Vector3.new(0, 2.6, 0), tugAt + Vector3.new(0, 1.8, 0)), 2.6, 50)
	if not Kit.wait(s, 2.6) then
		return
	end
	Kit.face(thief, bed, 0.2)
	Kit.clip(thief, Clips.tug, {
		fade = 0.2,
		events = function(name)
			if name == "tug" then
				thief.shake = 1
				task.delay(0.25, function()
					thief.shake = 0
				end)
				Audio.play("crack", { volume = 0.35, pitch = 1.6, duration = 0.4 })
			end
		end,
	})
	-- Grzyb na grządce chwieje się przy szarpaniu
	local wobbleStart = os.clock()
	local wobble = RunService.RenderStepped:Connect(function()
		if plant and plantBase and plant.Parent then
			local t = os.clock() - wobbleStart
			local amount = math.clamp(t / 1.2, 0, 1) * 0.25
			plant:PivotTo(plantBase * CFrame.new(0, math.abs(math.sin(t * 9)) * 0.25, 0) * CFrame.Angles(math.sin(t * 14) * amount, 0, math.sin(t * 11) * amount))
		end
	end)
	table.insert(s.connections, wobble)
	if not Kit.wait(s, 1.7) then
		return
	end

	-- 4. Gracz wraca i krzyczy
	Kit.phase(s, "caught")
	Audio.music(nil, 0.1)
	Audio.play("surprise", { volume = 0.9 })
	Kit.place(hero, gate - inward * 7, inward)
	Kit.move(hero, gate - inward * 0.5, 1.0, "run", 1.4)
	Kit.shot(s, look(gate + inward * 2.5 + side * 2 + Vector3.new(0, 2.6, 0), gate - inward * 4 + Vector3.new(0, 2.6, 0)), nil, 0, 55)
	task.spawn(function()
		Kit.bubble(s, hero, Localize.t("CUT2_HEY"), 0.9, false, nil, 1.1)
	end)
	if not Kit.wait(s, 1.0) then
		return
	end
	Kit.track(hero, "idle")
	Kit.clip(hero, Clips.point, { fade = 0.1 })
	wobble:Disconnect()
	if plant and plantBase and plant.Parent then
		plant:PivotTo(plantBase)
	end
	-- Złodziej podskakuje ze strachu
	Kit.shot(s, look(tugAt + side * 5 - inward * 1 + Vector3.new(0, 3, 0), tugAt + Vector3.new(0, 2.6, 0)), nil, 0, 52)
	Kit.face(thief, gate, 0.1)
	Kit.clip(thief, Clips.jumpScare, { fade = 0.05 })
	Kit.mark(s, thief, "!")
	Audio.play("loony", { volume = 0.8 })
	if not Kit.wait(s, 0.9) then
		return
	end
	-- Ucieka w drugą stronę ogródka i wywraca się na twarz
	Audio.music("hall", 0.2)
	local fleeTo = bed + inward * 12 - side * 3
	Kit.clip(thief, nil, { fade = 0.15 })
	Kit.move(thief, fleeTo, 1.4, "run", 1.7)
	Kit.follow(s, function()
		local p = thief.root.Position
		return look(gate + side * 3 + Vector3.new(0, 4, 0), p + Vector3.new(0, 1.5, 0))
	end, 55)
	if not Kit.wait(s, 1.4) then
		return
	end
	Kit.track(thief, nil)
	Kit.clip(thief, Clips.faceplant, {
		fade = 0.05,
		events = function(name)
			if name == "thud" then
				Audio.play("boom", { volume = 0.8 })
				s.shake = 0.5
			end
		end,
	})
	if not Kit.wait(s, 2.2) then
		return
	end
	Kit.clip(thief, nil, { fade = 0.1 })
	Kit.move(thief, fleeTo + inward * 20, 1.6, "run", 1.8)

	-- 5. Gracz go przegania i otrzepuje ręce
	Kit.phase(s, "shoo")
	Kit.shot(s, look(gate + inward * 4 + side * 3 + Vector3.new(0, 2.8, 0), gate - inward * 0.5 + Vector3.new(0, 2.6, 0)), nil, 0, 50)
	Kit.face(hero, fleeTo, 0.2)
	Kit.clip(hero, Clips.shoo, {
		fade = 0.15,
		events = function(name)
			if name == "shoo" then
				Audio.play("whoosh", { volume = 0.35, pitch = 1.3, jitter = 0.1 })
			end
		end,
	})
	task.spawn(function()
		Kit.bubble(s, hero, Localize.t("CUT2_BYE"), 1.0, false, nil, 1.1)
	end)
	if not Kit.wait(s, 1.6) then
		return
	end
	Kit.clip(hero, Clips.dustHands, {
		fade = 0.15,
		events = function(name)
			if name == "pat" then
				Audio.play("pat", { volume = 0.5, pitch = 1.4 })
			end
		end,
	})
	if not Kit.wait(s, 1.6) then
		return
	end
	Audio.music(nil, 1.2)
	Kit.fade(s, true, 0.5)
	Kit.wait(s, 0.6)
end

function TheftCutscene.play(onDone: () -> ())
	local garden = myGarden()
	if not garden then
		onDone()
		return
	end
	local s = Kit.begin(SOUNDS)
	Kit.run(s, function(scene)
		scenario(scene, garden)
	end, onDone)
end

return TheftCutscene
