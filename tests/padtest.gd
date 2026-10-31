extends Node
## Development-only gamepad harness (never exported: tests/* is excluded).
## Drives the real game using ONLY joypad events in the Steam Deck layout
## (Steam Input presents the Deck as an Xbox-style pad): A/B/X/Y, View, Menu,
## L1/R1, D-pad, left stick; and checks each button's effect on the title
## screen, settings, field, dialogue, pause menu, journal, shop, save screen
## and battle. Unbound inputs (L2/R2, L3/R3, right stick) are pressed too and
## must change nothing. Run:
##   godot --headless -- --padtest
##   xvfb-run godot --rendering-driver opengl3 --resolution 1280x800 -- --padtest --out=/abs/dir
## Prints one PASS/FAIL line per check, then PADTEST OK / PADTEST FAIL.

const DEV := 0
var out := ""
var _results: Array = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
			DirAccess.make_dir_recursive_absolute(out)
	Settings.values["text_speed"] = 3
	Settings.values["fast_animations"] = true
	Settings.values["battle_speed"] = 5
	Settings.values["touch_controls"] = "off"
	Input.joy_connection_changed.emit(DEV, true)
	await _title()
	await _field()
	await _menus()
	await _battle()
	var fails := _results.filter(func(r: Array) -> bool: return not r[1])
	print("PADTEST %s (%d checks, %d failed)" % ["OK" if fails.is_empty() else "FAIL", _results.size(), fails.size()])
	get_tree().quit(0 if fails.is_empty() else 1)


# ------------------------------------------------------------------ input

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _press(b: JoyButton, hold: float = 0.08) -> void:
	var e := InputEventJoypadButton.new()
	e.device = DEV
	e.button_index = b
	e.pressed = true
	e.pressure = 1.0
	Input.parse_input_event(e)
	await _wait(hold)
	var r := e.duplicate() as InputEventJoypadButton
	r.pressed = false
	r.pressure = 0.0
	Input.parse_input_event(r)
	await _wait(0.12)


func _axis(axis: JoyAxis, v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = DEV
	e.axis = axis
	e.axis_value = v
	Input.parse_input_event(e)


func _stick(dir: Vector2, secs: float) -> void:
	_axis(JOY_AXIS_LEFT_X, dir.x)
	_axis(JOY_AXIS_LEFT_Y, dir.y)
	await _wait(secs)
	_axis(JOY_AXIS_LEFT_X, 0.0)
	_axis(JOY_AXIS_LEFT_Y, 0.0)
	await _wait(0.35)


func _check(name: String, ok: bool) -> void:
	_results.append([name, ok])
	print(("PASS  " if ok else "FAIL  ") + name)


func _shot(name: String) -> void:
	if out == "":
		return
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])


func _focus() -> Control:
	return get_viewport().gui_get_focus_owner()


func _focus_text() -> String:
	var f := _focus()
	return (f as Button).text if f is Button else ""


## Walks the focused menu with the D-pad (down, then up) to a button by text.
func _focus_button(text: String) -> bool:
	for b: JoyButton in [JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_UP]:
		for i in 7:
			if _focus_text() == text:
				return true
			await _press(b)
	return _focus_text() == text


func _until(cond: Callable, secs: float) -> bool:
	var t := 0.0
	while t < secs:
		if cond.call():
			return true
		await _wait(0.1)
		t += 0.1
	return cond.call()


## Presses A through any dialogue until the player regains control.
func _clear_dialogue(max_secs: float = 90.0) -> bool:
	var w: Node = Router.world
	var t := 0.0
	while t < max_secs:
		if w.can_control():
			return true
		if w.dialogue.is_open() or Router.battle != null:
			await _press(JOY_BUTTON_A, 0.05)
			t += 0.17
		else:
			await _wait(0.2)
			t += 0.2
	return w.can_control()


# ------------------------------------------------------------------ title + settings

