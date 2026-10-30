extends Node3D
## Field exploration scene: owns the current map, actors, camera, HUD layers,
## the event runner, interaction, step triggers and random encounters.

const WALK_SPEED := 4.6
const RUN_SPEED := 7.6
const CAMERA_FOV := 30.0

var map_id: String = ""
var map_data: Dictionary = {}
var grid: MapGrid
var geometry: Node3D
var actors_root: Node3D
var player: FieldActor
var npcs: Dictionary = {}          # id -> FieldActor
var occupied: Dictionary = {}      # Vector2i -> String (npc id / "chest:<id>" / "solid")
var chests: Dictionary = {}        # Vector2i -> chest dict
var camera: Camera3D
var cam_target: Vector3
var env: WorldEnvironment
var hud: Node
var dialogue: Node
var touch: Node
var menu_layer: CanvasLayer
var events: EventRunner
var steps_since_battle: int = 0
var encounter_rng := RandomNumberGenerator.new()
var _wander_t: float = 0.0
var _active: bool = true
var _input_block_until: int = 0
var menu_open: bool = false
var _last_prompt_key: String = ""


func _ready() -> void:
	actors_root = Node3D.new()
	actors_root.name = "Actors"
	add_child(actors_root)
	camera = Camera3D.new()
	camera.fov = CAMERA_FOV
	camera.near = 0.5
	camera.far = 120.0
	camera.rotation_degrees = Vector3(-FieldActor.CAMERA_PITCH_DEG, 0, 0)
	add_child(camera)
	camera.current = true
	env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.03, 0.06)
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	add_child(env)
	hud = preload("res://scripts/ui/hud.gd").new()
	add_child(hud)
	dialogue = preload("res://scripts/ui/dialogue_box.gd").new()
	add_child(dialogue)
	touch = preload("res://scripts/ui/touch_controls.gd").new()
	add_child(touch)
	menu_layer = CanvasLayer.new()
	menu_layer.layer = 40
	add_child(menu_layer)
	events = EventRunner.new()
	events.world = self
	events.dialogue = dialogue
	add_child(events)
	encounter_rng.seed = GameState.rng_seed ^ 0x5eed


func set_world_active(on: bool) -> void:
	_active = on
	visible = on
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	for layer: Node in [hud, touch]:
		if layer is CanvasLayer:
			(layer as CanvasLayer).visible = on
	if on:
		camera.current = true
		_input_block_until = Time.get_ticks_msec() + 250
		Audio.play_music(str(map_data.get("music", "")))


# ------------------------------------------------------------------ map loading

func load_map(id: String, spawn: String = "", pos: Vector2i = Vector2i(-1, -1), facing: int = -1) -> void:
	map_id = id
	map_data = Content.map(id)
	if map_data.is_empty():
		push_error("Unknown map " + id)
		return
	if geometry:
		geometry.queue_free()
	for c in actors_root.get_children():
		c.queue_free()
	npcs.clear()
	occupied.clear()
	chests.clear()
	var builder := MapBuilder.new()
	# Mark opened chests so the builder draws them open.
	var props: Array = map_data.get("props", []).duplicate(true)
	for ch: Dictionary in map_data.get("chests", []):
		props.append({"t": "chest", "at": ch.at, "_opened": GameState.granted.has("chest:" + str(ch.id))})
	var built_map := map_data.duplicate()
	built_map["props"] = props
	built_map["rows"] = apply_patches(map_data)
	geometry = builder.build(built_map)
	grid = builder.grid
	add_child(geometry)
	var bg: Array = map_data.get("background", [0.03, 0.03, 0.06])
	env.environment.background_color = Color(bg[0], bg[1], bg[2])
	# Static solids from props.
	for p: Dictionary in map_data.get("props", []):
		if p.get("solid", _prop_solid_default(str(p.get("t", "")))):
			var wide := 2 if str(p.get("t")) == "stall" else int(p.get("w", 1))
			if str(p.get("t")) == "rug":
				continue
			for k in maxi(1, wide):
				occupied[Vector2i(int(p.at[0]) + k, int(p.at[1]))] = "solid"
	for ch: Dictionary in map_data.get("chests", []):
		var cp := Vector2i(int(ch.at[0]), int(ch.at[1]))
		chests[cp] = ch
		occupied[cp] = "chest:" + str(ch.id)
	_compute_safe_tiles()
	# Player
	var start := pos
	var face := facing
	if spawn != "" and map_data.get("spawns", {}).has(spawn):
		var s: Array = map_data.spawns[spawn]
		start = Vector2i(int(s[0]), int(s[1]))
		if s.size() > 2:
			face = FieldActor.facing_from_name(str(s[2]))
	if start == Vector2i(-1, -1) or not grid.inside(start.x, start.y):
		var d: Array = map_data.get("spawns", {}).get("default", [1, 1])
		start = Vector2i(int(d[0]), int(d[1]))
	player = FieldActor.new()
	player.setup("player", Content.character(GameState.lead()).get("sprite", GameState.lead()))
	actors_root.add_child(player)
	player.place(start, grid.stand_height(start.x, start.y))
	player.face(face if face >= 0 else GameState.map_facing)
	GameState.map_id = id
	GameState.map_pos = start
	_spawn_npcs()
	cam_target = player.position
	_snap_camera()
	steps_since_battle = 0
	Audio.play_music(str(map_data.get("music", "")))
	hud.show_location(str(map_data.get("name", id)), str(map_data.get("region", "")))
	if not id in GameState.discovered and map_data.get("destination", false):
		GameState.discovered.append(id)


