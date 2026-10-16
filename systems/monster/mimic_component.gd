# File 2: TheBestProject3/systems/monster/mimic_component.gd
class_name MimicComponent
extends Node

@export_group("Audio Lure Config")
@export var voice_clips: Array[AudioStream] = []
@export var lure_interval_min: float = 8.0
@export var lure_interval_max: float = 15.0
@export var pitch_scale_range: Vector2 = Vector2(0.85, 1.15)
@export var audio_player: AudioStreamPlayer3D

var _lure_timer: Timer
var _parent_monster: Node3D

signal lure_played(clip_name: String)

func _ready() -> void:
	_parent_monster = get_parent() as Node3D
	
	if not audio_player:
		audio_player = AudioStreamPlayer3D.new()
		audio_player.unit_size = 10.0
		audio_player.max_distance = 25.0
		add_child(audio_player)
	
	_lure_timer = Timer.new()
	_lure_timer.one_shot = true
	_lure_timer.timeout.connect(_on_lure_timer_timeout)
	add_child(_lure_timer)

func start_luring() -> void:
	_schedule_next_lure()

func stop_luring() -> void:
	_lure_timer.stop()
	if audio_player and audio_player.playing:
		audio_player.stop()

func play_voice_lure() -> void:
	if voice_clips.is_empty() or not audio_player:
		return
		
	var clip: AudioStream = voice_clips.pick_random()
	audio_player.stream = clip
	audio_player.pitch_scale = randf_range(pitch_scale_range.x, pitch_scale_range.y)
	audio_player.play()
	
	lure_played.emit(clip.resource_path.get_file())
	if Events.has_signal("mimic_lure_triggered"):
		Events.mimic_lure_triggered.emit(_parent_monster.global_position, clip.resource_path.get_file())

func _schedule_next_lure() -> void:
	var wait_time := randf_range(lure_interval_min, lure_interval_max)
	_lure_timer.start(wait_time)

func _on_lure_timer_timeout() -> void:
	play_voice_lure()
	_schedule_next_lure()
