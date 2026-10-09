"""Builds the Graveyard Shift store environment and exports it for Godot.

	blender -b --factory-startup -P art_source/blender/environment/build_store.py [-- --no-kit | --kit-only]

Outputs (paths relative to the repo root):
	art_source/blender/environment/store.blend          the generated store (packed textures)
	assets/models/environment/store_interior.glb        complete static store, ARCHITECTURE section 7 layout
	assets/models/environment/kit/*.glb                 reusable pieces (front = Godot +Z)
	assets/models/environment/textures/*.png            the pixel-art atlases (shared by the Godot materials)

Everything is authored in Godot coordinates (see geo.py); Blender (x, y, z) = Godot (x, -z, y).
Re-running is deterministic (fixed seeds).
"""
import math
import os
import sys

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import px  # noqa: E402
import geo  # noqa: E402
import kit as kitmod  # noqa: E402
from geo import MB, T, RY, RX, RZ, Chunks, make_object, make_empty  # noqa: E402
from kit import ENV, PROD, TUBE  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "models", "environment")
KIT_DIR = os.path.join(OUT_DIR, "kit")
TEX_DIR = os.path.join(OUT_DIR, "textures")
BLEND_PATH = os.path.join(HERE, "store.blend")

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []

# ------------------------------------------------------------------ layout (ARCHITECTURE section 7)
X0, X1, Z0, Z1 = -20.0, 20.0, -16.0, 16.0
SALES_Z0 = -6.0
CEIL_SALES, CEIL_BOH = 4.0, 3.0
EXT_T, INT_HALF = 0.3, 0.1
ROWS_X = (-16.0, -12.0, -8.0, -4.0, 0.0)
ROW_Z0, ROW_Z1 = -3.0, 7.0
ENDCAP_D = 0.4
SECTIONS = 8
SECTION_L = (ROW_Z1 - ROW_Z0 - 2 * ENDCAP_D) / SECTIONS  # 1.15 m
AISLES = {1: -14.0, 2: -10.0, 3: -6.0, 4: -2.0}
COUNTERS_X = (-12.0, -7.0, -2.0)
EMP_DOOR = (6.0, 8.4)
HALL_DOORS = {"storage": (-6.0, -4.4), "break_room": (5.0, 6.2), "office": (12.0, 13.2), "janitor": (17.5, 18.7)}
ROOMS = {"hallway": (-20.0, 20.0, -9.0, -6.0), "storage": (-20.0, 2.0, -16.0, -9.0), "break_room": (2.0, 10.0, -16.0, -9.0),
	"office": (10.0, 16.0, -16.0, -9.0), "janitor": (16.0, 20.0, -16.0, -9.0)}
EMERGENCY_DOOR_Z = (-13.5, -12.5)
BREAKER_POS = (0.0, 1.5, -8.85)

# Shelf faces: (row x, side) -> categories for sections k = 0 (back, z = -3) .. 7 (front, z = 7) and the placard
# shown on the front-most section of each group.
def _groups(*groups):
	cats, pls = [], []
	for cat, n, pl in groups:
		for i in range(n):
			cats.append(cat)
			pls.append(pl if i == n - 1 else None)
	return list(zip(cats, pls))


FACE_PLAN = {
	(-16.0, -1): _groups(("baking", 4, "BAKING"), ("pasta", 4, "PASTA")),
	(-16.0, 1): _groups(("cereal", 4, "CEREAL"), ("cereal", 4, "CEREAL")),
	(-12.0, -1): _groups(("cereal", 4, "CEREAL"), ("cereal", 4, "CEREAL")),
	(-12.0, 1): _groups(("chips", 4, "CHIPS"), ("snacks", 4, "SNACKS")),
	(-8.0, -1): _groups(("candy", 4, "CANDY"), ("cookies", 4, "COOKIES")),
	(-8.0, 1): _groups(("drinks", 4, "DRINKS"), ("soda", 4, "SODA")),
	(-4.0, -1): _groups(("drinks", 4, "DRINKS"), ("juice", 4, "JUICE")),
	# aisle 4, left side seen from the front: CEREAL, SNACKS, DRINKS, CEREAL (references 1/2)
	(-4.0, 1): _groups(("cereal", 3, "CEREAL"), ("drinks", 2, "DRINKS"), ("snacks", 2, "SNACKS"), ("cereal", 1, "CEREAL")),
	(0.0, -1): _groups(("soup", 3, "SOUP"), ("canned", 5, "CANNED")),
	(0.0, 1): _groups(("pasta", 4, "PASTA"), ("baking", 4, "BAKING")),
}
ENDCAP_CATS = {(-16.0, 1): "cereal", (-16.0, -1): "baking", (-12.0, 1): "chips", (-12.0, -1): "cereal", (-8.0, 1): "soda",
	(-8.0, -1): "cookies", (-4.0, 1): "drinks", (-4.0, -1): "snacks", (0.0, 1): "canned", (0.0, -1): "pasta"}


