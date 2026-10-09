extends SceneTree
## Screenshot of the store environment from a named viewpoint, with TEMPORARY lights only
## (dim OmniLights at the LightAnchor_* empties, black environment, a flashlight SpotLight).
## The 3D view renders at half resolution and is upscaled with nearest filtering, like the game.
##
##   ~/tools/godot/godot --path . --rendering-driver opengl3 --resolution 960x540 \
##       -s res://tools/shots/environment_shot.gd -- --views=ref2,ref3 --outdir=/abs/dir [--prefix=env_] [--fov=95]
##       [--energy=1.0] [--atten=1.5] [--range=5.5] [--ambient=0.035] [--pattern=alternate] [--full]
##   (writes <outdir>/<prefix><view>.png). Defaults are the tuned "reference look" temporary lights.
##
## Views: ref1, ref2 (aisle 4 toward DAIRY), ref3 (storage toward EXIT), checkout, produce, hallway, frozen,
## dairy, service, entrance, employees, storage_door, and "top" (orthographic plan, ceilings hidden; put it last).

const STORE_PATH := "res://assets/models/environment/store_interior.glb"
const SIZE := Vector2i(960, 540)
const VIEWS := {
	"ref1": {"pos": Vector3(-2.2, 1.6, 6.0), "target": Vector3(-2.5, 1.45, -5.0)},
	"ref2": {"pos": Vector3(-2.25, 1.6, 7.4), "target": Vector3(-3.1, 1.4, -5.0)},
	"ref3": {"pos": Vector3(-9.9, 1.6, -13.05), "target": Vector3(-20.0, 1.45, -13.0)},
	"checkout": {"pos": Vector3(-16.0, 1.7, 8.0), "target": Vector3(-4.0, 1.0, 13.5)},
	"produce": {"pos": Vector3(3.0, 1.7, 8.5), "target": Vector3(15.0, 0.9, -3.0)},
	"hallway": {"pos": Vector3(18.5, 1.6, -7.5), "target": Vector3(-10.0, 1.4, -7.5)},
	"frozen": {"pos": Vector3(-17.9, 1.6, 8.5), "target": Vector3(-18.1, 1.4, -3.0)},
	"dairy": {"pos": Vector3(1.0, 1.6, -3.6), "target": Vector3(-12.0, 1.3, -5.6)},
	"service": {"pos": Vector3(15.0, 1.7, 5.0), "target": Vector3(11.0, 1.0, 13.5)},
	"entrance": {"pos": Vector3(1.3, 1.7, 8.0), "target": Vector3(-1.0, 1.3, 16.0)},
	"employees": {"pos": Vector3(4.0, 1.6, 4.0), "target": Vector3(7.2, 1.6, -6.0)},
	"storage_door": {"pos": Vector3(-5.2, 1.6, -7.0), "target": Vector3(-5.2, 1.2, -13.0)},
	"counter_close": {"pos": Vector3(-10.4, 1.25, 13.4), "target": Vector3(-12.0, 0.55, 11.7)},
	"desk_close": {"pos": Vector3(11.8, 1.35, 15.0), "target": Vector3(10.6, 0.5, 12.5)},
	"fixture_close": {"pos": Vector3(-2.4, 1.9, 5.2), "target": Vector3(-2.0, 3.4, 2.9)},
}
const MAX_LIGHTS := 30


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := _parse_args()
	var names: PackedStringArray = String(args.get("views", args.get("view", "ref2"))).split(",")
	var out_dir: String = args.get("outdir", "user://")
	var prefix: String = args.get("prefix", "environment_")
	var full := args.has("full")
	var vp := SubViewport.new()
	vp.size = SIZE if full else SIZE / 2
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_DISABLED
	root.add_child(vp)
	var store := (load(STORE_PATH) as PackedScene).instantiate() as Node3D
	vp.add_child(store)
	var cam := Camera3D.new()
	cam.fov = float(args.get("fov", "95"))
	cam.near = 0.05
	cam.far = 80.0
	vp.add_child(cam)
	cam.current = true
	_add_environment(vp, float(args.get("ambient", "0.035")))
	var flashlight := SpotLight3D.new()
	flashlight.light_color = Color(1.0, 0.95, 0.85)
	flashlight.light_energy = float(args.get("flash", "1.6"))
	flashlight.spot_range = 16.0
	flashlight.spot_angle = 24.0
	flashlight.spot_attenuation = 1.2
	flashlight.shadow_enabled = true
	flashlight.position = Vector3(0.25, -0.3, 0.0)
	cam.add_child(flashlight)
	var lights := Node3D.new()
	store.add_child(lights)
	for view_name in names:
		for l in lights.get_children():
			l.free()
		if view_name == "top":
			# orthographic plan view of the whole footprint, ceilings hidden, flat light
			for n in ["Ceilings", "Fixtures", "Signs"]:
				var g := store.find_child(n, false, false) as Node3D
				if g != null:
					g.visible = false
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = 34.0
			cam.position = Vector3(0.0, 30.0, 0.0)
			cam.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
			flashlight.visible = false
			var sun := DirectionalLight3D.new()
			sun.rotation = Vector3(-1.2, 0.4, 0.0)
			sun.light_energy = 1.2
			lights.add_child(sun)
		else:
			var view: Dictionary = VIEWS[view_name]
			cam.position = view.pos
			cam.look_at(view.target)
			_add_lights(store, lights, cam.position, float(args.get("energy", "1.0")), float(args.get("atten", "1.5")),
				args.get("pattern", "all") == "alternate", float(args.get("range", "5.5")))
		for i in 12:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		if not full:
			img.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_NEAREST)
		var path := out_dir.path_join("%s%s.png" % [prefix, view_name])
		var err := img.save_png(path)
		print("saved %s (%s)" % [path, error_string(err)])
	quit()


