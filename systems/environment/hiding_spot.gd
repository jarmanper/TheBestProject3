class_name HidingSpot
extends Interactable
## Locker / under-counter / box pile the player can hide in.
## Children: Marker3D "HidePoint" (camera pose while hidden), Marker3D "ExitPoint".
## STUB — public API only. The Store Environment task replaces the bodies.

@export var spot_kind: StringName = &"locker"   ## &"locker", &"counter", &"boxes"

var occupant: Node3D


func _ready() -> void:
	super()
	add_to_group(&"hiding_spot")


func is_occupied() -> bool:
	return occupant != null


func get_hide_transform() -> Transform3D:
	var marker := get_node_or_null(^"HidePoint") as Node3D
	return marker.global_transform if marker else global_transform


func get_exit_position() -> Vector3:
	var marker := get_node_or_null(^"ExitPoint") as Node3D
	return marker.global_position if marker else global_position


## The monster found the occupant: force them out (the monster deals the damage).
func pull_out_occupant() -> void:
	pass
