extends SceneTree
## What the player sees while hidden: from inside the closed locker (looking out through the
## door's vent slits) and from the box-pile nook, with a lit room outside.
##   godot --path . --rendering-driver opengl3 --resolution 960x540 -s res://tools/shots/props_hide_views.gd -- --out=/abs/dir
## Writes props_hide_locker.png and props_hide_boxes.png.

## [prop, camera position (prop space), camera fov]
const VIEWS := {
	"locker": ["res://assets/models/props/locker.glb", Vector3(0.0, 1.56, -0.02), 80.0],
	"boxes": ["res://assets/models/props/box_pile_hide.glb", Vector3(0.0, 0.72, 0.0), 80.0],
}

var _out := "user://shots"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	for view: String in VIEWS:
		var spec: Array = VIEWS[view]
		var stage := Node3D.new()
		root.add_child(stage)
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color("0c0f0e")
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color("5a6660")
		env.ambient_light_energy = 0.2
		var world_env := WorldEnvironment.new()
		world_env.environment = env
		stage.add_child(world_env)
		var floor_mesh := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(20, 20)
		var floor_mat := StandardMaterial3D.new()
		floor_mat.albedo_color = Color("444a48")
		plane.material = floor_mat
		floor_mesh.mesh = plane
		stage.add_child(floor_mesh)
		for i in 3:
			var pillar := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.6, 2.4, 0.6)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color("6b6f5c")
			box.material = mat
			pillar.mesh = box
			pillar.position = Vector3(-1.5 + i * 1.5, 1.2, 3.5)
			stage.add_child(pillar)
		var lamp := OmniLight3D.new()
		lamp.light_color = Color("d8e2d4")
		lamp.light_energy = 1.6
		lamp.omni_range = 7.0
		lamp.position = Vector3(0.0, 2.8, 2.2)
		stage.add_child(lamp)
		var prop := (load(spec[0]) as PackedScene).instantiate() as Node3D
		stage.add_child(prop)
		var camera := Camera3D.new()
		camera.fov = spec[2]
		camera.near = 0.02
		camera.position = spec[1]
		camera.rotation.y = PI   # look toward +Z, out of the prop's front
		stage.add_child(camera)
		camera.current = true
		for i in 10:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := _out.path_join("props_hide_%s.png" % view)
		root.get_texture().get_image().save_png(path)
		print("saved ", path)
		stage.free()
	quit()
