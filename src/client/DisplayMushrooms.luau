--!strict
-- Grzyby do oglądania (nie do zbierania jak w lesie) wyglądają tak samo jak w lesie: serwer stawia tylko
-- znacznik (Model z niewidzialną częścią "Root", atrybuty Species / Variant / Tags), a tutaj każdy gracz
-- rysuje na nim grzyba kodem z MushroomView: ten sam kształt gatunku, warianty, cechy, aury, snopy
-- światła i zarodniki. Model trafia do środka znacznika, więc znika razem z nim.
--   "GardenMushroom" — grządki w ogródkach (zmniejszone, żeby zmieściły się w skrzyni; scenka kradzieży
--                      TheftCutscene kopiuje je jak wcześniej). Tabliczka nad grządką zależy od odległości
--                      (updateGardenLabels): z daleka nic, bliżej plakietka z dochodem, a jedna grządka
--                      naraz (najbliższa albo ta na środku ekranu) ma pełną kartę: nazwa, mutacje w ich
--                      kolorach i w języku gracza, wartość i dochód (atrybuty Value / Rate od serwera).
--                      Rzadkie grzyby mają gwiazdki przy nazwie (★ epicki, ★★ legendarny, ★★★ mityczny)
--                      i plakietkę w kolorze rzadkości. Nad całym ogródkiem wisi szyld z jego
--                      najrzadszymi grzybami („★★ LEGENDARNY ×4 · TĘCZOWY ×2”), widoczny z drugiej
--                      strony polany: im rzadsze grzyby, tym z dalszej odległości (gardenBanner).
--   "HoardMushroom"  — grzyby odebrane przez strażnika (Leszy, Skarbnik, Utopiec) w jego legowisku,
--                      z napisem mutacji nad grzybem.
--   "RavenDrop"      — grzyb, który kruk Baby Jagi upuścił obok gracza (Łysa Góra), wygląda jak w skarbcu.
-- Atrybut "Ground" (Vector3) = punkt na ziemi pod grzybem, gdy Root stoi wyżej (np. przycisk zabrania).
-- Atrybut "Fresh" = świeżo położony: wyrasta z ziemi; inaczej stoi od razu.
-- Napisy siedzą w PlayerGui z Adornee na znaczniku (jak tytuły graczy w TitleView).
-- StreamingEnabled: gdy gracz odejdzie daleko, Root znacznika wypada z klienta, a sam Model zostaje
-- (tag się nie zdejmuje). BillboardGui z Adornee poza światem Roblox rysuje w (0, 0, 0), czyli przed
-- chatką — stąd wisiały tam tabliczki grządek. Dlatego tabliczka żyje tylko razem ze swoim Root:
-- znika, gdy Root wypadnie, i wraca na nowym Root, gdy ten dojdzie z powrotem.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Economy = require(ReplicatedStorage.Shared.Economy)
local ClassColor = require(script.Parent.ClassColor)
local Localize = require(script.Parent.Localize)
local MushroomView = require(script.Parent.MushroomView)
local MutationText = require(script.Parent.MutationText)

local DisplayMushrooms = {}

-- Grzyb mieści się na grządce (skrzynia 3,4 studa) i pod tabliczką (4,4 studa nad ziemią)
DisplayMushrooms.FIT = Vector2.new(3.2, 3.4)

type Kind = { fit: Vector2?, garden: boolean }
local KINDS: { [string]: Kind } = {
	GardenMushroom = { fit = DisplayMushrooms.FIT, garden = true },
	-- w kółku co ok. 3,3 studa (Config.Hoard.radius)
	HoardMushroom = { fit = Vector2.new(3.4, 4.6), garden = false },
	-- Grzyb upuszczony przez kruka Baby Jagi (RavenService): leży chwilę, właściciel go podnosi
	RavenDrop = { fit = Vector2.new(3.4, 4.6), garden = false },
}

local RATE_COLOR = "#A6F06A"
local VALUE_COLOR = Color3.fromRGB(255, 226, 140)
local RATE_TEXT_COLOR = Color3.fromRGB(166, 240, 106)

-- Poziomy tabliczek grządek (odległość w poziomie od postaci, studs). Stały rozmiar w pikselach i ta
-- sama wysokość nad każdą grządką sprawiały, że z furtki trzy rzędy kart zlewały się w jedną.
local CARD_RANGE = 7 -- najbliższa grządka w tym promieniu ma pełną kartę
local CHIP_RANGE = 22 -- dalej nie ma żadnej tabliczki (widać poświatę grzyba)
local AIM_ANGLE = math.rad(6) -- albo grządka na środku ekranu (kamera patrzy prawie prosto na nią)
local CHIP_SIZE = UDim2.fromOffset(76, 22)

