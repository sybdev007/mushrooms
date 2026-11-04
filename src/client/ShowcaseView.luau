--!strict
-- Gablota w ogródku po stronie gracza (serwer: ShowcaseService, grzyby rysuje DisplayMushrooms):
-- podpis tylko nad wystawą, na którą patrzysz z bliska (najbliżej środka ekranu), żeby 18 kart naraz
-- nie zasłaniało regału: rzadkość i wariant („★★ LEGENDARNY · 🌈 TĘCZOWY”), nazwa gatunku w kolorze klasy,
-- a przy trofeum ze Znaleziska Nocy data („✨ Znalezisko Nocy · 4.11.2026”).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Economy"))
local ClassColor = require(script.Parent.ClassColor)
local DisplayMushrooms = require(script.Parent.DisplayMushrooms)
local Localize = require(script.Parent.Localize)
local PanelKit = require(script.Parent.PanelKit)
local UiKit = require(script.Parent.UiKit)

local ShowcaseView = {}

local player = Players.LocalPlayer
local RANGE = 16 -- studs od kamery
local AIM_PIXELS = 140 -- tyle pikseli od środka ekranu
local CARD_BG = Color3.fromRGB(14, 10, 20)
local TROPHY = Color3.fromRGB(255, 214, 90)

local gui = Instance.new("BillboardGui")
gui.Name = "ShowcaseLabel"
gui.Size = UDim2.fromOffset(190, 62)
gui.StudsOffset = Vector3.new(0, 2.6, 0)
gui.AlwaysOnTop = true
gui.LightInfluence = 0
gui.ResetOnSpawn = false
gui.Enabled = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local box = Instance.new("Frame")
box.Size = UDim2.fromScale(1, 1)
box.BackgroundColor3 = CARD_BG
box.BackgroundTransparency = 0.12
box.Parent = gui
PanelKit.corner(box, UDim.new(0, 10))
PanelKit.stroke(box, Color3.fromRGB(80, 64, 100), 1.5)

local function line(name: string, y: number, height: number, maxSize: number): TextLabel
	local label = PanelKit.label(box, name, UDim2.new(1, -10, 0, height), UDim2.fromOffset(5, y), maxSize, PanelKit.TEXT, PanelKit.TITLE_FONT)
	label.TextWrapped = true
	UiKit.outline(label, 1.5)
	return label
end
local badges = line("Badges", 4, 15, 13)
local name = line("Name", 19, 22, 19)
local extra = line("Extra", 42, 15, 13)
extra.TextColor3 = TROPHY

local shown: Model? = nil

local function dateText(t: number): string
	local d = os.date("*t", t)
	return string.format("%d.%d.%d", d.day, d.month, d.year)
end

local function show(marker: Model)
	local root = marker.PrimaryPart
	local species = marker:GetAttribute("Species")
	if not root or typeof(species) ~= "string" then
		return
	end
	local variant = marker:GetAttribute("Variant")
	local variantId = if typeof(variant) == "string" and variant ~= "" then variant else nil
	local def = Economy.getSpecies(species)
	badges.Text = DisplayMushrooms.badges(species, variantId)
	name.Text = if def then Localize.t(def.key) else species
	ClassColor.paint(name, species)
	local trophy = marker:GetAttribute("Trophy")
	local hasExtra = typeof(trophy) == "number"
	extra.Text = if hasExtra then "✨ " .. Localize.t("NIGHTFIND_NAME") .. " · " .. dateText(trophy :: number) else ""
	gui.Size = UDim2.fromOffset(190, if hasExtra then 62 else 44)
	badges.Visible = badges.Text ~= ""
	gui.Adornee = root
	gui.Enabled = true
	shown = marker
end

local function update()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	local center = Vector2.new(viewport.X / 2, viewport.Y / 2)
	local best: Model? = nil
	local bestScore = math.huge
	for _, marker in CollectionService:GetTagged("ShowcaseMushroom") do
		local root = marker:IsA("Model") and marker.PrimaryPart
		if root then
			local distance = (root.Position - camera.CFrame.Position).Magnitude
			if distance <= RANGE then
				local point, visible = camera:WorldToViewportPoint(root.Position + Vector3.new(0, 0.8, 0))
				if visible then
					local offset = (Vector2.new(point.X, point.Y) - center).Magnitude
					if offset <= AIM_PIXELS and offset < bestScore then
						best = marker :: Model
						bestScore = offset
					end
				end
			end
		end
	end
	if best then
		if best ~= shown or not gui.Enabled then
			show(best)
		end
	else
		gui.Enabled = false
		shown = nil
	end
end

function ShowcaseView.start()
	gui.Parent = player:WaitForChild("PlayerGui")
	Localize.onChanged(function()
		local current = shown
		if current and current.Parent then
			show(current)
		end
	end)
	task.spawn(function()
		while true do
			update()
			task.wait(0.15)
		end
	end)
end

return ShowcaseView
