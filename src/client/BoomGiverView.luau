--!strict
-- „Dawca Wysypu”: gracz, który kupił Wysyp dla całego serwera, jest wyróżniony, dopóki Wysyp trwa.
-- Widzą to wszyscy (każdy klient rysuje to sam z atrybutu gracza "BoomGiverUntil" od serwera):
--   * nad głową złota plakietka „🍄 DAWCA WYSYPU” z biegnącym blaskiem, promieniami za grzybkiem
--     i licznikiem do końca Wysypu (nad zwykłym tytułem z TitleView),
--   * wokół postaci złote iskierki i ciepła poświata.
-- Kilka osób dorzuciło się do jednego Wysypu = każda jest Dawcą do jego końca (serwer przedłuża im atrybut).
-- Jak w TitleView: BillboardGui w PlayerGui z Adornee na głowie i ResetOnSpawn = false.

local Players = game:GetService("Players")

local BillboardGuard = require(script.Parent.BillboardGuard)
local Localize = require(script.Parent.Localize)
local UiFx = require(script.Parent.UiFx)
local UiKit = require(script.Parent.UiKit)

local BoomGiverView = {}

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local GOLD = Color3.fromRGB(255, 208, 72)
local OUTLINE = UiKit.OUTLINE
local SPARKLES = "rbxasset://textures/particles/sparkles_main.dds"

type Badge = {
	gui: BillboardGui,
	label: TextLabel,
	timer: TextLabel,
	aura: Attachment?,
}
local badges: { [Player]: Badge } = {}

local function giverUntil(target: Player): number
	local value = target:GetAttribute("BoomGiverUntil")
	return if typeof(value) == "number" then value else 0
end

-- Gracz, który teraz jest Dawcą (do napisu „Wysyp od …” w liczniku); nil, gdy nikt
function BoomGiverView.currentGiver(): Player?
	local best: Player? = nil
	local now = os.time()
	for _, target in Players:GetPlayers() do
		if giverUntil(target) > now and (not best or giverUntil(target) > giverUntil(best :: Player)) then
			best = target
		end
	end
	return best
end

local function formatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function makeBillboard(target: Player): Badge
	local gui = Instance.new("BillboardGui")
	gui.Name = "BoomGiver_" .. target.UserId
	gui.Size = UDim2.fromOffset(250, 62)
	gui.StudsOffset = Vector3.new(0, 4.1, 0) -- nad tytułem (TitleView: 2,4)
	gui.MaxDistance = 140
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.AnchorPoint = Vector2.new(0.5, 1)
	pill.Position = UDim2.fromScale(0.5, 1)
	pill.Size = UDim2.new(0.86, 0, 0, 40)
	pill.BackgroundColor3 = Color3.fromRGB(92, 52, 16)
	pill.Parent = gui
	local pillCorner = Instance.new("UICorner")
	pillCorner.CornerRadius = UDim.new(1, 0)
	pillCorner.Parent = pill
	local shade = Instance.new("UIGradient")
	shade.Rotation = 90
	shade.Color = ColorSequence.new(Color3.fromRGB(255, 220, 150), Color3.fromRGB(150, 110, 80))
	shade.Parent = pill
	UiFx.goldStroke(pill, 3)
	UiFx.stripes(pill, Color3.fromRGB(255, 240, 200), 0.85)
	UiFx.pulse(pill, 0.04, 1.1)

	-- Grzybek z promieniami po lewej, wystaje poza plakietkę
	local iconHolder = Instance.new("Frame")
	iconHolder.Name = "IconHolder"
	iconHolder.BackgroundTransparency = 1
	iconHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	iconHolder.Position = UDim2.new(0, 10, 0.5, -2)
	iconHolder.Size = UDim2.fromOffset(54, 54)
	iconHolder.ZIndex = 3
	iconHolder.Parent = pill
	UiFx.rays(iconHolder, { size = 92, color = GOLD, count = 6, speed = 60, transparency = 0.25, zIndex = 2 })
	local icon = UiKit.icon("boom", iconHolder, UDim2.fromOffset(52, 52), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	icon.ZIndex = 4
	UiFx.wiggle(icon, 10, 1.4)

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, 40, 0, 4)
	label.Size = UDim2.new(1, -50, 1, -8)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.ZIndex = 4
	label.Parent = pill
	UiKit.outline(label, 2.5)
	UiFx.textGradient(label, Color3.fromRGB(255, 255, 230), Color3.fromRGB(255, 196, 40))

	-- Licznik do końca Wysypu w rogu
	local timerFrame = Instance.new("Frame")
	timerFrame.Name = "Timer"
	timerFrame.AnchorPoint = Vector2.new(1, 0)
	timerFrame.Position = UDim2.new(0.93, 0, 0, 0)
	timerFrame.Size = UDim2.fromOffset(56, 22)
	timerFrame.BackgroundColor3 = Color3.fromRGB(40, 70, 30)
	timerFrame.ZIndex = 5
	timerFrame.Parent = gui
	local timerCorner = Instance.new("UICorner")
	timerCorner.CornerRadius = UDim.new(1, 0)
	timerCorner.Parent = timerFrame
	local timerStroke = Instance.new("UIStroke")
	timerStroke.Color = OUTLINE
	timerStroke.Thickness = 2
	timerStroke.Parent = timerFrame
	local timer = Instance.new("TextLabel")
	timer.Name = "Text"
	timer.BackgroundTransparency = 1
	timer.Size = UDim2.fromScale(1, 1)
	timer.Font = Enum.Font.FredokaOne
	timer.TextSize = 15
	timer.TextColor3 = Color3.fromRGB(150, 255, 130)
	timer.ZIndex = 6
	timer.Parent = timerFrame

	gui.Parent = playerGui
	return { gui = gui, label = label, timer = timer, aura = nil }
