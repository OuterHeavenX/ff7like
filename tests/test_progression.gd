extends RefCounted
## XP/JP thresholds, learning prerequisites, party changes, inventory,
## equipment, quest branching and reward idempotence.

var t: Node


func test_xp_curve_monotonic_and_level_cap() -> void:
	var prev := 0
	for l in range(1, 99):
		var n := GameState.xp_to_next(l)
		t.ok(n > prev, "xp_to_next grows at level %d" % l)
		prev = n
	GameState.new_game()
	GameState.grant_xp("rowan", 100000000)
	t.eq(int(GameState.members["rowan"].level), 99, "level caps at 99")


func test_level_up_thresholds_exact() -> void:
	GameState.new_game()
	var need := GameState.xp_total_for_level(2) - int(GameState.members["rowan"].xp)
	t.eq(GameState.grant_xp("rowan", need - 1), 0, "one XP short does not level")
	t.eq(GameState.grant_xp("rowan", 1), 1, "exact threshold levels up")


func test_job_rank_and_learning_rules() -> void:
	GameState.new_game()
	var m: Dictionary = GameState.members["rowan"]
	t.eq(m.job, "wayfarer", "rowan starts as wayfarer")
	t.ok(GameState.learn_block_reason("rowan", "wayfarer", "first_aid").begins_with("Needs"), "needs JP")
	GameState.grant_jp("rowan", 15)
	t.ok(GameState.learn_ability("rowan", "wayfarer", "first_aid"), "learn with exact JP")
	t.eq(int(m.jp.wayfarer), 0, "JP spent")
	t.ok(not GameState.learn_ability("rowan", "wayfarer", "first_aid"), "cannot learn twice")
	GameState.grant_jp("rowan", 1000)
	t.ok(GameState.learn_block_reason("rowan", "wayfarer", "pathfinder").contains("rank") == false or GameState.job_rank("rowan", "wayfarer") >= 5, "rank gating consistent")
	t.ok("first_aid" in GameState.battle_skills("rowan").main, "learned active usable in battle")


func test_prerequisites_block() -> void:
	GameState.new_game()
	GameState.unlock_job("vanguard", true)
	GameState.join_member("garran", true)
	GameState.grant_jp("garran", 5000)
	var r := GameState.learn_block_reason("garran", "vanguard", "breaker")
	t.ok(r.contains("Shield Bash") or r.contains("shield_bash"), "breaker requires shield bash (%s)" % r)


func test_all_job_prerequisites_are_satisfiable() -> void:
	for jid: String in Content.table("jobs").keys():
		var abil: Array = Content.job(jid).get("abilities", [])
		var ids: Array = []
		for a: Dictionary in abil:
			ids.append(a.id)
		for a: Dictionary in abil:
			for pre: String in a.get("requires", []):
				t.ok(pre in ids, "%s/%s prerequisite %s exists in same job" % [jid, a.id, pre])
			t.ok(int(a.get("rank", 1)) <= GameState.RANK_THRESHOLDS.size(), "%s rank reachable" % a.id)
		t.ok(abil.size() >= 9, "%s has >= 9 abilities" % jid)


func test_party_changes_and_reserve_rewards() -> void:
	GameState.new_game()
	GameState.join_member("mira", true)
	GameState.join_member("garran", true)
	GameState.join_member("sera", true)
	GameState.join_member("ilyan", true)
	t.eq(GameState.party.size(), 4, "party max 4")
	t.eq(GameState.reserves(), ["ilyan"], "fifth member is reserve")
	var lvl_before := int(GameState.members["ilyan"].level)
	var rep := GameState.distribute_battle_rewards(100, 20, GameState.party)
	var ilyan_rep: Dictionary = {}
	for r: Dictionary in rep:
		if r.id == "ilyan":
			ilyan_rep = r
	t.eq(int(ilyan_rep.jp), 10, "reserve gets 50% JP")
	t.ok(int(ilyan_rep.xp) >= 75, "reserve gets at least 75% XP")
	t.ok(not GameState.set_party(["rowan", "mira", "garran", "sera", "ilyan"]), "cannot exceed 4")
	t.ok(GameState.set_party(["ilyan", "rowan"]), "can rearrange party")
	GameState.set_flag("party_required", ["mira"])
	t.ok(not GameState.set_party(["rowan"]), "required member must stay")


