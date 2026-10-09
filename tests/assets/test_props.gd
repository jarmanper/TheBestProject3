extends TestCase
## Task 3 assets: props, tool pickups, first-person viewmodels and HUD icons.
## Checks that every file exists and loads, the node names other systems toggle (`Door`, `Tool`,
## `LightPoint`), the origin/orientation rules in docs/ARCHITECTURE.md ("Model orientation and
## scale": model front = Godot +Z, floor props on the floor centre, wall props on the wall-contact
## centre), viewmodel placement for a FOV 95° camera looking down -Z, budgets and pixel filtering.

const PROPS_DIR := "res://assets/models/props/"
const VIEWMODELS_DIR := "res://assets/models/viewmodels/"
const ICONS_DIR := "res://assets/ui/icons/"

## Origin at the floor centre of the footprint (lowest point at y = 0).
const FLOOR_PROPS := [
	"locker", "box_pile_hide", "pickup_price_gun", "pickup_stock_box",
	"spill_decal", "wet_floor_sign", "trash_bag", "flattened_boxes", "messy_products",
	"shopping_cart", "cardboard_box_a", "cardboard_box_b", "cardboard_box_c", "pallet",
	"pallet_boxes", "mop_bucket", "trash_bin", "baler", "break_table", "chair",
	"vending_machine", "manager_desk", "crt_monitor", "office_chair", "intercom_mic",
	"walkie_talkie", "sink", "newspaper_debris", "safe",
]
## Origin at the wall-contact centre: the back face lies on z = 0 and the prop extends toward +Z.
const WALL_PROPS := [
	"pickup_mop", "pickup_box_cutter", "pickup_keys", "clipboard", "breaker_sparks",
	"time_clock", "breaker_panel",
]
const DOOR_PROPS := ["locker", "breaker_panel"]
const PICKUPS := ["pickup_mop", "pickup_price_gun", "pickup_box_cutter", "pickup_stock_box", "pickup_keys"]
const EMISSIVE_PROPS := ["vending_machine", "crt_monitor", "breaker_sparks"]
const VIEWMODELS := ["vm_flashlight", "vm_mop", "vm_price_gun", "vm_box_cutter", "vm_stock_box", "vm_keys"]
const ICONS := [
	"icon_flashlight", "icon_mop", "icon_price_gun", "icon_box_cutter", "icon_stock_box",
	"icon_keys", "icon_walkie",
]

const MAX_VIEWMODEL_TRIS := 800
const MAX_PROP_TRIS := 3000
const CAMERA_FOV := 95.0
const CAMERA_ASPECT := 16.0 / 9.0
## Godot's default Camera3D near plane; nothing visible may come closer than this.
const CAMERA_NEAR := 0.05


func test_every_prop_exists_and_loads() -> void:
	for prop: String in FLOOR_PROPS + WALL_PROPS:
		var path := PROPS_DIR + prop + ".glb"
		assert_true(ResourceLoader.exists(path), "missing %s" % path)
		var root := _instance(path)
		assert_true(root != null, "%s does not instantiate" % path)
		if root == null:
			continue
		assert_true(_meshes(root).size() > 0, "%s has no MeshInstance3D" % path)
		root.free()


func test_every_viewmodel_and_icon_exists_and_loads() -> void:
	for vm: String in VIEWMODELS:
		var path := VIEWMODELS_DIR + vm + ".glb"
		assert_true(ResourceLoader.exists(path), "missing %s" % path)
		if ResourceLoader.exists(path):
			assert_true(load(path) is PackedScene, "%s is not a scene" % path)
	for icon: String in ICONS:
		var path := ICONS_DIR + icon + ".png"
		assert_true(ResourceLoader.exists(path), "missing %s" % path)
		if ResourceLoader.exists(path):
			assert_true(load(path) is Texture2D, "%s is not a texture" % path)


