extends TestCase
## Long smoke test: the real game scene (scenes/game.tscn -> the final store) runs a whole
## night headless at TIME_SCALE x speed with every system live (player, three coworkers, the
## monster, the store manager, Tasks, HUD). The runner fails it on any engine error logged.
##
## The player stands still (invulnerable, so the night cannot end early) facing a corner of the
## break room until 2:00 AM — nothing can be seen from there, so rule 3 must stage a sighting —
## then watches the store from a long sightline. Run alone with:
##   godot --headless --path . -s res://tests/run_tests.gd -- --filter=night_smoke

const GAME := "res://scenes/game.tscn"
const TIME_SCALE := 8.0
const REAL_TIME_BUDGET_MS := 240000
const MANAGER_SEED := 20261009
## Facing into the break room's south-west corner: every view ray hits a wall within 0.6 m.
const CORNER := Vector3(2.55, 0.0, -15.55)
const CORNER_YAW := 45.0
## Long open views for the 2 AM sighting: [position, yaw] (yaw 0 looks down -Z).
const VANTAGES := [
	[Vector3(-18.5, 0.0, 14.8), -90.0],   # front of the store, looking east along the registers
	[Vector3(-19.0, 0.0, -7.5), -90.0],   # west end of the back hallway, looking east
	[Vector3(18.8, 0.0, 14.8), 45.0],     # customer-service corner, looking north-west over produce
	[Vector3(-2.0, 0.0, 8.5), 0.0],       # aisle 4 toward the dairy wall
]

var _counts := {}
var _states: Array[StringName] = []
var _pending_manager_task := false
var _hour_two_done := false
var _hooks: Array = []


func _count(key: String) -> void:
	_counts[key] = _counts.get(key, 0) + 1


func _hook(sig: Signal, callable: Callable) -> void:
	sig.connect(callable)
	_hooks.append([sig, callable])


func _on_task_added(task: TaskData) -> void:
	if task.is_manager_task:
		_count("manager_tasks")
		_pending_manager_task = true


func _on_intercom(_message: String, zone: StringName) -> void:
	_count("intercom")
	if _pending_manager_task and zone != &"":
		_count("manager_tasks_by_intercom")
	_pending_manager_task = false


func _on_walkie(speaker: String, _message: String, _origin: Vector3, is_mimic: bool) -> void:
	_count("walkie")
	if is_mimic:
		_count("mimic_lures")
	if _pending_manager_task and speaker == "MANAGER":
		_count("manager_tasks_by_walkie")
	_pending_manager_task = false


func _on_task_completed(task: TaskData, by: Node) -> void:
	if is_instance_valid(by) and by.is_in_group(&"coworker"):
		_count("coworker_completions")
		if not task.is_manager_task:
			_count("coworker_basic_completions")


func _on_monster_state(state: StringName) -> void:
	_states.append(state)


func _on_hour(hour: int) -> void:
	_count("hours")
	if hour == Monster.SIGHTING_DEADLINE_HOUR and not _hour_two_done:
		_hour_two_done = true
		_move_to_vantage()


## At 2 AM: the vantage farthest from the monster (so it is not seen by accident first).
func _move_to_vantage() -> void:
	var player := GameState.player as Player
	var monster := GameState.monster as Node3D
	var best: Array = VANTAGES[0]
	var best_distance := -1.0
	for vantage: Array in VANTAGES:
		var distance := (vantage[0] as Vector3).distance_to(monster.global_position) if monster else 0.0
		if distance > best_distance:
			best = vantage
			best_distance = distance
	_place(player, best[0], best[1])


static func _place(player: Player, position: Vector3, yaw: float) -> void:
	player.global_position = position
	player.velocity = Vector3.ZERO
	player.rotation.y = deg_to_rad(yaw)
	(player.get_node("Head") as Node3D).rotation.x = 0.0
	player.reset_physics_interpolation()


