extends "res://tools/shots/characters_base.gd"
## Recreates reference image 2's composition: first-person view down a dim aisle, one employee
## working at the left shelf, another standing further down on the right, seen from behind.
##   godot --path . --rendering-driver opengl3 --resolution 960x540 \
##       -s res://tools/shots/characters_ref2.gd -- --out=/abs/ref2.png [--half_res=1] [--time=0.5]


func build() -> void:
	make_environment(Color("3a4a46"), 0.3, 0.04, Color("0d1211"))
	make_camera(Vector3(-0.2, 1.62, 3.0), Vector3(0.35, 1.25, -4.0), 72.0)
	tile_floor(Vector3(0, 0, -3), Vector2(6, 16))
	box(Vector3(0, 3.25, -3), Vector3(6, 0.1, 16), Color("1c201f"))
	box(Vector3(0, 1.6, -10.2), Vector3(6, 3.2, 0.2), Color("232826"))
	box(Vector3(0.3, 2.45, -9.9), Vector3(1.1, 0.24, 0.05), Color("d8d3a8"), 0.25)
	shelf_run(-1.6, 3.0, -9.5, -1.0)
	shelf_run(1.8, 3.0, -9.5, 1.0)
	fluorescent(Vector3(-0.3, 3.15, 0.5), 1.6, 6.5)
	fluorescent(Vector3(0.3, 3.15, -4.5), 1.4, 6.5)
	omni(Vector3(0.6, 1.8, -8.6), Color("a0b0b0"), 0.6, 4.0)
	var time := arg_float("time", 0.5)
	# Working at the left shelf, side-on to the camera.
	add_character("employee_marcus", Vector3(-0.85, 0, -2.6), -90.0, "work", time)
	# Standing further down on the right, facing away.
	add_character("employee_dale", Vector3(1.05, 0, -4.4), 180.0, "idle", time)
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
	COLOR = vec4(0.0, 0.0, 0.0, (1.0 - smoothstep(0.8, 0.4, length(uv))) * 0.8);
}
"""
	material.shader = shader
	rect.material = material
