extends TestCase

const Fixture := preload("res://tests/player/player_fixture.gd")

var world: Node3D
var player: Player
var spot: HidingSpot


func before_each() -> void:
	world = Fixture.make_world(tree)
	player = Fixture.add_player(world)
	spot = Fixture.add_hiding_spot(world, Vector3(3, 0, 0))
	await wait_physics_frames(2)


func after_each() -> void:
	Input.action_release(&"move_forward")
	Input.action_release(&"interact")
	world.free()


func test_enter_hiding_state_signal_and_stat() -> void:
	GameState.start_night()
	GameState.night_running = false
	var hid: Array = []
	var record := func(s: Node3D) -> void: hid.append(s)
	Events.player_hid.connect(record)
	player.enter_hiding(spot)
	Events.player_hid.disconnect(record)
	assert_true(player.is_hidden)
	assert_eq(player.current_hiding_spot, spot)
	assert_eq(hid, [spot])
	assert_eq(GameState.stats["times_hidden"], 1)


func test_hidden_player_cannot_move_and_has_no_collision() -> void:
	player.enter_hiding(spot)
	await wait_physics_frames(2)
	var shape := player.get_node("CollisionShape3D") as CollisionShape3D
	assert_true(shape.disabled, "collision disabled while hidden")
	var start := player.global_position
	Input.action_press(&"move_forward")
	await wait_physics_frames(15)
	Input.action_release(&"move_forward")
	assert_near(player.global_position.distance_to(start), 0.0, 0.01, "no movement while hidden")


## Waits for the condition, not a wall-clock timer. Physics frames tick at a fixed 60 Hz, so
## the 180-frame cap is ~3 s, far more than the 0.35 s blend.
func _wait_camera_at(target: Vector3) -> float:
	var camera := player.get_camera()
	for i in 180:
		if camera.global_position.distance_to(target) < 0.02:
			break
		await tree.physics_frame
	await tree.process_frame
	return camera.global_position.distance_to(target)


func test_camera_blends_to_hide_point() -> void:
	player.enter_hiding(spot)
	var hide_point := spot.get_node("HidePoint") as Node3D
	assert_true(player.get_camera().global_position.distance_to(hide_point.global_position) > 0.1, "starts at the eye")
	assert_near(await _wait_camera_at(hide_point.global_position), 0.0, 0.02, "blended to the hide point")


func test_hidden_look_is_limited() -> void:
	player.enter_hiding(spot)
	player.apply_look(Vector2(100000, 100000))
	assert_near(player.hide_look.x, -deg_to_rad(40.0), 0.001, "yaw limit")
	assert_near(player.hide_look.y, -deg_to_rad(25.0), 0.001, "pitch limit")
	player.apply_look(Vector2(-100000, -100000))
	assert_near(player.hide_look.x, deg_to_rad(40.0), 0.001)
	assert_near(player.hide_look.y, deg_to_rad(25.0), 0.001)


func test_exit_hiding_moves_to_exit_point() -> void:
	var unhid: Array = []
	var record := func(s: Node3D) -> void: unhid.append(s)
	Events.player_unhid.connect(record)
	player.enter_hiding(spot)
	player.exit_hiding()
	Events.player_unhid.disconnect(record)
	assert_false(player.is_hidden)
	assert_eq(player.current_hiding_spot, null)
	assert_eq(unhid, [spot])
	var exit_point := spot.get_node("ExitPoint") as Node3D
	assert_near(player.global_position.x, exit_point.global_position.x, 0.01)
	assert_near(player.global_position.z, exit_point.global_position.z, 0.01)
	await wait_physics_frames(2)
	var shape := player.get_node("CollisionShape3D") as CollisionShape3D
	assert_false(shape.disabled, "collision back on")


func test_real_spot_enters_and_tracks_the_occupant() -> void:
	spot.interact(player)
	assert_true(player.is_hidden)
	assert_eq(spot.occupant, player, "the spot owns its occupant")
	var stranger := Node.new()
	assert_false(spot.can_interact(stranger), "occupied for anyone else")
	stranger.free()


func test_interact_while_hidden_leaves_the_spot() -> void:
	spot.interact(player)
	await wait_physics_frames(2)
	Input.action_press(&"interact")
	await wait_physics_frames(3)
	Input.action_release(&"interact")
	assert_false(player.is_hidden, "pressing interact while hidden leaves")
	assert_eq(spot.occupant, null, "the spot cleared its occupant")


func test_dying_while_hidden_leaves_the_spot_first() -> void:
	var unhid: Array = []
	var record := func(s: Node3D) -> void: unhid.append(s)
	Events.player_unhid.connect(record)
	spot.interact(player)
	await _wait_camera_at((spot.get_node("HidePoint") as Node3D).global_position)
	player.take_damage(200.0, spot.global_position)
	Events.player_unhid.disconnect(record)
	assert_true(player.is_dead())
	assert_false(player.is_hidden, "out of the spot")
	assert_eq(player.current_hiding_spot, null)
	assert_eq(spot.occupant, null, "the spot is free again")
	assert_eq(unhid, [spot], "player_unhid emitted")
	# The camera returns to the (falling) head instead of staying in the locker.
	var camera := player.get_camera()
	for i in 180:
		if not camera.top_level and camera.global_position.y < 1.0:
			break
		await tree.physics_frame
	assert_false(camera.top_level, "camera re-attached to the head")
	assert_true(camera.global_position.y < 1.0, "camera fell with the body (y %s)" % camera.global_position.y)
