**Plan wymaga poprawek przed kodowaniem.** Największe problemy to manipulowanie obsadą serwera, obchodzenie lokalnego cooldownu i limit 40%, który blokuje solo/duo, ale nie alty. Brak nagrody za ranking nie usuwa motywacji do oszustw — dodatkowe dynie nadal dają cukierki, nagrody ścieżki i losowania w kotle.

Przeczytałem oba dokumenty i sprawdziłem powiązaną logikę w kodzie. Poniżej rozróżniam istniejące zachowania od luk, które trzeba zamknąć w specyfikacji. Nie zmieniałem plików.

**1. Czy ranking można nabić bez grania?**

- **Kocioł: nie bezpośrednio.** Wygrana trafia tylko do `candyBag`. Przy obecnych wagach zwrot wynosi średnio `0,06 × 12 = 0,72` cukierka za próbę kosztującą 5, więc nie ma dodatniej pętli samych cukierków. Dodatkowy dopływ cukierków nadal zwiększa jednak liczbę monet i mikstur z kotła.
- **Samo logowanie nie daje punktów, ale odnawia zasoby.** [GameService.luau:876](T:/lantern/mushrooms/src/server/GameService.luau:876) losuje graczowi nowy las przy wejściu. Scenariusz: wybieram dostępne dynie, sprzedaję, wychodzę i wracam zamiast czekać na odrost. Nadal muszę zbierać, ale obchodzę czas regeneracji. Blokada sesji tego nie zatrzymuje. **Zapobieganie:** zachowywać istotny stan odrostu między sesjami albo stosować deterministyczne losowanie i zapis zebrania w danym okresie; sam stały seed nie wystarczy.
- **Robuxy dają przewagę pośrednią.** Obsługa Wysypu przyspiesza odrost całemu serwerowi, a kolejne zakupy ponownie skracają aktualne oczekiwanie: [GameService.luau:1331](T:/lantern/mushrooms/src/server/GameService.luau:1331). Produkty mają obecnie `id = 0`, więc to ryzyko po ich uruchomieniu. Nie jest to zakup punktów bez zbierania, ale grupa finansująca Wysyp może produkować więcej dyń. Trzeba jawnie zdecydować, czy ranking dopuszcza taką przewagę.
- **DEV na live może zanieczyścić ranking.** `candy50` i `candySet` zmieniają wynik, a `pumpkinBoom` daje wszystkim dodatkowe dynie. Sprawdzanie uprawnień chroni przed zwykłym graczem, ale nie przed skutkami testów administratora. **Zapobieganie:** ekonomiczne akcje DEV tylko w odseparowanym środowisku testowym. Wykluczenie samego administratora nie wystarczy, gdy bonus dostają inni gracze.

**[P1] Brakuje zasad zamknięcia rankingu** — [plan:17](T:/lantern/mushrooms/docs/plans/halloween-etap3.md:17). Sprzedaż sekundę przed końcem może nie trafić do zapisu wykonywanego co minutę. Z kolei opóźniony zapis ze starej sesji może nadpisać nowszy wynik; blokada profilu nie obejmuje automatycznie osobnego rankingu.

**Poprawka:** wynik pochodzi z trwałego profilu, zamknięcie zdobywania punktów następuje dokładnie przy `endsAt`, a publikowanie zaległych, poprawnych wyników ma osobną fazę finalizacji. Aktualizacje muszą być odporne na starsze zapisy. Monotoniczne maksimum pomaga tylko dla poprawnych wyników — potrzebna jest też możliwość usunięcia wyników testowych/oszukańczych.

**2. Czy cel da się farmić altami i na VIP? Tak.**

**[P1] Tani start, później pełny serwer** — [plan:26](T:/lantern/mushrooms/docs/plans/halloween-etap3.md:26).

Scenariusz: jedno konto uruchamia cel za 300. Potem dołączają pozostali. Trzy konta wpłacają po 100, wszyscy korzystają z nocy. Przy starcie z sześcioma graczami trzeba byłoby zebrać 900. Grupie opłaca się sterować wejściami przy każdym nowym celu.

**Poprawka:** najprościej usunąć zależność kosztu od chwilowej obsady. Jeśli skalowanie zostaje, potrzebna jest jawna reguła późniejszych uczestników i beneficjentów. Samo przeliczanie progu na żywo stworzy inne nadużycie: wychodzenie w celu obniżenia kosztu.

