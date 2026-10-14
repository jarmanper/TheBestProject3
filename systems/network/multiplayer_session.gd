extends Node
## Browser WebRTC lobby client. The signaling server only creates rooms and
## relays SDP/ICE; gameplay packets travel peer-to-peer through WebRTC.

signal status_changed(text: String)
signal lobby_updated(lobby_code: String, members: Array[Dictionary], host_peer_id: int)
signal connection_failed(reason: String)
signal match_started

const PROTOCOL_VERSION := 1
const MultiplayerConfigData := preload("res://systems/network/multiplayer_config.gd")

enum State { OFFLINE, CONNECTING, IN_LOBBY, MATCH_READY }

var config: Variant = MultiplayerConfigData.new()
var state := State.OFFLINE
var local_peer_id := 0
var host_peer_id := 0
var lobby_code := ""

var _socket: WebSocketPeer
var _pending_request: Dictionary = {}
var _members: Array[Dictionary] = []
var _connections: Dictionary[int, Object] = {}
var _mesh: MultiplayerPeer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	refresh_configuration()


func _process(_delta: float) -> void:
	if _socket == null:
		return
	_socket.poll()
	var socket_state := _socket.get_ready_state()
	if state == State.CONNECTING:
		if socket_state == WebSocketPeer.STATE_OPEN:
			state = State.IN_LOBBY
			_send(_pending_request)
			_pending_request.clear()
			_set_status("Connected to lobby service.")
		elif socket_state == WebSocketPeer.STATE_CLOSED:
			_fatal_fail("Could not connect to the lobby service.")
			return
	if socket_state != WebSocketPeer.STATE_OPEN:
		return
	while _socket.get_available_packet_count() > 0:
		var payload: Variant = JSON.parse_string(_socket.get_packet().get_string_from_utf8())
		if payload is Dictionary:
			_handle_message(payload)


func refresh_configuration() -> void:
	config = MultiplayerConfigData.new()
	config.load_config()
	if not config.is_ready():
		_set_status(config.validation_error)


func is_configured() -> bool:
	return config.is_ready()


func configuration_error() -> String:
	return config.validation_error


func members() -> Array[Dictionary]:
	return _members.duplicate(true)


func is_host() -> bool:
	return local_peer_id != 0 and local_peer_id == host_peer_id


func create_lobby(display_name: String) -> void:
	_begin({"type": "create", "name": _clean_name(display_name), "protocol": PROTOCOL_VERSION})


func join_lobby(code: String, display_name: String) -> void:
	_begin({
		"type": "join",
		"lobby": code.strip_edges().to_upper(),
		"name": _clean_name(display_name),
		"protocol": PROTOCOL_VERSION,
	})


func set_ready(ready: bool) -> void:
	if state < State.IN_LOBBY or local_peer_id == 0:
		return
	_send({"type": "ready", "ready": ready})


func start_match() -> void:
	if not is_host():
		_report_error("Only the lobby host can start the shift.")
		return
	_send({"type": "start"})


func leave_lobby() -> void:
	if _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_send({"type": "leave"})
		_socket.close()
	_socket = null
	_reset_transport()
	_members.clear()
	lobby_code = ""
	local_peer_id = 0
	host_peer_id = 0
	state = State.OFFLINE
	_set_status("Online lobby closed.")


func _begin(request: Dictionary) -> void:
	leave_lobby()
	refresh_configuration()
	if not config.is_ready():
		_report_error(config.validation_error)
		return
	_pending_request = request
	_socket = WebSocketPeer.new()
	var error := _socket.connect_to_url(config.signaling_url)
	if error != OK:
		_fatal_fail("Could not open the secure lobby connection: %s" % error_string(error))
		return
	state = State.CONNECTING
	_set_status("Connecting to lobby service…")


func _handle_message(message: Dictionary) -> void:
	match String(message.get("type", "")):
		"lobby_state":
			_apply_lobby_state(message)
		"signal":
			var data: Variant = message.get("data", {})
			if data is Dictionary:
				_handle_webrtc_signal(int(message.get("from", 0)), data)
		"match_started":
			state = State.MATCH_READY
			_set_status("All peers are connected. The shift can begin.")
			match_started.emit()
		"lobby_closed":
			_fatal_fail("The host closed the lobby.")
		"error":
			_report_error(String(message.get("message", "The lobby service rejected that request.")))


func _apply_lobby_state(message: Dictionary) -> void:
	lobby_code = String(message.get("lobby", ""))
	local_peer_id = int(message.get("self", 0))
	host_peer_id = int(message.get("host", 0))
	_members.clear()
	var raw_members: Variant = message.get("members", [])
	if raw_members is Array:
		for member: Variant in raw_members:
			if member is Dictionary:
				_members.append(member)
	_sync_webrtc_mesh()
	lobby_updated.emit(lobby_code, members(), host_peer_id)
	_set_status("Lobby %s — %d/%d crew connected." % [lobby_code, _members.size(), config.max_players])


