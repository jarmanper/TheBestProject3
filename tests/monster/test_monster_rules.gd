extends TestCase
## Pure timer logic behind the three GDD monster rules (no physics).

var rules: MonsterRules


func before_each() -> void:
	rules = MonsterRules.new()
	rules.rng.seed = 7


# --- Rule values are the GDD/contract values ---------------------------------

func test_rule_constants_match_contract() -> void:
	assert_eq(Monster.SPRINT_MAX_TIME, 13.0)
	assert_eq(Monster.WINDED_TIME, 6.0)
	assert_eq(Monster.REVEAL_RANGE, 7.0)
	assert_eq(Monster.REVEAL_TIME, 4.0)
	assert_eq(Monster.SIGHTING_DEADLINE_HOUR, 2)
	assert_eq(Monster.MAX_ABDUCTIONS, 2)
	assert_eq(Monster.ABDUCT_EARLIEST_HOUR, 1)


# --- Rule 1: 13-second sprint, then winded for 6 s ---------------------------

func test_winded_exactly_at_thirteen_seconds_of_sprint() -> void:
	for i in 25:
		assert_false(rules.tick_sprint(0.5, true), "not winded at %.1f s" % ((i + 1) * 0.5))
	assert_true(rules.tick_sprint(0.5, true), "winded at 13.0 s")


func test_winded_at_thirteen_seconds_in_physics_frames() -> void:
	var frames := 0
	while not rules.tick_sprint(1.0 / 60.0, true):
		frames += 1
		if frames > 2000:
			break
	assert_eq(frames + 1, 780, "13 s at 60 fps")


func test_winded_recovers_after_six_seconds_with_fresh_sprint() -> void:
	for i in 26:
		rules.tick_sprint(0.5, true)
	rules.start_winded()
	assert_true(rules.is_winded())
	for i in 11:
		assert_false(rules.tick_winded(0.5), "still winded at %.1f s" % ((i + 1) * 0.5))
	assert_true(rules.tick_winded(0.5), "recovered at 6.0 s")
	assert_false(rules.is_winded())
	assert_near(rules.sprint_time, 0.0, 0.0001, "fresh sprint timer")
	# A fresh timer means another full 13 s before the next wind.
	for i in 25:
		assert_false(rules.tick_sprint(0.5, true))
	assert_true(rules.tick_sprint(0.5, true))


func test_sprint_time_recovers_when_not_sprinting() -> void:
	rules.tick_sprint(5.0, true)
	rules.tick_sprint(3.0, false)
	assert_near(rules.sprint_time, 2.0, 0.0001)
	rules.tick_sprint(10.0, false)
	assert_near(rules.sprint_time, 0.0, 0.0001, "never below zero")


# --- Rule 2: reveal after lingering in range with line of sight --------------

func test_reveal_condition_needs_range_los_and_unhidden_player() -> void:
	assert_true(MonsterRules.is_reveal_condition(5.0, true, false))
	assert_true(MonsterRules.is_reveal_condition(7.0, true, false), "edge of range counts")
	assert_false(MonsterRules.is_reveal_condition(7.5, true, false), "out of range")
	assert_false(MonsterRules.is_reveal_condition(3.0, false, false), "no line of sight")
	assert_false(MonsterRules.is_reveal_condition(3.0, true, true), "player hidden")


func test_reveal_after_four_seconds_in_range() -> void:
	for i in 39:
		assert_false(rules.tick_reveal(0.1, true), "no reveal at %.1f s" % ((i + 1) * 0.1))
	assert_true(rules.tick_reveal(0.1, true), "reveal at 4.0 s")
	assert_near(rules.reveal_progress, 0.0, 0.0001, "progress resets after triggering")


func test_no_reveal_when_condition_false() -> void:
	for i in 100:
		assert_false(rules.tick_reveal(0.1, false))
	assert_near(rules.reveal_progress, 0.0, 0.0001)


