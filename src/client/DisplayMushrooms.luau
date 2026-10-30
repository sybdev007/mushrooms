--!strict
-- Grzyby do oglądania (nie do zbierania jak w lesie) wyglądają tak samo jak w lesie: serwer stawia tylko
-- znacznik (Model z niewidzialną częścią "Root", atrybuty Species / Variant / Tags), a tutaj każdy gracz
-- rysuje na nim grzyba kodem z MushroomView: ten sam kształt gatunku, warianty, cechy, aury, snopy
-- światła i zarodniki. Model trafia do środka znacznika, więc znika razem z nim.
--   "GardenMushroom" — grządki w ogródkach (zmniejszone, żeby zmieściły się w skrzyni; scenka kradzieży
--                      TheftCutscene kopiuje je jak wcześniej),
--   "HoardMushroom"  — grzyby odebrane przez strażnika (Leszy, Skarbnik, Utopiec) w jego legowisku.
-- Atrybut "Ground" (Vector3) = punkt na ziemi pod grzybem, gdy Root stoi wyżej (np. przycisk zabrania).
-- Atrybut "Fresh" = świeżo położony: wyrasta z ziemi; inaczej stoi od razu.

local CollectionService = game:GetService("CollectionService")

local MushroomView = require(script.Parent.MushroomView)

local DisplayMushrooms = {}

-- Grzyb mieści się na grządce (skrzynia 3,4 studa) i pod tabliczką z dochodem (GardenService.slotLabel)
DisplayMushrooms.FIT = Vector2.new(3.2, 3.4)

local KINDS: { [string]: { fit: Vector2? } } = {
	GardenMushroom = { fit = DisplayMushrooms.FIT },
	HoardMushroom = { fit = Vector2.new(3.4, 4.6) }, -- w kółku co ok. 3,3 studa (Config.Hoard.radius)
}

local ids: { [Instance]: string } = {}
local counter = 0

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
	local ground = marker:GetAttribute("Ground")
	counter += 1
	return {
		id = "display_" .. counter,
		position = if typeof(ground) == "Vector3" then ground else root.Position,
		species = species,
		variant = if typeof(variant) == "string" and variant ~= "" then variant else nil,
		tags = tags,
	}
end

local function added(marker: Instance, kind: { fit: Vector2? })
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
	MushroomView.add({ info }, {
		decorative = true,
		parent = marker :: Instance,
		grow = marker:GetAttribute("Fresh") == true,
		fit = kind.fit,
	})
end

local function removed(marker: Instance)
	local id = ids[marker]
	if id then
		ids[marker] = nil
		MushroomView.forget(id)
	end
end

function DisplayMushrooms.start()
	for tag, kind in KINDS do
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(marker)
			task.spawn(added, marker, kind)
		end)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(removed)
		for _, marker in CollectionService:GetTagged(tag) do
			task.spawn(added, marker, kind)
		end
	end
end

return DisplayMushrooms
