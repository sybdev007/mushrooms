--!strict
-- Cutscenka z kradzieżą (samouczek, po pierwszym posadzeniu grzyba):
--   1. sadzenie: gracz klęka przy grządce, rozgrzebuje ziemię, wkłada grzybek, klepie, wstaje — grzyb wyrasta z błyskiem
--   2. gotowe: ociera pot z czoła: „Gotowe! Teraz po olej i w las.” i wychodzi przez furtkę
--   3. zza rogu chatki: złodziejaszek wychyla się, chowa, wychyla jeszcze raz, chichocze i zaciera ręce
--   4. skradanie na paluszkach: przy furtce rozgląda się i robi „ćśś”, podkrada się do grządki i szarpie grzyba
--   5. zgrzyt płyty: gracz wraca biegiem: „Hej! Zostaw to!”. Złodziej podskakuje ze strachu, ucieka,
--      przeskakuje płot, ląduje na twarzy i zwiewa
--   6. gracz go przegania, otrzepuje ręce i sprawdza, czy grzybek jest cały. Potem okna z wyjaśnieniem kradzieży.
-- Pozycje są liczone w układzie ogródka (furtka, grządki, płot) i z prawdziwych ścian chatki,
-- więc nikt nie wchodzi w dom, w płot ani w grzyby, bez względu na to, który ogródek ma gracz.

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
local tween = Kit.tween

local SOUNDS = {
	"clues", "hall", "sneak", "pat", "plant", "gasp", "bubble", "blip", "surprise", "loony", "boom", "footstep", "crack",
	"whoosh", "leaves", "coin", "pick", "dig", "grow", "tiptoe", "scratch", "slide", "bodyfall", "pant", "shimmer",
}

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

-- ===== Efekty =====

local function puff(where: Vector3, color: Color3, count: number, up: number?)
	local holder = Instance.new("Attachment")
	holder.WorldPosition = where
	holder.Parent = Workspace.Terrain
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(color)
	e.Size = NumberSequence.new(0.5, 1.2)
	e.Transparency = NumberSequence.new(0.2, 1)
	e.Lifetime = NumberRange.new(0.35, 0.7)
	e.Speed = NumberRange.new(2, (up or 4))
	e.SpreadAngle = Vector2.new(60, 60)
	e.EmissionDirection = Enum.NormalId.Top
	e.Acceleration = Vector3.new(0, -10, 0)
	e.Rate = 0
	e.Parent = holder
	e:Emit(count)
	task.delay(1.2, function()
		holder:Destroy()
	end)
end

local function sparkle(where: Vector3, count: number)
	local holder = Instance.new("Attachment")
	holder.WorldPosition = where
	holder.Parent = Workspace.Terrain
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 140)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(150, 255, 160)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
	})
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new(0, 1)
	e.Lifetime = NumberRange.new(0.6, 1.1)
	e.Speed = NumberRange.new(3, 7)
	e.SpreadAngle = Vector2.new(80, 80)
	e.EmissionDirection = Enum.NormalId.Top
	e.Drag = 2
	e.Acceleration = Vector3.new(0, -3, 0)
	e.RotSpeed = NumberRange.new(-180, 180)
	e.Rate = 0
	e.Parent = holder
	e:Emit(count)
	task.delay(1.5, function()
		holder:Destroy()
	end)
end

-- Kropla potu odlatuje z czoła
local function sweatDrop(actor: Kit.Actor)
	local head = actor.head
	if not head then
		return
	end
	local drop = Instance.new("Part")
	drop.Shape = Enum.PartType.Ball
	drop.Size = Vector3.new(0.28, 0.28, 0.28)
	drop.Color = Color3.fromRGB(150, 210, 255)
	drop.Material = Enum.Material.Glass
	drop.Transparency = 0.15
	drop.CanCollide = false
	drop.CanQuery = false
	drop.CanTouch = false
	drop.Anchored = true
	drop.CFrame = head.CFrame * CFrame.new(0.45, 0.55, -0.35)
	drop.Parent = Workspace
	local start = drop.Position
	local right = head.CFrame.RightVector
	local t0 = os.clock()
	local fly: RBXScriptConnection? = nil
	fly = RunService.RenderStepped:Connect(function()
		local k = (os.clock() - t0) / 0.6
		drop.Position = start + right * k * 1.6 + Vector3.new(0, math.sin(k * math.pi) * 0.8 - k * 1.2, 0)
		if k >= 1 then
			if fly then
				fly:Disconnect()
			end
			drop:Destroy()
		end
	end)
end

-- ===== Geometria sceny =====

