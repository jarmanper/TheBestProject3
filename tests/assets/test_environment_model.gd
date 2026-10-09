extends TestCase
## Checks the exported store environment (assets/models/environment/store_interior.glb) against
## docs/ARCHITECTURE.md section 7: anchors, collisions, floor height, shelf rows, door openings, cavities.

const STORE_PATH := "res://assets/models/environment/store_interior.glb"
const KIT_DIR := "res://assets/models/environment/kit/"
const KIT_PIECES := [
	"gondola_cereal", "gondola_snacks", "gondola_drinks", "gondola_canned", "gondola_baking", "gondola_endcap",
	"wall_cooler", "freezer", "checkout_counter", "service_desk", "produce_table", "produce_wall_rack",
	"industrial_shelf", "industrial_shelf_empty", "fluorescent_fixture", "fluorescent_fixture_broken",
	"fluorescent_fixture_short", "sign_aisle_1", "sign_aisle_2", "sign_aisle_3", "sign_aisle_4", "sign_dairy",
	"sign_frozen", "sign_produce", "sign_customer_service", "sign_employees_only", "sign_exit",
	"emergency_light", "emergency_door", "pallet_boxes_static",
]
const ROWS_X := [-16.0, -12.0, -8.0, -4.0, 0.0]
const AISLE_X := [-14.0, -10.0, -6.0, -2.0]
## Door openings from ARCHITECTURE section 7: [x0, x1, wall z]. All open (no leaves).
const OPENINGS := [
	[6.0, 8.4, -6.0],     # employees-only double doorway, sales floor -> back hallway
	[-6.0, -4.4, -9.0],   # storage
	[5.0, 6.2, -9.0],     # break room
	[12.0, 13.2, -9.0],   # office
	[17.5, 18.7, -9.0],   # janitor closet
]

var _store: Node3D


func before_each() -> void:
	var scene := load(STORE_PATH) as PackedScene
	if scene != null:
		_store = scene.instantiate() as Node3D
		tree.root.add_child(_store)
		await wait_physics_frames(3)


func after_each() -> void:
	if _store != null:
		_store.free()
		_store = null
	await wait_frames(1)


func test_glb_loads_as_scene() -> void:
	assert_true(ResourceLoader.exists(STORE_PATH), "store_interior.glb is imported")
	assert_true(_store != null, "store_interior.glb instantiates to a Node3D")


func test_has_light_anchors_with_fixtures() -> void:
	if _store == null:
		_fail("store missing")
		return
	var anchors := _find(_store, func(n: Node) -> bool: return String(n.name).begins_with("LightAnchor_"))
	assert_true(anchors.size() >= 25, "at least 25 LightAnchor_* nodes (got %d)" % anchors.size())
	var broken := 0
	for a in anchors:
		var num := String(a.name).trim_prefix("LightAnchor_")
		var fixture := _store.find_child("Fixture_%s" % num, true, false)
		if fixture == null:
			fixture = _store.find_child("Fixture_%s_broken" % num, true, false)
			broken += 1
		assert_true(fixture is MeshInstance3D, "fixture for %s" % a.name)
		if fixture is MeshInstance3D:
			assert_true(_has_material(fixture as MeshInstance3D, "FluorescentTube"), "%s has a FluorescentTube surface" % fixture.name)
			var below := (a as Node3D).global_position.y < (fixture as Node3D).global_position.y
			assert_true(below, "%s hangs just under its fixture" % a.name)
	var ratio := float(broken) / maxf(1.0, float(anchors.size()))
	assert_true(ratio > 0.08 and ratio < 0.22, "about 15%% of fixtures are broken (got %.2f)" % ratio)


func test_has_static_collisions() -> void:
	if _store == null:
		_fail("store missing")
		return
	var bodies := _find(_store, func(n: Node) -> bool: return n is StaticBody3D)
	assert_true(bodies.size() >= 6, "several StaticBody3D collision groups (got %d)" % bodies.size())
	for b in bodies:
		assert_eq((b as StaticBody3D).collision_layer & Catalog.LAYER_WORLD, Catalog.LAYER_WORLD, "%s on the world layer" % b.name)


