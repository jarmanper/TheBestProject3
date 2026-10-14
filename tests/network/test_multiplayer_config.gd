extends TestCase
## Configuration tests are independent of the browser-only WebRTC classes, so
## they also protect the GitHub Actions headless run.

const MultiplayerConfigData := preload("res://systems/network/multiplayer_config.gd")


func _config(data: Dictionary) -> Variant:
	var config: Variant = MultiplayerConfigData.new()
	config.apply_dictionary(data)
	return config


func test_accepts_secure_signaling_with_stun_and_turn() -> void:
	var config: Variant = _config({
		"signaling_url": "wss://signal.example.com",
		"max_players": 4,
		"ice_servers": [
			{"urls": "stun:stun.example.com:3478"},
			{
				"urls": ["turns:turn.example.com:5349?transport=tcp"],
				"username": "crew",
				"credential": "temporary-token",
			},
		],
	})
	assert_true(config.is_ready())
	assert_eq(config.max_players, 4)
	assert_eq(config.webrtc_options().iceServers.size(), 2)


func test_rejects_insecure_signaling() -> void:
	var config: Variant = _config({
		"signaling_url": "ws://signal.example.com",
		"ice_servers": [{"urls": "stun:stun.example.com:3478"}],
	})
	assert_false(config.is_ready())
	assert_true(config.validation_error.contains("wss://"))


func test_requires_turn_credentials() -> void:
	var config: Variant = _config({
		"signaling_url": "wss://signal.example.com",
		"ice_servers": [
			{"urls": "stun:stun.example.com:3478"},
			{"urls": "turns:turn.example.com:5349?transport=tcp"},
		],
	})
	assert_false(config.is_ready())
	assert_true(config.validation_error.contains("TURN requires"))
