# Review kodu Halloween — etap 3

Data: 30.10.2026. Zakres: niezacommitowany `git diff`, `docs/REVIEW.md` i sekcja „Wersja 3” planu. Numery linii odnoszą się do sprawdzanej kopii roboczej. Kod aplikacji nie został zmieniony w ramach review.

**Werdykt: wymagane poprawki przed commitem.** Podział wkładu i proporcjonalne wypłaty rozwiązują główne problemy ekonomii celu. Pozostają problemy moderacji rankingu, publikowania niezapisanego wyniku i spójności zapisanego lasu. Poniżej odróżniam exploity zwykłego gracza od błędów wymagających awarii, danych uszkodzonych albo dostępu DEV/Studio.

## 1. [P1] Trwający UpdateAsync może odtworzyć wynik po usunięciu

**Plik i linie:** [LeaderboardService.luau:120](T:/lantern/mushrooms/src/server/LeaderboardService.luau:120), callback w liniach 120–125; usuwanie w liniach 208–213.

**Scenariusz:** zapis wyniku przechodzi `allowed`, po czym czeka w `UpdateAsync`. Administrator wywołuje `/rankremove`, ustawia `removed[userId] = true` i usuwa wpis. Opóźniony lub ponowiony callback sprawdza tylko `rankingAllowed(userId, false)`, czyli statyczną listę Config. Nie sprawdza `removed`. Może więc przywrócić właśnie usuniętą wartość nawet na tym samym serwerze. Ten serwer ją ukryje, ale inne serwery pokażą ją ponownie.

Zmiana serwera dodatkowo omija lokalną blokadę bez żadnego wyścigu. Wersja 3 jawnie opisuje blokadę jako lokalną i wymaga ręcznej zmiany Config do trwałego wykluczenia, ale oznacza to, że samo polecenie moderacji nie daje trwałego usunięcia. Aktualizacja Config nie aktualizuje automatycznie kodu już działających instancji.

**Poprawka:** co najmniej sprawdzać `removed` także przy każdej próbie transformacji `UpdateAsync`. Docelowo trwały znacznik moderacji / wersja wpisu musi uniemożliwiać odtworzenie wyniku przez stare instancje i żądania. Można użyć atomowo respektowanego znacznika w rekordzie rankingu lub wersjonowanego źródła publikacji. Osobny odczyt listy blokad przed zapisem, bez ochrony przed wyścigiem, nie daje pełnej gwarancji. Test: wstrzymać aktualizację, usunąć wpis, wznowić callback i powtórzyć na dwóch serwerach.

## 2. [P2] Ranking utrwala wynik, którego profil jeszcze nie zapisał

**Plik i linie:** [LeaderboardService.luau:104](T:/lantern/mushrooms/src/server/LeaderboardService.luau:104), linie 104–125; kolejność wyjścia: [GameService.luau:983](T:/lantern/mushrooms/src/server/GameService.luau:983).

**Scenariusz:** trwały profil ma 100 cukierków, gracz zdobywa kolejne 50. Okresowy upload zapisuje 150 w OrderedDataStore, lecz profil nadal ma na dysku 100. Serwer ulega awarii lub zapis profilu zawodzi. Po wejściu gracz ma 100, a ranking stale pokazuje 150, bo `max(old, score)` nie pozwala tego skorygować. Na wyjściu ranking również jest wysyłany przed `DataService.release`. `canSave = true` znaczy tutaj, że otwarto sesję, a nie że bieżący wynik został zapisany.

To błąd spójności przy awarii, nie dowód, że zwykły reconnect dowolnie dodaje punkty. Wynik może jednak zachować niezapisany postęp, a maksimum utrwala rozjazd aż do moderacji.

**Poprawka:** publikować snapshot potwierdzonego zapisu profilu, np. poprzez dostępne w lokalnym ProfileStore `OnAfterSave` / `LastSavedData`. Aktualizację rankingu można ponawiać do `finalizeAt`. Nie uznawać samego wywołania `Save()` za potwierdzenie trwałości. Test: udany zapis rankingu i nieudany zapis profilu, potem ponowne wejście.

## 3. [P2] Generacja lasu zmienia się mimo pominiętego resetu podczas spiritNight

**Plik i linie:** [GameService.luau:358](T:/lantern/mushrooms/src/server/GameService.luau:358), linie 358–360 i 915–928; nadpisanie fazy w liniach 1787–1792 i reset w 1801–1803.

**Scenariusz:** dozwolona na live akcja DEV `spiritNight` obejmuje naturalny świt. Pętla zamienia fazę na `night`, więc rzeczywisty `resetForest` nie zachodzi przy naturalnym świcie. `forestGen()` korzysta jednak z surowego `Cycle.at(os.time())` i przechodzi na nową generację. Zapis aktywnego gracza pozostaje ze starym `g` — `rememberSpot` nie zmienia istniejącego `g`. Gracz zbiera wartościowe grzyby, wychodzi i wraca: `saved.g ~= gen`, więc otrzymuje świeżo wylosowany, gotowy las zamiast własnych cooldownów. Gracze pozostający online nie dostają tego samego resetu. Jeśli przywołana noc kończy się jeszcze podczas świtu, możliwy jest również późniejszy dodatkowy reset przy zmianie fazy na `dawn`.

Nie wymaga to uprawnień DEV od farmiącego gracza, tylko uczestnictwa w dopuszczonym wydarzeniu administratora.

**Poprawka:** rozdzielić kalendarz odrostu od wizualnej/bonusowej fazy. Reset i wersję zapisu wyznaczać na podstawie tej samej generacji, niezależnie od nadpisania `phase.phase`. Przetwarzać zmianę generacji dokładnie raz również dla gracza dołączającego na granicy świtu. Test: przywołana noc przykrywająca cały świt oraz kończąca się w połowie świtu, z reconnectem i bez.

