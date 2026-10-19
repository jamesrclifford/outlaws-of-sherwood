"""Generates the scenery art: battle backdrops, the strategic map and UI frames.

Like make_sprites.py, everything is drawn from code with a seeded random
generator, so re-running it gives the same pixels.

  assets/backdrops/<location>.png  180x220, shown at 2x behind the battle field
  assets/map/map.png               176x196, shown at 2x; roads and places come from data/map.json
  assets/ui/*.png                  9-slice frames for buttons and panels, unit shadows and rings,
                                   mission path medallions, the title screen
  assets/items/<item>.png          16x16 gear icons for the armory
  assets/fx/*.png                  arrows, bolts and nets that fly across the battle field

Usage: python3 tools/make_scenery.py
"""
import json
import math
import os
import random
import sys
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))   # for make_font's glyphs

ROOT = os.path.join(os.path.dirname(__file__), "..")
BW, BH = 180, 220   # battle backdrop size; the top 440px of the screen at 2x
HORIZON = 64        # backdrop row where the ground starts
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def hexc(h, a=255):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (a,)


def mix(a, b, t):
    a, b = hexc(a) if isinstance(a, str) else a, hexc(b) if isinstance(b, str) else b
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(4))


class Canvas:
    def __init__(self, w, h, fill=(0, 0, 0, 0)):
        self.w, self.h = w, h
        self.img = Image.new("RGBA", (w, h), hexc(fill) if isinstance(fill, str) else fill)
        self.d = self.img.load()

    def px(self, x, y, c):
        x, y = int(x), int(y)
        if 0 <= x < self.w and 0 <= y < self.h:
            c = hexc(c) if isinstance(c, str) else c
            if c[3] == 255:
                self.d[x, y] = c
            else:
                self.d[x, y] = mix(self.d[x, y], (c[0], c[1], c[2], 255), c[3] / 255)

    def get(self, x, y):
        return self.d[int(x), int(y)] if 0 <= x < self.w and 0 <= y < self.h else None

    def rect(self, x0, y0, x1, y1, c):
        for y in range(int(y0), int(y1) + 1):
            for x in range(int(x0), int(x1) + 1):
                self.px(x, y, c)

    def line(self, x0, y0, x1, y1, c, width=1):
        steps = max(abs(x1 - x0), abs(y1 - y0), 1)
        for i in range(int(steps) + 1):
            x = round(x0 + (x1 - x0) * i / steps)
            y = round(y0 + (y1 - y0) * i / steps)
            for o in range(width):
                self.px(x + (o if abs(y1 - y0) > abs(x1 - x0) else 0), y + (0 if abs(y1 - y0) > abs(x1 - x0) else o), c)

    def ellipse(self, cx, cy, rx, ry, c):
        for y in range(int(cy - ry), int(cy + ry) + 1):
            for x in range(int(cx - rx), int(cx + rx) + 1):
                if ((x - cx) / max(rx, 0.5)) ** 2 + ((y - cy) / max(ry, 0.5)) ** 2 <= 1.0:
                    self.px(x, y, c)

    def gradient(self, y0, y1, colors, x0=0, x1=None):
        """Vertical gradient through the colors, dithered between bands like an old console."""
        x1 = self.w - 1 if x1 is None else x1
        n = len(colors) - 1
        for y in range(y0, y1 + 1):
            f = (y - y0) / max(1, y1 - y0) * n
            i = min(int(f), n - 1)
            frac = f - i
            for x in range(x0, x1 + 1):
                use = i + 1 if frac * 16 > BAYER[y % 4][x % 4] + 0.5 else i
                self.px(x, y, colors[use])

    def outline(self, colour):
        """Dark 1px outline around every opaque shape."""
        solid = {(x, y) for x in range(self.w) for y in range(self.h) if self.d[x, y][3] > 0}
        for x, y in solid:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if (x + dx, y + dy) not in solid and 0 <= x + dx < self.w and 0 <= y + dy < self.h:
                    self.d[x + dx, y + dy] = hexc(colour)

    def paste(self, other, x, y):
        self.img.alpha_composite(other.img, (int(x), int(y)))

    def save(self, *parts):
        path = os.path.join(ROOT, *parts)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        self.img.save(path)
        return path


# ---------------------------------------------------------------- shared scenery pieces

def speckle(c, y0, y1, colors, rng, density, x0=0, x1=None):
    x1 = c.w - 1 if x1 is None else x1
    for _ in range(int((x1 - x0) * (y1 - y0) * density)):
        c.px(rng.randint(x0, x1), rng.randint(y0, y1), rng.choice(colors))


