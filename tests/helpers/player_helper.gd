extends RefCounted
## Shared helper for Store Environment / Manager tests that need a Player.
## Player (systems/player/player.gd) uses @onready scene nodes (CollisionShape3D,
## Head/Camera3D/Flashlight, Head/Camera3D/Viewmodel), so tests must instantiate the
## real player.tscn rather than Player.new(). Not a test file (no "test_" prefix),
## so tests/run_tests.gd does not try to run it.

const PLAYER_SCENE := "res://systems/player/player.tscn"


## Instantiates the real player scene, adds it under `tree.root`, and returns it.
static func make_player(tree: SceneTree) -> Player:
	var player: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	tree.root.add_child(player)
	return player
