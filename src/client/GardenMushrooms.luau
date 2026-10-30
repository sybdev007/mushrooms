--!strict
-- Grzyby w ogródkach wyglądają tak samo jak w lesie: serwer stawia na grządce tylko znacznik
-- (Model z niewidzialną częścią, tag "GardenMushroom", atrybuty Species / Variant / Tags), a tutaj
-- każdy gracz rysuje na nim grzyba kodem z MushroomView: ten sam kształt gatunku, warianty, cechy,
-- aury, snopy światła i zarodniki. Model trafia do środka znacznika, więc znika razem z nim,
-- a scenka kradzieży (TheftCutscene) kopiuje go jak wcześniej.
-- Te grzyby są tylko do oglądania: nie da się ich zebrać jak w lesie (sadzenie i kradzież mają prompty).

local CollectionService = game:GetService("CollectionService")

local MushroomView = require(script.Parent.MushroomView)

local GardenMushrooms = {}

local TAG = "GardenMushroom"
local ids: { [Instance]: string } = {}
local counter = 0
-- Grzyb mieści się na grządce (skrzynia 3,4 studa) i pod tabliczką z dochodem (GardenService.slotLabel)
local FIT = Vector2.new(3.2, 3.4)

local function infoOf(marker: Model): MushroomView.MushroomInfo?
	local root = marker.PrimaryPart or marker:FindFirstChildWhichIsA("BasePart")
	local species = marker:GetAttribute("Species")
	if not root or typeof(species) ~= "string" then
		return nil
	end
	local variant = marker:GetAttribute("Variant")
	local tagsText = marker:GetAttribute("Tags")
	local tags: { string }? = nil
	if typeof(tagsText) == "string" and tagsText ~= "" then
		tags = string.split(tagsText, ",")
	end
	counter += 1
	return {
		id = "garden_" .. counter,
		position = root.Position,
		species = species,
		variant = if typeof(variant) == "string" and variant ~= "" then variant else nil,
		tags = tags,
	}
end

local function added(marker: Instance)
	if not marker:IsA("Model") or ids[marker] then
		return
	end
	-- Przy StreamingEnabled część znacznika może dojść chwilę później
	if not (marker.PrimaryPart or marker:FindFirstChildWhichIsA("BasePart")) then
		marker:WaitForChild("Root", 10)
		if not marker.Parent or ids[marker] then
			return
		end
	end
	local info = infoOf(marker)
	if not info then
		return
	end
	ids[marker] = info.id
	-- Wyrasta tylko świeżo posadzony (atrybut Fresh od serwera); przy wejściu do gry stoi od razu
	local fresh = marker:GetAttribute("Fresh") == true
	MushroomView.add({ info }, { decorative = true, parent = marker :: Instance, grow = fresh, fit = FIT })
end

local function removed(marker: Instance)
	local id = ids[marker]
	if id then
		ids[marker] = nil
		MushroomView.forget(id)
	end
end

function GardenMushrooms.start()
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(marker)
		task.spawn(added, marker)
	end)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(removed)
	for _, marker in CollectionService:GetTagged(TAG) do
		task.spawn(added, marker)
	end
end

return GardenMushrooms
