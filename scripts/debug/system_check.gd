class_name SystemCheck
extends RefCounted
## Phase 1 self-test of every foundation system. Used by BootCheck.tscn (in-app, runs on device)
## and tests/run_tests.gd (headless CI). Works in scratch files/dirs and restores all global state.

const AUTOLOADS: Array[String] = ["EventBus", "Settings", "AudioManager", "DataRegistry",
	"SaveManager", "GameManager", "SceneManager", "InputConfig", "Platform"]
const SCRATCH_DIR := "user://selftest"
const EXPECTED_CHARACTERS := 10
const EXPECTED_SEAS := 3
const EXPECTED_ISLANDS := 25

var results: Array[Dictionary] = []


func run(tree: SceneTree) -> Array[Dictionary]:
	results.clear()
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	_check_autoloads(tree)
	_check_display()
	_check_input()
	_check_data()
	_check_audio()
	_check_settings()
	_check_progression()
	_check_save_system()
	_cleanup_scratch()
	return results


func passed() -> int:
	return results.filter(func(r: Dictionary) -> bool: return r["ok"]).size()


func all_passed() -> bool:
	return passed() == results.size()


func _record(check_name: String, ok: bool, detail := "") -> void:
	results.append({"name": check_name, "ok": ok, "detail": detail})


# --- Checks ------------------------------------------------------------------

func _check_autoloads(tree: SceneTree) -> void:
	var missing: Array[String] = []
	for n in AUTOLOADS:
		if tree.root.get_node_or_null(n) == null:
			missing.append(n)
	_record("Autoload managers", missing.is_empty(),
		"%d/%d loaded" % [AUTOLOADS.size() - missing.size(), AUTOLOADS.size()] if missing.is_empty() else "missing: %s" % ", ".join(missing))


func _check_display() -> void:
	var w := int(ProjectSettings.get_setting("display/window/size/viewport_width"))
	var h := int(ProjectSettings.get_setting("display/window/size/viewport_height"))
	var filter := int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter"))
	var orient := int(ProjectSettings.get_setting("display/window/handheld/orientation"))
	var landscape := orient == DisplayServer.SCREEN_LANDSCAPE or orient == DisplayServer.SCREEN_SENSOR_LANDSCAPE \
		or orient == DisplayServer.SCREEN_REVERSE_LANDSCAPE
	_record("Pixel-art display config", w == 640 and h == 360 and filter == 0,
		"%dx%d, nearest filter=%s" % [w, h, filter == 0])
	_record("Landscape orientation", landscape, "orientation id %d" % orient)


func _check_input() -> void:
	var missing: Array[String] = []
	for action in InputConfig.all_actions():
		if not InputMap.has_action(action) or InputMap.action_get_events(action).is_empty():
			missing.append(action)
	_record("Input actions", missing.is_empty(),
		"%d actions bound" % InputConfig.all_actions().size() if missing.is_empty() else "unbound: %s" % ", ".join(missing))


func _check_data() -> void:
	var ok := DataRegistry.errors.is_empty()
	_record("Data files valid", ok, "no errors" if ok else "; ".join(DataRegistry.errors))
	var c := DataRegistry.count("characters")
	var s := DataRegistry.count("seas")
	var i := DataRegistry.count("islands")
	_record("Crew roster", c == EXPECTED_CHARACTERS, "%d playable characters" % c)
	_record("World data", s == EXPECTED_SEAS and i == EXPECTED_ISLANDS, "%d seas, %d islands" % [s, i])
	var orphans: Array[String] = []
	for island in DataRegistry.get_all("islands"):
		if not DataRegistry.has_entry("seas", str(island["sea"])):
			orphans.append(str(island["id"]))
	_record("Island -> sea links", orphans.is_empty(), "all linked" if orphans.is_empty() else ", ".join(orphans))
	_record("Item catalog", DataRegistry.count("items") > 0, "%d items" % DataRegistry.count("items"))


