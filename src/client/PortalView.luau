--!strict
-- Skrót do jaskini za chatką widzą wszyscy, ale działa tylko dla tych, którzy już raz
-- doszli do portalu za Leszym. Dla reszty wir jest szary i przygaszony, z kłódką nad łukiem.

local CollectionService = game:GetService("CollectionService")

local PortalView = {}

local TAG = "ShortcutSwirl"
local OPEN_COLOR = Color3.fromRGB(160, 90, 255)
local LOCKED_COLOR = Color3.fromRGB(70, 66, 80)

local unlocked = false

local function apply(swirl: Instance)
	if not swirl:IsA("BasePart") then
		return
	end
	swirl.Color = if unlocked then OPEN_COLOR else LOCKED_COLOR
	swirl.Transparency = if unlocked then 0.35 else 0.55
	local light = swirl:FindFirstChildOfClass("PointLight")
	if light then
		light.Color = swirl.Color
		light.Brightness = if unlocked then 2 else 0.3
	end
	local emitter = swirl:FindFirstChildOfClass("ParticleEmitter")
	if emitter then
		emitter.Enabled = unlocked
	end

	local lock = swirl:FindFirstChild("Lock")
	if not unlocked and not lock then
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
	elseif unlocked and lock then
		lock:Destroy()
	end
end

function PortalView.setUnlocked(value: boolean)
	if value == unlocked then
		return
	end
	unlocked = value
	for _, swirl in CollectionService:GetTagged(TAG) do
		apply(swirl)
	end
end

function PortalView.start()
	for _, swirl in CollectionService:GetTagged(TAG) do
		apply(swirl)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(apply)
end

return PortalView
