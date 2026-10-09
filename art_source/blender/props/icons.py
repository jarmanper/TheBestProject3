"""32x32 HUD slot icons (assets/ui/icons/icon_<id>.png): cream/white pixel style like the slot
icons in reference 3, transparent background, 1 px dark outline.

Shapes are drawn as vector primitives on a supersampled label grid; each output pixel takes the
majority tone of its samples (opaque when at least half are covered), so edges stay crisp with
no anti-aliasing. Coordinates are in pixels, y down.
"""
import math
import os

import numpy as np

from pxlib import rgb, save_png

SIZE = 32
SS = 6

# tones
SHADOW, MID, BASE, LIGHT, WHITE, DARK, DEEP, HOLE = 1, 2, 3, 4, 5, 6, 7, 8
TONES = {
    SHADOW: rgb("7A7660"),
    MID: rgb("AAA587"),
    BASE: rgb("D8D3A8"),
    LIGHT: rgb("EDE9D2"),
    WHITE: rgb("FFFDF0"),
    DARK: rgb("4B4C42"),
    DEEP: rgb("2C2E29"),
}
OUTLINE = rgb("121514", 0.9)


class Icon:
    def __init__(self):
        n = SIZE * SS
        c = (np.arange(n) + 0.5) / SS
        self.x, self.y = np.meshgrid(c, c)
        self.label = np.zeros((n, n), np.int16)

    def _set(self, mask, tone):
        self.label[mask] = tone

    def poly(self, pts, tone):
        inside = np.zeros(self.x.shape, bool)
        n = len(pts)
        for i in range(n):
            x0, y0 = pts[i]
            x1, y1 = pts[(i + 1) % n]
            cond = (y0 > self.y) != (y1 > self.y)
            with np.errstate(divide="ignore", invalid="ignore"):
                xc = x0 + (self.y - y0) * (x1 - x0) / (y1 - y0)
            inside ^= cond & (self.x < xc)
        self._set(inside, tone)

    def capsule(self, p0, p1, r, tone):
        (x0, y0), (x1, y1) = p0, p1
        dx, dy = x1 - x0, y1 - y0
        ln2 = max(dx * dx + dy * dy, 1e-9)
        t = np.clip(((self.x - x0) * dx + (self.y - y0) * dy) / ln2, 0, 1)
        d2 = (self.x - x0 - t * dx) ** 2 + (self.y - y0 - t * dy) ** 2
        self._set(d2 <= r * r, tone)

    def ellipse(self, c, rx, ry, tone, angle=0.0):
        ca, sa = math.cos(math.radians(angle)), math.sin(math.radians(angle))
        dx, dy = self.x - c[0], self.y - c[1]
        u = dx * ca + dy * sa
        v = -dx * sa + dy * ca
        self._set((u / rx) ** 2 + (v / ry) ** 2 <= 1.0, tone)

    def circle(self, c, r, tone):
        self.ellipse(c, r, r, tone)

    def rect(self, x0, y0, x1, y1, tone):
        self._set((self.x >= x0) & (self.x < x1) & (self.y >= y0) & (self.y < y1), tone)

    def shaded_capsule(self, p0, p1, r, light_dir=(-0.7, -0.7)):
        """Cylinder look: MID body, BASE core shifted toward the light, LIGHT highlight stripe."""
        lx, ly = light_dir
        self.capsule(p0, p1, r, MID)
        o = 0.18 * r
        self.capsule((p0[0] + lx * o, p0[1] + ly * o), (p1[0] + lx * o, p1[1] + ly * o), r * 0.72, BASE)
        o = 0.5 * r
        self.capsule((p0[0] + lx * o, p0[1] + ly * o), (p1[0] + lx * o, p1[1] + ly * o), max(0.6, r * 0.28), LIGHT)

    def render(self):
        lab = self.label.reshape(SIZE, SS, SIZE, SS).transpose(0, 2, 1, 3).reshape(SIZE, SIZE, SS * SS)
        covered = (lab > 0).mean(-1) >= 0.5
        counts = np.stack([(lab == t).sum(-1) for t in range(1, HOLE + 1)], -1)
        tone = counts.argmax(-1) + 1
        px = np.zeros((SIZE, SIZE, 4), np.float32)
        opaque = covered & (tone != HOLE)
        for t, color in TONES.items():
            px[opaque & (tone == t)] = color
        # 1 px outline around every opaque pixel (8-neighbourhood)
        grown = np.zeros_like(opaque)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                grown |= np.roll(np.roll(opaque, dy, 0), dx, 1)
        edge = grown & ~opaque
        edge[0, :] = edge[-1, :] = False
        edge[:, 0] = edge[:, -1] = False
        px[edge] = OUTLINE
        return px


