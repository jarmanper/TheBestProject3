extends SceneTree
## Generates systems/monster/sandbox/ai_sandbox.tscn: walls, shelves and counters
## (StaticBody3D, world layer) under a NavigationRegion3D whose navmesh is baked
## from the static colliders, StoreZones, spawn/patrol markers, TaskStations,
## a HidingSpot, StoreLights, 3 coworkers and the monster (the player
## is spawned at runtime by ai_sandbox.gd).
##   godot --headless --path . -s res://systems/monster/sandbox/build_ai_sandbox.gd
## Layout (x -16..16, z -13..13, +Z = front): sales floor with three shelf rows
## (aisles 1-2), checkout at the front, produce to the right, a dairy strip, and a
## back wall at z = -5 with doors into the storage room (left) and break room (right).

const OUT_PATH := "res://systems/monster/sandbox/ai_sandbox.tscn"
const WALL_HEIGHT := 3.5
const WALL := 0.3

var scene: Node3D                    ## the sandbox being built
var region: NavigationRegion3D
var _materials := {}


func _initialize() -> void:
	_build.call_deferred()


func _build() -> void:
	await process_frame   # autoloads are ready
	scene = Node3D.new()
	scene.name = "AiSandbox"
	region = NavigationRegion3D.new()
	region.name = "NavigationRegion3D"
	_add(scene, region)
	_build_geometry()
	# Bake from the static colliders while only the geometry is in the tree.
	root.add_child(scene)
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = Catalog.LAYER_WORLD
	mesh.agent_radius = 0.5   # contract 0.4 / 1.8, rounded up to the 0.25 m cells
	mesh.agent_height = 2.0
	mesh.agent_max_climb = 0.25
	mesh.region_min_size = 8.0   # drop unreachable islands (table tops)
	region.navigation_mesh = mesh
	region.bake_navigation_mesh(false)
	print("navmesh polygons: %d" % mesh.get_polygon_count())
	root.remove_child(scene)

	scene.set_script(load("res://systems/monster/sandbox/ai_sandbox.gd"))
	_build_environment()
	_build_zones()
	_build_markers()
	_build_gameplay()
	_build_actors()

	var packed := PackedScene.new()
	var err := packed.pack(scene)
	if err == OK:
		err = ResourceSaver.save(packed, OUT_PATH)
	print("saved %s: %s" % [OUT_PATH, error_string(err)])
	scene.free()
	quit(0 if err == OK else 1)


# --- Static geometry (world layer, parsed for the navmesh) ---------------------------

func _build_geometry() -> void:
	_box("Floor", Vector3(0, -0.1, 0), Vector3(32, 0.2, 26), Catalog.COLOR_CONCRETE)
	# Outer walls.
	_box("WallFront", Vector3(0, WALL_HEIGHT * 0.5, 13), Vector3(32, WALL_HEIGHT, WALL), Catalog.COLOR_CHARCOAL.lightened(0.15))
	_box("WallBack", Vector3(0, WALL_HEIGHT * 0.5, -13), Vector3(32, WALL_HEIGHT, WALL), Catalog.COLOR_CHARCOAL.lightened(0.15))
	_box("WallLeft", Vector3(-16, WALL_HEIGHT * 0.5, 0), Vector3(WALL, WALL_HEIGHT, 26), Catalog.COLOR_CHARCOAL.lightened(0.15))
	_box("WallRight", Vector3(16, WALL_HEIGHT * 0.5, 0), Vector3(WALL, WALL_HEIGHT, 26), Catalog.COLOR_CHARCOAL.lightened(0.15))
	# Back wall of the sales floor (z = -5) with doors at x -7..-5 and x 5..7.
	_box("BackWallA", Vector3(-11.5, WALL_HEIGHT * 0.5, -5), Vector3(9, WALL_HEIGHT, WALL), Catalog.COLOR_CONCRETE.darkened(0.3))
	_box("BackWallB", Vector3(0, WALL_HEIGHT * 0.5, -5), Vector3(10, WALL_HEIGHT, WALL), Catalog.COLOR_CONCRETE.darkened(0.3))
	_box("BackWallC", Vector3(11.5, WALL_HEIGHT * 0.5, -5), Vector3(9, WALL_HEIGHT, WALL), Catalog.COLOR_CONCRETE.darkened(0.3))
	_box("Partition", Vector3(0, WALL_HEIGHT * 0.5, -9), Vector3(WALL, WALL_HEIGHT, 8), Catalog.COLOR_CONCRETE.darkened(0.3))
	# Gondola shelf rows, 1.2 m deep x 8 m long x 2.2 m tall.
	for x in [-12.0, -8.0, -4.0]:
		_box("Shelf%d" % int(-x), Vector3(x, 1.1, 2), Vector3(1.2, 2.2, 8), Catalog.COLOR_OLIVE)
	# Dairy coolers along the back wall of the sales floor (clear of the storage door).
	_box("Coolers", Vector3(-12, 1.0, -4.5), Vector3(7, 2.0, 0.8), Catalog.COLOR_CREAM.darkened(0.4))
	# Checkout counter and produce tables.
	_box("Checkout", Vector3(-6, 0.45, 9.5), Vector3(0.9, 0.9, 3), Catalog.COLOR_CREAM.darkened(0.2))
	_box("ProduceA", Vector3(6, 0.45, 2), Vector3(2.4, 0.9, 1.4), Catalog.COLOR_OLIVE.darkened(0.2))
	_box("ProduceB", Vector3(11, 0.45, 2), Vector3(2.4, 0.9, 1.4), Catalog.COLOR_OLIVE.darkened(0.2))
	_box("ProduceC", Vector3(8.5, 0.45, 7), Vector3(2.4, 0.9, 1.4), Catalog.COLOR_OLIVE.darkened(0.2))
	# Storage room shelving and the break room table.
	_box("StorageShelfA", Vector3(-11, 1.2, -11), Vector3(6, 2.4, 0.8), Catalog.COLOR_CONCRETE)
	_box("StorageShelfB", Vector3(-4, 1.2, -8), Vector3(0.8, 2.4, 4), Catalog.COLOR_CONCRETE)
	_box("BreakTable", Vector3(8, 0.4, -10), Vector3(2.0, 0.8, 1.2), Catalog.COLOR_OLIVE.lightened(0.1))


