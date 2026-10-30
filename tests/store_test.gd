extends Node
## Self-check for the Settings and SaveData autoloads. Run this scene (F6) and read the
## Output: one PASS/FAIL line per check. Values it touches are put back afterwards.
## Also works from a terminal: godot --headless res://tests/store_test.tscn
## (exit code 1 on failure).

var _failures := 0


func _ready() -> void:
	var saved_sfx: Variant = Settings.get_value(&"audio/sfx_volume")
	var saved_whitelist: Variant = Settings.get_value(&"games/whitelist")
	var saved_affection: Variant = SaveData.get_value(&"affection/points")

	var changes: Array[StringName] = []
	var record := func(key: StringName) -> void: changes.append(key)
	Settings.changed.connect(record)

	Settings.set_value(&"audio/sfx_volume", 0.25)
	_check("set_value stores the value", Settings.get_value(&"audio/sfx_volume") == 0.25)
	_check("set_value emits changed", changes.size() == 1 and changes[0] == &"audio/sfx_volume")
	Settings.set_value(&"audio/sfx_volume", 0.25)
	_check("setting the same value doesn't emit changed", changes.size() == 1)

	Settings.set_value(&"audio/sfx_volume", 1)
	_check("ints convert to floats", typeof(Settings.get_value(&"audio/sfx_volume")) == TYPE_FLOAT)

	print("(the next two errors are expected)")
	Settings.set_value(&"audio/sfx_volume", "loud")
	_check("a value of the wrong type is rejected", Settings.get_value(&"audio/sfx_volume") == 1.0)
	Settings.set_value(&"nope/key", 1)
	_check("an unknown key is rejected", not Settings.has_key(&"nope/key"))

	var list: PackedStringArray = Settings.get_value(&"games/whitelist")
	list.append("store_test.exe")
	_check("get_value returns a copy", not Settings.get_value(&"games/whitelist").has("store_test.exe"))
	Settings.set_value(&"games/whitelist", ["store_test.exe"])
	_check("arrays convert to packed arrays", Settings.get_value(&"games/whitelist") is PackedStringArray)

	SaveData.set_value(&"affection/points", 42)
	Settings.changed.disconnect(record)

	Settings.flush()
	SaveData.flush()
	_check("settings survive a reload",
		_reloaded_value("res://scripts/data/settings.gd", &"games/whitelist") == PackedStringArray(["store_test.exe"]))
	_check("save data survives a reload",
		_reloaded_value("res://scripts/data/save_data.gd", &"affection/points") == 42)
	_check("no temp files are left behind",
		not FileAccess.file_exists("user://settings.cfg.tmp") and not FileAccess.file_exists("user://save.json.tmp"))

	Settings.set_value(&"audio/sfx_volume", saved_sfx)
	Settings.set_value(&"games/whitelist", saved_whitelist)
	SaveData.set_value(&"affection/points", saved_affection)
	Settings.flush()
	SaveData.flush()

	if _failures == 0:
		print("All store checks passed.")
	else:
		printerr("%d store check(s) failed." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


## Loads a fresh copy of a store from disk, as the next launch would, and reads `key`.
func _reloaded_value(script_path: String, key: StringName) -> Variant:
	var store: KeyValueStore = load(script_path).new()
	store._load()
	var value: Variant = store.get_value(key)
	store.free()
	return value


func _check(description: String, ok: bool) -> void:
	if ok:
		print("PASS  ", description)
	else:
		_failures += 1
		printerr("FAIL  ", description)
