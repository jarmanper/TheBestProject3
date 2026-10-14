extends PanelContainer
## Pre-game WebRTC lobby UI. The lobby is intentionally kept separate from
## gameplay replication so every online shift begins from a known roster.

signal closed

var _name_edit: LineEdit
var _code_edit: LineEdit
var _status: Label
var _roster: VBoxContainer
var _host: Button
var _join: Button
var _ready_button: Button
var _start: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left = -300.0
	offset_right = 300.0
	offset_top = -250.0
	offset_bottom = 250.0
	visible = false
	_build()
	_connect_session()


func _exit_tree() -> void:
	var session := _session()
	if session == null:
		return
	for connection: Array in [
		[&"status_changed", _on_status_changed],
		[&"lobby_updated", _on_lobby_updated],
		[&"connection_failed", _on_connection_failed],
		[&"match_started", _on_match_started],
	]:
		if session.is_connected(connection[0], connection[1]):
			session.disconnect(connection[0], connection[1])


func open() -> void:
	visible = true
	_call_session(&"refresh_configuration")
	_name_edit.grab_focus()
	_refresh()


func close() -> void:
	_call_session(&"leave_lobby")
	visible = false
	closed.emit()


func _build() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 28)
	margin.add_theme_constant_override(&"margin_right", 28)
	margin.add_theme_constant_override(&"margin_top", 24)
	margin.add_theme_constant_override(&"margin_bottom", 24)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 10)
	margin.add_child(column)
	var title := Label.new()
	title.text = "ONLINE LOBBY"
	title.add_theme_font_size_override(&"font_size", 40)
	title.add_theme_color_override(&"font_color", Catalog.COLOR_ORANGE)
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Create a crew room or join one with a six-character code."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override(&"font_size", 20)
	column.add_child(subtitle)
	_name_edit = _field("YOUR CALLSIGN", "Night Crew")
	column.add_child(_name_edit)
	_code_edit = _field("LOBBY CODE", "ABC123")
	_code_edit.max_length = 6
	column.add_child(_code_edit)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override(&"separation", 8)
	column.add_child(actions)
	_host = _button("HOST LOBBY", func() -> void: _call_session(&"create_lobby", [_name_edit.text]))
	_join = _button("JOIN LOBBY", func() -> void: _call_session(&"join_lobby", [_code_edit.text, _name_edit.text]))
	actions.add_child(_host)
	actions.add_child(_join)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 52
	_status.add_theme_font_size_override(&"font_size", 18)
	column.add_child(_status)
	var roster_title := Label.new()
	roster_title.text = "CREW"
	roster_title.add_theme_color_override(&"font_color", Catalog.COLOR_ORANGE)
	column.add_child(roster_title)
	_roster = VBoxContainer.new()
	_roster.custom_minimum_size.y = 88
	column.add_child(_roster)
	var lobby_actions := HBoxContainer.new()
	lobby_actions.add_theme_constant_override(&"separation", 8)
	column.add_child(lobby_actions)
	_ready_button = _button("READY", func() -> void: _call_session(&"set_ready", [true]))
	_start = _button("START SHIFT", func() -> void: _call_session(&"start_match"))
	var leave := _button("LEAVE", close)
	lobby_actions.add_child(_ready_button)
	lobby_actions.add_child(_start)
	lobby_actions.add_child(leave)


func _field(label_text: String, placeholder: String) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = label_text
	field.text = placeholder
	field.add_theme_font_size_override(&"font_size", 22)
	return field


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override(&"font_size", 20)
	button.pressed.connect(func() -> void:
		_play_ui_sound(&"ui_click")
		action.call())
	button.mouse_entered.connect(func() -> void: _play_ui_sound(&"ui_hover", -10.0))
	return button


func _on_status_changed(text: String) -> void:
	_status.text = text
	_refresh()


func _on_lobby_updated(_code: String, members: Array[Dictionary], host_id: int) -> void:
	for child in _roster.get_children():
		child.queue_free()
	for member in members:
		var line := Label.new()
		var role := "HOST" if int(member.get("id", 0)) == host_id else ("READY" if member.get("ready", false) else "NOT READY")
		line.text = "%s  —  %s" % [String(member.get("name", "Night Crew")), role]
		line.add_theme_font_size_override(&"font_size", 18)
		_roster.add_child(line)
	_refresh()


func _on_connection_failed(_reason: String) -> void:
	_refresh()


func _on_match_started() -> void:
	_status.text = "Network session ready. Gameplay synchronization is the next integration step."
	_refresh()


func _refresh() -> void:
	var session := _session()
	var configured := session != null and bool(session.call(&"is_configured"))
	var in_lobby := session != null and not String(session.get(&"lobby_code")).is_empty()
	_host.disabled = not configured or in_lobby
	_join.disabled = not configured or in_lobby
	_ready_button.disabled = not in_lobby
	_start.disabled = not in_lobby or session == null or not bool(session.call(&"is_host"))


func _session() -> Node:
	return get_tree().root.get_node_or_null(^"MultiplayerSession")


func _connect_session() -> void:
	var session := _session()
	if session == null:
		return
	session.connect(&"status_changed", _on_status_changed)
	session.connect(&"lobby_updated", _on_lobby_updated)
	session.connect(&"connection_failed", _on_connection_failed)
	session.connect(&"match_started", _on_match_started)


func _call_session(method: StringName, args: Array = []) -> Variant:
	var session := _session()
	return session.callv(method, args) if session != null else null


func _play_ui_sound(sound_id: StringName, volume_db := 0.0) -> void:
	var sfx := get_tree().root.get_node_or_null(^"Sfx")
	if sfx != null:
		sfx.call(&"play", sound_id, volume_db)
