"""Generates the game's pixel font as a BMFont (assets/fonts/outlaw.fnt + .png).

Glyphs are hand-drawn below: rows separated by spaces, '#' is ink, '.' is empty.
Row 0 is the top of a capital, row 6 sits on the baseline, rows 7-8 hold descenders.
Godot imports .fnt files directly; it draws at 1x for small sizes and whole multiples above.

Usage: python3 tools/make_font.py [--sample out.png]
"""
import os
import sys
from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "assets", "fonts")
BASE = 7          # pixels from the top of a line to the baseline
LINE = 11         # line height
SPACING = 1       # empty columns after each glyph

GLYPHS = {
    "A": ".##. #..# #..# #### #..# #..# #..#",
    "B": "###. #..# #..# ###. #..# #..# ###.",
    "C": ".##. #..# #... #... #... #..# .##.",
    "D": "###. #..# #..# #..# #..# #..# ###.",
    "E": "#### #... #... ###. #... #... ####",
    "F": "#### #... #... ###. #... #... #...",
    "G": ".##. #..# #... #.## #..# #..# .###",
    "H": "#..# #..# #..# #### #..# #..# #..#",
    "I": "### .#. .#. .#. .#. .#. ###",
    "J": "..## ...# ...# ...# #..# #..# .##.",
    "K": "#..# #..# #.#. ##.. #.#. #..# #..#",
    "L": "#... #... #... #... #... #... ####",
    "M": "#...# ##.## #.#.# #.#.# #...# #...# #...#",
    "N": "#..# ##.# ##.# #.## #.## #..# #..#",
    "O": ".##. #..# #..# #..# #..# #..# .##.",
    "P": "###. #..# #..# ###. #... #... #...",
    "Q": ".##. #..# #..# #..# #..# #.#. .#.#",
    "R": "###. #..# #..# ###. #.#. #..# #..#",
    "S": ".### #... #... .##. ...# ...# ###.",
    "T": "##### ..#.. ..#.. ..#.. ..#.. ..#.. ..#..",
    "U": "#..# #..# #..# #..# #..# #..# .##.",
    "V": "#...# #...# #...# #...# .#.#. .#.#. ..#..",
    "W": "#...# #...# #...# #.#.# #.#.# ##.## #...#",
    "X": "#...# #...# .#.#. ..#.. .#.#. #...# #...#",
    "Y": "#...# #...# .#.#. ..#.. ..#.. ..#.. ..#..",
    "Z": "#### ...# ..#. .#.. #... #... ####",
    "a": ".... .... .### #..# #..# #..# .###",
    "b": "#... #... ###. #..# #..# #..# ###.",
    "c": "... ... .## #.. #.. #.. .##",
    "d": "...# ...# .### #..# #..# #..# .###",
    "e": ".... .... .##. #..# #### #... .###",
    "f": "..# .#. ### .#. .#. .#. .#.",
    "g": ".... .... .### #..# #..# #..# .### ...# .##.",
    "h": "#... #... ###. #..# #..# #..# #..#",
    "i": "# . # # # # #",
    "j": "..# ... ..# ..# ..# ..# ..# ..# ##.",
    "k": "#... #... #..# #.#. ##.. #.#. #..#",
    "l": "#. #. #. #. #. #. .#",
    "m": "..... ..... ####. #.#.# #.#.# #.#.# #.#.#",
    "n": ".... .... ###. #..# #..# #..# #..#",
    "o": ".... .... .##. #..# #..# #..# .##.",
    "p": ".... .... ###. #..# #..# #..# ###. #... #...",
    "q": ".... .... .### #..# #..# #..# .### ...# ...#",
    "r": "... ... #.# ##. #.. #.. #..",
    "s": "... ... .## #.. .#. ..# ##.",
    "t": ".#. .#. ### .#. .#. .#. ..#",
    "u": ".... .... #..# #..# #..# #..# .###",
    "v": "..... ..... #...# #...# .#.#. .#.#. ..#..",
    "w": "..... ..... #...# #.#.# #.#.# #.#.# .#.#.",
    "x": "... ... #.# #.# .#. #.# #.#",
    "y": ".... .... #..# #..# #..# #..# .### ...# .##.",
    "z": ".... .... #### ..#. .#.. #... ####",
    "0": ".##. #..# #.## ##.# #..# #..# .##.",
    "1": ".#. ##. .#. .#. .#. .#. ###",
    "2": ".##. #..# ...# ..#. .#.. #... ####",
    "3": "###. ...# ...# .##. ...# ...# ###.",
    "4": "#..# #..# #..# #### ...# ...# ...#",
    "5": "#### #... ###. ...# ...# #..# .##.",
    "6": ".##. #... #... ###. #..# #..# .##.",
    "7": "#### ...# ..#. .#.. .#.. .#.. .#..",
    "8": ".##. #..# #..# .##. #..# #..# .##.",
    "9": ".##. #..# #..# .### ...# ...# .##.",
    "!": "# # # # # . #",
    "\"": "#.# #.#",
    "#": "..... .#.#. ##### .#.#. ##### .#.#.",
    "%": "##..# ##.#. ...#. ..#.. .#... .#.## #..##",
    "&": ".#.. #.#. .#.. #.#. #..# #.#. .#.#",
    "'": "# #",
    "(": ".# #. #. #. #. #. .#",
    ")": "#. .# .# .# .# .# #.",
    "*": "... #.# .#. #.#",
    "+": "... ... .#. ### .#.",
    ",": ". . . . . . # #",
    "-": "... ... ... ###",
    ".": ". . . . . . #",
    "/": "...# ...# ..#. .#.. .#.. #... #...",
    ":": ". . # . . . #",
    ";": ". . # . . . # #",
    "<": "... ..# .#. #.. .#. ..#",
    "=": "... ... ### ... ###",
    ">": "... #.. .#. ..# .#. #..",
    "?": ".##. #..# ...# ..#. .#.. .... .#..",
    "[": "## #. #. #. #. #. ##",
    "\\": "#... #... .#.. .#.. ..#. ...# ...#",
    "]": "## .# .# .# .# .# ##",
    "_": "... ... ... ... ... ... ... ###",
    "{": ".## .#. .#. #.. .#. .#. .##",
    "|": "# # # # # # # # #",
    "}": "##. .#. .#. ..# .#. .#. ##.",
    "^": ".#. #.#",
    "`": "#. .#",
    "~": ".... .... .#.# #.#.",
    "$": ".#. .## #.. .#. ..# ##. .#.",
    "@": ".###. #...# #.### #.#.# #.##. #.... .###.",
}
SPACE_WIDTH = 3


