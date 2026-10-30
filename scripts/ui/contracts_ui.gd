extends MenuScreen
## Bounty board: repeatable hunting contracts. Progress counts real defeats
## after acceptance (summons never count); each completion has a cooldown.

var board: String = ""
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
	var t := UITheme.title_label("Bounty Board", 28)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	add_back_button(head)
	var note := UITheme.label("Repeatable contracts. Accept one, defeat the target anywhere, then return here. Rewards include JP for your active party.", 17, UITheme.C_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(note)
	list = VBoxContainer.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(list)
	info = UITheme.label("", 18, UITheme.C_DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(0, 52)
	vb.add_child(info)
	_refresh()


func _refresh() -> void:
	MenuScreen.clear(list)
	var first: Button = null
	for cid: String in Content.table("contracts").keys():
		var c: Dictionary = Content.get_entry("contracts", cid)
		if str(c.board) != board:
			continue
		var st := GameState.contract_state(cid)
		var done := int(GameState.contracts.get(cid, {}).get("completions", 0))
		var label := "%s — defeat %d %s   " % [c.title, int(c.count), Content.enemy(str(c.enemy)).get("name", c.enemy)]
		match st:
			"available": label += "[Accept]"
			"active": label += "[%d/%d]" % [GameState.contract_progress(cid), int(c.count)]
			"ready": label += "[Turn in!]"
			"cooldown": label += "[restocking: win %d more battles]" % (int(GameState.contracts[cid].ready_after) - GameState.battles_won)
		if done > 0:
			label += "  (done %dx)" % done
		var b := UITheme.button(label, _act.bind(cid), 46)
		b.add_theme_font_size_override("font_size", 19)
		var rw: Dictionary = c.get("reward", {})
		var items: PackedStringArray = []
		for iid: String in rw.get("items", {}).keys():
			items.append("%s x%d" % [Content.item(iid).get("name", iid), int(rw.items[iid])])
		var help := "Where: %s. Danger %s. Reward: %d crowns, %d JP each (active party)%s." % [c.get("region", "?"), "*".repeat(int(c.get("danger", 1))), int(rw.get("gold", 0)), int(rw.get("jp", 0)), (", " + ", ".join(items)) if not items.is_empty() else ""]
		b.focus_entered.connect(func() -> void: info.text = help)
		list.add_child(b)
		if first == null:
			first = b
	if first:
		first.call_deferred("grab_focus")


func _act(cid: String) -> void:
	match GameState.contract_state(cid):
		"available":
			GameState.accept_contract(cid)
			Audio.sfx("confirm")
		"ready":
			GameState.turn_in_contract(cid)
			Audio.sfx("coin")
			info.text = "Contract complete! Rewards received."
		_:
			Audio.sfx("error")
	_refresh()
