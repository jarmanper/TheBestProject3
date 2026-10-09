extends Player
## The foundation Player stub plus bare-bones controls for the AI sandbox:
## WASD move, Shift sprint (noise 1.0, the monster hears it), mouse look
## (click to capture, Esc to release), E hide in / leave the nearest HidingSpot.
## The real Player (systems/player) replaces all of this in the game.

const WALK_SPEED := 3.0
const SPRINT_SPEED := 5.6
const HIDE_REACH := 2.0

var noise := 0.0
var _pitch := 0.0

@onready var camera: Camera3D = $Camera3D


func get_camera() -> Camera3D:
	return camera


func get_noise_level() -> float:
	return 0.0 if is_hidden else noise


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * GameState.mouse_sensitivity)
		_pitch = clampf(_pitch - motion.relative.y * GameState.mouse_sensitivity, -1.4, 1.4)
		camera.rotation.x = _pitch
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed(&"pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed(&"interact"):
		_toggle_hiding()


func _physics_process(delta: float) -> void:
	if is_hidden or health <= 0.0:
		noise = 0.0
		velocity = Vector3.ZERO
		return
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var sprinting := Input.is_action_pressed(&"sprint") and input.length() > 0.1
	var direction := (global_basis * Vector3(input.x, 0.0, input.y))
	direction.y = 0.0
	direction = direction.normalized() * (SPRINT_SPEED if sprinting else WALK_SPEED)
	velocity.x = direction.x
	velocity.z = direction.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - 9.8 * delta
	move_and_slide()
	noise = 0.0 if input.length() < 0.1 else (1.0 if sprinting else 0.35)


func _toggle_hiding() -> void:
	if is_hidden:
		exit_hiding()
		return
	for spot: Node3D in get_tree().get_nodes_in_group(&"hiding_spot"):
		if spot.global_position.distance_to(global_position) <= HIDE_REACH:
			enter_hiding(spot)
			return
