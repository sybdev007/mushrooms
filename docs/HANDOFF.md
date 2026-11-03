# Handoff — Midnight Mushroom Hunt

Stan na 2026-11-03. Ten plik czyta nowy czat z Claude na start pracy nad grą („przeczytaj docs/HANDOFF.md”).
Aktualizuj go, gdy zmieni się coś z poniższych list.

## Kto i jak pracuje

- **Tom** (GitHub sybdev007, Roblox: noscopeninjadoritos, UserId 1293490018) i **Miłosz** (GitHub Develarper77,
  Roblox: MiloszCzempion13, UserId 7532199310). Odpowiadamy po polsku.
- Repo: `sybdev007/mushrooms`. Kopie: PC Windows `T:\lantern\mushrooms`, MacBook `~/coding/mushrooms`.
- **Claude pisze zmiany w plikach, ale NIE commituje.** Tom commituje i pushuje sam jako sybdev007
  (`347552131+sybdev007@users.noreply.github.com`). Na Macu remote to `https://sybdev007@github.com/...` + token.
  Na końcu wiadomości commita:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` i linia `Claude-Session: …` z bieżącej sesji.
- **Codex** robi review logiki serwera według `docs/REVIEW.md` i research do `docs/plans/`.
- Publikacja: Rojo → Studio → **File → Publish to Roblox**. Bez publikacji zmiany nie trafiają do gry.
- Nie odpalać Play w Studio bez pytania, jeśli zmienia to zapis Toma (Studio z API pisze do prawdziwego DataStore).
- Hasła i logowania (Roblox, GitHub) Tom wpisuje sam.

### Zasady pracy z plikami (wyciągnięte z wpadek)
- Przed nadpisaniem pliku na dysku Toma **porównaj go z GitHubem** (Miłosz albo inna sesja mogła go zmienić).
  Raz nadpisałem świeżo ściągnięty `GameStrings.csv` i zniknęły napisy scenki kradzieży.
- Most do komputera przy pierwszym zapisie bywa „stary” — zapisuj dwa razy (force) i sprawdzaj rozmiar.
- Most nie kasuje plików i zostawia `*.lock` w `.git` po komendach git — git robi Tom w swoim terminalu.

## Narzędzia

- Luau `--!strict`, Rojo (`default.project.json`: `src/server`, `src/client`, `src/shared`, `src/first` → ReplicatedFirst).
- Testy: `lune run tests/economy.spec.luau` (ok. 716 testów). Lint: `selene src` (2 stare, nieszkodliwe błędy).
- Etap 1 na `feat/upgrade-gates`: 764 testy; DATA_VERSION = 6. Buty 4/8/12 poziomów według map
  (22/28/34 prędkości); olej 8/11/14; koszyk 6/10/14. Kupione stare poziomy zachowane. Nowe poziomy
  wymagają otwarcia świata i jego obozu lub późniejszego. Plan i scenariusze DEV: `docs/plans/upgrade-gates.md`.
  Model: jaskinia 1 h 31 min; bagna 2 h 47 min; 82 poziomy dochodowe 5 h 53 min.
  Lune i Rojo sprawdzone; zmienione moduły Selene bez błędów. Play w Studio niewykonany;
  etap czeka na test Play i akceptację przed merge. Etapy 2–5 jeszcze niewdrożone.
- Symulator ekonomii: `lune run tools/economy_sim.luau`.
- Tłumaczenia: `src/localization/GameStrings.csv` — kolumny `Key,Source,Context,Example,pl`, **bez przecinków w tekście**
  (test to sprawdza), każdy klucz z `Localize.t(...)` musi tu być.
- Skille Claude w repo: `.claude/skills/` (Roblox Luau / networking / datastores / economy / UI / characters /
  physics / studio-workflow + game-feel, game-ui-ux, level-design, performance). Nasze zasady są ważniejsze niż ich ogólniki.

## Gra (co już jest)

Nocne zbieranie grzybów z latarnią (olej, koszyk), 3 światy za portalami (las → jaskinia od 30 000 monet →
bagna od 1 000 000), 13 stref. Mutacje: warianty Srebro/Złoto/Tęcza + cechy (Mech, Blask, Kryształ, Otchłań,
event: Dynia). Strażnicy Leszy / Skarbnik / Utopiec — legowiska, kradzież, pościg. Ogródki (6, max 6 graczy na
serwer) z dochodem, skrzynią z limitem (ulepszenie `chest`), dochodem offline (2 h pełne + do 8 h po 25%) i
kradzieżą z cudzych ogródków (scenka). Grzybopedia, tytuły, zadania dzienne, seria logowań, rankingi,
wyprawy grupowe (połączone latarnie, podnoszenie kumpla), Halloween do 9.11 (cukierki, kocioł, ścieżka
nagród, Noc Dziadów, sekretny cmentarzyk z tytułem Halloween 2026, ranking cukierków do 16.11).

Społeczność (`src/server/CommunityService.luau`, `src/shared/Social.luau`):
- członek grupy Old Owl Studios: +10% szczęścia, tytuł Old Owl Member, paczka powitalna raz na konto
  (1 × rewardScale monet = 1600 w lesie + mikstura 15 min),
- znajomy z Robloxa na serwerze: +10% szczęścia dla obu,
- tytuł Przewodnik za 3 osoby, które weszły z zaproszenia (przycisk 👥 Zaproś).

Panel DEV (tylko `Config.DevUserIds`): na żywej grze tylko teleporty, rankingi, Noc Dziadów, Dyniowy wysyp i
„⚠️ Wyzeruj MÓJ zapis” (dwa kliknięcia, wyrzuca z gry). Reszta tylko w Studio. Studio i deweloperzy nie
trafiają na tablice rankingów (magazyny `LanternForager_Top_v2_*`).

## Numery Roblox

- Grupa **Old Owl Studios**: 463484833. Gra (universe): 10772830253, place: 72216132547990.
- Produkty (`Config.Products`): rescue 3724758636 (59 R$), boom 3724757048 (99), oil 3724758135 (15),
  harvest 3724757863 (29), luck 3724757551 (49). **x2s / x2m / x2l / x2xl (19/39/79/149 R$) mają id = 0 —
  do założenia w Creator Hub jako Unlisted.**
- **Twój Wysyp** (`boomSolo`, gałąź `ui-v2`): Wysyp tylko dla kupującego (te same `Config.Boom`, zapis
  `soloBoomUntil`, nie sumuje się z Wysypem serwera). Na razie `id = 0` (test w Studio, cena roboczo 49 R$).
  Do sklepu: zwykły produkt w Creator Hub (NIE Unlisted) i numer w `Config.Products.boomSolo`.
- Odznaki (`Config.Badges`, lista nazw i opisów w `docs/Odznaki.md`, obrazki `assets/badges/`):
  gotowe: first_mushroom, cave, gold, leszy, halloween2026.
  **Do założenia (po 5 dziennie za darmo):** atlas_page, swamp, skarbnik, utopiec, rainbow; potem lifesaver,
  streak7, grandmaster. Numery pobiera się z `https://badges.roblox.com/v1/universes/10772830253/badges`.

