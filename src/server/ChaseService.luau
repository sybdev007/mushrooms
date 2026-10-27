--!strict
-- Pościg strażnika skarbu. Zerwanie strzeżonego grzyba budzi strażnika: posąg otwiera oczy,
-- a z jego legowiska rusza potwór, który przenika przez przeszkody i goni gracza prosto do
-- bezpiecznej strefy (chatka albo obozowisko). Dogoni = gracz traci koszyk. Dobiegnie = ucieczka.
-- Każdy goniony gracz ma własnego potwora, ale wszyscy na serwerze go widzą.
-- Ten sam kod obsługuje Leszego w lesie i Skarbnika w jaskini (ChaseService.new).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Economy = require(ReplicatedStorage.Shared.Economy)

export type Hooks = {
	onCaught: (Player) -> (),
	onEscaped: (Player) -> (),
	onGaveUp: (Player) -> (),
}

export type Settings = {
	speed: number,
	wakeDelay: number,
	catchRadius: number,
	giveUpSeconds: number,
}

export type Options = {
	name: string, -- nazwa folderu i modeli ("Leszy", "Skarbnik")
	origin: Vector3?, -- skąd rusza potwór (środek legowiska)
	statue: Model?, -- uśpiony posąg, któremu zapalamy oczy podczas pościgu
	settings: Settings,
	build: (parent: Instance, at: CFrame, awake: boolean) -> Model,
	setAwake: (model: Model, awake: boolean) -> (),
	hooks: Hooks,
}

type Chase = {
	player: Player,
	model: Model,
	position: Vector3, -- na ziemi
	startedAt: number,
	wakeAt: number,
}

export type Chaser = {
	isChased: (Player) -> boolean,
	stop: (Player) -> (),
	startChase: (Player, Vector3?) -> boolean,
}

local ChaseService = {}

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Potwór rozpływa się w mroku zamiast znikać w jednej klatce
local function fadeOut(model: Model)
	local info = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Transparency < 1 then
			TweenService:Create(descendant, info, { Transparency = 1 }):Play()
		elseif descendant:IsA("Light") then
			TweenService:Create(descendant, info, { Brightness = 0 }):Play()
		end
	end
	task.delay(1, function()
		model:Destroy()
	end)
end

function ChaseService.new(options: Options): Chaser
	local chases: { [Player]: Chase } = {}
	local settings = options.settings
	local hooks = options.hooks
	local folder = Instance.new("Folder")
	folder.Name = options.name .. "Chases"
	folder.Parent = Workspace

	local function countChases(): number
		local n = 0
		for _ in chases do
			n += 1
		end
		return n
	end

	local self = {} :: Chaser

	function self.isChased(player: Player): boolean
		return chases[player] ~= nil
	end

	-- Kończy pościg bez wołania hooków (gracz wyszedł, zgasła mu latarnia, wszedł w portal itp.)
	function self.stop(player: Player)
		local chase = chases[player]
		if not chase then
			return
		end
		chases[player] = nil
		fadeOut(chase.model)
		if options.statue and countChases() == 0 then
			options.setAwake(options.statue, false)
		end
	end

	-- Zwraca true, jeśli pościg właśnie się zaczął
	function self.startChase(player: Player, from: Vector3?): boolean
		if chases[player] then
			return false
		end
		local origin = options.origin or from
		local root = getRoot(player)
		if not origin or not root then
			return false
		end
		local position = Vector3.new(origin.X, origin.Y, origin.Z)
		local target = Vector3.new(root.Position.X, origin.Y, root.Position.Z)
		local look = if (target - position).Magnitude > 0.1 then CFrame.lookAt(position, target) else CFrame.new(position)
		local model = options.build(folder, look, true)
		model.Name = options.name .. "_" .. player.Name

		local now = os.clock()
		chases[player] = {
			player = player,
			model = model,
			position = position,
			startedAt = now,
			wakeAt = now + settings.wakeDelay,
		}
		if options.statue then
			options.setAwake(options.statue, true)
		end
		return true
	end

	local function step(dt: number)
		local now = os.clock()
		for player, chase in chases do
			local root = getRoot(player)
			if not root or player.Parent == nil then
				self.stop(player)
				continue
			end
			if Economy.isSafeZone(Economy.zoneIndexAt(root.Position.Z)) then
				self.stop(player)
				hooks.onEscaped(player)
				continue
			end
			if now - chase.startedAt > settings.giveUpSeconds then
				self.stop(player)
				hooks.onGaveUp(player)
				continue
			end

			local target = Vector3.new(root.Position.X, chase.position.Y, root.Position.Z)
			local toTarget = target - chase.position
			local distance = toTarget.Magnitude
			local awake = now >= chase.wakeAt
			if awake and distance > 0.05 then
				local move = math.min(settings.speed * dt, distance)
				chase.position += toTarget.Unit * move
				distance -= move
			end

			-- Krok: lekkie podskoki i kołysanie na boki; przed ruszeniem drży, jakby się budził
			local t = now * (if awake then 7 else 18)
			local bob = if awake then math.abs(math.sin(t)) * 0.35 else 0
			local sway = if awake then math.sin(t) * 0.06 else math.sin(t) * 0.02
			local look = if distance > 0.1 then CFrame.lookAt(chase.position, target) else CFrame.new(chase.position)
			local root = chase.model.PrimaryPart
			if chase.model:GetAttribute("Rig") == true and root then
				-- Model ze szkieletem (Leszy): serwer przesuwa tylko pivot, ręce i nogi rusza klient (LeszyAnimator).
				-- Do tego mniej danych po sieci niż przy przesuwaniu każdej części.
				root.CFrame = look * root.PivotOffset:Inverse()
				chase.model:SetAttribute("Moving", awake)
			else
				chase.model:PivotTo(look * CFrame.new(0, bob, 0) * CFrame.Angles(0, 0, sway))
			end

			if awake and distance <= settings.catchRadius then
				self.stop(player)
				hooks.onCaught(player)
			end
		end
	end

	RunService.Heartbeat:Connect(step)
	Players.PlayerRemoving:Connect(self.stop)
	return self
end

return ChaseService