class Store:
	def __init__(self, kit, materials, rng):
		self.kit = kit
		self.mats = materials
		self.rng = rng
		self.col = bpy.context.scene.collection
		self.groups = {}
		self.collision = {}
		self.tris = 0
		self.objects = 0
		self.fixtures = []
		self.group_tris = {}

	# ------------------------------------------------------------ bookkeeping
	def group(self, name):
		if name not in self.groups:
			self.groups[name] = make_empty(bpy, name, self.col, size=0.5)
		return self.groups[name]

	def emit(self, name, mb, group, origin=(0.0, 0.0, 0.0), props=None):
		if mb.empty():
			return None
		self.tris += mb.tris()
		self.objects += 1
		self.group_tris[group] = self.group_tris.get(group, 0) + mb.tris()
		return make_object(bpy, name, mb, self.mats, self.col, parent=self.group(group), origin=origin, props=props)

	def collide(self, category, boxes, M=None):
		mb = self.collision.setdefault(category, MB())
		for mn, mx in boxes:
			if M is not None:
				corners = np.array([[x, y, z, 1.0] for x in (mn[0], mx[0]) for y in (mn[1], mx[1]) for z in (mn[2], mx[2])])
				w = (corners @ M.T)[:, :3]
				mn, mx = tuple(w.min(axis=0)), tuple(w.max(axis=0))
			mb.box(mn, mx, "Collision", (0, 0, 0, 0))

	def finish_collision(self):
		for cat, mb in sorted(self.collision.items()):
			make_object(bpy, "Collision_%s-colonly" % cat, mb, {}, self.col, parent=self.group("Collision"))

	# ------------------------------------------------------------ floors & ceilings
	@staticmethod
	def _splits(a0, a1, size=4.0):
		n = max(1, int(math.ceil((a1 - a0) / size - 1e-6)))
		return [a0 + (a1 - a0) * i / n for i in range(n + 1)]

	def _tiles(self, mb, x0, x1, z0, z1, step, y, down, pick, origin=(0.0, 0.0), mat=None):
		ox, oz = origin
		i0, i1 = int(math.floor((x0 - ox) / step + 1e-6)), int(math.ceil((x1 - ox) / step - 1e-6))
		j0, j1 = int(math.floor((z0 - oz) / step + 1e-6)), int(math.ceil((z1 - oz) / step - 1e-6))
		for i in range(i0, i1):
			for j in range(j0, j1):
				tx0, tz0 = ox + i * step, oz + j * step
				a0, a1 = max(tx0, x0), min(tx0 + step, x1)
				b0, b1 = max(tz0, z0), min(tz0 + step, z1)
				if a1 - a0 < 1e-4 or b1 - b0 < 1e-4:
					continue
				res = pick(i, j)
				if res is None:
					continue
				(u0, v0, u1, v1), rot = res
				fu0, fu1 = (a0 - tx0) / step, (a1 - tx0) / step
				fv0, fv1 = (b0 - tz0) / step, (b1 - tz0) / step  # fv along +z

				def uvat(fu, fz):
					# texture top row = -z side of the tile; rotate in 90 degree steps
					s, t = fu, 1.0 - fz
					for _ in range(rot):
						s, t = 1.0 - t, s
					return (u0 + (u1 - u0) * s, v0 + (v1 - v0) * t)

				if not down:
					pts = [(a0, y, b1), (a1, y, b1), (a1, y, b0), (a0, y, b0)]
					uvs = [uvat(fu0, fv1), uvat(fu1, fv1), uvat(fu1, fv0), uvat(fu0, fv0)]
				else:
					pts = [(a0, y, b0), (a1, y, b0), (a1, y, b1), (a0, y, b1)]
					uvs = [uvat(fu0, fv0), uvat(fu1, fv0), uvat(fu1, fv1), uvat(fu0, fv1)]
				mb.poly(pts, uvs, mat)

	def floors(self):
		rng = np.random.default_rng(101)
		W, H = 128.0, 64.0
		kinds = [0, 1, 2, 3, 4, 5, 6, 7]
		weights = np.array([36, 36, 7, 4, 3, 5, 6, 3], float)
		weights /= weights.sum()

		def tile_uv(cell_x, cell_y, cw, ch):
			e = 0.02
			return ((cell_x * cw + e) / W, 1 - ((cell_y + 1) * ch - e) / H, ((cell_x + 1) * cw - e) / W, 1 - (cell_y * ch + e) / H)

		def pick_sales(i, j):
			kind = int(rng.choice(kinds, p=weights))
			row = int(rng.integers(0, 4))
			return tile_uv(kind, row, 16, 16), 0

		def pick_conc(i, j):
			return tile_uv(int(rng.integers(0, 4)), int(rng.integers(0, 2)), 32, 32), int(rng.integers(0, 4))

		xs = self._splits(X0, X1)
		zs = [SALES_Z0, -2.0, 2.0, 6.0, 10.0, 14.0, Z1]
		for a, (x0, x1) in enumerate(zip(xs[:-1], xs[1:])):
			for b, (z0, z1) in enumerate(zip(zs[:-1], zs[1:])):
				mb = MB()
				self._tiles(mb, x0, x1, z0, z1, 0.5, 0.0, False, pick_sales, origin=(X0, SALES_Z0), mat="FloorTile")
				cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
				self.emit("Floor_Sales_%02d_%02d" % (a, b), mb, "Floors", origin=(cx, 0, cz))
		for room, (rx0, rx1, rz0, rz1) in ROOMS.items():
			for a, (x0, x1) in enumerate(zip(self._splits(rx0, rx1)[:-1], self._splits(rx0, rx1)[1:])):
				for b, (z0, z1) in enumerate(zip(self._splits(rz0, rz1)[:-1], self._splits(rz0, rz1)[1:])):
					mb = MB()
					self._tiles(mb, x0, x1, z0, z1, 1.0, 0.0, False, pick_conc, mat="FloorConcrete")
					self.emit("Floor_%s_%02d_%02d" % (room, a, b), mb, "Floors", origin=((x0 + x1) / 2, 0, (z0 + z1) / 2))
		self.collide("Floor", [((X0 - EXT_T, -0.3, Z0 - EXT_T), (X1 + EXT_T, 0.0, Z1 + EXT_T))])

	def ceilings(self):
		rng = np.random.default_rng(202)
		W, H = 128.0, 64.0
		drops = []
		holes = []

		def tile_uv(k):
			cx, cy = k % 4, k // 4
			e = 0.02
			return ((cx * 32 + e) / W, 1 - ((cy + 1) * 32 - e) / H, ((cx + 1) * 32 - e) / W, 1 - (cy * 32 + e) / H)

		def make_pick(y, boh):
			def pick(i, j):
				r = rng.random()
				if (i % 7 == 3 and j % 6 == 2):
					return tile_uv(6), 0
				if r < (0.025 if boh else 0.018):
					holes.append((i, j, y))
					return None
				if r < (0.032 if boh else 0.024):
					drops.append((i, j, y))
					return None
				if r < 0.08:
					return tile_uv(3), int(rng.integers(0, 4))
				if r < 0.11:
					return tile_uv(4), int(rng.integers(0, 4))
				if r < (0.16 if boh else 0.13):
					return tile_uv(5), int(rng.integers(0, 4))
				if r < 0.17:
					return tile_uv(7), 0
				return tile_uv(int(rng.integers(0, 3))), int(rng.integers(0, 4))
			return pick

		step = 0.6
		areas = [("Sales", X0, X1, SALES_Z0, Z1, CEIL_SALES, False, [SALES_Z0, -2.0, 2.0, 6.0, 10.0, 14.0, Z1])]
		for room, (rx0, rx1, rz0, rz1) in ROOMS.items():
			areas.append((room, rx0, rx1, rz0, rz1, CEIL_BOH, True, None))
		for name, ax0, ax1, az0, az1, y, boh, zsplit in areas:
			xs = self._splits(ax0, ax1)
			zs = zsplit or self._splits(az0, az1)
			for a, (x0, x1) in enumerate(zip(xs[:-1], xs[1:])):
				for b, (z0, z1) in enumerate(zip(zs[:-1], zs[1:])):
					holes.clear()
					drops.clear()
					mb = MB()
					self._tiles(mb, x0, x1, z0, z1, step, y, True, make_pick(y, boh), origin=(X0, Z0), mat="CeilingTile")
					plenum = self.kit.ep("plenum")
					for (i, j, yy) in holes + drops:
						tx0, tz0 = X0 + i * step, Z0 + j * step
						a0, a1, b0, b1 = max(tx0, x0), min(tx0 + step, x1), max(tz0, z0), min(tz0 + step, z1)
						mb.box((a0, yy, b0), (a1, yy + 0.5, b1), ENV, {"ny": plenum, "px": plenum, "nx": plenum, "pz": plenum, "nz": plenum}, skip=("py",))
						mb.box((a0 + 0.1, yy + 0.25, b0), (a0 + 0.16, yy + 0.32, b1), ENV, self.kit.solid_env("pipe"))
					for (i, j, yy) in drops:
						tx0, tz0 = X0 + i * step, Z0 + j * step
						a0, a1, b0, b1 = max(tx0, x0), min(tx0 + step, x1), max(tz0, z0), min(tz0 + step, z1)
						ang = float(rng.uniform(25, 55))
						r = tile_uv(int(rng.integers(3, 6)))
						with mb.at(T(a0, yy, b0), RZ(-ang)):
							pts = [(0, 0, 0), (a1 - a0, 0, 0), (a1 - a0, 0, b1 - b0), (0, 0, b1 - b0)]
							uvs = [(r[0], r[1]), (r[2], r[1]), (r[2], r[3]), (r[0], r[3])]
							mb.poly(pts, uvs, "CeilingTile")
							mb.poly(pts[::-1], uvs[::-1], "CeilingTile")
					self.emit("Ceiling_%s_%02d_%02d" % (name, a, b), mb, "Ceilings", origin=((x0 + x1) / 2, y, (z0 + z1) / 2))

	# ------------------------------------------------------------ walls
	def _wall_uv(self, face, corners):
		out = []
		for (x, y, z) in corners:
			if face in ("px", "nx"):
				out.append((z / 2.0, y / 4.0))
			elif face in ("pz", "nz"):
				out.append((x / 2.0, y / 4.0))
			else:
				out.append((x / 2.0, z / 2.0))
		return out

	@staticmethod
	def _in_sales(x, z):
		return X0 < x < X1 and SALES_Z0 < z < Z1

	def _wall_box(self, mb, mn, mx):
		cx, cy, cz = [(a + b) / 2 for a, b in zip(mn, mx)]
		normals = {"px": (1, 0), "nx": (-1, 0), "pz": (0, 1), "nz": (0, -1), "py": (0, 0), "ny": (0, 0)}
		for f in ("px", "nx", "pz", "nz", "py"):
			nx_, nz_ = normals[f]
			fx = (mx[0] if nx_ > 0 else mn[0] if nx_ < 0 else cx) + nx_ * 0.25
			fz = (mx[2] if nz_ > 0 else mn[2] if nz_ < 0 else cz) + nz_ * 0.25
			mat = "WallSales" if self._in_sales(fx, fz) else "WallBack"
			mb.box(mn, mx, mat, {f: self._wall_uv})

	def wall(self, axis, c, a0, a1, t0, t1, height, openings=(), solid_openings=()):
		"""axis 'x': wall along x at z in [t0, t1]; axis 'z': wall along z at x in [t0, t1].
		openings: (b0, b1, y0, y1) holes; solid_openings: holes that still collide (windows) or are closed doors."""
		pieces = []
		cuts = sorted(openings, key=lambda o: o[0])
		cur = a0
		for (b0, b1, y0, y1) in cuts:
			if b0 > cur:
				pieces.append((cur, b0, 0.0, height))
			if y0 > 0:
				pieces.append((b0, b1, 0.0, y0))
			if y1 < height:
				pieces.append((b0, b1, y1, height))
			cur = b1
		if cur < a1:
			pieces.append((cur, a1, 0.0, height))
		col = []
		for (b0, b1, y0, y1) in pieces:
			n = max(1, int(math.ceil((b1 - b0) / 4.0 - 1e-6)))
			for k in range(n):
				s0, s1 = b0 + (b1 - b0) * k / n, b0 + (b1 - b0) * (k + 1) / n
				if axis == "x":
					mn, mx = (s0, y0, t0), (s1, y1, t1)
				else:
					mn, mx = (t0, y0, s0), (t1, y1, s1)
				mb = MB()
				self._wall_box(mb, mn, mx)
				ctr = tuple((p + q) / 2 for p, q in zip(mn, mx))
				self.emit("Wall_%03d" % (self.objects + 1), mb, "Walls", origin=(ctr[0], 0, ctr[2]))
				col.append((mn, mx))
		for (b0, b1, y0, y1) in solid_openings:
			col.append(((b0, y0, t0), (b1, y1, t1)) if axis == "x" else ((t0, y0, b0), (t1, y1, b1)))
		self.collide("Walls", col)

	def door_frame(self, mb, axis, c, b0, b1, h, half):
		fr = self.kit.solid_env("frame")
		for sgn in (-1, 1):
			f0, f1 = sorted((c + sgn * half, c + sgn * (half + 0.025)))
			if axis == "x":
				mb.box((b0 - 0.06, 0, f0), (b0, h + 0.06, f1), ENV, fr)
				mb.box((b1, 0, f0), (b1 + 0.06, h + 0.06, f1), ENV, fr)
				mb.box((b0, h, f0), (b1, h + 0.06, f1), ENV, fr)
			else:
				mb.box((f0, 0, b0 - 0.06), (f1, h + 0.06, b0), ENV, fr)
				mb.box((f0, 0, b1), (f1, h + 0.06, b1 + 0.06), ENV, fr)
				mb.box((f0, h, b0), (f1, h + 0.06, b1), ENV, fr)
		# jamb linings inside the opening
		if axis == "x":
			mb.box((b0, 0, c - half), (b0 + 0.02, h, c + half), ENV, fr)
			mb.box((b1 - 0.02, 0, c - half), (b1, h, c + half), ENV, fr)
		else:
			mb.box((c - half, 0, b0), (c + half, h, b0 + 0.02), ENV, fr)
			mb.box((c - half, 0, b1 - 0.02), (c + half, h, b1), ENV, fr)

	def walls(self):
		E = EXT_T
		front_windows = [(-19.5, -3.0, 0.55, 2.7), (3.0, 8.0, 0.55, 2.7)]
		entrance = (-2.0, 2.0, 0.0, 2.6)
		# exterior walls sit outside the footprint so every zone keeps its full size
		self.wall("x", Z1, X0 - E, X1 + E, Z1, Z1 + E, CEIL_SALES, openings=front_windows + [entrance], solid_openings=front_windows)
		self.wall("x", Z0, X0 - E, X1 + E, Z0 - E, Z0, CEIL_BOH + 0.2)
		self.wall("z", X0, Z0, SALES_Z0, X0 - E, X0, CEIL_BOH + 0.2, openings=[(EMERGENCY_DOOR_Z[0], EMERGENCY_DOOR_Z[1], 0.0, 2.1)])
		self.wall("z", X0, SALES_Z0, Z1, X0 - E, X0, CEIL_SALES)
		self.wall("z", X1, Z0, SALES_Z0, X1, X1 + E, CEIL_BOH + 0.2)
		self.wall("z", X1, SALES_Z0, Z1, X1, X1 + E, CEIL_SALES)
		# interior walls (0.2 thick, centred on the layout lines)
		h = INT_HALF
		self.wall("x", SALES_Z0, X0, X1, SALES_Z0 - h, SALES_Z0 + h, CEIL_SALES, openings=[(EMP_DOOR[0], EMP_DOOR[1], 0.0, 2.4)])
		self.wall("x", -9.0, X0, X1, -9.0 - h, -9.0 + h, CEIL_BOH + 0.05, openings=[(a, b, 0.0, 2.2) for a, b in HALL_DOORS.values()])
		for x in (2.0, 10.0, 16.0):
			self.wall("z", x, Z0, -9.0 - h, x - h, x + h, CEIL_BOH + 0.05)
		mb = MB()
		self.door_frame(mb, "x", SALES_Z0, EMP_DOOR[0], EMP_DOOR[1], 2.4, h)
		self.emit("DoorFrame_EmployeesOnly", mb, "Doors", origin=(sum(EMP_DOOR) / 2, 0, SALES_Z0))
		for room, (a, b) in HALL_DOORS.items():
			mb = MB()
			self.door_frame(mb, "x", -9.0, a, b, 2.2, h)
			self.emit("DoorFrame_%s" % room, mb, "Doors", origin=((a + b) / 2, 0, -9.0))

	# ------------------------------------------------------------ entrance, windows, exterior black
	def storefront(self):
		alu = self.kit.solid_env("alu")
		black = self.kit.ep("black")
		glass_uv = self.kit.ep("black")
		zg = Z1 + 0.15
		# windows
		mb = MB()
		for (a, b, y0, y1) in [(-19.5, -3.0, 0.55, 2.7), (3.0, 8.0, 0.55, 2.7)]:
			n = max(1, int(round((b - a) / 2.0)))
			for k in range(n + 1):
				x = a + (b - a) * k / n
				mb.box((x - 0.04, y0, Z1 - 0.02), (x + 0.04, y1, Z1 + 0.2), ENV, alu)
			mb.box((a, y0 - 0.06, Z1 - 0.06), (b, y0, Z1 + 0.2), ENV, alu)
			mb.box((a, y1, Z1 - 0.02), (b, y1 + 0.06, Z1 + 0.2), ENV, alu)
			for k in range(n):
				xa, xb = a + (b - a) * k / n + 0.04, a + (b - a) * (k + 1) / n - 0.04
				mb.quad((xb, y0, zg), (xa, y0, zg), (xa, y1, zg), (xb, y1, zg), glass_uv, "Glass")
		self.emit("Windows", mb, "Doors", origin=(0, 0, Z1))
		# locked sliding entrance doors
		mb = MB()
		for x in (-2.0, 0.0, 2.0):
			mb.box((x - 0.05, 0, Z1 - 0.02), (x + 0.05, 2.6, Z1 + 0.25), ENV, alu)
		mb.box((-2.0, 2.45, Z1 - 0.02), (2.0, 2.6, Z1 + 0.25), ENV, alu)
		for xa, xb, zz in ((-1.95, 0.0, Z1 + 0.06), (0.0, 1.95, Z1 + 0.14)):
			mb.box((xa, 0, zz - 0.03), (xb, 0.12, zz + 0.03), ENV, alu)
			mb.box((xa, 2.3, zz - 0.03), (xb, 2.45, zz + 0.03), ENV, alu)
			mb.box((xa, 0.12, zz - 0.03), (xa + 0.06, 2.3, zz + 0.03), ENV, alu)
			mb.box((xb - 0.06, 0.12, zz - 0.03), (xb, 2.3, zz + 0.03), ENV, alu)
			mb.quad((xb - 0.06, 0.12, zz), (xa + 0.06, 0.12, zz), (xa + 0.06, 2.3, zz), (xb - 0.06, 2.3, zz), glass_uv, "Glass")
		cl = self.kit.e("sign_closed")
		mb.quad((-0.7, 1.35, Z1 + 0.025), (-1.3, 1.35, Z1 + 0.025), (-1.3, 1.52, Z1 + 0.025), (-0.7, 1.52, Z1 + 0.025), cl, ENV)
		push = self.kit.e("sticker_push")
		mb.quad((0.5, 1.2, Z1 + 0.105), (0.3, 1.2, Z1 + 0.105), (0.3, 1.3, Z1 + 0.105), (0.5, 1.3, Z1 + 0.105), push, ENV)
		self.emit("EntranceDoors", mb, "Doors", origin=(0, 0, Z1))
		self.collide("Doors", [((-2.0, 0, Z1), (2.0, 2.6, Z1 + EXT_T))])
		# black night outside the glass
		mb = MB()
		mb.quad((X1 + 1, -0.5, Z1 + 1.5), (X0 - 1, -0.5, Z1 + 1.5), (X0 - 1, 5.0, Z1 + 1.5), (X1 + 1, 5.0, Z1 + 1.5), black, ENV)
		mb.quad((X0 - 1, -0.02, Z1 + 1.5), (X1 + 1, -0.02, Z1 + 1.5), (X1 + 1, -0.02, Z1 + EXT_T), (X0 - 1, -0.02, Z1 + EXT_T), black, ENV)
		self.emit("OutsideNight", mb, "Doors", origin=(0, 0, Z1 + 1.0))

	# ------------------------------------------------------------ sales floor fixtures
	def gondolas(self):
		k = self.kit
		for r, x in enumerate(ROWS_X):
			for s in range(SECTIONS):
				z0 = ROW_Z0 + ENDCAP_D + s * SECTION_L
				zc = z0 + SECTION_L / 2
				cw, pw = FACE_PLAN[(x, -1)][s]
				ce, pe = FACE_PLAN[(x, 1)][s]
				gaps = 0.12 if self.rng.random() < 0.2 else 0.04
				mb = MB()
				rng = np.random.default_rng(1000 + r * 100 + s)
				k.gondola_section(mb, rng, SECTION_L, cw, ce, placard_w=pw, placard_e=pe,
					upright_start=True, upright_end=(s == SECTIONS - 1), overstock=0.45, gaps=gaps)
				ob = self.emit("Gondola_R%d_S%d" % (r + 1, s + 1), mb, "Shelving")
				ob.location = geo.to_blender((x, 0, zc))
			for end, z, rot in (("Front", ROW_Z1, 0), ("Back", ROW_Z0, 180)):
				mb = MB()
				rng = np.random.default_rng(2000 + r * 10 + rot)
				cat = ENDCAP_CATS[(x, 1 if rot == 0 else -1)]
				with mb.at(RY(rot)):
					k.gondola_endcap(mb, rng, cat)
				self.emit("Gondola_R%d_End%s" % (r + 1, end), mb, "Shelving", origin=(x, 0, z))
			self.collide("Shelves", [((x - 0.6, 0, ROW_Z0), (x + 0.6, kitmod.GONDOLA_H, ROW_Z1))])

	def coolers(self):
		k = self.kit
		# dairy: glass-door coolers along the back wall z = -6 (wall face -5.9, 0.8 deep), x -20..2
		n_doors, chunk = 30, 5
		dw = 22.0 / n_doors
		front_z = SALES_Z0 + INT_HALF + 0.8
		for c in range(n_doors // chunk):
			xa = X0 + c * chunk * dw
			xc = xa + chunk * dw / 2
			mb = MB()
			rng = np.random.default_rng(3000 + c)
			k.wall_cooler(mb, rng, chunk, dw, "dairy", side_l=(c == 0), side_r=(c == n_doors // chunk - 1))
			self.emit("DairyCooler_%d" % (c + 1), mb, "Coolers", origin=(0, 0, 0))
			obj = bpy.data.objects["DairyCooler_%d" % (c + 1)]
			obj.location = geo.to_blender((xc, 0, front_z))
		self.collide("Coolers", [((X0, 0, SALES_Z0 + INT_HALF), (2.0, 2.2, front_z))])
		# frozen: wall freezers along x = -20, z -3..7, facing +x
		n_doors, chunk = 12, 4
		dw = 10.0 / n_doors
		for c in range(n_doors // chunk):
			zc = ROW_Z1 - (c * chunk + chunk / 2) * dw
			mb = MB()
			rng = np.random.default_rng(3100 + c)
			k.wall_cooler(mb, rng, chunk, dw, "frozen", side_l=(c == 0), side_r=(c == n_doors // chunk - 1))
			ob = self.emit("Freezer_%d" % (c + 1), mb, "Coolers")
			ob.location = geo.to_blender((X0 + 0.8, 0, zc))
			ob.rotation_euler = (0, 0, math.radians(90))
		self.collide("Coolers", [((X0, 0, ROW_Z0), (X0 + 0.8, 2.2, ROW_Z1))])

	def checkouts(self):
		k = self.kit
		for n, cx in enumerate(COUNTERS_X):
			mb = MB()
			rng = np.random.default_rng(4000 + n)
			boxes = k.checkout_counter(mb, rng, lane=n + 1)
			self.emit("Checkout_%d" % (n + 1), mb, "Counters", origin=(0, 0, 0))
			ob = bpy.data.objects["Checkout_%d" % (n + 1)]
			ob.location = geo.to_blender((cx, 0, 11.5))
			self.collide("Counters", boxes, T(cx, 0, 11.5))
		mb = MB()
		boxes = k.service_desk(mb, np.random.default_rng(4100))
		ob = self.emit("ServiceDesk", mb, "Counters")
		ob.location = geo.to_blender((12.0, 0, 13.25))
		self.collide("Counters", boxes, T(12.0, 0, 13.25))

	def produce(self):
		k = self.kit
		rng = np.random.default_rng(5000)
		pairs = [("prod_apple", "prod_orange"), ("prod_lettuce", "prod_lime"), ("prod_banana", "prod_potato"),
			("prod_tomato", "prod_onion"), ("prod_orange", "prod_lime"), ("prod_apple", "prod_tomato")]
		n = 0
		for x in (5.0, 9.0, 13.0, 17.0):
			for z in (-2.0, 2.0, 6.0):
				mb = MB()
				boxes = k.produce_table(mb, rng, pairs[n % len(pairs)])
				n += 1
				ob = self.emit("ProduceTable_%02d" % n, mb, "Produce")
				ob.location = geo.to_blender((x, 0, z))
				self.collide("Tables", boxes, T(x, 0, z))
		zs = self._splits(-3.5, 8.0, 4.0)
		for i, (za, zb) in enumerate(zip(zs[:-1], zs[1:])):
			mb = MB()
			boxes = k.produce_wall_rack(mb, rng, zb - za, ["prod_lettuce", "prod_tomato", "prod_lime", "prod_onion", "prod_potato"][i:] + ["prod_apple"])
			zc = (za + zb) / 2
			ob = self.emit("ProduceRack_%d" % (i + 1), mb, "Produce")
			ob.location = geo.to_blender((X1 - 0.9, 0, zc))
			ob.rotation_euler = (0, 0, math.radians(-90))
			self.collide("Tables", boxes, chain_m(T(X1 - 0.9, 0, zc), RY(-90)))
		for i, (x, z, rot) in enumerate(((3.4, 8.0, 10.0), (18.9, -4.9, 90.0), (3.3, -4.6, -5.0))):
			mb = MB()
			boxes = k.pallet_stack(mb, rng, layers=2 if i != 1 else 3)
			ob = self.emit("Pallet_%d" % (i + 1), mb, "Produce")
			ob.location = geo.to_blender((x, 0, z))
			ob.rotation_euler = (0, 0, math.radians(rot))
			self.collide("Clutter", boxes, chain_m(T(x, 0, z), RY(rot)))

	# ------------------------------------------------------------ back of house
	def back_of_house(self):
		k = self.kit
		rng = np.random.default_rng(6000)
		# rows: A on the hallway wall, B back-to-back, a 2.2 m central aisle toward the EXIT (z ~ -13), C facing it,
		# a 1.3 m walkway behind C along the back wall
		rows = [
			("A", -9.0 - INT_HALF - 0.6, 180, -19.6, 8),
			("B", -10.7, 0, -18.1, 7), ("B", -11.9, 180, -18.1, 7),
			("C", -14.1, 0, -16.6, 6),
		]
		for name, zf, rot, xa, n in rows:
			for i in range(n):
				xc = xa + 0.75 + i * 1.5
				mb = MB()
				k.industrial_shelf(mb, np.random.default_rng(int(6100 + i * 7 + abs(zf) * 13 + rot)), fill=0.72)
				ob = self.emit("StorageShelf_%s%s_%d" % (name, "n" if rot == 0 else "s", i + 1), mb, "BackOfHouse")
				ob.location = geo.to_blender((xc, 0, zf))
				ob.rotation_euler = (0, 0, math.radians(rot))
		self.collide("StorageShelves", [((-19.6, 0, -9.7), (-7.6, 2.4, -9.0 - INT_HALF)), ((-18.1, 0, -11.9), (-7.6, 2.4, -10.7)),
			((-16.6, 0, -14.7), (-7.6, 2.4, -14.1))])
		# emergency door + EXIT sign (west wall, z ~ -13)
		mb = MB()
		with mb.at(RY(90)):
			boxes = k.steel_door(mb, 1.0, 2.1)
		ob = self.emit("EmergencyDoor", mb, "Doors")
		ob.location = geo.to_blender((X0, 0, sum(EMERGENCY_DOOR_Z) / 2))
		self.collide("Doors", [((X0 - EXT_T, 0, EMERGENCY_DOOR_Z[0]), (X0, 2.1, EMERGENCY_DOOR_Z[1]))])
		mb = MB()
		with mb.at(RY(90)):
			k.exit_sign(mb)
		self.emit("Sign_Exit", mb, "Signs", origin=(0, 0, 0))
		bpy.data.objects["Sign_Exit"].location = geo.to_blender((X0, 2.42, sum(EMERGENCY_DOOR_Z) / 2))
		make_empty(bpy, "ExitAnchor", self.col, (X0 + 0.35, 2.3, sum(EMERGENCY_DOOR_Z) / 2), self.group("LightAnchors"),
			{"kind": "exit", "zone": "storage", "color": "#2EFF6A"})
		# breaker panel on the hallway wall
		mb = MB()
		k.breaker_panel(mb, conduit_to=CEIL_BOH - BREAKER_POS[1] - 0.35)
		ob = self.emit("BreakerPanel_Static", mb, "BackOfHouse")
		ob.location = geo.to_blender((BREAKER_POS[0], BREAKER_POS[1], -9.0 + INT_HALF))
		# floor clutter in the storage room (reference 3): boxes, pallets, newspapers, scraps
		clutter = Chunks()
		col = []
		spots = [(-12.5, -12.4, 0.5, 0.35, 0.45, True), (-10.2, -13.7, 0.55, 0.4, 0.5, False), (-14.2, -13.75, 0.42, 0.3, 0.4, True),
			(-6.6, -15.3, 0.45, 0.4, 0.4, False), (-8.6, -12.3, 0.4, 0.3, 0.35, False), (-11.3, -15.45, 0.5, 0.35, 0.4, False),
			(-3.5, -10.6, 0.6, 0.5, 0.5, False), (-2.8, -10.3, 0.45, 0.35, 0.4, True), (0.8, -15.2, 0.6, 0.5, 0.5, False),
			(1.2, -14.5, 0.5, 0.4, 0.45, False), (0.9, -15.3, 0.55, 0.3, 0.45, False)]
		for (x, z, w, h, d, op) in spots:
			mb = clutter.get(x, z)
			rot = float(rng.uniform(-30, 30))
			with mb.at(T(x, 0, z), RY(rot)):
				boxes = k.floor_box(mb, rng, w, h, d, open_top=op)
			if w >= 0.45:
				col += [(bx, T(x, 0, z) @ RY(rot)) for bx in boxes]
		for (x, z, rot, layers) in ((-2.0, -14.6, 15, 2), (-1.0, -12.0, 85, 1)):
			mb = clutter.get(x, z)
			with mb.at(T(x, 0, z), RY(rot)):
				boxes = k.pallet_stack(mb, rng, layers)
			col += [(bx, T(x, 0, z) @ RY(rot)) for bx in boxes]
		for _ in range(12):
			x, z = float(rng.uniform(-17.0, -6.0)), float(rng.uniform(-13.9, -12.1))
			mb = clutter.get(x, z)
			with mb.at(T(x, 0.001 * float(rng.integers(0, 3)), z), RY(float(rng.uniform(0, 360)))):
				k.newspaper(mb, float(rng.uniform(0.35, 0.55)), float(rng.uniform(0.25, 0.4)))
		for _ in range(16):
			x, z = float(rng.uniform(-19.5, 1.5)), float(rng.uniform(-15.8, -9.4))
			mb = clutter.get(x, z)
			with mb.at(T(x, 0.001 * float(rng.integers(0, 3)), z), RY(float(rng.uniform(0, 360)))):
				k.newspaper(mb, float(rng.uniform(0.35, 0.55)), float(rng.uniform(0.25, 0.4)))
		for _ in range(70):
			x, z = float(rng.uniform(-19.8, 1.8)), float(rng.uniform(-15.9, -9.2))
			mb = clutter.get(x, z)
			with mb.at(T(x, 0, z), RY(float(rng.uniform(0, 360)))):
				k.scrap(mb, rng, float(rng.uniform(0.06, 0.16)))
		for _ in range(5):
			x, z = float(rng.uniform(-14, -6)), float(rng.uniform(-13.6, -12.4))
			mb = clutter.get(x, z)
			r = k.e("cardboard_flat")
			with mb.at(T(x, 0.006, z), RY(float(rng.uniform(0, 360)))):
				mb.quad((-0.5, 0, 0.35), (0.5, 0, 0.35), (0.5, 0, -0.35), (-0.5, 0, -0.35), r, ENV)
		# hallway: a little litter
		for _ in range(18):
			x, z = float(rng.uniform(-19.5, 19.5)), float(rng.uniform(-8.8, -6.2))
			mb = clutter.get(x, z)
			with mb.at(T(x, 0, z), RY(float(rng.uniform(0, 360)))):
				if rng.random() < 0.2:
					k.newspaper(mb, 0.4, 0.3)
				else:
					k.scrap(mb, rng, float(rng.uniform(0.05, 0.12)))
		for (cx, cz), mb in sorted(clutter.cells.items()):
			self.emit("Clutter_%d_%d" % (cx, cz), mb, "BackOfHouse", origin=((cx + 0.5) * 4, 0, (cz + 0.5) * 4))
		for (mn, mx), M in col:
			self.collide("Clutter", [(mn, mx)], M)
		# pipes along the hallway ceiling
		pipes = Chunks()
		for (zp, yp, r) in ((-8.6, 2.78, 0.06), (-8.75, 2.62, 0.035)):
			for xa in np.arange(X0, X1, 4.0):
				mb = pipes.get(xa + 2.0, zp)
				with mb.at(T(xa + 2.0, yp, zp), RZ(90)):
					mb.loft([(-2.0, r, 0.0), (2.0, r, 1.0)], 6, ENV, k.ep("pipe"))
				mb.box((xa + 1.98, yp, zp - 0.02), (xa + 2.02, CEIL_BOH, zp + 0.02), ENV, k.solid_env("chain"))
		for (cx, cz), mb in sorted(pipes.cells.items()):
			self.emit("Pipes_%d_%d" % (cx, cz), mb, "BackOfHouse", origin=((cx + 0.5) * 4, 0, (cz + 0.5) * 4))

	# ------------------------------------------------------------ sales-floor details
	def details(self):
		k = self.kit
		rng = np.random.default_rng(7000)
		det = Chunks()
		# fallen products in the aisles and cross aisles
		fallen = [(-14.3, 1.2), (-13.6, -1.8), (-10.4, 4.6), (-9.7, 0.4), (-10.2, -2.2), (-6.4, 3.3), (-5.7, -0.9),
			(-2.6, -2.2), (-1.3, 5.6), (-11.0, 8.4), (-4.5, 9.0), (1.4, 3.0), (-17.6, 4.2), (-6.0, -4.2)]
		labels = ["cereal_%d" % i for i in range(8)] + ["snackbox_%d" % i for i in range(6)]
		for (x, z) in fallen:
			mb = det.get(x, z)
			yaw = float(rng.uniform(0, 360))
			r = rng.random()
			if r < 0.45:
				lab = str(rng.choice(labels))
				w, h, d = (0.2, 0.3, 0.07) if lab.startswith("cereal") else (0.15, 0.21, 0.06)
				with mb.at(T(x, d, z), RY(yaw), RX(-90)):
					k.item_box(mb, w, h, d, lab)
			elif r < 0.75:
				for c in range(int(rng.integers(1, 4))):
					with mb.at(T(x + rng.uniform(-0.3, 0.3), 0.04, z + rng.uniform(-0.3, 0.3)), RY(float(rng.uniform(0, 360))), RZ(90), T(0, 0, 0.04)):
						k.item_can(mb, 0.04, 0.115, "can_%d" % int(rng.integers(0, 8)), y0=-0.0575)
			else:
				with mb.at(T(x, 0.06, z), RY(yaw), RX(-90)):
					k.item_bag(mb, 0.18, 0.27, 0.06, "snackbag_%d" % int(rng.integers(0, 6)))
		for _ in range(40):
			x, z = float(rng.uniform(-19.5, 19.5)), float(rng.uniform(-5.0, 15.5))
			if any(abs(x - rx) < 0.75 and ROW_Z0 - 0.1 < z < ROW_Z1 + 0.1 for rx in ROWS_X):
				continue
			mb = det.get(x, z)
			with mb.at(T(x, 0, z), RY(float(rng.uniform(0, 360)))):
				k.scrap(mb, rng, float(rng.uniform(0.05, 0.11)))
		# ceiling cables hanging in loops (references 1/2), heavier around the back of aisle 4
		cable_uv = k.ep("cable")
		spans = [((-2.6, -1.0), (-1.2, -3.2), 0.75), ((-1.4, -0.4), (-2.9, -2.6), 0.55), ((-3.2, -3.4), (-0.8, -4.6), 0.9),
			((-1.0, 1.4), (-2.8, -0.2), 0.6), ((-3.0, -1.6), (-1.6, -4.4), 1.0), ((-0.9, -2.4), (-2.0, -5.0), 0.7),
			((-2.2, 0.8), (-0.9, -0.6), 0.45), ((-10.5, -1.5), (-9.2, -4.0), 0.7), ((-6.8, 4.4), (-5.2, 2.2), 0.5),
			((-14.6, -2.0), (-13.2, -4.4), 0.8), ((8.0, -2.0), (10.5, -4.0), 0.6), ((14.5, 3.0), (12.6, 5.5), 0.7),
			((-17.0, 5.0), (-18.6, 2.6), 0.5), ((-8.8, 9.0), (-6.0, 8.0), 0.6), ((3.5, 12.0), (1.0, 9.5), 0.65)]
		for (a, b, sag) in spans:
			mb = det.get((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
			pts = []
			for i in range(13):
				t = i / 12
				pts.append((a[0] + (b[0] - a[0]) * t, CEIL_SALES - 0.02 - sag * 4 * t * (1 - t), a[1] + (b[1] - a[1]) * t))
			mb.tube(pts, 0.014, ENV, cable_uv)
		for (x, z, ln) in ((-1.6, -2.1, 1.1), (-2.4, -3.9, 0.8), (-9.8, -2.6, 1.3), (11.0, -1.0, 0.9), (-5.8, 6.5, 0.7)):
			mb = det.get(x, z)
			pts = [(x + 0.04 * math.sin(i), CEIL_SALES - 0.02 - ln * i / 6, z + 0.05 * math.cos(i * 1.3)) for i in range(7)]
			mb.tube(pts, 0.012, ENV, cable_uv)
		for (cx, cz), mb in sorted(det.cells.items()):
			self.emit("Details_%d_%d" % (cx, cz), mb, "Details", origin=((cx + 0.5) * 4, 0, (cz + 0.5) * 4))

	# ------------------------------------------------------------ signs
	def signs(self):
		k = self.kit
		for n, x in AISLES.items():
			mb = MB()
			k.hanging_sign(mb, "sign_aisle_%d" % n, 0.86, 0.69, CEIL_SALES - 3.3 - 0.345)
			self.emit("Sign_Aisle_%d" % n, mb, "Signs", origin=(0, 0, 0))
			bpy.data.objects["Sign_Aisle_%d" % n].location = geo.to_blender((x, 3.3, 2.0))
		hung = [("Sign_Dairy", "sign_dairy", 1.6, 0.52, (-2.0, 3.0, -5.4), 0), ("Sign_Frozen", "sign_frozen", 1.15, 0.31, (-17.9, 3.3, 2.0), 0),
			("Sign_Produce", "sign_produce", 1.6, 0.4, (11.0, 3.3, 2.0), 0), ("Sign_CustomerService", "sign_service", 2.4, 0.3, (12.0, 3.25, 12.2), 0)]
		for name, cell, w, h, pos, rot in hung:
			mb = MB()
			with mb.at(RY(rot)):
				k.hanging_sign(mb, cell, w, h, CEIL_SALES - pos[1] - h / 2)
			self.emit(name, mb, "Signs")
			bpy.data.objects[name].location = geo.to_blender(pos)
		mb = MB()
		k.wall_sign(mb, "sign_employees", 1.62, 0.23)
		self.emit("Sign_EmployeesOnly", mb, "Signs")
		bpy.data.objects["Sign_EmployeesOnly"].location = geo.to_blender((sum(EMP_DOOR) / 2, 2.62, SALES_Z0 + INT_HALF))
		for room, cell, w in (("storage", "sign_storage", 0.7), ("break_room", "sign_break", 0.95), ("office", "sign_office", 0.6), ("janitor", "sign_janitor", 0.7)):
			a, b = HALL_DOORS[room]
			mb = MB()
			k.wall_sign(mb, cell, w, w * 11 / {"storage": 46, "break_room": 64, "office": 40, "janitor": 46}[room])
			self.emit("Sign_Room_%s" % room, mb, "Signs")
			bpy.data.objects["Sign_Room_%s" % room].location = geo.to_blender(((a + b) / 2, 2.45, -9.0 + INT_HALF))

	# ------------------------------------------------------------ lights
	def lights(self):
		k = self.kit
		S, B = CEIL_SALES, CEIL_BOH
		plan = []  # (x, z, along, zone, ceiling, length, broken)
		for n, x in AISLES.items():
			for z in (5.9, 2.9, -0.1):
				plan.append((x, z, "z", "aisle_%d" % n, S, 1.25))
		for z in (5.9, 2.9, -0.1):
			plan.append((-17.9, z, "z", "frozen", S, 1.25))
		for x in (-18.0, -14.0, -10.0, -6.0, -2.0):
			plan.append((x, -4.3, "x", "dairy", S, 1.25))
		for x in (-16.0, -10.0, -4.0, 1.5):
			plan.append((x, 8.5, "x", "checkout", S, 1.25))
		for cx in COUNTERS_X:
			plan.append((cx + 0.95, 11.5, "z", "checkout", S, 1.25))
		for x in (-16.0, -9.5, -4.5):
			plan.append((x, 14.6, "x", "checkout", S, 1.25))
		plan.append((12.0, 13.6, "x", "service_desk", S, 1.25))
		plan.append((17.5, 11.2, "x", "service_desk", S, 1.25))
		for x in (5.5, 11.0, 16.5):
			for z in (-3.0, 1.5, 6.0):
				plan.append((x, z, "z", "produce", S, 1.25))
		for x in (-15.0, -7.0, 1.0, 9.0, 17.0):
			plan.append((x, -7.5, "x", "hallway", B, 0.9))
		for (x, z) in ((-16.5, -13.0), (-11.0, -13.0), (-3.0, -12.5)):
			plan.append((x, z, "x", "storage", B, 0.9))
		plan.append((6.0, -12.5, "x", "break_room", B, 0.9))
		plan.append((13.0, -12.5, "x", "office", B, 0.9))
		plan.append((18.0, -12.5, "z", "janitor", B, 0.9))
		broken_at = {(-2.0, 2.9), (-10.0, -0.1), (-10.0, -4.3), (-17.9, 5.9), (16.5, 6.0), (-16.0, 14.6), (9.0, -7.5), (-16.5, -13.0)}
		for i, (x, z, along, zone, ceil, L) in enumerate(plan):
			num = i + 1
			broken = (x, z) in broken_at
			hy = ceil - (0.47 if ceil > 3.5 else 0.25)
			rod = ceil - hy - 0.035
			mb = MB()
			with mb.at(RY(90 if along == "z" else 0)):
				k.fixture(mb, L=L, rod=rod, broken=broken, one_tube=broken and num % 2 == 0)
			name = "Fixture_%03d%s" % (num, "_broken" if broken else "")
			ob = self.emit(name, mb, "Fixtures", props={"zone": zone, "broken": int(broken), "anchor": "LightAnchor_%03d" % num})
			ob.location = geo.to_blender((x, hy, z))
			drop = 0.16 if broken else 0.0
			make_empty(bpy, "LightAnchor_%03d" % num, self.col, (x, hy - 0.13 - drop, z), self.group("LightAnchors"),
				{"zone": zone, "broken": int(broken), "fixture": name, "ceiling": ceil})
			self.fixtures.append((num, name, (x, round(hy - 0.13 - drop, 3), z), zone, broken))
		# red emergency lights (hallway + storage), each with an anchor
		em = [((-12.0, 2.55, -9.0 + INT_HALF), 0, "hallway"), ((8.0, 2.55, -9.0 + INT_HALF), 0, "hallway"),
			((-2.0, 2.55, SALES_Z0 - INT_HALF), 180, "hallway"), ((16.0, 2.55, SALES_Z0 - INT_HALF), 180, "hallway"),
			((X0, 2.5, -10.4), 90, "storage"), ((-12.0, 2.5, Z0), 0, "storage"), ((1.9, 2.5, -15.0), -90, "storage")]
		for i, (pos, rot, zone) in enumerate(em):
			mb = MB()
			with mb.at(RY(rot)):
				k.emergency_light(mb)
			ob = self.emit("EmergencyLight_%02d" % (i + 1), mb, "Fixtures", props={"zone": zone})
			ob.location = geo.to_blender(pos)
			off = RY(rot)[:3, :3] @ np.array([0.0, -0.2, 0.3])
			make_empty(bpy, "EmergencyAnchor_%02d" % (i + 1), self.col, tuple(np.array(pos) + off), self.group("LightAnchors"),
				{"kind": "emergency", "zone": zone, "color": "#B93B32"})
		for i, pos in enumerate(((-16.0, 1.3, -4.6), (-9.0, 1.3, -4.6), (-2.0, 1.3, -4.6), (-18.7, 1.3, 2.0))):
			make_empty(bpy, "CoolerAnchor_%02d" % (i + 1), self.col, pos, self.group("LightAnchors"),
				{"kind": "cooler", "zone": "dairy" if i < 3 else "frozen", "color": "#CFE4F0"})


def chain_m(*ms):
	return geo.chain(*ms)


# ================================================================== materials & textures
def make_image(name, canvas, save=True):
	img = bpy.data.images.new(name, canvas.w, canvas.h, alpha=True)
	img.pixels.foreach_set(px.save_rgba(canvas))
	if save:
		path = os.path.join(TEX_DIR, name + ".png")
		img.filepath_raw = path
		img.file_format = "PNG"
		img.save()
	img.pack()
	return img


def make_material(name, img=None, color=(1, 1, 1, 1), rough=0.8, metal=0.0, emit=None, strength=0.0, alpha=None, emit_from_img=False):
	m = bpy.data.materials.new(name)
	if not m.node_tree:
		m.use_nodes = True
	nt = m.node_tree
	b = nt.nodes.get("Principled BSDF")
	if img is not None:
		tex = nt.nodes.new("ShaderNodeTexImage")
		tex.image = img
		tex.interpolation = "Closest"
		nt.links.new(tex.outputs["Color"], b.inputs["Base Color"])
		if emit_from_img:
			nt.links.new(tex.outputs["Color"], b.inputs["Emission Color"])
			b.inputs["Emission Strength"].default_value = strength
	else:
		b.inputs["Base Color"].default_value = color
	b.inputs["Roughness"].default_value = rough
	b.inputs["Metallic"].default_value = metal
	if emit is not None:
		b.inputs["Emission Color"].default_value = emit
		b.inputs["Emission Strength"].default_value = strength
	if alpha is not None:
		b.inputs["Alpha"].default_value = alpha
		m.surface_render_method = "BLENDED"
	return m


def srgb_to_linear(h):
	c = px.C(h)
	lin = np.where(c[:3] <= 0.04045, c[:3] / 12.92, ((c[:3] + 0.055) / 1.055) ** 2.4)
	return (float(lin[0]), float(lin[1]), float(lin[2]), 1.0)


def build_materials():
	os.makedirs(TEX_DIR, exist_ok=True)
	P = px.build_products_atlas()
	E = px.build_env_atlas()
	floor, floor_rough = px.build_floor_tiles()
	conc = px.build_concrete()
	ceil = px.build_ceiling_tiles()
	wall_s = px.build_wall(21, "#7C7A6E", "#686658", "#2A2A26")
	wall_b = px.build_wall(22, "#56605A", "#46504A", "#262A28")
	imgs = {
		"atlas_products": make_image("atlas_products", P.c),
		"atlas_env": make_image("atlas_env", E.c),
		"floor_tiles": make_image("floor_tiles", floor),
		"floor_tiles_rough": make_image("floor_tiles_rough", floor_rough),
		"concrete": make_image("concrete", conc),
		"ceiling_tiles": make_image("ceiling_tiles", ceil),
		"wall_sales": make_image("wall_sales", wall_s),
		"wall_back": make_image("wall_back", wall_b),
	}
	mats = {
		"Products": make_material("Products", imgs["atlas_products"], rough=0.75),
		"Env": make_material("Env", imgs["atlas_env"], rough=0.7),
		"FloorTile": make_material("FloorTile", imgs["floor_tiles"], rough=0.2),
		"FloorConcrete": make_material("FloorConcrete", imgs["concrete"], rough=0.75),
		"CeilingTile": make_material("CeilingTile", imgs["ceiling_tiles"], rough=0.95),
		"WallSales": make_material("WallSales", imgs["wall_sales"], rough=0.85),
		"WallBack": make_material("WallBack", imgs["wall_back"], rough=0.85),
		"FluorescentTube": make_material("FluorescentTube", color=srgb_to_linear(px.CREAM), emit=srgb_to_linear(px.CREAM), strength=4.0),
		"CoolerLight": make_material("CoolerLight", color=srgb_to_linear("#CFE4F0"), emit=srgb_to_linear("#CFE4F0"), strength=2.0),
		"Glass": make_material("Glass", color=(0.02, 0.025, 0.03, 1.0), rough=0.05, alpha=0.18),
		"ExitSign": make_material("ExitSign", imgs["atlas_env"], strength=3.0, emit_from_img=True),
		"EmergencyLight": make_material("EmergencyLight", color=srgb_to_linear(px.RED), emit=srgb_to_linear("#FF3020"), strength=3.0),
	}
	return P, E, mats


# ================================================================== export
def export_glb(path):
	os.makedirs(os.path.dirname(path), exist_ok=True)
	bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_extras=True, export_yup=True,
		export_apply=False, export_materials="EXPORT", export_image_format="AUTO", export_cameras=False,
		export_lights=False, export_animations=False, use_selection=False)


def clear_objects():
	for ob in list(bpy.data.objects):
		bpy.data.objects.remove(ob, do_unlink=True)
	for me in list(bpy.data.meshes):
		if me.users == 0:
			bpy.data.meshes.remove(me)


def build_store(P, E, mats):
	k = kitmod.Kit(P, E)
	st = Store(k, mats, np.random.default_rng(42))
	st.floors()
	st.ceilings()
	st.walls()
	st.storefront()
	st.gondolas()
	st.coolers()
	st.checkouts()
	st.produce()
	st.back_of_house()
	st.details()
	st.signs()
	st.lights()
	st.finish_collision()
	return st


def kit_pieces(P, E, mats):
	k = kitmod.Kit(P, E)
	col = bpy.context.scene.collection
	out = []

	def piece(name, builder, colliders=True, anchors=()):
		clear_objects()
		mb = MB()
		boxes = builder(mb)
		obname = "".join(w.capitalize() for w in name.split("_"))
		make_object(bpy, obname, mb, mats, col)
		if colliders and boxes:
			cm = MB()
			for mn, mx in boxes:
				cm.box(mn, mx, "Collision", (0, 0, 0, 0))
			make_object(bpy, obname + "_Collision-colonly", cm, {}, col)
		for an, pos in anchors:
			make_empty(bpy, an, col, pos)
		path = os.path.join(KIT_DIR, name + ".glb")
		export_glb(path)
		out.append((name, mb.tris(), os.path.getsize(path)))

	def gondola(cat, placard):
		def b(mb):
			with mb.at(RY(90)):
				boxes = k.gondola_section(mb, np.random.default_rng(77), SECTION_L, cat, cat, placard, placard, True, True, 0.5, 0.03)
			return [((-SECTION_L / 2, 0, -0.6), (SECTION_L / 2, kitmod.GONDOLA_H, 0.6))]
		return b

	for cat, pl in (("cereal", "CEREAL"), ("snacks", "SNACKS"), ("drinks", "DRINKS"), ("canned", "CANNED"), ("baking", "BAKING")):
		piece("gondola_%s" % cat, gondola(cat, pl))

	def endcap(mb):
		return k.gondola_endcap(mb, np.random.default_rng(78), "soda")
	piece("gondola_endcap", endcap)
	piece("wall_cooler", lambda mb: [((a[0], a[1], a[2] + 0.4), (b[0], b[1], b[2] + 0.4)) for a, b in _shift(mb, (0, 0, 0.4), lambda m: k.wall_cooler(m, np.random.default_rng(79), 4, 0.75, "dairy"))])
	piece("freezer", lambda mb: [((a[0], a[1], a[2] + 0.4), (b[0], b[1], b[2] + 0.4)) for a, b in _shift(mb, (0, 0, 0.4), lambda m: k.wall_cooler(m, np.random.default_rng(80), 4, 0.8, "frozen"))])
	piece("checkout_counter", lambda mb: k.checkout_counter(mb, np.random.default_rng(81), 1))
	piece("service_desk", lambda mb: k.service_desk(mb, np.random.default_rng(82)))
	piece("produce_table", lambda mb: k.produce_table(mb, np.random.default_rng(83)))
	piece("produce_wall_rack", lambda mb: [((a[0], a[1], a[2] + 0.45), (b[0], b[1], b[2] + 0.45)) for a, b in _shift(mb, (0, 0, 0.45), lambda m: k.produce_wall_rack(m, np.random.default_rng(84), 2.4, ["prod_lettuce", "prod_tomato", "prod_lime"]))])
	piece("industrial_shelf", lambda mb: [((a[0], a[1], a[2] + 0.3), (b[0], b[1], b[2] + 0.3)) for a, b in _shift(mb, (0, 0, 0.3), lambda m: k.industrial_shelf(m, np.random.default_rng(85)))])
	piece("industrial_shelf_empty", lambda mb: [((a[0], a[1], a[2] + 0.3), (b[0], b[1], b[2] + 0.3)) for a, b in _shift(mb, (0, 0, 0.3), lambda m: k.industrial_shelf(m, np.random.default_rng(86), fill=0.0))])

	def fixture(L, rod, broken):
		def b(mb):
			with mb.at(T(0, -rod - 0.035, 0)):
				k.fixture(mb, L=L, rod=rod, broken=broken)
			return []
		return b
	piece("fluorescent_fixture", fixture(1.25, 0.45, False), anchors=[("LightAnchor", (0, -0.45 - 0.035 - 0.13, 0))])
	piece("fluorescent_fixture_broken", fixture(1.25, 0.45, True), anchors=[("LightAnchor", (0, -0.45 - 0.035 - 0.29, 0))])
	piece("fluorescent_fixture_short", fixture(0.9, 0.2, False), anchors=[("LightAnchor", (0, -0.2 - 0.035 - 0.13, 0))])

	def hanging(cell, w, h, hang):
		def b(mb):
			with mb.at(T(0, -hang - h / 2, 0)):
				k.hanging_sign(mb, cell, w, h, hang)
			return []
		return b
	for n in range(1, 5):
		piece("sign_aisle_%d" % n, hanging("sign_aisle_%d" % n, 0.86, 0.69, 0.355))
	piece("sign_dairy", hanging("sign_dairy", 1.3, 0.42, 0.79))
	piece("sign_frozen", hanging("sign_frozen", 1.15, 0.31, 0.545))
	piece("sign_produce", hanging("sign_produce", 1.6, 0.4, 0.5))
	piece("sign_customer_service", hanging("sign_service", 2.4, 0.3, 0.6))
	piece("sign_employees_only", lambda mb: (k.wall_sign(mb, "sign_employees", 1.62, 0.23), [])[1])
	piece("sign_exit", lambda mb: (k.exit_sign(mb), [])[1])
	piece("emergency_light", lambda mb: (k.emergency_light(mb), [])[1])
	piece("emergency_door", lambda mb: k.steel_door(mb, 1.0, 2.1))
	piece("pallet_boxes_static", lambda mb: k.pallet_stack(mb, np.random.default_rng(87), 2))
	return out


def _shift(mb, offset, builder):
	"""Builds with the piece translated so its footprint is centred (kit origin = floor centre)."""
	with mb.at(T(*offset)):
		return builder(mb)


def main():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	P, E, mats = build_materials()
	if "--kit-only" not in ARGS:
		st = build_store(P, E, mats)
		os.makedirs(OUT_DIR, exist_ok=True)
		bpy.ops.file.pack_all()
		bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH, compress=True)
		export_glb(os.path.join(OUT_DIR, "store_interior.glb"))
		print("STORE objects=%d tris=%d glb=%.2f MB fixtures=%d" % (st.objects, st.tris,
			os.path.getsize(os.path.join(OUT_DIR, "store_interior.glb")) / 1e6, len(st.fixtures)))
		for g, t in sorted(st.group_tris.items(), key=lambda kv: -kv[1]):
			print("  group %-14s tris=%d" % (g, t))
		with open(os.path.join(HERE, "light_anchors.txt"), "w") as f:
			f.write("# num name godot_position zone broken (generated by build_store.py)\n")
			for num, name, pos, zone, broken in st.fixtures:
				f.write("LightAnchor_%03d %s (%.2f, %.2f, %.2f) %s %s\n" % (num, name, pos[0], pos[1], pos[2], zone, "broken" if broken else ""))
	if "--no-kit" not in ARGS:
		res = kit_pieces(P, E, mats)
		for name, tris, size in res:
			print("KIT %-28s tris=%6d size=%7.1f KB" % (name, tris, size / 1e3))


main()
