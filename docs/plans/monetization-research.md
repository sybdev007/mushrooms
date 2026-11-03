# Monetyzuj wygląd, zanim podwoisz dochód graczy

**Rekomendacja: zachować obecne produkty, przetestować kosmetyczny VIP za 249 R$ i małe nagrody monetowe; nie wdrażać stałego x2, produktywnych grzybów za Robux ani obecnego x2 za monety.** Zarodniki odłożyć: dla obecnego katalogu dodają głównie drugi cennik, rabaty i pozostałe salda. Stałe x2 istotnie skraca już krótką progresję, a sprzedawany gatunek jest także trwałym źródłem dochodu i celem kradzieży. „x2 za monety” nie działa jako sensowny zlew, ponieważ obecny produkt podwaja konkretną wypłatę ze skrzyni. Poniższe ceny nowych ofert są hipotezami do pilotażu, bez danych potwierdzających optymalną konwersję. Mikstura szczęścia i Wysyp pozostają płatne; nagrody i kody nie dają ich ani waluty wymienialnej na nie.

Stan badania: **3 listopada 2026**. Przeczytano `docs/HANDOFF.md` i `docs/REVIEW.md`; analiza dotyczy GitHuba `sybdev007/mushrooms`, commit `7da90c977b50f226fd8a6b9fbddd56b6de02812d`. Nie znaleziono w repo plików makiet 02–04, więc oceniono pięć propozycji opisanych w zleceniu. Zakres pracy: dokument badawczy, bez zmian kodu, commitów i publikacji.

## Ekonomia ma już szybką progresję i płatne przyspieszenia

