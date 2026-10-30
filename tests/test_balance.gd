extends RefCounted
## Deterministic balance simulations with a human-like policy. These inform
## tuning; they do not prove fun or measure real playtime.

var t: Node


func _setup_party(level: int, extra: Array = []) -> void:
	GameState.new_game()
	GameState.join_member("garran", true)
	GameState.join_member("mira", true)
	for cid: String in extra:
		GameState.join_member(cid, true)
	for cid: String in GameState.roster:
		var m: Dictionary = GameState.members[cid]
		m.level = level
		m.xp = GameState.xp_total_for_level(level)
	GameState.heal_all()
	GameState.add_item("tonic", 6)


func _policy(s: BattleSim, u: BattleUnit) -> Dictionary:
	var boss_charging := false
	for e: BattleUnit in s.enemies_alive():
		if not e.charging.is_empty():
			boss_charging = true
	for a: BattleUnit in s.side_units(0):
		if a.hp_ratio() < 0.35 and s.command_block_reason(u, {"kind": "item", "id": "tonic"}) == "":
			return {"kind": "item", "id": "tonic", "targets": [a.uid]}
	if boss_charging and u.source_id == "garran" and s.command_block_reason(u, {"kind": "skill", "id": "shoulder_charge"}) == "":
		for e: BattleUnit in s.enemies_alive():
			if not e.charging.is_empty():
				return {"kind": "skill", "id": "shoulder_charge", "targets": [e.uid]}
	if boss_charging:
		return {"kind": "guard"}
	var foes := s.enemies_alive()
	var tgt: BattleUnit = foes[0]
	for f: BattleUnit in foes:
		if f.role == "healer" or (f.summoned and tgt.boss):
			tgt = f
			break
	for art: String in ["art_first_light", "art_lantern_relay", "art_spark_bulwark", "art_warden_line"]:
		var sk: Dictionary = Content.skill(art)
		if str(sk.get("owner")) == u.source_id and s.command_block_reason(u, {"kind": "skill", "id": art}) == "":
			return {"kind": "skill", "id": art, "targets": [tgt.uid]}
	var pref := {"rowan": "dash_cut", "mira": "spark_coil", "garran": "shoulder_charge", "nessa": "snipe"}
	var sid: String = pref.get(u.source_id, "attack")
	if u.sp < 8 or s.command_block_reason(u, {"kind": "skill", "id": sid}) != "":
		sid = "attack"
	return {"kind": "skill", "id": sid, "targets": [tgt.uid]}


func _simulate(enc: String, level: int, seeds: int, use_auto: bool = false, extra: Array = []) -> Dictionary:
	var wins := 0
	var total_time := 0.0
	var total_actions := 0
	for sd in seeds:
		_setup_party(level, extra)
		var party: Array = []
		var i := 0
		for cid: String in GameState.party:
			party.append(BattleUnit.from_member(cid, i))
			i += 1
		var enemies: Array = []
		var j := 0
		for eid: String in Content.encounter(enc).enemies:
			enemies.append(BattleUnit.from_enemy(eid, j))
			j += 1
		var s := BattleSim.new()
		s.auto_ack = true
		s.setup(party, enemies, 1000 + sd, {"can_escape": false}, GameState.inventory)
		var steps := 0
		while s.state == "running" and steps < 40000:
			s.step(0.05)
			for uid: String in s.ready_queue.duplicate():
				var u := s.unit(uid)
				var cmd := s.auto_command(u) if use_auto else _policy(s, u)
				if s.submit(uid, cmd) != "":
					s.submit(uid, {"kind": "guard"})
			steps += 1
		if s.state == "victory":
			wins += 1
		total_time += s.elapsed
		total_actions += s.action_count
	return {"wins": wins, "seeds": seeds, "avg_time": total_time / seeds, "avg_actions": float(total_actions) / seeds}