**[P1] Limit 40% jest limitem kont, nie osób** — [plan:27](T:/lantern/mushrooms/docs/plans/halloween-etap3.md:27).

Przy celu 300 jedno konto wniesie najwyżej 120, dwa 240 — solo i duo **nigdy nie ukończą celu**. Jedna osoba z dwoma altami już może. Alty muszą zdobyć dynie, więc nie jest to darmowa nagroda za logowanie, ale zabezpieczenie nie osiąga deklarowanego celu.

Dodatkowo, jeśli wkład będzie przypisany do obiektu `Player` i usuwany przy wyjściu, jedno konto wpłaci 120, wróci, wpłaci następne 120 i dokończy cel.

**Poprawka:** wkład według `UserId`, zachowany do końca celu mimo reconnectu. Limit 40% zastąpić mechanizmem tempa nagród, który nie wymaga trzech kont.

**[P1] Lokalny cooldown nie ogranicza farmienia między serwerami** — [plan:24](T:/lantern/mushrooms/docs/plans/halloween-etap3.md:24).

Grupa przygotowuje cele na kilku serwerach, uruchamia je kolejno i przenosi główne konta na aktywną noc. Nie musi grać tym samym kontem równocześnie. Restart instancji dodatkowo usuwa cooldown, jeżeli jest tylko w pamięci; znaczenie ma nieopisana reguła pierwszej nagrody.

**Poprawka:** jeśli limit ma chronić ekonomię gracza, musi obowiązywać między serwerami. Możliwe rozwiązania to wspólne okna nagród albo zapisany budżet korzystania z bonusu na konto, egzekwowany przy generowaniu zasobów. Sama lokalna przerwa 30 minut tego nie zapewnia.

**3. Czy powstaje pętla „dynie → noc → więcej dyń”? Tak, choć nie znamy jeszcze jej wydajności.**

Według [Config.luau:356](T:/lantern/mushrooms/src/shared/Config.luau:356) i [Config.luau:592](T:/lantern/mushrooms/src/shared/Config.luau:592):

| Parametr | Zwykłe warunki / Noc Dziadów |
|---|---|
| Szansa dyni | 6% / 18% |
| Czas odrostu względem spokojnej nocy | 100% / 75% |
| Szczęście Nocy Dziadów | ×1,8 |
| Naturalna Noc Dziadów | 18 minut na godzinę |

Przy ograniczeniu wyłącznie odrostem daje to około **4× więcej dyń niż spokojna noc**: `3 / 0,75`. To nie prognoza rzeczywistego zarobku — dojście, zbieranie i sprzedaż ograniczają wydajność.

Dwie dodatkowe noce po 10 minut mogą zwiększyć udział Nocy Dziadów z 18 do nawet 38 minut na godzinę, jeśli nie nakładają się na naturalną. Więcej cukierków oznacza też więcej losowań kotła i zysków poza eventem.

**Poprawka przed wdrożeniem:**

- Ustalić wspólny budżet czasu bonusowego oraz zasady nakładania z naturalną nocą.
- Dopuścić najwyżej jedną oczekującą nagrodę; bez kolejki wielu pełnych pasków.
- Określić, czy nadwyżka sprzedaży przechodzi do następnego celu.
- Jeśli bonusowe dynie mają nie finansować kolejnego celu, oznaczać ich pochodzenie przy wygenerowaniu. Wyłączenie naliczania tylko podczas nocy nie wystarczy: gracz przechowa koszyk i sprzeda po niej.
- Zmierzyć cukierki/minutę i monety/minutę dla solo, duo, grupy na bagnach oraz grupy z Wysypem. Obecne czasy progresji nie dowodzą bezpieczeństwa nowej pętli.

**4. Co po wyjściu graczy?**

**[P2] Cel może utknąć.** Sześciu graczy ustawia próg 900, pięciu wychodzi. Pozostały gracz nie może przekroczyć 360 własnego wkładu. W drugą stronę cel wystartowany przy małej obsadzie pozostaje zbyt tani dla dużej grupy.

Wkład wychodzących powinien zostać — odejmowanie karałoby innych i pozwalało sabotować pasek. Ich wykorzystany limit też musi zostać. Nie należy obniżać progu bezpośrednio po wyjściach.

