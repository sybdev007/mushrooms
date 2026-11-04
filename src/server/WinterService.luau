--!strict
-- Zima: choinka z prezentami przy chatce (WinterDecor). Choinka bierze płatki z kieszeni
-- (data.flakeBag) i losuje wynik (Winter.rollGift):
--   prezent: monety, mikstura szczęścia, garść płatków albo skórka (lodowa latarnia, laska cukrowa);
--   psikus: tylko wygląd na chwilę (głowa bałwana, latarnia świecąca lodowym światłem, śnieżyca wokół
--   gracza, śnieżka w ekran). Psikusy niczego nie zabierają.
-- Wynik idzie do klienta (GiftResult, okienko i dźwięk w GiftTreeView). Płatki, ścieżkę nagród
-- i kalendarz adwentowy obsługuje ProgressService, zakładanie skórek HalloweenService (wspólne Skins).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Winter = require(Shared.Winter)
local Skins = require(Shared.Skins)
local Progress = require(Shared.Progress)
local Remotes = require(Shared.Remotes)
local DataService = require(script.Parent.DataService)
local Ledger = require(script.Parent.Ledger)

type Data = DataService.Data

export type Api = {
	getData: (Player) -> Data?,
	notify: (Player, string, { any }?, string?) -> (),
	pushState: (Player) -> (),
	applyStats: (Player) -> (), -- przebudowa latarni i nożyka w dłoni
	refresh: (Player) -> (), -- okna (kieszeń z płatkami, skórki)
}

local WinterService = {}

local GiftResult = Remotes.get("GiftResult")

local api: Api
local lastUse: { [Player]: number } = {}
-- Psikusy w toku: gracz -> rodzaj -> numer (nowszy psikus tego samego rodzaju przedłuża czas)
local tricks: { [Player]: { [string]: number } } = {}

local LANTERN_COLOR = Color3.fromRGB(255, 205, 140) -- jak w GameService.applyCharacterStats
local FROST_COLOR = Color3.fromRGB(150, 220, 255)
local SNOW = Color3.fromRGB(245, 250, 255)
local COAL = Color3.fromRGB(34, 32, 36)
local CARROT = Color3.fromRGB(240, 128, 40)

local function trickToken(player: Player, kind: string): number
	local list = tricks[player]
	if not list then
		list = {}
		tricks[player] = list
	end
	local token = (list[kind] or 0) + 1
	list[kind] = token
	return token
end

local function stillLatest(player: Player, kind: string, token: number): boolean
	local list = tricks[player]
	return list ~= nil and list[kind] == token
end

local function weldedPart(parent: Instance, to: BasePart, name: string, size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = false
	p.Parent = parent
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = to
	weld.Part1 = p
	weld.Parent = p
	return p
end

-- Psikus: śniegowa głowa bałwana z marchewką i cylindrem (wszyscy ją widzą)
local function snowmanHead(player: Player, seconds: number)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not (character and head and head:IsA("BasePart")) then
		return
	end
	local old = character:FindFirstChild("TrickSnowman")
	if old then
		old:Destroy()
	end
	local token = trickToken(player, "snowman")
	local m = Instance.new("Model")
	m.Name = "TrickSnowman"
	local s = head.Size.Y * 1.8
	local base = head.CFrame * CFrame.new(0, s * 0.06, 0)
	weldedPart(m, head, "Ball", Vector3.one * s, base, SNOW, Enum.PartType.Ball)
	local front = base * CFrame.new(0, 0, -s * 0.48)
	for _, x in { -0.18, 0.18 } do
		weldedPart(m, head, "Eye", Vector3.one * s * 0.13, front * CFrame.new(x * s, s * 0.12, 0), COAL, Enum.PartType.Ball)
	end
	-- Marchewka: wąski klin wystający do przodu
	weldedPart(m, head, "Nose", Vector3.new(s * 0.12, s * 0.12, s * 0.45), front * CFrame.new(0, -s * 0.02, -s * 0.18), CARROT)
	for i = -2, 2 do
		weldedPart(m, head, "Smile", Vector3.one * s * 0.08, front * CFrame.new(i * s * 0.08, -s * 0.2 + math.abs(i) * s * 0.03, s * 0.02), COAL, Enum.PartType.Ball)
	end
	local hatBase = base * CFrame.new(0, s * 0.45, 0)
	weldedPart(m, head, "Brim", Vector3.new(s * 0.08, s * 0.9, s * 0.9), hatBase * CFrame.Angles(0, 0, math.rad(90)), COAL, Enum.PartType.Cylinder)
	weldedPart(m, head, "Hat", Vector3.new(s * 0.5, s * 0.58, s * 0.58), hatBase * CFrame.new(0, s * 0.27, 0) * CFrame.Angles(0, 0, math.rad(90)), COAL, Enum.PartType.Cylinder)
	weldedPart(m, head, "Band", Vector3.new(s * 0.1, s * 0.6, s * 0.6), hatBase * CFrame.new(0, s * 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(200, 40, 50), Enum.PartType.Cylinder)
	m.Parent = character
	-- Twarz pod śniegiem się nie przebija
	local face = head:FindFirstChildWhichIsA("Decal")
	if face then
		face.Transparency = 1
	end
	task.delay(seconds, function()
		if not stillLatest(player, "snowman", token) then
			return
		end
		if m.Parent then
			m:Destroy()
		end
		if face and face.Parent then
			face.Transparency = 0
		end
	end)
end

-- Psikus: latarnia świeci lodowym światłem (światło widzą wszyscy; szybkę w dłoni własny klient
-- barwi według atrybutu FrostLantern)
local function frostLantern(player: Player, seconds: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and root) then
		return
	end
	local token = trickToken(player, "frost")
	local attachment = root:FindFirstChild("LanternAttachment")
	local light = attachment and attachment:FindFirstChild("Lantern")
	if light and light:IsA("PointLight") then
		light.Color = FROST_COLOR
	end
	character:SetAttribute("FrostLantern", os.time() + seconds)
	task.delay(seconds, function()
		if not stillLatest(player, "frost", token) or not character.Parent then
			return
		end
		character:SetAttribute("FrostLantern", nil)
		local current = root:FindFirstChild("LanternAttachment")
		local currentLight = current and current:FindFirstChild("Lantern")
		if currentLight and currentLight:IsA("PointLight") then
			currentLight.Color = LANTERN_COLOR
		end
	end)
end

-- Psikus: śnieżyca kręci się wokół gracza
local function flurry(player: Player, seconds: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and root) then
		return
	end
	local old = root:FindFirstChild("TrickFlurry")
	if old then
		old:Destroy()
	end
	local token = trickToken(player, "flurry")
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "TrickFlurry"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 230, 255))
	emitter.LightEmission = 0.6
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(0.5, 0.45), NumberSequenceKeypoint.new(1, 0.2) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.1), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(1.2, 2)
	emitter.Speed = NumberRange.new(3, 6)
	emitter.SpreadAngle = Vector2.new(180, 30)
	emitter.RotSpeed = NumberRange.new(-180, 180)
	emitter.Acceleration = Vector3.new(0, -2, 0)
	emitter.Rate = 40
	emitter.Parent = root
	task.delay(seconds, function()
		if stillLatest(player, "flurry", token) and emitter.Parent then
			emitter:Destroy()
		end
	end)
