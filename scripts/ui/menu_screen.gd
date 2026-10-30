class_name MenuScreen
extends Control
## Base for full-screen menus: dims the scene, closes on Cancel, and restores
## focus. Every screen is escapable with controller B / Esc / touch Back.

signal closed

var _closing := false
var back_button: Button


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP


func add_dim(alpha: float = 0.72) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.05, alpha)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


## Visible tap target for touch users (B also works).
func add_back_button(parent: Control) -> Button:
	back_button = UITheme.button("◀ Back", back, 48)
	back_button.focus_mode = Control.FOCUS_NONE
	parent.add_child(back_button)
	return back_button


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _closing:
		return
	if event.is_action_pressed("cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		Audio.sfx("cancel")
		back()
	else:
		handle_input(event)


## Override for extra shortcuts (tabs, context action).
func handle_input(_event: InputEvent) -> void:
	pass


## Override to implement nested navigation; default closes the screen.
func back() -> void:
	close()


func close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	queue_free()


static func clear(c: Node) -> void:
	for ch in c.get_children():
		c.remove_child(ch)
		ch.queue_free()


static func focus_first(c: Node) -> void:
	for ch in c.get_children():
		if ch is Control and (ch as Control).focus_mode != Control.FOCUS_NONE and (ch as Control).visible:
			if ch is BaseButton and (ch as BaseButton).disabled:
				continue
			(ch as Control).call_deferred("grab_focus")
			return
		if ch.get_child_count() > 0:
			focus_first(ch)
			return
