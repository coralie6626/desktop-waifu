extends KeyValueStore
## Autoload `Settings`: user preferences, stored in user://settings.cfg. A key's
## "section/name" maps to a [section] and name in the file, so it stays hand-editable.
##
##   Settings.get_value(&"window/always_on_top")
##   Settings.set_value(&"audio/sfx_volume", 0.5)
##   Settings.changed.connect(func(key): ...)

const PATH := "user://settings.cfg"


func _defaults() -> Dictionary[StringName, Variant]:
	return {
		&"window/always_on_top": true,
		&"window/click_through": false,
		# "primary", "follow_mouse", or a screen index as a string.
		&"window/monitor": "primary",
		&"audio/voice_volume": 1.0,
		&"audio/sfx_volume": 1.0,
		# "HH:MM", 24-hour clock. Empty disables the sleep schedule.
		&"schedule/bedtime": "23:00",
		# Minutes between rest reminders; 0 turns them off.
		&"schedule/rest_reminder_minutes": 0,
		&"wardrobe/outfit": "default",
		&"wardrobe/pajamas": "default",
		&"wardrobe/hat": "",
		&"wardrobe/glasses": "",
		&"wardrobe/bedding": "default",
		&"wardrobe/cushion": "default",
		# Executable names (e.g. "game.exe") treated as full-screen games.
		&"games/whitelist": PackedStringArray(),
		# Executables that never count as games, even full-screen.
		&"games/blacklist": PackedStringArray(),
	}


func _read() -> Dictionary:
	var config := ConfigFile.new()
	var err := config.load(PATH)
	if err != OK:
		if err != ERR_FILE_NOT_FOUND:
			push_warning("Settings: couldn't read %s (%s), using defaults" % [PATH, error_string(err)])
		return {}
	var stored := {}
	for section in config.get_sections():
		for key in config.get_section_keys(section):
			stored["%s/%s" % [section, key]] = config.get_value(section, key)
	return stored


func _write(data: Dictionary[StringName, Variant]) -> Error:
	var config := ConfigFile.new()
	for key in data:
		var parts := String(key).split("/", true, 1)
		config.set_value(parts[0], parts[1], data[key])
	return _replace_file(PATH, config.save)
