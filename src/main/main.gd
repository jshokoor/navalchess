extends Node2D

# ─── Scene refs ──────────────────────────────────────────
@onready var board:        Board       = $Board
@onready var turn_manager: TurnManager = $TurnManager
@onready var fog_manager:  FogManager  = $FogManager
@onready var koth_manager: KothManager = $KothManager

# UI
@onready var lbl_phase:  Label  = $UI/TopBar/PhaseLabel
@onready var lbl_turn:   Label  = $UI/TopBar/TurnLabel
@onready var btn_end:    Button = $UI/TopBar/EndPhaseButton
@onready var lbl_info:   Label  = $UI/SidePanel/InfoLabel
@onready var lbl_hint:   Label  = $UI/SidePanel/HintLabel
@onready var lbl_zone:   Label  = $UI/SidePanel/ZoneLabel

# ─── Ship scenes ─────────────────────────────────────────
var _frigate_scene:       PackedScene = preload("res://src/ships/Frigate.tscn")
var _battlecruiser_scene: PackedScene = preload("res://src/ships/Battlecruiser.tscn")
var _submarine_scene:     PackedScene = preload("res://src/ships/Submarine.tscn")

# ─── State ───────────────────────────────────────────────
var selected_ship:  Ship         = null
var tow_source:     Frigate      = null
var tow_target_bc:  Battlecruiser = null
var is_tow_mode:    bool         = false
var all_ships:      Array[Ship]  = []

# Ships are always spawned in this fixed order so both peers share the same indices:
# 0-3 = host fleet (left side)   4-7 = client fleet (right side)
# HOST  → ships[0-3] are is_player_owned=true
# CLIENT→ ships[4-7] are is_player_owned=true
const HOST_SPAWNS: Array = [
	{ "scene": "frigate",       "pos": Vector2i(2, 2) },
	{ "scene": "frigate",       "pos": Vector2i(3, 7) },
	{ "scene": "battlecruiser", "pos": Vector2i(1, 5) },
	{ "scene": "submarine",     "pos": Vector2i(4, 4) },
]
const CLIENT_SPAWNS: Array = [
	{ "scene": "frigate",       "pos": Vector2i(13, 2) },
	{ "scene": "frigate",       "pos": Vector2i(12, 7) },
	{ "scene": "battlecruiser", "pos": Vector2i(14, 5) },
	{ "scene": "submarine",     "pos": Vector2i(11, 4) },
]

# ═════════════════════════════════════════════════════════
func _ready() -> void:
	fog_manager.setup(board)
	koth_manager.setup(board)
	_spawn_fleets()

	board.tile_selected.connect(_on_tile_selected)
	turn_manager.phase_changed.connect(_on_phase_changed)
	turn_manager.turn_advanced.connect(_on_turn_advanced)
	koth_manager.zone_control_changed.connect(_on_zone_changed)
	koth_manager.game_won.connect(_on_game_won)
	btn_end.pressed.connect(_on_end_phase_pressed)

	if NetworkManager.is_online:
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	_refresh_ui()

# ─── Fleet spawning ──────────────────────────────────────
func _spawn_fleets() -> void:
	var i_am_host := NetworkManager.is_host or not NetworkManager.is_online

	# Spawn host fleet first (indices 0-3), then client fleet (indices 4-7)
	for entry in HOST_SPAWNS:
		_spawn(_scene_for(entry["scene"]), entry["pos"], i_am_host)
	for entry in CLIENT_SPAWNS:
		_spawn(_scene_for(entry["scene"]), entry["pos"], not i_am_host)

func _scene_for(ship_name: String) -> PackedScene:
	match ship_name:
		"frigate":       return _frigate_scene
		"battlecruiser": return _battlecruiser_scene
		"submarine":     return _submarine_scene
	return _frigate_scene

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

# ─── Can this client interact right now? ─────────────────
func _i_can_act() -> bool:
	if not NetworkManager.is_online:
		return true
	return NetworkManager.is_my_turn_phase(turn_manager.current_phase)

