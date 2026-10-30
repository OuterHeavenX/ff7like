class_name EventRunner
extends Node
## Executes authored event scripts (JSON command lists). The vocabulary is a
## fixed set of operations — no arbitrary code — and every state effect is
## either idempotent or guarded by the reward ledger. Scenes can be skipped:
## skipping applies state effects silently, stops at choices, and shows the recap.

signal finished

var world: Node
var dialogue: Node
var running: bool = false
var skipping: bool = false
var _skip_asked: bool = false
var _current_id: String = ""
var _depth: int = 0
var _abort: bool = false


## Stops the current script (used when the player loads a save mid-event).
func abort() -> void:
	_abort = true
	if dialogue and dialogue.is_open():
		dialogue.close()


func run(eid: String) -> void:
	var ev: Variant = Content.event(eid)
	if ev == null:
		push_warning("event not found: " + eid)
		return
	var cmds: Array = ev if ev is Array else ev.get("cmds", [])
	var top := _depth == 0
	if top:
		running = true
		_abort = false
		skipping = false
		_skip_asked = false
		_current_id = eid
	_depth += 1
	await _exec_list(cmds)
	_depth -= 1
	if top:
		if _abort:
			_abort = false
			running = false
			finished.emit()
			return
		if skipping:
			skipping = false
			var recap: String = ev.get("recap", "") if ev is Dictionary else ""
			if recap != "":
				await dialogue.narrate("Scene skipped.\n\n" + recap)
		if dialogue.is_open():
			dialogue.close()
		running = false
		finished.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not running or skipping or _skip_asked:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("menu"):
		var ev: Variant = Content.event(_current_id)
		if ev is Dictionary and ev.get("skippable", false):
			get_viewport().set_input_as_handled()
			_ask_skip()


func _ask_skip() -> void:
	_skip_asked = true
	var idx: int = await dialogue.choose_overlay("Skip this scene? A short recap will be shown.", ["Keep watching", "Skip scene"])
	if idx == 1:
		skipping = true
		dialogue.abort_line()
	_skip_asked = false


func _exec_list(cmds: Array) -> void:
	for c: Variant in cmds:
		if _abort:
			return
		if not c is Dictionary:
			continue
		await _exec(c)
		if not is_inside_tree():
			return


func sub(text: String) -> String:
	## Party-aware substitutions: {lead}, {name:id}, {p:a|b|c}, {gold}, {sister}
	var out := text
	if not out.contains("{"):
		return out
	out = out.replace("{lead}", Content.character(GameState.lead()).get("name", "Rowan"))
	out = out.replace("{gold}", str(GameState.gold))
	out = out.replace("{sister}", "Wren")
	var re := RegEx.new()
	re.compile("\\{name:([a-z_]+)\\}")
	for m in re.search_all(out):
		out = out.replace(m.get_string(0), _speaker_name(m.get_string(1)))
	re.compile("\\{p:([a-z_|]+)\\}")
	for m in re.search_all(out):
		var pick := ""
		for cid in m.get_string(1).split("|"):
			if GameState.in_party(cid):
				pick = _speaker_name(cid)
				break
		if pick == "":
			pick = _speaker_name(GameState.lead())
		out = out.replace(m.get_string(0), pick)
	return out


func _speaker_name(who: String) -> String:
	if who == "":
		return ""
	if Content.has_entry("characters", who):
		return str(Content.character(who).get("name", who))
	if Content.has_entry("npcs", who):
		return str(Content.npc(who).get("name", who))
	return who


func _portrait(who: String, expr: String) -> Texture2D:
	var base := who
	if Content.has_entry("characters", who):
		base = str(Content.character(who).get("sprite", who))
	elif Content.has_entry("npcs", who):
		base = str(Content.npc(who).get("portrait", ""))
	if base == "":
		return null
	var path := "res://assets/portraits/%s_%s.png" % [base, expr if expr != "" else "neutral"]
	if ResourceLoader.exists(path):
		return load(path)
	path = "res://assets/portraits/%s_neutral.png" % base
	return load(path) if ResourceLoader.exists(path) else null


func _say(who: String, text: String, expr: String = "") -> void:
	if skipping:
		return
	await dialogue.say(_speaker_name(who), sub(text), _portrait(who, expr))


