extends SceneTree
## Generates res://levels/greybox/greybox.tscn from the docs/ARCHITECTURE.md §7 layout:
## world-layer boxes (walls with door openings, shelves, counters, coolers, partitions), all
## 14 StoreZones, spawn/patrol markers, stub TaskStations / ToolPickups / HidingSpots, store
## lights, intercom speakers, a dark environment and a baked navmesh (radius 0.4 m, height 1.8 m).
## Re-run after changing the layout:
##   godot --headless --path . -s res://levels/greybox/build_greybox.gd

const OUT_SCENE := "res://levels/greybox/greybox.tscn"
const OUT_NAVMESH := "res://levels/greybox/greybox_navmesh.res"
const ROOT_SCRIPT := "res://levels/greybox/greybox.gd"
const FONT_PATH := "res://assets/fonts/VT323-Regular.ttf"

const NAV_CELL_SIZE := 0.1
const NAV_CELL_HEIGHT := 0.1     ## agent height 1.8 = 18 cells, max climb 0.2 = 2; mesh sits ~0.2 m above the floor
const SALES_CEILING := 4.0
const BACK_CEILING := 3.0
const WALL := 0.3
const SHELF_ROWS := [-16.0, -12.0, -8.0, -4.0, 0.0]
const COUNTER_XS := [-12.0, -7.0, -2.0]
const BOARD_TOPS := [0.15, 0.6175, 1.0675, 1.5175, 1.9675]

const LIGHT_COOL := Color(0.86, 0.9, 0.8)
const LIGHT_WARM := Color(0.95, 0.88, 0.72)
const LIGHT_RED := Color(0.85, 0.2, 0.16)

## The 14 StoreZones (docs/ARCHITECTURE.md §7): [zone_id, x0, x1, z0, z1, ceiling height].
## Single source of truth: the final store (tools/build_store_level.gd) reads this table too.
const ZONE_BOUNDS := [
	[&"aisle_1", -15.4, -12.6, -3.0, 7.0, SALES_CEILING],
	[&"aisle_2", -11.4, -8.6, -3.0, 7.0, SALES_CEILING],
	[&"aisle_3", -7.4, -4.6, -3.0, 7.0, SALES_CEILING],
	[&"aisle_4", -3.4, -0.6, -3.0, 7.0, SALES_CEILING],
	[&"dairy", -20.0, 2.0, -6.0, -3.0, SALES_CEILING],
	[&"frozen", -20.0, -16.6, -3.0, 7.0, SALES_CEILING],
	[&"produce", 2.0, 20.0, -6.0, 9.0, SALES_CEILING],
	[&"checkout", -20.0, 6.0, 7.0, 16.0, SALES_CEILING],
	[&"service_desk", 6.0, 20.0, 9.0, 16.0, SALES_CEILING],
	[&"hallway", -20.0, 20.0, -9.0, -6.0, BACK_CEILING],
	[&"storage", -20.0, 2.0, -16.0, -9.0, BACK_CEILING],
	[&"break_room", 2.0, 10.0, -16.0, -9.0, BACK_CEILING],
	[&"office", 10.0, 16.0, -16.0, -9.0, BACK_CEILING],
	[&"janitor", 16.0, 20.0, -16.0, -9.0, BACK_CEILING],
]

const PALETTES := {
	&"cereal": [Color("b8442f"), Color("d1a03a"), Color("c7682c"), Color("3f5e95"), Color("e0d2a0")],
	&"snacks": [Color("d06a2a"), Color("c43d32"), Color("e2b33c"), Color("3c6aa8"), Color("6a9a3c")],
	&"drinks": [Color("2f6fb4"), Color("c9d2d6"), Color("3a8f4a"), Color("b33a32"), Color("e0e0da")],
	&"cans": [Color("9a9d96"), Color("b03a2e"), Color("c7a04a"), Color("5a7a3a"), Color("d8d3a8")],
	&"frozen": [Color("b7c9d8"), Color("4a72b0"), Color("d8d8d0"), Color("b03a2e")],
	&"dairy": [Color("e6e6dc"), Color("d8dce0"), Color("4a72b0"), Color("c8c0a0")],
	&"boxes": [Color("8a6a45"), Color("7b5d3c"), Color("9a7a52"), Color("6f5435"), Color("626D58")],
	&"produce": [Color("5d8c3a"), Color("a83a2a"), Color("d0a63a"), Color("c26a2a"), Color("7aa04a")],
}

var level: Node3D
var geometry: Node3D
var decor: Node3D
var _materials := {}
var _box_meshes := {}
var _box_shapes := {}
var _names := {}
var _seed := 100
var _font: Font
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_build.call_deferred()


func _build() -> void:
	await process_frame
	_rng.seed = 7
	_font = load(FONT_PATH)

	level = Node3D.new()
	level.name = "Greybox"
	level.set_script(load(ROOT_SCRIPT))

	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion3D"
	region.navigation_mesh = _make_navmesh()
	level.add_child(region)
	geometry = _group(region, "Geometry")
	decor = _group(level, "Decor")

	_build_shell()
	_build_sales_floor()
	_build_back_of_house()
	_build_signs()
	_build_zones()
	_build_markers()
	_build_stations()
	_build_tools()
	_build_hiding_spots()
	_build_lights()
	_build_intercom()
	_build_environment()

	root.add_child(level)
	await process_frame
	region.bake_navigation_mesh(false)
	var navmesh := region.navigation_mesh
	print("navmesh polygons: %d, vertices: %d" % [navmesh.get_polygon_count(), navmesh.vertices.size()])
	var err := ResourceSaver.save(navmesh, OUT_NAVMESH, ResourceSaver.FLAG_COMPRESS)
	assert(err == OK)
	navmesh.take_over_path(OUT_NAVMESH)

	# greybox.gd filled the product runs in _ready; they are regenerated at load, do not save them.
	for run in level.find_children("ProductRun*", "MultiMeshInstance3D", true, false):
		(run as MultiMeshInstance3D).multimesh = null
	_own(level, level)
	var packed := PackedScene.new()
	err = packed.pack(level)
	assert(err == OK)
	err = ResourceSaver.save(packed, OUT_SCENE)
	print("saved %s (%s)" % [OUT_SCENE, error_string(err)])
	quit(0 if err == OK else 1)


# --- Shell: floors, ceilings, exterior and interior walls --------------------------

