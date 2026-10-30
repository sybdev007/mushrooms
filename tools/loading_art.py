"""Grafiki ekranu wczytywania (assets/loading/).

    python3 tools/loading_art.py --halloween <obraz.png> --forest <obraz.png>

- tła: przeskalowane do 1024 px szerokości (więcej Roblox i tak nie przyjmie), JPG
- loading-sprites.png: arkusz 1024 x 512, komórki 256 x 256 (rząd, kolumna od zera):
    0,0 dynia   0,1 świecąca buzia dyni   0,2 grzybek-skoczek   0,3 świecące kropki grzybka
    1,0 kiełek błękitny   1,1 kiełek złoty   1,2 kiełek różowy   1,3 miękka poświata (biała, do barwienia)
  Warstwy „świecące” leżą dokładnie nad swoimi postaciami, więc w grze wystarczy nałożyć je
  na siebie i migotać przezroczystością.
- Bez argumentów rysuje tylko arkusz (tła zostają jak są).
- Cienie pod dynią i grzybkiem rysuje gra (dynia się toczy, grzybek skacze, cień zostaje na pasku).

Rysunek jest w SVG, a PNG robi Chromium z Playwrighta (przezroczyste tło).
"""

import argparse
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "loading")
CELL = 256
OUTLINE = "#2b1b12"

# ---------------------------------------------------------------- dynia

PUMPKIN_FACE = """
  <path d="M74,124 L112,124 L95,88 Z"/>
  <path d="M144,124 L182,124 L161,88 Z"/>
  <path d="M119,146 L137,146 L128,130 Z"/>
  <path d="M66,152 C86,206 170,206 190,152 L176,160 L168,151 L157,165 L145,156 L134,170
           L122,156 L111,165 L99,151 L90,161 L80,152 Z"/>
"""


def pumpkin() -> str:
    lobes = [
        (76, 146, 58, 80, "lobeOuter"),
        (180, 146, 58, 80, "lobeOuter"),
        (103, 143, 52, 86, "lobeMid"),
        (153, 143, 52, 86, "lobeMid"),
        (128, 141, 47, 89, "lobeCenter"),
    ]
    outline = "".join(
        f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{OUTLINE}" stroke="{OUTLINE}" stroke-width="14"/>'
        for x, y, rx, ry, _ in lobes
    )
    fills = "".join(
        f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="url(#{g})" stroke="{OUTLINE}" stroke-width="4"/>'
        for x, y, rx, ry, g in lobes
    )
    return f"""
    <defs>
      <radialGradient id="lobeCenter" cx="0.38" cy="0.3" r="0.8">
        <stop offset="0" stop-color="#ffc35a"/><stop offset="0.5" stop-color="#ff921f"/><stop offset="1" stop-color="#d9580b"/>
      </radialGradient>
      <radialGradient id="lobeMid" cx="0.4" cy="0.3" r="0.85">
        <stop offset="0" stop-color="#ffb247"/><stop offset="0.55" stop-color="#f7841a"/><stop offset="1" stop-color="#c94c09"/>
      </radialGradient>
      <radialGradient id="lobeOuter" cx="0.45" cy="0.3" r="0.9">
        <stop offset="0" stop-color="#f59a32"/><stop offset="0.6" stop-color="#e06d12"/><stop offset="1" stop-color="#b03f08"/>
      </radialGradient>
      <linearGradient id="stem" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stop-color="#93b84a"/><stop offset="1" stop-color="#4b6a1f"/>
      </linearGradient>
      <linearGradient id="carved" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stop-color="#3a0f03"/><stop offset="1" stop-color="#6b2407"/>
      </linearGradient>
    </defs>
    {outline}
    {fills}
    <!-- ogonek, wąs i listek -->
    <path d="M150,42 C164,30 182,34 182,48 C182,58 170,60 166,52" fill="none" stroke="{OUTLINE}" stroke-width="10" stroke-linecap="round"/>
    <path d="M150,42 C164,30 182,34 182,48 C182,58 170,60 166,52" fill="none" stroke="#7fa83a" stroke-width="5" stroke-linecap="round"/>
    <path d="M112,64 C110,46 118,30 128,16 L148,22 C140,34 136,48 140,64 Z" fill="url(#stem)" stroke="{OUTLINE}" stroke-width="6" stroke-linejoin="round"/>
    <path d="M140,54 C150,40 168,40 176,50 C164,60 150,62 140,54 Z" fill="#86c043" stroke="{OUTLINE}" stroke-width="5" stroke-linejoin="round"/>
    <!-- wyrzeźbiona buzia (ciemne wnętrze, świeci osobna warstwa) -->
    <g fill="url(#carved)" stroke="{OUTLINE}" stroke-width="4" stroke-linejoin="round">{PUMPKIN_FACE}</g>
    <!-- połysk -->
    <ellipse cx="44" cy="132" rx="8" ry="22" fill="#fff" opacity="0.32" transform="rotate(12 44 132)"/>
    <ellipse cx="80" cy="76" rx="8" ry="15" fill="#fff" opacity="0.42" transform="rotate(-32 80 76)"/>
    <ellipse cx="172" cy="78" rx="5" ry="9" fill="#fff" opacity="0.28" transform="rotate(30 172 78)"/>
    """


