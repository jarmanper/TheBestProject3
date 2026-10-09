class_name Player
extends CharacterBody3D
## First-person employee controlled by the human (docs/ARCHITECTURE.md §6).
## Movement, stamina, camera feel, flashlight, interaction ray + holds, hiding,
## damage/death and the held-tool viewmodel. Other systems use the public API only.

const WALK_SPEED := 3.0
const SPRINT_SPEED := 5.6
const ACCELERATION := 14.0
const DECELERATION := 16.0

const STAMINA_DRAIN := 20.0
const STAMINA_REGEN := 14.0
const STAMINA_REGEN_DELAY := 1.0
const STAMINA_RECOVER_AT := 35.0

const HEALTH_REGEN := 2.0
const HEALTH_REGEN_DELAY := 8.0
const DEATH_END_DELAY := 2.0

const FOV := 95.0
const SPRINT_FOV_BONUS := 4.0
const PITCH_LIMIT := deg_to_rad(85.0)
const HIDE_YAW_LIMIT := deg_to_rad(40.0)
const HIDE_PITCH_LIMIT := deg_to_rad(25.0)
const HIDE_BLEND_TIME := 0.35
const UNHIDE_BLEND_TIME := 0.25

const INTERACT_RANGE := 2.2
const HOLD_CANCEL_DISTANCE := 0.75

const NOISE_WALK := 0.35
const NOISE_SPRINT := 1.0
const NOISE_MIN_SPEED := 0.5

const BOB_RATE := 1.75             ## bob phase radians per metre travelled (one step per PI)
const BOB_VERTICAL := 0.035
const BOB_LATERAL := 0.02
const SPRINT_BOB_SCALE := 1.6
const SPRINT_ROLL := deg_to_rad(1.1)

const FLASHLIGHT_ENERGY := 1.8
const FLICKER_RADIUS := 12.0

const SHAKE_MAX_ANGLE := deg_to_rad(3.5)
const SHAKE_DECAY := 1.6

const EYE_HEIGHT := 1.6

var max_health := 100.0
var health := 100.0
var max_stamina := 100.0
var stamina := 100.0
var held_tool: StringName = &""
var is_hidden := false
var current_hiding_spot: Node3D
var input_enabled := true

var flashlight_on := true
var is_sprinting := false
var is_exhausted := false
## Look offset while hidden: x = yaw, y = pitch (radians, limited to ±40° / ±25°).
var hide_look := Vector2.ZERO

var _dead := false
var _death_timer := -1.0
var _death_anim := 0.0
var _stamina_wait := 0.0
var _since_damage := 999.0
var _trauma := 0.0
var _bob_phase := 0.0
var _bob_weight := 0.0
var _camera_bob := Vector3.ZERO
var _sprint_blend := 0.0
## Random source for the flashlight flicker (tests seed it).
var flicker_rng := RandomNumberGenerator.new()
var _flicker_timer := 0.0
var _flicker_level := 1.0
var _was_pressed := {}
var _edge_frames := {}

var _hide_pose := Transform3D.IDENTITY
var _blend_from := Transform3D.IDENTITY
var _blend_t := 1.0
var _returning := false

var _hold_target: Interactable
var _hold_elapsed := 0.0
var _hold_origin := Vector3.ZERO
var _last_prompt := ""

@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _head: Node3D = $Head
@onready var _camera: Camera3D = $Head/Camera3D
@onready var _flashlight: SpotLight3D = $Head/Camera3D/Flashlight
@onready var _viewmodel: PlayerViewmodel = $Head/Camera3D/Viewmodel


func _ready() -> void:
	add_to_group(&"player")
	collision_layer = Catalog.LAYER_PLAYER
	collision_mask = Catalog.LAYER_WORLD | Catalog.LAYER_NPC | Catalog.LAYER_MONSTER
	GameState.player = self
	_camera.fov = FOV
	_flashlight.light_cull_mask &= ~PlayerViewmodel.RENDER_LAYER
	_viewmodel.show_tool(held_tool)
	_apply_flashlight(1.0)


func _exit_tree() -> void:
	if GameState.player == self:
		GameState.player = null


