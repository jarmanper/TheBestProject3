extends RefCounted
## Stand-in for the Tasks autoload with the API coworkers use. The AI sandbox
## uses it while Tasks is still a stub; tests use it to feed exact task lists.

var tasks: Array[TaskData] = []
var completed: Array[TaskData] = []
var sort_manager_first := true   ## false: return tasks in insertion order (tests)


func add_task(station: Node3D, is_manager := false, hold_time := 3.0) -> TaskData:
	var task := TaskData.new()
	task.id = StringName("task_%d" % tasks.size())
	task.station = station
	task.title = station.get(&"title") if station.get(&"title") else "Task %d" % tasks.size()
	task.zone = station.get(&"zone") if station.get(&"zone") else &""
	task.is_manager_task = is_manager
	task.hold_time = hold_time
	tasks.append(task)
	if station.has_method(&"set_task"):
		station.set_task(task)
	return task


func get_open_tasks() -> Array[TaskData]:
	var open: Array[TaskData] = []
	for task in tasks:
		if task.is_open():
			open.append(task)
	if sort_manager_first:
		var manager := open.filter(func(task: TaskData) -> bool: return task.is_manager_task)
		var basic := open.filter(func(task: TaskData) -> bool: return not task.is_manager_task)
		open.assign(manager + basic)
	return open


func claim_task(task: TaskData, worker: Node) -> bool:
	if task == null or not task.is_open():
		return false
	if task.claimed_by != null and task.claimed_by != worker and is_instance_valid(task.claimed_by):
		return false
	task.claimed_by = worker
	return true


func release_task(task: TaskData, worker: Node) -> void:
	if task != null and task.claimed_by == worker:
		task.claimed_by = null


func complete_task(task: TaskData, by: Node) -> void:
	if task == null or not task.is_open():
		return
	task.completed = true
	task.claimed_by = null
	completed.append(task)
	Events.task_completed.emit(task, by)
	Events.tasks_changed.emit()
