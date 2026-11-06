# Przepustka Latarnika: skórki, poziomy, trzy ścieżki

Projekt do akceptacji Toma (6.11.2026). Nic z tego nie jest jeszcze w kodzie. Stan repo: `main` = `a5500f4`.
Pomysł Toma: przepustka z trzema ścieżkami (Darmowa, VIP, OP), skórki według rzadkości, pasek poziomu przy monetach
i ładne okno. Wybór skórek, sklep skórek, gamepassy, rebirth i pety to osobne etapy; na końcu jest opis, jak się łączą.

## Skrót

- **Sezon 1 trwa 8 tygodni**: 20.11.2026 – 15.01.2027 (00:00 UTC). Zima (1.12 – 7.01) wypada w środku i jej zadania
  dnia też dają XP przepustki. Skórki i tytuły zostają na zawsze, XP i zakup VIP/OP dotyczą jednego sezonu.
- **30 poziomów po 1 000 XP.** Po 30. poziomie co 2 500 XP jest „Gwiazda sezonu” (⭐ i 0,5 S monet, monety najwyżej 20 razy).
- **XP głównie z codziennej gry, nie z godzin**: logowanie 50, zadanie dnia 150, komplet zadań 200 (razem 700 dziennie),
  do tego zbieranie w lesie (1 XP za grzyb, premia za mutacje, pełne XP do 500 dziennie, potem ¼, najwyżej 1 000
  dziennie) i wyczyny (ucieczka strażnikowi, Znalezisko Nocy, ekspedycja, kuźnia, kradzież) z dziennymi limitami.
- **Tempo** (do sprawdzenia w Analytics): gracz regularny (45 min, 5 dni w tygodniu) kończy 30. poziom po ok.
  4–4,5 tygodnia, zapalony (2,5 h dziennie) po ok. 12 dniach, okazjonalny (20 min, 3 dni w tygodniu) dochodzi do
  ok. 14. poziomu.
- **Skórki: 16 nowych** (7 latarni, 5 nożyków, 2 ślady za graczem, 2 efekty zbierania), dokładnie w układzie Toma:
  Darmowa 2 pospolite i epicka na końcu; VIP niebieska na start, 2 zielone, epicka, legendarna; OP epicka na start,
  2 niebieskie, 2 epickie, 2 legendarne i Kosmiczna Latarnia na końcu.
- **Na poziomach 10, 20 i 30 każda ścieżka daje skórkę o stopień lepszą** (10: szara / zielona / niebieska,
  20: szara / zielona / fioletowa, 30: fioletowa / złota / kosmiczna). W oknie widać to od razu w jednej kolumnie.
- **Ceny: VIP 199 R$, OP 499 R$ (zawiera VIP), ulepszenie VIP → OP 300 R$.** Trzy produkty dewelopera
  (nie gamepassy), **osobne na każdy sezon** (Tom zakłada 3 nowe produkty przed każdym sezonem). Kupione później
  odbiera wszystkie zaległe nagrody od razu.
- **Zapis**: nowe pola `pass`, `passHistory`, `passBuys`, `boosts`, `recipesRewarded`, `grantedTitles`, sloty `equipped.trail` i
  `equipped.pickfx`, czyli **`DATA_VERSION` 10 → 11** (zasada 2) i Restart Servers po publikacji.
- **Zasada 7 zostaje**: na Darmowej ścieżce nie ma mikstury ani Wysypu (test to sprawdza). Mikstura i Wysyp są tylko
  w płatnych ścieżkach (decyzja Toma niżej) i trafiają do **Schowka**, skąd gracz uruchamia je, kiedy chce.
- **Codex (xhigh) przejrzał projekt 6.11**; jego uwagi są już wpisane (sekcja „Przegląd Codexa” na końcu).

### Decyzje dla Toma

| # | Pytanie | Propozycja |
|---|---|---|
| 1 | Czy przepustka jest sezonowa? | Tak, sezon 1 trwa 8 tygodni (20.11 – 15.01), kolejne 6–8 tygodni |
| 2 | Czy OP zawiera VIP? | Tak (kupujący OP odbiera wszystkie trzy rzędy) |
| 3 | Ceny | VIP 199 R$, OP 499 R$, VIP → OP 300 R$ |
| 4 | Ostatnia skórka OP | Kosmiczna Latarnia, nowa najwyższa rzadkość „kosmiczna” (kolor wariantu Kosmicznego) |
| 5 | Mikstura i Wysyp w płatnych ścieżkach | Tak, mało: VIP 2 × 15 min mikstury, OP 3 × 15 min, 2 × Twój Wysyp, 1 × Wysyp dla serwera |
| 6 | Czy skórki sezonu kiedyś wrócą? | Nie (wyłączne dla sezonu); w sklepie skórek będą inne |
| 7 | Nazwa | „Przepustka Latarnika”, sezon 1 „Duchy Puszczy” (Jaga, Skarbnik, Utopiec, Żmij, Perun, ogniki) |
| 8 | „Pomiń poziom” za Robux | Nie na start; ewentualnie w ostatnim tygodniu sezonu 2 |
| 9 | Kosmetyczny VIP 249 R$ z badania monetyzacji | Odłożyć: przepustka zajmuje to miejsce, a nazwa „VIP” by się dublowała |
| 10 | Krwawy księżyc: podwójne XP z lasu | Tak (łączy się z Prognozą nocy i Roblox Events) |
| 11 | Monety w płatnych ścieżkach | Tak, ale S zamrożone w chwili zdobycia poziomu (zakup wstecz po otwarciu nowego świata nie daje więcej); alternatywa: płatne ścieżki bez monet |
| 12 | Darmowa mikstura za komplet zadań (5 min) i 7. dzień logowania (10 min) | Jest w grze od dawna, a nie ma jej na liście wyjątków w zasadzie 7; zostawić i dopisać do `CLAUDE.md` albo usunąć (osobna sprawa, nie przepustka) |

## Co już jest w grze (sprawdzone w kodzie)

- **Skórki** (`src/shared/Skins.luau`): dwa sloty, `lantern` i `knife`. Cztery skórki z eventów: `pumpkin_lantern`,
  `sickle` (Halloween), `ice_lantern`, `candy_cane` (Zima). Każda to osobny model z części w
  `src/server/World/HandTools.luau`. Zapis: `data.skins` (lista) i `data.equipped` (slot → id). Skórki ze ścieżek
  eventów liczą się z liczników (`stats.candy`, `stats.snowflakes`), a nie z listy. Skórki nie mają rzadkości.
  Zakładanie: remote `EquipSkin` z okien Halloween i Zimy (`HalloweenService.onEquip` sprawdza `Skins.owns`).
  Okna pokazują skórki tylko jako emoji; 3D podglądu nie ma, bo `HandTools` leży na serwerze.
  `HandTools` nie ma żadnych `require`, więc da się go przenieść do `Shared` i budować podgląd w `ViewportFrame`.
- **Rzadkości i kolory**: `Config.Classes` (pospolity szary 200,200,200; niepospolity zielony 110,220,110;
  rzadki niebieski 90,170,255; epicki fiolet 190,110,255; legendarny złoty 255,170,40) i `Config.SpecialClasses`
  (mityczny 255,70,110; sekretny 236,240,255). Kosmiczny jest wariantem mutacji (ranga 4, kolor 70,50,170).
  Tytuły mają osobną skalę (`Titles.RARITIES`: common, rare, epic, legendary, mythic).