# --- Public API (docs/ARCHITECTURE.md §6) ------------------------------------

func take_damage(amount: float, _from_position: Vector3) -> void:
	if _dead or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	_since_damage = 0.0
	_trauma = minf(_trauma + 0.55 + amount / 100.0, 1.0)
	GameState.add_stat("damage_taken", amount)
	Sfx.play(&"player_hurt")
	Events.player_damaged.emit(amount, health)
	if health <= 0.0:
		_die()


func enter_hiding(spot: Node3D) -> void:
	if is_hidden or _dead or spot == null:
		return
	_cancel_hold()
	is_hidden = true
	current_hiding_spot = spot
	hide_look = Vector2.ZERO
	velocity = Vector3.ZERO
	is_sprinting = false
	_hide_pose = spot.get_hide_transform() if spot.has_method(&"get_hide_transform") else spot.global_transform
	global_position = Vector3(_hide_pose.origin.x, global_position.y, _hide_pose.origin.z)
	_collision.set_deferred(&"disabled", true)
	_start_camera_blend(false)
	_viewmodel.visible = false
	_set_prompt("")
	GameState.add_stat("times_hidden")
	Events.player_hid.emit(spot)


func exit_hiding() -> void:
	if not is_hidden:
		return
	var spot := current_hiding_spot
	is_hidden = false
	current_hiding_spot = null
	# Face where the hidden camera was looking, standing at the exit point.
	var look_basis := _hidden_camera_transform().basis
	var forward := -look_basis.z
	var exit_position := global_position
	if is_instance_valid(spot) and spot.has_method(&"get_exit_position"):
		exit_position = spot.get_exit_position()
	_start_camera_blend(true)
	global_position = exit_position
	velocity = Vector3.ZERO
	if Vector2(forward.x, forward.z).length() > 0.01:
		rotation.y = atan2(-forward.x, -forward.z)
	_head.rotation.x = clampf(asin(clampf(forward.y, -1.0, 1.0)), -PITCH_LIMIT, PITCH_LIMIT)
	_collision.set_deferred(&"disabled", false)
	_viewmodel.visible = true
	Events.player_unhid.emit(spot)


func set_held_tool(tool_id: StringName) -> void:
	held_tool = tool_id
	if is_instance_valid(_viewmodel):
		_viewmodel.show_tool(tool_id)
	Events.held_tool_changed.emit(tool_id)


func has_tool(tool_id: StringName) -> bool:
	return tool_id == &"" or held_tool == tool_id


## 0 when still or hidden, 0.35 walking, 1.0 sprinting.
func get_noise_level() -> float:
	if is_hidden or _dead:
		return 0.0
	if Vector2(velocity.x, velocity.z).length() < NOISE_MIN_SPEED:
		return 0.0
	return NOISE_SPRINT if is_sprinting else NOISE_WALK


func get_eye_position() -> Vector3:
	if is_instance_valid(_camera) and _camera.is_inside_tree():
		return _camera.global_position
	return global_position + Vector3.UP * EYE_HEIGHT


func get_camera() -> Camera3D:
	return _camera


func is_dead() -> bool:
	return _dead


func set_flashlight(on: bool) -> void:
	if flashlight_on == on:
		return
	flashlight_on = on
	Sfx.play(&"flashlight_click", -6.0)
	Events.flashlight_toggled.emit(on)


## Mouse look. `relative` is in screen pixels (InputEventMouseMotion.screen_relative).
func apply_look(relative: Vector2) -> void:
	if not input_enabled or _dead:
		return
	var sensitivity := GameState.mouse_sensitivity
	if is_hidden:
		hide_look.x = clampf(hide_look.x - relative.x * sensitivity, -HIDE_YAW_LIMIT, HIDE_YAW_LIMIT)
		hide_look.y = clampf(hide_look.y - relative.y * sensitivity, -HIDE_PITCH_LIMIT, HIDE_PITCH_LIMIT)
		return
	rotate_y(-relative.x * sensitivity)
	_head.rotation.x = clampf(_head.rotation.x - relative.y * sensitivity, -PITCH_LIMIT, PITCH_LIMIT)
	_viewmodel.add_sway(relative)


