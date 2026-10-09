extends Player
## Foundation Player stub with a settable noise level and its Camera3D child,
## for monster/coworker tests (the stub itself always reports silence).

var noise := 0.0


func get_noise_level() -> float:
	return 0.0 if is_hidden else noise


func get_camera() -> Camera3D:
	return get_node_or_null(^"Camera3D") as Camera3D
