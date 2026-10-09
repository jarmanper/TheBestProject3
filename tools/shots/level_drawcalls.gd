extends SceneTree
## Draw-call sweep of the real game in the store: the player stands on a grid of walkable
## points (every --step metres, on the navmesh) and looks in 8 directions; prints the worst
## views and the distribution of RENDER_TOTAL_DRAW_CALLS_IN_FRAME / PRIMITIVES.
##   ~/tools/godot/godot --path . --rendering-driver opengl3 --resolution 960x540 \
##       -s res://tools/shots/level_drawcalls.gd [-- --step=4 --flashlight=on]


func _arg(arg_name: String, default_value: String) -> String:
	for item in OS.get_cmdline_user_args():
		if item.begins_with("--%s=" % arg_name):
			return item.trim_prefix("--%s=" % arg_name)
	return default_value


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var util: GDScript = load("res://tools/shots/level_shot_util.gd")
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	game.set(&"capture_mouse_on_start", false)
	root.add_child(game)
	for i in 600:
		if game.get(&"state") != 0:
			break
		await process_frame
	var game_state := root.get_node("GameState")
	game_state.set(&"night_running", false)
	for node in get_nodes_in_group(&"coworker") + get_nodes_in_group(&"monster"):
		node.set_physics_process(false)
		(node as Node3D).global_position = Vector3(40, -30, 40)
	var player: Node3D = game_state.get(&"player")
	player.call(&"set_flashlight", _arg("flashlight", "on") == "on")
	await create_timer(4.0).timeout
	var map := player.get_world_3d().navigation_map
	var step := float(_arg("step", "4"))
	var samples: Array = []
	var x := -19.0
	while x <= 19.0:
		var z := -15.5
		while z <= 15.5:
			var probe := Vector3(x, 0, z)
			var on_mesh := NavigationServer3D.map_get_closest_point(map, probe)
			if Vector2(on_mesh.x - x, on_mesh.z - z).length() < 0.3:
				for yaw in range(0, 360, 45):
					util.place_player(on_mesh, float(yaw), 0.0)
					for i in 3:
						await process_frame
					await RenderingServer.frame_post_draw
					samples.append([int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
						int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)), on_mesh, yaw])
			z += step
		x += step
	samples.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var calls: Array = samples.map(func(s: Array) -> int: return s[0])
	var over := calls.filter(func(c: int) -> bool: return c >= 600).size()
	print("views: %d  max: %d  p95: %d  median: %d  >=600: %d" % [
		samples.size(), calls[0], calls[int(calls.size() * 0.05)], calls[calls.size() / 2], over])
	for s in samples.slice(0, 8):
		print("  %4d calls  %6d prims  at (%.1f, %.1f) yaw %d" % [s[0], s[1], s[2].x, s[2].z, s[3]])
	quit()