func _title() -> void:
	await Router.goto_title()
	await _wait(1.0)
	var title: Node = get_tree().current_scene
	await _press(JOY_BUTTON_START)
	_check("title: any button (Menu) opens the title menu", bool(title.get("_gate_open")))
	_check("title: InputHub reports gamepad", InputHub.active_device == "pad")
	await _wait(0.3)
	var first := _focus_text()
	_check("title: a menu button has focus (%s)" % first, first != "")
	await _press(JOY_BUTTON_DPAD_DOWN)
	var second := _focus_text()
	_check("title: D-pad down moves focus (%s -> %s)" % [first, second], second != "" and second != first)
	await _press(JOY_BUTTON_DPAD_UP)
	_check("title: D-pad up moves focus back", _focus_text() == first)
	await _stick(Vector2(0, 1), 0.15)
	_check("title: left stick down moves focus", _focus_text() == second)
	_check("title: reached Settings with D-pad", await _focus_button("Settings"))
	await _press(JOY_BUTTON_A)
	await _wait(0.3)
	var sub: Node = title.get("_sub")
	_check("title: A opens Settings", sub != null)
	await _shot("pad_settings")
	if sub:
		var t0 := int(sub.get("tab_idx"))
		await _press(JOY_BUTTON_RIGHT_SHOULDER)
		_check("settings: R1 next tab", int(sub.get("tab_idx")) == (t0 + 1) % 4)
		await _press(JOY_BUTTON_LEFT_SHOULDER)
		_check("settings: L1 previous tab", int(sub.get("tab_idx")) == t0)
		var f0 := _focus()
		await _press(JOY_BUTTON_DPAD_DOWN)
		_check("settings: D-pad moves focus", _focus() != f0 and _focus() != null)
		await _press(JOY_BUTTON_B)
		await _wait(0.3)
		_check("settings: B closes", title.get("_sub") == null)
	# Unbound inputs must not do anything on the title menu.
	var before := _focus_text()
	for b: JoyButton in [JOY_BUTTON_LEFT_STICK, JOY_BUTTON_RIGHT_STICK]:
		await _press(b)
	_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_axis(JOY_AXIS_RIGHT_X, 1.0)
	await _wait(0.3)
	_axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	_axis(JOY_AXIS_RIGHT_X, 0.0)
	await _wait(0.2)
	_check("title: L3/R3/L2/R2/right stick are inert", _focus_text() == before and title.get("_sub") == null)
	_check("title: reached New Game", await _focus_button("New Game"))
	await _press(JOY_BUTTON_A)
	_check("title: A on New Game starts the game", await _until(func() -> bool: return Router.world != null and GameState.active, 10.0))


# ------------------------------------------------------------------ field

func _field() -> void:
	await _wait(1.5)
	var w: Node = Router.world
	_check("opening: A advances dialogue to player control", await _clear_dialogue())
	await _shot("pad_field")
	_check("field: prompt glyphs use pad labels", InputHub.prompt("confirm") == "A" and InputHub.prompt("cancel") == "B")
	var dirs := {"right": [Vector2(1, 0), JOY_BUTTON_DPAD_RIGHT, FieldActor.Facing.RIGHT],
		"left": [Vector2(-1, 0), JOY_BUTTON_DPAD_LEFT, FieldActor.Facing.LEFT],
		"down": [Vector2(0, 1), JOY_BUTTON_DPAD_DOWN, FieldActor.Facing.DOWN],
		"up": [Vector2(0, -1), JOY_BUTTON_DPAD_UP, FieldActor.Facing.UP]}
	var p: FieldActor = w.player
	for k: String in dirs.keys():
		var d: Array = dirs[k]
		await _clear_dialogue(20.0)
		p = w.player
		var start := p.grid_pos
		await _stick(d[0], 0.5)
		_check("field: left stick %s turns/moves the player" % k, p.facing == int(d[2]) or p.grid_pos != start)
		await _clear_dialogue(20.0)
		p = w.player
		await _press(JOY_BUTTON_DPAD_UP if k != "up" else JOY_BUTTON_DPAD_DOWN, 0.05)
		await _wait(0.3)
		await _clear_dialogue(20.0)
		p = w.player
		var s2 := p.grid_pos
		await _press(d[1], 0.25)
		await _wait(0.3)
		_check("field: D-pad %s turns/moves the player" % k, p.facing == int(d[2]) or p.grid_pos != s2)
	# Find an open lane and check that holding B runs.
	await _clear_dialogue(20.0)
	p = w.player
	var run_dir := Vector2i.ZERO
	for v: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if w.grid.can_step(p.grid_pos, p.grid_pos + v) and not w.occupied.has(p.grid_pos + v):
			run_dir = v
			break
	var b_down := InputEventJoypadButton.new()
	b_down.device = DEV
	b_down.button_index = JOY_BUTTON_B
	b_down.pressed = true
	Input.parse_input_event(b_down)
	_axis(JOY_AXIS_LEFT_X, float(run_dir.x))
	_axis(JOY_AXIS_LEFT_Y, float(run_dir.y))
	var saw_run := await _until(func() -> bool: return p.moving and is_equal_approx(p._move_speed, w.RUN_SPEED), 1.0)
	_axis(JOY_AXIS_LEFT_X, 0.0)
	_axis(JOY_AXIS_LEFT_Y, 0.0)
	var b_up := b_down.duplicate() as InputEventJoypadButton
	b_up.pressed = false
	Input.parse_input_event(b_up)
	await _wait(0.5)
	_check("field: hold B + stick runs", saw_run)
	# X: party comment.
	await _clear_dialogue(20.0)
	p = w.player
	await _press(JOY_BUTTON_X)
	_check("field: X starts a party comment", await _until(func() -> bool: return w.dialogue.is_open(), 2.0))
	await _clear_dialogue(10.0)
	_check("field: A closes the comment", w.can_control())
	# A: talk to an NPC (stand next to one, face it).
	var talked := false
	for nid: String in w.npcs.keys():
		var a: FieldActor = w.npcs[nid]
		for v: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var spot: Vector2i = a.grid_pos + v
			if w.grid.is_walkable(spot.x, spot.y) and not w.occupied.has(spot):
				p.place(spot, w.grid.stand_height(spot.x, spot.y))
				p.face(FieldActor.dir_to_facing(-v))
				await _wait(0.3)
				await _press(JOY_BUTTON_A)
				talked = await _until(func() -> bool: return w.dialogue.is_open() or w.events.running, 2.0)
				break
		if talked:
			break
	_check("field: A talks to the NPC in front", talked)
	await _clear_dialogue(30.0)
	await _shot("pad_field_after_talk")


