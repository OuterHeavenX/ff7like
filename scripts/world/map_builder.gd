class_name MapBuilder
extends RefCounted
## Builds a field map from JSON into a few batched meshes:
##  * terrain/props (tile atlas, vertex-colored with baked lamp light + AO)
##  * water (animated pixel shader)
##  * glow (unshaded emissive bits: windows, lanterns)
##  * halos (additive billboards, one MultiMesh)
## plus lightweight CPU particles for smoke/dust/rain. Compatible renderer only.

const TILE_PX := 24.0
const ATLAS_TILES := 8
const SIDE_SHADE := {"n": 0.62, "s": 0.86, "e": 0.74, "w": 0.70}

static var _atlas: Texture2D
static var _tile_index: Dictionary = {}
static var _fx: Texture2D
static var _water_shader: Shader
static var _sway_shader: Shader

var grid: MapGrid
var map: Dictionary
var lights: Array = []        # [{pos: Vector3, color: Color, radius: float}]
var ambient: Color = Color(1, 1, 1)
var st: SurfaceTool
var st_water: SurfaceTool
var st_glow: SurfaceTool
var st_sway: SurfaceTool
var halos: Array = []         # [{pos, color, size}]
var root: Node3D
var interact_points: Array = []  # props that mark interactables (doors etc.)
var low_preset: bool = false


static func load_shared() -> void:
	if _atlas == null:
		_atlas = load("res://assets/textures/tiles.png")
		_fx = load("res://assets/textures/fx.png")
		var txt := FileAccess.get_file_as_string("res://assets/textures/tiles.json")
		_tile_index = JSON.parse_string(txt)
		_water_shader = load("res://scenes/world/water.gdshader")
		_sway_shader = load("res://scenes/world/sway.gdshader")


static func fx_texture() -> Texture2D:
	load_shared()
	return _fx


func build(map_data: Dictionary) -> Node3D:
	load_shared()
	map = map_data
	low_preset = str(Settings.get_value("visual_preset")) == "low"
	grid = parse_grid(map_data)
	var amb: Array = map.get("ambient", [1.0, 1.0, 1.0])
	ambient = Color(amb[0], amb[1], amb[2])
	root = Node3D.new()
	root.name = "MapGeometry"
	_collect_lights()
	st = _new_st()
	st_water = _new_st()
	st_glow = _new_st()
	st_sway = _new_st()
	_build_terrain()
	for p: Dictionary in map.get("props", []):
		_build_prop(p)
	_add_mesh(st, _terrain_material(), "Terrain")
	_add_mesh(st_water, _water_material(), "Water")
	_add_mesh(st_glow, _glow_material(), "Glow")
	_add_mesh(st_sway, _sway_material(), "Sway")
	_build_halos()
	_build_particles()
	return root


func _new_st() -> SurfaceTool:
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_TRIANGLES)
	return s


func _add_mesh(s: SurfaceTool, mat: Material, mesh_name: String) -> void:
	var arr := s.commit()
	if arr == null or arr.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	mi.mesh = arr
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


# ------------------------------------------------------------------ parsing

static func parse_grid(m: Dictionary) -> MapGrid:
	var g := MapGrid.new()
	var rows: Array = m.get("rows", [])
	var hrows: Array = m.get("heights", [])
	g.h = rows.size()
	g.w = 0
	for r: String in rows:
		g.w = maxi(g.w, r.length())
	var legend: Dictionary = Content.legend().duplicate(true)
	var over: Dictionary = m.get("legend", {})
	for k: String in over.keys():
		legend[k] = over[k]
	g.legend = legend
	var n := g.w * g.h
	g.chars.resize(n)
	g.level.resize(n)
	g.block.resize(n)
	g.walk.resize(n)
	g.stair.resize(n)
	g.water.resize(n)
	g.safe.resize(n)
	for y in g.h:
		var row: String = rows[y]
		var hrow: String = hrows[y] if y < hrows.size() else ""
		for x in g.w:
			var c := row[x] if x < row.length() else " "
			var i := g.idx(x, y)
			g.chars[i] = c
			var inf: Dictionary = legend.get(c, {})
			var lv := 0
			if x < hrow.length() and hrow[x] >= "0" and hrow[x] <= "9":
				lv = int(hrow[x])
			lv += int(inf.get("level", 0))
			g.level[i] = lv
			g.block[i] = int(inf.get("block", 0))
			g.walk[i] = 1 if bool(inf.get("walk", false)) else 0
			g.stair[i] = str(inf.get("stair", ""))
			g.water[i] = 1 if bool(inf.get("water", false)) else 0
			g.safe[i] = 0
	return g