func _build_shell() -> void:
	var xs := [-20.0, -12.0, -4.0, 4.0, 12.0, 20.0]
	var back_zs := [-16.0, -11.0, -6.0]
	var sales_zs := [-6.0, -1.0, 4.0, 10.0, 16.0]
	for i in xs.size() - 1:
		for j in back_zs.size() - 1:
			_floor_cell(xs[i], xs[i + 1], back_zs[j], back_zs[j + 1], &"floor_concrete", BACK_CEILING)
		for j in sales_zs.size() - 1:
			_floor_cell(xs[i], xs[i + 1], sales_zs[j], sales_zs[j + 1], &"floor_tile", SALES_CEILING)

	var half := WALL * 0.5
	# Exterior walls sit just outside the footprint.
	_wall_x("FrontWall", 16.0 + half, -20.0 - WALL, 20.0 + WALL, SALES_CEILING, [[-2.0, 2.0]], 2.6)
	_wall_x("BackWall", -16.0 - half, -20.0 - WALL, 20.0 + WALL, BACK_CEILING)
	_wall_z("WestWallSales", -20.0 - half, -6.0, 16.0, SALES_CEILING)
	_wall_z("WestWallBack", -20.0 - half, -16.0, -6.0, BACK_CEILING)
	_wall_z("EastWallSales", 20.0 + half, -6.0, 16.0, SALES_CEILING)
	_wall_z("EastWallBack", 20.0 + half, -16.0, -6.0, BACK_CEILING)
	# Sales floor / back of house divider with the employees-only doorway.
	_wall_x("DividerWall", -6.0, -20.0, 20.0, SALES_CEILING, [[6.0, 8.4]], 2.6)
	# Hallway wall with the four room doors.
	_wall_x("HallwayWall", -9.0, -20.0, 20.0, BACK_CEILING,
		[[-6.0, -4.4], [5.0, 6.2], [12.0, 13.2], [17.5, 18.7]], 2.3)
	for x in [2.0, 10.0, 16.0]:
		_wall_z("Partition_%d" % int(x), x, -16.0, -9.0 - half, BACK_CEILING)

	# Locked glass entrance doors (black night outside) and front windows.
	_solid("EntranceGlass", Vector3(0, 1.3, 16.0 + half), Vector3(4.0, 2.6, 0.08), &"glass")
	_visual("EntranceMullion", Vector3(0, 1.3, 16.0 + half), Vector3(0.08, 2.6, 0.12), &"metal_dark")
	_visual("EntrancePushBar", Vector3(0, 1.05, 16.0), Vector3(3.6, 0.05, 0.05), &"metal")
	for x in [-11.0, 11.0]:
		_visual("Window", Vector3(x, 1.8, 15.99), Vector3(14.0, 2.0, 0.02), &"glass", decor, false)
	# Emergency exit door in the west wall of the storage room.
	_visual("EmergencyDoor", Vector3(-19.97, 1.05, -13.0), Vector3(0.06, 2.1, 1.1), &"door_red")
	_visual("EmergencyDoorBar", Vector3(-19.9, 1.0, -13.0), Vector3(0.06, 0.06, 0.9), &"metal")


func _floor_cell(x0: float, x1: float, z0: float, z1: float, material: StringName, ceiling: float) -> void:
	var center := Vector3((x0 + x1) * 0.5, 0.0, (z0 + z1) * 0.5)
	var size := Vector3(x1 - x0, 0.2, z1 - z0)
	_solid("Floor", center + Vector3(0, -0.1, 0), size, material)
	var ceiling_node := _visual("Ceiling", center + Vector3(0, ceiling + 0.05, 0), Vector3(size.x, 0.1, size.z), &"ceiling", decor, false)
	ceiling_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Wall along X at `z` from x0 to x1 with door openings [[a, b], ...]; a lintel above each door.
func _wall_x(base: String, z: float, x0: float, x1: float, height: float, openings: Array = [], door_height := 2.4) -> void:
	var x := x0
	for cut: Array in openings:
		if cut[0] > x:
			_solid(base, Vector3((x + cut[0]) * 0.5, height * 0.5, z), Vector3(cut[0] - x, height, WALL), &"wall")
		_solid(base + "Lintel", Vector3((cut[0] + cut[1]) * 0.5, (door_height + height) * 0.5, z),
			Vector3(cut[1] - cut[0], height - door_height, WALL), &"wall")
		x = cut[1]
	if x1 > x:
		_solid(base, Vector3((x + x1) * 0.5, height * 0.5, z), Vector3(x1 - x, height, WALL), &"wall")


func _wall_z(base: String, x: float, z0: float, z1: float, height: float) -> void:
	_solid(base, Vector3(x, height * 0.5, (z0 + z1) * 0.5), Vector3(WALL, height, z1 - z0), &"wall")


# --- Sales floor --------------------------------------------------------------------

func _build_sales_floor() -> void:
	# Five gondola rows, 1.2 m deep x 10 m long (z -3..7), 2.2 m tall, five shelf levels.
	# Face categories: [west face, east face].
	var faces := {
		-16.0: [&"frozen", &"cereal"], -12.0: [&"cereal", &"snacks"], -8.0: [&"snacks", &"drinks"],
		-4.0: [&"drinks", &""], 0.0: [&"cans", &"cans"],
	}
	for cx: float in SHELF_ROWS:
		_gondola(cx, faces[cx])
	# Aisle 4 left side (row x = -4, east face): SNACKS / DRINKS / CEREAL like references 1/2.
	_product_run("ProductRun", Vector3(-3.97, 0, 3.75), 0.0, 3.2, 0.55, BOARD_TOPS, &"snacks")
	_product_run("ProductRun", Vector3(-3.97, 0, 0.35), 0.0, 3.3, 0.55, BOARD_TOPS, &"drinks")
	_product_run("ProductRun", Vector3(-3.97, 0, -2.95), 0.0, 3.2, 0.55, BOARD_TOPS, &"cereal")

	# Dairy: glass-door wall coolers along the back wall z = -6, lit inside.
	var x := -19.0
	while x < 2.0 - 0.01:
		_cooler("Cooler", Vector3(x + 1.5, 0, -5.45), 3.0, true)
		x += 3.0
	# Frozen: wall freezers along x = -20.
	for z0 in [-3.0, 0.4, 3.8]:
		_cooler("Freezer", Vector3(-19.45, 0, z0 + 1.6), 3.2, false)

	# Checkout: three counters 0.9 m wide x 3 m long along Z (z 10..13), register at z = 13.
	for i in COUNTER_XS.size():
		var cx: float = COUNTER_XS[i]
		_solid("CheckoutCounter", Vector3(cx, 0.45, 11.5), Vector3(0.9, 0.9, 3.0), &"counter")
		_visual("CounterTop", Vector3(cx, 0.92, 11.5), Vector3(0.95, 0.04, 3.05), &"counter_top")
		_visual("Conveyor", Vector3(cx, 0.945, 11.0), Vector3(0.6, 0.012, 1.9), &"black")
		_solid("Register", Vector3(cx, 1.115, 12.7), Vector3(0.45, 0.35, 0.4), &"metal_dark")
		_visual("RegisterScreen", Vector3(cx, 1.36, 12.52), Vector3(0.3, 0.16, 0.03), &"screen_green", decor, false)
		_visual("LanePole", Vector3(cx + 0.4, 1.6, 13.0), Vector3(0.05, 1.3, 0.05), &"metal")
		_sign("LaneSign", str(i + 1), Vector3(cx + 0.4, 2.4, 13.0), Vector3.FORWARD, Vector2(0.4, 0.35), 64, true)

	# Customer service: L-shaped desk around x 9..15, z 12..14.5.
	_solid("ServiceDesk", Vector3(12.0, 0.525, 12.4), Vector3(6.0, 1.05, 0.8), &"counter")
	_solid("ServiceDeskSide", Vector3(14.6, 0.525, 13.65), Vector3(0.8, 1.05, 1.7), &"counter")
	_visual("ServiceDeskTop", Vector3(12.0, 1.07, 12.4), Vector3(6.05, 0.04, 0.85), &"counter_top")
	_visual("ServiceDeskSideTop", Vector3(14.6, 1.07, 13.65), Vector3(0.85, 0.04, 1.75), &"counter_top")

	# Produce: low tables in a grid, plus a pallet of boxes.
	for tx in [6.0, 10.0, 14.0, 18.0]:
		for tz in [-2.0, 2.0, 6.0]:
			if tx == 18.0 and tz == 6.0:
				_solid("Pallet", Vector3(18, 0.075, 6), Vector3(1.2, 0.15, 1.0), &"wood")
				_solid("PalletBoxes", Vector3(18, 0.75, 6), Vector3(1.0, 1.2, 0.8), &"cardboard")
				continue
			_solid("ProduceTable", Vector3(tx, 0.4, tz), Vector3(2.0, 0.8, 1.2), &"wood")
			_visual("ProduceTray", Vector3(tx, 0.84, tz), Vector3(2.1, 0.08, 1.3), &"wood_dark")
			_product_run("ProductRun", Vector3(tx - 1.0, 0.88, tz + 0.6), PI * 0.5, 2.0, 1.2, [0.0], &"produce",
				Vector3(1.0, 0.06, 0.15), Vector3(1.15, 0.15, 0.3), 0.0)


