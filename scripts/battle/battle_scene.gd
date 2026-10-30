extends Node3D
## Battle presentation and input. Owns a BattleSim and renders its events.
## The simulation never waits on nodes: it produces an event list for each
## action, this scene animates it, then acknowledges so time can continue.

signal finished(result: Dictionary)

const FX_INDEX := {"slash": 0, "impact": 1, "fire": 2, "frost": 3, "bolt": 4, "heal": 5, "buff": 6, "debuff": 7,
	"resonance": 8, "sparkle": 9, "shield": 10, "smoke": 11, "halo": 12, "drop": 13, "note": 14, "mark": 15, "magic": 9}
const STATUS_ABBR := {"poison": "PSN", "burn": "BRN", "slow": "SLW", "haste": "HST", "sleep": "SLP", "silence": "SIL",
	"blind": "BLD", "regen": "RGN", "barrier": "BAR", "stun": "STN", "vulnerable": "VUL", "mark": "MRK", "guard": "GRD",
	"cover": "CVR", "taunt": "TNT", "counter_stance": "RIP"}
const STATUS_ICON := {"poison": 0, "burn": 1, "slow": 2, "haste": 3, "sleep": 4, "silence": 5, "blind": 6, "regen": 7,
	"barrier": 8, "stun": 9, "vulnerable": 10, "guard": 11, "mark": 12, "cover": 8, "taunt": 10, "counter_stance": 11}
const CAM_POS := Vector3(9.0, 6.2, 13.6)
const CAM_LOOK := Vector3(8.8, 0.6, 5.4)

var sim := BattleSim.new()
var encounter: Dictionary = {}
var opts: Dictionary = {}
var visuals: Dictionary = {}       # uid -> {root, sprite, home, frames, w, h}
var camera: Camera3D
var ui: Control
var help_label: Label
var wait_label: Label
var party_box: VBoxContainer
var enemy_box: VBoxContainer
var cmd_panel: PanelContainer
var cmd_box: VBoxContainer
var res_bar: ProgressBar
var res_label: Label
var auto_btn: Button
var banner: Label
var _presenting := false
var _ended := false
var _active_uid := ""              # party unit currently choosing
var _menu_state := ""              # "", "root", "list", "target"
var _pending_cmd: Dictionary = {}
var _target_ids: Array = []
var _target_idx := 0
var _target_multi := false
var _auto := false
var _cursor: Label3D
var _fx_tex: Texture2D
var _status_tex: Texture2D
var _taught_resonance := false
var _cam_pitch_comp := 1.0
var _list_back_state := "root"


func setup(enc_id: String, o: Dictionary) -> void:
	opts = o
	encounter = Content.encounter(enc_id)
	_fx_tex = MapBuilder.fx_texture()
	_status_tex = load("res://assets/ui/status_icons.png")
	_build_arena()
	_build_units()
	_build_ui()
	if Router.debug_auto_battle:
		_auto = true
		auto_btn.text = "Auto: ON"
	Audio.play_music(str(o.get("music", "")) if str(o.get("music", "")) != "" else str(encounter.get("music", "battle")))
	var names: PackedStringArray = []
	for u: BattleUnit in sim.enemies_alive():
		names.append(u.name)
	_show_help(("Boss: " if encounter.get("boss", false) else "") + ", ".join(names) + " — " + ("Wait mode" if _wait_mode() else "Active mode"))


func _wait_mode() -> bool:
	return str(Settings.get_value("battle_mode")) == "wait"


func _anim_speed() -> float:
	return 2.0 if bool(Settings.get_value("fast_animations")) else 1.0


# ------------------------------------------------------------------ construction

func _build_arena() -> void:
	var arena_id: String = encounter.get("arena", "arena_town")
	var b := MapBuilder.new()
	add_child(b.build(Content.map(arena_id)))
	camera = Camera3D.new()
	camera.fov = 36
	add_child(camera)
	camera.position = CAM_POS
	# Boss arenas frame higher so tall sprites stay on screen.
	camera.look_at(CAM_LOOK + (Vector3(0, 1.6, -0.4) if encounter.get("boss", false) else Vector3.ZERO))
	camera.current = true
	var look := CAM_LOOK + (Vector3(0, 1.6, -0.4) if encounter.get("boss", false) else Vector3.ZERO)
	_cam_pitch_comp = 1.0 / cos(atan2(CAM_POS.y - look.y, CAM_POS.z - look.z))
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	var bg: Array = Content.map(arena_id).get("background", [0.02, 0.02, 0.04])
	e.background_color = Color(bg[0], bg[1], bg[2])
	env.environment = e
	add_child(env)
	_cursor = Label3D.new()
	_cursor.text = "V"
	_cursor.font = UITheme.bold()
	_cursor.font_size = 72
	_cursor.outline_size = 14
	_cursor.modulate = Color(1, 0.85, 0.3)
	_cursor.pixel_size = 0.006
	_cursor.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_cursor.no_depth_test = true
	_cursor.visible = false
	add_child(_cursor)


func _build_units() -> void:
	var party_units: Array = []
	var i := 0
	for cid: String in GameState.party:
		party_units.append(BattleUnit.from_member(cid, i))
		i += 1
	var enemy_units: Array = []
	var j := 0
	for eid: String in encounter.get("enemies", []):
		enemy_units.append(BattleUnit.from_enemy(eid, j))
		GameState.record_enemy(eid, false)
		j += 1
	sim.setup(party_units, enemy_units, int(GameState.rng_seed) + GameState.steps * 7919 + int(GameState.playtime),
		{"can_escape": bool(encounter.get("can_escape", true)) and bool(opts.get("can_escape", true))}, GameState.inventory)
	for u: BattleUnit in sim.units:
		_make_visual(u)


func _party_slot(u: BattleUnit) -> Vector3:
	var idx := int(u.uid.substr(1))
	var x := 11.3 + idx * 0.3 + (1.0 if u.row == "back" else 0.0)
	return Vector3(x, 1.0, 2.5 + idx * 0.95)


