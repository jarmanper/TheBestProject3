class_name Coworker
extends CharacterBody3D
## An AI employee (DALE, RITA, MARCUS). Works the night's tasks, manager tasks
## first (GDD seam 2), rests between them, checks in on the walkie with where
## they really are, and runs when they see the monster's true form.
## Real coworkers have footsteps; the disguised monster does not.
## The monster can take them: abduct().

const WALK_SPEED := 2.0
const FLEE_SPEED := 4.5
const WORK_TIME_FACTOR := 4.0            ## works a task for hold_time x 4
const REST_TIME := Vector2(25.0, 50.0)   ## rest/wander after each task
const IDLE_RECHECK := Vector2(6.0, 12.0) ## nothing free: stroll, then look again
const WANDER_PAUSE := Vector2(5.0, 12.0)
const CHATTER_INTERVAL := Vector2(60.0, 120.0)
const FLEE_SIGHT_RANGE := 15.0
const FLEE_MAX_TIME := 15.0
const PANIC_LINE_COOLDOWN := 20.0
const REACH_DISTANCE := 2.5              ## close enough to a station to work it
const UNREACHABLE_SKIP := 30.0           ## ignore a task it could not reach this long
const ARRIVE_DISTANCE := 0.6
const EYE_HEIGHT := 1.6
const STEP_WALK := 1.0
const STEP_RUN := 1.5
const FOOTSTEP_VOLUME_DB := -14.0        ## quiet but positional
const FOOTSTEP_RANGE := 16.0
const TURN_SPEED := 8.0
const GRAVITY := 9.8

const CHOOSE := &"choose"
const TO_TASK := &"to_task"
const WORKING := &"working"
const RESTING := &"resting"
const FLEEING := &"fleeing"

@export var employee_name := "DALE"
@export var model_path := ""             ## set before _ready (from Catalog.COWORKERS)

## Where tasks come from; null means the Tasks autoload. Must offer
## get_open_tasks(), claim_task(task, worker), release_task(task, worker),
## complete_task(task, by) like Tasks does.
var task_source: Object
var state: StringName = CHOOSE
var state_time := 0.0
var current_task: TaskData
var rng := RandomNumberGenerator.new()

var _timer := 0.0
var _clock := 0.0
var _skip_until := {}                    ## TaskData -> _clock time it may be tried again
var _wander_left := 0.0
var _chatter_left := 0.0
var _panic_cooldown := 0.0
var _moving := false
var _target := Vector3.ZERO
var _speed := WALK_SPEED
var _face_point: Variant = null
var _yaw := 0.0
var _stuck_time := 0.0
var _stuck_check_pos := Vector3.ZERO
var _step_distance := 0.0
var _nav_ok := false
var _model: Node3D
var _anim: AnimationPlayer

@onready var _visual: Node3D = $Visual
@onready var _agent: NavigationAgent3D = $NavigationAgent3D


func _ready() -> void:
	add_to_group(&"coworker")
	add_to_group(&"employee")
	collision_layer = Catalog.LAYER_NPC
	collision_mask = Catalog.LAYER_WORLD
	rng.randomize()
	_model = CharacterModel.instantiate(model_path, CharacterModel.Placeholder.EMPLOYEE, employee_name)
	_visual.add_child(_model)
	_anim = CharacterModel.find_animation_player(_model)
	_yaw = rotation.y
	_target = global_position
	_chatter_left = _roll(CHATTER_INTERVAL)
	_set_state(CHOOSE)
	_timer = rng.randf_range(0.5, 3.0)   # stagger the first look at the checklist


func _exit_tree() -> void:
	_drop_task()


func _physics_process(delta: float) -> void:
	tick(delta)


## One AI step. Tests may turn physics processing off and call this directly.
func tick(delta: float) -> void:
	state_time += delta
	_clock += delta
	_panic_cooldown = maxf(_panic_cooldown - delta, 0.0)
	if not _nav_ok:   # once the map has synced it stays usable
		_nav_ok = AiNav.is_ready(_agent.get_navigation_map(), global_position)
	if state != FLEEING and _sees_true_monster():
		_start_flee()
	match state:
		CHOOSE: _tick_choose(delta)
		TO_TASK: _tick_to_task(delta)
		WORKING: _tick_working(delta)
		RESTING: _tick_resting(delta)
		FLEEING: _tick_fleeing(delta)
	_chatter(delta)
	_move(delta)
	_footsteps(delta)
	_update_animation()


# --- Public API -------------------------------------------------------------------

