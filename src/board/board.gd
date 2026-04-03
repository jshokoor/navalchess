class_name Board
extends Node2D

signal tile_selected(grid_pos: Vector2i)

const GRID_W    := 16
const GRID_H    := 10
const CELL_SIZE := 64
const HALF_W    := 8

# 2x2 capture zone in the dead centre of the board
# Grid centre x: 16/2 = 8 → tiles 7 and 8
# Grid centre y: 10/2 = 5 → tiles 4 and 5
const CAPTURE_ZONE: Array[Vector2i] = [
	Vector2i(7, 4), Vector2i(8, 4),
	Vector2i(7, 5), Vector2i(8, 5),
]

var tile_scene: PackedScene = preload("res://src/board/Tile.tscn")
var tiles: Dictionary = {}   # Vector2i -> Tile

# ─── Setup ───────────────────────────────────────────────
func _ready() -> void:
	_build_grid()

func _build_grid() -> void:
	for y in range(GRID_H):
		for x in range(GRID_W):
			var t: Tile = tile_scene.instantiate()
			var gp := Vector2i(x, y)
			t.grid_pos = gp
			t.position  = Vector2(x * CELL_SIZE, y * CELL_SIZE)
			t.set_player_side(x < HALF_W)
			if gp in CAPTURE_ZONE:
				t.set_capture_state(Tile.CaptureState.NEUTRAL)
			t.tile_clicked.connect(_on_tile_clicked)
			add_child(t)
			tiles[gp] = t

# ─── Dividing line ───────────────────────────────────────
func _draw() -> void:
	var x := float(HALF_W * CELL_SIZE)
	var h := float(GRID_H * CELL_SIZE)
	draw_line(Vector2(x, 0), Vector2(x, h), Color(1.0, 0.55, 0.1, 0.5), 3.0)

# ─── Signal relay ────────────────────────────────────────
func _on_tile_clicked(gp: Vector2i) -> void:
	tile_selected.emit(gp)

# ─── Grid API ────────────────────────────────────────────
func get_tile(gp: Vector2i) -> Tile:
	return tiles.get(gp, null)

func is_in_bounds(gp: Vector2i) -> bool:
	return gp.x >= 0 and gp.x < GRID_W and gp.y >= 0 and gp.y < GRID_H

func is_player_half(gp: Vector2i) -> bool:
	return gp.x < HALF_W

func is_capture_zone(gp: Vector2i) -> bool:
	return gp in CAPTURE_ZONE

func grid_to_world(gp: Vector2i) -> Vector2:
	return Vector2(gp.x * CELL_SIZE + CELL_SIZE * 0.5,
				   gp.y * CELL_SIZE + CELL_SIZE * 0.5)

func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(world_pos.x / CELL_SIZE), int(world_pos.y / CELL_SIZE))

# ─── Highlight API ───────────────────────────────────────
func highlight_tiles(positions: Array[Vector2i]) -> void:
	clear_highlights()
	for gp in positions:
		var t := get_tile(gp)
		if t:
			t.set_highlighted(true)

func clear_highlights() -> void:
	for gp in tiles:
		tiles[gp].set_highlighted(false)

# ─── Capture zone visual update ──────────────────────────
func set_capture_visuals(state: Tile.CaptureState) -> void:
	for gp in CAPTURE_ZONE:
		var t := get_tile(gp)
		if t:
			t.set_capture_state(state)
