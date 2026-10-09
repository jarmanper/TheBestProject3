extends SceneTree
## Builds the final store level: res://levels/store/store.tscn (+ store_navmesh.res).
##   godot --headless --path . -s res://tools/build_store_level.gd
## Re-runnable and deterministic. Satisfies the level contract in docs/ARCHITECTURE.md §6:
## the store art (store_interior.glb) at the origin, 14 StoreZones (from the greybox table),
## spawns, patrol points, intercom speakers, the 13 task stations (StationLayout), 5 tool racks,
## 9 hiding spots, props, StoreLights at the art's light anchors plus emergency/exit/cooler
## lights, ambience emitters, a WorldEnvironment and a baked NavigationRegion3D.
## Logic: tools/level/store_builder.gd; placement data: tools/level/store_layout.gd;
## environment: tools/level/store_environment.gd.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame   # the autoloads exist from here on
	var builder: RefCounted = load("res://tools/level/store_builder.gd").new()
	var err: Error = await builder.build(self)
	quit(0 if err == OK else 1)
