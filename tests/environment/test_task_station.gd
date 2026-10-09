extends TestCase

var _station: TaskStation
var _player: Player


func before_each() -> void:
	Tasks.reset()
	_station = TaskStation.new()
	_station.task_kind = &"mop_spill"
	_station.zone = &"aisle_3"
	_station.title = "Mop the spill in Aisle 3"
	_station.required_tool = &"mop"
	_station.hold_time = 4.0
	_station.basic_task = true
	tree.root.add_child(_station)
	_player = Player.new()
	tree.root.add_child(_player)


func after_each() -> void:
	Tasks.reset()
	_station.free()
	_player.free()


func test_inactive_station_has_no_prompt_and_is_not_interactable() -> void:
	assert_eq(_station.get_prompt(_player), "")
	assert_false(_station.can_interact(_player))


func test_active_station_prompts_for_the_missing_tool() -> void:
	Tasks.add_manager_task(_station, 30.0)
	assert_eq(_station.get_prompt(_player), "Needs: Mop")
	assert_false(_station.can_interact(_player))


func test_active_station_prompts_a_verb_once_player_has_the_tool() -> void:
	Tasks.add_manager_task(_station, 30.0)
	_player.set_held_tool(&"mop")
	assert_eq(_station.get_prompt(_player), "Mop spill")
	assert_true(_station.can_interact(_player))


func test_interact_completes_the_active_task() -> void:
	var task := Tasks.add_manager_task(_station, 30.0)
	_player.set_held_tool(&"mop")
	_station.interact(_player)
	assert_true(task.completed)
	assert_false(_station.is_active())


func test_active_visual_only_shows_while_a_task_is_active() -> void:
	var station := TaskStation.new()
	station.required_tool = &""
	var visual := Node3D.new()
	visual.name = "ActiveVisual"
	station.add_child(visual)
	tree.root.add_child(station)
	assert_false(visual.visible)
	var task := Tasks.add_manager_task(station, 30.0)
	assert_true(visual.visible)
	Tasks.complete_task(task, null)
	assert_false(visual.visible)
	station.free()


func test_get_work_position_uses_the_work_point_marker_when_present() -> void:
	var marker := Marker3D.new()
	marker.name = "WorkPoint"
	marker.position = Vector3(1.0, 0.0, 2.0)
	_station.add_child(marker)
	assert_eq(_station.get_work_position(), _station.global_position + Vector3(1.0, 0.0, 2.0))
