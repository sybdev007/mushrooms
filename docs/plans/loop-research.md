# Rozwój pętli Midnight Mushroom Hunt

Stan: plan przed implementacją, 2026-11-01. Dokument powstał na podstawie bieżącego kodu i ponownego uruchomienia `lune run tools/economy_sim.luau`. W tym checkoutcie nie było wcześniejszego `docs/plans/loop-research.md`; poniższy tekst odtwarza zakres wskazany w zleceniu, nie jest zachowaną kopią wcześniejszego researchu.

## 1. Diagnoza i wyniki symulatora

Obecna pętla: zbieranie → sprzedaż / ogródek → ulepszenia → następny świat. Atlas, mutacje, strażnicy, ogródek, pościgi i zadania już istnieją. Nowy plan powinien dodać powód do kolejnej wyprawy oraz zastosowanie dla pieniędzy po zakończeniu rozwoju sprzętu.

| Kamień milowy | Czas od początku gry w modelu | Dochód modelu w tym punkcie |
| --- | ---: | ---: |
| Odblokowanie jaskini, próg 30 000 monet | 56 min | 8 547 monet/min |
| Odblokowanie bagien, próg 1 000 000 monet | 1 h 53 min | 69 612 monet/min |
| Maksimum ulepszeń dochodowych | 3 h 41 min | 127 844 monet/min |
| Gra po wymaksowaniu, sama optymalna wyprawa na bagnach | po 3 h 41 min | około 100 658 monet/min |
| Gra po wymaksowaniu, wyprawa i modelowy ogródek | po 3 h 41 min | około 127 844 monet/min |

To model wydajnej gry, nie zmierzona mediana graczy. Symulator wybiera opłacalne strefy i zakupy, zakłada regularną sprzedaż i obsadzony ogródek; nie symuluje błędów, kradzieży, porażek, szukania drogi ani zachowania prawdziwego gracza. Nie uwzględnia też wszystkich dodatkowych źródeł i bonusów, np. premii sprzedaży z Atlasu oraz produktów za Robuxy. Kwoty przy portalach są progami posiadania monet: obecny `checkPortals` nie odejmuje ich przy odblokowaniu.

**Precyzja określenia „wszystkie ulepszenia max”:** wynik 3 h 41 min obejmuje listę `ECON` symulatora: `oil`, `basket`, `boots`, `knife`, `crystal`, `pack`, `rushwick`, `creel`, `beds`, `fertilizer`. Nie obejmuje `lantern` i `lock`. Pełny koszt tych dwóch pozostałych ścieżek wynosi odpowiednio 5 628 i 1 983 monety, razem 7 611, czyli około 3,6 sekundy końcowego dochodu modelu, bez czasu obsługi sklepu. Nie zmienia to diagnozy, ale 3 h 41 min nie należy podpisywać jako osobno zmierzonego czasu każdego ulepszenia.

**P1 — koniec ulepszeń pozostaje problemem ekonomii.** „Znalezisko Nocy” daje cel wyprawy, lecz samo nie usuwa monet. Nagroda pieniężna wręcz powiększyłaby nadwyżkę. Potrzebne są dwa osobne elementy: gablota jako wydatek oraz Znalezisko jako rozgrywka i kolekcja.

## 2. Zlew monet: gablota kolekcjonera w ogródku

### Zasady