func _enemy_slot(u: BattleUnit) -> Vector3:
	var all: Array = sim.side_units(1, false)
	var idx := all.find(u)
	var n := all.size()
	var layouts := {1: [Vector2(5.6, 3.6)], 2: [Vector2(6.2, 2.8), Vector2(5.0, 4.4)],
		3: [Vector2(6.6, 2.5), Vector2(4.8, 3.5), Vector2(6.6, 4.6)],
		4: [Vector2(6.8, 2.4), Vector2(4.8, 3.0), Vector2(6.8, 4.2), Vector2(4.8, 4.9)],
		5: [Vector2(7.0, 2.3), Vector2(5.0, 2.8), Vector2(6.0, 3.8), Vector2(4.6, 4.8), Vector2(7.0, 5.0)]}
	var lay: Array = layouts.get(mini(n, 5), layouts[5])
	var p: Vector2 = lay[idx % lay.size()]
	if u.boss:
		return Vector3(5.0, 1.0, 3.9)
	return Vector3(p.x, 1.0, p.y)


func _make_visual(u: BattleUnit) -> void:
	var root := Node3D.new()
	add_child(root)
	var spr := Sprite3D.new()
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	spr.shaded = false
	spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	spr.pixel_size = 1.0 / 24.0
	spr.double_sided = true
	var w := 32
	var h := 32
	if u.side == 0:
		spr.texture = load("res://assets/sprites/chars/%s_battle.png" % u.sprite)
		spr.hframes = 8
		spr.frame = 0 if u.alive() else 6
	else:
		var path := "res://assets/sprites/enemies/%s.png" % u.sprite
		spr.texture = load(path) if ResourceLoader.exists(path) else null
		spr.hframes = 2
		if spr.texture:
			w = spr.texture.get_width() / 2
			h = spr.texture.get_height()
	# Oversized sprites (bosses) are drawn at 2/3 scale so they stay framed.
	if h > 64:
		spr.pixel_size = 1.0 / 36.0
		h = int(h * 24.0 / 36.0)
		w = int(w * 24.0 / 36.0)
	spr.offset = Vector2(0, (h * 36.0 / 24.0 if spr.pixel_size < 1.0 / 30.0 else h) / 2.0)
	spr.scale = Vector3(1, _cam_pitch_comp, 1)
	root.add_child(spr)
	var shadow := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(maxf(0.7, w / 24.0 * 0.8), 0.4)
	q.orientation = PlaneMesh.FACE_Y
	shadow.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = _fx_tex
	m.uv1_scale = Vector3(1.0 / 8.0, 0.5, 1)
	m.uv1_offset = Vector3(4.0 / 8.0, 0.5, 0)
	m.albedo_color = Color(0, 0, 0, 0.55)
	shadow.material_override = m
	shadow.position.y = 0.02
	root.add_child(shadow)
	var home := _party_slot(u) if u.side == 0 else _enemy_slot(u)
	root.position = home
	visuals[u.uid] = {"root": root, "sprite": spr, "home": home, "w": w, "h": h, "t": randf() * 2.0}


# ------------------------------------------------------------------ UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 15
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.theme = UITheme.get_theme()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 16
	top.offset_right = -16
	top.offset_top = 10
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(top)
	var thb := HBoxContainer.new()
	top.add_child(thb)
	help_label = UITheme.label("", 20)
	help_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_label.custom_minimum_size = Vector2(0, 28)
	thb.add_child(help_label)
	wait_label = UITheme.label("|| WAIT", 18, UITheme.C_ACCENT)
	wait_label.visible = false
	thb.add_child(wait_label)
	auto_btn = UITheme.button("Auto: OFF", _toggle_auto, 40)
	auto_btn.focus_mode = Control.FOCUS_NONE
	auto_btn.add_theme_font_size_override("font_size", 18)
	thb.add_child(auto_btn)
	banner = UITheme.title_label("", 30)
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.position = Vector2(-400, 90)
	banner.size = Vector2(800, 80)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	banner.add_theme_constant_override("outline_size", 8)
	banner.visible = false
	ui.add_child(banner)
	# Party panel (bottom right)
	var pp := PanelContainer.new()
	pp.anchor_left = 1.0
	pp.anchor_right = 1.0
	pp.anchor_top = 1.0
	pp.anchor_bottom = 1.0
	pp.offset_left = -600
	pp.offset_right = -12
	pp.offset_top = -250
	pp.offset_bottom = -12
	ui.add_child(pp)
	var pvb := VBoxContainer.new()
	pp.add_child(pvb)
	var rhb := HBoxContainer.new()
	pvb.add_child(rhb)
	res_label = UITheme.label("Resonance 0", 16, Color(0.55, 0.95, 1.0))
	res_label.custom_minimum_size = Vector2(150, 0)
	rhb.add_child(res_label)
	res_bar = UITheme.bar(Color(0.45, 0.9, 1.0), 10)
	res_bar.max_value = 100
	res_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	res_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rhb.add_child(res_bar)
	party_box = VBoxContainer.new()
	party_box.add_theme_constant_override("separation", 2)
	pvb.add_child(party_box)
	# Enemy panel (bottom left)
	var ep := PanelContainer.new()
	ep.anchor_top = 1.0
	ep.anchor_bottom = 1.0
	ep.offset_left = 12
	ep.offset_right = 320
	ep.offset_top = -250
	ep.offset_bottom = -12
	ui.add_child(ep)
	enemy_box = VBoxContainer.new()
	ep.add_child(enemy_box)
	# Command panel (above enemy panel)
	cmd_panel = PanelContainer.new()
	cmd_panel.anchor_top = 1.0
	cmd_panel.anchor_bottom = 1.0
	cmd_panel.offset_left = 330
	cmd_panel.offset_right = 668
	cmd_panel.offset_top = -420
	cmd_panel.offset_bottom = -12
	ui.add_child(cmd_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cmd_panel.add_child(scroll)
	cmd_box = VBoxContainer.new()
	cmd_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(cmd_box)
	cmd_panel.visible = false
	_refresh_panels()


func _status_strip(u: BattleUnit) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 2)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for sid: String in u.statuses.keys():
		if not STATUS_ABBR.has(sid):
			continue
		var icon := TextureRect.new()
		var at := AtlasTexture.new()
		at.atlas = _status_tex
		var k: int = STATUS_ICON.get(sid, 15)
		at.region = Rect2((k % 8) * 16, (k / 8) * 16, 16, 16)
		icon.texture = at
		icon.custom_minimum_size = Vector2(20, 20)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(icon)
		var l := UITheme.label(STATUS_ABBR[sid], 13)
		hb.add_child(l)
	if not u.delayed.is_empty():
		hb.add_child(UITheme.label("~", 13))
	if not u.charging.is_empty():
		hb.add_child(UITheme.label("!CHARGING", 13, UITheme.C_BAD))
	return hb


