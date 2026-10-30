--!strict
-- Wygląd Pana Borowika po stronie klienta. Na czas Halloween (atrybut Workspace „Halloween”) staje się
-- Duchem Pana Borowika: cały w odcieniach błękitu (jasne części jasnoniebieskie, ciemne granatowe),
-- bez nóg (zamiast nich mglisty ogon), z delikatną obwódką. Unoszenie się robi MerchantView. Ten sam
-- wygląd dostaje portret w panelu skupu (SellPanel); w portrecie bez ogona, cząsteczek i obwódki.
-- Model buduje serwer: World/Merchant.luau (atrybuty części: Head = głowa, Legs = nogi).
--
-- Duch jest celowo nieprzezroczysty i bez jasnych barw: półprzezroczyste części nakładały się na
-- siebie i migotały przy każdym ruchu (Roblox rysował je raz w tej, raz w innej kolejności), a jasne
-- kolory, wypełnienie obwódki i światło w głowie przepalały się w ciepłym świetle chatki w białą plamę.

local Workspace = game:GetService("Workspace")

local MerchantLook = {}

-- Kolor części ducha zależy od jasności oryginału: od granatu (ciemne) do jasnego błękitu (jasne).
-- Broda, twarz, kapelusz i kurtka mają różne jasności, więc postać zostaje czytelna, a nic nie jest białe.
local DEEP = Color3.fromRGB(24, 62, 130)
local PALE = Color3.fromRGB(108, 190, 248)
local MIST = Color3.fromRGB(104, 152, 200)
local OUTLINE = Color3.fromRGB(140, 220, 255)
local PUPIL = Color3.fromRGB(14, 22, 46)

local function ghostColor(c: Color3): Color3
	local brightness = 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
	return DEEP:Lerp(PALE, math.clamp(brightness * 1.05, 0, 1))
end

-- Oryginalny wygląd części (żeby po Halloween wszystko wróciło)
export type Saved = { [BasePart]: { color: Color3, material: Enum.Material, transparency: number } }

function MerchantLook.isGhost(): boolean
	return Workspace:GetAttribute("Halloween") == true
end

-- Ogon ducha zamiast nóg: trzy coraz mniejsze kłęby mgły pod brzuszkiem, lekko zawinięte do tyłu.
-- Wisi za ladą, więc jego przezroczystość nikomu nie miga przed oczami.
local TAIL = {
	{ offset = Vector3.new(0, 1.72, 0.05), size = Vector3.new(2.05, 1.25, 1.62), transparency = 0.3 },
	{ offset = Vector3.new(0.05, 0.98, 0.22), size = Vector3.new(1.32, 1.02, 1.08), transparency = 0.45 },
	{ offset = Vector3.new(0.18, 0.42, 0.46), size = Vector3.new(0.66, 0.78, 0.58), transparency = 0.6 },
}

local function addTail(model: Model): BasePart?
	local pivot = model:GetPivot()
	local last: BasePart? = nil
	for _, piece in TAIL do
		local p = Instance.new("Part")
		p.Name = "GhostTail"
		p.Size = piece.size
		p.CFrame = pivot * CFrame.new(piece.offset)
		p.Color = MIST
		p.Material = Enum.Material.SmoothPlastic
		p.Transparency = piece.transparency
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
		p:SetAttribute("GhostPart", true)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
		p.Parent = model
		last = p
	end
	return last
end

local function addGlow(model: Model, tailEnd: BasePart?)
	-- Sama cienka obwódka, bez wypełnienia (wypełnienie przepalało ducha na biało)
	local highlight = Instance.new("Highlight")
	highlight.Name = "GhostHighlight"
	highlight.FillTransparency = 1
	highlight.OutlineColor = OUTLINE
	highlight.OutlineTransparency = 0.3
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model
	if tailEnd then
		-- Mgiełka spływająca z ogona (bez własnego światła: rozjaśniało ducha)
		local wisps = Instance.new("ParticleEmitter")
		wisps.Name = "GhostWisps"
		wisps.Texture = "rbxasset://textures/particles/smoke_main.dds"
		wisps.Color = ColorSequence.new(MIST)
		wisps.LightEmission = 0.2
		wisps.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1.4) })
		wisps.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.75), NumberSequenceKeypoint.new(1, 1) })
		wisps.Lifetime = NumberRange.new(1.2, 2.2)
		wisps.Rate = 5
		wisps.Speed = NumberRange.new(0.3, 0.9)
		wisps.SpreadAngle = Vector2.new(35, 35)
		wisps.EmissionDirection = Enum.NormalId.Bottom
		wisps.Parent = tailEnd
	end
end

-- Duch albo zwykły Pan Borowik. `saved` pamięta oryginały między wywołaniami.
-- portrait = true: bez ogona, cząsteczek i obwódki (portret w ViewportFrame)
function MerchantLook.setGhost(model: Model, ghost: boolean, saved: Saved, portrait: boolean?)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "Root" and not d:GetAttribute("GhostPart") then
			local original = saved[d]
			if not original then
				original = { color = d.Color, material = d.Material, transparency = d.Transparency }
				saved[d] = original
			end
			if not ghost then
				d.Color = original.color
				d.Material = original.material
				if d.Name ~= "Eyelid" then
					d.Transparency = original.transparency
				end
			elseif d:GetAttribute("Legs") then
				d.Transparency = 1
			else
				-- Oczy zostają żywe (białka i ciemne źrenice), reszta w błękitach ducha
				local eye = d.Name == "EyeWhite" or d.Name == "EyeShine"
				d.Color = if d.Name == "Pupil" then PUPIL elseif eye then original.color else ghostColor(original.color)
				d.Material = Enum.Material.SmoothPlastic
				if d.Name ~= "Eyelid" then
					d.Transparency = original.transparency
				end
			end
		end
	end
	for _, d in model:GetDescendants() do
		-- (GhostLight: światło z dawnej wersji ducha, sprzątane na wszelki wypadek)
		if d:GetAttribute("GhostPart") or d.Name == "GhostHighlight" or d.Name == "GhostLight" then
			d:Destroy()
		end
	end
	if ghost and not portrait then
		addGlow(model, addTail(model))
	end
end

return MerchantLook
