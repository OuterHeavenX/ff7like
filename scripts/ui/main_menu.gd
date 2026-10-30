extends MenuScreen
## Field menu. Left: sections. Right: section content. L/R (Q/E) switch sections
## at the top level and cycle party members inside member screens. B always backs out.

var world: Node
var start_tab: String = ""
var sections := ["Party", "Items", "Equip", "Jobs", "Passives", "Journal", "Bestiary", "Map", "Settings", "Save", "Title"]
var section_idx := 0
var member_idx := 0
var nav: VBoxContainer
var content: VBoxContainer
var footer: Label
var info: Label
var _swap_from := ""
var _locked_slots: Dictionary = {}
var _in_content := false


func _ready() -> void:
	add_dim(0.7)
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 24
	root.offset_right = -24
	root.offset_top = 20
	root.offset_bottom = -20
	root.add_theme_constant_override("separation", 12)
	add_child(root)
	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(230, 0)
	root.add_child(left)
	var lv := VBoxContainer.new()
	left.add_child(lv)
	nav = VBoxContainer.new()
	nav.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(nav)
	add_back_button(lv)
	footer = UITheme.label("", 17, UITheme.C_DIM)
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(footer)
	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(right)
	var rv := VBoxContainer.new()
	right.add_child(rv)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 4)
	scroll.add_child(content)
	info = UITheme.label("", 18, UITheme.C_DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(0, 48)
	rv.add_child(info)
	match start_tab:
		"journal": section_idx = sections.find("Journal")
		"jobs": section_idx = sections.find("Jobs")
		"pause": section_idx = sections.find("Settings")
	_build_nav()
	_show_section(start_tab in ["journal", "jobs"])
	Audio.sfx("confirm")


func _build_nav() -> void:
	MenuScreen.clear(nav)
	for i in sections.size():
		var b := UITheme.button(sections[i], _on_nav.bind(i), 42)
		b.add_theme_font_size_override("font_size", 21)
		if i == section_idx:
			b.add_theme_color_override("font_color", UITheme.C_ACCENT)
		b.focus_entered.connect(func() -> void:
			if section_idx != i:
				section_idx = i
				_show_section(false)
				_restyle_nav())
		nav.add_child(b)
	var s := int(GameState.playtime)
	footer.text = "%s\n%d crowns\n%d:%02d:%02d" % [GameState.location_name(), GameState.gold, s / 3600, (s / 60) % 60, s % 60]


func _restyle_nav() -> void:
	for i in nav.get_child_count():
		var b := nav.get_child(i) as Button
		if i == section_idx:
			b.add_theme_color_override("font_color", UITheme.C_ACCENT)
		else:
			b.remove_theme_color_override("font_color")


func _on_nav(i: int) -> void:
	section_idx = i
	_restyle_nav()
	_show_section(true)


func _focus_nav() -> void:
	_in_content = false
	(nav.get_child(section_idx) as Control).call_deferred("grab_focus")


func back() -> void:
	if _swap_from != "":
		_swap_from = ""
		_show_section(true)
		return
	if _in_content:
		_focus_nav()
		return
	close()


func handle_input(event: InputEvent) -> void:
	var member_screen: bool = sections[section_idx] in ["Equip", "Jobs", "Passives", "Party"] and _in_content
	if event.is_action_pressed("tab_next"):
		get_viewport().set_input_as_handled()
		if member_screen:
			member_idx = (member_idx + 1) % GameState.roster.size()
		else:
			section_idx = (section_idx + 1) % sections.size()
			_restyle_nav()
		_show_section(member_screen)
	elif event.is_action_pressed("tab_prev"):
		get_viewport().set_input_as_handled()
		if member_screen:
			member_idx = (member_idx - 1 + GameState.roster.size()) % GameState.roster.size()
		else:
			section_idx = (section_idx - 1 + sections.size()) % sections.size()
			_restyle_nav()
		_show_section(member_screen)
	elif event.is_action_pressed("journal"):
		get_viewport().set_input_as_handled()
		section_idx = sections.find("Journal")
		_restyle_nav()
		_show_section(true)
	elif event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		close()


func _cid() -> String:
	member_idx = clampi(member_idx, 0, GameState.roster.size() - 1)
	return GameState.roster[member_idx]


func _show_section(focus_content: bool) -> void:
	MenuScreen.clear(content)
	info.text = ""
	match sections[section_idx]:
		"Party": _party()
		"Items": _items()
		"Equip": _equip()
		"Jobs": _jobs()
		"Passives": _passives()
		"Journal": _journal()
		"Bestiary": _bestiary()
		"Map": _map()
		"Settings": _settings()
		"Save": _save()
		"Title": _title()
	_build_nav_footer()
	if focus_content:
		_in_content = true
		MenuScreen.focus_first(content)
	else:
		_in_content = false


func _build_nav_footer() -> void:
	var s := int(GameState.playtime)
	footer.text = "%s\n%d crowns\n%d:%02d:%02d" % [GameState.location_name(), GameState.gold, s / 3600, (s / 60) % 60, s % 60]


func _btn(text: String, cb: Callable, help: String = "", h: int = 44) -> Button:
	var b := UITheme.button(text, cb, h)
	b.add_theme_font_size_override("font_size", 20)
	b.focus_entered.connect(func() -> void:
		_in_content = true
		info.text = help)
	content.add_child(b)
	return b


func _header(text: String) -> void:
	content.add_child(UITheme.title_label(text, 24))


func _member_header(cid: String) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	var tr := TextureRect.new()
	var c: Dictionary = Content.character(cid)
	var path := "res://assets/portraits/%s_neutral.png" % c.get("sprite", cid)
	if ResourceLoader.exists(path):
		tr.texture = load(path)
	tr.custom_minimum_size = Vector2(96, 96)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hb.add_child(tr)
	var vb := VBoxContainer.new()
	hb.add_child(vb)
	var m: Dictionary = GameState.members[cid]
	var st := GameState.stats_for(cid)
	vb.add_child(UITheme.title_label("%s  —  %s" % [c.get("name", cid), c.get("role", "")], 24))
	vb.add_child(UITheme.label("Lv %d   HP %d/%d   SP %d/%d   %s row" % [int(m.level), int(m.hp), int(st.hp), int(m.sp), int(st.sp), str(m.row).capitalize()], 19))
	var job_name: String = Content.job(str(m.job)).get("name", "—")
	vb.add_child(UITheme.label("Job: %s (rank %d, %d JP)   Secondary: %s" % [job_name, GameState.job_rank(cid, str(m.job)), int(m.jp.get(m.job, 0)), Content.job(str(m.secondary)).get("name", "—") if str(m.secondary) != "" else "—"], 18, UITheme.C_DIM))
	vb.add_child(UITheme.label("%s / %s: change member" % [InputHub.prompt("tab_prev"), InputHub.prompt("tab_next")], 15, UITheme.C_DIM))
	content.add_child(hb)


# ------------------------------------------------------------------ Party & Status

func _party() -> void:
	_header("Party")
	content.add_child(UITheme.label("Active party (max 4) fights; reserves earn 75% XP (x2 catch-up when behind) and 50% JP.", 17, UITheme.C_DIM))
	var locked: Array = GameState.flags.get("party_required", []) if GameState.flags.get("party_required") is Array else []
	for cid: String in GameState.roster:
		var m: Dictionary = GameState.members[cid]
		var st := GameState.stats_for(cid)
		var c: Dictionary = Content.character(cid)
		var tag := "ACTIVE" if cid in GameState.party else "reserve"
		if _swap_from == cid:
			tag = ">> selected"
		var t := "%s  Lv%d  HP %d/%d  SP %d/%d  %s  [%s]%s" % [c.get("name", cid), int(m.level), int(m.hp), int(st.hp), int(m.sp), int(st.sp),
			Content.job(str(m.job)).get("name", ""), tag, "  (required)" if cid in locked else ""]
		_btn(t, _on_party_pick.bind(cid), "Select to view status, change row, or move between active party and reserves.")
	if GameState.roster.size() > 1:
		content.add_child(UITheme.label("Tip: select a member, then choose 'Swap/Move' and pick another to swap positions.", 16, UITheme.C_DIM))


func _on_party_pick(cid: String) -> void:
	if _swap_from != "" and _swap_from != cid:
		_do_swap(_swap_from, cid)
		_swap_from = ""
		_show_section(true)
		return
	MenuScreen.clear(content)
	member_idx = GameState.roster.find(cid)
	_member_header(cid)
	var st := GameState.stats_for(cid)
	var m: Dictionary = GameState.members[cid]
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 24)
	for k: String in ["atk", "mag", "def", "res", "spd", "dex"]:
		grid.add_child(UITheme.label(k.to_upper(), 19, UITheme.C_DIM))
		grid.add_child(UITheme.label(str(st[k]), 19))
	content.add_child(grid)
	var to_next := GameState.xp_total_for_level(int(m.level) + 1) - int(m.xp)
	content.add_child(UITheme.label("XP %d   (next level in %d)" % [int(m.xp), to_next], 18))
	var er: PackedStringArray = []
	for e: String in st.element_res.keys():
		er.append("%s %d%%" % [e, int(float(st.element_res[e]) * 100)])
	var sr: PackedStringArray = []
	for s: String in st.status_res.keys():
		sr.append("%s %d%%" % [s, int(float(st.status_res[s]) * 100)])
	content.add_child(UITheme.label("Element resistance: " + (", ".join(er) if not er.is_empty() else "none"), 17))
	content.add_child(UITheme.label("Status resistance: " + (", ".join(sr) if not sr.is_empty() else "none"), 17))
	var bio := UITheme.label(str(Content.character(cid).get("bio", "")), 17, UITheme.C_DIM)
	bio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(bio)
	_btn("Row: %s (toggle)" % str(m.row).capitalize(), func() -> void:
		m.row = "back" if m.row == "front" else "front"
		_on_party_pick(cid), "Back row: melee deals 60% and you take 70% physical damage. Ranged weapons ignore the dealing penalty.")
	if GameState.roster.size() > 1:
		_btn("Swap / Move…", func() -> void:
			_swap_from = cid
			_show_section(true)
			info.text = "Choose who to swap with.", "Swap positions with another member (active ⇄ reserve).")
	_btn("◀ Back to party list", func() -> void: _show_section(true))
	MenuScreen.focus_first(content)