func _check_audio() -> void:
	var buses_ok := AudioManager.has_bus("Music") and AudioManager.has_bus("SFX") and AudioManager.has_bus("UI")
	_record("Audio buses", buses_ok, "Music / SFX / UI")
	var bad: Array[String] = []
	for id: String in AudioManager.SYNTH_SFX:
		var s := AudioManager.get_sfx_stream(id) as AudioStreamWAV
		if s == null or s.data.size() == 0:
			bad.append(id)
	_record("Offline SFX library", bad.is_empty(),
		"%d sounds generated locally" % AudioManager.SYNTH_SFX.size() if bad.is_empty() else "failed: %s" % ", ".join(bad))


func _check_settings() -> void:
	var original_path: String = Settings.settings_path
	var scratch := SCRATCH_DIR + "/settings.cfg"
	if FileAccess.file_exists(scratch):
		DirAccess.remove_absolute(scratch)
	Settings.settings_path = scratch
	Settings.load_settings()

	Settings.set_value("audio", "music_volume", 0.33)
	Settings.set_value("display", "target_fps", 144) # not allowed -> default 60
	Settings.set_value("controls", "control_scale", 9.0) # clamped -> 1.6
	Settings.set_value("display", "target_fps", 30)
	var disk := ConfigFile.new()
	var loaded := disk.load(scratch) == OK
	var persisted := loaded and is_equal_approx(float(disk.get_value("audio", "music_volume", -1.0)), 0.33)
	var clamped := is_equal_approx(float(Settings.get_value("controls", "control_scale")), 1.6)
	var fps_applied := Engine.max_fps == 30
	Settings.set_value("display", "target_fps", 144)
	var fps_rejected := int(Settings.get_value("display", "target_fps")) == 60

	# A corrupted settings file must fall back to defaults, not crash.
	var f := FileAccess.open(scratch, FileAccess.WRITE)
	f.store_string("[audio]\nmusic_volume=\"loud\"\n%%%garbage")
	f.close()
	Settings.load_settings()
	var recovered := is_equal_approx(float(Settings.get_value("audio", "music_volume")), 0.8)

	Settings.settings_path = original_path
	Settings.load_settings()
	_record("Settings persist to disk", persisted, scratch)
	_record("Settings validation", clamped and fps_rejected, "clamp + whitelist")
	_record("FPS cap applies (30/60)", fps_applied, "Engine.max_fps restored to %d" % Engine.max_fps)
	_record("Corrupt settings recovery", recovered, "defaults restored")


func _check_progression() -> void:
	var snap := GameManager.capture_snapshot()
	var monotonic := true
	for lv in range(1, 50):
		if GameManager.exp_to_next(lv + 1) <= GameManager.exp_to_next(lv):
			monotonic = false
	var started := GameManager.new_game("rook")
	var hp_before := float(GameManager.get_player_stats().get("hp", 0))
	var gained := GameManager.add_exp(GameManager.exp_to_next(1) + GameManager.exp_to_next(2))
	var hp_after := float(GameManager.get_player_stats().get("hp", 0))
	var rejected := not GameManager.new_game("no_such_pirate")
	GameManager.restore_snapshot(snap)
	_record("EXP curve", monotonic, "Lv1->2 needs %d EXP" % GameManager.exp_to_next(1))
	_record("Level-up & stat growth", started and gained == 2 and hp_after > hp_before,
		"+%d levels, HP %d -> %d" % [gained, hp_before, hp_after])
	_record("Unknown character rejected", rejected)