- **HUD przy monetach** (`src/client/Hud.luau`): panel `Stats` 196 × `UiScale.STATS_HEIGHT` (102) w lewym górnym rogu:
  monety, koszyk, pasek gwarancji Złota. Pod nim rząd przycisków (język, muzyka, dźwięki, zaproś), przycisk sklepu
  i panel DEV; wszystkie liczą położenie z `UiScale.rowTop()` / `rowBottom()`, więc wyższy panel przesunie je sam.
  Prawa krawędź: kolumna `SideButtons` (Zadania, Grzybopedia, Tytuły, Społeczność, eventy).
- **Zdarzenia gry**: prawie wszystko przechodzi przez `ProgressService.event(player, kind, amount)` (pick, sell,
  steal, escape, revive, plant, upgrade, discover, forge, delve, nightFind, leszyOffer...) i `ProgressService.found`.
  To jedno miejsce, z którego przepustka może brać XP.
- **Zakupy**: `GameService.processReceipt` z listą `data.receipts` i `DataService.confirmSaved` (przyznanie dopiero
  po zapisie). Produkt z `id = 0` w Studio „kupuje się” za darmo, na żywo karta jest ukryta.
  Gamepassów w kodzie nie ma. Produkty z `id = 0`: `boomSolo`, `x2s/m/l/xl`. Odznaki z `id = 0`: `grandmaster`,
  `cosmic`, `forge_collection`, `winter2026`.
- **Monetyzacja** (`docs/plans/monetization-research.md`): NIE dla stałego x2, gatunków za Robux i x2 za monety;
  kosmetyka tak. Nagrody monetowe liczymy w S (`Progress.rewardScale`, las 1 600 monet, góra 520 000; zasada 8).
- **Ekonomia** (`lune run tools/economy_sim.luau`, 6.11): cała progresja to ok. 9 h wydajnej gry (Jaskinia 1 h 26,
  Bagna 2 h 42, Góra 6 h 35). Przepustka na 8 tygodni nie może więc iść za postępem świata; XP musi być płaskie
  (tyle samo w lesie, co na górze), inaczej nowy gracz stałby w miejscu, a weteran skończyłby w dwa wieczory.

## Zasady przepustki

1. **Sezon** z datami w `Config.Pass.seasons` (UTC, jak eventy). Poza sezonem przycisk i pasek są schowane
   (albo pokazują „Sezon 2 za 5 dni”, jeśli następny jest w Config).
2. **Trzy rzędy na tych samych poziomach**: Darmowa (każdy), VIP, OP. **OP zawiera VIP**: kupujący OP odbiera
   wszystkie trzy rzędy. Kupujący VIP odbiera Darmową i VIP.
3. **Poziom** = `xp // 1000`, najwyżej 30. Nagrody **odbiera się ręcznie** (klik na kafelek albo „Odbierz wszystko”),
   jak zadania dnia: chwila odbioru to frajda.
4. **Mikstura i Wysypy idą do Schowka**, nie działają od razu. Odbiór (także „Odbierz wszystko”) dopisuje je do
   `boosts`; gracz uruchamia każdą sztukę osobnym przyciskiem w oknie przepustki (np. w Krwawy księżyc).
   Schowek nie wygasa z sezonem (to rzeczy kupione za Robux).
5. **Zakup wstecz**: kto kupi VIP na 18. poziomie, od razu może odebrać wszystkie nagrody VIP z poziomów 1–18.
   Okno zakupu mówi wprost, co gracz odbierze od razu, a co zdobędzie później, i do kiedy trwa sezon:
   „Od razu: 3 skórki, 1 tytuł, 9 S monet. Do zdobycia do 15.01: jeszcze 2 skórki…”.
6. **Monety na kafelkach liczą S z chwili zdobycia poziomu** (serwer zapisuje S przy każdym nowym poziomie w
   `pass.sc`). Odbiór później albo zakup wstecz po otwarciu nowego świata daje tyle samo co odbiór od razu.
7. **Koniec sezonu**: wszystko, co gracz osiągnął i nie odebrał, dostaje automatycznie przy pierwszym wejściu
   po końcu (albo na żywo, gdy sezon kończy się w trakcie gry): skórki, tytuły, monety (z zamrożonym S),
   mikstury i Wysypy do Schowka, nieodebrane Gwiazdy. Potem XP i ścieżki się zerują, a sezon trafia do
   `passHistory`. Rozliczenie jest jednokrotne (znacznik w `passHistory`) i nie czeka na żadne usługi Robloxa.
   Definicje nagród dawnych sezonów zostają w `Pass.luau` na zawsze (gracz wracający po roku też dostaje swoje).
8. **Granica sezonu w każdym wywołaniu**: `add`, `claim`, zakup i aktywacja najpierw sprawdzają bieżący czas i
   sezon (nie tylko pętla co minutę); żądanie odbioru z okna podaje numer sezonu, a serwer odrzuca stary.
9. **Skórki i tytuły zostają na zawsze**, także po sezonie. Skórki sezonu nie wracają (decyzja 6).
10. **Po 30. poziomie**: co 2 500 XP „Gwiazda sezonu” (licznik ⭐ w oknie i przy pasku) i 0,5 S monet, monety
    najwyżej 20 razy na sezon. Tak samo dla wszystkich, bez różnicy między ścieżkami.

## Poziomy i nagrody

Legenda: ⚪ pospolita, 🟢 niepospolita, 🔵 rzadka, 🟣 epicka, 🟡 legendarna, 🌌 kosmiczna;
S = `Progress.rewardScale` w chwili odbioru (las 1 600, jaskinia 32 000, bagna 160 000, góra 520 000 monet);
🍀 = mikstura szczęścia 15 min (`Config.LuckPotion`), 🍄 Twój Wysyp = 10 min tylko dla siebie (jak `boomSolo`),
🍄🍄 Wysyp dla serwera = jak produkt `boom` (gracz zostaje Dawcą Wysypu), 🏷️ = tytuł.

| Poz. | Darmowa | VIP | OP |
|---:|---|---|---|
| 1 | — | 🔵 **Latarnia Nocnej Straży** | 🟣 **Latarnia Baby Jagi** |
| 2 | 0,5 S | 1 S | 1,5 S |
| 3 | — | 1 S | 1,5 S |
| 4 | 0,5 S | 1 S | 1,5 S |
| 5 | 🏷️ Nocny Wędrowiec (pospolity) | 🍀 15 min | 🔵 **Złote Iskry** (efekt zbierania) |
| 6 | 0,5 S | 1 S | 1,5 S |
| 7 | — | 1 S | 1,5 S |
| 8 | 0,5 S | 1 S | 1,5 S |
| 9 | — | 1 S | 🍀 15 min |
| 10 | ⚪ **Latarnia Brzozowa** | 🟢 **Ślad Mchu** (ślad za graczem) | 🔵 **Ślad Księżyca** (ślad za graczem) |
| 11 | — | 1 S | 1,5 S |
| 12 | 0,5 S | 1 S | 🍄 Twój Wysyp |
| 13 | — | 1 S | 1,5 S |
| 14 | 0,5 S | 1 S | 🏷️ Pan Nocy (epicki) |
| 15 | 🏷️ Tropiciel Świetlików (rzadki) | 🏷️ Nocny Latarnik (epicki) | 🟣 **Nóż Utopca** |
| 16 | 0,5 S | 1 S | 1,5 S |
| 17 | — | 1 S | 🍀 15 min |
| 18 | 0,5 S | 🍀 15 min | 🍄🍄 Wysyp dla serwera |
| 19 | — | 1 S | 1,5 S |
| 20 | ⚪ **Nożyk Jałowcowy** | 🟢 **Nożyk z Poroża** | 🟣 **Kruki** (efekt zbierania) |
| 21 | — | 1 S | 1,5 S |
| 22 | 0,5 S | 1 S | 🍄 Twój Wysyp |
| 23 | — | 1 S | 1,5 S |
| 24 | 0,5 S | 1 S | 🍀 15 min |
| 25 | 🏷️ Strażnik Nocy (epicki) | 🟣 **Sztylet Ognika** | 🟡 **Latarnia Skarbnika** |
| 26 | 0,5 S | 1 S | 1,5 S |
| 27 | — | 1 S | 1,5 S |
| 28 | 0,5 S | 2 S | 🟡 **Grom Peruna** |
| 29 | — | 2 S | 3 S |
| 30 | 🟣 **Latarnia Świetlików** + 🏅 odznaka sezonu | 🟡 **Latarnia Żmija** + 🏷️ Pogromca Nocy (legendarny) | 🌌 **Kosmiczna Latarnia** + 🏷️ Kosmiczny Latarnik (mityczny) |