func _do_swap(a: String, b: String) -> void:
	var p: Array = GameState.party.duplicate()
	var ia := p.find(a)
	var ib := p.find(b)
	if ia >= 0 and ib >= 0:
		p[ia] = b
		p[ib] = a
	elif ia >= 0:
		p[ia] = b
	elif ib >= 0:
		p[ib] = a
	if not GameState.set_party(p):
		Audio.sfx("error")
		info.text = "That party isn't allowed right now (a required member must stay active)."
	else:
		# Reorder roster so the lead stays first.
		var party_order: Array = GameState.party
		var rest: Array = GameState.reserves()
		GameState.roster = party_order + rest


# ------------------------------------------------------------------ Items

func _items() -> void:
	_header("Items")
	var cats := {"consumable": "Consumables", "equipment": "Equipment", "material": "Materials", "key": "Key Items"}
	for cat: String in cats.keys():
		var ids: Array = []
		for iid: String in GameState.inventory.keys():
			if str(Content.item(iid).get("type")) == cat and GameState.count_item(iid) > 0:
				ids.append(iid)
		if ids.is_empty():
			continue
		ids.sort()
		content.add_child(UITheme.label(cats[cat], 18, UITheme.C_ACCENT))
		for iid: String in ids:
			var it: Dictionary = Content.item(iid)
			var usable: bool = it.get("field", false)
			_btn("%s  x%d%s" % [it.get("name", iid), GameState.count_item(iid), "  (use)" if usable else ""],
				_on_item.bind(iid), str(it.get("desc", "")))


