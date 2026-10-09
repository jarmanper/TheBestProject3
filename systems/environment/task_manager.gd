extends Node
## Autoload "Tasks": the night's task checklist (Store Environment system).

const BASIC_TASKS_PER_NIGHT := 6
const MIN_TOOL_TASKS := 3
## Balance: all coworkers together may take at most this many *basic* tasks per night
## (completed + currently claimed), so the player still has to do most of the checklist.
## Manager tasks are never capped (GDD seam 2: coworkers prioritise them).
const MAX_COWORKER_BASIC_COMPLETIONS := 2

var _basic_tasks: Array[TaskData] = []
var _manager_tasks: Array[TaskData] = []
var _next_id := 0
var _coworker_basic_completions := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


## Manager deadlines count down only while the night runs (not on the menu after quitting).
func _process(delta: float) -> void:
	if not GameState.night_running:
		return
	for task in _manager_tasks:
		if task.is_open() and task.time_limit > 0.0:
			task.time_left -= delta
			if task.time_left <= 0.0:
				_fail_task(task)


## Clears every task (call before a new night).
func reset() -> void:
	for task in _basic_tasks:
		if task.station:
			task.station.set_task(null)
	for task in _manager_tasks:
		if task.station:
			task.station.set_task(null)
	_basic_tasks.clear()
	_manager_tasks.clear()
	_next_id = 0
	_coworker_basic_completions = 0


## Picks this night's basic tasks from stations in group "task_station" and activates them.
func begin_night() -> void:
	var tool_stations: Array[TaskStation] = []
	var plain_stations: Array[TaskStation] = []
	for node in get_tree().get_nodes_in_group(&"task_station"):
		var station := node as TaskStation
		if station == null or not station.basic_task:
			continue
		if station.required_tool != &"":
			tool_stations.append(station)
		else:
			plain_stations.append(station)
	tool_stations.shuffle()
	plain_stations.shuffle()

	var chosen: Array[TaskStation] = []
	var zones_used := {}
	var tool_quota := mini(MIN_TOOL_TASKS, tool_stations.size())
	for i in tool_quota:
		_pick_preferring_new_zone(chosen, tool_stations, zones_used)

	var rest: Array[TaskStation] = tool_stations + plain_stations
	rest.shuffle()
	while chosen.size() < BASIC_TASKS_PER_NIGHT and not rest.is_empty():
		_pick_preferring_new_zone(chosen, rest, zones_used)

	for station in chosen:
		_activate_basic_task(station)
	Events.tasks_changed.emit()


## Manager bonus task at `station`; fails after `time_limit` seconds. Sorted above basic tasks.
func add_manager_task(station: Node3D, time_limit: float) -> TaskData:
	var task_station := station as TaskStation
	if task_station == null or task_station.is_active():
		return null
	var task := TaskData.new()
	task.id = _make_id()
	task.title = task_station.title
	task.zone = task_station.zone
	task.required_tool = task_station.required_tool
	task.hold_time = task_station.hold_time
	task.is_manager_task = true
	task.time_limit = time_limit
	task.time_left = time_limit
	task.station = task_station
	_manager_tasks.append(task)
	task_station.set_task(task)
	Events.task_added.emit(task)
	Events.tasks_changed.emit()
	return task


func complete_task(task: TaskData, by: Node) -> void:
	if task == null or not task.is_open():
		return
	task.completed = true
	if not task.is_manager_task and is_instance_valid(by) and not _is_player(by):
		_coworker_basic_completions += 1
	GameState.add_stat("tasks_completed")
	if task.is_manager_task:
		GameState.add_stat("manager_tasks_completed")
	Events.task_completed.emit(task, by)
	Events.tasks_changed.emit()
	if task.station:
		task.station.set_task(null)
	_return_consumed_tool(task, by)


