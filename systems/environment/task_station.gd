class_name TaskStation
extends Interactable
## A place in the store where one kind of task gets done.
## STUB — public API only. The Store Environment task replaces the bodies.

@export var task_kind: StringName = &""       ## &"mop_spill", &"restock", ...
@export var zone: StringName = &""
@export var title := ""                       ## checklist text, e.g. "Mop the spill in Aisle 3"
@export var required_tool: StringName = &""
@export var basic_task := true                ## eligible for the nightly basic list
@export var manager_line := ""                ## what the manager says when assigning it

var task: TaskData                            ## the active task here, or null


func _ready() -> void:
	super()
	add_to_group(&"task_station")


func is_active() -> bool:
	return task != null and task.is_open()


## Called by Tasks when a task here becomes active / finishes.
func set_task(new_task: TaskData) -> void:
	task = new_task


## Where a worker stands to do this task.
func get_work_position() -> Vector3:
	return global_position
