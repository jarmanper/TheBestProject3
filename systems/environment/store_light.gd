class_name StoreLight
extends Node3D
## One ceiling fixture: a light plus the emissive tube mesh it belongs to.
## STUB — public API only. The Store Environment task replaces the bodies.

@export var base_energy := 1.0
@export var always_flicker := false   ## a "broken" fixture
@export var starts_off := false


func _ready() -> void:
	add_to_group(&"store_light")


## 0 = steady, 1 = violent flicker. Called by the monster's proximity effect.
func set_disturbance(_amount: float) -> void:
	pass