def clouds(c, rng, count, y_max, light="#f4f4ee", shade="#cfd8e0"):
    for _ in range(count):
        cx, cy, w = rng.randint(0, c.w), rng.randint(4, y_max), rng.randint(14, 30)
        for i in range(4):
            ox = cx - w // 2 + i * w // 4 + rng.randint(-2, 2)
            c.ellipse(ox, cy + 1, w // 5 + 2, 3, shade)
        for i in range(4):
            ox = cx - w // 2 + i * w // 4 + rng.randint(-2, 2)
            c.ellipse(ox, cy - (1 if i in (1, 2) else 0), w // 5 + 1, 3 if i in (1, 2) else 2, light)


def hills(c, rng, base, height, colour, top_colour=None, freq=1.0):
    phase = rng.random() * 6
    for x in range(c.w):
        h = height * (0.55 + 0.3 * math.sin(x / 23 * freq + phase) + 0.15 * math.sin(x / 9 * freq + phase * 2))
        top = int(base - h)
        for y in range(top, base + 1):
            c.px(x, y, colour)
        if top_colour:
            c.px(x, top, top_colour)


def leafy_tree(c, rng, x, base, height, radius, greens, trunk=("#5a3d24", "#3e2a18")):
    """A round-topped oak: trunk, then a canopy of shaded blobs lit from the top left."""
    t0 = base - height
    c.rect(x - 1, t0, x + 1, base, trunk[0])
    c.rect(x + 1, t0, x + 1, base, trunk[1])
    c.px(x - 2, base, trunk[1])
    c.px(x + 2, base, trunk[1])
    blobs = [(x + rng.randint(-radius, radius), t0 + rng.randint(-radius // 2, radius // 3), rng.randint(radius // 2 + 1, radius)) for _ in range(5)]
    blobs.append((x, t0 - radius // 3, radius))
    for bx, by, r in blobs:
        c.ellipse(bx + 1, by + 1, r, r * 0.8, greens[0])
    for bx, by, r in blobs:
        c.ellipse(bx, by, r - 1, r * 0.8 - 1, greens[1])
    for bx, by, r in blobs:
        c.ellipse(bx - r // 3, by - r // 3, max(1, r // 2), max(1, r // 3), greens[2])
    for _ in range(radius * 3):
        bx, by, r = rng.choice(blobs)
        c.px(bx + rng.randint(-r + 1, r - 1), by + rng.randint(-r // 2, r // 2), rng.choice(greens))


def grass_tufts(c, rng, y0, y1, count, colours):
    for _ in range(count):
        x, y = rng.randint(0, c.w - 1), rng.randint(y0, y1)
        col = rng.choice(colours)
        c.px(x, y, col)
        c.px(x - 1, y + 1, col)
        c.px(x + 1, y + 1, col)
        c.px(x, y - 1, col)


def stones(c, rng, y0, y1, count, light="#a8a090", dark="#6a6458"):
    for _ in range(count):
        x, y = rng.randint(0, c.w - 1), rng.randint(y0, y1)
        c.rect(x, y, x + 1, y, light)
        c.px(x, y + 1, dark)
        c.px(x + 1, y + 1, dark)


def cottage(c, x, base, w, h, wall="#e2d3a8", beam="#4a3220", roof=("#c9a24a", "#9a7632", "#e2c070")):
    """A timber-framed cottage with a thatched roof, front facing the viewer."""
    c.rect(x, base - h, x + w, base, wall)
    c.rect(x, base - h, x, base, beam)
    c.rect(x + w, base - h, x + w, base, beam)
    c.rect(x, base - h, x + w, base - h, beam)
    c.line(x, base - h, x + w // 2, base - 2, beam)
    c.line(x + w, base - h, x + w // 2, base - 2, beam)
    c.rect(x + w // 2 - 2, base - 6, x + w // 2 + 1, base, "#5a3a22")
    c.rect(x + 2, base - h + 3, x + 4, base - h + 5, "#3a4a5a")
    c.rect(x + w - 4, base - h + 3, x + w - 2, base - h + 5, "#3a4a5a")
    rh = h // 2 + 6
    for i in range(rh):
        y = base - h - 1 - i
        inset = i * (w // 2 + 2) // rh
        c.rect(x - 2 + inset, y, x + w + 2 - inset, y, roof[0] if i % 3 else roof[1])
    c.rect(x - 2, base - h - 1, x + w + 2, base - h - 1, roof[1])
    for i in range(0, w + 4, 3):
        c.px(x - 2 + i, base - h - 2 - (i % 2), roof[2])
    c.rect(x + w - 5, base - h - rh + 2, x + w - 3, base - h - rh // 2, "#7a6a5a")


def banner(c, x, top, colour="#a01e22", trim="#e0b84a"):
    c.rect(x, top, x + 5, top + 10, colour)
    c.px(x, top + 11, colour)
    c.px(x + 5, top + 11, colour)
    c.rect(x, top, x + 5, top, trim)
    c.rect(x + 2, top + 4, x + 3, top + 6, trim)


def crow(c, x, y, colour="#1e1a22"):
    c.px(x - 2, y - 1, colour)
    c.px(x - 1, y, colour)
    c.px(x, y, colour)
    c.px(x + 1, y, colour)
    c.px(x + 2, y - 1, colour)


# ---------------------------------------------------------------- battle backdrops

def new_backdrop():
    return Canvas(BW, BH, "#000000")


def bd_sherwood_edge():
    rng = random.Random(11)
    c = new_backdrop()
    c.gradient(0, HORIZON, ["#c8d88a", "#8fb060", "#4f7a3a"])
    # far trunks, then a dark canopy roof with sunlit gaps
    for x in range(-4, BW, 9):
        tx = x + rng.randint(0, 4)
        c.rect(tx, 10, tx + 2, HORIZON, "#3e5a34")
    for _ in range(70):
        c.ellipse(rng.randint(0, BW), rng.randint(-4, 26), rng.randint(6, 14), rng.randint(4, 9), rng.choice(["#2a4a24", "#24401f", "#30552a"]))
    for _ in range(14):
        c.ellipse(rng.randint(0, BW), rng.randint(2, 22), 3, 2, rng.choice(["#5c8a3c", "#6e9a44"]))
    # light shafts falling through the leaves
    for sx in (30, 96, 150):
        for y in range(18, BH):
            for x in range(sx + (y - 18) // 3, sx + (y - 18) // 3 + 6):
                if (x + y) % 2 == 0:
                    c.px(x, y, (255, 246, 190, 34))
    # big near trunks with roots
    for tx in (6, 64, 122, 172):
        w = rng.randint(5, 7)
        c.rect(tx, 0, tx + w, HORIZON + 4, "#4a3322")
        c.rect(tx + w - 2, 0, tx + w, HORIZON + 4, "#33231a")
        c.rect(tx, 0, tx, HORIZON + 4, "#6a4a30")
        for y in range(4, HORIZON, 7):
            c.px(tx + 2 + y % 3, y, "#33231a")
        c.line(tx - 4, HORIZON + 6, tx, HORIZON + 2, "#4a3322", 2)
        c.line(tx + w + 4, HORIZON + 6, tx + w, HORIZON + 2, "#33231a", 2)
    c.gradient(HORIZON + 2, BH - 1, ["#5a7a34", "#4a6a2e", "#3e5a28", "#334a22"])
    speckle(c, HORIZON + 2, BH - 1, ["#6a8a3e", "#3a5426", "#7a6a3a", "#5a4a2a"], rng, 0.08)
    for _ in range(26):   # ferns
        x, y = rng.randint(0, BW), rng.randint(HORIZON + 8, BH - 4)
        for i in range(-4, 5):
            c.px(x + i, y - (4 - abs(i)) // 2, "#7aa040")
            c.px(x + i, y - (4 - abs(i)) // 2 + 1, "#4f7a2e")
        c.line(x, y, x, y + 3, "#3f6024")
    for _ in range(7):    # toadstools
        x, y = rng.randint(4, BW - 4), rng.randint(HORIZON + 10, BH - 4)
        c.rect(x, y, x, y + 2, "#e8e0c8")
        c.rect(x - 2, y - 1, x + 2, y - 1, "#c0302a")
        c.rect(x - 1, y - 2, x + 1, y - 2, "#c0302a")
        c.px(x - 1, y - 1, "#f4f0e0")
    grass_tufts(c, rng, HORIZON + 4, BH - 2, 60, ["#7aa046", "#8ab24e"])
    return c


def bd_great_north_road():
    rng = random.Random(12)
    c = new_backdrop()
    c.gradient(0, HORIZON, ["#4f86c4", "#78a8d8", "#b4d4e8", "#dce8e4"])
    clouds(c, rng, 6, 34)
    hills(c, rng, HORIZON - 4, 22, "#7a9aa4", freq=0.7)
    hills(c, rng, HORIZON - 1, 13, "#5f8a50", "#7aa25c")
    for x in range(0, BW, 5):   # hedgerow
        c.ellipse(x + rng.randint(0, 2), HORIZON - 1, 3, 2, rng.choice(["#3f6a30", "#4a7a36"]))
    leafy_tree(c, rng, 26, HORIZON, 14, 8, ["#2e5226", "#447a34", "#6a9e48"])
    leafy_tree(c, rng, 150, HORIZON - 1, 10, 6, ["#2e5226", "#447a34", "#6a9e48"])
    c.gradient(HORIZON, BH - 1, ["#86ae58", "#74a04c", "#628c42", "#527a38"])
    speckle(c, HORIZON, BH - 1, ["#94bc62", "#5a8240"], rng, 0.06)
    # the road: a wide dirt band with cart ruts and stones
    top, bot = 104, 176
    for y in range(top, bot + 1):
        wob = round(math.sin(y / 7) * 1.5)
        for x in range(BW):
            edge = y - top < 2 + (x + wob) % 3 or bot - y < 2 + (x * 7) % 3
            c.px(x, y, "#9a7e52" if edge else ("#b49466" if (x + y) % 9 else "#a88a5c"))
    for ry in (118, 124, 156, 162):
        for x in range(BW):
            if rng.random() < 0.85:
                c.px(x, ry + (1 if x % 23 < 3 else 0), "#7e6440")
    stones(c, rng, top + 4, bot - 4, 40, "#c8b48a", "#7e6440")
    speckle(c, top, bot, ["#c4a676", "#8e7248"], rng, 0.04)
    grass_tufts(c, rng, HORIZON + 4, top - 2, 30, ["#9cc466", "#4e7a34"])
    grass_tufts(c, rng, bot + 3, BH - 2, 30, ["#9cc466", "#4e7a34"])
    # milestone at the roadside
    c.rect(88, 90, 94, 102, "#a8a49a")
    c.rect(89, 88, 93, 89, "#a8a49a")
    c.rect(93, 90, 94, 102, "#7a766c")
    c.rect(90, 93, 92, 93, "#5a564e")
    c.rect(90, 96, 91, 96, "#5a564e")
    return c


def bd_locksley():
    rng = random.Random(13)
    c = new_backdrop()
    c.gradient(0, HORIZON, ["#5a90c8", "#8ab8dc", "#cfe2e6"])
    clouds(c, rng, 4, 26)
    hills(c, rng, HORIZON - 6, 14, "#6f9a5a", freq=0.8)
    leafy_tree(c, rng, 10, HORIZON - 2, 12, 9, ["#2e5226", "#447a34", "#6a9e48"])
    cottage(c, 22, HORIZON + 2, 26, 16)
    cottage(c, 70, HORIZON - 1, 20, 13, wall="#d8c49a")
    leafy_tree(c, rng, 104, HORIZON - 2, 10, 7, ["#2e5226", "#447a34", "#6a9e48"])
    cottage(c, 120, HORIZON + 3, 30, 18)
    c.rect(160, HORIZON - 14, 161, HORIZON + 2, "#6a6a6a")   # a little church tower in the distance
    c.rect(157, HORIZON - 10, 164, HORIZON + 2, "#9a968a")
    c.rect(159, HORIZON - 7, 162, HORIZON - 5, "#3a3a44")
    c.gradient(HORIZON + 3, BH - 1, ["#8cb45a", "#78a24e", "#668e44", "#567c3a"])
    speckle(c, HORIZON + 3, BH - 1, ["#9ac464", "#5a8240", "#c8c070"], rng, 0.05)
    # wattle fence along the back of the green
    for x in range(0, BW, 6):
        c.rect(x, HORIZON + 4, x, HORIZON + 12, "#6a4a2c")
    for y in (HORIZON + 6, HORIZON + 9):
        c.line(0, y, BW, y, "#8a6a40")
    # a beaten dirt path winding down the green
    for y in range(HORIZON + 13, BH):
        cx = 90 + round(math.sin(y / 18) * 22)
        w = 6 + (y - HORIZON) // 10
        c.rect(cx - w, y, cx + w, y, "#b29468" if y % 5 else "#a4865c")
        c.px(cx - w, y, "#8e7248")
        c.px(cx + w, y, "#8e7248")
    stones(c, rng, HORIZON + 16, BH - 4, 18, "#c4b08a", "#7e6440")
    # the village well
    c.rect(150, 130, 168, 140, "#9a968a")
    for x in range(150, 169, 4):
        c.rect(x, 130 + (x // 4) % 2 * 4, x + 3, 130 + (x // 4) % 2 * 4, "#6e6a60")
    c.rect(151, 116, 152, 130, "#5a3d24")
    c.rect(166, 116, 167, 130, "#5a3d24")
    c.rect(148, 112, 170, 115, "#8a3a2a")
    c.rect(150, 111, 168, 111, "#a84a34")
    c.line(159, 116, 159, 124, "#3a2a1a")
    c.rect(157, 124, 161, 127, "#7a5a34")
    grass_tufts(c, rng, HORIZON + 14, BH - 2, 50, ["#a2ca6c", "#4e7a34"])
    for _ in range(9):   # daisies
        x, y = rng.randint(0, BW), rng.randint(HORIZON + 14, BH - 2)
        c.px(x, y, "#f4f0e0")
        c.px(x + 1, y, "#f0d040")
    return c


def bd_nottingham_gate():
    rng = random.Random(14)
    c = new_backdrop()
    c.gradient(0, HORIZON, ["#7a8aa4", "#9cacbc", "#c4ccc8"])
    clouds(c, rng, 3, 14, "#e4e6e4", "#b4bcc4")
    # town wall with crenellations, two towers and the gatehouse
    wall_top = 22
    c.rect(0, wall_top, BW, HORIZON + 2, "#8e8676")
    for y in range(wall_top, HORIZON + 2, 5):
        off = 0 if (y // 5) % 2 else 5
        for x in range(off - 10, BW, 10):
            c.rect(x, y, x + 9, y, "#6e685c")
            c.px(x, y + 1, "#6e685c")
            c.px(x, y + 2, "#6e685c")
            c.px(x, y + 3, "#6e685c")
    for x in range(0, BW, 8):
        c.rect(x, wall_top - 5, x + 4, wall_top - 1, "#8e8676")
        c.rect(x + 4, wall_top - 5, x + 4, wall_top - 1, "#6e685c")
    for tx in (14, 148):
        c.rect(tx, 4, tx + 18, HORIZON + 2, "#9a9282")
        c.rect(tx + 14, 4, tx + 18, HORIZON + 2, "#7a7466")
        for x in range(tx, tx + 19, 5):
            c.rect(x, 0, x + 2, 3, "#9a9282")
        c.rect(tx + 7, 16, tx + 9, 22, "#2a2830")
        c.rect(tx + 7, 36, tx + 9, 42, "#2a2830")
    gx = 70
    c.rect(gx, 8, gx + 40, HORIZON + 2, "#a29a8a")
    for x in range(gx, gx + 41, 6):
        c.rect(x, 3, x + 3, 7, "#a29a8a")
    for y in range(28, HORIZON + 3):   # arched gateway
        half = 11 if y > 36 else round(math.sqrt(max(0, 121 - (36 - y) ** 2)))
        c.rect(gx + 20 - half, y, gx + 20 + half, y, "#2a2422")
    for x in range(gx + 10, gx + 31, 3):   # portcullis
        c.rect(x, 26, x, HORIZON - 6, "#4a4038")
    for y in range(30, HORIZON - 6, 4):
        c.rect(gx + 10, y, gx + 30, y, "#4a4038")
    banner(c, gx + 4, 12)
    banner(c, gx + 31, 12)
    banner(c, 40, wall_top + 2)
    banner(c, 132, wall_top + 2)
    # cobbled square
    c.rect(0, HORIZON + 3, BW, BH, "#7a7268")
    for row, y in enumerate(range(HORIZON + 3, BH, 5)):
        off = 0 if row % 2 else 3
        for x in range(-off, BW, 6):
            shade = rng.choice(["#9a9286", "#8e8678", "#a69e90"])
            c.rect(x + 1, y + 1, x + 4, y + 3, shade)
            c.px(x + 1, y + 1, "#b8b0a2")
    speckle(c, HORIZON + 3, BH - 1, ["#6a6258", "#5e7a40"], rng, 0.01)
    c.rect(0, HORIZON + 3, BW, HORIZON + 4, "#5e584e")
    return c


def bd_hanged_mans_crossing():
    rng = random.Random(15)
    c = new_backdrop()
    c.gradient(0, HORIZON, ["#4a3a6a", "#8a4a5a", "#d0704a", "#f0b06a"])
    c.ellipse(132, HORIZON - 6, 12, 12, "#f8d890")
    c.ellipse(132, HORIZON - 6, 9, 9, "#fce8b0")
    hills(c, rng, HORIZON - 2, 18, "#4a3a44", freq=0.6)
    hills(c, rng, HORIZON + 1, 9, "#3a3434", "#5a4a40")
    c.gradient(HORIZON + 2, BH - 1, ["#6a5a3e", "#5e5036", "#52462e", "#463c28"])
    speckle(c, HORIZON + 2, BH - 1, ["#7a6a46", "#4a3e2a", "#6a6a3a"], rng, 0.08)
    # two muddy tracks crossing
    for y in range(HORIZON + 2, BH):
        w = 5 + (y - HORIZON) // 9
        cx = 90 + (y - HORIZON) // 6
        c.rect(cx - w, y, cx + w, y, "#7e6844" if y % 4 else "#74603e")
    for y in range(128, 150):
        c.rect(0, y, BW, y, "#7e6844" if y % 3 else "#74603e")
    for _ in range(6):   # puddles holding the sunset
        x, y = rng.randint(10, BW - 20), rng.randint(HORIZON + 14, BH - 8)
        c.ellipse(x, y, rng.randint(4, 8), 2, "#c88a5a")
        c.rect(x - 2, y - 1, x + 1, y - 1, "#f0b878")
    # a bare twisted oak
    tx = 34
    c.rect(tx, 18, tx + 4, HORIZON + 6, "#2e2422")
    c.rect(tx + 3, 18, tx + 4, HORIZON + 6, "#1e1816")
    for (x0, y0, x1, y1) in ((tx, 30, tx - 14, 14), (tx - 9, 19, tx - 18, 16), (tx + 4, 26, tx + 20, 10), (tx + 14, 15, tx + 26, 16), (tx + 2, 20, tx + 6, 4), (tx - 14, 14, tx - 16, 6)):
        c.line(x0, y0, x1, y1, "#2e2422", 2)
    crow(c, tx + 21, 8)
    crow(c, 88, 14)
    crow(c, 100, 20)
    # the old crossroads signpost
    sx = 120
    c.rect(sx, 40, sx + 1, HORIZON + 8, "#4a3424")
    c.rect(sx - 12, 42, sx + 2, 46, "#7a5a3a")
    c.px(sx - 13, 44, "#7a5a3a")
    c.rect(sx, 50, sx + 14, 54, "#6e5034")
    c.px(sx + 15, 52, "#6e5034")
    c.rect(sx - 10, 44, sx - 2, 44, "#3a2a1a")
    c.rect(sx + 3, 52, sx + 11, 52, "#3a2a1a")
    grass_tufts(c, rng, HORIZON + 4, BH - 2, 40, ["#8a8a4a", "#5a5432"])
    return c


def bd_sheriffs_toll_bridge():
    rng = random.Random(16)
    c = new_backdrop()
    c.gradient(0, HORIZON - 16, ["#5a8cc4", "#8ab4d8", "#c4dce4"])
    clouds(c, rng, 4, 20)
    hills(c, rng, HORIZON - 18, 12, "#5a8a4e", "#78a25e")
    for x in range(0, BW, 7):
        leafy_tree(c, rng, x + rng.randint(0, 3), HORIZON - 18, 3, 4, ["#2a4a24", "#3a6a30", "#5a8a40"])
    c.gradient(HORIZON - 17, HORIZON + 6, ["#7aa4c4", "#4f7ea4", "#3a6488"])   # the river
    for _ in range(40):
        x, y = rng.randint(0, BW), rng.randint(HORIZON - 15, HORIZON + 4)
        c.rect(x, y, x + rng.randint(2, 5), y, "#b4d4e8")
    # toll booth on the far end, Sheriff's colours
    c.rect(132, 14, 160, HORIZON - 6, "#8a6a44")
    for x in range(132, 161, 4):
        c.rect(x, 14, x, HORIZON - 6, "#6a4e30")
    c.rect(128, 8, 164, 13, "#8a3226")
    c.rect(130, 5, 162, 7, "#a84434")
    c.rect(142, 26, 150, 34, "#2a2422")
    banner(c, 120, 14)
    c.rect(100, 34, 131, 35, "#c8b04a")   # the toll barrier, striped
    for x in range(100, 132, 6):
        c.rect(x, 34, x + 2, 35, "#a01e22")
    c.rect(130, 32, 132, HORIZON - 6, "#5a4028")
    # the bridge deck: planks running across, with a railing at the back
    for x in range(0, BW, 7):
        shade = rng.choice(["#9a7a4e", "#8e6e44", "#a48456"])
        c.rect(x, HORIZON + 7, x + 5, BH, shade)
        c.rect(x + 6, HORIZON + 7, x + 6, BH, "#4a3420")
        for y in range(HORIZON + 10, BH, rng.randint(9, 15)):
            c.rect(x + 1, y, x + 3, y, "#7a5c38")
        c.px(x + 1, HORIZON + 9, "#3a2a1a")
        c.px(x + 4, BH - 3, "#3a2a1a")
    speckle(c, HORIZON + 8, BH - 1, ["#b49466", "#6e5232"], rng, 0.03)
    c.rect(0, HORIZON - 2, BW, HORIZON - 1, "#6a4a2c")   # rail
    c.rect(0, HORIZON + 3, BW, HORIZON + 3, "#6a4a2c")
    for x in range(2, BW, 16):
        c.rect(x, HORIZON - 4, x + 2, HORIZON + 7, "#5a3d24")
        c.px(x, HORIZON - 4, "#7a5a3a")
    c.rect(0, HORIZON + 6, BW, HORIZON + 6, "#3a2818")
    return c


def bd_brook_bridge():
    """Where Robin met Little John: a log over a woodland brook."""
    rng = random.Random(17)
    c = bd_sherwood_edge()
    # a brook running across the ground, crossed by a single great log
    for y in range(118, 168):
        wob = round(math.sin(y / 5) * 2)
        for x in range(BW):
            edge = min(y - 118, 167 - y)
            colour = "#4a7a9a" if edge > 3 else ("#6a9ab8" if edge > 1 else "#5a4a2e")
            c.px(x + wob * 0, y, colour)
    for _ in range(70):
        x, y = rng.randint(0, BW), rng.randint(122, 164)
        c.rect(x, y, x + rng.randint(2, 6), y, "#a8d0e4")
    for _ in range(12):   # stones in the water
        x, y = rng.randint(0, BW), rng.randint(124, 162)
        c.ellipse(x, y, 3, 2, "#8a8478")
        c.rect(x - 1, y - 1, x + 1, y - 1, "#aaa496")
    # the log runs from bank to bank, bark lines along its length
    c.rect(81, 108, 99, 178, "#6a4a2c")
    c.rect(81, 108, 83, 178, "#8a6a40")
    c.rect(97, 108, 99, 178, "#3e2a18")
    for x in range(85, 97, 4):
        for y in range(110, 177, 2):
            if rng.random() < 0.6:
                c.px(x, y, "#5a3d24")
    c.ellipse(90, 108, 9, 3, "#a08050")   # cut end, showing the rings
    c.ellipse(90, 108, 5, 1.5, "#c8a070")
    c.ellipse(90, 178, 9, 3, "#3e2a18")
    return c


def bd_friars_ford():
    """Fountain Dale: a wide shallow river with a gravel ford, willows on the banks."""
    rng = random.Random(18)
    c = new_backdrop()
    c.gradient(0, HORIZON, ["#6a9ccc", "#9cc4e0", "#d0e4e4"])
    clouds(c, rng, 4, 28)
    hills(c, rng, HORIZON - 4, 16, "#6f9a5a", "#86ae6a")
    for x in (14, 60, 148):
        leafy_tree(c, rng, x, HORIZON + 2, 14, 10, ["#3a5a2a", "#5a8a3a", "#88b05a"])
        for i in range(-8, 9, 3):   # willow fronds hanging down
            c.line(x + i, HORIZON - 14, x + i + 1, HORIZON - 2 + abs(i) // 3, "#6a9a40")
    c.rect(0, HORIZON + 3, BW, BH, "#7aa25a")
    c.gradient(HORIZON + 3, 92, ["#86ae58", "#74a04c"])
    c.gradient(93, 186, ["#5a8ab0", "#4a7aa4", "#3e6a94"])   # the river
    for _ in range(90):
        x, y = rng.randint(0, BW), rng.randint(95, 184)
        c.rect(x, y, x + rng.randint(2, 7), y, rng.choice(["#8ab8d8", "#a8d0e4"]))
    for y in range(93, 187):   # the gravel ford, angling across
        cx = 100 + (y - 93) // 3
        for x in range(cx - 14, cx + 15):
            if rng.random() < 0.7:
                c.px(x, y, rng.choice(["#b8a888", "#a09070", "#c8b898"]))
    c.gradient(187, BH - 1, ["#8a7a52", "#7aa25a", "#6a9248"])
    grass_tufts(c, rng, HORIZON + 6, 90, 30, ["#a2ca6c", "#4e7a34"])
    grass_tufts(c, rng, 192, BH - 2, 20, ["#a2ca6c", "#4e7a34"])
    for _ in range(10):   # reeds
        x = rng.randint(0, BW)
        y = rng.choice([92, 188])
        c.line(x, y, x, y - 7, "#5a7a30")
        c.rect(x, y - 9, x, y - 7, "#7a5a30")
    return c


def bd_archery_contest():
    """The Sheriff's contest outside Nottingham: banners, a stand of nobles, straw targets."""
    rng = random.Random(19)
    c = new_backdrop()
    c.gradient(0, HORIZON, ["#5a90c8", "#8ab8dc", "#cfe2e6"])
    clouds(c, rng, 4, 20)
    # Nottingham's walls on the skyline
    c.rect(0, 26, BW, HORIZON - 14, "#9a9282")
    for x in range(0, BW, 7):
        c.rect(x, 22, x + 3, 25, "#9a9282")
    c.rect(120, 4, 146, HORIZON - 14, "#aaa292")
    for x in range(120, 147, 6):
        c.rect(x, 0, x + 3, 3, "#aaa292")
    banner(c, 130, 8)
    # the noble stand, striped awning
    c.rect(20, HORIZON - 16, 100, HORIZON + 2, "#6a4a2c")
    for x in range(20, 101, 8):
        c.rect(x, HORIZON - 24, x + 3, HORIZON - 16, "#a01e22")
        c.rect(x + 4, HORIZON - 24, x + 7, HORIZON - 16, "#e0c050")
    for i in range(10):   # spectators
        x = 24 + i * 8
        c.rect(x, HORIZON - 12, x + 4, HORIZON - 4, rng.choice(["#3a5aa0", "#7a3a8a", "#2a6a3a", "#a03a2a", "#c8a040"]))
        c.rect(x + 1, HORIZON - 15, x + 3, HORIZON - 13, "#e0b090")
    c.gradient(HORIZON + 3, BH - 1, ["#8cb45a", "#7aa44e", "#689246", "#5a823c"])
    speckle(c, HORIZON + 3, BH - 1, ["#9ac464", "#5a8240"], rng, 0.05)
    # straw targets on stands, far end of the field
    for tx in (128, 152, 174):
        c.line(tx - 4, HORIZON + 22, tx, HORIZON + 6, "#5a3d24")
        c.line(tx + 4, HORIZON + 22, tx, HORIZON + 6, "#5a3d24")
        for r, colour in ((7, "#e0c870"), (5, "#c03a2a"), (3, "#f0ece0"), (1, "#c03a2a")):
            c.ellipse(tx, HORIZON + 8, r, r, colour)
    # pennant line strung across the field
    for x in range(0, BW, 6):
        y = HORIZON + 30 + round(math.sin(x / 30) * 3)
        c.px(x, y, "#3a2a1a")
        c.rect(x + 1, y + 1, x + 3, y + 1, ["#a01e22", "#e0c050", "#3a5aa0"][(x // 6) % 3])
        c.px(x + 2, y + 2, ["#a01e22", "#e0c050", "#3a5aa0"][(x // 6) % 3])
    c.rect(0, 150, BW, 150, "#e8e4d8")   # the shooting line chalked on the grass
    grass_tufts(c, rng, HORIZON + 6, BH - 2, 40, ["#a2ca6c", "#4e7a34"])
    return c


BACKDROPS = {
    "sherwood_edge": bd_sherwood_edge,
    "great_north_road": bd_great_north_road,
    "locksley": bd_locksley,
    "nottingham_gate": bd_nottingham_gate,
    "hanged_mans_crossing": bd_hanged_mans_crossing,
    "sheriffs_toll_bridge": bd_sheriffs_toll_bridge,
    "brook_bridge": bd_brook_bridge,
    "friars_ford": bd_friars_ford,
    "archery_contest": bd_archery_contest,
}


# ---------------------------------------------------------------- strategic map

MW, MH = 176, 196        # shown at 2x in the 352x392 map area
ICON_LIFT = 6            # icons sit this many map pixels above their node so the label fits below
INK = "#4a3826"


def map_point(node):
    return node["x"] / 2, node["y"] / 2 - ICON_LIFT


def bezier(p0, p1, bend):
    mx, my = (p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    ctrl = (mx - dy * bend, my + dx * bend)
    n = int(math.hypot(dx, dy) * 2) + 1
    pts = []
    for i in range(n + 1):
        t = i / n
        pts.append(((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * ctrl[0] + t * t * p1[0],
                    (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * ctrl[1] + t * t * p1[1]))
    return pts


def map_tree(c, x, y, rng):
    dark, mid, light = rng.choice([("#2e4a26", "#4a7236", "#6e9a4a"), ("#2a4422", "#41682f", "#5f8c40")])
    c.rect(x, y + 2, x, y + 3, "#5a3d24")
    c.rect(x - 2, y - 1, x + 2, y + 1, mid)
    c.rect(x - 1, y - 2, x + 1, y + 2, mid)
    c.px(x - 1, y - 1, light)
    c.px(x + 2, y + 1, dark)
    c.px(x + 1, y + 2, dark)


def icon_camp(c, x, y):
    """The Major Oak with the band's tent beneath it."""
    rng = random.Random(1)
    leafy_tree(c, rng, x - 2, y + 6, 6, 6, ["#2a4422", "#4a7a34", "#78a84c"])
    for i in range(6):   # tent
        c.rect(x + 2 + i // 2, y + 6 - i, x + 9 - i // 2, y + 6 - i, "#c8b88a" if i else "#a8986a")
    c.rect(x + 5, y + 3, x + 6, y + 6, "#4a3826")
    c.px(x, y + 6, "#f0a030")   # campfire
    c.px(x, y + 5, "#f8d050")


def icon_village(c, x, y):
    cottage(c, x - 7, y + 6, 8, 5)
    cottage(c, x + 1, y + 7, 7, 4, wall="#d4c49c")


def icon_forest(c, x, y):
    rng = random.Random(2)
    for dx, dy in ((-5, 2), (4, 1), (0, -2), (-1, 4), (6, 5)):
        leafy_tree(c, rng, x + dx, y + dy + 4, 3, 3, ["#203a1c", "#355a2a", "#527e3a"])


def icon_signpost(c, x, y):
    c.rect(x, y - 4, x, y + 6, "#4a3424")
    c.rect(x - 5, y - 3, x - 1, y - 1, "#8a6a44")
    c.px(x - 6, y - 2, "#8a6a44")
    c.rect(x + 1, y, x + 5, y + 2, "#7a5a3a")
    c.px(x + 6, y + 1, "#7a5a3a")
    c.rect(x - 3, y + 6, x + 3, y + 6, "#6a5a3e")


def icon_toll(c, x, y):
    c.rect(x - 4, y - 3, x + 3, y + 5, "#8a6a44")
    c.rect(x - 5, y - 5, x + 4, y - 3, "#a03a2a")
    c.rect(x - 1, y + 1, x, y + 5, "#2a2422")
    c.rect(x + 4, y + 2, x + 10, y + 2, "#c8b04a")
    c.px(x + 6, y + 2, "#a01e22")
    c.px(x + 9, y + 2, "#a01e22")


def icon_town(c, x, y):
    """Nottingham: castle keep on its rock behind the town wall."""
    c.rect(x - 9, y + 1, x + 9, y + 7, "#9a9282")
    for i in range(-9, 10, 3):
        c.px(x + i, y, "#9a9282")
    c.rect(x - 4, y - 7, x + 4, y + 1, "#aaa292")
    c.rect(x + 2, y - 7, x + 4, y + 1, "#8a8476")
    for i in (-4, -2, 0, 2, 4):
        c.px(x + i, y - 8, "#aaa292")
    c.rect(x - 1, y - 4, x, y - 2, "#2a2830")
    c.rect(x - 1, y + 4, x + 1, y + 7, "#2a2422")
    c.line(x, y - 8, x, y - 13, "#3a2a1a")
    c.rect(x + 1, y - 13, x + 4, y - 11, "#a01e22")
    for tx in (-9, 8):
        c.rect(x + tx, y - 2, x + tx + 1, y + 7, "#8a8476")


def icon_for(node_id, node):
    if node_id == "sheriffs_toll_bridge":
        return icon_toll
    if node_id == "hanged_mans_crossing":
        return icon_signpost
    return {"camp": icon_camp, "village": icon_village, "forest": icon_forest, "road": icon_signpost, "town": icon_town}[node["kind"]]


def make_map():
    rng = random.Random(21)
    data = json.load(open(os.path.join(ROOT, "data", "map.json")))
    nodes = data["nodes"]
    c = Canvas(MW, MH, "#d8c497")
    # aged parchment: mottled, darker towards the edges
    for y in range(MH):
        for x in range(MW):
            edge = min(x, y, MW - 1 - x, MH - 1 - y)
            t = max(0.0, 1 - edge / 22) ** 2 * 0.5 + rng.random() * 0.08
            c.px(x, y, mix("#dccb9e", "#a88a5a", t))
    for _ in range(30):
        c.ellipse(rng.randint(0, MW), rng.randint(0, MH), rng.randint(4, 12), rng.randint(3, 8), (168, 138, 90, 26))

    pts = {k: map_point(n) for k, n in nodes.items()}
    near_place = lambda x, y, r: any(math.hypot(x - px, y - py) < r for px, py in pts.values())

    # farmland strips in the open north
    for fx, fy in ((50, 14), (78, 30), (112, 14), (150, 40), (165, 70)):
        for i in range(4):
            for j in range(8):
                xx, yy = fx + j * 2 - 8, fy + i * 3 - 6
                if not near_place(xx, yy, 10):
                    c.rect(xx, yy, xx + 1, yy + 1, ["#c8bc78", "#a8b468", "#bca86a", "#9cae60"][(i + j // 4) % 4])
    # hills to the east
    for hx, hy in ((150, 90), (162, 98), (156, 106), (168, 84), (120, 150), (100, 112)):
        for i in range(-4, 5):
            c.px(hx + i, hy - (4 - abs(i)) // 2, INK)
        c.rect(hx - 1, hy - 1, hx + 1, hy, "#b89a6a")

    # the river, flowing from the east under the Sheriff's bridge and away south-west
    river = bezier((MW + 4, 100), pts["sheriffs_toll_bridge"], 0.1) + bezier(pts["sheriffs_toll_bridge"], (104, MH + 4), 0.2)
    water = set()
    for i, (x, y) in enumerate(river):
        w = 2.4 + i / len(river) * 1.6
        for yy in range(int(y - w), int(y + w) + 1):
            for xx in range(int(x - w), int(x + w) + 1):
                if math.hypot(xx - x, yy - y) <= w:
                    water.add((xx, yy))
    for xx, yy in water:
        c.px(xx, yy, "#6a9ab4")
    for xx, yy in water:
        if any((xx + dx, yy + dy) not in water for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
            c.px(xx, yy, "#3e6a88")
        elif (xx * 3 + yy) % 11 == 0:
            c.px(xx, yy, "#a8cce0")

    # Sherwood: trees thick around the outlaw places, kept clear of roads and places
    forest = [(30, 52, 30), (72, 88, 34), (50, 128, 26), (112, 82, 22), (98, 112, 18), (20, 100, 20)]
    road_pts = []
    drawn = set()
    for a, n in nodes.items():
        for b in n["links"]:
            key = tuple(sorted((a, b)))
            if key in drawn:
                continue
            drawn.add(key)
            bend = ((sum(map(ord, key[0] + key[1])) % 7) - 3) * 0.04   # stable per road, unlike hash()
            road_pts.append(bezier(pts[key[0]], pts[key[1]], bend))
    on_road = lambda x, y, r: any(math.hypot(x - rx, y - ry) < r for road in road_pts for rx, ry in road[::2])
    trees = []
    for gy in range(4, MH - 4, 5):
        for gx in range(4, MW - 4, 5):
            x, y = gx + rng.randint(-1, 2), gy + rng.randint(-1, 2)
            inside = any(math.hypot(x - fx, y - fy) < r * (0.85 + rng.random() * 0.3) for fx, fy, r in forest)
            if inside and not near_place(x, y, 11) and not on_road(x, y, 4) and (x, y) not in water:
                trees.append((x, y))
    for x, y in sorted(trees, key=lambda p: p[1]):
        map_tree(c, x, y, rng)

    # roads: dusty tracks, turning to planks where they cross water
    for road in road_pts:
        for x, y in road:
            for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1)):
                xx, yy = int(x) + dx, int(y) + dy
                if (xx, yy) in water:
                    c.px(xx, yy, "#8a6a44")
                else:
                    c.px(xx, yy, "#a2865a" if (xx + yy) % 5 else "#8e7248")

    # compass rose
    cx, cy = 18, MH - 20
    c.line(cx, cy - 9, cx, cy + 9, INK)
    c.line(cx - 9, cy, cx + 9, cy, INK)
    c.rect(cx - 1, cy - 8, cx + 1, cy - 2, "#a01e22")
    c.rect(cx - 1, cy + 2, cx + 1, cy + 8, INK)
    c.px(cx, cy - 10, INK)
    c.ellipse(cx, cy, 2, 2, "#e0c070")
    for dy, row in enumerate(("1001", "1101", "1011", "1001")):   # a tiny N above the needle
        for dx, bit in enumerate(row):
            if bit == "1":
                c.px(cx - 2 + dx, cy - 16 + dy, INK)

    # each place's icon
    for k, n in nodes.items():
        x, y = pts[k]
        icon = Canvas(MW, MH)
        icon_for(k, n)(icon, round(x), round(y))
        icon.outline("#2a1e14")
        c.paste(icon, 0, 0)

    # inked double frame
    for i, colour in ((0, "#3a2a1a"), (1, "#8a6a44"), (3, "#5a4430")):
        c.rect(i, i, MW - 1 - i, i, colour)
        c.rect(i, MH - 1 - i, MW - 1 - i, MH - 1 - i, colour)
        c.rect(i, i, i, MH - 1 - i, colour)
        c.rect(MW - 1 - i, i, MW - 1 - i, MH - 1 - i, colour)
    return c


# ---------------------------------------------------------------- UI pieces

def frame(fill, light, dark, border="#1e140c", size=12):
    """A bevelled 9-slice frame: dark border, lit top-left edge, shaded bottom-right."""
    c = Canvas(size, size, fill)
    c.rect(1, 1, size - 2, 1, light)
    c.rect(1, 1, 1, size - 2, light)
    c.rect(1, size - 2, size - 2, size - 2, dark)
    c.rect(size - 2, 1, size - 2, size - 2, dark)
    c.rect(0, 0, size - 1, 0, border)
    c.rect(0, size - 1, size - 1, size - 1, border)
    c.rect(0, 0, 0, size - 1, border)
    c.rect(size - 1, 0, size - 1, size - 1, border)
    return c


def make_ui():
    frame("#6a4a2c", "#8e6a42", "#4a321e").save("assets", "ui", "button.png")
    frame("#7e5a36", "#a47c4e", "#56391f").save("assets", "ui", "button_hover.png")
    frame("#4a321e", "#3a2616", "#6a4a2c").save("assets", "ui", "button_pressed.png")
    frame("#3e3226", "#4a3e32", "#2e2620", border="#1a140e").save("assets", "ui", "button_disabled.png")
    p = frame("#2a1e14", "#4a3826", "#1a120c", border="#0e0a06")
    p.rect(2, 2, 9, 9, (42, 30, 20, 235))
    p.save("assets", "ui", "panel.png")
    plaque = frame("#e8d8aa", "#f8ecc8", "#b49a6a", border="#4a3826")
    plaque.save("assets", "ui", "plaque.png")
    frame("#f0d070", "#fff0a8", "#c09a3a", border="#4a3826").save("assets", "ui", "plaque_selected.png")
    shadow = Canvas(28, 8)
    shadow.ellipse(13.5, 3.5, 13, 3.5, (0, 0, 0, 110))
    shadow.save("assets", "ui", "shadow.png")
    for name, colour in (("ring_turn", "#ffd860"), ("ring_target", "#7ad4ff")):
        ring = Canvas(32, 10)
        ring.ellipse(15.5, 4.5, 15, 4.5, hexc(colour, 255))
        # hollow out the middle, leaving a soft shadow inside the ring
        for y in range(10):
            for x in range(32):
                if ((x - 15.5) / 12.5) ** 2 + ((y - 4.5) / 2.8) ** 2 <= 1:
                    ring.d[x, y] = (0, 0, 0, 90)
        ring.save("assets", "ui", name + ".png")


# ---------------------------------------------------------------- mission path medallions

def medallion(fill="#5a4430", rim="#c8a860", dark="#2a1e14"):
    c = Canvas(22, 22)
    c.ellipse(10.5, 10.5, 10.5, 10.5, dark)
    c.ellipse(10.5, 10.5, 9.5, 9.5, rim)
    c.ellipse(10.5, 10.5, 8, 8, fill)
    c.ellipse(9, 8.5, 5, 4, mix(fill, "#ffffff", 0.08))
    return c


def node_approach(c):     # footprints along a trail
    for x, y in ((6, 13), (9, 9), (12, 13), (15, 8)):
        c.rect(x, y, x + 1, y + 2, "#e8dcc0")
        c.px(x, y + 3, "#e8dcc0")


def node_combat(c):       # crossed swords
    for d in (1, -1):
        x0 = 5 if d == 1 else 16
        c.line(x0, 5, x0 + 10 * d, 15, "#e8ecf2")
        c.line(x0 + d, 5, x0 + 10 * d + d, 15, "#a8b0bc")
        c.line(x0 + 7 * d, 15, x0 + 10 * d, 12, "#c8a040")
        c.px(x0 + 11 * d, 16, "#6a4a2c")


def node_choice(c):       # a fork in the road with a question mark
    for y, row in enumerate((".###.", "#...#", "...#.", "..#..", "..#..", ".....", "..#..")):
        for x, bit in enumerate(row):
            if bit == "#":
                c.rect(8 + x, 5 + y * 2, 8 + x, 6 + y * 2, "#f0d070")


def node_hazard(c):       # brambles and a rock
    c.ellipse(11, 13, 5, 3, "#8a8478")
    c.rect(8, 11, 12, 11, "#aaa496")
    for x0, y0, x1, y1 in ((4, 15, 9, 6), (9, 6, 13, 10), (12, 15, 17, 6), (6, 9, 10, 12)):
        c.line(x0, y0, x1, y1, "#5a8a3a")
    for x, y in ((6, 10), (10, 7), (15, 9), (13, 13), (8, 13)):
        c.px(x, y, "#c84040")


def node_objective(c):    # a treasure chest
    c.rect(5, 9, 16, 15, "#8a5a2c")
    c.rect(5, 7, 16, 9, "#a8703a")
    c.rect(5, 9, 16, 9, "#3a2414")
    c.rect(10, 9, 11, 11, "#f0d070")
    c.rect(5, 12, 16, 12, "#6a4420")
    c.px(7, 7, "#c8904a")


def node_duel(c):        # crossed quarterstaves: a friendly bout
    for o in (0, 1):
        c.line(5 + o, 4, 16 + o, 16, "#d8b070")
        c.line(16 + o, 4, 5 + o, 16, "#b08a50")
    for x, y in ((5, 4), (16, 16), (16, 4), (5, 16)):
        c.px(x, y, "#5a3d24")


def node_escape(c):       # the Major Oak, home
    rng = random.Random(3)
    leafy_tree(c, rng, 10, 16, 5, 5, ["#2a4422", "#4a7a34", "#78a84c"])


def trap_mark():
    c = Canvas(10, 10)
    for i in range(0, 10, 3):
        c.line(i, 0, i, 9, "#d04030")
        c.line(0, i, 9, i, "#d04030")
    c.outline("#2a0e0a")
    return c


NODE_ICONS = {"approach": node_approach, "combat": node_combat, "choice": node_choice, "duel": node_duel,
              "hazard": node_hazard, "objective": node_objective, "escape": node_escape}


def make_nodes():
    for kind, fn in NODE_ICONS.items():
        c = medallion()
        fn(c)
        c.save("assets", "ui", "node_%s.png" % kind)
    trap_mark().save("assets", "ui", "trap_mark.png")


# ---------------------------------------------------------------- armory item icons

def item_bow(c, wood, string="#e8e0c8"):
    pts = [(3, 2), (6, 2), (9, 4), (11, 7), (13, 10), (13, 13)]
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        c.line(x0, y0, x1, y1, wood)
        c.line(x0, y0 + 1, x1, y1 + 1, wood)
    c.line(3, 3, 13, 13, string)
    c.rect(9, 5, 10, 6, "#6a3a1a")


def item_staff(c, wood, cap):
    c.line(2, 14, 13, 3, wood)
    c.line(3, 14, 14, 3, mix(wood, "#000000", 0.3))
    c.rect(12, 2, 14, 4, cap)
    c.rect(2, 13, 3, 15, cap)


def item_sword(c, blade, hilt):
    c.line(4, 12, 13, 3, blade)
    c.line(5, 12, 14, 3, mix(blade, "#000000", 0.25))
    c.line(2, 10, 6, 14, hilt)
    c.line(2, 14, 4, 12, "#5a3a20")
    c.px(14, 2, blade)


def item_cudgel(c):
    c.line(3, 14, 10, 7, "#5a3a20")
    c.line(4, 14, 11, 7, "#3e2814")
    c.ellipse(11.5, 5.5, 3, 3, "#4a3020")
    c.px(10, 4, "#6a4a30")
    c.px(14, 3, "#2a1a10")
    c.px(9, 6, "#2a1a10")


def item_spear(c):
    c.line(2, 14, 11, 5, "#7a5a34")
    c.line(3, 14, 12, 5, "#5a3d24")
    c.rect(11, 3, 13, 5, "#d8dce4")
    c.rect(13, 1, 14, 2, "#d8dce4")
    c.px(12, 2, "#e8ecf2")


def item_torso(c, cloth, trim, studs=None, mail=False):
    c.rect(4, 3, 11, 13, cloth)
    c.rect(2, 3, 3, 8, cloth)
    c.rect(12, 3, 13, 8, cloth)
    c.rect(6, 2, 9, 3, (0, 0, 0, 0))
    c.rect(6, 3, 9, 3, trim)
    c.rect(4, 13, 11, 13, trim)
    if studs:
        for y in range(5, 12, 3):
            for x in range(5, 11, 3):
                c.px(x, y, studs)
    if mail:
        for y in range(4, 13):
            for x in range(4 + y % 2, 12, 2):
                c.px(x, y, "#7a8088")


def item_charm(c):
    for dx, dy in ((-2, -2), (2, -2), (-2, 2), (2, 2)):
        c.ellipse(8 + dx, 7 + dy, 2, 2, "#4a9a3a")
    c.px(7, 6, "#7ac85a")
    c.line(8, 9, 10, 14, "#3a6a2a")


def item_boots(c):
    for x0 in (2, 8):
        c.rect(x0, 3, x0 + 3, 11, "#7a5a3a")
        c.rect(x0, 11, x0 + 5, 13, "#5a3d24")
        c.rect(x0, 3, x0 + 3, 4, "#9a7a50")


def item_satchel(c):
    c.rect(3, 6, 12, 13, "#8a6a40")
    c.rect(3, 6, 12, 8, "#a4804e")
    c.line(4, 6, 7, 2, "#5a3d24")
    c.line(11, 6, 8, 2, "#5a3d24")
    c.rect(7, 8, 8, 9, "#c8a040")
    c.px(5, 5, "#5aa040")
    c.px(10, 4, "#7ac85a")
    c.px(11, 5, "#5aa040")


def item_lute(c, wood, strings):
    c.ellipse(6, 10, 4, 4, wood)
    c.ellipse(6, 10, 1, 1, "#3a2614")
    c.line(8, 7, 13, 2, "#6a4a2a")
    c.rect(13, 1, 14, 2, "#4a3020")
    c.line(4, 12, 13, 3, strings)


ITEM_ICONS = {
    "ash_lute": lambda c: item_lute(c, "#c8904a", "#e8e0c8"),
    "silver_harp": lambda c: item_lute(c, "#8a5a2a", "#d8dce4"),
    "yew_longbow": lambda c: item_bow(c, "#a0703a"),
    "hunters_recurve": lambda c: item_bow(c, "#6a4a2a"),
    "ironshod_staff": lambda c: item_staff(c, "#8a6a40", "#a8b0bc"),
    "great_oak_staff": lambda c: item_staff(c, "#6a4a2a", "#4a7a34"),
    "friars_staff": lambda c: item_staff(c, "#a08050", "#e8e0c8"),
    "duelling_sword": lambda c: item_sword(c, "#e8ecf2", "#c8a040"),
    "fine_arming_sword": lambda c: item_sword(c, "#d0d6e0", "#a03a2a"),
    "blackthorn_cudgel": item_cudgel,
    "outlaw_spear": item_spear,
    "padded_jerkin": lambda c: item_torso(c, "#8a7a5a", "#5a4a30"),
    "leather_brigandine": lambda c: item_torso(c, "#7a4a2a", "#4a2a14", studs="#d8c070"),
    "mail_shirt": lambda c: item_torso(c, "#a8b0bc", "#6a7078", mail=True),
    "lucky_charm": item_charm,
    "hunters_boots": item_boots,
    "herb_satchel": item_satchel,
}


def make_items():
    for item_id, fn in ITEM_ICONS.items():
        c = Canvas(16, 16)
        fn(c)
        c.outline("#1e140c")
        c.save("assets", "items", item_id + ".png")


# ---------------------------------------------------------------- battle effects

def make_fx():
    arrow = Canvas(14, 5)
    arrow.rect(2, 2, 10, 2, "#8a6a40")
    arrow.rect(11, 1, 12, 3, "#c8ccd4")
    arrow.px(13, 2, "#c8ccd4")
    arrow.rect(0, 1, 2, 1, "#e8e0c8")
    arrow.rect(0, 3, 2, 3, "#e8e0c8")
    arrow.save("assets", "fx", "arrow.png")
    bolt = Canvas(10, 5)
    bolt.rect(1, 2, 7, 2, "#5a3d24")
    bolt.rect(7, 1, 9, 3, "#9aa0aa")
    bolt.rect(0, 1, 1, 3, "#a03a2a")
    bolt.save("assets", "fx", "bolt.png")
    net = Canvas(14, 14)
    for i in range(1, 14, 3):
        net.line(i, 1, i, 12, "#d8c8a0")
        net.line(1, i, 12, i, "#d8c8a0")
    for x, y in ((1, 1), (12, 1), (1, 12), (12, 12)):
        net.rect(x - 1, y - 1, x, y, "#7a7468")
    net.save("assets", "fx", "net.png")
    spark = Canvas(9, 9)
    for i in range(9):
        spark.px(i, 4, "#fff4c0")
        spark.px(4, i, "#fff4c0")
    spark.px(2, 2, "#ffe080")
    spark.px(6, 6, "#ffe080")
    spark.px(2, 6, "#ffe080")
    spark.px(6, 2, "#ffe080")
    spark.rect(3, 3, 5, 5, "#ffffff")
    spark.save("assets", "fx", "spark.png")
    note = Canvas(8, 10)
    note.rect(5, 0, 5, 7, "#f0d070")
    note.rect(6, 1, 7, 2, "#f0d070")
    note.ellipse(3.5, 7.5, 2, 1.5, "#f0d070")
    note.outline("#3a2a1a")
    note.save("assets", "fx", "note.png")


# ---------------------------------------------------------------- title screen

def big_text(c, text, x, y, scale, fill_top, fill_bottom, edge="#1a0e06"):
    """Writes text with the game font's glyphs, scaled up, with a gradient fill and a thick outline."""
    import make_font
    layer = Canvas(c.w, c.h)
    cx = x
    for ch in text:
        if ch == " ":
            cx += (make_font.SPACE_WIDTH + 1) * scale
            continue
        rows = make_font.glyph_rows(ch)
        for gy, row in enumerate(rows):
            for gx, bit in enumerate(row):
                if bit == "#":
                    for sy in range(scale):
                        t = (gy * scale + sy) / (7 * scale)
                        layer.rect(cx + gx * scale, y + gy * scale + sy, cx + gx * scale + scale - 1, y + gy * scale + sy, mix(fill_top, fill_bottom, min(1, t)))
        cx += (len(rows[0]) + 1) * scale
    layer.outline(edge)
    layer.outline(edge)
    c.paste(layer, 0, 0)
    return cx - x


def text_width(text, scale):
    import make_font
    return sum(((make_font.SPACE_WIDTH if ch == " " else len(make_font.glyph_rows(ch)[0])) + 1) * scale for ch in text) - scale


def make_title():
    rng = random.Random(31)
    w, h = 180, 320
    c = Canvas(w, h, "#000000")
    c.gradient(0, 200, ["#1a1838", "#2e2450", "#5a3460", "#a04a50", "#e07848", "#f4b060"])
    for _ in range(50):
        c.px(rng.randint(0, w), rng.randint(0, 80), rng.choice(["#f4f0d8", "#a8a8c8", "#ffffff"]))
    for y in range(78, 100):   # crescent moon: the part of one disc not covered by another
        for x in range(136, 160):
            if math.hypot(x - 148, y - 89) <= 8 and math.hypot(x - 151, y - 87) > 7:
                c.px(x, y, "#f4ecc8")
    for base, height, colour in ((170, 36, "#3a2a48"), (190, 30, "#2a2038"), (214, 24, "#1c1628")):
        phase = rng.random() * 9
        for x in range(w):
            top = int(base - height * (0.6 + 0.25 * math.sin(x / 7 + phase) + 0.15 * math.sin(x / 3.1 + phase)))
            for y in range(top, h):
                c.px(x, y, colour)
    # the Major Oak, a dark giant against the sky
    oak = "#120e1a"
    c.rect(80, 150, 98, 262, oak)
    for x0, y0, x1, y1 in ((84, 170, 50, 120), (94, 165, 130, 115), (88, 150, 90, 96), (70, 140, 40, 140), (98, 150, 140, 150)):
        c.line(x0, y0, x1, y1, oak, 4)
    for _ in range(60):
        c.ellipse(rng.randint(28, 152), rng.randint(70, 150), rng.randint(8, 18), rng.randint(6, 12), oak)
    c.rect(0, 262, w, h, "#16121c")
    # campfire glow on the clearing
    for r, a in ((60, 30), (42, 40), (26, 60)):
        c.ellipse(90, 286, r, r * 0.45, (240, 140, 60, a))
    c.rect(84, 288, 96, 290, "#4a2a18")
    c.line(83, 291, 97, 285, "#3a2014", 2)
    for i, colour in enumerate(("#c83a1a", "#f08a2a", "#f8d050", "#fff4c0")):
        c.ellipse(90, 284 - i, 5 - i, 6 - i * 1.4, colour)
    big_text(c, "OUTLAWS", (w - text_width("OUTLAWS", 3)) // 2, 18, 3, "#fff0a0", "#d08a20")
    big_text(c, "of Sherwood", (w - text_width("of Sherwood", 2)) // 2, 46, 2, "#f0e6cc", "#b8a070")
    c.save("assets", "ui", "title.png")


def make_icon():
    """The app icon: Robin's sprite on a round greenwood badge, 192x192 (Android's largest launcher size)."""
    small = Canvas(48, 48)
    small.ellipse(23.5, 23.5, 23.5, 23.5, "#2a1e14")
    small.ellipse(23.5, 23.5, 22, 22, "#c8a860")
    small.gradient(0, 47, ["#f4c070", "#e07848", "#8a3a50"])
    for y in range(48):   # keep the gradient inside the badge only
        for x in range(48):
            if math.hypot(x - 23.5, y - 23.5) > 20.5:
                small.d[x, y] = (0, 0, 0, 0)
    ring = Canvas(48, 48)
    ring.ellipse(23.5, 23.5, 23.5, 23.5, "#2a1e14")
    ring.ellipse(23.5, 23.5, 22.5, 22.5, "#e0c070")
    ring.ellipse(23.5, 23.5, 21, 21, (0, 0, 0, 0))
    for y in range(48):
        for x in range(48):
            if math.hypot(x - 23.5, y - 23.5) <= 20.5:
                ring.d[x, y] = (0, 0, 0, 0)
    small.paste(ring, 0, 0)
    robin = Image.open(os.path.join(ROOT, "assets", "sprites", "robin.png"))
    small.img.alpha_composite(robin, (8, 6))
    icon = small.img.resize((192, 192), Image.NEAREST)
    icon.save(os.path.join(ROOT, "assets", "icon.png"))


def make_all():
    for name, fn in BACKDROPS.items():
        fn().save("assets", "backdrops", name + ".png")
    make_map().save("assets", "map", "map.png")
    make_ui()
    make_nodes()
    make_items()
    make_fx()
    make_title()
    make_icon()


if __name__ == "__main__":
    make_all()
    print("wrote %d backdrops, the map and UI frames" % len(BACKDROPS))