## Stamina step. `wants_sprint` = sprint held while moving. Sets is_sprinting.
func update_stamina(delta: float, wants_sprint: bool) -> void:
	var before := stamina
	is_sprinting = wants_sprint and not is_exhausted and stamina > 0.0
	if is_sprinting:
		stamina = maxf(stamina - STAMINA_DRAIN * delta, 0.0)
		_stamina_wait = STAMINA_REGEN_DELAY
		if stamina <= 0.0:
			is_exhausted = true
			Sfx.play(&"breath_exhausted", -3.0)
	else:
		var regen_time := delta
		if _stamina_wait > 0.0:
			regen_time = maxf(delta - _stamina_wait, 0.0)
			_stamina_wait = maxf(_stamina_wait - delta, 0.0)
		stamina = minf(stamina + STAMINA_REGEN * regen_time, max_stamina)
		if is_exhausted and stamina >= STAMINA_RECOVER_AT:
			is_exhausted = false
	if not is_equal_approx(stamina, before):
		Events.stamina_changed.emit(stamina, max_stamina)


## Health regen step (2 hp/s once 8 s have passed without damage).
func update_health(delta: float) -> void:
	var before := _since_damage
	_since_damage += delta
	if _dead or health >= max_health:
		return
	var regen_time := _since_damage - maxf(before, HEALTH_REGEN_DELAY)
	if regen_time > 0.0:
		health = minf(health + HEALTH_REGEN * regen_time, max_health)


## Death countdown: ends the night as &"dead" DEATH_END_DELAY s after dying.
func update_death(delta: float) -> void:
	if not _dead or _death_timer < 0.0:
		return
	_death_timer -= delta
	if _death_timer <= 0.0:
		_death_timer = -1.0
		GameState.end_night(&"dead")


# --- Frame updates -------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion:
		apply_look(motion.screen_relative)


func _physics_process(delta: float) -> void:
	var can_act := input_enabled and not _dead
	var move_input := Vector2.ZERO
	if can_act and not is_hidden:
		move_input = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var wants_sprint := can_act and not is_hidden and move_input.length() > 0.1 \
		and Input.is_action_pressed(&"sprint")
	update_stamina(delta, wants_sprint)
	if is_hidden:
		velocity = Vector3.ZERO
	else:
		_move(delta, move_input)
	var interact_edge := _action_edge(&"interact")
	var flashlight_edge := _action_edge(&"flashlight")
	if can_act and flashlight_edge:
		set_flashlight(not flashlight_on)
	_update_interaction(delta, can_act, interact_edge)


func _process(delta: float) -> void:
	update_health(delta)
	update_death(delta)
	_update_camera(delta)
	update_flashlight(delta)


func _move(delta: float, move_input: Vector2) -> void:
	var direction := (transform.basis * Vector3(move_input.x, 0.0, move_input.y))
	direction.y = 0.0
	if direction.length() > 1.0:
		direction = direction.normalized()
	var target := direction * (SPRINT_SPEED if is_sprinting else WALK_SPEED)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate := ACCELERATION if direction.length() > 0.01 else DECELERATION
	horizontal = horizontal.move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		velocity.y = minf(velocity.y, 0.0)
	else:
		velocity += get_gravity() * delta
	move_and_slide()


## Buttons already down (e.g. the click that resumed the game or recaptured the mouse) must
## be released before they act; also blocks a just-pressed edge for the next tick.
func ignore_held_actions() -> void:
	_cancel_hold()
	var frame := Engine.get_physics_frames()
	for action in [&"interact", &"flashlight"]:
		_was_pressed[action] = Input.is_action_pressed(action)
		_edge_frames[action] = frame


## True on the physics tick `action` went down. Manual edge detection (works for
## Input.action_press too); is_action_just_pressed only catches taps released
## within one tick. Never fires on two consecutive ticks.
func _action_edge(action: StringName) -> bool:
	var pressed := Input.is_action_pressed(action)
	var was: bool = _was_pressed.get(action, false)
	_was_pressed[action] = pressed
	var edge := (pressed and not was) or (not pressed and Input.is_action_just_pressed(action))
	if not edge:
		return false
	var frame := Engine.get_physics_frames()
	if frame - int(_edge_frames.get(action, -10)) <= 1:
		return false
	_edge_frames[action] = frame
	return true