Puste kafelki Darmowej ścieżki są celowe (pomysł Toma): obok nich świecą zamknięte nagrody VIP i OP.
Nazwy tytułów są robocze; muszą się różnić od tytułów twórców („Strażnik Latarni” jest zajęty).

**Razem w sezonie:**

| | Darmowa | VIP (bez Darmowej) | OP (bez VIP i Darmowej) | Kupujący OP razem |
|---|---:|---:|---:|---:|
| Skórki | 3 | 5 | 8 | 16 |
| Tytuły | 3 | 2 | 2 | 7 |
| Monety | 6 S | 24 S | 24 S | 54 S |
| Mikstura 15 min | 0 | 2 | 3 | 5 (75 min) |
| Wysyp | 0 | 0 | 2 × twój, 1 × serwer | 3 |

**Na każdym poziomie VIP daje więcej niż Darmowa, a OP więcej niż VIP** (pomysł Toma). Test liczy to punktami
wartości: monety = liczba S, mikstura 1,5, Twój Wysyp 2, Wysyp dla serwera 3, tytuł 1–5 i skórka 3–12 według
rzadkości. Tabela wyżej spełnia to na wszystkich 30 poziomach.

Skala monet: zadania dnia dają do 5 S dziennie, czyli w 8 tygodni do 280 S. Monety kupującego OP (54 S)
to ok. 11 dni zadań; na górze 54 S = ok. 28 mln, czyli ok. godzina dochodu gracza z wymaksowaną górą
(443 tys./min w symulatorze). Monety z płatnych ścieżek (48 S ponad Darmową) to płatna przewaga: przyspieszają
ulepszenia, a nie tylko ranking `richest`. Wcześniej w grze ważą więcej niż godzina dochodu na górze (S jest
stałe w świecie, a dochód w nim rośnie), dlatego S jest zamrożone w chwili zdobycia poziomu (zasada 6), a całość
to ten sam rząd co produkt harvest (29 R$ = 30 min ogródka). Decyzja 11: zostawić tak albo usunąć monety z
płatnych ścieżek. Mikstury z płatnych ścieżek dają też trochę więcej XP z mutacji (w limicie lasu).

## Skórki sezonu 1 „Duchy Puszczy”

| Skórka | Ścieżka, poziom | Rzadkość | Slot | Wygląd (szkic) | Koszt wykonania |
|---|---|---|---|---|---|
| Latarnia Brzozowa | Darmowa 10 | ⚪ pospolita | latarnia | biała kora w czarne paski, mosiężny daszek | mały (zmiana kolorów zwykłej latarni) |
| Nożyk Jałowcowy | Darmowa 20 | ⚪ pospolita | nożyk | jasna rączka z jałowca, zielony pędzelek | mały (kolory) |
| Latarnia Świetlików | Darmowa 30 | 🟣 epicka | latarnia | zielonkawe szkło, świetliki krążą wokół | średni (cząsteczki) |
| Latarnia Nocnej Straży | VIP 1 | 🔵 rzadka | latarnia | granatowa stal, niebieskie szkło, chłodny płomień | mały–średni |
| Ślad Mchu | VIP 10 | 🟢 niepospolita | ślad | kępki mchu i zielony pył za stopami | mały (cząsteczki) |
| Nożyk z Poroża | VIP 20 | 🟢 niepospolita | nożyk | rączka z poroża, kute ostrze | średni (model) |
| Sztylet Ognika | VIP 25 | 🟣 epicka | nożyk | turkusowe świecące ostrze, iskierki ognika | średni |
| Latarnia Żmija | VIP 30 | 🟡 legendarna | latarnia | głowa smoka trzyma płomień, skrzydła, iskry ognia | duży |
| Latarnia Baby Jagi | OP 1 | 🟣 epicka | latarnia | czaszka na kości, zielony płomień, dymek | średni–duży |
| Złote Iskry | OP 5 | 🔵 rzadka | efekt zbierania | złoty błysk i iskry przy każdym zebranym grzybie | mały |
| Ślad Księżyca | OP 10 | 🔵 rzadka | ślad | srebrny pył i małe półksiężyce | mały |
| Nóż Utopca | OP 15 | 🟣 epicka | nożyk | ostrze z perłowej muszli, kapiąca woda | średni |
| Kruki | OP 20 | 🟣 epicka | efekt zbierania | dwa małe kruki odlatują z miejsca zbioru | średni (kruki z `RavenService` jako wzór) |
| Latarnia Skarbnika | OP 25 | 🟡 legendarna | latarnia | górnicza lampa ze złota i klejnotów, błyski | duży |
| Grom Peruna | OP 28 | 🟡 legendarna | nożyk | ostrze-piorun, łuki elektryczne, trzask przy zbiorze | duży |
| Kosmiczna Latarnia | OP 30 | 🌌 kosmiczna | latarnia | szkło jak galaktyka, krążące gwiazdy i księżyc, gwiezdny pył za graczem | bardzo duży |

Dwa nowe sloty to tanie skórki z cząsteczek (bez modeli): **ślad** (cząsteczki i `Trail` przy stopach) i
**efekt zbierania** (krótki wybuch cząsteczek w miejscu zerwanego grzyba). Dzięki nim 16 skórek to
12 modeli zamiast 16. Skórki mają działać tylko na wygląd: zasięg i jasność światła latarni zostają takie same
(światło gry nie zależy od skórki), żadnych premii.

**Rzadkości skórek**: pospolita, niepospolita, rzadka, epicka, legendarna (kolory z `Config.Classes`), mityczna,
sekretna (`Config.SpecialClasses`) i nowa **kosmiczna** (kolor 70,50,170 z wariantu Kosmicznego, w oknie animowany
gradient jak galaktyka). Skórki z eventów też dostaną rzadkość (np. dyniowa latarnia i lodowa latarnia epickie,
sierp i laska cukrowa rzadkie), bo okno wyboru skórek będzie je sortować.

## XP: skąd i ile

Jedna funkcja serwera `PassService.add(player, source, amount)`. Większość wywołań w `ProgressService.event` /
`found` i w odbiorze logowania. Klient nigdy nie podaje XP (zasada 6).

