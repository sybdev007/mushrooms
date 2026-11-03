# Ekspedycja do Głębokich Komór (jaskinia) — projekt pilotażu

Stan: 3.11.2026. Powstał z rozmowy Tom + Claude + uwagi Codexa (`economy-sinks-and-offers-research.md`).
Decyzje zatwierdzone przez Toma 3.11. **Pierwsza wersja zbudowana na gałęzi `ekspedycja`** (sekcja „Wdrożenie”
na końcu) — do sprawdzenia w Studio przed scaleniem.

## Po co

Jaskinia i bagna nie mają powodu do powrotu, gdy gracz kupi już ulepszenia. Do tego nadwyżka monet
nie ma na co pójść. Ekspedycja ma dać powtarzalny cel w jaskini, którego zdobycze idą do kolekcji
i ogródka (relikty, wystawa), a monety wydaje się na ich oprawę. Nie dokładamy mnożnika zarobków.

Pilotaż: **jedna ekspedycja, ok. 10–15 min, trzy komory, jedna decyzja „wracasz czy ryzykujesz”**.
Bagna i rozbudowa innych map dopiero, jeśli gracze będą do niej wracać.

**Nazwa:** „wyprawa” to już nazwa wspólnych latarni (`src/shared/Expedition.luau`, napisy w grze).
Nowa rzecz w grze i w kodzie to **Ekspedycja** (np. `DelveService`, klucze `DELVE_*`), żeby się nie myliło.

## Główne pytanie: czemu drugi i dziesiąty raz?

### Co zmienia się między podejściami
- **Zlecenie**: na tablicy w Obozie 3 do wyboru, losowane z puli. Każde pokazuje cel, ryzyko i nagrodę.
  Przykłady: odnaleźć zaginioną skrzynię górnika · zebrać zestaw okazów z komór · wynieść relikt z Krypty.
- **Stan komór** na tę ekspedycję (1 losowy modyfikator): zawalone przejście (inna trasa), wysoka woda
  (olej schodzi szybciej, inne kryjówki), czuwający Skarbnik (patrol w Krypcie od wejścia).
- **Położenie znaleziska**: 3–4 kryjówki na komorę, losowo.
- **Zlecenie dnia**: jeden konkretny relikt, taki sam dla wszystkich graczy danego dnia.

### Decyzje gracza
- które zlecenie,
- koszyk: relikt zajmuje miejsce → grzyby na sprzedaż albo znalezisko,
- olej: czy starczy na trzecią komorę,
- **ognisko za drugą komorą**: znalezisko zabezpieczone, wracasz albo idziesz do Krypty po trofeum,
- sam czy z kumplem (połączone latarnie, podnoszenie — już są).

### Na co idą zdobycze
- **Zestawy reliktów** (pilot: 2 zestawy po 4 relikty; docelowo więcej). Zestaw = wpis do kolekcji,
  tytuł, dekoracja.
- **Duplikaty → odłamki**; z odłamków składasz brakujący relikt (ochrona przed pechem; każde podejście coś daje).
- **Renowacja / oprawa reliktu za monety** przed wystawieniem w gablocie ogródka — to jest zlew monet.
  Ceny dopiero po pomiarze nadwyżki (skala jaskini: S = 32 000; propozycja startowa do testu w symulatorze).
- **Ranga ekspedytora**: odblokowuje trudniejsze stany komór i wygląd latarni. **Bez mnożnika zarobków.**
- Relikty **nie dają dochodu**, nie da się ich sprzedać, ukraść ani przełożyć do ogródka jako grzyba.
- Relikty **nie zależą od mikstury szczęścia ani Wysypu** (płatne produkty dotyczą mutacji grzybów,
  nie zastępujemy ich niczym darmowym i nie robimy z nich warunku ukończenia).

## Wejście i trzy komory

- **Tablica w Obozie** (`ZONE_CAMP`) tylko wyjaśnia i daje zlecenie.
- **Wejście** to widoczne, tajemnicze przejście głębiej: w Otchłani (`ZONE_ABYSS`, z 1290–1420) albo na
  początku Kopalni (`ZONE_MINE`, z 1420–1610, przed skarbcem Skarbnika z = 1548). Dojście tam jest
  częścią przygody. Odnoga idzie w bok (oś X, za ścianą jaskini, `halfWidth = 46`), nie przedłuża głównej
  ścieżki, żeby nie ruszać numeracji stref i portalu na Bagna.
- Bez zlecenia przejście jest zamknięte (zawał / krata); w trakcie zlecenia otwarte dla tego gracza.

