class_name BattleSim
extends RefCounted
## Deterministic active-time battle simulation, independent of presentation.
##
## State machine: "running" -> "victory" | "defeat" | "escaped".
## Each step(dt): if an executed action is awaiting presentation (busy), nothing
## advances; otherwise the next queued action executes and produces events;
## otherwise (unless paused for a menu in Wait mode) ATB gauges fill.
## Party units that fill their gauge wait in `ready_queue` for a command.

const MAX_SUMMONS := 2
const MAX_ATB_GIFT := 50.0

var units: Array = []               # Array[BattleUnit]
var rng := RandomNumberGenerator.new()
var state: String = "running"
var queue: Array = []               # pending actions
var ready_queue: Array = []         # party uids awaiting commands
var events: Array = []              # events of the action being presented
var busy: bool = false
var paused: bool = false            # set by UI (Wait mode while choosing)
var auto_ack: bool = false          # headless tests: no presentation step
var time_scale: float = 1.0
var resonance: int = 0
var can_escape: bool = true
var escape_attempts: int = 0
var inventory: Dictionary = {}      # shared reference to the item stock
var reserved: Dictionary = {}
var enemy_index: int = 0
var elapsed: float = 0.0
var action_count: int = 0
var rewards_taken: bool = false
var log_lines: Array = []
var enemy_mods: Dictionary = {}       # difficulty scaling for enemies (incl. summons)
var _pending_status_events: Array = []


func setup(party: Array, enemies: Array, seed_value: int, opts: Dictionary = {}, inv: Dictionary = {}) -> void:
	rng.seed = seed_value
	units.clear()
	for u: BattleUnit in party:
		units.append(u)
	for e: BattleUnit in enemies:
		units.append(e)
		enemy_index = maxi(enemy_index, int(e.uid.substr(1)) + 1)
	can_escape = bool(opts.get("can_escape", true))
	enemy_mods = opts.get("enemy_mods", {})
	for e: BattleUnit in enemies:
		Difficulty.apply(e, enemy_mods)
	inventory = inv
	for u: BattleUnit in units:
		# Staggered openings; preemptive passives start fuller.
		u.atb = rng.randf_range(0.0, 35.0) if u.side == 0 else rng.randf_range(0.0, 25.0)
		if "first_strike" in u.tags:
			u.atb = maxf(u.atb, 60.0)
		if not u.alive():
			u.atb = 0.0


# ------------------------------------------------------------------ queries

func unit(uid: String) -> BattleUnit:
	for u: BattleUnit in units:
		if u.uid == uid:
			return u
	return null


func side_units(side: int, alive_only: bool = true) -> Array:
	var out: Array = []
	for u: BattleUnit in units:
		if u.side == side and (u.alive() or not alive_only):
			out.append(u)
	return out


func party() -> Array:
	return side_units(0, false)


func enemies_alive() -> Array:
	return side_units(1)


func skill_def(id: String) -> Dictionary:
	if Content.has_entry("skills", id):
		return Content.skill(id)
	return {}


func item_skill(item_id: String) -> Dictionary:
	var it: Dictionary = Content.item(item_id)
	var use: Dictionary = it.get("use", {})
	if use.is_empty():
		return {}
	var s := use.duplicate(true)
	s["id"] = item_id
	s["name"] = it.get("name", item_id)
	s["kind"] = "item"
	return s


func available_items() -> Array:
	var out: Array = []
	for iid: String in inventory.keys():
		var left := int(inventory[iid]) - int(reserved.get(iid, 0))
		if left > 0 and not item_skill(iid).is_empty() and Content.item(iid).get("battle", true):
			out.append(iid)
	out.sort()
	return out


## Valid target uids for a definition and actor. Accepts dead allies only for revives.
func valid_targets(actor: BattleUnit, def: Dictionary) -> Array:
	var t: String = def.get("target", "enemy")
	var out: Array = []
	match t:
		"self":
			out = [actor]
		"enemy", "enemies":
			out = side_units(1 - actor.side)
		"ally", "allies":
			out = side_units(actor.side)
		"ally_ko":
			for u: BattleUnit in side_units(actor.side, false):
				if not u.alive():
					out.append(u)
		"ally_any":
			out = side_units(actor.side, false)
		"other_ally":
			for u: BattleUnit in side_units(actor.side):
				if u != actor:
					out.append(u)
	var ids: Array = []
	for u: BattleUnit in out:
		ids.append(u.uid)
	return ids


func is_multi(def: Dictionary) -> bool:
	return str(def.get("target", "")) in ["enemies", "allies"]


