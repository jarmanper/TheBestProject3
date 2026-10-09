extends Node3D

## Single-player baseline for Project 3: a late-night supermarket closing shift.
## The player is one employee; the orange-uniformed mimic is the opposing AI.

const PLAYER_WALK_SPEED := 4.2
const PLAYER_SPRINT_SPEED := 7.0
const STAMINA_MAX := 100.0
const STAMINA_DRAIN_PER_SECOND := 29.0
const STAMINA_REGEN_PER_SECOND := 19.0
const INTERACTION_RANGE := 2.6
const MOUSE_SENSITIVITY := 0.0024
const STORE_HALF_WIDTH := 15.0
const STORE_FRONT := 12.0
const STORE_BACK := -20.0
const MIMIC_NAV_STEP := 1.0
const MIMIC_NAV_MIN := Vector2(-13.5, -18.5)
const MIMIC_NAV_MAX := Vector2(13.5, 10.5)

const CHARCOAL := Color("171B1A")
const SAFETY_ORANGE := Color("E87932")
const OLIVE := Color("626D58")
const FLUORESCENT := Color("D8D3A8")
const EMERGENCY_RED := Color("B93B32")
const CONCRETE := Color("444A48")

var player: CharacterBody3D
var head: Node3D
var camera: Camera3D
var monster: CharacterBody3D
var monster_body: Node3D
var monster_eye_light: OmniLight3D
var player_hidden := false
var game_ended := false
var stamina := STAMINA_MAX
var elapsed := 0.0
var manager_announced := false
var manager_time := 7.0
var mimic_sighting_done := false
var attack_exposure := 0.0
var monster_sprint_time := 0.0
var monster_cooldown := 0.0
var current_prompt := ""
var status_text := "Clocked in. Complete the closing checklist before dawn."
var mimic_navigation_ready := false
var mimic_grid_width := 0
var mimic_grid_depth := 0
var mimic_grid_walkable: Array[bool] = []
var mimic_path: Array[Vector3] = []
var mimic_path_goal := Vector3(999.0, 0.0, 999.0)
var mimic_stuck_time := 0.0
var mimic_has_player_los := false
var lighting_update_timer := 0.0

var tasks: Array = []
var manager_task: Dictionary = {}
var held_tools: Dictionary = {}
var interactables: Array = []
var task_labels: Dictionary = {}
var flicker_lights: Array[OmniLight3D] = []

var objective_label: Label
var checklist_label: Label
var prompt_label: Label
var status_label: Label
var stamina_label: Label
var danger_label: Label
var end_overlay: ColorRect
var end_title: Label
var ambience_player: AudioStreamPlayer
var footstep_player: AudioStreamPlayer
var intercom_player: AudioStreamPlayer
var stinger_player: AudioStreamPlayer
var footstep_timer := 0.0


func _ready() -> void:
	_build_store()
	_create_player()
	_create_mimic()
	_setup_tasks()
	_build_hud()
	_setup_audio()
	call_deferred("_build_mimic_navigation")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_update_hud()


func _exit_tree() -> void:
	# Explicitly stop generated streams before the audio server is torn down.
	for sound_player in [ambience_player, footstep_player, intercom_player, stinger_player]:
		if is_instance_valid(sound_player):
			sound_player.stop()
			sound_player.stream = null


func _process(delta: float) -> void:
	if game_ended:
		return
	elapsed += delta
	_update_lighting(delta)
	_update_manager_call()
	_update_scripted_sighting()
	_update_interaction_prompt()
	_update_hud()


func _physics_process(delta: float) -> void:
	if game_ended:
		return
	_move_player(delta)
	_update_mimic(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not game_ended:
		player.rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		head.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-78.0), deg_to_rad(78.0))
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED)
		elif game_ended and event.keycode == KEY_R:
			get_tree().reload_current_scene()
		elif not game_ended and event.keycode == KEY_F:
			_interact()
		elif not game_ended and event.keycode == KEY_E:
			_toggle_hiding()


