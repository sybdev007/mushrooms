# Zlewy monet po otwarciu Łysej Góry

**Teraz: górska półka za 327,6 mln i Ofiara dla Leszego od 100 mln.** Najpierw wypuścić półkę, potem osobno włączyć kapliczkę. Półka daje sześć widocznych zakupów i powód, by pokazywać znaleziska. Kapliczka daje dobrowolny wydatek także po ukończeniu gabloty. Globalny ranking włączyć po sprawdzeniu zapisu wpłat i moderacji. Kosmetyki w seriach zostawić na później. Odrzucić szlif wpisujący wyniki do podstawowej Grzybopedii i obowiązkowy rebirth.

## Punkt odniesienia

Sprawdzone na `sybdev007/mushrooms` `main` (`eb927bb`), po przeczytaniu `CLAUDE.md` i `docs/HANDOFF.md`. Symulator Lune daje 9 h 24 min do maks. ulepszeń dochodowych i 941 144 monet/min na końcu. Koszt katalogu ulepszeń to ok. 161 mln. Symulator osobno podaje 161 068 407 monet zarobionych w modelowanej ścieżce, więc tych dwóch liczb nie należy utożsamiać. Średnia stawka Góry z tabeli nagród to 448 946/min. Referencje dla Kotłów i Szczytu to 679 548 i 811 679/min. Saldo Toma 174 mln pochodzi z handoffu i jest przykładem, bez danych o rozkładzie sald innych graczy.

Stawki porównawcze to 27 i 54 mln na godzinę. Poniżej są godziny **zarobienia kwoty wydatku od zera**, bez innych zakupów. Przy posiadanym saldzie czas do zakupu to `max(0, cena − saldo) / stawka`. Wpłaty mogą być natychmiastowe. Tabela nie prognozuje chęci wydawania.

| Zlew / zakres | Monety | Godz. przy 450 tys./min | Godz. przy 900 tys./min | Praca |
|---|---:|---:|---:|---|
| Góra · miejsce 19 | 5,2 mln | 0,19 | 0,10 | M za serię |
| Góra · miejsce 20 | 10,4 mln | 0,39 | 0,19 | |
| Góra · miejsce 21 | 20,8 mln | 0,77 | 0,39 | |
| Góra · miejsce 22 | 41,6 mln | 1,54 | 0,77 | |
| Góra · miejsce 23 | 83,2 mln | 3,08 | 1,54 | |
| Góra · miejsce 24 | 166,4 mln | 6,16 | 3,08 | |
| Góra · komplet | **327,6 mln** | **12,13** | **6,07** | |
| Gablota · wszystkie cztery serie od zera | 448,8 mln | 16,62 | 8,31 | |
| Ofiara · pierwszy próg | 100 mln | 3,70 | 1,85 | M bez tablicy |
| Ofiara · drugi próg | 500 mln | 18,52 | 9,26 | L łącznie z tablicą |
| Ofiara · trzeci próg | 1 mld | 37,04 | 18,52 | |
| Ofiara · czwarty próg | 5 mld | 185,19 | 92,59 | |
| Ofiara · piąty próg | 10 mld | 370,37 | 185,19 | |
| Ofiara · szósty próg | 20 mld | 740,74 | 370,37 | |
| Szlif · Oko Nocy od zwykłego do Kosmicznego · oczekiwane opłaty | 8,01 mln | 0,30 | 0,15 | L |
| Kosmetyki · jedna seria czterech zakupów | 100 mln | 3,70 | 1,85 | L za katalog trzech serii |
| Kosmetyki · trzy serie po cztery | 300 mln | 11,11 | 5,56 | |
| Kosmetyki · dwa takie zestawy | 600 mln | 22,22 | 11,11 | |

S oznacza lokalną zmianę w istniejącym przepływie. M obejmuje kilka modułów i test w świecie. L obejmuje nowy przepływ z istotną pracą przy grafice, zapisie lub obsłudze rankingu. Progi Ofiary są skumulowane. Szlif ma zmienny czas i wymaga materiału oraz kolejnych prób.

## 1. Górska seria gabloty · M

