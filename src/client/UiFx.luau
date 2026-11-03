--!strict
-- Efekty interfejsu „jak w hitowych grach” (Grow a Garden, Steal a Brainrot):
--   promienie obracające się za ikoną, tęczowe i złote gradienty, obwódka z biegnącym blaskiem,
--   kołysanie ikon, pas światła po przycisku, pulsowanie, przesuwające się paski w tle,
--   liczenie liczby w górę i krótkie dźwięki interfejsu.
-- Wszystko, co rusza się stale, chodzi w JEDNEJ pętli RenderStepped i stoi, gdy element nie jest
-- widoczny (zamknięte okno nic nie kosztuje). Efekt znika sam razem ze swoim elementem.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Audio = require(script.Parent.Audio)
local UiKit = require(script.Parent.UiKit)

local UiFx = {}

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

-- ===== Jedna pętla dla wszystkich animacji =====

type Anim = { host: Instance, step: (t: number) -> () }
local anims: { [Instance]: Anim } = {}

-- Widoczny = cała droga do ScreenGui jest Visible / Enabled
local function shown(object: Instance): boolean
	local node: Instance? = object
	while node do
		if node:IsA("GuiObject") then
			if not node.Visible then
				return false
			end
		elseif node:IsA("LayerCollector") then
			return node.Enabled and node:IsDescendantOf(playerGui)
		end
		node = node.Parent
	end
	return false
end
UiFx.shown = shown

-- Rejestruje animację: `step(t)` co klatkę, gdy `host` (albo jego rodzic, dla UIGradient/UIStroke) jest widoczny
local function animate(key: Instance, host: Instance, step: (t: number) -> ())
	anims[key] = { host = host, step = step }
	key.Destroying:Connect(function()
		anims[key] = nil
	end)
end
UiFx.animate = animate

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for key, anim in anims do
		if key.Parent == nil then
			anims[key] = nil
		elseif shown(anim.host) then
			anim.step(t)
		end
	end
end)

-- ===== Kolory =====

local function hex(color: Color3): string
	return string.format("#%02X%02X%02X", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
end
UiFx.hex = hex

-- Tęcza przesunięta o `shift` (0..1): 7 punktów po kole barw
local function rainbow(shift: number, saturation: number?, value: number?): ColorSequence
	local points = {}
	for i = 0, 6 do
		local hue = (i / 6 + shift) % 1
		table.insert(points, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(hue, saturation or 0.7, value or 1)))
	end
	return ColorSequence.new(points)
end

-- ===== Gradienty =====

-- Pionowy gradient na napisie (np. biały u góry, złoty u dołu — jak tytuły w symulatorach)
function UiFx.textGradient(label: GuiObject, top: Color3, bottom: Color3): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Name = "TextShade"
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(top, bottom)
	gradient.Parent = label
	return gradient
end

-- Tęcza, która płynie (napis, ramka albo obwódka UIStroke). speed = obroty koła barw na sekundę
function UiFx.rainbow(target: Instance, speed: number?): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Name = "Rainbow"
	gradient.Color = rainbow(0)
	gradient.Parent = target
	local rate = speed or 0.25
	local host = if target:IsA("GuiObject") then target else (target.Parent or target)
	animate(gradient, host, function(t)
		gradient.Color = rainbow(t * rate)
	end)
	return gradient
end

-- Obracający się gradient (np. na UIStroke: blask biegnący po obwódce karty)
function UiFx.spin(target: Instance, colors: ColorSequence, degreesPerSecond: number?): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Name = "Spin"
	gradient.Color = colors
	gradient.Parent = target
	local rate = degreesPerSecond or 90
	local host = if target:IsA("GuiObject") then target else (target.Parent or target)
	animate(gradient, host, function(t)
		gradient.Rotation = (t * rate) % 360
	end)
	return gradient
end

-- Złota obwódka z biegnącym blaskiem (wyróżniona karta, ratunek koszyka)
function UiFx.goldStroke(target: GuiObject, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Name = "GoldStroke"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = thickness or 4
	stroke.Color = Color3.new(1, 1, 1)
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = target
	UiFx.spin(
		stroke,
		ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 196, 40)),
			ColorSequenceKeypoint.new(0.42, Color3.fromRGB(255, 214, 80)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 230)),
			ColorSequenceKeypoint.new(0.58, Color3.fromRGB(255, 214, 80)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(230, 140, 20)),
		}),
		120
	)
	return stroke
