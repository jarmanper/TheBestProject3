extends SceneTree
## Generates res://levels/greybox/greybox.tscn (+ greybox_navmesh.res) from the
## docs/ARCHITECTURE.md §7 layout. Re-run after changing the layout:
##   godot --headless --path . -s res://levels/greybox/build_greybox.gd
## A thin launcher (like tools/build_store_level.gd): the logic is in greybox_builder.gd, loaded
## after the first frame, once the autoloads exist -- the level's node scripts need them, and
## they do not exist yet while a `-s` script compiles.

const BUILDER := "res://levels/greybox/greybox_builder.gd"
const SALES_CEILING := 4.0
const BACK_CEILING := 3.0

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


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame   # the autoloads exist from here on
	var builder: RefCounted = load(BUILDER).new()
	var err: Error = await builder.build(self)
	quit(0 if err == OK else 1)
