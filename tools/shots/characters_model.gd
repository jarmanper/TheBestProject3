extends "res://tools/shots/characters_base.gd"
## One character, framed full body or head, from any yaw, frozen at any clip time.
##   godot --path . --rendering-driver opengl3 --resolution 960x540 \
##       -s res://tools/shots/characters_model.gd -- --out=/abs/shot.png --model=monster \
##       [--yaw=0] [--anim=idle] [--time=0.0] [--frame=full|head|upper] [--bright=1]


func build() -> void:
	var model := arg_str("model", "employee_dale")
	var bright := arg_bool("bright", true)
	make_environment(Color("5a6460"), 1.0 if bright else 0.45)
	tile_floor(Vector3(0, 0, 0), Vector2(10, 10))
	var character := add_character(model, Vector3.ZERO, arg_float("yaw", 0.0), arg_str("anim", "idle"),
		arg_float("time", 0.0))
	var height := 1.8
	if character != null:
		var top := 0.0
		for node in character.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := node as MeshInstance3D
			var aabb := mesh_instance.global_transform * mesh_instance.get_aabb()
			top = maxf(top, aabb.end.y)
		height = top
	var frame := arg_str("frame", "full")
	match frame:
		"head":
			var head_y := height - (0.58 if model == "monster" else 0.14)
			var forward := 0.6 if model == "monster" else 0.0
			var dist := 1.35 if model == "monster" else 0.75
			make_camera(Vector3(0, head_y, forward + dist), Vector3(0, head_y, forward), 40.0)
		"upper":
			make_camera(Vector3(0, height * 0.8, 1.9 + height * 0.3), Vector3(0, height * 0.7, 0), 45.0)
		_:
			make_camera(Vector3(0, height * 0.55, 2.4 + height), Vector3(0, height * 0.5, 0), 45.0)
	fluorescent(Vector3(0, 3.4, 1.0), 2.4 if bright else 1.6, 8.0, false)
	omni(Vector3(1.5, 1.6, 2.5), Color("c8ccc4"), 0.8 if bright else 0.3, 8.0)
	omni(Vector3(-2.0, 2.0, -1.5), Color("8890a0"), 0.5, 6.0)
