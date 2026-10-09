class_name StoreAreaCuller
extends Node
## Portal culling for the store (the web build's draw-call budget). The level's meshes are put
## on one visual layer per area (sales floor, back hallway, storage, break room, office,
## janitor closet; a wall between two areas is on both). Every frame the active camera's
## cull mask keeps only the areas it can see: its own, plus each area whose doorway is on
## screen and inside the previous doorway's screen rectangle (the hallway is the hub every
## door opens onto). Frustum culling alone draws the whole store behind the walls.
## The player's flashlight gets the same mask so its shadow pass skips hidden areas too.
## Characters and anything outside the level keep their own layers and are always drawn.

const FIRST_AREA_LAYER := 11            ## visual layers 11..16 (the viewmodel uses 20)
const AREAS := [&"sales", &"hallway", &"storage", &"break_room", &"office", &"janitor"]
## Area boxes on the floor plan [x0, x1, z0, z1] (docs/ARCHITECTURE.md §7, walls included).
const AREA_BOUNDS := {
	&"sales": [-20.4, 20.4, -6.1, 17.5],
	&"hallway": [-20.4, 20.4, -9.1, -5.9],
	&"storage": [-20.4, 2.1, -16.4, -8.9],
	&"break_room": [1.9, 10.1, -16.4, -8.9],
	&"office": [9.9, 16.1, -16.4, -8.9],
	&"janitor": [15.9, 20.4, -16.4, -8.9],
}
## Doorways [area_a, area_b, x0, x1, z, height] (all in walls along X).
const PORTALS := [
	[&"sales", &"hallway", 6.0, 8.4, -6.0, 2.4],
	[&"hallway", &"storage", -6.0, -4.4, -9.0, 2.2],
	[&"hallway", &"break_room", 5.0, 6.2, -9.0, 2.2],
	[&"hallway", &"office", 12.0, 13.2, -9.0, 2.2],
	[&"hallway", &"janitor", 17.5, 18.7, -9.0, 2.2],
]
## Standing this close to a doorway's plane (and within its width) sees through it whatever
## the angle.
const PORTAL_NEAR := 0.9
## Meshes that never need to cast the flashlight's shadow (floors, ceilings, lamps, signs).
const NO_SHADOW_PREFIXES := ["Floor", "Ceiling", "Fixture", "Sign", "Cable", "Details", "Pipes", "Vent", "Plenum"]
## Beyond these distances the store's depth fog (tools/level/store_environment.gd, fully opaque
## at 26 m) has swallowed a mesh, so it is not drawn at all: small things (props, fixtures,
## decals) sooner, structure at the fog's end.
const SMALL_SIZE := 1.6
const SMALL_RANGE := 20.0
const LARGE_RANGE := 27.0

var area_mask := 0                      ## all area layer bits
var visible_mask := 0                   ## area bits visible last frame
var enabled := true

var _camera: Camera3D
var _flashlight: Light3D


func _ready() -> void:
	for i in AREAS.size():
		area_mask |= _area_bit(i)
	tag_meshes(get_parent())


## Puts every mesh under `root` on the layers of the areas its bounds touch, and every light
## on the layers of the areas its range reaches (lights outside the visible areas are culled
## too, which keeps the view under the renderer's light limit).
func tag_meshes(root: Node) -> void:
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		var instance := node as GeometryInstance3D
		var bits := area_bits_for(instance.get_aabb(), instance.global_transform)
		if bits != 0:
			instance.layers = bits
		var longest := (instance.global_transform.basis * instance.get_aabb().size).abs().max_axis_index()
		var size := (instance.global_transform.basis * instance.get_aabb().size).abs()[longest]
		instance.visibility_range_end = SMALL_RANGE if size < SMALL_SIZE else LARGE_RANGE
		var mesh_name := String(instance.name)
		for prefix: String in NO_SHADOW_PREFIXES:
			if mesh_name.begins_with(prefix):
				instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				break
	for node in root.find_children("*", "OmniLight3D", true, false):
		var light := node as OmniLight3D
		var reach := Vector3.ONE * light.omni_range
		var bits := area_bits_for(AABB(-reach, reach * 2.0), Transform3D(Basis.IDENTITY, light.global_position))
		if bits != 0:
			light.layers = bits