func _refresh_panels() -> void:
	MenuScreen.clear(party_box)
	for u: BattleUnit in sim.party():
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 50)
		b.pressed.connect(_on_unit_tapped.bind(u.uid))
		var hb := HBoxContainer.new()
		hb.set_anchors_preset(Control.PRESET_FULL_RECT)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_theme_constant_override("separation", 8)
		b.add_child(hb)
		var name_col := UITheme.label(("» " if u.uid == _active_uid else "") + u.name.split(" ")[0] + ("  (B)" if u.row == "back" else ""), 19,
			UITheme.C_ACCENT if u.uid == _active_uid else (UITheme.C_BAD if not u.alive() else Color(0, 0, 0, 0)))
		name_col.custom_minimum_size = Vector2(130, 0)
		hb.add_child(name_col)
		var hpv := VBoxContainer.new()
		hpv.custom_minimum_size = Vector2(150, 0)
		hpv.add_theme_constant_override("separation", 0)
		hpv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(hpv)
		var hpl := UITheme.label("HP %d/%d" % [u.hp, u.max_hp], 16, UITheme.C_BAD if u.hp_ratio() < 0.3 else Color(0, 0, 0, 0))
		hpv.add_child(hpl)
		var hpb := UITheme.bar(UITheme.C_HP, 6)
		hpb.max_value = u.max_hp
		hpb.value = u.hp
		hpv.add_child(hpb)
		var spl := UITheme.label("SP %d" % u.sp, 16, UITheme.C_SP)
		spl.custom_minimum_size = Vector2(60, 0)
		hb.add_child(spl)
		var atv := VBoxContainer.new()
		atv.custom_minimum_size = Vector2(90, 0)
		atv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(atv)
		var atb := UITheme.bar(UITheme.C_ATB if u.atb < 100.0 else Color(1, 1, 1), 8)
		atb.max_value = 100
		atb.value = u.atb
		atb.name = "ATB"
		atv.add_child(UITheme.label("READY" if u.waiting_command else "", 12, UITheme.C_ACCENT))
		atv.add_child(atb)
		hb.add_child(_status_strip(u))
		b.set_meta("uid", u.uid)
		party_box.add_child(b)
	MenuScreen.clear(enemy_box)
	for u: BattleUnit in sim.enemies_alive():
		var b2 := Button.new()
		b2.focus_mode = Control.FOCUS_NONE
		b2.custom_minimum_size = Vector2(0, 46)
		b2.pressed.connect(_on_unit_tapped.bind(u.uid))
		var vb := VBoxContainer.new()
		vb.set_anchors_preset(Control.PRESET_FULL_RECT)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_theme_constant_override("separation", 0)
		b2.add_child(vb)
		var top := HBoxContainer.new()
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(top)
		top.add_child(UITheme.label(u.name, 18))
		top.add_child(_status_strip(u))
		var eb := UITheme.bar(UITheme.C_BAD, 5)
		eb.max_value = u.max_hp
		eb.value = u.hp
		vb.add_child(eb)
		enemy_box.add_child(b2)
	res_bar.value = sim.resonance
	res_label.text = "Resonance %d" % sim.resonance


func _update_atb_bars() -> void:
	for b: Node in party_box.get_children():
		var uid: String = b.get_meta("uid", "")
		var u := sim.unit(uid)
		if u == null:
			continue
		var bars := b.find_children("ATB", "ProgressBar", true, false)
		if not bars.is_empty():
			(bars[0] as ProgressBar).value = u.atb


func _show_help(t: String) -> void:
	help_label.text = t


# ------------------------------------------------------------------ main loop

func _process(delta: float) -> void:
	delta = minf(delta, 0.1)   # never simulate a backlog after suspend / tab switch
	_animate_idle(delta)
	if _ended:
		return
	sim.time_scale = Settings.battle_time_scale()
	var choosing := _active_uid != "" and _menu_state != ""
	sim.paused = choosing and _wait_mode()
	wait_label.visible = sim.paused
	if _presenting:
		return
	if sim.busy:
		_present(sim.take_events().duplicate())
		return
	sim.step(delta)
	_update_atb_bars()
	if sim.busy:
		return
	if _active_uid == "" and not sim.ready_queue.is_empty():
		_begin_command(str(sim.ready_queue[0]))
	elif _active_uid != "" and not sim.unit(_active_uid).waiting_command:
		_close_menu()


