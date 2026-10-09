class_name ToolPickup
extends Interactable
## A rack/hook holding one tool. Taking it gives the player the tool; the tool
## the player was holding goes back to its own rack.
## STUB — public API only. The Store Environment task replaces the bodies.

@export var tool_id: StringName = &""

var has_tool := true


func _ready() -> void:
	super()
	add_to_group(&"tool_pickup")


## Puts the tool back on this rack (used when a consumed tool is spent or swapped).
func return_tool() -> void:
	has_tool = true


static func find_rack(tree: SceneTree, id: StringName) -> ToolPickup:
	for rack: ToolPickup in tree.get_nodes_in_group(&"tool_pickup"):
		if rack.tool_id == id:
			return rack
	return null
