extends Node
## Authoritative runtime game state. Everything here is plain data keyed by
## stable content IDs so it serializes directly into portable save files.

signal party_changed
signal inventory_changed
signal gold_changed
signal flags_changed
signal quest_updated(quest_id: String)
signal notify(text: String)

const SCHEMA_VERSION := 3
const MAX_PARTY := 4
const MAX_LEVEL := 99
const MAX_PASSIVES := 3
const RESERVE_XP_SHARE := 0.75
const RESERVE_JP_SHARE := 0.5
const RANK_THRESHOLDS := [0, 60, 180, 400, 750, 1250, 2000, 3000]

var active: bool = false            # true once a real game is loaded / started
var members: Dictionary = {}        # id -> member state
var roster: Array = []              # joined member ids, in join order
var party: Array = []               # active battle party (<= 4)
var inventory: Dictionary = {}      # item id -> qty
var gold: int = 0
var flags: Dictionary = {}          # flag id -> Variant
var quests: Dictionary = {}         # quest id -> {stage, done, outcome, failed}
var granted: Dictionary = {}        # idempotence ledger: reward key -> true
var jobs_unlocked: Array = []
var bestiary: Dictionary = {}       # enemy id -> {seen, defeated}
var discovered: Array = []          # world map destinations
var map_id: String = ""
var map_pos: Vector2i = Vector2i.ZERO
var map_facing: int = 0
var chapter: String = "prologue"
var playtime: float = 0.0
var steps: int = 0
var tracked_quest: String = ""
var shop_stock: Dictionary = {}     # shop id -> {item id -> remaining}
var rng_seed: int = 0
var contracts: Dictionary = {}      # contract id -> {accepted_at (defeat count), completions, ready_after_battle}
var battles_won: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if active and not get_tree().paused:
		# Clamp large deltas (suspend/resume, tab switching) so time is not inflated.
		playtime += minf(delta, 0.25)


# ---------------------------------------------------------------- lifecycle

func reset() -> void:
	active = false
	members.clear()
	roster.clear()
	party.clear()
	inventory.clear()
	gold = 0
	flags.clear()
	quests.clear()
	granted.clear()
	jobs_unlocked.clear()
	bestiary.clear()
	discovered.clear()
	shop_stock.clear()
	contracts.clear()
	battles_won = 0
	map_id = ""
	map_pos = Vector2i.ZERO
	map_facing = 0
	chapter = "prologue"
	playtime = 0.0
	steps = 0
	tracked_quest = ""
	rng_seed = randi()


func new_game() -> void:
	reset()
	var start: Dictionary = Content.get_entry("chapters", "_start")
	for cid: String in start.get("party", ["rowan"]):
		join_member(cid, true)
	for job_id: String in start.get("jobs", []):
		unlock_job(job_id, true)
	for item_id: String in start.get("items", {}).keys():
		add_item(item_id, int(start.items[item_id]))
	gold = int(start.get("gold", 0))
	map_id = str(start.get("map", "bellweather_wick"))
	var p: Array = start.get("pos", [0, 0])
	map_pos = Vector2i(int(p[0]), int(p[1]))
	chapter = str(start.get("chapter", "prologue"))
	active = true


# ---------------------------------------------------------------- party

func make_member(cid: String) -> Dictionary:
	var c: Dictionary = Content.character(cid)
	var lvl: int = int(c.get("join_level", 1))
	var m := {
		"id": cid, "level": lvl, "xp": xp_total_for_level(lvl), "hp": 1, "sp": 0,
		"job": str(c.get("default_job", "")), "secondary": "",
		"jp": {}, "jp_total": {}, "learned": [], "passives": [],
		"equip": c.get("equip", {"weapon": "", "armor": "", "accessory": ""}).duplicate(),
		"row": str(c.get("row", "front")), "affinity": {},
	}
	for s: String in c.get("innate_skills", []):
		m.learned.append(s)
	return m