func _gondola(cx: float, categories: Array) -> void:
	var body := StaticBody3D.new()
	body.name = _unique("Gondola")
	body.collision_layer = Catalog.LAYER_WORLD
	body.collision_mask = 0
	body.position = Vector3(cx, 1.1, 2.0)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	shape.shape = _box_shape(Vector3(1.2, 2.2, 10.0))
	body.add_child(shape)
	geometry.add_child(body)
	_visual("ShelfBase", Vector3(cx, 0.075, 2.0), Vector3(1.2, 0.15, 10.0), &"shelf_dark")
	_visual("ShelfBack", Vector3(cx, 1.1, 2.0), Vector3(0.06, 2.2, 10.0), &"shelf")
	for top: float in BOARD_TOPS.slice(1):
		_visual("ShelfBoard", Vector3(cx, top - 0.0175, 2.0), Vector3(1.2, 0.035, 10.0), &"shelf")
	_visual("ShelfCap", Vector3(cx, 2.2, 2.0), Vector3(1.2, 0.04, 10.0), &"shelf_dark")
	for z in [-3.0, 2.0, 7.0]:
		_visual("ShelfUpright", Vector3(cx, 1.1, z), Vector3(1.22, 2.2, 0.05), &"shelf_dark")
	if categories[0] != &"":
		_product_run("ProductRun", Vector3(cx - 0.03, 0, 6.95), PI, 9.9, 0.55, BOARD_TOPS, categories[0])
	if categories[1] != &"":
		_product_run("ProductRun", Vector3(cx + 0.03, 0, -2.95), 0.0, 9.9, 0.55, BOARD_TOPS, categories[1])


## Wall cooler / freezer `length` long centred at `center`; dairy coolers face +Z, freezers +X.
func _cooler(base: String, center: Vector3, length: float, faces_z: bool) -> void:
	var height := 2.2 if faces_z else 2.0
	var size := Vector3(length, height, 0.8) if faces_z else Vector3(0.8, height, length)
	_solid(base, center + Vector3(0, height * 0.5, 0), size, &"cooler_frame")
	var front := Vector3(0, 0, 0.41) if faces_z else Vector3(0.41, 0, 0)
	var glass_size := Vector3(length - 0.1, height - 0.4, 0.02) if faces_z else Vector3(0.02, height - 0.4, length - 0.1)
	var glass := &"cooler_glass" if faces_z else &"freezer_glass"
	_visual(base + "Glass", center + front + Vector3(0, height * 0.5 + 0.05, 0), glass_size, glass, decor, false)
	var mullions := int(length / 0.75)
	for i in range(1, mullions):
		var offset := -length * 0.5 + i * length / mullions
		var at := center + front * 1.02 + (Vector3(offset, height * 0.5, 0) if faces_z else Vector3(0, height * 0.5, offset))
		_visual(base + "Mullion", at, Vector3(0.04, height - 0.3, 0.03) if faces_z else Vector3(0.03, height - 0.3, 0.04), &"metal_dark", decor, false)
	# Stock visible through the glass.
	var palette := &"dairy" if faces_z else &"frozen"
	var levels := [0.3, 0.75, 1.2, 1.65] if faces_z else [0.3, 0.8, 1.3]
	if faces_z:
		_product_run("ProductRun", center + Vector3(length * 0.5 - 0.05, 0, -0.35), -PI * 0.5, length - 0.1, 0.65, levels, palette)
	else:
		_product_run("ProductRun", center + Vector3(-0.35, 0, -length * 0.5 + 0.05), 0.0, length - 0.1, 0.65, levels, palette)


# --- Back of house --------------------------------------------------------------------

func _build_back_of_house() -> void:
	# Storage room: grey industrial shelving rows with boxes (reference image 3).
	_industrial_row(Vector3(-12.5, 0, -11.3), 8.0, true)
	_industrial_row(Vector3(-12.5, 0, -14.7), 8.0, true)
	_industrial_row(Vector3(-2.5, 0, -15.6), 7.0, true)
	_industrial_row(Vector3(0.9, 0, -12.5), 4.0, false)
	_solid("Cart", Vector3(-9.5, 0.5, -13.0), Vector3(0.6, 1.0, 1.0), &"metal")
	_solid("Cart", Vector3(-15.0, 0.5, -12.8), Vector3(0.6, 1.0, 1.0), &"metal")
	for i in 7:
		var at := Vector3(_rng.randf_range(-17.0, -3.0), 0.006, _rng.randf_range(-14.0, -12.0))
		var debris := _visual("Debris", at, Vector3(_rng.randf_range(0.2, 0.5), 0.01, _rng.randf_range(0.2, 0.4)), &"paper", decor, false)
		debris.rotation.y = _rng.randf_range(0.0, PI)

	# Break room: lockers (hiding spots), table, vending machine, time clock.
	_solid("BreakTable", Vector3(4.2, 0.375, -14.3), Vector3(1.6, 0.75, 0.8), &"wood")
	_solid("Chair", Vector3(4.2, 0.25, -13.55), Vector3(0.45, 0.5, 0.45), &"metal_dark")
	_solid("VendingMachine", Vector3(9.4, 0.95, -15.3), Vector3(1.0, 1.9, 0.8), &"metal_dark")
	_visual("VendingPanel", Vector3(9.4, 1.2, -14.89), Vector3(0.8, 1.2, 0.02), &"vending_panel", decor, false)
	_solid("TimeClock", Vector3(9.79, 1.4, -12.5), Vector3(0.12, 0.35, 0.28), &"metal")

	# Manager's office: desk, CRT monitor, intercom mic, filing cabinet.
	_solid("ManagerDesk", Vector3(13.0, 0.375, -13.8), Vector3(1.6, 0.75, 0.75), &"wood_dark")
	_visual("CrtMonitor", Vector3(13.0, 0.97, -13.85), Vector3(0.45, 0.4, 0.4), &"metal")
	_visual("CrtScreen", Vector3(13.0, 0.98, -14.06), Vector3(0.34, 0.26, 0.02), &"screen_green", decor, false)
	_visual("IntercomMic", Vector3(13.55, 0.83, -13.7), Vector3(0.12, 0.16, 0.12), &"black")
	_solid("FilingCabinet", Vector3(15.5, 0.65, -15.6), Vector3(0.5, 1.3, 0.6), &"locker")

	# Janitor closet: sink and bucket.
	_solid("Sink", Vector3(19.5, 0.45, -15.4), Vector3(0.8, 0.9, 0.6), &"metal")
	_solid("MopBucket", Vector3(17.2, 0.2, -15.3), Vector3(0.45, 0.4, 0.45), &"yellow")


## Grey metal shelving unit row with boxes, 0.6 m deep, 2.4 m tall. along_x: runs along X.
func _industrial_row(center: Vector3, length: float, along_x: bool) -> void:
	var size := Vector3(length, 2.4, 0.6) if along_x else Vector3(0.6, 2.4, length)
	var body := StaticBody3D.new()
	body.name = _unique("IndustrialShelf")
	body.collision_layer = Catalog.LAYER_WORLD
	body.position = center + Vector3(0, 1.2, 0)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	shape.shape = _box_shape(size)
	body.add_child(shape)
	geometry.add_child(body)
	for y in [0.1, 0.8, 1.5, 2.2]:
		_visual("RackBoard", center + Vector3(0, y, 0), Vector3(size.x, 0.04, size.z), &"metal")
	var posts := int(length / 2.0) + 1
	for i in posts:
		var offset := -length * 0.5 + i * length / (posts - 1)
		for side in [-0.28, 0.28]:
			var at := center + (Vector3(offset, 1.2, side) if along_x else Vector3(side, 1.2, offset))
			_visual("RackPost", at, Vector3(0.05, 2.4, 0.05), &"metal_dark")
	var levels := [0.12, 0.82, 1.52]
	# Rows along X show their boxes toward +Z; the row along Z faces -X (the storage interior).
	if along_x:
		_product_run("ProductRun", center + Vector3(length * 0.5 - 0.05, 0, -0.3), -PI * 0.5, length - 0.1, 0.6, levels, &"boxes",
			Vector3(0.35, 0.25, 0.3), Vector3(0.55, 0.55, 0.7), 0.25)
	else:
		_product_run("ProductRun", center + Vector3(0.3, 0, length * 0.5 - 0.05), PI, length - 0.1, 0.6, levels, &"boxes",
			Vector3(0.35, 0.25, 0.3), Vector3(0.55, 0.55, 0.7), 0.25)


