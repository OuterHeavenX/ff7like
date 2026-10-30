extends SceneTree
## Loads every GDScript and scene in the project so parse/compile errors surface
## with autoloads available. Usage: godot --headless -s res://tools/check_scripts.gd

var failures := 0


func _initialize() -> void:
	_walk("res://")
	print("check_scripts: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func _walk(dir_path: String) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for f in d.get_files():
		var p := dir_path.path_join(f)
		if f.ends_with(".gd") or f.ends_with(".tscn") or f.ends_with(".gdshader"):
			if p.begins_with("res://tools/check_scripts"):
				continue
			var r := ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_IGNORE)
			if r == null:
				failures += 1
				printerr("FAILED: ", p)
			elif r is GDScript and not (r as GDScript).can_instantiate():
				failures += 1
				printerr("CANNOT INSTANTIATE: ", p)
	for sub in d.get_directories():
		if sub.begins_with(".") or sub == "dist":
			continue
		_walk(dir_path.path_join(sub))
