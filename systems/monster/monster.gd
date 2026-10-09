class_name Monster
extends CharacterBody3D
## The mimic (GDD §5). It roams disguised as one of the coworkers, lures the
## player with fake walkie calls in their voices, abducts coworkers, and hunts
## the player under three rules players can learn:
##   1. It sprints at most SPRINT_MAX_TIME seconds, then is winded for WINDED_TIME.
##   2. Disguised, it turns once the player lingers within REVEAL_RANGE in line of
##      sight for REVEAL_TIME (it stops and stares first).
##   3. If the player has not seen it by SIGHTING_DEADLINE_HOUR, it stages a sighting.
## Rule timers live in MonsterRules, sight checks in Perception. It never
## teleports or changes form while the player can see it, except the deliberate
## reveal and the staged sighting's appearance.

# --- GDD rules (see docs/ARCHITECTURE.md "Monster rules") ---------------------
const SPRINT_MAX_TIME := 13.0           ## rule 1: seconds of sprinting before it is winded
const WINDED_TIME := 6.0                ## rule 1: seconds slow and wheezing
const REVEAL_RANGE := 7.0               ## rule 2: metres
const REVEAL_TIME := 4.0                ## rule 2: seconds of lingering before it turns
const SIGHTING_DEADLINE_HOUR := 2       ## rule 3: 2:00 AM

# --- Hunting ------------------------------------------------------------------
const ATTACK_RANGE := 1.7
const ATTACK_DAMAGE := 45.0
const CHASE_SPEED := 5.2                ## the player sprints 5.6, walks 3.0
const DISGUISED_SPEED := 2.0            ## same as a coworker's walk
const WINDED_SPEED := 1.2
const LOSE_TRACK_TIME := 4.0            ## chase without sight this long -> search
const REVEAL_COOLDOWN := 25.0           ## after a chase ends, no reveal for this long
const HEARING_RADIUS := 14.0            ## hears a sprinting player (noise >= 1) this far
const MAX_ABDUCTIONS := 2
const ABDUCT_EARLIEST_HOUR := 1
const FLICKER_RADIUS := 12.0            ## store lights within this flicker

# --- Tuning -------------------------------------------------------------------
const SIGHT_RANGE := 30.0               ## max seeing distance, both ways
const SEARCH_SPEED := 3.0
const RETREAT_SPEED := 4.0
const BURST_SPEED := 4.6                ## disguise tell: short too-fast bursts
const BURST_TIME := 0.45
const BURST_INTERVAL := Vector2(7.0, 15.0)
const STARE_AFTER := 1.0                ## rule 2 tell: stops and stares after this much lingering
const REVEAL_DURATION := Vector2(1.2, 1.5)
const ATTACK_WINDUP := 0.45             ## lunges during the wind-up, hits at its end
const ATTACK_RECOVER := 0.6
const INVESTIGATE_LINGER := Vector2(10.0, 20.0)
const LURE_TIME := 45.0
const LURE_MIN_DISTANCE := 18.0
const SEARCH_TIME := 10.0
const SEARCH_TRAVEL_MAX := 15.0
const SEARCH_HOP_RADIUS := 6.0
const RETREAT_UNSEEN_TIME := 2.0
const RETREAT_MIN_DISTANCE := 15.0
const RETREAT_GIVE_UP := 25.0           ## then any out-of-view spot will do
const SIGHTING_DISTANCE := Vector2(12.0, 22.0)
const SIGHTING_DISTANCE_RELAXED := Vector2(6.0, 28.0)  ## after a few failed attempts (small rooms)
const SIGHTING_HOLD_TIME := 3.0         ## seconds in view before it walks off
const SIGHTING_MAX_HOLD := 8.0
const SIGHTING_CLOSE_DISTANCE := 8.0
const SIGHTING_TRUE_FORM_CHANCE := 0.6
const SIGHTING_GAP := 3.0               ## out of view this long -> the next view is a new sighting
const SIGHTING_RETRY_DELAY := 8.0
const MIMIC_START_HOUR := 1
const MIMIC_INTERVAL := Vector2(90.0, 150.0)
const MIMIC_RETRY := 5.0
const ABDUCT_INTERVAL := Vector2(120.0, 200.0)
const ABDUCT_RETRY := 5.0
const ABDUCT_MIN_PLAYER_DISTANCE := 15.0
const MISSING_IDENTITY_CHANCE := 0.75   ## prefers wearing a missing coworker's face
const INTERCOM_MEMORY := 60.0           ## acts on an announcement heard this recently
const WORK_PAUSE := Vector2(4.0, 10.0)  ## roam: pretends to work this long at each stop
const TWITCH_INTERVAL := Vector2(1.5, 4.5)
const WHEEZE_INTERVAL := 3.0
const LIGHT_PULSE_INTERVAL := 0.25
const TASK_SPOT_AVOID := 3.0            ## it "works" at least this far from real tasks
const TURN_SPEED := 8.0
const ARRIVE_DISTANCE := 0.6
const GRAVITY := 9.8
const HEIGHT_TRUE := 2.6
const HEIGHT_DISGUISED := 1.8
const STEP_WALK := 1.2
const STEP_RUN := 1.9