# --- Signs ------------------------------------------------------------------------------

func _build_signs() -> void:
	var aisle_xs := [-14.0, -10.0, -6.0, -2.0]
	for i in aisle_xs.size():
		var at := Vector3(aisle_xs[i], 3.3, 2.0)
		_sign("AisleSign", "AISLE %d" % (i + 1), at, Vector3.BACK, Vector2(1.4, 0.55), 72, true)
		for dx in [-0.5, 0.5]:
			_visual("SignChain", at + Vector3(dx, 0.48, 0), Vector3(0.015, 0.42, 0.015), &"metal_dark", decor, false)
	_sign("DairySign", "DAIRY", Vector3(-2.0, 2.8, -5.4), Vector3.BACK, Vector2(2.4, 0.6), 110, false)
	_sign("FrozenSign", "FROZEN", Vector3(-18.9, 2.75, 2.0), Vector3.RIGHT, Vector2(1.8, 0.45), 64, false)
	_sign("ProduceSign", "PRODUCE", Vector3(11.0, 3.3, 1.5), Vector3.BACK, Vector2(2.0, 0.5), 72, true)
	_sign("ServiceSign", "CUSTOMER SERVICE", Vector3(12.0, 2.7, 12.4), Vector3.FORWARD, Vector2(3.2, 0.45), 60, true)
	_sign("EmployeesOnlySign", "EMPLOYEES ONLY", Vector3(7.2, 3.0, -5.82), Vector3.BACK, Vector2(2.4, 0.4), 52, false)
	_sign("ExitSign", "EXIT", Vector3(-19.82, 2.45, -13.0), Vector3.RIGHT, Vector2(0.7, 0.3), 64, false, &"exit_green", Color(0.75, 1.0, 0.8))
	# Shelf-top category placards (white with black text, references 1/2).
	_placard("CEREAL", Vector3(-12.6, 2.36, 4.0), Vector3.LEFT)
	_placard("SNACKS", Vector3(-8.6, 2.36, 4.0), Vector3.LEFT)
	_placard("DRINKS", Vector3(-4.6, 2.36, 4.0), Vector3.LEFT)
	_placard("SNACKS", Vector3(-3.4, 2.36, 5.4), Vector3.RIGHT)
	_placard("DRINKS", Vector3(-3.4, 2.36, 2.0), Vector3.RIGHT)
	_placard("CEREAL", Vector3(-3.4, 2.36, -1.4), Vector3.RIGHT)


## Dark board with cream pixel text facing `facing` (and the opposite side when double_sided).
func _sign(base: String, text: String, center: Vector3, facing: Vector3, board: Vector2, font_size: int,
		double_sided: bool, board_material := &"sign_board", text_color := Catalog.COLOR_CREAM) -> void:
	var along_z := absf(facing.z) > 0.5
	var size := Vector3(board.x, board.y, 0.04) if along_z else Vector3(0.04, board.y, board.x)
	_visual(base, center, size, board_material, decor, false)
	_label(text, center + facing * 0.025, facing, font_size, text_color)
	if double_sided:
		_label(text, center - facing * 0.025, -facing, font_size, text_color)


func _placard(text: String, center: Vector3, facing: Vector3) -> void:
	_visual("Placard", center, Vector3(0.03, 0.24, 0.95), &"placard", decor, false)
	_label(text, center + facing * 0.02, facing, 52, Color(0.08, 0.08, 0.08))


