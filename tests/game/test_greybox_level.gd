extends TestCase
## The greybox satisfies the level scene contract (docs/ARCHITECTURE.md §6 "Level scene contract", §7 layout).

const GREYBOX := "res://levels/greybox/greybox.tscn"

const ZONE_BOUNDS := {
	&"aisle_1": Rect2(-15.4, -3.0, 2.8, 10.0),
	&"aisle_2": Rect2(-11.4, -3.0, 2.8, 10.0),
	&"aisle_3": Rect2(-7.4, -3.0, 2.8, 10.0),
	&"aisle_4": Rect2(-3.4, -3.0, 2.8, 10.0),
	&"dairy": Rect2(-20.0, -6.0, 22.0, 3.0),
	&"frozen": Rect2(-20.0, -3.0, 3.4, 10.0),
	&"produce": Rect2(2.0, -6.0, 18.0, 15.0),
	&"checkout": Rect2(-20.0, 7.0, 26.0, 9.0),
	&"service_desk": Rect2(6.0, 9.0, 14.0, 7.0),
	&"hallway": Rect2(-20.0, -9.0, 40.0, 3.0),
	&"storage": Rect2(-20.0, -16.0, 22.0, 7.0),
	&"break_room": Rect2(2.0, -16.0, 8.0, 7.0),
	&"office": Rect2(10.0, -16.0, 6.0, 7.0),
	&"janitor": Rect2(16.0, -16.0, 4.0, 7.0),
}

var holder: Node3D
var level: Node3D


func before_each() -> void:
	holder = Node3D.new()
	tree.root.add_child(holder)
	level = (load(GREYBOX) as PackedScene).instantiate()
	holder.add_child(level)
	await _wait_for_navmesh()


## Region updates are asynchronous: wait until the greybox polygons are in the map.
func _wait_for_navmesh() -> void:
	var map := level.get_world_3d().navigation_map
	var probe := Vector3(6, 0, -12.5)
	for i in 120:
		await tree.physics_frame
		if NavigationServer3D.map_get_iteration_id(map) > 0 \
				and NavigationServer3D.map_get_closest_point(map, probe).distance_to(probe) < 0.5:
			return


func after_each() -> void:
	holder.free()


func _in_level(group: StringName) -> Array[Node]:
	var found: Array[Node] = []
	for node in tree.get_nodes_in_group(group):
		if level.is_ancestor_of(node):
			found.append(node)
	return found


func test_all_fourteen_zones_with_exact_bounds() -> void:
	var zones := _in_level(&"store_zone")
	assert_eq(zones.size(), 14, "zone count")
	var seen := {}
	for zone: StoreZone in zones:
		assert_true(ZONE_BOUNDS.has(zone.zone_id), "unexpected zone %s" % zone.zone_id)
		if not ZONE_BOUNDS.has(zone.zone_id):
			continue
		seen[zone.zone_id] = true
		var expected: Rect2 = ZONE_BOUNDS[zone.zone_id]
		var bounds := zone.get_bounds()
		var actual := Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z)
		assert_true(actual.position.is_equal_approx(expected.position) and actual.size.is_equal_approx(expected.size),
			"%s bounds %s, expected %s" % [zone.zone_id, actual, expected])
		assert_eq(zone.display_name, Catalog.zone_name(zone.zone_id))
	assert_eq(seen.size(), Catalog.ZONES.size(), "every Catalog zone present")


func test_spawn_markers() -> void:
	var player_spawns := _in_level(&"player_spawn")
	assert_eq(player_spawns.size(), 1, "one player_spawn")
	assert_true((player_spawns[0] as Node3D).global_position.is_equal_approx(Vector3(6, 0, -12.5)), "player spawn by the time clock")
	var facing := -(player_spawns[0] as Node3D).global_transform.basis.z
	assert_true(facing.z > 0.9, "player faces the break room door (+Z)")
	assert_eq(_in_level(&"coworker_spawn").size(), 3, "three coworker spawns")
	var monster_spawns := _in_level(&"monster_spawn")
	assert_eq(monster_spawns.size(), 1, "one monster spawn")
	assert_true((monster_spawns[0] as Node3D).global_position.is_equal_approx(Vector3(-18, 0, -15)), "monster in the far storage corner")
	assert_eq(_in_level(&"manager_spot").size(), 1, "one manager spot")
	assert_true(StoreZone.find_zone_id_at(tree, (_in_level(&"manager_spot")[0] as Node3D).global_position) == &"office", "manager in the office")
	assert_true(_in_level(&"patrol_point").size() >= 8, "several patrol points")
	for node in _in_level(&"coworker_spawn") + _in_level(&"monster_spawn") + _in_level(&"patrol_point"):
		assert_true(node is Marker3D, "%s is a Marker3D" % node.name)


func test_navmesh_is_baked_with_agent_size() -> void:
	var region := level.get_node("NavigationRegion3D") as NavigationRegion3D
	assert_true(region != null, "has a NavigationRegion3D")
	var navmesh := region.navigation_mesh
	assert_true(navmesh.get_polygon_count() > 100, "baked polygons: %d" % navmesh.get_polygon_count())
	assert_near(navmesh.agent_radius, 0.4)
	assert_near(navmesh.agent_height, 1.8)
	var map := level.get_world_3d().navigation_map
	assert_near(NavigationServer3D.map_get_cell_size(map), navmesh.cell_size, 0.0001, "map cell size matches the navmesh")
	assert_near(NavigationServer3D.map_get_cell_height(map), navmesh.cell_height, 0.0001, "map cell height matches the navmesh")


