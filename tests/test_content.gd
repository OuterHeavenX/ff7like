extends RefCounted
## Content integrity: dangling references, duplicate IDs, map connectivity,
## event command vocabulary, reachable exits and reward-duplication risks.

var t: Node

const OPS := ["damage", "heal", "sp", "status", "cleanse", "dispel", "atb", "atb_drain", "delay", "resonance", "summon", "analyze", "hp_cost"]
const TARGETS := ["self", "enemy", "enemies", "ally", "allies", "ally_ko", "ally_any", "other_ally"]
const EVENT_KEYS := ["say", "party_say", "narrate", "choice", "if", "flag", "item", "gold", "join", "leave", "require_party",
	"quest_start", "quest_stage", "quest_complete", "battle", "move", "face", "emote", "refresh_npcs", "refresh_map", "remove_npc",
	"wait", "fade", "warp", "music", "sfx", "shake", "flash", "title_card", "shop", "inn", "save_menu", "heal", "unlock_job",
	"learn", "set_chapter", "call", "autosave", "tutorial", "open_menu", "camera", "end_slice", "craft", "contracts"]


func test_no_load_errors() -> void:
	t.eq(Array(Content.load_errors), [], "content files parse without errors or duplicate IDs")


func test_skills_valid() -> void:
	for sid: String in Content.table("skills").keys():
		var s: Dictionary = Content.skill(sid)
		if str(s.get("kind")) == "passive":
			continue
		t.ok(str(s.get("target", "")) in TARGETS, "%s target valid" % sid)
		for op: Dictionary in s.get("ops", []):
			t.ok(str(op.get("op")) in OPS, "%s op %s known" % [sid, op.get("op")])
			if op.get("op") == "delay":
				t.ok(Content.has_entry("skills", str(op.skill)), "%s delay target exists" % sid)
			if op.get("op") == "summon":
				t.ok(Content.has_entry("enemies", str(op.enemy)), "%s summon exists" % sid)
			if op.get("op") == "status":
				t.ok(Content.has_entry("statuses", str(op.id)), "%s status %s defined" % [sid, op.id])
		for pid: String in s.get("partners", []):
			t.ok(Content.has_entry("characters", pid), "%s partner exists" % sid)


func test_job_and_character_refs() -> void:
	t.eq(Content.table("jobs").size(), 12, "12 jobs defined")
	for jid: String in Content.table("jobs").keys():
		var actives := 0
		var passives := 0
		for a: Dictionary in Content.job(jid).get("abilities", []):
			t.ok(Content.has_entry("skills", str(a.id)), "%s ability %s exists" % [jid, a.id])
			var kind := str(Content.skill(str(a.id)).get("kind"))
			if a.type == "passive":
				passives += 1
				t.eq(kind, "passive", "%s marked passive matches skill" % a.id)
			else:
				actives += 1
		t.ok(actives >= 6 and passives >= 3, "%s has 6 actives / 3 passives" % jid)
		t.ok(Content.job(jid).has("mastery"), "%s has mastery" % jid)
	t.eq(Content.table("characters").size(), 8, "8 playable characters")
	for cid: String in Content.table("characters").keys():
		var c: Dictionary = Content.character(cid)
		t.ok(Content.has_entry("jobs", str(c.default_job)), "%s default job" % cid)
		for s: String in c.get("personal_skills", []) + c.get("innate_skills", []):
			t.ok(Content.has_entry("skills", s), "%s skill %s" % [cid, s])
		for slot: String in c.get("equip", {}).keys():
			var iid: String = c.equip[slot]
			t.ok(iid == "" or Content.has_entry("items", iid), "%s start gear %s" % [cid, iid])
		t.ok(ResourceLoader.exists("res://assets/portraits/%s_neutral.png" % c.sprite), "%s portrait" % cid)
		t.ok(ResourceLoader.exists("res://assets/sprites/chars/%s_battle.png" % c.sprite), "%s battle sheet" % cid)


func test_enemies_encounters_shops() -> void:
	for eid: String in Content.table("enemies").keys():
		var e: Dictionary = Content.enemy(eid)
		for r: Dictionary in e.get("ai", []):
			t.ok(Content.has_entry("skills", str(r.skill)), "%s ai skill %s" % [eid, r.skill])
		for ph: Dictionary in e.get("phases", []):
			for r: Dictionary in ph.get("ai", []):
				t.ok(Content.has_entry("skills", str(r.skill)), "%s phase skill %s" % [eid, r.skill])
		for d: Dictionary in e.get("drops", []):
			t.ok(Content.has_entry("items", str(d.item)), "%s drop %s" % [eid, d.item])
		t.ok(ResourceLoader.exists("res://assets/sprites/enemies/%s.png" % e.get("sprite", eid)), "%s sprite" % eid)
	for enc: String in Content.table("encounters").keys():
		for eid: String in Content.encounter(enc).get("enemies", []):
			t.ok(Content.has_entry("enemies", eid), "%s enemy %s" % [enc, eid])
		t.ok(Content.has_map(str(Content.encounter(enc).get("arena", ""))), "%s arena" % enc)
	for sh: String in Content.table("shops").keys():
		for iid: String in Content.shop(sh).get("items", []):
			t.ok(Content.has_entry("items", iid) and int(Content.item(iid).get("price", 0)) > 0, "%s sells priced %s" % [sh, iid])