func _animate_idle(delta: float) -> void:
	for uid: String in visuals.keys():
		var v: Dictionary = visuals[uid]
		v.t = float(v.t) + delta
		var u := sim.unit(uid)
		var spr: Sprite3D = v.sprite
		if u == null or spr == null:
			continue
		if u.side == 1 and u.alive():
			spr.frame = int(float(v.t) * 2.0) % 2
			if not bool(Settings.get_value("reduce_motion")):
				spr.position.y = sin(float(v.t) * 2.2) * 0.04
		elif u.side == 0 and not v.get("busy", false):
			if not u.alive():
				spr.frame = 6
			elif u.waiting_command or u.hp_ratio() < 0.25:
				spr.frame = 1
			else:
				spr.frame = 0
	if _cursor.visible and not _target_ids.is_empty():
		var tid: String = _target_ids[_target_idx] if not _target_multi else _target_ids[0]
		if visuals.has(tid):
			var v2: Dictionary = visuals[tid]
			_cursor.position = (v2.root as Node3D).position + Vector3(0, float(v2.h) / 24.0 * _cam_pitch_comp + 0.35 + sin(Time.get_ticks_msec() / 150.0) * 0.06, 0)


# ------------------------------------------------------------------ presentation

func _present(evs: Array) -> void:
	_presenting = true
	var spd := _anim_speed()
	for ev: Dictionary in evs:
		match str(ev.t):
			"start":
				await _anim_start(ev, spd)
			"damage":
				_popup_damage(ev)
				await get_tree().create_timer(0.12 / spd).timeout
			"heal":
				_popup(str(ev.target), "+%d" % int(ev.amount), Color(0.5, 1.0, 0.6))
				Audio.sfx("heal")
			"sp":
				_popup(str(ev.target), "+%d SP" % int(ev.amount), Color(0.6, 0.8, 1.0))
			"status":
				var nm: String = Content.status_def(str(ev.id)).get("name", str(ev.id))
				if str(ev.id) == "delay":
					nm = "Delayed effect"
				_popup(str(ev.target), ("+" if ev.on else "-") + nm, Color(1.0, 0.85, 0.5) if ev.on else Color(0.8, 0.8, 0.8), 0.6)
				if ev.on:
					Audio.sfx("debuff" if str(ev.id) in BattleRules.BAD else "buff")
			"ko":
				await _anim_ko(str(ev.target))
			"revive":
				_popup(str(ev.target), "Revived!", Color(0.6, 1.0, 0.7))
				Audio.sfx("heal")
			"summon":
				var nu := sim.unit(str(ev.unit))
				if nu:
					_make_visual(nu)
					var v: Dictionary = visuals[nu.uid]
					(v.sprite as Sprite3D).modulate.a = 0.0
					var tw := create_tween()
					tw.tween_property(v.sprite, "modulate:a", 1.0, 0.4 / spd)
					_show_banner("%s appears!" % nu.name, Color(0.8, 0.9, 1.0))
					await get_tree().create_timer(0.5 / spd).timeout
			"msg":
				_show_help(str(ev.text))
				await get_tree().create_timer(0.9 / spd).timeout
			"telegraph":
				Audio.sfx("warning")
				_show_banner("! " + str(ev.text), Color(1.0, 0.55, 0.45))
				_flash_unit(str(ev.actor), Color(1.6, 1.6, 1.6))
				_show_help(str(ev.text))
				await get_tree().create_timer(1.8 / spd).timeout
			"phase":
				Audio.sfx("bell_wrong")
				_show_banner(str(ev.text), Color(0.9, 0.8, 1.0))
				_shake(0.25)
				await get_tree().create_timer(1.8 / spd).timeout
			"resonance":
				res_bar.value = int(ev.value)
				res_label.text = "Resonance %d" % int(ev.value)
				if int(ev.value) >= 50 and not _taught_resonance and not GameState.has_flag("taught_resonance"):
					_taught_resonance = true
					GameState.set_flag("taught_resonance")
					_show_banner("Resonance is ready! Choose \"Resonance\" to unleash a team technique.", Color(0.5, 0.95, 1.0))
					Audio.sfx("resonance")
					await get_tree().create_timer(1.6 / spd).timeout
			"row":
				var u := sim.unit(str(ev.target))
				var v3: Dictionary = visuals[u.uid]
				v3.home = _party_slot(u)
				var tw2 := create_tween()
				tw2.tween_property(v3.root, "position", v3.home, 0.25)
			"escape":
				if ev.ok:
					Audio.sfx("escape")
					_show_banner("Escaped!", Color(0.9, 0.9, 0.9))
					for u2: BattleUnit in sim.party():
						var tw3 := create_tween()
						tw3.tween_property(visuals[u2.uid].root, "position:x", 20.0, 0.6)
					await get_tree().create_timer(0.7).timeout
			"analyze":
				var t := sim.unit(str(ev.target))
				if t and t.side == 1:
					GameState.set_flag("analyzed_" + t.source_id)
			"end":
				await _end_battle(str(ev.outcome))
	_refresh_panels()
	sim.ack()
	_presenting = false
	if _menu_state == "root" and _active_uid != "":
		_build_root_menu()


func _anim_start(ev: Dictionary, spd: float) -> void:
	var actor := sim.unit(str(ev.actor))
	if actor == null or not visuals.has(actor.uid):
		return
	if ev.get("show_name", true):
		_show_banner(str(ev.name), Color(1, 1, 1) if actor.side == 0 else Color(1.0, 0.7, 0.6))
	var v: Dictionary = visuals[actor.uid]
	var root: Node3D = v.root
	var spr: Sprite3D = v.sprite
	var anim: String = ev.get("anim", "strike")
	var targets: Array = ev.get("targets", [])
	v.busy = true
	if actor.side == 0:
		if anim == "strike":
			spr.frame = 2
			var dest: Vector3 = v.home + Vector3(-1.4, 0, 0)
			if not targets.is_empty() and visuals.has(targets[0]) and sim.unit(targets[0]).side == 1:
				dest = (visuals[targets[0]].root as Node3D).position + Vector3(1.4, 0, 0.15)
			var tw := create_tween()
			tw.tween_property(root, "position", dest, 0.18 / spd)
			await tw.finished
			spr.frame = 3
			Audio.sfx("slash")
		elif anim == "cast":
			spr.frame = 4
			Audio.sfx("magic")
			await get_tree().create_timer(0.25 / spd).timeout
		else:
			spr.frame = 1
			await get_tree().create_timer(0.12 / spd).timeout
	else:
		_flash_unit(actor.uid, Color(1.7, 1.7, 1.7))
		var tw2 := create_tween()
		tw2.tween_property(root, "position", v.home + Vector3(0.7, 0, 0), 0.12 / spd)
		tw2.tween_property(root, "position", v.home, 0.12 / spd)
		Audio.sfx("magic" if anim == "cast" else "slash")
		await get_tree().create_timer(0.22 / spd).timeout
	for tid: String in targets:
		_spawn_fx(tid, str(ev.get("fx", "slash")))
	if str(ev.get("element", "")) != "":
		Audio.sfx({"fire": "fire", "frost": "frost", "storm": "storm"}.get(str(ev.element), "hit"))
	await get_tree().create_timer(0.16 / spd).timeout
	if actor.side == 0 and anim == "strike":
		var tw3 := create_tween()
		tw3.tween_property(root, "position", v.home, 0.18 / spd)
	v.busy = false