## 4. [P2] Przyspieszenie Wysypu nie trafia do zapisanego lasu

**Plik i linie:** [GameService.luau:933](T:/lantern/mushrooms/src/server/GameService.luau:933), odtworzenie zapisu; niezsynchronizowana zmiana w [GameService.luau:1431](T:/lantern/mushrooms/src/server/GameService.luau:1431).

**Scenariusz:** miejsce ma zapisany odrost za 90 s. Wysyp skraca `state.readyAt` do około 31,5 s, ale nie aktualizuje `data.forest.s[id].t`. Gracz wraca po 40 s w tej samej generacji: grzyb powinien być gotowy, tymczasem odtworzenie profilu przywraca wcześniejszy, dłuższy termin. Wyjście pozbawia go już przyznanej korzyści z produktu. To regresja spójności i utrata bonusu, nie droga do dodatkowego zarobku.

**Poprawka:** iterować po `id, state` i wywoływać `rememberSpot` po każdej zmianie `readyAt` w obsłudze Wysypu. Najlepiej scentralizować wszystkie mutacje stanu miejsca, żeby pamięć sesji i profil nie rozchodziły się w innych ścieżkach. Test: zakup Wysypu, reconnect przed pierwotnym terminem, także po kilku zakupach skracających ten sam cooldown.

## 5. [P2] Liczbowe śmieci w nowych polach przechodzą reconcile

**Plik i linie:** [DataService.luau:343](T:/lantern/mushrooms/src/server/DataService.luau:343), linie 343–361; użycie terminu w [GameService.luau:924](T:/lantern/mushrooms/src/server/GameService.luau:924).

**Scenariusz uszkodzonego profilu:** poprawny gatunek i aktualne `forest.g`, ale `entry.t = 1e30`, są akceptowane. Po wejściu miejsce nie odrośnie w bieżącej generacji. `typeof(x) == "number"` akceptuje również NaN i nieskończoności; `math.floor` nie jest walidacją skończoności. Analogicznie nowe `eventGoals.day/seconds` nie mają walidacji skończoności ani górnego limitu. Wadliwy licznik może zablokować należne wypłaty, a wadliwy dzień może powodować ciągłe zerowanie licznika zamiast utrzymania limitu. Nie wykazałem drogi, którą zwykły klient może zapisać te wartości — to wymagane w REVIEW.md zabezpieczenie przed śmieciami, nie stwierdzony exploit RemoteEvent.

**Poprawka:** przyjmować tylko skończone liczby (`x == x`, brak ±math.huge), walidować sensowny zakres dnia i generacji, ograniczać wykorzystany czas do zakresu 0–1800. Dla terminów lasu zastosować zakres zgodny z maksymalnym cooldownem, w tym strażników; nie naprawiać nieprawidłowego przyszłego terminu przez darmowy natychmiastowy odrost. Nieznane miejsca nie powinny zużywać limitu poprawnych wpisów kosztem istniejących miejsc. Testy reconcile: brak pól, zły typ, NaN, ±inf, bardzo odległy czas, niewłaściwy gatunek/strefa i nieznane identyfikatory.

## 6. [P2] Odczyt rankingu nie wyklucza istniejących wpisów deweloperów

**Plik i linie:** [LeaderboardService.luau:160](T:/lantern/mushrooms/src/server/LeaderboardService.luau:160).

**Scenariusz:** konto miało wynik przed dopisaniem do `Config.DevUserIds`, albo w magazynie został wpis z wcześniejszego testu. Upload poprawnie odrzuca dewelopera, lecz odczyt wywołuje `Halloween.rankingAllowed(userId, false)`, więc zachowany wynik nadal zajmuje miejsce w rankingu. Właściciel gry ma ten sam problem. Przekazywane `false` nie sprawdza tożsamości i nie usuwa starych wpisów.

**Poprawka:** wydzielić sprawdzanie dewelopera po `UserId`, działające również dla kont offline, i użyć go w odczycie oraz zapisie. Przy filtracji pobierać dalsze strony aż do zebrania wymaganej liczby dozwolonych wpisów albo końca wyników: teraz pierwsza dziesiątka wypełniona zbanowanymi kontami daje pustą tablicę zamiast następnych uczciwych graczy.

## 7. [P2] Studio może usuwać produkcyjny ranking pomimo blokady uploadu

**Plik i linie:** [LeaderboardService.luau:208](T:/lantern/mushrooms/src/server/LeaderboardService.luau:208), linie 208–213; droga wejścia: [GameService.luau:1237](T:/lantern/mushrooms/src/server/GameService.luau:1237).

**Scenariusz wymagający Studio z dostępem do API:** tester wywołuje `/rankremove <UserId>` lub `rankingRemove:<UserId>`. W Studio `isDeveloper` zwraca true, a `devActionAllowed` dopuszcza wszystkie akcje. `remove` nie sprawdza `RunService:IsStudio()` i używa tego samego `Halloween2026_Candy`. Test moderacji usuwa więc rzeczywisty wynik. Sprawdzenie Studio w `allowed` chroni tylko upload, nie tę nową mutację magazynu.

**Poprawka:** blokować produkcyjne `remove` w Studio albo kierować wszystkie operacje testowe na osobny magazyn. Warto też rozdzielić magazyny profili, bo sam zakaz uploadu ze Studio nie oznacza izolacji danych testowych. Test: komenda Studio nie wywołuje `RemoveAsync` na produkcyjnym magazynie.

