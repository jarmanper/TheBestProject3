extends Node3D
## Manual QA sandbox: spawns a sample of stations, tools, hiding spots and
## store lights to eyeball. Not part of the shipped level.

const TOOL_IDS: Array[StringName] = [&"mop", &"price_gun", &"box_cutter", &"stock_box", &"keys"]
const HIDING_SCENES := {
	&"locker": "res://systems/environment/hiding/hide_locker.tscn",
	&"counter": "res://systems/environment/hiding/hide_counter.tscn",
	&"boxes": "res://systems/environment/hiding/hide_boxes.tscn",
}


func _ready() -> void:
	_add_floor()
	_add_environment()
	var stations := StationLayout.spawn_all(self)
	_activate_a_few_for_display(stations)
	_spawn_tools()
	_spawn_hiding_spots()
	_spawn_store_lights()
	_spawn_markers()
	_add_camera()


## Shows a handful of stations' ActiveVisual as "in progress" so there is
## something to look at besides bare collision boxes. Bypasses the Tasks
## autoload entirely (TaskStation.set_task only needs a TaskData).
func _activate_a_few_for_display(stations: Array[TaskStation]) -> void:
	for i in mini(4, stations.size()):
		var task := TaskData.new()
		task.title = stations[i].title
		stations[i].set_task(task)


func _add_floor() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Catalog.LAYER_WORLD
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(44.0, 0.2, 34.0)
	shape.shape = box
	shape.position.y = -0.1
	body.add_child(shape)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box.size
	mesh_instance.mesh = mesh
	mesh_instance.position.y = -0.1
	var material := StandardMaterial3D.new()
	material.albedo_color = Catalog.COLOR_CONCRETE
	mesh_instance.material_override = material
	body.add_child(mesh_instance)
	add_child(body)


func _add_environment() -> void:
	var env_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Catalog.COLOR_CHARCOAL
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.45, 0.45, 0.48)
	environment.ambient_light_energy = 1.1
	env_node.environment = environment
	add_child(env_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.light_energy = 0.5
	sun.shadow_enabled = false
	add_child(sun)


func _spawn_tools() -> void:
	for i in TOOL_IDS.size():
		var tool_id: StringName = TOOL_IDS[i]
		var scene := Catalog.load_scene_or_null("res://systems/environment/tools/pickup_%s.tscn" % tool_id)
		var pickup: ToolPickup = scene.instantiate() if scene else ToolPickup.new()
		pickup.tool_id = tool_id
		add_child(pickup)
		pickup.global_position = Vector3(-16.0 + i * 3.0, 1.0, 9.5)


func _spawn_hiding_spots() -> void:
	var i := 0
	for kind: StringName in HIDING_SCENES:
		var scene := Catalog.load_scene_or_null(HIDING_SCENES[kind])
		var spot: HidingSpot = scene.instantiate() if scene else HidingSpot.new()
		spot.spot_kind = kind
		add_child(spot)
		spot.global_position = Vector3(-16.0 + i * 5.0, 0.0, -14.0)
		i += 1


func _spawn_store_lights() -> void:
	var scene := Catalog.load_scene_or_null("res://systems/environment/store_light.tscn")
	for i in 3:
		var light: Node3D = scene.instantiate() if scene else StoreLight.new()
		add_child(light)
		light.global_position = Vector3(-8.0 + i * 8.0, 3.8, 2.0)
		if i == 2:
			light.always_flicker = true


func _spawn_markers() -> void:
	var player_spawn := Marker3D.new()
	player_spawn.add_to_group(&"player_spawn")
	add_child(player_spawn)
	player_spawn.position = Vector3(0.0, 0.0, 14.0)

	var manager_spot := Marker3D.new()
	manager_spot.add_to_group(&"manager_spot")
	add_child(manager_spot)
	manager_spot.position = Vector3(13.0, 0.0, -12.0)

	var speaker := AudioStreamPlayer3D.new()
	speaker.add_to_group(&"intercom_speaker")
	add_child(speaker)
	speaker.position = Vector3(0.0, 3.5, 0.0)


func _add_camera() -> void:
	var camera := Camera3D.new()
	add_child(camera)
	camera.fov = 70.0
	camera.position = Vector3(-4.0, 28.0, 14.0)
	camera.look_at(Vector3(-4.0, 0.0, -2.0), Vector3.UP)
	camera.current = true