func _check_event_cmds(eid: String, cmds: Array) -> void:
	for c: Variant in cmds:
		if not c is Dictionary:
			t.ok(false, "%s non-dict command" % eid)
			continue
		var known := false
		for k: String in (c as Dictionary).keys():
			if k in EVENT_KEYS:
				known = true
		t.ok(known, "%s command %s known" % [eid, str(c.keys())])
		if c.has("item"):
			t.ok(Content.has_entry("items", str(c.item)), "%s item %s" % [eid, c.item])
		if c.has("quest_start"):
			t.ok(Content.has_entry("quests", str(c.quest_start)), "%s quest %s" % [eid, c.quest_start])
		if c.has("quest_stage"):
			t.ok(Content.has_entry("quests", str(c.quest_stage[0])), "%s quest %s" % [eid, c.quest_stage[0]])
			t.ok(int(c.quest_stage[1]) < Content.quest(str(c.quest_stage[0])).get("stages", []).size(), "%s stage in range" % eid)
		if c.has("quest_complete"):
			t.ok(Content.has_entry("quests", str(c.quest_complete)), "%s quest %s" % [eid, c.quest_complete])
		if c.has("battle"):
			t.ok(Content.has_entry("encounters", str(c.battle)), "%s encounter %s" % [eid, c.battle])
			_check_event_cmds(eid, c.get("win", []))
			_check_event_cmds(eid, c.get("lose", []))
		if c.has("warp"):
			t.ok(Content.has_map(str(c.warp)), "%s warp %s" % [eid, c.warp])
		if c.has("join"):
			t.ok(Content.has_entry("characters", str(c.join)), "%s join %s" % [eid, c.join])
		if c.has("call"):
			t.ok(Content.has_event(str(c.call)), "%s call %s" % [eid, c.call])
		if c.has("shop"):
			t.ok(Content.has_entry("shops", str(c.shop)), "%s shop %s" % [eid, c.shop])
		if c.has("unlock_job"):
			t.ok(Content.has_entry("jobs", str(c.unlock_job)), "%s job %s" % [eid, c.unlock_job])
		if c.has("music"):
			t.ok(ResourceLoader.exists("res://assets/audio/music/%s.ogg" % c.music), "%s music %s" % [eid, c.music])
		if c.has("say") and str(c.say) != "":
			var w := str(c.say)
			t.ok(Content.has_entry("characters", w) or Content.has_entry("npcs", w), "%s speaker %s" % [eid, w])
		if c.has("choice"):
			for o: Dictionary in c.choice:
				_check_event_cmds(eid, o.get("do", []))
		if c.has("if"):
			_check_event_cmds(eid, c.get("then", []))
			_check_event_cmds(eid, c.get("else", []))


func test_events_valid() -> void:
	for eid: String in Content.all_event_ids():
		var ev: Variant = Content.event(eid)
		var cmds: Array = ev if ev is Array else ev.get("cmds", [])
		_check_event_cmds(eid, cmds)
		if ev is Dictionary and ev.get("skippable", false):
			t.ok(str(ev.get("recap", "")) != "", "%s skippable scenes need a recap" % eid)


func _bfs(m: Dictionary, grid: MapGrid, start: Vector2i, blockers: Dictionary) -> Dictionary:
	var seen := {start: true}
	var q: Array = [start]
	while not q.is_empty():
		var p: Vector2i = q.pop_front()
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := p + d
			if seen.has(n) or blockers.has(n) or not grid.can_step(p, n):
				continue
			seen[n] = true
			q.append(n)
	return seen