func test_reveal_progress_decays_at_half_speed() -> void:
	rules.tick_reveal(3.0, true)
	rules.tick_reveal(2.0, false)
	assert_near(rules.reveal_progress, 2.0, 0.0001, "2 s out of range removes 1 s")
	rules.tick_reveal(10.0, false)
	assert_near(rules.reveal_progress, 0.0, 0.0001)


func test_no_reveal_during_cooldown() -> void:
	rules.start_reveal_cooldown()
	assert_near(rules.reveal_cooldown_left, Monster.REVEAL_COOLDOWN, 0.0001)
	for i in 200:  # 20 s in range, still inside the 25 s cooldown
		assert_false(rules.tick_reveal(0.1, true))
	for i in 50:   # cooldown runs out at 25 s
		rules.tick_reveal(0.1, false)
	assert_true(rules.reveal_cooldown_left <= 0.0)
	var revealed := false
	for i in 41:
		revealed = rules.tick_reveal(0.1, true) or revealed
	assert_true(revealed, "reveals again once the cooldown is over")


# --- Rule 3: appears to the player at least once by 2 AM ---------------------

func test_first_view_is_a_new_sighting() -> void:
	assert_false(rules.has_been_sighted)
	assert_true(rules.update_view(true, 0.1), "first time in view")
	assert_true(rules.has_been_sighted)
	assert_false(rules.update_view(true, 0.1), "still the same sighting")


func test_brief_glance_away_is_not_a_new_sighting() -> void:
	rules.update_view(true, 0.1)
	rules.update_view(false, 1.0)
	assert_false(rules.update_view(true, 0.1), "out of view only briefly")
	rules.update_view(false, Monster.SIGHTING_GAP + 0.1)
	assert_true(rules.update_view(true, 0.1), "new sighting after a real gap")


func test_sighting_staged_at_deadline_when_unsighted() -> void:
	assert_false(rules.should_stage_sighting(0))
	assert_false(rules.should_stage_sighting(1))
	assert_true(rules.should_stage_sighting(2))
	assert_true(rules.should_stage_sighting(4))


func test_no_staged_sighting_when_already_sighted() -> void:
	rules.update_view(true, 0.1)
	assert_false(rules.should_stage_sighting(2))
	assert_false(rules.should_stage_sighting(5))


func test_failed_staging_waits_before_retrying() -> void:
	rules.note_sighting_attempt()
	assert_false(rules.should_stage_sighting(2), "retry delay")
	rules.update_view(false, Monster.SIGHTING_RETRY_DELAY + 0.1)
	assert_true(rules.should_stage_sighting(2))


# --- Mimicry and abduction schedules -----------------------------------------

func test_schedules_wait_until_one_am() -> void:
	rules.tick_schedules(1000.0, 0)
	assert_false(rules.mimic_due())
	assert_false(rules.abduction_due())


func test_mimic_due_within_interval_after_one_am() -> void:
	rules.tick_schedules(Monster.MIMIC_INTERVAL.x - 1.0, 1)
	assert_false(rules.mimic_due())
	rules.tick_schedules(Monster.MIMIC_INTERVAL.y - Monster.MIMIC_INTERVAL.x + 2.0, 1)
	assert_true(rules.mimic_due())
	rules.mimic_done()
	assert_false(rules.mimic_due())
	assert_true(rules.next_mimic_in >= Monster.MIMIC_INTERVAL.x)


func test_abductions_capped_at_max() -> void:
	for i in Monster.MAX_ABDUCTIONS:
		rules.tick_schedules(Monster.ABDUCT_INTERVAL.y + 1.0, 1)
		assert_true(rules.abduction_due(), "abduction %d due" % (i + 1))
		rules.abduction_done()
	rules.tick_schedules(10000.0, 3)
	assert_false(rules.abduction_due(), "no more than MAX_ABDUCTIONS")
	assert_eq(rules.abductions, Monster.MAX_ABDUCTIONS)