func _collect_lights() -> void:
	for l: Dictionary in map.get("lights", []):
		var at: Array = l.at
		var c: Array = l.get("color", [1.0, 0.75, 0.4])
		lights.append({"pos": _tile_center(int(at[0]), int(at[1]), float(l.get("y", 1.2))),
			"color": Color(c[0], c[1], c[2]), "radius": float(l.get("radius", 4.0))})
	for p: Dictionary in map.get("props", []):
		var t: String = p.get("t", "")
		if p.has("lit_flag") and not GameState.has_flag(str(p.lit_flag)):
			continue
		if t in ["lamp", "lantern_post", "brazier", "window_glow", "crystal", "bell_shrine", "campfire", "furnace"]:
			var at2: Array = p.at
			var col := {"crystal": Color(0.55, 0.75, 1.0), "bell_shrine": Color(0.6, 0.95, 1.0),
				"furnace": Color(1.0, 0.5, 0.25)}.get(t, Color(1.0, 0.72, 0.38)) as Color
			if p.has("color"):
				col = Color(p.color[0], p.color[1], p.color[2])
			var rad := float(p.get("radius", {"window_glow": 2.2, "crystal": 3.0}.get(t, 4.2)))
			lights.append({"pos": _tile_center(int(at2[0]), int(at2[1]), 1.6), "color": col, "radius": rad})


func _tile_center(x: int, y: int, above: float = 0.0) -> Vector3:
	var lv := grid.floor_level(x, y) if grid.inside(x, y) else 0
	return Vector3(x + 0.5, lv * MapGrid.LEVEL + above, y + 0.5)


## Light reaching a point (ambient + lamps); used to tint 3D characters.
func light_at(p: Vector3) -> Color:
	return _light_at(p, 1.0)


## Baked lighting: ambient + lamp falloff, times face shading.
func _light_at(p: Vector3, face: float) -> Color:
	var c := ambient
	for l: Dictionary in lights:
		var d: float = p.distance_to(l.pos)
		var r: float = l.radius
		if d < r:
			var k := 1.0 - d / r
			c += (l.color as Color) * (k * k) * 0.95
	c = Color(minf(c.r, 1.25), minf(c.g, 1.25), minf(c.b, 1.25))
	return Color(minf(c.r * face, 1.0), minf(c.g * face, 1.0), minf(c.b * face, 1.0))


# ------------------------------------------------------------------ quads

func _uv_rect(tex: String) -> Rect2:
	var i := int(_tile_index.get(tex, 0))
	var inset := 0.25 / (TILE_PX * ATLAS_TILES)
	var s := 1.0 / ATLAS_TILES
	return Rect2((i % ATLAS_TILES) * s + inset, (i / ATLAS_TILES) * s + inset, s - inset * 2, s - inset * 2)


## Emits a quad a-b-c-d (counter-clockwise when seen from the front).
func _quad(s: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, uv: Rect2, face: float,
		tint: Color = Color(1, 1, 1), lit: bool = true, v_frac: float = 1.0, ao: Array = []) -> void:
	var uvs := [Vector2(uv.position.x, uv.position.y + uv.size.y * (1.0 - v_frac)),
		Vector2(uv.end.x, uv.position.y + uv.size.y * (1.0 - v_frac)),
		Vector2(uv.end.x, uv.end.y), Vector2(uv.position.x, uv.end.y)]
	var pts := [a, b, c, d]
	var cols: Array = []
	for i in 4:
		var col := _light_at(pts[i], face) if lit else Color(face, face, face)
		if not ao.is_empty():
			col = col * Color(ao[i], ao[i], ao[i])
		cols.append(Color(col.r * tint.r, col.g * tint.g, col.b * tint.b, 1.0))
	for tri: Array in [[0, 1, 2], [0, 2, 3]]:
		for k: int in tri:
			s.set_color(cols[k])
			s.set_uv(uvs[k])
			s.add_vertex(pts[k])


## Axis-aligned box made of atlas-textured faces. Bottom face omitted.
func _box(s: SurfaceTool, mn: Vector3, mx: Vector3, top_tex: String, side_tex: String,
		tint: Color = Color(1, 1, 1), lit: bool = true) -> void:
	var tuv := _uv_rect(top_tex)
	var suv := _uv_rect(side_tex)
	_quad(s, Vector3(mn.x, mx.y, mn.z), Vector3(mx.x, mx.y, mn.z), Vector3(mx.x, mx.y, mx.z), Vector3(mn.x, mx.y, mx.z), tuv, 1.0, tint, lit)
	var hgt := mx.y - mn.y
	var frac := clampf(hgt, 0.05, 1.0)
	# south (+z), north (-z), east (+x), west (-x)
	_quad(s, Vector3(mn.x, mx.y, mx.z), Vector3(mx.x, mx.y, mx.z), Vector3(mx.x, mn.y, mx.z), Vector3(mn.x, mn.y, mx.z), suv, SIDE_SHADE.s, tint, lit, frac)
	_quad(s, Vector3(mx.x, mx.y, mn.z), Vector3(mn.x, mx.y, mn.z), Vector3(mn.x, mn.y, mn.z), Vector3(mx.x, mn.y, mn.z), suv, SIDE_SHADE.n, tint, lit, frac)
	_quad(s, Vector3(mx.x, mx.y, mx.z), Vector3(mx.x, mx.y, mn.z), Vector3(mx.x, mn.y, mn.z), Vector3(mx.x, mn.y, mx.z), suv, SIDE_SHADE.e, tint, lit, frac)
	_quad(s, Vector3(mn.x, mx.y, mn.z), Vector3(mn.x, mx.y, mx.z), Vector3(mn.x, mn.y, mx.z), Vector3(mn.x, mn.y, mn.z), suv, SIDE_SHADE.w, tint, lit, frac)


