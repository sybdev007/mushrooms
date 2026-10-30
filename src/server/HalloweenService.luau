--!strict
-- Halloween, etap 2: kocioł „cukierek albo psikus” przy chatce i zakładanie skórek.
-- Kocioł bierze cukierki z kieszeni (data.candyBag) i losuje wynik (Halloween.rollCauldron):
--   nagroda: monety, mikstura szczęścia, garść cukierków albo skórka (dyniowa latarnia, sierp);
--   psikus: tylko wygląd na chwilę (dynia na głowie, zielona latarnia duchów, dusze wokół gracza,
--   duch wyskakujący na ekranie). Psikusy niczego nie zabierają.
-- Wynik idzie do klienta (CauldronResult, okienko i dźwięk w CauldronView).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Halloween = require(Shared.Halloween)
local Progress = require(Shared.Progress)
local Remotes = require(Shared.Remotes)
local DataService = require(script.Parent.DataService)

type Data = DataService.Data

export type Api = {
	getData: (Player) -> Data?,
	notify: (Player, string, { any }?, string?) -> (),
	pushState: (Player) -> (),
	applyStats: (Player) -> (), -- przebudowa latarni i nożyka w dłoni
	refresh: (Player) -> (), -- okna (kieszeń z cukierkami, skórki)
}

local HalloweenService = {}

local CauldronResult = Remotes.get("CauldronResult")
local EquipSkin = Remotes.get("EquipSkin")

local api: Api
local lastUse: { [Player]: number } = {}
-- Psikusy w toku: gracz -> rodzaj -> numer (nowszy psikus tego samego rodzaju przedłuża czas)
local tricks: { [Player]: { [string]: number } } = {}

local LANTERN_COLOR = Color3.fromRGB(255, 205, 140) -- jak w GameService.applyCharacterStats
local GHOST_COLOR = Color3.fromRGB(120, 255, 150)
local PUMPKIN = Color3.fromRGB(226, 110, 24)
local PUMPKIN_DARK = Color3.fromRGB(168, 70, 14)
local PUMPKIN_GLOW = Color3.fromRGB(255, 200, 80)

-- Kolejny psikus tego rodzaju: zwraca numer, a cofnięcie robi tylko ostatni
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

