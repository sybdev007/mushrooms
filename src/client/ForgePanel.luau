--!strict
-- Okno Kuźni Grzybów (Moździerz Zielarki). Po lewej przepisy, po prawej trzy sloty na grzyby z koszyka,
-- podgląd wyniku z szansami i przycisk „Połącz za …”. Sloty same podpowiadają najtańszy pasujący grzyb
-- (żeby nie zużyć przypadkiem cennego okazu); kliknięcie slotu przełącza na następny pasujący.
-- Podgląd liczy Shared/Forge, ale o wyniku decyduje serwer (ForgeService), a okno tylko go pokazuje.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Forge = require(Shared.Forge)
local Remotes = require(Shared.Remotes)
local Audio = require(script.Parent.Audio)
local Localize = require(script.Parent.Localize)
local MushroomArt = require(script.Parent.MushroomArt)
local MutationText = require(script.Parent.MutationText)
local PanelKit = require(script.Parent.PanelKit)
local UiKit = require(script.Parent.UiKit)

local ForgePanel = {}

type Item = Forge.Item

local WIDTH, HEIGHT = 780, 480
local LIST_W = 214
local CARD_W, CARD_H = 146, 176
local RIGHT_X = LIST_W + 24
local OUTLINE = PanelKit.OUTLINE
local GREEN = Color3.fromRGB(86, 186, 84)
local GREY = Color3.fromRGB(120, 108, 98)
local VIOLET = Color3.fromRGB(150, 110, 255)
local LOCKED = Color3.fromRGB(70, 52, 40)

local basket: { Item } = {}
local basketKey = ""
local coins = 0
local access: Forge.Access = {}
local found: { [string]: number } = {}
local selected: string = Config.Forge.recipes[1].id
local slots: { number? } = {}
local waiting = false
local lastSent = 0
local lastResult: { item: Item, lucky: boolean }? = nil

local function t(key: string, args: { any }?): string
	return Localize.t(key, args)
end

local function formatCoins(value: number): string
	local s = tostring(math.floor(value + 0.5))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (formatted:gsub("^ ", ""))
end

local function speciesName(id: string): string
	local species = Economy.getSpecies(id)
	return if species then t(species.key) else id
end

local function variantName(rank: number): string
	local id = Economy.variantOfRank(rank)
	local def = Economy.getVariant(id)
	return if def then t(def.key) else t("ATLAS_FORM_NORMAL")
end

local function tagLabel(id: string): string
	local tag = Economy.getTag(id)
	return if tag then tag.icon .. " " .. t(tag.key) else id
end

-- ===== Okno =====

local window = PanelKit.window({
	name = "Forge",
	parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	width = WIDTH,
	height = HEIGHT,
	ribbon = Color3.fromRGB(120, 80, 200),
	icon = "fertilizer",
	pillIcon = "coins",
	pillColor = Color3.fromRGB(52, 38, 30),
})
local content = window.content

local listHeader = PanelKit.label(content, "RecipesHeader", UDim2.fromOffset(LIST_W, 22), UDim2.fromOffset(4, 34), 18, PanelKit.MUTED)
local collection = PanelKit.label(content, "Collection", UDim2.fromOffset(LIST_W, 18), UDim2.new(0, 4, 1, -26), 15, PanelKit.MUTED, PanelKit.BODY_FONT)

type RecipeButton = { button: TextButton, name: TextLabel, status: TextLabel }
local recipeButtons: { [string]: RecipeButton } = {}
for index, recipe in Config.Forge.recipes do
	local button = Instance.new("TextButton")
	button.Name = "Recipe_" .. recipe.id
	button.Size = UDim2.fromOffset(LIST_W, 50)
	button.Position = UDim2.fromOffset(4, 60 + (index - 1) * 56)
	button.Text = ""
	button.ZIndex = 4
	button.Parent = content
	UiKit.button(button, PanelKit.TAB, { stroke = 2.5, radius = UDim.new(0, 14) })
	local name = PanelKit.label(button, "Name", UDim2.new(1, -16, 0, 24), UDim2.fromOffset(8, 3), 19)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.ZIndex = 5
	local status = PanelKit.label(button, "Status", UDim2.new(1, -16, 0, 16), UDim2.fromOffset(8, 28), 14, PanelKit.MUTED, PanelKit.BODY_FONT)
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.ZIndex = 5
	recipeButtons[recipe.id] = { button = button, name = name, status = status }
