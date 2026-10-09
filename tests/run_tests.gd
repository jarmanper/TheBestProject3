extends SceneTree
## Headless test runner.
##   godot --headless --path . -s res://tests/run_tests.gd [-- --filter=substring]
## Runs every `test_*` method of every tests/**/test_*.gd script that extends TestCase.
## A test fails on a failed assertion or on any engine/script error logged while it
## runs (warnings are allowed). A test file that fails to load or parse is a failure.
## Exit code 0 when all pass, 1 otherwise.


## Collects errors logged by the engine (script errors, push_error) during a test.
class ErrorCatcher extends Logger:
	var errors: Array[String] = []

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		var text := rationale if not rationale.is_empty() else code
		errors.append("%s (%s:%d)" % [text, file, line])

	func _log_message(_message: String, _error: bool) -> void:
		pass


var _filter := ""
var _catcher := ErrorCatcher.new()


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			_filter = arg.trim_prefix("--filter=")
	OS.add_logger(_catcher)
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
		_catcher.errors.clear()
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			print("LOAD FAIL  %s" % path)
			for message in _catcher.errors:
				print("      - %s" % message)
			failed += 1
			continue
		for method in script.get_script_method_list():
			var name: String = method.name
			if not name.begins_with("test_"):
				continue
			_catcher.errors.clear()
			var test: TestCase = script.new()
			test.tree = self
			await test.before_each()
			await test.call(name)
			await test.after_each()
			var problems: Array[String] = test.failures.duplicate()
			for message in _catcher.errors:
				problems.append("engine error: " + message)
			if problems.is_empty():
				passed += 1
				print("PASS  %s :: %s" % [path.get_file(), name])
			else:
				failed += 1
				print("FAIL  %s :: %s" % [path.get_file(), name])
				for message in problems:
					print("      - %s" % message)
	print("\n%d passed, %d failed" % [passed, failed])
	OS.remove_logger(_catcher)
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
