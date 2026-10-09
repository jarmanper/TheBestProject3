"""Pixel-art painting for the store textures (pure numpy, no bpy).

Every texture is painted into a Canvas (float RGBA, sRGB values 0..1, row 0 = top).
Atlases hand out named rectangles; geo.py turns them into UVs.
"""
import numpy as np

# ---------------------------------------------------------------- palette
CHARCOAL = "#171B1A"
ORANGE = "#E87932"
OLIVE = "#626D58"
CREAM = "#D8D3A8"
RED = "#B93B32"
CONCRETE = "#444A48"


def C(h, a=1.0):
	h = h.lstrip("#")
	return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)] + [a], np.float32)


def mix(c1, c2, t):
	a, b = C(c1) if isinstance(c1, str) else c1, C(c2) if isinstance(c2, str) else c2
	return (a * (1 - t) + b * t).astype(np.float32)


def scale(c, f):
	c = C(c) if isinstance(c, str) else c.copy()
	c[:3] = np.clip(c[:3] * f, 0, 1)
	return c


def lum(c):
	c = C(c) if isinstance(c, str) else c
	return float(0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2])


# ---------------------------------------------------------------- fonts
_F5 = {
	"A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
	"C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
	"D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
	"E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
	"F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
	"G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".####"],
	"H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"I": [".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."],
	"J": ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."],
	"K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
	"L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
	"M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
	"N": ["#...#", "#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#"],
	"O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
	"Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
	"R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
	"S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
	"T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
	"U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
	"W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "#.#.#", ".#.#."],
	"X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
	"Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
	"Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
	"0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
	"1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
	"2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
	"3": ["####.", "....#", "....#", ".###.", "....#", "....#", "####."],
	"4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
	"5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
	"6": [".###.", "#....", "#....", "####.", "#...#", "#...#", ".###."],
	"7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
	"8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
	"9": [".###.", "#...#", "#...#", ".####", "....#", "....#", ".###."],
	" ": ["....."] * 7,
	"-": [".....", ".....", ".....", "#####", ".....", ".....", "....."],
	".": [".....", ".....", ".....", ".....", ".....", ".##..", ".##.."],
	"!": ["..#..", "..#..", "..#..", "..#..", "..#..", ".....", "..#.."],
	"&": [".##..", "#..#.", "#.#..", ".#...", "#.#.#", "#..#.", ".##.#"],
	"'": ["..#..", "..#..", ".....", ".....", ".....", ".....", "....."],
	"/": ["....#", "...#.", "...#.", "..#..", ".#...", ".#...", "#...."],
	"$": ["..#..", ".####", "#.#..", ".###.", "..#.#", "####.", "..#.."],
	"%": ["##..#", "##..#", "...#.", "..#..", ".#...", "#..##", "#..##"],
	":": [".....", ".##..", ".##..", ".....", ".##..", ".##..", "....."],
}
_F3 = {
	"A": [".#.", "#.#", "###", "#.#", "#.#"], "B": ["##.", "#.#", "##.", "#.#", "##."],
	"C": [".##", "#..", "#..", "#..", ".##"], "D": ["##.", "#.#", "#.#", "#.#", "##."],
	"E": ["###", "#..", "##.", "#..", "###"], "F": ["###", "#..", "##.", "#..", "#.."],
	"G": [".##", "#..", "#.#", "#.#", ".##"], "H": ["#.#", "#.#", "###", "#.#", "#.#"],
	"I": ["###", ".#.", ".#.", ".#.", "###"], "J": ["..#", "..#", "..#", "#.#", ".#."],
	"K": ["#.#", "#.#", "##.", "#.#", "#.#"], "L": ["#..", "#..", "#..", "#..", "###"],
	"M": ["#.#", "###", "###", "#.#", "#.#"], "N": ["##.", "#.#", "#.#", "#.#", "#.#"],
	"O": [".#.", "#.#", "#.#", "#.#", ".#."], "P": ["##.", "#.#", "##.", "#..", "#.."],
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
	" ": ["..."] * 5, "-": ["...", "...", "###", "...", "..."], ".": ["...", "...", "...", "...", ".#."],
	"%": ["#.#", "..#", ".#.", "#..", "#.#"], "$": [".##", "##.", ".#.", ".##", "##."],
	"!": [".#.", ".#.", ".#.", "...", ".#."], "/": ["..#", "..#", ".#.", "#..", "#.."],
}
FONTS = {5: (_F5, 5, 7), 3: (_F3, 3, 5)}


def text_width(s, font=5, scale=1):
	_, gw, _ = FONTS[font]
	return (len(s) * (gw + 1) - 1) * scale


