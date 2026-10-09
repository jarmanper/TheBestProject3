extends TestCase

const PlayerHelper := preload("res://tests/helpers/player_helper.gd")

var _stations: Array[TaskStation] = []


func before_each() -> void:
	Tasks.reset()
	_stations.clear()


func after_each() -> void:
	GameState.night_running = false
	Tasks.reset()
	for station in _stations:
		if is_instance_valid(station):
			station.free()
	_stations.clear()


func _make_station(kind: StringName, zone: StringName, tool: StringName, basic := true) -> TaskStation:
	var station := TaskStation.new()
	station.task_kind = kind
	station.zone = zone
	station.title = "Test: %s" % kind
	station.required_tool = tool
	station.hold_time = 3.0
	station.basic_task = basic
	tree.root.add_child(station)
	_stations.append(station)
	return station


func _make_plain_stations(count: int, zone_prefix: String) -> void:
	for i in count:
		_make_station(StringName("kind_%d" % i), StringName("%s_%d" % [zone_prefix, i]), &"")


func test_begin_night_activates_six_basic_tasks_with_tool_variety() -> void:
	for i in 5:
		_make_station(StringName("tool_kind_%d" % i), StringName("zone_tool_%d" % i), &"mop")
	_make_plain_stations(5, "zone_plain")
	Tasks.begin_night()
	var open_tasks := Tasks.get_open_tasks()
	assert_eq(open_tasks.size(), Tasks.BASIC_TASKS_PER_NIGHT)
	var tool_tasks := 0
	for task in open_tasks:
		if task.required_tool != &"":
			tool_tasks += 1
	assert_true(tool_tasks >= Tasks.MIN_TOOL_TASKS,
		"expected at least %d tool tasks, got %d" % [Tasks.MIN_TOOL_TASKS, tool_tasks])


func test_begin_night_never_picks_a_manager_only_station() -> void:
	_make_station(&"breaker", &"hallway", &"keys", false)
	_make_plain_stations(6, "zone")
	Tasks.begin_night()
	for task in Tasks.get_open_tasks():
		assert_true(task.zone != &"hallway", "manager-only station should not join the basic rotation")
	assert_eq(Tasks.get_open_tasks().size(), 6)


func test_manager_task_only_on_inactive_station() -> void:
	var station := _make_station(&"safe", &"service_desk", &"keys", false)
	var task := Tasks.add_manager_task(station, 30.0)
	assert_true(task != null)
	var second := Tasks.add_manager_task(station, 30.0)
	assert_true(second == null, "station is already active; should refuse a second manager task")


func test_manager_task_fails_after_its_time_limit() -> void:
	var station := _make_station(&"safe", &"service_desk", &"keys", false)
	var failed_tasks: Array = []
	var record := func(task: TaskData) -> void: failed_tasks.append(task)
	Events.task_failed.connect(record)
	var before_failed: int = GameState.stats.get("manager_tasks_failed", 0)
	var task := Tasks.add_manager_task(station, 2.0)
	GameState.night_running = true
	Tasks._process(2.5)
	Events.task_failed.disconnect(record)
	assert_true(task.failed)
	assert_eq(failed_tasks.size(), 1)
	assert_false(station.is_active())
	assert_eq(GameState.stats.get("manager_tasks_failed", 0), before_failed + 1)


func test_get_open_tasks_orders_manager_before_basic_by_soonest_deadline() -> void:
	_make_plain_stations(6, "zone")
	Tasks.begin_night()
	var station_a := _make_station(&"breaker", &"hallway", &"keys", false)
	var station_b := _make_station(&"safe", &"service_desk", &"keys", false)
	var slow_task := Tasks.add_manager_task(station_a, 100.0)
	var fast_task := Tasks.add_manager_task(station_b, 10.0)
	var open_tasks := Tasks.get_open_tasks()
	assert_eq(open_tasks.size(), 8)
	assert_true(open_tasks[0] == fast_task, "soonest deadline should come first")
	assert_true(open_tasks[1] == slow_task)
	assert_false(open_tasks[2].is_manager_task)


func test_complete_task_updates_stats_emits_signals_and_clears_station() -> void:
	var station := _make_station(&"safe", &"service_desk", &"keys", false)
	var task := Tasks.add_manager_task(station, 30.0)
	var completions: Array = []
	var record := func(t: TaskData, _by: Node) -> void: completions.append(t)
	Events.task_completed.connect(record)
	var before_completed: int = GameState.stats.get("tasks_completed", 0)
	var before_manager_completed: int = GameState.stats.get("manager_tasks_completed", 0)
	Tasks.complete_task(task, null)
	Events.task_completed.disconnect(record)
	assert_true(task.completed)
	assert_eq(completions.size(), 1)
	assert_false(station.is_active())
	assert_eq(GameState.stats.get("tasks_completed", 0), before_completed + 1)
	assert_eq(GameState.stats.get("manager_tasks_completed", 0), before_manager_completed + 1)


func test_claim_task_is_exclusive_to_one_worker() -> void:
	var station := _make_station(&"safe", &"service_desk", &"keys", false)
	var task := Tasks.add_manager_task(station, 30.0)
	var worker_a := Node.new()
	var worker_b := Node.new()
	assert_true(Tasks.claim_task(task, worker_a))
	assert_false(Tasks.claim_task(task, worker_b))
	Tasks.release_task(task, worker_a)
	assert_true(Tasks.claim_task(task, worker_b))
	worker_a.free()
	worker_b.free()


func test_complete_task_returns_a_consumed_tool_to_its_rack_for_the_player() -> void:
	var station := _make_station(&"restock", &"aisle_2", &"stock_box")
	var rack := ToolPickup.new()
	rack.tool_id = &"stock_box"
	rack.has_tool = false
	tree.root.add_child(rack)
	var player := PlayerHelper.make_player(tree)
	player.set_held_tool(&"stock_box")
	var task := Tasks.add_manager_task(station, 30.0)
	Tasks.complete_task(task, player)
	assert_eq(player.held_tool, &"")
	assert_true(rack.has_tool)
	player.free()
	rack.free()


func test_complete_task_keeps_a_non_consumed_tool_in_the_players_hand() -> void:
	var station := _make_station(&"mop_spill", &"aisle_3", &"mop")
	var player := PlayerHelper.make_player(tree)
	player.set_held_tool(&"mop")
	var task := Tasks.add_manager_task(station, 30.0)
	Tasks.complete_task(task, player)
	assert_eq(player.held_tool, &"mop")
	player.free()


func test_required_remaining_counts_only_incomplete_basic_tasks() -> void:
	_make_plain_stations(6, "zone")
	Tasks.begin_night()
	assert_eq(Tasks.get_required_remaining(), 6)
	assert_false(Tasks.all_required_done())
	for task in Tasks.get_open_tasks().duplicate():
		Tasks.complete_task(task, null)
	assert_eq(Tasks.get_required_remaining(), 0)
	assert_true(Tasks.all_required_done())


func test_manager_deadlines_only_run_during_the_night() -> void:
	var station := _make_station(&"safe", &"office", &"", false)
	var task := Tasks.add_manager_task(station, 1.0)
	GameState.night_running = false   # e.g. quit to the menu with a task open
	Tasks._process(5.0)
	assert_false(task.failed, "no deadline runs outside the night")
	assert_near(task.time_left, 1.0, 0.001)
	GameState.night_running = true
	Tasks._process(1.5)
	assert_true(task.failed, "runs again once the night does")