## Pułapki (już raz na nie wpadliśmy)

- **`Progress.rewardScale` to jednostka nagrody W MONETACH** (las 1600, jaskinia 32 000, bagna 160 000),
  a nie mnożnik ~1. Paczka „150 × skala” dała graczom 240 000 monet.
- Mikstura szczęścia i Wysyp to płatne produkty — nie dawać ich darmowych zamienników (np. mikstur z grzybów).
- Studio z dostępem do API pisze do prawdziwych DataStore i rankingów.
- `screen_capture` w Studio nie widzi BillboardGui z `AlwaysOnTop`.
- Wszystkie nagrody i walidacja na serwerze; klientowi nie ufamy (`docs/REVIEW.md`).

## Co dalej

1. **Teraz:** założyć 5 odznak i wpisać numery; założyć produkty x2 (Unlisted) i wpisać id; Codex review
   zmian skrzyni / x2 / `ProcessReceipt` (commity 325efa7–4dcca51) i `CommunityService`.
2. **Obserwacja Analytics** przez tydzień po wydaniu: powroty D1/D7, długość sesji, gdzie gracze odpadają.
3. **Listopadowy update (po 9.11)** — plan w `docs/plans/loop-research.md` (Codex zapisał go na PC w `T:`;
   jeśli nie ma go w repo, trzeba go stamtąd dodać do commita):
   - **Gablota w ogródku** (zlew na monety po wymaksowaniu, które przy wydajnej grze jest po ~3 h 41 min):
     3 serie po 6 miejsc, cena `rewardScale(seria) × 10 × 2^(n−1)`; propozycja: 2 darmowe miejsca i wystawianie
     także kopii gatunków z Grzybopedii (żeby od początku było co pokazać).
   - **Znalezisko Nocy**: jeden legendarny grzyb na noc na serwer, kto pierwszy, donieść do chatki w 180 s,
     trofeum + tytuł (1/3/7/15); na start bez przechwytywania.
