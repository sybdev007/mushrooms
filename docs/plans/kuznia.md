# Kuźnia Grzybów — projekt Moździerza Zielarki

Status: **wdrożone na gałęzi `kuznia`** (4 listopada 2026) w lżejszej wersji — patrz „Stan wdrożenia” niżej.
Pierwotnie: propozycja do decyzji Toma (analiza Codexa, 4 listopada 2026).
Baza: `lysa-gora`, commit `a59487f10d96a2d7caf81965c02b591723597133`; gałąź dokumentu: `kuznia-plan`.
Wartości oznaczone jako stan wynikają z tej rewizji; wszystkie receptury, opłaty i ograniczenia kuźni są propozycją.

**Rekomendacja:** stała maszyna „Moździerz Zielarki” na Placu Portali. Trzy określone grzyby i opłata dają
jeden nowy gatunek z dwiema połączonymi cechami. Gatunek, cechy i wariant są znane przed zapłatą:
wariant wyniku jest najsłabszym wariantem składników. Sześć gatunków wyłącznie z kuźni, osobna kolekcja,
bez dochodu z ogrodu, suszenia, ponownego wkładania i bonusów płatnych produktów. To cel na zbieranie
konkretnych okazów i wydawanie nadwyżki monet. Maszyna nie emituje monet przy tworzeniu.

## Stan wdrożenia (gałąź `kuznia`) — wersja 2 (losowanie z ekwipunku)

Decyzje Toma (4.11, druga runda): do moździerza wrzucasz z ekwipunku **dowolne 3 grzyby**, kręci się
bęben i wychodzi **losowy grzyb z tych trzech z połączonymi cechami**. Może być **skucha** (gorszy grzyb),
**mała opłata** (25% wartości wrzuconych), 6 gatunków zostaje jako **ukryte przepisy**, a trzy tęczowe
grzyby strażników dają **mitycznego** albo **sekretnego** grzyba tylko z kuźni. Szanse ma sprawdzić Codex.

Zasady (`Config.Forge`, `src/shared/Forge.luau`):

| Wynik | Szansa | Co wychodzi |
|---|---|---|
| Skucha | 25% | losowy z trzech, **bez cech**, z najsłabszym wariantem z trzech |
| Zwykły | 65% | losowy z trzech (ze swoim wariantem) + **wszystkie cechy** trzech grzybów |
| Szczęście | 10% | jak zwykły, wariant **o rangę wyżej** (najwyżej kosmiczny) |

- **Ukryte przepisy** (6, dowolna kolejność): w „zwykłym” i „szczęściu” zamiast losowego wychodzi gatunek
  z kuźni (wariant = najsłabszy z trzech, w szczęściu o rangę wyżej; cechy połączone). Skucha jak wyżej.
  Wartość wyniku ok. 1,2× składników. Przepisy działają od Bagien / Łysej Góry / ucieczki Jadze.
- **Trójki strażników**, każdy co najmniej tęczowy: Leszy + Skarbnik + Utopiec → **Kwiat Paproci**
  (mityczny); Baba Jaga + dwóch z nich → **Oko Welesa** (sekretny). Nowe klasy `Config.SpecialClasses`.
- Grzybów z kuźni nie da się posadzić ani wrzucić z powrotem; suszonych i dyniowych (event) też nie.
- Okno: ekwipunek (siatka grzybów z koszyka), trzy miejsca, szanse i animacja bębna, który skacze po
  wrzuconych grzybach i staje na wylosowanym. Komunikaty o wyniku przychodzą dopiero po animacji.
- Grzybopedia: zakładka „Kuźnia” (8 gatunków) z podpowiedziami do nieodkrytych; tytuły Uczeń Zielarki,
  Mistrz Kuźni (6 przepisów), Znalazca Kwiatu Paproci, Wybraniec Welesa.
- Bez nowej wersji zapisu: połączenie jest atomowe w pamięci sesji ProfileStore, jak sprzedaż.
- Balans: `lune run tools/forge_odds.luau` (EV/(wrzucone+opłata) dla przepisów, strażników, losowych
  trójek z wypraw, dokładania cech i form do Grzybopedii). Testy: `tests/economy.spec.luau` (kuźnia).

Główny komplet to **6 gatunków w dowolnej formie**; na bagnach dostępne są pierwsze 3. Pozostałe formy
są opcjonalną kolekcją. Model pokazuje około **54 min na 3 gatunki po bagnach i 92 min na 6 po górze**,
przy zerowym zapasie materiałów i monet. Nie obiecujemy szybkiego kompletu kosmicznego: model celowanego
zbierania daje około 198 godzin na wszystkie 30 dokładnych form. Nie wiązać z tym obowiązkowych nagród.

## 1. Stan zastany i konsekwencje

Przeczytano: `docs/plans/lysa-gora.md`, `docs/plans/monetization-research.md`, `docs/HANDOFF.md`,
`docs/REVIEW.md`, `Config`, `Economy`, `Progress`, `Titles`, `Achievements`, ścieżki koszyka/sprzedaży/DEV/
kruków/strażników w `GameService`, wczytywanie i zapis w `DataService`, `MushroomView`, `MushroomArt`,
`HalloweenService`, `CauldronView`, `tools/economy_sim.luau`, `tests/economy.spec.luau`.
Dodatkowo sprawdzono integracje `ProgressService`, `GardenService`, `MapBuilder`.

| Stan w kodzie | Wniosek dla kuźni |
|---|---|
| Warianty: zwykły ranga 0 ×1; silver 1 ×1,5; gold 2 ×3; rainbow 3 ×8; cosmic 4 ×20 | Jeden wariant na okaz. Nie mnożymy wariantów i nie awansujemy trzech złotych do tęczy. |
| Cechy: mossy ×1,5; glowing/crystal/cursed ×2; abyssal/hexed ×2,5; moonlit ×3; pumpkin ×2 | Cechy dodają swoje nadwyżki, nie mnożą się między sobą. |
| `mutationMultiplier = variantMult × (1 + Σ(tagMult − 1))` | Dwie najsilniejsze różne cechy dają maks. ×4,5; z cosmic ×90. Trzy cechy cursed+hexed+moonlit dałyby ×110. |
| `BasketItem = {s,v,x,d}`; `x` jest listą | Wielocechowość nie wymaga nowego formatu listy mutacji. |
| `DataService.readMutations` uznaje wszystkie znane tagi i usuwa duplikaty; nie porównuje stref ani nie ustala limitu liczby | **Tak: koszyk i ogród zachowają cechy z różnych stref.** Sam zapis nie zabezpiecza limitu kuźni. |
| `Economy.plantIncome = itemValue × 0,04 × fertilizer`; nawóz maks. ×3 | Najdroższy proponowany kosmiczny wynik dawałby 151 200/min, gdyby dopuścić sadzenie. Zakaz jest istotną częścią balansu. |
| Suszarnia została usunięta; `d` 1–2 istnieje dla starych zapisów, `raw.drying` migruje do grządek | Nie tworzymy suszarni. Nie przyjmujemy starych suszonych okazów z `d>1`. |
| `Progress.PAGES` zawiera 4 światy; maski form używają `2^rank`; progi nagród stron kończą się na randze 3 | Kuźnia potrzebuje osobnej strony kolekcji bez nowych bonusów sprzedaży. |
| **`DataService.reconcile` nadal przycina maskę atlasu do 15** | Błąd zastany: cosmic potrzebuje bitu 16, pełna maska wynosi 31. Wczytanie 16 jako 15 gubi cosmic i może dopisać niższe formy. Poprawka przed wydaniem kuźni. |
| `ProgressService.found` aktualizuje ranking najlepszego znaleziska niezależnie od `source`; nowe odkrycie daje zdarzenie `discover` | Samo `found(...,"forge")` nie izoluje rankingu ani zadań. Potrzebna osobna ścieżka źródła. |
| `Economy.rollSpecies` ma fallback do ostatniej pozycji listy | `weight=0` nie jest wystarczającą gwarancją wyłączności. Gatunki kuźni wykluczyć z budowy pul. |
| `DataService` używa ProfileStore i blokady sesji. `save()` tylko zleca zapis; `confirmSaved()` czeka na zapis receipt | Kuźnia potrzebuje potwierdzenia własnego numeru operacji, nie udawanego paragonu Robux. |

