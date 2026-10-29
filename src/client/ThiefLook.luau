--!strict
-- Przebranie złodziejaszka dla aktora w cutscence (klon awatara gracza):
--   własna głowa (każdy awatar wygląda tak samo, bez twarzy gracza), czarna maska bandyty z ruchomymi oczami,
--   brwi, nos, zarost i mimika (uśmieszek / szeroki uśmiech / „O” ze strachu / „ćśś”), czapka-bini,
--   koszulka w biało-czarne paski, czarne rękawiczki, dżinsy i jutowy worek z „$” na plecach.

local ThiefLook = {}

export type Rig = {
	pupils: { Frame },
	eyes: { Frame },
	mouths: { [string]: GuiObject },
	brows: { Frame },
	head: BasePart,
	look: Vector2,
	costume: Model, -- części kostiumu (osobny model, żeby Humanoid klonu ich nie przeskalował)
}

local SKIN = Color3.fromRGB(236, 190, 150)
local MASK = Color3.fromRGB(24, 24, 30)
local SHIRT = Color3.fromRGB(30, 30, 38)
local STRIPE = Color3.fromRGB(238, 236, 230)
local JEANS = Color3.fromRGB(52, 62, 104)
local GLOVE = Color3.fromRGB(22, 22, 26)
local BEANIE = Color3.fromRGB(48, 48, 58)
local SACK = Color3.fromRGB(196, 156, 100)
local ROPE = Color3.fromRGB(120, 84, 48)

