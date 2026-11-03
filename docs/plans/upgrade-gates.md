# Etap 1 — ulepszenia odblokowywane wraz ze światami

Stan: 3 listopada 2026. Gałąź `feat/upgrade-gates`. Reguły zapisane przed implementacją.

## Reguły

- Buty zachowują bazę 16 i przyrost 1.5. Kolejne poziomy rozkładamy na światy.
- Olej i koszyk używają tego samego mechanizmu. Pozostałe ulepszenia zachowują obecne sklepy.
- Odblokowanie oznacza zapisany dostęp do świata a nie bieżące saldo monet.
- Nowy poziom wymaga dostępu do odpowiedniej mapy oraz bezpiecznego obozu tej mapy lub późniejszej.
  Niższe poziomy można dokupić w późniejszym obozie. Własne ulepszenia mapowe nadal mają jeden sklep.
- Te trzy karty występują w każdej zakładce. Kłódka podaje wymaganą mapę. Klient nie przyznaje poziomów.
- Starsze już kupione poziomy pozostają aktywne nawet ponad nowym limitem aktualnie otwartej mapy.
  Blokujemy tylko następny zakup. Nie odblokowujemy automatycznie map.

## Liczby startowe do strojenia symulatorem

| Ulepszenie | Las | Jaskinia | Bagna / maksimum | Statystyka | Cena startowa / wzrost |
|---|---:|---:|---:|---|---|
| Buty | 4 | 8 | 12 | 16 + 1.5 × poziom: 22 / 28 / 34 | 35 / 2.8 |
| Olej | 8 | 11 | 14 | 30 + 12 × poziom: 126 / 162 / 198 | 20 / 2.5 |
| Koszyk | 6 | 10 | 14 | 5 + 3 × poziom: 23 / 35 / 47 | 15 / 2.5 |

Koszt kolejnego poziomu pozostaje `floor(costBase × costGrowth^poziom + 0.5)`.
Próg jaskini 30 000 i bagien 1 000 000 pozostaje bez zmian. Wzrosty cen są hipotezą;
wynik symulacji i końcowe liczby należy dopisać przed oddaniem etapu.

Prędkość maksymalna przed pierwszym wejściem: las 16; jaskinia 22; bagna 28.
W danym świecie dostępne jest odpowiednio 22 / 28 / 34. Test liczy najniższy poziom
ucieczki przez `Economy.escapes` i rzeczywistą drogę z `Progress.escapeDistance` dla
Leszego 22 / Skarbnika 25 / Utopca 27.5. Każdy próg musi mieścić się w limicie jego świata.

## Zapis i migracja

Wersja danych 5 → 6. Nie potrzeba nowej waluty ani dodatkowych pól profilu: poziomy
i `caveUnlocked` / `swampUnlocked` już istnieją. Migracja zachowuje numer każdego
poprawnego kupionego poziomu oraz wszystkie inne dane. Nowe maksima są wyższe od starych.
Odrzucamy niefinitywne wartości poziomów zamiast zamieniać nieskończoność w darmowe maksimum.
Nie resetujemy monet ani ekwipunku. Test migracji obejmuje stary maksymalny zapis bez otwartych map.

## Serwer i ryzyka

- Wspólne czyste funkcje określają wymaganą mapę i dozwolone obozy dla następnego poziomu.
- `BuyUpgrade` sprawdza typ ID i limit oraz otwarcie mapy i pozycję przed odjęciem monet.
  Klient nie przesyła ceny ani docelowego poziomu. Zakup nie może się zatrzymać między odjęciem ceny a przyznaniem poziomu.
- Położenie ma uwzględniać obszar bezpiecznego obozu także w osi X; samo Z nie wystarcza.
- DEV dostaje scenariusze limitów lasu / jaskini / bagien dostępne wyłącznie w Studio i dla DEV.
- Wzrost prędkości wpływa też na kradzieże i czas przejścia. Nie zmieniamy reguł łupu ani płatnych produktów.
- Model pomija m.in. śmierć i kradzieże oraz bonus atlasu. Nie jest prognozą retencji.
- Trzy kolejne etapy mogą zwiększyć dochód. Rebirth wymaga ponownego strojenia po etapach 2–4.

## Weryfikacja i odbiór

Testy Lune: blokada bez wymaganej mapy także z wystarczającymi monetami; kolejne progi;
starsze poziomy bez degradacji; brak darmowych nowych poziomów; każdy boss osiągalny;
zakup w dozwolonym obozie; lokalizacja EN/PL bez przecinków. Symulator używa tych samych bramek
także przy analizie kilku przyszłych zakupów. Dodatkowo `selene src` i `rojo build`.

