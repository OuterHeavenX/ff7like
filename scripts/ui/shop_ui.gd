extends MenuScreen
## Buy / sell screen with equipment comparison for the active party.

var shop_id: String = ""
var mode := "buy"
var list: VBoxContainer
var info: Label
var gold_label: Label


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
	var sh: Dictionary = Content.shop(shop_id)
	var t := UITheme.title_label(str(sh.get("name", "Shop")), 28)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	gold_label = UITheme.label("", 20, UITheme.C_ACCENT)
	head.add_child(gold_label)
	add_back_button(head)
	var tabs := HBoxContainer.new()
	vb.add_child(tabs)
	tabs.add_child(UITheme.button("Buy", func() -> void:
		mode = "buy"
		_refresh(), 44))
	tabs.add_child(UITheme.button("Sell", func() -> void:
		mode = "sell"
		_refresh(), 44))
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


func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("tab_next") or event.is_action_pressed("tab_prev"):
		mode = "sell" if mode == "buy" else "buy"
		_refresh()


func _price(iid: String) -> int:
	return int(Content.item(iid).get("price", 0))


func _sell_price(iid: String) -> int:
	var it: Dictionary = Content.item(iid)
	return int(it.get("sell", int(it.get("price", 0)) / 2))


func _compare(iid: String) -> String:
	var it: Dictionary = Content.item(iid)
	if str(it.get("type")) != "equipment":
		return str(it.get("desc", ""))
	var slot: String = it.slot
	var parts: PackedStringArray = []
	for cid: String in GameState.party:
		if not GameState.can_equip(cid, iid):
			parts.append("%s: can't use" % str(Content.character(cid).get("name", cid)).split(" ")[0])
			continue
		var m: Dictionary = GameState.members[cid]
		var before := GameState.stats_for(cid)
		var saved: String = m.equip.get(slot, "")
		m.equip[slot] = iid
		var after := GameState.stats_for(cid)
		m.equip[slot] = saved
		var d: PackedStringArray = []
		for k: String in ["hp", "atk", "mag", "def", "res", "spd", "dex"]:
			var diff := int(after[k]) - int(before[k])
			if diff != 0:
				d.append("%s%+d" % [k.to_upper(), diff])
		parts.append("%s: %s" % [str(Content.character(cid).get("name", cid)).split(" ")[0], " ".join(d) if not d.is_empty() else "="])
	return str(it.get("desc", "")) + "\n" + "   ".join(parts)


func _refresh() -> void:
	gold_label.text = "%d crowns  " % GameState.gold
	MenuScreen.clear(list)
	var first: Button = null
	if mode == "buy":
		for iid: String in Content.shop(shop_id).get("items", []):
			var it: Dictionary = Content.item(iid)
			var b := UITheme.button("%s   %d cr   (own %d)" % [it.get("name", iid), _price(iid), GameState.count_item(iid)], _buy.bind(iid), 44)
			b.focus_entered.connect(func() -> void: info.text = _compare(iid))
			list.add_child(b)
			if first == null:
				first = b
	else:
		var ids: Array = GameState.inventory.keys()
		ids.sort()
		for iid: String in ids:
			var it: Dictionary = Content.item(iid)
			if str(it.get("type")) == "key" or _sell_price(iid) <= 0:
				continue
			var b := UITheme.button("%s x%d   sells for %d cr" % [it.get("name", iid), GameState.count_item(iid), _sell_price(iid)], _sell.bind(iid), 44)
			b.focus_entered.connect(func() -> void: info.text = str(it.get("desc", "")))
			list.add_child(b)
			if first == null:
				first = b
		if first == null:
			list.add_child(UITheme.label("Nothing to sell. (Key items can't be sold.)", 18))
	if first:
		first.call_deferred("grab_focus")


func _buy(iid: String) -> void:
	if not GameState.spend_gold(_price(iid)):
		Audio.sfx("error")
		info.text = "Not enough crowns."
		return
	GameState.add_item(iid, 1)
	Audio.sfx("coin")
	info.text = "Bought %s." % Content.item(iid).get("name", iid)
	var f := get_viewport().gui_get_focus_owner()
	var idx := f.get_index() if f and list.is_ancestor_of(f) else 0
	_refresh()
	if idx < list.get_child_count():
		(list.get_child(idx) as Control).call_deferred("grab_focus")


func _sell(iid: String) -> void:
	if GameState.count_item(iid) <= 0:
		return
	var it: Dictionary = Content.item(iid)
	if str(it.get("type")) == "equipment" and int(it.get("price", 0)) == 0:
		if not await ConfirmBox.ask(self, "%s is unique and can't be bought back. Sell it?" % it.get("name", iid), "Sell", "Keep"):
			return
	GameState.remove_item(iid, 1)
	GameState.add_gold(_sell_price(iid))
	Audio.sfx("coin")
	_refresh()
