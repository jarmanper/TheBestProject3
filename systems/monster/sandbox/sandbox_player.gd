extends Player
## The foundation Player stub plus bare-bones controls for the AI sandbox, used
## only while systems/player/player.tscn does not exist (see ai_sandbox.gd).
## WASD move, Shift sprint (noise 1.0, the monster hears it), mouse look
## (click to capture, Esc to release), E hide in / leave the nearest HidingSpot.
## Members are prefixed so they cannot clash with the real Player's.

const SANDBOX_WALK_SPEED := 3.0
const SANDBOX_SPRINT_SPEED := 5.6
const SANDBOX_HIDE_REACH := 2.0

var sandbox_noise := 0.0
var _sandbox_pitch := 0.0

@onready var sandbox_camera: Camera3D = $Camera3D


func get_camera() -> Camera3D:
	return sandbox_camera


func get_noise_level() -> float:
	return 0.0 if is_hidden else sandbox_noise


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * GameState.mouse_sensitivity)
		_sandbox_pitch = clampf(_sandbox_pitch - motion.relative.y * GameState.mouse_sensitivity, -1.4, 1.4)
		sandbox_camera.rotation.x = _sandbox_pitch
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed(&"pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed(&"interact"):
		_sandbox_toggle_hiding()


func _physics_process(delta: float) -> void:
	if is_hidden or health <= 0.0:
		sandbox_noise = 0.0
		velocity = Vector3.ZERO
		return
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var sprinting := Input.is_action_pressed(&"sprint") and input.length() > 0.1
	var direction := (global_basis * Vector3(input.x, 0.0, input.y))
	direction.y = 0.0
	direction = direction.normalized() * (SANDBOX_SPRINT_SPEED if sprinting else SANDBOX_WALK_SPEED)
	velocity.x = direction.x
	velocity.z = direction.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - 9.8 * delta
	move_and_slide()
	sandbox_noise = 0.0 if input.length() < 0.1 else (1.0 if sprinting else 0.35)


func _sandbox_toggle_hiding() -> void:
	if is_hidden:
		exit_hiding()
		return
	for spot: Node3D in get_tree().get_nodes_in_group(&"hiding_spot"):
		if spot.global_position.distance_to(global_position) <= SANDBOX_HIDE_REACH:
			enter_hiding(spot)
			return