## A coworker reserves a task so two workers do not walk to the same one.
## Refuses a basic task to a non-player worker once coworkers have used up
## MAX_COWORKER_BASIC_COMPLETIONS (completions plus open claims).
func claim_task(task: TaskData, worker: Node) -> bool:
	if task == null or not task.is_open():
		return false
	if task.claimed_by == worker:
		return true
	if task.claimed_by != null:
		return false
	if not task.is_manager_task and not _is_player(worker) \
			and _coworker_basic_completions + _coworker_basic_claims() >= MAX_COWORKER_BASIC_COMPLETIONS:
		return false
	task.claimed_by = worker
	return true


func release_task(task: TaskData, worker: Node) -> void:
	if task != null and task.claimed_by == worker:
		task.claimed_by = null


## Open tasks, manager tasks first (soonest deadline first), then basic tasks.
func get_open_tasks() -> Array[TaskData]:
	var manager_open: Array[TaskData] = _manager_tasks.filter(func(t: TaskData) -> bool: return t.is_open())
	manager_open.sort_custom(func(a: TaskData, b: TaskData) -> bool: return a.time_left < b.time_left)
	var basic_open: Array[TaskData] = _basic_tasks.filter(func(t: TaskData) -> bool: return t.is_open())
	var result: Array[TaskData] = []
	result.append_array(manager_open)
	result.append_array(basic_open)
	return result


## Every task of the night for the HUD: open manager, open basic, then done/failed.
func get_tasks_for_checklist() -> Array[TaskData]:
	var result := get_open_tasks()
	var finished: Array[TaskData] = []
	for task in _manager_tasks:
		if not task.is_open():
			finished.append(task)
	for task in _basic_tasks:
		if not task.is_open():
			finished.append(task)
	result.append_array(finished)
	return result


func get_required_remaining() -> int:
	var count := 0
	for task in _basic_tasks:
		if not task.completed:
			count += 1
	return count


func all_required_done() -> bool:
	return get_required_remaining() == 0


## Basic tasks finished by someone other than the player this night.
func get_coworker_basic_completions() -> int:
	return _coworker_basic_completions


func _coworker_basic_claims() -> int:
	var count := 0
	for task in _basic_tasks:
		if task.is_open() and is_instance_valid(task.claimed_by) and not _is_player(task.claimed_by):
			count += 1
	return count


static func _is_player(worker: Node) -> bool:
	return worker != null and is_instance_valid(worker) and worker.is_in_group(&"player")


func _activate_basic_task(station: TaskStation) -> TaskData:
	var task := TaskData.new()
	task.id = _make_id()
	task.title = station.title
	task.zone = station.zone
	task.required_tool = station.required_tool
	task.hold_time = station.hold_time
	task.is_manager_task = false
	task.station = station
	_basic_tasks.append(task)
	station.set_task(task)
	Events.task_added.emit(task)
	return task


func _fail_task(task: TaskData) -> void:
	task.failed = true
	Events.task_failed.emit(task)
	if task.station:
		task.station.set_task(null)
	GameState.add_stat("manager_tasks_failed")
	Events.tasks_changed.emit()


func _return_consumed_tool(task: TaskData, by: Node) -> void:
	if task.required_tool == &"":
		return
	if not Catalog.TOOLS.get(task.required_tool, {}).get("consumed", false):
		return
	if by == null or not by.is_in_group(&"player"):
		return
	by.set_held_tool(&"")
	var tree := by.get_tree()
	if tree == null:
		return
	var rack := ToolPickup.find_rack(tree, task.required_tool)
	if rack:
		rack.return_tool()


## Picks one station from `pool` (removing it), preferring one whose zone is
## not in `zones_used` yet. Falls back to the last entry when every zone left
## in the pool is already represented.
func _pick_preferring_new_zone(chosen: Array[TaskStation], pool: Array[TaskStation], zones_used: Dictionary) -> void:
	if pool.is_empty():
		return
	var index := pool.size() - 1
	for i in pool.size():
		if not zones_used.has(pool[i].zone):
			index = i
			break
	var station := pool[index]
	pool.remove_at(index)
	chosen.append(station)
	zones_used[station.zone] = true


func _make_id() -> StringName:
	_next_id += 1
	return StringName("task_%d" % _next_id)
