extends SceneTree
## Shared helpers for the character screenshot scripts (tools/shots/characters_*.gd).
## Subclasses override build(). Run (needs a display, e.g. WSLg):
##   godot --path . --rendering-driver opengl3 --resolution 960x540 \
##       -s res://tools/shots/characters_lineup.gd -- --out=/abs/path/shot.png
## Common user args: --out=PATH  --half_res=1 (3D at half resolution, nearest upscale, like the game)

const MODELS := {
	"employee_dale": "res://assets/models/characters/employee_dale.glb",
	"employee_rita": "res://assets/models/characters/employee_rita.glb",
	"employee_marcus": "res://assets/models/characters/employee_marcus.glb",
	"manager": "res://assets/models/characters/manager.glb",
	"monster": "res://assets/models/characters/monster.glb",
}

var args := {}
var world: Node3D
var camera: Camera3D
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var kv := arg.trim_prefix("--").split("=", true, 1)
			args[kv[0]] = kv[1]
	_rng.seed = 7
	_run.call_deferred()


func _run() -> void:
	_setup_world(arg_bool("half_res", false))
	build()
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := arg_str("out", "user://characters_shot.png")
	var image := root.get_texture().get_image()
	var err := image.save_png(path)
	print("saved %s (%s)" % [path, error_string(err)])
	quit()


## Override in shot scripts.
func build() -> void:
	pass


func arg_str(key: String, default: String) -> String:
	return String(args.get(key, default))


func arg_float(key: String, default: float) -> float:
	return float(args.get(key, str(default)))


func arg_bool(key: String, default: bool) -> bool:
	if not args.has(key):
		return default
	return String(args[key]) in ["1", "true", "yes"]


func _setup_world(half_res: bool) -> void:
	if not half_res:
		world = Node3D.new()
		root.add_child(world)
		return
	var layer := CanvasLayer.new()
	layer.layer = -1
	root.add_child(layer)
	var container := SubViewportContainer.new()
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.add_child(container)
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.stretch_shrink = 2
	var viewport := SubViewport.new()
	container.add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)


func make_environment(ambient: Color, ambient_energy: float, fog_density := 0.0,
		fog_color := Color("0b0d0c")) -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0b0d0c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient
	env.ambient_light_energy = ambient_energy
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	if fog_density > 0.0:
		env.fog_enabled = true
		env.fog_light_color = fog_color
		env.fog_density = fog_density
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	world.add_child(world_env)
	return env


func make_camera(position: Vector3, target: Vector3, fov := 70.0) -> Camera3D:
	camera = Camera3D.new()
	camera.fov = fov
	camera.near = 0.05
	world.add_child(camera)
	camera.position = position
	camera.look_at(target, Vector3.UP)
	camera.current = true
	return camera


func omni(position: Vector3, color: Color, energy: float, radius: float, shadows := false) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius
	light.omni_attenuation = 1.2
	light.shadow_enabled = shadows
	light.shadow_bias = 0.08
	light.shadow_normal_bias = 2.5
	world.add_child(light)
	light.position = position
	return light


func spot(position: Vector3, target: Vector3, color: Color, energy: float, radius: float, angle: float,
		shadows := false) -> SpotLight3D:
	var light := SpotLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.spot_range = radius
	light.spot_angle = angle
	light.shadow_enabled = shadows
	light.shadow_bias = 0.08
	light.shadow_normal_bias = 2.5
	world.add_child(light)
	light.position = position
	light.look_at(target, Vector3.UP if absf((target - position).normalized().y) < 0.99 else Vector3.FORWARD)
	return light


func box(position: Vector3, size: Vector3, color: Color, emission := 0.0, roughness := 0.9) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	world.add_child(instance)
	instance.position = position
	return instance


## Instances a character, plays `anim` and freezes it at `time` seconds. yaw in degrees
## (0 = facing +Z, toward a camera placed at +Z).
func add_character(model: String, position: Vector3, yaw := 0.0, anim := "idle", time := 0.0) -> Node3D:
	var path: String = MODELS.get(model, model)
	if not ResourceLoader.exists(path):
		push_warning("missing model %s" % path)
		return null
	var instance := (load(path) as PackedScene).instantiate() as Node3D
	world.add_child(instance)
	instance.position = position
	instance.rotation_degrees.y = yaw
	var player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player != null and player.has_animation(anim):
		player.play(anim)
		player.seek(time, true)
		player.pause()
	return instance


## Floor of dark wet tiles (checker texture, nearest filtered).
func tile_floor(center: Vector3, size: Vector2, tile := 0.6) -> void:
	var image := Image.create(16, 16, false, Image.FORMAT_RGB8)
	for y in 16:
		for x in 16:
			var odd := ((x / 8) + (y / 8)) % 2 == 1
			var c := Color("2b302f") if odd else Color("252928")
			if x % 8 == 0 or y % 8 == 0:
				c = Color("151817")
			c = c.lightened(_rng.randf_range(-0.04, 0.04))
			image.set_pixel(x, y, c)
	var texture := ImageTexture.create_from_image(image)
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 0.25
	material.metallic_specular = 0.7
	material.uv1_scale = Vector3(size.x / (tile * 2.0), size.y / (tile * 2.0), 1.0)
	var mesh := PlaneMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	world.add_child(instance)
	instance.position = center


## A gondola shelf run along Z with random product boxes. side = +1 shelf faces -X, -1 faces +X.
func shelf_run(x: float, z_from: float, z_to: float, side: float, height := 2.2, depth := 0.6,
		levels := 5) -> void:
	var length := absf(z_to - z_from)
	var zc := (z_from + z_to) * 0.5
	box(Vector3(x + side * depth * 0.5, height * 0.5, zc), Vector3(0.05, height, length), Color("2d332f"))
	for level in levels:
		var y := 0.15 + level * (height - 0.25) / float(levels - 1)
		box(Vector3(x, y, zc), Vector3(depth, 0.03, length), Color("4f5a4c"))
		if level == levels - 1:
			continue
		var z := minf(z_from, z_to) + 0.05
		var palette := [Color("b8432f"), Color("d8a33a"), Color("3f6fa8"), Color("e3dcc0"), Color("6f8a3a"),
			Color("8a3a6a"), Color("c96a2a")]
		while z < maxf(z_from, z_to) - 0.2:
			var w := _rng.randf_range(0.14, 0.32)
			var h := _rng.randf_range(0.16, 0.36)
			var d := _rng.randf_range(0.2, depth * 0.9)
			if _rng.randf() > 0.12:
				var c: Color = palette[_rng.randi() % palette.size()]
				c = c.lerp(Color("6a6a5a"), 0.45).darkened(_rng.randf_range(0.35, 0.6))
				box(Vector3(x - side * (depth - d) * 0.5 + side * 0.02, y + 0.015 + h * 0.5, z + w * 0.5),
					Vector3(d, h, w), c)
			z += w + _rng.randf_range(0.01, 0.05)


## Fluorescent ceiling fixture: emissive tube box plus a light below it.
func fluorescent(position: Vector3, energy := 2.2, radius := 7.0, along_z := true) -> void:
	var size := Vector3(0.18, 0.06, 1.3) if along_z else Vector3(1.3, 0.06, 0.18)
	box(position, size, Color("e8e6d0"), 3.0)
	omni(position + Vector3(0, -0.25, 0), Color("d8d8c0"), energy, radius, true)
