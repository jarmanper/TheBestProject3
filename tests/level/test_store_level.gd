extends TestCase
## The final store level (levels/store/store.tscn) satisfies the level contract
## (docs/ARCHITECTURE.md §6) and is playable: every place the game sends someone is on the
## one connected navmesh and reachable from the player spawn, every station / rack / hiding
## spot can be targeted by the player's interaction ray from where they stand, and the art
## renders the way the pictures need it (nearest-filtered pixels, no stray shadows).

const STORE := "res://levels/store/store.tscn"
const Greybox := preload("res://levels/greybox/build_greybox.gd")
const Builder := preload("res://tools/level/store_builder.gd")
const Layout := preload("res://tools/level/store_layout.gd")

const EYE := 1.6
const NEAREST_FILTERS := [
	BaseMaterial3D.TEXTURE_FILTER_NEAREST,
	BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS,
	BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC,
]

var holder: Node3D
var level: Node3D
var map: RID


func before_each() -> void:
	holder = Node3D.new()
	tree.root.add_child(holder)
	level = (load(STORE) as PackedScene).instantiate()
	holder.add_child(level)
	map = level.get_world_3d().navigation_map
	await _wait_for_navmesh()


func after_each() -> void:
	holder.free()


## Region updates are asynchronous: wait until the store polygons are in the map.
func _wait_for_navmesh() -> void:
	var probe: Vector3 = Layout.PLAYER_SPAWN.position
	for i in 180:
		await tree.physics_frame
		if NavigationServer3D.map_get_iteration_id(map) > 0 \
				and NavigationServer3D.map_get_closest_point_owner(map, probe).is_valid() \
				and NavigationServer3D.map_get_closest_point(map, probe).distance_to(probe) < 0.5:
			return
	_fail("navigation map never got the store navmesh")


func _in_level(group: StringName) -> Array[Node]:
	var found: Array[Node] = []
	for node in tree.get_nodes_in_group(group):
		if level.is_ancestor_of(node):
			found.append(node)
	return found


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## True when `point` is on the navmesh (within `tolerance` metres horizontally) and a path
## from the player spawn reaches it.
func _reachable(point: Vector3, tolerance := 0.45) -> bool:
	var target := NavigationServer3D.map_get_closest_point(map, point)
	if _flat(target, point) > tolerance:
		return false
	var start := NavigationServer3D.map_get_closest_point(map, Layout.PLAYER_SPAWN.position)
	var path := NavigationServer3D.map_get_path(map, start, target, true)
	return not path.is_empty() and _flat(path[path.size() - 1], target) < 0.25


## What the player's interaction ray (world + interact layers, areas included) hits first.
func _ray_hit(from: Vector3, to: Vector3) -> Object:
	var query := PhysicsRayQueryParameters3D.create(from, to, Catalog.LAYER_WORLD | Catalog.LAYER_INTERACT)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := level.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("collider")


static func _shape_center(area: Area3D) -> Vector3:
	for child in area.get_children():
		if child is CollisionShape3D:
			return (child as CollisionShape3D).global_position
	return area.global_position


# --- Contract ----------------------------------------------------------------------------------

func test_zones_come_from_the_greybox_table() -> void:
	var zones := _in_level(&"store_zone")
	assert_eq(zones.size(), 14, "zone count")
	var expected := {}
	for z: Array in Greybox.ZONE_BOUNDS:
		expected[z[0]] = Rect2(z[1], z[3], z[2] - z[1], z[4] - z[3])
	for zone: StoreZone in zones:
		assert_true(expected.has(zone.zone_id), "unexpected zone %s" % zone.zone_id)
		var bounds := zone.get_bounds()
		var actual := Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z)
		var rect: Rect2 = expected.get(zone.zone_id, Rect2())
		assert_true(actual.position.is_equal_approx(rect.position) and actual.size.is_equal_approx(rect.size),
			"%s bounds %s, expected %s" % [zone.zone_id, actual, rect])
		expected.erase(zone.zone_id)
	assert_true(expected.is_empty(), "missing zones %s" % [expected.keys()])


