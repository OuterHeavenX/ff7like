extends Node
## Content registry: the single authoritative loader for authored JSON data.
## Tables are small and loaded at boot; maps and event files are loaded on demand
## and cached so the full campaign never needs to be resident at once.

const TABLES := ["characters", "jobs", "skills", "items", "enemies", "encounters",
	"quests", "shops", "statuses", "chapters", "recipes", "npcs", "contracts"]

var tables: Dictionary = {}          # table name -> { id -> Dictionary }
var _map_cache: Dictionary = {}
var _event_cache: Dictionary = {}
var _event_index: Dictionary = {}    # event id -> file name
var load_errors: PackedStringArray = []


func _ready() -> void:
	reload()


func reload() -> void:
	tables.clear()
	_map_cache.clear()
	_event_cache.clear()
	_event_index.clear()
	load_errors.clear()
	for t: String in TABLES:
		tables[t] = _load_table("res://content/%s.json" % t)
	_index_events()


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		load_errors.append("missing file: " + path)
		return null
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		load_errors.append("%s:%d %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


func _load_table(path: String) -> Dictionary:
	var data: Variant = _read_json(path)
	var out: Dictionary = {}
	if data is Array:
		for entry: Variant in data:
			if entry is Dictionary and entry.has("id"):
				if out.has(entry.id):
					load_errors.append("duplicate id %s in %s" % [entry.id, path])
				out[entry.id] = entry
	elif data is Dictionary:
		out = data
	return out


func _index_events() -> void:
	var data: Variant = _read_json("res://content/events/index.json")
	if not data is Array:
		return
	for file_name: String in data:
		var events: Variant = _read_json("res://content/events/%s.json" % file_name)
		if events is Dictionary:
			_event_cache[file_name] = events
			for eid: String in events.keys():
				if _event_index.has(eid):
					load_errors.append("duplicate event id " + eid)
				_event_index[eid] = file_name


func table(name: String) -> Dictionary:
	return tables.get(name, {})


func get_entry(table_name: String, id: String) -> Dictionary:
	return tables.get(table_name, {}).get(id, {})


func has_entry(table_name: String, id: String) -> bool:
	return tables.get(table_name, {}).has(id)


func character(id: String) -> Dictionary: return get_entry("characters", id)
func job(id: String) -> Dictionary: return get_entry("jobs", id)
func skill(id: String) -> Dictionary: return get_entry("skills", id)
func item(id: String) -> Dictionary: return get_entry("items", id)
func enemy(id: String) -> Dictionary: return get_entry("enemies", id)
func encounter(id: String) -> Dictionary: return get_entry("encounters", id)
func quest(id: String) -> Dictionary: return get_entry("quests", id)
func shop(id: String) -> Dictionary: return get_entry("shops", id)
func status_def(id: String) -> Dictionary: return get_entry("statuses", id)
func npc(id: String) -> Dictionary: return get_entry("npcs", id)


func event(id: String) -> Variant:
	var f: String = _event_index.get(id, "")
	if f == "":
		return null
	return _event_cache[f].get(id)


func has_event(id: String) -> bool:
	return _event_index.has(id)


func all_event_ids() -> Array:
	return _event_index.keys()


func map(id: String) -> Dictionary:
	if _map_cache.has(id):
		return _map_cache[id]
	var data: Variant = _read_json("res://content/maps/%s.json" % id)
	if data is Dictionary:
		# Keep only a handful of maps resident.
		if _map_cache.size() > 6:
			_map_cache.clear()
		_map_cache[id] = data
		return data
	return {}


func has_map(id: String) -> bool:
	return FileAccess.file_exists("res://content/maps/%s.json" % id)


func map_ids() -> Array:
	var data: Variant = _read_json("res://content/maps/index.json")
	return data if data is Array else []


func legend() -> Dictionary:
	if not _map_cache.has("__legend"):
		var d: Variant = _read_json("res://content/maps/_legend.json")
		_map_cache["__legend"] = d if d is Dictionary else {}
	return _map_cache["__legend"]


func display_name(table_name: String, id: String) -> String:
	return str(get_entry(table_name, id).get("name", id))