func test_catalog_paths_resolve_for_every_tool() -> void:
	for tool_id: StringName in Catalog.TOOLS:
		assert_true(ResourceLoader.exists(Catalog.tool_viewmodel_path(tool_id)),
				"no viewmodel for %s" % tool_id)
		assert_true(ResourceLoader.exists(Catalog.tool_icon_path(tool_id)), "no icon for %s" % tool_id)
	assert_true(ResourceLoader.exists(Catalog.tool_viewmodel_path(&"flashlight")), "no flashlight viewmodel")
	assert_true(ResourceLoader.exists(Catalog.tool_icon_path(&"flashlight")), "no flashlight icon")


func test_doors_are_named_and_hinged() -> void:
	for prop: String in DOOR_PROPS:
		var root := _instance(PROPS_DIR + prop + ".glb")
		if root == null:
			_fail("%s missing" % prop)
			continue
		var door := root.find_child("Door", true, false) as Node3D
		assert_true(door != null, "%s has no Door" % prop)
		if door != null:
			# Origin on the hinge: one vertical edge of the door geometry sits on the door origin.
			var box := _local_aabb(door)
			var edge := minf(absf(box.position.x), absf(box.end.x))
			assert_true(edge < 0.03, "%s Door origin is not on a hinge edge (nearest x %.3f)" % [prop, edge])
			assert_true(box.size.x > 0.2 and box.size.y > 0.2, "%s Door is too small %s" % [prop, box.size])
			# The door is on the front (+Z) of the prop.
			var door_pos := root.global_transform.affine_inverse() * door.global_position
			assert_true(door_pos.z > 0.0, "%s Door is not on the +Z front (z %.3f)" % [prop, door_pos.z])
		root.free()


func test_locker_dimensions() -> void:
	var root := _instance(PROPS_DIR + "locker.glb")
	if root == null:
		_fail("locker missing")
		return
	var box := _scene_aabb(root)
	assert_near(box.size.x, 0.5, 0.06, "locker width")
	assert_near(box.size.y, 1.9, 0.06, "locker height")
	assert_near(box.size.z, 0.5, 0.08, "locker depth")
	root.free()


func test_pickups_have_tool_child() -> void:
	for prop: String in PICKUPS:
		var root := _instance(PROPS_DIR + prop + ".glb")
		if root == null:
			_fail("%s missing" % prop)
			continue
		var tool := root.find_child("Tool", true, false) as Node3D
		assert_true(tool != null, "%s has no Tool" % prop)
		if tool != null:
			assert_true(_meshes(tool).size() > 0, "%s Tool has no mesh" % prop)
			# Hiding the Tool (tool taken) must leave the rack/hook/tray visible.
			var rest := 0
			for mesh: MeshInstance3D in _meshes(root):
				if mesh != tool and not tool.is_ancestor_of(mesh):
					rest += 1
			assert_true(rest > 0, "%s has nothing besides the Tool" % prop)
		root.free()


func test_floor_props_stand_on_floor_centre() -> void:
	for prop: String in FLOOR_PROPS:
		var root := _instance(PROPS_DIR + prop + ".glb")
		if root == null:
			_fail("%s missing" % prop)
			continue
		var box := _scene_aabb(root)
		var centre := box.get_center()
		assert_true(box.position.y > -0.01 and box.position.y < 0.03,
				"%s lowest point y %.3f is not on the floor" % [prop, box.position.y])
		assert_true(absf(centre.x) <= 0.25 * box.size.x + 0.03,
				"%s footprint not centred on x (%.3f)" % [prop, centre.x])
		assert_true(absf(centre.z) <= 0.25 * box.size.z + 0.03,
				"%s footprint not centred on z (%.3f)" % [prop, centre.z])
		root.free()


func test_wall_props_back_on_wall_plane() -> void:
	for prop: String in WALL_PROPS:
		var root := _instance(PROPS_DIR + prop + ".glb")
		if root == null:
			_fail("%s missing" % prop)
			continue
		var box := _scene_aabb(root)
		assert_true(absf(box.position.z) < 0.015,
				"%s back is not on the wall plane z = 0 (min z %.3f)" % [prop, box.position.z])
		assert_true(box.end.z > 0.01, "%s does not extend toward +Z" % prop)
		assert_true(absf(box.get_center().x) <= 0.25 * box.size.x + 0.03,
				"%s not centred on x (%.3f)" % [prop, box.get_center().x])
		root.free()


