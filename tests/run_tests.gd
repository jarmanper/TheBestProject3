extends SceneTree
## Headless test runner.
##   godot --headless --path . -s res://tests/run_tests.gd [-- --filter=substring]
## Runs every `test_*` method of every tests/**/test_*.gd script that extends TestCase.
## Exit code 0 when all pass, 1 otherwise.

var _filter := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			_filter = arg.trim_prefix("--filter=")
	_run.call_deferred()


func _run() -> void:
	# Autoloads are added after _initialize; wait one frame so they exist.
	await process_frame
	var files := _find_tests("res://tests")
	files.sort()
	var passed := 0
	var failed := 0
	for path in files:
		if not _filter.is_empty() and not path.contains(_filter):
			continue
		var script := load(path) as GDScript
		if script == null:
			print("LOAD FAIL  %s" % path)
			failed += 1
			continue
		for method in script.get_script_method_list():
			var name: String = method.name
			if not name.begins_with("test_"):
				continue
			var test: TestCase = script.new()
			test.tree = self
			await test.before_each()
			await test.call(name)
			await test.after_each()
			if test.failures.is_empty():
				passed += 1
				print("PASS  %s :: %s" % [path.get_file(), name])
			else:
				failed += 1
				print("FAIL  %s :: %s" % [path.get_file(), name])
				for message in test.failures:
					print("      - %s" % message)
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _find_tests(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	for sub in dir.get_directories():
		found.append_array(_find_tests(dir_path.path_join(sub)))
	for file in dir.get_files():
		if file.begins_with("test_") and file.ends_with(".gd") and file != "test_case.gd":
			found.append(dir_path.path_join(file))
	return found