Zachować wzór `10 × 520 000 × 2^(k−1)` dla sześciu miejsc Góry. Pierwsze cztery kosztują 78 mln, pierwsze pięć 161,2 mln. Przy saldzie 174 mln i gotowych poprzednich seriach Tom kupi pięć i zachowa 12,8 mln. Do ostatniego zabraknie 153,6 mln, czyli 5 h 41 min lub 2 h 51 min. Jeżeli zaczyna od dwóch darmowych miejsc, poprzednie serie kosztują łącznie 121,2 mln. Wtedy saldo wystarczy jeszcze na pierwsze trzy miejsca Góry i zostanie 16,4 mln. Cena ostatniego miejsca stanowi 51% całej półki. Uzasadnia ją widoczne zwieńczenie kolekcji, więc przed wydaniem warto obejrzeć makietę półki z pełną obsadą. Gdy gracze z odpowiednim saldem omijają głównie ostatnie miejsce, przetestować cenę 120 mln dla tego miejsca. Całość wyniesie wtedy 281,2 mln (10,41 / 5,21 h). Zmiana tylko tego miejsca zachowuje tańszy start i historyczne ceny.

**Wystawa.** Półka tematycznie górska, z tymi samymi zasadami wystawiania co pozostałe. Na początku listy pokazać odkryte formy z Góry i wyróżnić Kosmiczne oraz trofea ze Znaleziska Nocy. Przykładowe eksponaty to Kołpak Wiedźmy, Gwiazdosz, Księżycowy Kołpak, Oko Nocy i Ziele Baby Jagi. Dopuścić wszystkie dotychczasowe kopie i trofea, żeby zakup od razu dało się wykorzystać. Zachować obsługę karty zdobyczy i automatyczne wystawienie trofeum na pierwszym wolnym kupionym miejscu. Eksponat jest dekoracją bez wartości sprzedażowej, zajętej grządki i mocy zbiorów.

**Implementacja i zapis.**

- Dopisać serię 4 z `unlock = "mountainUnlocked"` do `Config.Showcase.series`. Dodać flagę do `Showcase.Flags` i do danych przekazywanych przez `ShowcaseService`. Sam wpis w konfiguracji dałby złą cenę, bo `Showcase.seriesScale` podaje dziś do `Progress.rewardScale` trzeci argument `false`. Dla serii 4 podać `true`, pozostawiając dotychczasowe skale 1–3 i dwa darmowe miejsca w serii 1.
- Kolejność zakupu 1–24. Wymagać otwartej Góry oraz kupienia miejsca 18 przed 19. Właściciel ogląda ceny i brakującą kwotę przy regale. Odmowa dla nieotwartej Góry i dla żądania z innego ogródka. Klient pokazuje cenę, serwer przelicza następny slot oraz saldo. Jedno potwierdzenie kupuje wskazany slot. Powtórka tego samego żądania zastaje kolejny numer i niczego nie pobiera.
- `showcase.n` i `showcase.items` wystarczają. Zmienić górny limit `Showcase.readSave` do 24 wraz z `Showcase.TOTAL`. Wspólne wydanie z Ofiarą ma wersję 10. Jeśli półka wyjdzie wcześniej samodzielnie, zalecam wersję 10 już dla zwiększenia limitu, bo serwer z wersją 9 przy wczytaniu obciąłby miejsca 19–24. W takim wariancie Ofiara dostaje wersję 11. Stare sloty i wystawy zachowują identyfikatory. Profil bez zapisu zaczyna z dwoma miejscami. Po wydaniu zrestartować stare serwery według `CLAUDE.md`.
- Dodać czwartą półkę w `ShowcaseService`, gdzie wysokości są dziś zapisane dla trzech. Sprawdzić zmieszczenie w oknie `ShowcasePanel`, czytelność z alejki i na telefonie, zasłanianie ogrodu oraz poświatę przy sześciu pełnych regałach. Zacząć od tych samych słabych świateł. Ryzyko wizualne to wysoki regał i prześwietlenie, ekonomiczne to skończony katalog oraz próg 166,4 mln.
- W jednej sekcji bez oczekiwania zapisać obciążenie i nowy numer miejsca w tym samym profilu. Efekt, synchronizacja UI i analityka idą po zmianie stanu. Wyjście przed zakupem nie pobiera niczego, wyjście po zakupie zapisuje saldo i miejsce razem. Awaria przed potwierdzonym zapisem może cofnąć oba. Po wejściu stan okna pochodzi z profilu. 
- Analytics: istniejące `Coins/Sink/Shop` z `ShowcaseSlot19`–`ShowcaseSlot24`. `Milestone_MountainShowcaseFirst` i `Milestone_MountainShowcaseComplete` wyłącznie przy zakupach 19 i 24. Po tygodniu sprawdzić konwersję między miejscami wśród graczy z Górą, z uwzględnieniem tych, których było stać na dany zakup.