end

-- Sloty
type Slot = { card: Frame, title: TextLabel, tag: TextLabel, art: Frame, info: TextLabel, button: TextButton }
local slotViews: { Slot } = {}
for slot = 1, 3 do
	local x = RIGHT_X + (slot - 1) * (CARD_W + 18)
	local card = Instance.new("Frame")
	card.Name = "Slot" .. slot
	card.Size = UDim2.fromOffset(CARD_W, CARD_H)
	card.Position = UDim2.fromOffset(x, 40)
	card.BackgroundColor3 = PanelKit.CARD
	card.ZIndex = 4
	card.Parent = content
	PanelKit.corner(card, UDim.new(0, 16))
	PanelKit.stroke(card, OUTLINE, 2.5)
	local title = PanelKit.label(card, "Title", UDim2.new(1, -12, 0, 22), UDim2.fromOffset(6, 6), 17)
	title.ZIndex = 5
	local tag = PanelKit.label(card, "Tag", UDim2.new(1, -12, 0, 18), UDim2.fromOffset(6, 28), 14, PanelKit.MUTED, PanelKit.BODY_FONT)
	tag.ZIndex = 5
	local art = Instance.new("Frame")
	art.Name = "Art"
	art.BackgroundTransparency = 1
	art.Size = UDim2.fromOffset(84, 84)
	art.AnchorPoint = Vector2.new(0.5, 0)
	art.Position = UDim2.new(0.5, 0, 0, 50)
	art.ZIndex = 5
	art.Parent = card
	local info = PanelKit.label(card, "Info", UDim2.new(1, -12, 0, 34), UDim2.new(0, 6, 1, -40), 14, PanelKit.TEXT, PanelKit.BODY_FONT)
	info.ZIndex = 5
	local button = Instance.new("TextButton")
	button.Name = "Cycle"
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundTransparency = 1
	button.Text = ""
	button.ZIndex = 7
	button.Parent = card
	table.insert(slotViews, { card = card, title = title, tag = tag, art = art, info = info, button = button })
	if slot < 3 then
		local plus = PanelKit.label(content, "Plus", UDim2.fromOffset(18, 30), UDim2.fromOffset(x + CARD_W, 40 + CARD_H / 2 - 15), 26, PanelKit.GOLD)
		plus.Text = "+"
		plus.ZIndex = 5
	end
end

-- Wynik
local resultBox = Instance.new("Frame")
resultBox.Name = "Result"
resultBox.Size = UDim2.fromOffset(3 * CARD_W + 36, 132)
resultBox.Position = UDim2.fromOffset(RIGHT_X, 40 + CARD_H + 12)
resultBox.BackgroundColor3 = PanelKit.BG_DARK
resultBox.ZIndex = 4
resultBox.Parent = content
PanelKit.corner(resultBox, UDim.new(0, 16))
local resultStroke = PanelKit.stroke(resultBox, VIOLET, 2.5)
local resultArt = Instance.new("Frame")
resultArt.Name = "Art"
resultArt.BackgroundTransparency = 1
resultArt.Size = UDim2.fromOffset(108, 108)
resultArt.Position = UDim2.fromOffset(12, 12)
resultArt.ZIndex = 5
resultArt.Parent = resultBox
local resultName = PanelKit.label(resultBox, "Name", UDim2.new(1, -140, 0, 26), UDim2.fromOffset(130, 8), 22)
resultName.TextXAlignment = Enum.TextXAlignment.Left
resultName.ZIndex = 5
local resultTags = PanelKit.label(resultBox, "Tags", UDim2.new(1, -140, 0, 20), UDim2.fromOffset(130, 36), 17, PanelKit.TEXT, PanelKit.BODY_FONT)
resultTags.TextXAlignment = Enum.TextXAlignment.Left
resultTags.ZIndex = 5
local resultOdds = PanelKit.label(resultBox, "Odds", UDim2.new(1, -140, 0, 20), UDim2.fromOffset(130, 60), 16, PanelKit.GOLD, PanelKit.BODY_FONT)
resultOdds.TextXAlignment = Enum.TextXAlignment.Left
resultOdds.ZIndex = 5
local resultValue = PanelKit.label(resultBox, "Value", UDim2.new(1, -140, 0, 18), UDim2.fromOffset(130, 84), 15, PanelKit.GREEN, PanelKit.BODY_FONT)
resultValue.TextXAlignment = Enum.TextXAlignment.Left
resultValue.ZIndex = 5
local resultNote = PanelKit.label(resultBox, "Note", UDim2.new(1, -140, 0, 18), UDim2.fromOffset(130, 106), 13, PanelKit.MUTED, PanelKit.BODY_FONT)
resultNote.TextXAlignment = Enum.TextXAlignment.Left
resultNote.ZIndex = 5

