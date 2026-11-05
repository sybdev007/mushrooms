--!strict
-- Ekspedycja: karta z celem w prawym górnym rogu (jak lista zadań w hitowych grach), nad kolumną
-- przycisków (Ulepszenia na 42% wysokości), w skali HUD (UiScale), żeby na telefonie nic nie zasłaniała.
-- Przed zejściem: przypomnienie, gdzie jest szczelina, i ile czasu zostało.
-- W komorach: nazwa komory, kroki (zawał → cel → ognisko → lina albo Krypta) z odhaczaniem,
-- kto niesie znalezisko i czas do końca ekspedycji.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Delve = require(Shared:WaitForChild("Delve"))
local Localize = require(script.Parent.Localize)
local PanelKit = require(script.Parent.PanelKit)
local UiFx = require(script.Parent.UiFx)
local UiKit = require(script.Parent.UiKit)
local UiScale = require(script.Parent.UiScale)

local DelveHud = {}

local player = Players.LocalPlayer
local OUTLINE = PanelKit.OUTLINE
local DONE = Color3.fromRGB(140, 235, 110)
local TODO = PanelKit.TEXT
local NOW = PanelKit.GOLD

local gui = Instance.new("ScreenGui")
gui.Name = "DelveHud"
gui.ResetOnSpawn = false
gui.DisplayOrder = 3
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local card = Instance.new("Frame")
card.Name = "Card"
card.AnchorPoint = Vector2.new(1, 0)
card.Position = UDim2.new(1, -16, 0, 10)
card.Size = UDim2.fromOffset(300, 182)
card.BackgroundColor3 = PanelKit.BG_DARK
card.BackgroundTransparency = 0.08
card.Visible = false
card.Parent = gui
PanelKit.corner(card, UDim.new(0, 16))
PanelKit.stroke(card, OUTLINE, 3)
local scale = Instance.new("UIScale")
scale.Scale = UiScale.get()
scale.Parent = card
UiScale.onChanged(function()
	scale.Scale = UiScale.get()
end)

local title = PanelKit.label(card, "Title", UDim2.new(1, -60, 0, 26), UDim2.fromOffset(12, 8), 19, PanelKit.GOLD, PanelKit.TITLE_FONT)
title.TextXAlignment = Enum.TextXAlignment.Left
UiKit.outline(title, 2)
local timer = PanelKit.label(card, "Timer", UDim2.fromOffset(56, 22), UDim2.new(1, -64, 0, 10), 16, PanelKit.MUTED, PanelKit.BODY_FONT)
timer.TextXAlignment = Enum.TextXAlignment.Right
local place = PanelKit.label(card, "Place", UDim2.new(1, -24, 0, 18), UDim2.fromOffset(12, 34), 14, PanelKit.MUTED, PanelKit.BODY_FONT)
place.TextXAlignment = Enum.TextXAlignment.Left

local lines: { TextLabel } = {}
for i = 1, 5 do
	local line = PanelKit.label(card, "Step" .. i, UDim2.new(1, -24, 0, 22), UDim2.fromOffset(12, 56 + (i - 1) * 24), 15, TODO, PanelKit.BODY_FONT)
	line.TextXAlignment = Enum.TextXAlignment.Left
	UiKit.outline(line, 1.5)
	table.insert(lines, line)
end

local state: any = nil
local lastStepKey = ""

local function formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

type Step = { text: string, done: boolean }

