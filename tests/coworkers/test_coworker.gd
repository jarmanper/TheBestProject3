extends TestCase
## Coworker AI: task choice (manager first), claims, work time, flee, walkie, abduction.

const AiTestWorld := preload("res://tests/monster/ai_test_world.gd")
const TaskSource := preload("res://systems/monster/sandbox/sandbox_task_source.gd")
const STEP := 1.0 / 60.0

var world: Node3D
var source: RefCounted
var walkies: Array[Dictionary] = []


func before_each() -> void:
	world = AiTestWorld.create(tree)
	source = TaskSource.new()
	source.sort_manager_first = false   # the coworker must prefer manager tasks itself
	Events.walkie_message.connect(_on_walkie)


func after_each() -> void:
	Events.walkie_message.disconnect(_on_walkie)
	world.dispose()


func _on_walkie(speaker: String, message: String, origin: Vector3, is_mimic: bool) -> void:
	walkies.append({"speaker": speaker, "message": message, "origin": origin, "is_mimic": is_mimic})


func _spawn(employee_name: String, at: Vector3) -> Coworker:
	var coworker: Coworker = world.add_coworker(employee_name, at, source)
	coworker.set_physics_process(false)
	coworker.rng.seed = 99
	return coworker


## Fixed 60 Hz ticks inside one physics frame (move_and_slide uses the physics delta).
func _run(coworker: Coworker, seconds: float) -> void:
	await tree.physics_frame
	for i in maxi(roundi(seconds / STEP), 1):
		coworker.tick(STEP)


## Ticks until `condition` holds; returns the seconds it took (-1 if it never did).
func _run_until(coworker: Coworker, condition: Callable, max_seconds: float) -> float:
	await tree.physics_frame
	for i in roundi(max_seconds / STEP):
		coworker.tick(STEP)
		if condition.call():
			return (i + 1) * STEP
	return -1.0


func test_joins_groups_and_layers() -> void:
	var dale := _spawn("DALE", Vector3.ZERO)
	assert_true(dale.is_in_group(&"coworker"))
	assert_true(dale.is_in_group(&"employee"))
	assert_eq(dale.collision_layer, Catalog.LAYER_NPC)
	assert_eq(dale.collision_mask, Catalog.LAYER_WORLD)
	assert_true(dale.get_node(^"Visual").get_child_count() > 0, "model or placeholder")


func test_prefers_the_manager_task() -> void:
	var near: TaskStation = world.add_station(Vector3(2, 0, 0), &"aisle_1", "Mop the spill in Aisle 1")
	var far: TaskStation = world.add_station(Vector3(20, 0, 0), &"storage", "Restock the storage room")
	var basic: TaskData = source.add_task(near, false)
	var manager: TaskData = source.add_task(far, true)
	var dale := _spawn("DALE", Vector3.ZERO)
	assert_eq(dale.choose_task(), manager, "manager task first even though it is farther")
	manager.claimed_by = Node.new()
	assert_eq(dale.choose_task(), basic, "someone else has the manager task")
	manager.claimed_by.free()
	manager.claimed_by = null


func test_takes_the_nearest_basic_task() -> void:
	var far: TaskStation = world.add_station(Vector3(15, 0, 0), &"produce", "Far")
	var near: TaskStation = world.add_station(Vector3(3, 0, 0), &"aisle_1", "Near")
	source.add_task(far, false)
	var near_task: TaskData = source.add_task(near, false)
	var dale := _spawn("DALE", Vector3.ZERO)
	assert_eq(dale.choose_task(), near_task)


func test_claims_prevent_double_work() -> void:
	var station: TaskStation = world.add_station(Vector3(12, 0, 0), &"aisle_1", "Face the shelves")
	var task: TaskData = source.add_task(station, false)
	var dale := _spawn("DALE", Vector3.ZERO)
	var rita := _spawn("RITA", Vector3(1, 0, 0))
	await _run(dale, 3.1)   # past the staggered first look at the checklist
	assert_eq(dale.current_task, task)
	assert_eq(task.claimed_by, dale)
	assert_eq(dale.state, Coworker.TO_TASK)
	await _run(rita, 3.1)
	assert_eq(rita.current_task, null, "already claimed by DALE")
	assert_false(rita.state == Coworker.TO_TASK or rita.state == Coworker.WORKING)
	assert_eq(rita.choose_task(), null)


func test_works_hold_time_times_four_then_completes() -> void:
	var station: TaskStation = world.add_station(Vector3(0.3, 0, 0), &"aisle_1", "Price check")
	var task: TaskData = source.add_task(station, false, 2.0)
	var dale := _spawn("DALE", Vector3.ZERO)
	var started: float = await _run_until(dale, func() -> bool: return dale.state == Coworker.WORKING, 5.0)
	assert_true(started > 0.0, "starts working at the station")
	var worked: float = await _run_until(dale, func() -> bool: return task.completed, 20.0)
	assert_near(worked, 2.0 * Coworker.WORK_TIME_FACTOR, 0.05, "works hold_time x 4")
	assert_eq(source.completed, [task] as Array[TaskData])
	assert_eq(dale.state, Coworker.RESTING)
	assert_eq(dale.current_task, null)