func _popup_damage(ev: Dictionary) -> void:
	var tid: String = ev.target
	if ev.get("miss", false):
		_popup(tid, "Resisted" if ev.has("status_miss") else "Miss", Color(0.8, 0.8, 0.85))
		return
	if ev.get("immune", false):
		_popup(tid, "Immune", Color(0.7, 0.7, 0.75))
		return
	var txt := str(int(ev.amount))
	var col := Color(1, 1, 1)
	if ev.get("crit", false):
		txt += "!"
		col = Color(1.0, 0.85, 0.3)
		Audio.sfx("crit")
		_shake(0.12)
	else:
		Audio.sfx("hit")
	var tag := ""
	if ev.get("weak", false):
		tag = "WEAK"
	elif ev.get("resist", false):
		tag = "resist"
	elif ev.get("absorb", false):
		tag = "ABSORB"
		col = Color(0.5, 1.0, 0.6)
	if ev.has("dot"):
		col = Color(0.85, 0.6, 1.0)
	_popup(tid, txt + ("\n" + tag if tag != "" else ""), col)
	var u := sim.unit(tid)
	if u and visuals.has(tid):
		var v: Dictionary = visuals[tid]
		if u.side == 0 and u.alive():
			(v.sprite as Sprite3D).frame = 5
		_flash_unit(tid, Color(1.8, 0.7, 0.7))
		var root: Node3D = v.root
		var tw := create_tween()
		var push := 0.18 if u.side == 0 else -0.18
		tw.tween_property(root, "position:x", (v.home as Vector3).x + push, 0.05)
		tw.tween_property(root, "position:x", (v.home as Vector3).x, 0.1)


func _popup(uid: String, text: String, col: Color, scale_k: float = 1.0) -> void:
	if not visuals.has(uid):
		return
	var v: Dictionary = visuals[uid]
	var l := Label3D.new()
	l.text = text
	l.font = UITheme.bold()
	l.font_size = int(64 * scale_k)
	l.outline_size = 14
	l.outline_modulate = Color(0, 0, 0)
	l.modulate = col
	l.pixel_size = 0.006
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = (v.root as Node3D).position + Vector3(randf_range(-0.2, 0.2), float(v.h) / 24.0 * 0.8 + 0.5, 0.3)
	add_child(l)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y + 0.8, 0.9)
	tw.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.45)
	tw.chain().tween_callback(l.queue_free)


func _spawn_fx(uid: String, fx: String) -> void:
	if not visuals.has(uid):
		return
	var v: Dictionary = visuals[uid]
	var s := Sprite3D.new()
	var at := AtlasTexture.new()
	at.atlas = _fx_tex
	var k: int = FX_INDEX.get(fx, 1)
	at.region = Rect2((k % 8) * 32, (k / 8) * 32, 32, 32)
	s.texture = at
	s.pixel_size = 1.0 / 20.0
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.shaded = false
	s.no_depth_test = true
	s.position = (v.root as Node3D).position + Vector3(0, float(v.h) / 24.0 * 0.6, 0.4)
	add_child(s)
	var tw := create_tween().set_parallel(true)
	var big := 1.6 if not bool(Settings.get_value("reduce_flashing")) else 1.2
	tw.tween_property(s, "scale", Vector3(big, big, big), 0.35)
	tw.tween_property(s, "modulate:a", 0.0, 0.35).set_delay(0.15)
	tw.chain().tween_callback(s.queue_free)


func _flash_unit(uid: String, c: Color) -> void:
	if not visuals.has(uid) or bool(Settings.get_value("reduce_flashing")):
		return
	var spr: Sprite3D = visuals[uid].sprite
	spr.modulate = c
	var tw := create_tween()
	tw.tween_property(spr, "modulate", Color(1, 1, 1, spr.modulate.a), 0.25)


func _shake(strength: float) -> void:
	if not bool(Settings.get_value("camera_shake")) or bool(Settings.get_value("reduce_motion")):
		return
	var tw := create_tween()
	for i in 5:
		tw.tween_property(camera, "h_offset", randf_range(-strength, strength), 0.03)
	tw.tween_property(camera, "h_offset", 0.0, 0.03)


func _show_banner(t: String, c: Color) -> void:
	banner.text = t
	banner.add_theme_color_override("font_color", c)
	banner.visible = true
	banner.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.1)
	tw.tween_property(banner, "modulate:a", 0.0, 0.4)


func _anim_ko(uid: String) -> void:
	var u := sim.unit(uid)
	if u == null or not visuals.has(uid):
		return
	var v: Dictionary = visuals[uid]
	Audio.sfx("ko")
	if u.side == 0:
		(v.sprite as Sprite3D).frame = 6
		if uid == _active_uid:
			_close_menu()
	else:
		var tw := create_tween()
		tw.tween_property(v.sprite, "modulate", Color(1.5, 0.4, 1.2, 0.0), 0.5 / _anim_speed())
		await tw.finished
		(v.root as Node3D).visible = false


