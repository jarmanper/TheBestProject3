class_name PauseMenu
extends Control
## Pause overlay: RESUME / SETTINGS / QUIT TO MENU. The game scene decides what the
## buttons do (signals) and owns pausing + mouse capture.

signal resume_requested
signal quit_requested

const THEME := preload("res://ui/theme/game_theme.tres")
const SETTINGS_SCENE := preload("res://ui/menus/settings_panel.tscn")

var _buttons: VBoxContainer
var _clock: Label
var _resume: Button
var _settings: SettingsPanel


func _ready() -> void:
	theme = THEME
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	visible = false


func open() -> void:
	_clock.text = "%s  -  %s" % [GameState.get_clock_text(), "SHIFT IN PROGRESS"]
	_settings.visible = false
	_buttons.visible = true
	visible = true
	_resume.grab_focus()


func close() -> void:
	_settings.visible = false
	visible = false


func is_settings_open() -> bool:
	return _settings.visible


func close_settings() -> void:
	if _settings.visible:
		_settings.close()


func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.025, 0.024, 0.72)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	_buttons = VBoxContainer.new()
	_buttons.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_buttons.offset_left = 120.0
	_buttons.offset_top = -170.0
	_buttons.offset_right = 620.0
	_buttons.offset_bottom = 170.0
	_buttons.add_theme_constant_override(&"separation", 6)
	add_child(_buttons)
	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override(&"font_size", 84)
	title.add_theme_color_override(&"font_color", Catalog.COLOR_CREAM)
	_buttons.add_child(title)
	_clock = Label.new()
	_clock.add_theme_font_size_override(&"font_size", 28)
	_clock.add_theme_color_override(&"font_color", Color(Catalog.COLOR_CREAM, 0.6))
	_buttons.add_child(_clock)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 16
	_buttons.add_child(spacer)
	_resume = _button("RESUME", func() -> void: resume_requested.emit())
	_button("SETTINGS", func() -> void:
		_buttons.visible = false
		_settings.open())
	_button("QUIT TO MENU", func() -> void: quit_requested.emit())

	_settings = SETTINGS_SCENE.instantiate()
	add_child(_settings)
	_settings.closed.connect(func() -> void:
		_buttons.visible = true
		_resume.grab_focus())


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(func() -> void:
		Sfx.play(&"ui_click")
		action.call())
	button.mouse_entered.connect(func() -> void: Sfx.play(&"ui_hover", -10.0))
	_buttons.add_child(button)
	return button