def flashlight():
    ic = Icon()
    tail, neck, head = (6.5, 25.5), (16.0, 16.0), (21.0, 11.0)
    u = np.array([0.7071, -0.7071])
    n = np.array([0.7071, 0.7071])
    ic.shaded_capsule(tail, neck, 3.1)
    nk, hd = np.array(neck), np.array(head)
    ic.poly([tuple(nk - n * 3.1), tuple(hd - n * 5.4), tuple(hd + n * 5.4), tuple(nk + n * 3.1)], MID)
    ic.poly([tuple(nk - n * 2.6 - n * 0.6), tuple(hd - n * 4.8 - n * 0.6), tuple(hd + n * 3.0),
             tuple(nk + n * 1.6)], BASE)
    ic.poly([tuple(nk - n * 2.4), tuple(hd - n * 4.6), tuple(hd - n * 3.2), tuple(nk - n * 1.4)], LIGHT)
    band = hd - u * 0.6
    ic.capsule(tuple(band - n * 5.3), tuple(band + n * 5.3), 0.8, SHADOW)
    lens = hd + u * 1.2
    ic.ellipse(tuple(lens - u * 0.3), 2.6, 6.1, DARK, angle=-45)     # bezel
    ic.ellipse(tuple(lens), 2.1, 5.1, WHITE, angle=-45)              # glowing lens
    ic.ellipse(tuple(lens + n * 1.6 - u * 0.2), 0.9, 1.6, LIGHT, angle=-45)
    for k in (0.15, 0.3, 0.45):   # grip knurling
        p = np.array(tail) + (nk - np.array(tail)) * k
        ic.capsule(tuple(p - n * 2.6), tuple(p + n * 2.6), 0.45, SHADOW)
    sw = np.array(tail) + (nk - np.array(tail)) * 0.72 - n * 1.6
    ic.circle(tuple(sw), 1.1, DARK)
    return ic


def mop():
    ic = Icon()
    ic.shaded_capsule((25.5, 2.5), (13.5, 18.5), 1.5)
    ic.capsule((14.5, 17.5), (11.0, 22.0), 2.7, SHADOW)
    ic.capsule((14.0, 17.8), (11.5, 21.3), 1.6, MID)
    tips = [(3.0, 27.5), (5.0, 30.0), (8.5, 30.8), (12.0, 30.3), (15.0, 28.3), (16.0, 25.5)]
    for i, tip in enumerate(tips):
        ic.capsule((11.5, 22.0), tip, 1.7, MID if i % 2 else BASE)
    for i, tip in enumerate(tips[1:4]):
        ic.capsule((11.2, 22.6), (tip[0] - 0.6, tip[1] - 1.8), 0.6, LIGHT)
    return ic


def price_gun():
    """Pricing labeler seen from the side (nose right): tall housing with the label roll, slim
    nose with the print head, grip with a big squeeze lever in front of it."""
    ic = Icon()
    ic.poly([(5.5, 17), (11.5, 17), (10, 28.5), (4, 28.5)], MID)                 # grip
    ic.poly([(6.3, 17), (10.7, 17), (9.3, 27.5), (5, 27.5)], BASE)
    ic.poly([(12.5, 17), (17, 17), (14.2, 27.5), (10.8, 27.5)], SHADOW)        # lever
    ic.poly([(13.2, 17), (16, 17), (13.6, 26.2), (11.8, 26.2)], MID)
    ic.poly([(17, 11.5), (27.5, 13.5), (27.5, 17.5), (17, 17.5)], MID)          # nose
    ic.poly([(17, 12.6), (26.6, 14.4), (26.6, 16.6), (17, 16.6)], BASE)
    ic.capsule((17.5, 11.9), (27, 13.7), 0.6, WHITE)                            # label strip
    ic.rect(25.5, 16, 28.5, 19.5, DARK)                                         # print head
    ic.poly([(7, 5), (16, 5), (18, 7), (18, 18), (4.5, 18), (4.5, 7.5)], MID)   # housing
    ic.poly([(7.5, 6), (15.5, 6), (17, 7.5), (17, 17), (5.5, 17), (5.5, 8)], BASE)
    ic.rect(7.5, 6, 15.5, 7.2, LIGHT)
    ic.circle((11.2, 11.6), 4.4, LIGHT)                                         # label roll
    ic.circle((10.8, 11.2), 3.4, WHITE)
    ic.circle((11.2, 11.6), 1.6, DARK)
    return ic


