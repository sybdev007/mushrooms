# Odznaki Robloxa (badges)

Gra sama przyznaje odznaki (`ProgressService` → `BadgeService.AwardBadgeAsync`), ale każdą trzeba raz
założyć w Creator Hub i wpisać jej numer do `Config.Badges` w `src/shared/Config.luau`.
Dopóki numer to `0`, gra tej odznaki nie przyznaje (nic się nie psuje).

Gracze, którzy zdobyli coś przed założeniem odznaki, dostaną ją przy najbliższym zdarzeniu w grze
(zebranie grzyba, sprzedaż itp.), bo gra sprawdza osiągnięcia z zapisu, a nie tylko „w tej chwili”.

## Jak założyć odznakę

1. Wejdź na https://create.roblox.com/dashboard/creations i najedź na miniaturkę gry.
2. Kliknij `⋯` → **Create Badge**.
3. Wgraj obrazek z `assets/badges/` (512 × 512, Roblox przytnie go do koła).
4. Wpisz nazwę i opis z tabeli poniżej, zostaw **Enabled**, kliknij **Create Badge**.
5. Otwórz odznakę (Engagement → Badges), skopiuj jej numer (Badge ID) i wpisz go w `Config.Badges`.

Za darmo jest **5 odznak na dobę na grę** (kolejne po 100 Robux), więc najlepiej zakładać
po 5 dziennie: najpierw pierwsze pięć z tabeli (te zdobywa najwięcej graczy).

## Lista

| Klucz w `Config.Badges` | Obrazek | Nazwa (EN) | Opis (EN) | Po polsku |
|---|---|---|---|---|
| `first_mushroom` | `first_mushroom.png` | First Mushroom | Put your first mushroom in the basket. | Pierwszy grzyb – włóż pierwszy grzyb do koszyka |
| `cave` | `cave.png` | Into the Caves | Open the portal to the Caves. | Do jaskini – otwórz portal do jaskini |
| `gold` | `gold.png` | Golden Find | Find a Gold mushroom. | Złote znalezisko – znajdź złotego grzyba |
| `leszy` | `leszy.png` | Leshy's Thief | Steal the Leshy's crown mushroom. | Złodziej Leszego – ukradnij grzyb z Gniazda Leszego |
| `atlas_page` | `atlas_page.png` | Full Page | Find every mushroom on one Atlas page. | Pełna strona – znajdź każdy grzyb na stronie Grzybopedii |
| `swamp` | `swamp.png` | Into the Swamps | Open the portal to the Swamps. | Na bagna – otwórz portal na bagna |
| `skarbnik` | `skarbnik.png` | Skarbnik's Thief | Steal a truffle from Skarbnik's vault. | Złodziej Skarbnika – ukradnij truflę ze skarbca |
| `utopiec` | `utopiec.png` | Utopiec's Thief | Steal the chalice from the Utopiec's pond. | Złodziej Utopca – ukradnij kielich ze stawu Utopca |
| `rainbow` | `rainbow.png` | Rainbow Hunter | Find a Rainbow mushroom. | Łowca tęczy – znajdź tęczowego grzyba |
| `lifesaver` | `lifesaver.png` | Lifesaver | Help up a friend whose lantern went out. | Ratownik – podnieś kumpla, któremu zgasła latarnia |
| `streak7` | `streak7.png` | Regular Forager | Play 7 days in a row. | Stały bywalec – graj 7 dni z rzędu |
| `grandmaster` | `grandmaster.png` | Grand Forager | Find every mushroom in Rainbow form. | Arcygrzybiarz – cała Grzybopedia tęczowa |
| `halloween2026` | `halloween2026.png` | Halloween 2026 | Collect 100 candy during the 2026 Halloween event. | Halloween 2026 – zbierz 100 cukierków w czasie eventu (do 9 listopada) |

## Sprawdzenie

Odznaki działają tylko w opublikowanej grze (w Studio `AwardBadgeAsync` zwykle zwraca błąd,
który gra tylko wypisze w Output jako ostrzeżenie). Najprościej: opublikuj, wejdź do gry
i zbierz pierwszy grzyb – odznaka „First Mushroom” powinna wyskoczyć w rogu ekranu.
