extends Node
## Scene transitions and top-level flow: title, world, battle overlay, game over.
## Owns the fade layer and the focus-loss pause overlay.

signal battle_finished(result: Dictionary)

const TITLE_SCENE := "res://scenes/ui/title.tscn"
const WORLD_SCENE := "res://scenes/world/world.tscn"
const BATTLE_SCENE := "res://scenes/battle/battle.tscn"

var world: Node = null
var battle: Node = null
var _fade_layer: CanvasLayer
var _fade: ColorRect
var _pause_layer: CanvasLayer
var _toast_layer: CanvasLayer
var _toast_box: VBoxContainer
var busy: bool = false
## Development-only: the traversal harness sets this so battles auto-play.
## Never set by normal play; the harness file is excluded from exports.
var debug_auto_battle: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 100
	add_child(_fade_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.02, 0.02, 0.05, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_layer.add_child(_fade)
	_toast_layer = CanvasLayer.new()
	_toast_layer.layer = 90
	add_child(_toast_layer)
	_toast_box = VBoxContainer.new()
	_toast_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_box.position = Vector2(-260, 70)
	_toast_box.custom_minimum_size = Vector2(520, 0)
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_layer.add_child(_toast_box)
	GameState.notify.connect(toast)
	get_tree().root.focus_exited.connect(_on_focus_lost)


func fade_out(t: float = 0.35) -> void:
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, t)
	await tw.finished


func fade_in(t: float = 0.35) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, t)
	await tw.finished
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _swap_main(scene_path: String) -> Node:
	if battle and is_instance_valid(battle):
		battle.queue_free()
		battle = null
	var tree := get_tree()
	var old := tree.current_scene
	var packed: PackedScene = load(scene_path)
	var inst := packed.instantiate()
	tree.root.add_child(inst)
	tree.current_scene = inst
	if old and old != inst:
		old.queue_free()
	return inst


func goto_title() -> void:
	busy = true
	await fade_out()
	get_tree().paused = false
	GameState.active = false
	world = null
	InputHub.release_all()
	_swap_main(TITLE_SCENE)
	await fade_in()
	busy = false


func start_new_game() -> void:
	GameState.new_game()
	await enter_world(GameState.map_id, "", GameState.map_pos)
	if world and world.has_method("run_event"):
		var opening: String = Content.get_entry("chapters", "_start").get("opening_event", "")
		if opening != "":
			world.run_event(opening)


func continue_game(slot: String) -> bool:
	if not Saves.load_from(slot):
		return false
	await enter_world(GameState.map_id, "", GameState.map_pos)
	if Saves.last_error != "":
		toast(Saves.last_error)
	return true


## Loads (or reuses) the world scene and places the player on a map.
func enter_world(map_id: String, spawn: String = "", pos: Vector2i = Vector2i(-1, -1), facing: int = -1) -> void:
	busy = true
	InputHub.release_all()
	await fade_out()
	get_tree().paused = false
	if world == null or not is_instance_valid(world):
		world = _swap_main(WORLD_SCENE)
		await get_tree().process_frame
	world.load_map(map_id, spawn, pos, facing)
	await get_tree().process_frame
	await fade_in()
	busy = false
	if world.has_method("on_map_entered"):
		world.on_map_entered()


## Runs a battle over the hidden world. Awaitable; returns the result dictionary
## {outcome: "victory"|"defeat"|"escape", ...}.
func run_battle(encounter_id: String, opts: Dictionary = {}) -> Dictionary:
	busy = true
	InputHub.release_all()
	Audio.sfx("encounter")
	await _battle_transition_out()
	var packed: PackedScene = load(BATTLE_SCENE)
	battle = packed.instantiate()
	if world:
		world.set_world_active(false)
	get_tree().root.add_child(battle)
	battle.setup(encounter_id, opts)
	await fade_in(0.25)
	var result: Dictionary = await battle.finished
	await fade_out(0.35)
	if is_instance_valid(battle):
		battle.queue_free()
	battle = null
	if world and is_instance_valid(world):
		world.set_world_active(true)
	await get_tree().process_frame
	busy = false
	battle_finished.emit(result)
	if result.get("outcome") == "defeat" and not opts.get("defeat_continues", false):
		return await game_over(encounter_id, opts)
	await fade_in(0.35)
	return result