func test_maps_connected() -> void:
	var chest_ids := {}
	for mid: String in Content.map_ids():
		var m: Dictionary = Content.map(mid)
		t.ok(not m.is_empty(), "map %s loads" % mid)
		if mid.begins_with("arena_"):
			continue
		# Reachability assumes every conditional patch has been unlocked (doors,
		# drained channels); each patch's condition is set by some event.
		var pm := m.duplicate(true)
		var rows: Array = pm.get("rows", []).duplicate()
		for patch: Dictionary in m.get("patches", []):
			for i in patch.rows.size():
				var y: int = int(patch.at[1]) + i
				var r: String = rows[y]
				rows[y] = r.substr(0, int(patch.at[0])) + str(patch.rows[i]) + r.substr(int(patch.at[0]) + str(patch.rows[i]).length())
		pm["rows"] = rows
		var g := MapBuilder.parse_grid(pm)
		var blockers := {}
		for p: Dictionary in m.get("props", []):
			if p.get("solid", str(p.get("t")) in ["lamp", "tree", "barrel", "crate", "stall", "bench", "sign", "bell", "bell_shrine", "valve", "machine", "brazier", "table", "bed", "gear"]):
				blockers[Vector2i(int(p.at[0]), int(p.at[1]))] = true
		for ch: Dictionary in m.get("chests", []):
			blockers[Vector2i(int(ch.at[0]), int(ch.at[1]))] = true
			t.ok(not chest_ids.has(ch.id), "chest id %s unique" % ch.id)
			chest_ids[ch.id] = true
		for sname: String in m.get("spawns", {}).keys():
			var s: Array = m.spawns[sname]
			t.ok(g.is_walkable(int(s[0]), int(s[1])), "%s spawn %s walkable" % [mid, sname])
		var d: Array = m.spawns.get("default", [0, 0])
		var reach := _bfs(m, g, Vector2i(int(d[0]), int(d[1])), blockers)
		for tr: Dictionary in m.get("triggers", []):
			if str(tr.get("kind", "event")) == "exit":
				t.ok(Content.has_map(str(tr.to)), "%s exit to %s" % [mid, tr.to])
				var spn: String = tr.get("spawn", "")
				t.ok(spn == "" or Content.map(str(tr.to)).get("spawns", {}).has(spn), "%s exit spawn %s/%s" % [mid, tr.to, spn])
				if str(tr.get("on", "step")) == "step":
					var any := false
					for yy in int(tr.get("h", 1)):
						for xx in int(tr.get("w", 1)):
							if reach.has(Vector2i(int(tr.at[0]) + xx, int(tr.at[1]) + yy)):
								any = true
					t.ok(any or tr.has("cond"), "%s exit to %s reachable from default spawn" % [mid, tr.to])
			else:
				if tr.has("event"):
					t.ok(Content.has_event(str(tr.event)), "%s trigger event %s" % [mid, tr.event])
		for n: Dictionary in m.get("npcs", []):
			var talk: Variant = n.get("talk", "")
			if talk is Array:
				for e: Dictionary in talk:
					t.ok(Content.has_event(str(e.event)), "%s npc %s event %s" % [mid, n.id, e.event])
			elif str(talk) != "":
				t.ok(Content.has_event(str(talk)), "%s npc %s talk %s" % [mid, n.id, talk])
			t.ok(ResourceLoader.exists("res://assets/sprites/chars/%s_field.png" % n.get("sprite", "")), "%s npc sprite %s" % [mid, n.get("sprite")])
		for pt: Dictionary in m.get("party_talk", []):
			t.ok(Content.has_event(str(pt.event)), "%s party_talk %s" % [mid, pt.event])
		for e: Dictionary in m.get("encounters", {}).get("table", []):
			t.ok(Content.has_entry("encounters", str(e.enc)), "%s encounter %s" % [mid, e.enc])
		t.ok(m.get("music", "") == "" or ResourceLoader.exists("res://assets/audio/music/%s.ogg" % m.music), "%s music" % mid)


func test_required_main_quest_stages_set_by_events() -> void:
	# Every stage of each main quest must be reachable through some event command.
	var set_stages := {}
	for eid: String in Content.all_event_ids():
		_collect_stages(Content.event(eid), set_stages)
	for qid: String in Content.table("quests").keys():
		var q: Dictionary = Content.quest(qid)
		if str(q.type) != "main":
			continue
		for i in range(1, q.stages.size() - 1):
			t.ok(set_stages.has("%s:%d" % [qid, i]) or set_stages.has("%s:done" % qid), "%s stage %d is set somewhere" % [qid, i])
		t.ok(set_stages.has("%s:done" % qid), "%s can be completed" % qid)


func _collect_stages(v: Variant, out: Dictionary) -> void:
	if v is Dictionary:
		if v.has("quest_stage"):
			out["%s:%d" % [v.quest_stage[0], int(v.quest_stage[1])]] = true
		if v.has("quest_complete"):
			out["%s:done" % v.quest_complete] = true
		for k in v.keys():
			_collect_stages(v[k], out)
	elif v is Array:
		for x in v:
			_collect_stages(x, out)
