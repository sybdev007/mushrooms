--!strict
-- Suszarnie przed chatką. Każdy gracz na serwerze dostaje jedną.
-- Właściciel wiesza grzyby z koszyka, a one z czasem schną i drożeją (także gdy gracz jest offline).
-- Inni gracze mogą podkraść najcenniejszy grzyb: trzymają przycisk tyle sekund, ile daje kłódka,
-- i nie mogą kraść, gdy właściciel stoi przy swojej suszarni.
--
-- Przyciski to ProximityPrompt (działają na telefonie, klawiaturze i padzie).
-- Serwer tworzy wszystkie, a klient (src/client/RackPrompts.luau) pokazuje tylko te,
-- które dotyczą danego gracza. Każdą akcję i tak sprawdza serwer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Economy = require(ReplicatedStorage.Shared.Economy)

type Data = {
	coins: number,
	basket: { Economy.BasketItem },
	drying: { Economy.DryingItem },
	upgrades: { [string]: number },
}

export type Api = {
	getData: (Player) -> Data?,
	basketMax: (Player) -> number,
	notify: (Player, string, { any }?, string?) -> (),
	pushState: (Player) -> (),
}

type RackState = {
	id: number,
	model: Model,
	hub: BasePart,
	slots: { Attachment },
	pads: { BasePart? },
	slotLabels: { TextLabel },
	visuals: Folder,
	label: TextLabel,
	owner: Player?,
	protectedUntil: number,
	stealPrompt: ProximityPrompt,
}

local DryingService = {}

local VISUAL_REFRESH = 4
local GUARD_RADIUS = 10 -- właściciel bliżej swojej suszarni = nie da się z niej kraść
local STEAL_RANGE = 12 -- serwer jest łagodniejszy niż prompt przez opóźnienie sieci
local DRY_COLOR = Color3.fromRGB(92, 60, 36)
local PAD_EMPTY = Color3.fromRGB(96, 70, 50)
local PAD_FULL = Color3.fromRGB(88, 128, 66)
local PAD_GOLD = Color3.fromRGB(214, 170, 60)
local RATE_COLOR = "#A6F06A"
local DRY_DONE_COLOR = "#FFD75A"

local api: Api
local racks: { RackState } = {}
local rackOf: { [Player]: RackState } = {}
local thiefLast: { [Player]: number } = {}
local holdStarted: { [Player]: number } = {}

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function distanceTo(player: Player, part: BasePart): number
	local root = getRoot(player)
	if not root then
		return math.huge
	end
	local offset = root.Position - part.Position
	return Vector3.new(offset.X, 0, offset.Z).Magnitude
end

local function capColor(speciesId: string, golden: boolean): Color3
	if golden then
		return Color3.fromRGB(255, 205, 50)
	end
	local species = Economy.getSpecies(speciesId)
	local cap = species and species.cap or { 160, 120, 80 }
	return Color3.fromRGB(cap[1], cap[2], cap[3])
end

local function lockSeconds(owner: Player?): number
	local data = owner and api.getData(owner)
	local level = if data then data.upgrades.lock or 0 else 0
	return Economy.upgradeStat("lock", level)
end

-- ===== Wygląd suszarni =====

local function makePrompt(hub: BasePart, name: string, key: string, keyCode: Enum.KeyCode, order: number): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = key -- klient podmienia na tekst w języku gracza
	prompt.KeyboardKeyCode = keyCode
	prompt.GamepadKeyCode = if keyCode == Enum.KeyCode.F then Enum.KeyCode.ButtonY else Enum.KeyCode.ButtonX
	prompt.MaxActivationDistance = Config.Drying.promptDistance
	prompt.RequiresLineOfSight = false
	prompt.UIOffset = Vector2.new(0, order * 72)
	prompt.Enabled = false -- klient włącza lokalnie właściwe przyciski
	prompt:SetAttribute("TextKey", key)
	prompt.Parent = hub
	return prompt
end

local function buildLabel(hub: BasePart): TextLabel
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "OwnerTag"
	billboard.Size = UDim2.fromOffset(180, 54)
	billboard.StudsOffset = Vector3.new(0, 7, 0)
	billboard.MaxDistance = 70
	billboard.LightInfluence = 0
	billboard.Parent = hub
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(255, 236, 190)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.RichText = true
	label.Text = ""
	label.Parent = billboard
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(50, 30, 16)
	stroke.Parent = label
	return label
end