def glyph_rows(ch):
    return GLYPHS[ch].split(" ")


def build():
    chars = sorted(GLYPHS)
    cell_w = max(len(glyph_rows(c)[0]) for c in chars) + 1
    cols = 16
    rows = (len(chars) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell_w, rows * LINE), (0, 0, 0, 0))
    entries = []
    for i, ch in enumerate(chars):
        gr = glyph_rows(ch)
        w = len(gr[0])
        assert all(len(r) == w for r in gr), "ragged glyph %r" % ch
        x0, y0 = (i % cols) * cell_w, (i // cols) * LINE
        for y, row in enumerate(gr):
            for x, bit in enumerate(row):
                if bit == "#":
                    sheet.putpixel((x0 + x, y0 + y + 1), (255, 255, 255, 255))
        entries.append((ord(ch), x0, y0, w, LINE, 0, 0, w + SPACING))
    entries.append((32, 0, 0, 0, 0, 0, 0, SPACE_WIDTH + SPACING))
    os.makedirs(OUT, exist_ok=True)
    sheet.save(os.path.join(OUT, "outlaw.png"))
    lines = [
        'info face="Outlaw" size=8 bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=0,0',
        "common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0" % (LINE, BASE + 1, sheet.width, sheet.height),
        'page id=0 file="outlaw.png"',
        "chars count=%d" % len(entries),
    ]
    for cid, x, y, w, h, xo, yo, adv in sorted(entries):
        lines.append("char id=%d x=%d y=%d width=%d height=%d xoffset=%d yoffset=%d xadvance=%d page=0 chnl=15" % (cid, x, y, w, h, xo, yo, adv))
    open(os.path.join(OUT, "outlaw.fnt"), "w").write("\n".join(lines) + "\n")
    return sheet


def sample(path, text):
    scale = 4
    widths = {c: len(glyph_rows(c)[0]) + SPACING for c in GLYPHS}
    lines = text.split("\n")
    w = max(sum(widths.get(c, SPACE_WIDTH + SPACING) for c in l) for l in lines) + 4
    img = Image.new("RGBA", (w, LINE * len(lines) + 4), (42, 30, 20, 255))
    for li, line in enumerate(lines):
        x = 2
        for c in line:
            if c in GLYPHS:
                for y, row in enumerate(glyph_rows(c)):
                    for gx, bit in enumerate(row):
                        if bit == "#":
                            img.putpixel((x + gx, 2 + li * LINE + y + 1), (240, 230, 204, 255))
            x += widths.get(c, SPACE_WIDTH + SPACING)
    img.resize((img.width * scale, img.height * scale), Image.NEAREST).save(path)


if __name__ == "__main__":
    build()
    if "--sample" in sys.argv:
        sample(sys.argv[sys.argv.index("--sample") + 1],
               "ABCDEFGHIJKLMNOPQRSTUVWXYZ\nabcdefghijklmnopqrstuvwxyz\n0123456789 !\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~\n"
               "Robin Hood uses Bow Shot. Guy of Gisborne takes 12!\nDay 6   Gold 125   Supplies 20 (5 days)   Sheriff's plot 30%")
    print("wrote %d glyphs to %s" % (len(GLYPHS) + 1, os.path.normpath(OUT)))