func _label(text: String, position: Vector3, facing: Vector3, font_size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.name = _unique("Text")
	label.text = text
	label.font = _font
	label.font_size = font_size
	label.pixel_size = 0.004
	label.modulate = color
	label.outline_size = 0
	label.double_sided = false
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	label.position = position
	label.rotation.y = atan2(facing.x, facing.z)
	decor.add_child(label)
	return label


# --- Gameplay nodes ----------------------------------------------------------------------

func _build_zones() -> void:
	var holder := _group(level, "Zones")
	for z: Array in ZONE_BOUNDS:
		var zone := StoreZone.new()
		zone.name = "Zone_%s" % z[0]
		zone.zone_id = z[0]
		zone.display_name = Catalog.zone_name(z[0])
		var shape := CollisionShape3D.new()
		shape.name = "Box"
		var box := BoxShape3D.new()
		box.size = Vector3(z[2] - z[1], z[5], z[4] - z[3])
		shape.shape = box
		shape.position = Vector3((z[1] + z[2]) * 0.5, z[5] * 0.5, (z[3] + z[4]) * 0.5)
		zone.add_child(shape)
		holder.add_child(zone)


func _build_markers() -> void:
	var holder := _group(level, "Markers")
	_marker(holder, "PlayerSpawn", &"player_spawn", Vector3(6.0, 0, -12.5), PI)
	_marker(holder, "CoworkerSpawn1", &"coworker_spawn", Vector3(3.6, 0, -11.0), PI)
	_marker(holder, "CoworkerSpawn2", &"coworker_spawn", Vector3(8.4, 0, -11.0), PI)
	_marker(holder, "CoworkerSpawn3", &"coworker_spawn", Vector3(-1.0, 0, -7.5), -PI * 0.5)
	_marker(holder, "MonsterSpawn", &"monster_spawn", Vector3(-18.0, 0, -15.0), -PI * 0.5)
	_marker(holder, "ManagerSpot", &"manager_spot", Vector3(13.0, 0, -15.0), PI)
	var patrol := [
		Vector3(-14, 0, -1), Vector3(-14, 0, 5), Vector3(-10, 0, 2), Vector3(-6, 0, -1), Vector3(-6, 0, 5),
		Vector3(-2, 0, 2), Vector3(-10, 0, -4.5), Vector3(-17, 0, -4.5), Vector3(-18.2, 0, 2),
		Vector3(6, 0, -3.5), Vector3(14, 0, -3.5), Vector3(12.5, 0, 7.5), Vector3(-14.5, 0, 8.5),
		Vector3(-4.5, 0, 14.8), Vector3(17, 0, 11.5), Vector3(-15, 0, -7.5), Vector3(0, 0, -7.5),
		Vector3(15, 0, -7.5), Vector3(-14, 0, -13), Vector3(-4, 0, -14), Vector3(7.5, 0, -14.6),
		Vector3(18, 0, -12.5), Vector3(14.8, 0, -10.5),
	]
	for i in patrol.size():
		_marker(holder, "Patrol%02d" % (i + 1), &"patrol_point", patrol[i], 0.0)


func _marker(parent: Node3D, marker_name: String, group: StringName, position: Vector3, yaw: float) -> Marker3D:
	var marker := Marker3D.new()
	marker.name = marker_name
	marker.position = position
	marker.rotation.y = yaw
	marker.add_to_group(group, true)
	parent.add_child(marker)
	return marker


## The 13 task stations of the night (stub TaskStation nodes; Tasks picks from them).
func _build_stations() -> void:
	var holder := _group(level, "Stations")
	var defs := [
		{"id": "SpillAisle3", "kind": &"mop_spill", "zone": &"aisle_3", "title": "Mop the spill in Aisle 3", "tool": &"mop", "hold": 4.0,
			"prompt": "Mop spill", "line": "Somebody dropped a jug in aisle three. Grab the mop.",
			"area": [Vector3(-6, 0.1, 3.0), Vector3(1.2, 0.2, 1.2)], "work": Vector3(-6, 0, 4.2), "visual": &"spill"},
		{"id": "SpillProduce", "kind": &"mop_spill", "zone": &"produce", "title": "Mop the spill in Produce", "tool": &"mop", "hold": 4.0,
			"prompt": "Mop spill", "line": "There's a mess over in produce. Mop it before somebody slips.",
			"area": [Vector3(8, 0.1, 0.0), Vector3(1.2, 0.2, 1.2)], "work": Vector3(8, 0, 1.0), "visual": &"spill"},
		{"id": "RestockAisle2", "kind": &"restock", "zone": &"aisle_2", "title": "Restock Aisle 2", "tool": &"stock_box", "hold": 4.0,
			"prompt": "Restock shelf", "line": "Aisle two is picked clean. Bring a stock box from the back.",
			"area": [Vector3(-8.72, 1.0, 4.5), Vector3(0.25, 1.4, 1.4)], "work": Vector3(-9.6, 0, 4.5), "visual": &"restock"},
		{"id": "RestockAisle4", "kind": &"restock", "zone": &"aisle_4", "title": "Restock Aisle 4", "tool": &"stock_box", "hold": 4.0,
			"prompt": "Restock shelf", "line": "Need aisle four restocked before morning. Stock boxes are in the hallway.",
			"area": [Vector3(-0.72, 1.0, -1.0), Vector3(0.25, 1.4, 1.4)], "work": Vector3(-1.6, 0, -1.0), "visual": &"restock"},
		{"id": "FaceAisle1", "kind": &"face_shelf", "zone": &"aisle_1", "title": "Face the shelves in Aisle 1", "tool": &"", "hold": 3.0,
			"prompt": "Face shelves", "line": "Aisle one looks like a tornado hit it. Face those shelves.",
			"area": [Vector3(-12.72, 1.0, 1.5), Vector3(0.25, 1.4, 1.4)], "work": Vector3(-13.6, 0, 1.5), "visual": &"messy"},
		{"id": "Register1", "kind": &"count_register", "zone": &"checkout", "title": "Count register 1", "tool": &"", "hold": 4.0,
			"prompt": "Count register", "line": "Count down register one for me.",
			"area": [Vector3(-12, 1.15, 12.7), Vector3(0.6, 0.5, 0.55)], "work": Vector3(-11.1, 0, 12.6), "visual": &"drawer"},
		{"id": "Register2", "kind": &"count_register", "zone": &"checkout", "title": "Count register 2", "tool": &"", "hold": 4.0,
			"prompt": "Count register", "line": "Register two is off again. Count it.",
			"area": [Vector3(-7, 1.15, 12.7), Vector3(0.6, 0.5, 0.55)], "work": Vector3(-6.1, 0, 12.6), "visual": &"drawer"},
		{"id": "PriceDairy", "kind": &"price_labels", "zone": &"dairy", "title": "Update price labels in Dairy", "tool": &"price_gun", "hold": 3.0,
			"prompt": "Update price labels", "line": "Milk prices changed. Take the price gun to dairy.",
			"area": [Vector3(-12, 1.2, -4.95), Vector3(1.4, 1.2, 0.25)], "work": Vector3(-12, 0, -4.1), "visual": &"labels"},
		{"id": "FreezerLog", "kind": &"freezer_log", "zone": &"frozen", "title": "Log the freezer temperature", "tool": &"", "hold": 3.0,
			"prompt": "Log temperature", "line": "Log the freezer temps in frozen foods.",
			"area": [Vector3(-18.95, 1.3, 2.0), Vector3(0.25, 0.6, 0.8)], "work": Vector3(-18.1, 0, 2.0), "visual": &"clipboard"},
		{"id": "BoxesStorage", "kind": &"break_down_boxes", "zone": &"storage", "title": "Break down boxes in Storage", "tool": &"box_cutter", "hold": 5.0,
			"prompt": "Break down boxes", "line": "The storage room is full of empty boxes. Box cutter's on the wall in there.",
			"area": [Vector3(-6.5, 0.4, -12.8), Vector3(1.2, 0.8, 1.2)], "work": Vector3(-6.5, 0, -11.8), "visual": &"boxes"},
		{"id": "TrashBreakRoom", "kind": &"empty_trash", "zone": &"break_room", "title": "Empty the break room trash", "tool": &"", "hold": 3.0,
			"prompt": "Empty trash", "line": "Break room trash is overflowing. Take it out.",
			"area": [Vector3(9.4, 0.5, -10.0), Vector3(0.65, 1.0, 0.65)], "work": Vector3(8.7, 0, -10.0), "visual": &"trash"},
		{"id": "Breaker", "kind": &"reset_breaker", "zone": &"hallway", "title": "Reset the breaker", "tool": &"keys", "hold": 3.0,
			"prompt": "Reset breaker", "line": "Lights are acting up. Get the keys and reset the breaker in the back hallway.",
			"area": [Vector3(0, 1.5, -8.7), Vector3(0.7, 0.9, 0.25)], "work": Vector3(0, 0, -7.9), "visual": &"sparks"},
		{"id": "Safe", "kind": &"lock_safe", "zone": &"service_desk", "title": "Lock the safe", "tool": &"keys", "hold": 4.0,
			"prompt": "Lock safe", "line": "Somebody left the safe open at customer service. Lock it up.",
			"area": [Vector3(10.2, 0.45, 15.4), Vector3(0.8, 0.9, 0.8)], "work": Vector3(10.2, 0, 14.6), "visual": &"safe"},
	]
	# Props the stations sit on (obstacles for the navmesh).
	_solid("BreakerPanel", Vector3(0, 1.5, -8.79), Vector3(0.6, 0.8, 0.12), &"metal")
	_solid("Safe", Vector3(10.2, 0.4, 15.4), Vector3(0.7, 0.8, 0.7), &"metal_dark")
	_solid("TrashCan", Vector3(9.4, 0.45, -10.0), Vector3(0.55, 0.9, 0.55), &"black")
	for def: Dictionary in defs:
		var station := TaskStation.new()
		station.name = "Station_%s" % def.id
		station.task_kind = def.kind
		station.zone = def.zone
		station.title = def.title
		station.required_tool = def.tool
		station.hold_time = def.hold
		station.prompt_text = def.prompt
		station.manager_line = def.line
		station.basic_task = true
		station.position = def.area[0]
		_area_shape(station, def.area[1])
		var work := Marker3D.new()
		work.name = "WorkPoint"
		work.position = def.work - station.position
		station.add_child(work)
		var active := Node3D.new()
		active.name = "ActiveVisual"
		active.visible = false
		station.add_child(active)
		_station_visual(active, def.visual, def.area[1])
		holder.add_child(station)


func _station_visual(parent: Node3D, kind: StringName, area: Vector3) -> void:
	var floor_y := -area.y * 0.5
	match kind:
		&"spill":
			_visual("Puddle", Vector3(0, floor_y + 0.006, 0), Vector3(1.1, 0.01, 0.85), &"puddle", parent, false)
			_visual("WetFloorSign", Vector3(0.75, floor_y + 0.3, 0), Vector3(0.3, 0.6, 0.22), &"yellow", parent)
		&"restock":
			_visual("StockBox", Vector3(-0.7, -0.82, 0.3), Vector3(0.5, 0.35, 0.4), &"cardboard", parent)
			_visual("StockBox", Vector3(-0.75, -0.84, -0.3), Vector3(0.45, 0.3, 0.4), &"cardboard", parent)
		&"messy":
			for i in 5:
				var item := _visual("FallenItem", Vector3(-0.5 - _rng.randf() * 0.6, -0.95, _rng.randf_range(-0.6, 0.6)),
					Vector3(0.18, 0.1, 0.25), &"products_red", parent)
				item.rotation.y = _rng.randf_range(0.0, PI)
		&"drawer":
			_visual("CashDrawer", Vector3(0.2, -0.17, 0), Vector3(0.3, 0.08, 0.35), &"metal", parent)
		&"labels":
			_visual("LabelRoll", Vector3(0, -1.15, 0.6), Vector3(0.12, 0.06, 0.12), &"placard", parent)
		&"clipboard":
			_visual("Clipboard", Vector3(-0.05, 0, 0), Vector3(0.02, 0.32, 0.24), &"wood", parent)
		&"boxes":
			_visual("FlatBoxes", Vector3(0, -0.25, 0), Vector3(1.0, 0.3, 0.8), &"cardboard", parent)
			_visual("OpenBox", Vector3(0.2, 0.05, 0.1), Vector3(0.5, 0.35, 0.45), &"cardboard", parent)
		&"trash":
			_visual("TrashBag", Vector3(0, 0.5, 0), Vector3(0.5, 0.35, 0.5), &"black", parent)
		&"sparks":
			for i in 4:
				_visual("Spark", Vector3(_rng.randf_range(-0.25, 0.25), _rng.randf_range(-0.3, 0.3), 0.1),
					Vector3(0.03, 0.03, 0.03), &"spark", parent, false)
		&"safe":
			_visual("SafeDoorOpen", Vector3(0.45, 0.0, -0.2), Vector3(0.05, 0.65, 0.55), &"metal", parent)


func _build_tools() -> void:
	var holder := _group(level, "Tools")
	_solid("StockPallet", Vector3(-9.5, 0.075, -6.6), Vector3(1.2, 0.15, 0.8), &"wood")
	_solid("StockStack", Vector3(-9.5, 0.55, -6.6), Vector3(0.9, 0.8, 0.7), &"cardboard")
	var defs := [
		[&"mop", Vector3(19.75, 0.9, -12.0), Vector3(0.35, 1.8, 0.5)],
		[&"price_gun", Vector3(12.0, 1.17, 12.45), Vector3(0.4, 0.2, 0.35)],
		[&"box_cutter", Vector3(-3.5, 1.2, -9.27), Vector3(0.4, 0.35, 0.2)],
		[&"stock_box", Vector3(-9.5, 0.95, -6.6), Vector3(1.0, 0.9, 0.85)],
		[&"keys", Vector3(15.78, 1.4, -11.5), Vector3(0.15, 0.35, 0.35)],
	]
	for def: Array in defs:
		var pickup := ToolPickup.new()
		pickup.name = "Pickup_%s" % def[0]
		pickup.tool_id = def[0]
		pickup.prompt_text = "Take %s" % Catalog.tool_name(def[0])
		pickup.position = def[1]
		_area_shape(pickup, def[2])
		var tool := Node3D.new()
		tool.name = "Tool"
		pickup.add_child(tool)
		var rack := Node3D.new()
		rack.name = "Rack"
		pickup.add_child(rack)
		match def[0]:
			&"mop":
				_visual("Handle", Vector3(0, 0.1, 0), Vector3(0.04, 1.5, 0.04), &"wood", tool)
				_visual("MopHead", Vector3(0, -0.72, 0), Vector3(0.12, 0.14, 0.35), &"paper", tool)
				_visual("Hook", Vector3(0.14, 0.6, 0), Vector3(0.04, 0.1, 0.35), &"metal_dark", rack)
			&"price_gun":
				_visual("Gun", Vector3(0, 0.0, 0), Vector3(0.09, 0.13, 0.22), &"orange", tool)
				_visual("Tray", Vector3(0, -0.085, 0), Vector3(0.36, 0.02, 0.3), &"metal_dark", rack)
			&"box_cutter":
				_visual("Cutter", Vector3(0, 0, 0), Vector3(0.16, 0.035, 0.04), &"yellow", tool)
				_visual("Board", Vector3(0, 0, 0.09), Vector3(0.4, 0.3, 0.02), &"wood_dark", rack)
			&"stock_box":
				_visual("TopBox", Vector3(0, 0.15, 0), Vector3(0.45, 0.3, 0.35), &"cardboard", tool)
			&"keys":
				_visual("Keys", Vector3(-0.02, -0.03, 0), Vector3(0.03, 0.09, 0.1), &"yellow", tool)
				_visual("KeyBoard", Vector3(0.05, 0, 0), Vector3(0.02, 0.3, 0.3), &"wood_dark", rack)
		holder.add_child(pickup)


func _build_hiding_spots() -> void:
	var holder := _group(level, "HidingSpots")
	# Break room lockers against the west partition, facing +X.
	for z in [-15.3, -14.75, -14.2]:
		_locker(holder, Vector3(2.42, 0, z), -PI * 0.5)
	# Hallway locker by the janitor closet, facing -X.
	_locker(holder, Vector3(19.7, 0, -7.0), PI * 0.5)
	# Crouch spots on the cashier side of each checkout counter and behind the service desk.
	for cx: float in COUNTER_XS:
		_hide_spot(holder, &"counter", Vector3(cx + 0.85, 0.45, 11.0), Vector3(0.8, 0.9, 0.9),
			Vector3(cx + 0.75, 0.6, 11.0), 0.0, Vector3(cx + 1.5, 0, 11.6))
	_hide_spot(holder, &"counter", Vector3(11.0, 0.45, 13.25), Vector3(0.8, 0.9, 0.8),
		Vector3(11.0, 0.6, 13.15), -PI * 0.5, Vector3(11.0, 0, 14.1))
	# Box piles in the storage room.
	_box_pile(holder, Vector3(-17.35, 0, -10.15), 1.0)
	_box_pile(holder, Vector3(-0.9, 0, -12.2), -1.0)


func _locker(holder: Node3D, base: Vector3, yaw: float) -> void:
	var forward := Vector3(sin(yaw + PI), 0, cos(yaw + PI))
	_solid("Locker", base + Vector3(0, 0.95, 0), Vector3(0.5, 1.9, 0.5), &"locker")
	for i in 4:
		_visual("LockerVent", base + forward * 0.252 + Vector3(0, 1.45 + i * 0.06, 0),
			Vector3(0.3, 0.02, 0.01) if absf(forward.z) > 0.5 else Vector3(0.01, 0.02, 0.3), &"black", decor, false)
	_hide_spot(holder, &"locker", base + Vector3(0, 1.0, 0) + forward * 0.05, Vector3(0.6, 2.0, 0.6),
		base + Vector3(0, 1.55, 0) + forward * 0.03, yaw, base + forward * 0.9)


## U-shaped pile of boxes open toward `open_dir` (+1 = +X, -1 = -X) with a crouch nook inside.
func _box_pile(holder: Node3D, center: Vector3, open_dir: float) -> void:
	_solid("BoxPile", center + Vector3(-0.55 * open_dir, 0.5, 0), Vector3(0.4, 1.0, 1.3), &"cardboard")
	_solid("BoxPile", center + Vector3(0.0, 0.45, -0.5), Vector3(0.7, 0.9, 0.3), &"cardboard")
	_solid("BoxPile", center + Vector3(0.0, 0.45, 0.5), Vector3(0.7, 0.9, 0.3), &"cardboard")
	_visual("BoxPileTop", center + Vector3(-0.3 * open_dir, 1.15, 0.25), Vector3(0.5, 0.3, 0.45), &"cardboard")
	_hide_spot(holder, &"boxes", center + Vector3(0.05 * open_dir, 0.5, 0), Vector3(0.7, 1.0, 0.7),
		center + Vector3(-0.1 * open_dir, 0.6, 0), -PI * 0.5 * open_dir, center + Vector3(1.0 * open_dir, 0, 0))


func _hide_spot(holder: Node3D, kind: StringName, area_center: Vector3, area_size: Vector3,
		hide_point: Vector3, hide_yaw: float, exit_point: Vector3) -> void:
	var spot := HidingSpot.new()
	spot.name = _unique("Hide_%s" % kind)
	spot.spot_kind = kind
	spot.prompt_text = "Hide"
	spot.position = area_center
	_area_shape(spot, area_size)
	var hide := Marker3D.new()
	hide.name = "HidePoint"
	hide.position = hide_point - area_center
	hide.rotation.y = hide_yaw
	spot.add_child(hide)
	var exit := Marker3D.new()
	exit.name = "ExitPoint"
	exit.position = exit_point - area_center
	spot.add_child(exit)
	holder.add_child(spot)


func _area_shape(area: Area3D, size: Vector3) -> void:
	area.collision_layer = Catalog.LAYER_INTERACT
	area.collision_mask = 0
	area.monitoring = false
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	area.add_child(shape)


# --- Lights, intercom, environment ---------------------------------------------------------

func _build_lights() -> void:
	var holder := _group(level, "Lights")
	var y_sales := 3.7
	var y_back := 2.82
	var defs := [
		# name, fixture position, colour, energy, range, always_flicker, fixture size
		["AisleLight1", Vector3(-14, y_sales, 4.0), LIGHT_COOL, 1.1, 7.0, false],
		["AisleLight2", Vector3(-10, y_sales, 0.0), LIGHT_COOL, 1.1, 7.0, false],
		["AisleLight3", Vector3(-6, y_sales, 4.0), LIGHT_COOL, 1.0, 7.0, true],
		["AisleLight4", Vector3(-2, y_sales, 0.5), LIGHT_COOL, 1.2, 7.5, false],
		["AisleLight4Front", Vector3(-2, y_sales, 6.0), LIGHT_COOL, 0.8, 6.5, false],
		["DairyLight", Vector3(-12, y_sales, -4.5), LIGHT_COOL, 1.0, 7.5, false],
		["DairyLightAisle4", Vector3(-2.5, y_sales, -4.4), LIGHT_COOL, 1.1, 7.0, false],
		["FrozenLight", Vector3(-18.3, y_sales, 1.0), LIGHT_COOL, 0.9, 7.0, false],
		["CheckoutLightWest", Vector3(-12, y_sales, 10.5), LIGHT_COOL, 1.0, 7.5, false],
		["CheckoutLightEast", Vector3(-3, y_sales, 10.5), LIGHT_COOL, 0.9, 7.5, false],
		["ServiceLight", Vector3(12, y_sales, 10.5), LIGHT_WARM, 0.9, 7.5, false],
		["ProduceLight1", Vector3(8, y_sales, -2.0), LIGHT_COOL, 1.0, 7.5, false],
		["ProduceLight2", Vector3(15, y_sales, 4.0), LIGHT_COOL, 0.7, 7.0, true],
		["HallwayEmergency1", Vector3(-12, y_back, -7.5), LIGHT_RED, 0.9, 7.0, false],
		["HallwayEmergency2", Vector3(8, y_back, -7.5), LIGHT_RED, 0.9, 7.0, false],
		["StorageEmergency", Vector3(-12, y_back, -13.0), LIGHT_RED, 0.6, 7.0, false],
		["BreakRoomLight", Vector3(6, y_back, -12.5), LIGHT_COOL, 0.8, 6.0, false],
		["OfficeLight", Vector3(13, y_back, -12.5), LIGHT_WARM, 0.7, 5.5, false],
		["JanitorLight", Vector3(18, y_back, -12.5), LIGHT_COOL, 0.5, 4.5, true],
	]
	for def: Array in defs:
		var store_light := StoreLight.new()
		store_light.name = def[0]
		store_light.position = def[1]
		store_light.base_energy = def[3]
		store_light.always_flicker = def[5]
		var omni := OmniLight3D.new()
		omni.name = "Light"
		omni.position = Vector3(0, -0.2, 0)
		omni.light_color = def[2]
		omni.light_energy = def[3]
		omni.omni_range = def[4]
		omni.omni_attenuation = 1.3
		omni.light_specular = 0.7
		omni.shadow_enabled = false
		store_light.add_child(omni)
		var is_red: bool = def[2] == LIGHT_RED
		var ceiling := SALES_CEILING if def[1].y > 3.0 else BACK_CEILING
		if is_red:
			_visual("Fixture", Vector3.ZERO, Vector3(0.3, 0.12, 0.14), &"emergency_red", store_light, false)
		else:
			var length := 1.25 if ceiling == SALES_CEILING else 0.9
			_visual("Housing", Vector3(0, 0.03, 0), Vector3(length + 0.06, 0.06, 0.26), &"metal_dark", store_light, false)
			_visual("Fixture", Vector3(0, -0.02, 0), Vector3(length, 0.04, 0.18), &"fixture_tube", store_light, false)
			for dx in [-length * 0.4, length * 0.4]:
				var rod_length: float = ceiling - def[1].y
				_visual("Rod", Vector3(dx, rod_length * 0.5, 0), Vector3(0.015, rod_length, 0.015), &"metal_dark", store_light, false)
		holder.add_child(store_light)


func _build_intercom() -> void:
	var holder := _group(level, "Intercom")
	var spots := [Vector3(-6.0, 3.85, 8.0), Vector3(2.0, 2.85, -7.5), Vector3(11.0, 3.85, 0.0)]
	for i in spots.size():
		var speaker := AudioStreamPlayer3D.new()
		speaker.name = "IntercomSpeaker%d" % (i + 1)
		speaker.position = spots[i]
		speaker.bus = &"Voice"
		speaker.unit_size = 8.0
		speaker.max_distance = 60.0
		speaker.add_to_group(&"intercom_speaker", true)
		_visual("SpeakerGrille", Vector3(0, 0.08, 0), Vector3(0.38, 0.06, 0.38), &"metal_dark", speaker, false)
		holder.add_child(speaker)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.012, 0.012)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.48, 0.44)
	env.ambient_light_energy = 0.16
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.035, 0.042, 0.04)
	env.fog_density = 0.035
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 0.95
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.85
	env.adjustment_contrast = 1.05
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	level.add_child(world_env)