| Komora | Czynność | Przeszkoda / zagrożenie | Znalezisko |
|---|---|---|---|
| 1. Zawalony Chodnik | odgruzowanie (przytrzymanie przycisku) | osypujące się kamienie na czas | część zleceń, wskazówka do skrzyni |
| 2. Zalana Komora | kładki, kryjówki pod wodą | zmienny poziom wody, szybszy spadek oleju | główne znalezisko; **ognisko na wyjściu = zabezpieczone** |
| 3. Krypta Skarbnika (opcja) | wyniesienie trofeum | patrol Skarbnika | dodatkowe trofeum / relikt |

Złapanie lub zgaśnięcie latarni w Krypcie kasuje tylko premię z Krypty. Zabezpieczone znalezisko zostaje.
Przed ogniskiem: przepada zlecenie (bez kary w monetach), relikt nie wypada na ziemię dla innych.

## Review Codexa (3.11) — do wpisania w projekt przed budową

1. **[P1] Olej nie starcza.** Max latarnia 150 oleju (`Config.Upgrades.oil`: 30 + 12 × 10); z max kryształem
   (×0,5) solo to ~46 s w Otchłani (6,5/s) i ~40 s w Kopalni (7,5/s). Odnoga w osi X dziedziczy strefę po Z
   (`Economy.oilDrain`). Komory potrzebują **własnego spalania**, punktów uzupełnienia i zapasu na powrót.
   Zwykłe ukończenie musi być możliwe **bez kupowania oleju**.
2. **[P1] Relikt to nie grzyb.** Zapis koszyka odrzuca przedmioty spoza listy gatunków. Relikt trzymać
   w stanie ekspedycji, z wirtualnym zajęciem miejsca w koszyku. Ognisko przyznaje nagrodę i oznacza odbiór
   dla konkretnego podejścia (id podejścia) — ponowne kliknięcie i reconnect nie wypłacają drugi raz.
   Los reliktów osobno od grzybów: zachowanie całego koszyka po celowej porażce byłoby darmowym
   ubezpieczeniem zamiast płatnego ratunku (rescue).
3. **[P2] Modyfikatory a grupa.** Dwóch graczy w tej samej fizycznej komorze nie może mieć różnej wody.
   Podejście = solo albo **jawnie utworzona grupa** z jednym układem i modyfikatorem, nagrody osobiste.
   Pomoc, podnoszenie i bonus latarni (`Expedition.luau`, dziś po odległości) muszą sprawdzać przynależność
   do podejścia.
4. **[P2] Kolekcja ma koniec, zlew nie ma liczb.** Dopisać koszt renowacji, przelicznik duplikatów → odłamki,
   cenę złożenia brakującego reliktu i zastosowanie odłamków po skompletowaniu. 8 reliktów wystarczy do
   sprawdzenia zabawy, ale **nie jest to jeszcze trwałe rozwiązanie nadwyżek**.

## Decyzje (zatwierdzone przez Toma 3.11, propozycje Codexa)
1. Zlecenia: **prywatne podejście solo albo dla zaproszonej grupy**, bez wspólnego łupu na serwer.
2. Limit: **bez limitu** zwykłych ekspedycji (limit 3 nagród kończyłby zabawę po 30–45 min);
   zlecenie dnia rozliczane raz dziennie.
3. Trofea: **prosty regał w ogródku jako pierwszy etap gabloty**, na tej samej kolekcji reliktów.
4. Wejście: **Otchłań** — wcześniejsze odkrycie, z dala od skarbca Skarbnika i portalu na Bagna.

## Ryzyka do sprawdzenia (nie zakładamy z góry)
- **Balans**: osobna odnoga nie gwarantuje braku wpływu. Grzyby zbierane po drodze, szczęście (nożyk,
  głębokość, mikstura, Wysyp) i premie mogą dać nowe źródło monet. Do sprawdzenia w `tools/economy_sim.luau`
  i testach: ile monet/min daje ekspedycja vs zwykłe zbieranie w Kopalni.
- **Obciążenie serwera**: StreamingEnabled oszczędza tylko klienta. Pułapki, woda, patrol, kryjówki per gracz
  liczy serwer — zmierzyć przy 6 graczach (Studio: kilku testowych klientów).
- **Bezpieczeństwo**: serwer prowadzi stan zlecenia (komora, zabezpieczenie, nagroda); klient tylko pokazuje.
  Odbiór nagrody raz, z walidacją pozycji i czasu (`docs/REVIEW.md`).
- **Zapis**: nowe pola w DataService (relikty, odłamki, ranga, dzienny licznik) z migracją domyślną.

## Co mierzymy w pilotażu
- ile osób bierze zlecenie, ile kończy, mediana i p90 czasu,
- ile idzie do Krypty i ile tam przegrywa,
- powroty: kolejna ekspedycja w tej samej sesji, D1, D7,
- monety wydane na renowację vs monety zarobione w ekspedycji.