local function weldTo(base: BasePart, p: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = base
	w.Part1 = p
	w.Parent = p
end

local function part(model: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, base: BasePart, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.Parent = model
	weldTo(base, p)
	return p
end

local function frame(parent: Instance, pos: UDim2, size: UDim2, color: Color3, round: number?): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = pos
	f.Size = size
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	if round then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(round, 0)
		c.Parent = f
	end
	f.Parent = parent
	return f
end

local function surface(p: BasePart, face: Enum.NormalId): SurfaceGui
	local g = Instance.new("SurfaceGui")
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 120
	g.LightInfluence = 1
	g.Brightness = 1
	g.ClipsDescendants = true
	g.Parent = p
	return g
end

function ThiefLook.dress(clone: Model): Rig?
	local root = clone:FindFirstChild("HumanoidRootPart")
	local oldHead = clone:FindFirstChild("Head") :: BasePart?
	local torso = (clone:FindFirstChild("UpperTorso") or clone:FindFirstChild("Torso")) :: BasePart?
	if not oldHead or not torso then
		return nil
	end
	-- Precz z ubraniem, akcesoriami i twarzą gracza
	for _, d in clone:GetDescendants() do
		if d:IsA("Shirt") or d:IsA("Pants") or d:IsA("ShirtGraphic") or d:IsA("Accessory") or d:IsA("BodyColors") then
			d:Destroy()
		end
	end
	for _, d in oldHead:GetDescendants() do
		if d:IsA("Decal") or d:IsA("SurfaceAppearance") then
			d:Destroy()
		end
	end
	oldHead.Transparency = 1
	-- Kostium w osobnym modelu (spawany z ciałem). W modelu postaci Humanoid przeskalowałby dodane części.
	local costume = Instance.new("Model")
	costume.Name = clone.Name .. "Costume"

	-- Kolory ciała: paski na koszulce dokładamy osobno, ręce w rękawiczkach, dżinsy
	for _, p in clone:GetChildren() do
		if p:IsA("BasePart") and p ~= root and p ~= oldHead then
			local n = p.Name
			if n:find("Hand") or n:find("LowerArm") or n:find("Foot") then
				p.Color = GLOVE
			elseif n:find("Leg") or n == "LowerTorso" then
				p.Color = JEANS
			else
				p.Color = SHIRT
			end
			if p:IsA("MeshPart") then
				pcall(function()
					(p :: any).TextureID = ""
				end)
			end
		end
	end

	-- ===== Głowa =====
	local ts = torso.Size
	local k = math.clamp(ts.X / 2, 0.8, 1.3)
	local hs = Vector3.new(1.25, 1.18, 1.18) * k
	local head = part(costume, "ThiefHead", hs, oldHead.CFrame, SKIN, oldHead)
	-- Zarost, brwi i usta na twarzy
	local face = surface(head, Enum.NormalId.Front)
	local stubble = frame(face, UDim2.fromScale(0.5, 0.8), UDim2.fromScale(0.86, 0.42), Color3.fromRGB(118, 96, 84), 0.35)
	stubble.BackgroundTransparency = 0.72
	local brows: { Frame } = {}
	for i, x in { 0.3, 0.7 } do
		local b = frame(face, UDim2.fromScale(x, 0.17), UDim2.fromScale(0.26, 0.06), Color3.fromRGB(56, 38, 28), 1)
		b.Rotation = if i == 1 then 14 else -14
		table.insert(brows, b)
	end
	local mouths: { [string]: GuiObject } = {}
	-- Chytry uśmieszek w bok
	local smirk = Instance.new("Frame")
	smirk.BackgroundTransparency = 1
	smirk.Size = UDim2.fromScale(1, 1)
	smirk.Parent = face
	frame(smirk, UDim2.fromScale(0.52, 0.74), UDim2.fromScale(0.3, 0.05), Color3.fromRGB(80, 34, 34), 1).Rotation = -8
	frame(smirk, UDim2.fromScale(0.68, 0.705), UDim2.fromScale(0.08, 0.05), Color3.fromRGB(80, 34, 34), 1).Rotation = -40
	mouths.smirk = smirk
	-- Szeroki chciwy uśmiech z zębami
	local grin = frame(face, UDim2.fromScale(0.5, 0.75), UDim2.fromScale(0.5, 0.15), Color3.fromRGB(80, 30, 34), 0.5)
	local teeth = frame(grin, UDim2.fromScale(0.5, 0.26), UDim2.fromScale(0.82, 0.32), Color3.fromRGB(250, 250, 245), 0.3)
	local _ = teeth
	mouths.grin = grin
	-- „O” ze strachu
	local o = frame(face, UDim2.fromScale(0.5, 0.77), UDim2.fromScale(0.16, 0.2), Color3.fromRGB(70, 24, 28), 1)
	mouths.o = o
	-- „Ćśś”: zaciśnięte usta w dzióbek
	local shh = frame(face, UDim2.fromScale(0.5, 0.75), UDim2.fromScale(0.1, 0.08), Color3.fromRGB(110, 46, 46), 1)
	mouths.shh = shh
	for name, m in mouths do
		m.Visible = name == "smirk"
	end
	-- Nos (trochę wystaje, daje bryłę)
	part(costume, "Nose", Vector3.new(0.2, 0.2, 0.14) * k, head.CFrame * CFrame.new(0, -0.06 * k, -hs.Z / 2 - 0.06 * k), Color3.fromRGB(222, 168, 128), head)

	-- Maska bandyty: pasek dookoła głowy, oczy w otworach i dwa końce zawiązane z tyłu
	local band = part(costume, "Mask", Vector3.new(hs.X + 0.05, 0.34 * k, hs.Z + 0.05), head.CFrame * CFrame.new(0, 0.12 * k, 0), MASK, head)
	local bandGui = surface(band, Enum.NormalId.Front)
	local eyes: { Frame } = {}
	local pupils: { Frame } = {}
	for _, x in { 0.31, 0.69 } do
		local eye = frame(bandGui, UDim2.fromScale(x, 0.5), UDim2.fromScale(0.2, 0.62), Color3.fromRGB(252, 252, 248), 1)
		eye.ClipsDescendants = true
		local pupil = frame(eye, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.5, 0.6), Color3.fromRGB(18, 18, 22), 1)
		-- Błysk w oku
		frame(pupil, UDim2.fromScale(0.68, 0.3), UDim2.fromScale(0.3, 0.3), Color3.new(1, 1, 1), 1)
		table.insert(eyes, eye)
		table.insert(pupils, pupil)
	end
	for _, side in { -1, 1 } do
		local tail = part(costume, "MaskTail", Vector3.new(0.1, 0.12, 0.42) * k, head.CFrame * CFrame.new(side * 0.12 * k, 0.1 * k, hs.Z / 2 + 0.18 * k) * CFrame.Angles(math.rad(-25), math.rad(side * 28), 0), MASK, head)
		local _ = tail
	end

	-- Czapka-bini z wywiniętym brzegiem i małym czubkiem
	part(costume, "Beanie", Vector3.new(hs.X + 0.06, 0.46 * k, hs.Z + 0.06), head.CFrame * CFrame.new(0, hs.Y / 2 + 0.1 * k, 0), BEANIE, head, Enum.Material.Fabric)
	part(costume, "BeanieBrim", Vector3.new(hs.X + 0.14, 0.18 * k, hs.Z + 0.14), head.CFrame * CFrame.new(0, hs.Y / 2 - 0.1 * k, 0), Color3.fromRGB(36, 36, 44), head, Enum.Material.Fabric)
	part(costume, "BeanieTop", Vector3.new(0.3, 0.16, 0.3) * k, head.CFrame * CFrame.new(0, hs.Y / 2 + 0.38 * k, 0), Color3.fromRGB(36, 36, 44), head, Enum.Material.Fabric)

	-- ===== Koszulka w paski =====
	for _, y in { -0.28, 0.02, 0.32 } do
		part(costume, "Stripe", Vector3.new(ts.X + 0.04, ts.Y * 0.13, ts.Z + 0.04), torso.CFrame * CFrame.new(0, ts.Y * y, 0), STRIPE, torso)
	end
	for _, armName in { "LeftUpperArm", "RightUpperArm" } do
		local arm = clone:FindFirstChild(armName) :: BasePart?
		if arm then
			part(costume, "Stripe", Vector3.new(arm.Size.X + 0.04, arm.Size.Y * 0.2, arm.Size.Z + 0.04), arm.CFrame * CFrame.new(0, arm.Size.Y * 0.05, 0), STRIPE, arm)
		end
	end

	-- ===== Worek na plecach z „$” i pasek przez pierś =====
	local sackCf = torso.CFrame * CFrame.new(ts.X * 0.18, ts.Y * 0.1, ts.Z / 2 + 0.55 * k) * CFrame.Angles(0, 0, math.rad(-12))
	local sack = part(costume, "Sack", Vector3.new(1.5, 1.75, 1.1) * k, sackCf, SACK, torso, Enum.Material.Fabric)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = sack
	part(costume, "SackNeck", Vector3.new(0.5, 0.35, 0.4) * k, sackCf * CFrame.new(0, 0.95 * k, 0), SACK, torso, Enum.Material.Fabric)
	part(costume, "SackRope", Vector3.new(0.6, 0.12, 0.5) * k, sackCf * CFrame.new(0, 0.82 * k, 0), ROPE, torso, Enum.Material.Fabric)
	-- „$” na worku
	local label = part(costume, "SackSign", Vector3.new(0.9, 0.9, 0.05) * k, sackCf * CFrame.new(0, -0.05 * k, 0.53 * k), SACK, torso)
	label.Transparency = 1
	local signGui = surface(label, Enum.NormalId.Back)
	local dollar = Instance.new("TextLabel")
	dollar.BackgroundTransparency = 1
	dollar.Size = UDim2.fromScale(1, 1)
	dollar.Text = "$"
	dollar.TextScaled = true
	dollar.TextColor3 = Color3.fromRGB(110, 70, 36)
	dollar.FontFace = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Heavy)
	dollar.Parent = signGui
	-- Pasek worka przez pierś
	part(costume, "Strap", Vector3.new(0.2, ts.Y * 1.25, 0.06), torso.CFrame * CFrame.new(0, 0, -ts.Z / 2 - 0.03) * CFrame.Angles(0, 0, math.rad(38)), ROPE, torso)

	return { pupils = pupils, eyes = eyes, mouths = mouths, brows = brows, head = head, look = Vector2.zero, costume = costume }
end

-- Mimika: smirk / grin / o / shh
function ThiefLook.expression(rig: Rig, name: string)
	for key, m in rig.mouths do
		m.Visible = key == name
	end
	-- Ze strachu brwi idą w górę, przy chytrym uśmiechu marszczą się do środka
	local up = name == "o"
	for i, b in rig.brows do
		b.Rotation = if up then (if i == 1 then -16 else 16) else (if i == 1 then 14 else -14)
		b.Position = UDim2.fromScale(b.Position.X.Scale, if up then 0.1 else 0.17)
	end
	for _, eye in rig.eyes do
		eye.Size = if up then UDim2.fromScale(0.24, 0.82) else UDim2.fromScale(0.2, 0.62)
	end
end

-- Gdzie patrzą źrenice: x, y w zakresie -1..1 (rozbiegane oczy złodzieja)
function ThiefLook.look(rig: Rig, x: number, y: number)
	rig.look = Vector2.new(x, y)
	for _, pupil in rig.pupils do
		pupil.Position = UDim2.fromScale(0.5 + 0.28 * math.clamp(x, -1, 1), 0.5 + 0.22 * math.clamp(y, -1, 1))
	end
end

return ThiefLook