func _make_navmesh() -> NavigationMesh:
	var navmesh := NavigationMesh.new()
	navmesh.cell_size = NAV_CELL_SIZE
	navmesh.cell_height = NAV_CELL_HEIGHT
	navmesh.agent_radius = 0.4
	navmesh.agent_height = 1.8
	navmesh.agent_max_climb = 0.2
	navmesh.agent_max_slope = 45.0
	navmesh.region_min_size = 22.0
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navmesh.geometry_collision_mask = Catalog.LAYER_WORLD
	return navmesh


# --- Building blocks -----------------------------------------------------------------------

## Solid world-layer box (collision + mesh), under Geometry so it is baked into the navmesh.
func _solid(base: String, center: Vector3, size: Vector3, material: StringName, parent: Node3D = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = _unique(base)
	body.collision_layer = Catalog.LAYER_WORLD
	body.collision_mask = 0
	body.position = center
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	shape.shape = _box_shape(size)
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = _box_mesh(size)
	mesh.material_override = _mat(material)
	body.add_child(mesh)
	(parent if parent else geometry).add_child(body)
	return body


## Visual-only box (no collision).
func _visual(base: String, center: Vector3, size: Vector3, material: StringName, parent: Node3D = null, shadows := true) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = _unique(base)
	mesh.mesh = _box_mesh(size)
	mesh.material_override = _mat(material)
	mesh.position = center
	if not shadows:
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else decor).add_child(mesh)
	return mesh


