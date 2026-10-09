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

In the Godot editor (4.7.2): open this folder as a project and press Play. From the command
line:

```
~/tools/godot/godot --headless --path . --import   # first run, or after adding assets
~/tools/godot/godot --path .
```

## Build for web / GitHub Pages

The game ships as a static Web export on GitHub Pages (Compatibility renderer, threads off,
since GitHub Pages cannot send the COOP/COEP headers threads would need).

**Build locally:**

```
tools/build_web.sh          # release export -> build/web/
tools/build_web.sh --debug  # debug export
```

**Serve it locally to test in a browser:**

```
tools/serve_web.py          # serves build/web/ at http://127.0.0.1:8060/
```

**Deploy to GitHub Pages:** `.github/workflows/deploy-pages.yml` builds and deploys the Web
export automatically on every push to `main` (or via Actions → Run workflow). One-time repo
setting required before the first deploy: **Settings → Pages → Source: GitHub Actions**.

## Project layout

See `docs/ARCHITECTURE.md` for the full contract: systems and owners, signals, autoload APIs,
physics layers/groups, scene contracts, the store layout, and art direction.
