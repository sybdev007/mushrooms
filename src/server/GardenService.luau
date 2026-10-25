--!strict
-- Ogródki graczy, jak w Steal an Egg. Każdy gracz na serwerze dostaje jeden.
--   Sadzenie: właściciel sadzi najcenniejsze grzyby z koszyka na wolnych grządkach; lepszy grzyb
--   wypiera najsłabszy posadzony (ten jest sprzedawany). Posadzone grzyby co minutę sypią monety
--   do skrzyni przy furtce (także offline, do limitu). Właściciel odbiera monety przy skrzyni.
--   Kradzież: inny gracz trzyma przycisk (2 s + kłódka) i wyrywa najcenniejszy grzyb. Niesie go
--   nad głową wolniej niż zwykle, podświetlony na czerwono. Doniesie do swojego ogródka = łup jego.
--   Właściciel go dotknie = grzyb wraca. Wyjdzie z polany albo minie minuta = grzyb wraca.
--
-- Przyciski to ProximityPrompt (telefon, klawiatura, pad). Serwer tworzy wszystkie, a klient
-- (src/client/GardenPrompts.luau) pokazuje tylko te, które dotyczą danego gracza.
-- Każdą akcję i tak sprawdza serwer.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)

type Data = {
	coins: number,
	basket: { Economy.BasketItem },
	planted: { Economy.PlantItem },
	pot: number,
	incomeAt: number,
	upgrades: { [string]: number },
}

type MutationInfo = { variant: string?, tags: { string }? }

export type Api = {
	getData: (Player) -> Data?,
	basketMax: (Player) -> number,
	notify: (Player, string, { any }?, string?, MutationInfo?) -> (),
	pushState: (Player) -> (),
	applyStats: (Player) -> (), -- przelicza prędkość chodu (łup spowalnia)
	onEvent: ((Player, string, number?) -> ())?, -- zadania dzienne: "plant", "collect", "steal"
}

type GardenState = {
	id: number,
	model: Model,
	hub: BasePart,
	chest: BasePart?,
	soils: { BasePart },
	slots: { Attachment },
	lockTags: { BillboardGui },
	slotLabels: { TextLabel },
	visuals: Folder,
	label: TextLabel,
	potLabel: TextLabel?,
	ownerSign: TextLabel?,
	owner: Player?,
	protectedUntil: number,
	stealPrompt: ProximityPrompt,
	contentKey: string?,
}

type Carry = {
	item: Economy.PlantItem,
	owner: Player,
	startedAt: number,
	visuals: { Instance },
}

local GardenService = {}

local INCOME_TICK = 1
local VISUAL_REFRESH = 3
local STEAL_RANGE = 12 -- serwer jest łagodniejszy niż prompt przez opóźnienie sieci
local SOIL = Color3.fromRGB(86, 60, 42)
local SOIL_LOCKED = Color3.fromRGB(52, 44, 40)
local STEM_COLOR = Color3.fromRGB(232, 222, 200)
local RATE_COLOR = "#A6F06A"

local api: Api
local gardens: { GardenState } = {}
local gardenOf: { [Player]: GardenState } = {}
local carries: { [Player]: Carry } = {}
local thiefLast: { [Player]: number } = {}
local holdStarted: { [Player]: number } = {}

-- ===== Pomocnicze =====

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function distanceTo(player: Player, part: BasePart): number
	local root = getRoot(player)
	return if root then flatDistance(root.Position, part.Position) else math.huge
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function capColor(item: Economy.BasketItem): Color3
	local variant = Economy.getVariant(item.v)
	if variant then
		return rgb(variant.color)
	end
	local species = Economy.getSpecies(item.s)
	return rgb(species and species.cap or { 160, 120, 80 })
end

local function stat(player: Player?, id: string): number
	local data = player and api.getData(player)
	local level = if data then data.upgrades[id] or 0 else 0
	return Economy.upgradeStat(id, level)
end