# ------------------------------------------------------------------ command input

func _begin_command(uid: String) -> void:
	_active_uid = uid
	var u := sim.unit(uid)
	if _auto:
		var cmd := sim.auto_command(u)
		sim.submit(uid, cmd)
		_active_uid = ""
		return
	Audio.sfx("cursor", 1.3)
	_menu_state = "root"
	_build_root_menu()
	_refresh_panels()


func _close_menu() -> void:
	_menu_state = ""
	_active_uid = ""
	cmd_panel.visible = false
	_cursor.visible = false
	_target_ids.clear()
	for e: Node in enemy_box.get_children():
		(e as Button).modulate = Color(1, 1, 1)
	_refresh_panels()


func _cmd_button(text: String, cb: Callable, disabled_reason: String = "", help: String = "") -> Button:
	var b := UITheme.button(text, cb, 44)
	b.add_theme_font_size_override("font_size", 20)
	if disabled_reason != "":
		b.disabled = false
		b.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
		b.set_meta("blocked", disabled_reason)
	b.focus_entered.connect(func() -> void:
		_show_help(help + ("   [%s]" % disabled_reason if disabled_reason != "" else "")))
	cmd_box.add_child(b)
	return b


func _build_root_menu() -> void:
	MenuScreen.clear(cmd_box)
	cmd_panel.visible = true
	_menu_state = "root"
	var u := sim.unit(_active_uid)
	if u == null:
		return
	var sk: Dictionary = GameState.battle_skills(u.source_id)
	cmd_box.add_child(UITheme.title_label(u.name.split(" ")[0], 20))
	var first := _cmd_button("Attack", func() -> void: _choose_skill("attack"), "", "Basic weapon attack.")
	if not sk.personal.is_empty():
		_cmd_button(str(sk.personal_name) + " »", func() -> void: _open_list(sk.personal, str(sk.personal_name)), "", "Personal command.")
	var m: Dictionary = GameState.members[u.source_id]
	if not sk.main.is_empty():
		var jn: String = Content.job(str(m.job)).get("name", "Job")
		_cmd_button(jn + " »", func() -> void: _open_list(sk.main, jn), "", "Main job skills.")
	if not sk.secondary.is_empty():
		var jn2: String = Content.job(str(m.secondary)).get("name", "Job")
		_cmd_button(jn2 + " »", func() -> void: _open_list(sk.secondary, jn2), "", "Secondary skill set.")
	var arts := _arts_for(u)
	if not arts.is_empty():
		_cmd_button("Resonance »", func() -> void: _open_list(arts, "Resonance"), "" if sim.resonance >= 50 else "Needs 50 Resonance", "Team techniques fuelled by shared Resonance.")
	var items := sim.available_items()
	_cmd_button("Item »", func() -> void: _open_items(), "" if not items.is_empty() else "No usable items", "Use an item.")
	_cmd_button("Guard", func() -> void: _submit({"kind": "guard"}), "", "Halve damage taken until your next turn.")
	_cmd_button("Row: " + ("Back->Front" if u.row == "back" else "Front->Back"), func() -> void: _submit({"kind": "row"}), "", "Back row: melee deals 60%, physical damage taken 70%.")
	if sim.can_escape:
		_cmd_button("Escape", func() -> void: _submit({"kind": "escape"}), "", "Try to run. Chance improves with each attempt.")
	if not u.last_command.is_empty():
		_cmd_button("Repeat: " + _cmd_name(u.last_command), func() -> void: _repeat(), sim.command_block_reason(u, u.last_command), "Repeat your last skill or item (target is re-checked).  [%s]" % InputHub.prompt("context"))
	first.call_deferred("grab_focus")
	_show_help("%s's turn.  %s/%s: switch ready member  •  %s: repeat  •  %s: auto" % [u.name.split(" ")[0], InputHub.prompt("tab_prev"), InputHub.prompt("tab_next"), InputHub.prompt("context"), InputHub.prompt("menu")])


func _cmd_name(cmd: Dictionary) -> String:
	if str(cmd.get("kind")) == "item":
		return str(Content.item(str(cmd.id)).get("name", cmd.id))
	return str(Content.skill(str(cmd.get("id", "attack"))).get("name", "Attack"))


func _arts_for(u: BattleUnit) -> Array:
	var out: Array = []
	for sid: String in Content.table("skills").keys():
		var s: Dictionary = Content.skill(sid)
		if str(s.get("kind")) != "resonance" or str(s.get("owner", "")) != u.source_id:
			continue
		var ok := true
		for pid: String in s.get("partners", []):
			if not pid in GameState.party:
				ok = false
		if ok:
			out.append(sid)
	return out


func _open_list(ids: Array, title: String) -> void:
	MenuScreen.clear(cmd_box)
	_menu_state = "list"
	var u := sim.unit(_active_uid)
	cmd_box.add_child(UITheme.title_label(title, 20))
	var first: Button = null
	for sid: String in ids:
		var s: Dictionary = Content.skill(sid)
		var reason := sim.command_block_reason(u, {"kind": "skill", "id": sid})
		var cost := sim.sp_cost(u, s)
		var label := "%s%s" % [s.get("name", sid), ("  %d SP" % cost) if cost > 0 else ("  %d RES" % int(s.get("resonance", 0)) if int(s.get("resonance", 0)) > 0 else "")]
		var help := "%s  (%s)" % [s.get("desc", ""), _target_text(str(s.get("target", "enemy")))]
		var b := _cmd_button(label, func() -> void: _choose_skill(sid), reason, help)
		if first == null:
			first = b
	if first:
		first.call_deferred("grab_focus")