Jeśli gracze wracają: kolejne komory i zlecenia w jaskini, potem bagna (mgła i woda otwierające różne przejścia,
tropy Utopca, zatopione skrytki — zawsze z jakimś osiągalnym celem przy zamkniętej ścieżce).

## Wdrożenie (gałąź `ekspedycja`, 3.11)

Kod: `src/shared/Delve.luau` (liczby i czysta logika, testy w `tests/economy.spec.luau`),
`src/server/DelveService.luau` (przebieg, nagrody, zagrożenia, regał), `src/server/World/DelveMap.luau`
(tablica, szczelina, kopie komór), `src/client/DelvePanel.luau` (tablica i kolekcja), `src/client/DelveHud.luau`
(karta celu). Panel DEV: „TP: szczelina” (też na żywo) i „Ekspedycja: od razu do komór” (Studio).

- **Wejście:** tablica w Obozie (x 30, z 1028), szczelina w ścianie Otchłani za lawą (x 42, z 1398).
  Bez zlecenia szczelina mówi, żeby wziąć zlecenie. W pościgu strażnika nie da się zejść.
- **Kopie komór:** 6 (tyle graczy mieści serwer), budowane przy pierwszym użyciu, w bok od jaskini
  (x od 400 co 450, z 1338–1382 = Otchłań, więc świat jaskini: budzi w obozie, mrok jaskini). Odstęp między
  kopiami ~200 studs > zasięg pomocy kumpla (150), więc różne ekipy się nie łączą.
- **Ekipa:** solo albo do 4 osób, dołączenie tylko przy tablicy przed zejściem. Zlecenie czeka 10 min,
  ekspedycja trwa najwyżej 25 min. W komorach nie da się zrezygnować (to byłby darmowy powrót do obozu z koszykiem).
- **Olej:** w komorach pełna latarnia starcza na 240 s bez względu na poziom oleju (Kryształowy wkład wydłuża
  do 480 s), brodzenie w wodzie ×2,5, wspólne latarnie działają. Haki z olejem: sala wejściowa, wejście do
  Zalanej Komory, ognisko. Osuwisko w Chodniku: −15% oleju (nigdy do zera), co ~3,5 s (przy „Osuwiskach” ~2 s).
- **Zlecenia:** Zawalony szyb (3 kupki gruzu), Zaginiona skrzynia (1 z 4 kryjówek), Świecące próbki (3 z 6 miejsc,
  co najmniej jedna za zawałem). Zawał w Chodniku do odgruzowania zawsze (4 s, przy „Osuwiskach” 6 s).
- **Stan komór:** spokojne / wysoka woda (od rangi 0), osuwiska (ranga 1+), czuwający Skarbnik (ranga 2+);
  dwa ostatnie dają +2 odłamki.
- **Znalezisko i trofeum:** zajmują 1 miejsce w koszyku (bez miejsca znalezisko zostaje na ziemi). Ognisko przyznaje
  nagrodę każdemu z ekipy w komorach od razu do zapisu (raz na osobę). Zgaśnięcie / złapanie = zwykłe pochłonięcie
  (koszyk jak wszędzie); niesione znalezisko i trofeum wracają na miejsce dla reszty ekipy.
- **Krypta:** drzwi otwierają się po zabezpieczeniu. Strażnik (model Skarbnika) chodzi po trasie, widzi z bliska
  (4,5) i w stożku przed sobą (11, czuwający 15), we wnękach nie widzi. Zauważony = pościg, złapany = pochłonięcie.
  Trofeum wyniesione za drzwi: każdy z ekipy dostaje relikt z losowego zestawu i +4 odłamki.
- **Relikty:** 2 zestawy po 4 (3 zwykłe, 1 rzadki 1/10). Duplikat: 3 / 8 odłamków. Składanie: 12 / 30 odłamków.
  Renowacja: 50 000 / 150 000 monet. Oprawy: brąz 500 000 + 5, srebro 1,5 mln + 10, złoto 5 mln + 20 odłamków.
  Cała kolekcja to ~57 mln monet zlewu. Zlecenie dnia: ten sam relikt dla wszystkich danego dnia (raz dziennie).
- **Ranga i tytuły:** punkty = zabezpieczone ekspedycje + trofea z Krypty (progi 3/8/15/25/40). Tytuły:
  Ekspedytor (5 ekspedycji, rzadki), Łupieżca Krypty (10 trofeów, epicki).
- **Regał:** w każdym ogródku (prawy przedni róg), odnowione relikty stoją na nim z kolorem oprawy; przycisk
  przy regale otwiera kolekcję (tylko właścicielowi).

Do sprawdzenia w Studio: czas jednej ekspedycji (cel 10–15 min), czy 240 s oleju na odcinek nie jest za dużo /
za mało, czy strażnik nie jest za ostry, wygląd komór i karty celu, obciążenie przy kilku kopiach naraz.