local function steps(run: any): { Step }
	local list: { Step } = {}
	if run.state == "prepare" or not run.inside then
		table.insert(list, { text = Localize.t(if run.secured then "DELVE_STEP_TOO_LATE" else "DELVE_STEP_GO"), done = false })
		-- Zbiórka: kto już stoi przy szczelinie (wejście jednej osoby zabiera gotowych ze sobą)
		if run.state == "prepare" and typeof(run.crew) == "table" and #run.crew > 1 then
			for i, m in run.crew do
				if i > #lines - 1 then
					break
				end
				local key = if m.ready then "DELVE_STEP_READY" else "DELVE_STEP_ON_WAY"
				table.insert(list, { text = Localize.t(key, { tostring(m.name) }), done = m.ready == true })
			end
		end
		return list
	end
	local kind = Delve.kind(run.kind)
	table.insert(list, { text = Localize.t("DELVE_STEP_CLEAR"), done = run.blockageCleared })
	local objective = if run.kind == "chest"
		then Localize.t("DELVE_STEP_CHEST")
		elseif run.kind == "rubble" then Localize.t("DELVE_STEP_RUBBLE", { run.progress, if kind then kind.goal else 3 })
		else Localize.t("DELVE_STEP_SAMPLES", { run.progress, if kind then kind.goal else 3 })
	table.insert(list, { text = objective, done = run.objectiveDone })
	local carry = if run.findShown
		then Localize.t("DELVE_STEP_PICKUP")
		elseif run.carrier and not run.carrying then Localize.t("DELVE_STEP_CARRIER", { run.carrier })
		else Localize.t("DELVE_STEP_BONFIRE")
	table.insert(list, { text = carry, done = run.secured })
	if run.secured then
		if run.cryptCarrying then
			table.insert(list, { text = Localize.t("DELVE_STEP_ESCAPE"), done = false })
		elseif run.cryptSecured then
			table.insert(list, { text = Localize.t("DELVE_STEP_CRYPT_DONE"), done = true })
		elseif run.doorOpen then
			table.insert(list, { text = Localize.t("DELVE_STEP_ALTAR"), done = false })
		else
			table.insert(list, { text = Localize.t("DELVE_STEP_CHOICE"), done = false })
		end
		table.insert(list, { text = Localize.t("DELVE_STEP_EXIT"), done = false })
	end
	return list
end

local function render()
	local run = state and state.run
	-- Karta tylko dla trwającej ekspedycji gracza (po wyjściu liną serwer już jej nie przysyła)
	local show = run ~= nil
	if not show then
		card.Visible = false
		return
	end
	local kind = Delve.kind(run.kind)
	local modifier = Delve.modifier(run.modifier)
	title.Text = (if modifier then modifier.icon .. " " else "") .. (if kind then Localize.t(kind.key) else run.kind)
	local list = steps(run)
	local key = ""
	-- Pierwszy nieodhaczony krok świeci złotem
	local current = true
	for i, line in lines do
		local step = list[i]
		line.Visible = step ~= nil
		if step then
			line.Text = (if step.done then "✔ " else "• ") .. step.text
			line.TextColor3 = if step.done then DONE elseif current then NOW else TODO
			if not step.done then
				current = false
			end
			key ..= (if step.done then "1" else "0")
		end
	end
	card.Size = UDim2.fromOffset(300, 64 + #list * 24)
	if not card.Visible or key ~= lastStepKey then
		-- Nowy krok odhaczony: karta podskakuje
		UiFx.popIn(scale, UiScale.get(), 0.85, 0)
		if card.Visible and key ~= lastStepKey and string.find(key, "1") then
			UiFx.sound("ping", 0.4, 1.3)
		end
	end
	lastStepKey = key
	card.Visible = true
end

function DelveHud.setState(payload: any)
	state = payload
	render()
end

-- Nazwa komory i czas liczymy lokalnie co klatkę (bez czekania na serwer)
RunService.RenderStepped:Connect(function()
	if not card.Visible or not state or not state.run then
		return
	end
	local run = state.run
	timer.Text = formatTime(run.expiresAt - os.time())
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and Delve.isInside(root.Position) then
		local _, lx = Delve.locate(root.Position)
		local section = Delve.sectionAt(lx)
		place.Text = if section then "📍 " .. Localize.t(section.key) else ""
	else
		place.Text = if run.inside then "" else Localize.t("DELVE_WHERE_PASSAGE")
	end
end)

Localize.onChanged(render)

return DelveHud
