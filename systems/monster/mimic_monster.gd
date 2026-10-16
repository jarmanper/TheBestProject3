# File 1: TheBestProject3/systems/monster/mimic_monster.gd
class_name MimicMonster
extends CharacterBody3D

enum State { IDLE, DISGUISED, STALK, LURE, CHARGE, ATTACK }

@export_category("Movement Settings")
@export var walk_speed: float = 2.5
@export var charge_speed: float = 6.0

@export_category("Combat & Detection")
@export var detection_radius: float = 12.0
@export var attack_range: float = 1.8
@export var damage: float = 35.0

@export_category("Audio & Lure")
@export var voice_clips: Array[AudioStream] = []
@export var lure_interval_min: float = 8.0
@export var lure_interval_max: float = 15.0
@export var pitch_scale_range: Vector2 = Vector2(0.85, 1.15)

var current_state: State = State.IDLE
var target_player: Node3D = null
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var nav_agent: NavigationAgent3D
var audio_player: AudioStreamPlayer3D
var detection_area: Area3D
var attack_area: Area3D
var lure_timer: Timer

signal state_changed(old_state: State, new_state: State)
signal player_attacked(damage_amount: float)

func _ready() -> void:
	add_to_group("monster")
	_build_internal_nodes()
	set_state(State.IDLE)

func _build_internal_nodes() -> void:
	# Navigation Agent
	nav_agent = NavigationAgent3D.new()
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = 0.5
	add_child(nav_agent)

	# Audio Player & Lure Timer
	audio_player = AudioStreamPlayer3D.new()
	audio_player.unit_size = 10.0
	audio_player.max_distance = 25.0
	add_child(audio_player)

	lure_timer = Timer.new()
	lure_timer.one_shot = true
	lure_timer.timeout.connect(_on_lure_timer_timeout)
	add_child(lure_timer)

	# Detection Area3D (Collision Mask 2 = Player)
	detection_area = Area3D.new()
	detection_area.collision_layer = 0
	detection_area.collision_mask = 2
	var detect_col := CollisionShape3D.new()
	var detect_sphere := SphereShape3D.new()
	detect_sphere.radius = detection_radius
	detect_col.shape = detect_sphere
	detection_area.add_child(detect_col)
	add_child(detection_area)
	detection_area.body_entered.connect(_on_detection_body_entered)
	detection_area.body_exited.connect(_on_detection_body_exited)

	# Attack Area3D (Collision Mask 2 = Player)
	attack_area = Area3D.new()
	attack_area.collision_layer = 0
	attack_area.collision_mask = 2
	var atk_col := CollisionShape3D.new()
	var atk_sphere := SphereShape3D.new()
	atk_sphere.radius = attack_range
	atk_col.shape = atk_sphere
	attack_area.add_child(atk_col)
	add_child(attack_area)
	attack_area.body_entered.connect(_on_attack_body_entered)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	match current_state:
		State.IDLE, State.DISGUISED:
			velocity.x = move_toward(velocity.x, 0, walk_speed * delta)
			velocity.z = move_toward(velocity.z, 0, walk_speed * delta)

		State.STALK, State.CHARGE:
			if target_player:
				nav_agent.target_position = target_player.global_position
				if not nav_agent.is_navigation_finished():
					var next_pos: Vector3 = nav_agent.get_next_path_position()
					var dir: Vector3 = (next_pos - global_position).normalized()
					var speed: float = charge_speed if current_state == State.CHARGE else walk_speed
					velocity.x = dir.x * speed
					velocity.z = dir.z * speed
					look_at(Vector3(target_player.global_position.x, global_position.y, target_player.global_position.z), Vector3.UP)

	move_and_slide()

func set_state(new_state: State) -> void:
	if current_state == new_state:
		return
	var old_state: State = current_state
	current_state = new_state

	match new_state:
		State.IDLE:
			lure_timer.stop()
			if audio_player.playing:
				audio_player.stop()
		State.LURE:
			_schedule_next_lure()
		State.CHARGE:
			play_voice_lure(randf_range(pitch_scale_range.x, pitch_scale_range.y))

	state_changed.emit(old_state, new_state)

func play_voice_lure(pitch: float = 1.0) -> void:
	if voice_clips.is_empty():
		return
	audio_player.stream = voice_clips.pick_random()
	audio_player.pitch_scale = pitch
	audio_player.play()

func _schedule_next_lure() -> void:
	lure_timer.start(randf_range(lure_interval_min, lure_interval_max))

func _on_lure_timer_timeout() -> void:
	play_voice_lure()
	if current_state == State.LURE:
		_schedule_next_lure()

func _on_detection_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		target_player = body
		set_state(State.CHARGE)

func _on_detection_body_exited(body: Node3D) -> void:
	if body == target_player:
		target_player = null
		set_state(State.LURE)

func _on_attack_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and current_state == State.CHARGE:
		set_state(State.ATTACK)
		player_attacked.emit(damage)
		if Events.has_signal("player_damaged"):
			Events.player_damaged.emit(damage)