--!strict
-- Wygląd i teksty ekranu wczytywania. Ten moduł leży w ReplicatedFirst, bo ekran rusza, zanim
-- klient dostanie resztę gry (Shared/Config, tabelę tłumaczeń GameStrings). Dlatego teksty PL/EN
-- i numery obrazków są tutaj, a nie w Config/CSV.
--
-- ACTIVE przełącza motyw: "halloween" (dynia nad paskiem) albo "forest" (grzybek-skoczek i kiełki).
-- Grafiki: assets/loading/ (rysuje je tools/loading_art.py). Pusty numer obrazka = ekran działa
-- dalej, tylko bez tła / z emoji zamiast dyni i grzybka.

local LoadingTheme = {}

LoadingTheme.ACTIVE = "halloween"

export type Text = { pl: string, en: string }

export type Theme = {
	background: string,
	backdrop: Color3, -- kolor pod tłem, zanim obrazek się wczyta
	runner: "pumpkin" | "mushroom",
	fallbackRunner: string, -- emoji, gdy arkusz jeszcze nie jest wgrany
	titleTop: Color3,
	titleBottom: Color3,
	badge: Text,
	badgeColor: Color3,
	track: Color3,
	fillFrom: Color3,
	fillTo: Color3,
	glow: Color3, -- poświata biegacza i główki paska
	particles: { Color3 },
	particleKind: "embers" | "fireflies",
	bats: boolean,
	stages: { [string]: Text },
	tips: { Text },
}

-- Arkusz assets/loading/loading-sprites.png: 4 x 2 komórki po 256 px (pusty numer = emoji zamiast dyni i grzybka)
LoadingTheme.SPRITES = "rbxassetid://131022446736089"
LoadingTheme.CELL = 256
LoadingTheme.CELLS = {
	pumpkin = Vector2.new(0, 0),
	pumpkinGlow = Vector2.new(1, 0),
	mushroom = Vector2.new(2, 0),
	mushroomGlow = Vector2.new(3, 0),
	sproutCyan = Vector2.new(0, 1),
	sproutGold = Vector2.new(1, 1),
	sproutPink = Vector2.new(2, 1),
	glow = Vector2.new(3, 1),
}

-- Wskazówki prawdziwe w każdym motywie (sprawdzone z mechaniką gry)
local SHARED_TIPS: { Text } = {
	{
		pl = "Pilnuj oleju w latarni. Gdy zgaśnie, ciemność zabierze część grzybów z koszyka.",
		en = "Watch your lantern oil. When it runs out, the dark takes some mushrooms from your basket.",
	},
	{
		pl = "Grzyby posadzone w ogródku zarabiają monety, nawet gdy nie grasz.",
		en = "Mushrooms planted in your garden earn coins even while you're offline.",
	},
	{
		pl = "Stój przy swoim ogródku, a złodziej nic z niego nie wyniesie.",
		en = "Stay close to your garden and thieves can't take anything from it.",
	},
	{
		pl = "Im głębiej w lesie, tym częściej trafiają się mutacje.",
		en = "The deeper you go into the forest, the more often mutations appear.",
	},
	{
		pl = "Nożyk i mikstura szczęścia działają tylko na twoje grzyby, a Wysyp na cały serwer.",
		en = "The knife and the luck potion boost only your mushrooms. Mushroom Boom boosts the whole server.",
	},
}

local function withTips(extra: { Text }): { Text }
	local list = table.clone(extra)
	for _, tip in SHARED_TIPS do
		table.insert(list, tip)
	end
	return list
end