# ─── Tile click handler ──────────────────────────────────
func _on_tile_selected(gp: Vector2i) -> void:
	if not _i_can_act():
		lbl_hint.text = "Waiting for opponent…"
		return

	if is_tow_mode:
		_resolve_tow(gp)
		return

	var ship_here := _ship_at(gp)

	if selected_ship == null:
		if ship_here != null and ship_here.is_player_owned:
			_select(ship_here)
		return

	if ship_here == selected_ship:
		_deselect()
		return

	# Frigate → adjacent Battlecruiser: enter tow mode
	if selected_ship is Frigate and ship_here is Battlecruiser and ship_here.is_player_owned:
		var f  := selected_ship as Frigate
		var bc := ship_here as Battlecruiser
		if f.can_tow(bc):
			_enter_tow_mode(f, bc)
		else:
			lbl_hint.text = "Can't tow: not adjacent, not enough crew, or BC already acted."
		return

	# Battlecruiser → enemy tile: recon launch
	if selected_ship is Battlecruiser and not board.is_player_half(gp) == selected_ship.is_player_owned:
		var bc := selected_ship as Battlecruiser
		if turn_manager.can_turn_ship_act() and bc.can_launch_aircraft():
			var ship_idx := all_ships.find(bc)
			rpc("_net_launch_recon", ship_idx, gp, turn_manager.turn_number)
			_do_launch_recon(ship_idx, gp, turn_manager.turn_number)
			_deselect()
			_refresh_ui()
		elif not turn_manager.can_turn_ship_act():
			lbl_hint.text = "End Free Phase first."
		else:
			lbl_hint.text = "No aircraft available."
		return

	# Try move
	if _try_move_local(gp):
		fog_manager.update_ship_visibility(all_ships)
		_deselect()
		_refresh_ui()
		return

	_deselect()
	if ship_here != null and ship_here.is_player_owned:
		_select(ship_here)

# ═════════════════════════════════════════════════════════
# RPC LAYER — every mutating action has a net_ version
# that the local machine calls on itself AND sends to peer.
# ═════════════════════════════════════════════════════════

# ─── Move ────────────────────────────────────────────────
func _try_move_local(target: Vector2i) -> bool:
	if selected_ship == null:
		return false
	if _ship_at(target) != null:
		lbl_hint.text = "That tile is occupied."
		return false
	if selected_ship.turn_mode == Ship.TurnMode.TURN and not turn_manager.can_turn_ship_act():
		lbl_hint.text = "End Free Phase first."
		return false
	if not selected_ship.can_move_to(target, board):
		lbl_hint.text = "Can't move there."
		return false

	var idx := all_ships.find(selected_ship)
	rpc("_net_move_ship", idx, target)
	_do_move_ship(idx, target)
	return true

@rpc("any_peer", "reliable")
func _net_move_ship(ship_idx: int, target: Vector2i) -> void:
	# Called on the remote peer — skip if we already executed it locally
	if multiplayer.get_remote_sender_id() != 0:
		_do_move_ship(ship_idx, target)
		fog_manager.update_ship_visibility(all_ships)
		_refresh_ui()

func _do_move_ship(ship_idx: int, target: Vector2i) -> void:
	var ship := all_ships[ship_idx]
	ship.move_to(target, board)

# ─── Tow ─────────────────────────────────────────────────
func _enter_tow_mode(f: Frigate, bc: Battlecruiser) -> void:
	tow_source    = f
	tow_target_bc = bc
	is_tow_mode   = true
	bc.is_being_towed = true
	bc.queue_redraw()
	board.highlight_tiles(bc.get_tow_destinations(board))
	lbl_hint.text = "Tow mode: click a tile to drag the Battlecruiser there."