## Sprawdzone ścieżki bez potwierdzonego exploitu w tym diffie

- `Halloween.contribute` rozdziela 195 + 20 na wkłady 5/15 i tworzy osobne tabele wkładu dla kolejnych celów. Nie ma podwójnego zaliczenia nadwyżki; sprzedaż przez wiele progów jest obsłużona.
- `HalloweenService.contribute` jest wywoływane przez serwerową sprzedaż rzeczywistych dyń, po usunięciu przedmiotów z koszyka. Brak nowego zdalnego wejścia pozwalającego klientowi przesłać `amount`. Brak parametru `source` w `addCandy` nie jest sam w sobie luką: osobne wywołanie z `onSell` oddziela cel od zadań i kotła.
- `payGoal` ogranicza czas według aktualnego wykorzystania, zwiększa licznik i `luckUntil` przed wysłaniem komunikatu. Kolejny ukończony cel widzi już zużyty limit. Sprawdzane wywołania powiadomień i stanu nie dodają oczekiwania na klienta. Dzienne rozliczenie jest UTC; sześć wypłat wokół północy nie omija zadeklarowanego limitu kalendarzowego 1800 s na dzień.
- Suma nagród z jednego celu nie przekracza 200 × 3 = 600 s. Rozłożenie wkładu na alty nie mnoży tej sumy. Wiele kont ma osobne limity dzienne — to pozostała właściwość limitu na konto, a nie błąd proporcjonalnego podziału.
- `canSave = false` blokuje wkład, wypłatę celu i upload cukierków. Flaga jest jednak snapshotem powodzenia otwarcia profilu, nie potwierdzeniem jego bieżącej aktywności ani trwałości danych. Utrata sesji uruchamia kick; nie wykazałem powtarzalnego exploitu zwykłym reconnectem w tym krótkim oknie.
- `savedFits` odrzuca nieznany gatunek i niepasującą strefę/strażnika. Zwykły reconnect w tej samej generacji odtwarza grzyby i terminy zamiast losować cały las. Nie znalazłem bezpośredniego remote pozwalającego edytować `data.forest`.
- `devActionAllowed` działa po sprawdzeniu typu i `isDeveloper`. Na live dopuszcza wyłącznie dokładne teleporty, `boardsRefresh`, `spiritNight`, `pumpkinBoom` i zakotwiczony wzorzec `rankingRemove:<cyfry>`. `/coins` ma dodatkowy warunek Studio. Nie znalazłem obejścia allowlisty przez zwykłego gracza.
- `spiritNight` i `pumpkinBoom` nadal zwiększają produkcję zasobów innych graczy, których ranking nie wyklucza. To świadoma decyzja Wersji 3, więc nie zgłaszam samej obecności tych akcji jako niezgodności. Problem synchronizacji generacji z pkt 3 jest od niej niezależny.

## Weryfikacja i ograniczenia

- `lune run tests/economy.spec.luau`: **679 ok, 0 błędów**.
- `lune run tools/economy_sim.luau`: zakończone poprawnie; jaskinia około 56 min, bagna 1 h 53 min, maksymalne ulepszenia 3 h 41 min. Model nie dowodzi poprawności wypłat między serwerami ani zapisu lasu.
- `git diff --check`: bez błędów whitespace; Git wypisał ostrzeżenia LF/CRLF.
- Pierwsze uruchomienie Lune w sandboxie nie miało dostępu do katalogu. Powyższe wyniki pochodzą z udanych uruchomień po uzyskaniu uprawnienia.
- Nie uruchamiałem Studio ani rzeczywistych operacji DataStore. Wyścigi, awarie i scenariusze uszkodzonego profilu opisano na podstawie przepływu kodu, bez deklarowania reprodukcji w live. Istniejące nowe testy sprawdzają funkcje czyste, nie integrację `payGoal`, moderację, aktywność profilu ani round-trip lasu.
- Aktualizacja tabeli `data.forest` w pamięci nie jest natychmiastowym trwałym zapisem „także przy awarii”. Lokalny ProfileStore ma autozapis co 300 s; awaria może cofnąć stan do ostatniego zapisu. Profil wiąże koszyk i las w jednym snapshotcie, ale nie daje transakcji obejmującej profile całej grupy i ranking. Nie uznaję tej własności za samodzielny dowód darmowego farmienia bez sposobu wywołania odpowiedniej awarii.

**Kolejność poprawek:** zabezpieczyć usuwanie przed trwającymi aktualizacjami, publikować potwierdzony wynik profilu, ujednolicić reset/generację lasu, uzupełnić zapisy po Wysypie i walidację nowych pól, poprawić filtrowanie deweloperów i odizolować moderację Studio. Następnie testy integracyjne z kontrolowanym czasem, awariami i opóźnionymi zapisami.

---

## Ponowne review kodu — Wersja 4, 30.10.2026

**Werdykt: sześć pierwotnych usterek usunięto, problem generacji lasu nie jest w pełni naprawiony. Są też dwa problemy w ścieżkach awaryjnych rankingu.** Ocena według aktualnego `git diff`, `docs/REVIEW.md` i sekcji „Wersja 4”. Poniższe numery linii dotyczą aktualnej kopii, a nie pierwszego review powyżej.

### Status każdej z siedmiu uwag