func _box(box_name: String, center: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = box_name
	body.collision_layer = Catalog.LAYER_WORLD
	body.collision_mask = 0
	body.position = center
	_add(region, body)
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	_add(body, shape)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _material(color)
	_add(body, mesh_instance)
	return body


func _material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.6
		_materials[color] = material
	return _materials[color]


# --- Environment and lights --------------------------------------------------------

func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Catalog.COLOR_CHARCOAL
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("5a6260")
	env.ambient_light_energy = 0.6
	world_env.environment = env
	_add(scene, world_env)
	# Plain StoreLights (contract: child OmniLight3D "Light"); the real StoreLight
	# shows the monster's flicker, the foundation stub keeps them steady.
	var light_script := load("res://systems/environment/store_light.gd")
	var lights := [Vector3(-10, 3.2, 2), Vector3(-6, 3.2, 2), Vector3(-2, 3.2, 8), Vector3(9, 3.2, 4),
		Vector3(-7, 3.2, 10), Vector3(-8, 3.2, -9), Vector3(8, 3.2, -9), Vector3(9, 3.2, 10)]
	for i in lights.size():
		var store_light := Node3D.new()
		store_light.set_script(light_script)
		store_light.name = "StoreLight%d" % (i + 1)
		store_light.position = lights[i]
		_add(scene, store_light)
		var omni := OmniLight3D.new()
		omni.name = "Light"
		omni.light_color = Color("e8e4c8")
		omni.light_energy = 1.0
		omni.omni_range = 8.0
		omni.omni_attenuation = 1.2
		_add(store_light, omni)


# --- Zones, markers, gameplay nodes --------------------------------------------------------

func _build_zones() -> void:
	_zone(&"aisle_1", Vector3(-10, 1.5, 2), Vector3(2.8, 3, 8))
	_zone(&"aisle_2", Vector3(-6, 1.5, 2), Vector3(2.8, 3, 8))
	_zone(&"dairy", Vector3(-7, 1.5, -3.5), Vector3(18, 3, 3))
	_zone(&"checkout", Vector3(-7, 1.5, 9.5), Vector3(18, 3, 7))
	_zone(&"produce", Vector3(9, 1.5, 4), Vector3(14, 3, 18))
	_zone(&"storage", Vector3(-8, 1.5, -9), Vector3(16, 3, 8))
	_zone(&"break_room", Vector3(8, 1.5, -9), Vector3(16, 3, 8))


func _zone(zone_id: StringName, center: Vector3, size: Vector3) -> void:
	var zone := StoreZone.new()
	zone.name = "Zone_" + String(zone_id)
	zone.zone_id = zone_id
	zone.position = center
	_add(scene, zone)
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	_add(zone, shape)


func _build_markers() -> void:
	_marker("PlayerSpawn", &"player_spawn", Vector3(0, 0, 8))
	_marker("CoworkerSpawn1", &"coworker_spawn", Vector3(4, 0, -8))
	_marker("CoworkerSpawn2", &"coworker_spawn", Vector3(11, 0, -7))
	_marker("CoworkerSpawn3", &"coworker_spawn", Vector3(-2, 0, 4))
	_marker("MonsterSpawn", &"monster_spawn", Vector3(-14, 0, -12))
	var patrol := [Vector3(-10, 0, 0), Vector3(-6, 0, 4), Vector3(-14, 0, 8), Vector3(-2, 0, 10),
		Vector3(8, 0, -1), Vector3(13, 0, 10), Vector3(-12, 0, -8), Vector3(-2, 0, -11),
		Vector3(13, 0, -11), Vector3(-14, 0, -3.5), Vector3(1, 0, -3.5), Vector3(-1, 0, 2)]
	for i in patrol.size():
		_marker("Patrol%d" % (i + 1), &"patrol_point", patrol[i])


func _marker(marker_name: String, group: StringName, at: Vector3) -> Marker3D:
	var marker := Marker3D.new()
	marker.name = marker_name
	marker.position = at
	marker.add_to_group(group, true)
	_add(scene, marker)
	return marker


func _build_gameplay() -> void:
	_station("StationMop", Vector3(-10, 0, 3), &"mop_spill", &"aisle_1", "Mop the spill in Aisle 1", true)
	_station("StationRestock", Vector3(-10, 0, -9.5), &"restock", &"storage", "Restock the storage shelves", true)
	_station("StationPrice", Vector3(8.5, 0, 4.5), &"price_check", &"produce", "Price-check the produce", true)
	_station("StationTable", Vector3(8, 0, -8.5), &"clean_table", &"break_room", "Wipe the break room table", false)
	var spot := HidingSpot.new()
	spot.name = "Locker"
	spot.spot_kind = &"locker"
	spot.prompt_text = "Hide"
	spot.position = Vector3(15.3, 0, -9)
	_add(scene, spot)
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = Vector3(0.7, 2.0, 0.7)
	shape.shape = box
	shape.position.y = 1.0
	_add(spot, shape)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.7, 2.0, 0.7)
	mesh_instance.mesh = mesh
	mesh_instance.position.y = 1.0
	mesh_instance.material_override = _material(Catalog.COLOR_OLIVE.darkened(0.3))
	_add(spot, mesh_instance)
	var hide_point := Marker3D.new()
	hide_point.name = "HidePoint"
	hide_point.position = Vector3(0, 1.6, 0)
	_add(spot, hide_point)
	var exit_point := Marker3D.new()
	exit_point.name = "ExitPoint"
	exit_point.position = Vector3(-1.0, 0, 0)
	_add(spot, exit_point)