| Źródło | XP | Limit | Skąd w kodzie |
|---|---:|---|---|
| Odbiór nagrody za logowanie | 50 | raz dziennie | `claimLogin` |
| Ukończone zadanie dnia | 150 | 3 dziennie (zadań jest 3) | `Progress.questEvent` → `completed` |
| Komplet zadań dnia | 200 | raz dziennie | `allDone` |
| Zebrany grzyb w lesie | 1 | wspólny limit „las” | `ProgressService.found`, `source == "pick"` |
| Premia za mutację | Srebro +2, Złoto +5, Tęcza +20, Kosmiczny +100 | wspólny limit „las” | jw. |
| Ucieczka strażnikowi z jego grzybem | 100 | 3 dziennie | `onEscaped` w `GameService` (dziś bez sprawdzenia, czy grzyb strażnika jest jeszcze w koszyku: XP tylko, gdy jest) |
| Znalezisko Nocy doniesione | 150 | 3 dziennie | `event "nightFind"` (jedno na noc na serwer, więc na pełnym serwerze rzadziej) |
| Zabezpieczone znalezisko ekspedycji | 150 | 2 dziennie | `event "delve"` (to ognisko w `DelveService.secure`, przed wyjściem z komór) |
| Połączenie w kuźni | 20 | 10 dziennie | `event "forge"` (każde połączenie, też tanie: świadomy budżet łatwego XP) |
| Odkryty przepis kuźni | 150 | raz na przepis (trwały znacznik) | nowe zdarzenie w `ForgeService` (dziś go nie ma) |
| Kradzież z ogródka doniesiona | 50 | 3 dziennie | `event "steal"` |
| Podniesienie kumpla | 30 | 3 dziennie | `event "revive"` |
| Nowa forma w Grzybopedii | 15 | bez limitu (form jest skończenie wiele) | `event "discover"` |

- **Limit „las”**: pełne XP do 500 dziennie, potem ¼, **najwyżej 1 000 dziennie** (osiągane po ok. 2 000 surowych
  punktach). Zbieranie zostaje opłacalne, a automat zbierający całą dobę nie dostanie więcej niż zapalony gracz.
  Liczone z ułamkami (zbiór, który przekracza 500, dzieli się na część pełną i ćwiartkową). Dzień jak w zadaniach:
  od północy UTC (`Progress.dayIndex`); liczniki dnia zerują się na początku `add`, nie tylko w pętli co 15 s.
- **Krwawy księżyc** (decyzja 10): XP z lasu ×2 (limit dalej liczy się od surowych punktów ×2, więc to po prostu
  szybsze dojście do 500). Ok. 4 Krwawe księżyce dziennie, zapowiedziane w Prognozie nocy.
- **Mikstura szczęścia daje więcej mutacji, więc trochę więcej XP**: mieści się w limicie „las”, więc przewaga
  jest mała.
- **Alty**: limity dzienne na kradzież i podnoszenie ograniczają farmę „okradam własnego alta” do 240 XP dziennie
  (świadomy budżet, nie zero). Alt może sam zbierać XP, ale nie da go głównemu kontu (XP i nagrody nie
  przechodzą między kontami). AFK nie daje XP (nie ma takiego źródła; w strefie bez ruchu gaśnie latarnia).
- **Weteran z wymaksowaną grą**: zadania `upgrade` i `discover` bywają dla niego niewykonalne, a wymiana jest
  jedna dziennie, więc często traci komplet (200 XP). Poprawka osobno, przed sezonem: losowanie zadań pomija
  zadania niemożliwe dla gracza (`Progress.newDaily`). Bez niej regularny weteran ma ok. 1 085 XP dziennie,
  czyli 30. poziom po ok. 5,5 tygodnia.

### Tempo

Założenia: liczba zebranych grzybów na minutę to średnia z wracaniem do chatki (symulator ekonomii pokazuje
więcej, bo liczy wydajną grę). Obliczenie w scratchpadzie sesji (do przeniesienia jako `tools/pass_sim.luau`).

| Gracz | Gra | Stałe (logowanie i zadania) | Las | Wyczyny | XP na dzień gry | Do 30. poziomu | Po 8 tygodniach |
|---|---|---:|---:|---:|---:|---|---|
| Okazjonalny | 20 min, 3 dni w tyg., 2 z 3 zadań, bez kompletu | 350 | 210 | 50 | ok. 610 | 49 dni gry (ok. 16 tygodni) | poziom ok. 14 |
| Regularny | 45 min, 5 dni w tyg., komplet 9 dni na 10 | 680 | 520 | 215 | ok. 1 400 | 21–22 dni gry (4–4,5 tygodnia) | 30 + ok. 10 ⭐ |
| Zapalony | 2,5 h codziennie | 700 | 975 | 930 | ok. 2 600 | 12 dni | 30 + ok. 46 ⭐ (monety z 20) |
| Automat (bot) | 20 h dziennie, tylko las | 0–700 | 1 000 (limit) | 0 | do 1 700 | ok. 18 dni | to samo co regularny |

To hipoteza, nie pomiar: grzyby na minutę to średnia z wracaniem do chatki (symulator ekonomii liczy wydajną grę
i pokazuje więcej). Etap 1 przenosi to obliczenie do `tools/pass_sim.luau`, a po tygodniu sezonu porównujemy
z Analytics (`Milestone_Pass_Tier_*`).

Okazjonalny gracz po 8 tygodniach ma: Darmowa 1 skórkę (poz. 10), VIP 2 z 5, OP 3 z 8. Jeśli Analytics pokaże,
że kupujący VIP/OP utykają w połowie, najlepsza poprawka to **wyzwania tygodnia** (etap 2): co poniedziałek
3 zadania po 500 XP, otwarte do końca sezonu, więc kto zaczął później albo gra rzadko, nadrabia
(8 tygodni × 1 500 = 12 000 XP). Ewentualnie „Pomiń poziom” w ostatnim tygodniu (decyzja 8).

## Ceny i produkty w Creator Hub

| Klucz (sezon 1) | Co daje | Cena | Typ |
|---|---|---:|---|
| `pass1Vip` | ścieżka VIP w sezonie 1 | 199 R$ | produkt dewelopera |
| `pass1Op` | ścieżki VIP i OP w sezonie 1 | 499 R$ | produkt dewelopera |
| `pass1Upgrade` | VIP → OP w sezonie 1 (pokazywany tylko z VIP) | 300 R$ | produkt dewelopera |
| odznaka `pass_s1` | 30. poziom Darmowej ścieżki w sezonie 1 | — | odznaka (5 dziennie za darmo) |

- **Dlaczego produkt dewelopera, a nie gamepass**: gamepass kupuje się raz na zawsze, a przepustka jest na sezon.
  Produkt pozwala na ulepszenie VIP → OP za różnicę i przechodzi przez sprawdzony `processReceipt` (numer zakupu
  w zapisie, przyznanie dopiero po zapisie). Gamepassy zostają na rzeczy stałe (skórki na zawsze, „sklep skórek”).
- **Osobne produkty na sezon** (przegląd Codexa, P0): potwierdzenie zakupu od Robloxa nie ma daty, więc przy tych
  samych numerach spóźniony zakup z końca sezonu 1 trafiłby do sezonu 2. Z numerem sezonu w produkcie
  (`Config.Pass.seasons[n].products`) serwer zawsze wie, za który sezon zapłacono; zakup za sezon, który już się
  skończył, rozlicza ten sezon od razu (zaległe nagrody z poziomu zapisanego w `passHistory`).
