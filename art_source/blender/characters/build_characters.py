"""Character model generator for Graveyard Shift (task 1).

Regenerates every character from nothing (no hand-edited data):

    blender -b -P art_source/blender/characters/build_characters.py
    blender -b -P art_source/blender/characters/build_characters.py -- --only monster manager
        (--only: quick iteration, exports just those GLBs and does not rewrite the .blend)

Writes
    assets/models/characters/employee_dale.glb, employee_rita.glb, employee_marcus.glb,
    assets/models/characters/manager.glb, monster.glb
    art_source/blender/characters/characters.blend   (one scene per character)

Conventions (docs/ARCHITECTURE.md, "Model orientation and scale"):
- 1 Blender unit = 1 m, characters face Blender -Y (Godot +Z), origin on the floor between the feet.
- One armature per character with the contract bone names; one mesh rigidly skinned to it
  (every vertex 100 % on one bone); one material; one 128 px texture painted here with numpy and
  sampled with 'Closest' so the glTF sampler (and Godot) use nearest filtering.
- glTF animation names are exactly the contract names (idle/walk/run/work/attack/reveal/talk).
  Looping is switched on per animation in the Godot .import files (glTF has no loop flag).

Animation authoring: every pose is written as rotations about the *armature* axes at rest
(X = character's left, -Y = forward, Z = up; +X rotation pitches the upper body forward and swings
a hanging limb backward) and converted to each bone's local frame. Every frame is keyed, so loops
are exact (first frame == last frame) and nothing depends on Bezier handles.
"""

import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Euler, Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
OUT_DIR = os.path.join(REPO, "assets", "models", "characters")
BLEND_PATH = os.path.join(HERE, "characters.blend")
FPS = 30
TEX_SIZE = 128
TAU = math.tau

HUMAN_BONES = [
    "root", "hips", "spine", "chest", "neck", "head",
    "upper_arm.L", "forearm.L", "hand.L", "upper_arm.R", "forearm.R", "hand.R",
    "thigh.L", "shin.L", "foot.L", "thigh.R", "shin.R", "foot.R",
]
MONSTER_BONES = HUMAN_BONES + ["ear.L", "ear.R", "jaw"]
PARENT = {
    "root": None, "hips": "root", "spine": "hips", "chest": "spine", "neck": "chest", "head": "neck",
    "upper_arm.L": "chest", "forearm.L": "upper_arm.L", "hand.L": "forearm.L",
    "upper_arm.R": "chest", "forearm.R": "upper_arm.R", "hand.R": "forearm.R",
    "thigh.L": "hips", "shin.L": "thigh.L", "foot.L": "shin.L",
    "thigh.R": "hips", "shin.R": "thigh.R", "foot.R": "shin.R",
    "ear.L": "head", "ear.R": "head", "jaw": "head",
}


# =============================================================================
# Colour helpers
# =============================================================================

def col(hex_str):
    h = hex_str.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], np.float32) / 255.0


def mul(c, f):
    return np.clip(np.asarray(c, np.float32) * f, 0.0, 1.0)


def lerp(a, b, t):
    return np.asarray(a, np.float32) + (np.asarray(b, np.float32) - np.asarray(a, np.float32)) * t


