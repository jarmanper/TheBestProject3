extends TestCase

const Fixture := preload("res://tests/player/player_fixture.gd")

var world: Node3D
var player: Player


func before_each() -> void:
	world = Fixture.make_world(tree)
	player = Fixture.add_player(world)
	await wait_frames(1)


func after_each() -> void:
	world.free()


func test_sprint_drains_twenty_per_second() -> void:
	player.update_stamina(1.0, true)
	assert_true(player.is_sprinting, "sprinting while stamina is left")
	assert_near(player.stamina, 80.0, 0.01)


func test_regen_waits_one_second_then_fourteen_per_second() -> void:
	player.update_stamina(1.0, true)
	player.update_stamina(1.0, false)
	assert_near(player.stamina, 80.0, 0.01, "no regen during the first second")
	player.update_stamina(1.0, false)
	assert_near(player.stamina, 94.0, 0.01, "14/s after the delay")


func test_regen_stops_at_max() -> void:
	player.update_stamina(0.5, true)
	player.update_stamina(30.0, false)
	assert_near(player.stamina, player.max_stamina, 0.001)


func test_empty_stamina_exhausts_until_thirty_five() -> void:
	for i in 50:
		player.update_stamina(0.1, true)
	assert_near(player.stamina, 0.0, 0.001)
	assert_true(player.is_exhausted, "exhausted at 0")
	player.update_stamina(0.1, true)
	assert_false(player.is_sprinting, "cannot sprint while exhausted")
	# 1 s delay, then 14/s: 34 stamina after 1 + 34/14 s.
	player.update_stamina(1.0 + 34.0 / 14.0 - 0.1, true)
	assert_true(player.is_exhausted, "still exhausted below 35")
	assert_false(player.is_sprinting)
	player.update_stamina(0.2, false)
	assert_true(player.stamina >= 35.0, "stamina reached 35")
	assert_false(player.is_exhausted, "recovered at 35")
	player.update_stamina(0.1, true)
	assert_true(player.is_sprinting, "can sprint again")


func test_stamina_changed_signal() -> void:
	var values: Array[float] = []
	var record := func(value: float, max_value: float) -> void:
		values.append(value)
		assert_near(max_value, 100.0)
	Events.stamina_changed.connect(record)
	player.update_stamina(0.5, true)
	Events.stamina_changed.disconnect(record)
	assert_eq(values.size(), 1)
	assert_near(values[0], 90.0, 0.01)