func _open_items() -> void:
	MenuScreen.clear(cmd_box)
	_menu_state = "list"
	cmd_box.add_child(UITheme.title_label("Items", 20))
	var first: Button = null
	for iid: String in sim.available_items():
		var it: Dictionary = Content.item(iid)
		var left := int(sim.inventory.get(iid, 0)) - int(sim.reserved.get(iid, 0))
		var b := _cmd_button("%s  x%d" % [it.get("name", iid), left], func() -> void: _choose_item(iid), "", str(it.get("desc", "")))
		if first == null:
			first = b
	if first:
		first.call_deferred("grab_focus")
	else:
		_build_root_menu()


func _target_text(t: String) -> String:
	return {"enemy": "one foe", "enemies": "all foes", "ally": "one ally", "allies": "all allies", "self": "self",
		"ally_ko": "one fallen ally", "other_ally": "another ally"}.get(t, t)


func _choose_skill(sid: String) -> void:
	var u := sim.unit(_active_uid)
	var reason := sim.command_block_reason(u, {"kind": "skill", "id": sid})
	if reason != "":
		Audio.sfx("error")
		_show_help(reason)
		return
	_pending_cmd = {"kind": "skill", "id": sid}
	_start_targeting(Content.skill(sid))


func _choose_item(iid: String) -> void:
	_pending_cmd = {"kind": "item", "id": iid}
	_start_targeting(sim.item_skill(iid))


func _start_targeting(def: Dictionary) -> void:
	var u := sim.unit(_active_uid)
	_target_ids = sim.valid_targets(u, def)
	if _target_ids.is_empty():
		Audio.sfx("error")
		_show_help("No valid targets.")
		return
	_target_multi = sim.is_multi(def) or str(def.get("target")) == "self"
	_target_idx = 0
	var t: String = def.get("target", "enemy")
	if t in ["ally", "ally_any"]:
		# Default heals to the most wounded ally.
		var best := 0
		for i in _target_ids.size():
			if sim.unit(_target_ids[i]).hp_ratio() < sim.unit(_target_ids[best]).hp_ratio():
				best = i
		_target_idx = best
	elif not u.last_command.is_empty() and u.last_command.get("targets", []).size() > 0:
		var last: String = u.last_command.targets[0]
		if last in _target_ids:
			_target_idx = _target_ids.find(last)
	_menu_state = "target"
	cmd_panel.visible = false
	_cursor.visible = true
	_update_target_highlight()


func _update_target_highlight() -> void:
	var names: PackedStringArray = []
	if _target_multi:
		for id: String in _target_ids:
			names.append(sim.unit(id).name)
	else:
		names.append(sim.unit(_target_ids[_target_idx]).name)
	for uid: String in visuals.keys():
		var spr: Sprite3D = visuals[uid].sprite
		var on: bool = uid in _target_ids and (_target_multi or uid == _target_ids[_target_idx])
		spr.modulate = Color(1.25, 1.2, 1.0, spr.modulate.a) if on else Color(1, 1, 1, spr.modulate.a)
	_show_help("Target: " + ", ".join(names) + "   (%s confirm, %s back%s)" % [InputHub.prompt("confirm"), InputHub.prompt("cancel"),
		"" if _target_multi else ", «» change"])


func _confirm_target() -> void:
	var targets: Array = _target_ids.duplicate() if _target_multi else [_target_ids[_target_idx]]
	var cmd := _pending_cmd.duplicate()
	cmd["targets"] = targets
	for uid: String in visuals.keys():
		var spr: Sprite3D = visuals[uid].sprite
		spr.modulate = Color(1, 1, 1, spr.modulate.a)
	_submit(cmd)


func _submit(cmd: Dictionary) -> void:
	var reason := sim.submit(_active_uid, cmd)
	if reason != "":
		Audio.sfx("error")
		_show_help(reason)
		return
	Audio.sfx("confirm")
	_close_menu()


func _repeat() -> void:
	var u := sim.unit(_active_uid)
	if u == null or u.last_command.is_empty():
		return
	var cmd: Dictionary = u.last_command.duplicate(true)
	var def := sim.item_skill(str(cmd.id)) if str(cmd.kind) == "item" else Content.skill(str(cmd.id))
	var valid := sim.valid_targets(u, def)
	var tg: Array = []
	for t: String in cmd.get("targets", []):
		if t in valid:
			tg.append(t)
	if sim.is_multi(def):
		tg = valid
	if tg.is_empty() and not valid.is_empty():
		tg = [valid[0]]
	cmd["targets"] = tg
	_submit(cmd)


func _on_unit_tapped(uid: String) -> void:
	if _menu_state != "target":
		return
	if uid in _target_ids:
		if not _target_multi:
			_target_idx = _target_ids.find(uid)
		_confirm_target()


func _toggle_auto() -> void:
	_auto = not _auto
	auto_btn.text = "Auto: ON" if _auto else "Auto: OFF"
	if _auto and _active_uid != "" and _menu_state != "":
		var uid := _active_uid
		_close_menu()
		_begin_command(uid)


func _input(event: InputEvent) -> void:
	# Touch: tap sprites directly when targeting.
	if _menu_state == "target" and event is InputEventScreenTouch and event.pressed:
		var best := ""
		var best_d := 70.0
		for uid: String in _target_ids:
			var v: Dictionary = visuals[uid]
			var p := camera.unproject_position((v.root as Node3D).position + Vector3(0, float(v.h) / 48.0, 0))
			var d := p.distance_to((event as InputEventScreenTouch).position)
			if d < best_d:
				best_d = d
				best = uid
		if best != "":
			get_viewport().set_input_as_handled()
			_on_unit_tapped(best)


