extends TestCase
## Monster behaviour in small physics worlds. The monster's physics processing
## is off and the tests call tick() with fixed 60 Hz steps (deterministic).

const AiTestWorld := preload("res://tests/monster/ai_test_world.gd")
const TaskSource := preload("res://systems/monster/sandbox/sandbox_task_source.gd")
const STEP := 1.0 / 60.0

var world: Node3D
var states: Array[StringName] = []
var events: Array[String] = []
var walkies: Array[Dictionary] = []
var missing: Array[String] = []


class RecordingLight:
	extends StoreLight
	var last_disturbance := -1.0

	func set_disturbance(amount: float) -> void:
		last_disturbance = amount


func before_each() -> void:
	GameState.night_running = false
	GameState.night_time = 0.0
	GameState.stats = {}
	world = AiTestWorld.create(tree)
	Events.monster_state_changed.connect(_on_state)
	Events.chase_started.connect(_on_chase_started)
	Events.chase_ended.connect(_on_chase_ended)
	Events.monster_sighted.connect(_on_sighted)
	Events.walkie_message.connect(_on_walkie)
	Events.coworker_missing.connect(_on_missing)


func after_each() -> void:
	Events.monster_state_changed.disconnect(_on_state)
	Events.chase_started.disconnect(_on_chase_started)
	Events.chase_ended.disconnect(_on_chase_ended)
	Events.monster_sighted.disconnect(_on_sighted)
	Events.walkie_message.disconnect(_on_walkie)
	Events.coworker_missing.disconnect(_on_missing)
	world.dispose()
	GameState.night_time = 0.0
	GameState.stats = {}


func _on_state(state: StringName) -> void:
	states.append(state)


func _on_chase_started() -> void:
	events.append("chase_started")


func _on_chase_ended() -> void:
	events.append("chase_ended")


func _on_sighted() -> void:
	events.append("sighted")


func _on_walkie(speaker: String, message: String, origin: Vector3, is_mimic: bool) -> void:
	walkies.append({"speaker": speaker, "message": message, "origin": origin, "is_mimic": is_mimic})


func _on_missing(coworker_name: String) -> void:
	missing.append(coworker_name)


func _spawn_monster(at: Vector3) -> Monster:
	var monster: Monster = world.add_monster(at)
	monster.set_physics_process(false)
	monster.rng.seed = 1234
	return monster


## Runs `seconds` of fixed 60 Hz ticks. They run inside one physics frame so
## move_and_slide() uses the physics delta like a real _physics_process.
func _run(monster: Monster, seconds: float) -> void:
	await tree.physics_frame
	for i in maxi(roundi(seconds / STEP), 1):
		monster.tick(STEP)


## Ticks until `monster.state != from_state`; returns the number of ticks (-1 if never).
func _ticks_until_leaving(monster: Monster, from_state: StringName, max_ticks: int, each_tick := Callable()) -> int:
	await tree.physics_frame
	for i in max_ticks:
		if each_tick.is_valid():
			each_tick.call()
		monster.tick(STEP)
		if monster.state != from_state:
			return i + 1
	return -1


func _set_hour(hour: float) -> void:
	GameState.night_time = hour * GameState.SECONDS_PER_HOUR + 1.0


# --- Rule 2: reveal ----------------------------------------------------------------

func test_reveals_after_four_seconds_in_range_with_los() -> void:
	world.add_player(Vector3.ZERO, Vector3(0, 0, -10))
	var monster := _spawn_monster(Vector3(0, 0, -3.5))
	await world.settle()
	assert_eq(monster.state, Monster.DISGUISED_ROAM)
	assert_false(monster.is_true_form())
	await _run(monster, 3.9)
	assert_eq(monster.state, Monster.DISGUISED_ROAM, "not yet at 3.9 s")
	assert_true(monster._staring, "stops and stares at the player before turning")
	await _run(monster, 0.15)
	assert_eq(monster.state, Monster.REVEAL, "turns at 4 s")
	assert_true(monster.is_true_form())
	assert_eq(events.count("chase_started"), 1)
	await _run(monster, 1.6)
	var after_reveal := states.slice(states.rfind(Monster.REVEAL))
	assert_true(after_reveal.size() >= 2 and after_reveal[1] == Monster.CHASE, "reveal lasts 1.2-1.5 s then chases: %s" % [after_reveal])


