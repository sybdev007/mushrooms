"""Obrazki odznak 512 x 512 w stylu assets/badges (ciemna obwódka, promienie w kolorze odznaki,
ikona z grubym konturem). Rysuje tylko odznaki z NEW, istniejących plików nie nadpisuje.

Uruchom z katalogu projektu: python3 tools/badge_art.py
"""

import math
import os

from PIL import Image, ImageDraw, ImageFilter

SIZE = 512
K = 4  # rysujemy w 4x większej skali i zmniejszamy (gładkie krawędzie)
S = SIZE * K
INK = (43, 29, 20, 255)  # kontur jak w starych odznakach
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "badges")


def p(x, y):
    return (x * K, y * K)


def pts(points):
    return [p(x, y) for x, y in points]


def shade(color, f):
    r, g, b = color[:3]
    if f >= 0:
        return (int(r + (255 - r) * f), int(g + (255 - g) * f), int(b + (255 - b) * f), 255)
    return (int(r * (1 + f)), int(g * (1 + f)), int(b * (1 + f)), 255)


def base(color):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = S / 2
    # Promienie
    rays = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rays)
    rd.ellipse([c - 236 * K, c - 236 * K, c + 236 * K, c + 236 * K], fill=shade(color, -0.12))
    for i in range(24):
        if i % 2:
            continue
        a0 = math.radians(i * 15 - 90)
        a1 = math.radians((i + 1) * 15 - 90)
        r = 300 * K
        rd.polygon([(c, c), (c + r * math.cos(a0), c + r * math.sin(a0)), (c + r * math.cos(a1), c + r * math.sin(a1))], fill=shade(color, 0.12))
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([c - 150 * K, c - 150 * K, c + 150 * K, c + 150 * K], fill=shade(color, 0.35)[:3] + (150,))
    glow = glow.filter(ImageFilter.GaussianBlur(60 * K))
    rays = Image.alpha_composite(rays, glow)
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).ellipse([c - 236 * K, c - 236 * K, c + 236 * K, c + 236 * K], fill=255)
    img.paste(rays, (0, 0), mask)
    # Obwódki: ciemna gruba, cienka jasna w środku
    d.ellipse([c - 250 * K, c - 250 * K, c + 250 * K, c + 250 * K], outline=INK, width=22 * K)
    d.ellipse([c - 230 * K, c - 230 * K, c + 230 * K, c + 230 * K], outline=(255, 248, 232, 230), width=3 * K)
    return img


def outlined(img, draw_fn, width=9):
    """Kształt z konturem: najpierw kontur (pogrubiony kształt w kolorze INK), potem wypełnienie."""
    shape = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(shape))
    alpha = shape.split()[3]
    # Pogrubienie konturu: rozmycie i próg (szybciej niż MaxFilter na dużym obrazku)
    grown = alpha.filter(ImageFilter.GaussianBlur(width * K * 0.55)).point(lambda v: 255 if v > 6 else 0)
    ink = Image.new("RGBA", (S, S), INK)
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow.paste(Image.new("RGBA", (S, S), (0, 0, 0, 90)), (0, 0), grown)
    shadow = shadow.filter(ImageFilter.GaussianBlur(8 * K))
    img.alpha_composite(shadow, (0, 6 * K))
    img.paste(ink, (0, 0), grown)
    img.alpha_composite(shape)


def star(d, x, y, r, color):
    points = []
    for i in range(8):
        a = math.radians(i * 45 - 90)
        rr = r if i % 2 == 0 else r * 0.3
        points.append((x + rr * math.cos(a), y + rr * math.sin(a)))
    d.polygon(pts(points), fill=color)


def flame(d, x, y, s):
    d.polygon(pts([(x, y - 34 * s), (x + 16 * s, y - 6 * s), (x + 14 * s, y + 10 * s), (x, y + 16 * s), (x - 14 * s, y + 10 * s), (x - 16 * s, y - 6 * s)]), fill=(240, 120, 40, 255))
    d.polygon(pts([(x, y - 16 * s), (x + 8 * s, y + 2 * s), (x, y + 12 * s), (x - 8 * s, y + 2 * s)]), fill=(255, 220, 120, 255))


