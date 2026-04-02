class_name TurnManager
extends Node

# ─── Turn phases ─────────────────────────────────────────
# PLAYER_FREE  — Frigates (TurnMode.FREE) may move without restriction.
#                TURN ships (Battlecruiser, Submarine) cannot act yet.
# PLAYER_TURN  — TURN ships may each act once. Frigates may still move.
# ENEMY_TURN   — Reserved for enemy AI resolution.
# RESOLVING    — Placeholder for animations, torpedo travel, etc.
enum Phase { PLAYER_FREE, PLAYER_TURN, ENEMY_TURN, RESOLVING }

signal phase_changed(new_phase: Phase)
signal turn_advanced(turn_number: int)

var current_phase: Phase = Phase.PLAYER_FREE
var turn_number:   int   = 1

var player_ships: Array[Ship] = []
var enemy_ships:  Array[Ship] = []

func _ready() -> void:
	print("TurnManager ready — Turn 1, Player Free Phase")

# ─── Ship registry ───────────────────────────────────────
func register_ship(ship: Ship) -> void:
	if ship.is_player_owned:
		player_ships.append(ship)
	else:
		enemy_ships.append(ship)

# ─── Phase transitions ───────────────────────────────────
func end_player_free_phase() -> void:
	current_phase = Phase.PLAYER_TURN
	phase_changed.emit(current_phase)
	print("Phase → PLAYER_TURN")

func end_player_turn() -> void:
	_run_enemy_turn()

func _run_enemy_turn() -> void:
	current_phase = Phase.ENEMY_TURN
	phase_changed.emit(current_phase)
	print("Phase → ENEMY_TURN")
	# TODO: enemy AI acts here — for now auto-resolves
	_end_enemy_turn()

func _end_enemy_turn() -> void:
	turn_number += 1
	_reset_all_ships()
	turn_advanced.emit(turn_number)
	current_phase = Phase.PLAYER_FREE
	phase_changed.emit(current_phase)
	print("Turn %d — Player Free Phase" % turn_number)

func _reset_all_ships() -> void:
	for ship in player_ships + enemy_ships:
		ship.start_turn()

# ─── Queries ─────────────────────────────────────────────
func is_player_turn() -> bool:
	return current_phase == Phase.PLAYER_FREE or current_phase == Phase.PLAYER_TURN

func get_phase_label() -> String:
	match current_phase:
		Phase.PLAYER_FREE: return "Free Phase  —  Frigates may move"
		Phase.PLAYER_TURN: return "Command Phase  —  All ships may act"
		Phase.ENEMY_TURN:  return "Enemy Turn"
		Phase.RESOLVING:   return "Resolving…"
	return ""

func can_turn_ship_act() -> bool:
	return current_phase == Phase.PLAYER_TURN

# ─── Debug shortcut ──────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_N:
		print("DEBUG: Force advance turn")
		match current_phase:
			Phase.PLAYER_FREE: end_player_free_phase()
			Phase.PLAYER_TURN: end_player_turn()