func is_magic(def: Dictionary) -> bool:
	return bool(def.get("magic", str(def.get("kind", "")) in ["magic", "heal"]))


func sp_cost(actor: BattleUnit, def: Dictionary) -> int:
	var c := int(def.get("sp", 0))
	if "sp_saver" in actor.tags:
		c = int(ceil(c * 0.75))
	return c


## Returns "" if the command is allowed now, else a reason string for the UI.
func command_block_reason(actor: BattleUnit, cmd: Dictionary) -> String:
	if actor == null or not actor.alive():
		return "Cannot act."
	match str(cmd.get("kind", "skill")):
		"skill":
			var def := skill_def(str(cmd.id))
			if def.is_empty():
				return "Unknown skill."
			if sp_cost(actor, def) > actor.sp:
				return "Not enough SP."
			if is_magic(def) and actor.has_status("silence"):
				return "Silenced."
			if int(def.get("resonance", 0)) > 0:
				if resonance < int(def.resonance):
					return "Needs %d Resonance." % int(def.resonance)
				for pid: String in def.get("partners", []):
					var partner := _find_source(actor.side, pid)
					if partner == null or not partner.can_act():
						return "%s must be able to act." % Content.character(pid).get("name", pid)
			if valid_targets(actor, def).is_empty():
				return "No valid targets."
		"item":
			if not cmd.id in available_items():
				return "None left."
			if valid_targets(actor, item_skill(str(cmd.id))).is_empty():
				return "No valid targets."
		"escape":
			if not can_escape:
				return "Can't escape!"
	return ""


func _find_source(side: int, source: String) -> BattleUnit:
	for u: BattleUnit in units:
		if u.side == side and u.source_id == source:
			return u
	return null


# ------------------------------------------------------------------ commands

func submit(uid: String, cmd: Dictionary) -> String:
	var actor := unit(uid)
	if actor == null or not actor.waiting_command:
		return "Not ready."
	var reason := command_block_reason(actor, cmd)
	if reason != "":
		return reason
	actor.waiting_command = false
	actor.queued = true
	ready_queue.erase(uid)
	if str(cmd.get("kind")) == "item":
		reserved[cmd.id] = int(reserved.get(cmd.id, 0)) + 1
	if str(cmd.get("kind")) in ["skill", "item"]:
		actor.last_command = cmd.duplicate(true)
	queue.append({"actor": uid, "cmd": cmd})
	return ""


func skip_turn(uid: String) -> void:
	var actor := unit(uid)
	if actor and actor.waiting_command:
		submit(uid, {"kind": "guard"})


# ------------------------------------------------------------------ main loop

func step(dt: float) -> void:
	if state != "running":
		return
	if busy:
		if auto_ack:
			ack()
		return
	if not queue.is_empty():
		_execute(queue.pop_front())
		if auto_ack and busy:
			ack()
		return
	if paused:
		return
	elapsed += dt
	var scaled := dt * time_scale
	for u: BattleUnit in units:
		if not u.alive() or u.waiting_command or u.queued:
			continue
		u.atb += BattleRules.atb_rate(u) * scaled
		if u.atb >= 100.0:
			u.atb = 100.0
			_turn_start(u)
			if not queue.is_empty() or busy:
				return


func ack() -> void:
	busy = false
	events.clear()


func take_events() -> Array:
	return events


func _turn_start(u: BattleUnit) -> void:
	u.statuses.erase("guard")
	var evs: Array = []
	# Damage/heal over time — only on the unit's own turn (never while paused).
	if u.has_status("poison"):
		var d := maxi(1, int(u.max_hp * 0.06))
		_apply_hp(u, -d, evs, "poison")
	if u.alive() and u.has_status("burn"):
		var d2 := maxi(1, int(u.max_hp * 0.04))
		_apply_hp(u, -d2, evs, "burn")
	if u.alive() and u.has_status("regen"):
		_apply_hp(u, maxi(1, int(u.max_hp * 0.08)), evs, "regen")
	# Delayed effects owned by this unit.
	var due: Array = []
	for dly: Dictionary in u.delayed:
		dly.turns = int(dly.turns) - 1
		if int(dly.turns) <= 0:
			due.append(dly)
	for dly: Dictionary in due:
		u.delayed.erase(dly)
		queue.push_front({"actor": u.uid, "cmd": {"kind": "skill", "id": dly.skill, "targets": dly.targets, "delayed": true, "free": true}})
	if not u.alive():
		_flush(evs)
		_check_end()
		return
	if u.has_status("stun") or u.has_status("sleep"):
		var which := "stun" if u.has_status("stun") else "sleep"
		evs.append({"t": "msg", "text": "%s is %s!" % [u.name, "stunned" if which == "stun" else "asleep"]})
		if not u.charging.is_empty():
			u.charging = {}
			evs.append({"t": "msg", "text": "%s's charge was broken!" % u.name})
		if which == "stun":
			u.statuses.erase("stun")
			u.statuses["stun_guard"] = {"turns": 2}   # anti stun-lock
			evs.append({"t": "status", "target": u.uid, "id": "stun", "on": false})
		_end_turn(u, true)
		_flush(evs)
		return
	if not evs.is_empty():
		_flush(evs)
	if not u.charging.is_empty():
		queue.append({"actor": u.uid, "cmd": {"kind": "skill", "id": u.charging.skill, "targets": u.charging.targets, "charged": true}})
		u.charging = {}
		u.queued = true
		return
	if u.side == 0:
		u.waiting_command = true
		ready_queue.append(u.uid)
	else:
		var cmd := choose_enemy_action(u)
		u.queued = true
		queue.append({"actor": u.uid, "cmd": cmd})