# --- States (emitted with Events.monster_state_changed) ------------------------
const DISGUISED_ROAM := &"disguised_roam"
const INVESTIGATE := &"investigate"
const LURE := &"lure"
const REVEAL := &"reveal"
const CHASE := &"chase"
const WINDED := &"winded"
const SEARCH := &"search"
const ATTACK := &"attack"
const RETREAT := &"retreat"
const SIGHTING := &"sighting"
const CALM_STATES: Array[StringName] = [DISGUISED_ROAM, INVESTIGATE, LURE]
const RULE2_STATES: Array[StringName] = [DISGUISED_ROAM, INVESTIGATE, LURE, SIGHTING]
const HUNTING_STATES: Array[StringName] = [REVEAL, CHASE, WINDED, SEARCH, ATTACK]

var state: StringName = DISGUISED_ROAM
var state_time := 0.0
var rules := MonsterRules.new()
var rng := RandomNumberGenerator.new()
var disguise_name := ""                 ## whose face and voice it is wearing
var missing_names: Array[String] = []   ## coworkers it has taken
var investigate_target := Vector3.ZERO
var witnessed_spot: Node3D              ## hiding spot it watched the player enter

# Perception, refreshed every tick by _sense().
var _player: Player
var _camera: Camera3D
var _player_distance := INF
var _player_hidden := false
var _has_los := false                   ## line of sight to the player's eyes (hidden or not)
var _sees_player := false               ## line of sight and not hidden
var _in_view := false                   ## the player can see the monster
var _out_of_view_time := 0.0
var _last_known := Vector3.ZERO
var _unseen_time := 0.0
var _nav_ok := false

# Movement.
var _moving := false
var _target := Vector3.ZERO
var _speed := 0.0
var _face_point: Variant = null         ## Vector3 to face, overrides facing the movement
var _staring := false
var _yaw := 0.0
var _stuck_time := 0.0
var _stuck_check_pos := Vector3.ZERO

# Per-state scratch (reset on every state change).
var _phase := 0
var _timer := 0.0
var _timer2 := 0.0
var _attack_hit := false
var _sighting_failures := 0
var _pending_intercom: StringName = &""
var _pending_intercom_age := 0.0
var _chase_active := false

# Presence: forms, animation, tells.
var _true_form_active := false
var _true_model: Node3D
var _disguise_model: Node3D
var _anim: AnimationPlayer
var _anim_override: StringName = &""    ## looping anim while standing (work)
var _anim_locked := false               ## a one-shot (reveal/attack) is playing
var _head_twitch: HeadTwitch
var _twitch_tween: Tween
var _twitch_left := 0.0
var _burst_left := 0.0
var _burst_cooldown := 0.0
var _light_pulse_left := 0.0
var _step_distance := 0.0

@onready var _true_form: Node3D = $TrueForm
@onready var _disguise_form: Node3D = $DisguiseForm
@onready var _agent: NavigationAgent3D = $NavigationAgent3D
@onready var _breath: AudioStreamPlayer3D = $Breath


func _ready() -> void:
	add_to_group(&"monster")
	collision_layer = Catalog.LAYER_MONSTER
	collision_mask = Catalog.LAYER_WORLD
	GameState.monster = self
	rng.randomize()
	rules.rng = rng
	_true_model = CharacterModel.instantiate(Catalog.MODEL_MONSTER, CharacterModel.Placeholder.MONSTER)
	_true_form.add_child(_true_model)
	_breath.stream = Sfx.get_stream(&"monster_breath")
	_set_disguise(_pick_identity())
	_set_form(false)
	_yaw = rotation.y
	_target = global_position
	_burst_cooldown = _roll(BURST_INTERVAL)
	_twitch_left = _roll(TWITCH_INTERVAL)
	Events.intercom_announced.connect(_on_intercom_announced)
	Events.player_hid.connect(_on_player_hid)
	Events.coworker_missing.connect(_on_coworker_missing)
	_set_state(DISGUISED_ROAM)


func _exit_tree() -> void:
	if GameState.monster == self:
		GameState.monster = null


func _physics_process(delta: float) -> void:
	tick(delta)


## One AI step. Tests may turn physics processing off and call this directly.
func tick(delta: float) -> void:
	state_time += delta
	_sense(delta)
	_tick_rules(delta)
	_tick_state(delta)
	_move(delta)
	_tick_presence(delta)


# --- Public API -----------------------------------------------------------------

func is_true_form() -> bool:
	return _true_form_active


func is_hunting() -> bool:
	return state in HUNTING_STATES


func is_in_player_view() -> bool:
	return _in_view


## Jumps to a state (tests and the sandbox). Hunting states put on the true form.
func force_state(new_state: StringName) -> void:
	_set_state(new_state)


## Walks (disguised) to `point` and lingers there 10-20 s.
func investigate(point: Vector3) -> void:
	investigate_target = _snap_to_nav(point)
	if state != INVESTIGATE:
		_set_state(INVESTIGATE)
		return
	_phase = 0
	_face_point = null
	_anim_override = &""
	_go_to(investigate_target, DISGUISED_SPEED)


## GDD seam 1: heads to a point in the announced zone to wait for whoever answers.
func investigate_zone(zone_id: StringName) -> bool:
	var zone := StoreZone.find_zone(get_tree(), zone_id)
	if zone == null:
		return false
	investigate(AiNav.random_point_in_zone(zone, rng))
	return true


## Mimicry: from out of view, appears far from the player wearing a coworker's
## face (preferring a missing one) and calls for help on the walkie.
func try_mimic_lure() -> bool:
	if not state in CALM_STATES or _in_view or _player == null:
		return false
	var spot: Variant = _find_lure_spot()
	if spot == null:
		return false
	_set_disguise(_pick_identity())
	_teleport(spot)
	var zone_id := StoreZone.find_zone_id_at(get_tree(), global_position)
	var line := MonsterLines.lure_line(disguise_name, zone_id, rng)
	Events.walkie_message.emit(disguise_name, line, global_position, true)
	_set_state(LURE)
	return true


