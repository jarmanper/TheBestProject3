extends TestCase
## scenes/game.tscn: structure per docs/ARCHITECTURE.md §6, spawning, mouse look through the
## half-resolution SubViewportContainer, pausing and the end screen.

const GAME_SCENE := "res://scenes/game.tscn"

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


func test_mouse_look_through_the_subviewport_container() -> void:
	var player := GameState.player as Player
	var head := player.get_node("Head") as Node3D
	var yaw := player.rotation.y
	var pitch := head.rotation.x
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(640, 360)
	motion.relative = Vector2(80, 40)
	motion.screen_relative = Vector2(80, 40)
	tree.root.push_input(motion)
	await wait_frames(1)
	var sensitivity := GameState.mouse_sensitivity
	assert_near(angle_difference(yaw, player.rotation.y), -80.0 * sensitivity, 0.0001, "yaw turned by screen pixels")
	assert_near(head.rotation.x, pitch - 40.0 * sensitivity, 0.0001, "pitch turned by screen pixels")


func test_pause_and_resume() -> void:
	game.pause_game()
	assert_eq(game.state, Game.State.PAUSED)
	assert_true(tree.paused)
	assert_true(game.get_node("Menus/PauseMenu").visible, "pause menu shown")
	game.resume_game()
	assert_eq(game.state, Game.State.PLAYING)
	assert_false(tree.paused)
	assert_false(game.get_node("Menus/PauseMenu").visible)


func test_pause_action_toggles() -> void:
	var press := InputEventAction.new()
	press.action = &"pause"
	press.pressed = true
	tree.root.push_input(press)
	assert_eq(game.state, Game.State.PAUSED, "pause action pauses")
	tree.root.push_input(press)
	assert_eq(game.state, Game.State.PLAYING, "pause action resumes")


func test_lost_pointer_lock_pauses() -> void:
	# Headless never captures the mouse, so pretend it was captured once (as after CLOCK IN):
	# seeing it uncaptured while playing means the pointer lock was lost (web Esc, alt-tab).
	game._had_capture = true
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
