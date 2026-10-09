extends StoreLight
## Sandbox stand-in for the real StoreLight: its OmniLight3D child "Light"
## flickers with the monster's disturbance (decays to 0 within 0.5 s), so the
## proximity tell is visible before the Store Environment lights exist.

var _disturbance := 0.0
var _rng := RandomNumberGenerator.new()

@onready var _light: OmniLight3D = $Light


func set_disturbance(amount: float) -> void:
	_disturbance = maxf(_disturbance, clampf(amount, 0.0, 1.0))


func _process(delta: float) -> void:
	_disturbance = maxf(_disturbance - delta * 2.0, 0.0)
	var flicker := 1.0
	if _disturbance > 0.0 and _rng.randf() < 0.25 + _disturbance * 0.5:
		flicker = _rng.randf_range(0.05, 1.0 - _disturbance * 0.6)
	_light.light_energy = base_energy * flicker
