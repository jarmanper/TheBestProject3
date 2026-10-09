"""Mesh building in GODOT coordinates (Y up, +Z = store front), converted to Blender on object creation.

Blender (x, y, z) = Godot (x, -z, y). The conversion is a proper rotation, so CCW winding is kept.
Kit pieces are authored with their front facing Godot +Z (= Blender -Y, the glTF "model front").
"""
import math
from contextlib import contextmanager

import numpy as np


# ---------------------------------------------------------------- transforms (4x4, Godot coords)
def T(x=0.0, y=0.0, z=0.0):
	m = np.eye(4)
	m[:3, 3] = (x, y, z)
	return m


def RY(deg):
	"""Rotate about +Y. RY(90) turns local +Z into +X and local +X into -Z."""
	a = math.radians(deg)
	c, s = math.cos(a), math.sin(a)
	m = np.eye(4)
	m[0, 0], m[0, 2], m[2, 0], m[2, 2] = c, s, -s, c
	return m


def RX(deg):
	a = math.radians(deg)
	c, s = math.cos(a), math.sin(a)
	m = np.eye(4)
	m[1, 1], m[1, 2], m[2, 1], m[2, 2] = c, -s, s, c
	return m


def RZ(deg):
	a = math.radians(deg)
	c, s = math.cos(a), math.sin(a)
	m = np.eye(4)
	m[0, 0], m[0, 1], m[1, 0], m[1, 1] = c, -s, s, c
	return m


def chain(*ms):
	out = np.eye(4)
	for m in ms:
		out = out @ m
	return out


# face corner order: BL, BR, TR, TL as seen from outside (CCW)
def _face_corners(face, x0, y0, z0, x1, y1, z1):
	if face == "px":
		return [(x1, y0, z1), (x1, y0, z0), (x1, y1, z0), (x1, y1, z1)]
	if face == "nx":
		return [(x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0)]
	if face == "pz":
		return [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
	if face == "nz":
		return [(x1, y0, z0), (x0, y0, z0), (x0, y1, z0), (x1, y1, z0)]
	if face == "py":
		return [(x0, y1, z1), (x1, y1, z1), (x1, y1, z0), (x0, y1, z0)]
	if face == "ny":
		return [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)]
	raise ValueError(face)


FACES = ("px", "nx", "py", "ny", "pz", "nz")


def rect_uvs(r):
	u0, v0, u1, v1 = r
	return [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]