func _flush(evs: Array) -> void:
	var all := evs + _pending_status_events
	_pending_status_events = []
	if all.is_empty():
		return
	events = all
	busy = true


func _end_turn(u: BattleUnit, skipped: bool = false) -> void:
	u.atb = 0.0
	u.queued = false
	u.waiting_command = false
	u.turns_taken += 1
	var expired: Array = []
	for sid: String in u.statuses.keys():
		var s: Dictionary = u.statuses[sid]
		if s.get("fresh", false):
			s.erase("fresh")
			continue
		if sid == "guard":
			continue
		s.turns = int(s.get("turns", 1)) - 1
		if int(s.turns) <= 0:
			expired.append(sid)
	for sid: String in expired:
		u.statuses.erase(sid)
		if sid == "sleep":
			u.statuses["sleep_guard"] = {"turns": 1}
		if not sid.ends_with("_guard"):
			_pending_status_events.append({"t": "status", "target": u.uid, "id": sid, "on": false})
	if skipped:
		pass


# ------------------------------------------------------------------ execution

func _execute(action: Dictionary) -> void:
	var actor := unit(str(action.actor))
	var cmd: Dictionary = action.cmd
	var evs: Array = []
	if actor == null or not actor.alive():
		# Removed or defeated units never act; release any reservation.
		if str(cmd.get("kind")) == "item":
			reserved[cmd.id] = maxi(0, int(reserved.get(cmd.id, 0)) - 1)
		if actor:
			actor.queued = false
		return
	action_count += 1
	match str(cmd.get("kind", "skill")):
		"guard":
			actor.statuses["guard"] = {"turns": 1}
			evs.append({"t": "start", "actor": actor.uid, "name": "Guard", "anim": "ready", "fx": "shield", "targets": [actor.uid]})
			evs.append({"t": "status", "target": actor.uid, "id": "guard", "on": true})
			_end_turn(actor)
		"row":
			actor.row = "back" if actor.row == "front" else "front"
			evs.append({"t": "row", "target": actor.uid, "row": actor.row})
			evs.append({"t": "msg", "text": "%s moves to the %s row." % [actor.name, actor.row]})
			_end_turn(actor)
		"escape":
			escape_attempts += 1
			var ps := 0.0
			for u: BattleUnit in side_units(0):
				ps += u.spd
			ps /= maxf(1.0, side_units(0).size())
			var es := 0.0
			for u: BattleUnit in enemies_alive():
				es += u.spd
			es /= maxf(1.0, enemies_alive().size())
			if can_escape and rng.randf() < BattleRules.escape_chance(ps, es, escape_attempts - 1):
				evs.append({"t": "escape", "ok": true})
				state = "escaped"
			else:
				evs.append({"t": "escape", "ok": false})
				evs.append({"t": "msg", "text": "Couldn't get away!" if can_escape else "There's no escape!"})
			_end_turn(actor)
		"item":
			reserved[cmd.id] = maxi(0, int(reserved.get(cmd.id, 0)) - 1)
			if int(inventory.get(cmd.id, 0)) <= 0:
				evs.append({"t": "msg", "text": "No %s left!" % Content.item(str(cmd.id)).get("name", cmd.id)})
				_end_turn(actor)
			else:
				inventory[cmd.id] = int(inventory[cmd.id]) - 1
				if int(inventory[cmd.id]) <= 0:
					inventory.erase(cmd.id)
				var def := item_skill(str(cmd.id))
				_perform(actor, def, cmd.get("targets", []), evs, cmd)
				_end_turn(actor)
		_:
			var def2 := skill_def(str(cmd.get("id", "attack")))
			if def2.is_empty():
				def2 = skill_def("attack")
			if def2.get("charge", false) and not cmd.get("charged", false) and actor.side == 1:
				# Telegraphed attack: announce now, resolve on the next turn.
				actor.charging = {"skill": def2.id, "targets": _resolve_targets(actor, def2, cmd.get("targets", []))}
				evs.append({"t": "telegraph", "actor": actor.uid, "text": str(def2.get("telegraph", "%s is gathering power!" % actor.name))})
				_end_turn(actor)
			else:
				var reason := "" if cmd.get("free", false) else command_block_reason(actor, {"kind": "skill", "id": def2.id})
				if reason != "" and not cmd.get("charged", false):
					evs.append({"t": "msg", "text": "%s: %s" % [actor.name, reason]})
					_end_turn(actor)
				else:
					if not cmd.get("free", false):
						actor.sp -= mini(actor.sp, sp_cost(actor, def2))
						if int(def2.get("resonance", 0)) > 0:
							resonance -= int(def2.resonance)
							evs.append({"t": "resonance", "value": resonance})
							for pid: String in def2.get("partners", []):
								var partner := _find_source(actor.side, pid)
								if partner:
									partner.atb = 0.0
					_perform(actor, def2, cmd.get("targets", []), evs, cmd)
					if not cmd.get("delayed", false):
						_end_turn(actor)
	_flush(evs)
	_check_end()


