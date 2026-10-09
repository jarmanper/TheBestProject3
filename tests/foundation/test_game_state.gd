extends TestCase


func after_each() -> void:
	GameState.night_running = false


func test_clock_starts_at_midnight() -> void:
	GameState.start_night()
	assert_eq(GameState.get_clock_text(), "12:00 AM")
	assert_eq(GameState.get_hour(), 0)


func test_clock_text_after_ninety_minutes() -> void:
	GameState.start_night()
	GameState.advance(GameState.SECONDS_PER_HOUR * 1.5)
	assert_eq(GameState.get_clock_text(), "1:30 AM")


func test_hour_changed_emits_on_new_hour() -> void:
	var hours: Array[int] = []
	var record := func(hour: int) -> void: hours.append(hour)
	Events.hour_changed.connect(record)
	GameState.start_night()
	GameState.advance(GameState.SECONDS_PER_HOUR + 1.0)
	Events.hour_changed.disconnect(record)
	assert_eq(hours, [0, 1] as Array[int])


func test_night_ends_at_six_with_result() -> void:
	var results: Array[StringName] = []
	var record := func(result: StringName) -> void: results.append(result)
	Events.night_ended.connect(record)
	GameState.start_night()
	GameState.advance(GameState.SECONDS_PER_HOUR * GameState.END_HOUR)
	Events.night_ended.disconnect(record)
	assert_false(GameState.night_running)
	assert_eq(results.size(), 1)
	assert_eq(GameState.get_clock_text(), "6:00 AM")


func test_end_night_only_fires_once() -> void:
	var count := [0]
	var record := func(_result: StringName) -> void: count[0] += 1
	Events.night_ended.connect(record)
	GameState.start_night()
	GameState.end_night(&"dead")
	GameState.end_night(&"win")
	Events.night_ended.disconnect(record)
	assert_eq(count[0], 1)
	assert_eq(GameState.last_result, &"dead")