def mountain():
    img = base((108, 74, 160))

    def hill(d):
        d.polygon(pts([(96, 372), (190, 214), (232, 238), (282, 160), (416, 372)]), fill=(128, 116, 160, 255))
        d.polygon(pts([(282, 160), (318, 226), (296, 218), (276, 240), (256, 206)]), fill=(214, 206, 232, 255))
        d.rectangle([p(96, 352)[0], p(96, 352)[1], p(416, 372)[0], p(416, 372)[1]], fill=(98, 88, 128, 255))

    outlined(img, hill)

    def moon(d):
        d.ellipse([p(318, 92)[0], p(318, 92)[1], p(398, 172)[0], p(398, 172)[1]], fill=(250, 232, 160, 255))

    outlined(img, moon)
    d = ImageDraw.Draw(img)
    c = shade((108, 74, 160), -0.12)
    d.ellipse([p(300, 80)[0], p(300, 80)[1], p(376, 156)[0], p(376, 156)[1]], fill=c)
    outlined(img, lambda dd: flame(dd, 282, 150, 1.1), 7)
    star(d, 150, 140, 18, (255, 244, 210, 255))
    star(d, 196, 104, 10, (255, 244, 210, 255))
    return img


def jaga():
    img = base((70, 112, 72))

    def hat(d):
        d.ellipse([p(112, 318)[0], p(112, 318)[1], p(400, 386)[0], p(400, 386)[1]], fill=(70, 50, 92, 255))
        d.polygon(pts([(170, 352), (232, 190), (250, 130), (300, 96), (346, 110), (300, 128), (286, 196), (342, 352)]), fill=(84, 60, 110, 255))

    outlined(img, hat)
    d = ImageDraw.Draw(img)
    d.polygon(pts([(184, 316), (330, 316), (338, 344), (176, 344)]), fill=(224, 122, 46, 255))
    d.rectangle([p(242, 314)[0], p(242, 314)[1], p(272, 346)[0], p(272, 346)[1]], outline=(255, 214, 90, 255), width=6 * K)
    d.polygon(pts([(258, 140), (280, 130), (276, 196), (254, 200)]), fill=(104, 78, 132, 255))
    star(d, 150, 190, 16, (255, 244, 210, 255))
    star(d, 372, 214, 12, (255, 244, 210, 255))
    return img


def cosmic():
    img = base((46, 42, 122))

    def mushroom(d):
        d.rounded_rectangle([p(222, 250)[0], p(222, 250)[1], p(290, 380)[0], p(290, 380)[1]], radius=24 * K, fill=(236, 226, 206, 255))
        d.pieslice([p(126, 120)[0], p(126, 120)[1], p(386, 380)[0], p(386, 380)[1]], 180, 360, fill=(86, 60, 196, 255))
        d.rectangle([p(126, 244)[0], p(126, 244)[1], p(386, 262)[0], p(386, 262)[1]], fill=(70, 50, 170, 255))

    outlined(img, mushroom)
    d = ImageDraw.Draw(img)
    for x, y, r in [(196, 196, 10), (256, 160, 14), (316, 204, 9), (232, 226, 6), (290, 236, 6), (176, 230, 5)]:
        star(d, x, y, r, (230, 236, 255, 255))
    for x, y, r in [(110, 130, 16), (402, 150, 12), (390, 330, 18), (120, 336, 10)]:
        star(d, x, y, r, (255, 240, 200, 255))
    return img


