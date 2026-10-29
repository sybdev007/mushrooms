--!strict
-- Animuje wszystkich Leszych w świecie (tag "LeszyRig"): posąg w gnieździe śpi skulony i oddycha,
-- goniący Leszy idzie albo biegnie zależnie od prędkości (liczonej z ruchu pivotu, który przesuwa serwer),
-- a kiedy dopiero się budzi, trzęsie się i prostuje. Ciężkie kroki dają łupnięcie, gdy jest blisko.
-- Modele z atrybutem Scripted (np. aktor z cutscenki) animuje kto inny.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LeszyRig = require(ReplicatedStorage.Shared.LeszyRig)
local Audio = require(script.Parent.Audio)

local LeszyAnimator = {}

local RUN_SPEED = 22 -- studs/s, prędkość pościgu (Config.Leszy.speed) = pełny bieg
local MAX_DISTANCE = 260 -- dalej nikt nie zobaczy różnicy

type Entry = {
	rig: LeszyRig.Rig,
	last: Vector3?,
	speed: number, -- wygładzona 0..1
	phase: number,
	stand: number, -- 0 skulony (śpi), 1 wyprostowany
	lastSin: number,
}

local entries: { [Model]: Entry } = {}

local function track(model: Instance)
	if not model:IsA("Model") or entries[model] or not model:IsDescendantOf(Workspace) then
		return
	end
	entries[model] = {
		rig = LeszyRig.new(model),
		last = nil,
		speed = 0,
		phase = 0,
		stand = if model:GetAttribute("Awake") == true then 1 else 0,
		lastSin = 0,
	}
end

local function untrack(model: Instance)
	local entry = entries[model :: Model]
	if entry then
		LeszyRig.destroy(entry.rig)
		entries[model :: Model] = nil
	end
end

local function step(dt: number)
	local camera = Workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	local now = os.clock()
	for model, entry in entries do
		if model.Parent == nil then
			untrack(model)
			continue
		end
		if model:GetAttribute("Scripted") == true or not model.PrimaryPart then
			continue
		end
		local pivot = model:GetPivot()
		local position = pivot.Position
		if (position - eye).Magnitude > MAX_DISTANCE then
			entry.last = nil
			continue
		end
		-- Prędkość z przesunięcia pivotu (serwer przesuwa go co klatkę)
		local velocity = 0
		local last = entry.last
		if last and dt > 0 then
			velocity = Vector3.new(position.X - last.X, 0, position.Z - last.Z).Magnitude / dt
		end
		entry.last = position
		-- Skarbnik i Utopiec mają własną prędkość pościgu (atrybut RunSpeed z RigBlocks)
		local runSpeed = model:GetAttribute("RunSpeed")
		local target = math.clamp(velocity / (if typeof(runSpeed) == "number" and runSpeed > 0 then runSpeed else RUN_SPEED), 0, 1)
		entry.speed += (target - entry.speed) * math.min(1, dt * 6)
		local awake = model:GetAttribute("Awake") == true or model:GetAttribute("Moving") == true
		entry.stand += ((if awake then 1 else 0) - entry.stand) * math.min(1, dt * 2.2)
		-- Faza kroku rośnie z prędkością (duże kroki: ok. 1 krok na 3,5 studa)
		entry.phase += dt * (1.2 + entry.speed * 7.4)

		local pose, hips = LeszyRig.gait(now, entry.phase, entry.speed)
		local crouch = 1 - entry.stand
		if crouch > 0.01 then
			local cPose, cHips = LeszyRig.crouch(0.55, now)
			pose, hips = LeszyRig.mix(pose, hips, cPose, cHips, crouch)
		end
		LeszyRig.apply(entry.rig, pivot, pose, hips)

		-- Łupnięcie przy każdym kroku, kiedy biegnie blisko kamery
		local s = math.sin(entry.phase)
		if entry.speed > 0.3 and (s > 0) ~= (entry.lastSin > 0) then
			local distance = (position - eye).Magnitude
			if distance < 60 then
				Audio.play("footstep", { volume = 1.4 * (1 - distance / 60), pitch = 0.45, jitter = 0.08, at = position })
			end
		end
		entry.lastSin = s
	end
end

function LeszyAnimator.start()
	for _, model in CollectionService:GetTagged("LeszyRig") do
		track(model)
	end
	CollectionService:GetInstanceAddedSignal("LeszyRig"):Connect(track)
	CollectionService:GetInstanceRemovedSignal("LeszyRig"):Connect(untrack)
	RunService.RenderStepped:Connect(step)
end

return LeszyAnimator
