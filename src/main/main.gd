extends Node2D

# ─── Scene refs ──────────────────────────────────────────
@onready var board:        Board       = $Board
@onready var turn_manager: TurnManager = $TurnManager
@onready var fog_manager:  FogManager  = $FogManager

# UI
@onready var lbl_phase:   Label  = $UI/TopBar/PhaseLabel
@onready var lbl_turn:    Label  = $UI/TopBar/TurnLabel
@onready var btn_end:     Button = $UI/TopBar/EndPhaseButton
@onready var lbl_info:    Label  = $UI/SidePanel/InfoLabel
@onready var lbl_hint:    Label  = $UI/SidePanel/HintLabel

# ─── Ship scenes ─────────────────────────────────────────
var _frigate_scene:      PackedScene = preload("res://src/ships/Frigate.tscn")
var _battlecruiser_scene: PackedScene = preload("res://src/ships/Battlecruiser.tscn")
var _submarine_scene:    PackedScene = preload("res://src/ships/Submarine.tscn")

# ─── State ───────────────────────────────────────────────
var selected_ship: Ship = null
var all_ships:     Array[Ship] = []

# ═════════════════════════════════════════════════════════
func _ready() -> void:
	fog_manager.setup(board)
	_spawn_fleets()

	board.tile_selected.connect(_on_tile_selected)
	turn_manager.phase_changed.connect(_on_phase_changed)
	turn_manager.turn_advanced.connect(_on_turn_advanced)
	btn_end.pressed.connect(_on_end_phase_pressed)

	_refresh_ui()

# ─── Fleet spawning ──────────────────────────────────────
func _spawn_fleets() -> void:
	# Player fleet — left half (x 0-7)
	_spawn(frigate_s(),      Vector2i(2, 2),  true)
	_spawn(frigate_s(),      Vector2i(3, 7),  true)
	_spawn(battlecruiser_s(), Vector2i(1, 5), true)
	_spawn(submarine_s(),    Vector2i(4, 4),  true)

	# Enemy fleet — right half (x 8-15)
	_spawn(frigate_s(),      Vector2i(13, 2),  false)
	_spawn(frigate_s(),      Vector2i(12, 7),  false)
	_spawn(battlecruiser_s(), Vector2i(14, 5), false)
	_spawn(submarine_s(),    Vector2i(11, 4),  false)

func frigate_s()       -> PackedScene: return _frigate_scene
func battlecruiser_s() -> PackedScene: return _battlecruiser_scene
func submarine_s()     -> PackedScene: return _submarine_scene

func _spawn(scene: PackedScene, gp: Vector2i, is_player: bool) -> Ship:
	var ship: Ship = scene.instantiate()
	ship.is_player_owned = is_player
	board.add_child(ship)
	ship.setup(gp, board)
	turn_manager.register_ship(ship)
	all_ships.append(ship)

	if ship is Battlecruiser and is_player:
		(ship as Battlecruiser).recon_report_received.connect(_on_recon_report)

	return ship

# ─── Tile click handler ──────────────────────────────────
func _on_tile_selected(gp: Vector2i) -> void:
	if not turn_manager.is_player_turn():
		return

	var ship_here := _ship_at(gp)

	# ── Nothing selected ──────────────────────────────────
	if selected_ship == null:
		if ship_here != null and ship_here.is_player_owned:
			_select(ship_here)
		return

	# ── Clicked self → deselect ───────────────────────────
	if ship_here == selected_ship:
		_deselect()
		return

	# ── Battlecruiser recon: click enemy tile ─────────────
	if selected_ship is Battlecruiser and not board.is_player_half(gp):
		var bc := selected_ship as Battlecruiser
		if bc.can_launch_aircraft():
			bc.launch_recon(gp, turn_manager.turn_number, board)
			lbl_hint.text = "✈  Aircraft dispatched to (%d,%d) — intel arrives in 2 turns." % [gp.x, gp.y]
			_deselect()
			_refresh_ui()
			return
		else:
			lbl_hint.text = "No aircraft available or already acted this turn."
			return

	# ── Try to move selected ship ─────────────────────────
	if _try_move(gp):
		_deselect()
		_refresh_ui()
		return

	# ── Click a different friendly ship ───────────────────
	_deselect()
	if ship_here != null and ship_here.is_player_owned:
		_select(ship_here)

# ─── Selection ───────────────────────────────────────────
func _select(ship: Ship) -> void:
	selected_ship = ship
	ship.select()

	if ship is Battlecruiser:
		# Highlight enemy half as potential recon targets
		if (ship as Battlecruiser).can_launch_aircraft():
			var targets: Array[Vector2i] = []
			for gp: Vector2i in board.tiles:
				if not board.is_player_half(gp):
					targets.append(gp)
			board.highlight_tiles(targets)
			lbl_hint.text = "Click any enemy tile to dispatch recon aircraft."
		else:
			lbl_hint.text = "No aircraft available — wait for them to return."
	elif ship is Submarine:
		board.highlight_tiles(ship.get_valid_moves(board))
		lbl_hint.text = "Submarine: 1 tile per turn. Only moves in Command Phase."
	else:
		board.highlight_tiles(ship.get_valid_moves(board))
		lbl_hint.text = "Frigate: click a highlighted tile to move."

	_update_info_panel(ship)

