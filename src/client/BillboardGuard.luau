--!strict
-- Napis (BillboardGui w PlayerGui) przypięty do części, która może zniknąć ze świata: StreamingEnabled
-- wyrzuca daleki znacznik albo postać innego gracza, postać ginie i czeka na odrodzenie.
-- Roblox rysuje BillboardGui z Adornee poza Workspace w punkcie (0, 0, 0), czyli na polanie przed chatką.
-- Tak wisiały tam tabliczki grządek z dochodem (DisplayMushrooms ma na to własną obsługę),
-- napis „✨ Znalezisko Nocy” i tytuły graczy („Kosmiczny”).
--
-- BillboardGuard.bind(gui, część, chcęPokazać) ustawia Adornee i wyłącza napis w chwili, gdy część
-- opuści Workspace (AncestryChanged, bez czekania na pętlę). Streaming oddaje NOWĄ część, więc moduł
-- powinien co jakiś czas wołać bind z bieżącą częścią (pętla odświeżania), żeby napis wrócił.
-- Moduł, który sam decyduje o widoczności (np. ChestOffers), podaje ją w `wanted` zamiast ustawiać Enabled.

local Workspace = game:GetService("Workspace")

local BillboardGuard = {}

type Bound = { part: BasePart?, wanted: boolean, connection: RBXScriptConnection? }
local bound: { [BillboardGui]: Bound } = {}

-- Czy część jest teraz w świecie (napis na niej rysuje się we właściwym miejscu)
function BillboardGuard.inWorld(part: Instance?): boolean
	return part ~= nil and part:IsDescendantOf(Workspace)
end

local function sync(gui: BillboardGui, entry: Bound)
	gui.Enabled = entry.wanted and BillboardGuard.inWorld(entry.part)
end

function BillboardGuard.bind(gui: BillboardGui, part: BasePart?, wanted: boolean?)
	local entry = bound[gui]
	if not entry then
		local created: Bound = { part = nil, wanted = true, connection = nil }
		bound[gui] = created
		entry = created
		gui.Destroying:Connect(function()
			local old = bound[gui]
			if old and old.connection then
				old.connection:Disconnect()
			end
			bound[gui] = nil
		end)
	end
	local current = entry :: Bound
	current.wanted = wanted ~= false
	if current.part ~= part or gui.Adornee ~= part then
		if current.connection then
			current.connection:Disconnect()
			current.connection = nil
		end
		current.part = part
		gui.Adornee = part
		if part then
			current.connection = part.AncestryChanged:Connect(function()
				sync(gui, current)
			end)
		end
	end
	sync(gui, current)
end

return BillboardGuard
