--!strict
-- Klipy ruchu do cutscenek (klatki kluczowe dla stawów R15, odtwarza CutsceneKit).
-- Kąty w stopniach. Umowa znaków: +rx barku/biodra = ręka/noga do przodu, +rx łokcia = przedramię do przodu,
-- -rx kolana = łydka do tyłu, -rx talii = pochylenie, -rx szyi = patrzy w dół, +ry szyi = patrzy w lewo,
-- +rz prawego barku = ręka w bok (dla lewego -rz). Root.y w dół = kucanie, Root.z dodatnie = do tyłu.
-- Staw pominięty w klatce trzyma poprzednią wartość; ease „back” daje sprężysty przeskok, „snap” szybki start.

local Kit = require(script.Parent.CutsceneKit)
export type Clip = Kit.Clip

local Clips: { [string]: any } = {}

-- Prawa ręka trzyma latarnię lekko z boku (we śnie)
local LANTERN = { RightShoulder = { rx = 16, rz = 12 }, RightElbow = { rx = 26 }, RightWrist = { rx = -10 } }

local function merge(a: { [string]: any }, b: { [string]: any }): { [string]: any }
	local out = {}
	for k, v in a do
		out[k] = v
	end
	for k, v in b do
		out[k] = v
	end
	return out
end

local NEUTRAL = {
	Root = { rx = 0, ry = 0, rz = 0, x = 0, y = 0, z = 0 },
	Waist = { rx = 0, ry = 0, rz = 0 },
	Neck = { rx = 0, ry = 0, rz = 0 },
	LeftShoulder = { rx = 0, ry = 0, rz = 0 },
	LeftElbow = { rx = 0, ry = 0, rz = 0 },
	LeftWrist = { rx = 0, ry = 0, rz = 0 },
	RightShoulder = { rx = 0, ry = 0, rz = 0 },
	RightElbow = { rx = 0, ry = 0, rz = 0 },
	RightWrist = { rx = 0, ry = 0, rz = 0 },
	LeftHip = { rx = 0, ry = 0, rz = 0 },
	LeftKnee = { rx = 0, ry = 0, rz = 0 },
	LeftAnkle = { rx = 0, ry = 0, rz = 0 },
	RightHip = { rx = 0, ry = 0, rz = 0 },
	RightKnee = { rx = 0, ry = 0, rz = 0 },
	RightAnkle = { rx = 0, ry = 0, rz = 0 },
}

-- Przyklęk na lewym kolanie (prawa noga zgięta z przodu)
local KNEEL = {
	Root = { y = -1.15, rx = -4, z = 0.1 },
	RightHip = { rx = 88 },
	RightKnee = { rx = -92 },
	RightAnkle = { rx = 4 },
	LeftHip = { rx = -6 },
	LeftKnee = { rx = -112 },
	LeftAnkle = { rx = 38 },
}

local UP_LEGS = {
	Root = { y = 0, rx = 0, z = 0, x = 0, rz = 0, ry = 0 },
	RightHip = { rx = 0, rz = 0 },
	RightKnee = { rx = 0 },
	RightAnkle = { rx = 0 },
	LeftHip = { rx = 0, rz = 0 },
	LeftKnee = { rx = 0 },
	LeftAnkle = { rx = 0 },
}

-- ===== Sen: zwykły grzyb =====
-- Zauważa grzyba (przechyla głowę), przyklęka, łapie lewą ręką u nasady, kręci nim w dwie strony,
-- wyrywa z „pyk” (zdarzenie pop), ogląda z bliska, kiwa głową z uznaniem i wstaje z grzybem w dłoni.
Clips.pickKneel = {
	length = 3.3,
	keys = {
		{ t = 0, pose = merge(NEUTRAL, LANTERN) },
		{ t = 0.35, pose = { Waist = { rx = 6 }, Neck = { rx = -14, rz = 12 } } },
		{
			t = 0.85,
			ease = "out",
			pose = merge(KNEEL, {
				Waist = { rx = -30, ry = -4 },
				Neck = { rx = -26, rz = 0 },
				LeftShoulder = { rx = 62, rz = -4 },
				LeftElbow = { rx = 20 },
				RightShoulder = { rx = 8, rz = 22 },
				RightElbow = { rx = 30 },
			}),
		},
		{ t = 1.05, pose = { LeftShoulder = { rx = 55 }, LeftElbow = { rx = 26 }, LeftWrist = { rx = -18 } } },
		{ t = 1.25, pose = { Waist = { rx = -30, ry = 7 }, LeftWrist = { rx = -18, ry = 30 } } },
		{ t = 1.45, pose = { Waist = { rx = -30, ry = -7 }, LeftWrist = { ry = -30 } } },
		{
			t = 1.62,
			ease = "back",
			pose = {
				Root = { y = -1.0, rx = -2 },
				Waist = { rx = -12, ry = 0 },
				Neck = { rx = -6 },
				LeftShoulder = { rx = 100, rz = -4 },
				LeftElbow = { rx = 72 },
				LeftWrist = { rx = 0, ry = 0 },
			},
		},
		{ t = 2.05, pose = { LeftShoulder = { rx = 90, rz = 10 }, LeftElbow = { rx = 98 }, Neck = { rx = 8, rz = -16 }, Waist = { rx = -4 } } },
		{ t = 2.35, pose = { Neck = { rx = -4, rz = -10 } } },
		{ t = 2.6, pose = { Neck = { rx = 12, rz = -14 } } },
		{ t = 3.3, pose = merge(UP_LEGS, { Waist = { rx = 0, ry = 0 }, Neck = { rx = 0, rz = 0 }, LeftShoulder = { rx = 62, rz = 0 }, LeftElbow = { rx = 62 } }) },
	},
	events = { { t = 1.62, name = "pop" }, { t = 2.35, name = "sniff" } },
}