func _build_store() -> void:
	var environment := WorldEnvironment.new()
	var world_environment := Environment.new()
	world_environment.background_mode = Environment.BG_COLOR
	world_environment.background_color = CHARCOAL
	world_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_environment.ambient_light_color = OLIVE
	world_environment.ambient_light_energy = 0.32
	world_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.glow_enabled = true
	world_environment.glow_intensity = 0.55
	world_environment.fog_enabled = true
	world_environment.fog_light_color = Color("343B35")
	world_environment.fog_density = 0.012
	environment.environment = world_environment
	add_child(environment)

	_add_static_box("Floor", Vector3(31.0, 0.3, 34.0), Vector3(0.0, -0.15, -4.0), CONCRETE)
	_add_static_box("NorthWall", Vector3(31.0, 5.5, 0.4), Vector3(0.0, 2.75, STORE_BACK), CHARCOAL)
	_add_static_box("SouthWall", Vector3(31.0, 5.5, 0.4), Vector3(0.0, 2.75, STORE_FRONT), CHARCOAL)
	_add_static_box("WestWall", Vector3(0.4, 5.5, 32.0), Vector3(-STORE_HALF_WIDTH, 2.75, -4.0), CHARCOAL)
	_add_static_box("EastWall", Vector3(0.4, 5.5, 32.0), Vector3(STORE_HALF_WIDTH, 2.75, -4.0), CHARCOAL)
	_add_visual_box("Ceiling", Vector3(31.0, 0.25, 32.0), Vector3(0.0, 5.45, -4.0), Color("222826"))

	# Four long shelf rows create narrow aisles while leaving a clear central route.
	for shelf_x in [-9.0, -4.0, 4.0, 9.0]:
		_create_shelf_row(Vector3(shelf_x, 0.0, -6.0))
	_create_checkout_area()
	_create_stockroom()
	_create_hiding_spot("Staff Locker", Vector3(-12.7, 0.0, 6.0))
	_create_hiding_spot("Walk-in Cooler", Vector3(12.4, 0.0, -13.5))
	_create_hiding_spot("Cardboard Compactor", Vector3(-12.4, 0.0, -16.0))

	for z in [8.0, 1.0, -7.0, -15.0]:
		for x in [-11.0, -5.5, 0.0, 5.5, 11.0]:
			_add_fluorescent_light(Vector3(x, 5.05, z), (int(abs(x + z)) % 3) == 0)

	_add_emergency_light(Vector3(-14.2, 3.9, -18.5))
	_add_emergency_light(Vector3(14.2, 3.9, 10.5))


func _create_shelf_row(position: Vector3) -> void:
	var shelf := Node3D.new()
	shelf.name = "AisleShelf"
	shelf.position = position
	add_child(shelf)
	_add_static_box("ShelfFrame", Vector3(1.15, 3.2, 20.0), Vector3.ZERO, OLIVE, shelf)
	for level in [0.55, 1.35, 2.15, 2.95]:
		_add_visual_box("ShelfLip", Vector3(1.35, 0.10, 19.8), Vector3(0.0, level, 0.0), Color("8A9278"), shelf)
	for z in range(-8, 9, 2):
		var product_color: Color = [Color("A64D3E"), Color("C6B56B"), Color("4A7891"), Color("7E695A")][abs(z + int(position.x)) % 4]
		_add_visual_box("Products", Vector3(0.52, 0.42, 0.75), Vector3(-0.64, 1.62, float(z)), product_color, shelf)
		_add_visual_box("Products", Vector3(0.52, 0.42, 0.75), Vector3(0.64, 2.42, float(z) + 0.35), product_color.darkened(0.18), shelf)


func _create_checkout_area() -> void:
	_add_static_box("CheckoutCounter", Vector3(8.5, 1.1, 1.4), Vector3(0.0, 0.55, 8.4), OLIVE)
	_add_visual_box("RegisterGlow", Vector3(1.0, 0.25, 0.55), Vector3(0.0, 1.25, 8.1), FLUORESCENT)
	_add_visual_box("CheckoutSign", Vector3(3.0, 0.8, 0.15), Vector3(0.0, 3.8, 8.8), EMERGENCY_RED)


func _create_stockroom() -> void:
	_add_static_box("StockroomDivider", Vector3(0.35, 4.3, 8.0), Vector3(10.9, 2.15, -15.5), OLIVE)
	_add_static_box("StockroomShelf", Vector3(3.2, 2.6, 0.75), Vector3(12.5, 1.3, -18.0), OLIVE)
	_add_visual_box("BreakerCabinet", Vector3(1.1, 1.7, 0.18), Vector3(13.1, 2.0, -15.6), EMERGENCY_RED)


func _create_hiding_spot(title: String, position: Vector3) -> void:
	var spot := Node3D.new()
	spot.name = title.replace(" ", "")
	spot.position = position
	add_child(spot)
	_add_static_box("HideShell", Vector3(1.8, 3.5, 1.4), Vector3(0.0, 1.75, 0.0), Color("354039"), spot)
	_add_visual_box("HideDoor", Vector3(1.35, 2.6, 0.08), Vector3(0.0, 1.55, 0.74), Color("4B554A"), spot)
	_add_world_label(spot, title.to_upper(), Vector3(0.0, 3.85, 0.0), Color("B7C6AC"))
	interactables.append({"node": spot, "type": "hide", "title": title})


func _add_fluorescent_light(position: Vector3, flickers: bool) -> void:
	_add_visual_box("FluorescentFixture", Vector3(2.5, 0.12, 0.45), position, FLUORESCENT)
	var light := OmniLight3D.new()
	light.position = position + Vector3(0.0, -0.22, 0.0)
	light.light_color = FLUORESCENT
	light.light_energy = 1.4
	light.omni_range = 11.0
	light.shadow_enabled = true
	light.set_meta("flickers", flickers)
	light.set_meta("base_energy", light.light_energy)
	add_child(light)
	if flickers:
		flicker_lights.append(light)


func _add_emergency_light(position: Vector3) -> void:
	var light := OmniLight3D.new()
	light.position = position
	light.light_color = EMERGENCY_RED
	light.light_energy = 1.2
	light.omni_range = 7.0
	add_child(light)


