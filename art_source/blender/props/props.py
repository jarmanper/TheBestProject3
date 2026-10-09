"""Prop builders. Each `build_<name>(col, name)` creates its objects in collection `col` and
returns the top-level objects to export as assets/models/props/<name>.glb.

Blender axes: X right, -Y = model front (Godot +Z), Z up. Floor props: origin at the floor
centre of the footprint. Wall props: origin at the wall-contact centre, back face on y = 0,
extending toward -Y; MOUNT_HEIGHTS gives the suggested origin height above the floor.
"""
import math

import numpy as np
from mathutils import Matrix, Vector

import items
import mats
from items import INSIDE, LONG_SIDE, SHORT_SIDE, TOP, card_box
from pxlib import MeshBuilder, R, T, look_matrix, parent

BUILDERS = {}

# Suggested height (m) of a wall prop's origin above the floor.
MOUNT_HEIGHTS = {
    "pickup_mop": 1.35,
    "pickup_box_cutter": 1.25,
    "pickup_keys": 1.45,
    "clipboard": 1.35,
    "breaker_sparks": 1.5,
    "time_clock": 1.4,
    "breaker_panel": 1.5,
}


def prop(kind):
    def register(fn):
        BUILDERS[fn.__name__[len("build_"):]] = (fn, kind)
        return fn
    return register


def M(name):
    return mats.get(name)


def obj(mb, col, prop_name, node, location=(0, 0, 0)):
    return mb.to_object("%s__%s" % (prop_name, node), col, location, export_name=node)


def ground(*builders, z=0.0):
    """Shifts all builders together so the lowest vertex sits at `z`."""
    low = min(v.z for mb in builders for v in mb.verts)
    for mb in builders:
        for v in mb.verts:
            v.z += z - low


def center_xy(*builders):
    xs = [v.x for mb in builders for v in mb.verts]
    ys = [v.y for mb in builders for v in mb.verts]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    for mb in builders:
        for v in mb.verts:
            v.x -= cx
            v.y -= cy


# --- hiding spots ----------------------------------------------------------

@prop("floor")
def build_locker(col, name):
    """0.5 x 0.5 x 1.9 m olive locker. `Door` is hinged on the left edge (seen from the front);
    it opens outward with a negative Godot rotation.y (e.g. -100 degrees)."""
    olive, dark, light = M("MetalOlive"), M("MetalDark"), M("MetalLight")
    body = MeshBuilder()
    H, t = 1.9, 0.02
    zb, zt, yf = 0.08, H - 0.03, -0.232
    body.box((-0.25, -0.25, 0), (0.25, 0.25, zb), dark)                    # plinth
    body.box((-0.25, -0.25, zt), (0.25, 0.25, H), olive)                   # top cap
    body.box((-0.25, yf, zb), (-0.25 + t, 0.25, zt), olive)                # left side
    body.box((0.25 - t, yf, zb), (0.25, 0.25, zt), olive)                  # right side
    body.box((-0.25 + t, 0.25 - t, zb), (0.25 - t, 0.25, zt), olive)       # back
    body.box((-0.23, -0.2, 1.56), (0.23, 0.23, 1.58), olive)               # hat shelf
    body.bar((0, 0.23, 1.44), (0, 0.16, 1.47), 0.012, light)               # coat hook
    for z in (1.2, 1.25, 1.3):                                             # side vents
        for x in (-0.2505, 0.2505):
            body.box((x - 0.001, -0.08, z), (x + 0.001, 0.08, z + 0.012), dark)
    door = MeshBuilder()
    door_face = M("LockerDoor")
    door.box((0.003, -0.009, 0.004), (0.497, 0.009, 1.782), olive,
             mats={"-y": door_face, "+y": door_face},
             rects={"-y": (0.004, 0.002, 0.496, 0.998), "+y": (0.504, 0.002, 0.996, 0.998)})
    door.box((0.43, -0.03, 0.88), (0.465, -0.009, 1.04), light)            # latch handle
    door.box((0.44, -0.045, 0.93), (0.455, -0.03, 0.99), dark)             # padlock hasp
    for z in (0.25, 1.5):                                                  # hinge knuckles
        door.cylinder(light, r0=0.008, h=0.07, segs=6, m=T(0.0, -0.01, z))
    b = obj(body, col, name, "Locker")
    d = obj(door, col, name, "Door", location=(-0.25, -0.241, 0.083))
    parent(d, b)
    return [b]


@prop("floor")
def build_box_pile_hide(col, name):
    """Cardboard boxes around a crouch nook: cavity x -0.42..0.42, y -0.38..0.4 (Blender),
    0.96 m high, open toward the front (-Y, Godot +Z) between x -0.31 and 0.31.
    Suggested HidePoint (Godot): (0, 0.72, 0) looking toward +Z; ExitPoint (0, 0, 1.2)."""
    mb = MeshBuilder()
    boxes = [
        # back wall
        (-0.68, 0.64, 0.0, 0.56, 0.46, 0.46, 3), (-0.06, 0.66, 0.0, 0.62, 0.48, 0.50, -2),
        (0.62, 0.64, 0.0, 0.60, 0.46, 0.44, 4), (-0.55, 0.66, 0.46, 0.60, 0.44, 0.47, -5),
        (0.30, 0.66, 0.50, 0.66, 0.46, 0.46, 3),
        # side walls
        (-0.70, 0.0, 0.0, 0.74, 0.50, 0.50, 92), (-0.70, 0.05, 0.50, 0.66, 0.48, 0.46, 87),
        (0.70, 0.0, 0.0, 0.72, 0.50, 0.48, 88), (0.70, -0.02, 0.48, 0.70, 0.48, 0.48, 93),
        # front, leaving a gap
        (-0.62, -0.62, 0.0, 0.62, 0.44, 0.44, -4), (-0.66, -0.60, 0.44, 0.50, 0.40, 0.36, 8),
        (0.52, -0.60, 0.0, 0.42, 0.36, 0.32, 6),
        # on top of the roof
        (-0.35, 0.55, 0.985, 0.50, 0.40, 0.34, 10), (0.55, 0.10, 0.985, 0.45, 0.40, 0.30, -12),
        (0.02, -0.08, 0.99, 0.40, 0.36, 0.26, 25),
    ]
    for x, y, z, w, d, h, rot in boxes:
        card_box(mb, x, y, z, w, d, h, rot)
    sheet = M("Cardboard")
    mb.box((-0.64, -0.46, 0.965), (0.64, 0.52, 0.977), sheet, m=R(1.5, "y"), texel=0.5)
    mb.box((-0.5, -0.3, 0.977), (0.5, 0.42, 0.985), sheet, m=R(-7, "z"), rects={"+z": LONG_SIDE},
           mats={"+z": M("BoxAtlas")})
    return [obj(mb, col, name, "BoxPile")]


# --- tool pickups ----------------------------------------------------------

