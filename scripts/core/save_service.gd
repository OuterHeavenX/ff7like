extends Node
## Save management: 3 manual slots + 3 rotating autosaves, atomic writes with a
## retained backup, schema migration, validation, corruption recovery, and
## portable JSON export/import (browser download/upload bridge or native folders).

signal saved(slot: String)
signal import_ready(text: String)

const DIR := "user://saves"
const EXPORT_DIR := "user://exports"
const IMPORT_DIR := "user://imports"
const MANUAL_SLOTS := ["slot1", "slot2", "slot3"]
const AUTO_SLOTS := ["auto1", "auto2", "auto3"]
const MAX_IMPORT_BYTES := 2 * 1024 * 1024

var last_error: String = ""
var _js_callback: Variant = null   # keeps the JavaScriptObject callback alive


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	if not OS.has_feature("web"):
		DirAccess.make_dir_recursive_absolute(EXPORT_DIR)
		DirAccess.make_dir_recursive_absolute(IMPORT_DIR)


func slot_path(slot: String) -> String:
	return "%s/%s.json" % [DIR, slot]


func persistent_storage_available() -> bool:
	return OS.is_userfs_persistent()


# ---------------------------------------------------------------- writing

func build_payload() -> Dictionary:
	var d := GameState.to_dict()
	var names: Array = []
	for id: String in GameState.party:
		names.append(Content.character(id).get("name", id))
	var lead_level := 1
	if not GameState.party.is_empty():
		lead_level = int(GameState.members[GameState.party[0]].level)
	d["meta"] = {
		"location": GameState.location_name(),
		"chapter": GameState.chapter,
		"chapter_name": Content.get_entry("chapters", GameState.chapter).get("name", GameState.chapter),
		"party": names, "level": lead_level,
		"playtime": GameState.playtime,
		"timestamp": Time.get_unix_time_from_system(),
		"build": str(ProjectSettings.get_setting("application/config/version", "0")),
		"schema": GameState.SCHEMA_VERSION,
	}
	return d


func save_to(slot: String) -> bool:
	if not GameState.active:
		last_error = "No game in progress."
		return false
	return write_payload(slot, build_payload())


func write_payload(slot: String, payload: Dictionary) -> bool:
	last_error = ""
	var path := slot_path(slot)
	var tmp := path + ".tmp"
	var text := JSON.stringify(payload, "", false)
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		last_error = "Could not write save (%s)." % error_string(FileAccess.get_open_error())
		return false
	f.store_string(text)
	f.close()
	# Verify the temp file round-trips before touching the existing save.
	var check := _read_text(tmp)
	if check != text:
		last_error = "Save verification failed; previous save kept."
		DirAccess.remove_absolute(tmp)
		return false
	if FileAccess.file_exists(path):
		var bak := path + ".bak"
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		DirAccess.rename_absolute(path, bak)
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		last_error = "Could not finalize save (%s)." % error_string(err)
		return false
	saved.emit(slot)
	return true


## Autosave into the oldest rotating slot. Never runs on title/demo state.
func autosave() -> bool:
	if not GameState.active or not GameState.has_flag("autosave_enabled"):
		return false
	var oldest := AUTO_SLOTS[0]
	var oldest_t := INF
	for s: String in AUTO_SLOTS:
		var meta := read_meta(s)
		if meta.is_empty():
			oldest = s
			break
		var t := float(meta.get("timestamp", 0))
		if t < oldest_t:
			oldest_t = t
			oldest = s
	return save_to(oldest)


# ---------------------------------------------------------------- reading

func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func _parse(text: String) -> Variant:
	if text.strip_edges() == "":
		return null
	var j := JSON.new()
	if j.parse(text) != OK:
		return null
	return j.data


func read_meta(slot: String) -> Dictionary:
	var d: Variant = _parse(_read_text(slot_path(slot)))
	if d is Dictionary and d.has("meta"):
		return d.meta
	return {}


func slot_exists(slot: String) -> bool:
	return FileAccess.file_exists(slot_path(slot))


func any_save_exists() -> bool:
	for s: String in MANUAL_SLOTS + AUTO_SLOTS:
		if slot_exists(s):
			return true
	return false


func latest_slot() -> String:
	var best := ""
	var best_t := -1.0
	for s: String in MANUAL_SLOTS + AUTO_SLOTS:
		var m := read_meta(s)
		if not m.is_empty() and float(m.get("timestamp", 0)) > best_t:
			best_t = float(m.timestamp)
			best = s
	return best


## Loads a slot into GameState. Falls back to the backup if the main file is
## unreadable. Returns true on success; last_error explains failures.
func load_from(slot: String) -> bool:
	last_error = ""
	var path := slot_path(slot)
	var data: Variant = _parse(_read_text(path))
	var used_backup := false
	var result := validate_and_migrate(data) if data != null else {"ok": false, "error": "Save file unreadable."}
	if not result.ok:
		var bdata: Variant = _parse(_read_text(path + ".bak"))
		var bres := validate_and_migrate(bdata) if bdata != null else {"ok": false}
		if not bres.ok:
			last_error = str(result.get("error", "Save is corrupted and no valid backup exists."))
			return false
		result = bres
		used_backup = true
	GameState.from_dict(result.data)
	if used_backup:
		last_error = "Main save was damaged; recovered from backup."
	return true