## 2. Ofiara dla Leszego · M bez rankingu / L z rankingiem

Kapliczka przy chatce w lesie. Dostęp dla graczy z otwartą Łysą Górą. Po pierwszej wpłacie widać dożywotnią sumę, odblokowane nagrody i dystans do kolejnego progu. Żaden próg nie wypłaca monet ani nie daje przedmiotu do handlu. Poświata to efekt na tabliczce ogródka, bez zmiany oświetlenia wyprawy. Tytuły wybierane w istniejącym panelu `Titles`.

| Łącznie wpłacone | Nagroda |
|---:|---|
| 100 mln | Tytuł „Darczyńca Leszego” |
| 500 mln | Tytuł „Patron Puszczy” |
| 1 mld | Tytuł „Opiekun Kapliczki” i subtelna bursztynowa obwódka tabliczki |
| 5 mld | Tytuł „Legenda Puszczy” i srebrna obwódka |
| 10 mld | Tytuł „Wieczny Patron” i księżycowa obwódka |
| 20 mld | Tytuł „Strażnik Prastarej Puszczy” |
| Dalej | Licznik i pozycja w rankingu. Bez nowych nagród w pilotażu |

**Wpłata.** Przyciski 1 / 10 / 50 / 100 mln oraz wpisanie kwoty w pełnych milionach od 1 do 100. Brak przycisku „wszystko”. Potwierdzenie pokazuje wpłatę i saldo po transakcji. Serwer wystawia jednorazowy token dla kwoty i sesji z ważnością 30 s. Potwierdzenie wymaga aktualnej sesji z zapisywalnym profilem, gracza przy kapliczce (do 12 studów), otwartej Góry, poprawnej kwoty i wystarczającego salda. Maksymalnie jedna skuteczna wpłata na 2 s. Nowa oferta zastępuje poprzednią. Zużycie tokena, obciążenie i zwiększenie licznika w jednej sekcji bez oczekiwania. Odrzucać wartości niecałkowite, niefinitywne, ujemne, powyżej limitu lub z niezgodnego tokena. Przy braku środków po zmianie salda wyświetlić aktualne saldo i wymagać ponownego potwierdzenia.

**Zapis.** Nowe `data.stats.leszyOffered: number` z domyślnym 0 w `Titles.emptyStats` i reconcile w `DataService`. Wersja 9 → 10 przy wspólnym wydaniu, 10 → 11 przy osobnym po półce. Przy reconcile przyjmować nieujemne skończone całkowite wartości do bezpiecznego limitu `2^53−1`. Uszkodzoną wartość zresetować do 0. Przed wpłatą odrzucić sumę przekraczającą limit, bez pobrania kwoty. Nie odtwarzać wpłat z historii zarobków. Progi i poświatę wyliczać z licznika, bez drugiej kopii uprawnień. Odczyt uprawnień także z profilu już po ponownym wejściu. Zamknięcie okna, odłączenie przed potwierdzeniem lub utrata sesji usuwa ofertę. Wyjście po operacji zapisuje saldo i licznik razem. Brak zapisu po awarii nie może dać trwałego wyniku na tablicy. Jeśli klient straci odpowiedź, odczytuje stan zamiast ponawiać wpłatę automatycznie. Wydatki nie zmieniają `data.earned` używanego przez „Najbogatszych”.