-- Rzut grzyba przez ramię do plecaka (zdarzenie toss) i mały podskok z zadowolenia
Clips.toss = {
	length = 1.1,
	keys = {
		{ t = 0, pose = merge(NEUTRAL, merge(LANTERN, { LeftShoulder = { rx = 62 }, LeftElbow = { rx = 62 } })) },
		{ t = 0.28, ease = "out", pose = { LeftShoulder = { rx = 150, rz = -26 }, LeftElbow = { rx = 62 }, Waist = { ry = -16 }, Neck = { ry = -12 } } },
		{ t = 0.45, ease = "snap", pose = { LeftShoulder = { rx = 176, rz = 8 }, LeftElbow = { rx = 8 }, Waist = { ry = 10 } } },
		{ t = 0.75, pose = { LeftShoulder = { rx = 0, rz = 0 }, LeftElbow = { rx = 0 }, Waist = { ry = 0 }, Neck = { ry = 0 }, Root = { y = 0.22 } } },
		{ t = 0.9, ease = "in", pose = { Root = { y = -0.12 } } },
		{ t = 1.1, pose = { Root = { y = 0 } } },
	},
	events = { { t = 0.45, name = "toss" } },
}

-- ===== Sen: mityczny grzyb =====
-- Przyklęka, łapie, ciągnie trzy razy coraz mocniej (drżenie), za trzecim razem grzyb puszcza i gracz
-- ląduje na tyłku, a potem z grzybem uniesionym nad głową wstaje.
Clips.pickMythic = {
	length = 5.0,
	keys = {
		{ t = 0, pose = merge(NEUTRAL, LANTERN) },
		{
			t = 0.7,
			ease = "out",
			pose = merge(KNEEL, {
				Waist = { rx = -32 },
				Neck = { rx = -22 },
				LeftShoulder = { rx = 60, rz = -4 },
				LeftElbow = { rx = 20 },
				RightShoulder = { rx = 10, rz = 24 },
				RightElbow = { rx = 30 },
			}),
		},
		{ t = 1.1, ease = "snap", pose = { Root = { z = 0.4, rx = 6 }, Waist = { rx = -14 }, LeftShoulder = { rx = 40 }, LeftElbow = { rx = 6 } } },
		{ t = 1.35, pose = { Root = { z = 0.1, rx = -4 }, Waist = { rx = -30 }, LeftShoulder = { rx = 58 }, LeftElbow = { rx = 18 } } },
		{ t = 1.75, ease = "snap", pose = { Root = { z = 0.55, rx = 10 }, Waist = { rx = -8 }, LeftShoulder = { rx = 36 }, LeftElbow = { rx = 4 }, Neck = { rx = 6 } } },
		{ t = 2.0, pose = { Root = { z = 0.1, rx = -4 }, Waist = { rx = -30 }, LeftShoulder = { rx = 58 }, LeftElbow = { rx = 18 }, Neck = { rx = -22 } } },
		{ t = 2.45, ease = "snap", pose = { Root = { z = 0.75, rx = 16 }, Waist = { rx = 2 }, LeftShoulder = { rx = 30 }, LeftElbow = { rx = 0 }, Neck = { rx = 10 } } },
		-- Puszcza! Siada na tyłek, grzyb wysoko w górze
		{
			t = 2.75,
			ease = "back",
			pose = {
				Root = { y = -1.85, z = 0.7, rx = 16 },
				RightHip = { rx = 80 },
				RightKnee = { rx = -24 },
				LeftHip = { rx = 74 },
				LeftKnee = { rx = -34 },
				LeftAnkle = { rx = 0 },
				Waist = { rx = 8 },
				Neck = { rx = 24 },
				LeftShoulder = { rx = 172, rz = -6 },
				LeftElbow = { rx = 6 },
				RightShoulder = { rx = 20, rz = 40 },
				RightElbow = { rx = 20 },
			},
		},
		{ t = 3.6, pose = { Neck = { rx = 20, rz = 10 }, LeftShoulder = { rx = 168, rz = -2 } } },
		{
			t = 4.4,
			ease = "out",
			pose = merge(UP_LEGS, { Waist = { rx = 4 }, Neck = { rx = 16, rz = 0 }, LeftShoulder = { rx = 160, rz = -8 }, LeftElbow = { rx = 14 }, RightShoulder = { rx = 16, rz = 12 }, RightElbow = { rx = 26 } }),
		},
		{ t = 5.0, pose = { Neck = { rx = 12 } } },
	},
	events = { { t = 1.1, name = "tug" }, { t = 1.75, name = "tug" }, { t = 2.45, name = "tug" }, { t = 2.75, name = "pop" } },
}

