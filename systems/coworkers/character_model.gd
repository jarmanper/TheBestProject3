class_name CharacterModel
extends RefCounted
## Loads a character .glb (or builds a placeholder when it is missing) and helps
## drive its AnimationPlayer. Shared by Coworker and Monster so a disguised
## monster looks exactly like the coworker it copies.

enum Placeholder { EMPLOYEE, MONSTER }

const LOOPING_ANIMS: Array[StringName] = [
	Catalog.ANIM_IDLE, Catalog.ANIM_WALK, Catalog.ANIM_RUN, Catalog.ANIM_WORK,
]
## Ground speed (m/s) of each body's walk/run clip: moving at exactly this speed
## with speed_scale 1 keeps the planted foot still. Measured by Task 1's generator
## (art_source/blender/characters/build_characters.py prints "ground speed" per
## clip on every rebuild); update these when the animations change.
const GROUND_SPEED := {
	&"employee": {&"walk": 2.14, &"run": 4.86},
	&"monster": {&"walk": 1.14, &"run": 3.98},
	&"manager": {&"walk": 1.44},
}
const IDLE_BELOW := 0.15                 ## m/s; slower than this plays idle
const SKIN_COLOR := Color("c99a7a")
const MONSTER_SKIN := Color("b9a7a3")   ## pale, desaturated greyish pink
const CLAW_COLOR := Color("1c1a1a")

static var _warned := {}


## The model at `path`, or a placeholder of `kind` when the file is missing.
## `badge` is printed on the placeholder's chest (the real models paint it).
static func instantiate(path: String, kind: Placeholder, badge := "") -> Node3D:
	var scene := Catalog.load_scene_or_null(path)
	if scene != null:
		var model := scene.instantiate() as Node3D
		if model != null:
			model.name = "Model"
			setup_loops(find_animation_player(model))
			return model
	if not path.is_empty() and not _warned.has(path):
		_warned[path] = true
		push_warning("Missing character model %s, using a placeholder" % path)
	return build_monster_placeholder() if kind == Placeholder.MONSTER else build_employee_placeholder(badge)


static func find_animation_player(root: Node) -> AnimationPlayer:
	if root == null:
		return null
	var found := root.find_children("*", "AnimationPlayer", true, false)
	return found[0] as AnimationPlayer if not found.is_empty() else null


static func find_skeleton(root: Node) -> Skeleton3D:
	if root == null:
		return null
	var found := root.find_children("*", "Skeleton3D", true, false)
	return found[0] as Skeleton3D if not found.is_empty() else null


## idle/walk/run/work loop; reveal/attack play once.
static func setup_loops(player: AnimationPlayer) -> void:
	if player == null:
		return
	for anim_name in LOOPING_ANIMS:
		if player.has_animation(anim_name):
			player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR


## Plays `anim_name` if the model has it (no-op for placeholders).
static func play(player: AnimationPlayer, anim_name: StringName, speed := 1.0, blend := 0.2) -> void:
	if player == null or not player.has_animation(anim_name):
		return
	if player.current_animation != anim_name or not player.is_playing():
		player.play(anim_name, blend)
	player.speed_scale = speed


## Which clip a `body` (a GROUND_SPEED key) moving at `speed` m/s plays, and the
## speed_scale that keeps its feet planted: [anim_name, speed_scale].
## Runs once the speed is past halfway between the walk and run ground speeds.
static func locomotion(body: StringName, speed: float) -> Array:
	if speed < IDLE_BELOW:
		return [Catalog.ANIM_IDLE, 1.0]
	var speeds: Dictionary = GROUND_SPEED[body]
	var walk: float = speeds[&"walk"]
	var run: float = speeds.get(&"run", 0.0)
	if run > 0.0 and speed > (walk + run) * 0.5:
		return [Catalog.ANIM_RUN, speed / run]
	return [Catalog.ANIM_WALK, speed / walk]


## Plays idle/walk/run for `body` moving at `speed` (see locomotion()).
static func play_locomotion(player: AnimationPlayer, body: StringName, speed: float) -> void:
	var choice := locomotion(body, speed)
	play(player, choice[0], choice[1])


# --- Placeholders ------------------------------------------------------------

## Orange-uniform capsule with a head (node "Head"), cap and name badge.
static func build_employee_placeholder(badge := "") -> Node3D:
	var root := Node3D.new()
	root.name = "Placeholder"
	_add_mesh(root, _capsule(0.28, 1.45), Vector3(0, 0.75, 0), Catalog.COLOR_ORANGE)
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.58, 0)
	root.add_child(head)
	_add_mesh(head, _sphere(0.16), Vector3.ZERO, SKIN_COLOR)
	var cap := CylinderMesh.new()
	cap.top_radius = 0.17
	cap.bottom_radius = 0.17
	cap.height = 0.08
	_add_mesh(head, cap, Vector3(0, 0.12, 0), Catalog.COLOR_ORANGE.darkened(0.15))
	var brim := BoxMesh.new()
	brim.size = Vector3(0.22, 0.03, 0.14)
	_add_mesh(head, brim, Vector3(0, 0.09, 0.2), Catalog.COLOR_ORANGE.darkened(0.15))
	var boots := BoxMesh.new()
	boots.size = Vector3(0.42, 0.12, 0.3)
	_add_mesh(root, boots, Vector3(0, 0.06, 0.02), Color("141414"))
	if not badge.is_empty():
		var label := Label3D.new()
		label.text = badge
		label.font_size = 24
		label.pixel_size = 0.004
		label.outline_size = 0
		label.modulate = Catalog.COLOR_CHARCOAL
		label.position = Vector3(0.1, 1.2, 0.285)
		label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		root.add_child(label)
	return root


## Tall, thin pale figure with long arms, ears and a torn orange shirt.
static func build_monster_placeholder() -> Node3D:
	var root := Node3D.new()
	root.name = "Placeholder"
	_add_mesh(root, _capsule(0.26, 2.1), Vector3(0, 1.1, 0), MONSTER_SKIN)
	var shirt := CylinderMesh.new()
	shirt.top_radius = 0.3
	shirt.bottom_radius = 0.33
	shirt.height = 0.6
	_add_mesh(root, shirt, Vector3(0, 1.55, 0), Catalog.COLOR_ORANGE.darkened(0.25))
	for side in [-1.0, 1.0]:
		_add_mesh(root, _capsule(0.06, 1.35), Vector3(0.36 * side, 1.25, 0.05), MONSTER_SKIN)
		var claw := BoxMesh.new()
		claw.size = Vector3(0.1, 0.22, 0.06)
		_add_mesh(root, claw, Vector3(0.36 * side, 0.5, 0.08), CLAW_COLOR)
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 2.35, 0.05)
	root.add_child(head)
	_add_mesh(head, _sphere(0.2), Vector3.ZERO, MONSTER_SKIN)
	for side in [-1.0, 1.0]:
		var ear := BoxMesh.new()
		ear.size = Vector3(0.07, 0.45, 0.03)
		var ear_mesh := _add_mesh(head, ear, Vector3(0.1 * side, 0.36, 0), MONSTER_SKIN)
		ear_mesh.rotation.z = -0.2 * side
	var grin := BoxMesh.new()
	grin.size = Vector3(0.24, 0.04, 0.02)
	_add_mesh(head, grin, Vector3(0, -0.06, 0.19), CLAW_COLOR)
	return root


static func _capsule(radius: float, height: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 4
	return mesh


static func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 5
	return mesh


static func _add_mesh(parent: Node3D, mesh: Mesh, at: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	instance.material_override = material
	parent.add_child(instance)
	return instance
