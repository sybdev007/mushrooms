--!strict
-- Modele reliktów z ekspedycji (Shared/Delve.RELICS) z kilku klocków, ok. 1,4 studs: kilof, lampa
-- karbidowa, hełm sztygara, mapa, ognista geoda, perła w muszli, dzwonek Skarbnika, skamieniały grzyb.
-- Odnowiony relikt ma pełne kolory, świecące elementy i światło; zakurzony jest szary i matowy.
-- Model ma niewidzialną część "Core" (PrimaryPart) w środku; klient (RelicDisplay) obraca go i podpisuje.

local RelicArt = {}

RelicArt.SCALE = 1.5

local DUST = Color3.fromRGB(120, 116, 110)
local WOOD = Color3.fromRGB(124, 86, 56)
local IRON = Color3.fromRGB(84, 84, 90)
local BRASS = Color3.fromRGB(214, 170, 74)
local VERTICAL = CFrame.Angles(0, 0, math.rad(90))

type Builder = (add: (string, Vector3, CFrame, Color3, Enum.Material?, boolean?) -> BasePart, color: Color3) -> ()

local BUILDERS: { [string]: Builder } = {
	miner_pick = function(add, color)
		add("Block", Vector3.new(0.2, 1.6, 0.2), CFrame.Angles(0, 0, math.rad(-25)), WOOD)
		local head = CFrame.new(0.32, 0.68, 0) * CFrame.Angles(0, 0, math.rad(-25))
		add("Block", Vector3.new(1.2, 0.24, 0.24), head, IRON, Enum.Material.Metal)
		add("Wedge", Vector3.new(0.24, 0.24, 0.4), head * CFrame.new(-0.78, 0, 0) * CFrame.Angles(0, math.rad(90), 0), IRON, Enum.Material.Metal)
		add("Wedge", Vector3.new(0.24, 0.24, 0.4), head * CFrame.new(0.78, 0, 0) * CFrame.Angles(0, math.rad(-90), 0), IRON, Enum.Material.Metal)
		add("Ball", Vector3.new(0.16, 0.16, 0.16), head * CFrame.new(0.3, 0.14, 0), color, Enum.Material.Neon, true)
	end,
	miner_lamp = function(add, color)
		add("Cylinder", Vector3.new(0.18, 0.8, 0.8), CFrame.new(0, -0.55, 0) * VERTICAL, BRASS, Enum.Material.Metal)
		add("Cylinder", Vector3.new(0.7, 0.56, 0.56), CFrame.new(0, -0.1, 0) * VERTICAL, BRASS, Enum.Material.Metal)
		add("Ball", Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, 0.38, 0), color, Enum.Material.Neon, true)
		add("Cylinder", Vector3.new(0.1, 0.62, 0.62), CFrame.new(0, 0.66, 0) * VERTICAL, BRASS, Enum.Material.Metal)
		add("Block", Vector3.new(0.08, 0.5, 0.08), CFrame.new(-0.3, 0.92, 0) * CFrame.Angles(0, 0, math.rad(-35)), IRON)
		add("Block", Vector3.new(0.08, 0.5, 0.08), CFrame.new(0.3, 0.92, 0) * CFrame.Angles(0, 0, math.rad(35)), IRON)
	end,
	miner_helmet = function(add, color)
		add("Ball", Vector3.new(1.1, 0.9, 1.1), CFrame.new(0, 0.05, 0), color, Enum.Material.SmoothPlastic)
		add("Cylinder", Vector3.new(0.1, 1.5, 1.5), CFrame.new(0, -0.32, 0) * VERTICAL, color:Lerp(Color3.new(0, 0, 0), 0.2))
		add("Block", Vector3.new(1.2, 0.36, 0.9), CFrame.new(0, -0.55, 0), color, Enum.Material.SmoothPlastic)
		add("Cylinder", Vector3.new(0.2, 0.34, 0.34), CFrame.new(0, 0.18, -0.55) * CFrame.Angles(0, math.rad(90), 0), IRON, Enum.Material.Metal)
		add("Cylinder", Vector3.new(0.06, 0.26, 0.26), CFrame.new(0, 0.18, -0.66) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(255, 240, 180), Enum.Material.Neon, true)
	end,
	miner_map = function(add, color)
		local sheet = CFrame.Angles(math.rad(-55), 0, 0)
		add("Block", Vector3.new(1.3, 0.05, 1), sheet, Color3.fromRGB(226, 206, 160))
		add("Cylinder", Vector3.new(1.36, 0.16, 0.16), sheet * CFrame.new(0, 0.04, -0.52), Color3.fromRGB(206, 182, 132))
		add("Cylinder", Vector3.new(1.36, 0.16, 0.16), sheet * CFrame.new(0, 0.04, 0.52), Color3.fromRGB(206, 182, 132))
		add("Block", Vector3.new(0.7, 0.06, 0.06), sheet * CFrame.new(-0.1, 0.04, 0.05) * CFrame.Angles(0, math.rad(30), 0), color, Enum.Material.Neon, true)
		add("Block", Vector3.new(0.06, 0.06, 0.5), sheet * CFrame.new(0.25, 0.04, -0.15) * CFrame.Angles(0, math.rad(20), 0), color, Enum.Material.Neon, true)
		add("Block", Vector3.new(0.22, 0.07, 0.05), sheet * CFrame.new(0.35, 0.05, 0.25) * CFrame.Angles(0, math.rad(45), 0), Color3.fromRGB(220, 60, 50), Enum.Material.Neon, true)
		add("Block", Vector3.new(0.22, 0.07, 0.05), sheet * CFrame.new(0.35, 0.05, 0.25) * CFrame.Angles(0, math.rad(-45), 0), Color3.fromRGB(220, 60, 50), Enum.Material.Neon, true)
	end,
	deep_geode = function(add, color)
		add("Ball", Vector3.new(1.2, 0.95, 1.1), CFrame.new(0, -0.1, 0.05), Color3.fromRGB(70, 56, 52), Enum.Material.Slate)
		for i = 1, 5 do
			local angle = i / 5 * math.pi * 2
			add(
				"Block",
				Vector3.new(0.16, 0.5 + (i % 2) * 0.2, 0.16),
				CFrame.new(math.cos(angle) * 0.22, 0.22, -0.32 + math.sin(angle) * 0.12) * CFrame.Angles(math.rad(-30), angle, math.rad(15)),
				color,
				Enum.Material.Neon,
				true
			)
		end
	end,
	deep_pearl = function(add, color)
		add("Ball", Vector3.new(1.3, 0.3, 1.1), CFrame.new(0, -0.4, 0), Color3.fromRGB(196, 168, 150), Enum.Material.Marble)
		add("Ball", Vector3.new(1.3, 0.3, 1.1), CFrame.new(0, 0.15, 0.42) * CFrame.Angles(math.rad(-55), 0, 0), Color3.fromRGB(210, 182, 164), Enum.Material.Marble)
		add("Ball", Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, -0.12, -0.08), color, Enum.Material.Neon, true)
	end,
	deep_bell = function(add, color)
		add("Ball", Vector3.new(0.85, 0.85, 0.85), CFrame.new(0, 0.18, 0), color, Enum.Material.Metal)
		add("Cylinder", Vector3.new(0.5, 1, 1), CFrame.new(0, -0.18, 0) * VERTICAL, color, Enum.Material.Metal)
		add("Cylinder", Vector3.new(0.1, 1.16, 1.16), CFrame.new(0, -0.45, 0) * VERTICAL, color:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.Metal)
		add("Ball", Vector3.new(0.22, 0.22, 0.22), CFrame.new(0, -0.58, 0), IRON, Enum.Material.Metal)
		add("Cylinder", Vector3.new(0.08, 0.36, 0.36), CFrame.new(0, 0.66, 0) * CFrame.Angles(0, math.rad(90), 0), IRON, Enum.Material.Metal)
		add("Ball", Vector3.new(0.12, 0.12, 0.12), CFrame.new(0, 0.2, -0.43), Color3.fromRGB(255, 240, 200), Enum.Material.Neon, true)
	end,
	deep_fossil = function(add, color)
		add("Cylinder", Vector3.new(0.8, 0.38, 0.38), CFrame.new(0, -0.32, 0) * VERTICAL, Color3.fromRGB(150, 140, 126), Enum.Material.Slate)
		add("Ball", Vector3.new(1.3, 0.7, 1.3), CFrame.new(0, 0.18, 0), Color3.fromRGB(120, 112, 104), Enum.Material.Slate)
		for i = 1, 4 do
			local angle = i / 4 * math.pi * 2 + 0.4
			add(
				"Block",
				Vector3.new(0.5, 0.06, 0.08),
				CFrame.new(math.cos(angle) * 0.42, 0.3, math.sin(angle) * 0.42) * CFrame.Angles(0, -angle, math.rad(25)),
				color,
				Enum.Material.Neon,
				true
			)
		end
		add("Ball", Vector3.new(0.18, 0.18, 0.18), CFrame.new(0.2, 0.5, -0.2), color, Enum.Material.Neon, true)
	end,
}

