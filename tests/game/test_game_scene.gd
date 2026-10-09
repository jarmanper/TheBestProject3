extends TestCase
## scenes/game.tscn: structure per docs/ARCHITECTURE.md §6, spawning, mouse look through the
## half-resolution SubViewportContainer, pausing and the end screen.

const GAME_SCENE := "res://scenes/game.tscn"


class FakeStation extends Interactable:
	var used := 0

	func interact(_player: Node) -> void:
		used += 1


var game: Game


func before_each() -> void:
	game = (load(GAME_SCENE) as PackedScene).instantiate()
	game.capture_mouse_on_start = false
	tree.root.add_child(game)
	for i in 300:
		if game.state == Game.State.PLAYING:
			break
		await tree.process_frame


func after_each() -> void:
	Input.action_release(&"interact")
	game.free()
	tree.paused = false
	GameState.night_running = false


func test_starts_playing() -> void:
	assert_eq(game.state, Game.State.PLAYING)
	assert_true(GameState.night_running, "night started")
	assert_eq(GameState.get_clock_text(), "12:00 AM")


func test_structure_matches_contract() -> void:
	var view := game.get_node("WorldView") as SubViewportContainer
	assert_true(view.stretch, "stretch on")
	assert_eq(view.stretch_shrink, 2, "half resolution 3D")
	assert_eq(view.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "nearest upscale")
	var viewport := game.get_node("WorldView/SubViewport") as SubViewport
	assert_true(viewport.audio_listener_enable_3d, "3D audio listener in the world viewport")
	var world := game.get_node("WorldView/SubViewport/World") as Node3D
	assert_eq(GameState.world_root, world)
	assert_true(world.get_node_or_null(^"Level") != null, "level instanced as Level")
	assert_eq((game.get_node("PostFX") as CanvasLayer).layer, 1)
	assert_eq((game.get_node("HUD") as CanvasLayer).layer, 2)
	assert_eq((game.get_node("Menus") as CanvasLayer).layer, 3)


func test_player_at_spawn_facing_the_door() -> void:
	var player := GameState.player as Player
	assert_true(player != null and game.is_ancestor_of(player), "player spawned in the game world")
	assert_near(player.global_position.x, 6.0, 0.2)
	assert_near(player.global_position.z, -12.5, 0.2)
	assert_true(-player.global_transform.basis.z.z > 0.9, "facing +Z")
	assert_eq(player.get_viewport(), game.get_node("WorldView/SubViewport"), "player renders in the SubViewport")


func _motion(relative: Vector2) -> InputEventMouseMotion:
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(640, 360)
	motion.relative = relative
	motion.screen_relative = relative
	return motion


func _left_click(pressed := true) -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = Vector2(640, 360)
	click.pressed = pressed
	return click


func test_mouse_look_through_the_subviewport_container() -> void:
	# Capture is simulated in tests (headless cannot capture); the game starts captured.
	assert_true(game.is_mouse_captured(), "playing implies a captured pointer")
	var player := GameState.player as Player
	var head := player.get_node("Head") as Node3D
	var yaw := player.rotation.y
	var pitch := head.rotation.x
	tree.root.push_input(_motion(Vector2(80, 40)))
	await wait_frames(1)
	var sensitivity := GameState.mouse_sensitivity
	assert_near(angle_difference(yaw, player.rotation.y), -80.0 * sensitivity, 0.0001, "yaw turned by screen pixels")
	assert_near(head.rotation.x, pitch - 40.0 * sensitivity, 0.0001, "pitch turned by screen pixels")


func test_uncaptured_motion_is_ignored() -> void:
	var player := GameState.player as Player
	var head := player.get_node("Head") as Node3D
	var yaw := player.rotation.y
	var pitch := head.rotation.x
	game._simulated_captured = false   # the browser dropped the pointer lock
	tree.root.push_input(_motion(Vector2(300, 120)))
	assert_near(player.rotation.y, yaw, 0.00001, "no yaw from a free cursor")
	assert_near(head.rotation.x, pitch, 0.00001, "no pitch from a free cursor")


func test_pause_and_resume() -> void:
	game.pause_game()
	assert_eq(game.state, Game.State.PAUSED)
	assert_true(tree.paused)
	assert_true(game.get_node("Menus/PauseMenu").visible, "pause menu shown")
	assert_false(game.is_mouse_captured(), "pointer released while paused")
	game.resume_game()
	assert_eq(game.state, Game.State.PLAYING)
	assert_false(tree.paused)
	assert_true(game.is_mouse_captured())
	assert_false(game.get_node("Menus/PauseMenu").visible)


func test_resume_waits_for_a_click_when_capture_is_refused() -> void:
	var menu := game.get_node("Menus/PauseMenu") as PauseMenu
	game.pause_game()
	game.simulated_capture_refused = true   # web: Esc is no user gesture / ~1 s re-lock cooldown
	game.resume_game()
	assert_eq(game.state, Game.State.RESUMING, "waits for capture instead of playing")
	assert_true(tree.paused, "world stays paused until capture is observed")
	assert_true(menu.is_click_prompt_visible(), "CLICK TO RESUME shown")
	tree.root.push_input(_left_click())
	await wait_frames(2)
	assert_eq(game.state, Game.State.RESUMING, "still waiting while the browser refuses")
	game.simulated_capture_refused = false
	tree.root.push_input(_left_click())
	assert_eq(game.state, Game.State.PLAYING, "the click captured the pointer")
	assert_false(tree.paused)
	assert_false(menu.visible)


