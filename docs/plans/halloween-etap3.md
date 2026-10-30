# Plan: Halloween etap 3 (ranking cukierków + wspólny cel serwera) — wersja 2

Zgłoszenie: #2. Event trwa do 9.11.2026 (`Config.Halloween.endsAt`).
Wersja 1 przeszła review Codexa (`docs/plans/halloween-etap3-review.md`). Ta wersja odpowiada na jego uwagi;
na końcu tabela: uwaga → decyzja.

## Główna zmiana względem v1

Nagrodą za cel serwera **nie jest już dodatkowa Noc Dziadów**. To zamyka pętlę „dynie → noc → więcej dyń”
(Codex: ok. 4× więcej dyń w Noc Dziadów) i większość farmienia między serwerami. Nagroda nie daje więcej dyń,
a jej użycie ma dzienny limit **na konto, zapisany w profilu**, więc działa ponad serwerami i restartami.

## 1. Ranking „Najwięcej cukierków”

- Czwarta tablica przed chatką (`LeaderboardService`, `World/Boards`). Tylko sława, bez nagród.
- Wynik = `stats.candy` z profilu (zebrane łącznie; kocioł go nie zmienia).
- Punkty zdobywa się tylko do `endsAt`: `ProgressService.addCandy` już odrzuca cukierki po końcu eventu
  (sprzedaż i zadania sprawdzają `Halloween.active`), dopilnować tego też dla każdego nowego źródła.
- Zapis do OrderedDataStore przez `UpdateAsync` z **maksimum** (stary zapis z innej sesji nie obniży wyniku),
  co 60 s, przy wyjściu gracza i raz przy `endsAt` dla graczy na serwerze. Po `endsAt` tablica jest zamrożona
  (bez nowych zapisów) do 16.11, potem znika.
- Panel DEV: akcja „usuń wynik gracza z rankingu” (po UserId) do czyszczenia testów i oszustw.
- Płatny Wysyp przyspiesza odrost i daje pośrednio więcej dyń. **Decyzja: dopuszczamy** (ranking bez nagród,
  Wysyp jest dla całego serwera, a produkty i tak mają dziś `id = 0`).

## 2. Akcje DEV a ekonomia na żywo

- `candy50`, `candySet`, `candyReset`, `cauldron`, `pumpkinBoom`, `spiritNight` działają **tylko w Studio**
  (`RunService:IsStudio()`), nie na opublikowanej grze nawet dla deweloperów. W live zostają teleporty i podgląd.
- Wkład do celu serwera liczony jest z jawnego źródła `"sell"` przekazanego do `addCandy`, a nie z klucza
  komunikatu (`MSG_CANDY_SOLD` używa też akcja DEV).

## 3. Wspólny cel serwera „Kocioł się gotuje”

- Pasek w oknie 🎃 i nad kotłem: „Serwer: 140 / 200 🍬” plus „Twój wkład: 35”.
- **Stały próg 200 🍬**, niezależny od liczby graczy (nie da się go obniżyć wejściami i wyjściami; solo i duo
  mogą go skończyć, tylko wolniej). Brak limitu wkładu na konto.
- Liczą się tylko cukierki ze **sprzedaży dyń** (`source = "sell"`), nie z zadań dnia ani z kotła.
- Wkład zapisany po `UserId` do końca danego celu (wyjście i powrót nie kasują wkładu). Nadwyżka z ostatniej
  sprzedaży przechodzi do następnego celu.
- Stan celu jest w pamięci serwera (tylko ta instancja). Okno mówi to wprost: „postęp tego serwera”.
  Restart serwera = cel od zera; nagrody już wypłacone zostają w profilach.
- Domknięcie celu: serwer zmienia stan celu (licznik celów +1, pasek od nowa) w tym samym kroku co sprzedaż,
  bez oczekiwania; dopiero potem wypłaca nagrody i ogłasza. Dwie sprzedaże naraz = jedno domknięcie
  (sprzedaż jest obsługiwana po kolei w jednym wątku serwera, licznik zmienia się przed wypłatą).
- **Nagroda**: każdy gracz na serwerze, który dał co najmniej **10 🍬** do tego celu, dostaje:
  - miksturę szczęścia na 10 minut (szczęście zmienia warianty grzybów, **nie zmienia szansy na dynie**,
    która jest stała: `Halloween.pumpkinChance`),
  - dla wszystkich na serwerze: fajerwerki z dyń nad chatką i ogłoszenie (tylko efekt, bez wypłat).
- **Limit: 3 nagrody z celów na konto dziennie**, licznik w profilu (`data.eventGoals = { day, count }`),
  więc przechodzenie między serwerami i restarty go nie obchodzą. Po limicie wkład nadal pcha pasek
  (pomaga innym), ale gracz widzi „dzisiejszy limit nagród osiągnięty”.
- Po `endsAt`: pasek znika, nowe cele się nie zaczynają, nagrody nie są wypłacane.

## 4. Osobno: odnawianie lasu przez wyjście i wejście

