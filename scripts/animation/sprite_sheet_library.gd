class_name SpriteSheetLibrary
extends RefCounted
## Builds SpriteFrames from grid sprite sheets using the layouts in res://data/sprite_layouts.json.
## Results are cached per (sheet, layout), so ten characters sharing one sheet share one
## SpriteFrames + one texture in memory. Sheet dimensions are validated against the layout.

const LAYOUTS_PATH := "res://data/sprite_layouts.json"

static var _layouts: Dictionary = {}
static var _effects: Dictionary = {}
static var _cache: Dictionary = {}


static func _ensure_loaded() -> void:
	if not _layouts.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUTS_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SpriteSheetLibrary: cannot parse %s" % LAYOUTS_PATH)
		return
	_layouts = parsed.get("layouts", {})
	_effects = parsed.get("effects", {})


static func get_layout(layout_id: String) -> Dictionary:
	_ensure_loaded()
	return _layouts.get(layout_id, {})


static func effect_ids() -> Array[String]:
	_ensure_loaded()
	var out: Array[String] = []
	for k: String in _effects:
		out.append(k)
	return out


## Expected animation names for a layout (rows + aliases).
static func animation_names(layout_id: String) -> Array[String]:
	var layout := get_layout(layout_id)
	var out: Array[String] = []
	for r: String in layout.get("rows", []):
		out.append(r)
	for a: String in layout.get("aliases", {}):
		out.append(a)
	return out


static func get_frames(sheet_path: String, layout_id: String) -> SpriteFrames:
	var key := "%s|%s" % [sheet_path, layout_id]
	if _cache.has(key):
		return _cache[key]
	var layout := get_layout(layout_id)
	if layout.is_empty():
		push_error("SpriteSheetLibrary: unknown layout '%s'" % layout_id)
		return null
	if not ResourceLoader.exists(sheet_path):
		push_error("SpriteSheetLibrary: missing sheet %s" % sheet_path)
		return null
	var texture := load(sheet_path) as Texture2D
	if texture == null:
		return null
	var fw := int(layout["frame_size"][0])
	var fh := int(layout["frame_size"][1])
	var cols := int(layout["columns"])
	var rows: Array = layout["rows"]
	var expected := Vector2i(fw * cols, fh * rows.size())
	if Vector2i(texture.get_size()) != expected:
		push_error("SpriteSheetLibrary: %s is %s, layout '%s' expects %s" % [sheet_path, texture.get_size(), layout_id, expected])
		return null

	var fps: Dictionary = layout.get("fps", {})
	var loops: Array = layout.get("loop", [])
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	for row in rows.size():
		var anim := StringName(rows[row])
		frames.add_animation(anim)
		frames.set_animation_speed(anim, float(fps.get(rows[row], 10)))
		frames.set_animation_loop(anim, loops.has(rows[row]))
		for col in cols:
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(col * fw, row * fh, fw, fh)
			atlas.filter_clip = true # prevents neighbouring-frame bleed when scaled
			frames.add_frame(anim, atlas)
	var aliases: Dictionary = layout.get("aliases", {})
	for alias: String in aliases:
		var src := StringName(aliases[alias])
		if not frames.has_animation(src) or frames.has_animation(alias):
			continue
		frames.add_animation(alias)
		frames.set_animation_speed(alias, frames.get_animation_speed(src))
		frames.set_animation_loop(alias, false)
		for i in frames.get_frame_count(src):
			frames.add_frame(alias, frames.get_frame_texture(src, i))
	_cache[key] = frames
	return frames


## Frames for a data entry with a "sprite" block (characters, enemies, bosses).
static func frames_for_entry(entry: Dictionary, use_alt := false) -> SpriteFrames:
	var sprite: Dictionary = entry.get("sprite", {})
	var path := str(sprite.get("alt_sheet" if use_alt else "sheet", ""))
	if path == "" and use_alt:
		path = str(sprite.get("sheet", ""))
	return get_frames(path, str(sprite.get("layout", "")))


static func effect_frames(effect_id: String) -> SpriteFrames:
	_ensure_loaded()
	if not _effects.has(effect_id):
		push_error("SpriteSheetLibrary: unknown effect '%s'" % effect_id)
		return null
	return get_frames(str(_effects[effect_id]), "vfx_8x4")


static func clear_cache() -> void:
	_cache.clear()
