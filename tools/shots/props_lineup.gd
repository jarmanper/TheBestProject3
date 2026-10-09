extends SceneTree
## Screenshots of every Task 3 prop under dim store lighting (dark green-black room, cool
## fluorescent pools, a weak flashlight from the camera). Each group is framed automatically.
##   godot --path . --rendering-driver opengl3 --resolution 960x540 -s res://tools/shots/props_lineup.gd -- --out=/abs/dir
## Optional: --group=<name> renders one group. Writes props_<group>.png.

const DIR := "res://assets/models/props/"

const GROUPS := {
	"hiding_big": ["locker", "box_pile_hide", "vending_machine", "baler", "pallet_boxes", "shopping_cart"],
	"furniture": ["break_table", "chair", "manager_desk", "office_chair", "safe", "sink", "trash_bin", "mop_bucket"],
	"floor_clutter": ["spill_decal", "wet_floor_sign", "trash_bag", "flattened_boxes", "messy_products",
			"newspaper_debris"],
	"boxes": ["cardboard_box_a", "cardboard_box_b", "cardboard_box_c", "pallet", "pickup_stock_box"],
	"small": ["pickup_price_gun", "crt_monitor", "intercom_mic", "walkie_talkie"],
	"wall": ["pickup_mop", "pickup_box_cutter", "pickup_keys", "clipboard", "breaker_sparks", "time_clock",
			"breaker_panel"],
	"doors_and_taken": ["locker", "breaker_panel", "pickup_mop", "pickup_box_cutter", "pickup_keys",
			"pickup_price_gun", "pickup_stock_box"],
}
## Suggested origin heights of the wall props (see the Task 3 report).
const MOUNT_HEIGHTS := {
	"pickup_mop": 1.35, "pickup_box_cutter": 1.25, "pickup_keys": 1.45, "clipboard": 1.35,
	"breaker_sparks": 1.5, "time_clock": 1.4, "breaker_panel": 1.5,
}
const WALL_Z := -1.5
const FOV := 50.0

var _out := "user://shots"
var _only := ""


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--group="):
			_only = arg.trim_prefix("--group=")
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	for group: String in GROUPS:
		if not _only.is_empty() and group != _only:
			continue
		var stage := _make_stage()
		root.add_child(stage)
		var bounds := _place_group(stage, group)
		var camera := Camera3D.new()
		camera.fov = FOV
		stage.add_child(camera)
		var centre := bounds.get_center()
		var half_v := tan(deg_to_rad(FOV * 0.5))
		var half_h := half_v * 16.0 / 9.0
		var distance := maxf(bounds.size.x * 0.5 / half_h, bounds.size.y * 0.5 / half_v) * 1.12 + bounds.size.z * 0.5
		camera.look_at_from_position(centre + Vector3(0.0, distance * 0.28, distance), centre)
		camera.current = true
		var flashlight := SpotLight3D.new()
		flashlight.light_color = Color("fff1d6")
		flashlight.light_energy = 0.7
		flashlight.spot_range = 14.0
		flashlight.spot_angle = 40.0
		camera.add_child(flashlight)
		for i in 12:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := _out.path_join("props_%s.png" % group)
		root.get_texture().get_image().save_png(path)
		print("saved ", path)
		stage.free()
	quit()


func _make_stage() -> Node3D:
	var stage := Node3D.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0c0f0e")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("5a6660")
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	stage.add_child(world_env)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color("444a48")
	floor_mat.roughness = 0.35
	plane.material = floor_mat
	floor_mesh.mesh = plane
	stage.add_child(floor_mesh)
	var wall := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(30, 4, 0.2)
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color("3a403c")
	box.material = wall_mat
	wall.mesh = box
	wall.position = Vector3(0, 2, WALL_Z - 0.1)
	stage.add_child(wall)
	for x in [-4.5, -1.5, 1.5, 4.5]:
		var lamp := OmniLight3D.new()
		lamp.light_color = Color("d8e2d4")
		lamp.light_energy = 1.1
		lamp.omni_range = 6.0
		lamp.position = Vector3(x, 3.2, 0.6)
		stage.add_child(lamp)
	return stage


## Instances the group in a row facing +Z (floor props at z = 0, wall props on the wall at their
## mount height) and returns the bounds of everything placed.
func _place_group(stage: Node3D, group: String) -> AABB:
	var names: Array = GROUPS[group]
	var on_wall := group == "wall"
	var nodes: Array[Node3D] = []
	var widths: Array[float] = []
	for prop: String in names:
		var node := (load(DIR + prop + ".glb") as PackedScene).instantiate() as Node3D
		nodes.append(node)
		widths.append(maxf(_bounds(node).size.x, 0.12))
	var gap := 0.25
	var total := -gap
	for w in widths:
		total += w + gap
	var x := -total * 0.5
	var bounds := AABB()
	for i in nodes.size():
		var node := nodes[i]
		var prop: String = names[i]
		stage.add_child(node)
		var mounted := MOUNT_HEIGHTS.has(prop) and (on_wall or group == "doors_and_taken")
		var z := WALL_Z if mounted and not on_wall else 0.0
		node.position = Vector3(x + widths[i] * 0.5, MOUNT_HEIGHTS[prop] if mounted else 0.0, z)
		if on_wall:
			node.position.z = WALL_Z
		if group == "doors_and_taken":
			var door := node.find_child("Door", true, false) as Node3D
			if door:
				door.rotation.y = deg_to_rad(-100.0)
			var tool := node.find_child("Tool", true, false) as Node3D
			if tool:
				tool.visible = false
		var placed := _bounds(node)
		placed.position += node.position
		bounds = placed if i == 0 else bounds.merge(placed)
		x += widths[i] + gap
	return bounds


func _bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		var b := _relative_transform(node, mi) * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _relative_transform(root_node: Node3D, node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root_node:
		xf = (current as Node3D).transform * xf
		current = current.get_parent()
	return xf
