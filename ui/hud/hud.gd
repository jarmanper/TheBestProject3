class_name GameHud
extends CanvasLayer
## In-game HUD (references 2/3, no ammo). Top-left: HEALTH bar, flashlight + held-tool slots,
## stamina bar. Top-right: minimap, clock, task checklist. Centre: crosshair dot, interaction
## prompt, hold bar. Bottom: subtitles ([RADIO] / [INTERCOM] / Events.subtitle). Full screen:
## damage flash, low-health tint, hiding overlay, intro card. Never takes mouse input.
## Player-side 2D audio lives here too: the walkie radio, the heartbeat, and the task_fail sting.

const THEME := preload("res://ui/theme/game_theme.tres")

const MARGIN := 40.0
const RIGHT_COLUMN_WIDTH := 340.0
const SUBTITLE_MAX_LINES := 3
const CHECKLIST_TICK := 0.25
const INTRO_TIME := 3.5
const TASK_FAIL_DB := -4.0
const MARK_OPEN := "[ ]"
const MARK_MANAGER := "[!]"
const MARK_DONE := "[√]"
const MARK_FAILED := "[×]"

const COLOR_TEXT := Color(0.93, 0.93, 0.9)
const COLOR_DONE := Color(0.847, 0.827, 0.659, 0.38)
const COLOR_PROMPT_OFF := Color(0.58, 0.58, 0.55)

var checklist_collapsed := false

var _tasks: Array[TaskData] = []
var _rows: Array[Dictionary] = []
var _row_labels: Array[Label] = []
var _row_colors: Array[Color] = []
var _subtitles: Array[Dictionary] = []      ## {label, panel, time_left}
var _checklist_timer := 0.0
var _intro_time := 0.0
var _flash := 0.0
var _health_shown := 1.0
var _stamina_alpha := 0.0
var _shown_tool: StringName = &"__none__"
var _prompt_greyed := false

var _root: Control
var _health_bar: HudBar
var _flashlight_slot: HudSlot
var _tool_slot: HudSlot
var _tool_label: Label
var _stamina_bar: HudBar
var _minimap: HudMinimap
var _clock: Label
var _checklist_header: Label
var _checklist_rows: VBoxContainer
var _crosshair: ColorRect
var _prompt: Label
var _hold_bar: HudBar
var _subtitle_box: VBoxContainer
var _damage_flash: ColorRect
var _low_health: ColorRect
var _hide_overlay: HudHideOverlay
var _intro: Control
var _intro_label: Label
var _radio: WalkieRadio
var _heartbeat: Heartbeat


func _ready() -> void:
	layer = 2
	_build()
	_radio = WalkieRadio.new()
	_radio.name = "WalkieRadio"
	add_child(_radio)
	_radio.message_started.connect(_on_radio_message)
	_heartbeat = Heartbeat.new()
	_heartbeat.name = "Heartbeat"
	add_child(_heartbeat)
	Events.interaction_prompt_changed.connect(_on_prompt_changed)
	Events.interaction_progress.connect(_on_progress)
	Events.player_damaged.connect(_on_player_damaged)
	Events.player_died.connect(_on_player_died)
	Events.player_hid.connect(_on_player_hid)
	Events.player_unhid.connect(_on_player_unhid)
	Events.subtitle.connect(show_subtitle)
	Events.intercom_announced.connect(_on_intercom)
	Events.night_started.connect(_on_night_started)
	Events.tasks_changed.connect(refresh_checklist)
	Events.task_added.connect(_on_task_event)
	Events.task_completed.connect(_on_task_completed)
	Events.task_failed.connect(_on_task_failed)
	refresh_checklist()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_checklist"):
		toggle_checklist()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_update_player_widgets(delta)
	_clock.text = GameState.get_clock_text()
	_checklist_timer -= delta
	if _checklist_timer <= 0.0:
		_checklist_timer = CHECKLIST_TICK
		render_checklist(_tasks)
	update_subtitles(delta)
	_flash = maxf(_flash - delta * 1.6, 0.0)
	_set_alpha(_damage_flash, _flash * 0.45)
	if _intro_time > 0.0:
		_intro_time -= delta
		_intro.modulate.a = clampf(_intro_time / 0.8, 0.0, 1.0)
		_intro.visible = _intro_time > 0.0


