extends RefCounted
## Difficulty / random-battle options and the Normal-difficulty level curve.

var t: Node


func _with(key: String, value: Variant, body: Callable) -> void:
	var before: Variant = Settings.values.get(key)
	Settings.values[key] = value
	await body.call()
	Settings.values[key] = before


func test_difficulty_scales_only_enemies() -> void:
	GameState.new_game()
	var base := BattleUnit.from_enemy("hollow_clapper", 0)
	var story := BattleUnit.from_enemy("hollow_clapper", 0)
	Difficulty.apply(story, Difficulty.ENEMY_MODS.story)
	t.eq(story.max_hp, int(round(base.max_hp * 0.65)), "story HP x0.65")
	t.eq(story.atk, int(round(base.atk * 0.70)), "story ATK x0.70")
	var hard := BattleUnit.from_enemy("hollow_clapper", 0)
	Difficulty.apply(hard, Difficulty.ENEMY_MODS.hard)
	t.eq(hard.max_hp, int(round(base.max_hp * 1.30)), "hard HP x1.30")
	var hero := BattleUnit.from_member("rowan", 0)
	var hp := hero.max_hp
	Difficulty.apply(hero, Difficulty.ENEMY_MODS.hard)
	t.eq(hero.max_hp, hp, "party units are never scaled")


func test_summons_get_difficulty() -> void:
	GameState.new_game()
	var s := BattleSim.new()
	s.auto_ack = true
	s.setup([BattleUnit.from_member("rowan", 0)], [BattleUnit.from_enemy("hollow_clapper", 0)], 1, {"enemy_mods": Difficulty.ENEMY_MODS.story})
	t.eq(s.enemy_mods, Difficulty.ENEMY_MODS.story, "sim keeps the mods for summons")
	t.eq(s.enemies_alive()[0].max_hp, int(round(BattleUnit.from_enemy("hollow_clapper", 0).max_hp * 0.65)), "starting enemies scaled once")


func test_reward_multipliers() -> void:
	await _with("difficulty", "story", func() -> void:
		t.eq(float(Difficulty.reward_mults(false).xp), 1.25, "story +25% XP"))
	await _with("encounters", "fewer", func() -> void:
		var r := Difficulty.reward_mults(true)
		t.ok(is_equal_approx(float(r.xp), 2.0) and is_equal_approx(float(r.jp), 2.0) and is_equal_approx(float(r.gold), 2.0), "fewer battles: double rewards per random battle")
		t.eq(float(Difficulty.reward_mults(false).xp), 1.0, "story battles are not doubled")
		t.eq(Difficulty.encounter_rate(), 0.5, "fewer battles: half the encounter rate"))
	t.eq(Difficulty.encounter_rate(), 1.0, "normal encounter rate")


func test_invalid_settings_fall_back() -> void:
	Settings.set_value("difficulty", "nightmare")
	t.eq(str(Settings.get_value("difficulty")), "normal", "unknown difficulty clamps to normal")
	Settings.set_value("encounters", "never")
	t.eq(str(Settings.get_value("encounters")), "normal", "unknown encounter option clamps to normal")


func test_story_and_hard_boss_balance() -> void:
	var bal: Object = load("res://tests/test_balance.gd").new()
	bal.set("t", t)
	var story: Dictionary = bal._simulate("boss_clapper", 5, 6, false, [], Difficulty.ENEMY_MODS.story)
	t.ok(int(story.wins) == 6, "Story: Chapter One boss is beaten at Lv5 (%d/6)" % story.wins)
	var hard: Dictionary = bal._simulate("boss_clapper", 9, 6, false, [], Difficulty.ENEMY_MODS.hard)
	t.ok(int(hard.wins) >= 3, "Hard: Chapter One boss is winnable at Lv9 (%d/6)" % hard.wins)


## Expected level from fighting what you meet: story battles plus ten random
## battles per chapter (a conservative count for one pass through each
## dungeon), using each map's weighted encounter table. Normal play must reach
## a level where each boss is fair without grinding.
func _avg_random_xp(maps: Array) -> float:
	var total := 0.0
	var n := 0
	for mid: String in maps:
		var tbl: Array = Content.map(mid).get("encounters", {}).get("table", [])
		var wsum := 0.0
		var xsum := 0.0
		for e: Dictionary in tbl:
			var xp := 0
			for eid: String in Content.encounter(str(e.enc)).enemies:
				xp += int(Content.enemy(eid).get("xp", 0))
			wsum += float(e.get("w", 1))
			xsum += float(e.get("w", 1)) * xp
		if wsum > 0.0:
			total += xsum / wsum
			n += 1
	return total / maxf(1.0, float(n))


func _enc_xp(enc: String) -> int:
	var xp := 0
	for eid: String in Content.encounter(enc).enemies:
		xp += int(Content.enemy(eid).get("xp", 0))
	return xp


func _level_for(xp: int) -> int:
	var lv := 1
	while GameState.xp_total_for_level(lv + 1) <= xp:
		lv += 1
	return lv


func test_normal_progression_reaches_fair_boss_levels() -> void:
	var xp := _enc_xp("story_wardens") + _enc_xp("uc_rats")
	xp += int(10.0 * _avg_random_xp(["undercroft_cistern", "undercroft_upper"]))
	var ch1 := _level_for(xp)
	print("    natural Lv before Chapter One boss: %d (%d XP)" % [ch1, xp])
	t.ok(ch1 >= 6, "Chapter One boss reached at Lv6+ (got %d)" % ch1)
	var bal: Object = load("res://tests/test_balance.gd").new()
	bal.set("t", t)
	var r: Dictionary = bal._simulate("boss_clapper", ch1, 10)
	t.ok(int(r.wins) >= 8, "Chapter One boss fair at the natural level (%d/10)" % r.wins)
	xp += _enc_xp("boss_clapper") + _enc_xp("tr_wraiths") + _enc_xp("tr_marksmen")
	xp += int(10.0 * _avg_random_xp(["freight_cars", "millbrook_cutting"]))
	var ch2 := _level_for(xp)
	print("    natural Lv before Chapter Two boss: %d (%d XP)" % [ch2, xp])
	t.ok(ch2 >= 11, "Chapter Two boss reached at Lv11+ (got %d)" % ch2)
	xp += _enc_xp("boss_signal_warden") + int(10.0 * _avg_random_xp(["glass_vaults"]))
	var ch3 := _level_for(xp)
	print("    natural Lv before Chapter Three boss: %d (%d XP)" % [ch3, xp])
	t.ok(ch3 >= 15, "Chapter Three boss reached at Lv15+ (got %d)" % ch3)
