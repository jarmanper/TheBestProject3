# Architecture & Contracts

This is the shared contract every system builds against. If you change a name,
path or signature here, update every system that uses it. The design itself comes
from the GDD (`Project 3 Kickoff.pdf`); the look comes from the three reference
images in `docs/art_reference/` ("the pictures are exactly how the game should look").

## 1. Game summary (from the GDD)

Store employees work a late shift completing tasks around a supermarket while a
monster that mimics them hunts them down.

- **Single-player adaptation.** The game must run on GitHub Pages (static hosting, no
  game server), so the other three employees are AI coworkers. The monster mimics
  *them*: their look, their behaviour and their walkie-talkie voices.
- **Night:** 12:00 AM to 6:00 AM, `GameState.SECONDS_PER_HOUR` = 90 real seconds per hour (9 minutes total).
- **Win:** reach 6:00 AM alive with every basic task done ("SHIFT COMPLETE").
- **Fired:** reach 6:00 AM alive with basic tasks left ("YOU'RE FIRED").
- **Dead:** health reaches 0 ("YOU DIDN'T MAKE IT").
- **In scope (GDD §7):** hiding spots, stamina/sprinting, task checklist.
- **Out of scope (GDD §7):** monster health, weapons, in-game voice chat. No ammo, no guns, no combat.
  The HUD in the reference pictures shows AMMO — we do **not** copy that part.

### Systems and owners (GDD §2)

| System | Owner | Folder |
|---|---|---|
| Store Manager — NPC who gives bonus tasks by walkie-talkie or store intercom | Anthony | `systems/manager/` |
| Store Environment — basic tasks, tools, hiding spots, store lights | Caleb | `systems/environment/` |
| Monster — mimic, chase, rules | team | `systems/monster/` |
| Coworkers — AI employees | team | `systems/coworkers/` |
| Player — first-person controller | team | `systems/player/` |

### Seams (GDD §3)

1. **Intercom → Monster.** `StoreManager` writes `Events.intercom_announced(message, zone)`.
   Everyone hears it, *including the monster*, which reads it and heads to that zone to wait
   for whoever answers. Walkie messages are private: the monster does **not** hear them.
2. **Manager → Tasks → Workers.** `StoreManager` adds a task with `Tasks.add_manager_task()`.
   `Tasks` sorts manager tasks above basic tasks (priority); coworkers always claim open
   manager tasks first; the HUD checklist lists them first.
3. **Tasks ↔ Tools.** Some tasks need a tool (`TaskData.required_tool`). The player picks
   tools up from `ToolPickup` racks; `TaskStation.can_interact()` reads `player.held_tool`.

### Monster rules (GDD §5) — exact values live in `systems/monster/monster.gd` constants

1. **13-second sprint.** It can sprint for at most `SPRINT_MAX_TIME = 13.0` s, then it is
   *winded* (`WINDED_TIME = 6.0` s, slow, loud wheezing). Players learn: survive 13 s and it gasps.
2. **Turns after lingering in range.** While disguised, if the player stays within
   `REVEAL_RANGE = 7.0` m in line of sight for `REVEAL_TIME = 4.0` s, it transforms to its true
   form and attacks. Players learn: a coworker who stops working and just watches you is wrong.
3. **Appears to everyone at least once.** If the player has not seen it (true or disguised) by
   `SIGHTING_DEADLINE_HOUR = 2` (2:00 AM), the monster stages a sighting: it appears inside the
   player's view at a distance, holds, and leaves. It does not have to approach.

Disguise tells for observant players: no footstep sounds, head twitches, standing still
facing shelves/walls, "working" on things that are not tasks, flashlight and nearby store
lights flicker when it is within ~12 m.

## 2. Engine & project rules

- Godot **4.7.2**, GDScript, **Compatibility renderer** (`gl_compatibility`) because the
  web export only supports it. Physics: Jolt (existing setting).
- Web export with **threads disabled** (GitHub Pages cannot send COOP/COEP headers).
- Audio buses: `Master`, `Music`, `SFX`, `Ambience`, `Voice` (volume only — the web build plays
  audio as Web Audio samples, which ignores bus effects, so radio/PA filtering is baked into
  the audio files).
- Typed GDScript, tabs, `snake_case` files, `PascalCase` `class_name`s.
- Never block on missing assets: load models/sounds by the paths below and fall back to a
  placeholder (capsule/box, silence + one `push_warning`) if a file is missing.

### Folders

