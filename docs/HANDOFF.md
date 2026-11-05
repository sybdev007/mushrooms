# Handoff — Midnight Mushroom Hunt

Stan na **5.11.2026, po przeróbce kuźni na runę** (czas polski). Zasady pracy i komendy są w `CLAUDE.md` (Claude Code czyta go sam).
Tu: co jest w grze, co zrobiliśmy ostatnio, co jest otwarte. Aktualizuj ten plik po większych zmianach.

## Gdzie co jest

- Repo `sybdev007/mushrooms`, gałąź **`main`** (wszystko scalone, ostatni commit z poprawką nowych graczy: `ef4ae0a`,
  opublikowany 5.11 ok. 01:00 i sprawdzony na żywo).
  Gałęzie `petla`, `lysa-gora`, `feat/tryb-filmowy` itd. są już w `main`; nie pracuj na nich.
- PC Toma: `T:\lantern\mushrooms` (Rojo serwuje stąd). MacBook: `~/coding/mushrooms` (Intel: `selene` z Rokit
  to wersja na ARM i się nie uruchamia, lint rób na PC; `lune` i `rojo` działają).
- **Kuźnia v3 (runa)** z `fcc1f0f` opublikowana 5.11 (Tom: działa na żywo).
- Notatki: `docs/plans/loop-research.md` (plan pętli, gabloty i Znaleziska) i `docs/plans/review-petla.md`
  (przegląd gałęzi `petla` od Codexa) są w repo od `8bc2c69`.
- Gra: universe 10772830253, place 72216132547990, grupa Old Owl Studios 463484833.

## Co jest w grze

Nocne zbieranie grzybów z latarnią (olej, koszyk). Cztery światy za portalami:
las → jaskinia (30 000 monet) → bagna (1 000 000) → **Łysa Góra** (10 000 000).
- Mutacje: warianty Srebro → Złoto → Tęcza → **Kosmiczny** (ranga 4, na wszystkich mapach) + cechy stref
  (Mech, Blask, Kryształ, Żar Otchłani; na górze Przeklęty, Zaklęty, Księżycowy) i cechy eventów (Dynia, Szron).
- Strażnicy: Leszy, Skarbnik, Utopiec, **Baba Jaga** (chatka na kurzej stopce na szczycie, kruki w Wiedźmim Lesie
  i Kotłach Sabatu, trujące opary kotłów). Kradzież ich grzybów → pościg (`ChaseService`).
- Ogródki (6 na serwer): dochód, skrzynia z limitem, dochód offline, kradzież z cudzych ogródków (scenka),
  pogoda nocy zmienia grzyby w ogródku (`GardenWeather`), **gablota** na kopie z Grzybopedii i trofea.
- **Znalezisko Nocy**: jeden legendarny grzyb na noc na serwer, donieść do chatki; trofea i tytuły.
- **Moździerz Zielarki (kuźnia, wersja 3: runa)**: 3 dowolne grzyby → runa sumuje wkład i wyłania grzyb
  ze wszystkich światów w progu skucha 22% / gorszy 36% / podobny 25% / lepszy 14% / wielki 3% wkładu,
  wariant z „gorąca” wkładu, do 4 cech, opłata 8%. Ukryte przepisy i trójki strażników (Kwiat Paproci,
  Oko Welesa) działają w 70%. Okno i animacja według projektu Toma (krąg run, trójkąt, bęben, błysk).
  Zasady: `src/shared/Forge.luau`, `docs/plans/kuznia.md` (sekcja „wersja 3”), symulator `tools/forge_odds.luau`.
- **Ekspedycja do Głębokich Komór** (tablica zleceń w Obozie, relikty, regał). `docs/plans/cave-expedition.md`.
- Grzybopedia, tytuły, zadania dzienne (odbiór ręczny), seria logowań, rankingi, wyprawy grupowe.
- **Ścieżka grzybiarza** (od 5.11, `src/shared/ForagerPath.luau`): po samouczku karta misji prowadzi przez
  6 celów do otwarcia Jaskini (buty 3, 8 gatunków, mutacja, Korona Leszego, ucieczka, 30 000 monet i portal).
  Bez nagród i nowych pól zapisu; analityka `Milestone_Path_<id>` pokazuje, gdzie nowi gracze odpadają.
- **Karta zdobyczy** (od 5.11, `src/client/FindCard.luau`): nowa forma w Grzybopedii Złota+, grzyb strażnika
  albo z kuźni (`Showcase.cardWorthy`) = karta u góry ekranu z modelem 3D i przyciskiem „Wystaw w gablocie”
  (z dowolnego miejsca, tylko na wolne kupione miejsce, `Showcase.quickSlot`). Nad regałem tabliczka
  „🏆 imię · N 🍄”. Analityka `Milestone_FindCardShowcase`.
