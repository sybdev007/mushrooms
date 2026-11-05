--!strict
-- Zbiórka do ekspedycji: gdy ktoś bierze zlecenie z tablicy w Obozie, inni gracze z otwartą Jaskinią
-- dostają u góry ekranu kartę „⛏️ Tom zbiera ekipę · Zaginiona skrzynia · 1/4” z przyciskiem „Dołącz”
-- (DelveService.callCrew). Dołączyć można z dowolnego miejsca; do komór schodzi się i tak przez szczelinę
-- w Otchłani (karta celu DelveHud prowadzi dalej). Karta znika po CALL_SECONDS, po kliknięciu, gdy ekipa
-- jest pełna albo zeszła. Nie blokuje chodzenia. Zdarzenie DelveCall ma tylko tego odbiorcę (zasada 4).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Delve = require(Shared:WaitForChild("Delve"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Audio = require(script.Parent.Audio)
local Localize = require(script.Parent.Localize)
local PanelKit = require(script.Parent.PanelKit)
local UiKit = require(script.Parent.UiKit)
local UiScale = require(script.Parent.UiScale)

local DelveCall = {}

local CALL_SECONDS = 15
local WIDTH, HEIGHT = 340, 88
local TOP = 312 -- pod kartą zdobyczy (FindCard), żeby się nie nakładały

local gui = Instance.new("ScreenGui")
gui.Name = "DelveCall"
gui.ResetOnSpawn = false
gui.DisplayOrder = 19
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local card = Instance.new("Frame")
card.Name = "Card"
card.AnchorPoint = Vector2.new(0.5, 0)
card.Size = UDim2.fromOffset(WIDTH, HEIGHT)
card.BackgroundColor3 = Color3.fromRGB(34, 26, 20)
card.BackgroundTransparency = 0.05
card.Visible = false
card.Parent = gui
PanelKit.corner(card, UDim.new(0, 16))
PanelKit.stroke(card, Color3.fromRGB(110, 200, 255), 3)
local cardScale = Instance.new("UIScale")
cardScale.Parent = card

local head = PanelKit.label(card, "Head", UDim2.new(1, -50, 0, 24), UDim2.fromOffset(14, 8), 20, PanelKit.GOLD)
head.TextXAlignment = Enum.TextXAlignment.Left
UiKit.outline(head, 2)
local line = PanelKit.label(card, "Line", UDim2.new(1, -150, 0, 40), UDim2.fromOffset(14, 38), 16, PanelKit.TEXT, PanelKit.BODY_FONT)
line.TextXAlignment = Enum.TextXAlignment.Left
line.TextWrapped = true

local join = Instance.new("TextButton")
join.Name = "Join"
join.Size = UDim2.fromOffset(118, 38)
join.Position = UDim2.new(1, -130, 0, 40)
join.BackgroundColor3 = Color3.fromRGB(64, 190, 78)
join.Text = ""
join.Parent = card
PanelKit.corner(join, UDim.new(0, 12))
PanelKit.stroke(join, PanelKit.OUTLINE, 2.5)
local joinText = PanelKit.label(join, "Text", UDim2.new(1, -10, 1, -8), UDim2.fromOffset(5, 4), 18)
UiKit.outline(joinText, 2)

local close = Instance.new("TextButton")
close.Name = "Close"
close.Size = UDim2.fromOffset(26, 26)
close.AnchorPoint = Vector2.new(0.5, 0.5)
close.Position = UDim2.new(1, -4, 0, 4)
close.BackgroundColor3 = Color3.fromRGB(196, 44, 40)
close.Text = "X" -- FredokaOne nie ma znaku „✕”
close.TextScaled = true
close.Font = PanelKit.TITLE_FONT
close.TextColor3 = Color3.new(1, 1, 1)
close.Parent = card
PanelKit.corner(close, UDim.new(1, 0))
PanelKit.stroke(close, PanelKit.OUTLINE, 2)

type Call = { id: number, leader: string, kind: string?, modifier: string?, count: number, max: number }
local current: Call? = nil
local token = 0
local dismissed: { [number]: boolean } = {} -- zbiórki, które gracz zamknął (aktualizacje ich nie wracają)

local function shownTop(): number
	return math.floor(TOP * UiScale.get())
end

local function hide()
	token += 1
	current = nil
	if not card.Visible then
		return
	end
	local mine = token
	local tween = TweenService:Create(card, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(0.5, 0, 0, -HEIGHT - 20) })
	tween:Play()
	tween.Completed:Once(function()
		if token == mine then
			card.Visible = false
		end
	end)
end

local function render()
	local call = current
	if not call then
		return
	end
	local kind = if call.kind then Delve.kind(call.kind) else nil
	local modifier = if call.modifier then Delve.modifier(call.modifier) else nil
	head.Text = "⛏️ " .. Localize.t("DELVECALL_HEAD", { call.leader })
	line.Text = Localize.t("DELVECALL_LINE", {
		(if modifier then modifier.icon .. " " else "") .. (if kind then Localize.t(kind.key) else ""),
		call.count,
		call.max,
	})
	joinText.Text = Localize.t("DELVE_JOIN")
end

local function show(call: Call)
	local same = current ~= nil and (current :: Call).id == call.id and card.Visible
	current = call
	render()
	if same then
		return -- tylko nowa liczba osób, bez ponownego wjazdu i dźwięku
	end
	token += 1
	local mine = token
	card.Visible = true
	card.Position = UDim2.new(0.5, 0, 0, -HEIGHT - 20)
	TweenService:Create(card, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, shownTop()),
	}):Play()
	Audio.play("ping", { volume = 0.6 })
	task.delay(CALL_SECONDS, function()
		if token == mine then
			hide()
		end
	end)
end

join.Activated:Connect(function()
	local call = current
	if call then
		Remotes.get("DelveAction"):FireServer("join", call.id)
		Audio.play("ping", { volume = 0.5 })
	end
	hide()
end)
close.Activated:Connect(function()
	local call = current
	if call then
		dismissed[call.id] = true
	end
	hide()
end)

function DelveCall.start()
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local function layout()
		cardScale.Scale = UiScale.get()
		if card.Visible and current then
			card.Position = UDim2.new(0.5, 0, 0, shownTop())
		end
	end
	layout()
	UiScale.onChanged(layout)
	Localize.onChanged(render)
	Remotes.get("DelveCall").OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" or typeof(payload.id) ~= "number" then
			return
		end
		if payload.closed then
			if current and (current :: Call).id == payload.id then
				hide()
			end
			return
		end
		if dismissed[payload.id] or typeof(payload.leader) ~= "string" then
			return
		end
		show({
			id = payload.id,
			leader = payload.leader,
			kind = if typeof(payload.kind) == "string" then payload.kind else nil,
			modifier = if typeof(payload.modifier) == "string" then payload.modifier else nil,
			count = tonumber(payload.count) or 1,
			max = tonumber(payload.max) or Delve.MAX_PARTY,
		})
	end)
end

return DelveCall
