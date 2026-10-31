class_name Nav
extends RefCounted
## Wayfinding over content data. Works out where the tracked objective is by
## finding the event that advances the quest to its next stage and where that
## event can be triggered (map triggers, NPC talk, map auto-events, and any
## event that `call`s it), then routes between maps through exit triggers.
## A stage may override this with "target": {"map": id, "at": [x, y]}.

static var _built: bool = false
static var _event_locs: Dictionary = {}   # event id -> Array of {map, at (Vector2i or null), cond, npc}
static var _callers: Dictionary = {}      # event id -> Array of caller event ids
static var _advancers: Dictionary = {}    # "qid#stage" -> Array of event ids that set that stage
static var _exits: Dictionary = {}        # map id -> Array of {to, at, w, h, cond}
static var _names: Dictionary = {}        # map id -> display name
static var _warps: Dictionary = {}        # event id -> Array of destination map ids


static func build() -> void:
	if _built:
		return
	_built = true
	for mid: String in Content.map_ids():
		var m: Dictionary = Content.map(mid)
		_names[mid] = str(m.get("name", mid))
		if mid.begins_with("arena_"):
			continue
		var ex: Array = []
		for t: Dictionary in m.get("triggers", []):
			var at := Vector2i(int(t.at[0]), int(t.at[1]))
			if str(t.get("kind", "event")) == "exit":
				ex.append({"to": str(t.to), "at": at, "w": int(t.get("w", 1)), "h": int(t.get("h", 1)),
					"cond": t.get("cond", ""), "door": str(t.get("on", "step")) == "interact"})
			elif t.has("event"):
				_add_loc(str(t.event), {"map": mid, "at": at, "cond": t.get("cond", ""), "npc": ""})
		_exits[mid] = ex
		for n: Dictionary in m.get("npcs", []):
			var talk: Variant = n.get("talk", "")
			var entries: Array = talk if talk is Array else ([{"event": talk}] if str(talk) != "" else [])
			for e: Dictionary in entries:
				var conds: Array = []
				for c: Variant in [n.get("cond", ""), e.get("cond", "")]:
					if str(c) != "":
						conds.append(c)
				_add_loc(str(e.event), {"map": mid, "at": Vector2i(int(n.at[0]), int(n.at[1])),
					"cond": conds, "npc": str(n.id)})
		for a: Dictionary in m.get("auto_events", []):
			_add_loc(str(a.event), {"map": mid, "at": null, "cond": a.get("cond", ""), "npc": ""})
	for eid: String in Content.all_event_ids():
		var ev: Variant = Content.event(eid)
		var cmds: Array = ev if ev is Array else (ev.get("cmds", []) if ev is Dictionary else [])
		_scan(eid, cmds)
	# Scripted passages (a hatch, a lift, a train) count as exits for routing.
	for eid: String in _warps.keys():
		for loc: Dictionary in event_locations(eid):
			if loc.at == null or not _exits.has(str(loc.map)):
				continue
			for to: String in _warps[eid]:
				if to == str(loc.map):
					continue
				var dup := false
				for e: Dictionary in _exits[loc.map]:
					if str(e.to) == to and e.at == loc.at:
						dup = true
				if not dup:
					(_exits[loc.map] as Array).append({"to": to, "at": loc.at, "w": 1, "h": 1, "cond": loc.cond,
						"door": true, "event": true, "npc": str(loc.npc)})


static func _add_loc(eid: String, loc: Dictionary) -> void:
	if not _event_locs.has(eid):
		_event_locs[eid] = []
	(_event_locs[eid] as Array).append(loc)


static func _scan(eid: String, cmds: Array) -> void:
	for c: Variant in cmds:
		if not c is Dictionary:
			continue
		var d: Dictionary = c
		if d.has("call"):
			var callee := str(d.call)
			if not _callers.has(callee):
				_callers[callee] = []
			(_callers[callee] as Array).append(eid)
		if d.has("quest_stage") and d.quest_stage is Array and (d.quest_stage as Array).size() >= 2:
			_add_adv(str(d.quest_stage[0]), int(d.quest_stage[1]), eid)
		if d.has("warp") and Content.has_map(str(d.warp)) and not str(d.warp).begins_with("arena_"):
			if not _warps.has(eid):
				_warps[eid] = []
			if not str(d.warp) in _warps[eid]:
				(_warps[eid] as Array).append(str(d.warp))
		if d.has("quest_complete"):
			var qid := str(d.quest_complete)
			_add_adv(qid, maxi(0, Content.quest(qid).get("stages", []).size() - 1), eid)
		for sub: String in ["then", "else", "win", "lose"]:
			if d.get(sub) is Array:
				_scan(eid, d[sub])
		if d.get("choice") is Array:
			for o: Variant in d.choice:
				if o is Dictionary and (o as Dictionary).get("do") is Array:
					_scan(eid, o.do)


