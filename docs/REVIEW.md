# Review zmian przed commitem (dla Codexa)

Jak pracujemy:

1. Claude pisze kod, testuje go (Lune, selene, luau-lsp) i zapisuje pliki w `T:\lantern\mushrooms` **bez commita**.
2. Rojo synchronizuje pliki do Studio, więc zmianę da się od razu przetestować w grze.
3. Codex robi review według tej listy (opis poniżej).
4. Jeśli review jest OK, robimy commit i push z PC. Jeśli nie, uwagi idą do Claude'a.

Przed każdą następną zmianą wszystko musi być wypchnięte na GitHuba. Claude zaczyna pracę od stanu z `origin/main`.

## Jak odpalić review

W terminalu w `T:\lantern\mushrooms`:

```
git status
git diff
```

Potem do Codexa, np.:

> Zrób review niezacommitowanych zmian w tym repo (`git diff`) według `docs/REVIEW.md`.
> Skup się na exploitach po stronie serwera. Dla każdego problemu podaj plik, linię,
> konkretny scenariusz ataku i poprawkę. Pomiń styl kodu.

Przed dużym etapem (np. nowy event) zrób też review **planu**, zanim powstanie kod:

> To jest plan nowej funkcji: (wklej plan). Szukaj dziur w ekonomii i exploitów:
> jak gracz albo grupa graczy (też alty) może to farmić, zduplikować nagrody
> albo zarobić więcej, niż planowaliśmy. Podaj konkretne scenariusze i jak im zapobiec.

Testy logiki (Lune, z katalogu repo):

```
lune run tests/economy.spec.luau
lune run tools/economy_sim.luau
```

## Zasada nr 1: klient kłamie

Wszystko, co przychodzi z RemoteEvent albo ProximityPrompt, może być podrobione: argumenty, ich typy, częstotliwość i pozycja gracza (exploiter może się teleportować). Serwer:

- sprawdza **typ** każdego argumentu (`typeof(x) == "string"` itd.) i odrzuca resztę;
- **nie bierze od klienta** wartości, cen, ilości ani wyniku losowania; liczy je sam z `session.data` i `Config`;
- sprawdza **odległość** od miejsca akcji (stoisko, grzyb, skupywacz), z małą tolerancją na opóźnienie sieci;
- ma **odstęp** między akcjami (cooldown), żeby spam nie dawał przewagi;
- zmienia dane gracza **tylko po wszystkich sprawdzeniach** (najpierw walidacja, potem odjęcie kosztu, potem nagroda).

## Wejścia z klienta (tu szukać dziur)

| Wejście | Gdzie | Co sprawdzić |
|---|---|---|
| `PickMushroom` (id grzyba) | `GameService.onPick` | Czy grzyb jest widoczny dla **tego** gracza; dystans `Config.PickRadiusServer`; `PickCooldown`; czy pełny koszyk blokuje; grzyby strażników budzą strażnika |
| `SellBasket` (indeksy, odcisk koszyka) | `GameService.onSell` | Dystans do skupywacza / kramiku (`canSell`); `Economy.validSellIndices` (duplikaty, ujemne, poza zakresem, ułamki); wartość liczona przez serwer; cukierki (`Halloween.candyFor`) tylko za faktycznie sprzedane dyniowe grzyby |
| `BuyUpgrade` (id) | `GameService.onBuy` | Czy id istnieje w `Config.Upgrades`; maks. poziom; koszt odejmowany przed podniesieniem poziomu; ulepszenia jaskini i bagien tylko w ich obozie |
| `DevAction` (nazwa akcji) | `GameService.onDevAction`, `ProgressService.dev`, `HalloweenService.dev` | **Każda** akcja musi przejść przez `isDeveloper`. Nowe akcje (np. `candySet:…`, `cauldron`, `spiritNight`, `pumpkinBoom`) nie mogą być osiągalne inną drogą |
| `/coins` na czacie | `GameService.setupDevCommands` | Tylko `isDeveloper` |
| `StudioPurchase` | `GameService.onStudioPurchase` | Działa tylko w Studio (`RunService:IsStudio()`) i tylko dla produktów z `id = 0` |
| Zakupy za Robuxy | `GameService.processReceipt`, `grantProduct` | Ten sam `PurchaseId` drugi raz nie daje nagrody (`data.receipts`); `NotProcessedYet`, gdy gracza nie ma albo nie da się dać nagrody; ratunek koszyka tylko w czasie okazji |
| `GardenPlant`, `GardenAuto` | `GardenService` | Sadzić można tylko z własnego koszyka, we własnym ogródku, na odblokowanej grządce; zamiana oddaje stary grzyb do koszyka (koszyk się nie przepełni) i nie liczy się jako sadzenie (zadania, tytuł Ogrodnik) |
| Kradzież z ogródka (prompt) | `GardenService` (steal) | Dystans, cooldowny (`stealCooldown`, `thiefCooldown`), właściciel w pobliżu blokuje; łup wraca po `carry.timeout`; złodziej nie może wynieść grzyba poza zasady (np. dachem chatki: `Cabin.buildClimbGuards`) |
| Skarbiec strażnika (prompt) | `HoardService` | Dystans `takeDistance`; jeden grzyb nie trafia do dwóch graczy naraz |
| Podnoszenie kumpla (prompt) | `GameService` (revive) | Tylko gracz w pobliżu, tylko gdy ktoś naprawdę czeka na pomoc |
| `QuestReroll` | `ProgressService.onReroll` | Raz dziennie, tylko nieukończone zadanie, indeks w zakresie |
| `SelectTitle` | `ProgressService.onSelectTitle` | Tylko zdobyty tytuł (`Titles.earned`) albo `""` / `"none"` |
| `SaveSettings` | `ProgressService` | Klucze `music` / `sfx` z wartością boolean albo `musicVolume` / `sfxVolume` z liczbą (`Progress.normalizeVolume`: NaN i nieskończoność odrzucone, przycięte do 0..1, co 5%); nic innego |
| `EquipSkin` (slot, id) | `HalloweenService.onEquip` | Slot z `Halloween.SLOTS`; skórka pasuje do slotu; gracz ją ma (`Halloween.ownsSkin`) |
| Kocioł (prompt) | `HalloweenService.useCauldron` | Event trwa; `cauldron.cooldown`; najpierw sprawdzenie i odjęcie `cost` z `candyBag`, potem losowanie na serwerze (`math.random`); skórka, którą gracz ma, daje monety, a nie drugą skórkę |
| `TutorialStep` | `TutorialService.clientStep` | Klient może skończyć tylko cutscenkę; reszty kroków pilnuje serwer |

