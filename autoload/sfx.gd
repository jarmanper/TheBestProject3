extends Node
## Sound registry and fire-and-forget playback helpers.
## Each id maps to one or more base paths without an extension; ".ogg" is tried
## first, then ".wav". Missing files warn once and play nothing.

## Informational (tests, debugging): `id` started playing through play() or play_at().
signal played(id: StringName)

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

## Per-id mix level in dB, added to the caller's volume_db by play() and play_at(). The web
## build ignores bus effects, so the mix lives here and in the files: small, frequent sounds
## (footsteps, clicks, flickers, buzz) sit low, the ambience is a bed, and the monster and
## stingers stay loud. Every id in SOUNDS has an entry (tests/assets/test_audio_mix.gd).
const MIX_DB := {
	&"footstep_tile": -4.0, &"breath_exhausted": -3.0, &"heartbeat": 0.0,
	&"flashlight_click": -2.0, &"player_hurt": -2.0, &"player_death": 0.0,
	&"task_progress": -4.0, &"task_complete": -5.0, &"task_fail": -2.0, &"tool_pickup": -4.0,
	&"locker_open": -4.0, &"locker_close": -5.0, &"box_rustle": -4.0, &"cart_rattle": -2.0,
	&"time_clock_punch": -4.0,
	&"light_flicker": -2.0, &"distant_bang": 0.0, &"metal_creak": 0.0, &"shift_end_bell": -2.0,
	&"intercom_chime": -6.0, &"intercom_voice": -3.0,
	&"walkie_squelch_on": -4.0, &"walkie_squelch_off": -4.0, &"walkie_voice": 0.0,
	&"walkie_voice_mimic": 0.0,
	&"monster_footstep": -2.0, &"monster_breath": 0.0, &"monster_winded": 0.0,
	&"monster_growl": 0.0, &"monster_reveal": 0.0, &"monster_scream": 0.0,
	&"monster_attack_hit": 0.0, &"abduct_distant": 0.0, &"chase_stinger": 0.0,
	&"ui_click": 0.0, &"ui_hover": 0.0,
	&"amb_store_hum": 0.0, &"amb_fluorescent_buzz": -4.0, &"amb_freezer_hum": 0.0,
	&"amb_backroom": 0.0, &"music_dread": 0.0, &"music_chase": 0.0,
}

## 3D attenuation: the distance (m) at which a positional sound is at its full level; it drops
## 6 dB per doubling past that. Small sounds die off fast, big ones carry. Others: UNIT_SIZE_DEFAULT.
const UNIT_SIZE := {
	&"footstep_tile": 1.5, &"flashlight_click": 1.0, &"light_flicker": 1.0, &"box_rustle": 1.5,
	&"tool_pickup": 1.5, &"task_progress": 1.5, &"task_complete": 2.0, &"amb_fluorescent_buzz": 1.0,
	&"locker_open": 2.5, &"locker_close": 2.5, &"cart_rattle": 3.0, &"metal_creak": 3.0,
	&"distant_bang": 5.0, &"intercom_chime": 4.0, &"intercom_voice": 4.0,
	&"monster_footstep": 4.0, &"monster_growl": 6.0, &"monster_reveal": 6.0,
	&"monster_scream": 8.0, &"monster_winded": 5.0, &"abduct_distant": 8.0,
}
const UNIT_SIZE_DEFAULT := 3.0

## At most this many of an id play at once (extra requests are dropped): stops a crowd of
## coworkers' footsteps or several fixtures from stacking into one loud burst.
const MAX_VOICES := {
	&"footstep_tile": 4, &"light_flicker": 1, &"box_rustle": 2, &"cart_rattle": 1,
	&"distant_bang": 1, &"metal_creak": 1, &"monster_footstep": 2,
}

## Minimum seconds between two plays of an id, store-wide (extra requests are dropped).
const MIN_GAP := {
	&"light_flicker": 3.0, &"distant_bang": 8.0, &"metal_creak": 8.0, &"cart_rattle": 8.0,
}

## How long to let the audio thread run at shutdown (see _exit_tree).
const SHUTDOWN_DRAIN_MS := 80

var _cache := {}        # base path -> AudioStream (or null when missing)
var _warned := {}
var _voices := {}       # id -> number of its one-shots playing now
var _last_played := {}  # id -> Time.get_ticks_msec() of its last play


