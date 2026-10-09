extends TestCase
## Verifies every Sfx.SOUNDS id resolves to a loadable audio file, every
## Sfx.LOOPING id comes back looping from Sfx.get_stream(), and durations are
## sane (one-shots < 8s, loops >= 4s). See docs/ARCHITECTURE.md ("Sfx") and
## autoload/sfx.gd.


func test_every_sound_variant_file_loads() -> void:
	for id in Sfx.SOUNDS:
		var variants: Array = Sfx.SOUNDS[id]
		assert_true(not variants.is_empty(), "id %s has no variants" % id)
		for base in variants:
			var found := false
			for ext in [".ogg", ".wav"]:
				if ResourceLoader.exists(base + ext):
					var stream := load(base + ext)
					assert_true(stream is AudioStream, "%s%s did not load as an AudioStream" % [base, ext])
					found = true
					break
			assert_true(found, "missing audio file for %s (.ogg|.wav)" % base)


func test_every_id_resolves_via_get_stream() -> void:
	for id in Sfx.SOUNDS:
		var stream := Sfx.get_stream(id)
		assert_true(stream != null, "Sfx.get_stream(%s) returned null" % id)


func test_looping_ids_loop() -> void:
	for id in Sfx.LOOPING:
		var stream := Sfx.get_stream(id)
		assert_true(stream != null, "missing stream for looping id %s" % id)
		if stream == null:
			continue
		if stream is AudioStreamOggVorbis:
			assert_true(stream.loop, "%s (ogg) is not set to loop" % id)
		elif stream is AudioStreamWAV:
			assert_true(stream.loop_mode != AudioStreamWAV.LOOP_DISABLED, "%s (wav) is not set to loop" % id)
		else:
			_fail("%s has an unexpected stream type for looping audio" % id)


func test_durations_are_sane() -> void:
	for id in Sfx.SOUNDS:
		var is_loop: bool = id in Sfx.LOOPING
		for base in Sfx.SOUNDS[id]:
			var stream: AudioStream = null
			for ext in [".ogg", ".wav"]:
				if ResourceLoader.exists(base + ext):
					stream = load(base + ext)
					break
			if stream == null:
				continue
			var length: float = stream.get_length()
			if is_loop:
				assert_true(length >= 4.0, "%s loop is only %.2fs (want >= 4s)" % [base, length])
			else:
				assert_true(length < 8.0, "%s one-shot is %.2fs (want < 8s)" % [base, length])
