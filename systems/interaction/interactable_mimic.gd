# File 1: TheBestProject3/systems/interaction/interactable_mimic.gd
class_name InteractableMimic
extends Node3D

@export_group("Mimic Setup")
@export var monster_scene: PackedScene  # Drag your existing monster scene here in Inspector
@export var trigger_distance: float = 2.5
@export var is_disguised: bool = true

signal revealed(monster_instance: Node3D)

func _ready() -> void:
	add_to_group("interactable_mimic")
	
	# Programmatically build trigger area
	var interact_area := Area3D.new()
	interact_area.collision_layer = 0
	interact_area.collision_mask = 2  # Collision layer 2 = Player
	
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(trigger_distance, trigger_distance, trigger_distance)
	col.shape = box
	interact_area.add_child(col)
	add_child(interact_area)
	
	interact_area.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if is_disguised and body.is_in_group("player"):
		reveal_monster(body)

func reveal_monster(target_player: Node3D = null) -> void:
	if not is_disguised:
		return
		
	is_disguised = false
	
	if monster_scene:
		var monster_instance := monster_scene.instantiate() as Node3D
		get_parent().add_child(monster_instance)
		monster_instance.global_transform = global_transform
		
		# Target player and alert existing monster if methods exist
		if "target_player" in monster_instance:
			monster_instance.target_player = target_player
		if monster_instance.has_method("set_state"):
			monster_instance.set_state(2)  # Set to CHARGE / ALERT state
			
		revealed.emit(monster_instance)
		if Events.has_signal("mimic_revealed"):
			Events.mimic_revealed.emit(global_position)
	
	queue_free()