class_name Game
extends Node
## The game scene (docs/ARCHITECTURE.md §6). Loads the level into the half-resolution 3D
## viewport, spawns the player and (when their scenes exist) the coworkers, monster and store
## manager at the level's markers, starts the night, runs ambience/music, and owns mouse
## capture, pausing and the end screen.
##
## Mouse events are forwarded into the SubViewport explicitly (the container ignores the mouse):
## with a captured/locked pointer the GUI does not route motion to the container reliably,
## and the player reads InputEventMouseMotion.screen_relative so look speed ignores the shrink.

enum State { LOADING, PLAYING, PAUSED, ENDED }

## Emitted once the night has started (state PLAYING).
signal started

const AMBIENCE_DB := -8.0
const DREAD_DB := -17.0
const CHASE_DB := -7.0
const SILENT_DB := -60.0
const MUSIC_FADE := 1.6
const NAV_WAIT_FRAMES := 120

## Screenshot/test runs turn this off so they do not grab the desktop mouse.
@export var capture_mouse_on_start := true

var state := State.LOADING
var level: Node3D
var player: Player

var _had_capture := false
var _ambience: AudioStreamPlayer
var _music_dread: AudioStreamPlayer
var _music_chase: AudioStreamPlayer
var _music_tween: Tween

@onready var world_view: SubViewportContainer = $WorldView
@onready var sub_viewport: SubViewport = $WorldView/SubViewport
@onready var world: Node3D = $WorldView/SubViewport/World
@onready var hud: GameHud = $HUD
@onready var pause_menu: PauseMenu = $Menus/PauseMenu
@onready var end_screen: EndScreen = $Menus/EndScreen


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	world_view.process_mode = Node.PROCESS_MODE_PAUSABLE
	hud.process_mode = Node.PROCESS_MODE_PAUSABLE
	get_tree().paused = false
	GameState.world_root = world
	pause_menu.resume_requested.connect(resume_game)
	pause_menu.quit_requested.connect(quit_to_menu)
	end_screen.restart_requested.connect(restart)
	end_screen.menu_requested.connect(quit_to_menu)
	Events.night_ended.connect(_on_night_ended)
	Events.chase_started.connect(_on_chase_started)
	Events.chase_ended.connect(_on_chase_ended)

	_spawn_level()
	_spawn_player()
	await _wait_for_navigation()
	_spawn_npcs()
	_start_audio()
	Tasks.reset()
	GameState.start_night()
	Tasks.begin_night()
	state = State.PLAYING
	if capture_mouse_on_start:
		_capture_mouse()
	started.emit()


func _exit_tree() -> void:
	if GameState.world_root == world:
		GameState.world_root = null
	if is_instance_valid(GameState.monster) and is_ancestor_of(GameState.monster):
		GameState.monster = null
	GameState.night_running = false
	get_tree().paused = false


