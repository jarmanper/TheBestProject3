extends Node3D
## Builds small physics worlds for the monster/coworker tests (not a test file).
##   var world := AiTestWorld.create(tree)
##   world.add_box(...); world.add_player(...); await world.settle()
##   ...
##   world.dispose()

const FakePlayer := preload("res://tests/monster/fake_player.gd")
const MONSTER_SCENE := "res://systems/monster/monster.tscn"
const COWORKER_SCENE := "res://systems/coworkers/coworker.tscn"

var region: NavigationRegion3D
var tree: SceneTree


static func create(scene_tree: SceneTree, floor_size := Vector2(60.0, 60.0)) -> Node3D:
	var world: Node3D = load("res://tests/monster/ai_test_world.gd").new()
	world.tree = scene_tree
	world.name = "AiTestWorld"
	scene_tree.root.add_child(world)
	world.region = NavigationRegion3D.new()
	world.region.name = "Nav"
	world.add_child(world.region)
	world.add_box(Vector3(0.0, -0.1, 0.0), Vector3(floor_size.x, 0.2, floor_size.y))
	return world


## A static box on the world layer (walls, shelves) under the navigation region.
func add_box(center: Vector3, size: Vector3, layer := Catalog.LAYER_WORLD) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	region.add_child(body)
	body.global_position = center
	return body


func add_zone(zone_id: StringName, center: Vector3, size: Vector3) -> StoreZone:
	var zone := StoreZone.new()
	zone.zone_id = zone_id
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	zone.add_child(shape)
	add_child(zone)
	zone.global_position = center
	return zone


func add_marker(group: StringName, at: Vector3) -> Marker3D:
	var marker := Marker3D.new()
	marker.add_to_group(group)
	add_child(marker)
	marker.global_position = at
	return marker


## The foundation Player stub (with a controllable noise level) plus a Camera3D
## at eye height looking at `look_target`.
func add_player(at: Vector3, look_target: Vector3) -> Player:
	var player: Player = FakePlayer.new()
	player.name = "Player"
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	player.add_child(shape)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.fov = 95.0
	camera.position.y = 1.6
	player.add_child(camera)
	add_child(player)
	player.global_position = at
	aim_player(player, look_target)
	return player


func aim_player(player: Player, look_target: Vector3) -> void:
	var camera := player.get_node(^"Camera3D") as Camera3D
	var flat := Vector3(look_target.x, camera.global_position.y, look_target.z)
	if flat.distance_to(camera.global_position) > 0.01:
		camera.look_at(flat, Vector3.UP)


func add_monster(at: Vector3) -> Monster:
	var monster: Monster = (load(MONSTER_SCENE) as PackedScene).instantiate()
	add_child(monster)
	monster.global_position = at
	return monster


func add_coworker(employee_name: String, at: Vector3, task_source: Object = null) -> Coworker:
	var coworker: Coworker = (load(COWORKER_SCENE) as PackedScene).instantiate()
	coworker.employee_name = employee_name
	coworker.task_source = task_source
	add_child(coworker)
	coworker.global_position = at
	return coworker


func add_station(at: Vector3, zone: StringName, title: String) -> TaskStation:
	var station := TaskStation.new()
	station.zone = zone
	station.title = title
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	shape.shape = box
	station.add_child(shape)
	add_child(station)
	station.global_position = at
	return station


## Bakes the navmesh from the static colliders. 0.5/2.0 is what radius 0.4 and
## height 1.8 round up to on the default 0.25 m cells (without the bake warnings).
func bake_navigation() -> void:
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = Catalog.LAYER_WORLD
	mesh.agent_radius = 0.5
	mesh.agent_height = 2.0
	region.navigation_mesh = mesh
	region.bake_navigation_mesh(false)


## Waits until the (asynchronous) navigation map has the baked polygons.
func settle_navigation() -> void:
	for i in 60:
		await tree.physics_frame
		if AiNav.is_ready(get_world_3d().navigation_map, Vector3.ZERO):
			return
	push_error("navigation map never became ready")


## Lets physics register new bodies and the navigation map sync.
func settle(frames := 3) -> void:
	for i in frames:
		await tree.physics_frame


## Leaves the tree now (groups, signals) and frees at the end of the frame.
func dispose() -> void:
	GameState.player = null
	GameState.monster = null
	if is_inside_tree():
		get_parent().remove_child(self)
	queue_free()
