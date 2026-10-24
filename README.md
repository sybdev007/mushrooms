# Lantern Forager (nazwa robocza)

Grzybobranie z latarnią w ciemnym lesie. Pętla:
**wchodzisz do lasu → zbierasz grzyby → wracasz, zanim zgaśnie latarnia → sprzedajesz albo suszysz → ulepszasz → idziesz głębiej.**

Dwa haki ponad podstawową pętlą:
- **Gniazdo Leszego** na końcu Mrocznego Jaru: zerwiesz Koronę Leszego, a on cię goni aż do chatki.
- **Suszarnie przed chatką**: grzyby schną i drożeją, ale inni gracze mogą je podkraść, gdy nie pilnujesz.

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
| `src/shared/Config.luau` | ReplicatedStorage.Shared | **Cały balans**: strefy, grzyby, ceny, ulepszenia |
| `src/shared/Economy.luau` | ReplicatedStorage.Shared | Czyste funkcje: koszty, losowanie gatunku, wartość koszyka |
| `src/shared/Remotes.luau` | ReplicatedStorage.Shared | Nazwy RemoteEventów |
| `src/shared/Sounds.luau` | ReplicatedStorage.Shared | ID dźwięków (sprawdzone, że się ładują) |
| `src/server/MapBuilder.luau` | ServerScriptService.Server | Rozkłada las: drzewa, krzaki, ścieżkę, bramy, miejsca na grzyby |
| `src/server/World/Cabin.luau` | ServerScriptService.Server | Chatka z bali z gankiem, kominkiem, ladą i suszarką |
| `src/server/World/Props.luau` | ServerScriptService.Server | Klocki świata: sosny, brzozy, dęby, kamienie, latarnie, tabliczki |
| `src/server/World/Palette.luau` | ServerScriptService.Server | Wszystkie kolory świata w jednym miejscu |
| `src/server/DataService.luau` | ServerScriptService.Server | Zapis postępu (DataStore) |
| `src/server/GameService.luau` | ServerScriptService.Server | Olej, zbieranie, sprzedaż, ulepszenia, „las cię pochłania” |
| `src/server/LeszyService.luau` | ServerScriptService.Server | Pościg Leszego po zerwaniu Korony |
| `src/server/DryingService.luau` | ServerScriptService.Server | Suszarnie: wieszanie, sprzedaż suszonych, kradzież |
| `src/server/World/Grove.luau` | ServerScriptService.Server | Gniazdo Leszego: krąg kamieni, tabliczka, uśpiony posąg |
| `src/server/World/Leszy.luau` | ServerScriptService.Server | Model Leszego z klocków |
| `src/server/World/Rack.luau` | ServerScriptService.Server | Model suszarni |
| `src/client/Hud.luau` | StarterPlayerScripts.Client | Interfejs pod telefon, deszcz monet po sprzedaży |
| `src/client/UiScale.luau` | StarterPlayerScripts.Client | Skala interfejsu zależna od ekranu |
| `src/client/MushroomView.luau` | StarterPlayerScripts.Client | Rysowanie grzybów (każdy gracz ma własne) |
| `src/client/Atmosphere.luau` | StarterPlayerScripts.Client | Mrok, mgła, kolory i niebo zależne od strefy |
| `src/client/Effects.luau` | StarterPlayerScripts.Client | Dźwięki, świetliki, iskry i „+N” przy zbieraniu, pierścień ulepszenia |
| `src/client/Warnings.luau` | StarterPlayerScripts.Client | Czerwona winieta, baner „Wracaj!” ze strzałką, oczy Leszego |
| `src/client/Signs.luau` | StarterPlayerScripts.Client | Napisy na tabliczkach w języku gracza |
| `src/client/RackPrompts.luau` | StarterPlayerScripts.Client | Pokazuje graczowi właściwe przyciski przy suszarniach |
| `src/client/Localize.luau` | StarterPlayerScripts.Client | Tłumaczenia EN/PL |
| `src/localization/GameStrings.csv` | LocalizationService | Wszystkie teksty po angielsku i polsku |
| `tests/economy.spec.luau` | — | Testy logiki i balansu (Lune) |

## Jak działa prototyp