func test_markers() -> void:
	var player_spawns := _in_level(&"player_spawn")
	assert_eq(player_spawns.size(), 1, "one player_spawn")
	var spawn := player_spawns[0] as Node3D
	assert_true(spawn.global_position.is_equal_approx(Vector3(6, 0, -12.5)), "player spawn by the time clock")
	assert_true(-spawn.global_basis.z.z > 0.9, "the player faces the break room door (+Z)")
	assert_eq(_in_level(&"coworker_spawn").size(), 3, "three coworker spawns")
	var monster_spawns := _in_level(&"monster_spawn")
	assert_eq(monster_spawns.size(), 1, "one monster spawn")
	assert_true((monster_spawns[0] as Node3D).global_position.is_equal_approx(Vector3(-18, 0, -15)), "monster in the far storage corner")
	var manager := _in_level(&"manager_spot")
	assert_eq(manager.size(), 1, "one manager spot")
	assert_eq(StoreZone.find_zone_id_at(tree, (manager[0] as Node3D).global_position), &"office", "manager in the office")
	assert_true((manager[0] as Node3D).global_basis.z.z > 0.9, "manager faces the office door (model front +Z)")
	var patrol := _in_level(&"patrol_point")
	assert_true(patrol.size() >= 18 and patrol.size() <= 30, "about 20 patrol points, got %d" % patrol.size())
	var zones_with_patrol := {}
	for point: Node3D in patrol:
		zones_with_patrol[StoreZone.find_zone_id_at(tree, point.global_position)] = true
	for zone_id in Catalog.ZONES:
		assert_true(zones_with_patrol.has(zone_id), "a patrol point in %s" % zone_id)
	var speakers := _in_level(&"intercom_speaker")
	assert_true(speakers.size() >= 4 and speakers.size() <= 6, "4-6 intercom speakers, got %d" % speakers.size())
	for speaker: Node3D in speakers:
		assert_true(speaker is AudioStreamPlayer3D, "speaker is an AudioStreamPlayer3D")
		assert_true(speaker.global_position.y > 2.7, "%s near the ceiling" % speaker.name)
	assert_eq(level.find_children("*", "WorldEnvironment", true, false).size(), 1, "one WorldEnvironment")


func test_every_station_from_the_layout_table() -> void:
	var stations := _in_level(&"task_station")
	assert_eq(stations.size(), StationLayout.STATIONS.size(), "station count")
	for entry: Dictionary in StationLayout.STATIONS:
		var found: TaskStation = null
		for station: TaskStation in stations:
			if station.title == entry.title:
				found = station
		assert_true(found != null, "station '%s'" % entry.title)
		if found == null:
			continue
		assert_eq(found.scene_file_path, entry.scene, "%s uses its station scene" % entry.title)
		assert_eq(found.zone, entry.zone)
		assert_eq(StoreZone.find_zone_id_at(tree, found.get_work_position()), entry.zone,
			"%s: work point inside its zone" % entry.title)


func test_every_tool_has_one_rack_and_every_station_tool_a_rack() -> void:
	var racks := _in_level(&"tool_pickup")
	assert_eq(racks.size(), Catalog.TOOLS.size(), "one rack per tool")
	var expected_zone := {&"mop": &"janitor", &"price_gun": &"service_desk", &"box_cutter": &"storage",
		&"stock_box": &"storage", &"keys": &"office"}
	for rack: ToolPickup in racks:
		assert_eq(StoreZone.find_zone_id_at(tree, rack.global_position), expected_zone.get(rack.tool_id, &""),
			"%s rack zone" % rack.tool_id)
		assert_true(rack.has_tool, "%s starts on its rack" % rack.tool_id)
	for station: TaskStation in _in_level(&"task_station"):
		if station.required_tool != &"":
			assert_true(ToolPickup.find_rack(tree, station.required_tool) != null,
				"%s needs %s: a rack exists" % [station.title, station.required_tool])