Nie używać starych cen z pierwszej tabeli planu Łysej Góry: aktualnie `witch_hat=9500`, `night_eye=52000`,
`jaga_toadstool=115000`, próg góry **10 mln**, `rewardScale(mountain)=520000` monet. Próg portalu to
w obecnym modelu wymagane saldo, nie wydatek odejmowany przy otwarciu. Handoff i stare raporty mają starsze
czasy progresji; niżej podano nowy przebieg z aktualnego symulatora.

## 2. Trzy warianty mechaniki

| Wariant | Zasada | Plusy | Minusy | Decyzja |
|---|---|---|---|---|
| A. Swobodne łączenie | Dowolne 3 okazy; gatunek jednego z nich i dwie wybrane cechy z sumy wejść | Dużo eksperymentowania; proste pierwsze użycie | Tani cosmic i dwa tanie nośniki cech mogą wzmacniać drogi gatunek; wiele kombinacji i wyjątków; słabszy powód powrotu do konkretnych stref | Nie na v1. Wymaga osobnego ograniczenia wartości dla każdej kombinacji. |
| B. Losowanie z wagami | Określona receptura; np. 80% najniższej rangi i 20% najwyższej rangi wejść, gatunek stały | Napięcie i powtarzalność prób | Utrata rzadkich okazów; płatne szczęście i pośrednie finansowanie wymagają ostrożnego projektu; EV nie chroni ogrodu przed jackpotem | Odrzucić na start. 80/20 to porównywany wariant, nie aktywne szanse v1. |
| C. Receptury gatunków + składanie mutacji | 3 wskazane gatunki; 2 wymagane cechy; stały gatunek wyniku; minimum rang wejść | Zrozumiałe 100%; nie trzeba powtarzać po porażce; kontrola EV; zachęta do wypraw na starsze mapy | Mniej losowości w samej maszynie; kolekcja kosmiczna bardzo długa; skończona liczba celów | **Rekomendowany.** Niepowtarzalność pochodzi z polowania na składniki i wyglądu hybrydy. |

Dla B rozkład przy równych rangach składa się do jednego wyniku 100%; przy różnych
`EV = 0,8 V(minRank) + 0,2 V(maxRank)`. Na recepturze R6 z wejściami cosmic/rainbow/gold z przykładu poniżej:
80% złoty 189000 i 20% kosmiczny 1260000 → EV **403200**, czyli 45,30% wejścia 890000.
To tylko jeden przypadek, nie dowód bezpieczeństwa B dla wszystkich wejść; v1 używa C.

## 3. Miejsce, nazwa, dostępność i rytm

**Nazwa UI: „Moździerz Zielarki” / „Herbalist's Mortar”**, nagłówek kolekcji „Kuźnia Grzybów” /
„Mushroom Forge”. Kamienny moździerz z miedzianymi obejmami, tłuczkiem i trzema miseczkami na grzyby.
Dwa strumienie zarodników oplatają tłuczek i tworzą nowy okaz. Zieleń mchu + fiolet run, drewno PanelKit.
Bez przemysłowego pieca i bez kopiowania dyniowego kotła Halloween.

Alternatywy: „Kuźnia Zarodników” (bardziej magiczna), „Moździerz Baby Jagi” (mocniej związany z górą).
Druga nazwa myli przyjazną usługę z bossem; preferujemy Zielarkę. Obiekt stoi na bocznym skraju Placu
Portali, w bezpiecznej strefie chatki. W `buildPortalPlaza` zarezerwować osobny obszar ok. 10×10 studs,
poza przejściem i fundamentami przyszłych portali; finalne współrzędne ustalić po obejrzeniu mapy w Studio.
Nie stawiać go przy ogródku Jagi: nie ma służyć ratowaniu koszyka podczas pościgu.

- Receptury R1–R3: ukończony tutorial i `swampUnlocked`. To dostęp po wejściu na bagna, **nie przymus
  wykupienia każdej kosmetycznej kategorii ulepszeń**. Duże opłaty czynią z niego opcjonalny cel po progresji.
- R4–R6: dodatkowo `mountainUnlocked`. R6 wymaga choć jednej zapisanej ucieczki przed Jagą; status
  `bestiary.jaga.escaped>=1`. Nie wymaga ponownej walki przy każdym tworzeniu.
- Podgląd wszystkich receptur od początku; dokładne brakujące warunki są widoczne.
- Nie ma opłaty za samo odblokowanie maszyny, kolejki wspólnej dla serwera, biletów, darmowego dziennego
  losowania ani przyspieszania za Robux. Każdy z 6 graczy korzysta niezależnie.
- Opłata za każdą recepturę w tabeli; mnożnik zależy od gwarantowanej rangi wyniku.
- Animacja 4 s; odstęp między zatwierdzeniami **10 s na konto**, zapisany jako `nextAt`. Następna operacja
  wymaga też potwierdzenia zapisu poprzedniej. Brak wielominutowego oczekiwania i odbioru następnego dnia.
- Zamknięcie UI nie anuluje zatwierdzonej operacji. Animacja nigdy nie wywołuje przyznania przedmiotu.

## 4. Dokładne reguły v1

### 4.1. Wejścia i wynik

Gracz wybiera recepturę i dokładnie **3 różne pozycje własnego koszyka**. W kolejności dowolnej muszą
pasować do trzech gatunków receptury. Dwie pozycje mają przypisaną wymaganą cechę. Nie wystarczy
przynieść tej cechy na innym gatunku. Trzecia pozycja nie wymaga cechy. Dodatkowe zwykłe cechy są
akceptowane, ale zostają utracone; UI pokazuje je jako nieprzenoszone. Odrzucamy wejścia z `pumpkin`,
nieznanymi tagami, niedozwolonymi danymi, `d>1`, gatunkiem kuźni lub `mimic=true`.

Gatunki receptury są różne, dlatego dopasowanie jest jednoznaczne. Żaden wymagany składnik nie jest
łupem strażnika. Nie przyjmujemy przedmiotów niesionych w scence kradzieży ani z escrow ratunku;
muszą już rzeczywiście być w koszyku. Nie ma pobierania bezpośrednio z grządki ani z Grzybopedii.

Dla wejść `i=1..3`:

- `r = min(variantRank(v_i))`; zwykły to 0. `v_out = variantOfRank(r)`.
- `x_out = dokładnie dwa różne tagi receptury`, w stałym porządku identyfikatorów; `d_out=nil`.
- `s_out = gatunek receptury`; **dokładnie 1 sztuka**, nie trzy kopie. Nie losujemy dodatkowej nagrody.
- `I = Σ Economy.itemValue(input_i)`; `O = round(base_out × variantMult(r) × [1 + Σ(tagMult−1)])`.
- `F = fee_recipe × feeRank[r]`; `feeRank = {0:1; 1:1,5; 2:2; 3:3; 4:5}`.
- Serwer sprawdza również `O <= floor(0,60 × I)` jako bezpiecznik przyszłych zmian Config.
  Nie przejdzie → oferta niedostępna; nie pobiera kosztu, nie usuwa mutacji po cichu.
- `EV(O)=O`, bo rozkład ma jeden wynik. Ubytek wartości przy natychmiastowej sprzedaży bez bonusów:
  `sink = I + F − O`. Sama opłata usuwa F monet; I−O to utracona możliwość sprzedaży składników.

### 4.2. Tabela szans — obowiązująca

| Rangi trzech wejść | Wynik | Szansa | Inne warianty | Mnożnik opłaty |
|---|---|---:|---:|---:|
| Co najmniej jeden zwykły | Zwykły z dwiema cechami | 100% | 0% | ×1 |
| Wszystkie srebrne lub lepsze; co najmniej jedno srebro | Srebrny z dwiema cechami | 100% | 0% | ×1,5 |
| Wszystkie złote lub lepsze; co najmniej jedno złoto | Złoty z dwiema cechami | 100% | 0% | ×2 |
| Wszystkie tęczowe lub lepsze; co najmniej jedna tęcza | Tęczowy z dwiema cechami | 100% | 0% | ×3 |
| Trzy kosmiczne | Kosmiczny z dwiema cechami | 100% | 0% | ×5 |

Szanse gatunku i zachowania każdej z dwóch wymaganych cech wynoszą 100%. Przepis niespełniony nie jest
„0% sukcesu” — to niedozwolona operacja bez kosztu. Nawet trzy cosmic nie tworzą wyższej rangi.
Wybór lepszego wariantu niż pozostałe **nie poprawia wyniku**; ostrzeżenie pokazuje dokładnie utraconą
rangę i wymaga dodatkowego potwierdzenia. Automatyczny wybór nigdy nie poświęca lepszej rangi.

### 4.3. Przykłady z konkretnymi wejściami

