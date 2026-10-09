extends RefCounted
## Screenshot logic for the game_*.gd shot scripts (Task 5). Run a shot with:
##   ~/tools/godot/godot --path . --rendering-driver opengl3 --resolution 960x540 \
##       -s res://tools/shots/game_ingame.gd [-- --out=/abs/dir]
## PNGs go to <project>/.superpowers/shots/ unless --out is given (keep them out of git).
##
## The -s entry scripts are compiled before the autoloads exist, so they must not name
## GameState/Events/Tasks. They load this file at runtime (after one frame) and call it.

const GAME_SCENE := "res://scenes/game.tscn"


## Entry point used by every game_*.gd shot script.
static func run(tree: SceneTree, shot: String) -> void:
	match shot:
		"main_menu":
			await _main_menu(tree)
		"ingame":
			await _ingame(tree)
		"paused":
			await _paused(tree)
		"end_screen":
			await _end_screen(tree)
	tree.quit()


static func arg(name: String, default_value: String) -> String:
	for item in OS.get_cmdline_user_args():
		if item.begins_with("--%s=" % name):
			return item.trim_prefix("--%s=" % name)
	return default_value


static func out_path(file_name: String) -> String:
	var dir := arg("out", ProjectSettings.globalize_path("res://").path_join(".superpowers/shots"))
	DirAccess.make_dir_recursive_absolute(dir)
	return dir.path_join(file_name)


static func save(tree: SceneTree, file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out_path(file_name)
	var err := tree.root.get_texture().get_image().save_png(path)
	print("saved %s (%s)" % [path, error_string(err)])


static func wait_frames(tree: SceneTree, count: int) -> void:
	for i in count:
		await tree.process_frame


## Instances the game without grabbing the desktop mouse and waits for the night to start.
static func start_game(tree: SceneTree) -> Game:
	var game: Game = (load(GAME_SCENE) as PackedScene).instantiate()
	game.capture_mouse_on_start = false
	tree.root.add_child(game)
	for i in 600:
		if game.state == Game.State.PLAYING:
			break
		await tree.process_frame
	return game


## Puts the player at `position` looking along yaw/pitch (degrees).
static func place_player(position: Vector3, yaw_degrees: float, pitch_degrees := 0.0) -> Player:
	var player := GameState.player as Player
	player.global_position = position
	player.rotation.y = deg_to_rad(yaw_degrees)
	(player.get_node("Head") as Node3D).rotation.x = deg_to_rad(pitch_degrees)
	player.velocity = Vector3.ZERO
	return player


## A believable checklist for the HUD while the Tasks autoload is still a stub.
static func sample_tasks() -> Array[TaskData]:
	var tasks: Array[TaskData] = []
	tasks.append(_task("Reset the breaker", true, 74.0))
	tasks.append(_task("Mop the spill in Aisle 3"))
	tasks.append(_task("Restock Aisle 4"))
	tasks.append(_task("Count register 1"))
	tasks.append(_task("Log the freezer temperature", false, 0.0, true))
	tasks.append(_task("Face the shelves in Aisle 1", false, 0.0, true))
	return tasks


static func _task(title: String, manager := false, time_left := 0.0, done := false) -> TaskData:
	var task := TaskData.new()
	task.title = title
	task.is_manager_task = manager
	task.time_limit = 120.0 if manager else 0.0
	task.time_left = time_left
	task.completed = done
	return task


# --- Shots ------------------------------------------------------------------------

static func _main_menu(tree: SceneTree) -> void:
	tree.root.add_child((load("res://scenes/main_menu.tscn") as PackedScene).instantiate())
	await wait_frames(tree, 20)
	await save(tree, "game_main_menu.png")


## Reference-2 viewpoint (aisle 4 toward DAIRY) and reference-3 viewpoint (storage toward EXIT).
## `-- --view=aisle,storage,intro,hide` picks which to take (default aisle,storage).
static func _ingame(tree: SceneTree) -> void:
	var views := arg("view", "aisle,storage").split(",")
	var game := await start_game(tree)
	var hud := game.get_node("HUD") as GameHud
	if views.has("intro"):
		await wait_frames(tree, 8)
		await save(tree, "game_intro_card.png")
	await tree.create_timer(GameHud.INTRO_TIME + 0.5).timeout
	hud.render_checklist(sample_tasks())
	var player := GameState.player as Player
	player.health = 68.0
	for view in views:
		match view:
			"aisle":
				place_player(Vector3(-2.0, 0, 6.6), 0.0, 4.0)
				Events.walkie_message.emit("RITA", "Anyone else hear that in the back?", Vector3.ZERO, false)
				Events.interaction_prompt_changed.emit("[E] Restock shelf")
				await wait_frames(tree, 30)
				await save(tree, "game_ingame_aisle4.png")
			"storage":
				player.set_held_tool(&"box_cutter")
				place_player(Vector3(-5.2, 0, -13.0), 90.0, 2.0)
				Events.interaction_prompt_changed.emit("")
				await wait_frames(tree, 30)
				await save(tree, "game_ingame_storage.png")
			"hide":
				for node in tree.get_nodes_in_group(&"hiding_spot"):
					if (node as HidingSpot).spot_kind == &"locker":
						player.enter_hiding(node)
						break
				await tree.create_timer(0.8).timeout
				await save(tree, "game_hidden_locker.png")


static func _paused(tree: SceneTree) -> void:
	var game := await start_game(tree)
	await tree.create_timer(GameHud.INTRO_TIME + 0.5).timeout
	(game.get_node("HUD") as GameHud).render_checklist(sample_tasks())
	place_player(Vector3(-6.0, 0, 6.4), 8.0, 0.0)
	await wait_frames(tree, 10)
	game.pause_game()
	await wait_frames(tree, 10)
	await save(tree, "game_paused.png")


## `-- --result=win|fired|dead` (default dead).
static func _end_screen(tree: SceneTree) -> void:
	var result := StringName(arg("result", "dead"))
	var game := await start_game(tree)
	place_player(Vector3(-14.0, 0, -1.0), 180.0, -5.0)
	GameState.advance(GameState.SECONDS_PER_HOUR * 3.7)
	GameState.add_stat("tasks_completed", 3)
	GameState.add_stat("times_hidden", 2)
	GameState.add_stat("damage_taken", 100.0)
	GameState.add_stat("monster_sightings", 1)
	GameState.end_night(result)
	await wait_frames(tree, 15)
	await save(tree, "game_end_%s.png" % result)
	game.queue_free()