## Re-validates targets at execution time; dead/removed single targets are
## retargeted to a living unit on the same side so actions never hit nothing.
func _resolve_targets(actor: BattleUnit, def: Dictionary, wanted: Array) -> Array:
	var valid := valid_targets(actor, def)
	if valid.is_empty():
		return []
	if is_multi(def):
		return valid
	var tgt: String = str(wanted[0]) if not wanted.is_empty() else ""
	if tgt in valid:
		return [tgt]
	if str(def.get("target")) == "ally_ko":
		return []
	if str(def.get("target")) == "self":
		return [actor.uid]
	return [valid[rng.randi() % valid.size()]]


func _perform(actor: BattleUnit, def: Dictionary, wanted: Array, evs: Array, cmd: Dictionary) -> void:
	var targets := _resolve_targets(actor, def, wanted)
	var phys_single := not is_multi(def) and _has_physical(def) and str(def.get("target")) in ["enemy"]
	# Cover: a guardian intercepts single-target physical attacks.
	if phys_single and not targets.is_empty():
		var orig := unit(targets[0])
		for g: BattleUnit in side_units(orig.side):
			if g != orig and g.has_status("cover") and g.can_act():
				evs.append({"t": "msg", "text": "%s shields %s!" % [g.name, orig.name]})
				targets = [g.uid]
				break
	evs.append({"t": "start", "actor": actor.uid, "name": str(def.get("name", "Attack")),
		"anim": str(def.get("anim", "strike")), "fx": str(def.get("fx", "slash")), "targets": targets,
		"element": str(def.get("element", "")), "show_name": str(def.get("id", "")) != "attack"})
	if targets.is_empty():
		evs.append({"t": "msg", "text": "But there was no target."})
		return
	var res_gain := 0
	if actor.side == 0:
		res_gain += 2 + int(def.get("resonance_gain", 0))
	var countered := false
	for op: Dictionary in def.get("ops", []):
		var op_targets: Array = targets
		if str(op.get("to", "")) == "self":
			op_targets = [actor.uid]
		for tid: String in op_targets:
			var t := unit(tid)
			if t == null:
				continue
			match str(op.op):
				"damage":
					if not t.alive():
						continue
					for h in int(op.get("hits", 1)):
						if not t.alive():
							break
						var r := BattleRules.roll_damage(rng, actor, t, op, not def.get("ranged", false))
						var amount: int = r.amount
						evs.append({"t": "damage", "target": t.uid, "amount": absi(amount), "crit": r.crit, "miss": r.miss,
							"weak": float(r.element_mult) > 1.01, "resist": float(r.element_mult) < 0.99 and float(r.element_mult) > 0.0,
							"immune": r.get("immune", false), "absorb": amount < 0, "element": str(op.get("element", ""))})
						if r.miss or r.get("immune", false):
							continue
						if amount < 0:
							_apply_hp(t, -amount, evs, "")
							continue
						if actor.side == 0:
							if float(r.element_mult) > 1.01:
								res_gain += 10
							if t.has_status("mark") or t.has_status("vulnerable"):
								res_gain += 6
						if t.side == 0 and t.has_status("guard"):
							resonance = mini(100, resonance + 4)
						_apply_hp(t, -amount, evs, "")
						if t.has_status("sleep") and t.alive():
							t.statuses.erase("sleep")
							t.statuses["sleep_guard"] = {"turns": 1}
							evs.append({"t": "status", "target": t.uid, "id": "sleep", "on": false})
						if op.has("drain"):
							_apply_hp(actor, int(amount * float(op.drain)), evs, "")
					# Counterattacks: never chained, never from counters.
					if not countered and not cmd.get("counter", false) and phys_single and str(op.get("type", "physical")) == "physical" \
							and t.alive() and t.can_act() and t.side != actor.side and actor.alive():
						var chance := 0.0
						if "counter" in t.tags:
							chance = 0.35
						if t.has_status("counter_stance"):
							chance = 1.0
						if rng.randf() < chance:
							countered = true
							queue.push_front({"actor": t.uid, "cmd": {"kind": "skill", "id": "counter", "targets": [actor.uid], "counter": true, "free": true, "delayed": true}})
				"heal":
					if op.get("revive", false):
						if t.alive():
							continue
						t.hp = maxi(1, int(t.max_hp * float(op.get("pct", 0.25))))
						t.statuses.clear()
						t.atb = 0.0
						evs.append({"t": "revive", "target": t.uid, "amount": t.hp})
						res_gain += 6
						continue
					if not t.alive():
						continue
					var amt := BattleRules.heal_amount(rng, actor, t, op)
					if t.hp_ratio() < 0.3 and actor.side == 0:
						res_gain += 6
					_apply_hp(t, amt, evs, "")
				"sp":
					if t.alive():
						var before := t.sp
						t.sp = mini(t.max_sp, t.sp + int(op.amount))
						evs.append({"t": "sp", "target": t.uid, "amount": t.sp - before})
				"status":
					var sid: String = op.id
					if not t.alive():
						continue
					var chance2 := float(op.get("chance", 1.0))
					if str(def.get("target")) in ["ally", "allies", "self", "other_ally"] or sid in BattleRules.GOOD:
						chance2 = 1.0 if t.side == actor.side else chance2
					if t.side == actor.side or BattleRules.status_lands(rng, t, sid, chance2):
						_add_status(t, sid, int(op.get("turns", BattleRules.STATUS_DEFAULT_TURNS.get(sid, 3))), t == actor, evs)
						if actor.side == 0 and sid in BattleRules.BAD:
							res_gain += 4
					elif t.side != actor.side:
						evs.append({"t": "damage", "target": t.uid, "amount": 0, "miss": true, "status_miss": sid})
				"cleanse":
					var ids: Array = op.get("ids", BattleRules.BAD)
					for sid2: String in ids:
						if t.statuses.has(sid2):
							t.statuses.erase(sid2)
							evs.append({"t": "status", "target": t.uid, "id": sid2, "on": false})
				"dispel":
					for sid3: String in BattleRules.GOOD:
						if t.statuses.has(sid3):
							t.statuses.erase(sid3)
							evs.append({"t": "status", "target": t.uid, "id": sid3, "on": false})
				"atb":
					# Anti-loop: gifts cap at +50, never to self, never repeated by delays.
					if t.alive() and t != actor and not t.waiting_command and not t.queued:
						t.atb = minf(99.0, t.atb + minf(MAX_ATB_GIFT, float(op.amount)))
						evs.append({"t": "msg", "text": "%s's time gauge surges!" % t.name})
				"atb_drain":
					if t.alive():
						t.atb = maxf(0.0, t.atb - float(op.amount))
				"delay":
					if not cmd.get("delayed", false):
						actor.delayed.append({"skill": str(op.skill), "targets": [t.uid], "turns": int(op.get("turns", 1))})
						evs.append({"t": "status", "target": t.uid, "id": "delay", "on": true})
				"resonance":
					res_gain += int(op.amount)
				"hp_cost":
					# Risky power: costs the caster HP but can never KO them.
					var cost := int(actor.max_hp * float(op.get("pct", 0.1)))
					cost = mini(cost, actor.hp - 1)
					if cost > 0:
						actor.hp -= cost
						evs.append({"t": "damage", "target": actor.uid, "amount": cost, "dot": "cost"})
					break
				"summon":
					var current := 0
					for u: BattleUnit in enemies_alive():
						if u.summoned:
							current += 1
					for k in int(op.get("count", 1)):
						if current >= int(op.get("max", MAX_SUMMONS)):
							break
						var nu := BattleUnit.from_enemy(str(op.enemy), enemy_index)
						Difficulty.apply(nu, enemy_mods)
						enemy_index += 1
						nu.summoned = true   # summons never grant rewards
						nu.rewards = {}
						nu.atb = 20.0
						units.append(nu)
						current += 1
						evs.append({"t": "summon", "unit": nu.uid})
					break
				"analyze":
					var weak: PackedStringArray = []
					var resist: PackedStringArray = []
					for e: String in t.element_mod.keys():
						if float(t.element_mod[e]) > 1.01:
							weak.append(e)
						elif float(t.element_mod[e]) < 0.99:
							resist.append(e)
					evs.append({"t": "msg", "text": "%s — HP %d/%d. Weak: %s. Resists: %s." % [t.name, t.hp, t.max_hp,
						", ".join(weak) if not weak.is_empty() else "none", ", ".join(resist) if not resist.is_empty() else "none"]})
					evs.append({"t": "analyze", "target": t.uid})
	if actor.side == 0 and "resonant" in actor.tags:
		res_gain += 4
	if actor.side == 0 and res_gain > 0 and not cmd.get("charged", false):
		resonance = mini(100, resonance + res_gain)
		evs.append({"t": "resonance", "value": resonance})
	_check_phases(evs)