-- ===== Sen: latarnia gaśnie =====
-- Gracz opuszcza grzyba, unosi latarnię przed twarz i się jej przygląda, potrząsa nią (zdarzenia tink),
-- latarnia gaśnie (zdarzenie out), odskok i rozglądanie się w ciemności.
Clips.lantern = {
	length = 5.4,
	keys = {
		{ t = 0, pose = merge(NEUTRAL, merge(LANTERN, { LeftShoulder = { rx = 150, rz = -8 }, LeftElbow = { rx = 14 }, Neck = { rx = 12 } })) },
		{ t = 0.6, pose = { LeftShoulder = { rx = 48, rz = -6 }, LeftElbow = { rx = 70 }, Neck = { rx = 0 } } },
		{
			t = 1.2,
			ease = "out",
			pose = { RightShoulder = { rx = 56, rz = -16 }, RightElbow = { rx = 26 }, RightWrist = { rx = -20 }, Neck = { rx = 6, ry = -14 }, Waist = { ry = -8, rx = -4 } },
		},
		{ t = 1.7, pose = { Neck = { rx = 4, ry = -18, rz = 8 } } },
		{ t = 1.85, ease = "snap", pose = { RightShoulder = { rx = 61, rz = -24 } } },
		{ t = 2.0, ease = "snap", pose = { RightShoulder = { rx = 56, rz = -10 } } },
		{ t = 2.15, ease = "snap", pose = { RightShoulder = { rx = 61, rz = -24 } } },
		{ t = 2.3, ease = "snap", pose = { RightShoulder = { rx = 56, rz = -14 } } },
		{ t = 3.0, pose = { Neck = { rx = 10, ry = -20, rz = -6 } } },
		-- Gaśnie: odruchowy odskok głowy, ręka z latarnią opada
		{ t = 3.25, ease = "snap", pose = { Waist = { rx = 6, ry = 0 }, Neck = { rx = 14, ry = 0, rz = 0 }, RightShoulder = { rx = 40, rz = 6 }, RightElbow = { rx = 30 }, Root = { z = 0.2 } } },
		{ t = 3.9, pose = { Waist = { rx = -10 }, Neck = { rx = -2, ry = 50 }, LeftShoulder = { rx = 34, rz = -2 }, LeftElbow = { rx = 80 }, Root = { y = -0.25, z = 0 } } },
		{ t = 4.5, pose = { Neck = { ry = -50 }, Waist = { ry = -8 } } },
		{ t = 5.0, pose = { Neck = { ry = 0 }, Waist = { ry = 0 } } },
		{ t = 5.4, pose = { Neck = { rx = 6 } } },
	},
	events = { { t = 1.85, name = "tink" }, { t = 2.15, name = "tink" }, { t = 3.25, name = "out" } },
}

-- Odwraca się z przerażeniem (krok w tył) zanim zacznie uciekać
Clips.recoil = {
	length = 0.7,
	keys = {
		{ t = 0, pose = merge(NEUTRAL, merge(LANTERN, { LeftShoulder = { rx = 34 }, LeftElbow = { rx = 80 } })) },
		{ t = 0.25, ease = "snap", pose = { Root = { z = 0.6, rx = 10, y = -0.2 }, Waist = { rx = 12 }, Neck = { rx = 16 }, LeftShoulder = { rx = 90, rz = -20 }, LeftElbow = { rx = 110 }, RightShoulder = { rx = 70, rz = 30 } } },
		{ t = 0.7, pose = { Root = { z = 0.5, rx = 6, y = -0.1 } } },
	},
}

-- ===== Ogródek: gracz =====
-- Klęczy przy grządce i klepie ziemię obiema dłońmi (zdarzenia pat), potem wstaje
Clips.patSoil = {
	length = 2.2,
	keys = {
		{ t = 0, pose = NEUTRAL },
		{ t = 0.45, ease = "out", pose = merge(KNEEL, { Waist = { rx = -36 }, Neck = { rx = -24 }, LeftShoulder = { rx = 66, rz = -6 }, LeftElbow = { rx = 18 }, RightShoulder = { rx = 50, rz = 8 }, RightElbow = { rx = 30 } }) },
		{ t = 0.65, ease = "snap", pose = { LeftShoulder = { rx = 48 }, RightShoulder = { rx = 70 }, LeftElbow = { rx = 34 }, RightElbow = { rx = 14 } } },
		{ t = 0.85, ease = "snap", pose = { LeftShoulder = { rx = 70 }, RightShoulder = { rx = 48 }, LeftElbow = { rx = 14 }, RightElbow = { rx = 34 } } },
		{ t = 1.05, ease = "snap", pose = { LeftShoulder = { rx = 48 }, RightShoulder = { rx = 70 }, LeftElbow = { rx = 34 }, RightElbow = { rx = 14 } } },
		{ t = 1.25, ease = "snap", pose = { LeftShoulder = { rx = 66 }, RightShoulder = { rx = 66 }, LeftElbow = { rx = 18 }, RightElbow = { rx = 18 } } },
		{ t = 1.6, pose = { Neck = { rx = -10, rz = 10 } } },
		{ t = 2.2, ease = "out", pose = merge(UP_LEGS, { Waist = { rx = 0 }, Neck = { rx = 0, rz = 0 }, LeftShoulder = { rx = 0, rz = 0 }, RightShoulder = { rx = 0, rz = 0 }, LeftElbow = { rx = 0 }, RightElbow = { rx = 0 } }) },
	},
	events = { { t = 0.65, name = "pat" }, { t = 0.85, name = "pat" }, { t = 1.05, name = "pat" }, { t = 1.25, name = "pat" } },
}