func _on_item(iid: String) -> void:
	var it: Dictionary = Content.item(iid)
	if not it.get("field", false):
		info.text = str(it.get("desc", ""))
		return
	MenuScreen.clear(content)
	_header("Use %s on…" % it.get("name", iid))
	for cid: String in GameState.roster:
		var m: Dictionary = GameState.members[cid]
		var st := GameState.stats_for(cid)
		_btn("%s  HP %d/%d  SP %d/%d" % [Content.character(cid).get("name", cid), int(m.hp), int(st.hp), int(m.sp), int(st.sp)], _use_item.bind(iid, cid))
	_btn("◀ Back", func() -> void: _show_section(true))
	MenuScreen.focus_first(content)


func _use_item(iid: String, cid: String) -> void:
	if GameState.count_item(iid) <= 0:
		_show_section(true)
		return
	var m: Dictionary = GameState.members[cid]
	var st := GameState.stats_for(cid)
	var used := false
	for op: Dictionary in Content.item(iid).get("use", {}).get("ops", []):
		match str(op.op):
			"heal":
				if op.get("revive", false):
					if int(m.hp) <= 0:
						m.hp = maxi(1, int(st.hp * float(op.get("pct", 0.3))))
						used = true
				elif int(m.hp) > 0 and int(m.hp) < int(st.hp):
					m.hp = mini(int(st.hp), int(m.hp) + int(op.get("flat", 0)) + int(st.hp * float(op.get("pct", 0.0))))
					used = true
			"sp":
				if int(m.sp) < int(st.sp):
					m.sp = mini(int(st.sp), int(m.sp) + int(op.amount))
					used = true
			"cleanse":
				used = true   # field ailments clear after battle; allow use for completeness
	if used:
		GameState.remove_item(iid, 1)
		Audio.sfx("heal")
		info.text = "Used %s on %s." % [Content.item(iid).get("name", iid), Content.character(cid).get("name", cid)]
	else:
		Audio.sfx("error")
		info.text = "It would have no effect."
	if GameState.count_item(iid) > 0:
		_on_item(iid)
	else:
		_show_section(true)