class MB:
	"""Mesh builder. Faces never share vertices (flat shaded low-poly)."""

	def __init__(self):
		self.verts = []
		self.faces = []
		self.uvs = []
		self.fmat = []
		self.mats = []
		self.M = np.eye(4)

	@contextmanager
	def at(self, *ms):
		old = self.M
		self.M = old @ chain(*ms)
		try:
			yield self
		finally:
			self.M = old

	def _mat(self, m):
		if m not in self.mats:
			self.mats.append(m)
		return self.mats.index(m)

	def _tp(self, pts):
		p = np.asarray(pts, np.float64)
		p = p @ self.M[:3, :3].T + self.M[:3, 3]
		return [tuple(v) for v in p]

	def poly(self, pts, uvs, mat):
		base = len(self.verts)
		self.verts.extend(self._tp(pts))
		self.faces.append(tuple(range(base, base + len(pts))))
		self.uvs.append(list(uvs))
		self.fmat.append(self._mat(mat))

	def quad(self, bl, br, tr, tl, r, mat):
		self.poly([bl, br, tr, tl], rect_uvs(r) if len(r) == 4 and not isinstance(r[0], tuple) else r, mat)

	def box(self, mn, mx, mat, uv, skip=()):
		"""uv: a rect (u0, v0, u1, v1) for every face, a dict face->rect (missing/None = skip face),
		or a callable(face, corners) -> 4 uv pairs. skip: faces to leave out."""
		x0, y0, z0 = mn
		x1, y1, z1 = mx
		if x1 - x0 <= 1e-6 or y1 - y0 <= 1e-6 or z1 - z0 <= 1e-6:
			return
		for f in FACES:
			if f in skip:
				continue
			if isinstance(uv, dict):
				r = uv.get(f, uv.get("*"))
				if r is None:
					continue
			else:
				r = uv
			corners = _face_corners(f, x0, y0, z0, x1, y1, z1)
			if callable(r):
				self.poly(corners, r(f, corners), mat)
			else:
				self.poly(corners, rect_uvs(r), mat)

	def loft(self, rings, n, mat, r_uv, cap_uv=None, cx=0.0, cz=0.0, start=0.0, rx_scale=1.0):
		"""Ring-to-ring prism around the Y axis. rings: [(y, radius, v_fraction)], bottom to top.
		Side UVs wrap the rect r_uv once (u) and use v_fraction inside it (v). cap_uv: top cap rect."""
		u0, v0, u1, v1 = r_uv
		ang = [start + 2 * math.pi * i / n for i in range(n + 1)]

		def P(a, y, r):
			return (cx + r * math.cos(a) * rx_scale, y, cz + r * math.sin(a))

		for (ya, ra, fa), (yb, rb, fb) in zip(rings[:-1], rings[1:]):
			va, vb = v0 + (v1 - v0) * fa, v0 + (v1 - v0) * fb
			for i in range(n):
				a0, a1 = ang[i], ang[i + 1]
				ua, ub = u1 - (u1 - u0) * i / n, u1 - (u1 - u0) * (i + 1) / n
				self.poly([P(a1, ya, ra), P(a0, ya, ra), P(a0, yb, rb), P(a1, yb, rb)],
					[(ub, va), (ua, va), (ua, vb), (ub, vb)], mat)
		if cap_uv is not None:
			y, r, _ = rings[-1]
			cu0, cv0, cu1, cv1 = cap_uv
			pts, uvs = [], []
			for i in range(n, 0, -1):
				a = ang[i]
				pts.append(P(a, y, r))
				uvs.append((cu0 + (cu1 - cu0) * (0.5 + 0.5 * math.cos(a)), cv0 + (cv1 - cv0) * (0.5 - 0.5 * math.sin(a))))
			self.poly(pts, uvs, mat)

	def tube(self, path, radius, mat, r_uv):
		"""Square-section tube along a polyline (cables, rods)."""
		pts = [np.asarray(p, np.float64) for p in path]
		frames = []
		for i, p in enumerate(pts):
			if i == 0:
				t = pts[1] - pts[0]
			elif i == len(pts) - 1:
				t = pts[-1] - pts[-2]
			else:
				t = pts[i + 1] - pts[i - 1]
			t = t / (np.linalg.norm(t) + 1e-9)
			ref = np.array([0.0, 1.0, 0.0]) if abs(t[1]) < 0.9 else np.array([1.0, 0.0, 0.0])
			s1 = np.cross(t, ref)
			s1 /= np.linalg.norm(s1)
			s2 = np.cross(s1, t)
			frames.append([p + radius * (math.cos(k * math.pi / 2) * s1 + math.sin(k * math.pi / 2) * s2) for k in range(4)])
		u0, v0, u1, v1 = r_uv
		for a, b in zip(frames[:-1], frames[1:]):
			for k in range(4):
				k2 = (k + 1) % 4
				self.poly([tuple(a[k2]), tuple(a[k]), tuple(b[k]), tuple(b[k2])],
					[(u0, v0), (u1, v0), (u1, v1), (u0, v1)], mat)

	def extend(self, other):
		base = len(self.verts)
		self.verts.extend(other.verts)
		for f, uv, m in zip(other.faces, other.uvs, other.fmat):
			self.faces.append(tuple(i + base for i in f))
			self.uvs.append(uv)
			self.fmat.append(self._mat(other.mats[m]))

	def tris(self):
		return sum(len(f) - 2 for f in self.faces)

	def empty(self):
		return not self.faces

	def bounds(self):
		v = np.asarray(self.verts)
		return v.min(axis=0), v.max(axis=0)


class Chunks:
	"""MBs keyed by a 4x4 m grid cell, for spread-out detail (debris, cables)."""

	def __init__(self, size=4.0):
		self.size = size
		self.cells = {}

	def get(self, x, z):
		key = (int(math.floor(x / self.size)), int(math.floor(z / self.size)))
		if key not in self.cells:
			self.cells[key] = MB()
		return self.cells[key]


# ---------------------------------------------------------------- Blender side
def to_blender(v):
	x, y, z = v
	return (x, -z, y)


def make_object(bpy, name, mb, materials, collection, parent=None, origin=(0.0, 0.0, 0.0), props=None):
	"""Create a mesh object from an MB. origin (Godot coords) becomes the object's location."""
	V = np.asarray(mb.verts, np.float64) - np.asarray(origin, np.float64)
	VB = np.stack([V[:, 0], -V[:, 2], V[:, 1]], axis=1)
	me = bpy.data.meshes.new(name)
	me.from_pydata(VB.tolist(), [], mb.faces)
	uvl = me.uv_layers.new(name="UVMap")
	flat = np.array([c for f in mb.uvs for p in f for c in p], np.float32)
	uvl.data.foreach_set("uv", flat)
	slot = {}
	for m in mb.mats:
		if m in materials:
			slot[m] = len(me.materials)
			me.materials.append(materials[m])
	if slot:
		me.polygons.foreach_set("material_index", [slot.get(mb.mats[i], 0) for i in mb.fmat])
	me.update()
	ob = bpy.data.objects.new(name, me)
	ob.location = to_blender(origin)
	collection.objects.link(ob)
	if parent is not None:
		ob.parent = parent
	for k, v in (props or {}).items():
		ob[k] = v
	return ob


def make_empty(bpy, name, collection, pos=(0.0, 0.0, 0.0), parent=None, props=None, size=0.2):
	ob = bpy.data.objects.new(name, None)
	ob.empty_display_size = size
	ob.location = to_blender(pos)
	collection.objects.link(ob)
	if parent is not None:
		ob.parent = parent
	for k, v in (props or {}).items():
		ob[k] = v
	return ob
