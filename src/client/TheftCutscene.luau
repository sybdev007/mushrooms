--!strict
-- Cutscenka z kradzieżą (samouczek, po pierwszym posadzeniu grzyba). Gra w osobnym ogródku
-- zbudowanym tylko u gracza (TheftStage, jak las ze snu w intro), więc każde ujęcie jest zaplanowane
-- i nic nie wchodzi w kadr, bez względu na to, który ogródek ma gracz.
--   1. Księżycowa noc, kamera zjeżdża nad ogródek. Gracz klęka przy grządce i sadzi grzyb.
--   2. Z grządki wyrasta złoty borowik z buzią (iskry). Gracz ociera pot: „Gotowe! Teraz po olej
--      i w las.” i wychodzi przez furtkę (kamera zza grządki, grzyb w kadrze).
--   3. Zza krzaka za płotem wychyla się złodziejaszek, chowa się, wychyla znowu, zaciera ręce:
--      „Hehe… ładne grzybki…”
--   4. Skrada się na paluszkach wzdłuż płotu, w prześwicie furtki rozgląda się i robi „ćśś”,
--      podkrada się do grządki.
--   5. Szarpie: „Nnngh… siedzi mocno!” (grzyb zaciska oczka) — i grzyb wyskakuje mu w rękę.
--   6. Z grzybem świeci na czerwono i idzie wolno (napis to tłumaczy). W furtce staje gracz: „Hej!
--      Zostaw to!”, a złodziej robi minę przyłapanego.
--   7. Gracz dobiega i dotyka złodzieja: błysk, grzyb wraca łukiem na grządkę (napis: dotknij złodzieja…).
--   8. Złodziej ucieka, przeskakuje płot i ląduje na twarzy. Gracz: „I nie wracaj!”
--   9. „Uff. Mój grzybek jest cały.” Kamera odjeżdża w górę nad ogródek. Potem okna samouczka.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Audio = require(script.Parent.Audio)
local Clips = require(script.Parent.CutsceneClips)
local Kit = require(script.Parent.CutsceneKit)
local Localize = require(script.Parent.Localize)
local MushroomView = require(script.Parent.MushroomView)
local TheftStage = require(script.Parent.TheftStage)

local TheftCutscene = {}

local look = Kit.look
local tween = Kit.tween
local at = TheftStage.at

local SOUNDS = {
	"clues", "hall", "sneak", "pat", "plant", "gasp", "bubble", "blip", "surprise", "loony", "boom", "footstep", "crack",
	"whoosh", "leaves", "coin", "pick", "dig", "grow", "tiptoe", "scratch", "slide", "bodyfall", "pant", "shimmer",
	"forest", "ping", "owl", "warn",
}

local DIRT = Color3.fromRGB(92, 64, 40)
local GOLD = Color3.fromRGB(236, 172, 44)
local PRIZE_SIZE = 0.82 -- borowik z MushroomView jest spory: tyle, żeby kapelusz nie zasłaniał głów postaci
local HELD_SCALE = 0.5 -- w ręce złodzieja (względem PRIZE_SIZE)

-- ===== Światło =====

-- Księżycowa noc: chłodna, ale postacie, grzyb i ogródek dobrze widać (Kit przywraca światło po
-- scenie, a próg poświaty oddajemy sami). Wyższy próg poświaty: przy takim świetle twarze i dłonie
-- świeciły na biało.
local function gardenNight(s: Kit.Scene)
	Lighting.ClockTime = 0.3
	Lighting.Brightness = 2.4
	Lighting.Ambient = Color3.fromRGB(116, 122, 170)
	Lighting.OutdoorAmbient = Color3.fromRGB(128, 136, 184)
	Lighting.ExposureCompensation = 0.3
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if bloom then
		local threshold = bloom.Threshold
		bloom.Threshold = math.max(threshold, 1.6)
		Kit.onCleanup(s, function()
			bloom.Threshold = threshold
		end)
	end
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Density = 0.28
		atmosphere.Color = Color3.fromRGB(46, 54, 98)
		atmosphere.Haze = 1.1
		atmosphere.Glare = 0
	end
	local color = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if color then
		color.TintColor = Color3.fromRGB(214, 222, 255)
		color.Saturation = 0.06
		color.Contrast = 0.14
		color.Brightness = 0.02
	end
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