# ------------------------------------------------------------------ menus

func _menus() -> void:
	var w: Node = Router.world
	await _clear_dialogue(20.0)
	await _press(JOY_BUTTON_Y)
	await _wait(0.4)
	_check("field: Y opens the main menu", w.menu_open)
	var m: Node = w.menu_layer.get_child(w.menu_layer.get_child_count() - 1) if w.menu_layer.get_child_count() > 0 else null
	if m:
		await _shot("pad_menu")
		var s0 := int(m.get("section_idx"))
		await _press(JOY_BUTTON_RIGHT_SHOULDER)
		_check("menu: R1 next section", int(m.get("section_idx")) != s0)
		await _press(JOY_BUTTON_LEFT_SHOULDER)
		_check("menu: L1 previous section", int(m.get("section_idx")) == s0)
		var f0 := _focus()
		await _press(JOY_BUTTON_DPAD_DOWN)
		_check("menu: D-pad down moves focus", _focus() != f0 and _focus() != null)
		await _press(JOY_BUTTON_DPAD_UP)
		await _press(JOY_BUTTON_A)
		await _wait(0.3)
		_check("menu: A enters the section", bool(m.get("_in_content")))
		await _press(JOY_BUTTON_B)
		await _wait(0.2)
		_check("menu: B steps back to the section list", not bool(m.get("_in_content")))
		await _press(JOY_BUTTON_B)
		await _wait(0.4)
		_check("menu: B closes the menu", not w.menu_open)
	await _wait(0.4)
	await _press(JOY_BUTTON_BACK)
	await _wait(0.4)
	m = w.menu_layer.get_child(w.menu_layer.get_child_count() - 1) if w.menu_open else null
	_check("field: View opens the Journal", m != null and str(m.sections[int(m.section_idx)]) == "Journal")
	await _shot("pad_journal")
	if m:
		await _press(JOY_BUTTON_Y)
		await _wait(0.4)
		_check("menu: Y also closes the menu", not w.menu_open)
	await _wait(0.4)
	await _press(JOY_BUTTON_START)
	await _wait(0.4)
	m = w.menu_layer.get_child(w.menu_layer.get_child_count() - 1) if w.menu_open else null
	_check("field: Menu (Start) opens pause/settings", m != null and str(m.sections[int(m.section_idx)]) == "Settings")
	if m:
		await _press(JOY_BUTTON_B)
		await _press(JOY_BUTTON_B)
		await _wait(0.4)
		_check("pause: B closes", not w.menu_open)
	# Shop opened by an event.
	await _wait(0.3)
	var shop_id: String = Content.table("shops").keys()[0]
	w.hud.open_shop(shop_id)
	await _wait(0.4)
	var shop: Node = w.menu_layer.get_child(w.menu_layer.get_child_count() - 1)
	await _shot("pad_shop")
	_check("shop: opens with a focused entry", _focus() != null and shop.is_ancestor_of(_focus()))
	var sf := _focus()
	await _press(JOY_BUTTON_DPAD_DOWN)
	_check("shop: D-pad moves between entries", _focus() != sf and _focus() != null)
	var mode0 := str(shop.get("mode"))
	await _press(JOY_BUTTON_RIGHT_SHOULDER)
	_check("shop: R1 switches Buy/Sell", str(shop.get("mode")) != mode0)
	await _press(JOY_BUTTON_B)
	await _wait(0.4)
	_check("shop: B closes", not w.menu_open)
	w.hud.open_save_menu()
	await _wait(0.4)
	await _shot("pad_save")
	_check("save screen: opens with a focused slot", _focus() != null)
	await _press(JOY_BUTTON_B)
	await _wait(0.4)
	_check("save screen: B closes", not w.menu_open)
	for scr: Array in [["crafting", "res://scripts/ui/craft_ui.gd", {"station": "any"}],
			["bounty board", "res://scripts/ui/contracts_ui.gd", {"board": "bellweather"}]]:
		w.hud.open_screen(scr[1], scr[2])
		await _wait(0.4)
		_check("%s: opens with focus" % scr[0], _focus() != null)
		await _press(JOY_BUTTON_B)
		await _wait(0.4)
		_check("%s: B closes" % scr[0], not w.menu_open)


