class_name Player
extends CharacterBody3D
## First-person employee controlled by the human.
## STUB — public API with minimal behaviour so other systems can be tested
## against it. The Player task replaces this with the real controller.

var max_health := 100.0
var health := 100.0
var max_stamina := 100.0
var stamina := 100.0
var held_tool: StringName = &""
var is_hidden := false
var current_hiding_spot: Node3D
var input_enabled := true


func _ready() -> void:
	add_to_group(&"player")
	collision_layer = Catalog.LAYER_PLAYER
	collision_mask = Catalog.LAYER_WORLD | Catalog.LAYER_NPC
	GameState.player = self


func take_damage(amount: float, _from_position: Vector3) -> void:
	if health <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	Events.player_damaged.emit(amount, health)
	if health <= 0.0:
		Events.player_died.emit()


func enter_hiding(spot: Node3D) -> void:
	is_hidden = true
	current_hiding_spot = spot
	Events.player_hid.emit(spot)


func exit_hiding() -> void:
	var spot := current_hiding_spot
	is_hidden = false
	current_hiding_spot = null
	Events.player_unhid.emit(spot)


func set_held_tool(tool_id: StringName) -> void:
	held_tool = tool_id
	Events.held_tool_changed.emit(tool_id)


func has_tool(tool_id: StringName) -> bool:
	return tool_id == &"" or held_tool == tool_id


## 0 when still or hidden, 0.35 walking, 1.0 sprinting.
func get_noise_level() -> float:
	return 0.0


func get_eye_position() -> Vector3:
	return global_position + Vector3.UP * 1.6


func get_camera() -> Camera3D:
	return null