func _check_save_system() -> void:
	var snap := GameManager.capture_snapshot()
	var original_dir: String = SaveManager.save_dir
	SaveManager.save_dir = SCRATCH_DIR + "/saves"
	for s in range(0, SaveManager.MAX_MANUAL_SLOTS + 1):
		SaveManager.delete_slot(s)

	# Round trip.
	GameManager.new_game("mira")
	GameManager.add_gold(250)
	GameManager.state["inventory"]["meat_on_bone"] = 1
	GameManager.state["flags"]["met_old_sailor"] = true
	var first := GameManager.to_save_dict()
	var saved := GameManager.save_to_slot(1)
	var loaded := GameManager.load_slot(1)
	var same: bool = loaded and _canon(GameManager.to_save_dict()) == _canon(first)
	var types_ok: bool = typeof(GameManager.state["player"]["level"]) == TYPE_INT \
		and typeof(GameManager.state["inventory"]["meat_on_bone"]) == TYPE_INT
	var no_refill: bool = loaded and int(GameManager.state["inventory"]["meat_on_bone"]) == 1
	_record("Save -> load round trip", saved and same, "slot 1, %d bytes" % FileAccess.get_file_as_string(SaveManager.slot_path(1)).length())
	_record("Types restored after JSON", types_ok and no_refill, "ints + inventory intact")

	# Backup rotation + tamper detection: second save makes the first the backup.
	GameManager.add_gold(1000)
	SaveManager.save_game(1, GameManager.to_save_dict(), GameManager.build_save_meta())
	var text := FileAccess.get_file_as_string(SaveManager.slot_path(1))
	var tampered := text.replace("\\\"gold\\\":1350", "\\\"gold\\\":999999")
	var fw := FileAccess.open(SaveManager.slot_path(1), FileAccess.WRITE)
	fw.store_string(tampered)
	fw.close()
	var r := SaveManager.load_game(1)
	var from_backup: bool = r["ok"] and r["from_backup"] and int(r["data"]["gold"]) == 350
	_record("Tamper detection -> backup", tampered != text and from_backup, "checksum mismatch caught, backup gold=%s" % str(r["data"].get("gold", "?")))
	var healed := SaveManager.load_game(1)
	_record("Main file self-heals", healed["ok"] and not healed["from_backup"], "backup copied over bad file")

	# Both files destroyed -> clean failure, no crash.
	for p in [SaveManager.slot_path(1), SaveManager.backup_path(1)]:
		var g := FileAccess.open(p, FileAccess.WRITE)
		g.store_string("{not json")
		g.close()
	var dead := SaveManager.load_game(1)
	_record("Unrecoverable save handled", not dead["ok"] and str(dead["error"]) != "", str(dead["error"]))

	# Future version rejected.
	var future := JSON.stringify({"magic": SaveManager.SAVE_MAGIC, "version": 999, "payload": "{}", "checksum": "{}".sha256_text()})
	var fv := FileAccess.open(SaveManager.slot_path(3), FileAccess.WRITE)
	fv.store_string(future)
	fv.close()
	_record("Unknown save version rejected", not SaveManager.load_game(3)["ok"])

	# Slot validation, autosave, listing and Continue target.
	var invalid_rejected: bool = not SaveManager.save_game(42, {}) and not SaveManager.load_game(-1)["ok"]
	_record("Invalid slots rejected", invalid_rejected)
	var auto_ok: bool = GameManager.autosave() and SaveManager.load_game(SaveManager.AUTOSAVE_SLOT)["ok"]
	_record("Autosave slot", auto_ok, "slot 0")
	GameManager.save_to_slot(2)
	var slots := SaveManager.list_slots()
	var meta: Dictionary = slots[2]["meta"]
	_record("Slot listing + metadata", slots.size() == 4 and slots[2]["valid"] and str(meta.get("character_name", "")) == "Mira Vey",
		"%s Lv%s @ %s" % [meta.get("character_name", "?"), meta.get("level", "?"), meta.get("island_name", "?")])
	var recent := SaveManager.get_most_recent_slot()
	_record("Continue picks newest save", recent == 2 or recent == 0, "slot %d" % recent)

	for s in range(0, SaveManager.MAX_MANUAL_SLOTS + 1):
		SaveManager.delete_slot(s)
	_record("Slot deletion", not SaveManager.has_save(1) and not SaveManager.has_save(2))
	SaveManager.save_dir = original_dir
	GameManager.restore_snapshot(snap)


func _cleanup_scratch() -> void:
	var saves := SCRATCH_DIR + "/saves"
	if DirAccess.dir_exists_absolute(saves):
		for f in DirAccess.get_files_at(saves):
			DirAccess.remove_absolute(saves + "/" + f)
		DirAccess.remove_absolute(saves)
	for f in DirAccess.get_files_at(SCRATCH_DIR):
		DirAccess.remove_absolute(SCRATCH_DIR + "/" + f)
	DirAccess.remove_absolute(SCRATCH_DIR)


## Canonical JSON text, so int/float differences from JSON round trips don't matter.
static func _canon(d: Dictionary) -> String:
	var copy := d.duplicate(true)
	copy.erase("play_time_sec")
	return JSON.stringify(JSON.parse_string(JSON.stringify(copy)), "", true)