local function bedsOf(garden: GardenState, player: Player?): number
	return math.min(stat(player, "beds"), #garden.slots)
end

local function formatRate(rate: number): string
	return if rate < 10 then string.format("%.1f", rate) else tostring(math.floor(rate + 0.5))
end

local function formatCoins(value: number): string
	local s = tostring(math.floor(value + 0.5))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (formatted:gsub("^ ", ""))
end

local function mutationIcons(item: Economy.BasketItem): string
	local icons = ""
	local variant = Economy.getVariant(item.v)
	if variant then
		icons ..= variant.icon
	end
	for _, id in item.x or {} do
		local tag = Economy.getTag(id)
		if tag then
			icons ..= tag.icon
		end
	end
	return icons
end

local function speciesKey(item: Economy.BasketItem): string?
	local species = Economy.getSpecies(item.s)
	return species and species.key or nil
end

-- Zawsze tabela (także pusta): szablony komunikatów mają miejsce na etykietę mutacji
local function mutationOf(item: Economy.BasketItem): MutationInfo
	return { variant = item.v, tags = item.x }
end

-- Czy pozycja leży w danym ogródku (z małym zapasem za płotem)
local function insideGarden(garden: GardenState, position: Vector3): boolean
	local localPos = garden.model:GetPivot():PointToObjectSpace(position)
	local half = Config.Garden.size / 2 + 1
	return math.abs(localPos.X) <= half and math.abs(localPos.Z) <= half
end

-- ===== Wygląd =====

local function newPart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

-- Grzyb na grządce: trzon i kapelusz w kolorze gatunku albo wariantu, z efektami mutacji.
-- base: punkt na ziemi pod grzybem. Zwraca model (do przyspawania na głowie złodzieja też).
local function buildMushroom(parent: Instance, item: Economy.BasketItem, base: CFrame, scale: number?): Model
	local s = scale or 1
	local group = Instance.new("Model")
	group.Name = "PlantedMushroom"
	local stem = newPart(group, "Stem", Vector3.new(1.3, 0.55, 0.55) * s, base * CFrame.new(0, 0.65 * s, 0) * CFrame.Angles(0, 0, math.rad(90)), STEM_COLOR)
	stem.Shape = Enum.PartType.Cylinder
	local cap = newPart(group, "Cap", Vector3.new(2, 1.1, 2) * s, base * CFrame.new(0, 1.35 * s, 0), capColor(item))
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = cap

	local rank = Economy.variantRank(item.v)
	if rank >= 2 then
		cap.Material = Enum.Material.Neon
	elseif rank == 1 then
		cap.Material = Enum.Material.Metal
		cap.Reflectance = 0.3
	end
	local species = Economy.getSpecies(item.s)
	if rank >= 2 or (species and (species.grove or species.lair or species.guardian)) then
		local light = Instance.new("PointLight")
		light.Color = cap.Color
		light.Range = 8
		light.Brightness = 1.2
		light.Parent = cap
	end
	if rank >= 1 then
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkles.Color = ColorSequence.new(cap.Color, Color3.new(1, 1, 1))
		sparkles.LightEmission = 1
		sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
		sparkles.Lifetime = NumberRange.new(0.8, 1.3)
		sparkles.Speed = NumberRange.new(0.4, 1.2)
		sparkles.SpreadAngle = Vector2.new(180, 180)
		sparkles.Rate = ({ 2, 5, 12 })[rank] or 3
		sparkles.Parent = cap
	end
	for _, id in item.x or {} do
		local tag = Economy.getTag(id)
		if tag and id == "mossy" then
			newPart(group, "Moss", Vector3.new(1.1, 0.2, 1.1) * s, cap.CFrame * CFrame.new(0.3 * s, 0.45 * s, 0.2 * s), rgb(tag.color))
		elseif tag then
			-- Cechy świecące (blask, kryształ, żar): poświata w kolorze cechy
			local light = Instance.new("PointLight")
			light.Color = rgb(tag.color)
			light.Range = 6
			light.Brightness = 1.4
			light.Parent = cap
		end
	end
	group.PrimaryPart = cap
	group.Parent = parent
	return group
end

local function billboard(parent: Instance, name: string, size: UDim2, offset: Vector3, maxDistance: number): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Size = size
	gui.StudsOffset = offset
	gui.MaxDistance = maxDistance
	gui.LightInfluence = 0
	gui.Parent = parent
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(255, 236, 190)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.RichText = true
	label.Text = ""
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(50, 30, 16)
	stroke.Parent = label
	return label
end

-- Tabliczka nad grządką: mutacje, wartość i dochód na minutę. To ona kusi złodziei.
local function slotLabel(slot: Attachment): TextLabel
	local label = billboard(slot, "SlotTag", UDim2.fromOffset(100, 42), Vector3.new(0, 3.4, 0), 45)
	label.BackgroundColor3 = Color3.fromRGB(40, 28, 20)
	label.BackgroundTransparency = 0.25
	label.TextColor3 = Color3.fromRGB(255, 226, 140)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 3)
	padding.PaddingBottom = UDim.new(0, 3)
	padding.Parent = label
	local stroke = label:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Thickness = 1.5
	stroke.Color = Color3.fromRGB(200, 146, 74)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	;(label.Parent :: BillboardGui).Enabled = false
	return label
