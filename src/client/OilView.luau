--!strict
-- Kończący się olej na pasku u góry, jak w cutscence: gdy oleju jest mało (poza chatką i obozem),
-- pasek miga na czerwono i się trzęsie, ikonka latarni drga i przygasa, z końca paska kapią krople,
-- a obok pojawia się licznik „⏱ 0:12”, ile sekund zostało do zgaśnięcia (z tempa spalania).
-- Pasek należy do Hud (Hud/Top/Oil); tu tylko go animujemy, bez zmiany układu.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local UiKit = require(script.Parent.UiKit)
local UiScale = require(script.Parent.UiScale)

local OilView = {}

local CRITICAL = 0.1 -- poniżej: mocniejsze drżenie i przygasanie latarni
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local layer = Instance.new("ScreenGui")
layer.Name = "OilView"
layer.ResetOnSpawn = false
layer.DisplayOrder = 3
layer.Parent = playerGui

-- Licznik sekund po lewej od paska
local timer = Instance.new("Frame")
timer.Name = "Timer"
timer.AnchorPoint = Vector2.new(1, 0.5)
timer.Size = UDim2.fromOffset(92, 30)
timer.BackgroundColor3 = Color3.fromRGB(150, 28, 24)
timer.Visible = false
timer.Parent = layer
local timerCorner = Instance.new("UICorner")
timerCorner.CornerRadius = UDim.new(1, 0)
timerCorner.Parent = timer
local timerStroke = Instance.new("UIStroke")
timerStroke.Color = UiKit.OUTLINE
timerStroke.Thickness = 2.5
timerStroke.Parent = timer
local timerScale = Instance.new("UIScale")
timerScale.Parent = timer
local timerText = Instance.new("TextLabel")
timerText.BackgroundTransparency = 1
timerText.Size = UDim2.new(1, -12, 1, -6)
timerText.Position = UDim2.fromOffset(6, 3)
timerText.Font = Enum.Font.FredokaOne
timerText.TextScaled = true
timerText.TextColor3 = Color3.new(1, 1, 1)
timerText.Parent = timer
UiKit.outline(timerText, 2)

-- ===== Stan =====

local fraction = 1
local danger = false
local oilNow = 0
local lastOil: number? = nil
local lastAt = 0
local rate = 0 -- olej na sekundę (średnia ruchoma)

type Parts = { panel: Frame, icon: GuiObject?, fill: Frame?, color: Color3? }
local parts: Parts? = nil

local function findParts(): Parts?
	if parts and parts.panel.Parent then
		return parts
	end
	local hud = playerGui:FindFirstChild("Hud")
	local top = hud and hud:FindFirstChild("Top")
	local panel = top and top:FindFirstChild("Oil")
	if not (panel and panel:IsA("Frame")) then
		return nil
	end
	local icon = panel:FindFirstChild("Icon")
	local fill = panel:FindFirstChild("Fill", true)
	parts = {
		panel = panel,
		icon = if icon and icon:IsA("GuiObject") then icon else nil,
		fill = if fill and fill:IsA("Frame") then fill else nil,
		color = if fill and fill:IsA("Frame") then fill.BackgroundColor3 else nil,
	}
	return parts
end

-- Kropla oleju spada z końca paska i znika
local function drip(fill: Frame)
	local at = fill.AbsolutePosition + Vector2.new(fill.AbsoluteSize.X - 4, fill.AbsoluteSize.Y)
	local drop = Instance.new("Frame")
	drop.AnchorPoint = Vector2.new(0.5, 0)
	drop.Position = UDim2.fromOffset(at.X, at.Y)
	local size = math.random(5, 8) * UiScale.get()
	drop.Size = UDim2.fromOffset(size, size * 1.3)
	drop.BackgroundColor3 = Color3.fromRGB(255, 120, 40)
	drop.BorderSizePixel = 0
	drop.Parent = layer
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = drop
	local fall = TweenService:Create(drop, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.fromOffset(at.X, at.Y + 34 * UiScale.get()),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size * 0.6, size),
	})
	fall.Completed:Connect(function()
		drop:Destroy()
	end)
	fall:Play()
end

local function formatSeconds(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return string.format("⏱ %d:%02d", seconds // 60, seconds % 60)
end

-- Stan z serwera (co tick): ile oleju, czy gracz jest poza bezpiecznym miejscem
function OilView.update(state: any)
	local oilMax = tonumber(state.oilMax) or 0
	local oil = tonumber(state.oil) or 0
	oilNow = oil
	fraction = if oilMax > 0 then math.clamp(oil / oilMax, 0, 1) else 1
	danger = not Economy.isSafeZone(state.zone) and not state.downed
	-- Tempo spalania z kolejnych paczek (tylko gdy olej spada)
	local now = os.clock()
	if lastOil and danger and oil < lastOil then
		local dt = now - lastAt
		if dt > 0.05 then
			local current = (lastOil - oil) / dt
			rate = if rate > 0 then rate * 0.8 + current * 0.2 else current
		end
	elseif not danger then
		rate = 0
	end
	lastOil = oil
	lastAt = now
end

local nextDrip = 0
RunService.RenderStepped:Connect(function()
	local p = findParts()
	if not p then
		return
	end
	local low = danger and fraction < Config.OilLowFraction
	local t = os.clock()
	if not low then
		p.panel.Rotation = 0
		if p.fill and p.color then
			p.fill.BackgroundColor3 = p.color
		end
		if p.icon then
			UiKit.setIconTransparency(p.icon, 0)
		end
		timer.Visible = false
		return
	end
	local critical = fraction < CRITICAL
	-- Miganie na czerwono i drżenie jak w cutscence (mocniej, gdy zostały resztki)
	local flash = 0.5 + 0.5 * math.sin(t * (if critical then 16 else 12))
	if p.fill and p.color then
		p.fill.BackgroundColor3 = p.color:Lerp(Color3.fromRGB(255, 50, 40), 0.6 + 0.4 * flash)
	end
	p.panel.Rotation = math.sin(t * 40) * (if critical then 2.5 else 1.5) * flash
	-- Latarnia drga i przygasa (szum, nie losowe skoki)
	if p.icon then
		local dip = if critical and math.noise(t * 3.1, 7.7) > 0.2 then 0.55 else 0
		UiKit.setIconTransparency(p.icon, math.clamp(0.25 - 0.25 * math.noise(t * 9, 1.3) + dip, 0, 0.8))
	end
	if p.fill and t >= nextDrip and fraction > 0 then
		nextDrip = t + (if critical then 0.22 else 0.4)
		drip(p.fill)
	end
	-- Ile sekund zostało
	if rate > 0.01 then
		local scale = UiScale.get()
		timerScale.Scale = scale * (1 + 0.08 * flash)
		local abs = p.panel.AbsolutePosition
		timer.Position = UDim2.fromOffset(abs.X - 8 * scale, abs.Y + p.panel.AbsoluteSize.Y / 2)
		timerText.Text = formatSeconds(oilNow / rate)
		timer.Visible = true
	else
		timer.Visible = false
	end
end)

return OilView
