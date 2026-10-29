--!strict
-- Zakładka Strażnicy w Grzybopedii: Leszy, Skarbnik, Utopiec.
-- Strażnika poznaje się, gdy ukradnie mu się strzeżony grzyb (zapis bestiary, Shared/Progress).
-- Po lewej trzy karty z portretem (model 3D w ViewportFrame; nieodkryty = czarna sylwetka),
-- po prawej opis wybranego: legenda, liczby z Config (szybkość, budzenie, próg butów do ucieczki),
-- własne liczniki gracza i rada. Stronę buduje i przełącza AtlasPanel.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Progress = require(Shared.Progress)
local Localize = require(script.Parent.Localize)
local UiKit = require(script.Parent.UiKit)

local BestiaryPage = {}

local TITLE_FONT = Enum.Font.FredokaOne
local BODY_FONT = Enum.Font.GothamBold
local LORE_FONT = Enum.Font.Gotham
local TEXT = Color3.fromRGB(252, 238, 210)
local MUTED = Color3.fromRGB(214, 188, 150)
local ACCENT = Color3.fromRGB(255, 214, 120)
local CARD = Color3.fromRGB(58, 42, 30)
local CARD_DARK = Color3.fromRGB(30, 21, 15)
local EDGE = Color3.fromRGB(96, 70, 48)
local LIST_WIDTH = 128
local GAP = 8

-- Kolor klasy Legendarny (grzyby strażników też są legendarne)
local LEGENDARY = (function(): Color3
	local class = Config.Classes[#Config.Classes]
	return Color3.fromRGB(class.color[1], class.color[2], class.color[3])
end)()

-- Gdy portret jeszcze się nie wczytał (albo siatka zawiodła): emoji na karcie
local FALLBACK_ICON: { [string]: string } = { leszy = "🌳", skarbnik = "⛏️", utopiec = "🐸" }

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function text(parent: Instance, name: string, size: UDim2, position: UDim2, font: Enum.Font, maxSize: number, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = size
	l.Position = position
	l.BackgroundTransparency = 1
	l.TextColor3 = color or TEXT
	l.Font = font
	l.TextScaled = true
	l.RichText = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = maxSize
	c.Parent = l
	return l
end

local function formatCoins(value: number): string
	local s = tostring(math.floor(value + 0.5))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (formatted:gsub("^ ", ""))
end

local function zoneName(index: number?): string
	local zone = if index then Config.Zones[index] else nil
	return if zone then Localize.t(zone.key) else "?"
end

-- ===== Portret: model strażnika w ViewportFrame =====

type Portrait = {
	viewport: ViewportFrame,
	camera: Camera,
	fallback: TextLabel,
	target: Vector3, -- środek modelu
	distance: number,
	height: number,
	ready: boolean,
}

-- Ustawia kamerę przed modelem (przód modelu to -Z), lekko z boku pod kątem `yaw`
local function aim(portrait: Portrait, yaw: number)
	if not portrait.ready then
		return
	end
	local offset = Vector3.new(math.sin(yaw) * portrait.distance, portrait.height * 0.08, -math.cos(yaw) * portrait.distance)
	portrait.camera.CFrame = CFrame.lookAt(portrait.target + offset, portrait.target)
end

local function fillPortrait(portrait: Portrait, source: Model)
	local model = source:Clone()
	model.Parent = portrait.viewport
	local box, size = model:GetBoundingBox()
	portrait.target = box.Position
	portrait.height = size.Y
	-- Odległość, z której cała postać mieści się w kadrze (kamera 40°, kadr prawie kwadratowy)
	local half = math.max(size.Y, size.X * 1.1) / 2
	portrait.distance = half / math.tan(math.rad(portrait.camera.FieldOfView / 2)) * 1.12 + size.Z / 2
	portrait.ready = true
	portrait.fallback.Visible = false
	aim(portrait, math.rad(-18))
end

local function newPortrait(parent: GuiObject, guardian: string): Portrait
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Portrait"
	viewport.Size = UDim2.new(1, -8, 1, -30)
	viewport.Position = UDim2.fromOffset(4, 4)
	viewport.BackgroundColor3 = CARD_DARK
	viewport.Ambient = Color3.fromRGB(150, 140, 130)
	viewport.LightColor = Color3.fromRGB(255, 236, 205)
	viewport.LightDirection = Vector3.new(-0.6, -1, 0.8)
	viewport.ZIndex = 2
	viewport.Parent = parent
	corner(viewport, 8)
	-- Ciepła poświata od dołu, jak od latarni
	local glow = Instance.new("UIGradient")
	glow.Rotation = 90
	glow.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 200, 140))
	glow.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local fallback = text(viewport, "Fallback", UDim2.fromScale(0.7, 0.7), UDim2.fromScale(0.15, 0.15), TITLE_FONT, 60)
	fallback.TextXAlignment = Enum.TextXAlignment.Center
	fallback.Text = FALLBACK_ICON[guardian] or "❔"
	fallback.ZIndex = 3
	local portrait: Portrait = {
		viewport = viewport,
		camera = camera,
		fallback = fallback,
		target = Vector3.zero,
		distance = 10,
		height = 8,
		ready = false,
	}
	-- Modele buduje serwer w tle (siatki z sieci), więc czekamy bez blokowania okna
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("GuardianPortraits", 60)
		local source = folder and folder:WaitForChild(guardian, 10)
		if source and source:IsA("Model") then
			fillPortrait(portrait, source)
		end
	end)
	return portrait