## Vertical wall face split into 1-unit texture segments to avoid stretching.
func _wall_face(s: SurfaceTool, x0: float, z0: float, x1: float, z1: float, y_lo: float, y_hi: float,
		tex: String, face: float, tint: Color) -> void:
	var y := y_hi
	var uv := _uv_rect(tex)
	while y > y_lo + 0.001:
		var seg := minf(1.0, y - y_lo)
		_quad(s, Vector3(x0, y, z0), Vector3(x1, y, z1), Vector3(x1, y - seg, z1), Vector3(x0, y - seg, z0), uv, face, tint, true, seg)
		y -= seg


# ------------------------------------------------------------------ terrain

func _tint_for(inf: Dictionary) -> Color:
	var t: Array = inf.get("tint", [1.0, 1.0, 1.0])
	return Color(t[0], t[1], t[2])


func _build_terrain() -> void:
	var L := MapGrid.LEVEL
	for y in grid.h:
		for x in grid.w:
			var c := grid.ch(x, y)
			if c == " ":
				continue
			var inf := grid.info(x, y)
			var tint := _tint_for(inf)
			var lv := grid.floor_level(x, y)
			var top := float(grid.top_level(x, y)) * L
			var floor_y := float(lv) * L
			var is_water := bool(inf.get("water", false))
			var top_tex: String = inf.get("top", inf.get("tex", "cobble"))
			var side_tex: String = inf.get("side", inf.get("tex", "cobble"))
			var sdir := grid.stair_dir(x, y)
			if is_water:
				var wy := floor_y - 0.28
				_quad(st_water, Vector3(x, wy, y), Vector3(x + 1, wy, y), Vector3(x + 1, wy, y + 1), Vector3(x, wy, y + 1), Rect2(0, 0, 1, 1), 1.0, Color(1, 1, 1))
				# canal bed walls are drawn by neighbours' side faces
				top = floor_y - 0.28
			elif sdir != "":
				_build_stair(x, y, sdir, floor_y, top_tex, side_tex, tint)
			else:
				_quad(st, Vector3(x, top, y), Vector3(x + 1, top, y), Vector3(x + 1, top, y + 1), Vector3(x, top, y + 1),
					_uv_rect(top_tex), 1.0, tint, true, 1.0, _ao(x, y, grid.top_level(x, y)))
				if inf.get("bridge", false):
					# rails
					_box(st, Vector3(x, top, y - 0.02), Vector3(x + 1, top + 0.32, y + 0.08), "planks", "planks", tint)
					_box(st, Vector3(x, top, y + 0.92), Vector3(x + 1, top + 0.32, y + 1.02), "planks", "planks", tint)
			# sides toward lower neighbours
			var my_top := top
			for nd: Array in [[0, 1, "s"], [0, -1, "n"], [1, 0, "e"], [-1, 0, "w"]]:
				var nx: int = x + nd[0]
				var ny: int = y + nd[1]
				var ninf := grid.info(nx, ny)
				var n_top := -2.0
				if grid.inside(nx, ny) and grid.ch(nx, ny) != " ":
					n_top = float(grid.top_level(nx, ny)) * L
					if bool(ninf.get("water", false)):
						n_top = float(grid.floor_level(nx, ny)) * L - 0.6
					if grid.stair_dir(nx, ny) != "":
						n_top = float(grid.floor_level(nx, ny)) * L
				if n_top >= my_top - 0.001:
					continue
				var face: float = SIDE_SHADE[nd[2]]
				var stex: String = side_tex
				var lo := n_top
				# Building blocks: the floor part below uses the floor texture.
				match nd[2]:
					"s": _wall_face(st, x, y + 1, x + 1, y + 1, lo, my_top, stex, face, tint)
					"n": _wall_face(st, x + 1, y, x, y, lo, my_top, stex, face, tint)
					"e": _wall_face(st, x + 1, y + 1, x + 1, y, lo, my_top, stex, face, tint)
					"w": _wall_face(st, x, y, x, y + 1, lo, my_top, stex, face, tint)
			# Lit windows on south faces of buildings.
			if inf.get("windows", false) and grid.block[grid.idx(x, y)] >= 3:
				var south_top := float(grid.top_level(x, y + 1)) * L
				if south_top < floor_y + 0.2 and (x * 7 + y * 3) % 3 != 0:
					var wy0 := floor_y + 0.55
					_glow_quad(Vector3(x + 0.3, wy0 + 0.5, y + 1.01), Vector3(x + 0.7, wy0 + 0.5, y + 1.01),
						Vector3(x + 0.7, wy0, y + 1.01), Vector3(x + 0.3, wy0, y + 1.01), Color(1.0, 0.78, 0.42))
					halos.append({"pos": Vector3(x + 0.5, wy0 + 0.25, y + 1.1), "color": Color(1.0, 0.7, 0.35, 0.35), "size": 1.1})
			if inf.get("roof", "") != "":
				_build_roof(x, y, top, str(inf.roof), tint)


