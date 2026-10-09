class_name CrtPostFx
extends CanvasLayer
## Full-screen CRT pass (crt.gdshader) over everything on lower canvas layers.
## Follows GameState.crt_enabled (Settings). Keeps animating while the game is paused.


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = GameState.crt_enabled


func _process(_delta: float) -> void:
	if visible != GameState.crt_enabled:
		visible = GameState.crt_enabled
