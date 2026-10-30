--!strict
-- Rysuje tablice rankingów (części z tagiem "Leaderboard") w języku gracza.
-- Serwer (LeaderboardService) wpisuje wyniki do atrybutu "Entries" jako JSON:
--   [{ n = nazwa, v = wynik, me = userId }], a "Source" mówi, czy to cały świat, czy ten serwer.
-- SurfaceGui trzymamy w PlayerGui z Adornee (tak rysuje się pewnie także po przesyłaniu mapy),
-- bezpośrednio, z ResetOnSpawn = false: zwykły folder w PlayerGui Roblox kasuje przy odrodzeniu.

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Progress = require(Shared.Progress)
local Localize = require(script.Parent.Localize)
local UiKit = require(script.Parent.UiKit)

local LeaderboardView = {}

local player = Players.LocalPlayer
local TITLE_FONT = Enum.Font.FredokaOne
local BODY_FONT = Enum.Font.GothamBold
local TEXT = Color3.fromRGB(252, 238, 210)
local MUTED = Color3.fromRGB(214, 188, 150)
local ACCENT = Color3.fromRGB(255, 214, 120)
local MEDALS = { "🥇", "🥈", "🥉" }

local KINDS: { [string]: { title: string, icon: string, color: Color3, weekly: boolean } } = {
	richest = { title = "BOARD_RICHEST", icon = "coin", color = Color3.fromRGB(255, 205, 80), weekly = false },
	rare = { title = "BOARD_RARE", icon = "trophy", color = Color3.fromRGB(255, 130, 220), weekly = true },
	thieves = { title = "BOARD_THIEVES", icon = "sell", color = Color3.fromRGB(255, 120, 90), weekly = true },
	candy = { title = "BOARD_CANDY", icon = "candy", color = Color3.fromRGB(255, 150, 50), weekly = false },
}

local playerGui = player:WaitForChild("PlayerGui")

type Row = { frame: Frame, rank: TextLabel, name: TextLabel, value: TextLabel, price: TextLabel? }
type Board = { screen: BasePart, gui: SurfaceGui, title: TextLabel, subtitle: TextLabel, rows: { Row }, empty: TextLabel }
local boards: { [BasePart]: Board } = {}

-- Krótko i bez spacji (60.5K, 1.25M): napis na tablicy jest skalowany i zawijał się na spacji
-- w środku liczby („60” w jednej linii, „000” pod spodem)
local function shortNumber(value: number): string
	local v = math.floor(value + 0.5)
	local function trim(text: string): string
		return (text:gsub("%.0+([KMB])$", "%1"):gsub("(%.%d-)0+([KMB])$", "%1%2"))
	end
	if v < 10000 then
		return tostring(v)
	elseif v < 1e6 then
		local k = v / 1000
		return trim(if k < 100 then string.format("%.1fK", k) else string.format("%dK", math.floor(k)))
	elseif v < 1e9 then
		local m = v / 1e6
		return trim(if m < 10 then string.format("%.2fM", m) elseif m < 100 then string.format("%.1fM", m) else string.format("%dM", math.floor(m)))
	end
	local b = v / 1e9
	return trim(if b < 10 then string.format("%.2fB", b) else string.format("%.1fB", b))
end

