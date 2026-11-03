extends Node
## Headless test runner. Run:
##   godot --headless --path . res://tests/TestRunner.tscn
## Exits with code 0 when everything passes, 1 otherwise.

const REQUIRED_DIRS: Array[String] = [
	"res://assets/characters", "res://assets/audio", "res://assets/fonts",
	"res://scenes/main", "res://scenes/menus", "res://scenes/combat", "res://scenes/ui",
	"res://scripts/managers", "res://scripts/save_system", "res://scripts/android",
	"res://resources/items", "res://data/characters", "res://data/islands", "res://data/items",
]
const SCENES: Array[String] = ["res://scenes/main/SplashScreen.tscn", "res://scenes/main/BootCheck.tscn"]


func _ready() -> void:
	var check := SystemCheck.new()
	var results := check.run(get_tree())
	results.append_array(_project_checks())

	var failed := 0
	print("\n=== Neon Tides :: Phase 1 tests ===")
	for r in results:
		if not r["ok"]:
			failed += 1
		print("%s %-32s %s" % ["[ OK ]" if r["ok"] else "[FAIL]", r["name"], r["detail"]])
	print("=== %d/%d passed ===\n" % [results.size() - failed, results.size()])
	get_tree().quit(0 if failed == 0 else 1)


func _project_checks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var missing: Array[String] = []
	for d in REQUIRED_DIRS:
		if not DirAccess.dir_exists_absolute(d):
			missing.append(d)
	out.append({"name": "Folder architecture", "ok": missing.is_empty(), "detail": ", ".join(missing) if missing else "%d dirs" % REQUIRED_DIRS.size()})

	var bad_scenes: Array[String] = []
	for s in SCENES:
		var ps := load(s) as PackedScene
		if ps == null or not ps.can_instantiate():
			bad_scenes.append(s)
			continue
		var inst := ps.instantiate()
		if inst == null:
			bad_scenes.append(s)
		else:
			inst.free()
	out.append({"name": "Scenes load & instantiate", "ok": bad_scenes.is_empty(), "detail": ", ".join(bad_scenes) if bad_scenes else "%d scenes" % SCENES.size()})

	var preset := ConfigFile.new()
	var has_preset := preset.load("res://export_presets.cfg") == OK
	var internet: bool = has_preset and bool(preset.get_value("preset.0.options", "permissions/internet", true))
	var includes_data: bool = has_preset and str(preset.get_value("preset.0", "include_filter", "")).contains("data/*.json")
	out.append({"name": "Android preset: no INTERNET", "ok": has_preset and not internet, "detail": "permission off" if not internet else "INTERNET enabled!"})
	out.append({"name": "Android preset ships data", "ok": includes_data, "detail": "include_filter has data/*.json"})
	var orient := int(ProjectSettings.get_setting("display/window/handheld/orientation"))
	out.append({"name": "Back button not auto-quit", "ok": not bool(ProjectSettings.get_setting("application/config/quit_on_go_back")), "detail": "handled by Platform (orientation %d)" % orient})
	return out
