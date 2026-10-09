extends TestCase
## Movement + noise levels, driven through the real input actions.

const Fixture := preload("res://tests/player/player_fixture.gd")

var world: Node3D
var player: Player


func before_each() -> void:
	world = Fixture.make_world(tree)
	player = Fixture.add_player(world)
	await wait_physics_frames(2)


func after_each() -> void:
	for action in [&"move_forward", &"sprint", &"interact"]:
		Input.action_release(action)
	world.free()


func _horizontal_speed() -> float:
	return Vector2(player.velocity.x, player.velocity.z).length()


func test_still_player_is_silent() -> void:
	assert_eq(player.get_noise_level(), 0.0)


func test_walking_speed_and_noise() -> void:
	Input.action_press(&"move_forward")
	await wait_physics_frames(40)
	assert_near(_horizontal_speed(), Player.WALK_SPEED, 0.05, "walk speed")
	assert_near(player.get_noise_level(), 0.35, 0.001, "walking noise")
	assert_true(player.global_position.z < -0.5, "moved forward (-Z)")


func test_sprinting_speed_and_noise() -> void:
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await wait_physics_frames(40)
	assert_near(_horizontal_speed(), Player.SPRINT_SPEED, 0.05, "sprint speed")
	assert_near(player.get_noise_level(), 1.0, 0.001, "sprinting noise")
	assert_true(player.stamina < player.max_stamina, "sprinting drained stamina")


func test_acceleration_is_smooth() -> void:
	Input.action_press(&"move_forward")
	await wait_physics_frames(2)
	var early := _horizontal_speed()
	assert_true(early > 0.0 and early < Player.WALK_SPEED, "speed ramps up (got %s)" % early)


func test_input_disabled_stops_movement() -> void:
	player.input_enabled = false
	Input.action_press(&"move_forward")
	await wait_physics_frames(20)
	assert_near(_horizontal_speed(), 0.0, 0.01)


func test_hidden_player_is_silent() -> void:
	var spot := Fixture.add_hiding_spot(world, Vector3(3, 0, 0))
	player.velocity = Vector3(3, 0, 0)
	player.enter_hiding(spot)
	assert_eq(player.get_noise_level(), 0.0)
	player.exit_hiding()


func test_layers_and_shape() -> void:
	assert_eq(player.collision_layer, Catalog.LAYER_PLAYER)
	assert_eq(player.collision_mask, Catalog.LAYER_WORLD | Catalog.LAYER_NPC | Catalog.LAYER_MONSTER, "player bumps into the disguised monster like a coworker")
	var capsule := (player.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	assert_near(capsule.height, 1.8)
	assert_near(capsule.radius, 0.35)
	assert_near(player.get_camera().fov, 95.0, 0.01)
	assert_true(player.is_in_group(&"player"))
	assert_eq(GameState.player, player)
