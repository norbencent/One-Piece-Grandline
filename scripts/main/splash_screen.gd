extends Control
## SplashScreen.tscn — first scene. Animates the title in, then advances on tap or after a delay.
## Phase 1 advances to BootCheck (system diagnostics); Phase 2 switches NEXT_SCENE to MainMenu.

const NEXT_SCENE := "res://scenes/main/BootCheck.tscn"
const AUTO_ADVANCE_SEC := 4.0

@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _tagline: Label = %Tagline
@onready var _tap_label: Label = %TapLabel
@onready var _version: Label = %VersionLabel

var _leaving := false
var _ready_for_input := false


func _ready() -> void:
	_title.label_settings = NeonTheme.title_settings(44, NeonTheme.TEXT, NeonTheme.NEON.darkened(0.2))
	_subtitle.label_settings = NeonTheme.title_settings(18, NeonTheme.GOLD, NeonTheme.RED.darkened(0.4))
	_tagline.add_theme_color_override("font_color", NeonTheme.TEXT_DIM)
	_tap_label.add_theme_color_override("font_color", NeonTheme.NEON)
	_version.add_theme_color_override("font_color", NeonTheme.TEXT_DIM)
	_version.text = "v%s  //  OFFLINE" % ProjectSettings.get_setting("application/config/version", "0.0.0")

	for n: CanvasItem in [_title, _subtitle, _tagline, _tap_label]:
		n.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(0.2)
	tw.tween_property(_title, "modulate:a", 1.0, 0.6)
	tw.tween_property(_subtitle, "modulate:a", 1.0, 0.4)
	tw.tween_property(_tagline, "modulate:a", 1.0, 0.4)
	tw.tween_callback(_on_intro_done)
	AudioManager.play_ui("splash_chime")
	get_tree().create_timer(AUTO_ADVANCE_SEC).timeout.connect(_advance)


func _on_intro_done() -> void:
	_ready_for_input = true
	var blink := create_tween().set_loops()
	blink.tween_property(_tap_label, "modulate:a", 1.0, 0.5)
	blink.tween_property(_tap_label, "modulate:a", 0.25, 0.5)


func _unhandled_input(event: InputEvent) -> void:
	if not _ready_for_input:
		return
	var tapped: bool = (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventMouseButton and event.pressed) \
		or event.is_action_pressed("ui_accept")
	if tapped:
		get_viewport().set_input_as_handled()
		_advance()


func _advance() -> void:
	if _leaving or not is_inside_tree():
		return
	_leaving = true
	AudioManager.play_ui("ui_confirm")
	SceneManager.change_scene(NEXT_SCENE)
