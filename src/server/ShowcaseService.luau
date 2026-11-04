--!strict
-- Gablota w ogródku: regał pod bocznym płotem każdego ogródka (lewy, patrząc od furtki) z trzema półkami
-- (od dołu las, jaskinia, bagna) po Config.Showcase.perSeries miejsc. Właściciel otwiera okno przyciskiem
-- przy regale (ShowcasePanel): kupuje kolejne miejsca za monety i wystawia kopie grzybów z Grzybopedii albo
-- trofea ze Znaleziska Nocy. Wystawione grzyby rysuje każdy klient (znaczniki "ShowcaseMushroom",
-- DisplayMushrooms), podpisy dokłada ShowcaseView. Zasady i ceny: Shared/Showcase.
-- Regał stawiamy tu przy starcie serwera (a nie w World/Garden), żeby pojawił się też na mapie zapisanej
-- w miejscu (MapBuilder czyta wtedy gotowy folder Map i nie buduje ogródków od nowa).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Showcase = require(ReplicatedStorage.Shared.Showcase)
local Ledger = require(script.Parent.Ledger)
local Palette = require(script.Parent.World.Palette)

export type Api = {
	getData: (Player) -> any?,
	notify: (Player, string, { any }?, string?, any?) -> (),
	pushState: (Player) -> (),
	rootOf: (Player) -> BasePart?,
}

local ShowcaseService = {}

-- Regał (lokalnie: środek na ziemi, -Z = przód w stronę dziedzińca, +X = strona furtki)
-- Półki zaczynają się nad zamkniętą szafką (3 studs): niżej zasłaniały je grzyby z grządek obok
local LENGTH = 14
local DEPTH = 1.8
local HEIGHT = 10.4
local SHELF_Y = { 3, 5.4, 7.8 } -- wierzch półek od dołu: las, jaskinia, bagna
local SLOT_STEP = (LENGTH - 1.4) / Config.Showcase.perSeries
local FROM_FENCE = 1.4 -- środek regału tyle od bocznego płotu
local ALONG = 3.5 -- środek regału tyle za środkiem ogródka (w stronę tylnego płotu)
local PLATE_OWNED = Color3.fromRGB(196, 160, 112)
local PLATE_LOCKED = Color3.fromRGB(58, 44, 36)
local ACTION_GAP = 0.2

local api: Api
local cabinets: { [Model]: Model } = {} -- ogródek -> regał
local lastAction: { [Player]: number } = {}