func _exec(c: Dictionary) -> void:
	if c.has("cond") and not GameState.check(c.cond):
		return
	if c.has("say"):
		await _say(str(c.say), str(c.get("text", "")), str(c.get("expr", "")))
	elif c.has("party_say"):
		var spoke := false
		for line: Dictionary in c.party_say:
			if GameState.in_party(str(line.who)):
				await _say(str(line.who), str(line.text), str(line.get("expr", "")))
				spoke = true
				break
		if not spoke and c.has("fallback"):
			await _say(str(c.fallback.who), str(c.fallback.text), str(c.fallback.get("expr", "")))
	elif c.has("narrate"):
		if not skipping:
			await dialogue.narrate(sub(str(c.narrate)))
	elif c.has("choice"):
		var opts: Array = []
		var labels: Array = []
		for o: Dictionary in c.choice:
			if GameState.check(o.get("cond", "")):
				opts.append(o)
				labels.append(sub(str(o.text)))
		if opts.is_empty():
			return
		skipping = false   # choices always require the player
		var idx: int = await dialogue.choose(sub(str(c.get("prompt", ""))), labels, _portrait(str(c.get("who", "")), ""), _speaker_name(str(c.get("who", ""))))
		var chosen: Dictionary = opts[clampi(idx, 0, opts.size() - 1)]
		if chosen.has("flag"):
			GameState.set_flag(str(chosen.flag))
		await _exec_list(chosen.get("do", []))
	elif c.has("if"):
		if GameState.check(c["if"]):
			await _exec_list(c.get("then", []))
		else:
			await _exec_list(c.get("else", []))
	elif c.has("flag"):
		GameState.set_flag(str(c.flag), c.get("value", true))
	elif c.has("item"):
		var q := int(c.get("qty", 1))
		var key: String = c.get("once", "")
		if key != "":
			if GameState.granted.has(key):
				return
			GameState.granted[key] = true
		if q >= 0:
			GameState.add_item(str(c.item), q)
			if not skipping and not c.get("silent", false):
				Audio.sfx("item")
				Router.toast("Received %s x%d" % [Content.item(str(c.item)).get("name", c.item), q])
		else:
			GameState.remove_item(str(c.item), -q)
	elif c.has("gold"):
		var key2: String = c.get("once", "")
		if key2 != "":
			if GameState.granted.has(key2):
				return
			GameState.granted[key2] = true
		GameState.add_gold(int(c.gold))
		if not skipping and int(c.gold) > 0:
			Audio.sfx("coin")
			Router.toast("Received %d crowns" % int(c.gold))
	elif c.has("join"):
		GameState.join_member(str(c.join), skipping)
		if not skipping:
			Audio.sfx("levelup")
	elif c.has("leave"):
		GameState.leave_member(str(c.leave))
	elif c.has("require_party"):
		GameState.set_flag("party_required", c.require_party)
	elif c.has("quest_start"):
		GameState.start_quest(str(c.quest_start))
	elif c.has("quest_stage"):
		GameState.set_quest_stage(str(c.quest_stage[0]), int(c.quest_stage[1]))
	elif c.has("quest_complete"):
		GameState.complete_quest(str(c.quest_complete), str(c.get("outcome", "")))
	elif c.has("battle"):
		await _battle(c)
	elif c.has("move"):
		var a: FieldActor = world.actor(str(c.move))
		if a:
			if skipping:
				var last: Array = c.path[c.path.size() - 1]
				var p := Vector2i(int(last[0]), int(last[1]))
				world.occupied.erase(a.grid_pos)
				a.place(p, world.grid.stand_height(p.x, p.y))
				if a != world.player:
					world.occupied[p] = a.actor_id
				else:
					GameState.map_pos = p
			elif c.get("wait", true):
				await world.move_actor(a, c.path, float(c.get("speed", 3.5)))
			else:
				world.move_actor(a, c.path, float(c.get("speed", 3.5)))
	elif c.has("face"):
		var a2: FieldActor = world.actor(str(c.face))
		if a2:
			if c.has("toward"):
				var other: FieldActor = world.actor(str(c.toward))
				if other:
					a2.face_toward(other.grid_pos)
			else:
				a2.face(FieldActor.facing_from_name(str(c.get("dir", "down"))))
	elif c.has("emote"):
		var a3: FieldActor = world.actor(str(c.emote))
		if a3 and not skipping:
			a3.show_emote(str(c.get("text", "!")))
			Audio.sfx("talk", 1.4)
	elif c.has("refresh_map"):
		world.load_map_keep_player()
	elif c.has("refresh_npcs"):
		world.refresh_npcs()
	elif c.has("remove_npc"):
		world.remove_npc(str(c.remove_npc))
	elif c.has("wait"):
		if not skipping:
			await get_tree().create_timer(float(c.wait)).timeout
	elif c.has("fade"):
		if not skipping:
			if str(c.fade) == "out":
				await Router.fade_out(float(c.get("time", 0.4)))
			else:
				await Router.fade_in(float(c.get("time", 0.4)))
	elif c.has("warp"):
		await Router.enter_world(str(c.warp), str(c.get("spawn", "")))
	elif c.has("music"):
		Audio.play_music(str(c.music))
	elif c.has("sfx"):
		if not skipping:
			Audio.sfx(str(c.sfx))
	elif c.has("shake"):
		if not skipping and bool(Settings.get_value("camera_shake")) and not bool(Settings.get_value("reduce_motion")):
			await _shake(float(c.shake))
	elif c.has("flash"):
		if not skipping and not bool(Settings.get_value("reduce_flashing")):
			await dialogue.flash(Color(c.flash[0], c.flash[1], c.flash[2]))
	elif c.has("title_card"):
		if not skipping:
			await dialogue.title_card(sub(str(c.title_card)), sub(str(c.get("sub", ""))))
	elif c.has("shop"):
		if not skipping:
			await world.hud.open_shop(str(c.shop))
	elif c.has("inn"):
		if not skipping:
			await _inn(int(c.inn))
	elif c.has("save_menu"):
		if not skipping:
			await world.hud.open_save_menu()
	elif c.has("heal"):
		GameState.heal_all()
		if not skipping:
			Audio.sfx("heal")
	elif c.has("unlock_job"):
		GameState.unlock_job(str(c.unlock_job), skipping)
	elif c.has("learn"):
		var who: String = c.learn[0]
		if GameState.members.has(who) and not str(c.learn[1]) in GameState.members[who].learned:
			GameState.members[who].learned.append(str(c.learn[1]))
	elif c.has("set_chapter"):
		GameState.chapter = str(c.set_chapter)
	elif c.has("call"):
		await run(str(c.call))
	elif c.has("autosave"):
		GameState.set_flag("autosave_enabled")
		Saves.autosave()
	elif c.has("tutorial"):
		if not skipping:
			await dialogue.tutorial(str(c.get("title", "Tip")), sub(str(c.tutorial)))
	elif c.has("open_menu"):
		if not skipping:
			await world.open_menu(str(c.open_menu))
	elif c.has("camera"):
		pass   # camera follows the player; reserved for authored pans
	elif c.has("end_slice"):
		await _end_slice()
	else:
		push_warning("Unknown event command: %s" % str(c.keys()))


