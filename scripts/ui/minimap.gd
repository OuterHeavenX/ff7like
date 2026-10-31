class_name Minimap
extends Control
## Top-down map of the current field map: terrain, exits (gold when they lead
## to the objective), people, the player with facing, and the objective.
## Used small in the HUD and large in the pause menu's Map page.

var world: Node3D
var max_size: Vector2 = Vector2(232, 150)
var show_title: bool = false
var _tex: ImageTexture
var _tile: float = 6.0
var _map_px: Vector2 = Vector2.ZERO
var _map_id: String = ""
var _t: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	if world == null or world.grid == null:
		return
	if str(world.map_id) != _map_id:
		rebuild()
	queue_redraw()


func rebuild() -> void:
	_map_id = str(world.map_id)
	var g: MapGrid = world.grid
	_tile = clampf(floorf(minf(max_size.x / g.w, max_size.y / g.h)), 2.0, 16.0)
	_map_px = Vector2(g.w, g.h) * _tile
	custom_minimum_size = _map_px + Vector2(12, 12 + (22 if show_title else 0))
	size = custom_minimum_size
	var img := Image.create(g.w, g.h, false, Image.FORMAT_RGBA8)
	for y in g.h:
		for x in g.w:
			img.set_pixel(x, y, _tile_color(g, x, y))
	_tex = ImageTexture.create_from_image(img)


static func _tile_color(g: MapGrid, x: int, y: int) -> Color:
	var i := g.idx(x, y)
	if g.water[i] == 1:
		return Color(0.16, 0.34, 0.52)
	if g.walk[i] == 1:
		var lv := float(g.level[i])
		var c := Color(0.50, 0.48, 0.46).lightened(clampf(lv * 0.06, -0.3, 0.3))
		if g.stair[i] != "":
			c = c.lightened(0.18)
		return c
	if g.ch(x, y) == " ":
		return Color(0, 0, 0, 0)
	return Color(0.17, 0.15, 0.21)


func _origin() -> Vector2:
	return Vector2(6, 6 + (22 if show_title else 0))


func _to_px(tile: Vector2) -> Vector2:
	return _origin() + tile * _tile


func _draw() -> void:
	if world == null or world.grid == null or _tex == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.03, 0.07, 0.72))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.85, 0.72, 0.45, 0.55), false, 1.5)
	if show_title:
		draw_string(UITheme.bold(), Vector2(8, 20), Nav.map_name(_map_id), HORIZONTAL_ALIGNMENT_LEFT, size.x - 16, 18, Color(1.0, 0.86, 0.55))
	draw_texture_rect(_tex, Rect2(_origin(), _map_px), false)
	var wf: Wayfinder = world.get("wayfinder")
	var goal_exit: Dictionary = wf.target.get("exit", {}) if wf else {}
	for e: Dictionary in Nav.exits(_map_id):
		var is_goal: bool = not goal_exit.is_empty() and e.at == goal_exit.at and str(e.to) == str(goal_exit.to)
		if not GameState.check(e.cond) or (bool(e.get("event", false)) and not is_goal):
			continue
		var col := Color(1.0, 0.78, 0.25) if is_goal else Color(0.55, 0.85, 1.0)
		draw_rect(Rect2(_to_px(Vector2(e.at)), Vector2(int(e.w), int(e.h)) * _tile), col)
	for nid: String in world.npcs.keys():
		var a: FieldActor = world.npcs[nid]
		draw_circle(_to_px(Vector2(a.grid_pos) + Vector2(0.5, 0.5)), maxf(1.5, _tile * 0.32), Color(0.95, 0.9, 0.75))
	if wf:
		var gt: Variant = wf.goal_tile()
		if gt != null:
			var c := _to_px(Vector2(gt as Vector2i) + Vector2(0.5, 0.5))
			var r := maxf(3.5, _tile * 0.7) * (1.0 + 0.15 * sin(_t * 5.0))
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), Color(1.0, 0.8, 0.3))
			draw_polyline(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0), c + Vector2(0, -r)]), Color(0.2, 0.1, 0.0), 1.0)
	if world.player:
		var p: FieldActor = world.player
		var c2 := _to_px(Vector2(p.grid_pos) + Vector2(0.5, 0.5))
		var f := Vector2(FieldActor.facing_vec(p.facing))
		var side := Vector2(-f.y, f.x)
		var r2 := maxf(4.0, _tile * 0.75)
		var tri := PackedVector2Array([c2 + f * r2, c2 - f * r2 * 0.6 + side * r2 * 0.7, c2 - f * r2 * 0.6 - side * r2 * 0.7])
		draw_colored_polygon(tri, Color(1, 1, 1))
		draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color(0.1, 0.05, 0.15), 1.2)
