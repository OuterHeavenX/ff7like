extends CanvasLayer
## Field HUD: location banner, tracked objective (with where to go next),
## minimap, off-screen objective arrow, interaction prompt.
## Also hosts modal shop / save screens requested by events.

var root: Control
var banner: PanelContainer
var banner_label: Label
var objective: Label
var prompt_panel: PanelContainer
var prompt_label: Label
var fps_label: Label
var next_label: Label
var minimap: Minimap
var goal_arrow: Control


## Edge-of-screen pointer toward an off-screen objective.
class GoalArrow extends Control:
	var dir: Vector2 = Vector2.RIGHT
	var t: float = 0.0

	func _draw() -> void:
		var c := size * 0.5
		var s := 1.0 + 0.1 * sin(t * 6.0)
		var f := dir * 22.0 * s
		var side := Vector2(-dir.y, dir.x) * 15.0 * s
		var pts := PackedVector2Array([c + f, c - f * 0.5 + side, c - f * 0.15, c - f * 0.5 - side])
		draw_colored_polygon(pts, Color(1.0, 0.8, 0.3, 0.95))
		pts.append(pts[0])
		draw_polyline(pts, Color(0.2, 0.1, 0.0), 2.0)


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)
	banner = PanelContainer.new()
	banner.position = Vector2(24, 20)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(banner)
	banner_label = UITheme.title_label("", 26)
	banner.add_child(banner_label)
	banner.modulate.a = 0.0
	objective = UITheme.label("", 18, UITheme.C_DIM)
	objective.position = Vector2(26, 20)
	objective.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	objective.add_theme_constant_override("outline_size", 6)
	root.add_child(objective)
	next_label = UITheme.label("", 16, Color(1.0, 0.82, 0.45))
	next_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	next_label.add_theme_constant_override("outline_size", 6)
	root.add_child(next_label)
	minimap = Minimap.new()
	minimap.world = get_parent()
	root.add_child(minimap)
	goal_arrow = GoalArrow.new()
	goal_arrow.size = Vector2(64, 64)
	goal_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	goal_arrow.visible = false
	root.add_child(goal_arrow)
	prompt_panel = PanelContainer.new()
	prompt_panel.anchor_left = 0.5
	prompt_panel.anchor_right = 0.5
	prompt_panel.anchor_top = 1.0
	prompt_panel.anchor_bottom = 1.0
	prompt_panel.offset_top = -86
	prompt_panel.offset_bottom = -40
	prompt_panel.offset_left = -110
	prompt_panel.offset_right = 110
	prompt_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	prompt_panel.gui_input.connect(func(e: InputEvent) -> void:
		# Tapping the prompt interacts (touch convenience; A still works).
		if e is InputEventMouseButton and e.pressed and get_parent().can_control():
			get_parent().interact())
	root.add_child(prompt_panel)
	prompt_label = UITheme.label("", 20)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_panel.add_child(prompt_label)
	prompt_panel.visible = false
	fps_label = UITheme.label("", 16, UITheme.C_DIM)
	fps_label.anchor_left = 1.0
	fps_label.anchor_right = 1.0
	fps_label.offset_left = -120
	fps_label.position.y = 4
	root.add_child(fps_label)
	GameState.quest_updated.connect(func(_q: String) -> void: refresh())
	InputHub.device_changed.connect(func(_k: String) -> void: refresh())
	refresh()


func _process(d: float) -> void:
	fps_label.visible = bool(Settings.get_value("show_fps"))
	if fps_label.visible:
		fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	var vp := root.get_global_rect().size
	minimap.visible = bool(Settings.get_value("minimap"))
	var touch_top := 104.0 if InputHub.touch_controls_visible() else 0.0
	minimap.position = Vector2(vp.x - minimap.size.x - 14, 14 + touch_top + (24 if fps_label.visible else 0))
	_update_goal_arrow(d, vp)