-- Buduje relikt nad `at` (środek modelu). restored = pełne kolory i światło, inaczej zakurzony.
function RelicArt.build(parent: Instance, relicId: string, color: Color3, at: CFrame, restored: boolean): Model
	local model = Instance.new("Model")
	model.Name = "Relic_" .. relicId
	local core = Instance.new("Part")
	core.Name = "Core"
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.Transparency = 1
	core.Size = Vector3.new(0.2, 0.2, 0.2)
	core.CFrame = at
	core.Parent = model
	model.PrimaryPart = core

	local function add(shape: string, size: Vector3, offset: CFrame, partColor: Color3, material: Enum.Material?, _glows: boolean?): BasePart
		local part: BasePart
		if shape == "Wedge" then
			part = Instance.new("WedgePart")
		else
			local p = Instance.new("Part")
			p.Shape = if shape == "Ball" then Enum.PartType.Ball elseif shape == "Cylinder" then Enum.PartType.Cylinder else Enum.PartType.Block
			part = p
		end
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Size = size
		part.CFrame = at * offset
		if restored then
			part.Color = partColor
			part.Material = material or Enum.Material.SmoothPlastic
		else
			-- Zakurzony: szary, matowy, bez świecenia
			part.Color = partColor:Lerp(DUST, 0.7)
			part.Material = Enum.Material.Slate
		end
		part.Parent = model
		return part
	end

	local builder = BUILDERS[relicId]
	if builder then
		builder(add, color)
	else
		add("Ball", Vector3.new(0.8, 0.8, 0.8), CFrame.new(), color, Enum.Material.Neon, true)
	end
	-- Na podeście relikt ma być widać z dróżki: 1,5× większy (światło daje płytka postumentu)
	model:ScaleTo(RelicArt.SCALE)
	model.Parent = parent
	return model
end

return RelicArt