- **Rozliczenie każdego zakupu** (czysta funkcja `Pass.settle`, testy). Przyciski w oknie ukrywają złe kombinacje,
  a okno zakupu otwiera serwer (`PromptProductPurchase` po sprawdzeniu przez remote `PassBuy`), ale klient może
  wywołać zakup sam, więc serwer musi umieć rozliczyć wszystko:

  | Kupione | Gracz ma już | Wynik |
  |---|---|---|
  | VIP | nic | VIP |
  | OP | nic albo VIP | OP (nadpłata 199 przy VIP: VIP na następny sezon) |
  | Ulepszenie | VIP | OP |
  | Ulepszenie | nic | VIP teraz; późniejszy VIP w tym sezonie daje OP (razem 499) |
  | VIP / OP / ulepszenie | już OP (albo VIP przy VIP) | przechodzi na następny sezon (VIP albo OP) |

  Zapis: lista `passBuys` (numer zakupu, sezon, rodzaj, wynik) zapisana razem z uprawnieniem przed
  `PurchaseGranted`, niezależna od bufora 50 `receipts`. Przeniesienia na następny sezon to wpisy w tej liście,
  nie jedna flaga, więc kilka zakupów w dowolnej kolejności rozlicza się poprawnie.
- **Dlaczego 199 / 499**: obecne produkty kosztują 15–149 R$, badanie proponowało stały kosmetyczny pass 249 R$;
  tu zakup trwa jeden sezon i wymaga gry, więc VIP jest tańszy. VIP za 199 to najtańsza droga do 5 skórek;
  OP za 499 to „wszystko”. Ulepszenie za 300 nie karze za kupienie najpierw VIP. To hipoteza, nie potwierdzona
  wycena: sprawdzić w Analytics (konwersja, ile osób kupuje ulepszenie) i porównać ceny regionalne
  (Roblox obniża je do 30–100% ceny bazowej; 199 + 300 po regionalnej cenie nie musi dać 499).
- Do czasu założenia produktów: `id = 0` w Config, w Studio kupują się za darmo, na żywo przyciski są ukryte.
- Przyciski kupna znikają 1 h przed końcem sezonu; spóźnione potwierdzenia rozlicza tabela wyżej.
- **Opis produktu w Creator Hub musi mówić, że to jeden sezon** („Sezon 1: do 15.01.2027”).

## Zapis (DataService, `DATA_VERSION` 10 → 11)

```lua
pass = {
    s = 1,          -- numer sezonu, którego dotyczą pola niżej (0 = jeszcze nigdy)
    xp = 0,         -- XP w tym sezonie
    vip = false,    -- kupiona ścieżka VIP (OP też ustawia vip = true)
    op = false,
    cf = 0, cv = 0, co = 0, -- odebrane poziomy Darmowej / VIP / OP (bity 1..30)
    sc = {},        -- S (Progress.rewardScale) w chwili zdobycia każdego poziomu: monety kafelków z tego poziomu
    stars = 0,      -- odebrane Gwiazdy sezonu (monety najwyżej 20)
    day = -1,       -- dzień liczników dziennych (Progress.dayIndex)
    forest = 0,     -- surowe punkty z lasu dziś (do limitów 500 i 1 000 XP)
    feats = {},     -- dzisiejsze liczniki wyczynów: escape, nightFind, delve, forge, steal, revive
},
passHistory = {},   -- zakończone sezony: { s, xp, vip, op, settled } (rozliczenie raz, analityka)
passBuys = {},      -- każdy zakup przepustki: { id = PurchaseId, s, kind, result } (też przeniesienia na następny sezon)
boosts = { luck = 0, solo = 0, boom = 0 }, -- Schowek: mikstury i Wysypy z płatnych ścieżek, do uruchomienia
recipesRewarded = {}, -- przepisy kuźni, za które było już XP (raz na przepis)
grantedTitles = {}, -- tytuły dane wprost (przepustka, później kody), Titles sprawdza tę listę
equipped = { lantern = "", knife = "", trail = "", pickfx = "" }, -- dwa nowe sloty
```

- Skórki z przepustki trafiają do istniejącej listy `data.skins` przy odbiorze; `Skins.owns` dla
  `source = "pass"` sprawdza listę (eventy dalej liczą z liczników).
- `DataService.load` sprawdza całe struktury, nie tylko liczby: brakujące pola = domyślne; `cf/cv/co` przycięte do
  30 bitów; `xp`, `sc`, `forest` skończone i nieujemne; `feats`, `passHistory`, `passBuys` tylko ze znanymi polami;
  nieznane skórki w `equipped` = "". Test „zupełnie nowy gracz” (zasada 3) musi przejść z nowymi polami.
- Zmiana sezonu (`pass.s ~= bieżący`): rozliczenie starego sezonu (zasada 7), wpis do `passHistory` z
  `settled = true`, zerowanie, potem przeniesienia z `passBuys` na nowy sezon. Działa też przy wejściu
  po kilku sezonach przerwy (odbiór za sezon zapisany w `pass.s`, według jego zachowanej tabeli).
- Odznaka sezonu: przyznawana i ponawiana niezależnie od bitu odbioru (gdy `BadgeService` zawiedzie, następne
  wejście próbuje znowu, jak przy innych odznakach w `data.badges`).
- **Panel DEV**: `DEV_SNAPSHOT_KEYS` w `GameService` musi objąć `pass`, `passHistory`, `passBuys`, `boosts`, `skins`,
  `equipped`, `grantedTitles`, `titleChoice`, `luckUntil`, `soloBoomUntil` (zasada 1: po testach w Studio przywracamy
  zapis Toma), a `devRestore` musi odświeżyć postać (skórki) i okna. Wysyp dla serwera zmienia stan poza zapisem,
  więc w Studio test „na niby” (akcja DEV bez prawdziwego Wysypu). Akcje DEV (tylko Studio): +1 000 XP, ustaw poziom,
  daj VIP/OP, odbierz wszystko, „koniec sezonu teraz”, zeruj przepustkę.
- Po publikacji obowiązkowo **Restart Servers** (stary serwer z wersją 10 wyrzuci gracza z zapisem 11, zamiast
  go nadpisać; zasada 2).

## UI

### Pasek przy monetach (HUD, lewy górny róg)

Czwarty wiersz panelu `Stats`, pod paskiem gwarancji Złota. `UiScale.STATS_HEIGHT` 102 → ok. 130, więc rząd
przycisków, sklep i panel DEV zjadą niżej same (liczą od `rowTop`).

```
┌──────────────────────────┐
│ 🪙 12 345 678            │
│ 🧺 14/30  ▓▓▓▓▓▓░░░      │
│ ⭐ Złoto za 23  ▓▓▓░░░░  │
│ (12) ▓▓▓▓▓▓▓░░░ 340/1000 │  ← kółko z poziomem w kolorze ścieżki, klik = okno przepustki
└──────────────────────────┘
```

- Kółko z numerem poziomu: Darmowa drewno i zieleń, VIP niebieski ze złotą obwódką, OP fiolet z przesuwającym się
  gradientem (`UiFx`). Gdy coś czeka na odbiór: czerwona kropka z liczbą i delikatne podskoki (jak `SideButtons.setAttention`).
- „+12 XP” wylatuje obok paska, zbierane co ok. 1 s (przy szybkim zbieraniu nie zasypuje ekranu).
- Po 30. poziomie zamiast numeru „⭐ 3”, pasek liczy do następnej gwiazdy.
- Ostatnie 3 dni sezonu: obok paska „⏳ 3 dni”.
- **Telefon wymaga osobnego układu, nie tylko skalowania**: przy najmniejszej skali HUD (0,55) wiersz 28 px
  miałby ok. 15 px, za mało dla palca. Na małym ekranie pasek przepustki jest osobną pigułką tuż pod panelem monet,
  w skali rzędu przycisków (`UiScale.row`, co najmniej 0,8), z polem dotyku min. 40 px; rząd przycisków zjeżdża
  pod nią. Na telefonie `SideButtons` to poziomy rząd kwadratów pod „Ulepszeniami”, więc przycisk 🎟️ dochodzi
  do tego rzędu (sprawdzić, czy przy Zimie rząd się mieści, i poziomy ekran 812 × 375).