-- Sadzenie od zera: klęka, rozgrzebuje ziemię dwoma ruchami (dig), wkłada grzybek prawą ręką (place),
-- klepie ziemię dookoła (pat) i wstaje. Tułów pochyla się mniej niż przy klepaniu, żeby głowa nie wchodziła w grządkę.
Clips.plantSeed = {
	length = 3.4,
	keys = {
		{ t = 0, pose = NEUTRAL },
		{ t = 0.45, ease = "out", pose = merge(KNEEL, { Waist = { rx = -24 }, Neck = { rx = -26 }, LeftShoulder = { rx = 62, rz = -10 }, LeftElbow = { rx = 22 }, RightShoulder = { rx = 62, rz = 10 }, RightElbow = { rx = 22 } }) },
		-- Rozgrzebuje: dłonie zgarniają ziemię na boki
		{ t = 0.7, ease = "snap", pose = { LeftShoulder = { rx = 54, rz = -28 }, RightShoulder = { rx = 54, rz = 28 }, LeftElbow = { rx = 40 }, RightElbow = { rx = 40 } } },
		{ t = 0.9, pose = { LeftShoulder = { rx = 64, rz = -6 }, RightShoulder = { rx = 64, rz = 6 }, LeftElbow = { rx = 16 }, RightElbow = { rx = 16 } } },
		{ t = 1.1, ease = "snap", pose = { LeftShoulder = { rx = 54, rz = -30 }, RightShoulder = { rx = 54, rz = 30 }, LeftElbow = { rx = 40 }, RightElbow = { rx = 40 } } },
		-- Wkłada grzybek: prawa ręka w dół do dołka, lewa opiera się o kolano
		{ t = 1.45, ease = "out", pose = { RightShoulder = { rx = 70, rz = 4 }, RightElbow = { rx = 10 }, RightWrist = { rx = 20 }, LeftShoulder = { rx = 20, rz = -10 }, LeftElbow = { rx = 60 }, Neck = { rx = -30 } } },
		{ t = 1.75, pose = { RightShoulder = { rx = 64 }, RightElbow = { rx = 18 }, RightWrist = { rx = 0 } } },
		-- Klepie dookoła
		{ t = 1.95, ease = "snap", pose = { LeftShoulder = { rx = 66, rz = -8 }, LeftElbow = { rx = 14 }, RightShoulder = { rx = 50 }, RightElbow = { rx = 34 } } },
		{ t = 2.15, ease = "snap", pose = { LeftShoulder = { rx = 50 }, LeftElbow = { rx = 34 }, RightShoulder = { rx = 66 }, RightElbow = { rx = 14 } } },
		{ t = 2.35, ease = "snap", pose = { LeftShoulder = { rx = 66 }, LeftElbow = { rx = 14 }, RightShoulder = { rx = 66 }, RightElbow = { rx = 14 } } },
		{ t = 2.7, pose = { Neck = { rx = -8, rz = 8 }, Waist = { rx = -10 } } },
		{ t = 3.4, ease = "out", pose = merge(UP_LEGS, { Waist = { rx = 0 }, Neck = { rx = 0, rz = 0 }, LeftShoulder = { rx = 0, rz = 0 }, RightShoulder = { rx = 0, rz = 0 }, LeftElbow = { rx = 0 }, RightElbow = { rx = 0 }, RightWrist = { rx = 0 } }) },
	},
	events = { { t = 0.7, name = "dig" }, { t = 1.1, name = "dig" }, { t = 1.5, name = "place" }, { t = 1.95, name = "pat" }, { t = 2.15, name = "pat" }, { t = 2.35, name = "pat" } },
}

