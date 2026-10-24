--!strict
-- Napisy na szyldach (bramy stref, chatka). Serwer oznacza szyld tagiem "LocalizedSign"
-- i atrybutem SignKey, a klient dokłada tekst w języku gracza i podmienia go po zmianie języka.

local CollectionService = game:GetService("CollectionService")

local Localize = require(script.Parent.Localize)

local Signs = {}

local TAG = "LocalizedSign"
local labels: { [Instance]: TextLabel } = {}

local function decorate(part: Instance)
	if not part:IsA("BasePart") or labels[part] then
		return
	end
	local key = part:GetAttribute("SignKey")
	if typeof(key) ~= "string" then
		return
	end
	local faceName = part:GetAttribute("SignFace")
	local face = Enum.NormalId.Front
	if typeof(faceName) == "string" then
		for _, item in Enum.NormalId:GetEnumItems() do
			if item.Name == faceName then
				face = item
			end
		end
	end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignText"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0.25
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -20, 1, -12)
	label.Position = UDim2.new(0, 10, 0, 6)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(255, 236, 190)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = Localize.t(key)
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(60, 36, 20)
	stroke.Parent = label

	labels[part] = label
	part.Destroying:Connect(function()
		labels[part] = nil
	end)
end

function Signs.start()
	for _, part in CollectionService:GetTagged(TAG) do
		decorate(part)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(decorate)
	-- Przy streamingu szyld może zniknąć i wrócić: wtedy dostanie nowy napis
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(part)
		labels[part] = nil
	end)
	Localize.onChanged(function()
		for part, label in labels do
			local key = part:GetAttribute("SignKey")
			if typeof(key) == "string" then
				label.Text = Localize.t(key)
			end
		end
	end)
end

return Signs
