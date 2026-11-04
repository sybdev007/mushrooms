--!strict
-- Kotły Sabatu na Łysej Górze (tag "SabbathCauldron", World/Mountain): u każdego gracza bulgoczą
-- (dźwięk „cauldron” w świecie, cichnie z odległością). Dźwięk idzie przez Audio, więc słucha
-- suwaka efektów w ustawieniach. Kocioł, który wypadnie ze streamingu, milknie razem z nim.

local CollectionService = game:GetService("CollectionService")

local Audio = require(script.Parent.Audio)

local SabbathView = {}

local sounds: { [Instance]: Sound } = {}

local function track(model: Instance)
	if sounds[model] then
		return
	end
	local brew = model:FindFirstChild("Brew", true)
	if not (brew and brew:IsA("BasePart")) then
		-- Przy StreamingEnabled części kotła mogą dojść chwilę po samym modelu
		local connection: RBXScriptConnection? = nil
		connection = model.DescendantAdded:Connect(function(child)
			if child.Name == "Brew" and child:IsA("BasePart") and connection then
				connection:Disconnect()
				track(model)
			end
		end)
		return
	end
	local sound = Audio.loop("cauldron", 0.55)
	if not sound then
		return
	end
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 5
	sound.RollOffMaxDistance = 36
	sound.PlaybackSpeed = 0.9 + math.random() * 0.2 -- każdy kocioł trochę inaczej
	sound.TimePosition = math.random() * 3
	sound.Parent = brew
	sounds[model] = sound
end

local function untrack(model: Instance)
	local sound = sounds[model]
	if sound then
		sounds[model] = nil
		sound:Destroy()
	end
end

for _, model in CollectionService:GetTagged("SabbathCauldron") do
	track(model)
end
CollectionService:GetInstanceAddedSignal("SabbathCauldron"):Connect(track)
CollectionService:GetInstanceRemovedSignal("SabbathCauldron"):Connect(untrack)

return SabbathView
