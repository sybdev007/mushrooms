--!strict
-- Kruki Baby Jagi (Łysa Góra: Wiedźmi Las i Kotły Sabatu). Co jakiś czas kruk upatruje sobie gracza
-- z grzybami w koszyku: na ziemi w miejscu gracza pojawia się cień z fioletową obwódką, kruk krąży
-- wysoko, a po Config.Ravens.warn sekundach nurkuje. Kto nie zdążył odskoczyć, traci najtańszy grzyb
-- z koszyka; kruk upuszcza go kilka kroków dalej i grzyb leży tam przez Config.Ravens.dropSeconds.
-- Wystarczy po niego podejść (tylko właściciel). Przy ogniskach sabatu kruki nie atakują.
-- Uczy ruchu, nie zabiera dużo (wzór: kamienie z ekspedycji, DelveService).
-- Kruk i cień są na serwerze (widzą je wszyscy), a grzyb na ziemi rysuje każdy klient
-- (DisplayMushrooms, tag "RavenDrop"), tak jak grzyby w skarbcu strażnika.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local MountainShared = require(ReplicatedStorage.Shared.Mountain)

export type Item = { s: string, v: string?, x: { string }? }

export type Hooks = {
	takeCheapest: (Player) -> Item?, -- zabiera najtańszy grzyb z koszyka (nil: pusty)
	giveBack: (Player, Item) -> boolean, -- oddaje grzyb do koszyka (false: brak miejsca)
	notify: (Player, string, { any }?) -> (),
	rootOf: (Player) -> BasePart?,
}

export type Ravens = {
	-- Co krok serwera dla gracza, który jest w lesie (nie w obozie, nie leży)
	step: (player: Player, zone: number, root: BasePart, basketCount: number, now: number) -> (),
	-- Gracz wyszedł albo stracił koszyk: jego grzyby na ziemi znikają
	forget: (player: Player) -> (),
	-- Panel DEV: następny kruk od razu (gdy gracz jest w strefie kruków i ma coś w koszyku)
	devNow: (player: Player) -> (),
}

local RavenService = {}

local PICKUP_RADIUS = 4
local FIRE_SAFE = 10 -- tak blisko ogniska sabatu kruki nie atakują
local CIRCLE_HEIGHT = 22
local SHADOW = Color3.fromRGB(16, 8, 24)
local WARN = Color3.fromRGB(170, 80, 255)
local BLACK = Color3.fromRGB(22, 20, 28)
local BLACK_SHINE = Color3.fromRGB(46, 40, 70)
local BEAK = Color3.fromRGB(70, 66, 60)
local EYE = Color3.fromRGB(255, 70, 70)

type Drop = { model: Model, owner: Player, item: Item, ground: Vector3, fullNoticeAt: number }

