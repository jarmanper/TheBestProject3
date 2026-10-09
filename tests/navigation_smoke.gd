extends SceneTree

func _init() -> void:
	change_scene_to_file("res://main.tscn")
	call_deferred("_check_navigation")


func _check_navigation() -> void:
	for frame in range(3):
		await process_frame
	await physics_frame
	await physics_frame
	var game = current_scene
	if game == null:
		push_error("Main scene did not load for the navigation test.")
		quit(1)
		return
	if not game.mimic_navigation_ready:
		push_error("Mimic navigation grid was not built.")
		quit(1)
		return
	var path = game._find_mimic_path(game.monster.global_position, game._priority_task_position())
	if path.size() < 2:
		push_error("Mimic could not find a route to the active task.")
		quit(1)
		return
	var spawn_position: Vector3 = game.monster.global_position
	game.monster.global_position = Vector3(-6.5, 0.0, -7.5)
	if game._mimic_has_line_of_sight(Vector3(0.0, 1.0, -7.5)):
		push_error("Shelf collision did not block the mimic's line of sight.")
		quit(1)
		return
	game.monster.global_position = spawn_position
	await create_timer(1.0).timeout
	var travelled: float = game._flat_distance(spawn_position, game.monster.global_position)
	if travelled < 0.2:
		print("Mimic remained at: ", game.monster.global_position, " // route target: ", game.mimic_path[0] if not game.mimic_path.is_empty() else "none")
		push_error("Mimic did not move from its spawn position.")
		quit(1)
		return
	print("Mimic navigation validated: ", path.size(), " path points; moved ", snappedf(travelled, 0.01), "m after spawning.")
	quit()