type Mode = "card" | "chip" | "hidden"

type Label = {
	gui: BillboardGui,
	mutations: TextLabel,
	value: TextLabel?,
	info: MushroomView.MushroomInfo,
	refresh: () -> (),
	-- Tylko tabliczki grządek: poziom wybiera updateGardenLabels
	root: BasePart?,
	setMode: ((Mode) -> ())?,
	distance: number?,
}

local ids: { [Instance]: string } = {}
local labels: { [Instance]: Label } = {}
-- Połączenia tabliczki (atrybuty, pilnowanie Root) — rozłączane razem z nią
local connections: { [Instance]: { RBXScriptConnection } } = {}
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local counter = 0

local function track(marker: Instance, connection: RBXScriptConnection)
	local list = connections[marker]
	if not list then
		list = {}
		connections[marker] = list
	end
	table.insert(list, connection)
end

-- Root znacznika (przy streamingu może go chwilowo nie być)
local function rootOf(marker: Instance): BasePart?
	local root = marker:FindFirstChild("Root")
	return if root and root:IsA("BasePart") then root else nil
end

local function formatRate(rate: number): string
	return if rate < 10 then string.format("%.1f", rate) else tostring(math.floor(rate + 0.5))
end

-- Krótko na plakietkę: 640, 4,6K, 1,2M (w polskiej wersji przecinek)
local function compact(value: number): string
	if value < 1000 then
		return formatRate(value)
	end
	local function one(x: number, suffix: string): string
		local text = if x < 10 then string.format("%.1f", x) else tostring(math.floor(x))
		text = text:gsub("%.0$", "")
		if Localize.getLocale() == "pl" then
			text = text:gsub("%.", ",")
		end
		return text .. suffix
	end
	if value >= 1e9 then
		return one(value / 1e9, "B")
	elseif value >= 1e6 then
		return one(value / 1e6, "M")
	end
	return one(value / 1e3, "K")
end

local function formatCoins(value: number): string
	local s = tostring(math.floor(value + 0.5))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (formatted:gsub("^ ", ""))
end

