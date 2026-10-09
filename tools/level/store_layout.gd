extends RefCounted
## Placement data for the final store level (tools/build_store_level.gd).
## Godot coordinates (docs/ARCHITECTURE.md §7): +Z toward the entrance, floor at y = 0.
## Yaw is in degrees around +Y; for models and stations it turns their front (+Z) toward
## (sin yaw, 0, cos yaw). Zones come from levels/greybox/build_greybox.gd (ZONE_BOUNDS)
## and stations from systems/environment/station_layout.gd — not repeated here.
##
## Wall faces used below: the hallway wall z = -9 is 0.2 m thick (room side z = -9.1, hallway
## side z = -8.9); partitions x = 2 / 10 / 16 are 0.2 m thick; exterior walls sit outside the
## footprint (inner faces x = ±20, z = -16 / 16).

const PROPS_DIR := "res://assets/models/props/"

## Wall-prop origin heights above the floor (Task 3, props.py MOUNT_HEIGHTS).
const MOUNT_HEIGHTS := {
	&"pickup_mop": 1.35,
	&"pickup_box_cutter": 1.25,
	&"pickup_keys": 1.45,
	&"clipboard": 1.35,
	&"breaker_sparks": 1.5,
	&"time_clock": 1.4,
	&"breaker_panel": 1.5,
}

# --- Markers ------------------------------------------------------------------------------

## Player camera looks down -Z, so yaw 180 faces +Z (the break room door).
const PLAYER_SPAWN := {"position": Vector3(6.0, 0.0, -12.5), "yaw": 180.0}
## Characters face their model front (+Z): yaw 0 faces +Z.
const COWORKER_SPAWNS := [
	{"position": Vector3(4.0, 0.0, -14.4), "yaw": 30.0},
	{"position": Vector3(8.2, 0.0, -11.2), "yaw": -60.0},
	{"position": Vector3(-1.5, 0.0, -7.4), "yaw": 90.0},
]
const MONSTER_SPAWN := {"position": Vector3(-18.0, 0.0, -15.0), "yaw": 90.0}
## Behind the desk, facing the office door.
const MANAGER_SPOT := {"position": Vector3(13.0, 0.0, -15.15), "yaw": 0.0}

## Roam / flee targets, at least one per zone, all on open floor.
const PATROL_POINTS := [
	Vector3(-14.0, 0.0, 0.5),      # aisle_1
	Vector3(-10.0, 0.0, 5.5),      # aisle_2
	Vector3(-6.0, 0.0, -1.5),      # aisle_3
	Vector3(-2.0, 0.0, 4.5),       # aisle_4
	Vector3(-17.0, 0.0, -4.0),     # dairy
	Vector3(-5.0, 0.0, -4.0),      # dairy
	Vector3(-18.0, 0.0, 5.5),      # frozen
	Vector3(7.0, 0.0, 4.0),        # produce
	Vector3(15.0, 0.0, -0.5),      # produce
	Vector3(11.0, 0.0, 8.2),       # produce
	Vector3(-14.5, 0.0, 8.5),      # checkout
	Vector3(-4.5, 0.0, 14.5),      # checkout
	Vector3(3.5, 0.0, 11.5),       # checkout
	Vector3(17.5, 0.0, 11.0),      # service_desk
	Vector3(8.0, 0.0, 10.0),       # service_desk
	Vector3(-15.0, 0.0, -7.5),     # hallway
	Vector3(2.5, 0.0, -7.5),       # hallway
	Vector3(15.0, 0.0, -7.5),      # hallway
	Vector3(-12.0, 0.0, -13.0),    # storage (central aisle)
	Vector3(-18.6, 0.0, -13.0),    # storage (by the emergency exit)
	Vector3(-5.5, 0.0, -11.5),     # storage (open end)
	Vector3(4.2, 0.0, -10.4),      # break_room
	Vector3(11.3, 0.0, -10.3),     # office
	Vector3(17.3, 0.0, -11.0),     # janitor
]

## Ceiling PA speakers (group intercom_speaker).
const INTERCOM_SPEAKERS := [
	Vector3(-8.0, 3.9, 2.0),
	Vector3(10.0, 3.9, 2.0),
	Vector3(-6.0, 3.9, 12.0),
	Vector3(0.0, 2.9, -7.5),
	Vector3(-12.0, 2.9, -12.5),
	Vector3(6.0, 2.9, -11.0),
]