- Jedno darmowe miejsce pokazuje pierwsze zdobyte trofeum. Kolejne miejsca kupuje się za monety, bez wzrostu dochodu, szczęścia, pojemności koszyka czy ochrony ogródka.
- Trzy osobne serie gablot: leśna, kryształowa i bagienna, po sześć płatnych miejsc każda. Razem maksymalnie 19 miejsc z darmowym. Seria wymaga odblokowania odpowiedniego świata; nie trzeba wykupywać poprzedniej serii.
- Miejsce ma stały identyfikator serii i numer. Cena nie zależy od aktualnego miejsca pobytu ani wybranego portalu. Tańsza seria leśna nie odblokowuje miejsc bagiennych. To zamyka kupienie całej pojemności po cenach lasu przed wejściem do jaskini.
- Wystawiane są dekoracyjne zapisy zdobytych trofeów. Nie są to dodatkowe grządki ani bezpieczny magazyn przedmiotów ekonomicznych. W MVP nie można zamienić eksponatu na grzyb do sadzenia, sprzedaży, kradzieży lub handlu. Nie przenosimy istniejących dochodowych grzybów z ogródka do gabloty.
- Kolekcja zdobytych trofeów istnieje niezależnie od liczby miejsc. Brak wolnej gabloty nie blokuje otrzymania nagrody; gracz wybiera, co wystawić. Ten sam egzemplarz nie zajmuje kilku miejsc jednocześnie.
- Zmiana wystawy jest darmowa. Zakup miejsca jest trwały, bez sprzedaży zwrotnej. Każdy próg daje widoczną korzyść dekoracyjną: nowe stanowisko oraz stopniowo bogatszą oprawę całej serii.

### Skala i progi cen

`Progress.rewardScale` zwraca jednostkę nagród w monetach: las **1 600**, jaskinia **32 000**, bagna **160 000**. To nie mnożnik 1/20/100 przekazywany bezpośrednio jako cena.

Dla numeru płatnego miejsca `n = 1..6` w danej serii:

`cena(seria, n) = rewardScale(seria) × 10 × 2^(n - 1)`.

Skalę serii ustalamy przez `Progress.rewardScale(false, false)`, `Progress.rewardScale(true, false)` i `Progress.rewardScale(true, true)`. Nie używamy przy każdym zakupie bieżących flag kupującego do wyceny tej samej serii. Wszystkie poniższe ceny są cenami kolejnego miejsca, nie sumą do danego poziomu.

| Płatne miejsce w serii | Jednostki skali | Las | Jaskinia | Bagna | Bagna: suma od pierwszego miejsca |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 | 10 | 16 000 | 320 000 | 1 600 000 | 1 600 000 |
| 2 | 20 | 32 000 | 640 000 | 3 200 000 | 4 800 000 |
| 3 | 40 | 64 000 | 1 280 000 | 6 400 000 | 11 200 000 |
| 4 | 80 | 128 000 | 2 560 000 | 12 800 000 | 24 000 000 |
| 5 | 160 | 256 000 | 5 120 000 | 25 600 000 | 49 600 000 |
| 6 | 320 | 512 000 | 10 240 000 | 51 200 000 | 100 800 000 |
| **Razem** | **630** | **1 008 000** | **20 160 000** | **100 800 000** | **100 800 000** |

Wszystkie trzy serie pochłaniają łącznie **121 968 000 monet**. Leśna jest opcjonalnym celem kolekcjonera, a nie obowiązkiem przed jaskinią; UI powinno nadal wskazywać odblokowanie świata jako główny cel początkującego.

### Na ile dni wystarczą bagienne miejsca?

Przyjmujemy start bez oszczędności, wszystkie ulepszenia dochodowe i wydawanie całego dalszego dochodu na gablotę. „Dzień” poniżej oznacza konkretny budżet sesji, nie sztuczną blokadę czasową.

| Dochód | Czas aktywnego zarabiania na 100,8 mln | Dni po 2 h gry |
| --- | ---: | ---: |
| 100 000 monet/min | 16,80 h | 8,40 |
| 127 844 monet/min, końcowy wynik modelu | 13,14 h | 6,57 |
| 200 000 monet/min, scenariusz szybszego zarabiania | 8,40 h | 4,20 |

Przy 127 844 monet/min kolejne pojedyncze zakupy wymagają około **12,5 / 25 / 50 / 100 / 200 / 400 minut**. W sesjach po godzinie sama seria bagienna daje około 13 dni wydawania; przy dwóch godzinach około tygodnia. Ostatni próg jest długim celem prestiżowym, dlatego ta sama aktualizacja powinna pokazać wygląd nagrody przed zakupem.

