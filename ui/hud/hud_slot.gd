class_name HudSlot
extends Control
## Square item slot (reference 3): frame + 32 px icon drawn at 1.5x, nearest.
## Without an icon file it draws a flashlight shape or a short text tag.

@export var lit := true

var icon: Texture2D
var fallback_text := ""
var draw_flashlight := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Loads `path` if it exists; otherwise uses the fallback drawing.
func set_icon_path(path: String, text := "", flashlight_shape := false) -> void:
	icon = load(path) as Texture2D if ResourceLoader.exists(path) else null
	fallback_text = text
	draw_flashlight = flashlight_shape
	queue_redraw()


func clear() -> void:
	icon = null
	fallback_text = ""
	draw_flashlight = false
	queue_redraw()


func set_lit(value: bool) -> void:
	if lit != value:
		lit = value
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color(0.0, 0.0, 0.0, 0.45))
	draw_rect(rect, Color(0.93, 0.93, 0.9, 0.55), false, 2.0)
	var tint := Color(1, 1, 1, 1.0 if lit else 0.35)
	if icon:
		var icon_size := Vector2(48, 48)
		draw_texture_rect(icon, Rect2((size - icon_size) * 0.5, icon_size), false, tint)
	elif draw_flashlight:
		_draw_flashlight_shape(tint)
	elif not fallback_text.is_empty():
		var font := get_theme_default_font()
		var font_size := 22
		var text_size := font.get_string_size(fallback_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(font, Vector2((size.x - text_size.x) * 0.5, (size.y + font_size * 0.6) * 0.5),
			fallback_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(Catalog.COLOR_CREAM, tint.a))


## A diagonal flashlight like the icons in references 2/3, with a beam when lit.
func _draw_flashlight_shape(tint: Color) -> void:
	var c := size * 0.5
	var color := Color(Catalog.COLOR_CREAM, tint.a)
	var dir := Vector2(1, -1).normalized()
	var side := Vector2(-dir.y, dir.x)
	var tail := c - dir * 14.0
	var neck := c + dir * 4.0
	var head := c + dir * 11.0
	draw_colored_polygon(PackedVector2Array([
		tail + side * 3.5, neck + side * 3.5, neck - side * 3.5, tail - side * 3.5]), color)
	draw_colored_polygon(PackedVector2Array([
		neck + side * 3.5, head + side * 6.5, head - side * 6.5, neck - side * 3.5]), color)
	if lit:
		var beam := Color(Catalog.COLOR_CREAM, 0.35)
		draw_colored_polygon(PackedVector2Array([
			head + side * 6.0, head + dir * 12.0 + side * 11.0,
			head + dir * 12.0 - side * 11.0, head - side * 6.0]), beam)