-- Tabliczka nad stanowiskiem: ile grzyb jest teraz wart i ile zyskuje na minutę.
-- To ona zachęca innych do kradzieży, więc widać ją z daleka.
local function buildSlotLabel(slot: Attachment): TextLabel
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "SlotTag"
	billboard.Size = UDim2.fromOffset(96, 42)
	billboard.StudsOffset = Vector3.new(0, 1.9, 0)
	billboard.MaxDistance = 45
	billboard.LightInfluence = 0
	billboard.Enabled = false
	billboard.Parent = slot
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(40, 28, 20)
	label.BackgroundTransparency = 0.25
	label.TextColor3 = Color3.fromRGB(255, 226, 140)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.RichText = true
	label.Text = ""
	label.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 3)
	padding.PaddingBottom = UDim.new(0, 3)
	padding.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Color = Color3.fromRGB(200, 146, 74)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = label
	return label
end

local function slotText(item: Economy.DryingItem, now: number): string
	local value = Economy.dryingValue(item, now)
	local rate = Economy.dryRatePerMinute(item, now)
	if rate > 0 then
		-- Jedno miejsce po przecinku tylko dla małych stawek, żeby nie było „+0/min”
		local rateText = if rate < 10 then string.format("%.1f", rate) else string.format("%d", math.floor(rate + 0.5))
		return string.format('💰 %d\n<font color="%s">+%s/min</font>', value, RATE_COLOR, rateText)
	end
	return string.format('💰 %d\n<font color="%s">✓ MAX</font>', value, DRY_DONE_COLOR)
end

local STEM_COLOR = Color3.fromRGB(226, 214, 190)

