extends Node
## Local-only play report. Records where time goes (per area and per
## objective), battles, defeats, frame rate and settings changes, so a
## playtester can export or copy a summary and send it by hand. Nothing is
## ever sent over the network. Stored in user://playlog.json, separate from
## saves; can be turned off or cleared in the menu.

const PATH := "user://playlog.json"
const MAX_ENTRIES := 400
const LONG_OBJECTIVE_SECS := 480.0   # flagged as "possibly stuck" in the summary

var data: Dictionary = {}
var _battle_start_ms: int = 0
var _battle: Dictionary = {}
var _fps_t: float = 0.0
var _save_t: float = 0.0
var _dirty: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	_new_session()
	GameState.quest_updated.connect(_on_quest_updated)
	Settings.changed.connect(_on_setting)
	Router.battle_started.connect(_on_battle_started)
	Router.battle_finished.connect(_on_battle_finished)


func enabled() -> bool:
	return bool(Settings.get_value("play_report"))


func _empty() -> Dictionary:
	return {"version": 1, "created": int(Time.get_unix_time_from_system()), "sessions": [], "areas": {},
		"objectives": [], "battles": [], "defeats": [], "settings": [], "fps": {}}


func _load() -> void:
	data = _empty()
	if not FileAccess.file_exists(PATH):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if d is Dictionary and int((d as Dictionary).get("version", 0)) == 1:
		for k: String in data.keys():
			if (d as Dictionary).has(k) and typeof(d[k]) == typeof(data[k]):
				data[k] = d[k]


func save() -> void:
	if not _dirty:
		return
	_dirty = false
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()


func clear() -> void:
	data = _empty()
	_dirty = true
	_new_session()
	save()


func _push(key: String, entry: Dictionary) -> void:
	var arr: Array = data[key]
	arr.append(entry)
	while arr.size() > MAX_ENTRIES:
		arr.pop_front()
	_dirty = true


func _pt() -> int:
	return int(GameState.playtime)


func _new_session() -> void:
	if not enabled():
		return
	var screen := DisplayServer.screen_get_size()
	_push("sessions", {"start": int(Time.get_unix_time_from_system()),
		"build": str(ProjectSettings.get_setting("application/config/version", "")),
		"os": OS.get_name(), "web": OS.has_feature("web"),
		"mobile": OS.has_feature("web_android") or OS.has_feature("web_ios") or OS.has_feature("mobile"),
		"touch": DisplayServer.is_touchscreen_available(), "screen": [screen.x, screen.y],
		"renderer": str(RenderingServer.get_video_adapter_name()),
		"difficulty": Difficulty.level(), "encounters": str(Settings.get_value("encounters")),
		"characters": str(Settings.get_value("character_style")), "preset": str(Settings.get_value("visual_preset"))})


func _process(delta: float) -> void:
	if not enabled() or not GameState.active:
		return
	var w: Node = Router.world
	var in_field := w != null and is_instance_valid(w) and Router.battle == null and not get_tree().paused
	if in_field:
		var a: Dictionary = data.areas.get(GameState.map_id, {"secs": 0.0, "visits": 0})
		a.secs = float(a.secs) + minf(delta, 0.25)
		data.areas[GameState.map_id] = a
		_dirty = true
		_fps_t += delta
		if _fps_t >= 2.0:
			_fps_t = 0.0
			var fps := Engine.get_frames_per_second()
			var s: Dictionary = data.fps.get(GameState.map_id, {"sum": 0.0, "n": 0, "min": 9999.0})
			s.sum = float(s.sum) + fps
			s.n = int(s.n) + 1
			s.min = minf(float(s.min), fps)
			data.fps[GameState.map_id] = s
	_save_t += delta
	if _save_t >= 30.0:
		_save_t = 0.0
		save()


func note_map_entered(map_id: String) -> void:
	if not enabled():
		return
	var a: Dictionary = data.areas.get(map_id, {"secs": 0.0, "visits": 0})
	a.visits = int(a.visits) + 1
	data.areas[map_id] = a
	_dirty = true


func _on_quest_updated(qid: String) -> void:
	if not enabled():
		return
	var objs: Array = data.objectives
	for o: Dictionary in objs:
		if str(o.quest) == qid and int(o.end) < 0:
			o.end = _pt()
	var q: Dictionary = GameState.quests.get(qid, {})
	if q.is_empty() or bool(q.get("done", false)):
		_dirty = true
		save()
		return
	var stages: Array = Content.quest(qid).get("stages", [])
	var st := int(q.get("stage", 0))
	var text: String = str(stages[st].get("objective", "")) if st < stages.size() else ""
	_push("objectives", {"quest": qid, "stage": st, "text": text, "start": _pt(), "end": -1, "map": GameState.map_id})
	save()


func _on_setting(key: String) -> void:
	if not enabled() and key != "play_report":
		return
	if key in ["bindings", "music_volume", "sfx_volume"]:
		return
	_push("settings", {"key": key, "value": str(Settings.get_value(key)), "pt": _pt()})


