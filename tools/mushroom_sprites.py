"""Generuje arkusz pikselowych grzybków do interfejsu (assets/mushroom-sprites.png).

Każdy kształt ma dwie warstwy 32x32 (w arkuszu powiększone 2x, pole 64 px):
  - "cap": biała sylwetka kapelusza, w grze barwiona ImageColor3 na kolor gatunku albo mutacji,
  - "over": wszystko, co ma własny kolor: obrys, trzon z buzią, blaszki, kropki, cienie i blaski
    (półprzezroczyste, więc działają na każdym kolorze kapelusza).
Na końcu arkusza są efekty: miękka poświata, promienie, iskra i pierścień.

Uruchom: python3 tools/mushroom_sprites.py  (zapisuje PNG i podgląd w kolorach do assets/)
"""

import math
from PIL import Image, ImageDraw, ImageFilter

N = 32
SCALE = 2
CELL = N * SCALE
OUT = (43, 27, 18, 255)
STEM = (248, 236, 214, 255)
STEM_SHADE = (222, 200, 172, 255)
GILL = (232, 210, 180, 255)
GILL_SHADE = (204, 178, 146, 255)
DOT = (255, 253, 246, 255)
EYE = (43, 27, 18, 255)
BLUSH = (255, 150, 160, 255)
SHADE = (0, 0, 0, 70)
DEEP = (0, 0, 0, 110)
SHINE = (255, 255, 255, 150)
SOFT = (255, 255, 255, 80)


def ellipse(cx, cy, rx, ry, cond=None):
    pts = set()
    for y in range(N):
        for x in range(N):
            if ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1:
                if cond is None or cond(x, y):
                    pts.add((x, y))
    return pts


def rect(x1, y1, x2, y2):
    return {(x, y) for x in range(x1, x2 + 1) for y in range(y1, y2 + 1)}


def poly(points):
    img = Image.new("L", (N, N), 0)
    ImageDraw.Draw(img).polygon(points, fill=255)
    return {(x, y) for y in range(N) for x in range(N) if img.getpixel((x, y)) > 0}


def dome(cx, top, rx, h, rim=2.2):
    """Kapelusz: górna połowa elipsy i lekko zaokrąglony spód."""
    base = top + h
    upper = ellipse(cx, base, rx, h, lambda x, y: y < base)
    lower = ellipse(cx, base, rx, rim, lambda x, y: y >= base)
    return upper | lower, base


class Shape:
    def __init__(self):
        self.cap = set()
        self.stem = set()
        self.gills = set()
        self.dots = []
        self.over = {}  # (x, y) -> rgba rysowane na końcu (np. pierścień, łuski)
        self.faces = []  # (x, y) środek buzi
        self.stem_tinted = False  # kurka: trzon w kolorze kapelusza


def amanita():
    s = Shape()
    s.cap, base = dome(16, 3, 14, 11)
    s.gills = ellipse(16, base + 1.2, 10, 2.2) - s.cap
    s.stem = (rect(11, base, 20, 26) | ellipse(15.9, 26.5, 6, 3)) - s.cap
    s.dots = [(9, 9), (15, 6), (21, 8), (24, 12), (6, 13), (13, 11), (19, 12)]
    s.faces = [(16, 20)]
    return s


def bolete():
    s = Shape()
    s.cap, base = dome(16, 4, 15, 10, rim=2.6)
    s.gills = ellipse(16, base + 1.5, 11, 2.4) - s.cap
    s.stem = ellipse(16, 23, 7, 8.5, lambda x, y: y >= base) - s.cap
    for x, y in [(13, 20), (18, 19), (15, 25), (19, 24), (12, 26)]:
        s.over[(x, y)] = STEM_SHADE
    s.faces = [(16, 22)]
    return s


def chanterelle():
    s = Shape()
    s.cap = poly([(3, 9), (8, 7), (13, 9), (18, 7), (23, 9), (28, 8), (27, 12), (20, 18), (19, 28), (13, 28), (12, 18), (5, 12)])
    s.stem_tinted = True
    # Blaszki-żeberka na lejku
    for i, x in enumerate([9, 13, 17, 21]):
        for y in range(12, 17):
            px = x + (y - 12) * (1 if x < 16 else -1) // 2
            s.over[(px, y)] = SHADE
    for x in range(6, 27):
        if (x, 9) in s.cap:
            s.over[(x, 9)] = SOFT
    s.faces = [(16, 22)]
    return s


