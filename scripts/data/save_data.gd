extends KeyValueStore
## Autoload `SaveData`: progress that builds up over time, stored in user://save.json.
## Same API as Settings (get_value / set_value / changed); kept apart so wiping
## preferences never wipes progress, and the other way round.

const PATH := "user://save.json"
## Bump when the layout changes, and migrate older files in _read().
const VERSION := 1


func _defaults() -> Dictionary[StringName, Variant]:
	return {
		&"affection/points": 0,
		# Daily gain cap bookkeeping (see Affection): the day it counts for, and the total.
		&"affection/day": "",
		&"affection/gained_today": 0,
		# Unix time she was last running, to notice neglect.
		&"affection/last_seen": 0,
		# Snack Time topic ids that have been seen at least once.
		&"talk/unlocked_topics": PackedStringArray(),
		# Milestones and story events for the Memories gallery: {id: unix time unlocked}.
		&"talk/memories": {},
		# One answer per day from the mood check-in: {"YYYY-MM-DD": "great" | "okay" | ...}.
		&"talk/mood_history": {},
		# Snack Time (see SnackTime): the day the offer is for, the topic ids offered, and
		# those already talked about that day.
		&"talk/snack_day": "",
		&"talk/snack_offer": PackedStringArray(),
		&"talk/snack_done": PackedStringArray(),
		# Each reminder is a Dictionary; its fields are defined by the reminders feature.
		&"tools/reminders": [],
	}


## Records a Memories-gallery entry the first time it happens; returns true if it's new.
func unlock_memory(id: String) -> bool:
	var memories: Dictionary = get_value(&"talk/memories")
	if memories.has(id):
		return false
	memories[id] = int(Time.get_unix_time_from_system())
	set_value(&"talk/memories", memories)
	return true


func _read() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var text := FileAccess.get_file_as_string(PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary or not parsed.get("values") is Dictionary:
		# Keep the broken file around instead of overwriting the player's progress.
		var backup := PATH.get_basename() + ".broken.json"
		DirAccess.copy_absolute(PATH, backup)
		push_error("SaveData: %s is unreadable, copied it to %s and started fresh" % [PATH, backup])
		return {}
	return parsed["values"]


func _write(data: Dictionary[StringName, Variant]) -> Error:
	var text := JSON.stringify({"version": VERSION, "values": data}, "\t")
	return _replace_file(PATH, func(path: String) -> Error:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return FileAccess.get_open_error()
		file.store_string(text)
		var err := file.get_error()
		file.close() # Must be closed before it's renamed.
		return err
	)
