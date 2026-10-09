class_name HidingSpot
extends Interactable
## Locker / under-counter / box pile the player can hide in.
## Children: Marker3D "HidePoint" (camera pose while hidden), Marker3D "ExitPoint".
## Lockers additionally use a child Node3D "Door" that gets tweened open/closed.

@export var spot_kind: StringName = &"locker"   ## &"locker", &"counter", &"boxes"

var occupant: Node3D

var _door_tween: Tween


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


func get_prompt(player: Node) -> String:
	if is_occupied() and occupant != player:
		return ""
	return "Exit" if _is_hiding_here(player) else "Hide"


func can_interact(player: Node) -> bool:
	return not is_occupied() or occupant == player


func interact(player: Node) -> void:
	if player == null:
		return
	if _is_hiding_here(player):
		_exit(player)
	elif not is_occupied():
		_enter(player)


## The monster found the occupant: force them out (the monster deals the damage).
func pull_out_occupant() -> void:
	if occupant == null:
		return
	var forced := occupant
	_animate_door(true)
	if forced.has_method("exit_hiding"):
		forced.exit_hiding()
	occupant = null


func _is_hiding_here(player: Node) -> bool:
	return player != null and "is_hidden" in player and player.is_hidden \
		and "current_hiding_spot" in player and player.current_hiding_spot == self


func _enter(player: Node) -> void:
	occupant = player
	_play_enter_effects()
	player.enter_hiding(self)


func _exit(player: Node) -> void:
	_play_exit_effects()
	player.exit_hiding()
	occupant = null


func _play_enter_effects() -> void:
	match spot_kind:
		&"locker":
			_animate_door(true)
			Sfx.play_at(&"locker_open", global_position)
		&"boxes":
			Sfx.play_at(&"box_rustle", global_position)


func _play_exit_effects() -> void:
	match spot_kind:
		&"locker":
			_animate_door(false)
			Sfx.play_at(&"locker_close", global_position)
		&"boxes":
			Sfx.play_at(&"box_rustle", global_position)


func _animate_door(opening: bool) -> void:
	var door := get_node_or_null(^"Door") as Node3D
	if door == null:
		return
	var target_degrees := -100.0 if opening else 0.0
	if _door_tween and _door_tween.is_valid():
		_door_tween.kill()
	_door_tween = create_tween()
	_door_tween.tween_property(door, "rotation_degrees:y", target_degrees, 0.3)
