class_name EndScreen
extends Control
## End of the night (Events.night_ended): "SHIFT COMPLETE" / "YOU'RE FIRED" / "YOU DIDN'T MAKE IT",
## the time reached, GameState.stats, and WORK ANOTHER SHIFT / MAIN MENU.

signal restart_requested
signal menu_requested

const THEME := preload("res://ui/theme/game_theme.tres")

const STAT_NAMES := {
	"tasks_completed": "TASKS COMPLETED",
	"manager_tasks_completed": "MANAGER TASKS DONE",
	"manager_tasks_failed": "MANAGER TASKS MISSED",
	"damage_taken": "DAMAGE TAKEN",
	"times_hidden": "TIMES HIDDEN",
	"monster_sightings": "SIGHTINGS",
	"coworkers_lost": "COWORKERS LOST",
}

var _title: Label
var _subtitle: Label
var _stats: Label
var _buttons: Array[Button] = []


func _ready() -> void:
	theme = THEME
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	visible = false


static func title_for(result: StringName) -> String:
	match result:
		&"win":
			return "SHIFT COMPLETE"
		&"fired":
			return "YOU'RE FIRED"
		_:
			return "YOU DIDN'T MAKE IT"


static func color_for(result: StringName) -> Color:
	match result:
		&"win":
			return Catalog.COLOR_CREAM
		&"fired":
			return Catalog.COLOR_ORANGE
		_:
			return Catalog.COLOR_RED


func show_result(result: StringName) -> void:
	_title.text = title_for(result)
	_title.add_theme_color_override(&"font_color", color_for(result))
	var time := GameState.get_clock_text()
	match result:
		&"win":
			_subtitle.text = "%s. Every task done. Same time tomorrow night." % time
		&"fired":
			_subtitle.text = "%s. You made it, but the checklist didn't. Hand in your badge." % time
		_:
			_subtitle.text = "Your shift ended at %s." % time
	var lines := PackedStringArray(["TIME REACHED  %s" % time, ""])
	for key: String in STAT_NAMES:
		var value: Variant = GameState.stats.get(key, 0)
		lines.append("%-22s %s" % [STAT_NAMES[key], str(roundi(value)) if value is float else str(value)])
	_stats.text = "\n".join(lines)
	visible = true
	_buttons[0].grab_focus()


func get_title_text() -> String:
	return _title.text


func get_body_text() -> String:
	return _subtitle.text + "\n" + _stats.text


func get_button_texts() -> Array[String]:
	var texts: Array[String] = []
	for button in _buttons:
		texts.append(button.text)
	return texts


func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.018, 0.017, 0.88)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.offset_left = -420.0
	column.offset_right = 420.0
	column.offset_top = -280.0
	column.offset_bottom = 280.0
	column.add_theme_constant_override(&"separation", 8)
	add_child(column)
	_title = Label.new()
	_title.add_theme_font_size_override(&"font_size", 96)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)
	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override(&"font_size", 28)
	_subtitle.add_theme_color_override(&"font_color", Color(Catalog.COLOR_CREAM, 0.8))
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_subtitle)
	_stats = Label.new()
	_stats.add_theme_font_size_override(&"font_size", 28)
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_stats.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_stats)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 24)
	column.add_child(row)
	_buttons.append(_button(row, "WORK ANOTHER SHIFT", func() -> void: restart_requested.emit()))
	_buttons.append(_button(row, "MAIN MENU", func() -> void: menu_requested.emit()))


func _button(row: HBoxContainer, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(func() -> void:
		Sfx.play(&"ui_click")
		action.call())
	row.add_child(button)
	return button