local function sparkle(where: Vector3, count: number, color: Color3?)
	local holder = Instance.new("Attachment")
	holder.WorldPosition = where
	holder.Parent = Workspace.Terrain
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = if color
		then ColorSequence.new(color)
		else ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 140)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 210, 90)),
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

-- Kroki w tle, dopóki ich nie zatrzymamy
local function footsteps(s: Kit.Scene, every: number, volume: number): thread
	return task.spawn(function()
		while not s.cancelled do
			Audio.play("footstep", { volume = volume, jitter = 0.12 })
			task.wait(every)
		end
	end)
end

-- ===== Złoty grzyb =====

-- Złoty borowik w tej samej grafice co grzyby w grze (MushroomView: warstwowy kapelusz, buzia na
-- nóżce). MushroomView buduje go raz, a scenka bierze kopię, którą przesuwa i skaluje sama
-- (oryginał MushroomView by unosił). Bez aury: krąg i krążące świetliki ruszają się tylko w pętli
-- MushroomView, w kopii stałyby w miejscu. Kapelusz bez neonu, żeby z bliska miał cienie, a nie był
-- płaską żółtą plamą. Niewidzialny PrimaryPart leży pod nóżką (rośnie od podstawy), a jego przód
-- (LookVector) to strona z buzią.
local AURA_PARTS = { Orbit = true, RingGlow = true, RingPiece = true, RingRipple = true }

local function prizeMushroom(where: Vector3, parent: Instance): Model
	local id = "cut_theft_prize"
	MushroomView.add({ { id = id, position = where, species = "porcini", variant = "gold" } }, { decorative = true, grow = false, parent = parent })
	local built = parent:FindFirstChild(id)
	local model = if built and built:IsA("Model") then built:Clone() else Instance.new("Model")
	MushroomView.forget(id)
	model.Name = "CutsceneMushroom"
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			if AURA_PARTS[d.Name] then
				d:Destroy()
			else
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.CastShadow = false
				if d.Name == "Cap" then
					d.Material = Enum.Material.SmoothPlastic
					d.Color = GOLD:Lerp(d.Color, 0.25)
				end
			end
		elseif d:IsA("BillboardGui") or d:IsA("Beam") then
			d:Destroy()
		elseif d:IsA("PointLight") then
			d.Color = Color3.fromRGB(255, 200, 100)
			d.Range = 9
			d.Brightness = 1.2
		end
	end
	local stem = model:FindFirstChild("Stem", true)
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = CFrame.new(where) * (if stem and stem:IsA("BasePart") then stem.CFrame.Rotation else CFrame.identity)
	root.Parent = model
	model.PrimaryPart = root
	if not model:FindFirstChildWhichIsA("ParticleEmitter", true) then
		local glitter = Instance.new("ParticleEmitter")
		glitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		glitter.Rate = 4
		glitter.Lifetime = NumberRange.new(0.6, 1.2)
		glitter.Speed = NumberRange.new(0.4, 1.2)
		glitter.SpreadAngle = Vector2.new(180, 180)
		glitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.3), NumberSequenceKeypoint.new(1, 0) })
		glitter.LightEmission = 1
		glitter.Color = ColorSequence.new(Color3.fromRGB(255, 236, 150))
		glitter.Parent = stem or root
	end
	return model
end