| Nr | Uwaga z poprzedniego review | Status | Uzasadnienie |
|---|---|---|---|
| 1 | Opóźniony zapis odtwarza usunięty wynik | **naprawione** | `remove` zapisuje trwałe 0, a `writeCandy` sprawdza znacznik i lokalną blokadę przy każdym wywołaniu transformacji. `nil` oznacza nowy wpis, 0 oznacza zakaz — te stany nie są mylone. Globalny odczyt ma `minValue = 1`. Pozostaje osobny nowy problem lokalnego fallbacku, opisany niżej. |
| 2 | Publikacja niezapisanego wyniku | **naprawione** | Upload globalny i `onProfileSaved` korzystają z `confirmedCandy`, opartego na `LastSavedData` / `OnAfterSave`, zamiast bieżącego `stats.candy`. Nowy problem: nieudana publikacja końcowego zapisu gracza offline nie jest ponawiana. |
| 3 | Rozjazd generacji przy przywołanej nocy | **nie naprawione** | Powrót na ten sam opóźniony serwer jest poprawiony. Przywrócenie nowszego lasu na starszym serwerze działa, ale późniejszy reset serwera ponownie losuje ten sam las. Brakuje ochrony na poziomie generacji każdego profilu. |
| 4 | Wysyp nie zapisuje skróconych terminów | **naprawione** | Pętla ma `id` i po zmianie `readyAt` wywołuje `rememberSpot` ([GameService.luau:1445](T:/lantern/mushrooms/src/server/GameService.luau:1445)). |
| 5 | Nieskończone / odległe liczby w nowych polach | **naprawione** | `finite` odrzuca NaN i ±inf, licznik sekund ma limit, dzień ma zakres, czas miejsca ma górny pułap. Przyszłe generacje są odrzucane w `canRestore`. Ocena dotyczy zgłoszonych pól, nie stanowi audytu wszystkich starszych pól profilu. |
| 6 | Deweloperzy pozostają w odczycie rankingu | **naprawione** | `staffId` działa po UserId także offline; `candyAllowedId` jest używane przy odczycie i zapisie. Dalsze strony są czytane zgodnie z limitem pięciu stron z planu. |
| 7 | Studio usuwa produkcyjny wynik | **naprawione** | `LeaderboardService.remove` odrzuca Studio przed ustawieniem blokady i przed operacją DataStore. Komenda dostaje wynik powodzenia. |

### A. [P1] Ponowny reset tej samej generacji po przejściu między serwerami

**Plik i linie:** [GameService.luau:1034](T:/lantern/mushrooms/src/server/GameService.luau:1034), reset wszystkich sesji w liniach 1034–1035; [GameService.luau:1820](T:/lantern/mushrooms/src/server/GameService.luau:1820), ustawienie generacji i reset. Warunek dopuszczający nowszy zapis: [Cycle.luau:111](T:/lantern/mushrooms/src/shared/Cycle.luau:111); przywrócenie: GameService 924–926.

**Scenariusz gracza/grupy:**

1. Na serwerze A zaczyna się zwykły świt. Gracz dostaje las generacji 1000 i zbiera wartościowe miejsca; nowe cooldowny są zapisane w profilu.
2. Przechodzi na serwer B, gdzie przywołana Noc Dziadów opóźniła świt, więc `serverGen = 999`. `canRestore(1000, 999, t)` słusznie zwraca true. Profil zachowuje generację 1000 i zużyte miejsca.
3. Przywołanie na B kończy się przed końcem naturalnego świtu. `shouldRegrow("dawn", 999, t)` zwraca true. Serwer ustawia `serverGen = 1000` i wywołuje `regrowForest` dla wszystkich sesji, również tego gracza.
4. Gracz dostaje drugi świeży las generacji 1000, z `readyAt = now`, mimo że swój reset tej generacji już wykorzystał na A. Grupa może szukać kolejnych serwerów z później kończącym się przywołaniem i powtórzyć manewr w obrębie tego świtu.

To rzeczywiste dodatkowe losowanie i obejście cooldownów, również strażników; nie jest to nieskończona pętla bez warunków. Wymaga serwerów z różnym momentem zakończenia dozwolonego wydarzenia DEV. Gracz korzystający z luki sam nie potrzebuje uprawnień DEV.

**Potwierdzenie:** uruchomiłem przez stdin Lune test używający rzeczywistych modułów `Config` i `Cycle`, bez tworzenia pliku testowego. Dla `dawn + 30 s` nowszy zapis jest przyjmowany, a przy `dawn + 60 s` reset opóźnionego serwera celuje w dokładnie tę samą generację 1000. Następnie przepływ `resetForest` w kodzie bezwarunkowo odnawia wszystkie sesje. Nie jest to test integracyjny Roblox.

**Poprawka:** zwykły reset kalendarzowy stosować tylko do sesji, których `data.forest.g < targetGeneration`. Samo `serverGen` określa stan serwera, nie to, czy dany gracz odebrał już reset gdzie indziej. Zapisanej generacji nie wolno cofać. Oddzielić wymuszone odnowienie przez `pumpkinBoom` / debug od resetu kalendarzowego: obecne `regrowForest` wpisuje `forestGen()` bez względu na wcześniejsze `g`, więc na starszym serwerze może dodatkowo obniżyć generację nowszego profilu. Bonus administratora może być świadomie dodatkowy, ale nie powinien powodować kolejnego bonusu przez cofnięcie numeru generacji i reconnect.

**Test wymagany:** A resetuje do g, gracz zbiera, B przywraca g przy swoim g−1, B dogania do g — grzyby i terminy tego gracza pozostają bez zmian; gracze B z g−1 otrzymują reset. Osobno `pumpkinBoom` na sesji z generacją nowszą od serwera nie obniża `g`.

### B. [P2] Nowy problem: końcowy wynik offline przepada po jednym błędzie publikacji

**Plik i linie:** [LeaderboardService.luau:250](T:/lantern/mushrooms/src/server/LeaderboardService.luau:250), `onProfileSaved`, zwłaszcza 264–273; czyszczenie potwierdzonego snapshotu: [DataService.luau:464](T:/lantern/mushrooms/src/server/DataService.luau:464).