func _unhandled_input(event: InputEvent) -> void:
	if _ended:
		return
	if _auto and (event.is_action_pressed("cancel") or event.is_action_pressed("menu") or event.is_action_pressed("confirm")):
		# Any press cancels auto-battle instantly.
		get_viewport().set_input_as_handled()
		_toggle_auto()
		return
	if event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		_toggle_auto()
		return
	if _active_uid == "":
		return
	match _menu_state:
		"target":
			if event.is_action_pressed("confirm"):
				get_viewport().set_input_as_handled()
				_confirm_target()
			elif event.is_action_pressed("cancel"):
				get_viewport().set_input_as_handled()
				Audio.sfx("cancel")
				_cursor.visible = false
				for uid: String in visuals.keys():
					var spr: Sprite3D = visuals[uid].sprite
					spr.modulate = Color(1, 1, 1, spr.modulate.a)
				_build_root_menu()
			elif not _target_multi and (event.is_action_pressed("move_left") or event.is_action_pressed("move_up")):
				get_viewport().set_input_as_handled()
				_target_idx = (_target_idx - 1 + _target_ids.size()) % _target_ids.size()
				Audio.sfx("cursor")
				_update_target_highlight()
			elif not _target_multi and (event.is_action_pressed("move_right") or event.is_action_pressed("move_down")):
				get_viewport().set_input_as_handled()
				_target_idx = (_target_idx + 1) % _target_ids.size()
				Audio.sfx("cursor")
				_update_target_highlight()
		"list":
			if event.is_action_pressed("cancel"):
				get_viewport().set_input_as_handled()
				Audio.sfx("cancel")
				_build_root_menu()
		"root":
			if event.is_action_pressed("context"):
				get_viewport().set_input_as_handled()
				_repeat()
			elif event.is_action_pressed("tab_next") or event.is_action_pressed("tab_prev"):
				get_viewport().set_input_as_handled()
				_cycle_ready()
	# Blocked buttons explain themselves instead of acting.
	if event.is_action_pressed("confirm"):
		var f := get_viewport().gui_get_focus_owner()
		if f and f.has_meta("blocked") and f.is_inside_tree() and cmd_box.is_ancestor_of(f):
			get_viewport().set_input_as_handled()
			Audio.sfx("error")
			_show_help(str(f.get_meta("blocked")))


func _cycle_ready() -> void:
	if sim.ready_queue.size() < 2:
		return
	var cur := _active_uid
	sim.ready_queue.erase(cur)
	sim.ready_queue.append(cur)
	_close_menu()
	_begin_command(str(sim.ready_queue[0]))


# ------------------------------------------------------------------ end

func _write_back(revive_ko: bool) -> void:
	for u: BattleUnit in sim.party():
		var m: Dictionary = GameState.members[u.source_id]
		m.hp = u.hp if u.hp > 0 else (1 if revive_ko else 0)
		m.sp = u.sp


func _end_battle(outcome: String) -> void:
	if _ended:
		return
	_ended = true
	_close_menu()
	match outcome:
		"victory":
			for u: BattleUnit in sim.side_units(1, false):
				if not u.summoned:
					GameState.record_enemy(u.source_id, true)
			var rw := sim.take_rewards()
			GameState.battles_won += 1
			_write_back(true)
			var alive: Array = []
			for u: BattleUnit in sim.side_units(0):
				alive.append(u.source_id)
			var report: Array = GameState.distribute_battle_rewards(int(rw.get("xp", 0)), int(rw.get("jp", 0)), alive)
			GameState.add_gold(int(rw.get("gold", 0)))
			for iid: String in rw.get("drops", {}).keys():
				GameState.add_item(iid, int(rw.drops[iid]))
			for u2: BattleUnit in sim.side_units(0):
				(visuals[u2.uid].sprite as Sprite3D).frame = 7
			Audio.play_music("victory", 0.3)
			await _victory_screen(rw, report)
			finished.emit({"outcome": "victory", "rewards": rw})
		"defeat":
			_write_back(false)
			_show_banner("The party has fallen…", Color(1.0, 0.5, 0.5))
			await get_tree().create_timer(1.6).timeout
			finished.emit({"outcome": "defeat"})
		_:
			_write_back(false)
			finished.emit({"outcome": "escape"})


func _victory_screen(rw: Dictionary, report: Array) -> void:
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.custom_minimum_size = Vector2(760, 0)
	p.position = Vector2(-380, -250)
	ui.add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	p.add_child(vb)
	vb.add_child(UITheme.title_label("Victory!", 32))
	vb.add_child(UITheme.label("Earned %d XP and %d JP (base, before shares)  •  %d crowns" % [int(rw.xp), int(rw.jp), int(rw.gold)], 19))
	for r: Dictionary in report:
		var c: Dictionary = Content.character(str(r.id))
		var m: Dictionary = GameState.members[str(r.id)]
		var job_name: String = Content.job(str(m.job)).get("name", "—")
		var line := "%s  +%d XP  +%d JP (%s)" % [str(c.get("name", r.id)).split(" ")[0], int(r.xp), int(r.jp), job_name]
		if int(r.levels) > 0:
			line += "   LEVEL UP! %d -> %d" % [int(r.level_before), int(r.level)]
		if r.rank_up:
			line += "   %s rank %d!" % [job_name, int(r.rank)]
		var to_next := GameState.xp_total_for_level(int(m.level) + 1) - int(m.xp)
		line += "   (next Lv: %d XP)" % to_next
		if str(r.note) != "":
			line += "  [%s]" % r.note
		var l := UITheme.label(line, 18, UITheme.C_ACCENT if int(r.levels) > 0 else Color(0, 0, 0, 0))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(l)
		if int(r.levels) > 0:
			Audio.sfx("levelup")
	var drops: Dictionary = rw.get("drops", {})
	if not drops.is_empty():
		var parts: PackedStringArray = []
		for iid: String in drops.keys():
			parts.append("%s x%d" % [Content.item(iid).get("name", iid), int(drops[iid])])
		vb.add_child(UITheme.label("Found: " + ", ".join(parts), 18))
	var b := UITheme.button("Continue", Callable(), 48)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(b)
	await get_tree().create_timer(0.4).timeout
	b.grab_focus()
	await b.pressed