@prop("wall")
def build_pickup_mop(col, name):
    """Wall bracket (Rack) with a mop (Tool) clipped in it. Mount the origin at y = 1.35 m."""
    grey, black = M("MetalGrey"), M("PlasticBlack")
    rack = MeshBuilder()
    rack.box((-0.13, -0.012, -0.04), (0.13, 0.0, 0.04), grey)
    for x in (-0.07, 0.07):
        rack.box((x - 0.024, -0.075, -0.022), (x - 0.013, -0.012, 0.022), black)
        rack.box((x + 0.013, -0.075, -0.022), (x + 0.024, -0.012, 0.022), black)
    for x in (-0.115, 0.115):
        rack.cylinder(M("MetalLight"), r0=0.007, h=0.004, segs=6, m=T(x, -0.012, 0) @ R(90, "x"))
    tool = MeshBuilder()
    # lean the bottom forward (-Y) so the strand head clears the wall
    items.mop(tool, R(-math.degrees(math.atan2(0.105, 1.32)), "x"), top=0.32, bottom=1.0, head=0.27)
    r = obj(rack, col, name, "Rack")
    t = obj(tool, col, name, "Tool", location=(-0.07, -0.043, 0.0))
    return [r, t]


@prop("floor")
def build_pickup_price_gun(col, name):
    """Counter tray (Rack) with a spare label roll; the price gun (Tool) lies in it."""
    tray, roll, black = M("CounterTray"), M("LabelRoll"), M("PlasticBlack")
    rack = MeshBuilder()
    w, d, h, t = 0.36, 0.24, 0.035, 0.01
    rack.box((-w / 2, -d / 2, 0), (w / 2, d / 2, 0.008), tray)
    rack.box((-w / 2, -d / 2, 0.008), (w / 2, -d / 2 + t, h), tray)
    rack.box((-w / 2, d / 2 - t, 0.008), (w / 2, d / 2, h), tray)
    rack.box((-w / 2, -d / 2 + t, 0.008), (-w / 2 + t, d / 2 - t, h), tray)
    rack.box((w / 2 - t, -d / 2 + t, 0.008), (w / 2, d / 2 - t, h), tray)
    rack.cylinder(roll, r0=0.032, h=0.028, segs=8, m=T(0.12, 0.065, 0.008), wrap_u=2,
                  cap_rect=(0.1, 0.2, 0.9, 0.8))
    rack.cylinder(black, r0=0.011, h=0.03, segs=6, m=T(0.12, 0.065, 0.008))
    tool = MeshBuilder()
    items.price_gun(tool, R(90, "x"))   # lying on its side: gun-up (+Z) points to -Y
    r = obj(rack, col, name, "Rack")
    t = obj(tool, col, name, "Tool", location=(-0.04, 0.04, 0.008 + 0.024))   # resting on its label roll
    return [r, t]


@prop("wall")
def build_pickup_box_cutter(col, name):
    """Small pegboard plate with a hook (Rack); the box cutter (Tool) hangs on it.
    Mount the origin at y = 1.25 m (wall or the side of a shelf upright)."""
    rack = MeshBuilder()
    rack.box((-0.09, -0.012, -0.12), (0.09, 0.0, 0.12), M("PegBoard"), rects={"-y": (0, 0, 1, 1)})
    hook = M("MetalLight")
    rack.bar((0, -0.012, 0.07), (0, -0.075, 0.07), 0.006, hook)
    rack.bar((0, -0.075, 0.07), (0, -0.082, 0.085), 0.006, hook)
    rack.box((-0.06, -0.014, -0.11), (0.06, -0.012, -0.085), M("Labels"), rects={"-y": (0.03, 0.53, 0.47, 0.6)})
    tool = MeshBuilder()
    # hang it from the hole in its tail: blade (local +Y) down, slider (local +Z) toward the front
    items.box_cutter(tool, Matrix(((-1, 0, 0, 0), (0, 0, -1, 0), (0, -1, 0, 0), (0, 0, 0, 1))))
    r = obj(rack, col, name, "Rack")
    t = obj(tool, col, name, "Tool", location=(0.0, -0.035, -0.012))
    return [r, t]


@prop("floor")
def build_pickup_stock_box(col, name):
    """Low metal rack (Rack) with stock boxes; `Tool` is the top box on the right stack."""
    grey = M("MetalGrey")
    rack = MeshBuilder()
    w, d = 0.9, 0.46
    for x in (-w / 2 + 0.015, w / 2 - 0.015):
        for y in (-d / 2 + 0.015, d / 2 - 0.015):
            rack.box((x - 0.015, y - 0.015, 0), (x + 0.015, y + 0.015, 0.78), grey)
    for z in (0.1, 0.72):
        rack.box((-w / 2, -d / 2, z), (w / 2, d / 2, z + 0.025), grey)
        rack.box((-w / 2, -d / 2 - 0.004, z + 0.025), (w / 2, -d / 2 + 0.006, z + 0.05), grey)
    for x, z in ((-0.2, 0.125), (0.21, 0.125), (-0.2, 0.745), (0.2, 0.745)):
        items.stock_box(rack, T(x, 0.0, z) @ R(2 * x * 10, "z"))
    tool = MeshBuilder()
    items.stock_box(tool, T(0, 0, 0))
    r = obj(rack, col, name, "Rack")
    t = obj(tool, col, name, "Tool", location=(0.19, 0.0, 0.745 + 0.26))
    return [r, t]


@prop("wall")
def build_pickup_keys(col, name):
    """Key board with three hooks (Rack); the store key ring (Tool) hangs on the middle hook.
    Mount the origin at y = 1.45 m."""
    rack = MeshBuilder()
    rack.box((-0.14, -0.015, -0.1), (0.14, 0.0, 0.1), M("Hardboard"), rects={"-y": (0, 0, 1, 1)},
             mats={"-y": M("KeyBoard")})
    for x in (-0.08, 0.0, 0.08):
        rack.bar((x, -0.015, -0.02), (x, -0.045, -0.02), 0.004, M("Brass"))
        rack.bar((x, -0.045, -0.02), (x, -0.05, -0.008), 0.004, M("Brass"))
    tool = MeshBuilder()
    items.keyring(tool, T(0, 0, 0))
    r = obj(rack, col, name, "Rack")
    t = obj(tool, col, name, "Tool", location=(0.0, -0.04, -0.018))
    return [r, t]


# --- task visuals ----------------------------------------------------------

@prop("floor")
def build_spill_decal(col, name):
    """1.2 m puddle quad (alpha blended, glossy), 4 mm above the floor."""
    mb = MeshBuilder()
    mb.poly([(-0.6, -0.6, 0.004), (0.6, -0.6, 0.004), (0.6, 0.6, 0.004), (-0.6, 0.6, 0.004)], M("Spill"),
            uv="fit")
    return [obj(mb, col, name, "Spill")]


@prop("floor")
def build_wet_floor_sign(col, name):
    """Yellow A-frame CAUTION WET FLOOR sign."""
    mb = MeshBuilder()
    face, yellow = M("WetSign"), M("PlasticYellow")
    panel = MeshBuilder()
    panel.box((-0.15, -0.006, -0.62), (0.15, 0.006, 0.0), yellow, rects={"-y": (0, 0, 1, 1)}, mats={"-y": face})
    for yaw in (0.0, 180.0):
        mb.merge(panel, R(yaw, "z") @ R(-14, "x"))
    mb.box((-0.07, -0.012, 0.0), (0.07, 0.012, 0.06), yellow)
    mb.box((-0.04, -0.013, 0.02), (0.04, 0.013, 0.045), M("PlasticBlack"))
    ground(mb)
    return [obj(mb, col, name, "WetFloorSign")]


