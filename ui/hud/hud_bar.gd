class_name HudBar
extends Control
## Flat bar with a dark back and a thin light frame (the health bar of reference 3).

@export var fill_color := Catalog.COLOR_RED
@export var back_color := Color(0.0, 0.0, 0.0, 0.55)
@export var frame_color := Color(0.93, 0.93, 0.9, 0.35)
@export var inset := 2.0

var value := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_fill_color(color: Color) -> void:
	if color != fill_color:
		fill_color = color
		queue_redraw()


func set_value(new_value: float) -> void:
	new_value = clampf(new_value, 0.0, 1.0)
	if not is_equal_approx(new_value, value):
		value = new_value
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), back_color)
	var inner := Rect2(Vector2(inset, inset), Vector2((size.x - inset * 2.0) * value, size.y - inset * 2.0))
	if inner.size.x > 0.0:
		draw_rect(inner, fill_color)
	if frame_color.a > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), frame_color, false, 1.0)
