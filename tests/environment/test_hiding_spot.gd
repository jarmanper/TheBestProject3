extends TestCase

const PlayerHelper := preload("res://tests/helpers/player_helper.gd")

var _spot: HidingSpot
var _player: Player


func before_each() -> void:
	_spot = HidingSpot.new()
	_spot.spot_kind = &"counter"
	tree.root.add_child(_spot)
	_player = PlayerHelper.make_player(tree)


func after_each() -> void:
	_spot.free()
	_player.free()


func test_prompt_is_hide_when_empty() -> void:
	assert_eq(_spot.get_prompt(_player), "Hide")
	assert_true(_spot.can_interact(_player))


func test_interact_enters_hiding() -> void:
	_spot.interact(_player)
	assert_true(_player.is_hidden)
	assert_true(_player.current_hiding_spot == _spot)
	assert_true(_spot.is_occupied())
	assert_eq(_spot.occupant, _player)


func test_interact_again_exits_hiding() -> void:
	_spot.interact(_player)
	_spot.interact(_player)
	assert_false(_player.is_hidden)
	assert_false(_spot.is_occupied())


func test_occupied_spot_blocks_a_different_player() -> void:
	_spot.interact(_player)
	var other := PlayerHelper.make_player(tree)
	assert_false(_spot.can_interact(other))
	assert_eq(_spot.get_prompt(other), "")
	other.free()


func test_pull_out_occupant_forces_them_out() -> void:
	_spot.interact(_player)
	_spot.pull_out_occupant()
	assert_false(_player.is_hidden)
	assert_false(_spot.is_occupied())


func test_locker_hides_without_erroring_and_animates_its_door() -> void:
	var locker := HidingSpot.new()
	locker.spot_kind = &"locker"
	var door := Node3D.new()
	door.name = "Door"
	locker.add_child(door)
	tree.root.add_child(locker)
	locker.interact(_player)
	assert_true(_player.is_hidden)
	locker.free()