func _resolve_tow(gp: Vector2i) -> void:
	var valid := tow_target_bc.get_tow_destinations(board)
	if gp in valid and _ship_at(gp) == null:
		var f_idx  := all_ships.find(tow_source)
		var bc_idx := all_ships.find(tow_target_bc)
		rpc("_net_tow", f_idx, bc_idx, gp)
		_do_tow(f_idx, bc_idx, gp)
		fog_manager.update_ship_visibility(all_ships)
		lbl_hint.text = "Battlecruiser towed to (%d,%d)." % [gp.x, gp.y]
	else:
		tow_target_bc.is_being_towed = false
		tow_target_bc.queue_redraw()
		lbl_hint.text = "Tow cancelled."
	_exit_tow_mode()

@rpc("any_peer", "reliable")
func _net_tow(f_idx: int, bc_idx: int, target: Vector2i) -> void:
	if multiplayer.get_remote_sender_id() != 0:
		_do_tow(f_idx, bc_idx, target)
		fog_manager.update_ship_visibility(all_ships)
		_refresh_ui()

func _do_tow(f_idx: int, bc_idx: int, target: Vector2i) -> void:
	var f  := all_ships[f_idx]  as Frigate
	var bc := all_ships[bc_idx] as Battlecruiser
	f.tow(bc, target, board)

func _exit_tow_mode() -> void:
	is_tow_mode   = false
	tow_source    = null
	tow_target_bc = null
	_deselect()
	_refresh_ui()

# ─── Recon ───────────────────────────────────────────────
@rpc("any_peer", "reliable")
func _net_launch_recon(ship_idx: int, target: Vector2i, turn_num: int) -> void:
	if multiplayer.get_remote_sender_id() != 0:
		_do_launch_recon(ship_idx, target, turn_num)
		_refresh_ui()

func _do_launch_recon(ship_idx: int, target: Vector2i, turn_num: int) -> void:
	var bc := all_ships[ship_idx] as Battlecruiser
	bc.launch_recon(target, turn_num, board)

# ─── Phase transitions ───────────────────────────────────
func _on_end_phase_pressed() -> void:
	_deselect()
	var phase := turn_manager.current_phase
	rpc("_net_end_phase", phase)
	_do_end_phase(phase)

@rpc("any_peer", "reliable")
func _net_end_phase(phase: int) -> void:
	if multiplayer.get_remote_sender_id() != 0:
		_do_end_phase(phase)

func _do_end_phase(phase: int) -> void:
	match phase:
		TurnManager.Phase.PLAYER_FREE: turn_manager.end_player_free_phase()
		TurnManager.Phase.PLAYER_TURN: turn_manager.end_player_turn()
		# ENEMY_TURN is the client's "player turn" from their perspective —
		# the TurnManager on the host calls end_enemy_turn which advances
		# the turn counter and resets ships. We mirror that here.
		TurnManager.Phase.ENEMY_TURN:  turn_manager.end_player_turn()

# ─── Recon callback ──────────────────────────────────────
func _on_recon_report(scouted_tiles: Array[Vector2i], turn_dispatched: int) -> void:
	fog_manager.reveal_tiles(scouted_tiles, turn_manager.turn_number)
	var age := turn_manager.turn_number - turn_dispatched
	lbl_hint.text = "📡  Intel received! Data is %d turn(s) old." % age

# ─── Turn events ─────────────────────────────────────────
func _on_phase_changed(_phase: TurnManager.Phase) -> void:
	_deselect()
	_refresh_ui()

func _on_turn_advanced(turn_num: int) -> void:
	fog_manager.decay_fog(turn_num)
	fog_manager.update_ship_visibility(all_ships)
	for ship in all_ships:
		if ship is Battlecruiser:
			(ship as Battlecruiser).process_turn(turn_num)
	koth_manager.evaluate(all_ships)
	_refresh_ui()

# ─── Zone / Win ──────────────────────────────────────────
func _on_zone_changed(_side: String, _progress: int) -> void:
	lbl_zone.text = koth_manager.get_status_text()

func _on_game_won(side: String) -> void:
	var i_am_host  := NetworkManager.is_host or not NetworkManager.is_online
	var i_won      := (side == "player" and i_am_host) or (side == "enemy" and not i_am_host)
	lbl_hint.text  = "🏆  YOU WIN!" if i_won else "💀  OPPONENT WINS"
	btn_end.disabled = true

