class_name Catalog
extends RefCounted
## Shared ids, display names, asset paths and constants that several systems agree on.
## See docs/ARCHITECTURE.md. Change a value here, not in the systems that read it.

const GAME_TITLE := "GRAVEYARD SHIFT"

# Physics layer bit values (layer N = 1 << (N - 1)).
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_MONSTER := 4
const LAYER_NPC := 8
const LAYER_INTERACT := 16

# GDD §6 palette.
const COLOR_CHARCOAL := Color("171B1A")
const COLOR_ORANGE := Color("E87932")
const COLOR_OLIVE := Color("626D58")
const COLOR_CREAM := Color("D8D3A8")
const COLOR_RED := Color("B93B32")
const COLOR_CONCRETE := Color("444A48")

const ZONES := {
	&"aisle_1": "Aisle 1",
	&"aisle_2": "Aisle 2",
	&"aisle_3": "Aisle 3",
	&"aisle_4": "Aisle 4",
	&"dairy": "Dairy",
	&"frozen": "Frozen Foods",
	&"produce": "Produce",
	&"checkout": "Checkout",
	&"service_desk": "Customer Service",
	&"hallway": "Back Hallway",
	&"storage": "Storage Room",
	&"break_room": "Break Room",
	&"office": "Manager's Office",
	&"janitor": "Janitor Closet",
}

## consumed: the tool goes back to its rack when a task that needs it completes.
const TOOLS := {
	&"mop": {"name": "Mop", "consumed": false},
	&"price_gun": {"name": "Price Gun", "consumed": false},
	&"box_cutter": {"name": "Box Cutter", "consumed": false},
	&"stock_box": {"name": "Stock Box", "consumed": true},
	&"keys": {"name": "Store Keys", "consumed": false},
}

const COWORKERS := [
	{"name": "DALE", "model": "res://assets/models/characters/employee_dale.glb"},
	{"name": "RITA", "model": "res://assets/models/characters/employee_rita.glb"},
	{"name": "MARCUS", "model": "res://assets/models/characters/employee_marcus.glb"},
]
const MODEL_MANAGER := "res://assets/models/characters/manager.glb"
const MODEL_MONSTER := "res://assets/models/characters/monster.glb"

## Animation names inside character .glb files.
const ANIM_IDLE := &"idle"
const ANIM_WALK := &"walk"
const ANIM_RUN := &"run"
const ANIM_WORK := &"work"
const ANIM_ATTACK := &"attack"   ## monster only
const ANIM_REVEAL := &"reveal"   ## monster only
const ANIM_TALK := &"talk"       ## manager only

const SCENES := {
	&"main_menu": "res://scenes/main_menu.tscn",
	&"game": "res://scenes/game.tscn",
	&"level": "res://levels/store/store.tscn",
	&"level_greybox": "res://levels/greybox/greybox.tscn",
	&"player": "res://systems/player/player.tscn",
	&"coworker": "res://systems/coworkers/coworker.tscn",
	&"monster": "res://systems/monster/monster.tscn",
	&"store_manager": "res://systems/manager/store_manager.tscn",
	&"hud": "res://ui/hud/hud.tscn",
}


static func tool_name(tool_id: StringName) -> String:
	return TOOLS.get(tool_id, {}).get("name", String(tool_id))


static func tool_icon_path(tool_id: StringName) -> String:
	return "res://assets/ui/icons/icon_%s.png" % tool_id


static func tool_viewmodel_path(tool_id: StringName) -> String:
	return "res://assets/models/viewmodels/vm_%s.glb" % tool_id


static func zone_name(zone_id: StringName) -> String:
	return ZONES.get(zone_id, String(zone_id).capitalize())


## Loads a PackedScene if it exists, else returns null without erroring.
static func load_scene_or_null(path: String) -> PackedScene:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as PackedScene
