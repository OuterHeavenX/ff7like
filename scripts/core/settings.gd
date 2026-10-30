extends Node
## Machine-local preferences (display, audio, controls, accessibility).
## Stored separately from gameplay saves in user://settings.cfg so that
## portable save files never carry device-specific configuration.

signal changed(key: String)

const PATH := "user://settings.cfg"

const DEFAULTS := {
	"text_speed": 2,            # 0 slow, 1 normal, 2 fast, 3 instant
	"ui_scale": 1.0,            # 0.85 .. 1.5
	"battle_mode": "wait",      # "wait" | "active"
	"battle_speed": 3,          # 1 (slowest) .. 5 (fastest)
	"fast_animations": false,
	"reduce_motion": false,
	"reduce_flashing": false,
	"camera_shake": true,
	"music_volume": 0.7,
	"sfx_volume": 0.8,
	"high_contrast": false,
	"quest_markers": true,
	"touch_controls": "auto",   # "auto" | "on" | "off"
	"visual_preset": "standard",# "standard" | "low"
	"pause_on_focus_loss": true,
	"show_fps": false,
	"bindings": {},             # action -> Array of serialized events
}

var values: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()


func load_settings() -> void:
	values = DEFAULTS.duplicate(true)
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for key: String in DEFAULTS.keys():
			if cfg.has_section_key("settings", key):
				var v: Variant = cfg.get_value("settings", key)
				if typeof(v) == typeof(DEFAULTS[key]) or (typeof(DEFAULTS[key]) == TYPE_FLOAT and typeof(v) == TYPE_INT):
					values[key] = v
	_clamp_values()


func _clamp_values() -> void:
	values.text_speed = clampi(int(values.text_speed), 0, 3)
	values.ui_scale = clampf(float(values.ui_scale), 0.85, 1.5)
	values.battle_speed = clampi(int(values.battle_speed), 1, 5)
	values.music_volume = clampf(float(values.music_volume), 0.0, 1.0)
	values.sfx_volume = clampf(float(values.sfx_volume), 0.0, 1.0)
	if not values.battle_mode in ["wait", "active"]:
		values.battle_mode = "wait"
	if not values.touch_controls in ["auto", "on", "off"]:
		values.touch_controls = "auto"
	if not values.visual_preset in ["standard", "low"]:
		values.visual_preset = "standard"


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key: String in values.keys():
		cfg.set_value("settings", key, values[key])
	cfg.save(PATH)


func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


func set_value(key: String, v: Variant) -> void:
	values[key] = v
	_clamp_values()
	save_settings()
	changed.emit(key)


func reset_defaults() -> void:
	var keep_bindings: Dictionary = values.get("bindings", {})
	values = DEFAULTS.duplicate(true)
	values.bindings = keep_bindings
	save_settings()
	for key: String in values.keys():
		changed.emit(key)


## Characters per second for dialogue reveal; 0 means instant.
func text_cps() -> float:
	match int(values.text_speed):
		0: return 28.0
		1: return 48.0
		2: return 90.0
	return 0.0


## Battle time multiplier from the 1..5 speed setting.
func battle_time_scale() -> float:
	return [0.6, 0.8, 1.0, 1.3, 1.7][int(values.battle_speed) - 1]
