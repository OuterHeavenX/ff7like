extends RefCounted
## Battle simulation rules: damage bounds, statuses, targeting, outcomes.

var t: Node


func _party_unit(uid: String, hp: int = 100) -> BattleUnit:
	var u := BattleUnit.new()
	u.uid = uid
	u.side = 0
	u.name = uid
	u.level = 5
	u.max_hp = hp
	u.hp = hp
	u.max_sp = 30
	u.sp = 30
	u.atk = 20
	u.mag = 18
	u.def = 10
	u.res = 10
	u.spd = 10
	u.dex = 10
	u.source_id = "rowan"
	return u


func _enemy_unit(uid: String, eid: String = "warden") -> BattleUnit:
	return BattleUnit.from_enemy(eid, int(uid.substr(1)))


func _sim(party: Array, enemies: Array, seed_v: int = 7) -> BattleSim:
	var s := BattleSim.new()
	s.auto_ack = true
	s.setup(party, enemies, seed_v, {"can_escape": true}, {"tonic": 2})
	return s


func _run_until_ready(s: BattleSim, max_steps: int = 5000) -> bool:
	for i in max_steps:
		if not s.ready_queue.is_empty() or s.state != "running":
			return true
		s.step(0.05)
	return false


func test_damage_bounded_and_positive() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var a := _party_unit("p0")
	var b := _enemy_unit("e0")
	for i in 200:
		var r := BattleRules.roll_damage(rng, a, b, {"type": "physical", "power": 100}, true)
		if not r.miss:
			t.ok(r.amount >= 1, "damage at least 1")
			t.ok(r.amount < 200, "damage bounded for level-5 attacker (got %d)" % r.amount)
	t.ok(BattleRules.mitigation(10000, 1) < 1.0, "mitigation never reaches 100%")


func test_normal_attacks_do_not_miss_without_blind() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var a := _party_unit("p0")
	var b := _enemy_unit("e0")
	var misses := 0
	for i in 300:
		if BattleRules.roll_damage(rng, a, b, {"type": "physical", "power": 100}, true).miss:
			misses += 1
	t.eq(misses, 0, "warden has 0 evade; normal attacks always hit")
	a.statuses["blind"] = {"turns": 3}
	misses = 0
	for i in 300:
		if BattleRules.roll_damage(rng, a, b, {"type": "physical", "power": 100}, true).miss:
			misses += 1
	t.ok(misses > 90 and misses < 210, "blind halves accuracy (%d/300 missed)" % misses)


func test_elements_weak_resist_absorb_immune() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var a := _party_unit("p0")
	var wisp := BattleUnit.from_enemy("tallow_wisp", 0)
	var r := BattleRules.roll_damage(rng, a, wisp, {"type": "magic", "power": 100, "element": "fire"}, false)
	t.ok(r.amount < 0, "wisp absorbs fire")
	var r2 := BattleRules.roll_damage(rng, a, wisp, {"type": "magic", "power": 100, "element": "frost"}, false)
	t.ok(float(r2.element_mult) > 1.4, "wisp weak to frost")
	var clap := BattleUnit.from_enemy("hollow_clapper", 1)
	var r3 := BattleRules.roll_damage(rng, a, clap, {"type": "magic", "power": 100, "element": "sound"}, false)
	t.ok(r3.get("immune", false), "clapper immune to sound")


func test_poison_ticks_only_on_own_turn_and_expires() -> void:
	var p := _party_unit("p0", 200)
	var e := _enemy_unit("e0")
	var s := _sim([p], [e])
	p.statuses["poison"] = {"turns": 2}
	s.paused = true
	for i in 200:
		s.step(0.05)
	t.eq(p.hp, 200, "no poison ticks while paused (Wait mode menu)")
	s.paused = false
	p.atb = 99.9
	e.atb = 0.0
	s.step(0.05)
	t.eq(p.hp, 200 - 12, "poison ticks 6% at turn start")
	t.ok(p.waiting_command, "party unit waits for a command after ticking")
	s.submit(p.uid, {"kind": "guard"})
	s.step(0.05)
	s.step(0.05)
	t.eq(int(p.statuses.get("poison", {}).get("turns", 0)), 1, "poison duration decremented at end of own turn")


func test_stun_lock_prevention() -> void:
	var p := _party_unit("p0")
	var e := _enemy_unit("e0")
	var s := _sim([p], [e])
	s._add_status(e, "stun", 1, false, [])
	e.atb = 99.9
	p.atb = 0.0
	s.step(0.05)
	t.ok(not e.has_status("stun"), "stun consumed on its turn")
	t.ok(e.has_status("stun_guard"), "stun guard granted")
	var rng := RandomNumberGenerator.new()
	t.ok(not BattleRules.status_lands(rng, e, "stun", 1.0), "cannot be re-stunned immediately")


func test_dead_units_never_act_and_targets_revalidate() -> void:
	var p := _party_unit("p0")
	var e1 := _enemy_unit("e0")
	var e2 := _enemy_unit("e1")
	var s := _sim([p], [e1, e2])
	p.atb = 100.0
	p.waiting_command = true
	s.ready_queue.append(p.uid)
	t.eq(s.submit(p.uid, {"kind": "skill", "id": "attack", "targets": [e1.uid]}), "", "submit ok")
	e1.hp = 0   # killed before the queued action resolves
	s.queue.push_front({"actor": e1.uid, "cmd": {"kind": "skill", "id": "attack", "targets": [p.uid]}})
	var hp_before := p.hp
	s.step(0.05)   # dead e1's action is dropped
	t.eq(p.hp, hp_before, "dead enemy did not act")
	var e2_before := e2.hp
	s.step(0.05)   # party action retargets to e2
	t.ok(e2.hp < e2_before, "queued attack retargeted to a living enemy")


