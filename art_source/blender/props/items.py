"""Hand-held items shared by the tool pickups and the first-person viewmodels, plus
cardboard box helpers. Each function adds geometry to a MeshBuilder through matrix `m`
(rigid transforms only).
"""
import math

from mathutils import Vector

import mats
from pxlib import R, T

# BoxAtlas UV rects (u0, v0, u1, v1), inset half a texel so nearest sampling never bleeds.
_I = 0.5 / 64
SHORT_SIDE = (0 + _I, 0.5 + _I, 0.5 - _I, 1 - _I)
LONG_SIDE = (0.5 + _I, 0.5 + _I, 1 - _I, 1 - _I)
TOP = (0 + _I, 0 + _I, 0.5 - _I, 0.5 - _I)
INSIDE = (0.5 + _I, 0 + _I, 1 - _I, 0.5 - _I)
# StockBox (64x32): left half printed side, right half taped top.
_J = 0.5 / 64
STOCK_SIDE = (0 + _J, 0 + _J * 2, 0.5 - _J, 1 - _J * 2)
STOCK_TOP = (0.5 + _J, 0 + _J * 2, 1 - _J, 1 - _J * 2)

TO_Y = R(-90, "x")    # cylinder() builds along +Z; this turns local +Z into +Y


def M(name):
    return mats.get(name)


def card_box(mb, x, y, z, w, d, h, rot=0.0, m=None, extra=None):
    """Closed taped cardboard box, bottom centre at (x, y, z), rotated `rot` degrees about Z.
    The long side always gets the label face and the tape runs along it."""
    if d > w:
        w, d = d, w
        rot += 90.0
    mm = T(x, y, z) @ R(rot, "z")
    if extra is not None:
        mm = mm @ extra
    if m is not None:
        mm = m @ mm
    rects = {"-y": LONG_SIDE, "+y": LONG_SIDE, "-x": SHORT_SIDE, "+x": SHORT_SIDE, "+z": TOP, "-z": TOP}
    mb.box((-w / 2, -d / 2, 0), (w / 2, d / 2, h), M("BoxAtlas"), m=mm, rects=rects)


def stock_box(mb, m, w=0.4, d=0.3, h=0.26):
    """The carriable stock box (Tool of pickup_stock_box, held in vm_stock_box).
    Bottom centre at the local origin, long side along X."""
    rects = {"-y": STOCK_SIDE, "+y": STOCK_SIDE, "-x": STOCK_SIDE, "+x": STOCK_SIDE,
             "+z": STOCK_TOP, "-z": STOCK_TOP}
    mb.box((-w / 2, -d / 2, 0), (w / 2, d / 2, h), M("StockBox"), m=m, rects=rects)


def open_box(mb, m, w, d, h, flaps=(115, 120, 105, 125), wall=0.008):
    """Open cardboard box (no lid) with four flaps folded outward by the given angles (deg)
    for the -y, +y, -x, +x edges (0 = closed, 90 = standing up, 180 = folded flat outward).
    Bottom centre at the local origin."""
    atlas = M("BoxAtlas")
    rects = {"-y": LONG_SIDE, "+y": LONG_SIDE, "-x": SHORT_SIDE, "+x": SHORT_SIDE, "-z": TOP}
    mb.box((-w / 2, -d / 2, 0), (w / 2, d / 2, h), atlas, m=m, rects=rects, skip=("+z",))
    inner = {k: INSIDE for k in ("-y", "+y", "-x", "+x", "+z", "-z")}
    mb.box((-w / 2 + wall, -d / 2 + wall, wall), (w / 2 - wall, d / 2 - wall, h), atlas, m=m,
           rects=inner, skip=("+z",), inward=True)
    for x0, y0, x1, y1 in ((-w / 2, -d / 2, w / 2, -d / 2 + wall), (-w / 2, d / 2 - wall, w / 2, d / 2),
                           (-w / 2, -d / 2 + wall, -w / 2 + wall, d / 2 - wall),
                           (w / 2 - wall, -d / 2 + wall, w / 2, d / 2 - wall)):
        mb.poly([(x0, y0, h), (x1, y0, h), (x1, y1, h), (x0, y1, h)], atlas, m=m, uv="fit", rect=INSIDE)
    # Each flap is hinged on a top edge. Built lying flat over the opening (pointing toward the
    # box centre along +Y after the yaw), then rotated about the hinge (local X) by -angle.
    specs = [
        ((0, -d / 2, h), w, d * 0.5, 0.0, flaps[0]),
        ((0, d / 2, h), w, d * 0.5, 180.0, flaps[1]),
        ((-w / 2, 0, h), d, w * 0.5, -90.0, flaps[2]),
        ((w / 2, 0, h), d, w * 0.5, 90.0, flaps[3]),
    ]
    for (px, py, pz), length, depth, yaw, angle in specs:
        fm = m @ T(px, py, pz) @ R(yaw, "z") @ R(angle, "x")
        top = [(-length / 2, 0, 0), (length / 2, 0, 0), (length / 2, depth, 0), (-length / 2, depth, 0)]
        mb.poly(top, atlas, m=fm, uv="fit", rect=SHORT_SIDE)
        mb.poly(top[::-1], atlas, m=fm @ T(0, 0, -0.003), uv="fit", rect=INSIDE)