**Scenariusz awarii, nie darmowego farmienia:** profil gracza zapisuje po wyjściu końcowe 150 cukierków, podczas gdy ranking ma 100. `OnAfterSave` uruchamia publikację. Jedna awaria/throttling `UpdateAsync` kończy się tylko `warn`. Gracza nie ma już w `Players:GetPlayers()`, więc pętla minutowa go nie ponowi; `confirmed[player]` zostaje usunięte, a callback nie zachowuje zadania do ponowienia. Jeśli gracz nie wróci przed `finalizeAt`, wynik pozostaje zaniżony mimo poprawnego trwałego profilu. Samo wydłużenie okresu finalizacji nie uruchamia naprawy.

**Poprawka:** zachować kolejkę zaległych potwierdzonych wyników po UserId, niezależną od obiektu Player i obecności w sesji, i ponawiać z backoffem do sukcesu/znacznika moderacji/finalizacji. Używać snapshotu `_saved` przekazanego do callbacku zamiast zależeć od czasu życia cache. Jeśli finalizacja ma przetrwać także zamknięcie procesu, potrzebna jest trwała kolejka albo inny mechanizm odtworzenia brakujących publikacji. Każda ponowna próba nadal musi respektować znacznik 0 i wykluczenia.

Nie zgłaszam samego `task.spawn` jako dowodu, że obecny callback zawsze czyta wyczyszczony cache: w aktualnym przepływie odczyt `confirmedCandy` następuje przed pierwszym oczekiwaniem tego listenera. Potwierdzony problem to brak ponowień po błędzie publikacji, nie hipotetyczna kolejność wszystkich callbacków.

### C. [P2] Nowy problem: lokalny fallback pokazuje wynik zbanowany znacznikiem 0

**Plik i linie:** [LeaderboardService.luau:214](T:/lantern/mushrooms/src/server/LeaderboardService.luau:214), linie 214–219, w połączeniu z `candyAllowedId` w 107–109.

**Scenariusz:** moderator na A zapisuje 0 dla konta, bez dopisywania go do Config. Konto przechodzi na B, którego lokalne `removed` jest puste. Zwykły zapis globalny poprawnie respektuje 0. Jeśli odczyt DataStore na B zawiedzie, `topFor` przechodzi jednak na lokalne `scoreOf(data, "candy", ...)`; `allowed` nie zna trwałego znacznika tego konta. Konto ponownie pojawia się na lokalnej tablicy z dodatnim wynikiem. Do tego fallback używa bieżącego, a nie potwierdzonego `stats.candy`.

Skutek jest ograniczony do widoku oznaczonego `server`: nie nadpisuje 0 w globalnym magazynie i nie daje nagrody ekonomicznej. Mimo to stanowi obejście wykluczenia w jednej z dróg prezentacji rankingu. Nie zakładam, że zwykły gracz może sam wywołać awarię DataStore; może wykorzystać serwer z awarią.

**Poprawka:** dla cukierków w razie braku dostępu pokazywać ostatni zatwierdzony globalny snapshot ze wskazaniem nieaktualności albo stan „ranking niedostępny”. Nie tworzyć nowej listy z profili przy nieznanym statusie moderacji. Jeśli lokalny ranking ma zostać, potrzebuje potwierdzonego wyniku i potwierdzonego statusu wykluczenia; sam cache wyniku profilu nie wystarczy.

### Dodatkowe sprawdzenia i granice oceny

- Znacznik 0 jest poprawną poprawką dla współpracujących instancji z aktualnym `writeCandy`: dodatni wynik nie może zastąpić istniejącego 0, a nowy wpis z `old == nil` może powstać. Nie znalazłem nowej drogi zwykłego klienta do ustawiania/usuwania znacznika. Przy wdrożeniu trzeba zakończyć stare instancje z poprzednim kodem `max(old, score)` — tamten kod nie respektuje 0. To warunek migracji, nie wada nowej transformacji.
- `confirmedCandy` odrzuca nieliczbowe, nieskończone i niedodatnie wartości. `OnAfterSave` korzysta z potwierdzonego stanu ProfileStore. Nie znalazłem w nowej ścieżce globalnego uploadu zamiany go z bieżącą tabelą `session.data`. Wyjątek prezentacyjny to fallback z pkt C.
- Nowa walidacja `eventGoals`, `forest.g/t` i `luckUntil` usuwa zgłoszone nieskończoności. Nadal nie jest pełną walidacją całego profilu: nieznane identyfikatory miejsc mogą zajmować limit 600 wpisów przed sprawdzeniem mapy, a `canRestore` zakłada wartości wcześniej oczyszczone przez `reconcile`. Nie wykazałem drogi z RemoteEvent do wstawiania takich wpisów; nie podnoszę tego do nowego exploitu zwykłego klienta.
- Pięć stron odczytu to świadomy limit Wersji 4, a nie obietnica zawsze pełnej dziesiątki. Bardzo duża liczba dodatnich starych wpisów kont wykluczonych w Config może nadal ukryć dalsze dozwolone wyniki; porządkowanie ich do 0 rozwiązuje to bez nieograniczonej paginacji.
- Proporcjonalne wypłaty celu i allowlista DEV nie otrzymały tu zmiany otwierającej potwierdzony nowy exploit. Zachowują ograniczenia i świadome wyjątki z Wersji 3.

### Weryfikacja

