extends TestCase
## Held tool / viewmodel swap and the flashlight toggle.

const Fixture := preload("res://tests/player/player_fixture.gd")

var world: Node3D
var player: Player


func before_each() -> void:
	world = Fixture.make_world(tree)
	player = Fixture.add_player(world)
	await wait_physics_frames(2)


func after_each() -> void:
	Input.action_release(&"flashlight")
	world.free()


func _viewmodel() -> PlayerViewmodel:
	return player.get_node("Head/Camera3D/Viewmodel") as PlayerViewmodel


func test_empty_handed_shows_flashlight_viewmodel() -> void:
	assert_eq(_viewmodel().current_id, &"flashlight")
	assert_true(_viewmodel().get_child_count() > 0, "a model (or placeholder) is shown")


func test_set_held_tool_swaps_viewmodel_and_emits() -> void:
	var got: Array[StringName] = []
	var record := func(id: StringName) -> void: got.append(id)
	Events.held_tool_changed.connect(record)
	player.set_held_tool(&"mop")
	assert_eq(player.held_tool, &"mop")
	assert_true(player.has_tool(&"mop"))
	assert_false(player.has_tool(&"keys"))
	assert_true(player.has_tool(&""), "no tool needed")
	assert_eq(_viewmodel().current_id, &"mop")
	player.set_held_tool(&"")
	Events.held_tool_changed.disconnect(record)
	assert_eq(_viewmodel().current_id, &"flashlight")
	assert_eq(got, [&"mop", &""] as Array[StringName])


func test_flashlight_toggle_action() -> void:
	var states: Array[bool] = []
	var record := func(on: bool) -> void: states.append(on)
	Events.flashlight_toggled.connect(record)
	assert_true(player.flashlight_on, "starts on")
	Input.action_press(&"flashlight")
	await wait_physics_frames(3)
	Input.action_release(&"flashlight")
	await wait_physics_frames(2)
	Events.flashlight_toggled.disconnect(record)
	assert_false(player.flashlight_on)
	assert_eq(states, [false] as Array[bool])
	await wait_frames(2)
	var light := player.get_node("Head/Camera3D/Flashlight") as SpotLight3D
	assert_false(light.visible, "light hidden when off")


func test_flashlight_flickers_near_monster() -> void:
	# Deterministic: the player's own _process is off, time is stepped by hand, RNG seeded.
	player.set_process(false)
	player.flicker_rng.seed = 1234
	var monster := Node3D.new()
	world.add_child(monster)
	var previous := GameState.monster
	GameState.monster = monster
	var light := player.get_node("Head/Camera3D/Flashlight") as SpotLight3D

	monster.global_position = player.global_position + Vector3(0, 0, -20.0)
	assert_near(player.get_monster_disturbance(), 0.0, 0.0001, "no disturbance beyond 12 m")
	for i in 20:
		player.update_flashlight(0.05)
		assert_near(light.light_energy, Player.FLASHLIGHT_ENERGY, 0.0001, "steady when far")

	monster.global_position = player.global_position + Vector3(0, 0, -1.0)
	assert_near(player.get_monster_disturbance(), 1.0 - 1.0 / Player.FLICKER_RADIUS, 0.0001)
	var dimmed := 0
	for i in 40:
		player.update_flashlight(0.05)
		if light.light_energy < Player.FLASHLIGHT_ENERGY * 0.5:
			dimmed += 1
	GameState.monster = previous
	assert_true(dimmed > 0, "flashlight dipped while the monster was 1 m away")
	assert_true(dimmed < 40, "and recovered between dips")
