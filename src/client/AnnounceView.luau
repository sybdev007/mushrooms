--!strict
-- Ogłoszenia admina (AnnounceService): duży napis na środku ekranu u wszystkich graczy na każdym
-- serwerze, z podpisem, kto pisze. Kolejne ogłoszenia czekają w kolejce.
-- openInput(): okienko dla dewelopera z polem tekstowym (panel DEV → „📢 Ogłoszenie”).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local Localize = require(script.Parent.Localize)
local PanelKit = require(script.Parent.PanelKit)
local UiFx = require(script.Parent.UiFx)
local UiKit = require(script.Parent.UiKit)

local AnnounceView = {}

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local HOLD_SECONDS = 7
local MAX_LENGTH = 140

-- ===== Napis na środku ekranu =====

local gui = Instance.new("ScreenGui")
gui.Name = "Announcement"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 20
gui.Enabled = false
gui.Parent = playerGui

local band = Instance.new("Frame")
band.Name = "Band"
band.AnchorPoint = Vector2.new(0.5, 0.5)
band.Position = UDim2.fromScale(0.5, 0.42)
band.Size = UDim2.new(1, 0, 0, 170)
band.BackgroundColor3 = Color3.fromRGB(20, 10, 30)
band.BackgroundTransparency = 0.25
band.BorderSizePixel = 0
band.Parent = gui
local bandFade = Instance.new("UIGradient")
bandFade.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.18, 0),
	NumberSequenceKeypoint.new(0.82, 0),
	NumberSequenceKeypoint.new(1, 1),
})
bandFade.Parent = band
local scale = Instance.new("UIScale")
scale.Parent = band

local rays = UiFx.rays(band, { size = 420, color = Color3.fromRGB(255, 210, 110), count = 9, speed = 22, transparency = 0.55, zIndex = 1 })
rays.Position = UDim2.fromScale(0.5, 0.5)

local header = PanelKit.label(band, "Header", UDim2.new(0.8, 0, 0, 30), UDim2.new(0.1, 0, 0, 14), 26, PanelKit.GOLD, PanelKit.TITLE_FONT)
header.ZIndex = 3
UiKit.outline(header, 2.5)
UiFx.textGradient(header, Color3.fromRGB(255, 244, 190), Color3.fromRGB(255, 176, 40))

local message = PanelKit.label(band, "Message", UDim2.new(0.84, 0, 0, 104), UDim2.new(0.08, 0, 0, 50), 46, Color3.new(1, 1, 1), PanelKit.TITLE_FONT)
message.TextWrapped = true
message.RichText = false
message.ZIndex = 3
UiKit.outline(message, 3.5)
UiFx.textGradient(message, Color3.new(1, 1, 1), Color3.fromRGB(255, 226, 150))

type Item = { text: string, from: string }
local queue: { Item } = {}
local showing = false

local function setVisible(alpha: number)
	band.BackgroundTransparency = 1 - (1 - 0.25) * alpha
	header.TextTransparency = 1 - alpha
	message.TextTransparency = 1 - alpha
	for _, d in header:GetChildren() do
		if d:IsA("UIStroke") then
			d.Transparency = 1 - alpha
		end
	end
	for _, d in message:GetChildren() do
		if d:IsA("UIStroke") then
			d.Transparency = 1 - alpha
		end
	end
	rays.Visible = alpha > 0.05
end

local function showNext()
	if showing then
		return
	end
	local item = table.remove(queue, 1)
	if not item then
		gui.Enabled = false
		return
	end
	showing = true
	header.Text = Localize.t("ANNOUNCE_HEADER", { item.from })
	message.Text = item.text
	gui.Enabled = true
	setVisible(1)
	UiFx.popIn(scale, 1, 0.5)
	UiFx.sound("ping", 0.7, 0.9)
	task.delay(HOLD_SECONDS, function()
		-- Wygaszenie w 0,6 s
		local start = os.clock()
		while os.clock() - start < 0.6 do
			setVisible(1 - (os.clock() - start) / 0.6)
			task.wait()
		end
		setVisible(0)
		showing = false
		showNext()
	end)