local function newPart(size: Vector3, cf: CFrame, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
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

-- Ustawia wygląd jednego suszącego się grzyba: im suchszy, tym ciemniejszy i mniejszy
local function styleMushroom(group: Model, item: Economy.DryingItem, slot: Attachment, now: number)
	local progress = Economy.dryProgress(now - item.t)
	local scale = 1 - 0.25 * progress
	local base = slot.WorldCFrame
	local cap = group:FindFirstChild("Cap") :: BasePart
	local stem = group:FindFirstChild("Stem") :: BasePart
	cap.Size = Vector3.new(1.3, 0.8, 1.3) * scale
	-- Kapeluszem w dół, jak grzyb suszony na nitce
	cap.CFrame = base * CFrame.Angles(math.rad(180), 0, 0)
	cap.Color = capColor(item.s, item.g):Lerp(DRY_COLOR, if item.g then progress * 0.3 else progress * 0.65)
	stem.Size = Vector3.new(0.35, 0.8, 0.35) * scale
	stem.CFrame = base * CFrame.new(0, -0.55 * scale, 0)
	stem.Color = STEM_COLOR:Lerp(DRY_COLOR, progress * 0.5)
end

local function buildMushroom(parent: Instance, item: Economy.DryingItem, slot: Attachment): Model
	local group = Instance.new("Model")
	group.Name = "DryingMushroom"
	newPart(Vector3.new(0.05, 0.5, 0.05), slot.WorldCFrame * CFrame.new(0, 0.25, 0), Color3.fromRGB(200, 190, 170), group).Name = "Thread"
	local cap = newPart(Vector3.one, slot.WorldCFrame, Color3.new(), group)
	cap.Name = "Cap"
	if item.g then
		cap.Material = Enum.Material.Neon
	end
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = cap
	newPart(Vector3.one, slot.WorldCFrame, STEM_COLOR, group).Name = "Stem"
	group.Parent = parent
	return group
end

-- Klucz zawartości suszarni: gdy się nie zmienił, tylko przemalowujemy istniejące części
-- zamiast budować je od nowa (mniej danych przez sieć, ważne na telefonach)
local function contentKey(drying: { Economy.DryingItem }): string
	local parts = {}
	for _, item in drying do
		table.insert(parts, string.format("%s%s%d", item.s, if item.g then "g" else "", item.t))
	end
	return table.concat(parts, "|")
end

local rackKeys: { [number]: string } = {}

local function refreshRack(rack: RackState)
	local owner = rack.owner
	local data = owner and api.getData(owner)
	if not owner or not data then
		rack.visuals:ClearAllChildren()
		rackKeys[rack.id] = nil
		rack.label.Text = ""
		rack.model:SetAttribute("Count", 0)
		for index, label in rack.slotLabels do
			(label.Parent :: BillboardGui).Enabled = false
			local pad = rack.pads[index]
			if pad then
				pad.Color = PAD_EMPTY
			end
		end
		return
	end
	local now = os.time()
	local key = contentKey(data.drying)
	if rackKeys[rack.id] ~= key then
		rackKeys[rack.id] = key
		rack.visuals:ClearAllChildren()
		for index, item in data.drying do
			local slot = rack.slots[index]
			if slot then
				local group = buildMushroom(rack.visuals, item, slot)
				group.Name = "Slot" .. index
			end
		end
	end
	for index, item in data.drying do
		local group = rack.visuals:FindFirstChild("Slot" .. index)
		local slot = rack.slots[index]
		if group and group:IsA("Model") and slot then
			styleMushroom(group, item, slot, now)
		end
	end
	-- Tabliczki i kolor płytek: zajęte stanowiska świecą zielenią, złote grzyby złotem
	for index, label in rack.slotLabels do
		local item = data.drying[index]
		local billboard = label.Parent :: BillboardGui
		billboard.Enabled = item ~= nil
		if item then
			label.Text = slotText(item, now)
		end
		local pad = rack.pads[index]
		if pad then
			pad.Color = if not item then PAD_EMPTY elseif item.g then PAD_GOLD else PAD_FULL
		end
	end
	local count = #data.drying
	rack.model:SetAttribute("Count", count)
	rack.stealPrompt.HoldDuration = lockSeconds(owner)
	local value = Economy.rackValue(data.drying, now)
	rack.label.Text = string.format(
		"<b>%s</b>\n🍄 %d/%d   💰 %d",
		owner.DisplayName,
		count,
		Config.Drying.slots,
		value
	)
end

-- ===== Przydział suszarni =====

function DryingService.assign(player: Player)
	if rackOf[player] then
		return
	end
	for _, rack in racks do
		if not rack.owner then
			rack.owner = player
			rackOf[player] = rack
			rack.model:SetAttribute("OwnerUserId", player.UserId)
			rack.model:SetAttribute("OwnerName", player.DisplayName)
			refreshRack(rack)
			return
		end
	end
	api.notify(player, "MSG_NO_RACK")
end

function DryingService.release(player: Player)
	local rack = rackOf[player]
	rackOf[player] = nil
	thiefLast[player] = nil
	holdStarted[player] = nil
	if rack then
		rack.owner = nil
		rack.model:SetAttribute("OwnerUserId", 0)
		rack.model:SetAttribute("OwnerName", "")
		refreshRack(rack)
	end
end

function DryingService.refresh(player: Player)
	local rack = rackOf[player]
	if rack then
		refreshRack(rack)
	end
end

-- ===== Akcje =====

local function onHang(rack: RackState, player: Player)
	if rack.owner ~= player then
		return
	end
	local data = api.getData(player)
	if not data then
		return
	end
	local free = Config.Drying.slots - #data.drying
	if free <= 0 then
		api.notify(player, "MSG_RACK_FULL")
		return
	end
	local chosen = Economy.pickForDrying(data.basket, free)
	if #chosen == 0 then
		api.notify(player, "MSG_NOTHING_TO_HANG")
		return
	end
	local now = os.time()
	-- Usuwamy od końca, żeby indeksy się nie przesuwały
	table.sort(chosen, function(a, b)
		return a > b
	end)
	for _, index in chosen do
		local item = table.remove(data.basket, index)
		if item then
			table.insert(data.drying, { s = item.s, g = item.g, t = now })
		end
	end
	api.notify(player, "MSG_HUNG", { #chosen })
	refreshRack(rack)
	api.pushState(player)
end

local function onCollect(rack: RackState, player: Player)
	if rack.owner ~= player then
		return
	end
	local data = api.getData(player)
	if not data or #data.drying == 0 then
		return
	end
	local value = Economy.rackValue(data.drying, os.time())
	data.coins += value
	table.clear(data.drying)
	api.notify(player, "MSG_SOLD", { value })
	refreshRack(rack)
	api.pushState(player)
end

local function onSteal(rack: RackState, thief: Player)
	local owner = rack.owner
	if not owner or owner == thief then
		return
	end
	local ownerData = api.getData(owner)
	local thiefData = api.getData(thief)
	if not ownerData or not thiefData or #ownerData.drying == 0 then
		return
	end
	-- Prompt nie pilnuje czasu trzymania po stronie serwera, więc sprawdzamy sami
	local began = holdStarted[thief]
	holdStarted[thief] = nil
	local hold = lockSeconds(owner)
	if not began or os.clock() - began < hold - 0.35 then
		return
	end
	if distanceTo(thief, rack.hub) > STEAL_RANGE then
		return
	end
	local now = os.clock()
	if now < rack.protectedUntil then
		api.notify(thief, "MSG_RACK_PROTECTED")
		return
	end
	if now - (thiefLast[thief] or 0) < Config.Drying.thiefCooldown then
		return
	end
	if distanceTo(owner, rack.hub) <= GUARD_RADIUS then
		api.notify(thief, "MSG_OWNER_GUARDING")
		return
	end
	if #thiefData.basket >= api.basketMax(thief) then
		api.notify(thief, "MSG_BASKET_FULL")
		return
	end

	local index = Economy.mostValuableIndex(ownerData.drying, os.time())
	if not index then
		return
	end
	local item = table.remove(ownerData.drying, index)
	if not item then
		return
	end
	table.insert(thiefData.basket, { s = item.s, g = item.g, d = Economy.dryMultiplier(os.time() - item.t) })
	rack.protectedUntil = now + Config.Drying.stealCooldown
	thiefLast[thief] = now

	local species = Economy.getSpecies(item.s)
	local nameKey = species and species.key or nil
	api.notify(thief, "MSG_STOLE", nil, nameKey)
	api.notify(owner, "MSG_ROBBED", { thief.DisplayName }, nameKey)
	refreshRack(rack)
	api.pushState(thief)
	api.pushState(owner)
end

-- ===== Start =====

function DryingService.start(rackInfos: { { id: number, model: Model } }, serviceApi: Api)
	api = serviceApi
	for _, info in rackInfos do
		local model = info.model
		local hub = model.PrimaryPart
		if not hub then
			continue
		end
		local slots: { Attachment } = {}
		local pads: { BasePart? } = {}
		local slotLabels: { TextLabel } = {}
		for i = 1, Config.Drying.slots do
			local slot = model:FindFirstChild("Slot" .. i, true)
			if slot and slot:IsA("Attachment") then
				table.insert(slots, slot)
				-- Płytka stanowiska to część, w której siedzi Attachment (własne modele mogą jej nie mieć)
				local pad = slot.Parent
				pads[#slots] = if pad and pad:IsA("BasePart") and string.find(pad.Name, "^Pad") then pad else nil
				table.insert(slotLabels, buildSlotLabel(slot))
			end
		end
		local visuals = Instance.new("Folder")
		visuals.Name = "Drying"
		visuals.Parent = model

		local hang = makePrompt(hub, "Hang", "RACK_HANG", Enum.KeyCode.E, 0)
		local collect = makePrompt(hub, "Collect", "RACK_COLLECT", Enum.KeyCode.F, 1)
		local steal = makePrompt(hub, "Steal", "RACK_STEAL", Enum.KeyCode.E, 0)
		steal.HoldDuration = lockSeconds(nil)
		steal:SetAttribute("Thief", true)
		hang:SetAttribute("Owner", true)
		collect:SetAttribute("Owner", true)

		local rack: RackState = {
			id = info.id,
			model = model,
			hub = hub,
			slots = slots,
			pads = pads,
			slotLabels = slotLabels,
			visuals = visuals,
			label = buildLabel(hub),
			owner = nil,
			protectedUntil = 0,
			stealPrompt = steal,
		}
		model:SetAttribute("OwnerUserId", 0)
		model:SetAttribute("Count", 0)
		table.insert(racks, rack)

		hang.Triggered:Connect(function(player)
			onHang(rack, player)
		end)
		collect.Triggered:Connect(function(player)
			onCollect(rack, player)
		end)
		steal.PromptButtonHoldBegan:Connect(function(player)
			holdStarted[player] = os.clock()
			-- Właściciel dostaje ostrzeżenie od razu, żeby mógł przybiec i przegonić złodzieja
			local owner = rack.owner
			local ownerData = owner and api.getData(owner)
			if owner and owner ~= player and ownerData and #ownerData.drying > 0 then
				api.notify(owner, "MSG_RACK_ALERT", { player.DisplayName })
			end
		end)
		steal.Triggered:Connect(function(player)
			onSteal(rack, player)
		end)
	end

	Players.PlayerRemoving:Connect(DryingService.release)

	-- Grzyby na sznurkach powoli ciemnieją, a wartość na tabliczce rośnie
	task.spawn(function()
		while true do
			task.wait(VISUAL_REFRESH)
			for _, rack in racks do
				if rack.owner then
					refreshRack(rack)
				end
			end
		end
	end)
end

return DryingService
