extends TestCase
## Personal work for all three AI employees, player help, shared requests and missing staff.

const COWORKER := preload("res://systems/coworkers/coworker.tscn")

var _stations: Array[TaskStation] = []
var _workers: Array[Coworker] = []
var _player: Node


func before_each() -> void:
	Tasks.reset()
	for i in Tasks.BASIC_TASKS_PER_NIGHT:
		_station()
	for info: Dictionary in Catalog.COWORKERS:
		var worker: Coworker = COWORKER.instantiate()
		worker.employee_name = info.name
		tree.root.add_child(worker)
		worker.set_physics_process(false)
		_workers.append(worker)
	_player = Node.new()
	_player.add_to_group(&"player")
	tree.root.add_child(_player)
	Tasks.begin_night()


func after_each() -> void:
	Tasks.reset()
	for worker in _workers:
		if is_instance_valid(worker):
			worker.free()
	for station in _stations:
		station.free()
	_player.free()
	_workers.clear()
	_stations.clear()


func _station() -> TaskStation:
	var station := TaskStation.new()
	station.task_kind = StringName("kind_%d" % _stations.size())
	station.zone = StringName("zone_%d" % _stations.size())
	station.title = "Crew task %d" % _stations.size()
	tree.root.add_child(station)
	_stations.append(station)
	return station


func _assignment(worker: Coworker) -> TaskData:
	for task in Tasks.get_open_tasks():
		if task.assigned_to == StringName(worker.employee_name):
			return task
	return null


func test_each_coworker_gets_a_distinct_personal_task() -> void:
	var claimed: Array[TaskData] = []
	for worker in _workers:
		var task := worker.choose_task()
		assert_true(task != null, "%s has work" % worker.employee_name)
		if task == null:
			continue
		assert_eq(task.assigned_to, StringName(worker.employee_name))
		assert_false(claimed.has(task), "each worker has different work")
		assert_true(Tasks.claim_task(task, worker))
		claimed.append(task)
	assert_eq(claimed.size(), 3, "all three can work at the same time")
	var player_tasks := Tasks.get_open_tasks().filter(func(t: TaskData) -> bool: return t.assigned_to == &"YOU")
	assert_eq(player_tasks.size(), 3, "three assignments remain for the human")


func test_coworkers_cannot_take_each_others_or_the_players_work() -> void:
	var dale := _workers[0]
	var rita := _workers[1]
	assert_false(Tasks.claim_task(_assignment(rita), dale))
	for task in Tasks.get_open_tasks():
		if task.assigned_to == &"YOU":
			assert_false(Tasks.claim_task(task, dale))
	var own := _assignment(dale)
	assert_true(Tasks.claim_task(own, dale))
	assert_true(Tasks.claim_task(own, dale), "reclaiming one's current job is safe")
	Tasks.complete_task(own, dale)
	assert_eq(dale.choose_task(), null, "does not poach someone else's assignment after finishing")


func test_player_can_finish_a_coworkers_task_first() -> void:
	var dale := _workers[0]
	var task := _assignment(dale)
	dale._tick_choose(4.0)
	assert_eq(dale.current_task, task)
	Tasks.complete_task(task, _player)
	assert_true(task.completed)
	assert_eq(task.claimed_by, null)
	dale._tick_to_task(0.0)
	assert_eq(dale.current_task, null)
	assert_eq(dale.state, Coworker.CHOOSE)
	assert_eq(Tasks.get_coworker_basic_completions(), 0)


func test_all_three_completions_count_toward_the_shift() -> void:
	for worker in _workers:
		var task := _assignment(worker)
		assert_true(Tasks.claim_task(task, worker))
		Tasks.complete_task(task, worker)
	assert_eq(Tasks.get_coworker_basic_completions(), 3)
	assert_eq(Tasks.get_required_remaining(), 3)
	assert_false(Tasks.all_required_done())
	for task in Tasks.get_open_tasks():
		Tasks.complete_task(task, _player)
	assert_true(Tasks.all_required_done())


func test_manager_requests_remain_shared_and_take_priority() -> void:
	var manager_task := Tasks.add_manager_task(_station(), 60.0)
	var dale := _workers[0]
	assert_eq(dale.choose_task(), manager_task)
	assert_true(Tasks.claim_task(manager_task, dale))
	assert_false(Tasks.claim_task(manager_task, _workers[1]), "only one worker reserves a request")
	Tasks.complete_task(manager_task, dale)
	var own := _assignment(dale)
	Tasks.complete_task(own, dale)
	manager_task = Tasks.add_manager_task(_station(), 60.0)
	assert_eq(dale.choose_task(), manager_task, "continues helping after personal work is done")
	assert_true(Tasks.claim_task(manager_task, dale))


func test_abduction_transfers_unfinished_assignment_to_player() -> void:
	var dale := _workers[0]
	var task := _assignment(dale)
	dale._tick_choose(4.0)
	assert_eq(task.claimed_by, dale)
	dale.abduct()
	assert_eq(task.claimed_by, null)
	assert_eq(task.assigned_to, &"YOU")
	assert_true(Tasks.claim_task(task, _player))
	Tasks.complete_task(task, _player)
	assert_true(task.completed, "the missing worker cannot block shift completion")


func test_removing_a_worker_releases_their_assignment() -> void:
	var task := _assignment(_workers[1])
	_workers[1].free()
	assert_eq(task.assigned_to, &"YOU")
	assert_true(Tasks.claim_task(task, _player))


func test_reset_creates_fresh_assignments_and_clears_completions() -> void:
	var old_task := _assignment(_workers[0])
	Tasks.complete_task(old_task, _workers[0])
	Tasks.reset()
	Tasks.begin_night()
	assert_eq(Tasks.get_coworker_basic_completions(), 0)
	for worker in _workers:
		var task := _assignment(worker)
		assert_true(task != null and task != old_task and task.is_open())