Studio Play: scenariusze DEV; odmowa zakupów w terenie i przy zamkniętej mapie; zakup w odpowiednim obozie;
wygląd kart i zakładek na telefonie; ucieczki od wszystkich trzech bossów; ponowne wejście ze starym zapisem.
Ten czat nie ma narzędzia sterowania Studio. Nie oznaczać Play jako zaliczonego bez rzeczywistego testu.

## Wynik implementacji i liczby

Zachowano liczby z tabeli startowej. `lune run tools/economy_sim.luau`:

| Punkt | Main przed zmianą | Etap 1 |
|---|---:|---:|
| Jaskinia | 56 min | 1 h 31 min |
| Bagna | 1 h 53 min | 2 h 47 min |
| Modelowane ulepszenia dochodowe | 3 h 41 min / 70 poziomów | 5 h 53 min / 82 poziomy |
| Dochód końcowy modelu | 127 844 monet/min | 170 449 monet/min |

Koszt wszystkich nowych poziomów butów: 4 515 335 monet; oleju: 4 967 041; koszyka: 3 725 280.
To wydłużenie podstawowej progresji a nie trwałe rozwiązanie inflacji. Wyższe statystyki zwiększają
końcowy dochód; kuźnia i rebirth muszą zostać osobno przeliczone na tej bazie. Dostęp do jaskini
po około 91 minutach jest ryzykiem dla D1 i wymaga obserwacji zamiast deklaracji poprawy retencji.

Test pościgu: Leszy od butów 3 (20.5) przy leśnym limicie 4; Skarbnik od 5 (23.5) przy
jaskiniowym limicie 8; Utopiec od 8 (28) przy bagiennym limicie 12. Nie zmieniono parametrów bossów.
Niższa prędkość od prędkości potwora może wystarczyć dzięki opóźnieniu pobudki i dystansowi do obozu.
Testy oleju używają limitów dostępnych PRZED otwarciem kolejnej mapy a nie globalnego maksimum.

## Jak sprawdzić w DevPanel

Nowe przyciski działają wyłącznie w Studio i dla DEV. Zmieniają testowane poziomy oraz odblokowania
i ustawiają 100 mln monet. Nie używać ich do oceniania tempa zwykłej gry.

1. **Bramki: limit lasu** — buty 4 / olej 8 / koszyk 6; obie dalsze mapy zamknięte; teleport do chatki.
   Trzy kolejne poziomy pokazują kłódkę i odblokowanie jaskini mimo dostępnych monet.
2. **Odblokuj jaskinię** i **TP: obozowisko** — karty są w zakładce jaskini; da się kupić następny poziom.
   Próba zakupu tych samych wyższych poziomów przy chatce odsyła do właściwego obozu.
3. **Bramki: limit jaskini** — buty 8 / olej 11 / koszyk 10; następne poziomy wymagają bagien.
4. **Odblokuj bagna** i **TP: przystań (bagna)** — następne poziomy można kupić.
   **Bramki: limit bagien** ustawia 12 / 14 / 14 i każda karta pokazuje MAX.
5. **Bramki: stary maksymalny zapis** — imituje stare kupione 8 / 10 / 10 przy zamkniętych mapach.
   Statystyki zostają a kolejne zakupy wymagają właściwych map. Rzeczywiste ładowanie v5 → v6
   jest osobno testowane w Lune z DataService i atrapą ProfileStore bez kontaktu z DataStore Roblox.
6. Sprawdzić telefon oraz EN/PL: brak zdublowanych kart; wszystkie znaczniki 12/14 poziomów mieszczą się;
   kłódka wskazuje mapę; otwarty panel odświeża się po odblokowaniu mapy. Sprawdzić brak zakupu w terenie.
7. Reset ulepszeń oraz zakup butów do poziomu 3 / 5 / 8 i ucieczki przed odpowiednimi bossami.
   Zmierzyć także drogę i olej na faktycznych przeszkodach; model pościgu nie zastępuje Play.

Pełny `selene src` ma dwa zastane błędy `if_same_then_else` w `SettingsButtons.luau` i `CutsceneKit.luau`.
Nie należą do tego etapu. Weryfikować osobno brak błędów we wszystkich zmienionych modułach.
Play w Studio pozostaje niewykonany z powodu braku narzędzia sterowania aplikacją w tym czacie.
Nie scalać ani publikować tej gałęzi jako przetestowanej w Play.

Weryfikacja końcowa: **764 testy Lune zaliczone**; `rojo build` poprawny; `git diff --check` poprawny.
Selene zmienionych modułów: **0 błędów / 37 ostrzeżeń / 0 błędów parsowania** (kod zakończenia 1
ze względu na ostrzeżenia). Pełny przebieg `selene src`: 2 zastane błędy wskazane powyżej.