func test_no_reveal_when_player_hidden() -> void:
	var player: Player = world.add_player(Vector3.ZERO, Vector3(0, 0, -10))
	var monster := _spawn_monster(Vector3(0, 0, -4))
	await world.settle()
	monster.force_state(Monster.LURE)
	player.is_hidden = true
	await _run(monster, 6.0)
	assert_false(Monster.REVEAL in states, "never reveals at a hidden player")
	assert_false(monster.is_true_form())


func test_no_reveal_without_line_of_sight() -> void:
	world.add_player(Vector3.ZERO, Vector3(0, 0, -10))
	world.add_box(Vector3(0.0, 1.5, -2.0), Vector3(8.0, 3.0, 0.3))
	var monster := _spawn_monster(Vector3(0, 0, -4))
	await world.settle()
	monster.force_state(Monster.LURE)
	await _run(monster, 6.0)
	assert_false(Monster.REVEAL in states, "a wall between them")


func test_no_reveal_out_of_range() -> void:
	world.add_player(Vector3.ZERO, Vector3(0, 0, -10))
	var monster := _spawn_monster(Vector3(0, 0, -9))
	await world.settle()
	monster.force_state(Monster.LURE)
	await _run(monster, 6.0)
	assert_false(Monster.REVEAL in states, "9 m is beyond REVEAL_RANGE")


# --- Rule 1: sprint and winded ---------------------------------------------------------

func test_winded_after_thirteen_seconds_of_chase_then_chases_again() -> void:
	var player: Player = world.add_player(Vector3(0, 0, -10), Vector3(0, 0, -20))
	var monster := _spawn_monster(Vector3.ZERO)
	await world.settle()
	monster.force_state(Monster.CHASE)
	# The player keeps running ahead, always in sight, never caught.
	var flee := func() -> void: player.global_position = monster.global_position + Vector3(0, 0, -8)
	var ticks: int = await _ticks_until_leaving(monster, Monster.CHASE, 2000, flee)
	assert_eq(ticks, 780, "13 s of sprint at 60 Hz")
	assert_eq(monster.state, Monster.WINDED)
	ticks = await _ticks_until_leaving(monster, Monster.WINDED, 2000, flee)
	assert_eq(ticks, 360, "winded for 6 s")
	assert_eq(monster.state, Monster.CHASE, "sees the player: chases again")
	assert_near(monster.rules.sprint_time, 0.0, 0.05, "with a fresh sprint timer")


func test_winded_searches_when_player_out_of_sight() -> void:
	var player: Player = world.add_player(Vector3(0, 0, -10), Vector3(0, 0, -20))
	var monster := _spawn_monster(Vector3.ZERO)
	await world.settle()
	monster.force_state(Monster.WINDED)
	player.is_hidden = true
	await _run(monster, 6.1)
	assert_eq(monster.state, Monster.SEARCH)


# --- Rule 3: staged sighting ----------------------------------------------------------

func test_sighting_staged_at_two_am_when_unsighted() -> void:
	var player: Player = world.add_player(Vector3.ZERO, Vector3(0, 0, -10))
	var monster := _spawn_monster(Vector3(0, 0, 25))   # behind the player
	world.bake_navigation()
	await world.settle_navigation()
	_set_hour(1)
	await _run(monster, 0.5)
	assert_false(monster.state == Monster.SIGHTING, "not before 2 AM")
	monster.global_position = Vector3(0, 0, 25)
	_set_hour(2)
	await _run(monster, STEP)
	assert_eq(monster.state, Monster.SIGHTING, "staged at 2 AM")
	var camera := Perception.find_player_camera(player)
	var distance := Vector2(monster.global_position.x, monster.global_position.z).length()
	assert_true(distance >= 11.5 and distance <= 22.5, "12-22 m from the player (got %.1f)" % distance)
	assert_true(Perception.is_point_visible_to_camera(camera, monster.global_position + Vector3.UP * 1.2), "inside the view")
	await _run(monster, STEP)
	assert_eq(events.count("sighted"), 1, "monster_sighted emitted")
	assert_eq(GameState.stats.get("monster_sightings", 0), 1)
	# Holds ~3 s, then walks out of view and goes back to roaming.
	await _run(monster, 3.2)
	assert_eq(monster._phase, 1, "leaving after the hold")


