extends SceneTree
## Screenshot helper for the Store Environment sandbox.
## godot --path . --rendering-driver opengl3 --resolution 1280x720 -s res://tools/shots/shot_env_sandbox.gd

const OUT_PATH := "user://env_sandbox.png"


func _initialize() -> void:
	var scene := load("res://systems/environment/sandbox/env_sandbox.tscn") as PackedScene
	var instance := scene.instantiate()
	root.add_child(instance)
	_wait_and_shoot.call_deferred()


func _wait_and_shoot() -> void:
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(OUT_PATH)
	print("Saved screenshot to %s" % ProjectSettings.globalize_path(OUT_PATH))
	quit()