local fuse = Instance.new("TextButton")
fuse.Name = "Fuse"
fuse.Size = UDim2.fromOffset(300, 50)
fuse.Position = UDim2.fromOffset(RIGHT_X, 40 + CARD_H + 12 + 132 + 12)
fuse.Font = PanelKit.TITLE_FONT
fuse.TextScaled = true
fuse.TextColor3 = Color3.new(1, 1, 1)
fuse.ZIndex = 5
fuse.Parent = content
UiKit.button(fuse, GREEN, { stroke = 3, radius = UDim.new(0, 16), gloss = true })
UiKit.outline(fuse, 2.5)
local fusePad = Instance.new("UIPadding")
fusePad.PaddingLeft = UDim.new(0, 12)
fusePad.PaddingRight = UDim.new(0, 12)
fusePad.Parent = fuse
local fuseSize = Instance.new("UITextSizeConstraint")
fuseSize.MaxTextSize = 24
fuseSize.Parent = fuse
local status = PanelKit.label(content, "Status", UDim2.fromOffset(3 * CARD_W + 36 - 312, 50), UDim2.fromOffset(RIGHT_X + 312, 40 + CARD_H + 12 + 132 + 12), 15, PanelKit.MUTED, PanelKit.BODY_FONT)
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextWrapped = true

-- ===== Rysowanie =====

-- Okno odświeża się przy każdym stanie z serwera: grzybka budujemy od nowa tylko, gdy coś się zmieniło
local function drawArt(box: Frame, item: Item?, dim: boolean)
	local key = if item then string.format("%s|%s|%s|%s", item.s, item.v or "", table.concat(item.x or {}, ","), tostring(dim)) else ""
	if box:GetAttribute("ArtKey") == key then
		return
	end
	box:SetAttribute("ArtKey", key)
	for _, child in box:GetChildren() do
		child:Destroy()
	end
	if not item then
		return
	end
	-- Przygaszony podgląd (pusty slot, nieznany wynik) stoi w miejscu; reszta mieni się tylko przy otwartym oknie
	local still = function(): boolean
		return false
	end
	local art = MushroomArt.build(box, item :: any, { active = if dim then still else window.isOpen })
	if art then
		if dim then
			for _, d in art:GetDescendants() do
				if d:IsA("ImageLabel") then
					d.ImageTransparency = 0.6
				end
			end
		end
		return
	end
	-- Bez arkusza grzybków: emotka w kolorze kapelusza
	local icon = PanelKit.label(box, "Icon", UDim2.fromScale(1, 1), UDim2.new(), 60)
	icon.Text = "🍄"
	icon.TextTransparency = if dim then 0.6 else 0
	icon.ZIndex = box.ZIndex + 1
end

local function recipeOf(id: string): Config.ForgeRecipe
	return (Forge.recipe(id) or Config.Forge.recipes[1]) :: Config.ForgeRecipe
end

-- Sloty: zostają wybrane grzyby, jeśli nadal pasują; puste wypełnia najtańszy pasujący
local function fillSlots()
	local recipe = recipeOf(selected)
	local taken: { [number]: boolean } = {}
	for slot = 1, #recipe.inputs do
		local index = slots[slot]
		if index and not taken[index] and Forge.fits(recipe, slot, basket[index]) then
			taken[index] = true
		else
			slots[slot] = nil
		end
	end
	for slot = 1, #recipe.inputs do
		if not slots[slot] then
			local index = Forge.cheapestFor(recipe, slot, basket, taken)
			slots[slot] = index
			if index then
				taken[index] = true
			end
		end
	end