## Ambient occlusion per vertex: darken corners next to taller neighbours.
func _ao(x: int, y: int, my_top: int) -> Array:
	var corners := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]
	var out: Array = []
	for c: Vector2i in corners:
		var occl := 0
		for dx in [-1, 0]:
			for dy in [-1, 0]:
				var tx: int = x + c.x + dx
				var ty: int = y + c.y + dy
				if tx == x and ty == y:
					continue
				if grid.inside(tx, ty) and grid.top_level(tx, ty) > my_top:
					occl += 1
		out.append(1.0 - 0.14 * occl)
	return out


func _build_stair(x: int, y: int, sdir: String, floor_y: float, top_tex: String, side_tex: String, tint: Color) -> void:
	var v := MapGrid.stair_vec(sdir)
	var hi_y := float(grid.floor_level(x + v.x, y + v.y)) * MapGrid.LEVEL
	var steps := 4
	for i in steps:
		var t0 := float(i) / steps
		var t1 := float(i + 1) / steps
		var hy := lerpf(floor_y, hi_y, t1)
		var mn := Vector3(x, floor_y - 0.01, y)
		var mx := Vector3(x + 1, hy, y + 1)
		match sdir:
			"^":
				mn.z = y + 1 - t1
				mx.z = y + 1 - t0
			"v":
				mn.z = y + t0
				mx.z = y + t1
			"<":
				mn.x = x + 1 - t1
				mx.x = x + 1 - t0
			">":
				mn.x = x + t0
				mx.x = x + t1
		_box(st, mn, mx, top_tex, side_tex, tint)


func _build_roof(x: int, y: int, top: float, kind: String, tint: Color) -> void:
	# Overhanging roof slab with eaves on exposed edges, ridge raised toward block centre.
	var tex := "roof_red" if kind == "red" else "roof_slate"
	var e := 0.12
	var mn := Vector3(x - (e if grid.info(x - 1, y).get("roof", "") == "" else 0.0), top, y - (e if grid.info(x, y - 1).get("roof", "") == "" else 0.0))
	var mx := Vector3(x + 1 + (e if grid.info(x + 1, y).get("roof", "") == "" else 0.0), top + 0.18, y + 1 + (e if grid.info(x, y + 1).get("roof", "") == "" else 0.0))
	var inner := 0
	for d: Vector2i in [Vector2i(0, 1), Vector2i(0, -1)]:
		if grid.info(x + d.x, y + d.y).get("roof", "") != "":
			inner += 1
	mx.y += 0.22 * inner
	_box(st, mn, mx, tex, tex, tint)


# ------------------------------------------------------------------ props

func _glow_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	_quad(st_glow, a, b, c, d, _uv_rect("window"), 1.0, col, false)


func _cyl(s: SurfaceTool, center: Vector3, r_bot: float, r_top: float, hgt: float, sides: int, tex: String, tint: Color) -> void:
	var uv := _uv_rect(tex)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := center + Vector3(cos(a0) * r_bot, 0, sin(a0) * r_bot)
		var p1 := center + Vector3(cos(a1) * r_bot, 0, sin(a1) * r_bot)
		var q0 := center + Vector3(cos(a0) * r_top, hgt, sin(a0) * r_top)
		var q1 := center + Vector3(cos(a1) * r_top, hgt, sin(a1) * r_top)
		var nz := sin((a0 + a1) * 0.5)
		var nx := cos((a0 + a1) * 0.5)
		var face := 0.66 + 0.2 * nz + 0.06 * nx
		_quad(s, q1, q0, p0, p1, uv, face, tint)
	var top_c := center + Vector3(0, hgt, 0)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var q0 := center + Vector3(cos(a0) * r_top, hgt, sin(a0) * r_top)
		var q1 := center + Vector3(cos(a1) * r_top, hgt, sin(a1) * r_top)
		_quad(s, top_c, q1, q0, q0, uv, 1.0, tint)


