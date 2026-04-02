class_name FogManager
extends Node

# After this many turns without new recon, scouted tiles revert to HIDDEN.
const FOG_DECAY_TURNS := 3

var board: Board
# Tracks last turn each enemy tile was scouted.  Vector2i → turn number
var last_scouted: Dictionary = {}

# ─── Init ────────────────────────────────────────────────
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

# ─── Reveal ──────────────────────────────────────────────
## Called when an aircraft returns with intelligence.
func reveal_tiles(positions: Array[Vector2i], current_turn: int) -> void:
	for gp in positions:
		var t := board.get_tile(gp)
		if t == null:
			continue
		if not board.is_player_half(gp):
			t.set_fog_state(Tile.FogState.SCOUTED)
			last_scouted[gp] = current_turn

## Mark a tile as fully visible (used for player-side tiles and immediate detection).
func mark_visible(gp: Vector2i) -> void:
	var t := board.get_tile(gp)
	if t:
		t.set_fog_state(Tile.FogState.VISIBLE)

# ─── Decay ───────────────────────────────────────────────
## Called each turn. Scouted tiles that are old enough fade back to HIDDEN.
func decay_fog(current_turn: int) -> void:
	for gp: Vector2i in last_scouted:
		var age: int = current_turn - last_scouted[gp]
		var t := board.get_tile(gp)
		if t == null:
			continue
		if age >= FOG_DECAY_TURNS:
			t.set_fog_state(Tile.FogState.HIDDEN)
		# else stays SCOUTED — partial intel still shown

# ─── Query ───────────────────────────────────────────────
func is_tile_visible(gp: Vector2i) -> bool:
	var t := board.get_tile(gp)
	if t == null:
		return false
	return t.fog_state == Tile.FogState.VISIBLE

func is_tile_known(gp: Vector2i) -> bool:
	var t := board.get_tile(gp)
	if t == null:
		return false
	return t.fog_state != Tile.FogState.HIDDEN
