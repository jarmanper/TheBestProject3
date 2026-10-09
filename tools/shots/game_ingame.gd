extends SceneTree
## Screenshot: ingame. Logic and options in game_shot_util.gd.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await load("res://tools/shots/game_shot_util.gd").run(self, "ingame")