func _battle(c: Dictionary) -> void:
	var opts := {"can_escape": not c.get("no_escape", true), "defeat_continues": c.get("lose_ok", false),
		"music": c.get("music", ""), "intro": c.get("intro", ""), "boss": c.get("boss", false)}
	var was_skipping := skipping
	skipping = false
	var res: Dictionary = await world.start_battle(str(c.battle), opts)
	skipping = was_skipping and false
	if res.get("outcome") == "abandoned":
		_abort = true
	elif res.get("outcome") == "victory":
		await _exec_list(c.get("win", []))
	else:
		await _exec_list(c.get("lose", []))


func _inn(price: int) -> void:
	var idx: int = await dialogue.choose("Rest for the night? (%d crowns — restores HP and SP)" % price, ["Rest", "Not now"])
	if idx != 0:
		return
	if not GameState.spend_gold(price):
		await dialogue.say_simple("", "You don't have enough crowns.")
		return
	await Router.fade_out(0.6)
	GameState.heal_all()
	Audio.sfx("heal")
	await get_tree().create_timer(0.6).timeout
	await Router.fade_in(0.6)
	await dialogue.say_simple("", "The party feels rested.")
	await world.hud.open_save_menu()


func _shake(strength: float) -> void:
	var cam: Camera3D = world.camera
	for i in 10:
		cam.h_offset = randf_range(-strength, strength) * 0.1
		cam.v_offset = randf_range(-strength, strength) * 0.1
		await get_tree().process_frame
		await get_tree().process_frame
	cam.h_offset = 0.0
	cam.v_offset = 0.0


func _end_slice() -> void:
	GameState.set_flag("slice_complete")
	Saves.autosave()
	await dialogue.title_card("End of Chapter One", "Bellweather")
	await dialogue.narrate("Thank you for playing this build of Echoes of the Last Dawn.\n\nChapter Two, \"The Rainward Line\", is not yet built. Your progress has been autosaved; the journal records where the story continues.\n\nYou may keep exploring Bellweather, take on remaining side quests, or return to the title.")
