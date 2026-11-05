# Balans szans Kuźni Grzybów

> Dotyczy wersji 2 (skucha / zwykły / szczęście). Od 5.11 obowiązuje runa (wersja 3): zasady i liczby
> w [planie Kuźni](kuznia.md), sekcja „Stan wdrożenia — wersja 3”.

Gałąź `kuznia`, zasady z sekcji „Stan wdrożenia — wersja 2” w [planie Kuźni](kuznia.md).
Kolumna „Po” pokazuje przetestowaną propozycję. **Wprowadzone do gry** (sekcja „Decyzja” na końcu).
EV oznacza średnią wartość sprzedaży wyniku podzieloną przez wartość wkładu i opłatę łącznie, według cen bazowych.

## Przed i po

| Parametr | Przed | Po | Uzasadnienie |
| --- | ---: | ---: | --- |
| Skucha | 25% | 30% | Prawie co trzecia próba oddaje tylko jeden okaz, bez cech i w najniższej randze wkładu. |
| Zwykły | 65% | 62% | Łączenie cech pozostaje najczęstszym wynikiem. |
| Szczęście | 10% | 8% | Awans średnio raz na 12,5 prób, gdy wylosowany okaz może awansować. |
| Opłata od wartości wkładu | 25% | 30% | Większy margines dla cennych trójek i kumulacji cech. |
| Minimalna opłata | 25 | 25 | Zachowuje koszt najtańszych prób. |
| Trafienie gatunku z przepisu lub trójki strażników | 75% | 70% | Średnio 1,43 zamiast 1,33 próby na trafienie przy gotowych zestawach. |

| Gatunek | Wartość przed | Wartość po | Najwyższe EV przed → po w skrypcie |
| --- | ---: | ---: | ---: |
| forge_mossbell | 1 050 | 1 050 | 0,950 → 0,848 |
| forge_emberpearl | 4 700 | 4 700 | 0,937 → 0,835 |
| forge_glasscap | 3 800 | 3 800 | 0,939 → 0,838 |
| forge_runemorel | 39 700 | 39 700 | 0,917 → 0,811 |
| forge_mooncoral | 52 600 | 52 600 | 0,914 → 0,808 |
| forge_eclipsestar | 36 000 | 36 000 | 0,916 → 0,812 |
| Kwiat Paproci | 50 000 | 50 000 | 0,940 → 0,842 |
| Oko Welesa | 150 000 | 150 000 | 0,958 → 0,857 |

Dla sześciu receptur zwykły wynik z podstawowych składników z wymaganymi cechami jest wart 1,20–1,21× samego wkładu. Zachowałbym te ceny, bo nagradzają skompletowanie przepisu, a nawet najlepsza z 125 kombinacji rang dla każdego przepisu ma EV poniżej 0,85 po zmianie. Szczyt wypada dla trzech złotych składników. Mieszane rangi obniżają wynik przez regułę minimum.

Tęczowy Kwiat jest wart 400 000 przy wkładzie 329 760 przed opłatą. Tęczowe Oko jest warte 1 200 000 przy wkładzie od 969 760 do 1 248 000. Zachowałbym obie ceny. Pozostałe dwie trójki Oka mają po zmianie maksima EV 0,707 i 0,683, więc koszt wejścia zależy mocno od doboru strażników. Kosmiczna forma z trzech tęczowych strażników kosztuje średnio 12,5 prób. Przy samych kosmicznych strażnikach każdy wynik poza skuchą jest kosmiczny.

## Formy w Grzybopedii

Dla trójki jednego gatunku w tej samej randze, poza pasującym przepisem, brutto potrzeba średnio 3/p sztuk niższej rangi. Jeśli gracz ponownie używa zwrotu z każdej nieudanej próby, zużywa netto średnio 2/p + 1 sztuk. Opłata nadal jest pobierana przy każdej próbie.