func test_inventory_and_equipment() -> void:
	GameState.new_game()
	GameState.add_item("tonic", 200)
	t.eq(GameState.count_item("tonic"), 99, "stack cap 99")
	t.ok(not GameState.remove_item("hi_tonic", 1), "cannot remove missing")
	GameState.add_item("steel_saber", 1)
	var before := int(GameState.stats_for("rowan").atk)
	t.ok(GameState.equip("rowan", "weapon", "steel_saber"), "equip saber")
	t.ok(int(GameState.stats_for("rowan").atk) > before, "atk increases")
	t.eq(GameState.count_item("courier_knife"), 1, "old weapon returned to bag")
	t.ok(not GameState.equip("rowan", "weapon", "torque_wrench"), "cannot equip unowned/unusable")
	GameState.add_item("oak_maul", 1)
	t.ok(not GameState.can_equip("rowan", "oak_maul"), "rowan cannot use hammers")
	t.ok(not GameState.spend_gold(999999), "cannot overspend")


func test_optimize_respects_locks() -> void:
	GameState.new_game()
	GameState.add_item("steel_saber", 1)
	GameState.add_item("padded_vest", 1)
	GameState.optimize_equipment("rowan", ["weapon"])
	t.eq(str(GameState.members["rowan"].equip.weapon), "courier_knife", "locked weapon untouched")
	t.eq(str(GameState.members["rowan"].equip.armor), "padded_vest", "armor optimized")


func test_quest_branching_and_idempotence() -> void:
	GameState.new_game()
	GameState.start_quest("sq_small_debts")
	GameState.set_quest_stage("sq_small_debts", 2)
	GameState.set_quest_stage("sq_small_debts", 1)
	t.eq(GameState.quest_stage("sq_small_debts"), 2, "stages never move backwards")
	var g0 := GameState.gold
	GameState.complete_quest("sq_small_debts", "mercy")
	t.eq(GameState.gold - g0, 30, "mercy outcome reward")
	t.eq(GameState.count_item("barrel_hoop"), 1, "mercy item")
	GameState.complete_quest("sq_small_debts", "truth")
	t.eq(GameState.gold - g0, 30, "completing again grants nothing")
	t.ok(GameState.check("quest_outcome:sq_small_debts=mercy"), "outcome condition")


func test_grant_once_ledger() -> void:
	GameState.new_game()
	t.ok(GameState.grant_once("chest:x", {"gold": 10}), "first grant")
	t.ok(not GameState.grant_once("chest:x", {"gold": 10}), "second grant refused")


func test_conditions() -> void:
	GameState.new_game()
	GameState.set_flag("a")
	t.ok(GameState.check("flag:a&!flag:b"), "and/not")
	t.ok(GameState.check("flag:b|flag:a"), "or")
	t.ok(GameState.check("party:rowan"), "party")
	t.ok(not GameState.check("roster:mira"), "roster")
	t.ok(GameState.check("item:tonic>=3"), "item count")


func test_crafting_atomic_and_gated() -> void:
	GameState.new_game()
	t.ok(GameState.craft_block_reason("r_honed_knife", "smith").begins_with("Unequip"), "equipped base item must be unequipped first")
	GameState.equip("rowan", "weapon", "")
	t.ok(GameState.craft_block_reason("r_honed_knife", "any") == "Needs a smithy.", "upgrade needs smithy")
	t.ok(GameState.craft_block_reason("r_honed_knife", "smith").begins_with("Needs Brass"), "needs materials")
	GameState.add_item("brass_scrap", 4)
	var g0 := GameState.gold
	t.ok(GameState.craft("r_honed_knife", "smith"), "craft upgrade")
	t.eq(GameState.count_item("honed_knife"), 1, "result granted")
	t.eq(GameState.count_item("courier_knife"), 0, "base consumed")
	t.eq(GameState.count_item("brass_scrap"), 0, "materials consumed")
	t.eq(g0 - GameState.gold, 80, "gold cost")
	t.ok(not GameState.craft("r_honed_knife", "smith"), "cannot craft without inputs")


func test_contracts_repeatable_with_cooldown() -> void:
	GameState.new_game()
	t.eq(GameState.contract_state("c_brass_rats"), "available", "available")
	GameState.record_enemy("brass_rat", true)
	t.ok(GameState.accept_contract("c_brass_rats"), "accept")
	t.eq(GameState.contract_progress("c_brass_rats"), 0, "kills before accepting don't count")
	for i in 6:
		GameState.record_enemy("brass_rat", true)
	t.eq(GameState.contract_state("c_brass_rats"), "ready", "ready after 6")
	var g0 := GameState.gold
	t.ok(GameState.turn_in_contract("c_brass_rats"), "turn in")
	t.eq(GameState.gold - g0, 120, "reward once")
	t.ok(not GameState.turn_in_contract("c_brass_rats"), "no double turn-in")
	t.eq(GameState.contract_state("c_brass_rats"), "cooldown", "cooldown after completion")
	GameState.battles_won += 3
	t.eq(GameState.contract_state("c_brass_rats"), "available", "repeatable after cooldown")