local function part(props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

-- Kruk z klocków: tułów, głowa z dziobem i czerwonymi oczkami, rozpostarte skrzydła i ogon.
-- Przód to -Z. Wszystko przyspawane do niewidzialnego "Root", więc rusza się cały naraz.
local function buildRaven(parent: Instance, at: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "Raven"
	local root = part({ Name = "Root", Size = Vector3.new(0.6, 0.6, 0.6), CFrame = at, Transparency = 1, Parent = m })
	m.PrimaryPart = root
	local function piece(name: string, size: Vector3, offset: CFrame, color: Color3, neon: boolean?): BasePart
		local p = part({ Name = name, Size = size, CFrame = at * offset, Color = color, Parent = m })
		if neon then
			p.Material = Enum.Material.Neon
		end
		p.Anchored = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = p
		weld.Parent = p
		return p
	end
	piece("Body", Vector3.new(1.1, 0.9, 2.2), CFrame.new(0, 0, 0), BLACK)
	piece("Back", Vector3.new(0.8, 0.2, 1.6), CFrame.new(0, 0.5, 0.1), BLACK_SHINE)
	piece("Head", Vector3.new(0.8, 0.8, 0.8), CFrame.new(0, 0.35, -1.35), BLACK)
	piece("Beak", Vector3.new(0.3, 0.26, 0.8), CFrame.new(0, 0.25, -2.1) * CFrame.Angles(math.rad(-8), 0, 0), BEAK)
	for _, side in { -1, 1 } do
		piece("Eye", Vector3.new(0.14, 0.14, 0.14), CFrame.new(side * 0.36, 0.48, -1.55), EYE, true)
		-- Skrzydło z dwóch klocków: szersze przy tułowiu, węższe na końcu, lekko w górę
		piece("Wing", Vector3.new(1.8, 0.16, 1.4), CFrame.new(side * 1.4, 0.15, 0) * CFrame.Angles(0, 0, math.rad(side * 12)), BLACK)
		piece("WingTip", Vector3.new(1.4, 0.12, 0.9), CFrame.new(side * 2.95, 0.45, 0.25) * CFrame.Angles(0, math.rad(side * -10), math.rad(side * 18)), BLACK_SHINE)
	end
	piece("Tail", Vector3.new(0.9, 0.14, 1.1), CFrame.new(0, 0.05, 1.5) * CFrame.Angles(math.rad(8), 0, 0), BLACK)
	local whoosh = Instance.new("Sound")
	whoosh.Name = "Whoosh"
	whoosh.SoundId = Config.Audio.sfx.whoosh
	whoosh.Volume = 0.7
	whoosh.RollOffMaxDistance = 80
	whoosh.Parent = root
	m.Parent = parent
	return m
end

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Czy w pobliżu płonie ognisko sabatu (tag "SabbathFire", World/Mountain)
local function nearFire(at: Vector3): boolean
	for _, fire in CollectionService:GetTagged("SabbathFire") do
		if fire:IsA("BasePart") and flat(fire.Position, at) <= FIRE_SAFE then
			return true
		end
	end
	return false
end

-- Strefy kruków od pierwszej do ostatniej (z) — żeby upuszczony grzyb nie wylądował w obozie ani za bramą
local function ravenBounds(): (number, number)
	local z1, z2 = math.huge, -math.huge
	for _, zone in Config.Zones do
		if MountainShared.ravenZone(zone.id) then
			z1 = math.min(z1, zone.startZ)
			z2 = math.max(z2, zone.endZ)
		end
	end
	return z1, z2
end

function RavenService.start(hooks: Hooks): Ravens
	local settings = Config.Ravens
	local folder = Instance.new("Folder")
	folder.Name = "Ravens"
	folder.Parent = Workspace
	local rng = Random.new()
	local nextAt: { [Player]: number } = {}
	local busy: { [Player]: boolean } = {}
	local drops: { Drop } = {}
	local minZ, maxZ = ravenBounds()
	local halfWidth = Config.Mountain.halfWidth - 6

	local function schedule(player: Player, now: number)
		if not player.Parent then
			nextAt[player] = nil -- wyszedł w trakcie ataku
			return
		end
		nextAt[player] = now + settings.every * rng:NextNumber(0.7, 1.3)
	end

	local function removeDrop(drop: Drop)
		local index = table.find(drops, drop)
		if index then
			table.remove(drops, index)
		end
		if drop.model.Parent then
			drop.model:Destroy()
		end
	end

	-- Grzyb upuszczony przez kruka: znacznik jak w skarbcu strażnika (DisplayMushrooms rysuje grzyba)
	local function placeDrop(owner: Player, item: Item, ground: Vector3)
		local model = Instance.new("Model")
		model.Name = "RavenDrop"
		local root = part({ Name = "Root", Size = Vector3.new(1.6, 1.6, 1.6), Position = ground + Vector3.new(0, 0.8, 0), Transparency = 1, Parent = model })
		model.PrimaryPart = root
		-- Fioletowa obwódka na ziemi: widać, gdzie leży, nawet w ciemności
		part({
			Name = "Ring",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.06, 3.2, 3.2),
			CFrame = CFrame.new(ground + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = WARN,
			Material = Enum.Material.Neon,
			Transparency = 0.55,
			Parent = model,
		})
		model:SetAttribute("Species", item.s)
		model:SetAttribute("Variant", item.v or "")
		model:SetAttribute("Tags", table.concat(item.x or {}, ","))
		model:SetAttribute("Ground", ground)
		model:SetAttribute("Owner", owner.UserId)
		model:SetAttribute("Fresh", true)
		CollectionService:AddTag(model, "RavenDrop")
		model.Parent = folder
		local drop: Drop = { model = model, owner = owner, item = item, ground = ground, fullNoticeAt = 0 }
		table.insert(drops, drop)
		task.delay(3, function()
			if model.Parent then
				model:SetAttribute("Fresh", false)
			end
		end)
		task.delay(settings.dropSeconds, function()
			if table.find(drops, drop) then
				removeDrop(drop)
				if owner.Parent then
					hooks.notify(owner, "MSG_RAVEN_DROP_GONE")
				end
			end
		end)
	end

	local function tween(instance: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
		local t = TweenService:Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Sine, direction or Enum.EasingDirection.InOut), goal)
		t:Play()
		return t
	end

	-- Jeden atak: cień i krążący kruk, nurkowanie, a potem (jeśli trafił) odlot z grzybem i upuszczenie
	local function strike(player: Player, target: Vector3)
		busy[player] = true
		local ground = Vector3.new(target.X, 0, target.Z)
		local radius = settings.radius
		local shadow = part({
			Name = "RavenShadow",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.05, 1, 1),
			CFrame = CFrame.new(ground + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = SHADOW,
			Transparency = 0.8,
			Parent = folder,
		})
		local ring = part({
			Name = "RavenWarning",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.07, radius * 2, radius * 2),
			CFrame = CFrame.new(ground + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = WARN,
			Material = Enum.Material.Neon,
			Transparency = 0.5,
			Parent = folder,
		})
		tween(shadow, settings.warn, { Size = Vector3.new(0.05, radius * 2, radius * 2), Transparency = 0.35 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

		-- Kruk nadlatuje z boku i zawisa wysoko nad celem
		local angle = rng:NextNumber(0, math.pi * 2)
		local from = ground + Vector3.new(math.cos(angle) * 40, CIRCLE_HEIGHT + 8, math.sin(angle) * 40)
		local above = ground + Vector3.new(0, CIRCLE_HEIGHT, 0)
		local heading = ((ground - from) * Vector3.new(1, 0, 1)).Unit
		local raven = buildRaven(folder, CFrame.lookAt(from, above))
		local root = raven.PrimaryPart :: BasePart
		tween(root, settings.warn * 0.85, { CFrame = CFrame.lookAt(above, above + heading) })
		task.wait(settings.warn)

		-- Nurkowanie
		local whoosh = root:FindFirstChild("Whoosh")
		if whoosh and whoosh:IsA("Sound") then
			whoosh:Play()
		end
		local low = ground + Vector3.new(0, 1.5, 0)
		local dive = tween(root, 0.32, { CFrame = CFrame.lookAt(low, low + heading) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		dive.Completed:Wait()
		ring:Destroy()
		shadow:Destroy()

		local hit = false
		local playerRoot = hooks.rootOf(player)
		if playerRoot and flat(playerRoot.Position, ground) <= radius + 0.5 then
			local item = hooks.takeCheapest(player)
			if item then
				hit = true
				hooks.notify(player, "MSG_RAVEN_HIT")
				-- Odlatuje nisko kawałek dalej i upuszcza grzyb (w granicach stref kruków)
				local away = rng:NextNumber(0, math.pi * 2)
				local drop = ground + Vector3.new(math.cos(away), 0, math.sin(away)) * settings.dropDistance
				drop = Vector3.new(math.clamp(drop.X, -halfWidth, halfWidth), 0, math.clamp(drop.Z, minZ + 6, maxZ - 6))
				local away3 = drop - ground
				local carryHeading = if away3.Magnitude > 0.1 then away3.Unit else heading
				local carry = tween(root, 0.8, { CFrame = CFrame.lookAt(drop + Vector3.new(0, 4, 0), drop + Vector3.new(0, 4, 0) + carryHeading) })
				carry.Completed:Wait()
				placeDrop(player, item, drop)
			end
		end
		-- Odlot w górę i znika
		local exitAt = root.Position + Vector3.new(rng:NextNumber(-30, 30), 40, rng:NextNumber(-30, 30))
		local leave = tween(root, 1.4, { CFrame = CFrame.lookAt(exitAt, exitAt + (exitAt - root.Position)) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		leave.Completed:Wait()
		raven:Destroy()
		busy[player] = nil
		-- Po trafieniu kruk daje dłużej spokój (gracz i tak biegnie po grzyb)
		schedule(player, os.clock() + (if hit then settings.every * 0.5 else 0))
	end

	local self = {} :: Ravens

	function self.step(player: Player, zone: number, root: BasePart, basketCount: number, now: number)
		-- Podnoszenie upuszczonych grzybów (tylko właściciel, wystarczy podejść)
		for i = #drops, 1, -1 do
			local drop = drops[i]
			if drop.owner == player and flat(root.Position, drop.ground) <= PICKUP_RADIUS then
				if hooks.giveBack(player, drop.item) then
					removeDrop(drop)
				elseif now - drop.fullNoticeAt > 4 then
					drop.fullNoticeAt = now
					hooks.notify(player, "MSG_BASKET_FULL")
				end
			end
		end
		if busy[player] then
			return
		end
		local def = Config.Zones[zone]
		if not def or not MountainShared.ravenZone(def.id) or basketCount == 0 or nearFire(root.Position) then
			schedule(player, now)
			return
		end
		local due = nextAt[player]
		if not due then
			schedule(player, now)
			return
		end
		if now < due then
			return
		end
		-- Cel: tam, gdzie gracz stoi (z małym rozrzutem). Kto idzie, ten zdąży wyjść z cienia.
		local spread = rng:NextNumber(0, 1.5)
		local a = rng:NextNumber(0, math.pi * 2)
		local target = root.Position + Vector3.new(math.cos(a) * spread, 0, math.sin(a) * spread)
		task.spawn(function()
			local ok, err = pcall(function()
				strike(player, target)
			end)
			if not ok then
				warn("[RavenService] " .. tostring(err))
				busy[player] = nil
				schedule(player, os.clock())
			end
		end)
	end

	function self.devNow(player: Player)
		nextAt[player] = 0
	end

	function self.forget(player: Player)
		for i = #drops, 1, -1 do
			if drops[i].owner == player then
				removeDrop(drops[i])
			end
		end
		nextAt[player] = nil
	end

	return self
end

return RavenService