func test_common_encounters_winnable() -> void:
	for enc: String in ["uc_rats", "uc_moths", "uc_mender", "uc_wisps", "uc_crabs", "uc_echo", "uc_wisp_mender", "uc_crab_pair"]:
		var r := _simulate(enc, 4, 6)
		print("    sim %-14s Lv4  wins %d/%d  sim-time %.1fs  actions %.1f" % [enc, r.wins, r.seeds, r.avg_time, r.avg_actions])
		t.ok(r.wins == r.seeds, "%s always winnable at Lv4" % enc)


func test_boss_winnable_but_not_trivial() -> void:
	for lvl in [5, 6, 7, 8]:
		var r := _simulate("boss_clapper", lvl, 10)
		print("    sim boss_clapper  Lv%d  wins %d/%d  sim-time %.1fs  actions %.1f" % [lvl, r.wins, r.seeds, r.avg_time, r.avg_actions])
		if lvl == 7:
			t.ok(r.wins >= 7, "boss winnable at expected level 7 with sensible play (%d/10)" % r.wins)
			t.ok(r.avg_actions >= 20, "boss is not trivial (%.1f actions)" % r.avg_actions)


func test_auto_battle_policy_is_viable() -> void:
	for lvl in [7, 8, 10]:
		var r := _simulate("boss_clapper", lvl, 10, true)
		print("    sim boss_clapper AUTO Lv%d  wins %d/%d  actions %.1f" % [lvl, r.wins, r.seeds, r.avg_actions])
	var r2 := _simulate("uc_crabs", 4, 6, true)
	print("    sim uc_crabs AUTO Lv4 wins %d/%d" % [r2.wins, r2.seeds])
	t.ok(r2.wins == r2.seeds, "auto-battle clears common fights")


func test_elite_ironside() -> void:
	var r := _simulate("elite_ironside", 6, 8)
	print("    sim elite_ironside Lv6 wins %d/%d  sim-time %.1fs  actions %.1f" % [r.wins, r.seeds, r.avg_time, r.avg_actions])
	t.ok(r.wins >= 5, "optional elite beatable at Lv6")


func test_story_wardens_tutorial() -> void:
	GameState.new_game()
	GameState.join_member("garran", true)
	var party: Array = [BattleUnit.from_member("rowan", 0), BattleUnit.from_member("garran", 1)]
	var wins := 0
	for sd in 10:
		var p2: Array = [BattleUnit.from_member("rowan", 0), BattleUnit.from_member("garran", 1)]
		var s := BattleSim.new()
		s.auto_ack = true
		s.setup(p2, [BattleUnit.from_enemy("warden", 0), BattleUnit.from_enemy("warden", 1)], 50 + sd, {}, {"tonic": 3})
		var steps := 0
		while s.state == "running" and steps < 40000:
			s.step(0.05)
			for uid: String in s.ready_queue.duplicate():
				s.submit(uid, s.auto_command(s.unit(uid)))
			steps += 1
		if s.state == "victory":
			wins += 1
	print("    sim story_wardens Lv1-2 (attack only): wins %d/10" % wins)
	t.ok(wins >= 9, "tutorial fight is safe even with attack-only play")


func test_chapter_two_balance() -> void:
	for enc: String in ["rw_hounds_spider", "rw_toad_spiders", "rw_kites", "rw_golem_toad", "tr_leeches", "tr_golem", "tr_marksmen"]:
		var r := _simulate(enc, 10, 6, false, ["nessa"])
		print("    sim %-16s Lv10 wins %d/%d  actions %.1f" % [enc, r.wins, r.seeds, r.avg_actions])
		t.ok(r.wins >= 5, "%s winnable at Lv10" % enc)
	for lvl in [10, 11, 12, 13]:
		var r2 := _simulate("boss_signal_warden", lvl, 8, false, ["nessa"])
		print("    sim boss_signal_warden Lv%d wins %d/%d  actions %.1f" % [lvl, r2.wins, r2.seeds, r2.avg_actions])
