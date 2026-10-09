class_name TestCase
extends RefCounted
## Base class for tests run by tests/run_tests.gd.
## Define `func test_something() -> void:` methods; they may `await`.

var tree: SceneTree
var failures: Array[String] = []


## Optional per-test hooks.
func before_each() -> void:
	pass


func after_each() -> void:
	pass


func assert_true(condition: bool, message := "expected true") -> void:
	if not condition:
		_fail(message)


func assert_false(condition: bool, message := "expected false") -> void:
	if condition:
		_fail(message)


func assert_eq(actual: Variant, expected: Variant, message := "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		_fail("%s expected <%s> got <%s>" % [message, expected, actual])


func assert_near(actual: float, expected: float, tolerance := 0.001, message := "") -> void:
	if absf(actual - expected) > tolerance:
		_fail("%s expected %s ± %s got %s" % [message, expected, tolerance, actual])


## Waits for `count` process frames.
func wait_frames(count := 1) -> void:
	for i in count:
		await tree.process_frame


## Waits for `count` physics frames.
func wait_physics_frames(count := 1) -> void:
	for i in count:
		await tree.physics_frame


func _fail(message: String) -> void:
	failures.append(message)
