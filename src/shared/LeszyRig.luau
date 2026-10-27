--!strict
-- Szkielet Leszego bez Humanoida: model z klocków (Leszy.build na serwerze) ma kości jako atrybuty.
--   Każda część ma atrybut Limb (do której kości należy) i Rest (położenie względem pivotu w pozie spoczynkowej).
--   Model ma atrybuty J_<kość> (staw w układzie modelu). Hierarchia kości jest stała (PARENT niżej).
-- Pozę liczymy co klatkę: dla każdej kości obrót wokół jej stawu, złożony z obrotem rodzica,
-- i przesuwamy wszystkie części jednym BulkMoveTo. Działa tak samo w cutscence i w pościgu w grze.

local Workspace = game:GetService("Workspace")

local LeszyRig = {}

export type Pose = { [string]: CFrame }

local ORDER = { "Hips", "Torso", "Head", "UpperArmL", "ForearmL", "UpperArmR", "ForearmR", "ThighL", "ShinL", "ThighR", "ShinR" }
local PARENT: { [string]: string } = {
	Hips = "",
	Torso = "Hips",
	Head = "Torso",
	UpperArmL = "Torso",
	ForearmL = "UpperArmL",
	UpperArmR = "Torso",
	ForearmR = "UpperArmR",
	ThighL = "Hips",
	ShinL = "ThighL",
	ThighR = "Hips",
	ShinR = "ThighR",
}
LeszyRig.ORDER = ORDER
LeszyRig.PARENT = PARENT

export type Rig = {
	model: Model,
	parts: { BasePart },
	rests: { CFrame },
	limbs: { string },
	joints: { [string]: Vector3 },
	dirty: boolean,
	connections: { RBXScriptConnection },
}

local function collect(rig: Rig)
	table.clear(rig.parts)
	table.clear(rig.rests)
	table.clear(rig.limbs)
	for _, d in rig.model:GetDescendants() do
		if d:IsA("BasePart") then
			local limb = d:GetAttribute("Limb")
			local rest = d:GetAttribute("Rest")
			if typeof(limb) == "string" and typeof(rest) == "CFrame" then
				table.insert(rig.parts, d)
				table.insert(rig.rests, rest)
				table.insert(rig.limbs, limb)
			end
		end
	end
	for _, limb in ORDER do
		local j = rig.model:GetAttribute("J_" .. limb)
		rig.joints[limb] = if typeof(j) == "Vector3" then j else Vector3.zero
	end
	rig.dirty = false
end

function LeszyRig.isRig(model: Instance): boolean
	return model:IsA("Model") and model:GetAttribute("Rig") == true
end

function LeszyRig.new(model: Model): Rig
	local rig: Rig = {
		model = model,
		parts = {},
		rests = {},
		limbs = {},
		joints = {},
		dirty = true,
		connections = {},
	}
	-- Przy StreamingEnabled części dochodzą i znikają w trakcie gry
	table.insert(rig.connections, model.DescendantAdded:Connect(function()
		rig.dirty = true
	end))
	table.insert(rig.connections, model.DescendantRemoving:Connect(function()
		rig.dirty = true
	end))
	collect(rig)
	return rig
end

function LeszyRig.destroy(rig: Rig)
	for _, c in rig.connections do
		c:Disconnect()
	end
	table.clear(rig.connections)
end

local IDENTITY = CFrame.new()