end

Remotes.get("AnnounceShow").OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" or typeof(payload.text) ~= "string" then
		return
	end
	table.insert(queue, { text = payload.text, from = if typeof(payload.from) == "string" then payload.from else "Admin" })
	showNext()
end)

-- ===== Okienko do pisania (tylko deweloper) =====

local input = PanelKit.window({
	name = "AnnounceInput",
	parent = playerGui,
	width = 560,
	height = 240,
	ribbon = Color3.fromRGB(214, 90, 60),
	icon = "scroll",
	displayOrder = 12,
})
local box = Instance.new("TextBox")
box.Name = "Text"
box.Size = UDim2.new(1, -16, 0, 96)
box.Position = UDim2.fromOffset(8, 8)
box.BackgroundColor3 = Color3.fromRGB(40, 28, 20)
box.TextColor3 = PanelKit.TEXT
box.PlaceholderColor3 = PanelKit.MUTED
box.Font = PanelKit.BODY_FONT
box.TextSize = 20
box.TextWrapped = true
box.TextXAlignment = Enum.TextXAlignment.Left
box.TextYAlignment = Enum.TextYAlignment.Top
box.ClearTextOnFocus = false
box.MultiLine = false
box.Text = ""
box.Parent = input.content
PanelKit.corner(box, UDim.new(0, 12))
PanelKit.stroke(box, PanelKit.OUTLINE, 3)
local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0, 10)
pad.PaddingRight = UDim.new(0, 10)
pad.PaddingTop = UDim.new(0, 8)
pad.Parent = box
local counter = PanelKit.label(input.content, "Counter", UDim2.fromOffset(200, 20), UDim2.new(0, 10, 0, 112), 15, PanelKit.MUTED, PanelKit.BODY_FONT)
counter.TextXAlignment = Enum.TextXAlignment.Left
local send = Instance.new("TextButton")
send.Name = "Send"
send.Text = ""
send.Size = UDim2.fromOffset(220, 48)
send.AnchorPoint = Vector2.new(1, 0)
send.Position = UDim2.new(1, -8, 0, 110)
send.Parent = input.content
local sendStroke = UiKit.button(send, Color3.fromRGB(64, 190, 78), { gloss = true, radius = UDim.new(0, 14), stroke = 3 })
sendStroke.Color = PanelKit.OUTLINE
local sendText = PanelKit.label(send, "Text", UDim2.new(1, -12, 1, -10), UDim2.fromOffset(6, 5), 22, Color3.new(1, 1, 1), PanelKit.TITLE_FONT)
sendText.ZIndex = 4
UiKit.outline(sendText, 2.5)
UiFx.shine(send, 2.4)

local function refreshInput()
	input.title.Text = Localize.t("ANNOUNCE_TITLE")
	box.PlaceholderText = Localize.t("ANNOUNCE_PLACEHOLDER")
	sendText.Text = Localize.t("ANNOUNCE_SEND")
	counter.Text = string.format("%d / %d", utf8.len(box.Text) or 0, MAX_LENGTH)
end

box:GetPropertyChangedSignal("Text"):Connect(function()
	local length = utf8.len(box.Text) or 0
	if length > MAX_LENGTH then
		box.Text = string.sub(box.Text, 1, (utf8.offset(box.Text, MAX_LENGTH + 1) or (#box.Text + 1)) - 1)
	end
	counter.Text = string.format("%d / %d", math.min(length, MAX_LENGTH), MAX_LENGTH)
end)

local function submit()
	local text = box.Text
	if string.match(text, "%S") == nil then
		UiKit.shake(box)
		return
	end
	Remotes.get("AdminAnnounce"):FireServer(text)
	box.Text = ""
	input.setOpen(false)
end
send.Activated:Connect(submit)
box.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		submit()
	end
end)

function AnnounceView.openInput()
	refreshInput()
	input.setOpen(true)
	task.defer(function()
		box:CaptureFocus()
	end)
end

Localize.onChanged(refreshInput)

return AnnounceView
