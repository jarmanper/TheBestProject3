# Night Shift: Store 03

A single-player, first-person survival-horror baseline for Project 3. You are a late-shift supermarket employee completing closing tasks while an orange-uniformed mimic learns where the work will take you.

## Play

Open the project with Godot 4.7 and run `main.tscn` (it is configured as the startup scene).

- `WASD` - move
- `Shift` - sprint (uses stamina)
- `F` - take a tool or complete a task
- `E` - enter/leave a hiding spot
- `Esc` - release/capture the mouse
- `R` - restart after a win or loss

## GitHub Pages

The project includes a Web export preset and [GitHub Pages workflow](.github/workflows/deploy-pages.yml). After pushing to `main`, enable **Settings -> Pages -> Source -> GitHub Actions** in the repository. The workflow exports the game with Godot 4.7.2 and deploys it; GitHub displays the resulting `github.io` URL in the deployment details.

## Baseline systems

- A low-poly, dark supermarket with narrow aisles, flickering fluorescent lights, red emergency lighting, storage, checkout, tools, three hiding spots, and built-in ambient/footstep/intercom/mimic audio.
- A closing-task checklist: lock the register, restock an aisle, clean a spill with a mop, then finish the manager's intercom priority task with a utility key.
- A manager intercom event that promotes the rear-breaker task and immediately redirects the mimic to that work location.
- An unkillable mimic that initially passes as an employee, guarantees a sighting, uses collision-aware routes around shelves, loses sight through aisle obstructions, attacks after sustained close range, and can sprint for only 13 seconds before it slows down.
- No weapons, monster health, multiplayer, or in-game voice chat; those are intentionally outside this first single-player slice.