func join_member(cid: String, silent: bool = false) -> void:
	if not Content.has_entry("characters", cid):
		push_warning("join_member: unknown character " + cid)
		return
	if not members.has(cid):
		members[cid] = make_member(cid)
		_catch_up_level(cid)
		var st := stats_for(cid)
		members[cid].hp = st.hp
		members[cid].sp = st.sp
	if not cid in roster:
		roster.append(cid)
	if not cid in party and party.size() < MAX_PARTY:
		party.append(cid)
	if not silent:
		notify.emit("%s joined the party." % Content.character(cid).get("name", cid))
	party_changed.emit()


func leave_member(cid: String) -> void:
	party.erase(cid)
	roster.erase(cid)
	party_changed.emit()


func set_party(ids: Array) -> bool:
	if ids.is_empty() or ids.size() > MAX_PARTY:
		return false
	for id: String in ids:
		if not id in roster:
			return false
	var locked: Array = flags.get("party_required", [])
	for req: String in locked:
		if req in roster and not req in ids:
			return false
	party = ids.duplicate()
	party_changed.emit()
	return true


func reserves() -> Array:
	var out: Array = []
	for id: String in roster:
		if not id in party:
			out.append(id)
	return out


func in_party(cid: String) -> bool:
	return cid in party


func lead() -> String:
	return party[0] if not party.is_empty() else "rowan"


func _catch_up_level(cid: String) -> void:
	# New recruits join near the party average so nobody needs recovery grinding.
	if roster.is_empty():
		return
	var total := 0
	for id: String in roster:
		total += int(members[id].level) if members.has(id) else 1
	var avg := int(floor(float(total) / float(roster.size())))
	var m: Dictionary = members[cid]
	if int(m.level) < avg - 1:
		m.level = avg - 1
		m.xp = xp_total_for_level(m.level)


# ---------------------------------------------------------------- progression

static func xp_to_next(level: int) -> int:
	return int(round(14.0 + 7.0 * pow(float(level), 1.85)))


static func xp_total_for_level(level: int) -> int:
	var t := 0
	for l in range(1, level):
		t += xp_to_next(l)
	return t


static func rank_for_jp(total: int) -> int:
	var r := 1
	for i in RANK_THRESHOLDS.size():
		if total >= RANK_THRESHOLDS[i]:
			r = i + 1
	return r


func job_rank(cid: String, job_id: String) -> int:
	return rank_for_jp(int(members[cid].jp_total.get(job_id, 0)))


## Grants XP to one member; returns number of levels gained.
func grant_xp(cid: String, amount: int) -> int:
	var m: Dictionary = members[cid]
	if int(m.level) >= MAX_LEVEL:
		return 0
	var before_stats := stats_for(cid)
	m.xp = int(m.xp) + maxi(amount, 0)
	var gained := 0
	while int(m.level) < MAX_LEVEL and int(m.xp) >= xp_total_for_level(int(m.level) + 1):
		m.level = int(m.level) + 1
		gained += 1
	if gained > 0:
		var after := stats_for(cid)
		m.hp = mini(int(m.hp) + (after.hp - before_stats.hp), after.hp)
		m.sp = mini(int(m.sp) + (after.sp - before_stats.sp), after.sp)
	return gained


func grant_jp(cid: String, amount: int) -> void:
	var m: Dictionary = members[cid]
	var j: String = m.job
	if j == "":
		return
	m.jp[j] = int(m.jp.get(j, 0)) + amount
	m.jp_total[j] = int(m.jp_total.get(j, 0)) + amount


