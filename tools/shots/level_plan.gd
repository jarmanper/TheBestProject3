extends SceneTree
## Plan view of the store level: ceilings hidden, flat light, the baked navmesh drawn in
## translucent green, and gameplay markers as coloured posts (white = player spawn, orange =
## coworker spawns, red = monster spawn, blue = manager spot, yellow = patrol points,
## cyan = station work points, magenta = hiding exit points).
##   ~/tools/godot/godot --path . --rendering-driver opengl3 --resolution 1600x1280 \
##       -s res://tools/shots/level_plan.gd -- --out=/abs/plan.png [--center=x,z --size=metres]

const LEVEL := "res://levels/store/store.tscn"


func _arg(arg_name: String, default_value: String) -> String:
	for item in OS.get_cmdline_user_args():
		if item.begins_with("--%s=" % arg_name):
			return item.trim_prefix("--%s=" % arg_name)
	return default_value


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var level := (load(LEVEL) as PackedScene).instantiate() as Node3D
	root.add_child(level)
	await process_frame
	# Seen from 40 m up: no area culling, no draw distance.
	var culler := level.get_node_or_null("AreaCuller")
	if culler:
		culler.set(&"enabled", false)
	for geometry in level.find_children("*", "GeometryInstance3D", true, false):
		(geometry as GeometryInstance3D).visibility_range_end = 0.0
	for node in level.find_children("*", "Node3D", true, false):
		var node_name := String(node.name)
		if node_name.begins_with("Ceiling") or node_name.begins_with("Fixture") or node_name.begins_with("Cable") \
				or node_name.begins_with("Sign_") or node_name.begins_with("Pipes"):
			(node as Node3D).visible = false
	for light in level.find_children("*", "Light3D", true, false):
		(light as Light3D).visible = false
	var world_env := level.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env:
		world_env.queue_free()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.9
	var flat := WorldEnvironment.new()
	flat.environment = env
	root.add_child(flat)

	var region := level.get_node("NavigationRegion3D") as NavigationRegion3D
	_draw_navmesh(region.navigation_mesh)
	_posts(&"player_spawn", Color.WHITE, 0.35)
	_posts(&"coworker_spawn", Color(1.0, 0.5, 0.1), 0.3)
	_posts(&"monster_spawn", Color.RED, 0.35)
	_posts(&"manager_spot", Color(0.2, 0.4, 1.0), 0.3)
	_posts(&"patrol_point", Color.YELLOW, 0.2)
	for station in get_nodes_in_group(&"task_station"):
		_post(station.call(&"get_work_position"), Color.CYAN, 0.2)
	for spot in get_nodes_in_group(&"hiding_spot"):
		_post(spot.call(&"get_exit_position"), Color.MAGENTA, 0.2)

	var center := _arg("center", "0,0").split(",")
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = float(_arg("size", "33"))
	camera.far = 100.0
	root.add_child(camera)
	camera.global_position = Vector3(float(center[0]), 40.0, float(center[1]))
	camera.rotation_degrees = Vector3(-90, 0, 0)
	camera.current = true
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var out := _arg("out", ProjectSettings.globalize_path("res://.superpowers/shots/level_plan.png"))
	var err := root.get_texture().get_image().save_png(out)
	print("saved %s (%s)" % [out, error_string(err)])
	quit()


func _draw_navmesh(navmesh: NavigationMesh) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in navmesh.get_polygon_count():
		var poly := navmesh.get_polygon(p)
		for k in range(1, poly.size() - 1):
			for index in [poly[0], poly[k], poly[k + 1]]:
				mesh.surface_add_vertex(navmesh.vertices[index] + Vector3.UP * 0.05)
	mesh.surface_end()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.1, 1.0, 0.3, 0.35)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	root.add_child(instance)


func _posts(group: StringName, color: Color, radius: float) -> void:
	for node in get_nodes_in_group(group):
		_post((node as Node3D).global_position, color, radius)


func _post(position: Vector3, color: Color, radius: float) -> void:
	var post := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = 6.0
	post.mesh = cylinder
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	post.material_override = material
	root.add_child(post)
	post.global_position = position + Vector3.UP * 3.0
