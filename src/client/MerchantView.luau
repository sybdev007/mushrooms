--!strict
-- Skupywacz w chatce po stronie klienta: teksty przycisku rozmowy i tabliczki w języku gracza,
-- a po rozmowie otwarcie panelu sprzedaży. Model stoi na serwerze (World/Merchant.luau).
-- Do tego trochę życia, tylko u tego gracza (części są zakotwiczone, ruch się nie replikuje):
--   oddech (brzuszek i ramiona lekko się unoszą), głowa kiwa się i przechyla, mruganie powiekami;
--   na Halloween Duch Pana Borowika (MerchantLook): unosi się nad podłogą i lekko kołysze.
-- Przycisk rozmowy wisi na niewidocznej części Root, której nie ruszamy (przycisk stoi w miejscu).
-- Tabliczka z imieniem wisi na głowie, więc rusza się razem z nią, ale tylko o włos.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Localize = require(script.Parent.Localize)
local MerchantLook = require(script.Parent.MerchantLook)
local SellPanel = require(script.Parent.SellPanel)

local MerchantView = {}

local ANIMATE_DISTANCE = 80 -- dalej nikt nie zobaczy oddechu
local NECK = CFrame.new(0, 4.45, -0.08) -- punkt obrotu głowy (lokalnie, nad kołnierzykiem)

type Piece = { part: BasePart, base: CFrame, head: boolean, height: number }
type Tracked = {
	model: Model,
	prompt: ProximityPrompt?,
	name: TextLabel?,
	role: TextLabel?,
	pivot: CFrame,
	pieces: { Piece },
	lids: { BasePart },
	saved: MerchantLook.Saved,
	ghost: boolean,
	nextBlink: number,
	blinkUntil: number,
}
local tracked: { [Model]: Tracked | boolean } = {}

local function refreshTexts(entry: Tracked)
	local nameKey = if entry.ghost then "NPC_NAME_GHOST" else "NPC_NAME"
	if entry.prompt then
		entry.prompt.ActionText = Localize.t("NPC_SELL")
		entry.prompt.ObjectText = Localize.t(nameKey)
	end
	if entry.name then
		entry.name.Text = Localize.t(nameKey)
	end
	if entry.role then
		entry.role.Text = Localize.t("NPC_ROLE")
	end
end

-- Części do animacji: położenie względem stóp (pivot) w chwili wczytania
local function collect(entry: Tracked)
	table.clear(entry.pieces)
	table.clear(entry.lids)
	for _, d in entry.model:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "Root" then
			local base = (d:GetAttribute("BaseCFrame") :: CFrame?) or d.CFrame
			d:SetAttribute("BaseCFrame", base)
			local localCf = entry.pivot:ToObjectSpace(base)
			table.insert(entry.pieces, { part = d, base = localCf, head = d:GetAttribute("Head") == true, height = localCf.Position.Y })
			if d.Name == "Eyelid" then
				table.insert(entry.lids, d)
			end
		end
	end
end

local function applyLook(entry: Tracked)
	local ghost = MerchantLook.isGhost()
	-- Przed zmianą wyglądu wszystko wraca na miejsce (ogon ducha liczy się od stóp modelu)
	for _, piece in entry.pieces do
		piece.part.CFrame = entry.pivot * piece.base
	end
	entry.ghost = ghost
	MerchantLook.setGhost(entry.model, ghost, entry.saved)
	collect(entry)
	refreshTexts(entry)
end

local function animate(entry: Tracked, now: number)
	local ghost = entry.ghost
	-- Duch unosi się nad podłogą i lekko kołysze; zwykły stoi
	local float = if ghost
		then CFrame.new(0, 0.6 + math.sin(now * 1.3) * 0.3, 0) * CFrame.Angles(0, math.rad(math.sin(now * 0.7) * 4), math.rad(math.sin(now * 0.9) * 1.5))
		else CFrame.new()
	local breath = math.sin(now * 1.7)
	local nod = CFrame.Angles(math.rad(math.sin(now * 0.9) * 1.6), 0, math.rad(math.sin(now * 0.55) * 2.6))
	local headTurn = NECK * nod * NECK:Inverse()
	local parts = table.create(#entry.pieces)
	local cframes = table.create(#entry.pieces)
	for _, piece in entry.pieces do
		-- Oddech: im wyżej, tym bardziej się unosi (stopy stoją)
		local lift = breath * 0.035 * math.clamp((piece.height - 1.8) / 2.6, 0, 1)
		local localCf = if piece.head then CFrame.new(0, lift, 0) * headTurn * piece.base else CFrame.new(0, lift, 0) * piece.base
		table.insert(parts, piece.part)
		table.insert(cframes, entry.pivot * float * localCf)
	end
	Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)

	-- Mruganie co kilka sekund
	if now >= entry.nextBlink then
		entry.blinkUntil = now + 0.13
		entry.nextBlink = now + 2.6 + math.random() * 2.8
	end
	local closed = now < entry.blinkUntil
	for _, lid in entry.lids do
		lid.Transparency = if closed then 0 else 1
	end
end

local function track(instance: Instance)
	if not instance:IsA("Model") or tracked[instance] then
		return
	end
	local model = instance :: Model
	tracked[model] = true -- zajęte, zanim dotrą części
	-- Model przychodzi w całości (Atomic), ale na wszelki wypadek czekamy na kluczowe części
	task.spawn(function()
		local root = model:WaitForChild("Root", 15)
		local head = model:WaitForChild("Head", 15)
		local prompt = root and root:WaitForChild("MerchantPrompt", 15)
		local tag = head and head:WaitForChild("NameTag", 15)
		local name = tag and tag:WaitForChild("Name", 5)
		local role = tag and tag:WaitForChild("Role", 5)
		if model.Parent == nil or not (root and root:IsA("BasePart")) then
			tracked[model] = nil
			return
		end
		local entry: Tracked = {
			model = model,
			prompt = if prompt and prompt:IsA("ProximityPrompt") then prompt else nil,
			name = if name and name:IsA("TextLabel") then name else nil,
			role = if role and role:IsA("TextLabel") then role else nil,
			pivot = model:GetPivot(),
			pieces = {},
			lids = {},
			saved = {},
			ghost = false,
			nextBlink = os.clock() + 2,
			blinkUntil = 0,
		}
		tracked[model] = entry
		collect(entry)
		applyLook(entry)
		if entry.prompt then
			entry.prompt.Triggered:Connect(function()
				SellPanel.open()
			end)
		end
	end)
	model.Destroying:Connect(function()
		tracked[model] = nil
	end)
end

function MerchantView.start()
	for _, model in CollectionService:GetTagged("Merchant") do
		track(model)
	end
	CollectionService:GetInstanceAddedSignal("Merchant"):Connect(track)
	Localize.onChanged(function()
		for _, entry in tracked do
			if typeof(entry) == "table" then
				refreshTexts(entry)
			end
		end
	end)
	-- Początek i koniec Halloween: zwykły Pan Borowik albo Duch
	Workspace:GetAttributeChangedSignal("Halloween"):Connect(function()
		for _, entry in tracked do
			if typeof(entry) == "table" and entry.ghost ~= MerchantLook.isGhost() then
				applyLook(entry)
			end
		end
	end)
	RunService.RenderStepped:Connect(function()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local now = os.clock()
		for _, entry in tracked do
			if typeof(entry) == "table" and entry.model.Parent then
				if (camera.CFrame.Position - entry.pivot.Position).Magnitude <= ANIMATE_DISTANCE then
					animate(entry, now)
				end
			end
		end
	end)
end

return MerchantView