def cluster():
    s = Shape()
    a, ba = dome(9, 9, 7, 6)
    b, bb = dome(22, 5, 8, 7)
    c, bc = dome(15, 15, 6, 5)
    s.cap = a | b | c
    stems = set()
    for (cx, by, w) in [(9, ba, 2), (22, bb, 2), (15, bc, 3)]:
        for y in range(by, 30):
            t = (y - by) / max(1, 29 - by)
            x = round(cx + (16 - cx) * t)
            for dx in range(-w + 1, w + 1):
                stems.add((x + dx - 1, y))
    s.stem = stems - s.cap
    s.dots = [(7, 11), (20, 8), (24, 10), (14, 17)]
    s.faces = [(16, 24, "small")]
    return s


def parasol():
    s = Shape()
    s.cap = ellipse(16, 10, 15, 5.5, lambda x, y: y < 12) | ellipse(16, 11.5, 15, 1.6) | ellipse(16, 5, 3, 3)
    s.gills = ellipse(16, 13.2, 11, 1.6) - s.cap
    s.stem = (rect(14, 12, 18, 27) | ellipse(16, 28, 4.5, 2.5)) - s.cap
    for x in range(12, 21):
        s.over[(x, 17)] = GILL
        s.over[(x, 18)] = GILL_SHADE
    for x, y in [(7, 9), (11, 7), (20, 7), (25, 9), (9, 11), (15, 9), (22, 10), (4, 11), (27, 11)]:
        s.over[(x, y)] = DEEP
    s.faces = [(16, 21, "small")]
    return s


def oyster():
    s = Shape()
    top = ellipse(14, 13, 13, 8, lambda x, y: y <= 15) | ellipse(14, 15, 13, 2.5)
    low = ellipse(19, 21, 10, 5, lambda x, y: y <= 22) | ellipse(19, 22.5, 10, 2)
    s.cap = top | low
    s.stem = (rect(4, 17, 8, 28) | rect(3, 26, 11, 29)) - s.cap
    for i in range(4):
        for t in range(6):
            x, y = 8 + i * 5 + t // 2, 16 - t // 3
            if (x, y) in top:
                s.over[(x, y)] = SHADE
    s.faces = [(14, 10)]
    return s


def crystal():
    s = Shape()
    mid = poly([(16, 1), (22, 8), (21, 19), (11, 19), (10, 8)])
    left = poly([(4, 8), (10, 11), (11, 19), (6, 19), (3, 13)])
    right = poly([(28, 6), (29, 13), (26, 19), (21, 19), (22, 10)])
    s.cap = mid | left | right
    s.stem = (rect(11, 19, 20, 28) | ellipse(16, 28, 7, 2.5)) - s.cap
    for (x, y) in mid:
        if x >= 16:
            s.over[(x, y)] = SHADE
    for (x, y) in left | right:
        if y > 14:
            s.over[(x, y)] = SHADE
    for y in range(4, 16):
        s.over[(13, y)] = SHINE
    s.faces = [(16, 23)]
    return s


def bell():
    s = Shape()
    upper = ellipse(16, 13, 9, 10, lambda x, y: y < 15)
    flare = poly([(7, 13), (25, 13), (28, 19), (4, 19)])
    s.cap = upper | flare
    s.gills = ellipse(16, 19.5, 9, 1.6) - s.cap
    # Świecący środek dzwonka
    for (x, y) in ellipse(16, 12, 4, 5):
        s.over[(x, y)] = (255, 255, 230, 160)
    stem = set()
    for y in range(20, 30):
        x = 16 + round(math.sin((y - 20) / 3) * 1.5)
        stem |= {(x - 1, y), (x, y), (x + 1, y)}
    s.stem = stem - s.cap
    s.faces = [(16, 15, "small")]
    return s


def puffball():
    s = Shape()
    s.cap = ellipse(16, 17, 12, 11)
    s.stem = (rect(12, 25, 19, 29) | ellipse(16, 29, 6, 1.5)) - s.cap
    for x, y in [(10, 12), (21, 10), (19, 15), (8, 19), (24, 19), (14, 9)]:
        s.over[(x, y)] = SHADE
    s.faces = [(16, 20)]
    return s


def crown():
    s = Shape()
    cap, base = dome(16, 9, 13, 8)
    prongs = poly([(6, 12), (5, 3), (9, 7), (11, 10)]) | poly([(13, 9), (16, 1), (19, 9)]) | poly([(21, 10), (23, 7), (27, 3), (26, 12)])
    s.cap = cap | prongs
    s.gills = ellipse(16, base + 1.2, 9, 2) - s.cap
    s.stem = (rect(12, base, 19, 28) | ellipse(16, 28, 5.5, 2.5)) - s.cap
    s.dots = [(16, 4), (6, 6), (26, 6)]
    s.faces = [(16, 23)]
    return s


