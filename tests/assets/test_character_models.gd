extends TestCase
## Character models (task 1): every contract GLB exists, instantiates, has an AnimationPlayer with the
## contract clips (looping ones loop), a Skeleton3D with the contract bones, a sane height with the
## feet on the floor, faces +Z (model front), and nearest-filtered materials.

const HUMAN_BONES: Array[String] = [
	"root", "hips", "spine", "chest", "neck", "head",
	"upper_arm.L", "forearm.L", "hand.L", "upper_arm.R", "forearm.R", "hand.R",
	"thigh.L", "shin.L", "foot.L", "thigh.R", "shin.R", "foot.R",
]
const MONSTER_EXTRA_BONES: Array[String] = ["ear.L", "ear.R", "jaw"]

## clip name -> [loops, length in seconds]
const EMPLOYEE_CLIPS := {
	&"idle": [true, 2.0], &"walk": [true, 1.0], &"run": [true, 0.6], &"work": [true, 1.5],
}
const MANAGER_CLIPS := {&"idle": [true, 2.5], &"talk": [true, 2.0], &"walk": [true, 1.1]}
const MONSTER_CLIPS := {
	&"idle": [true, 2.4], &"walk": [true, 1.4], &"run": [true, 0.7],
	&"attack": [false, 0.8], &"reveal": [false, 1.5],
}


func test_employee_models() -> void:
	assert_eq(Catalog.COWORKERS.size(), 3, "three coworkers")
	for coworker: Dictionary in Catalog.COWORKERS:
		await _check_model(coworker["model"], EMPLOYEE_CLIPS, HUMAN_BONES, 1.70, 1.90)


func test_manager_model() -> void:
	await _check_model(Catalog.MODEL_MANAGER, MANAGER_CLIPS, HUMAN_BONES, 1.70, 1.90)


func test_monster_model() -> void:
	var bones: Array[String] = HUMAN_BONES.duplicate()
	bones.append_array(MONSTER_EXTRA_BONES)
	await _check_model(Catalog.MODEL_MONSTER, MONSTER_CLIPS, bones, 2.50, 2.70)


func test_contract_animation_names_match_catalog() -> void:
	var names: Array[StringName] = [Catalog.ANIM_IDLE, Catalog.ANIM_WALK, Catalog.ANIM_RUN, Catalog.ANIM_WORK]
	for clip in names:
		assert_true(EMPLOYEE_CLIPS.has(clip), "employee clip %s" % clip)
	assert_true(MANAGER_CLIPS.has(Catalog.ANIM_TALK), "manager talk clip")
	assert_true(MONSTER_CLIPS.has(Catalog.ANIM_ATTACK), "monster attack clip")
	assert_true(MONSTER_CLIPS.has(Catalog.ANIM_REVEAL), "monster reveal clip")


func _check_model(path: String, clips: Dictionary, bones: Array[String], min_height: float,
		max_height: float) -> void:
	var tag := path.get_file()
	assert_true(ResourceLoader.exists(path), "%s exists" % tag)
	if not ResourceLoader.exists(path):
		return
	var scene := load(path) as PackedScene
	assert_true(scene != null, "%s loads as a PackedScene" % tag)
	if scene == null:
		return
	var model := scene.instantiate() as Node3D
	assert_true(model != null, "%s instantiates as Node3D" % tag)
	if model == null:
		return
	tree.root.add_child(model)
	await wait_frames(1)

	var player := _find_first(model, "AnimationPlayer") as AnimationPlayer
	assert_true(player != null, "%s has an AnimationPlayer" % tag)
	if player != null:
		for clip: StringName in clips:
			var expected: Array = clips[clip]
			assert_true(player.has_animation(clip), "%s has animation '%s'" % [tag, clip])
			if not player.has_animation(clip):
				continue
			var animation := player.get_animation(clip)
			assert_eq(animation.loop_mode != Animation.LOOP_NONE, expected[0], "%s '%s' looping" % [tag, clip])
			assert_near(animation.length, expected[1], 0.05, "%s '%s' length" % [tag, clip])

	var skeleton := _find_first(model, "Skeleton3D") as Skeleton3D
	assert_true(skeleton != null, "%s has a Skeleton3D" % tag)
	if skeleton != null:
		for bone in bones:
			assert_true(skeleton.find_bone(bone) >= 0, "%s has bone '%s'" % [tag, bone])

	var bounds := _model_bounds(model)
	assert_true(bounds.size.y >= min_height and bounds.size.y <= max_height,
		"%s height %.3f within [%.2f, %.2f]" % [tag, bounds.size.y, min_height, max_height])
	assert_near(bounds.position.y, 0.0, 0.03, "%s feet on the floor (min y)" % tag)
	assert_true(absf(bounds.get_center().x) < 0.1, "%s centred on x" % tag)
	# Faces +Z (model front): near the floor the toes reach further toward +Z than the heels do toward -Z.
	var feet := _floor_vertex_z_range(model, 0.06)
	assert_true(feet.y > -feet.x + 0.03, "%s faces +Z (feet z range %s)" % [tag, feet])
	_check_nearest_materials(model, tag)

	model.queue_free()
	await wait_frames(1)


func _check_nearest_materials(model: Node, tag: String) -> void:
	var checked := 0
	for node in _find_all(model, "MeshInstance3D"):
		var mesh_instance := node as MeshInstance3D
		for surface in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_active_material(surface) as BaseMaterial3D
			if material == null:
				continue
			checked += 1
			assert_true(material.albedo_texture != null, "%s surface %d has an albedo texture" % [tag, surface])
			var filter := material.texture_filter
			assert_true(filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST
				or filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS,
				"%s surface %d uses nearest filtering (got %d)" % [tag, surface, filter])
	assert_true(checked > 0, "%s has at least one material" % tag)


func _model_bounds(model: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for node in _find_all(model, "MeshInstance3D"):
		var mesh_instance := node as MeshInstance3D
		var box := mesh_instance.global_transform * mesh_instance.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds


## (min z, max z) of all rest-pose vertices lower than `max_y` (world space).
func _floor_vertex_z_range(model: Node3D, max_y: float) -> Vector2:
	var z_range := Vector2(INF, -INF)
	for node in _find_all(model, "MeshInstance3D"):
		var mesh_instance := node as MeshInstance3D
		for surface in mesh_instance.mesh.get_surface_count():
			var vertices: PackedVector3Array = mesh_instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var world := mesh_instance.global_transform * vertex
				if world.y < max_y:
					z_range.x = minf(z_range.x, world.z)
					z_range.y = maxf(z_range.y, world.z)
	return z_range


func _find_first(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find_first(child, type_name)
		if found != null:
			return found
	return null


func _find_all(node: Node, type_name: String) -> Array[Node]:
	var found: Array[Node] = []
	if node.is_class(type_name):
		found.append(node)
	for child in node.get_children():
		found.append_array(_find_all(child, type_name))
	return found