# ------------------------------------------------------------------ Equip

func _equip() -> void:
	var cid := _cid()
	_member_header(cid)
	var m: Dictionary = GameState.members[cid]
	for slot: String in ["weapon", "armor", "accessory"]:
		var iid: String = m.equip.get(slot, "")
		var nm: String = Content.item(iid).get("name", "—") if iid != "" else "—"
		var lock := "  🔒" if _locked_slots.get(cid + slot, false) else ""
		_btn("%s:  %s%s" % [slot.capitalize(), nm, lock], _on_slot.bind(cid, slot),
			str(Content.item(iid).get("desc", "Empty slot.")) + "   [%s: lock/unlock for Optimize]" % InputHub.prompt("context")).set_meta("slot", slot)
	_btn("Optimize (skips locked slots)", func() -> void:
		var locked: Array = []
		for s: String in ["weapon", "armor", "accessory"]:
			if _locked_slots.get(cid + s, false):
				locked.append(s)
		GameState.optimize_equipment(cid, locked)
		Audio.sfx("confirm")
		_show_section(true), "Equips the strongest gear you own in each unlocked slot.")
	_stat_line(cid)


func _stat_line(cid: String) -> void:
	var st := GameState.stats_for(cid)
	content.add_child(UITheme.label("ATK %d  MAG %d  DEF %d  RES %d  SPD %d  DEX %d" % [st.atk, st.mag, st.def, st.res, st.spd, st.dex], 18, UITheme.C_DIM))


func _input(event: InputEvent) -> void:
	if sections[section_idx] == "Equip" and event.is_action_pressed("context"):
		var f := get_viewport().gui_get_focus_owner()
		if f and f.has_meta("slot") and content.is_ancestor_of(f):
			get_viewport().set_input_as_handled()
			var key: String = _cid() + str(f.get_meta("slot"))
			_locked_slots[key] = not _locked_slots.get(key, false)
			_show_section(true)