- **Prognoza nocy** (od 5.11, `src/client/NightForecast.luau`, `Cycle.upcoming/nextOf/effects`): 🔮 przy zegarze
  nocy albo klawisz N; bieżąca noc z działaniem, najbliższy Krwawy księżyc, 5 następnych nocy. Zapowiedź
  Krwawego księżyca w HUD 10 min wcześniej. Do pierwszego otwarcia 🔮 pulsuje z dymkiem (`settings.forecastSeen`,
  DEV → Samouczek → „Podpowiedź prognozy od nowa”). `tools/night_forecast.luau` do Roblox Events.
- **Wskazówki do przepisów kuźni** (od 5.11, `Forge.warmth` / `Forge.hints`): w moździerzu „🔥 Ciepło!”, gdy
  2 z 3 grzybów pasują do nieodkrytego przepisu; w Grzybopedii co `Config.Forge.hintEvery` (5) połączeń kolejny
  składnik z nazwy (najwyżej 2 z 3), licznik do następnej; Oko Welesa po Kwiecie Paproci: „wśród nich Baba Jaga”.
- **Zbiórka do ekspedycji** (od 5.11, `client/DelveCall.luau`, `DelveService.callCrew`): wzięte zlecenie =
  karta „X zbiera ekipę” z „Dołącz” u graczy z Jaskinią (dołączenie z dowolnego miejsca); gotowość ✅/🚶
  (20 studów od szczeliny) w oknie tablicy i karcie celu; kto wchodzi, zabiera gotowych; „Zaproś znajomego”.
  Analityka `Milestone_DelveCrew` (liczba osób przy starcie). Sprawdzone na dwóch kontach.
- **Górska półka gabloty i Ofiara dla Leszego** (`93324e9`, plan `docs/plans/endgame-zlew.md`, DATA_VERSION 10):
  seria 4 gabloty od Łysej Góry (5,2–166,4 mln, razem 327,6 mln; regał z czwartą półką, okno na 4 rzędy);
  kapliczka na Placu Portali naprzeciw moździerza (`ShrineService`, `ShrinePanel`, `Shared/Shrine`): wpłaty
  1 / 10 / 100 mln / 1 mld z potwierdzeniem, serwer sprawdza wszystko (bez tokenów), `stats.leszyOffered`,
  tytuły 100 mln – 20 mld, obwódka tabliczki ogródka od 1 / 5 / 10 mld. Globalny ranking: osobny etap po pilotażu.
  Test w Studiu 5.11: OK; opublikowane i sprawdzone na żywo (kapliczka, wpłata, górska półka). Do obejrzenia
  później: okno gabloty na telefonie i obwódka tabliczki od 1 mld. Za tydzień w Analytics: `LeszyOffering`,
  `Milestone_LeszyFirstOffering`, `Milestone_MountainShowcaseFirst/Complete`; potem decyzja o rankingu.
- Eventy (daty w `Config`, UTC): **Halloween do 10.11 00:00** (cukierki, kocioł, Noc Dziadów),
  **Zima 1.12 – 7.01** (płatki, choinka, kalendarz adwentowy). Zima jeszcze nie była na żywo:
  sprawdzić w Studio przed 1.12 (panel DEV).
- Społeczność: Old Owl Studios (+10% szczęścia, tytuł, paczka powitalna raz na konto z 15 min mikstury
  — świadomy wyjątek od „mikstura tylko płatna”), znajomi +10%, zaproszenia.
- Panel DEV (`Config.DevUserIds`: Tom, Miłosz): na żywo tylko część akcji (`Config.DevLiveActions`),
  reszta w Studio. **Tryb filmowy** (DEV → 🎬): czysty ekran i ujęcia do nagrań; klawisze L / K / J / U.

### Łysa Góra po przeróbce „x1000” (4.11)
Prawdziwa góra z trójkątów (`src/shared/MountainTerrain.luau`: siatka, profil wysokości, serpentyny, pady pod
bramy i kotły), urwisko nad doliną z rzeką i wioską, kamienna ścieżka z czaszkowymi latarniami, krąg kamieni
z wielkim ogniskiem, chatka na szczycie. Niebo po stronie klienta (`src/client/MountainSky.luau`): księżyc za
szczytem, czarownice na miotłach, nietoperze, pioruny, morze chmur z cząsteczek. Klimat w `Atmosphere.luau`.
Opis i liczby: `docs/plans/lysa-gora.md` (sekcja „Prawdziwa góra i nocne niebo”).

