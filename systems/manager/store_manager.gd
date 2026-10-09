class_name StoreManager
extends Node3D
## The store manager: spawns the manager NPC, greets the night crew over the
## intercom, and periodically assigns bonus tasks by intercom or walkie.
##
## Real time drives this through `_process` -> `tick(delta)`, but `tick()` is
## public so tests can fast-forward without waiting on real seconds, and
## `issue_bonus_task()` can be called directly to test task assignment itself.

## PA voice plays from this many intercom speakers nearest the player (more = phasing echo).
const PA_SPEAKER_COUNT := 2
const PA_VOICE_DB := 2.0

@export var welcome_delay := 6.0
@export var min_first_bonus_delay := 50.0
@export var max_first_bonus_delay := 70.0
@export var min_bonus_interval := 70.0
@export var max_bonus_interval := 110.0
@export var max_open_manager_tasks := 2
@export var manager_task_time_limit := 120.0
@export var pa_flavour_min_interval := 90.0
@export var pa_flavour_max_interval := 150.0

var npc: Node3D

var _elapsed := 0.0
var _welcome_sent := false
var _next_bonus_at := 0.0
var _next_pa_flavour_at := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group(&"store_manager")
	_spawn_npc()
	Events.night_started.connect(_on_night_started)
	Events.hour_changed.connect(_on_hour_changed)
	Events.coworker_missing.connect(_on_coworker_missing)
	Events.task_completed.connect(_on_task_completed)
	Events.task_failed.connect(_on_task_failed)


func _process(delta: float) -> void:
	if GameState.night_running:
		tick(delta)


## Advances the manager's internal clock by `delta` seconds. Exposed so tests
## can drive welcome/bonus-task timing without waiting on real time.
func tick(delta: float) -> void:
	_elapsed += delta
	_maybe_send_welcome()
	_maybe_send_pa_flavour()
	_maybe_issue_bonus_task()


## Picks an inactive station and assigns it as a manager task, 50/50 over the
## intercom or the walkie. Returns false when there is nothing to assign.
func issue_bonus_task() -> bool:
	var station := _pick_inactive_station()
	if station == null:
		return false
	var task := Tasks.add_manager_task(station, manager_task_time_limit)
	if task == null:
		return false
	var line: String = station.manager_line if not station.manager_line.is_empty() else ("Attention: " + station.title)
	if _rng.randf() < 0.5:
		_announce(line, station.zone)
	else:
		_walkie(line)
	return true


func _on_night_started() -> void:
	_elapsed = 0.0
	_welcome_sent = false
	_next_bonus_at = _rng.randf_range(min_first_bonus_delay, max_first_bonus_delay)
	_next_pa_flavour_at = _elapsed + _rng.randf_range(pa_flavour_min_interval, pa_flavour_max_interval)


## Seeds the manager's coin flips and picks (intercom or walkie, which station, when), so a
## test or a replay gets the same night of announcements.
func set_seed(value: int) -> void:
	_rng.seed = value


## Hourly PA line from 1 AM to 5 AM. 6:00 AM has none: the night ends then and the end screen
## would cut it off; the shift-end bell (scenes/game.gd) marks it instead.
func _on_hour_changed(hour: int) -> void:
	if hour > 0 and hour < GameState.END_HOUR:
		_announce(ManagerLines.random_hourly(GameState.get_clock_text()))


func _on_coworker_missing(coworker_name: String) -> void:
	_walkie(ManagerLines.random_missing(coworker_name))


func _on_task_completed(task: TaskData, _by: Node) -> void:
	if task.is_manager_task:
		_walkie(ManagerLines.TASK_COMPLETED.pick_random())


func _on_task_failed(task: TaskData) -> void:
	if task.is_manager_task:
		_walkie(ManagerLines.TASK_FAILED.pick_random())


func _maybe_send_welcome() -> void:
	if not _welcome_sent and _elapsed >= welcome_delay:
		_welcome_sent = true
		_announce(ManagerLines.WELCOME.pick_random())