# ─── Disconnect ──────────────────────────────────────────
func _on_peer_disconnected(_id: int) -> void:
	lbl_hint.text = "⚠️  Opponent disconnected."
	btn_end.disabled = true

# ─── Selection ───────────────────────────────────────────
func _select(ship: Ship) -> void:
	selected_ship = ship
	ship.select()

	if ship is Battlecruiser:
		var bc := ship as Battlecruiser
		if turn_manager.can_turn_ship_act() and bc.can_launch_aircraft():
			var targets: Array[Vector2i] = []
			for gp: Vector2i in board.tiles:
				if board.is_player_half(gp) != ship.is_player_owned:
					targets.append(gp)
			board.highlight_tiles(targets)
			lbl_hint.text = "Click enemy tile for recon, or click adjacent Frigate to be towed."
		else:
			lbl_hint.text = "No aircraft / not Command Phase.  A Frigate can tow this ship."
	elif ship is Frigate:
		board.highlight_tiles(ship.get_valid_moves(board))
		lbl_hint.text = "Click to move.  Click an adjacent friendly Battlecruiser to tow it."
	elif ship is Submarine:
		if turn_manager.can_turn_ship_act():
			board.highlight_tiles(ship.get_valid_moves(board))
			lbl_hint.text = "Submarine: 1 tile per turn."
		else:
			lbl_hint.text = "Submarine acts in Command Phase."
	_update_info_panel(ship)

func _deselect() -> void:
	if selected_ship:
		selected_ship.deselect()
		selected_ship = null
	board.clear_highlights()
	lbl_info.text = ""
	lbl_hint.text = ""

# ─── UI ──────────────────────────────────────────────────
func _refresh_ui() -> void:
	lbl_phase.text = turn_manager.get_phase_label()
	lbl_turn.text  = "Turn  %d" % turn_manager.turn_number
	lbl_zone.text  = koth_manager.get_status_text()

	var my_turn := _i_can_act()
	match turn_manager.current_phase:
		TurnManager.Phase.PLAYER_FREE:
			btn_end.text     = "End Free Phase  →"
			btn_end.disabled = not my_turn
		TurnManager.Phase.PLAYER_TURN:
			btn_end.text     = "End Command Phase  →"
			btn_end.disabled = not my_turn
		TurnManager.Phase.ENEMY_TURN:
			btn_end.text     = "End Your Turn  →"
			btn_end.disabled = not my_turn
		_:
			btn_end.text     = "…"
			btn_end.disabled = true

func _update_info_panel(ship: Ship) -> void:
	var type_name: String
	match ship.ship_type:
		Ship.ShipType.FRIGATE:       type_name = "⛵  Frigate"
		Ship.ShipType.BATTLECRUISER: type_name = "🚢  Battlecruiser"
		Ship.ShipType.SUBMARINE:     type_name = "🤿  Submarine"
		_:                           type_name = "Ship"

	var pct  := int((ship.crew / ship.max_crew) * 100)
	var lines := [
		type_name,
		"Crew: %d / %d  (%d%%)" % [int(ship.crew), int(ship.max_crew), pct],
		"Pos: (%d, %d)" % [ship.grid_pos.x, ship.grid_pos.y],
		"Capture weight: %d" % KothManager.WEIGHT.get(ship.ship_type, 1),
	]
	if ship is Battlecruiser:
		var bc := ship as Battlecruiser
		lines.append("Aircraft: %d / %d" % [bc.aircraft_ready, bc.max_aircraft])
		lines.append("In flight: %d" % bc.missions_in_flight.size())
	elif ship is Submarine:
		lines.append("Torpedo range: %d" % (ship as Submarine).torpedo_range)
	elif ship is Frigate:
		lines.append("Tow cost: 15 crew")
	lbl_info.text = "\n".join(lines)

# ─── Helpers ─────────────────────────────────────────────
func _ship_at(gp: Vector2i) -> Ship:
	for ship in all_ships:
		if ship.grid_pos == gp:
			return ship
	return null