**Tablica.** Po pilotażu uruchomić globalny ranking dożywotni `LanternForager_Top_v2_leszy`. Oprzeć się na ścieżce cukierków w `LeaderboardService`: tylko suma z potwierdzonego zapisu przez `DataService.onSaved`, także po wyjściu, oraz odtworzenie kolejki z potwierdzonego profilu przy kolejnym wejściu. `ScoreQueue` ponawia wynik po błędzie, a `UpdateAsync` bierze maksimum z zapisanej i nowej sumy. Odczyt czołówki co 60 s. Przy awarii ostatni poprawny odczyt z oznaczeniem opóźnienia albo komunikat o niedostępności. Konta DEV i Studio poza zapisem globalnym, konta DEV odfiltrować też przy odczycie. Przed startem mieć trwały znacznik moderacji (0) i filtr wykluczeń po UserId. Stary zapis i ponowienie nie mogą odtworzyć usuniętego wyniku. Brak nagród za pozycję i brak tygodniowego resetu. Ryzyka to ranking wielkości portfela, błędne wpłaty, sztuczne monety i opóźnienie po zapisie. Pierwszy próg daje osiągalny cel także bez miejsca w czołówce. Przy 174 mln można od razu wpłacić 100 mln albo kupić pięć górskich miejsc przy gotowej reszcie gabloty. Tych dwóch wydatków to saldo nie pokryje.

**Analytics.** `Coins/Sink/Shop`, SKU `LeszyOffering`, z kwotą i saldem po zatwierdzonej mutacji. `Milestone_LeszyFirstOffering` przy przejściu z 0, a `Milestone_LeszyOffering100M`, `500M`, `1B`, `5B`, `10B`, `20B` przy przekroczeniu progu, każdy raz w wynikowym profilu. Metryki po tygodniu to odsetek wpłacających wśród aktywnych z Górą, ponowne wpłaty, suma spalonych monet do sumy zarobionych w kohorcie oraz mediana i górny decyl salda. Oddzielić wpłaty od zakupów gabloty i wykluczyć ruch testowy. Duża jednorazowa wpłata ze starego salda nie mierzy utrzymania zlewu w kolejnych tygodniach.

## 3. Szlif wariantu w moździerzu · L · odłożyć

Model do oceny to jedna sztuka, jedna ranga w górę przy sukcesie, ta sama ranga przy porażce i opłata w obu przypadkach. Kandydaci to świeże sztuki bez cech, zwykłe gatunki dostępnych światów, po otwarciu Góry. Wykluczyć grzyby strażników, mimiki, trofea i gatunki tylko z kuźni. Szanse stałe, bez bonusów szczęścia, dodatkowych efektów i ochrony płatnymi produktami.

| Przejście | Sukces | Opłata za próbę na Oku Nocy | Średnia suma opłat do sukcesu |
|---|---:|---:|---:|
| Zwykły → Srebrny | 65% | 100 000 | 153 846 |
| Srebrny → Złoty | 45% | 166 829 | 370 731 |
| Złoty → Tęczowy | 25% | 322 401 | 1 289 604 |
| Tęczowy → Kosmiczny | 10% | 619 596 | 6 195 960 |

Cennik dla gatunku i rangi: `S` i `T` to ceny z `Economy.mushroomValue` przed i po sukcesie. `E = 1,84 × ((1−p) × S + p × T)`, `opłata = max(100 000, ceil(E / 0,85 − S))`. Mnożnik 1,84 to maksimum sprzedaży z czterech stron Grzybopedii. Wartość wejścia liczona konserwatywnie po cenie bazowej. Model obejmuje normalną sprzedaż, bez deweloperskiego podwajania. `lune run tools/endgame_polish_ev.luau` sprawdził 152 kombinacje gatunku i rangi na aktualnym `main`. Najwyższe `E / (S + opłata)` to 0,850000. Dla pojedynczej próby z Tęczowym Okiem Nocy jest to wydatek ok. 1,38 / 0,69 min gry. Dziesięć prób średnio do sukcesu daje 6,20 mln samych opłat (0,23 / 0,11 h). Cała ścieżka daje średnio 8,01 mln samych opłat przy ponawianiu po porażce. Te sumy pomijają koszt pozyskania materiału i ewentualną sprzedaż wyniku.

**Decyzja.** Zwrot ze sprzedaży sam w sobie nie dopuszcza tej opcji. Produktywny wynik można zasadzić i czerpać trwały dochód. Wpis do podstawowego atlasu może domknąć próg strony, a sama Tęcza daje do +10 pkt proc. ceny sprzedaży za stronę. Arcygrzybiarz i `grandmaster` korzystają z tęczowych stron. Wydanie monet na ostatni brakujący wpis stałoby się zakupem wyższego przyszłego dochodu. Ryzyka obejmują też losowe serie porażek, ponowienie po rozłączeniu i skrót wokół nocnych poszukiwań. Jeżeli wrócimy do szlifu, zachować wyłącznie kosmetyczną formę do gabloty w osobnym katalogu bez premii, uprawy, handlu, sprzedaży i podstawowego `grandmaster`. W takim wydaniu zwrot monet wynosi 0. Powyższy cennik daje punkt odniesienia do testów chęci wydawania, bez obietnicy sprzedaży kosmetyku.

