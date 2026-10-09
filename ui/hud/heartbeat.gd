class_name Heartbeat
extends Node
## Player-side heartbeat loop (2D, SFX bus), owned by the HUD like the walkie radio. It fades in
## while the player's health is below LOW_HEALTH_FRACTION or the monster, in its true form and
## hunting, is within CHASE_DISTANCE, and fades out (then stops) otherwise. Reads
## GameState.player / GameState.monster through their contract APIs, so test doubles work.

const LOW_HEALTH_FRACTION := 0.35
const CHASE_DISTANCE := 8.0
const ON_DB := -3.0
const FADE_IN_TIME := 0.8               ## seconds from silent to full
const FADE_OUT_TIME := 2.5              ## seconds from full to silent
const SILENT_LEVEL := 0.001

var _loop: AudioStreamPlayer
var _level := 0.0                       ## 0 silent .. 1 full


func _ready() -> void:
	_loop = AudioStreamPlayer.new()
	_loop.name = "Loop"
	_loop.bus = &"SFX"
	_loop.stream = Sfx.get_stream(&"heartbeat")
	_loop.volume_db = linear_to_db(SILENT_LEVEL)
	add_child(_loop)
	Events.night_ended.connect(_on_night_ended)


func _process(delta: float) -> void:
	tick(delta)


func _notification(what: int) -> void:
	# Pausing the tree stops _process; hold the loop where it is instead of letting it play on.
	if _loop == null:
		return
	if what == NOTIFICATION_PAUSED:
		_loop.stream_paused = true
	elif what == NOTIFICATION_UNPAUSED:
		_loop.stream_paused = false


## The rule: low health, or the true form chasing within CHASE_DISTANCE.
static func wants_heartbeat(health_fraction: float, monster_distance: float, monster_chasing: bool) -> bool:
	return health_fraction < LOW_HEALTH_FRACTION or (monster_chasing and monster_distance <= CHASE_DISTANCE)


## Moves the fade one step toward on/off (called from _process; tests step it by hand).
func tick(delta: float) -> void:
	var target := 1.0 if _should_beat() else 0.0
	var fade_time := FADE_IN_TIME if target > _level else FADE_OUT_TIME
	_level = move_toward(_level, target, delta / fade_time)
	_apply()


func is_beating() -> bool:
	return _loop != null and _loop.playing


## 0 (silent) .. 1 (full volume).
func get_level() -> float:
	return _level


func _should_beat() -> bool:
	var player := GameState.player
	if not GameState.night_running or not is_instance_valid(player) or not player.is_inside_tree():
		return false
	if player.has_method(&"is_dead") and player.call(&"is_dead"):
		return false
	var health := float(player.get(&"health"))
	var max_health := maxf(float(player.get(&"max_health")), 1.0)
	if health <= 0.0:
		return false
	var monster := GameState.monster
	var chasing := false
	var distance := INF
	if is_instance_valid(monster) and monster.is_inside_tree() \
			and monster.has_method(&"is_true_form") and monster.has_method(&"is_hunting"):
		chasing = monster.call(&"is_true_form") and monster.call(&"is_hunting")
		distance = monster.global_position.distance_to(player.global_position)
	return wants_heartbeat(health / max_health, distance, chasing)


func _apply() -> void:
	if _loop == null or _loop.stream == null:
		return
	if _level <= 0.0:
		if _loop.playing:
			_loop.stop()
		return
	_loop.volume_db = ON_DB + linear_to_db(maxf(_level, SILENT_LEVEL))
	if not _loop.playing:
		_loop.play()


func _on_night_ended(_result: StringName) -> void:
	_level = 0.0
	_apply()