-- Ociera pot z czoła przedramieniem (zdarzenie sweat), wzdycha z ulgą i opiera ręce na biodrach
Clips.wipeSweat = {
	length = 2.4,
	keys = {
		{ t = 0, pose = NEUTRAL },
		{ t = 0.35, ease = "out", pose = { RightShoulder = { rx = 128, rz = -38 }, RightElbow = { rx = 118 }, Neck = { rx = 8, rz = -6 }, Waist = { rx = 2 } } },
		{ t = 0.7, pose = { RightShoulder = { rx = 126, rz = -4 }, RightElbow = { rx = 116 }, Neck = { rx = 10, ry = -12, rz = 4 } } },
		{ t = 1.05, ease = "out", pose = { RightShoulder = { rx = 0, rz = 6 }, RightElbow = { rx = 0 }, LeftShoulder = { rz = -6 }, Neck = { rx = 14, ry = 0, rz = 0 }, Waist = { rx = 8 }, Root = { y = -0.1 } } },
		{ t = 1.45, pose = { Waist = { rx = 0 }, Neck = { rx = 2 }, Root = { y = 0 } } },
		{
			t = 1.8,
			ease = "back",
			pose = { LeftShoulder = { rx = -12, rz = -34 }, LeftElbow = { rx = 104 }, RightShoulder = { rx = -12, rz = 34 }, RightElbow = { rx = 104 }, Waist = { rx = 4 }, Neck = { rx = 6 } },
		},
		{ t = 2.4, pose = { Neck = { rx = 4, rz = 6 } } },
	},
	events = { { t = 0.6, name = "sweat" }, { t = 1.05, name = "sigh" } },
}

-- Woła „Hej!” i wskazuje palcem złodzieja
Clips.point = {
	length = 0.6,
	keys = {
		{ t = 0, pose = NEUTRAL },
		{ t = 0.25, ease = "back", pose = { RightShoulder = { rx = 92, rz = 4 }, RightElbow = { rx = 0 }, LeftShoulder = { rx = 10, rz = -24 }, LeftElbow = { rx = 70 }, Waist = { rx = -6 }, Neck = { rx = 4 } } },
		{ t = 0.6, pose = { RightShoulder = { rx = 88 } } },
	},
}

-- Przegania: macha ręką nad głową (zdarzenia shoo), druga pięść na biodrze
Clips.shoo = {
	length = 1.6,
	keys = {
		{ t = 0, pose = NEUTRAL },
		{ t = 0.2, ease = "out", pose = { RightShoulder = { rx = 150, rz = 24 }, RightElbow = { rx = 60 }, LeftShoulder = { rx = -10, rz = -32 }, LeftElbow = { rx = 104 }, Waist = { rx = -6 }, Neck = { rx = 6 } } },
		{ t = 0.4, ease = "snap", pose = { RightElbow = { rx = 10 } } },
		{ t = 0.6, ease = "snap", pose = { RightElbow = { rx = 70 } } },
		{ t = 0.8, ease = "snap", pose = { RightElbow = { rx = 10 } } },
		{ t = 1.0, ease = "snap", pose = { RightElbow = { rx = 70 } } },
		{ t = 1.2, ease = "snap", pose = { RightElbow = { rx = 10 } } },
		{ t = 1.6, pose = { RightShoulder = { rx = 0, rz = 0 }, RightElbow = { rx = 0 }, LeftShoulder = { rx = 0, rz = 0 }, LeftElbow = { rx = 0 }, Waist = { rx = 0 }, Neck = { rx = 0 } } },
	},
	events = { { t = 0.4, name = "shoo" }, { t = 0.8, name = "shoo" }, { t = 1.2, name = "shoo" } },
}

-- Otrzepuje dłonie (klaśnięcia) z miną „i po sprawie”
Clips.dustHands = {
	length = 1.3,
	keys = {
		{ t = 0, pose = NEUTRAL },
		{ t = 0.2, pose = { LeftShoulder = { rx = 52, rz = 14 }, RightShoulder = { rx = 52, rz = -14 }, LeftElbow = { rx = 70 }, RightElbow = { rx = 70 }, Neck = { rx = 8, rz = 8 } } },
		{ t = 0.4, ease = "snap", pose = { LeftWrist = { ry = 30 }, RightWrist = { ry = -30 } } },
		{ t = 0.6, ease = "snap", pose = { LeftWrist = { ry = -20 }, RightWrist = { ry = 20 } } },
		{ t = 0.8, ease = "snap", pose = { LeftWrist = { ry = 30 }, RightWrist = { ry = -30 } } },
		{ t = 1.3, pose = { LeftShoulder = { rx = -10, rz = -34 }, LeftElbow = { rx = 104 }, RightShoulder = { rx = -10, rz = 34 }, RightElbow = { rx = 104 }, LeftWrist = { ry = 0 }, RightWrist = { ry = 0 }, Neck = { rx = 10, rz = 0 }, Waist = { rx = 4 } } },
	},
	events = { { t = 0.4, name = "pat" }, { t = 0.8, name = "pat" } },
}

