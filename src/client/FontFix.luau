--!strict
-- FredokaOne (główna czcionka gry) nie ma polskich liter ą ę ń ś ź ć: Roblox podstawia je z innej
-- czcionki i napis się rozjeżdża („Wi ę cej”). Gdy gra jest po polsku, każdy napis w FredokaOne
-- (okna, HUD, tabliczki w świecie) dostaje zaokrąglone Nunito Heavy, które ma wszystkie znaki.
-- Po angielsku wraca FredokaOne.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Localize = require(script.Parent.Localize)

local FontFix = {}

local POLISH_FONT = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Heavy)
local ORIGINAL_FONT = Font.fromEnum(Enum.Font.FredokaOne)

-- Napisy, które pierwotnie były w FredokaOne (słabe klucze: zniszczone napisy znikają same)
local tracked: { [GuiObject]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function polish(): boolean
	return Localize.getLocale() == "pl"
end

local function apply(label: GuiObject)
	local text = label :: any
	text.FontFace = if polish() then POLISH_FONT else ORIGINAL_FONT
end

local function consider(object: Instance)
	if not (object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox")) then
		return
	end
	-- Ekran wczytywania (ReplicatedFirst) sam dobiera czcionki i nie może zmienić ich w trakcie
	if object:FindFirstAncestor("LoadingScreen") then
		return
	end
	local text = object :: any
	local label = object :: GuiObject
	local function check()
		-- Kod może ustawić FredokaOne później (albo ponownie): wtedy podmieniamy jeszcze raz
		if text.Font == Enum.Font.FredokaOne then
			tracked[label] = true
			if polish() then
				apply(label)
			end
		end
	end
	object:GetPropertyChangedSignal("FontFace"):Connect(check)
	check()
end

local function watch(root: Instance)
	for _, d in root:GetDescendants() do
		consider(d)
	end
	root.DescendantAdded:Connect(consider)
end

function FontFix.start()
	local player = Players.LocalPlayer
	watch(player:WaitForChild("PlayerGui"))
	watch(Workspace)
	Localize.onChanged(function()
		for label in tracked do
			if label.Parent then
				apply(label)
			end
		end
	end)
end

return FontFix