```
autoload/            Events, GameState, Sfx (singletons)
systems/shared/      Catalog (ids, paths, palette, layers)
systems/interaction/ Interactable base class
systems/player/      Player (+ viewmodel)
systems/environment/ Tasks (autoload), TaskData, TaskStation, ToolPickup, HidingSpot, StoreZone, StoreLight
systems/manager/     StoreManager + manager NPC
systems/monster/     Monster + Perception helpers
systems/coworkers/   Coworker
ui/                  HUD, menus, post-processing (CRT)
levels/greybox/      CSG blockout of the layout below (for testing)
levels/store/        Final store level (art + gameplay nodes)
scenes/              main_menu.tscn, game.tscn
assets/models/       characters/, environment/, props/, viewmodels/ (.glb exported from Blender)
assets/audio/        sfx/, ambience/, music/
assets/ui/icons/     32x32 pixel icons
assets/fonts/        pixel font
art_source/          Blender generator scripts + .blend files (has .gdignore)
tests/               headless test runner + test_*.gd
docs/                this file + art_reference/ (has .gdignore)
```

### Running tests

```
godot --headless --path . --import            # first time / after adding assets
godot --headless --path . -s res://tests/run_tests.gd                 # all tests
godot --headless --path . -s res://tests/run_tests.gd -- --filter=monster
```

Tests are `tests/**/test_*.gd` files that `extends TestCase` and define `func test_*()` methods
(they may `await`). Use `assert_true/assert_false/assert_eq/assert_near`. `self.tree` is the
running `SceneTree`; add nodes under `tree.root` and free them at the end of the test.

## 3. Physics layers

| Layer | Bit value | Name | Used by |
|---|---|---|---|
| 1 | 1 | world | static geometry (walls, shelves, counters). Blocks line of sight. |
| 2 | 2 | player | Player body |
| 3 | 4 | monster | Monster body |
| 4 | 8 | npc | Coworkers, manager NPC |
| 5 | 16 | interact | `Interactable` Area3Ds (task stations, tools, hiding spots) |

Masks: Player = world+npc (9). Monster = world (1). Coworker = world (1).
Bit constants live in `Catalog.LAYER_*`.

## 4. Groups

`player`, `monster`, `coworker`, `employee` (coworkers + manager NPC), `task_station`,
`tool_pickup`, `hiding_spot`, `store_zone`, `store_light`, `intercom_speaker`,
`player_spawn`, `coworker_spawn`, `monster_spawn`, `manager_spot`, `patrol_point`.

## 5. Autoload APIs

### `Events` (`autoload/events.gd`) — signal bus
See the file; it is the authoritative list. Systems emit/connect there instead of
holding references to each other.