func _on_slot(cid: String, slot: String) -> void:
	MenuScreen.clear(content)
	_member_header(cid)
	_header("Choose %s" % slot)
	var cur: String = GameState.members[cid].equip.get(slot, "")
	var before := GameState.stats_for(cid)
	var options: Array = []
	for iid: String in GameState.inventory.keys():
		if str(Content.item(iid).get("slot", "")) == slot and GameState.count_item(iid) > 0:
			options.append(iid)
	options.sort()
	if cur != "":
		_btn("Remove %s" % Content.item(cur).get("name", cur), func() -> void:
			GameState.equip(cid, slot, "")
			_show_section(true))
	for iid: String in options:
		var ok := GameState.can_equip(cid, iid)
		var preview := _preview(cid, slot, iid, before) if ok else "Cannot equip (weapon type not usable by this character)."
		var b := _btn(("%s  x%d" % [Content.item(iid).get("name", iid), GameState.count_item(iid)]) + ("" if ok else "  ✕"), func() -> void:
			if ok and GameState.equip(cid, slot, iid):
				Audio.sfx("confirm")
				_show_section(true)
			else:
				Audio.sfx("error"), preview)
		if not ok:
			b.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
	if options.is_empty():
		content.add_child(UITheme.label("No %s items in inventory." % slot, 18, UITheme.C_DIM))
	_btn("◀ Back", func() -> void: _show_section(true))
	MenuScreen.focus_first(content)


func _preview(cid: String, slot: String, iid: String, before: Dictionary) -> String:
	# Simulate the swap on a copy so the comparison is exact.
	var m: Dictionary = GameState.members[cid]
	var saved: String = m.equip.get(slot, "")
	m.equip[slot] = iid
	var after := GameState.stats_for(cid)
	m.equip[slot] = saved
	var parts: PackedStringArray = []
	for k: String in ["hp", "sp", "atk", "mag", "def", "res", "spd", "dex"]:
		var d := int(after[k]) - int(before[k])
		if d != 0:
			parts.append("%s %s%d" % [k.to_upper(), "+" if d > 0 else "", d])
	var it: Dictionary = Content.item(iid)
	var extra := ""
	if not it.get("element_res", {}).is_empty() or not it.get("status_res", {}).is_empty():
		extra = "  Special: " + str(it.get("desc", ""))
	return ("Change: " + (", ".join(parts) if not parts.is_empty() else "no stat change")) + extra


# ------------------------------------------------------------------ Jobs

func _jobs() -> void:
	var cid := _cid()
	_member_header(cid)
	var m: Dictionary = GameState.members[cid]
	content.add_child(UITheme.label("Choose a job to view abilities, set it as main job, or set it as your secondary skill set. Learned abilities are never lost; changing jobs is free. JP is earned by your current main job.", 16, UITheme.C_DIM))
	for jid: String in Content.table("jobs").keys():
		var j: Dictionary = Content.job(jid)
		var unlocked := jid in GameState.jobs_unlocked
		var usable := GameState.can_use_job(cid, jid)
		var learned := 0
		for a: Dictionary in j.get("abilities", []):
			if a.id in m.learned:
				learned += 1
		var tag := ""
		if jid == m.job:
			tag = "  [MAIN]"
		elif jid == m.secondary:
			tag = "  [SECONDARY]"
		var mastered := GameState.is_job_mastered(cid, jid)
		var t := "%s  rank %d  %d JP  (%d/%d learned)%s%s" % [j.get("name", jid), GameState.job_rank(cid, jid), int(m.jp.get(jid, 0)), learned, j.get("abilities", []).size(), tag, "  ★MASTERED" if mastered else ""]
		if not unlocked:
			t = "%s  — locked" % j.get("name", jid)
		var b := _btn(t, _on_job.bind(cid, jid), str(j.get("desc", "")) + ("" if unlocked else "  Unlock: " + str(j.get("unlock", "?"))))
		if not usable:
			b.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))


