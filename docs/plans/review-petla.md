# Review gałęzi petla

Porównanie `main...origin/petla` (43 pliki), od `a26f16f` do `01d110f`. Przegląd kodu i testy Lune na kopii pobranej gałęzi. Git zablokował przełączenie, ponieważ gałąź nadpisałaby lokalny, nieśledzony `docs/plans/kuznia-szanse.md`. Scenariusze serwerowe i wydajność oceniono statycznie, bez uruchamiania Roblox Studio.

## Uwagi według ważności

### P0 — Stary serwer może skasować nowe dane, zachowując koszt zakupów

**Kod** — `src/server/DataService.luau`, `reconcile`, `load`, zapis i zamknięcie profilu na main. `src/server/Packages/ProfileStore.luau`, `SaveProfileAsync` (kontrola właściciela około linii 756).

**Scenariusz** — Gracz kupuje miejsce na nowym serwerze i wychodzi po zapisaniu profilu. Dołącza do znajomego na serwerze sprzed aktualizacji. Stary serwer legalnie otwiera kolejną sesję na tym samym kluczu. Jego `reconcile` tworzy nową tabelę ze znanych pól, a `load` przypisuje ją do `profile.Data`. Autosave lub zamknięcie sesji zapisuje tę tabelę. Następnie nowy serwer odczyta obniżone saldo oraz domyślną gablotę. Tak samo wypadają `trophies`, `weatherNight`, `stats.nightFinds` i nowe pola zimy, w tym `flakeBag` oraz zimowe liczniki. Utrata pól może także dotknąć nowych identyfikatorów przechodzących przez stare listy dozwolonych wartości.

**Znaczenie** — Ostatni slot kosztuje 51,2 mln. Blokada ProfileStore porównuje aktywną sesję i numer jej otwarcia, co zapobiega spóźnionemu zapisowi poprzedniego właściciela. W tym scenariuszu właścicielem jest już stary serwer i zapis całej tabeli jest dozwolony.