Plan powinien określić również utratę postępu przy zamknięciu serwera. Bez zapisu gracz może stracić prawie ukończony cel po restarcie; interfejs musi jasno mówić, że to postęp bieżącej instancji.

**5. Czy klient albo spam RemoteEventów może to wykorzystać?**

Plan nie wymaga zaufania klientowi, ale potrzebuje konkretnych warunków implementacji:

- Cel aktualizuje wyłącznie serwer po skutecznej sprzedaży rzeczywistych przedmiotów. Nie przez nowy remote „dodaj wkład”.
- Źródło cukierków musi być jawne. **Nie rozpoznawać sprzedaży po `MSG_CANDY_SOLD`: akcja DEV `candy50` używa tego samego klucza** — [ProgressService.luau:473](T:/lantern/mushrooms/src/server/ProgressService.luau:473).
- Przyznawany wkład to minimum z wartości sprzedaży, pozostałego limitu konta i brakującego postępu. Limit dotyczy sumy, nie pojedynczego żądania.
- Usunięcie sprzedanych przedmiotów i naliczenie wkładu musi być jedną operacją bez oddawania sterowania pomiędzy etapami.
- Dwie sprzedaże domykające próg muszą uruchomić dokładnie jedną nagrodę. Najpierw zmiana stanu celu, potem ogłoszenia i efekty.
- Zakończenie eventu musi blokować także oczekującą nagrodę.

Szczególnie warto przetestować: powtórzony pakiet sprzedaży, sprzedaż po jednej sztuce, reconnect po osiągnięciu limitu, jednoczesne domknięcie celu oraz przekroczenie `endsAt` podczas oczekiwania.

**6. Czego brakuje, żeby było fajne?**

- Możliwości ukończenia celu przez solo i duo.
- Widocznego osobistego wkładu i wyjaśnienia, dlaczego kolejna sprzedaż nie poruszyła paska.
- Komunikatu „Cel ukończony — noc za 07:32”, zamiast pozornie zablokowanego paska.
- Gwarancji, że nagroda nie przepadnie przez nałożenie na naturalną noc.
- Małych celebracji postępu bez dodatkowych wypłat ekonomicznych.
- Jasnych zasad rankingu: VIP, płatne bonusy, testy DEV i moment ostatecznego zamknięcia wyników.

**Do poprawionego planu przede wszystkim wpisałbym:** cel osiągalny przy dowolnej liczbie graczy, koszt odporny na wejścia/wyjścia, ochronę przed rotacją serwerów, jednoznaczny cykl życia oczekującej nagrody oraz odseparowanie DEV od ekonomii live.

---

## Ponowne review — wersja 2, 30.10.2026

**Werdykt: główna zmiana jest dobra, ale plan nadal wymaga doprecyzowania przed kodowaniem.** Zweryfikowałem wersję z nagłówkiem „wersja 2” i tabelą „Uwagi z review → decyzje”. Poniższa ocena dotyczy specyfikacji, nie potwierdza poprawności przyszłej implementacji. Sprawdziłem też istniejące ścieżki zapisu, odrostu i akcji DEV.

### Co zamknięto, a co pozostaje otwarte

| Poprzednia uwaga | Ocena wersji 2 |
|---|---|
| Tani start i manipulowanie obsadą | Zamknięta: stały próg 200 nie zależy od wejść i wyjść. |
| Limit 40% blokujący solo/duo | Zamknięta: usunięto limit wkładu. |
| Cel utykający po wyjściu graczy | Zamknięta projektowo: pozostali mogą sami dokończyć cel. |
| Reconnect kasujący wkład | Zamknięta projektowo: klucz UserId, wkład pozostaje do końca celu. |
| Rotacja serwerów omijająca cooldown | Zamknięta dla nagród jednego konta przy poprawnym, trwałym zapisie limitu; nie jest to limit na osobę ani grupę altów. |
| Dynie → dodatkowa noc → więcej dyń | Bezpośrednia pętla zamknięta: mikstura nie zwiększa szansy dyni ani nie uruchamia nocy. Większe przychody z wariantów nadal wymagają oceny balansu. |
| Restart kasujący pasek | Świadomie zaakceptowane, z komunikatem dla gracza. |
| Źródło cukierków po kluczu komunikatu | Zamknięta projektowo przez jawne source, nadawane wyłącznie przez serwer. |
| Płatny Wysyp | Świadomie zaakceptowana przewaga, nie traktuję jej dalej jako blokady. |
| DEV na live | Częściowo: deklaracja jest dobra, ale zakres blokad i izolację Studio trzeba uściślić. |
| Zamknięcie rankingu i stare zapisy | Maksimum chroni przed obniżeniem wyniku, ale finalizacja i korekty nadal mają dziury. |
| Relog odnawiający las | Niezamknięta: losowy odrost i sam leftAt nie zachowują stanu zasobów. |
| Czytelność i celebracja | Poprawione: osobisty wkład, limit nagród, natychmiastowy efekt kosmetyczny. |