## Distributes battle rewards. Returns a per-member report for the victory screen.
func distribute_battle_rewards(xp: int, jp: int, alive_ids: Array) -> Array:
	var report: Array = []
	var avg_level := 0.0
	for id: String in party:
		avg_level += float(members[id].level)
	avg_level /= maxf(1.0, float(party.size()))
	for id: String in roster:
		var m: Dictionary = members[id]
		var share_xp := float(xp)
		var share_jp := float(jp)
		var note := ""
		if id in party:
			if not id in alive_ids:
				share_xp *= 0.5
				share_jp *= 0.5
				note = "KO: half share"
		else:
			share_xp *= RESERVE_XP_SHARE
			share_jp *= RESERVE_JP_SHARE
			note = "Reserve share"
			if float(m.level) < avg_level - 2.0:
				share_xp *= 2.0
				note = "Reserve catch-up x2"
		var lvl_before: int = m.level
		var gained := grant_xp(id, int(round(share_xp)))
		var rank_before := job_rank(id, m.job) if m.job != "" else 0
		grant_jp(id, int(round(share_jp)))
		var rank_after := job_rank(id, m.job) if m.job != "" else 0
		report.append({"id": id, "xp": int(round(share_xp)), "jp": int(round(share_jp)),
			"level_before": lvl_before, "level": m.level, "levels": gained,
			"rank_up": rank_after > rank_before, "rank": rank_after, "note": note})
	return report


func unlock_job(job_id: String, silent: bool = false) -> void:
	if not Content.has_entry("jobs", job_id) or job_id in jobs_unlocked:
		return
	jobs_unlocked.append(job_id)
	if not silent:
		notify.emit("New job available: %s" % Content.job(job_id).get("name", job_id))


## Whether `cid` may equip job `job_id` as main job.
func can_use_job(cid: String, job_id: String) -> bool:
	if not job_id in jobs_unlocked:
		return false
	var j: Dictionary = Content.job(job_id)
	var allowed: Array = j.get("allowed", [])
	return allowed.is_empty() or cid in allowed


func set_job(cid: String, job_id: String) -> bool:
	if not can_use_job(cid, job_id):
		return false
	var m: Dictionary = members[cid]
	m.job = job_id
	if m.secondary == job_id:
		m.secondary = ""
	_clamp_hp(cid)
	party_changed.emit()
	return true


func set_secondary(cid: String, job_id: String) -> bool:
	var m: Dictionary = members[cid]
	if job_id != "" and (job_id == m.job or not job_id in jobs_unlocked or learned_actives(cid, job_id).is_empty()):
		return false
	m.secondary = job_id
	party_changed.emit()
	return true


func learned_actives(cid: String, job_id: String) -> Array:
	var out: Array = []
	for a: Dictionary in Content.job(job_id).get("abilities", []):
		if str(a.get("type")) == "active" and a.id in members[cid].learned:
			out.append(a.id)
	return out


func ability_entry(job_id: String, ability_id: String) -> Dictionary:
	for a: Dictionary in Content.job(job_id).get("abilities", []):
		if a.id == ability_id:
			return a
	return {}


## Returns "" if learnable, otherwise a human-readable reason.
func learn_block_reason(cid: String, job_id: String, ability_id: String) -> String:
	var m: Dictionary = members[cid]
	var a := ability_entry(job_id, ability_id)
	if a.is_empty():
		return "Unknown ability."
	if ability_id in m.learned:
		return "Already learned."
	if int(a.get("rank", 1)) > job_rank(cid, job_id):
		return "Requires %s rank %d." % [Content.job(job_id).get("name", job_id), int(a.get("rank", 1))]
	for pre: String in a.get("requires", []):
		if not pre in m.learned:
			return "Requires %s." % Content.display_name("skills", pre)
	if int(m.jp.get(job_id, 0)) < int(a.get("jp", 0)):
		return "Needs %d JP (have %d)." % [int(a.get("jp", 0)), int(m.jp.get(job_id, 0))]
	return ""


func learn_ability(cid: String, job_id: String, ability_id: String) -> bool:
	if learn_block_reason(cid, job_id, ability_id) != "":
		return false
	var m: Dictionary = members[cid]
	var a := ability_entry(job_id, ability_id)
	m.jp[job_id] = int(m.jp.get(job_id, 0)) - int(a.get("jp", 0))
	m.learned.append(ability_id)
	if is_job_mastered(cid, job_id):
		notify.emit("%s mastered %s!" % [Content.character(cid).get("name", cid), Content.job(job_id).get("name", job_id)])
	party_changed.emit()
	return true


