--!strict
-- Ofiara dla Leszego (plan docs/plans/endgame-zlew.md, punkt 2): kapliczka na Placu Portali, naprzeciw
-- Moździerza Zielarki. Gracz z otwartą Łysą Górą wpłaca monety (1 / 10 / 100 mln / 1 mld, w oknie
-- ShrinePanel potwierdza kwotę), a suma w data.stats.leszyOffered daje tytuły (Titles, Config.Shrine.tiers)
-- i obwódkę imienia na tabliczce ogródka (GardenService). Nic nie wypłaca i nie daje przedmiotów.
-- Bez tokenów: każdą wpłatę serwer sprawdza od nowa (Shared/Shrine.check): profil zapisywalny, Góra,
-- odległość, kwota w pełnych milionach do 1 mld, saldo, jedna wpłata na Config.Shrine.cooldown s.
-- Obciążenie i licznik zmieniają się razem, bez czekania pomiędzy (jedna sekcja, ten sam profil).
-- Kapliczkę stawiamy tu przy starcie serwera (jak regał gabloty), żeby była też na mapie zapisanej w miejscu.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Shrine = require(ReplicatedStorage.Shared.Shrine)
local Analytics = require(script.Parent.Analytics)
local Ledger = require(script.Parent.Ledger)
local Palette = require(script.Parent.World.Palette)

export type Api = {
	getData: (Player) -> any?,
	notify: (Player, string, { any }?) -> (),
	pushState: (Player) -> (),
	rootOf: (Player) -> BasePart?,
	canSave: (Player) -> boolean,
	event: (Player, string, number) -> (), -- ProgressService.event: licznik, tytuły, okna
	refreshGarden: (Player) -> (), -- obwódka tabliczki ogródka po nowym progu
}

local ShrineService = {}

local PROMPT_DISTANCE = 9 -- przycisk bliżej niż Config.Shrine.reach (serwer jest łagodniejszy przez opóźnienie)
local TRY_GAP = 0.25 -- nawet odrzucone prośby najwyżej tak często

local api: Api
local position = Vector3.new(Config.Shrine.position.x, 0, Config.Shrine.position.z)
local lastOffer: { [Player]: number } = {}
local lastTry: { [Player]: number } = {}
local ShrineView = Remotes.get("ShrineView")

local function formatCoins(value: number): string
	local s = string.format("%.0f", value)
	local formatted = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (formatted:gsub("^ ", ""))
end

local function part(parent: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.Material = Enum.Material.Wood
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = false
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

-- Przydrożna kapliczka: kamienny cokół, słup, domek z daszkiem, w środku omszały łeb z porożem
-- (Leszy), świeca i misa na ofiary z monetami. cf: przód (-Z) patrzy na środek placu.
local function build(parent: Instance, cf: CFrame): ProximityPrompt
	local m = Instance.new("Model")
	m.Name = "LeszyShrine"
	part(m, { Name = "Base", Size = Vector3.new(3, 0.8, 3), CFrame = cf * CFrame.new(0, 0.4, 0), Color = Palette.stone, Material = Enum.Material.Cobblestone })
	part(m, { Name = "Post", Size = Vector3.new(0.6, 3.6, 0.6), CFrame = cf * CFrame.new(0, 2.6, 0.3), Color = Palette.log })
	part(m, { Name = "House", Size = Vector3.new(2.4, 1.9, 1.6), CFrame = cf * CFrame.new(0, 5.3, 0.1), Color = Palette.plankDark })
	part(m, { Name = "Niche", Size = Vector3.new(1.8, 1.4, 0.1), CFrame = cf * CFrame.new(0, 5.25, -0.71), Color = Color3.fromRGB(26, 20, 16), Material = Enum.Material.SmoothPlastic })
	for _, side in { -1, 1 } do
		local roof = part(m, {
			Name = "Roof",
			Size = Vector3.new(1.7, 0.18, 2.2),
			CFrame = cf * CFrame.new(side * 0.68, 6.55, 0.1) * CFrame.Angles(0, 0, math.rad(-side * 38)),
			Color = Palette.roof,
		})
		roof.CanCollide = false
	end
	-- Omszały łeb z porożem w niszy
	part(m, { Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.new(0.9, 0.9, 0.9), CFrame = cf * CFrame.new(0, 5.15, -0.45), Color = Palette.moss, Material = Enum.Material.Grass })
	for _, side in { -1, 1 } do
		local antler = part(m, {
			Name = "Antler",
			Size = Vector3.new(0.12, 0.8, 0.12),
			CFrame = cf * CFrame.new(side * 0.35, 5.75, -0.45) * CFrame.Angles(0, 0, math.rad(-side * 30)),
			Color = Palette.logEnd,
		})
		antler.CanCollide = false
	end
	for _, side in { -1, 1 } do
		local eye = part(m, {
			Name = "Eye",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.14, 0.14, 0.14),
			CFrame = cf * CFrame.new(side * 0.17, 5.25, -0.86),
			Color = Color3.fromRGB(150, 255, 120),
			Material = Enum.Material.Neon,
		})
		eye.CanCollide = false
	end
	-- Świeca i ciepłe światło
	local candle = part(m, { Name = "Candle", Size = Vector3.new(0.22, 0.5, 0.22), CFrame = cf * CFrame.new(0.65, 4.62, -0.45), Color = Color3.fromRGB(240, 230, 200), Material = Enum.Material.SmoothPlastic })
	candle.CanCollide = false
	local flame = part(m, { Name = "Flame", Shape = Enum.PartType.Ball, Size = Vector3.new(0.16, 0.22, 0.16), CFrame = cf * CFrame.new(0.65, 4.98, -0.45), Color = Palette.lanternGlow, Material = Enum.Material.Neon })
	flame.CanCollide = false
	local light = Instance.new("PointLight")
	light.Color = Palette.lanternGlow
	light.Range = 10
	light.Brightness = 0.9
	light.Shadows = false
	light.Parent = flame
	-- Misa na ofiary przed słupem, z monetami
	part(m, { Name = "Bowl", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.35, 1.5, 1.5), CFrame = cf * CFrame.new(0, 0.98, -0.9) * CFrame.Angles(0, 0, math.rad(90)), Color = Palette.metal, Material = Enum.Material.Metal })
	local coins = part(m, { Name = "Coins", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 1.2, 1.2), CFrame = cf * CFrame.new(0, 1.18, -0.9) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(255, 205, 70), Material = Enum.Material.Neon })
	coins.CanCollide = false
	-- Przycisk (tłumaczy go klient: tag LocalizedPrompt i klucze TextKey / ObjectKey, client/Signs)
	local anchor = part(m, { Name = "PromptAnchor", Size = Vector3.new(1, 1, 1), CFrame = cf * CFrame.new(0, 2.5, -1.6), Transparency = 1 })
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LeszyShrinePrompt"
	prompt.ActionText = "Make an offering"
	prompt.ObjectText = "Offering to Leszy"
	prompt:SetAttribute("TextKey", "LESZY_OFFER_PROMPT")
	prompt:SetAttribute("ObjectKey", "LESZY_OFFER_TITLE")
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor
	CollectionService:AddTag(prompt, "LocalizedPrompt")
	m.Parent = parent
	return prompt