# --- Interaction ------------------------------------------------------------------

func _update_interaction(delta: float, can_act: bool, interact_edge: bool) -> void:
	if is_hidden:
		_set_prompt("[E] Leave" if can_act else "")
		if can_act and interact_edge:
			_leave_hiding_spot()
		return
	var target := _find_interactable() if can_act else null
	var prompt := ""
	var allowed := false
	if target:
		var text := target.get_prompt(self)
		allowed = target.can_interact(self) and not text.is_empty()
		if not text.is_empty():
			prompt = ("[E] " + text) if allowed else text
	_set_prompt(prompt)

	if _hold_target:
		var keep := _hold_target == target and allowed and Input.is_action_pressed(&"interact") \
			and global_position.distance_to(_hold_origin) <= HOLD_CANCEL_DISTANCE
		if not keep:
			_cancel_hold()

	if target and allowed and interact_edge and _hold_target == null:
		if target.hold_time <= 0.0:
			target.interact(self)
		else:
			_hold_target = target
			_hold_elapsed = 0.0
			_hold_origin = global_position
			target.hold_started(self)
			Events.interaction_progress.emit(0.0)

	if _hold_target:
		_hold_elapsed += delta
		var fraction := clampf(_hold_elapsed / _hold_target.hold_time, 0.0, 1.0)
		Events.interaction_progress.emit(fraction)
		if fraction >= 1.0:
			var done := _hold_target
			_hold_target = null
			Events.interaction_progress.emit(-1.0)
			done.interact(self)


func _find_interactable() -> Interactable:
	if not is_inside_tree():
		return null
	var origin := _camera.global_position
	var query := PhysicsRayQueryParameters3D.create(origin,
		origin - _camera.global_transform.basis.z * INTERACT_RANGE,
		Catalog.LAYER_WORLD | Catalog.LAYER_INTERACT, [get_rid()])
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	return hit.collider as Interactable


func _cancel_hold() -> void:
	if _hold_target == null:
		return
	var target := _hold_target
	_hold_target = null
	Events.interaction_progress.emit(-1.0)
	if is_instance_valid(target):
		target.hold_stopped(self)


func _set_prompt(text: String) -> void:
	if text == _last_prompt:
		return
	_last_prompt = text
	Events.interaction_prompt_changed.emit(text)


## Interact pressed while hidden: let the spot handle it (it toggles), else leave ourselves.
func _leave_hiding_spot() -> void:
	var spot := current_hiding_spot
	if is_instance_valid(spot):
		spot.interact(self)
	if is_hidden:
		exit_hiding()   # the spot is gone (freed) or did not release us


# --- Camera -------------------------------------------------------------------------

func _start_camera_blend(returning: bool) -> void:
	_blend_from = _camera.global_transform
	_blend_t = 0.0
	_returning = returning
	_camera.top_level = true
	_camera.global_transform = _blend_from


func _hidden_camera_transform() -> Transform3D:
	var look := Basis(Vector3.UP, hide_look.x) * Basis(Vector3.RIGHT, hide_look.y)
	return Transform3D(_hide_pose.basis.orthonormalized() * look, _hide_pose.origin)


