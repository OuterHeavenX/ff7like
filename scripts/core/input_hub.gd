extends Node
## Centralized input layer: builds the InputMap, applies user rebinding,
## tracks the active input method (keyboard / gamepad / touch) with hysteresis,
## and receives virtual presses from on-screen touch controls.
## Gameplay code queries actions only; it never reads raw key codes.

signal device_changed(kind: String)
signal bindings_changed

const GAME_ACTIONS := ["move_up", "move_down", "move_left", "move_right", "confirm",
	"cancel", "context", "menu", "journal", "pause", "tab_prev", "tab_next"]

## Actions that the player may rebind (movement included).
const REBINDABLE := GAME_ACTIONS

const ACTION_LABELS := {
	"move_up": "Move Up", "move_down": "Move Down", "move_left": "Move Left",
	"move_right": "Move Right", "confirm": "Confirm / Interact", "cancel": "Cancel / Run",
	"context": "Context Action", "menu": "Menu", "journal": "Journal / Map",
	"pause": "Pause", "tab_prev": "Previous Tab / Member", "tab_next": "Next Tab / Member",
}

## UI mirrors keep Control focus navigation consistent with gameplay bindings.
const UI_MIRRORS := {
	"ui_up": "move_up", "ui_down": "move_down", "ui_left": "move_left",
	"ui_right": "move_right", "ui_accept": "confirm", "ui_cancel": "cancel",
}

var active_device: String = "kb"
var virtual_move: Vector2 = Vector2.ZERO
var touch_seen: bool = false
var _last_switch_ms: int = 0
var _virtual_held: Dictionary = {}


static func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


