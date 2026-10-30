extends MenuScreen
## Crafting: focused upgrades and consumables with explicit recipes.

var station: String = "any"
var list: VBoxContainer
var info: Label


func _ready() -> void:
	add_dim(0.75)
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.offset_left = 120
	p.offset_right = -120
	p.offset_top = 40
	p.offset_bottom = -40
	add_child(p)
	var vb := VBoxContainer.new()
	p.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var t := UITheme.title_label("Crafting" + (" — Smithy" if station == "smith" else ""), 28)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	add_back_button(head)
	var note := UITheme.label("Materials drop from enemies (see the Bestiary). Upgrades consume the original item; unequip it first.", 17, UITheme.C_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	info = UITheme.label("", 18, UITheme.C_DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(0, 52)
	vb.add_child(info)
	_refresh()


func _recipe_text(r: Dictionary) -> String:
	var parts: PackedStringArray = []
	for iid: String in r.get("materials", {}).keys():
		parts.append("%s %d/%d" % [Content.item(iid).get("name", iid), GameState.count_item(iid), int(r.materials[iid])])
	if int(r.get("gold", 0)) > 0:
		parts.append("%d cr" % int(r.gold))
	return ", ".join(parts)


func _refresh() -> void:
	var keep := 0
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if f and list.is_ancestor_of(f):
		keep = f.get_index()
	MenuScreen.clear(list)
	for rid: String in Content.table("recipes").keys():
		var r: Dictionary = Content.get_entry("recipes", rid)
		if str(r.get("station", "any")) == "smith" and station != "smith":
			continue
		var reason := GameState.craft_block_reason(rid, station)
		var res: Dictionary = Content.item(str(r.result))
		var b := UITheme.button("%s x%d   [%s]" % [res.get("name", r.result), int(r.get("qty", 1)), _recipe_text(r)], _craft.bind(rid), 44)
		b.add_theme_font_size_override("font_size", 19)
		if reason != "":
			b.add_theme_color_override("font_color", Color(0.6, 0.6, 0.66))
		b.focus_entered.connect(func() -> void:
			info.text = str(r.get("desc", res.get("desc", ""))) + ("" if reason == "" else "   — " + reason))
		list.add_child(b)
	if list.get_child_count() > 0:
		(list.get_child(mini(keep, list.get_child_count() - 1)) as Control).call_deferred("grab_focus")


func _craft(rid: String) -> void:
	var reason := GameState.craft_block_reason(rid, station)
	if reason != "":
		Audio.sfx("error")
		info.text = reason
		return
	if GameState.craft(rid, station):
		Audio.sfx("item")
		info.text = "Crafted %s." % Content.item(str(Content.get_entry("recipes", rid).result)).get("name", "")
	_refresh()
