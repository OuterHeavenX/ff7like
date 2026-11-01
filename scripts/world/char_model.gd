class_name CharModel
extends Node3D
## Procedural low-poly 3D character (chibi proportions) assembled from rounded
## boxes, driven by the appearance specs that tools/gen_art.py exports to
## assets/models/appearance.json (same palette as the 2D sprites/portraits).
## Handles facing (smooth yaw), walk cycle, idle breathing, blinking, battle
## poses, local light tint and hit flashes. Front of the model is +Z.

enum Pose { IDLE, READY, WINDUP, STRIKE, CAST, HURT, KO, VICTORY }

const FACE_SIZE := 0.5
const MODEL_SCALE := 1.1
const SHADER_PATH := "res://scenes/world/char.gdshader"
const OUTLINE_PATH := "res://scenes/world/char_outline.gdshader"

static var _specs: Dictionary = {}
static var _builds: Dictionary = {}
static var _shader: Shader
static var _outline: ShaderMaterial
static var _mesh_cache: Dictionary = {}

var spec: Dictionary = {}
var mat: ShaderMaterial
var body: Node3D
var hips: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var weapon: Node3D
var yaw_target: float = 0.0
var pose: int = Pose.IDLE
## Walk-cycle inputs, set by the owner (FieldActor) every frame.
var walking: bool = false
var walk_speed: float = 4.5
## Sprite3D-compatible aliases so battle code can drive models and sprites alike.
var frame: int = 0:
	set(v):
		frame = v
		pose = v
var modulate: Color = Color(1, 1, 1, 1):
	set(v):
		modulate = v
		if mat:
			mat.set_shader_parameter("mod_color", Color(v.r, v.g, v.b, 1.0))
var segments: int = 2
var _dims: Dictionary = {}
var _walk: float = 0.0
var _walk_amt: float = 0.0
var _t: float = 0.0
var _blink_t: float = 2.5
var _flash: float = 0.0
var _flash_on: bool = false
var _batches: Dictionary = {}      # pivot Node3D -> SurfaceTool (parts merged per limb)


static func _load_specs() -> void:
	if not _specs.is_empty():
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/appearance.json"))
	if d is Dictionary:
		_specs = d.get("characters", {})
		_builds = d.get("builds", {})
	_shader = load(SHADER_PATH)
	_outline = ShaderMaterial.new()
	_outline.shader = load(OUTLINE_PATH)


static func has_spec(id: String) -> bool:
	_load_specs()
	return _specs.has(id)


func build(sprite_id: String, with_weapon: bool = false) -> void:
	_load_specs()
	spec = _specs.get(sprite_id, _specs.get("townsman", {}))
	var low := str(Settings.get_value("visual_preset")) == "low"
	if low:
		segments = 1
	mat = ShaderMaterial.new()
	mat.shader = _shader
	var face_path := "res://assets/models/faces/%s.png" % sprite_id
	if ResourceLoader.exists(face_path):
		mat.set_shader_parameter("face_tex", load(face_path))
	var b := str(spec.get("build", "normal"))
	_dims = _dims_for(b)
	if not low:
		mat.next_pass = _outline
	body = Node3D.new()
	body.name = "Body"
	add_child(body)
	body.scale = Vector3.ONE * MODEL_SCALE * (0.74 if b == "child" else 1.0)
	_build_legs()
	_build_torso()
	_build_head()
	_build_accessories()
	if with_weapon:
		_build_weapon(str(spec.get("weapon", "none")))
	_commit_batches()


static func _dims_for(b: String) -> Dictionary:
	var d := {"tw": 0.40, "th": 0.38, "td": 0.26, "leg": 0.40, "aw": 0.13, "al": 0.36, "lw": 0.15,
		"head": Vector3(0.62, 0.56, 0.54)}
	match b:
		"slim":
			d.tw = 0.36
			d.td = 0.24
			d.aw = 0.12
			d.lw = 0.14
		"broad":
			d.tw = 0.50
			d.th = 0.42
			d.td = 0.31
			d.aw = 0.155
			d.al = 0.38
			d.lw = 0.17
		"tall":
			d.th = 0.44
			d.leg = 0.50
			d.al = 0.42
		"child":
			d.tw = 0.38
			d.th = 0.32
			d.leg = 0.32
			d.al = 0.30
			d.head = Vector3(0.66, 0.60, 0.58)
	return d