@prop("floor")
def build_trash_bag(col, name):
    """Lumpy black garbage bag with a tied top."""
    mb = MeshBuilder()
    bag = M("BagBlack")
    mb.ellipsoid((0, 0, 0.22), (0.25, 0.21, 0.25), bag, segs=8, rings=6, jitter=0.12, seed=3, flat_bottom=0.0)
    mb.cylinder(bag, r0=0.06, r1=0.018, h=0.1, segs=6, m=T(0.01, 0.0, 0.44), smooth=False)
    for yaw in (20, 160):
        mb.poly([(-0.012, 0, 0.0), (0.012, 0, 0.0), (0.03, 0.0, 0.07), (-0.02, 0, 0.06)], bag,
                m=T(0.01, 0, 0.53) @ R(yaw, "z"))
        mb.poly([(-0.012, 0, 0.0), (-0.02, 0, 0.06), (0.03, 0.0, 0.07), (0.012, 0, 0.0)], bag,
                m=T(0.01, 0, 0.53) @ R(yaw, "z"))
    ground(mb)
    center_xy(mb)
    return [obj(mb, col, name, "TrashBag")]


@prop("floor")
def build_flattened_boxes(col, name):
    """Stack of broken-down cardboard boxes plus one half-collapsed box."""
    mb = MeshBuilder()
    atlas = M("BoxAtlas")
    rng = np.random.default_rng(5)
    for i in range(6):
        w, d = 0.95 + rng.random() * 0.15, 0.6 + rng.random() * 0.1
        m = T(rng.random() * 0.08 - 0.04, rng.random() * 0.08 - 0.04, i * 0.011) @ R(rng.random() * 24 - 12, "z")
        rect = LONG_SIDE if i % 2 == 0 else SHORT_SIDE
        mb.box((-w / 2, -d / 2, 0), (w / 2, d / 2, 0.01), M("Cardboard"), m=m, rects={"+z": rect, "-z": TOP},
               mats={"+z": atlas, "-z": atlas})
        mb.box((-0.004, -d / 2, 0.0101), (0.004, d / 2, 0.0103), atlas, m=m, rects={"+z": INSIDE}, skip=("-z",))
    items.open_box(mb, T(0.18, -0.05, 0.066) @ R(18, "z") @ R(8, "x"), 0.45, 0.34, 0.16, flaps=(160, 150, 170, 140))
    ground(mb)
    center_xy(mb)
    return [obj(mb, col, name, "FlattenedBoxes")]


@prop("floor")
def build_messy_products(col, name):
    """Knocked-over groceries (cereal boxes, snack boxes, cans, bottles) for 'face shelves'."""
    mb = MeshBuilder()
    prod = M("Products")
    q = 0.25

    def cell(row, i):
        u0, v0 = i * q, 1.0 - (row + 1) * q
        e = 0.5 / 64
        return (u0 + e, v0 + e, u0 + q - e, v0 + q - e)

    def strip(row, i):
        u0, v0 = i * q, 1.0 - (row + 1) * q
        return (u0 + 0.02, v0 + 0.005, u0 + q - 0.02, v0 + 0.015)

    def cereal(x, y, rot, i, standing=False, lean=0.0):
        w, d, h = 0.19, 0.065, 0.28
        rects = {"-y": cell(0, i), "+y": cell(0, (i + 1) % 4), "-x": strip(0, i), "+x": strip(0, i),
                 "+z": strip(0, i), "-z": strip(0, i)}
        if standing:
            m = T(x, y, 0) @ R(rot, "z") @ R(lean, "x")
        else:   # lying on its back, front up
            m = T(x, y, d / 2) @ R(rot, "z") @ R(-90, "x") @ T(0, 0, -h / 2)
        mb.box((-w / 2, -d / 2, 0), (w / 2, d / 2, h), prod, m=m, rects=rects)

    def snack(x, y, rot, i):
        w, d, h = 0.13, 0.045, 0.17
        rects = {"-y": cell(1, i), "+y": cell(1, i), "-x": strip(1, i), "+x": strip(1, i),
                 "+z": strip(1, i), "-z": strip(1, i)}
        mb.box((-w / 2, -d / 2, 0), (w / 2, d / 2, h), prod, m=T(x, y, d / 2) @ R(rot, "z") @ R(-90, "x")
               @ T(0, 0, -h / 2), rects=rects)

    def can(x, y, rot, i):
        r, h = 0.033, 0.12
        mb.cylinder(prod, r0=r, h=h, segs=8, m=T(x, y, r) @ R(rot, "z") @ R(90, "y") @ T(0, 0, -h / 2),
                    rect=cell(2, i), cap_rect=strip(2, i))

    def bottle(x, y, rot, i):
        r, h = 0.038, 0.19
        base = T(x, y, r) @ R(rot, "z") @ R(90, "y") @ T(0, 0, -h / 2)
        mb.cylinder(prod, r0=r, h=h, segs=8, m=base, rect=cell(3, i), cap_rect=strip(3, i))
        mb.cylinder(prod, r0=r, r1=0.014, h=0.05, segs=8, m=base @ T(0, 0, h), rect=strip(3, i), caps=(False, False))
        mb.cylinder(M("PlasticBlack"), r0=0.015, h=0.025, segs=6, m=base @ T(0, 0, h + 0.05))

    cereal(-0.32, -0.02, 15, 0)
    cereal(-0.08, 0.06, -8, 2)
    cereal(0.36, -0.1, 70, 1)
    cereal(0.12, 0.17, 0, 3, standing=True, lean=-18)
    snack(0.0, -0.17, 30, 0)
    snack(0.3, 0.12, -40, 3)
    can(-0.42, 0.18, 20, 0)
    can(-0.18, -0.2, -65, 1)
    can(0.22, -0.2, 10, 3)
    can(-0.25, 0.22, 95, 2)
    bottle(0.05, -0.02, 120, 2)
    bottle(-0.45, -0.15, 75, 0)
    ground(mb)
    center_xy(mb)
    return [obj(mb, col, name, "Products")]


@prop("wall")
def build_clipboard(col, name):
    """Freezer temperature log on a clipboard (hangs on the freezer front).
    Mount the origin at y = 1.35 m."""
    mb = MeshBuilder()
    mb.box((-0.115, -0.006, -0.16), (0.115, 0.0, 0.16), M("Hardboard"))
    mb.box((-0.104, -0.008, -0.15), (0.104, -0.006, 0.12), M("PaperLog"), rects={"-y": (0, 0, 1, 1)})
    clip = M("MetalLight")
    mb.box((-0.05, -0.02, 0.1), (0.05, -0.006, 0.14), clip)
    mb.cylinder(clip, r0=0.01, h=0.09, segs=6, m=T(-0.045, -0.016, 0.142) @ R(90, "y"))
    mb.tube((0.07, -0.009, 0.12), (0.075, -0.012, -0.05), 0.004, M("RedPlastic"), segs=5)
    return [obj(mb, col, name, "Clipboard")]