func test_flashlight_viewmodel_has_light_point_at_lens() -> void:
	var root := _instance(VIEWMODELS_DIR + "vm_flashlight.glb")
	if root == null:
		_fail("vm_flashlight missing")
		return
	var point := root.find_child("LightPoint", true, false) as Node3D
	assert_true(point != null, "vm_flashlight has no LightPoint")
	if point != null:
		var pos := root.global_transform.affine_inverse() * point.global_position
		assert_true(pos.z < -0.2, "LightPoint is not in front of the camera (z %.3f)" % pos.z)
		assert_true(pos.x > 0.0 and pos.y < 0.0, "LightPoint is not lower right %s" % pos)
		var forward := -point.global_basis.z.normalized()
		assert_true(forward.z < -0.9, "LightPoint -Z does not point down the view (%s)" % forward)
	root.free()


func test_viewmodels_sit_low_and_clear_the_near_plane() -> void:
	for vm: String in VIEWMODELS:
		var root := _instance(VIEWMODELS_DIR + vm + ".glb")
		if root == null:
			_fail("%s missing" % vm)
			continue
		var tris := _triangles(root)
		assert_true(tris.size() > 0, "%s has no triangles" % vm)
		assert_true(tris.size() / 3 <= MAX_VIEWMODEL_TRIS,
				"%s has %d tris (max %d)" % [vm, tris.size() / 3, MAX_VIEWMODEL_TRIS])
		var box := _scene_aabb(root)
		var centre := box.get_center()
		assert_true(centre.z < -0.15, "%s is not in front of the camera (z %.3f)" % [vm, centre.z])
		assert_true(centre.y < -0.08, "%s is not below the view centre (y %.3f)" % [vm, centre.y])
		if vm == "vm_stock_box":
			assert_true(absf(centre.x) < 0.1, "vm_stock_box is not centred (x %.3f)" % centre.x)
		else:
			assert_true(centre.x > 0.05, "%s is not on the right (x %.3f)" % [vm, centre.x])
		var cut := _near_plane_cut(tris)
		assert_true(cut.is_empty(), "%s crosses the near plane inside the view: %s" % [vm, cut])
		root.free()


func test_prop_triangle_budget() -> void:
	for prop: String in FLOOR_PROPS + WALL_PROPS:
		var root := _instance(PROPS_DIR + prop + ".glb")
		if root == null:
			_fail("%s missing" % prop)
			continue
		var count := _triangles(root).size() / 3
		assert_true(count > 0 and count <= MAX_PROP_TRIS, "%s has %d tris" % [prop, count])
		root.free()


func test_textures_are_nearest_filtered() -> void:
	var paths: Array[String] = []
	for prop: String in FLOOR_PROPS + WALL_PROPS:
		paths.append(PROPS_DIR + prop + ".glb")
	for vm: String in VIEWMODELS:
		paths.append(VIEWMODELS_DIR + vm + ".glb")
	for path in paths:
		var root := _instance(path)
		if root == null:
			_fail("%s missing" % path)
			continue
		for material in _materials(root):
			if material.albedo_texture != null:
				assert_true(material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST
						or material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS,
						"%s material %s is not nearest-filtered" % [path.get_file(), material.resource_name])
		root.free()


func test_emissive_and_transparent_materials() -> void:
	for prop: String in EMISSIVE_PROPS:
		var root := _instance(PROPS_DIR + prop + ".glb")
		if root == null:
			_fail("%s missing" % prop)
			continue
		var emissive := false
		for material in _materials(root):
			emissive = emissive or material.emission_enabled
		assert_true(emissive, "%s has no emissive material" % prop)
		root.free()
	var spill := _instance(PROPS_DIR + "spill_decal.glb")
	if spill == null:
		_fail("spill_decal missing")
		return
	var transparent := false
	for material in _materials(spill):
		transparent = transparent or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
	assert_true(transparent, "spill_decal has no transparent material")
	var box := _scene_aabb(spill)
	assert_near(box.size.x, 1.2, 0.1, "spill width")
	assert_near(box.size.z, 1.2, 0.1, "spill depth")
	spill.free()


