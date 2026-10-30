--!strict
-- Grzyby do oglądania (nie do zbierania jak w lesie) wyglądają tak samo jak w lesie: serwer stawia tylko
-- znacznik (Model z niewidzialną częścią "Root", atrybuty Species / Variant / Tags), a tutaj każdy gracz
-- rysuje na nim grzyba kodem z MushroomView: ten sam kształt gatunku, warianty, cechy, aury, snopy
-- światła i zarodniki. Model trafia do środka znacznika, więc znika razem z nim.
--   "GardenMushroom" — grządki w ogródkach (zmniejszone, żeby zmieściły się w skrzyni; scenka kradzieży
--                      TheftCutscene kopiuje je jak wcześniej). Tabliczka nad grządką: mutacje w ich
--                      kolorach i w języku gracza, wartość i dochód (atrybuty Value / Rate od serwera).
--   "HoardMushroom"  — grzyby odebrane przez strażnika (Leszy, Skarbnik, Utopiec) w jego legowisku,
--                      z napisem mutacji nad grzybem.
-- Atrybut "Ground" (Vector3) = punkt na ziemi pod grzybem, gdy Root stoi wyżej (np. przycisk zabrania).
-- Atrybut "Fresh" = świeżo położony: wyrasta z ziemi; inaczej stoi od razu.
-- Napisy siedzą w PlayerGui z Adornee na znaczniku (jak tytuły graczy w TitleView).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Economy)
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
}

local RATE_COLOR = "#A6F06A"
local VALUE_COLOR = Color3.fromRGB(255, 226, 140)

type Label = {
	gui: BillboardGui,
	mutations: TextLabel,
	value: TextLabel?,
	info: MushroomView.MushroomInfo,
	refresh: () -> (),
}

local ids: { [Instance]: string } = {}
local labels: { [Instance]: Label } = {}
local connections: { [Instance]: RBXScriptConnection } = {}
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local counter = 0

local function formatRate(rate: number): string
	return if rate < 10 then string.format("%.1f", rate) else tostring(math.floor(rate + 0.5))
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

-- Tabliczka nad grządką: [mutacje w kolorach] / 💰 wartość / +dochód/min, obwódka w kolorze klasy
local function gardenLabel(marker: Model, root: BasePart, info: MushroomView.MushroomInfo): Label
	local gui = Instance.new("BillboardGui")
	gui.Name = "GardenSlotTag"
	gui.StudsOffset = Vector3.new(0, 4.4, 0)
	gui.MaxDistance = 45
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.ResetOnSpawn = false
	gui.Adornee = root
	local box = Instance.new("Frame")
	box.Size = UDim2.fromScale(1, 1)
	box.BackgroundColor3 = Color3.fromRGB(40, 28, 20)
	box.BackgroundTransparency = 0.25
	box.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = box
	local class = Economy.speciesClass(info.species)
	local border = Instance.new("UIStroke")
	border.Thickness = 1.5
	border.Color = Color3.fromRGB(class.color[1], class.color[2], class.color[3])
	border.Parent = box
	local mutations = textLabel(box, UDim2.new(1, -8, 0, 17), UDim2.fromOffset(4, 3), Color3.new(1, 1, 1))
	local value = textLabel(box, UDim2.new(1, -8, 0, 36), UDim2.fromOffset(4, 3), VALUE_COLOR)

	local function refresh()
		local text = MutationText.rich(info.variant, info.tags)
		local hasMutations = text ~= ""
		mutations.Text = text
		mutations.Visible = hasMutations
		-- Z mutacjami tabliczka jest wyższa i szersza (nazwy w kolorach u góry)
		gui.Size = if hasMutations then UDim2.fromOffset(118, 60) else UDim2.fromOffset(100, 42)
		value.Position = UDim2.fromOffset(4, if hasMutations then 21 else 3)
		local amount = marker:GetAttribute("Value")
		local rate = marker:GetAttribute("Rate")
		value.Text = string.format(
			'💰 %s\n<font color="%s">+%s/min</font>',
			if typeof(amount) == "number" then formatCoins(amount) else "…",
			RATE_COLOR,
			if typeof(rate) == "number" then formatRate(rate) else "…"
		)
	end
	local entry: Label = { gui = gui, mutations = mutations, value = value, info = info, refresh = refresh }
	refresh()
	connections[marker] = marker.AttributeChanged:Connect(function(name)
		if name == "Value" or name == "Rate" then
			refresh()
		end
	end)
	gui.Parent = playerGui
	return entry
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

local function added(marker: Instance, kind: Kind)
	if not marker:IsA("Model") or ids[marker] then
		return
	end
	-- Przy StreamingEnabled część znacznika może dojść chwilę później
	if not (marker.PrimaryPart or marker:FindFirstChildWhichIsA("BasePart")) then
		marker:WaitForChild("Root", 10)
		if not marker.Parent or ids[marker] then
			return
		end
	end
	local info = infoOf(marker)
	local root = marker.PrimaryPart or marker:FindFirstChildWhichIsA("BasePart")
	if not info or not root then
		return
	end
	ids[marker] = info.id
	MushroomView.add({ info }, {
		decorative = true,
		parent = marker :: Instance,
		grow = marker:GetAttribute("Fresh") == true,
		fit = kind.fit,
	})
	local label = if kind.garden then gardenLabel(marker, root, info) else hoardLabel(root, info)
	if label then
		labels[marker] = label
	end
end

local function removed(marker: Instance)
	local entry = labels[marker]
	if entry then
		labels[marker] = nil
		entry.gui:Destroy()
	end
	local connection = connections[marker]
	if connection then
		connections[marker] = nil
		connection:Disconnect()
	end
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
