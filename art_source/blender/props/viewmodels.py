"""First-person viewmodels (assets/models/viewmodels/vm_<tool>.glb).

Authored in camera space: the GLB origin is the camera, Blender +Y is the view direction
(Godot -Z), +X is screen right, +Z is up. Every item sits in the lower right of a FOV 95°
(vertical) camera, except the stock box which is held in both hands at the lower centre.
Arms run back past the screen edge so nothing visible comes closer than the 0.05 m near plane.
Each GLB holds `Arms` (gloves + orange sleeves) and `Item`; vm_flashlight also has the Empty
`LightPoint` at the lens (identity rotation, so its -Z in Godot is the camera's forward).
"""
from mathutils import Matrix, Vector

import items
import mats
from pxlib import MeshBuilder, R, S, T, empty, look_matrix

BUILDERS = {}


def viewmodel(fn):
    BUILDERS[fn.__name__[len("build_"):]] = fn
    return fn


def M(name):
    return mats.get(name)


def basis(forward, up=(0, 0, 1)):
    """Rotation whose local +Y is `forward` and local +Z is as close to `up` as possible."""
    f = Vector(forward).normalized()
    r = f.cross(Vector(up)).normalized()
    u = r.cross(f).normalized()
    return Matrix(((r.x, f.x, u.x, 0), (r.y, f.y, u.y, 0), (r.z, f.z, u.z, 0), (0, 0, 0, 1)))


def frame(origin, forward, up=(0, 0, 1)):
    return T(*origin) @ basis(forward, up)


def hand(mb, m, side=1.0, open_fingers=0.0):
    """Low-poly gloved hand closed around the local Y axis (the grip axis, pointing forward).
    Right hand for side = +1: the back of the hand is on the outer (+X) side, the four fingers
    wrap under the grip and curl up its inner side, the thumb crosses over the top.
    `open_fingers` (0..1) loosens the curl (fingers further from the axis)."""
    glove = M("Glove")

    def hbox(x0, y0, z0, x1, y1, z1):
        xa, xb = sorted((x0 * side, x1 * side))
        mb.box((xa, y0, z0), (xb, y1, z1), glove, m=m, texel=0.1)

    o = open_fingers * 0.012
    hbox(0.014, -0.05, -0.042, 0.046, 0.04, 0.028)                 # back of the hand / palm
    for i, (y, reach) in enumerate(((0.029, 0.0), (0.008, 0.004), (-0.013, 0.002), (-0.033, -0.006))):
        w = 0.0095
        hbox(-0.03 - reach, y - w, -0.047 - o, 0.03, y + w, -0.022 - o)     # under the grip
        hbox(-0.043 - reach - o, y - w, -0.04 - o, -0.021 - o, y + w, 0.006 + reach)   # curled tip
    hbox(-0.022, 0.0, 0.016, 0.03, 0.022, 0.036)                   # thumb across the top
    hbox(0.018, -0.03, 0.006, 0.04, 0.004, 0.034)                  # thumb base


def arm(mb, grip, forward, elbow, up=(0, 0, 1), side=1.0, open_fingers=0.0):
    """A gloved hand closed around an axis through `grip` along `forward`, and an orange sleeve
    from the wrist back to `elbow` (which should be outside the view)."""
    glove, sleeve = M("Glove"), M("OrangeFabric")
    m = frame(grip, forward, up)
    hand(mb, m, side, open_fingers)
    wrist = m @ Vector((side * 0.028, -0.044, -0.008))
    d = (Vector(elbow) - wrist).normalized()
    cuff = wrist + d * 0.05
    mb.tube(wrist, cuff, 0.03, glove, segs=8, r1=0.036, texel=0.1)
    mb.tube(cuff, cuff + d * 0.028, 0.046, sleeve, segs=8, texel=0.15)
    mb.tube(cuff + d * 0.028, Vector(elbow), 0.043, sleeve, segs=8, r1=0.055, texel=0.15)


def finish(col, name, arms_mb, item_mb, light_point=None):
    out = [arms_mb.to_object("%s__Arms" % name, col, export_name="Arms"),
           item_mb.to_object("%s__Item" % name, col, export_name="Item")]
    if light_point is not None:
        out.append(empty("%s__LightPoint" % name, col, location=light_point, export_name="LightPoint"))
    return out