Dochód offline przyspiesza zakup. Różnica końcowego modelowego dochodu łącznego i wyprawy to około `127 844 - 100 658 = 27 186 monet/min` z ogródka. Jeden pełny odbiór za limit 120 minut daje około **3 262 320 monet**. Przy 2 h aktywnej gry dziennie i jednym takim odbiorze: `100 800 000 / (127 844 × 120 + 3 262 320) ≈ 5,42 dnia`. Dochód ogródka podczas aktywnej gry jest już w 127 844 — nie dodajemy go ponownie. Wielokrotne odbiory offline, AFK, bardzo mocne rośliny i zakupy `harvest` skrócą ten czas bardziej.

To cel na kilka dni typowych sesji, nie gwarancja na kilka dni ciągłego farmienia. Gracz z istniejącymi 100 mln oszczędności kupi większość od razu. Po zebraniu danych można dodawać skończone serie dekoracji/prestiżowych opraw; nie tworzyć nieskończonej liczby modeli ani mnożników dochodu. Skończona gablota wydłuża P1, nie rozwiązuje go na zawsze.

### Zgodność z produktami za Robuxy

Obecne produkty to `rescue`, `boom`, `oil`, `harvest`, `luck` (`Config.Products`, `GameService.grantProduct`). Gablota nie daje ich zamienników za monety: nie ratuje koszyka, nie dolewa oleju, nie uruchamia Wysypu, nie podnosi szczęścia ani nie wypłaca dochodu ogródka. W szczególności nie dodaje grządek do `data.planted`; `GardenService.harvestNow` nadal liczy tylko istniejące rośliny i `Config.Garden.harvestMinutes = 30`.

Wydatek zachowuje zastosowanie przyspieszeń zarabiania: większy dochód pozwala szybciej kupić dekorację. Nie obiecujemy neutralnego wpływu na sprzedaż Robuxów bez pomiaru; sprawdzamy go po wdrożeniu. Znalezisko nie przyznaje odnawialnych darmowych odpowiedników tych produktów.

### Zakup i zapis

Serwer otrzymuje wyłącznie serię i oczekiwany następny numer. Sam sprawdza dozwoloną serię, odblokowanie świata, bliskość własnej gabloty, aktywny profil, stan portfela i dokładny następny poziom. Odrzuca ułamki, NaN, nieskończoność, zakup poziomu poza 1..6 i ponowioną prośbę o już kupione miejsce. Odejmowanie monet i zwiększenie poziomu odbywa się razem, bez yield pomiędzy nimi, w tym samym profilu. Nie zapisujemy oddzielnie portfela i zakupu.

Nowe dane mają ograniczony rozmiar: trzy liczniki 0..6, do 19 referencji wystawowych oraz zamknięty katalog trofeów. `DataService.defaultData` i lokalne `reconcile` muszą obsłużyć migrację i walidację; nie wystarczy dopisać pól tylko w pamięci sesji.

## 3. „Znalezisko Nocy” — MVP bez przechwytywania

**Pętla: zerwij → donieś do punktu w tym samym świecie → odbierz dekoracyjne trofeum.** MVP zaczyna się od jednego typu znaleziska w lesie i jednego punktu oddania przy chatce. Jaskinia i bagna później wykorzystują ten sam mechanizm z własnymi punktami w obozach. Gablota i jej ceny mogą od początku obsługiwać trzy serie; nowe trofea stopniowo wypełniają kolekcję.