end

-- ===== Promienie za ikoną =====

export type RaysOptions = {
	size: number, -- średnica w pikselach
	color: Color3?,
	count: number?, -- liczba promieni (każdy przechodzi przez środek, więc widać 2 × count)
	speed: number?, -- stopnie na sekundę
	transparency: number?, -- przezroczystość w środku (0 = pełne)
	zIndex: number?,
	position: UDim2?,
}

-- Snop obracających się promieni (jak za nagrodą w Steal a Brainrot). Zwraca ramkę-kontener.
function UiFx.rays(parent: Instance, options: RaysOptions): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Rays"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = options.position or UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(options.size, options.size)
	holder.ZIndex = options.zIndex or 1
	holder.Active = false
	holder.Parent = parent
	local count = options.count or 6
	local center = options.transparency or 0.45
	for i = 1, count do
		local beam = Instance.new("Frame")
		beam.Name = "Beam" .. i
		beam.BorderSizePixel = 0
		beam.AnchorPoint = Vector2.new(0.5, 0.5)
		beam.Position = UDim2.fromScale(0.5, 0.5)
		beam.Size = UDim2.new(0, math.max(6, math.floor(options.size * 0.13)), 1, 0)
		beam.Rotation = (i - 1) * 180 / count
		beam.BackgroundColor3 = options.color or Color3.fromRGB(255, 230, 140)
		beam.ZIndex = holder.ZIndex
		beam.Active = false
		beam.Parent = holder
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.5 + center * 0.5),
			NumberSequenceKeypoint.new(0.5, center),
			NumberSequenceKeypoint.new(0.7, 0.5 + center * 0.5),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = beam
	end
	local rate = options.speed or 25
	animate(holder, holder, function(t)
		holder.Rotation = (t * rate) % 360
	end)
	return holder
end

-- Miękka poświata: kilka koncentrycznych kół, coraz bardziej przezroczystych
function UiFx.glow(parent: Instance, size: number, color: Color3, strength: number?, zIndex: number?): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Glow"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(size, size)
	holder.ZIndex = zIndex or 1
	holder.Active = false
	holder.Parent = parent
	local base = 1 - (strength or 0.35)
	for i, factor in { 1, 0.72, 0.46 } do
		local ring = Instance.new("Frame")
		ring.Name = "Ring" .. i
		ring.BorderSizePixel = 0
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 0.5)
		ring.Size = UDim2.fromScale(factor, factor)
		ring.BackgroundColor3 = color
		ring.BackgroundTransparency = math.clamp(base + (1 - base) * (1 - i / 3) * 0.9, 0, 1)
		ring.ZIndex = holder.ZIndex
		ring.Active = false
		ring.Parent = holder
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = ring
	end
	return holder
end

-- ===== Ruch =====

-- Delikatne kołysanie w górę i w dół (ikona produktu, grzyb na karcie)
function UiFx.bob(target: GuiObject, amplitude: number?, period: number?, phase: number?)
	local base = target.Position
	local amp = amplitude or 4
	local omega = math.pi * 2 / (period or 2.4)
	local offset = phase or math.random() * 6
	animate(target, target, function(t)
		target.Position = base + UDim2.fromOffset(0, math.floor(math.sin(t * omega + offset) * amp + 0.5))
	end)
end

-- Kołysanie na boki (plakietka „CAŁY SERWER”, naklejka x2)
function UiFx.wiggle(target: GuiObject, degrees: number?, period: number?)
	local base = target.Rotation
	local amp = degrees or 4
	local omega = math.pi * 2 / (period or 1.8)
	animate(target, target, function(t)
		target.Rotation = base + math.sin(t * omega) * amp
	end)
end

-- Pulsowanie przez własną UIScale elementu (nie dla przycisków UiKit: one używają UIScale do wciśnięcia)
function UiFx.pulse(target: GuiObject, amount: number?, period: number?)
	local scale = target:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = target
	local amp = amount or 0.05
	local omega = math.pi * 2 / (period or 1.2)
	animate(scale, target, function(t)
		local base = (scale:GetAttribute("Base") :: number?) or 1
		scale.Scale = base * (1 + math.sin(t * omega) * amp)
	end)
end