# --- Checklist -----------------------------------------------------------------

## Pulls the night's tasks from the Tasks autoload and renders them.
func refresh_checklist() -> void:
	render_checklist(Tasks.get_tasks_for_checklist())


## Renders `tasks` (any order): open manager tasks (soonest deadline first), open basic tasks,
## then finished ones (done dimmed with a check, failed in red).
func render_checklist(tasks: Array) -> void:
	_tasks = sort_for_checklist(tasks)
	_rows.clear()
	for task in _tasks:
		_rows.append({"text": format_task(task), "color": color_for(task)})
	# Row labels are pooled: surplus rows are hidden, never freed, so a re-render in the
	# same frame cannot reuse a label that is about to be deleted.
	while _row_labels.size() < _rows.size():
		var label := _make_label(24)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = RIGHT_COLUMN_WIDTH - 24.0
		_checklist_rows.add_child(label)
		_row_labels.append(label)
		_row_colors.append(Color(0, 0, 0, 0))
	for i in _row_labels.size():
		var label := _row_labels[i]
		label.visible = i < _rows.size()
		if not label.visible:
			continue
		label.text = _rows[i].text
		var color: Color = _rows[i].color
		if color != _row_colors[i]:
			_row_colors[i] = color
			label.add_theme_color_override(&"font_color", color)
	_checklist_header.text = get_checklist_header() + ("  [TAB]" if checklist_collapsed else "")
	_checklist_rows.visible = not checklist_collapsed


static func sort_for_checklist(tasks: Array) -> Array[TaskData]:
	var manager: Array[TaskData] = []
	var basic: Array[TaskData] = []
	var finished: Array[TaskData] = []
	for item in tasks:
		var task := item as TaskData
		if task == null:
			continue
		if not task.is_open():
			finished.append(task)
		elif task.is_manager_task:
			manager.append(task)
		else:
			basic.append(task)
	manager.sort_custom(func(a: TaskData, b: TaskData) -> bool:
		var a_left := a.time_left if a.time_limit > 0.0 else INF
		var b_left := b.time_left if b.time_limit > 0.0 else INF
		return a_left < b_left)
	var sorted: Array[TaskData] = []
	sorted.append_array(manager)
	sorted.append_array(basic)
	sorted.append_array(finished)
	return sorted


static func format_task(task: TaskData) -> String:
	if task.failed:
		return "%s %s" % [MARK_FAILED, task.title]
	if task.completed:
		return "%s %s" % [MARK_DONE, task.title]
	if task.is_manager_task:
		var text := "%s %s" % [MARK_MANAGER, task.title]
		if task.time_limit > 0.0:
			var seconds := int(ceilf(maxf(task.time_left, 0.0)))
			text += "  %d:%02d" % [floori(seconds / 60.0), seconds % 60]
		return text
	return "%s %s" % [MARK_OPEN, task.title]


static func color_for(task: TaskData) -> Color:
	if task.failed:
		return Catalog.COLOR_RED
	if task.completed:
		return COLOR_DONE
	if task.is_manager_task:
		return Catalog.COLOR_ORANGE
	return Catalog.COLOR_CREAM


func get_checklist_rows() -> Array[Dictionary]:
	return _rows


func get_checklist_header() -> String:
	var left := 0
	for task in _tasks:
		if task.is_open() and not task.is_manager_task:
			left += 1
	return "TASKS - %d LEFT" % left


func toggle_checklist() -> void:
	checklist_collapsed = not checklist_collapsed
	render_checklist(_tasks)


func is_checklist_rows_visible() -> bool:
	return _checklist_rows.visible


# --- Subtitles -----------------------------------------------------------------

func show_subtitle(text: String, duration: float) -> void:
	if text.is_empty():
		return
	while _subtitles.size() >= SUBTITLE_MAX_LINES:
		var oldest: Dictionary = _subtitles.pop_front()
		oldest.panel.queue_free()
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"SubtitlePanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var label := _make_label(28)
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if text.begins_with("[RADIO]"):
		label.add_theme_color_override(&"font_color", Catalog.COLOR_CREAM)
	elif text.begins_with("[INTERCOM]"):
		label.add_theme_color_override(&"font_color", Color(0.75, 0.86, 0.95))
	panel.add_child(label)
	_subtitle_box.add_child(panel)
	_subtitles.append({"label": label, "panel": panel, "time_left": duration})


