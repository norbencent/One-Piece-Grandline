extends Control
## AssetGallery.tscn — live preview of every imported art asset, animated in-engine.
## Cycles animations, island backgrounds and crew skins so the asset packs can be checked on device.

const BACK_SCENE := "res://scenes/main/BootCheck.tscn"
const CREW_ANIMS: Array[String] = ["idle", "walk", "run", "jump", "attack", "special", "hurt", "death", "victory"]
## How enemy/boss sheets (4 rows) follow the selected crew animation.
const ENEMY_FALLBACK := {"run": "walk", "jump": "idle", "special": "attack", "victory": "idle", "death": "death"}
const SCALE := 1.5

@onready var _background: TextureRect = %Background
@onready var _stage: Control = %Stage
@onready var _header: Label = %Header
@onready var _anim_button: Button = %AnimButton
@onready var _bg_button: Button = %BgButton
@onready var _skin_button: Button = %SkinButton
@onready var _back_button: Button = %BackButton

var _anim_index := 0
var _bg_index := 0
var _use_alt := false
var _backgrounds: Array[String] = []
var _crew_sprites: Array[AnimatedSprite2D] = []
var _enemy_sprites: Array[AnimatedSprite2D] = []


func _ready() -> void:
	_header.label_settings = NeonTheme.title_settings(14, NeonTheme.NEON, NeonTheme.NAVY)
	for island in DataRegistry.get_all("islands"):
		var bg := str(island.get("background", ""))
		if bg != "" and not _backgrounds.has(bg):
			_backgrounds.append(bg)
	_build_crew()
	_build_enemies()
	_build_effects()
	_build_ship()
	_anim_button.pressed.connect(_next_anim)
	_bg_button.pressed.connect(_next_background)
	_skin_button.pressed.connect(_toggle_skin)
	_back_button.pressed.connect(_go_back)
	Platform.push_back_handler(_go_back)
	_read_cmdline()
	_apply_background()
	_apply_anim()
	_anim_button.grab_focus()


## Optional: `godot ... -- --anim=attack --bg=2 --alt` opens the gallery in a given state.
func _read_cmdline() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--anim="):
			_anim_index = maxi(0, CREW_ANIMS.find(arg.trim_prefix("--anim=")))
		elif arg.begins_with("--bg="):
			_bg_index = clampi(int(arg.trim_prefix("--bg=")), 0, maxi(0, _backgrounds.size() - 1))
		elif arg == "--alt":
			_toggle_skin()


func _exit_tree() -> void:
	Platform.pop_back_handler(_go_back)


func _make_sprite(frames: SpriteFrames, pos: Vector2, scale_factor := SCALE) -> AnimatedSprite2D:
	var s := AnimatedSprite2D.new()
	s.sprite_frames = frames
	s.centered = true
	s.scale = Vector2(scale_factor, scale_factor)
	s.position = pos
	_stage.add_child(s)
	return s


func _add_caption(text: String, center_x: float, y: float, width := 62.0) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(center_x - width / 2.0, y)
	l.size = Vector2(width, 10)
	l.add_theme_font_size_override("font_size", 8)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 3)
	_stage.add_child(l)


func _build_crew() -> void:
	var crew := DataRegistry.get_all("characters")
	for i in crew.size():
		var x := 33.0 + i * 63.0
		var s := _make_sprite(SpriteSheetLibrary.frames_for_entry(crew[i]), Vector2(x, 112))
		_crew_sprites.append(s)
		_add_caption(str(crew[i]["name"]).get_slice(" ", 0), x, 144)


func _build_enemies() -> void:
	var enemies := DataRegistry.get_all("enemies")
	var x := 36.0
	for e in enemies:
		var is_boss := str(e["tier"]) == "boss"
		var y := 228.0 if is_boss else 240.0
		var s := _make_sprite(SpriteSheetLibrary.frames_for_entry(e), Vector2(x + (24 if is_boss else 0), y))
		_enemy_sprites.append(s)
		_add_caption(str(e["name"]), x + (24 if is_boss else 0), 274, 70)
		x += 112.0 if is_boss else 72.0


func _build_effects() -> void:
	var ids := SpriteSheetLibrary.effect_ids()
	for i in ids.size():
		var x := 300.0 + i * 52.0
		var s := _make_sprite(SpriteSheetLibrary.effect_frames(ids[i]), Vector2(x, 300), 1.25)
		s.play(&"play")
		s.animation_finished.connect(func() -> void: s.play(&"play"))
		_add_caption(ids[i].replace("_", " "), x, 316, 56)


func _build_ship() -> void:
	var ship := Sprite2D.new()
	ship.texture = load("res://assets/ships/pirate_sloop_192x96.png")
	ship.position = Vector2(540, 230)
	_stage.add_child(ship)
	var bob := create_tween().set_loops()
	bob.tween_property(ship, "position:y", 226.0, 0.8).set_trans(Tween.TRANS_SINE)
	bob.tween_property(ship, "position:y", 230.0, 0.8).set_trans(Tween.TRANS_SINE)


func _apply_anim() -> void:
	var anim := CREW_ANIMS[_anim_index]
	for s in _crew_sprites:
		if s.sprite_frames:
			s.play(StringName(anim))
	for s in _enemy_sprites:
		if s.sprite_frames == null:
			continue
		var name := anim if s.sprite_frames.has_animation(anim) else str(ENEMY_FALLBACK.get(anim, "idle"))
		s.play(StringName(name))
	_anim_button.text = "ANIM: %s" % anim.to_upper()
	_update_header()


func _apply_background() -> void:
	if _backgrounds.is_empty():
		return
	_background.texture = load(_backgrounds[_bg_index])
	_update_header()


func _update_header() -> void:
	var bg := _backgrounds[_bg_index].get_file().get_basename() if not _backgrounds.is_empty() else "-"
	_header.text = "ASSET GALLERY  //  %s  //  %s skin" % [bg.replace("_640x360", ""), "alt" if _use_alt else "main"]


func _next_anim() -> void:
	AudioManager.play_ui("ui_move")
	_anim_index = (_anim_index + 1) % CREW_ANIMS.size()
	_apply_anim()


func _next_background() -> void:
	AudioManager.play_ui("ui_move")
	_bg_index = (_bg_index + 1) % maxi(1, _backgrounds.size())
	_apply_background()


func _toggle_skin() -> void:
	AudioManager.play_ui("ui_move")
	_use_alt = not _use_alt
	var crew := DataRegistry.get_all("characters")
	for i in crew.size():
		_crew_sprites[i].sprite_frames = SpriteSheetLibrary.frames_for_entry(crew[i], _use_alt)
	_apply_anim()


func _go_back() -> void:
	AudioManager.play_ui("ui_back")
	SceneManager.change_scene(BACK_SCENE)