1. **Dostępność:** jedna osobista próba na naturalny cykl nocy, po samouczku. Serwer wyznacza punkt spośród przygotowanych, osiągalnych miejsc. Osobista dostępność zapobiega zajęciu wszystkich znalezisk przez jednego gracza/grupę. Inni mogą zobaczyć niesiony okaz, ale nie mogą go zabrać, blokować interakcji ani otrzymać kopii nagrody.
2. **Identyfikator:** próba jest powiązana z `Cycle.at(os.time()).index`, nie z samym przełączeniem wizualnej fazy na noc. Przywołana Noc Dziadów, Wysyp, restart lub wymuszona faza nie tworzą dodatkowego uprawnienia. Zapamiętujemy najwyższy rozpoczęty cykl w profilu; nie cofamy go po zmianie serwera. W przyszłej wersji wieloświatowej obowiązuje nadal jedna próba łącznie, nie trzy po zmianie portalu.
3. **Zerwanie:** serwer sprawdza cykl, uprawnienie, żywą postać, brak stanu downed, odblokowany świat, dystans 3D i brak innego noszonego łupu. Rezerwuje próbę i tworzy jeden obiekt noszenia. Klient nie wybiera nagrody, wartości ani miejsca. Nie trafia on do `basket`, `planted` czy skarbca.
4. **Transport:** grzyb nad głową, czytelna obwódka, punkt dostawy i licznik. Dla MVP limit 180 s od zerwania, niezależnie od nadejścia świtu; stały współczynnik prędkości 0,9 jako wartość do testów trasy. Nie kopiować `guardianSpeed = 0.6` z kradzieży: może uczynić ucieczkę niemożliwą. Zwykły olej i istniejące zagrożenia nadal działają. Nie dodajemy nowego strażnika w MVP.
5. **Dostawa:** tylko w wyznaczonym punkcie świata, po serwerowej kontroli odległości, stanu noszenia, terminu i przebytej drogi. Samo wejście do dowolnej bezpiecznej strefy lub zakończenie pościgu nie wystarcza. Przejście `carrying → delivered` zużywa identyfikator dokładnie raz przed przyznaniem trofeum.
6. **Nagroda:** dekoracyjne trofeum z zamkniętego katalogu oraz licznik udanych dostaw. Kolejne warianty oprawy można odblokowywać za 1/3/7/15 dostaw. Bez monet, dodatkowego dochodu, szczęścia i odsprzedaży duplikatów. Dostawa daje postęp, a gablota daje powód do wydawania normalnie zarobionych monet.
7. **Porażka:** złapanie, `engulf`, śmierć/reset, portal, wyjście i timeout kończą próbę bez nagrody; nie zostawiają łupu dla innych. Stan downed wstrzymuje możliwość dostawy, ale nie zegar: pomoc kolegi albo istniejący produkt `oil` może pozwolić dokończyć próbę przed końcem. `rescue` nadal ratuje zwykły koszyk według obecnych zasad; UI wyraźnie oddziela od niego transportowane trofeum.

Stan `carrying` pozostaje sesyjny; w profilu zostają rozpoczęty cykl i ukończone nagrody. Po reconnect nie wznawiamy transportu ani nie losujemy kolejnej próby w tym cyklu. Utrata serwera po rozpoczęciu może oznaczać utratę próby — to jawna reguła MVP, a nie pretekst do przyznawania nagrody bez dostawy.

### Wykorzystanie istniejącego noszenia

`GardenService` już ma lokalne `carries`, `carryVisuals`, `endCarry`, `stepCarries` oraz publiczne `isCarrying` i `speedFactor`. Nie ma publicznego `beginCarry` ani obsługi znaleziska. Trzeba wydzielić wspólny rdzeń noszenia albo rozszerzyć go o rozróżnione typy `gardenTheft` i `nightFind`; nie tworzyć dwóch niezależnych rejestrów pozwalających nosić dwa łupy.

- Wspólne: wizualizacja z `carryVisuals` (w tym `ThiefHighlight`, dla trofeum inny kolor/opis), sprzątanie obiektów, stan jednego noszonego łupu, ponowne przeliczenie prędkości w `applyCharacterStats`.
- Osobne polityki: adresat dostawy, timeout, dopuszczony świat, rezultat porażki i przechwytywanie. Obecny `stepCarries` odrzuca łup poza strefą 1 i po 60 s, a więc nie obsłuży wyprawy w lesie bez zmiany.
- Nie ustawiać `owner = carrier` tylko po to, aby pasował obecny typ: test odległości właściciela natychmiast uznałby to za odzyskanie. `nightFind` nie ma właściciela okradanej grządki.
- `endCarry` obecnie wywołuje `giveItem`, które może posadzić grzyb, dołożyć do koszyka albo wypłacić monety. Dla `nightFind` obowiązuje oddzielny callback nagrody dekoracyjnej; żaden z tych fallbacków nie może się uruchomić.
- W MVP nie uruchamiamy testu `tagRadius` dla znaleziska. Istniejąca kradzież ogródka zachowuje swoje obecne reguły.