func _input(event: InputEvent) -> void:
	if state != State.PLAYING or not (event is InputEventMouse):
		return
	var shrink := float(maxi(world_view.stretch_shrink, 1))
	sub_viewport.push_input(event.xformed_by(Transform2D.IDENTITY.scaled(Vector2.ONE / shrink)), true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		if state == State.PLAYING:
			pause_game()
			get_viewport().set_input_as_handled()
		elif state == State.PAUSED:
			if pause_menu.is_settings_open():
				pause_menu.close_settings()
			else:
				resume_game()
			get_viewport().set_input_as_handled()
	elif state == State.PLAYING and event is InputEventMouseButton and event.is_pressed() \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		# Click back into the game (web: pointer lock needs a user gesture).
		_capture_mouse()


func _process(_delta: float) -> void:
	if state != State.PLAYING:
		return
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_had_capture = true
	elif _had_capture:
		# Pointer lock lost: web Esc (the browser eats the key), alt-tab, focus change.
		pause_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == State.PLAYING and _had_capture:
		pause_game()


func pause_game() -> void:
	if state != State.PLAYING:
		return
	state = State.PAUSED
	get_tree().paused = true
	_release_mouse()
	pause_menu.open()


func resume_game() -> void:
	if state != State.PAUSED:
		return
	pause_menu.close()
	state = State.PLAYING
	get_tree().paused = false
	_capture_mouse()


func restart() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(Catalog.SCENES.game)


func quit_to_menu() -> void:
	get_tree().paused = false
	_release_mouse()
	get_tree().change_scene_to_file(Catalog.SCENES.main_menu)


# --- Spawning ---------------------------------------------------------------------

func _spawn_level() -> void:
	var scene := Catalog.load_scene_or_null(Catalog.SCENES.level)
	if scene == null:
		scene = Catalog.load_scene_or_null(Catalog.SCENES.level_greybox)
	level = scene.instantiate() as Node3D
	level.name = "Level"
	world.add_child(level)


func _spawn_player() -> void:
	player = (load(Catalog.SCENES.player) as PackedScene).instantiate()
	player.name = "Player"
	var spawn := _markers(&"player_spawn")
	if not spawn.is_empty():
		player.transform = _spawn_transform(spawn[0])
	world.add_child(player)


## Coworkers, monster and store manager — each only if its scene exists yet.
func _spawn_npcs() -> void:
	var coworker_scene := Catalog.load_scene_or_null(Catalog.SCENES.coworker)
	if coworker_scene:
		var spawns := _markers(&"coworker_spawn")
		for i in Catalog.COWORKERS.size():
			var info: Dictionary = Catalog.COWORKERS[i]
			var coworker := coworker_scene.instantiate()
			coworker.name = "Coworker%s" % String(info.name).capitalize()
			coworker.set(&"employee_name", info.name)
			coworker.set(&"model_path", info.model)
			if not spawns.is_empty() and coworker is Node3D:
				(coworker as Node3D).transform = _spawn_transform(spawns[i % spawns.size()])
			world.add_child(coworker)
	var monster_scene := Catalog.load_scene_or_null(Catalog.SCENES.monster)
	if monster_scene:
		var monster := monster_scene.instantiate()
		monster.name = "Monster"
		var spawns := _markers(&"monster_spawn")
		if not spawns.is_empty() and monster is Node3D:
			(monster as Node3D).transform = _spawn_transform(spawns[0])
		world.add_child(monster)
	var manager_scene := Catalog.load_scene_or_null(Catalog.SCENES.store_manager)
	if manager_scene:
		var manager := manager_scene.instantiate()
		manager.name = "StoreManager"
		world.add_child(manager)


func _markers(group: StringName) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group(group):
		if node is Node3D and level.is_ancestor_of(node):
			found.append(node)
	return found


func _spawn_transform(marker: Node3D) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, marker.global_rotation.y), marker.global_position)


## Navigation regions sync asynchronously; AI must not query the map before it has the level.
func _wait_for_navigation() -> void:
	if level.find_children("*", "NavigationRegion3D", true, false).is_empty():
		return
	var map := world.get_world_3d().navigation_map
	var probe := player.global_position
	for i in NAV_WAIT_FRAMES:
		if NavigationServer3D.map_get_iteration_id(map) > 0 \
				and NavigationServer3D.map_get_closest_point(map, probe).distance_to(probe) < 1.0:
			return
		await get_tree().physics_frame
	push_warning("Game: navigation map not ready after %d physics frames" % NAV_WAIT_FRAMES)


# --- Audio ------------------------------------------------------------------------------

func _start_audio() -> void:
	_ambience = _make_player(&"amb_store_hum", &"Ambience", AMBIENCE_DB)
	_music_dread = _make_player(&"music_dread", &"Music", DREAD_DB)
	_music_chase = _make_player(&"music_chase", &"Music", SILENT_DB, false)


func _make_player(id: StringName, bus: StringName, volume_db: float, autoplay := true) -> AudioStreamPlayer:
	var audio := AudioStreamPlayer.new()
	audio.name = String(id).to_pascal_case()
	audio.stream = Sfx.get_stream(id)
	audio.bus = bus
	audio.volume_db = volume_db
	add_child(audio)
	if autoplay and audio.stream:
		audio.play()
	return audio


func _on_chase_started() -> void:
	if _music_chase.stream and not _music_chase.playing:
		_music_chase.play()
	_crossfade(_music_chase, CHASE_DB, _music_dread, SILENT_DB)


func _on_chase_ended() -> void:
	if _music_dread.stream and not _music_dread.playing:
		_music_dread.play()
	_crossfade(_music_dread, DREAD_DB, _music_chase, SILENT_DB)


func _crossfade(fade_in: AudioStreamPlayer, in_db: float, fade_out: AudioStreamPlayer, out_db: float) -> void:
	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween().set_parallel()
	_music_tween.tween_property(fade_in, ^"volume_db", in_db, MUSIC_FADE)
	_music_tween.tween_property(fade_out, ^"volume_db", out_db, MUSIC_FADE)


# --- Mouse / end of night -------------------------------------------------------------------

func _capture_mouse() -> void:
	_had_capture = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _release_mouse() -> void:
	_had_capture = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_night_ended(result: StringName) -> void:
	if state == State.ENDED:
		return
	state = State.ENDED
	pause_menu.close()
	_release_mouse()
	get_tree().paused = true
	hud.visible = false
	if _music_chase and _music_chase.playing:
		_on_chase_ended()
	end_screen.show_result(result)