local function cabinWalls(): (Vector3?, Vector3?)
	local map = Workspace:FindFirstChild("Map")
	local cabin = map and map:FindFirstChild("Cabin")
	if not cabin then
		return nil, nil
	end
	local minV = Vector3.new(math.huge, 0, math.huge)
	local maxV = Vector3.new(-math.huge, 0, -math.huge)
	local any = false
	for _, p in cabin:GetChildren() do
		-- Ściany są z bali; dach i ganek pomijamy (wysoko albo płasko)
		if p.Name == "Log" and p:IsA("BasePart") and p.Position.Y < 12 then
			local cf, sz = p.CFrame, p.Size
			for _, sx in { -1, 1 } do
				for _, szz in { -1, 1 } do
					local v = (cf * CFrame.new(sx * sz.X / 2, 0, szz * sz.Z / 2)).Position
					minV = Vector3.new(math.min(minV.X, v.X), 0, math.min(minV.Z, v.Z))
					maxV = Vector3.new(math.max(maxV.X, v.X), 0, math.max(maxV.Z, v.Z))
					any = true
				end
			end
		end
	end
	if not any then
		return nil, nil
	end
	return minV, maxV
end

local function groundAt(v: Vector3, fallback: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	if player.Character then
		table.insert(ignore, player.Character)
	end
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(Vector3.new(v.X, fallback + 8, v.Z), Vector3.new(0, -20, 0), params)
	return if hit then hit.Position.Y else fallback
end

-- Czy w tym miejscu stoi coś wyższego niż trawa (płot, skrzynia, tablica…)
local function blocked(at: Vector3, size: Vector3, groundY: number): boolean
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	if player.Character then
		params.FilterDescendantsInstances = { player.Character }
	end
	for _, p in Workspace:GetPartBoundsInBox(CFrame.new(at.X, groundY + size.Y / 2 + 0.4, at.Z), size, params) do
		-- Niskie rzeczy (podłoga, ganek, kamienie) da się przejść; liczy się to, co wyższe niż schodek
		if p.Transparency < 1 and p.CanCollide and p.Position.Y + p.Size.Y / 2 > groundY + 1.3 then
			return true
		end
	end
	return false
end

type Corner = { c: Vector3, n1: Vector3, n2: Vector3, y: number, center: Vector3 }

-- Róg chatki na kryjówkę: blisko furtki, z miejscem na złodzieja i kamerę.
-- n1 = ściana widoczna od strony ogródka (stąd patrzy kamera), n2 = ściana, za którą stoi złodziej.
local function pickCorner(gateOut: Vector3, groundY: number): Corner?
	local minV, maxV = cabinWalls()
	if not minV or not maxV then
		return nil
	end
	local best: Corner? = nil
	local bestScore = math.huge
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local c = Vector3.new(if sx < 0 then minV.X else maxV.X, 0, if sz < 0 then minV.Z else maxV.Z)
			local nx = Vector3.new(sx, 0, 0)
			local nz = Vector3.new(0, 0, sz)
			local toGate = flat(gateOut - c)
			local dir = toGate.Unit
			local n1, n2 = nx, nz
			if dir:Dot(nz) > dir:Dot(nx) then
				n1, n2 = nz, nx
			end
			local y = groundAt(c + n1 * 2 + n2 * 2, groundY)
			local hide = c + n2 * 1.9 - n1 * 1.5
			local eye = c + n1 * 6 - n2 * 4.5
			local score = toGate.Magnitude
			if blocked(hide, Vector3.new(1.6, 3.4, 1.6), y) then
				score += 60
			end
			if blocked(eye, Vector3.new(2, 2, 2), y + 1.5) then
				score += 30
			end
			if score < bestScore then
				bestScore = score
				best = { c = Vector3.new(c.X, y, c.Z), n1 = n1, n2 = n2, y = y, center = (minV + maxV) / 2 }
			end
		end
	end
	return best
end

-- ===== Scenariusz =====

local function scenario(s: Kit.Scene, garden: Model)
	local frame = garden:GetPivot()
	local grass = garden:FindFirstChild("GardenGrass")
	local groundY = if grass and grass:IsA("BasePart") then grass.Position.Y + grass.Size.Y / 2 else frame.Position.Y - 2.3
	-- Punkt na ziemi w układzie ogródka: x w poprzek, z w głąb (furtka na z = -6.5, grządki od z = 4.8)
	local function P(x: number, z: number, y: number?): Vector3
		local p = (frame * CFrame.new(x, 0, z)).Position
		return Vector3.new(p.X, groundY + (y or 0), p.Z)
	end
	local function localOf(v: Vector3): Vector3
		return frame:PointToObjectSpace(v)
	end
	local inward = frame:VectorToWorldSpace(Vector3.new(0, 0, 1))
	local across = frame:VectorToWorldSpace(Vector3.new(1, 0, 0))

	-- Grzyb, którym się zajmujemy: posadzony najbliżej furtki (najlepiej w środkowym rzędzie)
	local folder = garden:FindFirstChild("Planted")
	local plant: Model? = nil
	local bx, bz = 0, 4.8
	if folder then
		local bestScore = math.huge
		for _, child in folder:GetChildren() do
			if child:IsA("Model") then
				local l = localOf(child:GetPivot().Position)
				local score = l.Z * 10 + math.abs(l.X)
				if score < bestScore then
					bestScore = score
					plant = child
					bx, bz = l.X, l.Z
				end
			end
		end
	end
	if not plant then
		local slot = garden:FindFirstChild("Slot2", true)
		if slot and slot:IsA("Attachment") then
			local l = localOf(slot.WorldPosition)
			bx, bz = l.X, l.Z
		end
	end
	local bedCenter = P(bx, bz)

	-- Prawdziwe grzyby i tabliczki ogródków chowamy (tylko u siebie); gramy na kopii grzyba.
	-- Raz na starcie, a potem tylko to, co dojdzie w trakcie (wcześniej co ćwierć sekundy przeszukiwało
	-- wszystkie ogródki i scenka gubiła klatki)
	local hiddenParts: { [Instance]: boolean } = {}
	local hiddenOther: { [Instance]: boolean } = {}
	local function hidePlanted(d: Instance)
		if (d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture")) and not hiddenParts[d] then
			hiddenParts[d] = true;
			(d :: any).LocalTransparencyModifier = 1
		elseif (d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("BillboardGui") or d:IsA("Beam") or d:IsA("Trail")) and hiddenOther[d] == nil then
			hiddenOther[d] = (d :: any).Enabled;
			(d :: any).Enabled = false
		end
	end
	local function hideSign(d: Instance)
		if d:IsA("BillboardGui") and hiddenOther[d] == nil then
			hiddenOther[d] = d.Enabled
			d.Enabled = false
		end
	end
	if folder then
		for _, d in folder:GetDescendants() do
			hidePlanted(d)
		end
		table.insert(s.connections, folder.DescendantAdded:Connect(hidePlanted))
	end
	for _, g in CollectionService:GetTagged("GardenPlot") do
		for _, d in g:GetDescendants() do
			hideSign(d)
		end
		table.insert(s.connections, g.DescendantAdded:Connect(hideSign))
	end
	-- Tabliczki z dochodem nad grzybami (GardenSlotTag) wiszą w PlayerGui, a nie w ogródku
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		for _, d in playerGui:GetDescendants() do
			hideSign(d)
		end
		table.insert(s.connections, playerGui.DescendantAdded:Connect(hideSign))
	end
	Kit.onCleanup(s, function()
		for d in hiddenParts do
			if d.Parent then
				(d :: any).LocalTransparencyModifier = 0
			end
		end
		for d, was in hiddenOther do
			if d.Parent then
				(d :: any).Enabled = was
			end
		end
	end)

	-- Kopia grzyba: rośnie, chwieje się i podskakuje bez ruszania prawdziwego modelu
	local fake: Model? = nil
	local fakeBase: CFrame? = nil
	local fakeDrop = 0
	-- Grzyby w ogródku to duże modele pomniejszone przez ScaleTo: skala kopii liczy się od tej
	-- skali, a nie od 1 (inaczej kopia rosła do pełnego rozmiaru modelu i zasłaniała pół ekranu)
	local fakeBaseScale = 1
	if plant then
		plant.Archivable = true
		local copy = plant:Clone()
		if copy then
			for _, d in copy:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
					d.LocalTransparencyModifier = 0
				elseif d:IsA("Decal") or d:IsA("Texture") then
					d.LocalTransparencyModifier = 0
				elseif d:IsA("BillboardGui") then
					d:Destroy()
				end
			end
			-- Bez etykiet (np. „GardenMushroom”): inaczej widok grzybów ogródka brał kopię za nowy grzyb
			-- i doklejał do niej drugi, olbrzymi model, który zasłaniał całą scenę
			for _, d in { copy :: Instance, table.unpack(copy:GetDescendants()) } do
				for _, tag in CollectionService:GetTags(d) do
					CollectionService:RemoveTag(d, tag)
				end
			end
			copy.Name = "CutsceneMushroom"
			copy.Parent = Workspace
			fake = copy
			fakeBaseScale = copy:GetScale()
			local base = copy:GetPivot()
			fakeBase = base
			local cf, size = copy:GetBoundingBox()
			fakeDrop = base.Position.Y - (cf.Position.Y - size.Y / 2)
			Kit.onCleanup(s, function()
				copy:Destroy()
			end)
		end
	end
	-- Skala grzyba od podstawy (k = 1 pełny rozmiar), lift = o ile wyciągnięty z ziemi
	local fakeScale = 1
	local function setFake(k: number, lift: number?, tilt: CFrame?)
		local m = fake
		local base = fakeBase
		if not m or not base then
			return
		end
		k = math.max(k, 0.02)
		-- ScaleTo przelicza cały model: nie w każdej klatce za drobną zmianę (to też gubiło klatki)
		if math.abs(k - fakeScale) > 0.025 or (k == 1 and fakeScale ~= 1) then
			m:ScaleTo(fakeBaseScale * k)
			fakeScale = k
		end
		m:PivotTo(base * CFrame.new(0, -(1 - k) * fakeDrop + (lift or 0), 0) * (tilt or CFrame.new()))
	end
	setFake(0.02)

	local hero = Kit.actor(s, { name = "Gardener" })
	local thief = Kit.actor(s, { name = "Thief", thief = true })
	if not hero or not thief then
		return
	end
	-- Złodziej czeka poza kadrem
	Kit.place(thief, P(0, -400), inward)

	local heroSpot = P(bx, bz - 2.55)
	Kit.place(hero, heroSpot, inward)

	-- Strona, w którą gracz odchodzi: przeciwna do rogu chatki ze złodziejem
	local gateOut = P(0, -9.6)
	local corner = pickCorner(gateOut, groundY)
	local cornerSide = 1
	if corner then
		cornerSide = if localOf(corner.c).X >= 0 then 1 else -1
	end
	local heroSide = -cornerSide

	-- Noc w ogródku: trochę jaśniej i ciepłe światło nad grządką, żeby było widać miny
	local Lighting = game:GetService("Lighting")
	if Lighting.ClockTime < 6.5 or Lighting.ClockTime > 17.5 then
		Lighting.ExposureCompensation = math.max(Lighting.ExposureCompensation, 0) + 0.2
	end
	local function fill(where: Vector3, color: Color3, range: number, brightness: number)
		local a = Instance.new("Attachment")
		a.WorldPosition = where
		a.Parent = Workspace.Terrain
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = range
		light.Brightness = brightness
		light.Shadows = false
		light.Parent = a
		Kit.onCleanup(s, function()
			a:Destroy()
		end)
	end
	fill(P(bx - 7, bz - 7, 11), Color3.fromRGB(255, 214, 160), 24, 0.9)
	fill(P(5, -9, 10), Color3.fromRGB(190, 210, 255), 20, 0.6)
	if corner then
		fill(Vector3.new(corner.c.X, corner.y + 8, corner.c.Z) + corner.n1 * 7 - corner.n2 * 2, Color3.fromRGB(190, 210, 255), 20, 0.6)
	end

	-- ===== 1. Sadzenie =====
	Kit.phase(s, "plant")
	Kit.letterbox(s, true, 0.01)
	Kit.loop(s, "forest", 0.35)
	Kit.shot(s, look(P(bx - 6.5, bz - 7.5, 3.4), P(bx - 0.2, bz - 1.3, 0.9)), look(P(bx - 5.4, bz - 6.4, 3.0), P(bx - 0.1, bz - 1.2, 1.0)), 3.6, 50)
	Kit.fade(s, false, 0.8)
	Kit.clip(hero, Clips.plantSeed, {
		fade = 0.2,
		events = function(name)
			if name == "dig" then
				Audio.play("dig", { volume = 0.7, jitter = 0.1, duration = 0.5 })
				puff(bedCenter + Vector3.new(0, 0.9, 0) - inward * 0.6, Color3.fromRGB(92, 64, 40), 8)
			elseif name == "place" then
				Audio.play("plant", { volume = 0.7, duration = 1 })
				setFake(0.18)
			elseif name == "pat" then
				Audio.play("pat", { volume = 0.6, jitter = 0.12, duration = 0.3 })
				puff(bedCenter + Vector3.new(0, 0.9, 0) - inward * 0.5, Color3.fromRGB(110, 78, 50), 4, 2.5)
			end
		end,
	})
	if not Kit.wait(s, 3.4) then
		return
	end
	-- Krok w tył i grzyb wyrasta z błyskiem
	Kit.clip(hero, nil, { fade = 0.2 })
	Kit.track(hero, "idle")
	local backTo = P(bx, bz - 3.6) + Vector3.new(0, hero.hip, 0)
	tween(hero.rootValue, 0.45, { Value = CFrame.lookAt(backTo, backTo + inward) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	Kit.shot(s, look(P(bx - 3.6, bz - 4.6, 2.6), P(bx, bz, 1.2)), look(P(bx - 3.1, bz - 4.0, 2.3), P(bx, bz, 1.4)), 1.8, 48)
	if not Kit.wait(s, 0.35) then
		return
	end
	Audio.play("grow", { volume = 0.8, duration = 2 })
	Audio.play("pick", { volume = 0.8 })
	local growStart = os.clock()
	local grow: RBXScriptConnection? = nil
	grow = RunService.RenderStepped:Connect(function()
		local k = math.clamp((os.clock() - growStart) / 0.85, 0, 1)
		-- Sprężyste wyrastanie (lekko ponad rozmiar i z powrotem)
		local e = 1 - math.pow(1 - k, 3)
		local over = math.sin(k * math.pi) * 0.18
		setFake(0.18 + (1 - 0.18) * e + over * (1 - k * 0.5))
		if k >= 1 then
			setFake(1)
			if grow then
				grow:Disconnect()
			end
		end
	end)
	table.insert(s.connections, grow :: RBXScriptConnection)
	sparkle(bedCenter + Vector3.new(0, 1.2, 0), 40)
	puff(bedCenter + Vector3.new(0, 1, 0), Color3.fromRGB(120, 90, 60), 10)
	if not Kit.wait(s, 1.5) then
		return
	end

	-- ===== 2. Gotowe: pot z czoła =====
	Kit.phase(s, "done")
	Kit.face(hero, P(bx, bz - 12), 0.35)
	-- Z boku, żeby za plecami było widać świeżo posadzony grzyb
	Kit.shot(s, look(P(bx + 3.6, -5.6, 3.1), P(bx + 0.5, bz - 2.6, 2.0)), look(P(bx + 3.2, -5.0, 3.0), P(bx + 0.5, bz - 2.6, 2.1)), 4, 46)
	if not Kit.wait(s, 0.35) then
		return
	end
	Kit.clip(hero, Clips.wipeSweat, {
		fade = 0.15,
		events = function(name)
			if name == "sweat" then
				sweatDrop(hero)
				Audio.play("whoosh", { volume = 0.25, pitch = 1.7 })
			elseif name == "sigh" then
				Audio.play("gasp", { volume = 0.45, pitch = 0.85 })
			end
		end,
	})
	if not Kit.wait(s, 1.9) then
		return
	end
	if not Kit.bubble(s, hero, Localize.t("CUT2_DONE"), 1.2, false, nil, 1.15) then
		return
	end

	-- ===== Wychodzi przez furtkę =====
	Kit.phase(s, "leave")
	Kit.clip(hero, nil, { fade = 0.3 })
	Kit.shot(s, look(P(bx - 3.2 * heroSide, bz + 3.2, 3.8), P(0, -7.5, 1.8)), look(P(bx - 2.8 * heroSide, bz + 2.6, 3.6), P(heroSide * 3, -9, 1.8)), 3, 50)
	Kit.path(s, hero, { P(bx * 0.4, -3.2), P(0, -5.5), P(0, -9.4), P(heroSide * 14, -9.8) }, 8, "walk", 0.85)
	local steps = task.spawn(function()
		while not s.cancelled do
			Audio.play("footstep", { volume = 0.4, jitter = 0.12 })
			task.wait(0.36)
		end
	end)
	if not Kit.wait(s, 2.9) then
		task.cancel(steps)
		return
	end
	task.cancel(steps)

	-- ===== 3. Zza rogu chatki: złodziej =====
	Kit.phase(s, "peek")
	Kit.place(hero, P(0, -400), inward)
	Audio.music("clues", 0.4)
	local c = if corner then corner.c else P(cornerSide * 10, -14)
	local n1 = if corner then corner.n1 else -inward
	local n2 = if corner then corner.n2 else across * cornerSide
	local cy = if corner then corner.y else groundY
	local function at(v: Vector3, y: number?): Vector3
		return Vector3.new(v.X, cy + (y or 0), v.Z)
	end
	local hide = at(c + n2 * 1.9 - n1 * 1.5)
	Kit.place(thief, hide, n1)
	Kit.expression(thief, "smirk")
	Kit.eyes(thief, 0, 0)
	local edge = at(c + n2 * 1.6 - n1 * 0.4)
	Kit.shot(s, look(at(c + n1 * 6 - n2 * 4.5, 2.6), edge + Vector3.new(0, 2.0, 0)), look(at(c + n1 * 5.2 - n2 * 4.0, 2.4), edge + Vector3.new(0, 2.1, 0)), 4.6, 44)
	Audio.play("leaves", { volume = 0.5, duration = 1.2 })
	Kit.clip(thief, Clips.peekOut, {
		fade = 0.15,
		events = function(name)
			if name == "peek" then
				Kit.eyes(thief, -1, 0.2, 0.15)
				task.delay(0.35, function()
					Kit.eyes(thief, 1, 0.2, 0.2)
				end)
			elseif name == "hide" then
				Audio.play("whoosh", { volume = 0.2, pitch = 2.2 })
				Kit.eyes(thief, 0, 0, 0.1)
			elseif name == "rub" then
				Kit.expression(thief, "grin")
				Kit.eyes(thief, 0, -0.3, 0.2)
			elseif name == "hehe" then
				for i = 0, 3 do
					task.delay(i * 0.15, function()
						Audio.play("blip", { volume = 0.35, pitch = 0.7 + (i % 2) * 0.12 })
					end)
				end
			end
		end,
	})
	if not Kit.wait(s, 2.4) then
		return
	end
	task.spawn(function()
		Kit.bubble(s, thief, Localize.t("CUT2_THIEF"), 1.0, false, nil, 0.72)
	end)
	if not Kit.wait(s, 2.4) then
		return
	end

	-- ===== 4. Skradanie =====
	Kit.phase(s, "sneak")
	Kit.expression(thief, "smirk")
	local out = at(c + n1 * 1.8 + n2 * 2.0)
	local towardGate = flat(gateOut - out)
	towardGate = if towardGate.Magnitude > 0.1 then towardGate.Unit else n1
	local function sneakSteps(name: string)
		if name == "step" then
			Audio.play("tiptoe", { volume = 0.55, jitter = 0.15, duration = 0.4 })
			Audio.play("sneak", { volume = 0.35, jitter = 0.1, duration = 0.5 })
		end
	end
	Kit.clip(thief, Clips.sneak, { fade = 0.25, events = sneakSteps })
	Kit.path(s, thief, { out, out + towardGate * 5 }, 3.2)
	local sideways = towardGate:Cross(Vector3.yAxis)
	-- Kamera za plecami, lekko z boku, po stronie z dala od chatki (widać worek z „$” i drogę do ogródka)
	local cabinCenter = if corner then corner.center else c - n1 * 5 - n2 * 5
	if sideways:Dot(flat(out - cabinCenter)) < 0 then
		sideways = -sideways
	end
	Kit.follow(s, function()
		local p = thief.root.Position
		return look(p - towardGate * 5.5 + sideways * 2.2 + Vector3.new(0, 1.6, 0), p + towardGate * 4 + Vector3.new(0, 0.4, 0))
	end, 50)
	if not Kit.wait(s, 2.3) then
		return
	end

	-- Przy furtce: rozgląda się i „ćśś”
	Kit.phase(s, "gate")
	Kit.place(thief, P(cornerSide * 6, -9.6), -across * cornerSide)
	Kit.clip(thief, Clips.sneak, { fade = 0.1, events = sneakSteps })
	local toGate = Kit.path(s, thief, { P(cornerSide * 0.5, -9.6) }, 3.2)
	Kit.shot(s, look(P(-cornerSide * 2.6, -1.2, 3.3), P(cornerSide * 2, -9.6, 2.0)), look(P(-cornerSide * 2.2, -1.8, 3.1), P(cornerSide * 0.6, -9.6, 2.1)), toGate + 2.2, 50)
	if not Kit.wait(s, toGate) then
		return
	end
	Kit.face(thief, P(0, 0), 0.25)
	Kit.clip(thief, Clips.lookAround, {
		fade = 0.15,
		events = function(name)
			if name == "shh" then
				Kit.expression(thief, "shh")
				Audio.play("whoosh", { volume = 0.15, pitch = 2.4 })
			end
		end,
	})
	task.delay(0.3, function()
		Kit.eyes(thief, 1, 0, 0.15)
	end)
	task.delay(0.85, function()
		Kit.eyes(thief, -1, 0, 0.15)
	end)
	task.delay(1.3, function()
		Kit.eyes(thief, 0, 0, 0.15)
	end)
	if not Kit.wait(s, 2.3) then
		return
	end

	-- Podkrada się do grządki
	Kit.phase(s, "tiptoe")
	Kit.expression(thief, "grin")
	local tugSpot = P(bx, bz - 3.1)
	local camSide = if bx > 0.5 then 1 elseif bx < -0.5 then -1 else -cornerSide
	Kit.clip(thief, Clips.sneak, { fade = 0.1, events = sneakSteps })
	local toBed = Kit.path(s, thief, { P(0, -4.6), tugSpot }, 3.6)
	local tipEye = P(bx + camSide * 7, bz - 5.2, 3.4)
	Kit.follow(s, function()
		return look(tipEye, thief.root.Position + Vector3.new(0, 0.3, 0))
	end, 50)
	if not Kit.wait(s, toBed) then
		return
	end

	-- Szarpie grzyba
	Kit.phase(s, "tug")
	Kit.face(thief, bedCenter, 0.2)
	Kit.expression(thief, "shh")
	Audio.music(nil, 1.2)
	Kit.shot(s, look(P(bx + camSide * 5.8, bz - 2.4, 2.4), P(bx + camSide * 0.2, bz - 1.6, 1.3)), look(P(bx + camSide * 5.0, bz - 2.0, 2.2), P(bx + camSide * 0.1, bz - 1.4, 1.4)), 2.6, 50)
	local pull = Instance.new("NumberValue")
	local wobbleStart = os.clock()
	local wobble = RunService.RenderStepped:Connect(function()
		local t = os.clock() - wobbleStart
		local amount = math.clamp(t / 1.2, 0, 1) * 0.22
		setFake(1, pull.Value + math.abs(math.sin(t * 9)) * 0.12, CFrame.Angles(math.sin(t * 14) * amount, 0, math.sin(t * 11) * amount))
	end)
	table.insert(s.connections, wobble)
	Kit.clip(thief, Clips.tug, {
		fade = 0.2,
		events = function(name)
			if name == "tug" then
				thief.shake = 1
				task.delay(0.25, function()
					thief.shake = 0
				end)
				Audio.play("crack", { volume = 0.35, pitch = 1.6, duration = 0.35 })
				Audio.play("dig", { volume = 0.5, pitch = 1.2, duration = 0.4 })
				tween(pull, 0.25, { Value = pull.Value + 0.18 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				puff(bedCenter + Vector3.new(0, 0.9, 0), Color3.fromRGB(92, 64, 40), 6, 3)
				sweatDrop(thief)
				s.shake = math.max(s.shake, 0.12)
			end
		end,
	})
	task.delay(0.9, function()
		if not s.cancelled then
			Kit.bubble(s, thief, Localize.t("CUT2_TUG"), 0.6, false, nil, 0.7)
		end
	end)
	if not Kit.wait(s, 2.3) then
		return
	end

	-- ===== 5. Zgrzyt płyty: gracz wraca =====
	Kit.phase(s, "caught")
	Audio.play("scratch", { volume = 0.9, duration = 1.2 })
	s.shake = 0.3
	local heroAt = P(0, -4.2)
	Kit.place(hero, P(heroSide * 6.5, -9.6), -across * heroSide)
	Kit.path(s, hero, { P(0, -9.6), heroAt }, 14, "run", 1.3)
	do
		-- Szeroki kadr z boku: gracz przy furtce i złodziej przy grządce naraz
		local mid = (heroAt + tugSpot) / 2
		local line = flat(tugSpot - heroAt)
		local perp = if line.Magnitude > 0.1 then line.Unit:Cross(Vector3.yAxis) else across
		local reach = math.max(9.5, line.Magnitude * 1.15)
		local l = localOf(mid + perp * reach)
		if math.abs(l.X) > 11.5 or l.Z < -5.5 then
			perp = -perp
		end
		Kit.shot(s, look(mid + perp * reach + Vector3.new(0, 3.6, 0), mid + Vector3.new(0, 2.1, 0)), look(mid + perp * (reach - 0.8) + Vector3.new(0, 3.3, 0), mid + Vector3.new(0, 2.2, 0)), 1.4, 56)
	end
	task.delay(0.45, function()
		if not s.cancelled then
			Audio.play("surprise", { volume = 0.9, duration = 1.6 })
			Kit.bubble(s, hero, Localize.t("CUT2_HEY"), 1.0, false, nil, 1.1)
		end
	end)
	if not Kit.wait(s, 0.5) then
		return
	end
	-- Złodziej podskakuje ze strachu, grzyb wraca do ziemi
	wobble:Disconnect()
	pull.Value = 0
	setFake(1)
	Kit.face(thief, heroAt, 0.1)
	Kit.clip(thief, Clips.jumpScare, { fade = 0.05 })
	Kit.expression(thief, "o")
	Kit.eyes(thief, 0, 0)
	Kit.mark(s, thief, "!")
	Audio.play("loony", { volume = 0.8, duration = 2.2 })
	if not Kit.wait(s, 0.5) then
		return
	end
	Kit.track(hero, "idle")
	Kit.clip(hero, Clips.point, { fade = 0.1 })
	if not Kit.wait(s, 0.5) then
		return
	end
	task.spawn(function()
		Kit.bubble(s, thief, Localize.t("CUT2_OOPS"), 0.5, false, nil, 0.8)
	end)
	if not Kit.wait(s, 0.9) then
		return
	end

	-- ===== Ucieczka przez płot =====
	Kit.phase(s, "flee")
	local esc = if bx > 0.5 then 1 elseif bx < -0.5 then -1 else -heroSide
	if blocked(P(esc * 16, bz - 0.6), Vector3.new(3, 3, 3), groundY) and not blocked(P(-esc * 16, bz - 0.6), Vector3.new(3, 3, 3), groundY) then
		esc = -esc
	end
	Audio.music("hall", 0.2)
	Kit.clip(thief, nil, { fade = 0.12 })
	local run = Kit.path(s, thief, { P(esc * 8.8, bz - 2.8), P(esc * 11.2, bz - 1.4) }, 15, "run", 1.5)
	local fleeEye = P(esc * 3.5, bz - 7.5, 5.2)
	Kit.follow(s, function()
		return look(fleeEye, thief.root.Position + Vector3.new(0, 0.2, 0))
	end, 52)
	Audio.play("pant", { volume = 0.5, duration = 1.4, pitch = 1.3 })
	if not Kit.wait(s, run) then
		return
	end
	-- Hop przez płot
	Audio.play("slide", { volume = 0.8 })
	Kit.track(thief, nil)
	Kit.clip(thief, Clips.vault, { fade = 0.05 })
	Kit.hop(s, thief, P(esc * 15.6, bz - 1.0), 0.62, 3.4)
	if not Kit.wait(s, 0.62) then
		return
	end
	-- I prosto na twarz
	Kit.clip(thief, Clips.faceplant, {
		fade = 0.05,
		events = function(name)
			if name == "thud" then
				Audio.play("bodyfall", { volume = 0.9, duration = 1 })
				Audio.play("boom", { volume = 0.5 })
				puff(thief.root.Position - Vector3.new(0, 1.5, 0), Color3.fromRGB(150, 130, 100), 14, 3)
				s.shake = 0.5
				Kit.mark(s, thief, "✦", Color3.fromRGB(255, 220, 80))
			end
		end,
	})
	if not Kit.wait(s, 2.2) then
		return
	end
	Kit.clip(thief, nil, { fade = 0.1 })
	Kit.expression(thief, "o")
	Kit.path(s, thief, { P(esc * 34, bz + 4) }, 17, "run", 1.6)
	Audio.play("pant", { volume = 0.5, duration = 1.2, pitch = 1.4 })
	if not Kit.wait(s, 0.9) then
		return
	end

	-- ===== 6. Przeganianie =====
	Kit.phase(s, "shoo")
	local away = P(esc * 20, bz)
	Kit.face(hero, away, 0.2)
	local dir = flat(away - heroAt).Unit
	local camSide2 = dir:Cross(Vector3.yAxis)
	Kit.shot(s, look(heroAt + dir * 7.5 + camSide2 * 1.8 + Vector3.new(0, 3.1, 0), heroAt + Vector3.new(0, 2.4, 0)), look(heroAt + dir * 6.6 + camSide2 * 1.5 + Vector3.new(0, 3.0, 0), heroAt + Vector3.new(0, 2.5, 0)), 3.2, 48)
	Kit.clip(hero, Clips.shoo, {
		fade = 0.15,
		events = function(name)
			if name == "shoo" then
				Audio.play("whoosh", { volume = 0.35, pitch = 1.3, jitter = 0.1 })
			end
		end,
	})
	task.spawn(function()
		Kit.bubble(s, hero, Localize.t("CUT2_BYE"), 0.9, false, nil, 1.1)
	end)
	if not Kit.wait(s, 1.7) then
		return
	end
	Kit.clip(hero, Clips.dustHands, {
		fade = 0.15,
		events = function(name)
			if name == "pat" then
				Audio.play("pat", { volume = 0.5, pitch = 1.4, duration = 0.3 })
			end
		end,
	})
	if not Kit.wait(s, 1.2) then
		return
	end
	-- Na koniec spojrzenie na grzybek: cały
	Kit.face(hero, bedCenter, 0.3)
	Kit.shot(s, look(P(bx - camSide * 3.2, bz - 4.8, 2.8), P(bx, bz - 0.5, 1.3)), look(P(bx - camSide * 2.6, bz - 4.0, 2.5), P(bx, bz - 0.3, 1.4)), 2.4, 48)
	sparkle(bedCenter + Vector3.new(0, 1.6, 0), 18)
	Audio.play("shimmer", { volume = 0.5, duration = 1.5 })
	if not Kit.bubble(s, hero, Localize.t("CUT2_SAFE"), 0.9, true, nil, 1.1) then
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
