extends RefCounted
## Shared setup for player tests: a floor under the tree root and a Player on it.
## Not a test file (no "test_" prefix), preload it from tests.

const PLAYER_SCENE := "res://systems/player/player.tscn"


## A Node3D under the root with a 40 x 40 m world-layer floor at y = 0.
static func make_world(tree: SceneTree) -> Node3D:
	var world := Node3D.new()
	world.name = "PlayerTestWorld"
	tree.root.add_child(world)
	add_box(world, Vector3(0, -0.1, 0), Vector3(40, 0.2, 40))
	return world


static func add_player(world: Node3D, position := Vector3.ZERO) -> Player:
	var player: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	player.position = position
	world.add_child(player)
	return player


## A static world-layer box (walls, floors) centred at `center`.
static func add_box(parent: Node3D, center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Catalog.LAYER_WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	parent.add_child(body)
	return body


## A stub HidingSpot with HidePoint/ExitPoint markers.
static func add_hiding_spot(parent: Node3D, position: Vector3, kind := &"locker") -> HidingSpot:
	var spot := HidingSpot.new()
	spot.spot_kind = kind
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 1.9, 0.6)
	shape.shape = box
	shape.position = Vector3(0, 0.95, 0)
	spot.add_child(shape)
	var hide_point := Marker3D.new()
	hide_point.name = "HidePoint"
	hide_point.position = Vector3(0, 1.5, 0)
	spot.add_child(hide_point)
	var exit_point := Marker3D.new()
	exit_point.name = "ExitPoint"
	exit_point.position = Vector3(0, 0, 1.0)
	spot.add_child(exit_point)
	spot.position = position
	parent.add_child(spot)
	return spot
