extends Node3D
## Title screen: slow cinematic pan across festival-night Bellweather,
## authored logo treatment, "press any button" gate (unlocks browser audio),
## then Continue / New Game / Load / Settings / Quit.

var camera: Camera3D
var ui: Control
var menu_box: VBoxContainer
var press_label: Label
var logo: Control
var _t: float = 0.0
var _gate_open: bool = false
var _sub: Control = null
var _picking: bool = false


func _ready() -> void:
	var builder := MapBuilder.new()
	var m: Dictionary = Content.map("bellweather_wick")
	if not m.is_empty():
		add_child(builder.build(m))
	camera = Camera3D.new()
	camera.fov = 34
	camera.rotation_degrees = Vector3(-22, -18, 0)
	add_child(camera)
	camera.current = true
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.03, 0.07)
	env.environment = e
	add_child(env)
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.theme = UITheme.get_theme()
	layer.add_child(ui)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.02, 0.06, 0.35)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(shade)
	_build_logo()
	press_label = UITheme.label("Press any button", 26)
	press_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	press_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	press_label.position = Vector2(-200, -150)
	press_label.size = Vector2(400, 40)
	ui.add_child(press_label)
	menu_box = VBoxContainer.new()
	menu_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	menu_box.position = Vector2(-150, -300)
	menu_box.custom_minimum_size = Vector2(300, 0)
	menu_box.add_theme_constant_override("separation", 4)
	menu_box.visible = false
	ui.add_child(menu_box)
	var ver := UITheme.label("v" + str(ProjectSettings.get_setting("application/config/version")) + "  •  Godot 4.4.1", 16, UITheme.C_DIM)
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.position = Vector2(-300, -34)
	ver.size = Vector2(280, 24)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui.add_child(ver)
	var credit := UITheme.label("An original JRPG  •  Early build: Prologue – Chapter Three", 16, UITheme.C_DIM)
	credit.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	credit.position = Vector2(20, -34)
	credit.size = Vector2(600, 24)
	ui.add_child(credit)
	Audio.play_music("title", 1.5)
	if OS.has_feature("web"):
		_web_install_and_update()


func _build_logo() -> void:
	logo = Control.new()
	logo.set_anchors_preset(Control.PRESET_CENTER_TOP)
	logo.position = Vector2(-460, 70)
	logo.size = Vector2(920, 220)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(logo)
	var small := UITheme.label("E C H O E S   O F   T H E", 26, Color(0.85, 0.82, 0.9))
	small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	small.size = Vector2(920, 30)
	small.add_theme_font_override("font", UITheme.bold())
	logo.add_child(small)
	var big := Label.new()
	big.text = "LAST DAWN"
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.position = Vector2(0, 30)
	big.size = Vector2(920, 120)
	big.add_theme_font_override("font", UITheme.bold())
	big.add_theme_font_size_override("font_size", 104)
	big.add_theme_color_override("font_color", Color(1.0, 0.80, 0.45))
	big.add_theme_color_override("font_outline_color", Color(0.25, 0.08, 0.02))
	big.add_theme_constant_override("outline_size", 14)
	big.add_theme_color_override("font_shadow_color", Color(1.0, 0.5, 0.15, 0.45))
	big.add_theme_constant_override("shadow_offset_x", 0)
	big.add_theme_constant_override("shadow_offset_y", 6)
	big.add_theme_constant_override("shadow_outline_size", 28)
	logo.add_child(big)
	var line := ColorRect.new()
	line.color = Color(1.0, 0.8, 0.45, 0.7)
	line.position = Vector2(260, 160)
	line.size = Vector2(400, 2)
	logo.add_child(line)
	var tag := UITheme.label("What the bells forget, we carry.", 22, Color(0.9, 0.88, 0.95))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.position = Vector2(0, 172)
	tag.size = Vector2(920, 30)
	logo.add_child(tag)


func _process(delta: float) -> void:
	_t += minf(delta, 0.1)
	var s := 0.0 if bool(Settings.get_value("reduce_motion")) else _t * 0.05
	camera.position = Vector3(15.0 + sin(s) * 6.0, 3.6, 13.5 + cos(s * 0.7) * 0.8)
	camera.rotation_degrees = Vector3(-14.0, -8.0 + sin(s) * 7.0, 0.0)
	if not _gate_open:
		press_label.modulate.a = 0.45 + 0.55 * absf(sin(_t * 2.0))


func _input(event: InputEvent) -> void:
	if _gate_open:
		return
	var pressed := (event is InputEventKey and event.is_pressed() and not event.is_echo()) \
		or (event is InputEventJoypadButton and event.is_pressed()) \
		or (event is InputEventScreenTouch and event.is_pressed()) \
		or (event is InputEventMouseButton and event.is_pressed())
	if pressed and _over_update_button(event):
		return   # let the update button receive the tap
	if pressed:
		get_viewport().set_input_as_handled()
		_gate_open = true
		press_label.visible = false
		Audio.sfx("confirm")
		_show_menu()