4. **Research u Codexa** (prompty już dane): kradzież bez kamperów (`docs/plans/theft-research.md`),
   nowe grzyby / 4. świat / boss / dużo mutacji (`docs/plans/content-expansion.md`). Po ich oddaniu:
   sprawdzić liczby w kodzie i symulatorze, zanim cokolwiek budować.
5. **Monetyzacja** — raport Codexa `docs/plans/monetization-research.md` (3.11). Decyzje: NIE dla stałego x2
   monet, gatunków za Robux i x2 za monety; Zarodniki odłożone; nagrody co 6 h na razie nie robimy
   (dublowałaby zadania dzienne i serię logowań). Do pilotażu po tygodniu obserwacji: kod 0,25 S raz na
   konto, potem kosmetyczny VIP 249 R$ (0 monet, 0 ochrony).
   Paczka Old Owl (15 min mikstury za darmo) to **świadomy wyjątek** od zasady „mikstura tylko płatna” —
   jednorazowy prezent na konto za dołączenie do grupy. Nie rozszerzać na inne darmowe źródła.
6. **UI v2 (kierunek „Chatka Leszego”)** — makiety w Figmie:
   https://www.figma.com/design/nWef7rc8ymwxygFWwJ3LKp (sklep, szanse, klasy kolor + kształt, ratunek,
   karta x2, panel DEV Studio / na żywo). Tytuły w Nunito Black, bo tak wygląda gra po polsku (`FontFix`).
   Kod na gałęzi `ui-v2` (do sprawdzenia w Studio przed scaleniem): nowy `UiFx` (promienie, gradienty, błysk,
   kołysanie — jedna pętla RenderStepped, stoi gdy element niewidoczny), `ClassColor` (klasa grzyba = kolor nazwy; znaki ● ▲ ■ ◆ ★ usunięte 3.11),
   sklep i Szanse jako okna PanelKit, karta ratunku, progi x2, nowy panel DEV. Lista akcji DEV na żywo jest
   w `Config.DevLiveActions` (czyta ją serwer i panel). Typy sprawdza `luau-lsp analyze` z definicjami Robloxa.
   Przyciski z boku (SideButtons) i „Ulepszenia” mają błysk i promienie jak sklep; `setAttention` = migający
   przycisk, gdy coś czeka. **Zadania, premia za komplet i seria logowań odbiera się ręcznie** (RemoteEvent `QuestClaim`,
   `claimed` / `bonusClaimed` w zapisie; stare zapisy: zrobione = już wypłacone).
7. **Ekspedycja do Głębokich Komór** (gałąź `ekspedycja`, z `ui-v2`) — plan i liczby w `docs/plans/cave-expedition.md`.
   Tablica zleceń w Obozie, szczelina w Otchłani, własna kopia trzech komór na ekipę (Chodnik, Zalana Komora
   z ogniskiem, Krypta ze strażnikiem), relikty z odłamkami, renowacją i oprawą (zlew monet), regał w ogródku,
   tytuły Ekspedytor i Łupieżca Krypty. Zapis: `data.delve` (`Delve.readSave`). Do sprawdzenia w Studio
   (panel DEV: „Ekspedycja: od razu do komór”), potem scalenie razem z `ui-v2`.
