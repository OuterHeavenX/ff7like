extends Node
## Development-only chapter traversal harness (never exported: tests/* is
## excluded). Plays the Prologue + Chapter One route by running the real story
## events in order, auto-advancing dialogue (first choice), auto-playing
## battles, and closing shops/menus. Run:
##   godot --headless -- --smoke
## Prints ROUTE OK / ROUTE FAIL and exits with 0/1.

var _pressing := true
var _fail: Array = []


func _ready() -> void:
	Router.debug_auto_battle = true
	Engine.time_scale = 6.0
	Settings.values["fast_animations"] = true
	Settings.values["battle_speed"] = 5
	Settings.values["text_speed"] = 3
	await Router.start_new_game()
	await _settle()
	if "--boss" in OS.get_cmdline_user_args():
		await _boss_only()
		return
	var w: Node = Router.world
	await _ev("bellweather_wick", "")   # opening ran on new game
	_expect(GameState.quests.has("mq_sealed_fork"), "prologue quest started")
	await _go("post_office")
	await _run("ev_hale_delivery")
	_expect(GameState.count_item("tuning_fork") == 1, "got fork")
	await _go("bellweather_station")
	await _run("ev_wren")
	await _run("ev_mira_delivery")
	_expect(GameState.quest_stage("mq_sealed_fork") == 2, "fork refused by Mira")
	await _go("bellweather_square")
	await _run("ev_toll")
	_expect(GameState.has_flag("toll_happened") and GameState.quests.has("mq_street_forgot"), "toll happened, chapter 1 started")
	await _go("bellweather_wick")
	await _run("ev_bridge_after_toll")
	await _run("ev_abernethy_after")
	await _run("ev_pim_drawing")
	await _go("post_office")
	await _run("ev_hale_after")
	await _run("ev_post_ledger")
	_expect(GameState.quest_stage("mq_street_forgot") == 2, "three proofs found")
	await _go("bellweather_wick")
	await _run("ev_home_return")
	_expect("garran" in GameState.party and "mira" in GameState.party, "Garran and Mira joined")
	await _go("bellweather_square")
	await _run("ev_oswin")
	for lamp in ["ev_lamp_square_a", "ev_lamp_square_b"]:
		await _run(lamp)
	await _go("bellweather_wick")
	for lamp in ["ev_lamp_wick_a", "ev_lamp_wick_b"]:
		await _run(lamp)
	await _go("bellweather_square")
	await _run("ev_oswin")
	_expect(GameState.quests.get("sq_lamplighter", {}).get("done", false), "lamplighter quest complete")
	await _run("ev_brisk")
	await _run("ev_dunmore")
	await _go("bellweather_wick")
	await _run("ev_receipt_crate")
	await _go("bellweather_square")
	await _run("ev_brisk")
	_expect(GameState.quests.get("sq_small_debts", {}).get("done", false), "small debts quest resolved (%s)" % GameState.quests.get("sq_small_debts", {}).get("outcome", "?"))
	await _go("copper_kettle")
	await _run("ev_hask")
	await _run("ev_garran_badge")
	await _run("ev_mira_balcony")
	_expect(GameState.count_item("hatch_key") == 1, "hatch key")
	await _go("bellweather_wick")
	await _run("ev_hatch")
	await _settle()
	_expect(GameState.map_id == "undercroft_upper", "descended into undercroft (map %s)" % GameState.map_id)
	await _run("ev_tamsin_rescue")
	await _run("ev_valve_a")
	await _go("undercroft_cistern")
	await _run("ev_valve_b")
	_expect(GameState.has_flag("cistern_drained"), "cistern drained")
	await _run("ev_joss_found")
	# Simulated grinding to the expected level for the optional elite and boss.
	for cid: String in GameState.roster:
		var need := GameState.xp_total_for_level(10) - int(GameState.members[cid].xp)
		if need > 0:
			GameState.grant_xp(cid, need)
	GameState.heal_all()
	GameState.add_item("tonic", 5)
	await _run("ev_ironside")
	_expect(GameState.has_flag("ironside_done"), "optional elite defeated")
	await _go("undercroft_upper")
	await _run("ev_tamsin_cache")
	_expect(GameState.quests.get("sq_night_crew", {}).get("done", false), "night crew quest")
	await _go("undercroft_core")
	GameState.heal_all()
	await _run("ev_core_pell")
	await _run("ev_core_terminal")
	await _run("ev_boss_clapper")
	await _settle()
	_expect(GameState.has_flag("boss_clapper_done"), "boss defeated")
	_expect(GameState.quests.get("mq_street_forgot", {}).get("done", false), "chapter one main quest complete")
	_expect(GameState.has_flag("slice_complete"), "slice end reached")
	_expect(Saves.any_save_exists(), "autosave written")
	print("PLAYTIME (simulated, not representative): %.1fs" % GameState.playtime)
	if _fail.is_empty():
		print("ROUTE OK")
	else:
		for f in _fail:
			printerr("ROUTE FAIL: ", f)
	get_tree().quit(0 if _fail.is_empty() else 1)