func _on_job(cid: String, jid: String) -> void:
	var j: Dictionary = Content.job(jid)
	if not jid in GameState.jobs_unlocked:
		info.text = "Locked. " + str(j.get("unlock", ""))
		Audio.sfx("error")
		return
	MenuScreen.clear(content)
	_member_header(cid)
	var m: Dictionary = GameState.members[cid]
	_header("%s — rank %d, %d JP available" % [j.get("name", jid), GameState.job_rank(cid, jid), int(m.jp.get(jid, 0))])
	var mods: PackedStringArray = []
	for k: String in j.get("stat_mod", {}).keys():
		mods.append("%s %+d%%" % [k.to_upper(), int(float(j.stat_mod[k]) * 100)])
	content.add_child(UITheme.label("Stat modifiers as main job: " + ", ".join(mods), 17, UITheme.C_DIM))
	var mastery: Dictionary = j.get("mastery", {})
	content.add_child(UITheme.label("Mastery reward — %s: %s" % [mastery.get("name", ""), mastery.get("desc", "")], 17, UITheme.C_DIM))
	if jid != m.job:
		_btn("Set as MAIN job", func() -> void:
			if GameState.set_job(cid, jid):
				Audio.sfx("confirm")
			_on_job(cid, jid), "Main job: stat modifiers apply, its learned skills appear in battle, and it earns JP.")
	if jid != m.job and jid != m.secondary:
		_btn("Set as SECONDARY skill set", func() -> void:
			if GameState.set_secondary(cid, jid):
				Audio.sfx("confirm")
				_on_job(cid, jid)
			else:
				Audio.sfx("error")
				info.text = "Learn at least one active ability from this job first.", "Use this job's learned active skills from a second battle command.")
	elif jid == m.secondary:
		_btn("Clear secondary", func() -> void:
			GameState.set_secondary(cid, "")
			_on_job(cid, jid))
	for a: Dictionary in j.get("abilities", []):
		var s: Dictionary = Content.skill(str(a.id))
		var reason := GameState.learn_block_reason(cid, jid, str(a.id))
		var state := "✓ learned" if a.id in m.learned else ("%d JP" % int(a.jp))
		var t := "%s %s  [%s]  rank %d  %s" % ["◆" if a.type == "active" else "◇", s.get("name", a.id), a.type, int(a.get("rank", 1)), state]
		var help := "%s%s%s" % [s.get("desc", ""), ("  SP %d." % int(s.get("sp", 0))) if int(s.get("sp", 0)) > 0 else "",
			("" if reason == "" or a.id in m.learned else "  — " + reason)]
		var b := _btn(t, _learn.bind(cid, jid, str(a.id)), help)
		if reason != "" and not a.id in m.learned:
			b.add_theme_color_override("font_color", Color(0.6, 0.6, 0.66))
	_btn("◀ Back to jobs", func() -> void: _show_section(true))
	MenuScreen.focus_first(content)


func _learn(cid: String, jid: String, aid: String) -> void:
	var reason := GameState.learn_block_reason(cid, jid, aid)
	if reason != "":
		Audio.sfx("error")
		info.text = reason
		return
	var a := GameState.ability_entry(jid, aid)
	if not await ConfirmBox.ask(self, "Learn %s for %d JP? (JP spent is permanent; the ability is kept forever.)" % [Content.skill(aid).get("name", aid), int(a.jp)], "Learn", "Cancel"):
		return
	if GameState.learn_ability(cid, jid, aid):
		Audio.sfx("levelup")
	_on_job(cid, jid)


# ------------------------------------------------------------------ Passives

func _passives() -> void:
	var cid := _cid()
	_member_header(cid)
	var m: Dictionary = GameState.members[cid]
	content.add_child(UITheme.label("Equip up to %d learned passives from any job. (%d/%d equipped)" % [GameState.MAX_PASSIVES, m.passives.size(), GameState.MAX_PASSIVES], 17, UITheme.C_DIM))
	var list := GameState.learned_passives(cid)
	if list.is_empty():
		content.add_child(UITheme.label("No passives learned yet. Learn them from the Jobs screen with JP.", 18))
	for pid: String in list:
		var s: Dictionary = Content.skill(pid)
		_btn("%s %s" % ["[■]" if pid in m.passives else "[  ]", s.get("name", pid)], func() -> void:
			if not GameState.toggle_passive(cid, pid):
				Audio.sfx("error")
				info.text = "All passive slots are full. Unequip one first."
			else:
				_show_section(true), str(s.get("desc", "")))