func is_job_mastered(cid: String, job_id: String) -> bool:
	var abilities: Array = Content.job(job_id).get("abilities", [])
	if abilities.is_empty():
		return false
	for a: Dictionary in abilities:
		if not a.id in members[cid].learned:
			return false
	return true


func learned_passives(cid: String) -> Array:
	var out: Array = []
	for sid: String in members[cid].learned:
		if str(Content.skill(sid).get("kind", "")) == "passive":
			out.append(sid)
	return out


func toggle_passive(cid: String, sid: String) -> bool:
	var m: Dictionary = members[cid]
	if sid in m.passives:
		m.passives.erase(sid)
	else:
		if not sid in learned_passives(cid) or m.passives.size() >= MAX_PASSIVES:
			return false
		m.passives.append(sid)
	_clamp_hp(cid)
	party_changed.emit()
	return true


## Commands available in battle: personal, main job actives, secondary actives.
func battle_skills(cid: String) -> Dictionary:
	var m: Dictionary = members[cid]
	var c := Content.character(cid)
	var personal: Array = []
	for s: String in c.get("personal_skills", []):
		var req: String = Content.skill(s).get("requires_flag", "")
		if s in m.learned or (req != "" and has_flag(req)):
			personal.append(s)
	var main: Array = learned_actives(cid, m.job) if m.job != "" else []
	var sec: Array = learned_actives(cid, m.secondary) if m.secondary != "" else []
	return {"personal": personal, "personal_name": c.get("command", "Talent"), "main": main, "secondary": sec}


# ---------------------------------------------------------------- stats

const STAT_KEYS := ["hp", "sp", "atk", "mag", "def", "res", "spd", "dex"]


## Final stats from level, job, equipment and passives. Bounded and explainable.
func stats_for(cid: String) -> Dictionary:
	var m: Dictionary = members[cid]
	var c: Dictionary = Content.character(cid)
	var base: Dictionary = c.get("base", {})
	var growth: Dictionary = c.get("growth", {})
	var lvl := int(m.level)
	var out: Dictionary = {}
	for k: String in STAT_KEYS:
		out[k] = float(base.get(k, 5)) + float(growth.get(k, 1)) * float(lvl - 1)
	var job: Dictionary = Content.job(str(m.job))
	for k: String in job.get("stat_mod", {}).keys():
		out[k] = out[k] * (1.0 + float(job.stat_mod[k]))
	var elem_res: Dictionary = {}
	var status_res: Dictionary = {}
	var tags: Array = []
	for slot: String in ["weapon", "armor", "accessory"]:
		var iid: String = str(m.equip.get(slot, ""))
		if iid == "":
			continue
		var it: Dictionary = Content.item(iid)
		for k: String in it.get("stats", {}).keys():
			out[k] = float(out.get(k, 0)) + float(it.stats[k])
		for e: String in it.get("element_res", {}).keys():
			elem_res[e] = float(elem_res.get(e, 0.0)) + float(it.element_res[e])
		for s: String in it.get("status_res", {}).keys():
			status_res[s] = maxf(float(status_res.get(s, 0.0)), float(it.status_res[s]))
		for t: String in it.get("tags", []):
			tags.append(t)
	for pid: String in m.passives:
		var p: Dictionary = Content.skill(pid)
		for k: String in p.get("stat_pct", {}).keys():
			out[k] = out[k] * (1.0 + float(p.stat_pct[k]))
		for t: String in p.get("tags", []):
			tags.append(t)
		for sr: String in p.get("status_res", {}).keys():
			status_res[sr] = maxf(float(status_res.get(sr, 0.0)), float(p.status_res[sr]))
	for job_id: String in jobs_unlocked:
		if is_job_mastered(cid, job_id):
			var mastery: Dictionary = Content.job(job_id).get("mastery", {})
			for k: String in mastery.get("stat_pct", {}).keys():
				out[k] = out[k] * (1.0 + float(mastery.stat_pct[k]))
	for k: String in STAT_KEYS:
		out[k] = maxi(1, int(round(out[k])))
	out["element_res"] = elem_res
	out["status_res"] = status_res
	out["tags"] = tags
	out["weapon_kind"] = Content.item(str(m.equip.get("weapon", ""))).get("kind", "fist")
	out["ranged"] = "ranged" in tags
	return out


