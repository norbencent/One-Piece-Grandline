extends CanvasLayer
## Scene transitions with fade + background loading (autoload: SceneManager).
## Also owns the global UI theme and the optional FPS overlay.

const FADE_COLOR := Color(0.01, 0.02, 0.06, 1.0)

var _fade: ColorRect
var _fps_label: Label
var _busy := false


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.theme = NeonTheme.build()

	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = FADE_COLOR
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	add_child(_fade)

	_fps_label = Label.new()
	_fps_label.name = "Fps"
	_fps_label.position = Vector2(4, 2)
	_fps_label.add_theme_font_size_override("font_size", 9)
	_fps_label.add_theme_color_override("font_color", NeonTheme.GOOD)
	add_child(_fps_label)
	_update_fps_visibility()
	EventBus.settings_changed.connect(func(key: String, _v: Variant) -> void:
		if key == "display/show_fps":
			_update_fps_visibility())
	EventBus.settings_reloaded.connect(_update_fps_visibility)


func _process(_delta: float) -> void:
	if _fps_label.visible:
		_fps_label.text = "%d FPS" % Engine.get_frames_per_second()


func _update_fps_visibility() -> void:
	_fps_label.visible = bool(Settings.get_value("display", "show_fps"))
	set_process(_fps_label.visible)


func is_busy() -> bool:
	return _busy


## Fades out, loads `path` on a background thread, swaps scenes, fades in.
func change_scene(path: String, fade_time := 0.3) -> bool:
	if _busy:
		return false
	if not ResourceLoader.exists(path):
		push_error("SceneManager: scene not found %s" % path)
		return false
	_busy = true
	EventBus.scene_change_started.emit(path)
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	ResourceLoader.load_threaded_request(path)

	var out := create_tween()
	out.tween_property(_fade, "modulate:a", 1.0, fade_time)
	await out.finished

	while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
	var packed := ResourceLoader.load_threaded_get(path) as PackedScene
	if packed == null:
		push_error("SceneManager: failed to load %s" % path)
	else:
		get_tree().paused = false
		get_tree().change_scene_to_packed(packed)
		await get_tree().process_frame

	var back := create_tween()
	back.tween_property(_fade, "modulate:a", 0.0, fade_time)
	await back.finished
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false
	EventBus.scene_change_finished.emit(path)
	return packed != null
