# AI night crew

CLOCK IN starts a shift with the player and three autonomous employees: Dale, Rita and
Marcus. The game runs locally in desktop and browser exports; there is no online lobby,
signaling server, WebRTC connection, or deployment configuration.

The six basic tasks are divided at the start of each night. Each coworker receives one
task and the other three are marked YOU. The checklist shows assignments in brackets.
Coworkers navigate to their stations, reserve their tasks, work through the hold time,
then rest or wander. They never take another employee's basic assignment. Manager bonus
tasks remain shared and take priority when workers choose their next job.

The player can complete any task, including one a coworker is already approaching. That
worker notices and releases the task. Coworkers carry their own work supplies, so they do
not consume the player's tools or empty tool racks. They check in over the walkie with
their actual locations, flee the revealed monster, and can be abducted. A missing worker's
unfinished assignment transfers to YOU so the night can still be completed.

All basic work must be done by 6:00 AM to win. NPC completions count toward the same
checklist and shift result as player completions. Pause freezes the whole crew; restarting
creates a fresh crew and a new set of assignments.

Implementation: `scenes/game.gd` spawns the three employees listed in `Catalog.COWORKERS`;
`systems/environment/task_manager.gd` assigns and tracks work;
`systems/coworkers/coworker.gd` handles task choice, navigation, work, radio and danger.

Run the full suite with:

```
"$GODOT" --headless --path . -s res://tests/run_tests.gd
```

Focused checks use `-- --filter=worker_assignments`, `-- --filter=coworker`,
`-- --filter=test_game_scene`, or `-- --filter=test_hud`.
