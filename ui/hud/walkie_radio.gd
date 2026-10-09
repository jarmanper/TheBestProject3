class_name WalkieRadio
extends Node
## Player-side walkie-talkie (docs/ARCHITECTURE.md "Who plays which voice audio"):
## on Events.walkie_message plays walkie_squelch_on -> the speaker's recorded line from VoiceLines
## (the mimic's take when is_mimic; generic walkie_voice / walkie_voice_mimic babble when the line
## has no clip) -> walkie_squelch_off on the Voice bus. Overlapping messages queue up.
## `is_mimic` only picks the sound; it is never shown.

## A message started playing; the HUD shows "[RADIO] SPEAKER: message" for `duration` s.
signal message_started(speaker: String, message: String, duration: float)

const SQUELCH_FALLBACK := 0.25
const GAP := 0.35
const SUBTITLE_HOLD := 1.5
## History id for a real recorded line (VoiceLines) instead of the babble ids.
const VOICE_LINE_ID := &"walkie_voice_line"
const VOICE_LINE_DB := 0.0    ## recorded lines: peaks -6 dBFS, speech RMS ~-21 dBFS (~11 dB under the old babble)
const BABBLE_DB := -8.0       ## the old babble fallback is hot (RMS ~-10 dBFS): pull it down

## Sound ids in play order (debug/tests).
var history: Array[StringName] = []
## Stream of the most recently started message's voice (debug/tests).
var last_voice_stream: AudioStream

var _queue: Array[Dictionary] = []
var _steps: Array[Dictionary] = []      ## remaining {id, stream, duration} of the current message
var _time_left := 0.0
var _busy := false
var _speaker: AudioStreamPlayer


func _ready() -> void:
	_speaker = AudioStreamPlayer.new()
	_speaker.name = "Speaker"
	_speaker.bus = &"Voice"
	add_child(_speaker)
	Events.walkie_message.connect(_on_walkie_message)


func _process(delta: float) -> void:
	tick(delta)


func enqueue(speaker_name: String, message: String, is_mimic: bool) -> void:
	_queue.append({"speaker": speaker_name, "message": message, "mimic": is_mimic})
	if not _busy:
		_start_next()


func is_busy() -> bool:
	return _busy


func tick(delta: float) -> void:
	if not _busy:
		return
	_time_left -= delta
	while _busy and _time_left <= 0.0:
		_next_step()


func _on_walkie_message(speaker_name: String, message: String, _origin: Vector3, is_mimic: bool) -> void:
	enqueue(speaker_name, message, is_mimic)


func _start_next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	var item: Dictionary = _queue.pop_front()
	var voice_step := _voice_step(item.speaker, item.message, item.mimic)
	last_voice_stream = voice_step.stream
	_steps = [
		_step(&"walkie_squelch_on", SQUELCH_FALLBACK),
		voice_step,
		_step(&"walkie_squelch_off", SQUELCH_FALLBACK),
		{"id": &"", "stream": null, "duration": GAP},
	]
	_busy = true
	_time_left = 0.0
	var duration := 0.0
	for step in _steps:
		duration += step.duration
	message_started.emit(item.speaker, item.message, duration + SUBTITLE_HOLD)
	_next_step()


func _next_step() -> void:
	if _steps.is_empty():
		_start_next()
		return
	var step: Dictionary = _steps.pop_front()
	_time_left += step.duration
	if step.id != &"":
		history.append(step.id)
		if step.stream and is_inside_tree():
			_speaker.stream = step.stream
			_speaker.volume_db = step.get("volume_db", 0.0)
			_speaker.play()


## The speaker's real recorded line (VoiceLines; the mimic's subtly wrong take when
## `is_mimic`), or the generic babble when this exact line has no clip.
func _voice_step(speaker_name: String, message: String, is_mimic: bool) -> Dictionary:
	var clip := VoiceLines.get_stream(speaker_name, message, is_mimic, VoiceLines.WALKIE)
	if clip:
		return {"id": VOICE_LINE_ID, "stream": clip, "duration": maxf(clip.get_length(), 0.05), "volume_db": VOICE_LINE_DB}
	var voice_id := &"walkie_voice_mimic" if is_mimic else &"walkie_voice"
	var step := _step(voice_id, clampf(message.length() * 0.06, 1.5, 6.0))
	step["volume_db"] = BABBLE_DB
	return step


func _step(id: StringName, fallback: float) -> Dictionary:
	var stream := Sfx.get_stream(id)
	var duration := fallback
	if stream:
		duration = maxf(stream.get_length(), 0.05)
	return {"id": id, "stream": stream, "duration": duration}
