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
