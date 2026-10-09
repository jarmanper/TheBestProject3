extends SceneTree
## HUD icon check: every icon in a reference-3 style slot box (grey frame, dark inside) at 3x,
## nearest-filtered, plus a 1x row at native size, over a dark background.
##   godot --path . --rendering-driver opengl3 --resolution 960x540 -s res://tools/shots/props_icons.gd -- --out=/abs/dir
## Writes props_icons.png.

const ICONS := ["flashlight", "mop", "price_gun", "box_cutter", "stock_box", "keys", "walkie"]
const SLOT := 108
const SCALE := 3

var _out := "user://shots"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	var canvas := Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(canvas)
	var background := ColorRect.new()
	background.color = Color("0d100f")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(background)
	var x := 24.0
	for icon: String in ICONS:
		var texture := load("res://assets/ui/icons/icon_%s.png" % icon) as Texture2D
		var frame := ColorRect.new()
		frame.color = Color("8c8c84")
		frame.position = Vector2(x, 60)
		frame.size = Vector2(SLOT, SLOT)
		canvas.add_child(frame)
		var inside := ColorRect.new()
		inside.color = Color("101312")
		inside.position = Vector2(3, 3)
		inside.size = Vector2(SLOT - 6, SLOT - 6)
		frame.add_child(inside)
		var big := TextureRect.new()
		big.texture = texture
		big.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		big.stretch_mode = TextureRect.STRETCH_SCALE
		big.size = Vector2(32 * SCALE, 32 * SCALE)
		big.position = Vector2((SLOT - 32 * SCALE) * 0.5, (SLOT - 32 * SCALE) * 0.5)
		frame.add_child(big)
		var label := Label.new()
		label.text = icon.to_upper()
		label.position = Vector2(x, 60 + SLOT + 6)
		label.add_theme_color_override(&"font_color", Color("e9e6d2"))
		canvas.add_child(label)
		var small := TextureRect.new()
		small.texture = texture
		small.position = Vector2(x + (SLOT - 32) * 0.5, 260)
		canvas.add_child(small)
		x += SLOT + 24
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := _out.path_join("props_icons.png")
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
	quit()