## Conditional tile patches (e.g. a drained channel) applied before building.
static func apply_patches(m: Dictionary) -> Array:
	var rows: Array = m.get("rows", []).duplicate()
	for patch: Dictionary in m.get("patches", []):
		if not GameState.check(patch.get("cond", "")):
			continue
		var px := int(patch.at[0])
		var py := int(patch.at[1])
		var prow: Array = patch.rows
		for i in prow.size():
			var y := py + i
			if y < 0 or y >= rows.size():
				continue
			var r: String = rows[y]
			var add: String = prow[i]
			rows[y] = r.substr(0, px) + add + r.substr(px + add.length())
	return rows


func _prop_solid_default(t: String) -> bool:
	return t in ["lamp", "lantern_post", "tree", "barrel", "crate", "stall", "bench", "sign", "bell",
		"bell_shrine", "valve", "machine", "brazier", "furnace", "table", "bed", "gear"]


func _spawn_npcs() -> void:
	for n: Dictionary in map_data.get("npcs", []):
		if not GameState.check(n.get("cond", "")):
			continue
		var a := FieldActor.new()
		var nid: String = n.id
		a.setup(nid, str(n.get("sprite", "townsman")))
		a.data = n
		actors_root.add_child(a)
		var p := Vector2i(int(n.at[0]), int(n.at[1]))
		a.place(p, grid.stand_height(p.x, p.y))
		a.face(FieldActor.facing_from_name(str(n.get("face", "down"))))
		a.set_meta("home", p)
		npcs[nid] = a
		occupied[p] = nid


func refresh_npcs() -> void:
	# Re-evaluate NPC visibility conditions after flags change (events).
	for n: Dictionary in map_data.get("npcs", []):
		var nid: String = n.id
		var want := GameState.check(n.get("cond", ""))
		if want and not npcs.has(nid):
			var a := FieldActor.new()
			a.setup(nid, str(n.get("sprite", "townsman")))
			a.data = n
			actors_root.add_child(a)
			var p := Vector2i(int(n.at[0]), int(n.at[1]))
			a.place(p, grid.stand_height(p.x, p.y))
			a.face(FieldActor.facing_from_name(str(n.get("face", "down"))))
			a.set_meta("home", p)
			npcs[nid] = a
			occupied[p] = nid
		elif not want and npcs.has(nid):
			remove_npc(nid)


func remove_npc(nid: String) -> void:
	if not npcs.has(nid):
		return
	var a: FieldActor = npcs[nid]
	occupied.erase(a.grid_pos)
	a.queue_free()
	npcs.erase(nid)


