class_name PropPlaceholder
extends Node3D
## Loads a prop model by its contract path (one of Task 3's GLBs). Shows a
## simple coloured BoxMesh instead when the file does not exist yet, so scenes
## work before the art lands and pick it up automatically once it does.

@export var model_path := ""              ## "" = always use the fallback box, no warning
@export var fallback_size := Vector3(0.5, 0.5, 0.5)
@export var fallback_color := Catalog.COLOR_OLIVE
@export var fallback_lift := true          ## true = sit the box on the floor (local y = 0)


func _ready() -> void:
	if not model_path.is_empty():
		if ResourceLoader.exists(model_path):
			var scene := load(model_path) as PackedScene
			if scene:
				add_child(scene.instantiate())
				return
		push_warning("Missing prop model: %s" % model_path)
	_add_fallback_box()


func _add_fallback_box() -> void:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = fallback_size
	mesh_instance.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = fallback_color
	mesh_instance.material_override = material
	if fallback_lift:
		mesh_instance.position.y = fallback_size.y * 0.5
	add_child(mesh_instance)
