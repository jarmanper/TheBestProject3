extends TestCase
## Player-side walkie radio: squelch -> voice (mimic variant) -> squelch, queued.

var radio: WalkieRadio
var started: Array = []


func before_each() -> void:
	radio = WalkieRadio.new()
	started.clear()
	radio.message_started.connect(func(speaker: String, message: String, duration: float) -> void:
		started.append([speaker, message, duration]))


func after_each() -> void:
	radio.free()


func _run(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		radio.tick(0.05)
		t += 0.05


func test_squelch_voice_squelch_in_order() -> void:
	radio.enqueue("DALE", "I'm in the freezer aisle.", false)
	_run(20.0)
	assert_eq(radio.history, [&"walkie_squelch_on", &"walkie_voice", &"walkie_squelch_off"] as Array[StringName])
	assert_false(radio.is_busy())


func test_mimic_uses_mimic_voice() -> void:
	radio.enqueue("RITA", "Can you help me in storage?", true)
	_run(20.0)
	assert_eq(radio.history, [&"walkie_squelch_on", &"walkie_voice_mimic", &"walkie_squelch_off"] as Array[StringName])


func test_overlapping_messages_queue() -> void:
	radio.enqueue("DALE", "First.", false)
	radio.enqueue("RITA", "Second.", true)
	radio.tick(0.05)
	assert_eq(started.size(), 1, "second waits for the first")
	assert_eq(started[0][0], "DALE")
	_run(30.0)
	assert_eq(started.size(), 2)
	assert_eq(started[1][0], "RITA")
	assert_eq(radio.history, [
		&"walkie_squelch_on", &"walkie_voice", &"walkie_squelch_off",
		&"walkie_squelch_on", &"walkie_voice_mimic", &"walkie_squelch_off",
	] as Array[StringName])


func test_message_started_has_subtitle_duration() -> void:
	radio.enqueue("MARCUS", "Breaker's acting up again.", false)
	assert_eq(started.size(), 1)
	assert_true(started[0][2] >= 2.0, "subtitle lasts at least the voice line")
