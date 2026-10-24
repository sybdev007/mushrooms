--!strict
-- Pościg Leszego. Zerwanie Korony Leszego w gnieździe budzi go: posąg otwiera oczy,
-- a z gniazda rusza Leszy, który przenika przez drzewa i goni gracza prosto do chatki.
-- Dogoni = gracz traci koszyk (jak przy zgaśnięciu latarni). Dobiegnie do polany = ucieczka.
-- Każdy goniony gracz ma własnego Leszego, ale wszyscy na serwerze go widzą.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)
local World = script.Parent:WaitForChild("World")
local Leszy = require(World:WaitForChild("Leszy"))

export type Hooks = {
	onCaught: (Player) -> (),
	onEscaped: (Player) -> (),
	onGaveUp: (Player) -> (),
}

type Chase = {
	player: Player,
	model: Model,
	position: Vector3, -- na ziemi
	startedAt: number,
	wakeAt: number,
}

local LeszyService = {}

local chases: { [Player]: Chase } = {}
local hooks: Hooks
local groveCenter: Vector3? = nil
local statue: Model? = nil
local folder: Folder

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function countChases(): number
	local n = 0
	for _ in chases do
		n += 1
	end
	return n
end

-- Leszy rozpływa się w mroku zamiast znikać w jednej klatce
local function fadeOut(model: Model)
	local info = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Transparency < 1 then
			TweenService:Create(descendant, info, { Transparency = 1 }):Play()
		elseif descendant:IsA("PointLight") then
			TweenService:Create(descendant, info, { Brightness = 0 }):Play()
		end
	end
	task.delay(1, function()
		model:Destroy()
	end)
end

function LeszyService.isChased(player: Player): boolean
	return chases[player] ~= nil
end

-- Kończy pościg bez wołania hooków (gracz wyszedł, zgasła mu latarnia itp.)
function LeszyService.stop(player: Player)
	local chase = chases[player]
	if not chase then
		return
	end
	chases[player] = nil
	fadeOut(chase.model)
	if statue and countChases() == 0 then
		Leszy.setAwake(statue, false)
	end
end

-- Zwraca true, jeśli pościg właśnie się zaczął
function LeszyService.startChase(player: Player, from: Vector3?): boolean
	if chases[player] then
		return false
	end
	local origin = groveCenter or from
	local root = getRoot(player)
	if not origin or not root then
		return false
	end
	local position = Vector3.new(origin.X, 0, origin.Z)
	local target = Vector3.new(root.Position.X, 0, root.Position.Z)
	local look = if (target - position).Magnitude > 0.1 then CFrame.lookAt(position, target) else CFrame.new(position)
	local model = Leszy.build(folder, look, true)
	model.Name = "Leszy_" .. player.Name

	local now = os.clock()
	chases[player] = {
		player = player,
		model = model,
		position = position,
		startedAt = now,
		wakeAt = now + Config.Leszy.wakeDelay,
	}
	if statue then
		Leszy.setAwake(statue, true)
	end
	return true
end

local function step(_dt: number)
	local now = os.clock()
	for player, chase in chases do
		local root = getRoot(player)
		if not root or player.Parent == nil then
			LeszyService.stop(player)
			continue
		end
		if Economy.zoneIndexAt(root.Position.Z) == 1 then
			LeszyService.stop(player)
			hooks.onEscaped(player)
			continue
		end
		if now - chase.startedAt > Config.Leszy.giveUpSeconds then
			LeszyService.stop(player)
			hooks.onGaveUp(player)
			continue
		end

		local target = Vector3.new(root.Position.X, 0, root.Position.Z)
		local toTarget = target - chase.position
		local distance = toTarget.Magnitude
		local awake = now >= chase.wakeAt
		if awake and distance > 0.05 then
			local move = math.min(Config.Leszy.speed * _dt, distance)
			chase.position += toTarget.Unit * move
			distance -= move
		end

		-- Krok: lekkie podskoki i kołysanie na boki; przed ruszeniem drży, jakby się budził
		local t = now * (if awake then 7 else 18)
		local bob = if awake then math.abs(math.sin(t)) * 0.35 else 0
		local sway = if awake then math.sin(t) * 0.06 else math.sin(t) * 0.02
		local look = if distance > 0.1 then CFrame.lookAt(chase.position, target) else CFrame.new(chase.position)
		chase.model:PivotTo(look * CFrame.new(0, bob, 0) * CFrame.Angles(0, 0, sway))

		if awake and distance <= Config.Leszy.catchRadius then
			LeszyService.stop(player)
			hooks.onCaught(player)
		end
	end
end

function LeszyService.start(center: Vector3?, statueModel: Model?, serviceHooks: Hooks)
	groveCenter = center
	statue = statueModel
	hooks = serviceHooks
	folder = Instance.new("Folder")
	folder.Name = "Leszies"
	folder.Parent = Workspace
	RunService.Heartbeat:Connect(step)
	Players.PlayerRemoving:Connect(LeszyService.stop)
end

return LeszyService