Uruchomiono **`lune run tools/economy_sim.luau`**. Wynik bazowy: jaskinia po **56 min**, bagna po **113 min**, maksymalizacja **70 modelowanych poziomów ulepszeń dochodowych po 221 min**; łącznie zarobione **10 894 393 monety**, końcowy dochód **127 844 monet/min**. To model wydajnej gry, nie mediana graczy. Nie symuluje śmierci, kradzieży, dochodu offline, płatnych produktów ani rzeczywistego napełniania i limitowania skrzyni. Ogród jest idealizowany, a wybór stref i zakupów zoptymalizowany. „Maksymalizacja” nie obejmuje wszystkich kategorii, m.in. `chest`, `lock` i `lantern`; nie należy nazywać 221 minut końcem całej gry. ([Symulator](https://github.com/sybdev007/mushrooms/blob/7da90c977b50f226fd8a6b9fbddd56b6de02812d/tools/economy_sim.luau#L1))

W całym raporcie **S = `Progress.rewardScale`, czyli kwota monet**, a nie mnożnik dochodu. Wartości wynikają z 10-krotności bazowej wartości najdroższego zwykłego gatunku świata. Dla porównania symulator podaje osobne reprezentatywne stany dochodowe; nie są to dochody każdego gracza w danym świecie. ([Progress](https://github.com/sybdev007/mushrooms/blob/7da90c977b50f226fd8a6b9fbddd56b6de02812d/src/shared/Progress.luau#L307))

| Wielkość | Las | Jaskinia | Bagna |
|---|---:|---:|---:|
| 1 S, w monetach | 1 600 | 32 000 | 160 000 |
| Dochód referencyjny symulatora, monet/min | 366 | 16 939 | 68 145 |
| Jedno zadanie: 1 S | 1 600 | 32 000 | 160 000 |
| Proponowane 0,1 S | 160 | 3 200 | 16 000 |
| Proponowane 0,25 S | 400 | 8 000 | 40 000 |

Nie istnieje jeden kurs Robux → monety dla całego katalogu. **Rescue 59 R$** odzyskuje zagrożony koszyk; **oil 15 R$** tankuje latarnię; **harvest 29 R$** dopisuje do skrzyni **30 minut aktualnego dochodu ogrodu**. **Luck 49 R$** daje **15 min x2 szczęścia**, a **Wysyp/boom 99 R$** daje serwerowi **10 min szybszych odrostów i x1,5 szczęścia**. Ceny tych pięciu produktów przyjęto ze zlecenia i Handoff; kod zawiera ich identyfikatory, ale nie potwierdza bieżącej ceny każdego konta w sklepie Roblox. ([Przyznawanie produktów](https://github.com/sybdev007/mushrooms/blob/7da90c977b50f226fd8a6b9fbddd56b6de02812d/src/server/GameService.luau#L1457), [parametry](https://github.com/sybdev007/mushrooms/blob/7da90c977b50f226fd8a6b9fbddd56b6de02812d/src/shared/Config.luau#L812))

**Obecne x2 podwaja jeden odbiór skrzyni, nie dochód przez określony czas.** Kod ma cztery progi **15/40/120/240 minut** zaksięgowanego dochodu i ceny **19/39/79/149 R$**. Wszystkie cztery identyfikatory wynoszą 0, więc to jeszcze nie pełna aktywna oferta live. Handoff wymienia tylko trzy warianty i jest tu niepełny. Bonus x2 trafia bezpośrednio do portfela, poza limitem skrzyni. ([Config](https://github.com/sybdev007/mushrooms/blob/7da90c977b50f226fd8a6b9fbddd56b6de02812d/src/shared/Config.luau#L552), [wypłata](https://github.com/sybdev007/mushrooms/blob/7da90c977b50f226fd8a6b9fbddd56b6de02812d/src/server/GardenService.luau#L979))

Ranking **`richest` mierzy aktualne saldo**, więc każda nagroda monetowa podnosi wynik, a zakup go obniża. `rare` mierzy najlepsze znalezisko tygodnia, `thieves` liczbę doniesionych kradzieży tygodnia, `candy` zebrane cukierki Halloween. Płatna przewaga ekonomiczna nie musi bezpośrednio dopisywać punktów do pozostałych rankingów, aby pomagać: szybsze ulepszenia ułatwiają wyprawy i ucieczkę z łupem. ([LeaderboardService](https://github.com/sybdev007/mushrooms/blob/7da90c977b50f226fd8a6b9fbddd56b6de02812d/src/server/LeaderboardService.luau#L62))

## VIP za 499 R$ kupuje zbyt duży stały przyrost monet

**Ocena: odrzucić stałe x2; zachować kierunek kosmetyczny.** Przy niezmienionym stanie ulepszeń x2 całego dochodu dodaje tyle monet, ile zarabiałby gracz bez niego. Dla stanów referencyjnych oznacza to dodatkowe **21 960 / 1 016 340 / 4 088 700 monet na godzinę** w lesie/jaskini/bagnach. To rachunek `dochód × 60`, nie model godziny rzeczywistej gry. Jeśli x2 obejmie tylko sprzedaż koszyka albo tylko ogród, wynik będzie inny; zakres trzeba ustalić przed implementacją.

Dodatkowo wykonano analizę wrażliwości na kopii symulatora poza repo: podwojono łączny modelowany dochód aktywny i ogrodowy oraz dochód używany do wyboru ulepszeń. Jaskinia przesunęła się **56 → 37 min**, bagna **113 → 70 min**, a modelowane ulepszenia **221 → 122 min**. To skrócenie o około **34%, 38% i 45%**, nie obietnica wyniku VIP w grze. Zakupy i wcześniejsze wejście do bogatszych stref sprawiają, że nie wystarczy mechanicznie podzielić wszystkich czasów przez dwa. Skrypt źródłowy nie został zmieniony.

Wpływ na `richest` jest bezpośredni i trwały; przewaga w `rare` i `thieves` pośrednia przez szybsze ulepszenia. VIP nie powinien mnożyć nagród zadań, kodów, cukierków ani wartości samego grzyba. Pokój VIP ma **0 monet wpływu tylko wtedy**, gdy jest miejscem społecznym bez skrótów, schronienia przed pościgiem, oddawania łupu, dodatkowych grządek, specjalnego sklepu lub ochrony ogródka. Złota nazwa sama w sobie ma 0 wpływu ekonomicznego.

Kanibalizacja byłaby największa wobec **harvest 29 i x2 19–149**, bo nadwyżka monet zmniejsza potrzebę kupowania kolejnych wypłat. **Rescue 59 i oil 15** tracą część znaczenia po szybszym zakupie ulepszeń; **luck 49 i boom 99** nadal pomagają w znajdowaniu okazów, ale ekonomiczny etap, w którym są potrzebne, staje się krótszy. Gdy VIP podwaja też harvest lub bonus x2, podnosi ich wartość, lecz zwiększa emisję: odpowiednie połączenie dwóch mnożników mogłoby dać 4-krotność pierwotnej wypłaty. To ryzyko projektowe, nie istniejąca reguła kodu. Bez telemetrii nie ma podstaw do procentowej prognozy kanibalizacji.

Najbliższa analogia to **Steal a Brainrot**, którego oficjalny opis łączy dochód i kradzież. Radio Times opisał 19 stycznia 2026 VIP za **499 R$ z +50% pieniędzy**, tagiem i dodatkowymi 10 sekundami zamknięcia bazy. To oferta historyczna ze źródła wtórnego, nie dowód dzisiejszej ceny. Tracker Rolimon’s pokazuje **375 R$**; przyczyna różnicy nie została ustalona. Sam mnożnik x2 daje dwa razy większy dodatkowy przyrost niż +50% przy tej samej bazie, ale gospodarki obu gier są różne. ([Roblox](https://www.roblox.com/games/109983668079237/Steal-a-Brainrot), [Radio Times](https://www.radiotimes.com/technology/gaming/steal-a-brainrot-vip-gamepass-explained/), [Rolimon’s](https://www.rolimons.com/gamepass/1229510262))

**Propozycja pilotażu: gamepass 249 R$**, złota nazwa, tag VIP, społeczny pokój i wygląd latarni, bez statystyk. Efekt: **0 dodatkowych monet, 0 punktów rankingowych, 0 ochrony ogródka**. Cena 249 jest hipotezą, a nie ceną wyprowadzoną z danych konkurencji. Nie ma obecnie dowodu popytu na same kosmetyki za 499 R$. Jednorazowy pass jest właściwą formą stałego przywileju. ([Roblox: Passes](https://create.roblox.com/docs/production/monetization/passes))

## Zarodniki zmieniają płatność, lecz nie zmniejszają pay-to-win

**Ocena: odłożyć, pozostawić bezpośrednie zakupy.** Paczki 100/400/1500 niczego nie określają bez ceny Robux i cennika efektów. Dla paczki `P` Zarodników za `R` Robux i produktu kosztującego `Z` Zarodników uśredniona cena efektu wynosi **`Z × R / P` R$**. Przykładowo paczki 100/400/1500 za 100/350/1200 R$ obniżyłyby efektywną cenę luck za 49 Z do **49 / 42,875 / 39,2 R$**. Największa paczka daje w tym przykładzie 20% rabatu całemu katalogowi. To ilustracja ryzyka, nie rekomendowany cennik.

Samo kupienie paczki emituje **0 monet**. Monety lub przewaga pojawiają się przy wydaniu Z na harvest, x2 albo efekty zwiększające skuteczność. Wtedy wpływ na `richest`, pozostałe rankingi i kradzież jest taki jak dla tego samego produktu kupionego bezpośrednio. P2W pozostaje; trudniej tylko porównać cenę. Waluta bez transferów sama nie jest łupem z ogródka. Jeżeli później kupuje produktywne rośliny, dziedziczy ryzyko transferu ich wartości przez kradzież.

Kanibalizacja dotyczy **wszystkich** SKU: rescue 59, boom 99, oil 15, harvest 29, luck 49 i x2 19–149. Paczki z rabatem obniżają ich efektywną cenę; paczki bez rabatu wypierają część zakupów bezpośrednich bez dodania nowej funkcji. Przy minimalnej paczce 100 Z zakup oil za 15 Z wymaga wydania 100 R$ w modelu 1:1 i zostawia 85 Z. Nie wolno utożsamiać tego z neutralnym doświadczeniem zakupu za 15 R$.

Jeżeli waluta stanie się później potrzebna z innego powodu, **punkt odniesienia bez rabatów** to 100/400/1500 Z za 100/400/1500 R$, a ceny efektów identyczne liczbowo z katalogiem Robux. To wyłącznie wariant porównawczy, nie plan wdrożenia teraz. Nie rozdawać Z w kodach, za logowanie ani za monety, jeśli można za nie kupić luck lub Wysyp. Nie wprowadzać wymiany i transferów między kontami. Paczki to powtarzalne developer products, a wydanie portfela Z wymaga wewnętrznej transakcji serwera z tymi samymi ograniczeniami efektu; przyznanie paczki musi wynikać z potwierdzonego `ProcessReceipt`. ([Roblox: Developer products](https://create.roblox.com/docs/production/monetization/developer-products))

Nie potwierdzono bieżącego pierwotnego cennika Tickets w Bee Swarm, więc nie użyto jego kwot do ustalania cen. Dodatkowo Roblox pozwala na ceny regionalne **30–100% bazowej**. Przy dwóch drogach zakupu trzeba porównywać efektywne ceny wszystkich paczek i produktów dla faktycznej ceny gracza, a nie tylko nominalnego kursu. Nie sprawdzono ustawień Managed Pricing tej gry. ([Roblox: Regional pricing](https://create.roblox.com/docs/production/monetization/regional-pricing))

## Handlarz co 30 minut sprzedawałby trwały dochód i atrakcyjny łup

**Ocena: nie sprzedawać za Robux produktywnych gatunków w obecnej ekonomii.** Roślina o wartości `V` daje **`0,04 × V × F` monet/min**, gdzie mnożnik nawozu `F` rośnie od 1 do 3. Sprzedawany okaz nie jest więc tylko jednorazowym pakietem monet równym cenie sprzedaży. Poniższe liczby dotyczą jednego najdroższego zwykłego gatunku danego świata, bez mutacji. ([Economy](https://github.com/sybdev007/mushrooms/blob/7da90c977b50f226fd8a6b9fbddd56b6de02812d/src/shared/Economy.luau#L468), [gatunki i ogród](https://github.com/sybdev007/mushrooms/blob/7da90c977b50f226fd8a6b9fbddd56b6de02812d/src/shared/Config.luau#L387))

| Jeden okaz | Las | Jaskinia | Bagna |
|---|---:|---:|---:|
| Wartość sprzedaży V, monety | 160 | 3 200 | 16 000 |
| Dochód/min przy F=1 | 6,4 | 128 | 640 |
| Dochód/min przy F=3 | 19,2 | 384 | 1 920 |
| Dochód za 6 h offline, F=1, odpowiednia skrzynia | 1 152 | 23 040 | 115 200 |
| Dochód za 6 h offline, F=3, odpowiednia skrzynia | 3 456 | 69 120 | 345 600 |

Sześć godzin offline odpowiada tutaj **180 minutom pełnego dochodu**: 120 minut 100% + 240 minut 25%. Bazowy limit skrzyni ogranicza wynik do 120 minut, czyli przy F=1 do **768 / 15 360 / 76 800 monet**. Lepsza skrzynia pozwala uzyskać wartości z tabeli. Restock co 30 min daje **48 okien na dobę**; nie ogranicza trwałej emisji z wcześniej kupionych roślin. Limit grządek ogranicza równoczesną uprawę, ale nie rozwiązuje zamiany na coraz droższe okazy.

Kradzież wybiera najdroższy posadzony okaz. Po doniesieniu przenosi go złodziejowi do ogródka lub koszyka, a przy braku miejsca może wypłacić wartość w monetach; udana kradzież dodaje 1 do `thieves`. Płatny drogi okaz zwiększa więc atrakcyjność ofiary. Ochrona wyłącznie zakupionych grzybów tworzy płatny bezpieczny dochód; automatyczne odtworzenie grzyba kupującemu przy zachowaniu łupu złodzieja tworzy duplikację, także alt → główne konto. ([Kradzież](https://github.com/sybdev007/mushrooms/blob/7da90c977b50f226fd8a6b9fbddd56b6de02812d/src/server/GardenService.luau#L795), [przekazanie łupu](https://github.com/sybdev007/mushrooms/blob/7da90c977b50f226fd8a6b9fbddd56b6de02812d/src/server/GardenService.luau#L480))

P2W byłoby wysokie: zakup omija polowanie i część ryzyka. Kanibalizuje przede wszystkim **luck 49 i boom 99**, bo kupujący dostaje pożądany okaz bez korzystania z ich losowych korzyści; zmniejsza też okazje do użycia **oil 15 i rescue 59**. Lepszy ogród zwiększa wartość **harvest 29 i x2 19–149**, lecz nadmiar monet może zmniejszyć potrzebę ich zakupu. `richest` korzysta z dochodu bezpośrednio. Kupiony okaz nie powinien zaliczać się do `rare`: obecne `ProgressService.found` nalicza najlepsze znalezisko niezależnie od źródła, więc użycie go bez rozróżnienia pochodzenia dopuściłoby płatne wejście na ten ranking. ([ProgressService](https://github.com/sybdev007/mushrooms/blob/7da90c977b50f226fd8a6b9fbddd56b6de02812d/src/server/ProgressService.luau#L372))

Grow a Garden potwierdza oficjalnie pętlę restocku, sadzenia i wzrostu offline. Beebom opisał 3 kwietnia 2026 restock nasion co **5 min** i przyspieszenie za **79 R$**; to źródło wtórne. Tutaj 30 min oznaczałoby 2, a nie 12 okien na godzinę, ale sama popularność tej mechaniki nie dowodzi jej dopasowania do kradzieży w tej grze. ([Roblox](https://www.roblox.com/games/126884695634066/Grow-a-Garden), [Beebom](https://beebom.com/grow-a-garden-seed-shop-guide/))

Jeżeli wróci temat handlarza, bezpieczniejszy kierunek to widoczne dekoracje bez dochodu. Dla jakiejkolwiek sprzedaży produktywnych okazów najpierw potrzebny jest odrębny model emisji i utraty, limit konta zachowywany między serwerami oraz jednoznaczna własność po kradzieży. Zwykły zakup konkretnego pokazanego gatunku należy odróżnić od płatnego losowania. Roblox obejmuje zasadami płatnej losowości także walutę kupioną za Robux i płatne luck boosts; ujawnienie wyników, szans i ograniczenia kont wymagają osobnej weryfikacji. Dokumentacja nie rozstrzyga wprost, czy ta kradzież jest „trading”, więc nie należy ogłaszać jej automatycznie zakazaną. ([Roblox: Paid random items](https://create.roblox.com/docs/production/monetization/paid-random-items))

## x2 za monety nie jest racjonalnym zlewem; małe nagrody mają policzalny budżet

### Obecne x2 za monety: odrzucić

Niech **B** będzie dodatkową wypłatą obecnego x2, a **C** ceną w monetach. Bilans względem zwykłego odbioru wynosi **`B − C`**. Przy B=32 000 i C=16 000 gra tworzy dodatkowe **16 000 monet**. Przy C=32 000 zakup jest neutralny i nie daje korzyści. Przy C=40 000 usuwa 8 000 monet, lecz świadomy gracz płaci 40 000 za 32 000. Nie ma użytecznej ceny, która jednocześnie daje graczowi zysk monetowy i stanowi zlew.

Wariant C<B staje się obowiązkowym zyskownym kliknięciem, podnosi `richest` i przyspiesza ulepszenia; nie daje bezpośrednich punktów `rare`, `thieves` ani `candy`. Dotyczy już posiadanych monet skrzyni, więc nie wprowadza nowego kradzionego przedmiotu, ale wzmacnia późniejszą przewagę sprzętową. Najsilniej kanibalizuje płatne **x2 19–149**, następnie **harvest 29**; **rescue 59, oil 15, luck 49 i boom 99** odczuwają pośrednio nadwyżkę monet. Nie zmniejsza przewagi płatnych produktów przez sam fakt udostępnienia przycisku za monety.

Czasowy mnożnik dochodu to inny produkt, którego tutaj nie ma. Oficjalna baza BIG Games potwierdza np. Coins Potion V w Pet Simulator 99: **+100% monet przez 50 min**, ale widoczny RAP nie jest ceną zlewu ustaloną przez twórcę. Nie przenosić tego modelu na jednorazowy odbiór skrzyni. ([BIG Games](https://db.biggames.io/database/potions/%7B%22id%22:%22Coins%22,%22tn%22:6%7D))

Jeśli potrzeba nowego zlewu, propozycja do osobnego sprawdzenia to dekoracja bez odsprzedaży, dochodu i transferów: pierwsza **1 S = 1 600 / 32 000 / 160 000 monet**, kolejny wariant **3 S = 4 800 / 96 000 / 480 000**. Usuwa całą cenę i nie generuje zwrotu. Nie zastępuje to istniejącego planu gabloty z Handoff ani jego cen; jest alternatywą do decyzji projektowej. Roblox zaleca mierzenie źródeł i zlewów oddzielnie, co pozwoli ocenić rzeczywisty bilans. ([Roblox: Economy events](https://create.roblox.com/docs/production/analytics/economy-events))

### Nagroda co 6 h i kody: wdrażać w małym pilotażu

**Propozycja: 0,1 S co 6 h**, wyłącznie monety do portfela. Maksymalnie **4 przyznania w ruchomych 24 h**, jedno gotowe do odbioru, bez kumulacji pominiętych okresów. Kod kampanii: **0,25 S raz na konto**, jeden taki kod w kampanii, ważny 7 dni. Warunek obu: ukończony tutorial, 10 aktywnych minut i jedna zwykła sprzedaż. Serwer ustala świat; wartość gotowej nagrody zostaje zamrożona w chwili uzyskania uprawnienia, aby przejście portalu nie przeliczało już gotowego odbioru.

| Budżet nowych nagród, monety | Las | Jaskinia | Bagna |
|---|---:|---:|---:|
| Jeden odbiór po 6 h: 0,1 S | 160 | 3 200 | 16 000 |
| Maksimum w 24 h: 0,4 S | 640 | 12 800 | 64 000 |
| Maksimum w 7 dni przy stałym świecie: 2,8 S | 4 480 | 89 600 | 448 000 |
| Jeden kod kampanii: 0,25 S | 400 | 8 000 | 40 000 |

Cały dzienny limit odpowiada około **1,75 / 0,76 / 0,94 min** referencyjnego dochodu, a nie czterem pełnym zadaniom. Na samym początku lasu przy około 56 monet/min pojedyncze 160 monet to jednak niemal 2,9 min gry — stąd warunek aktywności. To maksymalny budżet, nie prognoza czterech codziennych powrotów. Sześciogodzinny interwał nie ma potwierdzonej przewagi nad 24 h dla tej gry; należy ocenić go jako pilotaż retencji.

`richest` wzrośnie o otrzymaną kwotę, lecz pozostałe rankingi nie dostaną bezpośrednich punktów. Monety w portfelu nie są łupem z ogródka. Nagrody pomagają obu grupom graczy i mają niskie dodatkowe ryzyko P2W, pod warunkiem braku płatnego mnożenia, dodatkowych odbiorów i obchodzenia limitu. Kanibalizacja **harvest 29 i x2 19–149** jest ograniczana małym budżetem, a wobec **rescue 59, oil 15, luck 49 i boom 99** pozostaje pośrednia przez progresję. Nie jest zerowa, ale nie oferujemy bezpłatnego odpowiednika ich funkcji.

Nie dawać w tych nagrodach luck, Wysypu, Zarodników, rescue, oil, harvest, x2 ani produktywnych roślin. Kody kosmetyczne mogą później dawać **0 monet**. Zastany wyjątek: paczka społecznościowa już dopisuje 900 sekund do tego samego `luckUntil` co płatna mikstura. To sprzeczność obecnego stanu z zasadą „luck pozostaje płatne”, do osobnej decyzji właścicieli; raport jej nie rozszerza ani nie zmienia. ([CommunityService](https://github.com/sybdev007/mushrooms/blob/7da90c977b50f226fd8a6b9fbddd56b6de02812d/src/server/CommunityService.luau#L135))

Konkurencyjne przykłady nie uzasadniają kopiowania kwot. Tracker PS99 podaje VIP **400 R$** w próbce z 1 listopada 2026, a społecznościowa wiki opisuje nagrodę VIP co 6 h; starszy artykuł mówił o 24 h. To słabsze, zmienne źródła i nagroda płatnego VIP, nie dowód skuteczności darmowego odbioru dla wszystkich. Dlatego nie przenosimy diamentów ani częstotliwości konkurenta na monety tej gry. ([SpawnRadar](https://www.spawnradar.com/games/3317771874/minigames-pet-simulator-99), [Pet Simulator Wiki](https://petsimulatorwiki.com/wiki/vip-gamepass-pet-simulator-99/), [Pro Game Guides, 2023](https://progameguides.com/roblox/is-buying-vip-worth-it-in-pet-simulator-99-roblox/))

## Najpierw zmierz obecne produkty, potem dodawaj jedną ofertę

Wdrożenie powinno zachować kolejność poniżej. Dokument nie autoryzuje publikacji ani zmian produkcyjnego zapisu.

| Kolejność | Decyzja | Cena i liczby do pierwszej próby |
|---|---|---|
| 1 | Dokończyć istniejącą ofertę x2 i review zakupu, potem zebrać bazę danych | 19/39/79/149 R$; progi 15/40/120/240 min; obecnie ID=0. Zachować rescue 59, boom 99, oil 15, harvest 29, luck 49 |
| 2 | Minimum tydzień obserwacji bez równoczesnego mieszania nowych modeli | D1/D7, sesje, saldo i źródła/zlewy, zakupy każdego SKU; tydzień nie gwarantuje dostatecznej próby |
| 3 | Pilotaż nagrody 6 h i jednego kodu, osobno od zmiany VIP | 0,1 S/odbiór, max 4/24 h; kod 0,25 S, raz/konto/kampanię, 7 dni |
| 4 | Pilotaż kosmetycznego VIP, z własnym okresem pomiaru | 249 R$; złota nazwa, tag, pokój społeczny, wygląd latarni; 0 monet, bonusów i ochrony |
| 5 | Zlew dopiero po potwierdzeniu nadwyżki monet | Opcjonalne dekoracje 1 S i 3 S; bez ekonomicznego zwrotu; porównać z planem gabloty |
| Odłożyć | Zarodniki | Brak wdrożenia teraz; nie oferować rabatów ani darmowych Z wymienialnych na płatne efekty |
| Odrzucić | VIP stałe x2, produktywne gatunki za Robux, obecne x2 za monety | Brak rekomendowanej ceny: problem dotyczy konstrukcji, nie samej kwoty |

Przed implementacją nagród kryterium odbioru powinien być pojedynczy serwerowy zapis: kwota, świat, termin i identyfikator przyznania. Reconnect, równoległe żądania i wejście na inny serwer nie mogą ponawiać nagrody; klient nie podaje ceny, świata ani czasu. Stan limitu i wykorzystane kody muszą przetrwać zapis oraz restart. Alty nadal otrzymają własny mały grant — warunek aktywności tylko podnosi koszt farmienia, nie eliminuje go. Nie tworzyć transferowalnych nagród ani ścieżki darmowy grant → płatny gatunek → kradzież → główne konto. Te wymagania wynikają z modelu nadużyć opisanego w [REVIEW.md](https://github.com/sybdev007/mushrooms/blob/7da90c977b50f226fd8a6b9fbddd56b6de02812d/docs/REVIEW.md).

O powodzeniu decydować powinny nie tylko przychody, lecz także zakupy harvest/x2 na powracającego płacącego gracza, koncentracja salda w `richest`, czasy do portali oraz wyjścia po kradzieży. Porównywać podobne kohorty i normalizować zakupy aktywnością; nie wyciągać wniosków z samej sumy przychodu przy zmiennej liczbie graczy. Brak danych ARPDAU, konwersji i udziału poszczególnych źródeł monet uniemożliwia dziś rzetelną prognozę wzrostu przychodów. Kosmetyczny VIP i ograniczone granty mają jednak jawny koszt ekonomiczny, podczas gdy stałe x2 i produktywne zakupy przenoszą koszt na całą przyszłą gospodarkę oraz relacje między złodziejem a właścicielem ogródka.
