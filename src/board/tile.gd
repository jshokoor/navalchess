class_name Tile
extends Area2D

signal tile_clicked(grid_pos: Vector2i)

const CELL_SIZE := 64

enum FogState {
	VISIBLE,
	SCOUTED,
	HIDDEN
}

enum CaptureState {
	NONE,
	NEUTRAL,
	PLAYER,
	ENEMY,
	CONTESTED
}

var grid_pos:       Vector2i
var fog_state:      FogState     = FogState.HIDDEN
var capture_state:  CaptureState = CaptureState.NONE
var is_highlighted: bool = false
var is_hovered:     bool = false
var is_player_side: bool = false

# ─── Colours ─────────────────────────────────────────────
const C_OCEAN        := Color(0.12, 0.32, 0.58)
const C_OCEAN_HOVER  := Color(0.18, 0.42, 0.70)
const C_GRID         := Color(0.08, 0.22, 0.45)
const C_HIGHLIGHT    := Color(1.0,  0.90, 0.2,  0.45)
const C_FOG_SCOUTED  := Color(0.04, 0.06, 0.18, 0.55)
const C_FOG_HIDDEN   := Color(0.04, 0.06, 0.18, 0.92)
const C_PLAYER_TINT  := Color(0.12, 0.36, 0.62)
const C_ENEMY_TINT   := Color(0.14, 0.28, 0.52)
const C_CAP_NEUTRAL  := Color(0.85, 0.85, 0.85, 0.18)
const C_CAP_PLAYER   := Color(0.20, 0.60, 1.00, 0.30)
const C_CAP_ENEMY    := Color(1.00, 0.25, 0.25, 0.30)
const C_CAP_CONTESTED:= Color(0.90, 0.55, 0.10, 0.38)

# ─── Drawing ─────────────────────────────────────────────
func _draw() -> void:
	var base  := C_OCEAN_HOVER if is_hovered else (C_PLAYER_TINT if is_player_side else C_ENEMY_TINT)
	var inner := Rect2(1, 1, CELL_SIZE - 2, CELL_SIZE - 2)
	var full  := Rect2(0, 0, CELL_SIZE,     CELL_SIZE)

	draw_rect(inner, base)
	draw_rect(full, C_GRID, false, 1.0)

	# Capture zone overlay
	match capture_state:
		CaptureState.NEUTRAL:   draw_rect(inner, C_CAP_NEUTRAL)
		CaptureState.PLAYER:    draw_rect(inner, C_CAP_PLAYER)
		CaptureState.ENEMY:     draw_rect(inner, C_CAP_ENEMY)
		CaptureState.CONTESTED: draw_rect(inner, C_CAP_CONTESTED)

	if is_highlighted:
		draw_rect(inner, C_HIGHLIGHT)

	match fog_state:
		FogState.SCOUTED:
			draw_rect(full, C_FOG_SCOUTED)
		FogState.HIDDEN:
			draw_rect(full, C_FOG_HIDDEN)
			draw_rect(Rect2(28, 24, 8, 6),  Color(0.3, 0.3, 0.5, 0.4))
			draw_rect(Rect2(30, 34, 4, 10), Color(0.3, 0.3, 0.5, 0.4))

# ─── State setters ───────────────────────────────────────
func set_fog_state(state: FogState) -> void:
	fog_state = state
	queue_redraw()

func set_highlighted(on: bool) -> void:
	is_highlighted = on
	queue_redraw()

func set_player_side(is_player: bool) -> void:
	is_player_side = is_player
	queue_redraw()

func set_capture_state(state: CaptureState) -> void:
	capture_state = state
	queue_redraw()

# ─── Input ───────────────────────────────────────────────
func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tile_clicked.emit(grid_pos)

func _on_mouse_entered() -> void:
	is_hovered = true
	queue_redraw()

func _on_mouse_exited() -> void:
	is_hovered = false
	queue_redraw()