def pumpkin_glow() -> str:
    return f"""
    <defs>
      <radialGradient id="fire" cx="0.5" cy="0.62" r="0.75">
        <stop offset="0" stop-color="#fffbd0"/><stop offset="0.45" stop-color="#ffe066"/><stop offset="1" stop-color="#ff9a1a"/>
      </radialGradient>
      <filter id="halo" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="7"/></filter>
    </defs>
    <g fill="#ffb000" opacity="0.95" filter="url(#halo)">{PUMPKIN_FACE}</g>
    <g fill="url(#fire)">{PUMPKIN_FACE}</g>
    """


# ---------------------------------------------------------------- grzybek-skoczek

SPOTS = [(78, 80, 15), (128, 50, 13), (178, 84, 17), (104, 114, 10), (156, 118, 9), (52, 118, 8), (206, 120, 8)]


def mushroom() -> str:
    spots = "".join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="#d9d2ff" opacity="0.95"/>' for x, y, r in SPOTS)
    return f"""
    <defs>
      <linearGradient id="cap" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stop-color="#8f7dff"/><stop offset="0.55" stop-color="#b878ff"/><stop offset="1" stop-color="#ff8ad2"/>
      </linearGradient>
      <linearGradient id="stalk" x1="0" y1="0" x2="1" y2="0">
        <stop offset="0" stop-color="#fff7ea"/><stop offset="1" stop-color="#ecd2ad"/>
      </linearGradient>
    </defs>
    <!-- nóżki -->
    <ellipse cx="106" cy="233" rx="19" ry="11" fill="#f2d7b0" stroke="{OUTLINE}" stroke-width="6"/>
    <ellipse cx="150" cy="233" rx="19" ry="11" fill="#f2d7b0" stroke="{OUTLINE}" stroke-width="6"/>
    <!-- trzonek z buzią -->
    <path d="M96,126 C92,170 88,206 94,226 Q128,242 162,226 C168,206 164,170 160,126 Z" fill="url(#stalk)" stroke="{OUTLINE}" stroke-width="7" stroke-linejoin="round"/>
    <ellipse cx="111" cy="174" rx="7.5" ry="10.5" fill="{OUTLINE}"/>
    <ellipse cx="145" cy="174" rx="7.5" ry="10.5" fill="{OUTLINE}"/>
    <circle cx="113.5" cy="169.5" r="3.2" fill="#fff"/>
    <circle cx="147.5" cy="169.5" r="3.2" fill="#fff"/>
    <ellipse cx="99" cy="191" rx="9" ry="5" fill="#ff8fb1" opacity="0.75"/>
    <ellipse cx="157" cy="191" rx="9" ry="5" fill="#ff8fb1" opacity="0.75"/>
    <path d="M118,190 Q128,201 138,190" fill="none" stroke="{OUTLINE}" stroke-width="5" stroke-linecap="round"/>
    <!-- blaszki pod kapeluszem -->
    <ellipse cx="128" cy="148" rx="98" ry="14" fill="#f6e6ff" stroke="{OUTLINE}" stroke-width="5"/>
    <!-- kapelusz -->
    <path d="M22,136 C22,62 72,20 128,20 C184,20 234,62 234,136 C234,150 210,153 128,153 C46,153 22,150 22,136 Z"
          fill="url(#cap)" stroke="{OUTLINE}" stroke-width="8" stroke-linejoin="round"/>
    {spots}
    <ellipse cx="84" cy="56" rx="28" ry="12" fill="#fff" opacity="0.45" transform="rotate(-24 84 56)"/>
    """


def mushroom_glow() -> str:
    core = "".join(f'<circle cx="{x}" cy="{y}" r="{r}"/>' for x, y, r in SPOTS)
    return f"""
    <defs>
      <radialGradient id="spot" cx="0.4" cy="0.35" r="0.7">
        <stop offset="0" stop-color="#ffffff"/><stop offset="0.5" stop-color="#a8fdff"/><stop offset="1" stop-color="#3fe3ff"/>
      </radialGradient>
      <filter id="halo2" x="-60%" y="-60%" width="220%" height="220%"><feGaussianBlur stdDeviation="6"/></filter>
    </defs>
    <g fill="#38e8ff" opacity="0.9" filter="url(#halo2)">{core}</g>
    <g fill="url(#spot)">{core}</g>
    """


# ---------------------------------------------------------------- kiełki (wyświetlane małe: grube kontury)


