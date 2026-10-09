extends CharacterBody3D
## Test double with the Player contract API (docs/ARCHITECTURE.md §6) and a
## settable noise level. It does not extend Player on purpose, so the monster
## and coworker tests keep working unchanged when the real Player (its nodes,
## _ready and input handling) replaces the foundation stub.

var max_health := 100.0
var health := 100.0
var is_hidden := false
var current_hiding_spot: Node3D
var held_tool: StringName = &""
var noise := 0.0                       ## what get_noise_level() reports while not hidden


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


func get_noise_level() -> float:
	return 0.0 if is_hidden else noise


func get_eye_position() -> Vector3:
	return global_position + Vector3.UP * 1.6


func get_camera() -> Camera3D:
	return get_node_or_null(^"Camera3D") as Camera3D