# ---------------------------------------------------------------- canvas
class Canvas:
	def __init__(self, w, h, bg="#000000"):
		self.w, self.h = w, h
		self.a = np.zeros((h, w, 4), np.float32)
		self.a[:] = C(bg) if isinstance(bg, str) else bg

	def _c(self, c):
		return C(c) if isinstance(c, str) else np.asarray(c, np.float32)

	def rect(self, x, y, w, h, c):
		x0, y0, x1, y1 = max(0, x), max(0, y), min(self.w, x + w), min(self.h, y + h)
		if x1 > x0 and y1 > y0:
			self.a[y0:y1, x0:x1] = self._c(c)

	def px(self, x, y, c):
		if 0 <= x < self.w and 0 <= y < self.h:
			self.a[y, x] = self._c(c)

	def outline(self, x, y, w, h, c):
		self.rect(x, y, w, 1, c)
		self.rect(x, y + h - 1, w, 1, c)
		self.rect(x, y, 1, h, c)
		self.rect(x + w - 1, y, 1, h, c)

	def shade(self, x, y, w, h, f):
		x0, y0, x1, y1 = max(0, x), max(0, y), min(self.w, x + w), min(self.h, y + h)
		self.a[y0:y1, x0:x1, :3] = np.clip(self.a[y0:y1, x0:x1, :3] * f, 0, 1)

	def noise(self, x, y, w, h, amt, rng, mono=True):
		x0, y0, x1, y1 = max(0, x), max(0, y), min(self.w, x + w), min(self.h, y + h)
		shape = (y1 - y0, x1 - x0, 1 if mono else 3)
		n = rng.uniform(-amt, amt, shape).astype(np.float32)
		self.a[y0:y1, x0:x1, :3] = np.clip(self.a[y0:y1, x0:x1, :3] + n, 0, 1)

	def vgrad(self, x, y, w, h, f_top, f_bot):
		for i in range(h):
			t = i / max(1, h - 1)
			self.shade(x, y + i, w, 1, f_top * (1 - t) + f_bot * t)

	def ellipse(self, cx, cy, rx, ry, c):
		yy, xx = np.mgrid[0:self.h, 0:self.w]
		m = ((xx + 0.5 - cx) / max(rx, 0.01)) ** 2 + ((yy + 0.5 - cy) / max(ry, 0.01)) ** 2 <= 1.0
		self.a[m] = self._c(c)

	def blot(self, cx, cy, r, f, rng, clip=None):
		"""Darken an irregular blob (grime). clip = (x, y, w, h) to stay inside."""
		yy, xx = np.mgrid[0:self.h, 0:self.w]
		d = np.sqrt((xx + 0.5 - cx) ** 2 + (yy + 0.5 - cy) ** 2)
		jitter = rng.uniform(0.6, 1.0, d.shape)
		m = d < r * jitter
		if clip:
			x, y, w, h = clip
			cm = np.zeros_like(m)
			cm[max(0, y):y + h, max(0, x):x + w] = True
			m &= cm
		self.a[m, :3] = np.clip(self.a[m, :3] * f, 0, 1)

	def text(self, x, y, s, c, font=5, scale=1):
		glyphs, gw, gh = FONTS[font]
		col = self._c(c)
		for i, ch in enumerate(s.upper()):
			g = glyphs.get(ch, glyphs.get(" "))
			for gy, row in enumerate(g):
				for gx, bit in enumerate(row):
					if bit == "#":
						self.rect(x + (i * (gw + 1) + gx) * scale, y + gy * scale, scale, scale, col)

	def text_center(self, x, y, w, s, c, font=5, scale=1):
		self.text(x + (w - text_width(s, font, scale)) // 2, y, s, c, font, scale)

	def blit(self, other, x, y):
		self.a[y:y + other.h, x:x + other.w] = other.a

	def grade(self, x, y, w, h, sat=0.8, val=0.8):
		"""Desaturate towards luminance and darken (muted night-time product colours)."""
		r = self.a[y:y + h, x:x + w, :3]
		l = (0.3 * r[..., 0] + 0.59 * r[..., 1] + 0.11 * r[..., 2])[..., None]
		self.a[y:y + h, x:x + w, :3] = np.clip((l + (r - l) * sat) * val, 0, 1)


class Atlas:
	"""A canvas with a simple row packer. Regions are (x, y, w, h) in pixels, top-left origin."""

	def __init__(self, w, h, bg="#000000"):
		self.c = Canvas(w, h, bg)
		self.w, self.h = w, h
		self.regions = {}
		self._x = self._y = self._row = 0

	def alloc(self, name, w, h):
		if self._x + w > self.w:
			self._x, self._y, self._row = 0, self._y + self._row, 0
		if self._y + h > self.h:
			raise RuntimeError("atlas full allocating %s" % name)
		r = (self._x, self._y, w, h)
		self.regions[name] = r
		self._x += w
		self._row = max(self._row, h)
		return r

	def newrow(self):
		self._x, self._y, self._row = 0, self._y + self._row, 0

	def uv(self, name, sub=None):
		"""(u0, v0, u1, v1) with v up. sub = fractions (fx0, fy0, fx1, fy1) of the region, top-left origin."""
		x, y, w, h = self.regions[name]
		fx0, fy0, fx1, fy1 = sub if sub else (0, 0, 1, 1)
		e = 0.02
		px0, px1 = x + fx0 * w + e, x + fx1 * w - e
		py0, py1 = y + fy0 * h + e, y + fy1 * h - e
		return (px0 / self.w, 1 - py1 / self.h, px1 / self.w, 1 - py0 / self.h)

	def uvpx(self, name, fx=0.5, fy=0.5):
		"""Degenerate rect at one point of the region (a flat colour)."""
		x, y, w, h = self.regions[name]
		u, v = (x + fx * w) / self.w, 1 - (y + fy * h) / self.h
		return (u, v, u, v)


def save_rgba(canvas):
	"""Return a flat float array bottom-up for bpy image.pixels."""
	return np.flipud(canvas.a).ravel()


# ================================================================ products atlas
CEREAL = [("#B83A2E", "#E8C040", "OATS"), ("#E0B030", "#A02820", "CORN"), ("#2F5FA8", "#E8E0C8", "BRAN"),
	("#3C8A3E", "#F0E070", "CRISP"), ("#D86A20", "#5A2A10", "PUFFS"), ("#6E3A86", "#F0C040", "LOOPS"),
	("#8A5A30", "#F0E0B0", "HONEY"), ("#D8D0B8", "#C03028", "FLAKE")]
SNACKBOX = [("#C83828", "#F0D060", "CRAK"), ("#2E5A9A", "#F0F0E0", "WAFR"), ("#E2A23A", "#6A3010", "COOK"),
	("#3E7A3A", "#F0E8C0", "THIN"), ("#7A2E5A", "#F0C0E0", "FIGS"), ("#E8E0C8", "#B02828", "GRAH")]
SNACKBAG = [("#D8B020", "#C02820", "CHIP"), ("#C02828", "#F0D040", "HOT"), ("#2A4E9A", "#F0E0A0", "SALT"),
	("#2E7A3A", "#F0F0D0", "SOUR"), ("#6A2A8A", "#F0D070", "BBQ"), ("#E07020", "#FFF0C0", "CHZ")]
BOTTLE = [("#2A140C", "#C02828", "COLA"), ("#E07A1E", "#2A5AA0", "ORNG"), ("#6FB83A", "#F0F0E0", "LIME"),
	("#9CC0D0", "#2E6AB0", "AQUA"), ("#5A2272", "#F0D060", "GRP"), ("#A82424", "#F0F0F0", "CHRY")]
CANS = [("#B8302A", "#E8E4D8", "SOUP"), ("#2E5A9A", "#E0D8C0", "BEAN"), ("#3E8A3A", "#F0E8B0", "PEAS"),
	("#E0B830", "#3A6A2A", "CORN"), ("#D86A28", "#F0E8D8", "YAMS"), ("#7A3A28", "#E8D8B0", "CHLI"),
	("#4A6A8A", "#F0F0F0", "TUNA"), ("#8A2A4A", "#F0E0D0", "BEET")]
JARS = [("#A8281E", "#E8DEB8", "SAUC"), ("#6A8A2A", "#E8E0C0", "PKLE"), ("#D8A020", "#5A3A10", "MUST"),
	("#5A3018", "#E0C890", "JAM")]
BAGGED = [("#E8E4D8", "#B03028", "FLOUR"), ("#F0EEE6", "#2E5AA0", "SUGAR"), ("#E8D8B0", "#7A4A20", "RICE")]
PASTA = [("#2A4E9A", "#F0E070", "PASTA"), ("#B83A2E", "#F0E8C8", "MACC"), ("#1E6A4A", "#F0E0A0", "SPAG")]
FROZEN = [("#B82E28", "#F0C040", "PIZZA"), ("#2E4E9A", "#F0F0F0", "MEALS"), ("#2E7A4A", "#F0F0E0", "PEAS"),
	("#E0E0E8", "#5A3A8A", "CREAM")]
MILK = [("#E8E8E0", "#C02828", "MILK"), ("#E8E8E0", "#2A5AB0", "2%"), ("#E8E8E0", "#3A8A3A", "SKIM")]
JUICE = [("#E89020", "#3A8A2A", "OJ"), ("#C83040", "#F0E0E0", "CRAN"), ("#E8D840", "#3A7A2A", "LEMN")]
PLACARDS = ["CEREAL", "SNACKS", "DRINKS", "CANNED", "SOUP", "BAKING", "PASTA", "CHIPS", "SODA", "JUICE",
	"COOKIES", "CANDY", "DAIRY", "FROZEN", "GOODS"]


def _label_text(c, x, y, w, word, col):
	if text_width(word, 3) <= w - 2:
		c.text_center(x, y, w, word, col, font=3)
	else:
		c.text_center(x, y, w, word[: max(1, (w - 1) // 4)], col, font=3)


def build_products_atlas(seed=7):
	rng = np.random.default_rng(seed)
	A = Atlas(256, 256, "#101210")
	c = A.c
	dark = C("#1c1c1a")
	for i, (base, acc, word) in enumerate(CEREAL):
		x, y, w, h = A.alloc("cereal_%d" % i, 24, 32)
		c.rect(x, y, w, h, base)
		c.rect(x, y + 2, w, 8, acc)
		_label_text(c, x, y + 3, w, word, base if lum(acc) > 0.5 else "#F0F0E8")
		c.ellipse(x + 12, y + 21, 9, 5, "#E8E2D0")
		c.rect(x + 3, y + 21, 18, 5, "#E8E2D0")
		for _ in range(14):
			c.px(x + int(rng.integers(5, 19)), y + int(rng.integers(17, 22)), rng.choice(["#C89040", "#A86A28", "#E0B060", "#F0D080"]))
		c.rect(x, y + 28, w, 2, acc)
		c.shade(x + 3, y + 25, 18, 2, 0.8)
		c.outline(x, y, w, h, scale(base, 0.55))
		c.noise(x, y, w, h, 0.035, rng)
	for i, (base, acc, word) in enumerate(SNACKBOX):
		x, y, w, h = A.alloc("snackbox_%d" % i, 16, 20)
		c.rect(x, y, w, h, base)
		c.rect(x, y + 9, w, 3, acc)
		_label_text(c, x, y + 2, w, word, acc)
		for k in range(3):
			c.ellipse(x + 4 + k * 4, y + 15.5, 2, 2, "#B07838")
		c.outline(x, y, w, h, scale(base, 0.55))
		c.noise(x, y, w, h, 0.035, rng)
	for i, (base, acc, word) in enumerate(SNACKBAG):
		x, y, w, h = A.alloc("snackbag_%d" % i, 16, 24)
		c.rect(x, y, w, h, base)
		c.vgrad(x, y, w, h, 1.15, 0.8)
		c.rect(x, y, w, 2, scale(base, 1.3))
		c.rect(x, y + h - 2, w, 2, scale(base, 1.3))
		for k in range(0, w, 2):
			c.px(x + k, y + 1, scale(base, 0.6))
			c.px(x + k + 1, y + h - 2, scale(base, 0.6))
		_label_text(c, x, y + 4, w, word, acc)
		c.ellipse(x + 8, y + 15, 5, 4, "#E0B040")
		for _ in range(6):
			c.px(x + int(rng.integers(4, 12)), y + int(rng.integers(12, 18)), "#C08020")
		c.noise(x, y, w, h, 0.04, rng)
	for i, (liq, acc, word) in enumerate(BOTTLE):
		x, y, w, h = A.alloc("bottle_%d" % i, 16, 24)
		c.rect(x, y, w, h, liq)
		c.rect(x, y + 8, w, 8, acc)
		_label_text(c, x, y + 9, w, word, "#F0F0E8" if lum(acc) < 0.5 else "#202020")
		c.rect(x + 3, y, 1, h, scale(liq, 1.6))
		c.shade(x, y + 18, w, 6, 0.8)
		c.noise(x, y, w, h, 0.03, rng)
	for i, col in enumerate(["#C02828", "#2A5AB0", "#E8E8E0", "#3A8A3A", "#202020", "#E0B030"]):
		x, y, w, h = A.alloc("cap_%d" % i, 4, 4)
		c.rect(x, y, w, h, col)
	for i, (base, acc, word) in enumerate(CANS):
		x, y, w, h = A.alloc("can_%d" % i, 16, 12)
		c.rect(x, y, w, 6, base)
		c.rect(x, y + 6, w, 6, acc)
		_label_text(c, x, y + 6, w, word, base)
		c.rect(x + 6, y + 2, 4, 2, "#D8B040")
		c.rect(x, y, w, 1, "#9A9C98")
		c.rect(x, y + h - 1, w, 1, "#7A7C78")
		c.noise(x, y, w, h, 0.03, rng)
	x, y, w, h = A.alloc("can_top", 4, 4)
	c.rect(x, y, w, h, "#A8AAA6")
	for i, (base, acc, word) in enumerate(JARS):
		x, y, w, h = A.alloc("jar_%d" % i, 12, 16)
		c.rect(x, y, w, h, base)
		c.rect(x, y, w, 3, "#C8A848")
		c.rect(x, y + 6, w, 6, acc)
		_label_text(c, x, y + 7, w, word, base)
		c.rect(x + 2, y + 3, 1, 12, scale(base, 1.5))
		c.noise(x, y, w, h, 0.03, rng)
	A.newrow()
	for i, (base, acc, word) in enumerate(BAGGED):
		x, y, w, h = A.alloc("bagged_%d" % i, 16, 24)
		c.rect(x, y, w, h, base)
		c.rect(x, y + 6, w, 9, acc)
		_label_text(c, x, y + 8, w, word, base)
		c.rect(x, y, w, 2, scale(base, 0.85))
		c.noise(x, y, w, h, 0.03, rng)
	for i, (base, acc, word) in enumerate(PASTA):
		x, y, w, h = A.alloc("pasta_%d" % i, 16, 20)
		c.rect(x, y, w, h, base)
		_label_text(c, x, y + 2, w, word, acc)
		c.rect(x + 3, y + 9, 10, 7, "#E8D070")
		c.outline(x + 3, y + 9, 10, 7, "#B89838")
		c.outline(x, y, w, h, scale(base, 0.55))
		c.noise(x, y, w, h, 0.03, rng)
	for i, (base, acc, word) in enumerate(FROZEN):
		x, y, w, h = A.alloc("frozen_%d" % i, 24, 16)
		c.rect(x, y, w, h, base)
		_label_text(c, x, y + 1, w, word, acc)
		c.ellipse(x + 12, y + 11, 7, 3.5, acc)
		for _ in range(5):
			c.px(x + int(rng.integers(7, 17)), y + int(rng.integers(9, 13)), scale(base, 0.8))
		c.outline(x, y, w, h, scale(base, 0.6))
		c.noise(x, y, w, h, 0.03, rng)
	for i, (base, acc, word) in enumerate(MILK):
		x, y, w, h = A.alloc("milk_%d" % i, 16, 20)
		c.rect(x, y, w, h, base)
		c.rect(x, y + 7, w, 7, acc)
		_label_text(c, x, y + 8, w, word, base)
		c.vgrad(x, y, w, h, 1.0, 0.85)
		c.noise(x, y, w, h, 0.025, rng)
	for i, (base, acc, word) in enumerate(JUICE):
		x, y, w, h = A.alloc("juice_%d" % i, 12, 20)
		c.rect(x, y, w, h, base)
		c.rect(x, y, w, 5, "#E8E8E0")
		c.ellipse(x + 6, y + 12, 4, 4, acc)
		_label_text(c, x, y + 6, w, word, "#F8F8F0")
		c.noise(x, y, w, h, 0.03, rng)
	for i, (kraft, ink) in enumerate([("#A47A48", "#2A2018"), ("#B08A58", "#7A2A20"), ("#96703E", "#1E3A6A")]):
		x, y, w, h = A.alloc("case_%d" % i, 32, 16)
		c.rect(x, y, w, h, kraft)
		c.rect(x, y + 6, w, 3, "#C8A878")
		c.rect(x + 4, y + 11, 10, 3, ink)
		c.text(x + 18, y + 10, "12", ink, font=3)
		c.outline(x, y, w, h, scale(kraft, 0.65))
		c.noise(x, y, w, h, 0.04, rng)
	A.newrow()
	c.grade(0, 0, A.w, A._y, sat=0.78, val=0.8)
	# placards: white board, black pixel text, dark border
	for name in PLACARDS:
		x, y, w, h = A.alloc("pl_" + name, 48, 11)
		c.rect(x, y, w, h, "#E6E4DA")
		c.outline(x, y, w, h, "#2A2A28")
		c.text_center(x, y + 2, w, name, "#151515")
		c.noise(x + 1, y + 1, w - 2, h - 2, 0.02, rng)
	A.newrow()
	# shelf metal
	x, y, w, h = A.alloc("shelf_top", 8, 8)
	c.rect(x, y, w, h, "#7E8278")
	c.noise(x, y, w, h, 0.03, rng)
	x, y, w, h = A.alloc("shelf_lip", 64, 6)
	c.rect(x, y, w, h, "#A6A89E")
	c.rect(x, y, w, 1, "#C8C9C0")
	c.rect(x, y + 5, w, 1, "#4A4C46")
	for k in range(2, w - 3, 8):
		col = "#E8E6D8" if rng.random() > 0.2 else "#E8C838"
		c.rect(x + k, y + 1, 4, 3, col)
		c.px(x + k + 1, y + 2, "#555550")
	x, y, w, h = A.alloc("upright", 8, 8)
	c.rect(x, y, w, h, "#3C403A")
	for k in range(1, 8, 3):
		c.px(x + 3, y + k, "#1A1C18")
	x, y, w, h = A.alloc("pegboard", 32, 32)
	c.rect(x, y, w, h, "#3E423A")
	c.noise(x, y, w, h, 0.025, rng)
	for py in range(2, 32, 4):
		for pxx in range(2, 32, 4):
			c.px(x + pxx, y + py, "#1C1E1A")
	x, y, w, h = A.alloc("kick", 16, 8)
	c.rect(x, y, w, h, "#2C2F2A")
	c.rect(x, y, w, 1, "#4E524A")
	c.noise(x, y, w, h, 0.02, rng)
	x, y, w, h = A.alloc("endpanel", 16, 32)
	c.rect(x, y, w, h, OLIVE)
	c.vgrad(x, y, w, h, 1.1, 0.75)
	c.outline(x, y, w, h, "#3E4636")
	c.noise(x, y, w, h, 0.03, rng)
	x, y, w, h = A.alloc("fill_dark", 4, 4)
	c.rect(x, y, w, h, "#121412")
	x, y, w, h = A.alloc("kraft_top", 16, 16)
	c.rect(x, y, w, h, "#A47A48")
	c.rect(x, y + 7, w, 2, "#C8A878")
	c.noise(x, y, w, h, 0.04, rng)
	return A


# ================================================================ environment atlas
def _board(c, x, y, w, h, bg, border):
	c.rect(x, y, w, h, bg)
	c.outline(x, y, w, h, border)


def build_env_atlas(seed=11):
	rng = np.random.default_rng(seed)
	A = Atlas(256, 256, "#000000")
	c = A.c
	sign_bg, sign_fg, sign_border = "#1E2321", CREAM, "#3E4440"
	# hanging aisle signs: "AISLE" over a big number, like references 1/2
	for n in range(1, 5):
		x, y, w, h = A.alloc("sign_aisle_%d" % n, 40, 32)
		_board(c, x, y, w, h, sign_bg, sign_border)
		c.text_center(x, y + 3, w, "AISLE", sign_fg)
		c.text_center(x, y + 13, w, str(n), sign_fg, scale=2)
		c.noise(x + 1, y + 1, w - 2, h - 2, 0.02, rng)
	for name, label, w in [("sign_frozen", "FROZEN", 48), ("sign_produce", "PRODUCE", 52),
			("sign_employees", "EMPLOYEES ONLY", 92), ("sign_service", "CUSTOMER SERVICE", 104)]:
		x, y, w, h = A.alloc(name, w, 13)
		_board(c, x, y, w, h, sign_bg, sign_border)
		c.text_center(x, y + 3, w, label, sign_fg)
		c.noise(x + 1, y + 1, w - 2, h - 2, 0.02, rng)
	# DAIRY: light board with dark text, as seen at the end of aisle 4 in references 1/2
	x, y, w, h = A.alloc("sign_dairy", 40, 13)
	_board(c, x, y, w, h, "#D6D4CA", "#5A5A54")
	c.text_center(x, y + 3, w, "DAIRY", "#1A1A18")
	x, y, w, h = A.alloc("sign_exit", 30, 13)
	_board(c, x, y, w, h, "#0E3A1A", "#1E5A2A")
	c.text_center(x, y + 3, w, "EXIT", "#9CFFA0")
	for name, label, w in [("sign_storage", "STORAGE", 46), ("sign_break", "BREAK ROOM", 64),
			("sign_office", "OFFICE", 40), ("sign_janitor", "JANITOR", 46)]:
		x, y, w, h = A.alloc(name, w, 11)
		_board(c, x, y, w, h, "#C8C6BA", "#4A4A44")
		c.text_center(x, y + 2, w, label, "#1A1A18")
	for n in range(1, 4):
		x, y, w, h = A.alloc("sign_lane_%d" % n, 11, 11)
		_board(c, x, y, w, h, sign_bg, sign_border)
		c.text_center(x, y + 2, w, str(n), "#E8C850")
	x, y, w, h = A.alloc("sign_closed", 40, 11)
	_board(c, x, y, w, h, RED, "#E8E0D0")
	c.text_center(x, y + 2, w, "CLOSED", "#F4F0E8")
	A.newrow()
	# checkout / counters
	x, y, w, h = A.alloc("counter_body", 16, 16)
	c.rect(x, y, w, h, "#C4BE98")
	c.rect(x + 7, y, 1, h, "#9C9678")
	c.noise(x, y, w, h, 0.025, rng)
	x, y, w, h = A.alloc("counter_top", 16, 16)
	c.rect(x, y, w, h, "#8E8A7E")
	c.noise(x, y, w, h, 0.05, rng)
	x, y, w, h = A.alloc("counter_kick", 16, 4)
	c.rect(x, y, w, h, "#1E1F1E")
	x, y, w, h = A.alloc("belt", 32, 8)
	c.rect(x, y, w, h, "#1A1B1A")
	for k in range(0, w, 4):
		c.rect(x + k, y, 1, h, "#2C2E2C")
	x, y, w, h = A.alloc("steel", 8, 8)
	c.rect(x, y, w, h, "#8E9290")
	c.noise(x, y, w, h, 0.04, rng)
	x, y, w, h = A.alloc("register", 16, 16)
	c.rect(x, y, w, h, "#2A2C2C")
	for ky in range(3):
		for kx in range(4):
			c.rect(x + 2 + kx * 3, y + 7 + ky * 3, 2, 2, "#8A8C88" if (kx + ky) % 3 else "#B84030")
	c.rect(x + 2, y + 2, 12, 3, "#3A3C3A")
	x, y, w, h = A.alloc("screen", 16, 12)
	c.rect(x, y, w, h, "#16302A")
	c.text(x + 2, y + 2, "0.00", "#4ED8A0", font=3)
	c.rect(x + 2, y + 8, 12, 1, "#2E6A50")
	x, y, w, h = A.alloc("scanner", 8, 8)
	c.rect(x, y, w, h, "#121616")
	c.rect(x, y + 4, w, 1, "#8A2A20")
	A.newrow()
	# coolers / freezers
	x, y, w, h = A.alloc("cooler_frame", 8, 8)
	c.rect(x, y, w, h, "#2A2C2B")
	c.noise(x, y, w, h, 0.02, rng)
	x, y, w, h = A.alloc("cooler_inner", 8, 8)
	c.rect(x, y, w, h, "#9EA4A2")
	x, y, w, h = A.alloc("cooler_grille", 16, 8)
	c.rect(x, y, w, h, "#1A1C1B")
	for k in range(1, h, 2):
		c.rect(x, y + k, w, 1, "#3A3D3B")
	x, y, w, h = A.alloc("cooler_header", 32, 8)
	c.rect(x, y, w, h, "#262A28")
	c.rect(x, y + h - 1, w, 1, "#4A4E4C")
	x, y, w, h = A.alloc("frost", 8, 8)
	c.rect(x, y, w, h, "#9DB8C4")
	c.noise(x, y, w, h, 0.04, rng)
	x, y, w, h = A.alloc("wire_shelf", 16, 4)
	c.rect(x, y, w, h, "#7A7E7C")
	for k in range(0, w, 2):
		c.px(x + k, y + 1, "#3A3C3A")
		c.px(x + k, y + 2, "#3A3C3A")
	# industrial shelving (reference 3: grey slotted uprights, grey beams, dark decks)
	x, y, w, h = A.alloc("ishelf_upright", 8, 32)
	c.rect(x, y, w, h, "#4A504C")
	for k in range(1, h, 3):
		c.rect(x + 3, y + k, 2, 1, "#161816")
	c.rect(x, y, 1, h, "#6A706C")
	x, y, w, h = A.alloc("ishelf_beam", 16, 4)
	c.rect(x, y, w, h, "#454A47")
	c.rect(x, y, w, 1, "#6E7470")
	x, y, w, h = A.alloc("ishelf_deck", 16, 16)
	c.rect(x, y, w, h, "#4A4C46")
	c.noise(x, y, w, h, 0.05, rng)
	A.newrow()
	# storage boxes
	for i, kraft in enumerate(["#9C7444", "#B08654", "#8A6A40"]):
		x, y, w, h = A.alloc("box_kraft_%d" % i, 24, 24)
		c.rect(x, y, w, h, kraft)
		c.rect(x + 10, y, 4, h, "#C2A070")
		c.rect(x, y + 11, w, 1, scale(kraft, 0.75))
		c.outline(x, y, w, h, scale(kraft, 0.6))
		if i == 1:
			c.rect(x + 2, y + 15, 7, 1, "#2A2018")
			c.rect(x + 2, y + 17, 5, 1, "#2A2018")
			c.rect(x + 15, y + 15, 6, 4, "#3A2A1A")
		c.noise(x, y, w, h, 0.045, rng)
	for i, (paper, band, ink) in enumerate([("#D8D2BC", "#B8302A", "#F0E8D0"), ("#D0CCB8", "#2E5A9A", "#F0F0E0"),
			("#DCD6C0", "#E0A030", "#5A2A10"), ("#CFC8B0", "#3A7A3A", "#F0F0E0")]):
		x, y, w, h = A.alloc("box_stock_%d" % i, 24, 24)
		c.rect(x, y, w, h, scale(paper, 0.85))
		c.rect(x + 3, y + 7, 18, 9, band)
		c.text_center(x, y + 9, w, ["LUCKY", "BRAND", "TASTY", "FRESH"][i][:4], ink, font=3)
		c.rect(x + 3, y + 18, 8, 2, scale(band, 0.8))
		c.rect(x + 13, y + 18, 8, 2, "#5A5850")
		c.outline(x, y, w, h, scale(paper, 0.55))
		c.noise(x, y, w, h, 0.035, rng)
	x, y, w, h = A.alloc("box_olive", 24, 24)
	c.rect(x, y, w, h, OLIVE)
	c.text_center(x, y + 9, w, "NO.4", "#2A3024", font=3)
	c.outline(x, y, w, h, "#3A4232")
	c.noise(x, y, w, h, 0.04, rng)
	x, y, w, h = A.alloc("newspaper", 32, 24)
	c.rect(x, y, w, h, "#C4C0B0")
	c.rect(x + 2, y + 2, 28, 3, "#2A2A28")
	for k in range(7, 22, 2):
		c.rect(x + 2, y + k, 13, 1, "#7A7870")
		c.rect(x + 17, y + k, 13 if k > 14 else 0, 1, "#7A7870")
	c.rect(x + 17, y + 7, 13, 7, "#5A5850")
	c.noise(x, y, w, h, 0.05, rng)
	x, y, w, h = A.alloc("paper_scrap", 8, 8)
	c.rect(x, y, w, h, "#D0CCC0")
	c.noise(x, y, w, h, 0.08, rng)
	x, y, w, h = A.alloc("pallet", 32, 8)
	c.rect(x, y, w, h, "#7E6040")
	for k in (0, 7, 15, 23, 31):
		c.rect(x + k, y, 1, h, "#3A2A1A")
	c.noise(x, y, w, h, 0.05, rng)
	A.newrow()
	# produce piles: tiled fruit dots
	for name, base, dot, dot2 in [("prod_apple", "#5A1414", "#B8281E", "#E04A30"), ("prod_orange", "#8A4210", "#E07A1E", "#F0A040"),
			("prod_lettuce", "#1E4A1A", "#4E9A32", "#8AC850"), ("prod_banana", "#7A6A14", "#E0C838", "#F0E070"),
			("prod_potato", "#4A3420", "#9A7448", "#B89060"), ("prod_tomato", "#6A1410", "#D0301E", "#F05838"),
			("prod_lime", "#1E3E12", "#5AA02A", "#8AD048"), ("prod_onion", "#5A4428", "#C8A070", "#9A4A6A")]:
		x, y, w, h = A.alloc(name, 16, 16)
		c.rect(x, y, w, h, base)
		for py in range(0, 16, 4):
			for pxx in range(0, 16, 4):
				ox = 2 if (py // 4) % 2 else 0
				cx, cy = x + (pxx + ox) % 16 + 2, y + py + 2
				c.rect(cx - 1, cy - 1, 3, 3, dot)
				c.px(cx - 1, cy - 1, dot2)
		c.noise(x, y, w, h, 0.05, rng)
		c.grade(x, y, w, h, sat=0.8, val=0.78)
	x, y, w, h = A.alloc("cooler_side", 16, 32)
	c.rect(x, y, w, h, "#6E7670")
	c.vgrad(x, y, w, h, 1.15, 0.7)
	c.outline(x, y, w, h, "#2A2C2B")
	c.noise(x, y, w, h, 0.02, rng)
	x, y, w, h = A.alloc("table_skirt", 16, 16)
	c.rect(x, y, w, h, "#2E4430")
	for k in range(0, w, 4):
		c.rect(x + k, y, 1, h, "#1E2E20")
	c.noise(x, y, w, h, 0.03, rng)
	x, y, w, h = A.alloc("wood", 16, 8)
	c.rect(x, y, w, h, "#6A5034")
	for k in range(1, h, 3):
		c.rect(x, y + k, w, 1, "#5A4028")
	c.noise(x, y, w, h, 0.04, rng)
	A.newrow()
	# breaker panel, emergency door, frames, fixtures
	x, y, w, h = A.alloc("breaker", 24, 32)
	c.rect(x, y, w, h, "#7A7E78")
	c.outline(x, y, w, h, "#4A4E48")
	c.rect(x + 2, y + 2, 20, 28, "#6E726C")
	for ry in range(4):
		for rx in range(2):
			c.rect(x + 4 + rx * 9, y + 4 + ry * 5, 7, 3, "#2A2C2A")
			c.rect(x + 5 + rx * 9, y + 5 + ry * 5, 2, 1, "#C8C8C0")
	c.rect(x + 7, y + 25, 10, 3, "#E0C030")
	c.text(x + 8, y + 25, "!", "#1A1A1A", font=3)
	c.noise(x, y, w, h, 0.03, rng)
	x, y, w, h = A.alloc("door_steel", 24, 48)
	c.rect(x, y, w, h, "#4E5450")
	c.outline(x, y, w, h, "#2E3230")
	c.rect(x + 1, y + 22, 22, 3, "#A8ACA8")
	c.rect(x + 1, y + 25, 22, 1, "#3A3E3A")
	c.rect(x + 3, y + 8, 18, 9, "#C8C4B8")
	c.text_center(x + 3, y + 9, 18, "EXIT", RED, font=3)
	c.text_center(x + 3, y + 14 - 1, 18, "ONLY", RED, font=3)
	c.vgrad(x, y, w, h, 1.0, 0.75)
	c.noise(x, y, w, h, 0.03, rng)
	for name, col in [("frame", "#3A3E3C"), ("alu", "#8E9494"), ("fixture_housing", "#B8B6AC"), ("fixture_inner", "#E2E0D4"),
			("cable", "#0C0C0C"), ("chain", "#5A5C58"), ("black", "#000000"), ("baseboard", "#262826"),
			("pipe", "#4C524E"), ("emerg_housing", "#C8C8C0"), ("handle", "#B8BCBA"), ("rubber", "#202220"),
			("plenum", "#08090A"), ("conduit", "#6A6E6A")]:
		x, y, w, h = A.alloc(name, 8, 8)
		c.rect(x, y, w, h, col)
		c.noise(x, y, w, h, 0.02, rng)
	x, y, w, h = A.alloc("vent", 16, 16)
	c.rect(x, y, w, h, "#8A8C86")
	for k in range(2, 14, 2):
		c.rect(x + 2, y + k, 12, 1, "#2A2C2A")
	c.outline(x, y, w, h, "#5A5C58")
	x, y, w, h = A.alloc("debris_wrap", 8, 8)
	c.rect(x, y, w, h, "#B83A2E")
	c.rect(x, y + 3, w, 2, "#E8C040")
	x, y, w, h = A.alloc("debris_can", 8, 8)
	c.rect(x, y, w, h, "#2E5A9A")
	c.rect(x, y + 3, w, 2, "#C8C8C8")
	x, y, w, h = A.alloc("cardboard_flat", 32, 16)
	c.rect(x, y, w, h, "#9A7448")
	c.rect(x + 15, y, 2, h, "#B89060")
	c.rect(x, y + 7, w, 1, "#7A5A34")
	c.noise(x, y, w, h, 0.05, rng)
	x, y, w, h = A.alloc("sticker_push", 16, 8)
	c.rect(x, y, w, h, "#D8D4C8")
	c.text_center(x, y + 1, w, "PUSH", "#2A2A28", font=3)
	return A


# ================================================================ tiling textures
def build_floor_tiles(seed=3):
	"""128x64 atlas of 32 floor tile variants, 16 px = one 0.5 m tile. Grout on top/left edges only."""
	rng = np.random.default_rng(seed)
	cv = Canvas(128, 64)
	rough = Canvas(128, 64)
	greys = [C("#454B49"), C("#3D4341"), C("#4A4F4C"), C("#393E3D")]
	grout = C("#1E2221")
	for j in range(4):
		for i in range(8):
			x, y = i * 16, j * 16
			k = j * 8 + i
			base = greys[k % 2] if k < 16 else greys[(k % 2) + 2]
			cv.rect(x, y, 16, 16, base)
			cv.noise(x, y, 16, 16, 0.018, rng)
			rough.rect(x, y, 16, 16, C("#3A3A3A"))
			rough.noise(x, y, 16, 16, 0.05, rng)
			kind = k % 8
			if kind == 2:   # grime blotch
				cv.blot(x + rng.uniform(4, 12), y + rng.uniform(4, 12), rng.uniform(4, 7), 0.75, rng, (x, y, 16, 16))
			elif kind == 3:  # brownish stain
				cv.blot(x + rng.uniform(5, 11), y + rng.uniform(5, 11), rng.uniform(3, 6), 0.8, rng, (x, y, 16, 16))
				cv.a[y:y + 16, x:x + 16, 0] = np.clip(cv.a[y:y + 16, x:x + 16, 0] * 1.06, 0, 1)
			elif kind == 4:  # crack
				cx, cy = x + 2, y + int(rng.integers(3, 13))
				for s in range(14):
					cv.px(cx + s, cy, grout)
					cy += int(rng.integers(-1, 2))
					cy = min(max(cy, y + 1), y + 15)
			elif kind == 5:  # black scuff streaks
				for _ in range(2):
					sx, sy = x + int(rng.integers(2, 10)), y + int(rng.integers(2, 14))
					cv.rect(sx, sy, int(rng.integers(3, 6)), 1, scale(base, 0.55))
			elif kind == 6:  # wet puddle: darker and glossier
				cv.blot(x + 8, y + 8, 7.5, 0.82, rng, (x, y, 16, 16))
				rough.blot(x + 8, y + 8, 7.5, 0.35, rng, (x, y, 16, 16))
			elif kind == 7:  # dirty corner
				cv.blot(x + 1, y + 1, 6, 0.8, rng, (x, y, 16, 16))
			cv.rect(x, y, 16, 1, grout)
			cv.rect(x, y, 1, 16, grout)
			rough.rect(x, y, 16, 1, C("#8A8A8A"))
			rough.rect(x, y, 1, 16, C("#8A8A8A"))
	return cv, rough


def build_concrete(seed=5):
	"""128x64 atlas of 8 concrete variants, 32 px = 1 m."""
	rng = np.random.default_rng(seed)
	cv = Canvas(128, 64)
	for j in range(2):
		for i in range(4):
			x, y = i * 32, j * 32
			k = j * 4 + i
			cv.rect(x, y, 32, 32, "#4C504C" if k % 2 == 0 else "#484C48")
			cv.noise(x, y, 32, 32, 0.03, rng)
			cv.noise(x, y, 32, 32, 0.015, rng, mono=False)
			if k in (1, 4, 6):
				cv.blot(x + rng.uniform(8, 24), y + rng.uniform(8, 24), rng.uniform(6, 12), 0.72, rng, (x, y, 32, 32))
			if k == 2:  # oil stain
				cv.blot(x + 16, y + 16, 10, 0.55, rng, (x, y, 32, 32))
			if k == 3:  # crack
				cx, cy = x + 1, y + int(rng.integers(8, 24))
				for s in range(30):
					cv.px(cx + s, cy, "#262826")
					cy = min(max(cy + int(rng.integers(-1, 2)), y + 1), y + 30)
			if k == 5:  # faded yellow safety line
				cv.rect(x, y + 13, 32, 3, mix("#4C504C", "#B89A30", 0.55))
				cv.noise(x, y + 13, 32, 3, 0.05, rng)
			if k == 7:  # water rings
				cv.blot(x + 10, y + 20, 7, 0.8, rng, (x, y, 32, 32))
				cv.blot(x + 22, y + 10, 5, 0.85, rng, (x, y, 32, 32))
	return cv


def build_ceiling_tiles(seed=9):
	"""128x64 atlas of 8 drop-ceiling tile variants, 32 px per tile; T-bar on top/left edges."""
	rng = np.random.default_rng(seed)
	cv = Canvas(128, 64)
	tbar, tbar_hi = C("#5E5E58"), C("#9A9A92")
	for j in range(2):
		for i in range(4):
			x, y = i * 32, j * 32
			k = j * 4 + i
			base = ["#74746C", "#70706A", "#78786F", "#727269", "#706E66", "#4A4A45", "#74746C", "#66665F"][k]
			cv.rect(x, y, 32, 32, base)
			cv.noise(x, y, 32, 32, 0.035, rng)
			for _ in range(40):  # fissured speckle
				cv.px(x + int(rng.integers(1, 32)), y + int(rng.integers(1, 32)), scale(base, 0.75))
			if k == 3:  # water stain ring
				cv.blot(x + 16, y + 16, 12, 0.85, rng, (x, y, 32, 32))
				cv.blot(x + 16, y + 16, 8, 1.08, rng, (x, y, 32, 32))
				cv.a[y:y + 32, x:x + 32, 2] *= 0.9
			if k == 4:  # brown leak stain off-centre
				cv.blot(x + 10, y + 22, 9, 0.75, rng, (x, y, 32, 32))
				cv.a[y:y + 32, x:x + 32, 2] *= 0.88
			if k == 5:  # dark, mouldy tile
				cv.blot(x + 16, y + 14, 14, 0.7, rng, (x, y, 32, 32))
			if k == 6:  # air vent grille
				cv.rect(x + 6, y + 6, 20, 20, "#A0A098")
				for s in range(8, 25, 3):
					cv.rect(x + 8, y + s, 16, 1, "#3A3A36")
				cv.outline(x + 6, y + 6, 20, 20, "#6A6A64")
			if k == 7:  # sagging grey tile
				cv.vgrad(x, y, 32, 32, 0.9, 0.7)
			cv.rect(x, y, 32, 1, tbar)
			cv.rect(x, y, 1, 32, tbar)
			cv.rect(x, y + 1, 32, 1, tbar_hi)
			cv.rect(x + 1, y, 1, 32, tbar_hi)
	return cv


def build_wall(seed, base, block, grime):
	"""64x128 = 2 m wide x 4 m tall painted block wall, repeats horizontally. Rows from the top."""
	rng = np.random.default_rng(seed)
	cv = Canvas(64, 128, base)
	cv.noise(0, 0, 64, 128, 0.02, rng)
	# block courses: 0.2 m high (6.4 px) -> lines every 6/7 px; blocks 0.4 m (12.8 px)
	for r in range(20):
		yy = 128 - int(round(r * 6.4))
		cv.rect(0, yy - 1, 64, 1, block)
		off = 0 if r % 2 == 0 else 6
		for k in range(-1, 6):
			xx = int(round(off + k * 12.8))
			cv.rect(xx, yy - 7, 1, 6, block)
	# grime gradient near the floor and streaks
	cv.vgrad(0, 96, 64, 32, 1.0, 0.7)
	for _ in range(6):
		sx = int(rng.integers(0, 64))
		cv.shade(sx, int(rng.integers(30, 90)), 1, int(rng.integers(10, 40)), 0.88)
	cv.rect(0, 124, 64, 4, grime)  # rubber cove base 0.12 m
	cv.rect(0, 123, 64, 1, scale(grime, 1.4))
	return cv
