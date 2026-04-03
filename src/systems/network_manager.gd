extends Node

# ─── Constants ───────────────────────────────────────────
const PORT        := 7777
const MAX_CLIENTS := 1   # Strictly 2-player

# ─── State ───────────────────────────────────────────────
var is_host:   bool = false
var is_online: bool = false   # false = local/solo debug mode

signal connection_succeeded
signal connection_failed(reason: String)
signal peer_connected
signal peer_disconnected

# ─── Host ────────────────────────────────────────────────
func host_game() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err   := peer.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		connection_failed.emit("Could not open port %d — is it already in use?" % PORT)
		return

	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	is_host   = true
	is_online = true
	print("[Net] Hosting on port %d" % PORT)

# ─── Join ────────────────────────────────────────────────
func join_game(address: String) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err   := peer.create_client(address, PORT)
	if err != OK:
		connection_failed.emit("Could not connect to %s:%d" % [address, PORT])
		return

	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	is_host   = false
	is_online = true
	print("[Net] Connecting to %s:%d …" % [address, PORT])

# ─── Local (solo / debug) ────────────────────────────────
func play_local() -> void:
	is_host   = true
	is_online = false
	print("[Net] Local mode — both sides on one machine")

# ─── Callbacks ───────────────────────────────────────────
func _on_peer_connected(id: int) -> void:
	print("[Net] Peer connected: %d" % id)
	peer_connected.emit()

func _on_peer_disconnected(id: int) -> void:
	print("[Net] Peer disconnected: %d" % id)
	peer_disconnected.emit()

func _on_connected_to_server() -> void:
	print("[Net] Connected to host.")
	connection_succeeded.emit()

func _on_connection_failed() -> void:
	print("[Net] Connection failed.")
	connection_failed.emit("Connection timed out.")

# ─── Helpers ─────────────────────────────────────────────
## True when it is this machine's ships that should be interactive.
## Host controls left fleet (player 1), client controls right fleet (player 2).
func is_my_turn_phase(phase: int) -> bool:
	if not is_online:
		return true   # Local: always interactive
	# Phase enum: PLAYER_FREE=0, PLAYER_TURN=1 → host acts
	# ENEMY_TURN=2 → client acts (from host's perspective it's enemy turn)
	if is_host:
		return phase == 0 or phase == 1
	else:
		return phase == 2