func _on_battle_started(enc: String, opts: Dictionary) -> void:
	_battle_start_ms = Time.get_ticks_msec()
	var levels: Array = []
	for cid: String in GameState.party:
		levels.append(int(GameState.members[cid].level))
	_battle = {"enc": enc, "random": bool(opts.get("random", false)), "map": GameState.map_id, "pt": _pt(),
		"levels": levels, "difficulty": Difficulty.level()}


func _on_battle_finished(result: Dictionary) -> void:
	if not enabled() or _battle.is_empty():
		return
	var b := _battle.duplicate()
	b["outcome"] = str(result.get("outcome", "?"))
	b["secs"] = int((Time.get_ticks_msec() - _battle_start_ms) / 1000.0)
	_push("battles", b)
	if b.outcome == "defeat":
		_push("defeats", {"enc": b.enc, "map": b.map, "pt": b.pt, "levels": b.levels})
	_battle = {}
	save()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED,
			NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		save()


# ------------------------------------------------------------------ report

static func _clock(secs: float) -> String:
	var s := int(secs)
	return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60] if s >= 3600 else "%d:%02d" % [s / 60, s % 60]


func _map_name(mid: String) -> String:
	return str(Content.map(mid).get("name", mid)) if Content.has_map(mid) else mid


## Human-readable summary (what a playtester sends back).
func summary() -> String:
	var L: PackedStringArray = []
	L.append("ECHOES OF THE LAST DAWN — play report (local only)")
	var sess: Array = data.sessions
	if not sess.is_empty():
		var s: Dictionary = sess[sess.size() - 1]
		L.append("Build %s · %s%s · screen %sx%s · %s" % [s.get("build", "?"), s.get("os", "?"),
			" (browser, touch)" if bool(s.get("web")) and bool(s.get("touch")) else (" (browser)" if bool(s.get("web")) else ""),
			s.screen[0], s.screen[1], s.get("renderer", "")])
		L.append("Difficulty %s · random battles %s · characters %s · visual preset %s" % [s.get("difficulty", "?"),
			s.get("encounters", "?"), s.get("characters", "?"), s.get("preset", "?")])
	L.append("Sessions: %d · playtime %s · chapter %s" % [sess.size(), _clock(GameState.playtime), GameState.chapter])
	L.append("")
	L.append("TIME PER AREA")
	var areas: Array = data.areas.keys()
	areas.sort_custom(func(a: String, b: String) -> bool: return float(data.areas[a].secs) > float(data.areas[b].secs))
	for mid: String in areas.slice(0, 12):
		var a: Dictionary = data.areas[mid]
		L.append("  %-26s %8s  (%d visits)" % [_map_name(mid), _clock(float(a.secs)), int(a.visits)])
	L.append("")
	L.append("TIME PER OBJECTIVE  (* = over %d min: possibly stuck)" % int(LONG_OBJECTIVE_SECS / 60.0))
	for o: Dictionary in data.objectives:
		var end_pt := int(o.end) if int(o.end) >= 0 else _pt()
		var dur := float(end_pt - int(o.start))
		L.append("  %s %7s  %s%s" % ["*" if dur > LONG_OBJECTIVE_SECS else " ", _clock(dur), str(o.text),
			"" if int(o.end) >= 0 else "  (current)"])
	L.append("")
	var bats: Array = data.battles
	var wins := bats.filter(func(b: Dictionary) -> bool: return b.outcome == "victory").size()
	var esc := bats.filter(func(b: Dictionary) -> bool: return b.outcome == "escape").size()
	var losses := bats.filter(func(b: Dictionary) -> bool: return b.outcome == "defeat").size()
	var secs := 0
	for b: Dictionary in bats:
		secs += int(b.secs)
	L.append("BATTLES  %d fought · %d won · %d escaped · %d lost · avg %ds" % [bats.size(), wins, esc, losses,
		secs / maxi(1, bats.size())])
	for b: Dictionary in bats:
		if not bool(b.random):
			L.append("  story/boss %-22s %-8s %3ds  party Lv %s" % [b.enc, b.outcome, int(b.secs), str(b.levels)])
	if not (data.defeats as Array).is_empty():
		L.append("DEFEATS")
		for d: Dictionary in data.defeats:
			L.append("  %s in %s at %s, party Lv %s" % [d.enc, _map_name(str(d.map)), _clock(float(d.pt)), str(d.levels)])
	L.append("")
	if not (data.fps as Dictionary).is_empty():
		L.append("FRAME RATE (avg / lowest sample)")
		for mid: String in data.fps.keys():
			var f: Dictionary = data.fps[mid]
			L.append("  %-26s %3d / %3d fps" % [_map_name(mid), int(float(f.sum) / maxf(1.0, float(f.n))), int(f.min)])
		L.append("")
	if not (data.settings as Array).is_empty():
		L.append("SETTINGS CHANGED")
		for c: Dictionary in (data.settings as Array).slice(-20):
			L.append("  %s -> %s at %s" % [c.key, c.value, _clock(float(c.pt))])
	return "\n".join(L)


## Full report: summary followed by the raw data, for exporting.
func full_report() -> String:
	return summary() + "\n\n--- raw data (JSON) ---\n" + JSON.stringify(data, " ")