end

local function grantSkin(player: Player, data: Data, skin: string)
	local def = Winter.getSkin(skin)
	if not def then
		return
	end
	if not table.find(data.skins, skin) then
		table.insert(data.skins, skin)
	end
	-- Nowa skórka od razu w dłoni
	;(data.equipped :: any)[def.slot] = skin
	api.applyStats(player)
end

-- Jedno wrzucenie płatków pod choinkę
local function useTree(player: Player)
	local data = api.getData(player)
	if not data or not Winter.active(os.time()) then
		return
	end
	local now = os.clock()
	local tree = Config.Winter.tree
	if now - (lastUse[player] or 0) < tree.cooldown then
		return
	end
	lastUse[player] = now
	if data.flakeBag < tree.cost then
		api.notify(player, "MSG_GIFT_NEED", { tree.cost, data.flakeBag })
		return
	end
	data.flakeBag -= tree.cost

	local outcome = Winter.rollGift(math.random())
	local scale = Progress.rewardScale(data.caveUnlocked, data.swampUnlocked, data.mountainUnlocked)
	local result: { [string]: any } = { id = outcome.id, seconds = outcome.seconds }
	if outcome.id == "coins" then
		local coins = math.floor((outcome.scale or 1) * scale)
		Ledger.earn(player, data, coins, "Gameplay", "GiftTree")
		result.amount = coins
	elseif outcome.id == "luck" then
		local seconds = outcome.seconds or 300
		data.luckUntil = math.max(os.time(), data.luckUntil) + seconds
		result.amount = math.floor(seconds / 60)
	elseif outcome.id == "flakes" then
		local amount = outcome.amount or 0
		data.flakeBag += amount
		result.amount = amount
	elseif outcome.skin then
		local def = Winter.getSkin(outcome.skin)
		if Skins.owns(data.skins, data.stats, outcome.skin) or not def then
			-- Już ją ma: zamiast skórki worek monet
			local coins = math.floor(tree.duplicateScale * scale)
			Ledger.earn(player, data, coins, "Gameplay", "GiftTree")
			result.id = "skin_dupe"
			result.amount = coins
			result.skinKey = if def then def.key else nil
		else
			grantSkin(player, data, outcome.skin)
			result.skinKey = (def :: any).key
			-- Ogłoszenie dla całego serwera: ktoś wylosował skórkę
			for _, other in Players:GetPlayers() do
				if other ~= player then
					api.notify(other, "MSG_GIFT_SKIN_ALL", { player.DisplayName }, def.key)
				end
			end
		end
	elseif outcome.id == "trick_snowman" then
		snowmanHead(player, outcome.seconds or 60)
	elseif outcome.id == "trick_frost" then
		frostLantern(player, outcome.seconds or 120)
	elseif outcome.id == "trick_flurry" then
		flurry(player, outcome.seconds or 45)
	end
	result.bag = data.flakeBag
	GiftResult:FireClient(player, result)
	api.pushState(player)
	api.refresh(player)
end

local function bindPrompt(prompt: Instance)
	if prompt:IsA("ProximityPrompt") then
		prompt.Triggered:Connect(useTree)
	end
end

-- Panel DEV: choinka bez podchodzenia (narzędzia Studio nie klikają ProximityPrompt)
function WinterService.dev(player: Player, action: string): boolean
	if action == "giftTree" then
		lastUse[player] = 0
		useTree(player)
		return true
	end
	return false
end

function WinterService.start(serviceApi: Api)
	api = serviceApi
	for _, prompt in CollectionService:GetTagged("GiftTreePrompt") do
		bindPrompt(prompt)
	end
	CollectionService:GetInstanceAddedSignal("GiftTreePrompt"):Connect(bindPrompt)
	Players.PlayerRemoving:Connect(function(player)
		lastUse[player] = nil
		tricks[player] = nil
	end)
end

return WinterService