@prop("wall")
def build_breaker_sparks(col, name):
    """Emissive spark streaks spraying from the origin plus a soot mark on the wall plane.
    Place the origin where the sparks come from (e.g. on the breaker panel)."""
    mb = MeshBuilder()
    mb.poly([(-0.16, -0.003, -0.2), (0.16, -0.003, -0.2), (0.16, -0.003, 0.14), (-0.16, -0.003, 0.14)],
            M("Scorch"), uv="fit")
    rng = np.random.default_rng(9)
    hot, warm = M("Sparks"), M("SparksHot")
    for i in range(18):
        a = rng.random() * 2 * math.pi
        spread = 0.25 + rng.random() * 0.75
        d = Vector((math.cos(a) * spread, -1.0, math.sin(a) * spread * 0.8 + 0.25)).normalized()
        speed = 0.08 + rng.random() * 0.12
        p0 = Vector((0, -0.01, 0)) + d * 0.015
        p1 = p0 + d * speed * 0.6
        p2 = p1 + d * speed * 0.5 + Vector((0, 0, -0.03 - rng.random() * 0.05))
        mat = hot if i % 3 else warm
        w = 0.004 + rng.random() * 0.003
        for a0, b0, wa in ((p0, p1, w), (p1, p2, w * 0.7)):
            axis = (b0 - a0).normalized()
            side1 = axis.cross(Vector((0, 0, 1))).normalized() * wa
            side2 = axis.cross(side1).normalized() * wa
            for s in (side1, side2):
                mb.poly([a0 - s, a0 + s, b0 + s * 0.4, b0 - s * 0.4], mat, uv="fit")
    for i in range(10):
        p = Vector((rng.random() * 0.3 - 0.15, -0.03 - rng.random() * 0.2, -0.05 - rng.random() * 0.4))
        mb.cbox(p, (0.008, 0.008, 0.008), warm, m=None)
    mb.ellipsoid((0, -0.012, 0), (0.016, 0.01, 0.016), hot, segs=6, rings=3)
    return [obj(mb, col, name, "Sparks")]


# --- furniture / clutter ---------------------------------------------------

@prop("floor")
def build_shopping_cart(col, name):
    """Wire shopping cart (reference 3): grey wire basket, red handle, four casters.
    Nose toward the front (-Y), handle at the back (+Y)."""
    mb = MeshBuilder()
    wire, grey, red, rub = M("WireGrid"), M("MetalGrey"), M("RedPlastic"), M("Rubber")
    BLb, BRb = Vector((-0.26, 0.42, 0.48)), Vector((0.26, 0.42, 0.48))
    FLb, FRb = Vector((-0.21, -0.45, 0.52)), Vector((0.21, -0.45, 0.52))
    BLt, BRt = Vector((-0.28, 0.46, 0.96)), Vector((0.28, 0.46, 0.96))
    FLt, FRt = Vector((-0.24, -0.5, 0.94)), Vector((0.24, -0.5, 0.94))
    tex = 0.36
    for quad in ((FLb, FRb, BRb, BLb), (FLb, BLb, BLt, FLt), (BRb, FRb, FRt, BRt), (FRb, FLb, FLt, FRt),
                 (BLb, BRb, BRt, BLt)):
        mb.poly(quad, wire, uv="world", texel=tex)
    for a, b in ((BLt, BRt), (BRt, FRt), (FRt, FLt), (FLt, BLt), (BLb, BRb), (BRb, FRb), (FRb, FLb), (FLb, BLb),
                 (BLb, BLt), (BRb, BRt), (FLb, FLt), (FRb, FRt)):
        mb.bar(a, b, 0.014, grey)
    hl, hr = Vector((-0.29, 0.56, 1.0)), Vector((0.29, 0.56, 1.0))
    mb.bar(BLt, hl, 0.016, grey)
    mb.bar(BRt, hr, 0.016, grey)
    mb.bar(hl + Vector((-0.01, 0, 0)), hr + Vector((0.01, 0, 0)), 0.034, red)
    # chassis
    for s in (-1, 1):
        back = Vector((s * 0.235, 0.4, 0.13))
        front = Vector((s * 0.175, -0.4, 0.13))
        mb.bar(back, front, 0.02, grey)
        mb.bar(back, Vector((s * 0.25, 0.42, 0.48)), 0.02, grey)
        mb.bar(front, Vector((s * 0.2, -0.43, 0.52)), 0.016, grey)
    mb.poly([(-0.19, -0.3, 0.16), (0.19, -0.3, 0.16), (0.22, 0.34, 0.16), (-0.22, 0.34, 0.16)], wire,
            uv="world", texel=tex)
    for x, y in ((-0.235, 0.4), (0.235, 0.4), (-0.175, -0.4), (0.175, -0.4)):
        mb.box((x - 0.012, y - 0.03, 0.06), (x + 0.012, y + 0.01, 0.13), grey)
        mb.cylinder(rub, r0=0.055, h=0.028, segs=8, m=T(x - 0.014, y - 0.01, 0.055) @ R(90, "y"))
    ground(mb)
    return [obj(mb, col, name, "ShoppingCart")]


@prop("floor")
def build_cardboard_box_a(col, name):
    """Closed, taped medium box."""
    mb = MeshBuilder()
    card_box(mb, 0, 0, 0, 0.5, 0.38, 0.34)
    return [obj(mb, col, name, "Box")]


@prop("floor")
def build_cardboard_box_b(col, name):
    """Large open box with its flaps folded out."""
    mb = MeshBuilder()
    items.open_box(mb, T(), 0.6, 0.45, 0.42, flaps=(118, 112, 128, 104))
    return [obj(mb, col, name, "Box")]


@prop("floor")
def build_cardboard_box_c(col, name):
    """Small box, lid half open."""
    mb = MeshBuilder()
    items.open_box(mb, T(), 0.36, 0.3, 0.26, flaps=(20, 35, 95, 80))
    return [obj(mb, col, name, "Box")]


def _pallet(mb):
    """1.2 x 1.0 x 0.134 m pallet: bottom boards, three stringers, seven deck boards."""
    wood = M("Wood")
    for x in (-0.56, 0.0, 0.56):
        mb.box((x - 0.04, -0.5, 0.022), (x + 0.04, 0.5, 0.112), wood, texel=0.6)
    for i in range(7):
        y = -0.45 + i * 0.15
        mb.box((-0.6, y - 0.05, 0.112), (0.6, y + 0.05, 0.134), wood, texel=0.6)
    for y in (-0.45, 0.0, 0.45):
        mb.box((-0.6, y - 0.05, 0.0), (0.6, y + 0.05, 0.022), wood, texel=0.6)


@prop("floor")
def build_pallet(col, name):
    """1.2 x 1.0 m wooden pallet."""
    mb = MeshBuilder()
    _pallet(mb)
    return [obj(mb, col, name, "Pallet")]


