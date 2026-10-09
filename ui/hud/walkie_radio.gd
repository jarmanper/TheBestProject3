class_name WalkieRadio
extends Node
## Player-side walkie-talkie (docs/ARCHITECTURE.md "Who plays which voice audio"):
## on Events.walkie_message plays walkie_squelch_on -> walkie_voice (walkie_voice_mimic when
## is_mimic) -> walkie_squelch_off on the Voice bus. Overlapping messages queue up.
## `is_mimic` only picks the sound; it is never shown.

## A message started playing; the HUD shows "[RADIO] SPEAKER: message" for `duration` s.
signal message_started(speaker: String, message: String, duration: float)

const SQUELCH_FALLBACK := 0.25
const GAP := 0.35
const SUBTITLE_HOLD := 1.5

## Sound ids in play order (debug/tests).
var history: Array[StringName] = []

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
	var voice_id := &"walkie_voice_mimic" if item.mimic else &"walkie_voice"
	_steps = [
		_step(&"walkie_squelch_on", SQUELCH_FALLBACK),
		_step(voice_id, clampf(String(item.message).length() * 0.06, 1.5, 6.0)),
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
			_speaker.play()


func _step(id: StringName, fallback: float) -> Dictionary:
	var stream := Sfx.get_stream(id)
	var duration := fallback
	if stream:
		duration = maxf(stream.get_length(), 0.05)
	return {"id": id, "stream": stream, "duration": duration}
