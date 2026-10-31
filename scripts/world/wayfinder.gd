class_name Wayfinder
extends Node3D
## In-world navigation aids for the field: a floating name sign and floor
## arrows at every exit, and a bobbing beacon over the tracked objective (or
## over the exit that leads toward it when the objective is on another map).

const C_EXIT := Color(0.92, 0.94, 1.0)
const C_GOAL := Color(1.0, 0.80, 0.30)

var world: Node3D
var target: Dictionary = {}          # Nav.resolve() result for the current map
var _exit_nodes: Array = []          # [{exit, label, arrows}]
var _beacon: Node3D
var _beam: MeshInstance3D
var _t: float = 0.0
static var _arrow_mesh: ArrayMesh
static var _gem_mesh: ArrayMesh


func setup(w: Node3D) -> void:
	world = w
	GameState.quest_updated.connect(func(_q: String) -> void: refresh())
	GameState.flags_changed.connect(refresh)
	Settings.changed.connect(func(k: String) -> void:
		if k == "quest_markers":
			refresh())


## Rebuild exit signs for the freshly loaded map, then resolve the objective.
func rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_exit_nodes.clear()
	_beacon = null
	_beam = null
	var grid: MapGrid = world.grid
	if grid == null or str(world.map_id).begins_with("arena_"):
		return
	for e: Dictionary in Nav.exits(world.map_id):
		_exit_nodes.append(_make_exit(e, grid))
	_beacon = Node3D.new()
	add_child(_beacon)
	var gem := MeshInstance3D.new()
	gem.mesh = _gem()
	gem.material_override = _unshaded(C_GOAL, 1.0)
	gem.scale = Vector3(0.22, 0.30, 0.22)
	_beacon.add_child(gem)
	_beam = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.18
	cyl.bottom_radius = 0.34
	cyl.height = 3.2
	cyl.radial_segments = 10
	cyl.rings = 1
	_beam.mesh = cyl
	var bm := _unshaded(Color(C_GOAL.r, C_GOAL.g, C_GOAL.b, 0.16), 0.16)
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam.material_override = bm
	add_child(_beam)
	refresh()


func _make_exit(e: Dictionary, grid: MapGrid) -> Dictionary:
	if str(e.get("npc", "")) != "":
		# Passage offered by a person (e.g. a ferryman): routed to, not signposted.
		return {"exit": e, "label": null, "arrows": []}
	var at: Vector2i = e.at
	var w := int(e.w)
	var h := int(e.h)
	var center := Vector2(at.x + w * 0.5, at.y + h * 0.5)
	var out_dir := Vector2i.ZERO
	if at.x == 0:
		out_dir = Vector2i(-1, 0)
	elif at.x + w >= grid.w:
		out_dir = Vector2i(1, 0)
	elif at.y == 0:
		out_dir = Vector2i(0, -1)
	elif at.y + h >= grid.h:
		out_dir = Vector2i(0, 1)
	var floor_y := grid.stand_height(clampi(int(center.x), 0, grid.w - 1), clampi(int(center.y), 0, grid.h - 1))
	if bool(e.get("door", false)):
		# Doors sit in a wall; use the standing tile in front of them.
		var below := Vector2i(at.x, at.y + 1)
		if grid.inside(below.x, below.y):
			floor_y = grid.stand_height(below.x, below.y)
	var label := Label3D.new()
	var nm := Nav.map_name(str(e.to))
	label.text = "< " + nm if out_dir.x < 0 else (nm + " >" if out_dir.x > 0 else nm)
	label.font = UITheme.bold()
	label.font_size = 40
	label.outline_size = 12
	label.outline_modulate = Color(0.05, 0.03, 0.08, 0.9)
	label.pixel_size = 0.0065
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 2
	label.modulate = C_EXIT
	var lift := 2.3 if bool(e.get("door", false)) else 1.5
	var lp := Vector3(center.x, floor_y + lift, center.y)
	# Near the left/right border, grow the sign inward so it stays on screen.
	var text_w := label.font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x
	if lp.x < 4.0:
		label.offset.x = text_w * 0.5
		lp.x = maxf(at.x, 2.8)
	elif lp.x > grid.w - 4.0:
		label.offset.x = -text_w * 0.5
		lp.x = minf(at.x + w, grid.w - 2.8)
	lp.z = clampf(lp.z, 0.8, grid.h - 0.4)
	label.position = lp
	add_child(label)
	var arrows: Array = []
	if out_dir != Vector2i.ZERO:
		for yy in h:
			for xx in w:
				var tile := Vector2i(at.x + xx, at.y + yy)
				if not grid.is_walkable(tile.x, tile.y):
					continue
				var a := MeshInstance3D.new()
				a.mesh = _arrow()
				a.material_override = _unshaded(Color(C_EXIT.r, C_EXIT.g, C_EXIT.b, 0.55), 0.55)
				a.position = Vector3(tile.x + 0.5, grid.stand_height(tile.x, tile.y) + 0.04, tile.y + 0.5)
				a.rotation.y = atan2(-float(out_dir.y), float(out_dir.x))
				add_child(a)
				arrows.append(a)
	return {"exit": e, "label": label, "arrows": arrows}


