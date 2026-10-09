extends TestCase
## Player-side heartbeat loop (ui/hud/heartbeat.gd): fades in at low health or with the
## true form chasing close by, fades out otherwise.

const FakePlayer := preload("res://tests/monster/fake_player.gd")


class FakeMonster extends Node3D:
	var true_form := false
	var hunting := false

	func is_true_form() -> bool:
		return true_form

	func is_hunting() -> bool:
		return hunting


var heartbeat: Heartbeat
var player: Node3D
var monster: FakeMonster


func before_each() -> void:
	player = FakePlayer.new()
	tree.root.add_child(player)
	monster = FakeMonster.new()
	tree.root.add_child(monster)
	monster.global_position = Vector3(0, 0, -30)
	GameState.monster = monster
	GameState.night_running = true
	heartbeat = Heartbeat.new()
	heartbeat.set_process(false)   # stepped by hand
	tree.root.add_child(heartbeat)


func after_each() -> void:
	GameState.night_running = false
	GameState.player = null
	GameState.monster = null
	heartbeat.free()
	player.free()
	monster.free()


func test_wants_heartbeat_at_low_health_or_chased_close() -> void:
	assert_false(Heartbeat.wants_heartbeat(1.0, INF, false), "healthy, nothing near")
	assert_true(Heartbeat.wants_heartbeat(0.3, INF, false), "below 35% health")
	assert_false(Heartbeat.wants_heartbeat(0.4, INF, false))
	assert_true(Heartbeat.wants_heartbeat(1.0, 7.5, true), "the true form chasing within 8 m")
	assert_false(Heartbeat.wants_heartbeat(1.0, 9.0, true), "chasing, but farther than 8 m")
	assert_false(Heartbeat.wants_heartbeat(1.0, 3.0, false), "close, but not chasing")


func test_fades_in_at_low_health_and_out_again() -> void:
	heartbeat.tick(1.0)
	assert_false(heartbeat.is_beating(), "silent while healthy")
	player.set(&"health", 30.0)
	heartbeat.tick(0.3)
	assert_true(heartbeat.is_beating(), "starts at low health")
	assert_true(heartbeat.get_level() > 0.0 and heartbeat.get_level() < 1.0, "fading in")
	heartbeat.tick(Heartbeat.FADE_IN_TIME)
	assert_near(heartbeat.get_level(), 1.0, 0.001, "full")
	player.set(&"health", 100.0)
	heartbeat.tick(Heartbeat.FADE_OUT_TIME * 0.5)
	assert_true(heartbeat.is_beating(), "fading out, not cut")
	heartbeat.tick(Heartbeat.FADE_OUT_TIME)
	assert_false(heartbeat.is_beating(), "stopped once faded out")


func test_beats_while_the_true_form_chases_close() -> void:
	monster.true_form = true
	monster.hunting = true
	monster.global_position = Vector3(0, 0, -6)
	heartbeat.tick(Heartbeat.FADE_IN_TIME)
	assert_near(heartbeat.get_level(), 1.0, 0.001, "chased within 8 m")
	monster.global_position = Vector3(0, 0, -20)
	heartbeat.tick(Heartbeat.FADE_OUT_TIME)
	assert_false(heartbeat.is_beating(), "it fell behind")


func test_stops_when_the_night_ends() -> void:
	player.set(&"health", 10.0)
	heartbeat.tick(Heartbeat.FADE_IN_TIME)
	assert_true(heartbeat.is_beating())
	GameState.end_night(&"fired")
	assert_false(heartbeat.is_beating(), "silent behind the end screen")