-- ===== Ogródek: złodziej =====
-- Wychyla się zza rogu (przechył w prawo), chowa się, wychyla jeszcze raz i zaciera ręce
Clips.peek = {
	length = 3.0,
	keys = {
		{ t = 0, pose = merge(NEUTRAL, { Waist = { rx = -8 }, LeftShoulder = { rx = 20 }, RightShoulder = { rx = 20 } }) },
		{ t = 0.45, ease = "out", pose = { Root = { rz = -24, x = 0.6, y = -0.2 }, Neck = { rz = 14, ry = -10 }, Waist = { rz = -6 } } },
		{ t = 0.9, pose = { Neck = { rz = 14, ry = 18 } } },
		{ t = 1.15, ease = "snap", pose = { Root = { rz = 0, x = 0, y = 0 }, Neck = { rz = 0, ry = 0 }, Waist = { rz = 0 } } },
		{ t = 1.5, ease = "out", pose = { Root = { rz = -30, x = 0.8, y = -0.3 }, Neck = { rz = 18, ry = -4 } } },
		{ t = 2.0, pose = { LeftShoulder = { rx = 62, rz = 22 }, RightShoulder = { rx = 62, rz = -22 }, LeftElbow = { rx = 84 }, RightElbow = { rx = 84 } } },
		{ t = 2.2, ease = "snap", pose = { LeftWrist = { ry = 30 }, RightWrist = { ry = -30 } } },
		{ t = 2.4, ease = "snap", pose = { LeftWrist = { ry = -30 }, RightWrist = { ry = 30 } } },
		{ t = 2.6, ease = "snap", pose = { LeftWrist = { ry = 30 }, RightWrist = { ry = -30 } } },
		{ t = 3.0, pose = { LeftWrist = { ry = 0 }, RightWrist = { ry = 0 }, Neck = { rz = 10, rx = 8 } } },
	},
}

-- Zza rogu chatki (ściana z boku, róg przed nim): skulony wychyla się do przodu (głowa wychodzi za róg),
-- cofa się szybko, wychyla jeszcze raz, a potem chichocze i zaciera ręce (zdarzenia hehe, rub)
local CROUCH = { Root = { y = -0.55, rx = -8, z = 0.4 }, Waist = { rx = -22 }, LeftHip = { rx = 30 }, RightHip = { rx = 30 }, LeftKnee = { rx = -46 }, RightKnee = { rx = -46 }, LeftAnkle = { rx = 16 }, RightAnkle = { rx = 16 } }
Clips.peekOut = {
	length = 4.6,
	keys = {
		{ t = 0, pose = merge(NEUTRAL, merge(CROUCH, { LeftShoulder = { rx = 40, rz = -14 }, LeftElbow = { rx = 80 }, RightShoulder = { rx = 40, rz = 14 }, RightElbow = { rx = 80 } })) },
		{ t = 0.55, ease = "out", pose = { Root = { z = -0.9, y = -0.65, rx = -14 }, Waist = { rx = -30 }, Neck = { rx = 24, ry = 10 } } },
		{ t = 1.1, pose = { Neck = { rx = 20, ry = -16 } } },
		{ t = 1.3, ease = "snap", pose = { Root = { z = 0.5, y = -0.5, rx = -6 }, Waist = { rx = -16 }, Neck = { rx = 6, ry = 0 } } },
		{ t = 1.75, ease = "out", pose = { Root = { z = -1.0, y = -0.62, rx = -14 }, Waist = { rx = -28 }, Neck = { rx = 24, ry = 4 } } },
		-- Zaciera ręce przed sobą
		{ t = 2.4, ease = "out", pose = { LeftShoulder = { rx = 70, rz = 24 }, RightShoulder = { rx = 70, rz = -24 }, LeftElbow = { rx = 92 }, RightElbow = { rx = 92 }, Neck = { rx = 14 } } },
		{ t = 2.6, ease = "snap", pose = { LeftWrist = { ry = 34 }, RightWrist = { ry = -34 }, Root = { y = -0.55 } } },
		{ t = 2.8, ease = "snap", pose = { LeftWrist = { ry = -34 }, RightWrist = { ry = 34 }, Root = { y = -0.68 } } },
		{ t = 3.0, ease = "snap", pose = { LeftWrist = { ry = 34 }, RightWrist = { ry = -34 }, Root = { y = -0.55 } } },
		{ t = 3.2, ease = "snap", pose = { LeftWrist = { ry = -34 }, RightWrist = { ry = 34 }, Root = { y = -0.68 } } },
		{ t = 3.4, ease = "snap", pose = { LeftWrist = { ry = 34 }, RightWrist = { ry = -34 }, Root = { y = -0.55 } } },
		-- Chichot: ramiona podskakują
		{ t = 3.6, ease = "snap", pose = { Waist = { rx = -18 }, Neck = { rx = 2, rz = 8 } } },
		{ t = 3.75, ease = "snap", pose = { Waist = { rx = -26 }, Neck = { rx = 10, rz = -6 } } },
		{ t = 3.9, ease = "snap", pose = { Waist = { rx = -18 }, Neck = { rx = 2, rz = 8 } } },
		{ t = 4.05, ease = "snap", pose = { Waist = { rx = -26 }, Neck = { rx = 10, rz = -6 } } },
		{ t = 4.6, pose = { LeftWrist = { ry = 0 }, RightWrist = { ry = 0 }, Neck = { rx = 12, rz = 0 } } },
	},
	events = { { t = 0.55, name = "peek" }, { t = 1.3, name = "hide" }, { t = 1.75, name = "peek" }, { t = 2.6, name = "rub" }, { t = 3.6, name = "hehe" } },
}

