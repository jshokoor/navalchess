class_name Battlecruiser
extends Ship

# ─── Aircraft state ──────────────────────────────────────
var max_aircraft:      int = 3
var aircraft_ready:    int = 3
var missions_in_flight: Array = []   # Array of mission Dictionaries

# Emitted when a recon aircraft returns with intelligence.
# scouted_tiles: the grid positions observed
# turn_dispatched: which turn the aircraft left — tells the player how stale the data is
signal recon_report_received(scouted_tiles: Array[Vector2i], turn_dispatched: int)

func _ready() -> void:
	ship_type  = ShipType.BATTLECRUISER
	turn_mode  = TurnMode.TURN
	move_range = 0          # Stationary — deploys once, anchors in place
	max_crew   = 200.0
	ship_color = Color(0.85, 0.52, 0.08)
	draw_size  = Vector2(34, 50)
	super._ready()

# ─── Override: cannot move ───────────────────────────────
func can_move_to(_target: Vector2i, _board: Board) -> bool:
	return false

func get_valid_moves(_board: Board) -> Array[Vector2i]:
	return []

# ─── Aircraft API ────────────────────────────────────────
func can_launch_aircraft() -> bool:
	return aircraft_ready > 0 and not has_acted_this_turn

## Dispatch a recon aircraft to a target zone on the enemy half.
## The aircraft will return after FLIGHT_TURNS turns and emit recon_report_received.
func launch_recon(target_zone: Vector2i, current_turn: int, _board: Board) -> bool:
	const FLIGHT_TURNS := 2

	if not can_launch_aircraft():
		return false

	aircraft_ready    -= 1
	has_acted_this_turn = true

	missions_in_flight.append({
		"target":         target_zone,
		"dispatched_turn": current_turn,
		"return_turn":    current_turn + FLIGHT_TURNS,
	})

	action_completed.emit()
	queue_redraw()
	return true

## Called by main each turn to check for returning aircraft.
func process_turn(current_turn: int) -> void:
	var returned := missions_in_flight.filter(func(m): return current_turn >= m["return_turn"])
	for mission in returned:
		missions_in_flight.erase(mission)
		aircraft_ready += 1
		var scouted := _scouted_tiles(mission["target"])
		recon_report_received.emit(scouted, mission["dispatched_turn"])
	if returned.size() > 0:
		queue_redraw()

func _scouted_tiles(center: Vector2i) -> Array[Vector2i]:
	# Aircraft reveals a 3×3 area around the target tile.
	var result: Array[Vector2i] = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			result.append(center + Vector2i(dx, dy))
	return result

# ─── Draw — show aircraft availability ───────────────────
func _draw() -> void:
	super._draw()
	# Small aircraft readiness dots above the ship
	for i in range(max_aircraft):
		var ready := i < aircraft_ready
		var col   := Color(0.9, 0.9, 0.2) if ready else Color(0.3, 0.3, 0.3, 0.5)
		var px    := -float(max_aircraft - 1) * 5.0 * 0.5 + i * 10.0
		draw_circle(Vector2(px, -draw_size.y * 0.5 - 10), 4.0, col)