func test_every_zone_and_marker_is_reachable_from_the_player_spawn() -> void:
	var map := level.get_world_3d().navigation_map
	assert_true(NavigationServer3D.map_get_iteration_id(map) > 0, "map synced")
	var start := NavigationServer3D.map_get_closest_point(map, (_in_level(&"player_spawn")[0] as Node3D).global_position)
	var targets := {}
	for zone: StoreZone in _in_level(&"store_zone"):
		targets[String(zone.zone_id)] = zone.get_bounds().get_center() * Vector3(1, 0, 1)
	for group in [&"coworker_spawn", &"monster_spawn", &"manager_spot", &"patrol_point"]:
		for marker: Node3D in _in_level(group):
			targets[marker.name] = marker.global_position
	for station: TaskStation in _in_level(&"task_station"):
		targets[station.name] = station.get_work_position() * Vector3(1, 0, 1)
	for target_name: String in targets:
		var goal := NavigationServer3D.map_get_closest_point(map, targets[target_name])
		var path := NavigationServer3D.map_get_path(map, start, goal, true)
		var reached := not path.is_empty() and path[-1].distance_to(goal) < 0.3
		assert_true(reached, "%s reachable (path ends %s, goal %s)" % [target_name, path[-1] if not path.is_empty() else "none", goal])


func test_markers_stand_on_the_navmesh() -> void:
	var map := level.get_world_3d().navigation_map
	for group in [&"player_spawn", &"coworker_spawn", &"monster_spawn", &"manager_spot", &"patrol_point"]:
		for marker: Node3D in _in_level(group):
			var on_mesh := NavigationServer3D.map_get_closest_point(map, marker.global_position)
			assert_true(on_mesh.distance_to(marker.global_position) < 0.3, "%s is on the navmesh" % marker.name)


func test_intercom_speakers_environment_and_lights() -> void:
	var speakers := _in_level(&"intercom_speaker")
	assert_true(speakers.size() >= 2, "at least two intercom speakers")
	for speaker in speakers:
		assert_true(speaker is AudioStreamPlayer3D, "%s is an AudioStreamPlayer3D" % speaker.name)
	assert_true(level.find_children("*", "WorldEnvironment", true, false).size() == 1, "one WorldEnvironment")
	var lights := _in_level(&"store_light")
	assert_true(lights.size() >= 12, "about a dozen store lights (%d)" % lights.size())
	for light: Node3D in lights:
		assert_true(light.get_node_or_null(^"Light") is OmniLight3D, "%s has an OmniLight3D child 'Light'" % light.name)


func test_gameplay_nodes() -> void:
	var stations := _in_level(&"task_station")
	assert_true(stations.size() >= 10, "task stations (%d)" % stations.size())
	for station: TaskStation in stations:
		assert_false(station.title.is_empty(), "%s has a title" % station.name)
		assert_true(Catalog.ZONES.has(station.zone), "%s zone %s" % [station.name, station.zone])
		assert_eq(StoreZone.find_zone_id_at(tree, station.get_work_position()) != &"", true, "%s work point inside a zone" % station.name)
		assert_true(station.get_node_or_null(^"ActiveVisual") != null, "%s has ActiveVisual" % station.name)
		assert_true(station.hold_time >= 3.0 and station.hold_time <= 5.0, "%s hold time" % station.name)
		assert_eq(station.collision_layer, Catalog.LAYER_INTERACT)
	var tools := {}
	for rack: ToolPickup in _in_level(&"tool_pickup"):
		tools[rack.tool_id] = true
		assert_true(rack.get_node_or_null(^"Tool") != null, "%s has a Tool child" % rack.name)
	for tool_id in Catalog.TOOLS:
		assert_true(tools.has(tool_id), "a rack for %s" % tool_id)
	var kinds := {}
	for spot: HidingSpot in _in_level(&"hiding_spot"):
		kinds[spot.spot_kind] = true
		assert_true(spot.get_node_or_null(^"HidePoint") is Marker3D, "%s HidePoint" % spot.name)
		assert_true(spot.get_node_or_null(^"ExitPoint") is Marker3D, "%s ExitPoint" % spot.name)
	for kind in [&"locker", &"counter", &"boxes"]:
		assert_true(kinds.has(kind), "a %s hiding spot" % kind)


func test_world_geometry_is_on_the_world_layer() -> void:
	var bodies := level.find_children("*", "StaticBody3D", true, false)
	assert_true(bodies.size() > 50, "static geometry present")
	for body: StaticBody3D in bodies:
		assert_eq(body.collision_layer, Catalog.LAYER_WORLD, "%s layer" % body.name)


func test_shelves_are_stocked_at_load() -> void:
	var runs := level.find_children("ProductRun*", "MultiMeshInstance3D", true, false)
	assert_true(runs.size() > 10, "product runs")
	var filled := 0
	for run: MultiMeshInstance3D in runs:
		if run.multimesh and run.multimesh.instance_count > 0:
			filled += 1
	assert_eq(filled, runs.size(), "every run filled")