-- Skok przez płot: nogi podkulone, ręce do góry (poza na czas lotu)
Clips.vault = {
	length = 0.6,
	keys = {
		{ t = 0, pose = NEUTRAL },
		{
			t = 0.15,
			ease = "out",
			pose = {
				Root = { rx = -10 },
				LeftHip = { rx = 80, rz = -10 },
				RightHip = { rx = 60, rz = 10 },
				LeftKnee = { rx = -110 },
				RightKnee = { rx = -90 },
				LeftShoulder = { rx = 150, rz = -30 },
				RightShoulder = { rx = 150, rz = 30 },
				LeftElbow = { rx = 20 },
				RightElbow = { rx = 20 },
				Waist = { rx = -10 },
				Neck = { rx = 10 },
			},
		},
		{ t = 0.6, pose = { Root = { rx = -24 }, LeftHip = { rx = 20 }, RightHip = { rx = 40 }, LeftKnee = { rx = -30 }, RightKnee = { rx = -50 } } },
	},
}

-- Skradanie na paluszkach jak w kreskówce: zgięty, łapy jak szpony, wysokie kolana, rozgląda się (pętla).
-- Zdarzenia step przy każdym postawieniu stopy.
local SNEAK_BODY = {
	Root = { y = -0.35, rx = -10 },
	Waist = { rx = -24 },
	LeftShoulder = { rx = 72, rz = -18 },
	LeftElbow = { rx = 96 },
	LeftWrist = { rx = -40 },
	RightShoulder = { rx = 72, rz = 18 },
	RightElbow = { rx = 96 },
	RightWrist = { rx = -40 },
}
Clips.sneak = {
	length = 1.6,
	loop = true,
	keys = {
		{ t = 0, pose = merge(NEUTRAL, merge(SNEAK_BODY, { LeftHip = { rx = 64 }, LeftKnee = { rx = -98 }, LeftAnkle = { rx = -30 }, RightHip = { rx = -12 }, RightKnee = { rx = -14 }, RightAnkle = { rx = 20 }, Root = { y = -0.18, rx = -10 }, Neck = { rx = 20, ry = 22 } })) },
		{ t = 0.4, ease = "in", pose = { LeftHip = { rx = 30 }, LeftKnee = { rx = -26 }, LeftAnkle = { rx = 0 }, Root = { y = -0.45 } } },
		{ t = 0.8, ease = "out", pose = { RightHip = { rx = 64 }, RightKnee = { rx = -98 }, RightAnkle = { rx = -30 }, LeftHip = { rx = -12 }, LeftKnee = { rx = -14 }, LeftAnkle = { rx = 20 }, Root = { y = -0.18 }, Neck = { ry = -22 } } },
		{ t = 1.2, ease = "in", pose = { RightHip = { rx = 30 }, RightKnee = { rx = -26 }, RightAnkle = { rx = 0 }, Root = { y = -0.45 } } },
		{ t = 1.6, ease = "out", pose = { LeftHip = { rx = 64 }, LeftKnee = { rx = -98 }, LeftAnkle = { rx = -30 }, RightHip = { rx = -12 }, RightKnee = { rx = -14 }, RightAnkle = { rx = 20 }, Root = { y = -0.18 }, Neck = { ry = 22 } } },
	},
	events = { { t = 0.4, name = "step" }, { t = 1.2, name = "step" } },
}

-- Rozgląda się na boki (czy nikt nie patrzy), palec na ustach „ćśś”
Clips.lookAround = {
	length = 2.2,
	keys = {
		{ t = 0, pose = merge(NEUTRAL, SNEAK_BODY) },
		{ t = 0.4, pose = { Neck = { ry = 60, rx = 8 }, Waist = { ry = 14 } } },
		{ t = 0.9, pose = { Neck = { ry = -60 }, Waist = { ry = -14 } } },
		{ t = 1.3, pose = { Neck = { ry = 0, rx = 4 }, Waist = { ry = 0 } } },
		{ t = 1.6, ease = "back", pose = { RightShoulder = { rx = 104, rz = -44 }, RightElbow = { rx = 128 }, RightWrist = { rx = 0 }, Neck = { rx = 10 } } },
		{ t = 2.2, pose = { Neck = { rx = 6, rz = 8 } } },
	},
	events = { { t = 1.6, name = "shh" } },
}

