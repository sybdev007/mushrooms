# Lantern Forager (nazwa robocza)

Grzybobranie z latarnią w ciemnym lesie. Szary prototyp pętli:
**wchodzisz do lasu → zbierasz grzyby → wracasz, zanim zgaśnie latarnia → sprzedajesz → ulepszasz → idziesz głębiej.**

Wszystko jest z klocków. Celem tej wersji jest sprawdzenie, czy sama pętla wciąga, zanim wydamy czas na modele.

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
| `src/server/MapBuilder.luau` | ServerScriptService.Server | Buduje szarą mapę: chatka + 3 strefy lasu |
| `src/server/DataService.luau` | ServerScriptService.Server | Zapis postępu (DataStore) |
| `src/server/GameService.luau` | ServerScriptService.Server | Olej, zbieranie, sprzedaż, ulepszenia, „las cię pochłania” |
| `src/client/Hud.luau` | StarterPlayerScripts.Client | Interfejs pod telefon |
| `src/client/MushroomView.luau` | StarterPlayerScripts.Client | Rysowanie grzybów (każdy gracz ma własne) |
| `src/client/Atmosphere.luau` | StarterPlayerScripts.Client | Mrok i mgła zależne od strefy |
| `src/client/Localize.luau` | StarterPlayerScripts.Client | Tłumaczenia EN/PL |
| `src/localization/GameStrings.csv` | LocalizationService | Wszystkie teksty po angielsku i polsku |
| `tests/economy.spec.luau` | — | Testy logiki i balansu (Lune) |

## Jak działa prototyp

- **Strefy** ciągną się wzdłuż osi +Z: Chatka → Skraj lasu → Gęstwina → Mroczny Jar. Na granicach stoją świecące słupki.
- **Olej** spada w lesie (im głębiej, tym szybciej) i sam się uzupełnia w chatce. Poniżej 25% latarnia migocze.
- **Latarnia zgaśnie** → ekran ciemnieje, gracz wraca do chatki i traci wszystkie grzyby z koszyka.
- **Grzyby** są osobne dla każdego gracza (nikt nikomu nie wyzbiera), odrastają po 90 s, 3% szans na złotą mutację (×3 wartości).
- W **Gęstwinie i Jarze** widać tylko grzyby w zasięgu latarni. Złote i Świecący Muchomor widać zawsze, jako przynętę.
- **Chatka**: panel sprzedaży i 4 ulepszeń (latarnia, zbiornik oleju, koszyk, buty).
- **Sterowanie**: przycisk ZBIERZ obok przycisku skoku na telefonie, `E` na klawiaturze, `X` na padzie.
- **Język**: domyślnie z ustawień konta, przycisk w prawym górnym rogu przełącza EN/PL.

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

## Zapis w Studio

Żeby zapis działał przy testach w Studio: Game Settings → Security → **Enable Studio Access to API Services**.
Bez tego gra działa normalnie, ale pokazuje komunikat, że postęp nie jest zapisywany.

## Własna mapa zamiast klocków

Zrób w Workspace folder `Map` z częścią `SpawnPoint` i folderem `Spots`. Każda część w `Spots` to miejsce na grzyb
z atrybutem liczbowym `Zone` (2, 3 lub 4). Wtedy `MapBuilder` niczego nie buduje, tylko czyta waszą mapę.
Granice stref nadal wynikają z osi Z w `Config.Zones`.

## Co dalej (kolejność do ustalenia)

1. **Zagrać 15 minut na telefonie** i sprawdzić, czy chce się zrobić „jeszcze jedno wejście”.
2. Suszarnia w chatce (dochód pasywny, powód do powrotu za kilka godzin).
3. Wysyp i pogoda wspólna dla wszystkich serwerów, z prognozą na tablicy w chatce.
4. Atlas grzybów (`data.atlas` już zapisuje odkryte gatunki).
5. Grzyby-mimiki i Leszy w Mrocznym Jarze.
6. Przed publikacją: ProfileStore zamiast prostego DataStore, rzadsze wysyłanie stanu do klienta.
