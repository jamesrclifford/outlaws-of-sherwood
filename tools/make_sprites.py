"""Generates the 32x32 pixel-art unit sprites in assets/sprites/.

Every sprite is drawn from code so the art stays consistent and easy to tweak:
a shared humanoid body (head, torso, arms, legs) is dressed per character with
clothes, headgear and a signature prop. All sprites face right; the game flips
enemies so the two sides face each other.

Usage: python3 tools/make_sprites.py [--sheet out.png]
"""
import os
import sys
from PIL import Image, ImageDraw

SIZE = 32
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sprites")
OUTLINE = (26, 20, 16, 255)


def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (255,)


class Sprite:
    def __init__(self):
        self.img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        self.d = self.img.load()

    def px(self, x, y, c):
        if 0 <= x < SIZE and 0 <= y < SIZE:
            self.d[x, y] = hexc(c) if isinstance(c, str) else c

    def rect(self, x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.px(x, y, c)

    def line(self, x0, y0, x1, y1, c):
        steps = max(abs(x1 - x0), abs(y1 - y0), 1)
        for i in range(steps + 1):
            self.px(round(x0 + (x1 - x0) * i / steps), round(y0 + (y1 - y0) * i / steps), c)

    def outline(self):
        """Dark 1px outline around the figure, the classic pixel-art look."""
        solid = {(x, y) for x in range(SIZE) for y in range(SIZE) if self.d[x, y][3] > 0}
        for x, y in solid:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < SIZE and 0 <= ny < SIZE and (nx, ny) not in solid:
                    self.d[nx, ny] = OUTLINE

    def save(self, name):
        self.outline()
        self.img.save(os.path.join(OUT, name + ".png"))
        return self.img


def humanoid(s, skin, tunic, tunic_dark, legs, boots, belt=None, tall=0, wide=0, fat=0):
    """Draws a standing figure facing right. tall raises the head, wide broadens shoulders, fat adds a belly."""
    top = 6 - tall
    # legs and boots
    s.rect(13 - wide // 2, 22, 15, 28, legs)
    s.rect(17, 22, 19 + wide // 2, 28, legs)
    s.rect(12 - wide // 2, 29, 15, 31, boots)
    s.rect(17, 29, 20 + wide // 2, 31, boots)
    # torso (left half lit, right half shaded)
    s.rect(12 - wide, top + 8, 20 + wide + fat, 21, tunic)
    s.rect(17 + fat, top + 8, 20 + wide + fat, 21, tunic_dark)
    if fat:
        s.rect(20, top + 12, 20 + wide + fat, 20, tunic_dark)
    if belt:
        s.rect(12 - wide, 19, 20 + wide + fat, 19, belt)
    # arms
    s.rect(10 - wide, top + 9, 11 - wide, 18, tunic_dark)
    s.rect(21 + wide + fat, top + 9, 22 + wide + fat, 17, tunic)
    s.rect(10 - wide, 19, 11 - wide, 19, skin)
    s.rect(21 + wide + fat, 18, 22 + wide + fat, 18, skin)
    # head
    s.rect(13, top, 19, top + 6, skin)
    s.px(18, top + 3, "#1a1410")  # eye, looking right
    s.px(19, top + 5, "#a8644a")  # mouth corner
    s.rect(15, top + 7, 17, top + 7, skin)  # neck
    return top


def bow(s, x=24, y0=7, y1=27, wood="#7a4a22"):
    """A longbow held upright: a pale string, with the wooden stave bowed out in front of it."""
    s.line(x, y0, x, y1, "#e8e0c8")
    span = y1 - y0
    for y in range(y0, y1 + 1):
        t = (y - y0) / span
        bend = round(3 * (1 - (2 * t - 1) ** 2))
        s.px(x + bend, y, wood)
        s.px(x + bend + 1, y, "#5a3418") if 0.2 < t < 0.8 else None


def quiver(s, top):
    s.rect(9, top + 8, 10, top + 15, "#6b3d1e")
    for x, c in ((9, "#e8e0c8"), (10, "#c0392b")):
        s.px(x, top + 7, c)


def staff(s, x=23, y0=1, y1=31, wood="#8a5a2b"):
    s.rect(x, y0, x, y1, wood)
    s.px(x, y0, "#5a3a1a")
    s.px(x, y1, "#5a3a1a")


def sword(s, hx=22, hy=18, blade="#d8dde3"):
    s.line(hx + 1, hy - 1, hx + 6, hy - 6, blade)
    s.rect(hx, hy - 2, hx + 1, hy, "#c9a227")  # crossguard
    s.px(hx - 1, hy + 1, "#6b3d1e")


def robin_body():
    s = Sprite()
    top = humanoid(s, "#e0ac82", "#3f7d3a", "#2d5a29", "#5a4a2a", "#4a2f18", belt="#6b3d1e")
    s.rect(12, top - 1, 19, top + 1, "#3f7d3a")      # hood
    s.rect(11, top, 13, top + 7, "#2d5a29")           # hood falls behind
    s.rect(14, top - 2, 17, top - 2, "#3f7d3a")
    s.line(17, top - 1, 21, top - 4, "#c0392b")       # red feather
    s.rect(14, top + 6, 18, top + 6, "#8a5a2b")       # short beard
    return s, top


def robin():
    s, top = robin_body()
    quiver(s, top)
    bow(s)
    return s.save("robin")


def robin_staff():
    """Robin with the oak staff he cut for the bout on the bridge."""
    s, top = robin_body()
    staff(s, x=24, y0=2)
    return s.save("robin_staff")


def little_john():
    s = Sprite()
    top = humanoid(s, "#d9a07a", "#7a5a3a", "#5a4228", "#4a3a2a", "#3a2614", belt="#3a2614", tall=3, wide=2)
    s.rect(13, top - 1, 19, top, "#6b4423")            # brown hair
    s.rect(12, top, 12, top + 4, "#6b4423")
    s.rect(14, top + 5, 19, top + 8, "#6b4423")        # big beard
    s.px(18, top + 3, "#1a1410")
    staff(s, x=25, y0=0)
    return s.save("little_john")


def will():
    s = Sprite()
    top = humanoid(s, "#ecbd96", "#b5302a", "#8a221d", "#3a3a4a", "#2a1a10", belt="#c9a227")
    s.rect(13, top - 1, 19, top + 1, "#e8c45a")        # blond hair
    s.rect(12, top - 2, 19, top - 1, "#b5302a")        # scarlet cap
    s.rect(19, top - 1, 21, top - 1, "#b5302a")        # cap brim
    s.px(16, top - 3, "#ffffff")                        # small white plume
    sword(s, hx=22, hy=17)
    return s.save("will")


def tuck():
    s = Sprite()
    top = humanoid(s, "#e8b090", "#7a5636", "#5c3f25", "#5c3f25", "#3a2614", belt="#d8c99a", fat=3)
    s.rect(13, top, 19, top + 1, "#e8b090")            # bald pate
    s.rect(12, top + 1, 13, top + 4, "#8a7a6a")        # tonsure ring
    s.rect(19, top + 2, 19, top + 3, "#8a7a6a")
    s.rect(12, 22, 20, 28, "#7a5636")                   # habit hangs to the ankles
    s.rect(17, 22, 20, 28, "#5c3f25")
    s.px(14, 20, "#d8c99a")                             # rope knot
    s.px(14, 21, "#d8c99a")
    s.rect(25, 12, 26, 18, "#4a2f18")                   # blackthorn cudgel
    s.rect(24, 10, 27, 12, "#3a2614")
    return s.save("tuck")


def merry_man():
    s = Sprite()
    top = humanoid(s, "#d8a47c", "#6a7a3a", "#4f5c2a", "#5a4a32", "#3a2614", belt="#6b3d1e")
    s.rect(12, top + 6, 20, top + 8, "#4f5c2a")        # hood down around the shoulders
    s.rect(13, top - 1, 19, top, "#3a2a1a")            # dark hair
    s.line(23, 2, 23, 31, "#8a5a2b")                   # spear shaft
    s.rect(22, 0, 24, 2, "#c8ccd2")                     # spear head
    s.px(23, 0, "#e8ecf2")
    return s.save("merry_man")


def sheriff_soldier(s, top):
    s.rect(12, top - 1, 20, top, "#7d8590")             # kettle helmet
    s.rect(11, top + 1, 21, top + 1, "#5d6570")         # brim
    s.rect(13, top + 8, 19, 20, "#c9a227")               # Sheriff's tabard (gold on red)
    s.rect(17, top + 8, 19, 20, "#a8861f")
    s.rect(15, top + 10, 16, top + 13, "#8a1f1f")       # red device


def man_at_arms():
    s = Sprite()
    top = humanoid(s, "#d9a582", "#8a9099", "#6a7079", "#5a5f66", "#2a2a2a", belt="#3a2614")
    sheriff_soldier(s, top)
    sword(s, hx=22, hy=16)
    s.rect(20, 14, 24, 21, "#8a1f1f")                   # shield
    s.rect(21, 15, 23, 20, "#c9a227")
    s.rect(22, 15, 22, 20, "#8a1f1f")
    return s.save("man_at_arms")


def crossbowman():
    s = Sprite()
    top = humanoid(s, "#dcaa86", "#8a9099", "#6a7079", "#5a5f66", "#2a2a2a", belt="#3a2614")
    sheriff_soldier(s, top)
    s.rect(19, 16, 28, 16, "#6b3d1e")                   # crossbow stock
    s.line(25, 12, 25, 20, "#4a4f55")                   # steel bow
    s.line(25, 12, 27, 16, "#e8e0c8")
    s.line(25, 20, 27, 16, "#e8e0c8")
    s.rect(9, top + 9, 10, top + 14, "#6b3d1e")         # bolt case
    return s.save("crossbowman")


def knight():
    s = Sprite()
    # horse
    s.rect(4, 17, 24, 24, "#e6e1d6")
    s.rect(4, 22, 24, 24, "#c9c3b5")
    s.rect(23, 11, 27, 18, "#e6e1d6")                   # neck and head
    s.rect(26, 12, 29, 15, "#e6e1d6")
    s.px(27, 12, "#1a1410")
    s.rect(22, 10, 24, 15, "#8a8a8a")                   # mane
    s.rect(2, 17, 4, 23, "#8a8a8a")                     # tail
    for x in (6, 9, 19, 22):
        s.rect(x, 25, x + 1, 30, "#c9c3b5")
        s.rect(x, 31, x + 1, 31, "#3a3a3a")
    s.rect(5, 17, 22, 20, "#2a4a8a")                    # blue caparison
    s.rect(5, 20, 22, 21, "#d8d8d8")
    # rider
    s.rect(12, 8, 17, 16, "#9aa2ac")                     # mail
    s.rect(15, 8, 17, 16, "#7a828c")
    s.rect(12, 9, 17, 13, "#2a4a8a")                     # surcoat
    s.rect(13, 10, 14, 12, "#d8d8d8")
    s.rect(12, 1, 17, 7, "#b0b8c2")                      # great helm
    s.rect(15, 1, 17, 7, "#8a929c")
    s.rect(14, 4, 17, 4, "#1a1410")                      # eye slit
    s.rect(14, 0, 15, 0, "#c0392b")                      # plume
    s.line(13, 15, 31, 9, "#8a5a2b")                     # lance
    s.px(31, 9, "#d8dde3")
    s.px(30, 9, "#d8dde3")
    return s.save("knight")


def forester():
    s = Sprite()
    top = humanoid(s, "#d6a07a", "#5a6a4a", "#43503a", "#4a4232", "#2e2216", belt="#3a2614")
    s.rect(12, top - 1, 19, top + 1, "#7a6a4a")         # leather hood
    s.rect(11, top, 12, top + 8, "#5f5238")
    s.rect(15, top - 2, 16, top - 2, "#7a6a4a")
    bow(s, x=24, y0=9, y1=25, wood="#5a3a1a")
    s.rect(8, 22, 11, 27, "#9a9a8a")                    # coiled net at the hip
    for y in (23, 25):
        s.rect(8, y, 11, y, "#6a6a5a")
    return s.save("forester")


def tax_collector():
    s = Sprite()
    top = humanoid(s, "#f0c8a8", "#6a2a7a", "#4f1e5c", "#3a2a3a", "#1a1414", belt="#c9a227", fat=2)
    s.rect(12, top - 2, 20, top, "#2a1a2a")             # tall hat
    s.rect(11, top + 1, 21, top + 1, "#2a1a2a")
    s.rect(13, top - 1, 19, top - 1, "#c9a227")         # gold band
    s.rect(14, top + 5, 18, top + 5, "#c88870")         # jowls
    s.rect(23, 15, 27, 20, "#c9a227")                    # money bag
    s.rect(24, 14, 26, 14, "#a8861f")
    s.px(25, 17, "#7a5a10")
    s.rect(17, top + 9, 18, top + 11, "#e8e0c8")        # ledger
    return s.save("tax_collector")


def hound():
    s = Sprite()
    s.rect(6, 17, 22, 23, "#8a6a4a")                     # body
    s.rect(6, 21, 22, 23, "#6a4f36")
    s.rect(20, 13, 26, 19, "#8a6a4a")                    # head
    s.rect(25, 16, 29, 18, "#8a6a4a")                    # muzzle
    s.px(29, 16, "#1a1410")                              # nose
    s.px(24, 15, "#1a1410")                              # eye
    s.rect(20, 12, 22, 15, "#5a4028")                    # ear
    s.rect(9, 18, 18, 19, "#c9a227")                     # Sheriff's livery cloth
    s.rect(9, 18, 18, 18, "#8a1f1f")
    s.rect(20, 19, 23, 19, "#8a1f1f")                    # collar
    for x in (7, 10, 17, 20):
        s.rect(x, 24, x + 1, 30, "#6a4f36")
        s.rect(x, 31, x + 1, 31, "#3a2a1a")
    s.line(5, 18, 2, 14, "#8a6a4a")                      # tail up
    return s.save("hound")


def guy():
    s = Sprite()
    top = humanoid(s, "#d8b094", "#2a2a2e", "#1a1a1e", "#2a2a2e", "#111111", belt="#8a1f1f", tall=1)
    s.rect(12, top - 1, 19, top + 1, "#14100c")          # black hair
    s.rect(12, top + 2, 13, top + 5, "#14100c")
    s.rect(16, top + 6, 19, top + 6, "#14100c")          # dark stubble
    # horse-hide cloak from the ballad, with its mane on the shoulder
    s.rect(8, top + 8, 12, 27, "#8a6a4a")
    s.rect(8, top + 8, 9, 27, "#6a4f36")
    s.px(10, 14, "#e6e1d6")
    s.px(9, 20, "#e6e1d6")
    s.rect(9, top + 6, 14, top + 7, "#3a2a1a")
    s.rect(13, top + 10, 19, top + 10, "#8a1f1f")       # red sash
    sword(s, hx=22, hy=15, blade="#e8ecf2")
    s.line(29, 9, 30, 8, "#e8ecf2")                      # longer blade
    return s.save("guy")


def alan():
    s = Sprite()
    top = humanoid(s, "#ecc0a0", "#3a5aa0", "#2a4278", "#e0c050", "#5a3a20", belt="#e0c050")
    s.rect(13, top - 1, 19, top + 2, "#a0642a")         # auburn curls
    s.rect(12, top + 1, 13, top + 6, "#a0642a")
    s.rect(12, top - 3, 18, top - 1, "#e0c050")         # floppy yellow cap
    s.rect(18, top - 2, 20, top - 2, "#e0c050")
    s.line(14, top - 3, 10, top - 7, "#c0392b")         # long red feather
    s.rect(16, top + 9, 18, top + 11, "#e0c050")       # motley diamond on the tunic
    # lute held across the body
    for y in range(15, 22):
        w = 3 - abs(y - 18) // 2
        s.rect(21 - w, y, 23 + w, y, "#b07a3a")
    s.rect(22, 17, 22, 18, "#3a2614")                   # sound hole
    s.line(24, 15, 28, 9, "#7a4a22")                    # neck
    s.rect(27, 8, 29, 9, "#5a3418")                     # pegbox
    return s.save("alan")


def bishop():
    s = Sprite()
    top = humanoid(s, "#e8c0a0", "#e8e4dc", "#c8c2b8", "#7a3a8a", "#3a2a3a", belt="#c9a227", fat=2)
    s.rect(12, 22, 20, 28, "#e8e4dc")                   # long white robe
    s.rect(17, 22, 20, 28, "#c8c2b8")
    s.rect(15, top + 8, 16, 28, "#7a3a8a")              # purple stole
    s.px(15, 24, "#c9a227")
    s.rect(14, top - 4, 18, top - 1, "#e8e4dc")         # mitre
    s.rect(15, top - 6, 17, top - 4, "#e8e4dc")
    s.rect(16, top - 6, 16, top - 1, "#c9a227")
    s.rect(14, top - 1, 18, top - 1, "#c9a227")
    s.line(24, 6, 24, 30, "#c9a227")                    # crozier
    s.rect(24, 4, 26, 5, "#c9a227")
    s.px(27, 6, "#c9a227")
    s.px(26, 7, "#c9a227")
    s.rect(18, 16, 21, 19, "#8a6a2a")                   # a fat purse
    s.px(19, 15, "#c9a227")
    return s.save("bishop")


def sheriff():
    s = Sprite()
    top = humanoid(s, "#ecc4a4", "#8a1f1f", "#661616", "#2a2a2e", "#111111", belt="#c9a227", fat=2)
    s.rect(12, top - 1, 19, top + 1, "#3a2a1a")         # oiled hair
    s.rect(15, top + 6, 19, top + 6, "#3a2a1a")         # pointed beard
    s.px(19, top + 7, "#3a2a1a")
    s.rect(11, top - 3, 20, top - 1, "#1a1a1e")         # black velvet hat
    s.rect(18, top - 4, 22, top - 3, "#1a1a1e")
    s.line(13, top - 3, 10, top - 7, "#e8ecf2")         # white plume
    s.rect(12, top + 8, 20, top + 9, "#c9a227")         # chain of office
    s.px(16, top + 10, "#c9a227")
    s.px(16, top + 11, "#e8d070")
    s.rect(8, top + 9, 10, 26, "#1a1a1e")               # black cloak behind
    s.line(23, 18, 23, 28, "#c9a227")                   # staff of office
    s.rect(22, 17, 24, 17, "#e8d070")
    return s.save("sheriff")


def monk():
    s = Sprite()
    top = humanoid(s, "#ecc4a4", "#3a3a40", "#26262c", "#3a3a40", "#1a1414", belt="#d8c99a", fat=1)
    s.rect(12, top - 1, 19, top + 1, "#3a3a40")         # black cowl up
    s.rect(11, top, 13, top + 7, "#26262c")
    s.rect(12, 22, 20, 28, "#3a3a40")                   # habit to the ankles
    s.rect(17, 22, 20, 28, "#26262c")
    s.px(14, 20, "#d8c99a")
    s.px(14, 21, "#d8c99a")
    s.rect(21, 18, 25, 23, "#8a6a2a")                   # a heavy purse he swears is empty
    s.rect(22, 17, 24, 17, "#6a4a1a")
    s.px(23, 20, "#c9a227")
    return s.save("monk")


def tradesman():
    s = Sprite()
    top = humanoid(s, "#d9a07a", "#8a6a3a", "#6a5028", "#4a3a2a", "#2e2216", belt="#3a2614", wide=1)
    s.rect(13, top - 1, 19, top, "#8a4a2a")             # ginger hair
    s.rect(14, top + 5, 19, top + 7, "#8a4a2a")         # bushy beard
    s.rect(13, top + 10, 19, 24, "#a8805a")             # leather apron
    s.rect(13, top + 10, 19, top + 10, "#6a4a2a")
    s.rect(11, top - 2, 19, top - 1, "#5a6a3a")         # flat cap
    s.rect(24, 4, 24, 30, "#7a5028")                    # crab-tree staff
    s.rect(23, 4, 25, 6, "#5a3418")
    return s.save("tradesman")


def beggar():
    s = Sprite()
    top = humanoid(s, "#d6a07a", "#8a8070", "#6a6252", "#6a6252", "#4a3a2a", belt="#5a4a3a")
    s.rect(12, top - 1, 19, top + 1, "#9a9a92")         # grey straggly hair
    s.rect(14, top + 5, 19, top + 8, "#b4b4aa")         # long grey beard
    for x, y in ((13, 14), (18, 17), (14, 20), (19, 12)):
        s.rect(x, y, x + 1, y + 1, "#a08a6a")           # patches
    s.rect(8, 13, 11, 20, "#7a6a4a")                    # meal-bag over the shoulder
    s.line(11, 12, 18, top + 8, "#5a4a3a")
    s.rect(24, 3, 24, 31, "#6a4a2a")                    # long pikestaff
    s.px(24, 2, "#8a8a8a")
    return s.save("beggar")


def pirate():
    s = Sprite()
    top = humanoid(s, "#d8a47c", "#e8e4dc", "#c8c2b8", "#3a4a8a", "#2a1a10", belt="#a01e22")
    for y in range(top + 9, 21, 2):                     # striped shirt
        s.rect(12, y, 20, y, "#3a4a8a")
    s.rect(12, top - 2, 19, top, "#a01e22")             # red headscarf
    s.rect(10, top, 12, top + 2, "#a01e22")
    s.rect(14, top + 5, 19, top + 6, "#2a1a10")         # black moustache
    s.px(18, top + 3, "#1a1410")
    s.rect(17, top + 2, 19, top + 2, "#1a1410")         # eyepatch band
    s.line(21, 18, 27, 12, "#d8dde3")                   # curved cutlass
    s.px(28, 12, "#d8dde3")
    s.rect(20, 17, 21, 18, "#c9a227")
    return s.save("pirate")


def king():
    s = Sprite()
    top = humanoid(s, "#e8bc98", "#e8e4dc", "#c8c2b8", "#6a6a74", "#2a2a2a", belt="#c9a227", tall=2, wide=1)
    s.rect(14, top + 10, 18, top + 11, "#a01e22")       # crusader cross on the surcoat
    s.rect(15, top + 9, 17, 18, "#a01e22")
    s.rect(13, top - 1, 19, top + 1, "#c87a3a")         # the Lionheart's red-gold hair
    s.rect(14, top + 5, 19, top + 7, "#c87a3a")         # and beard
    s.rect(13, top - 3, 19, top - 2, "#e0c050")         # crown
    for x in (13, 16, 19):
        s.px(x, top - 4, "#e0c050")
    s.px(16, top - 3, "#a01e22")
    s.rect(8, top + 8, 10, 27, "#6a2a8a")               # purple cloak
    sword(s, hx=22, hy=16, blade="#e8ecf2")
    return s.save("king")


DRAWERS = [robin, robin_staff, little_john, will, tuck, alan, merry_man, man_at_arms, crossbowman, knight, forester, tax_collector, hound, bishop, guy, sheriff, monk, tradesman, beggar, pirate, king]


def contact_sheet(images, path, scale=5):
    cols = 4
    rows = (len(images) + cols - 1) // cols
    cell = SIZE * scale + 20
    sheet = Image.new("RGBA", (cols * cell, rows * (cell + 14)), (40, 52, 40, 255))
    draw = ImageDraw.Draw(sheet)
    for i, (name, img) in enumerate(images):
        x, y = (i % cols) * cell + 10, (i // cols) * (cell + 14) + 8
        sheet.alpha_composite(img.resize((SIZE * scale, SIZE * scale), Image.NEAREST), (x, y))
        draw.text((x, y + SIZE * scale + 2), name, fill=(232, 224, 200, 255))
    sheet.save(path)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    images = [(f.__name__, f()) for f in DRAWERS]
    if "--sheet" in sys.argv:
        contact_sheet(images, sys.argv[sys.argv.index("--sheet") + 1])
    print("wrote %d sprites to %s" % (len(images), os.path.normpath(OUT)))
