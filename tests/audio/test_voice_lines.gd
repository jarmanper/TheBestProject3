extends TestCase
## Recorded voice lines (VoiceLines + assets/audio/voice): every line the game can say has a
## clip for its speaker, lure lines have the mimic take, unknown lines fall back quietly.

var radio: WalkieRadio


func before_each() -> void:
	VoiceLines.reset_cache()
	radio = WalkieRadio.new()


func after_each() -> void:
	radio.free()


func _run(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		radio.tick(0.05)
		t += 0.05


func test_every_enumerated_line_has_a_clip() -> void:
	var lines := VoiceLines.enumerate_all()
	assert_true(lines.size() > 300, "enumerated %d lines" % lines.size())
	var missing: Array[String] = []
	for line in lines:
		if not VoiceLines.has_clip(line.speaker, line.text, line.mimic, StringName(line.channel)):
			missing.append("%s/%s%s: %s" % [line.channel, line.speaker, " (mimic)" if line.mimic else "", line.text])
	assert_true(missing.is_empty(), "%d lines without a clip (re-run art_source/voice/build_voices.sh), e.g. %s"
			% [missing.size(), missing.slice(0, 3)])


func test_every_speaker_and_lure_is_covered() -> void:
	var lines := VoiceLines.enumerate_all()
	var speakers := {}
	var mimic_speakers := {}
	for line in lines:
		speakers[line.speaker] = true
		if line.mimic:
			mimic_speakers[line.speaker] = true
	for entry: Dictionary in Catalog.COWORKERS:
		assert_true(speakers.has(entry["name"]), "%s speaks" % entry["name"])
		assert_true(mimic_speakers.has(entry["name"]), "the mimic can wear %s's voice" % entry["name"])
	assert_true(speakers.has("MANAGER"), "the manager speaks")
	var lure := MonsterLines.lure_line("RITA", &"storage", RandomNumberGenerator.new())
	assert_true(VoiceLines.has_clip("RITA", lure, true, VoiceLines.WALKIE), "lure has a mimic clip: " + lure)


func test_real_and_mimic_takes_are_different_clips() -> void:
	var rng := RandomNumberGenerator.new()
	var line := MonsterLines.lure_line("DALE", &"dairy", rng)
	var mimic := VoiceLines.get_stream("DALE", line, true, VoiceLines.WALKIE)
	assert_true(mimic != null, "mimic take loads")
	var chatter := CoworkerLines.chatter_line("DALE", &"dairy", &"resting", "", rng)
	var real := VoiceLines.get_stream("DALE", chatter, false, VoiceLines.WALKIE)
	assert_true(real != null, "real take loads")
	assert_true(mimic != real)


func test_unknown_line_returns_null_not_error() -> void:
	assert_eq(VoiceLines.get_stream("DALE", "This sentence was never recorded.", false, VoiceLines.WALKIE), null)
	assert_eq(VoiceLines.get_stream("NOBODY", "Hello.", true, VoiceLines.INTERCOM), null)
	assert_false(VoiceLines.has_clip("DALE", "This sentence was never recorded.", false, VoiceLines.WALKIE))


func test_clips_load_with_sane_durations() -> void:
	var lines := VoiceLines.enumerate_all()
	var checked := 0
	for i in range(0, lines.size(), 7):   ## a spread sample; loading all is slow-ish
		var line: Dictionary = lines[i]
		var stream := VoiceLines.get_stream(line.speaker, line.text, line.mimic, StringName(line.channel))
		assert_true(stream != null, "loads: " + line.text)
		if stream == null:
			continue
		var seconds := stream.get_length()
		var per_char := seconds / maxf(String(line.text).length(), 1.0)
		assert_true(seconds > 0.8 and seconds < 14.0, "%.2fs for \"%s\"" % [seconds, line.text])
		assert_true(per_char > 0.03 and per_char < 0.2, "%.3fs/char for \"%s\"" % [per_char, line.text])
		checked += 1
	assert_true(checked > 50, "checked %d clips" % checked)


func test_radio_plays_real_clip_for_known_line() -> void:
	var line := CoworkerLines.chatter_line("MARCUS", &"produce", &"resting", "", RandomNumberGenerator.new())
	var clip := VoiceLines.get_stream("MARCUS", line, false, VoiceLines.WALKIE)
	radio.enqueue("MARCUS", line, false)
	assert_eq(radio.last_voice_stream, clip, "plays MARCUS's recording")
	_run(20.0)
	assert_eq(radio.history, [&"walkie_squelch_on", WalkieRadio.VOICE_LINE_ID, &"walkie_squelch_off"] as Array[StringName])


func test_radio_plays_mimic_clip_for_lure() -> void:
	var line := MonsterLines.lure_line("RITA", &"office", RandomNumberGenerator.new())
	radio.enqueue("RITA", line, true)
	assert_eq(radio.last_voice_stream, VoiceLines.get_stream("RITA", line, true, VoiceLines.WALKIE))
	assert_true(radio.last_voice_stream != VoiceLines.get_stream("RITA", line, false, VoiceLines.WALKIE))


func test_radio_falls_back_to_babble_for_unknown_line() -> void:
	radio.enqueue("DALE", "A line nobody recorded yet.", false)
	_run(20.0)
	assert_eq(radio.history, [&"walkie_squelch_on", &"walkie_voice", &"walkie_squelch_off"] as Array[StringName])