func test_no_staged_sighting_when_already_sighted() -> void:
	world.add_player(Vector3.ZERO, Vector3(0, 0, -10))
	var monster := _spawn_monster(Vector3(0, 0, -10))   # in plain view
	world.bake_navigation()
	await world.settle_navigation()
	_set_hour(1)
	await _run(monster, STEP)
	assert_true(monster.rules.has_been_sighted, "seen naturally at 1 AM")
	assert_eq(events.count("sighted"), 1)
	monster.global_position = Vector3(0, 0, 25)   # out of view
	_set_hour(2)
	await _run(monster, 1.0)
	assert_false(Monster.SIGHTING in states, "no staged sighting needed")


func test_new_sighting_counted_after_a_real_gap() -> void:
	world.add_player(Vector3.ZERO, Vector3(0, 0, -10))
	var monster := _spawn_monster(Vector3(0, 0, -10))
	await world.settle()
	monster.force_state(Monster.LURE)
	await _run(monster, STEP)
	monster.global_position = Vector3(0, 0, 25)
	await _run(monster, Monster.SIGHTING_GAP + 0.5)
	monster.global_position = Vector3(0, 0, -10)
	await _run(monster, STEP)
	assert_eq(events.count("sighted"), 2)
	assert_eq(GameState.stats.get("monster_sightings", 0), 2)


# --- Seam 1, hearing ---------------------------------------------------------------------

func test_intercom_sends_it_to_investigate_that_zone() -> void:
	world.add_player(Vector3.ZERO, Vector3(0, 0, -10))
	var zone: StoreZone = world.add_zone(&"storage", Vector3(15, 1.5, 15), Vector3(8, 3, 8))
	world.add_zone(&"produce", Vector3(-15, 1.5, -15), Vector3(8, 3, 8))
	var monster := _spawn_monster(Vector3(0, 0, -20))
	world.bake_navigation()
	await world.settle_navigation()
	Events.intercom_announced.emit("Clean-up in the storage room.", &"storage")
	assert_eq(monster.state, Monster.INVESTIGATE)
	assert_true(zone.contains_point(monster.investigate_target), "target %s inside the storage zone" % monster.investigate_target)
	assert_false(monster.is_true_form(), "goes disguised")


func test_intercom_ignored_while_chasing() -> void:
	world.add_player(Vector3.ZERO, Vector3(0, 0, -10))
	world.add_zone(&"storage", Vector3(15, 1.5, 15), Vector3(8, 3, 8))
	var monster := _spawn_monster(Vector3(0, 0, -20))
	await world.settle()
	monster.force_state(Monster.CHASE)
	Events.intercom_announced.emit("Clean-up in the storage room.", &"storage")
	assert_eq(monster.state, Monster.CHASE)


func test_hears_sprinting_player_within_radius() -> void:
	var player: Player = world.add_player(Vector3.ZERO, Vector3(0, 0, -10))
	var monster := _spawn_monster(Vector3(0, 0, 12))
	world.add_box(Vector3(0.0, 1.5, 6.0), Vector3(8.0, 3.0, 0.3))   # hearing goes through walls
	await world.settle()
	player.noise = 0.35
	await _run(monster, STEP)
	assert_eq(monster.state, Monster.DISGUISED_ROAM, "walking is quiet enough")
	player.noise = 1.0
	await _run(monster, STEP)
	assert_eq(monster.state, Monster.INVESTIGATE, "sprinting within 14 m is heard")
	assert_true(monster.investigate_target.distance_to(Vector3.ZERO) < 0.5)


func test_does_not_hear_beyond_radius() -> void:
	var player: Player = world.add_player(Vector3.ZERO, Vector3(0, 0, -10))
	var monster := _spawn_monster(Vector3(0, 0, 20))
	await world.settle()
	player.noise = 1.0
	await _run(monster, STEP)
	assert_eq(monster.state, Monster.DISGUISED_ROAM)


# --- Hiding ---------------------------------------------------------------------------------

func _add_spot(at: Vector3, exit: Vector3) -> HidingSpot:
	var spot := HidingSpot.new()
	var exit_point := Marker3D.new()
	exit_point.name = "ExitPoint"
	spot.add_child(exit_point)
	world.add_child(spot)
	spot.global_position = at
	exit_point.global_position = exit
	return spot