func _clamp_hp(cid: String) -> void:
	var st := stats_for(cid)
	members[cid].hp = clampi(int(members[cid].hp), 0, st.hp)
	members[cid].sp = clampi(int(members[cid].sp), 0, st.sp)


func heal_all() -> void:
	for id: String in roster:
		var st := stats_for(id)
		members[id].hp = st.hp
		members[id].sp = st.sp


func can_equip(cid: String, item_id: String) -> bool:
	var it: Dictionary = Content.item(item_id)
	var slot: String = str(it.get("slot", ""))
	if slot == "":
		return false
	var who: Array = it.get("users", [])
	if not who.is_empty() and not cid in who:
		return false
	if slot == "weapon":
		var kinds: Array = Content.character(cid).get("weapons", [])
		return kinds.is_empty() or str(it.get("kind", "")) in kinds
	return true


func equip(cid: String, slot: String, item_id: String) -> bool:
	var m: Dictionary = members[cid]
	var current: String = str(m.equip.get(slot, ""))
	if item_id != "":
		if not can_equip(cid, item_id) or str(Content.item(item_id).get("slot")) != slot or count_item(item_id) <= 0:
			return false
		remove_item(item_id, 1)
	if current != "":
		add_item(current, 1)
	m.equip[slot] = item_id
	_clamp_hp(cid)
	party_changed.emit()
	return true


## Picks the strongest equippable gear per slot, respecting locked slots.
func optimize_equipment(cid: String, locked: Array = []) -> void:
	for slot: String in ["weapon", "armor", "accessory"]:
		if slot in locked:
			continue
		var best := str(members[cid].equip.get(slot, ""))
		var best_score := _gear_score(best)
		for iid: String in inventory.keys():
			if int(inventory[iid]) <= 0 or str(Content.item(iid).get("slot", "")) != slot or not can_equip(cid, iid):
				continue
			var s := _gear_score(iid)
			if s > best_score:
				best = iid
				best_score = s
		if best != str(members[cid].equip.get(slot, "")):
			equip(cid, slot, best)


func _gear_score(iid: String) -> float:
	if iid == "":
		return 0.0
	var it: Dictionary = Content.item(iid)
	var s := 0.0
	for k: String in it.get("stats", {}).keys():
		var w := 0.2 if k == "hp" else (0.4 if k == "sp" else 1.0)
		s += float(it.stats[k]) * w
	return s + float(it.get("score_bonus", 0))


# ---------------------------------------------------------------- inventory

func add_item(iid: String, qty: int = 1) -> void:
	if qty <= 0 or not Content.has_entry("items", iid):
		return
	var cap := int(Content.item(iid).get("max", 99))
	inventory[iid] = mini(int(inventory.get(iid, 0)) + qty, cap)
	inventory_changed.emit()


func remove_item(iid: String, qty: int = 1) -> bool:
	if count_item(iid) < qty:
		return false
	inventory[iid] = int(inventory[iid]) - qty
	if int(inventory[iid]) <= 0:
		inventory.erase(iid)
	inventory_changed.emit()
	return true


func count_item(iid: String) -> int:
	return int(inventory.get(iid, 0))


func add_gold(amount: int) -> void:
	gold = maxi(0, gold + amount)
	gold_changed.emit()


func spend_gold(amount: int) -> bool:
	if amount < 0 or gold < amount:
		return false
	gold -= amount
	gold_changed.emit()
	return true