func _add_environment(parent: Node, ambient: float) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.62, 0.6)
	env.ambient_light_energy = ambient
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color(0.03, 0.035, 0.035)
	env.fog_density = 0.035
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)


## alternate: only every other fluorescent anchor is lit ("alternating bright and dark pools").
func _add_lights(store: Node, parent: Node3D, cam_pos: Vector3, energy_scale: float, atten: float, alternate: bool, sales_range: float) -> void:
	var anchors: Array[Node3D] = []
	_collect(store, anchors)
	anchors.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_to(cam_pos) < b.global_position.distance_to(cam_pos))
	var count := 0
	for a in anchors:
		if count >= MAX_LIGHTS:
			break
		var extras: Dictionary = a.get_meta(&"extras", {})
		var kind: String = extras.get("kind", "fluorescent")
		if alternate and kind == "fluorescent" and String(a.name).to_int() % 2 == 0:
			continue
		var light := OmniLight3D.new()
		match kind:
			"exit":
				light.light_color = Color(0.25, 1.0, 0.45)
				light.light_energy = 0.9
				light.omni_range = 3.5
			"emergency":
				light.light_color = Color(1.0, 0.18, 0.12)
				light.light_energy = 0.6
				light.omni_range = 5.0
			"cooler":
				light.light_color = Color(0.75, 0.88, 1.0)
				light.light_energy = 0.35
				light.omni_range = 3.0
			_:
				light.light_color = Color(0.86, 0.9, 0.8)
				light.light_energy = 1.25 if int(extras.get("broken", 0)) == 0 else 0.45
				light.omni_range = sales_range if float(extras.get("ceiling", 4.0)) > 3.5 else minf(sales_range, 5.0)
				light.omni_attenuation = atten
		light.light_energy *= energy_scale
		parent.add_child(light)
		light.global_position = a.global_position
		count += 1


func _collect(node: Node, out: Array[Node3D]) -> void:
	var n := String(node.name)
	if node is Node3D and (n.begins_with("LightAnchor_") or n.begins_with("EmergencyAnchor_") or n.begins_with("CoolerAnchor_") or n == "ExitAnchor"):
		out.append(node as Node3D)
	for c in node.get_children():
		_collect(c, out)


func _parse_args() -> Dictionary:
	var d := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var kv := arg.trim_prefix("--").split("=", true, 1)
			d[kv[0]] = kv[1] if kv.size() > 1 else "true"
	return d
