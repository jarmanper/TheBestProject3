extends Node
## Night clock, end-of-night result, stats, persisted settings, and references
## to the live player/monster/world so systems can find each other.

const SECONDS_PER_HOUR := 90.0
const END_HOUR := 6
const SETTINGS_PATH := "user://settings.cfg"
const BRIGHTNESS_MIN := 0.4

var night_running := false
var night_time := 0.0                 ## seconds since 12:00 AM
var last_result: StringName = &""
var stats := {}

var player: Node3D
var monster: Node3D
var world_root: Node3D                ## 3D root inside the game viewport

var mouse_sensitivity := 0.0025       ## radians per pixel
var master_volume := 0.8              ## 0..1
var crt_enabled := true
var brightness: float = 1.0:          ## 0.4..1.0 -- horror game: can only be turned DOWN
	set(value):
		brightness = clampf(value, BRIGHTNESS_MIN, 1.0)

var _last_hour := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	load_settings()


func _process(delta: float) -> void:
	if night_running:
		advance(delta)


func start_night() -> void:
	night_time = 0.0
	night_running = true
	last_result = &""
	_last_hour = 0
	stats = {
		"tasks_completed": 0,
		"manager_tasks_completed": 0,
		"manager_tasks_failed": 0,
		"damage_taken": 0.0,
		"times_hidden": 0,
		"monster_sightings": 0,
		"coworkers_lost": 0,
	}
	Events.night_started.emit()
	Events.hour_changed.emit(0)


## Moves the clock forward. Ends the night at END_HOUR as win or fired -- unless the player
## is already dead (dying just before 6:00 AM): their death path ends it as &"dead".
func advance(delta: float) -> void:
	if not night_running:
		return
	night_time = minf(night_time + delta, SECONDS_PER_HOUR * END_HOUR)
	var hour := get_hour()
	if hour != _last_hour:
		_last_hour = hour
		Events.hour_changed.emit(hour)
	if hour >= END_HOUR and not is_player_dead():
		end_night(&"win" if Tasks.all_required_done() else &"fired")


## True when the registered player has died (Player.is_dead()).
func is_player_dead() -> bool:
	return is_instance_valid(player) and player.has_method(&"is_dead") and player.call(&"is_dead")


func end_night(result: StringName) -> void:
	if not night_running:
		return
	night_running = false
	last_result = result
	Events.night_ended.emit(result)


func get_hour() -> int:
	return int(night_time / SECONDS_PER_HOUR)


func get_minute() -> int:
	return int(fmod(night_time, SECONDS_PER_HOUR) / SECONDS_PER_HOUR * 60.0)


## 0.0 at 12:00 AM, 1.0 at 6:00 AM.
func get_night_progress() -> float:
	return night_time / (SECONDS_PER_HOUR * END_HOUR)


## "12:00 AM", "1:07 AM", ... "6:00 AM".
func get_clock_text() -> String:
	var hour := get_hour()
	var display_hour := 12 if hour == 0 else hour
	return "%d:%02d AM" % [display_hour, get_minute()]


func add_stat(key: String, amount: Variant = 1) -> void:
	stats[key] = stats.get(key, 0) + amount


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		mouse_sensitivity = config.get_value("input", "mouse_sensitivity", mouse_sensitivity)
		master_volume = config.get_value("audio", "master_volume", master_volume)
		crt_enabled = config.get_value("video", "crt_enabled", crt_enabled)
		brightness = config.get_value("video", "brightness", brightness)
	set_master_volume(master_volume)


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("video", "crt_enabled", crt_enabled)
	config.set_value("video", "brightness", brightness)
	config.save(SETTINGS_PATH)