func _build_prop(p: Dictionary) -> void:
	var t: String = p.get("t", "")
	var at: Array = p.get("at", [0, 0])
	var x := int(at[0])
	var y := int(at[1])
	var base := _tile_center(x, y)
	var by := base.y
	var tint := Color(1, 1, 1)
	if p.has("tint"):
		tint = Color(p.tint[0], p.tint[1], p.tint[2])
	match t:
		"lamp", "lantern_post":
			_box(st, Vector3(x + 0.44, by, y + 0.44), Vector3(x + 0.56, by + 1.5, y + 0.56), "pipe", "pipe", Color(0.35, 0.33, 0.38))
			_box(st, Vector3(x + 0.36, by + 1.5, y + 0.36), Vector3(x + 0.64, by + 1.58, y + 0.64), "brass", "brass", Color(0.5, 0.45, 0.4))
			var dark := p.has("lit_flag") and not GameState.has_flag(str(p.lit_flag))
			if dark:
				_box(st, Vector3(x + 0.38, by + 1.58, y + 0.38), Vector3(x + 0.62, by + 1.86, y + 0.62), "glass", "glass", Color(0.35, 0.4, 0.5))
			else:
				_glow_box(Vector3(x + 0.38, by + 1.58, y + 0.38), Vector3(x + 0.62, by + 1.86, y + 0.62), Color(1.0, 0.82, 0.48))
			_box(st, Vector3(x + 0.34, by + 1.86, y + 0.34), Vector3(x + 0.66, by + 1.94, y + 0.66), "brass", "brass", Color(0.5, 0.45, 0.4))
			if not dark:
				halos.append({"pos": Vector3(x + 0.5, by + 1.72, y + 0.5), "color": Color(1.0, 0.72, 0.36, 0.55), "size": 1.8})
		"tree":
			_box(st, Vector3(x + 0.4, by, y + 0.4), Vector3(x + 0.6, by + 0.9, y + 0.6), "planks", "planks", Color(0.6, 0.45, 0.35))
			var leaf := Color(0.55, 0.85, 0.5) * tint
			_box(st, Vector3(x + 0.05, by + 0.8, y + 0.05), Vector3(x + 0.95, by + 1.5, y + 0.95), "hedge", "hedge", leaf)
			_box(st, Vector3(x + 0.18, by + 1.5, y + 0.18), Vector3(x + 0.82, by + 2.0, y + 0.82), "hedge", "hedge", leaf * 1.08)
			_box(st, Vector3(x + 0.32, by + 2.0, y + 0.32), Vector3(x + 0.68, by + 2.3, y + 0.68), "hedge", "hedge", leaf * 1.15)
		"barrel":
			_cyl(st, Vector3(x + 0.5, by, y + 0.5), 0.3, 0.3, 0.7, 8, "planks", Color(0.9, 0.8, 0.7))
		"crate":
			var s2 := float(p.get("size", 0.7))
			_box(st, Vector3(x + 0.5 - s2 / 2, by, y + 0.5 - s2 / 2), Vector3(x + 0.5 + s2 / 2, by + s2, y + 0.5 + s2 / 2), "planks", "planks", Color(1.0, 0.85, 0.7))
		"stall":
			var cc: Array = p.get("color", [0.8, 0.25, 0.25])
			var canopy := Color(cc[0], cc[1], cc[2])
			for cx2: float in [0.08, 1.82]:
				_box(st, Vector3(x + cx2, by, y + 0.1), Vector3(x + cx2 + 0.1, by + 1.4, y + 0.2), "planks", "planks")
			_box(st, Vector3(x, by, y + 0.15), Vector3(x + 2, by + 0.7, y + 0.8), "planks", "planks", Color(0.9, 0.75, 0.6))
			_box(st, Vector3(x - 0.1, by + 1.4, y - 0.1), Vector3(x + 2.1, by + 1.5, y + 0.95), "plaster", "plaster", canopy)
			for k in 4:
				_box(st, Vector3(x + 0.2 + k * 0.45, by + 0.7, y + 0.35), Vector3(x + 0.45 + k * 0.45, by + 0.86, y + 0.6), "plaster", "plaster", [Color(1, 0.6, 0.3), Color(0.9, 0.9, 0.4), Color(0.5, 0.8, 0.4), Color(0.9, 0.4, 0.5)][k])
		"bench":
			_box(st, Vector3(x + 0.05, by + 0.3, y + 0.3), Vector3(x + 0.95, by + 0.4, y + 0.7), "planks", "planks")
			_box(st, Vector3(x + 0.1, by, y + 0.35), Vector3(x + 0.2, by + 0.3, y + 0.65), "pipe", "pipe", Color(0.4, 0.4, 0.45))
			_box(st, Vector3(x + 0.8, by, y + 0.35), Vector3(x + 0.9, by + 0.3, y + 0.65), "pipe", "pipe", Color(0.4, 0.4, 0.45))
		"sign":
			_box(st, Vector3(x + 0.45, by, y + 0.45), Vector3(x + 0.55, by + 0.9, y + 0.55), "planks", "planks")
			_box(st, Vector3(x + 0.15, by + 0.6, y + 0.48), Vector3(x + 0.85, by + 1.05, y + 0.58), "planks", "planks", Color(1.1, 1.0, 0.85))
		"fence":
			var len_x := int(p.get("len", 1))
			_box(st, Vector3(x, by + 0.35, y + 0.45), Vector3(x + len_x, by + 0.45, y + 0.55), "planks", "planks")
			for k in len_x + 1:
				_box(st, Vector3(x + k - 0.05, by, y + 0.42), Vector3(x + k + 0.05, by + 0.6, y + 0.58), "planks", "planks")
		"bunting", "lantern_string":
			var to: Array = p.get("to", [x + 4, y])
			var a := Vector3(x + 0.5, by + 2.3, y + 0.5)
			var b := _tile_center(int(to[0]), int(to[1]), 2.3)
			var n := int(a.distance_to(b) * 2.0)
			var cols := [Color(1, 0.55, 0.3), Color(1, 0.85, 0.4), Color(0.5, 0.8, 1.0), Color(0.95, 0.45, 0.6)]
			for k in n + 1:
				var f := float(k) / maxf(1.0, n)
				var pos := a.lerp(b, f) - Vector3(0, sin(f * PI) * 0.45, 0)
				if t == "lantern_string":
					_glow_box(pos - Vector3(0.07, 0.1, 0.07), pos + Vector3(0.07, 0.08, 0.07), cols[k % 4])
					if k % 2 == 0 and not low_preset:
						halos.append({"pos": pos, "color": Color(cols[k % 4].r, cols[k % 4].g, cols[k % 4].b, 0.35), "size": 0.7})
				else:
					var c2: Color = cols[k % 4]
					_quad(st_sway, pos + Vector3(-0.12, 0, 0), pos + Vector3(0.12, 0, 0), pos + Vector3(0, -0.3, 0), pos + Vector3(0, -0.3, 0), _uv_rect("plaster"), 1.0, c2)
		"bell", "bell_shrine":
			var big := t == "bell"
			var r := 0.9 if big else 0.3
			var hgt := 1.6 if big else 0.55
			var yb := by + (1.0 if big else 0.5)
			if not big:
				_box(st, Vector3(x + 0.2, by, y + 0.2), Vector3(x + 0.8, by + 0.45, y + 0.8), "stone", "stone_wall")
			_cyl(st, Vector3(x + 0.5, yb, y + 0.5), r, r * 0.45, hgt, 10, "brass", Color(1.1, 0.9, 0.6))
			_box(st, Vector3(x + 0.45, yb + hgt, y + 0.45), Vector3(x + 0.55, yb + hgt + 0.2, y + 0.55), "pipe", "pipe")
			if not big:
				_glow_box(Vector3(x + 0.42, by + 0.45, y + 0.42), Vector3(x + 0.58, by + 0.55, y + 0.58), Color(0.6, 1.0, 1.0))
				halos.append({"pos": Vector3(x + 0.5, by + 0.8, y + 0.5), "color": Color(0.5, 0.95, 1.0, 0.5), "size": 1.4})
		"door":
			# Door slab on the south face of the wall tile at (x, y).
			var top_y := by + 1.1
			_quad(st, Vector3(x + 0.22, top_y, y + 1.015), Vector3(x + 0.78, top_y, y + 1.015), Vector3(x + 0.78, by, y + 1.015), Vector3(x + 0.22, by, y + 1.015), _uv_rect("door"), 0.95, tint)
		"window_glow":
			pass   # light only
		"hatch":
			_quad(st, Vector3(x + 0.1, by + 0.03, y + 0.1), Vector3(x + 0.9, by + 0.03, y + 0.1), Vector3(x + 0.9, by + 0.03, y + 0.9), Vector3(x + 0.1, by + 0.03, y + 0.9), _uv_rect("grate"), 1.0, Color(0.9, 0.85, 0.7))
			_box(st, Vector3(x + 0.42, by, y + 0.42), Vector3(x + 0.58, by + 0.12, y + 0.58), "brass", "brass")
		"chest":
			var opened: bool = p.get("_opened", false)
			_box(st, Vector3(x + 0.2, by, y + 0.3), Vector3(x + 0.8, by + 0.4, y + 0.75), "planks", "brass", Color(1.0, 0.8, 0.5))
			if not opened:
				_box(st, Vector3(x + 0.18, by + 0.4, y + 0.28), Vector3(x + 0.82, by + 0.55, y + 0.77), "brass", "planks", Color(1.0, 0.85, 0.55))
		"pipe_run":
			var len2 := float(p.get("len", 3))
			var vert := bool(p.get("vertical", false))
			if vert:
				_box(st, Vector3(x + 0.35, by, y + 0.35), Vector3(x + 0.65, by + len2, y + 0.65), "pipe", "pipe")
			else:
				_box(st, Vector3(x, by + 0.9, y + 0.4), Vector3(x + len2, by + 1.2, y + 0.7), "pipe", "pipe")
		"valve":
			_cyl(st, Vector3(x + 0.5, by, y + 0.5), 0.15, 0.15, 0.7, 6, "pipe", Color(0.7, 0.7, 0.8))
			_cyl(st, Vector3(x + 0.5, by + 0.7, y + 0.5), 0.35, 0.35, 0.08, 8, "brass", Color(1.0, 0.5, 0.4) if not p.get("_on", false) else Color(0.5, 1.0, 0.6))
		"gear":
			_cyl(st, Vector3(x + 0.5, by, y + 0.5), 0.45, 0.45, 0.2, 12, "brass", Color(0.9, 0.8, 0.6))
		"crystal":
			_glow_box(Vector3(x + 0.35, by, y + 0.35), Vector3(x + 0.65, by + 0.9, y + 0.65), Color(0.6, 0.75, 1.0))
			halos.append({"pos": Vector3(x + 0.5, by + 0.6, y + 0.5), "color": Color(0.5, 0.7, 1.0, 0.5), "size": 1.6})
		"brazier", "campfire", "furnace":
			_cyl(st, Vector3(x + 0.5, by, y + 0.5), 0.3, 0.38, 0.5, 8, "stone_wall", Color(0.8, 0.8, 0.85))
			_glow_box(Vector3(x + 0.3, by + 0.5, y + 0.3), Vector3(x + 0.7, by + 0.75, y + 0.7), Color(1.0, 0.6, 0.25))
			halos.append({"pos": Vector3(x + 0.5, by + 0.85, y + 0.5), "color": Color(1.0, 0.55, 0.2, 0.6), "size": 2.0})
		"boat":
			var bl := float(p.get("len", 3))
			_box(st, Vector3(x + 0.1, by - 0.35, y + 0.2), Vector3(x + bl - 0.1, by - 0.05, y + 0.8), "planks", "planks", Color(0.85, 0.7, 0.55))
			_box(st, Vector3(x + 0.3, by - 0.05, y + 0.25), Vector3(x + 0.5, by + 0.1, y + 0.75), "planks", "planks")
		"rug":
			var rw := float(p.get("w", 2))
			var rh := float(p.get("h", 1))
			_quad(st, Vector3(x, by + 0.02, y), Vector3(x + rw, by + 0.02, y), Vector3(x + rw, by + 0.02, y + rh), Vector3(x, by + 0.02, y + rh), _uv_rect("carpet"), 1.0, tint)
		"table":
			_box(st, Vector3(x + 0.1, by + 0.55, y + 0.1), Vector3(x + float(p.get("w", 1)) - 0.1, by + 0.65, y + 0.9), "planks", "planks")
			_box(st, Vector3(x + 0.15, by, y + 0.15), Vector3(x + 0.25, by + 0.55, y + 0.25), "planks", "planks")
			_box(st, Vector3(x + float(p.get("w", 1)) - 0.25, by, y + 0.75), Vector3(x + float(p.get("w", 1)) - 0.15, by + 0.55, y + 0.85), "planks", "planks")
		"bed":
			_box(st, Vector3(x + 0.1, by, y + 0.05), Vector3(x + 0.9, by + 0.4, y + 1.9), "planks", "plaster", Color(0.9, 0.85, 0.8))
			_box(st, Vector3(x + 0.15, by + 0.4, y + 0.1), Vector3(x + 0.85, by + 0.5, y + 0.45), "plaster", "plaster")
			_box(st, Vector3(x + 0.12, by + 0.4, y + 0.6), Vector3(x + 0.88, by + 0.48, y + 1.85), "carpet", "carpet", tint)
		"mural":
			_quad(st, Vector3(x + 0.05, by + 1.3, y + 1.01), Vector3(x + 0.95, by + 1.3, y + 1.01), Vector3(x + 0.95, by + 0.4, y + 1.01), Vector3(x + 0.05, by + 0.4, y + 1.01), _uv_rect("mural"), 1.0, tint)
		"machine":
			var mw := float(p.get("w", 2))
			var md := float(p.get("d", 1))
			_box(st, Vector3(x + 0.05, by, y + 0.05), Vector3(x + mw - 0.05, by + 1.2, y + md - 0.05), "brass", "metal_wall", Color(0.9, 0.85, 0.8))
			_glow_box(Vector3(x + 0.3, by + 0.6, y + md - 0.04), Vector3(x + 0.6, by + 0.8, y + md), Color(0.5, 1.0, 0.9))
		_:
			pass