func _update_camera(delta: float) -> void:
	_trauma = maxf(_trauma - SHAKE_DECAY * delta, 0.0)
	_update_bob(delta)
	var shake := _trauma * _trauma
	var shake_rot := Vector3(
		randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * SHAKE_MAX_ANGLE * shake
	var roll := sin(_bob_phase) * SPRINT_ROLL * _sprint_blend * _bob_weight
	var local := Transform3D(Basis.from_euler(Vector3(shake_rot.x, shake_rot.y, roll + shake_rot.z)), _camera_bob)

	if _dead:
		_death_anim = minf(_death_anim + delta / 1.2, 1.0)
		var fall := ease(_death_anim, 0.4)
		_head.position.y = lerpf(EYE_HEIGHT, 0.35, fall)
		local.basis = Basis.from_euler(Vector3(-0.35 * fall, 0.0, deg_to_rad(75.0) * fall)) * local.basis

	if _camera.top_level:
		_blend_t = minf(_blend_t + delta / (UNHIDE_BLEND_TIME if _returning else HIDE_BLEND_TIME), 1.0)
		var target := (_head.global_transform * local) if _returning else _hidden_camera_transform()
		var weight := ease(_blend_t, -2.0)
		_camera.global_transform = _blend_from.interpolate_with(target, weight)
		if _returning and _blend_t >= 1.0:
			_camera.top_level = false
			_camera.transform = local
	else:
		_camera.transform = local
	var target_fov := FOV + SPRINT_FOV_BONUS * _sprint_blend
	_camera.fov = lerpf(_camera.fov, target_fov, clampf(6.0 * delta, 0.0, 1.0))
	_viewmodel.update_motion(delta, _camera_bob)


func _update_bob(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	var moving := speed > 0.3 and is_on_floor() and not is_hidden and not _dead
	_bob_weight = move_toward(_bob_weight, 1.0 if moving else 0.0, delta * 4.0)
	_sprint_blend = move_toward(_sprint_blend, 1.0 if (is_sprinting and moving) else 0.0, delta * 3.0)
	if moving:
		var previous := _bob_phase
		_bob_phase += speed * BOB_RATE * delta
		if floorf(previous / PI) != floorf(_bob_phase / PI):
			_footstep()
	var amount := _bob_weight * clampf(speed / WALK_SPEED, 0.0, 1.0) * lerpf(1.0, SPRINT_BOB_SCALE, _sprint_blend)
	_camera_bob = Vector3(
		sin(_bob_phase) * BOB_LATERAL * amount,
		(absf(sin(_bob_phase)) * 2.0 - 1.0) * BOB_VERTICAL * amount,
		0.0)


func _footstep() -> void:
	var volume := -4.0 if is_sprinting else -12.0
	Sfx.play_at(&"footstep_tile", global_position, volume, randf_range(0.92, 1.08), 25.0)


# --- Flashlight ------------------------------------------------------------------------

## 0 beyond FLICKER_RADIUS from GameState.monster, rising to 1 at the player.
func get_monster_disturbance() -> float:
	var monster := GameState.monster
	if not is_instance_valid(monster) or not monster.is_inside_tree() or not is_inside_tree():
		return 0.0
	var distance := monster.global_position.distance_to(global_position)
	return clampf(1.0 - distance / FLICKER_RADIUS, 0.0, 1.0)


## Flashlight flicker step (called from _process). Random dips use `flicker_rng`.
func update_flashlight(delta: float) -> void:
	var disturbance := get_monster_disturbance()
	if disturbance > 0.0:
		_flicker_timer -= delta
		if _flicker_timer <= 0.0:
			_flicker_timer = flicker_rng.randf_range(0.03, 0.16)
			_flicker_level = flicker_rng.randf_range(0.0, 0.35) if flicker_rng.randf() < disturbance * 0.75 \
				else flicker_rng.randf_range(0.8, 1.0)
	else:
		_flicker_level = 1.0
	_apply_flashlight(_flicker_level)


func _apply_flashlight(level: float) -> void:
	var on := flashlight_on and not is_hidden
	_flashlight.visible = on
	_flashlight.light_energy = FLASHLIGHT_ENERGY * level


func _die() -> void:
	if is_hidden:
		# Leave the spot first so the camera falls from the body, and the spot is free again.
		var spot := current_hiding_spot
		if is_instance_valid(spot) and spot.has_method(&"pull_out_occupant"):
			spot.pull_out_occupant()
		if is_hidden:
			exit_hiding()
	_dead = true
	input_enabled = false
	is_sprinting = false
	_cancel_hold()
	_set_prompt("")
	_death_timer = DEATH_END_DELAY
	_death_anim = 0.0
	_viewmodel.visible = false
	Sfx.play(&"player_death")
	Events.player_died.emit()