## Idempotent reward grant keyed by a stable id. Returns false if already granted.
func grant_once(key: String, rewards: Dictionary) -> bool:
	if granted.has(key):
		return false
	granted[key] = true
	if rewards.has("gold"):
		add_gold(int(rewards.gold))
	for iid: String in rewards.get("items", {}).keys():
		add_item(iid, int(rewards.items[iid]))
	if rewards.has("xp") or rewards.has("jp"):
		distribute_battle_rewards(int(rewards.get("xp", 0)), int(rewards.get("jp", 0)), party)
	for j: String in rewards.get("jobs", []):
		unlock_job(j)
	return true


# ---------------------------------------------------------------- flags & quests

func has_flag(f: String) -> bool:
	if not flags.has(f):
		return false
	var v: Variant = flags[f]
	match typeof(v):
		TYPE_NIL: return false
		TYPE_BOOL: return v
		TYPE_INT, TYPE_FLOAT: return v != 0
		TYPE_ARRAY: return not (v as Array).is_empty()
	return true


func set_flag(f: String, v: Variant = true) -> void:
	flags[f] = v
	flags_changed.emit()


func quest_state(qid: String) -> Dictionary:
	return quests.get(qid, {})


func quest_stage(qid: String) -> int:
	return int(quests.get(qid, {}).get("stage", -1))


func start_quest(qid: String) -> void:
	if quests.has(qid) or not Content.has_entry("quests", qid):
		return
	quests[qid] = {"stage": 0, "done": false, "outcome": "", "failed": false}
	if tracked_quest == "" or str(Content.quest(qid).get("type")) == "main":
		tracked_quest = qid
	notify.emit("Quest started: %s" % Content.quest(qid).get("title", qid))
	quest_updated.emit(qid)


func set_quest_stage(qid: String, stage: int) -> void:
	if not quests.has(qid):
		start_quest(qid)
	var q: Dictionary = quests[qid]
	if bool(q.done) or stage <= int(q.stage):
		return   # stages only move forward; repeated triggers are harmless
	q.stage = stage
	quest_updated.emit(qid)


func complete_quest(qid: String, outcome: String = "") -> void:
	if not quests.has(qid):
		start_quest(qid)
	var q: Dictionary = quests[qid]
	if bool(q.done):
		return
	q.done = true
	q.outcome = outcome
	var qd: Dictionary = Content.quest(qid)
	q.stage = maxi(int(q.stage), qd.get("stages", []).size() - 1)
	var rewards: Dictionary = qd.get("rewards", {})
	if outcome != "" and qd.get("outcome_rewards", {}).has(outcome):
		rewards = qd.outcome_rewards[outcome]
	grant_once("quest:" + qid, rewards)
	notify.emit("Quest complete: %s" % qd.get("title", qid))
	if tracked_quest == qid:
		tracked_quest = _next_tracked()
	quest_updated.emit(qid)


func _next_tracked() -> String:
	for qid: String in quests.keys():
		if not bool(quests[qid].done) and str(Content.quest(qid).get("type")) == "main":
			return qid
	for qid: String in quests.keys():
		if not bool(quests[qid].done):
			return qid
	return ""


func record_enemy(eid: String, defeated: bool) -> void:
	var b: Dictionary = bestiary.get(eid, {"seen": 0, "defeated": 0})
	b.seen = int(b.seen) + 1
	if defeated:
		b.defeated = int(b.defeated) + 1
	bestiary[eid] = b


## Constrained condition language. Supported forms (joined with "&"):
##   flag:X  !flag:X  quest:X>=N  quest_done:X  !quest:X  quest_outcome:X=Y
##   item:X>=N  party:X  !party:X  roster:X  gold>=N  chapter:X
func check(cond: Variant) -> bool:
	if cond == null:
		return true
	if cond is Array:
		for c: Variant in cond:
			if not check(c):
				return false
		return true
	var s := str(cond).strip_edges()
	if s == "":
		return true
	if s.contains("&"):
		for part in s.split("&"):
			if not check(part):
				return false
		return true
	if s.contains("|"):
		for part in s.split("|"):
			if check(part):
				return true
		return false
	var neg := s.begins_with("!")
	if neg:
		s = s.substr(1)
	var result := _check_atom(s)
	return not result if neg else result