local function weldedPart(parent: Instance, to: BasePart, name: string, size: Vector3, cf: CFrame, color: Color3, neon: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
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

-- Psikus: dynia zamiast głowy (wszyscy ją widzą)
local function pumpkinHead(player: Player, seconds: number)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not (character and head and head:IsA("BasePart")) then
		return
	end
	local old = character:FindFirstChild("TrickPumpkin")
	if old then
		old:Destroy()
	end
	local token = trickToken(player, "pumpkin")
	local m = Instance.new("Model")
	m.Name = "TrickPumpkin"
	local s = head.Size.Y * 1.9
	local base = head.CFrame * CFrame.new(0, s * 0.08, 0)
	weldedPart(m, head, "Body", Vector3.new(s, s * 0.82, s), base, PUMPKIN)
	weldedPart(m, head, "LobeX", Vector3.new(s * 1.08, s * 0.7, s * 0.8), base, PUMPKIN_DARK)
	weldedPart(m, head, "LobeZ", Vector3.new(s * 0.8, s * 0.7, s * 1.08), base, PUMPKIN_DARK)
	weldedPart(m, head, "Stem", Vector3.new(s * 0.16, s * 0.3, s * 0.16), base * CFrame.new(0, s * 0.52, 0) * CFrame.Angles(0, 0, math.rad(-12)), Color3.fromRGB(70, 104, 40))
	local front = base * CFrame.new(0, 0, -s * 0.54 - 0.02)
	for _, x in { -0.2, 0.2 } do
		weldedPart(m, head, "Eye", Vector3.new(s * 0.17, s * 0.17, 0.06), front * CFrame.new(x * s, s * 0.1, 0) * CFrame.Angles(0, 0, math.rad(45)), PUMPKIN_GLOW, true)
	end
	weldedPart(m, head, "Mouth", Vector3.new(s * 0.5, s * 0.12, 0.06), front * CFrame.new(0, -s * 0.17, 0), PUMPKIN_GLOW, true)
	for _, x in { -0.1, 0.1 } do
		weldedPart(m, head, "Tooth", Vector3.new(s * 0.08, s * 0.06, 0.07), front * CFrame.new(x * s, -s * 0.13, -0.01), PUMPKIN)
	end
	m.Parent = character
	-- Twarz pod dynią się nie przebija
	local face = head:FindFirstChildWhichIsA("Decal")
	if face then
		face.Transparency = 1
	end
	task.delay(seconds, function()
		if not stillLatest(player, "pumpkin", token) then
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

-- Psikus: latarnia świeci na zielono jak u duchów (światło widzą wszyscy; szybkę w dłoni
-- własny klient barwi według atrybutu GhostLantern)
local function ghostLantern(player: Player, seconds: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and root) then
		return
	end
	local token = trickToken(player, "ghost")
	local attachment = root:FindFirstChild("LanternAttachment")
	local light = attachment and attachment:FindFirstChild("Lantern")
	if light and light:IsA("PointLight") then
		light.Color = GHOST_COLOR
	end
	character:SetAttribute("GhostLantern", os.time() + seconds)
	task.delay(seconds, function()
		if not stillLatest(player, "ghost", token) or not character.Parent then
			return
		end
		character:SetAttribute("GhostLantern", nil)
		local current = root:FindFirstChild("LanternAttachment")
		local currentLight = current and current:FindFirstChild("Lantern")
		if currentLight and currentLight:IsA("PointLight") then
			currentLight.Color = LANTERN_COLOR
		end
	end)
end

-- Psikus: dusze krążą wokół gracza
local function spirits(player: Player, seconds: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and root) then
		return
	end
	local old = root:FindFirstChild("TrickSpirits")
	if old then
		old:Destroy()
	end
	local token = trickToken(player, "spirits")
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "TrickSpirits"
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(210, 245, 255), Color3.fromRGB(190, 150, 255))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(0.5, 1.4), NumberSequenceKeypoint.new(1, 0.4) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.35), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(1.5, 2.5)
	emitter.Speed = NumberRange.new(2, 3.5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.Acceleration = Vector3.new(0, 1.2, 0)
	emitter.Rate = 8
	emitter.Parent = root
	task.delay(seconds, function()
		if stillLatest(player, "spirits", token) and emitter.Parent then
			emitter:Destroy()
		end
	end)
end

local function grantSkin(player: Player, data: Data, skin: string)
	local def = Halloween.getSkin(skin)
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

-- Jedno wrzucenie cukierków do kotła
local function useCauldron(player: Player)
	local data = api.getData(player)
	if not data or not Halloween.active(os.time()) then
		return
	end
	local now = os.clock()
	local cauldron = Config.Halloween.cauldron
	if now - (lastUse[player] or 0) < cauldron.cooldown then
		return
	end
	lastUse[player] = now
	if data.candyBag < cauldron.cost then
		api.notify(player, "MSG_CAULDRON_NEED", { cauldron.cost, data.candyBag })
		return
	end
	data.candyBag -= cauldron.cost

	local outcome = Halloween.rollCauldron(math.random())
	local scale = Progress.rewardScale(data.caveUnlocked, data.swampUnlocked)
	local result: { [string]: any } = { id = outcome.id, seconds = outcome.seconds }
	if outcome.id == "coins" then
		local coins = math.floor((outcome.scale or 1) * scale)
		data.coins += coins
		result.amount = coins
	elseif outcome.id == "luck" then
		local seconds = outcome.seconds or 300
		data.luckUntil = math.max(os.time(), data.luckUntil) + seconds
		result.amount = math.floor(seconds / 60)
	elseif outcome.id == "candy" then
		local amount = outcome.amount or 0
		data.candyBag += amount
		result.amount = amount
	elseif outcome.skin then
		local def = Halloween.getSkin(outcome.skin)
		if Halloween.ownsSkin(data.skins, data.stats.candy, outcome.skin) or not def then
			-- Już ją ma: zamiast skórki worek monet
			local coins = math.floor(cauldron.duplicateScale * scale)
			data.coins += coins
			result.id = "skin_dupe"
			result.amount = coins
			result.skinKey = if def then def.key else nil
		else
			grantSkin(player, data, outcome.skin)
			result.skinKey = (def :: any).key
			-- Ogłoszenie dla całego serwera: ktoś wylosował skórkę
			for _, other in Players:GetPlayers() do
				if other ~= player then
					api.notify(other, "MSG_CAULDRON_SKIN_ALL", { player.DisplayName }, def.key)
				end
			end
		end
	elseif outcome.id == "trick_pumpkin" then
		pumpkinHead(player, outcome.seconds or 60)
	elseif outcome.id == "trick_ghostlight" then
		ghostLantern(player, outcome.seconds or 120)
	elseif outcome.id == "trick_spirits" then
		spirits(player, outcome.seconds or 45)
	end
	result.bag = data.candyBag
	CauldronResult:FireClient(player, result)
	api.pushState(player)
	api.refresh(player)
end

local function onEquip(player: Player, slot: unknown, id: unknown)
	local data = api.getData(player)
	if not data or typeof(slot) ~= "string" or typeof(id) ~= "string" or not table.find(Halloween.SLOTS, slot) then
		return
	end
	if id ~= "" then
		local def = Halloween.getSkin(id)
		if not def or def.slot ~= slot or not Halloween.ownsSkin(data.skins, data.stats.candy, id) then
			return
		end
	end
	;(data.equipped :: any)[slot] = id
	api.applyStats(player)
	api.refresh(player)
end

local function bindPrompt(prompt: Instance)
	if prompt:IsA("ProximityPrompt") then
		prompt.Triggered:Connect(useCauldron)
	end
end

-- Panel DEV: kocioł bez podchodzenia (narzędzia Studio nie klikają ProximityPrompt)
function HalloweenService.dev(player: Player, action: string): boolean
	if action == "cauldron" then
		lastUse[player] = 0
		useCauldron(player)
		return true
	end
	return false
end

function HalloweenService.start(serviceApi: Api)
	api = serviceApi
	EquipSkin.OnServerEvent:Connect(onEquip)
	for _, prompt in CollectionService:GetTagged("CauldronPrompt") do
		bindPrompt(prompt)
	end
	CollectionService:GetInstanceAddedSignal("CauldronPrompt"):Connect(bindPrompt)
	Players.PlayerRemoving:Connect(function(player)
		lastUse[player] = nil
		tricks[player] = nil
	end)
end

return HalloweenService
