class_name PlayerViewmodel
extends Node3D
## The thing in the player's hands (flashlight when empty-handed, else the held tool).
## Loads Catalog.tool_viewmodel_path(id); the GLBs are posed for a camera looking down -Z,
## so the model sits at this node's origin. Missing files fall back to a box.

## Render layer 20: the player's own flashlight excludes it (it sits right behind the hands
## and would blow them out); store lights and ambient still light the viewmodel.
const RENDER_LAYER := 1 << 19
const SWAY_AMOUNT := 0.00035     ## metres per pixel of mouse motion
const SWAY_MAX := 0.035
const SWAY_RETURN := 8.0
const BOB_SCALE := 0.6           ## fraction of the camera bob the hands follow

var current_id: StringName = &"__none__"
var _model: Node3D
var _sway := Vector2.ZERO
var _bob := Vector3.ZERO


## Shows the viewmodel for `tool_id` (&"" = flashlight).
func show_tool(tool_id: StringName) -> void:
	var id := tool_id if tool_id != &"" else &"flashlight"
	if id == current_id and is_instance_valid(_model):
		return
	current_id = id
	if is_instance_valid(_model):
		_model.queue_free()
	_model = _load_model(id)
	_model.name = "Model"
	add_child(_model)
	_prepare_geometry(_model)


func add_sway(mouse_relative: Vector2) -> void:
	_sway -= mouse_relative * SWAY_AMOUNT
	_sway = _sway.limit_length(SWAY_MAX)


## Called every frame by the player with the camera bob offset.
func update_motion(delta: float, camera_bob: Vector3) -> void:
	_sway = _sway.lerp(Vector2.ZERO, clampf(SWAY_RETURN * delta, 0.0, 1.0))
	_bob = _bob.lerp(camera_bob * BOB_SCALE, clampf(12.0 * delta, 0.0, 1.0))
	position = Vector3(_sway.x - _bob.x, _sway.y - _bob.y * 0.5, 0.0)
	rotation = Vector3(_sway.y * 1.5, _sway.x * 1.5, 0.0)


func _load_model(id: StringName) -> Node3D:
	var path := Catalog.tool_viewmodel_path(id)
	var scene := Catalog.load_scene_or_null(path)
	if scene:
		var instance := scene.instantiate() as Node3D
		if instance:
			return instance
	return _placeholder(id)


## Simple box stand-ins, coloured per tool, lower right of the view (stock box centred).
static func _placeholder(id: StringName) -> Node3D:
	var root := Node3D.new()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.roughness = 0.8
	match id:
		&"flashlight":
			box.size = Vector3(0.05, 0.05, 0.24)
			mesh.position = Vector3(0.2, -0.2, -0.36)
			material.albedo_color = Color(0.08, 0.08, 0.08)
		&"stock_box":
			box.size = Vector3(0.42, 0.28, 0.3)
			mesh.position = Vector3(0.0, -0.36, -0.55)
			material.albedo_color = Color(0.55, 0.42, 0.27)
		&"mop":
			box.size = Vector3(0.035, 0.035, 0.9)
			mesh.position = Vector3(0.24, -0.3, -0.55)
			mesh.rotation_degrees = Vector3(-25, 0, 0)
			material.albedo_color = Catalog.COLOR_CREAM.darkened(0.3)
		_:
			box.size = Vector3(0.09, 0.12, 0.16)
			mesh.position = Vector3(0.22, -0.22, -0.4)
			material.albedo_color = Catalog.COLOR_OLIVE
	box.material = material
	mesh.mesh = box
	mesh.name = "Placeholder"
	root.add_child(mesh)
	return root


## No shadows from the hands, and put them on RENDER_LAYER.
static func _prepare_geometry(node: Node) -> void:
	if node is GeometryInstance3D:
		var geometry := node as GeometryInstance3D
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		geometry.layers = RENDER_LAYER
	for child in node.get_children():
		_prepare_geometry(child)