func _col(key: String) -> Color:
	return Color(str(spec.get(key, "#888888")))


# ------------------------------------------------------------------ meshes

## Rounded box centred on the origin with smooth normals. Each face is a grid
## whose border rows are spaced by tan() so the bevel samples evenly in angle.
static func rounded_box(size: Vector3, radius: float, color: Color, seg: int = 3,
		face_cy: float = INF) -> ArrayMesh:
	var key := "%s|%.3f|%s|%d|%s" % [size, radius, color.to_html(), seg, face_cy]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var h := size * 0.5
	var r := minf(radius, minf(h.x, minf(h.y, h.z)) * 0.98)
	var inner := h - Vector3(r, r, r)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(color)
	var axes := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	for n: Vector3 in axes:
		var u := Vector3.UP if absf(n.y) < 0.5 else Vector3.RIGHT
		var v := n.cross(u)
		var cu := _axis_coords(absf(u.dot(h)), r, seg)
		var cv := _axis_coords(absf(v.dot(h)), r, seg)
		var nd := absf(n.dot(h))
		var pts: Array = []
		var nrm: Array = []
		for a: float in cu:
			var row_p: Array = []
			var row_n: Array = []
			for c: float in cv:
				var q: Vector3 = n * nd + u * a + v * c
				var cl := Vector3(clampf(q.x, -inner.x, inner.x), clampf(q.y, -inner.y, inner.y), clampf(q.z, -inner.z, inner.z))
				var dv := q - cl
				var nn := n if dv.length() < 0.00001 else dv.normalized()
				row_p.append(cl + nn * r)
				row_n.append(nn)
			pts.append(row_p)
			nrm.append(row_n)
		for i in cu.size() - 1:
			for j in cv.size() - 1:
				var quad := [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]
				for tri: Array in [[0, 1, 2], [0, 2, 3]]:
					var p0: Vector3 = pts[quad[tri[0]][0]][quad[tri[0]][1]]
					var p1: Vector3 = pts[quad[tri[1]][0]][quad[tri[1]][1]]
					var p2: Vector3 = pts[quad[tri[2]][0]][quad[tri[2]][1]]
					var order: Array = tri
					# Godot treats clockwise triangles (seen from outside) as front faces.
					if (p1 - p0).cross(p2 - p0).dot(n) > 0.0:
						order = [tri[0], tri[2], tri[1]]
					for k: int in order:
						var ij: Array = quad[k]
						var p: Vector3 = pts[ij[0]][ij[1]]
						st.set_normal(nrm[ij[0]][ij[1]])
						if face_cy == INF:
							st.set_uv(Vector2(-1, -1))
						else:
							st.set_uv(Vector2(0.5 + p.x / FACE_SIZE, 0.5 - (p.y - face_cy) / FACE_SIZE))
						st.add_vertex(p)
	var mesh := st.commit()
	_mesh_cache[key] = mesh
	return mesh


static func _axis_coords(half: float, r: float, seg: int) -> Array:
	var inner := half - r
	var out: Array = []
	for k in range(seg, 0, -1):
		out.append(-(inner + r * tan(float(k) * PI / (4.0 * seg))))
	out.append(-inner)
	if inner > 0.0005:
		out.append(inner)
	for k in range(1, seg + 1):
		out.append(inner + r * tan(float(k) * PI / (4.0 * seg)))
	return out


## Queues a rounded box on a pivot; all parts of one pivot become one mesh.
func _part(parent: Node3D, size: Vector3, pos: Vector3, color: Color, radius: float = -1.0,
		rot: Vector3 = Vector3.ZERO, face_cy: float = INF) -> void:
	var r := radius if radius >= 0.0 else minf(size.x, minf(size.y, size.z)) * 0.3
	var mesh := rounded_box(size, r, color, segments if r > 0.03 else 1, face_cy)
	if not _batches.has(parent):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[parent] = st
	(_batches[parent] as SurfaceTool).append_from(mesh, 0, Transform3D(Basis.from_euler(rot), pos))