1. `bay_bolete [mossy]` = 24 + `porcini [glowing]` = 150 + `bog_bell` = 2000.
   I=2174; F=1000000. **100%** `forge_mossbell [glowing,mossy]`, zwykły, O=750.
   0% srebra/złota/tęczy/cosmic. Przedmioty znikają dopiero po zatwierdzeniu na serwerze.
2. `pearl gold [crystal]` = 2520 + `obsidian gold [abyssal]` = 7125 + `bog_pearl gold` = 31500.
   I=41145; F=4000000. **100%** `forge_emberpearl gold [abyssal,crystal]`, O=21000.
   Różne cechy jaskini są połączone; wariant gold nie mnoży się przez gold.
3. `heart_of_mountain cosmic [abyssal]` = 110000 + `earthstar rainbow [moonlit]` = 624000
   + `night_eye gold` = 156000. I=890000; F=64000000.
   **100%** `forge_eclipsestar gold [abyssal,moonlit]`, O=189000. UI ostrzega o zużyciu cosmic i rainbow.
4. Te same trzy gatunki R6, wszystkie cosmic, te same wymagane cechy: I=2710000; F=160000000.
   **100%** `forge_eclipsestar cosmic [abyssal,moonlit]`, O=1260000 (×90 bazy).
   Poza tą recepturą 0% szansy na ten gatunek; brak dropu świata lub zakupu u handlarza.

### 4.4. Limity obiegu i opłacalności

- Maks. **2 cechy na wynik kuźni**, dokładnie te w recepturze. Nie dokładamy cech po czasie.
- Brak ponownego wsadu jakiegokolwiek gatunku `forgeOnly`, niezależnie od tagów i nazwy klienta.
- **Brak sadzenia, automatycznego sadzenia, dochodu offline i suszenia.** `Economy.plantIncome` dla
  `forgeOnly` zwraca 0 jako dodatkowa ochrona; GardenService odmawia sadzenia wcześniej.
- Wynik jest fizycznym przedmiotem w koszyku, można go sprzedać standardowo. Nie jest automatycznie
  chroniony przed śmiercią/krukiem po wykonaniu; trwały wpis kolekcji pozostaje.
- Utrwalenie w Grzybopedii daje podgląd 3D zdobytej formy bez możliwości wyjęcia kopii do koszyka.
  To minimalny sposób zachowania trofeum; pełna gablota z osobnego planu nie jest zależnością v1.
- Brak handlu, dropu na ziemię na życzenie i ścieżki do ogródkowej kradzieży. W razie utraty przez kruka
  obowiązują zasady istniejącego upuszczonego przedmiotu; jego gatunek nadal blokuje recrafting i sadzenie.
- Pumpkin nie jest tworzone ani kopiowane. Sprzedaż wyniku nie daje cukierków i nie postępuje celu kotła.
- Pozostaje zwykły bonus sprzedaży istniejących stron, ale strona kuźni nie dodaje kolejnego bonusu.
  Przy dzisiejszym maksimum 4×(3%+3%+5%+10%)=84%: `O ×1,84 <= 0,9392 I` dla najgorszej
  receptury R2. Nawet zdobycie pełnego bonusu dopiero po craftingu nie daje zysku względem I, przed opłatą.
  Adminowe ×2 sprzedaży jest zdarzeniem DEV, nie założeniem normalnego balansu; testować je osobno.

## 5. Sześć gatunków dostępnych wyłącznie z maszyny

Każdy przepis daje wskazany gatunek ze szansą 100%. „Baza” to nowe `Species.value`, nie kwota faktycznej
sprzedaży. O0 uwzględnia dwie cechy, ale nie wariant ani bonus atlasu. Wagi świata: brak uczestnictwa
w losowaniu, nie tylko `weight=0`. Kolejność R1–R6 jest kolejnością kolekcji, nie rankingiem ceny sprzedaży.

| R | ID; PL / EN | Składniki (wymagane cechy w nawiasach) | Baza / O0 | Opłata zwykła | Wygląd 3D; obrazek 2D |
|---|---|---|---:|---:|---|
| 1 | `forge_mossbell`; Mchowy Dzwon / Mossbell | bay_bolete(mossy) + porcini(glowing) + bog_bell | 300 / 750 | 1 mln | `bell`: zielony zwisający kapelusz z turkusowymi blaszkami i pasem mchu; sprite bell |
| 2 | `forge_emberpearl`; Żaroperła / Emberpearl | pearl(crystal) + obsidian(abyssal) + bog_pearl | 2000 / 7000 | 2 mln | `ball`: czarna perła z czerwonymi szczelinami i błękitnymi kryształkami; sprite puffball |
| 3 | `forge_glasscap`; Szkliwiak / Glasscap | lantern_shroom(crystal) + glowing_agaric(glowing) + moon_lily | 1500 / 4500 | 4 mln | `crystal`: mleczny kapelusz ze świecącym turkusowym środkiem; sprite crystal |
| 4 | `forge_runemorel`; Runiczny Smardz / Runic Morel | witch_hat(cursed) + hex_cluster(hexed) + raven_bracket | 5000 / 17500 | 8 mln | `morel`: fioletowy plaster miodu i zielone runy w zagłębieniach; sprite bell tymczasowo |
| 5 | `forge_mooncoral`; Księżycowy Koral / Mooncoral | sabbath_puffball(hexed) + moon_hat(moonlit) + night_eye | 9000 / 40500 | 16 mln | `tentacles`: srebrne ramiona z zielonymi końcówkami; sprite crown tymczasowo |
| 6 | `forge_eclipsestar`; Gwiazdosz Zaćmienia / Eclipse Earthstar | heart_of_mountain(abyssal) + earthstar(moonlit) + night_eye | 14000 / 63000 | 32 mln | `star`: czarna kula nad srebrnymi płatkami i żarem w szczelinach; sprite puffball tymczasowo |

W v1 **nie potrzeba nowego generatora kształtu FORMS**. Potrzebne są nowe wpisy `SHAPES`, `FORMS`,
parametry barw/dekoracji i osobne mapowania `SPECIES_SHAPE`. Sylwetka i wzór na kapeluszu odróżniają
gatunki nawet przy cosmic, które nadpisuje bazową barwę. Nie obiecywać własnych sprite'ów, dopóki Tom nie
wgra arkusza. Jeśli zastępcze ikony są zbyt podobne, pokazać nazwę i obie cechy; można użyć podglądu 3D.

`MushroomArt.effects` obecnie zachowuje pierwszy zestaw particles, a aura 3D także ma priorytety;
nie wystarczy przekazać dwóch tagów, by oba były czytelne. Proponowane dwie małe plakietki cech na karcie,
na modelu jedna geometria cechy i jeden ograniczony efekt drugiej. Maks. jeden zestaw orbit i jedno
światło; podglądy animować tylko gdy widoczne. Żadnych sześciu pełnych kosmicznych snopów w małym oknie.

### Grzybopedia, tytuły i odznaki

- Osobna zakładka **„Kuźnia”**, 6 kart i maski dokładnych form 0–4. W UI „gatunki 0/6” oraz osobno
  „formy 0/30”. Zwykły wynik zalicza gatunek; lepszy wariant nie daje automatycznie niższych bitów.
- Nie dopisywać `forge` bezpośrednio do ekonomicznej listy `Progress.PAGES`. Wydzielić listę stron świata
  i stron kolekcji; `pageOf/pageSpecies` rozpoznają `forgeOnly`, nie jego techniczny `zone`.
- **Nie liczy się do Arcygrzybiarza**, bonusów cenowych, rewardScale ani celów odkrywania światów.
  Dotychczasowe wymagania 4 stron i tytuły gracza pozostają bez zmian.
- `forgeCraft` aktualizuje własne liczniki/atlas/tytuły, ale nie `weekly.best`, pick, pickGold,
  pickMutated, discover ani spotkania ze strażnikiem. Faktyczna późniejsza sprzedaż jednej sztuki może
  naliczyć zwykłe `sell=1`; koszt i utrata trzech wejść wykluczają darmową farmę licznika.
- Tytuły: **Uczeń Zielarki / Herbalist's Apprentice** za 1 craft (rare);
  **Mistrz Kuźni / Forge Master** za wszystkie 6 gatunków (legendary). Bez monet i boostów.
  Nie dodajemy tytułu za 30 form na start: koszt czasu poniżej jest zbyt duży na główny cel.
- Odznaki `forge_first` i `forge_collection`, odpowiednio 1 craft i 6 gatunków. ID początkowo 0;
  Tom tworzy odznaki w Creator Hub. Nie przyznawać odznak z niepotwierdzonej transakcji.