## The task this worker would take now: open manager tasks first (GDD seam 2),
## then the nearest open basic task. Skips tasks another worker has claimed.
func choose_task() -> TaskData:
	var best: TaskData = null
	var best_key := Vector2(INF, INF)
	for task: TaskData in _source().get_open_tasks():
		if task == null or not task.is_open() or not is_instance_valid(task.station):
			continue
		if task.claimed_by != null and task.claimed_by != self and is_instance_valid(task.claimed_by):
			continue
		if _skip_until.get(task, 0.0) > _clock:
			continue
		var key := Vector2(0.0 if task.is_manager_task else 1.0, global_position.distance_to(_work_position(task)))
		if key.x < best_key.x or (key.x == best_key.x and key.y < best_key.y):
			best = task
			best_key = key
	return best


## Truthful walkie check-in about where this worker is right now.
func say_where_i_am() -> void:
	var zone_id := StoreZone.find_zone_id_at(get_tree(), global_position)
	var activity := &"resting"
	if state == WORKING:
		activity = &"working"
	elif state == TO_TASK:
		activity = &"heading"
	var title := current_task.title if current_task != null else ""
	var line := CoworkerLines.chatter_line(employee_name, zone_id, activity, title, rng)
	Events.walkie_message.emit(employee_name, line, global_position, false)


## The monster took this worker: release any claim and vanish.
func abduct() -> void:
	_drop_task()
	set_physics_process(false)
	queue_free()


# --- States ---------------------------------------------------------------------------

func _set_state(new_state: StringName) -> void:
	state = new_state
	state_time = 0.0
	_face_point = null
	match new_state:
		CHOOSE:
			_timer = 0.0
		TO_TASK:
			_go_to(_snap_to_nav(_work_position(current_task)), WALK_SPEED)
		WORKING:
			_stop()
			_timer = current_task.hold_time * WORK_TIME_FACTOR
			_face_point = current_task.station.global_position
		RESTING:
			_timer = _roll(REST_TIME)
			_wander_left = rng.randf_range(0.0, 4.0)
		FLEEING:
			_go_to(_flee_point(), FLEE_SPEED)