func get_subtitle_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	for item in _subtitles:
		lines.append((item.label as Label).text)
	return lines


## Ages subtitles by `delta` seconds and drops expired ones (called from _process).
func update_subtitles(delta: float) -> void:
	for i in range(_subtitles.size() - 1, -1, -1):
		_subtitles[i].time_left -= delta
		if _subtitles[i].time_left <= 0.0:
			_subtitles[i].panel.queue_free()
			_subtitles.remove_at(i)


# --- Accessors (tests, screenshots) -----------------------------------------------

func get_clock_text() -> String:
	return _clock.text


func get_prompt_text() -> String:
	return _prompt.text


func is_prompt_greyed() -> bool:
	return _prompt_greyed


func is_hold_bar_visible() -> bool:
	return _hold_bar.visible


func get_hold_fraction() -> float:
	return _hold_bar.value


func get_hide_overlay_kind() -> StringName:
	return _hide_overlay.kind


func is_intro_visible() -> bool:
	return _intro.visible


func get_intro_text() -> String:
	return _intro_label.text


func get_radio() -> WalkieRadio:
	return _radio


func get_heartbeat() -> Heartbeat:
	return _heartbeat


# --- Event handlers ----------------------------------------------------------------

func _on_prompt_changed(text: String) -> void:
	_prompt.text = text
	_prompt_greyed = not text.is_empty() and not text.begins_with("[E]")
	_prompt.add_theme_color_override(&"font_color", COLOR_PROMPT_OFF if _prompt_greyed else COLOR_TEXT)


func _on_progress(fraction: float) -> void:
	_hold_bar.visible = fraction >= 0.0
	_hold_bar.set_value(maxf(fraction, 0.0))


func _on_player_damaged(_amount: float, _health_left: float) -> void:
	_flash = 1.0


func _on_player_died() -> void:
	_crosshair.visible = false
	_prompt.text = ""
	_hold_bar.visible = false


func _on_player_hid(spot: Node3D) -> void:
	var kind: Variant = spot.get(&"spot_kind") if spot else null
	_hide_overlay.show_kind(kind if kind is StringName else &"locker")
	_crosshair.visible = false


func _on_player_unhid(_spot: Node3D) -> void:
	_hide_overlay.clear()
	_crosshair.visible = true


func _on_intercom(message: String, _zone: StringName) -> void:
	show_subtitle("[INTERCOM] %s" % message, clampf(message.length() * 0.07, 4.0, 9.0))


func _on_radio_message(speaker_name: String, message: String, duration: float) -> void:
	show_subtitle("[RADIO] %s: %s" % [speaker_name, message], duration)


func _on_night_started() -> void:
	_intro_label.text = "%s — CLOCK IN" % GameState.get_clock_text()
	_intro_time = INTRO_TIME
	_intro.modulate.a = 1.0
	_intro.visible = true
	refresh_checklist()


func _on_task_event(_task: TaskData) -> void:
	refresh_checklist()


func _on_task_completed(_task: TaskData, _by: Node) -> void:
	refresh_checklist()


## A manager task ran out of time: the checklist row turns red and a short sting plays.
func _on_task_failed(_task: TaskData) -> void:
	Sfx.play(&"task_fail", TASK_FAIL_DB)
	refresh_checklist()


# --- Player widgets -------------------------------------------------------------------