static func _add_adv(qid: String, stage: int, eid: String) -> void:
	var k := "%s#%d" % [qid, stage]
	if not _advancers.has(k):
		_advancers[k] = []
	if not eid in _advancers[k]:
		(_advancers[k] as Array).append(eid)


## All places an event can start from, following `call` chains upward.
static func event_locations(eid: String) -> Array:
	build()
	var out: Array = []
	var seen := {}
	var stack: Array = [eid]
	while not stack.is_empty():
		var e: String = stack.pop_back()
		if seen.has(e):
			continue
		seen[e] = true
		out.append_array(_event_locs.get(e, []))
		stack.append_array(_callers.get(e, []))
	return out


static func map_name(mid: String) -> String:
	build()
	return str(_names.get(mid, Content.map(mid).get("name", mid)))


static func exits(mid: String) -> Array:
	build()
	return _exits.get(mid, [])


## Candidate locations for the tracked quest's current objective.
static func objective_locations(qid: String) -> Array:
	build()
	if qid == "" or not GameState.quests.has(qid) or bool(GameState.quests[qid].get("done", false)):
		return []
	var stages: Array = Content.quest(qid).get("stages", [])
	var s := GameState.quest_stage(qid)
	if s >= 0 and s < stages.size() and stages[s] is Dictionary and (stages[s] as Dictionary).has("target"):
		var t: Dictionary = stages[s].target
		var at: Variant = Vector2i(int(t.at[0]), int(t.at[1])) if t.has("at") else null
		return [{"map": str(t.map), "at": at, "cond": "", "npc": str(t.get("npc", ""))}]
	for nxt in range(s + 1, maxi(s + 2, stages.size())):
		var evs: Array = _advancers.get("%s#%d" % [qid, nxt], [])
		var locs: Array = []
		for eid: String in evs:
			locs.append_array(event_locations(eid))
		if not locs.is_empty():
			var live := locs.filter(func(l: Dictionary) -> bool: return GameState.check(l.cond))
			return live if not live.is_empty() else locs
	return []


## Resolves the objective relative to the current map. Returns {} when unknown,
## else {map, at (Vector2i or null), npc, here: bool, exit: Dictionary (first hop
## when the objective is on another map), hops}.
static func resolve(qid: String, from_map: String) -> Dictionary:
	var locs := objective_locations(qid)
	if locs.is_empty():
		return {}
	var best: Dictionary = {}
	var best_hops := 1 << 20
	for l: Dictionary in locs:
		if str(l.map) == from_map:
			return {"map": from_map, "at": l.at, "npc": l.npc, "here": true, "exit": {}, "hops": 0}
		var route := route_first_exit(from_map, str(l.map))
		if not route.is_empty() and int(route.hops) < best_hops:
			best_hops = int(route.hops)
			best = {"map": l.map, "at": l.at, "npc": l.npc, "here": false, "exit": route.exit, "hops": route.hops}
	return best


## Breadth-first search across exits whose conditions currently pass.
static func route_first_exit(from_map: String, to_map: String) -> Dictionary:
	build()
	var first := {from_map: {}}
	var hops := {from_map: 0}
	var queue: Array = [from_map]
	while not queue.is_empty():
		var m: String = queue.pop_front()
		if m == to_map:
			return {"exit": first[m], "hops": hops[m]}
		for e: Dictionary in _exits.get(m, []):
			var to := str(e.to)
			if first.has(to) or not GameState.check(e.cond):
				continue
			first[to] = e if m == from_map else first[m]
			hops[to] = int(hops[m]) + 1
			queue.append(to)
	return {}
