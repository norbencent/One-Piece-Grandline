extends Node
## Global signal hub (autoload: EventBus).
## Systems emit and listen here instead of holding direct references to each other.

# --- Game lifecycle ---
signal game_started(character_id: String)
signal game_loaded(slot: int)
signal game_saved(slot: int)
signal save_failed(slot: int, reason: String)
signal backup_restored(slot: int)

# --- Settings ---
signal settings_changed(key: String, value: Variant)
signal settings_reloaded

# --- Scenes / navigation ---
signal scene_change_started(path: String)
signal scene_change_finished(path: String)
signal back_requested
signal pause_requested

# --- Player / progression ---
signal player_stats_changed
signal player_leveled_up(new_level: int)
signal gold_changed(total: int)

# --- UI ---
signal toast_requested(text: String)