SHAPES = [
    ("amanita", amanita),
    ("bolete", bolete),
    ("chanterelle", chanterelle),
    ("cluster", cluster),
    ("parasol", parasol),
    ("oyster", oyster),
    ("crystal", crystal),
    ("bell", bell),
    ("puffball", puffball),
    ("crown", crown),
]


def neighbours(p):
    x, y = p
    return [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]


def render(shape: Shape):
    cap = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    over = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    cp, op = cap.load(), over.load()
    body = shape.cap | shape.stem | shape.gills

    def blend(x, y, c):
        if not (0 <= x < N and 0 <= y < N):
            return
        r, g, b, a = op[x, y]
        if c[3] == 255 or a == 0:
            op[x, y] = c if a == 0 or c[3] == 255 else c
            if c[3] < 255 and a == 0:
                op[x, y] = c
            return
        # półprzezroczyste na nieprzezroczystym: mieszamy
        t = c[3] / 255
        op[x, y] = (round(r * (1 - t) + c[0] * t), round(g * (1 - t) + c[1] * t), round(b * (1 - t) + c[2] * t), a)

    # Kapelusz: biała sylwetka (barwiona w grze); kurka ma trzon w tym samym kolorze
    for (x, y) in shape.cap:
        cp[x, y] = (255, 255, 255, 255)
    if shape.stem_tinted:
        for (x, y) in shape.stem:
            cp[x, y] = (255, 255, 255, 255)

    # Trzon i blaszki mają własne kolory
    if not shape.stem_tinted:
        xs = [x for x, _ in shape.stem] or [0]
        right = max(xs)
        for (x, y) in shape.stem:
            op[x, y] = STEM_SHADE if x >= right - 1 else STEM
        for (x, y) in shape.stem:
            if (x - 1, y) not in shape.stem:
                op[x, y] = (255, 250, 240, 255)
    for (x, y) in shape.gills:
        op[x, y] = GILL_SHADE if (x, y + 1) not in shape.gills else GILL

    # Cienie i blaski kapelusza: dolny brzeg i prawa strona ciemniej, lewy górny łuk jaśniej
    for (x, y) in shape.cap:
        below = (x, y + 1) not in shape.cap
        below2 = (x, y + 2) not in shape.cap
        rightEdge = (x + 1, y) not in shape.cap or (x + 2, y) not in shape.cap
        if below:
            blend(x, y, DEEP)
        elif below2:
            blend(x, y, SHADE)
        elif rightEdge:
            blend(x, y, SHADE)
        top = (x, y - 1) not in shape.cap
        leftEdge = (x - 1, y) not in shape.cap
        if (top or leftEdge) and not below and x < 16:
            nx = (x, y + 1)
            if nx in shape.cap:
                blend(nx[0], nx[1], SHINE)
    for (x, y) in shape.dots:
        for p in [(x, y), (x + 1, y), (x, y + 1), (x + 1, y + 1)]:
            if p in shape.cap:
                op[p] = DOT
        if (x + 1, y + 2) in shape.cap:
            blend(x + 1, y + 2, SHADE)
    for p, c in shape.over.items():
        if p in body or c[3] == 255:
            blend(p[0], p[1], c)

    # Buzia: oczka 2x2 z białym błyskiem (na wąskich trzonach 1x2), uśmiech i rumieńce
    for face in shape.faces:
        fx, fy = face[0], face[1]
        small = len(face) > 2 and face[2] == "small"
        if small:
            for ex in (fx - 2, fx + 1):
                op[ex, fy] = EYE
                op[ex, fy + 1] = EYE
            op[fx - 1, fy + 2] = EYE
            op[fx, fy + 2] = EYE
            continue
        for ex in (fx - 3, fx + 1):
            for dx in (0, 1):
                for dy in (0, 1, 2):
                    op[ex + dx, fy + dy] = EYE
            op[ex, fy] = (255, 255, 255, 255)
        op[fx - 1, fy + 3] = EYE
        op[fx, fy + 3] = EYE
        for bx in (fx - 5, fx + 3):
            for dx in (0, 1):
                if (bx + dx, fy + 2) in body:
                    op[bx + dx, fy + 2] = BLUSH

    # Obrys: piksele tuż obok bryły, a także granica kapelusza nad trzonem i blaszkami
    for y in range(N):
        for x in range(N):
            p = (x, y)
            if p in body:
                continue
            if any(q in body for q in neighbours(p)):
                op[x, y] = OUT
    for (x, y) in shape.cap:
        if ((x, y + 1) in shape.stem or (x, y + 1) in shape.gills) and not shape.stem_tinted:
            op[x, y] = OUT
    for (x, y) in shape.stem:
        if (x, y - 1) in shape.gills:
            op[x, y] = (op[x, y][0] - 20, op[x, y][1] - 20, op[x, y][2] - 20, 255)
    return cap, over


