extends RefCounted
## Screenshots of the real game in the final store (HUD + CRT on), staged like the reference
## pictures, plus draw-call / primitive counts per view. Entry: tools/shots/level_views.gd.
##   ~/tools/godot/godot --path . --rendering-driver opengl3 --resolution 960x540 \
##       -s res://tools/shots/level_views.gd -- [--views=ref2,ref1,ref3,breakroom,office,hide] \
##       [--out=/abs/dir] [--prefix=v1_] [--flashlight=on|off]
## Loaded at runtime by the entry script (the game's classes need the autoloads).

const GAME_SCENE := "res://scenes/game.tscn"
const ALL_VIEWS := "ref2,ref1,ref3,breakroom,office,hide,locker,hallway,checkout"


static func arg(arg_name: String, default_value: String) -> String:
	for item in OS.get_cmdline_user_args():
		if item.begins_with("--%s=" % arg_name):
			return item.trim_prefix("--%s=" % arg_name)
	return default_value


static func run(tree: SceneTree) -> void:
	var game: Game = (load(GAME_SCENE) as PackedScene).instantiate()
	game.capture_mouse_on_start = false
	tree.root.add_child(game)
	for i in 600:
		if game.state == Game.State.PLAYING:
			break
		await tree.process_frame
	# Freeze the AI and the clock: the shots stage everyone by hand.
	GameState.night_running = false
	for node in tree.get_nodes_in_group(&"coworker") + tree.get_nodes_in_group(&"monster"):
		node.set_physics_process(false)
		node.set_process(false)
	await tree.create_timer(GameHud.INTRO_TIME + 0.6).timeout
	var player := GameState.player as Player
	player.set_flashlight(arg("flashlight", "on") == "on")
	if arg("activate", "") == "all":
		# Show every station's task visual (spill, boxes, sparks...) for the detail shots.
		for station: TaskStation in tree.get_nodes_in_group(&"task_station"):
			if not station.is_active():
				var task := TaskData.new()
				task.title = station.title
				station.set_task(task)
	var prefix := arg("prefix", "")
	var report: Array[String] = []
	for view in arg("views", ALL_VIEWS).split(","):
		await _stage(tree, game, view)
		await _settle(tree)
		var counts := await _save(tree, "%slevel_%s.png" % [prefix, view])
		report.append("%-10s draw_calls=%d primitives=%d objects=%d" % [view, counts.x, counts.y, counts.z])
	for line in report:
		print(line)
	tree.quit()


static func _settle(tree: SceneTree) -> void:
	for i in 24:
		await tree.process_frame


