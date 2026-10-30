extends MenuScreen
## Settings: gameplay, battle, audio, display, accessibility and controls.
## Every option is operable by keyboard, gamepad (left/right to change) and touch.

var tabs: Array = ["Gameplay", "Audio & Display", "Accessibility", "Controls"]
var tab_idx := 0
var tab_bar: HBoxContainer
var body: VBoxContainer
var info: Label
var _listening_action := ""
var _listen_deadline := 0


func _ready() -> void:
	add_dim(0.85)
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.offset_left = 60
	p.offset_right = -60
	p.offset_top = 30
	p.offset_bottom = -30
	add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	p.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var t := UITheme.title_label("Settings", 30)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	add_back_button(head)
	tab_bar = HBoxContainer.new()
	vb.add_child(tab_bar)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 4)
	scroll.add_child(body)
	info = UITheme.label("", 18, UITheme.C_DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(info)
	_build()


func handle_input(event: InputEvent) -> void:
	if _listening_action != "":
		return
	if event.is_action_pressed("tab_next"):
		tab_idx = (tab_idx + 1) % tabs.size()
		_build()
	elif event.is_action_pressed("tab_prev"):
		tab_idx = (tab_idx - 1 + tabs.size()) % tabs.size()
		_build()


func _build() -> void:
	MenuScreen.clear(tab_bar)
	for i in tabs.size():
		var b := UITheme.button(("▸ " if i == tab_idx else "") + tabs[i], func() -> void:
			tab_idx = i
			_build(), 44)
		b.focus_mode = Control.FOCUS_NONE
		if i == tab_idx:
			b.add_theme_color_override("font_color", UITheme.C_ACCENT)
		tab_bar.add_child(b)
	var hint := UITheme.label("  %s / %s: switch tabs" % [InputHub.prompt("tab_prev"), InputHub.prompt("tab_next")], 16, UITheme.C_DIM)
	tab_bar.add_child(hint)
	MenuScreen.clear(body)
	match tab_idx:
		0:
			_choice("Battle mode", "battle_mode", ["wait", "active"], ["Wait (time pauses in menus)", "Active (time keeps flowing)"],
				"Wait pauses the battle timeline whenever you are choosing a command or target.")
			_choice("Battle speed", "battle_speed", [1, 2, 3, 4, 5], ["1 (slowest)", "2", "3 (default)", "4", "5 (fastest)"], "Scales how fast time gauges fill.")
			_toggle("Fast battle animations", "fast_animations", "Shortens attack and spell animations.")
			_choice("Text speed", "text_speed", [0, 1, 2, 3], ["Slow", "Normal", "Fast", "Instant"], "How quickly dialogue appears.")
			_toggle("Quest objective on HUD", "quest_markers", "Shows the tracked objective in the corner of the field screen.")
			_toggle("Pause when window loses focus", "pause_on_focus_loss", "Recommended for browser and Steam Deck suspend.")
		1:
			_slider("Music volume", "music_volume")
			_slider("Sound effects volume", "sfx_volume")
			_choice("Visual preset", "visual_preset", ["standard", "low"], ["Standard", "Low / mobile"], "Low reduces particles and ambient effects. Takes effect on next map load.")
			_choice("UI scale", "ui_scale", [0.85, 1.0, 1.15, 1.3, 1.5], ["85%", "100%", "115%", "130%", "150%"], "Scales menus and text independently of the world view.")
			_choice("Touch controls", "touch_controls", ["auto", "on", "off"], ["Auto", "Always on", "Off"], "Auto shows them after the first touch.")
			_toggle("Show FPS counter", "show_fps", "")
			if not OS.has_feature("web"):
				var fs := UITheme.button("Toggle fullscreen", func() -> void:
					var m := DisplayServer.window_get_mode()
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if m == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN), 44)
				body.add_child(fs)
		2:
			_toggle("Reduce motion", "reduce_motion", "Disables camera pans, shakes and screen swirls.")
			_toggle("Reduce flashing", "reduce_flashing", "Replaces flashes with gentle fades.")
			_toggle("Camera shake", "camera_shake", "")
			_toggle("High contrast UI", "high_contrast", "Black panels, white text, yellow focus. Reopen menus to apply.")
			var l := UITheme.label("Status effects always show a distinct icon shape and text label, never color alone.", 18, UITheme.C_DIM)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			body.add_child(l)
			body.add_child(UITheme.button("Restore default settings", func() -> void:
				if await ConfirmBox.ask(self, "Restore all settings (except controls) to defaults?", "Restore", "Cancel"):
					Settings.reset_defaults()
					_build(), 44))
		3:
			for action: String in InputHub.REBINDABLE:
				var b := UITheme.button("%s:   %s" % [InputHub.ACTION_LABELS[action], InputHub.bindings_text(action)], _rebind.bind(action), 44)
				b.add_theme_font_size_override("font_size", 19)
				body.add_child(b)
			body.add_child(UITheme.button("Reset controls to defaults", func() -> void:
				if await ConfirmBox.ask(self, "Reset all control bindings?", "Reset", "Cancel"):
					InputHub.reset_bindings()
					_build(), 44))
			var l2 := UITheme.label("Select an action, then press the new key or button. Binding a key already used elsewhere moves it (you will be told which action lost it). Listening times out after 5 seconds.", 17, UITheme.C_DIM)
			l2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			body.add_child(l2)
	MenuScreen.focus_first(body)