end

local function render()
	if not window.isOpen() then
		return
	end
	window.title.Text = t("FORGE_TITLE")
	window.pillText.Text = formatCoins(coins)
	listHeader.Text = t("FORGE_RECIPES")
	local have, total = 0, #Config.Forge.recipes
	for _, recipe in Config.Forge.recipes do
		if (found[recipe.id] or 0) > 0 then
			have += 1
		end
	end
	collection.Text = t("FORGE_COLLECTION", { have, total })

	for _, recipe in Config.Forge.recipes do
		local view = recipeButtons[recipe.id]
		local open, reason = Forge.unlocked(recipe, access)
		view.name.Text = speciesName(recipe.id)
		view.status.Text = if not open
			then "🔒 " .. t((reason or "FORGE_NEED_SWAMP") .. "_SHORT")
			elseif (found[recipe.id] or 0) > 0 then t("FORGE_IN_COLLECTION")
			else t("FORGE_NEW")
		UiKit.recolor(view.button, if recipe.id == selected then PanelKit.TAB_ON elseif open then PanelKit.TAB else LOCKED)
	end

	local recipe = recipeOf(selected)
	local items: { Item } = {}
	for slot, input in recipe.inputs do
		local view = slotViews[slot]
		local index = slots[slot]
		local item = if index then basket[index] else nil
		view.title.Text = speciesName(input.s)
		view.tag.Text = if input.tag then tagLabel(input.tag) else t("FORGE_ANY_TRAIT")
		if item then
			table.insert(items, item)
			local count = #Forge.candidates(recipe, slot, basket)
			local mutations = MutationText.rich(item.v, item.x)
			view.info.Text = (if mutations ~= "" then mutations .. "\n" else "") .. "💰 " .. formatCoins(Economy.itemValue(item :: any))
				.. (if count > 1 then "  ·  " .. t("FORGE_MORE", { count }) else "")
			drawArt(view.art, item, false)
		else
			view.info.Text = t("FORGE_SLOT_EMPTY")
			drawArt(view.art, { s = input.s, x = if input.tag then { input.tag } else nil }, true)
		end
	end

	-- Wynik i szanse
	local open, reason = Forge.unlocked(recipe, access)
	local quote = if #items == #recipe.inputs then Forge.quote(recipe, items) else nil
	resultName.Text = speciesName(recipe.id)
	local tags = Forge.resultTags(recipe)
	if quote then
		resultTags.Text = MutationText.rich(Economy.variantOfRank(quote.rank), tags)
		if quote.upChance > 0 then
			local up = math.floor(quote.upChance * 100 + 0.5)
			resultOdds.Text = t("FORGE_ODDS", { 100 - up, variantName(quote.rank), up, variantName(quote.upRank) } :: { any })
		else
			resultOdds.Text = t("FORGE_ODDS_ONE", { variantName(quote.rank) })
		end
		resultValue.Text = t("FORGE_WORTH", { formatCoins(quote.value), formatCoins(quote.inputValue) })
		local lost = {}
		for _, id in quote.lostTags do
			table.insert(lost, tagLabel(id))
		end
		resultNote.Text = if #lost > 0 then t("FORGE_LOST", { table.concat(lost, " ") }) else t("FORGE_NO_PLANT")
		drawArt(resultArt, { s = recipe.id, v = Economy.variantOfRank(quote.rank), x = tags }, false)
	else
		resultTags.Text = MutationText.rich(nil, tags)
		resultOdds.Text = ""
		resultValue.Text = ""
		resultNote.Text = t("FORGE_NO_PLANT")
		drawArt(resultArt, { s = recipe.id, x = tags }, (found[recipe.id] or 0) == 0)
	end
	if lastResult and lastResult.item.s == recipe.id then
		resultStroke.Color = if lastResult.lucky then PanelKit.GOLD else VIOLET
	else
		resultStroke.Color = VIOLET
	end

	-- Przycisk i powód, jeśli nie da się połączyć
	local ready = false
	if waiting then
		fuse.Text = t("FORGE_WORKING")
		status.Text = ""
	elseif not open then
		fuse.Text = t("FORGE_LOCKED")
		status.Text = t(reason or "FORGE_NEED_SWAMP")
	elseif not quote then
		fuse.Text = t("FORGE_LOCKED")
		status.Text = t("FORGE_NEED_ITEMS")
	else
		fuse.Text = t("FORGE_COST", { formatCoins(quote.fee) })
		if coins < quote.fee then
			status.Text = t("FORGE_NO_COINS", { formatCoins(quote.fee - coins) })
		else
			ready = true
			status.Text = t("FORGE_HINT")
		end
	end
	UiKit.recolor(fuse, if ready then GREEN else GREY)
	fuse.Active = ready
