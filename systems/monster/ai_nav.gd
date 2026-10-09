class_name AiNav
extends RefCounted
## Navigation helpers shared by the monster and the coworkers.
## The navigation map syncs asynchronously: right after a level loads it may list
## a region whose polygons are not usable yet, so "ready" means a query near
## `probe` actually lands on a polygon. Callers cache a true result.

const AGENT_RADIUS := 0.4         ## level contract (docs/ARCHITECTURE.md §6)
const AGENT_HEIGHT := 1.8
const AGENT_MAX_CLIMB := 0.25
const MIN_ISLAND_SIDE := 2.0      ## m; walkable islands smaller than this square are dropped


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


## A NavigationMesh that bakes from the static world colliders on the project's
## navigation cells with the contract agent. Agent sizes are rounded to whole
## cells the way the baker would (radius/height up, climb down), so a bake does
## not warn about lost precision; e.g. 0.25 m cells give radius 0.5, height 2.0.
static func make_bake_mesh() -> NavigationMesh:
	var cell_size: float = ProjectSettings.get_setting("navigation/3d/default_cell_size", 0.25)
	var cell_height: float = ProjectSettings.get_setting("navigation/3d/default_cell_height", 0.25)
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = Catalog.LAYER_WORLD
	mesh.cell_size = cell_size
	mesh.cell_height = cell_height
	mesh.agent_radius = ceilf(AGENT_RADIUS / cell_size - 0.001) * cell_size
	mesh.agent_height = ceilf(AGENT_HEIGHT / cell_height - 0.001) * cell_height
	mesh.agent_max_climb = floorf(AGENT_MAX_CLIMB / cell_height + 0.001) * cell_height
	mesh.region_min_size = ceilf(MIN_ISLAND_SIDE / cell_size)   # in cells
	return mesh