func _has_physical(def: Dictionary) -> bool:
	for op: Dictionary in def.get("ops", []):
		if str(op.op) == "damage" and str(op.get("type", "physical")) == "physical":
			return true
	return false


func _apply_hp(t: BattleUnit, delta: int, evs: Array, source: String) -> void:
	if delta < 0:
		t.hp = maxi(0, t.hp + delta)
		if source != "":
			evs.append({"t": "damage", "target": t.uid, "amount": -delta, "dot": source})
		if t.hp <= 0:
			_ko(t, evs)
	else:
		var before := t.hp
		t.hp = mini(t.max_hp, t.hp + delta)
		evs.append({"t": "heal", "target": t.uid, "amount": t.hp - before})


func _ko(t: BattleUnit, evs: Array) -> void:
	t.hp = 0
	t.statuses.clear()
	t.atb = 0.0
	t.charging = {}
	t.delayed.clear()
	t.waiting_command = false
	t.queued = false
	ready_queue.erase(t.uid)
	# Drop any queued actions by this unit (dead units never act).
	var kept: Array = []
	for a: Dictionary in queue:
		if str(a.actor) != t.uid:
			kept.append(a)
		elif str(a.cmd.get("kind")) == "item":
			reserved[a.cmd.id] = maxi(0, int(reserved.get(a.cmd.id, 0)) - 1)
	queue = kept
	evs.append({"t": "ko", "target": t.uid})


