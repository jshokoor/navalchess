class_name Frigate
extends Ship

@export var cannon_range:  int   = 3
@export var crew_per_tile: float = 4.0

const TOW_CREW_COST: float = 15.0

func _ready() -> void:
	ship_type  = ShipType.FRIGATE
	turn_mode  = TurnMode.FREE
	move_range = 3
	max_crew   = 80.0
	ship_color = Color(0.20, 0.55, 0.95)
	draw_size  = Vector2(18, 34)
	super._ready()

# ─── Movement (crew-gated, not turn-locked) ──────────────
func can_move_to(target: Vector2i, board: Board) -> bool:
	if not board.is_in_bounds(target):
		return false
	var dist := (Vector2(target) - Vector2(grid_pos)).length()
	if dist > float(move_range):
		return false
	return can_spend_crew(dist * crew_per_tile)

func move_to(target: Vector2i, board: Board) -> void:
	var dist := (Vector2(target) - Vector2(grid_pos)).length()
	spend_crew(dist * crew_per_tile)
	grid_pos = target
	position  = board.grid_to_world(target)
	action_completed.emit()
	queue_redraw()

# ─── Tow API ─────────────────────────────────────────────
## Returns true if this frigate is adjacent to a friendly Battlecruiser
## and has enough crew to tow it.
func can_tow(bc: Battlecruiser) -> bool:
	var delta := bc.grid_pos - grid_pos
	var adjacent = abs(delta.x) <= 1 and abs(delta.y) <= 1 and delta != Vector2i.ZERO
	return adjacent and can_spend_crew(TOW_CREW_COST) and not bc.has_acted_this_turn

## Execute the tow: spend crew, move the Battlecruiser one tile.
func tow(bc: Battlecruiser, target: Vector2i, board: Board) -> void:
	spend_crew(TOW_CREW_COST)
	bc.tow_to(target, board)
	has_acted_this_turn = true
	action_completed.emit()
	queue_redraw()

# ─── Combat ──────────────────────────────────────────────
func fire_cannons(target: Vector2i) -> Dictionary:
	var dist := (Vector2(target) - Vector2(grid_pos)).length()
	if dist > cannon_range:
		return { "success": false, "reason": "out_of_range" }
	return { "success": true, "damage": 20, "target": target }
