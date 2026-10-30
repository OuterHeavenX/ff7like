class_name MapGrid
extends RefCounted
## Walkability / height data for a field map. One tile = 1 world unit.
## Heights are stored in levels; one level = LEVEL world units.

const LEVEL := 0.5

var w: int = 0
var h: int = 0
var chars: PackedStringArray = []
var level: PackedInt32Array = []       # floor level per tile
var block: PackedInt32Array = []       # extra block levels above floor (walls)
var walk: PackedByteArray = []
var stair: PackedStringArray = []      # "", "^", "v", "<", ">"
var water: PackedByteArray = []
var safe: PackedByteArray = []          # no random encounters on these tiles
var legend: Dictionary = {}


func idx(x: int, y: int) -> int:
	return y * w + x


func inside(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h


func ch(x: int, y: int) -> String:
	return chars[idx(x, y)] if inside(x, y) else " "


func info(x: int, y: int) -> Dictionary:
	return legend.get(ch(x, y), legend.get(" ", {}))


func floor_level(x: int, y: int) -> int:
	return level[idx(x, y)] if inside(x, y) else -4


func top_level(x: int, y: int) -> int:
	if not inside(x, y):
		return -4
	return level[idx(x, y)] + block[idx(x, y)]


func is_walkable(x: int, y: int) -> bool:
	return inside(x, y) and walk[idx(x, y)] == 1


func stair_dir(x: int, y: int) -> String:
	return stair[idx(x, y)] if inside(x, y) else ""


## World-space height of an actor standing in the middle of tile (x, y).
func stand_height(x: int, y: int) -> float:
	if not inside(x, y):
		return 0.0
	var base := float(level[idx(x, y)]) * LEVEL
	var s := stair[idx(x, y)]
	if s != "":
		var hi := float(_stair_high(x, y)) * LEVEL
		return (base + hi) * 0.5
	return base


func _stair_high(x: int, y: int) -> int:
	var d := stair_vec(stair[idx(x, y)])
	return floor_level(x + d.x, y + d.y) if inside(x + d.x, y + d.y) else level[idx(x, y)] + 1


static func stair_vec(s: String) -> Vector2i:
	match s:
		"^": return Vector2i(0, -1)
		"v": return Vector2i(0, 1)
		"<": return Vector2i(-1, 0)
		">": return Vector2i(1, 0)
	return Vector2i.ZERO


## Static terrain check for moving from a to b (dynamic blockers handled by World).
func can_step(a: Vector2i, b: Vector2i) -> bool:
	if not is_walkable(b.x, b.y):
		return false
	var la := floor_level(a.x, a.y)
	var lb := floor_level(b.x, b.y)
	var sa := stair_dir(a.x, a.y)
	var sb := stair_dir(b.x, b.y)
	var dirv := b - a
	if sa == "" and sb == "":
		return la == lb
	# Stairs connect only along their axis.
	if sb != "":
		var v := stair_vec(sb)
		if dirv == v:
			return la == lb   # entering from the low end
		if dirv == -v:
			return la == _stair_high(b.x, b.y) or la == lb
		return la == lb and sa == sb
	var va := stair_vec(sa)
	if dirv == va:
		return lb == _stair_high(a.x, a.y)
	if dirv == -va:
		return lb == la
	return false
