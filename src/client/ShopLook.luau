--!strict
-- Wygląd „jak w sklepie” dla wszystkich okien (oprócz Ulepszeń): te same elementy, co karty sklepu
-- (ShopPanel), zebrane w jednym miejscu, żeby każde okno wyglądało i ruszało się tak samo:
--   * halo: obracające się promienie i miękka poświata za ikoną,
--   * shade: pionowy cień na karcie (jaśniej u góry),
--   * title: biało-kremowy gradient na tytule z grubym obrysem,
--   * button: przebiegający błysk na przycisku,
--   * hover: karta lekko rośnie pod kursorem,
--   * cascade: karty wskakują po kolei przy otwarciu okna (z dźwiękiem „whoosh”),
--   * bob: ikona kołysze się w górę i w dół.
-- Wszystko, co się rusza, chodzi w pętli UiFx i stoi, gdy okno jest zamknięte.

local TweenService = game:GetService("TweenService")

local UiFx = require(script.Parent.UiFx)

local ShopLook = {}

local TITLE_TOP = Color3.new(1, 1, 1)
local TITLE_BOTTOM = Color3.fromRGB(255, 226, 150)

-- Promienie i poświata za ikoną. position: środek ikony w rodzicu. Zwraca kontener (do ukrycia / ZIndex).
function ShopLook.halo(parent: Instance, position: UDim2, accent: Color3, size: number?, strong: boolean?, zIndex: number?): Frame
	local s = size or 150
	local holder = Instance.new("Frame")
	holder.Name = "Halo"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = position
	holder.Size = UDim2.fromOffset(1, 1)
	holder.ZIndex = zIndex or 1
	holder.Active = false
	holder.Parent = parent
	UiFx.rays(holder, {
		size = s * 1.5,
		color = accent,
		count = 7,
		speed = if strong then 34 else 14,
		transparency = if strong then 0.3 else 0.62,
		zIndex = holder.ZIndex,
	})
	UiFx.glow(holder, s, accent, if strong then 0.4 else 0.25, holder.ZIndex)
	return holder
end

-- Pionowy cień na karcie (jak karty sklepu)
function ShopLook.shade(frame: GuiObject, bottom: Color3?): UIGradient
	local existing = frame:FindFirstChild("Shade")
	if existing and existing:IsA("UIGradient") then
		return existing
	end
	local g = Instance.new("UIGradient")
	g.Name = "Shade"
	g.Rotation = 90
	g.Color = ColorSequence.new(Color3.new(1, 1, 1), bottom or Color3.fromRGB(176, 166, 158))
	g.Parent = frame
	return g
end

-- Tytuł karty: kremowy gradient (biały kolor tekstu, żeby gradient miał pełne barwy)
function ShopLook.title(label: TextLabel, top: Color3?, bottom: Color3?)
	label.TextColor3 = Color3.new(1, 1, 1)
	if not label:FindFirstChildOfClass("UIGradient") then
		UiFx.textGradient(label, top or TITLE_TOP, bottom or TITLE_BOTTOM)
	end
end

-- Błysk przebiegający po przycisku (rytm: co ile sekund)
function ShopLook.button(button: GuiObject, every: number?)
	if not button:FindFirstChild("Shine") then
		UiFx.shine(button, every or 2.8)
	end
end

-- Karta rośnie pod kursorem. Zwraca jej UIScale (ten sam używa cascade).
function ShopLook.hover(target: GuiObject, amount: number?): UIScale
	local found = target:FindFirstChildOfClass("UIScale")
	local scale: UIScale = if found then found else Instance.new("UIScale")
	scale.Parent = target
	local grow = 1 + (amount or 0.035)
	target.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = grow }):Play()
	end)
	target.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.18), { Scale = 1 }):Play()
	end)
	return scale
end

-- Karty wskakują po kolei (wołać przy otwarciu okna). Pomija niewidoczne.
function ShopLook.cascade(items: { GuiObject }, step: number?, from: number?)
	local index = 0
	for _, item in items do
		if item.Visible then
			index += 1
			local found = item:FindFirstChildOfClass("UIScale")
			local scale: UIScale = if found then found else Instance.new("UIScale")
			scale.Parent = item
			UiFx.popIn(scale, 1, from or 0.55, (step or 0.05) * index)
		end
	end
end

-- Dźwięk otwarcia okna (jak sklep)
function ShopLook.openSound()
	UiFx.sound("whoosh", 0.35)
end

-- Kołysanie ikony w górę i w dół
function ShopLook.bob(icon: GuiObject, amplitude: number?, period: number?)
	UiFx.bob(icon, amplitude or 4, period or 2.3)
end

return ShopLook