- `lune run tests/economy.spec.luau`: **680 ok, 0 błędów**.
- `lune run tools/economy_sim.luau`: sukces; nadal około 56 min do jaskini, 1 h 53 min do bagien i 3 h 41 min do maksymalnych ulepszeń.
- `git diff --check`: bez błędów whitespace, tylko ostrzeżenia LF/CRLF.
- Dodatkowy test przez stdin potwierdził kombinację `canRestore` / `shouldRegrow` z pkt A na rzeczywistym module Cycle. Obecny test pokoleń sprawdza każdą decyzję osobno i nie testuje końcowego resetu sesji z już nowszym `data.forest.g`.
- Nie uruchamiałem Studio ani rzeczywistych awarii DataStore. Dla pkt B/C dowodem jest przepływ kodu, nie deklarowana reprodukcja w usłudze live. Potrzebne testy integracyjne: dwa serwery i opóźniony świt, błędna pierwsza publikacja po wyjściu oraz fallback po moderacji na innym serwerze.

**Do zamknięcia review:** reset lasu według generacji każdego profilu, ponawianie publikacji końcowych potwierdzonych wyników oraz bezpieczny fallback rankingu cukierków. Pozostałych sześciu pierwotnych usterek nie zgłaszam ponownie jako nienaprawionych.

---

## Ponowne review kodu — Wersja 5, 30.10.2026

**Werdykt: A naprawione; B naprawione dla ponawiania na działającym serwerze; C ma nowy problem w cache. Dodatkowo kolejka dopuszcza równoległe wysyłanie tych samych wpisów.** Sprawdziłem aktualny diff według `docs/REVIEW.md` i sekcji „Wersja 5”. Numery linii poniżej dotyczą tej wersji kopii roboczej.

### Status A, B i C

| Uwaga | Status | Ocena poprawki |
|---|---|---|
| A — drugi reset tej samej generacji | **naprawione** | `resetForest` sprawdza generację każdej sesji przez `Cycle.needsRegrow`; równa albo nowsza generacja nie dostaje zwykłego resetu. `regrowForest` zachowuje maksimum starego i serwerowego `g`, również przy `pumpkinBoom`. |
| B — brak ponawiania wyniku po wyjściu | **naprawione** | Wynik ze snapshotu trafia do `pending[UserId]`, pozostaje po błędzie i jest ponawiany przez pętlę minutową także bez Playera. Nie zależy już od wyczyszczonego `confirmed`. Nowa usterka współbieżności opisana w pkt 1. Kolejka pozostaje nietrwała — ograniczenie opisane niżej. |
| C — lokalna lista omijająca moderację | **nowy problem** | Budowanie listy z bieżących profili usunięto, więc pierwotna ścieżka została zamknięta. Cache `lastCandy` nie jest jednak filtrowany po lokalnym usunięciu konta; przy błędzie odczytu może ponownie pokazać wynik, o którego wykluczeniu ten serwer już wie. |

### 1. [P2] Równoległe flushCandy powielają operacje DataStore

**Plik i linie:** [LeaderboardService.luau:146](T:/lantern/mushrooms/src/server/LeaderboardService.luau:146), `flushCandy`, zwłaszcza 158–169; wywołanie przy każdym potwierdzonym zapisie w liniach 307–312.

**Scenariusz:** jeden worker robi kopię `pending` i czeka na `UpdateAsync`. W tym czasie następny `OnAfterSave`, minutowa pętla albo zamykanie serwera uruchamia drugi `flushCandy`. Nie ma blokady workera ani oznaczenia wpisu jako wysyłanego. Drugi worker kopiuje tę samą kolejkę i wysyła te same wyniki. Nawet gdy pierwszy worker później opróżni `pending`, pozostałe nadal przechodzą po swoich kopiach i wykonują zbędne zapisy.

Grupa kont z cukierkami może wywołać serię końcowych zapisów przez zbliżone w czasie wyjścia; podobne spiętrzenie wystąpi legalnie przy zamknięciu serwera. Przy wolnym DataStore kolejne callbacki powielają coraz większą liczbę oczekujących operacji, zamiast scalać pracę. Skutkiem jest zużycie budżetu zapisów, throttling i opóźnienie publikacji innym graczom. `max(old, score)` chroni wartość rankingu przed mnożeniem punktów, ale nie koszt i liczbę żądań.

**Potwierdzenie:** test przez stdin Lune załadował rzeczywisty blok `pending`/`queueCandy`/`flushCandy` z pliku, podstawiając zawieszającą się atrapę `writeCandy`. Dwa równoległe wywołania dla jednego oczekującego wyniku rozpoczęły dwa zapisy tego samego konta. Nie wykonywałem rzeczywistych operacji DataStore.

**Poprawka:** jeden worker opróżniający kolejkę, z blokadą ustawianą przed pierwszym yieldem. Kolejne callbacki tylko scalają najwyższy wynik po UserId i sygnalizują pracę. Worker po zapisie usuwa wyłącznie wersję, którą faktycznie obsłużył; nowszy wynik pozostaje. Zachować ochronę znacznika 0, obsługę błędów i zwolnienie blokady także przy błędzie. `BindToClose` powinien współpracować z tym workerem, nie uruchamiać następnej niezależnej kopii.

**Test:** zablokowany zapis, kilka nowych snapshotów i wywołań flush; najwyżej jedna operacja w toku na konto, po odblokowaniu opublikowany największy wynik, brak utraty nowszego wpisu.

### 2. [P2] Cache fallbacku przywraca lokalnie usunięty wynik

**Plik i linie:** [LeaderboardService.luau:269](T:/lantern/mushrooms/src/server/LeaderboardService.luau:269), zwrot `lastCandy`; moderacja w liniach 323–337.

