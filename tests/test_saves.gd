extends RefCounted
## Save round trips, migration, corrupted-file recovery, import validation.

var t: Node


func test_round_trip() -> void:
	GameState.new_game()
	GameState.join_member("mira", true)
	GameState.add_item("hi_tonic", 3)
	GameState.set_flag("toll_happened")
	GameState.start_quest("mq_street_forgot")
	GameState.set_flag("autosave_enabled")
	t.ok(Saves.save_to("slot3"), "save ok: " + Saves.last_error)
	var snapshot := GameState.to_dict()
	GameState.reset()
	t.ok(Saves.load_from("slot3"), "load ok")
	t.eq(GameState.roster, snapshot.roster, "roster restored")
	t.eq(GameState.count_item("hi_tonic"), 3, "items restored")
	t.ok(GameState.has_flag("toll_happened"), "flags restored")
	t.eq(typeof(GameState.members["rowan"].level), TYPE_INT, "ints normalized after JSON")
	Saves.delete_slot("slot3")


func test_backup_recovery_from_corruption() -> void:
	GameState.new_game()
	t.ok(Saves.save_to("slot3"), "first save")
	GameState.add_gold(500)
	t.ok(Saves.save_to("slot3"), "second save (first becomes .bak)")
	var f := FileAccess.open(Saves.slot_path("slot3"), FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	t.ok(Saves.load_from("slot3"), "recovered from backup")
	t.ok(Saves.last_error.contains("backup"), "user told about recovery")
	Saves.delete_slot("slot3")


func test_migration_v1() -> void:
	GameState.new_game()
	var d := GameState.to_dict()
	d.schema = 1
	d.erase("shop_stock")
	d.erase("bestiary")
	for id: String in d.members.keys():
		d.members[id].erase("passives")
	var r := Saves.validate_and_migrate(JSON.parse_string(JSON.stringify(d)))
	t.ok(r.ok, "v1 migrates")
	t.eq(int(r.data.schema), GameState.SCHEMA_VERSION, "schema bumped")
	t.ok(r.data.members.rowan.has("passives"), "passives added")


func test_rejects_newer_and_garbage() -> void:
	t.ok(not Saves.validate_and_migrate({"schema": 999}).ok, "newer schema rejected")
	t.ok(not Saves.validate_and_migrate("hello").ok, "non-dict rejected")
	t.ok(not Saves.check_import("not json at all").ok, "garbage import rejected")
	t.ok(not Saves.check_import("__TOO_LARGE__").ok, "oversize rejected")


func test_unknown_ids_dropped_gracefully() -> void:
	GameState.new_game()
	var d := GameState.to_dict()
	d.inventory["no_such_item"] = 3
	d.members["ghost"] = d.members.rowan.duplicate(true)
	d.roster.append("ghost")
	d.map_id = "no_such_map"
	var r := Saves.validate_and_migrate(JSON.parse_string(JSON.stringify(d)))
	t.ok(r.ok, "still loads")
	t.ok(not r.data.inventory.has("no_such_item"), "unknown item dropped")
	t.ok(not "ghost" in r.data.roster, "unknown member dropped")
	t.ok(Content.has_map(str(r.data.map_id)), "falls back to a real map")


func test_import_round_trip() -> void:
	GameState.new_game()
	GameState.add_gold(77)
	t.ok(Saves.save_to("slot2"), "save")
	var text := Saves.export_text("slot2")
	var chk := Saves.check_import(text)
	t.ok(chk.ok, "export validates on import")
	t.ok(Saves.apply_import("slot1", chk), "apply import")
	t.ok(Saves.load_from("slot1"), "load imported")
	t.eq(GameState.gold, 197, "gold preserved through export/import")
	Saves.delete_slot("slot1")
	Saves.delete_slot("slot2")


func test_no_autosave_without_game() -> void:
	GameState.reset()
	t.ok(not Saves.autosave(), "title state never autosaves")