local function make(parent: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = false
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

local function decor(p: Part): Part
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

local function seriesColor(series: number): Color3
	local c = Config.Showcase.series[series].color
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- Środek miejsca na półce (lokalnie w regale); miejsce 1 z lewej patrząc z dziedzińca (strona furtki)
local function slotLocal(slot: number): CFrame
	local series, k = Showcase.slotOf(slot)
	local x = (LENGTH / 2 - 0.7 - SLOT_STEP / 2) - (k - 1) * SLOT_STEP
	return CFrame.new(x, SHELF_Y[series], -0.1)
end

local function buildCabinet(garden: Model): Model?
	local grass = garden:FindFirstChild("GardenGrass")
	if not (grass and grass:IsA("BasePart")) then
		return nil
	end
	local center = grass.CFrame * CFrame.new(0, 0.02, 0)
	local halfW = grass.Size.X / 2
	-- Obrót o 90°: przód regału (-Z) patrzy na środek ogródka (-X ogródka)
	local cf = center * CFrame.new(halfW - FROM_FENCE, 0, ALONG) * CFrame.Angles(0, math.rad(90), 0)
	local m = Instance.new("Model")
	m.Name = "Showcase"
	local wood, woodDark = Palette.plank, Palette.plankDark
	make(m, { Name = "Plinth", Size = Vector3.new(LENGTH, SHELF_Y[1], DEPTH), CFrame = cf * CFrame.new(0, SHELF_Y[1] / 2, 0), Color = woodDark })
	-- Drzwiczki szafki pod półkami (sama ozdoba)
	for i = 1, 4 do
		local x = -LENGTH / 2 + (i - 0.5) * LENGTH / 4
		decor(make(m, { Name = "Door", Size = Vector3.new(LENGTH / 4 - 0.5, SHELF_Y[1] - 0.8, 0.1), CFrame = cf * CFrame.new(x, SHELF_Y[1] / 2, -DEPTH / 2 - 0.05), Color = wood }))
		decor(make(m, { Name = "Knob", Shape = Enum.PartType.Ball, Size = Vector3.new(0.25, 0.25, 0.25), CFrame = cf * CFrame.new(x + (if i % 2 == 1 then 1 else -1), SHELF_Y[1] / 2, -DEPTH / 2 - 0.15), Color = Color3.fromRGB(230, 180, 60) }))
	end
	make(m, { Name = "Back", Size = Vector3.new(LENGTH, HEIGHT, 0.3), CFrame = cf * CFrame.new(0, HEIGHT / 2, DEPTH / 2 - 0.15), Color = Palette.plankDark:Lerp(Color3.new(0, 0, 0), 0.25) })
	for _, side in { -1, 1 } do
		make(m, { Name = "Post", Size = Vector3.new(0.5, HEIGHT, DEPTH), CFrame = cf * CFrame.new(side * (LENGTH / 2 - 0.25), HEIGHT / 2, 0), Color = wood })
	end
	make(m, { Name = "Crown", Size = Vector3.new(LENGTH + 0.6, 0.5, DEPTH + 0.4), CFrame = cf * CFrame.new(0, HEIGHT + 0.25, 0), Color = woodDark })
	for series, y in SHELF_Y do
		if series > 1 then
			make(m, { Name = "Shelf", Size = Vector3.new(LENGTH - 1, 0.3, DEPTH - 0.3), CFrame = cf * CFrame.new(0, y - 0.15, -0.15), Color = wood })
		end
		-- Świecąca listwa na krawędzi półki w kolorze serii i ciepłe światło nad nią
		decor(make(m, {
			Name = "Edge",
			Size = Vector3.new(LENGTH - 1, 0.12, 0.12),
			CFrame = cf * CFrame.new(0, y - 0.2, -DEPTH / 2 + 0.05),
			Color = seriesColor(series),
			Material = Enum.Material.Neon,
			Transparency = 0.35,
		}))
		local lamp = decor(make(m, {
			Name = "Lamp",
			Size = Vector3.new(0.4, 0.2, 0.4),
			CFrame = cf * CFrame.new(0, y + 2.1, DEPTH / 2 - 0.45),
			Color = Palette.lanternGlow,
			Material = Enum.Material.Neon,
			Transparency = 0.2,
		}))
		local light = Instance.new("PointLight")
		light.Color = Palette.lanternGlow
		-- Słabe: wystawione grzyby świecą same, a mocniejsze lampy prześwietlały regał na biało
		light.Range = 6
		light.Brightness = 0.25
		light.Shadows = false
		light.Parent = lamp
	end
	for slot = 1, Showcase.TOTAL do
		local plate = decor(make(m, {
			Name = "Plate" .. slot,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.1, 1.6, 1.6),
			CFrame = cf * slotLocal(slot) * CFrame.new(0, 0.05, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = PLATE_LOCKED,
		}))
		plate.Material = Enum.Material.Wood
	end
	-- Przycisk właściciela (GardenPrompts włącza go tylko właścicielowi i tłumaczy napis)
	local anchor = decor(make(m, { Name = "PromptAnchor", Size = Vector3.new(1, 1, 1), CFrame = cf * CFrame.new(0, 3, -DEPTH / 2 - 0.6), Transparency = 1 }))
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShowcasePrompt"
	prompt.ActionText = "SHOWCASE_PROMPT"
	prompt:SetAttribute("TextKey", "SHOWCASE_PROMPT")
	prompt:SetAttribute("Owner", true)
	prompt.Enabled = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Config.Showcase.promptDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor
	m:SetAttribute("Origin", cf)
	m.Parent = garden
	return m
end

local function ownerOf(garden: Model): Player?
	local ownerId = garden:GetAttribute("OwnerUserId")
	return if typeof(ownerId) == "number" and ownerId ~= 0 then Players:GetPlayerByUserId(ownerId) else nil
end

local function gardenOf(player: Player): Model?
	for garden in cabinets do
		if garden:GetAttribute("OwnerUserId") == player.UserId then
			return garden
		end
	end
	return nil
end

-- Regał od nowa według zapisu właściciela (pusty ogródek = puste, ciemne miejsca)
local function refresh(garden: Model, freshSlot: number?)
	local cabinet = cabinets[garden]
	if not cabinet then
		return
	end
	local old = cabinet:FindFirstChild("Exhibits")
	if old then
		old:Destroy()
	end
	local owner = ownerOf(garden)
	local data = if owner then api.getData(owner) else nil
	local save: Showcase.Save? = if data then data.showcase else nil
	local origin = cabinet:GetAttribute("Origin")
	if typeof(origin) ~= "CFrame" then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Exhibits"
	for slot = 1, Showcase.TOTAL do
		local plate = cabinet:FindFirstChild("Plate" .. slot)
		local owned = save ~= nil and slot <= save.n
		if plate and plate:IsA("BasePart") then
			plate.Color = if owned then PLATE_OWNED else PLATE_LOCKED
		end
		local exhibit = if save then save.items[tostring(slot)] else nil
		if exhibit and owned then
			local ground = (origin * slotLocal(slot)).Position + Vector3.new(0, 0.1, 0)
			local marker = Instance.new("Model")
			marker.Name = "Exhibit" .. slot
			local root = make(marker, {
				Name = "Root",
				Size = Vector3.new(0.6, 0.6, 0.6),
				CFrame = CFrame.new(ground + Vector3.new(0, 0.3, 0)),
				Transparency = 1,
			})
			decor(root)
			marker.PrimaryPart = root
			marker:SetAttribute("Species", exhibit.s)
			marker:SetAttribute("Variant", exhibit.v or "")
			marker:SetAttribute("Tags", "")
			marker:SetAttribute("Ground", ground)
			if exhibit.t then
				marker:SetAttribute("Trophy", exhibit.t)
			end
			if slot == freshSlot then
				-- Grzyb wyrasta na oczach tych, którzy stoją obok (później dołączający widzą go od razu)
				marker:SetAttribute("Fresh", true)
				task.delay(3, function()
					if marker.Parent then
						marker:SetAttribute("Fresh", false)
					end
				end)
			end
			CollectionService:AddTag(marker, "ShowcaseMushroom")
			marker.Parent = folder
		end
	end
	folder.Parent = cabinet
end

function ShowcaseService.refreshOf(player: Player, freshSlot: number?)
	local garden = gardenOf(player)
	if garden then
		refresh(garden, freshSlot)
	end
end

local function flags(data: any): Showcase.Flags
	return { caveUnlocked = data.caveUnlocked == true, swampUnlocked = data.swampUnlocked == true }
end

-- Okno: stan każdego miejsca i lista tego, co można wystawić
local function sendView(player: Player, open: boolean)
	local data = api.getData(player)
	if not data then
		return
	end
	local save: Showcase.Save = data.showcase
	local nextSlot, nextPrice, reason = Showcase.nextSlot(save, flags(data))
	local slots = {}
	for slot = 1, Showcase.TOTAL do
		local series = Showcase.slotOf(slot)
		local state = if slot <= save.n then "owned" elseif slot == nextSlot then "next" elseif not Showcase.seriesOpen(series, flags(data)) then "world" else "locked"
		table.insert(slots, { state = state, price = Showcase.price(slot), item = save.items[tostring(slot)] })
	end
	Remotes.get("ShowcaseView"):FireClient(player, {
		slots = slots,
		next = nextSlot,
		nextPrice = nextPrice,
		reason = reason,
		coins = data.coins,
		options = Showcase.options(data.atlas, data.trophies),
	}, open)
end

local function near(player: Player): boolean
	local garden = gardenOf(player)
	local cabinet = if garden then cabinets[garden] else nil
	local root = api.rootOf(player)
	local origin = cabinet and cabinet:GetAttribute("Origin")
	if not (root and typeof(origin) == "CFrame") then
		return false
	end
	return (root.Position - origin.Position).Magnitude <= LENGTH / 2 + Config.Showcase.promptDistance + 4
end

local function onAction(player: Player, payload: unknown)
	local now = os.clock()
	if (lastAction[player] or 0) + ACTION_GAP > now then
		return
	end
	lastAction[player] = now
	local data = api.getData(player)
	if not data or typeof(payload) ~= "table" or not near(player) then
		return
	end
	local request = payload :: any
	local save: Showcase.Save = data.showcase
	if request.op == "buy" then
		local slot, price, reason = Showcase.nextSlot(save, flags(data))
		-- Klient mówi, które miejsce kupuje: podwójne kliknięcie nie kupi dwóch
		if not slot or not price or request.slot ~= slot then
			if reason == "world" then
				api.notify(player, "MSG_SHOWCASE_WORLD")
			end
			sendView(player, false)
			return
		end
		if data.coins < price then
			api.notify(player, "MSG_SHOWCASE_NO_COINS")
			sendView(player, false)
			return
		end
		Ledger.spend(player, data, price, "Shop", "ShowcaseSlot" .. slot)
		save.n = slot
		api.notify(player, "MSG_SHOWCASE_BOUGHT", { slot, Showcase.TOTAL })
		api.pushState(player)
		ShowcaseService.refreshOf(player)
		sendView(player, false)
	elseif request.op == "set" then
		local slot = request.slot
		local exhibit = Showcase.readExhibit(request.item)
		if typeof(slot) ~= "number" or slot ~= math.floor(slot) or slot < 1 or slot > save.n or not exhibit then
			return
		end
		if not Showcase.allowed(data.atlas, data.trophies, exhibit) then
			return
		end
		save.items[tostring(slot)] = exhibit
		ShowcaseService.refreshOf(player, slot)
		sendView(player, false)
	elseif request.op == "clear" then
		local slot = request.slot
		if typeof(slot) ~= "number" or not save.items[tostring(slot)] then
			return
		end
		save.items[tostring(slot)] = nil
		ShowcaseService.refreshOf(player)
		sendView(player, false)
	end
end

-- Trofeum ze Znaleziska Nocy: do listy trofeów i od razu na pierwsze wolne miejsce w gablocie.
-- Zwraca true, gdy stanęło w gablocie (false = czeka w oknie, bo nie ma wolnego miejsca).
function ShowcaseService.addTrophy(player: Player, exhibit: Showcase.Exhibit): boolean
	local data = api.getData(player)
	if not data then
		return false
	end
	Showcase.addTrophy(data.trophies, exhibit)
	local save: Showcase.Save = data.showcase
	local slot = Showcase.firstEmpty(save)
	if slot then
		save.items[tostring(slot)] = exhibit
		ShowcaseService.refreshOf(player, slot)
	end
	return slot ~= nil
end

-- Panel DEV (Studio): gablota od zera (miejsca, wystawy i trofea), żeby przywrócić zapis po teście
function ShowcaseService.devReset(player: Player)
	local data = api.getData(player)
	if not data then
		return
	end
	data.showcase = Showcase.emptySave()
	data.trophies = {}
	ShowcaseService.refreshOf(player)
end

-- Panel DEV (Studio): wszystkie miejsca kupione (bez płacenia) i wypełnione najrzadszymi formami
function ShowcaseService.devFill(player: Player)
	local data = api.getData(player)
	if not data then
		return
	end
	local save: Showcase.Save = data.showcase
	save.n = Showcase.TOTAL
	local options = Showcase.options(data.atlas, data.trophies)
	for slot = 1, Showcase.TOTAL do
		local option = options[slot]
		if option and not save.items[tostring(slot)] then
			save.items[tostring(slot)] = option
		end
	end
	ShowcaseService.refreshOf(player)
end

function ShowcaseService.start(gardens: { Model }, serviceApi: Api)
	api = serviceApi
	for _, garden in gardens do
		local cabinet = buildCabinet(garden)
		if not cabinet then
			warn("[ShowcaseService] Ogródek bez GardenGrass: " .. garden.Name)
			continue
		end
		cabinets[garden] = cabinet
		local prompt = cabinet:FindFirstChild("ShowcasePrompt", true)
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.Triggered:Connect(function(player)
				if garden:GetAttribute("OwnerUserId") ~= player.UserId then
					return
				end
				sendView(player, true)
			end)
		end
		garden:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
			-- Dane właściciela wczytują się chwilę po przydziale ogródka
			task.delay(1, refresh, garden)
		end)
		refresh(garden)
	end
	Remotes.get("ShowcaseAction").OnServerEvent:Connect(onAction)
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
	end)
end

return ShowcaseService
