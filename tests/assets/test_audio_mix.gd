extends TestCase
## autoload/sfx.gd mix and limits (MIX_DB, UNIT_SIZE, MAX_VOICES, MIN_GAP, earshot culling) and
## the store lights' rare, local natural-flicker sound (StoreLight.flicker_sound_allowed).

const FakePlayer := preload("res://tests/monster/fake_player.gd")

var world: Node3D
var started: Array[Node] = []


func before_each() -> void:
	world = Node3D.new()
	tree.root.add_child(world)
	Sfx.reset_limits()
	started.clear()


func after_each() -> void:
	for node in started:
		if is_instance_valid(node):
			node.free()
	GameState.player = null
	world.free()
	Sfx.reset_limits()


func _keep(node: Node) -> Node:
	if node:
		started.append(node)
	return node


func test_mix_table_covers_every_id() -> void:
	for id in Sfx.SOUNDS:
		assert_true(Sfx.MIX_DB.has(id), "MIX_DB has no level for %s" % id)
		var level: float = Sfx.MIX_DB.get(id, 0.0)
		assert_true(level <= 0.0 and level >= -12.0, "%s mix level %.1f dB is in -12..0" % [id, level])
	for id in Sfx.MIX_DB:
		assert_true(Sfx.SOUNDS.has(id), "MIX_DB entry %s is a known sound" % id)


func test_small_sounds_sit_below_the_monster() -> void:
	for id: StringName in [&"footstep_tile", &"light_flicker", &"amb_fluorescent_buzz", &"task_progress"]:
		assert_true(Sfx.mix_db(id) < Sfx.mix_db(&"monster_scream"), "%s sits below the monster" % id)
		assert_true(Sfx.unit_size(id) < Sfx.unit_size(&"monster_scream"), "%s carries less far than the monster" % id)


func test_play_adds_the_mix_level() -> void:
	var player := _keep(Sfx.play(&"footstep_tile", -3.0)) as AudioStreamPlayer
	assert_true(player != null, "played")
	if player:
		assert_near(player.volume_db, -3.0 + Sfx.mix_db(&"footstep_tile"))


func test_play_at_uses_mix_level_and_unit_size() -> void:
	var player := _keep(Sfx.play_at(&"box_rustle", Vector3.ZERO, -2.0)) as AudioStreamPlayer3D
	assert_true(player != null, "played")
	if player:
		assert_near(player.volume_db, -2.0 + Sfx.mix_db(&"box_rustle"))
		assert_near(player.unit_size, Sfx.unit_size(&"box_rustle"))


func test_voice_cap_drops_extra_footsteps() -> void:
	var cap: int = Sfx.MAX_VOICES[&"footstep_tile"]
	for i in cap:
		assert_true(_keep(Sfx.play(&"footstep_tile")) != null, "footstep %d plays" % i)
	assert_eq(_keep(Sfx.play(&"footstep_tile")), null, "one over the cap is dropped")
	(started[0] as Node).free()
	assert_true(_keep(Sfx.play(&"footstep_tile")) != null, "a freed voice makes room")


func test_min_gap_drops_a_second_flicker_sound() -> void:
	var first := _keep(Sfx.play_at(&"light_flicker", Vector3.ZERO))
	assert_true(first != null, "first flicker plays")
	first.free()
	assert_eq(_keep(Sfx.play_at(&"light_flicker", Vector3.ZERO)), null, "inside MIN_GAP: dropped")
	Sfx.reset_limits()
	assert_true(_keep(Sfx.play_at(&"light_flicker", Vector3.ZERO)) != null, "plays again after the gap")


func test_one_shots_beyond_earshot_are_not_started() -> void:
	var listener := FakePlayer.new()
	world.add_child(listener)
	listener.global_position = Vector3.ZERO
	assert_eq(_keep(Sfx.play_at(&"box_rustle", Vector3(20, 0, 0), 0.0, 1.0, 10.0)), null, "20 m away, 10 m range")
	assert_true(_keep(Sfx.play_at(&"box_rustle", Vector3(5, 0, 0), 0.0, 1.0, 10.0)) != null, "5 m away plays")
	assert_true(_keep(Sfx.play_at(&"task_progress", Vector3(20, 0, 0), 0.0, 1.0, 10.0)) != null,
		"loops always start (the player may walk up to them)")


func test_natural_flicker_sound_is_local() -> void:
	StoreLight.last_flicker_sound_ms = -1000000
	assert_false(StoreLight.flicker_sound_allowed(StoreLight.FLICKER_SOUND_RANGE + 1.0, 100000), "out of range: silent")
	assert_true(StoreLight.flicker_sound_allowed(StoreLight.FLICKER_SOUND_RANGE - 1.0, 100000), "in range: audible")


func test_natural_flicker_sound_has_a_store_wide_cooldown() -> void:
	StoreLight.last_flicker_sound_ms = 100000
	var cooldown_ms := int(StoreLight.FLICKER_SOUND_COOLDOWN * 1000.0)
	assert_false(StoreLight.flicker_sound_allowed(2.0, 100000 + cooldown_ms - 500), "inside the cooldown: silent")
	assert_true(StoreLight.flicker_sound_allowed(2.0, 100000 + cooldown_ms + 1), "after the cooldown: audible")
	StoreLight.last_flicker_sound_ms = -1000000
	assert_true(StoreLight.FLICKER_SOUND_COOLDOWN >= 3.0, "at most one flicker sound every few seconds")
	assert_true(StoreLight.FLICKER_SOUND_RANGE <= 10.0, "only nearby fixtures are heard")


func test_ambient_scares_are_quiet_and_far() -> void:
	assert_true(AmbientScares.VOLUME_DB <= -14.0, "quiet bed noises")
	assert_true(AmbientScares.MIN_DISTANCE >= 12.0, "never close to the player")
