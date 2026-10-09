extends SceneTree
## Screenshots of the final store in the real game (HUD + CRT). Options and logic in
## level_shot_util.gd. PNGs go to <project>/.superpowers/shots/ unless --out is given.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await load("res://tools/shots/level_shot_util.gd").run(self)
