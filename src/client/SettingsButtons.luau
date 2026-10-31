--!strict
-- Przyciski w rzędzie obok przełącznika języka (pod panelem monet), w tym samym „cukierkowym” stylu:
--   🎵 muzyka, 🔊 dźwięki, 👥 Zaproś znajomych.
-- Rząd jest wyższy niż reszta HUD i na telefonie zmniejsza się mniej (UiScale.row), żeby trafić palcem.
-- 🎵 i 🔊 otwierają panelik z suwakami głośności (muzyka, dźwięki). Głośność zapisuje się w danych
-- gracza (SaveSettings), a wraca jako atrybuty MusicVolume / SfxVolume (i MusicOn / SfxOn).
-- Wyciszone (suwak na zero) = przycisk czerwony ze skreśleniem.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Audio = require(script.Parent.Audio)
local Localize = require(script.Parent.Localize)
local UiKit = require(script.Parent.UiKit)
local UiScale = require(script.Parent.UiScale)

local SettingsButtons = {}

local player = Players.LocalPlayer
local SaveSettings = Remotes.get("SaveSettings")

local gui = Instance.new("ScreenGui")
gui.Name = "SettingsButtons"
gui.ResetOnSpawn = false
gui.DisplayOrder = 4
gui.Parent = player:WaitForChild("PlayerGui")

local HEIGHT = UiScale.ROW_HEIGHT
local GAP = 6
local LANGUAGE_WIDTH = 88 -- przycisk języka z Hud (widoczny tylko dla deweloperów)
local languageShown = false
local TOGGLE_WIDTH = 50
local ICON = 30
local ON_COLOR = UiKit.COLORS.wood
local OFF_COLOR = UiKit.COLORS.red
local CREAM = Color3.fromRGB(255, 244, 222)
local PANEL_BG = Color3.fromRGB(46, 32, 22)
local PANEL_STROKE = Color3.fromRGB(200, 146, 74)

type Entry = { button: TextButton, width: number }
local entries: { Entry } = {}

local function makeButton(name: string, width: number, color: Color3, icon: string): (TextButton, GuiObject)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.fromOffset(width, HEIGHT)
	button.Text = ""
	button.Font = Enum.Font.FredokaOne
	button.TextSize = 22
	button.TextColor3 = Color3.fromRGB(255, 252, 240)
	button.TextXAlignment = Enum.TextXAlignment.Right
	button.Parent = gui
	UiKit.button(button, color, { gloss = true })
	local small = width <= TOGGLE_WIDTH + 4
	local image = UiKit.icon(icon, button, UDim2.fromOffset(ICON, ICON), UDim2.new(0, if small then width / 2 else 6, 0.5, 0), Vector2.new(if small then 0.5 else 0, 0.5))
	table.insert(entries, { button = button, width = width })
	return button, image
end

-- ===== Panel z suwakami =====

local panel = Instance.new("Frame")
panel.Name = "AudioPanel"
panel.Size = UDim2.fromOffset(280, 132)
panel.BackgroundColor3 = PANEL_BG
panel.Visible = false
panel.Active = true -- dotyk na panelu nie obraca kamery
panel.ZIndex = 10
panel.Parent = gui
local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 12)
panelCorner.Parent = panel
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = PANEL_STROKE
panelStroke.Thickness = 2
panelStroke.Parent = panel
local panelScale = Instance.new("UIScale")
panelScale.Parent = panel

type Slider = {
	value: number,
	set: (value: number) -> (),
}

