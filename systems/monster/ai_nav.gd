class_name AiNav
extends RefCounted
## Navigation helpers shared by the monster and the coworkers.
## The navigation map syncs asynchronously: right after a level loads it may list
## a region whose polygons are not usable yet, so "ready" means a query near
## `probe` actually lands on a polygon.


static func is_ready(map: RID, probe: Vector3) -> bool:
	return map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0 \
		and NavigationServer3D.map_get_closest_point_owner(map, probe).is_valid()


## `point` moved onto the navmesh when it is ready, else kept at `fallback_y`.
static func snap(map: RID, ready: bool, point: Vector3, fallback_y := 0.0) -> Vector3:
	if not ready:
		return Vector3(point.x, fallback_y, point.z)
	return NavigationServer3D.map_get_closest_point(map, point)


## A random floor point inside a zone's box (0.5 m from its edges), not snapped.
static func random_point_in_zone(zone: StoreZone, rng: RandomNumberGenerator) -> Vector3:
	var bounds := zone.get_bounds()
	var margin_x := minf(0.5, bounds.size.x * 0.5)
	var margin_z := minf(0.5, bounds.size.z * 0.5)
	return Vector3(
		rng.randf_range(bounds.position.x + margin_x, bounds.end.x - margin_x),
		0.0,
		rng.randf_range(bounds.position.z + margin_z, bounds.end.z - margin_z))
