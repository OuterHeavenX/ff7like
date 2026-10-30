extends MenuScreen
## Save / load screen with slot metadata, overwrite & delete confirmation, and
## portable JSON export/import (browser download/upload or native folders).

var mode: String = "load"   # "save" | "load"
var list: VBoxContainer
var status: Label


func _ready() -> void:
	add_dim(0.85)
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.offset_left = 60
	p.offset_right = -60
	p.offset_top = 40
	p.offset_bottom = -40
	add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	p.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var t := UITheme.title_label("Save Game" if mode == "save" else "Load Game", 30)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	add_back_button(head)
	status = UITheme.label("", 18, UITheme.C_DIM)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	if not Saves.persistent_storage_available():
		status.text = "Warning: this browser is not persisting storage (private mode or blocked site data). Export your save to keep it."
	elif OS.has_feature("web"):
		status.text = "Saves are stored in this browser. Use Export to back up or move a save to another device."
	else:
		status.text = "Save folder: %s" % ProjectSettings.globalize_path("user://saves")
	Saves.import_ready.connect(_on_import_text)
	_refresh()


func _fmt_time(sec: float) -> String:
	var s := int(sec)
	return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]


func _slot_text(slot: String) -> String:
	var m := Saves.read_meta(slot)
	var label := ("Slot " + slot.substr(4)) if slot.begins_with("slot") else ("Autosave " + slot.substr(4))
	if m.is_empty():
		return "%s — empty" % label if not Saves.slot_exists(slot) else "%s — unreadable (backup may exist)" % label
	var date := Time.get_datetime_string_from_unix_time(int(m.get("timestamp", 0)), true)
	return "%s   %s — %s\n      %s  •  Lv %d  •  %s  •  %s" % [label, m.get("chapter_name", ""), m.get("location", ""),
		", ".join(PackedStringArray(m.get("party", []))), int(m.get("level", 1)), _fmt_time(float(m.get("playtime", 0))), date]


func _refresh() -> void:
	MenuScreen.clear(list)
	var slots: Array = Saves.MANUAL_SLOTS.duplicate()
	if mode == "load":
		slots += Saves.AUTO_SLOTS
	var first: Control = null
	for slot: String in slots:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var b := UITheme.button(_slot_text(slot), _on_slot.bind(slot), 64)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 19)
		if mode == "load" and not Saves.slot_exists(slot):
			b.disabled = true
		row.add_child(b)
		if Saves.slot_exists(slot):
			row.add_child(UITheme.button("Export", _on_export.bind(slot), 64))
			if slot.begins_with("slot"):
				row.add_child(UITheme.button("Delete", _on_delete.bind(slot), 64))
		list.add_child(row)
		if first == null and not b.disabled:
			first = b
	var imp := UITheme.button("Import save file…", _on_import, 52)
	list.add_child(imp)
	if not OS.has_feature("web"):
		var hint := UITheme.label("Native import: place .json files in %s" % ProjectSettings.globalize_path(Saves.IMPORT_DIR), 16, UITheme.C_DIM)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(hint)
	if first == null:
		first = imp
	first.call_deferred("grab_focus")


func _on_slot(slot: String) -> void:
	if mode == "save":
		if Saves.slot_exists(slot) and not await ConfirmBox.ask(self, "Overwrite this save?\n" + _slot_text(slot), "Overwrite", "Cancel"):
			return
		if Saves.save_to(slot):
			Audio.sfx("save")
			Router.toast("Game saved.")
			_refresh()
		else:
			status.text = "Save failed: " + Saves.last_error
			Audio.sfx("error")
	else:
		if GameState.active and not await ConfirmBox.ask(self, "Load this save? Unsaved progress will be lost.", "Load", "Cancel"):
			return
		# Load synchronously first so failures are reported here, then route
		# without awaiting (this screen may be freed by the scene change).
		if Saves.load_from(slot):
			if Saves.last_error != "":
				Router.toast(Saves.last_error)
			Router.enter_world(GameState.map_id, "", GameState.map_pos)
			close()
		else:
			status.text = "Could not load: " + Saves.last_error
			Audio.sfx("error")


func _on_export(slot: String) -> void:
	var out := Saves.export_slot(slot)
	if out == "":
		status.text = "Export failed: " + Saves.last_error
	elif OS.has_feature("web"):
		status.text = "Downloaded %s. Keep it somewhere safe; import it on any device." % out
	else:
		status.text = "Exported to %s" % out


func _on_delete(slot: String) -> void:
	if await ConfirmBox.ask(self, "Delete this save permanently?\n" + _slot_text(slot), "Delete", "Keep"):
		Saves.delete_slot(slot)
		_refresh()


func _on_import() -> void:
	if OS.has_feature("web"):
		status.text = "Choose a save file…"
		Saves.request_web_import()
		return
	var files := Saves.native_import_files()
	if files.is_empty():
		status.text = "No .json files found in %s" % ProjectSettings.globalize_path(Saves.IMPORT_DIR)
		return
	# Use the newest file in the import folder.
	files.sort_custom(func(a: String, b: String) -> bool: return FileAccess.get_modified_time(a) > FileAccess.get_modified_time(b))
	_on_import_text(Saves.read_import_file(files[0]))


func _on_import_text(text: String) -> void:
	if not is_inside_tree():
		return
	var res := Saves.check_import(text)
	if not res.ok:
		status.text = "Import rejected: " + str(res.get("error", "invalid file"))
		Audio.sfx("error")
		return
	var m: Dictionary = res.get("meta", {})
	var desc := "%s — %s, %s" % [m.get("chapter_name", "?"), m.get("location", "?"), _fmt_time(float(m.get("playtime", 0)))]
	var target := ""
	for s: String in Saves.MANUAL_SLOTS:
		if not Saves.slot_exists(s):
			target = s
			break
	if target == "":
		target = "slot3"
	var msg := "Import save (%s) into %s?" % [desc, target.replace("slot", "Slot ")]
	if Saves.slot_exists(target):
		msg += "\nThis will overwrite the existing save in that slot."
	if not await ConfirmBox.ask(self, msg, "Import", "Cancel"):
		return
	if Saves.apply_import(target, res):
		status.text = "Imported into %s." % target.replace("slot", "Slot ")
		Audio.sfx("save")
		_refresh()
	else:
		status.text = "Import failed: " + Saves.last_error