| Forma | Kuźnia brutto przed → po | Kuźnia netto przed → po | Niższa ranga na jedną wyższą przy bazowych szansach zbierania |
| --- | ---: | ---: | ---: |
| Srebrna | 30 → 37,5 | 21 → 26 | 16,7 według skryptu, 15,2 dla dokładnej formy podstawowej |
| Złota | 30 → 37,5 | 21 → 26 | 2,4 |
| Tęczowa | 30 → 37,5 | 21 → 26 | 6,25 |
| Kosmiczna | 30 → 37,5 | 21 → 26 | 5,0 |

Dla srebra skrypt przyjmuje 100% dla niższej rangi. Dokładna forma podstawowa ma 91,02% po odjęciu wszystkich wariantów. Proporcje zbierania opisują bazowe losowania, bez gwarancji rang i premii. Kuźnia nadal pomaga celować w konkretny gatunek i zużyć zapas duplikatów. Można też wrzucić jeden pożądany okaz i dwa tanie, wtedy awans celu ma szansę p/3 na próbę. Na tych danych wspólne 8% wystarcza także dla wysokich rang. Osobna szansa zależna od rangi wymagałaby zmiany logiki. Osiem gatunków kuźni ma własną kolekcję, a wyniki zwykłych gatunków mogą uzupełniać ich formy w atlasie.

## Ryzyka ekonomiczne

W 80 000 wylosowanych trójkach z wypraw skrypt znalazł zero kombinacji z EV ≥ 1 w obu ustawieniach. Najwyższy wynik w tej próbie spadł z 0,750 do 0,664. Dla drogiego grzyba z dwiema świeżymi cechami maksimum spadło z 0,969 do 0,852. Samo 0,969 oznacza mały margines straty dla konkretnego testu, przy znacznej zmienności pojedynczych wypłat.

**Wielokrotne łączenie cech daje dodatni EV.** Zwykłe gatunki z Kuźni można użyć ponownie. Dodatkowy pomiar na rzeczywistym `Forge.expectedValue` użył tęczowego `night_eye`, `ember` z cechami mossy/glowing/crystal/abyssal i `earthstar` z cursed/hexed/moonlit. EV wyniosło **1,792 przed i 1,574 po**. Po zmianie wkład to 562 500, opłata 168 750, średni wynik 1 150 650. Wyhodowanie dawców przez poprzednie losowania ma własny koszt. Ten pomiar dowodzi dodatniego zwrotu pojedynczej operacji dla posiadanych dawców, a rentowność całego cyklu od surowych grzybów pozostaje niepoliczona. Premie sprzedaży i użytkowa wartość wielocechowych okazów w ogródku pozostają poza tym EV.

Dla samego przykładu po zmianie potrzeba opłaty około 105% wkładu do zrównania EV z 1. Taki próg obciążyłby również wszystkie proste przepisy i nie stanowi gwarancji dla innych zestawów. Rekomenduję 30/62/8 i 30% jako strojenie typowych prób. Jeśli warunkiem wydania jest EV poniżej 1 dla każdego legalnego wkładu, ta propozycja go nie spełnia.

## Weryfikacja

`lune run tools/forge_odds.luau` uruchomiono dla obu ustawień. `lune run tests/economy.spec.luau` dało w obu przypadkach **1114 OK, 0 błędów**. Próbne wartości wprowadzono na czas pomiaru i przywrócono plik konfiguracji po testach.

## Decyzja (wprowadzone na gałęzi `kuznia`)

- Szanse 30 / 62 / 8 i opłata 30% wartości wkładu (min 25) — jak w propozycji. Ceny ośmiu gatunków bez zmian.
- Luka z wielokrotnym łączeniem cech zamknięta inaczej niż podniesieniem opłaty dla wszystkich:
  opłata rośnie tylko dla trójek, których średni wynik przekroczyłby 90% (wkład + opłata)
  (`Config.Forge.maxReturn = 0.9`, `Forge.preview`). Przykład z raportu: wkład 562 500, opłata 716 001
  zamiast 168 750, EV 0,900. Zwykłe trójki i przepisy płacą 30%.
- Test `kuźnia: wiele cech doklejonych do drogiego grzyba podnosi opłatę` i warunek EV ≤ 0,9
  dla wszystkich kombinacji rang przepisów i strażników w `tests/economy.spec.luau`.