func _commit_batches() -> void:
	for pivot: Node3D in _batches.keys():
		var mi := MeshInstance3D.new()
		mi.mesh = (_batches[pivot] as SurfaceTool).commit()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(mi)
	_batches.clear()


func _pivot(parent: Node3D, pos: Vector3, nm: String) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	n.position = pos
	parent.add_child(n)
	return n


# ------------------------------------------------------------------ body

func _build_legs() -> void:
	var leg: float = _dims.leg
	var lw: float = _dims.lw
	var pants := _col("pants")
	var boots := _col("boots")
	for side in [-1, 1]:
		var p := _pivot(body, Vector3(0.095 * side, leg, 0), "LegL" if side < 0 else "LegR")
		_part(p, Vector3(lw, leg - 0.10, lw + 0.01), Vector3(0, -(leg - 0.10) * 0.5, 0), pants, 0.04)
		_part(p, Vector3(lw + 0.03, 0.14, lw + 0.08), Vector3(0, -leg + 0.07, 0.03), boots, 0.045)
		if side < 0:
			leg_l = p
		else:
			leg_r = p


func _build_torso() -> void:
	var tw: float = _dims.tw
	var th: float = _dims.th
	var td: float = _dims.td
	hips = _pivot(body, Vector3(0, _dims.leg, 0), "Hips")
	var coat := _col("coat")
	var coat2 := _col("coat2")
	_part(hips, Vector3(tw, th, td), Vector3(0, th * 0.5, 0), coat, 0.09)
	# Coat hem / skirt, belt and centre seam.
	_part(hips, Vector3(tw + 0.03, 0.14, td + 0.03), Vector3(0, 0.02, 0), coat2, 0.05)
	_part(hips, Vector3(tw + 0.02, 0.045, td + 0.02), Vector3(0, 0.11, 0), coat2.darkened(0.35), 0.015)
	_part(hips, Vector3(0.05, th - 0.12, 0.02), Vector3(0, th * 0.55, td * 0.5), coat2, 0.01)
	_part(hips, Vector3(0.13, 0.06, 0.12), Vector3(0, th + 0.02, 0), _col("skin"), 0.03)
	var aw: float = _dims.aw
	var al: float = _dims.al
	for side in [-1, 1]:
		var p := _pivot(hips, Vector3((tw * 0.5 + aw * 0.5 + 0.005) * side, th - 0.05, 0), "ArmL" if side < 0 else "ArmR")
		p.rotation.z = 0.08 * side
		_part(p, Vector3(aw, al - 0.08, aw + 0.01), Vector3(0, -(al - 0.08) * 0.5 + 0.03, 0), coat, 0.05)
		_part(p, Vector3(aw + 0.01, 0.05, aw + 0.02), Vector3(0, -al + 0.10, 0), coat2, 0.02)
		_part(p, Vector3(aw - 0.01, 0.11, aw), Vector3(0, -al + 0.03, 0), _col("skin"), 0.045)
		if side < 0:
			arm_l = p
		else:
			arm_r = p


func _build_head() -> void:
	var hs: Vector3 = _dims.head
	head = _pivot(hips, Vector3(0, float(_dims.th) + 0.04, 0), "Head")
	var cy := hs.y * 0.5
	_part(head, hs, Vector3(0, cy, 0), _col("skin"), 0.13, Vector3.ZERO, -0.03)
	_build_hair(str(spec.get("hair_style", "short")), hs, cy)


