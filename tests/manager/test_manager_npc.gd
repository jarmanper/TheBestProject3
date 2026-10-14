extends TestCase
## The manager's in-world contract: StoreManager places an interactable NPC at
## the level marker, and the interaction routes through ManagerNpc.talk().

var _manager: StoreManager
var _spot: Marker3D


func before_each() -> void:
	_spot = Marker3D.new()
	_spot.add_to_group(&"manager_spot")
	_spot.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(35.0)), Vector3(12.0, 0.0, -13.0))
	tree.root.add_child(_spot)
	_manager = StoreManager.new()
	tree.root.add_child(_manager)
	await wait_frames(1)


func after_each() -> void:
	if is_instance_valid(_manager):
		_manager.queue_free()
	if is_instance_valid(_spot):
		_spot.queue_free()
	await wait_frames(1)


func test_spawns_manager_npc_at_the_manager_spot() -> void:
	var npc := _manager.npc as ManagerNpc
	assert_true(npc != null, "StoreManager spawns a ManagerNpc")
	if npc == null:
		return
	assert_near(npc.global_position.x, _spot.global_position.x)
	assert_near(npc.global_position.y, _spot.global_position.y)
	assert_near(npc.global_position.z, _spot.global_position.z)
	assert_true(npc.is_in_group(&"employee"), "manager participates as an employee NPC")
	assert_eq(npc.collision_layer, Catalog.LAYER_NPC, "manager uses the NPC collision layer")
	assert_eq(npc.collision_mask, Catalog.LAYER_WORLD, "manager collides with store geometry")
	assert_true(npc.get_node_or_null(^"CollisionShape3D") is CollisionShape3D, "manager has a body collider")
	assert_true(npc.get_node_or_null(^"Model") is Node3D, "manager has a model holder")


func test_talk_area_is_interactable_and_routes_to_the_manager() -> void:
	var npc := _manager.npc as ManagerNpc
	assert_true(npc != null, "StoreManager spawns a ManagerNpc")
	if npc == null:
		return
	var talk_area := npc.get_node_or_null(^"TalkArea") as TalkPoint
	assert_true(talk_area != null, "manager has a TalkPoint")
	if talk_area == null:
		return
	assert_eq(talk_area.prompt_text, "Talk")
	assert_eq(talk_area.collision_layer, Catalog.LAYER_INTERACT, "talk point is raycastable as an interaction")
	assert_true(talk_area.get_node_or_null(^"CollisionShape3D") is CollisionShape3D, "talk point has an interaction volume")

	var subtitles: Array[String] = []
	var record := func(message: String, _duration: float) -> void: subtitles.append(message)
	Events.subtitle.connect(record)
	talk_area.interact(null)
	Events.subtitle.disconnect(record)
	assert_eq(subtitles.size(), 1, "talking produces one manager subtitle")
	if subtitles.size() == 1:
		assert_true(subtitles[0] in ManagerLines.TALK, "talking uses a manager line")
