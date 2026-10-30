extends CanvasLayer
## Field HUD: location banner, tracked objective, interaction prompt, gold.
## Also hosts modal shop / save screens requested by events.

var root: Control
var banner: PanelContainer
var banner_label: Label
var objective: Label
var prompt_panel: PanelContainer
var prompt_label: Label
var fps_label: Label


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
	prompt_panel = PanelContainer.new()
	prompt_panel.anchor_left = 0.5
	prompt_panel.anchor_right = 0.5
	prompt_panel.anchor_top = 1.0
	prompt_panel.anchor_bottom = 1.0
	prompt_panel.offset_top = -86
	prompt_panel.offset_bottom = -40
	prompt_panel.offset_left = -110
	prompt_panel.offset_right = 110
	prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
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


func _process(_d: float) -> void:
	fps_label.visible = bool(Settings.get_value("show_fps"))
	if fps_label.visible:
		fps_label.text = "%d FPS" % Engine.get_frames_per_second()


func refresh() -> void:
	var q := GameState.tracked_quest
	if q != "" and bool(Settings.get_value("quest_markers")) and GameState.quests.has(q):
		var qd: Dictionary = Content.quest(q)
		var stages: Array = qd.get("stages", [])
		var st := clampi(GameState.quest_stage(q), 0, maxi(0, stages.size() - 1))
		var obj: String = stages[st].get("objective", "") if not stages.is_empty() else ""
		objective.text = "◆ " + obj
	else:
		objective.text = ""
	objective.position.y = 20 if banner.modulate.a < 0.1 else 74


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