func _build_hair(style: String, hs: Vector3, cy: float) -> void:
	var hair := _col("hair")
	var hx := hs.x * 0.5
	var hz := hs.z * 0.5
	var top := cy + hs.y * 0.5
	match style:
		"helmet":
			var c := _col("coat")
			_part(head, Vector3(hs.x + 0.08, 0.30, hs.z + 0.08), Vector3(0, top - 0.10, -0.01), c, 0.1)
			_part(head, Vector3(hs.x + 0.12, 0.05, hs.z + 0.12), Vector3(0, top - 0.24, 0.0), c.darkened(0.2), 0.02)
			_part(head, Vector3(0.07, 0.12, hs.z * 0.8), Vector3(0, top + 0.07, -0.02), _col("accent"), 0.03)
			return
		"hood":
			var c2 := _col("coat")
			_part(head, Vector3(hs.x + 0.10, 0.20, hs.z + 0.10), Vector3(0, top - 0.04, -0.03), c2, 0.09)
			for s in [-1, 1]:
				_part(head, Vector3(0.07, hs.y * 0.92, hs.z * 0.95), Vector3((hx + 0.035) * s, cy - 0.02, -0.03), c2, 0.03)
			_part(head, Vector3(hs.x + 0.10, hs.y * 0.95, 0.10), Vector3(0, cy - 0.02, -hz - 0.03), c2, 0.04)
			_part(head, Vector3(0.24, 0.20, 0.10), Vector3(0, cy - 0.28, -hz - 0.06), c2.darkened(0.15), 0.04)
			_part(head, Vector3(hs.x - 0.06, 0.07, 0.06), Vector3(0, top - 0.17, hz + 0.0), hair, 0.025)
			return
		"hat":
			var hc := Color("#3a2a4a")
			_part(head, Vector3(hs.x - 0.08, 0.26, hs.z - 0.08), Vector3(0, top + 0.10, -0.02), hc, 0.06)
			_part(head, Vector3(hs.x + 0.26, 0.05, hs.z + 0.24), Vector3(0, top - 0.03, 0.0), hc, 0.025)
			_part(head, Vector3(hs.x - 0.06, 0.05, hs.z - 0.06), Vector3(0, top + 0.02, -0.02), _col("accent"), 0.015)
			_part(head, Vector3(0.05, 0.30, 0.09), Vector3(hx - 0.06, top + 0.24, -0.08), Color("#f6f0e0"), 0.02, Vector3(0.0, 0.0, -0.35))
			_part(head, Vector3(hs.x + 0.02, 0.24, 0.10), Vector3(0, cy + 0.02, -hz - 0.01), hair, 0.04)
			return
		"cap":
			var cc := _col("coat2")
			_part(head, Vector3(hs.x + 0.05, 0.20, hs.z + 0.04), Vector3(0, top - 0.04, -0.01), cc, 0.08)
			_part(head, Vector3(hs.x * 0.8, 0.04, 0.20), Vector3(0, top - 0.11, hz + 0.08), cc.darkened(0.2), 0.015)
			_part(head, Vector3(hs.x + 0.03, 0.22, 0.10), Vector3(0, cy + 0.02, -hz - 0.01), hair, 0.04)
			for s in [-1, 1]:
				_part(head, Vector3(0.05, 0.14, 0.16), Vector3((hx + 0.01) * s, cy + 0.04, 0.02), hair, 0.02)
			return
		"bald_beard":
			_part(head, Vector3(hs.x - 0.04, 0.22, 0.12), Vector3(0, cy - 0.20, hz - 0.02), hair, 0.06)
			_part(head, Vector3(0.20, 0.14, 0.10), Vector3(0, cy - 0.34, hz - 0.04), hair, 0.05)
			for s in [-1, 1]:
				_part(head, Vector3(0.05, 0.16, 0.20), Vector3((hx + 0.01) * s, cy + 0.0, -0.06), hair, 0.02)
			return
	# Shared base: crown + back + bangs for ordinary hairstyles.
	var crown_h := 0.17 if style in ["slick", "cropped_beard"] else 0.26
	_part(head, Vector3(hs.x + 0.06, crown_h, hs.z + 0.05), Vector3(0, top - crown_h * 0.5 + 0.05, -0.02), hair, 0.125)
	_part(head, Vector3(hs.x + 0.04, hs.y * 0.62, 0.12), Vector3(0, cy + 0.06, -hz - 0.0), hair, 0.05)
	if style not in ["slick", "cropped_beard"]:
		_part(head, Vector3(hs.x - 0.02, 0.09, 0.07), Vector3(0, top - 0.10, hz + 0.0), hair, 0.03)
		for s in [-1, 1]:
			_part(head, Vector3(0.06, 0.20, 0.18), Vector3((hx + 0.01) * s, cy + 0.06, 0.06), hair, 0.025)
	match style:
		"tousled":
			for t: Array in [[-0.13, 0.10, 0.5], [0.06, 0.04, -0.4], [0.17, -0.10, 0.3]]:
				_part(head, Vector3(0.12, 0.10, 0.26), Vector3(t[0], top + 0.04, t[1]), hair, 0.05, Vector3(0.55, float(t[2]), 0.0))
		"ponytail":
			_part(head, Vector3(0.08, 0.06, 0.06), Vector3(0, cy + 0.12, -hz - 0.09), _col("accent"), 0.02)
			_part(head, Vector3(0.14, 0.40, 0.13), Vector3(0, cy - 0.12, -hz - 0.14), hair, 0.06, Vector3(-0.35, 0, 0))
		"long":
			_part(head, Vector3(hs.x + 0.04, 0.50, 0.12), Vector3(0, cy - 0.30, -hz + 0.01), hair, 0.05)
			for s in [-1, 1]:
				_part(head, Vector3(0.08, 0.44, 0.12), Vector3((hx - 0.01) * s, cy - 0.12, hz - 0.06), hair, 0.035)
		"braid":
			for i in 4:
				_part(head, Vector3(0.13, 0.12, 0.12), Vector3(0.0, cy - 0.10 - i * 0.11, -hz - 0.08 - i * 0.01), hair, 0.05)
			_part(head, Vector3(0.10, 0.05, 0.10), Vector3(0, cy - 0.53, -hz - 0.12), _col("accent"), 0.02)
		"bob":
			for s in [-1, 1]:
				_part(head, Vector3(0.10, hs.y * 0.78, hs.z * 0.8), Vector3((hx + 0.03) * s, cy - 0.04, -0.03), hair, 0.04)
		"bun":
			_part(head, Vector3(0.24, 0.22, 0.22), Vector3(0, top + 0.06, -hz + 0.04), hair, 0.09)
		"slick":
			_part(head, Vector3(0.24, 0.06, hs.z * 0.9), Vector3(-0.12, top + 0.03, -0.02), hair.lightened(0.12), 0.02)
		"cropped_beard":
			_part(head, Vector3(hs.x - 0.06, 0.12, 0.08), Vector3(0, cy - 0.24, hz - 0.01), hair.darkened(0.1), 0.04)


