extends TestCase

var _mop_rack: ToolPickup
var _price_rack: ToolPickup
var _player: Player


func before_each() -> void:
	_mop_rack = ToolPickup.new()
	_mop_rack.tool_id = &"mop"
	tree.root.add_child(_mop_rack)
	_price_rack = ToolPickup.new()
	_price_rack.tool_id = &"price_gun"
	tree.root.add_child(_price_rack)
	_player = Player.new()
	tree.root.add_child(_player)


func after_each() -> void:
	_mop_rack.free()
	_price_rack.free()
	_player.free()


func test_prompt_offers_to_take_the_tool() -> void:
	assert_eq(_mop_rack.get_prompt(_player), "Take Mop")


func test_taking_a_tool_arms_the_player_and_hides_the_rack() -> void:
	var tool_mesh := Node3D.new()
	tool_mesh.name = "Tool"
	_mop_rack.add_child(tool_mesh)
	_mop_rack.interact(_player)
	assert_eq(_player.held_tool, &"mop")
	assert_false(_mop_rack.has_tool)
	assert_false(tool_mesh.visible)
	assert_eq(_mop_rack.get_prompt(_player), "")
	assert_false(_mop_rack.can_interact(_player))


func test_taking_a_new_tool_returns_the_previous_one_to_its_rack() -> void:
	_mop_rack.interact(_player)
	assert_eq(_player.held_tool, &"mop")
	_price_rack.interact(_player)
	assert_eq(_player.held_tool, &"price_gun")
	assert_true(_mop_rack.has_tool, "the mop should have gone back to its rack")


func test_return_tool_makes_it_available_again() -> void:
	_mop_rack.interact(_player)
	_mop_rack.return_tool()
	assert_true(_mop_rack.has_tool)
	assert_eq(_mop_rack.get_prompt(_player), "Take Mop")


func test_find_rack_locates_a_rack_by_tool_id() -> void:
	var found := ToolPickup.find_rack(tree, &"price_gun")
	assert_true(found == _price_rack)
