class_name VoiceLines
extends RefCounted
## Real spoken voice clips for walkie and intercom lines: one recording per final sentence,
## a distinct voice per speaker, and a subtly wrong "mimic" take of every lure line.
##
## Clips are generated offline by art_source/voice/build_voices.sh, which calls
## `enumerate_all()` below so the recorded set always matches the live line tables
## (ManagerLines, StationLayout, CoworkerLines, MonsterLines). Each clip's path is
## derived from (channel, speaker, mimic, exact text), listed in the generated
## assets/audio/voice/voice_manifest.gd. A line with no clip (a teammate added or
## reworded one and nobody re-ran the pipeline) returns null: callers fall back to the
## generic babble, and a warning is pushed once per line.

const WALKIE := &"walkie"
const INTERCOM := &"intercom"
const MANIFEST_PATH := "res://assets/audio/voice/voice_manifest.gd"

static var _manifest: Dictionary = {}
static var _manifest_loaded := false
static var _cache: Dictionary = {}
static var _warned: Dictionary = {}


## The clip for `speaker` saying exactly `text` on `channel` (WALKIE or INTERCOM), or the
## mimic's wrong-sounding take of it when `is_mimic`. Null when no clip was generated.
static func get_stream(speaker: String, text: String, is_mimic: bool, channel: StringName) -> AudioStream:
	var key := clip_key(speaker, text, is_mimic, channel)
	if _cache.has(key):
		return _cache[key]
	var path := clip_path(speaker, text, is_mimic, channel)
	var stream: AudioStream = null
	if not path.is_empty() and ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	if stream == null and not _warned.has(key):
		_warned[key] = true
		push_warning("VoiceLines: no %s clip for %s%s: \"%s\" (re-run art_source/voice/build_voices.sh)"
				% [channel, speaker, " (mimic)" if is_mimic else "", text])
	_cache[key] = stream
	return stream


## Manifest path for a line, or "" when it was never generated.
static func clip_path(speaker: String, text: String, is_mimic: bool, channel: StringName) -> String:
	return String(_get_manifest().get(clip_key(speaker, text, is_mimic, channel), ""))


static func has_clip(speaker: String, text: String, is_mimic: bool, channel: StringName) -> bool:
	return not clip_path(speaker, text, is_mimic, channel).is_empty()


## Manifest key: "channel|SPEAKER|mimic-flag|exact text".
static func clip_key(speaker: String, text: String, is_mimic: bool, channel: StringName) -> String:
	return "%s|%s|%d|%s" % [channel, speaker.to_upper(), int(is_mimic), text]


## Drops cached streams and re-reads the manifest (tests / after regeneration).
static func reset_cache() -> void:
	_cache.clear()
	_warned.clear()
	_manifest_loaded = false
	_manifest = {}


static func _get_manifest() -> Dictionary:
	if not _manifest_loaded:
		_manifest_loaded = true
		if ResourceLoader.exists(MANIFEST_PATH):
			var script := load(MANIFEST_PATH) as GDScript
			if script:
				var lines: Variant = script.get_script_constant_map().get("LINES", {})
				if lines is Dictionary:
					_manifest = lines
	return _manifest


# --- Enumeration (used by the offline pipeline and tests) -------------------------------

## Every final string the game can emit on the walkie or intercom, as
## [{speaker, text, mimic, channel}], built by calling the real line tables with every
## placeholder value (coworker names, zones, clock hours, station titles).
static func enumerate_all() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	var names: Array[String] = []
	for entry: Dictionary in Catalog.COWORKERS:
		names.append(String(entry["name"]))
	var zones: Array[StringName] = [&""]
	for zone_id: StringName in Catalog.ZONES:
		zones.append(zone_id)

	# Store manager: intercom (StoreManager._announce) and walkie (StoreManager._walkie).
	for line: String in ManagerLines.WELCOME:
		_add(out, seen, "MANAGER", line, false, INTERCOM)
	for hour in range(1, GameState.END_HOUR):
		for template: String in ManagerLines.HOURLY:
			_add(out, seen, "MANAGER", template % ("%d:00 AM" % hour), false, INTERCOM)
	for line: String in ManagerLines.PA_FLAVOUR:
		_add(out, seen, "MANAGER", line, false, INTERCOM)
	for entry: Dictionary in StationLayout.STATIONS:
		var line: String = entry.get("manager_line", "")
		if line.is_empty():
			line = "Attention: " + String(entry["title"])
		_add(out, seen, "MANAGER", line, false, INTERCOM)
		_add(out, seen, "MANAGER", line, false, WALKIE)
	for coworker_name in names:
		for template: String in ManagerLines.COWORKER_MISSING:
			_add(out, seen, "MANAGER", template % coworker_name, false, WALKIE)
	for line: String in ManagerLines.TASK_COMPLETED:
		_add(out, seen, "MANAGER", line, false, WALKIE)
	for line: String in ManagerLines.TASK_FAILED:
		_add(out, seen, "MANAGER", line, false, WALKIE)

	# Coworkers: truthful check-ins and panic (Coworker.say_where_i_am / _start_flee).
	for coworker_name in names:
		for zone_id in zones:
			for template: String in CoworkerLines.RESTING:
				_add(out, seen, coworker_name, CoworkerLines._fill(template, coworker_name, zone_id, ""), false, WALKIE)
			for template: String in CoworkerLines.HEADING:
				_add(out, seen, coworker_name, CoworkerLines._fill(template, coworker_name, zone_id, ""), false, WALKIE)
			for template: String in CoworkerLines.PANIC:
				_add(out, seen, coworker_name, CoworkerLines._fill(template, coworker_name, zone_id, ""), false, WALKIE)
		# Working: they stand at the station, so the zone is the station's own.
		for entry: Dictionary in StationLayout.STATIONS:
			for template: String in CoworkerLines.WORKING:
				_add(out, seen, coworker_name, CoworkerLines._fill(template, coworker_name, entry["zone"], String(entry["title"])), false, WALKIE)

	# The mimic wearing a coworker's voice (Monster.try_mimic_lure).
	for coworker_name in names:
		for zone_id in zones:
			for template: String in MonsterLines.LURES:
				var line := template.format({"name": coworker_name, "zone": CoworkerLines.zone_phrase(zone_id)})
				_add(out, seen, coworker_name, line, true, WALKIE)
	return out


static func _add(out: Array[Dictionary], seen: Dictionary, speaker: String, text: String, mimic: bool, channel: StringName) -> void:
	var key := clip_key(speaker, text, mimic, channel)
	if seen.has(key):
		return
	seen[key] = true
	out.append({"speaker": speaker, "text": text, "mimic": mimic, "channel": String(channel)})