func _compute_safe_tiles() -> void:
	var marks: Array = []
	for t: Dictionary in map_data.get("triggers", []):
		marks.append(Vector2i(int(t.at[0]), int(t.at[1])))
	for s: Variant in map_data.get("spawns", {}).values():
		marks.append(Vector2i(int(s[0]), int(s[1])))
	for n: Dictionary in map_data.get("npcs", []):
		marks.append(Vector2i(int(n.at[0]), int(n.at[1])))
	for m: Vector2i in marks:
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if grid.inside(m.x + dx, m.y + dy):
					grid.safe[grid.idx(m.x + dx, m.y + dy)] = 1


func on_map_entered() -> void:
	# Autosave only on maps marked safe and once a real game has begun.
	if map_data.get("autosave", false):
		Saves.autosave()
	for t: Dictionary in map_data.get("auto_events", []):
		var eid: String = t.event
		if GameState.check(t.get("cond", "")) and not (t.get("once", true) and GameState.granted.has("event:" + eid)):
			if t.get("once", true):
				GameState.granted["event:" + eid] = true
			await run_event(eid)
			break


# ------------------------------------------------------------------ camera

func _snap_camera() -> void:
	var dist := float(map_data.get("camera_dist", 14.0))
	var pitch := deg_to_rad(FieldActor.CAMERA_PITCH_DEG)
	camera.position = cam_target + Vector3(0, sin(pitch) * dist + 0.6, cos(pitch) * dist)


func _update_camera(delta: float) -> void:
	if player == null:
		return
	var goal := player.position
	var bounds: Array = map_data.get("camera_bounds", [])
	if bounds.size() == 4:
		goal.x = clampf(goal.x, float(bounds[0]), float(bounds[2]))
		goal.z = clampf(goal.z, float(bounds[1]), float(bounds[3]))
	elif grid:
		# Keep the view over the map instead of the void beyond its edges.
		var half_w := 7.5 * float(map_data.get("camera_dist", 14.0)) / 14.0
		var w := float(grid.w)
		goal.x = w * 0.5 if w <= half_w * 2.0 else clampf(goal.x, half_w, w - half_w)
		var h := float(grid.h)
		goal.z = clampf(goal.z, minf(3.5, h * 0.5), maxf(h - 2.5, h * 0.5))
	var k := 1.0 - exp(-delta * 6.0)
	cam_target = cam_target.lerp(goal, k)
	_snap_camera()


# ------------------------------------------------------------------ input & movement

func can_control() -> bool:
	return _active and not menu_open and not events.running and not Router.busy \
		and Time.get_ticks_msec() > _input_block_until and not dialogue.is_open()


func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	_update_camera(delta)
	if player == null:
		return
	_wander(delta)
	_update_prompt()
	if not can_control() or player.moving:
		return
	var v := InputHub.move_vector()
	if v.length() < 0.4:
		return
	var d := Vector2i.ZERO
	if absf(v.x) > absf(v.y):
		d.x = 1 if v.x > 0 else -1
	else:
		d.y = 1 if v.y > 0 else -1
	try_move(d)


func try_move(d: Vector2i) -> void:
	var target := player.grid_pos + d
	player.face(FieldActor.dir_to_facing(d))
	if not grid.can_step(player.grid_pos, target) or occupied.has(target):
		return
	var running := Input.is_action_pressed("cancel")
	player.step_to(target, grid.stand_height(target.x, target.y), RUN_SPEED if running else WALK_SPEED)
	GameState.map_pos = target
	GameState.map_facing = player.facing
	GameState.steps += 1
	await player.arrived
	if (GameState.steps % 2) == 0:
		Audio.sfx("step", 0.9 + 0.2 * encounter_rng.randf())
	_on_step(target)


func _on_step(p: Vector2i) -> void:
	for t: Dictionary in map_data.get("triggers", []):
		if str(t.get("on", "step")) != "step":
			continue
		if not _trigger_covers(t, p) or not GameState.check(t.get("cond", "")):
			continue
		match str(t.get("kind", "event")):
			"exit":
				var f := int(FieldActor.facing_from_name(str(t.face))) if t.has("face") else -1
				Router.enter_world(str(t.to), str(t.get("spawn", "")), Vector2i(-1, -1), f)
				Audio.sfx("door")
				return
			"event":
				var eid: String = t.event
				if t.get("once", false):
					if GameState.granted.has("event:" + eid):
						continue
					GameState.granted["event:" + eid] = true
				await run_event(eid)
				return
	_check_encounter(p)