func _create_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Employee"
	player.position = Vector3(0.0, 1.0, 10.2)
	player.collision_layer = 2
	player.collision_mask = 1
	add_child(player)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.8
	shape.shape = capsule
	player.add_child(shape)
	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.0, 0.52, 0.0)
	player.add_child(head)
	camera = Camera3D.new()
	camera.fov = 95.0
	camera.current = true
	head.add_child(camera)
	var beam := SpotLight3D.new()
	beam.light_color = Color("E8E2BA")
	beam.light_energy = 1.0
	beam.spot_range = 14.0
	beam.spot_angle = 33.0
	beam.shadow_enabled = true
	camera.add_child(beam)


func _create_mimic() -> void:
	monster = CharacterBody3D.new()
	monster.name = "Mimic"
	# Spawn in the rear cross-aisle, clear of the cardboard compactor and shelves.
	monster.position = Vector3(-10.5, 0.0, -18.5)
	monster.collision_layer = 4
	monster.collision_mask = 1
	add_child(monster)
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.8
	collision.shape = capsule
	collision.position = Vector3(0.0, 0.9, 0.0)
	monster.add_child(collision)
	monster_body = Node3D.new()
	monster.add_child(monster_body)
	var torso := MeshInstance3D.new()
	var torso_mesh := BoxMesh.new()
	torso_mesh.size = Vector3(0.85, 1.0, 0.45)
	torso.mesh = torso_mesh
	torso.position = Vector3(0.0, 1.15, 0.0)
	torso.material_override = _material(SAFETY_ORANGE)
	monster_body.add_child(torso)
	var head_mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.32
	sphere.height = 0.64
	head_mesh.mesh = sphere
	head_mesh.position = Vector3(0.0, 1.85, 0.0)
	head_mesh.material_override = _material(Color("C7B195"))
	monster_body.add_child(head_mesh)
	for side in [-0.58, 0.58]:
		var arm := MeshInstance3D.new()
		var arm_mesh := CylinderMesh.new()
		arm_mesh.top_radius = 0.12
		arm_mesh.bottom_radius = 0.12
		arm_mesh.height = 1.15
		arm.mesh = arm_mesh
		arm.position = Vector3(side, 1.12, 0.0)
		arm.rotation.z = side * 0.2
		arm.material_override = _material(Color("252A28"))
		monster_body.add_child(arm)
	monster_eye_light = OmniLight3D.new()
	monster_eye_light.position = Vector3(0.0, 1.85, -0.25)
	monster_eye_light.light_color = EMERGENCY_RED
	monster_eye_light.light_energy = 0.0
	monster_eye_light.omni_range = 3.5
	monster_body.add_child(monster_eye_light)
	_add_world_label(monster_body, "EMPLOYEE", Vector3(0.0, 2.35, 0.0), Color("FFCB94"))


func _setup_tasks() -> void:
	tasks = [
		{"id": "register", "title": "Lock the front register", "position": Vector3(0.0, 0.0, 6.35), "requires": "", "complete": false},
		{"id": "restock", "title": "Restock Aisle 2", "position": Vector3(-6.5, 0.0, -7.5), "requires": "", "complete": false},
		{"id": "spill", "title": "Clean the produce spill", "position": Vector3(1.3, 0.0, -11.0), "requires": "Mop", "complete": false}
	]
	manager_task = {"id": "breaker", "title": "Reset the rear breaker", "position": Vector3(12.3, 0.0, -14.2), "requires": "Utility Key", "complete": false, "visible": false}
	for task in tasks:
		_create_task_station(task, false)
	_create_task_station(manager_task, true)
	_create_tool_station("Mop", "MOP CLOSET", Vector3(-12.3, 0.0, 2.5), Color("6F91A1"))
	_create_tool_station("Utility Key", "MAINTENANCE CAGE", Vector3(12.1, 0.0, 6.1), Color("D8B65C"))


func _create_task_station(task: Dictionary, starts_hidden: bool) -> void:
	var station := Node3D.new()
	station.name = "Task_" + task["id"]
	station.position = task["position"]
	station.visible = not starts_hidden
	add_child(station)
	var color := EMERGENCY_RED if starts_hidden else OLIVE
	_add_static_box("TaskConsole", Vector3(0.9, 1.15, 0.65), Vector3(0.0, 0.58, 0.0), color, station)
	_add_visual_box("TaskGlow", Vector3(0.62, 0.14, 0.3), Vector3(0.0, 1.18, -0.36), FLUORESCENT, station)
	var label_text: String = task["title"].to_upper()
	if task["requires"] != "":
		label_text += "\nNEEDS " + String(task["requires"]).to_upper()
	var label := _add_world_label(station, label_text, Vector3(0.0, 1.85, 0.0), Color("F5EAB8"))
	task_labels[task["id"]] = label
	interactables.append({"node": station, "type": "task", "task_id": task["id"]})
	task["node"] = station


