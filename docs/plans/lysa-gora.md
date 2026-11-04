# Łysa Góra — czwarty świat z Babą Jagą (plan, 4.11)

Decyzje Toma (4.11): Łysa Góra + Baba Jaga; cechy mutacji tylko na nowej mapie + jeden nowy wariant
ponad tęczowym na wszystkich mapach; nowe kształty tylko dla grzybów nowej mapy; najpierw plan, potem budowa.
Gałąź: `lysa-gora` (od `ekspedycja-bramki`, bo limity ulepszeń zależą od świata — bramki Codexa).

## Po co ten świat
Po wymaksowaniu bagien gracz zarabia ok. 170 tys./min (symulator, 5 h 53 min) i nie ma celu ani zlewu.
Łysa Góra daje: nowy cel do odblokowania, 10 nowych grzybów w nowych kształtach, 3 cechy, nowego bossa,
nowe poziomy ulepszeń (zlew monet) i rzadki wariant, na który poluje się na wszystkich mapach.

## Mapa (z 3000–3480, za Stawem Utopca)
| Strefa | z | Mrok / olej | Co tam jest |
|---|---|---|---|
| Polana Zielarki (obóz) | 3000–3040 | 0,5 / 0 | bezpieczna: skup, olej, ulepszenia świata, portal powrotny, chatka zielarki, ognisko |
| Wiedźmi Las | 3040–3170 | 0,75 / 7 | krzywe czarne drzewa, kości i amulety na gałęziach, kruki, czarne koty |
| Kotły Sabatu | 3170–3300 | 0,9 / 10 | polana z kotłami (trujące opary), ogniska sabatu, miotły w ziemi |
| Szczyt Łysej Góry | 3300–3480 | 1,0 / 13 | krąg kamieni, chatka na kurzej stopce, ogródek Baby Jagi z jej grzybami |

Wejście: portal za Stawem Utopca + skrót na Placu Portali (jak bagna). Próg: **ok. 5 mln monet** (do ustalenia
symulatorem; dla porównania bagna 1 mln). Raz otwarte zostaje otwarte (`mountainUnlocked` w zapisie).
Klimat: fiolet i trująca zieleń, księżyc w pełni, iskry z ognisk. Muzyka: „Night on Bald Mountain” (już w bibliotece).

## Grzyby (10 nowych; ok. 5× bagna, jak bagna ok. 5× jaskinia)
| Strefa | Grzyb (PL / EN) | Kształt | Wartość | Waga |
|---|---|---|---|---|
| Wiedźmi Las | Kołpak Wiedźmy / Witch's Hat | **stożek** (spiczasty kapelusz) | 10 000 | 50 |
| | Czarci Smardz / Devil's Morel | **smardz** (plaster miodu) | 14 000 | 35 |
| | Huba Kruków / Raven's Bracket | **huba** (półki na pieńku) | 20 000 | 15 |
| Kotły Sabatu | Purchawka Sabatu / Sabbath Puffball | kula, **pyli zarodnikami** przy zerwaniu | 24 000 | 45 |
| | Czarcie Palce / Devil's Fingers | **macki** (czerwone ramiona z jaja) | 34 000 | 35 |
| | Wiedźmia Kępka / Hex Cluster | kępka, trująco zielona | 48 000 | 20 |
| Szczyt | Gwiazdosz / Earthstar | **gwiazda** (kula na rozłożonych płatkach) | 40 000 | 50 |
| | Księżycowy Kołpak / Moon Hat | stożek, srebrny | 55 000 | 35 |
| | Oko Nocy / Night's Eye | kula z okiem, które śledzi gracza | 80 000 | 15 |
| Ogródek Jagi | Ziele Baby Jagi / Baba Jaga's Toadstool | duży stożek z runami | 180 000 | strażnik |

Nowe kształty (5): stożek, smardz, huba, macki, gwiazda — w tym samym stylu klocków co obecne grzyby
(`MushroomView`, nowe `FORMS`). Karty w UI na start dostają najbliższe istniejące obrazki (`MushroomArt`);
własne obrazki później (trzeba wgrać arkusz na konto Toma).

## Mutacje
- **Cechy Łysej Góry** (tylko tam, jak mech/blask/kryształ/otchłań):
  Przeklęty 💀 (Wiedźmi Las, x2, fioletowy dym) · Zaklęty 🔮 (Kotły, x2,5, krążące runy) ·
  Księżycowy 🌙 (Szczyt, x3, srebrna aureola).
- **Nowy wariant ponad tęczowym: Kosmiczny 🌌** — wszystkie mapy, szansa ok. 1/1250 (tęczowy 1/250), x20,
  ciemnogranatowy kapelusz w gwiazdach, mgławica wokół. Średnio podnosi dochód o ok. 1,5% — to cel do
  polowania, nie zmiana ekonomii. Mikstura szczęścia działa na niego jak na inne warianty (płatny produkt
  zostaje jedynym boostem; nic darmowego w zamian). Okno Szans pokazuje nową szansę.

## Baba Jaga (boss)
- Lata w moździerzu z tłuczkiem, miotłą zamiata za sobą ślady. Model z klocków ze szkieletem jak Leszy.
- **Chatka na kurzej stopce** na szczycie powoli się obraca. Ogródek z Zielem jest za chatką.
  Zerwiesz, gdy chatka **patrzy na ciebie** → Jaga wylatuje od razu; gdy jest odwrócona → 2,5 s przewagi.
  Gracz uczy się czekać na dobry moment (jak „czerwone-zielone światło”).
