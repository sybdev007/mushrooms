# Lantern Forager (nazwa robocza)

Grzybobranie z latarnią w ciemnym lesie. Pętla:
**wchodzisz do lasu → zbierasz grzyby → wracasz, zanim zgaśnie latarnia → sprzedajesz albo sadzisz w ogródku → ulepszasz → idziesz głębiej.**

Haki ponad podstawową pętlą:
- **Gniazdo Leszego** na końcu Mrocznego Jaru: zerwiesz Koronę Leszego, a on cię goni aż do chatki.
- **Jaskinia** za portalem w Gnieździe Leszego: drugi świat od 50 000 monet, z własnym obozowiskiem, grzybami i ulepszeniami.
- **Bagna** za portalem w Sztolni Skarbnika: trzeci świat od 1 000 000 monet, z Utopcem i błędnymi ognikami.
- **Ogródki jak w Steal an Egg**: posadzony grzyb co minutę sypie monety, ale inni gracze mogą go wyrwać i nieść do siebie. Dogonisz złodzieja = grzyb wraca.

Świat jest kreskówkowym low-poly budowanym kodem (bez importowanych modeli): chatka z bali, jesienny las,
ścieżka z latarniami, bramy stref, świecące grzyby, świetliki i mgła. Działa od razu po `rojo serve`.

## Start (raz na komputer)

