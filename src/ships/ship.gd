class_name Ship
extends Node2D

signal action_completed

# ─── Enums ───────────────────────────────────────────────
enum ShipType   { FRIGATE, BATTLECRUISER, SUBMARINE }
enum TurnMode   { FREE, TURN }  # FREE = acts outside turn clock; TURN = waits its phase

# ─── Stats (overridden by subclasses) ────────────────────
@export var ship_type:   ShipType = ShipType.FRIGATE
@export var turn_mode:   TurnMode = TurnMode.TURN
@export var max_crew:    float    = 100.0
@export var move_range:  int      = 3
@export var is_player_owned: bool = true

var crew:               float
var grid_pos:           Vector2i
var has_acted_this_turn: bool = false

# ─── Visual config (set by subclasses) ───────────────────
var ship_color:  Color   = Color.WHITE
var draw_size:   Vector2 = Vector2(20, 36)
var is_selected: bool    = false

# ─── Ready ───────────────────────────────────────────────
func _ready() -> void:
	crew = max_crew
	queue_redraw()

func setup(gp: Vector2i, board: Board) -> void:
	grid_pos = gp
	position  = board.grid_to_world(gp)
	queue_redraw()

# ─── Drawing ─────────────────────────────────────────────
func _draw() -> void:
	var c := ship_color.lightened(0.25) if is_selected else ship_color
	var half := draw_size * 0.5
	var r    := Rect2(-half, draw_size)

	draw_rect(r, c)

	# Ownership outline
	var outline := Color.CYAN if is_player_owned else Color(1.0, 0.3, 0.3)
	draw_rect(r, outline, false, 2.0)

	# Forward indicator — small triangle at top
	var tip := Vector2(0, -half.y - 5)
	var bl  := Vector2(-5, -half.y)
	var br  := Vector2( 5, -half.y)
	draw_colored_polygon(PackedVector2Array([tip, bl, br]), outline)

	# Crew pip bar at bottom
	var pips    := int((crew / max_crew) * 5.0)
	var pip_col := Color(0.2, 0.9, 0.3) if crew / max_crew > 0.4 else Color(0.9, 0.5, 0.1)
	for i in range(5):
		var px := -half.x + 2 + i * 6
		var pc := pip_col if i < pips else Color(0.2, 0.2, 0.2, 0.5)
		draw_rect(Rect2(px, half.y + 3, 5, 3), pc)

# ─── Crew API ────────────────────────────────────────────
func can_spend_crew(cost: float) -> bool:
	return crew >= cost

func spend_crew(amount: float) -> void:
	crew = max(0.0, crew - amount)
	queue_redraw()

func add_crew(amount: float) -> void:
	crew = min(max_crew, crew + amount)
	queue_redraw()

# ─── Movement ────────────────────────────────────────────
func can_move_to(target: Vector2i, board: Board) -> bool:
	if has_acted_this_turn and turn_mode == TurnMode.TURN:
		return false
	var dist: float = (Vector2(target) - Vector2(grid_pos)).length()
	return dist <= float(move_range) and board.is_in_bounds(target)

func move_to(target: Vector2i, board: Board) -> void:
	grid_pos = target
	position  = board.grid_to_world(target)
	has_acted_this_turn = true
	action_completed.emit()
	queue_redraw()

func get_valid_moves(board: Board) -> Array[Vector2i]:
	var moves: Array[Vector2i] = []
	for x in range(-move_range, move_range + 1):
		for y in range(-move_range, move_range + 1):
			var t := grid_pos + Vector2i(x, y)
			if t != grid_pos and can_move_to(t, board):
				moves.append(t)
	return moves

# ─── Turn lifecycle ───────────────────────────────────────
func start_turn() -> void:
	has_acted_this_turn = false

# ─── Selection visuals ───────────────────────────────────
func select() -> void:
	is_selected = true
	queue_redraw()

func deselect() -> void:
	is_selected = false
	queue_redraw()