## Positional ambience loops (quiet).
const AMBIENT_EMITTERS := [
	{"id": &"amb_freezer_hum", "position": Vector3(-14.0, 1.2, -5.2), "db": -10.0, "range": 12.0},
	{"id": &"amb_freezer_hum", "position": Vector3(-4.0, 1.2, -5.2), "db": -10.0, "range": 12.0},
	{"id": &"amb_freezer_hum", "position": Vector3(-19.0, 1.2, 2.0), "db": -10.0, "range": 12.0},
	{"id": &"amb_backroom", "position": Vector3(-8.0, 2.0, -7.5), "db": -12.0, "range": 16.0},
	{"id": &"amb_backroom", "position": Vector3(10.0, 2.0, -7.5), "db": -12.0, "range": 16.0},
	{"id": &"amb_backroom", "position": Vector3(-12.0, 2.0, -12.8), "db": -10.0, "range": 16.0},
]

# --- Tools and hiding spots ------------------------------------------------------------------

## Tool racks (systems/environment/tools/pickup_<tool>.tscn); wall racks at their mount height.
const TOOL_RACKS := [
	{"tool": &"mop", "position": Vector3(19.98, 1.35, -12.6), "yaw": -90.0},           # janitor closet, east wall
	{"tool": &"price_gun", "position": Vector3(13.2, 1.05, 12.42), "yaw": 180.0},      # service desk top
	{"tool": &"box_cutter", "position": Vector3(1.9, 1.25, -12.7), "yaw": -90.0},      # storage, east partition
	{"tool": &"stock_box", "position": Vector3(1.666, 0.0, -10.55), "yaw": -90.0},     # storage, east partition
	{"tool": &"keys", "position": Vector3(10.1, 1.45, -11.2), "yaw": 90.0},            # office, west partition
]

## Hiding spots (systems/environment/hiding/hide_<kind>.tscn). +Z of each spot is its opening.
## Counter cavities (Task 2): checkouts x cx-0.35..cx+0.45, z 11.4..12.2 open on +X;
## service desk x 10.2..11.0, z 12.1..12.9 open on +Z.
const HIDING_SPOTS := [
	{"kind": &"locker", "position": Vector3(2.37, 0.0, -10.35), "yaw": 90.0},
	{"kind": &"locker", "position": Vector3(2.37, 0.0, -10.88), "yaw": 90.0},
	{"kind": &"locker", "position": Vector3(2.37, 0.0, -11.41), "yaw": 90.0},
	{"kind": &"boxes", "position": Vector3(-4.4, 0.0, -14.55), "yaw": 0.0},
	{"kind": &"boxes", "position": Vector3(-1.2, 0.0, -10.2), "yaw": 90.0},
	{"kind": &"counter", "position": Vector3(-11.95, 0.0, 11.8), "yaw": 90.0},
	{"kind": &"counter", "position": Vector3(-6.95, 0.0, 11.8), "yaw": 90.0},
	{"kind": &"counter", "position": Vector3(-1.95, 0.0, 11.8), "yaw": 90.0},
	{"kind": &"counter", "position": Vector3(10.6, 0.0, 12.5), "yaw": 0.0},
]

# --- Props -------------------------------------------------------------------------------------