func _add_status(t: BattleUnit, sid: String, turns: int, fresh: bool, evs: Array) -> void:
	if sid == "haste" and t.statuses.has("slow"):
		t.statuses.erase("slow")
		evs.append({"t": "status", "target": t.uid, "id": "slow", "on": false})
		return
	if sid == "slow" and t.statuses.has("haste"):
		t.statuses.erase("haste")
		evs.append({"t": "status", "target": t.uid, "id": "haste", "on": false})
		return
	# Reapplying refreshes duration (no stacking).
	var entry := {"turns": turns}
	if fresh:
		entry["fresh"] = true
	t.statuses[sid] = entry
	evs.append({"t": "status", "target": t.uid, "id": sid, "on": true})


func _check_phases(evs: Array) -> void:
	for u: BattleUnit in enemies_alive():
		if u.phases.is_empty():
			continue
		while u.phase < u.phases.size() and u.hp_ratio() <= float(u.phases[u.phase].get("hp_below", 0.0)):
			var ph: Dictionary = u.phases[u.phase]
			u.phase += 1
			evs.append({"t": "phase", "actor": u.uid, "text": str(ph.get("message", "%s changes stance!" % u.name))})
			if ph.has("ai"):
				u.ai = ph.ai
			if ph.has("skills"):
				u.skills = ph.skills
			for k: String in ph.get("stat_mod", {}).keys():
				u.set(k, int(float(u.get(k)) * float(ph.stat_mod[k])))
			for sid: String in ph.get("statuses", []):
				_add_status(u, sid, 99, false, evs)
			for e: String in ph.get("elements", {}).keys():
				u.element_mod[e] = float(ph.elements[e])
			if ph.has("summon"):
				var cnt := int(ph.get("summon_count", 1))
				for k in cnt:
					var nu := BattleUnit.from_enemy(str(ph.summon), enemy_index)
					Difficulty.apply(nu, enemy_mods)
					enemy_index += 1
					nu.summoned = true
					nu.rewards = {}
					nu.atb = 10.0
					units.append(nu)
					evs.append({"t": "summon", "unit": nu.uid})
			u.charging = {}