def flashlight(mb, m):
    """Black flashlight along local +Y, origin at the grip centre. Returns the lens centre
    (local, before `m`)."""
    body, lens, rub = M("FlashlightBody"), M("Lens"), M("Rubber")
    mb.cylinder(body, r0=0.021, h=0.018, segs=8, m=m @ T(0, -0.115, 0) @ TO_Y, texel=0.05)
    mb.cylinder(body, r0=0.018, h=0.19, segs=8, m=m @ T(0, -0.097, 0) @ TO_Y, caps=(False, False), texel=0.04)
    mb.cylinder(body, r0=0.018, r1=0.029, h=0.04, segs=8, m=m @ T(0, 0.093, 0) @ TO_Y, caps=(False, False),
                texel=0.05)
    mb.cylinder(body, r0=0.029, h=0.03, segs=8, m=m @ T(0, 0.133, 0) @ TO_Y, caps=(False, False), texel=0.05)
    mb.cylinder(body, r0=0.029, r1=0.026, h=0.004, segs=8, m=m @ T(0, 0.163, 0) @ TO_Y, caps=(False, False),
                texel=0.05)
    mb.cylinder(lens, r0=0.026, h=0.001, segs=8, m=m @ T(0, 0.162, 0) @ TO_Y, cap_rect=(0, 0, 1, 1),
                caps=(False, True))
    mb.box((-0.006, 0.0, 0.016), (0.006, 0.025, 0.023), rub, m=m)
    return Vector((0, 0.164, 0))


def price_gun(mb, m):
    """Pricing labeler (not a weapon): tall orange rear housing with the cream label roll showing
    on both sides, slim nose with a black print head, pistol grip with a large trigger lever.
    Local frame: nose toward +X, top toward +Z, thickness along Y. Origin at the grip centre."""
    body, black, roll = M("OrangePlastic"), M("PlasticBlack"), M("LabelRoll")
    g = m @ T(0.083, 0, 0.045)   # profile space -> grip centre at the origin
    profile = [(0.115, 0.0), (0.115, 0.03), (0.035, 0.045), (0.022, 0.098), (-0.078, 0.098), (-0.095, 0.075),
               (-0.095, 0.0), (-0.115, -0.085), (-0.1, -0.098), (-0.075, -0.095), (-0.055, 0.0)]
    mb.extrude(profile, 0.036, body, m=g, texel=0.08)
    mb.box((-0.008, -0.012, -0.088), (0.008, 0.012, 0.0), black, m=g @ T(-0.03, 0, 0) @ R(-14, "y"))   # lever
    mb.box((0.095, -0.013, -0.012), (0.12, 0.013, 0.012), black, m=g)                                  # print head
    side = R(90, "x")
    mb.cylinder(roll, r0=0.036, h=0.046, segs=8, m=g @ T(-0.035, 0.023, 0.05) @ side,
                cap_rect=(0.1, 0.2, 0.9, 0.8), wrap_u=2)
    mb.cylinder(black, r0=0.012, h=0.05, segs=6, m=g @ T(-0.035, 0.025, 0.05) @ side)
    mb.box((0.0, -0.011, 0.0), (0.087, 0.011, 0.003), roll, m=g @ T(0.03, 0, 0.046) @ R(10, "y"),
           uv="fit")                                                                                  # label strip


