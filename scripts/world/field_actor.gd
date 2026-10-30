class_name FieldActor
extends Node3D
## A grid-bound pixel-art character in the field. Uses an upright Y-billboard
## whose height is stretched by 1/cos(camera pitch) so pixels keep their
## authored proportions under the tilted camera (no backward lean, no clipping).

signal arrived

const PPU := 24.0
const CAMERA_PITCH_DEG := 40.0
enum Facing { DOWN, UP, LEFT, RIGHT }

var actor_id: String = ""
var sprite_id: String = ""
var grid_pos: Vector2i = Vector2i.ZERO
var facing: int = Facing.DOWN
var moving: bool = false
var data: Dictionary = {}
var sprite: Sprite3D
var shadow: MeshInstance3D
var emote: Label3D
var _anim_t: float = 0.0
var _step_phase: int = 0
var _tween: Tween
var _move_speed: float = 4.5


static func dir_to_facing(d: Vector2i) -> int:
	if d.y > 0: return Facing.DOWN
	if d.y < 0: return Facing.UP
	if d.x < 0: return Facing.LEFT
	return Facing.RIGHT


static func facing_vec(f: int) -> Vector2i:
	match f:
		Facing.UP: return Vector2i(0, -1)
		Facing.LEFT: return Vector2i(-1, 0)
		Facing.RIGHT: return Vector2i(1, 0)
	return Vector2i(0, 1)


static func facing_from_name(s: String) -> int:
	match s:
		"up": return Facing.UP
		"left": return Facing.LEFT
		"right": return Facing.RIGHT
	return Facing.DOWN


func setup(id: String, spr: String) -> void:
	actor_id = id
	sprite_id = spr
	name = id
	sprite = Sprite3D.new()
	var path := "res://assets/sprites/chars/%s_field.png" % spr
	if ResourceLoader.exists(path):
		sprite.texture = load(path)
	sprite.hframes = 3
	sprite.vframes = 4
	sprite.pixel_size = 1.0 / PPU
	sprite.centered = true
	sprite.offset = Vector2(0, 16)
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.shaded = false
	sprite.double_sided = true
	sprite.scale = Vector3(1.0, 1.0 / cos(deg_to_rad(CAMERA_PITCH_DEG)), 1.0)
	add_child(sprite)
	shadow = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.62, 0.36)
	q.orientation = PlaneMesh.FACE_Y
	shadow.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = MapBuilder.fx_texture()
	m.uv1_scale = Vector3(1.0 / 8.0, 1.0 / 2.0, 1)
	m.uv1_offset = Vector3(4.0 / 8.0, 1.0 / 2.0, 0)
	m.albedo_color = Color(0, 0, 0, 0.55)
	shadow.material_override = m
	shadow.position = Vector3(0, 0.02, 0)
	add_child(shadow)
	_update_frame()


func set_tint(c: Color) -> void:
	if sprite:
		sprite.modulate = c


func place(p: Vector2i, height: float) -> void:
	grid_pos = p
	position = Vector3(p.x + 0.5, height, p.y + 0.5)


func face(f: int) -> void:
	facing = f
	_update_frame()


func face_toward(target: Vector2i) -> void:
	var d := target - grid_pos
	if abs(d.x) > abs(d.y):
		face(Facing.RIGHT if d.x > 0 else Facing.LEFT)
	elif d != Vector2i.ZERO:
		face(Facing.DOWN if d.y > 0 else Facing.UP)


func step_to(p: Vector2i, height: float, speed: float = 4.5) -> void:
	_move_speed = speed
	face(dir_to_facing(p - grid_pos))
	grid_pos = p
	moving = true
	if _tween:
		_tween.kill()
	_tween = create_tween()
	var target := Vector3(p.x + 0.5, height, p.y + 0.5)
	_tween.tween_property(self, "position", target, 1.0 / speed)
	_tween.tween_callback(_on_arrived)


func _on_arrived() -> void:
	moving = false
	arrived.emit()


func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	if moving:
		_anim_t += delta * _move_speed * 1.0
		if _anim_t >= 0.5:
			_anim_t = 0.0
			_step_phase = (_step_phase + 1) % 4
			_update_frame()
	elif _step_phase != 0:
		_step_phase = 0
		_update_frame()


func _update_frame() -> void:
	if sprite == null:
		return
	var col := 0
	match _step_phase:
		1: col = 1
		3: col = 2
	sprite.frame = facing * 3 + col


func show_emote(text: String, seconds: float = 1.2) -> void:
	if emote == null:
		emote = Label3D.new()
		emote.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		emote.font = UITheme.bold()
		emote.font_size = 64
		emote.outline_size = 12
		emote.pixel_size = 0.006
		emote.position = Vector3(0, 2.1, 0)
		emote.no_depth_test = true
		add_child(emote)
	emote.text = text
	emote.visible = true
	var tw := create_tween()
	tw.tween_interval(seconds)
	tw.tween_callback(func() -> void: emote.visible = false)
