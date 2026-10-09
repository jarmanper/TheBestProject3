class_name StationLayout
extends RefCounted
## Data table for the night's 13 task stations: kind, zone, title, tool, hold
## time and manager line, with a Godot position/yaw consistent with
## docs/ARCHITECTURE.md §7. Levels and the sandbox scene build their stations
## from this table instead of duplicating placement by hand.
##
## Placement (fitted to the final store art, levels/store): `position` is the
## thing being worked on (shelf face, spill, register, breaker...) at floor
## level, and `yaw_degrees` turns the station's +Z toward where the worker
## stands — each station scene's WorkPoint sits 0.9 m along +Z.
##
## `basic_task = false` marks the two stations only the Store Manager ever
## assigns (the breaker and the safe) — they never show up in the nightly
## random basic six.

const STATIONS := [
	{
		"kind": &"mop_spill", "zone": &"aisle_3", "title": "Mop the spill in Aisle 3",
		"tool": &"mop", "hold_time": 4.0, "basic_task": true,
		"manager_line": "Clean up on aisle three, someone's going to slip.",
		"position": Vector3(-6.0, 0.0, 1.0), "yaw_degrees": 0.0,
		"scene": "res://systems/environment/stations/station_spill.tscn",
	},
	{
		"kind": &"mop_spill", "zone": &"produce", "title": "Mop the spill in Produce",
		"tool": &"mop", "hold_time": 4.0, "basic_task": true,
		"manager_line": "There's a spill out by produce, grab the mop.",
		"position": Vector3(11.0, 0.0, 0.0), "yaw_degrees": 0.0,
		"scene": "res://systems/environment/stations/station_spill.tscn",
	},
	{
		"kind": &"restock", "zone": &"aisle_2", "title": "Restock the shelves in Aisle 2",
		"tool": &"stock_box", "hold_time": 3.5, "basic_task": true,
		"manager_line": "Aisle two is looking bare, bring out a box.",
		"position": Vector3(-11.3, 0.0, 4.0), "yaw_degrees": 90.0,
		"scene": "res://systems/environment/stations/station_restock.tscn",
	},
	{
		"kind": &"restock", "zone": &"aisle_4", "title": "Restock the shelves in Aisle 4",
		"tool": &"stock_box", "hold_time": 3.5, "basic_task": true,
		"manager_line": "Aisle four needs restocking when you get a chance.",
		"position": Vector3(-0.7, 0.0, 0.5), "yaw_degrees": -90.0,
		"scene": "res://systems/environment/stations/station_restock.tscn",
	},
	{
		"kind": &"face_shelf", "zone": &"aisle_1", "title": "Face the shelves in Aisle 1",
		"tool": &"", "hold_time": 3.0, "basic_task": true,
		"manager_line": "Aisle one's a mess, square it away.",
		"position": Vector3(-15.3, 0.0, 2.0), "yaw_degrees": 90.0,
		"scene": "res://systems/environment/stations/station_face_shelf.tscn",
	},
	{
		"kind": &"register", "zone": &"checkout", "title": "Count Register 1",
		"tool": &"", "hold_time": 4.0, "basic_task": true,
		"manager_line": "Register one needs to be counted out.",
		"position": Vector3(-11.55, 0.0, 12.8), "yaw_degrees": 90.0,
		"scene": "res://systems/environment/stations/station_register.tscn",
	},
	{
		"kind": &"register", "zone": &"checkout", "title": "Count Register 2",
		"tool": &"", "hold_time": 4.0, "basic_task": true,
		"manager_line": "Register two still needs counting.",
		"position": Vector3(-6.55, 0.0, 12.8), "yaw_degrees": 90.0,
		"scene": "res://systems/environment/stations/station_register.tscn",
	},
	{
		"kind": &"price_update", "zone": &"dairy", "title": "Update price labels in Dairy",
		"tool": &"price_gun", "hold_time": 3.0, "basic_task": true,
		"manager_line": "Dairy prices changed, re-tag the shelf labels.",
		"position": Vector3(-8.0, 0.0, -5.05), "yaw_degrees": 0.0,
		"scene": "res://systems/environment/stations/station_price.tscn",
	},
	{
		"kind": &"freezer_log", "zone": &"frozen", "title": "Log the freezer temperature",
		"tool": &"", "hold_time": 3.0, "basic_task": true,
		"manager_line": "Don't forget the freezer temperature log.",
		"position": Vector3(-19.2, 0.0, 2.0), "yaw_degrees": 90.0,
		"scene": "res://systems/environment/stations/station_freezer_log.tscn",
	},
	{
		"kind": &"boxes", "zone": &"storage", "title": "Break down boxes in Storage",
		"tool": &"box_cutter", "hold_time": 4.0, "basic_task": true,
		"manager_line": "Storage room's piling up, break those boxes down.",
		"position": Vector3(-2.6, 0.0, -12.0), "yaw_degrees": 180.0,
		"scene": "res://systems/environment/stations/station_boxes.tscn",
	},
	{
		"kind": &"trash", "zone": &"break_room", "title": "Empty the break room trash",
		"tool": &"", "hold_time": 3.0, "basic_task": true,
		"manager_line": "Break room trash is overflowing again.",
		"position": Vector3(9.4, 0.0, -9.6), "yaw_degrees": 180.0,
		"scene": "res://systems/environment/stations/station_trash.tscn",
	},
	{
		"kind": &"breaker", "zone": &"hallway", "title": "Reset the breaker",
		"tool": &"keys", "hold_time": 5.0, "basic_task": false,
		"manager_line": "The breaker tripped, go reset it before we lose the lights.",
		"position": Vector3(0.0, 1.5, -8.9), "yaw_degrees": 0.0,
		"scene": "res://systems/environment/stations/station_breaker.tscn",
	},
	{
		"kind": &"safe", "zone": &"service_desk", "title": "Lock the safe",
		"tool": &"keys", "hold_time": 5.0, "basic_task": false,
		"manager_line": "Lock up the safe at the service desk before it's too late.",
		"position": Vector3(13.4, 0.0, 15.1), "yaw_degrees": 180.0,
		"scene": "res://systems/environment/stations/station_safe.tscn",
	},
]


## Instantiates every station in the table under `parent`. Returns the spawned nodes.
static func spawn_all(parent: Node) -> Array[TaskStation]:
	var spawned: Array[TaskStation] = []
	for entry in STATIONS:
		spawned.append(spawn_one(parent, entry))
	return spawned


static func spawn_one(parent: Node, entry: Dictionary) -> TaskStation:
	var scene: PackedScene = Catalog.load_scene_or_null(entry["scene"])
	var station: TaskStation
	if scene:
		station = scene.instantiate()
	else:
		station = TaskStation.new()
		station.add_child(_fallback_shape())
	station.task_kind = entry["kind"]
	station.zone = entry["zone"]
	station.title = entry["title"]
	station.required_tool = entry["tool"]
	station.hold_time = entry["hold_time"]
	station.basic_task = entry["basic_task"]
	station.manager_line = entry["manager_line"]
	station.name = "Station_%s_%s" % [entry["kind"], entry["zone"]]
	parent.add_child(station)
	station.global_position = entry["position"]
	station.rotation_degrees.y = entry["yaw_degrees"]
	return station


static func _fallback_shape() -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.6, 1.0)
	shape.shape = box
	shape.position.y = 0.8
	return shape
