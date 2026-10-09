extends "res://tools/shots/characters_base.gd"
## All five characters side by side under dim store lighting.
##   godot --path . --rendering-driver opengl3 --resolution 960x540 \
##       -s res://tools/shots/characters_lineup.gd -- --out=/abs/lineup.png [--back=1] [--anim=idle] [--time=0.3]
##       [--bright=1]


func build() -> void:
	var bright := arg_bool("bright", false)
	make_environment(Color("4a5450"), 0.9 if bright else 0.45)
	var back := arg_bool("back", false)
	var anim := arg_str("anim", "idle")
	var time := arg_float("time", 0.3)
	var yaw := 0.0  # models face +Z; the back view moves the camera instead
	var cam_z := -6.2 if back else 6.2
	make_camera(Vector3(0.0, 1.45, cam_z), Vector3(0.0, 1.2, 0.0), 45.0)
	tile_floor(Vector3(0, 0, 0), Vector2(14, 10))
	box(Vector3(0, 2.0, -3.0 if not back else 3.0), Vector3(14, 4, 0.2), Color("1f2422"))
	var xs := [-2.6, -1.45, -0.3, 0.9, 2.45]
	if back:
		xs.reverse()
	var names := ["employee_dale", "employee_rita", "employee_marcus", "manager", "monster"]
	for i in names.size():
		var name: String = names[i]
		var clip := anim
		if name == "manager" and anim in ["run", "work"]:
			clip = "talk"
		if name == "monster" and anim == "work":
			clip = "idle"
		add_character(name, Vector3(xs[i], 0, 0), yaw, clip, time)
	fluorescent(Vector3(-1.2, 3.6, 0.8), 2.6 if bright else 1.8, 8.0, false)
	fluorescent(Vector3(1.6, 3.6, 0.8), 2.6 if bright else 1.8, 8.0, false)
	omni(Vector3(0, 1.6, cam_z * 0.6), Color("b8c0b8"), 0.6 if bright else 0.25, 8.0)