func _trigger_covers(t: Dictionary, p: Vector2i) -> bool:
	var x := int(t.at[0])
	var y := int(t.at[1])
	var w := int(t.get("w", 1))
	var h := int(t.get("h", 1))
	return p.x >= x and p.x < x + w and p.y >= y and p.y < y + h


func _check_encounter(p: Vector2i) -> void:
	var enc: Dictionary = map_data.get("encounters", {})
	if enc.is_empty() or GameState.has_flag("no_encounters") or grid.safe[grid.idx(p.x, p.y)] == 1:
		return
	if not GameState.check(enc.get("cond", "")):
		return
	steps_since_battle += 1
	var min_steps := int(enc.get("min_steps", 12))
	if steps_since_battle < min_steps:
		return
	var chance := minf(0.5, float(steps_since_battle - min_steps + 1) * 0.035 * float(enc.get("rate", 1.0)))
	for cid: String in GameState.party:
		if "p_trail_sense" in GameState.members[cid].passives:
			chance *= 0.75
			break
	if encounter_rng.randf() >= chance:
		return
	var options: Array = []
	var total := 0.0
	for e: Dictionary in enc.get("table", []):
		if GameState.check(e.get("cond", "")):
			options.append(e)
			total += float(e.get("w", 1))
	if options.is_empty():
		return
	var roll := encounter_rng.randf() * total
	var chosen: String = options[0].enc
	for e: Dictionary in options:
		roll -= float(e.get("w", 1))
		if roll <= 0.0:
			chosen = e.enc
			break
	steps_since_battle = 0
	await start_battle(chosen, {"can_escape": true})


func start_battle(enc_id: String, opts: Dictionary = {}) -> Dictionary:
	opts["snapshot"] = GameState.to_dict()
	var res: Dictionary = await Router.run_battle(enc_id, opts)
	steps_since_battle = -6   # grace period after any battle
	hud.refresh()
	return res


func _unhandled_input(event: InputEvent) -> void:
	if not can_control():
		return
	if event.is_action_pressed("confirm") and not player.moving:
		get_viewport().set_input_as_handled()
		interact()
	elif event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		open_menu("")
	elif event.is_action_pressed("journal"):
		get_viewport().set_input_as_handled()
		open_menu("journal")
	elif event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		open_menu("pause")
	elif event.is_action_pressed("context"):
		get_viewport().set_input_as_handled()
		party_talk()


func open_menu(tab: String) -> void:
	if menu_open:
		return
	menu_open = true
	InputHub.release_all()
	var m: Control = preload("res://scripts/ui/main_menu.gd").new()
	m.world = self
	m.start_tab = tab
	menu_layer.add_child(m)
	await m.closed
	menu_open = false
	_input_block_until = Time.get_ticks_msec() + 150
	hud.refresh()


## Returns a description of what the player would interact with, for prompts.
func _interaction_target() -> Dictionary:
	var f := player.grid_pos + FieldActor.facing_vec(player.facing)
	for step in 2:
		var p := f + FieldActor.facing_vec(player.facing) * step
		var occ: String = occupied.get(p, "")
		if occ != "" and occ != "solid":
			if occ.begins_with("chest:"):
				var opened := GameState.granted.has(occ)
				return {"kind": "chest", "pos": p, "label": "Open" if not opened else "Look"}
			return {"kind": "npc", "id": occ, "pos": p, "label": "Talk"}
		for t: Dictionary in map_data.get("triggers", []):
			if str(t.get("on", "step")) == "interact" and _trigger_covers(t, p) and GameState.check(t.get("cond", "")):
				return {"kind": "trigger", "t": t, "label": str(t.get("label", "Check"))}
		# Look across counters only.
		if step == 0 and not bool(grid.info(p.x, p.y).get("counter", false)):
			break
	return {}


func _update_prompt() -> void:
	var tgt := _interaction_target() if can_control() else {}
	var key := str(tgt.get("label", "")) + str(tgt.get("pos", "")) + InputHub.active_device
	if key != _last_prompt_key:
		_last_prompt_key = key
		hud.set_prompt(str(tgt.get("label", "")))


