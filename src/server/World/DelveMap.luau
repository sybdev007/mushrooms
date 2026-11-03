--!strict
-- Głębokie Komory (ekspedycja, Shared/Delve): budowa z klocków jak reszta jaskini.
--   * buildEntrances: tablica zleceń w Obozie i szczelina „Zejdź w głąb” w ścianie Otchłani,
--   * buildCopy: jedna kopia trzech komór (każda ekspedycja dostaje własną, DelveService je przydziela).
-- Kopia: Sala (hak z olejem) → Zawalony Chodnik (zawał do odgruzowania, kupki gruzu, osuwiska)
-- → Zalana Komora (woda, kładki, kryjówki) → Ognisko (zabezpieczenie, lina do obozu, drzwi)
-- → Krypta Skarbnika (filary, wnęki, ołtarz z trofeum).
-- Przyciski (ProximityPrompt) mają tag "LocalizedPrompt" (Signs tłumaczy TextKey) i są wyłączone;
-- włącza je DelveService dla konkretnej ekspedycji.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Delve = require(ReplicatedStorage.Shared.Delve)
local Palette = require(script.Parent.Palette)
local Props = require(script.Parent.Props)

local DelveMap = {}

local VERTICAL = CFrame.Angles(0, 0, math.rad(90))
local ROCK = { Color3.fromRGB(66, 48, 46), Color3.fromRGB(58, 42, 42), Color3.fromRGB(78, 56, 50) }
local MUD = Color3.fromRGB(46, 40, 36)
local WATER = Color3.fromRGB(40, 110, 120)
local RUBBLE = Color3.fromRGB(104, 86, 70)
local GLOW = { Color3.fromRGB(255, 120, 60), Color3.fromRGB(120, 230, 255), Color3.fromRGB(170, 110, 255) }

local function make(className: string, props: { [string]: any }): BasePart
	local p = Instance.new(className) :: BasePart
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

local function decor(p: BasePart): BasePart
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	return p
end

-- Przycisk tłumaczony po stronie klienta (Signs: tag LocalizedPrompt)
local function prompt(parent: Instance, name: string, textKey: string, objectKey: string?, hold: number, distance: number?): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = textKey
	p.HoldDuration = hold
	p.MaxActivationDistance = distance or 9
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.F -- E zbiera grzyby
	p.GamepadKeyCode = Enum.KeyCode.ButtonY
	p.Enabled = false
	p:SetAttribute("TextKey", textKey)
	if objectKey then
		p:SetAttribute("ObjectKey", objectKey)
	end
	CollectionService:AddTag(p, "LocalizedPrompt")
	p.Parent = parent
	return p
end

local function glowCrystal(parent: Instance, base: Vector3, color: Color3, rng: Random, light: boolean)
	for i = 1, rng:NextInteger(2, 4) do
		local h = rng:NextNumber(1.2, 3.2)
		local part = decor(make("Part", {
			Name = "Crystal",
			Size = Vector3.new(0.5 + h * 0.15, h, 0.5 + h * 0.15),
			CFrame = CFrame.new(base + Vector3.new(rng:NextNumber(-0.8, 0.8), h / 2 - 0.2, rng:NextNumber(-0.8, 0.8)))
				* CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 6.28), rng:NextNumber(-0.4, 0.4)),
			Color = color,
			Material = Enum.Material.Neon,
			Transparency = 0.15,
			Parent = parent,
		}))
		if light and i == 1 then
			local l = Instance.new("PointLight")
			l.Color = color
			l.Range = 10
			l.Brightness = 0.7
			l.Shadows = false
			l.Parent = part
		end
	end
end

-- ===== Wejścia: tablica w Obozie i szczelina w Otchłani =====

export type Entrances = {
	board: BasePart,
	boardPrompt: ProximityPrompt,
	passage: BasePart,
	passagePrompt: ProximityPrompt,
}

DelveMap.BOARD = Vector3.new(30, 0, 1028) -- w Obozie, z boku za kramikiem
DelveMap.PASSAGE = Vector3.new(42, 0, 1398) -- w ścianie Otchłani za rzeką lawy

-- Rezerwacja na mapie (nic tam nie wyrośnie)
function DelveMap.reservedRects(): { { x1: number, x2: number, z1: number, z2: number } }
	local p = DelveMap.PASSAGE
	return { { x1 = p.X - 10, x2 = p.X + 6, z1 = p.Z - 9, z2 = p.Z + 9 } }
end