@prop("floor")
def build_pallet_boxes(col, name):
    """Pallet stacked with cardboard boxes (two full layers and a partial third)."""
    mb = MeshBuilder()
    _pallet(mb)
    rng = np.random.default_rng(11)
    z = 0.134
    for h in (0.4, 0.38):
        for ix in (-0.29, 0.29):
            for iy in (-0.24, 0.24):
                card_box(mb, ix + rng.random() * 0.02 - 0.01, iy + rng.random() * 0.02 - 0.01, z, 0.56, 0.46, h,
                         rot=rng.random() * 4 - 2)
        z += h
    card_box(mb, -0.28, 0.2, z, 0.55, 0.45, 0.36, rot=4)
    card_box(mb, 0.3, 0.22, z, 0.5, 0.42, 0.3, rot=-6)
    return [obj(mb, col, name, "PalletBoxes")]


@prop("floor")
def build_mop_bucket(col, name):
    """Yellow janitor's mop bucket with a wringer, dirty water and casters."""
    mb = MeshBuilder()
    yellow, grey, water, rub, black = (M("PlasticYellow"), M("MetalGrey"), M("Water"), M("Rubber"),
                                       M("PlasticBlack"))
    b0 = [Vector(p) for p in ((-0.17, -0.22, 0.1), (0.17, -0.22, 0.1), (0.17, 0.22, 0.1), (-0.17, 0.22, 0.1))]
    b1 = [Vector(p) for p in ((-0.2, -0.26, 0.44), (0.2, -0.26, 0.44), (0.2, 0.26, 0.44), (-0.2, 0.26, 0.44))]
    i1 = [Vector((p.x * 0.92, p.y * 0.94, 0.44)) for p in b1]
    i0 = [Vector((p.x * 0.92, p.y * 0.92, 0.13)) for p in b0]
    mb.poly(b0[::-1], yellow)
    for k in range(4):
        j = (k + 1) % 4
        mb.poly([b0[k], b0[j], b1[j], b1[k]], yellow, texel=0.3)
        mb.poly([i0[j], i0[k], i1[k], i1[j]], yellow, texel=0.3)
        mb.poly([b1[k], b1[j], i1[j], i1[k]], yellow, texel=0.3)
    wl = [i0[k].lerp(i1[k], 0.6) for k in range(4)]
    mb.poly(wl, water, uv="world", texel=0.3)
    mb.box((-0.19, -0.25, 0.06), (0.19, 0.25, 0.1), grey)
    for x in (-0.15, 0.15):
        for y in (-0.21, 0.21):
            mb.cylinder(rub, r0=0.03, h=0.025, segs=6, m=T(x - 0.0125, y, 0.03) @ R(90, "y"))
    mb.box((-0.17, 0.06, 0.44), (0.17, 0.27, 0.62), grey, texel=0.3)
    mb.box((-0.12, 0.02, 0.5), (0.12, 0.06, 0.6), grey)
    mb.bar((0.15, 0.2, 0.62), (0.15, 0.18, 0.98), 0.025, grey)
    mb.bar((0.15, 0.18, 0.98), (0.15, -0.05, 1.0), 0.025, grey)
    mb.cylinder(black, r0=0.018, h=0.1, segs=6, m=T(0.15, -0.05, 1.0) @ R(90, "x") @ T(0, 0, -0.05))
    mb.bar((-0.12, -0.27, 0.42), (0.12, -0.27, 0.42), 0.015, grey)
    return [obj(mb, col, name, "MopBucket")]


@prop("floor")
def build_trash_bin(col, name):
    """Octagonal olive plastic bin with a black liner folded over the rim."""
    mb = MeshBuilder()
    bin_m, bag = M("PlasticOlive"), M("BagBlack")
    ph = math.pi / 8
    mb.cylinder(bin_m, r0=0.2, r1=0.235, h=0.72, segs=8, caps=(True, False), smooth=False, texel=0.4, phase=ph)
    # liner inside the bin (faces turned inward), folded over the rim
    inner = MeshBuilder()
    inner.cylinder(bag, r0=0.19, r1=0.226, h=0.72, segs=8, caps=(False, False), smooth=False, phase=ph)
    inner.faces = [(tuple(reversed(f[0])), list(reversed(f[1])), f[2], f[3]) for f in inner.faces]
    mb.merge(inner, T(0, 0, 0.02))
    mb.cylinder(bag, r0=0.243, r1=0.24, h=0.08, segs=8, m=T(0, 0, 0.66), caps=(False, False), smooth=False,
                phase=ph)
    for i in range(8):   # flat ring joining the outer fold to the liner
        a0, a1 = ph + 2 * math.pi * i / 8, ph + 2 * math.pi * (i + 1) / 8
        mb.poly([(math.cos(a0) * 0.226, math.sin(a0) * 0.226, 0.74), (math.cos(a0) * 0.24, math.sin(a0) * 0.24, 0.74),
                 (math.cos(a1) * 0.24, math.sin(a1) * 0.24, 0.74), (math.cos(a1) * 0.226, math.sin(a1) * 0.226, 0.74)],
                bag)
    mb.ellipsoid((0, 0, 0.2), (0.16, 0.15, 0.16), bag, segs=6, rings=4, jitter=0.15, seed=4, flat_bottom=0.03)
    return [obj(mb, col, name, "TrashBin")]


@prop("floor")
def build_baler(col, name):
    """Vertical cardboard baler (1.5 x 0.95 x 2.3 m): chamber door with a grille, hazard
    band, control box and warning labels."""
    mb = MeshBuilder()
    olive, grey, chamber, hz, ctrl, lab = (M("MetalOlive"), M("MetalGrey"), M("BalerChamber"), M("Hazard"),
                                           M("ControlBox"), M("Labels"))
    mb.box((-0.75, -0.475, 0.06), (0.75, 0.475, 1.6), olive, texel=0.6)
    mb.box((-0.7, -0.42, 1.6), (0.7, 0.42, 2.12), olive, texel=0.6)
    mb.box((-0.7, -0.435, 1.6), (0.7, -0.42, 1.72), hz, texel=0.25)
    mb.cylinder(grey, r0=0.09, h=0.18, segs=8, m=T(0, 0, 2.12))
    mb.cylinder(grey, r0=0.11, h=0.03, segs=8, m=T(0, 0, 2.27))
    for x in (-0.68, 0.68):
        for y in (-0.4, 0.4):
            mb.box((x - 0.06, y - 0.06, 0), (x + 0.06, y + 0.06, 0.06), grey)
    # chamber door
    mb.box((-0.62, -0.5, 0.14), (0.42, -0.475, 1.46), grey, texel=0.6)
    mb.box((-0.54, -0.505, 0.46), (0.34, -0.5, 1.38), chamber, rects={"-y": (0, 0, 1, 1)})
    for z in (0.3, 0.38):
        mb.box((-0.54, -0.52, z), (0.34, -0.5, z + 0.04), olive)
    mb.box((0.3, -0.56, 0.75), (0.34, -0.5, 1.05), M("PlasticBlack"))
    for z in (0.3, 1.25):
        mb.cylinder(grey, r0=0.02, h=0.14, segs=6, m=T(-0.63, -0.5, z))
    # control box and labels
    mb.box((0.48, -0.54, 1.0), (0.72, -0.475, 1.32), grey, rects={"-y": (0, 0, 1, 1)}, mats={"-y": ctrl})
    mb.box((-0.3, -0.437, 1.78), (-0.06, -0.42, 2.0), lab, rects={"-y": (0.0, 0.5, 0.5, 1.0)})
    mb.box((0.05, -0.437, 1.78), (0.29, -0.42, 2.0), lab, rects={"-y": (0.5, 0.5, 1.0, 1.0)})
    mb.box((0.5, -0.437, 1.85), (0.62, -0.42, 1.97), lab, rects={"-y": (0.0, 0.0, 0.5, 0.5)})
    return [obj(mb, col, name, "Baler")]


