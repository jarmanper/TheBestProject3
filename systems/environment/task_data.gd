class_name TaskData
extends Resource
## One task on the night's checklist. Created by Tasks (the task manager).

var id: StringName = &""
var title := ""                      ## "Mop the spill in Aisle 3"
var zone: StringName = &""
var required_tool: StringName = &""  ## &"" when no tool is needed
var hold_time := 3.0
var is_manager_task := false
var time_limit := 0.0                ## manager tasks: seconds allowed (0 = no limit)
var time_left := 0.0
var completed := false
var failed := false
var station: Node3D                  ## the TaskStation that completes it
var assigned_to: StringName = &""    ## employee name, &"YOU", or empty for shared work
var claimed_by: Node                 ## coworker currently walking to / doing it


func is_open() -> bool:
	return not completed and not failed


## The player can help anyone; AI workers stick to their own basic assignments.
func can_be_worked_by(worker: Node) -> bool:
	if not is_instance_valid(worker):
		return false
	if worker.is_in_group(&"player") or assigned_to == &"":
		return true
	return worker is Coworker and assigned_to == StringName(worker.employee_name)
