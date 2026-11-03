extends Node
## Loads read-only game data from res://data/<category>/*.json (autoload: DataRegistry).
## Each file is {"entries": [ {...}, ... ]}. Entries are validated against REQUIRED_FIELDS
## and indexed by "id". Callers always receive deep copies, so data can't be mutated by accident.
## NOTE: the Android export preset includes "data/*.json" so these raw files ship in the APK.

const DATA_ROOT := "res://data"
const REQUIRED_FIELDS := {
	"characters": ["id", "name", "role", "base_stats", "growth", "skills"],
	"islands": ["id", "name", "sea", "order", "biome"],
	"seas": ["id", "name", "order"],
	"items": ["id", "name", "category", "rarity", "price"],
}

var errors: PackedStringArray = []
var _tables: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	errors.clear()
	_tables.clear()
	for category: String in REQUIRED_FIELDS:
		_tables[category] = {}
	_load_dir("characters", "%s/characters" % DATA_ROOT)
	_load_dir("items", "%s/items" % DATA_ROOT)
	_load_dir("islands", "%s/islands" % DATA_ROOT)
	for e in errors:
		push_error("DataRegistry: %s" % e)


func _load_dir(default_category: String, dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		errors.append("missing data dir %s" % dir_path)
		return
	for file in DirAccess.get_files_at(dir_path):
		if file.get_extension() != "json":
			continue
		var path := "%s/%s" % [dir_path, file]
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) != TYPE_DICTIONARY:
			errors.append("%s is not a JSON object" % path)
			continue
		var doc: Dictionary = parsed
		# A file may declare its own category (e.g. seas.json lives with islands).
		var category := str(doc.get("category", default_category))
		if not REQUIRED_FIELDS.has(category):
			errors.append("%s: unknown category '%s'" % [path, category])
			continue
		var entries: Variant = doc.get("entries")
		if typeof(entries) != TYPE_ARRAY:
			errors.append("%s has no 'entries' array" % path)
			continue
		for entry: Variant in entries:
			_add_entry(category, entry, path)


func _add_entry(category: String, entry: Variant, source: String) -> void:
	if typeof(entry) != TYPE_DICTIONARY:
		errors.append("%s: non-object entry in %s" % [source, category])
		return
	var e: Dictionary = entry
	for field: String in REQUIRED_FIELDS[category]:
		if not e.has(field):
			errors.append("%s: %s entry '%s' missing '%s'" % [source, category, e.get("id", "?"), field])
			return
	var id := str(e["id"])
	var table: Dictionary = _tables[category]
	if table.has(id):
		errors.append("%s: duplicate %s id '%s'" % [source, category, id])
		return
	table[id] = e


func has_entry(category: String, id: String) -> bool:
	return _tables.has(category) and (_tables[category] as Dictionary).has(id)


func get_entry(category: String, id: String) -> Dictionary:
	if not has_entry(category, id):
		return {}
	return (_tables[category][id] as Dictionary).duplicate(true)


## All entries of a category, sorted by "order" (if present) then id.
func get_all(category: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not _tables.has(category):
		return out
	for e: Dictionary in (_tables[category] as Dictionary).values():
		out.append(e.duplicate(true))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var oa := float(a.get("order", 0))
		var ob := float(b.get("order", 0))
		if oa != ob:
			return oa < ob
		return str(a["id"]) < str(b["id"]))
	return out


func count(category: String) -> int:
	return (_tables.get(category, {}) as Dictionary).size()


func get_islands_in_sea(sea_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for island in get_all("islands"):
		if island["sea"] == sea_id:
			out.append(island)
	return out