func _value_label(label: String, key: String, values: Array, names: Array) -> String:
	var v: Variant = Settings.get_value(key)
	var idx := 0
	for i in values.size():
		if str(values[i]) == str(v) or (typeof(v) == TYPE_FLOAT and typeof(values[i]) == TYPE_FLOAT and is_equal_approx(float(v), float(values[i]))):
			idx = i
	return "%s:   ◀ %s ▶" % [label, names[idx]]


func _choice(label: String, key: String, values: Array, names: Array, help: String) -> void:
	var b := UITheme.button(_value_label(label, key, values, names), Callable(), 44)
	var step := func(dir: int) -> void:
		var v: Variant = Settings.get_value(key)
		var idx := 0
		for i in values.size():
			if str(values[i]) == str(v):
				idx = i
		idx = (idx + dir + values.size()) % values.size()
		Settings.set_value(key, values[idx])
		b.text = _value_label(label, key, values, names)
		Audio.sfx("cursor")
	b.pressed.connect(func() -> void: step.call(1))
	b.gui_input.connect(func(e: InputEvent) -> void:
		if e.is_action_pressed("ui_left"):
			step.call(-1)
			b.accept_event()
		elif e.is_action_pressed("ui_right"):
			step.call(1)
			b.accept_event())
	b.focus_entered.connect(func() -> void: info.text = help)
	body.add_child(b)


func _toggle(label: String, key: String, help: String) -> void:
	var b := UITheme.button("", Callable(), 44)
	var upd := func() -> void: b.text = "%s:   %s" % [label, "ON" if bool(Settings.get_value(key)) else "OFF"]
	upd.call()
	b.pressed.connect(func() -> void:
		Settings.set_value(key, not bool(Settings.get_value(key)))
		upd.call())
	b.focus_entered.connect(func() -> void: info.text = help)
	body.add_child(b)


func _slider(label: String, key: String) -> void:
	var hb := HBoxContainer.new()
	var l := UITheme.label(label, 20)
	l.custom_minimum_size = Vector2(300, 0)
	hb.add_child(l)
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 1
	s.step = 0.05
	s.value = float(Settings.get_value(key))
	s.custom_minimum_size = Vector2(320, 44)
	s.focus_mode = Control.FOCUS_ALL
	s.value_changed.connect(func(v: float) -> void:
		Settings.set_value(key, v)
		Audio.sfx("cursor"))
	hb.add_child(s)
	body.add_child(hb)


func _rebind(action: String) -> void:
	_listening_action = action
	_listen_deadline = Time.get_ticks_msec() + 5000
	info.text = "Press a key or button for \"%s\"…" % InputHub.ACTION_LABELS[action]


func _input(event: InputEvent) -> void:
	if _listening_action == "":
		return
	var ok := false
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		ok = true
	elif event is InputEventJoypadButton and event.is_pressed():
		ok = true
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.7:
		ok = true
	if not ok:
		return
	get_viewport().set_input_as_handled()
	var action := _listening_action
	_listening_action = ""
	var lost := InputHub.rebind(action, event)
	info.text = "Bound %s to %s." % [InputHub.ACTION_LABELS[action], InputHub.describe_event(event)]
	if lost != "":
		info.text += " (Removed from %s.)" % InputHub.ACTION_LABELS[lost]
	_build()


func _process(_d: float) -> void:
	if _listening_action != "" and Time.get_ticks_msec() > _listen_deadline:
		_listening_action = ""
		info.text = "Rebinding cancelled."
