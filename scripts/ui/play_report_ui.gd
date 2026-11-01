extends MenuScreen
## Play report viewer: summary of where time went, with Export (browser
## download / native file), Copy and Clear. Data never leaves the device
## unless the player sends the exported text themselves.

var scroll: ScrollContainer
var status: Label
var _clear_armed: bool = false


func _ready() -> void:
	add_dim(0.88)
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.offset_left = 50
	p.offset_right = -50
	p.offset_top = 30
	p.offset_bottom = -30
	add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	p.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var t := UITheme.title_label("Play report", 28)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	add_back_button(head)
	var note := UITheme.label("Stored only on this device. Export or Copy it and send it to the developer as feedback. %s/%s scroll." % [
		InputHub.prompt("move_up"), InputHub.prompt("move_down")], 16, UITheme.C_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(note)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var body := UITheme.label(PlayLog.summary() if PlayLog.enabled() or not (PlayLog.data.battles as Array).is_empty() else "Play report recording is off (Settings > Gameplay).", 17)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	status = UITheme.label("", 17, UITheme.C_ACCENT)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	var export_b := UITheme.button("Export file", _export, 48)
	var copy_b := UITheme.button("Copy text", _copy, 48)
	var clear_b := UITheme.button("Clear", _clear, 48)
	for b: Button in [export_b, copy_b, clear_b]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(b)
	export_b.call_deferred("grab_focus")


func _input(event: InputEvent) -> void:
	if _closing or not is_visible_in_tree():
		return
	# D-pad / arrows / stick scroll the report; left/right move between buttons.
	if event.is_action_pressed("move_up", true) or event.is_action_pressed("move_down", true):
		get_viewport().set_input_as_handled()
		scroll.scroll_vertical += -60 if event.is_action_pressed("move_up", true) else 60


func _stamp() -> String:
	return Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")


func _export() -> void:
	PlayLog.save()
	var text := PlayLog.full_report()
	var fname := "echoes_playreport_%s.txt" % _stamp()
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(text.to_utf8_buffer(), fname, "text/plain")
		status.text = "Downloaded %s." % fname
		return
	DirAccess.make_dir_recursive_absolute(Saves.EXPORT_DIR)
	var path := "%s/%s" % [Saves.EXPORT_DIR, fname]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		status.text = "Could not write the report."
		return
	f.store_string(text)
	f.close()
	status.text = "Saved to " + ProjectSettings.globalize_path(path)


func _copy() -> void:
	DisplayServer.clipboard_set(PlayLog.summary())
	status.text = "Summary copied. Paste it into a message to send it."


func _clear() -> void:
	if not _clear_armed:
		_clear_armed = true
		status.text = "Press Clear again to erase the play report."
		return
	PlayLog.clear()
	_clear_armed = false
	status.text = "Play report cleared."
	(scroll.get_child(0) as Label).text = PlayLog.summary()