end

for id, view in recipeButtons do
	view.button.Activated:Connect(function()
		if selected ~= id then
			selected = id
			slots = {}
			fillSlots()
			Audio.play("click")
			render()
		end
	end)
end

for slot, view in slotViews do
	view.button.Activated:Connect(function()
		local recipe = recipeOf(selected)
		local list = Forge.candidates(recipe, slot, basket)
		if #list <= 1 then
			return
		end
		-- Następny pasujący, pomijając grzyby wybrane w innych slotach
		local chosen = slots[slot]
		local current = if chosen then table.find(list, chosen) or 0 else 0
		for step = 1, #list do
			local candidate = list[(current + step - 1) % #list + 1]
			local usedElsewhere = false
			for other, index in slots do
				if other ~= slot and index == candidate then
					usedElsewhere = true
				end
			end
			if not usedElsewhere then
				slots[slot] = candidate
				break
			end
		end
		Audio.play("click")
		render()
	end)
end

fuse.Activated:Connect(function()
	if waiting or not fuse.Active then
		return
	end
	local recipe = recipeOf(selected)
	local chosen = {}
	for slot = 1, #recipe.inputs do
		local index = slots[slot]
		if not index then
			return
		end
		table.insert(chosen, index)
	end
	waiting = true
	render()
	Audio.play("cauldron", { volume = 0.8, duration = 2 })
	Remotes.get("ForgeAction"):FireServer({ kind = "craft", recipe = selected, slots = chosen, key = basketKey })
	-- Serwer zawsze odpowiada (wynik albo powód), ale gdyby odpowiedź zginęła, przycisk nie zostaje zablokowany
	local sentAt = os.clock()
	lastSent = sentAt
	task.delay(6, function()
		if waiting and lastSent == sentAt then
			waiting = false
			render()
		end
	end)
end)

-- ===== Dane z serwera =====

Remotes.get("ForgeView").OnClientEvent:Connect(function(view: any, open: boolean)
	if typeof(view) ~= "table" then
		return
	end
	access = if typeof(view.access) == "table" then view.access else {}
	found = if typeof(view.found) == "table" then view.found else {}
	waiting = false
	if typeof(view.result) == "table" then
		lastResult = { item = view.result, lucky = view.lucky == true }
		slots = {}
		Audio.play(if view.lucky then "levelup" else "shimmer")
		UiKit.burst(resultBox, Vector2.new(70, 66), if view.lucky then 40 else 22, { VIOLET, PanelKit.GOLD, Color3.fromRGB(150, 255, 90) })
	end
	if open then
		-- Gdy wybrany przepis jest zamknięty: pierwszy otwarty, którego gracz jeszcze nie ma w kolekcji
		-- (a jak ma wszystkie, ostatni otwarty)
		if not Forge.unlocked(recipeOf(selected), access) then
			local fresh: string? = nil
			local last: string? = nil
			for _, recipe in Config.Forge.recipes do
				if Forge.unlocked(recipe, access) then
					last = recipe.id
					if not fresh and (found[recipe.id] or 0) == 0 then
						fresh = recipe.id
					end
				end
			end
			selected = fresh or last or selected
		end
		slots = {}
		fillSlots()
		window.setOpen(true)
	end
	fillSlots()
	render()
end)

window.onToggle(function(open: boolean)
	if open then
		fillSlots()
		render()
	else
		waiting = false
	end
end)

Localize.onChanged(render)

function ForgePanel.setBasket(items: { Item }, key: string)
	basket = items
	basketKey = key
	fillSlots()
	render()
end

function ForgePanel.setCoins(value: number)
	coins = value
	render()
end

return ForgePanel
