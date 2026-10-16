# File 2: TheBestProject3/systems/interaction/interactable_mimic.gd
class_name InteractableMimic
extends Node3D

@export var is_disguised: bool = true

func _ready() -> void:
	# Programmatically create trigger area for player interaction
	var interact_area := Area3D.new()
	interact_area.collision_layer = 0
	interact_area.collision_mask = 2
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.0, 2.0)
	col.shape = box
	interact_area.add_child(col)
	add_child(interact_area)
	interact_area.body_entered.connect(func(body): if is_disguised and body.is_in_group("player"): reveal_mimic(body))

func reveal_mimic(target: Node3D = null) -> void:
	is_disguised = false
	var mimic := CharacterBody3D.new()
	mimic.set_script(preload("res://systems/monster/mimic_monster.gd"))
	
	# Visual mesh for the spawned monster
	var mesh_inst := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	mesh_inst.mesh = capsule
	mimic.add_child(mesh_inst)

	var col_inst := CollisionShape3D.new()
	var cap_shape := CapsuleShape3D.new()
	col_inst.shape = cap_shape
	mimic.add_child(col_inst)

	get_parent().add_child(mimic)
	mimic.global_transform = global_transform
	
	if target:
		mimic.target_player = target
		mimic.set_state(mimic.State.CHARGE)

	queue_free()