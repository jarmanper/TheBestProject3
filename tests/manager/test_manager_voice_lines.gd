extends TestCase
## Manager dialogue lives in ManagerLines. This focused guard makes a changed
## PA or walkie sentence fail until its generated voice clip is refreshed.


func before_each() -> void:
	VoiceLines.reset_cache()


func test_every_manager_dialogue_category_has_copy() -> void:
	assert_false(ManagerLines.WELCOME.is_empty(), "welcome lines")
	assert_false(ManagerLines.HOURLY.is_empty(), "hourly lines")
	assert_false(ManagerLines.PA_FLAVOUR.is_empty(), "PA flavour lines")
	assert_false(ManagerLines.COWORKER_MISSING.is_empty(), "missing-coworker lines")
	assert_false(ManagerLines.TASK_COMPLETED.is_empty(), "completion lines")
	assert_false(ManagerLines.TASK_DUE_SOON.is_empty(), "due-soon lines")
	assert_false(ManagerLines.TASK_FAILED.is_empty(), "failure lines")
	assert_false(ManagerLines.TALK.is_empty(), "face-to-face talk lines")


func test_every_manager_intercom_line_has_a_generated_clip() -> void:
	var lines: Array[String] = []
	for line: String in ManagerLines.WELCOME:
		lines.append(line)
	for hour in range(1, GameState.END_HOUR):
		for template: String in ManagerLines.HOURLY:
			lines.append(template % ("%d:00 AM" % hour))
	for line: String in ManagerLines.PA_FLAVOUR:
		lines.append(line)
	for entry: Dictionary in StationLayout.STATIONS:
		lines.append(_station_line(entry))
	_assert_clips(lines, VoiceLines.INTERCOM)


func test_every_manager_walkie_line_has_a_generated_clip() -> void:
	var lines: Array[String] = []
	for entry: Dictionary in StationLayout.STATIONS:
		lines.append(_station_line(entry))
	for coworker: Dictionary in Catalog.COWORKERS:
		for template: String in ManagerLines.COWORKER_MISSING:
			lines.append(template % String(coworker["name"]))
	for line: String in ManagerLines.TASK_COMPLETED:
		lines.append(line)
	for line: String in ManagerLines.TASK_DUE_SOON:
		lines.append(line)
	for line: String in ManagerLines.TASK_FAILED:
		lines.append(line)
	_assert_clips(lines, VoiceLines.WALKIE)


func _station_line(entry: Dictionary) -> String:
	var line := String(entry.get("manager_line", ""))
	return line if not line.is_empty() else "Attention: " + String(entry["title"])


func _assert_clips(lines: Array[String], channel: StringName) -> void:
	for line in lines:
		assert_true(VoiceLines.has_clip("MANAGER", line, false, channel),
			"%s clip for: %s" % [channel, line])