- Pościg: szybsza od Utopca (ok. 35 studs/s) → ucieczka od **butów 13** (nowe poziomy góry); dalej jak
  u innych strażników (ten sam `ChaseService`/`HoardService`, wpis w `GUARDIANS`, `Progress.GUARDIANS`,
  zakładka Strażnicy w Grzybopedii).

## Zagrożenia mapy
- **Kruki Baby Jagi** (Wiedźmi Las i Kotły): co jakiś czas kruk wybiera gracza, nad nim pojawia się cień
  (1,5 s ostrzeżenia), potem nurkuje. Trafiony gubi **jeden najtańszy grzyb**, który kruk upuszcza kilka metrów
  dalej (można go podnieść). Uczy ruchu, nie zabiera dużo. Wzór: kamienie z ekspedycji.
- **Trujące opary z kotłów** (Kotły): zielone chmury przy kotłach, w środku olej pali się 2× szybciej.
  Ogniska sabatu są bezpieczne od kruków, ale **nie dolewają oleju** (żeby nie robić darmowego zamiennika
  płatnej butelki oleju).

## Ulepszenia (zlew monet)
- Nowe limity świata: olej 17, koszyk 18, buty 16 (`worldCaps.mountain`).
  Dzisiejsze krzywe dają za te poziomy łącznie ok. 490 mln (buty 16 = 178 mln) — za stromo.
  Propozycja: łagodniejszy wzrost dla poziomów góry, cel ok. 4–6 h na komplet; liczby z symulatora.
- Dwa ulepszenia na Polanie Zielarki (jak knot z sitowia i wiklinowy kosz na bagnach):
  **Ziołowy knot** (mniej oleju na Łysej Górze) i **Torba Wiedźmy** (+miejsca w koszyku).

## Reszta
- Grzybopedia: strona „Łysa Góra” (premia do ceny jak inne strony) + Baba Jaga w zakładce Strażnicy.
- Tytuły: Badacz Łysej Góry (strona), Uciekinier Baby Jagi (ucieczka), Kosmiczny (pierwszy grzyb kosmiczny).
- Odznaki: „Łysa Góra” i „Baba Jaga” — **Tom zakłada w Creator Hub** i wpisuje numery.
- Zadania dzienne: skala nagród góry = najdroższy zwykły grzyb × 10 (= 800 tys.).
- DEV: TP na polanę/kotły/szczyt, odblokuj górę, +10 mln, przyzwij Jagę, wymuś kosmiczny.
- Zapis: `mountainUnlocked`, `DATA_VERSION` 7; stare zapisy bez zmian.

## Kolejność budowy
1. **Dane i ekonomia:** Config (strefy, grzyby, cechy, wariant, limity, brama świata), Economy/Progress
   dla 4 światów, zapis, symulator → próg wejścia i ceny; testy Lune.
2. **Mapa:** `World/Mountain.luau` (4 strefy, obóz, portal, chatka), MapBuilder, tło, mgła, muzyka.
3. **Grzyby:** 5 nowych kształtów, cechy i wariant kosmiczny (aury), obrazki zastępcze w UI.
4. **Baba Jaga:** model, pościg, obracająca się chatka, kruki, opary.
5. **UI i treść:** Grzybopedia, Strażnicy, tytuły, DEV, teksty PL/EN.
6. **Test w Studio przez MCP** (zrzuty każdej strefy, pościg, kruki, ceny), poprawki, oddanie.

## Ryzyka
- Wydajność: czwarty świat to kolejne ~2–3 tys. części; StreamingEnabled już jest, ale trzeba sprawdzić
  liczbę świateł i neonu (lekcja z 4.11: mniej świateł, słabsza poświata).
- Wariant ponad tęczą dotyka wielu miejsc (MushroomView, odznaki, tytuły, Okno Szans, sprzedaż) — testy.
- Ceny nowych poziomów: bez symulatora łatwo zrobić ścianę (178 mln za buty) albo nic nie znaczący zlew.

## Stan (4.11, wieczór)
Zrobione etapy 1–5 na gałęzi `lysa-gora` (testy Lune 1030 ok, kompilacja 118 plików, typy bez nowych błędów):
- Mapa, portal przy Stawie Utopca i skrót na Placu Portali, Polana Zielarki, opary z kotłów (bulgoczą),
  chatka na kurzej stopce (obraca się, snop spojrzenia czerwony, gdy patrzy na ogródek), Baba Jaga.
- 5 nowych kształtów grzybów, Oko Nocy śledzi gracza, purchawka pyli, cechy Przeklęty/Zaklęty/Księżycowy,
  wariant Kosmiczny (gwiazdy, mgławica, snop).
- Kruki: cień → nurkowanie → najtańszy grzyb ląduje 10 studs dalej na 45 s (sprawdzone w Studio: trafienie,
  podniesienie, unik).
- Grzybopedia (zakładki na 4 światy, znaczek 🌌), tytuły Uciekinier Baby Jagi i Kosmiczny, DEV: kruk teraz,
  pościg Jagi teraz, grzyby obok kosmiczne.

Do zrobienia / dla Toma:
- Zrzuty nowych grzybów, kruka i Jagi w locie: Studio przestało rysować 3D w trakcie testu (zablokowany
  komputer?), więc kształty sprawdzone tylko kodem (budują się bez błędów, wymiary w normie).
- Odznaki „Łysa Góra”, „Baba Jaga”, „Kosmiczny”: założyć w Creator Hub i wpisać numery w `Config.Badges`.
- Arcygrzybiarz (cała księga tęczowa) wymaga teraz też strony Łysej Góry — gracze z tym tytułem go stracą,
  dopóki nie uzupełnią nowej strony (tak samo było przy bagnach).
- Okno Szans ma teraz 11 wierszy (4 warianty + 7 cech): sprawdzić na telefonie, czy się mieści.