func _glow_box(mn: Vector3, mx: Vector3, col: Color) -> void:
	_box(st_glow, mn, mx, "plaster", "plaster", col, false)


# ------------------------------------------------------------------ materials

func _terrain_material() -> Material:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_texture = _atlas
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _glow_material() -> Material:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_texture = _atlas
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.albedo_color = Color(1.25, 1.2, 1.1)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _water_material() -> Material:
	var m := ShaderMaterial.new()
	m.shader = _water_shader
	var wc: Array = map.get("water_color", [0.1, 0.22, 0.32])
	m.set_shader_parameter("base_color", Color(wc[0], wc[1], wc[2]))
	m.set_shader_parameter("ambient", ambient)
	return m


func _sway_material() -> Material:
	var m := ShaderMaterial.new()
	m.shader = _sway_shader
	m.set_shader_parameter("atlas", _atlas)
	return m


func _build_halos() -> void:
	if halos.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = halos.size()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	for i in halos.size():
		var hl: Dictionary = halos[i]
		var s: float = hl.size
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, s, s)), hl.pos))
		mm.set_instance_color(i, hl.color)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Halos"
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _fx
	mat.uv1_scale = Vector3(1.0 / 8.0, 1.0 / 2.0, 1)
	mat.uv1_offset = Vector3(4.0 / 8.0, 1.0 / 2.0, 0)
	mat.no_depth_test = false
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)