func _update_goal_arrow(d: float, vp: Vector2) -> void:
	var w: Node = get_parent()
	var wf: Wayfinder = w.get("wayfinder")
	var gp: Variant = wf.goal_position() if wf else null
	var cam: Camera3D = w.get("camera")
	if gp == null or cam == null or not w.call("can_control"):
		goal_arrow.visible = false
		return
	var vsize := get_viewport().get_visible_rect().size
	var behind := cam.is_position_behind(gp)
	var sp := cam.unproject_position(gp)
	var margin := 12.0
	if not behind and Rect2(Vector2(margin, margin), vsize - Vector2(margin, margin) * 2.0).has_point(sp):
		goal_arrow.visible = false
		return
	# Viewport pixels -> HUD canvas units (canvas_items stretch).
	var k := vp / vsize
	var centre := vsize * 0.5
	var dir := (sp - centre).normalized() if not behind else (centre - sp).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.DOWN
	var half := centre - Vector2(70, 70)
	var tx := absf(half.x / dir.x) if absf(dir.x) > 0.001 else INF
	var ty := absf(half.y / dir.y) if absf(dir.y) > 0.001 else INF
	var edge := centre + dir * minf(tx, ty)
	var ga := goal_arrow as GoalArrow
	ga.dir = dir
	ga.t += d
	ga.position = edge * k - ga.size * 0.5
	ga.visible = true
	ga.queue_redraw()


func refresh() -> void:
	var q := GameState.tracked_quest
	if q != "" and bool(Settings.get_value("quest_markers")) and GameState.quests.has(q):
		var qd: Dictionary = Content.quest(q)
		var stages: Array = qd.get("stages", [])
		var st := clampi(GameState.quest_stage(q), 0, maxi(0, stages.size() - 1))
		var obj: String = stages[st].get("objective", "") if not stages.is_empty() else ""
		objective.text = "* " + obj
	else:
		objective.text = ""
	objective.position.y = 20 if banner.modulate.a < 0.1 else 74
	next_label.text = _next_hint() if objective.text != "" else ""
	next_label.position = Vector2(30, objective.position.y + 26)


## "Go to: <map>" when the objective lies beyond an exit.
func _next_hint() -> String:
	var wf: Wayfinder = get_parent().get("wayfinder")
	if wf == null or wf.target.is_empty():
		return ""
	if bool(wf.target.here):
		return "Objective is in this area (follow the gold marker)."
	var e: Dictionary = wf.target.exit
	var via := Nav.map_name(str(e.to))
	var dest := Nav.map_name(str(wf.target.map))
	if via == dest:
		return "Head to %s (gold exit)." % dest
	return "Head to %s, toward %s (gold exit)." % [via, dest]


func show_location(map_name: String, region: String) -> void:
	banner_label.text = map_name if region == "" else "%s — %s" % [region, map_name]
	var tw := create_tween()
	tw.tween_property(banner, "modulate:a", 1.0, 0.4)
	tw.tween_callback(refresh)
	tw.tween_interval(2.4)
	tw.tween_property(banner, "modulate:a", 0.0, 0.6)
	tw.tween_callback(refresh)


func set_prompt(text: String) -> void:
	if text == "":
		prompt_panel.visible = false
		return
	prompt_panel.visible = true
	var glyph := InputHub.prompt("confirm")
	prompt_label.text = "%s  %s" % [glyph, text] if InputHub.active_device != "touch" else text


func open_shop(shop_id: String) -> void:
	var s: Control = preload("res://scripts/ui/shop_ui.gd").new()
	s.shop_id = shop_id
	get_parent().menu_layer.add_child(s)
	get_parent().menu_open = true
	await s.closed
	get_parent().menu_open = false


func open_save_menu() -> void:
	var s: Control = preload("res://scripts/ui/save_ui.gd").new()
	s.mode = "save"
	get_parent().menu_layer.add_child(s)
	get_parent().menu_open = true
	await s.closed
	get_parent().menu_open = false


## Generic modal screen host for event-opened UIs (crafting, contracts).
func open_screen(script_path: String, props: Dictionary) -> void:
	var s: Control = load(script_path).new()
	for k: String in props.keys():
		s.set(k, props[k])
	get_parent().menu_layer.add_child(s)
	get_parent().menu_open = true
	await s.closed
	get_parent().menu_open = false
