extends TestCase
## Line of sight and camera visibility against real physics.

const AiTestWorld := preload("res://tests/monster/ai_test_world.gd")

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
	var player: Player = world.add_player(Vector3.ZERO, Vector3(0, 0, -10))
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
	var player: Player = world.add_player(Vector3.ZERO, Vector3(0, 0, -10))
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


func test_finds_camera_on_plain_player_stub() -> void:
	var player := Player.new()
	var camera := Camera3D.new()
	player.add_child(camera)
	world.add_child(player)
	assert_eq(Perception.find_player_camera(player), camera)