local function slider(order: number, icon: string, textKey: string, color: Color3, onChange: (number) -> (), onCommit: (number) -> ()): Slider
	local top = 10 + (order - 1) * 60
	-- ZIndex nad tłem panelu (ten ScreenGui ma globalne ZIndex, więc dziecko nie wychodzi samo na wierzch)
	UiKit.icon(icon, panel, UDim2.fromOffset(26, 26), UDim2.fromOffset(14, top + 13), Vector2.new(0, 0.5)).ZIndex = 11
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(46, top)
	title.Size = UDim2.fromOffset(150, 26)
	title.Font = Enum.Font.FredokaOne
	title.TextSize = 20
	title.TextColor3 = CREAM
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 11
	title.Parent = panel
	UiKit.outline(title, 2)
	local percent = Instance.new("TextLabel")
	percent.Name = "Percent"
	percent.BackgroundTransparency = 1
	percent.Position = UDim2.new(1, -74, 0, top)
	percent.Size = UDim2.fromOffset(60, 26)
	percent.Font = Enum.Font.FredokaOne
	percent.TextSize = 20
	percent.TextColor3 = color
	percent.TextXAlignment = Enum.TextXAlignment.Right
	percent.ZIndex = 11
	percent.Parent = panel
	UiKit.outline(percent, 2)

	-- Tor suwaka; strefa dotyku jest wyższa niż sam tor, żeby łatwo było go złapać
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.BackgroundTransparency = 1
	hit.Position = UDim2.fromOffset(14, top + 28)
	hit.Size = UDim2.new(1, -28, 0, 30)
	hit.ZIndex = 12
	hit.Parent = panel
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.new(0, 10, 0.5, 0)
	track.Size = UDim2.new(1, -20, 0, 12)
	track.BackgroundColor3 = Color3.fromRGB(22, 14, 10)
	track.ZIndex = 11
	track.Parent = hit
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track
	local trackStroke = Instance.new("UIStroke")
	trackStroke.Color = UiKit.OUTLINE
	trackStroke.Thickness = 2
	trackStroke.Parent = track
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = color
	fill.Size = UDim2.fromScale(1, 1)
	fill.ZIndex = 12
	fill.Parent = track
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill
	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(26, 26)
	knob.BackgroundColor3 = CREAM
	knob.ZIndex = 13
	knob.Parent = track
	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(1, 0)
	knobCorner.Parent = knob
	local knobStroke = Instance.new("UIStroke")
	knobStroke.Color = UiKit.OUTLINE
	knobStroke.Thickness = 2.5
	knobStroke.Parent = knob

	local self: Slider = { value = 1, set = function() end }
	local function render()
		fill.Size = UDim2.fromScale(self.value, 1)
		fill.Visible = self.value > 0
		knob.Position = UDim2.fromScale(self.value, 0.5)
		percent.Text = string.format("%d%%", math.floor(self.value * 100 + 0.5))
		title.Text = Localize.t(textKey)
	end
	self.set = function(value: number)
		self.value = math.clamp(value, 0, 1)
		render()
	end
	Localize.onChanged(render)

	-- Przeciąganie myszą albo palcem (dotyk śledzimy po tym samym obiekcie wejścia)
	local dragging: InputObject? = nil
	local function fromX(x: number)
		local width = track.AbsoluteSize.X
		if width <= 0 then
			return
		end
		local value = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
		value = math.floor(value * 20 + 0.5) / 20
		if value ~= self.value then
			self.set(value)
			onChange(value)
		end
	end
	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = input
			fromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		local current = dragging
		if not current then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement and current.UserInputType == Enum.UserInputType.MouseButton1 then
			fromX(input.Position.X)
		elseif input == current then
			fromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local current = dragging
		if current and (input == current or (input.UserInputType == Enum.UserInputType.MouseButton1 and current.UserInputType == Enum.UserInputType.MouseButton1)) then
			dragging = nil
			onCommit(self.value)
		end
	end)
	render()
	return self
end

-- ===== Przyciski =====

-- Stan przycisku: czerwony ze skreśleniem, gdy wyciszone
type Toggle = { button: TextButton, render: (muted: boolean) -> () }
local function audioButton(name: string, icon: string): Toggle
	local button, image = makeButton(name, TOGGLE_WIDTH, ON_COLOR, icon)
	local slash = Instance.new("Frame")
	slash.Name = "Slash"
	slash.AnchorPoint = Vector2.new(0.5, 0.5)
	slash.Position = UDim2.fromScale(0.5, 0.5)
	slash.Size = UDim2.fromOffset(4, 34)
	slash.Rotation = 45
	slash.BackgroundColor3 = Color3.fromRGB(255, 252, 240)
	slash.BorderSizePixel = 0
	slash.ZIndex = 5
	slash.Visible = false
	slash.Parent = button
	local slashStroke = Instance.new("UIStroke")
	slashStroke.Color = UiKit.OUTLINE
	slashStroke.Thickness = 1.5
	slashStroke.Parent = slash
	return {
		button = button,
		render = function(muted: boolean)
			UiKit.recolor(button, if muted then OFF_COLOR else ON_COLOR)
			slash.Visible = muted
			UiKit.setIconTransparency(image, if muted then 0.35 else 0)
		end,
	}
end

-- Jeden przycisk dźwięku: otwiera panel z suwakami muzyki i dźwięków. Czerwony, gdy oba wyciszone.
local soundButton = audioButton("Sounds", "sound")
local musicLevel, soundLevel = 1, 1
local function renderAudio()
	soundButton.render(musicLevel <= 0 and soundLevel <= 0)
end

local musicSlider = slider(1, "music", "SET_MUSIC", Color3.fromRGB(255, 196, 80), function(value)
	Audio.setMusicLevel(value)
	musicLevel = value
	renderAudio()
end, function(value)
	SaveSettings:FireServer("musicVolume", value)
end)
local soundSlider = slider(2, "sound", "SET_SOUNDS", Color3.fromRGB(140, 226, 110), function(value)
	Audio.setSfxLevel(value)
	soundLevel = value
	renderAudio()
end, function(value)
	SaveSettings:FireServer("sfxVolume", value)
	Audio.play("click") -- próbka głośności dźwięków
end)

-- Zapisana głośność przychodzi od serwera jako atrybuty gracza
local function level(volumeName: string, onName: string): number
	local volume = player:GetAttribute(volumeName)
	local on = player:GetAttribute(onName)
	if on == false then
		return 0
	end
	return if typeof(volume) == "number" then math.clamp(volume, 0, 1) else 1