func _station(station_name: String, at: Vector3, kind: StringName, zone: StringName, title: String, basic: bool) -> void:
	var station := TaskStation.new()
	station.name = station_name
	station.task_kind = kind
	station.zone = zone
	station.title = title
	station.basic_task = basic
	station.hold_time = 2.5
	station.prompt_text = title
	station.position = at
	_add(scene, station)
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = Vector3(1, 1, 1)
	shape.shape = box
	shape.position.y = 0.5
	_add(station, shape)
	var marker := MeshInstance3D.new()
	marker.name = "ActiveVisual"
	var disc := CylinderMesh.new()
	disc.top_radius = 0.5
	disc.bottom_radius = 0.5
	disc.height = 0.02
	marker.mesh = disc
	marker.position.y = 0.02
	marker.material_override = _material(Catalog.COLOR_CREAM)
	_add(station, marker)


func _build_actors() -> void:
	# The player is spawned at PlayerSpawn by ai_sandbox.gd at runtime (the real
	# Player scene once it exists, else the foundation stub with sandbox controls).
	var coworker_scene := load(Catalog.SCENES[&"coworker"]) as PackedScene
	var spawns := [Vector3(4, 0, -8), Vector3(11, 0, -7), Vector3(-2, 0, 4)]
	for i in Catalog.COWORKERS.size():
		var coworker := coworker_scene.instantiate()
		coworker.name = "Coworker" + String(Catalog.COWORKERS[i]["name"]).capitalize()
		coworker.set(&"employee_name", Catalog.COWORKERS[i]["name"])
		coworker.set(&"model_path", Catalog.COWORKERS[i]["model"])
		coworker.position = spawns[i]
		_add(scene, coworker)
	var monster := (load(Catalog.SCENES[&"monster"]) as PackedScene).instantiate()
	monster.name = "Monster"
	monster.position = Vector3(-14, 0, -12)
	_add(scene, monster)


func _add(parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = scene