- Opcjonalna gablota w późniejszym etapie może pokazywać wyłącznie dekoracyjną kopię wpisu. Bez dochodu,
  wyjmowania i „podaruj grzyb”. Nie implementujemy teraz systemu gabloty.

## 6. Monetyzacja: rozdzielenie efektów

Kuźnia **nie daje** Mikstury szczęścia, Wysypu, oleju, Plonu, Ratunku, x2 ani waluty wymienialnej na nie.
Nie zmienia `luckUntil`, boom, oil, pot ani ofert x2. Nie daje dodatkowego rzutu i nie odnawia wsadu po
niezadowalającym wyniku. Kocioł Halloween ma takie nagrody w zastanym kodzie; kopiujemy wyłącznie
konwencję UI/efektów, nigdy jego pulę nagród.

| Produkt | Bezpośredni wpływ na kuźnię | Pośredni wpływ |
|---|---|---|
| Mikstura / Wysyp | **0**; wszystkie wyniki receptury 100%, także podczas boostu | Mogą ułatwić znalezienie wymaganych mutacji podczas normalnej wyprawy. Ich dotychczasowe szanse i zasady pozostają. |
| Pełna latarnia / Ratunek | **0** | Mogą pomóc donieść składniki, jak inne okazy. Maszyna nie ratuje przed pościgiem. |
| Plon / x2 skrzyni | **0** do wyniku i opłaty | Dają monety, które gracz może wydać na opłatę. Nie nazywać kuźni ekonomicznie niezależną od płatności. |