end
local function fromServer()
	local music = level("MusicVolume", "MusicOn")
	local sounds = level("SfxVolume", "SfxOn")
	musicSlider.set(music)
	soundSlider.set(sounds)
	Audio.setMusicLevel(music)
	Audio.setSfxLevel(sounds)
	musicLevel, soundLevel = music, sounds
	renderAudio()
end
for _, name in { "MusicVolume", "MusicOn", "SfxVolume", "SfxOn" } do
	player:GetAttributeChangedSignal(name):Connect(fromServer)
end
fromServer()

-- Zaproś znajomych (okno zaproszeń Robloxa). Chowa się, gdy Roblox nie pozwala zapraszać.
local invite = makeButton("Invite", 136, UiKit.COLORS.green, "invite")
local invitePadding = Instance.new("UIPadding")
invitePadding.PaddingRight = UDim.new(0, 11)
invitePadding.Parent = invite
local function renderInvite()
	invite.Text = Localize.t("HUD_INVITE")
end
renderInvite()
Localize.onChanged(renderInvite)

-- Plakietka „+10% 🍀”: znajomy na tym samym serwerze daje obu graczom więcej szczęścia
-- (CommunityService). Wisi pod dolnym rogiem przycisku, bo rząd stoi przy górnej krawędzi ekranu.
do
	local badge = Instance.new("TextLabel")
	badge.Name = "Badge"
	badge.AutomaticSize = Enum.AutomaticSize.X
	badge.Size = UDim2.fromOffset(20, 22)
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.Position = UDim2.new(1, 8, 1, -4) -- prawie cała pod przyciskiem, nie zasłania napisu
	badge.BackgroundColor3 = Color3.fromRGB(64, 186, 78)
	badge.Font = Enum.Font.FredokaOne
	badge.TextSize = 15
	badge.TextColor3 = Color3.new(1, 1, 1)
	badge.Text = string.format("+%d%% 🍀", math.floor((Config.Community.friendLuck - 1) * 100 + 0.5))
	badge.ZIndex = 5
	badge.Parent = invite
	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(1, 0)
	badgeCorner.Parent = badge
	local badgeStroke = Instance.new("UIStroke")
	badgeStroke.Color = Color3.new(1, 1, 1)
	badgeStroke.Thickness = 2
	badgeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	badgeStroke.Parent = badge
	local badgePad = Instance.new("UIPadding")
	badgePad.PaddingLeft = UDim.new(0, 7)
	badgePad.PaddingRight = UDim.new(0, 7)
	badgePad.Parent = badge
end

local function callSocial(names: { string }, ...: any): (boolean, any)
	for _, name in names do
		local ok, method = pcall(function()
			return (SocialService :: any)[name]
		end)
		if ok and method then
			return pcall(method, SocialService, ...)
		end
	end
	return false, nil
end

invite.Activated:Connect(function()
	local ok, can = callSocial({ "CanSendGameInviteAsync" }, player)
	if ok and can then
		callSocial({ "PromptGameInvite", "PromptGameInviteAsync" }, player)
	end
end)

-- ===== Układ =====

local function layout()
	local scale = UiScale.row()
	local y = UiScale.rowTop()
	local x = 12 + (if languageShown then math.floor((LANGUAGE_WIDTH + GAP) * scale) else 0)
	for _, entry in entries do
		if entry.button.Visible then
			local uiScale = entry.button:FindFirstChildOfClass("UIScale")
			if uiScale then
				uiScale:SetAttribute("Base", scale)
				uiScale.Scale = scale
			end
			entry.button.Position = UDim2.fromOffset(x, y)
			x += math.floor((entry.width + GAP) * scale)
		end
	end
	-- Panel pod rzędem, od lewej krawędzi przycisku dźwięku
	panelScale.Scale = scale
	panel.Position = UDim2.fromOffset(soundButton.button.Position.X.Offset, UiScale.rowBottom() + 8)
end

local function setOpen(open: boolean)
	panel.Visible = open
	if open then
		layout()
	end
end
soundButton.button.Activated:Connect(function()
	setOpen(not panel.Visible)
end)

-- Klik albo dotyk poza panelem i przyciskami dźwięku zamyka panel
local function inside(object: GuiObject, position: Vector3): boolean
	local at, size = object.AbsolutePosition, object.AbsoluteSize
	return position.X >= at.X and position.X <= at.X + size.X and position.Y >= at.Y and position.Y <= at.Y + size.Y
end
UserInputService.InputBegan:Connect(function(input)
	if not panel.Visible then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	if inside(panel, input.Position) or inside(soundButton.button, input.Position) then
		return
	end
	setOpen(false)
end)

task.spawn(function()
	local ok, can = callSocial({ "CanSendGameInviteAsync" }, player)
	invite.Visible = not ok or can == true
	layout()
end)

UiScale.onChanged(layout)
layout()

-- Deweloper ma przed tymi przyciskami przełącznik języka (Hud), więc rząd przesuwa się w prawo
function SettingsButtons.setDev(enabled: boolean)
	if languageShown ~= enabled then
		languageShown = enabled
		layout()
	end
end

return SettingsButtons
