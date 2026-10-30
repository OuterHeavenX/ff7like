extends CanvasLayer
## On-screen touch controls for exploration: a floating left stick plus
## right-side action buttons. Each finger is tracked by its touch index so
## moving and interacting simultaneously works. Only ScreenTouch/ScreenDrag
## events are used (never emulated mouse), preventing double triggers.

const STICK_RADIUS := 78.0
const DEAD := 0.25

var root: Control
var stick_center := Vector2.ZERO
var stick_knob := Vector2.ZERO
var stick_index := -1
var buttons: Array = []           # [{action, label, rect_node}]
var _held: Dictionary = {}        # touch index -> action
var canvas: Control


class Pad extends Control:
	var owner_ctl: Node
	func _draw() -> void:
		owner_ctl._draw_pad(self)


func _ready() -> void:
	layer = 20
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)
	canvas = Pad.new()
	canvas.owner_ctl = self
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(canvas)
	_add_button("confirm", "A", Vector2(-110, -150), 46.0)
	_add_button("cancel", "B", Vector2(-200, -84), 38.0)
	_add_button("context", "X", Vector2(-200, -210), 32.0)
	_add_button("menu", "MENU", Vector2(-80, -290), 34.0)
	_add_button("journal", "LOG", Vector2(-60, 60), 28.0, true)
	_add_button("pause", "II", Vector2(-140, 60), 26.0, true)
	visible = InputHub.touch_controls_visible()
	InputHub.device_changed.connect(func(_k: String) -> void: visible = InputHub.touch_controls_visible())
	Settings.changed.connect(func(k: String) -> void:
		if k == "touch_controls":
			visible = InputHub.touch_controls_visible())


func _add_button(action: String, label: String, offset: Vector2, radius: float, top: bool = false) -> void:
	buttons.append({"action": action, "label": label, "offset": offset, "radius": radius, "top": top})


func _button_center(b: Dictionary) -> Vector2:
	var vp := root.get_global_rect().size
	var o: Vector2 = b.offset
	var safe := DisplayServer.get_display_safe_area()
	var inset := 0.0
	if safe.size.x > 0 and DisplayServer.screen_get_size().x > 0:
		inset = float(DisplayServer.screen_get_size().x - safe.end.x) * vp.x / float(DisplayServer.screen_get_size().x)
	return Vector2(vp.x + o.x - inset, (o.y if b.top else vp.y + o.y))


func _world_menu_open() -> bool:
	var w := get_parent()
	return w != null and bool(w.get("menu_open"))


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			var hit := _hit_button(t.position)
			if hit != "":
				_held[t.index] = hit
				InputHub.press_virtual(hit, true)
				get_viewport().set_input_as_handled()
				canvas.queue_redraw()
				return
			var vp := root.get_global_rect().size
			if not _world_menu_open() and stick_index == -1 and t.position.x < vp.x * 0.42 and t.position.y > vp.y * 0.35:
				stick_index = t.index
				stick_center = t.position
				stick_knob = t.position
				get_viewport().set_input_as_handled()
				canvas.queue_redraw()
		else:
			if _held.has(t.index):
				InputHub.press_virtual(_held[t.index], false)
				_held.erase(t.index)
				get_viewport().set_input_as_handled()
				canvas.queue_redraw()
			if t.index == stick_index:
				stick_index = -1
				InputHub.virtual_move = Vector2.ZERO
				get_viewport().set_input_as_handled()
				canvas.queue_redraw()
	elif event is InputEventScreenDrag:
		var dr := event as InputEventScreenDrag
		if dr.index == stick_index:
			var d := dr.position - stick_center
			if d.length() > STICK_RADIUS:
				# Floating stick follows the finger so it never "sticks".
				stick_center += d.normalized() * (d.length() - STICK_RADIUS)
				d = dr.position - stick_center
			stick_knob = dr.position
			var v := d / STICK_RADIUS
			InputHub.virtual_move = v if v.length() > DEAD else Vector2.ZERO
			get_viewport().set_input_as_handled()
			canvas.queue_redraw()


func _hit_button(p: Vector2) -> String:
	var menu := _world_menu_open()
	for b: Dictionary in buttons:
		if menu and b.action != "cancel":
			continue
		if p.distance_to(_button_center(b)) <= float(b.radius) + 10.0:
			return b.action
	return ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_held.clear()
		stick_index = -1


func _process(_d: float) -> void:
	if visible:
		canvas.queue_redraw()


func _draw_pad(c: Control) -> void:
	var menu := _world_menu_open()
	var f := UITheme.bold()
	if not menu:
		var vp := root.get_global_rect().size
		var base := stick_center if stick_index != -1 else Vector2(150, vp.y - 150)
		c.draw_circle(base, STICK_RADIUS, Color(1, 1, 1, 0.08))
		c.draw_arc(base, STICK_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.35), 2.0)
		var knob := stick_knob if stick_index != -1 else base
		if knob.distance_to(base) > STICK_RADIUS:
			knob = base + (knob - base).normalized() * STICK_RADIUS
		c.draw_circle(knob, 30, Color(1, 0.85, 0.55, 0.45))
	for b: Dictionary in buttons:
		if menu and b.action != "cancel":
			continue
		var held: bool = b.action in _held.values()
		var center := _button_center(b)
		var r: float = b.radius
		c.draw_circle(center, r, Color(1, 0.8, 0.45, 0.45) if held else Color(0, 0, 0, 0.35))
		c.draw_arc(center, r, 0, TAU, 40, Color(1, 0.85, 0.6, 0.75), 2.0)
		var fs := 22 if str(b.label).length() <= 2 else 14
		var sz := f.get_string_size(b.label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		c.draw_string(f, center - Vector2(sz.x / 2, -fs / 3.0), b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.9))