func test_witnessed_hiding_spot_is_searched_and_occupant_pulled_out() -> void:
	var player: Player = world.add_player(Vector3(0, 0, -1), Vector3(0, 0, -10))
	var spot := _add_spot(Vector3(0, 0, -1.5), Vector3(0, 0, -0.5))
	var monster := _spawn_monster(Vector3(0, 0, 0.3))
	await world.settle()
	monster.force_state(Monster.CHASE)
	player.global_position = Vector3(0, 0, -6)   # just out of reach
	await _run(monster, STEP)
	player.global_position = Vector3(0, 0, -1)
	player.enter_hiding(spot)
	assert_eq(monster.witnessed_spot, spot, "watched the player hide")
	await _run(monster, 0.1)
	assert_eq(monster.state, Monster.ATTACK, "went to the spot and pulled them out")
	assert_false(player.is_hidden, "no longer hidden")


func test_unwitnessed_hiding_is_not_known() -> void:
	var player: Player = world.add_player(Vector3(0, 0, -1), Vector3(0, 0, -10))
	world.add_box(Vector3(0.0, 1.5, 4.0), Vector3(10.0, 3.0, 0.3))
	var spot := _add_spot(Vector3(0, 0, -1.5), Vector3(0, 0, -0.5))
	var monster := _spawn_monster(Vector3(0, 0, 8))
	await world.settle()
	monster.force_state(Monster.CHASE)
	await _run(monster, STEP)
	player.enter_hiding(spot)
	assert_eq(monster.witnessed_spot, null)


# --- Attack and retreat ------------------------------------------------------------------------

func test_attack_damages_player_in_range_then_retreats() -> void:
	var player: Player = world.add_player(Vector3.ZERO, Vector3(0, 0, -10))
	var monster := _spawn_monster(Vector3(0, 0, -1.2))
	await world.settle()
	monster.force_state(Monster.CHASE)
	await _run(monster, STEP)
	assert_eq(monster.state, Monster.ATTACK, "in range: attacks")
	await _run(monster, Monster.ATTACK_WINDUP + 0.05)
	assert_near(player.health, 100.0 - Monster.ATTACK_DAMAGE, 0.01)
	await _run(monster, Monster.ATTACK_RECOVER)
	assert_eq(monster.state, Monster.RETREAT)


func test_retreat_redisguises_out_of_view_and_ends_chase() -> void:
	world.add_player(Vector3.ZERO, Vector3(0, 0, -10))
	world.add_marker(&"patrol_point", Vector3(0, 0, 25))
	world.add_marker(&"patrol_point", Vector3(-20, 0, 20))
	var monster := _spawn_monster(Vector3(0, 0, 20))   # behind the player, 20 m away
	await world.settle()
	monster.force_state(Monster.REVEAL)
	monster.force_state(Monster.RETREAT)
	await _run(monster, Monster.RETREAT_UNSEEN_TIME + 0.2)
	assert_eq(monster.state, Monster.DISGUISED_ROAM)
	assert_false(monster.is_true_form(), "disguised again")
	assert_eq(events.count("chase_started"), 1)
	assert_eq(events.count("chase_ended"), 1)
	assert_true(monster.rules.reveal_cooldown_left > Monster.REVEAL_COOLDOWN - 1.0, "reveal cooldown running")


func test_retreat_waits_while_in_view() -> void:
	world.add_player(Vector3.ZERO, Vector3(0, 0, -10))
	var monster := _spawn_monster(Vector3(0, 0, -20))   # in plain view, 20 m away
	await world.settle()
	monster.force_state(Monster.RETREAT)
	var pin := func() -> void: monster.global_position = Vector3(0, 0, -20)   # pinned in view
	var ticks: int = await _ticks_until_leaving(monster, Monster.RETREAT, 180, pin)
	assert_eq(ticks, -1)
	assert_eq(monster.state, Monster.RETREAT, "never vanishes while watched")
	assert_true(monster.is_true_form())


# --- Mimicry and abductions ----------------------------------------------------------------------

func test_mimic_lure_calls_from_far_away_out_of_view() -> void:
	world.add_player(Vector3.ZERO, Vector3(0, 0, -10))
	world.add_zone(&"storage", Vector3(20, 1.5, 20), Vector3(8, 3, 8))
	var monster := _spawn_monster(Vector3(0, 0, 10))
	world.bake_navigation()
	await world.settle_navigation()
	await _run(monster, STEP)
	assert_true(monster.try_mimic_lure())
	assert_eq(monster.state, Monster.LURE)
	assert_eq(walkies.size(), 1)
	assert_true(walkies[0]["is_mimic"], "the hidden truth flag is set")
	assert_eq(walkies[0]["speaker"], monster.disguise_name)
	assert_true(String(walkies[0]["message"]).contains(monster.disguise_name))
	assert_true(String(walkies[0]["message"]).contains("storage room"))
	assert_true(Vector2(monster.global_position.x, monster.global_position.z).length() >= 14.0, "far from the player")
	await _run(monster, STEP)
	assert_false(monster.is_in_player_view(), "appeared out of view")