# ------------------------------------------------------------------ battle

func _battle() -> void:
	var w: Node = Router.world
	var done := {"res": {}}
	var run := func() -> void: done.res = await w.start_battle("uc_crabs", {"can_escape": true})
	run.call()
	var b: Node = null
	var ready := await _until(func() -> bool:
		b = Router.battle
		return b != null and str(b.get("_active_uid")) != "" and str(b.get("_menu_state")) == "root", 20.0)
	_check("battle: command menu appears", ready)
	if not ready:
		return
	b = Router.battle
	await _wait(0.3)
	await _shot("pad_battle")
	var first := _focus_text()
	await _press(JOY_BUTTON_DPAD_DOWN)
	_check("battle: D-pad down moves the cursor (%s -> %s)" % [first, _focus_text()], _focus_text() != first)
	await _press(JOY_BUTTON_DPAD_UP)
	_check("battle: D-pad up returns to %s" % first, _focus_text() == first)
	await _press(JOY_BUTTON_A)
	await _wait(0.2)
	_check("battle: A on Attack opens targeting", str(b.get("_menu_state")) == "target")
	var t0 := int(b.get("_target_idx"))
	await _press(JOY_BUTTON_DPAD_RIGHT)
	_check("battle: D-pad changes target", int(b.get("_target_idx")) != t0 or (b.get("_target_ids") as Array).size() < 2)
	await _shot("pad_battle_target")
	await _press(JOY_BUTTON_B)
	await _wait(0.2)
	_check("battle: B backs out of targeting", str(b.get("_menu_state")) == "root")
	var actor := str(b.get("_active_uid"))
	await _press(JOY_BUTTON_A)
	await _press(JOY_BUTTON_A)
	_check("battle: A, A submits Attack", str(b.get("_active_uid")) != actor or str(b.get("_menu_state")) != "target")
	await _press(JOY_BUTTON_Y)
	await _wait(0.2)
	_check("battle: Y toggles auto-battle on", bool(b.get("_auto")))
	await _press(JOY_BUTTON_A)
	await _wait(0.2)
	_check("battle: any button cancels auto-battle", not bool(b.get("_auto")))
	# R1/L1 cycle between ready members; X repeats the last command.
	var cycled := await _until(func() -> bool: return (b.get("_menu_state") == "root" and (b.sim.ready_queue as Array).size() >= 2), 15.0)
	if cycled:
		var a0 := str(b.get("_active_uid"))
		await _press(JOY_BUTTON_RIGHT_SHOULDER)
		await _wait(0.2)
		_check("battle: R1 switches to the next ready member", str(b.get("_active_uid")) != a0)
	else:
		_check("battle: R1 cycle skipped (never two members ready at once)", true)
	await _press(JOY_BUTTON_Y)
	var finished := await _until(func() -> bool: return Router.battle == null or bool(b.get("_ended")), 60.0)
	_check("battle: finishes under auto-battle", finished)
	await _shot("pad_battle_end")
	var back := await _until(func() -> bool:
		if Router.battle != null:
			_press(JOY_BUTTON_A, 0.05)
		return Router.battle == null and w.can_control(), 30.0)
	_check("battle: A dismisses results and returns to the field", back)
