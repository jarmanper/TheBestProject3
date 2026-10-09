class_name SettingsPanel
extends PanelContainer
## Settings shared by the main menu and the pause menu: mouse sensitivity, master volume,
## CRT effect, fullscreen. Changes apply immediately; GameState.save_settings() on close.

signal closed

const THEME := preload("res://ui/theme/game_theme.tres")
const SENSITIVITY_MIN := 0.0005
const SENSITIVITY_MAX := 0.008
const SENSITIVITY_DEFAULT := 0.0025

var _sensitivity: HSlider
var _sensitivity_value: Label
var _volume: HSlider
var _volume_value: Label
var _crt: CheckButton
var _fullscreen: CheckButton
var _back: Button


func _ready() -> void:
	theme = THEME
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	_build()
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	_sensitivity.set_value_no_signal(GameState.mouse_sensitivity)
	_volume.set_value_no_signal(GameState.master_volume)
	_crt.set_pressed_no_signal(GameState.crt_enabled)
	_fullscreen.set_pressed_no_signal(_is_fullscreen())
	_update_value_labels()
	visible = true
	_sensitivity.grab_focus()


func close() -> void:
	GameState.save_settings()
	visible = false
	closed.emit()


func set_sensitivity(value: float) -> void:
	GameState.mouse_sensitivity = clampf(value, SENSITIVITY_MIN, SENSITIVITY_MAX)
	_sensitivity.set_value_no_signal(GameState.mouse_sensitivity)
	_update_value_labels()


func set_volume(value: float) -> void:
	GameState.set_master_volume(value)
	_volume.set_value_no_signal(GameState.master_volume)
	_update_value_labels()


func set_crt(on: bool) -> void:
	GameState.crt_enabled = on
	_crt.set_pressed_no_signal(on)


func set_fullscreen(on: bool) -> void:
	_fullscreen.set_pressed_no_signal(on)
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)


func _is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


func _update_value_labels() -> void:
	_sensitivity_value.text = "x%.1f" % (GameState.mouse_sensitivity / SENSITIVITY_DEFAULT)
	_volume_value.text = "%d%%" % roundi(GameState.master_volume * 100.0)


func _build() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 10)
	add_child(column)
	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_size_override(&"font_size", 48)
	title.add_theme_color_override(&"font_color", Catalog.COLOR_ORANGE)
	column.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 18)
	grid.add_theme_constant_override(&"v_separation", 12)
	column.add_child(grid)
	_sensitivity = _slider(grid, "MOUSE SENSITIVITY", SENSITIVITY_MIN, SENSITIVITY_MAX, 0.0001)
	_sensitivity_value = _value_label(grid)
	_sensitivity.value_changed.connect(set_sensitivity)
	_volume = _slider(grid, "MASTER VOLUME", 0.0, 1.0, 0.05)
	_volume_value = _value_label(grid)
	_volume.value_changed.connect(set_volume)

	_crt = CheckButton.new()
	_crt.text = "CRT SCREEN EFFECT"
	_crt.toggled.connect(set_crt)
	column.add_child(_crt)
	_fullscreen = CheckButton.new()
	_fullscreen.text = "FULLSCREEN"
	_fullscreen.toggled.connect(set_fullscreen)
	column.add_child(_fullscreen)

	_back = Button.new()
	_back.text = "BACK"
	_back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_back.pressed.connect(func() -> void:
		Sfx.play(&"ui_click")
		close())
	column.add_child(_back)


func _slider(grid: GridContainer, caption: String, min_value: float, max_value: float, step: float) -> HSlider:
	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override(&"font_size", 30)
	grid.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.custom_minimum_size = Vector2(260, 28)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(slider)
	return slider


func _value_label(grid: GridContainer) -> Label:
	var label := Label.new()
	label.custom_minimum_size.x = 70
	label.add_theme_font_size_override(&"font_size", 30)
	grid.add_child(label)
	return label