func _show_menu() -> void:
	for c in menu_box.get_children():
		menu_box.remove_child(c)
		c.queue_free()
	menu_box.visible = true
	var first: Button = null
	if Saves.any_save_exists():
		first = UITheme.button("Continue", _continue, 50)
		menu_box.add_child(first)
	var ng := UITheme.button("New Game", _new_game, 50)
	menu_box.add_child(ng)
	if first == null:
		first = ng
	menu_box.add_child(UITheme.button("Load Game", _load, 50))
	menu_box.add_child(UITheme.button("Settings", _settings, 50))
	if not OS.has_feature("web"):
		menu_box.add_child(UITheme.button("Quit", func() -> void: get_tree().quit(), 50))
	for b in menu_box.get_children():
		(b as Button).alignment = HORIZONTAL_ALIGNMENT_CENTER
	first.call_deferred("grab_focus")


func _continue() -> void:
	var slot := Saves.latest_slot()
	if slot == "" or Router.busy:
		return
	if not Saves.load_from(slot):
		Router.toast("Could not load: " + Saves.last_error)
		return
	menu_box.visible = false
	if Saves.last_error != "":
		Router.toast(Saves.last_error)
	Router.enter_world(GameState.map_id, "", GameState.map_pos)


func _new_game() -> void:
	if Router.busy:
		return
	_show_difficulty()


## New Game first asks for a difficulty (also changeable later in Settings).
func _show_difficulty() -> void:
	_picking = true
	for c in menu_box.get_children():
		menu_box.remove_child(c)
		c.queue_free()
	menu_box.add_child(UITheme.title_label("Choose difficulty", 24))
	var blurb := UITheme.label("", 16, UITheme.C_DIM)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(300, 64)
	var focus_me: Button = null
	for i in Difficulty.LEVELS.size():
		var lvl: String = Difficulty.LEVELS[i]
		var b := UITheme.button(Difficulty.LABELS[i], func() -> void: _start_with(lvl), 50)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.focus_entered.connect(func() -> void: blurb.text = Difficulty.BLURBS[lvl])
		menu_box.add_child(b)
		if lvl == Difficulty.level():
			focus_me = b
	menu_box.add_child(blurb)
	var back := UITheme.button("Back", func() -> void:
		_picking = false
		_show_menu(), 44)
	back.alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_box.add_child(back)
	focus_me.call_deferred("grab_focus")


func _start_with(lvl: String) -> void:
	if Router.busy:
		return
	_picking = false
	Settings.set_value("difficulty", lvl)
	menu_box.visible = false
	Audio.stop_music(1.0)
	Router.start_new_game()


func _unhandled_input(event: InputEvent) -> void:
	if _picking and event.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		Audio.sfx("cancel")
		_picking = false
		_show_menu()


func _open_sub(node: Control) -> void:
	menu_box.visible = false
	logo.visible = false
	_sub = node
	ui.add_child(node)
	await node.closed
	_sub = null
	logo.visible = true
	_show_menu()


func _load() -> void:
	var s: Control = preload("res://scripts/ui/save_ui.gd").new()
	s.mode = "load"
	_open_sub(s)


func _settings() -> void:
	var s: Control = preload("res://scripts/ui/settings_ui.gd").new()
	_open_sub(s)


# ------------------------------------------------------------------ installable web app

## Browser builds: suggest installing to the home screen (fullscreen, offline)
## when not already installed, and offer a restart when a newer build has been
## downloaded by the service worker. Only on the title screen, never mid-game.
func _web_install_and_update() -> void:
	var kind: Variant = JavaScriptBridge.eval("""
		(function () {
			var mm = function (q) { return window.matchMedia && window.matchMedia(q).matches; };
			if (window.navigator.standalone === true || mm('(display-mode: standalone)') || mm('(display-mode: fullscreen)')) { return ''; }
			var ua = navigator.userAgent || '';
			if (/iPhone|iPad|iPod/.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)) { return 'ios'; }
			if (/Android/.test(ua)) { return 'android'; }
			return '';
		})()
	""", true)
	var tip := ""
	match str(kind):
		"ios": tip = "Tip: tap Share, then \"Add to Home Screen\" to install the game and play fullscreen."
		"android": tip = "Tip: open the browser menu and choose \"Install app\" (or \"Add to Home screen\") to play fullscreen."
	if tip != "":
		var l := UITheme.label(tip + "\nThe installed app keeps its own saves: use Load Game > Export / Import to move one across.", 17, Color(0.85, 0.9, 1.0))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.set_anchors_preset(Control.PRESET_CENTER_TOP)
		l.position = Vector2(-450, 300)
		l.size = Vector2(900, 60)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		l.add_theme_constant_override("outline_size", 6)
		ui.add_child(l)
	if JavaScriptBridge.pwa_needs_update():
		_show_update_button()
	else:
		JavaScriptBridge.pwa_update_available.connect(_show_update_button)


func _over_update_button(event: InputEvent) -> bool:
	var b := ui.get_node_or_null("UpdateButton") as Control
	if b == null:
		return false
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		return b.get_global_rect().has_point(event.position)
	return false


func _show_update_button() -> void:
	if ui.has_node("UpdateButton"):
		return
	var b := UITheme.button("A new version is ready - tap to update", func() -> void: JavaScriptBridge.pwa_update(), 46)
	b.name = "UpdateButton"
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.20, 0.13, 0.05, 0.92)
	sb.border_color = UITheme.C_ACCENT
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	for st: String in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, sb)
	b.set_anchors_preset(Control.PRESET_CENTER_TOP)
	b.position = Vector2(-260, 16)
	b.size = Vector2(520, 46)
	ui.add_child(b)