## 4. Kosmetyki w skończonych seriach · L · później

Trzy serie po cztery elementy w cenach 5 / 15 / 30 / 50 mln za serię. Latarnia: obudowy i emblematy bez zmiany zasięgu, jasności i widoczności. Ogródek: furtka, płot, szyld i dekoracja regału bez kolizji i osłon. Chatka: tabliczka, proporzec, detal drzwi i wykończenie półki gracza, widoczne tylko w jego części chatki lub u niego lokalnie. Zakupy z podglądem, bez duplikatów, przenoszenia między graczami i nagród monetowych. Każda seria to 100 mln, a 12 rzeczy to 300 mln. To rozmiar katalogu porównywalny z górską półką. Przy 900 tys./min katalog za 100 mln znika po 1 h 51 min, więc jedna seria jest małym dodatkiem. Żeby zapełnić 10 h przy tej stawce, potrzeba co najmniej 540 mln ofert, czyli sześciu serii po 100 mln w tym modelu. Kolejne serie wymagają stałego nakładu grafiki i testów. Ryzyka to niska różnorodność, zasłanianie ogródka i dublowanie kosmetyków sezonowych lub planowanego VIP. Najpierw sprawdzić, czy gracze wydają na istniejącą półkę i status.

## Granice projektu

Zlew ma zerowy wpływ na tempo zdobywania monet w rekomendowanych opcjach. Mikstura szczęścia, Wysyp, rescue, oil, harvest i x2 skrzyni zachowują ofertę za Robux. Zachować decyzje z `monetization-research.md` o stałym x2, produktywnych grzybach za Robux i nowej walucie premium. Obowiązkowy rebirth nadal odpada zgodnie z `hit-research.md`. Nawet ponowny wydatek rzędu 161 mln odpowiada przy obecnym tempie tylko ok. 3–6 h zarabiania. Sam reset wymusza utratę postępu, podczas gdy problem dotyczy tego, na co gracz może wydać już zarobione monety.

## Testy do dopisania podczas wdrożenia

W `tests/economy.spec.luau`:

1. Wszystkie ceny 1–18 bez zmiany, w tym dwa zera na początku. Sloty 19–24 mapują się na serię 4 i mają sześć cen z tabeli. Suma 327 600 000. Po 24 wynik `full`.
2. `nextSlot` przy 18 miejscach zwraca `world` bez Góry, po otwarciu zwraca 19 i 5 200 000. Otwarcie Góry z niepełnymi Bagnami nie pomija zakupów. Reconcile starych zapisów i nowego profilu, zachowanie starych eksponatów i kluczy, odczyt prawidłowego slotu 24, odrzucenie slotu 25 i niekupionego slotu. Karta i trofeum trafiają do wolnego kupionego miejsca według dotychczasowych zasad.
3. Ofiara na starym profilu ma 0. Reconcile zachowuje liczbę powyżej 32-bitowego zakresu. Odrzuca ujemne, ułamki, NaN, nieskończoność i wartości poza limitem. Kwota od 1 do 100 mln w pełnych milionach. Testy dokładnego salda, za małego salda, kwoty nad limitem i przekroczenia limitu licznika. Sukces zmienia saldo i licznik o identyczną kwotę, a `earned` i bonus sprzedaży pozostają takie same.
4. Tytuł i wygląd tuż poniżej, dokładnie na i powyżej każdego progu. Suma rośnie dalej po 20 mld. Wybrany stary tytuł pozostaje wyborem gracza.
5. Czysta logika potwierdzeń: ważny, wygasły, powtórzony i obcy token, podmieniona kwota, zastąpiona oferta, równoległe potwierdzenia i zniknięcie flagi dostępności przed potwierdzeniem. Jedna zaakceptowana akcja daje jeden wydatek.
6. Przekazywanie do kolejki wyłącznie zapisanej wartości, ponowienie przy błędzie, starszy wynik po nowszym, znacznik moderacji i wykluczenia. Dodać kontrolę nowych kluczy lokalizacji do istniejącego testu.