func test_victory_rewards_once_and_summons_give_none() -> void:
	var p := _party_unit("p0")
	var e := _enemy_unit("e0")
	var s := _sim([p], [e])
	var m := BattleUnit.from_enemy("echo_mote", 5)
	m.summoned = true
	m.rewards = {}
	s.units.append(m)
	e.hp = 0
	m.hp = 0
	s._check_end()
	t.eq(s.state, "victory", "victory when all enemies down")
	var r := s.take_rewards()
	t.eq(int(r.xp), int(Content.enemy("warden").xp), "xp from non-summoned only")
	t.ok(s.take_rewards().is_empty(), "rewards cannot be taken twice")


func test_defeat_state() -> void:
	var p := _party_unit("p0", 1)
	var e := _enemy_unit("e0")
	var s := _sim([p], [e])
	p.hp = 0
	s._check_end()
	t.eq(s.state, "defeat", "defeat when party down")


func test_wait_mode_freezes_time() -> void:
	var p := _party_unit("p0")
	var e := _enemy_unit("e0")
	var s := _sim([p], [e])
	var a0 := e.atb
	s.paused = true
	for i in 100:
		s.step(0.1)
	t.eq(e.atb, a0, "enemy ATB does not fill while paused")


func test_atb_gift_capped_and_not_self() -> void:
	var p := _party_unit("p0")
	var p2 := _party_unit("p1")
	var e := _enemy_unit("e0")
	var s := _sim([p, p2], [e])
	p2.atb = 10.0
	var evs: Array = []
	s._perform(p, Content.skill("relay"), [p2.uid], evs, {})
	t.ok(p2.atb <= 60.0 and p2.atb >= 49.0, "relay adds 40 capped (got %f)" % p2.atb)
	t.ok(not p.uid in s.valid_targets(p, Content.skill("relay")), "relay cannot target self")


func test_delay_cannot_chain() -> void:
	var p := _party_unit("p0")
	var e := _enemy_unit("e0")
	var s := _sim([p], [e])
	s._perform(p, Content.skill("demolition"), [e.uid], [], {})
	t.eq(p.delayed.size(), 1, "demolition schedules one delayed effect")
	s._perform(p, Content.skill("demolition"), [e.uid], [], {"delayed": true})
	t.eq(p.delayed.size(), 1, "delayed executions cannot schedule more delays")


func test_item_reservation_prevents_double_use() -> void:
	var p := _party_unit("p0")
	var p2 := _party_unit("p1")
	var e := _enemy_unit("e0")
	var s := _sim([p, p2], [e])
	s.inventory = {"tonic": 1}
	for u: BattleUnit in [p, p2]:
		u.waiting_command = true
		s.ready_queue.append(u.uid)
	t.eq(s.submit(p.uid, {"kind": "item", "id": "tonic", "targets": [p.uid]}), "", "first tonic ok")
	t.ok(s.submit(p2.uid, {"kind": "item", "id": "tonic", "targets": [p2.uid]}) != "", "second tonic blocked (reserved)")


func test_escape_blocked_in_boss() -> void:
	var p := _party_unit("p0")
	var e := _enemy_unit("e0", "hollow_clapper")
	var s := BattleSim.new()
	s.auto_ack = true
	s.setup([p], [e], 1, {"can_escape": false}, {})
	t.ok(s.command_block_reason(p, {"kind": "escape"}) != "", "cannot escape boss")


func test_boss_phase_and_charge_break() -> void:
	var p := _party_unit("p0", 500)
	var e := _enemy_unit("e0", "hollow_clapper")
	var s := _sim([p], [e])
	e.hp = int(e.max_hp * 0.5)
	var evs: Array = []
	s._check_phases(evs)
	t.eq(e.phase, 1, "phase 2 entered under 60% HP")
	t.ok(s.enemies_alive().size() >= 2, "phase 2 summons motes")
	e.charging = {"skill": "e_discordant_peal", "targets": []}
	s._add_status(e, "stun", 1, false, [])
	e.atb = 99.9
	for u: BattleUnit in s.units:
		if u != e:
			u.atb = 0.0
	s.step(0.05)
	t.ok(e.charging.is_empty(), "stun breaks the telegraphed charge")


func test_full_battle_terminates() -> void:
	# A complete auto-played fight must end (no infinite loops / softlocks).
	GameState.new_game()
	var party: Array = [BattleUnit.from_member("rowan", 0)]
	var s := _sim(party, [_enemy_unit("e0", "brass_rat")], 11)
	var steps := 0
	while s.state == "running" and steps < 20000:
		s.step(0.05)
		for uid: String in s.ready_queue.duplicate():
			s.submit(uid, s.auto_command(s.unit(uid)))
		steps += 1
	t.ok(s.state != "running", "battle ended (state %s after %d steps)" % [s.state, steps])