1. Zainstaluj [Rokit](https://github.com/rojo-rbx/rokit), potem w folderze projektu:
   ```
   rokit install
   ```
   To instaluje Rojo, Selene i Lune w wersjach z `rokit.toml`, takich samych dla ciebie i Miłosza.
2. W Studio zainstaluj plugin Rojo (Plugins → Manage Plugins albo `rojo plugin install`).

## Praca na co dzień

```
rojo serve
```
Otwórz pusty place w Studio, w pluginie Rojo kliknij **Connect**. Kod z `src/` synchronizuje się na żywo.
Kod edytujecie w edytorze (VS Code + rozszerzenie Luau LSP), a nie w Studio, bo Rojo nadpisze zmiany zrobione w Studio.

Zbudowanie pliku miejsca bez Studio:
```
rojo build -o lantern-forager.rbxlx
```

## Struktura

| Ścieżka | Trafia do | Co robi |
|---|---|---|
| `src/first/LoadingScreen.client.luau` | ReplicatedFirst | Ekran wczytywania: etapy wczytywania, postać stoi, dopóki pod nią nie ma podłogi, przejście do intra |
| `src/first/LoadingUI.luau` | ReplicatedFirst | Wygląd ekranu wczytywania: tło, pasek z dynią albo grzybkiem, wskazówki, iskry |
| `src/first/LoadingTheme.luau` | ReplicatedFirst | Motyw ekranu (`ACTIVE`), teksty PL/EN, numery obrazków |
| `src/shared/Config.luau` | ReplicatedStorage.Shared | **Cały balans**: strefy, grzyby, ceny, ulepszenia |
| `src/shared/Economy.luau` | ReplicatedStorage.Shared | Czyste funkcje: koszty, losowanie gatunku, wartość koszyka |
| `src/shared/Remotes.luau` | ReplicatedStorage.Shared | Nazwy RemoteEventów |
| `src/shared/Cycle.luau` | ReplicatedStorage.Shared | Dzień i noc z zegara: faza, koniec fazy, zdarzenie nocy |
| `src/shared/Sounds.luau` | ReplicatedStorage.Shared | ID dźwięków (sprawdzone, że się ładują) |
| `src/server/MapBuilder.luau` | ServerScriptService.Server | Rozkłada las: drzewa, krzaki, ścieżkę, bramy, miejsca na grzyby |
| `src/server/World/Cabin.luau` | ServerScriptService.Server | Chatka z bali z gankiem, kominkiem, ladą i suszarką |
| `src/server/World/Props.luau` | ServerScriptService.Server | Klocki świata: sosny, brzozy, dęby, kamienie, latarnie, tabliczki |
| `src/server/World/Palette.luau` | ServerScriptService.Server | Wszystkie kolory świata w jednym miejscu |
| `src/server/DataService.luau` | ServerScriptService.Server | Zapis postępu (DataStore) |
| `src/server/GameService.luau` | ServerScriptService.Server | Olej, zbieranie, sprzedaż, ulepszenia, „las cię pochłania” |
| `src/server/ChaseService.luau` | ServerScriptService.Server | Pościg strażnika (Leszy, Skarbnik) po zerwaniu jego grzyba |
| `src/server/World/Skarbnik.luau` | ServerScriptService.Server | Model Skarbnika (siatka 3D, zapasowo z klocków) |
| `src/server/World/Swamp.luau` | ServerScriptService.Server | Bagna: przystań, kładka, rozlewiska, wierzby, ogniki, staw Utopca |
| `src/server/World/Utopiec.luau` | ServerScriptService.Server | Model Utopca (siatka 3D, zapasowo z klocków) |
| `src/server/HoardService.luau` | ServerScriptService.Server | Skarbiec Leszego: korony odebrane złapanym, do zgarnięcia przez każdego |
| `src/server/GardenService.luau` | ServerScriptService.Server | Ogródki: sadzenie, dochód co minutę i offline, skrzynia, kradzież z noszeniem łupu |
| `src/server/World/Grove.luau` | ServerScriptService.Server | Gniazdo Leszego: krąg kamieni, tabliczka, uśpiony posąg |
| `src/server/World/Leszy.luau` | ServerScriptService.Server | Model Leszego z klocków |
| `src/server/World/Beds.luau` | ServerScriptService.Server | Siatka grządek 3 x 3 w ogródku |
| `src/server/World/Cave.luau` | ServerScriptService.Server | Jaskinia: obozowisko, skalne ściany, strop, kryształy, jezioro, lawa, portale |
| `src/server/World/Garden.luau` | ServerScriptService.Server | Ogródek gracza: płot, furtka z imieniem, grządki, skrzynia na monety, rabatki |
| `src/client/Hud.luau` | StarterPlayerScripts.Client | Interfejs pod telefon, deszcz monet po sprzedaży |
| `src/client/UiScale.luau` | StarterPlayerScripts.Client | Skala interfejsu zależna od ekranu |
| `src/client/MushroomView.luau` | StarterPlayerScripts.Client | Rysowanie grzybów (każdy gracz ma własne) |
| `src/client/Atmosphere.luau` | StarterPlayerScripts.Client | Mrok, mgła, kolory i niebo zależne od strefy |
| `src/client/Effects.luau` | StarterPlayerScripts.Client | Dźwięki, świetliki, iskry i „+N” przy zbieraniu, pierścień ulepszenia |
| `src/client/Warnings.luau` | StarterPlayerScripts.Client | Czerwona winieta, baner „Wracaj!” ze strzałką, oczy Leszego |
| `src/client/Signs.luau` | StarterPlayerScripts.Client | Napisy na tabliczkach w języku gracza |
| `src/client/SellPanel.luau` | StarterPlayerScripts.Client | Panel sprzedaży u skupywacza: karty grzybów, sprzedaj jeden / zaznaczone / wszystko |
| `src/client/MerchantView.luau` | StarterPlayerScripts.Client | Skupywacz: teksty, obracanie się do gracza, otwieranie panelu sprzedaży |
| `src/server/World/Merchant.luau` | ServerScriptService.Server | Model skupywacza (Pan Borowik) z kapeluszem-muchomorem |
| `src/client/ShopPanel.luau` | StarterPlayerScripts.Client | Sklep za Robuxy, ratunek koszyka, szybki olej, liczniki Wysypu i mikstury |
| `src/client/Purchases.luau` | StarterPlayerScripts.Client | Okno płatności Robloxa i ceny produktów |
| `src/client/GardenPrompts.luau` | StarterPlayerScripts.Client | Pokazuje graczowi właściwe przyciski w ogródkach |
| `src/client/BestiaryPage.luau` | StarterPlayerScripts.Client | Zakładka Strażnicy w Grzybopedii: portrety, opisy, liczby i liczniki |
| `src/client/Localize.luau` | StarterPlayerScripts.Client | Tłumaczenia EN/PL |
| `src/localization/GameStrings.csv` | LocalizationService | Wszystkie teksty po angielsku i polsku |
| `tests/economy.spec.luau` | — | Testy logiki i balansu (Lune) |

## Jak działa prototyp

- **Strefy** ciągną się wzdłuż osi +Z: Chatka → Skraj lasu → Gęstwina → Mroczny Jar. Na granicach stoją bramy z tabliczkami.
- **Olej** spada w lesie (im głębiej, tym szybciej). Napełnia się tylko w świecącym kręgu przy beczce w chatce (`Config.Stations.oil`).
- **Ostrzeżenia**: przy 50% oleju komunikat, przy 25% latarnia migocze, pasek pulsuje, słychać serce, a brzegi ekranu czerwienieją.
  Niezależnie od procentów baner **„Wracaj do chatki!”** ze strzałką i odległością pojawia się, gdy oleju zostaje
  tyle, ile potrzeba na powrót (z 30% zapasu, `Config.ReturnMargin`). Liczy to `Economy.shouldTurnBack`.
- Gdy olej prawie się kończy w Gęstwinie lub Jarze, z ciemności patrzą **czerwone oczy Leszego**.
- **Latarnia zgaśnie** → ekran ciemnieje, gracz wraca do chatki i traci wszystkie grzyby z koszyka.
- **Grzyby** są osobne dla każdego gracza (nikt nikomu nie wyzbiera), odrastają po 90 s. Mutacje: Srebro ×1,5, Złoto ×3, Tęcza ×8, plus cechy od miejsca (Mech, Blask).
- W **Gęstwinie i Jarze** widać tylko grzyby w zasięgu latarni. Złote i Świecący Muchomor widać zawsze, jako przynętę.
- **Chatka** (36 x 32 studs): na środku tylnej ściany, za ladą, stoi skupywacz **Pan Borowik** (`Config.Merchant`). Przycisk „Sprzedaj grzyby” otwiera panel
  z kartami grzybów z koszyka (kapelusz w kolorze gatunku lub mutacji, nazwa w kolorze klasy, cena): można sprzedać
  jeden, zaznaczone albo wszystko. Serwer sprawdza odległość od skupywacza i odcisk koszyka. W obozowiskach panel
  otwiera się w kręgu przy kramiku. W chatce są też półki ze świecącymi słoikami, stolik z lampką-muchomorem,
  a na ganku ławka i doniczki.
- **Ulepszenia**: fioletowy przycisk „Ulepszenia” przy prawej krawędzi ekranu albo klawisz **R** (Y na padzie).
  Czerwona kropka pokazuje, na ile ulepszeń gracza stać. Panel ma kolorowe karty (ikona, opis, kropki poziomów,
  wartość „x1 » x1.25”, przycisk z ceną) i zakładki Las / Jaskinia / Bagna, gdy są odblokowane; kupuje się
  w bezpiecznej strefie danego świata (leśne w chatce i na polanie).
- **Ikony**: dwa arkusze z Figmy, `assets/ui-icons.png` i `assets/ui-icons-2.png` (ramka „sprite/ui-icons-2”, źródła SVG
  w `assets/icons2/`). Numery obrazków są w `Config.UiIcons` i `Config.UiIcons2`; bez numeru UiKit pokazuje emoji.
- **Gniazdo Leszego** (koniec Jaru, `Config.Grove`): krąg kamieni z 3 Koronami Leszego (220 monet, każdy gracz ma własne,
  odrastają po 4 min). Zerwanie budzi Leszego: rusza z gniazda po 2 s, przenika przez drzewa i biegnie 22 studs/s.
  Złapie = tracisz koszyk, a Leszy odnosi zabrane korony do **skarbca** na środku gniazda (`HoardService`). Skarbiec jest wspólny:
  każdy na serwerze dostaje ogłoszenie i może pobiec po korony, ale zabranie korony znów budzi Leszego. Dobiegniesz do polany = ucieczka. Bez ulepszeń butów nie da się uciec, od poziomu 3 już tak
  (pilnują tego testy, `Economy.escapesLeszy`). Wszyscy na serwerze widzą, kogo goni.
- **Ogródki** (`Config.Garden`, `GardenService`): 4 ogródki, po dwa z każdej strony chatki, furtką do środka polany.
  Każdy gracz dostaje własny, z imieniem na furtce. W środku siatka 9 grządek, z czego na start odblokowane są 3
  (ulepszenie **Grządki**, do 9). „Posadź grzyby” sadzi najcenniejsze z koszyka; gdy grządki są pełne, lepszy grzyb
  wypiera najsłabszy (ten jest sprzedawany). Posadzony grzyb daje co minutę 4% swojej wartości (zwrot po 25 min),
  ulepszenie **Nawóz** mnoży dochód do 3×. Monety zbierają się w skrzyni przy furtce, także offline (do 2 godzin).
  Nad każdą grządką tabliczka z mutacjami, wartością i `+X/min`.
- **Kradzież jak w Steal an Egg**: inny gracz trzyma „Wyrwij grzyb” (2 s + poziom kłódki) i zabiera najcenniejszy.
  Niesie go nad głową, podświetlony na czerwono dla wszystkich, wolniej niż zwykle (zwykły łup 85% prędkości,
  tęcza 60%, korony strażników 60%). Doniesie do swojego ogródka = łup rośnie u niego. Właściciel go dotknie
  (6 studs) = grzyb wraca. Wyjście z polany, minuta bez doniesienia albo reset postaci = grzyb wraca.
  Nie da się kraść, gdy właściciel stoi przy swoich grządkach, a po kradzieży ogródek ma 25 s ochrony.
  Właściciel dostaje alarm, gdy ktoś zaczyna wyrywać, i drugi, gdy złodziej ucieka.
- **Jaskinia** (`Config.Cave`, strefy z `world = "cave"`): portal za Gniazdem Leszego wpuszcza graczy, którzy mają
  co najmniej 50 000 monet (monety zostają, a jaskinia zostaje otwarta na zawsze, `data.caveUnlocked`).
  Obozowisko górników jest bezpieczne: beczki z olejem, kramik ze skupem i dwoma ulepszeniami jaskini
  (Kryształowy knot: mniej oleju w jaskini, Plecak górnika: większy koszyk) i portal z powrotem do chatki.
  Dalej Kryształowe Korytarze → Podziemne Jezioro → Otchłań → Sztolnia Skarbnika, 9 nowych gatunków (do 2200 monet za Serce Góry)
  i cechy Kryształ i Żar Otchłani. Zgaśnięcie latarni w jaskini = pobudka w obozowisku. Leszy nie wchodzi do jaskini:
  wskoczenie w portal kończy pościg. Testy pilnują, że z maks. leśnymi ulepszeniami dojdziesz do Jeziora,
  a do końca Otchłani dopiero z Kryształowym knotem.
- **Skarbnik** (`Config.Lair`, `Config.Skarbnik`): duch kopalni ze śląskich legend pilnuje Złotych Trufli (6000 monet)
  w skarbcu na końcu Sztolni. Działa jak Leszy (wspólny `ChaseService` i `HoardService`): zerwanie budzi go,
  goni do obozowiska, złapie = koszyk przepada, a trufle wracają do skarbca dla każdego.
- **Jaskinia wygląda**: świecące robaczki na stropie, gigantyczne świecące grzyby z opadającymi zarodnikami,
  wodospady przy jeziorkach, rzeka lawy z mostem, wózki z rudą, świecący mech, kamyki.
- **Bagna** (`Config.Swamp`, strefy z `world = "swamp"`, `World/Swamp.luau`): portal za skarbcem Skarbnika
  wpuszcza od 1 000 000 monet (zapis `swampUnlocked`), skrót na Placu Portali po lewej. Przystań rybaków na palach
  (olej, skup, dwa ulepszenia: Knot z sitowia i Wiklinowy kosz) → Trzęsawisko → Mokradła Ogników → Staw Utopca.
  Otwarte niebo, zielona mgła, kładka środkiem, rozlewiska z liliami, wierzby płaczące, trzciny, latające ogniki.
  **Błędne ogniki** (`mimic`): wyglądają jak cenny Ognik, ale zerwanie kradnie 35% oleju; zdradza je tylko
  nierówno drgające światło. **Utopiec** pilnuje Kielichów (60 000) na wyspie pośrodku stawu, budzi się prawie
  od razu i ucieka się przed nim tylko na maksymalnych butach.
- **Strażnicy** (`GUARDIANS` w `GameService`): Leszy, Skarbnik i Utopiec działają według tych samych zasad;
  nowy strażnik to wpis w tabeli, model w `World/` i miejsca na mapie.
- **Las**: drzewa stoją korona przy koronie, bez nachodzenia (`CANOPY` w `MapBuilder`). Obrzeże mapy jest stawiane
  pierwsze, a reszta lasu je omija.
- **Nożyk** (ulepszenie `knife`, 6 poziomów): mnoży szanse na mutacje do ×2,5. Nóż w lewej ręce zmienia kolor
  z poziomem (`Config.KnifeColors`), od 4. poziomu ostrze świeci.
- **Klasy grzybów** (`Config.Classes`, `Economy.speciesClass`): Pospolity, Niepospolity, Rzadki, Epicki według tego,
  jak często gatunek rośnie, a grzyby strażników zawsze Legendarne. Celowany grzyb ma obwódkę i napis
  „Borowik · Rzadki” w kolorze klasy; tabliczki w ogródku też mają kolor klasy.
- **Głębiej = częstsze mutacje** (`Config.DepthLuck`, `Economy.zoneLuck`): pierwsza niebezpieczna strefa świata ×1,
  każda kolejna +0,3 (Gęstwina ×1,3, Jar ×1,6, w jaskini i na bagnach tak samo).
- **Grzybopedia** (`src/shared/Progress.luau`, `ProgressService`, okno `AtlasPanel`, przycisk 📖 obok języka):
  każdy gatunek w 4 formach (zwykła, srebrna, złota, tęczowa), strona = świat. Odkryte formy w kolorze,
  nieodkryte to czarne sylwetki, nieznany gatunek ma nazwę „???”. Progi strony (każdy grzyb odkryty /
  co najmniej srebrny / złoty / tęczowy) dają na zawsze +3/+3/+5/+10% do ceny przy sprzedaży, a złota i tęczowa
  strona dają tytuł nad głową (`TitleView`: Znawca Lasu, Mistrz Bagien… i Arcygrzybiarz za wszystko na tęczę).
  Zapis: `atlas[gatunek]` = maska bitów form (stare `true` = zwykła).
- **Strażnicy w Grzybopedii** (`Progress.GUARDIANS`, strona `BestiaryPage`, ostatnia zakładka księgi): karta każdego
  strażnika z portretem 3D (ViewportFrame z modelem z `ReplicatedStorage.GuardianPortraits`, budowanym w tle przez
  `GameService`). Strażnika poznaje się dopiero, gdy ukradnie mu się strzeżony grzyb (z legowiska albo ze skarbca);
  wcześniej to czarna sylwetka z kłódką, „???” i tylko nazwą kryjówki. Odkryty ma legendę, przydomek, liczby z Config
  (szybkość, budzenie, próg butów do ucieczki liczony przez `Progress.bootsToEscape`, bezpieczna strefa), własne
  liczniki gracza (skradzione / ucieczki / złapał cię) i radę. Pierwsze odkrycie daje komunikat, a Grzybopedia
  otwiera się wtedy od razu na jego karcie. Zapis: `bestiary[strażnik] = { found, stolen, escaped, caught }`;
  stare zapisy z grzybem strażnika w księdze dostają go od razu (`Progress.migrateBestiary`).
  Nowy strażnik = wpis w `Progress.GUARDIANS` i teksty `BOSS_<ID>`, `_TITLE`, `_LORE`, `_TIP` w CSV.
  Panel DEV: „Strażnicy: odkryj następnego”, „Strażnicy: wyczyść”.
- **Codzienne zadania i seria logowań** (`Progress.QUESTS`, okno `QuestPanel`, przycisk 📜): 3 zadania dziennie
  (każdy gracz ma swój zestaw, raz dziennie można jedno wymienić), np. zbierz 30 grzybów, znajdź złotego,
  ucieknij strażnikowi, donieś łup. Nagrody przychodzą same; za wszystkie trzy premia i 5 min mikstury szczęścia.
  Seria logowań 7 dni w kółko (7. dzień: mikstura na 10 min), dzień przerwy zeruje serię. Nowy dzień o północy UTC.
  Nagrody rosną z najdalszym odblokowanym światem (`Progress.rewardScale`).
- **Rankingi** (`LeaderboardService`, model `World/Boards.luau`, rysuje `LeaderboardView`): trzy tablice na polanie
  przed chatką: Najbogatsi grzybiarze, Znalezisko tygodnia (brama nad ścieżką) i Złodzieje tygodnia.
  OrderedDataStore wspólny dla wszystkich serwerów, tygodniowe tablice zerują się w poniedziałek. Bez dostępu do
  DataStore (Studio bez API) pokazują graczy z tego serwera. Panel DEV: „Księga…”, „Zadania…”, „Rankingi: odśwież”.
- **Wspólne wyprawy** (`src/shared/Expedition.luau`, `ExpeditionView`): gracze w niebezpiecznej strefie bliżej niż
  20 studs łączą latarnie. Grupa 2: olej −25%, światło +25%; 3: −35% / +40%; 4: −40% / +50%. Plakietka obok paska
  oleju. Gdy komuś zgaśnie latarnia, a ktoś jest w promieniu 150 studs, gracz nie znika od razu: stoi w mroku
  z napisem 🆘 nad głową przez 15 s, a kumpel podchodzi i trzyma F („Podnieś”), żeby oddać mu 30% oleju.
  Bez pomocy las pochłania jak zwykle. Butelka oleju za Robuxy też podnosi. Zadanie dnia „Podnieś kumpla”.
  Panel DEV: „Wyprawa: grupa x3”, „Wyprawa: zgaś mi latarnię”.
- **Balans szczęścia** (`Config.LuckBalance`, `Economy.luck`): szczęście ×N działa jak N rzutów, z których liczy się
  najlepszy (`1 − (1 − szansa)^N`), więc szanse nigdy nie dochodzą do 100%. Darmowe bonusy (nożyk × głębokość × noc)
  mają malejący zysk i razem zbliżają się do ×5; płatne (Wysyp ×1,5, mikstura ×2) mnożą w pełni; całość najwyżej ×8.
  Gracz widzi wszystkie procenty w sklepie pod przyciskiem **% Szanse** (`OddsPanel`).
- **Dzień i noc** (`Config.Cycle`, `src/shared/Cycle.luau`): 18 min nocy i 2 min świtu, liczone z zegara, więc na
  wszystkich serwerach jest ta sama pora. Każda noc ma zdarzenie: Spokojna noc, Pełnia (mutacje ×1,5), Deszcz
  (odrost 2× szybciej), Gęsta mgła (widać mniej, mutacje ×1,3), Krwawy księżyc (mutacje ×2,5, rzadki).
  O świcie niebo się rozjaśnia, a las u każdego gracza odrasta od nowa (nowe gatunki i mutacje), z prognozą
  następnej nocy. Pora i licznik są w HUD przed nazwą strefy. Panel DEV ma „Świt teraz” i „Noc teraz”.
- **Sterowanie**: przycisk ZBIERZ obok przycisku skoku na telefonie, `E` na klawiaturze, `X` na padzie.
- **Język**: domyślnie z ustawień konta, przycisk pod licznikiem monet przełącza EN/PL (także napisy na tabliczkach).
- **Lista graczy** pokazuje monety wszystkich na serwerze (kolumna 💰).
- **Kamera** oddala się najwyżej na `Config.CameraMaxZoom` (22 studs) i przysuwa się, gdy zasłaniają ją drzewa, więc nie da się oglądać lasu z góry.

Serwer jest jedynym źródłem prawdy: klient tylko prosi („zbierz ten grzyb”), a serwer sprawdza odległość, pojemność koszyka, strefę i monety.

## Balans

Zmieniasz liczby w `src/shared/Config.luau`, potem uruchamiasz testy:
```
lune run tests/economy.spec.luau
```
Testy pilnują m.in., żeby:
- pierwszy pełny koszyk wystarczał na jakieś ulepszenie,
- na start dało się przejść Skraj lasu, ale **nie** dotrzeć do Mrocznego Jaru bez ulepszeń,
- z pełnymi ulepszeniami dało się przejść cały las,
- każdy tekst miał wersję EN i PL.

Lint: `selene src`

## Zakupy za Robuxy

Pięć produktów (`Config.Products`): **Zachowaj grzyby** (przycisk na czarnym ekranie po zgaśnięciu latarni
lub złapaniu przez strażnika, przez 15 s), **Wysyp dla wszystkich** (10 min szybszego odrostu i więcej mutacji
na całym serwerze, z ogłoszeniem, kto zafundował), **Butelka oleju** (też szybki przycisk przy pasku oleju,
gdy w lesie spada poniżej 40%), **Zbiory od razu** (30 minut dochodu z ogródka do skrzyni) i **Mikstura szczęścia** (15 min, 2× mutacje).
Sklep otwiera przycisk 🛒 pod przełącznikiem języka.

Jak podpiąć: Creator Hub → gra → Monetization → **Developer Products** → utwórz 5 produktów (nazwa, ikonka, cena),
skopiuj ich numery do `Config.Products` (pole `id`). Dopóki `id = 0`, w Studio zakup działa za darmo (do testów),
a w prawdziwej grze przycisk jest ukryty. Serwer obsługuje zakupy w `ProcessReceipt` i zapamiętuje ostatnie
numery zakupów, więc ten sam zakup nigdy nie da rzeczy dwa razy.

## Ekran wczytywania

Własny ekran zamiast domyślnego Robloxa (`src/first`, czyli ReplicatedFirst). Zasłania wczytywanie mapy
(przy StreamingEnabled świat dochodzi kawałkami) i trzyma postać w miejscu, aż pod nogami jest podłoga,
więc nikt już nie spada z mapy na starcie. Nowemu graczowi intro startuje dopiero po ekranie, z czerni.

- Motyw: `LoadingTheme.ACTIVE` = `"halloween"` (dynia toczy się po pasku) albo `"forest"` (grzybek skacze
  i zostawia świecące kiełki). Po Halloween wystarczy zmienić tę jedną linijkę.
- Grafiki: `assets/loading/` (tła i arkusz dyni/grzybków). Arkusz rysuje `python3 tools/loading_art.py`
  (SVG → PNG przez Playwright). Po zmianie: wgraj w Studio (Asset Manager → Bulk Import) i wpisz numery
  w `LoadingTheme`. Pusty numer = ekran działa dalej, tylko bez tła i z emoji zamiast dyni.
- Podgląd bez wchodzenia do gry: w trakcie Play, w pasku poleceń (Client)
  `require(game.ReplicatedFirst.LoadingUI).preview("forest", 12)`.

## Rozmiar serwera

Ogródków jest 6 (`Config.Garden.plots`), więc ustaw serwer na **6 graczy**: w Studio File → Game Settings → Places → (…) przy miejscu →
Server Size / Max Players, albo w Creator Hub w ustawieniach miejsca. Gracz ponad limit suszarni dostaje komunikat,
że nie ma wolnego ogródka. Małe serwery to też większa szansa, że okradnie cię ktoś, kogo potem rozpoznasz.

## Zapis w Studio

Żeby zapis działał przy testach w Studio: Game Settings → Security → **Enable Studio Access to API Services**.
Bez tego gra działa normalnie, ale pokazuje komunikat, że postęp nie jest zapisywany.

## Własna mapa zamiast klocków

Zrób w Workspace folder `Map` z częścią `SpawnPoint` i folderem `Spots`. Każda część w `Spots` to miejsce na grzyb
z atrybutem liczbowym `Zone` (2, 3 lub 4). Wtedy `MapBuilder` niczego nie buduje, tylko czyta waszą mapę.
Granice stref nadal wynikają z osi Z w `Config.Zones`.

## Co dalej (kolejność do ustalenia)

1. **Zagrać 15 minut na telefonie** i sprawdzić, czy chce się zrobić „jeszcze jedno wejście”.
   Mapa ma ok. 7 tys. części; jeśli słabszy telefon klatkuje, pierwsze do odchudzenia są rzędy sosen na brzegach.
2. ~~Suszarnia~~ zastąpiona ogródkami z grządkami (sadzenie, dochód, kradzież z noszeniem).
3. Wysyp i pogoda wspólna dla wszystkich serwerów, z prognozą na tablicy w chatce.
4. Atlas grzybów (`data.atlas` już zapisuje odkryte gatunki).
5. ~~Leszy~~ zrobione (pościg z gniazda). Dalej: grzyby-mimiki.
6. Przed publikacją: ProfileStore zamiast prostego DataStore, rzadsze wysyłanie stanu do klienta.
