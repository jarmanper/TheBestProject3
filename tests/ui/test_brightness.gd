extends TestCase
## Brightness setting: GameState clamping/persistence, the settings slider, the post-fx
## uniform (with CRT on and off), and the pause menu's QUIT GAME button.

const SETTINGS := "res://ui/menus/settings_panel.tscn"
const PAUSE_MENU := "res://ui/menus/pause_menu.tscn"
const POSTFX := "res://ui/postfx/postfx.tscn"

var _saved := {}


func before_each() -> void:
	_saved = {
		"brightness": GameState.brightness,
		"crt": GameState.crt_enabled,
	}


func after_each() -> void:
	GameState.brightness = _saved.brightness
	GameState.crt_enabled = _saved.crt
	GameState.save_settings()


func test_brightness_clamps_to_range() -> void:
	GameState.brightness = 0.0
	assert_near(GameState.brightness, GameState.BRIGHTNESS_MIN, 0.001, "clamped to minimum")
	GameState.brightness = -5.0
	assert_near(GameState.brightness, GameState.BRIGHTNESS_MIN, 0.001, "clamped to minimum")
	GameState.brightness = 2.0
	assert_near(GameState.brightness, 1.0, 0.001, "never above 1.0")
	GameState.brightness = 0.7
	assert_near(GameState.brightness, 0.7, 0.001, "mid-range value kept")


func test_brightness_persists_through_save_load() -> void:
	GameState.brightness = 0.55
	GameState.save_settings()
	GameState.brightness = 1.0
	GameState.load_settings()
	assert_near(GameState.brightness, 0.55, 0.001, "brightness reloaded from settings.cfg")
	var config := ConfigFile.new()
	assert_eq(config.load(GameState.SETTINGS_PATH), OK, "settings file written")
	assert_near(config.get_value("video", "brightness"), 0.55, 0.001)


func test_settings_panel_brightness_slider() -> void:
	var panel: SettingsPanel = (load(SETTINGS) as PackedScene).instantiate()
	tree.root.add_child(panel)
	panel.open()
	var slider_range := panel.get_brightness_range()
	assert_near(slider_range.x, GameState.BRIGHTNESS_MIN, 0.001, "slider minimum is 40%")
	assert_near(slider_range.y, 1.0, 0.001, "slider maximum is 100%")
	panel.set_brightness(0.4)
	assert_near(GameState.brightness, 0.4, 0.001)
	panel.set_brightness(2.0)
	assert_near(GameState.brightness, 1.0, 0.001, "slider cannot push brightness above 1.0")
	panel.free()


func test_postfx_brightness_uniform_follows_gamestate_crt_on_and_off() -> void:
	var fx: CanvasLayer = (load(POSTFX) as PackedScene).instantiate()
	tree.root.add_child(fx)
	var material: ShaderMaterial = (fx.get_node("Screen") as ColorRect).material

	GameState.crt_enabled = true
	GameState.brightness = 0.65
	await wait_frames(2)
	assert_true(fx.visible, "post-fx pass stays visible with CRT on")
	assert_near(float(material.get_shader_parameter(&"brightness")), 0.65, 0.001, "brightness applied with CRT on")

	GameState.crt_enabled = false
	GameState.brightness = 0.45
	await wait_frames(2)
	assert_true(fx.visible, "post-fx pass stays visible with CRT off (brightness must still apply)")
	assert_near(float(material.get_shader_parameter(&"brightness")), 0.45, 0.001, "brightness applied with CRT off")
	assert_near(float(material.get_shader_parameter(&"vignette_strength")), 0.0, 0.001, "CRT look removed when off")
	fx.free()


func test_quit_game_button_desktop_vs_web() -> void:
	var menu: PauseMenu = (load(PAUSE_MENU) as PackedScene).instantiate()
	tree.root.add_child(menu)
	menu.open()
	var texts := menu.get_button_texts()
	assert_eq(texts.has("QUIT GAME"), not OS.has_feature("web"), "QUIT GAME hidden only on web")
	assert_true(texts.has("RESUME"))
	assert_true(texts.has("QUIT TO MENU"))
	menu.free()
