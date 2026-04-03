class_name Battlecruiser
extends Ship

# ─── Aircraft state ──────────────────────────────────────
var max_aircraft:       int  = 3
var aircraft_ready:     int  = 3
var missions_in_flight: Array = []

# Tow state — set by Frigate when it initiates a tow
var is_being_towed: bool = false

signal recon_report_received(scouted_tiles: Array[Vector2i], turn_dispatched: int)

func _ready() -> void:
	ship_type  = ShipType.BATTLECRUISER
	turn_mode  = TurnMode.TURN
	move_range = 0
	max_crew   = 200.0
	ship_color = Color(0.85, 0.52, 0.08)
	draw_size  = Vector2(34, 50)
	super._ready()

# ─── Cannot self-move ────────────────────────────────────
func can_move_to(_target: Vector2i, _board: Board) -> bool:
	return false

func get_valid_moves(_board: Board) -> Array[Vector2i]:
	return []

# ─── Tow API (called by Frigate) ─────────────────────────
## Returns the valid tiles a towing Frigate can drag this ship to.
## One tile in any direction from current position.
func get_tow_destinations(board: Board) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var t := grid_pos + Vector2i(dx, dy)
			if board.is_in_bounds(t):
				result.append(t)
	return result

## Move the battlecruiser to a new tile — called by Frigate after spending crew.
func tow_to(target: Vector2i, board: Board) -> void:
	grid_pos = target
	position  = board.grid_to_world(target)
	has_acted_this_turn = true
	is_being_towed = false
	action_completed.emit()
	queue_redraw()

# ─── Aircraft API ────────────────────────────────────────
func can_launch_aircraft() -> bool:
	return aircraft_ready > 0 and not has_acted_this_turn

func launch_recon(target_zone: Vector2i, current_turn: int, _board: Board) -> bool:
	const FLIGHT_TURNS := 2
	if not can_launch_aircraft():
		return false
	aircraft_ready     -= 1
	has_acted_this_turn = true
	missions_in_flight.append({
		"target":          target_zone,
		"dispatched_turn": current_turn,
		"return_turn":     current_turn + FLIGHT_TURNS,
	})
	action_completed.emit()
	queue_redraw()
	return true

func process_turn(current_turn: int) -> void:
	var returned := missions_in_flight.filter(func(m): return current_turn >= m["return_turn"])
	for mission in returned:
		missions_in_flight.erase(mission)
		aircraft_ready += 1
		recon_report_received.emit(_scouted_tiles(mission["target"]), mission["dispatched_turn"])
	if returned.size() > 0:
		queue_redraw()

func _scouted_tiles(center: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			result.append(center + Vector2i(dx, dy))
	return result

# ─── Draw ────────────────────────────────────────────────
func _draw() -> void:
	super._draw()
	for i in range(max_aircraft):
		var is_available := i < aircraft_ready
		var col   := Color(0.9, 0.9, 0.2) if is_available else Color(0.3, 0.3, 0.3, 0.5)
		var px    := -float(max_aircraft - 1) * 5.0 * 0.5 + i * 10.0
		draw_circle(Vector2(px, -draw_size.y * 0.5 - 10), 4.0, col)

	# Tow indicator
	if is_being_towed:
		draw_rect(Rect2(-draw_size.x * 0.5 - 4, -draw_size.y * 0.5 - 4,
						draw_size.x + 8, draw_size.y + 8),
				  Color(0.2, 1.0, 0.6, 0.6), false, 3.0)
