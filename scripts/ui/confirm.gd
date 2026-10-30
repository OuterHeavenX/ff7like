class_name ConfirmBox
extends Control
## Modal yes/no prompt. Usage: var ok: bool = await ConfirmBox.ask(self, "Overwrite?")

signal answered(yes: bool)


static func ask(host: Node, text: String, yes_text: String = "Yes", no_text: String = "No") -> bool:
	var c := ConfirmBox.new()
	c._build(text, yes_text, no_text)
	host.add_child(c)
	var r: bool = await c.answered
	c.queue_free()
	return r


func _build(text: String, yes_text: String, no_text: String) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.custom_minimum_size = Vector2(560, 0)
	p.position = Vector2(-280, -110)
	add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	p.add_child(vb)
	var l := UITheme.label(text)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(l)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 24)
	vb.add_child(hb)
	var no := UITheme.button(no_text, func() -> void: answered.emit(false), 48)
	var yes := UITheme.button(yes_text, func() -> void: answered.emit(true), 48)
	no.custom_minimum_size.x = 160
	yes.custom_minimum_size.x = 160
	hb.add_child(no)
	hb.add_child(yes)
	no.call_deferred("grab_focus")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		answered.emit(false)
	elif event is InputEventKey or event is InputEventJoypadButton:
		# Swallow everything else so underlying menus don't react.
		if event.is_pressed():
			pass