## Noc 4/5.11: awaria „Label” i co naprawiliśmy

Objawy: biały ekran przy wejściu, w oknach Zadań / Tytułów / Grzybopedii same napisy „Label”, nowy gracz
(kolega Toma) nie miał nic. Przyczyny i poprawki (wszystko w `main`):

| Commit | Problem | Poprawka |
|---|---|---|
| `ef4ae0a` | **Nowi gracze w ogóle nie mogli grać** od poprawek z przeglądu (`91e1231`): `DataService.load` czytał `raw.version`, gdy `raw = nil` (brak zapisu) → błąd, brak sesji | sprawdzenie `typeof(raw) == "table"`; test „zupełnie nowy gracz” |
| `f6f9939` | `ProgressUpdate` wysłany przy wejściu, zanim klient podłączył odbiorniki → Roblox oddaje go tylko pierwszemu (okno Halloween); reszta okien pusta | `src/client/ProgressFeed.luau`: jedno podłączenie, pamięta ostatni stan |
| `40cf7fc` | błąd w `GardenService.assign` / `ProgressService.join` przerywał resztę wejścia | `joinStep` z xpcall i śladem w konsoli serwera |
| `d28c371` | przy awarii DataStore Robloxa („Access forbidden”) ProfileStore ponawiał bez końca, gracz w grze bez danych | po 60 s (z ponowieniami ok. 70 s) wyrzucenie z wyjaśnieniem; ekran wczytywania czeka do 90 s i po 12 s pisze „Roblox odpowiada wolno” |

**Sprawdzone po publikacji `ef4ae0a` (5.11):** wejście nowym kontem (samouczek, zadania), pierwsze wejście Toma na
świeży serwer (Zadania od razu wypełnione), F9 → Server bez czerwonych linii. Wszystko działa.

### Zapis Toma (incydent 4.11)
O 18:59 UTC serwer ze starą wersją (DATA_VERSION 6) zgubił mu pola zapisu; przywrócony ręcznie
(UpdateAsync, bez aktywnej sesji). Od tego czasu jest strażnik wersji (pkt 2 w `CLAUDE.md`).
Ostatni znany stan: ok. 174 mln monet, 33 śmierci, 18 ucieczek, Łysa Góra otwarta, latarnia `ice_lantern`.
Magazyn `LanternForager_Profiles_v1`, klucz `player_1293490018`.

## Otwarte zadania

0. ~~Opublikować `51d208e` + `af8fa4f`~~: opublikowane 5.11 wieczorem, Tom sprawdził (zapis przy wyjściu,
   F9 → Server czysto, ucieczka przed Jagą). `51d208e`: od kuźni v3 każde wyjście gracza wywalało
   `onPlayerRemoving` (devSnapshots przed deklaracją). `af8fa4f`: Baba Jaga 43 → 36 studs/s. Jeśli okaże się
   za łatwa, 37–38 też da się przebiec na butach 15–16 (test „Baba Jaga: zapas”).
   `831bd15` (opublikowane i sprawdzone 5.11): napisy „Znalezisko Nocy”, tytuły graczy, Dawca Wysypu i x2
   skrzyni wisiały przed chatką, gdy ich część wypadła ze streamingu. Teraz `BillboardGuard` (zasada 11 w `CLAUDE.md`).
   `43f7fdd` (opublikowane i sprawdzone 5.11): poprawki kuźni v3 z przeglądu Codexa. Wyjście w trakcie animacji
   nie gubi Grzybopedii i licznika, `Forge.preview` liczy średni zwrot dokładnie (maxReturn 0,9 trzymany),
   `devSnapshot`/`devRestore` najpierw rozliczają kuźnię. Codex nie znalazł P0 ani trójki z zyskiem.
1. ~~Opublikować `main` z kuźnią v3~~: opublikowane 5.11, Tom potwierdził, że działa. Do obserwacji przez kilka
   dni: Analytics kuźni (ile połączeń, które progi), czy gracze nie narzekają na skuchy przy drogich trójkach.
   Lint `selene src` na PC jeszcze nie puszczony. W Studio sprawdzone 5.11: trójka z góry (gorszy 0,53×), przepis (dzwonek mszysty 1,21×), tania trójka
   (skucha), po polsku i po angielsku, konsola czysta. Zapis Toma po teście przywrócony („Przywróć stan”).
   (Od 5.11 wieczorem `DATA_VERSION` = 9: `settings.forecastSeen` przy Prognozie nocy.)