### Bezpieczeństwo próby

Sprawdzenie promptu nie wystarczy. Kontrole serwera obejmują dystans z wysokością i świat, zdrowie/downed, blokadę współbieżnego zerwania/dostawy, maksymalny czas oraz próbki ruchu z tolerancją na opóźnienia. Minimalny czas przejścia sam nie zatrzyma teleportu: gracz może teleportować się i odczekać. Każdy legalny portal kończy próbę przed `PivotTo`; niemożliwa zmiana pozycji unieważnia dostawę.

Rozpoczęty cykl, znacznik dostawy i nagroda muszą być spójne w jednym profilu z blokadą sesji. Przy `canSave == false` funkcja jest niedostępna. Rezerwację próby należy potwierdzić zapisem przed udostępnieniem łupu; zablokować ponowne prośby podczas oczekiwania. `DataService.save` zwracające `true` oznacza wywołanie `profile:Save()`, nie potwierdzony zapis — potrzebne potwierdzenie przez istniejące `DataService.onSaved` i sprawdzenie zapisanego znacznika. Po timeout nie wydajemy łupu. W razie utraty niezapisanej dostawy klient nie może otrzymać obietnicy trwałego zapisu; po reconnect decyduje zapisany profil. Żadnego przenoszenia nagród na inne konta.

Alty mogą zdobywać własne dekoracje, ale nie przekazują ich ani monet głównemu kontu. Prywatny serwer nie daje krótszego cyklu, dodatkowych prób ani wyższej nagrody. Testowe wymuszenia pozostają poza produkcyjnym naliczaniem postępu.

## 4. Krok 2: opcjonalne przechwytywanie

Osobny etap po sprawdzeniu ukończeń i porażek MVP. Najpierw dobrowolny wariant wyprawy PvP; nie zmieniamy po cichu zasad osobistego znaleziska ani bezpieczeństwa gabloty.

- Nadal jeden obiekt i jedna nagroda na próbę. Przejęcie zmienia posiadacza, nie tworzy nowego egzemplarza i nie resetuje pierwotnego deadline.
- Wykorzystać ten sam `carries`, sprzątanie z `endCarry`, wizualizację `ThiefHighlight` i `Config.Garden.carry.tagRadius = 6` jako początkowy promień testów. Sam obecny test XZ nie wystarczy: potrzeba kontroli wysokości, przeszkód i dozwolonej strefy.
- Aktualne `stepCarries` pozwala odzyskać łup wyłącznie pierwotnemu właścicielowi. Przejęcie przez innego uczestnika to nowa logika, nie włączenie istniejącej flagi.
- Transfer bez yield: usunięcie starego noszenia → przypisanie tego samego `findId` nowemu graczowi → odświeżenie obu postaci. Nie wywoływać ścieżki `endCarry(..., "delivered")` przy przechwyceniu, bo dziś wypłaca łup i nalicza `steal`.
- Dostawa wyłącznie w punkcie wybranego świata. Punkt i bezpieczna strefa mają zakaz przechwytywania; krótka osłona po przejęciu zapobiega odbijaniu łupu co klatkę. Zasięg i długość osłony wymagają prób na trasach.
- Bez nagród za samo przechwycenie/odzyskanie; jeden końcowy postęp dostawy. Uczestnik może otrzymać najwyżej jedną nagrodę tej aktywności na cykl, niezależnie od liczby przekazań i serwerów. Uczestnictwo rezerwuje jego uprawnienie przed transferem. Nie naliczamy ogrodowych zadań `steal` ani rankingu kradzieży za podawanie znaleziska między altami.
- Transfer między kontami wymaga dopracowania zapisu obu uprawnień i zachowania po rozłączeniu. To osobny warunek wdrożenia kroku 2; zapis jednego profilu z MVP nie zapewnia transakcji obejmującej dwóch graczy.

## 5. Pliki i konkretne funkcje

