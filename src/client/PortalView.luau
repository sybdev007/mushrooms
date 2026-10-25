--!strict
-- Skróty na Placu Portali widzą wszyscy, ale działają tylko dla tych, którzy już raz doszli
-- do portalu danego świata. Dla reszty wir jest szary i przygaszony, z kłódką nad łukiem.
-- Wir ma atrybuty World ("cave", "swamp") i OpenColor (kolor otwartego portalu).

local CollectionService = game:GetService("CollectionService")

local PortalView = {}

local TAG = "ShortcutSwirl"
local DEFAULT_OPEN = Color3.fromRGB(160, 90, 255)
local LOCKED_COLOR = Color3.fromRGB(70, 66, 80)

local unlockedWorlds: { [string]: boolean } = {}

local function isOpen(swirl: Instance): boolean
	local world = swirl:GetAttribute("World")
	return unlockedWorlds[if typeof(world) == "string" then world else "cave"] == true
end

local function apply(swirl: Instance)
	if not swirl:IsA("BasePart") then
		return
	end
	local open = isOpen(swirl)
	local openColor = swirl:GetAttribute("OpenColor")
	local color = if open then (if typeof(openColor) == "Color3" then openColor else DEFAULT_OPEN) else LOCKED_COLOR
	-- Wir składa się z prostokąta i pasków łuku (dzieci), barwimy wszystko razem
	local parts: { BasePart } = { swirl }
	for _, child in swirl:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(parts, child)
		end
	end
	for _, part in parts do
		part.Color = color
		part.Transparency = if open then 0.35 else 0.55
	end
	local light = swirl:FindFirstChildOfClass("PointLight")
	if light then
		light.Color = color
		light.Brightness = if open then 2 else 0.3
	end
	local emitter = swirl:FindFirstChildOfClass("ParticleEmitter")
	if emitter then
		emitter.Enabled = open
	end

	local lock = swirl:FindFirstChild("Lock")
	if not open and not lock then
		local gui = Instance.new("BillboardGui")
		gui.Name = "Lock"
		gui.Size = UDim2.fromOffset(70, 70)
		gui.LightInfluence = 0
		gui.MaxDistance = 120
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = "🔒"
		label.TextScaled = true
		label.Parent = gui
		gui.Parent = swirl
	elseif open and lock then
		lock:Destroy()
	end
end

-- worlds: { cave = true/false, swamp = true/false }
function PortalView.setUnlocked(worlds: { [string]: boolean })
	local changed = false
	for world, value in worlds do
		if unlockedWorlds[world] ~= value then
			unlockedWorlds[world] = value
			changed = true
		end
	end
	if changed then
		for _, swirl in CollectionService:GetTagged(TAG) do
			apply(swirl)
		end
	end
end

function PortalView.start()
	for _, swirl in CollectionService:GetTagged(TAG) do
		apply(swirl)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(apply)
	-- Atrybuty mogą dojść po samym wirze (replikacja), wtedy barwimy jeszcze raz
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(swirl)
		swirl:GetAttributeChangedSignal("World"):Connect(function()
			apply(swirl)
		end)
	end)
end

return PortalView
