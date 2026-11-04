--!strict
-- Łysa Góra nocą (tylko u gracza, tylko na górze): czarownice na miotłach przelatują na tle wielkiego
-- księżyca i krążą nad szczytem, czasem któraś przemknie z chichotem tuż nad głową; stada nietoperzy
-- przelatują nad ścieżką, a nad chatką Baby Jagi krąży kilka na stałe; nad doliną co jakiś czas bije
-- piorun (błysk, zygzak w chmurach, grzmot z opóźnieniem). O świcie czarownice i nietoperze znikają.
-- Księżyc za szczytem ustawia Atmosphere (szerokość geograficzna i pora), tu tylko z niego korzystamy.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Terrain = require(ReplicatedStorage.Shared.MountainTerrain)
local Audio = require(script.Parent.Audio)

local MountainSky = {}

local SILHOUETTE = Color3.fromRGB(14, 10, 20)
local EYE = Color3.fromRGB(150, 255, 90)
local BOLT = Color3.fromRGB(228, 214, 255)
local FLASH_TINT = Color3.fromRGB(232, 222, 255)
local TAU = math.pi * 2

local rng = Random.new()
local folder = Instance.new("Folder")
folder.Name = "MountainSky"

-- Błysk pioruna: osobna korekcja kolorów (Atmosphere jej nie rusza, ma ją na liście swoich efektów)
local flash = Instance.new("ColorCorrectionEffect")
flash.Name = "MountainFlash"
flash.Brightness = 0
flash.TintColor = Color3.new(1, 1, 1)
flash.Enabled = false
flash.Parent = Lighting

local function newPart(className: string, size: Vector3, color: Color3?, neon: boolean?): BasePart
	local p = Instance.new(className) :: BasePart
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.Color = color or SILHOUETTE
	p.Size = size
	p.Parent = folder
	return p
end

-- ===== Lotnicy: czarownica i nietoperz z klocków (przód -Z), ruszane przez BulkMoveTo =====

type Piece = { part: BasePart, offset: CFrame, flap: number? } -- flap: skrzydło (-1/1) albo peleryna (0)
type Flyer = { pieces: { Piece }, parts: { BasePart }, cframes: { CFrame } }