**Scenariusz:** serwer pobiera czołówkę zawierającą konto X. Moderator na tym samym serwerze usuwa X: ustawia `removed[X]`, czyści `pending[X]` i skutecznie zapisuje 0. Następujący odczyt rankingu zawodzi. `topFor` zwraca niezmienione `lastCandy`, więc X nadal jest pokazywane, mimo że serwer zna jego wykluczenie. To nie opóźnienie propagacji moderacji z innego serwera, tylko pominięcie własnego stanu moderacji.

Cache otrzymuje też `Source = "global"`, a `refresh` ustawia mu nowe `UpdatedAt`. Widok nie odróżnia zatem starej odpowiedzi od udanego świeżego odczytu. Globalne 0 nadal działa poprawnie — problem dotyczy wyświetlania, nie odtworzenia dodatniego wyniku w magazynie ani wypłaty nagród.

**Poprawka:** przy lokalnej moderacji usunąć konto także z `lastCandy`, a przy każdym zwrocie cache ponownie filtrować przez `candyAllowedId`. Chroni to również przed zapisaniem do cache starszej odpowiedzi z odczytu rozpoczętego przed moderacją. Zachować czas ostatniego udanego odczytu i oznaczyć dane jako nieaktualne albo pokazać stan niedostępności. Nie obiecywać bieżącej wiedzy o moderacji z innych serwerów podczas awarii odczytu.

**Test:** udany odczyt z X → udana moderacja X → błąd odczytu; X znika także z fallbacku. Drugi wariant: odczyt rozpoczęty przed moderacją kończy się po niej.

### Sprawdzone własności i ograniczenia

- [Cycle.luau:117](T:/lantern/mushrooms/src/shared/Cycle.luau:117): `needsRegrow(nil, target)` i starsza generacja dają reset; równa/nowsza nie. [GameService.luau:1040](T:/lantern/mushrooms/src/server/GameService.luau:1040) faktycznie używa warunku w pętli sesji. Wymuszony reset jest osobną ścieżką, a [GameService.luau:1018](T:/lantern/mushrooms/src/server/GameService.luau:1018) nie cofa `g`. Nie znalazłem nowego obejścia resetu zwykłym reconnectem w sprawdzanych zmianach.
- `queueCandy` scala wyniki maksimum. Usunięcie `pending` tylko przy równości z wysłanym snapshotem zachowuje wyższy wynik dodany w trakcie oczekiwania. Wolniejszy starszy worker nie obniża `published`. Nie stwierdziłem podwajania punktów przez kolejkę; pkt 1 dotyczy powielania żądań.
- Callback `writeCandy` nadal respektuje znacznik 0 i lokalne wykluczenie przy każdej próbie. Udane anulowanie transformacji na znaczniku kończy ponawianie; choć `published` nazywa taki wynik opublikowanym, nie jest to droga do nadpisania 0. Nie ma w tej wersji automatycznego cofania moderacji.
- [DataService.luau:473](T:/lantern/mushrooms/src/server/DataService.luau:473): `candyOf` waliduje strukturę tabel, odrzuca nieliczbowe wartości, NaN, ±inf i liczby niedodatnie, dodatnie zaokrągla w dół. Dostaje snapshot z serwerowego `OnAfterSave`, nie dane RemoteEvent. Wydzielenie tej funkcji nie otwiera nowego źródła cukierków ani odczytu bieżącego, niezapisanego profilu. Nie ma jednak górnego limitu dla wielkich skończonych liczb w uszkodzonym zapisie; nie wykazałem klientowej drogi ich wstrzyknięcia.
- Kolejka jest tylko w pamięci. `BindToClose` czeka 3 s i robi jedną próbę, nie gwarantuje dotarcia wszystkich końcowych snapshotów ani powodzenia zapisu. Awaria procesu lub błąd ostatniej próby nadal może zostawić wynik offline nieopublikowany do następnego wejścia. To ograniczenie trwałości, o którym wspominało poprzednie review, a nie powód do twierdzenia, że zwykłe ponawianie na działającym serwerze nie zostało naprawione. Pełna gwarancja finalizacji wymaga trwałej kolejki albo późniejszego odtworzenia publikacji z zapisanych profili.
- Przy pierwszym błędzie `flushCandy` przerywa cały przebieg. Oczekujące wyniki pozostają, ale pojedynczy uporczywie błędny wpis może opóźniać konta trafiające po nim. Przy wdrażaniu jednego workera warto izolować błędy wpisów i stosować osobne terminy kolejnych prób, zamiast blokować pozostałych.

### Weryfikacja

- `lune run tests/economy.spec.luau`: **680 ok, 0 błędów**. Rozszerzony test pokoleń obejmuje teraz A → B → opóźniony reset B oraz `needsRegrow`.
- `lune run tools/economy_sim.luau`: sukces, nadal około 56 min do jaskini, 1 h 53 min do bagien, 3 h 41 min do maksymalnych ulepszeń.
- `git diff --check`: bez błędów whitespace; ostrzeżenia LF/CRLF.
- Dodatkowy test kolejki przez stdin: potwierdzone dwa równoległe zapisy dla jednego oczekującego wyniku. Nie tworzyłem plików testowych i nie zmieniałem kodu aplikacji.
- Nie uruchamiałem Studio ani awarii usług live. Scenariusz cache oceniono z przepływu kodu; pozostaje do sprawdzenia testem integracyjnym z atrapą odczytu i moderacji.

**Do poprawienia przed zamknięciem review:** serializacja pracy `flushCandy` oraz usuwanie znanych wykluczeń także z cache fallbacku. Pierwotna luka A jest zamknięta; nie ma podstaw, by ponownie zgłaszać mnożenie zasobów przez reset tej samej generacji.

---

## Ponowne review kodu — Wersja 6, 30.10.2026

