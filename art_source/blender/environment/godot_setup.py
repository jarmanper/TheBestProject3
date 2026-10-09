"""Godot-side setup for the environment assets (plain Python 3, run after build_store.py).

	python3 art_source/blender/environment/godot_setup.py

- writes the shared StandardMaterial3D resources in assets/models/environment/materials/
  (nearest-filtered pixel textures, wet floor roughness, emissive tubes),
- sets the import parameters of the atlas PNGs (lossless + mipmaps, never VRAM-compressed),
- sets the import parameters of every environment .glb: embedded images discarded, every glTF material
  mapped to the shared .tres (so the store and all kit pieces share one copy of each texture), no LODs.
Then run `godot --headless --path . --import`.
"""
import glob
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
ENV = os.path.join(ROOT, "assets", "models", "environment")
RES = "res://assets/models/environment"

FILTER_NEAREST_MIPMAPS = 2
TRANSPARENCY_ALPHA = 1


def color(h, a=1.0):
	h = h.lstrip("#")
	r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
	return "Color(%.4f, %.4f, %.4f, %.3f)" % (r, g, b, a)


# name -> (file, textures {property: png}, plain properties)
MATERIALS = {
	"Products": ("products.tres", {"albedo_texture": "atlas_products.png"}, {"roughness": 0.78, "metallic_specular": 0.35}),
	"Env": ("env.tres", {"albedo_texture": "atlas_env.png"}, {"roughness": 0.7, "metallic_specular": 0.4}),
	"FloorTile": ("floor_tile.tres", {"albedo_texture": "floor_tiles.png", "roughness_texture": "floor_tiles_rough.png"},
		{"roughness": 1.0, "metallic_specular": 1.0}),
	"FloorConcrete": ("floor_concrete.tres", {"albedo_texture": "concrete.png"}, {"roughness": 0.72, "metallic_specular": 0.4}),
	"CeilingTile": ("ceiling_tile.tres", {"albedo_texture": "ceiling_tiles.png"}, {"roughness": 0.95, "metallic_specular": 0.2}),
	"WallSales": ("wall_sales.tres", {"albedo_texture": "wall_sales.png"}, {"roughness": 0.85, "metallic_specular": 0.3}),
	"WallBack": ("wall_back.tres", {"albedo_texture": "wall_back.png"}, {"roughness": 0.85, "metallic_specular": 0.3}),
	"FluorescentTube": ("fluorescent_tube.tres", {}, {"albedo_color": color("D8D3A8"), "emission_enabled": "true",
		"emission": color("D8D3A8"), "emission_energy_multiplier": 3.0, "roughness": 0.4}),
	"CoolerLight": ("cooler_light.tres", {}, {"albedo_color": color("CFE4F0"), "emission_enabled": "true",
		"emission": color("CFE4F0"), "emission_energy_multiplier": 1.6}),
	"Glass": ("glass.tres", {}, {"transparency": TRANSPARENCY_ALPHA, "albedo_color": color("0C1013", 0.28),
		"roughness": 0.04, "metallic_specular": 0.9}),
	"ExitSign": ("exit_sign.tres", {"albedo_texture": "atlas_env.png", "emission_texture": "atlas_env.png"},
		{"emission_enabled": "true", "emission": color("FFFFFF"), "emission_energy_multiplier": 2.5}),
	"EmergencyLight": ("emergency_light.tres", {}, {"albedo_color": color("B93B32"), "emission_enabled": "true",
		"emission": color("FF3A28"), "emission_energy_multiplier": 2.2}),
}


def fmt(v):
	if isinstance(v, float):
		return ("%.4f" % v).rstrip("0").rstrip(".") if v != int(v) else "%.1f" % v
	return str(v)


def write_materials():
	os.makedirs(os.path.join(ENV, "materials"), exist_ok=True)
	for name, (fname, textures, props) in MATERIALS.items():
		lines = ['[gd_resource type="StandardMaterial3D" load_steps=%d format=3]' % (len(set(textures.values())) + 1), ""]
		ids = {}
		for png in textures.values():
			if png not in ids:
				ids[png] = str(len(ids) + 1)
				lines.append('[ext_resource type="Texture2D" path="%s/textures/%s" id="%s"]' % (RES, png, ids[png]))
		if ids:
			lines.append("")
		lines.append("[resource]")
		lines.append('resource_name = "%s"' % name)
		for k, v in props.items():
			lines.append("%s = %s" % (k, fmt(v)))
		for prop, png in textures.items():
			lines.append('%s = ExtResource("%s")' % (prop, ids[png]))
		lines.append("texture_filter = %d" % FILTER_NEAREST_MIPMAPS)
		with open(os.path.join(ENV, "materials", fname), "w") as f:
			f.write("\n".join(lines) + "\n")


def set_params(path, params, header):
	"""Replace (or add) keys in the [params] section of a .import file, creating a minimal file if needed."""
	text = open(path).read() if os.path.exists(path) else header
	if "[params]" not in text:
		text = text.rstrip("\n") + "\n\n[params]\n"
	head, body = text.split("[params]", 1)
	body_lines = body.strip("\n").split("\n") if body.strip() else []
	out, i = [], 0
	keys = dict(params)
	while i < len(body_lines):
		line = body_lines[i]
		m = re.match(r"^([\w/]+)=", line)
		if m and m.group(1) in keys:
			# multi-line values (dictionaries) run until a line that is just "}"
			if line.rstrip().endswith("{") and not line.rstrip().endswith("{}"):
				while i < len(body_lines) and body_lines[i] != "}":
					i += 1
			out.append("%s=%s" % (m.group(1), keys.pop(m.group(1))))
		else:
			out.append(line)
		i += 1
	for k, v in keys.items():
		out.append("%s=%s" % (k, v))
	with open(path, "w") as f:
		f.write(head + "[params]\n\n" + "\n".join(l for l in out if l != "") + "\n")


def material_subresources():
	parts = []
	for name, (fname, _, _) in MATERIALS.items():
		parts.append('"%s": {\n"use_external/enabled": true,\n"use_external/path": "%s/materials/%s"\n}' % (name, RES, fname))
	return '{\n"materials": {\n' + ",\n".join(parts) + "\n}\n}"


def main():
	write_materials()
	tex_header = '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n'
	for png in sorted(glob.glob(os.path.join(ENV, "textures", "*.png"))):
		set_params(png + ".import", {"compress/mode": "0", "mipmaps/generate": "true", "mipmaps/limit": "-1",
			"detect_3d/compress_to": "0", "process/fix_alpha_border": "false"}, tex_header)
	scene_header = '[remap]\n\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n'
	subres = material_subresources()
	for glb in sorted(glob.glob(os.path.join(ENV, "**", "*.glb"), recursive=True)):
		set_params(glb + ".import", {"meshes/ensure_tangents": "false", "meshes/generate_lods": "false",
			"gltf/embedded_image_handling": "0", "_subresources": subres}, scene_header)
	# textures Godot extracted from the GLBs before this setup ran are redundant now
	for extracted in sorted(set(p for p in glob.glob(os.path.join(ENV, "**", "*.png*"), recursive=True)
			if os.sep + "textures" + os.sep not in p)):
		os.remove(extracted)
	print("materials:", len(MATERIALS), "glb imports configured:", len(glob.glob(os.path.join(ENV, "**", "*.glb"), recursive=True)))


main()