func _check_end() -> void:
	if state != "running":
		return
	if enemies_alive().is_empty():
		state = "victory"
		events.append({"t": "end", "outcome": "victory"})
		busy = true
	elif side_units(0).is_empty():
		state = "defeat"
		events.append({"t": "end", "outcome": "defeat"})
		busy = true


# ------------------------------------------------------------------ enemy AI

func _ai_condition(u: BattleUnit, cond: String) -> bool:
	if cond == "":
		return true
	for part in cond.split("&"):
		var c := part.strip_edges()
		if c.begins_with("self_hp<"):
			if not u.hp_ratio() < float(c.substr(8)):
				return false
		elif c.begins_with("self_hp>"):
			if not u.hp_ratio() > float(c.substr(8)):
				return false
		elif c.begins_with("ally_hp<"):
			var any := false
			for a: BattleUnit in side_units(u.side):
				if a.hp_ratio() < float(c.substr(8)):
					any = true
			if not any:
				return false
		elif c == "ally_down":
			var down := false
			for a: BattleUnit in side_units(u.side, false):
				if not a.alive() and not a.summoned:
					down = true
			if not down:
				return false
		elif c.begins_with("turn%"):
			var n := int(c.substr(5))
			if n <= 0 or (u.turns_taken + 1) % n != 0:
				return false
		elif c.begins_with("phase>="):
			if u.phase < int(c.substr(7)):
				return false
		elif c.begins_with("allies<"):
			if side_units(u.side).size() >= int(c.substr(7)):
				return false
		elif c.begins_with("foe_status:"):
			var sid := c.substr(11)
			var f := false
			for t: BattleUnit in side_units(1 - u.side):
				if t.has_status(sid):
					f = true
			if not f:
				return false
		elif c.begins_with("no_foe_status:"):
			var sid2 := c.substr(14)
			for t: BattleUnit in side_units(1 - u.side):
				if t.has_status(sid2):
					return false
		elif c.begins_with("self_no:"):
			if u.has_status(c.substr(8)):
				return false
	return true


func choose_enemy_action(u: BattleUnit) -> Dictionary:
	var options: Array = []
	var total := 0.0
	for rule: Dictionary in u.ai:
		var sid: String = rule.get("skill", "attack")
		var def := skill_def(sid)
		if def.is_empty() or not _ai_condition(u, str(rule.get("if", ""))):
			continue
		if command_block_reason(u, {"kind": "skill", "id": sid}) != "":
			continue
		options.append(rule)
		total += float(rule.get("w", 1))
	var pick: Dictionary = {"skill": "attack", "target": "random"}
	if not options.is_empty():
		var roll := rng.randf() * total
		for rule: Dictionary in options:
			roll -= float(rule.get("w", 1))
			if roll <= 0.0:
				pick = rule
				break
	var def2 := skill_def(str(pick.get("skill", "attack")))
	var cands := valid_targets(u, def2)
	var tgt: Array = []
	if not cands.is_empty():
		match str(pick.get("target", "random")):
			"lowest_hp":
				var best: BattleUnit = null
				for id: String in cands:
					var c := unit(id)
					if best == null or c.hp_ratio() < best.hp_ratio():
						best = c
				tgt = [best.uid]
			"front":
				var fronts: Array = []
				for id: String in cands:
					if unit(id).row == "front":
						fronts.append(id)
				if fronts.is_empty():
					fronts = cands
				tgt = [fronts[rng.randi() % fronts.size()]]
			"back":
				var backs: Array = []
				for id: String in cands:
					if unit(id).row == "back":
						backs.append(id)
				if backs.is_empty():
					backs = cands
				tgt = [backs[rng.randi() % backs.size()]]
			_:
				tgt = [cands[rng.randi() % cands.size()]]
		# Challenge/taunt: single-target hostile actions usually go to the taunter.
		if not is_multi(def2) and str(def2.get("target")) == "enemy":
			for id: String in cands:
				if unit(id).has_status("taunt") and rng.randf() < 0.75:
					tgt = [id]
					break
	return {"kind": "skill", "id": str(def2.get("id", "attack")), "targets": tgt}


