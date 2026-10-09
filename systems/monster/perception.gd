class_name Perception
extends RefCounted
## Sight helpers shared by the monster and the coworkers.
## Only the world layer blocks sight (walls, shelves, counters); characters do not.

const DEFAULT_VIEW_DISTANCE := 30.0


## True when nothing on the world layer lies between `from` and `to`.
static func has_line_of_sight(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	if space == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(from, to, Catalog.LAYER_WORLD)
	query.collide_with_areas = false
	return space.intersect_ray(query).is_empty()


## True when `point` is inside the camera's frustum, within `max_distance` of it
## and not hidden behind world geometry.
static func is_point_visible_to_camera(camera: Camera3D, point: Vector3, max_distance := DEFAULT_VIEW_DISTANCE) -> bool:
	if camera == null or not camera.is_inside_tree():
		return false
	var eye := camera.global_position
	if eye.distance_to(point) > max_distance:
		return false
	if not camera.is_position_in_frustum(point):
		return false
	return has_line_of_sight(camera.get_world_3d().direct_space_state, eye, point)


## True when any of `points` (e.g. feet, chest, head of a character) is visible.
static func is_any_point_visible(camera: Camera3D, points: PackedVector3Array, max_distance := DEFAULT_VIEW_DISTANCE) -> bool:
	for point in points:
		if is_point_visible_to_camera(camera, point, max_distance):
			return true
	return false


## Sample points along a standing character of `height` at `base` (its feet).
static func body_points(base: Vector3, height: float) -> PackedVector3Array:
	return PackedVector3Array([
		base + Vector3.UP * (height * 0.2),
		base + Vector3.UP * (height * 0.55),
		base + Vector3.UP * (height * 0.9),
	])


## The camera the player sees through: `get_camera()` when it returns one,
## else the first Camera3D below the player node.
static func find_player_camera(player: Node) -> Camera3D:
	if player == null or not is_instance_valid(player):
		return null
	if player.has_method(&"get_camera"):
		var camera: Camera3D = player.get_camera()
		if camera != null:
			return camera
	var found := player.find_children("*", "Camera3D", true, false)
	return found[0] as Camera3D if not found.is_empty() else null