def mortar(img, color, bowl=(150, 140, 128)):
    def shape(d):
        d.rounded_rectangle([p(320, 120)[0], p(320, 120)[1], p(352, 300)[0], p(352, 300)[1]], radius=14 * K, fill=(176, 128, 82, 255))
        d.chord([p(132, 210)[0], p(132, 210)[1], p(380, 410)[0], p(380, 410)[1]], 0, 180, fill=bowl + (255,))
        d.rectangle([p(122, 300)[0], p(122, 300)[1], p(390, 318)[0], p(390, 318)[1]], fill=shade(bowl, -0.15))
        d.rectangle([p(206, 396)[0], p(206, 396)[1], p(306, 412)[0], p(306, 412)[1]], fill=shade(bowl, -0.2))

    outlined(img, shape)
    d = ImageDraw.Draw(img)
    d.arc([p(150, 250)[0], p(150, 250)[1], p(362, 390)[0], p(362, 390)[1]], 20, 160, fill=shade(bowl, 0.25), width=6 * K)


def forge_first():
    img = base((74, 122, 92))
    mortar(img, (74, 122, 92))
    d = ImageDraw.Draw(img)

    def leaf(dd):
        dd.ellipse([p(176, 226)[0], p(176, 226)[1], p(236, 296)[0], p(236, 296)[1]], fill=(120, 200, 100, 255))

    outlined(img, leaf, 6)
    star(d, 140, 160, 18, (255, 244, 210, 255))
    star(d, 252, 196, 11, (255, 244, 210, 255))
    return img


def forge_collection():
    img = base((176, 120, 42))
    mortar(img, (176, 120, 42), (160, 150, 136))
    d = ImageDraw.Draw(img)
    for x, y, cap in [(166, 214, (255, 70, 110)), (236, 186, (236, 240, 255)), (110, 260, (255, 205, 50))]:
        def small(dd, x=x, y=y, cap=cap):
            dd.rounded_rectangle([p(x - 10, y)[0], p(x - 10, y)[1], p(x + 10, y + 34)[0], p(x + 10, y + 34)[1]], radius=8 * K, fill=(236, 226, 206, 255))
            dd.pieslice([p(x - 32, y - 28)[0], p(x - 32, y - 28)[1], p(x + 32, y + 30)[0], p(x + 32, y + 30)[1]], 180, 360, fill=cap + (255,))

        outlined(img, small, 6)
    d = ImageDraw.Draw(img)
    star(d, 400, 120, 20, (255, 244, 210, 255))
    star(d, 300, 112, 12, (255, 244, 210, 255))
    return img


def snowflake(d, x, y, r, color, width):
    for i in range(6):
        a = math.radians(i * 60 - 90)
        ex, ey = x + r * math.cos(a), y + r * math.sin(a)
        d.line([p(x, y), p(ex, ey)], fill=color, width=width * K)
        for t, b in ((0.55, 0.32), (0.8, 0.22)):
            bx, by = x + r * t * math.cos(a), y + r * t * math.sin(a)
            for side in (-1, 1):
                ba = a + side * math.radians(40)
                d.line([p(bx, by), p(bx + r * b * math.cos(ba), by + r * b * math.sin(ba))], fill=color, width=max(2, width - 4) * K)
    d.ellipse([p(x - width, y - width)[0], p(x - width, y - width)[1], p(x + width, y + width)[0], p(x + width, y + width)[1]], fill=color)


def winter2026():
    img = base((58, 112, 176))
    outlined(img, lambda d: snowflake(d, 256, 250, 150, (236, 246, 255, 255), 22), 8)
    d = ImageDraw.Draw(img)
    snowflake(d, 256, 250, 150, (188, 222, 250, 255), 8)
    for x, y, r in [(120, 140, 16), (396, 132, 12), (402, 360, 18), (116, 368, 10)]:
        star(d, x, y, r, (255, 248, 220, 255))
    return img


NEW = {
    "winter2026": winter2026,
    "mountain": mountain,
    "jaga": jaga,
    "cosmic": cosmic,
    "forge_first": forge_first,
    "forge_collection": forge_collection,
}

if __name__ == "__main__":
    for name, draw in NEW.items():
        path = os.path.join(OUT, name + ".png")
        if os.path.exists(path):
            print("jest już:", path)
            continue
        draw().resize((SIZE, SIZE), Image.LANCZOS).save(path)
        print("zapisano:", path)