func _build_particles() -> void:
	for p: Dictionary in map.get("props", []):
		var t: String = p.get("t", "")
		if not t in ["smoke", "steam", "fireflies", "dust", "embers"]:
			continue
		if low_preset and t in ["fireflies", "dust"]:
			continue
		var at: Array = p.at
		var pos := _tile_center(int(at[0]), int(at[1]), float(p.get("y", 0.0)))
		root.add_child(make_particles(t, pos, p))
	var weather: String = map.get("weather", "")
	if weather == "rain" and not low_preset:
		var c := make_particles("rain", Vector3(grid.w * 0.5, 8, grid.h * 0.5), {"w": grid.w, "h": grid.h})
		root.add_child(c)


static func make_particles(t: String, pos: Vector3, p: Dictionary) -> CPUParticles3D:
	var c := CPUParticles3D.new()
	c.position = pos
	var q := QuadMesh.new()
	q.size = Vector2(0.25, 0.25)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = fx_texture()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.uv1_scale = Vector3(1.0 / 8.0, 1.0 / 2.0, 1)
	mat.uv1_offset = Vector3(3.0 / 8.0, 1.0 / 2.0, 0)   # smoke puff cell
	q.material = mat
	c.mesh = q
	match t:
		"smoke", "steam":
			c.amount = 10
			c.lifetime = 3.0
			c.direction = Vector3(0.2, 1, 0)
			c.spread = 12
			c.initial_velocity_min = 0.3
			c.initial_velocity_max = 0.5
			c.gravity = Vector3(0.05, 0.05, 0)
			c.scale_amount_min = 1.5
			c.scale_amount_max = 3.0
			c.color = Color(0.7, 0.7, 0.8, 0.35) if t == "smoke" else Color(0.9, 0.95, 1.0, 0.4)
		"fireflies", "embers":
			mat.uv1_offset = Vector3(4.0 / 8.0, 1.0 / 2.0, 0)
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			c.amount = 14
			c.lifetime = 4.0
			c.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			c.emission_box_extents = Vector3(float(p.get("w", 4)), 1.0, float(p.get("h", 4)))
			c.direction = Vector3(0, 1, 0)
			c.spread = 180
			c.initial_velocity_min = 0.05
			c.initial_velocity_max = 0.25
			c.gravity = Vector3(0, 0.02 if t == "fireflies" else 0.3, 0)
			c.scale_amount_min = 0.4
			c.scale_amount_max = 0.8
			c.color = Color(1.0, 0.85, 0.4, 0.9) if t == "fireflies" else Color(1.0, 0.5, 0.2, 0.9)
		"dust":
			c.amount = 18
			c.lifetime = 6.0
			c.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			c.emission_box_extents = Vector3(float(p.get("w", 6)), 1.5, float(p.get("h", 6)))
			c.spread = 180
			c.initial_velocity_min = 0.02
			c.initial_velocity_max = 0.08
			c.gravity = Vector3.ZERO
			c.scale_amount_min = 0.15
			c.scale_amount_max = 0.3
			c.color = Color(0.9, 0.9, 0.8, 0.4)
		"rain":
			mat.uv1_offset = Vector3(0, 0, 0)
			q.size = Vector2(0.04, 0.5)
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
			c.amount = 180
			c.lifetime = 0.8
			c.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			c.emission_box_extents = Vector3(float(p.get("w", 20)) * 0.6, 0.5, float(p.get("h", 20)) * 0.6)
			c.direction = Vector3(-0.1, -1, 0)
			c.spread = 2
			c.initial_velocity_min = 10
			c.initial_velocity_max = 12
			c.gravity = Vector3.ZERO
			c.color = Color(0.7, 0.8, 1.0, 0.45)
	return c