-- Ustawia model: pivot (na ziemi pod stopami, przód -Z), poza kości i przesunięcie bioder (podskok, kucnięcie)
function LeszyRig.apply(rig: Rig, pivot: CFrame, pose: Pose, hips: CFrame?)
	if rig.dirty then
		collect(rig)
	end
	local world: { [string]: CFrame } = { [""] = pivot }
	for _, limb in ORDER do
		local parentCf = world[PARENT[limb]]
		if limb == "Hips" and hips then
			parentCf = parentCf * hips
		end
		local r = pose[limb]
		if r then
			local j = rig.joints[limb]
			world[limb] = parentCf * CFrame.new(j) * r * CFrame.new(-j)
		else
			world[limb] = parentCf
		end
	end
	local parts = rig.parts
	local cfs = table.create(#parts)
	for i, part in parts do
		cfs[i] = (world[rig.limbs[i]] or pivot) * rig.rests[i]
	end
	if #parts > 0 then
		Workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- ===== Pozy =====
-- Kąty w stopniach. Przód to -Z, więc obrót +X uda/ramienia = noga/ręka do przodu, -X tułowia = pochylenie.

local function rx(d: number): CFrame
	return CFrame.Angles(math.rad(d), 0, 0)
end
local function ry(d: number): CFrame
	return CFrame.Angles(0, math.rad(d), 0)
end
local function rz(d: number): CFrame
	return CFrame.Angles(0, 0, math.rad(d))
end
local function lerp(a: number, b: number, k: number): number
	return a + (b - a) * k
end

-- Chód i bieg. t = czas (s), phase = faza kroku (radiany, rośnie z prędkością), speed 0 = stoi, 0.5 = idzie, 1 = biegnie.
-- Oddech i kołysanie głowy działają zawsze, więc stojący Leszy też żyje.
function LeszyRig.gait(t: number, phase: number, speed: number): (Pose, CFrame)
	local walk = math.clamp(speed * 2, 0, 1)
	local run = math.clamp((speed - 0.5) * 2, 0, 1)
	local still = 1 - walk
	local s = math.sin(phase)
	local c = math.cos(phase)
	local legA = walk * lerp(26, 46, run)
	local armA = walk * lerp(20, 42, run)
	local kneeB = walk * lerp(34, 70, run)
	local breath = math.sin(t * 1.7)
	local pose: Pose = {
		Torso = rx(-(5 + 20 * run) + breath * 2 * still) * ry(s * 7 * walk),
		Head = rx(4 + 14 * run + math.sin(t * 1.2) * 3 * still) * ry(math.sin(t * 0.6) * 10 * still - s * 5 * walk),
		UpperArmL = rx(-s * armA + breath * 3 * still + 6) * rz(-7),
		UpperArmR = rx(s * armA - breath * 3 * still + 6) * rz(7),
		ForearmL = rx(14 + 22 * run + math.max(0, -s) * 14 * walk),
		ForearmR = rx(14 + 22 * run + math.max(0, s) * 14 * walk),
		ThighL = rx(s * legA),
		ThighR = rx(-s * legA),
		-- Kolano zgina się, kiedy noga przechodzi do przodu
		ShinL = rx(-(4 + kneeB * math.max(0, c))),
		ShinR = rx(-(4 + kneeB * math.max(0, -c))),
	}
	-- Najwyżej, kiedy nogi się mijają, najniżej przy szerokim kroku
	local bob = walk * lerp(0.18, 0.55, run) * (0.5 - math.abs(s))
	local hips = CFrame.new(0, bob + breath * 0.05 * still, 0) * rz(s * 3 * walk) * ry(-s * 4 * walk)
	return pose, hips
end

-- Przykucnięty / wyłażący z ziemi (k = 1 skulony, 0 stoi). Bez oddechu – dodaje go gait przy mieszaniu.
function LeszyRig.crouch(k: number, t: number): (Pose, CFrame)
	local tremble = math.noise(t * 9, 3.1) * 4 * k
	local pose: Pose = {
		Torso = rx(-48 * k + tremble),
		Head = rx(-20 * k + 30 * k * k),
		UpperArmL = rx(34 * k) * rz(-10 * k),
		UpperArmR = rx(34 * k) * rz(10 * k),
		ForearmL = rx(30 * k),
		ForearmR = rx(30 * k),
		ThighL = rx(70 * k) * rz(-8 * k),
		ThighR = rx(70 * k) * rz(8 * k),
		ShinL = rx(-105 * k),
		ShinR = rx(-105 * k),
	}
	return pose, CFrame.new(0, -2.3 * k, 0)
end

-- Ryk: odchyla się, ręce w górę i na boki, łeb do tyłu, trzęsie się (k = siła 0..1)
function LeszyRig.roar(k: number, t: number): (Pose, CFrame)
	local shake = math.noise(t * 22, 7.7) * 5 * k
	local pose: Pose = {
		Torso = rx(16 * k + shake * 0.4),
		Head = rx(32 * k + shake) * ry(shake),
		UpperArmL = rx(55 * k) * rz(-75 * k),
		UpperArmR = rx(55 * k) * rz(75 * k),
		ForearmL = rx(40 * k) * rz(-10 * k),
		ForearmR = rx(40 * k) * rz(10 * k),
		ThighL = rx(14 * k) * rz(-9 * k),
		ThighR = rx(-10 * k) * rz(9 * k),
		ShinL = rx(-18 * k),
		ShinR = rx(-6 * k),
	}
	return pose, CFrame.new(0, -0.35 * k, 0)
end

-- Rzut z łapami do przodu (łapie gracza)
function LeszyRig.lunge(k: number): (Pose, CFrame)
	local pose: Pose = {
		Torso = rx(-40 * k),
		Head = rx(28 * k),
		UpperArmL = rx(118 * k) * rz(8 * k),
		UpperArmR = rx(118 * k) * rz(-8 * k),
		ForearmL = rx(-6 * k),
		ForearmR = rx(-6 * k),
		ThighL = rx(48 * k),
		ShinL = rx(-50 * k),
		ThighR = rx(-34 * k),
		ShinR = rx(-14 * k),
	}
	return pose, CFrame.new(0, -0.7 * k, 0)
end

-- Miesza dwie pozy (k = 0 → a, 1 → b)
function LeszyRig.mix(a: Pose, ah: CFrame, b: Pose, bh: CFrame, k: number): (Pose, CFrame)
	local out: Pose = {}
	for _, limb in ORDER do
		local x = a[limb] or IDENTITY
		local y = b[limb] or IDENTITY
		out[limb] = x:Lerp(y, k)
	end
	return out, ah:Lerp(bh, k)
end

-- Składa dwie pozy (np. pościg + ryk na chwilę): obrót b dokładany po obrocie a
function LeszyRig.add(a: Pose, ah: CFrame, b: Pose, bh: CFrame): (Pose, CFrame)
	local out: Pose = {}
	for _, limb in ORDER do
		out[limb] = (a[limb] or IDENTITY) * (b[limb] or IDENTITY)
	end
	return out, ah * bh
end

return LeszyRig
