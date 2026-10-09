extends TestCase

const Fixture := preload("res://tests/player/player_fixture.gd")

var world: Node3D
var player: Player


func before_each() -> void:
	world = Fixture.make_world(tree)
	player = Fixture.add_player(world)
	await wait_frames(1)


func after_each() -> void:
	GameState.night_running = false
	world.free()


func test_damage_reduces_health_and_emits() -> void:
	var got := []
	var record := func(amount: float, health_left: float) -> void: got.append([amount, health_left])
	Events.player_damaged.connect(record)
	player.take_damage(30.0, Vector3(0, 0, -2))
	Events.player_damaged.disconnect(record)
	assert_near(player.health, 70.0)
	assert_eq(got.size(), 1)
	assert_near(got[0][0], 30.0)
	assert_near(got[0][1], 70.0)


func test_regen_after_eight_seconds() -> void:
	player.take_damage(20.0, Vector3.ZERO)
	player.update_health(7.9)
	assert_near(player.health, 80.0, 0.001, "no regen before 8 s")
	player.update_health(1.1)
	assert_near(player.health, 82.0, 0.01, "2 hp/s after 8 s")
	player.take_damage(10.0, Vector3.ZERO)
	player.update_health(1.0)
	assert_near(player.health, 72.0, 0.01, "new damage resets the delay")


func test_death_signals_and_ends_night_after_two_seconds() -> void:
	GameState.start_night()
	var died := [0]
	var on_died := func() -> void: died[0] += 1
	var results: Array[StringName] = []
	var on_ended := func(result: StringName) -> void: results.append(result)
	Events.player_died.connect(on_died)
	Events.night_ended.connect(on_ended)
	player.take_damage(150.0, Vector3.ZERO)
	assert_near(player.health, 0.0)
	assert_eq(died[0], 1, "player_died once")
	assert_true(player.is_dead())
	assert_false(player.input_enabled, "input off when dead")
	player.update_death(1.5)
	assert_eq(results.size(), 0, "night not ended yet")
	player.update_death(0.6)
	assert_eq(results, [&"dead"] as Array[StringName], "ended as dead after 2 s")
	player.take_damage(10.0, Vector3.ZERO)
	assert_eq(died[0], 1, "no second death")
	Events.player_died.disconnect(on_died)
	Events.night_ended.disconnect(on_ended)


func test_damage_stat_recorded() -> void:
	GameState.start_night()
	player.take_damage(12.5, Vector3.ZERO)
	assert_near(GameState.stats["damage_taken"], 12.5)
