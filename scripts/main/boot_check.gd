extends Control
## BootCheck.tscn — Phase 1 in-app diagnostics. Runs SystemCheck on the actual device
## (so the save system, storage and audio are verified on real Android hardware) and lists results.

const TITLE_SCENE := "res://scenes/main/SplashScreen.tscn"
const GALLERY_SCENE := "res://scenes/debug/AssetGallery.tscn"

@onready var _header: Label = %Header
@onready var _info: Label = %Info
@onready var _summary: Label = %Summary
@onready var _results: VBoxContainer = %Results
@onready var _rerun: Button = %RerunButton
@onready var _title_button: Button = %TitleButton
@onready var _gallery_button: Button = %GalleryButton


func _ready() -> void:
	_header.label_settings = NeonTheme.title_settings(16, NeonTheme.NEON, NeonTheme.NAVY)
	_info.add_theme_color_override("font_color", NeonTheme.TEXT_DIM)
	_rerun.pressed.connect(_on_rerun)
	_title_button.pressed.connect(_go_title)
	_gallery_button.pressed.connect(func() -> void:
		AudioManager.play_ui("ui_confirm")
		SceneManager.change_scene(GALLERY_SCENE))
	Platform.push_back_handler(_go_title)
	_info.text = "%s  |  %s  |  window %s  |  user:// %s" % [
		OS.get_name(),
		str(ProjectSettings.get_setting("rendering/renderer/rendering_method")),
		str(DisplayServer.window_get_size()),
		"OK" if DirAccess.dir_exists_absolute("user://") else "MISSING",
	]
	_rerun.grab_focus()
	_run_checks()


func _exit_tree() -> void:
	Platform.pop_back_handler(_go_title)


func _run_checks() -> void:
	for child in _results.get_children():
		child.queue_free()
	var check := SystemCheck.new()
	var results := check.run(get_tree())
	for r in results:
		_results.add_child(_make_row(r))
	var all_ok := check.all_passed()
	_summary.text = "%d / %d SYSTEMS ONLINE" % [check.passed(), results.size()]
	_summary.add_theme_color_override("font_color", NeonTheme.GOOD if all_ok else NeonTheme.RED)
	AudioManager.play_ui("ui_confirm" if all_ok else "ui_error")


func _make_row(r: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var tag := Label.new()
	tag.text = "[ OK ]" if r["ok"] else "[FAIL]"
	tag.custom_minimum_size.x = 44
	tag.add_theme_color_override("font_color", NeonTheme.GOOD if r["ok"] else NeonTheme.RED)
	var name_label := Label.new()
	name_label.text = str(r["name"])
	name_label.custom_minimum_size.x = 190
	var detail := Label.new()
	detail.text = str(r["detail"])
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.clip_text = true
	detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	detail.add_theme_color_override("font_color", NeonTheme.TEXT_DIM)
	for l: Label in [tag, name_label, detail]:
		l.add_theme_font_size_override("font_size", 10)
		row.add_child(l)
	return row


func _on_rerun() -> void:
	AudioManager.play_ui("ui_move")
	_run_checks()


func _go_title() -> void:
	AudioManager.play_ui("ui_back")
	SceneManager.change_scene(TITLE_SCENE)
