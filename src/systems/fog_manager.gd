class_name FogManager
extends Node

const FOG_DECAY_TURNS := 3

var board: Board
var last_scouted: Dictionary = {}

func setup(b: Board) -> void:
	board = b
	for gp: Vector2i in board.tiles:
		var t := board.get_tile(gp)
		if t == null:
			continue
		if board.is_player_half(gp):
			t.set_fog_state(Tile.FogState.VISIBLE)
		else:
			t.set_fog_state(Tile.FogState.HIDDEN)

# ─── Recon reveal ────────────────────────────────────────
func reveal_tiles(positions: Array[Vector2i], current_turn: int) -> void:
	for gp in positions:
		var t := board.get_tile(gp)
		if t == null:
			continue
		if not board.is_player_half(gp):
			t.set_fog_state(Tile.FogState.SCOUTED)
			last_scouted[gp] = current_turn

func mark_visible(gp: Vector2i) -> void:
	var t := board.get_tile(gp)
	if t:
		t.set_fog_state(Tile.FogState.VISIBLE)

# ─── Crossing detection ──────────────────────────────────
## Call after any ship moves.  Enemy ships in the player's half become
## visible; enemy ships back in their own half return to hidden (unless scouted).
func update_ship_visibility(all_ships: Array[Ship]) -> void:
	for ship in all_ships:
		if ship.is_player_owned:
			continue
		var t := board.get_tile(ship.grid_pos)
		if t == null:
			continue
		if board.is_player_half(ship.grid_pos):
			# Enemy crossed into player territory — always visible
			t.set_fog_state(Tile.FogState.VISIBLE)
		else:
			# Back in their half — restore scouted/hidden based on last recon
			if ship.grid_pos in last_scouted:
				t.set_fog_state(Tile.FogState.SCOUTED)
			else:
				t.set_fog_state(Tile.FogState.HIDDEN)

# ─── Decay ───────────────────────────────────────────────
func decay_fog(current_turn: int) -> void:
	for gp: Vector2i in last_scouted:
		var age: int = current_turn - last_scouted[gp]
		var t := board.get_tile(gp)
		if t == null:
			continue
		if age >= FOG_DECAY_TURNS and not board.is_player_half(gp):
			t.set_fog_state(Tile.FogState.HIDDEN)

# ─── Queries ─────────────────────────────────────────────
func is_tile_visible(gp: Vector2i) -> bool:
	var t := board.get_tile(gp)
	return t != null and t.fog_state == Tile.FogState.VISIBLE

func is_tile_known(gp: Vector2i) -> bool:
	var t := board.get_tile(gp)
	return t != null and t.fog_state != Tile.FogState.HIDDEN