func _check_atom(s: String) -> bool:
	if s.begins_with("flag:"):
		return has_flag(s.substr(5))
	if s.begins_with("quest_done:"):
		var q := s.substr(11)
		return quests.has(q) and bool(quests[q].done)
	if s.begins_with("quest_outcome:"):
		var parts := s.substr(14).split("=")
		return quests.has(parts[0]) and str(quests[parts[0]].outcome) == parts[1]
	if s.begins_with("quest:"):
		var body := s.substr(6)
		if body.contains(">="):
			var p := body.split(">=")
			return quest_stage(p[0]) >= int(p[1])
		if body.contains("<"):
			var p2 := body.split("<")
			return quests.has(p2[0]) and quest_stage(p2[0]) < int(p2[1])
		return quests.has(body)
	if s.begins_with("item:"):
		var body2 := s.substr(5)
		if body2.contains(">="):
			var p3 := body2.split(">=")
			return count_item(p3[0]) >= int(p3[1])
		return count_item(body2) > 0
	if s.begins_with("party:"):
		return s.substr(6) in party
	if s.begins_with("roster:"):
		return s.substr(7) in roster
	if s.begins_with("gold>="):
		return gold >= int(s.substr(6))
	if s.begins_with("chapter:"):
		return chapter == s.substr(8)
	push_warning("Unknown condition: " + s)
	return false


# ---------------------------------------------------------------- crafting

## Returns "" if craftable, else the reason. `station` is "smith" or "any".
func craft_block_reason(rid: String, station: String) -> String:
	var r: Dictionary = Content.get_entry("recipes", rid)
	if r.is_empty():
		return "Unknown recipe."
	if str(r.get("station", "any")) == "smith" and station != "smith":
		return "Needs a smithy."
	for iid: String in r.get("materials", {}).keys():
		var need := int(r.materials[iid])
		var have := count_item(iid)
		if have < need:
			var equipped := 0
			for cid: String in roster:
				for slot: String in ["weapon", "armor", "accessory"]:
					if str(members[cid].equip.get(slot, "")) == iid:
						equipped += 1
			if have + equipped >= need:
				return "Unequip %s first." % Content.item(iid).get("name", iid)
			return "Needs %s x%d (have %d)." % [Content.item(iid).get("name", iid), need, have]
	if gold < int(r.get("gold", 0)):
		return "Needs %d crowns." % int(r.gold)
	return ""


## Atomic: checks everything first, then consumes and grants.
func craft(rid: String, station: String) -> bool:
	if craft_block_reason(rid, station) != "":
		return false
	var r: Dictionary = Content.get_entry("recipes", rid)
	for iid: String in r.get("materials", {}).keys():
		remove_item(iid, int(r.materials[iid]))
	spend_gold(int(r.get("gold", 0)))
	add_item(str(r.result), int(r.get("qty", 1)))
	return true


# ---------------------------------------------------------------- contracts (repeatable)

func contract_progress(cid: String) -> int:
	var c: Dictionary = Content.get_entry("contracts", cid)
	var st: Dictionary = contracts.get(cid, {})
	if not st.has("accepted_at"):
		return 0
	var now := int(bestiary.get(str(c.enemy), {}).get("defeated", 0))
	return clampi(now - int(st.accepted_at), 0, int(c.count))


func contract_state(cid: String) -> String:
	var st: Dictionary = contracts.get(cid, {})
	if st.has("accepted_at"):
		return "ready" if contract_progress(cid) >= int(Content.get_entry("contracts", cid).count) else "active"
	if battles_won < int(st.get("ready_after", 0)):
		return "cooldown"
	return "available"


func accept_contract(cid: String) -> bool:
	if contract_state(cid) != "available":
		return false
	var c: Dictionary = Content.get_entry("contracts", cid)
	var st: Dictionary = contracts.get(cid, {"completions": 0})
	st["accepted_at"] = int(bestiary.get(str(c.enemy), {}).get("defeated", 0))
	contracts[cid] = st
	return true


