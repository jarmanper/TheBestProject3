"""Shared helpers for the props generator: pixel canvases, images, materials, mesh building
and glTF export. Blender 5.0, run through build_props.py.

Conventions (docs/ARCHITECTURE.md "Model orientation and scale"):
1 Blender unit = 1 m, Z up, models face Blender -Y (glTF/Godot +Z). Floor props have their
origin at the floor centre of their footprint; wall props at the wall-contact centre with the
back face on the plane y = 0 and the prop extending toward -Y.
"""
import math

import bpy
import numpy as np
from mathutils import Matrix, Vector

# --- colours ---------------------------------------------------------------

PALETTE = {
    "charcoal": "171B1A",   # Midnight Charcoal
    "orange": "E87932",     # Industrial Orange
    "olive": "626D58",      # Faded Olive
    "cream": "D8D3A8",      # Fluorescent Cream
    "red": "B93B32",        # Emergency Red
    "concrete": "444A48",   # Concrete Gray
}


def rgb(hex_or_name, alpha=1.0):
    """sRGB colour (0..1) as a numpy RGBA vector."""
    value = PALETTE.get(hex_or_name, hex_or_name).lstrip("#")
    r, g, b = (int(value[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    return np.array([r, g, b, alpha], dtype=np.float32)


def shade(color, factor):
    """Scales the RGB of a colour, keeps alpha."""
    out = np.array(color, dtype=np.float32).copy()
    out[:3] = np.clip(out[:3] * factor, 0.0, 1.0)
    return out


def mix(a, b, t):
    return (np.asarray(a, np.float32) * (1.0 - t) + np.asarray(b, np.float32) * t).astype(np.float32)


def srgb_to_linear(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


# --- pixel canvas ----------------------------------------------------------

FONT_3X5 = {
    "A": [".#.", "#.#", "###", "#.#", "#.#"], "B": ["##.", "#.#", "##.", "#.#", "##."],
    "C": [".##", "#..", "#..", "#..", ".##"], "D": ["##.", "#.#", "#.#", "#.#", "##."],
    "E": ["###", "#..", "##.", "#..", "###"], "F": ["###", "#..", "##.", "#..", "#.."],
    "G": [".##", "#..", "#.#", "#.#", ".##"], "H": ["#.#", "#.#", "###", "#.#", "#.#"],
    "I": ["###", ".#.", ".#.", ".#.", "###"], "J": ["..#", "..#", "..#", "#.#", ".#."],
    "K": ["#.#", "#.#", "##.", "#.#", "#.#"], "L": ["#..", "#..", "#..", "#..", "###"],
    "M": ["#.#", "###", "###", "#.#", "#.#"], "N": ["##.", "#.#", "#.#", "#.#", "#.#"],
    "O": ["###", "#.#", "#.#", "#.#", "###"], "P": ["##.", "#.#", "##.", "#..", "#.."],
    "Q": [".#.", "#.#", "#.#", "##.", ".##"], "R": ["##.", "#.#", "##.", "#.#", "#.#"],
    "S": [".##", "#..", ".#.", "..#", "##."], "T": ["###", ".#.", ".#.", ".#.", ".#."],
    "U": ["#.#", "#.#", "#.#", "#.#", "###"], "V": ["#.#", "#.#", "#.#", "#.#", ".#."],
    "W": ["#.#", "#.#", "###", "###", "#.#"], "X": ["#.#", "#.#", ".#.", "#.#", "#.#"],
    "Y": ["#.#", "#.#", ".#.", ".#.", ".#."], "Z": ["###", "..#", ".#.", "#..", "###"],
    "0": ["###", "#.#", "#.#", "#.#", "###"], "1": [".#.", "##.", ".#.", ".#.", "###"],
    "2": ["##.", "..#", ".#.", "#..", "###"], "3": ["##.", "..#", ".#.", "..#", "##."],
    "4": ["#.#", "#.#", "###", "..#", "..#"], "5": ["###", "#..", "##.", "..#", "##."],
    "6": [".##", "#..", "###", "#.#", "###"], "7": ["###", "..#", ".#.", ".#.", ".#."],
    "8": ["###", "#.#", "###", "#.#", "###"], "9": ["###", "#.#", "###", "..#", "##."],
    "!": [".#.", ".#.", ".#.", "...", ".#."], "-": ["...", "...", "###", "...", "..."],
    ":": ["...", ".#.", "...", ".#.", "..."], ".": ["...", "...", "...", "...", ".#."],
    "/": ["..#", "..#", ".#.", "#..", "#.."], " ": ["...", "...", "...", "...", "..."],
    "$": [".##", "##.", ".#.", ".##", "##."], "%": ["#.#", "..#", ".#.", "#..", "#.#"],
}


class Canvas:
    """RGBA float canvas in sRGB, row 0 at the top (like an image editor)."""

    def __init__(self, w, h, color=(0, 0, 0, 0), seed=1):
        self.w, self.h = w, h
        self.px = np.zeros((h, w, 4), dtype=np.float32)
        self.px[:, :] = np.asarray(color, dtype=np.float32)
        self.rng = np.random.default_rng(seed)

    # drawing -------------------------------------------------------------
    def rect(self, x0, y0, x1, y1, color, alpha=1.0):
        """Fills [x0, x1) x [y0, y1), blending with `alpha`."""
        x0, x1 = max(0, int(x0)), min(self.w, int(x1))
        y0, y1 = max(0, int(y0)), min(self.h, int(y1))
        if x0 >= x1 or y0 >= y1:
            return
        c = np.asarray(color, dtype=np.float32)
        region = self.px[y0:y1, x0:x1]
        region[:] = region * (1.0 - alpha) + c * alpha

    def outline(self, x0, y0, x1, y1, color, alpha=1.0):
        self.rect(x0, y0, x1, y0 + 1, color, alpha)
        self.rect(x0, y1 - 1, x1, y1, color, alpha)
        self.rect(x0, y0, x0 + 1, y1, color, alpha)
        self.rect(x1 - 1, y0, x1, y1, color, alpha)

    def dot(self, x, y, color, alpha=1.0):
        self.rect(x, y, x + 1, y + 1, color, alpha)

    def line(self, x0, y0, x1, y1, color, alpha=1.0):
        steps = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
        for i in range(steps):
            t = i / max(1, steps - 1)
            self.dot(round(x0 + (x1 - x0) * t), round(y0 + (y1 - y0) * t), color, alpha)

    def disc(self, cx, cy, r, color, alpha=1.0):
        yy, xx = np.mgrid[0:self.h, 0:self.w]
        mask = (xx + 0.5 - cx) ** 2 + (yy + 0.5 - cy) ** 2 <= r * r
        c = np.asarray(color, dtype=np.float32)
        self.px[mask] = self.px[mask] * (1.0 - alpha) + c * alpha

    def ring(self, cx, cy, r0, r1, color, alpha=1.0):
        yy, xx = np.mgrid[0:self.h, 0:self.w]
        d2 = (xx + 0.5 - cx) ** 2 + (yy + 0.5 - cy) ** 2
        mask = (d2 <= r1 * r1) & (d2 >= r0 * r0)
        c = np.asarray(color, dtype=np.float32)
        self.px[mask] = self.px[mask] * (1.0 - alpha) + c * alpha

    def text(self, x, y, string, color, alpha=1.0, scale=1, spacing=1):
        cx = x
        for ch in string.upper():
            glyph = FONT_3X5.get(ch, FONT_3X5[" "])
            for gy, row in enumerate(glyph):
                for gx, bit in enumerate(row):
                    if bit == "#":
                        self.rect(cx + gx * scale, y + gy * scale, cx + (gx + 1) * scale,
                                  y + (gy + 1) * scale, color, alpha)
            cx += (3 + spacing) * scale
        return cx

    @staticmethod
    def text_width(string, scale=1, spacing=1):
        return max(0, len(string) * (3 + spacing) * scale - spacing * scale)

    # texture ---------------------------------------------------------------
    def noise(self, amount, y0=0, y1=None, x0=0, x1=None):
        """Multiplies brightness by random per-pixel factors in [1-amount, 1+amount]."""
        y1 = self.h if y1 is None else y1
        x1 = self.w if x1 is None else x1
        n = 1.0 + (self.rng.random((y1 - y0, x1 - x0, 1)) * 2.0 - 1.0) * amount
        region = self.px[y0:y1, x0:x1, :3]
        region[:] = np.clip(region * n, 0.0, 1.0)

    def row_noise(self, amount):
        """Horizontal fibre streaks (whole rows brighter/darker)."""
        n = 1.0 + (self.rng.random((self.h, 1, 1)) * 2.0 - 1.0) * amount
        self.px[:, :, :3] = np.clip(self.px[:, :, :3] * n, 0.0, 1.0)

    def col_noise(self, amount):
        n = 1.0 + (self.rng.random((1, self.w, 1)) * 2.0 - 1.0) * amount
        self.px[:, :, :3] = np.clip(self.px[:, :, :3] * n, 0.0, 1.0)

    def speckle(self, probability, color, alpha=1.0, region=None):
        x0, y0, x1, y1 = region or (0, 0, self.w, self.h)
        mask = self.rng.random((y1 - y0, x1 - x0)) < probability
        c = np.asarray(color, dtype=np.float32)
        sub = self.px[y0:y1, x0:x1]
        sub[mask] = sub[mask] * (1.0 - alpha) + c * alpha

    def streaks(self, count, color, alpha, length=(3, 10), vertical=True):
        for _ in range(count):
            x = int(self.rng.integers(0, self.w))
            y = int(self.rng.integers(0, self.h))
            n = int(self.rng.integers(length[0], length[1] + 1))
            for i in range(n):
                if vertical:
                    self.dot(x, (y + i) % self.h, color, alpha * (1.0 - i / (n + 1)))
                else:
                    self.dot((x + i) % self.w, y, color, alpha * (1.0 - i / (n + 1)))

    def vgradient(self, top, bottom):
        """Multiplies brightness from `top` (row 0) to `bottom` (last row)."""
        f = np.linspace(top, bottom, self.h, dtype=np.float32)[:, None, None]
        self.px[:, :, :3] = np.clip(self.px[:, :, :3] * f, 0.0, 1.0)

    def edge_dark(self, amount, width=1):
        for i in range(width):
            f = 1.0 - amount * (1.0 - i / width)
            self.px[i, :, :3] *= f
            self.px[self.h - 1 - i, :, :3] *= f
            self.px[:, i, :3] *= f
            self.px[:, self.w - 1 - i, :3] *= f

    def paste(self, other, x, y):
        h, w = other.px.shape[:2]
        self.px[y:y + h, x:x + w] = other.px

    def image(self, name):
        return make_image(name, self.px)


def make_image(name, px):
    """Creates (or replaces) a packed Blender image from a top-down sRGB RGBA array."""
    old = bpy.data.images.get(name)
    if old is not None:
        bpy.data.images.remove(old)
    h, w = px.shape[:2]
    img = bpy.data.images.new(name, w, h, alpha=True)
    img.pixels.foreach_set(np.ascontiguousarray(np.clip(px[::-1], 0.0, 1.0)).ravel())
    img.pack()
    return img


def save_png(px, path):
    """Writes a top-down sRGB RGBA array to a PNG file via Blender's image API."""
    h, w = px.shape[:2]
    img = bpy.data.images.new("_png_out", w, h, alpha=True)
    img.pixels.foreach_set(np.ascontiguousarray(np.clip(px[::-1], 0.0, 1.0)).ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


# --- materials -------------------------------------------------------------

def material(name, image=None, color=None, rough=0.85, metal=0.0, emit=None, emit_strength=1.0,
             alpha=None, double=False):
    """Principled material. `image` is a Blender image (nearest-sampled), `color` an sRGB colour
    used when there is no image. `emit` is True (emit the image), an sRGB colour, or None.
    `alpha` is None, "CLIP" (glTF MASK) or "BLEND". Cached by name."""
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    mat = bpy.data.materials.new(name)
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    tex = None
    if image is not None:
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = image
        tex.interpolation = "Closest"
        tex.extension = "REPEAT"
        tex.location = (-400, 200)
        links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    elif color is not None:
        c = rgb(color) if isinstance(color, str) else np.asarray(color, np.float32)
        lin = srgb_to_linear(c[:3])
        bsdf.inputs["Base Color"].default_value = (lin[0], lin[1], lin[2], 1.0)
    if alpha is not None and tex is not None:
        if alpha == "CLIP":
            rnd = nodes.new("ShaderNodeMath")
            rnd.operation = "ROUND"
            rnd.location = (-150, -100)
            links.new(tex.outputs["Alpha"], rnd.inputs[0])
            links.new(rnd.outputs[0], bsdf.inputs["Alpha"])
        else:
            links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    if emit is not None:
        if emit is True and tex is not None:
            links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
        else:
            c = rgb(emit) if isinstance(emit, str) else np.asarray(emit, np.float32)
            lin = srgb_to_linear(c[:3])
            bsdf.inputs["Emission Color"].default_value = (lin[0], lin[1], lin[2], 1.0)
        bsdf.inputs["Emission Strength"].default_value = emit_strength
    mat.use_backface_culling = not double
    return mat


# --- mesh building ---------------------------------------------------------

AXES = {
    "-x": Vector((-1, 0, 0)), "+x": Vector((1, 0, 0)),
    "-y": Vector((0, -1, 0)), "+y": Vector((0, 1, 0)),
    "-z": Vector((0, 0, -1)), "+z": Vector((0, 0, 1)),
}


def face_frame(normal):
    """Right/up vectors for texturing a face seen from outside (never mirrored)."""
    n = normal.normalized()
    if abs(n.z) < 0.7:
        up_ref = Vector((0, 0, 1))
    else:
        up_ref = Vector((0, 1, 0)) if n.z > 0 else Vector((0, -1, 0))
    right = up_ref.cross(n)
    if right.length < 1e-6:
        right = Vector((1, 0, 0))
    right.normalize()
    up = n.cross(right).normalized()
    return right, up


def poly_normal(pts):
    n = Vector((0, 0, 0))
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        n.x += (a.y - b.y) * (a.z + b.z)
        n.y += (a.z - b.z) * (a.x + b.x)
        n.z += (a.x - b.x) * (a.y + b.y)
    return n.normalized() if n.length > 1e-12 else Vector((0, 0, 1))


def T(x=0.0, y=0.0, z=0.0):
    return Matrix.Translation((x, y, z))


def R(deg, axis):
    return Matrix.Rotation(math.radians(deg), 4, axis.upper())


def S(x, y=None, z=None):
    y = x if y is None else y
    z = x if z is None else z
    return Matrix.Diagonal((x, y, z, 1.0))


def look_matrix(p0, p1, roll=0.0):
    """Matrix whose local +Z runs from p0 to p1 (length not scaled), origin at p0."""
    p0, p1 = Vector(p0), Vector(p1)
    d = (p1 - p0).normalized()
    ref = Vector((0, 0, 1)) if abs(d.z) < 0.95 else Vector((0, 1, 0))
    x = ref.cross(d).normalized()
    y = d.cross(x).normalized()
    m = Matrix((
        (x.x, y.x, d.x, p0.x),
        (x.y, y.y, d.y, p0.y),
        (x.z, y.z, d.z, p0.z),
        (0, 0, 0, 1),
    ))
    if roll:
        m = m @ R(roll, "z")
    return m


class MeshBuilder:
    """Collects polygons with per-corner UVs and material names, then makes one object."""

    def __init__(self):
        self.verts = []
        self.faces = []   # (vertex indices, uvs, material, smooth)

    @property
    def tri_count(self):
        return sum(len(f[0]) - 2 for f in self.faces)

    def add_vert(self, p):
        self.verts.append(Vector(p))
        return len(self.verts) - 1

    def add_face(self, indices, uvs, mat, smooth=False):
        self.faces.append((tuple(indices), [tuple(uv) for uv in uvs], mat, smooth))

    def poly(self, pts, mat, m=None, uv="world", texel=0.5, rect=(0, 0, 1, 1), uv_offset=(0, 0),
             uvs=None, smooth=False, flip=False):
        """Adds one polygon (points CCW seen from the front). UVs are computed in the local
        space (before `m`): "world" tiles one texture per `texel` metres; "fit" stretches the
        face's bounds over `rect` (u0, v0, u1, v1 in 0..1, v up)."""
        pts = [Vector(p) for p in pts]
        if flip:
            pts = pts[::-1]
        if uvs is None:
            uvs = self._uvs(pts, uv, texel, rect, uv_offset)
        if m is not None:
            pts = [m @ p for p in pts]
        idx = [self.add_vert(p) for p in pts]
        self.add_face(idx, uvs, mat, smooth)

    @staticmethod
    def _uvs(pts, mode, texel, rect, uv_offset):
        right, up = face_frame(poly_normal(pts))
        us = [p.dot(right) for p in pts]
        vs = [p.dot(up) for p in pts]
        if mode == "fit":
            u0, u1, v0, v1 = min(us), max(us), min(vs), max(vs)
            du, dv = max(u1 - u0, 1e-9), max(v1 - v0, 1e-9)
            return [(rect[0] + (u - u0) / du * (rect[2] - rect[0]),
                     rect[1] + (v - v0) / dv * (rect[3] - rect[1])) for u, v in zip(us, vs)]
        return [(u / texel + uv_offset[0], v / texel + uv_offset[1]) for u, v in zip(us, vs)]

    def box(self, mn, mx, mat, m=None, uv="world", texel=0.5, rects=None, mats=None, skip=(),
            inward=False, uv_offset=(0, 0)):
        """Axis-aligned box (in local space, then transformed by `m`). `rects`/`mats` are dicts
        keyed by face ("-y" = front, "+y" = back, "+z" = top ...) for per-face UV rects
        (fit mode) or materials. `inward` flips faces (for interiors)."""
        x0, y0, z0 = mn
        x1, y1, z1 = mx
        corners = {
            "-y": [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)],
            "+y": [(x1, y1, z0), (x0, y1, z0), (x0, y1, z1), (x1, y1, z1)],
            "-x": [(x0, y1, z0), (x0, y0, z0), (x0, y0, z1), (x0, y1, z1)],
            "+x": [(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)],
            "+z": [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)],
            "-z": [(x0, y1, z0), (x1, y1, z0), (x1, y0, z0), (x0, y0, z0)],
        }
        for key, pts in corners.items():
            if key in skip:
                continue
            face_mat = (mats or {}).get(key, mat)
            if face_mat is None:
                continue
            pts = [Vector(p) for p in pts]
            if poly_normal(pts).dot(AXES[key]) < 0:
                pts = pts[::-1]
            if inward:
                pts = pts[::-1]
            if rects is not None and key in rects:
                self.poly(pts, face_mat, m=m, uv="fit", rect=rects[key])
            elif uv == "fit":
                self.poly(pts, face_mat, m=m, uv="fit", rect=(rects or {}).get(key, (0, 0, 1, 1)))
            else:
                self.poly(pts, face_mat, m=m, uv="world", texel=texel, uv_offset=uv_offset)

    def cbox(self, center, size, mat, m=None, **kw):
        """Box from a centre and full size."""
        c, s = Vector(center), Vector(size) * 0.5
        self.box(c - s, c + s, mat, m=m, **kw)

    def cylinder(self, mat, r0=0.05, r1=None, h=0.1, segs=8, m=None, caps=(True, True),
                 smooth=True, texel=0.5, cap_mat=None, wrap_u=None, v_range=None, phase=0.0,
                 rect=None, cap_rect=None):
        """Cylinder/cone along local +Z from z = 0 to z = h. `wrap_u` repeats the texture that
        many times around (default: by circumference / texel). `rect` fits the side to a texture
        rect (u0, v0, u1, v1). Caps are flat polygons (`cap_rect` fits them)."""
        r1 = r0 if r1 is None else r1
        m = m or Matrix.Identity(4)
        angles = [phase + 2 * math.pi * i / segs for i in range(segs)]
        bottom = [m @ Vector((r0 * math.cos(a), r0 * math.sin(a), 0)) for a in angles]
        top = [m @ Vector((r1 * math.cos(a), r1 * math.sin(a), h)) for a in angles]
        bi = [self.add_vert(p) for p in bottom]
        ti = [self.add_vert(p) for p in top]
        circ = 2 * math.pi * max(r0, r1)
        reps = wrap_u if wrap_u is not None else max(1.0, round(circ / texel))
        for i in range(segs):
            j = (i + 1) % segs
            u0, u1 = reps * i / segs, reps * (i + 1) / segs
            if rect is not None:
                ua = rect[0] + (rect[2] - rect[0]) * i / segs
                ub = rect[0] + (rect[2] - rect[0]) * (i + 1) / segs
                uvs = [(ua, rect[1]), (ub, rect[1]), (ub, rect[3]), (ua, rect[3])]
            else:
                va, vb = (0.0, h / texel) if v_range is None else v_range
                uvs = [(u0, va), (u1, va), (u1, vb), (u0, vb)]
            self.add_face([bi[i], bi[j], ti[j], ti[i]], uvs, mat, smooth)
        cm = cap_mat or mat
        if caps[0] and r0 > 1e-6:
            pts = [Vector((r0 * math.cos(a), r0 * math.sin(a), 0)) for a in reversed(angles)]
            self._cap(pts, cm, m, r0, texel, cap_rect)
        if caps[1] and r1 > 1e-6:
            pts = [Vector((r1 * math.cos(a), r1 * math.sin(a), h)) for a in angles]
            self._cap(pts, cm, m, r1, texel, cap_rect)

    def _cap(self, pts, mat, m, r, texel, cap_rect):
        if cap_rect is not None:
            rect = cap_rect
            uvs = [(rect[0] + (p.x / r * 0.5 + 0.5) * (rect[2] - rect[0]),
                    rect[1] + (p.y / r * 0.5 + 0.5) * (rect[3] - rect[1])) for p in pts]
        else:
            uvs = [(p.x / texel, p.y / texel) for p in pts]
        idx = [self.add_vert(m @ p) for p in pts]
        self.add_face(idx, uvs, mat, False)

    def tube(self, p0, p1, r, mat, segs=6, r1=None, **kw):
        """Cylinder between two points."""
        p0, p1 = Vector(p0), Vector(p1)
        self.cylinder(mat, r0=r, r1=r1, h=(p1 - p0).length, segs=segs, m=look_matrix(p0, p1), **kw)

    def bar(self, p0, p1, w, mat, d=None, roll=0.0, **kw):
        """Square-section bar between two points (w x d cross-section)."""
        p0, p1 = Vector(p0), Vector(p1)
        d = w if d is None else d
        length = (p1 - p0).length
        self.box((-w / 2, -d / 2, 0), (w / 2, d / 2, length), mat, m=look_matrix(p0, p1, roll), **kw)

    def ellipsoid(self, center, radii, mat, segs=8, rings=5, m=None, jitter=0.0, seed=0,
                  flat_bottom=None, smooth=False, texel=0.5):
        """Low-poly ellipsoid (UV sphere). `flat_bottom` clamps z (local) to that value."""
        rng = np.random.default_rng(seed)
        m = m or Matrix.Identity(4)
        c = Vector(center)
        grid = []
        for ri in range(rings + 1):
            phi = math.pi * ri / rings
            row = []
            for si in range(segs):
                th = 2 * math.pi * si / segs
                p = Vector((math.sin(phi) * math.cos(th) * radii[0], math.sin(phi) * math.sin(th) * radii[1],
                            -math.cos(phi) * radii[2]))
                if jitter and 0 < ri < rings:
                    p *= 1.0 + (rng.random() * 2 - 1) * jitter
                p += c
                if flat_bottom is not None:
                    p.z = max(p.z, flat_bottom)
                row.append(p)
                if ri in (0, rings):
                    break
            grid.append(row)
        idx = [[self.add_vert(m @ p) for p in row] for row in grid]
        for ri in range(rings):
            for si in range(segs):
                sj = (si + 1) % segs
                u0, u1 = si / segs * 2, (si + 1) / segs * 2
                v0, v1 = ri / rings, (ri + 1) / rings
                if ri == 0:
                    self.add_face([idx[0][0], idx[1][sj], idx[1][si]], [(u0, v0), (u1, v1), (u0, v1)], mat, smooth)
                elif ri == rings - 1:
                    self.add_face([idx[ri][si], idx[ri][sj], idx[ri + 1][0]], [(u0, v0), (u1, v0), (u0, v1)], mat,
                                  smooth)
                else:
                    self.add_face([idx[ri][si], idx[ri][sj], idx[ri + 1][sj], idx[ri + 1][si]],
                                  [(u0, v0), (u1, v0), (u1, v1), (u0, v1)], mat, smooth)

    def extrude(self, profile, depth, mat, m=None, side_mat=None, texel=0.5, rect=None, side_texel=None,
                back_rect=None, caps=(True, True)):
        """Extrudes a 2D polygon given in the local XZ plane (x right, z up, CCW seen from -Y)
        along +Y from y = -depth/2 to y = +depth/2. The front (-Y) and back faces get "fit"
        UVs over `rect` when given, else world UVs."""
        m = m or Matrix.Identity(4)
        h = depth / 2
        front = [Vector((x, -h, z)) for x, z in profile]
        back = [Vector((x, h, z)) for x, z in profile]
        if poly_normal(front).y > 0:
            front = front[::-1]
            back = back[::-1]
        if caps[0]:
            self.poly(front, mat, m=m, uv="fit" if rect else "world", rect=rect or (0, 0, 1, 1), texel=texel)
        if caps[1]:
            self.poly(back[::-1], mat, m=m, uv="fit" if (back_rect or rect) else "world",
                      rect=back_rect or rect or (0, 0, 1, 1), texel=texel)
        n = len(front)
        st = side_texel or texel
        for i in range(n):
            j = (i + 1) % n
            quad = [front[j], front[i], back[i], back[j]]
            if poly_normal(quad).dot((front[i] + front[j]) * 0.5 - sum(front, Vector()) / n) < 0:
                quad = quad[::-1]
            self.poly(quad, side_mat or mat, m=m, uv="world", texel=st)

    def merge(self, other, m=None):
        base = len(self.verts)
        for v in other.verts:
            self.verts.append(m @ v if m is not None else v.copy())
        for idx, uvs, mat, smooth in other.faces:
            self.faces.append((tuple(i + base for i in idx), list(uvs), mat, smooth))

    def to_object(self, name, collection, location=(0, 0, 0), export_name=None):
        """Creates a mesh object. `export_name` is the exact node name written to the glTF
        (Blender object names must be unique per file, so the object itself is prefixed)."""
        mesh = bpy.data.meshes.new(name)
        faces = [f[0] for f in self.faces]
        mesh.from_pydata([tuple(v) for v in self.verts], [], faces)
        mats = []
        for f in self.faces:
            if f[2] not in mats:
                mats.append(f[2])
        for mat in mats:
            mesh.materials.append(mat)
        mesh.polygons.foreach_set("material_index", [mats.index(f[2]) for f in self.faces])
        uv_layer = mesh.uv_layers.new(name="UVMap")
        flat_uvs = [c for f in self.faces for uv in f[1] for c in uv]
        uv_layer.data.foreach_set("uv", flat_uvs)
        sharp = mesh.attributes.new("sharp_face", "BOOLEAN", "FACE")
        sharp.data.foreach_set("value", [not f[3] for f in self.faces])
        mesh.validate(clean_customdata=False)
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        obj.location = location
        collection.objects.link(obj)
        if export_name:
            obj["export_name"] = export_name
        return obj


def empty(name, collection, location=(0, 0, 0), export_name=None, size=0.05):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = "ARROWS"
    obj.empty_display_size = size
    obj.location = location
    collection.objects.link(obj)
    if export_name:
        obj["export_name"] = export_name
    return obj


def parent(child, parent_obj):
    """Parents `child` keeping its authored location as the local offset. Prop roots sit at the
    origin unrotated while being built, so local == world here. (matrix_world is not used: it is
    not evaluated yet for objects created in the same script run.)"""
    child.parent = parent_obj
    child.matrix_parent_inverse = Matrix.Identity(4)


# --- scene / export --------------------------------------------------------

def new_collection(name):
    col = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(col)
    return col


def hierarchy(objs):
    out = []

    def rec(o):
        out.append(o)
        for c in o.children:
            rec(c)

    for o in objs:
        rec(o)
    return out


def triangle_count(objs):
    total = 0
    for o in hierarchy(objs):
        if o.type == "MESH":
            total += sum(len(p.vertices) - 2 for p in o.data.polygons)
    return total


def export_glb(objs, path):
    """Exports the given top-level objects (and their children) to a .glb with the exact node
    names stored in each object's "export_name" property."""
    all_objs = hierarchy(objs)
    renamed = []
    for o in all_objs:
        target = o.get("export_name")
        if target and o.name != target:
            renamed.append((o, o.name))
            o.name = target
            if o.name != target:
                raise RuntimeError("object name %s is taken; cannot export %s" % (target, path))
    try:
        bpy.ops.object.select_all(action="DESELECT")
        for o in all_objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = all_objs[0]
        bpy.ops.export_scene.gltf(
            filepath=path, export_format="GLB", use_selection=True, export_apply=True,
            export_yup=True, export_texcoords=True, export_normals=True, export_materials="EXPORT",
            export_image_format="AUTO", export_cameras=False, export_lights=False,
            export_animations=False, export_extras=False, export_vertex_color="NONE",
        )
    finally:
        for o, old in renamed:
            o.name = old