func test_skips_a_task_it_cannot_reach() -> void:
	var walled: TaskStation = world.add_station(Vector3(6, 0, 0), &"storage", "Behind walls")
	for side in [Vector3(2.5, 1.5, 0), Vector3(-2.5, 1.5, 0)]:
		world.add_box(Vector3(6, 0, 0) + side, Vector3(0.3, 3.0, 5.3))
	for side in [Vector3(0, 1.5, 2.5), Vector3(0, 1.5, -2.5)]:
		world.add_box(Vector3(6, 0, 0) + side, Vector3(5.3, 3.0, 0.3))
	var open_station: TaskStation = world.add_station(Vector3(-10, 0, 0), &"produce", "In the open")
	var walled_task: TaskData = source.add_task(walled, false)
	var open_task: TaskData = source.add_task(open_station, false)
	world.bake_navigation()
	await world.settle_navigation()
	var dale := _spawn("DALE", Vector3.ZERO)
	assert_eq(dale.choose_task(), walled_task, "nearest first")
	var took: float = await _run_until(dale, func() -> bool: return dale.current_task == open_task, 40.0)
	assert_true(took > 0.0, "gave up on the walled-in task and took the other one")
	assert_eq(walled_task.claimed_by, null, "released the claim")


func test_drops_task_the_player_finished_first() -> void:
	var station: TaskStation = world.add_station(Vector3(10, 0, 0), &"aisle_1", "Mop")
	var task: TaskData = source.add_task(station, false)
	var dale := _spawn("DALE", Vector3.ZERO)
	await _run(dale, 3.1)
	assert_eq(dale.state, Coworker.TO_TASK)
	source.complete_task(task, null)
	await _run(dale, STEP)
	assert_eq(dale.current_task, null)
	assert_eq(dale.state, Coworker.CHOOSE)


func test_abduct_releases_claim_and_frees() -> void:
	var station: TaskStation = world.add_station(Vector3(10, 0, 0), &"aisle_1", "Mop")
	var task: TaskData = source.add_task(station, false)
	var dale := _spawn("DALE", Vector3.ZERO)
	await _run(dale, 3.1)
	assert_eq(task.claimed_by, dale)
	dale.abduct()
	assert_eq(task.claimed_by, null, "claim released")
	assert_true(dale.is_queued_for_deletion())


func test_flees_from_true_form_monster_with_panic_line() -> void:
	world.add_player(Vector3(0, 0, 30), Vector3(0, 0, 40))
	var dale := _spawn("DALE", Vector3.ZERO)
	var monster: Monster = world.add_monster(Vector3(0, 0, -8))
	monster.set_physics_process(false)
	await world.settle()
	await _run(dale, STEP)
	assert_false(dale.state == Coworker.FLEEING, "a disguised monster looks like a coworker")
	monster.force_state(Monster.CHASE)
	await _run(dale, STEP)
	assert_eq(dale.state, Coworker.FLEEING)
	var panic := walkies.filter(func(w: Dictionary) -> bool: return w["speaker"] == "DALE")
	assert_eq(panic.size(), 1, "one panic walkie line")
	assert_false(panic[0]["is_mimic"])


func test_does_not_flee_without_line_of_sight() -> void:
	world.add_player(Vector3(0, 0, 30), Vector3(0, 0, 40))
	world.add_box(Vector3(0, 1.5, -4), Vector3(10, 3, 0.3))
	var dale := _spawn("DALE", Vector3.ZERO)
	var monster: Monster = world.add_monster(Vector3(0, 0, -8))
	monster.set_physics_process(false)
	await world.settle()
	monster.force_state(Monster.CHASE)
	await _run(dale, STEP)
	assert_false(dale.state == Coworker.FLEEING)


func test_walkie_check_in_tells_where_they_really_are() -> void:
	world.add_zone(&"storage", Vector3(0, 1.5, 0), Vector3(10, 3, 10))
	var rita := _spawn("RITA", Vector3(1, 0, 1))
	rita.say_where_i_am()
	assert_eq(walkies.size(), 1)
	assert_eq(walkies[0]["speaker"], "RITA")
	assert_false(walkies[0]["is_mimic"])
	assert_true(String(walkies[0]["message"]).contains("storage room"), walkies[0]["message"])
	assert_true((walkies[0]["origin"] as Vector3).distance_to(rita.global_position) < 0.01)


func test_chatter_every_one_to_two_minutes() -> void:
	var rita := _spawn("RITA", Vector3.ZERO)
	await _run(rita, Coworker.CHATTER_INTERVAL.x - 1.0)
	assert_eq(walkies.size(), 0, "not before 60 s")
	await _run(rita, Coworker.CHATTER_INTERVAL.y - Coworker.CHATTER_INTERVAL.x + 2.0)
	assert_true(walkies.size() >= 1, "checks in within 60-120 s")
	assert_false(walkies[0]["is_mimic"])
