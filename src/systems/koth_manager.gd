class_name KothManager
extends Node

# Turns a side must hold the zone (majority weight) to win
const HOLD_TURNS_TO_WIN := 3

# Capture weight per ship type
const WEIGHT := {
	Ship.ShipType.FRIGATE:       1,
	Ship.ShipType.BATTLECRUISER: 3,
	Ship.ShipType.SUBMARINE:     2,
}

signal zone_control_changed(controlling_side: String, hold_progress: int)
signal game_won(winning_side: String)

var board: Board

var player_hold_turns: int = 0
var enemy_hold_turns:  int = 0
var last_controller:   String = "none"  # "player", "enemy", "contested", "none"

func setup(b: Board) -> void:
	board = b

# ─── Called each turn end ────────────────────────────────
func evaluate(all_ships: Array[Ship]) -> void:
	var player_weight := 0
	var enemy_weight  := 0

	for ship in all_ships:
		if not board.is_capture_zone(ship.grid_pos):
			continue
		var w: int = WEIGHT.get(ship.ship_type, 1)
		if ship.is_player_owned:
			player_weight += w
		else:
			enemy_weight  += w

	var controller := _resolve_controller(player_weight, enemy_weight)
	_update_hold(controller)
	_update_visuals(controller)
	zone_control_changed.emit(controller, _hold_progress(controller))

	# Win check
	if player_hold_turns >= HOLD_TURNS_TO_WIN:
		game_won.emit("player")
	elif enemy_hold_turns >= HOLD_TURNS_TO_WIN:
		game_won.emit("enemy")

func _resolve_controller(pw: int, ew: int) -> String:
	if pw == 0 and ew == 0: return "none"
	if pw > ew:             return "player"
	if ew > pw:             return "enemy"
	return "contested"

func _update_hold(controller: String) -> void:
	if controller == "player":
		player_hold_turns += 1
		enemy_hold_turns   = 0
	elif controller == "enemy":
		enemy_hold_turns  += 1
		player_hold_turns  = 0
	else:
		# Contested or empty — neither side advances
		pass
	last_controller = controller

func _hold_progress(controller: String) -> int:
	if controller == "player": return player_hold_turns
	if controller == "enemy":  return enemy_hold_turns
	return 0

func _update_visuals(controller: String) -> void:
	var state: Tile.CaptureState
	match controller:
		"player":    state = Tile.CaptureState.PLAYER
		"enemy":     state = Tile.CaptureState.ENEMY
		"contested": state = Tile.CaptureState.CONTESTED
		_:           state = Tile.CaptureState.NEUTRAL
	board.set_capture_visuals(state)

func get_status_text() -> String:
	match last_controller:
		"player":
			return "🔵  Zone held by you  —  %d / %d turns" % [player_hold_turns, HOLD_TURNS_TO_WIN]
		"enemy":
			return "🔴  Zone held by enemy  —  %d / %d turns" % [enemy_hold_turns, HOLD_TURNS_TO_WIN]
		"contested":
			return "⚔️  Zone contested!"
		_:
			return "⬜  Zone uncontrolled"
