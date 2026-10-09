class_name Interactable
extends Area3D
## Something the player can look at and use with the `interact` action.
## Lives on physics layer 5 (interact). Give it a CollisionShape3D child.
## The player calls get_prompt/can_interact/interact; for hold_time > 0 the
## player drives the hold timer and calls interact() once it fills.

@export var prompt_text := "Use"
@export var hold_time := 0.0


func _ready() -> void:
	collision_layer = Catalog.LAYER_INTERACT
	collision_mask = 0
	monitoring = false
	monitorable = true


## Text shown under the crosshair, e.g. "Mop spill" or "Needs: Mop".
func get_prompt(_player: Node) -> String:
	return prompt_text


func can_interact(_player: Node) -> bool:
	return true


func interact(_player: Node) -> void:
	pass


## The player started holding `interact` on this (hold_time > 0 only).
func hold_started(_player: Node) -> void:
	pass


## The hold ended without completing (released, looked away, moved).
func hold_stopped(_player: Node) -> void:
	pass
