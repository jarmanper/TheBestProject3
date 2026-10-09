class_name StoreZone
extends Area3D
## A named box-shaped region of the store (Aisle 3, Storage Room, ...).
## Used for intercom locations, AI destinations and the minimap.
## Needs one CollisionShape3D child with a BoxShape3D.

@export var zone_id: StringName = &""
@export var display_name := ""


func _ready() -> void:
	add_to_group(&"store_zone")
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	monitorable = false
	if display_name.is_empty():
		display_name = Catalog.zone_name(zone_id)


## World-space axis-aligned bounds of the zone's box.
func get_bounds() -> AABB:
	var shape_node := _get_box_node()
	if shape_node == null:
		return AABB(global_position, Vector3.ZERO)
	var size: Vector3 = (shape_node.shape as BoxShape3D).size
	return AABB(shape_node.global_position - size * 0.5, size)


func contains_point(point: Vector3) -> bool:
	var bounds := get_bounds()
	return point.x >= bounds.position.x and point.x <= bounds.end.x \
		and point.z >= bounds.position.z and point.z <= bounds.end.z


## Random floor-level point inside the zone, snapped to the navmesh when one exists.
func get_random_point() -> Vector3:
	var bounds := get_bounds()
	var point := Vector3(
		randf_range(bounds.position.x + 0.5, bounds.end.x - 0.5),
		0.0,
		randf_range(bounds.position.z + 0.5, bounds.end.z - 0.5))
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) > 0:
		point = NavigationServer3D.map_get_closest_point(map, point)
	return point


static func find_zone(tree: SceneTree, zone_id: StringName) -> StoreZone:
	for zone: StoreZone in tree.get_nodes_in_group(&"store_zone"):
		if zone.zone_id == zone_id:
			return zone
	return null


static func find_zone_id_at(tree: SceneTree, point: Vector3) -> StringName:
	for zone: StoreZone in tree.get_nodes_in_group(&"store_zone"):
		if zone.contains_point(point):
			return zone.zone_id
	return &""


func _get_box_node() -> CollisionShape3D:
	for child in get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D:
			return child
	return null
