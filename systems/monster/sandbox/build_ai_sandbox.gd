extends SceneTree
## Regenerates systems/monster/sandbox/ai_sandbox.tscn (see ai_sandbox_builder.gd):
##   godot --headless --path . -s res://systems/monster/sandbox/build_ai_sandbox.gd
## Re-run after changing the layout or the project's navigation cell settings.
## The builder is loaded at runtime, after the autoloads exist: the real
## TaskStation/HidingSpot/StoreLight scripts use Sfx, which a -s script cannot
## reference at compile time.

const BUILDER := "res://systems/monster/sandbox/ai_sandbox_builder.gd"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame   # autoloads are in the tree now
	var builder: RefCounted = load(BUILDER).new()
	var err: Error = builder.call(&"build", root)
	quit(0 if err == OK else 1)
