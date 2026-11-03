extends Node
## Persists and applies user settings to user://settings.cfg (autoload: Settings).
## Every value is sanitized against DEFAULTS, so a hand-edited or corrupted file can't crash the game.

const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_VERSION := 1
const ALLOWED_FPS: Array[int] = [30, 60]
const DIFFICULTIES: Array[String] = ["easy", "normal", "hard"]

const DEFAULTS := {
	"audio": {
		"master_volume": 1.0,
		"music_volume": 0.8,
		"sfx_volume": 0.9,
		"ui_volume": 0.8,
	},
	"display": {
		"target_fps": 60,
		"vsync": true,
		"show_fps": false,
		"screen_shake": true,
	},
	"controls": {
		"control_scale": 1.0,
		"control_opacity": 0.75,
		"left_handed": false,
		"vibration": true,
		"button_offsets": {},
	},
	"gameplay": {
		"autosave": true,
		"autosave_interval_sec": 180,
		"difficulty": "normal",
	},
}

## Overridable so the self-test can work on a scratch file.
var settings_path := SETTINGS_PATH
var _cfg := ConfigFile.new()


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	_cfg = ConfigFile.new()
	var err := _cfg.load(settings_path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("Settings file unreadable (%s); using defaults." % error_string(err))
		_cfg = ConfigFile.new()
	for section: String in DEFAULTS:
		var defaults: Dictionary = DEFAULTS[section]
		for key: String in defaults:
			var value: Variant = _cfg.get_value(section, key, defaults[key])
			_cfg.set_value(section, key, _sanitize(section, key, value))
	_cfg.set_value("meta", "version", SETTINGS_VERSION)
	apply_display()
	EventBus.settings_reloaded.emit()


func save_settings() -> bool:
	var err := _cfg.save(settings_path)
	if err != OK:
		push_error("Could not save settings: %s" % error_string(err))
		return false
	return true


func get_value(section: String, key: String) -> Variant:
	if not DEFAULTS.has(section) or not (DEFAULTS[section] as Dictionary).has(key):
		push_error("Unknown setting %s/%s" % [section, key])
		return null
	return _cfg.get_value(section, key, DEFAULTS[section][key])


func set_value(section: String, key: String, value: Variant, persist := true) -> void:
	if not DEFAULTS.has(section) or not (DEFAULTS[section] as Dictionary).has(key):
		push_error("Unknown setting %s/%s" % [section, key])
		return
	var clean: Variant = _sanitize(section, key, value)
	_cfg.set_value(section, key, clean)
	if section == "display":
		apply_display()
	EventBus.settings_changed.emit("%s/%s" % [section, key], clean)
	if persist:
		save_settings()


func reset_to_defaults() -> void:
	_cfg = ConfigFile.new()
	for section: String in DEFAULTS:
		var defaults: Dictionary = DEFAULTS[section]
		for key: String in defaults:
			_cfg.set_value(section, key, _copy(defaults[key]))
	_cfg.set_value("meta", "version", SETTINGS_VERSION)
	save_settings()
	apply_display()
	EventBus.settings_reloaded.emit()


func apply_display() -> void:
	Engine.max_fps = int(get_value("display", "target_fps"))
	var vsync: bool = get_value("display", "vsync")
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


func _sanitize(section: String, key: String, value: Variant) -> Variant:
	var default: Variant = DEFAULTS[section][key]
	var is_number := typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
	match typeof(default):
		TYPE_FLOAT:
			if not is_number:
				return default
			var f := float(value)
			match key:
				"control_scale":
					return clampf(f, 0.6, 1.6)
				"control_opacity":
					return clampf(f, 0.2, 1.0)
				_:
					return clampf(f, 0.0, 1.0)
		TYPE_INT:
			if not is_number:
				return default
			var i := int(value)
			match key:
				"target_fps":
					return i if ALLOWED_FPS.has(i) else default
				"autosave_interval_sec":
					return clampi(i, 30, 1800)
			return i
		TYPE_BOOL:
			return value if typeof(value) == TYPE_BOOL else default
		TYPE_STRING:
			if typeof(value) != TYPE_STRING:
				return default
			if key == "difficulty" and not DIFFICULTIES.has(value):
				return default
			return value
		TYPE_DICTIONARY:
			return (value as Dictionary).duplicate(true) if typeof(value) == TYPE_DICTIONARY else _copy(default)
	return value


func _copy(v: Variant) -> Variant:
	if typeof(v) == TYPE_DICTIONARY:
		return (v as Dictionary).duplicate(true)
	if typeof(v) == TYPE_ARRAY:
		return (v as Array).duplicate(true)
	return v