## Placeholder filled with boxes at load time by greybox.gd (see fill_product_run).
func _product_run(base: String, origin: Vector3, yaw: float, length: float, depth: float, levels: Array,
		palette: StringName, item_min := Vector3(0.2, 0.13, 0.07), item_max := Vector3(0.42, 0.3, 0.19),
		gap_chance := 0.08) -> void:
	var run := MultiMeshInstance3D.new()
	run.name = _unique(base)
	run.position = origin
	run.rotation.y = yaw
	run.material_override = _mat(&"products")
	run.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	run.set_meta(&"seed", _seed)
	_seed += 1
	run.set_meta(&"length", length)
	run.set_meta(&"depth", depth)
	run.set_meta(&"levels", levels)
	run.set_meta(&"palette", PackedColorArray(PALETTES[palette]))
	run.set_meta(&"item_min", item_min)
	run.set_meta(&"item_max", item_max)
	run.set_meta(&"gap_chance", gap_chance)
	decor.add_child(run)


func _group(parent: Node3D, group_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = group_name
	parent.add_child(node)
	return node


func _unique(base: String) -> String:
	var count: int = _names.get(base, 0) + 1
	_names[base] = count
	return base if count == 1 else "%s%d" % [base, count]


func _box_mesh(size: Vector3) -> BoxMesh:
	var key := str(size)
	if not _box_meshes.has(key):
		var mesh := BoxMesh.new()
		mesh.size = size
		_box_meshes[key] = mesh
	return _box_meshes[key]


func _box_shape(size: Vector3) -> BoxShape3D:
	var key := str(size)
	if not _box_shapes.has(key):
		var shape := BoxShape3D.new()
		shape.size = size
		_box_shapes[key] = shape
	return _box_shapes[key]


func _own(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_own(child, owner_node)


func _mat(id: StringName) -> StandardMaterial3D:
	if _materials.has(id):
		return _materials[id]
	var m := StandardMaterial3D.new()
	m.resource_name = String(id)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.roughness = 0.85
	match id:
		&"floor_tile":
			m.albedo_texture = _tile_texture()
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.roughness = 0.16
			m.metallic_specular = 0.7
		&"floor_concrete":
			m.albedo_texture = _noise_texture(Color(0.2, 0.21, 0.205), 0.12)
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3(0.5, 0.5, 0.5)
			m.roughness = 0.75
		&"ceiling":
			m.albedo_texture = _ceiling_texture()
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3(1.0 / 1.2, 1.0 / 1.2, 1.0 / 1.2)
		&"wall":
			m.albedo_texture = _noise_texture(Catalog.COLOR_CONCRETE, 0.08)
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3(0.5, 0.5, 0.5)
			m.roughness = 0.9
		&"shelf":
			m.albedo_color = Catalog.COLOR_OLIVE.darkened(0.15)
			m.metallic = 0.3
			m.roughness = 0.55
		&"shelf_dark":
			m.albedo_color = Color(0.17, 0.19, 0.18)
			m.metallic = 0.3
			m.roughness = 0.6
		&"counter":
			m.albedo_color = Color(0.23, 0.25, 0.24)
		&"counter_top":
			m.albedo_color = Catalog.COLOR_CREAM.darkened(0.45)
			m.roughness = 0.4
		&"cooler_frame":
			m.albedo_color = Color(0.15, 0.17, 0.16)
			m.metallic = 0.4
		&"cooler_glass":
			_glow(m, Color(0.72, 0.85, 0.8), 0.9, 0.45)
		&"freezer_glass":
			_glow(m, Color(0.55, 0.72, 0.9), 0.8, 0.45)
		&"fixture_tube":
			_glow(m, Catalog.COLOR_CREAM.lightened(0.3), 2.5, 1.0)
		&"emergency_red":
			_glow(m, Catalog.COLOR_RED.lightened(0.2), 2.0, 1.0)
		&"exit_green":
			_glow(m, Color(0.2, 0.75, 0.35), 1.6, 1.0)
		&"screen_green":
			_glow(m, Color(0.35, 0.6, 0.4), 0.8, 1.0)
		&"vending_panel":
			_glow(m, Color(0.7, 0.8, 0.85), 0.7, 1.0)
		&"spark":
			_glow(m, Color(1.0, 0.65, 0.25), 3.0, 1.0)
		&"sign_board":
			m.albedo_color = Color(0.1, 0.115, 0.11)
		&"placard":
			m.albedo_color = Color(0.85, 0.85, 0.8)
		&"glass":
			m.albedo_color = Color(0.03, 0.045, 0.055, 0.85)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.metallic = 0.6
			m.roughness = 0.05
		&"cardboard":
			m.albedo_color = Color("8a6a45")
		&"paper":
			m.albedo_color = Color(0.6, 0.6, 0.55)
		&"wood":
			m.albedo_color = Color("6b5236")
		&"wood_dark":
			m.albedo_color = Color("3f3022")
		&"locker":
			m.albedo_color = Catalog.COLOR_OLIVE.darkened(0.1)
			m.metallic = 0.35
			m.roughness = 0.5
		&"metal":
			m.albedo_color = Color(0.25, 0.27, 0.26)
			m.metallic = 0.5
			m.roughness = 0.5
		&"metal_dark":
			m.albedo_color = Color(0.12, 0.13, 0.13)
			m.metallic = 0.4
			m.roughness = 0.55
		&"black":
			m.albedo_color = Color(0.05, 0.055, 0.055)
		&"door_red":
			m.albedo_color = Color(0.32, 0.15, 0.13)
		&"yellow":
			m.albedo_color = Color("c9a227")
		&"orange":
			m.albedo_color = Catalog.COLOR_ORANGE
		&"products":
			m.vertex_color_use_as_albedo = true
			m.roughness = 0.7
		&"products_red":
			m.albedo_color = Color("b8442f")
		&"puddle":
			m.albedo_color = Color(0.05, 0.07, 0.07, 0.8)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.02
			m.metallic = 0.3
		_:
			push_error("unknown material %s" % id)
	_materials[id] = m
	return m


func _glow(m: StandardMaterial3D, color: Color, energy: float, alpha: float) -> void:
	m.albedo_color = Color(color, alpha)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


## Two-tone 0.5 m floor tiles with grout (32 px per metre).
func _tile_texture() -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for y in 32:
		for x in 32:
			var light := ((x >> 4) + (y >> 4)) % 2 == 1
			var c := Color(0.2, 0.215, 0.21) if light else Color(0.165, 0.18, 0.175)
			if x % 16 == 0 or y % 16 == 0:
				c = Color(0.09, 0.1, 0.098)
			img.set_pixel(x, y, c.darkened(rng.randf() * 0.12))
	return ImageTexture.create_from_image(img)


## Drop-ceiling tiles (two per texture repeat) with a dark grid.
func _ceiling_texture() -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	for y in 32:
		for x in 32:
			var c := Color(0.3, 0.31, 0.29)
			if (x >> 4) == 1 and (y >> 4) == 0:
				c = Color(0.2, 0.2, 0.19)
			if x % 16 == 0 or y % 16 == 0:
				c = Color(0.1, 0.1, 0.1)
			img.set_pixel(x, y, c.darkened(rng.randf() * 0.1))
	return ImageTexture.create_from_image(img)


func _noise_texture(base: Color, amount: float) -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(base.r * 1000)
	for y in 32:
		for x in 32:
			img.set_pixel(x, y, base.darkened(rng.randf() * amount).lightened(rng.randf() * amount * 0.3))
	return ImageTexture.create_from_image(img)
