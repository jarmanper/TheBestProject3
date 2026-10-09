class_name AmbientScares
extends Node
## Far-off noises during the night: every INTERVAL seconds a muffled thud, a slow creak or a
## cart rattle plays positionally (quiet, on the Ambience bus) somewhere in the back of house or
## a far aisle, MIN_DISTANCE..MAX_DISTANCE metres from the player -- never close to them, and
## never on top of the previous one (a noise still playing skips the next turn).
## The game scene adds one (scenes/game.gd); it only runs while the night does.

## A noise played (tests, debugging).
signal scare_played(id: StringName, position: Vector3)

const SOUNDS: Array[StringName] = [&"distant_bang", &"metal_creak", &"cart_rattle"]
const INTERVAL := Vector2(30.0, 90.0)
const MIN_DISTANCE := 14.0
const MAX_DISTANCE := 36.0
const VOLUME_DB := -16.0
const HEAR_DISTANCE := 40.0
const SPOT_TRIES := 16
## Where the noises come from: back of house and the far aisles (StoreZone ids).
const SOURCE_ZONES: Array[StringName] = [
	&"storage", &"hallway", &"janitor", &"office", &"break_room",
	&"dairy", &"frozen", &"aisle_1", &"aisle_2", &"aisle_3", &"aisle_4", &"produce",
]

var rng := RandomNumberGenerator.new()
var next_in := 0.0                      ## seconds until the next noise
var _last: AudioStreamPlayer3D          ## the noise playing now, if any


func _init() -> void:
	rng.randomize()
	next_in = _roll()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _process(delta: float) -> void:
	if GameState.night_running:
		tick(delta)


func tick(delta: float) -> void:
	next_in -= delta
	if next_in > 0.0:
		return
	next_in = _roll()
	play_scare()


## Plays one noise far from the player. False when there is no player or no spot far enough.
func play_scare() -> bool:
	var player := GameState.player
	if not is_instance_valid(player) or not player.is_inside_tree():
		return false
	if is_instance_valid(_last) and _last.playing:
		return false
	var spot: Variant = pick_spot(player.global_position)
	if spot == null:
		return false
	var id: StringName = SOUNDS[rng.randi() % SOUNDS.size()]
	var position := (spot as Vector3) + Vector3.UP * rng.randf_range(0.3, 2.2)
	_last = Sfx.play_at(id, position, VOLUME_DB, rng.randf_range(0.88, 1.05), HEAR_DISTANCE, &"Ambience")
	scare_played.emit(id, position)
	return true


## A floor point in a source zone, MIN_DISTANCE..MAX_DISTANCE from `from` (flat). null if none.
func pick_spot(from: Vector3) -> Variant:
	var zones: Array[StoreZone] = []
	for node in get_tree().get_nodes_in_group(&"store_zone"):
		var zone := node as StoreZone
		if zone != null and zone.zone_id in SOURCE_ZONES:
			zones.append(zone)
	if zones.is_empty():
		return null
	for attempt in SPOT_TRIES:
		var bounds := zones[rng.randi() % zones.size()].get_bounds()
		var point := Vector3(
			rng.randf_range(bounds.position.x + 0.5, bounds.end.x - 0.5), 0.0,
			rng.randf_range(bounds.position.z + 0.5, bounds.end.z - 0.5))
		var distance := Vector2(point.x - from.x, point.z - from.z).length()
		if distance >= MIN_DISTANCE and distance <= MAX_DISTANCE:
			return point
	return null


func _roll() -> float:
	return rng.randf_range(INTERVAL.x, INTERVAL.y)