### Okno przepustki

Przycisk 🎟️ „Przepustka” w `SideButtons` (plakietka z liczbą do odebrania), klawisz **P** (wolny), klik w pasek HUD.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ 🎟️ PRZEPUSTKA LATARNIKA · Sezon 1: Duchy Puszczy           ⏳ 41 dni 6 h   ✕ │
│ (12) ▓▓▓▓▓▓▓▓░░░░░ 340 / 1000 XP        Dziś z lasu 380/500 · 🩸 XP ×2      │
├──────────────────┬───────────────────────────────────────────────────────────┤
│                  │ poz.   1      2      3   …   10     11   …   30           │
│   PODGLĄD 3D     │ ═══════●══════════════════════════════════════════════    │
│  (obraca się)    │  OP   [🟣]  [1,5S]  [🍀]  …  [🔵]  [1,5S] …  [🌌]  🔒      │
│                  │  VIP  [🔵]  [1 S]  [1 S]  …  [🟢]  [1 S]  …  [🟡]  🔒      │
│ Latarnia         │  DARM [  ]  [0,5S] [  ]   …  [⚪]  [  ]   …  [🟣]          │
│ Baby Jagi        │                                         ◄  przewijanie  ►  │
│ 🟣 EPICKA · OP 1 │                                                           │
│ [ Załóż ]        │                                                           │
├──────────────────┴───────────────────────────────────────────────────────────┤
│ [ Odbierz wszystko (4) ]   [ Jak zdobywać XP ]        [ VIP 199 ]  [ OP 499 ] │
└──────────────────────────────────────────────────────────────────────────────┘
```

- **Kafelki** w ramce koloru rzadkości. Stany: zamknięty (przygaszony, kłódka), do odebrania (świeci, podskakuje,
  „Odbierz”), odebrany (✔, przygaszony), niekupiona ścieżka (kłódka z napisem VIP/OP; klik = okno zakupu).
- **Linia postępu** nad rzędami z latarenką na bieżącym poziomie; okno otwiera się przewinięte do niej.
- **Podgląd 3D** wybranej nagrody w `ViewportFrame`: skórki latarni i nożyka budowane tym samym kodem co w dłoni
  (`HandTools` przeniesiony do `Shared`), ślady i efekty zbierania jako zapętlona animacja cząsteczek. Pod spodem
  nazwa, rzadkość, slot i „Załóż” (gdy już jest twoja).
- **Pod OP baner** z Kosmiczną Latarnią na końcu sezonu (najmocniejsza zachęta do kupna).
- **„Jak zdobywać XP”**: lista źródeł z dzisiejszymi licznikami („Ucieczki 1/3”, „Las 380/500”).
- **Schowek** (zakładka albo pasek w oknie): 🍀 × 2, 🍄 × 1, 🍄🍄 × 1, każdy z przyciskiem „Użyj”. „Odbierz
  wszystko” tylko wkłada je do Schowka, nigdy nie uruchamia.
- Telefon: okno na cały ekran, podgląd 3D jako wysuwany panel po kliknięciu kafelka, kafelki ok. 84 × 96,
  przewijanie palcem. Pada (gamepad): wybór kafelków strzałkami (`GuiService.SelectedObject`).

### Odbiór, nowy poziom, zakup

- **Nowy poziom**: krótki napis u góry „🎟️ Poziom 13!” z nagrodami tego poziomu w trzech rzędach; zamknięte
  nagrody VIP/OP widać z kłódką (delikatna zachęta, bez wyskakującego okna zakupu).
- **Odbiór skórki**: karta jak `FindCard` (model 3D, nazwa w kolorze rzadkości, przycisk „Załóż teraz”);
  kafelek leci do paska. Monety lecą do licznika monet jak przy zadaniach.
- **Zakup**: okno z listą „Od razu odbierzesz…”, potem `PromptProductPurchase`. Po potwierdzeniu z serwera
  rząd VIP/OP odblokowuje się błyskiem przesuwającym się po kafelkach i wszystkie zaległe zaczynają świecić.
- Okno korzysta z `PanelKit` i `UiKit` (ten sam styl co Kuźnia i Zadania). Stan przepustki przychodzi w
  `ProgressUpdate` (pole `pass`), a okno i HUD zapisują się przez `ProgressFeed.subscribe` (zasada 4).
  `ProgressService.send` pomija stan o tym samym odcisku, a odcisk to stała lista pól: **stan przepustki musi
  do niego trafić**, inaczej XP i odblokowanie VIP nie dojdą do klienta. Żeby nie wysyłać całego stanu przy
  każdym grzybie, XP do paska idzie zbiorczo (najwyżej raz na ok. 1 s).

### Garderoba (minimalna, w etapie 2)

Przegląd Codexa: poza sezonem okno przepustki znika, a bez Garderoby gracz nie miałby gdzie z powrotem założyć
kupionej skórki. Dlatego już w pierwszej wersji małe okno „Garderoba”: cztery sloty (latarnia, nożyk, ślad,
efekt zbierania), w każdym lista posiadanych skórek (z przepustki i eventów) i „Zdejmij”. Pełna Garderoba z
podglądem 3D i sortowaniem według rzadkości to późniejszy etap (sekcja na końcu).

## Serwer i bezpieczeństwo

- `PassService` (nowy): `add` (XP, limity, Krwawy księżyc), `claim(season, tier, track)` przez remote `PassClaim`
  (sprawdza sezon, poziom, kupioną ścieżkę, bit odebrania; odbiór i bit w jednym kroku, bez podwójnych odbiorów),
  `claimAll`, `useBoost`, `buy` (sprawdza i otwiera zakup z serwera), `settle` z `grantProduct`, `rollover` na
  początku każdego wywołania i dodatkowo co minutę (koniec sezonu w trakcie gry). Wejście przez `joinStep`
  (zasada 5), **przed pierwszym wysłaniem stanu postępu**, żeby okna od razu miały pole `pass`.
- Remote z limitem częstotliwości jak inne przyciski (`cooledDown`).
- Monety z przepustki idą przez `Ledger` ze źródłem `pass` (Analytics economy events), osobno od zadań.
- `EquipSkin` dostaje sloty `trail` i `pickfx`; walidacja przez `Skins.owns`, jak dziś.
- Ślad: serwer ustawia atrybut postaci (`TrailSkin`), każdy klient rysuje ślad u wszystkich graczy i odtwarza go
  po odrodzeniu i po powrocie postaci ze streamingu.
- Efekt zbierania: sam atrybut nie wystarczy, bo każdy gracz ma własny las i zniknięcie grzyba widzi tylko
  zbierający. Serwer przy zbiorze wysyła krótki sygnał (`UnreliableRemoteEvent`: kto, gdzie, jaki efekt) do graczy
  w pobliżu. Bez `BillboardGui`; gdyby powstał napis nad głową, to przez `BillboardGuard` (zasada 11).
- `HandTools` w `Shared` zachowuje obecny kontrakt: nazwy modeli, część `LanternGlass` (przyciemnianie przy braku
  oleju) i atrybuty `Skin` / `Tier` / `Level`, od których zależy przebudowa narzędzi w `GameService`.
- Rzadkość „kosmiczna” dochodzi tylko w katalogu skórek; klasy grzybów (`Config.Classes`) się nie zmieniają.

## Pliki do zmiany

| Plik | Co |
|---|---|
| `src/shared/Pass.luau` (nowy) | sezony, tabela nagród, funkcje czyste: poziom z XP, limity, bity odbioru, odbiór wsteczny, koniec sezonu, „co odbierzesz po zakupie” (testy w Lune) |
| `src/shared/Config.luau` | `Config.Pass` (sezony z datami i produktami `vip/op/upgrade` z `id = 0`, XP źródeł, limity, Gwiazdy), `Config.Badges.pass_s1 = 0` |
| `src/shared/Skins.luau` | rzadkość, źródło (`event` / `pass` / później `shop`), sloty `trail` i `pickfx`, `owns` dla przepustki |
| `src/shared/HandTools.luau` (przeniesiony z `src/server/World`) | 7 latarni i 5 nożyków; podgląd w `ViewportFrame` u klienta |
| `src/client/SkinFx.luau` (nowy) | ślady i efekty zbierania u wszystkich graczy |
| `src/server/PassService.luau` (nowy) | XP, odbiór, Schowek, zakup i rozliczenie, koniec sezonu |
| `src/server/ProgressService.luau` | wywołania `PassService.add` w `event`, `found`, odbiorze logowania; pole `pass` w `ProgressUpdate` i w odcisku |
| `src/server/GameService.luau` | `joinStep("pass")`, rozliczenie zakupów przepustki, XP za ucieczkę tylko z grzybem strażnika, sygnał efektu zbierania, `DEV_SNAPSHOT_KEYS`, akcje DEV, sloty skórek przy postaci |
| `src/server/ForgeService.luau` | zdarzenie „odkryty przepis” (raz na przepis) |
| `src/shared/Progress.luau` | losowanie zadań dnia bez zadań niemożliwych dla gracza (osobna poprawka przed sezonem) |
| `src/server/DataService.luau` | pola zapisu, `DATA_VERSION` 11, sprzątanie przy wczytaniu |
| `src/server/HalloweenService.luau`, `WinterService.luau` | `onEquip` dla nowych slotów (albo wspólny `SkinService`) |
| `src/shared/Titles.luau` | tytuły przepustki (`special = "pass"`) z `grantedTitles` |
| `src/shared/Remotes.luau` | `PassClaim`, `PassClaimAll`, `PassBuy`, `PassUseBoost`, `PickFx` (Unreliable) |
| `src/client/PassPanel.luau` (nowy) | okno przepustki ze Schowkiem |
| `src/client/WardrobePanel.luau` (nowy) | minimalna Garderoba (4 sloty, „Zdejmij”) |
| `src/client/Hud.luau`, `src/client/UiScale.luau` | czwarty wiersz panelu, `STATS_HEIGHT` |
| `src/client/Purchases.luau`, `src/client/DevPanel.luau` | zakup ścieżek, akcje DEV |
| `src/localization/GameStrings.csv` | nazwy skórek, tytułów, napisy okna (bez przecinków) |
| `tests/economy.spec.luau` | testy niżej |
| `tools/pass_sim.luau` (nowy) | tempo XP dla profili graczy |
| `docs/HANDOFF.md`, `docs/Odznaki.md` | opis, odznaka sezonu |

## Etapy i testy

0. **Przed sezonem, osobno**: losowanie zadań dnia bez zadań niemożliwych dla weterana.
1. **Logika i zapis** (bez okna): `Pass.luau`, `PassService`, zapis 11, produkty z `id = 0`, akcje DEV, testy,
   `tools/pass_sim.luau`.
2. **HUD i okna**: pasek, okno przepustki ze Schowkiem, minimalna Garderoba, odbiór, karta skórki, zakup w Studio
   (darmowy przy `id = 0`). Najpierw prototyp podglądu 3D i jednego efektu cząsteczek, potem reszta.
3. **Skórki**: 16 skórek (najpierw tanie: kolory, ślady, efekty; potem modele), podgląd 3D, sloty.
4. **Test w Studiu z Tomem** (zasada 1: najpierw pytanie, czy Tom nie gra na żywo; na start `devSnapshot`,
   na końcu `devRestore`), potem produkty i odznaka w Creator Hub, publikacja przez Toma, Restart Servers.
5. **Po starcie**: Analytics po tygodniu; wyzwania tygodnia, jeśli kupujący utykają.

Testy w Lune (muszą przechodzić przed commitem):
- poziom z XP, Gwiazdy po 30., limit „las” (pełne do 500, potem ¼, najwyżej 1 000; zbiór na granicy 500 z
  ułamkami) i nowy dzień, limity wyczynów, Krwawy księżyc;
- odbiór: tylko osiągnięty poziom, tylko kupiona ścieżka, drugi odbiór nic nie daje, OP odblokowuje VIP,
  monety z S zamrożonego przy zdobyciu poziomu, mikstura i Wysyp do Schowka (także przy „Odbierz wszystko”);
- zakup wstecz (lista „od razu / później”); każdy wiersz tabeli rozliczeń (ulepszenie bez VIP, OP po VIP,
  drugi VIP, zakupy w odwrotnej kolejności); spóźniony zakup za skończony sezon; potwierdzenie ponowione
  po nieudanym zapisie (bez podwójnego przyznania);
- koniec sezonu: zaległe skórki, tytuły, monety, Schowek i Gwiazdy trafiają do gracza raz (drugie rozliczenie nic
  nie daje), XP i ścieżki się zerują, `passHistory`; wejście po dwóch sezonach przerwy; koniec bez następnego
  sezonu w Config; granica sezonu co do sekundy (UTC); odbiór z okna z numerem starego sezonu odrzucony;
- koniec sezonu albo wyjście w trakcie animacji kuźni (XP i znalezisko się nie gubią, jak w poprawce `43f7fdd`);
- **zasada 7**: żaden kafelek Darmowej ścieżki nie daje mikstury ani Wysypu;
- każda skórka z tabeli istnieje w `Skins` z rzadkością zgodną z tabelą; każdy tytuł istnieje w `Titles`;
- na każdym poziomie VIP ma więcej punktów wartości niż Darmowa, a OP więcej niż VIP (punkty jak w sekcji
  „Poziomy i nagrody”);
- „zupełnie nowy gracz” z nowymi polami, stary zapis 10 → 11, śmieci w polach `pass`;
- klucze z `Localize.t` są w CSV (istniejący test).

## Ryzyka

| Ryzyko | Co z tym robimy |
|---|---|
| 16 skórek to najwięcej pracy (12 modeli z części) | najpierw tanie skórki; modele po kolei; w razie poślizgu start sezonu przesuwa się w Config, nie w kodzie |
| `DATA_VERSION` 11: gracz na starym serwerze | Restart Servers po publikacji (zasada 2), jak zawsze |
| Test w Studiu zmienia prawdziwy zapis Toma | `DEV_SNAPSHOT_KEYS` z polami przepustki; pytanie przed Play (zasada 1) |
| Zakup przychodzi po końcu sezonu, w złej kolejności albo bez wczytanego zapisu | produkty na sezon, `passBuys` i tabela rozliczeń; `NotProcessedYet` bez zapisu, jak dziś |
| Klient sam wywołuje zakup (np. ulepszenie bez VIP) | serwer rozlicza każdą kombinację, niczego nie zjada bez rekompensaty |
| Gracze kupią VIP/OP i nie dojdą do końca | tempo z tabeli (regularny kończy w 4–4,5 tygodnia z 8), wyzwania tygodnia jako zapas, Analytics poziomów |
| Tempo to hipoteza | `tools/pass_sim.luau` i porównanie z Analytics po tygodniu |
| Monety z płatnych ścieżek = płatna przewaga (ulepszenia, `richest`) | 48 S ponad Darmową, S zamrożone przy zdobyciu poziomu; decyzja 11 |
| Mikstura w płatnych ścieżkach zjada sprzedaż mikstury 49 R$ | tylko 2–3 sztuki; decyzja 5 |
| Wysyp dla serwera pomaga też niepłacącym | tak samo jak dzisiejszy produkt `boom`; to zaleta (Dawca Wysypu), nie darmowy zamiennik |
| Automat zbierający całą dobę | twardy limit 1 000 XP z lasu dziennie |
| Alty farmią XP kradzieżą i podnoszeniem | dzienne limity (razem do 240 XP); XP i nagrody nie przechodzą między kontami |
| Weteran nie może zrobić zadania `upgrade` / `discover` | osobna poprawka losowania zadań przed sezonem |
| Za ciasno w lewym górnym rogu na telefonie | osobna pigułka w skali rzędu przycisków, pole dotyku min. 40 px; przegląd na 375 × 812 i 812 × 375 |
| Kupiona skórka bez okna, w którym można ją założyć | minimalna Garderoba już w etapie 2 |
| Nazwa VIP zderza się z pomysłem kosmetycznego VIP 249 R$ | ten pomysł odkładamy (decyzja 9) |
| Sezon kończy się, gdy gracz jest w grze | sprawdzenie sezonu w każdym wywołaniu i co minutę; rozliczenie jednokrotne |
| Skórka wpływa na widoczność (kolor światła) | skórki nie zmieniają `PointLight` latarni, tylko model |

## Jak to się łączy z kolejnymi pomysłami Toma

- **Wybór skórek (pełna Garderoba)**: rozbudowa minimalnej Garderoby z etapu 2 o siatkę wszystkich skórek z
  podglądem 3D, sortowanie według rzadkości i źródła. Korzysta z tego samego `Skins` (rzadkość, źródło) i remote
  `EquipSkin`. „Załóż” zostaje też w oknie przepustki i na karcie nowej skórki.
- **Skórki za monety i za Robux (sklep skórek)**: `Skins.source = "shop"`. Za monety: zlew monet z badania
  (ceny w S, np. 3 S i 10 S, bez zwrotu przy sprzedaży), za Robux: **gamepass na skórkę** (stała własność,
  widoczny na stronie gry). Skórki przepustki do sklepu nie trafiają.
- **Gamepassy i produkty do założenia w Creator Hub**: dla przepustki 3 produkty dewelopera na każdy sezon
  i 1 odznaka (wyżej);
  zaległe: `boomSolo`, `x2s/m/l/xl` i odznaki z `id = 0` (`HANDOFF.md`, otwarte zadania 2–3).
  Gamepassy dopiero przy sklepie skórek.
- **Rebirth**: jeśli zeruje monety i światy, to S spada, więc kafelki z monetami odebrane po rebircie są warte mniej;
  XP i poziom przepustki rebirth zostawia. Rebirth może dawać XP (np. 2 000) i własne skórki w tym samym `Skins`.
- **Pety**: najprościej jako kolejny slot kosmetyczny (`pet`) w `Skins`, bez premii (premia = pay-to-win, sprzeczne
  z badaniem). Wtedy pet może być nagrodą OP w sezonie 2 albo przedmiotem sklepu.

## Analityka

- `Milestone_Pass_Tier_<n>` (1, 5, 10, 15, 20, 25, 30) i `Milestone_Pass_Star_1`;
- zakupy: `PassPurchase_vip / op / upgrade` z poziomem w chwili zakupu, `PassWindowOpened`, `PassBuyPrompt`;
- XP według źródła (zbiorczo przy wyjściu gracza, bez zdarzenia na każdy grzyb);
- monety z przepustki jako źródło `pass` w economy events (`Ledger`).

## Przegląd Codexa (6.11.2026, xhigh)

Codex przeczytał projekt i kod (bez zmian w plikach). Co zmieniło się w projekcie po jego uwagach:

| Waga | Uwaga | Zmiana w projekcie |
|---|---|---|
| P0 | Te same numery produktów w każdym sezonie: spóźniony zakup trafia do złego sezonu; jedna flaga `credit` nie zniesie kilku zakupów | produkty na sezon, lista `passBuys`, tabela rozliczeń |
| P0 | Ukrycie przycisku ulepszenia to nie walidacja (klient może sam wywołać zakup) | serwer rozlicza każdą kombinację; zakup otwiera serwer po sprawdzeniu |
| P0 | Pętla co minutę nie pilnuje granicy sezonu | sprawdzenie sezonu w każdym `add` / `claim` / zakupie, numer sezonu w żądaniu, rozliczenie jednokrotne, stare tabele zostają |
| P1 | Okazjonalny gracz z dwoma zadaniami nie ma kompletu (350, nie 410 stałych) | tabela tempa poprawiona (poziom ok. 14) |
| P1 | Miękki limit lasu nie zatrzymuje automatu | twardy limit 1 000 XP dziennie |
| P1 | Weteran nie zrobi zadań `upgrade` / `discover` | osobna poprawka losowania zadań (etap 0) |
| P1 | Monety z płatnych ścieżek pomagają też w ulepszeniach; zakup wstecz po otwarciu świata daje więcej | S zamrożone przy zdobyciu poziomu; decyzja 11 |
| P1 | Darmowa mikstura za komplet zadań i 7. dzień logowania jest poza wyjątkami zasady 7 | decyzja 12 (osobno od przepustki) |
| P1 | Ucieczka bez sprawdzenia grzyba, kuźnia bez zdarzenia przepisu, `delve` = ognisko, reset dnia co 15 s | doprecyzowane w tabeli XP |
| P1 | Odcisk w `ProgressService.send` nie zna przepustki | stan przepustki w odcisku, XP zbiorczo |
| P1 | `devSnapshot` bez `passHistory`, `luckUntil`, `soloBoomUntil`, `titleChoice` | lista kluczy uzupełniona, Wysyp serwera w Studio na niby |
| P1 | Efekt zbierania: inni gracze nie wiedzą, kiedy i gdzie ktoś zebrał grzyb | sygnał `PickFx` do graczy w pobliżu |
| P1 | Poza sezonem nie ma gdzie założyć skórki | minimalna Garderoba w etapie 2 |
| P1 | Telefon: 15 px wiersza przy skali 0,55; `SideButtons` to tam poziomy rząd | osobna pigułka z polem dotyku 40 px |
| P1 | „Odbierz wszystko” odpaliłby naraz mikstury i Wysypy | Schowek (`boosts`), uruchamianie osobno |
| P1 | Testy tylko funkcji czystych | testy awarii (ponowione potwierdzenie, kolejność zakupów, granica sezonu, kuźnia) |
| P2 | Ceny to hipoteza, ceny regionalne | okno zakupu „od razu / później” z datą końca; porównanie regionalne |
| P2 | Kontrakt `HandTools` (nazwy, `LanternGlass`, atrybuty) i prototyp cząsteczek | wpisane w sekcji serwera i w etapie 2 |

Uwaga Codexa: symulator ekonomii u niego się nie uruchomił (błąd katalogu domowego), więc liczby ekonomii w tym
dokumencie pochodzą z przebiegu na PC Toma (6.11).