end

local function lockTag(slot: Attachment): BillboardGui
	local label = billboard(slot, "LockTag", UDim2.fromOffset(40, 40), Vector3.new(0, 1.2, 0), 40)
	label.Text = "🔒"
	local gui = label.Parent :: BillboardGui
	gui.Enabled = false
	return gui
end

local function ownerSignLabel(sign: BasePart): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Name = "OwnerText"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0.2
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -16, 1, -8)
	label.Position = UDim2.fromOffset(8, 4)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(255, 236, 190)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = "🌿"
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Color3.fromRGB(60, 36, 20)
	stroke.Parent = label
	return label
end

local function contentKey(planted: { Economy.PlantItem }): string
	local parts = {}
	for _, item in planted do
		table.insert(parts, string.format("%s:%s:%s:%d", item.s, item.v or "", table.concat(item.x or {}, ","), item.t))
	end
	return table.concat(parts, "|")
end

local function lockSeconds(owner: Player?): number
	return stat(owner, "lock")
end

local function refreshGarden(garden: GardenState)
	local owner = garden.owner
	local data = owner and api.getData(owner)
	if garden.ownerSign then
		garden.ownerSign.Text = if owner then owner.DisplayName else "🌿"
	end
	local beds = bedsOf(garden, owner)
	local planted = if data then data.planted else {}

	-- Grzyby budujemy od nowa tylko po zmianie zawartości (mniej danych przez sieć)
	local key = if owner then contentKey(planted) else ""
	if garden.contentKey ~= key then
		garden.contentKey = key
		garden.visuals:ClearAllChildren()
		for index, item in planted do
			local slot = garden.slots[index]
			if slot then
				buildMushroom(garden.visuals, item, slot.WorldCFrame).Name = "Slot" .. index
			end
		end
	end

	local fertilizer = stat(owner, "fertilizer")
	for index, label in garden.slotLabels do
		local item = planted[index]
		local gui = label.Parent :: BillboardGui
		gui.Enabled = item ~= nil
		if item then
			-- Obwódka tabliczki w kolorze klasy grzyba
			local class = Economy.speciesClass(item.s)
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = rgb(class.color)
			end
			local icons = mutationIcons(item)
			label.Text = string.format(
				'%s💰 %s\n<font color="%s">+%s/min</font>',
				if icons ~= "" then icons .. " " else "",
				formatCoins(Economy.itemValue(item)),
				RATE_COLOR,
				formatRate(Economy.plantIncome(item, fertilizer))
			)
		end
		local locked = index > beds
		garden.lockTags[index].Enabled = locked and owner ~= nil
		local soil = garden.soils[index]
		if soil then
			soil.Color = if locked then SOIL_LOCKED else SOIL
		end
	end

	garden.model:SetAttribute("Count", #planted)
	garden.model:SetAttribute("Beds", beds)
	garden.stealPrompt.HoldDuration = lockSeconds(owner)
	if owner and data then
		garden.label.Text = string.format(
			'<b>%s</b>\n🍄 %d/%d   <font color="%s">+%s/min</font>',
			owner.DisplayName,
			#planted,
			beds,
			RATE_COLOR,
			formatRate(Economy.gardenIncome(planted, fertilizer))
		)
		if garden.potLabel then
			garden.potLabel.Text = "💰 " .. formatCoins(math.floor(data.pot))
		end
	else
		garden.label.Text = ""
		if garden.potLabel then
			garden.potLabel.Text = ""
		end
	end
end

-- Daje grzyb graczowi: wolna grządka, potem koszyk, a jak nigdzie nie ma miejsca, to monety.
-- Zwraca, gdzie trafił: "bed", "basket" albo "coins".
local function giveItem(player: Player, item: Economy.PlantItem): string
	local data = api.getData(player)
	if not data then
		return "lost"
	end
	local garden = gardenOf[player]
	if garden and #data.planted < bedsOf(garden, player) then
		item.t = os.time()
		table.insert(data.planted, item)
		return "bed"
	end
	if #data.basket < api.basketMax(player) then
		table.insert(data.basket, { s = item.s, v = item.v, x = item.x, d = item.d })
		return "basket"
	end
	data.coins += Economy.itemValue(item)
	return "coins"
end

-- ===== Niesienie łupu =====

local function carryVisuals(thief: Player, item: Economy.PlantItem): { Instance }
	local character = thief.Character
	local head = character and character:FindFirstChild("Head")
	if not (character and head and head:IsA("BasePart")) then
		return {}
	end
	-- Grzyb nad głową złodzieja, przyspawany do głowy
	local model = buildMushroom(character, item, head.CFrame * CFrame.new(0, 0.9, 0), 0.8)
	model.Name = "StolenMushroom"
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = head
			weld.Part1 = part
			weld.Parent = part
		end
	end
	-- Czerwona obwódka widoczna dla wszystkich, także zza drzew
	local highlight = Instance.new("Highlight")
	highlight.Name = "ThiefHighlight"
	highlight.FillColor = Color3.fromRGB(255, 60, 40)
	highlight.FillTransparency = 0.8
	highlight.OutlineColor = Color3.fromRGB(255, 80, 60)
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = character
	local label = billboard(head, "LootTag", UDim2.fromOffset(130, 32), Vector3.new(0, 4.6, 0), 200)
	local icons = mutationIcons(item)
	label.Text = string.format("🏃 %s💰 %s", if icons ~= "" then icons .. " " else "", formatCoins(Economy.itemValue(item)))
	label.TextColor3 = Color3.fromRGB(255, 140, 120)
	return { model, highlight, label.Parent :: Instance }
end

-- outcome: "delivered" (złodziej doniósł), "tagged" (właściciel dogonił), "dropped" (wyszedł z polany,
-- minął czas, rozłączył się)
local function endCarry(thief: Player, outcome: string)
	local carry = carries[thief]
	if not carry then
		return
	end
	carries[thief] = nil
	for _, instance in carry.visuals do
		instance:Destroy()
	end
	if thief.Parent then
		api.applyStats(thief)
	end
	local item = carry.item
	local owner = carry.owner
	local ownerHere = owner.Parent ~= nil and api.getData(owner) ~= nil
	local nameKey = speciesKey(item)
	local mutation = mutationOf(item)

	if outcome == "delivered" then
		local where = giveItem(thief, item)
		api.notify(thief, if where == "bed" then "MSG_LOOT_PLANTED" else "MSG_LOOT_DELIVERED", nil, nameKey, mutation)
		if api.onEvent then
			api.onEvent(thief, "steal", 1)
		end
		if ownerHere then
			api.notify(owner, "MSG_ROBBED", { thief.DisplayName }, nameKey, mutation)
		end
	elseif ownerHere then
		giveItem(owner, item)
		if outcome == "tagged" then
			api.notify(thief, "MSG_LOOT_TAGGED", { owner.DisplayName }, nameKey)
		elseif thief.Parent then
			api.notify(thief, "MSG_LOOT_DROPPED", nil, nameKey)
		end
		api.notify(owner, "MSG_LOOT_RECOVERED", nil, nameKey, mutation)
	elseif thief.Parent then
		-- Właściciel wyszedł z gry: łup przepada, a złodziej dostaje informację
		api.notify(thief, "MSG_LOOT_DROPPED", nil, nameKey)
	end

	for _, player in { thief, owner } do
		local garden = gardenOf[player]
		if garden then
			refreshGarden(garden)
		end
		if player.Parent then
			api.pushState(player)
		end
	end
end

local function stepCarries()
	local now = os.clock()
	for thief, carry in carries do
		local root = getRoot(thief)
		local garden = gardenOf[thief]
		if not root or thief.Parent == nil then
			endCarry(thief, "dropped")
			continue
		end
		local ownerRoot = getRoot(carry.owner)
		if ownerRoot and carry.owner.Parent and flatDistance(ownerRoot.Position, root.Position) <= Config.Garden.carry.tagRadius then
			endCarry(thief, "tagged")
		elseif garden and insideGarden(garden, root.Position) then
			endCarry(thief, "delivered")
		elseif Economy.zoneIndexAt(root.Position.Z) ~= 1 or now - carry.startedAt > Config.Garden.carry.timeout then
			endCarry(thief, "dropped")
		end
	end
end

-- ===== Akcje =====

local function onPlant(garden: GardenState, player: Player)
	if garden.owner ~= player then
		return
	end
	local data = api.getData(player)
	if not data then
		return
	end
	local beds = bedsOf(garden, player)
	local moves = Economy.planPlanting(data.basket, data.planted, beds)
	if #moves == 0 then
		api.notify(player, if #data.basket == 0 then "MSG_NOTHING_TO_PLANT" else "MSG_GARDEN_FULL")
		return
	end
	local now = os.time()
	local sold = 0
	local fromBasket = {}
	for _, move in moves do
		local item = data.basket[move.basket]
		local plant: Economy.PlantItem = { s = item.s, v = item.v, x = item.x, d = item.d, t = now }
		if move.replace then
			sold += Economy.itemValue(data.planted[move.replace])
			data.planted[move.replace] = plant
		else
			table.insert(data.planted, plant)
		end
		table.insert(fromBasket, move.basket)
	end
	-- Usuwamy z koszyka od końca, żeby indeksy się nie przesuwały
	table.sort(fromBasket, function(a, b)
		return a > b
	end)
	for _, index in fromBasket do
		table.remove(data.basket, index)
	end
	data.coins += sold
	if api.onEvent then
		api.onEvent(player, "plant", #moves)
	end
	if sold > 0 then
		api.notify(player, "MSG_PLANTED_SWAP", { #moves, sold })
	else
		api.notify(player, "MSG_PLANTED", { #moves })
	end
	refreshGarden(garden)
	api.pushState(player)
end

local function onCollect(garden: GardenState, player: Player)
	if garden.owner ~= player then
		return
	end
	local data = api.getData(player)
	if not data then
		return
	end
	local amount = math.floor(data.pot)
	if amount < 1 then
		api.notify(player, "MSG_POT_EMPTY")
		return
	end
	data.pot -= amount
	data.coins += amount
	if api.onEvent then
		api.onEvent(player, "collect", 1)
	end
	api.notify(player, "MSG_COLLECTED", { amount })
	refreshGarden(garden)
	api.pushState(player)
end

local function onSteal(garden: GardenState, thief: Player)
	local owner = garden.owner
	if not owner or owner == thief or carries[thief] then
		return
	end
	local ownerData = api.getData(owner)
	if not ownerData or #ownerData.planted == 0 then
		return
	end
	-- Prompt nie pilnuje czasu trzymania po stronie serwera, więc sprawdzamy sami
	local began = holdStarted[thief]
	holdStarted[thief] = nil
	if not began or os.clock() - began < lockSeconds(owner) - 0.35 then
		return
	end
	if distanceTo(thief, garden.hub) > STEAL_RANGE then
		return
	end
	if not gardenOf[thief] then
		api.notify(thief, "MSG_NO_RACK")
		return
	end
	local now = os.clock()
	if now < garden.protectedUntil then
		api.notify(thief, "MSG_RACK_PROTECTED")
		return
	end
	if now - (thiefLast[thief] or 0) < Config.Garden.thiefCooldown then
		return
	end
	if distanceTo(owner, garden.hub) <= Config.Garden.guardRadius then
		api.notify(thief, "MSG_OWNER_GUARDING")
		return
	end

	local index = Economy.mostValuableIndex(ownerData.planted)
	if not index then
		return
	end
	local item = table.remove(ownerData.planted, index) :: Economy.PlantItem
	garden.protectedUntil = now + Config.Garden.stealCooldown
	thiefLast[thief] = now
	carries[thief] = { item = item, owner = owner, startedAt = now, visuals = carryVisuals(thief, item) }
	api.applyStats(thief)

	local nameKey = speciesKey(item)
	api.notify(thief, "MSG_STOLE", nil, nameKey, mutationOf(item))
	api.notify(owner, "MSG_THIEF_RUNNING", { thief.DisplayName }, nameKey, mutationOf(item))
	refreshGarden(garden)
	api.pushState(owner)
end

-- ===== Przydział ogródków =====

function GardenService.assign(player: Player)
	if gardenOf[player] then
		return
	end
	local data = api.getData(player)
	for _, garden in gardens do
		if not garden.owner then
			garden.owner = player
			gardenOf[player] = garden
			garden.model:SetAttribute("OwnerUserId", player.UserId)
			garden.model:SetAttribute("OwnerName", player.DisplayName)
			if data then
				-- Więcej posadzonych niż odblokowanych grządek (np. po przeniesieniu ze starej suszarni):
				-- nadmiar trafia do skrzyni jako monety
				local beds = bedsOf(garden, player)
				while #data.planted > beds do
					local weakest = Economy.weakestIndex(data.planted) :: number
					data.pot += Economy.itemValue(table.remove(data.planted, weakest) :: Economy.PlantItem)
				end
				-- Dochód za czas offline
				local now = os.time()
				if data.incomeAt > 0 then
					local earned = Economy.offlineIncome(data.planted, stat(player, "fertilizer"), now - data.incomeAt)
					data.pot += earned
					if earned >= 1 then
						api.notify(player, "MSG_OFFLINE_INCOME", { math.floor(earned) })
					end
				end
				data.incomeAt = now
			end
			refreshGarden(garden)
			return
		end
	end
	api.notify(player, "MSG_NO_RACK")
end

function GardenService.release(player: Player)
	endCarry(player, "dropped")
	-- Złodzieje, którzy niosą grzyb tego gracza, dostają go na własność dopiero po doniesieniu
	local garden = gardenOf[player]
	gardenOf[player] = nil
	thiefLast[player] = nil
	holdStarted[player] = nil
	if garden then
		garden.owner = nil
		garden.model:SetAttribute("OwnerUserId", 0)
		garden.model:SetAttribute("OwnerName", "")
		refreshGarden(garden)
	end
end

function GardenService.refresh(player: Player)
	local garden = gardenOf[player]
	if garden then
		refreshGarden(garden)
	end
end

-- Mnożnik prędkości chodu (1 = normalnie, mniej = niesie łup)
function GardenService.speedFactor(player: Player): number
	local carry = carries[player]
	return if carry then Economy.carrySpeed(carry.item) else 1
end

function GardenService.isCarrying(player: Player): boolean
	return carries[player] ~= nil
end

-- Produkt za Robuxy: od razu dochód z kilkudziesięciu minut. false = nic nie rośnie.
function GardenService.harvestNow(player: Player): boolean
	local data = api.getData(player)
	if not data or #data.planted == 0 then
		return false
	end
	local amount = Economy.gardenIncome(data.planted, stat(player, "fertilizer")) * Config.Garden.harvestMinutes
	data.pot += amount
	api.notify(player, "MSG_HARVEST", { math.floor(amount) })
	GardenService.refresh(player)
	return true
end

-- ===== Start =====

local function makePrompt(part: BasePart, name: string, key: string, keyCode: Enum.KeyCode, order: number): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = key -- klient podmienia na tekst w języku gracza
	prompt.KeyboardKeyCode = keyCode
	prompt.GamepadKeyCode = if keyCode == Enum.KeyCode.F then Enum.KeyCode.ButtonY else Enum.KeyCode.ButtonX
	prompt.MaxActivationDistance = Config.Garden.promptDistance
	prompt.RequiresLineOfSight = false
	prompt.UIOffset = Vector2.new(0, order * 72)
	prompt.Enabled = false -- klient włącza lokalnie właściwe przyciski
	prompt:SetAttribute("TextKey", key)
	prompt.Parent = part
	return prompt
end

function GardenService.start(gardenInfos: { { id: number, model: Model } }, serviceApi: Api)
	api = serviceApi
	for _, info in gardenInfos do
		local model = info.model
		local hub = model.PrimaryPart
		if not hub then
			continue
		end
		local slots: { Attachment } = {}
		local soils: { BasePart } = {}
		local slotLabels: { TextLabel } = {}
		local lockTags: { BillboardGui } = {}
		for i = 1, Config.Garden.maxBeds do
			local slot = model:FindFirstChild("Slot" .. i, true)
			if slot and slot:IsA("Attachment") then
				table.insert(slots, slot)
				local soil = slot.Parent
				if soil and soil:IsA("BasePart") then
					table.insert(soils, soil)
				end
				table.insert(slotLabels, slotLabel(slot))
				table.insert(lockTags, lockTag(slot))
			end
		end
		local visuals = Instance.new("Folder")
		visuals.Name = "Planted"
		visuals.Parent = model
		local signPart = model:FindFirstChild("OwnerSign", true)
		local chestPart = model:FindFirstChild("Chest", true)
		local chest = if chestPart and chestPart:IsA("BasePart") then chestPart else nil

		local plant = makePrompt(hub, "Plant", "GARDEN_PLANT", Enum.KeyCode.E, 0)
		local steal = makePrompt(hub, "Steal", "GARDEN_STEAL", Enum.KeyCode.E, 0)
		steal.HoldDuration = lockSeconds(nil)
		steal:SetAttribute("Thief", true)
		plant:SetAttribute("Owner", true)
		local collect: ProximityPrompt? = nil
		if chest then
			collect = makePrompt(chest, "Collect", "GARDEN_COLLECT", Enum.KeyCode.F, 0)
			;(collect :: ProximityPrompt):SetAttribute("Owner", true)
		end

		local garden: GardenState = {
			id = info.id,
			model = model,
			hub = hub,
			chest = chest,
			soils = soils,
			slots = slots,
			lockTags = lockTags,
			slotLabels = slotLabels,
			visuals = visuals,
			-- Podsumowanie (imię, grządki, dochód) wisi nad furtką, żeby nie zasłaniało tabliczek grządek
			label = billboard(
				if signPart and signPart:IsA("BasePart") then signPart else hub,
				"OwnerTag",
				UDim2.fromOffset(200, 54),
				Vector3.new(0, 3, 0),
				80
			),
			potLabel = if chest then billboard(chest, "PotTag", UDim2.fromOffset(140, 36), Vector3.new(0, 3.4, 0), 50) else nil,
			ownerSign = if signPart and signPart:IsA("BasePart") then ownerSignLabel(signPart) else nil,
			owner = nil,
			protectedUntil = 0,
			stealPrompt = steal,
			contentKey = nil,
		}
		model:SetAttribute("OwnerUserId", 0)
		model:SetAttribute("Count", 0)
		-- Po tym tagu klient (GardenPrompts) znajduje ogródki
		CollectionService:AddTag(model, "GardenPlot")
		table.insert(gardens, garden)
		refreshGarden(garden)

		plant.Triggered:Connect(function(player)
			onPlant(garden, player)
		end)
		if collect then
			collect.Triggered:Connect(function(player)
				onCollect(garden, player)
			end)
		end
		steal.PromptButtonHoldBegan:Connect(function(player)
			holdStarted[player] = os.clock()
			-- Właściciel dostaje ostrzeżenie od razu, żeby mógł przybiec i przegonić złodzieja
			local owner = garden.owner
			local ownerData = owner and api.getData(owner)
			if owner and owner ~= player and ownerData and #ownerData.planted > 0 then
				api.notify(owner, "MSG_RACK_ALERT", { player.DisplayName })
			end
		end)
		steal.Triggered:Connect(function(player)
			onSteal(garden, player)
		end)
	end

	Players.PlayerRemoving:Connect(GardenService.release)

	-- Złodziej zginął (np. reset postaci): łup wraca
	Players.PlayerAdded:Connect(function(player)
		player.CharacterRemoving:Connect(function()
			endCarry(player, "dropped")
		end)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterRemoving:Connect(function()
			endCarry(player, "dropped")
		end)
	end

	RunService.Heartbeat:Connect(stepCarries)

	-- Dochód z grządek co sekundę, wygląd co kilka sekund
	task.spawn(function()
		local sinceVisual = 0
		while true do
			task.wait(INCOME_TICK)
			local now = os.time()
			sinceVisual += INCOME_TICK
			for _, garden in gardens do
				local owner = garden.owner
				local data = owner and api.getData(owner)
				if owner and data then
					data.pot += Economy.gardenIncome(data.planted, stat(owner, "fertilizer")) * INCOME_TICK / 60
					data.incomeAt = now
				end
				if sinceVisual >= VISUAL_REFRESH then
					refreshGarden(garden)
				end
			end
			if sinceVisual >= VISUAL_REFRESH then
				sinceVisual = 0
			end
		end
	end)
end

return GardenService