## Takes a coworker the player cannot see who is far from the player. Only an
## unseen, roaming monster does it: it then stands in their place wearing their face.
func try_abduction() -> bool:
	if rules.abductions >= MAX_ABDUCTIONS or state != DISGUISED_ROAM or _in_view:
		return false
	var victims: Array[Coworker] = []
	for node in get_tree().get_nodes_in_group(&"coworker"):
		var coworker := node as Coworker
		if coworker != null and not coworker.is_queued_for_deletion() and _can_abduct_unseen(coworker):
			victims.append(coworker)
	if victims.is_empty():
		return false
	var victim: Coworker = victims[rng.randi() % victims.size()]
	var victim_name := victim.employee_name
	var spot := victim.global_position
	victim.abduct()
	rules.abduction_done()
	Sfx.play_at(&"abduct_distant", spot + Vector3.UP, 0.0, 1.0, 60.0)
	_note_missing(victim_name)
	Events.coworker_missing.emit(victim_name)
	GameState.add_stat("coworkers_lost")
	_set_disguise(_identity_for(victim_name))
	_teleport(_snap_to_nav(spot))
	_set_state(DISGUISED_ROAM)
	return true


## Rule 3: from out of view, appears 12-22 m ahead of the player inside their view.
func try_stage_sighting() -> bool:
	if not state in CALM_STATES or _in_view or _player == null or _camera == null:
		return false
	rules.note_sighting_attempt()
	var spot: Variant = _find_sighting_spot()
	if spot == null:
		_sighting_failures += 1
		return false
	_set_form(rng.randf() < SIGHTING_TRUE_FORM_CHANCE)
	_teleport(spot)
	_face_now(_player.global_position)
	_set_state(SIGHTING)
	return true


## Multi-line summary for the sandbox overlay.
func get_debug_text() -> String:
	return "MONSTER %s (%s)%s\nreveal %.1f/%.0f s  cooldown %.0f\nsprint %.1f/%.0f s  winded %.1f\nsighted %s (%d)  abductions %d  mimic in %.0f s" % [
		String(state).to_upper(), "TRUE FORM" if _true_form_active else "as " + disguise_name,
		"  [in view]" if _in_view else "",
		rules.reveal_progress, REVEAL_TIME, rules.reveal_cooldown_left,
		rules.sprint_time, SPRINT_MAX_TIME, rules.winded_left,
		rules.has_been_sighted, rules.sightings, rules.abductions, maxf(rules.next_mimic_in, 0.0),
	]


# --- Perception -------------------------------------------------------------------

func _sense(delta: float) -> void:
	_nav_ok = AiNav.is_ready(_agent.get_navigation_map(), global_position)
	_player = GameState.player as Player if is_instance_valid(GameState.player) else null
	if _player != null and not _player.is_inside_tree():
		_player = null
	if _player == null:
		_camera = null
		_player_distance = INF
		_has_los = false
		_sees_player = false
		_in_view = false
		_out_of_view_time += delta
		return
	if _camera == null or not is_instance_valid(_camera) or not _camera.is_inside_tree():
		_camera = Perception.find_player_camera(_player)
	var my_eye := global_position + Vector3.UP * (_height() * 0.9)
	var player_eye := _player.get_eye_position()
	_player_distance = _flat_distance(global_position, _player.global_position)
	_player_hidden = _player.is_hidden
	_has_los = my_eye.distance_to(player_eye) <= SIGHT_RANGE \
		and Perception.has_line_of_sight(get_world_3d().direct_space_state, my_eye, player_eye)
	_sees_player = _has_los and not _player_hidden
	if _sees_player:
		_last_known = _player.global_position
	_in_view = _is_visible_at(global_position, _height())
	_out_of_view_time = 0.0 if _in_view else _out_of_view_time + delta


func _is_visible_at(base: Vector3, height: float) -> bool:
	if _camera == null:
		return false
	return Perception.is_any_point_visible(_camera, Perception.body_points(base, height), SIGHT_RANGE)


func _hears_player() -> bool:
	return _player != null and not _player_hidden and _player_distance <= HEARING_RADIUS \
		and _player.get_noise_level() >= 1.0


func _can_abduct_unseen(coworker: Coworker) -> bool:
	if _player == null:
		return true
	if _flat_distance(coworker.global_position, _player.global_position) <= ABDUCT_MIN_PLAYER_DISTANCE:
		return false
	return not _is_visible_at(coworker.global_position, HEIGHT_DISGUISED)


# --- Rules --------------------------------------------------------------------------

func _tick_rules(delta: float) -> void:
	# Rule 3 bookkeeping: count every new time the player lays eyes on it.
	if rules.update_view(_in_view, delta):
		Events.monster_sighted.emit()
		GameState.add_stat("monster_sightings")
	var hour := GameState.get_hour()
	rules.tick_schedules(delta, hour)
	_pending_intercom_age += delta
	# Rule 2: a player lingering near the disguise makes it turn.
	var lingering := state in RULE2_STATES \
		and MonsterRules.is_reveal_condition(_player_distance, _has_los, _player_hidden)
	if rules.tick_reveal(delta, lingering):
		_set_state(REVEAL)
		return
	if not state in CALM_STATES:
		return
	if _hears_player():
		investigate(_player.global_position)
	# Rule 3: make sure the player has seen it at least once by the deadline.
	if rules.should_stage_sighting(hour) and try_stage_sighting():
		return
	if state != DISGUISED_ROAM:
		return
	if rules.abduction_due() and not try_abduction():
		rules.delay_abduction(ABDUCT_RETRY)
	elif rules.mimic_due():
		if try_mimic_lure():
			rules.mimic_done()
		else:
			rules.delay_mimic(MIMIC_RETRY)


