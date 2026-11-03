--!strict
-- Baner „ADMIN ABUSE” u góry ekranu: wydarzenia włączone z panelu DEV dla całego serwera
-- (Config.AdminAbuse i Noc Dziadów). Serwer trzyma je jako atrybuty Workspace "Abuse_<id>" = koniec
-- (os.time); tu pokazujemy listę z odliczaniem, tęczowym napisem, złotą obwódką i paskami.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Localize = require(script.Parent.Localize)
local PanelKit = require(script.Parent.PanelKit)
local UiFx = require(script.Parent.UiFx)
local UiKit = require(script.Parent.UiKit)
local UiScale = require(script.Parent.UiScale)

local AdminEvents = {}

local gui = Instance.new("ScreenGui")
gui.Name = "AdminEvents"
gui.ResetOnSpawn = false
gui.DisplayOrder = 5
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

-- Nazwa wydarzenia po id (klucz tłumaczenia)
local NAMES: { [string]: string } = { spirit_night = "ABUSE_SPIRIT" }
for _, def in Config.AdminAbuse do
	NAMES[def.id] = def.key
end

local holder = Instance.new("Frame")
holder.Name = "Holder"
holder.BackgroundTransparency = 1
holder.AnchorPoint = Vector2.new(0.5, 0)
holder.Position = UDim2.new(0.5, 0, 0, 6)
holder.Size = UDim2.fromOffset(320, 0)
holder.AutomaticSize = Enum.AutomaticSize.Y
holder.Visible = false
holder.Parent = gui
local scale = Instance.new("UIScale")
scale.Parent = holder
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 4)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = holder

local header = PanelKit.label(holder, "Header", UDim2.fromOffset(260, 30), UDim2.new(), 26, Color3.new(1, 1, 1), PanelKit.TITLE_FONT)
header.LayoutOrder = 0
header.Text = "⚡ ADMIN ABUSE ⚡"
UiKit.outline(header, 3)
UiFx.rainbow(header, 0.4)
UiFx.pulse(header, 0.05, 1)

type Row = { frame: Frame, text: TextLabel }
local rows: { [string]: Row } = {}

local function formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function rowFor(id: string): Row
	local existing = rows[id]
	if existing then
		return existing
	end
	local frame = Instance.new("Frame")
	frame.Name = "Event_" .. id
	frame.Size = UDim2.fromOffset(300, 34)
	frame.BackgroundColor3 = Color3.fromRGB(70, 34, 110)
	frame.ClipsDescendants = true
	frame.LayoutOrder = 1
	frame.Parent = holder
	PanelKit.corner(frame, UDim.new(1, 0))
	UiFx.goldStroke(frame, 3)
	UiFx.stripes(frame, Color3.fromRGB(255, 220, 255), 0.85)
	local text = PanelKit.label(frame, "Text", UDim2.new(1, -20, 1, -8), UDim2.fromOffset(10, 4), 19, Color3.new(1, 1, 1), PanelKit.TITLE_FONT)
	text.ZIndex = 3
	UiKit.outline(text, 2)
	local row = { frame = frame, text = text }
	rows[id] = row
	local popScale = Instance.new("UIScale")
	popScale.Parent = frame
	UiFx.popIn(popScale, 1, 0.4)
	UiFx.sound("ping", 0.5, 1.3)
	return row
end

local function refresh()
	local now = os.time()
	local any = false
	local seen: { [string]: boolean } = {}
	for name, value in Workspace:GetAttributes() do
		if string.sub(name, 1, 6) == "Abuse_" and typeof(value) == "number" and value > now then
			local id = string.sub(name, 7)
			seen[id] = true
			any = true
			local row = rowFor(id)
			row.text.Text = Localize.t(NAMES[id] or id) .. "  ·  " .. formatTime(value - now)
		end
	end
	for id, row in rows do
		if not seen[id] then
			row.frame:Destroy()
			rows[id] = nil
		end
	end
	holder.Visible = any
	scale.Scale = UiScale.get()
end

Workspace.AttributeChanged:Connect(function(name)
	if string.sub(name, 1, 6) == "Abuse_" then
		refresh()
	end
end)
Localize.onChanged(refresh)
task.spawn(function()
	while true do
		refresh()
		task.wait(1)
	end
end)

return AdminEvents