LoadingTheme.themes = {
	halloween = {
		background = "rbxassetid://100478588810107", -- assets/loading/bg-halloween.jpg
		backdrop = Color3.fromRGB(26, 14, 38),
		runner = "pumpkin",
		fallbackRunner = "🎃",
		titleTop = Color3.fromRGB(255, 230, 130),
		titleBottom = Color3.fromRGB(255, 132, 34),
		badge = { pl = "🎃 Halloween w lesie", en = "🎃 Halloween in the forest" },
		badgeColor = Color3.fromRGB(122, 52, 170),
		track = Color3.fromRGB(46, 22, 52),
		fillFrom = Color3.fromRGB(255, 196, 64),
		fillTo = Color3.fromRGB(255, 106, 26),
		glow = Color3.fromRGB(255, 150, 40),
		particles = { Color3.fromRGB(255, 170, 60), Color3.fromRGB(255, 214, 110), Color3.fromRGB(255, 120, 40) },
		particleKind = "embers",
		bats = true,
		stages = {
			connect = { pl = "Rzeźbimy dynie", en = "Carving pumpkins" },
			world = { pl = "Zapalamy latarnie w lesie", en = "Lighting the forest lanterns" },
			assets = { pl = "Budzimy duchy", en = "Waking the ghosts" },
			save = { pl = "Szukamy twojego koszyka", en = "Finding your basket" },
			done = { pl = "Do lasu!", en = "Into the woods!" },
		},
		tips = withTips({
			{
				pl = "Sprzedane dyniowe grzyby dają cukierki. Wydasz je w kotle przy chatce!",
				en = "Sold pumpkin mushrooms give candy. Spend it at the cauldron by the cabin!",
			},
			{
				pl = "W czasie Halloween co trzecia noc to Noc Dziadów: dyniowe grzyby rosną wtedy częściej.",
				en = "During Halloween every third night is Forefathers' Eve, when pumpkin mushrooms grow more often.",
			},
		}),
	} :: Theme,
	forest = {
		background = "rbxassetid://76824083718605", -- assets/loading/bg-forest.jpg
		backdrop = Color3.fromRGB(10, 18, 40),
		runner = "mushroom",
		fallbackRunner = "🍄",
		titleTop = Color3.fromRGB(190, 250, 255),
		titleBottom = Color3.fromRGB(120, 150, 255),
		badge = { pl = "Zbieraj grzyby, pilnuj latarni", en = "Pick mushrooms, keep your lantern lit" },
		badgeColor = Color3.fromRGB(40, 96, 150),
		track = Color3.fromRGB(16, 30, 56),
		fillFrom = Color3.fromRGB(120, 245, 255),
		fillTo = Color3.fromRGB(176, 120, 255),
		glow = Color3.fromRGB(110, 230, 255),
		particles = { Color3.fromRGB(255, 236, 120), Color3.fromRGB(190, 255, 140), Color3.fromRGB(140, 240, 255) },
		particleKind = "fireflies",
		bats = false,
		stages = {
			connect = { pl = "Wchodzimy do lasu", en = "Entering the forest" },
			world = { pl = "Zapalamy latarnie", en = "Lighting the lanterns" },
			assets = { pl = "Grzyby wychodzą spod liści", en = "Mushrooms are popping up" },
			save = { pl = "Szukamy twojego koszyka", en = "Finding your basket" },
			done = { pl = "Do lasu!", en = "Into the woods!" },
		},
		tips = withTips({}),
	} :: Theme,
}

function LoadingTheme.get(id: string?): Theme
	return LoadingTheme.themes[id or LoadingTheme.ACTIVE] or LoadingTheme.themes.halloween
end

-- Język jak w grze (Localize.detectLocale): z konta gracza, polski albo angielski
function LoadingTheme.locale(): string
	local Players = game:GetService("Players")
	local LocalizationService = game:GetService("LocalizationService")
	local player = Players.LocalPlayer
	local id = if player then player.LocaleId else ""
	if id == nil or id == "" then
		id = LocalizationService.RobloxLocaleId
	end
	return if string.lower(string.sub(id, 1, 2)) == "pl" then "pl" else "en"
end

function LoadingTheme.text(value: Text, locale: string): string
	return if locale == "pl" then value.pl else value.en
end

return LoadingTheme