def box_cutter():
    ic = Icon()
    blade = [(19.6, 9.6), (23.2, 13.2), (28.0, 6.6), (27.4, 4.4)]
    ic.poly(blade, LIGHT)
    ic.poly([(20.6, 10.6), (23.2, 13.2), (28.0, 6.6), (27.6, 5.6)], WHITE)
    ic.capsule((22.3, 9.9), (24.0, 11.6), 0.4, MID)
    ic.capsule((24.6, 7.6), (26.3, 9.3), 0.4, MID)
    ic.shaded_capsule((6.0, 26.0), (19.5, 12.5), 3.5)
    ic.capsule((19.0, 13.0), (21.2, 10.8), 2.4, MID)
    n = np.array([0.7071, 0.7071])
    for k in (0.08, 0.2, 0.32, 0.44):
        p = np.array((6.0, 26.0)) + (np.array((19.5, 12.5)) - np.array((6.0, 26.0))) * k
        ic.capsule(tuple(p - n * 3.0), tuple(p + n * 3.0), 0.5, SHADOW)
    s = np.array((6.0, 26.0)) + (np.array((19.5, 12.5)) - np.array((6.0, 26.0))) * 0.68 - n * 2.0
    ic.capsule(tuple(s - np.array([0.7071, -0.7071]) * 1.5), tuple(s + np.array([0.7071, -0.7071]) * 1.5), 1.0,
               DARK)
    return ic


def stock_box():
    ic = Icon()
    ic.poly([(3, 11), (16, 17.5), (16, 29.5), (3, 23)], MID)
    ic.poly([(16, 17.5), (29, 11), (29, 23), (16, 29.5)], SHADOW)
    ic.poly([(16, 4.5), (29, 11), (16, 17.5), (3, 11)], BASE)
    ic.poly([(8.0, 8.4), (11.0, 6.9), (24.0, 13.4), (21.0, 14.9)], LIGHT)
    ic.capsule((9.5, 7.7), (22.5, 14.2), 0.35, MID)
    ic.poly([(21.0, 14.9), (24.0, 13.4), (24.0, 18.6), (21.0, 20.1)], MID)
    ic.poly([(6, 16.5), (12.5, 19.8), (12.5, 24.5), (6, 21.2)], LIGHT)
    ic.capsule((7.2, 18.4), (11.4, 20.6), 0.35, DARK)
    ic.capsule((7.2, 20.4), (10.2, 22.0), 0.35, DARK)
    return ic


def keys():
    ic = Icon()
    ic.circle((11.0, 9.5), 6.4, MID)
    ic.circle((10.6, 9.1), 5.6, BASE)
    ic.circle((11.0, 9.5), 4.4, HOLE)
    # key hanging down-right
    ic.capsule((17.0, 17.0), (26.5, 26.5), 1.7, MID)
    ic.capsule((16.6, 16.6), (26.0, 26.0), 1.0, BASE)
    for t in ((20.5, 23.0), (22.5, 25.0), (24.6, 27.1)):
        ic.rect(t[0] - 1, t[1] - 1, t[0] + 1, t[1] + 1, MID)
    ic.circle((15.5, 15.5), 3.9, MID)
    ic.circle((15.1, 15.1), 3.1, LIGHT)
    ic.circle((15.5, 15.5), 1.5, DEEP)
    # key hanging straight down
    ic.capsule((8.5, 19.0), (8.5, 29.0), 1.6, MID)
    ic.capsule((8.1, 19.0), (8.1, 28.5), 0.9, BASE)
    for ty in (23.0, 25.5):
        ic.rect(10.0, ty, 11.5, ty + 1.5, MID)
    ic.circle((8.5, 16.5), 3.5, MID)
    ic.circle((8.1, 16.1), 2.7, LIGHT)
    ic.circle((8.5, 16.5), 1.5, DEEP)
    return ic


def walkie():
    ic = Icon()
    ic.capsule((12.5, 11.0), (12.5, 2.5), 1.5, MID)
    ic.capsule((12.1, 10.0), (12.1, 3.0), 0.7, BASE)
    ic.rect(17, 6, 21, 10.5, SHADOW)
    ic.rect(17.8, 6.6, 19.2, 10.5, MID)
    body = [(10.5, 10), (22.5, 10), (23.5, 11), (23.5, 29), (22.5, 30), (10.5, 30), (9.5, 29), (9.5, 11)]
    ic.poly(body, MID)
    ic.poly([(10.5, 11), (21.5, 11), (22.5, 12), (22.5, 28), (21.5, 29), (10.5, 29)], BASE)
    ic.rect(10.5, 11, 12, 29, LIGHT)
    for y in (13.0, 15.0, 17.0, 19.0):
        ic.rect(13.0, y, 21.0, y + 1.0, DARK)
    ic.rect(12.5, 21.5, 21.5, 26.0, DEEP)
    ic.rect(13.5, 22.5, 18.0, 23.5, LIGHT)
    ic.rect(8.2, 14, 9.6, 20, SHADOW)
    return ic


ICONS = {
    "flashlight": flashlight,
    "mop": mop,
    "price_gun": price_gun,
    "box_cutter": box_cutter,
    "stock_box": stock_box,
    "keys": keys,
    "walkie": walkie,
}


def build_all(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    written = []
    for name, fn in ICONS.items():
        px = fn().render()
        path = os.path.join(out_dir, "icon_%s.png" % name)
        save_png(px, path)
        written.append((path, int((px[..., 3] > 0.5).sum())))
    return written
