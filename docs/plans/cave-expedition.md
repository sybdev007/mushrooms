# Ekspedycja do Głębokich Komór (jaskinia) — projekt pilotażu

Stan: 3.11.2026. Projekt, nie gotowa funkcja. Powstał z rozmowy Tom + Claude + uwagi Codexa
(`economy-sinks-and-offers-research.md`). Do review przez Codexa przed budową.

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

## Do ustalenia (decyzje Toma)
1. Zlecenia **osobne dla każdego gracza** (proponowane: brak podbierania i kamperów) czy wspólne na serwer.
2. Limit dzienny: bez limitu czy np. 3 nagrody dziennie + zlecenie dnia.
3. Gdzie trofea: od razu w gablocie (pierwszy krok wystaw) czy na razie osobny regał w ogródku.
4. Wejście: Otchłań czy Kopalnia.

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
