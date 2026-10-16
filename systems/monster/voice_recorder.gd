# File: TheBestProject3/systems/monster/voice_recorder.gd
class_name VoiceRecorder
extends Node

@export var mimic_component: MimicComponent
@export var capture_interval: float = 4.0

var record_effect: AudioEffectRecord
var record_timer: Timer

func _ready() -> void:
	_setup_audio_bus()
	
	record_timer = Timer.new()
	record_timer.wait_time = capture_interval
	record_timer.autostart = true
	record_timer.timeout.connect(_capture_voice_snippet)
	add_child(record_timer)

func _setup_audio_bus() -> void:
	# Programmatically create a muted recording bus for the microphone
	var bus_idx := AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(bus_idx, "MicRecord")
	AudioServer.set_bus_mute(bus_idx, true)  # Mute so player doesn't hear an echo
	
	record_effect = AudioEffectRecord.new()
	AudioServer.add_bus_effect(bus_idx, record_effect)
	record_effect.set_recording_active(true)

func _capture_voice_snippet() -> void:
	if not record_effect or not record_effect.is_recording_active():
		return
		
	var recording: AudioStreamWAV = record_effect.get_recording()
	# Restart recording buffer for the next snippet
	record_effect.set_recording_active(false)
	record_effect.set_recording_active(true)
	
	# Only store clip if audio data was actually captured
	if recording and recording.data.size() > 1000 and mimic_component:
		# Keep only the latest 5 voice clips to prevent memory bloat
		if mimic_component.voice_clips.size() >= 5:
			mimic_component.voice_clips.pop_front()
			
		mimic_component.voice_clips.append(recording)