def big(img):
    return img.resize((img.width * SCALE, img.height * SCALE), Image.NEAREST)


def fx_cells():
    cells = []
    # Miękka poświata
    g = Image.new("RGBA", (CELL, CELL), (255, 255, 255, 0))
    p = g.load()
    for y in range(CELL):
        for x in range(CELL):
            d = math.hypot(x + 0.5 - CELL / 2, y + 0.5 - CELL / 2) / (CELL / 2)
            a = max(0.0, 1 - d) ** 1.8
            p[x, y] = (255, 255, 255, round(255 * a))
    cells.append(("glow", g))
    # Promienie (12 klinów, miękkie)
    r = Image.new("L", (CELL * 4, CELL * 4), 0)
    d = ImageDraw.Draw(r)
    c = CELL * 2
    for i in range(12):
        a = i * math.pi / 6
        w = math.pi / 22
        d.polygon([(c, c), (c + math.cos(a - w) * c, c + math.sin(a - w) * c), (c + math.cos(a + w) * c, c + math.sin(a + w) * c)], fill=255)
    r = r.filter(ImageFilter.GaussianBlur(6)).resize((CELL, CELL), Image.LANCZOS)
    rays = Image.new("RGBA", (CELL, CELL), (255, 255, 255, 0))
    rp, lp = rays.load(), r.load()
    for y in range(CELL):
        for x in range(CELL):
            dd = math.hypot(x + 0.5 - CELL / 2, y + 0.5 - CELL / 2) / (CELL / 2)
            fade = max(0.0, 1 - dd) ** 0.8
            rp[x, y] = (255, 255, 255, round(lp[x, y] * fade))
    cells.append(("rays", rays))
    # Iskra (pikselowa gwiazdka 4-ramienna)
    s = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    sp = s.load()
    for i in range(16):
        for j in range(16):
            dx, dy = abs(i - 7.5), abs(j - 7.5)
            if (dx < 1 and dy < 7.5) or (dy < 1 and dx < 7.5) or (dx < 2 and dy < 2.5) or (dy < 2 and dx < 2.5):
                sp[i, j] = (255, 255, 255, 255)
    cells.append(("spark", s.resize((CELL, CELL), Image.NEAREST)))
    # Pierścień
    ring = Image.new("RGBA", (CELL, CELL), (255, 255, 255, 0))
    rp = ring.load()
    for y in range(CELL):
        for x in range(CELL):
            dd = math.hypot(x + 0.5 - CELL / 2, y + 0.5 - CELL / 2) / (CELL / 2)
            a = max(0.0, 1 - abs(dd - 0.82) / 0.12)
            rp[x, y] = (255, 255, 255, round(255 * a ** 1.5))
    cells.append(("ring", ring))
    return cells


def main():
    import os
    cols = 8
    cells = []
    for name, fn in SHAPES:
        cap, over = render(fn())
        cells.append((name + "_cap", big(cap)))
        cells.append((name + "_over", big(over)))
    cells += fx_cells()
    rows = math.ceil(len(cells) / cols)
    sheet = Image.new("RGBA", (cols * CELL, rows * CELL), (0, 0, 0, 0))
    for i, (_, img) in enumerate(cells):
        sheet.paste(img, ((i % cols) * CELL, (i // cols) * CELL))
    root = os.path.join(os.path.dirname(__file__), "..", "assets")
    sheet.save(os.path.join(root, "mushroom-sprites.png"))
    print("cells:", ", ".join(f"{i}={n}" for i, (n, _) in enumerate(cells)))

    # Podgląd w kolorach (nie trafia do gry)
    colors = [(230, 40, 40), (140, 90, 50), (240, 170, 40), (196, 150, 80), (215, 195, 160), (196, 200, 214), (170, 100, 255), (255, 200, 90), (240, 236, 255), (120, 255, 190)]
    prev = Image.new("RGBA", (len(SHAPES) * CELL * 2, CELL * 2), (250, 244, 230, 255))
    for i, (name, fn) in enumerate(SHAPES):
        cap, over = render(fn())
        tinted = Image.new("RGBA", cap.size)
        cp, tp = cap.load(), tinted.load()
        for y in range(N):
            for x in range(N):
                r, g, b, a = cp[x, y]
                c = colors[i]
                tp[x, y] = (r * c[0] // 255, g * c[1] // 255, b * c[2] // 255, a)
        comp = Image.alpha_composite(tinted, over)
        prev.alpha_composite(comp.resize((CELL * 2, CELL * 2), Image.NEAREST), (i * CELL * 2, 0))
    prev.save(os.path.join(os.path.dirname(__file__), "..", "assets", "mushroom-sprites-preview.png"))


if __name__ == "__main__":
    main()
