extends TestCase
## Plays the real game in the store the way a person would, through the input actions:
## take a tool from its rack, do a task that needs it (holding interact), hide in a break-room
## locker and leave it, and talk to the manager. Catches seams the unit tests cannot: real
## props and colliders in the way of the interaction ray, wall-mounted racks, hold timing.
## The monster and coworkers are frozen so nothing interferes.

const GAME := "res://scenes/game.tscn"

var game: Game
var player: Player


func before_each() -> void:
	game = (load(GAME) as PackedScene).instantiate()
	game.capture_mouse_on_start = false
	tree.root.add_child(game)
	for i in 600:
		if game.state == Game.State.PLAYING:
			break
		await tree.process_frame
	player = GameState.player as Player
	for node in tree.get_nodes_in_group(&"coworker") + tree.get_nodes_in_group(&"monster"):
		node.process_mode = Node.PROCESS_MODE_DISABLED
		(node as Node3D).global_position = Vector3(40, -30, 40)


func after_each() -> void:
	Input.action_release(&"interact")
	game.free()
	await tree.process_frame


## Stands the player at `feet` looking at `target`, and lets physics settle.
func _stand_and_look(feet: Vector3, target: Vector3) -> void:
	player.global_position = feet
	player.velocity = Vector3.ZERO
	await wait_physics_frames(2)
	var eye := player.get_eye_position()
	var to := target - eye
	player.rotation.y = atan2(-to.x, -to.z)
	(player.get_node("Head") as Node3D).rotation.x = atan2(to.y, Vector2(to.x, to.z).length())
	await wait_physics_frames(3)


func _press_interact(hold_seconds := 0.0) -> void:
	Input.action_press(&"interact")
	await wait_physics_frames(2)
	if hold_seconds > 0.0:
		await tree.create_timer(hold_seconds).timeout
	Input.action_release(&"interact")
	await wait_physics_frames(3)


static func _shape_center(area: Area3D) -> Vector3:
	for child in area.get_children():
		if child is CollisionShape3D:
			return (child as CollisionShape3D).global_position
	return area.global_position


func test_take_a_tool_and_do_its_task() -> void:
	# Make sure a mop task is open (the night picks six at random).
	var station: TaskStation = null
	for node: TaskStation in tree.get_nodes_in_group(&"task_station"):
		if node.required_tool == &"mop" and node.zone == &"aisle_3":
			station = node
	assert_true(station != null, "the aisle 3 spill station exists")
	if station == null:
		return
	if not station.is_active():
		Tasks.add_manager_task(station, 600.0)
	var rack := ToolPickup.find_rack(tree, &"mop")
	await _stand_and_look(rack.global_position + rack.global_basis.z * 0.9 - Vector3.UP * rack.global_position.y,
		_shape_center(rack))
	await _press_interact()
	assert_eq(player.held_tool, &"mop", "took the mop from its wall rack in the janitor closet")
	assert_false(rack.has_tool, "the rack is empty")

	var completed: Array = []
	var record := func(task: TaskData, by: Node) -> void: completed.append([task, by])
	Events.task_completed.connect(record)
	await _stand_and_look(station.get_work_position(), _shape_center(station))
	await _press_interact(station.hold_time + 0.6)
	Events.task_completed.disconnect(record)
	assert_eq(completed.size(), 1, "holding interact on the spill completed the task")
	if completed.size() == 1:
		assert_true(completed[0][1] == player, "completed by the player")
	assert_false(station.is_active(), "the spill is gone")


func test_hide_in_a_locker_and_come_out() -> void:
	var locker: HidingSpot = null
	for spot: HidingSpot in tree.get_nodes_in_group(&"hiding_spot"):
		if spot.spot_kind == &"locker":
			locker = spot
			break
	await _stand_and_look(locker.get_exit_position(), _shape_center(locker))
	await _press_interact()
	assert_true(player.is_hidden, "hid in the locker")
	assert_true(locker.is_occupied(), "the locker knows it is occupied")
	await tree.create_timer(0.9).timeout
	await _press_interact()
	assert_false(player.is_hidden, "came back out")
	var floor_point := NavigationServer3D.map_get_closest_point(player.get_world_3d().navigation_map, player.global_position)
	assert_true(Vector2(floor_point.x - player.global_position.x, floor_point.z - player.global_position.z).length() < 0.3,
		"standing on walkable floor after leaving")


func test_talk_to_the_manager() -> void:
	var spot := tree.get_first_node_in_group(&"manager_spot") as Node3D
	var talked: Array = []
	var record := func(text: String, _duration: float) -> void: talked.append(text)
	Events.subtitle.connect(record)
	await _stand_and_look(spot.global_position + Vector3(0, 0, 2.3), spot.global_position + Vector3(0, 1.3, 0))
	await _press_interact()
	Events.subtitle.disconnect(record)
	assert_eq(talked.size(), 1, "the manager answered across the desk")
