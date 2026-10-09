extends RefCounted
## Store level generator logic, run by tools/build_store_level.gd (see there). It is loaded at
## runtime because the level's node scripts need the autoloads, which do not exist yet while
## a `-s` script compiles.

const Layout := preload("res://tools/level/store_layout.gd")
const StoreEnvironment := preload("res://tools/level/store_environment.gd")
const Greybox := preload("res://levels/greybox/build_greybox.gd")

const OUT_SCENE := "res://levels/store/store.tscn"
const OUT_NAVMESH := "res://levels/store/store_navmesh.res"
const ROOT_SCRIPT := "res://levels/store/store.gd"
const AMBIENT_SCRIPT := "res://levels/store/ambient_emitter.gd"
const CULLER_SCRIPT := "res://levels/store/area_culler.gd"
const STORE_GLB := "res://assets/models/environment/store_interior.glb"

const NAV_CELL_SIZE := 0.1
const NAV_CELL_HEIGHT := 0.1
const NAV_AGENT_RADIUS := 0.4
const NAV_AGENT_HEIGHT := 1.8
const NAV_MAX_CLIMB := 0.2
## Recast squares this (in cells) for the smallest island it keeps: 24 -> 576 cells = 5.76 m².
## The tops of the gondolas (1.2 m x 10 m, eroded to ~0.5 m x 9.2 m = 4.6 m²), the storage racks
## (4.9 m²), counters and tables would otherwise become unreachable islands the AI could snap to;
## the floor is one connected region set and is never affected.
const NAV_REGION_MIN_SIZE := 24.0

var level: Node3D
var region: NavigationRegion3D
var interior: Node3D
var _tree: SceneTree
var _counts := {}


## Builds and saves the level. Returns OK or the save error.
func build(tree: SceneTree) -> Error:
	_tree = tree
	level = Node3D.new()
	level.name = "Store"
	level.set_script(load(ROOT_SCRIPT))

	region = NavigationRegion3D.new()
	region.name = "NavigationRegion3D"
	_add(level, region)
	interior = (load(STORE_GLB) as PackedScene).instantiate() as Node3D
	interior.name = "StoreInterior"
	_add(region, interior)

	# Everything with a static collider goes under the region so the navmesh bake sees it.
	_tree.root.add_child(level)
	_build_props()
	_build_tools()
	_build_hiding_spots()
	_build_stations()
	await _tree.process_frame
	_bake_navmesh()
	_tree.root.remove_child(level)

	# Nodes whose _ready would mutate the instanced art (StoreLight duplicates fixture
	# materials) are added outside the tree so nothing runtime-only gets saved.
	_build_zones()
	_build_markers()
	_build_lights()
	_build_audio()
	_build_environment()
	_build_culler()

	var packed := PackedScene.new()
	var err := packed.pack(level)
	if err == OK:
		err = ResourceSaver.save(packed, OUT_SCENE)
	print("counts: %s" % _counts)
	print("saved %s (%s)" % [OUT_SCENE, error_string(err)])
	level.free()
	return err


# --- Gameplay nodes -------------------------------------------------------------------------

func _build_zones() -> void:
	var holder := _group(level, "Zones")
	for z: Array in Greybox.ZONE_BOUNDS:
		var zone := StoreZone.new()
		zone.name = "Zone_%s" % z[0]
		zone.zone_id = z[0]
		zone.display_name = Catalog.zone_name(z[0])
		var shape := CollisionShape3D.new()
		shape.name = "Box"
		var box := BoxShape3D.new()
		box.size = Vector3(z[2] - z[1], z[5], z[4] - z[3])
		shape.shape = box
		shape.position = Vector3((z[1] + z[2]) * 0.5, z[5] * 0.5, (z[3] + z[4]) * 0.5)
		_add(holder, zone)
		_add(zone, shape)
		_count("zones")


func _build_markers() -> void:
	var holder := _group(level, "Markers")
	_marker(holder, "PlayerSpawn", &"player_spawn", Layout.PLAYER_SPAWN)
	for i in Layout.COWORKER_SPAWNS.size():
		_marker(holder, "CoworkerSpawn%d" % (i + 1), &"coworker_spawn", Layout.COWORKER_SPAWNS[i])
	_marker(holder, "MonsterSpawn", &"monster_spawn", Layout.MONSTER_SPAWN)
	_marker(holder, "ManagerSpot", &"manager_spot", Layout.MANAGER_SPOT)
	for i in Layout.PATROL_POINTS.size():
		_marker(holder, "Patrol%02d" % (i + 1), &"patrol_point", {"position": Layout.PATROL_POINTS[i], "yaw": 0.0})