# ------------------------------------------------------------------ Journal

func _journal() -> void:
	_header("Journal")
	var ch: Dictionary = Content.get_entry("chapters", GameState.chapter)
	content.add_child(UITheme.label(str(ch.get("name", GameState.chapter)), 19, UITheme.C_ACCENT))
	var order := {"main": "Main Story", "personal": "Personal", "side": "Side Quests", "contract": "Contracts"}
	for typ: String in order.keys():
		var ids: Array = []
		for qid: String in GameState.quests.keys():
			if str(Content.quest(qid).get("type")) == typ:
				ids.append(qid)
		if ids.is_empty():
			continue
		content.add_child(UITheme.label(order[typ], 18, UITheme.C_DIM))
		ids.sort_custom(func(a: String, b: String) -> bool: return int(GameState.quests[a].done) < int(GameState.quests[b].done))
		for qid: String in ids:
			var q: Dictionary = Content.quest(qid)
			var qs: Dictionary = GameState.quests[qid]
			var mark := "✓ " if qs.done else ("◆ " if qid == GameState.tracked_quest else "• ")
			_btn(mark + str(q.get("title", qid)), _on_quest.bind(qid), _quest_summary(qid))
	if GameState.quests.is_empty():
		content.add_child(UITheme.label("No entries yet.", 18))


func _quest_summary(qid: String) -> String:
	var q: Dictionary = Content.quest(qid)
	var qs: Dictionary = GameState.quests[qid]
	var stages: Array = q.get("stages", [])
	var st := clampi(int(qs.stage), 0, maxi(0, stages.size() - 1))
	if qs.done:
		var oc: String = q.get("outcomes", {}).get(str(qs.outcome), "")
		return "Completed. " + oc
	return "Now: " + str(stages[st].get("objective", "")) if not stages.is_empty() else ""


func _on_quest(qid: String) -> void:
	MenuScreen.clear(content)
	var q: Dictionary = Content.quest(qid)
	var qs: Dictionary = GameState.quests[qid]
	_header(str(q.get("title", qid)))
	content.add_child(UITheme.label("%s  •  From: %s  •  %s" % [str(q.get("type", "")).capitalize(), q.get("giver", "—"), q.get("location", "")], 17, UITheme.C_DIM))
	var sm := UITheme.label(str(q.get("summary", "")), 18)
	sm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(sm)
	var stages: Array = q.get("stages", [])
	var cur := int(qs.stage)
	for i in stages.size():
		if i > cur and not qs.done:
			break
		var done_step: bool = i < cur or bool(qs.done)
		var l := UITheme.label(("✓ " if done_step else "▶ ") + str(stages[i].get("objective", "")), 17, UITheme.C_DIM if done_step else Color(0, 0, 0, 0))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(l)
	if not qs.done and cur < stages.size():
		var rc := UITheme.label("Recap: " + str(stages[cur].get("recap", "")), 17, UITheme.C_ACCENT)
		rc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(rc)
		_btn("Track this quest" if GameState.tracked_quest != qid else "Tracking ◆", func() -> void:
			GameState.tracked_quest = qid
			_on_quest(qid))
	elif qs.done and str(qs.outcome) != "":
		content.add_child(UITheme.label("Outcome: " + str(q.get("outcomes", {}).get(str(qs.outcome), qs.outcome)), 17))
	_btn("◀ Back", func() -> void: _show_section(true))
	MenuScreen.focus_first(content)


# ------------------------------------------------------------------ Bestiary