func area_bits_for(local_box: AABB, xform: Transform3D) -> int:
	var box := xform * local_box
	var bits := 0
	for i in AREAS.size():
		var b: Array = AREA_BOUNDS[AREAS[i]]
		if box.position.x <= b[1] and box.end.x >= b[0] and box.position.z <= b[3] and box.end.z >= b[2]:
			bits |= _area_bit(i)
	return bits


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != _camera:
		_camera = camera
		_flashlight = null
		if camera:
			for light in camera.find_children("*", "SpotLight3D", true, false):
				_flashlight = light as Light3D
	if camera == null:
		return
	var mask := compute_visible(camera) if enabled else area_mask
	if mask == visible_mask and (camera.cull_mask & area_mask) == mask:
		return
	visible_mask = mask
	camera.cull_mask = (camera.cull_mask & ~area_mask) | mask
	if _flashlight:
		_flashlight.light_cull_mask = (_flashlight.light_cull_mask & ~area_mask) | mask


## Area layer bits the camera can see: its area plus areas reachable through on-screen doorways.
func compute_visible(camera: Camera3D) -> int:
	var start := area_at(camera.global_position)
	if start < 0:
		return area_mask
	var screen := Rect2(Vector2.ZERO, camera.get_viewport().get_visible_rect().size)
	var bits := _area_bit(start)
	var queue: Array = [[start, screen]]
	var seen := {start: true}
	while not queue.is_empty():
		var item: Array = queue.pop_front()
		var from: int = item[0]
		var rect: Rect2 = item[1]
		for portal: Array in PORTALS:
			var a := AREAS.find(portal[0])
			var b := AREAS.find(portal[1])
			var to := b if a == from else (a if b == from else -1)
			if to < 0 or seen.has(to):
				continue
			var through := _portal_rect(camera, portal, screen)
			if not through.has_area():
				continue
			var clipped := rect.intersection(through)
			if not clipped.has_area():
				continue
			seen[to] = true
			bits |= _area_bit(to)
			queue.append([to, clipped])
	return bits


## The area (index) containing `point`; rooms win over the hallway they border. -1 outside.
func area_at(point: Vector3) -> int:
	var best := -1
	var best_size := INF
	for i in AREAS.size():
		var b: Array = AREA_BOUNDS[AREAS[i]]
		if point.x >= b[0] and point.x <= b[1] and point.z >= b[2] and point.z <= b[3]:
			var size: float = (b[1] - b[0]) * (b[3] - b[2])
			if size < best_size:
				best = i
				best_size = size
	return best


## Screen rectangle of a doorway, empty when it is off screen or behind the camera.
func _portal_rect(camera: Camera3D, portal: Array, screen: Rect2) -> Rect2:
	var x0: float = portal[2]
	var x1: float = portal[3]
	var z: float = portal[4]
	var height: float = portal[5]
	var eye := camera.global_position
	if absf(eye.z - z) < PORTAL_NEAR and eye.x > x0 - 0.5 and eye.x < x1 + 0.5:
		return screen
	var corners := [Vector3(x0, 0.0, z), Vector3(x1, 0.0, z), Vector3(x0, height, z), Vector3(x1, height, z)]
	var behind := 0
	var points := PackedVector2Array()
	for corner: Vector3 in corners:
		if camera.is_position_behind(corner):
			behind += 1
		else:
			points.append(camera.unproject_position(corner))
	if behind == corners.size():
		return Rect2()
	if behind > 0:
		return screen   # straddles the camera plane: be conservative
	var rect := Rect2(points[0], Vector2.ZERO)
	for p in points:
		rect = rect.expand(p)
	return rect.intersection(screen)


func _area_bit(index: int) -> int:
	return 1 << (FIRST_AREA_LAYER - 1 + index)