func _build_accessories() -> void:
	var tw: float = _dims.tw
	var th: float = _dims.th
	var td: float = _dims.td
	var acc := _col("accent")
	match str(spec.get("acc", "none")):
		"satchel":
			_part(hips, Vector3(0.05, th * 1.25, 0.03), Vector3(0.0, th * 0.55, td * 0.5 + 0.015), Color("#6a4024"), 0.01, Vector3(0, 0, 0.75))
			_part(hips, Vector3(0.17, 0.17, 0.10), Vector3(tw * 0.5 + 0.02, 0.12, 0.06), Color("#8a5a34"), 0.04)
		"goggles":
			var hs: Vector3 = _dims.head
			var y := hs.y - 0.13
			_part(head, Vector3(hs.x + 0.07, 0.06, hs.z + 0.07), Vector3(0, y, -0.01), Color("#5a3a22"), 0.02)
			for s in [-1, 1]:
				_part(head, Vector3(0.14, 0.10, 0.06), Vector3(0.13 * s, y + 0.01, hs.z * 0.5 + 0.03), acc, 0.04)
		"pauldron":
			_part(hips, Vector3(0.22, 0.10, td + 0.06), Vector3(-(tw * 0.5 + 0.05), th - 0.01, 0), acc.darkened(0.1), 0.04)
		"sash":
			_part(hips, Vector3(0.07, th * 1.25, 0.03), Vector3(0.0, th * 0.5, td * 0.5 + 0.015), acc, 0.01, Vector3(0, 0, -0.75))
		"scarf":
			_part(hips, Vector3(tw * 0.85, 0.09, td + 0.04), Vector3(0, th - 0.01, 0), acc, 0.04)
			_part(hips, Vector3(0.08, 0.22, 0.04), Vector3(tw * 0.25, th - 0.12, td * 0.5 + 0.03), acc, 0.02)
		"collar":
			_part(hips, Vector3(tw * 0.7, 0.10, td + 0.02), Vector3(0, th + 0.01, -0.01), acc, 0.03)
		"shawl":
			_part(hips, Vector3(tw + 0.10, 0.12, td + 0.06), Vector3(0, th - 0.04, 0), acc, 0.05)
		"apron":
			_part(hips, Vector3(tw * 0.78, th * 0.85, 0.03), Vector3(0, th * 0.38, td * 0.5 + 0.02), Color("#efe8d8"), 0.01)
		"bell":
			_part(hips, Vector3(0.09, 0.09, 0.09), Vector3(0, 0.08, td * 0.5 + 0.05), acc, 0.04)