**Obie uwagi Wersji 5 naprawione.** Nie znalazłem w sprawdzonych zmianach nowego exploitu pozwalającego zwykłemu graczowi zwiększyć wynik lub ominąć moderację. Pozostaje błąd ograniczenia czasu zamykania serwera, opisany poniżej. Ocena obejmuje aktualny diff, nowy plik `ScoreQueue.luau` oraz sekcję „Wersja 6”, według zasad `docs/REVIEW.md`.

| Uwaga Wersji 5 | Status | Uzasadnienie |
|---|---|---|
| 1 — równoległe flush powielają operacje | **naprawione** | `running` jest ustawiane przed wywołaniem workera; następne `flush` ustawiają tylko `again`. Po zapisie kasowana jest wyłącznie wysłana wersja, wyższy wynik zostaje. Błąd `retry` nie przerywa pozostałych wpisów. |
| 2 — cache pokazuje lokalnie usunięte konto | **naprawione** | `filterCandy` jest wywoływane przy zapisaniu udanego odczytu, przy zwrocie fallbacku i przy moderacji. Późno zakończony stary odczyt też podlega ponownej filtracji. Cache ma `Source = stale` i zachowuje czas ostatniego udanego odczytu. |

### [P2] Nowy problem: deadline zamykania nie obejmuje uruchomionego synchronicznie flush

**Plik i linie:** [LeaderboardService.luau:358](T:/lantern/mushrooms/src/server/LeaderboardService.luau:358), linie 358–360; [ScoreQueue.luau:58](T:/lantern/mushrooms/src/server/ScoreQueue.luau:58).

**Scenariusz awarii:** w chwili zamykania kolejka ma wiele wpisów, a worker nie działa. `BindToClose` wywołuje `flushCandy()` bezpośrednio. To wywołanie samo staje się workerem i czeka na kolejne operacje DataStore. Dopiero po całym przebiegu kod ustawia `deadline = os.clock() + 20`. Limit 20 s nie obejmuje więc żadnego z tych oczekiwań. Przy wolnych zapisach wykonanie może zostać przerwane wraz z zamknięciem procesu przed dotarciem do pętli deadline, z pozostawionymi wynikami offline.

Gdy worker już działa, `flushCandy` wraca szybko i deadline działa dla oczekiwania na niego. Problem dotyczy właśnie przypadku bez aktywnego workera. Nie jest to mnożenie punktów ani obejście pojedynczego workera; jest to rozbieżność z deklarowanym ograniczeniem czasu.

**Poprawka:** ustalić deadline przed uruchomieniem pracy, uruchomić wywołanie tego samego chronionego workera asynchronicznie i czekać na jego stan tylko do ustalonego czasu. Jeśli wymagane jest także zaprzestanie rozpoczynania nowych zapisów po deadline, przekazać warunek zatrzymania do workera i sprawdzać go między operacjami. Nie zakładać, że da się anulować już rozpoczęte oczekiwanie DataStore. Test: nieaktywny worker, kilka zapisów z opóźnieniem przekraczającym budżet — callback zamykania respektuje czas także w tym wariancie.

### Pozostałe sprawdzenia

- `remove` najpierw ustawia lokalne wykluczenie, usuwa oczekujący wpis i filtruje cache, a następnie zapisuje trwałe 0. Kopia listy kluczy w workerze ponownie odczytuje `pending[userId]`, więc usunięty przed obsługą wpis jest pomijany. Zapis już w toku nadal chroni callback `UpdateAsync` oraz trwały znacznik. Nie znalazłem regresji odtwarzającej zmoderowany wynik.
- `running` wraca do false także po wyjątku dzięki zewnętrznemu `pcall`. W aktualnym adapterze błędy DataStore są zamieniane na `retry`/`stop`. `stop` kończy bieżący przebieg, nie usuwa oczekujących danych. Nowy wyższy wynik dodany podczas zapisu nie jest kasowany przez potwierdzenie niższego.
- `again` może spowodować wcześniejszą ponowną próbę błędnego wpisu, jeśli w trakcie pracy przyszło następne żądanie flush. Nie ma jeszcze backoffu per konto, ale nie powstają już równoległe kopie workera. Nie traktuję samego braku backoffu jako dowodu nowego exploitu.
- Cache nie zna nowych decyzji moderacji z innych serwerów podczas awarii odczytu. Jest teraz jawnie oznaczone jako stare dane; to oczekiwane ograniczenie cache, a nie powrót lokalnej listy z profili.
- Nietrwałość kolejki została jawnie zaakceptowana w Wersji 6. Nie zgłaszam ponownie utraty nieopublikowanych wyników przy awarii procesu jako nowej usterki tej wersji. Próba przy zamknięciu również pozostaje działaniem bez gwarancji trwałej publikacji.

### Weryfikacja

- `lune run tests/economy.spec.luau`: **681 ok, 0 błędów**. Nowy test ScoreQueue obejmuje spiętrzone wywołania, najwyżej jeden zapis w toku, wyższy wynik dodany podczas oczekiwania, błąd wpisu i usuwanie z kolejki.
- `git diff --check`: bez błędów whitespace; ostrzeżenia LF/CRLF.
- Nie powtarzałem niezmienionej symulacji ekonomii: poprawki dotyczą kolejki i cache. Nie uruchamiałem Studio ani rzeczywistych operacji DataStore. Scenariusz deadline wynika z kolejności wywołań; obecny test czystej kolejki nie testuje callbacku `BindToClose`.

**Ocena końcowa tej rundy:** uwagi 1 i 2 zamknięte; do poprawienia pozostaje umiejscowienie deadline w obsłudze zamykania. Dopisano wyłącznie ten plik review.
