extends RefCounted
## Validated, export-safe WebRTC connection settings. The generated production
## file is intentionally ignored: every browser can read a Web export's PCK.

const PATH := "res://config/multiplayer.json"
const DEFAULT_MAX_PLAYERS := 4

var signaling_url := ""
var ice_servers: Array[Dictionary] = []
var max_players := DEFAULT_MAX_PLAYERS
var validation_error := ""


func load_config(path := PATH) -> void:
	if not FileAccess.file_exists(path):
		validation_error = "Online play has not been configured for this build."
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		validation_error = "Online play configuration is not valid JSON."
		return
	apply_dictionary(parsed)


func apply_dictionary(data: Dictionary) -> void:
	signaling_url = String(data.get("signaling_url", "")).strip_edges()
	max_players = clampi(int(data.get("max_players", DEFAULT_MAX_PLAYERS)), 2, 8)
	ice_servers.clear()
	validation_error = ""
	var raw_servers: Variant = data.get("ice_servers", [])
	if raw_servers is Array:
		for raw_server: Variant in raw_servers:
			if not raw_server is Dictionary:
				continue
			var urls: Array[String] = []
			var raw_urls: Variant = raw_server.get("urls", [])
			if raw_urls is String:
				urls.append(raw_urls)
			elif raw_urls is Array:
				for url: Variant in raw_urls:
					if url is String and not String(url).strip_edges().is_empty():
						urls.append(String(url).strip_edges())
			if urls.is_empty():
				continue
			var server: Dictionary = {"urls": urls}
			var username := String(raw_server.get("username", "")).strip_edges()
			var credential := String(raw_server.get("credential", ""))
			if not username.is_empty():
				server["username"] = username
			if not credential.is_empty():
				server["credential"] = credential
			ice_servers.append(server)
	_validate()


func is_ready() -> bool:
	return validation_error.is_empty()


func webrtc_options() -> Dictionary:
	return {"iceServers": ice_servers}


func _validate() -> void:
	if not signaling_url.begins_with("wss://"):
		validation_error = "The signaling URL must use wss://."
		return
	if ice_servers.is_empty():
		validation_error = "At least one STUN or TURN server is required."
		return
	var has_turn := false
	for server in ice_servers:
		for url: String in server.get("urls", []):
			if url.begins_with("turn:") or url.begins_with("turns:"):
				has_turn = true
				if String(server.get("username", "")).is_empty() or String(server.get("credential", "")).is_empty():
					validation_error = "TURN requires a username and credential."
					return
	if not has_turn:
		validation_error = "A TURN server is required for reliable online play."
