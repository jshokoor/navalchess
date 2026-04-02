class_name Submarine
extends Ship

@export var torpedo_range: int   = 7
var is_submerged:         bool   = true

signal torpedo_fired(from_tile: Vector2i, to_tile: Vector2i)

func _ready() -> void:
	ship_type  = ShipType.SUBMARINE
	turn_mode  = TurnMode.TURN
	move_range = 1          # One tile per turn — slow and deliberate
	max_crew   = 60.0
	ship_color = Color(0.22, 0.68, 0.38)
	draw_size  = Vector2(14, 30)
	super._ready()

# ─── Override: adjacent tiles only, orthogonal + diagonal ─
func can_move_to(target: Vector2i, board: Board) -> bool:
	if has_acted_this_turn:
		return false
	var delta := target - grid_pos
	return (abs(delta.x) <= 1 and abs(delta.y) <= 1
	        and target != grid_pos
	        and board.is_in_bounds(target))

func get_valid_moves(board: Board) -> Array[Vector2i]:
	var moves: Array[Vector2i] = []
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var t := grid_pos + Vector2i(dx, dy)
			if can_move_to(t, board):
				moves.append(t)
	return moves

# ─── Torpedo ─────────────────────────────────────────────
func fire_torpedo(target: Vector2i) -> Dictionary:
	if has_acted_this_turn:
		return { "success": false, "reason": "already_acted" }
	var dist := (Vector2(target) - Vector2(grid_pos)).length()
	if dist > float(torpedo_range):
		return { "success": false, "reason": "out_of_range" }
	has_acted_this_turn = true
	torpedo_fired.emit(grid_pos, target)
	action_completed.emit()
	return { "success": true, "damage": 60, "target": target }

# ─── Submersion toggle ───────────────────────────────────
func toggle_submerge() -> void:
	is_submerged = not is_submerged
	# Submerged subs are harder to detect — represented visually by lower alpha
	modulate.a = 0.5 if is_submerged else 1.0

# ─── Draw — periscope indicator when submerged ───────────
func _draw() -> void:
	super._draw()
	if is_submerged:
		var top := -draw_size.y * 0.5
		draw_line(Vector2(0, top), Vector2(0, top - 10), Color(0.5, 0.9, 0.5), 2.0)
		draw_circle(Vector2(0, top - 12), 2.5, Color(0.5, 0.9, 0.5))