## Forgets voice counts and MIN_GAP timestamps (tests).
func reset_limits() -> void:
	_voices.clear()
	_last_played.clear()


## The mix level (dB) play() and play_at() add for `id`.
func mix_db(id: StringName) -> float:
	return MIX_DB.get(id, 0.0)


## The 3D unit_size play_at() uses for `id`.
func unit_size(id: StringName) -> float:
	return UNIT_SIZE.get(id, UNIT_SIZE_DEFAULT)


## False when `id` is over its MAX_VOICES or inside its MIN_GAP (looping ids are never limited).
func can_play(id: StringName) -> bool:
	if id in LOOPING:
		return true
	if MAX_VOICES.has(id) and _voices.get(id, 0) >= MAX_VOICES[id]:
		return false
	if MIN_GAP.has(id) and _last_played.has(id):
		if (Time.get_ticks_msec() - _last_played[id]) / 1000.0 < MIN_GAP[id]:
			return false
	return true


## True when a positional one-shot at `position` can't reach the player (beyond max_distance):
## it would be silent, so it isn't started at all. No player (menus, tests): never culled.
func is_out_of_earshot(position: Vector3, max_distance: float) -> bool:
	var listener: Node = GameState.player
	if not is_instance_valid(listener) or not listener.is_inside_tree() or not listener is Node3D:
		return false
	return (listener as Node3D).global_position.distance_to(position) > max_distance


func _track(id: StringName, player: Node) -> void:
	_last_played[id] = Time.get_ticks_msec()
	if MAX_VOICES.has(id):
		_voices[id] = _voices.get(id, 0) + 1
		player.tree_exiting.connect(func() -> void: _voices[id] = maxi(0, _voices.get(id, 1) - 1))


## Shutdown only (autoloads leave the tree when the engine quits, after the scene).
## Leaving the tree only *pauses* a player's playback; the engine stops it when the node is
## deleted, which happens after every _exit_tree and right before AudioServer.finish(), so the
## audio thread never gets to free it and the playbacks (with the looping streams they hold)
## are reported as "ObjectDB instances leaked" / "resources still in use at exit". Stop every
## player now and give the audio thread a few mix steps (about 12 ms each) to free them.
func _exit_tree() -> void:
	_cache.clear()
	var tree := get_tree()
	if tree and tree.root:
		for node in tree.root.find_children("*", "", true, false):
			if node is AudioStreamPlayer or node is AudioStreamPlayer3D or node is AudioStreamPlayer2D:
				node.stop()
	# Also covers players freed during the last frame (already stopping, not yet freed).
	# Not on the Web: the page just closes there, and OS.delay_msec is unsupported.
	if not OS.has_feature("web"):
		OS.delay_msec(SHUTDOWN_DRAIN_MS)


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
## `volume_db` is added to the id's MIX_DB level. Returns null when nothing was started
## (unknown id, or over its MAX_VOICES / inside its MIN_GAP).
func play(id: StringName, volume_db := 0.0, pitch := 1.0, bus := &"SFX") -> AudioStreamPlayer:
	if not can_play(id):
		return null
	var stream := get_stream(id)
	if stream == null:
		return null
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db + mix_db(id)
	player.pitch_scale = pitch
	player.bus = bus
	add_child(player)
	player.finished.connect(player.queue_free)
	_track(id, player)
	player.play()
	played.emit(id)
	return player


## Plays a one-shot positional sound in the game world. `volume_db` is added to the id's MIX_DB
## level; attenuation uses the id's UNIT_SIZE. Returns null when nothing was started (unknown id,
## over its limits, or a one-shot beyond max_distance of the player).
func play_at(id: StringName, position: Vector3, volume_db := 0.0, pitch := 1.0, max_distance := 30.0, bus := &"SFX") -> AudioStreamPlayer3D:
	if not id in LOOPING and is_out_of_earshot(position, max_distance):
		return null
	if not can_play(id):
		return null
	var stream := get_stream(id)
	if stream == null:
		return null
	var parent: Node = GameState.world_root if is_instance_valid(GameState.world_root) else self
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db + mix_db(id)
	player.pitch_scale = pitch
	player.max_distance = max_distance
	player.unit_size = unit_size(id)
	player.bus = bus
	parent.add_child(player)
	player.global_position = position
	player.finished.connect(player.queue_free)
	_track(id, player)
	player.play()
	played.emit(id)
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