end

-- ===== Strona =====

export type Page = {
	frame: Frame,
	render: (bestiary: { [string]: Progress.GuardianRecord }) -> (),
	select: (id: string) -> (),
	setActive: (active: boolean) -> (),
}

type Card = {
	button: TextButton,
	stroke: UIStroke,
	name: TextLabel,
	lock: GuiObject,
	portrait: Portrait,
}

type Stat = { label: TextLabel, value: TextLabel }

function BestiaryPage.new(parent: Instance, size: UDim2, position: UDim2): Page
	local frame = Instance.new("Frame")
	frame.Name = "Guardians"
	frame.BackgroundTransparency = 1
	frame.Size = size
	frame.Position = position
	frame.Visible = false
	frame.Parent = parent

	-- Karty strażników po lewej
	local cards: { [string]: Card } = {}
	local count = #Progress.GUARDIANS
	for index, def in Progress.GUARDIANS do
		local button = Instance.new("TextButton")
		button.Name = def.id
		button.Text = ""
		button.AutoButtonColor = false
		button.BackgroundColor3 = CARD
		button.Size = UDim2.new(0, LIST_WIDTH, 1 / count, -GAP * (count - 1) / count)
		button.Position = UDim2.new(0, 0, (index - 1) / count, (index - 1) * GAP / count)
		button.Parent = frame
		corner(button, 10)
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Thickness = 2
		stroke.Color = EDGE
		stroke.Parent = button
		local portrait = newPortrait(button, def.id)
		local name = text(button, "Name", UDim2.new(1, -8, 0, 20), UDim2.new(0, 4, 1, -24), TITLE_FONT, 16)
		name.TextXAlignment = Enum.TextXAlignment.Center
		local lock = UiKit.icon("lock", button, UDim2.fromOffset(22, 22), UDim2.new(1, -8, 0, 8), Vector2.new(1, 0))
		lock.ZIndex = 4
		cards[def.id] = { button = button, stroke = stroke, name = name, lock = lock, portrait = portrait }
	end

	-- Opis wybranego strażnika po prawej
	local detail = Instance.new("Frame")
	detail.Name = "Detail"
	detail.BackgroundColor3 = CARD
	detail.Size = UDim2.new(1, -(LIST_WIDTH + GAP), 1, 0)
	detail.Position = UDim2.fromOffset(LIST_WIDTH + GAP, 0)
	detail.Parent = frame
	corner(detail, 10)
	local detailStroke = Instance.new("UIStroke")
	detailStroke.Thickness = 2
	detailStroke.Color = EDGE
	detailStroke.Parent = detail
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = detail

	local nameLabel = text(detail, "Name", UDim2.new(1, 0, 0, 28), UDim2.fromOffset(0, 8), TITLE_FONT, 26)
	UiKit.outline(nameLabel, 1.5, Color3.fromRGB(30, 18, 10))
	local epithet = text(detail, "Epithet", UDim2.new(1, 0, 0, 16), UDim2.fromOffset(0, 38), BODY_FONT, 13, MUTED)
	local lore = text(detail, "Lore", UDim2.new(1, 0, 0, 104), UDim2.fromOffset(0, 60), LORE_FONT, 14)
	lore.TextWrapped = true
	lore.TextYAlignment = Enum.TextYAlignment.Top

	-- Liczby: 2 kolumny x 3 wiersze
	local statsFrame = Instance.new("Frame")
	statsFrame.Name = "Stats"
	statsFrame.BackgroundTransparency = 1
	statsFrame.Size = UDim2.new(1, 0, 0, 110)
	statsFrame.Position = UDim2.fromOffset(0, 170)
	statsFrame.Parent = detail
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.5, -4, 0, 34)
	grid.CellPadding = UDim2.fromOffset(8, 4)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = statsFrame
	local STAT_IDS = { "guards", "lair", "speed", "wake", "escape", "safe" }
	local stats: { [string]: Stat } = {}
	for order, id in STAT_IDS do
		local cell = Instance.new("Frame")
		cell.Name = id
		cell.LayoutOrder = order
		cell.BackgroundColor3 = CARD_DARK
		cell.BackgroundTransparency = 0.35
		cell.Parent = statsFrame
		corner(cell, 6)
		local label = text(cell, "Label", UDim2.new(1, -12, 0, 12), UDim2.fromOffset(6, 3), BODY_FONT, 11, MUTED)
		local value = text(cell, "Value", UDim2.new(1, -12, 0, 16), UDim2.fromOffset(6, 15), TITLE_FONT, 15)
		stats[id] = { label = label, value = value }
	end

	local record = text(detail, "Record", UDim2.new(1, 0, 0, 16), UDim2.fromOffset(0, 286), BODY_FONT, 13, MUTED)
	local tip = text(detail, "Tip", UDim2.new(1, 0, 0, 40), UDim2.fromOffset(0, 306), LORE_FONT, 13, ACCENT)
	tip.TextWrapped = true
	tip.TextYAlignment = Enum.TextYAlignment.Top

	-- ===== Stan =====

	local selected = Progress.GUARDIANS[1].id
	local last: { [string]: Progress.GuardianRecord } = {}
	local spin: RBXScriptConnection? = nil

	local function setStat(id: string, label: string, value: string, color: Color3?)
		local stat = stats[id]
		stat.label.Text = label
		stat.value.Text = value
		stat.value.TextColor3 = color or TEXT
	end

	local function renderDetail(def: Progress.GuardianDef, info: Progress.GuardianRecord)
		local species = Economy.guardianSpecies(def.id)
		local lairZone = if species[1] then species[1].zone else nil
		local safeZone = Progress.safeZone(def.world)
		local known = info.found

		nameLabel.Text = if known then Localize.t(def.key) else "???"
		nameLabel.TextColor3 = if known then LEGENDARY else MUTED
		epithet.Text = if known
			then string.format("%s  ·  %s", Localize.t(def.key .. "_TITLE"), Localize.t("ATLAS_PAGE_" .. string.upper(def.world)))
			else Localize.t("BESTIARY_UNKNOWN_TITLE")
		lore.Text = Localize.t(if known then def.key .. "_LORE" else "BESTIARY_LOCKED")
		lore.TextColor3 = if known then TEXT else MUTED

		-- Kryjówkę widać zawsze (jak strefy nieznanych grzybów), reszta po odkryciu
		setStat("lair", Localize.t("BESTIARY_LAIR"), zoneName(lairZone))
		if known then
			local names = {}
			local value = 0
			for _, s in species do
				table.insert(names, Localize.t(s.key))
				value = math.max(value, s.value)
			end
			setStat("guards", Localize.t("BESTIARY_GUARDS"), string.format("%s  💰 %s", table.concat(names, " / "), formatCoins(value)), LEGENDARY)
			setStat("speed", Localize.t("BESTIARY_SPEED"), string.format("%g", def.chase.speed))
			setStat("wake", Localize.t("BESTIARY_WAKE"), Localize.t("BESTIARY_SECONDS", { string.format("%g", def.chase.wakeDelay) }))
			local boots = Progress.bootsToEscape(def)
			if boots then
				setStat("escape", Localize.t("BESTIARY_ESCAPE"), "🥾 " .. Localize.t("BESTIARY_ESCAPE_LEVEL", { boots }), ACCENT)
			else
				setStat("escape", Localize.t("BESTIARY_ESCAPE"), Localize.t("BESTIARY_ESCAPE_NONE"), Color3.fromRGB(255, 120, 100))
			end
			setStat("safe", Localize.t("BESTIARY_SAFE"), zoneName(safeZone), Color3.fromRGB(150, 255, 150))
			record.Text = Localize.t("BESTIARY_RECORD", { info.stolen, info.escaped, info.caught })
			tip.Text = "💡 " .. Localize.t(def.key .. "_TIP")
		else
			setStat("guards", Localize.t("BESTIARY_GUARDS"), "???", MUTED)
			setStat("speed", Localize.t("BESTIARY_SPEED"), "???", MUTED)
			setStat("wake", Localize.t("BESTIARY_WAKE"), "???", MUTED)
			setStat("escape", Localize.t("BESTIARY_ESCAPE"), "???", MUTED)
			setStat("safe", Localize.t("BESTIARY_SAFE"), "???", MUTED)
			record.Text = ""
			tip.Text = ""
		end
	end

	local function render(bestiary: { [string]: Progress.GuardianRecord })
		last = bestiary
		for _, def in Progress.GUARDIANS do
			local card = cards[def.id]
			local info = Progress.guardianRecord(bestiary, def.id)
			local isSelected = def.id == selected
			card.name.Text = if info.found then Localize.t(def.key) else "???"
			card.name.TextColor3 = if info.found then (if isSelected then ACCENT else TEXT) else MUTED
			card.lock.Visible = not info.found
			card.stroke.Color = if isSelected then ACCENT else EDGE
			card.button.BackgroundColor3 = if isSelected then Color3.fromRGB(84, 60, 40) else CARD
			-- Nieodkryty: czarna sylwetka (jak nieodkryte formy grzybów)
			local viewport = card.portrait.viewport
			viewport.ImageColor3 = if info.found then Color3.new(1, 1, 1) else Color3.new(0, 0, 0)
			viewport.ImageTransparency = if info.found then 0 else 0.35
			card.portrait.fallback.TextTransparency = if info.found then 0 else 0.6
			if isSelected then
				renderDetail(def, info)
			end
		end
	end

	local function selectGuardian(id: string)
		if Progress.getGuardian(id) then
			selected = id
			render(last)
		end
	end

	-- Wybrany i odkryty strażnik powoli się obraca, pozostałe stoją bokiem
	local function setActive(active: boolean)
		frame.Visible = active
		if active and spin then
			return -- już się kręci (np. nowa paczka danych przy otwartym oknie)
		end
		if spin then
			spin:Disconnect()
			spin = nil
		end
		for _, card in cards do
			aim(card.portrait, math.rad(-18))
		end
		if active then
			local started = os.clock()
			spin = RunService.RenderStepped:Connect(function()
				local card = cards[selected]
				if card and Progress.guardianRecord(last, selected).found then
					aim(card.portrait, math.rad(-18) + math.sin((os.clock() - started) * 0.8) * math.rad(32))
				end
			end)
		end
	end

	for id, card in cards do
		card.button.Activated:Connect(function()
			if id ~= selected then
				-- Poprzedni wraca do pozy bokiem
				local previous = cards[selected]
				if previous then
					aim(previous.portrait, math.rad(-18))
				end
			end
			selectGuardian(id)
		end)
	end

	return {
		frame = frame,
		render = render,
		select = selectGuardian,
		setActive = setActive,
	}
end

return BestiaryPage