local function textLabel(parent: Instance, size: UDim2, position: UDim2, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = size
	label.Position = position
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.RichText = true
	label.TextColor3 = color
	label.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(30, 20, 12)
	stroke.Parent = label
	return label
end

local function infoOf(marker: Model): MushroomView.MushroomInfo?
	local root = marker.PrimaryPart or marker:FindFirstChildWhichIsA("BasePart")
	local species = marker:GetAttribute("Species")
	if not root or typeof(species) ~= "string" then
		return nil
	end
	local variant = marker:GetAttribute("Variant")
	local tagsText = marker:GetAttribute("Tags")
	local tags: { string }? = nil
	if typeof(tagsText) == "string" and tagsText ~= "" then
		tags = string.split(tagsText, ",")
	end
	local ground = marker:GetAttribute("Ground")
	counter += 1
	return {
		id = "display_" .. counter,
		position = if typeof(ground) == "Vector3" then ground else root.Position,
		species = species,
		variant = if typeof(variant) == "string" and variant ~= "" then variant else nil,
		tags = tags,
	}
end

-- ===== Rzadkość grzybów w ogródku =====
-- (tylko ogródki: grzyby do zbierania w lesie wyglądają tak jak zawsze, MushroomView)

local CLASS_RANK: { [string]: number } = { common = 0, uncommon = 1, rare = 2, epic = 3, legendary = 4, mythic = 5, secret = 5 }

-- Klasa gatunku jako liczba: 0 pospolity ... 3 epicki, 4 legendarny, 5 mityczny i sekretny (z kuźni)
local function classRank(species: string): number
	return CLASS_RANK[Economy.speciesClass(species).id] or 0
end

-- Stopień rzadkości: 0 brak, 1 złoty, 2 tęczowy albo epicki, 3 kosmiczny albo legendarny,
-- 4 mityczny albo sekretny. Im wyższy, tym dalej widać szyld ogródka.
local function rarityTier(info: MushroomView.MushroomInfo): number
	local variantRank = Economy.variantRank(info.variant)
	local rank = classRank(info.species)
	local byVariant = if variantRank >= 4 then 3 elseif variantRank >= 3 then 2 elseif variantRank >= 2 then 1 else 0
	local byClass = if rank >= 5 then 4 elseif rank >= 4 then 3 elseif rank >= 3 then 2 else 0
	return math.max(byVariant, byClass)
end

-- Kolor rzadkości (ramka plakietki): tęcza i kosmos wygrywają z klasą, potem epicki i wyżej, potem złoto
local function rarityAccent(info: MushroomView.MushroomInfo): Color3
	local variantColor = if Economy.variantRank(info.variant) >= 3 then MutationText.variantColor(info.variant) else nil
	if variantColor then
		return variantColor
	end
	if classRank(info.species) >= 3 then
		local class = Economy.speciesClass(info.species)
		return Color3.fromRGB(class.color[1], class.color[2], class.color[3])
	end
	return MutationText.variantColor(info.variant) or Color3.new(1, 1, 1)
end

-- Gwiazdki przed nazwą według klasy (3 epicki, 4 legendarny, 5 mityczny / sekretny)
local STARS: { [number]: string } = setmetatable({ [3] = "★ ", [4] = "★★ ", [5] = "★★★ " }, {
	__index = function()
		return ""
	end,
}) :: any

-- ===== Szyld nad ogródkiem =====
-- Najrzadsze grzyby ogródka jednym napisem nad środkową grządką, np. „★★ LEGENDARNY ×4 · TĘCZOWY ×2”.
-- Widać go z daleka (im rzadsze grzyby, tym dalej), żeby inni gracze od razu wiedzieli, gdzie rosną
-- skarby. Liczy się na kliencie ze znaczników grządek (atrybuty Species / Variant / Tags).

local BANNER_DISTANCE = { 70, 120, 160, 200 } -- według najwyższego stopnia (rarityTier)
local BANNER_GROUPS = 3
local BANNER_BG = Color3.fromRGB(22, 16, 34)

type Banner = { gui: BillboardGui, label: TextLabel, border: UIStroke, anchor: BasePart }
local banners: { [Model]: Banner } = {}
local bannerDirty: { [Model]: boolean } = {}
local gardenOfMarker: { [Instance]: Instance } = {} -- znacznik grządki -> ogródek (przy usuwaniu nie ma już rodzica)

local function hexOf(c: Color3): string
	return "#" .. c:ToHex()
end

-- Napis jednej grupy (klasa z gwiazdkami albo wariant) i jej stopień; nil = zwykły grzyb
local function groupOf(info: MushroomView.MushroomInfo): (string?, number, Color3)
	local tier = rarityTier(info)
	if tier <= 0 then
		return nil, 0, Color3.new(1, 1, 1)
	end
	local rank = classRank(info.species)
	local classTier = if rank >= 5 then 4 elseif rank >= 4 then 3 elseif rank >= 3 then 2 else 0
	if classTier >= tier then
		local class = Economy.speciesClass(info.species)
		local color = Color3.fromRGB(class.color[1], class.color[2], class.color[3])
		local text = string.format('<font color="%s">%s%s</font>', hexOf(color), STARS[rank], MutationText.upper(Localize.t(class.key)))
		return text, tier, color
	end
	return MutationText.variantTitle(info.variant), tier, MutationText.variantColor(info.variant) or Color3.new(1, 1, 1)
end

local function refreshBanner(garden: Model)
	bannerDirty[garden] = nil
	local planted = garden:FindFirstChild("Planted")
	local groups: { [string]: { text: string, tier: number, count: number, color: Color3 } } = {}
	if planted and garden.Parent then
		for _, marker in planted:GetChildren() do
			local species = marker:GetAttribute("Species")
			if typeof(species) == "string" then
				local variant = marker:GetAttribute("Variant")
				local info: MushroomView.MushroomInfo = {
					id = "",
					position = Vector3.zero,
					species = species,
					variant = if typeof(variant) == "string" and variant ~= "" then variant else nil,
				}
				local text, tier, color = groupOf(info)
				if text then
					local group = groups[text]
					if group then
						group.count += 1
					else
						groups[text] = { text = text, tier = tier, count = 1, color = color }
					end
				end
			end
		end
	end
	local list = {}
	for _, group in groups do
		table.insert(list, group)
	end
	table.sort(list, function(a, b)
		if a.tier ~= b.tier then
			return a.tier > b.tier
		end
		return a.count > b.count
	end)
	local banner = banners[garden]
	local anchor = garden:FindFirstChild("Bed5", true) or garden:FindFirstChild("Bed1", true)
	if #list == 0 or not anchor or not anchor:IsA("BasePart") then
		if banner then
			banner.gui:Destroy()
			banners[garden] = nil
		end
		return
	end
	if not banner then
		local gui = Instance.new("BillboardGui")
		gui.Name = "GardenBanner"
		gui.Size = UDim2.new(7, 150, 1.1, 22)
		gui.StudsOffset = Vector3.new(0, 9, 0)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.ResetOnSpawn = false
		local pill = Instance.new("Frame")
		pill.Size = UDim2.fromScale(1, 1)
		pill.BackgroundColor3 = BANNER_BG
		pill.BackgroundTransparency = 0.2
		pill.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = pill
		local border = Instance.new("UIStroke")
		border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		border.Thickness = 3
		border.Parent = pill
		local label = textLabel(pill, UDim2.new(1, -20, 0.78, 0), UDim2.fromScale(0.5, 0.5), Color3.new(1, 1, 1))
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		gui.Parent = playerGui
		banner = { gui = gui, label = label, border = border, anchor = anchor }
		banners[garden] = banner
	end
	local b = banner :: Banner
	b.anchor = anchor
	b.gui.Adornee = anchor
	b.gui.MaxDistance = BANNER_DISTANCE[list[1].tier] or 120
	b.border.Color = list[1].color
	local parts = {}
	for i = 1, math.min(BANNER_GROUPS, #list) do
		local group = list[i]
		table.insert(parts, group.text .. (if group.count > 1 then " ×" .. group.count else ""))
	end
	b.label.Text = table.concat(parts, "  ·  ")
end

-- Zmiany w ogródku liczymy raz na klatkę, nawet gdy naraz dojdzie kilka grządek
local function markBanner(garden: Instance?)
	if not garden or not garden:IsA("Model") or not CollectionService:HasTag(garden, "GardenPlot") then
		return
	end
	if bannerDirty[garden] then
		return
	end
	bannerDirty[garden] = true
	task.defer(refreshBanner, garden)
end

-- Tabliczka nad grządką. Pełna karta: nazwa gatunku w kolorze klasy / [mutacje w kolorach] /
-- 💰 wartość  +dochód/min, obwódka w kolorze klasy (klasę mówi kolor nazwy, bez osobnych znaków).
-- Plakietka: kropka w kolorze wariantu (bez wariantu: klasy) i sam dochód.
local function gardenLabel(marker: Model, root: BasePart, info: MushroomView.MushroomInfo): Label
	local gui = Instance.new("BillboardGui")
	gui.Name = "GardenSlotTag"
	gui.StudsOffset = Vector3.new(0, 4.4, 0)
	gui.MaxDistance = 45
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.ResetOnSpawn = false
	gui.Adornee = root
	gui.Size = CHIP_SIZE
	gui.Enabled = false -- poziom ustawia updateGardenLabels
	local classColor = ClassColor.of(info.species)

	local box = Instance.new("Frame")
	box.Size = UDim2.fromScale(1, 1)
	box.BackgroundColor3 = Color3.fromRGB(40, 28, 20)
	box.BackgroundTransparency = 0.25
	box.Visible = false
	box.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = box
	local border = Instance.new("UIStroke")
	border.Thickness = 1.5
	border.Color = classColor
	border.Parent = box
	local name = textLabel(box, UDim2.new(1, -8, 0, 17), UDim2.fromOffset(4, 3), Color3.new(1, 1, 1))
	ClassColor.paint(name, info.species)
	local mutations = textLabel(box, UDim2.new(1, -8, 0, 15), UDim2.fromOffset(4, 21), Color3.new(1, 1, 1))
	local value = textLabel(box, UDim2.new(1, -8, 0, 16), UDim2.fromOffset(4, 21), VALUE_COLOR)

	local chip = Instance.new("Frame")
	chip.Size = UDim2.fromScale(1, 1)
	chip.BackgroundColor3 = Color3.fromRGB(40, 28, 20)
	chip.BackgroundTransparency = 0.25
	chip.Visible = false
	chip.Parent = gui
	local chipCorner = Instance.new("UICorner")
	chipCorner.CornerRadius = UDim.new(0, 7)
	chipCorner.Parent = chip
	local chipBorder = Instance.new("UIStroke")
	-- Rzadki grzyb (złoty i wyżej, epicki i wyżej): grubsza ramka w kolorze rzadkości
	local rare = rarityTier(info) > 0
	chipBorder.Thickness = if rare then 2.5 else 1.5
	chipBorder.Color = if rare then rarityAccent(info) else classColor
	chipBorder.Parent = chip
	local variant = Economy.getVariant(info.variant)
	local dot = Instance.new("Frame")
	dot.Size = UDim2.fromOffset(9, 9)
	dot.Position = UDim2.new(0, 7, 0.5, -4)
	dot.BackgroundColor3 = if variant then Color3.fromRGB(variant.color[1], variant.color[2], variant.color[3]) else classColor
	dot.BorderSizePixel = 0
	dot.Parent = chip
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot
	local chipRate = textLabel(chip, UDim2.new(1, -24, 1, -6), UDim2.fromOffset(20, 3), RATE_TEXT_COLOR)

	local hasMutations = false
	local function layout(mode: Mode)
		gui.Enabled = mode ~= "hidden"
		box.Visible = mode == "card"
		chip.Visible = mode == "chip"
		if mode == "card" then
			-- Z mutacjami karta jest wyższa (nazwa, mutacje w kolorach, wartość z dochodem)
			gui.Size = if hasMutations then UDim2.fromOffset(136, 58) else UDim2.fromOffset(136, 42)
		elseif mode == "chip" then
			gui.Size = CHIP_SIZE
		end
	end

	local function refresh()
		local species = Economy.getSpecies(info.species)
		name.Text = STARS[classRank(info.species)] .. (if species then Localize.t(species.key) else "?")
		local text = MutationText.rich(info.variant, info.tags)
		hasMutations = text ~= ""
		mutations.Text = text
		mutations.Visible = hasMutations
		value.Position = UDim2.fromOffset(4, if hasMutations then 38 else 21)
		local amount = marker:GetAttribute("Value")
		local rate = marker:GetAttribute("Rate")
		value.Text = string.format(
			'💰 %s  <font color="%s">+%s/min</font>',
			if typeof(amount) == "number" then formatCoins(amount) else "…",
			RATE_COLOR,
			if typeof(rate) == "number" then formatRate(rate) else "…"
		)
		chipRate.Text = "+" .. (if typeof(rate) == "number" then compact(rate) else "…") .. "/min"
	end

	local mode: Mode = "hidden"
	local entry: Label = {
		gui = gui,
		mutations = mutations,
		value = value,
		info = info,
		refresh = function()
			refresh()
			layout(mode)
		end,
		root = root,
		setMode = function(next: Mode)
			if next ~= mode then
				mode = next
				layout(mode)
			end
		end,
	}
	refresh()
	track(
		marker,
		marker.AttributeChanged:Connect(function(attribute)
			if attribute == "Value" or attribute == "Rate" then
				refresh()
			end
		end)
	)
	gui.Parent = playerGui
	return entry
end

-- Poziomy tabliczek grządek: jedna pełna karta (najbliższa grządka w CARD_RANGE, a bez takiej ta, na
-- którą patrzy kamera), plakietki do CHIP_RANGE, dalej nic
local function updateGardenLabels()
	local camera = Workspace.CurrentCamera
	local character = Players.LocalPlayer.Character
	local body = character and character:FindFirstChild("HumanoidRootPart")
	local origin: Vector3? = if body and body:IsA("BasePart") then body.Position elseif camera then camera.CFrame.Position else nil
	if not origin then
		return
	end
	local eye = if camera then camera.CFrame.Position else origin
	local look = if camera then camera.CFrame.LookVector else Vector3.new(0, 0, -1)
	local nearest: Label?, nearestDistance = nil, CARD_RANGE
	local aimed: Label?, aimedAngle = nil, AIM_ANGLE
	for _, entry in labels do
		local root = entry.root
		if entry.setMode and root then
			local p = root.Position
			local distance = Vector2.new(p.X - origin.X, p.Z - origin.Z).Magnitude
			entry.distance = distance
			if distance < nearestDistance then
				nearest, nearestDistance = entry, distance
			end
			local to = p + Vector3.new(0, 1.5, 0) - eye
			if distance <= CHIP_RANGE and to.Magnitude > 0.1 then
				local angle = math.acos(math.clamp(look:Dot(to.Unit), -1, 1))
				if angle < aimedAngle then
					aimed, aimedAngle = entry, angle
				end
			end
		end
	end
	local focus = nearest or aimed
	for _, entry in labels do
		local setMode = entry.setMode
		local distance = entry.distance
		if setMode and distance then
			setMode(if entry == focus then "card" elseif distance <= CHIP_RANGE then "chip" else "hidden")
		end
	end
end

-- Napis z mutacjami nad grzybem w skarbcu (tylko gdy ma mutacje)
local function hoardLabel(root: BasePart, info: MushroomView.MushroomInfo): Label?
	if MutationText.rich(info.variant, info.tags) == "" then
		return nil
	end
	local gui, label = MutationText.billboard("HoardMutations", UDim2.fromOffset(150, 24), 60)
	gui.StudsOffset = Vector3.new(0, 4.6, 0) -- Root stoi 0,8 nad ziemią, grzyb ma do 4,6 studa
	gui.Adornee = root
	local entry: Label = {
		gui = gui,
		mutations = label,
		info = info,
		refresh = function()
			label.Text = MutationText.rich(info.variant, info.tags)
		end,
	}
	entry.refresh()
	gui.Parent = playerGui
	return entry
end

local function dropLabel(marker: Instance)
	local entry = labels[marker]
	if entry then
		labels[marker] = nil
		entry.gui:Destroy()
	end
	local list = connections[marker]
	if list then
		connections[marker] = nil
		for _, connection in list do
			connection:Disconnect()
		end
	end
end

-- Tabliczka przypięta do bieżącego Root. Gdy Root wypadnie (streaming), tabliczka znika, zanim Roblox
-- zdąży narysować ją w (0, 0, 0); gdy dojdzie nowy Root, tabliczka wraca na nim.
local function attachLabel(marker: Model, kind: Kind, info: MushroomView.MushroomInfo)
	local root = rootOf(marker)
	if not root or not root:IsDescendantOf(workspace) then
		track(
			marker,
			marker.ChildAdded:Connect(function(child)
				if child.Name == "Root" and child:IsA("BasePart") and ids[marker] then
					dropLabel(marker)
					attachLabel(marker, kind, info)
				end
			end)
		)
		return
	end
	local label = if kind.garden then gardenLabel(marker, root, info) else hoardLabel(root, info)
	if label then
		labels[marker] = label
	end
	track(
		marker,
		root.AncestryChanged:Connect(function()
			if root:IsDescendantOf(workspace) then
				return
			end
			dropLabel(marker)
			if ids[marker] and marker.Parent then
				attachLabel(marker, kind, info)
			end
		end)
	)
end

local function added(marker: Instance, kind: Kind)
	if not marker:IsA("Model") or ids[marker] then
		return
	end
	-- Przy StreamingEnabled część znacznika może dojść chwilę później
	if not rootOf(marker) then
		marker:WaitForChild("Root", 10)
		if not marker.Parent or ids[marker] then
			return
		end
	end
	local info = infoOf(marker)
	if not info or not rootOf(marker) then
		return
	end
	ids[marker] = info.id
	local garden = if kind.garden and marker.Parent then marker.Parent.Parent else nil
	if garden then
		gardenOfMarker[marker] = garden
		markBanner(garden)
	end
	MushroomView.add({ info }, {
		decorative = true,
		parent = marker :: Instance,
		grow = marker:GetAttribute("Fresh") == true,
		fit = kind.fit,
	})
	attachLabel(marker, kind, info)
end

local function removed(marker: Instance)
	dropLabel(marker)
	-- Grządka opustoszała albo właściciel wyszedł: szyld ogródka liczy się od nowa
	local garden = gardenOfMarker[marker]
	gardenOfMarker[marker] = nil
	markBanner(garden)
	local id = ids[marker]
	if id then
		ids[marker] = nil
		MushroomView.forget(id)
	end
end

function DisplayMushrooms.start()
	Localize.onChanged(function()
		for _, entry in labels do
			entry.refresh()
		end
		for garden in banners do
			refreshBanner(garden)
		end
	end)
	task.spawn(function()
		while true do
			updateGardenLabels()
			-- Szyld bez grządki w świecie (streaming) Roblox rysowałby w (0, 0, 0), czyli przy chatce
			for garden, banner in banners do
				local inWorld = banner.anchor:IsDescendantOf(Workspace)
				if banner.gui.Enabled ~= inWorld then
					banner.gui.Enabled = inWorld
				end
				if not garden.Parent then
					banner.gui:Destroy()
					banners[garden] = nil
				end
			end
			task.wait(0.15)
		end
	end)
	for tag, kind in KINDS do
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(marker)
			task.spawn(added, marker, kind)
		end)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(removed)
		for _, marker in CollectionService:GetTagged(tag) do
			task.spawn(added, marker, kind)
		end
	end
end

return DisplayMushrooms