# --- State machine ------------------------------------------------------------------

func _set_state(new_state: StringName) -> void:
	state = new_state
	state_time = 0.0
	_phase = 0
	_timer = 0.0
	_timer2 = 0.0
	_face_point = null
	_staring = false
	_anim_override = &""
	_anim_locked = false
	match new_state:
		DISGUISED_ROAM: _enter_disguised_roam()
		INVESTIGATE: _enter_investigate()
		LURE: _enter_lure()
		REVEAL: _enter_reveal()
		CHASE: _enter_chase()
		WINDED: _enter_winded()
		SEARCH: _enter_search()
		ATTACK: _enter_attack()
		RETREAT: _enter_retreat()
		SIGHTING: _enter_sighting()
	Events.monster_state_changed.emit(new_state)


func _tick_state(delta: float) -> void:
	match state:
		DISGUISED_ROAM: _tick_disguised_roam(delta)
		INVESTIGATE: _tick_investigate(delta)
		LURE: _tick_lure(delta)
		REVEAL: _tick_reveal(delta)
		CHASE: _tick_chase(delta)
		WINDED: _tick_winded(delta)
		SEARCH: _tick_search(delta)
		ATTACK: _tick_attack(delta)
		RETREAT: _tick_retreat(delta)
		SIGHTING: _tick_sighting(delta)


# disguised_roam: walk between stops and pretend to work there (facing a shelf).
func _enter_disguised_roam() -> void:
	_go_to(_pick_roam_point(), DISGUISED_SPEED)


func _tick_disguised_roam(delta: float) -> void:
	if not _pending_intercom.is_empty():
		var zone := _pending_intercom
		_pending_intercom = &""
		if _pending_intercom_age <= INTERCOM_MEMORY and investigate_zone(zone):
			return
	if _stare_if_lingered():
		return
	if _phase == 0:
		if not _moving:
			_phase = 1
			_timer = _roll(WORK_PAUSE)
			_pretend_to_work()
		return
	_timer -= delta
	if _timer <= 0.0:
		_phase = 0
		_face_point = null
		_anim_override = &""
		_go_to(_pick_roam_point(), DISGUISED_SPEED)


# investigate: walk to a heard/announced spot, linger 10-20 s looking around.
func _enter_investigate() -> void:
	_go_to(investigate_target, DISGUISED_SPEED)


func _tick_investigate(delta: float) -> void:
	if _stare_if_lingered():
		return
	if _phase == 0:
		if not _moving:
			_phase = 1
			_timer = _roll(INVESTIGATE_LINGER)
		return
	_look_around(delta)
	_timer -= delta
	if _timer <= 0.0:
		_set_state(DISGUISED_ROAM)


# lure: stands where its fake walkie call said, facing away, waiting.
func _enter_lure() -> void:
	_stop()
	if _player != null:
		_face_now(global_position * 2.0 - _player.global_position)
	_anim_override = Catalog.ANIM_WORK if rng.randf() < 0.5 else &""
	_timer = LURE_TIME


func _tick_lure(delta: float) -> void:
	if _stare_if_lingered():
		return
	_timer -= delta
	if _timer <= 0.0:
		_set_state(DISGUISED_ROAM)


# reveal: transforms into the true form in front of the player.
func _enter_reveal() -> void:
	_stop()
	_set_form(true)
	if _player != null:
		_face_now(_player.global_position)
	_play_once(Catalog.ANIM_REVEAL)
	Sfx.play_at(&"monster_reveal", global_position + Vector3.UP * 2.0, 3.0, 1.0, 40.0)
	Sfx.play(&"chase_stinger")
	_timer = rng.randf_range(REVEAL_DURATION.x, REVEAL_DURATION.y)
	_start_chase_event()


func _tick_reveal(delta: float) -> void:
	if _player != null:
		_face_point = _player.global_position
	_timer -= delta
	if _timer <= 0.0:
		_set_state(CHASE)


# chase: true form, full speed; rule 1 sprint timer runs.
func _enter_chase() -> void:
	_ensure_hunting_form()
	_unseen_time = 0.0


func _tick_chase(delta: float) -> void:
	if rules.tick_sprint(delta, true):
		_set_state(WINDED)
		return
	if _sees_player:
		_unseen_time = 0.0
		if _player_distance <= ATTACK_RANGE:
			_set_state(ATTACK)
			return
		_go_to(_player.global_position, CHASE_SPEED)
		return
	if witnessed_spot != null:
		_set_state(SEARCH)
		return
	_unseen_time += delta
	_go_to(_last_known, CHASE_SPEED)
	if _unseen_time >= LOSE_TRACK_TIME:
		_set_state(SEARCH)


# winded (rule 1): slow, loud wheezing for WINDED_TIME, then chase again or search.
func _enter_winded() -> void:
	_ensure_hunting_form()
	rules.start_winded()
	_timer2 = 0.0


