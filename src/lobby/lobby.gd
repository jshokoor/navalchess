extends Control

@onready var btn_host:    Button      = $VBox/HostButton
@onready var btn_join:    Button      = $VBox/JoinRow/JoinButton
@onready var input_ip:    LineEdit    = $VBox/JoinRow/IPInput
@onready var btn_local:   Button      = $VBox/LocalButton
@onready var lbl_status:  Label       = $VBox/StatusLabel
@onready var spinner:     Control     = $VBox/Spinner

const MAIN_SCENE := "res://src/main/Main.tscn"

func _ready() -> void:
	spinner.hide()
	NetworkManager.connection_succeeded.connect(_on_connected)
	NetworkManager.connection_failed.connect(_on_failed)
	NetworkManager.peer_connected.connect(_on_peer_connected)

	btn_host.pressed.connect(_on_host_pressed)
	btn_join.pressed.connect(_on_join_pressed)
	btn_local.pressed.connect(_on_local_pressed)

# ─── Button handlers ─────────────────────────────────────
func _on_host_pressed() -> void:
	_set_status("Waiting for opponent to connect…")
	_set_buttons_enabled(false)
	spinner.show()
	NetworkManager.host_game()

func _on_join_pressed() -> void:
	var ip := input_ip.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	_set_status("Connecting to %s…" % ip)
	_set_buttons_enabled(false)
	spinner.show()
	NetworkManager.join_game(ip)

func _on_local_pressed() -> void:
	NetworkManager.play_local()
	get_tree().change_scene_to_file(MAIN_SCENE)

# ─── Network callbacks ───────────────────────────────────
func _on_peer_connected() -> void:
	# Host sees this when client connects
	_set_status("Opponent connected!  Starting…")
	await get_tree().create_timer(0.6).timeout
	get_tree().change_scene_to_file(MAIN_SCENE)

func _on_connected() -> void:
	# Client sees this when it successfully reaches the host
	_set_status("Connected!  Waiting for host…")

func _on_failed(reason: String) -> void:
	_set_status("❌  %s" % reason)
	_set_buttons_enabled(true)
	spinner.hide()

# ─── Helpers ─────────────────────────────────────────────
func _set_status(msg: String) -> void:
	lbl_status.text = msg

func _set_buttons_enabled(on: bool) -> void:
	btn_host.disabled  = not on
	btn_join.disabled  = not on
	btn_local.disabled = not on