static func _btn(b: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	return e


static func _axis(a: JoyAxis, v: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = a
	e.axis_value = v
	return e


func default_events(action: String) -> Array:
	match action:
		"move_up": return [_key(KEY_W), _key(KEY_UP), _btn(JOY_BUTTON_DPAD_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)]
		"move_down": return [_key(KEY_S), _key(KEY_DOWN), _btn(JOY_BUTTON_DPAD_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)]
		"move_left": return [_key(KEY_A), _key(KEY_LEFT), _btn(JOY_BUTTON_DPAD_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)]
		"move_right": return [_key(KEY_D), _key(KEY_RIGHT), _btn(JOY_BUTTON_DPAD_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)]
		"confirm": return [_key(KEY_ENTER), _key(KEY_SPACE), _key(KEY_Z), _key(KEY_KP_ENTER), _btn(JOY_BUTTON_A)]
		"cancel": return [_key(KEY_ESCAPE), _key(KEY_X), _key(KEY_BACKSPACE), _key(KEY_SHIFT), _btn(JOY_BUTTON_B)]
		"context": return [_key(KEY_F), _key(KEY_C), _btn(JOY_BUTTON_X)]
		"menu": return [_key(KEY_TAB), _key(KEY_V), _btn(JOY_BUTTON_Y)]
		"journal": return [_key(KEY_J), _key(KEY_M), _btn(JOY_BUTTON_BACK)]
		"pause": return [_key(KEY_P), _key(KEY_F1), _btn(JOY_BUTTON_START)]
		"tab_prev": return [_key(KEY_Q), _key(KEY_PAGEUP), _btn(JOY_BUTTON_LEFT_SHOULDER)]
		"tab_next": return [_key(KEY_E), _key(KEY_PAGEDOWN), _btn(JOY_BUTTON_RIGHT_SHOULDER)]
	return []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	apply_bindings()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	if OS.has_feature("web") and DisplayServer.is_touchscreen_available():
		active_device = "touch"
		touch_seen = true
	elif not Input.get_connected_joypads().is_empty():
		active_device = "pad"


func apply_bindings() -> void:
	var custom: Dictionary = Settings.get_value("bindings")
	for action: String in GAME_ACTIONS:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		InputMap.add_action(action, 0.45)
		var events: Array = []
		if custom.has(action) and custom[action] is Array and not custom[action].is_empty():
			for d: Variant in custom[action]:
				var ev := deserialize_event(d)
				if ev != null:
					events.append(ev)
		if events.is_empty():
			events = default_events(action)
		for ev: InputEvent in events:
			InputMap.action_add_event(action, ev)
	for ui: String in UI_MIRRORS.keys():
		if not InputMap.has_action(ui):
			InputMap.add_action(ui, 0.5)
		InputMap.action_erase_events(ui)
		for ev: InputEvent in InputMap.action_get_events(UI_MIRRORS[ui]):
			InputMap.action_add_event(ui, ev)
		# Keep Enter/arrow keys working in menus even after exotic rebinding.
		match ui:
			"ui_up": InputMap.action_add_event(ui, _key(KEY_UP))
			"ui_down": InputMap.action_add_event(ui, _key(KEY_DOWN))
			"ui_left": InputMap.action_add_event(ui, _key(KEY_LEFT))
			"ui_right": InputMap.action_add_event(ui, _key(KEY_RIGHT))
			"ui_accept": InputMap.action_add_event(ui, _key(KEY_ENTER))
			"ui_cancel": InputMap.action_add_event(ui, _key(KEY_ESCAPE))
	bindings_changed.emit()


static func serialize_event(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var code: int = k.physical_keycode if k.physical_keycode != 0 else k.keycode
		return {"type": "key", "code": code}
	if ev is InputEventJoypadButton:
		return {"type": "joy_button", "index": (ev as InputEventJoypadButton).button_index}
	if ev is InputEventJoypadMotion:
		var m := ev as InputEventJoypadMotion
		return {"type": "joy_axis", "axis": m.axis, "value": signf(m.axis_value)}
	return {}


static func deserialize_event(d: Variant) -> InputEvent:
	if not d is Dictionary:
		return null
	match str(d.get("type", "")):
		"key":
			var e := InputEventKey.new()
			e.physical_keycode = int(d.get("code", 0)) as Key
			return e
		"joy_button":
			var b := InputEventJoypadButton.new()
			b.button_index = int(d.get("index", 0)) as JoyButton
			return b
		"joy_axis":
			var m := InputEventJoypadMotion.new()
			m.axis = int(d.get("axis", 0)) as JoyAxis
			m.axis_value = float(d.get("value", 1.0))
			return m
	return null


static func events_match(a: InputEvent, b: InputEvent) -> bool:
	return serialize_event(a) == serialize_event(b) and not serialize_event(a).is_empty()


## Rebinds one slot of an action. Returns the name of an action that lost this
## binding because of a conflict (or "" if none).
func rebind(action: String, ev: InputEvent) -> String:
	var custom: Dictionary = Settings.get_value("bindings").duplicate(true)
	var conflict := ""
	for other: String in GAME_ACTIONS:
		if other == action:
			continue
		var evs: Array = InputMap.action_get_events(other)
		for existing: InputEvent in evs:
			if events_match(existing, ev):
				conflict = other
				var kept: Array = []
				for e2: InputEvent in evs:
					if not events_match(e2, ev):
						kept.append(serialize_event(e2))
				custom[other] = kept
	var mine: Array = []
	var is_pad := ev is InputEventJoypadButton or ev is InputEventJoypadMotion
	# Replace the first binding of the same device family; keep the rest.
	var replaced := false
	for existing: InputEvent in InputMap.action_get_events(action):
		var existing_pad := existing is InputEventJoypadButton or existing is InputEventJoypadMotion
		if not replaced and existing_pad == is_pad:
			mine.append(serialize_event(ev))
			replaced = true
		elif not events_match(existing, ev):
			mine.append(serialize_event(existing))
	if not replaced:
		mine.push_front(serialize_event(ev))
	custom[action] = mine
	Settings.set_value("bindings", custom)
	apply_bindings()
	return conflict


func reset_bindings() -> void:
	Settings.set_value("bindings", {})
	apply_bindings()


func describe_event(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var code: Key = k.physical_keycode if k.physical_keycode != 0 else k.keycode
		return OS.get_keycode_string(code)
	if ev is InputEventJoypadButton:
		return pad_button_name((ev as InputEventJoypadButton).button_index)
	if ev is InputEventJoypadMotion:
		var m := ev as InputEventJoypadMotion
		var names := {JOY_AXIS_LEFT_X: ["L-Stick Left", "L-Stick Right"], JOY_AXIS_LEFT_Y: ["L-Stick Up", "L-Stick Down"],
			JOY_AXIS_RIGHT_X: ["R-Stick Left", "R-Stick Right"], JOY_AXIS_RIGHT_Y: ["R-Stick Up", "R-Stick Down"],
			JOY_AXIS_TRIGGER_LEFT: ["LT", "LT"], JOY_AXIS_TRIGGER_RIGHT: ["RT", "RT"]}
		var pair: Array = names.get(m.axis, ["Axis-", "Axis+"])
		return pair[0] if m.axis_value < 0 else pair[1]
	return "?"


static func pad_button_name(b: int) -> String:
	match b:
		JOY_BUTTON_A: return "A"
		JOY_BUTTON_B: return "B"
		JOY_BUTTON_X: return "X"
		JOY_BUTTON_Y: return "Y"
		JOY_BUTTON_BACK: return "View"
		JOY_BUTTON_START: return "Menu"
		JOY_BUTTON_LEFT_SHOULDER: return "L1"
		JOY_BUTTON_RIGHT_SHOULDER: return "R1"
		JOY_BUTTON_DPAD_UP: return "D-Up"
		JOY_BUTTON_DPAD_DOWN: return "D-Down"
		JOY_BUTTON_DPAD_LEFT: return "D-Left"
		JOY_BUTTON_DPAD_RIGHT: return "D-Right"
		JOY_BUTTON_LEFT_STICK: return "L3"
		JOY_BUTTON_RIGHT_STICK: return "R3"
	return "Pad %d" % b


## Short glyph text for the current device, used by on-screen prompts.
func prompt(action: String) -> String:
	var want_pad := active_device == "pad"
	if active_device == "touch":
		match action:
			"confirm": return "Tap"
			"cancel": return "Back"
			"menu": return "Menu"
	for ev: InputEvent in InputMap.action_get_events(action) if InputMap.has_action(action) else []:
		var is_pad := ev is InputEventJoypadButton or ev is InputEventJoypadMotion
		if is_pad == want_pad:
			return describe_event(ev)
	return ACTION_LABELS.get(action, action)


func bindings_text(action: String) -> String:
	var parts: PackedStringArray = []
	for ev: InputEvent in InputMap.action_get_events(action):
		parts.append(describe_event(ev))
	return ", ".join(parts)


func _input(event: InputEvent) -> void:
	var kind := ""
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		kind = "touch"
		touch_seen = true
	elif event is InputEventKey and event.is_pressed():
		kind = "kb"
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION and event.is_pressed():
		kind = "kb"
	elif event is InputEventJoypadButton and event.is_pressed():
		kind = "pad"
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.6:
		kind = "pad"
	if kind != "" and kind != active_device:
		var now := Time.get_ticks_msec()
		# Hysteresis prevents prompt flicker from incidental input.
		if now - _last_switch_ms > 250:
			_last_switch_ms = now
			active_device = kind
			device_changed.emit(kind)


func touch_controls_visible() -> bool:
	match str(Settings.get_value("touch_controls")):
		"on": return true
		"off": return false
	return touch_seen or (OS.has_feature("web") and DisplayServer.is_touchscreen_available()) \
		or OS.has_feature("mobile")


## Movement vector combining actions and the virtual stick. 4-way grid
## movement resolves the dominant axis downstream.
func move_vector() -> Vector2:
	var v := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if virtual_move.length() > v.length():
		v = virtual_move
	return v


func press_virtual(action: String, pressed: bool) -> void:
	if pressed == _virtual_held.get(action, false):
		return
	_virtual_held[action] = pressed
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)
	var ui := ""
	for k: String in UI_MIRRORS.keys():
		if UI_MIRRORS[k] == action:
			ui = k
	if ui != "":
		var ev2 := InputEventAction.new()
		ev2.action = ui
		ev2.pressed = pressed
		Input.parse_input_event(ev2)


func release_all() -> void:
	virtual_move = Vector2.ZERO
	for action: String in _virtual_held.keys():
		if _virtual_held[action]:
			press_virtual(action, false)
	for action: String in GAME_ACTIONS:
		Input.action_release(action)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		release_all()


func _on_joy_connection_changed(_device: int, connected: bool) -> void:
	release_all()
	if connected:
		active_device = "pad"
		device_changed.emit("pad")
