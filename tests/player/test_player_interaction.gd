extends TestCase
## Interaction ray, prompts and holds per the Interactable contract.

const Fixture := preload("res://tests/player/player_fixture.gd")


class FakeStation extends Interactable:
	var allowed := true
	var started := 0
	var stopped := 0
	var used := 0

	func get_prompt(_player: Node) -> String:
		return prompt_text if allowed else "Needs: Mop"

	func can_interact(_player: Node) -> bool:
		return allowed

	func interact(_player: Node) -> void:
		used += 1

	func hold_started(_player: Node) -> void:
		started += 1

	func hold_stopped(_player: Node) -> void:
		stopped += 1


var world: Node3D
var player: Player
var prompts: Array[String] = []
var progress: Array[float] = []


func _on_prompt(text: String) -> void:
	prompts.append(text)


func _on_progress(fraction: float) -> void:
	progress.append(fraction)


func before_each() -> void:
	world = Fixture.make_world(tree)
	player = Fixture.add_player(world)
	prompts.clear()
	progress.clear()
	Events.interaction_prompt_changed.connect(_on_prompt)
	Events.interaction_progress.connect(_on_progress)
	await wait_physics_frames(2)


func after_each() -> void:
	Input.action_release(&"interact")
	Events.interaction_prompt_changed.disconnect(_on_prompt)
	Events.interaction_progress.disconnect(_on_progress)
	world.free()


## A 0.6 m box Interactable straight ahead of the camera (player faces -Z, eye at 1.6 m).
func _add_station(distance: float, hold := 0.0) -> FakeStation:
	var station := FakeStation.new()
	station.prompt_text = "Mop spill"
	station.hold_time = hold
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 0.6, 0.6)
	shape.shape = box
	station.add_child(shape)
	station.position = Vector3(0, 1.6, -distance)
	world.add_child(station)
	return station


func _last_prompt() -> String:
	return prompts[-1] if not prompts.is_empty() else ""


func test_prompt_for_station_in_reach() -> void:
	_add_station(1.5)
	await wait_physics_frames(3)
	assert_eq(_last_prompt(), "[E] Mop spill")


func test_missing_tool_prompt_has_no_key_hint() -> void:
	var station := _add_station(1.5)
	station.allowed = false
	await wait_physics_frames(3)
	assert_eq(_last_prompt(), "Needs: Mop")


func test_out_of_reach_has_no_prompt() -> void:
	_add_station(3.0)
	await wait_physics_frames(3)
	assert_eq(_last_prompt(), "")


func test_wall_blocks_the_ray() -> void:
	_add_station(1.8)
	Fixture.add_box(world, Vector3(0, 1.5, -0.9), Vector3(2, 3, 0.2))
	await wait_physics_frames(3)
	assert_eq(_last_prompt(), "")


func test_instant_interact() -> void:
	var station := _add_station(1.5)
	await wait_physics_frames(2)
	Input.action_press(&"interact")
	await wait_physics_frames(3)
	Input.action_release(&"interact")
	assert_eq(station.used, 1)


func test_hold_completes_and_reports_progress() -> void:
	var station := _add_station(1.5, 0.3)
	await wait_physics_frames(2)
	Input.action_press(&"interact")
	# Holds advance with the fixed physics step: 0.3 s = 18 ticks. Wait for the outcome.
	for i in 60:
		await tree.physics_frame
		if station.used > 0:
			break
	await wait_physics_frames(2)
	Input.action_release(&"interact")
	assert_eq(station.started, 1, "hold_started once")
	assert_eq(station.used, 1, "interact after the hold filled")
	assert_eq(station.stopped, 0, "completed holds are not 'stopped'")
	assert_true(progress.size() >= 3, "progress reported")
	assert_true(progress.has(-1.0), "bar hidden at the end")
	var max_fraction := 0.0
	for value in progress:
		max_fraction = maxf(max_fraction, value)
	assert_true(max_fraction > 0.5, "progress filled")


func test_releasing_cancels_the_hold() -> void:
	var station := _add_station(1.5, 2.0)
	await wait_physics_frames(2)
	Input.action_press(&"interact")
	await wait_physics_frames(10)
	Input.action_release(&"interact")
	await wait_physics_frames(3)
	assert_eq(station.started, 1)
	assert_eq(station.stopped, 1, "hold_stopped on release")
	assert_eq(station.used, 0)
	assert_eq(progress[-1], -1.0)


func test_cannot_hold_without_tool() -> void:
	var station := _add_station(1.5, 0.2)
	station.allowed = false
	await wait_physics_frames(2)
	Input.action_press(&"interact")
	await wait_physics_frames(25)
	Input.action_release(&"interact")
	assert_eq(station.started, 0)
	assert_eq(station.used, 0)