func _tick_winded(delta: float) -> void:
	_timer2 -= delta
	if _timer2 <= 0.0:
		_timer2 = WHEEZE_INTERVAL
		Sfx.play_at(&"monster_winded", global_position + Vector3.UP * 2.2, 4.0, 1.0, 40.0)
	_go_to(_last_known, WINDED_SPEED)
	if rules.tick_winded(delta):
		_set_state(CHASE if _sees_player else SEARCH)


# search: last known position, or straight to the hiding spot it saw the player enter.
func _enter_search() -> void:
	_ensure_hunting_form()
	_timer = SEARCH_TRAVEL_MAX
	if witnessed_spot != null and is_instance_valid(witnessed_spot):
		_go_to(_snap_to_nav(_spot_front(witnessed_spot)), SEARCH_SPEED)
	else:
		witnessed_spot = null
		_go_to(_last_known, SEARCH_SPEED)


func _tick_search(delta: float) -> void:
	rules.tick_sprint(delta, false)
	if _sees_player:
		_set_state(CHASE)
		return
	if witnessed_spot != null:
		if not is_instance_valid(witnessed_spot):
			witnessed_spot = null
		elif not _moving or _flat_distance(global_position, _spot_front(witnessed_spot)) <= 1.3:
			if _pull_player_out(witnessed_spot):
				return
			witnessed_spot = null   # they slipped out before it got there
			_phase = 1
			_timer = SEARCH_TIME
		return
	if _hears_player():
		_last_known = _player.global_position
		_go_to(_last_known, SEARCH_SPEED)
	_timer -= delta
	if _phase == 0:
		if not _moving or _timer <= 0.0:
			_phase = 1
			_timer = SEARCH_TIME
		return
	if _timer <= 0.0:
		_set_state(RETREAT)
		return
	if not _moving:
		_look_around(delta)
		_timer2 -= delta
		if _timer2 <= -1.5:
			_timer2 = 0.0
			var hop := _last_known + Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized() * SEARCH_HOP_RADIUS
			_go_to(_snap_to_nav(hop), SEARCH_SPEED)


# attack: lunging wind-up with a scream, damage if the player is still in range.
func _enter_attack() -> void:
	_ensure_hunting_form()
	_attack_hit = false
	_play_once(Catalog.ANIM_ATTACK)
	Sfx.play_at(&"monster_scream", global_position + Vector3.UP * 2.0, 3.0, 1.0, 40.0)


func _tick_attack(_delta: float) -> void:
	if _player != null:
		_face_point = _player.global_position
	if _phase == 0:
		if _player != null and _player_distance > 1.0:
			_go_to(_player.global_position, CHASE_SPEED)
		else:
			_stop()
		if state_time >= ATTACK_WINDUP:
			_phase = 1
			_stop()
			_resolve_attack()
		return
	if state_time >= ATTACK_WINDUP + ATTACK_RECOVER:
		_set_state(RETREAT if _attack_hit else CHASE)


func _resolve_attack() -> void:
	if _player == null or _player.is_hidden or _player.health <= 0.0:
		return
	var distance := _flat_distance(global_position, _player.global_position)
	if distance <= ATTACK_RANGE and _has_los:
		_player.take_damage(ATTACK_DAMAGE, global_position)
		Sfx.play_at(&"monster_attack_hit", _player.global_position + Vector3.UP, 0.0, 1.0, 20.0)
		_attack_hit = true


# retreat: breaks away; once unseen and far, vanishes and puts a face back on.
func _enter_retreat() -> void:
	_ensure_hunting_form()
	_go_to(_pick_far_point(), RETREAT_SPEED)


func _tick_retreat(delta: float) -> void:
	rules.tick_sprint(delta, false)
	var unseen := _out_of_view_time >= RETREAT_UNSEEN_TIME
	var far := _player == null or _player_distance > RETREAT_MIN_DISTANCE
	if unseen and (far or state_time >= RETREAT_GIVE_UP):
		_finish_retreat()
		return
	if not _moving:
		_go_to(_pick_far_point(), RETREAT_SPEED)


func _finish_retreat() -> void:
	var spot: Variant = _find_hidden_point()
	if spot != null:
		_teleport(spot)
	_set_disguise(_pick_identity())
	_set_form(false)
	rules.start_reveal_cooldown()
	rules.reset_sprint()
	witnessed_spot = null
	_end_chase_event()
	_set_state(DISGUISED_ROAM)


# sighting (rule 3): holds in the player's view, then walks out of it.
func _enter_sighting() -> void:
	_stop()
	_timer = 0.0


func _tick_sighting(delta: float) -> void:
	if _phase == 0:
		if _player != null:
			_face_point = _player.global_position
		if _in_view:
			_timer += delta
		var close := _player != null and _player_distance <= SIGHTING_CLOSE_DISTANCE
		if _timer >= SIGHTING_HOLD_TIME or close or state_time >= SIGHTING_MAX_HOLD:
			_phase = 1
			_face_point = null
			_sighting_failures = 0
			_leave_view()
		return
	if _out_of_view_time >= 1.0:
		if _true_form_active:
			_set_form(false)
		_set_state(DISGUISED_ROAM)
	elif not _moving:
		_leave_view()


func _leave_view() -> void:
	var spot: Variant = _find_escape_point()
	_go_to(spot if spot != null else _pick_far_point(), DISGUISED_SPEED)


# --- State helpers ----------------------------------------------------------------

## Rule 2 tell: a coworker who stops what it is doing and just watches you.
func _stare_if_lingered() -> bool:
	_staring = rules.reveal_progress >= STARE_AFTER \
		and MonsterRules.is_reveal_condition(_player_distance, _has_los, _player_hidden)
	return _staring