### `GameState` (`autoload/game_state.gd`)
Night clock (`start_night()`, `advance(delta)`, `get_clock_text()`, `get_hour()`,
`get_night_progress()`), `end_night(result)`, stats dictionary, settings
(`mouse_sensitivity`, `master_volume`, `crt_enabled`) persisted to `user://settings.cfg`,
and registered references: `player`, `monster`, `world_root` (the `Node3D` that holds the level,
inside the game's 3D viewport).

### `Sfx` (`autoload/sfx.gd`)
`Sfx.play(id)` (2D/UI), `Sfx.play_at(id, position)` (one-shot 3D, parented under
`GameState.world_root`), `Sfx.get_stream(id)` (for looping emitters you own). Sound ids map to
base paths without an extension; `.ogg` is tried first, then `.wav`. Ids with several variants
pick one at random. `Sfx.LOOPING` ids are returned with looping enabled.

### `Tasks` (`systems/environment/task_manager.gd`)
See the file's public methods; summary:
`reset()`, `begin_night()`, `add_manager_task(station, time_limit) -> TaskData`,
`complete_task(task, by)`, `claim_task(task, worker) -> bool`, `release_task(task, worker)`,
`get_open_tasks() -> Array[TaskData]` (manager tasks first), `get_tasks_for_checklist()`,
`get_required_remaining() -> int`, `all_required_done() -> bool`.

## 6. Scene contracts

### Player — `systems/player/player.tscn`, `class_name Player extends CharacterBody3D`
Public API other systems may call (see `systems/player/player.gd`):
`health`, `max_health`, `stamina`, `max_stamina`, `held_tool: StringName`, `is_hidden: bool`,
`current_hiding_spot`, `take_damage(amount, from_position)`, `enter_hiding(spot)`,
`exit_hiding()`, `set_held_tool(id)`, `has_tool(id)`, `get_noise_level() -> float`
(0 still/hidden, 0.35 walking, 1.0 sprinting), `get_eye_position() -> Vector3`,
`get_camera() -> Camera3D`, `input_enabled`.
Camera: first person, FOV **95°**, slight sway while walking, subtle extra movement while
sprinting. A `SpotLight3D` flashlight (toggle `flashlight`) flickers when the monster is near.

### Interactable — `systems/interaction/interactable.gd`, `class_name Interactable extends Area3D`
Collision layer 5 (interact). The player ray-casts on layers world+interact (so walls block it)
and calls `get_prompt(player)`, `can_interact(player)`, `interact(player)`. `hold_time > 0` means
the player must hold `interact` that long; the player drives the progress bar and calls
`hold_started(player)` / `hold_stopped(player)` (stopped = cancelled, not completed).

### Who plays which voice audio
- **Walkie** (`Events.walkie_message`): the player side (HUD/radio) plays `walkie_squelch_on`,
  then `walkie_voice` (or `walkie_voice_mimic` when `is_mimic`), then `walkie_squelch_off`, on the
  `Voice` bus, and shows the subtitle `[RADIO] NAME: message`.
- **Intercom** (`Events.intercom_announced`): `StoreManager` plays `intercom_chime` + `intercom_voice`
  positionally at every `intercom_speaker`; the HUD shows `[INTERCOM] message`.
- `Events.subtitle`: HUD only.

### Model orientation and scale
1 Blender unit = 1 m. Models are authored facing Blender **-Y** (Blender's front view), which the
glTF exporter turns into Godot **+Z** ("model front"). Code that turns a character toward a point
uses `look_at(target, Vector3.UP, true)` (use_model_front). Origins: characters and floor props at
the floor centre of their footprint; wall props at the wall-contact centre. Viewmodels: see the
props task — they are posed for a camera looking down Godot -Z.

### TaskStation, ToolPickup, HidingSpot (extend Interactable)
- `TaskStation`: one place in the store where a task can be done. `task_kind`, `zone`,
  `title`, `required_tool`, `hold_time`, `basic_task`, child `ActiveVisual` (shown only while its
  task is active, e.g. the spill decal), `get_work_position() -> Vector3`.
- `ToolPickup`: `tool_id`; gives the player that tool (the previously held tool goes back to its
  own rack).
- `HidingSpot`: `spot_kind` (`&"locker"`, `&"counter"`, `&"boxes"`), child `Marker3D`s
  `HidePoint` (camera position/rotation while hidden) and `ExitPoint`, `is_occupied()`,
  `pull_out_occupant()` (monster found you).

### StoreZone — `systems/environment/store_zone.gd`, `class_name StoreZone extends Area3D`
`zone_id`, `display_name`, a `BoxShape3D`, `get_random_point() -> Vector3`,
static `StoreZone.find_zone_id_at(tree, position) -> StringName`.

### Level scene contract (greybox and final store)
Root `Node3D` containing: `Marker3D` in groups `player_spawn` (1), `coworker_spawn` (3),
`monster_spawn` (1), `manager_spot` (1), several `patrol_point`s; `StoreZone`s;
`TaskStation`s; `ToolPickup`s; `HidingSpot`s; `StoreLight`s; a `NavigationRegion3D` with a
baked mesh (agent radius 0.4 m, height 1.8 m); `AudioStreamPlayer3D`s in group
`intercom_speaker`; a `WorldEnvironment`.

### Game scene — `scenes/game.tscn`
```
Game (Node, game.gd)
├─ WorldView (SubViewportContainer, stretch, stretch_shrink 2 → 3D at half resolution, nearest upscale)
│  └─ SubViewport
│     └─ World (Node3D)  ← GameState.world_root
│        ├─ Level (instance of Catalog.SCENES.level)
│        ├─ Player, Coworkers ×3, Monster, StoreManager
├─ PostFX (CanvasLayer 1) — CRT/vignette/grain screen shader
├─ HUD (CanvasLayer 2)
└─ Menus (CanvasLayer 3) — pause, end screens
```
`game.gd` spawns actors at the level's spawn markers, calls `GameState.start_night()` and
`Tasks.begin_night()`, and switches to the end screen on `Events.night_ended`.

### Monster proximity effects
The monster calls `StoreLight.set_disturbance(amount)` (0..1, from distance) on lights within 12 m
about every 0.25 s; a light's disturbance decays to 0 within 0.5 s when no longer refreshed. The
player's flashlight reads `GameState.monster` distance itself and flickers within 12 m.

## 7. Store layout (Godot coordinates, metres)

Y is up. **+Z points toward the store entrance (front), -Z toward the back.** Floor at y = 0.
Blender is Z-up: Blender (x, y, z) = Godot (x, -z, y). Exterior walls 0.3 m thick.
Sales floor ceiling height 4.0 m (drop ceiling); back-of-house ceiling 3.0 m.

**Footprint:** x ∈ [-20, 20], z ∈ [-16, 16].

**Sales floor** (x -20..20, z -6..16)
- Front wall z = 16 with locked glass entrance doors at x -2..2 (black night outside).
- **Checkout** (zone `checkout`, x -20..6, z 7..16): three checkout counters 0.9 m wide × 3 m long
  running along Z (z 10..13) centred at x = -12, -7, -2, register at the z = 13 end.
- **Customer service** (zone `service_desk`, x 6..20, z 9..16): L-shaped desk around x 9..15, z 12..14.5.
- **Aisles:** five gondola shelf rows, each 1.2 m deep × 10 m long (z -3..7), 2.2 m tall, five shelf
  levels, centred at x = -16, -12, -8, -4, 0. Aisles between them:
  - `aisle_1` x -15.4..-12.6 (centre -14) — CEREAL
  - `aisle_2` x -11.4..-8.6 (centre -10) — SNACKS
  - `aisle_3` x -7.4..-4.6 (centre -6) — DRINKS
  - `aisle_4` x -3.4..-0.6 (centre -2) — left side (row x=-4) has SNACKS / DRINKS / CEREAL sections
    with shelf-top signs exactly like reference image 1/2; right side (row x=0) canned goods.
  - Hanging "AISLE n" sign above each aisle centre at z = 2, y = 3.3.
- **Dairy** (zone `dairy`, x -20..2, z -6..-3): glass-door wall coolers along the back wall z = -6
  (0.8 m deep, lit inside), hanging "DAIRY" sign at x = -2, z = -5.4, y = 3.0 — visible at the end of
  Aisle 4 like the reference pictures.
- **Frozen** (zone `frozen`, x -20..-16.6, z -3..7): wall freezers along x = -20, "FROZEN" sign.
- **Produce** (zone `produce`, x 2..20, z -6..9): low produce tables (0.9 m) in a grid, pallets.
- **Employees-only doorway** in the back wall z = -6 at x 6..8.4 (double-door opening, sign above).

**Back of house** (z -16..-6, ceiling 3.0 m)
- **Back hallway** (zone `hallway`, x -20..20, z -9..-6): wall z = -9 has door openings into each
  room; breaker panel on the hallway wall near x = 0. Red emergency lighting.
- **Storage room** (zone `storage`, x -20..2, z -16..-9, door x -6..-4.4): rows of grey industrial
  metal shelving with boxes, carts and debris (reference image 3), green EXIT sign over an emergency
  door in the west wall x = -20 at z ≈ -13. Dim, red emergency light.
- **Break room** (zone `break_room`, x 2..10, z -16..-9, door x 5..6.2): lockers, table, vending
  machine, time clock.
- **Manager's office** (zone `office`, x 10..16, z -16..-9, door x 12..13.2): desk, CRT monitor, intercom
  mic. The manager NPC (blue work shirt, reference image 3) stays here.
- **Janitor closet** (zone `janitor`, x 16..20, z -16..-9, door x 17.5..18.7): mop, bucket, sink.
- Partition walls between rooms at x = 2, 10, 16 (z -16..-9).

**Spawns:** player in the break room by the time clock (6, 0, -12.5) facing the door; coworkers in
the break room/hallway; monster in the far storage corner (-18, 0, -15).

## 8. Art direction (GDD §6 + reference pictures)

- Low-poly, slightly pixelated textures (Lethal Company style). Textures small (32–256 px), sampled
  **nearest**. No photorealism, no heavy detail, no gore, no cartoonish monster.
- Palette: Midnight Charcoal `#171B1A` (dark interiors), Industrial Orange `#E87932` (uniforms),
  Faded Olive `#626D58` (shelves/storage/equipment), Fluorescent Cream `#D8D3A8` (lights, signs,
  checkout), Emergency Red `#B93B32` (alarms, exits, danger), Concrete Gray `#444A48` (floors, metal,
  walls).
- Lighting: dim fluorescent ceiling fixtures with occasional flicker → alternating bright and dark
  pools; emergency red light in some areas; storage and back halls barely lit; wet, reflective floor tile.
- Characters: simple silhouettes. Employee = bright orange uniform + cap, dark gloves, black boots, small
  badge, small per-person differences. Monster (reference image 1) = tall, thin, grinning stitched rabbit
  creature in a torn orange uniform with a badge, long arms and claws. Manager = blue work shirt, badge.
- Screen: CRT-style framing (reference image 1): vignette, rounded dark corners, faint scanlines/grain,
  3D rendered at half resolution with nearest upscaling.
- HUD (reference images 2/3): white pixel/terminal font, red HEALTH bar top-left with item slots below
  (flashlight, held tool), minimap top-right. **No ammo counter.**