## Rzeczy, które serwer liczy sam (nie mogą przyjść od klienta)

- **Olej:** spada co tick w `GameService.tick`. Gdy dojdzie do 0, `engulf` zabiera koszyk (albo kumpel w pobliżu podnosi gracza). Klient tylko pokazuje pasek.
- **Strefa gracza:** z pozycji `HumanoidRootPart` na serwerze (`Economy.zoneIndexAt`).
- **Mutacje i warianty:** `rollSpot` na serwerze (szczęście z `Economy.luck`, dynie z `Halloween.pumpkinChance`).
- **Pora dnia i Noc Dziadów:** z zegara serwera (`Cycle`), atrybuty w `Workspace` są tylko do wyświetlania.
- **Cukierki:** tylko `ProgressService.addCandy` (sprzedaż dyń, zadania). `stats.candy` = zebrane łącznie (ścieżka nagród, tytuły, odznaka), `candyBag` = do wydania w kotle.
- **Nagrody ścieżki Halloween:** `grantTrack` wypłaca każdy próg raz (`data.eventClaimed`).

## Ekonomia: na co patrzeć przy review

- Czy nowa nagroda nie da się zebrać wiele razy (np. sprzedaż po jednym grzybie, wyjście i wejście do gry, kilka serwerów naraz). Zapis ma blokadę sesji (ProfileStore), więc dane są otwarte tylko na jednym serwerze.
- Czy coś nie zamienia się w pętlę zysku (np. kocioł: średnio więcej cukierków na wyjściu niż na wejściu; test `halloween: kocioł`).
- Wspólne nagrody serwera (cele serwera, rankingi): czy alty na jednym serwerze nie nabiją ich za darmo.
- Liczby z `Config` przelicz w `tools/economy_sim.luau`: czas do jaskini i bagien oraz do maks. ulepszeń. Ostatnio: jaskinia ok. 56 min, bagna ok. 1 h 53 min, koniec ok. 3 h 41 min.

## Inne rzeczy warte zgłoszenia

- Błędy, które wywalają pętlę serwera (np. `nil` w `tick`): jeden gracz nie może zatrzymać gry wszystkim.
- Zapis: nowe pola w danych gracza muszą mieć wartość domyślną w `DataService.defaultData` i sprawdzenie w `reconcile` (stary zapis albo śmieci nie mogą wywalić gry).
- Teksty dla gracza: nowy klucz musi być w `src/localization/GameStrings.csv` (EN i PL, bez przecinków w tekście).
- Atrybuty, które klient ustawia na swoim graczu (`Loaded`, `IntroPending` z ekranu wczytywania), nie docierają do serwera. Serwer nie może na nich polegać. Teksty ekranu wczytywania są w `src/first/LoadingTheme.luau`, nie w CSV, bo ekran rusza, zanim klient dostanie tabelę tłumaczeń.
