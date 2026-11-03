--!strict
-- Ogłoszenia admina (AnnounceService): na środku ekranu u wszystkich graczy na każdym serwerze.
-- Spokojna karta na lekko szarym, półprzezroczystym tle: po lewej miniaturka autora od pasa w górę
-- (jego awatar z Robloxa), po prawej imię i tekst. Bez promieni i błysków: wjeżdża, wisi, znika.
-- Kolejne ogłoszenia czekają w kolejce.
-- openInput(): okienko dla dewelopera z polem tekstowym (panel DEV → „📢 Ogłoszenie”).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local Localize = require(script.Parent.Localize)
local PanelKit = require(script.Parent.PanelKit)
local UiFx = require(script.Parent.UiFx)
local UiKit = require(script.Parent.UiKit)
local UiScale = require(script.Parent.UiScale)

local AnnounceView = {}

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local HOLD_SECONDS = 7
local MAX_LENGTH = 140

-- ===== Karta na środku ekranu =====

local gui = Instance.new("ScreenGui")
gui.Name = "Announcement"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 20
gui.Enabled = false
gui.Parent = playerGui

local CARD_Y = 0.36
local CARD_SCALE = 0.5 -- cała karta o połowę mniejsza niż projekt 640×150 (Tom, 3.11)
local card = Instance.new("CanvasGroup")
card.Name = "Card"
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.Position = UDim2.fromScale(0.5, CARD_Y)
card.Size = UDim2.fromOffset(640, 150)
card.BackgroundColor3 = Color3.fromRGB(64, 64, 70)
card.BackgroundTransparency = 0.22
card.GroupTransparency = 1
card.Parent = gui
PanelKit.corner(card, UDim.new(0, 20))
local cardStroke = Instance.new("UIStroke")
cardStroke.Color = Color3.fromRGB(200, 200, 208)
cardStroke.Transparency = 0.55
cardStroke.Thickness = 2
cardStroke.Parent = card
local scale = Instance.new("UIScale")
scale.Parent = card

-- Miniaturka autora od pasa w górę (AvatarBust z Robloxa) w jasnoszarym kółku
local portraitBack = Instance.new("Frame")
portraitBack.Name = "PortraitBack"
portraitBack.AnchorPoint = Vector2.new(0, 0.5)
portraitBack.Position = UDim2.new(0, 16, 0.5, 0)
portraitBack.Size = UDim2.fromOffset(118, 118)
portraitBack.BackgroundColor3 = Color3.fromRGB(150, 150, 158)
portraitBack.BackgroundTransparency = 0.35
portraitBack.Parent = card
PanelKit.corner(portraitBack, UDim.new(1, 0))
local portrait = Instance.new("ImageLabel")
portrait.Name = "Portrait"
portrait.BackgroundTransparency = 1
portrait.Size = UDim2.fromScale(1, 1)
portrait.ScaleType = Enum.ScaleType.Fit
portrait.Parent = portraitBack
PanelKit.corner(portrait, UDim.new(1, 0))

local name = PanelKit.label(card, "Name", UDim2.new(1, -170, 0, 24), UDim2.fromOffset(150, 16), 20, Color3.fromRGB(215, 215, 222), PanelKit.BODY_FONT)
name.TextXAlignment = Enum.TextXAlignment.Left
local message = PanelKit.label(card, "Message", UDim2.new(1, -170, 1, -54), UDim2.fromOffset(150, 44), 32, Color3.new(1, 1, 1), PanelKit.TITLE_FONT)
message.TextWrapped = true
message.RichText = false
message.TextXAlignment = Enum.TextXAlignment.Left
message.TextYAlignment = Enum.TextYAlignment.Top
UiKit.outline(message, 1.5, Color3.fromRGB(30, 30, 34))

type Item = { text: string, from: string, userId: number }
local queue: { Item } = {}
local showing = false
local thumbnails: { [number]: string } = {}

-- Miniaturka z Robloxa (raz na autora); bez niej sam szary krąg
local function portraitOf(userId: number): string
	local cached = thumbnails[userId]
	if cached then
		return cached
	end
	if userId <= 0 then
		return ""
	end
	local ok, image = pcall(function()
		return (Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.AvatarBust, Enum.ThumbnailSize.Size180x180))
	end)
	local url = if ok and typeof(image) == "string" then image else ""
	thumbnails[userId] = url
	return url
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
	portrait.Image = portraitOf(item.userId)
	name.Text = Localize.t("ANNOUNCE_HEADER", { item.from })
	message.Text = item.text
	scale.Scale = UiScale.get() * CARD_SCALE
	gui.Enabled = true
	-- Wjazd: z lekkim przesunięciem w górę i rozjaśnieniem
	card.Position = UDim2.new(0.5, 0, CARD_Y, 12)
	card.GroupTransparency = 1
	local info = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(card, info, { GroupTransparency = 0, Position = UDim2.fromScale(0.5, CARD_Y) }):Play()
	UiFx.sound("ping", 0.5, 0.85)
	task.delay(HOLD_SECONDS, function()
		local out = TweenService:Create(card, TweenInfo.new(0.5), { GroupTransparency = 1 })
		out:Play()
		out.Completed:Wait()
		showing = false
		showNext()
	end)
end

Remotes.get("AnnounceShow").OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" or typeof(payload.text) ~= "string" then
		return
	end
	table.insert(queue, {
		text = payload.text,
		from = if typeof(payload.from) == "string" then payload.from else "Admin",
		userId = if typeof(payload.userId) == "number" then payload.userId else 0,
	})
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