Codex zauważył, że przy wejściu do gry las losuje się od nowa (`GameService.onPlayerAdded`), więc wyjście
i powrót zastępuje czekanie na odrost (dotyczy dyń, ale też rzadkich wariantów — to stary problem).
**Poprawka w tym etapie:** profil zapisuje czas wyjścia (`data.leftAt`). Jeśli gracz wraca szybciej niż
`Config.RespawnSeconds`, grzyby nie są gotowe od razu, tylko odrastają stopniowo (losowy czas do pełnego
odrostu), tak jak po zebraniu.

## Testy (Lune + Studio)

- Lune: domknięcie celu, nadwyżka, wkład po UserId po reconnect, próg 10 🍬, dzienny limit 3 i reset o północy,
  brak naliczenia z zadań i z DEV, brak celów i nagród po `endsAt`, ranking `max(old, new)`.
- Studio: sprzedaż po jednej sztuce, dwie szybkie sprzedaże domykające cel, reconnect, akcje DEV w live
  wyłączone (symulacja `IsStudio = false` w teście).

## Uwagi z review → decyzje

| Uwaga Codexa | Decyzja |
|---|---|
| Tani start celu przy małej obsadzie | Stały próg 200, niezależny od graczy |
| Limit 40% blokuje solo/duo, nie alty | Usunięty; zamiast niego dzienny limit nagród na konto w profilu |
| Lokalny cooldown, rotacja serwerów, restart | Nagroda limitowana w profilu (3 / dzień), nie w pamięci serwera |
| Pętla dynie → noc → więcej dyń | Nagroda to szczęście (nie wpływa na dynie), bez dodatkowych Nocy Dziadów |
| Wkład kasowany przy reconnect | Wkład po UserId do końca celu |
| Cel utyka po wyjściu graczy | Stały próg, wkład wychodzących zostaje |
| Restart serwera kasuje postęp | Akceptujemy; okno mówi „postęp tego serwera” |
| DEV zanieczyszcza ranking / daje bonus innym | Ekonomiczne akcje DEV tylko w Studio + usuwanie wyniku z rankingu |
| Źródło cukierków po kluczu komunikatu | Jawny parametr `source` w `addCandy` |
| Zamknięcie rankingu, stare zapisy | `UpdateAsync` z maksimum, zapis przy `endsAt`, potem zamrożenie |
| Relog odnawia las | `data.leftAt` + stopniowy odrost po szybkim powrocie |
| Wysyp za Robuxy daje przewagę w rankingu | Dopuszczamy (ranking bez nagród) |
| Fajność: wkład, stan po domknięciu | Pasek + „Twój wkład”, ogłoszenie i fajerwerki od razu, bez czekania |

---

## Wersja 3 (po drugim review) — co zrobiłem w kodzie

| Uwaga z drugiego review | Decyzja (zaimplementowana) |
|---|---|
| [P1] Relog nadal losuje las | Cały las gracza (gatunek, mutacje, czas gotowości w `os.time`) siedzi w profilu (`data.forest`) i aktualizuje się przy każdej zmianie, więc też przy awarii (autozapis profilu). Przy wejściu w tym samym „pokoleniu lasu” (do następnego świtu) las wraca 1:1 z czasami odrostu, łącznie z legowiskami strażników. Po świcie las i tak odrasta wszystkim. |
| [P1] Finalizacja rankingu | `ProgressService.addCandy` sam odrzuca cukierki po `endsAt` (centralny warunek). Wyniki z profilu można wysyłać aż do `finalizeAt` (16.11), tablica stoi do tej chwili. |
| [P1] Usunięty wynik wraca | `Config.Halloween.rankingBanned` sprawdzane przy każdym zapisie (także wewnątrz `UpdateAsync`) i przy odczycie tablicy; `/rankremove <UserId>` usuwa wpis od razu i blokuje go na tym serwerze. |
| [P2] Podział wkładu mnoży nagrodę | Nagroda proporcjonalna: 3 s mikstury za cukierek, maks. 10 min na cel i 30 min dziennie na konto. Budżet celu (200 × 3 s = 10 min) nie rośnie od rozłożenia na konta. |
| [P2] Nadwyżka | `Halloween.contribute` dzieli sprzedaż między kolejne cele (do kończonego tylko reszta), snapshot wkładów przed resetem, sprzedaż przez kilka progów obsłużona. Każdy cel wypłacany raz. Bez yieldów między zmianą stanu a wypłatą. |
| [P2] Limit w profilu | Tylko sesje z zapisywanym profilem (`canSave`) wnoszą wkład, dostają nagrody i trafiają do rankingu. Doba UTC (`Progress.dayIndex`). Nagroda od razu wydłuża `luckUntil` (nie przedmiot). Wypłata tylko dla obecnych w chwili domknięcia. |
| [P2] DEV na live | Zamknięta allowlista na live: teleporty, `boardsRefresh`, `rankingRemove`, oraz dwa ogłaszane wydarzenia „admin abuse” (`spiritNight`, `pumpkinBoom`) — świadomie zostają. Wszystko inne (monety, cukierki, ulepszenia, zadania, pora dnia, `/coins`) tylko w Studio. Ranking nigdy nie przyjmuje zapisów ze Studio ani od deweloperów. |

