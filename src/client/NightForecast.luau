--!strict
-- Prognoza nocy: okienko pod paskiem strefy (klik w pasek z zegarem nocy, przycisk 🔮 obok albo klawisz N).
-- Noce liczymy z zegara (Shared/Cycle), więc klient zna każdą przyszłą noc, tak samo jak serwer:
--   teraz: zdarzenie tej nocy, ile zostało i co robi (Cycle.effects); o świcie „las odrasta”,
--   najbliższy Krwawy księżyc: godzina według zegara gracza i za ile,
--   5 następnych nocy z godziną startu i działaniem.
-- Nic nie idzie przez sieć (poza czasem serwera: Workspace:GetServerTimeNow).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Cycle = require(Shared:WaitForChild("Cycle"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Hud = require(script.Parent.Hud)
local Localize = require(script.Parent.Localize)
local PanelKit = require(script.Parent.PanelKit)
local UiKit = require(script.Parent.UiKit)
local UiScale = require(script.Parent.UiScale)

local NightForecast = {}

local ROWS = 5
local RARE = "blood_moon"
local WIDTH = 380
local ROW_H = 42 -- dwie linijki: godzina i nazwa, pod spodem działanie

local gui = Instance.new("ScreenGui")
gui.Name = "NightForecast"
gui.ResetOnSpawn = false
gui.DisplayOrder = 12
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0)
panel.Position = UDim2.new(0.5, 0, 0, 108)
panel.Size = UDim2.fromOffset(WIDTH, 128 + ROWS * ROW_H)
panel.BackgroundColor3 = Color3.fromRGB(22, 16, 38)
panel.BackgroundTransparency = 0.06
panel.Visible = false
panel.Parent = gui
PanelKit.corner(panel, UDim.new(0, 16))
PanelKit.stroke(panel, Color3.fromRGB(150, 120, 230), 2.5)
local panelScale = Instance.new("UIScale")
panelScale.Parent = panel

local title = PanelKit.label(panel, "Title", UDim2.new(1, -60, 0, 24), UDim2.fromOffset(14, 8), 22, PanelKit.GOLD)
title.TextXAlignment = Enum.TextXAlignment.Left
UiKit.outline(title, 2)
local close = Instance.new("TextButton")
close.Name = "Close"
close.Size = UDim2.fromOffset(28, 28)
close.Position = UDim2.new(1, -36, 0, 7)
close.BackgroundColor3 = Color3.fromRGB(196, 44, 40)
close.Text = "X"
close.TextScaled = true
close.Font = PanelKit.TITLE_FONT
close.TextColor3 = Color3.new(1, 1, 1)
close.Parent = panel
PanelKit.corner(close, UDim.new(1, 0))
PanelKit.stroke(close, PanelKit.OUTLINE, 2)

local now1 = PanelKit.label(panel, "Now", UDim2.new(1, -28, 0, 22), UDim2.fromOffset(14, 38), 18)
now1.TextXAlignment = Enum.TextXAlignment.Left
local now2 = PanelKit.label(panel, "NowEffects", UDim2.new(1, -28, 0, 18), UDim2.fromOffset(14, 60), 15, PanelKit.MUTED, PanelKit.BODY_FONT)
now2.TextXAlignment = Enum.TextXAlignment.Left

local rareBox = Instance.new("Frame")
rareBox.Name = "Rare"
rareBox.Size = UDim2.new(1, -20, 0, 30)
rareBox.Position = UDim2.fromOffset(10, 86)
rareBox.BackgroundColor3 = Color3.fromRGB(110, 20, 30)
rareBox.BackgroundTransparency = 0.25
rareBox.Parent = panel
PanelKit.corner(rareBox, UDim.new(0, 10))
local rareText = PanelKit.label(rareBox, "Text", UDim2.new(1, -16, 1, -6), UDim2.fromOffset(8, 3), 16, Color3.fromRGB(255, 200, 200))
rareText.TextXAlignment = Enum.TextXAlignment.Left

type Row = { time: TextLabel, name: TextLabel, effects: TextLabel }
local rows: { Row } = {}
for i = 1, ROWS do
	local y = 122 + (i - 1) * ROW_H
	local time = PanelKit.label(panel, "Time" .. i, UDim2.fromOffset(100, 20), UDim2.fromOffset(14, y + 3), 16, PanelKit.MUTED, PanelKit.BODY_FONT)
	time.TextXAlignment = Enum.TextXAlignment.Left
	local name = PanelKit.label(panel, "Name" .. i, UDim2.new(1, -132, 0, 20), UDim2.fromOffset(118, y + 2), 17)
	name.TextXAlignment = Enum.TextXAlignment.Left
	local effects = PanelKit.label(panel, "Effects" .. i, UDim2.new(1, -132, 0, 16), UDim2.fromOffset(118, y + 22), 14, PanelKit.MUTED, PanelKit.BODY_FONT)
	effects.TextXAlignment = Enum.TextXAlignment.Left
	table.insert(rows, { time = time, name = name, effects = effects })
end

local function number(value: number): string
	local text = string.format("%g", value)
	return if Localize.getLocale() == "pl" then (string.gsub(text, "%.", ",")) else text
end

local function effectsText(event: any): string
	local parts = {}
	for _, effect in Cycle.effects(event) do
		table.insert(parts, Localize.t(effect.key, if effect.value then { number(effect.value) } else nil))
	end
	return table.concat(parts, " · ")
end

local function clock(seconds: number): string
	local total = math.max(0, math.floor(seconds))
	if total >= 3600 then
		return string.format("%d h %02d min", total // 3600, (total % 3600) // 60)
	end
	return string.format("%d:%02d", total // 60, total % 60)
end

-- Godzina startu według zegara gracza; inny dzień = „jutro” albo data
local function when(t: number, now: number): string
	local d = os.date("*t", math.floor(t)) :: any
	local today = os.date("*t", math.floor(now)) :: any
	local hm = string.format("%d:%02d", d.hour, d.min)
	if d.year == today.year and d.yday == today.yday then
		return hm
	end
	local tomorrow = os.date("*t", math.floor(now) + 86400) :: any
	if d.year == tomorrow.year and d.yday == tomorrow.yday then
		return Localize.t("FORECAST_TOMORROW", { hm })
	end
	return string.format("%d.%d %s", d.day, d.month, hm)
end

local function render()
	local now = Workspace:GetServerTimeNow()
	title.Text = "🔮 " .. Localize.t("FORECAST_TITLE")
	local phase = Cycle.at(now)
	if phase.phase == "night" then
		now1.Text = Localize.t("FORECAST_NOW", { phase.event.icon, Localize.t(phase.event.key), clock(phase.endsAt - now) })
		now2.Text = effectsText(phase.event)
	else
		now1.Text = Localize.t("FORECAST_DAWN", { clock(phase.endsAt - now) })
		now2.Text = Localize.t("FORECAST_DAWN_INFO")
	end
	local rare = Cycle.nextOf(now, RARE)
	if rare then
		rareText.Text = Localize.t("FORECAST_RARE", { rare.event.icon, Localize.t(rare.event.key), when(rare.startsAt, now), clock(rare.startsAt - now) })
	end
	rareBox.Visible = rare ~= nil
	for i, night in Cycle.upcoming(now, ROWS) do
		local row = rows[i]
		row.time.Text = when(night.startsAt, now)
		row.name.Text = night.event.icon .. " " .. Localize.t(night.event.key)
		row.name.TextColor3 = if night.event.id == RARE then Color3.fromRGB(255, 120, 120) else PanelKit.TEXT
		row.effects.Text = effectsText(night.event)
	end
end

-- ===== Podpowiedź: „tu jest prognoza” =====
-- Dopóki gracz ani razu nie otworzył prognozy (ustawienie forecastSeen w zapisie, atrybut gracza
-- ForecastSeen), przycisk 🔮 pulsuje, a obok co jakiś czas wyskakuje dymek: po wejściu do gry i o każdym
-- świcie, na HINT_SECONDS. W trakcie samouczka nic (NightForecast.update dostaje stan gracza).
local HINT_SECONDS = 12
local player = Players.LocalPlayer
local tutorialDone = false
local orbScale = Instance.new("UIScale")
local bubbleUntil = 0
local hintShownOnce = false

local function seen(): boolean
	return player:GetAttribute("ForecastSeen") == true
end

local function hintActive(): boolean
	-- Atrybut przychodzi z serwera po wczytaniu zapisu; zanim przyjdzie, nic nie pokazujemy
	return tutorialDone and player:GetAttribute("ForecastSeen") == false
end

local function showBubble()
	if hintActive() then
		bubbleUntil = os.clock() + HINT_SECONDS
	end
end

local function setOpen(open: boolean)
	panel.Visible = open
	if open then
		render()
		bubbleUntil = 0
		if not seen() then
			-- Pierwsze otwarcie: podpowiedź znika na zawsze (serwer zapisuje forecastSeen)
			player:SetAttribute("ForecastSeen", true)
			Remotes.get("SaveSettings"):FireServer("forecastSeen", true)
		end
	end
end

-- Stan gracza ze StateUpdate (Main.client): podpowiedź dopiero po samouczku
function NightForecast.update(state: any)
	local done = typeof(state) == "table" and typeof(state.tutorial) == "number" and state.tutorial >= Config.Tutorial.done
	if done and not tutorialDone then
		tutorialDone = true
		if not hintShownOnce then
			hintShownOnce = true
			task.delay(4, showBubble)
		end
	end
	tutorialDone = done
end

function NightForecast.toggle()
	setOpen(not panel.Visible)
end

function NightForecast.start()
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local function layout()
		local scale = UiScale.get()
		panelScale.Scale = scale
		panel.Position = UDim2.new(0.5, 0, 0, math.floor(108 * scale))
	end
	layout()
	UiScale.onChanged(layout)
	-- Klik w pasek z zegarem nocy albo w zapowiedź następnej nocy
	for _, pill in { Hud.zonePill(), Hud.forecastPill() } do
		local hit = Instance.new("TextButton")
		hit.Name = "ForecastHit"
		hit.Size = UDim2.fromScale(1, 1)
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.ZIndex = 10
		hit.Parent = pill
		hit.Activated:Connect(NightForecast.toggle)
	end
	-- Przycisk 🔮 tuż obok paska strefy (żeby było widać, że prognoza istnieje)
	local zone = Hud.zonePill()
	local orb = Instance.new("TextButton")
	orb.Name = "ForecastButton"
	orb.Size = UDim2.fromOffset(28, 28)
	orb.AnchorPoint = Vector2.new(0, 0)
	orb.Position = UDim2.new(1, 4, 0, 0)
	orb.BackgroundColor3 = Color3.fromRGB(70, 46, 120)
	orb.Text = "🔮"
	orb.TextScaled = true
	orb.Parent = zone
	PanelKit.corner(orb, UDim.new(1, 0))
	PanelKit.stroke(orb, PanelKit.OUTLINE, 2)
	orb.Activated:Connect(NightForecast.toggle)
	orbScale.Parent = orb
	-- Dymek z podpowiedzią po prawej stronie przycisku
	local tip = Instance.new("Frame")
	tip.Name = "ForecastHint"
	tip.Size = UDim2.fromOffset(250, 30)
	tip.Position = UDim2.new(1, 40, 0, -1)
	tip.BackgroundColor3 = Color3.fromRGB(70, 46, 120)
	tip.Visible = false
	tip.Parent = zone
	PanelKit.corner(tip, UDim.new(0, 10))
	PanelKit.stroke(tip, PanelKit.GOLD, 2)
	local tipText = PanelKit.label(tip, "Text", UDim2.new(1, -14, 1, -6), UDim2.fromOffset(7, 3), 16, PanelKit.TEXT)
	UiKit.outline(tipText, 1.5)
	local arrowTip = Instance.new("Frame")
	arrowTip.Name = "Arrow"
	arrowTip.Size = UDim2.fromOffset(12, 12)
	arrowTip.AnchorPoint = Vector2.new(0.5, 0.5)
	arrowTip.Position = UDim2.fromScale(0, 0.5)
	arrowTip.Rotation = 45
	arrowTip.BackgroundColor3 = Color3.fromRGB(70, 46, 120)
	arrowTip.BorderSizePixel = 0
	arrowTip.ZIndex = 0
	arrowTip.Parent = tip
	local function tipLabel()
		tipText.Text = "🔮 " .. Localize.t("FORECAST_HINT")
	end
	tipLabel()
	Localize.onChanged(tipLabel)
	-- Pulsowanie i dymek (co klatkę; tanie: dwie właściwości)
	local lastPhase: string? = nil
	RunService.RenderStepped:Connect(function()
		local active = hintActive()
		orbScale.Scale = if active then 1 + 0.12 * math.abs(math.sin(os.clock() * 3)) else 1
		tip.Visible = active and os.clock() < bubbleUntil and not panel.Visible
		-- O świcie dymek wraca (gracz stoi i czeka na odrost: dobry moment na prognozę)
		local phase = Cycle.at(Workspace:GetServerTimeNow()).phase
		if phase ~= lastPhase then
			if phase == "dawn" and lastPhase ~= nil then
				showBubble()
			end
			lastPhase = phase
		end
	end)
	close.Activated:Connect(function()
		setOpen(false)
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.N then
			NightForecast.toggle()
		end
	end)
	Localize.onChanged(function()
		if panel.Visible then
			render()
		end
	end)
	-- Odliczanie w otwartym okienku
	task.spawn(function()
		while true do
			task.wait(1)
			if panel.Visible then
				render()
			end
		end
	end)
end

return NightForecast