func _pretend_to_work() -> void:
	var wall: Variant = _nearest_wall_point()
	_face_point = wall if wall != null else global_position + _random_flat_dir()
	_anim_override = Catalog.ANIM_WORK if rng.randf() < 0.6 else &""


func _look_around(delta: float) -> void:
	_timer2 -= delta
	if _timer2 <= 0.0:
		_timer2 = rng.randf_range(1.5, 3.0)
		_face_point = global_position + _random_flat_dir()


func _pull_player_out(spot: Node3D) -> bool:
	if _player == null or not _player.is_hidden or _player.current_hiding_spot != spot:
		return false
	_face_now(spot.global_position)
	if spot.has_method(&"pull_out_occupant"):
		spot.pull_out_occupant()
	if _player.is_hidden and _player.current_hiding_spot == spot:
		_player.exit_hiding()   # a hiding spot that cannot eject (stub) still loses its occupant
	witnessed_spot = null
	_set_state(ATTACK)
	return true


func _ensure_hunting_form() -> void:
	if not _true_form_active:
		_set_form(true)
	_start_chase_event()


func _start_chase_event() -> void:
	if not _chase_active:
		_chase_active = true
		Events.chase_started.emit()


func _end_chase_event() -> void:
	if _chase_active:
		_chase_active = false
		Events.chase_ended.emit()


# --- Places ---------------------------------------------------------------------

func _pick_roam_point() -> Vector3:
	var patrol := get_tree().get_nodes_in_group(&"patrol_point")
	var zones := get_tree().get_nodes_in_group(&"store_zone")
	for attempt in 8:
		var point := global_position + _random_flat_dir() * rng.randf_range(4.0, 10.0)
		var roll := rng.randf()
		if _player != null and roll < 0.35:
			# It hunts: drift toward wherever the player is working.
			var zone := StoreZone.find_zone(get_tree(), StoreZone.find_zone_id_at(get_tree(), _player.global_position))
			point = AiNav.random_point_in_zone(zone, rng) if zone != null \
				else _player.global_position + _random_flat_dir() * rng.randf_range(5.0, 10.0)
		elif not patrol.is_empty() and roll < 0.7:
			point = (patrol[rng.randi() % patrol.size()] as Node3D).global_position
		elif not zones.is_empty():
			point = AiNav.random_point_in_zone(zones[rng.randi() % zones.size()], rng)
		point = _snap_to_nav(point)
		if _flat_distance(point, global_position) >= 2.0 and not _near_task_station(point):
			return point
	return _snap_to_nav(global_position + _random_flat_dir() * 4.0)


## Retreat: a place far from the player, reached by heading away from them.
func _pick_far_point() -> Vector3:
	var from := _player.global_position if _player != null else global_position
	var points := _away_points()
	if points.is_empty():
		return _snap_to_nav(global_position + (global_position - from).normalized() * 10.0)
	points.sort_custom(func(a: Vector3, b: Vector3) -> bool: return _flat_distance(a, from) > _flat_distance(b, from))
	return _snap_to_nav(points[rng.randi() % mini(3, points.size())])


## Leaving a sighting: the nearest place the player cannot see, away from them. null if none.
func _find_escape_point() -> Variant:
	var points := _away_points()
	points.sort_custom(func(a: Vector3, b: Vector3) -> bool: return _flat_distance(a, global_position) < _flat_distance(b, global_position))
	for point in points:
		var snapped := _snap_to_nav(point)
		if _flat_distance(snapped, global_position) > 1.0 and not _is_visible_at(snapped, _height()):
			return snapped
	return null


## A place the player cannot see, preferring far from them (teleport target). null if none.
func _find_hidden_point() -> Variant:
	var from := _player.global_position if _player != null else global_position
	var points := _candidate_points()
	points.sort_custom(func(a: Vector3, b: Vector3) -> bool: return _flat_distance(a, from) > _flat_distance(b, from))
	for point in points:
		var snapped := _snap_to_nav(point)
		if not _is_visible_at(snapped, HEIGHT_TRUE):
			return snapped
	return null


## Candidate places that lead away from the player: farther from them than the
## monster is now and not in their direction (more than 60 degrees off it).
func _away_points() -> Array[Vector3]:
	var points := _candidate_points()
	if _player == null:
		return points
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var my_distance := to_player.length()
	var away: Array[Vector3] = []
	for point in points:
		if _flat_distance(point, _player.global_position) <= my_distance:
			continue
		var to_point := point - global_position
		to_point.y = 0.0
		if my_distance > 0.1 and to_point.length() > 0.1 and to_point.normalized().dot(to_player / my_distance) > 0.5:
			continue
		away.append(point)
	return away if not away.is_empty() else points


