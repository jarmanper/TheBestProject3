Added by Caleb (cdmilliken)
Anthony's here too

## How to play

- **Move:** W/A/S/D or arrow keys
- **Sprint:** Shift
- **Interact:** E or left mouse button (hold for tasks that need it; a progress bar shows how long)
- **Flashlight:** F or right mouse button
- **Checklist:** Tab
- **Pause:** Escape or P

Work the overnight shift, finish every basic task before 6:00 AM, and stay out of sight of
whichever coworker is actually the monster in disguise.

## Run locally

In the Godot 4.7.2 editor: open this folder as a project and press Play. From the command
line, with `$GODOT` set to your Godot 4.7.2 editor binary (for example
`export GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64`):

```
"$GODOT" --headless --path . --import   # first run, or after adding assets
"$GODOT" --path .
```

## Run the tests

```
"$GODOT" --headless --path . -s res://tests/run_tests.gd                        # everything (~2 min)
"$GODOT" --headless --path . -s res://tests/run_tests.gd -- --filter=manager    # one area
```

A test fails on a failed assertion or on any engine/script error logged while it runs; the
command exits 1 if anything failed. The GitHub Pages workflow runs the same suite before every
deploy. `tests/level/test_night_smoke.gd` plays a whole night in the real store (~100 s).

## Build for web / GitHub Pages

The game ships as a static Web export on GitHub Pages (Compatibility renderer, threads off,
since GitHub Pages cannot send the COOP/COEP headers threads would need).

**Build locally:**

```
tools/build_web.sh          # release export -> build/web/ (uses $GODOT)
tools/build_web.sh --debug  # debug export
```

The export leaves out `tests/`, `tools/`, the `systems/*/sandbox/` scenes and the greybox
generator (`exclude_filter` in `export_presets.cfg`); none of them is loaded by the game.

**Serve it locally to test in a browser:**

```
tools/serve_web.py          # serves build/web/ at http://127.0.0.1:8060/
```

**Deploy to GitHub Pages:** `.github/workflows/deploy-pages.yml` builds and deploys the Web
export automatically on every push to `main` (or via Actions → Run workflow). One-time repo
setting required before the first deploy: **Settings → Pages → Source: GitHub Actions**.

## Working on your system

Each system lives in its own folder (owners from the GDD; full contract in
`docs/ARCHITECTURE.md`). Run the tests for your area after a change.

- **Anthony — Store Manager** (`systems/manager/`): timings and limits are exported tunables on
  `StoreManager` (`store_manager.gd`: welcome delay, first-bonus window, bonus interval, open
  manager-task cap, manager-task time limit, PA filler interval). Every line the manager says —
  welcome, hourly, PA filler, coworker missing, task done/failed — is in `manager_lines.gd`;
  the bonus-task call for each station is its `manager_line` in
  `systems/environment/station_layout.gd`. Tests: `--filter=manager`.
- **Caleb — Store Environment** (`systems/environment/`): the 13 task stations (kind, zone,
  title, tool, hold time, manager line, position) are the table in `station_layout.gd`; after
  editing it, rebuild the store with
  `"$GODOT" --headless --path . -s res://tools/build_store_level.gd` (it regenerates
  `levels/store/store.tscn`; never edit that file by hand). Hiding spots are
  `hiding/hide_locker.tscn`, `hide_boxes.tscn`, `hide_counter.tscn`; tool racks are
  `tools/pickup_*.tscn`; station scenes are `stations/station_*.tscn`.
  Tests: `--filter=environment` and `--filter=test_store_level`.

## Project layout

See `docs/ARCHITECTURE.md` for the full contract: systems and owners, signals, autoload APIs,
physics layers/groups, scene contracts, the store layout, and art direction.
