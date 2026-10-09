extends SceneTree
## Headless soak run of the AI sandbox: starts the night at --hour, runs --frames
## fixed frames and prints the sandbox log (monster states, walkie, intercom,
## abductions) plus a monster summary every 30 s of game time.
##   godot --headless --path . --fixed-fps 60 -s res://systems/monster/sandbox/sandbox_soak.gd -- --hour=1.9 --frames=18000
## An intercom call to the storage room goes out 10 s in (GDD seam 1).

const SANDBOX := "res://systems/monster/sandbox/ai_sandbox.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var hour := 0.0
	var frames := 1200
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hour="):
			hour = arg.trim_prefix("--hour=").to_float()
		elif arg.begins_with("--frames="):
			frames = arg.trim_prefix("--frames=").to_int()
	var events := root.get_node(^"/root/Events")
	var game_state := root.get_node(^"/root/GameState")
	var sandbox: Node3D = (load(SANDBOX) as PackedScene).instantiate()
	sandbox.set(&"start_hour", hour)
	root.add_child(sandbox)
	for i in frames:
		await process_frame
		if i == 600:
			events.intercom_announced.emit("Could someone come to the storage room, please.", &"storage")
		if i % 1800 == 0 and is_instance_valid(game_state.monster):
			print("--- %s\n%s" % [game_state.get_clock_text(), game_state.monster.get_debug_text()])
			for coworker in sandbox.get_tree().get_nodes_in_group(&"coworker"):
				print("%s: %s" % [coworker.employee_name, coworker.state])
			var source: Variant = sandbox.get(&"task_source")
			if source != null:
				print("tasks done by coworkers: %d / %d" % [source.completed.size(), source.tasks.size()])
	print("--- end %s  stats %s" % [game_state.get_clock_text(), game_state.stats])
	sandbox.queue_free()
	await process_frame
	quit()