func _build_weapon(kind: String) -> void:
	if arm_r == null:
		return
	var al: float = _dims.al
	weapon = _pivot(arm_r, Vector3(0, -al + 0.03, 0.02), "Weapon")
	var metal := Color("#c8d0dc")
	var wood := Color("#7a5232")
	var acc := _col("accent")
	match kind:
		"blade":
			_part(weapon, Vector3(0.05, 0.08, 0.05), Vector3(0, 0, 0), wood, 0.015)
			_part(weapon, Vector3(0.16, 0.035, 0.05), Vector3(0, 0, 0.06), acc, 0.012)
			_part(weapon, Vector3(0.035, 0.05, 0.62), Vector3(0, 0, 0.38), metal, 0.012)
		"wrench":
			_part(weapon, Vector3(0.05, 0.05, 0.42), Vector3(0, 0, 0.18), Color("#8a8e96"), 0.015)
			_part(weapon, Vector3(0.16, 0.06, 0.10), Vector3(0, 0, 0.42), Color("#8a8e96"), 0.02)
		"shield":
			_part(weapon, Vector3(0.06, 0.44, 0.36), Vector3(0.06, 0.08, 0.06), Color("#4f6884"), 0.05)
			_part(weapon, Vector3(0.07, 0.16, 0.14), Vector3(0.07, 0.08, 0.06), acc, 0.04)
		"staff":
			_part(weapon, Vector3(0.045, 0.045, 1.0), Vector3(0, 0, 0.18), wood, 0.015)
			_part(weapon, Vector3(0.11, 0.11, 0.11), Vector3(0, 0, 0.70), acc, 0.05)
		"tome":
			_part(weapon, Vector3(0.20, 0.26, 0.07), Vector3(0, -0.02, 0.08), Color("#5b3f7d"), 0.02)
			_part(weapon, Vector3(0.17, 0.23, 0.075), Vector3(0.012, -0.02, 0.08), Color("#efe8d8"), 0.01)
		"bow":
			for i in 5:
				var a := (float(i) - 2.0) * 0.38
				_part(weapon, Vector3(0.04, 0.04, 0.16), Vector3(0, sin(a) * 0.30, 0.1 + cos(a) * 0.12), wood, 0.012, Vector3(a, 0, 0))
		"lute":
			_part(weapon, Vector3(0.26, 0.30, 0.10), Vector3(0, -0.04, 0.14), Color("#a8743a"), 0.08)
			_part(weapon, Vector3(0.05, 0.05, 0.34), Vector3(0, 0.0, 0.40), wood, 0.015)


# ------------------------------------------------------------------ runtime

func set_facing_yaw(yaw: float, snap: bool = false) -> void:
	yaw_target = yaw
	if snap:
		rotation.y = yaw


func set_light(c: Color) -> void:
	if mat:
		mat.set_shader_parameter("light_tint", c)


func flash(color: Color = Color(1, 1, 1), seconds: float = 0.15) -> void:
	_flash = seconds
	if mat:
		mat.set_shader_parameter("flash_color", color)


func set_pose(p: int) -> void:
	pose = p


func _process(delta: float) -> void:
	animate(minf(delta, 0.1), walking, walk_speed)