## Validates structure and migrates older schemas. Pure function over data.
func validate_and_migrate(data: Variant) -> Dictionary:
	if not data is Dictionary:
		return {"ok": false, "error": "Not a save file."}
	var d: Dictionary = (data as Dictionary).duplicate(true)
	var schema := int(d.get("schema", 0))
	if schema <= 0:
		return {"ok": false, "error": "Missing schema version."}
	if schema > GameState.SCHEMA_VERSION:
		return {"ok": false, "error": "Save is from a newer build (schema %d)." % schema}
	var warnings: Array = []
	while schema < GameState.SCHEMA_VERSION:
		match schema:
			1:
				# v1 -> v2: added shop stock, bestiary and passive loadouts.
				if not d.has("shop_stock"):
					d.shop_stock = {}
				if not d.has("bestiary"):
					d.bestiary = {}
				for id: String in d.get("members", {}).keys():
					if not d.members[id].has("passives"):
						d.members[id].passives = []
					if not d.members[id].has("affinity"):
						d.members[id].affinity = {}
		schema += 1
		d.schema = schema
	for key: String in ["members", "roster", "party", "inventory", "flags", "quests", "map_id"]:
		if not d.has(key):
			return {"ok": false, "error": "Save missing field '%s'." % key}
	if not d.members is Dictionary or not d.roster is Array or not d.party is Array:
		return {"ok": false, "error": "Save has malformed party data."}
	# Drop references to content that no longer exists instead of crashing.
	for id: String in d.members.keys():
		if not Content.has_entry("characters", id):
			d.members.erase(id)
			warnings.append("Removed unknown character " + id)
	d.roster = d.roster.filter(func(x: Variant) -> bool: return d.members.has(str(x)))
	d.party = d.party.filter(func(x: Variant) -> bool: return d.roster.has(x))
	if d.party.is_empty():
		if d.roster.is_empty():
			return {"ok": false, "error": "Save contains no party."}
		d.party = [d.roster[0]]
	if not d.inventory is Dictionary:
		return {"ok": false, "error": "Save has malformed inventory."}
	for iid: String in d.inventory.keys():
		if not Content.has_entry("items", iid):
			d.inventory.erase(iid)
			warnings.append("Removed unknown item " + iid)
	if not Content.has_map(str(d.map_id)):
		warnings.append("Unknown map %s; returning to start." % d.map_id)
		var start: Dictionary = Content.get_entry("chapters", "_start")
		d.map_id = start.get("map", "bellweather_wick")
		d.map_pos = start.get("pos", [0, 0])
	return {"ok": true, "data": d, "warnings": warnings}


func delete_slot(slot: String) -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(slot_path(slot) + suffix):
			DirAccess.remove_absolute(slot_path(slot) + suffix)


# ---------------------------------------------------------------- portable transfer

func export_text(slot: String) -> String:
	return _read_text(slot_path(slot))


## Exports a slot. On web this triggers a browser download; natively it writes
## into user://exports and returns the absolute path.
func export_slot(slot: String) -> String:
	var text := export_text(slot)
	if text == "":
		last_error = "Slot is empty."
		return ""
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	var fname := "echoes_%s_%s.json" % [slot, stamp]
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(text.to_utf8_buffer(), fname, "application/json")
		return fname
	var p := "%s/%s" % [EXPORT_DIR, fname]
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		last_error = "Could not write export."
		return ""
	f.store_string(text)
	f.close()
	return ProjectSettings.globalize_path(p)


## Web: opens the browser file picker; emits import_ready(text) when chosen.
func request_web_import() -> void:
	if not OS.has_feature("web"):
		return
	_js_callback = JavaScriptBridge.create_callback(_on_js_file)
	var window: JavaScriptObject = JavaScriptBridge.get_interface("window")
	window.echoesImportCallback = _js_callback
	JavaScriptBridge.eval("""
		(function(){
			var input = document.createElement('input');
			input.type = 'file';
			input.accept = '.json,application/json';
			input.style.display = 'none';
			input.onchange = function(e){
				var file = e.target.files[0];
				if (!file) { return; }
				if (file.size > %d) { window.echoesImportCallback('__TOO_LARGE__'); return; }
				var reader = new FileReader();
				reader.onload = function(){ window.echoesImportCallback(reader.result); };
				reader.readAsText(file);
			};
			document.body.appendChild(input);
			input.click();
			setTimeout(function(){ document.body.removeChild(input); }, 60000);
		})();
	""" % MAX_IMPORT_BYTES, true)


func _on_js_file(args: Array) -> void:
	if args.is_empty():
		return
	import_ready.emit(str(args[0]))


func native_import_files() -> Array:
	var out: Array = []
	var dir := DirAccess.open(IMPORT_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.get_extension().to_lower() == "json":
			out.append("%s/%s" % [IMPORT_DIR, f])
	return out


func read_import_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > MAX_IMPORT_BYTES:
		return ""
	return f.get_as_text()


## Validates imported text; returns {ok, data, meta, error}.
func check_import(text: String) -> Dictionary:
	if text == "__TOO_LARGE__" or text.length() > MAX_IMPORT_BYTES:
		return {"ok": false, "error": "File is too large to be a save."}
	var d: Variant = _parse(text)
	var res := validate_and_migrate(d)
	if res.ok:
		res["meta"] = d.get("meta", {})
	return res


func apply_import(slot: String, checked: Dictionary) -> bool:
	if not checked.get("ok", false):
		return false
	var payload: Dictionary = checked.data
	if not payload.has("meta"):
		payload["meta"] = checked.get("meta", {})
	return write_payload(slot, payload)
