extends Node
## Sound registry and fire-and-forget playback helpers.
## Each id maps to one or more base paths without an extension; ".ogg" is tried
## first, then ".wav". Missing files warn once and play nothing.

const SFX := "res://assets/audio/sfx/"
const AMB := "res://assets/audio/ambience/"
const MUS := "res://assets/audio/music/"

const SOUNDS := {
	# Player
	&"footstep_tile": [SFX + "footstep_tile_01", SFX + "footstep_tile_02", SFX + "footstep_tile_03", SFX + "footstep_tile_04", SFX + "footstep_tile_05", SFX + "footstep_tile_06"],
	&"breath_exhausted": [SFX + "breath_exhausted"],
	&"heartbeat": [SFX + "heartbeat_loop"],
	&"flashlight_click": [SFX + "flashlight_click"],
	&"player_hurt": [SFX + "player_hurt"],
	&"player_death": [SFX + "player_death"],
	# Interaction / tasks
	&"task_progress": [SFX + "task_progress_loop"],
	&"task_complete": [SFX + "task_complete"],
	&"task_fail": [SFX + "task_fail"],
	&"tool_pickup": [SFX + "tool_pickup"],
	&"locker_open": [SFX + "locker_open"],
	&"locker_close": [SFX + "locker_close"],
	&"box_rustle": [SFX + "box_rustle"],
	&"cart_rattle": [SFX + "cart_rattle"],
	&"time_clock_punch": [SFX + "time_clock_punch"],
	# Store
	&"light_flicker": [SFX + "light_flicker_01", SFX + "light_flicker_02", SFX + "light_flicker_03"],
	&"distant_bang": [SFX + "distant_bang_01", SFX + "distant_bang_02", SFX + "distant_bang_03"],
	&"metal_creak": [SFX + "metal_creak_01", SFX + "metal_creak_02"],
	&"shift_end_bell": [SFX + "shift_end_bell"],
	# Manager / radio
	&"intercom_chime": [SFX + "intercom_chime"],
	&"intercom_voice": [SFX + "intercom_voice_01", SFX + "intercom_voice_02", SFX + "intercom_voice_03", SFX + "intercom_voice_04"],
	&"walkie_squelch_on": [SFX + "walkie_squelch_on"],
	&"walkie_squelch_off": [SFX + "walkie_squelch_off"],
	&"walkie_voice": [SFX + "walkie_voice_01", SFX + "walkie_voice_02", SFX + "walkie_voice_03", SFX + "walkie_voice_04", SFX + "walkie_voice_05", SFX + "walkie_voice_06"],
	&"walkie_voice_mimic": [SFX + "walkie_voice_mimic_01", SFX + "walkie_voice_mimic_02", SFX + "walkie_voice_mimic_03"],
	# Monster
	&"monster_footstep": [SFX + "footstep_monster_01", SFX + "footstep_monster_02", SFX + "footstep_monster_03", SFX + "footstep_monster_04"],
	&"monster_breath": [SFX + "monster_breath_loop"],
	&"monster_winded": [SFX + "monster_winded"],
	&"monster_growl": [SFX + "monster_growl_01", SFX + "monster_growl_02"],
	&"monster_reveal": [SFX + "monster_reveal"],
	&"monster_scream": [SFX + "monster_scream"],
	&"monster_attack_hit": [SFX + "monster_attack_hit"],
	&"abduct_distant": [SFX + "abduct_distant"],
	&"chase_stinger": [SFX + "chase_stinger"],
	# UI
	&"ui_click": [SFX + "ui_click"],
	&"ui_hover": [SFX + "ui_hover"],
	# Ambience / music (looping)
	&"amb_store_hum": [AMB + "amb_store_hum"],
	&"amb_fluorescent_buzz": [AMB + "amb_fluorescent_buzz"],
	&"amb_freezer_hum": [AMB + "amb_freezer_hum"],
	&"amb_backroom": [AMB + "amb_backroom"],
	&"music_dread": [MUS + "music_dread_loop"],
	&"music_chase": [MUS + "music_chase_loop"],
}

const LOOPING := [
	&"heartbeat", &"task_progress", &"monster_breath",
	&"amb_store_hum", &"amb_fluorescent_buzz", &"amb_freezer_hum", &"amb_backroom",
	&"music_dread", &"music_chase",
]

var _cache := {}        # base path -> AudioStream (or null when missing)
var _warned := {}


## Returns a stream for `id` (random variant). Looping ids come back looping.
func get_stream(id: StringName) -> AudioStream:
	var variants: Array = SOUNDS.get(id, [])
	if variants.is_empty():
		_warn_once(String(id), "Unknown sound id '%s'" % id)
		return null
	var stream := _load_base(variants.pick_random())
	if stream and id in LOOPING:
		_enable_loop(stream)
	return stream


## Plays a non-positional sound (UI, radio, player's own sounds).
func play(id: StringName, volume_db := 0.0, pitch := 1.0, bus := &"SFX") -> AudioStreamPlayer:
	var stream := get_stream(id)
	if stream == null:
		return null
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.bus = bus
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
	return player


## Plays a one-shot positional sound in the game world.
func play_at(id: StringName, position: Vector3, volume_db := 0.0, pitch := 1.0, max_distance := 30.0, bus := &"SFX") -> AudioStreamPlayer3D:
	var stream := get_stream(id)
	if stream == null:
		return null
	var parent: Node = GameState.world_root if is_instance_valid(GameState.world_root) else self
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.max_distance = max_distance
	player.unit_size = 4.0
	player.bus = bus
	parent.add_child(player)
	player.global_position = position
	player.finished.connect(player.queue_free)
	player.play()
	return player


func _load_base(base: String) -> AudioStream:
	if _cache.has(base):
		return _cache[base]
	var stream: AudioStream = null
	for ext in [".ogg", ".wav"]:
		if ResourceLoader.exists(base + ext):
			stream = load(base + ext)
			break
	if stream == null:
		_warn_once(base, "Missing sound file: %s(.ogg|.wav)" % base)
	_cache[base] = stream
	return stream


func _enable_loop(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	elif stream is AudioStreamWAV and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)


func _warn_once(key: String, message: String) -> void:
	if not _warned.has(key):
		_warned[key] = true
		push_warning(message)