func _find_lure_spot() -> Variant:
	var from := _player.global_position
	var points: Array[Vector3] = []
	for point in _candidate_points():
		if _flat_distance(point, from) >= LURE_MIN_DISTANCE:
			points.append(point)
	for zone: StoreZone in get_tree().get_nodes_in_group(&"store_zone"):
		var point := AiNav.random_point_in_zone(zone, rng)
		if _flat_distance(point, from) >= LURE_MIN_DISTANCE:
			points.append(point)
	for i in range(points.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var swap := points[i]
		points[i] = points[j]
		points[j] = swap
	for point in points:
		var snapped := _snap_to_nav(point)
		if not _is_visible_at(snapped, HEIGHT_DISGUISED):
			return snapped
	return null


func _find_sighting_spot() -> Variant:
	var span := SIGHTING_DISTANCE if _sighting_failures < 3 else SIGHTING_DISTANCE_RELAXED
	var forward := -_camera.global_basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		return null
	forward = forward.normalized()
	var half_angle := deg_to_rad(_camera.fov) * 0.5 * 0.75
	var base := _player.global_position
	for attempt in 24:
		var direction := forward.rotated(Vector3.UP, rng.randf_range(-half_angle, half_angle))
		var point := _snap_to_nav(base + direction * rng.randf_range(span.x, span.y))
		var distance := _flat_distance(point, base)
		if distance < span.x - 0.5 or distance > span.y + 0.5:
			continue
		if Perception.is_point_visible_to_camera(_camera, point + Vector3.UP * 1.2, SIGHT_RANGE):
			return point
	return null


## Patrol points plus the centre of every zone.
func _candidate_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for marker in get_tree().get_nodes_in_group(&"patrol_point"):
		points.append((marker as Node3D).global_position)
	for zone: StoreZone in get_tree().get_nodes_in_group(&"store_zone"):
		var center := zone.get_bounds().get_center()
		points.append(Vector3(center.x, 0.0, center.z))
	return points


func _near_task_station(point: Vector3) -> bool:
	for station in get_tree().get_nodes_in_group(&"task_station"):
		var spot: Vector3 = station.get_work_position() if station.has_method(&"get_work_position") \
			else (station as Node3D).global_position
		if _flat_distance(spot, point) < TASK_SPOT_AVOID:
			return true
	return false


func _nearest_wall_point() -> Variant:
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3.UP * 1.2
	var best: Variant = null
	var best_distance := INF
	for i in 8:
		var direction := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 8.0)
		var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 2.5, Catalog.LAYER_WORLD)
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			var distance := origin.distance_to(hit.position)
			if distance < best_distance:
				best_distance = distance
				best = hit.position
	return best


func _spot_front(spot: Node3D) -> Vector3:
	if spot.has_method(&"get_exit_position"):
		return spot.get_exit_position()
	return spot.global_position


# --- Identity and forms ------------------------------------------------------------

func _pick_identity() -> Dictionary:
	var missing := Catalog.COWORKERS.filter(func(entry: Dictionary) -> bool: return entry["name"] in missing_names)
	if not missing.is_empty() and rng.randf() < MISSING_IDENTITY_CHANCE:
		return missing[rng.randi() % missing.size()]
	return Catalog.COWORKERS[rng.randi() % Catalog.COWORKERS.size()]


func _identity_for(employee_name: String) -> Dictionary:
	for entry: Dictionary in Catalog.COWORKERS:
		if entry["name"] == employee_name:
			return entry
	return {"name": employee_name, "model": ""}


func _note_missing(employee_name: String) -> void:
	if not employee_name in missing_names:
		missing_names.append(employee_name)


func _set_disguise(identity: Dictionary) -> void:
	disguise_name = identity["name"]
	if _twitch_tween != null:
		_twitch_tween.kill()
	if _disguise_model != null:
		_disguise_form.remove_child(_disguise_model)
		_disguise_model.queue_free()
	_disguise_model = CharacterModel.instantiate(identity["model"], CharacterModel.Placeholder.EMPLOYEE, disguise_name)
	_disguise_form.add_child(_disguise_model)
	_head_twitch = null
	var skeleton := CharacterModel.find_skeleton(_disguise_model)
	if skeleton != null and skeleton.find_bone(HeadTwitch.BONE_NAME) >= 0:
		_head_twitch = HeadTwitch.new()
		skeleton.add_child(_head_twitch)
	if not _true_form_active:
		_anim = CharacterModel.find_animation_player(_disguise_model)


func _set_form(true_form: bool) -> void:
	_true_form_active = true_form
	_true_form.visible = true_form
	_disguise_form.visible = not true_form
	_anim = CharacterModel.find_animation_player(_true_model if true_form else _disguise_model)
	_step_distance = 0.0
	if true_form and _breath.stream != null:
		_breath.play()
	elif not true_form:
		_breath.stop()


func _height() -> float:
	return HEIGHT_TRUE if _true_form_active else HEIGHT_DISGUISED


# --- Movement --------------------------------------------------------------------

func _go_to(point: Vector3, speed: float) -> void:
	_speed = speed
	_moving = true
	if point.distance_to(_target) > 0.4 or _agent.target_position.distance_to(point) > 0.4:
		_target = point
		_agent.target_position = point


func _stop() -> void:
	_moving = false


func _teleport(point: Vector3) -> void:
	global_position = point
	velocity = Vector3.ZERO
	_moving = false
	_target = point
	_agent.target_position = point
	_step_distance = 0.0
	reset_physics_interpolation()


func _move(delta: float) -> void:
	var horizontal := Vector3.ZERO
	if _moving and not _staring:
		if _flat_distance(global_position, _target) <= ARRIVE_DISTANCE:
			_moving = false
		else:
			var next := _agent.get_next_path_position() if _nav_ok else _target
			var to_next := next - global_position
			to_next.y = 0.0
			if to_next.length() > 0.05:
				horizontal = to_next.normalized() * _current_speed()
			elif not _nav_ok or _agent.is_navigation_finished():
				_moving = false
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()
	_check_stuck(delta, horizontal)
	_update_facing(delta, horizontal)


func _current_speed() -> float:
	if _burst_left > 0.0 and not _true_form_active:
		return BURST_SPEED
	return _speed


## Gives up on a target it cannot make progress toward (states treat it as arrived).
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