func interact() -> void:
	var tgt := _interaction_target()
	match str(tgt.get("kind", "")):
		"npc":
			var a: FieldActor = npcs[tgt.id]
			a.face_toward(player.grid_pos)
			var talk: Variant = a.data.get("talk", "")
			if talk is Array:
				# Conditional talk list: first entry whose condition passes.
				for entry: Dictionary in talk:
					if GameState.check(entry.get("cond", "")):
						await run_event(str(entry.event))
						break
			elif str(talk) != "":
				await run_event(str(talk))
			a.face(FieldActor.facing_from_name(str(a.data.get("face", "down"))))
		"chest":
			await open_chest(tgt.pos)
		"trigger":
			var t: Dictionary = tgt.t
			if str(t.get("kind", "event")) == "exit":
				Audio.sfx("door")
				Router.enter_world(str(t.to), str(t.get("spawn", "")))
				return
			var eid: String = t.event
			if t.get("once", false):
				if GameState.granted.has("event:" + eid):
					return
				GameState.granted["event:" + eid] = true
			await run_event(eid)


func open_chest(p: Vector2i) -> void:
	var ch: Dictionary = chests[p]
	var key := "chest:" + str(ch.id)
	if GameState.granted.has(key):
		await dialogue.say_simple("", "The chest is empty.")
		return
	var rewards := {"items": ch.get("items", {}), "gold": int(ch.get("gold", 0))}
	if GameState.grant_once(key, rewards):
		Audio.sfx("chest")
		var parts: PackedStringArray = []
		for iid: String in rewards.items.keys():
			parts.append("%s x%d" % [Content.item(iid).get("name", iid), int(rewards.items[iid])])
		if rewards.gold > 0:
			parts.append("%d crowns" % rewards.gold)
		# Rebuild to show it opened.
		load_map_keep_player()
		await dialogue.say_simple("", "Found " + ", ".join(parts) + ".")


func load_map_keep_player() -> void:
	var pos := player.grid_pos
	var f := player.facing
	load_map(map_id, "", pos, f)


func run_event(eid: String) -> void:
	if not Content.has_event(eid):
		push_warning("Missing event " + eid)
		return
	hud.set_prompt("")
	await events.run(eid)
	refresh_npcs()
	hud.refresh()
	_input_block_until = Time.get_ticks_msec() + 200


func party_talk() -> void:
	# Context action: a party member comments on the current place.
	for entry: Dictionary in map_data.get("party_talk", []):
		if GameState.check(entry.get("cond", "")):
			await run_event(str(entry.event))
			return
	await dialogue.say_simple(Content.character(GameState.lead()).get("name", ""), "Nothing to add right now.")


# ------------------------------------------------------------------ NPC idle movement

func _wander(delta: float) -> void:
	_wander_t += delta
	if _wander_t < 0.6:
		return
	_wander_t = 0.0
	if events.running or dialogue.is_open():
		return
	for nid: String in npcs.keys():
		var a: FieldActor = npcs[nid]
		var radius := int(a.data.get("wander", 0))
		if radius <= 0 or a.moving or encounter_rng.randf() > 0.25:
			continue
		var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		var d: Vector2i = dirs[encounter_rng.randi() % 4]
		var tgt := a.grid_pos + d
		var home: Vector2i = a.get_meta("home")
		if absi(tgt.x - home.x) > radius or absi(tgt.y - home.y) > radius:
			continue
		if not grid.can_step(a.grid_pos, tgt) or occupied.has(tgt) or tgt == player.grid_pos:
			continue
		occupied.erase(a.grid_pos)
		occupied[tgt] = nid
		a.step_to(tgt, grid.stand_height(tgt.x, tgt.y), 2.5)


## Used by events: move an actor along tile path.
func move_actor(a: FieldActor, path: Array, speed: float = 3.5) -> void:
	for step: Variant in path:
		var tgt := Vector2i(int(step[0]), int(step[1]))
		if a != player:
			occupied.erase(a.grid_pos)
		a.step_to(tgt, grid.stand_height(tgt.x, tgt.y), speed)
		await a.arrived
		if a != player:
			occupied[tgt] = a.actor_id
	if a == player:
		GameState.map_pos = player.grid_pos


func actor(id: String) -> FieldActor:
	if id == "player" or id == "rowan_field":
		return player
	return npcs.get(id)