static func _save(tree: SceneTree, file_name: String) -> Vector3i:
	await RenderingServer.frame_post_draw
	var counts := Vector3i(
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
	var dir := arg("out", ProjectSettings.globalize_path("res://.superpowers/shots"))
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(file_name)
	var err := tree.root.get_texture().get_image().save_png(path)
	print("saved %s (%s)" % [path, error_string(err)])
	return counts


## Puts the player at `position` looking along yaw/pitch (degrees; yaw 0 looks down -Z).
static func place_player(position: Vector3, yaw: float, pitch := 0.0) -> Player:
	var player := GameState.player as Player
	if player.is_hidden:
		player.exit_hiding()
	player.global_position = position
	player.rotation.y = deg_to_rad(yaw)
	(player.get_node("Head") as Node3D).rotation.x = deg_to_rad(pitch)
	player.velocity = Vector3.ZERO
	return player


## Puts the player at `position` (feet) looking at `target`.
static func aim_player(position: Vector3, target: Vector3) -> Player:
	var eye := position + Vector3.UP * 1.6
	var to := target - eye
	var yaw := rad_to_deg(atan2(-to.x, -to.z))
	var pitch := rad_to_deg(atan2(to.y, Vector2(to.x, to.z).length()))
	return place_player(position, yaw, pitch)


## Puts a character at `position` with its model front (+Z) turned to `yaw` degrees, playing `anim`.
static func pose(character: Node3D, position: Vector3, yaw: float, anim: StringName, time := 0.0) -> void:
	character.global_position = position
	character.rotation = Vector3(0, deg_to_rad(yaw), 0)
	if character.get(&"_yaw") != null:
		character.set(&"_yaw", deg_to_rad(yaw))
	var animation := CharacterModel.find_animation_player(_visible_model(character))
	if animation and animation.has_animation(anim):
		animation.play(anim)
		animation.seek(time, true)
		animation.speed_scale = 0.0 if time > 0.0 else 1.0


static func _visible_model(character: Node3D) -> Node:
	for form_name in ["TrueForm", "DisguiseForm", "Visual"]:
		var form := character.get_node_or_null(form_name) as Node3D
		if form and form.visible:
			return form
	return character


static func coworkers(tree: SceneTree) -> Array[Node3D]:
	var list: Array[Node3D] = []
	for node in tree.get_nodes_in_group(&"coworker"):
		list.append(node as Node3D)
	return list


static func _hide_everyone(tree: SceneTree) -> void:
	for node in coworkers(tree):
		node.global_position = Vector3(30, -20, 30)
	var monster := GameState.monster as Node3D
	if monster:
		monster.global_position = Vector3(32, -20, 32)


static func _stage(tree: SceneTree, game: Game, view: String) -> void:
	_hide_everyone(tree)
	var crew := coworkers(tree)
	var monster := GameState.monster as Node3D
	Events.interaction_prompt_changed.emit("")
	match view:
		"ref2":
			# Aisle 4 toward DAIRY: one coworker stocking the left shelf, one standing on the right.
			place_player(Vector3(-2.0, 0, 8.2), 0.0, 4.0)
			if crew.size() >= 2:
				pose(crew[0], Vector3(-2.9, 0, 1.8), -90.0, Catalog.ANIM_WORK)
				pose(crew[1], Vector3(-1.2, 0, -0.6), 180.0, Catalog.ANIM_IDLE)
		"ref1":
			# A coworker seen from behind in the aisle, the monster's true form further down.
			place_player(Vector3(-2.3, 0, 8.0), 4.0, 7.0)
			if crew.size() >= 1:
				pose(crew[0], Vector3(-2.65, 0, 6.6), 175.0, Catalog.ANIM_IDLE)
			if monster:
				monster.call(&"_set_form", true)
				pose(monster, Vector3(-1.65, 0, 3.7), 12.0, Catalog.ANIM_REVEAL, 1.45)
		"ref3":
			# Storage toward the green EXIT sign, someone walking up the aisle.
			place_player(Vector3(-8.2, 0, -13.0), 90.0, 4.0)
			if crew.size() >= 1:
				pose(crew[0], Vector3(-11.6, 0, -12.95), 90.0, Catalog.ANIM_IDLE)
		"breakroom":
			place_player(Vector3(6.0, 0, -12.5), 180.0, -2.0)
			if crew.size() >= 2:
				pose(crew[0], Vector3(4.2, 0, -10.5), 120.0, Catalog.ANIM_IDLE)
				pose(crew[1], Vector3(8.4, 0, -10.6), 200.0, Catalog.ANIM_IDLE)
		"office":
			place_player(Vector3(12.6, 0, -9.7), 0.0, -4.0)
		"hide":
			for spot: HidingSpot in tree.get_nodes_in_group(&"hiding_spot"):
				if spot.spot_kind == &"counter" and spot.global_position.x < -6.0 and spot.global_position.x > -8.0:
					place_player(spot.get_exit_position(), 0.0)
					(GameState.player as Player).enter_hiding(spot)
					break
			if crew.size() >= 1:
				pose(crew[0], Vector3(-4.6, 0, 11.0), -100.0, Catalog.ANIM_WALK)
			await tree.create_timer(0.8).timeout
		"locker":
			for spot: HidingSpot in tree.get_nodes_in_group(&"hiding_spot"):
				if spot.spot_kind == &"locker":
					place_player(spot.get_exit_position(), 0.0)
					(GameState.player as Player).enter_hiding(spot)
					break
			if crew.size() >= 1:
				pose(crew[0], Vector3(5.2, 0, -11.6), -70.0, Catalog.ANIM_WALK)
			await tree.create_timer(0.8).timeout
		"hallway":
			place_player(Vector3(-17.5, 0, -7.5), -90.0, 0.0)
		"breaker":
			aim_player(Vector3(-1.4, 0, -6.8), Vector3(0.0, 1.3, -8.9))
		"janitor":
			aim_player(Vector3(17.4, 0, -10.2), Vector3(19.6, 0.9, -13.0))
		"storage_east":
			aim_player(Vector3(-4.8, 0, -10.0), Vector3(0.5, 0.6, -12.2))
		"service":
			aim_player(Vector3(11.0, 0, 10.6), Vector3(13.2, 0.9, 13.6))
		"dairy":
			aim_player(Vector3(-5.5, 0, -2.4), Vector3(-8.0, 0.6, -5.2))
		"frozen":
			aim_player(Vector3(-17.0, 0, 3.9), Vector3(-19.2, 1.1, 2.0))
		"produce":
			aim_player(Vector3(13.6, 0, 3.8), Vector3(11.0, 0.0, 0.0))
		"checkout":
			place_player(Vector3(4.5, 0, 10.0), 65.0, -4.0)