func _update_facing(delta: float, horizontal: Vector3) -> void:
	var look := Vector3.ZERO
	if _staring and _player != null:
		look = _player.global_position - global_position
	elif _face_point != null:
		look = (_face_point as Vector3) - global_position
	elif horizontal.length() > 0.1:
		look = horizontal
	look.y = 0.0
	if look.length() < 0.01:
		return
	_yaw = lerp_angle(_yaw, atan2(look.x, look.z), clampf(TURN_SPEED * delta, 0.0, 1.0))
	look_at(global_position + Vector3(sin(_yaw), 0.0, cos(_yaw)), Vector3.UP, true)


func _face_now(point: Vector3) -> void:
	var look := point - global_position
	look.y = 0.0
	if look.length() < 0.01:
		return
	_yaw = atan2(look.x, look.z)
	look_at(global_position + look, Vector3.UP, true)


func _snap_to_nav(point: Vector3) -> Vector3:
	return AiNav.snap(_agent.get_navigation_map(), _nav_ok, point, global_position.y)


# --- Presence: lights, sounds, animation, tells -------------------------------------

func _tick_presence(delta: float) -> void:
	_pulse_lights(delta)
	_update_animation()
	if _true_form_active:
		_footsteps(delta)
	else:
		_disguise_tells(delta)


## Store lights within FLICKER_RADIUS flicker, stronger when closer.
func _pulse_lights(delta: float) -> void:
	_light_pulse_left -= delta
	if _light_pulse_left > 0.0:
		return
	_light_pulse_left = LIGHT_PULSE_INTERVAL
	for node in get_tree().get_nodes_in_group(&"store_light"):
		var light := node as Node3D
		if light == null or not light.has_method(&"set_disturbance"):
			continue
		var distance := light.global_position.distance_to(global_position)
		if distance <= FLICKER_RADIUS:
			light.set_disturbance(clampf(1.0 - distance / FLICKER_RADIUS, 0.05, 1.0))


func _footsteps(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed < 0.3:
		return
	_step_distance += speed * delta
	var stride := STEP_RUN if speed > 3.0 else STEP_WALK
	if _step_distance >= stride:
		_step_distance = 0.0
		Sfx.play_at(&"monster_footstep", global_position, 0.0, rng.randf_range(0.9, 1.1), 35.0)


## No footsteps (coworkers have them), head twitches, short too-fast bursts.
func _disguise_tells(delta: float) -> void:
	_twitch_left -= delta
	if _twitch_left <= 0.0:
		_twitch_left = _roll(TWITCH_INTERVAL)
		_twitch_head()
	if _burst_left > 0.0:
		_burst_left -= delta
		return
	_burst_cooldown -= delta
	if _burst_cooldown <= 0.0:
		_burst_cooldown = _roll(BURST_INTERVAL)
		if _moving and state in CALM_STATES:
			_burst_left = BURST_TIME


func _twitch_head() -> void:
	var degrees := rng.randf_range(25.0, 50.0)
	var hold := rng.randf_range(0.12, 0.35)
	if _head_twitch != null and is_instance_valid(_head_twitch) and _head_twitch.has_head_bone():
		_head_twitch.twitch(degrees, hold, rng)
		return
	if _disguise_model == null:
		return
	var head := _disguise_model.find_child("Head", true, false) as Node3D
	if head == null:
		return
	if _twitch_tween != null:
		_twitch_tween.kill()
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	head.rotation = Vector3(rng.randf_range(-0.3, 0.3), deg_to_rad(degrees) * side, rng.randf_range(-0.5, 0.5))
	_twitch_tween = create_tween()
	_twitch_tween.tween_interval(hold)
	_twitch_tween.tween_property(head, "rotation", Vector3.ZERO, 0.25)


func _play_once(anim_name: StringName) -> void:
	_anim_locked = true
	if _anim != null and _anim.has_animation(anim_name):
		_anim.play(anim_name, 0.1)
		_anim.speed_scale = 1.0


func _update_animation() -> void:
	if _anim == null or _anim_locked:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed > 3.2:
		CharacterModel.play(_anim, Catalog.ANIM_RUN, clampf(speed / CHASE_SPEED, 0.6, 1.6))
	elif speed > 0.15:
		CharacterModel.play(_anim, Catalog.ANIM_WALK, clampf(speed / DISGUISED_SPEED, 0.5, 2.0))
	elif _anim_override != &"" and not _staring:
		CharacterModel.play(_anim, _anim_override)
	else:
		CharacterModel.play(_anim, Catalog.ANIM_IDLE)


# --- Signals -------------------------------------------------------------------------

## GDD seam 1: everyone hears the intercom, including the monster.
func _on_intercom_announced(_message: String, zone: StringName) -> void:
	if not is_inside_tree():
		return
	if state in CALM_STATES:
		investigate_zone(zone)
	elif state == SIGHTING or state == RETREAT:
		_pending_intercom = zone
		_pending_intercom_age = 0.0


## It only knows where the player hid if it was watching at that moment.
func _on_player_hid(spot: Node3D) -> void:
	witnessed_spot = spot if _has_los and state in HUNTING_STATES else null


func _on_coworker_missing(coworker_name: String) -> void:
	_note_missing(coworker_name)


# --- Small helpers ---------------------------------------------------------------------

func _roll(span: Vector2) -> float:
	return rng.randf_range(span.x, span.y)


func _random_flat_dir() -> Vector3:
	return Vector3.FORWARD.rotated(Vector3.UP, rng.randf() * TAU)


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