func test_floor_is_hit_at_y0_at_zone_centres() -> void:
	if _store == null:
		_fail("store missing")
		return
	var points: Array[Vector2] = []
	for x in AISLE_X:
		for z in [-1.0, 2.0, 5.0]:
			points.append(Vector2(x, z))
	points.append_array([Vector2(-17.9, 2.0), Vector2(-10.0, -4.2), Vector2(-9.5, 8.5), Vector2(11.0, 0.0),
		Vector2(12.0, 10.5), Vector2(0.0, -7.5), Vector2(-12.0, -13.0), Vector2(6.0, -12.5), Vector2(13.0, -12.5),
		Vector2(18.0, -12.5), Vector2(-18.0, -15.0)])
	for p in points:
		var hit := _ray(Vector3(p.x, 2.9, p.y), Vector3(p.x, -1.0, p.y))
		assert_false(hit.is_empty(), "floor under %s" % p)
		if not hit.is_empty():
			assert_near((hit.position as Vector3).y, 0.0, 0.02, "floor height at %s" % p)


func test_shelf_rows_block_rays_across() -> void:
	if _store == null:
		_fail("store missing")
		return
	for x in ROWS_X:
		for z in [-2.5, 0.0, 2.0, 4.0, 6.5]:
			for y in [0.3, 1.0, 1.8]:
				var hit := _ray(Vector3(x - 1.3, y, z), Vector3(x + 1.3, y, z))
				assert_false(hit.is_empty(), "row x=%s blocks at z=%s y=%s" % [x, z, y])
				if not hit.is_empty():
					assert_near((hit.position as Vector3).x, x - 0.6, 0.05, "row x=%s face" % x)


func test_door_openings_are_passable() -> void:
	if _store == null:
		_fail("store missing")
		return
	for o in OPENINGS:
		var x0: float = o[0]
		var x1: float = o[1]
		var wz: float = o[2]
		for t in [0.15, 0.5, 0.85]:
			var x := lerpf(x0, x1, t)
			for y in [0.3, 1.0, 1.9]:
				var hit := _ray(Vector3(x, y, wz + 0.9), Vector3(x, y, wz - 0.9))
				assert_true(hit.is_empty(), "opening %s..%s in wall z=%s passable at x=%.2f y=%s" % [x0, x1, wz, x, y])
		# the wall right beside the opening is solid
		for x in [x0 - 0.4, x1 + 0.4]:
			var side := _ray(Vector3(x, 1.0, wz + 0.9), Vector3(x, 1.0, wz - 0.9))
			assert_false(side.is_empty(), "wall z=%s solid beside the opening at x=%.2f" % [wz, x])


func test_closed_doors_and_exterior_walls_block() -> void:
	if _store == null:
		_fail("store missing")
		return
	var rays := {
		"entrance doors": [Vector3(0.0, 1.0, 15.0), Vector3(0.0, 1.0, 17.5)],
		"front windows": [Vector3(-10.0, 1.5, 15.0), Vector3(-10.0, 1.5, 17.5)],
		"emergency door": [Vector3(-19.0, 1.0, -13.0), Vector3(-21.0, 1.0, -13.0)],
		"east wall": [Vector3(19.5, 1.0, 12.0), Vector3(21.5, 1.0, 12.0)],
		"back wall": [Vector3(0.0, 1.0, -15.0), Vector3(0.0, 1.0, -17.5)],
		"west wall": [Vector3(-19.5, 1.0, 12.0), Vector3(-21.5, 1.0, 12.0)],
	}
	for key in rays:
		var hit := _ray(rays[key][0], rays[key][1])
		assert_false(hit.is_empty(), "%s blocks" % key)


