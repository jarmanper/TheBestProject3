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
	var monster := Node3D.new()
	world.add_child(monster)
	monster.global_position = player.global_position + Vector3(0, 0, -1.0)
	var previous := GameState.monster
	GameState.monster = monster
	var light := player.get_node("Head/Camera3D/Flashlight") as SpotLight3D
	var dimmed := false
	for i in 40:
		await wait_frames(1)
		if light.light_energy < Player.FLASHLIGHT_ENERGY * 0.5:
			dimmed = true
	GameState.monster = previous
	assert_true(dimmed, "flashlight dipped while the monster was 1 m away")