def box_cutter(mb, m):
    """Yellow box cutter along local +Y (blade at +Y), flat side up (+Z). Origin at the grip."""
    body, black, steel = M("CutterBody"), M("PlasticBlack"), M("Steel")
    rects = {"+z": (0, 0, 1, 1), "-z": (0, 0, 1, 1)}
    mb.box((-0.013, -0.08, -0.009), (0.013, 0.055, 0.009), body, m=m, rects=rects, texel=0.05)
    mb.box((-0.010, 0.055, -0.007), (0.010, 0.07, 0.007), M("MetalLight"), m=m, texel=0.05)
    mb.box((-0.005, -0.01, 0.009), (0.005, 0.02, 0.014), black, m=m)
    blade = [(-0.006, 0.0), (0.006, 0.0), (0.004, 0.03), (-0.008, 0.021)]
    mb.extrude(blade, 0.002, steel, m=m @ T(0, 0.068, 0) @ R(-90, "x"), texel=0.05)


def mop(mb, m, top=0.32, bottom=1.0, head=0.26):
    """Mop along local Z: handle from z = +top down to z = -bottom, strand head below it.
    Origin at the grip point on the handle."""
    handle, black, strands = M("MetalLight"), M("PlasticBlack"), M("MopStrands")
    mb.tube(m @ Vector((0, 0, top)), m @ Vector((0, 0, -bottom)), 0.012, handle, segs=6, texel=0.1)
    mb.cylinder(black, r0=0.0145, h=0.07, segs=6, m=m @ T(0, 0, top - 0.06))
    mb.cylinder(M("PlasticYellow"), r0=0.03, r1=0.024, h=0.05, segs=6, m=m @ T(0, 0, -bottom - 0.03))
    mb.cylinder(strands, r0=0.085, r1=0.04, h=head - 0.02, segs=8, m=m @ T(0, 0, -bottom - head),
                wrap_u=3, v_range=(0.0, 1.0), cap_rect=(0.1, 0.1, 0.9, 0.9), caps=(True, False))
    for i in range(6):
        a = i / 6 * 2 * math.pi + 0.3
        x, y = math.cos(a) * 0.07, math.sin(a) * 0.07
        mb.box((x - 0.012, y - 0.012, -bottom - head - 0.035), (x + 0.012, y + 0.012, -bottom - head + 0.02),
               strands, m=m, texel=0.2)


def keyring(mb, m, fan=1.0):
    """Key ring hanging from the local origin (top of the ring) with three keys and an orange
    tag below it; the ring lies in the XZ plane facing -Y."""
    brass, silver, tag = M("Brass"), M("MetalLight"), M("OrangePlastic")
    r = 0.02
    pts = [Vector((math.sin(2 * math.pi * i / 10) * r, 0, -r + math.cos(2 * math.pi * i / 10) * r))
           for i in range(10)]
    for i in range(10):
        mb.bar(m @ pts[i], m @ pts[(i + 1) % 10], 0.0035, silver)
    for angle, mat, dy in ((-22.0, brass, 0.004), (4.0, silver, -0.004), (27.0, brass, 0.0)):
        km = m @ T(0, dy, -2 * r) @ R(angle * fan, "y")
        mb.cylinder(mat, r0=0.011, h=0.003, segs=6, m=km @ T(0, 0.0015, -0.011) @ R(90, "x"), texel=0.05)
        mb.box((-0.0035, -0.0012, -0.066), (0.0035, 0.0012, -0.02), mat, m=km, texel=0.05)
        mb.box((0.0035, -0.0012, -0.06), (0.0065, 0.0012, -0.054), mat, m=km, texel=0.05)
        mb.box((0.0035, -0.0012, -0.047), (0.0060, 0.0012, -0.04), mat, m=km, texel=0.05)
    tm = m @ T(0.004, 0.003, -2 * r) @ R(-48 * fan, "y")
    mb.box((-0.011, -0.0015, -0.042), (0.011, 0.0015, -0.006), tag, m=tm, texel=0.05)
