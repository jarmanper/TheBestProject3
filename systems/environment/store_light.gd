class_name StoreLight
extends Node3D
## One ceiling fixture: a light plus the emissive tube mesh it belongs to.
## Child "Light" (OmniLight3D) is required; an optional `fixture_path` points
## at a fixture mesh whose emission is modulated alongside the light.

const DISTURBANCE_DECAY_TIME := 0.5    ## seconds for set_disturbance() to fade back to 0
const NATURAL_FLICKER_MIN := 8.0
const NATURAL_FLICKER_MAX := 20.0

@export var base_energy := 1.0
@export var always_flicker := false   ## a "broken" fixture
@export var starts_off := false
@export var fixture_path: NodePath
@export var buzzes := false           ## plays a quiet amb_fluorescent_buzz loop (budget: <= 10 lights)

var _light: OmniLight3D
var _fixture: MeshInstance3D
var _fixture_material: StandardMaterial3D
var _fixture_emission := 1.0          ## the tube material's own emission energy at full brightness
var _disturbance := 0.0
var _flicker_elapsed := 0.0
var _next_flicker_at := 0.0


func _ready() -> void:
	add_to_group(&"store_light")
	_light = get_node_or_null(^"Light") as OmniLight3D
	if _light:
		# Range and colour come from the scene (the level tunes them); never cast shadows.
		_light.shadow_enabled = false
	if not fixture_path.is_empty():
		_fixture = get_node_or_null(fixture_path) as MeshInstance3D
		if _fixture:
			_bind_fixture_material()
	if starts_off:
		_set_energy_fraction(0.0)
	else:
		_set_energy_fraction(1.0)
		_schedule_next_flicker()
	if buzzes:
		_start_buzz()


func _process(delta: float) -> void:
	if _disturbance > 0.0:
		_disturbance = maxf(0.0, _disturbance - delta / DISTURBANCE_DECAY_TIME)
	if starts_off:
		return
	if always_flicker or _disturbance > 0.05:
		_erratic_flicker()
	else:
		_natural_flicker(delta)


## 0 = steady, 1 = violent flicker. Called by the monster's proximity effect.
func set_disturbance(amount: float) -> void:
	_disturbance = clampf(amount, 0.0, 1.0)


func get_disturbance() -> float:
	return _disturbance


## True while this fixture is on (not dead or switched off) and `point` is within its light's
## range. The monster's rule 3 asks this: a player only counts a sighting of something lit.
func lights_point(point: Vector3) -> bool:
	if starts_off or _light == null or base_energy <= 0.0:
		return false
	return _light.global_position.distance_to(point) <= _light.omni_range


func _schedule_next_flicker() -> void:
	_flicker_elapsed = 0.0
	_next_flicker_at = randf_range(NATURAL_FLICKER_MIN, NATURAL_FLICKER_MAX)


func _natural_flicker(delta: float) -> void:
	_flicker_elapsed += delta
	if _flicker_elapsed >= _next_flicker_at:
		_schedule_next_flicker()
		_quick_flicker()


## The flicker clicks only carry a short way: about thirty lit fixtures each flicker every
## 8-20 s, and at the default 30 m the whole store clicked a couple of times a second.
const FLICKER_SOUND_DB := -8.0
const FLICKER_SOUND_RANGE := 14.0


func _quick_flicker() -> void:
	Sfx.play_at(&"light_flicker", global_position, FLICKER_SOUND_DB, 1.0, FLICKER_SOUND_RANGE)
	var tween := create_tween()
	tween.tween_method(_set_energy_fraction, 1.0, 0.15, 0.05)
	tween.tween_method(_set_energy_fraction, 0.15, 1.0, 0.1)


func _erratic_flicker() -> void:
	var intensity := maxf(_disturbance, 0.35 if always_flicker else 0.0)
	_set_energy_fraction(1.0 - randf() * 0.6 * intensity)


func _set_energy_fraction(fraction: float) -> void:
	if _light:
		_light.light_energy = base_energy * fraction
		# A dark light still counts toward the renderer's per-view and per-mesh light limits.
		_light.visible = fraction > 0.0
	if _fixture_material:
		_fixture_material.emission_energy_multiplier = _fixture_emission * fraction


## Gives this light its own copy of the fixture's emissive (tube) surface material, so dimming
## one fixture does not dim the others that share it. Only that surface is overridden: real
## fixtures have a housing surface and a tube surface.
func _bind_fixture_material() -> void:
	var surface := 0
	var mesh := _fixture.mesh
	if mesh:
		for i in mesh.get_surface_count():
			var candidate := _fixture.get_active_material(i) as BaseMaterial3D
			if candidate and candidate.emission_enabled:
				surface = i
				break
	var base_mat := _fixture.get_active_material(surface)
	if base_mat is StandardMaterial3D:
		_fixture_material = base_mat.duplicate() as StandardMaterial3D
	else:
		_fixture_material = StandardMaterial3D.new()
		_fixture_material.emission_enabled = true
	_fixture_emission = _fixture_material.emission_energy_multiplier
	if mesh and mesh.get_surface_count() > 1:
		_fixture.set_surface_override_material(surface, _fixture_material)
	else:
		_fixture.material_override = _fixture_material


func _start_buzz() -> void:
	var emitter := Sfx.play_at(&"amb_fluorescent_buzz", global_position, -18.0)
	if emitter:
		emitter.max_distance = 6.0
