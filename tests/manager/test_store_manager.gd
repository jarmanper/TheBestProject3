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


func _make_inactive_station(i: int, is_basic := false) -> TaskStation:
	var station := TaskStation.new()
	station.task_kind = &"safe"
	station.zone = StringName("zone_%d" % i)
	station.title = "Station %d" % i
	station.required_tool = &"keys"
	station.basic_task = is_basic
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


func test_bonus_task_uses_the_configured_deadline_and_precedes_basic_work() -> void:
	tree.root.add_child(_manager)
	_manager.manager_task_time_limit = 47.0
	for i in 6:
		_make_inactive_station(i, true)
	var manager_station := _make_inactive_station(6)
	manager_station.manager_line = "Lock up the safe at the service desk before it's too late."
	Tasks.begin_night()
	assert_true(_manager.issue_bonus_task())
	var open_tasks := Tasks.get_open_tasks()
	assert_eq(open_tasks.size(), 7)
	var bonus := open_tasks[0]
	assert_true(bonus.is_manager_task, "manager work is prioritized before basic work")
	assert_true(bonus.station == manager_station, "only inactive station receives the bonus task")
	assert_near(bonus.time_limit, 47.0)
	assert_near(bonus.time_left, 47.0)
	assert_false(open_tasks[1].is_manager_task, "basic work remains after the priority task")


func test_issue_bonus_task_announces_on_intercom_with_the_stations_zone() -> void:
	tree.root.add_child(_manager)
	var station := _make_inactive_station(0)
	station.manager_line = "Lock up the safe at the service desk before it's too late."
	var heard: Array[StringName] = []
	var record := func(_message: String, zone: StringName) -> void: heard.append(zone)
	Events.intercom_announced.connect(record)
	assert_true(_manager.issue_bonus_task(StoreManager.AnnouncementChannel.INTERCOM))
	Events.intercom_announced.disconnect(record)
	assert_eq(heard, [station.zone], "intercom publishes the task zone for the monster")


func test_issue_bonus_task_sends_walkie_without_an_intercom_broadcast() -> void:
	tree.root.add_child(_manager)
	var station := _make_inactive_station(0)
	station.manager_line = "Lock up the safe at the service desk before it's too late."
	var intercoms: Array = []
	var walkies: Array = []
	var on_intercom := func(_message: String, _zone: StringName) -> void: intercoms.append(true)
	var on_walkie := func(speaker: String, message: String, _origin: Vector3, is_mimic: bool) -> void:
		walkies.append([speaker, message, is_mimic])
	Events.intercom_announced.connect(on_intercom)
	Events.walkie_message.connect(on_walkie)
	assert_true(_manager.issue_bonus_task(StoreManager.AnnouncementChannel.WALKIE))
	Events.intercom_announced.disconnect(on_intercom)
	Events.walkie_message.disconnect(on_walkie)
	assert_true(intercoms.is_empty(), "walkie assignments do not broadcast a monster-visible zone")
	assert_eq(walkies.size(), 1)
	assert_eq(walkies[0], ["MANAGER", station.manager_line, false])


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


func test_night_start_resets_the_welcome_schedule() -> void:
	_manager.welcome_delay = 1.0
	_manager.min_first_bonus_delay = 999.0
	_manager.max_first_bonus_delay = 999.0
	_manager.pa_flavour_min_interval = 999.0
	_manager.pa_flavour_max_interval = 999.0
	tree.root.add_child(_manager)
	var heard: Array = []
	var record := func(message: String, _zone: StringName) -> void: heard.append(message)
	Events.intercom_announced.connect(record)
	Events.night_started.emit()
	_manager.tick(1.0)
	Events.night_started.emit()
	_manager.tick(0.5)
	assert_eq(heard.size(), 1, "new night restarts the welcome delay")
	_manager.tick(0.5)
	Events.intercom_announced.disconnect(record)
	assert_eq(heard.size(), 2, "each night gets one welcome")
	assert_true(heard.all(func(line: String) -> bool: return line in ManagerLines.WELCOME))


func test_pa_flavour_uses_its_tunable_interval_and_repeats() -> void:
	_manager.welcome_delay = 999.0
	_manager.min_first_bonus_delay = 999.0
	_manager.max_first_bonus_delay = 999.0
	_manager.pa_flavour_min_interval = 2.0
	_manager.pa_flavour_max_interval = 2.0
	tree.root.add_child(_manager)
	var heard: Array = []
	var record := func(message: String, _zone: StringName) -> void: heard.append(message)
	Events.intercom_announced.connect(record)
	Events.night_started.emit()
	_manager.tick(1.9)
	assert_true(heard.is_empty(), "PA flavour waits for its configured interval")
	_manager.tick(0.1)
	_manager.tick(1.9)
	assert_eq(heard.size(), 1, "one PA flavour line at two seconds")
	_manager.tick(0.1)
	Events.intercom_announced.disconnect(record)
	assert_eq(heard.size(), 2, "PA flavour reschedules at the same tunable interval")
	assert_true(heard.all(func(line: String) -> bool: return line in ManagerLines.PA_FLAVOUR))


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