func test_pause_key_while_waiting_for_capture_opens_the_menu() -> void:
	var menu := game.get_node("Menus/PauseMenu") as PauseMenu
	game.pause_game()
	game.simulated_capture_refused = true
	game.resume_game()
	var press := InputEventAction.new()
	press.action = &"pause"
	press.pressed = true
	tree.root.push_input(press)
	assert_eq(game.state, Game.State.PAUSED)
	assert_true(menu.visible and not menu.is_click_prompt_visible(), "back to the pause menu")


func test_recapture_click_does_not_interact() -> void:
	var player := GameState.player as Player
	var station := FakeStation.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 0.6, 0.6)
	shape.shape = box
	station.add_child(shape)
	game.get_node("WorldView/SubViewport/World").add_child(station)
	station.global_position = player.get_eye_position() - player.global_transform.basis.z * 1.5
	await wait_physics_frames(3)
	game.pause_game()
	game.simulated_capture_refused = true
	game.resume_game()
	game.simulated_capture_refused = false
	# The left button is `interact`: hold it as the browser would while the click arrives.
	Input.action_press(&"interact")
	tree.root.push_input(_left_click())
	assert_eq(game.state, Game.State.PLAYING)
	await wait_physics_frames(6)
	assert_eq(station.used, 0, "the click that resumed the game did not interact")
	Input.action_release(&"interact")
	tree.root.push_input(_left_click(false))
	await wait_physics_frames(2)
	Input.action_press(&"interact")
	await wait_physics_frames(3)
	Input.action_release(&"interact")
	assert_eq(station.used, 1, "a fresh click interacts")
	station.queue_free()


func test_pause_action_toggles() -> void:
	var press := InputEventAction.new()
	press.action = &"pause"
	press.pressed = true
	tree.root.push_input(press)
	assert_eq(game.state, Game.State.PAUSED, "pause action pauses")
	tree.root.push_input(press)
	assert_eq(game.state, Game.State.PLAYING, "pause action resumes")


func test_lost_pointer_lock_pauses() -> void:
	# The browser drops the lock on Esc (and eats the key): playing without capture pauses.
	game._simulated_captured = false
	await wait_frames(2)
	assert_eq(game.state, Game.State.PAUSED, "lost capture pauses the game")


func test_mouse_is_not_forwarded_while_paused() -> void:
	var player := GameState.player as Player
	game.pause_game()
	var yaw := player.rotation.y
	var motion := InputEventMouseMotion.new()
	motion.screen_relative = Vector2(200, 0)
	tree.root.push_input(motion)
	await wait_frames(1)
	assert_near(player.rotation.y, yaw, 0.00001)


func test_night_end_shows_end_screen() -> void:
	GameState.end_night(&"fired")
	assert_eq(game.state, Game.State.ENDED)
	assert_true(tree.paused, "world paused")
	var screen := game.get_node("Menus/EndScreen") as EndScreen
	assert_true(screen.visible)
	assert_eq(screen.get_title_text(), "YOU'RE FIRED")
	assert_false(game.get_node("HUD").visible, "HUD hidden behind the end screen")


func _sounds_during(action: Callable) -> Array[StringName]:
	var played: Array[StringName] = []
	var record := func(id: StringName) -> void: played.append(id)
	Sfx.played.connect(record)
	action.call()
	Sfx.played.disconnect(record)
	return played


func test_shift_end_bell_rings_at_six_am() -> void:
	var played := _sounds_during(func() -> void: GameState.end_night(&"fired"))
	assert_true(&"shift_end_bell" in played, "the bell rings for YOU'RE FIRED: %s" % [played])


func test_shift_end_bell_rings_on_a_win() -> void:
	var played := _sounds_during(func() -> void: GameState.end_night(&"win"))
	assert_true(&"shift_end_bell" in played, "the bell rings for SHIFT COMPLETE: %s" % [played])


func test_no_shift_end_bell_for_a_death() -> void:
	var played := _sounds_during(func() -> void: GameState.end_night(&"dead"))
	assert_false(&"shift_end_bell" in played, "no bell when the player died")


func test_ambient_scares_run_in_the_game() -> void:
	var scares := game.get_node_or_null(^"AmbientScares") as AmbientScares
	assert_true(scares != null, "the game has an ambient-scares node")
	if scares:
		assert_eq(scares.process_mode, Node.PROCESS_MODE_PAUSABLE, "quiet while paused")


func test_missing_actor_scenes_are_skipped() -> void:
	var world := game.get_node("WorldView/SubViewport/World")
	var expected := 2   # Level + Player
	for key in [&"coworker", &"monster", &"store_manager"]:
		if ResourceLoader.exists(Catalog.SCENES[key]):
			expected += 3 if key == &"coworker" else 1
	var actors := 0
	for child in world.get_children():
		if not (child is AudioStreamPlayer3D):
			actors += 1
	assert_eq(actors, expected, "only existing actor scenes are spawned")