@prop("floor")
def build_break_table(col, name):
    """Break-room table, 1.2 x 0.8 m, laminate top on grey metal legs."""
    mb = MeshBuilder()
    top, edge, grey = M("Laminate"), M("MetalDark"), M("MetalGrey")
    mb.box((-0.6, -0.4, 0.72), (0.6, 0.4, 0.75), edge, mats={"+z": top}, texel=0.6)
    for x in (-0.54, 0.54):
        for y in (-0.34, 0.34):
            mb.box((x - 0.02, y - 0.02, 0), (x + 0.02, y + 0.02, 0.72), grey)
    for y in (-0.34, 0.34):
        mb.box((-0.52, y - 0.012, 0.66), (0.52, y + 0.012, 0.72), grey)
    mb.cylinder(M("PlasticBeige"), r0=0.035, r1=0.042, h=0.1, segs=6, m=T(0.3, -0.12, 0.75), texel=0.2)
    return [obj(mb, col, name, "BreakTable")]


@prop("floor")
def build_chair(col, name):
    """Stackable break-room chair: olive plastic shell on tube legs, back toward +Y."""
    mb = MeshBuilder()
    shell, grey = M("ChairShell"), M("MetalGrey")
    mb.box((-0.21, -0.21, 0.43), (0.21, 0.21, 0.46), shell, texel=0.4)
    mb.box((-0.2, -0.015, 0.0), (0.2, 0.015, 0.32), shell, m=T(0, 0.215, 0.53) @ R(-8, "x"), texel=0.4)
    for x in (-0.18, 0.18):
        for y in (-0.18, 0.18):
            mb.tube((x * 1.08, y * 1.08, 0.0), (x, y, 0.43), 0.011, grey, segs=6)
        mb.tube((x, 0.18, 0.46), (x, 0.24, 0.62), 0.011, grey, segs=6)
        mb.tube((x * 1.04, -0.187, 0.12), (x * 1.04, 0.187, 0.12), 0.009, grey, segs=5)   # side stretcher
    return [obj(mb, col, name, "Chair")]


@prop("floor")
def build_vending_machine(col, name):
    """Snack vending machine (0.9 x 0.8 x 1.85 m) with an emissive product window and header."""
    mb = MeshBuilder()
    body, panel, keypad, black = M("MetalDark"), M("VendingPanel"), M("VendingKeypad"), M("PlasticBlack")
    mb.box((-0.45, -0.4, 0.05), (0.45, 0.4, 1.85), body, texel=0.6)
    mb.box((-0.43, -0.38, 0.0), (0.43, 0.38, 0.05), black)
    yf = -0.404
    mb.poly([(-0.42, yf, 0.56), (0.18, yf, 0.56), (0.18, yf, 1.62), (-0.42, yf, 1.62)], panel, uv="fit",
            rect=(0.004, 0.004, 0.996, 0.871))
    mb.poly([(-0.42, yf, 1.66), (0.42, yf, 1.66), (0.42, yf, 1.82), (-0.42, yf, 1.82)], panel, uv="fit",
            rect=(0.004, 0.879, 0.996, 0.996))
    mb.poly([(0.22, yf, 0.95), (0.42, yf, 0.95), (0.42, yf, 1.45), (0.22, yf, 1.45)], keypad, uv="fit")
    for x0, x1, z0, z1 in ((-0.44, 0.2, 0.53, 0.56), (-0.44, 0.2, 1.62, 1.65), (-0.44, -0.42, 0.53, 1.65),
                           (0.18, 0.2, 0.53, 1.65)):
        mb.box((x0, -0.42, z0), (x1, -0.4, z1), M("MetalGrey"))
    mb.box((-0.4, -0.412, 0.16), (0.16, -0.4, 0.4), black)
    mb.box((-0.36, -0.43, 0.3), (0.12, -0.412, 0.36), M("MetalGrey"))
    mb.box((0.26, -0.415, 0.6), (0.36, -0.4, 0.68), black)
    return [obj(mb, col, name, "VendingMachine")]


@prop("wall")
def build_time_clock(col, name):
    """Punch clock with a card rack. Mount the origin at y = 1.4 m."""
    mb = MeshBuilder()
    body, grey = M("PlasticBeige"), M("MetalGrey")
    mb.box((-0.21, -0.13, -0.17), (0.0, 0.0, 0.17), body, texel=0.3)
    yf = -0.1315
    mb.poly([(-0.2, yf, 0.0), (-0.01, yf, 0.0), (-0.01, yf, 0.16), (-0.2, yf, 0.16)], M("ClockFace"), uv="fit")
    mb.poly([(-0.2, yf, -0.16), (-0.01, yf, -0.16), (-0.01, yf, -0.01), (-0.2, yf, -0.01)], M("TimeClockBody"),
            uv="fit")
    mb.box((0.04, -0.045, -0.2), (0.21, 0.0, 0.2), grey, texel=0.3)
    for z in (0.02, -0.17):
        mb.box((0.045, -0.06, z), (0.205, -0.045, z + 0.1), grey)
        for k in range(5):
            x = 0.055 + k * 0.03
            mb.poly([(x, -0.0515, z + 0.03), (x + 0.024, -0.0515, z + 0.03), (x + 0.024, -0.0515, z + 0.15),
                     (x, -0.0515, z + 0.15)], M("TimeCard"), uv="fit")
    return [obj(mb, col, name, "TimeClock")]


@prop("floor")
def build_manager_desk(col, name):
    """Steel office desk (1.5 x 0.75 m) with a drawer pedestal on the left and a few papers."""
    mb = MeshBuilder()
    body, top, drawers, edge = M("MetalOlive"), M("LaminateDark"), M("Drawers"), M("MetalGrey")
    mb.box((-0.75, -0.375, 0.73), (0.75, 0.375, 0.76), edge, mats={"+z": top}, texel=0.6)
    mb.box((-0.73, -0.36, 0.03), (-0.33, 0.36, 0.73), body, rects={"-y": (0, 0, 1, 1)}, mats={"-y": drawers},
           texel=0.6)
    mb.box((-0.71, -0.34, 0.0), (-0.35, 0.34, 0.03), M("MetalDark"))
    mb.box((0.7, -0.36, 0.0), (0.73, 0.36, 0.73), body, texel=0.6)
    mb.box((-0.33, 0.33, 0.25), (0.7, 0.36, 0.73), body, texel=0.6)
    for x0, y0, rot, mat in ((-0.5, -0.05, 8, "PaperLog"), (-0.42, 0.08, -14, "Newsprint")):
        mb.poly([(-0.11, -0.15, 0), (0.11, -0.15, 0), (0.11, 0.15, 0), (-0.11, 0.15, 0)], M(mat), uv="fit",
                m=T(x0, y0, 0.7605) @ R(rot, "z"))
    return [obj(mb, col, name, "ManagerDesk")]


