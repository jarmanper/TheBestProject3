"""Pixel textures for the props (small, painted with numpy, sampled nearest).

Each painter returns a Canvas. `get(name)` builds the Blender image once and caches it.
Colours follow the GDD palette (pxlib.PALETTE) plus a few material browns/greys.
"""
import math

import bpy
import numpy as np

from pxlib import Canvas, mix, rgb, shade

BLACK = rgb("101211")
INK = rgb("1E2120")
WHITE = rgb("E9E6D2")
CREAM = rgb("cream")
ORANGE = rgb("orange")
RED = rgb("red")
OLIVE = rgb("olive")
CONCRETE = rgb("concrete")
CARD = rgb("8C6B44")
CARD_DARK = rgb("6A5033")
TAPE = rgb("B59866")
YELLOW = rgb("C9A43A")
STEEL = rgb("8E9390")


def _metal(base, seed, w=32, h=32, scratches=10, grime=0.18, noise=0.06):
    c = Canvas(w, h, base, seed)
    c.noise(noise)
    c.speckle(0.04, shade(base, 0.82))
    c.speckle(0.015, shade(base, 1.2))
    c.streaks(scratches, shade(base, 1.25), 0.6, (2, 6), vertical=False)
    c.streaks(scratches // 2, shade(base, 0.7), 0.5, (3, 9), vertical=True)
    c.vgradient(1.0, 1.0 - grime)
    return c


def metal_olive():
    return _metal(OLIVE, 11)


def metal_grey():
    return _metal(rgb("5C625F"), 12)


def metal_dark():
    return _metal(rgb("2C312F"), 13, scratches=8, grime=0.1)


def metal_safe():
    return _metal(rgb("3B443E"), 14, scratches=6, grime=0.12)


def plastic_black():
    c = Canvas(16, 16, rgb("1B1E1D"), 21)
    c.noise(0.08)
    c.speckle(0.05, rgb("2A2E2C"))
    return c


def plastic_olive():
    c = Canvas(16, 16, rgb("4E5848"), 22)
    c.noise(0.06)
    c.speckle(0.05, rgb("3E463A"))
    return c


def plastic_yellow():
    c = Canvas(16, 16, YELLOW, 23)
    c.noise(0.07)
    c.speckle(0.06, shade(YELLOW, 0.8))
    c.vgradient(1.0, 0.82)
    return c


def plastic_beige():
    c = Canvas(16, 16, rgb("B3AB8E"), 24)
    c.noise(0.05)
    c.speckle(0.05, rgb("9E967A"))
    return c


def rubber():
    c = Canvas(8, 8, rgb("161717"), 25)
    c.noise(0.1)
    return c


def steel():
    c = Canvas(32, 32, STEEL, 26)
    c.row_noise(0.06)
    c.noise(0.04)
    c.speckle(0.03, rgb("6E726F"))
    c.streaks(6, rgb("5E6360"), 0.5, (3, 8))
    return c


def cardboard():
    c = Canvas(32, 32, CARD, 31)
    c.row_noise(0.05)
    c.noise(0.06)
    c.speckle(0.04, CARD_DARK)
    c.speckle(0.01, rgb("A7845A"))
    return c


def box_atlas():
    """64x64: [0,0] short side with tape tab, [32,0] long side with label + arrows,
    [0,32] top with tape seam (tape along u), [32,32] inside (dark)."""
    c = Canvas(64, 64, CARD, 32)
    c.row_noise(0.04)
    c.noise(0.06)
    c.speckle(0.04, CARD_DARK)
    # short side: tape tab coming down from the top seam
    c.rect(12, 0, 20, 7, TAPE)
    c.rect(12, 6, 20, 7, shade(TAPE, 0.85))
    c.edge_dark(0.0)
    # long side: shipping label and "this side up" arrows
    c.rect(36, 6, 50, 15, WHITE)
    for row in (8, 10, 12):
        c.rect(37, row, 48 - (row % 3), row + 1, rgb("4A4A44"))
    c.rect(51, 6, 53, 7, INK)
    for ax in (54, 59):
        c.rect(ax + 1, 7, ax + 2, 12, rgb("3C2A18"))
        c.rect(ax, 8, ax + 3, 9, rgb("3C2A18"))
    c.text(36, 20, "FRAGILE", rgb("4A3320"), alpha=0.5)
    c.rect(44, 0, 52, 3, TAPE)
    # top: tape along u through the middle
    c.rect(0, 44, 32, 52, TAPE)
    c.rect(0, 47, 32, 48, shade(TAPE, 0.7))
    c.noise(0.03, 44, 52, 0, 32)
    # inside
    c.rect(32, 32, 64, 64, rgb("5A452D"))
    c.noise(0.08, 32, 64, 32, 64)
    # box edges darker (each 32px cell)
    for cx in (0, 32):
        for cy in (0, 32):
            c.rect(cx, cy, cx + 32, cy + 1, CARD_DARK, 0.6)
            c.rect(cx, cy + 31, cx + 32, cy + 32, CARD_DARK, 0.6)
            c.rect(cx, cy, cx + 1, cy + 32, CARD_DARK, 0.6)
            c.rect(cx + 31, cy, cx + 32, cy + 32, CARD_DARK, 0.6)
    return c


def stock_box():
    """64x32 product stock box (the carriable Tool box): [0..32) side with a printed product
    panel, [32..64) top with tape."""
    c = Canvas(64, 32, rgb("97754B"), 33)
    c.row_noise(0.04)
    c.noise(0.05)
    c.rect(4, 6, 28, 22, CREAM)
    c.rect(4, 6, 28, 10, ORANGE)
    c.text(6, 7, "STOCK", WHITE)
    c.rect(6, 13, 26, 14, rgb("6B6B60"))
    c.rect(6, 16, 20, 17, rgb("6B6B60"))
    c.rect(22, 15, 26, 20, INK)
    c.text(5, 25, "12X", rgb("3C2A18"))
    c.rect(32, 12, 64, 20, TAPE)
    c.rect(32, 15, 64, 16, shade(TAPE, 0.7))
    for x0 in (0, 32):
        c.outline(x0, 0, x0 + 32, 32, CARD_DARK, 0.6)
    return c


def wood():
    c = Canvas(32, 16, rgb("85735A"), 41)
    c.row_noise(0.12)
    c.noise(0.05)
    for _ in range(5):
        y = int(c.rng.integers(0, 16))
        c.rect(0, y, 32, y + 1, rgb("5E5140"), 0.5)
    c.disc(9, 7, 1.5, rgb("4E4232"), 0.7)
    c.rect(0, 0, 32, 1, rgb("4A3F31"), 0.6)
    c.rect(0, 15, 32, 16, rgb("4A3F31"), 0.6)
    return c


def wire_grid():
    """Alpha-clipped wire mesh: 1px wires every 3px (coverage > 50% so mipmaps keep it)."""
    c = Canvas(24, 24, (0, 0, 0, 0), 42)
    wire = rgb("9DA39E")
    for i in range(0, 24, 3):
        c.rect(i, 0, i + 1, 24, wire)
        c.rect(0, i, 24, i + 1, wire)
    c.noise(0.08)
    return c


def mop_strands():
    c = Canvas(16, 16, rgb("A39E86"), 43)
    for x in range(16):
        c.rect(x, 0, x + 1, 16, shade(rgb("A39E86"), 0.75 + 0.35 * ((x * 7) % 5) / 4))
    c.vgradient(1.05, 0.55)
    c.speckle(0.08, rgb("5C5848"))
    return c


def wet_sign():
    """32x64 caution sign face."""
    c = Canvas(32, 64, YELLOW, 44)
    c.noise(0.04)
    c.outline(0, 0, 32, 64, INK)
    c.outline(1, 1, 31, 63, shade(YELLOW, 0.8))
    w = Canvas.text_width("CAUTION")
    c.text((32 - w) // 2 + 1, 5, "CAUTION", INK)
    # warning triangle with slipping figure
    for row in range(16):
        half = row * 0.7
        c.rect(16 - half, 14 + row, 16 + half + 1, 15 + row, INK)
    for row in range(2, 14):
        half = max(0, row * 0.7 - 2)
        c.rect(16 - half, 14 + row, 16 + half + 1, 15 + row, YELLOW)
    c.disc(17.5, 21.5, 1.3, INK)
    c.line(16, 23, 14, 27, INK)
    c.line(15, 25, 18, 24, INK)
    c.line(14, 27, 17, 28, INK)
    c.line(14, 27, 12, 28, INK)
    c.rect(11, 28, 22, 29, INK)
    w = Canvas.text_width("WET")
    c.text((32 - w) // 2 + 1, 38, "WET", INK)
    w = Canvas.text_width("FLOOR")
    c.text((32 - w) // 2 + 1, 45, "FLOOR", INK)
    c.vgradient(1.0, 0.85)
    return c


def newsprint():
    c = Canvas(32, 32, rgb("BDB7A0"), 45)
    c.noise(0.04)
    c.rect(2, 2, 30, 6, rgb("38382F"))
    c.rect(2, 7, 30, 8, rgb("6E6B5C"))
    c.rect(2, 10, 14, 19, rgb("6B6A60"))
    c.speckle(0.25, rgb("4C4B42"), 0.6, (2, 10, 14, 19))
    for y in range(10, 30, 2):
        c.rect(16, y, 30, y + 1, rgb("75725F"))
    for y in range(21, 30, 2):
        c.rect(2, y, 14, y + 1, rgb("75725F"))
    c.speckle(0.02, rgb("8B7A55"))
    return c


def paper_log():
    """Clipboard sheet: header, ruled temperature table with pencil entries."""
    c = Canvas(32, 32, rgb("D9D5BF"), 46)
    c.noise(0.03)
    c.text(2, 2, "TEMP", INK)
    c.rect(19, 3, 30, 6, rgb("8A8673"))
    for y in range(9, 31, 3):
        c.rect(1, y, 31, y + 1, rgb("8DA0A8"))
    c.rect(11, 9, 12, 31, rgb("A06060"))
    for i, y in enumerate(range(10, 23, 3)):
        c.rect(3, y + 1, 9, y + 2, rgb("3E3E3A"))
        c.rect(14, y + 1, 20 + (i * 3) % 7, y + 2, rgb("3E3E3A"))
    return c


def spill():
    """64x64 RGBA puddle (alpha blended): one connected pool of murky brown liquid with lobed,
    pixel-stepped edges, a few droplets, a lighter wet rim and a soft highlight band."""
    rng = np.random.default_rng(47)
    n = 64
    yy, xx = np.mgrid[0:n, 0:n] + 0.5
    field = np.zeros((n, n))
    for bx, by, br in [(32, 33, 15), (23, 27, 9), (41, 39, 10), (30, 43, 8), (42, 25, 8), (21, 38, 7)]:
        field += np.exp(-((xx - bx) ** 2 + (yy - by) ** 2) / (2 * br ** 2))
    for _ in range(6):
        a = rng.random() * 2 * math.pi
        d = 25 + rng.random() * 4
        bx, by = 32 + math.cos(a) * d, 32 + math.sin(a) * d
        field += 0.8 * np.exp(-((xx - bx) ** 2 + (yy - by) ** 2) / (2 * (1.3 + rng.random() * 0.6) ** 2))
    mask = field > 0.42
    c = Canvas(n, n, (0, 0, 0, 0), 47)
    depth = np.clip((field - 0.42) / 0.9, 0.0, 1.0)
    shallow, deep = rgb("54452C"), rgb("2B2416")
    for ch in range(3):
        c.px[..., ch] = np.where(mask, shallow[ch] * (1 - depth) + deep[ch] * depth, 0.0)
    c.px[..., 3] = np.where(mask, 0.62 + 0.25 * depth, 0.0)
    inner = np.roll(mask, 1, 0) & np.roll(mask, -1, 0) & np.roll(mask, 1, 1) & np.roll(mask, -1, 1)
    rim = mask & ~inner
    c.px[rim, :3] = rgb("6A5A3C")[:3]
    c.px[rim, 3] = 0.55
    return c


def scorch():
    n = 16
    yy, xx = np.mgrid[0:n, 0:n] + 0.5
    rng = np.random.default_rng(48)
    d = np.sqrt((xx - 8) ** 2 + ((yy - 8) * 1.2) ** 2) / 8 + (rng.random((n, n)) - 0.5) * 0.35
    c = Canvas(n, n, (0, 0, 0, 0), 48)
    a = np.clip(1.1 - d, 0, 0.9)
    c.px[..., :3] = rgb("0E0D0B")[:3]
    c.px[..., 3] = np.where(a > 0.15, a, 0)
    return c


def vending_panel():
    """64x128: rows 0-15 backlit header "SNACKS", rows 16-127 the lit product window."""
    c = Canvas(64, 128, rgb("101412"), 51)
    c.rect(0, 0, 64, 16, RED)
    c.noise(0.05, 0, 16)
    w = Canvas.text_width("SNACKS", scale=2)
    c.text((64 - w) // 2, 3, "SNACKS", WHITE, scale=2)
    # window: dim cream backlight gradient
    c.rect(0, 16, 64, 128, rgb("2B3029"))
    colors = [rgb("C2482F"), rgb("E0A23A"), rgb("D8D3A8"), rgb("5C8A4A"), rgb("3F6E9A"),
              rgb("E87932"), rgb("8C3A6B"), rgb("C9C04A")]
    rng = np.random.default_rng(52)
    for row in range(5):
        y = 20 + row * 21
        c.rect(2, y + 17, 62, y + 19, rgb("6E746F"))       # shelf lip
        for col in range(5):
            x = 4 + col * 12
            if rng.random() < 0.12:
                continue
            col_c = colors[int(rng.integers(0, len(colors)))]
            h = int(rng.integers(9, 15))
            c.rect(x, y + 17 - h, x + 9, y + 17, col_c)
            c.rect(x, y + 17 - h, x + 9, y + 18 - h, shade(col_c, 1.3))
            c.rect(x + 2, y + 17 - h + 3, x + 7, y + 17 - h + 5, WHITE, 0.7)
            c.dot(x + 4, y + 19, CREAM)                       # price tag
        c.line(3, y + 1, 61, y + 1, rgb("4A504B"))
    c.noise(0.05, 16, 128)
    c.vgradient(1.0, 0.75)
    c.outline(0, 16, 64, 128, rgb("0B0D0C"))
    return c


def vending_keypad():
    """16x32 selection panel: display, keypad, coin slot."""
    c = Canvas(16, 32, rgb("3A403D"), 53)
    c.noise(0.05)
    c.rect(2, 2, 14, 6, rgb("0F2A18"))
    c.text(3, 2, "A4", rgb("7BE08A"))
    for r in range(4):
        for k in range(3):
            c.rect(3 + k * 4, 9 + r * 3, 5 + k * 4, 11 + r * 3, CREAM)
    c.rect(6, 23, 10, 24, BLACK)
    c.rect(4, 27, 12, 30, BLACK)
    c.outline(0, 0, 16, 32, rgb("252927"))
    return c


def crt_screen():
    """32x24 green terminal screen (emissive)."""
    c = Canvas(32, 24, rgb("0B1A12"), 54)
    green = rgb("6FD08A")
    lines = ["SHIFT 3", "CAM 3 OK", "TEMP 38F", "> _"]
    for i, s in enumerate(lines):
        c.text(1, 2 + i * 6, s, green, alpha=0.9)
    for y in range(0, 24, 2):
        c.rect(0, y, 32, y + 1, rgb("000000"), 0.25)
    c.edge_dark(0.4, 2)
    return c


def clock_face():
    c = Canvas(16, 16, (0, 0, 0, 0), 55)
    c.rect(0, 0, 16, 16, rgb("3A3F3C"))
    c.disc(8, 8, 7, rgb("1C1F1E"))
    c.disc(8, 8, 6.2, rgb("D6D1B4"))
    for a in range(12):
        ang = a / 12 * 2 * math.pi
        c.dot(round(8 + math.sin(ang) * 5.2 - 0.5), round(8 - math.cos(ang) * 5.2 - 0.5), INK)
    c.line(8, 8, 8, 4, INK)
    c.line(8, 8, 11, 9, INK)
    c.dot(7, 8, RED)
    return c


def time_clock_body():
    """16x32 front of the punch clock below the face: label + card slot."""
    c = Canvas(16, 32, rgb("8F8C7A"), 56)
    c.noise(0.05)
    c.rect(2, 4, 14, 10, rgb("2A2E2C"))
    c.text(2, 4, "IN", rgb("7BE08A"))
    c.rect(3, 16, 13, 18, BLACK)
    c.rect(2, 22, 14, 28, rgb("6B685A"))
    c.text(3, 23, "OUT", WHITE, alpha=0.8)
    c.outline(0, 0, 16, 32, rgb("5C5A4E"))
    return c


def time_card():
    c = Canvas(8, 16, rgb("D3CDAF"), 57)
    for y in range(3, 16, 2):
        c.rect(1, y, 7, y + 1, rgb("9A947A"))
    c.rect(1, 1, 7, 2, RED)
    return c


def labels():
    """32x32 sticker atlas: [0,0,16,16] DANGER, [16,0,32,16] high-voltage bolt,
    [0,16,16,32] cream id plate, [16,16,32,32] hazard stripes."""
    c = Canvas(32, 32, WHITE, 58)
    c.rect(0, 0, 16, 6, RED)
    c.text(1, 1, "DNG", WHITE)
    c.rect(2, 8, 14, 9, INK)
    c.rect(2, 10, 12, 11, INK)
    c.rect(2, 12, 13, 13, INK)
    c.rect(16, 0, 32, 16, YELLOW)
    c.outline(16, 0, 32, 16, INK)
    bolt = [(25, 2), (21, 8), (24, 8), (21, 14), (27, 6), (24, 6), (27, 2)]
    for (x0, y0), (x1, y1) in zip(bolt, bolt[1:]):
        c.line(x0, y0, x1, y1, INK)
    c.rect(23, 4, 25, 9, INK)
    c.rect(0, 16, 16, 32, rgb("C9C3A2"))
    c.outline(0, 16, 16, 32, rgb("6B6754"))
    c.text(2, 18, "NO", INK)
    c.text(2, 25, "417", INK)
    for y in range(16, 32):
        for x in range(16, 32):
            c.dot(x, y, YELLOW if ((x + y) // 3) % 2 == 0 else INK)
    return c


def hazard():
    c = Canvas(16, 16, YELLOW, 59)
    for y in range(16):
        for x in range(16):
            if ((x + y) // 4) % 2 == 1:
                c.dot(x, y, INK)
    c.noise(0.06)
    return c


def baler_chamber():
    """32x32 grille over compressed cardboard."""
    c = Canvas(32, 32, rgb("1A1B18"), 60)
    for y in range(4, 30, 3):
        tone = CARD if (y // 3) % 2 == 0 else CARD_DARK
        c.rect(2, y, 30, y + 2, shade(tone, 0.7 + 0.2 * ((y * 5) % 3) / 2))
    c.noise(0.1)
    for x in range(0, 32, 5):
        c.rect(x, 0, x + 2, 32, rgb("5F6662"))
        c.rect(x, 0, x + 1, 32, rgb("7C837E"))
    c.rect(0, 0, 32, 2, rgb("4C524F"))
    c.rect(0, 30, 32, 32, rgb("4C524F"))
    return c


def control_box():
    """16x16 baler control panel: red stop, green start, label."""
    c = Canvas(16, 16, rgb("4D5550"), 61)
    c.noise(0.05)
    c.disc(5, 5, 2.6, RED)
    c.dot(4, 4, rgb("E07060"))
    c.disc(11, 5, 2.2, rgb("3E8A4A"))
    c.rect(2, 10, 14, 14, WHITE)
    c.rect(3, 11, 12, 12, INK)
    c.outline(0, 0, 16, 16, rgb("2E3330"))
    return c


def laminate():
    c = Canvas(32, 32, rgb("A8A48C"), 62)
    c.noise(0.04)
    c.speckle(0.08, rgb("948F76"))
    c.ring(20, 12, 3.2, 4.2, rgb("7A6A4A"), 0.4)
    c.speckle(0.01, rgb("6B6550"))
    return c


def laminate_dark():
    c = Canvas(32, 32, rgb("5F5F52"), 63)
    c.noise(0.04)
    c.speckle(0.08, rgb("54544A"))
    return c


def fabric_dark():
    c = Canvas(16, 16, rgb("2C3036"), 64)
    for y in range(16):
        for x in range(16):
            if (x + y) % 2 == 0:
                c.dot(x, y, rgb("33383F"))
    c.noise(0.06)
    return c


def hardboard():
    c = Canvas(16, 16, rgb("7A5F3E"), 65)
    c.noise(0.06)
    c.speckle(0.1, rgb("6A5235"))
    return c


def brass():
    c = Canvas(8, 8, rgb("A68C4C"), 66)
    c.noise(0.1)
    c.dot(2, 2, rgb("D2B86E"))
    return c


def key_board():
    """32x24 key board with "KEYS" header."""
    c = Canvas(32, 24, rgb("C4BB97"), 67)
    c.noise(0.04)
    c.outline(0, 0, 32, 24, rgb("6B5A3E"))
    c.outline(1, 1, 31, 23, rgb("8A7A58"))
    w = Canvas.text_width("KEYS")
    c.text((32 - w) // 2 + 1, 3, "KEYS", INK)
    c.rect(4, 10, 28, 11, rgb("8A7A58"))
    for x in (8, 16, 24):
        c.text(x - 1, 17, "", INK)
    return c


def peg_board():
    c = Canvas(16, 16, rgb("6B6B60"), 68)
    c.noise(0.05)
    for y in range(2, 16, 4):
        for x in range(2, 16, 4):
            c.dot(x, y, rgb("2A2C28"))
    return c


def orange_plastic():
    c = Canvas(16, 16, rgb("D46A2C"), 69)
    c.noise(0.06)
    c.speckle(0.05, rgb("B4592A"))
    return c


def label_roll():
    """16x16: cream labels with an orange stripe edge (wraps around the roll)."""
    c = Canvas(16, 16, rgb("E2DDC4"), 70)
    c.rect(0, 0, 16, 2, ORANGE)
    c.rect(0, 14, 16, 16, ORANGE)
    for x in range(0, 16, 4):
        c.rect(x, 2, x + 1, 14, rgb("BEB89E"))
    return c


def cutter_body():
    """16x16 box-cutter body: yellow with black ribbed grip on the lower half."""
    c = Canvas(16, 16, rgb("D8A92E"), 71)
    c.noise(0.05)
    for y in range(8, 16, 2):
        c.rect(0, y, 16, y + 1, rgb("1E1E1C"))
    c.rect(0, 0, 16, 1, rgb("A8821F"))
    return c


def walkie():
    """16x32 walkie-talkie front: grille, display, orange PTT band."""
    c = Canvas(16, 32, rgb("1C1F1E"), 72)
    c.noise(0.06)
    for y in range(4, 16, 2):
        for x in range(3, 13, 2):
            c.dot(x, y, rgb("070808"))
    c.rect(3, 18, 13, 22, rgb("1F3A28"))
    c.rect(4, 19, 9, 20, rgb("7BE08A"), 0.8)
    c.rect(0, 25, 16, 27, ORANGE)
    c.outline(0, 0, 16, 32, rgb("2C302E"))
    return c


def products():
    """64x64 product label atlas, 16x16 cells:
    row 0: cereal box fronts (red, cream, orange, olive); row 1: snack boxes;
    row 2: can labels; row 3: bottle labels."""
    c = Canvas(64, 64, CREAM, 73)
    fronts = [rgb("B8402E"), rgb("D8D3A8"), rgb("E08A35"), rgb("6E7E52")]
    for i, col in enumerate(fronts):
        x = i * 16
        c.rect(x, 0, x + 16, 16, col)
        c.rect(x + 2, 2, x + 14, 6, WHITE if i != 1 else RED)
        c.disc(x + 8, 11, 3, rgb("E6C35A") if i != 2 else rgb("8A3A2A"))
        c.rect(x, 15, x + 16, 16, shade(col, 0.7))
    snacks = [rgb("3E6E9A"), rgb("C7B53A"), rgb("9A3A6B"), rgb("D46A2C")]
    for i, col in enumerate(snacks):
        x = i * 16
        c.rect(x, 16, x + 16, 32, col)
        c.rect(x + 3, 19, x + 13, 24, WHITE)
        c.rect(x + 4, 21, x + 12, 22, INK)
        c.rect(x + 2, 27, x + 14, 29, shade(col, 1.3))
    cans = [rgb("B93B32"), rgb("3E7A4A"), rgb("C9C3A2"), rgb("3F5E8A")]
    for i, col in enumerate(cans):
        x = i * 16
        c.rect(x, 32, x + 16, 48, col)
        c.rect(x, 32, x + 16, 34, STEEL)
        c.rect(x, 46, x + 16, 48, STEEL)
        c.rect(x, 38, x + 16, 42, WHITE if i != 2 else RED)
    bottles = [rgb("4B7A3A"), rgb("7A3A2A"), rgb("2E4E7A"), rgb("C9A43A")]
    for i, col in enumerate(bottles):
        x = i * 16
        c.rect(x, 48, x + 16, 64, shade(col, 0.6))
        c.rect(x, 53, x + 16, 60, CREAM)
        c.rect(x, 55, x + 16, 57, col)
    c.noise(0.04)
    return c


def orange_fabric():
    c = Canvas(16, 16, ORANGE, 74)
    c.noise(0.05)
    c.row_noise(0.05)
    for x in (4, 11):
        c.rect(x, 0, x + 1, 16, shade(ORANGE, 0.82), 0.7)
    return c


def glove():
    c = Canvas(16, 16, rgb("232726"), 75)
    c.noise(0.08)
    c.speckle(0.06, rgb("2E3331"))
    c.rect(0, 7, 16, 8, rgb("161918"))
    return c


def water():
    c = Canvas(8, 8, rgb("2C2D24"), 76)
    c.noise(0.06)
    c.dot(2, 3, rgb("4A4A3A"))
    return c


def bag_black():
    c = Canvas(16, 16, rgb("141716"), 77)
    c.noise(0.05)
    c.streaks(7, rgb("2E3331"), 0.8, (3, 8))
    return c


def metal_light():
    """Light grey hardware (hooks, clips, hinges)."""
    return _metal(rgb("8A908C"), 78, w=16, h=16, scratches=3, grime=0.05)


def flashlight_body():
    """16x16 black flashlight: knurled grip rows, button."""
    c = Canvas(16, 16, rgb("1A1C1C"), 79)
    for y in range(0, 16, 2):
        c.rect(0, y, 16, y + 1, rgb("252928"))
    c.noise(0.06)
    return c


def lens():
    c = Canvas(8, 8, rgb("F1ECC8"), 80)
    c.ring(4, 4, 3, 4.2, rgb("B8B293"))
    c.dot(3, 3, rgb("FFFFF0"))
    return c


def drawers():
    """32x32 steel desk drawer fronts (3 drawers with pulls)."""
    c = _metal(rgb("5F665E"), 81, scratches=4, grime=0.1)
    for y0 in (0, 11, 22):
        c.outline(1, y0 + 1, 31, y0 + 10, rgb("3A403A"))
        c.rect(11, y0 + 4, 21, y0 + 6, rgb("A3A89F"))
        c.rect(13, y0 + 7, 19, y0 + 8, CREAM)
    return c


def safe_front():
    """32x32 safe door front: inset border, brand plate."""
    c = _metal(rgb("3B443E"), 82, scratches=5, grime=0.08)
    c.outline(2, 2, 30, 30, rgb("232824"))
    c.outline(3, 3, 29, 29, rgb("505A53"))
    c.rect(10, 24, 22, 27, rgb("B79E5A"))
    c.text(11, 24, "", INK)
    return c


def sink_inside():
    c = Canvas(16, 16, rgb("7C807C"), 83)
    c.noise(0.06)
    c.speckle(0.1, rgb("5D5F55"))
    c.disc(8, 8, 2, rgb("2A2C2A"))
    return c


def chair_shell():
    c = Canvas(16, 16, rgb("5A6552"), 84)
    c.noise(0.05)
    c.speckle(0.04, rgb("4A5444"))
    return c


def breaker_inside():
    """32x48 breaker rows behind the panel door (two columns of switches)."""
    c = Canvas(32, 48, rgb("6A6F6B"), 85)
    c.noise(0.05)
    c.rect(13, 2, 19, 46, rgb("3A3E3B"))
    for row in range(8):
        y = 3 + row * 5
        for x0 in (3, 20):
            c.rect(x0, y, x0 + 9, y + 4, rgb("1A1C1B"))
            on = (row * 3 + x0) % 4 != 0
            c.rect(x0 + (5 if on else 2), y + 1, x0 + (7 if on else 4), y + 3, WHITE)
        c.rect(14, y + 1, 18, y + 2, CREAM, 0.6)
    c.outline(0, 0, 32, 48, rgb("454946"))
    return c


def breaker_door():
    """32x48 front of the breaker panel door: grey with a danger sticker and handle shadow."""
    c = _metal(rgb("6B716D"), 86, scratches=6, grime=0.1)
    c.rect(8, 6, 24, 18, YELLOW)
    c.outline(8, 6, 24, 18, INK)
    bolt = [(17, 7), (13, 12), (16, 12), (13, 17), (19, 11), (16, 11), (19, 7)]
    for (x0, y0), (x1, y1) in zip(bolt, bolt[1:]):
        c.line(x0, y0, x1, y1, INK)
    c.rect(15, 9, 17, 13, INK)
    c.rect(6, 22, 26, 28, WHITE)
    c.rect(6, 22, 26, 24, RED)
    c.rect(8, 25, 24, 26, INK)
    c.text(7, 33, "PANEL", INK, alpha=0.7)
    c.text(10, 39, "B-2", INK, alpha=0.7)
    return c


def locker_door():
    """64x128 locker door (0.5 x 1.79 m per half): left half = outer face with a number plate,
    right half = inner face. Both have the same alpha-clipped vent slits (2 px = 2.8 cm tall)
    so the player can see out while hiding."""
    c = _metal(OLIVE, 87, w=64, h=128, scratches=24, grime=0.22)
    inner = shade(OLIVE, 0.8)
    c.px[:, 32:, :3] *= 0.82
    for x0 in (0, 32):
        c.outline(x0, 0, x0 + 32, 128, shade(OLIVE, 0.75), 0.6)
    c.rect(11, 6, 21, 11, CREAM)
    c.outline(11, 6, 21, 11, rgb("8A876C"))
    c.text(12, 6, "07", INK)
    for x0 in (0, 32):
        lip = shade(OLIVE, 1.25) if x0 == 0 else shade(inner, 1.15)
        for y in (16, 20, 24, 28, 32, 36, 104, 108, 112, 116):
            c.rect(x0 + 7, y, x0 + 25, y + 2, (0, 0, 0, 0))
            c.rect(x0 + 7, y + 2, x0 + 25, y + 3, lip)
    c.speckle(0.08, shade(OLIVE, 0.6), 0.8, (0, 96, 32, 128))
    return c


def counter_tray():
    c = Canvas(16, 16, rgb("2A2D2B"), 88)
    c.noise(0.06)
    return c


PAINTERS = {name: fn for name, fn in globals().items()
            if callable(fn) and not name.startswith("_") and fn.__module__ == __name__ and name not in ("get",)}

_cache = {}


def get(name):
    """The Blender image for a painter, created once."""
    if name not in _cache:
        _cache[name] = PAINTERS[name]().image("tex_" + name)
    return _cache[name]


def reset_cache():
    _cache.clear()