func _marker(parent: Node3D, marker_name: String, group: StringName, def: Dictionary) -> void:
	var marker := Marker3D.new()
	marker.name = marker_name
	marker.position = def.position
	marker.rotation_degrees.y = def.yaw
	marker.add_to_group(group, true)
	_add(parent, marker)
	_count(String(group))


func _build_stations() -> void:
	var holder := _group(region, "Stations")
	for station in StationLayout.spawn_all(holder):
		station.owner = level
		_count("stations")


func _build_tools() -> void:
	var holder := _group(region, "Tools")
	for def: Dictionary in Layout.TOOL_RACKS:
		var scene := load("res://systems/environment/tools/pickup_%s.tscn" % def.tool) as PackedScene
		var rack := scene.instantiate() as Node3D
		rack.name = "Rack_%s" % def.tool
		rack.position = def.position
		rack.rotation_degrees.y = def.yaw
		_add(holder, rack)
		_count("tools")


func _build_hiding_spots() -> void:
	var holder := _group(region, "HidingSpots")
	var index := {}
	for def: Dictionary in Layout.HIDING_SPOTS:
		var scene := load("res://systems/environment/hiding/hide_%s.tscn" % def.kind) as PackedScene
		var spot := scene.instantiate() as Node3D
		index[def.kind] = index.get(def.kind, 0) + 1
		spot.name = "Hide_%s_%d" % [def.kind, index[def.kind]]
		spot.position = def.position
		spot.rotation_degrees.y = def.yaw
		_add(holder, spot)
		_count("hiding_spots")


# --- Props ----------------------------------------------------------------------------------

func _build_props() -> void:
	var holder := _group(region, "Props")
	var index := {}
	for def: Array in Layout.PROPS:
		var model: String = def[0]
		var scene := load(Layout.PROPS_DIR + model + ".glb") as PackedScene
		var prop := scene.instantiate() as Node3D
		index[model] = index.get(model, 0) + 1
		prop.name = "%s_%d" % [model.to_pascal_case(), index[model]]
		prop.position = def[1]
		prop.rotation_degrees.y = def[2]
		_add(holder, prop)
		if def[3] == "auto":
			_box_collider(prop, _model_aabb(prop))
		_count("props")


## A world-layer box around `bounds` (prop-local), as a StaticBody3D child of the prop.
func _box_collider(prop: Node3D, bounds: AABB) -> void:
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = Catalog.LAYER_WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = (bounds.size - Vector3(0.02, 0.0, 0.02)).max(Vector3(0.05, 0.05, 0.05))
	shape.shape = box
	shape.position = bounds.get_center()
	# The node is an instanced model: its own children are not saved, so the body is ours.
	prop.add_child(body)
	body.owner = level
	body.add_child(shape)
	shape.owner = level


static func _model_aabb(node: Node3D) -> AABB:
	var acc := [null]
	_merge_aabb(node, Transform3D.IDENTITY, acc)
	return acc[0] if acc[0] != null else AABB(Vector3(-0.25, 0, -0.25), Vector3(0.5, 0.5, 0.5))


static func _merge_aabb(node: Node, xform: Transform3D, acc: Array) -> void:
	if node is MeshInstance3D:
		var box: AABB = xform * (node as MeshInstance3D).get_aabb()
		acc[0] = box if acc[0] == null else (acc[0] as AABB).merge(box)
	for child in node.get_children():
		if child is Node3D:
			_merge_aabb(child, xform * (child as Node3D).transform, acc)


# --- Lights --------------------------------------------------------------------------------------

func _build_lights() -> void:
	var holder := _group(level, "Lights")
	var anchors := interior.get_node("LightAnchors")
	for anchor: Node3D in anchors.get_children():
		var anchor_name := String(anchor.name)
		var position := _level_transform(anchor).origin
		var extras: Dictionary = anchor.get_meta(&"extras", {})
		if anchor_name.begins_with("LightAnchor_"):
			_fixture_light(holder, anchor, position, extras)
		elif anchor_name.begins_with("EmergencyAnchor_"):
			_plain_light(holder, anchor_name.replace("Anchor", "Light"), position,
				Layout.EMERGENCY_COLOR, Layout.EMERGENCY_ENERGY, Layout.EMERGENCY_RANGE, 1.2)
			_count("emergency_lights")
		elif anchor_name == "ExitAnchor":
			_plain_light(holder, "ExitLight", position, Layout.EXIT_COLOR, Layout.EXIT_ENERGY, Layout.EXIT_RANGE, 1.4)
			_count("exit_lights")
		elif anchor_name.begins_with("CoolerAnchor_"):
			_plain_light(holder, anchor_name.replace("Anchor", "Light"), position,
				Layout.COOLER_COLOR, Layout.COOLER_ENERGY, Layout.COOLER_RANGE, 1.6)
			_count("cooler_lights")


