extends SceneTree
## Screenshot of the AI sandbox from the player's eyes (needs a GPU-less GL context):
##   godot --path . --rendering-driver opengl3 --resolution 960x540 \
##     -s res://systems/monster/sandbox/sandbox_shot.gd -- --shot=roam --out=/abs/path.png
## Shots: roam (disguised monster and a coworker down an aisle), reveal (true form,
## mid-reveal in front of the player), overview (high view of the whole sandbox).

const SANDBOX := "res://systems/monster/sandbox/ai_sandbox.tscn"


func _initialize() -> void:
	create_timer(240.0).timeout.connect(quit.bind(1))   # never hang on a script error
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var shot := "roam"
	var out := "user://ai_sandbox_shot.png"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot = arg.trim_prefix("--shot=")
		elif arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	var sandbox: Node3D = (load(SANDBOX) as PackedScene).instantiate()
	sandbox.set(&"show_overlay", false)
	root.add_child(sandbox)
	for i in 5:
		await physics_frame
	var player := sandbox.get_node(^"Player") as Node3D
	var camera := player.find_children("*", "Camera3D", true, false)[0] as Camera3D
	# Untyped on purpose: Monster/Coworker scripts use autoloads, which a -s script
	# cannot reference at compile time.
	var monster := sandbox.get_node(^"Monster") as Node3D
	var rita := sandbox.get_node(^"CoworkerRita") as Node3D
	var dale := sandbox.get_node(^"CoworkerDale") as Node3D
	for actor: Node in [monster, rita, dale, sandbox.get_node(^"CoworkerMarcus")]:
		actor.set_physics_process(false)
	player.set_physics_process(false)
	match shot:
		"reveal":
			player.global_position = Vector3(-6, 0, 7.4)
			monster.global_position = Vector3(-6, 0, 3.0)
			monster.call(&"force_state", &"reveal")
			rita.global_position = Vector3(-10, 0, 1)
		"overview":
			player.global_position = Vector3(0, 9, 16)
			camera.rotation.x = deg_to_rad(-38)
			monster.global_position = Vector3(-6, 0, 2)
		_:
			player.global_position = Vector3(-6, 0, 7.4)
			monster.global_position = Vector3(-6.4, 0, 1.0)
			monster.look_at(Vector3(-4, 0, 1.0), Vector3.UP, true)   # facing the shelf: a tell
			rita.global_position = Vector3(-5.5, 0, 4.0)
			rita.look_at(Vector3(-5.5, 0, 9.5), Vector3.UP, true)
			dale.global_position = Vector3(-10, 0, -1)
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png(out)
	print("saved %s: %s" % [out, error_string(err)])
	quit()