-- Kuca i wyrywa grzyb z grządki, szarpiąc coraz mocniej (zdarzenia tug)
Clips.tug = {
	length = 2.4,
	loop = false,
	keys = {
		{ t = 0, pose = merge(NEUTRAL, SNEAK_BODY) },
		{
			t = 0.4,
			ease = "out",
			pose = {
				Root = { y = -1.35, rx = -6, z = 0.1 },
				LeftHip = { rx = 96, rz = -12 },
				RightHip = { rx = 96, rz = 12 },
				LeftKnee = { rx = -122 },
				RightKnee = { rx = -122 },
				LeftAnkle = { rx = 30 },
				RightAnkle = { rx = 30 },
				Waist = { rx = -36 },
				Neck = { rx = -6, ry = 0 },
				LeftShoulder = { rx = 64, rz = 6 },
				RightShoulder = { rx = 64, rz = -6 },
				LeftElbow = { rx = 24 },
				RightElbow = { rx = 24 },
				LeftWrist = { rx = 0 },
				RightWrist = { rx = 0 },
			},
		},
		{ t = 0.8, ease = "snap", pose = { Root = { z = 0.5, rx = 8 }, Waist = { rx = -12 }, LeftShoulder = { rx = 40 }, RightShoulder = { rx = 40 }, LeftElbow = { rx = 4 }, RightElbow = { rx = 4 } } },
		{ t = 1.1, pose = { Root = { z = 0.1, rx = -6 }, Waist = { rx = -36 }, LeftShoulder = { rx = 64 }, RightShoulder = { rx = 64 }, LeftElbow = { rx = 24 }, RightElbow = { rx = 24 } } },
		{ t = 1.5, ease = "snap", pose = { Root = { z = 0.65, rx = 12 }, Waist = { rx = -6 }, LeftShoulder = { rx = 34 }, RightShoulder = { rx = 34 }, LeftElbow = { rx = 0 }, RightElbow = { rx = 0 }, Neck = { rx = 8 } } },
		{ t = 1.8, pose = { Root = { z = 0.1, rx = -6 }, Waist = { rx = -36 }, LeftShoulder = { rx = 64 }, RightShoulder = { rx = 64 }, LeftElbow = { rx = 24 }, RightElbow = { rx = 24 }, Neck = { rx = -6 } } },
		{ t = 2.4, pose = { Neck = { rx = -2 } } },
	},
	events = { { t = 0.8, name = "tug" }, { t = 1.5, name = "tug" } },
}

-- Podskok ze strachu: wyskakuje w górę z rękami w górze, ląduje skulony
Clips.jumpScare = {
	length = 0.9,
	keys = {
		{ t = 0, pose = NEUTRAL },
		{
			t = 0.18,
			ease = "snap",
			pose = {
				Root = { y = 1.6, rx = 6, z = 0 },
				LeftShoulder = { rx = 160, rz = -34 },
				RightShoulder = { rx = 160, rz = 34 },
				LeftElbow = { rx = 20 },
				RightElbow = { rx = 20 },
				LeftHip = { rx = 30, rz = -16 },
				RightHip = { rx = -20, rz = 16 },
				LeftKnee = { rx = -60 },
				RightKnee = { rx = -40 },
				Waist = { rx = 12 },
				Neck = { rx = 16 },
			},
		},
		{ t = 0.55, ease = "in", pose = { Root = { y = -0.5, rx = -8 }, LeftHip = { rx = 40, rz = -10 }, RightHip = { rx = 40, rz = 10 }, LeftKnee = { rx = -70 }, RightKnee = { rx = -70 }, LeftShoulder = { rx = 80, rz = -40 }, RightShoulder = { rx = 80, rz = 40 } } },
		{ t = 0.9, pose = { Root = { y = -0.3 } } },
	},
}

-- Wywrotka w biegu: leci na twarz z rękami do przodu, leży, zrywa się
Clips.faceplant = {
	length = 2.2,
	keys = {
		{ t = 0, pose = merge(NEUTRAL, { Waist = { rx = -14 }, LeftShoulder = { rx = 40 }, RightShoulder = { rx = -30 } }) },
		{ t = 0.25, ease = "in", pose = { Root = { rx = -40, y = -0.6 }, LeftShoulder = { rx = 140, rz = -20 }, RightShoulder = { rx = 140, rz = 20 }, LeftHip = { rx = -30 }, RightHip = { rx = 10 } } },
		{ t = 0.5, ease = "out", pose = { Root = { rx = -86, y = -2.3, z = -0.8 }, LeftShoulder = { rx = 170 }, RightShoulder = { rx = 170 }, LeftElbow = { rx = 10 }, RightElbow = { rx = 10 }, LeftHip = { rx = -14 }, RightHip = { rx = -6 }, Neck = { rx = 30 } } },
		{ t = 0.65, ease = "out", pose = { Root = { rx = -82, y = -2.15 }, LeftHip = { rx = -40 }, LeftKnee = { rx = -60 } } },
		{ t = 1.3, pose = { Root = { rx = -84, y = -2.2 }, LeftHip = { rx = -10 }, LeftKnee = { rx = -10 }, Neck = { rx = 34, ry = 20 } } },
		{ t = 1.7, ease = "out", pose = { Root = { rx = -30, y = -1.2, z = 0 }, LeftShoulder = { rx = 60 }, RightShoulder = { rx = 60 }, LeftElbow = { rx = 40 }, RightElbow = { rx = 40 }, LeftHip = { rx = 80 }, LeftKnee = { rx = -110 }, Neck = { rx = 10, ry = 0 } } },
		{ t = 2.2, ease = "out", pose = merge(UP_LEGS, { Waist = { rx = -14 }, LeftShoulder = { rx = 0 }, RightShoulder = { rx = 0 }, LeftElbow = { rx = 0 }, RightElbow = { rx = 0 }, Neck = { rx = 0 } }) },
	},
	events = { { t = 0.5, name = "thud" } },
}

return Clips