-- Oczka grzyba: zaciśnięte (kiedy złodziej go szarpie i niesie) albo zwykłe
local function squint(model: Model, on: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Eye" then
			local normal = d:GetAttribute("NormalSize")
			if typeof(normal) ~= "Vector3" then
				normal = d.Size
				d:SetAttribute("NormalSize", normal)
			end
			local k = d.Size.Z / (normal :: Vector3).Z -- bieżąca skala modelu (ScaleTo zmienia też oczka)
			local base = (normal :: Vector3) * k
			d.Size = if on then Vector3.new(base.X * 1.5, base.Y * 0.3, base.Z) else base
		end
	end
end

-- ===== Scenariusz =====

local function scenario(s: Kit.Scene)
	local stage = TheftStage.build()
	Kit.onCleanup(s, function()
		stage:Destroy()
	end)
	local hero = Kit.actor(s, { name = "Gardener" })
	local thief = Kit.actor(s, { name = "Thief", thief = true })
	if not hero or not thief then
		return
	end
	gardenNight(s)

	local bedZ = TheftStage.BED_Z
	local soil = at(0, bedZ, TheftStage.SOIL_Y)
	local plantSpot = at(0, bedZ - 2.55)
	local forward = Vector3.new(0, 0, 1)

	-- Złoty grzyb: na razie maleńki i schowany w ziemi. Buzią w stronę furtki, lekko w lewo
	-- (stamtąd patrzy większość ujęć).
	local prize = prizeMushroom(soil, stage)
	prize.Parent = stage
	local prizeBase = CFrame.lookAt(soil, soil + Vector3.new(-0.45, 0, -0.9))
	local prizeScale = 1
	local function setPrize(k: number, lift: number?, tilt: CFrame?)
		k = math.max(k, 0.02)
		if math.abs(k - prizeScale) > 0.02 or (k == 1 and prizeScale ~= 1) then
			prize:ScaleTo(k * PRIZE_SIZE)
			prizeScale = k
		end
		prize:PivotTo(prizeBase * CFrame.new(0, lift or 0, 0) * (tilt or CFrame.identity))
	end
	setPrize(0.02, -0.3)

	-- Czerwona poświata złodzieja z cudzym grzybem (tak jak w grze)
	local glow = Instance.new("Highlight")
	glow.FillColor = Color3.fromRGB(255, 50, 50)
	glow.FillTransparency = 0.55
	glow.OutlineColor = Color3.fromRGB(255, 120, 110)
	glow.OutlineTransparency = 0
	glow.DepthMode = Enum.HighlightDepthMode.Occluded
	glow.Enabled = false
	glow.Parent = thief.model
	local redLight = Instance.new("PointLight")
	redLight.Color = Color3.fromRGB(255, 70, 60)
	redLight.Range = 10
	redLight.Brightness = 0
	redLight.Parent = thief.root

	Kit.place(thief, at(-200, -200), forward)
	Kit.place(hero, plantSpot, forward)

	-- ===== 1. Noc nad ogródkiem i sadzenie =====
	Kit.phase(s, "plant")
	Kit.letterbox(s, true, 0.01)
	Kit.loop(s, "forest", 0.35)
	-- Najpierw czarny ekran z podpisem (jak w intro). Kamera już stoi nad ogródkiem, bo światło
	-- w świeżo zbudowanym, dalekim ogródku układa się dopiero po chwili (inaczej pierwsze ujęcia
	-- byłyby ciemne i jaśniały na oczach gracza).
	local opening = look(at(-3, -27, 15), at(0, 4, 1))
	Kit.shot(s, opening, nil, 0, 50)
	Kit.caption(s, Localize.t("CUT2_TITLE"), true, 1.0)
	if not Kit.wait(s, 2.2) then
		return
	end
	Kit.caption(s, Localize.t("CUT2_TITLE"), false, 0.7)
	Kit.shot(s, opening, look(at(-2.2, -13, 7.5), at(0, 3, 1.6)), 4.2, 50, Enum.EasingStyle.Quad)
	Kit.fade(s, false, 1.4)
	task.delay(1.4, function()
		if not s.cancelled then
			Audio.play("owl", { volume = 0.45 })
		end
	end)
	if not Kit.wait(s, 2.6) then
		return
	end
	-- Zza grządki, na twarz klęczącego gracza (w tle furtka i latarnia przy dróżce)
	Kit.shot(s, look(at(3.8, bedZ + 5.8, 3.4), at(0, bedZ - 1.9, 2.0)), look(at(3.3, bedZ + 5.1, 3.2), at(0, bedZ - 1.9, 2.0)), 3.6, 42)
	Kit.clip(hero, Clips.plantSeed, {
		fade = 0.2,
		events = function(name)
			if name == "dig" then
				Audio.play("dig", { volume = 0.7, jitter = 0.1, duration = 0.5 })
				puff(soil + Vector3.new(0, 0.3, -0.6), DIRT, 8)
			elseif name == "place" then
				Audio.play("plant", { volume = 0.7, duration = 1 })
				setPrize(0.16, -0.05)
			elseif name == "pat" then
				Audio.play("pat", { volume = 0.6, jitter = 0.12, duration = 0.3 })
			end
		end,
	})
	if not Kit.wait(s, 3.3) then
		return
	end

	-- ===== 2. Złoty grzyb wyrasta =====
	Kit.phase(s, "grow")
	Kit.clip(hero, nil, { fade = 0.3 })
	-- Gracz obchodzi grządkę i staje z boku, żeby nie zasłaniać grzyba
	local admire = at(2.8, bedZ + 0.4)
	local aside = Kit.path(s, hero, { at(2.9, bedZ - 2.4), admire }, 7, "walk", 0.9)
	task.delay(aside, function()
		Kit.track(hero, "idle")
		Kit.face(hero, soil, 0.2)
	end)
	-- Nisko, przed grządką: grzyb wyrasta buzią do nas, gracz patrzy z boku, w tle okna chatki
	Kit.shot(s, look(at(-1.6, bedZ - 6.4, 1.5), at(0.6, bedZ, 2.0)), look(at(-1.4, bedZ - 5.6, 1.7), at(0.6, bedZ, 2.3)), 2.2, 46)
	if not Kit.wait(s, 0.45) then
		return
	end
	Audio.play("grow", { volume = 0.8, duration = 1.4 })
	Audio.play("shimmer", { volume = 0.5, duration = 1.5 })
	local growStart = os.clock()
	local grow: RBXScriptConnection? = nil
	grow = RunService.RenderStepped:Connect(function()
		local k = math.clamp((os.clock() - growStart) / 0.9, 0, 1)
		-- Sprężyste wyrastanie (lekko ponad rozmiar i z powrotem)
		local e = 1 - math.pow(1 - k, 3)
		local over = math.sin(k * math.pi) * 0.16
		setPrize(0.16 + (1 - 0.16) * e + over * (1 - k * 0.5))
		if k >= 1 then
			setPrize(1)
			if grow then
				grow:Disconnect()
			end
		end
	end)
	table.insert(s.connections, grow :: RBXScriptConnection)
	sparkle(soil + Vector3.new(0, 1.2, 0), 40)
	puff(soil + Vector3.new(0, 0.4, 0), DIRT, 10)
	if not Kit.wait(s, 1.6) then
		return
	end

	-- ===== Gotowe: pot z czoła i wyjście =====
	Kit.phase(s, "done")
	Kit.face(hero, at(1.3, -12), 0.35)
	-- Przed graczem, za jego plecami złoty grzyb na grządce
	Kit.shot(s, look(at(5.8, bedZ - 7.6, 3.4), at(1.2, bedZ - 1.0, 2.4)), look(at(5.3, bedZ - 6.9, 3.2), at(1.2, bedZ - 0.8, 2.5)), 3.4, 46)
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
	if not Kit.wait(s, 1.8) then
		return
	end
	if not Kit.bubble(s, hero, Localize.t("CUT2_DONE"), 1.0, false, nil, 1.15) then
		return
	end

	Kit.phase(s, "leave")
	Kit.clip(hero, nil, { fade = 0.3 })
	-- Zza grządki: złoty grzyb z lewej, gracz odchodzi przez furtkę w noc
	Kit.shot(s, look(at(3.2, bedZ + 6.2, 3.2), at(-0.6, -9, 1.6)), look(at(2.9, bedZ + 5.6, 3.4), at(-0.4, -12, 1.8)), 3.2, 48)
	Kit.path(s, hero, { at(2.9, bedZ - 2.4), at(0.8, -4.5), at(0, -10.2), at(0, -16), at(2.5, -24) }, 7.5, "walk", 0.9)
	local steps = footsteps(s, 0.38, 0.35)
	if not Kit.wait(s, 2.9) then
		task.cancel(steps)
		return
	end
	task.cancel(steps)
	Kit.place(hero, at(0, -300), forward)

	-- ===== 3. Zza krzaka: złodziej =====
	Kit.phase(s, "peek")
	Audio.music("clues", 0.4)
	-- Kamera za płotem, przy rogu ogródka: krzak przed nami, płot po prawej prowadzi do chatki
	local bush = TheftStage.BUSH
	local peekEye = at(-12.6, -13.2, 2.9)
	local toBush = Vector3.new(bush.X - (-12.6), 0, bush.Z - (-13.2)).Unit
	local hide = at(bush.X + toBush.X * 2.2, bush.Z + toBush.Z * 2.2)
	Kit.place(thief, hide, -toBush)
	Kit.expression(thief, "smirk")
	Kit.eyes(thief, 0, 0)
	Kit.shot(s, look(peekEye, hide + Vector3.new(0, 3.3, 0)), look(peekEye + toBush * 1.2 + Vector3.new(0, -0.2, 0), hide + Vector3.new(0, 3.2, 0)), 4.4, 38)
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
	if not Kit.wait(s, 2.3) then
		return
	end
	task.spawn(function()
		Kit.bubble(s, thief, Localize.t("CUT2_THIEF"), 1.0, false, nil, 0.72)
	end)
	if not Kit.wait(s, 2.5) then
		return
	end

	-- ===== 4. Skradanie wzdłuż płotu =====
	Kit.phase(s, "sneak")
	Kit.expression(thief, "smirk")
	local function sneakSteps(name: string)
		if name == "step" then
			Audio.play("tiptoe", { volume = 0.55, jitter = 0.15, duration = 0.4 })
			Audio.play("sneak", { volume = 0.35, jitter = 0.1, duration = 0.5 })
		end
	end
	Kit.clip(thief, Clips.sneak, { fade = 0.25, events = sneakSteps })
	Kit.path(s, thief, { at(-13.6, -7.4), at(-13.4, -10.2) }, 3.6)
	local sneakEye = at(-6.0, -19.5, 3.4)
	Kit.follow(s, function()
		return look(sneakEye, thief.root.Position + Vector3.new(0, 0.4, 0))
	end, 46)
	if not Kit.wait(s, 2.4) then
		return
	end

	-- Przy furtce: rozgląda się i „ćśś” (ujęcie ze środka ogródka: wchodzi za płotem i staje
	-- w samym prześwicie furtki, słupki i belka robią mu ramkę)
	Kit.phase(s, "gate")
	Kit.place(thief, at(-6.4, -13.6), Vector3.new(1, 0, 0))
	Kit.clip(thief, Clips.sneak, { fade = 0.1, events = sneakSteps })
	local toGate = Kit.path(s, thief, { at(-2.8, -13.3), at(-1.0, -12.5) }, 3.2)
	Kit.shot(s, look(at(2.4, -4.6, 3.0), at(-1.0, -12.4, 2.7)), look(at(2.1, -5.1, 2.9), at(-1.1, -12.5, 2.7)), toGate + 2.4, 48)
	if not Kit.wait(s, toGate) then
		return
	end
	Kit.face(thief, at(0, 0), 0.25)
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

	-- Przez furtkę w głąb ogródka (z boku), a potem to samo ujęcie zza grzyba co przy wyjściu gracza
	Kit.phase(s, "tiptoe")
	Kit.expression(thief, "grin")
	Kit.clip(thief, Clips.sneak, { fade = 0.1, events = sneakSteps })
	Kit.path(s, thief, { at(-0.4, -11.2), at(0, -6.2) }, 3.8)
	local sideEye = at(-7.2, -6.0, 3.6)
	Kit.follow(s, function()
		return look(sideEye, thief.root.Position + Vector3.new(0, 0.3, 0))
	end, 48)
	if not Kit.wait(s, 1.9) then
		return
	end
	-- Podchodzi do grzyba z boku grządki (z przodu kapelusz zasłaniał mu głowę). Kamera nisko przed
	-- grządką: złodziej i złoty grzyb obok siebie, grzyb buzią do nas.
	local tugSpot = at(-2.7, bedZ)
	Kit.place(thief, at(-3.6, bedZ - 5.4), forward)
	Kit.clip(thief, Clips.sneak, { fade = 0.05, events = sneakSteps })
	local toBed = Kit.path(s, thief, { at(-3.1, bedZ - 2.2), tugSpot }, 3.4)
	local tugEye = look(at(-0.8, bedZ - 6.6, 2.8), at(-1.4, bedZ, 2.2))
	Kit.shot(s, look(at(-0.4, bedZ - 7.4, 3.0), at(-1.4, bedZ, 2.2)), tugEye, toBed + 0.3, 46)
	if not Kit.wait(s, toBed) then
		return
	end

	-- ===== 5. Szarpanie =====
	Kit.phase(s, "tug")
	Kit.face(thief, soil, 0.2)
	Kit.expression(thief, "shh")
	Audio.music(nil, 1.2)
	Kit.shot(s, tugEye, look(at(-1.0, bedZ - 5.8, 2.6), at(-1.4, bedZ, 2.3)), 2.6, 44)
	local pull = Instance.new("NumberValue")
	local wobbleStart = os.clock()
	local wobble = RunService.RenderStepped:Connect(function()
		local t = os.clock() - wobbleStart
		local amount = math.clamp(t / 1.2, 0, 1) * 0.2
		setPrize(1, pull.Value + math.abs(math.sin(t * 9)) * 0.1, CFrame.Angles(math.sin(t * 14) * amount, 0, math.sin(t * 11) * amount))
	end)
	table.insert(s.connections, wobble)
	Kit.clip(thief, Clips.tug, {
		fade = 0.2,
		events = function(name)
			if name == "tug" then
				squint(prize, true)
				thief.shake = 1
				task.delay(0.25, function()
					thief.shake = 0
				end)
				Audio.play("crack", { volume = 0.35, pitch = 1.6, duration = 0.35 })
				Audio.play("dig", { volume = 0.5, pitch = 1.2, duration = 0.4 })
				tween(pull, 0.25, { Value = pull.Value + 0.16 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				puff(soil + Vector3.new(0, 0.3, 0), DIRT, 6, 3)
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
	if not Kit.wait(s, 2.2) then
		return
	end
	-- Pyk! Grzyb wyskakuje mu w rękę
	wobble:Disconnect()
	setPrize(HELD_SCALE)
	Kit.attach(thief, "RightHand", prize, CFrame.new(0, -0.42, -0.1))
	Audio.play("pick", { volume = 0.9 })
	Audio.play("coin", { volume = 0.5, pitch = 1.2 })
	sparkle(soil + Vector3.new(0, 1, 0), 26)
	puff(soil + Vector3.new(0, 0.3, 0), DIRT, 12, 5)
	s.shake = 0.25
	Kit.clip(thief, nil, { fade = 0.15 })
	Kit.track(thief, "idle")
	Kit.expression(thief, "grin")
	if not Kit.wait(s, 0.5) then
		return
	end

	-- ===== 6. Złodziej z grzybem: czerwona poświata i powolny krok =====
	Kit.phase(s, "carry")
	Kit.face(thief, at(0, -12), 0.3)
	glow.Enabled = true
	tween(redLight, 0.4, { Brightness = 1.6 })
	Audio.play("warn", { volume = 0.5 })
	Kit.subtitle(s, Localize.t("CUT2_SUB_RED"), Color3.fromRGB(255, 120, 110))
	local meet = at(0, -4.6)
	Kit.path(s, thief, { at(-2.9, bedZ - 2.4), at(-0.6, -1.4), meet }, 2.8, "walk", 0.62)
	-- Kamera cofa się przed nim, nisko, od jego lewej (złodziej na tle księżyca, grzyb w prawej ręce)
	Kit.follow(s, function()
		local p = thief.root.Position
		return look(p + Vector3.new(-1.9, -0.9, -6.2), p + Vector3.new(0, 0.6, 0))
	end, 46)
	if not Kit.wait(s, 3.2) then
		return
	end

	-- W furtce staje gracz
	Kit.phase(s, "caught")
	Kit.subtitle(s, nil)
	Audio.play("scratch", { volume = 0.9, duration = 1.2 })
	local heroGate = at(0, -10.2)
	Kit.place(hero, heroGate, forward)
	Kit.track(hero, "idle")
	-- Zza pleców złodzieja: w furtce stoi gracz
	Kit.shot(s, look(at(-2.6, -0.2, 3.6), at(0.2, -10.2, 3.3)), look(at(-2.4, -0.8, 3.5), at(0.2, -10.2, 3.4)), 2.4, 44)
	Kit.track(thief, "idle")
	Kit.mark(s, hero, "!")
	Audio.play("surprise", { volume = 0.9, duration = 1.6 })
	Kit.clip(hero, Clips.point, { fade = 0.1 })
	if not Kit.bubble(s, hero, Localize.t("CUT2_HEY"), 0.5, false, nil, 1.1) then
		return
	end
	-- Przyłapany: jego mina z bliska (od strony furtki)
	Kit.shot(s, look(at(-2.3, -10.4, 3.4), at(0, -4.6, 3.3)), look(at(-2.0, -9.8, 3.4), at(0, -4.6, 3.4)), 1.8, 42)
	Kit.face(thief, heroGate, 0.1)
	Kit.clip(thief, Clips.jumpScare, { fade = 0.05 })
	Kit.expression(thief, "o")
	Kit.eyes(thief, 0, 0)
	Kit.mark(s, thief, "!")
	Audio.play("loony", { volume = 0.7, duration = 2.2 })
	task.spawn(function()
		Kit.bubble(s, thief, Localize.t("CUT2_OOPS"), 0.5, false, nil, 0.8)
	end)
	if not Kit.wait(s, 1.2) then
		return
	end

	-- ===== 7. Dotknięcie: grzyb wraca na grządkę =====
	Kit.phase(s, "tag")
	Kit.subtitle(s, Localize.t("CUT2_SUB_TOUCH"), Color3.fromRGB(150, 255, 150))
	Kit.clip(hero, nil, { fade = 0.1 })
	local thiefAt = thief.rootValue.Value.Position - Vector3.new(0, thief.hip, 0)
	local reach = Vector3.new(thiefAt.X, heroGate.Y, thiefAt.Z) - forward * 1.7
	local dash = Kit.path(s, hero, { reach }, 15, "run", 1.4)
	Kit.shot(s, look(at(-10.0, -2.6, 3.4), at(0, -1.0, 2.4)), look(at(-9.6, -2.2, 3.3), at(0, -0.6, 2.4)), 3.2, 52)
	if not Kit.wait(s, dash) then
		return
	end
	Kit.track(hero, "idle")
	Kit.flash(s, Color3.new(1, 1, 1), 0.55, 0.35)
	s.shake = 0.35
	Audio.play("boom", { volume = 0.45 })
	Audio.play("coin", { volume = 0.8 })
	glow.Enabled = false
	tween(redLight, 0.2, { Brightness = 0 })
	-- Grzyb wylatuje z ręki złodzieja i łukiem wraca na grządkę
	for _, d in prize:GetDescendants() do
		if d:IsA("WeldConstraint") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	prize.Parent = stage
	local from = prize:GetPivot()
	local flyStart = os.clock()
	local landed = false
	local fly: RBXScriptConnection? = nil
	fly = RunService.RenderStepped:Connect(function()
		local k = math.clamp((os.clock() - flyStart) / 0.85, 0, 1)
		local e = k * k * (3 - 2 * k)
		local p = from.Position:Lerp(soil, e) + Vector3.new(0, math.sin(k * math.pi) * 5, 0)
		local scale = HELD_SCALE + (1 - HELD_SCALE) * e
		if math.abs(scale - prizeScale) > 0.02 then
			prize:ScaleTo(scale * PRIZE_SIZE)
			prizeScale = scale
		end
		prize:PivotTo(CFrame.new(p) * prizeBase.Rotation * CFrame.Angles(0, k * math.pi * 4, 0))
		if k >= 1 then
			if fly then
				fly:Disconnect()
			end
			landed = true
			setPrize(1)
			squint(prize, false)
			sparkle(soil + Vector3.new(0, 1.2, 0), 34)
			puff(soil + Vector3.new(0, 0.3, 0), DIRT, 10)
			Audio.play("plant", { volume = 0.7, duration = 1 })
			Audio.play("shimmer", { volume = 0.6, duration = 1.5 })
		end
	end)
	table.insert(s.connections, fly :: RBXScriptConnection)
	Kit.clip(thief, Clips.jumpScare, { fade = 0.05 })
	if not Kit.wait(s, 1.1) then
		return
	end
	if not landed then
		setPrize(1)
		squint(prize, false)
	end

	-- ===== 8. Ucieczka przez płot i lądowanie na twarzy =====
	Kit.phase(s, "flee")
	Kit.subtitle(s, nil)
	Audio.music("hall", 0.2)
	Kit.clip(thief, nil, { fade = 0.12 })
	Kit.expression(thief, "o")
	local run = Kit.path(s, thief, { at(-6.0, -3.2), at(-9.6, 1.0) }, 13, "run", 1.5)
	local fleeEye = at(-1.5, -10.5, 4.6)
	Kit.follow(s, function()
		return look(fleeEye, thief.root.Position + Vector3.new(0, 0.4, 0))
	end, 50)
	Audio.play("pant", { volume = 0.5, duration = 1.4, pitch = 1.3 })
	if not Kit.wait(s, run) then
		return
	end
	Audio.play("slide", { volume = 0.8 })
	Kit.track(thief, nil)
	Kit.clip(thief, Clips.vault, { fade = 0.05 })
	local landing = at(-14.6, 1.6)
	Kit.hop(s, thief, landing, 0.62, 3.4)
	if not Kit.wait(s, 0.62) then
		return
	end
	Kit.shot(s, look(at(-19.4, 7.2, 2.4), landing + Vector3.new(0, 0.8, 0)), look(at(-19.0, 6.6, 2.2), landing + Vector3.new(0, 0.7, 0)), 2.0, 46)
	Kit.clip(thief, Clips.faceplant, {
		fade = 0.05,
		events = function(name)
			if name == "thud" then
				Audio.play("bodyfall", { volume = 0.9, duration = 1 })
				Audio.play("boom", { volume = 0.5 })
				puff(landing + Vector3.new(0, 0.3, 0), Color3.fromRGB(150, 130, 100), 14, 3)
				s.shake = 0.5
				-- Gwiazdki z głowy po lądowaniu (znaku ✦ nie ma w czcionce gry)
				sparkle(landing + Vector3.new(0, 1.6, 0), 18, Color3.fromRGB(255, 220, 80))
			end
		end,
	})
	if not Kit.wait(s, 2.0) then
		return
	end
	Kit.clip(thief, nil, { fade = 0.1 })
	Kit.path(s, thief, { at(-26, 10), at(-40, 22) }, 17, "run", 1.6)
	Audio.play("pant", { volume = 0.5, duration = 1.2, pitch = 1.4 })
	if not Kit.wait(s, 0.7) then
		return
	end

	-- ===== Przeganianie =====
	Kit.phase(s, "shoo")
	local heroAt = hero.rootValue.Value.Position - Vector3.new(0, hero.hip, 0)
	Kit.face(hero, at(-20, 4), 0.2)
	Kit.shot(s, look(heroAt + Vector3.new(-6.4, 3.2, 1.6), heroAt + Vector3.new(0, 2.4, 0)), look(heroAt + Vector3.new(-5.8, 3.0, 1.4), heroAt + Vector3.new(0, 2.5, 0)), 2.6, 48)
	Kit.clip(hero, Clips.shoo, {
		fade = 0.15,
		events = function(name)
			if name == "shoo" then
				Audio.play("whoosh", { volume = 0.35, pitch = 1.3, jitter = 0.1 })
			end
		end,
	})
	task.spawn(function()
		Kit.bubble(s, hero, Localize.t("CUT2_BYE"), 0.8, false, nil, 1.1)
	end)
	if not Kit.wait(s, 1.8) then
		return
	end
	Kit.place(thief, at(-200, -200), forward)

	-- ===== 9. Grzybek cały =====
	Kit.phase(s, "safe")
	Audio.music(nil, 1.2)
	Kit.clip(hero, nil, { fade = 0.1 })
	-- Gracz znowu z boku grządki, kamera nisko przed nią: grzyb buzią do nas, gracz obok
	Kit.place(hero, admire, forward)
	Kit.face(hero, soil, 0)
	Kit.track(hero, "idle")
	local safeEnd = look(at(-1.2, bedZ - 5.8, 2.0), at(0.8, bedZ, 2.4))
	Kit.shot(s, look(at(-1.5, bedZ - 6.6, 1.8), at(0.8, bedZ, 2.2)), safeEnd, 2.6, 46)
	Kit.clip(hero, Clips.dustHands, {
		fade = 0.15,
		events = function(name)
			if name == "pat" then
				Audio.play("pat", { volume = 0.5, pitch = 1.4, duration = 0.3 })
			end
		end,
	})
	sparkle(soil + Vector3.new(0, 1.8, 0), 18)
	Audio.play("shimmer", { volume = 0.5, duration = 1.5 })
	if not Kit.bubble(s, hero, Localize.t("CUT2_SAFE"), 0.9, true, nil, 1.1) then
		return
	end
	-- Odjazd w górę nad ogródek
	Kit.shot(s, safeEnd, look(at(0, -20, 15), at(0, 2, 0.5)), 3.0, 50, Enum.EasingStyle.Quad)
	if not Kit.wait(s, 1.9) then
		return
	end
	Kit.fade(s, true, 0.9)
	Kit.wait(s, 1.0)
end

function TheftCutscene.play(onDone: () -> ())
	local s = Kit.begin(SOUNDS)
	Kit.run(s, scenario, onDone)
end

-- Podgląd w Studio: workspace:SetAttribute("DebugTheftScene", <cokolwiek>) u klienta odpala scenkę od nowa
if RunService:IsStudio() then
	Workspace:GetAttributeChangedSignal("DebugTheftScene"):Connect(function()
		if not Kit.isPlaying() then
			TheftCutscene.play(function() end)
		end
	end)
end

return TheftCutscene