## Advance animation. `moving` drives the walk cycle; `speed` is tiles/sec.
func animate(delta: float, moving: bool, speed: float = 4.5) -> void:
	_t += delta
	_walk_amt = move_toward(_walk_amt, 1.0 if moving else 0.0, delta * 7.0)
	if moving:
		_walk += delta * speed * PI
	var s := sin(_walk) * _walk_amt
	var k := 1.0 - exp(-delta * 14.0)
	rotation.y = lerp_angle(rotation.y, yaw_target, 1.0 - exp(-delta * 16.0))
	var breath := sin(_t * 2.2) * 0.012
	var want := {"leg_l": s * 0.75, "leg_r": -s * 0.75, "arm_l": -s * 0.65, "arm_r": s * 0.65,
		"lean": 0.06 * _walk_amt, "head": 0.0, "arm_l_z": -0.08, "arm_r_z": 0.08, "body_x": 0.0,
		"body_y": absf(sin(_walk)) * 0.05 * _walk_amt + breath * (1.0 - _walk_amt)}
	match pose:
		Pose.READY:
			want.lean = 0.18
			want.arm_l = -0.5
			want.arm_r = -0.6
			want.leg_l = -0.25
			want.leg_r = 0.2
			want.body_y = -0.03 + breath
		Pose.WINDUP:
			want.lean = -0.15
			want.arm_r = -3.3
			want.arm_l = -0.4
			want.leg_l = -0.35
			want.leg_r = 0.3
		Pose.STRIKE:
			want.lean = 0.38
			want.arm_r = -1.25
			want.arm_l = 0.5
			want.leg_l = -0.55
			want.leg_r = 0.45
			want.body_y = -0.04
		Pose.CAST:
			want.lean = -0.08
			want.arm_l = -2.0
			want.arm_r = -2.0
			want.arm_l_z = 0.25
			want.arm_r_z = -0.25
			want.head = -0.15
		Pose.HURT:
			want.lean = -0.4
			want.head = -0.3
			want.arm_l = 0.6
			want.arm_r = 0.6
			want.arm_l_z = -0.5
			want.arm_r_z = 0.5
		Pose.KO:
			want.body_x = -PI * 0.5
			want.lean = 0.0
			want.arm_l = -2.8
			want.arm_r = -2.8
			want.leg_l = 0.0
			want.leg_r = 0.0
			want.body_y = 0.16
		Pose.VICTORY:
			want.arm_r = -3.0
			want.arm_l = -0.2
			want.arm_l_z = -0.3
			want.head = -0.1
			want.body_y = absf(sin(_t * 5.0)) * 0.06
	leg_l.rotation.x = lerpf(leg_l.rotation.x, want.leg_l, k)
	leg_r.rotation.x = lerpf(leg_r.rotation.x, want.leg_r, k)
	arm_l.rotation.x = lerpf(arm_l.rotation.x, want.arm_l, k)
	arm_r.rotation.x = lerpf(arm_r.rotation.x, want.arm_r, k)
	arm_l.rotation.z = lerpf(arm_l.rotation.z, want.arm_l_z, k)
	arm_r.rotation.z = lerpf(arm_r.rotation.z, want.arm_r_z, k)
	hips.rotation.x = lerpf(hips.rotation.x, want.lean, k)
	head.rotation.x = lerpf(head.rotation.x, want.head + sin(_t * 1.3) * 0.02, k)
	body.rotation.x = lerpf(body.rotation.x, want.body_x, k * 0.6)
	body.position.y = lerpf(body.position.y, want.body_y, k)
	# Blink every few seconds.
	_blink_t -= delta
	var blink := _blink_t < 0.12
	if _blink_t < 0.0:
		_blink_t = 2.0 + fmod(_t * 7.31, 3.0)
	if mat:
		mat.set_shader_parameter("face_frame", 1.0 if (blink or pose == Pose.KO) else 0.0)
		if _flash > 0.0:
			_flash -= delta
			_flash_on = true
			mat.set_shader_parameter("flash", clampf(_flash / 0.15, 0.0, 1.0) * 0.8)
		elif _flash_on:
			_flash_on = false
			mat.set_shader_parameter("flash", 0.0)
