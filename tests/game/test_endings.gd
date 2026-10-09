extends TestCase
## The three endings (docs/ARCHITECTURE.md §1): 6:00 AM alive with every basic task done is a
## win, with any left it is "fired", and health reaching 0 is "dead" -- even when the player
## dies just before 6:00 AM, inside Player.DEATH_END_DELAY.

const Fixture := preload("res://tests/player/player_fixture.gd")

var world: Node3D
var player: Player
var results: Array[StringName] = []


func before_each() -> void:
	Tasks.reset()
	world = Fixture.make_world(tree)
	player = Fixture.add_player(world)
	for i in Tasks.BASIC_TASKS_PER_NIGHT:
		var station := TaskStation.new()
		station.task_kind = StringName("kind_%d" % i)
		station.zone = StringName("zone_%d" % i)
		station.title = "Task %d" % i
		station.basic_task = true
		world.add_child(station)
	Events.night_ended.connect(_on_night_ended)
	await wait_frames(1)
	GameState.start_night()
	Tasks.begin_night()


func after_each() -> void:
	Events.night_ended.disconnect(_on_night_ended)
	GameState.night_running = false
	Tasks.reset()
	world.free()


func _on_night_ended(result: StringName) -> void:
	results.append(result)


func _finish_basic_tasks(leave_open: int) -> void:
	var open := Tasks.get_open_tasks()
	for i in open.size() - leave_open:
		Tasks.complete_task(open[i], player)


func _night_length() -> float:
	return GameState.SECONDS_PER_HOUR * GameState.END_HOUR


func test_every_basic_task_done_at_six_is_a_win() -> void:
	assert_eq(Tasks.get_required_remaining(), Tasks.BASIC_TASKS_PER_NIGHT, "a full checklist")
	_finish_basic_tasks(0)
	assert_true(Tasks.all_required_done())
	GameState.advance(_night_length() - 1.0)
	assert_true(results.is_empty(), "nothing ends before 6:00 AM")
	GameState.advance(1.0)
	assert_eq(results, [&"win"] as Array[StringName], "SHIFT COMPLETE")
	assert_eq(GameState.last_result, &"win")
	assert_eq(GameState.get_clock_text(), "6:00 AM")


func test_one_basic_task_left_at_six_is_fired() -> void:
	_finish_basic_tasks(1)
	assert_eq(Tasks.get_required_remaining(), 1)
	GameState.advance(_night_length())
	assert_eq(results, [&"fired"] as Array[StringName], "YOU'RE FIRED")
	assert_eq(GameState.last_result, &"fired")


func test_open_manager_tasks_do_not_cost_the_win() -> void:
	var extra := TaskStation.new()
	extra.zone = &"office"
	extra.title = "Bonus"
	extra.basic_task = false
	world.add_child(extra)
	Tasks.add_manager_task(extra, 0.0)
	_finish_basic_tasks(0)
	GameState.advance(_night_length())
	assert_eq(results, [&"win"] as Array[StringName], "only basic tasks decide the ending")


func test_dying_just_before_six_ends_the_night_dead() -> void:
	_finish_basic_tasks(0)
	GameState.advance(_night_length() - 0.5)   # 5:59 AM, everything done
	player.take_damage(player.max_health, Vector3.ZERO)
	assert_true(player.is_dead())
	GameState.advance(1.0)                      # 6:00 AM inside the 2 s death delay
	assert_true(results.is_empty(), "a dead player neither wins nor gets fired (%s)" % [results])
	assert_true(GameState.night_running, "the death path ends this night")
	player.update_death(Player.DEATH_END_DELAY)
	assert_eq(results, [&"dead"] as Array[StringName], "YOU DIDN'T MAKE IT")
	assert_eq(GameState.last_result, &"dead")