Numery linii odnoszą się do kodu odczytanego 2026-11-01. Funkcje oznaczone jako proponowane jeszcze nie istnieją. Funkcje lokalne wymagają refaktoru lub jawnego API, nie da się ich bezpośrednio wywołać z nowego serwisu.

| Plik / istniejące funkcje | Konkretne zastosowanie lub konieczna zmiana |
| --- | --- |
| `src/server/GameService.luau`: `onPick` (1051), `rollSpot` (316) | Wzorzec walidacji zbierania. Znalezisko kierować do osobnej obsługi przed zwykłym dodaniem do koszyka i `ProgressService.found`; nie losować go ponownie przez odrost lasu. |
| `GameService`: `applyCharacterStats` (473), `tick` (810), `pushState` (274) | Wspólny mnożnik noszenia, obsługa transportu/downed, publikowanie celu i czasu. `WalkSpeed` obecnie korzysta z `GardenService.speedFactor`. |
| `GameService`: `travel` (618), `checkPortals` (626), `engulf` (530), `onCharacterAdded` (871), `onPlayerRemoving` (978) | Zakończenie próby przed teleportem/utratą sesji; obsługa resetu również przez `CharacterRemoving`. W `onPlayerRemoving` sprzątać z dostępem do sesji, zanim `sessions[player]` stanie się nil. |
| `GameService`: `start` (1589), pętla faz nocy w `start`, `resetForest` (1040), `regrowForest` (1020) | Wpiąć nowy serwis i harmonogram naturalnego cyklu. Reset lasu, Wysyp i noc przywołana nie mogą ponownie otwierać próby. |
| `GameService`: `grantProduct` (1452), `processReceipt` (1507), `onSell` (1174), `onBuy` (1544) | Zachować znaczenie produktów i koszyka. Zakup gabloty jako oddzielna akcja; nie używać `onBuy` z efektem napełnienia oleju ani dodawać trofeum do sprzedaży. |
| `src/server/GardenService.luau`: `carryVisuals` (463), `endCarry` (499), `stepCarries` (550), lokalne `carries` | Wydzielić wspólny mechanizm noszenia i różne reguły kończenia. Zachować `ThiefHighlight`, ale dopasować wygląd. Wyłączyć odzyskiwanie przez właściciela dla MVP znaleziska. |
| `GardenService`: `onSteal` (741), `isCarrying` (869), `speedFactor` (864), `release` (841), `start` (903) | Wzajemna blokada dwóch łupów; istniejące podpięcia Heartbeat i CharacterRemoving. Nie rozszerzać automatycznie reguł kradzieży ogrodu na Znalezisko. |
| `GardenService`: `assign` (795), `refreshGarden` (367), `nearOwnGarden` (591), `refresh` (856), `release` (841) | Przydział i odświeżanie gabloty właściciela, walidacja zakupu przy własnym ogródku, usuwanie modeli po odejściu. Osobny kontener wizualny, niezależny od `planted`. |
| `GardenService`: `giveItem` (442), `onPlantOne` (615), `onPlant` (659), `harvestNow` (874) | Granice integracji: trofea nie przechodzą przez te funkcje. W szczególności brak automatycznej zamiany na monety i brak zwiększenia dochodu produktu `harvest`. |
| `src/server/HoardService.luau`: `new` (33), lokalne `build`, `self.drop`, callback `prompt.Triggered`, hook `take` | Wzorzec serwerowego znacznika i zajęcia obiektu. Nie używać obecnego wspólnego skarbca do MVP: pozwala innym zabierać przedmiot. `self.drop` nie służy do upuszczania Znaleziska po porażce. |
| `src/server/ChaseService.luau`: `new` (79), `self.startChase`, `self.stop`, `self.isChased`, lokalne `step` | Istniejące pościgi i ich hooki można zachować. `onCaught` w `GameService.start` prowadzi do `engulf`; musi zakończyć transport. `onEscaped` oraz `onGaveUp` nie oznaczają dostawy trofeum; `stop` sam nie wywołuje hooków. |
| `src/server/ProgressService.luau`: `found` (371), `event` (304), `guardianEvent` (357) | `found` od razu aktualizuje Atlas, ranking najlepszego znaleziska i zdarzenia strażników, więc nie używać go dla dekoracyjnego ładunku. Nowy jawny event dostawy i pole kolekcji dopiero po zweryfikowanym sukcesie; nie podszywać się pod `steal`, `pick` lub `escape`. |
| `ProgressService`: lokalne `send` (152), `refreshTitle` (119), publiczne `refresh` (586), `join` (276) | Przesyłanie ograniczonej kolekcji i postępu, odświeżenie po dostawie i wejściu. Nowe tytuły wymagają osobnego wpisu w definicjach, samo wywołanie `event` nie tworzy nagrody. |
| `src/shared/Progress.luau`: `rewardScale` (307); `src/shared/Config.luau`: `Products`, `Garden.carry`, `Garden.harvestMinutes` | Ceny zależne od serii świata, parametry noszenia i sprawdzenie zgodności z istniejącą monetyzacją. |
| `src/shared/Cycle.luau`: `at`, `length` | Identyfikator naturalnego cyklu dla prób, wspólny dla serwerów. Nie utożsamiać z wizualnym `CyclePhase` ani generacją odrostu lasu. |
| `src/server/DataService.luau`: `defaultData` (88), lokalne `reconcile` (161), `save` (503), `onSaved` (498), `release` (514) | Domyślne pola gabloty/kolekcji/próby, ograniczenia i migracja, potwierdzenie rezerwacji, zapis całego profilu oraz blokada sesji. |

