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


func test_camera_blends_to_hide_point() -> void:
	player.enter_hiding(spot)
	await tree.create_timer(Player.HIDE_BLEND_TIME + 0.2).timeout
	var hide_point := spot.get_node("HidePoint") as Node3D
	assert_near(player.get_camera().global_position.distance_to(hide_point.global_position), 0.0, 0.02)


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


func test_interact_while_hidden_leaves_the_spot() -> void:
	player.enter_hiding(spot)
	await wait_physics_frames(2)
	Input.action_press(&"interact")
	await wait_physics_frames(3)
	Input.action_release(&"interact")
	assert_false(player.is_hidden, "pressing interact while hidden leaves")