@viewmodel
def build_vm_flashlight(col, name):
    """Black flashlight in the right hand, pointing ahead (reference 2's dark held object)."""
    grip, fwd = Vector((0.25, 0.42, -0.30)), Vector((-0.12, 1.0, 0.17))
    arms, item = MeshBuilder(), MeshBuilder()
    m = frame(grip, fwd)
    lens = m @ items.flashlight(item, m)
    arm(arms, grip, fwd, (0.43, 0.02, -0.6))
    return finish(col, name, arms, item, light_point=lens + (m.to_3x3() @ Vector((0, 0.004, 0))))


@viewmodel
def build_vm_mop(col, name):
    """Mop held near the top of its handle in the right hand, shaft running forward and down,
    strand head low at the bottom centre."""
    grip = Vector((0.27, 0.42, -0.36))
    head_dir = (Vector((0.06, 1.2, -1.22)) - grip).normalized()
    arms, item = MeshBuilder(), MeshBuilder()
    items.mop(item, look_matrix(grip, grip - head_dir), top=0.06, bottom=1.0, head=0.27)
    arm(arms, grip, head_dir, (0.44, 0.04, -0.66))
    return finish(col, name, arms, item)


@viewmodel
def build_vm_price_gun(col, name):
    """Orange pricing labeler held by its pistol grip, nose forward."""
    grip = Vector((0.27, 0.40, -0.31))
    nose = Vector((-0.65, 0.75, 0.08)).normalized()
    up = Vector((0, 0, 1))
    side = up.cross(nose).normalized()
    up = nose.cross(side).normalized()
    gun = Matrix(((nose.x, side.x, up.x, grip.x), (nose.y, side.y, up.y, grip.y), (nose.z, side.z, up.z, grip.z),
                  (0, 0, 0, 1)))
    arms, item = MeshBuilder(), MeshBuilder()
    items.price_gun(item, gun)
    handle = (gun.to_3x3() @ Vector((0.042, 0.0, 0.095))).normalized()
    arm(arms, grip, handle, (0.44, 0.06, -0.64), up=-nose)
    return finish(col, name, arms, item)


@viewmodel
def build_vm_box_cutter(col, name):
    """Yellow box cutter in the right hand, blade forward."""
    grip, fwd = Vector((0.25, 0.40, -0.28)), Vector((-0.3, 1.0, 0.12))
    arms, item = MeshBuilder(), MeshBuilder()
    m = frame(grip, fwd)
    items.box_cutter(item, m @ T(0, 0.07, 0.0) @ R(-30, "y") @ S(1.25))
    arm(arms, grip, fwd, (0.43, 0.02, -0.57))
    return finish(col, name, arms, item)


@viewmodel
def build_vm_keys(col, name):
    """Store key ring hanging from the right hand's thumb and index, keys dangling in front
    (drawn 1.4x life size so they read at the bottom of the screen)."""
    grip, fwd = Vector((0.25, 0.43, -0.25)), Vector((-0.22, 1.0, 0.08))
    arms, item = MeshBuilder(), MeshBuilder()
    m = frame(grip, fwd)
    ring_top = m @ Vector((-0.045, 0.05, 0.0))
    items.keyring(item, T(*ring_top) @ R(18, "z") @ R(-12, "x") @ S(1.6))
    arm(arms, grip, fwd, (0.42, 0.02, -0.56), open_fingers=0.3)
    return finish(col, name, arms, item)


@viewmodel
def build_vm_stock_box(col, name):
    """Stock box carried in both hands at the lower centre, printed side toward the camera."""
    arms, item = MeshBuilder(), MeshBuilder()
    items.stock_box(item, T(0, 0.58, -0.56) @ R(-8, "x"))
    for s in (-1, 1):
        grip = Vector((s * 0.215, 0.53, -0.44))
        arm(arms, grip, (s * -0.1, 1.0, 0.0), (s * 0.46, 0.08, -0.8), side=s)
    return finish(col, name, arms, item)