func _tick_choose(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	var task := choose_task()
	if task != null and _source().claim_task(task, self):
		current_task = task
		_set_state(TO_TASK)
		return
	_timer = _roll(IDLE_RECHECK)
	_go_to(_wander_point(), WALK_SPEED)


func _tick_to_task(_delta: float) -> void:
	if not _still_mine(current_task):
		_drop_task()
		_set_state(CHOOSE)
		return
	if _moving:
		return
	if _flat_distance(global_position, _work_position(current_task)) <= REACH_DISTANCE:
		_set_state(WORKING)
	else:
		_skip_until[current_task] = _clock + UNREACHABLE_SKIP
		_drop_task()   # cannot reach it; let someone else try
		_set_state(CHOOSE)
		_timer = _roll(IDLE_RECHECK)


func _tick_working(delta: float) -> void:
	if not _still_mine(current_task):
		_drop_task()
		_set_state(CHOOSE)
		return
	_timer -= delta
	if _timer > 0.0:
		return
	var task := current_task
	current_task = null
	_source().complete_task(task, self)
	_set_state(RESTING)


func _tick_resting(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_set_state(CHOOSE)
		return
	if not _moving:
		_wander_left -= delta
		if _wander_left <= 0.0:
			_wander_left = _roll(WANDER_PAUSE)
			_go_to(_wander_point(), WALK_SPEED)


func _tick_fleeing(_delta: float) -> void:
	if not _moving or state_time >= FLEE_MAX_TIME:
		_set_state(RESTING)


func _start_flee() -> void:
	_drop_task()
	if _panic_cooldown <= 0.0:
		_panic_cooldown = PANIC_LINE_COOLDOWN
		var zone_id := StoreZone.find_zone_id_at(get_tree(), global_position)
		Events.walkie_message.emit(employee_name, CoworkerLines.panic_line(employee_name, zone_id, rng), global_position, false)
	_set_state(FLEEING)


func _sees_true_monster() -> bool:
	var monster := GameState.monster
	if monster == null or not is_instance_valid(monster) or not monster.is_inside_tree():
		return false
	if not monster.has_method(&"is_true_form") or not monster.is_true_form():
		return false
	var eye := global_position + Vector3.UP * EYE_HEIGHT
	var target := monster.global_position + Vector3.UP * 1.5
	if eye.distance_to(target) > FLEE_SIGHT_RANGE:
		return false
	return Perception.has_line_of_sight(get_world_3d().direct_space_state, eye, target)


func _chatter(delta: float) -> void:
	_chatter_left -= delta
	if _chatter_left > 0.0:
		return
	_chatter_left = _roll(CHATTER_INTERVAL)
	if state != FLEEING:
		say_where_i_am()


# --- Tasks -------------------------------------------------------------------------------

func _source() -> Object:
	return task_source if task_source != null else Tasks


func _still_mine(task: TaskData) -> bool:
	return task != null and task.is_open() and is_instance_valid(task.station) \
		and (task.claimed_by == null or task.claimed_by == self)


func _drop_task() -> void:
	if current_task != null and (current_task.claimed_by == self or current_task.claimed_by == null):
		_source().release_task(current_task, self)
	current_task = null


func _work_position(task: TaskData) -> Vector3:
	var station := task.station
	if station.has_method(&"get_work_position"):
		return station.get_work_position()
	return station.global_position


# --- Places ----------------------------------------------------------------------------

func _wander_point() -> Vector3:
	var zones := get_tree().get_nodes_in_group(&"store_zone")
	var patrol := get_tree().get_nodes_in_group(&"patrol_point")
	var point := global_position + Vector3.FORWARD.rotated(Vector3.UP, rng.randf() * TAU) * rng.randf_range(3.0, 8.0)
	var roll := rng.randf()
	if not zones.is_empty() and roll < 0.6:
		point = AiNav.random_point_in_zone(zones[rng.randi() % zones.size()], rng)
	elif not patrol.is_empty():
		point = (patrol[rng.randi() % patrol.size()] as Node3D).global_position
	return _snap_to_nav(point)


## The patrol point (or zone centre) farthest from the monster.
func _flee_point() -> Vector3:
	var danger := global_position
	if is_instance_valid(GameState.monster):
		danger = GameState.monster.global_position
	var best := global_position + (global_position - danger).normalized() * 10.0
	var best_distance := -1.0
	var points: Array[Vector3] = []
	for marker in get_tree().get_nodes_in_group(&"patrol_point"):
		points.append((marker as Node3D).global_position)
	for zone: StoreZone in get_tree().get_nodes_in_group(&"store_zone"):
		points.append(zone.get_bounds().get_center())
	for point in points:
		var distance := _flat_distance(point, danger)
		if distance > best_distance:
			best_distance = distance
			best = point
	return _snap_to_nav(Vector3(best.x, 0.0, best.z))


# --- Movement, sound, animation ------------------------------------------------------------

func _go_to(point: Vector3, speed: float) -> void:
	_speed = speed
	_moving = true
	_target = point
	_agent.target_position = point


func _stop() -> void:
	_moving = false


func _move(delta: float) -> void:
	var horizontal := Vector3.ZERO
	if _moving:
		if _flat_distance(global_position, _target) <= ARRIVE_DISTANCE:
			_moving = false
		else:
			var next := _agent.get_next_path_position() if _nav_ok else _target
			var to_next := next - global_position
			to_next.y = 0.0
			if to_next.length() > 0.05:
				horizontal = to_next.normalized() * _speed
			elif not _nav_ok or _agent.is_navigation_finished():
				_moving = false
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()
	_check_stuck(delta, horizontal)
	var look := horizontal
	if _face_point != null:
		look = (_face_point as Vector3) - global_position
	look.y = 0.0
	if look.length() > 0.01:
		_yaw = lerp_angle(_yaw, atan2(look.x, look.z), clampf(TURN_SPEED * delta, 0.0, 1.0))
		look_at(global_position + Vector3(sin(_yaw), 0.0, cos(_yaw)), Vector3.UP, true)


## Gives up on a target it cannot make progress toward (treated as arrived).
func _check_stuck(delta: float, horizontal: Vector3) -> void:
	if horizontal.length() < 0.1:
		_stuck_time = 0.0
		_stuck_check_pos = global_position
		return
	_stuck_time += delta
	if _stuck_time >= 2.0:
		if global_position.distance_to(_stuck_check_pos) < 0.3:
			_moving = false
		_stuck_time = 0.0
		_stuck_check_pos = global_position


func _snap_to_nav(point: Vector3) -> Vector3:
	return AiNav.snap(_agent.get_navigation_map(), _nav_ok, point, global_position.y)


func _footsteps(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed < 0.3:
		return
	_step_distance += speed * delta
	if _step_distance >= (STEP_RUN if speed > 3.0 else STEP_WALK):
		_step_distance = 0.0
		Sfx.play_at(&"footstep_tile", global_position, FOOTSTEP_VOLUME_DB, rng.randf_range(0.92, 1.08), FOOTSTEP_RANGE)


func _update_animation() -> void:
	if _anim == null:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed < CharacterModel.IDLE_BELOW and state == WORKING:
		CharacterModel.play(_anim, Catalog.ANIM_WORK)
	else:
		# Clip and speed_scale from the employee clips' measured ground speed: no foot sliding.
		CharacterModel.play_locomotion(_anim, &"employee", speed)


func _roll(span: Vector2) -> float:
	return rng.randf_range(span.x, span.y)


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
