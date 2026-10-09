extends TestCase
## scenes/ambient_scares.gd: far-off bangs, creaks and cart rattles during the night.

const FakePlayer := preload("res://tests/monster/fake_player.gd")

var world: Node3D
var scares: AmbientScares
var player: Node3D
var played: Array[Dictionary] = []


func before_each() -> void:
	world = Node3D.new()
	tree.root.add_child(world)
	player = FakePlayer.new()
	world.add_child(player)
	player.global_position = Vector3(6, 0, -12.5)   # the break room
	scares = AmbientScares.new()
	scares.set_process(false)
	scares.rng.seed = 5
	world.add_child(scares)
	scares.scare_played.connect(_on_played)
	GameState.night_running = true


func after_each() -> void:
	GameState.night_running = false
	GameState.player = null
	world.free()


func _on_played(id: StringName, position: Vector3) -> void:
	played.append({"id": id, "position": position})


func _zone(zone_id: StringName, x0: float, x1: float, z0: float, z1: float) -> StoreZone:
	var zone := StoreZone.new()
	zone.zone_id = zone_id
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(x1 - x0, 3.0, z1 - z0)
	shape.shape = box
	zone.add_child(shape)
	world.add_child(zone)
	zone.global_position = Vector3((x0 + x1) * 0.5, 1.5, (z0 + z1) * 0.5)
	return zone


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func test_interval_and_distances() -> void:
	assert_eq(AmbientScares.INTERVAL, Vector2(30.0, 90.0), "one every 30-90 s")
	assert_true(AmbientScares.MIN_DISTANCE >= 6.0, "never within 6 m of the player")
	assert_true(AmbientScares.VOLUME_DB < 0.0, "quiet")
	for id: StringName in AmbientScares.SOUNDS:
		assert_true(Sfx.SOUNDS.has(id), "%s is a known sound" % id)


func test_spots_are_far_from_the_player_in_back_rooms_or_far_aisles() -> void:
	_zone(&"break_room", 2.0, 10.0, -16.0, -9.0)   # where the player is
	_zone(&"storage", -20.0, 2.0, -16.0, -9.0)
	_zone(&"aisle_1", -15.4, -12.6, -3.0, 7.0)
	_zone(&"checkout", -20.0, 6.0, 7.0, 16.0)     # the front: not a source
	for i in 200:
		var spot: Variant = scares.pick_spot(player.global_position)
		assert_true(spot != null, "found a spot")
		if spot == null:
			return
		assert_true(_flat(spot, player.global_position) >= AmbientScares.MIN_DISTANCE, "far from the player: %s" % spot)
		var zone_id := StoreZone.find_zone_id_at(tree, spot)
		assert_true(zone_id in [&"storage", &"aisle_1"], "from the back or a far aisle, not %s" % zone_id)


func test_no_spot_when_every_source_is_close() -> void:
	_zone(&"break_room", 2.0, 10.0, -16.0, -9.0)
	assert_eq(scares.pick_spot(player.global_position), null, "nothing far enough away")


func test_plays_one_noise_per_interval_only_during_the_night() -> void:
	_zone(&"storage", -20.0, 2.0, -16.0, -9.0)
	var first: float = scares.next_in
	assert_true(first >= AmbientScares.INTERVAL.x and first <= AmbientScares.INTERVAL.y)
	scares.tick(first - 0.1)
	assert_true(played.is_empty(), "not before its time")
	scares.tick(0.2)
	assert_eq(played.size(), 1, "one noise")
	assert_true(played[0]["id"] in AmbientScares.SOUNDS)
	assert_true(_flat(played[0]["position"], player.global_position) >= AmbientScares.MIN_DISTANCE)
	assert_true(scares.next_in >= AmbientScares.INTERVAL.x and scares.next_in <= AmbientScares.INTERVAL.y, "next one in 30-90 s")
	GameState.night_running = false
	scares._process(500.0)
	assert_eq(played.size(), 1, "silent once the night is over")