## [model, position, yaw, collider]. collider: "auto" = a box around the model, "" = none
## (flat debris you walk over, wall-mounted things).
const PROPS := [
	# Break room: time clock by the spawn, table and chairs, vending machine, trash.
	["time_clock", Vector3(7.0, 1.4, -9.1), 180.0, ""],
	["break_table", Vector3(6.6, 0.0, -14.6), 0.0, "auto"],
	["chair", Vector3(6.1, 0.0, -15.35), 0.0, "auto"],
	["chair", Vector3(7.1, 0.0, -15.3), -8.0, "auto"],
	["chair", Vector3(6.2, 0.0, -13.85), 172.0, "auto"],
	["chair", Vector3(7.25, 0.0, -13.7), 200.0, "auto"],
	["walkie_talkie", Vector3(6.35, 0.85, -14.55), 35.0, ""],
	["vending_machine", Vector3(9.5, 0.0, -13.2), -90.0, "auto"],
	["trash_bin", Vector3(8.8, 0.0, -9.45), 0.0, "auto"],
	# Manager's office: desk, CRT, intercom mic, office chair (manager_spot is behind the desk).
	["manager_desk", Vector3(13.0, 0.0, -13.95), 0.0, "auto"],
	["crt_monitor", Vector3(12.5, 0.76, -14.0), 160.0, ""],
	["intercom_mic", Vector3(13.5, 0.76, -13.8), 195.0, ""],
	["office_chair", Vector3(14.45, 0.0, -14.95), -140.0, "auto"],
	["trash_bin", Vector3(15.55, 0.0, -9.55), 0.0, "auto"],
	["cardboard_box_a", Vector3(10.5, 0.0, -15.6), 8.0, "auto"],
	["cardboard_box_c", Vector3(10.55, 0.34, -15.62), -14.0, ""],
	# Janitor closet: sink, mop bucket (the mop hangs on the east wall).
	["sink", Vector3(18.7, 0.0, -15.75), 0.0, "auto"],
	["mop_bucket", Vector3(17.0, 0.0, -15.35), 25.0, "auto"],
	["trash_bag", Vector3(19.55, 0.0, -9.6), 40.0, "auto"],
	["wet_floor_sign", Vector3(16.6, 0.0, -15.6), 15.0, "auto"],
	# Back hallway: breaker panel (replaces the static box in the store art), baler, cart, bags.
	["breaker_panel", Vector3(0.0, 1.5, -8.9), 0.0, ""],
	["baler", Vector3(-19.33, 0.0, -7.5), 90.0, "auto"],
	["shopping_cart", Vector3(-13.0, 0.0, -6.55), 95.0, "auto"],
	["trash_bag", Vector3(-8.2, 0.0, -6.42), 0.0, "auto"],
	["trash_bag", Vector3(-7.65, 0.0, -6.45), 70.0, "auto"],
	["flattened_boxes", Vector3(3.6, 0.0, -8.35), 8.0, "auto"],
	# Storage room (reference 3): carts in the aisle, boxes, debris, a pallet of stock.
	["shopping_cart", Vector3(-8.9, 0.0, -12.3), 92.0, "auto"],
	["shopping_cart", Vector3(-15.4, 0.0, -12.35), 76.0, "auto"],
	["cardboard_box_b", Vector3(-13.9, 0.0, -13.75), 20.0, "auto"],
	["cardboard_box_a", Vector3(-14.55, 0.0, -13.8), -10.0, "auto"],
	["cardboard_box_a", Vector3(-14.5, 0.34, -13.78), 25.0, ""],
	["newspaper_debris", Vector3(-11.6, 0.0, -13.0), 30.0, ""],
	["newspaper_debris", Vector3(-7.4, 0.0, -13.4), -40.0, ""],
	["flattened_boxes", Vector3(-16.7, 0.0, -13.55), -15.0, "auto"],
	["pallet_boxes", Vector3(-0.42, 0.0, -15.35), 0.0, "auto"],
	["trash_bag", Vector3(-3.9, 0.0, -9.5), 0.0, "auto"],
	["trash_bag", Vector3(1.4, 0.0, -9.5), 120.0, "auto"],
	# Sales floor: carts by the entrance, stray boxes, a wet-floor sign.
	["shopping_cart", Vector3(2.75, 0.0, 15.0), 90.0, "auto"],
	["shopping_cart", Vector3(3.15, 0.0, 15.0), 90.0, ""],
	["shopping_cart", Vector3(3.55, 0.0, 15.0), 90.0, ""],
	["shopping_cart", Vector3(-17.5, 0.0, 9.0), 140.0, "auto"],
	["cardboard_box_a", Vector3(1.4, 0.0, 7.9), 15.0, "auto"],
	["cardboard_box_b", Vector3(-17.9, 0.0, 7.6), -30.0, "auto"],
	["cardboard_box_c", Vector3(5.4, 0.0, -4.9), 5.0, "auto"],
	["wet_floor_sign", Vector3(-9.9, 0.0, 7.7), 30.0, "auto"],
	["newspaper_debris", Vector3(-2.2, 0.0, -2.2), 75.0, ""],
]

# --- Lighting ------------------------------------------------------------------------------------

## Fluorescent fixtures (LightAnchor_###) that stay dark: about a third of the working ones,
## so the floor alternates bright and dark pools.
const FIXTURES_OFF := [2, 4, 8, 14, 16, 19, 21, 24, 25, 29, 32, 34, 36, 38, 40, 42, 44]
## Broken fixtures (Fixture_###_broken): flicker constantly, or are dead.
const BROKEN_FLICKER := [11, 13, 41, 45]
const BROKEN_DEAD := [6, 18, 28, 47]
## Fixtures with an audible buzz (budget <= 10).
const BUZZING := [11, 13, 41, 45, 43, 48, 50, 52]
## Per-zone light energy (back rooms barely lit).
const ZONE_ENERGY := {
	&"hallway": 0.55,
	&"storage": 0.7,
	&"break_room": 1.15,
	&"office": 0.75,
	&"janitor": 0.6,
}
const FIXTURE_ENERGY := 1.0
const FIXTURE_RANGE := 5.5
const FIXTURE_ATTENUATION := 1.5
const FIXTURE_COLOR := Color(0.86, 0.9, 0.8)
const OFFICE_COLOR := Color(0.95, 0.88, 0.72)

const EMERGENCY_COLOR := Color(0.95, 0.16, 0.12)
const EMERGENCY_ENERGY := 1.4
const EMERGENCY_RANGE := 4.5
const EXIT_COLOR := Color(0.2, 1.0, 0.42)
const EXIT_ENERGY := 1.2
const EXIT_RANGE := 4.0
const COOLER_COLOR := Color(0.81, 0.89, 0.94)
const COOLER_ENERGY := 0.6
const COOLER_RANGE := 3.5
