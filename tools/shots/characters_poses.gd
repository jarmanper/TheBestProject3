extends "res://tools/shots/characters_base.gd"
## Animation contact sheet: one character repeated across a clip at evenly spaced times.
##   godot --path . --rendering-driver opengl3 --resolution 960x540 \
##       -s res://tools/shots/characters_poses.gd -- --out=/abs/walk.png --model=employee_dale \
##       --anim=walk [--count=6] [--yaw=90] [--end=1]
## --yaw=90 shows the right-hand side (character walking toward screen right).
## --end=1 includes the clip's final frame (for one-shot clips like attack/reveal).


func build() -> void:
	var model := arg_str("model", "employee_dale")
	var anim := arg_str("anim", "walk")
	var count := int(arg_float("count", 6.0))
	var yaw := arg_float("yaw", 90.0)
	var include_end := arg_bool("end", false)
	make_environment(Color("5a6460"), 1.0)
	tile_floor(Vector3(0, 0, 0), Vector2(16, 8))
	var big := model == "monster"
	var spacing := 1.75 if big else 0.95
	var length := 1.0
	var path: String = MODELS.get(model, model)
	if ResourceLoader.exists(path):
		var probe := (load(path) as PackedScene).instantiate()
		var player := probe.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if player != null and player.has_animation(anim):
			length = player.get_animation(anim).length
		probe.free()
	var width := spacing * float(count - 1)
	for i in count:
		var t := length * float(i) / float(count - 1 if include_end else count)
		add_character(model, Vector3(-width * 0.5 + spacing * i, 0, 0), yaw, anim, t)
	var height := 2.7 if big else 1.85
	var dist := maxf(width * 0.95, height * 1.9) + 1.5
	make_camera(Vector3(0, height * 0.55, dist), Vector3(0, height * 0.48, 0), 40.0)
	fluorescent(Vector3(0, 3.6, 1.5), 2.6, 12.0, false)
	omni(Vector3(0, 1.8, dist * 0.6), Color("c8ccc4"), 0.7, 12.0)