function DelveMap.buildEntrances(parent: Instance): Entrances
	local folder = Instance.new("Folder")
	folder.Name = "DelveEntrances"

	-- Tablica zleceń: dwa słupy, deska z przypiętymi kartkami, latarnia; przodem do środka obozu (-X)
	local cf = CFrame.lookAt(DelveMap.BOARD, DelveMap.BOARD + Vector3.new(-1, 0, 0))
	for _, side in { -1, 1 } do
		make("Part", { Name = "BoardPost", Size = Vector3.new(0.6, 7, 0.6), CFrame = cf * CFrame.new(side * 3.4, 3.5, 0.3), Color = Palette.log, Parent = folder })
	end
	local board = make("Part", {
		Name = "DelveBoard",
		Size = Vector3.new(6.4, 3.8, 0.4),
		CFrame = cf * CFrame.new(0, 4, 0),
		Color = Palette.plankDark,
		Parent = folder,
	})
	local rng = Random.new(31)
	for i = 1, 5 do
		decor(make("Part", {
			Name = "Note",
			Size = Vector3.new(1.3, 1.6, 0.05),
			CFrame = cf * CFrame.new(-2.3 + (i - 1) * 1.15, 4 + rng:NextNumber(-0.7, 0.7), -0.23) * CFrame.Angles(0, 0, rng:NextNumber(-0.25, 0.25)),
			Color = if i == 3 then Color3.fromRGB(255, 226, 150) else Color3.fromRGB(232, 220, 196),
			Parent = folder,
		}))
	end
	Props.signBoard(folder, cf * CFrame.new(0, 6.5, -0.05), Vector3.new(6.4, 1.2, 0.3), "SIGN_DELVE_BOARD", Enum.NormalId.Front)
	Props.hangingLantern(folder, (cf * CFrame.new(3.4, 7.2, -0.8)).Position, 16)
	local boardPrompt = prompt(board, "DelveBoardPrompt", "DELVE_PROMPT_BOARD", "DELVE_BOARD_OBJECT", 0, 10)
	boardPrompt.Enabled = true

	-- Szczelina w ścianie Otchłani: ciemny otwór w skalnym łuku, fioletowe pęknięcia, szyld
	local p = DelveMap.PASSAGE
	local pcf = CFrame.lookAt(p, p + Vector3.new(-1, 0, 0)) -- przodem do środka jaskini
	for _, side in { -1, 1 } do
		for level = 0, 3 do
			make("Part", {
				Name = "PassageRock",
				Size = Vector3.new(3.2, 3, 3.6),
				CFrame = pcf * CFrame.new(side * 4.2, 1.5 + level * 2.7, 1.2) * CFrame.Angles(rng:NextNumber(-0.2, 0.2), rng:NextNumber(-0.3, 0.3), 0),
				Color = ROCK[rng:NextInteger(1, #ROCK)],
				Material = Enum.Material.Slate,
				Parent = folder,
			})
		end
	end
	for i = -2, 2 do
		make("Part", {
			Name = "PassageRock",
			Size = Vector3.new(3, 2.6, 3.6),
			CFrame = pcf * CFrame.new(i * 2, 11.4 - math.abs(i) * 0.6, 1.2) * CFrame.Angles(0, 0, i * 0.2),
			Color = ROCK[rng:NextInteger(1, #ROCK)],
			Material = Enum.Material.Slate,
			Parent = folder,
		})
	end
	local passage = make("Part", {
		Name = "DelvePassage",
		Size = Vector3.new(5.6, 9.6, 0.6),
		CFrame = pcf * CFrame.new(0, 4.8, 2.2),
		Color = Color3.fromRGB(8, 6, 12),
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
	for i = 1, 5 do
		decor(make("Part", {
			Name = "Crack",
			Size = Vector3.new(0.18, rng:NextNumber(1.5, 3.5), 0.1),
			CFrame = pcf * CFrame.new(rng:NextNumber(-2.2, 2.2), rng:NextNumber(1.5, 8), 1.85) * CFrame.Angles(0, 0, rng:NextNumber(-0.6, 0.6)),
			Color = Color3.fromRGB(170, 110, 255),
			Material = Enum.Material.Neon,
			Parent = folder,
		}))
	end
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(170, 110, 255)
	glow.Range = 16
	glow.Brightness = 1.2
	glow.Parent = passage
	local mist = Instance.new("ParticleEmitter")
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Color = ColorSequence.new(Color3.fromRGB(120, 80, 200))
	mist.LightEmission = 0.4
	mist.Transparency = NumberSequence.new(0.7, 1)
	mist.Size = NumberSequence.new(2, 4)
	mist.Lifetime = NumberRange.new(2, 3)
	mist.Rate = 4
	mist.Speed = NumberRange.new(0.5, 1)
	mist.Parent = passage
	glowCrystal(folder, (pcf * CFrame.new(-3.4, 0, -1.4)).Position, GLOW[3], rng, false)
	glowCrystal(folder, (pcf * CFrame.new(3.6, 0, -1)).Position, GLOW[3], rng, false)
	Props.signBoard(folder, pcf * CFrame.new(0, 13.6, 0.4), Vector3.new(7, 1.4, 0.3), "SIGN_DELVE", Enum.NormalId.Front)
	local passagePrompt = prompt(passage, "DelvePassagePrompt", "DELVE_PROMPT_ENTER", "SIGN_DELVE", 0.6, 10)
	passagePrompt.Enabled = true

	folder.Parent = parent
	return { board = board, boardPrompt = boardPrompt, passage = passage, passagePrompt = passagePrompt }
end

-- ===== Jedna kopia komór =====

export type Interactive = { part: BasePart, prompt: ProximityPrompt, model: Instance }

export type Copy = {
	slot: number,
	origin: Vector3,
	folder: Folder,
	spawn: CFrame,
	blockage: Interactive,
	alcoves: { Interactive },
	hides: { Interactive },
	samples: { Interactive },
	find: Interactive, -- znalezisko do zabrania (gdy komuś zabrakło miejsca w koszyku)
	water: BasePart,
	floodPlanks: { BasePart },
	bonfire: Interactive,
	fire: { Instance }, -- płomienie ogniska (zapalone po zabezpieczeniu)
	exit: Interactive,
	door: Interactive,
	altar: Interactive,
	relic: BasePart, -- trofeum na ołtarzu
	guardHome: CFrame,
}

-- Zapisuje stan widoczności części modelu (żeby przy resecie przywrócić przezroczystość)
local function remember(model: Instance)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d:SetAttribute("BaseTransparency", d.Transparency)
			d:SetAttribute("BaseCollide", d.CanCollide)
		end
	end
	if model:IsA("BasePart") then
		model:SetAttribute("BaseTransparency", model.Transparency)
		model:SetAttribute("BaseCollide", model.CanCollide)
	end
end

-- Pokazuje / chowa model (kupka gruzu, drzwi, próbka): przezroczystość i kolizja wracają do bazowych
function DelveMap.setShown(model: Instance, shown: boolean)
	local function apply(part: BasePart)
		local base = part:GetAttribute("BaseTransparency")
		local collide = part:GetAttribute("BaseCollide")
		part.Transparency = if shown then (if typeof(base) == "number" then base else 0) else 1
		part.CanCollide = shown and collide == true
	end
	if model:IsA("BasePart") then
		apply(model)
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			apply(d)
		elseif d:IsA("PointLight") then
			d.Enabled = shown
		elseif d:IsA("ParticleEmitter") then
			d.Enabled = shown
		end
	end
end

local function rubblePile(parent: Instance, at: Vector3, scale: number, rng: Random, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	for i = 1, 6 do
		local s = rng:NextNumber(1.4, 2.6) * scale
		make("Part", {
			Name = "Rubble",
			Size = Vector3.new(s * rng:NextNumber(0.8, 1.3), s * rng:NextNumber(0.6, 1), s * rng:NextNumber(0.8, 1.3)),
			CFrame = CFrame.new(at + Vector3.new(rng:NextNumber(-1.2, 1.2) * scale, s * 0.35 + (if i > 3 then s * 0.5 else 0), rng:NextNumber(-1, 1) * scale))
				* CFrame.Angles(rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, 6.28), rng:NextNumber(-0.5, 0.5)),
			Color = RUBBLE:Lerp(ROCK[1], rng:NextNumber(0, 0.6)),
			Material = Enum.Material.Slate,
			CanCollide = false,
			Parent = m,
		})
	end
	-- Wystający trzonek kilofa: widać, że to gruz z dawnej sztolni
	decor(make("Part", {
		Name = "Handle",
		Size = Vector3.new(0.25, 2.2, 0.25),
		CFrame = CFrame.new(at + Vector3.new(0.6, 1.8 * scale, 0)) * CFrame.Angles(0, 0, 0.6),
		Color = Palette.log,
		Parent = m,
	}))
	m.Parent = parent
	return m
end

local function oilHook(parent: Instance, at: Vector3)
	make("Part", { Name = "HookPost", Size = Vector3.new(0.5, 6, 0.5), Position = at + Vector3.new(0, 3, 0), Color = Palette.plankDark, Parent = parent })
	make("Part", {
		Name = "HookBarrel",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2.2, 1.8, 1.8),
		CFrame = CFrame.new(at + Vector3.new(0, 1.1, 1.2)) * VERTICAL,
		Color = Color3.fromRGB(110, 74, 46),
		Parent = parent,
	})
	Props.hangingLantern(parent, at + Vector3.new(0, 5.8, 0), 14)
	-- Krąg na ziemi jak przy beczkach w obozie (tankowanie w promieniu Delve.REFILL_RADIUS)
	local pieces = 14
	for i = 1, pieces do
		local angle = (i - 1) / pieces * math.pi * 2
		decor(make("Part", {
			Name = "OilRing",
			Size = Vector3.new(0.3, 0.06, 1.2),
			CFrame = CFrame.new(at + Vector3.new(math.cos(angle) * 3.6, 0.04, math.sin(angle) * 3.6)) * CFrame.Angles(0, -angle, 0),
			Color = Color3.fromRGB(255, 186, 80),
			Material = Enum.Material.Neon,
			Transparency = 0.3,
			Parent = parent,
		}))
	end
end

-- Ściany, podłoga i strop odcinka (od x1 do x2, połowa szerokości half)
local function shell(folder: Instance, origin: Vector3, section: Delve.Section, rng: Random, floorColor: Color3)
	local length = section.x2 - section.x1
	local mid = origin + Vector3.new(section.x1 + length / 2, 0, 0)
	make("Part", { Name = "Floor", Size = Vector3.new(length, 2, section.half * 2 + 4), Position = mid + Vector3.new(0, -1, 0), Color = floorColor, Material = Enum.Material.Slate, Parent = folder })
	make("Part", {
		Name = "Ceiling",
		Size = Vector3.new(length, 3, section.half * 2 + 4),
		Position = mid + Vector3.new(0, Delve.CEILING + 1.5, 0),
		Color = ROCK[2],
		Material = Enum.Material.Slate,
		Parent = folder,
	})
	for _, side in { -1, 1 } do
		make("Part", {
			Name = "Wall",
			Size = Vector3.new(length, Delve.CEILING + 2, 2),
			Position = mid + Vector3.new(0, Delve.CEILING / 2, side * (section.half + 1)),
			Color = ROCK[rng:NextInteger(1, #ROCK)],
			Material = Enum.Material.Slate,
			Parent = folder,
		})
		-- Nieregularne głazy przy ścianie, żeby nie wyglądało jak pudełko
		local x = section.x1 + 2
		while x < section.x2 - 1 do
			local s = rng:NextNumber(3, 6)
			decor(make("Part", {
				Name = "WallRock",
				Size = Vector3.new(s * rng:NextNumber(0.9, 1.4), s * rng:NextNumber(1, 2.2), s * 0.7),
				CFrame = CFrame.new(origin + Vector3.new(x, s * 0.6, side * (section.half + 0.2)))
					* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(-0.4, 0.4), rng:NextNumber(-0.3, 0.3)),
				Color = ROCK[rng:NextInteger(1, #ROCK)],
				Material = Enum.Material.Slate,
				Parent = folder,
			}))
			x += rng:NextNumber(4, 7)
		end
	end
	-- Stalaktyty
	for _ = 1, math.floor(length / 8) do
		local h = rng:NextNumber(1.5, 4)
		decor(make("Part", {
			Name = "Stalactite",
			Size = Vector3.new(1, h, 1),
			CFrame = CFrame.new(origin + Vector3.new(rng:NextNumber(section.x1 + 1, section.x2 - 1), Delve.CEILING - h / 2, rng:NextNumber(-section.half + 1, section.half - 1)))
				* CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
			Color = ROCK[3],
			Material = Enum.Material.Slate,
			Parent = folder,
		}))
	end
end

-- Ściana poprzeczna na granicy odcinków (zasłania różnicę szerokości), z przejściem o połowie szerokości gap
local function crossWall(folder: Instance, origin: Vector3, x: number, half: number, gap: number)
	for _, side in { -1, 1 } do
		local width = half - gap
		if width > 0 then
			make("Part", {
				Name = "CrossWall",
				Size = Vector3.new(2, Delve.CEILING + 2, width + 1),
				Position = origin + Vector3.new(x, Delve.CEILING / 2, side * (gap + width / 2 + 0.5)),
				Color = ROCK[1],
				Material = Enum.Material.Slate,
				Parent = folder,
			})
		end
	end
	-- Nad przejściem skała do stropu
	make("Part", {
		Name = "CrossLintel",
		Size = Vector3.new(2, Delve.CEILING - 10, gap * 2),
		Position = origin + Vector3.new(x, 10 + (Delve.CEILING - 10) / 2, 0),
		Color = ROCK[2],
		Material = Enum.Material.Slate,
		Parent = folder,
	})
end

local function interactive(model: Instance, part: BasePart, textKey: string, objectKey: string?, hold: number): Interactive
	remember(model)
	return { part = part, prompt = prompt(part, "Prompt", textKey, objectKey, hold), model = model }
end

local function mineFrame(folder: Instance, origin: Vector3, x: number, half: number)
	for _, side in { -1, 1 } do
		decor(make("Part", { Name = "FramePost", Size = Vector3.new(0.7, 9, 0.7), Position = origin + Vector3.new(x, 4.5, side * (half - 0.6)), Color = Palette.log, Parent = folder }))
	end
	decor(make("Part", { Name = "FrameBeam", Size = Vector3.new(0.8, 0.8, half * 2), Position = origin + Vector3.new(x, 9.2, 0), Color = Palette.log, Parent = folder }))
end

function DelveMap.buildCopy(parent: Instance, slot: number, rng: Random): Copy
	local x0, z0 = Delve.slotOrigin(slot)
	local origin = Vector3.new(x0, Delve.FLOOR_Y, z0)
	local folder = Instance.new("Folder")
	folder.Name = "DelveCopy" .. slot
	local function at(x: number, y: number, z: number): Vector3
		return origin + Vector3.new(x, y, z)
	end
	local sections: { [string]: Delve.Section } = {}
	for _, section in Delve.SECTIONS do
		sections[section.id] = section
		shell(folder, origin, section, rng, if section.id == "flooded" then MUD else ROCK[2])
	end
	-- Ściany na końcach i między odcinkami
	make("Part", { Name = "EndWall", Size = Vector3.new(2, Delve.CEILING + 2, 24), Position = at(-1, Delve.CEILING / 2, 0), Color = ROCK[1], Material = Enum.Material.Slate, Parent = folder })
	make("Part", { Name = "EndWall", Size = Vector3.new(2, Delve.CEILING + 2, 44), Position = at(251, Delve.CEILING / 2, 0), Color = ROCK[1], Material = Enum.Material.Slate, Parent = folder })
	crossWall(folder, origin, 18, sections.hall.half + 1, sections.tunnel.half)
	crossWall(folder, origin, 92, sections.flooded.half + 1, sections.tunnel.half)
	crossWall(folder, origin, 172, sections.flooded.half + 1, sections.camp.half)
	crossWall(folder, origin, Delve.SPOTS.cryptDoor, sections.crypt.half + 1, 3)

	-- Sala: miejsce lądowania, szyld, pierwszy hak z olejem
	local spawn = CFrame.lookAt(at(Delve.SPOTS.spawn.x, 3, Delve.SPOTS.spawn.z), at(30, 3, 0))
	for _, hook in Delve.SPOTS.oil do
		oilHook(folder, at(hook.x, 0, hook.z))
	end
	Props.signBoard(folder, CFrame.lookAt(at(17, 11, 0), at(0, 11, 0)), Vector3.new(7, 1.4, 0.3), "DELVE_TUNNEL", Enum.NormalId.Front)
	glowCrystal(folder, at(3, 0, 7), GLOW[1], rng, true)

	-- Chodnik: obudowa górnicza, zawał w poprzek, kupki gruzu pod ścianą
	local tunnel = sections.tunnel
	for x = tunnel.x1 + 6, tunnel.x2 - 4, 10 do
		mineFrame(folder, origin, x, tunnel.half)
	end
	local blockModel = Instance.new("Model")
	blockModel.Name = "Blockage"
	local blockWall = make("Part", {
		Name = "BlockageWall",
		Size = Vector3.new(3, 10, tunnel.half * 2),
		Position = at(Delve.SPOTS.blockage, 5, 0),
		Color = RUBBLE,
		Material = Enum.Material.Slate,
		Parent = blockModel,
	})
	for _ = 1, 10 do
		local s = rng:NextNumber(2, 3.6)
		decor(make("Part", {
			Name = "Rubble",
			Size = Vector3.new(s, s * 0.8, s),
			CFrame = CFrame.new(at(Delve.SPOTS.blockage + rng:NextNumber(-2, 2), rng:NextNumber(0.5, 8.5), rng:NextNumber(-tunnel.half + 1, tunnel.half - 1)))
				* CFrame.Angles(rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, 6.28), 0),
			Color = RUBBLE:Lerp(ROCK[1], rng:NextNumber(0, 0.6)),
			Material = Enum.Material.Slate,
			Parent = blockModel,
		}))
	end
	blockModel.Parent = folder
	local blockage = interactive(blockModel, blockWall, "DELVE_PROMPT_CLEAR", "DELVE_BLOCKAGE", Delve.CLEAR_HOLD.normal)
	local alcoves: { Interactive } = {}
	for i, spot in Delve.SPOTS.alcoves do
		local m = rubblePile(folder, at(spot.x, 0, spot.z), 0.9, rng, "Alcove" .. i)
		local core = make("Part", { Name = "Core", Size = Vector3.new(2.4, 2, 2.4), Position = at(spot.x, 1, spot.z), Transparency = 1, CanCollide = false, Parent = m })
		table.insert(alcoves, interactive(m, core, "DELVE_PROMPT_DIG", "DELVE_ALCOVE", Delve.CLEAR_HOLD.alcove))
	end

	-- Zalana Komora: woda, kładki na palach, wysepki, kryjówki pod ścianami
	local flooded = sections.flooded
	local waterLength = flooded.x2 - flooded.x1
	local water = decor(make("Part", {
		Name = "Water",
		Size = Vector3.new(waterLength, Delve.WATER_Y, flooded.half * 2),
		Position = at(flooded.x1 + waterLength / 2, Delve.WATER_Y / 2, 0),
		Color = WATER,
		Material = Enum.Material.Glass,
		Transparency = 0.35,
		Parent = folder,
	}))
	-- Schodki z Chodnika na kładki (kładki są 3 studs nad dnem)
	for i = 1, 6 do
		make("Part", {
			Name = "Step",
			Size = Vector3.new(1.2, i * 0.5, 4),
			Position = at(85.6 + i, i * 0.25, 0),
			Color = Palette.plankDark,
			Material = Enum.Material.WoodPlanks,
			Parent = folder,
		})
	end
	local route = { { 92, 0 }, { 110, 0 }, { 110, 10 }, { 135, 10 }, { 135, -8 }, { 158, -8 }, { 158, 0 }, { 172, 0 } }
	local floodPlanks: { BasePart } = {}
	for i = 1, #route - 1 do
		local a = at(route[i][1], 0, route[i][2])
		local b = at(route[i + 1][1], 0, route[i + 1][2])
		local length = (b - a).Magnitude + 3.6
		local plank = make("Part", {
			Name = "Walkway",
			Size = Vector3.new(3.6, 0.6, length),
			CFrame = CFrame.lookAt((a + b) / 2 + Vector3.new(0, Delve.WALK_Y - 0.3, 0), b + Vector3.new(0, Delve.WALK_Y - 0.3, 0)),
			Color = Palette.plank,
			Material = Enum.Material.WoodPlanks,
			Parent = folder,
		})
		-- Pale co kilka studs
		local count = math.floor(length / 6)
		for j = 0, count do
			local p = a:Lerp(b, j / math.max(count, 1))
			for _, side in { -1, 1 } do
				local offset = CFrame.lookAt(a, b).RightVector * side * 1.6
				decor(make("Part", {
					Name = "Pile",
					Size = Vector3.new(0.5, Delve.WALK_Y, 0.5),
					Position = p + offset + Vector3.new(0, Delve.WALK_Y / 2 - 0.4, 0),
					Color = Palette.plankDark,
					Parent = folder,
				}))
			end
		end
		-- Wysoka woda zalewa dwa środkowe odcinki (trzeba brodzić)
		if i == 3 or i == 5 then
			plank:SetAttribute("BaseCFrame", plank.CFrame)
			table.insert(floodPlanks, plank)
		end
	end
	-- Wysepki (suche przy zwykłej wodzie, zalane przy wysokiej)
	for _, island in { { 120, -14 }, { 146, 14 }, { 164, -16 } } do
		make("Part", {
			Name = "Island",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2, 7, 7),
			CFrame = CFrame.new(at(island[1], 1, island[2])) * VERTICAL,
			Color = ROCK[3],
			Material = Enum.Material.Slate,
			Parent = folder,
		})
		glowCrystal(folder, at(island[1] + 1.5, 2, island[2] + 1), GLOW[2], rng, true)
	end
	local hides: { Interactive } = {}
	for i, spot in Delve.SPOTS.hides do
		local m = Instance.new("Model")
		m.Name = "Hide" .. i
		local side = if spot.z > 0 then 1 else -1
		local crate = make("Part", {
			Name = "Crate",
			Size = Vector3.new(2.6, 2, 2),
			CFrame = CFrame.new(at(spot.x, 2.2, spot.z)) * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0),
			Color = Palette.plankDark,
			Material = Enum.Material.WoodPlanks,
			Parent = m,
		})
		-- Półka skalna pod skrzynką
		make("Part", { Name = "Ledge", Size = Vector3.new(4, 1.2, 3.4), Position = at(spot.x, 0.6, spot.z + side * 0.4), Color = ROCK[1], Material = Enum.Material.Slate, Parent = m })
		decor(make("Part", { Name = "Band", Size = Vector3.new(2.7, 0.2, 2.1), CFrame = crate.CFrame * CFrame.new(0, 0.4, 0), Color = Palette.metal, Parent = m }))
		m.Parent = folder
		table.insert(hides, interactive(m, crate, "DELVE_PROMPT_SEARCH", "DELVE_HIDE", 1.5))
	end
	local samples: { Interactive } = {}
	for i, spot in Delve.SPOTS.samples do
		local section = Delve.sectionAt(spot.x)
		local y = if section and section.id == "flooded" then 2.2 else 0.4
		local m = Instance.new("Model")
		m.Name = "Sample" .. i
		local orb = make("Part", {
			Name = "Orb",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.2, 1.2, 1.2),
			Position = at(spot.x, y + 0.8, spot.z),
			Color = Color3.fromRGB(120, 255, 200),
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = m,
		})
		if y > 1 then
			make("Part", { Name = "Rock", Size = Vector3.new(2.4, y, 2.4), Position = at(spot.x, y / 2, spot.z), Color = ROCK[3], Material = Enum.Material.Slate, Parent = m })
		end
		local light = Instance.new("PointLight")
		light.Color = orb.Color
		light.Range = 9
		light.Brightness = 1
		light.Parent = orb
		m.Parent = folder
		table.insert(samples, interactive(m, orb, "DELVE_PROMPT_SAMPLE", "DELVE_SAMPLE", 0.8))
	end
	-- Znalezisko, gdy ktoś nie miał miejsca w koszyku (DelveService stawia je w miejscu celu)
	local findModel = Instance.new("Model")
	findModel.Name = "Find"
	local findPart = make("Part", {
		Name = "FindBox",
		Size = Vector3.new(1.8, 1.4, 1.4),
		Position = at(Delve.SPOTS.spawn.x, -20, 0),
		Color = Color3.fromRGB(230, 180, 70),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = findModel,
	})
	findModel.Parent = folder
	local find = interactive(findModel, findPart, "DELVE_PROMPT_TAKE", "DELVE_FIND", 0.5)

	-- Ognisko: zgaszone do zabezpieczenia, lina w górę do obozu, drzwi Krypty
	local camp = sections.camp
	local bonfireModel = Instance.new("Model")
	bonfireModel.Name = "Bonfire"
	local bf = Delve.SPOTS.bonfire
	for i = 0, 7 do
		local angle = i / 8 * math.pi * 2
		make("Part", {
			Size = Vector3.new(0.9, 0.6, 0.9),
			Position = at(bf.x + math.cos(angle) * 1.8, 0.3, bf.z + math.sin(angle) * 1.8),
			Color = Palette.rock[1],
			Material = Enum.Material.Slate,
			Parent = bonfireModel,
		})
	end
	local embers = make("Part", {
		Name = "Embers",
		Size = Vector3.new(2, 0.5, 2),
		Position = at(bf.x, 0.25, bf.z),
		Color = Color3.fromRGB(60, 40, 30),
		Material = Enum.Material.Slate,
		CanCollide = false,
		Parent = bonfireModel,
	})
	local fireEmitter = Instance.new("ParticleEmitter")
	fireEmitter.Texture = "rbxasset://textures/particles/fire_main.dds"
	fireEmitter.Color = ColorSequence.new(Color3.fromRGB(255, 180, 80), Color3.fromRGB(255, 70, 30))
	fireEmitter.LightEmission = 1
	fireEmitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.8), NumberSequenceKeypoint.new(1, 0.2) })
	fireEmitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	fireEmitter.Lifetime = NumberRange.new(0.7, 1.2)
	fireEmitter.Rate = 24
	fireEmitter.Speed = NumberRange.new(2, 3.4)
	fireEmitter.SpreadAngle = Vector2.new(15, 15)
	fireEmitter.EmissionDirection = Enum.NormalId.Top
	fireEmitter.Enabled = false
	fireEmitter.Parent = embers
	local fireLight = Instance.new("PointLight")
	fireLight.Color = Color3.fromRGB(255, 150, 70)
	fireLight.Range = 26
	fireLight.Brightness = 1.6
	fireLight.Enabled = false
	fireLight.Parent = embers
	bonfireModel.Parent = folder
	local bonfire: Interactive = { part = embers, prompt = prompt(embers, "Prompt", "DELVE_PROMPT_SECURE", "DELVE_BONFIRE", 1.2), model = bonfireModel }

	local ex = Delve.SPOTS.exit
	local exitModel = Instance.new("Model")
	exitModel.Name = "Exit"
	local rope = make("Part", {
		Name = "Rope",
		Size = Vector3.new(0.3, Delve.CEILING, 0.3),
		Position = at(ex.x, Delve.CEILING / 2, ex.z),
		Color = Color3.fromRGB(170, 140, 90),
		Material = Enum.Material.Fabric,
		CanCollide = false,
		Parent = exitModel,
	})
	for y = 2, Delve.CEILING - 2, 3 do
		decor(make("Part", { Name = "Knot", Shape = Enum.PartType.Ball, Size = Vector3.new(0.6, 0.6, 0.6), Position = at(ex.x, y, ex.z), Color = rope.Color, Parent = exitModel }))
	end
	local shaftLight = Instance.new("PointLight")
	shaftLight.Color = Color3.fromRGB(255, 220, 160)
	shaftLight.Range = 10
	shaftLight.Brightness = 0.8
	shaftLight.Parent = rope
	exitModel.Parent = folder
	local exit: Interactive = { part = rope, prompt = prompt(rope, "Prompt", "DELVE_PROMPT_EXIT", "DELVE_EXIT", 0.6), model = exitModel }

	local doorModel = Instance.new("Model")
	doorModel.Name = "CryptDoor"
	local doorPart = make("Part", {
		Name = "Door",
		Size = Vector3.new(1.4, 10, 6),
		Position = at(Delve.SPOTS.cryptDoor, 5, 0),
		Color = Color3.fromRGB(70, 60, 56),
		Material = Enum.Material.Slate,
		Parent = doorModel,
	})
	for _, y in { 2.5, 7.5 } do
		decor(make("Part", { Name = "DoorBand", Size = Vector3.new(1.5, 0.4, 6.1), Position = at(Delve.SPOTS.cryptDoor, y, 0), Color = Palette.metal, Parent = doorModel }))
	end
	decor(make("Part", {
		Name = "DoorRune",
		Size = Vector3.new(1.5, 2.2, 2.2),
		CFrame = CFrame.new(at(Delve.SPOTS.cryptDoor, 5, 0)) * CFrame.Angles(math.rad(45), 0, 0),
		Color = Color3.fromRGB(255, 200, 60),
		Material = Enum.Material.Neon,
		Transparency = 0.4,
		Parent = doorModel,
	}))
	doorModel.Parent = folder
	local door = interactive(doorModel, doorPart, "DELVE_PROMPT_DOOR", "DELVE_CRYPT", 1)
	Props.signBoard(folder, CFrame.lookAt(at(Delve.SPOTS.cryptDoor - 1.2, 11.5, 0), at(0, 11.5, 0)), Vector3.new(7, 1.4, 0.3), "DELVE_CRYPT", Enum.NormalId.Front)
	Props.hangingLantern(folder, at(camp.x1 + 3, 10, camp.half - 1.5), 14)

	-- Krypta: dwa rzędy filarów, wnęki z ciemnymi zasłonami, ołtarz z trofeum
	local crypt = sections.crypt
	for _, x in Delve.SPOTS.pillars do
		for _, side in { -1, 1 } do
			make("Part", {
				Name = "Pillar",
				Size = Vector3.new(2.6, Delve.CEILING, 2.6),
				Position = at(x, Delve.CEILING / 2, side * 6.5),
				Color = Color3.fromRGB(84, 74, 70),
				Material = Enum.Material.Cobblestone,
				Parent = folder,
			})
		end
	end
	for _, niche in Delve.SPOTS.niches do
		local mid = (niche.x1 + niche.x2) / 2
		decor(make("Part", {
			Name = "NicheFloor",
			Size = Vector3.new(niche.x2 - niche.x1, 0.1, 4.5),
			Position = at(mid, 0.06, niche.z * (crypt.half - 2.2)),
			Color = Color3.fromRGB(20, 16, 18),
			Parent = folder,
		}))
		for _, x in { niche.x1 - 0.4, niche.x2 + 0.4 } do
			make("Part", {
				Name = "NicheWall",
				Size = Vector3.new(0.8, 8, 4.6),
				Position = at(x, 4, niche.z * (crypt.half - 2.3)),
				Color = ROCK[1],
				Material = Enum.Material.Slate,
				Parent = folder,
			})
		end
		decor(make("Part", {
			Name = "Cobweb",
			Size = Vector3.new(niche.x2 - niche.x1 + 0.8, 2, 0.05),
			Position = at(mid, 7.4, niche.z * (crypt.half - 4.6)),
			Color = Color3.fromRGB(200, 200, 210),
			Transparency = 0.7,
			Parent = folder,
		}))
	end
	local al = Delve.SPOTS.altar
	local altarModel = Instance.new("Model")
	altarModel.Name = "Altar"
	local altarBlock = make("Part", {
		Name = "AltarBlock",
		Size = Vector3.new(3, 3, 5),
		Position = at(al.x, 1.5, al.z),
		Color = Color3.fromRGB(92, 80, 74),
		Material = Enum.Material.Cobblestone,
		Parent = altarModel,
	})
	for _, side in { -1, 1 } do
		local candle = decor(make("Part", { Name = "Candle", Size = Vector3.new(0.4, 1, 0.4), Position = at(al.x, 3.5, al.z + side * 2), Color = Color3.fromRGB(240, 230, 200), Parent = altarModel }))
		local flame = Instance.new("PointLight")
		flame.Color = Color3.fromRGB(255, 180, 90)
		flame.Range = 8
		flame.Brightness = 0.8
		flame.Parent = candle
	end
	altarModel.Parent = folder
	local relic = make("Part", {
		Name = "CryptRelic",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.6, 1.6, 1.6),
		Position = at(al.x, 4, al.z),
		Color = Color3.fromRGB(255, 210, 90),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = folder,
	})
	local relicLight = Instance.new("PointLight")
	relicLight.Color = relic.Color
	relicLight.Range = 14
	relicLight.Brightness = 1.4
	relicLight.Parent = relic
	remember(relic)
	local altar: Interactive = { part = altarBlock, prompt = prompt(altarBlock, "Prompt", "DELVE_PROMPT_ALTAR", "DELVE_TROPHY", 2.5), model = altarModel }
	for i = 1, 4 do
		glowCrystal(folder, at(crypt.x1 + 8 + i * 10, 0, (if i % 2 == 0 then 1 else -1) * (crypt.half - 1)), GLOW[1], rng, i % 2 == 0)
	end

	folder.Parent = parent
	local first = Delve.SPOTS.patrol[1]
	return {
		slot = slot,
		origin = origin,
		folder = folder,
		spawn = spawn,
		blockage = blockage,
		alcoves = alcoves,
		hides = hides,
		samples = samples,
		find = find,
		water = water,
		floodPlanks = floodPlanks,
		bonfire = bonfire,
		fire = { fireEmitter, fireLight },
		exit = exit,
		door = door,
		altar = altar,
		relic = relic,
		guardHome = CFrame.lookAt(at(first.x, 0, first.z), at(first.x + 10, 0, first.z)),
	}