func _create_tool_station(tool_name: String, sign: String, position: Vector3, color: Color) -> void:
	var station := Node3D.new()
	station.name = tool_name.replace(" ", "")
	station.position = position
	add_child(station)
	_add_static_box("ToolCabinet", Vector3(1.15, 1.6, 0.7), Vector3(0.0, 0.8, 0.0), Color("3F4C42"), station)
	_add_visual_box("Tool", Vector3(0.18, 1.15, 0.18), Vector3(0.0, 1.7, -0.15), color, station)
	_add_world_label(station, sign, Vector3(0.0, 2.1, 0.0), color)
	interactables.append({"node": station, "type": "tool", "tool": tool_name, "title": sign})


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var title := Label.new()
	title.text = "NIGHT SHIFT // STORE 03"
	title.position = Vector2(28, 22)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", SAFETY_ORANGE)
	layer.add_child(title)

	objective_label = Label.new()
	objective_label.position = Vector2(28, 64)
	objective_label.size = Vector2(480, 62)
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective_label.add_theme_font_size_override("font_size", 18)
	objective_label.add_theme_color_override("font_color", FLUORESCENT)
	layer.add_child(objective_label)

	checklist_label = Label.new()
	checklist_label.position = Vector2(28, 138)
	checklist_label.size = Vector2(400, 180)
	checklist_label.add_theme_font_size_override("font_size", 16)
	checklist_label.add_theme_color_override("font_color", Color("DEE4D3"))
	layer.add_child(checklist_label)

	stamina_label = Label.new()
	stamina_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	stamina_label.offset_left = -255
	stamina_label.offset_top = 25
	stamina_label.offset_right = -30
	stamina_label.offset_bottom = 58
	stamina_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stamina_label.add_theme_font_size_override("font_size", 18)
	stamina_label.add_theme_color_override("font_color", Color("E6D99C"))
	layer.add_child(stamina_label)

	danger_label = Label.new()
	danger_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	danger_label.offset_left = -415
	danger_label.offset_top = 60
	danger_label.offset_right = -30
	danger_label.offset_bottom = 90
	danger_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	danger_label.add_theme_font_size_override("font_size", 15)
	danger_label.add_theme_color_override("font_color", EMERGENCY_RED)
	layer.add_child(danger_label)

	status_label = Label.new()
	status_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	status_label.offset_left = 28
	status_label.offset_right = -28
	status_label.offset_top = -95
	status_label.offset_bottom = -65
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 17)
	status_label.add_theme_color_override("font_color", Color("D3D8C3"))
	layer.add_child(status_label)

	prompt_label = Label.new()
	prompt_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	prompt_label.offset_left = 28
	prompt_label.offset_right = -28
	prompt_label.offset_top = -58
	prompt_label.offset_bottom = -25
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.add_theme_font_size_override("font_size", 20)
	prompt_label.add_theme_color_override("font_color", FLUORESCENT)
	layer.add_child(prompt_label)

	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -8
	crosshair.offset_top = -13
	crosshair.offset_right = 8
	crosshair.offset_bottom = 13
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.add_theme_font_size_override("font_size", 26)
	crosshair.add_theme_color_override("font_color", Color("EDF0DA"))
	layer.add_child(crosshair)

	end_overlay = ColorRect.new()
	end_overlay.color = Color(0.03, 0.04, 0.035, 0.92)
	end_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	end_overlay.visible = false
	layer.add_child(end_overlay)
	end_title = Label.new()
	end_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	end_title.offset_left = -300
	end_title.offset_top = -100
	end_title.offset_right = 300
	end_title.offset_bottom = 100
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	end_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	end_title.add_theme_font_size_override("font_size", 32)
	end_overlay.add_child(end_title)


func _setup_audio() -> void:
	# The prototype uses generated WAV streams so its basic soundscape ships with
	# the project instead of depending on imported audio assets.
	ambience_player = AudioStreamPlayer.new()
	ambience_player.name = "FluorescentHum"
	ambience_player.stream = _make_ambient_stream()
	ambience_player.volume_db = -10.0
	add_child(ambience_player)
	_play_sound(ambience_player)

	footstep_player = AudioStreamPlayer.new()
	footstep_player.name = "Footsteps"
	footstep_player.stream = _make_tone_stream(0.12, 78.0, 0.36, 23.0, true)
	footstep_player.volume_db = -8.0
	add_child(footstep_player)

	intercom_player = AudioStreamPlayer.new()
	intercom_player.name = "IntercomCue"
	intercom_player.stream = _make_tone_stream(0.44, 720.0, 0.20, 3.2, false)
	intercom_player.volume_db = -7.0
	add_child(intercom_player)

	stinger_player = AudioStreamPlayer.new()
	stinger_player.name = "MimicStinger"
	stinger_player.stream = _make_tone_stream(0.52, 132.0, 0.27, 4.8, false)
	stinger_player.volume_db = -5.0
	add_child(stinger_player)


