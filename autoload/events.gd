extends Node
## Global signal bus. Systems emit and connect here instead of holding
## references to each other. Keep this list in sync with docs/ARCHITECTURE.md.

# --- Night flow -------------------------------------------------------------
signal night_started
signal hour_changed(hour: int)                ## 0 = 12 AM ... 6 = 6 AM
signal night_ended(result: StringName)        ## &"win", &"fired" or &"dead"

# --- Player -----------------------------------------------------------------
signal player_damaged(amount: float, health_left: float)
signal player_died
signal player_hid(spot: Node3D)
signal player_unhid(spot: Node3D)
signal stamina_changed(value: float, max_value: float)
signal held_tool_changed(tool_id: StringName) ## &"" when empty-handed
signal flashlight_toggled(on: bool)
signal interaction_prompt_changed(text: String) ## "" hides the prompt
signal interaction_progress(fraction: float)    ## < 0 hides the hold bar

# --- Tasks (Store Environment) ---------------------------------------------
signal task_added(task: TaskData)
signal task_completed(task: TaskData, by: Node)
signal task_failed(task: TaskData)
signal tasks_changed                           ## checklist should refresh

# --- Store Manager -----------------------------------------------------------
## Store-wide PA. Everyone hears it, including the monster (GDD seam 1).
signal intercom_announced(message: String, zone: StringName)
## Private radio to the player. `is_mimic` is the hidden truth: never show it in UI.
signal walkie_message(speaker: String, message: String, origin: Vector3, is_mimic: bool)

# --- Monster ----------------------------------------------------------------
signal monster_state_changed(state: StringName)
signal monster_sighted                         ## monster entered the player's view
signal chase_started
signal chase_ended
signal coworker_missing(coworker_name: String)

# --- Misc -------------------------------------------------------------------
signal subtitle(text: String, duration: float)