func _bestiary() -> void:
	_header("Bestiary")
	var ids: Array = GameState.bestiary.keys()
	ids.sort()
	if ids.is_empty():
		content.add_child(UITheme.label("No creatures recorded yet.", 18))
	for eid: String in ids:
		var e: Dictionary = Content.enemy(eid)
		var b: Dictionary = GameState.bestiary[eid]
		var known := int(b.get("defeated", 0)) >= 1 or GameState.has_flag("analyzed_" + eid)
		var help := str(e.get("desc", ""))
		if known:
			var s: Dictionary = e.get("stats", {})
			var weak: PackedStringArray = []
			var resist: PackedStringArray = []
			for el: String in e.get("elements", {}).keys():
				var v := float(e.elements[el])
				if v > 1.01:
					weak.append(el)
				elif v < 0.99:
					resist.append(el + (" (absorb)" if v < 0 else (" (immune)" if v == 0.0 else "")))
			help += "  HP %d  Lv %d  Role: %s.  Weak: %s.  Resists: %s." % [int(s.get("hp", 0)), int(e.get("level", 1)), e.get("role", ""),
				", ".join(weak) if not weak.is_empty() else "—", ", ".join(resist) if not resist.is_empty() else "—"]
		else:
			help += "  (Defeat or analyze it to learn more.)"
		_btn("%s   seen %d  defeated %d" % [e.get("name", eid), int(b.get("seen", 0)), int(b.get("defeated", 0))], func() -> void: info.text = help, help)


# ------------------------------------------------------------------ Map

func _map() -> void:
	_header("Map — Bellweather")
	var here: Dictionary = Content.map(GameState.map_id)
	var can_travel: bool = here.get("destination", false) and not here.has("encounters")
	content.add_child(UITheme.label("Fast travel is available between discovered places while in town." if can_travel else "Fast travel is unavailable here (dungeon or interior).", 17, UITheme.C_DIM))
	for mid: String in GameState.discovered:
		var md: Dictionary = Content.map(mid)
		var here_tag := "  (you are here)" if mid == GameState.map_id else ""
		var b := _btn("%s — %s%s" % [md.get("region", ""), md.get("name", mid), here_tag], func() -> void:
			if not can_travel or mid == GameState.map_id:
				Audio.sfx("error")
				return
			close()
			Router.enter_world(mid, "default"), "Travel to %s." % md.get("name", mid))
		if not can_travel:
			b.add_theme_color_override("font_color", Color(0.6, 0.6, 0.66))
	content.add_child(UITheme.label("The wider world map (the Rainward Line and beyond) opens in Chapter Two — not yet built.", 16, UITheme.C_DIM))


# ------------------------------------------------------------------ Settings / Save / Title

func _settings() -> void:
	_header("Settings")
	_btn("Open settings…", func() -> void:
		var s: Control = preload("res://scripts/ui/settings_ui.gd").new()
		add_child(s)
		await s.closed
		_show_section(true), "Gameplay, battle mode & speed, audio, accessibility and controls.")
	_btn("Resume", close, "Return to the game.")


func _save() -> void:
	_header("Save")
	var here: Dictionary = Content.map(GameState.map_id)
	if here.has("encounters"):
		content.add_child(UITheme.label("You can only save at a Bell Shrine in dangerous areas.", 18))
		_btn("Load a save…", _open_load, "Load a previous save.")
		return
	_btn("Save game…", func() -> void:
		var s: Control = preload("res://scripts/ui/save_ui.gd").new()
		s.mode = "save"
		add_child(s)
		await s.closed
		_show_section(true), "Choose a slot. Autosaves also happen at safe map transitions.")
	_btn("Load a save…", _open_load, "Load a previous save.")


func _open_load() -> void:
	var s: Control = preload("res://scripts/ui/save_ui.gd").new()
	s.mode = "load"
	add_child(s)
	await s.closed
	if is_inside_tree():
		close()


func _title() -> void:
	_header("Return to Title")
	_btn("Return to title screen", func() -> void:
		if await ConfirmBox.ask(self, "Return to the title screen? Unsaved progress will be lost.", "Return", "Stay"):
			close()
			Router.goto_title(), "Unsaved progress since your last save will be lost.")
