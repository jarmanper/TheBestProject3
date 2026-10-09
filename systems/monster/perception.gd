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


## True when `point` is in front of the camera and on screen inside the middle `fraction` of
## the view on both axes (1.0 = the whole frame). The CRT vignette darkens the rest.
static func is_point_in_view_center(camera: Camera3D, point: Vector3, fraction: float) -> bool:
	if camera == null or not camera.is_inside_tree() or camera.is_position_behind(point):
		return false
	var half := camera.get_viewport().get_visible_rect().size * 0.5
	if half.x <= 0.0 or half.y <= 0.0:
		return false
	var offset := (camera.unproject_position(point) - half) / half   # -1..1 across the frame
	return absf(offset.x) <= fraction and absf(offset.y) <= fraction


## True when `light` is on (visible) and `point` lies inside its cone and range.
static func is_point_in_spotlight(light: SpotLight3D, point: Vector3) -> bool:
	if light == null or not light.is_inside_tree() or not light.is_visible_in_tree():
		return false
	var to_point := point - light.global_position
	var distance := to_point.length()
	if distance > light.spot_range:
		return false
	if distance < 0.01:
		return true
	var forward := -light.global_basis.z.normalized()
	return forward.dot(to_point / distance) >= cos(deg_to_rad(light.spot_angle))


## True when `point` is lit for the player: inside the flashlight's beam (while it is on) or
## within range of a store light that is on (StoreLight.lights_point).
static func is_point_lit(tree: SceneTree, point: Vector3, flashlight: SpotLight3D) -> bool:
	if is_point_in_spotlight(flashlight, point):
		return true
	for node in tree.get_nodes_in_group(&"store_light"):
		if node.has_method(&"lights_point") and node.lights_point(point):
			return true
	return false


## The player's flashlight: the first SpotLight3D under the player's camera (null if none).
static func find_flashlight(player: Node) -> SpotLight3D:
	var camera := find_player_camera(player)
	if camera == null:
		return null
	var found := camera.find_children("*", "SpotLight3D", true, false)
	return found[0] as SpotLight3D if not found.is_empty() else null


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
