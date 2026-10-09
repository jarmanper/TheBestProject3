extends TestCase
## Balance rule (Task 9): coworkers may take at most Tasks.MAX_COWORKER_BASIC_COMPLETIONS basic
## tasks per night (completed + currently claimed, all coworkers combined), so the player still
## has to do most of the checklist. Manager tasks stay claimable (GDD seam 2).

var _stations: Array[TaskStation] = []
var _workers: Array[Node] = []


func before_each() -> void:
	Tasks.reset()
	_stations.clear()
	_workers.clear()


func after_each() -> void:
	Tasks.reset()
	for node in _stations + _workers:
		if is_instance_valid(node):
			node.free()
	_stations.clear()
	_workers.clear()


func _station(basic := true) -> TaskStation:
	var station := TaskStation.new()
	station.task_kind = StringName("kind_%d" % _stations.size())
	station.zone = StringName("zone_%d" % _stations.size())
	station.title = "Cap test %d" % _stations.size()
	station.basic_task = basic
	tree.root.add_child(station)
	_stations.append(station)
	return station


func _worker(is_player := false) -> Node:
	var worker := Node.new()
	if is_player:
		worker.add_to_group(&"player")
	tree.root.add_child(worker)
	_workers.append(worker)
	return worker


## Six basic tasks, like a real night.
func _basic_tasks() -> Array[TaskData]:
	for i in Tasks.BASIC_TASKS_PER_NIGHT:
		_station()
	Tasks.begin_night()
	return Tasks.get_open_tasks()


func test_cap_is_two() -> void:
	assert_eq(Tasks.MAX_COWORKER_BASIC_COMPLETIONS, 2)


func test_coworker_cannot_claim_a_basic_task_after_reaching_the_cap() -> void:
	var tasks := _basic_tasks()
	var coworker := _worker()
	for i in Tasks.MAX_COWORKER_BASIC_COMPLETIONS:
		assert_true(Tasks.claim_task(tasks[i], coworker), "claim %d under the cap" % i)
		Tasks.complete_task(tasks[i], coworker)
	assert_false(Tasks.claim_task(tasks[2], coworker), "cap reached: basic claim must be refused")
	assert_eq(Tasks.get_coworker_basic_completions(), 2)


func test_open_claims_count_toward_the_cap() -> void:
	var tasks := _basic_tasks()
	var dale := _worker()
	var rita := _worker()
	var marcus := _worker()
	assert_true(Tasks.claim_task(tasks[0], dale))
	assert_true(Tasks.claim_task(tasks[1], rita))
	assert_false(Tasks.claim_task(tasks[2], marcus), "two open coworker claims already fill the cap")
	assert_true(Tasks.claim_task(tasks[0], dale), "re-claiming a task it already holds stays allowed")
	Tasks.release_task(tasks[1], rita)
	assert_true(Tasks.claim_task(tasks[2], marcus), "a released claim frees the slot")


func test_completions_without_a_claim_also_count() -> void:
	var tasks := _basic_tasks()
	var coworker := _worker()
	Tasks.complete_task(tasks[0], coworker)
	Tasks.complete_task(tasks[1], coworker)
	assert_false(Tasks.claim_task(tasks[2], coworker))


func test_manager_tasks_stay_claimable_past_the_cap() -> void:
	var tasks := _basic_tasks()
	var coworker := _worker()
	Tasks.complete_task(tasks[0], coworker)
	Tasks.complete_task(tasks[1], coworker)
	var manager_task := Tasks.add_manager_task(_station(false), 60.0)
	assert_true(Tasks.claim_task(manager_task, coworker), "manager tasks are never capped")
	Tasks.complete_task(manager_task, coworker)
	assert_eq(Tasks.get_coworker_basic_completions(), 2, "manager tasks do not use up the basic cap")


func test_player_is_never_capped() -> void:
	var tasks := _basic_tasks()
	var coworker := _worker()
	var player := _worker(true)
	Tasks.complete_task(tasks[0], coworker)
	Tasks.complete_task(tasks[1], coworker)
	assert_true(Tasks.claim_task(tasks[2], player))
	Tasks.complete_task(tasks[2], player)
	Tasks.complete_task(tasks[3], player)
	assert_eq(Tasks.get_coworker_basic_completions(), 2, "player completions are not coworker completions")


func test_reset_clears_the_count() -> void:
	var tasks := _basic_tasks()
	var coworker := _worker()
	Tasks.complete_task(tasks[0], coworker)
	Tasks.complete_task(tasks[1], coworker)
	Tasks.reset()
	for station in _stations:
		station.free()
	_stations.clear()
	var fresh := _basic_tasks()
	assert_eq(Tasks.get_coworker_basic_completions(), 0)
	assert_true(Tasks.claim_task(fresh[0], coworker))
