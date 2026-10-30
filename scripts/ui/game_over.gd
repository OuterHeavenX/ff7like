extends CanvasLayer
## Defeat screen: retry the battle (party restored, nothing lost), load the
## latest save, or return to title. No hidden permanent consequences.

signal chosen(choice: String)


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UITheme.get_theme()
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.02, 0.05, 0.96)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_CENTER)
	vb.custom_minimum_size = Vector2(520, 0)
	vb.position = Vector2(-260, -150)
	vb.add_theme_constant_override("separation", 10)
	root.add_child(vb)
	var t := UITheme.title_label("The light gutters out…", 34)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var info := UITheme.label("Retry restores the party to how it was before this battle. Nothing is lost. You may change equipment or party from the menu after retrying a story battle with the Adjust option.", 18, UITheme.C_DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(info)
	var b1 := UITheme.button("Retry battle", func() -> void: chosen.emit("retry"), 52)
	vb.add_child(b1)
	vb.add_child(UITheme.button("Adjust party & equipment, then retry", func() -> void: chosen.emit("prepare"), 52))
	vb.add_child(UITheme.button("Load latest save", func() -> void: chosen.emit("load"), 52))
	vb.add_child(UITheme.button("Return to title", func() -> void: chosen.emit("title"), 52))
	Audio.play_music("theme_wren")
	b1.call_deferred("grab_focus")