@prop("floor")
def build_crt_monitor(col, name):
    """Beige CRT monitor with an emissive green terminal screen (screen faces -Y)."""
    mb = MeshBuilder()
    beige, screen, black = M("PlasticBeige"), M("CRTScreen"), M("PlasticBlack")
    mb.box((-0.12, -0.12, 0.0), (0.12, 0.1, 0.03), beige)
    mb.box((-0.05, -0.05, 0.03), (0.05, 0.05, 0.06), beige)
    mb.box((-0.19, -0.2, 0.06), (0.19, -0.14, 0.42), beige, texel=0.3)
    f = [Vector(p) for p in ((-0.17, -0.14, 0.08), (0.17, -0.14, 0.08), (0.17, -0.14, 0.40), (-0.17, -0.14, 0.40))]
    b = [Vector(p) for p in ((-0.11, 0.18, 0.12), (0.11, 0.18, 0.12), (0.11, 0.18, 0.34), (-0.11, 0.18, 0.34))]
    for k in range(4):
        j = (k + 1) % 4
        mb.poly([f[j], f[k], b[k], b[j]], beige, texel=0.3)
    mb.poly(b[::-1], beige, texel=0.3)
    mb.poly([(-0.155, -0.2015, 0.11), (0.155, -0.2015, 0.11), (0.155, -0.2015, 0.38), (-0.155, -0.2015, 0.38)],
            screen, uv="fit")
    for x in (0.08, 0.12, 0.16):
        mb.box((x - 0.012, -0.205, 0.075), (x + 0.012, -0.2, 0.09), black)
    mb.box((-0.17, -0.205, 0.078), (-0.16, -0.2, 0.088), M("GreenLight"))
    return [obj(mb, col, name, "CRTMonitor")]


@prop("floor")
def build_office_chair(col, name):
    """Swivel office chair: five-star base, gas lift, dark fabric seat and back (back at +Y)."""
    mb = MeshBuilder()
    black, fabric, grey, rub = M("PlasticBlack"), M("FabricDark"), M("MetalGrey"), M("Rubber")
    for i in range(5):
        a = 2 * math.pi * i / 5 + math.pi / 2
        end = Vector((math.cos(a) * 0.3, math.sin(a) * 0.3, 0.07))
        mb.bar((0, 0, 0.1), end, 0.035, black, d=0.03)
        mb.cylinder(rub, r0=0.026, h=0.024, segs=6, m=T(end.x, end.y, 0.026) @ R(90, "z") @ R(90, "y")
                    @ T(0, 0, -0.012))
    mb.cylinder(grey, r0=0.025, h=0.34, segs=6, m=T(0, 0, 0.08))
    mb.cylinder(black, r0=0.035, h=0.12, segs=6, m=T(0, 0, 0.08))
    mb.box((-0.2, -0.2, 0.4), (0.2, 0.2, 0.43), black)
    mb.box((-0.25, -0.25, 0.43), (0.25, 0.23, 0.51), fabric, texel=0.3)
    mb.bar((0, 0.15, 0.42), (0, 0.27, 0.6), 0.05, black, d=0.02)
    mb.box((-0.22, -0.03, 0.0), (0.22, 0.03, 0.5), fabric, m=T(0, 0.27, 0.56) @ R(-10, "x"), texel=0.3)
    for s in (-1, 1):
        mb.bar((s * 0.22, 0.05, 0.45), (s * 0.24, 0.05, 0.64), 0.025, black)
        mb.box((s * 0.24 - 0.035, -0.12, 0.64), (s * 0.24 + 0.035, 0.12, 0.67), black)
    return [obj(mb, col, name, "OfficeChair")]


@prop("floor")
def build_intercom_mic(col, name):
    """Desk PA microphone: base with a red push-to-talk button, gooseneck, mic head toward -Y."""
    mb = MeshBuilder()
    black, metal = M("PlasticBlack"), M("MetalLight")
    mb.box((-0.075, -0.065, 0.0), (0.075, 0.065, 0.03), black)
    mb.box((-0.065, -0.055, 0.03), (0.065, 0.055, 0.042), black)
    mb.box((-0.028, -0.05, 0.042), (0.028, -0.02, 0.052), M("RedPlastic"))
    pts = [Vector(p) for p in ((0, 0.025, 0.042), (0, 0.025, 0.12), (0, 0.005, 0.2), (0, -0.035, 0.26),
                               (0, -0.08, 0.29))]
    for a, b in zip(pts, pts[1:]):
        mb.tube(a, b, 0.008, metal, segs=6)
    d = (pts[-1] - pts[-2]).normalized()
    mb.tube(pts[-1], pts[-1] + d * 0.065, 0.02, black, segs=8, r1=0.024)
    mb.cylinder(metal, r0=0.024, h=0.003, segs=8, m=look_matrix(pts[-1] + d * 0.065, pts[-1] + d * 0.07))
    mb.tube((0, 0.065, 0.012), (0, 0.13, 0.006), 0.005, black, segs=4)
    return [obj(mb, col, name, "IntercomMic")]


@prop("wall")
def build_breaker_panel(col, name):
    """Grey breaker box (0.5 x 0.7 x 0.12 m) with a conduit. `Door` is hinged on the left
    edge and opens outward with a negative Godot rotation.y. Mount the origin at y = 1.5 m."""
    grey, light = M("MetalGrey"), M("MetalLight")
    mb = MeshBuilder()
    t = 0.012
    mb.box((-0.25, -0.012, -0.35), (0.25, 0.0, 0.35), grey)
    mb.box((-0.25, -0.12, 0.35 - t), (0.25, -0.012, 0.35), grey)
    mb.box((-0.25, -0.12, -0.35), (0.25, -0.012, -0.35 + t), grey)
    mb.box((-0.25, -0.12, -0.35 + t), (-0.25 + t, -0.012, 0.35 - t), grey)
    mb.box((0.25 - t, -0.12, -0.35 + t), (0.25, -0.012, 0.35 - t), grey)
    mb.poly([(-0.238, -0.0125, -0.338), (0.238, -0.0125, -0.338), (0.238, -0.0125, 0.338),
             (-0.238, -0.0125, 0.338)], M("BreakerInside"), uv="fit")
    mb.cylinder(grey, r0=0.022, h=0.4, segs=6, m=T(0.1, -0.06, 0.35))
    mb.box((0.07, -0.09, 0.35), (0.13, -0.03, 0.39), light)
    door = MeshBuilder()
    face = M("BreakerDoor")
    door.box((0.002, -0.0075, -0.348), (0.498, 0.0075, 0.348), grey, rects={"-y": (0, 0, 1, 1)}, mats={"-y": face})
    door.box((0.44, -0.03, -0.06), (0.47, -0.0075, 0.06), light)
    door.cylinder(M("PlasticBlack"), r0=0.012, h=0.01, segs=6, m=T(0.455, -0.03, 0.09) @ R(90, "x"))
    for z in (-0.25, 0.25):
        door.cylinder(light, r0=0.007, h=0.06, segs=6, m=T(0.0, -0.008, z - 0.03))
    b = obj(mb, col, name, "BreakerPanel")
    d = obj(door, col, name, "Door", location=(-0.25, -0.1275, 0.0))
    parent(d, b)
    return [b]


