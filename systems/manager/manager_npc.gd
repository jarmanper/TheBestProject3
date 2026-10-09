class_name ManagerNpc
extends CharacterBody3D
## The store manager's NPC body: idles at `manager_spot` and offers small talk
## through its "Talk" interactable child.

@onready var _model_holder: Node3D = get_node_or_null(^"Model")

var _anim: AnimationPlayer


func _ready() -> void:
	add_to_group(&"employee")
	collision_layer = Catalog.LAYER_NPC
	collision_mask = Catalog.LAYER_WORLD
	_load_model()
	_play_idle()


func talk() -> void:
	if _anim and _anim.has_animation(Catalog.ANIM_TALK):
		_anim.play(Catalog.ANIM_TALK)
	Events.subtitle.emit(ManagerLines.TALK.pick_random(), 3.0)


func _load_model() -> void:
	if _model_holder == null:
		return
	if ResourceLoader.exists(Catalog.MODEL_MANAGER):
		var scene := load(Catalog.MODEL_MANAGER) as PackedScene
		if scene:
			_model_holder.add_child(scene.instantiate())
			_anim = _model_holder.find_child("AnimationPlayer", true, false) as AnimationPlayer
			return
		push_warning("Could not load manager model: %s" % Catalog.MODEL_MANAGER)
	else:
		push_warning("Missing manager model: %s" % Catalog.MODEL_MANAGER)
	_add_fallback_capsule(_model_holder)


func _add_fallback_capsule(parent: Node3D) -> void:
	var mesh_instance := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	mesh_instance.mesh = capsule
	mesh_instance.position.y = capsule.height * 0.5
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.35, 0.75)  ## blue work shirt placeholder
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)


func _play_idle() -> void:
	if _anim and _anim.has_animation(Catalog.ANIM_IDLE):
		_anim.play(Catalog.ANIM_IDLE)