func test_taking_a_tool_leaves_its_rack_visible() -> void:
	for rack: ToolPickup in _in_level(&"tool_pickup"):
		var model := rack.get_node("Tool")
		var inner := model.find_child("Tool", true, false) as Node3D
		var frame := model.find_child("Rack", true, false) as Node3D
		assert_true(inner != null and frame != null, "%s model has its Tool and Rack" % rack.tool_id)
		if inner == null or frame == null:
			continue
		rack.has_tool = false
		rack._update_visual()
		assert_false(inner.is_visible_in_tree(), "%s tool hidden once taken" % rack.tool_id)
		assert_true(frame.is_visible_in_tree(), "%s rack stays visible" % rack.tool_id)
		rack.return_tool()
		assert_true(inner.is_visible_in_tree(), "%s tool back on its rack" % rack.tool_id)


func test_hiding_spots() -> void:
	var spots := _in_level(&"hiding_spot")
	assert_eq(spots.size(), 9, "hiding spot count")
	var by_kind_zone := {}
	for spot: HidingSpot in spots:
		var key := "%s@%s" % [spot.spot_kind, StoreZone.find_zone_id_at(tree, spot.global_position)]
		by_kind_zone[key] = by_kind_zone.get(key, 0) + 1
		# The hidden camera looks out of the spot's opening (+Z of the spot).
		var look := -spot.get_hide_transform().basis.z
		assert_true(look.dot(spot.global_basis.z) > 0.9, "%s: hidden view looks out" % spot.name)
		if spot.spot_kind == &"locker":
			assert_true(spot.find_child("Door", true, false) != null, "%s has the locker door to swing" % spot.name)
	assert_eq(by_kind_zone.get("locker@break_room", 0), 3, "three lockers in the break room")
	assert_eq(by_kind_zone.get("boxes@storage", 0), 2, "two box piles in storage")
	assert_eq(by_kind_zone.get("counter@checkout", 0), 3, "three checkout crouch spots")
	assert_eq(by_kind_zone.get("counter@service_desk", 0), 1, "one service-desk crouch spot")


func test_one_breaker_panel_is_visible() -> void:
	var static_box := level.find_child("BreakerPanel_Static", true, false) as Node3D
	assert_true(static_box != null and not static_box.is_visible_in_tree(), "the art's static breaker box is hidden")
	# breaker_panel.glb: BreakerPanel (mesh) -> Door.
	var panels := level.find_children("BreakerPanel", "MeshInstance3D", true, false).filter(
		func(n: Node) -> bool: return (n as Node3D).is_visible_in_tree() and n.get_node_or_null(^"Door") != null)
	assert_eq(panels.size(), 1, "exactly one breaker panel (the prop with a door)")


# --- Navigation -----------------------------------------------------------------------------------

func test_navmesh_settings_and_one_island() -> void:
	var region := level.get_node("NavigationRegion3D") as NavigationRegion3D
	var navmesh := region.navigation_mesh
	assert_true(navmesh.get_polygon_count() > 200, "baked polygons: %d" % navmesh.get_polygon_count())
	assert_near(navmesh.cell_size, 0.1)
	assert_near(navmesh.cell_height, 0.1)
	assert_near(navmesh.agent_radius, 0.4)
	assert_near(navmesh.agent_height, 1.8)
	assert_near(NavigationServer3D.map_get_cell_size(map), navmesh.cell_size, 0.0001, "map cell size matches")
	assert_near(NavigationServer3D.map_get_cell_height(map), navmesh.cell_height, 0.0001, "map cell height matches")
	assert_near(ProjectSettings.get_setting("navigation/3d/default_cell_size"), 0.1, 0.0001, "project default cell size")
	assert_eq(Builder.count_islands(navmesh), 1, "one connected walkable floor (no shelf-top islands)")


func test_every_zone_is_reachable() -> void:
	for zone: StoreZone in _in_level(&"store_zone"):
		var bounds := zone.get_bounds()
		var ok := false
		for fx in [0.5, 0.25, 0.75]:
			for fz in [0.5, 0.25, 0.75]:
				var probe := Vector3(bounds.position.x + bounds.size.x * fx, 0.0, bounds.position.z + bounds.size.z * fz)
				var snapped := NavigationServer3D.map_get_closest_point(map, probe)
				if zone.contains_point(snapped) and _reachable(snapped):
					ok = true
		assert_true(ok, "zone %s has reachable floor" % zone.zone_id)