func _fixture_light(holder: Node3D, anchor: Node3D, position: Vector3, extras: Dictionary) -> void:
	var number := int(String(anchor.name).trim_prefix("LightAnchor_"))
	var zone := StringName(extras.get("zone", ""))
	var fixture := interior.find_child(String(extras.get("fixture", "")), true, false) as MeshInstance3D
	var light := StoreLight.new()
	light.name = "StoreLight_%03d" % number
	light.position = position
	light.base_energy = Layout.ZONE_ENERGY.get(zone, Layout.FIXTURE_ENERGY)
	light.always_flicker = number in Layout.BROKEN_FLICKER
	light.starts_off = number in Layout.BROKEN_DEAD or number in Layout.FIXTURES_OFF
	light.buzzes = number in Layout.BUZZING and not light.starts_off
	var omni := OmniLight3D.new()
	omni.name = "Light"
	omni.position = Vector3(0, -0.12, 0)
	omni.light_color = Layout.OFFICE_COLOR if zone == &"office" else Layout.FIXTURE_COLOR
	omni.light_energy = light.base_energy
	omni.omni_range = Layout.FIXTURE_RANGE
	omni.omni_attenuation = Layout.FIXTURE_ATTENUATION
	omni.light_specular = 1.0
	omni.shadow_enabled = false
	omni.distance_fade_enabled = true
	omni.distance_fade_begin = 24.0
	omni.distance_fade_length = 6.0
	_add(holder, light)
	_add(light, omni)
	if light.always_flicker:
		_add(light, _sparks())
	if fixture:
		light.fixture_path = light.get_path_to(fixture)
	else:
		push_warning("No fixture mesh for %s" % anchor.name)
	_count("store_lights")
	if light.starts_off:
		_count("store_lights_off")


## A slow trickle of sparks under a broken, flickering fixture (references 1 and 2).
func _sparks() -> CPUParticles3D:
	var sparks := CPUParticles3D.new()
	sparks.name = "Sparks"
	sparks.position = Vector3(0, -0.15, 0)
	sparks.amount = 24
	sparks.lifetime = 1.4
	sparks.randomness = 0.6
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 0.25
	sparks.direction = Vector3(0, -1, 0)
	sparks.spread = 35.0
	sparks.initial_velocity_min = 0.2
	sparks.initial_velocity_max = 0.9
	sparks.gravity = Vector3(0, -5.5, 0)
	sparks.scale_amount_min = 0.6
	sparks.scale_amount_max = 1.2
	sparks.visibility_aabb = AABB(Vector3(-1.5, -3.6, -1.5), Vector3(3, 3.8, 3))
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.albedo_color = Color(1.0, 0.93, 0.7)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.85, 0.55)
	material.emission_energy_multiplier = 3.0
	quad.material = material
	sparks.mesh = quad
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return sparks


func _plain_light(holder: Node3D, light_name: String, position: Vector3, color: Color, energy: float,
		light_range: float, attenuation: float) -> void:
	var omni := OmniLight3D.new()
	omni.name = light_name
	omni.position = position
	omni.light_color = color
	omni.light_energy = energy
	omni.omni_range = light_range
	omni.omni_attenuation = attenuation
	omni.light_specular = 0.4
	omni.shadow_enabled = false
	omni.distance_fade_enabled = true
	omni.distance_fade_begin = 24.0
	omni.distance_fade_length = 6.0
	_add(holder, omni)


# --- Audio, environment ----------------------------------------------------------------------------

