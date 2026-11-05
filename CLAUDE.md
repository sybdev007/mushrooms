# Midnight Mushroom Hunt (Lantern Forager): zasady dla Claude Code

Gra na Robloxie: nocne zbieranie grzybów z latarnią. Kod Luau `--!strict`, synchronizowany Rojo do Studia.
**Pełny stan projektu, historia i lista zadań: `docs/HANDOFF.md`. Przeczytaj go na start każdej sesji.**

## Kto i jak

- Tom (GitHub `sybdev007`, Roblox `noscopeninjadoritos`, UserId 1293490018) i Miłosz (GitHub `Develarper77`,
  Roblox `MiloszCzempion13`, UserId 7532199310). **Odpowiadaj po polsku** i używaj polskich nazw z gry.
- Kopia na PC: `T:\lantern\mushrooms` (Windows). Repo `sybdev007/mushrooms`, gałąź robocza `main`.
- Wolno ci commitować i pushować. Autor: `sybdev007 <347552131+sybdev007@users.noreply.github.com>`.
  Na końcu wiadomości commita: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Hasła i logowania (Roblox, GitHub, Creator Hub) Tom wpisuje sam.
- Publikuje Tom: Rojo Connect → poczekaj na synchronizację → File → Publish to Roblox →
  Creator Hub → Configurations → Server management → **Restart Servers** („only outdated versions”).

## Komendy

```
rokit install                      # raz: rojo 7.7.1, selene 0.31.0, lune 0.11.1
lune run tests/economy.spec.luau   # testy logiki (1368 ok); MUSZĄ przechodzić przed commitem
selene src                         # lint
rojo serve                         # synchronizacja ze Studiem
lune run tools/economy_sim.luau    # symulator ekonomii
lune run tools/forge_odds.luau     # szanse kuźni
lune run tools/night_forecast.luau # Krwawe księżyce na 7 dni (czas lokalny) do Roblox Events
```

Struktura: `src/server` → ServerScriptService.Server, `src/client` → StarterPlayerScripts.Client,
`src/shared` → ReplicatedStorage.Shared, `src/first` → ReplicatedFirst (ekran wczytywania),
`src/localization/GameStrings.csv` (kolumny `Key,Source,Context,Example,pl`, **bez przecinków w tekście**,
każdy klucz z `Localize.t` musi tu być; test to sprawdza). Liczby gry są w `src/shared/Config.luau`.

## Twarde zasady (każda kosztowała nas kiedyś błąd)

1. **Play w Studiu pisze do PRAWDZIWEGO DataStore** i otwiera sesję zapisu gracza. Jeśli Tom gra w tym czasie
   na żywo, wyrzuci go z gry („dane otwarte na innym serwerze”). Przed Play zapytaj, czy nie gra. Po testach,
   które zmieniły jego zapis (monety, śmierci, ucieczki), przywróć stan. Najprościej: na starcie akcja DEV
   `devSnapshot`, na końcu `devRestore` (koszyk, monety, Grzybopedia, liczniki, zadania; tylko w Studio).
2. **Każde nowe pole zapisu = podbij `DATA_VERSION`** w `src/server/DataService.luau` (teraz 10). Serwer ze starszą
   wersją wyrzuca gracza z nowszym zapisem, zamiast go nadpisać. Po publikacji zawsze Restart Servers.
3. **Gracz bez zapisu** (`profile.Data = {}`, brak starego zapisu → `raw = nil`) musi przejść przez `DataService.load`.
   Test „zupełnie nowy gracz” pilnuje tego; nie usuwaj go.
4. **Zdarzenia z serwera wysłane raz przy wejściu**: Roblox oddaje zdarzenie z kolejki tylko PIERWSZEMU podłączonemu
   odbiornikowi. Dlatego `ProgressUpdate` ma jedno podłączenie w `src/client/ProgressFeed.luau`; okna zapisują się
   przez `ProgressFeed.subscribe`. Nowe okno = `ProgressFeed.subscribe`, nigdy własne `OnClientEvent`.
   Ta sama zasada dla każdego nowego zdarzenia, którego słucha więcej niż jeden moduł.
5. Wejście gracza (`GameService.onPlayerAdded`) woła systemy przez `joinStep` (xpcall + ślad w konsoli serwera).
   Nowy system przy wejściu dodawaj tak samo.
6. Nagrody i walidacja tylko na serwerze; klientowi nie ufamy (`docs/REVIEW.md`).
7. Mikstura szczęścia i Wysyp to płatne produkty: żadnych darmowych zamienników (wyjątek: paczka Old Owl).
   Świadomy wyjątek (decyzja Toma 5.11): nagrody eventów sezonowych, czyli Halloween (ścieżka cukierków,
   kocioł) i Zima (ścieżka płatków, kalendarz, choinka), mogą dawać miksturę na kilka–kilkanaście minut.
   Poza eventami nie dodawaj nowych darmowych źródeł.
8. `Progress.rewardScale` to jednostka nagrody W MONETACH (las 1600), a nie mnożnik ~1.
9. Przed nadpisaniem pliku, który mógł zmienić Miłosz albo inna sesja, porównaj z GitHubem (`git fetch`, `git diff`).
10. Sprawdź gałąź przed pracą (`git status`): raz Rojo wgrał do Studia starą gałąź i Tom opublikował stary kod.
11. **Napis nad częścią świata** (BillboardGui w PlayerGui z Adornee): przypinaj przez `BillboardGuard.bind`
    (`src/client/BillboardGuard.luau`) i w pętli przepinaj na bieżącą część. Napis na części, która wypadła ze
    streamingu albo zginęła z postacią, Roblox rysuje w (0, 0, 0) przed chatką (tak wisiały dochody grządek,
    „Znalezisko Nocy” i tytuły graczy). Test „napisy nad częściami świata” łapie `.Adornee =` ustawiane wprost.

## Debugowanie gry na żywo

- Błędy serwera: w grze F9 → Log → przełącz **Client** na **Server** (widzą to tylko deweloperzy).
- Albo Creator Hub → Creations → gra → Monitoring → **Error Report**.
- Logi klienta i Studia na PC: `%LOCALAPPDATA%\Roblox\logs` (tylko komunikaty klienta/Studia, bez serwera na żywo).
- Studio MCP (Roblox Studio → Assistant → MCP): `execute_luau` w kontekście Server podczas Play ma dostęp do
  DataStore; w trybie Edit DataStore potrafi odpowiadać „Access forbidden”. Allowlista HTTP asystenta
  blokuje `raw.githubusercontent.com`.