def value_noise(h, w, cell, rng):
    """Smooth blotchy noise in [0, 1], bilinear interpolation of a random grid."""
    gh, gw = h // cell + 2, w // cell + 2
    g = rng.random((gh, gw)).astype(np.float32)
    ys = np.arange(h) / cell
    xs = np.arange(w) / cell
    y0 = ys.astype(int)
    x0 = xs.astype(int)
    fy = (ys - y0)[:, None]
    fx = (xs - x0)[None, :]
    a = g[y0][:, x0]
    b = g[y0][:, x0 + 1]
    c = g[y0 + 1][:, x0]
    d = g[y0 + 1][:, x0 + 1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


# 3x5 pixel font (M, N, W wider). '1' = ink.
FONT = {
    "A": ["010", "101", "111", "101", "101"],
    "B": ["110", "101", "110", "101", "110"],
    "C": ["011", "100", "100", "100", "011"],
    "D": ["110", "101", "101", "101", "110"],
    "E": ["111", "100", "110", "100", "111"],
    "F": ["111", "100", "110", "100", "100"],
    "G": ["011", "100", "101", "101", "011"],
    "H": ["101", "101", "111", "101", "101"],
    "I": ["111", "010", "010", "010", "111"],
    "K": ["101", "101", "110", "101", "101"],
    "L": ["100", "100", "100", "100", "111"],
    "M": ["10001", "11011", "10101", "10001", "10001"],
    "N": ["1001", "1101", "1011", "1001", "1001"],
    "O": ["010", "101", "101", "101", "010"],
    "P": ["110", "101", "110", "100", "100"],
    "R": ["110", "101", "110", "101", "101"],
    "S": ["011", "100", "010", "001", "110"],
    "T": ["111", "010", "010", "010", "010"],
    "U": ["101", "101", "101", "101", "111"],
    "W": ["10001", "10001", "10101", "11011", "10001"],
    " ": ["00", "00", "00", "00", "00"],
}


def text_width(s):
    return sum(len(FONT[ch][0]) for ch in s) + max(0, len(s) - 1)


# =============================================================================
# Texture atlas
# =============================================================================

class Region:
    """A named rectangle of the atlas; all coordinates are local, origin top-left."""

    def __init__(self, atlas, name):
        self.atlas = atlas
        self.name = name
        self.x, self.y, self.w, self.h = atlas.rects[name]

    @property
    def view(self):
        return self.atlas.px[self.y:self.y + self.h, self.x:self.x + self.w]

    def fill(self, c):
        self.view[:] = c

    def rect(self, x, y, w, h, c):
        x0, y0 = max(0, int(x)), max(0, int(y))
        x1, y1 = min(self.w, int(x + w)), min(self.h, int(y + h))
        if x1 > x0 and y1 > y0:
            self.view[y0:y1, x0:x1] = c

    def dot(self, x, y, c):
        x, y = int(x), int(y)
        if 0 <= x < self.w and 0 <= y < self.h:
            self.view[y, x] = c

    def tones(self, tones, field):
        idx = np.clip((field * len(tones)).astype(int), 0, len(tones) - 1)
        self.view[:] = np.asarray(tones, np.float32)[idx]

    def text(self, x, y, s, c):
        for ch in s:
            glyph = FONT[ch]
            for gy, row in enumerate(glyph):
                for gx, bit in enumerate(row):
                    if bit == "1":
                        self.dot(x + gx, y + gy, c)
            x += len(glyph[0]) + 1

    def grad_y(self):
        return np.repeat(np.linspace(0.0, 1.0, self.h, dtype=np.float32)[:, None], self.w, 1)

    def grad_x(self):
        return np.repeat(np.linspace(0.0, 1.0, self.w, dtype=np.float32)[None, :], self.h, 0)


class Atlas:
    def __init__(self, name, regions, seed, size=TEX_SIZE):
        """regions: list of (name, w, h). Packed in shelves, tallest first."""
        self.name = name
        self.size = size
        self.px = np.zeros((size, size, 3), np.float32)
        self.rng = np.random.default_rng(seed)
        self.rects = {}
        x = y = shelf_h = 0
        for rname, w, h in sorted(regions, key=lambda r: (-r[2], -r[1])):
            if x + w > size:
                x, y, shelf_h = 0, y + shelf_h, 0
            if y + h > size:
                raise RuntimeError("atlas %s is full at region %s" % (name, rname))
            self.rects[rname] = (x, y, w, h)
            x += w
            shelf_h = max(shelf_h, h)

    def __getitem__(self, name):
        return Region(self, name)

    def to_image(self):
        img = bpy.data.images.new(self.name, self.size, self.size, alpha=False)
        rgba = np.ones((self.size, self.size, 4), np.float32)
        rgba[:, :, :3] = np.clip(self.px, 0.0, 1.0)
        img.pixels.foreach_set(np.ascontiguousarray(rgba[::-1]).ravel())
        img.update()
        img.pack()
        return img

    def uv(self, rname, s, t):
        """Maps (s, t) in [0, 1] (t = 1 at the top of the region) onto pixel centres of a region."""
        x, y, w, h = self.rects[rname]
        px = x + 0.5 + s * (w - 1)
        py = y + 0.5 + (1.0 - t) * (h - 1)
        return (px / self.size, 1.0 - py / self.size)


# =============================================================================
# Mesh building (lofts with box-projected atlas UVs, rigid bone weights)
# =============================================================================

def sec_rect(hx, hy, c=0.0):
    """Rectangle section (counter-clockwise), optionally with chamfered corners."""
    if c <= 0.0:
        return [(hx, -hy), (hx, hy), (-hx, hy), (-hx, -hy)]
    c = min(c, hx * 0.95, hy * 0.95)
    return [(hx, -hy + c), (hx, hy - c), (hx - c, hy), (-hx + c, hy),
            (-hx, hy - c), (-hx, -hy + c), (-hx + c, -hy), (hx - c, -hy)]


def sec_ellipse(hx, hy, n=8, phase=0.5):
    return [(hx * math.cos(TAU * (k + phase) / n), hy * math.sin(TAU * (k + phase) / n)) for k in range(n)]


class Builder:
    SIDES = ("left", "right", "back", "front", "top", "bottom")

    def __init__(self, atlas, bones):
        self.atlas = atlas
        self.bones = bones
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.verify()
        self.deform = self.bm.verts.layers.deform.verify()

    def loft(self, path, sections, bone, regions, hint=(1.0, 0.0, 0.0), caps=(True, True),
             proj=None, bias=(1.0, 1.0, 1.0), ragged=None):
        """Lofts `sections` (2D, counter-clockwise, all the same point count) along `path`.

        Section x follows `hint` (made perpendicular to the path); section y is tangent x hint.
        regions: {'front'|'back'|'left'|'right'|'top'|'bottom'|'side'|'all': atlas region}.
        proj: optional ((x0, y0, z0), (x1, y1, z1)) projection box shared by several parts.
        ragged: optional (ring index, max offset, rng): pushes that ring's vertices randomly along
        the path (torn hems).
        """
        if len(sections) == 1:
            sections = sections * len(path)
        assert len(sections) == len(path), "one section per path point"
        assert len({len(sec) for sec in sections}) == 1, "all sections need the same point count"
        pts = [Vector(p) for p in path]
        rings = []
        for i, p in enumerate(pts):
            if i == 0:
                t = pts[1] - p
            elif i == len(pts) - 1:
                t = p - pts[i - 1]
            else:
                t = pts[i + 1] - pts[i - 1]
            t.normalize()
            h = Vector(hint)
            s = (h - h.dot(t) * t).normalized()
            o = t.cross(s)
            ring = []
            for sx, sy in sections[i]:
                q = p + sx * s + sy * o
                if ragged is not None and i == (ragged[0] % len(pts)):
                    q = q + t * (ragged[1] * float(ragged[2].uniform(-1.0, 1.0)))
                ring.append(self.bm.verts.new(q))
            rings.append(ring)
        faces = []
        n = len(rings[0])
        for a, b in zip(rings, rings[1:]):
            for j in range(n):
                faces.append(self.bm.faces.new((a[j], a[(j + 1) % n], b[(j + 1) % n], b[j])))
        if caps[0]:
            faces.append(self.bm.faces.new(list(reversed(rings[0]))))
        if caps[1]:
            faces.append(self.bm.faces.new(rings[-1]))
        verts = [v for ring in rings for v in ring]
        self._finish(verts, faces, bone, regions, proj, bias)
        return verts

    def box(self, lo, hi, bone, regions, proj=None):
        """Axis-aligned box from lo to hi corner."""
        (x0, y0, z0), (x1, y1, z1) = lo, hi
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        return self.loft([(cx, cy, z0), (cx, cy, z1)], [sec_rect((x1 - x0) / 2, (y1 - y0) / 2)],
                         bone, regions, proj=proj)

    def _finish(self, verts, faces, bone, regions, proj, bias):
        gi = self.bones.index(bone)
        for v in verts:
            v[self.deform][gi] = 1.0
        if proj is None:
            lo = Vector((min(v.co.x for v in verts), min(v.co.y for v in verts), min(v.co.z for v in verts)))
            hi = Vector((max(v.co.x for v in verts), max(v.co.y for v in verts), max(v.co.z for v in verts)))
        else:
            lo, hi = Vector(proj[0]), Vector(proj[1])
        size = Vector((max(hi.x - lo.x, 1e-6), max(hi.y - lo.y, 1e-6), max(hi.z - lo.z, 1e-6)))
        for f in faces:
            f.smooth = False
            f.normal_update()
            nx, ny, nz = (abs(f.normal.x) * bias[0], abs(f.normal.y) * bias[1], abs(f.normal.z) * bias[2])
            if ny >= nx and ny >= nz:
                side = "front" if f.normal.y < 0 else "back"
            elif nx >= nz:
                side = "left" if f.normal.x > 0 else "right"
            else:
                side = "top" if f.normal.z > 0 else "bottom"
            region = regions.get(side)
            mirrored_side = False
            if region is None and side in ("left", "right"):
                region = regions.get("side")
                mirrored_side = region is not None
            if region is None:
                region = regions["all"]
            for loop in f.loops:
                p = loop.vert.co
                rx = (p.x - lo.x) / size.x
                ry = (p.y - lo.y) / size.y
                rz = (p.z - lo.z) / size.z
                if side == "front":
                    s, t = rx, rz
                elif side == "back":
                    s, t = 1.0 - rx, rz
                elif side == "left":
                    s, t = ry, rz
                elif side == "right":
                    s, t = (ry if mirrored_side else 1.0 - ry), rz
                elif side == "top":
                    s, t = rx, ry
                else:
                    s, t = rx, 1.0 - ry
                s = min(max(s, 0.0), 1.0)
                t = min(max(t, 0.0), 1.0)
                loop[self.uv].uv = self.atlas.uv(region, s, t)

    def to_object(self, name, scene, material):
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        me.materials.append(material)
        obj = bpy.data.objects.new(name, me)
        scene.collection.objects.link(obj)
        for b in self.bones:
            obj.vertex_groups.new(name=b)
        return obj


def make_material(name, image):
    mat = bpy.data.materials.new(name)
    if mat.node_tree is None:  # Blender < 5 needs use_nodes; 5.x always has a node tree
        mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.interpolation = "Closest"
    tex.location = (-400, 200)
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.85
    bsdf.inputs["Metallic"].default_value = 0.0
    return mat


def triangle_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


# =============================================================================
# Armature + animation
# =============================================================================

def build_armature(name, scene, joints, bones):
    """joints: {bone: (head, tail)}. Bones are created in `bones` order with PARENT links."""
    arm = bpy.data.armatures.new(name + "_rig")
    obj = bpy.data.objects.new(name + "_rig", arm)
    scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for b in bones:
        eb = arm.edit_bones.new(b)
        eb.head, eb.tail = joints[b]
        d = (Vector(joints[b][1]) - Vector(joints[b][0])).normalized()
        # Keep every bone's local Z pointing forward (-Y) where possible so axes are predictable:
        # for upright bones local X = +X, local Y = up, local Z = forward (Godot: X, Y up, Z front).
        eb.align_roll(Vector((0, 0, 1)) if abs(d.y) > 0.9 else Vector((0, -1, 0)))
    for b in bones:
        if PARENT[b]:
            arm.edit_bones[b].parent = arm.edit_bones[PARENT[b]]
            arm.edit_bones[b].use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    arm.display_type = "STICK"
    obj.show_in_front = True
    return obj


class Animator:
    """Keys poses given as armature-axis Euler angles (degrees) per bone, every frame."""

    def __init__(self, rig, prefix, ground_points=None):
        self.rig = rig
        self.prefix = prefix
        self.rest = {b.name: b.matrix_local.to_3x3() for b in rig.data.bones}
        self.rest_inv = {k: m.inverted() for k, m in self.rest.items()}
        # ground_points: [(bone, 'head'|'tail', rest height above floor)] used to plant the feet.
        self.ground_points = ground_points or []
        self.actions = {}
        self.loops = {}
        self.ground_speed = {}
        for pb in rig.pose.bones:
            pb.rotation_mode = "QUATERNION"

    def _apply(self, pose, hips_offset):
        for pb in self.rig.pose.bones:
            e = pose.get(pb.name, (0.0, 0.0, 0.0))
            r = Euler((math.radians(e[0]), math.radians(e[1]), math.radians(e[2])), "XYZ").to_matrix()
            pb.rotation_quaternion = (self.rest_inv[pb.name] @ r @ self.rest[pb.name]).to_quaternion()
            pb.location = (0.0, 0.0, 0.0)
        self.rig.pose.bones["hips"].location = self.rest_inv["hips"] @ Vector(hips_offset)

    def _contact(self):
        """(ground point index, armature y) of the lowest ground point (the planted foot)."""
        bpy.context.view_layer.update()
        best = None
        for i, (bone, end, rest_h) in enumerate(self.ground_points):
            pb = self.rig.pose.bones[bone]
            p = pb.head if end == "head" else pb.tail
            key = (p.z - rest_h, i, p.y)
            best = key if best is None or key < best else best
        return (best[1] % 2 if len(self.ground_points) == 4 else best[1], best[2])  # 0 = left foot, 1 = right

    def _ground_error(self):
        bpy.context.view_layer.update()
        lowest = None
        for bone, end, rest_h in self.ground_points:
            pb = self.rig.pose.bones[bone]
            p = pb.head if end == "head" else pb.tail
            h = p.z - rest_h
            lowest = h if lowest is None else min(lowest, h)
        return lowest or 0.0

    def action(self, name, seconds, pose_fn, loop=True, ground=True):
        """pose_fn(t) -> dict; t runs 0..1 over the clip (inclusive). Special key '@hips' = (x, y, z)
        armature-space offset of the hips. With ground=True the hips are raised/lowered every frame
        so the lowest foot point touches the floor (plus '@lift' metres)."""
        frames = max(1, round(seconds * FPS))
        act = bpy.data.actions.new("%s.%s" % (self.prefix, name))
        ad = self.rig.animation_data or self.rig.animation_data_create()
        ad.action = act
        prev = {}
        contacts = []
        for f in range(frames + 1):
            t = f / frames
            if loop and f == frames:
                t = 0.0  # exact seamless loop
            pose = pose_fn(t)
            offset = Vector(pose.get("@hips", (0.0, 0.0, 0.0)))
            self._apply(pose, offset)
            if ground and self.ground_points:
                offset.z -= self._ground_error() - pose.get("@lift", 0.0)
                self._apply(pose, offset)
                contacts.append(self._contact())
            for pb in self.rig.pose.bones:
                q = pb.rotation_quaternion.copy()
                if pb.name in prev and prev[pb.name].dot(q) < 0.0:
                    q.negate()
                    pb.rotation_quaternion = q
                prev[pb.name] = q
                pb.keyframe_insert("rotation_quaternion", frame=f, group=pb.name)
            self.rig.pose.bones["hips"].keyframe_insert("location", frame=f, group="hips")
        bag = act.layers[0].strips[0].channelbag(act.slots[0])
        for fc in bag.fcurves:
            for kp in fc.keyframe_points:
                kp.interpolation = "LINEAR"
        if contacts and name in ("walk", "run"):
            # Ground speed: how fast the planted foot slides backward; move the character at this
            # speed and the feet do not skate.
            speeds = []
            for (k0, y0), (k1, y1) in zip(contacts, contacts[1:]):
                if k0 == k1:
                    speeds.append((y1 - y0) * FPS)
            speeds.sort()
            v = speeds[len(speeds) // 2] if speeds else 0.0
            self.ground_speed[name] = v
            print("[characters] %-16s %-6s ground speed %.2f m/s" % (self.prefix, name, v))
        track = ad.nla_tracks.new()
        track.name = name
        strip = track.strips.new(name, 0, act)
        strip.mute = False
        ad.action = None
        self._apply({}, (0.0, 0.0, 0.0))
        self.actions[name] = act
        self.loops[name] = loop
        return act


def wave(t, freq=1.0, phase=0.0):
    return math.sin(TAU * (freq * t + phase))


def wavec(t, freq=1.0, phase=0.0):
    return math.cos(TAU * (freq * t + phase))


def smooth(a, b, x):
    """Smoothstep of x between a and b."""
    if b == a:
        return 1.0 if x >= b else 0.0
    u = min(max((x - a) / (b - a), 0.0), 1.0)
    return u * u * (3.0 - 2.0 * u)


def keyed(t, keys):
    """Interpolates between (time, pose) keys with smoothstep easing (component-wise)."""
    if t <= keys[0][0]:
        return dict(keys[0][1])
    for (t0, p0), (t1, p1) in zip(keys, keys[1:]):
        if t <= t1:
            u = smooth(t0, t1, t)
            out = {}
            for k in set(p0) | set(p1):
                a = p0.get(k, 0.0 if k == "@lift" else (0.0, 0.0, 0.0))
                b = p1.get(k, 0.0 if k == "@lift" else (0.0, 0.0, 0.0))
                if k == "@lift":
                    out[k] = a + (b - a) * u
                else:
                    out[k] = tuple(a[i] + (b[i] - a[i]) * u for i in range(3))
            return out
    return dict(keys[-1][1])


def add_pose(*poses):
    out = {}
    for p in poses:
        for k, v in p.items():
            if k.startswith("@"):
                if k == "@lift":
                    out[k] = out.get(k, 0.0) + v
                else:
                    a = out.get(k, (0.0, 0.0, 0.0))
                    out[k] = (a[0] + v[0], a[1] + v[1], a[2] + v[2])
            else:
                a = out.get(k, (0.0, 0.0, 0.0))
                out[k] = (a[0] + v[0], a[1] + v[1], a[2] + v[2])
    return out


def scale_pose(p, f):
    out = {}
    for k, v in p.items():
        out[k] = v * f if k == "@lift" else (v[0] * f, v[1] * f, v[2] * f)
    return out


# =============================================================================
# Humans: employees and the manager
# =============================================================================

def human_joints(p):
    sx, ex, wx, hx = p["shoulder"], p["elbow"], p["wrist"], p["hand_end"]
    lx = p["leg_x"]
    j = {
        "root": ((0, 0, 0), (0, 0, 0.15)),
        "hips": ((0, 0, p["hip_z"]), (0, 0, p["spine_z"])),
        "spine": ((0, 0, p["spine_z"]), (0, 0, p["chest_z"])),
        "chest": ((0, 0, p["chest_z"]), (0, 0, p["neck_z"])),
        "neck": ((0, 0, p["neck_z"]), (0, 0, p["head_z"])),
        "head": ((0, 0, p["head_z"]), (0, 0, p["head_top"])),
    }
    for side, m in (("L", 1), ("R", -1)):
        j["upper_arm." + side] = ((m * sx[0], sx[1], sx[2]), (m * ex[0], ex[1], ex[2]))
        j["forearm." + side] = ((m * ex[0], ex[1], ex[2]), (m * wx[0], wx[1], wx[2]))
        j["hand." + side] = ((m * wx[0], wx[1], wx[2]), (m * hx[0], hx[1], hx[2]))
        j["thigh." + side] = ((m * lx, 0, p["hip_z"]), (m * lx, 0.0, p["knee_z"]))
        j["shin." + side] = ((m * lx, 0.0, p["knee_z"]), (m * lx, 0.01, p["ankle_z"]))
        j["foot." + side] = ((m * lx, 0.01, p["ankle_z"]), (m * lx, -0.14, 0.03))
    return j


EMPLOYEE_PROPS = {
    "hip_z": 0.90, "spine_z": 1.02, "chest_z": 1.22, "neck_z": 1.44, "head_z": 1.53, "head_top": 1.78,
    "knee_z": 0.50, "ankle_z": 0.09, "leg_x": 0.10,
    "shoulder": (0.205, 0.0, 1.405), "elbow": (0.25, 0.015, 1.14), "wrist": (0.27, 0.0, 0.885),
    "hand_end": (0.275, -0.005, 0.77),
    # Torso rings (z, half width, half depth, y centre); 0.93..1.47.
    "torso": [(0.93, 0.198, 0.128, 0.0), (1.06, 0.202, 0.131, 0.0), (1.22, 0.222, 0.140, 0.0),
              (1.36, 0.235, 0.140, 0.0), (1.425, 0.232, 0.132, 0.005), (1.475, 0.16, 0.10, 0.01)],
    "pelvis": [(0.95, 0.192, 0.124), (0.87, 0.19, 0.12), (0.80, 0.178, 0.104)],
    "thigh_w": (0.088, 0.092, 0.073, 0.077),
    "shin_w": (0.071, 0.074, 0.062, 0.064),
    "head": [(1.515, 0.07, 0.08, -0.012), (1.555, 0.09, 0.1, -0.004), (1.615, 0.099, 0.108, 0.0),
             (1.695, 0.100, 0.112, 0.004), (1.755, 0.082, 0.096, 0.006), (1.775, 0.05, 0.06, 0.006)],
    "sleeve_end": 0.62,     # fraction of the upper arm covered by the sleeve
    "sleeve_w": (0.074, 0.078),
}


def employee_palette(skin_hex):
    skin = col(skin_hex)
    return {
        "skin": [mul(skin, 1.08), skin, mul(skin, 0.86), mul(skin, 0.70)],
        "cloth": [col("#F08A45"), col("#E87932"), col("#C9642A"), col("#9E4B1F")],
        "glove": col("#1C1C1C"),
        "boot": col("#111111"),
        "sole": col("#2A2826"),
        "belt": col("#151515"),
        "collar": col("#D9D4C2"),
        "patch": [col("#D2D2C6"), col("#C3C4B7"), col("#AEB0A3")],
        "badge": col("#E8E4CF"),
        "ink": col("#1E1E1E"),
    }


def paint_cloth(r, tones, rng, grad=0.30, base=0.30, blotch=0.30, speck=0.10, cell=6, folds=0):
    g = r.grad_y()
    field = base + grad * g + blotch * (value_noise(r.h, r.w, cell, rng) - 0.5) \
        + speck * (rng.random((r.h, r.w)).astype(np.float32) - 0.5)
    for _ in range(folds):
        fy = int(rng.integers(2, max(3, r.h - 2)))
        fx = int(rng.integers(0, max(1, r.w // 2)))
        fl = int(rng.integers(max(2, r.w // 4), max(3, r.w // 2 + 1)))
        field[fy, fx:fx + fl] += 0.28
        field[max(0, fy - 1), fx:fx + fl] -= 0.12
    r.tones(tones, field)


def paint_skin(r, tones, rng, base=0.30, blotch=0.25, cell=4):
    """Low-contrast skin: mostly tone 1, soft blotches toward tones 0 and 2."""
    n = value_noise(r.h, r.w, cell, rng) + (base - 0.3) + 0.06 * (rng.random((r.h, r.w)) - 0.5)
    r.fill(tones[1])
    v = r.view
    hi = n < 0.5 - blotch
    lo = n > 0.5 + blotch
    v[hi] = lerp(tones[1], tones[0], 0.55)
    v[lo] = lerp(tones[1], tones[2], 0.55)


def paint_badge(r, text, bg, ink, frame=None):
    r.fill(bg)
    if frame is not None:
        r.rect(0, 0, r.w, 1, frame)
        r.rect(0, r.h - 1, r.w, 1, frame)
        r.rect(0, 0, 1, r.h, frame)
        r.rect(r.w - 1, 0, 1, r.h, frame)
    tw = text_width(text)
    r.text((r.w - tw) // 2, (r.h - 5) // 2 + (1 if r.h % 2 == 0 else 0), text, ink)


def bounce_light(r, from_row, amount):
    """Brightens the rows below `from_row` (the jaw faces away from overhead lights)."""
    v = r.view
    rows = np.clip((np.arange(r.h) - from_row) / max(1, r.h - from_row), 0.0, 1.0)[:, None, None]
    v[:] = np.clip(v * (1.0 + amount * rows), 0.0, 1.0)


def paint_employee_face(r, spec, pal, rng):
    """Face region (front of the head): 32 x 32, top row = top of the head."""
    skin = pal["skin"]
    paint_skin(r, skin, rng, base=0.28, blotch=0.20)
    w, h = r.w, r.h
    # Volume: darker cheeks/jaw edges and under the chin.
    for x in range(w):
        if min(x, w - 1 - x) == 0:
            r.rect(x, 0, 1, h, skin[2])
    r.rect(1, h - 1, w - 2, 1, lerp(skin[1], skin[2], 0.6))
    bounce_light(r, 19, 0.07)
    eye_y = 14
    lx, rx = 9, 20  # left edge of the character's right eye / left eye (viewer's left / right)
    # Brow ridge shadow + brows.
    brow = spec.get("brow", col("#3A2A20"))
    r.rect(lx - 1, eye_y - 2, 5, 1, skin[2])
    r.rect(rx - 1, eye_y - 2, 5, 1, skin[2])
    if spec.get("feminine"):
        r.rect(lx, eye_y - 3, 3, 1, brow)
        r.rect(rx + 1, eye_y - 3, 3, 1, brow)
    else:
        r.rect(lx, eye_y - 3, 4, 1, brow)
        r.rect(rx, eye_y - 3, 4, 1, brow)
    # Eyes: dark sockets, flat pale whites and small dark pupils that stare a little too straight.
    for ex in (lx, rx):
        r.rect(ex - 1, eye_y - 1, 5, 3, lerp(skin[2], skin[3], 0.5))
        r.rect(ex, eye_y, 3, 1, col("#CFC9BC"))
        r.dot(ex + 1, eye_y, col("#141210"))
        r.rect(ex, eye_y + 1, 3, 1, skin[2])
        if spec.get("feminine"):
            r.rect(ex - 1, eye_y - 1, 5, 1, col("#1A1412"))  # lashes / liner
    # Nose: shadow down the side and under the tip.
    r.rect(15, eye_y + 1, 1, 4, skin[2])
    r.rect(14, eye_y + 5, 4, 1, skin[3])
    r.rect(16, eye_y + 1, 1, 4, skin[0])
    # Mouth: thin, straight, corners pulled down a pixel (unsettlingly neutral).
    mouth = spec.get("mouth", mul(skin[3], 0.75))
    my = eye_y + 9
    r.rect(13, my, 7, 1, mouth)
    r.dot(12, my + 1, mouth)
    r.dot(20, my + 1, mouth)
    if spec.get("feminine"):
        r.rect(14, my + 1, 5, 1, lerp(mouth, skin[1], 0.35))   # lower lip
    else:
        r.rect(13, my + 1, 7, 1, skin[0])
    # Ears at the extreme edges of the front projection.
    r.rect(0, eye_y - 1, 1, 5, skin[3])
    r.rect(w - 1, eye_y - 1, 1, 5, skin[3])
    hair = spec["hair"]
    if spec.get("cap"):
        r.rect(0, 0, w, 9, hair)        # hidden under the cap crown
        r.rect(0, 9, 2, 5, hair)        # sideburns
        r.rect(w - 2, 9, 2, 5, hair)
    if spec.get("beard") is not None:
        # short boxed beard: jawline, chin and moustache in one colour with a few lighter hairs
        stub = spec["beard"]
        light = lerp(stub, skin[1], 0.35)
        for y in range(eye_y + 4, h):
            for x in range(1, w - 1):
                if 13 <= x <= 19 and my <= y <= my + 1:
                    continue  # lips stay clear
                jaw = (y >= my + 3) or ((x <= 4 or x >= w - 5) and y >= eye_y + 5)
                lip = y == my - 1 and 12 <= x <= 20
                chin = y >= my + 2 and 11 <= x <= 21
                if jaw or lip or chin:
                    r.dot(x, y, light if rng.random() < 0.18 else stub)
    if spec.get("glasses"):
        frame = col("#121212")
        lens = col("#5E6A70")
        for ex in (lx, rx):
            r.rect(ex - 2, eye_y - 2, 7, 1, frame)
            r.rect(ex - 2, eye_y + 2, 7, 1, frame)
            r.rect(ex - 2, eye_y - 2, 1, 5, frame)
            r.rect(ex + 4, eye_y - 2, 1, 5, frame)
            r.rect(ex - 1, eye_y - 1, 5, 3, lens)
            r.dot(ex + 1, eye_y, col("#141210"))
            r.dot(ex + 3, eye_y - 1, col("#B9C4C8"))
        r.rect(lx + 5, eye_y - 1, rx - lx - 7, 1, frame)
        r.rect(0, eye_y - 1, lx - 2, 1, frame)
        r.rect(rx + 5, eye_y - 1, w - rx - 5, 1, frame)
    if spec.get("long_hair"):
        r.rect(0, 0, w, 7, hair)
        r.rect(0, 7, 6, 4, hair)        # side-swept fringe
        r.rect(w - 4, 7, 4, 3, hair)
        r.rect(6, 7, 6, 1, hair)
        r.rect(0, 11, 2, 10, hair)       # hair over the ears
        r.rect(w - 2, 11, 2, 10, hair)
        for x in range(w):
            if rng.random() < 0.35:
                r.dot(x, int(rng.integers(0, 7)), mul(hair, 1.6))


def paint_head_side(r, spec, pal, rng):
    """Side of the head, s = 0 at the face. Ear in the middle, hair behind/above."""
    skin = pal["skin"]
    paint_skin(r, skin, rng, base=0.40, blotch=0.2)
    hair = spec["hair"]
    w, h = r.w, r.h
    if spec.get("long_hair"):
        r.rect(0, 0, w, 7, hair)
        r.rect(w // 3, 0, w - w // 3, h - 6, hair)
        r.rect(w // 2, h - 6, w // 2, 6, hair)
        for _ in range(12):
            r.dot(int(rng.integers(w // 3, w)), int(rng.integers(0, h - 6)), mul(hair, 1.5))
    else:
        r.rect(w // 3, 0, w - w // 3, h // 2 + 2, hair)
        r.rect(w // 2, h // 2 + 2, w // 2, int(h * 0.3), hair)   # behind the ear, down to the nape
        r.rect(w // 3 - 2, h // 3, 2, 6, hair)  # sideburn
    # Ear.
    ex = w // 2 - 3
    r.rect(ex, h // 2 - 4, 4, 7, skin[2])
    r.rect(ex + 1, h // 2 - 3, 2, 5, skin[3])
    r.rect(0, h - 3, w, 3, skin[2])


def paint_head_back(r, spec, pal, rng):
    skin = pal["skin"]
    paint_skin(r, skin, rng, base=0.45, blotch=0.2)
    hair = spec["hair"]
    if spec.get("long_hair"):
        r.rect(0, 0, r.w, r.h - 3, hair)
        r.rect(r.w // 2 - 3, r.h // 3, 6, 3, col("#2E2A30"))  # hair tie
        for _ in range(16):
            r.dot(int(rng.integers(0, r.w)), int(rng.integers(0, r.h - 3)), mul(hair, 1.5))
    else:
        # short hair down to the nape, slightly ragged hairline, neck skin below
        line = int(r.h * 0.8)
        r.rect(0, 0, r.w, line, hair)
        for x in range(r.w):
            if rng.random() < 0.5:
                r.dot(x, line, hair)
            if x in (0, 1, r.w - 2, r.w - 1):
                r.rect(x, line, 1, 2, hair)
        for _ in range(10):
            r.dot(int(rng.integers(0, r.w)), int(rng.integers(0, line)), mul(hair, 1.35))


def ring_at(rings, z):
    """Linear interpolation of (z, hx, hy, cy) rings at height z."""
    for a, b in zip(rings, rings[1:]):
        if a[0] <= z <= b[0]:
            u = (z - a[0]) / (b[0] - a[0])
            return (z,) + tuple(a[i] + (b[i] - a[i]) * u for i in (1, 2, 3))
    return (z,) + tuple(rings[-1][1:])


def build_human(scene, spec):
    """Shared employee/manager builder. spec holds name, colours, proportions and options."""
    p = dict(EMPLOYEE_PROPS)
    p.update(spec.get("props", {}))
    pal = spec["palette"]
    rng = np.random.default_rng(spec["seed"])
    regions = [
        ("face", 32, 32), ("head_side", 16, 32), ("head_back", 16, 16), ("hair", 8, 8),
        ("shirt_front", 32, 32), ("shirt_back", 32, 32), ("shirt_side", 16, 32), ("shirt_top", 16, 16),
        ("sleeve", 16, 16), ("pants", 16, 32), ("pants_front", 32, 16), ("skin", 16, 16),
        ("glove", 8, 8), ("boot", 16, 8), ("sole", 8, 8), ("belt", 32, 4), ("belt_plain", 8, 4), ("collar", 16, 8),
        ("badge", 32, 9), ("badge_edge", 4, 4), ("cap", 16, 16), ("cap_brim", 16, 8),
    ]
    regions += spec.get("extra_regions", [])
    atlas = Atlas(spec["name"] + "_tex", regions, spec["seed"])
    shirt, pants_t, skin_t = spec["shirt"], spec["pants"], pal["skin"]

    # ---- paint ----
    spec.get("face_painter", paint_employee_face)(atlas["face"], spec, pal, rng)
    paint_head_side(atlas["head_side"], spec, pal, rng)
    paint_head_back(atlas["head_back"], spec, pal, rng)
    atlas["hair"].fill(spec["hair"])
    paint_skin(atlas["skin"], skin_t, rng)
    r = atlas["shirt_front"]
    paint_cloth(r, shirt, rng, grad=0.25, base=0.30, folds=2)
    r.rect(15, 0, 2, 3, skin_t[2])             # V of the collar
    r.rect(15, 3, 1, 11, shirt[3])             # placket
    for by in (5, 9, 13):
        r.dot(16, by, mul(shirt[0], 1.05))
    r.rect(19, 9, 8, 1, shirt[2])              # breast pocket seam
    r.rect(0, 0, 1, r.h, shirt[2])
    r.rect(r.w - 1, 0, 1, r.h, shirt[2])
    if spec.get("front_tag"):
        r.rect(5, 5, 6, 3, col("#D6D6D0"))     # plain white name tag above the right pocket
        r.rect(6, 6, 4, 1, col("#8A8A88"))
    spec.get("paint_shirt_front", lambda *_: None)(r, shirt, rng)
    r = atlas["shirt_back"]
    paint_cloth(r, shirt, rng, grad=0.28, base=0.30, folds=3)
    if spec.get("back_patch", True):
        patch = pal["patch"]
        r.rect(7, 6, 18, 8, patch[1])
        r.rect(7, 6, 18, 1, patch[0])
        r.rect(7, 13, 18, 1, patch[2])
        f = value_noise(8, 18, 3, rng)
        for yy in range(8):
            for xx in range(18):
                if f[yy, xx] > 0.62:
                    r.dot(7 + xx, 6 + yy, patch[2])
        r.rect(10, 9, 12, 1, col("#9C9E92"))    # unreadable print on the patch
        r.rect(12, 11, 8, 1, col("#A5A79B"))
    paint_cloth(atlas["shirt_side"], shirt, rng, grad=0.25, base=0.42, folds=2)
    paint_cloth(atlas["shirt_top"], shirt, rng, grad=0.0, base=0.12)
    r = atlas["sleeve"]
    paint_cloth(r, shirt, rng, grad=0.2, base=0.33)
    r.rect(0, r.h - 2, r.w, 2, shirt[2])
    r = atlas["pants"]
    paint_cloth(r, pants_t, rng, grad=0.25, base=0.35, folds=3, cell=5)
    r.rect(0, r.h - 2, r.w, 2, pants_t[3])
    r = atlas["pants_front"]
    paint_cloth(r, pants_t, rng, grad=0.35, base=0.3)
    r.rect(15, 0, 1, r.h, pants_t[3])           # fly / crotch seam
    atlas["glove"].fill(pal["glove"])
    atlas["glove"].rect(0, 0, 8, 2, mul(pal["glove"], 1.6))
    r = atlas["boot"]
    r.fill(pal["boot"])
    r.rect(0, r.h - 2, r.w, 2, pal["sole"])
    r.rect(0, 0, r.w, 1, mul(pal["boot"], 1.8))
    atlas["sole"].fill(pal["sole"])
    r = atlas["belt"]
    r.fill(pal["belt"])
    r.rect(14, 0, 4, 4, col("#77736A"))
    r.rect(15, 1, 2, 2, pal["belt"])
    atlas["belt_plain"].fill(pal["belt"])
    atlas["collar"].fill(pal["collar"])
    atlas["collar"].rect(0, 7, 16, 1, mul(pal["collar"], 0.8))
    paint_badge(atlas["badge"], spec["badge_text"], spec.get("badge_bg", pal["badge"]), pal["ink"],
                spec.get("badge_frame"))
    atlas["badge_edge"].fill(spec.get("badge_bg", pal["badge"]))
    r = atlas["cap"]
    paint_cloth(r, shirt, rng, grad=0.25, base=0.22)
    r.rect(7, 0, 1, r.h, shirt[2])
    r.rect(0, r.h - 2, r.w, 2, shirt[2])
    r = atlas["cap_brim"]
    r.fill(shirt[2])
    r.rect(0, 0, r.w, 2, shirt[3])
    for fn in spec.get("extra_paint", []):
        fn(atlas, pal, rng)

    # ---- geometry ----
    B = Builder(atlas, HUMAN_BONES)
    lx = p["leg_x"]
    for side, m in (("L", 1), ("R", -1)):
        x = m * lx
        # Boots: shoe on the foot bone, shaft around the ankle on the shin bone.
        B.loft([(x, 0.075, 0.066), (x, -0.04, 0.062), (x, -0.13, 0.048), (x, -0.178, 0.036)],
               [sec_rect(0.056, 0.066, 0.012), sec_rect(0.058, 0.062, 0.012), sec_rect(0.055, 0.048, 0.014),
                sec_rect(0.048, 0.036, 0.014)],
               "foot." + side, {"all": "boot", "bottom": "sole"}, hint=(1, 0, 0))
        B.loft([(x, 0.012, 0.08), (x, 0.012, 0.175)], [sec_rect(0.062, 0.068, 0.015)], "shin." + side,
               {"all": "boot"})
        # Trousers.
        tw = p["thigh_w"]
        B.loft([(x, 0.0, p["hip_z"] + 0.05), (x, 0.0, p["knee_z"] - 0.03)],
               [sec_rect(tw[0], tw[1], 0.025), sec_rect(tw[2], tw[3], 0.02)],
               "thigh." + side, {"all": "pants"})
        sw = p["shin_w"]
        B.loft([(x, 0.004, p["knee_z"] + 0.045), (x, 0.012, 0.15)],
               [sec_rect(sw[0], sw[1], 0.02), sec_rect(sw[2], sw[3], 0.018)],
               "shin." + side, {"all": "pants"})
    pel = p["pelvis"]
    B.loft([(0, 0, z) for z, _, _ in pel], [sec_rect(hx, hy, 0.03) for _, hx, hy in pel], "hips",
           {"all": "pants", "front": "pants_front"})
    B.loft([(0, 0.0, 0.905), (0, 0.0, 0.952)], [sec_rect(p["pelvis"][0][1] + 0.012, p["pelvis"][0][2] + 0.01, 0.03)],
           "hips", {"all": "belt_plain", "front": "belt"})
    # Torso: lower half on the spine bone, upper on the chest, one shared projection box.
    torso = p["torso"]
    tx = max(t[1] for t in torso)
    ty = max(t[2] for t in torso)
    tproj = ((-tx, -ty - 0.01, torso[0][0]), (tx, ty + 0.01, torso[-1][0]))
    # Split at the chest joint; the lower piece reaches 3 cm into the (slightly larger) upper piece.
    cz = p["chest_z"]
    lo_end = ring_at(torso, cz + 0.03)
    lower = [t for t in torso if t[0] < cz + 0.03] + [(lo_end[0], lo_end[1] * 0.985, lo_end[2] * 0.985, lo_end[3])]
    upper = [ring_at(torso, cz - 0.01)] + [t for t in torso if t[0] > cz - 0.01]
    shirt_regions = {"front": "shirt_front", "back": "shirt_back", "side": "shirt_side", "top": "shirt_top",
                     "bottom": "shirt_side"}
    B.loft([(0, cy, z) for z, _, _, cy in lower], [sec_rect(hx, hy, 0.04) for _, hx, hy, _ in lower], "spine",
           shirt_regions, proj=tproj)
    B.loft([(0, cy, z) for z, _, _, cy in upper], [sec_rect(hx, hy, 0.04) for _, hx, hy, _ in upper], "chest",
           shirt_regions, proj=tproj)
    for fn in spec.get("extra_torso", []):
        fn(B, p)
    # Collar and neck.
    nz = p["neck_z"]
    B.loft([(0, 0.008, nz - 0.01), (0, 0.006, nz + 0.045)], [sec_rect(0.078, 0.072, 0.025)], "chest",
           {"all": "collar"})
    B.loft([(0, 0.004, nz - 0.03), (0, 0.0, p["head_z"] + 0.03)], [sec_rect(0.052, 0.054, 0.018)], "neck",
           {"all": "skin"})
    # Head.
    hd = p["head"]
    hx = max(t[1] for t in hd)
    hy = max(t[2] for t in hd)
    hproj = ((-hx, -hy, hd[0][0]), (hx, hy, hd[-1][0]))
    B.loft([(0, cy, z) for z, _, _, cy in hd], [sec_rect(a, b, min(a, b) * 0.38) for _, a, b, _ in hd], "head",
           {"front": "face", "side": "head_side", "back": "head_back", "top": "hair", "bottom": "skin"},
           proj=hproj, bias=(1.0, 1.15, 1.0))
    for fn in spec.get("extra_head", []):
        fn(B, p)
    # Arms.
    J = human_joints(p)
    for side, m in (("L", 1), ("R", -1)):
        sh, el = Vector(J["upper_arm." + side][0]), Vector(J["upper_arm." + side][1])
        wr, he = Vector(J["hand." + side][0]), Vector(J["hand." + side][1])
        d = (el - sh).normalized()
        top = sh + Vector((-m * 0.012, 0.0, 0.018)) - d * 0.02
        send = sh + (el - sh) * p["sleeve_end"]
        sw0, sw1 = p["sleeve_w"]
        B.loft([top, send], [sec_rect(sw0, sw1, 0.02), sec_rect(sw0 + 0.004, sw1 + 0.003, 0.02)],
               "upper_arm." + side, {"all": "sleeve", "top": "shirt_top"})
        if p["sleeve_end"] < 0.98:
            B.loft([send - d * 0.03, el + d * 0.02], [sec_rect(0.046, 0.048, 0.014)], "upper_arm." + side,
                   {"all": "skin"})
        else:
            # long sleeve: no skin above the elbow
            pass
        fd = (wr - el).normalized()
        B.loft([el - fd * 0.015, wr], [sec_rect(0.045, 0.047, 0.014), sec_rect(0.037, 0.039, 0.012)],
               "forearm." + side, {"all": spec.get("forearm_region", "skin")})
        hand_region = {"all": spec.get("hand_region", "glove")}
        hd_dir = (he - wr).normalized()
        B.loft([wr - hd_dir * 0.02, wr + (he - wr) * 0.45, he],
               [sec_rect(0.03, 0.047, 0.01), sec_rect(0.029, 0.05, 0.01), sec_rect(0.024, 0.044, 0.01)],
               "hand." + side, hand_region)
        # thumb, pointing forward/down from the inner front of the hand
        tb = wr + (he - wr) * 0.25 + Vector((-m * 0.012, -0.045, 0.0))
        B.loft([tb, tb + Vector((-m * 0.006, -0.025, -0.05))], [sec_rect(0.013, 0.014, 0.0)], "hand." + side,
               hand_region)
    # Badge on the character's left chest.
    bz = spec.get("badge_z", 1.315)
    front_y = -(spec.get("badge_y_front", 0.141))
    bw = spec.get("badge_w", 0.064)
    bh = bw * 9 / 32 * 1.25
    bxc = spec.get("badge_x", 0.105)
    B.box((bxc - bw, front_y - 0.006, bz - bh), (bxc + bw, front_y + 0.004, bz + bh), "chest",
          {"all": "badge_edge", "front": "badge"})
    # Cap.
    if spec.get("cap"):
        ct = p["head_top"]
        B.loft([(0, 0.004, ct - 0.085), (0, 0.004, ct - 0.02), (0, 0.006, ct + 0.012), (0, 0.008, ct + 0.026)],
               [sec_rect(0.108, 0.122, 0.035), sec_rect(0.106, 0.120, 0.035), sec_rect(0.096, 0.108, 0.04),
                sec_rect(0.07, 0.08, 0.03)],
               "head", {"all": "cap", "bottom": "cap_brim"})
        # brim: thin slab sticking forward, tilted slightly down
        B.loft([(0, -0.10, ct - 0.072), (0, -0.215, ct - 0.088)],
               [sec_rect(0.094, 0.009, 0.0), sec_rect(0.082, 0.007, 0.0)],
               "head", {"all": "cap", "bottom": "cap_brim"}, hint=(1, 0, 0))
    obj_name = spec["name"]
    img = atlas.to_image()
    mat = make_material(obj_name + "_mat", img)
    mesh = B.to_object(obj_name + "_body", scene, mat)
    return mesh, J, p


# ---------------------------------------------------------------------------
# Human animations
# ---------------------------------------------------------------------------

def gait(t, thigh_amp, knee_amp, arm_amp, elbow, stance_knee=4.0, lean=0.0, twist=5.0, bob=0.0,
         foot_follow=0.8, arm_out=4.0):
    """One walk/run cycle at phase t (left leg forward at t = 0.25)."""
    s = wave(t)
    c = wavec(t)
    pose = {}
    for side, m in (("L", 1.0), ("R", -1.0)):
        th = -thigh_amp * s * m
        sw = max(0.0, c * m)   # swing phase weight (leg passing under the body)
        kn = stance_knee + knee_amp * sw
        pose["thigh." + side] = (th, 0.0, 0.0)
        pose["shin." + side] = (kn, 0.0, 0.0)
        pose["foot." + side] = (-(th + kn) * foot_follow + 6.0 * max(0.0, -c * m), 0.0, 0.0)
        ua = arm_amp * s * m
        pose["upper_arm." + side] = (ua, -m * arm_out, 0.0)
        pose["forearm." + side] = (-elbow - 0.4 * arm_amp * max(0.0, -s * m), 0.0, 0.0)
        pose["hand." + side] = (-4.0, 0.0, 0.0)
    pose["hips"] = (lean * 0.3, 1.5 * s, -twist * s)
    pose["spine"] = (lean * 0.4, -0.8 * s, twist * 0.6 * s)
    pose["chest"] = (lean * 0.3, -0.6 * s, twist * 0.9 * s)
    pose["neck"] = (-lean * 0.5, 0.0, -twist * 0.4 * s)
    pose["head"] = (-lean * 0.3 + 1.5 * wave(t, 2.0, 0.1), 0.0, -twist * 0.4 * s)
    pose["@hips"] = (0.0, 0.0, 0.0)
    pose["@lift"] = bob * max(0.0, wave(t, 2.0, 0.0))
    return pose


def employee_actions(anim):
    def idle(t):
        b = wave(t)
        return {
            "hips": (0.0, 1.2 * b, 0.0),
            "spine": (0.6 * b, -0.6 * b, 0.0),
            "chest": (1.4 * wave(t, 1.0, 0.1), -0.4 * b, 1.0 * wave(t, 1.0, 0.3)),
            "neck": (1.0 * wave(t, 1.0, 0.2), 0.0, 0.0),
            "head": (1.5 * wave(t, 1.0, 0.25), 0.0, 4.0 * wave(t, 1.0, 0.6)),
            "upper_arm.L": (1.5 * wave(t, 1.0, 0.3), -3.0, 0.0),
            "upper_arm.R": (1.5 * wave(t, 1.0, 0.35), 3.0, 0.0),
            "forearm.L": (-8.0 - 1.5 * b, 0.0, 0.0),
            "forearm.R": (-8.0 - 1.5 * b, 0.0, 0.0),
            "thigh.L": (0.0, 0.0, -3.0), "thigh.R": (0.0, 0.0, 3.0),
            "foot.L": (0.0, 0.0, 3.0), "foot.R": (0.0, 0.0, -3.0),
        }

    def walk(t):
        return gait(t, thigh_amp=33.0, knee_amp=50.0, arm_amp=22.0, elbow=12.0, lean=3.0, twist=6.0)

    def run(t):
        p = gait(t, thigh_amp=42.0, knee_amp=95.0, arm_amp=38.0, elbow=78.0, stance_knee=14.0, lean=14.0,
                 twist=9.0, bob=0.05, foot_follow=0.55, arm_out=8.0)
        return p

    # Stocking shelves: bend and pick an item off a low shelf, straighten, place it at chest height.
    place = {
        "spine": (4.0, 0.0, 0.0), "chest": (2.0, 0.0, 0.0), "neck": (2.0, 0.0, 0.0), "head": (-4.0, 0.0, 0.0),
        "upper_arm.L": (-62.0, -4.0, -6.0), "upper_arm.R": (-66.0, 4.0, 6.0),
        "forearm.L": (-34.0, 0.0, -8.0), "forearm.R": (-30.0, 0.0, 8.0),
        "hand.L": (6.0, 0.0, 0.0), "hand.R": (6.0, 0.0, 0.0),
    }
    lower = {
        "hips": (8.0, 0.0, 0.0), "spine": (12.0, 0.0, 0.0), "chest": (6.0, 0.0, 0.0), "neck": (-4.0, 0.0, 0.0),
        "upper_arm.L": (-24.0, -4.0, -4.0), "upper_arm.R": (-26.0, 4.0, 4.0),
        "forearm.L": (-50.0, 0.0, -6.0), "forearm.R": (-46.0, 0.0, 6.0),
        "thigh.L": (-10.0, 0.0, 0.0), "thigh.R": (-10.0, 0.0, 0.0),
        "shin.L": (16.0, 0.0, 0.0), "shin.R": (16.0, 0.0, 0.0), "foot.L": (-6.0, 0.0, 0.0), "foot.R": (-6.0, 0.0, 0.0),
    }
    pick = {
        "hips": (20.0, 0.0, 0.0), "spine": (22.0, 0.0, 3.0), "chest": (12.0, 0.0, 3.0), "neck": (-12.0, 0.0, 0.0),
        "head": (-6.0, 0.0, 0.0),
        "upper_arm.L": (-22.0, -6.0, -8.0), "upper_arm.R": (-30.0, 6.0, 8.0),
        "forearm.L": (-22.0, 0.0, -6.0), "forearm.R": (-18.0, 0.0, 6.0),
        "hand.L": (-10.0, 0.0, 0.0), "hand.R": (-10.0, 0.0, 0.0),
        "thigh.L": (-34.0, 0.0, -3.0), "thigh.R": (-30.0, 0.0, 3.0),
        "shin.L": (52.0, 0.0, 0.0), "shin.R": (46.0, 0.0, 0.0),
        "foot.L": (-18.0, 0.0, 0.0), "foot.R": (-16.0, 0.0, 0.0),
    }
    carry = {
        "hips": (6.0, 0.0, 0.0), "spine": (6.0, 0.0, -2.0), "chest": (2.0, 0.0, -2.0), "neck": (0.0, 0.0, 0.0),
        "upper_arm.L": (-30.0, -4.0, -8.0), "upper_arm.R": (-34.0, 4.0, 8.0),
        "forearm.L": (-72.0, 0.0, -10.0), "forearm.R": (-68.0, 0.0, 10.0),
        "thigh.L": (-8.0, 0.0, 0.0), "thigh.R": (-6.0, 0.0, 0.0),
        "shin.L": (12.0, 0.0, 0.0), "shin.R": (10.0, 0.0, 0.0),
    }

    def work(t):
        return keyed(t, [(0.0, place), (0.22, lower), (0.45, pick), (0.72, carry), (1.0, place)])

    anim.action("idle", 2.0, idle)
    anim.action("walk", 1.0, walk)
    anim.action("run", 0.6, run)
    anim.action("work", 1.5, work)


def manager_actions(anim):
    def idle(t):
        b = wave(t)
        look = wave(t, 1.0, 0.1)
        return {
            "hips": (0.0, 1.0 * b, 0.0),
            "spine": (1.0 * b, -0.6 * b, 0.0),
            "chest": (1.8 * wave(t, 2.0, 0.1), 0.0, 2.0 * look),
            "neck": (2.0, 0.0, 3.0 * look),
            "head": (2.0 * wave(t, 2.0, 0.3), 2.0 * b, 9.0 * look),
            "upper_arm.L": (2.0 * wave(t, 1.0, 0.3), -5.0, 0.0),
            "upper_arm.R": (-8.0, 4.0, 0.0),
            "forearm.L": (-10.0, 0.0, 0.0),
            "forearm.R": (-35.0 - 3.0 * b, 0.0, 10.0),
            "thigh.L": (0.0, 0.0, -4.0), "thigh.R": (0.0, 0.0, 4.0),
        }

    def talk(t):
        g = wave(t, 2.0)
        lift = 0.5 - 0.5 * wavec(t)
        return {
            "hips": (0.0, 1.0 * wave(t), 0.0),
            "spine": (1.5, 0.0, -2.0 + 3.0 * lift),
            "chest": (1.5 * wave(t, 2.0, 0.2), 0.0, 4.0 * lift),
            "neck": (2.0 + 3.0 * wave(t, 4.0), 0.0, 3.0 * lift),
            "head": (2.5 * wave(t, 4.0, 0.15), 3.0 * wave(t, 1.0, 0.2), 4.0 * lift),
            # right hand explains: forearm raised and opened outward, beats on the words
            "upper_arm.R": (-18.0 - 18.0 * lift - 5.0 * g, 14.0 + 8.0 * lift, 0.0),
            "forearm.R": (-58.0 - 22.0 * lift + 12.0 * g, 0.0, -28.0 - 10.0 * lift),
            "hand.R": (-8.0 + 10.0 * g, 18.0, -10.0 * wave(t, 2.0, 0.1)),
            # left arm relaxed, a smaller echo of the gesture
            "upper_arm.L": (-8.0 + 3.0 * g, -7.0, 0.0),
            "forearm.L": (-28.0 + 8.0 * wave(t, 2.0, 0.3), 0.0, 8.0),
            "hand.L": (0.0, 0.0, 4.0 * g),
            "thigh.L": (0.0, 0.0, -4.0), "thigh.R": (0.0, 0.0, 4.0),
        }

    def walk(t):
        return gait(t, thigh_amp=22.0, knee_amp=40.0, arm_amp=14.0, elbow=14.0, lean=2.0, twist=5.0, arm_out=7.0)

    anim.action("idle", 2.5, idle)
    anim.action("talk", 2.0, talk)
    anim.action("walk", 1.1, walk)


# ---------------------------------------------------------------------------
# Character specs
# ---------------------------------------------------------------------------

def rita_extras():
    def head(B, p):
        hd = p["head"]
        # Hair shell over the top/back of the head, plus a ponytail with a dark tie.
        B.loft([(0, 0.02, 1.665), (0, 0.016, 1.73), (0, 0.012, 1.775), (0, 0.01, 1.792)],
               [sec_rect(0.106, 0.104, 0.04), sec_rect(0.104, 0.104, 0.04), sec_rect(0.088, 0.092, 0.035),
                sec_rect(0.055, 0.06, 0.02)],
               "head", {"all": "hair"})
        B.loft([(0, 0.112, 1.705), (0, 0.142, 1.675)], [sec_rect(0.03, 0.03, 0.01)], "head", {"all": "hair_tie"},
               hint=(1, 0, 0))
        for m in (1, -1):
            B.loft([(m * 0.104, -0.035, 1.735), (m * 0.106, -0.045, 1.64), (m * 0.098, -0.04, 1.565)],
                   [sec_rect(0.012, 0.05, 0.004), sec_rect(0.014, 0.05, 0.004), sec_rect(0.01, 0.036, 0.004)],
                   "head", {"all": "hair"}, hint=(1, 0, 0))
        B.loft([(0, 0.13, 1.69), (0, 0.168, 1.62), (0, 0.172, 1.54), (0, 0.158, 1.47)],
               [sec_rect(0.038, 0.034, 0.012), sec_rect(0.042, 0.036, 0.012), sec_rect(0.034, 0.03, 0.01),
                sec_rect(0.016, 0.016, 0.005)],
               "head", {"all": "hair"}, hint=(1, 0, 0))

    def paint(atlas, pal, rng):
        atlas["hair_tie"].fill(col("#3B2F4A"))
        r = atlas["hair"]
        r.fill(col("#231A15"))
        for _ in range(10):
            r.dot(int(rng.integers(0, 8)), int(rng.integers(0, 8)), col("#3A2A20"))

    return head, paint


def employee_spec(name, seed, skin_hex, hair_hex, **kw):
    pal = employee_palette(skin_hex)
    spec = {
        "name": name, "seed": seed, "palette": pal, "badge_text": kw.pop("badge"),
        "shirt": pal["cloth"], "pants": pal["cloth"], "hair": col(hair_hex),
        "cap": True,
    }
    spec.update(kw)
    return spec


def make_specs():
    specs = {}
    specs["employee_dale"] = employee_spec(
        "employee_dale", 11, "#D9B48F", "#4A3628", badge="DALE",
        beard=col("#5C4636"), brow=col("#4A3628"))
    head, paint = rita_extras()
    specs["employee_rita"] = employee_spec(
        "employee_rita", 23, "#C08A67", "#231A15", badge="RITA", cap=False, long_hair=True, feminine=True,
        brow=col("#1E1612"), mouth=col("#7A4038"),
        extra_head=[head], extra_paint=[paint], extra_regions=[("hair_tie", 4, 4)],
        props={"head_top": 1.775,
               "head": [(1.52, 0.06, 0.072, -0.014), (1.555, 0.081, 0.096, -0.005), (1.615, 0.096, 0.106, 0.0),
                        (1.695, 0.098, 0.11, 0.004), (1.755, 0.08, 0.095, 0.006), (1.775, 0.05, 0.06, 0.006)],
               # slightly narrower shoulders and waist than the men
               "torso": [(z, hx * 0.94, hy * 0.97, cy) for z, hx, hy, cy in EMPLOYEE_PROPS["torso"]],
               "shoulder": (0.195, 0.0, 1.405), "elbow": (0.238, 0.015, 1.14), "wrist": (0.257, 0.0, 0.885),
               "hand_end": (0.262, -0.005, 0.77)})
    specs["employee_marcus"] = employee_spec(
        "employee_marcus", 37, "#6B4632", "#151110", badge="MARCUS", glasses=True,
        brow=col("#120E0C"), mouth=col("#3A2219"))
    specs["manager"] = manager_spec()
    return specs


def manager_spec():
    skin = col("#C99A7E")
    pal = employee_palette("#C99A7E")
    pal["glove"] = mul(skin, 0.9)
    shirt = [col("#5F7FA1"), col("#4B6A8C"), col("#3B5674"), col("#2C4058")]
    pants = [col("#2A3142"), col("#202636"), col("#181D2A"), col("#11141D")]
    pal["boot"] = col("#1B1612")
    pal["sole"] = col("#0E0C0A")
    pal["belt"] = col("#1A1A1C")
    pal["collar"] = col("#557596")
    apron = [col("#343A46"), col("#2A2F3A"), col("#20242D"), col("#171A21")]

    def paint(atlas, pal, rng):
        r = atlas["apron_front"]
        paint_cloth(r, apron, rng, grad=0.3, base=0.32, folds=3, cell=5)
        r.rect(4, 9, 24, 1, apron[3])          # pocket seam
        r.rect(15, 9, 1, 8, apron[3])
        r.rect(0, 0, r.w, 2, apron[0])         # waist band
        r = atlas["apron_side"]
        paint_cloth(r, apron, rng, grad=0.3, base=0.4, cell=5)
        r.rect(0, 0, r.w, 2, apron[0])
        r = atlas["shirt_front"]
        # Collar points, breast-pocket flaps; the MANAGER badge is the 3D tag on the left pocket.
        for i in range(3):
            r.rect(10 + i, i, 5 - i, 1, shirt[0])
            r.rect(17, i, 5 - i, 1, shirt[0])
        r.rect(4, 9, 8, 1, shirt[3])
        r.rect(4, 10, 8, 1, shirt[0])
        r.rect(20, 9, 8, 1, shirt[3])
        r.rect(20, 10, 8, 1, shirt[0])
        r.rect(4, 15, 8, 1, shirt[2])
        r.rect(20, 15, 8, 1, shirt[2])

    def torso(B, p):
        # Work apron from the waist to just above the knee; wraps the front and sides.
        rings = [(1.00, 0.215, 0.165, -0.004), (0.86, 0.222, 0.160, -0.012), (0.70, 0.224, 0.150, -0.025),
                 (0.53, 0.226, 0.145, -0.04)]
        B.loft([(0, cy, z) for z, _, _, cy in rings], [sec_rect(hx, hy, 0.05) for _, hx, hy, _ in rings], "hips",
               {"front": "apron_front", "side": "apron_side", "back": "apron_side", "all": "apron_side"},
               caps=(False, True))

    return {
        "name": "manager", "seed": 51, "palette": pal, "badge_text": "MANAGER",
        "shirt": shirt, "pants": pants, "hair": col("#3B2C22"), "brow": col("#2E221B"),
        "cap": False, "front_tag": True, "back_patch": False,
        "badge_bg": col("#E3C86A"), "badge_frame": col("#C47A2A"), "badge_w": 0.07, "badge_x": 0.115,
        "badge_y_front": 0.162, "badge_z": 1.33,
        "hand_region": "skin",
        "face_painter": lambda r, _spec, pal, rng: paint_manager_face(r, pal, rng),
        "extra_paint": [paint], "extra_torso": [torso],
        "extra_regions": [("apron_front", 32, 24), ("apron_side", 16, 24)],
        "props": {
            "head_top": 1.785,
            "torso": [(0.93, 0.218, 0.160, -0.012), (1.05, 0.232, 0.172, -0.02), (1.18, 0.236, 0.165, -0.012),
                      (1.33, 0.245, 0.158, 0.0), (1.42, 0.240, 0.146, 0.005), (1.475, 0.17, 0.105, 0.01)],
            "pelvis": [(0.95, 0.205, 0.15), (0.87, 0.20, 0.135), (0.80, 0.186, 0.112)],
            "thigh_w": (0.094, 0.098, 0.078, 0.082),
            "shoulder": (0.215, 0.0, 1.40),
            "elbow": (0.27, 0.02, 1.14), "wrist": (0.285, 0.0, 0.89), "hand_end": (0.29, -0.005, 0.775),
            "head": [(1.515, 0.084, 0.084, -0.016), (1.555, 0.099, 0.102, -0.006), (1.615, 0.103, 0.110, 0.0),
                     (1.695, 0.100, 0.112, 0.004), (1.760, 0.084, 0.098, 0.008), (1.785, 0.055, 0.065, 0.008)],
            "sleeve_end": 0.70, "sleeve_w": (0.08, 0.084),
        },
    }


def paint_manager_face(r, pal, rng):
    """Worried middle-aged face: raised inner brows, wide eyes, open mouth, receding hair."""
    skin = pal["skin"]
    paint_skin(r, skin, rng, base=0.30, blotch=0.25)
    w, h = r.w, r.h
    hair = col("#3B2C22")
    r.rect(0, 0, w, 5, hair)
    r.rect(0, 5, 7, 3, hair)
    r.rect(w - 7, 5, 7, 3, hair)
    r.rect(0, 8, 2, 7, hair)
    r.rect(w - 2, 8, 2, 7, hair)
    r.rect(12, 5, 8, 1, hair)
    for x in range(w):
        if min(x, w - 1 - x) <= 1:
            r.rect(x, 15, 1, h - 15, skin[2])
    r.rect(0, h - 2, w, 2, skin[2])
    # forehead creases
    r.rect(10, 7, 12, 1, skin[2])
    r.rect(12, 9, 8, 1, skin[2])
    eye_y = 14
    lx, rx = 9, 20
    brow = col("#2E221B")
    # brows: inner ends raised (worry)
    r.rect(lx - 1, eye_y - 2, 2, 1, brow)
    r.rect(lx + 1, eye_y - 3, 2, 1, brow)
    r.rect(lx + 3, eye_y - 4, 1, 1, brow)
    r.rect(rx + 2, eye_y - 2, 2, 1, brow)
    r.rect(rx, eye_y - 3, 2, 1, brow)
    r.rect(rx - 1, eye_y - 4, 1, 1, brow)
    for ex in (lx, rx):
        r.rect(ex - 1, eye_y - 1, 5, 4, skin[3])
        r.rect(ex, eye_y - 1, 3, 2, col("#D8D2C6"))
        r.rect(ex + 1, eye_y - 1, 1, 2, col("#2A2018"))
        r.rect(ex - 1, eye_y + 2, 5, 1, skin[2])      # bags
        r.rect(ex, eye_y + 3, 3, 1, skin[2])
    r.rect(15, eye_y + 1, 1, 4, skin[2])
    r.rect(14, eye_y + 5, 4, 1, skin[3])
    r.rect(16, eye_y + 1, 1, 4, skin[0])
    # nasolabial folds
    r.rect(11, eye_y + 5, 1, 4, skin[2])
    r.rect(20, eye_y + 5, 1, 4, skin[2])
    # open, slightly grimacing mouth
    my = eye_y + 9
    r.rect(13, my - 1, 6, 1, mul(skin[3], 0.8))
    r.rect(13, my, 6, 2, col("#2A1412"))
    r.rect(14, my, 4, 1, col("#BDB6A4"))
    r.rect(13, my + 2, 6, 1, mul(skin[2], 0.95))
    r.rect(0, eye_y - 1, 1, 5, skin[3])
    r.rect(w - 1, eye_y - 1, 1, 5, skin[3])
    bounce_light(r, 18, 0.07)


# =============================================================================
# The monster (reference image 1, true form)
# =============================================================================

MONSTER_JOINTS = {
    "root": ((0, 0, 0), (0, 0, 0.15)),
    "hips": ((0, 0.02, 0.94), (0, 0.0, 1.14)),
    "spine": ((0, 0.0, 1.14), (0, -0.07, 1.46)),
    "chest": ((0, -0.07, 1.46), (0, -0.20, 1.78)),
    "neck": ((0, -0.20, 1.78), (0, -0.32, 1.90)),
    "head": ((0, -0.32, 1.90), (0, -0.32, 2.32)),
    "jaw": ((0, -0.26, 1.93), (0, -0.66, 1.80)),
    "ear.L": ((0.15, -0.40, 2.27), (0.19, -0.38, 2.50)),
    "ear.R": ((-0.15, -0.40, 2.27), (-0.32, -0.39, 2.47)),
    "upper_arm.L": ((0.32, -0.19, 1.74), (0.73, -0.25, 1.50)),
    "forearm.L": ((0.73, -0.25, 1.50), (0.79, -0.42, 0.90)),
    "hand.L": ((0.79, -0.42, 0.90), (0.81, -0.50, 0.70)),
    "upper_arm.R": ((-0.32, -0.19, 1.74), (-0.73, -0.25, 1.50)),
    "forearm.R": ((-0.73, -0.25, 1.50), (-0.79, -0.42, 0.90)),
    "hand.R": ((-0.79, -0.42, 0.90), (-0.81, -0.50, 0.70)),
    "thigh.L": ((0.18, 0.02, 0.92), (0.34, -0.15, 0.54)),
    "shin.L": ((0.34, -0.15, 0.54), (0.35, 0.07, 0.20)),
    "foot.L": ((0.35, 0.07, 0.20), (0.37, -0.22, 0.02)),
    "thigh.R": ((-0.18, 0.02, 0.92), (-0.34, -0.15, 0.54)),
    "shin.R": ((-0.34, -0.15, 0.54), (-0.35, 0.07, 0.20)),
    "foot.R": ((-0.35, 0.07, 0.20), (-0.37, -0.22, 0.02)),
}

MON = {
    "skin": [col("#C9AEAC"), col("#AA8D90"), col("#886B73"), col("#614853")],
    "blotch": col("#94535C"),
    "bruise": col("#5A3C4C"),
    "stitch": col("#22161A"),
    "shirt": [col("#E2803E"), col("#D06A2C"), col("#A65224"), col("#723A1C")],
    "stain": col("#5C3A26"),
    "lip": col("#8C3238"),
    "lip_dark": col("#5E1C24"),
    "mouth": col("#240A0E"),
    "tooth": col("#D9CFA4"),
    "tooth_dark": col("#A89A68"),
    "sclera": col("#DCD5C8"),
    "iris": col("#8A3A40"),
    "pupil": col("#0C0809"),
    "claw": col("#170E0F"),
    "finger": col("#4E2A2C"),
    "ear_in": [col("#C9A2A2"), col("#B08488"), col("#906A72")],
    "badge": col("#D8C98A"),
    "ink": col("#2A1C14"),
}


def disc(r, cx, cy, rad, c):
    for y in range(int(cy - rad - 1), int(cy + rad + 2)):
        for x in range(int(cx - rad - 1), int(cx + rad + 2)):
            if (x - cx) ** 2 + (y - cy) ** 2 <= rad * rad:
                r.dot(x, y, c)


def stitch_line(r, x0, y0, x1, y1, c, every=2, cross=1):
    n = max(abs(x1 - x0), abs(y1 - y0), 1)
    dx, dy = (x1 - x0) / n, (y1 - y0) / n
    for i in range(int(n) + 1):
        x, y = x0 + dx * i, y0 + dy * i
        r.dot(round(x), round(y), c)
        if i % every == 0 and cross:
            # short cross stitch perpendicular to the line
            px, py = -dy, dx
            for k in range(1, cross + 1):
                r.dot(round(x + px * k), round(y + py * k), c)
                r.dot(round(x - px * k), round(y - py * k), c)


def paint_monster_skin(r, rng, base=0.33, blotchy=True):
    skin = MON["skin"]
    field = base + 0.35 * (value_noise(r.h, r.w, 4, rng) - 0.5) + 0.12 * (rng.random((r.h, r.w)) - 0.5)
    r.tones(skin, field)
    if blotchy:
        blot = value_noise(r.h, r.w, 5, rng)
        v = r.view
        mask = blot > 0.72
        v[mask] = lerp(v[mask], MON["blotch"], 0.55)
        mask = blot < 0.18
        v[mask] = lerp(v[mask], MON["bruise"], 0.35)


def paint_torn(r, rng, tones, holes=2, hem=True, base=0.32):
    """Dirty orange cloth with skin showing through ragged holes and a ragged dark hem."""
    paint_cloth(r, tones, rng, grad=0.25, base=base, blotch=0.35, folds=3, cell=5)
    v = r.view
    stains = value_noise(r.h, r.w, 6, rng)
    m = stains > 0.75
    v[m] = lerp(v[m], MON["stain"], 0.5)
    for _ in range(holes):
        # a ragged tear: a few overlapping blobs near one side, skin showing through
        cx = int(rng.choice([rng.integers(2, r.w // 3), rng.integers(2 * r.w // 3, r.w - 2)]))
        cy = int(rng.integers(r.h // 3, r.h - 5))
        for _blob in range(3):
            bx, by = cx + int(rng.integers(-2, 3)), cy + int(rng.integers(-2, 3))
            rx, ry = float(rng.uniform(1.0, 2.6)), float(rng.uniform(0.8, 1.8))
            for y in range(by - 3, by + 4):
                for x in range(bx - 4, bx + 5):
                    d = ((x - bx) / rx) ** 2 + ((y - by) / ry) ** 2
                    if d <= 1.0:
                        r.dot(x, y, MON["skin"][2] if rng.random() < 0.5 else MON["skin"][1])
                    elif d <= 1.8 and rng.random() < 0.6:
                        r.dot(x, y, tones[3])
    if hem:
        for x in range(r.w):
            depth = int(rng.integers(1, 4))
            r.rect(x, r.h - depth, 1, depth, tones[3])
            if rng.random() < 0.3:
                r.dot(x, r.h - depth - 1, MON["stain"])


def paint_monster_face(r, rng):
    """48 x 40, top row = top of the head (z 2.30), mouth line (jaw split) at row 27."""
    paint_monster_skin(r, rng, base=0.22)
    w, h = r.w, r.h
    v = r.view
    # darker sides for volume
    for x in range(w):
        e = min(x, w - 1 - x)
        if e < 4:
            v[:, x] = lerp(v[:, x], MON["skin"][3], 0.45 - e * 0.1)
    # --- big round dead eye (monster's left = viewer's right) ---
    ex, ey = 34.0, 13.0
    disc(r, ex, ey, 8.2, MON["bruise"])
    disc(r, ex, ey, 7.2, mul(MON["bruise"], 0.7))
    disc(r, ex, ey, 6.2, MON["sclera"])
    for y in range(int(ey - 7), int(ey + 7)):
        for x in range(int(ex - 7), int(ex + 7)):
            d = math.hypot(x - ex, y - ey)
            if 5.0 < d <= 6.3 and rng.random() < 0.5:
                r.dot(x, y, col("#C0A8A0"))   # bloodshot rim
    disc(r, ex + 0.4, ey + 0.3, 3.4, MON["iris"])
    disc(r, ex + 0.4, ey + 0.3, 2.4, col("#B89A94"))
    disc(r, ex + 0.4, ey + 0.3, 1.1, MON["pupil"])
    r.dot(ex - 2, ey - 3, col("#F2EEE4"))
    # --- smaller, squinting eye ---
    sx, sy = 14.0, 14.0
    disc(r, sx, sy, 5.4, MON["bruise"])
    disc(r, sx, sy + 0.6, 3.6, MON["sclera"])
    r.rect(int(sx - 5), int(sy - 5), 11, 5, MON["skin"][2])   # heavy drooping lid
    r.rect(int(sx - 4), int(sy - 1), 9, 1, MON["stitch"])
    disc(r, sx + 0.5, sy + 1.2, 1.6, MON["iris"])
    r.dot(sx + 0.5, sy + 1.2, MON["pupil"])
    # stitches: forehead seam down to the small eye, a cheek seam, one over the big eye
    stitch_line(r, 18, 0, 15, 8, MON["stitch"])
    stitch_line(r, 5, 18, 9, 25, MON["stitch"])
    stitch_line(r, 41, 3, 44, 9, MON["stitch"])
    # --- nose ---
    r.rect(21, 19, 6, 1, col("#A86A6E"))
    r.rect(22, 20, 4, 1, col("#A86A6E"))
    r.rect(23, 21, 2, 1, col("#8E5056"))
    r.dot(22, 20, MON["mouth"])
    r.dot(25, 20, MON["mouth"])
    # --- the grin: very wide crescent, red lips, rows of yellow teeth ---
    def mouth_y(x):
        return 27.0 - 5.5 * ((x - 24.0) / 20.0) ** 2

    for x in range(5, w - 5):
        my = mouth_y(x)
        top = int(round(my))
        edge = abs(x - 24) > 17
        # upper lip
        r.dot(x, top - 4, MON["lip_dark"])
        r.dot(x, top - 3, MON["lip"])
        if not edge:
            # upper teeth (2 px wide, dark gaps, a few missing)
            gap = (x % 3 == 0)
            missing = x in (9, 30, 38)
            c = MON["mouth"] if (gap or missing) else (MON["tooth"] if (x // 3) % 2 else MON["tooth_dark"])
            r.dot(x, top - 2, c)
            r.dot(x, top - 1, c if not gap else MON["mouth"])
            r.dot(x, top, MON["mouth"])
            # lower teeth, shorter and fewer
            gap2 = (x % 3 == 1)
            c2 = MON["mouth"] if (gap2 or x in (14, 27, 33)) else MON["tooth_dark"]
            r.dot(x, top + 1, c2)
            r.dot(x, top + 2, MON["lip"])
            r.dot(x, top + 3, MON["lip_dark"])
        else:
            r.dot(x, top - 2, MON["mouth"])
            r.dot(x, top - 1, MON["lip"])
            r.dot(x, top, MON["lip_dark"])
    # cheeks pushed up by the grin
    for cx in (6, 42):
        for y in range(18, 23):
            r.dot(cx, y, MON["skin"][3])
    # chin and jaw seam shadow
    r.rect(14, h - 3, 20, 1, MON["skin"][3])
    r.rect(0, h - 1, w, 1, MON["skin"][3])


def paint_monster_atlas(atlas, rng):
    paint_monster_face(atlas["m_face"], rng)
    r = atlas["m_head_side"]
    paint_monster_skin(r, rng, base=0.36)
    stitch_line(r, r.w // 2, 2, r.w // 2 + 3, r.h - 6, MON["stitch"])
    r = atlas["m_head_back"]
    paint_monster_skin(r, rng, base=0.42)
    stitch_line(r, r.w // 2, 0, r.w // 2 + 1, r.h - 2, MON["stitch"], every=3)
    paint_monster_skin(atlas["m_head_top"], rng, base=0.3)
    atlas["m_mouth"].fill(MON["mouth"])
    atlas["m_mouth"].rect(0, 0, 8, 2, MON["lip_dark"])
    paint_monster_skin(atlas["m_skin"], rng, base=0.36)
    # forearms and shins: mottled skin darkening into dirty, blood-dark hands and feet (no gore)
    r = atlas["m_limb_low"]
    paint_monster_skin(r, rng, base=0.40)
    g = r.grad_y()[..., None]
    v = r.view
    v[:] = lerp(v, MON["blotch"][None, None, :], np.clip((g - 0.35) * 1.2, 0.0, 0.55))
    v[:] = lerp(v, MON["finger"][None, None, :], np.clip((g - 0.7) * 2.0, 0.0, 0.6))
    r = atlas["m_belly"]
    paint_monster_skin(r, rng, base=0.2)
    v = r.view
    yy, xx = np.mgrid[0:r.h, 0:r.w].astype(np.float32)
    d = np.hypot((xx - r.w * 0.5) / (r.w * 0.5), (yy - r.h * 0.42) / (r.h * 0.55))
    v[:] = lerp(v, MON["skin"][0][None, None, :], np.clip(0.45 - d, 0.0, 0.4)[..., None])
    v[:] = lerp(v, MON["skin"][3][None, None, :], np.clip((d - 0.75) * 1.4, 0.0, 0.6)[..., None])
    v[:] = lerp(v, col("#C49C9C")[None, None, :], 0.25)
    stitch_line(r, 7, 7, 14, 27, MON["stitch"], every=3)
    disc(r, 17, 21, 1.2, MON["skin"][3])          # navel
    for y in range(7, 18):                        # a swollen lump on its left side
        for x in range(20, 31):
            dd = math.hypot(x - 25.5, y - 12.5)
            if dd <= 4.5:
                r.dot(x, y, lerp(r.view[y, x], MON["blotch"], 0.35 if dd > 3 else 0.15))
    r.rect(25, 9, 2, 1, MON["skin"][0])
    r = atlas["m_belly_side"]
    paint_monster_skin(r, rng, base=0.42)
    paint_torn(atlas["m_shirt_front"], rng, MON["shirt"], holes=1, hem=True)
    r = atlas["m_shirt_front"]
    # collar V and lapels
    for i in range(6):
        r.dot(13 + i, i, MON["shirt"][3])
        r.dot(18 - i + 1, i, MON["shirt"][3])
    r.rect(14, 0, 4, 3, MON["skin"][2])
    r.rect(8, 0, 5, 2, MON["shirt"][0])
    r.rect(19, 0, 5, 2, MON["shirt"][0])
    r = atlas["m_collar"]
    paint_cloth(r, MON["shirt"], rng, grad=0.3, base=0.2)
    r.rect(0, r.h - 2, r.w, 2, MON["shirt"][3])
    paint_torn(atlas["m_shirt_back"], rng, MON["shirt"], holes=2, hem=True)
    r = atlas["m_shirt_back"]
    r.rect(8, 5, 16, 6, col("#A8A698"))               # filthy back patch
    f = value_noise(6, 16, 3, rng)
    for yy in range(6):
        for xx in range(16):
            if f[yy, xx] > 0.6:
                r.dot(8 + xx, 5 + yy, col("#7C7466"))
    paint_torn(atlas["m_shirt_side"], rng, MON["shirt"], holes=1, hem=True, base=0.4)
    paint_torn(atlas["m_sleeve"], rng, MON["shirt"], holes=0, hem=True)
    paint_torn(atlas["m_shorts"], rng, MON["shirt"], holes=1, hem=False, base=0.36)
    atlas["m_shorts"].rect(15, 0, 1, 10, MON["shirt"][3])
    paint_torn(atlas["m_shorts_leg"], rng, MON["shirt"], holes=1, hem=True, base=0.36)
    r = atlas["m_hand"]
    paint_monster_skin(r, rng, base=0.55)
    g = r.grad_y()
    v = r.view
    v[:] = lerp(v, MON["finger"][None, None, :], np.clip(g[..., None] * 1.5 + 0.25, 0.0, 1.0))
    v[g > 0.62] = MON["claw"]
    v[(g > 0.55) & (g <= 0.62)] = lerp(MON["finger"], MON["claw"], 0.6)
    r = atlas["m_claw"]
    r.fill(MON["claw"])
    r.rect(0, 0, 8, 2, col("#3A2424"))
    r = atlas["m_foot"]
    paint_monster_skin(r, rng, base=0.42)
    r.rect(0, r.h - 3, r.w, 3, MON["skin"][3])
    for x in range(1, r.w, 5):
        r.rect(x, r.h - 4, 3, 3, MON["claw"])        # toenails on the front face
    r = atlas["m_ear_in"]
    paint_skin(r, MON["ear_in"], rng, base=0.35, blotch=0.3)
    r.rect(0, 0, 2, r.h, MON["skin"][2])
    r.rect(r.w - 2, 0, 2, r.h, MON["skin"][2])
    stitch_line(r, r.w // 2, r.h - 4, r.w // 2, r.h // 2, MON["stitch"])
    r = atlas["m_ear_out"]
    paint_monster_skin(r, rng, base=0.36)
    for _ in range(3):  # tears along the edge
        y = int(rng.integers(2, r.h - 4))
        r.rect(0, y, 3, 2, MON["bruise"])
    paint_badge(atlas["m_badge"], "BOB", MON["badge"], MON["ink"], frame=col("#8A7A48"))
    v = atlas["m_badge"].view
    v[:] = v * (0.8 + 0.25 * rng.random((v.shape[0], v.shape[1], 1)))
    atlas["m_badge_edge"].fill(MON["badge"])


def poly_front_y(points, x):
    """y of the front (most negative y) edge of a closed 2D polygon at abscissa x."""
    best = None
    n = len(points)
    for i in range(n):
        (x0, y0), (x1, y1) = points[i], points[(i + 1) % n]
        if min(x0, x1) <= x <= max(x0, x1) and x0 != x1:
            y = y0 + (y1 - y0) * (x - x0) / (x1 - x0)
            best = y if best is None else min(best, y)
    return best if best is not None else 0.0


def align_matrix(direction, origin):
    """Rotation taking -Z onto `direction`, then translation to origin."""
    d = Vector(direction).normalized()
    q = Vector((0.0, 0.0, -1.0)).rotation_difference(d)
    return Matrix.Translation(Vector(origin)) @ q.to_matrix().to_4x4()


def ellipsoid_rings(center, radii, n_rings, z_from=-1.0, z_to=1.0):
    """Path points and (hx, hy) for lofting an ellipsoid between relative heights z_from..z_to."""
    cx, cy, cz = center
    rx, ry, rz = radii
    pts, secs = [], []
    a0, a1 = math.acos(max(-1.0, min(1.0, z_from))), math.acos(max(-1.0, min(1.0, z_to)))
    for i in range(n_rings):
        a = a0 + (a1 - a0) * i / (n_rings - 1)
        k = max(math.sin(a), 0.08)
        pts.append((cx, cy, cz + rz * math.cos(a)))
        secs.append((rx * k, ry * k))
    return pts, secs


def build_monster(scene):
    rng = np.random.default_rng(97)
    regions = [
        ("m_face", 48, 40), ("m_head_side", 24, 32), ("m_head_back", 24, 24), ("m_head_top", 16, 16),
        ("m_mouth", 8, 8), ("m_skin", 24, 24), ("m_belly", 32, 32), ("m_belly_side", 16, 24),
        ("m_shirt_front", 32, 32), ("m_shirt_back", 32, 32), ("m_shirt_side", 16, 32), ("m_sleeve", 16, 16),
        ("m_shorts", 32, 16), ("m_shorts_leg", 16, 24), ("m_hand", 16, 24), ("m_claw", 8, 8),
        ("m_foot", 16, 16), ("m_ear_in", 16, 32), ("m_ear_out", 16, 32), ("m_badge", 24, 9),
        ("m_badge_edge", 4, 4), ("m_collar", 16, 8), ("m_limb_low", 16, 24),
    ]
    atlas = Atlas("monster_tex", regions, 97)
    paint_monster_atlas(atlas, rng)
    J = MONSTER_JOINTS
    B = Builder(atlas, MONSTER_BONES)
    skin = {"all": "m_skin"}

    # ---- head: cranium (head bone) + jaw (jaw bone) share one face projection ----
    fproj = ((-0.345, -0.72, 1.72), (0.345, -0.16, 2.345))
    face_regions = {"front": "m_face", "side": "m_head_side", "back": "m_head_back", "top": "m_head_top",
                    "bottom": "m_mouth"}
    cran = [(1.92, 0.330, 0.230, -0.45), (2.01, 0.345, 0.250, -0.44), (2.12, 0.335, 0.255, -0.43),
            (2.22, 0.300, 0.240, -0.415), (2.30, 0.215, 0.180, -0.40), (2.345, 0.11, 0.10, -0.40)]
    B.loft([(0, cy, z) for z, _, _, cy in cran], [sec_ellipse(a, b, 12) for _, a, b, _ in cran], "head",
           face_regions, proj=fproj, bias=(1.0, 1.2, 1.0))
    jaw = [(1.925, 0.322, 0.220, -0.455), (1.85, 0.29, 0.205, -0.465), (1.77, 0.19, 0.15, -0.47),
           (1.72, 0.09, 0.08, -0.465)]
    B.loft([(0, cy, z) for z, _, _, cy in jaw], [sec_ellipse(a, b, 12) for _, a, b, _ in jaw], "jaw",
           {"front": "m_face", "side": "m_head_side", "back": "m_head_back", "top": "m_mouth",
            "bottom": "m_head_side"}, proj=fproj, bias=(1.0, 1.2, 1.0))
    # inner mouth (dark throat box, visible when the jaw opens)
    B.loft([(0, -0.48, 1.865), (0, -0.48, 1.95)], [sec_rect(0.20, 0.13, 0.05)], "head", {"all": "m_mouth"})
    # bulging big eye and the smaller one: discs that pick up the painted eyes via the face projection
    for (x, z, rad, depth) in ((0.144, 2.142, 0.108, 0.032), (-0.144, 2.126, 0.072, 0.018)):
        ring = ring_at(cran, z)
        y_front = ring[3] + poly_front_y(sec_ellipse(ring[1], ring[2], 12), x) + 0.012
        B.loft([(x, y_front + 0.01, z), (x, y_front - depth, z)],
               [sec_ellipse(rad, rad * 0.95, 8), sec_ellipse(rad * 0.82, rad * 0.78, 8)], "head",
               {"front": "m_face", "all": "m_face"}, hint=(1, 0, 0), proj=fproj)
    # ears: flat tapering blades; L stands up and folds forward at the tip, R flops outward (torn)
    ear_l = [(0.14, -0.41, 2.25), (0.17, -0.39, 2.38), (0.20, -0.38, 2.50), (0.21, -0.44, 2.585),
             (0.21, -0.55, 2.575)]
    ear_r = [(-0.14, -0.41, 2.25), (-0.22, -0.39, 2.38), (-0.34, -0.39, 2.46), (-0.48, -0.41, 2.46),
             (-0.60, -0.44, 2.37)]
    ear_secs = [sec_rect(0.045, 0.024, 0.009), sec_rect(0.074, 0.026, 0.011), sec_rect(0.078, 0.022, 0.011),
                sec_rect(0.064, 0.018, 0.009), sec_rect(0.024, 0.011, 0.004)]
    B.loft(ear_l, ear_secs, "ear.L", {"front": "m_ear_in", "all": "m_ear_out"}, hint=(1, 0, 0))
    B.loft(ear_r, ear_secs, "ear.R", {"front": "m_ear_in", "all": "m_ear_out", "top": "m_ear_in"},
           hint=(0, 0, 1))

    # ---- neck, torso, belly ----
    B.loft([(0, -0.16, 1.74), (0, -0.24, 1.84), (0, -0.31, 1.93)],
           [sec_ellipse(0.10, 0.09, 8), sec_ellipse(0.09, 0.085, 8), sec_ellipse(0.10, 0.09, 8)], "neck", skin)
    shirt_regions = {"front": "m_shirt_front", "back": "m_shirt_back", "side": "m_shirt_side",
                     "top": "m_shirt_side", "bottom": "m_shirt_side"}
    chest = [(1.40, 0.26, 0.19, -0.03), (1.54, 0.29, 0.205, -0.085), (1.67, 0.325, 0.20, -0.145),
             (1.77, 0.325, 0.175, -0.195), (1.845, 0.18, 0.12, -0.235)]
    tproj = ((-0.325, -0.42, 1.06), (0.325, 0.22, 1.845))
    B.loft([(0, -0.215, 1.79), (0, -0.25, 1.875)], [sec_ellipse(0.18, 0.14, 10), sec_ellipse(0.165, 0.13, 10)],
           "chest", {"all": "m_collar"}, ragged=(-1, 0.025, rng), caps=(False, False))
    B.loft([(0, cy, z) for z, _, _, cy in chest], [sec_ellipse(a, b, 10) for _, a, b, _ in chest], "chest",
           shirt_regions, proj=tproj, ragged=(0, 0.035, rng))
    lower = [(1.06, 0.25, 0.19, 0.035), (1.28, 0.265, 0.195, 0.01), (1.47, 0.265, 0.192, -0.03)]
    B.loft([(0, cy, z) for z, _, _, cy in lower], [sec_ellipse(a, b, 10) for _, a, b, _ in lower], "spine",
           shirt_regions, proj=tproj, ragged=(0, 0.03, rng))
    pts, secs = ellipsoid_rings((0.0, -0.13, 1.17), (0.30, 0.30, 0.31), 8, -0.9, 0.88)
    B.loft(pts, [sec_ellipse(a, b, 12) for a, b in secs], "spine",
           {"front": "m_belly", "side": "m_belly_side", "all": "m_belly_side"}, bias=(1.0, 1.25, 1.0))
    # badge on the shirt's left chest, tilted with the hunched chest
    bz0, bz1 = 1.47, 1.57
    bx0, bx1 = 0.105, 0.255

    def chest_front(x, z):
        r0 = ring_at(chest, z)
        return r0[3] + poly_front_y(sec_ellipse(r0[1], r0[2], 10), x) - 0.008

    zc = (bz0 + bz1) * 0.5
    y0, y1 = chest_front(bx0, zc), chest_front(bx1, zc)
    across = Vector((bx1 - bx0, y1 - y0, 0.0)).normalized()
    half = Vector((bx1 - bx0, y1 - y0, 0.0)).length * 0.5
    mid = Vector(((bx0 + bx1) * 0.5, (y0 + y1) * 0.5 - 0.004, 0.0))
    B.loft([(mid.x, mid.y + (chest_front(0.18, bz0) - chest_front(0.18, zc)), bz0),
            (mid.x, mid.y + (chest_front(0.18, bz1) - chest_front(0.18, zc)), bz1)],
           [sec_rect(half, 0.006, 0.0)], "chest", {"front": "m_badge", "all": "m_badge_edge"},
           hint=tuple(across))

    # ---- hips / shorts / legs ----
    pel = [(0.80, 0.25, 0.18, 0.02), (0.94, 0.29, 0.21, 0.02), (1.10, 0.27, 0.20, 0.03)]
    B.loft([(0, cy, z) for z, _, _, cy in pel], [sec_ellipse(a, b, 10) for _, a, b, _ in pel], "hips",
           {"all": "m_shorts", "side": "m_shorts_leg"})
    for side, m in (("L", 1), ("R", -1)):
        hip, knee = Vector(J["thigh." + side][0]), Vector(J["thigh." + side][1])
        heel, toe = Vector(J["foot." + side][0]), Vector(J["foot." + side][1])
        # torn shorts leg (wide, ragged hem) over a thin bare thigh
        B.loft([hip + Vector((0, 0, 0.06)), hip + (knee - hip) * 0.55],
               [sec_ellipse(0.14, 0.135, 9), sec_ellipse(0.135, 0.13, 9)], "thigh." + side,
               {"all": "m_shorts_leg"}, ragged=(-1, 0.04, rng), caps=(True, False))
        B.loft([hip + (knee - hip) * 0.4, knee + (knee - hip).normalized() * 0.02],
               [sec_ellipse(0.09, 0.085, 7), sec_ellipse(0.072, 0.07, 7)], "thigh." + side, skin)
        # shin: knobbly knee to the raised heel
        B.loft([knee + Vector((0, -0.02, 0.03)), knee + (heel - knee) * 0.5, heel + Vector((0, 0.0, -0.02))],
               [sec_ellipse(0.08, 0.075, 7), sec_ellipse(0.062, 0.064, 7), sec_ellipse(0.054, 0.058, 7)],
               "shin." + side, {"all": "m_limb_low"})
        # long digitigrade foot: heel high, ball and splayed toes on the floor
        ball = Vector((toe.x, toe.y + 0.13, 0.045))
        B.loft([heel + Vector((0, 0.02, 0.02)), ball, Vector((toe.x, toe.y, 0.03)), Vector((toe.x, toe.y - 0.045, 0.02))],
               [sec_rect(0.05, 0.045, 0.012), sec_rect(0.066, 0.05, 0.014), sec_rect(0.078, 0.032, 0.01),
                sec_rect(0.066, 0.018, 0.006)], "foot." + side, {"all": "m_foot"}, hint=(1, 0, 0))

    # ---- arms ----
    for side, m in (("L", 1), ("R", -1)):
        sh, el = Vector(J["upper_arm." + side][0]), Vector(J["upper_arm." + side][1])
        wr, he = Vector(J["hand." + side][0]), Vector(J["hand." + side][1])
        d = (el - sh).normalized()
        B.loft([sh - d * 0.06 + Vector((0, 0, 0.03)), sh + (el - sh) * 0.42],
               [sec_ellipse(0.11, 0.105, 8), sec_ellipse(0.10, 0.095, 8)], "upper_arm." + side,
               {"all": "m_sleeve", "top": "m_shirt_side"}, ragged=(-1, 0.035, rng), caps=(True, False))
        B.loft([sh + (el - sh) * 0.3, el + d * 0.03],
               [sec_ellipse(0.068, 0.066, 7), sec_ellipse(0.055, 0.055, 7)], "upper_arm." + side, skin)
        fd = (wr - el).normalized()
        B.loft([el - fd * 0.03, el + (wr - el) * 0.5, wr + fd * 0.02],
               [sec_ellipse(0.06, 0.06, 7), sec_ellipse(0.048, 0.046, 7), sec_ellipse(0.042, 0.038, 7)],
               "forearm." + side, {"all": "m_limb_low"})
        # hand: palm facing back, long fingers fanned across the front view, claws hooking forward
        hd = (he - wr).normalized()
        M = align_matrix(hd, wr)
        R = M.to_3x3()
        hint = tuple(R @ Vector((1, 0, 0)))

        def H(a, b, z):
            # local hand frame: a = outward from the body, b = forward, z along the hand (negative)
            return M @ Vector((m * a, -b, z))

        B.loft([H(0, 0, 0.02), H(0, 0, -0.08), H(0, 0.005, -0.16)],
               [sec_rect(0.05, 0.034, 0.01), sec_rect(0.066, 0.037, 0.012), sec_rect(0.07, 0.031, 0.01)],
               "hand." + side, {"all": "m_hand"}, hint=hint)
        for fa, length, spread in ((-0.054, 0.27, -0.35), (-0.018, 0.32, -0.12), (0.018, 0.31, 0.12),
                                   (0.054, 0.25, 0.35)):
            z0 = -0.15
            pts = [H(fa, 0.0, z0),
                   H(fa + spread * 0.25 * length, 0.012, z0 - length * 0.40),
                   H(fa + spread * 0.5 * length, 0.04, z0 - length * 0.75),
                   H(fa + spread * 0.6 * length, 0.085, z0 - length)]
            B.loft(pts, [sec_rect(0.017, 0.016), sec_rect(0.015, 0.014), sec_rect(0.011, 0.01),
                         sec_rect(0.003, 0.003)], "hand." + side, {"all": "m_hand"}, hint=hint)
        # thumb on the inner side, hooking forward and down
        pts = [H(-0.06, 0.01, -0.06), H(-0.11, 0.05, -0.12), H(-0.13, 0.09, -0.21)]
        B.loft(pts, [sec_rect(0.017, 0.016), sec_rect(0.013, 0.012), sec_rect(0.003, 0.003)], "hand." + side,
               {"all": "m_hand"}, hint=hint)

    img = atlas.to_image()
    mat = make_material("monster_mat", img)
    mesh = B.to_object("monster_body", scene, mat)
    rig = build_armature("monster", scene, J, MONSTER_BONES)
    tris = finish_character(scene, "monster", mesh, rig)
    anim = Animator(rig, "monster", [("foot.L", "head", 0.20), ("foot.R", "head", 0.20),
                                     ("foot.L", "tail", 0.02), ("foot.R", "tail", 0.02)])
    monster_actions(anim)
    return rig, mesh, anim, tris


def monster_actions(anim):
    def limp_arms(t, amp=6.0, lag=0.0):
        out = {}
        for side, ph in (("L", 0.0), ("R", 0.45)):
            out["upper_arm." + side] = (amp * wave(t, 1.0, ph + lag), 1.5 * wave(t, 1.0, ph + 0.2), 0.0)
            out["forearm." + side] = (amp * 0.9 * wave(t, 1.0, ph + lag - 0.12), 0.0, 0.0)
            out["hand." + side] = (amp * 1.3 * wave(t, 1.0, ph + lag - 0.25), 0.0, 0.0)
        return out

    def idle(t):
        b = wave(t)
        b2 = wave(t, 1.0, 0.25)
        pose = {
            "hips": (0.0, 2.5 * b, 1.5 * b2),
            "spine": (1.5 * wave(t, 1.0, 0.1), -1.5 * b, -1.0 * b2),
            "chest": (3.0 * wave(t, 1.0, 0.15), -2.0 * b, -1.5 * b2),
            "neck": (3.0 * wave(t, 1.0, 0.3), 0.0, 2.0 * b2),
            "head": (2.0 * wave(t, 1.0, 0.4), 8.0 * wave(t, 1.0, 0.05), 4.0 * b2),
            "jaw": (2.0 + 2.0 * wave(t, 2.0), 0.0, 0.0),
            "ear.L": (5.0 * wave(t, 1.0, 0.2), 0.0, 0.0),
            "ear.R": (0.0, 6.0 * wave(t, 1.0, 0.35), 0.0),
            "thigh.L": (0.0, 0.0, -2.0 * b), "thigh.R": (0.0, 0.0, -2.0 * b),
        }
        return add_pose(pose, limp_arms(t, 6.0, -0.1))

    def walk(t):
        s, c = wave(t), wavec(t)
        pose = {}
        for side, m in (("L", 1.0), ("R", -1.0)):
            th = -24.0 * s * m
            swing = max(0.0, c * m)
            pose["thigh." + side] = (th, 0.0, 0.0)
            pose["shin." + side] = (-6.0 + 34.0 * swing, 0.0, 0.0)
            pose["foot." + side] = (-(th - 6.0 + 34.0 * swing) * 0.7, 0.0, 0.0)
            pose["upper_arm." + side] = (16.0 * s * m, 0.0, 0.0)
            pose["forearm." + side] = (12.0 * wave(t, 1.0, -0.1 * m) * m - 4.0, 0.0, 0.0)
            pose["hand." + side] = (14.0 * wave(t, 1.0, -0.2 * m) * m, 0.0, 0.0)
        pose["hips"] = (0.0, 4.0 * s, -7.0 * s)
        pose["spine"] = (2.0, -2.0 * s, 4.0 * s)
        pose["chest"] = (2.0 + 1.5 * wave(t, 2.0), -2.0 * s, 6.0 * s)
        pose["neck"] = (-2.0, 0.0, -4.0 * s)
        pose["head"] = (-1.5 * wave(t, 2.0, 0.15), 3.0 * s, -3.0 * s)
        pose["jaw"] = (3.0, 0.0, 0.0)
        pose["ear.L"] = (4.0 * wave(t, 2.0, 0.3), 0.0, 0.0)
        pose["ear.R"] = (0.0, 5.0 * wave(t, 2.0, 0.4), 0.0)
        return pose

    def run(t):
        s, c = wave(t), wavec(t)
        pose = {}
        for side, m in (("L", 1.0), ("R", -1.0)):
            th = -52.0 * s * m
            swing = max(0.0, c * m)
            pose["thigh." + side] = (th - 8.0, 0.0, 0.0)
            pose["shin." + side] = (72.0 * swing, 0.0, 0.0)
            pose["foot." + side] = (-(th + 72.0 * swing) * 0.5, 0.0, 0.0)
            # arms thrown forward, clawing alternately
            pose["upper_arm." + side] = (-62.0 + 26.0 * s * m, -m * 8.0, 0.0)
            pose["forearm." + side] = (-18.0 + 20.0 * s * m, 0.0, 0.0)
            pose["hand." + side] = (-15.0 + 10.0 * s * m, 0.0, 0.0)
        pose["hips"] = (12.0, 5.0 * s, -10.0 * s)
        pose["spine"] = (12.0, -3.0 * s, 7.0 * s)
        pose["chest"] = (8.0 + 4.0 * wave(t, 2.0), -2.0 * s, 9.0 * s)
        pose["neck"] = (-20.0, 0.0, -5.0 * s)
        pose["head"] = (-14.0 + 4.0 * wave(t, 2.0, 0.2), 4.0 * s, -4.0 * s)
        pose["jaw"] = (10.0 + 4.0 * wave(t, 2.0), 0.0, 0.0)
        pose["ear.L"] = (14.0 + 6.0 * wave(t, 2.0, 0.3), 0.0, 0.0)
        pose["ear.R"] = (8.0, 10.0 * wave(t, 2.0, 0.4), 0.0)
        pose["@lift"] = 0.05 * max(0.0, wave(t, 2.0, 0.1))
        return pose

    rest = {}
    windup = {
        "hips": (-4.0, 0.0, 10.0), "spine": (-6.0, 0.0, 8.0), "chest": (-8.0, 0.0, 14.0),
        "neck": (4.0, 0.0, -6.0), "head": (2.0, -6.0, -8.0), "jaw": (22.0, 0.0, 0.0),
        "upper_arm.R": (-95.0, 35.0, 0.0), "forearm.R": (-35.0, 0.0, 0.0), "hand.R": (-20.0, 0.0, 0.0),
        "upper_arm.L": (-35.0, -10.0, 0.0), "forearm.L": (-20.0, 0.0, 0.0),
        "thigh.L": (-14.0, 0.0, 0.0), "shin.L": (8.0, 0.0, 0.0), "thigh.R": (10.0, 0.0, 0.0),
        "ear.L": (-12.0, 0.0, 0.0), "ear.R": (0.0, -12.0, 0.0),
        "@hips": (0.0, 0.08, 0.0),
    }
    strike = {
        "hips": (12.0, 0.0, -14.0), "spine": (14.0, 0.0, -10.0), "chest": (16.0, 0.0, -22.0),
        "neck": (-14.0, 0.0, 8.0), "head": (-10.0, 8.0, 10.0), "jaw": (32.0, 0.0, 0.0),
        "upper_arm.R": (-40.0, -20.0, 45.0), "forearm.R": (-10.0, 0.0, 0.0), "hand.R": (10.0, 0.0, 0.0),
        "upper_arm.L": (-55.0, -25.0, 0.0), "forearm.L": (-10.0, 0.0, 0.0),
        "thigh.L": (-34.0, 0.0, 0.0), "shin.L": (14.0, 0.0, 0.0), "foot.L": (16.0, 0.0, 0.0),
        "thigh.R": (22.0, 0.0, 0.0), "shin.R": (10.0, 0.0, 0.0), "foot.R": (-20.0, 0.0, 0.0),
        "ear.L": (18.0, 0.0, 0.0), "ear.R": (0.0, 14.0, 0.0),
        "@hips": (0.0, -0.38, 0.0),
    }
    follow = {
        "hips": (8.0, 0.0, -8.0), "spine": (8.0, 0.0, -6.0), "chest": (8.0, 0.0, -12.0),
        "neck": (-6.0, 0.0, 4.0), "head": (-4.0, 4.0, 6.0), "jaw": (14.0, 0.0, 0.0),
        "upper_arm.R": (-10.0, -10.0, 25.0), "forearm.R": (-8.0, 0.0, 0.0),
        "upper_arm.L": (-25.0, -10.0, 0.0),
        "thigh.L": (-18.0, 0.0, 0.0), "shin.L": (8.0, 0.0, 0.0), "foot.L": (8.0, 0.0, 0.0),
        "thigh.R": (12.0, 0.0, 0.0), "foot.R": (-10.0, 0.0, 0.0),
        "@hips": (0.0, -0.22, 0.0),
    }

    def attack(t):
        return keyed(t, [(0.0, rest), (0.32, windup), (0.5, strike), (0.66, follow), (1.0, rest)])

    upright = {
        "hips": (-4.0, 0.0, 0.0), "spine": (-14.0, 0.0, 0.0), "chest": (-16.0, 0.0, 0.0),
        "neck": (6.0, 0.0, 0.0), "head": (20.0, 0.0, 0.0), "jaw": (6.0, 0.0, 0.0),
        "thigh.L": (12.0, 0.0, 0.0), "thigh.R": (12.0, 0.0, 0.0),
        "shin.L": (-14.0, 0.0, 0.0), "shin.R": (-14.0, 0.0, 0.0),
        "foot.L": (4.0, 0.0, 0.0), "foot.R": (4.0, 0.0, 0.0),
        "upper_arm.L": (-10.0, -10.0, 0.0), "upper_arm.R": (-10.0, 10.0, 0.0),
        "ear.L": (-8.0, 0.0, 0.0), "ear.R": (0.0, 14.0, 0.0),
    }
    spread = dict(upright)
    spread.update({
        "upper_arm.L": (-22.0, -26.0, 0.0), "upper_arm.R": (-22.0, 26.0, 0.0),
        "forearm.L": (-12.0, -48.0, 0.0), "forearm.R": (-12.0, 48.0, 0.0),
        "hand.L": (-8.0, -22.0, 0.0), "hand.R": (-8.0, 22.0, 0.0),
        "neck": (8.0, 0.0, 0.0), "head": (22.0, 26.0, 0.0), "jaw": (36.0, 0.0, 0.0),
        "ear.L": (-10.0, 0.0, 0.0), "ear.R": (0.0, 22.0, 0.0),
    })

    def reveal(t):
        tremble = smooth(0.0, 0.1, t) * (1.0 - smooth(0.2, 0.3, t)) + smooth(0.65, 0.8, t)
        base = keyed(t, [(0.0, rest), (0.18, rest), (0.32, upright), (0.62, spread), (1.0, spread)])
        jitter = {
            "head": (2.5 * wave(t, 17.0), 2.0 * wave(t, 13.0, 0.3), 0.0),
            "chest": (1.0 * wave(t, 11.0, 0.1), 0.0, 0.0),
            "hand.L": (4.0 * wave(t, 15.0, 0.2), 0.0, 0.0),
            "hand.R": (4.0 * wave(t, 14.0, 0.6), 0.0, 0.0),
            "jaw": (3.0 * wave(t, 9.0), 0.0, 0.0),
        }
        return add_pose(base, scale_pose(jitter, tremble))

    anim.action("idle", 2.4, idle)
    anim.action("walk", 1.4, walk)
    anim.action("run", 0.6, run)
    anim.action("attack", 0.8, attack, loop=False)
    anim.action("reveal", 1.5, reveal, loop=False)


# =============================================================================
# Scene, export
# =============================================================================

def human_ground_points(p):
    return [("foot.L", "head", p["ankle_z"]), ("foot.R", "head", p["ankle_z"]),
            ("foot.L", "tail", 0.03), ("foot.R", "tail", 0.03)]


def finish_character(scene, name, mesh, rig):
    mesh.parent = rig
    mod = mesh.modifiers.new("Armature", "ARMATURE")
    mod.object = rig
    tris = triangle_count(mesh)
    print("[characters] %-16s tris=%d verts=%d" % (name, tris, len(mesh.data.vertices)))
    return tris


def build_human_character(scene, spec, actions_fn):
    mesh, J, p = build_human(scene, spec)
    rig = build_armature(spec["name"], scene, J, HUMAN_BONES)
    tris = finish_character(scene, spec["name"], mesh, rig)
    anim = Animator(rig, spec["name"], human_ground_points(p))
    actions_fn(anim)
    return rig, mesh, anim, tris


def new_scene(name):
    sc = bpy.data.scenes.new(name)
    sc.render.fps = FPS
    sc.frame_start = 0
    sc.frame_end = 60
    bpy.context.window.scene = sc
    return sc


def export_character(scene, name, rig, mesh, anim):
    bpy.context.window.scene = scene
    # Temporarily give this character's actions their plain contract names.
    for clip, act in anim.actions.items():
        act.name = clip
    for o in scene.objects:
        o.select_set(o in (rig, mesh))
    bpy.context.view_layer.objects.active = rig
    path = os.path.join(OUT_DIR, name + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, use_active_scene=True,
        export_yup=True, export_apply=False, export_texcoords=True, export_normals=True,
        export_tangents=False, export_materials="EXPORT", export_image_format="AUTO",
        export_cameras=False, export_lights=False, export_extras=False,
        export_skins=True, export_def_bones=False, export_leaf_bone=False,
        export_animations=True, export_animation_mode="ACTIONS", export_anim_single_armature=False,
        export_force_sampling=True, export_frame_step=1, export_anim_slide_to_zero=True,
        export_reset_pose_bones=True, export_optimize_animation_size=True,
        export_morph=False,
    )
    for clip, act in anim.actions.items():
        act.name = "%s.%s" % (anim.prefix, clip)
    write_import_file(name, anim.loops)
    print("[characters] exported", path)


IMPORT_PARAMS = """nodes/root_type=""
nodes/root_name=""
nodes/root_script=null
mesh_library/use_node_names_as_mesh_names=false
array_mesh/deduplicate_surfaces=true
nodes/apply_root_scale=true
nodes/root_scale=1.0
nodes/import_as_skeleton_bones=false
nodes/use_name_suffixes=true
nodes/use_node_type_suffixes=true
meshes/ensure_tangents=true
meshes/generate_lods=false
meshes/create_shadow_meshes=true
meshes/light_baking=1
meshes/lightmap_texel_size=0.2
meshes/force_disable_compression=false
skins/use_named_skins=true
animation/import=true
animation/fps=30
animation/trimming=false
animation/remove_immutable_tracks=true
animation/import_rest_as_RESET=false
import_script/path="res://assets/models/characters/character_import.gd"
materials/extract=0
materials/extract_format=0
materials/extract_path=""
_subresources={}
gltf/naming_version=2
gltf/embedded_image_handling=3
gltf/texture_map_mode=1
"""


def write_import_file(name, loops):
    """Writes the Godot import settings next to the GLB: textures stay embedded and uncompressed
    (no extracted PNG, no VRAM compression blurring the pixels), no LODs, and the post-import script
    that sets each clip's loop flag (glTF cannot store it). Godot's [remap] section (with the uid)
    is kept if present."""
    one_shot = sorted(clip for clip, loop in loops.items() if not loop)
    assert all(clip in ("attack", "reveal") for clip in one_shot), "update character_import.gd ONE_SHOT"
    path = os.path.join(OUT_DIR, name + ".glb.import")
    head = '[remap]\n\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n\n'
    if os.path.exists(path):
        with open(path, encoding="utf-8") as fh:
            old = fh.read()
        if "[params]" in old:
            head = old.split("[params]")[0]
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(head + "[params]\n\n" + IMPORT_PARAMS)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = set()
    if "--only" in argv:
        only = set(argv[argv.index("--only") + 1:])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    os.makedirs(OUT_DIR, exist_ok=True)
    first = bpy.context.window.scene
    specs = make_specs()
    built = []
    order = ["employee_dale", "employee_rita", "employee_marcus", "manager", "monster"]
    for name in order:
        if only and name not in only:
            continue
        sc = new_scene(name)
        if name == "monster":
            rig, mesh, anim, tris = build_monster(sc)
            budget = 3000
        else:
            fn = manager_actions if name == "manager" else employee_actions
            rig, mesh, anim, tris = build_human_character(sc, specs[name], fn)
            budget = 1500
        if tris > budget:
            raise RuntimeError("%s has %d triangles (budget %d)" % (name, tris, budget))
        built.append((sc, name, rig, mesh, anim))
    for sc, name, rig, mesh, anim in built:
        export_character(sc, name, rig, mesh, anim)
    if not only:
        if first.name not in [b[1] for b in built]:
            bpy.data.scenes.remove(first)
        bpy.context.window.scene = built[0][0]
        bpy.context.preferences.filepaths.save_version = 0  # no characters.blend1 backup
        bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH, compress=True)
        print("[characters] saved", BLEND_PATH)


if __name__ == "__main__":
    main()