## Auto-battle policy (also used by headless simulations). Never spends items.
## Priorities: answer telegraphed charges, keep allies alive with skills, use
## Resonance arts, then the strongest affordable attack on a priority target.
func auto_command(u: BattleUnit) -> Dictionary:
	var foes := enemies_alive()
	if foes.is_empty():
		return {"kind": "guard"}
	var skills := _usable_skill_ids(u)
	var charger: BattleUnit = null
	for f: BattleUnit in foes:
		if not f.charging.is_empty():
			charger = f
	if charger:
		for sid: String in skills:
			for op: Dictionary in skill_def(sid).get("ops", []):
				if str(op.op) == "status" and str(op.id) == "stun" and str(skill_def(sid).get("target")) in ["enemy", "enemies"]:
					return {"kind": "skill", "id": sid, "targets": [charger.uid]}
		return {"kind": "guard"}
	var allies := side_units(u.side)
	var weakest: BattleUnit = allies[0]
	for a: BattleUnit in allies:
		if a.hp_ratio() < weakest.hp_ratio():
			weakest = a
	for a: BattleUnit in side_units(u.side, false):
		if not a.alive():
			for sid: String in skills:
				if str(skill_def(sid).get("target")) == "ally_ko":
					return {"kind": "skill", "id": sid, "targets": [a.uid]}
	if weakest.hp_ratio() < 0.4:
		for sid: String in skills:
			var d := skill_def(sid)
			if str(d.get("kind")) == "heal" and str(d.get("target")) in ["ally", "allies", "self"]:
				if str(d.get("target")) == "self" and weakest != u:
					continue
				return {"kind": "skill", "id": sid, "targets": [weakest.uid]}
	var tgt: BattleUnit = foes[0]
	for f: BattleUnit in foes:
		if f.role == "healer" or (f.summoned and tgt.boss):
			tgt = f
			break
		if f.hp < tgt.hp and not tgt.role == "healer":
			tgt = f
	for sid: String in skills:
		if int(skill_def(sid).get("resonance", 0)) > 0:
			return {"kind": "skill", "id": sid, "targets": [tgt.uid]}
	var best := "attack"
	var best_score := 1.0
	var reserve := u.max_sp * 0.3
	for sid: String in skills:
		var d2 := skill_def(sid)
		if int(d2.get("resonance", 0)) > 0 or not str(d2.get("target")) in ["enemy", "enemies"]:
			continue
		var score := 0.0
		for op: Dictionary in d2.get("ops", []):
			if str(op.op) == "damage":
				var mult := tgt.elem(str(op.get("element", "")))
				score += float(op.get("power", 100)) / 100.0 * float(op.get("hits", 1)) * maxf(0.0, mult)
		if is_multi(d2):
			score *= minf(float(foes.size()), 2.5) * 0.8
		if u.sp - sp_cost(u, d2) < reserve and sp_cost(u, d2) > 0:
			score *= 0.5
		if score > best_score:
			best_score = score
			best = sid
	return {"kind": "skill", "id": best, "targets": [tgt.uid]}


func _usable_skill_ids(u: BattleUnit) -> Array:
	var out: Array = []
	var ids: Array = u.skills.duplicate() if u.side == 1 else []
	if u.side == 0 and GameState.members.has(u.source_id):
		var bs := GameState.battle_skills(u.source_id)
		ids = bs.personal + bs.main + bs.secondary
		for sid: String in Content.table("skills").keys():
			var sd: Dictionary = Content.skill(sid)
			if str(sd.get("owner", "")) == u.source_id:
				var ok := true
				for pid: String in sd.get("partners", []):
					if _find_source(u.side, pid) == null:
						ok = false
				if ok:
					ids.append(sid)
	for sid: String in ids:
		if command_block_reason(u, {"kind": "skill", "id": sid}) == "":
			out.append(sid)
	return out


# ------------------------------------------------------------------ rewards

## Computes rewards once. Returns {} if already taken (idempotent).
func take_rewards() -> Dictionary:
	if state != "victory" or rewards_taken:
		return {}
	rewards_taken = true
	var xp := 0
	var jp := 0
	var gold := 0
	var drops: Dictionary = {}
	for u: BattleUnit in side_units(1, false):
		if u.summoned or u.rewards.is_empty():
			continue
		xp += int(u.rewards.get("xp", 0))
		jp += int(u.rewards.get("jp", 0))
		gold += int(u.rewards.get("gold", 0))
		for d: Dictionary in u.rewards.get("drops", []):
			if rng.randf() < float(d.get("chance", 0.1)):
				drops[d.item] = int(drops.get(d.item, 0)) + int(d.get("qty", 1))
	return {"xp": xp, "jp": jp, "gold": gold, "drops": drops}
