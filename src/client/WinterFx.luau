--!strict
-- Zima po stronie gracza (tylko gdy serwer włączy Zimę, atrybut Workspace.Winter):
--   śnieg na ziemi i drzewach w lesie: każdy klient przebarwia u siebie trawę, korony drzew, krzaki
--   i tło za lasem (bez zmian na serwerze i bez ruchu w sieci); po Zimie kolory wracają;
--   padający śnieg wokół kamery w lesie i na polanie (nie pod dachem chatki, nie w innych światach);
--   szybka latarni w dłoni świeci lodowym światłem, gdy gracz ma psikus z choinki (atrybut FrostLantern
--   barwi Main.client razem z GhostLantern).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Economy)
local Winter = require(Shared.Winter)

local WinterFx = {}

local SNOW_GROUND = Color3.fromRGB(226, 234, 244)
local SNOW = Color3.fromRGB(246, 250, 255)
-- Ile bieli: ziemia prawie cała, zieleń drzew i krzaków do połowy (zostaje kolor pod śniegiem)
local GROUND_AMOUNT = 0.82
local GREEN_AMOUNT = 0.55
-- Foldery mapy ze śniegiem (las i polana); reszta (jaskinia, bagna, góra, chatka) bez zmian
local SNOWY_FOLDERS = { Border = true, Backdrop_Forest = true, Backdrop_Clearing = true, Gardens = true }

local originals: { [BasePart]: Color3 } = {}
local connections: { RBXScriptConnection } = {}
local on = false

local function eventOn(): boolean
	local attr = Workspace:GetAttribute("Winter")
	if typeof(attr) == "boolean" then
		return attr
	end
	return Winter.active(Workspace:GetServerTimeNow())
end

-- Zieleń liści, trawy i mchu (pnie, kamienie, grzyby i dekoracje zostają)
local function isGreen(color: Color3): boolean
	return color.G > color.R + 0.03 and color.G > color.B + 0.02
end

local function whiten(part: BasePart, target: Color3, amount: number)
	if originals[part] then
		return
	end
	originals[part] = part.Color
	part.Color = part.Color:Lerp(target, amount)
end

local function snowPart(part: Instance, groundLike: boolean)
	-- Świecące rzeczy (grzyby w lesie, lampki) i grzyby posadzone w ogródkach zostają w swoich kolorach
	if not part:IsA("BasePart") or part.Material == Enum.Material.Neon or part:FindFirstAncestor("Planted") then
		return
	end
	if groundLike then
		whiten(part, SNOW_GROUND, GROUND_AMOUNT)
	elseif isGreen(part.Color) then
		whiten(part, SNOW, GREEN_AMOUNT)
	end
end

-- Czy element mapy dostaje śnieg: ziemia stref lasu, drzewa i krzaki z obrzeża i stref lasu, tło
local function snowyRoot(child: Instance): (boolean, boolean)
	local name = child.Name
	if string.sub(name, 1, 7) == "Ground_" then
		return true, true
	end
	return SNOWY_FOLDERS[name] == true or string.sub(name, 1, 6) == "Decor_", false
end

local function apply(map: Instance)
	local count = 0
	for _, child in map:GetChildren() do
		local snowy, groundLike = snowyRoot(child)
		if snowy then
			snowPart(child, groundLike)
			for _, d in child:GetDescendants() do
				snowPart(d, false)
				count += 1
				if count % 3000 == 0 then
					task.wait()
					if not on then
						return
					end
				end
			end
			-- Części wczytane później (StreamingEnabled)
			table.insert(
				connections,
				child.DescendantAdded:Connect(function(d)
					if on then
						snowPart(d, false)
					end
				end)
			)
		end
	end
	table.insert(
		connections,
		map.ChildAdded:Connect(function(child)
			if not on then
				return
			end
			local snowy, groundLike = snowyRoot(child)
			if snowy then
				snowPart(child, groundLike)
				for _, d in child:GetDescendants() do
					snowPart(d, false)
				end
			end
		end)
	)
end

local function restore()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for part, color in originals do
		if part.Parent then
			part.Color = color
		end
	end
	table.clear(originals)
end

-- ===== Padający śnieg =====

local emitterPart = Instance.new("Part")
emitterPart.Name = "Snowfall"
emitterPart.Anchored = true
emitterPart.CanCollide = false
emitterPart.CanTouch = false
emitterPart.CanQuery = false
emitterPart.Transparency = 1
emitterPart.Size = Vector3.new(90, 1, 90)
local snowfall = Instance.new("ParticleEmitter")
snowfall.Name = "Snow"
snowfall.Texture = "rbxasset://textures/particles/smoke_main.dds"
snowfall.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
snowfall.LightEmission = 0.25
snowfall.LightInfluence = 0.6
snowfall.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.22), NumberSequenceKeypoint.new(1, 0.16) })
snowfall.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.1, 0.1), NumberSequenceKeypoint.new(0.85, 0.2), NumberSequenceKeypoint.new(1, 1) })
snowfall.Lifetime = NumberRange.new(5, 7)
snowfall.Speed = NumberRange.new(4, 7)
snowfall.EmissionDirection = Enum.NormalId.Bottom
snowfall.SpreadAngle = Vector2.new(12, 12)
snowfall.Acceleration = Vector3.new(0.6, 0, 0.3)
snowfall.RotSpeed = NumberRange.new(-60, 60)
snowfall.Shape = Enum.ParticleEmitterShape.Box
snowfall.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
snowfall.Rate = 140
snowfall.Enabled = false
snowfall.Parent = emitterPart

local roofParams = RaycastParams.new()
roofParams.FilterType = Enum.RaycastFilterType.Exclude

-- Kamera w lesie albo na polanie i nie pod dachem chatki
local function snowHere(camera: Camera): boolean
	local position = camera.CFrame.Position
	local zone = Economy.zoneIndexAt(position.Z)
	if Economy.zoneWorld(zone) ~= "forest" or position.Y > 200 then
		return false
	end
	local character = Players.LocalPlayer.Character
	roofParams.FilterDescendantsInstances = if character then { character, emitterPart } else { emitterPart }
	local hit = Workspace:Raycast(position, Vector3.new(0, 40, 0), roofParams)
	local cabin = hit and hit.Instance:FindFirstAncestor("Cabin")
	return cabin == nil
end

local function setOn(value: boolean)
	if value == on then
		return
	end
	on = value
	if on then
		local map = Workspace:FindFirstChild("Map") or Workspace:WaitForChild("Map", 30)
		if map then
			task.spawn(apply, map)
		end
	else
		restore()
		snowfall.Enabled = false
		emitterPart.Parent = nil
	end
end

function WinterFx.start()
	setOn(eventOn())
	Workspace:GetAttributeChangedSignal("Winter"):Connect(function()
		setOn(eventOn())
	end)
	local check = 0
	RunService.RenderStepped:Connect(function(dt)
		if not on then
			return
		end
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		emitterPart.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 26, 0))
		if emitterPart.Parent ~= camera then
			emitterPart.Parent = camera
		end
		check += dt
		if check >= 0.3 then
			check = 0
			snowfall.Enabled = snowHere(camera)
		end
	end)
end

return WinterFx
