extends RefCounted
## Local play report: records objectives, battles and areas; summary and
## export text; clearing; respects the off switch.

var t: Node


func _fresh() -> void:
	Settings.values["play_report"] = true
	PlayLog.data = PlayLog._empty()
	GameState.new_game()
	GameState.active = true


func test_objectives_record_durations() -> void:
	_fresh()
	GameState.playtime = 10.0
	GameState.start_quest("mq_sealed_fork")
	GameState.playtime = 700.0
	GameState.set_quest_stage("mq_sealed_fork", 1)
	var objs: Array = PlayLog.data.objectives
	t.eq(objs.size(), 2, "two objectives recorded")
	t.eq(int(objs[0].end) - int(objs[0].start), 690, "first objective lasted 690 s")
	t.eq(int(objs[1].end), -1, "current objective still open")
	var s := PlayLog.summary()
	t.ok(s.contains("Pick up tonight's delivery"), "summary lists objective text")
	t.ok(s.contains("*"), "long objective flagged as possibly stuck")


func test_battles_and_defeats() -> void:
	_fresh()
	Router.battle_started.emit("uc_rats", {"random": true})
	Router.battle_finished.emit({"outcome": "victory"})
	Router.battle_started.emit("boss_clapper", {})
	Router.battle_finished.emit({"outcome": "defeat"})
	t.eq((PlayLog.data.battles as Array).size(), 2, "two battles logged")
	t.eq((PlayLog.data.defeats as Array).size(), 1, "defeat logged")
	var s := PlayLog.summary()
	t.ok(s.contains("2 fought") and s.contains("1 lost"), "battle totals in summary")
	t.ok(s.contains("boss_clapper"), "boss result listed")


func test_area_visits_and_report_text() -> void:
	_fresh()
	PlayLog.note_map_entered("bellweather_wick")
	PlayLog.note_map_entered("bellweather_wick")
	t.eq(int(PlayLog.data.areas.bellweather_wick.visits), 2, "visits counted")
	var full := PlayLog.full_report()
	t.ok(full.contains("--- raw data (JSON) ---"), "export includes raw data")
	var raw := full.substr(full.find("{"))
	t.ok(JSON.parse_string(raw) is Dictionary, "raw data section is valid JSON")


func test_off_switch_and_clear() -> void:
	_fresh()
	Settings.values["play_report"] = false
	Router.battle_started.emit("uc_rats", {})
	Router.battle_finished.emit({"outcome": "victory"})
	PlayLog.note_map_entered("bellweather_wick")
	t.eq((PlayLog.data.battles as Array).size(), 0, "nothing recorded when off")
	t.ok(not (PlayLog.data.areas as Dictionary).has("bellweather_wick"), "no area data when off")
	Settings.values["play_report"] = true
	Router.battle_started.emit("uc_rats", {})
	Router.battle_finished.emit({"outcome": "victory"})
	PlayLog.clear()
	t.eq((PlayLog.data.battles as Array).size(), 0, "clear empties the log")