func test_counter_cavities_leave_crouch_space() -> void:
	if _store == null:
		_fail("store missing")
		return
	for cx in [-12.0, -7.0, -2.0]:
		# into the cavity from the cashier side (+x): open for ~0.8 m, then the back panel
		var hit := _ray(Vector3(cx + 1.5, 0.45, 11.8), Vector3(cx - 1.5, 0.45, 11.8))
		assert_false(hit.is_empty(), "checkout x=%s has a back panel" % cx)
		if not hit.is_empty():
			assert_near((hit.position as Vector3).x, cx - 0.35, 0.05, "checkout x=%s cavity depth" % cx)
		var top := _ray(Vector3(cx + 1.5, 0.95, 11.8), Vector3(cx - 1.5, 0.95, 11.8))
		assert_false(top.is_empty(), "checkout x=%s counter top above the cavity" % cx)
		var up := _ray(Vector3(cx, 0.1, 11.8), Vector3(cx, 0.85, 11.8))
		assert_true(up.is_empty(), "checkout x=%s cavity is 0.85+ m high" % cx)
	var desk := _ray(Vector3(10.6, 0.45, 13.8), Vector3(10.6, 0.45, 11.0))
	assert_false(desk.is_empty(), "service desk cavity back panel")
	if not desk.is_empty():
		assert_near((desk.position as Vector3).z, 12.1, 0.05, "service desk cavity depth")


func test_named_landmarks_exist() -> void:
	if _store == null:
		_fail("store missing")
		return
	for n in ["Sign_Aisle_1", "Sign_Aisle_2", "Sign_Aisle_3", "Sign_Aisle_4", "Sign_Dairy", "Sign_Frozen", "Sign_Produce",
			"Sign_CustomerService", "Sign_EmployeesOnly", "Sign_Exit", "EmergencyDoor", "EntranceDoors", "BreakerPanel_Static",
			"ServiceDesk", "Checkout_1", "Checkout_2", "Checkout_3", "ExitAnchor"]:
		assert_true(_store.find_child(n, true, false) != null, "%s exists" % n)
	var sign := _store.find_child("Sign_Aisle_4", true, false) as Node3D
	if sign != null:
		assert_true(sign.global_position.is_equal_approx(Vector3(-2.0, 3.3, 2.0)), "AISLE 4 sign at (-2, 3.3, 2)")
	var dairy := _store.find_child("Sign_Dairy", true, false) as Node3D
	if dairy != null:
		assert_true(dairy.global_position.is_equal_approx(Vector3(-2.0, 3.0, -5.4)), "DAIRY sign at (-2, 3.0, -5.4)")
	var panel := _store.find_child("BreakerPanel_Static", true, false) as Node3D
	if panel != null:
		assert_true(panel.global_position.distance_to(Vector3(0.0, 1.5, -8.9)) < 0.01, "breaker panel on the hallway wall at x=0")


func test_kit_pieces_load() -> void:
	for piece in KIT_PIECES:
		var path: String = KIT_DIR + piece + ".glb"
		assert_true(ResourceLoader.exists(path), "%s exists" % path)
		var scene := load(path) as PackedScene
		assert_true(scene != null, "%s loads" % path)
		if scene != null:
			var n := scene.instantiate()
			assert_true(n is Node3D, "%s instantiates" % path)
			n.free()
	var fixture := (load(KIT_DIR + "fluorescent_fixture.glb") as PackedScene)
	if fixture != null:
		var f := fixture.instantiate()
		assert_true(f.find_child("LightAnchor", true, false) != null, "kit fixture has a LightAnchor")
		var meshes := _find(f, func(n: Node) -> bool: return n is MeshInstance3D)
		var tube := false
		for m in meshes:
			tube = tube or _has_material(m as MeshInstance3D, "FluorescentTube")
		assert_true(tube, "kit fixture has a FluorescentTube surface")
		f.free()


# ------------------------------------------------------------------ helpers
func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var space := tree.root.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, Catalog.LAYER_WORLD)
	q.hit_back_faces = false
	return space.intersect_ray(q)


func _find(root: Node, pred: Callable) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if pred.call(n):
			out.append(n)
		stack.append_array(n.get_children())
	return out


func _has_material(mi: MeshInstance3D, mat_name: String) -> bool:
	if mi.mesh == null:
		return false
	for i in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(i)
		if m != null and m.resource_name == mat_name:
			return true
	return false