Po wdrożeniu sprawdzić na serwerze testowym odłączenie w obu oknach przed i po akcji, ponowne wejście, brak Góry i brak dostępu do zapisu, próbę wywołania z daleka, dwa szybkie potwierdzenia, wyjście podczas zapisu, oraz zachowanie tablicy podczas błędu DataStore. W Studio sprawdzić także widok regału na telefonie, sześć pełnych ogródków i działanie wczytywania fragmentów mapy.

## Teksty do GameStrings.csv

Poniższe wiersze są propozycją do wdrożenia. Wspólne komunikaty zakupu gabloty już istnieją.

```csv
SHOWCASE_SERIES_MOUNTAIN,Mountain shelf,,,Półka Łysej Góry
SHOWCASE_MOUNTAIN_LOCKED,Unlock Bald Mountain to buy spots on this shelf,,,Odblokuj Łysą Górę aby kupić miejsca na tej półce
LESZY_OFFER_TITLE,Offering to Leszy,,,Ofiara dla Leszego
LESZY_OFFER_PROMPT,Make an offering,,,Złóż ofiarę
LESZY_OFFER_TOTAL,Total offered: {1},,,Łącznie złożono: {1}
LESZY_OFFER_NEXT,Next reward at {1} coins offered,,,Następna nagroda po wpłaceniu {1} monet
LESZY_OFFER_LIMIT,Choose a whole number from 1 to 100 million coins,,,Wybierz od 1 do 100 milionów monet w pełnych milionach
LESZY_OFFER_CONFIRM,Offer {1} coins? You will have {2} left. This cannot be undone.,,,Złożyć {1} monet? Zostanie ci {2}. Tej wpłaty nie można cofnąć.
LESZY_OFFER_CANCEL,Cancel,,,Anuluj
LESZY_OFFER_ACCEPT,Confirm offering,,,Potwierdź wpłatę
LESZY_OFFER_DONE,You offered {1} coins,,,Ofiara złożona: {1} monet
LESZY_OFFER_LOCKED,Unlock Bald Mountain to make an offering,,,Odblokuj Łysą Górę aby złożyć ofiarę
LESZY_OFFER_TOO_FAR,Move closer to the shrine,,,Podejdź bliżej kapliczki
LESZY_OFFER_EXPIRED,Offer expired. Choose an amount again.,,,Potwierdzenie wygasło. Wybierz kwotę ponownie.
LESZY_OFFER_NO_COINS,You do not have enough coins for this offering,,,Masz za mało monet na tę ofiarę
LESZY_OFFER_UNAVAILABLE,Offerings are temporarily unavailable,,,Wpłaty są chwilowo niedostępne
LESZY_OFFER_BOARD,Most generous foragers,,,Najhojniejsi grzybiarze
LESZY_OFFER_ALL_REWARDS,All rewards unlocked. You can keep making offerings.,,,Wszystkie nagrody odblokowane. Nadal możesz składać ofiary.
TITLE_LESZY_DONOR,Donor of Leszy,,,Darczyńca Leszego
TITLE_LESZY_PATRON,Patron of the Woods,,,Patron Puszczy
TITLE_LESZY_SHRINE,Keeper of the Shrine,,,Opiekun Kapliczki
TITLE_LESZY_LEGEND,Legend of the Woods,,,Legenda Puszczy
TITLE_LESZY_ETERNAL,Eternal Patron,,,Wieczny Patron
TITLE_LESZY_ANCIENT,Guardian of the Ancient Woods,,,Strażnik Prastarej Puszczy
```

## Źródła w repozytorium

`CLAUDE.md`, `docs/HANDOFF.md`, `docs/plans/hit-research.md`, `docs/plans/monetization-research.md`, `tools/economy_sim.luau`, `src/shared/{Config,Economy,Progress,Showcase,Titles,Forge}.luau` i `src/server/{DataService,LeaderboardService,ShowcaseService,Ledger,Analytics,GameService}.luau`. Wyceny i progi są propozycjami do pilotażu. Analiza opiera się na tej grze.
