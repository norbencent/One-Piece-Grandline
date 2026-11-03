extends Node
## Offline JSON save system (autoload: SaveManager). Never touches the network.
##
## Layout (user://saves/):
##   slot_0.json      autosave slot
##   slot_1..3.json   manual slots
##   slot_N.bak.json  previous good save of that slot (automatic backup)
##
## File envelope:
##   { magic, version, saved_at, saved_at_unix, meta{...}, checksum, payload }
## "payload" is the game state serialized as a JSON *string*; "checksum" is its SHA-256.
## Keeping the payload as a string makes the checksum exact (JSON round-trips turn ints into floats).
##
## Write path is crash-safe: write .tmp -> re-read & verify -> current file becomes .bak -> .tmp becomes current.
## Read path: if the main file fails validation, the .bak is used and restored automatically.

const SAVE_DIR := "user://saves"
const SAVE_MAGIC := "NEONTIDES"
const SAVE_VERSION := 1
const AUTOSAVE_SLOT := 0
const MAX_MANUAL_SLOTS := 3

## Overridable so the self-test can work in a scratch directory.
var save_dir := SAVE_DIR
var _autosave_timer: Timer


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(save_dir)
	_autosave_timer = Timer.new()
	_autosave_timer.name = "AutosaveTimer"
	_autosave_timer.process_callback = Timer.TIMER_PROCESS_IDLE
	_autosave_timer.timeout.connect(_on_autosave_timeout)
	add_child(_autosave_timer)
	_refresh_autosave_timer()
	EventBus.settings_changed.connect(func(key: String, _v: Variant) -> void:
		if key.begins_with("gameplay/autosave"):
			_refresh_autosave_timer())
	EventBus.settings_reloaded.connect(_refresh_autosave_timer)


# --- Paths -------------------------------------------------------------------

func is_valid_slot(slot: int) -> bool:
	return slot >= AUTOSAVE_SLOT and slot <= MAX_MANUAL_SLOTS


func slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [save_dir, slot]


func backup_path(slot: int) -> String:
	return "%s/slot_%d.bak.json" % [save_dir, slot]


func _tmp_path(slot: int) -> String:
	return "%s/slot_%d.tmp" % [save_dir, slot]


func has_save(slot: int) -> bool:
	return is_valid_slot(slot) and (FileAccess.file_exists(slot_path(slot)) or FileAccess.file_exists(backup_path(slot)))


# --- Save --------------------------------------------------------------------

func save_game(slot: int, data: Dictionary, meta: Dictionary = {}) -> bool:
	if not is_valid_slot(slot):
		return _save_fail(slot, "invalid slot %d" % slot)
	DirAccess.make_dir_recursive_absolute(save_dir)
	var payload := JSON.stringify(data)
	var envelope := {
		"magic": SAVE_MAGIC,
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"saved_at_unix": Time.get_unix_time_from_system(),
		"meta": meta,
		"checksum": payload.sha256_text(),
		"payload": payload,
	}
	var tmp := _tmp_path(slot)
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return _save_fail(slot, "cannot write temp file (%s)" % error_string(FileAccess.get_open_error()))
	f.store_string(JSON.stringify(envelope, "\t"))
	f.close()

	var verify := _read_envelope(tmp)
	if not verify["ok"]:
		DirAccess.remove_absolute(tmp)
		return _save_fail(slot, "verification failed: %s" % verify["error"])

	var main := slot_path(slot)
	var bak := backup_path(slot)
	if FileAccess.file_exists(main):
		# Only rotate a *valid* main file into the backup, so a bad file never overwrites a good backup.
		if _read_envelope(main)["ok"]:
			if FileAccess.file_exists(bak):
				DirAccess.remove_absolute(bak)
			DirAccess.rename_absolute(main, bak)
		else:
			DirAccess.remove_absolute(main)
	var err := DirAccess.rename_absolute(tmp, main)
	if err != OK:
		return _save_fail(slot, "cannot finalize save (%s)" % error_string(err))
	EventBus.game_saved.emit(slot)
	return true


func _save_fail(slot: int, reason: String) -> bool:
	push_error("Save slot %d failed: %s" % [slot, reason])
	EventBus.save_failed.emit(slot, reason)
	return false


# --- Load --------------------------------------------------------------------