- **Strefy** ciągną się wzdłuż osi +Z: Chatka → Skraj lasu → Gęstwina → Mroczny Jar. Na granicach stoją bramy z tabliczkami.
- **Olej** spada w lesie (im głębiej, tym szybciej) i sam się uzupełnia w chatce.
- **Ostrzeżenia**: przy 50% oleju komunikat, przy 25% latarnia migocze, pasek pulsuje, słychać serce, a brzegi ekranu czerwienieją.
  Niezależnie od procentów baner **„Wracaj do chatki!”** ze strzałką i odległością pojawia się, gdy oleju zostaje
  tyle, ile potrzeba na powrót (z 30% zapasu, `Config.ReturnMargin`). Liczy to `Economy.shouldTurnBack`.
- Gdy olej prawie się kończy w Gęstwinie lub Jarze, z ciemności patrzą **czerwone oczy Leszego**.
- **Latarnia zgaśnie** → ekran ciemnieje, gracz wraca do chatki i traci wszystkie grzyby z koszyka.
- **Grzyby** są osobne dla każdego gracza (nikt nikomu nie wyzbiera), odrastają po 90 s, 3% szans na złotą mutację (×3 wartości).
- W **Gęstwinie i Jarze** widać tylko grzyby w zasięgu latarni. Złote i Świecący Muchomor widać zawsze, jako przynętę.
- **Chatka**: panel sprzedaży i 5 ulepszeń (latarnia, zbiornik oleju, koszyk, buty, kłódka suszarni).
- **Gniazdo Leszego** (koniec Jaru, `Config.Grove`): krąg kamieni z 3 Koronami Leszego (220 monet, każdy gracz ma własne,
  odrastają po 4 min). Zerwanie budzi Leszego: rusza z gniazda po 2 s, przenika przez drzewa i biegnie 22 studs/s.
  Złapie = tracisz koszyk. Dobiegniesz do polany = ucieczka. Bez ulepszeń butów nie da się uciec, od poziomu 3 już tak
  (pilnują tego testy, `Economy.escapesLeszy`). Wszyscy na serwerze widzą, kogo goni.
- **Suszarnie** (`Config.Drying`): 8 miejsc na polanie, każdy gracz dostaje jedną z tabliczką z imieniem.
  Właściciel: „Rozwieś grzyby” (najcenniejsze świeże z koszyka, do 6 sztuk) i „Sprzedaj suszone”.
  Grzyb schnie 10 min (także offline) i wtedy jest wart 2×. Inni gracze: „Podkradnij” zabiera najcenniejszy grzyb
  do ich koszyka. Trzeba trzymać przycisk (2 s + poziom kłódki), nie da się, gdy właściciel stoi przy suszarni,
  a po kradzieży suszarnia ma 25 s ochrony. Właściciel dostaje alarm, gdy ktoś zaczyna kraść.
- **Sterowanie**: przycisk ZBIERZ obok przycisku skoku na telefonie, `E` na klawiaturze, `X` na padzie.
- **Język**: domyślnie z ustawień konta, przycisk pod licznikiem monet przełącza EN/PL (także napisy na tabliczkach).
- **Lista graczy** pokazuje monety wszystkich na serwerze (kolumna 💰).

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

## Rozmiar serwera

Suszarni jest 8, więc ustaw serwer na **8 graczy**: w Studio File → Game Settings → Places → (…) przy miejscu →
Server Size / Max Players, albo w Creator Hub w ustawieniach miejsca. Gracz ponad limit suszarni dostaje komunikat,
że nie ma wolnej. Małe serwery to też większa szansa, że okradnie cię ktoś, kogo potem rozpoznasz.

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
2. ~~Suszarnia~~ zrobione (przed chatką, z kradzieżą). Dalej: więcej miejsc na suszarni jako ulepszenie.
3. Wysyp i pogoda wspólna dla wszystkich serwerów, z prognozą na tablicy w chatce.
4. Atlas grzybów (`data.atlas` już zapisuje odkryte gatunki).
5. ~~Leszy~~ zrobione (pościg z gniazda). Dalej: grzyby-mimiki.
6. Przed publikacją: ProfileStore zamiast prostego DataStore, rzadsze wysyłanie stanu do klienta.