Brak nowego SKU kuźni. Wariant z płatnym podnoszeniem szans **nie jest rekomendowany ani wyceniony**.
Gdyby wrócił wariant B, trzeba osobno określić pełny rozkład każdego wyniku przed/po efekcie,
obsługę `PolicyService` i pośrednio kupionej waluty. Roblox wymienia syntezę losową i luck boosts w zasadach
paid random items; samo płacenie monetami nie dowodzi wyłączenia spod tych zasad.
Źródło sprawdzone 4.11.2026: [Roblox — Paid random items](https://create.roblox.com/docs/production/monetization/paid-random-items).
Rekomendowany wariant C ma jeden ujawniony wynik i nie dodaje generatora płatnej losowej nagrody.

## 7. Liczby: EV, zlew i czas kolekcji

### 7.1. Uruchomienia i stan bazowy

Uruchomiono Lune **0.11.1**, `lune run tests/economy.spec.luau`: **1030 ok, 0 błędów**.
Uruchomiono niezmieniony `lune run tools/economy_sim.luau`:

| Kamień milowy modelu | Czas od startu | Dochód modelowy |
|---|---:|---:|
| Jaskinia otwarta | 1 h 29 min | 4018/min |
| Bagna otwarte | 2 h 43 min | 65357/min |
| Ulepszenia bagien rushwick/creel max | 5 h 42 min | 175882/min |
| Łysa Góra otwarta, saldo 10 mln | 6 h 39 min | 446281/min |
| Ulepszenia góry herbwick/witchbag max | 9 h 06 min | 924477/min |
| Wszystkie 104 modelowane poziomy dochodowe | 9 h 24 min | 941144/min |

161068407 monet zarobionych łącznie. To nie pełne wymaksowanie wszystkich pozycji `Config.Upgrades`:
symulator pomija m.in. chest, lock i lantern w liście ECON. Model idealizuje ogród (2× średnia wartości
strefy), zakupy i wybór tras; nie symuluje strat u strażników, kruków, konkurencji 6 graczy, limitu skrzyni,
offline, płatnych boostów ani bonusu sprzedaży atlasu. Nie są to mediany prawdziwych graczy.

### 7.2. Zwrot wartości składników

Wiersze dla najtańszych poprawnych składników bez wariantów, tylko wymagane tagi; pełne obliczenia
bez losowania. Opłaty nie są doliczane do mianownika „zwrot składników”, by nie ukrywać siły wyniku.

| R | Wartość 3 wejść I | EV wyniku O | O/I | Opłata F | Ubytek I+F−O | O przy 3 cosmic |
|---|---:|---:|---:|---:|---:|---:|
| 1 | 2174 | 750 | 34,50% | 1000000 | 1001424 | 15000 |
| 2 | 13715 | 7000 | **51,04%** | 2000000 | 2006715 | 140000 |
| 3 | 9520 | 4500 | 47,27% | 4000000 | 4005020 | 90000 |
| 4 | 115500 | 17500 | 15,15% | 8000000 | 8098000 | 350000 |
| 5 | 197500 | 40500 | 20,51% | 16000000 | 16157000 | 810000 |
| 6 | 135500 | 63000 | 46,49% | 32000000 | 32072500 | 1260000 |

Sprawdzono **750 kombinacji** (6 receptur × 5³ wariantów), wszystkie spełniają limit O≤0,60I.
To też można udowodnić: każdy składnik ma mnożnik wariantu co najmniej taki jak wynik, zatem
`I >= I0 × m(minRank)`, a `O = O0 × m(minRank)`. Największy iloraz to `7000/13715 = 0,510390`.
Dodatkowe poprawne cechy tylko zwiększają I, bo wynik zachowuje zawsze tę samą parę. Pumpkin i suszenie
są wykluczone, a duplikaty tagów niedozwolone. Ten dowód przestaje obowiązywać po zmianie receptur/cen;
stąd osobny test i runtime guard, nie arbitralny globalny nerf `mutationMultiplier`.

Łącznie pierwszy zwykły komplet 6 sztuk: składniki **473909**, wyniki **132750**, opłaty **63000000**.
Ubytek względem sprzedaży składników: **63341159** monet przy zerowym bonusie. Nie jest to 63,34 mln
bezpośrednio usuniętego salda: saldo traci 63 mln, reszta to koszt alternatywny składników.

Gdyby pozwolić posadzić 9 kosmicznych R6, przy nawozie ×3 dawałyby **1360800 monet/min**.
To więcej od całego referencyjnego dochodu po górze, mimo stratnej pojedynczej receptury.
**Dlatego ujemne EV sprzedaży nie wystarcza — sadzenie pozostaje zakazane.** Realny przyrost trwałego
pasywnego dochodu z kuźni to **0/min**. Sprzedaż wyniku zwraca część kosztu, nie generuje zysku w pętli.

### 7.3. Czas zdobywania — jawny model i ograniczenia

Osobny skrypt analityczny Lune poza repo wykorzystał niezmienione funkcje `trip`, `income` i ładowanie
modułów z początku `tools/economy_sim.luau`. Parametry: 10000 prób Monte Carlo, seed 20261104;
wynik EV liczony dokładnie. Skrypt do odtworzenia znajduje się w aneksie, nie jest kodem gry.

Dla każdego składnika: `p = species.weight / sumWeights(zone) × P(dokładny wariant | luck) ×
P(wymagany tag | luck)`. Brak wymaganego tagu oznacza ostatni czynnik 1.
Luck pochodzi z `Economy.luck` przy maks. nożyku i głębokości; bez mikstury, Wysypu, grupy, znajomego i nocy.
`variantOdds` daje rzeczywiste prawdopodobieństwa, nie surowe 0,0008 dla każdego stanu.
Czas jednej próby = czas wyprawy / liczba zbiorów z aktualnego `trip`; liczba prób ma rozkład geometryczny.
Maks. ulepszenia dostępne w danym świecie, ogród max. Materiały zbierane kolejno na wskazany cel,
bez magazynowania przy okazji składników innych receptur i bez zatrzymywania innych form.

**Ważne ograniczenie:** model przyjmuje niezależne odświeżane rzuty z puli i mnoży szansę wariantu przez
szansę tagu. Pomija rzeczywisty harmonogram odrostów, możliwość oglądania wariantu przed zebraniem,
konkurencję oraz przenoszenie zapasów. Dlatego nie jest ani gwarancją, ani ścisłą górną granicą czasu.
Nie obejmuje pierwszej ucieczki przed Jagą i odkrycia portali; te warunki muszą być już spełnione.

| Cel od zera zapasów | Opłaty | Czas zdobycia monet przy dochodzie referencyjnym | Średni czas składników | P50 / P90 / P95 czasu składników | Suma modelowa* |
|---|---:|---:|---:|---:|---:|
| Bagna max: R1–R3 zwykłe | 7 mln | 39,80 min | 14,01 min | 12,12 / 23,44 / 28,18 min | **54,31 min** |
| Góra max: R1–R6 zwykłe | 63 mln | 66,94 min | 23,64 min | 22,03 / 34,97 / 39,85 min | **91,58 min** |
| Góra max: 24 dokładne formy, zwykła–tęczowa | 472,5 mln | 8,37 h | 36,97 h | 35,50 / 50,86 / 56,80 h | **45,41 h** |
| Góra max: wszystkie 30 dokładnych form | 787,5 mln | 13,95 h | 184,23 h | 176,12 / 253,50 / 282,76 h | **198,26 h** |

*Sumujemy czas farmienia opłat, polowania i 10 s na każdą sztukę. Nie zaliczamy zarobku podczas polowania
na poczet opłat, nie odliczamy sprzedaży wyniku. Rzeczywista równoległa produkcja monet skróci tę sumę;
straty i konkurencja mogą ją wydłużyć. P50/P90/P95 dotyczą tylko polowania w modelu.
Dla bogatego gracza z gotowymi monetami i składnikami 6 craftów zajmuje około minuty, a 30 około 5 min
plus opóźnienia zapisu. Nie udajemy, że sam cooldown daje tygodnie zawartości.

Gracz, który ma już R1–R3 z bagien, potrzebuje na górze tylko R4–R6 i **56 mln** opłat dla zwykłych form,
a nie ponownie 63 mln. Tabela pełnej kolekcji liczy stan bez wcześniejszych wpisów.

Wniosek projektowy: premiujemy **6 gatunków**, nie 30 form. Formy cosmic są długim dobrowolnym polowaniem,
bez odznaki zamykającej inną zawartość. Jeśli Tom chce cały atlas kuźni w 5–10 h, musi zmienić wymagania
wariantów; nie ukrywać 198 h pod etykietą „kilka wieczorów”. Taka zmiana wymaga nowej symulacji i ochrony
przed zamianą taniego cosmic w drogi. Kuźnia v1 jest **skończonym zlewem kolekcjonerskim**, nie wiecznym
rozwiązaniem emisji monet. Po kolekcji potrzebne będą nowe przepisy/dekoracje, a nie sztuczne obowiązkowe
powtórzenia bez nagrody.

## 8. UI i teksty do CSV

Okno PanelKit w stylu chatki; desktop ok. 760×500, na telefonie dwa przełączane widoki „Składniki” /
„Wynik”, zamiast pomniejszania całej tabeli. Minimalne cele dotykowe 44 px po skali, przewijanie i bezpieczne
marginesy; sprawdzić w 705×338 oraz pionowym telefonie. Fokus pada zaczyna na wyborze receptury, nie
na przycisku zużycia. Klawisz/proximity jak istniejące stanowiska; nie nadpisywać skrótu innego panelu.

1. Lista 6 receptur: nazwa i sylwetka wyniku, stan odkrycia, wymagany świat. Zablokowane mają jawny warunek.
2. Trzy sloty z koszyka. Karta pokazuje gatunek, wariant, tagi, wartość sprzedaży; zaznaczenie odpowiada
   konkretnej pozycji aktualnego koszyka. Filtr „Pasujące”, nigdy automatycznie najdroższe okazy.
3. Podgląd: model/ikona wyniku, dwie cechy, gwarantowany wariant, **100%**, liczba sztuk 1, opłata,
   wartość 3 składników i informacja „Do kolekcji — nie rośnie w ogródku”. Widoczna utrata dodatkowych cech.
4. Przycisk „Połącz za {1} monet” dostępny dopiero po odpowiedzi serwera. Przed pierwszą operacją
   potwierdzenie „Zużyjesz te 3 grzyby”. Przy mieszanych rangach/utracie dodatkowych cech potwierdzenie
   zawsze; standardowo nie dodawać kolejnego modala do każdego równego zestawu.
5. Po kliknięciu „Zapisywanie…”, blokada ponownego żądania. Animacja: 0–1 s wsad, 1–3 s dwa pasma cech,
   3–4 s ujawnienie. **Gotowy wynik dopiero po potwierdzonym zapisie**, w razie wolnego zapisu animacja
   kończy się neutralnym oczekiwaniem; nie wyświetla losowej ruletki, skoro wynik jest gwarantowany.
6. Karta „Utworzono” i przycisk „Zobacz w Grzybopedii”. Zamknięcie nie przyznaje ponownie. Podczas
   oczekiwania można zamknąć UI. Przy ponownym wejściu status transakcji wraca z serwera.

Wzór wizualny z `CauldronView`: skalowanie Back, kontrolowany burst i dźwięk `cauldron`/`shimmer`.
Nie kopiować jump scare, darmowych nagród, wymiany duplikatów na monety ani samego bezpieczeństwa handlera.
Nie przenosić wyniku jako fizycznego pickupu z serwera — to otwiera wyścig dwóch graczy.

Proponowane wiersze (specyfikacja; **nie zmieniamy teraz GameStrings.csv**). Dokładnie pięć kolumn
`Key,Source,Context,Example,pl`; w tekstach nie ma przecinków. Dynamiczne wartości przez `{1}` itd.

```csv
Key,Source,Context,Example,pl
FORGE_NAME,Herbalist's Mortar,,,Moździerz Zielarki
FORGE_COLLECTION,Mushroom Forge,,,Kuźnia Grzybów
FORGE_OPEN,View recipes,,,Zobacz przepisy
FORGE_SELECT,Choose 3 mushrooms from your basket,,,Wybierz 3 grzyby z koszyka
FORGE_MATCHING,Matching ingredients,,,Pasujące składniki
FORGE_RESULT,Guaranteed result: {1} — 100%,,,Gwarantowany wynik: {1} — 100%
FORGE_COUNT,You receive 1 mushroom,,,Otrzymasz 1 grzyb
FORGE_COST,Fuse for {1} coins,,,Połącz za {1} monet
FORGE_INPUT_VALUE,Ingredient value: {1},,,Wartość składników: {1}
FORGE_OUTPUT_VALUE,Sale value: {1},,,Wartość sprzedaży: {1}
FORGE_CONSUME,These 3 mushrooms will be consumed,,,Te 3 grzyby zostaną zużyte
FORGE_MIN_VARIANT,The lowest input variant determines the result,,,Najniższy wariant składników określa wynik
FORGE_LOST_TRAITS,These traits will not carry over: {1},,,Te cechy nie przejdą na wynik: {1}
FORGE_CONFIRM_LOSS,Use the stronger mushrooms anyway?,,,Mimo to zużyć silniejsze grzyby?
FORGE_NO_PLANT,Collection item — cannot be planted or fused again,,,Okaz kolekcjonerski — nie można sadzić ani ponownie łączyć
FORGE_NO_BOOST,Luck boosts do not change this result,,,Bonusy szczęścia nie zmieniają tego wyniku
FORGE_NO_EVENT,Event mushrooms cannot be used here,,,Grzybów eventowych nie można tutaj użyć
FORGE_NO_DRIED,Dried mushrooms cannot be used here,,,Suszonych grzybów nie można tutaj użyć
FORGE_NEED_WORLD,Unlock {1} first,,,Najpierw odblokuj {1}
FORGE_NEED_JAGA,Escape Baba Jaga once to unlock this recipe,,,Ucieknij Babie Jadze raz aby odblokować ten przepis
FORGE_WRONG_INPUT,The ingredients do not match this recipe,,,Składniki nie pasują do przepisu
FORGE_NO_COINS,You need {1} more coins,,,Brakuje {1} monet
FORGE_CHANGED,Your basket changed — choose again,,,Koszyk się zmienił — wybierz ponownie
FORGE_BUSY,Wait for the previous fusion to save,,,Poczekaj na zapis poprzedniego połączenia
FORGE_COOLDOWN,Ready in {1} seconds,,,Gotowe za {1} s
FORGE_UNSAFE,Finish the chase and return to the mortar,,,Zakończ pościg i wróć do moździerza
FORGE_SAVE_WAIT,Saving your fusion…,,,Zapisywanie połączenia…
FORGE_SAVE_PENDING,Still waiting for confirmation — do not repeat the fusion,,,Nadal czekamy na potwierdzenie — nie powtarzaj połączenia
FORGE_UNAVAILABLE,This recipe is temporarily unavailable,,,Ten przepis jest chwilowo niedostępny
FORGE_DONE,Created: {1},,,Utworzono: {1}
FORGE_ATLAS,View collection,,,Zobacz kolekcję
FORGE_SPECIES_COUNT,Species: {1}/6,,,Gatunki: {1}/6
FORGE_FORMS_COUNT,Optional forms: {1}/30,,,Opcjonalne formy: {1}/30
MUSH_FORGE_MOSSBELL,Mossbell,,,Mchowy Dzwon
MUSH_FORGE_EMBERPEARL,Emberpearl,,,Żaroperła
MUSH_FORGE_GLASSCAP,Glasscap,,,Szkliwiak
MUSH_FORGE_RUNEMOREL,Runic Morel,,,Runiczny Smardz
MUSH_FORGE_MOONCORAL,Mooncoral,,,Księżycowy Koral
MUSH_FORGE_ECLIPSESTAR,Eclipse Earthstar,,,Gwiazdosz Zaćmienia
TITLE_FORGE_APPRENTICE,Herbalist's Apprentice,,,Uczeń Zielarki
TITLE_FORGE_MASTER,Forge Master,,,Mistrz Kuźni
```

## 9. Zapis v8, transakcja i odzyskiwanie

### 9.1. Co wymaga wersji

Same dwie cechy już mieszczą się w v7. **Rekomendujemy DATA_VERSION=8 przy implementacji**, ponieważ
przybywa trwały stan operacji, dostępność specjalnych gatunków i reguły kolekcji. Ten dokument nie podnosi
wersji w kodzie.

Minimalne nowe dane: `forge = {seq=0, crafted=0, nextAt=0, last=nil}`. `last` to ostatnia transakcja:
`{id, recipe, configVersion, cost, result={s,v,x}, completedAt}`. `id` powiązany z UserId i rosnącym seq;
nie przyjmować go od klienta jako dowodu wykonania. Brak nieograniczonej historii, nie trzymać wszystkich
zużytych koszyków. Maski gatunków kuźni można przechowywać w istniejącym `atlas`.

`forgeOnly` należy do definicji gatunku, **nie jest opcjonalną flagą klienta**, którą można zgubić przy
kopiowaniu `{s,v,x,d}`. Każdy taki gatunek zawsze ma zakaz sadzenia i recraftingu. Reconcile zachowuje
dokładnie jego dozwoloną parę tagów i wariant 0–4; nieznane/niekompletne wpisy kieruje do diagnostyki,
bez „naprawiania” przez losowanie nowej nagrody. Nie przyznawać odkryć ze śmieciowego rekordu `last`.

Migracja v7→v8:

1. Brak `forge` → puste wartości; **zero darmowych grzybów, kosztów, nagród i gotowych receptur**.
2. Maski atlasu walidować jako skończone całkowite 0–31 (najlepiej maską dozwolonych bitów); `true`→1.
   Poprawne stare maski 0–15 zachować. Nie da się z samego 15 odtworzyć wcześniej zgubionego cosmic.
   Ewentualne odtworzenie bitu 16 tylko z wiarygodnego posiadanego kosmicznego okazu/backupów; osobna
   decyzja Toma. Nie nadawać wszystkim cosmic ani nie kasować masowo niższych form.
3. Zachować dotychczasowe grządki, `d`, eventowe pumpkin, poziomy ulepszeń, salda i maski zwykłych gatunków.
   Nowy limit dwóch tagów dotyczy **wyjść kuźni**, nie globalnego przycinania starych okazów.
4. Walidować `forge.seq/crafted/nextAt/cost` jako finite, całkowite i nieujemne; limit cooldownu przy
   odczycie do rozsądnych 10 s względem teraz. Ograniczyć długości stringów, list i rekordów.
5. Jeśli `forgeOnly` znalazł się w `planted`, dochód musi być 0 już przed liczeniem offline. Przenieść do
   koszyka lub wydzielonej odzyskiwalnej kolekcji bez wypłaty monet; nie używać konwersji nadmiaru
   grządek na pot. Koszyk pełny → zachować rekord w naprawczym depozycie bez możliwości ponownego odbioru.
6. Starszy serwer v7 nie może ponownie zapisać profilu v8: nie zna gatunków i pól, więc mógłby je wyciąć.
   Wdrożenie wymaga zakończenia starych sesji/serwerów albo wcześniej przygotowanej kompatybilnej wersji.
   Przed cofaniem wersji przygotować migrację wstecz; nie kasować `forge` i definicji gatunków na ślepo.

### 9.2. Protokół operacji

- Podgląd to niewiążąca oferta serwera: receptura, 3 indeksy, **obowiązkowy** `basketKey`, rewizja koszyka,
  wersja konfiguracji, cena, wynik oraz krótki token sesji ważny np. 30 s. Klient nie podaje ceny ani wyniku.
- Każda zmiana koszyka podnosi rewizję: zbiór, sprzedaż, sadzenie/zamiana, kruk, śmierć, odzysk, DEV.
  Sam `basketKey` może powtórzyć się po usunięciu i dodaniu identycznych okazów — rewizja zapobiega temu ABA.
  Dla jednej sesji wystarczy rewizja; trwałe UID wszystkich starych grzybów nie jest wymaganiem v1.
- Przy zatwierdzeniu serwer sprawdza typy i rozmiary pakietu, dokładnie 3 unikalne całkowite indeksy,
  token, rewizję, zawartość, odległość 3D do moździerza (np. ≤12 studs), żywą postać, tutorial/światy,
  brak pościgu/downed/carry/ekspedycyjnego transportu, aktywny profil, brak poprzedniej operacji w toku,
  cooldown, pełną recepturę, zasoby i limit O/I. Koszt wyłącznie z aktualnego Config.
- Sekcja krytyczna **bez yield**: zajęcie operacji → odjęcie F → usunięcie 3 pozycji malejąco → dodanie
  1 wyniku → atlas/liczniki → nowy `seq`, `last`, `nextAt`, rewizja. Wszystko w jednym profilu.
  Zmiana koszyka netto −2; uwzględnić rezerwacje miejsc `DelveService.reserved`, nie bypassować limitów.
- Następnie zlecić zapis i czekać na potwierdzenie konkretnego `seq/id` w `LastSavedData`/`OnAfterSave`.
  Nie traktować `DataService.save()==true` jako trwałego zatwierdzenia.
- Do potwierdzenia zakaz następnego craftu i sprzedaży/transferu wyniku; operacja nie otwiera osobnej
  przechowalni składników. Nigdy nie czekać na zapis przed ich usunięciem bez wspólnej blokady.
  Zwykłe zagrożenia nadal mogą zmieniać koszyk już po całej sekcji krytycznej; nie dodajemy nietykalności.
  Utrata powstałego okazu jest oddzielnym zdarzeniem po craftingu, nie powodem ponownego przyznania.
- Potwierdzenie zapisu publikuje wynik, odznaki i statystyki zlewu. Przy wolnym zapisie: oczekiwanie,
  blokada powtórzenia; **brak automatycznego zwrotu po 20 s**, bo zapis może zakończyć się później.
- Disconnect przed zmianą: nic nie zabrano. Po zmianie przed zapisem: ProfileStore próbuje zapisać cały
  stan na release. Jeżeli żaden zapis nie nastąpił, wraca cały wcześniejszy profil; nie istnieje trwała
  połowa operacji. Po trwałym zapisie: ponowny login pokazuje historię, nie dodaje ponownie wyniku.
- Po restarcie sprawdzamy stan profilu i `seq`; `last.result` to opis historyczny, **nie oczekująca nagroda
  do przyznania**. Wynik mógł już zostać sprzedany lub utracony. Przydzielenie go z `last` zduplikuje przedmiot.
- Nie używać `data.receipts` Robux do craftingu, nie wykonywać `BadgeService`/sieci/RNG w callbacku
  powtarzalnej aktualizacji magazynu. Dla C nie ma losowania w ogóle; ewentualny B losowałby tylko raz
  na serwerze, przed trwałym zapisaniem pełnej operacji.

## 10. Plan zmian plik po pliku — do przyszłej implementacji

| Plik/moduł | Zakres przyszłej zmiany |
|---|---|
| `src/shared/Config.luau` | `SpeciesDef.forgeOnly`, 6 gatunków dopisanych na końcu (bez przestawiania indeksów rankingów), `Config.Forge` z recepturami, opłatami, cooldownem i numerem balansu; ID odznak 0. |
| Nowy `src/shared/Forge.luau` | Czyste dopasowanie receptur, quote/walidacja, minimum rangi, para tagów, fee, O/I, walidacja stanu zapisu. Zero API Roblox; wspólna logika do testów i podglądu. |
| `src/shared/Economy.luau` | Wykluczenie forgeOnly z speciesByZone/rollSpecies/guardian pools; 0 plantIncome dla forgeOnly; jawna klasa rzadkości nowych gatunków zamiast przypadkowej klasy z weight=0. Zachować wzór mutacji i wartości. |
| `src/shared/Progress.luau` | Osobna kolekcja forge, rozdzielenie stron świata od stron UI, zachowanie rank 0–4, wykluczenie kuźni z bonusów/rewardScale/Grandmaster. |
| `src/shared/Titles.luau` | Licznik forgeCraft i tytuły 1 craft / 6 gatunków; nie zmieniać warunków dawnych tytułów. |
| `src/shared/Achievements.luau` | forge_first/forge_collection, source danych kuźni; potwierdzony zapis przed przyznaniem. |
| `src/server/DataService.luau` | v8, default/reconcile forge, maski do 31, walidacja forgeOnly w koszyku/grządkach przed offline; potwierdzanie seq operacji. |
| Nowy `src/server/ForgeService.luau` | Podgląd, walidacja serwera, tokeny, cooldown, transakcja i stan oczekiwania na zapis; niezależny stan per gracz. |
| `src/server/GameService.luau` | Start/integracja ForgeService, rewizja koszyka na wszystkich ścieżkach, odrzucanie craftu przy zagrożeniach, blokada obrotu pending wynikiem, komunikaty; DEV tylko Studio. |
| `src/server/GardenService.luau` | Zakaz forgeOnly w ręcznym/auto sadzeniu, zamianach i odzysku; zapobieganie konwersji niedozwolonych nasadzeń do pot. |
| `src/server/ProgressService.luau` | Dedykowane foundForge lub rozdzielenie źródeł przed discover/rankingiem/questami; aktualizacja samej kolekcji i forgeCraft. |
| `src/shared/Remotes.luau` | Jawne nazwy quote/commit/state/result; limity pakietów w odbiorcach, nie poleganie na nazwie Remote. |
| Nowy `src/server/World/Forge.luau`; `src/server/MapBuilder.luau` | Model moździerza, osobna rezerwacja przestrzeni na Placu Portali, prompt i przekazanie pozycji serwisowi. |
| Nowy `src/client/ForgePanel.luau`; `src/client/Main.client.luau` | Okno, 3 sloty, podgląd 100%, obsługa statusów/animacji; klient nie przyznaje i nie odejmuje. |
| `src/client/MushroomView.luau` | SHAPES/FORMS nowych gatunków, odróżnialne detale; ograniczone FX dla dwóch cech i wariantu. |
| `src/client/MushroomArt.luau` | SPECIES_SHAPE i widoczne dwie cechy przy priorytetach FX; istniejący arkusz na start. |
| `src/client/AtlasPanel.luau` | Zakładka kuźni, 6 kart × 5 form, podgląd zdobytych okazów; bez standardowego bonusu stron. |
| `src/localization/GameStrings.csv` | Wiersze z tego planu i ewentualne istniejące klucze opisów tytułów; walidacja 5 kolumn i pokrycia kluczy. |
| `src/server/HalloweenService.luau`; `src/client/CauldronView.luau` | Bez zmian mechaniki; referencja animacji. Nie łączyć walut i pul nagród. |
| `src/server/RavenService.luau`, `HoardService.luau`, `DelveService.luau` | Audyt granic mutacji koszyka i przenoszenia danych; poprawić tylko potrzebne hooki rewizji/integracji. Brak nowych dropów forgeOnly. |
| `tests/economy.spec.luau` + nowy test Forge | Dokładne przykłady, 750 kombinacji, migracje, wykluczenie pul/ogrodu/progresji; serwerowe scenariusze osobno. |
| `tools/economy_sim.luau` / przyszły `tools/forge_sim.luau` | Raport zlewu, model celowanego polowania i jawne ograniczenia. Obecnie żadnego z tych plików nie zmieniamy. |
| `docs/Odznaki.md`, `docs/HANDOFF.md` | Uaktualnić dopiero po przyjęciu/implementacji. Ten commit zawiera tylko niniejszy plan. |

## 11. Testy akceptacyjne i exploity

| Przypadek | Oczekiwany wynik |
|---|---|
| Każda receptura w 5³ kombinacjach wariantów | 750/750: min ranga, 1 wynik, 2 właściwe tagi, O/I≤0,60; niezmieniona wycena zwykłych grzybów. |
| Dodatkowy tag, duplikat, pumpkin, stare d=2, mimic, nieznane s/v/x, NaN/Inf | Dodatkowy zwykły tag jawnie utracony; reszta według reguł odrzucona przed kosztem. |
| 1 mocny + 2 słabe; permutacje slotów | Ten sam wynik i cena; ostrzeżenie o degradacji; brak awansu rangi i automatycznego wyboru lepszych. |
| Próba wkładania wyniku / ręcznego i automatycznego sadzenia / naprawy grządki | Odmowa; 0 offline i 0 pot; brak recraftingu także po reconnect i transferze krukiem. |
| `rollSpecies` przy r=0 i blisko 1; pusta pula | Nigdy forgeOnly. Samo weight=0 nie wystarcza; testuje budowę list. |
| Pełny atlas świata przed i po dodaniu kuźni | Ten sam bonus i Arcygrzybiarz; rewardScale góry 520000; forge nie podnosi weekly.best. |
| Cosmic mask 16/17/31; stare true/15; v7 bez forge | Dokładne bity zachowane, brak dopisywania niższych; stare dane bez utraty; świeże forge zerowe. |
| Kliknięcie 2×, replay tokenu, 2 różne requesty, reconnect i drugi serwer | Jeden koszt, trzy usunięte składniki, jeden wynik; cooldown wspólny w zapisie, jedna sesja ProfileStore. |
| Kruk lub sprzedaż zmienia koszyk między quote a commit | Rewizja/token niezgodne; nic nie pobrano; świeży podgląd. |
| Kruk/strażnik/śmierć podczas animacji | Transakcja już była atomowa; zagrożenie działa na nowy koszyk; animacja nie odtwarza utraconych wejść ani wyniku. |
| Natychmiastowy teleport do moździerza w trakcie pościgu | Odmowa mimo poprawnej odległości; samo sprawdzenie miejsca nie wystarcza. |
| Rozłączenie przed mutacją / przed zapisem / po zapisie / po sprzedaży wyniku | Powrót do całego starego stanu lub całego zapisanego stanu. `last` nigdy nie jest ponownym grantem. |
| Zapis opóźniony >20 s i potem udany; utrata blokady profilu | Brak refundu na timeout i brak drugiej operacji; zakończona sesja nie publikuje autorytatywnego sukcesu. |
| Niepoprawny payload: string zamiast listy, dziury, dodatkowe klucze, 3 kopie indeksu, duże stringi | Odrzucenie i limit żądań quote/commit przed kosztownym liczeniem; serwer nie ufa UI. |
| Odblokowanie świata podrobione przez klienta; profil canSave=false | Odmowa. Dane DEV tylko po uprawnieniach i RunService:IsStudio(). |
| 6 równoczesnych graczy | Brak wspólnej blokady maszyny i wzajemnego przejmowania wyniku; brak fizycznego pickupu. |
| Mikstura/Wysyp aktywne, Plon/x2 kupione podczas UI | Rozkład receptury nadal 100%, brak darmowych odpowiedników; quote nie używa luck. |
| Stary serwer v7 odczytuje v8 | Wdrożenie blokuje taką ścieżkę; rollback nie usuwa gatunków i atlasu bez migracji. |
| UI mobile/gamepad i oba języki | 3 czytelne sloty, szanse przed płatnością, pełna opłata, ostrzeżenia, poprawne fokusy i anulowanie animacji przy zamknięciu. |

DEV do późniejszego testu w Studio: zestaw każdej receptury, rangi mieszane i cosmic, wymuszone oczekiwanie
na zapis, fail/release profilu, zmiana koszyka po quote, kruk i pościg przy zatwierdzeniu, reset wyłącznie
stanu kuźni na profilu testowym. Nie odpalać Play na rzeczywistym zapisie Toma do tych prób.

Telemetria po wdrożeniu: quote → commit → confirmed; recipe/rank/configVersion/opId, koszt monet,
wartość zużytych składników, wartość wyniku, czas do kolejnego odkrycia, liczba odmów/stale/błędów zapisu.
Deduplikacja zdarzeń po opId. Osobno bezpośredni zlew F i koszt alternatywny I−O. Mierzyć powroty do starych
światów, rezygnację przed pierwszym craftem, kończenie 3/6 gatunków oraz sprzedaż wyniku. Bez telemetrii nie
zakładamy, że 32 mln za ostatnią recepturę będzie odbierane jako atrakcyjny cel.

## 12. Pytania do Toma — propozycje domyślne nie blokują planu

1. **Czy gwarantowana receptura spełnia fantazję „forge”, czy konieczne jest losowanie?** Rekomendacja:
   100% i emocje w wyprawie. Jeśli losowanie jest wymaganiem, przeprojektować B i ponownie policzyć balans.
2. **Czy akceptujemy kolekcjonerskie okazy bez sadzenia?** Rekomendacja: tak. Zgoda na ogród zmienia
   projekt ekonomiczny, nie tylko jedno ustawienie. 1,36 mln/min z 9 kosmicznych R6 pokazuje skalę.
3. **Czy trzy kosmiczne składniki na kosmiczną formę są celowo bardzo długim polowaniem?** Rekomendacja:
   tak jako opcjonalne formy, główny cel tylko 6 gatunków; 30 form nie daje obowiązkowej nagrody.
4. **Czy zlew ma trwać około 1–2 h po górze, czy wiele dni?** Rekomendacja: 63 mln za podstawowy komplet
   i pomiar realnego czasu; dla bogatych ze zgromadzonymi składnikami to krótki zakup kolekcji.
5. **Czy widoczny zapis trofeum w atlasie wystarczy na premierę, czy potrzebna jest gablota 3D w ogródku?**
   Rekomendacja: atlas z podglądem, gablota w osobnym etapie bez wyjmowania kopii.
6. **Nazwa i wygląd:** Moździerz Zielarki na Placu Portali czy urządzenie Baby Jagi na górze?
   Rekomendacja: plac, dostęp pierwszych receptur od bagien; sprawdzić kompozycję mapy w Studio.
7. **Czy R6 wymaga pierwszej ucieczki przed Jagą?** Rekomendacja: tak; symulator nie mierzy czasu tego
   osiągnięcia. Nie uzależniać przepisu od odznaki Roblox, której ID może nadal wynosić 0.
8. **Jak naprawić historycznie uszkodzone maski cosmic?** Rekomendacja: zachować istniejące wpisy,
   poprawić zapis 0–31 i odtwarzać cosmic wyłącznie na podstawie wiarygodnych danych; nie zgadywać.

Przed implementacją potrzebna akceptacja zwłaszcza punktów 1–3. To pytania produktowe, nie brak możliwości
odczytania kodu. Nie wymagają zmieniania gry w tym zadaniu.

## Aneks A. Odtworzenie obliczeń

Uruchomiono osobny skrypt w scratch, nie dodano kodu do `src`, `tests` ani `tools`. Aby odtworzyć wynik
na wskazanym SHA: z `tools/economy_sim.luau` skopiować początek **przed** linią
`local s: State = { levels = {}, cave = false` do tymczasowego pliku `.luau`. Dopisać poniższy fragment,
a następnie wykonać `lune run /ścieżka/do/pliku.luau` **z katalogu repo** i bez argumentów progów portali.
Początek zawiera ładowanie prawdziwego Config/Economy/Progress oraz niezmienione funkcje trip/income;
nie przepisujemy ich wzorów do innego języka. Nie uruchamia Roblox ani DataStore.

```luau
local recipes = {
 {id="forge_mossbell", base=300, fee=1000000, inputs={{"bay_bolete","mossy"},{"porcini","glowing"},{"bog_bell"}}},
 {id="forge_emberpearl", base=2000, fee=2000000, inputs={{"pearl","crystal"},{"obsidian","abyssal"},{"bog_pearl"}}},
 {id="forge_glasscap", base=1500, fee=4000000, inputs={{"lantern_shroom","crystal"},{"glowing_agaric","glowing"},{"moon_lily"}}},
 {id="forge_runemorel", base=5000, fee=8000000, inputs={{"witch_hat","cursed"},{"hex_cluster","hexed"},{"raven_bracket"}}},
 {id="forge_mooncoral", base=9000, fee=16000000, inputs={{"sabbath_puffball","hexed"},{"moon_hat","moonlit"},{"night_eye"}}},
 {id="forge_eclipsestar", base=14000, fee=32000000, inputs={{"heart_of_mountain","abyssal"},{"earthstar","moonlit"},{"night_eye"}}},
}
local variants={false,"silver","gold","rainbow","cosmic"}
local fees={1,1.5,2,3,5}
local multipliers={1,1.5,3,8,20}
-- Nie zmieniamy Config: gatunki wyjściowe są tylko w tabeli badania.
local checked=0
for _,r in recipes do
 local normalIn=0
 local tagBonus=1
 for _,i in r.inputs do
  normalIn+=Economy.mushroomValue(i[1],nil,if i[2] then {i[2]} else nil)
  if i[2] then tagBonus+=Economy.getTag(i[2]).mult-1 end
 end
 local normalOut=r.base*tagBonus
 print(string.format("EV %s input=%d output=%d ratio=%.6f fee=%d loss=%d cosmic=%d",r.id,normalIn,normalOut,normalOut/normalIn,r.fee,normalIn+r.fee-normalOut,normalOut*20))
 for a=1,5 do for b=1,5 do for c=1,5 do
  local ranks={a,b,c};local sum=0
  for n,i in r.inputs do sum+=Economy.mushroomValue(i[1],variants[ranks[n]] or nil,if i[2] then {i[2]} else nil) end
  local out=math.floor(normalOut*multipliers[math.min(a,b,c)]+0.5)
  assert(out<=0.6*sum); checked+=1
 end end end
end
print("CHECKED",checked)
local function probe(world)
 local s={levels={},cave=true,swamp=true,mountain=world=="mountain",coins=0,minutes=0,earned=0}
 for id in Config.Upgrades do s.levels[id]=Economy.upgradeCap(id,world) end
 return s
end
local seed=20261104
local function random()
 seed=(seed*48271)%2147483647
 return seed/2147483647
end
local function taskList(s,last,forms)
 local list={};local totalFee=0
 for ri=1,last do
  local r=recipes[ri]
  for vi=1,forms do
   totalFee+=r.fee*fees[vi]
   for _,i in r.inputs do
    local sp=Economy.getSpecies(i[1]);local z=sp.zone
    local t=trip(s,z); assert(t)
    local weight=0;for _,v in Economy.speciesForZone(z) do weight+=v.weight end
    local luck=Economy.luck({knifeLevel=s.levels.knife,zone=z,boom=false,potion=false})
    local vp=1
    local odds=Economy.variantOdds(luck)
    if vi==1 then for _,o in odds do vp-=o.chance end
    else for _,o in odds do if o.id==variants[vi] then vp=o.chance end end end
    local tp=if i[2] then Economy.tagOdds(Economy.getTag(i[2]),luck) else 1
    -- Co najmniej wymagana cecha; dodatkowe cechy mogą podnieść wejściową wartość.
    table.insert(list,{p=sp.weight/weight*vp*tp, minutes=t.seconds/60/t.picks})
   end
  end
 end
 return list,totalFee
end
for _,scenario in {{"swamp",3,1},{"mountain",6,1},{"mountain",6,4},{"mountain",6,5}} do
 local s=probe(scenario[1]);local tasks,fee=taskList(s,scenario[2],scenario[3])
 local mean=0;for _,t in tasks do mean+=t.minutes/t.p end
 local runs={}
 for run=1,10000 do
  local total=0
  for _,t in tasks do total+=(math.floor(math.log(1-random())/math.log(1-t.p))+1)*t.minutes end
  table.insert(runs,total)
 end
 table.sort(runs)
 local rate=income(s)
 print(string.format("TIME %s species=%d forms=%d income=%.3f fee=%d fundMin=%.3f huntMean=%.3f huntP50=%.3f huntP90=%.3f huntP95=%.3f totalMean=%.3f",scenario[1],scenario[2],scenario[3],rate,fee,fee/rate,mean,runs[5000],runs[9000],runs[9500],mean+fee/rate+scenario[2]*scenario[3]*10/60))
end
-- Przykłady niejednakowych wariantów.
for _,v in {{5,4,3},{5,5,5},{1,1,1}} do
 local r=recipes[6];local input=0
 for k,i in r.inputs do input+=Economy.mushroomValue(i[1],variants[v[k]] or nil,if i[2] then {i[2]} else nil) end
 local rank=math.min(table.unpack(v));local output=63000*multipliers[rank]
 print("EXAMPLE_R6",table.concat(v,"/"),input,output,r.fee*fees[rank])
end
```