func _battle_transition_out() -> void:
	if bool(Settings.get_value("reduce_flashing")) or bool(Settings.get_value("reduce_motion")):
		await fade_out(0.3)
		return
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	for i in 3:
		tw.tween_property(_fade, "color", Color(0.9, 0.85, 1.0, 0.55), 0.06)
		tw.tween_property(_fade, "color", Color(0.02, 0.02, 0.05, 0.0), 0.08)
	tw.tween_property(_fade, "color", Color(0.02, 0.02, 0.05, 1.0), 0.25)
	await tw.finished


## Returns the final battle result after retries, or {outcome: "abandoned"}
## when the player loads a save or quits (callers must stop their script).
func game_over(encounter_id: String, opts: Dictionary) -> Dictionary:
	var scene: PackedScene = load("res://scenes/ui/game_over.tscn")
	var go := scene.instantiate()
	get_tree().root.add_child(go)
	await fade_in(0.5)
	var choice: String = await go.chosen
	go.queue_free()
	match choice:
		"retry":
			# Restore party to pre-battle condition and retry; nothing is lost.
			if opts.has("snapshot"):
				GameState.from_dict(opts.snapshot)
			return await run_battle(encounter_id, opts.duplicate())
		"prepare":
			if opts.has("snapshot"):
				GameState.from_dict(opts.snapshot)
			if world and is_instance_valid(world):
				await fade_in(0.3)
				await world.open_menu("")
			return await run_battle(encounter_id, opts.duplicate())
		"load":
			var slot := Saves.latest_slot()
			if world and is_instance_valid(world):
				world.events.abort()
			if slot == "" or not await continue_game(slot):
				await goto_title()
		_:
			await goto_title()
	return {"outcome": "abandoned"}


func toast(text: String) -> void:
	var p := PanelContainer.new()
	p.theme = UITheme.get_theme()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(l)
	_toast_box.add_child(p)
	p.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.2)
	tw.tween_interval(2.6)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)


func _on_focus_lost() -> void:
	if not bool(Settings.get_value("pause_on_focus_loss")) or not GameState.active:
		return
	if _pause_layer != null or OS.has_feature("editor_hint"):
		return
	show_pause_overlay("Paused — focus lost.\nPress any button or tap to resume.")


func show_pause_overlay(text: String) -> void:
	if _pause_layer != null:
		return
	InputHub.release_all()
	var was_paused := get_tree().paused
	get_tree().paused = true
	_pause_layer = CanvasLayer.new()
	_pause_layer.layer = 95
	add_child(_pause_layer)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_layer.add_child(bg)
	var l := Label.new()
	l.theme = UITheme.get_theme()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_layer.add_child(l)
	_pause_layer.set_meta("was_paused", was_paused)
	# Small grace period so the event that caused focus return is ignored.
	_pause_layer.set_meta("t", Time.get_ticks_msec())


func _input(event: InputEvent) -> void:
	if _pause_layer == null:
		return
	var pressed := (event is InputEventKey and event.is_pressed()) or \
		(event is InputEventJoypadButton and event.is_pressed()) or \
		(event is InputEventScreenTouch and event.is_pressed()) or \
		(event is InputEventMouseButton and event.is_pressed())
	if pressed and Time.get_ticks_msec() - int(_pause_layer.get_meta("t")) > 300:
		get_tree().paused = bool(_pause_layer.get_meta("was_paused"))
		_pause_layer.queue_free()
		_pause_layer = null
		get_viewport().set_input_as_handled()
