extends "res://tools/shots/characters_base.gd"
## Recreates reference image 3's composition: the manager standing in a dim storage room between
## metal shelves, a fluorescent tube above and a green EXIT sign behind him.
##   godot --path . --rendering-driver opengl3 --resolution 960x540 \
##       -s res://tools/shots/characters_ref3.gd -- --out=/abs/ref3.png [--half_res=1] [--anim=idle]


func build() -> void:
	make_environment(Color("324440"), 0.3, 0.035, Color("0c1412"))
	make_camera(Vector3(0.0, 1.6, 1.75), Vector3(0.0, 1.22, -2.0), 70.0)
	tile_floor(Vector3(0, 0, -2), Vector2(6, 12))
	box(Vector3(0, 3.0, -2), Vector3(6, 0.1, 12), Color("1d2120"))
	box(Vector3(0, 1.5, -4.2), Vector3(6, 3.0, 0.2), Color("27302c"))          # back wall
	box(Vector3(0, 1.05, -4.08), Vector3(1.0, 2.1, 0.06), Color("1e2523"))      # emergency door
	box(Vector3(0, 2.45, -4.05), Vector3(0.5, 0.2, 0.05), Color("46d27a"), 2.0)  # EXIT sign
	omni(Vector3(0, 2.3, -3.6), Color("46d27a"), 1.2, 4.5)
	shelf_run(-1.5, 2.5, -4.0, -1.0, 2.4, 0.5, 5)
	shelf_run(1.5, 2.5, -4.0, 1.0, 2.4, 0.5, 5)
	fluorescent(Vector3(0.0, 2.95, -0.2), 2.0, 6.0)
	omni(Vector3(0.3, 1.5, 2.6), Color("c0c8c0"), 0.35, 5.0)  # player's flashlight spill
	add_character("manager", Vector3(0.0, 0, -0.6), 0.0, arg_str("anim", "idle"), arg_float("time", 0.6))