@prop("floor")
def build_walkie_talkie(col, name):
    """Black walkie-talkie standing upright (front toward -Y)."""
    mb = MeshBuilder()
    black = M("PlasticBlack")
    mb.box((-0.03, -0.018, 0.0), (0.03, 0.018, 0.13), black, rects={"-y": (0, 0, 1, 1)}, mats={"-y": M("Walkie")})
    mb.cylinder(black, r0=0.0065, r1=0.005, h=0.085, segs=6, m=T(-0.016, 0.004, 0.13))
    mb.cylinder(M("MetalGrey"), r0=0.008, h=0.014, segs=6, m=T(0.014, 0.0, 0.13))
    mb.box((-0.034, -0.008, 0.07), (-0.03, 0.008, 0.1), M("OrangePlastic"))
    mb.box((-0.02, 0.018, 0.04), (0.02, 0.024, 0.11), black)
    return [obj(mb, col, name, "Walkie")]


@prop("floor")
def build_sink(col, name):
    """Janitor's utility sink on legs (back toward +Y, against the wall), faucet on a splash."""
    mb = MeshBuilder()
    steel, inside, grey = M("Steel"), M("SinkInside"), M("MetalGrey")
    mb.box((-0.3, -0.25, 0.6), (0.3, 0.25, 0.9), steel, skip=("+z",), texel=0.4)
    mb.box((-0.27, -0.22, 0.63), (0.27, 0.22, 0.9), steel, skip=("+z",), inward=True, texel=0.4,
           mats={"-z": None})
    mb.poly([(-0.27, -0.22, 0.63), (0.27, -0.22, 0.63), (0.27, 0.22, 0.63), (-0.27, 0.22, 0.63)], inside, uv="fit")
    for x0, y0, x1, y1 in ((-0.3, -0.25, 0.3, -0.22), (-0.3, 0.22, 0.3, 0.25), (-0.3, -0.22, -0.27, 0.22),
                           (0.27, -0.22, 0.3, 0.22)):
        mb.poly([(x0, y0, 0.9), (x1, y0, 0.9), (x1, y1, 0.9), (x0, y1, 0.9)], steel)
    for x in (-0.26, 0.26):
        for y in (-0.21, 0.21):
            mb.box((x - 0.018, y - 0.018, 0.0), (x + 0.018, y + 0.018, 0.6), grey)
    mb.box((-0.3, 0.22, 0.9), (0.3, 0.25, 1.15), steel, texel=0.4)
    mb.tube((0, 0.22, 1.05), (0, 0.08, 1.05), 0.012, M("MetalLight"), segs=6)
    mb.tube((0, 0.08, 1.05), (0, 0.08, 0.98), 0.012, M("MetalLight"), segs=6)
    for x in (-0.09, 0.09):
        mb.cylinder(M("MetalLight"), r0=0.02, h=0.03, segs=6, m=T(x, 0.22, 1.06) @ R(90, "x"))
    return [obj(mb, col, name, "Sink")]


@prop("floor")
def build_newspaper_debris(col, name):
    """Scattered newspaper sheets, crumpled paper, receipts and cardboard scraps (reference 3)."""
    mb = MeshBuilder()
    news, card, paper = M("Newsprint"), M("Cardboard"), M("PaperLog")
    rng = np.random.default_rng(21)
    for i in range(7):
        w, d = 0.3 + rng.random() * 0.15, 0.24 + rng.random() * 0.1
        x, y = rng.random() * 1.3 - 0.65, rng.random() * 1.1 - 0.55
        lift = math.radians(4 + rng.random() * 18)
        m = T(x, y, 0.002 + i * 0.001) @ R(rng.random() * 360, "z")
        mb.poly([(-w / 2, -d / 2, 0), (0, -d / 2, 0), (0, d / 2, 0), (-w / 2, d / 2, 0)], news, m=m, uv="fit",
                rect=(0, 0, 0.5, 1))
        hx, hz = math.cos(lift) * w / 2, math.sin(lift) * w / 2
        mb.poly([(0, -d / 2, 0), (hx, -d / 2, hz), (hx, d / 2, hz), (0, d / 2, 0)], news, m=m, uv="fit",
                rect=(0.5, 0, 1, 1))
    for i in range(6):
        p = (rng.random() * 1.4 - 0.7, rng.random() * 1.2 - 0.6, 0.035)
        mb.ellipsoid(p, (0.045, 0.04, 0.035), news if i % 2 else paper, segs=5, rings=3, jitter=0.3, seed=i,
                     flat_bottom=0.0)
    for i in range(3):
        m = T(rng.random() * 1.2 - 0.6, rng.random() * 1.0 - 0.5, 0.004) @ R(rng.random() * 360, "z")
        mb.poly([(-0.12, -0.08, 0), (0.12, -0.08, 0), (0.1, 0.09, 0), (-0.13, 0.07, 0)], card, m=m, texel=0.5)
    for i in range(3):
        m = T(rng.random() * 1.2 - 0.6, rng.random() * 1.0 - 0.5, 0.005) @ R(rng.random() * 360, "z")
        mb.poly([(-0.02, -0.09, 0), (0.02, -0.09, 0), (0.02, 0.09, 0), (-0.02, 0.09, 0)], paper, m=m, uv="fit",
                rect=(0.1, 0.1, 0.4, 0.9))
    ground(mb)
    center_xy(mb)
    return [obj(mb, col, name, "Debris")]


@prop("floor")
def build_safe(col, name):
    """Dark green steel floor safe with a dial and a three-spoke handle (door faces -Y)."""
    mb = MeshBuilder()
    body, front, metal = M("MetalSafe"), M("SafeFront"), M("MetalLight")
    mb.box((-0.275, -0.275, 0.04), (0.275, 0.275, 0.7), body, rects={"-y": (0, 0, 1, 1)}, mats={"-y": front},
           texel=0.5)
    for x in (-0.23, 0.23):
        for y in (-0.23, 0.23):
            mb.box((x - 0.03, y - 0.03, 0.0), (x + 0.03, y + 0.03, 0.04), M("MetalDark"))
    mb.cylinder(metal, r0=0.05, h=0.02, segs=8, m=T(0.0, -0.275, 0.5) @ R(90, "x"))
    mb.cylinder(M("PlasticBlack"), r0=0.035, h=0.03, segs=8, m=T(0.0, -0.275, 0.5) @ R(90, "x"))
    hub = Vector((0.13, -0.3, 0.33))
    mb.cylinder(metal, r0=0.02, h=0.03, segs=6, m=T(0.13, -0.275, 0.33) @ R(90, "x"))
    for i in range(3):
        a = 2 * math.pi * i / 3 + 0.4
        mb.bar(hub, hub + Vector((math.cos(a) * 0.07, 0, math.sin(a) * 0.07)), 0.012, metal)
    for z in (0.18, 0.55):
        mb.cylinder(metal, r0=0.012, h=0.08, segs=6, m=T(-0.272, -0.278, z))
    return [obj(mb, col, name, "Safe")]