func _deselect() -> void:
	if selected_ship != null:
		selected_ship.deselect()
		selected_ship = null
	board.clear_highlights()
	lbl_info.text = ""
	lbl_hint.text = ""

# ─── Movement ────────────────────────────────────────────
func _try_move(target: Vector2i) -> bool:
	if selected_ship == null:
		return false
	if _ship_at(target) != null:
		lbl_hint.text = "That tile is occupied."
		return false

	# TURN-mode ships can only move during Command Phase
	if selected_ship.turn_mode == Ship.TurnMode.TURN:
		if not turn_manager.can_turn_ship_act():
			lbl_hint.text = "Press 'End Free Phase' first to give commands to this ship."
			return false

	if not selected_ship.can_move_to(target, board):
		lbl_hint.text = "Cannot move there — out of range or already acted."
		return false

	selected_ship.move_to(target, board)
	return true

# ─── Recon intel callback ────────────────────────────────
func _on_recon_report(scouted_tiles: Array[Vector2i], turn_dispatched: int) -> void:
	fog_manager.reveal_tiles(scouted_tiles, turn_manager.turn_number)
	var age := turn_manager.turn_number - turn_dispatched
	lbl_hint.text = "📡  Intel received! Positions are %d turn(s) old — enemy may have moved." % age

# ─── Turn events ─────────────────────────────────────────
func _on_phase_changed(_phase: TurnManager.Phase) -> void:
	_deselect()
	_refresh_ui()

func _on_turn_advanced(turn_num: int) -> void:
	fog_manager.decay_fog(turn_num)
	# Process returning aircraft for all battlecruisers
	for ship in all_ships:
		if ship is Battlecruiser:
			(ship as Battlecruiser).process_turn(turn_num)
	_refresh_ui()

func _on_end_phase_pressed() -> void:
	_deselect()
	match turn_manager.current_phase:
		TurnManager.Phase.PLAYER_FREE: turn_manager.end_player_free_phase()
		TurnManager.Phase.PLAYER_TURN: turn_manager.end_player_turn()

# ─── UI ──────────────────────────────────────────────────
func _refresh_ui() -> void:
	lbl_phase.text = turn_manager.get_phase_label()
	lbl_turn.text  = "Turn  %d" % turn_manager.turn_number

	match turn_manager.current_phase:
		TurnManager.Phase.PLAYER_FREE:
			btn_end.text = "End Free Phase  →"
			btn_end.disabled = false
		TurnManager.Phase.PLAYER_TURN:
			btn_end.text = "End Command Phase  →"
			btn_end.disabled = false
		_:
			btn_end.text = "…"
			btn_end.disabled = true

func _update_info_panel(ship: Ship) -> void:
	var type_name: String
	match ship.ship_type:
		Ship.ShipType.FRIGATE:       type_name = "⛵  Frigate"
		Ship.ShipType.BATTLECRUISER: type_name = "🚢  Battlecruiser"
		Ship.ShipType.SUBMARINE:     type_name = "🤿  Submarine"
		_:                           type_name = "Ship"

	var crew_pct := int((ship.crew / ship.max_crew) * 100)
	var lines := [
		type_name,
		"Crew: %d / %d  (%d%%)" % [int(ship.crew), int(ship.max_crew), crew_pct],
		"Position: (%d, %d)" % [ship.grid_pos.x, ship.grid_pos.y],
		"Turn mode: %s" % ("Free" if ship.turn_mode == Ship.TurnMode.FREE else "Turn"),
	]

	if ship is Battlecruiser:
		var bc := ship as Battlecruiser
		lines.append("Aircraft ready: %d / %d" % [bc.aircraft_ready, bc.max_aircraft])
		lines.append("Missions in flight: %d" % bc.missions_in_flight.size())
	elif ship is Submarine:
		var sub := ship as Submarine
		lines.append("Submerged: %s" % ("Yes" if sub.is_submerged else "No"))
		lines.append("Torpedo range: %d" % sub.torpedo_range)
	elif ship is Frigate:
		var f := ship as Frigate
		lines.append("Cannon range: %d" % f.cannon_range)
		lines.append("Crew / move: %.0f" % f.crew_per_tile)

	lbl_info.text = "\n".join(lines)

# ─── Helpers ─────────────────────────────────────────────
func _ship_at(gp: Vector2i) -> Ship:
	for ship in all_ships:
		if ship.grid_pos == gp:
			return ship
	return null
