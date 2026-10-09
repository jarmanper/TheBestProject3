extends TestCase
## HudMinimap.collect_markers(): open-task and needed-tool-rack markers (pure data, no pixels).

const PlayerHelper := preload("res://tests/helpers/player_helper.gd")

var _minimap: HudMinimap
var _stations: Array[TaskStation] = []
var _racks: Array[ToolPickup] = []
var _player: Player


func before_each() -> void:
	Tasks.reset()
	_stations.clear()
	_racks.clear()
	_minimap = HudMinimap.new()
	tree.root.add_child(_minimap)
	_player = PlayerHelper.make_player(tree)


func after_each() -> void:
	GameState.night_running = false
	Tasks.reset()
	for station in _stations:
		if is_instance_valid(station):
			station.free()
	for rack in _racks:
		if is_instance_valid(rack):
			rack.free()
	_minimap.free()
	_player.free()


func _make_station(tool: StringName, pos: Vector3) -> TaskStation:
	var station := TaskStation.new()
	station.task_kind = &"mop_spill"
	station.title = "Test task"
	station.required_tool = tool
	tree.root.add_child(station)
	station.global_position = pos
	_stations.append(station)
	return station


func _make_rack(tool: StringName, pos: Vector3) -> ToolPickup:
	var rack := ToolPickup.new()
	rack.tool_id = tool
	tree.root.add_child(rack)
	rack.global_position = pos
	_racks.append(rack)
	return rack


func test_open_manager_task_is_marked_at_its_station() -> void:
	var station := _make_station(&"", Vector3(1, 0, 2))
	Tasks.add_manager_task(station, 30.0)
	var markers := _minimap.collect_markers()
	assert_eq(markers.size(), 1)
	assert_eq(markers[0].type, &"task")
	assert_true(markers[0].manager, "manager tasks are flagged manager")
	assert_eq(markers[0].position, Vector3(1, 0, 2))
	assert_false(markers[0].highlighted, "no tool needed, nothing to highlight")


func test_basic_task_marker_is_not_flagged_manager() -> void:
	var station := _make_station(&"", Vector3(3, 0, 4))
	station.basic_task = true
	Tasks.begin_night()
	var markers := _minimap.collect_markers()
	assert_eq(markers.size(), 1)
	assert_false(markers[0].manager, "basic tasks are not flagged manager")


func test_completed_tasks_are_not_marked() -> void:
	var station := _make_station(&"", Vector3(1, 0, 2))
	var task := Tasks.add_manager_task(station, 30.0)
	Tasks.complete_task(task, _player)
	assert_eq(_minimap.collect_markers().size(), 0)


func test_marks_the_rack_of_a_needed_tool_until_held() -> void:
	_make_station(&"mop", Vector3(5, 0, 5))
	_make_rack(&"mop", Vector3(18, 0, -12))
	Tasks.add_manager_task(_stations[0], 30.0)
	var markers := _minimap.collect_markers()
	assert_eq(markers.size(), 2, "one task marker + one rack marker")
	assert_false(markers[0].highlighted, "tool not held yet")
	assert_eq(markers[1].type, &"rack")
	assert_eq(markers[1].position, Vector3(18, 0, -12))

	_player.set_held_tool(&"mop")
	markers = _minimap.collect_markers()
	assert_eq(markers.size(), 1, "rack marker drops once the player holds the tool")
	assert_true(markers[0].highlighted, "the task the held tool unlocks is highlighted")


func test_a_taken_rack_is_not_marked() -> void:
	_make_station(&"mop", Vector3(5, 0, 5))
	var rack := _make_rack(&"mop", Vector3(18, 0, -12))
	rack.has_tool = false
	Tasks.add_manager_task(_stations[0], 30.0)
	var markers := _minimap.collect_markers()
	assert_eq(markers.size(), 1, "the rack's tool is already gone, so only the task is marked")
	assert_eq(markers[0].type, &"task")


func test_one_rack_marker_per_tool_even_with_several_tasks_needing_it() -> void:
	var a := _make_station(&"mop", Vector3(1, 0, 1))
	var b := _make_station(&"mop", Vector3(9, 0, 9))
	_make_rack(&"mop", Vector3(18, 0, -12))
	Tasks.add_manager_task(a, 30.0)
	Tasks.add_manager_task(b, 30.0)
	var rack_markers := 0
	for marker in _minimap.collect_markers():
		if marker.type == &"rack":
			rack_markers += 1
	assert_eq(rack_markers, 1)
