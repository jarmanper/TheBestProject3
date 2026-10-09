extends SceneTree
## Dumps every walkie/intercom line (VoiceLines.enumerate_all) as JSON to the path after "--".
##   godot --headless --path . -s res://art_source/voice/dump_lines.gd -- out.json


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var out_path := args[0] if not args.is_empty() else "user://voice_lines.json"
	var lines: Array = load("res://systems/shared/voice_lines.gd").enumerate_all()
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(lines, "\t"))
	file.close()
	print("dumped %d lines to %s" % [lines.size(), out_path])
	quit(0)
