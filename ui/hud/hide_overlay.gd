class_name HudHideOverlay
extends Control
## Screen overlay while hidden, by HidingSpot.spot_kind: locker = dark with horizontal vent
## slits, counter = dark underside above, boxes = cardboard edges around a gap.

const FADE_SPEED := 4.0

var kind: StringName = &""
var _shown_kind: StringName = &""
var _alpha := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func show_kind(spot_kind: StringName) -> void:
	kind = spot_kind
	if not kind.is_empty():
		_shown_kind = kind
	queue_redraw()


func clear() -> void:
	kind = &""


func _process(delta: float) -> void:
	var target := 1.0 if not kind.is_empty() else 0.0
	if not is_equal_approx(_alpha, target):
		_alpha = move_toward(_alpha, target, FADE_SPEED * delta)
		queue_redraw()
	visible = _alpha > 0.0


func _draw() -> void:
	if _alpha <= 0.0:
		return
	var w := size.x
	var h := size.y
	match _shown_kind:
		&"locker":
			var dark := Color(0.02, 0.025, 0.022, 0.97 * _alpha)
			var slit_count := 6
			var slit_h := h * 0.035
			var gap := h * 0.06
			var total := slit_count * slit_h + (slit_count - 1) * gap
			var top := (h - total) * 0.5
			var x0 := w * 0.2
			var x1 := w * 0.8
			draw_rect(Rect2(0, 0, w, top), dark)
			draw_rect(Rect2(0, top + total, w, h - top - total), dark)
			draw_rect(Rect2(0, top, x0, total), dark)
			draw_rect(Rect2(x1, top, w - x1, total), dark)
			for i in slit_count:
				var y := top + i * (slit_h + gap) + slit_h
				if i < slit_count - 1:
					draw_rect(Rect2(x0, y, x1 - x0, gap), dark)
				# soft slit edges
				var edge := Color(dark, dark.a * 0.5)
				draw_rect(Rect2(x0, y - slit_h, x1 - x0, slit_h * 0.2), edge)
				draw_rect(Rect2(x0, y - slit_h * 0.2, x1 - x0, slit_h * 0.2), edge)
		&"counter":
			var under := Color(0.02, 0.022, 0.02, 0.96 * _alpha)
			draw_rect(Rect2(0, 0, w, h * 0.38), under)
			_gradient_band(0.38, 0.55, under)
			var side := Color(0.0, 0.0, 0.0, 0.55 * _alpha)
			draw_rect(Rect2(0, 0, w * 0.06, h), side)
			draw_rect(Rect2(w * 0.94, 0, w * 0.06, h), side)
		&"boxes":
			var card := Color(0.16, 0.12, 0.08, 0.96 * _alpha)
			draw_rect(Rect2(0, 0, w * 0.33, h), card)
			draw_rect(Rect2(w * 0.67, 0, w * 0.33, h), card)
			draw_rect(Rect2(0, 0, w, h * 0.22), card)
			var edge := Color(0.32, 0.24, 0.15, 0.9 * _alpha)
			draw_rect(Rect2(w * 0.33 - 6, h * 0.22, 6, h * 0.78), edge)
			draw_rect(Rect2(w * 0.67, h * 0.22, 6, h * 0.78), edge)
		_:
			draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.6 * _alpha))


## Vertical fade from `color` at y0 to transparent at y1 (fractions of the height).
func _gradient_band(y0: float, y1: float, color: Color) -> void:
	var w := size.x
	var top := size.y * y0
	var bottom := size.y * y1
	var clear_color := Color(color, 0.0)
	draw_polygon(PackedVector2Array([Vector2(0, top), Vector2(w, top), Vector2(w, bottom), Vector2(0, bottom)]),
		PackedColorArray([color, color, clear_color, clear_color]))