func _update_player_widgets(delta: float) -> void:
	var player := GameState.player as Player
	if not is_instance_valid(player):
		return
	var fraction := clampf(player.health / maxf(player.max_health, 1.0), 0.0, 1.0)
	_health_shown = move_toward(_health_shown, fraction, delta * 1.5)
	_health_bar.set_value(_health_shown)
	_set_alpha(_low_health, clampf((0.35 - fraction) / 0.35, 0.0, 1.0) * 0.22)

	_stamina_bar.set_value(player.stamina / maxf(player.max_stamina, 1.0))
	_stamina_bar.set_fill_color(Catalog.COLOR_RED if player.is_exhausted else Catalog.COLOR_CREAM)
	var stamina_full := player.stamina >= player.max_stamina - 0.01
	_stamina_alpha = move_toward(_stamina_alpha, 0.0 if stamina_full else 1.0, delta * 2.5)
	_stamina_bar.modulate.a = _stamina_alpha

	_flashlight_slot.set_lit(player.flashlight_on)
	var tool_id := player.held_tool
	if tool_id != _shown_tool:
		_shown_tool = tool_id
		if tool_id == &"":
			_tool_slot.clear()
			_tool_label.text = ""
		else:
			_tool_slot.set_icon_path(Catalog.tool_icon_path(tool_id), Catalog.tool_name(tool_id).substr(0, 4).to_upper())
			_tool_label.text = Catalog.tool_name(tool_id).to_upper()


