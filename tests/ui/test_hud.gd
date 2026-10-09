extends TestCase

const HUD_SCENE := "res://ui/hud/hud.tscn"

var hud: GameHud


func before_each() -> void:
	hud = (load(HUD_SCENE) as PackedScene).instantiate()
	tree.root.add_child(hud)
	await wait_frames(1)


func after_each() -> void:
	GameState.night_running = false
	hud.free()


func _task(title: String, manager := false, time_left := 0.0, completed := false, failed := false) -> TaskData:
	var task := TaskData.new()
	task.title = title
	task.is_manager_task = manager
	task.time_limit = 120.0 if manager and time_left > 0.0 else 0.0
	task.time_left = time_left
	task.completed = completed
	task.failed = failed
	return task


func _texts() -> Array[String]:
	var texts: Array[String] = []
	for row in hud.get_checklist_rows():
		texts.append(row.text)
	return texts


func test_checklist_order_and_styles() -> void:
	var basic_open := _task("Restock Aisle 2")
	var done := _task("Mop the spill in Aisle 3", false, 0.0, true)
	var manager_late := _task("Lock the safe", true, 90.0)
	var failed := _task("Count register 1", true, 0.0, false, true)
	var manager_soon := _task("Reset the breaker", true, 30.0)
	hud.render_checklist([basic_open, done, manager_late, failed, manager_soon])
	assert_eq(_texts(), [
		"[!] Reset the breaker  0:30",
		"[!] Lock the safe  1:30",
		"[ ] Restock Aisle 2",
		"[√] Mop the spill in Aisle 3",
		"[×] Count register 1",
	] as Array[String])
	var rows := hud.get_checklist_rows()
	assert_eq(rows[0].color, Catalog.COLOR_ORANGE, "manager tasks orange")
	assert_eq(rows[2].color, Catalog.COLOR_CREAM, "basic tasks cream")
	assert_true(rows[3].color.a < 0.5, "done tasks dimmed")
	assert_eq(rows[4].color, Catalog.COLOR_RED, "failed tasks red")


func test_countdown_rounds_up_and_untimed_manager_tasks_have_none() -> void:
	hud.render_checklist([_task("Lock the safe", true, 125.2), _task("Face the shelves", true, 0.0)])
	assert_eq(_texts(), ["[!] Lock the safe  2:06", "[!] Face the shelves"] as Array[String])


func test_header_counts_open_basic_tasks() -> void:
	hud.render_checklist([_task("A"), _task("B"), _task("C", false, 0.0, true), _task("M", true, 50.0)])
	assert_eq(hud.get_checklist_header(), "TASKS - 2 LEFT")


func test_toggle_collapses_checklist() -> void:
	hud.render_checklist([_task("A")])
	assert_false(hud.checklist_collapsed)
	hud.toggle_checklist()
	assert_true(hud.checklist_collapsed)
	assert_false(hud.is_checklist_rows_visible(), "rows hidden when collapsed")
	hud.toggle_checklist()
	assert_true(hud.is_checklist_rows_visible())


func test_refresh_reads_tasks_autoload() -> void:
	hud.render_checklist([_task("A")])
	hud.refresh_checklist()
	assert_eq(hud.get_checklist_rows().size(), Tasks.get_tasks_for_checklist().size())


func test_clock_follows_game_state() -> void:
	GameState.start_night()
	GameState.advance(GameState.SECONDS_PER_HOUR * 1.5)
	await wait_frames(2)
	assert_eq(hud.get_clock_text(), "1:30 AM")


func test_prompt_greyed_without_key_hint() -> void:
	Events.interaction_prompt_changed.emit("[E] Mop spill")
	assert_eq(hud.get_prompt_text(), "[E] Mop spill")
	assert_false(hud.is_prompt_greyed())
	Events.interaction_prompt_changed.emit("Needs: Mop")
	assert_eq(hud.get_prompt_text(), "Needs: Mop")
	assert_true(hud.is_prompt_greyed())
	Events.interaction_prompt_changed.emit("")
	assert_eq(hud.get_prompt_text(), "")


func test_hold_bar() -> void:
	Events.interaction_progress.emit(0.5)
	assert_true(hud.is_hold_bar_visible())
	assert_near(hud.get_hold_fraction(), 0.5)
	Events.interaction_progress.emit(-1.0)
	assert_false(hud.is_hold_bar_visible())


func test_subtitles_from_events() -> void:
	Events.subtitle.emit("Somebody's in the back.", 3.0)
	Events.intercom_announced.emit("Clean-up in aisle three.", &"aisle_3")
	var lines := hud.get_subtitle_lines()
	assert_true(lines.has("Somebody's in the back."), "plain subtitle")
	assert_true(lines.has("[INTERCOM] Clean-up in aisle three."), "intercom subtitle")
	for i in 5:
		Events.subtitle.emit("line %d" % i, 3.0)
	assert_eq(hud.get_subtitle_lines().size(), GameHud.SUBTITLE_MAX_LINES, "oldest lines dropped")


func test_subtitles_expire() -> void:
	hud.show_subtitle("short", 0.05)
	await tree.create_timer(0.3).timeout
	assert_false(hud.get_subtitle_lines().has("short"))


func test_walkie_message_subtitle_never_reveals_mimic() -> void:
	Events.walkie_message.emit("RITA", "Can you help me in storage?", Vector3.ZERO, true)
	await wait_frames(1)
	var lines := hud.get_subtitle_lines()
	assert_true(lines.has("[RADIO] RITA: Can you help me in storage?"), "radio subtitle: %s" % [lines])
	for line in lines:
		assert_false(line.to_lower().contains("mimic"))


func test_hide_overlay_follows_spot_kind() -> void:
	var spot := HidingSpot.new()
	spot.spot_kind = &"counter"
	Events.player_hid.emit(spot)
	assert_eq(hud.get_hide_overlay_kind(), &"counter")
	Events.player_unhid.emit(spot)
	assert_eq(hud.get_hide_overlay_kind(), &"")
	spot.free()


func test_intro_card_on_night_start() -> void:
	GameState.start_night()
	assert_true(hud.is_intro_visible(), "intro card shown")
	assert_eq(hud.get_intro_text(), "12:00 AM — CLOCK IN")


func test_hud_never_blocks_mouse() -> void:
	for control in hud.find_children("*", "Control", true, false):
		assert_eq((control as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s ignores the mouse" % control.name)
