extends Node
## Autoload "Tasks": the night's task checklist (Store Environment system).
## STUB — public API only. The Store Environment task replaces the bodies.

const BASIC_TASKS_PER_NIGHT := 6


## Clears every task (call before a new night).
func reset() -> void:
	pass


## Picks this night's basic tasks from stations in group "task_station" and activates them.
func begin_night() -> void:
	pass


## Manager bonus task at `station`; fails after `time_limit` seconds. Sorted above basic tasks.
func add_manager_task(_station: Node3D, _time_limit: float) -> TaskData:
	return null


func complete_task(_task: TaskData, _by: Node) -> void:
	pass


## A coworker reserves a task so two workers do not walk to the same one.
func claim_task(_task: TaskData, _worker: Node) -> bool:
	return false


func release_task(_task: TaskData, _worker: Node) -> void:
	pass


## Open tasks, manager tasks first (soonest deadline first), then basic tasks.
func get_open_tasks() -> Array[TaskData]:
	return []


## Every task of the night for the HUD: open manager, open basic, then done/failed.
func get_tasks_for_checklist() -> Array[TaskData]:
	return []


func get_required_remaining() -> int:
	return 0


func all_required_done() -> bool:
	return get_required_remaining() == 0