-- Ukośne paski płynące w tle (karta-wyróżnienie, ratunek). Rodzic musi mieć ClipsDescendants.
function UiFx.stripes(parent: GuiObject, color: Color3?, transparency: number?, zIndex: number?): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Stripes"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = zIndex or parent.ZIndex
	holder.ClipsDescendants = true
	holder.Active = false
	holder.Parent = parent
	local corner = parent:FindFirstChildOfClass("UICorner")
	if corner then
		corner:Clone().Parent = holder
	end
	local GAP = 34
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.BackgroundTransparency = 1
	track.Size = UDim2.new(1, GAP * 4, 1, 0)
	track.Position = UDim2.fromOffset(-GAP * 2, 0)
	track.ZIndex = holder.ZIndex
	track.Active = false
	track.Parent = holder
	for i = 0, 40 do
		local stripe = Instance.new("Frame")
		stripe.BorderSizePixel = 0
		stripe.AnchorPoint = Vector2.new(0.5, 0.5)
		stripe.Size = UDim2.new(0, 12, 3, 0)
		stripe.Position = UDim2.new(0, i * GAP, 0.5, 0)
		stripe.Rotation = 30
		stripe.BackgroundColor3 = color or Color3.new(1, 1, 1)
		stripe.BackgroundTransparency = transparency or 0.9
		stripe.ZIndex = holder.ZIndex
		stripe.Active = false
		stripe.Parent = track
	end
	animate(track, holder, function(t)
		track.Position = UDim2.fromOffset(-GAP * 2 + math.floor((t * 14) % GAP), 0)
	end)
	return holder
end

-- Pas światła przebiegający po przycisku co `every` sekund (przycisk przycina go do swoich krawędzi)
function UiFx.shine(button: GuiObject, every: number?)
	button.ClipsDescendants = true
	local band = Instance.new("Frame")
	band.Name = "Shine"
	band.BackgroundColor3 = Color3.new(1, 1, 1)
	band.BorderSizePixel = 0
	band.Size = UDim2.new(0.28, 0, 2.6, 0)
	band.AnchorPoint = Vector2.new(0.5, 0.5)
	band.Position = UDim2.fromScale(-0.4, 0.5)
	band.Rotation = 22
	band.ZIndex = button.ZIndex + 6
	band.Active = false
	band.Parent = button
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.45, 0.5),
		NumberSequenceKeypoint.new(0.55, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	fade.Parent = band
	local pause = every or 2.6
	local cycle = 0.7 + pause
	local offset = math.random() * cycle
	animate(band, button, function(t)
		local phase = ((t + offset) % cycle) / 0.7
		band.Visible = phase < 1
		if phase < 1 then
			local eased = 1 - (1 - phase) ^ 2
			band.Position = UDim2.fromScale(-0.4 + eased * 1.8, 0.5)
		end
	end)
end

-- Podskok przy otwarciu (okno, karta): skala od `from` do bazy z odbiciem
function UiFx.popIn(scale: UIScale, base: number?, from: number?, delay: number?)
	local target = base or (scale:GetAttribute("Base") :: number?) or 1
	scale.Scale = target * (from or 0.6)
	local tween = TweenService:Create(scale, TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, delay or 0), { Scale = target })
	tween:Play()
end

-- Liczba rośnie do `value` w `time` sekund (np. „+184 tys.” na karcie skrzyni)
function UiFx.countTo(label: TextLabel, value: number, format: (number) -> string, time: number?)
	local start = os.clock()
	local duration = time or 0.6
	local token = (label:GetAttribute("CountToken") :: number? or 0) + 1
	label:SetAttribute("CountToken", token)
	task.spawn(function()
		while label.Parent and label:GetAttribute("CountToken") == token do
			local k = math.min(1, (os.clock() - start) / duration)
			local eased = 1 - (1 - k) ^ 3
			label.Text = format(value * eased)
			if k >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
	end)
end

-- Krótkie potrząśnięcie (brak miejsca, nie da się kupić) — z UiKit, tu dla wygody
UiFx.shake = UiKit.shake

-- ===== Dźwięki interfejsu =====

local lastSound: { [string]: number } = {}
-- Dźwięk z Config.Audio.sfx; ten sam najwyżej co 0,06 s (szybkie najechania nie terkoczą)
function UiFx.sound(name: string, volume: number?, pitch: number?)
	local now = os.clock()
	if now - (lastSound[name] or 0) < 0.06 then
		return
	end
	lastSound[name] = now
	pcall(Audio.play, name, { volume = volume or 0.5, pitch = pitch or 1, jitter = 0.04 })
end

return UiFx