local function flyer(pieces: { Piece }): Flyer
	local parts = {}
	for _, piece in pieces do
		table.insert(parts, piece.part)
	end
	return { pieces = pieces, parts = parts, cframes = table.create(#parts) }
end

-- Czarownica na miotle: kij z miotłą, peleryna, głowa z nosem, spiczasty kapelusz z rondem,
-- ręka na kiju, zielone oczka (widać je, kiedy przelatuje blisko)
local function buildWitch(s: number): Flyer
	local pieces: { Piece } = {}
	local function add(className: string, size: Vector3, offset: CFrame, color: Color3?, neon: boolean?, flap: number?)
		local part = newPart(className, size * s, color, neon)
		table.insert(pieces, { part = part, offset = CFrame.new(offset.Position * s) * offset.Rotation, flap = flap })
	end
	local cylinderZ = CFrame.Angles(0, math.rad(90), 0)
	add("Part", Vector3.new(6.6, 0.26, 0.26), CFrame.new(0, 0, 0) * cylinderZ)
	add("Part", Vector3.new(1.3, 1.1, 2.2), CFrame.new(0, -0.05, 4.1) * CFrame.Angles(math.rad(-8), 0, 0))
	add("WedgePart", Vector3.new(1.5, 0.9, 1.4), CFrame.new(0, 0.3, 5.6) * CFrame.Angles(math.rad(180), 0, 0))
	add("WedgePart", Vector3.new(1.4, 2.4, 1.9), CFrame.new(0, 1.25, 0.95))
	add("Part", Vector3.new(1, 1, 1), CFrame.new(0, 2.8, 0.55))
	add("WedgePart", Vector3.new(0.22, 0.3, 0.7), CFrame.new(0, 2.66, -0.1) * CFrame.Angles(0, math.rad(180), 0))
	add("Part", Vector3.new(0.12, 2.5, 2.5), CFrame.new(0, 3.2, 0.6) * CFrame.Angles(0, 0, math.rad(90)))
	add("WedgePart", Vector3.new(1.05, 2.3, 1.5), CFrame.new(0, 4.4, 0.95) * CFrame.Angles(math.rad(-10), 0, 0))
	add("Part", Vector3.new(0.3, 0.3, 2.2), CFrame.new(0, 1.3, -0.3) * CFrame.Angles(math.rad(35), 0, 0))
	add("WedgePart", Vector3.new(1.2, 0.18, 2.4), CFrame.new(0, 1.6, 2.6), nil, nil, 0)
	for _, side in { -1, 1 } do
		add("Part", Vector3.new(0.16, 0.12, 0.06), CFrame.new(side * 0.22, 2.9, 0.04), EYE, true)
	end
	return flyer(pieces)
end

-- Nietoperz: tułów, łebek z uszami i dwa skrzydła machające na zawiasach przy tułowiu
local function buildBat(s: number): Flyer
	local pieces: { Piece } = {}
	local function add(className: string, size: Vector3, offset: CFrame, flap: number?)
		local part = newPart(className, size * s)
		table.insert(pieces, { part = part, offset = CFrame.new(offset.Position * s) * offset.Rotation, flap = flap })
	end
	add("Part", Vector3.new(0.5, 0.42, 0.9), CFrame.new())
	add("Part", Vector3.new(0.36, 0.32, 0.34), CFrame.new(0, 0.08, -0.55))
	for _, side in { -1, 1 } do
		add("WedgePart", Vector3.new(0.08, 0.22, 0.16), CFrame.new(side * 0.1, 0.32, -0.55))
		-- Skrzydło: klin leżący poziomo (trójkąt w płaszczyźnie XZ, szeroki przy tułowiu), zawias przy boku
		add("WedgePart", Vector3.new(0.05, 1.3, 0.9), CFrame.new(side * 0.25, 0, 0) * CFrame.Angles(0, 0, math.rad(-90 * side)), side)
	end
	return flyer(pieces)
end

-- Ustawia lotnika w `cf`. flap: kąt skrzydeł (radiany), cloak: falowanie peleryny
local function place(f: Flyer, cf: CFrame, flap: number, cloak: number)
	for i, piece in f.pieces do
		local offset = piece.offset
		local side = piece.flap
		if side == 0 then
			offset = offset * CFrame.Angles(cloak, 0, 0)
		elseif side then
			-- Skrzydło obraca się wokół zawiasu przy tułowiu, a jego środek leży pół rozpiętości dalej
			offset = CFrame.new(offset.Position) * CFrame.Angles(0, 0, side * flap) * CFrame.new(side * f.parts[i].Size.Y / 2, 0, 0) * offset.Rotation
		end
		f.cframes[i] = cf * offset
	end
	if folder.Parent == Workspace then
		Workspace:BulkMoveTo(f.parts, f.cframes, Enum.BulkMoveMode.FireCFrameChanged)
	else
		for i, part in f.parts do
			part.CFrame = f.cframes[i]
		end
	end
end

local function hide(f: Flyer)
	place(f, CFrame.new(0, -1000, 0), 0, 0)
end

-- ===== Czarownice =====

-- Dwie krążą nad szczytem, trzecia przelatuje na tle księżyca albo nad głową gracza
local circling = { buildWitch(1.6), buildWitch(1.4) }
local crosser = buildWitch(1.7)
local crossing: { from: Vector3, to: Vector3, start: number, duration: number, arc: number }? = nil
local nextCrossing = 0
local nextSwoop = 0

local function startMoonCrossing(camera: Camera, now: number)
	local moon = Lighting:GetMoonDirection()
	if moon.Y < 0.05 then
		return
	end
	local distance = rng:NextNumber(80, 140)
	local center = camera.CFrame.Position + moon * distance
	local across = moon:Cross(Vector3.yAxis)
	if across.Magnitude < 0.1 then
		return
	end
	across = across.Unit * (if rng:NextNumber() < 0.5 then 1 else -1)
	local half = distance * 0.75
	local drop = Vector3.new(0, -distance * 0.06, 0)
	crossing = {
		from = center - across * half + drop,
		to = center + across * half + drop,
		start = now,
		duration = half * 2 / rng:NextNumber(34, 44),
		arc = distance * 0.12,
	}
	Audio.play("witch", { volume = 0.3, pitch = rng:NextNumber(0.95, 1.15) })
end

-- Przelot tuż nad głową gracza: zza pleców, nisko, z wiatrem i chichotem
local function startSwoop(root: BasePart, camera: Camera, now: number)
	local look = camera.CFrame.LookVector
	local forward = Vector3.new(look.X, 0, look.Z)
	if forward.Magnitude < 0.1 then
		return
	end
	forward = forward.Unit
	local side = forward:Cross(Vector3.yAxis) * rng:NextNumber(-0.4, 0.4)
	local base = root.Position
	crossing = {
		from = base - forward * 60 + side * 20 + Vector3.new(0, 16, 0),
		to = base + forward * 70 - side * 20 + Vector3.new(0, 22, 0),
		start = now,
		duration = 2.6,
		arc = -9,
	}
	Audio.play("witchFly", { volume = 0.8, pitch = rng:NextNumber(0.9, 1.1) })
	task.delay(0.9, function()
		Audio.play("witch", { volume = 0.55, pitch = rng:NextNumber(1, 1.2) })
	end)
end

local function updateWitches(now: number, root: BasePart, camera: Camera, zoneDef: Config.ZoneDef)
	-- Krążące nad szczytem (sylwetki na tle nieba, widać je z całej góry)
	local lair = Config.JagaLair
	for i, witch in circling do
		local period = if i == 1 then 38 else 47
		local angle = now / period * TAU * (if i == 1 then 1 else -1) + i * 2.1
		local radius = if i == 1 then 74 else 96
		local height = Terrain.TOP + (if i == 1 then 34 else 48) + math.sin(now * 0.7 + i) * 4
		local center = Vector3.new(lair.centerX, 0, lair.centerZ - 20)
		local at = center + Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
		local ahead = angle + 0.05 * (if i == 1 then 1 else -1)
		local towards = center + Vector3.new(math.cos(ahead) * radius, height, math.sin(ahead) * radius)
		local bank = CFrame.Angles(0, 0, math.rad(if i == 1 then 18 else -18))
		place(witch, CFrame.lookAt(at, towards) * bank, 0, math.sin(now * 9 + i) * 0.35)
	end
	-- Przelot na tle księżyca albo nad głową
	if not crossing and now >= nextCrossing then
		if now >= nextSwoop and not zoneDef.safe then
			startSwoop(root, camera, now)
			nextSwoop = now + rng:NextNumber(60, 110)
		else
			startMoonCrossing(camera, now)
		end
		nextCrossing = now + rng:NextNumber(14, 26)
	end
	local c = crossing
	if c then
		local t = (now - c.start) / c.duration
		if t >= 1 then
			crossing = nil
			hide(crosser)
		else
			local at = c.from:Lerp(c.to, t) + Vector3.new(0, math.sin(t * math.pi) * c.arc, 0)
			local ahead = c.from:Lerp(c.to, math.min(t + 0.02, 1)) + Vector3.new(0, math.sin(math.min(t + 0.02, 1) * math.pi) * c.arc, 0)
			if (ahead - at).Magnitude > 0.01 then
				place(crosser, CFrame.lookAt(at, ahead) * CFrame.Angles(0, 0, math.sin(now * 3) * 0.12), 0, math.sin(now * 11) * 0.4)
			end
		end
	end
end

-- ===== Nietoperze =====

local hutBats = { buildBat(1.2), buildBat(1.1), buildBat(1.3) }
local flock: { Flyer } = {}
for _ = 1, 8 do
	table.insert(flock, buildBat(rng:NextNumber(0.9, 1.25)))
end
type Flight = { from: Vector3, to: Vector3, start: number, duration: number, offsets: { Vector3 }, phases: { number } }
local flight: Flight? = nil
local nextFlock = 0

local function startFlock(root: BasePart, camera: Camera, now: number)
	local look = camera.CFrame.LookVector
	local forward = Vector3.new(look.X, 0, look.Z)
	if forward.Magnitude < 0.1 then
		return
	end
	forward = forward.Unit
	local across = forward:Cross(Vector3.yAxis) * (if rng:NextNumber() < 0.5 then 1 else -1)
	local base = root.Position + forward * rng:NextNumber(4, 16) + Vector3.new(0, rng:NextNumber(7, 12), 0)
	local offsets, phases = {}, {}
	for i = 1, #flock do
		offsets[i] = Vector3.new(rng:NextNumber(-5, 5), rng:NextNumber(-2.5, 2.5), rng:NextNumber(-5, 5))
		phases[i] = rng:NextNumber(0, TAU)
	end
	flight = { from = base - across * 50, to = base + across * 50, start = now, duration = rng:NextNumber(3.2, 4.2), offsets = offsets, phases = phases }
end

local function updateBats(now: number, root: BasePart, camera: Camera, zoneDef: Config.ZoneDef)
	-- Nad chatką Baby Jagi krążą zawsze (widać je, kiedy gracz jest blisko szczytu)
	local lair = Config.JagaLair
	local hut = Vector3.new(lair.centerX, Terrain.TOP + 17, lair.hutZ)
	local nearHut = (hut - root.Position).Magnitude < 220
	for i, bat in hutBats do
		if nearHut then
			local angle = now * (1.4 + i * 0.25) + i * 2
			local radius = 7 + i * 2.5
			local at = hut + Vector3.new(math.cos(angle) * radius, math.sin(now * 2.3 + i) * 2, math.sin(angle) * radius)
			local ahead = hut + Vector3.new(math.cos(angle + 0.1) * radius, math.sin(now * 2.3 + i) * 2, math.sin(angle + 0.1) * radius)
			place(bat, CFrame.lookAt(at, ahead), math.sin(now * 22 + i) * 0.9, 0)
		else
			hide(bat)
		end
	end
	-- Stado przelatuje nad ścieżką co jakiś czas
	if not flight and now >= nextFlock and not zoneDef.safe then
		startFlock(root, camera, now)
		nextFlock = now + rng:NextNumber(22, 40)
	end
	local f = flight
	if f then
		local t = (now - f.start) / f.duration
		if t >= 1 then
			flight = nil
			for _, bat in flock do
				hide(bat)
			end
		else
			local direction = (f.to - f.from).Unit
			for i, bat in flock do
				local wobble = Vector3.new(math.sin(now * 6 + f.phases[i]) * 1.2, math.sin(now * 9 + f.phases[i]) * 0.8, math.cos(now * 5 + f.phases[i]) * 1.2)
				local at = f.from:Lerp(f.to, t) + f.offsets[i] + wobble
				place(bat, CFrame.lookAt(at, at + direction), math.sin(now * 24 + f.phases[i]) * 0.95, 0)
			end
		end
	end
end

-- ===== Pioruny =====

local nextBolt = 0
local boltParts: { BasePart } = {}

local function clearBolt()
	for _, p in boltParts do
		p:Destroy()
	end
	table.clear(boltParts)
end

-- Zygzak z neonowych odcinków od nieba do morza chmur (z jedną odnogą)
local function drawBolt(top: Vector3, bottom: Vector3, width: number, depth: number)
	local segments = 10
	local previous = top
	local span = (bottom - top).Magnitude
	for k = 1, segments do
		local t = k / segments
		local point = top:Lerp(bottom, t)
		if k < segments then
			point += Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * span * 0.06
		end
		local length = (point - previous).Magnitude
		local p = newPart("Part", Vector3.new(width, width, length), BOLT, true)
		p.CFrame = CFrame.lookAt((previous + point) / 2, point)
		table.insert(boltParts, p)
		if depth > 0 and k == math.floor(segments * 0.4) then
			local branchEnd = point + Vector3.new(rng:NextNumber(-1, 1) * span * 0.25, -span * 0.3, rng:NextNumber(-1, 1) * span * 0.25)
			drawBolt(point, branchEnd, width * 0.6, depth - 1)
		end
		previous = point
	end
end

local function setBoltVisible(visible: boolean)
	for _, p in boltParts do
		p.Transparency = if visible then 0 else 1
	end
end

local function strike(camera: Camera)
	clearBolt()
	-- Gdzieś przed graczem, nad doliną albo za szczytem (widać z ekranu)
	local look = camera.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z) + rng:NextNumber(-1.1, 1.1)
	local distance = rng:NextNumber(220, 420)
	local camPos = camera.CFrame.Position
	local ground = camPos + Vector3.new(-math.sin(yaw), 0, -math.cos(yaw)) * distance
	local bottom = Vector3.new(ground.X, Terrain.CLOUDS + rng:NextNumber(-4, 8), ground.Z)
	local top = bottom + Vector3.new(rng:NextNumber(-40, 40), rng:NextNumber(200, 260), rng:NextNumber(-40, 40))
	drawBolt(top, bottom, rng:NextNumber(1.6, 2.6), 1)
	-- Mignięcie: błysk, przerwa, drugi błysk, powolne gaśnięcie
	task.spawn(function()
		flash.Enabled = true
		flash.TintColor = FLASH_TINT
		local strength = rng:NextNumber(0.22, 0.34)
		flash.Brightness = strength
		setBoltVisible(true)
		task.wait(0.07)
		flash.Brightness = strength * 0.2
		setBoltVisible(false)
		task.wait(0.06)
		flash.Brightness = strength * 0.8
		setBoltVisible(true)
		local fade = 0.35
		local started = os.clock()
		while os.clock() - started < fade do
			local k = 1 - (os.clock() - started) / fade
			flash.Brightness = strength * 0.8 * k
			for _, p in boltParts do
				p.Transparency = 1 - k
			end
			RunService.RenderStepped:Wait()
		end
		flash.Brightness = 0
		flash.Enabled = false
		clearBolt()
	end)
	-- Grzmot dochodzi później, im dalej, tym ciszej i niżej
	local delay = 0.4 + distance / 380
	task.delay(delay, function()
		Audio.play(if distance < 300 then "thunderClose" else "thunder", { volume = 0.9 - distance / 1000, pitch = rng:NextNumber(0.85, 1.05) })
	end)
end

-- ===== Sterowanie =====

local active = false
local allFlyers: { Flyer } = { crosser }
for _, w in circling do
	table.insert(allFlyers, w)
end
for _, b in hutBats do
	table.insert(allFlyers, b)
end
for _, b in flock do
	table.insert(allFlyers, b)
end

local function setActive(value: boolean)
	if value == active then
		return
	end
	active = value
	if value then
		folder.Parent = Workspace
	else
		crossing = nil
		flight = nil
		for _, f in allFlyers do
			hide(f)
		end
		clearBolt()
		flash.Brightness = 0
		flash.Enabled = false
		folder.Parent = nil
	end
end
for _, f in allFlyers do
	hide(f)
end

-- Wołane co klatkę z Main (po Atmosphere.update)
function MountainSky.update(root: BasePart, zoneDef: Config.ZoneDef)
	local night = Workspace:GetAttribute("CyclePhase") ~= "dawn"
	setActive(zoneDef.world == "mountain" and night)
	if not active then
		return
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local now = os.clock()
	if nextBolt == 0 then
		-- Pierwsze zdarzenia chwilę po wejściu na górę
		nextBolt = now + rng:NextNumber(6, 12)
		nextCrossing = now + rng:NextNumber(4, 8)
		nextSwoop = now + rng:NextNumber(40, 70)
		nextFlock = now + rng:NextNumber(10, 18)
	end
	updateWitches(now, root, camera, zoneDef)
	updateBats(now, root, camera, zoneDef)
	if now >= nextBolt then
		nextBolt = now + rng:NextNumber(14, 34)
		strike(camera)
	end
end

-- Test w Studio: Workspace.MountainSky.Test:Fire("bolt" | "moon" | "swoop" | "bats")
if RunService:IsStudio() then
	local test = Instance.new("BindableEvent")
	test.Name = "Test"
	test.Parent = folder
	test.Event:Connect(function(what: string)
		local camera = Workspace.CurrentCamera
		local character = game:GetService("Players").LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not camera or not (root and root:IsA("BasePart")) then
			return
		end
		local now = os.clock()
		if what == "bolt" then
			strike(camera)
		elseif what == "moon" then
			startMoonCrossing(camera, now)
			nextCrossing = now + 30
		elseif what == "swoop" then
			startSwoop(root, camera, now)
			nextCrossing = now + 30
		elseif what == "bats" then
			startFlock(root, camera, now)
			nextFlock = now + 40
		end
	end)
end

return MountainSky
