--!strict
-- Przyciski w rzędzie obok przełącznika języka (pod panelem monet), w tym samym „cukierkowym” stylu:
--   🎵 muzyka wł./wył., 🔊 dźwięki wł./wył. (zapisywane w danych gracza), 👥 Zaproś znajomych.
-- Wyłączony przycisk robi się czerwony i dostaje skreślenie.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
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

local HEIGHT = 30
local GAP = 6
local LANGUAGE_WIDTH = 70 -- przycisk języka z Hud
local ON_COLOR = UiKit.COLORS.wood
local OFF_COLOR = UiKit.COLORS.red

type Entry = { button: TextButton, width: number }
local entries: { Entry } = {}

local function layout()
	local scale = UiScale.get()
	-- Ten sam rachunek co w Hud.layout: panel monet (80) + odstęp, potem rząd języka
	local y = 8 + math.floor(80 * scale) + 8
	local x = 12 + math.floor((LANGUAGE_WIDTH + GAP) * scale)
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
end

local function makeButton(name: string, width: number, color: Color3, icon: string): (TextButton, GuiObject)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.fromOffset(width, HEIGHT)
	button.Text = ""
	button.Font = Enum.Font.FredokaOne
	button.TextSize = 18
	button.TextColor3 = Color3.fromRGB(255, 252, 240)
	button.TextXAlignment = Enum.TextXAlignment.Right
	button.Parent = gui
	UiKit.button(button, color, { gloss = true })
	local image = UiKit.icon(icon, button, UDim2.fromOffset(24, 24), UDim2.new(0, if width <= 44 then width / 2 else 5, 0.5, 0), Vector2.new(if width <= 44 then 0.5 else 0, 0.5))
	table.insert(entries, { button = button, width = width })
	return button, image
end

-- Przełącznik: kolor i skreślenie według stanu
local function toggle(name: string, icon: string, key: string, apply: (boolean) -> ())
	local button, image = makeButton(name, 40, ON_COLOR, icon)
	local slash = Instance.new("Frame")
	slash.Name = "Slash"
	slash.AnchorPoint = Vector2.new(0.5, 0.5)
	slash.Position = UDim2.fromScale(0.5, 0.5)
	slash.Size = UDim2.fromOffset(4, 28)
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
	local on = true
	local function render()
		apply(on)
		UiKit.recolor(button, if on then ON_COLOR else OFF_COLOR)
		slash.Visible = not on
		UiKit.setIconTransparency(image, if on then 0 else 0.35)
	end
	button.Activated:Connect(function()
		on = not on
		render()
		SaveSettings:FireServer(key, on)
	end)
	-- Zapisane ustawienie przychodzi od serwera jako atrybut gracza
	local attribute = if key == "music" then "MusicOn" else "SfxOn"
	local function fromServer()
		local value = player:GetAttribute(attribute)
		if typeof(value) == "boolean" and value ~= on then
			on = value
			render()
		end
	end
	player:GetAttributeChangedSignal(attribute):Connect(fromServer)
	fromServer()
end

toggle("Music", "music", "music", Audio.setMusicOn)
toggle("Sounds", "sound", "sfx", Audio.setSfxOn)

-- Zaproś znajomych (okno zaproszeń Robloxa). Chowa się, gdy Roblox nie pozwala zapraszać.
local invite = makeButton("Invite", 108, UiKit.COLORS.green, "invite")
local invitePadding = Instance.new("UIPadding")
invitePadding.PaddingRight = UDim.new(0, 9)
invitePadding.Parent = invite
local function renderInvite()
	invite.Text = Localize.t("HUD_INVITE")
end
renderInvite()
Localize.onChanged(renderInvite)

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
task.spawn(function()
	local ok, can = callSocial({ "CanSendGameInviteAsync" }, player)
	invite.Visible = not ok or can == true
	layout()
end)

UiScale.onChanged(layout)
layout()

return SettingsButtons