func test_mimic_lure_never_teleports_while_seen() -> void:
	world.add_player(Vector3.ZERO, Vector3(0, 0, -10))
	world.add_zone(&"storage", Vector3(20, 1.5, 20), Vector3(8, 3, 8))
	var monster := _spawn_monster(Vector3(0, 0, -10))
	await world.settle()
	await _run(monster, STEP)
	assert_true(monster.is_in_player_view())
	assert_false(monster.try_mimic_lure())
	assert_true(walkies.is_empty())


func test_abduction_emits_coworker_missing() -> void:
	world.add_player(Vector3.ZERO, Vector3(0, 0, -10))
	var source := TaskSource.new()
	var rita: Coworker = world.add_coworker("RITA", Vector3(0, 0, 25), source)   # behind the player, far
	rita.set_physics_process(false)
	var monster := _spawn_monster(Vector3(10, 0, 10))
	await world.settle()
	await _run(monster, STEP)
	assert_true(monster.try_abduction())
	assert_eq(missing, ["RITA"] as Array[String])
	assert_true(rita.is_queued_for_deletion(), "coworker removed")
	assert_eq(GameState.stats.get("coworkers_lost", 0), 1)
	assert_true("RITA" in monster.missing_names)


func test_no_abduction_in_view_or_near_player() -> void:
	world.add_player(Vector3.ZERO, Vector3(0, 0, -10))
	var near: Coworker = world.add_coworker("DALE", Vector3(0, 0, 8))      # behind but close
	var seen: Coworker = world.add_coworker("MARCUS", Vector3(0, 0, -20))  # far but in view
	near.set_physics_process(false)
	seen.set_physics_process(false)
	var monster := _spawn_monster(Vector3(10, 0, 10))
	await world.settle()
	await _run(monster, STEP)
	assert_false(monster.try_abduction())
	assert_true(missing.is_empty())


func test_abductions_capped_at_two() -> void:
	world.add_player(Vector3.ZERO, Vector3(0, 0, -10))
	for i in 3:
		var coworker: Coworker = world.add_coworker(Catalog.COWORKERS[i]["name"], Vector3(i * 3.0, 0, 25))
		coworker.set_physics_process(false)
	var monster := _spawn_monster(Vector3(10, 0, 10))
	await world.settle()
	await _run(monster, STEP)
	assert_true(monster.try_abduction())
	assert_true(monster.try_abduction())
	assert_false(monster.try_abduction(), "MAX_ABDUCTIONS reached")
	assert_eq(missing.size(), 2)


# --- Presence --------------------------------------------------------------------------------------

func test_flickers_lights_within_radius() -> void:
	var near := RecordingLight.new()
	var far := RecordingLight.new()
	world.add_child(near)
	world.add_child(far)
	near.global_position = Vector3(3, 3.5, 0)
	far.global_position = Vector3(20, 3.5, 0)
	var monster := _spawn_monster(Vector3.ZERO)
	await world.settle()
	await _run(monster, 0.3)
	assert_true(near.last_disturbance > 0.0, "a light 4.6 m away flickers")
	assert_eq(far.last_disturbance, -1.0, "a light 20 m away does not")


func test_registers_in_group_and_game_state() -> void:
	var monster := _spawn_monster(Vector3.ZERO)
	await world.settle()
	assert_true(monster.is_in_group(&"monster"))
	assert_eq(GameState.monster, monster)
	assert_eq(monster.collision_layer, Catalog.LAYER_MONSTER)
	assert_eq(monster.collision_mask, Catalog.LAYER_WORLD)
	assert_true(monster.get_node(^"TrueForm").get_child_count() > 0, "true form model or placeholder")
	assert_true(monster.get_node(^"DisguiseForm").get_child_count() > 0, "disguise model or placeholder")
	assert_true(monster.disguise_name in ["DALE", "RITA", "MARCUS"])
