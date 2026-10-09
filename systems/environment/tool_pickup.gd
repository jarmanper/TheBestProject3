class_name ToolPickup
extends Interactable
## A rack/hook holding one tool. Taking it gives the player the tool; the tool
## the player was holding goes back to its own rack.

@export var tool_id: StringName = &""

var has_tool := true


func _ready() -> void:
	super()
	add_to_group(&"tool_pickup")
	_update_visual()


func get_prompt(_player: Node) -> String:
	if not has_tool:
		return ""
	return "Take %s" % Catalog.tool_name(tool_id)


func can_interact(_player: Node) -> bool:
	return has_tool


func interact(player: Node) -> void:
	if not has_tool:
		return
	var previous: StringName = player.held_tool
	if previous != &"" and previous != tool_id:
		var tree := get_tree()
		if tree:
			var previous_rack := ToolPickup.find_rack(tree, previous)
			if previous_rack:
				previous_rack.return_tool()
	player.set_held_tool(tool_id)
	has_tool = false
	_update_visual()
	Sfx.play_at(&"tool_pickup", global_position)


## Puts the tool back on this rack (used when a consumed tool is spent or swapped).
func return_tool() -> void:
	has_tool = true
	_update_visual()


func _update_visual() -> void:
	var tool_mesh := get_node_or_null(^"Tool")
	if tool_mesh:
		tool_mesh.visible = has_tool


static func find_rack(tree: SceneTree, id: StringName) -> ToolPickup:
	for rack: ToolPickup in tree.get_nodes_in_group(&"tool_pickup"):
		if rack.tool_id == id:
			return rack
	return null