func _boss_only() -> void:
	GameState.join_member("garran", true)
	GameState.join_member("mira", true)
	for cid: String in GameState.roster:
		GameState.grant_xp(cid, GameState.xp_total_for_level(10))
	GameState.heal_all()
	GameState.set_flag("pell_found")
	await _go("undercroft_core")
	await _run("ev_boss_clapper")
	_expect(GameState.has_flag("boss_clapper_done"), "boss defeated")
	get_tree().quit(0 if _fail.is_empty() else 1)


func _expect(c: bool, msg: String) -> void:
	print(("  ok   " if c else "  FAIL ") + msg)
	if not c:
		_fail.append(msg)


func _go(map_id: String) -> void:
	await Router.enter_world(map_id, "default")
	await _settle()


func _ev(_m: String, _e: String) -> void:
	await _settle()


func _run(eid: String) -> void:
	print("  > %s  (t=%ds)" % [eid, Time.get_ticks_msec() / 1000])
	await Router.world.run_event(eid)
	await _settle()


func _settle() -> void:
	for i in 20000:
		await get_tree().process_frame
		if i > 3 and not Router.busy and (Router.world == null or not Router.world.events.running) and Router.battle == null:
			break


func _process(_d: float) -> void:
	if not _pressing:
		return
	# Close menus/shops opened by events.
	for n in get_tree().get_nodes_in_group("__none"):
		pass
	var menus := get_tree().root.find_children("*", "MenuScreen", true, false)
	if not menus.is_empty():
		if Engine.get_process_frames() % 6 == 0:
			_tap("cancel")
		return
	if Router.battle != null and is_instance_valid(Router.battle):
		if Engine.get_process_frames() % 600 == 0:
			var b: Node = Router.battle
			var sm: BattleSim = b.sim
			var hp: PackedStringArray = []
			for u: BattleUnit in sm.units:
				hp.append("%s:%d/%d atb%d w%s q%s" % [u.uid, u.hp, u.max_hp, int(u.atb), u.waiting_command, u.queued])
			print("    [battle] state=%s busy=%s presenting=%s queue=%d ready=%s active=%s menu=%s auto=%s | %s" % [sm.state, sm.busy, b._presenting, sm.queue.size(), sm.ready_queue, b._active_uid, b._menu_state, b._auto, " ".join(hp)])
		if Router.battle.get("_ended") and Engine.get_process_frames() % 10 == 0:
			_tap("confirm")
		return
	if Engine.get_process_frames() % 4 == 0:
		_tap("confirm")


func _tap(action: String) -> void:
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		Input.parse_input_event(ev)
		var ui := "ui_accept" if action == "confirm" else "ui_cancel"
		var ev2 := InputEventAction.new()
		ev2.action = ui
		ev2.pressed = pressed
		Input.parse_input_event(ev2)