## Re-resolve the objective and recolour exits (on quest/flag changes).
func refresh() -> void:
	if world == null or world.grid == null:
		return
	var on := bool(Settings.get_value("quest_markers"))
	target = Nav.resolve(GameState.tracked_quest, world.map_id) if on else {}
	var goal_exit: Dictionary = target.get("exit", {})
	for n: Dictionary in _exit_nodes:
		var e: Dictionary = n.exit
		var is_goal: bool = not goal_exit.is_empty() and e.at == goal_exit.at and str(e.to) == str(goal_exit.to)
		# Scripted passages (hatches, lifts) are only signposted when they are the way on.
		var open := GameState.check(e.cond) and (not bool(e.get("event", false)) or is_goal)
		var col := C_GOAL if is_goal else C_EXIT
		if n.label == null:
			continue
		(n.label as Label3D).visible = open
		(n.label as Label3D).modulate = col
		for a: MeshInstance3D in n.arrows:
			a.visible = open
			(a.material_override as StandardMaterial3D).albedo_color = Color(col.r, col.g, col.b, 0.6 if is_goal else 0.4)


## World position of the objective marker on this map, or null.
func goal_position() -> Variant:
	if target.is_empty() or world == null or world.grid == null:
		return null
	var grid: MapGrid = world.grid
	if bool(target.here):
		var npc := str(target.npc)
		if npc != "" and world.npcs.has(npc):
			return (world.npcs[npc] as Node3D).position + Vector3(0, 2.15, 0)
		if target.at == null:
			return null
		var p: Vector2i = target.at
		var fy := grid.stand_height(clampi(p.x, 0, grid.w - 1), clampi(p.y, 0, grid.h - 1))
		return Vector3(p.x + 0.5, fy + 1.9, p.y + 0.5)
	var e: Dictionary = target.exit
	if e.is_empty():
		return null
	var enpc := str(e.get("npc", ""))
	if enpc != "" and world.npcs.has(enpc):
		return (world.npcs[enpc] as Node3D).position + Vector3(0, 2.15, 0)
	var gt: Variant = goal_tile()
	if gt == null:
		return null
	var t: Vector2i = gt
	var fy := grid.stand_height(clampi(t.x, 0, grid.w - 1), clampi(t.y, 0, grid.h - 1))
	if bool(e.get("door", false)) and grid.inside(t.x, t.y + 1):
		fy = grid.stand_height(t.x, t.y + 1)
	return Vector3(t.x + 0.5, fy + 2.0, t.y + 0.5)


## Tile the objective points at (for the minimap): objective tile/NPC, or the
## nearest tile of the exit to take.
func goal_tile() -> Variant:
	if target.is_empty() or world == null:
		return null
	if bool(target.here):
		var npc := str(target.npc)
		if npc != "" and world.npcs.has(npc):
			return (world.npcs[npc] as FieldActor).grid_pos
		return target.at
	var e: Dictionary = target.exit
	if e.is_empty():
		return null
	var pp: Vector2i = world.player.grid_pos if world.player else Vector2i.ZERO
	var at: Vector2i = e.at
	return Vector2i(clampi(pp.x, at.x, at.x + int(e.w) - 1), clampi(pp.y, at.y, at.y + int(e.h) - 1))


func _process(delta: float) -> void:
	_t += delta
	if _beacon == null:
		return
	var gp: Variant = goal_position()
	_beacon.visible = gp != null
	_beam.visible = gp != null and bool(target.get("here", false)) and str(target.get("npc", "")) == ""
	if gp == null:
		return
	var bob := 0.0 if bool(Settings.get_value("reduce_motion")) else sin(_t * 3.0) * 0.08
	_beacon.position = (gp as Vector3) + Vector3(0, bob, 0)
	_beacon.rotation.y = _t * 1.6
	if _beam.visible:
		_beam.position = (gp as Vector3) + Vector3(0, -0.3, 0)
	for n: Dictionary in _exit_nodes:
		for a: MeshInstance3D in n.arrows:
			var k := 1.0 + 0.08 * sin(_t * 4.0 + a.position.x + a.position.z)
			a.scale = Vector3(k, 1.0, k)


static func _unshaded(c: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


## Flat arrow head lying on the floor, pointing along +X.
static func _arrow() -> ArrayMesh:
	if _arrow_mesh:
		return _arrow_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tip := Vector3(0.30, 0, 0)
	var a := Vector3(-0.18, 0, -0.28)
	var notch := Vector3(-0.04, 0, 0)
	var b := Vector3(-0.18, 0, 0.28)
	for v: Vector3 in [tip, notch, a, tip, b, notch]:
		st.set_normal(Vector3.UP)
		st.add_vertex(v)
	_arrow_mesh = st.commit()
	return _arrow_mesh


## Octahedron "gem" marker.
static func _gem() -> ArrayMesh:
	if _gem_mesh:
		return _gem_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(0, 1, 0)
	var bot := Vector3(0, -1, 0)
	var ring := [Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, 0, -1)]
	for i in 4:
		var p: Vector3 = ring[i]
		var q: Vector3 = ring[(i + 1) % 4]
		for tri: Array in [[top, q, p], [bot, p, q]]:
			for v: Vector3 in tri:
				st.add_vertex(v)
	st.generate_normals()
	_gem_mesh = st.commit()
	return _gem_mesh