**Poprawka** — Przy wydaniu bez zmian kodu zamknąć dostęp publiczny, opublikować aktualizację, zrestartować wszystkie nieaktualne serwery bez opóźnienia i otworzyć dostęp po ich wygaszeniu. Przy wdrożeniu z równoległymi wersjami najpierw wydać i rozpropagować wersję zgodności, która odmawia zapisu profilu z nowszą wersją schematu albo zachowuje obce pola także wewnątrz znanych tabel. Sam restart rozpoczęty po publicznej publikacji ogranicza okno ryzyka, ale Roblox dopuszcza bezpośrednie dołączenia do serwerów przeznaczonych do zamknięcia, np. przez zaproszenie. [Roblox Creator Hub — wydawanie aktualizacji](https://create.roblox.com/docs/projects/update-games)

### P1 — Oddanie Znaleziska sprawdza pas współrzędnej Z zamiast polany i żywej postaci

**Kod** — `src/server/NightFindService.luau`, `step`, `pick`, `start`; `src/shared/NightFind.luau`, `delivered`; `src/server/GameService.luau`, `getRoot`.

**Scenariusz** — Gracz zrywa okaz i dochodzi do współrzędnej Z strefy 1 poza polaną, także na innej wysokości. Jeżeli przemieszcza się poniżej progu wykrywania skoku, sam warunek strefy zalicza dostawę. Jeżeli postać umrze przy granicy, a jej root pozostanie do następnej próbki, `getRoot` nadal może go zwrócić i `step` zaliczy dostawę przed `CharacterRemoving`.

**Znaczenie** — Można zaliczyć trofeum poza celem. Utrata okazu przy śmierci zależy od kolejności zdarzeń.

**Poprawka** — Sprawdzać serwerowy obszar polany w 3D oraz żywego Humanoida przy zerwaniu i oddaniu. Podpiąć `Humanoid.Died` dla postaci niosącej okaz i porównywać jej tożsamość w pętli.

### P2 — Można połączyć Znalezisko z kradzieżą

**Kod** — `src/server/GardenService.luau`, `onSteal`; `src/server/GameService.luau`, `NightFindService.start` i jego callback `busy`.

**Scenariusz** — Gracz zbiera pięć grzybów, bierze Znalezisko, a w drodze do polany uruchamia kradzież przy cudzym ogródku. `busy` blokuje podniesienie Znaleziska przy niesieniu kradzionego grzyba. `onSteal` sprawdza tylko własne `carries`, więc odwrotna kolejność pozwala nieść oba okazy.

**Znaczenie** — Jedno ograniczenie zależy od kolejności akcji. Oba systemy mogą jednocześnie założyć efekty niesienia i przeliczyć ruch postaci.

**Poprawka** — Przekazać do GardenService sprawdzenie `NightFindService.isCarrying` i użyć go przed zabraniem grzyba właścicielowi.

### P2 — Zbiory spoza zwykłego lasu odblokowują kradzież

**Kod** — `src/server/GameService.luau`, `onPick`; `src/server/GardenService.luau`, `onPick`, `stealBlock`.

**Scenariusz** — Po kradzieży gracz zbiera pięć okazów w Gnieździe Leszego, w legowisku lub w innym świecie, jeśli trafiają do zwykłego `onPick`. Każdy udany zbiór w tej ścieżce zwiększa licznik bez sprawdzenia `spot.grove`, `spot.lair`, strażnika ani świata. Po powrocie gracz spełnia warunek kolejnej kradzieży.

**Znaczenie** — Wymóg pięciu zbiorów działa, ale ma szerszy zakres niż powrót po okazy w zwykłym lesie.

**Poprawka** — Naliczaj tylko zbiory z dozwolonych miejsc na podstawie serwerowego `spot`. Jeżeli Gniazdo i leśne legowiska mają się liczyć, ustal to w regule i ogranicz świat do lasu.

### P2 — Próg teleportu może odrzucić legalny ruch i przepuścić małe skoki

**Kod** — `src/server/NightFindService.luau`, `step`, stałe `TELEPORT_STEP` i `TELEPORT_SPEED`.

**Scenariusz** — Gracz niesie okaz i zeskakuje z wysokości, dostaje silny odrzut albo po przerwie w replikacji pozycja dobiega do serwera w jednej próbce. Przy kroku 0,25 s granica wynosi około 35 studów w 3D, więc legalne przemieszczenie ponad nią gubi okaz. Przy opóźnieniu samej pętli próg rośnie wraz z `dt`, natomiast skok pozycji dostarczony w pojedynczej aktualizacji sieci może przypaść na zwykły krótki krok. Przesunięcia pod progiem przechodzą, także w serii.

**Znaczenie** — O wyniku może decydować sposób dostarczenia pozycji. Samo siedzenie nie powoduje skoku, ale szybko przeniesione siedzenie lub pojazd wpada pod tę samą regułę. Przypadków tych nie zmierzono w Studio.

**Poprawka** — Zachować jawne zrzucanie przy teleportach gry i oddzielić ocenę ruchu poziomego od spadania. Sprawdzić krótkie okno kilku próbek pod emulacją opóźnienia i z odrzutem, zanim pojedynczy skok stanie się podstawą utraty nagrody.

### P2 — Dwa niezaliczone testy tabliczek

**Kod** — `tests/economy.spec.luau:1227` i `:1233`; `src/client/MutationText.luau`, `upper`, `variantBadge`; `src/client/DisplayMushrooms.luau`, `badges`.

**Scenariusz** — Uruchomienie `lune run tests/economy.spec.luau` daje **1251 ok, 2 błędów**. Porównanie polskiego napisu tęczy zawodzi mimo identycznego wyglądu w konsoli. Przerwanie tego testu pomija przywrócenie `locale = "en"`; następny test oczekuje angielskiego i dostaje polski.

**Znaczenie** — Drugi wynik zależy od pierwszego, więc przebieg nie potwierdza samodzielnie usterki angielskiej tabliczki.

**Poprawka** — Porównać punkty kodowe oczekiwanej i rzeczywistej etykiety po usunięciu RichText oraz sprawdzić zachowanie w Studio. Izolować język każdego testu lub przywracać go także po błędzie asercji.

## Do decyzji, nie błąd

- **Ekonomia pogody.** `Economy.gardenIncome` sumuje `plantIncome`, które bierze wartość okazu, stawkę ogródka i nawóz. Wariant, suszenie (jeśli okaz je ma) i nawóz mnożą bazę, a cechy sumują nadwyżki ponad 1 w `mutationMultiplier`. Krwawy (×3) może dać niemal ×3 względem tego samego okazu bez cech, więc ×2,2 to szacunek dla składu ogródka, bez gwarancji jako pułap. Wariant i nawóz zwiększają wartość bezwzględną przyrostu, a różne wartości grządek wpływają na stosunek sum. ×1,28 po 8 h zależy od składu i liczby rozliczonych nocy. Przy wejściu `assign` liczy dochód offline przed `applyWeather`, więc zmiany podnoszą przyszłą stawkę bez wyrównania za minione godziny.
- **Ochrona po wyjściu właściciela.** `GardenService.release` zeruje ochronę i serię kradzieży, więc właściciel wracający na ten sam lub inny serwer może znowu być okradziony przed upływem poprzedniego czasu. Wyjście samego złodzieja zeruje jego zbiory, więc dalej potrzebuje pięciu. Jeśli ochrona ma podążać za właścicielem, potrzebuje zapisanego terminu w czasie Unix i jawnej reguły resetowania serii.
- **Świt i restart.** Świt usuwa okaz leżący w lesie; niosący ma dalej swoje 180 s. Restart usuwa okaz i stan niesienia. Nowa instancja w tej samej nocy może wyznaczyć kolejny spawn, jeśli zostało wystarczająco czasu według `NightFind.spawnTime`. To jest limit na instancję, także przy zmianie serwera. Dodatkowo `step` sprawdza minimum czasu przy planowaniu, więc po długim pustym okresie już zaplanowany okaz może pojawić się tuż przed świtem. Jeśli minimum ma obowiązywać przy faktycznym spawnie, przeliczyć je też w tej chwili.
- **Telefon.** `ShowcaseView.update` co 0,15 s pobiera listę markerów, mierzy dystans dla wszystkich obecnych na kliencie i projektuje tylko te w zasięgu. `DisplayMushrooms` co 0,15 s dobiera etykiety i element pod celownikiem, a `NightFindView` co 0,2 s obsługuje pojedynczy okaz i HUD. Przy 108 wystawach większym ryzykiem są tysiące części, światła i efekty w załadowanych ogródkach. Najtańszy pierwszy krok to odrzucić całe odległe ogródki przed iteracją wystaw i utrzymywać listę markerów przez sygnały dodania/usunięcia. Jeżeli profiler na telefonie nadal pokazuje koszt sceny, ograniczyć liczbę części i efektów w reprezentacji gabloty, zwłaszcza poza najbliższym ogródkiem. `glow` zmniejsza intensywność efektu, ale jego wpływ na koszt zależy od liczby utworzonych instancji.

## Sprawdzone i wygląda dobrze

- **Zakup i wystawianie.** `ShowcaseService.onAction` liczy cenę i następny slot na serwerze z flagami świata. Sprawdza pozycję względem własnej gabloty, środki i zgodność numeru slotu. Zmienia `save.n` po wydaniu monet przed odświeżeniem widoku; ponowienie tego samego żądania odpada na numerze slotu. `readExhibit` waliduje gatunek i wariant, normalizuje znacznik czasu, a `allowed` wymaga dokładnego dopasowania gatunku, wariantu i czasu do posiadanego trofeum lub odkrycia formy w atlasie. Losowy dodatni `t` nie tworzy trofeum. Sprawdzane typy pól oraz porównania zakresu zabezpieczają ścieżkę RemoteEvent przed typowymi błędnymi wartościami, w tym NaN i nieskończonością.
- **Znalezisko.** Serwer sprawdza dystans w 3D i `busy`; dwóch chętnych nie dostanie tego samego okazu, bo `pick` usuwa go przed oddaniem sterowania. `deliver` czyści `carrier` przed przyznaniem trofeum i licznika, więc kolejne próbki nie dublują nagrody. Nagroda nie dodaje monet. Wyjście gracza i usunięcie postaci kończą niesienie. Każdy graczowy `PivotTo` w GameService ma wcześniej `drop`, w tym engulf, portal, ścieżki DEV i przeniesienie przy odblokowaniu świata. Wszystkie wywołania `DelveService.api.travel` prowadzą do callbacku z `drop` przed `PivotTo`.
- **Pogoda.** `GardenWeather.rollNight` zależy od numeru globalnej nocy i UserId, a wybór grządki także od aktualnych kandydatów. Po zapisaniu `weatherNight` rejoin i zmiana serwera nie dają nowych losowań dla rozliczonej nocy. Przy pierwszym przydziale ogródka stary zapis z zerem przyjmuje ostatnią zakończoną noc bez nadrabiania historii. `range` ogranicza zaległości do 24, a `canGet` blokuje kolejną cechę z zestawu pogody na tym samym okazie.
- **Ochrona ogródka.** `stealBlock` sprawdza termin ochrony i zbiory po stronie serwera. Po udanej kradzieży `onSteal` ustawia kolejno 25/60/120 s i zeruje zbiory przed powiadomieniami. Zmiana złodzieja nie omija ochrony aktywnego ogródka. Powrót właściciela zeruje stopień przyszłej ochrony; aktualny termin dalej obowiązuje.
- **Zima i DEV.** Ścieżka gry bramkuje dekoracje przez `Winter.active`, przycisk, panel, muzykę i efekty przez stan sezonu, a ekran ładowania przez własne zgodne daty. Szron, prezenty, kalendarz i naliczanie płatków mają warunki serwerowe. Zimowa odznaka wymaga 100 płatków, a jej identyfikator w kodzie nadal wynosi 0. Widoczność odznaki w publicznej konfiguracji Roblox zależy od publikacji w Creator Hub i nie wynika z repozytorium. `devActionAllowed` wymaga Studio albo wpisu na liście akcji live, dodatkowo `onDev` sprawdza tożsamość dewelopera. Zimowy podgląd, testowe akcje gabloty i Znaleziska pozostają poza listą live. `frostBoom` jest na liście, ale sprawdza aktywny sezon. Osobne istniejące uprawnienie `resetSave` może zmienić własny zapis dewelopera, a akcje administracyjne takie jak `abuseSell` mogą wpłynąć na zarobki.