func _maybe_send_pa_flavour() -> void:
	if _elapsed < _next_pa_flavour_at:
		return
	_next_pa_flavour_at = _elapsed + _rng.randf_range(pa_flavour_min_interval, pa_flavour_max_interval)
	_announce(ManagerLines.PA_FLAVOUR.pick_random())


func _maybe_issue_bonus_task() -> void:
	if _elapsed < _next_bonus_at:
		return
	if _open_manager_task_count() >= max_open_manager_tasks:
		_next_bonus_at = _elapsed + 5.0   ## at the cap; check back soon rather than spamming
		return
	if issue_bonus_task():
		_next_bonus_at = _elapsed + _rng.randf_range(min_bonus_interval, max_bonus_interval)
	else:
		_next_bonus_at = _elapsed + 5.0  ## nothing free right now; retry soon


func _open_manager_task_count() -> int:
	var count := 0
	for task in Tasks.get_open_tasks():
		if task.is_manager_task:
			count += 1
	return count


func _pick_inactive_station() -> TaskStation:
	var candidates: Array[TaskStation] = []
	for node in get_tree().get_nodes_in_group(&"task_station"):
		var station := node as TaskStation
		if station and not station.is_active():
			candidates.append(station)
	if candidates.is_empty():
		return null
	return candidates[_rng.randi() % candidates.size()]


## Chime, then the manager's spoken PA clip (VoiceLines) at the intercom speakers nearest the
## player -- only a couple, so the same line does not echo/phase out of every ceiling speaker.
## A line with no generated clip falls back to the generic intercom babble.
func _announce(message: String, zone: StringName = &"") -> void:
	Events.intercom_announced.emit(message, zone)
	var speakers := _nearest_intercom_speakers(PA_SPEAKER_COUNT)
	for speaker in speakers:
		Sfx.play_at(&"intercom_chime", speaker.global_position)
	var clip := VoiceLines.get_stream("MANAGER", message, false, VoiceLines.INTERCOM)
	if clip == null:
		for speaker in speakers:
			Sfx.play_at(&"intercom_voice", speaker.global_position)
		return
	var chime := Sfx.get_stream(&"intercom_chime")
	var delay := chime.get_length() * 0.8 if chime else 0.0
	var positions: Array[Vector3] = []
	for speaker in speakers:
		positions.append(speaker.global_position)
	if delay > 0.0 and is_inside_tree():
		await get_tree().create_timer(delay, false).timeout
		if not is_inside_tree():
			return
	for at in positions:
		_play_pa_clip(clip, at)


func _nearest_intercom_speakers(count: int) -> Array[Node3D]:
	var speakers: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group(&"intercom_speaker"):
		if node is Node3D:
			speakers.append(node)
	var listener: Node3D = GameState.player if is_instance_valid(GameState.player) else null
	if listener == null or not listener.is_inside_tree() or speakers.size() <= count:
		return speakers.slice(0, count)
	var from := listener.global_position
	speakers.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_squared_to(from) < b.global_position.distance_squared_to(from))
	return speakers.slice(0, count)


func _play_pa_clip(clip: AudioStream, at: Vector3) -> void:
	var parent: Node = GameState.world_root if is_instance_valid(GameState.world_root) else self
	var player := AudioStreamPlayer3D.new()
	player.name = "PAVoice"
	player.stream = clip
	player.bus = &"Voice"
	player.volume_db = PA_VOICE_DB
	player.unit_size = 6.0
	player.max_distance = 40.0
	parent.add_child(player)
	player.global_position = at
	player.finished.connect(player.queue_free)
	player.play()


func _walkie(message: String) -> void:
	var origin := npc.global_position if npc else global_position
	Events.walkie_message.emit("MANAGER", message, origin, false)


func _spawn_npc() -> void:
	var scene := Catalog.load_scene_or_null("res://systems/manager/manager_npc.tscn")
	npc = scene.instantiate() if scene else _build_fallback_npc()
	add_child(npc)
	var spot := get_tree().get_first_node_in_group(&"manager_spot") as Node3D
	if spot:
		npc.global_transform = spot.global_transform


func _build_fallback_npc() -> Node3D:
	var body := Node3D.new()
	body.add_to_group(&"employee")
	return body