func test_icons_are_32px_and_transparent() -> void:
	for icon: String in ICONS:
		var path := ICONS_DIR + icon + ".png"
		var texture: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
		if texture == null:
			_fail("%s missing" % path)
			continue
		assert_eq(texture.get_width(), 32, "%s width" % icon)
		assert_eq(texture.get_height(), 32, "%s height" % icon)
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		assert_true(image != null and image.detect_alpha() != Image.ALPHA_NONE, "%s has no alpha" % icon)
		if image == null:
			continue
		assert_near(image.get_pixel(0, 0).a, 0.0, 0.01, "%s corner is not transparent" % icon)
		var opaque := 0
		for y in 32:
			for x in 32:
				if image.get_pixel(x, y).a > 0.5:
					opaque += 1
		assert_true(opaque >= 60 and opaque <= 700, "%s has %d opaque pixels" % [icon, opaque])


# --- helpers ---------------------------------------------------------------

func _instance(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var node := scene.instantiate() as Node3D
	if node != null:
		tree.root.add_child(node)
	return node


func _meshes(root: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		found.append(root)
	for node in root.find_children("*", "MeshInstance3D", true, false):
		found.append(node as MeshInstance3D)
	return found


func _materials(root: Node) -> Array[BaseMaterial3D]:
	var found: Array[BaseMaterial3D] = []
	for mesh_instance in _meshes(root):
		if mesh_instance.mesh == null:
			continue
		for i in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_active_material(i) as BaseMaterial3D
			if material != null and not found.has(material):
				found.append(material)
	return found


## AABB of every mesh under `root`, in `root`'s space.
func _scene_aabb(root: Node3D) -> AABB:
	var inverse := root.global_transform.affine_inverse()
	var result := AABB()
	var first := true
	for mesh_instance in _meshes(root):
		if mesh_instance.mesh == null:
			continue
		var box := (inverse * mesh_instance.global_transform) * mesh_instance.mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


## AABB of the meshes under `node`, in `node`'s own space.
func _local_aabb(node: Node3D) -> AABB:
	return _scene_aabb(node)


## Every triangle under `root` as a flat list of vertices in `root`'s space.
func _triangles(root: Node3D) -> PackedVector3Array:
	var inverse := root.global_transform.affine_inverse()
	var result := PackedVector3Array()
	for mesh_instance in _meshes(root):
		if mesh_instance.mesh == null:
			continue
		var xf := inverse * mesh_instance.global_transform
		for vertex in mesh_instance.mesh.get_faces():
			result.append(xf * vertex)
	return result


## Returns the first triangle edge that crosses the near plane inside the view rectangle of a
## FOV 95° (vertical) 16:9 camera at the origin looking down -Z, or "" when none does.
func _near_plane_cut(tris: PackedVector3Array) -> String:
	var half_h := CAMERA_NEAR * tan(deg_to_rad(CAMERA_FOV * 0.5))
	var half_w := half_h * CAMERA_ASPECT
	for t in range(0, tris.size() - 2, 3):
		var points: Array[Vector3] = [tris[t], tris[t + 1], tris[t + 2]]
		var hits: Array[Vector2] = []
		for e in 3:
			var a := points[e]
			var b := points[(e + 1) % 3]
			var da := -a.z - CAMERA_NEAR
			var db := -b.z - CAMERA_NEAR
			if (da < 0.0) != (db < 0.0):
				var p := a.lerp(b, da / (da - db))
				hits.append(Vector2(p.x, p.y))
		if hits.size() < 2:
			continue
		for s in 9:
			var q := hits[0].lerp(hits[1], s / 8.0)
			if absf(q.x) <= half_w and absf(q.y) <= half_h:
				return "triangle near %s" % points[0]
	return ""
