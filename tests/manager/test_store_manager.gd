extends TestCase

var _manager: StoreManager
var _stations: Array[TaskStation] = []


func before_each() -> void:
	Tasks.reset()
	GameState.night_running = false
	_stations.clear()
	_manager = StoreManager.new()


func after_each() -> void:
	Tasks.reset()
	GameState.night_running = false
	if is_instance_valid(_manager):
		_manager.free()
	for station in _stations:
		if is_instance_valid(station):
			station.free()
	_stations.clear()


func _make_inactive_station(i: int) -> TaskStation:
	var station := TaskStation.new()
	station.task_kind = &"safe"
	station.zone = StringName("zone_%d" % i)
	station.title = "Station %d" % i
	station.required_tool = &"keys"
	station.basic_task = false
	tree.root.add_child(station)
	_stations.append(station)
	return station


func test_issue_bonus_task_adds_a_manager_task_at_an_inactive_station() -> void:
	tree.root.add_child(_manager)
	for i in 3:
		_make_inactive_station(i)
	assert_true(_manager.issue_bonus_task())
	assert_eq(Tasks.get_open_tasks().size(), 1)
	assert_true(Tasks.get_open_tasks()[0].is_manager_task)


func test_issue_bonus_task_returns_false_with_no_inactive_stations() -> void:
	tree.root.add_child(_manager)
	assert_false(_manager.issue_bonus_task())


func test_issue_bonus_task_announces_on_intercom_with_the_stations_zone() -> void:
	tree.root.add_child(_manager)
	var heard: Array = []
	var record := func(_message: String, zone: StringName) -> void: heard.append(zone)
	Events.intercom_announced.connect(record)
	for i in 20:
		_make_inactive_station(i)
		_manager.issue_bonus_task()
		if not heard.is_empty():
			break
	Events.intercom_announced.disconnect(record)
	assert_false(heard.is_empty(), "expected at least one bonus task to go out over the intercom in 20 tries")
	assert_true(String(heard[0]).begins_with("zone_"))


func test_tick_sends_the_welcome_line_once_after_its_delay() -> void:
	_manager.welcome_delay = 6.0
	tree.root.add_child(_manager)
	var heard: Array = []
	var record := func(message: String, _zone: StringName) -> void: heard.append(message)
	Events.intercom_announced.connect(record)
	Events.night_started.emit()
	_manager.tick(5.0)
	assert_true(heard.is_empty(), "should not welcome before the delay elapses")
	_manager.tick(2.0)
	_manager.tick(1.0)
	Events.intercom_announced.disconnect(record)
	assert_eq(heard.size(), 1)
	assert_true(heard[0] in ManagerLines.WELCOME)


func test_tick_issues_the_first_bonus_task_within_its_configured_window() -> void:
	tree.root.add_child(_manager)
	_manager.min_first_bonus_delay = 1.0
	_manager.max_first_bonus_delay = 1.0
	_manager.welcome_delay = 0.0
	for i in 3:
		_make_inactive_station(i)
	Events.night_started.emit()
	_manager.tick(0.5)
	assert_eq(Tasks.get_open_tasks().size(), 0)
	_manager.tick(1.0)
	assert_eq(Tasks.get_open_tasks().size(), 1)


func test_tick_never_exceeds_the_max_open_manager_tasks() -> void:
	tree.root.add_child(_manager)
	_manager.max_open_manager_tasks = 2
	_manager.min_first_bonus_delay = 0.0
	_manager.max_first_bonus_delay = 0.0
	_manager.min_bonus_interval = 1.0
	_manager.max_bonus_interval = 1.0
	_manager.welcome_delay = 0.0
	for i in 10:
		_make_inactive_station(i)
	Events.night_started.emit()
	for i in 20:
		_manager.tick(1.0)
	var open_manager_tasks := 0
	for task in Tasks.get_open_tasks():
		if task.is_manager_task:
			open_manager_tasks += 1
	assert_true(open_manager_tasks <= 2, "should never have more than max_open_manager_tasks open at once")


func test_manager_reacts_on_walkie_when_a_manager_task_fails() -> void:
	tree.root.add_child(_manager)
	var station := _make_inactive_station(0)
	var heard: Array = []
	var record := func(speaker: String, message: String, _origin: Vector3, is_mimic: bool) -> void:
		heard.append([speaker, message, is_mimic])
	Events.walkie_message.connect(record)
	var task := Tasks.add_manager_task(station, 1.0)
	GameState.night_running = true   # deadlines only run during the night
	Tasks._process(1.5)
	Events.walkie_message.disconnect(record)
	assert_true(task.failed)
	assert_eq(heard.size(), 1)
	assert_eq(heard[0][0], "MANAGER")
	assert_false(heard[0][2])


func _intercom_lines_for_hour(hour: int) -> Array:
	var heard: Array = []
	var record := func(message: String, _zone: StringName) -> void: heard.append(message)
	Events.intercom_announced.connect(record)
	Events.hour_changed.emit(hour)
	Events.intercom_announced.disconnect(record)
	return heard


func test_hourly_announcement_each_hour_but_not_at_six() -> void:
	tree.root.add_child(_manager)
	assert_eq(_intercom_lines_for_hour(0).size(), 0, "no hourly line at 12 AM (the welcome covers it)")
	assert_eq(_intercom_lines_for_hour(3).size(), 1, "3 AM is announced")
	assert_eq(_intercom_lines_for_hour(GameState.END_HOUR).size(), 0, "6 AM: the shift-end bell, not a line cut off by the end screen")


func test_set_seed_makes_the_manager_repeatable() -> void:
	tree.root.add_child(_manager)
	for i in 6:
		_make_inactive_station(i)
	var picks: Array = []
	for run in 2:
		Tasks.reset()
		_manager.set_seed(1234)
		assert_true(_manager.issue_bonus_task())
		picks.append(Tasks.get_open_tasks()[0].title)
	assert_eq(picks[0], picks[1], "same seed, same station")
