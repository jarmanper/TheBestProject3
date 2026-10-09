extends TestCase
## End screen texts, settings persistence and the main menu.

const END_SCREEN := "res://ui/menus/end_screen.tscn"
const SETTINGS := "res://ui/menus/settings_panel.tscn"
const MAIN_MENU := "res://scenes/main_menu.tscn"

var _saved := {}


func before_each() -> void:
	_saved = {
		"sensitivity": GameState.mouse_sensitivity,
		"volume": GameState.master_volume,
		"crt": GameState.crt_enabled,
	}


func after_each() -> void:
	GameState.mouse_sensitivity = _saved.sensitivity
	GameState.set_master_volume(_saved.volume)
	GameState.crt_enabled = _saved.crt
	GameState.save_settings()


func test_end_screen_titles() -> void:
	assert_eq(EndScreen.title_for(&"win"), "SHIFT COMPLETE")
	assert_eq(EndScreen.title_for(&"fired"), "YOU'RE FIRED")
	assert_eq(EndScreen.title_for(&"dead"), "YOU DIDN'T MAKE IT")


func test_end_screen_shows_time_and_stats() -> void:
	GameState.start_night()
	GameState.advance(GameState.SECONDS_PER_HOUR * 2.5)
	GameState.add_stat("tasks_completed", 4)
	GameState.night_running = false
	var screen: EndScreen = (load(END_SCREEN) as PackedScene).instantiate()
	tree.root.add_child(screen)
	screen.show_result(&"dead")
	assert_true(screen.visible)
	assert_eq(screen.get_title_text(), "YOU DIDN'T MAKE IT")
	assert_true(screen.get_body_text().contains("2:30 AM"), "time reached shown")
	assert_true(screen.get_body_text().contains("TASKS COMPLETED"), "stats shown")
	assert_true(screen.get_body_text().contains("4"))
	assert_eq(screen.get_button_texts(), ["WORK ANOTHER SHIFT", "MAIN MENU"] as Array[String])
	screen.free()


func test_settings_apply_and_save() -> void:
	var panel: SettingsPanel = (load(SETTINGS) as PackedScene).instantiate()
	tree.root.add_child(panel)
	panel.open()
	panel.set_sensitivity(0.004)
	panel.set_volume(0.3)
	panel.set_crt(false)
	panel.close()
	assert_near(GameState.mouse_sensitivity, 0.004, 0.00001)
	assert_near(GameState.master_volume, 0.3, 0.001)
	assert_false(GameState.crt_enabled)
	var config := ConfigFile.new()
	assert_eq(config.load(GameState.SETTINGS_PATH), OK, "settings file written")
	assert_near(config.get_value("audio", "master_volume"), 0.3, 0.001)
	assert_false(panel.visible)
	panel.free()


func test_main_menu_buttons() -> void:
	var menu: MainMenu = (load(MAIN_MENU) as PackedScene).instantiate()
	tree.root.add_child(menu)
	await wait_frames(1)
	var texts := menu.get_button_texts()
	assert_true(texts.has("CLOCK IN"))
	assert_true(texts.has("SETTINGS"))
	assert_eq(texts.has("QUIT"), not OS.has_feature("web"), "QUIT hidden only on web")
	assert_eq(menu.get_title_text(), Catalog.GAME_TITLE)
	menu.free()
