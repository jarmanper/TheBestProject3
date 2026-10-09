class_name HudMinimap
extends Control
## Top-down minimap (reference 3) drawn from the level's StoreZone rectangles (x/z) with the
## player arrow. Never shows the monster or coworkers. North-up: -Z (the back) is up.

const PADDING := 6.0
const ZONE_REFRESH := 1.0
const COLOR_BACK := Color(0.05, 0.075, 0.06, 0.85)
const COLOR_FRAME := Color(0.93, 0.93, 0.9, 0.5)
const COLOR_ZONE := Color(0.36, 0.39, 0.37, 0.85)
const COLOR_ZONE_EDGE := Color(0.62, 0.65, 0.6, 0.6)
const COLOR_CURRENT := Color(0.47, 0.52, 0.42, 0.95)
const COLOR_PLAYER := Color(0.45, 0.95, 0.5)
const COLOR_RACK := Color(0.55, 0.85, 0.86, 0.95)      ## cool cyan — "where is the mop"
const COLOR_UNLOCK_RING := Color(1.0, 1.0, 1.0, 0.85)
const TASK_RADIUS := 3.0
const RACK_RADIUS := 3.4
const MARKER_MARGIN := 5.0
const PULSE_SPEED := 0.9    ## cycles/second

var _zones: Array[Dictionary] = []     ## {id, rect (world x/z)}
var _bounds := Rect2()
var _refresh := 0.0
var _pulse := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_refresh -= delta
	_pulse += delta
	if _refresh <= 0.0:
		_refresh = ZONE_REFRESH
		collect_zones()
	queue_redraw()


func collect_zones() -> void:
	_zones.clear()
	var bounds := Rect2()
	for node in get_tree().get_nodes_in_group(&"store_zone"):
		var zone := node as StoreZone
		if zone == null or not zone.is_inside_tree():
			continue
		var box := zone.get_bounds()
		var rect := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
		_zones.append({"id": zone.zone_id, "rect": rect})
		bounds = rect if bounds.size == Vector2.ZERO else bounds.merge(rect)
	_bounds = bounds


func get_zone_count() -> int:
	return _zones.size()


## World position -> local pixel position.
func world_to_map(point: Vector3) -> Vector2:
	if _bounds.size.x <= 0.0 or _bounds.size.y <= 0.0:
		return size * 0.5
	var area := size - Vector2(PADDING, PADDING) * 2.0
	var scale_factor := minf(area.x / _bounds.size.x, area.y / _bounds.size.y)
	var offset := (size - _bounds.size * scale_factor) * 0.5
	return offset + (Vector2(point.x, point.z) - _bounds.position) * scale_factor


## Keeps a marker's pixel position inside the map's drawable rect (never clipped at an edge).
func _clamp_to_map(point: Vector2) -> Vector2:
	var w: float = size.x
	var h: float = size.y
	if w <= MARKER_MARGIN * 2.0 or h <= MARKER_MARGIN * 2.0:
		return point
	return Vector2(clampf(point.x, MARKER_MARGIN, w - MARKER_MARGIN), clampf(point.y, MARKER_MARGIN, h - MARKER_MARGIN))


## Pure (no drawing): the markers to show for the current tasks/player state. Each entry is
## either {"type": &"task", "position": Vector3, "manager": bool, "highlighted": bool} for an
## open task (highlighted = the player already holds the tool it needs — ring it instead of
## marking its rack), or {"type": &"rack", "position": Vector3} for the rack of a tool an open
## task needs that the player does NOT hold (one marker per tool id, only while the rack still
## has the tool). Never includes the monster or coworkers.
func collect_markers() -> Array[Dictionary]:
	var markers: Array[Dictionary] = []
	var player := GameState.player
	var has_player := is_instance_valid(player) and player.is_inside_tree()
	var tree := get_tree()
	var racks_marked := {}
	for item in Tasks.get_open_tasks():
		var task := item as TaskData
		if task == null or task.station == null:
			continue
		var needs_tool: bool = task.required_tool != &""
		var holding: bool = needs_tool and has_player and player.has_tool(task.required_tool)
		markers.append({
			"type": &"task",
			"position": task.station.global_position,
			"manager": task.is_manager_task,
			"highlighted": holding,
		})
		if needs_tool and not holding and tree and not racks_marked.has(task.required_tool):
			racks_marked[task.required_tool] = true
			var rack := ToolPickup.find_rack(tree, task.required_tool)
			if rack and rack.has_tool:
				markers.append({"type": &"rack", "position": rack.global_position})
	return markers


func _draw_marker(marker: Dictionary) -> void:
	var at := _clamp_to_map(world_to_map(marker.position))
	if marker.type == &"rack":
		var pts := PackedVector2Array([
			at + Vector2(0, -RACK_RADIUS), at + Vector2(RACK_RADIUS, 0),
			at + Vector2(0, RACK_RADIUS), at + Vector2(-RACK_RADIUS, 0),
		])
		draw_colored_polygon(pts, COLOR_RACK)
		return
	var manager: bool = marker.manager
	var color: Color = Catalog.COLOR_ORANGE if manager else Catalog.COLOR_CREAM
	if manager:
		color.a = lerpf(0.65, 1.0, 0.5 + 0.5 * sin(_pulse * TAU * PULSE_SPEED))
	draw_circle(at, TASK_RADIUS, color)
	if marker.highlighted:
		draw_arc(at, TASK_RADIUS + 3.0, 0.0, TAU, 20, COLOR_UNLOCK_RING, 1.5, true)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BACK)
	var player := GameState.player
	var has_player := is_instance_valid(player) and player.is_inside_tree()
	var current: StringName = &""
	if has_player:
		current = StoreZone.find_zone_id_at(get_tree(), player.global_position)
	for zone in _zones:
		var rect: Rect2 = zone.rect
		var a := world_to_map(Vector3(rect.position.x, 0, rect.position.y))
		var b := world_to_map(Vector3(rect.end.x, 0, rect.end.y))
		var map_rect := Rect2(a, b - a)
		draw_rect(map_rect, COLOR_CURRENT if zone.id == current else COLOR_ZONE)
		draw_rect(map_rect, COLOR_ZONE_EDGE, false, 1.0)
	for marker in collect_markers():
		_draw_marker(marker)
	if has_player:
		var at := world_to_map(player.global_position)
		var forward := -player.global_transform.basis.z
		var dir := Vector2(forward.x, forward.z).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.UP
		var side := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([at + dir * 7.0, at - dir * 4.0 + side * 4.5, at - dir * 4.0 - side * 4.5]), COLOR_PLAYER)
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_FRAME, false, 2.0)