func _sync_webrtc_mesh() -> void:
	if local_peer_id <= 0 or not ClassDB.class_exists(&"WebRTCMultiplayerPeer") or not ClassDB.class_exists(&"WebRTCPeerConnection"):
		return
	if _mesh == null:
		var candidate: Object = ClassDB.instantiate(&"WebRTCMultiplayerPeer")
		if not candidate is MultiplayerPeer:
			_fatal_fail("This build does not include the WebRTC transport.")
			return
		_mesh = candidate as MultiplayerPeer
		var create_error: int = _mesh.call(&"create_mesh", local_peer_id)
		if create_error != OK:
			_fatal_fail("Could not initialize WebRTC: %s" % error_string(create_error))
			return
		multiplayer.multiplayer_peer = _mesh
	var active_peer_ids: Dictionary[int, bool] = {}
	for member in _members:
		var peer_id: int = int(member.get("id", 0))
		if peer_id <= 0 or peer_id == local_peer_id:
			continue
		active_peer_ids[peer_id] = true
		# The lower ID offers, so every pair negotiates exactly once.
		if local_peer_id < peer_id and not _connections.has(peer_id):
			var connection := _make_connection(peer_id)
			if connection != null:
				connection.call(&"create_offer")
	for peer_id in _connections.keys():
		if not active_peer_ids.has(peer_id):
			_mesh.call(&"remove_peer", peer_id)
			_connections.erase(peer_id)


func _make_connection(peer_id: int) -> Object:
	if _connections.has(peer_id):
		return _connections[peer_id]
	var connection: Object = ClassDB.instantiate(&"WebRTCPeerConnection")
	if connection == null:
		_fatal_fail("This build does not include WebRTCPeerConnection.")
		return null
	var initialize_error: int = connection.call(&"initialize", config.webrtc_options())
	if initialize_error != OK:
		_fatal_fail("Could not configure ICE servers: %s" % error_string(initialize_error))
		return null
	connection.connect(&"session_description_created", _on_session_description_created.bind(peer_id))
	connection.connect(&"ice_candidate_created", _on_ice_candidate_created.bind(peer_id))
	var add_error: int = _mesh.call(&"add_peer", connection, peer_id)
	if add_error != OK:
		_fatal_fail("Could not add WebRTC peer: %s" % error_string(add_error))
		return null
	_connections[peer_id] = connection
	return connection


func _handle_webrtc_signal(from_peer: int, data: Dictionary) -> void:
	if from_peer <= 0 or from_peer == local_peer_id:
		return
	var kind := String(data.get("kind", ""))
	var connection := _connections.get(from_peer) as Object
	if connection == null and kind == "offer":
		connection = _make_connection(from_peer)
	if connection == null:
		return
	match kind:
		"offer":
			connection.call(&"set_remote_description", "offer", String(data.get("sdp", "")))
			connection.call(&"create_answer")
		"answer":
			connection.call(&"set_remote_description", "answer", String(data.get("sdp", "")))
		"candidate":
			connection.call(&"add_ice_candidate", String(data.get("media", "")), int(data.get("index", 0)), String(data.get("candidate", "")))


func _on_session_description_created(kind: String, sdp: String, peer_id: int) -> void:
	var connection := _connections.get(peer_id) as Object
	if connection == null:
		return
	connection.call(&"set_local_description", kind, sdp)
	_send_webrtc_signal(peer_id, {"kind": kind, "sdp": sdp})


func _on_ice_candidate_created(media: String, index: int, candidate: String, peer_id: int) -> void:
	_send_webrtc_signal(peer_id, {"kind": "candidate", "media": media, "index": index, "candidate": candidate})


func _send_webrtc_signal(peer_id: int, data: Dictionary) -> void:
	_send({"type": "signal", "to": peer_id, "data": data})


func _send(message: Dictionary) -> void:
	if _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.send_text(JSON.stringify(message))


func _reset_transport() -> void:
	if _mesh != null:
		_mesh.call(&"close")
		if multiplayer.multiplayer_peer == _mesh:
			multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_mesh = null
	_connections.clear()


func _clean_name(value: String) -> String:
	var cleaned := value.strip_edges().substr(0, 20)
	return cleaned if not cleaned.is_empty() else "Night Crew"


func _set_status(text: String) -> void:
	status_changed.emit(text)


func _report_error(reason: String) -> void:
	_set_status(reason)
	connection_failed.emit(reason)


func _fatal_fail(reason: String) -> void:
	if _socket != null:
		_socket.close()
	_socket = null
	_reset_transport()
	_members.clear()
	lobby_code = ""
	local_peer_id = 0
	host_peer_id = 0
	state = State.OFFLINE
	_report_error(reason)