## Turn in: rewards once per completion; then cooldown measured in won battles.
func turn_in_contract(cid: String) -> bool:
	if contract_state(cid) != "ready":
		return false
	var c: Dictionary = Content.get_entry("contracts", cid)
	var st: Dictionary = contracts[cid]
	st.erase("accepted_at")
	st["completions"] = int(st.get("completions", 0)) + 1
	st["ready_after"] = battles_won + int(c.get("cooldown_battles", 3))
	var rw: Dictionary = c.get("reward", {})
	add_gold(int(rw.get("gold", 0)))
	for iid: String in rw.get("items", {}).keys():
		add_item(iid, int(rw.items[iid]))
	if int(rw.get("jp", 0)) > 0:
		for id: String in party:
			grant_jp(id, int(rw.jp))
	return true


# ---------------------------------------------------------------- serialization

func location_name() -> String:
	return str(Content.map(map_id).get("name", map_id)) if map_id != "" else "—"


func to_dict() -> Dictionary:
	return {
		"schema": SCHEMA_VERSION,
		"build": str(ProjectSettings.get_setting("application/config/version", "0")),
		"members": members.duplicate(true), "roster": roster.duplicate(), "party": party.duplicate(),
		"inventory": inventory.duplicate(), "gold": gold, "flags": flags.duplicate(true),
		"quests": quests.duplicate(true), "granted": granted.duplicate(),
		"jobs_unlocked": jobs_unlocked.duplicate(), "bestiary": bestiary.duplicate(true),
		"discovered": discovered.duplicate(), "map_id": map_id,
		"map_pos": [map_pos.x, map_pos.y], "map_facing": map_facing, "chapter": chapter,
		"playtime": playtime, "steps": steps, "tracked_quest": tracked_quest,
		"shop_stock": shop_stock.duplicate(true), "rng_seed": rng_seed,
		"contracts": contracts.duplicate(true), "battles_won": battles_won,
	}


func from_dict(src: Dictionary) -> void:
	# Deep copy so later resets never mutate the caller's snapshot (retry/load).
	var d: Dictionary = src.duplicate(true)
	reset()
	members = d.get("members", {})
	roster = d.get("roster", [])
	party = d.get("party", [])
	inventory = {}
	for k: String in d.get("inventory", {}).keys():
		inventory[k] = int(d.inventory[k])
	gold = int(d.get("gold", 0))
	flags = d.get("flags", {})
	quests = d.get("quests", {})
	granted = d.get("granted", {})
	jobs_unlocked = d.get("jobs_unlocked", [])
	bestiary = d.get("bestiary", {})
	discovered = d.get("discovered", [])
	map_id = str(d.get("map_id", ""))
	var p: Array = d.get("map_pos", [0, 0])
	map_pos = Vector2i(int(p[0]), int(p[1]))
	map_facing = int(d.get("map_facing", 0))
	chapter = str(d.get("chapter", "prologue"))
	playtime = float(d.get("playtime", 0.0))
	steps = int(d.get("steps", 0))
	tracked_quest = str(d.get("tracked_quest", ""))
	shop_stock = d.get("shop_stock", {})
	rng_seed = int(d.get("rng_seed", 0))
	contracts = d.get("contracts", {})
	battles_won = int(d.get("battles_won", 0))
	# JSON numbers arrive as floats; normalize integer fields on members.
	for id: String in members.keys():
		var m: Dictionary = members[id]
		for k: String in ["level", "xp", "hp", "sp"]:
			m[k] = int(m.get(k, 0))
		for table: String in ["jp", "jp_total"]:
			var t: Dictionary = m.get(table, {})
			for jk: String in t.keys():
				t[jk] = int(t[jk])
	for qid: String in quests.keys():
		quests[qid].stage = int(quests[qid].get("stage", 0))
	active = true
	party_changed.emit()
