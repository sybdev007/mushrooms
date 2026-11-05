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
1. ~~Opublikować `main` z kuźnią v3~~: opublikowane 5.11, Tom potwierdził, że działa. Do obserwacji przez kilka
   dni: Analytics kuźni (ile połączeń, które progi), czy gracze nie narzekają na skuchy przy drogich trójkach.
   Lint `selene src` na PC jeszcze nie puszczony. W Studio sprawdzone 5.11: trójka z góry (gorszy 0,53×), przepis (dzwonek mszysty 1,21×), tania trójka
   (skucha), po polsku i po angielsku, konsola czysta. Zapis Toma po teście przywrócony („Przywróć stan”).
   Nowych pól zapisu nie ma, `DATA_VERSION` bez zmian (8).
2. **Odznaki z id = 0** w `Config.Badges`: `grandmaster`, `cosmic`, `forge_collection`, `winter2026`
   (Tom zakłada w Creator Hub, 5 dziennie za darmo; numery z
   `https://badges.roblox.com/v1/universes/10772830253/badges`). Opisy i obrazki: `docs/Odznaki.md`, `assets/badges/`.
3. **Produkty z id = 0** w `Config.Products`: `x2s / x2m / x2l / x2xl` (19/39/79/149 R$, Unlisted),
   `boomSolo` (Twój Wysyp, zwykły produkt, roboczo 49 R$). Bez numeru karta jest ukryta na żywo.
4. Zima: przegląd i test w Studio przed 1.12.
5. ~~Dodać do repo `loop-research.md` i `review-petla.md`~~: zrobione (`8bc2c69`).
6. Monetyzacja (`docs/plans/monetization-research.md`): NIE dla stałego x2 monet, gatunków za Robux, x2 za monety.
   Do pilotażu po tygodniu obserwacji Analytics: kod 0,25 S raz na konto, kosmetyczny VIP 249 R$.

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
