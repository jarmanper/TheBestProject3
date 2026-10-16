# File 3: TheBestProject3/systems/monster/mimic_manager.gd
class_name MimicManager
extends Node

@export var max_active_mimics: int = 5

var registered_props: Array[InteractableMimic] = []
var active_monsters: Array[Node3D] = []

func _ready() -> void:
	if Events.has_signal("mimic_revealed"):
		Events.mimic_revealed.connect(_on_mimic_revealed)
	_scan_scene_for_mimics()

func _scan_scene_for_mimics() -> void:
	registered_props.clear()
	var nodes := get_tree().get_nodes_in_group("interactable_mimic")
	for node in nodes:
		if node is InteractableMimic:
			register_mimic(node as InteractableMimic)

func register_mimic(prop: InteractableMimic) -> void:
	if not registered_props.has(prop):
		registered_props.append(prop)
		if not prop.revealed.is_connected(_on_prop_revealed):
			prop.revealed.connect(_on_prop_revealed)

func _on_prop_revealed(monster_instance: Node3D) -> void:
	if monster_instance and not active_monsters.has(monster_instance):
		active_monsters.append(monster_instance)
		monster_instance.tree_exited.connect(func(): active_monsters.erase(monster_instance))

func _on_mimic_revealed(_pos: Vector3) -> void:
	active_monsters = active_monsters.filter(func(m): return is_instance_valid(m))