func test_spawns_patrol_points_and_work_points_are_reachable() -> void:
	for group in [&"coworker_spawn", &"monster_spawn", &"manager_spot", &"patrol_point"]:
		for marker: Node3D in _in_level(group):
			assert_true(_reachable(marker.global_position), "%s %s at %s reachable" % [group, marker.name, marker.global_position])
	for station: TaskStation in _in_level(&"task_station"):
		assert_true(_reachable(station.get_work_position()), "work point of '%s' at %s reachable" % [station.title, station.get_work_position()])


func test_every_hiding_spot_exits_onto_the_navmesh() -> void:
	for spot: HidingSpot in _in_level(&"hiding_spot"):
		assert_true(_reachable(spot.get_exit_position(), 0.3), "%s exit %s on reachable floor" % [spot.name, spot.get_exit_position()])


# --- Interaction ----------------------------------------------------------------------------------

func test_stations_can_be_targeted_from_their_work_point() -> void:
	for station: TaskStation in _in_level(&"task_station"):
		var eye := station.get_work_position() + Vector3.UP * EYE
		var hit := _ray_hit(eye, eye + (_shape_center(station) - eye).normalized() * 2.2)
		assert_true(hit == station, "'%s' targeted from its work point (hit %s)" % [station.title, hit])


func test_racks_and_hiding_spots_can_be_targeted_from_in_front() -> void:
	for rack: ToolPickup in _in_level(&"tool_pickup"):
		var target := _shape_center(rack)
		var stand := rack.global_position + rack.global_basis.z * 0.9
		assert_eq(StoreZone.find_zone_id_at(tree, stand), StoreZone.find_zone_id_at(tree, rack.global_position),
			"%s rack faces into its own room" % rack.tool_id)
		assert_true(_reachable(Vector3(stand.x, 0.0, stand.z), 0.6), "%s rack: floor in front at %s reachable" % [rack.tool_id, stand])
		var eye := Vector3(stand.x, EYE, stand.z)
		var hit := _ray_hit(eye, eye + (target - eye).normalized() * 2.2)
		assert_true(hit == rack, "%s rack targeted from in front (hit %s)" % [rack.tool_id, hit])
	for spot: HidingSpot in _in_level(&"hiding_spot"):
		var exit := spot.get_exit_position()
		var eye := Vector3(exit.x, EYE, exit.z)
		var target := _shape_center(spot)
		var hit := _ray_hit(eye, eye + (target - eye).normalized() * 2.2)
		assert_true(hit == spot, "%s targeted from its exit point (hit %s)" % [spot.name, hit])


# --- Look -------------------------------------------------------------------------------------------

func test_pixel_textures_are_nearest_filtered() -> void:
	await wait_frames(2)   # PropPlaceholders have loaded their models
	var bad := {}
	for instance: MeshInstance3D in level.find_children("*", "MeshInstance3D", true, false):
		if instance.mesh == null:
			continue
		for i in instance.mesh.get_surface_count():
			var material := instance.get_active_material(i) as BaseMaterial3D
			if material and material.albedo_texture and not material.texture_filter in NEAREST_FILTERS:
				bad[material.resource_path if material.resource_path else instance.name] = material.texture_filter
	assert_true(bad.is_empty(), "linear-filtered pixel textures: %s" % bad)


func test_lights() -> void:
	var store_lights := _in_level(&"store_light")
	assert_eq(store_lights.size(), 52, "a StoreLight at every LightAnchor")
	var off := 0
	var buzz := 0
	for light: StoreLight in store_lights:
		var omni := light.get_node("Light") as OmniLight3D
		assert_true(omni.omni_range >= 4.5 and omni.omni_range <= 6.0, "%s range %s" % [light.name, omni.omni_range])
		assert_true(light._fixture != null, "%s drives its fixture's tube" % light.name)
		off += 1 if light.starts_off else 0
		buzz += 1 if light.buzzes else 0
	assert_true(buzz <= 10, "at most 10 buzzing fixtures, got %d" % buzz)
	assert_true(off >= 15 and off <= 26, "about a third of the fixtures dark, got %d" % off)
	for light: Light3D in level.find_children("*", "Light3D", true, false):
		assert_false(light.shadow_enabled, "%s casts no shadows (only the flashlight does)" % light.name)