local function label(parent: Instance, name: string, size: UDim2, position: UDim2, font: Enum.Font, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = size
	l.Position = position
	l.BackgroundTransparency = 1
	l.Font = font
	l.TextColor3 = color or TEXT
	l.TextScaled = true
	l.RichText = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

local VARIANT_BY_RANK: { [number]: Config.VariantDef } = {}
for _, variant in Config.Variants do
	VARIANT_BY_RANK[variant.rank] = variant
end

-- Tekst wyniku; dla znaleziska tygodnia drugi tekst to cena (rysowana pod nazwą grzyba)
local function valueText(kind: string, value: number): (string, string?)
	if kind == "rare" then
		local coins, speciesId, rank = Progress.decodeFind(value)
		local species = if speciesId then Economy.getSpecies(speciesId) else nil
		local variant = VARIANT_BY_RANK[rank]
		local name = if species then Localize.t(species.key) else "?"
		return (if variant then variant.icon .. " " else "") .. name, "💰 " .. shortNumber(coins)
	elseif kind == "thieves" then
		return Localize.t("BOARD_STEALS", { value })
	elseif kind == "candy" then
		return "🍬 " .. shortNumber(value)
	end
	return "💰 " .. shortNumber(value)
end

local function render(board: Board)
	local screen = board.screen
	local kind = screen:GetAttribute("Kind")
	local def = if typeof(kind) == "string" then KINDS[kind] else nil
	if not def then
		return
	end
	board.title.Text = Localize.t(def.title)
	board.title.TextColor3 = def.color
	local parts = {}
	if kind == "thieves" then
		table.insert(parts, Localize.t("BOARD_THIEVES_HINT"))
	elseif kind == "candy" then
		table.insert(parts, Localize.t(if Workspace:GetAttribute("Halloween") == true then "BOARD_CANDY_HINT" else "BOARD_CANDY_FINAL"))
	end
	if def.weekly then
		table.insert(parts, Localize.t("BOARD_WEEK_RESET"))
	end
	if screen:GetAttribute("Source") == "server" then
		table.insert(parts, Localize.t("BOARD_SERVER"))
	end
	board.subtitle.Text = table.concat(parts, "  ·  ")

	local entries = {}
	local raw = screen:GetAttribute("Entries")
	if typeof(raw) == "string" then
		local ok, decoded = pcall(function()
			return HttpService:JSONDecode(raw)
		end)
		if ok and typeof(decoded) == "table" then
			entries = decoded
		end
	end
	board.empty.Visible = #entries == 0
	board.empty.Text = Localize.t("BOARD_EMPTY")
	for index, row in board.rows do
		local entry = entries[index]
		row.frame.Visible = entry ~= nil
		if entry then
			local mine = entry.me == player.UserId
			row.rank.Text = MEDALS[index] or tostring(index)
			row.name.Text = tostring(entry.n)
			row.name.TextColor3 = if mine then ACCENT else TEXT
			local text, price = valueText(kind :: string, tonumber(entry.v) or 0)
			row.value.Text = text
			if row.price then
				row.price.Text = price or ""
			end
			row.frame.BackgroundTransparency = if mine then 0.55 else (if index % 2 == 0 then 0.85 else 1)
		end
	end
end

local function build(screen: BasePart)
	if boards[screen] then
		return
	end
	local kind = screen:GetAttribute("Kind")
	local def = if typeof(kind) == "string" then KINDS[kind] else nil
	if not def then
		return
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Board_" .. (kind :: string)
	gui.Adornee = screen
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.MaxDistance = 140
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.fromRGB(34, 26, 20)
	root.BorderSizePixel = 0
	root.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.03, 0)
	pad.PaddingBottom = UDim.new(0.03, 0)
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.Parent = root

	UiKit.icon(def.icon, root, UDim2.fromScale(0.13, 0.13), UDim2.fromScale(0, 0))
	local title = label(root, "Title", UDim2.fromScale(0.85, 0.1), UDim2.fromScale(0.15, 0.01), TITLE_FONT, def.color)
	local subtitle = label(root, "Subtitle", UDim2.fromScale(0.85, 0.045), UDim2.fromScale(0.15, 0.11), BODY_FONT, MUTED)
	local line = Instance.new("Frame")
	line.Size = UDim2.new(1, 0, 0, 3)
	line.Position = UDim2.fromScale(0, 0.165)
	line.BackgroundColor3 = def.color
	line.BorderSizePixel = 0
	line.Parent = root

	local rows: { Row } = {}
	local count = screen:GetAttribute("Rows")
	local rowCount = if typeof(count) == "number" then count else 8
	local top, height = 0.19, 0.8 / rowCount
	for index = 1, rowCount do
		local frame = Instance.new("Frame")
		frame.Name = "Row" .. index
		frame.Size = UDim2.fromScale(1, height * 0.94)
		frame.Position = UDim2.fromScale(0, top + (index - 1) * height)
		frame.BackgroundColor3 = Color3.fromRGB(255, 220, 150)
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.Parent = root
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.2, 0)
		c.Parent = frame
		local rank = label(frame, "Rank", UDim2.fromScale(0.1, 0.86), UDim2.fromScale(0.01, 0.07), TITLE_FONT, ACCENT)
		rank.TextXAlignment = Enum.TextXAlignment.Center
		local name = label(frame, "Name", UDim2.fromScale(0.44, 0.8), UDim2.fromScale(0.12, 0.1), TITLE_FONT)
		local value: TextLabel
		local price: TextLabel? = nil
		if kind == "rare" then
			-- Znalezisko tygodnia: nazwa grzyba u góry, cena mniejszym złotym napisem pod nią
			value = label(frame, "Value", UDim2.fromScale(0.44, 0.5), UDim2.fromScale(0.56, 0.04), TITLE_FONT)
			price = label(frame, "Price", UDim2.fromScale(0.44, 0.4), UDim2.fromScale(0.56, 0.54), TITLE_FONT, ACCENT)
			price.TextXAlignment = Enum.TextXAlignment.Right
		else
			value = label(frame, "Value", UDim2.fromScale(0.44, 0.72), UDim2.fromScale(0.56, 0.14), TITLE_FONT)
		end
		value.TextXAlignment = Enum.TextXAlignment.Right
		rows[index] = { frame = frame, rank = rank, name = name, value = value, price = price }
	end
	local empty = label(root, "Empty", UDim2.fromScale(1, 0.1), UDim2.fromScale(0, 0.45), TITLE_FONT, MUTED)
	empty.TextXAlignment = Enum.TextXAlignment.Center

	local board: Board = { screen = screen, gui = gui, title = title, subtitle = subtitle, rows = rows, empty = empty }
	boards[screen] = board
	render(board)
	screen:GetAttributeChangedSignal("Entries"):Connect(function()
		render(board)
	end)
	screen:GetAttributeChangedSignal("Source"):Connect(function()
		render(board)
	end)
	screen.AncestryChanged:Connect(function()
		if not screen:IsDescendantOf(game) then
			gui:Destroy()
			boards[screen] = nil
		end
	end)
end

for _, screen in CollectionService:GetTagged("Leaderboard") do
	if screen:IsA("BasePart") then
		build(screen)
	end
end
CollectionService:GetInstanceAddedSignal("Leaderboard"):Connect(function(screen)
	if screen:IsA("BasePart") then
		build(screen)
	end
end)
Localize.onChanged(function()
	for _, board in boards do
		render(board)
	end
end)

return LeaderboardView