func _build_audio() -> void:
	var holder := _group(level, "Audio")
	for i in Layout.INTERCOM_SPEAKERS.size():
		var speaker := AudioStreamPlayer3D.new()
		speaker.name = "IntercomSpeaker%d" % (i + 1)
		speaker.position = Layout.INTERCOM_SPEAKERS[i]
		speaker.bus = &"Voice"
		speaker.unit_size = 8.0
		speaker.max_distance = 60.0
		speaker.add_to_group(&"intercom_speaker", true)
		_add(holder, speaker)
		_count("intercom_speakers")
	var emitter_script := load(AMBIENT_SCRIPT)
	for i in Layout.AMBIENT_EMITTERS.size():
		var def: Dictionary = Layout.AMBIENT_EMITTERS[i]
		var emitter := AudioStreamPlayer3D.new()
		emitter.set_script(emitter_script)
		emitter.name = "Ambience%d_%s" % [i + 1, String(def.id).trim_prefix("amb_")]
		emitter.set(&"sound_id", def.id)
		emitter.position = def.position
		emitter.volume_db = def.db
		emitter.unit_size = 3.0
		emitter.max_distance = def.range
		emitter.bus = &"Ambience"
		_add(holder, emitter)
		_count("ambient_emitters")


## Last child: its _ready tags every mesh after the props and stations loaded their models.
func _build_culler() -> void:
	var culler := Node.new()
	culler.name = "AreaCuller"
	culler.set_script(load(CULLER_SCRIPT))
	_add(level, culler)


func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = StoreEnvironment.make()
	_add(level, world_env)


# --- Navigation ------------------------------------------------------------------------------------

func _bake_navmesh() -> void:
	var navmesh := NavigationMesh.new()
	navmesh.cell_size = NAV_CELL_SIZE
	navmesh.cell_height = NAV_CELL_HEIGHT
	navmesh.agent_radius = NAV_AGENT_RADIUS
	navmesh.agent_height = NAV_AGENT_HEIGHT
	navmesh.agent_max_climb = NAV_MAX_CLIMB
	navmesh.agent_max_slope = 45.0
	navmesh.region_min_size = NAV_REGION_MIN_SIZE
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navmesh.geometry_collision_mask = Catalog.LAYER_WORLD
	region.navigation_mesh = navmesh
	region.bake_navigation_mesh(false)
	var islands := island_bounds(navmesh)
	print("navmesh polygons: %d, vertices: %d, islands: %d" % [
		navmesh.get_polygon_count(), navmesh.vertices.size(), islands.size()])
	for box in islands.slice(1):
		push_warning("navmesh island apart from the floor: %s" % box)
	var err := ResourceSaver.save(navmesh, OUT_NAVMESH, ResourceSaver.FLAG_COMPRESS)
	assert(err == OK)
	navmesh.take_over_path(OUT_NAVMESH)


## Connected groups of polygons (sharing a vertex). The store should be exactly one.
static func count_islands(navmesh: NavigationMesh) -> int:
	return island_bounds(navmesh).size()


## The bounding box of each connected group of navmesh polygons, largest first.
static func island_bounds(navmesh: NavigationMesh) -> Array[AABB]:
	var parent: Array[int] = []
	for i in navmesh.vertices.size():
		parent.append(i)
	for p in navmesh.get_polygon_count():
		var poly := navmesh.get_polygon(p)
		for k in range(1, poly.size()):
			var a := _find_root(parent, poly[0])
			var b := _find_root(parent, poly[k])
			if a != b:
				parent[a] = b
	var boxes := {}
	for p in navmesh.get_polygon_count():
		var poly := navmesh.get_polygon(p)
		var root_id := _find_root(parent, poly[0])
		for index in poly:
			var v := navmesh.vertices[index]
			boxes[root_id] = (boxes[root_id] as AABB).expand(v) if boxes.has(root_id) else AABB(v, Vector3.ZERO)
	var result: Array[AABB] = []
	for box: AABB in boxes.values():
		result.append(box)
	result.sort_custom(func(a: AABB, b: AABB) -> bool: return a.get_volume() + a.size.x * a.size.z > b.get_volume() + b.size.x * b.size.z)
	return result


static func _find_root(parent: Array[int], i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


# --- Helpers ---------------------------------------------------------------------------------------

func _add(parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = level


func _group(parent: Node3D, group_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = group_name
	_add(parent, node)
	return node


## `node`'s transform relative to the level root (works outside the scene tree).
func _level_transform(node: Node3D) -> Transform3D:
	var xform := node.transform
	var parent := node.get_parent()
	while parent != null and parent != level:
		if parent is Node3D:
			xform = (parent as Node3D).transform * xform
		parent = parent.get_parent()
	return xform


func _count(key: String) -> void:
	_counts[key] = _counts.get(key, 0) + 1
