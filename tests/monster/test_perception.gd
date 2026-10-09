extends TestCase
## Line of sight and camera visibility against real physics.

const AiTestWorld := preload("res://tests/monster/ai_test_world.gd")
const FakePlayer := preload("res://tests/monster/fake_player.gd")

var world: Node3D


func before_each() -> void:
	world = AiTestWorld.create(tree)


func after_each() -> void:
	world.dispose()


func _space() -> PhysicsDirectSpaceState3D:
	return world.get_world_3d().direct_space_state


func test_wall_blocks_line_of_sight() -> void:
	world.add_box(Vector3(0.0, 1.5, 0.0), Vector3(4.0, 3.0, 0.3))
	await world.settle()
	assert_false(Perception.has_line_of_sight(_space(), Vector3(0, 1.5, -3), Vector3(0, 1.5, 3)), "wall between")
	assert_true(Perception.has_line_of_sight(_space(), Vector3(5, 1.5, -3), Vector3(5, 1.5, 3)), "beside the wall")


func test_only_world_layer_blocks_sight() -> void:
	world.add_box(Vector3(0.0, 1.5, 0.0), Vector3(4.0, 3.0, 0.3), Catalog.LAYER_NPC)
	world.add_box(Vector3(0.0, 1.5, 1.0), Vector3(4.0, 3.0, 0.3), Catalog.LAYER_MONSTER)
	await world.settle()
	assert_true(Perception.has_line_of_sight(_space(), Vector3(0, 1.5, -3), Vector3(0, 1.5, 3)))


func test_point_visible_in_front_of_camera() -> void:
	var player: FakePlayer = world.add_player(Vector3.ZERO, Vector3(0, 0, -10))
	await world.settle()
	var camera := Perception.find_player_camera(player)
	assert_true(camera != null, "camera found")
	assert_true(Perception.is_point_visible_to_camera(camera, Vector3(0, 1.2, -10)), "ahead")
	assert_true(Perception.is_point_visible_to_camera(camera, Vector3(4, 1.2, -10)), "ahead, off centre")
	assert_false(Perception.is_point_visible_to_camera(camera, Vector3(0, 1.2, 10)), "behind")
	assert_false(Perception.is_point_visible_to_camera(camera, Vector3(12, 1.2, 0)), "to the side")
	assert_false(Perception.is_point_visible_to_camera(camera, Vector3(0, 1.2, -40)), "beyond 30 m")
	assert_true(Perception.is_point_visible_to_camera(camera, Vector3(0, 1.2, -40), 50.0), "custom max distance")


func test_wall_hides_point_from_camera() -> void:
	var player: FakePlayer = world.add_player(Vector3.ZERO, Vector3(0, 0, -10))
	world.add_box(Vector3(0.0, 1.5, -5.0), Vector3(6.0, 3.0, 0.3))
	await world.settle()
	var camera := Perception.find_player_camera(player)
	assert_false(Perception.is_point_visible_to_camera(camera, Vector3(0, 1.2, -10)))
	var points := Perception.body_points(Vector3(0, 0, -10), 2.6)
	assert_false(Perception.is_any_point_visible(camera, points), "the wall hides the whole body")


func test_body_points_cover_feet_to_head() -> void:
	var points := Perception.body_points(Vector3(1, 0, 2), 2.0)
	assert_eq(points.size(), 3)
	assert_near(points[0].y, 0.4)
	assert_near(points[2].y, 1.8)


func test_finds_camera_when_get_camera_returns_null() -> void:
	var player := Player.new()   # the foundation stub returns null from get_camera()
	var camera := Camera3D.new()
	player.add_child(camera)
	assert_eq(Perception.find_player_camera(player), camera, "falls back to the Camera3D child")
	player.free()


# --- Rule 3: what a player can actually make out ------------------------------------

func test_view_center_is_the_middle_seventy_percent() -> void:
	var player: FakePlayer = world.add_player(Vector3.ZERO, Vector3(0, 0, -10))
	await world.settle()
	var camera := Perception.find_player_camera(player)
	var ahead := Vector3(0, 1.6, -10)
	assert_true(Perception.is_point_in_view_center(camera, ahead, 0.7), "straight ahead")
	# 42 degrees off the axis: inside the 95-degree frustum, outside its middle 70%.
	var edge := Vector3(10.0 * tan(deg_to_rad(42.0)), 1.6, -10)
	assert_true(camera.is_position_in_frustum(edge), "still on screen")
	assert_false(Perception.is_point_in_view_center(camera, edge, 0.7), "at the edge of the screen")
	assert_true(Perception.is_point_in_view_center(camera, edge, 1.0), "the whole frame counts it")
	assert_false(Perception.is_point_in_view_center(camera, Vector3(0, 1.6, 10), 0.7), "behind")


func test_spotlight_cone_and_range() -> void:
	var light := SpotLight3D.new()
	light.spot_range = 18.0
	light.spot_angle = 28.0
	world.add_child(light)
	light.global_position = Vector3(0, 1.6, 0)   # looks down -Z
	assert_true(Perception.is_point_in_spotlight(light, Vector3(0, 1.2, -10)), "in the beam")
	assert_true(Perception.is_point_in_spotlight(light, Vector3(10.0 * tan(deg_to_rad(25.0)), 1.6, -10)), "inside 28 degrees")
	assert_false(Perception.is_point_in_spotlight(light, Vector3(10.0 * tan(deg_to_rad(32.0)), 1.6, -10)), "outside the cone")
	assert_false(Perception.is_point_in_spotlight(light, Vector3(0, 1.6, -19)), "beyond its range")
	light.visible = false
	assert_false(Perception.is_point_in_spotlight(light, Vector3(0, 1.2, -10)), "switched off")
	assert_false(Perception.is_point_in_spotlight(null, Vector3(0, 1.2, -10)), "no flashlight")


func test_lit_by_a_store_light_that_is_on() -> void:
	world.add_store_light(Vector3(0, 3.5, -10))
	world.add_store_light(Vector3(10, 3.5, -10), false)
	assert_true(Perception.is_point_lit(tree, Vector3(0, 1.0, -10), null), "under a lit fixture")
	assert_true(Perception.is_point_lit(tree, Vector3(3, 1.0, -10), null), "within its range")
	assert_false(Perception.is_point_lit(tree, Vector3(0, 1.0, -20), null), "out of its range")
	assert_false(Perception.is_point_lit(tree, Vector3(10, 1.0, -10), null), "under a dead fixture")


func test_lit_by_the_flashlight() -> void:
	var player: FakePlayer = world.add_player(Vector3.ZERO, Vector3(0, 0, -10))
	await world.settle()
	var flashlight := Perception.find_flashlight(player)
	assert_true(flashlight != null, "the player's flashlight is found")
	assert_true(Perception.is_point_lit(tree, Vector3(0, 1.0, -10), flashlight), "in the beam")
	world.set_flashlight(player, false)
	assert_false(Perception.is_point_lit(tree, Vector3(0, 1.0, -10), flashlight), "flashlight off, no store light")
