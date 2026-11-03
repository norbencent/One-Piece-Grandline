extends Node
## Owns the live game state (autoload: GameManager).
## The whole run is one Dictionary so it serializes straight to JSON via SaveManager.
## Derived values (stats) are computed from data + level instead of being saved, so balance
## changes in data/*.json apply to existing saves.

const MAX_LEVEL := 99
const STARTING_GOLD := 100

var state: Dictionary = {}
var active_slot := -1
var _is_active := false


func _process(delta: float) -> void:
	if _is_active:
		state["play_time_sec"] = float(state.get("play_time_sec", 0.0)) + delta


func is_game_active() -> bool:
	return _is_active


# --- New / load / save -------------------------------------------------------

func new_game(character_id: String) -> bool:
	if not DataRegistry.has_entry("characters", character_id):
		push_error("new_game: unknown character '%s'" % character_id)
		return false
	state = _fresh_state(character_id)
	active_slot = -1
	_is_active = true
	EventBus.game_started.emit(character_id)
	EventBus.player_stats_changed.emit()
	return true


func _fresh_state(character_id: String) -> Dictionary:
	var crew := DataRegistry.get_entry("characters", character_id)
	var start_island := ""
	var islands := DataRegistry.get_all("islands")
	if not islands.is_empty():
		start_island = str(islands[0]["id"])
	var skills: Array = crew.get("skills", [])
	return {
		"player": {
			"character_id": character_id,
			"level": 1,
			"exp": 0,
			"hp": int(crew["base_stats"]["hp"]),
			"unlocked_skills": skills.slice(0, 1),
			"skill_levels": {},
			"equipment": {"weapon": "", "armor": "", "accessory": ""},
		},
		"roster": [character_id],
		"gold": STARTING_GOLD,
		"inventory": {"meat_on_bone": 3},
		"quests": {"active": {}, "completed": []},
		"world": {
			"current_island": start_island,
			"visited_islands": [start_island],
			"treasures_collected": [],
		},
		"flags": {},
		"play_time_sec": 0.0,
	}


func to_save_dict() -> Dictionary:
	return state.duplicate(true)


## Loads a dictionary from disk, filling any keys missing from older saves and restoring
## int types lost through JSON. Returns false if the data can't describe a valid game.
func load_from_dict(data: Dictionary) -> bool:
	var player: Variant = data.get("player")
	if typeof(player) != TYPE_DICTIONARY:
		return false
	var character_id := str((player as Dictionary).get("character_id", ""))
	if not DataRegistry.has_entry("characters", character_id):
		push_error("Save references unknown character '%s'" % character_id)
		return false
	var template := _fresh_state(character_id)
	template["inventory"] = {} # dynamic keys: never re-add starter items on load
	state = merge_typed(template, data)
	var inventory: Dictionary = state["inventory"]
	for item_id: Variant in inventory.keys():
		inventory[item_id] = int(inventory[item_id])
	_is_active = true
	EventBus.player_stats_changed.emit()
	return true


func save_to_slot(slot: int) -> bool:
	if not _is_active:
		return false
	var ok := SaveManager.save_game(slot, to_save_dict(), build_save_meta())
	if ok and slot != SaveManager.AUTOSAVE_SLOT:
		active_slot = slot
	return ok


func load_slot(slot: int) -> bool:
	var result := SaveManager.load_game(slot)
	if not result["ok"]:
		push_warning("Load slot %d failed: %s" % [slot, result["error"]])
		return false
	if not load_from_dict(result["data"]):
		return false
	active_slot = slot
	EventBus.game_loaded.emit(slot)
	return true


func autosave() -> bool:
	if not _is_active or not bool(Settings.get_value("gameplay", "autosave")):
		return false
	return SaveManager.save_game(SaveManager.AUTOSAVE_SLOT, to_save_dict(), build_save_meta())


func end_game() -> void:
	_is_active = false
	state = {}
	active_slot = -1