def sprout(kind: str) -> str:
    if kind == "cyan":
        cap = '<path d="M30,150 C30,70 78,36 128,36 C178,36 226,70 226,150 C226,166 30,166 30,150 Z" fill="url(#c1)" stroke="#2b1b12" stroke-width="14" stroke-linejoin="round"/>'
        stem = '<path d="M100,150 C98,190 96,214 100,232 L156,232 C160,214 158,190 156,150 Z" fill="#f4ecdf" stroke="#2b1b12" stroke-width="14" stroke-linejoin="round"/>'
        dots = '<circle cx="90" cy="96" r="16" fill="#e8ffff"/><circle cx="150" cy="78" r="12" fill="#e8ffff"/><circle cx="176" cy="118" r="10" fill="#e8ffff"/>'
        grad = '<linearGradient id="c1" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#9ef8ff"/><stop offset="1" stop-color="#1fa8d8"/></linearGradient>'
        glow = "#46e6ff"
    elif kind == "gold":
        cap = '<path d="M58,118 C66,60 100,26 128,22 C156,26 190,60 198,118 C198,130 58,130 58,118 Z" fill="url(#c2)" stroke="#2b1b12" stroke-width="14" stroke-linejoin="round"/>'
        stem = '<path d="M112,118 C108,170 104,210 108,234 L148,234 C152,210 148,170 144,118 Z" fill="#fff3d6" stroke="#2b1b12" stroke-width="14" stroke-linejoin="round"/>'
        dots = '<ellipse cx="104" cy="70" rx="12" ry="18" fill="#fff8d0" opacity="0.8" transform="rotate(-20 104 70)"/>'
        grad = '<linearGradient id="c2" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff07a"/><stop offset="1" stop-color="#ff9f1f"/></linearGradient>'
        glow = "#ffc93a"
    else:
        cap = '<path d="M44,140 C40,80 80,34 128,34 C176,34 216,80 212,140 C190,128 176,150 160,138 C146,152 110,152 96,138 C80,150 66,128 44,140 Z" fill="url(#c3)" stroke="#2b1b12" stroke-width="14" stroke-linejoin="round"/>'
        stem = '<path d="M106,140 C102,184 100,214 104,234 L152,234 C156,214 154,184 150,140 Z" fill="#fbeaf2" stroke="#2b1b12" stroke-width="14" stroke-linejoin="round"/>'
        dots = '<ellipse cx="92" cy="82" rx="16" ry="11" fill="#ffe3f6" opacity="0.85" transform="rotate(-25 92 82)"/>'
        grad = '<linearGradient id="c3" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffc1ec"/><stop offset="1" stop-color="#d9449f"/></linearGradient>'
        glow = "#ff6fd2"
    return f"""
    <defs>{grad}<filter id="h_{kind}" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="16"/></filter></defs>
    <ellipse cx="128" cy="110" rx="104" ry="86" fill="{glow}" opacity="0.55" filter="url(#h_{kind})"/>
    {stem}{cap}{dots}
    """


def soft_glow() -> str:
    return """
    <defs><radialGradient id="soft" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#fff" stop-opacity="1"/>
      <stop offset="0.35" stop-color="#fff" stop-opacity="0.6"/>
      <stop offset="0.7" stop-color="#fff" stop-opacity="0.16"/>
      <stop offset="1" stop-color="#fff" stop-opacity="0"/>
    </radialGradient></defs>
    <circle cx="128" cy="128" r="128" fill="url(#soft)"/>
    """


SHEET = [
    [pumpkin, pumpkin_glow, mushroom, mushroom_glow],
    [lambda: sprout("cyan"), lambda: sprout("gold"), lambda: sprout("pink"), soft_glow],
]


def render_sheet(path: str):
    from playwright.sync_api import sync_playwright

    width, height = CELL * 4, CELL * 2
    groups = []
    for row, cells in enumerate(SHEET):
        for col, draw in enumerate(cells):
            groups.append(f'<svg x="{col * CELL}" y="{row * CELL}" width="{CELL}" height="{CELL}" viewBox="0 0 256 256" overflow="hidden">{draw()}</svg>')
    svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}">{"".join(groups)}</svg>'
    html = f'<html><body style="margin:0;background:transparent">{svg}</body></html>'
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": width, "height": height}, device_scale_factor=1)
        page.set_content(html)
        page.screenshot(path=path, omit_background=True, clip={"x": 0, "y": 0, "width": width, "height": height})
        browser.close()


def background(src: str, path: str):
    image = Image.open(src).convert("RGB")
    w, h = image.size
    target_w = 1024
    target_h = round(h * target_w / w)
    image = image.resize((target_w, target_h), Image.LANCZOS)
    image.save(path, "JPEG", quality=90, optimize=True, progressive=False)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--halloween")
    parser.add_argument("--forest")
    args = parser.parse_args()
    os.makedirs(OUT, exist_ok=True)
    if args.halloween:
        background(args.halloween, os.path.join(OUT, "bg-halloween.jpg"))
    if args.forest:
        background(args.forest, os.path.join(OUT, "bg-forest.jpg"))
    render_sheet(os.path.join(OUT, "loading-sprites.png"))
    print("gotowe:", sorted(os.listdir(OUT)))


if __name__ == "__main__":
    main()