func test_a_whole_night_runs_clean() -> void:
	var saved := [Engine.time_scale, Engine.physics_ticks_per_second, Engine.max_physics_steps_per_frame]
	_hook(Events.task_added, _on_task_added)
	_hook(Events.intercom_announced, _on_intercom)
	_hook(Events.walkie_message, _on_walkie)
	_hook(Events.task_completed, _on_task_completed)
	_hook(Events.monster_state_changed, _on_monster_state)
	_hook(Events.monster_sighted, func() -> void: _count("monster_sighted"))
	_hook(Events.night_ended, func(_result: StringName) -> void: _count("night_ended"))
	_hook(Events.coworker_missing, func(_name: String) -> void: _count("coworkers_missing"))
	_hook(Events.hour_changed, _on_hour)

	var game: Game = (load(GAME) as PackedScene).instantiate()
	game.capture_mouse_on_start = false
	tree.root.add_child(game)
	for i in 600:
		if game.state == Game.State.PLAYING:
			break
		await tree.process_frame
	assert_eq(game.state, Game.State.PLAYING, "the night started")
	assert_true(game.level.scene_file_path == Catalog.SCENES.level, "the game loaded the store, not the greybox")
	var manager := game.get_node_or_null("WorldView/SubViewport/World/StoreManager")
	assert_true(manager != null, "the store manager is in the world")
	if manager:
		manager._rng.seed = MANAGER_SEED   # deterministic intercom/walkie coin flips
	var player := GameState.player as Player
	player.max_health = 1.0e9
	player.health = 1.0e9
	_place(player, CORNER, CORNER_YAW)

	Engine.time_scale = TIME_SCALE
	Engine.physics_ticks_per_second = roundi(60.0 * TIME_SCALE)
	Engine.max_physics_steps_per_frame = 64
	var started_ms := Time.get_ticks_msec()
	var start_physics := Engine.get_physics_frames()
	while GameState.night_running and Time.get_ticks_msec() - started_ms < REAL_TIME_BUDGET_MS:
		await tree.process_frame
	var physics_ticks := Engine.get_physics_frames() - start_physics
	var real_seconds := (Time.get_ticks_msec() - started_ms) / 1000.0
	Engine.time_scale = saved[0]
	Engine.physics_ticks_per_second = saved[1]
	Engine.max_physics_steps_per_frame = saved[2]

	var basic_left := Tasks.get_required_remaining()
	print("  night smoke: %.0f s real, %d physics ticks (%.0f%% of game time), result %s" % [
		real_seconds, physics_ticks, 100.0 * physics_ticks / (GameState.SECONDS_PER_HOUR * GameState.END_HOUR * 60.0),
		GameState.last_result])
	print("  counts: %s" % _counts)
	print("  monster states: %s" % [_states])
	print("  basic tasks left for the player: %d of %d, coworker basic completions: %d" % [
		basic_left, Tasks.BASIC_TASKS_PER_NIGHT, Tasks.get_coworker_basic_completions()])

	assert_eq(_counts.get("night_ended", 0), 1, "the night ended")
	assert_true(GameState.last_result in [&"fired", &"win"], "reached 6 AM alive (result %s)" % GameState.last_result)
	assert_true(_counts.get("manager_tasks_by_intercom", 0) >= 1, "the manager gave a task over the intercom")
	assert_true(_counts.get("manager_tasks_by_walkie", 0) >= 1, "the manager gave a task over the walkie")
	assert_true(_counts.get("coworker_completions", 0) >= 1, "coworkers completed a task")
	assert_true(_states.size() >= 3, "the monster changed state at least 3 times (%d)" % _states.size())
	assert_true(&"sighting" in _states, "rule 3: the monster staged a sighting")
	assert_true(_counts.get("monster_sighted", 0) >= 1, "the player saw the monster")
	assert_true(Tasks.get_coworker_basic_completions() <= Tasks.MAX_COWORKER_BASIC_COMPLETIONS, "coworkers stay under the cap")
	assert_true(basic_left >= Tasks.BASIC_TASKS_PER_NIGHT - Tasks.MAX_COWORKER_BASIC_COMPLETIONS,
		"the player still has most basic tasks to do (%d left)" % basic_left)

	for hook: Array in _hooks:
		(hook[0] as Signal).disconnect(hook[1])
	game.queue_free()
	await tree.process_frame
	await tree.process_frame