### 1. [P1] Losowy odrost po relogu nadal można wykorzystywać

**Miejsce:** sekcja 4 planu, `data.leftAt` i losowy czas odrostu.

Scenariusz: gracz wybiera wartościowe grzyby, wraca szybko i otrzymuje nowe losowanie całego lasu oraz nowych czasów gotowości. Jeśli czas jest losowany od zera do pełnego odrostu, część miejsc będzie dostępna znacznie wcześniej niż normalnie po zebraniu. Kolejny relog ponownie losuje zarówno zasoby, jak i oczekiwanie. Plan nie określa dolnej granicy ani zachowania wcześniejszych terminów, więc nie gwarantuje braku przewagi.

`Config.RespawnSeconds` wynosi 90 s, ale istniejąca ścieżka zbierania ma również osobne czasy strażników. Ogólne „po 90 sekundach wszystko gotowe” nie może skracać ich odrostu. Sam zapis czasu wyjścia nie obejmuje też awarii procesu: wtedy pozostaje stary `leftAt` i wejście może zostać uznane za powrót po długiej przerwie.

**Poprawka:** zachować po stronie serwera terminy gotowości zebranych zasobów oraz stan losowania albo identyfikatory ich generacji. Reconnect nie może przyspieszać istniejącego terminu ani ponownie losować niezebranych zasobów. Dla prostszego rozwiązania potrzebny jest konserwatywny, trwały mechanizm blokady odnowienia, obejmujący awarie i dłuższe cooldowny; losowe opóźnienie przy każdym wejściu nie jest takim mechanizmem. Nie wystarczy samo stałe ziarno bez informacji, co już zebrano.

**Test:** porównać maksymalny dostęp do zasobów przy grze ciągłej, wielokrotnych relogach oraz awarii przed zapisem wyjścia; powrót nie może tworzyć dodatkowych losowań ani skracać terminów.

### 2. [P1] Jednorazowy zapis przy endsAt nie zapewnia końcowego rankingu

**Miejsce:** sekcja 1, „raz przy endsAt”, potem „bez nowych zapisów”.

Scenariusz: gracz sprzedaje dynię tuż przed końcem. Ostatni zapis rankingu zawodzi albo serwer kończy pracę przed publikacją. Profil zachował poprawny wynik, lecz po `endsAt` nie wolno już go wysłać. Gracz bezpowrotnie traci końcowe punkty na tablicy. Tick serwera może również zauważyć koniec dopiero po dokładnej sekundzie granicznej.

**Poprawka:** rozdzielić zamknięcie zdobywania punktów od finalizacji publikacji. Po `endsAt` można ponawiać wysłanie trwałego wyniku zdobytego przed końcem, bez dopisywania nowych cukierków. Dopiero po zdefiniowanej fazie finalizacji ogłaszać wynik ostateczny. Ranking powinien publikować zatwierdzony stan profilu, żeby maksimum nie utrwaliło wyniku z niezapisanej sesji po awarii.

W planie jest też nieścisłość: obecne `ProgressService.addCandy` samo nie sprawdza `Halloween.active`; sprawdzają to wywołania sprzedaży i zadań. Warto dodać centralny warunek czasu do funkcji, a nie opierać obietnicy „tylko do endsAt” na każdym obecnym i przyszłym wywołującym.

### 3. [P1] Usunięty wynik wróci przy następnej synchronizacji

**Miejsce:** sekcja 1, maksimum w OrderedDataStore i akcja „usuń wynik gracza”.