Proponowany nowy `NightFindService`: `begin`, `deliver`, `cancel`, `step`, `join`, `leave` — właściciel cyklu próby i nagrody. Proponowany wspólny `CarryService`: `begin`, `finish`, `isCarrying`, `speedFactor`, z callbackami polityki ogródka i znaleziska. Proponowany `ShowcaseService`: `buySlot`, `setDisplay`, `refresh`, `release`. To nazwy planowanych punktów implementacji, nie istniejące API. Konfiguracja cen powinna mieć jedną czystą funkcję współdzieloną przez serwer i podgląd klienta; serwer zawsze przelicza cenę sam.

## 6. Kolejność i kryteria odbioru

1. Gablota i migracja profilu: realny odpływ monet po maksimum sprzętu. Sprawdzić ceny wszystkich 18 płatnych miejsc, brak podwójnego zakupu i zachowanie po reconnect.
2. Znalezisko MVP w lesie: ukończenie jednej trasy przez gracza ze sprzętem odpowiadającym dostępności wydarzenia; koszyk pełny i pełna wystawa nie blokują dekoracyjnej nagrody. Pozostali gracze nie przejmują łupu.
3. Testy granic: dwie równoczesne dostawy, spam zerwania, zwykły łup ogrodowy plus Znalezisko, reset/portal/śmierć, downed i pomoc, timeout, świt podczas noszenia, przywołana noc, restart i zmiana serwera, brak zapisu, opóźnione potwierdzenie zapisu oraz teleport do punktu oddania. Sprawdzić także regresję istniejącej kradzieży ogródka i wszystkich pięciu produktów.
4. Pomiar: czas od wymaksowania do zakupów, wydane monety względem zarobionych, odsetek graczy kupujących 1./3./6. miejsce, liczba rozpoczętych i ukończonych dostaw oraz przyczyny porażek. Porównać sesje i zakupy Robuxów przed/po, bez zakładania, że sama wysoka cena poprawi powroty.
5. Rozszerzenie na pozostałe światy, a dopiero potem osobno testowany wariant przechwytywania. P1 oceniać przez wykorzystanie monet, a Znalezisko przez zainteresowanie wyprawami — sukces jednego nie dowodzi sukcesu drugiego.

Walidacja tego dokumentu: symulator uruchomiony ponownie, obliczenia progów sprawdzone, przeczytane wskazane serwisy i powiązane funkcje skali/zapisu. Nie zmieniono implementacji gry; powyższe scenariusze są warunkami przyszłego wdrożenia, nie deklaracją wykonanych testów funkcjonalnych.