end

-- Stan okna u gracza (open = otwórz okno)
local function sendView(player: Player, open: boolean)
	local data = api.getData(player)
	if not data then
		return
	end
	local total = Shrine.readTotal(data.stats.leszyOffered)
	ShrineView:FireClient(player, {
		total = total,
		nextGoal = Shrine.nextGoal(total),
		coins = data.coins,
		unlocked = data.mountainUnlocked == true,
		available = api.canSave(player),
	}, open)
end

local function onAction(player: Player, amount: unknown)
	local now = os.clock()
	if now - (lastTry[player] or 0) < TRY_GAP then
		return
	end
	lastTry[player] = now
	local data = api.getData(player)
	if not data then
		return
	end
	local root = api.rootOf(player)
	local total = Shrine.readTotal(data.stats.leszyOffered)
	local ok, why = Shrine.check({
		amount = amount,
		coins = data.coins,
		total = total,
		mountainUnlocked = data.mountainUnlocked == true,
		distance = if root then (root.Position - position).Magnitude else nil,
		canSave = api.canSave(player),
		now = now,
		lastAt = lastOffer[player],
	})
	if not ok then
		if why then
			api.notify(player, why)
		end
		sendView(player, false)
		return
	end
	local value = amount :: number
	lastOffer[player] = now
	-- Obciążenie i licznik razem, bez czekania pomiędzy (ten sam profil)
	Ledger.spend(player, data, value, "Shop", "LeszyOffering")
	api.event(player, "leszyOffer", value)
	local after = Shrine.readTotal(data.stats.leszyOffered)
	if total == 0 then
		Analytics.milestone(player, "LeszyFirstOffering")
	end
	for _, goal in Shrine.crossed(total, after) do
		Analytics.milestone(player, "LeszyOffering" .. Shrine.label(goal))
	end
	api.notify(player, "LESZY_OFFER_DONE", { formatCoins(value) })
	api.pushState(player)
	if Shrine.glow(after) ~= Shrine.glow(total) then
		api.refreshGarden(player)
	end
	sendView(player, false)
end

function ShrineService.start(serviceApi: Api)
	api = serviceApi
	local parent = Workspace:FindFirstChild("Map") or Workspace
	local plaza = Config.PortalPlaza.center
	local prompt = build(parent, CFrame.lookAt(position, Vector3.new(plaza.x, 0, plaza.z)))
	prompt.Triggered:Connect(function(player: Player)
		sendView(player, true)
	end)
	Remotes.get("ShrineAction").OnServerEvent:Connect(onAction)
	Players.PlayerRemoving:Connect(function(player)
		lastOffer[player] = nil
		lastTry[player] = nil
	end)
end

return ShrineService
