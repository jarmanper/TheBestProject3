class_name TaskStation
extends Interactable
## A place in the store where one kind of task gets done.

const VERB_PROMPTS := {
	&"mop_spill": "Mop spill",
	&"restock": "Restock shelf",
	&"face_shelf": "Face shelves",
	&"register": "Count register",
	&"price_update": "Update price labels",
	&"freezer_log": "Log freezer temperature",
	&"boxes": "Break down boxes",
	&"trash": "Empty trash",
	&"breaker": "Reset the breaker",
	&"safe": "Lock the safe",
}

@export var task_kind: StringName = &""       ## &"mop_spill", &"restock", ...
@export var zone: StringName = &""
@export var title := ""                       ## checklist text, e.g. "Mop the spill in Aisle 3"
@export var required_tool: StringName = &""
@export var basic_task := true                ## eligible for the nightly basic list
@export var manager_line := ""                ## what the manager says when assigning it

var task: TaskData                            ## the active task here, or null

var _progress_player: AudioStreamPlayer3D


func _ready() -> void:
	super()
	add_to_group(&"task_station")
	_update_active_visual()


func is_active() -> bool:
	return task != null and task.is_open()


## Called by Tasks when a task here becomes active / finishes.
func set_task(new_task: TaskData) -> void:
	task = new_task
	_update_active_visual()


## Where a worker stands to do this task.
func get_work_position() -> Vector3:
	var marker := get_node_or_null(^"WorkPoint") as Node3D
	return marker.global_position if marker else global_position


func get_prompt(player: Node) -> String:
	if not is_active():
		return ""
	if not player.has_tool(required_tool):
		return "Needs: %s" % Catalog.tool_name(required_tool)
	return VERB_PROMPTS.get(task_kind, title if not title.is_empty() else "Do task")


func can_interact(player: Node) -> bool:
	if not is_active():
		return false
	return player.has_tool(required_tool)


func interact(player: Node) -> void:
	if not is_active() or not player.has_tool(required_tool):
		return
	_stop_progress_sound()
	Sfx.play_at(&"task_complete", global_position)
	Tasks.complete_task(task, player)


## The player started holding `interact` on this (hold_time > 0 only).
func hold_started(_player: Node) -> void:
	_stop_progress_sound()
	_progress_player = Sfx.play_at(&"task_progress", global_position)


## The hold ended without completing (released, looked away, moved).
func hold_stopped(_player: Node) -> void:
	_stop_progress_sound()


func _stop_progress_sound() -> void:
	if _progress_player and is_instance_valid(_progress_player):
		_progress_player.queue_free()
	_progress_player = null


func _update_active_visual() -> void:
	var visual := get_node_or_null(^"ActiveVisual")
	if visual:
		visual.visible = is_active()