Scenariusz: administrator usuwa wpis testera lub oszusta, ale `stats.candy` w profilu nadal wynosi 100000. Zapis przy wyjściu albo kolejna synchronizacja tworzy ten sam wpis ponownie. Samo obniżenie licznika profilu też nie wystarczy, dopóki w rankingu pozostaje większa wartość chroniona przez maksimum. Opóźnione żądanie starej sesji może odtworzyć usunięty wynik.

**Poprawka:** określić trwałe wykluczenie konta z tej edycji rankingu albo wersjonowaną korektę wyniku, respektowaną przez wszystkie ścieżki publikacji. Moderacja musi obejmować źródło danych i ochronę przed starymi zapisami; samo usunięcie klucza nie zamyka uwagi. Polityka korekt powinna działać także po zamrożeniu rankingu.

### 4. [P2] Próg 10 pozwala rozdzielić ten sam cel na wiele wypłat

**Miejsce:** sekcja 3, 200 cukierków na cel i 10 cukierków do nagrody.

Scenariusz: zamiast jednego konta wpłacającego 200, grupa rozdziela wkład na konta wpłacające po 10. Jeden cel może wtedy wypłacić do 20 mikstur po 10 minut, o ile pojemność serwera pozwala tylu beneficjentom być obecnymi. Trzy cele za 600 cukierków dają takim 20 kontom łącznie 600 minut bonusu, podczas gdy samotny gracz dostaje za te same 600 cukierków tylko 30 minut. Przy mniejszym serwerze skala jest odpowiednio mniejsza.

To nie duplikacja przedmiotów ani dowód zysku na głównym koncie: każde konto musi zdobyć własny wkład, a transfer zysków zależy od innych mechanik. Jest to jednak realne mnożenie łącznej wartości nagrody przez podział pracy. Konta z wykorzystanym limitem mogą też nadal finansować cele dla nowych kont. Limit 3 na konto tego nie zabrania.

**Decyzja potrzebna w planie:** czy pełna nagroda dla każdej osoby z minimalnym wkładem jest zamierzoną premią za współpracę? Jeśli tak, zaakceptować ją jawnie i mierzyć łączną emisję bonusu. Jeśli nie, powiązać czas mikstury z wkładem, np. stałą liczbą sekund za zaliczony cukierek, z limitem 10 minut na cel i 30 minut dziennie. Taki wariant ma stały budżet nagrody na cel niezależny od rozdzielenia wkładu. Nie dodawałbym ograniczenia do VIP — publiczna grupa może zrobić to samo.

### 5. [P2] Nadwyżka wymaga jednoznacznego podziału wkładu i wypłat

**Miejsce:** sekcja 3, nadwyżka przechodzi do następnego celu.

Scenariusz: pasek ma 195/200, a konto bez wcześniejszego wkładu sprzedaje dynie za 20 cukierków. Do kończonego celu należy 5, do nowego 15. Przypisanie całych 20 do starego celu da niezasłużoną miksturę za faktyczne 5. Jeśli następnie całe 20 zostanie przypisane także do nowego, powstanie podwójny wkład.

**Poprawka:** najpierw rozdzielić sprzedaż między konkretne identyfikatory celów, a potem oceniać próg 10 osobno w każdym z nich. Przed resetem zachować snapshot uczestników ukończonego celu. Obsłużyć też sprzedaż przekraczającą więcej niż jeden próg, jeśli pozwala na to koszyk. Dwie poprawne sprzedaże mogą legalnie domknąć dwa różne cele — wymaganie powinno brzmieć „każdy cel wypłacany najwyżej raz”, nie bezwarunkowo „dwie sprzedaże = jedno domknięcie”.

Stan celu, wykorzystanie limitu dziennego i przyznanie czasu bonusu muszą zostać rozstrzygnięte bez yieldów przed efektami i komunikatami. Jeden wątek serwera nie wystarcza, jeśli obsługa oddaje sterowanie podczas wywołań. Próg 200 dotyczy wkładu; pełna prawidłowa sprzedaż nadal daje graczowi wszystkie należne cukierki do kieszeni i rankingu.

### 6. [P2] Limit w profilu potrzebuje reguł błędów, czasu i sposobu wykorzystania