end

-- Wysoka woda: podnosi lustro wody i zatapia dwa odcinki kładek
function DelveMap.setFlood(copy: Copy, flood: boolean)
	local height = if flood then Delve.FLOOD_Y else Delve.WATER_Y
	local water = copy.water
	water.Size = Vector3.new(water.Size.X, height, water.Size.Z)
	water.Position = Vector3.new(water.Position.X, Delve.FLOOR_Y + height / 2, water.Position.Z)
	for _, plank in copy.floodPlanks do
		local base = plank:GetAttribute("BaseCFrame")
		if typeof(base) == "CFrame" then
			plank.CFrame = if flood then base * CFrame.new(0, -(Delve.WALK_Y - 0.6), 0) else base
		end
	end
end

-- Ogień w ognisku (po zabezpieczeniu znaleziska)
function DelveMap.setFire(copy: Copy, lit: boolean)
	for _, instance in copy.fire do
		if instance:IsA("ParticleEmitter") then
			instance.Enabled = lit
		elseif instance:IsA("PointLight") then
			instance.Enabled = lit
		end
	end
	copy.bonfire.part.Color = if lit then Color3.fromRGB(255, 120, 40) else Color3.fromRGB(60, 40, 30)
	copy.bonfire.part.Material = if lit then Enum.Material.Neon else Enum.Material.Slate
end

return DelveMap
