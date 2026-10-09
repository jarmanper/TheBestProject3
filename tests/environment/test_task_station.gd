extends TestCase

const PlayerHelper := preload("res://tests/helpers/player_helper.gd")

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
	_player = PlayerHelper.make_player(tree)


func after_each() -> void:
	GameState.night_running = false
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


func test_active_station_prompts_the_racks_zone_when_one_is_found() -> void:
	Tasks.add_manager_task(_station, 30.0)
	var rack := ToolPickup.new()
	rack.tool_id = &"mop"
	tree.root.add_child(rack)
	var zone := StoreZone.new()
	zone.zone_id = &"janitor"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 4, 10)
	shape.shape = box
	zone.add_child(shape)
	tree.root.add_child(zone)
	rack.global_position = Vector3(18, 0, -12)
	zone.global_position = Vector3(18, 0, -12)
	assert_eq(_station.get_prompt(_player), "Needs: Mop — in Janitor Closet")
	rack.free()
	zone.free()


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


## hold_started() calls Sfx.play_at(&"task_progress", ...), which returns null
## in a test environment with no audio assets on disk, so these tests inject
## a stand-in AudioStreamPlayer3D directly rather than relying on Sfx — the
## point under test is set_task()'s bookkeeping, not Sfx itself.
func _simulate_progress_sound(station: TaskStation) -> void:
	var stand_in := AudioStreamPlayer3D.new()
	station.add_child(stand_in)
	station._progress_player = stand_in


func test_set_task_stops_the_progress_sound_when_the_task_is_cleared_mid_hold() -> void:
	var task := Tasks.add_manager_task(_station, 2.0)
	_player.set_held_tool(&"mop")
	_simulate_progress_sound(_station)
	assert_true(_station.is_progress_sound_playing())
	# The manager task times out while the player is still mid-hold; Tasks
	# clears the station via set_task(null) without the player ever calling
	# interact()/hold_stopped().
	GameState.night_running = true
	Tasks._process(2.5)
	assert_true(task.failed)
	assert_false(_station.is_progress_sound_playing())


func test_set_task_stops_the_progress_sound_when_someone_else_finishes_the_task() -> void:
	var task := Tasks.add_manager_task(_station, 30.0)
	_player.set_held_tool(&"mop")
	_simulate_progress_sound(_station)
	assert_true(_station.is_progress_sound_playing())
	# A coworker finishes the same task first; Tasks clears the station out
	# from under the player who is still holding interact.
	Tasks.complete_task(task, null)
	assert_false(_station.is_progress_sound_playing())


func test_get_work_position_uses_the_work_point_marker_when_present() -> void:
	var marker := Marker3D.new()
	marker.name = "WorkPoint"
	marker.position = Vector3(1.0, 0.0, 2.0)
	_station.add_child(marker)
	assert_eq(_station.get_work_position(), _station.global_position + Vector3(1.0, 0.0, 2.0))