2. **Odznaki z id = 0** w `Config.Badges`: `grandmaster`, `cosmic`, `forge_collection`, `winter2026`
   (Tom zakłada w Creator Hub, 5 dziennie za darmo; numery z
   `https://badges.roblox.com/v1/universes/10772830253/badges`). Opisy i obrazki: `docs/Odznaki.md`, `assets/badges/`.
3. **Produkty z id = 0** w `Config.Products`: `x2s / x2m / x2l / x2xl` (19/39/79/149 R$, Unlisted),
   `boomSolo` (Twój Wysyp, zwykły produkt, roboczo 49 R$). Bez numeru karta jest ukryta na żywo.
4. Zima: kod przejrzany 5.11 (daty, zapis, serwer, okno; bez błędów). Mikstura z nagród zimy zostaje jak
   w Halloween (zasada 7 w `CLAUDE.md`). **Test w Studiu 5.11 (przez MCP): wszystko działa.** Wystrój 251
   części (mapa ok. 29 tys.), śnieg pada w lesie i nie pod dachem chatki, ścieżka płatków, choinka (monety,
   mikstura, płatki, duplikat skórki → monety, 4 psikusy), kalendarz (drugi raz tego dnia nic), Zamieć
   (51% oszronionych), wyłączenie zimy sprząta wystrój i śnieg. Zostało: odznaka `winter2026` (id = 0).
   Uwagi: przy Halloween i Zimie naraz przycisk Zimy spada pod ekran (1.12 Halloween już nie ma, więc OK);
   `devRestore` nie obejmuje pól zimy (`flakeBag`, `winterClaimed`, `advent`), skórek ani `luckUntil`.
   Zimowe dane Toma z testów wyzerowane 5.11 (`winterReset`: płatki, kieszeń, progi, kalendarz, zimowe skórki);
   zimę 1.12 zaczyna od zera jak wszyscy.
   Przed zimą 2027 wyzerować `advent`, `stats.snowflakes` i `winterClaimed` (zapis nie pamięta roku).
   Drobiazg spoza zimy: `StateUpdate` ma dwóch odbiorców (ExpeditionView i Main.client), zasada 4.
5. ~~Dodać do repo `loop-research.md` i `review-petla.md`~~: zrobione (`8bc2c69`).
6. Monetyzacja (`docs/plans/monetization-research.md`): NIE dla stałego x2 monet, gatunków za Robux, x2 za monety.
   Do pilotażu po tygodniu obserwacji Analytics: kod 0,25 S raz na konto, kosmetyczny VIP 249 R$.
7. Pomysły z researchu hitów (`docs/plans/hit-research.md`, Codex 5.11). Zrobione: Ścieżka grzybiarza,
   karta zdobyczy i tabliczka gabloty, Prognoza nocy, wskazówki do przepisów kuźni, zbiórka do ekspedycji
   (cały ranking z punktów 1–6). Za ok. tydzień sprawdzić w Analytics `Path_*`, `FindCardShowcase` i `DelveCrew`.
   Z jego listy zostają: tygodniowe tematy (np. „Tydzień Leszego”) i kosmetyczny VIP — po danych z Analytics.
   Roblox Events (Tom, Creator Hub): wieczorne Krwawe księżyce z `lune run tools/night_forecast.luau`.

## Numery

- Produkty: rescue 3724758636 (59 R$), boom 3724757048 (99), oil 3724758135 (15), harvest 3724757863 (29),
  luck 3724757551 (49).
- Odznaki gotowe: first_mushroom, cave, swamp, gold, rainbow, leszy, skarbnik, utopiec, atlas_page, lifesaver,
  streak7, halloween2026, mountain, jaga, forge_first (numery w `Config.Badges`).
- Dźwięki gry: `Config.Audio` (m.in. thunder, thunderClose, witchFly z Pro Sound Effects).

## Pułapki techniczne

- Studio renderuje 3D na szaro/czarno, gdy okno jest schowane; GUI widać normalnie (zrzuty przez MCP).
- `screen_capture` w Studio nie widzi BillboardGui z `AlwaysOnTop`.
- `Lighting.GeographicLatitude = 100` + `ClockTime 0` stawia księżyc nisko za szczytem góry (Atmosphere).
- Mapa ma ok. 27,5 tys. części (sama góra ok. 6 tys.); build serwera jest synchroniczny w `MapBuilder.build`.
- Ranking: Studio i deweloperzy nie trafiają na tablice (`LanternForager_Top_v2_*`).
- Typy: `luau-lsp analyze` z definicjami Robloxa i sourcemapą z `rojo sourcemap` (stare błędy typów są znane;
  porównuj z poprzednim wynikiem, nie licz na zero).
