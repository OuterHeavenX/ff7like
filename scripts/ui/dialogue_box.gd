extends CanvasLayer
## Dialogue presentation: speaker name, portrait, typewriter text, choices,
## narration cards, tutorials and chapter title cards. Input requires fresh
## presses (and a short arming delay) so held or mashed buttons cannot skip lines.

signal _advance
signal _chosen(idx: int)

const ARM_MS := 140

var root: Control
var panel: PanelContainer
var name_label: Label
var text_label: RichTextLabel
var portrait: TextureRect
var arrow: Label
var choice_panel: PanelContainer
var choice_box: VBoxContainer
var overlay: ColorRect
var center_label: Label
var _open: bool = false
var _revealing: bool = false
var _reveal_t: float = 0.0
var _armed_at: int = 0
var _mode: String = ""     # "line", "choice", "narrate", "card"
var _aborted: bool = false


func _ready() -> void:
	layer = 30
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)
	overlay = ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(overlay)
	center_label = Label.new()
	center_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	center_label.offset_left = 120
	center_label.offset_right = -120
	center_label.visible = false
	root.add_child(center_label)
	panel = PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -560
	panel.offset_right = 560
	panel.offset_top = -214
	panel.offset_bottom = -16
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(_on_panel_input)
	root.add_child(panel)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	panel.add_child(hb)
	portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(160, 160)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hb.add_child(portrait)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)
	name_label = UITheme.title_label("", 24)
	vb.add_child(name_label)
	text_label = RichTextLabel.new()
	text_label.bbcode_enabled = true
	text_label.fit_content = false
	text_label.scroll_active = false
	text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_label.add_theme_font_size_override("normal_font_size", 25)
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(text_label)
	arrow = Label.new()
	arrow.text = "▼"
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(arrow)
	choice_panel = PanelContainer.new()
	choice_panel.anchor_left = 0.5
	choice_panel.anchor_right = 0.5
	choice_panel.anchor_top = 1.0
	choice_panel.anchor_bottom = 1.0
	choice_panel.offset_left = 120
	choice_panel.offset_right = 560
	choice_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	choice_panel.offset_bottom = -222
	choice_panel.offset_top = -222
	root.add_child(choice_panel)
	choice_box = VBoxContainer.new()
	choice_panel.add_child(choice_box)
	_hide_all()
	Settings.changed.connect(func(k: String) -> void:
		if k == "high_contrast":
			root.theme = UITheme.get_theme())


func _hide_all() -> void:
	panel.visible = false
	choice_panel.visible = false
	center_label.visible = false
	overlay.color.a = 0.0
	_open = false


func is_open() -> bool:
	return _open


func close() -> void:
	_hide_all()
	_mode = ""


func abort_line() -> void:
	_aborted = true
	_advance.emit()
	if _mode == "choice":
		pass


func _process(delta: float) -> void:
	if _revealing:
		var cps := Settings.text_cps()
		if cps <= 0.0:
			text_label.visible_ratio = 1.0
			_revealing = false
		else:
			_reveal_t += delta * cps
			var n := int(_reveal_t)
			if n >= text_label.get_total_character_count():
				text_label.visible_characters = -1
				_revealing = false
			else:
				if n != text_label.visible_characters and n % 3 == 0:
					Audio.sfx("talk", 1.0 + float(n % 5) * 0.03)
				text_label.visible_characters = n
	arrow.modulate.a = (0.4 + 0.6 * absf(sin(Time.get_ticks_msec() / 300.0))) if not _revealing else 0.0


func _press() -> void:
	if Time.get_ticks_msec() < _armed_at:
		return
	if _mode == "line" or _mode == "narrate" or _mode == "card":
		if _revealing:
			text_label.visible_characters = -1
			_revealing = false
			_armed_at = Time.get_ticks_msec() + 90
		else:
			_advance.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not _open or _mode == "choice":
		return
	if event.is_action_pressed("confirm") or event.is_action_pressed("cancel"):
		if event.is_echo():
			return
		get_viewport().set_input_as_handled()
		_press()
	elif event is InputEventMouseButton and event.pressed and _mode in ["narrate", "card"]:
		_press()


func _on_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_press()