# --- Construction ----------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.theme = THEME
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_low_health = _full_rect("LowHealth", Color(Catalog.COLOR_RED, 0.0))
	_damage_flash = _full_rect("DamageFlash", Color(Catalog.COLOR_RED, 0.0))
	_hide_overlay = HudHideOverlay.new()
	_hide_overlay.name = "HideOverlay"
	_root.add_child(_hide_overlay)
	_hide_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Top-left: health, slots, stamina.
	var top_left := VBoxContainer.new()
	top_left.name = "TopLeft"
	top_left.position = Vector2(MARGIN, MARGIN - 6.0)
	top_left.add_theme_constant_override(&"separation", 4)
	_root.add_child(top_left)
	_health_bar = HudBar.new()
	_health_bar.name = "HealthBar"
	_health_bar.custom_minimum_size = Vector2(230, 18)
	top_left.add_child(_health_bar)
	var health_label := _make_label(28)
	health_label.text = "HEALTH"
	top_left.add_child(health_label)
	var slots := HBoxContainer.new()
	slots.name = "Slots"
	slots.add_theme_constant_override(&"separation", 10)
	top_left.add_child(slots)
	_flashlight_slot = HudSlot.new()
	_flashlight_slot.name = "FlashlightSlot"
	_flashlight_slot.custom_minimum_size = Vector2(64, 64)
	_flashlight_slot.set_icon_path(Catalog.tool_icon_path(&"flashlight"), "", true)
	slots.add_child(_flashlight_slot)
	var tool_column := VBoxContainer.new()
	tool_column.add_theme_constant_override(&"separation", 0)
	slots.add_child(tool_column)
	_tool_slot = HudSlot.new()
	_tool_slot.name = "ToolSlot"
	_tool_slot.custom_minimum_size = Vector2(64, 64)
	tool_column.add_child(_tool_slot)
	_tool_label = _make_label(22)
	_tool_label.name = "ToolName"
	tool_column.add_child(_tool_label)
	_stamina_bar = HudBar.new()
	_stamina_bar.name = "StaminaBar"
	_stamina_bar.custom_minimum_size = Vector2(230, 6)
	_stamina_bar.fill_color = Catalog.COLOR_CREAM
	_stamina_bar.frame_color = Color(0, 0, 0, 0)
	_stamina_bar.inset = 1.0
	_stamina_bar.modulate.a = 0.0
	top_left.add_child(_stamina_bar)

	# Top-right: minimap, clock, checklist.
	var top_right := VBoxContainer.new()
	top_right.name = "TopRight"
	top_right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top_right.offset_left = -MARGIN - RIGHT_COLUMN_WIDTH
	top_right.offset_right = -MARGIN
	top_right.offset_top = MARGIN - 6.0
	top_right.add_theme_constant_override(&"separation", 2)
	_root.add_child(top_right)
	_minimap = HudMinimap.new()
	_minimap.name = "Minimap"
	_minimap.custom_minimum_size = Vector2(168, 136)
	_minimap.size_flags_horizontal = Control.SIZE_SHRINK_END
	top_right.add_child(_minimap)
	_clock = _make_label(40)
	_clock.name = "Clock"
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock.text = GameState.get_clock_text()
	top_right.add_child(_clock)
	_checklist_header = _make_label(24)
	_checklist_header.name = "ChecklistHeader"
	_checklist_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_checklist_header.add_theme_color_override(&"font_color", Catalog.COLOR_CREAM)
	top_right.add_child(_checklist_header)
	_checklist_rows = VBoxContainer.new()
	_checklist_rows.name = "ChecklistRows"
	_checklist_rows.add_theme_constant_override(&"separation", -2)
	top_right.add_child(_checklist_rows)

	# Centre: crosshair, prompt, hold bar.
	_crosshair = ColorRect.new()
	_crosshair.name = "Crosshair"
	_crosshair.color = Color(Catalog.COLOR_CREAM, 0.75)
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.offset_left = -2.0
	_crosshair.offset_top = -2.0
	_crosshair.offset_right = 2.0
	_crosshair.offset_bottom = 2.0
	_root.add_child(_crosshair)
	_prompt = _make_label(30)
	_prompt.name = "Prompt"
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_prompt.offset_left = -300.0
	_prompt.offset_right = 300.0
	_prompt.offset_top = 26.0
	_prompt.offset_bottom = 60.0
	_root.add_child(_prompt)
	_hold_bar = HudBar.new()
	_hold_bar.name = "HoldBar"
	_hold_bar.fill_color = Catalog.COLOR_CREAM
	_hold_bar.set_anchors_preset(Control.PRESET_CENTER)
	_hold_bar.offset_left = -80.0
	_hold_bar.offset_right = 80.0
	_hold_bar.offset_top = 66.0
	_hold_bar.offset_bottom = 74.0
	_hold_bar.visible = false
	_root.add_child(_hold_bar)

	# Bottom: subtitles.
	_subtitle_box = VBoxContainer.new()
	_subtitle_box.name = "Subtitles"
	_subtitle_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_subtitle_box.offset_left = -520.0
	_subtitle_box.offset_right = 520.0
	_subtitle_box.offset_top = -170.0
	_subtitle_box.offset_bottom = -MARGIN - 20.0
	_subtitle_box.alignment = BoxContainer.ALIGNMENT_END
	_subtitle_box.add_theme_constant_override(&"separation", 4)
	_root.add_child(_subtitle_box)

	# Intro card.
	_intro = Control.new()
	_intro.name = "IntroCard"
	_intro.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_intro)
	var intro_back := ColorRect.new()
	intro_back.color = Color(0.0, 0.0, 0.0, 0.55)
	intro_back.set_anchors_preset(Control.PRESET_CENTER)
	intro_back.offset_left = -360.0
	intro_back.offset_right = 360.0
	intro_back.offset_top = -70.0
	intro_back.offset_bottom = 60.0
	_intro.add_child(intro_back)
	var intro_title := _make_label(26)
	intro_title.text = Catalog.GAME_TITLE
	intro_title.add_theme_color_override(&"font_color", Catalog.COLOR_ORANGE)
	intro_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro_title.set_anchors_preset(Control.PRESET_CENTER)
	intro_title.offset_left = -360.0
	intro_title.offset_right = 360.0
	intro_title.offset_top = -62.0
	intro_title.offset_bottom = -30.0
	_intro.add_child(intro_title)
	_intro_label = _make_label(64)
	_intro_label.name = "IntroText"
	_intro_label.text = "12:00 AM — CLOCK IN"
	_intro_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro_label.set_anchors_preset(Control.PRESET_CENTER)
	_intro_label.offset_left = -360.0
	_intro_label.offset_right = 360.0
	_intro_label.offset_top = -34.0
	_intro_label.offset_bottom = 40.0
	_intro.add_child(_intro_label)
	_intro.visible = false

	_set_mouse_ignore(_root)


func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override(&"font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _full_rect(node_name: String, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = node_name
	rect.color = color
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(rect)
	return rect


## ColorRect.color redraws on every assignment; only touch it when the alpha changes.
static func _set_alpha(rect: ColorRect, alpha: float) -> void:
	if not is_equal_approx(rect.color.a, alpha):
		rect.color.a = alpha


static func _set_mouse_ignore(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_set_mouse_ignore(child)
