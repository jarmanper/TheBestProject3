extends "res://tools/shots/characters_base.gd"
## Recreates reference image 1's composition: an employee seen from behind in the foreground, the
## monster standing down a dim store aisle under a fluorescent light. Placeholder shelves and boxes.
##   godot --path . --rendering-driver opengl3 --resolution 960x540 \
##       -s res://tools/shots/characters_ref1.gd -- --out=/abs/ref1.png [--half_res=1] \
##       [--employee=employee_dale] [--monster_anim=idle] [--time=0.4]


func build() -> void:
	make_environment(Color("3a4a46"), 0.32, 0.035, Color("0d1211"))
	make_camera(Vector3(0.1, 1.62, 3.2), Vector3(0.25, 1.5, -4.0), 72.0)
	tile_floor(Vector3(0, 0, -3), Vector2(6, 16))
	box(Vector3(0, 3.25, -3), Vector3(6, 0.1, 16), Color("1c201f"))         # ceiling
	box(Vector3(0, 1.6, -10.2), Vector3(6, 3.2, 0.2), Color("232826"))       # far wall
	box(Vector3(0.2, 2.45, -9.9), Vector3(1.1, 0.24, 0.05), Color("d8d3a8"), 0.25)  # "DAIRY" sign
	box(Vector3(1.05, 2.85, -0.4), Vector3(0.7, 0.5, 0.06), Color("2a2f2c"))  # hanging aisle sign
	shelf_run(-1.6, 3.0, -9.5, -1.0)
	shelf_run(1.8, 3.0, -9.5, 1.0)
	for z in [-0.5, -3.0]:
		box(Vector3(-1.1, 2.32, z), Vector3(0.6, 0.18, 0.04), Color("d8d3a8"), 0.15)  # shelf-top signs
	fluorescent(Vector3(-0.1, 3.15, -1.0), 2.4, 7.5)
	fluorescent(Vector3(0.0, 3.15, 1.6), 0.9, 5.0)
	fluorescent(Vector3(0.1, 3.15, -7.5), 1.2, 6.0)
	omni(Vector3(0.2, 1.4, -8.8), Color("8fa0a0"), 0.5, 4.0)
	var time := arg_float("time", 0.4)
	add_character(arg_str("employee", "employee_dale"), Vector3(-0.62, 0, 1.75), 180.0, "idle", time)
	add_character("monster", Vector3(0.42, 0, -1.55), -10.0, arg_str("monster_anim", "idle"), time)
	_vignette()


func _vignette() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	root.add_child(layer)
	var rect := ColorRect.new()
	layer.add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
void fragment() {
	vec2 uv = (UV - 0.5) * vec2(1.0, 0.9);
	float v = smoothstep(0.78, 0.38, length(uv));
	float corner = smoothstep(0.47, 0.5, max(abs(UV.x - 0.5), abs(UV.y - 0.5)));
	COLOR = vec4(0.0, 0.0, 0.0, clamp(1.0 - v + corner, 0.0, 1.0) * 0.85);
}
"""
	material.shader = shader
	rect.material = material