func _update_footsteps(moving: bool, sprinting: bool, delta: float) -> void:
	if not moving:
		footstep_timer = 0.0
		return
	footstep_timer -= delta
	if footstep_timer <= 0.0:
		footstep_player.pitch_scale = 1.15 if sprinting else 0.92
		_play_sound(footstep_player)
		footstep_timer = 0.31 if sprinting else 0.48


func _play_sound(sound_player: AudioStreamPlayer) -> void:
	# Headless validation has no audio device; skipping playback keeps its dummy
	# audio backend from retaining a playback object at process exit.
	if DisplayServer.get_name() != "headless" and is_instance_valid(sound_player):
		sound_player.play()


func _make_ambient_stream() -> AudioStreamWAV:
	const SAMPLE_RATE := 22050
	const DURATION := 4.0
	var frame_count := int(SAMPLE_RATE * DURATION)
	var samples := PackedByteArray()
	samples.resize(frame_count * 2)
	for frame in range(frame_count):
		var time := float(frame) / SAMPLE_RATE
		var hum := sin(TAU * 58.0 * time) * 0.030
		hum += sin(TAU * 117.0 * time) * 0.012
		hum += sin(TAU * 3.0 * time) * 0.004
		samples.encode_s16(frame * 2, int(clampf(hum, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frame_count
	stream.data = samples
	return stream


func _make_tone_stream(duration: float, frequency: float, amplitude: float, decay: float, noisy: bool) -> AudioStreamWAV:
	const SAMPLE_RATE := 22050
	var frame_count := int(SAMPLE_RATE * duration)
	var samples := PackedByteArray()
	samples.resize(frame_count * 2)
	for frame in range(frame_count):
		var time := float(frame) / SAMPLE_RATE
		var envelope := exp(-time * decay)
		var sample := sin(TAU * frequency * time)
		sample += sin(TAU * frequency * 1.97 * time) * 0.25
		if noisy:
			sample += sin(TAU * frequency * 0.43 * time) * 0.45
			sample += sin(TAU * frequency * 3.71 * time) * 0.16
		sample *= amplitude * envelope
		samples.encode_s16(frame * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = samples
	return stream


func _move_player(delta: float) -> void:
	if player_hidden:
		player.velocity = Vector3.ZERO
		footstep_player.stop()
		return
	var input_vector := Vector2.ZERO
	if Input.is_key_pressed(KEY_A):
		input_vector.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		input_vector.x += 1.0
	if Input.is_key_pressed(KEY_W):
		input_vector.y += 1.0
	if Input.is_key_pressed(KEY_S):
		input_vector.y -= 1.0
	var moving := input_vector.length() > 0.01
	var sprinting := moving and Input.is_key_pressed(KEY_SHIFT) and stamina > 0.0
	_update_footsteps(moving, sprinting, delta)
	var speed := PLAYER_SPRINT_SPEED if sprinting else PLAYER_WALK_SPEED
	if sprinting:
		stamina = maxf(0.0, stamina - STAMINA_DRAIN_PER_SECOND * delta)
	else:
		stamina = minf(STAMINA_MAX, stamina + STAMINA_REGEN_PER_SECOND * delta)
	var direction := Vector3.ZERO
	if moving:
		var forward := -player.global_transform.basis.z
		var right := player.global_transform.basis.x
		direction = (right * input_vector.x + forward * input_vector.y).normalized()
	player.velocity.x = direction.x * speed
	player.velocity.z = direction.z * speed
	if not player.is_on_floor():
		player.velocity.y -= 18.0 * delta
	else:
		player.velocity.y = -0.1
	player.move_and_slide()
	var sway_strength := 0.045 if sprinting else 0.022
	var target_y := 0.52 + sin(elapsed * (11.0 if sprinting else 7.0)) * sway_strength if moving else 0.52
	head.position.y = lerpf(head.position.y, target_y, minf(delta * 10.0, 1.0))


func _build_mimic_navigation() -> void:
	# Wait for the store's static collision bodies to enter the physics world.
	await get_tree().physics_frame
	mimic_grid_width = int((MIMIC_NAV_MAX.x - MIMIC_NAV_MIN.x) / MIMIC_NAV_STEP) + 1
	mimic_grid_depth = int((MIMIC_NAV_MAX.y - MIMIC_NAV_MIN.y) / MIMIC_NAV_STEP) + 1
	mimic_grid_walkable.clear()
	var clearance_shape := BoxShape3D.new()
	clearance_shape.size = Vector3(0.82, 1.6, 0.82)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = clearance_shape
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var space_state := get_world_3d().direct_space_state
	for z in range(mimic_grid_depth):
		for x in range(mimic_grid_width):
			var cell := Vector2i(x, z)
			query.transform = Transform3D(Basis.IDENTITY, _mimic_grid_world(cell) + Vector3(0.0, 1.0, 0.0))
			mimic_grid_walkable.append(space_state.intersect_shape(query, 1).is_empty())
	mimic_navigation_ready = true


func _mimic_has_line_of_sight(target: Vector3) -> bool:
	var eye := monster.global_position + Vector3(0.0, 1.55, 0.0)
	var target_eye := Vector3(target.x, maxf(target.y + 0.7, 1.2), target.z)
	var query := PhysicsRayQueryParameters3D.create(eye, target_eye, 1)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _mimic_next_path_point(target: Vector3) -> Vector3:
	var target_changed := _flat_distance(mimic_path_goal, target) > 1.0
	var has_unreached_target := _flat_distance(monster.global_position, target) > MIMIC_NAV_STEP
	if target_changed or (mimic_path.is_empty() and has_unreached_target):
		mimic_path = _find_mimic_path(monster.global_position, target)
		mimic_path_goal = target
	# A new grid path begins at the nearest cell center. Use a generous threshold
	# so replanning mid-cell does not make the mimic oscillate backward.
	while not mimic_path.is_empty() and _flat_distance(monster.global_position, mimic_path[0]) < MIMIC_NAV_STEP * 0.75:
		mimic_path.pop_front()
	if mimic_path.is_empty():
		return monster.global_position
	return mimic_path[0]


func _find_mimic_path(start: Vector3, goal: Vector3) -> Array[Vector3]:
	var start_cell := _nearest_mimic_walkable_cell(start)
	var goal_cell := _nearest_mimic_walkable_cell(goal)
	if start_cell == Vector2i(-1, -1) or goal_cell == Vector2i(-1, -1):
		return []
	var open_cells: Array[Vector2i] = [start_cell]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start_cell: 0.0}
	var f_score: Dictionary = {start_cell: _mimic_grid_heuristic(start_cell, goal_cell)}
	while not open_cells.is_empty():
		var current_index := 0
		var current_f := INF
		for index in range(open_cells.size()):
			var candidate_f := float(f_score.get(open_cells[index], INF))
			if candidate_f < current_f:
				current_f = candidate_f
				current_index = index
		var current: Vector2i = open_cells[current_index]
		open_cells.remove_at(current_index)
		if current == goal_cell:
			return _reconstruct_mimic_path(came_from, current)
		for neighbor in _mimic_grid_neighbors(current):
			if not _mimic_grid_is_walkable(neighbor):
				continue
			var tentative_g := float(g_score.get(current, INF)) + 1.0
			if tentative_g < float(g_score.get(neighbor, INF)):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				f_score[neighbor] = tentative_g + _mimic_grid_heuristic(neighbor, goal_cell)
				if not open_cells.has(neighbor):
					open_cells.append(neighbor)
	return []


func _reconstruct_mimic_path(came_from: Dictionary, current: Vector2i) -> Array[Vector3]:
	var cells: Array[Vector2i] = [current]
	var cursor := current
	while came_from.has(cursor):
		var parent: Vector2i = came_from[cursor]
		cells.append(parent)
		cursor = parent
	cells.reverse()
	var route: Array[Vector3] = []
	for cell in cells:
		route.append(_mimic_grid_world(cell))
	return route


func _nearest_mimic_walkable_cell(position: Vector3) -> Vector2i:
	var base := Vector2i(
		clampi(roundi((position.x - MIMIC_NAV_MIN.x) / MIMIC_NAV_STEP), 0, mimic_grid_width - 1),
		clampi(roundi((position.z - MIMIC_NAV_MIN.y) / MIMIC_NAV_STEP), 0, mimic_grid_depth - 1)
	)
	for radius in range(0, 8):
		for z_offset in range(-radius, radius + 1):
			for x_offset in range(-radius, radius + 1):
				if max(abs(x_offset), abs(z_offset)) != radius:
					continue
				var candidate := base + Vector2i(x_offset, z_offset)
				if _mimic_grid_is_walkable(candidate):
					return candidate
	return Vector2i(-1, -1)


func _mimic_grid_neighbors(cell: Vector2i) -> Array[Vector2i]:
	return [
		cell + Vector2i.LEFT,
		cell + Vector2i.RIGHT,
		cell + Vector2i.UP,
		cell + Vector2i.DOWN
	]


func _mimic_grid_is_walkable(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.x >= mimic_grid_width or cell.y < 0 or cell.y >= mimic_grid_depth:
		return false
	return mimic_grid_walkable[cell.y * mimic_grid_width + cell.x]


func _mimic_grid_world(cell: Vector2i) -> Vector3:
	return Vector3(MIMIC_NAV_MIN.x + cell.x * MIMIC_NAV_STEP, 0.0, MIMIC_NAV_MIN.y + cell.y * MIMIC_NAV_STEP)


func _mimic_grid_heuristic(from: Vector2i, to: Vector2i) -> float:
	return abs(from.x - to.x) + abs(from.y - to.y)


func _update_mimic(delta: float) -> void:
	if not mimic_navigation_ready:
		mimic_has_player_los = false
		return
	if player_hidden:
		attack_exposure = 0.0
	var target := _priority_task_position()
	var player_distance := _flat_distance(monster.global_position, player.global_position)
	mimic_has_player_los = not player_hidden and player_distance < 11.5 and _mimic_has_line_of_sight(player.global_position)
	var chasing := mimic_has_player_los
	if chasing:
		target = player.global_position
	var should_sprint := false
	if chasing and monster_cooldown <= 0.0 and monster_sprint_time < 13.0:
		should_sprint = true
		monster_sprint_time += delta
		if monster_sprint_time >= 13.0:
			monster_cooldown = 7.0
			status_text = "The mimic slows down. Its sprint cannot last forever."
	else:
		monster_cooldown = maxf(0.0, monster_cooldown - delta)
		if monster_cooldown <= 0.0 and not chasing:
			monster_sprint_time = 0.0
	var speed := 6.1 if should_sprint else 2.8
	# A confirmed line of sight is already an obstacle-free route, so avoid an
	# A* search during direct pursuit. Search only while moving task-to-task.
	var navigation_target := target if chasing else _mimic_next_path_point(target)
	var direction := navigation_target - monster.global_position
	direction.y = 0.0
	if direction.length() > 0.55:
		var previous_position := monster.global_position
		monster.velocity = direction.normalized() * speed
		monster.move_and_slide()
		monster_body.look_at(monster.global_position + direction, Vector3.UP, true)
		if _flat_distance(previous_position, monster.global_position) < 0.01:
			mimic_stuck_time += delta
			if mimic_stuck_time >= 0.25:
				mimic_path.clear()
				mimic_stuck_time = 0.0
		else:
			mimic_stuck_time = 0.0
	else:
		monster.velocity = Vector3.ZERO
		mimic_stuck_time = 0.0
	monster_eye_light.light_energy = 1.1 if chasing else 0.0
	var mimic_material_color := Color("78332D") if chasing else SAFETY_ORANGE
	var torso_mesh := monster_body.get_child(0) as MeshInstance3D
	if torso_mesh:
		torso_mesh.material_override = _material(mimic_material_color)
	if chasing and player_distance < 2.55:
		attack_exposure += delta
		if attack_exposure >= 1.65:
			_end_shift(false)
	else:
		attack_exposure = maxf(0.0, attack_exposure - delta * 2.0)


func _update_manager_call() -> void:
	if elapsed >= manager_time and not manager_announced and not manager_task["complete"]:
		manager_announced = true
		var station: Node3D = manager_task["node"]
		station.visible = true
		_play_sound(intercom_player)
		status_text = "INTERCOM - MANAGER: Priority task! Reset the rear breaker. The whole store heard that."


func _update_scripted_sighting() -> void:
	if elapsed < 15.0 or mimic_sighting_done or player_hidden:
		return
	var forward := -player.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.1:
		forward = Vector3.FORWARD
	var appearance_position := player.global_position + forward.normalized() * 9.0
	appearance_position.x = clampf(appearance_position.x, -12.5, 12.5)
	appearance_position.z = clampf(appearance_position.z, -18.0, 9.0)
	appearance_position.y = 0.0
	monster.global_position = appearance_position
	mimic_sighting_done = true
	_play_sound(stinger_player)
	status_text = "You catch an orange uniform standing too still in the aisle."


func _update_lighting(delta: float) -> void:
	# Property updates on shadow-casting lights are more expensive than the math;
	# a 12 Hz flicker remains intentionally choppy while avoiding per-frame churn.
	lighting_update_timer -= delta
	if lighting_update_timer > 0.0:
		return
	lighting_update_timer = 1.0 / 12.0
	for light in flicker_lights:
		var pulse := sin(elapsed * 8.0 + light.position.x * 1.9 + light.position.z) + sin(elapsed * 2.7 + light.position.z)
		light.light_energy = light.get_meta("base_energy") * (0.22 if pulse > 1.15 else 1.0)


func _update_interaction_prompt() -> void:
	current_prompt = ""
	if player_hidden:
		current_prompt = "[E] Leave hiding spot"
		return
	var item := _nearest_interactable()
	if item.is_empty():
		return
	match item["type"]:
		"task":
			var task := _task_for_id(item["task_id"])
			if task.is_empty() or task["complete"]:
				return
			if task["requires"] != "" and not held_tools.has(task["requires"]):
				current_prompt = "[F] " + String(task["title"]) + " (needs " + String(task["requires"]) + ")"
			else:
				current_prompt = "[F] Complete: " + String(task["title"])
		"tool":
			if not held_tools.has(item["tool"]):
				current_prompt = "[F] Take " + String(item["tool"])
		"hide":
			current_prompt = "[E] Hide in " + String(item["title"])


func _nearest_interactable() -> Dictionary:
	var best: Dictionary = {}
	var best_score := -999.0
	var forward := -camera.global_transform.basis.z
	for item in interactables:
		var node: Node3D = item["node"]
		if not is_instance_valid(node) or not node.visible:
			continue
		if item["type"] == "tool" and held_tools.has(item["tool"]):
			continue
		if item["type"] == "task":
			var task := _task_for_id(item["task_id"])
			if task.is_empty() or task["complete"]:
				continue
		var to_item := node.global_position - camera.global_position
		var distance := to_item.length()
		if distance > INTERACTION_RANGE or distance < 0.01:
			continue
		var facing := forward.dot(to_item.normalized())
		if facing < 0.42:
			continue
		var score := facing * 3.0 - distance * 0.15
		if score > best_score:
			best_score = score
			best = item
	return best


func _interact() -> void:
	if player_hidden:
		return
	var item := _nearest_interactable()
	if item.is_empty():
		return
	if item["type"] == "tool":
		var tool_name: String = item["tool"]
		if not held_tools.has(tool_name):
			held_tools[tool_name] = true
			var tool_node: Node3D = item["node"]
			tool_node.visible = false
			status_text = "Picked up " + tool_name + "."
	elif item["type"] == "task":
		_complete_task(item["task_id"])


func _complete_task(id: String) -> void:
	var task := _task_for_id(id)
	if task.is_empty() or task["complete"]:
		return
	if task["requires"] != "" and not held_tools.has(task["requires"]):
		status_text = "You need " + String(task["requires"]) + " before you can do that."
		return
	task["complete"] = true
	var station: Node3D = task["node"]
	station.visible = false
	status_text = "Completed: " + String(task["title"]) + "."
	if _all_tasks_complete():
		_end_shift(true)


func _toggle_hiding() -> void:
	if player_hidden:
		player_hidden = false
		status_text = "You leave the hiding spot."
		return
	var item := _nearest_interactable()
	if not item.is_empty() and item["type"] == "hide":
		player_hidden = true
		attack_exposure = 0.0
		status_text = "Hidden. The mimic cannot see you, but the checklist still waits."


func _task_for_id(id: String) -> Dictionary:
	if id == manager_task.get("id", ""):
		return manager_task
	for task in tasks:
		if task["id"] == id:
			return task
	return {}


func _priority_task() -> Dictionary:
	if manager_announced and not manager_task["complete"]:
		return manager_task
	for task in tasks:
		if not task["complete"]:
			return task
	return {}


func _priority_task_position() -> Vector3:
	var task := _priority_task()
	if task.is_empty():
		return monster.global_position
	return task["position"]


func _all_tasks_complete() -> bool:
	for task in tasks:
		if not task["complete"]:
			return false
	# The manager's instruction is part of the shift, even if the player clears
	# the ordinary list before the intercom call arrives.
	return manager_task["complete"]


func _update_hud() -> void:
	var priority := _priority_task()
	if priority.is_empty():
		objective_label.text = "CLOSING CHECKLIST COMPLETE"
	else:
		var prefix := "PRIORITY // " if manager_announced and priority["id"] == manager_task["id"] else "CURRENT // "
		objective_label.text = prefix + String(priority["title"]).to_upper()
	var lines: Array[String] = ["CLOSING CHECKLIST"]
	for task in tasks:
		lines.append(("[x] " if task["complete"] else "[ ] ") + String(task["title"]))
	if manager_announced:
		lines.append(("[x] " if manager_task["complete"] else "[!] ") + "PRIORITY: " + String(manager_task["title"]))
	checklist_label.text = "\n".join(lines)
	stamina_label.text = "STAMINA  %03d%%" % int(stamina)
	prompt_label.text = current_prompt
	status_label.text = status_text + "\nWASD move  SHIFT sprint  F interact  E hide"
	var monster_distance := _flat_distance(monster.global_position, player.global_position)
	if player_hidden:
		danger_label.text = "HIDDEN // BREAK LINE OF SIGHT"
	elif mimic_has_player_los:
		var run_note := "RUNNING" if monster_sprint_time > 0.0 and monster_cooldown <= 0.0 else "STALKING"
		danger_label.text = "MIMIC " + run_note + " // " + str(int(monster_distance)) + "m"
	elif monster_distance < 11.5:
		danger_label.text = "MIMIC LOST SIGHT BEHIND SHELVES"
	else:
		danger_label.text = "MIMIC SEARCHING TASK LOCATION"


func _end_shift(won: bool) -> void:
	game_ended = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	ambience_player.stop()
	footstep_player.stop()
	end_overlay.visible = true
	if won:
		end_title.text = "SHIFT COMPLETE\n\nEvery closing task is finished. You made it to dawn.\n\nPress R to work another shift."
		end_title.add_theme_color_override("font_color", FLUORESCENT)
	else:
		end_title.text = "THE MIMIC FOUND YOU\n\nPress R to retry."
		end_title.add_theme_color_override("font_color", EMERGENCY_RED)


func _add_static_box(node_name: String, size: Vector3, position: Vector3, color: Color, parent: Node3D = self) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position
	parent.add_child(body)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(color)
	body.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body


func _add_visual_box(node_name: String, size: Vector3, position: Vector3, color: Color, parent: Node3D = self) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	mesh.position = position
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(color)
	parent.add_child(mesh)
	return mesh


func _add_world_label(parent: Node3D, text: String, position: Vector3, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = position
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.006
	label.font_size = 42
	label.outline_size = 8
	label.modulate = color
	label.no_depth_test = false
	parent.add_child(label)
	return label


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	return material


func _flat_distance(a: Vector3, b: Vector3) -> float:
	var delta := a - b
	delta.y = 0.0
	return delta.length()
