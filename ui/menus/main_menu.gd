class_name MainMenu
extends Control
## Title screen (project main scene): GRAVEYARD SHIFT over a dark flickering CRT background,
## CLOCK IN / SETTINGS / QUIT (hidden on web) and a controls panel. CLOCK IN captures the
## mouse from the click (the web build needs this user gesture for pointer lock).

const THEME := preload("res://ui/theme/game_theme.tres")
const BACKGROUND_SHADER := preload("res://ui/menus/menu_background.gdshader")
const POSTFX_SCENE := preload("res://ui/postfx/postfx.tscn")
const SETTINGS_SCENE := preload("res://ui/menus/settings_panel.tscn")

const CONTROLS := [
	["WASD / ARROWS", "MOVE"],
	["SHIFT", "SPRINT"],
	["E / LEFT MOUSE", "INTERACT (HOLD FOR TASKS)"],
	["F / RIGHT MOUSE", "FLASHLIGHT"],
	["TAB", "TASK LIST"],
	["ESC / P", "PAUSE"],
]
const HINTS := [
	"Finish your tasks before 6:00 AM.",
	"Hide in lockers, under counters, behind boxes.",
	"A coworker who stops working and just stares is not your coworker.",
	"It can only sprint for 13 seconds.",
]

var _title: Label
var _buttons: VBoxContainer
var _settings: SettingsPanel
var _music: AudioStreamPlayer
var _flicker := 0.0


func _ready() -> void:
	theme = THEME
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()
	add_child(POSTFX_SCENE.instantiate())
	var stream := Sfx.get_stream(&"music_dread")
	if stream:
		_music = AudioStreamPlayer.new()
		_music.stream = stream
		_music.bus = &"Music"
		_music.volume_db = -14.0
		add_child(_music)
		_music.play()
	(_buttons.get_child(0) as Button).grab_focus()


func _process(delta: float) -> void:
	# The title buzzes like a failing sign.
	_flicker -= delta
	if _flicker <= 0.0:
		_flicker = randf_range(0.05, 0.6)
		_title.modulate.a = 0.55 if randf() < 0.12 else 1.0


func get_button_texts() -> Array[String]:
	var texts: Array[String] = []
	for child in _buttons.get_children():
		var button := child as Button
		if button and button.visible:
			texts.append(button.text)
	return texts


func get_title_text() -> String:
	return _title.text


func _clock_in() -> void:
	Sfx.play(&"time_clock_punch")
	# Captured inside the click handler: browsers only grant pointer lock on a user gesture.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().change_scene_to_file(Catalog.SCENES.game)


func _build() -> void:
	var background := ColorRect.new()
	background.name = "Background"
	var material := ShaderMaterial.new()
	material.shader = BACKGROUND_SHADER
	background.material = material
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	column.offset_left = 120.0
	column.offset_right = 760.0
	column.offset_top = -250.0
	column.offset_bottom = 250.0
	column.add_theme_constant_override(&"separation", 4)
	add_child(column)
	var overline := Label.new()
	overline.text = "NIGHT CREW  //  12:00 AM - 6:00 AM"
	overline.add_theme_font_size_override(&"font_size", 28)
	overline.add_theme_color_override(&"font_color", Color(Catalog.COLOR_CREAM, 0.55))
	column.add_child(overline)
	_title = Label.new()
	_title.name = "Title"
	_title.text = Catalog.GAME_TITLE
	_title.add_theme_font_size_override(&"font_size", 120)
	_title.add_theme_color_override(&"font_color", Catalog.COLOR_CREAM)
	_title.add_theme_color_override(&"font_shadow_color", Color(Catalog.COLOR_RED, 0.75))
	_title.add_theme_constant_override(&"shadow_offset_x", 4)
	_title.add_theme_constant_override(&"shadow_offset_y", 3)
	column.add_child(_title)
	var tagline := Label.new()
	tagline.text = "Finish your tasks. Trust no one in orange."
	tagline.add_theme_font_size_override(&"font_size", 32)
	tagline.add_theme_color_override(&"font_color", Catalog.COLOR_ORANGE)
	column.add_child(tagline)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 36
	column.add_child(spacer)
	_buttons = VBoxContainer.new()
	_buttons.name = "Buttons"
	_buttons.add_theme_constant_override(&"separation", 4)
	column.add_child(_buttons)
	_button("CLOCK IN", _clock_in)
	_button("SETTINGS", func() -> void:
		_buttons.visible = false
		_settings.open())
	var quit := _button("QUIT", func() -> void: get_tree().quit())
	quit.visible = not OS.has_feature("web")

	var panel := PanelContainer.new()
	panel.name = "Controls"
	panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	panel.offset_left = -500.0
	panel.offset_right = -90.0
	panel.offset_top = -170.0
	panel.offset_bottom = 230.0
	add_child(panel)
	var controls := VBoxContainer.new()
	controls.add_theme_constant_override(&"separation", 2)
	panel.add_child(controls)
	var header := Label.new()
	header.text = "CONTROLS"
	header.add_theme_color_override(&"font_color", Catalog.COLOR_ORANGE)
	controls.add_child(header)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 18)
	controls.add_child(grid)
	for pair: Array in CONTROLS:
		for i in 2:
			var cell := Label.new()
			cell.text = pair[i]
			cell.add_theme_font_size_override(&"font_size", 24)
			cell.add_theme_color_override(&"font_color", Catalog.COLOR_CREAM if i == 0 else Color(0.93, 0.93, 0.9, 0.8))
			grid.add_child(cell)
	var rule := Control.new()
	rule.custom_minimum_size.y = 10
	controls.add_child(rule)
	for hint: String in HINTS:
		var line := Label.new()
		line.text = "- " + hint
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size.x = 360
		line.add_theme_font_size_override(&"font_size", 22)
		line.add_theme_color_override(&"font_color", Color(0.93, 0.93, 0.9, 0.62))
		controls.add_child(line)

	var footer := Label.new()
	footer.text = "HEADPHONES RECOMMENDED"
	footer.add_theme_font_size_override(&"font_size", 22)
	footer.add_theme_color_override(&"font_color", Color(Catalog.COLOR_CREAM, 0.4))
	footer.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	footer.offset_left = 120.0
	footer.offset_top = -70.0
	footer.offset_bottom = -40.0
	add_child(footer)

	_settings = SETTINGS_SCENE.instantiate()
	add_child(_settings)
	_settings.closed.connect(func() -> void:
		_buttons.visible = true
		(_buttons.get_child(0) as Button).grab_focus())


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override(&"font_size", 48)
	button.pressed.connect(func() -> void:
		Sfx.play(&"ui_click")
		action.call())
	button.mouse_entered.connect(func() -> void: Sfx.play(&"ui_hover", -10.0))
	_buttons.add_child(button)
	return button
