--!strict
-- Skarbiec strażnika (Leszego w lesie, Skarbnika w jaskini). Gdy strażnik złapie gracza, odbiera mu
-- swoje grzyby i odnosi je do legowiska. Leżą tam dla wszystkich: kto pierwszy dobiegnie i przytrzyma
-- przycisk, ten je zabiera (i budzi strażnika). Grzyby w skarbcu są wspólne, w przeciwieństwie do
-- zwykłych, więc serwer trzyma je w Workspace (znacznik z przyciskiem), a wygląd jak w lesie rysuje
-- każdy klient (DisplayMushrooms).
-- Każdy skarbiec to osobny obiekt: HoardService.new(...).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)

export type Item = { s: string, v: string?, x: { string }? }

export type Hooks = {
	-- Zwraca true, jeśli gracz zabrał grzyb (miejsce w koszyku itp. sprawdza GameService)
	take: (Player, Item) -> boolean,
}

export type Hoard = {
	drop: (items: { Item }) -> number,
	count: () -> number,
}

local HoardService = {}

local PROMPT_TAG = "LocalizedPrompt" -- klient (Signs) wpisuje teksty przycisku w języku gracza

-- groveCenter: środek legowiska, name: nazwa folderu w Workspace
function HoardService.new(groveCenter: Vector3?, name: string, serviceHooks: Hooks): Hoard
	local center = groveCenter
	local hooks = serviceHooks
	local slots: { Model? } = {}
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = Workspace
	local self = {} :: Hoard

	local function part(props: { [string]: any }): BasePart
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Material = Enum.Material.SmoothPlastic
		for key, value in props do
			(p :: any)[key] = value
		end
		return p
	end

	local function slotPosition(index: number): Vector3
		local origin = center or Vector3.zero
		if index == 1 then
			return origin
		end
		local angle = (index - 2) / (Config.Hoard.maxItems - 1) * math.pi * 2
		return origin + Vector3.new(math.cos(angle), 0, math.sin(angle)) * Config.Hoard.radius
	end

	-- Znacznik grzyba: niewidzialny "Root" z przyciskiem zabrania; samego grzyba (ten sam model co w lesie,
	-- z aurami) rysuje każdy klient (DisplayMushrooms, tag "HoardMushroom")
	local function build(item: Item, index: number): Model
		local base = slotPosition(index)
		local model = Instance.new("Model")
		model.Name = "HoardCrown"
		local stem = part({
			Name = "Root",
			Size = Vector3.new(1.6, 1.6, 1.6),
			Position = base + Vector3.new(0, 0.8, 0),
			Transparency = 1,
			CanQuery = false,
			Parent = model,
		})
		model.PrimaryPart = stem
		model:SetAttribute("Species", item.s)
		model:SetAttribute("Variant", item.v or "")
		model:SetAttribute("Tags", table.concat(item.x or {}, ","))
		model:SetAttribute("Ground", base)
		-- Świeżo odniesiony grzyb wyrasta z ziemi; kto wejdzie później, widzi go od razu
		model:SetAttribute("Fresh", true)
		task.delay(3, function()
			if model.Parent then
				model:SetAttribute("Fresh", false)
			end
		end)
		CollectionService:AddTag(model, "HoardMushroom")

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "Take"
		prompt.HoldDuration = 0.6
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.ActionText = "Take"
		local species = Economy.getSpecies(item.s)
		prompt.ObjectText = item.s
		prompt:SetAttribute("TextKey", "PROMPT_TAKE_CROWN")
		prompt:SetAttribute("ObjectKey", if species then species.key else "MUSH_LESZY_CROWN")
		CollectionService:AddTag(prompt, PROMPT_TAG)
		prompt.Parent = stem

		prompt.Triggered:Connect(function(player: Player)
			if slots[index] ~= model then
				return -- ktoś był szybszy
			end
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not (root and root:IsA("BasePart")) then
				return
			end
			local offset = root.Position - base
			if Vector3.new(offset.X, 0, offset.Z).Magnitude > Config.Hoard.takeDistance then
				return
			end
			if hooks.take(player, item) then
				slots[index] = nil
				model:Destroy()
			end
		end)

		model.Parent = folder
		return model
	end

	-- Kładzie korony w skarbcu. Zwraca, ile się zmieściło (reszta przepada).
	function self.drop(items: { Item }): number
		if not center then
			return 0
		end
		local placed = 0
		for _, item in items do
			for index = 1, Config.Hoard.maxItems do
				if not slots[index] then
					slots[index] = build(item, index)
					placed += 1
					break
				end
			end
		end
		return placed
	end

	function self.count(): number
		local n = 0
		for index = 1, Config.Hoard.maxItems do
			if slots[index] then
				n += 1
			end
		end
		return n
	end

	return self
end

return HoardService