**Miejsce:** sekcja 3, `eventGoals = { day, count }` i „użycie” nagrody.

Istniejący `DataService.load` potrafi zwrócić dane domyślne z `canSave = false`. W takiej sesji limit jest tylko pozornie trwały. Takich sesji nie należy dopuszczać do wypłat i oficjalnego rankingu; najprościej także do wkładu w cel. Wypłata powinna wymagać aktywnego profilu, a licznik i bonus powinny być częścią tego samego stanu zapisu. Awaria nie może zachować korzyści przy utracie informacji o wykorzystaniu limitu.

Trzeba dopisać: dzień według zegara serwera, np. UTC; wartości domyślne i walidację nowych pól; reset tylko po przejściu do nowego dnia; regułę dla osób wychodzących podczas wypłaty. Ponieważ nagroda jest dla obecnych, listę uprawnionych najlepiej ustalić w chwili domknięcia.

„3 nagrody na dzień” nie oznacza maksymalnie 30 minut w każdym ruchomym okresie 24 godzin. Gracz może zdobyć trzy tuż przed północą i trzy po północy. To normalna konsekwencja limitu kalendarzowego, nie obejście — należy ją zaakceptować albo wybrać okno kroczące. Jeśli bonus dodaje się do istniejącego `luckUntil`, limit dotyczy przyznanego czasu, nie czasu faktycznego działania danego dnia. Jeżeli „mikstura” ma być przedmiotem przechowywanym do późniejszego użycia, limit samych przyznań nie ograniczy późniejszego zużycia zapasów. Plan powinien jasno wybrać automatyczne wydłużenie czasu albo przedmiot i moment egzekwowania limitu.

### 7. [P2] DEV: potrzebna pełna allowlista live i izolacja testów

**Miejsce:** sekcja 2, lista sześciu akcji Studio-only i deklaracja „w live zostają teleporty i podgląd”.

Jeśli to ostatnie zdanie oznacza zamkniętą allowlistę, blokuje większość dawnych ścieżek ekonomicznych. Jeśli implementacja zablokuje wyłącznie sześć wymienionych akcji, zostaną m.in. `questsNew` + `questsDone` (powtarzane cukierki z zadań), monety, maksymalne ulepszenia i sterowanie cyklem. Należy zapisać jednoznacznie: wszystkie pozostałe akcje zmieniające ekonomię lub postęp są Studio-only, także osobne komendy czatu.

Studio-only nie oznacza automatycznie danych testowych. Jeżeli Studio ma dostęp do produkcyjnych magazynów, testowe `candySet` może zostać zapisane w prawdziwym profilu i później opublikowane przez live. Potrzebne są oddzielne magazyny profili i rankingów albo brak dostępu testów do produkcyjnego zapisu. Teleport DEV na live również przyspiesza zbieranie; jeśli pozostaje, trzeba zaakceptować tę przewagę lub wykluczyć konto testowe z rankingu.

### Minimalne uzupełnienia testów wersji 2

- Relog wielokrotny, crash bez zapisu `leftAt`, odrost strażników oraz zachowanie istniejących losowań.
- Zapis rankingu zawodzący przy `endsAt`, publikacja zaległego trwałego wyniku i stary zapis po korekcie/usunięciu.
- Pasek 195 + sprzedaż 20: wkład 5/15 i brak nagrody za pierwszy cel dla nowego uczestnika.
- Jedna duża sprzedaż przez kilka progów i dwie kolejne wypłaty przy liczniku dziennym równym 2: łącznie tylko jedna nowa nagroda dla konta.
- Przejście serwer A → B z wykorzystanym limitem, profil niewczytany, utrata aktywnej sesji oraz granica dnia.
- Próba użycia wszystkich ekonomicznych akcji DEV na live i sprawdzenie izolacji magazynów Studio.
- Porównanie emisji mikstur przy 200 cukierkach od jednej osoby i przy rozdzieleniu na wkłady po 10.

**Rekomendacja:** zachować stały próg, brak limitu wkładu i zamianę nocy na ograniczony bonus. Przed kodem poprawić odrost po relogu oraz finalizację/korekty rankingu, jednoznacznie opisać podział nadwyżki i wypłaty, a mnożenie nagród przez grupę świadomie zaakceptować albo ograniczyć budżetem czasu na cel.