func build_save_meta() -> Dictionary:
	if not _is_active:
		return {}
	var crew := DataRegistry.get_entry("characters", get_character_id())
	var island := DataRegistry.get_entry("islands", str(state["world"]["current_island"]))
	return {
		"character_id": get_character_id(),
		"character_name": str(crew.get("name", "?")),
		"level": get_level(),
		"island_name": str(island.get("name", "?")),
		"gold": int(state["gold"]),
		"play_time_sec": int(state["play_time_sec"]),
	}


## Snapshot/restore lets diagnostics run without disturbing a real session.
func capture_snapshot() -> Dictionary:
	return {"state": state.duplicate(true), "active": _is_active, "slot": active_slot}


func restore_snapshot(snap: Dictionary) -> void:
	state = (snap["state"] as Dictionary).duplicate(true)
	_is_active = bool(snap["active"])
	active_slot = int(snap["slot"])


# --- Progression helpers -----------------------------------------------------

func get_character_id() -> String:
	return str(state.get("player", {}).get("character_id", ""))


func get_level() -> int:
	return int(state.get("player", {}).get("level", 1))


static func exp_to_next(level: int) -> int:
	return int(round(40.0 * pow(level, 1.6))) + 60


## Base stats + growth * (level - 1). Equipment bonuses are layered on in Phase 6.
func get_player_stats() -> Dictionary:
	var crew := DataRegistry.get_entry("characters", get_character_id())
	if crew.is_empty():
		return {}
	var base: Dictionary = crew["base_stats"]
	var growth: Dictionary = crew["growth"]
	var lv := get_level() - 1
	var out := {}
	for stat: String in base:
		var v := float(base[stat]) + float(growth.get(stat, 0.0)) * lv
		out[stat] = v if stat == "crit_chance" else float(round(v))
	return out


## Adds EXP and handles multi-level-ups. Returns the number of levels gained.
func add_exp(amount: int) -> int:
	if not _is_active or amount <= 0:
		return 0
	var player: Dictionary = state["player"]
	var gained := 0
	player["exp"] = int(player["exp"]) + amount
	while int(player["level"]) < MAX_LEVEL and int(player["exp"]) >= exp_to_next(int(player["level"])):
		player["exp"] = int(player["exp"]) - exp_to_next(int(player["level"]))
		player["level"] = int(player["level"]) + 1
		gained += 1
	if gained > 0:
		player["hp"] = int(get_player_stats()["hp"])
		EventBus.player_leveled_up.emit(int(player["level"]))
	EventBus.player_stats_changed.emit()
	return gained


func add_gold(amount: int) -> int:
	state["gold"] = maxi(0, int(state.get("gold", 0)) + amount)
	EventBus.gold_changed.emit(int(state["gold"]))
	return int(state["gold"])


# --- Utilities ---------------------------------------------------------------

## Deep-merges `loaded` onto `template`: keeps loaded values whose type matches the template,
## restores ints from JSON floats, fills missing keys, and preserves extra loaded keys.
static func merge_typed(template: Variant, loaded: Variant) -> Variant:
	var loaded_is_num := typeof(loaded) == TYPE_INT or typeof(loaded) == TYPE_FLOAT
	match typeof(template):
		TYPE_DICTIONARY:
			if typeof(loaded) != TYPE_DICTIONARY:
				return (template as Dictionary).duplicate(true)
			var src: Dictionary = loaded
			var out: Dictionary = src.duplicate(true)
			for key: Variant in template:
				out[key] = merge_typed(template[key], src.get(key))
			return out
		TYPE_ARRAY:
			return (loaded as Array).duplicate(true) if typeof(loaded) == TYPE_ARRAY else (template as Array).duplicate(true)
		TYPE_INT:
			return int(loaded) if loaded_is_num else template
		TYPE_FLOAT:
			return float(loaded) if loaded_is_num else template
		TYPE_BOOL, TYPE_STRING:
			return loaded if typeof(loaded) == typeof(template) else template
	return template if loaded == null else loaded
