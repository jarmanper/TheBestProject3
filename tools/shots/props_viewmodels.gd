extends SceneTree
## First-person viewmodel check: each vm_*.glb is instanced at the origin of a Camera3D
## (FOV 95, near 0.02, looking down -Z) at eye height 1.6 m in a dim aisle with a flashlight,
## the way the Player holds it.
##   godot --path . --rendering-driver opengl3 --resolution 960x540 -s res://tools/shots/props_viewmodels.gd -- --out=/abs/dir
## Options: --lit adds a fill light near the hand (to inspect the model); --half renders the 3D
## at half resolution with nearest upscaling like the game (stretch_shrink 2).
## Writes vm_<name>.png (vm_<name>_lit.png / vm_<name>_half.png with the options).

const VIEWMODELS := ["vm_flashlight", "vm_mop", "vm_price_gun", "vm_box_cutter", "vm_stock_box", "vm_keys"]

var _out := "user://shots"
var _lit := false
var _half := false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg == "--lit":
			_lit = true
		elif arg == "--half":
			_half = true
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	var holder: Node = root
	if _half:
		var container := SubViewportContainer.new()
		container.stretch = true
		container.stretch_shrink = 2
		container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(container)
		var viewport := SubViewport.new()
		container.add_child(viewport)
		holder = viewport
	var stage := _make_aisle()
	holder.add_child(stage)
	var camera := Camera3D.new()
	camera.fov = 95.0
	camera.near = 0.02
	camera.position = Vector3(0.0, 1.6, 0.0)
	stage.add_child(camera)
	camera.current = true
	var flashlight := SpotLight3D.new()
	flashlight.light_color = Color("fff1d6")
	flashlight.light_energy = 1.2
	flashlight.spot_range = 18.0
	flashlight.spot_angle = 28.0
	camera.add_child(flashlight)
	if _lit:
		var fill := OmniLight3D.new()
		fill.light_energy = 0.8
		fill.omni_range = 1.6
		fill.position = Vector3(-0.3, 0.3, 0.1)
		camera.add_child(fill)
	var suffix := "_lit" if _lit else ("_half" if _half else "")
	for vm: String in VIEWMODELS:
		var node := (load("res://assets/models/viewmodels/%s.glb" % vm) as PackedScene).instantiate() as Node3D
		camera.add_child(node)
		for i in 10:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := _out.path_join("%s%s.png" % [vm, suffix])
		root.get_texture().get_image().save_png(path)
		print("saved ", path)
		node.free()
	quit()


## A store aisle like reference 2: wet dark floor, two shelf rows, back wall, dim ceiling lights.
func _make_aisle() -> Node3D:
	var stage := Node3D.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0b0e0d")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("4d5a55")
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	stage.add_child(world_env)
	stage.add_child(_box(Vector3(0, -0.05, -8), Vector3(8, 0.1, 24), Color("3d4442"), 0.25))
	for x in [-1.9, 1.9]:
		stage.add_child(_box(Vector3(x, 1.1, -8), Vector3(1.2, 2.2, 20), Color("4a5248"), 0.8))
	stage.add_child(_box(Vector3(0, 2, -18), Vector3(8, 4, 0.2), Color("2f3532"), 0.9))
	for z in [-1.0, -5.0, -10.0]:
		var lamp := OmniLight3D.new()
		lamp.light_color = Color("d8e2d4")
		lamp.light_energy = 1.4
		lamp.omni_range = 6.5
		lamp.position = Vector3(0, 3.3, z)
		stage.add_child(lamp)
	return stage


func _box(centre: Vector3, size: Vector3, color: Color, roughness: float) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.position = centre
	return mesh_instance