## Returns { ok: bool, data: Dictionary, meta: Dictionary, from_backup: bool, error: String }.
func load_game(slot: int) -> Dictionary:
	var result := {"ok": false, "data": {}, "meta": {}, "from_backup": false, "error": ""}
	if not is_valid_slot(slot):
		result["error"] = "invalid slot %d" % slot
		return result
	var main := _read_envelope(slot_path(slot))
	if main["ok"]:
		result["ok"] = true
		result["data"] = main["data"]
		result["meta"] = main["envelope"].get("meta", {})
		return result

	var bak := _read_envelope(backup_path(slot))
	if bak["ok"]:
		push_warning("Save slot %d main file invalid (%s); restored backup." % [slot, main["error"]])
		DirAccess.copy_absolute(backup_path(slot), slot_path(slot))
		EventBus.backup_restored.emit(slot)
		result["ok"] = true
		result["from_backup"] = true
		result["data"] = bak["data"]
		result["meta"] = bak["envelope"].get("meta", {})
		return result

	result["error"] = "main: %s; backup: %s" % [main["error"], bak["error"]]
	return result


func _read_envelope(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _invalid("missing")
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return _invalid("empty or unreadable")
	var json := JSON.new()
	if json.parse(text) != OK:
		return _invalid("malformed JSON (line %d)" % json.get_error_line())
	if typeof(json.data) != TYPE_DICTIONARY:
		return _invalid("not an object")
	var env: Dictionary = json.data
	if str(env.get("magic", "")) != SAVE_MAGIC:
		return _invalid("bad magic")
	var version := int(env.get("version", 0))
	if version < 1 or version > SAVE_VERSION:
		return _invalid("unsupported version %d" % version)
	var payload: Variant = env.get("payload")
	if typeof(payload) != TYPE_STRING:
		return _invalid("missing payload")
	if (payload as String).sha256_text() != str(env.get("checksum", "")):
		return _invalid("checksum mismatch")
	var inner := JSON.new()
	if inner.parse(payload) != OK or typeof(inner.data) != TYPE_DICTIONARY:
		return _invalid("payload corrupt")
	return {"ok": true, "error": "", "envelope": env, "data": _migrate(inner.data, version)}


func _invalid(reason: String) -> Dictionary:
	return {"ok": false, "error": reason, "envelope": {}, "data": {}}


## Upgrades older save data to SAVE_VERSION. Add a branch per version bump.
func _migrate(data: Dictionary, from_version: int) -> Dictionary:
	var d := data
	if from_version < 1:
		pass # No pre-1 format exists.
	return d


# --- Slot management ---------------------------------------------------------

func delete_slot(slot: int) -> void:
	if not is_valid_slot(slot):
		return
	for p in [slot_path(slot), backup_path(slot), _tmp_path(slot)]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


## One entry per slot: { slot, exists, valid, is_autosave, saved_at, saved_at_unix, meta }.
func list_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for slot in range(AUTOSAVE_SLOT, MAX_MANUAL_SLOTS + 1):
		var info := {"slot": slot, "exists": false, "valid": false, "is_autosave": slot == AUTOSAVE_SLOT,
			"saved_at": "", "saved_at_unix": 0.0, "meta": {}}
		var path := slot_path(slot)
		if not FileAccess.file_exists(path) and FileAccess.file_exists(backup_path(slot)):
			path = backup_path(slot)
		if FileAccess.file_exists(path):
			info["exists"] = true
			var env := _read_envelope(path)
			if env["ok"]:
				var e: Dictionary = env["envelope"]
				info["valid"] = true
				info["saved_at"] = str(e.get("saved_at", ""))
				info["saved_at_unix"] = float(e.get("saved_at_unix", 0.0))
				info["meta"] = e.get("meta", {})
		out.append(info)
	return out


## The most recently written valid slot (for "Continue"), or -1.
func get_most_recent_slot() -> int:
	var best := -1
	var best_time := -1.0
	for info in list_slots():
		if info["valid"] and float(info["saved_at_unix"]) > best_time:
			best_time = float(info["saved_at_unix"])
			best = int(info["slot"])
	return best


# --- Autosave ----------------------------------------------------------------

func _refresh_autosave_timer() -> void:
	if _autosave_timer == null:
		return
	_autosave_timer.stop()
	if bool(Settings.get_value("gameplay", "autosave")):
		_autosave_timer.wait_time = float(Settings.get_value("gameplay", "autosave_interval_sec"))
		_autosave_timer.start()


func _on_autosave_timeout() -> void:
	GameManager.autosave()
