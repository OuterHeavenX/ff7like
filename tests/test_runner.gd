extends Node
## Headless test runner. Usage:
##   godot --headless res://tests/test_runner.tscn            (all suites)
##   godot --headless res://tests/test_runner.tscn -- --only=battle
## Exits with code 0 on success, 1 on any failure.

const SUITES := ["res://tests/test_battle.gd", "res://tests/test_progression.gd", "res://tests/test_saves.gd",
	"res://tests/test_content.gd", "res://tests/test_balance.gd", "res://tests/test_world_aids.gd",
	"res://tests/test_difficulty.gd", "res://tests/test_play_log.gd"]

var failures: Array = []
var passes := 0
var current := ""


func _ready() -> void:
	await get_tree().process_frame
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	for path: String in SUITES:
		if only != "" and not path.contains(only):
			continue
		var suite: Object = load(path).new()
		suite.set("t", self)
		for m in suite.get_method_list():
			var mname: String = m.name
			if not mname.begins_with("test_"):
				continue
			current = path.get_file() + "::" + mname
			var before := failures.size()
			GameState.reset()
			await suite.call(mname)
			if failures.size() == before:
				passes += 1
				print("  PASS ", current)
	print("\n%d passed, %d failed" % [passes, failures.size()])
	for f in failures:
		printerr("FAIL: ", f)
	get_tree().quit(1 if not failures.is_empty() else 0)


func ok(cond: bool, msg: String) -> void:
	if not cond:
		failures.append("%s — %s" % [current, msg])


func eq(a: Variant, b: Variant, msg: String) -> void:
	if a != b:
		failures.append("%s — %s (got %s, expected %s)" % [current, msg, str(a), str(b)])
