extends TestCase
## Model loading fallbacks, animation loop setup and the head-twitch tell.


func test_missing_models_fall_back_to_placeholders_with_a_head() -> void:
	var employee := CharacterModel.instantiate("res://does/not/exist.glb", CharacterModel.Placeholder.EMPLOYEE, "RITA")
	var monster := CharacterModel.instantiate("", CharacterModel.Placeholder.MONSTER)
	assert_true(employee.find_child("Head", true, false) != null, "employee placeholder head")
	assert_true(monster.find_child("Head", true, false) != null, "monster placeholder head")
	var badge := employee.find_children("*", "Label3D", true, false)
	assert_eq(badge.size(), 1)
	assert_eq((badge[0] as Label3D).text, "RITA")
	employee.free()
	monster.free()


func test_loop_modes_set_in_code() -> void:
	var holder := Node3D.new()
	var player := AnimationPlayer.new()
	holder.add_child(player)
	var library := AnimationLibrary.new()
	for anim_name in [Catalog.ANIM_IDLE, Catalog.ANIM_WALK, Catalog.ANIM_RUN, Catalog.ANIM_WORK, Catalog.ANIM_ATTACK, Catalog.ANIM_REVEAL]:
		var animation := Animation.new()
		animation.length = 1.0
		library.add_animation(anim_name, animation)
	player.add_animation_library(&"", library)
	assert_eq(CharacterModel.find_animation_player(holder), player, "found recursively")
	CharacterModel.setup_loops(player)
	for anim_name in [Catalog.ANIM_IDLE, Catalog.ANIM_WALK, Catalog.ANIM_RUN, Catalog.ANIM_WORK]:
		assert_eq(player.get_animation(anim_name).loop_mode, Animation.LOOP_LINEAR, String(anim_name))
	for anim_name in [Catalog.ANIM_ATTACK, Catalog.ANIM_REVEAL]:
		assert_eq(player.get_animation(anim_name).loop_mode, Animation.LOOP_NONE, String(anim_name))
	holder.free()


func test_locomotion_matches_clip_ground_speed() -> void:
	# [clip, speed_scale] such that speed_scale x ground speed == the body's speed: no foot sliding.
	var chase := CharacterModel.locomotion(&"monster", Monster.CHASE_SPEED)
	assert_eq(chase[0], Catalog.ANIM_RUN)
	assert_near(chase[1], Monster.CHASE_SPEED / 3.98, 0.001)
	var winded := CharacterModel.locomotion(&"monster", Monster.WINDED_SPEED)
	assert_eq(winded[0], Catalog.ANIM_WALK)
	assert_near(winded[1], Monster.WINDED_SPEED / 1.14, 0.001)
	var search := CharacterModel.locomotion(&"monster", Monster.SEARCH_SPEED)
	assert_eq(search[0], Catalog.ANIM_RUN, "3 m/s is closer to the monster's lurching run")
	var disguised := CharacterModel.locomotion(&"employee", Monster.DISGUISED_SPEED)
	assert_eq(disguised[0], Catalog.ANIM_WALK)
	assert_near(disguised[1], Monster.DISGUISED_SPEED / 2.14, 0.001)
	var walker := CharacterModel.locomotion(&"employee", Coworker.WALK_SPEED)
	assert_near(walker[1], disguised[1], 0.001, "the disguise walks exactly like a coworker")
	var flee := CharacterModel.locomotion(&"employee", Coworker.FLEE_SPEED)
	assert_eq(flee[0], Catalog.ANIM_RUN)
	assert_near(flee[1], Coworker.FLEE_SPEED / 4.86, 0.001)
	assert_eq(CharacterModel.locomotion(&"employee", 0.05)[0], Catalog.ANIM_IDLE)
	assert_eq(CharacterModel.locomotion(&"manager", 3.0)[0], Catalog.ANIM_WALK, "no run clip")


func test_head_twitch_rotates_the_head_bone() -> void:
	var skeleton := Skeleton3D.new()
	skeleton.add_bone("neck")
	var head := skeleton.add_bone("head")
	skeleton.set_bone_parent(head, 0)
	var twitch := HeadTwitch.new()
	skeleton.add_child(twitch)
	tree.root.add_child(skeleton)
	await tree.process_frame
	await tree.process_frame
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	assert_true(twitch.has_head_bone())
	# Modifier results only exist while the skeleton updates; read them there.
	var seen: Array[Quaternion] = []
	skeleton.skeleton_updated.connect(func() -> void: seen.append(skeleton.get_bone_global_pose(head).basis.get_rotation_quaternion()))
	await tree.process_frame
	var rest: Quaternion = seen.back() if not seen.is_empty() else Quaternion.IDENTITY
	twitch.twitch(40.0, 0.5, rng)
	await tree.process_frame
	await tree.process_frame
	assert_true(seen.size() >= 2, "skeleton updated")
	var angle := rad_to_deg(rest.angle_to(seen.back()))
	assert_near(angle, 40.0, 1.0, "head snapped 40 degrees")
	skeleton.free()