end

-- Iskierki i poświata wokół postaci (każdy klient robi je sam; znikają razem z postacią)
local function makeAura(root: BasePart): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = "BoomGiverAura"
	attachment.Position = Vector3.new(0, 0.5, 0)
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "Sparkles"
	sparkles.Texture = SPARKLES
	sparkles.Color = ColorSequence.new(Color3.fromRGB(255, 236, 140), Color3.fromRGB(255, 150, 40))
	sparkles.LightEmission = 1
	sparkles.LightInfluence = 0
	sparkles.Rate = 14
	sparkles.Lifetime = NumberRange.new(0.9, 1.6)
	sparkles.Speed = NumberRange.new(1.2, 3)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Acceleration = Vector3.new(0, 2.5, 0)
	sparkles.RotSpeed = NumberRange.new(-90, 90)
	sparkles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparkles.Shape = Enum.ParticleEmitterShape.Cylinder
	sparkles.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	sparkles.Parent = attachment
	local light = Instance.new("PointLight")
	light.Name = "Glow"
	light.Color = Color3.fromRGB(255, 200, 110)
	light.Brightness = 1.4
	light.Range = 11
	light.Shadows = false
	light.Parent = attachment
	attachment.Parent = root
	return attachment
end

local function remove(target: Player)
	local badge = badges[target]
	if badge then
		badges[target] = nil
		badge.gui:Destroy()
		if badge.aura then
			badge.aura:Destroy()
		end
	end
end

local function update(target: Player)
	local left = giverUntil(target) - os.time()
	local character = target.Character
	local head = character and character:FindFirstChild("Head")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if left <= 0 or not (head and head:IsA("BasePart")) then
		remove(target)
		return
	end
	local existing = badges[target]
	if existing and not existing.gui.Parent and existing.aura then
		existing.aura:Destroy() -- plakietka zniknęła sama: nie zostawiamy podwójnych iskierek
	end
	local b: Badge = if existing and existing.gui.Parent then existing else makeBillboard(target)
	badges[target] = b
	BillboardGuard.bind(b.gui, head) -- głowa poza światem (streaming, śmierć) = plakietka gaśnie
	b.label.Text = Localize.t("BOOM_GIVER")
	b.timer.Text = formatTime(left)
	if root and root:IsA("BasePart") and (not b.aura or b.aura.Parent ~= root) then
		if b.aura then
			b.aura:Destroy()
		end
		b.aura = makeAura(root)
	end
end

local function watch(target: Player)
	target:GetAttributeChangedSignal("BoomGiverUntil"):Connect(function()
		update(target)
	end)
	target.CharacterAdded:Connect(function(character)
		character:WaitForChild("Head", 10)
		character:WaitForChild("HumanoidRootPart", 10)
		remove(target)
		update(target)
	end)
	update(target)
end

for _, target in Players:GetPlayers() do
	watch(target)
end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(remove)
Localize.onChanged(function()
	for target in badges do
		update(target)
	end
end)

-- Licznik i koniec Wysypu
task.spawn(function()
	while true do
		task.wait(0.5)
		for target in badges do
			update(target)
		end
	end
end)

return BoomGiverView