func _show_line(speaker: String, text: String, tex: Texture2D) -> void:
	_open = true
	_aborted = false
	panel.visible = true
	choice_panel.visible = false
	center_label.visible = false
	name_label.text = speaker
	name_label.visible = speaker != ""
	portrait.texture = tex
	portrait.visible = tex != null
	text_label.text = text
	text_label.visible_characters = 0
	_reveal_t = 0.0
	_revealing = true
	_armed_at = Time.get_ticks_msec() + ARM_MS


func say(speaker: String, text: String, tex: Texture2D = null) -> void:
	_mode = "line"
	_show_line(speaker, text, tex)
	await _advance
	_mode = ""


func say_simple(speaker: String, text: String) -> void:
	await say(speaker, text, null)
	close()


func narrate(text: String) -> void:
	_open = true
	_mode = "narrate"
	panel.visible = false
	choice_panel.visible = false
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(overlay, "color:a", 0.82, 0.3)
	center_label.text = text
	center_label.visible = true
	center_label.add_theme_font_size_override("font_size", 26)
	_revealing = false
	_armed_at = Time.get_ticks_msec() + 400
	await _advance
	var tw2 := create_tween()
	tw2.tween_property(overlay, "color:a", 0.0, 0.3)
	center_label.visible = false
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_open = false
	_mode = ""


func title_card(title: String, subtitle: String) -> void:
	_open = true
	_mode = "card"
	panel.visible = false
	overlay.color = Color(0.02, 0.02, 0.05, 0.0)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(overlay, "color:a", 1.0, 0.6)
	await tw.finished
	center_label.text = title + ("\n\n" + subtitle if subtitle != "" else "")
	center_label.add_theme_font_size_override("font_size", 40)
	center_label.add_theme_font_override("font", UITheme.bold())
	center_label.visible = true
	center_label.modulate.a = 0.0
	var tw2 := create_tween()
	tw2.tween_property(center_label, "modulate:a", 1.0, 0.8)
	_armed_at = Time.get_ticks_msec() + 900
	var timer := get_tree().create_timer(4.0)
	timer.timeout.connect(func() -> void:
		if _mode == "card":
			_advance.emit())
	await _advance
	var tw3 := create_tween()
	tw3.tween_property(center_label, "modulate:a", 0.0, 0.5)
	tw3.tween_property(overlay, "color:a", 0.0, 0.6)
	await tw3.finished
	center_label.visible = false
	center_label.remove_theme_font_override("font")
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_open = false
	_mode = ""


func flash(c: Color) -> void:
	overlay.color = Color(c.r, c.g, c.b, 0.0)
	var tw := create_tween()
	tw.tween_property(overlay, "color:a", 0.8, 0.08)
	tw.tween_property(overlay, "color:a", 0.0, 0.5)
	await tw.finished


func tutorial(title: String, text: String) -> void:
	await say(title, "[color=#ffd27a]" + text + "[/color]", null)
	close()


func _build_choices(options: Array) -> void:
	for c in choice_box.get_children():
		c.queue_free()
	var first: Button = null
	for i in options.size():
		var b := UITheme.button(str(options[i]), func() -> void: _chosen.emit(i), 48)
		choice_box.add_child(b)
		if first == null:
			first = b
	choice_panel.visible = true
	choice_panel.reset_size()
	if first:
		first.call_deferred("grab_focus")


func choose(prompt: String, options: Array, tex: Texture2D = null, speaker: String = "") -> int:
	_mode = "choice"
	if prompt != "":
		_show_line(speaker, prompt, tex)
		text_label.visible_characters = -1
		_revealing = false
	else:
		_open = true
	_build_choices(options)
	var idx: int = await _chosen
	choice_panel.visible = false
	_mode = ""
	return idx


## Choice shown above any current line without disturbing it (used for skip prompts).
func choose_overlay(prompt: String, options: Array) -> int:
	var prev_mode := _mode
	var prev_text := text_label.text
	var prev_name := name_label.text
	var was_visible := panel.visible
	var idx := await choose(prompt, options)
	if was_visible and not _aborted:
		_mode = prev_mode
		text_label.text = prev_text
		name_label.text = prev_name
	elif not was_visible:
		panel.visible = false
		_open = false
	return idx
