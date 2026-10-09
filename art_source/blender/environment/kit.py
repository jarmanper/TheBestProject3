"""Reusable store pieces, authored in Godot coordinates with their front facing +Z.

Each builder writes into an MB (geo.py) at the MB's current transform, so the store places a piece with
`with mb.at(T(...), RY(...)): kit.piece(mb, ...)`, and the kit exporter calls it at the origin.
Collision boxes are returned as lists of (min, max) in the same local frame (transformed by the caller).
"""
import math

import numpy as np

from geo import T, RY, RZ

PROD = "Products"
ENV = "Env"
TUBE = "FluorescentTube"
COOL = "CoolerLight"
GLASS = "Glass"
EXITM = "ExitSign"
EMER = "EmergencyLight"

SHELF_LEVELS = (0.12, 0.55, 0.98, 1.41, 1.84)
GONDOLA_H = 2.2
GONDOLA_HALF = 0.6


class Kit:
	def __init__(self, products_atlas, env_atlas):
		self.P = products_atlas
		self.E = env_atlas

	# ------------------------------------------------------------ uv helpers
	def p(self, name, sub=None):
		return self.P.uv(name, sub)

	def pp(self, name, fx=0.5, fy=0.5):
		return self.P.uvpx(name, fx, fy)

	def e(self, name, sub=None):
		return self.E.uv(name, sub)

	def ep(self, name, fx=0.5, fy=0.5):
		return self.E.uvpx(name, fx, fy)

	def solid_env(self, name):
		return {"*": self.ep(name)}

	# ============================================================ products
	# Local item frame: centred on x = 0, standing on y = 0, front face at z = 0, extending to -z.
	def _box_uvs(self, label):
		return {"pz": self.p(label), "px": self.p(label, (0.0, 0.15, 0.12, 0.85)),
			"nx": self.p(label, (0.88, 0.15, 1.0, 0.85)), "py": self.pp(label, 0.15, 0.08)}

	def item_box(self, mb, w, h, d, label):
		mb.box((-w / 2, 0, -d), (w / 2, h, 0), PROD, self._box_uvs(label))

	def item_bag(self, mb, w, h, d, label):
		f = self.p(label)
		side = self.p(label, (0.0, 0.2, 0.15, 0.8))
		top = self.pp(label, 0.5, 0.04)
		lz = 0.18 * d
		mb.quad((-w / 2, 0, 0), (w / 2, 0, 0), (w / 2, h, -lz), (-w / 2, h, -lz), f, PROD)
		mb.quad((-w / 2, h, -lz), (w / 2, h, -lz), (w / 2, h, -d + lz), (-w / 2, h, -d + lz), top, PROD)
		mb.poly([(w / 2, 0, 0), (w / 2, 0, -d), (w / 2, h, -d + lz), (w / 2, h, -lz)],
			[(side[0], side[1]), (side[2], side[1]), (side[2], side[3]), (side[0], side[3])], PROD)
		mb.poly([(-w / 2, 0, -d), (-w / 2, 0, 0), (-w / 2, h, -lz), (-w / 2, h, -d + lz)],
			[(side[0], side[1]), (side[2], side[1]), (side[2], side[3]), (side[0], side[3])], PROD)

	def item_bottle(self, mb, r, h, label, cap, n=5):
		start = math.pi / 2 - math.pi / n
		mb.loft([(0.0, r, 0.0), (0.62 * h, r, 0.72), (0.82 * h, 0.36 * r, 1.0)], n, PROD, self.p(label), cz=-r, start=start)
		mb.loft([(0.82 * h, 0.34 * r, 0.0), (h, 0.34 * r, 1.0)], n, PROD, self.p(cap), cap_uv=self.p(cap), cz=-r, start=start)

	def item_can(self, mb, r, h, label, y0=0.0, n=6):
		start = math.pi / 2 - math.pi / n
		mb.loft([(y0, r, 0.0), (y0 + h, r, 1.0)], n, PROD, self.p(label), cap_uv=self.p("can_top"), cz=-r, start=start)

	def item_jar(self, mb, r, h, label, n=6):
		start = math.pi / 2 - math.pi / n
		mb.loft([(0.0, r, 0.0), (h, r, 1.0)], n, PROD, self.p(label), cap_uv=self.pp(label, 0.5, 0.05), cz=-r, start=start)

	def item_jug(self, mb, r, h, label, cap):
		mb.loft([(0.0, r, 0.0), (0.7 * h, r, 0.8), (0.88 * h, 0.5 * r, 1.0)], 4, PROD, self.p(label), cz=-r * 0.75, start=math.pi / 4)
		mb.loft([(0.88 * h, 0.2 * r, 0.0), (h, 0.2 * r, 1.0)], 4, PROD, self.p(cap), cap_uv=self.p(cap), cz=-r * 0.75, start=math.pi / 4)

	def item_carton(self, mb, w, h, d, label):
		bh = 0.8 * h
		f = self.p(label, (0, 0.2, 1, 1))
		g = self.p(label, (0, 0, 1, 0.2))
		side = self.p(label, (0.0, 0.3, 0.15, 1.0))
		mb.box((-w / 2, 0, -d), (w / 2, bh, 0), PROD, {"pz": f, "px": side, "nx": side})
		mb.quad((-w / 2, bh, 0), (w / 2, bh, 0), (w / 2, h, -d / 2), (-w / 2, h, -d / 2), g, PROD)
		mb.quad((w / 2, bh, -d), (-w / 2, bh, -d), (-w / 2, h, -d / 2), (w / 2, h, -d / 2), g, PROD)
		s = [(side[0], side[1]), (side[2], side[1]), ((side[0] + side[2]) / 2, side[3])]
		mb.poly([(w / 2, bh, 0), (w / 2, bh, -d), (w / 2, h, -d / 2)], s, PROD)
		mb.poly([(-w / 2, bh, -d), (-w / 2, bh, 0), (-w / 2, h, -d / 2)], s, PROD)

	def build_item(self, mb, spec, clear_h):
		k = spec[0]
		if k == "box":
			_, w, h, d, lab = spec
			self.item_box(mb, w, min(h, clear_h), d, lab)
		elif k == "bag":
			_, w, h, d, lab = spec
			self.item_bag(mb, w, min(h, clear_h), d, lab)
		elif k == "bottle":
			_, r, h, lab, cap = spec
			self.item_bottle(mb, r, min(h, clear_h), lab, cap)
		elif k == "can":
			_, r, h, lab, stack = spec
			for s in range(stack):
				if (s + 1) * h <= clear_h:
					self.item_can(mb, r, h, lab, y0=s * h)
		elif k == "jar":
			_, r, h, lab = spec
			self.item_jar(mb, r, min(h, clear_h), lab)
		elif k == "jug":
			_, r, h, lab, cap = spec
			self.item_jug(mb, r, min(h, clear_h), lab, cap)
		elif k == "carton":
			_, w, h, d, lab = spec
			self.item_carton(mb, w, min(h, clear_h), d, lab)

	@staticmethod
	def spec_width(spec):
		k = spec[0]
		if k in ("bottle", "can", "jar", "jug"):
			return 2 * spec[1]
		return spec[1]

	def item_generator(self, cat, level, rng):
		"""Returns a function producing the next item spec; consecutive facings repeat a variant (blocks)."""
		ri = lambda n: int(rng.integers(0, n))
		top = level == 4

		def choose():
			if cat == "cereal":
				if level == 0:
					return [("box", 0.23, 0.33, 0.5, "cereal_%d" % ri(8))]
				return [("box", float(rng.choice([0.17, 0.18, 0.19])), float(rng.choice([0.25, 0.27, 0.28])), 0.45, "cereal_%d" % ri(8))]
			if cat in ("snacks", "cookies", "candy"):
				if level == 0:
					return [("box", 0.34, 0.24, 0.5, "case_%d" % ri(3))]
				if cat == "candy":
					return [("box", 0.11, 0.15, 0.3, "snackbox_%d" % ri(6))]
				if level in (1, 2) or cat == "cookies" and level < 4:
					return [("box", 0.15, 0.21, 0.4, "snackbox_%d" % ri(6))]
				return [("bag", 0.18, 0.27, 0.3, "snackbag_%d" % ri(6))]
			if cat == "chips":
				return [("bag", 0.21 if level == 0 else 0.18, 0.32 if level == 0 else 0.27, 0.3, "snackbag_%d" % ri(6))]
			if cat in ("drinks", "soda", "juice"):
				b = ri(6)
				if level == 0:
					return [("box", 0.32, 0.26, 0.5, "case_%d" % ri(3))]
				if level == 1:
					return [("bottle", 0.055, 0.33, "bottle_%d" % b, "cap_%d" % ri(6))]
				if level == 2:
					if cat == "juice":
						return [("carton", 0.1, 0.27, 0.1, "juice_%d" % ri(3))]
					return [("bottle", 0.042, 0.27, "bottle_%d" % b, "cap_%d" % ri(6))]
				if level == 3:
					if cat == "soda":
						return [("can", 0.034, 0.12, "bottle_%d" % b, 2)]
					return [("carton", 0.095, 0.25, 0.1, "juice_%d" % ri(3))]
				return [("bottle", 0.034, 0.21, "bottle_%d" % b, "cap_%d" % ri(6))]
			if cat in ("canned", "soup"):
				if level == 0:
					return [("box", 0.36, 0.24, 0.5, "case_%d" % ri(3))]
				if top:
					return [("box", 0.14, 0.22, 0.32, "pasta_%d" % ri(3))] if rng.random() < 0.5 else [("jar", 0.045, 0.16, "jar_%d" % ri(4))]
				if level == 2 and rng.random() < 0.45:
					return [("jar", 0.045, 0.16, "jar_%d" % ri(4))]
				big = level == 1 and rng.random() < 0.4
				return [("can", 0.05 if big else 0.04, 0.15 if big else 0.115, "can_%d" % (ri(8) if cat == "canned" else ri(3)), 1 if big else int(rng.choice([1, 2, 2])))]
			if cat in ("baking", "pasta"):
				if level == 0:
					return [("bag", 0.22, 0.32, 0.25, "bagged_%d" % ri(3))]
				if level in (1, 2) or cat == "pasta":
					return [("box", 0.14, 0.22, 0.32, "pasta_%d" % ri(3))]
				if level == 3:
					return [("jar", 0.045, 0.16, "jar_%d" % ri(4))]
				return [("box", 0.15, 0.21, 0.4, "snackbox_%d" % ri(6))]
			return [("box", 0.2, 0.25, 0.4, "case_%d" % ri(3))]

		state = {"spec": None, "left": 0}

		def nxt():
			if state["left"] <= 0:
				state["spec"] = choose()[0]
				state["left"] = int(rng.integers(1, 4))
			state["left"] -= 1
			return state["spec"]

		return nxt

	def fill_level(self, mb, cat, level, length, clear_h, depth, rng, gaps=0.05):
		"""Fill one shelf face. Local: x along the shelf (-length/2..length/2), y = shelf top, front z = 0."""
		gen = self.item_generator(cat, level, rng)
		a = -length / 2 + 0.012
		end = length / 2 - 0.008
		any_cyl = False
		while True:
			spec = gen()
			w = self.spec_width(spec)
			if a + w > end:
				break
			if rng.random() < gaps:
				a += w + 0.01
				continue
			if spec[0] in ("bottle", "can", "jar", "jug"):
				any_cyl = True
				with mb.at(T(a + w / 2, 0, -rng.uniform(0.0, 0.02))):
					self.build_item(mb, spec, clear_h)
			else:
				with mb.at(T(a + w / 2, 0, -rng.uniform(0.0, 0.025))):
					self.build_item(mb, spec, clear_h)
			a += w + rng.uniform(0.004, 0.012)
		if any_cyl:
			fd = self.pp("fill_dark")
			mb.box((-length / 2, 0, -depth), (length / 2, min(clear_h, 0.3), -0.2), PROD, {"pz": fd, "py": fd})

	# ============================================================ gondola
	def gondola_section(self, mb, rng, L, cat_w, cat_e, placard_w=None, placard_e=None,
			upright_start=True, upright_end=False, overstock=0.4, gaps=0.05):
		"""Double-sided gondola section, spine along Z at x = 0, z in [-L/2, L/2]. West face = -x, east = +x.
		Returns collision boxes (local)."""
		z0, z1 = -L / 2, L / 2
		top = self.pp("shelf_top")
		kick = self.p("kick")
		lip = self.p("shelf_lip")
		peg = self.p("pegboard")
		up = self.pp("upright")
		# plinth / base deck
		mb.box((-GONDOLA_HALF, 0, z0), (GONDOLA_HALF, SHELF_LEVELS[0], z1), PROD,
			{"px": kick, "nx": kick, "py": top}, skip=("ny",))
		# spine back panel
		mb.box((-0.025, SHELF_LEVELS[0], z0), (0.025, GONDOLA_H, z1), PROD, {"px": peg, "nx": peg, "py": up})
		# uprights
		for zz, on in ((z0, upright_start), (z1, upright_end)):
			if on:
				mb.box((-0.045, 0, zz - 0.025), (0.045, GONDOLA_H + 0.03, zz + 0.025), PROD, {"*": up})
		# shelves + lips
		for i, y in enumerate(SHELF_LEVELS):
			for side in (-1, 1):
				xa, xb = sorted((0.025 * side, 0.575 * side))
				if i > 0:
					mb.box((xa, y - 0.025, z0), (xb, y, z1), PROD, {"py": top, "ny": up, "px": top, "nx": top}, skip=("pz", "nz"))
				lx0, lx1 = sorted((0.565 * side, 0.6 * side))
				face = "px" if side > 0 else "nx"
				mb.box((lx0, y - 0.045, z0), (lx1, y + 0.02, z1), PROD, {face: lip, "py": top, "ny": up})
		# top rail
		mb.box((-0.05, GONDOLA_H, z0), (0.05, GONDOLA_H + 0.03, z1), PROD, {"*": up})
		# products, each face in a frame whose +z is the face normal
		for side, cat in ((1, cat_e), (-1, cat_w)):
			if not cat:
				continue
			with mb.at(T(0.565 * side, 0, 0), RY(90 * side)):
				for i, y in enumerate(SHELF_LEVELS):
					clear = (SHELF_LEVELS[i + 1] - 0.03 - y - 0.02) if i < 4 else 0.33
					with mb.at(T(0, y, 0)):
						self.fill_level(mb, cat, i, L, clear, 0.52, rng, gaps)
		# overstock cases on top
		if rng.random() < overstock:
			n = int(rng.integers(1, 3))
			for _ in range(n):
				w = rng.uniform(0.35, 0.5)
				zc = rng.uniform(z0 + w / 2, z1 - w / 2)
				h = rng.uniform(0.2, 0.32)
				with mb.at(T(rng.uniform(-0.15, 0.15), GONDOLA_H + 0.03, zc), RY(float(rng.choice([0, 90])) + rng.uniform(-8, 8))):
					lab = "case_%d" % int(rng.integers(0, 3))
					mb.box((-w / 2, 0, -0.25), (w / 2, h, 0.25), PROD,
						{"pz": self.p(lab), "nz": self.p(lab), "px": self.p(lab, (0, 0, 0.5, 1)), "nx": self.p(lab, (0.5, 0, 1, 1)), "py": self.p("kraft_top")})
		# placards on top, angled 45 degrees toward the store front so they read like references 1/2
		for side, pl in ((1, placard_e), (-1, placard_w)):
			if pl:
				with mb.at(T(0.3 * side, GONDOLA_H + 0.03, z1 - 0.32), RY(45 * side)):
					self.placard(mb, pl)
		return [((-GONDOLA_HALF, 0, z0), (GONDOLA_HALF, GONDOLA_H, z1))]

	def placard(self, mb, name, w=0.8, h=0.185):
		r = self.p("pl_" + name)
		post = self.pp("upright")
		mb.box((-0.012, 0, -0.012), (0.012, 0.06, 0.012), PROD, {"*": post})
		mb.box((-w / 2, 0.06, -0.008), (w / 2, 0.06 + h, 0.008), PROD,
			{"pz": r, "nz": r, "py": self.pp("pl_" + name, 0.02, 0.05), "px": post, "nx": post, "ny": post})

	def gondola_endcap(self, mb, rng, cat, width=2 * GONDOLA_HALF, depth=0.4, gaps=0.04):
		"""End cap facing +z: occupies x +-width/2, z in [-depth, 0]."""
		top = self.pp("shelf_top")
		kick = self.p("kick")
		lip = self.p("shelf_lip")
		endp = self.p("endpanel")
		up = self.pp("upright")
		hw = width / 2
		mb.box((-hw, 0, -depth), (hw, SHELF_LEVELS[0], 0), PROD, {"pz": kick, "px": kick, "nx": kick, "py": top}, skip=("ny",))
		mb.box((-hw, SHELF_LEVELS[0], -depth), (hw, GONDOLA_H, -depth + 0.03), PROD, {"pz": self.p("pegboard"), "py": up})
		for sx in (-1, 1):
			xa, xb = sorted((sx * hw, sx * (hw - 0.03)))
			mb.box((xa, 0, -depth), (xb, GONDOLA_H, 0), PROD, {"px": endp, "nx": endp, "pz": up, "py": up})
		for i, y in enumerate(SHELF_LEVELS):
			if i > 0:
				mb.box((-hw + 0.03, y - 0.025, -depth + 0.03), (hw - 0.03, y, -0.01), PROD, {"py": top, "ny": up}, skip=("pz", "nz", "px", "nx"))
			mb.box((-hw + 0.03, y - 0.045, -0.035), (hw - 0.03, y + 0.02, 0), PROD, {"pz": lip, "py": top})
			clear = (SHELF_LEVELS[i + 1] - 0.03 - y - 0.02) if i < 4 else 0.33
			with mb.at(T(0, y, -0.035)):
				self.fill_level(mb, cat, i, width - 0.08, clear, depth - 0.07, rng, gaps)
		mb.box((-hw, GONDOLA_H, -depth), (hw, GONDOLA_H + 0.03, 0), PROD, {"*": up})
		return [((-hw, 0, -depth), (hw, GONDOLA_H, 0))]

	# ============================================================ coolers / freezers
	def wall_cooler(self, mb, rng, n_doors, door_w, kind="dairy", depth=0.8, height=2.2, side_l=True, side_r=True):
		"""Glass-door wall cooler, front at z = 0, back at z = -depth, x centred. kind: dairy | frozen."""
		W = n_doors * door_w
		x0, x1 = -W / 2, W / 2
		frame = self.solid_env("cooler_frame")
		inner = self.ep("frost" if kind == "frozen" else "cooler_inner")
		kick_y, head_y = 0.2, 1.95
		# kick grille, header, top
		mb.box((x0, 0, -0.1), (x1, kick_y, 0), ENV, {"pz": self.e("cooler_grille"), "py": self.ep("cooler_frame")})
		mb.box((x0, head_y, -0.12), (x1, height, 0), ENV, {"pz": self.e("cooler_header"), "ny": self.ep("cooler_frame"), "py": self.ep("cooler_frame")})
		mb.box((x0, height - 0.02, -depth), (x1, height, -0.12), ENV, {"py": self.ep("cooler_frame")})
		# interior shell
		mb.quad((x0, kick_y, -depth + 0.02), (x1, kick_y, -depth + 0.02), (x1, head_y, -depth + 0.02), (x0, head_y, -depth + 0.02), inner, ENV)
		mb.quad((x0, head_y, -depth + 0.02), (x1, head_y, -depth + 0.02), (x1, head_y, -0.1), (x0, head_y, -0.1), inner, ENV)  # ceiling, faces down
		mb.box((x0, 0, -depth), (x1, kick_y, -0.1), ENV, {"py": inner})
		side = {"px": self.e("cooler_side"), "nx": self.e("cooler_side"), "*": self.ep("cooler_frame")}
		for on, xs in ((side_l, x0), (side_r, x1)):
			if on:
				xa, xb = (xs, xs + 0.04) if xs == x0 else (xs - 0.04, xs)
				mb.box((xa, 0, -depth), (xb, height, 0), ENV, side)
		shelves = (0.57, 0.92, 1.27, 1.62)
		for y in shelves:
			mb.box((x0 + 0.04, y - 0.02, -depth + 0.05), (x1 - 0.04, y, -0.1), ENV, {"py": self.e("wire_shelf"), "pz": self.ep("handle"), "ny": inner})
		# mullions with light strips behind the glass
		for k in range(n_doors + 1):
			xm = x0 + k * door_w
			mb.box((xm - 0.03, kick_y, -0.07), (xm + 0.03, head_y, 0), ENV, frame)
			mb.box((xm - 0.015, kick_y + 0.05, -0.1), (xm + 0.015, head_y - 0.05, -0.07), COOL, {"*": self.ep("black")})
		mb.box((x0, head_y - 0.05, -0.14), (x1, head_y - 0.02, -0.12), COOL, {"ny": self.ep("black"), "pz": self.ep("black")})
		# doors: glass + handle
		for k in range(n_doors):
			xa, xb = x0 + k * door_w + 0.03, x0 + (k + 1) * door_w - 0.03
			mb.quad((xa, kick_y, -0.02), (xb, kick_y, -0.02), (xb, head_y, -0.02), (xa, head_y, -0.02), self.ep("black"), GLASS)
			mb.box((xa, kick_y, -0.03), (xb, kick_y + 0.04, 0.0), ENV, frame)
			mb.box((xa, head_y - 0.04, -0.03), (xb, head_y, 0.0), ENV, frame)
			hx = xb - 0.07 if k % 2 == 0 else xa + 0.05
			mb.box((hx, 0.85, 0.0), (hx + 0.02, 1.55, 0.04), ENV, self.solid_env("handle"))
			# stock
			for li, y in enumerate((kick_y,) + shelves):
				clear = (shelves[li] - 0.04 - y) if li < len(shelves) else head_y - y - 0.06
				with mb.at(T((xa + xb) / 2, y, -0.12)):
					self._cooler_stock(mb, rng, kind, xb - xa - 0.04, clear, k, li)
		return [((x0, 0, -depth), (x1, height, 0))]

	def _cooler_stock(self, mb, rng, kind, length, clear, door, level):
		a = -length / 2
		if kind == "dairy":
			theme = (door * 7 + level * 3 + int(rng.integers(0, 3))) % 4
		else:
			theme = (door * 5 + level * 2 + int(rng.integers(0, 3))) % 3
		while True:
			if kind == "dairy":
				if theme == 0:
					spec, w = ("jug", 0.075, 0.26, "milk_%d" % int(rng.integers(0, 3)), "cap_%d" % int(rng.integers(0, 3))), 0.16
				elif theme == 1:
					spec, w = ("carton", 0.095, 0.25, 0.095, "milk_%d" % int(rng.integers(0, 3))), 0.105
				elif theme == 2:
					spec, w = ("carton", 0.095, 0.25, 0.095, "juice_%d" % int(rng.integers(0, 3))), 0.105
				else:
					spec, w = ("box", 0.12, 0.08, 0.4, "snackbox_%d" % int(rng.integers(0, 6))), 0.13
			else:
				if theme == 0:
					spec, w = ("box", 0.3, 0.2, 0.45, "frozen_%d" % int(rng.integers(0, 2))), 0.31
				elif theme == 1:
					spec, w = ("can", 0.07, 0.12, "frozen_3", 1), 0.15
				else:
					spec, w = ("bag", 0.2, 0.26, 0.2, "frozen_2"), 0.21
			if a + w > length / 2:
				break
			if rng.random() > 0.07:
				with mb.at(T(a + w / 2, 0, 0)):
					self.build_item(mb, spec, clear)
			a += w + 0.008

	# ============================================================ checkout counter
	def checkout_counter(self, mb, rng, lane=1):
		"""Counter 0.9 wide (x) x 3 long (z), register/bagging at the +z end, cashier on +x.
		Crouch cavity 0.8 (z) x 0.8 (x) x 0.9 (y) open to +x at z in [-0.1, 0.7]. Returns collision boxes."""
		body = self.e("counter_body")
		topm = self.e("counter_top")
		kick = self.e("counter_kick")
		hx, hz, top_y, cav_y = 0.45, 1.5, 0.98, 0.9
		cz0, cz1, cx0 = -0.1, 0.7, -0.35
		bodyuv = {"px": body, "nx": body, "pz": body, "nz": body}
		mb.box((-hx, 0, -hz), (hx, cav_y, cz0), ENV, bodyuv)
		mb.box((-hx, 0, cz1), (hx, cav_y, hz), ENV, bodyuv)
		mb.box((-hx, 0, cz0), (cx0, cav_y, cz1), ENV, {"px": self.ep("counter_kick"), "nx": body})
		mb.box((-hx - 0.02, cav_y, -hz - 0.02), (hx + 0.02, top_y, hz + 0.02), ENV,
			{"py": topm, "px": self.ep("steel"), "nx": self.ep("steel"), "pz": self.ep("steel"), "nz": self.ep("steel"), "ny": self.ep("counter_kick")})
		# kick plates
		for (za, zb) in ((-hz, cz0), (cz1, hz)):
			mb.box((hx, 0, za), (hx + 0.01, 0.1, zb), ENV, {"px": kick})
		mb.box((-hx - 0.01, 0, -hz), (-hx, 0.1, hz), ENV, {"nx": kick})
		# conveyor
		mb.box((-0.32, top_y, -hz + 0.05), (0.26, top_y + 0.02, 0.2), ENV, {"py": self.e("belt"), "pz": self.ep("rubber"), "nz": self.ep("rubber")})
		for xa in (-0.36, 0.26):
			mb.box((xa, top_y, -hz + 0.03), (xa + 0.04, top_y + 0.06, 0.22), ENV, self.solid_env("steel"))
		mb.box((-0.28, top_y + 0.02, -0.3), (0.22, top_y + 0.06, -0.26), ENV, self.solid_env("rubber"))  # divider bar
		# scanner bed
		mb.box((-0.3, top_y, 0.25), (0.22, top_y + 0.01, 0.6), ENV, {"py": self.e("scanner")})
		mb.box((-0.42, top_y, 0.3), (-0.3, top_y + 0.28, 0.55), ENV, {"*": self.ep("register"), "px": self.e("scanner")})
		# register + screen on the cashier side
		mb.box((0.05, top_y, 0.75), (0.42, top_y + 0.12, 1.15), ENV, {"*": self.ep("register"), "py": self.e("register")})
		mb.box((0.2, top_y + 0.12, 0.93), (0.24, top_y + 0.36, 0.97), ENV, self.solid_env("steel"))
		mb.box((0.18, top_y + 0.32, 0.82), (0.24, top_y + 0.56, 1.08), ENV, {"*": self.ep("register"), "px": self.e("screen")})
		# card terminal facing the customer
		mb.box((-0.42, top_y, 0.8), (-0.3, top_y + 0.14, 0.95), ENV, {"*": self.ep("register"), "nx": self.e("screen")})
		# bagging rack
		for zz in (1.22, 1.46):
			mb.box((-0.3, top_y, zz), (-0.27, top_y + 0.45, zz + 0.03), ENV, self.solid_env("steel"))
			mb.box((0.2, top_y, zz), (0.23, top_y + 0.45, zz + 0.03), ENV, self.solid_env("steel"))
		mb.box((-0.3, top_y + 0.42, 1.22), (0.23, top_y + 0.45, 1.49), ENV, self.solid_env("steel"))
		mb.box((-0.24, top_y, 1.25), (0.16, top_y + 0.06, 1.45), ENV, self.solid_env("paper_scrap"))
		# lane light pole with number
		mb.box((0.32, top_y, -hz + 0.05), (0.36, 2.25, -hz + 0.09), ENV, self.solid_env("steel"))
		sign = self.e("sign_lane_%d" % lane)
		mb.box((0.22, 2.25, -hz + 0.02), (0.46, 2.49, -hz + 0.12), ENV, {"pz": sign, "nz": sign, "px": sign, "nx": sign, "py": self.ep("frame"), "ny": self.ep("frame")})
		return [((-hx, 0, -hz), (hx, top_y, cz0)), ((-hx, 0, cz1), (hx, top_y, hz)),
			((-hx, 0, cz0), (cx0, top_y, cz1)), ((-hx, cav_y, cz0), (hx, top_y, cz1))]

	# ============================================================ service desk
	def service_desk(self, mb, rng):
		"""L-shaped desk in WORLD-aligned local coords with origin at (12, 0, 13.25) (store x 9..15, z 12..14.5).
		Long arm faces -z (customers), short arm faces +x. Cavity in the long arm opening to +z (employee side)."""
		body = self.e("counter_body")
		topm = self.e("counter_top")
		kick = self.e("counter_kick")
		ox, oz = 12.0, 13.25
		H, cav_h = 1.05, 0.9
		boxes = []

		def L(x, z):
			return x - ox, z - oz

		def solid(xa, za, xb, zb, y0=0.0, y1=cav_h, uv=None):
			(a, b), (c, d) = L(xa, za), L(xb, zb)
			mb.box((a, y0, b), (c, y1, d), ENV, uv or {"px": body, "nx": body, "pz": body, "nz": body})

		# long arm x 9..14.1, z 12..12.9 with cavity x 10.2..11.0, z 12.1..12.9
		solid(9.0, 12.0, 10.2, 12.9)
		solid(11.0, 12.0, 14.1, 12.9)
		solid(10.2, 12.0, 11.0, 12.1, uv={"nz": body, "pz": self.ep("counter_kick")})
		# short arm x 14.1..15, z 12..14.5
		solid(14.1, 12.0, 15.0, 14.5)
		# tops (overhang on the customer sides)
		for (xa, za, xb, zb) in ((8.95, 11.9, 14.1, 12.95), (14.1, 11.9, 15.1, 14.55)):
			(a, b), (c, d) = L(xa, za), L(xb, zb)
			mb.box((a, cav_h, b), (c, H, d), ENV, {"py": topm, "px": self.ep("steel"), "nx": self.ep("steel"), "pz": self.ep("steel"), "nz": self.ep("steel"), "ny": self.ep("counter_kick")})
		# kick plates customer side
		(a, b), (c, d) = L(9.0, 11.99), L(14.1, 12.0)
		mb.box((a, 0, b), (c, 0.1, d), ENV, {"nz": kick})
		(a, b), (c, d) = L(15.0, 12.0), L(15.01, 14.5)
		mb.box((a, 0, b), (c, 0.1, d), ENV, {"px": kick})
		# computer + monitor facing the employee side, bell, papers
		(a, b) = L(12.6, 12.45)
		mb.box((a - 0.2, H, b - 0.15), (a + 0.2, H + 0.08, b + 0.15), ENV, {"*": self.ep("register"), "py": self.e("register")})
		mb.box((a - 0.03, H + 0.08, b - 0.02), (a + 0.03, H + 0.25, b + 0.02), ENV, self.solid_env("steel"))
		mb.box((a - 0.2, H + 0.22, b - 0.04), (a + 0.2, H + 0.5, b + 0.04), ENV, {"*": self.ep("register"), "pz": self.e("screen")})
		(a, b) = L(10.0, 12.3)
		mb.box((a - 0.15, H, b - 0.11), (a + 0.15, H + 0.01, b + 0.11), ENV, {"py": self.e("newspaper")})
		(a, b) = L(14.6, 13.0)
		mb.loft([(H, 0.05, 0.0), (H + 0.05, 0.02, 1.0)], 6, ENV, self.ep("steel"), cap_uv=self.ep("steel"), cx=a, cz=b)
		# back cabinet along the front wall
		(a, b), (c, d) = L(9.4, 15.45), L(14.0, 16.0)
		mb.box((a, 0, b), (c, 0.9, d), ENV, {"nz": body, "py": topm, "px": body, "nx": body})
		for i in range(5):
			lab = "box_stock_%d" % int(rng.integers(0, 4))
			w = rng.uniform(0.3, 0.45)
			xa = a + 0.1 + i * 0.9
			mb.box((xa, 0.9, b + 0.05), (xa + w, 0.9 + rng.uniform(0.2, 0.35), b + 0.45), ENV, {"*": self.e(lab)}, skip=("ny",))
		for (xa, za, xb, zb) in ((9.0, 12.0, 10.2, 12.9), (11.0, 12.0, 14.1, 12.9), (10.2, 12.0, 11.0, 12.1), (14.1, 12.0, 15.0, 14.5), (9.4, 15.45, 14.0, 16.0)):
			(a, b), (c, d) = L(xa, za), L(xb, zb)
			boxes.append(((a, 0, b), (c, H if zb < 15 else 0.9, d)))
		(a, b), (c, d) = L(10.2, 12.0), L(11.0, 12.9)
		boxes.append(((a, cav_h, b), (c, H, d)))
		return boxes

	# ============================================================ produce
	def produce_table(self, mb, rng, kinds=("prod_apple", "prod_orange")):
		"""1.2 (x) x 2.4 (z) display table, 0.9 m tall, two sloped produce beds."""
		hx, hz = 0.6, 1.2
		skirt = self.e("table_skirt")
		wood = self.e("wood")
		mb.box((-hx + 0.05, 0, -hz + 0.05), (hx - 0.05, 0.7, hz - 0.05), ENV, {"px": skirt, "nx": skirt, "pz": skirt, "nz": skirt})
		for (xa, za, xb, zb) in ((-hx, -hz, hx, -hz + 0.06), (-hx, hz - 0.06, hx, hz), (-hx, -hz, -hx + 0.06, hz), (hx - 0.06, -hz, hx, hz)):
			mb.box((xa, 0.7, za), (xb, 0.86, zb), ENV, {"*": wood})
		mb.box((-0.03, 0.7, -hz), (0.03, 0.95, hz), ENV, {"*": wood})
		nz = 10
		for side, kind in ((-1, kinds[0]), (1, kinds[1])):
			uv = self.e(kind)
			xs = [side * 0.03, side * 0.2, side * 0.38, side * 0.56]
			ys = [0.95, 0.93, 0.88, 0.8]
			zs = np.linspace(-hz + 0.06, hz - 0.06, nz + 1)
			jit = rng.uniform(-0.035, 0.035, (4, nz + 1))
			jit[0, :] *= 0.4
			jit[-1, :] *= 0.3
			for i in range(3):
				for j in range(nz):
					p = lambda ii, jj: (xs[ii], ys[ii] + jit[ii, jj], zs[jj])
					if side > 0:
						corners = [p(i, j + 1), p(i + 1, j + 1), p(i + 1, j), p(i, j)]
					else:
						corners = [p(i + 1, j + 1), p(i, j + 1), p(i, j), p(i + 1, j)]
					mb.quad(*corners, uv, ENV)
		return [((-hx, 0, -hz), (hx, 0.9, hz))]

	def produce_wall_rack(self, mb, rng, length, kinds):
		"""Angled wall rack against a wall at z = -0.9 (back), front at z = 0, x centred."""
		hx = length / 2
		skirt = self.e("table_skirt")
		wood = self.e("wood")
		mb.box((-hx, 0, -0.9), (hx, 0.75, 0), ENV, {"pz": skirt, "px": skirt, "nx": skirt})
		mb.box((-hx, 0.75, -0.9), (hx, 1.9, -0.82), ENV, {"pz": self.e("table_skirt"), "py": wood})
		mb.box((-hx, 1.9, -0.9), (hx, 2.0, -0.6), ENV, {"*": wood})
		n = max(1, int(round(length / 0.8)))
		bw = length / n
		for i in range(n):
			uv = self.e(kinds[i % len(kinds)])
			xa, xb = -hx + i * bw + 0.02, -hx + (i + 1) * bw - 0.02
			mb.quad((xa, 0.85, 0), (xb, 0.85, 0), (xb, 1.3, -0.82), (xa, 1.3, -0.82), uv, ENV)
			mb.box((xb, 0.75, -0.85), (xb + 0.04, 1.35, 0), ENV, {"*": wood})
		mb.box((-hx, 0.75, -0.05), (hx, 0.9, 0), ENV, {"*": wood})
		return [((-hx, 0, -0.9), (hx, 2.0, 0))]

	def pallet_stack(self, mb, rng, layers=2):
		"""1.2 x 1.0 pallet with kraft boxes, footprint centred."""
		wood = self.e("pallet")
		for k in range(3):
			zz = -0.5 + k * 0.45
			mb.box((-0.6, 0, zz), (0.6, 0.1, zz + 0.1), ENV, {"*": wood})
		mb.box((-0.6, 0.1, -0.5), (0.6, 0.14, 0.5), ENV, {"*": wood, "py": wood}, skip=("ny",))
		h = 0.14
		for layer in range(layers):
			bh = rng.uniform(0.25, 0.32)
			for i in range(2):
				for j in range(2):
					lab = "box_kraft_%d" % int(rng.integers(0, 3))
					xa = -0.58 + i * 0.59
					za = -0.48 + j * 0.49
					mb.box((xa, h, za), (xa + 0.56, h + bh, za + 0.46), ENV, {"*": self.e(lab)}, skip=("ny",))
			h += bh
		return [((-0.6, 0, -0.5), (0.6, h, 0.5))]

	# ============================================================ lights
	def fixture(self, mb, L=1.25, rod=0.45, broken=False, one_tube=False):
		"""Two-tube strip fixture, long axis along x, housing centred at the origin.
		Rods go up `rod` metres from the housing top (to the ceiling)."""
		housing = self.ep("fixture_housing")
		inner = self.ep("fixture_inner")
		ht = 0.035
		pivot = L / 2 - 0.12

		def body():
			mb.box((-L / 2, -ht, -0.11), (L / 2, ht, 0.11), ENV, {"*": housing, "ny": inner})
			for sz in (-1, 1):
				pts = [(-L / 2, -ht, sz * 0.11), (L / 2, -ht, sz * 0.11), (L / 2, -ht - 0.05, sz * 0.15), (-L / 2, -ht - 0.05, sz * 0.15)]
				mb.poly(pts, [(inner[0], inner[1])] * 4, ENV)
				mb.poly(pts[::-1], [(inner[0], inner[1])] * 4, ENV)
			for k, tz in enumerate((-0.05, 0.05)):
				if one_tube and k == 0:
					continue
				with mb.at(T(0, -ht - 0.03, tz), RZ(90)):
					mb.loft([(-L / 2 + 0.05, 0.018, 0.0), (L / 2 - 0.05, 0.018, 1.0)], 6, TUBE, (0.5, 0.5, 0.5, 0.5))
			for ex in (-L / 2 + 0.02, L / 2 - 0.05):
				mb.box((ex, -ht - 0.05, -0.09), (ex + 0.03, -ht, 0.09), ENV, {"*": housing})

		if broken:
			tilt = 13.0
			with mb.at(T(pivot, ht, 0), RZ(tilt), T(-pivot, -ht, 0)):
				body()
			mb.box((pivot - 0.008, ht, -0.008), (pivot + 0.008, ht + rod, 0.008), ENV, self.solid_env("chain"))
			mb.box((-pivot - 0.008, ht + rod * 0.55, -0.008), (-pivot + 0.008, ht + rod, 0.008), ENV, self.solid_env("chain"))
			drop = math.sin(math.radians(tilt)) * 2 * pivot
			mb.tube([(-pivot + 0.05, ht + rod, 0.03), (-pivot + 0.1, ht + rod * 0.4, 0.05), (-pivot + 0.2, ht - drop * 0.5 + 0.1, 0.04)], 0.006, ENV, self.ep("cable"))
		else:
			body()
			for px in (-pivot, pivot):
				mb.box((px - 0.008, ht, -0.008), (px + 0.008, ht + rod, 0.008), ENV, self.solid_env("chain"))

	def emergency_light(self, mb):
		"""Wall unit, back on z = 0, two red lamp heads."""
		mb.box((-0.16, -0.06, 0), (0.16, 0.06, 0.08), ENV, self.solid_env("emerg_housing"))
		for sx in (-1, 1):
			mb.box((sx * 0.1 - 0.035, -0.11, 0.02), (sx * 0.1 + 0.035, -0.05, 0.09), EMER, {"*": self.ep("black")})

	def exit_sign(self, mb):
		"""Wall-mounted EXIT box, back on z = 0, glowing face +z."""
		mb.box((-0.3, -0.13, 0), (0.3, 0.13, 0.08), ENV, self.solid_env("emerg_housing"), skip=("pz",))
		mb.quad((-0.285, -0.12, 0.081), (0.285, -0.12, 0.081), (0.285, 0.12, 0.081), (-0.285, 0.12, 0.081), self.e("sign_exit"), EXITM)

	# ============================================================ signs
	def hanging_sign(self, mb, cell, w, h, hang, thick=0.03):
		"""Board centred on the origin, readable from +z and -z, chains up `hang` m from the board top."""
		r = self.e(cell)
		fr = self.ep("frame")
		mb.box((-w / 2, -h / 2, -thick / 2), (w / 2, h / 2, thick / 2), ENV, {"pz": r, "nz": r, "*": fr})
		for sx in (-1, 1):
			x = sx * (w / 2 - 0.08)
			mb.box((x - 0.006, h / 2, -0.006), (x + 0.006, h / 2 + hang, 0.006), ENV, self.solid_env("chain"))

	def wall_sign(self, mb, cell, w, h):
		r = self.e(cell)
		mb.box((-w / 2, -h / 2, 0), (w / 2, h / 2, 0.025), ENV, {"pz": r, "*": self.ep("frame")}, skip=("nz",))

	def breaker_panel(self, mb, conduit_to=1.4):
		"""Grey breaker panel, back on z = 0, centred on the origin, conduit to the ceiling."""
		mb.box((-0.25, -0.35, 0), (0.25, 0.35, 0.1), ENV, {"pz": self.e("breaker"), "*": self.ep("frame")}, skip=("nz",))
		mb.box((-0.05, 0.35, 0.02), (0.05, 0.35 + conduit_to, 0.07), ENV, self.solid_env("conduit"))
		mb.box((0.12, 0.35, 0.03), (0.16, 0.35 + conduit_to, 0.06), ENV, self.solid_env("conduit"))

	def steel_door(self, mb, w=1.0, h=2.1):
		"""Closed steel door in a wall opening; interior face of the wall at z = 0, door faces +z."""
		mb.box((-w / 2, 0, -0.06), (w / 2, h, -0.02), ENV, {"pz": self.e("door_steel"), "*": self.ep("frame")})
		mb.box((-w / 2 + 0.08, 0.95, -0.02), (w / 2 - 0.08, 1.02, 0.05), ENV, self.solid_env("handle"))
		fr = self.solid_env("frame")
		mb.box((-w / 2 - 0.06, 0, -0.02), (-w / 2, h + 0.06, 0.03), ENV, fr)
		mb.box((w / 2, 0, -0.02), (w / 2 + 0.06, h + 0.06, 0.03), ENV, fr)
		mb.box((-w / 2, h, -0.02), (w / 2, h + 0.06, 0.03), ENV, fr)
		return [((-w / 2, 0, -0.06), (w / 2, h, -0.02))]

	# ============================================================ back of house
	def industrial_shelf(self, mb, rng, L=1.5, D=0.6, H=2.4, levels=(0.1, 0.7, 1.3, 1.9), fill=0.75, floor_boxes=True):
		"""Grey slotted-angle shelving unit, front at z = 0, back at z = -D, x centred (reference 3)."""
		upr = self.e("ishelf_upright")
		beam = self.e("ishelf_beam")
		deck = self.e("ishelf_deck")
		hx = L / 2
		for x in (-hx, hx - 0.04):
			for z in (-D, -0.04):
				mb.box((x, 0, z), (x + 0.04, H, z + 0.04), ENV, {"*": upr})
		for y in levels + (H - 0.04,):
			mb.box((-hx, y - 0.02, -D), (hx, y, 0), ENV, {"py": deck, "ny": deck, "px": beam, "nx": beam}, skip=("pz", "nz"))
			for z in (-D, -0.04):
				mb.box((-hx, y - 0.06, z), (hx, y, z + 0.04), ENV, {"*": beam})
		# cross brace on the back
		mb.tube([(-hx + 0.02, 0.1, -D + 0.02), (hx - 0.02, H - 0.1, -D + 0.02)], 0.008, ENV, self.ep("frame"))
		for li, y in enumerate(levels):
			if li == 0 and not floor_boxes:
				continue
			clear = (levels[li + 1] - 0.08 - y) if li + 1 < len(levels) else (H - 0.1 - y)
			x = -hx + 0.06
			while x < hx - 0.1:
				w = float(rng.uniform(0.28, 0.55))
				if x + w > hx - 0.06:
					break
				if rng.random() < fill * 0.35 and li > 0 and clear > 0.32:
					lab = "cereal_%d" % int(rng.integers(0, 8)) if rng.random() < 0.6 else "snackbox_%d" % int(rng.integers(0, 6))
					bw, bh = (0.2, 0.3) if lab.startswith("cereal") else (0.15, 0.21)
					n = max(1, int(w / (bw + 0.01)))
					for q in range(n):
						with mb.at(T(x + q * (bw + 0.01) + bw / 2, y, -0.04 - rng.uniform(0, 0.03))):
							self.item_box(mb, bw, bh, 0.42, lab)
					x += n * (bw + 0.01) + float(rng.uniform(0.03, 0.1))
					continue
				if rng.random() < fill:
					h = float(min(clear, rng.uniform(0.18, 0.45)))
					d = float(rng.uniform(0.32, D - 0.06))
					r = rng.random()
					lab = ("box_stock_%d" % int(rng.integers(0, 4))) if r < 0.45 else ("box_olive" if r < 0.55 else "box_kraft_%d" % int(rng.integers(0, 3)))
					with mb.at(T(x + w / 2, y, -0.03 - rng.uniform(0, 0.06)), RY(rng.uniform(-6, 6))):
						mb.box((-w / 2, 0, -d), (w / 2, h, 0), ENV, {"*": self.e(lab)}, skip=("ny", "nz"))
						if h < clear - 0.22 and rng.random() < 0.45:
							h2 = float(min(clear - h, rng.uniform(0.15, 0.3)))
							w2 = w * rng.uniform(0.6, 0.95)
							mb.box((-w2 / 2, h, -d * 0.9), (w2 / 2, h + h2, -0.02), ENV, {"*": self.e("box_kraft_%d" % int(rng.integers(0, 3)))}, skip=("ny", "nz"))
				x += w + float(rng.uniform(0.02, 0.08))
		return [((-hx, 0, -D), (hx, H, 0))]

	def floor_box(self, mb, rng, w, h, d, label=None, open_top=False):
		"""Cardboard box standing on the floor, footprint centred. open_top: flaps folded out, dark inside."""
		lab = label or "box_kraft_%d" % int(rng.integers(0, 3))
		mb.box((-w / 2, 0, -d / 2), (w / 2, h, d / 2), ENV, {"*": self.e(lab)}, skip=("ny",) + (("py",) if open_top else ()))
		if open_top:
			fl = self.e("box_kraft_%d" % int(rng.integers(0, 3)))
			mb.box((-w / 2 + 0.01, h * 0.55, -d / 2 + 0.01), (w / 2 - 0.01, h * 0.57, d / 2 - 0.01), ENV, {"py": self.ep("plenum")})
			for sz in (-1, 1):
				pts = [(-w / 2, h, sz * d / 2), (w / 2, h, sz * d / 2), (w / 2, h + 0.12, sz * d * 0.8), (-w / 2, h + 0.12, sz * d * 0.8)]
				mb.poly(pts, [(fl[0], fl[1]), (fl[2], fl[1]), (fl[2], fl[3]), (fl[0], fl[3])], ENV)
				mb.poly(pts[::-1], [(fl[0], fl[3]), (fl[2], fl[3]), (fl[2], fl[1]), (fl[0], fl[1])], ENV)
		return [((-w / 2, 0, -d / 2), (w / 2, h, d / 2))]

	def newspaper(self, mb, w=0.45, d=0.32):
		r = self.e("newspaper")
		mb.quad((-w / 2, 0.004, d / 2), (w / 2, 0.004, d / 2), (w / 2, 0.004, -d / 2), (-w / 2, 0.004, -d / 2), r, ENV)

	def scrap(self, mb, rng, s=0.12):
		"""Crumpled paper / wrapper: a tiny pyramid on the floor."""
		r = self.e(str(rng.choice(["paper_scrap", "debris_wrap", "debris_can", "paper_scrap"])))
		h = s * float(rng.uniform(0.3, 0.6))
		a, b, c, d = (-s / 2, 0.002, s / 2), (s / 2, 0.002, s / 2), (s / 2, 0.002, -s / 2), (-s / 2, 0.002, -s / 2)
		apex = (float(rng.uniform(-s / 4, s / 4)), h, float(rng.uniform(-s / 4, s / 4)))
		uv = [(r[0], r[1]), (r[2], r[1]), ((r[0] + r[2]) / 2, r[3])]
		for p, q in ((a, b), (b, c), (c, d), (d, a)):
			mb.poly([p, q, apex], uv, ENV)