---

## Wersja 4 (po review kodu: `halloween-etap3-code-review.md`)

| Uwaga | Poprawka |
|---|---|
| [P1] Trwający `UpdateAsync` odtwarza usunięty wynik | Usunięcie zapisuje w magazynie znacznik `0` zamiast kasować wpis. Funkcja w `UpdateAsync` przy każdym wywołaniu (też ponowionym po konflikcie) widzi znacznik i nic nie zapisuje — na każdym serwerze, bez zmiany Config. Odczyt tablicy pomija wartości < 1. |
| [P2] Ranking z niezapisanego profilu | Ranking cukierków wysyła tylko `LastSavedData` profilu: `DataService.confirmedCandy` i `DataService.onSaved` (ProfileStore `OnAfterSave`, także ostatni zapis po wyjściu). |
| [P2] Pokolenie lasu przy przywołanej nocy | Serwer trzyma własne pokolenie (`serverGen`). Reset tylko gdy widać świt i kalendarz jest nowszy (`Cycle.shouldRegrow`) — raz, także gdy przywołanie kończy się w połowie świtu. Przywracanie: zapis z tego samego lub nowszego pokolenia, nie z przyszłości kalendarza (`Cycle.canRestore`), więc skakanie między serwerami nie losuje lasu. Testy Lune. |
| [P2] Wysyp nie trafia do profilu | Po skróceniu `readyAt` przez Wysyp `rememberSpot` dla każdego miejsca. |
| [P2] NaN / ±inf / odległe terminy | `DataService.finite`; `forest.t` przycinane do teraz + 1 h (bez darmowego odrostu), `forest.g ≥ 0`, id ≤ 64 znaki; `eventGoals.day` od 0 do jutra, `seconds` 0..`maxPerDay`; `luckUntil` skończone. |
| [P2] Deweloperzy w odczycie tablicy | Sprawdzenie po UserId (twórca gry, `Config.DevUserIds`) przy zapisie i odczycie; odczyt przechodzi do 5 stron, aż zbierze 10 dozwolonych wpisów. |
| [P2] Studio usuwa produkcyjny wynik | `LeaderboardService.remove` nie działa w Studio; deweloper dostaje komunikat „ok” albo „FAILED”. |

## Wersja 5 (po drugim review kodu)

| Uwaga | Poprawka |
|---|---|
| [P1] A: drugi reset tej samej generacji po przejściu między serwerami | Świt z kalendarza odnawia tylko sesje, których `data.forest.g` jest starsze od nowego pokolenia serwera (`Cycle.needsRegrow`). Gracz, który świt dostał na innym serwerze, zachowuje las i czasy odrostu. `regrowForest` (też `pumpkinBoom`) nigdy nie obniża `g`. Test Lune: scenariusz A → B → B dogania świt. |
| [P2] B: wynik po wyjściu przepada po jednym błędzie | Kolejka zaległych wyników po UserId (`pending`), niezależna od obiektu Player. `onProfileSaved` bierze wynik z przekazanego snapshotu zapisu (`DataService.candyOf`). Ponowienie co minutę do skutku, znacznika usunięcia albo finalizacji, plus próba przy zamykaniu serwera (`BindToClose`). Moderacja czyści kolejkę dla konta. |
| [P2] C: lokalny fallback pokazuje zbanowanych | Ranking cukierków nie buduje listy z profili. Bez dostępu do magazynu pokazuje ostatnią pobraną czołówkę świata (albo pustą tablicę). |

## Wersja 6 (po trzecim review kodu)

| Uwaga | Poprawka |
|---|---|
| [P2] Równoległe `flushCandy` powielają zapisy | Nowy moduł `src/server/ScoreQueue.luau` (czysty, test w Lune): jeden worker, kolejne wywołania tylko zgłaszają „jeszcze raz”. Najwyżej jeden zapis naraz, błąd jednego wpisu nie blokuje następnych, po zapisie znika tylko wysłana wersja. `BindToClose` czeka na tego samego workera (do 20 s), nie uruchamia drugiego. |
| [P2] Cache fallbacku pokazuje lokalnie usuniętego | `lastCandy` filtrowane przez `candyAllowedId` przy zapisie do cache, przy każdym zwrocie i przy moderacji. Zwrot z cache ma `Source = "stale"` i `UpdatedAt` z chwili ostatniego udanego odczytu. |

Znane ograniczenie (świadomie): kolejka jest w pamięci serwera. Awaria procesu może zostawić wynik gracza offline nieopublikowany do jego następnego wejścia (wtedy wyśle się z profilu).

## Wersja 6.1

- [P2] Limit czasu przy zamykaniu serwera: `deadline` ustawiany na początku `BindToClose` (25 s), `flushCandy` uruchamiany w tle (`task.spawn`), callback czeka na workera tylko do limitu.
