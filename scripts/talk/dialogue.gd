extends Node
## Autoload `Dialogue`: her lines, loaded from data/dialogue/lines.json and keyed by
## trigger (idle, grab, pat, face, ...). Each line can carry a reaction animation and
## conditions on the time of day, affection level, today's mood, outfit or an unlocked
## memory. pick() returns a random line whose conditions hold, avoiding an immediate
## repeat. See the _comment at the top of the file for the format.

const LINES_PATH := "res://data/dialogue/lines.json"

## trigger -> Array of {"text": String, "anim": StringName, "when": Dictionary, "weight": float}
var _lines: Dictionary[StringName, Array] = {}
## trigger -> the text picked last time.
var _last: Dictionary[StringName, String] = {}


func _ready() -> void:
	load_lines(LINES_PATH)


## Replaces the loaded lines with the ones in `path`.
func load_lines(path: String) -> void:
	_lines.clear()
	_last.clear()
	var data: Variant = load_json(path)
	if not data is Dictionary:
		return
	for trigger: String in data:
		if trigger.begins_with("_"):
			continue # Comments.
		var entry: Variant = data[trigger]
		var default_anim := &""
		if entry is Dictionary:
			default_anim = StringName(entry.get("anim", ""))
			entry = entry.get("lines", [])
		var lines: Array[Dictionary] = []
		for line: Variant in entry:
			lines.append(_normalise(line, default_anim))
		_lines[StringName(trigger)] = lines


func has_trigger(trigger: StringName) -> bool:
	return _lines.has(trigger)


## A random line for `trigger` that fits right now, as {"text", "anim"}, or {} if none.
func pick(trigger: StringName) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var total := 0.0
	var context := current_context()
	for line: Dictionary in _lines.get(trigger, []):
		if matches(line.when, context):
			candidates.append(line)
	if candidates.size() > 1:
		candidates = candidates.filter(func(line: Dictionary) -> bool: return line.text != _last.get(trigger, ""))
	if candidates.is_empty():
		return {}
	for line in candidates:
		total += line.weight
	var roll := randf() * total
	var chosen: Dictionary = candidates.back()
	for line in candidates:
		roll -= line.weight
		if roll < 0.0:
			chosen = line
			break
	_last[trigger] = chosen.text
	return {"text": chosen.text, "anim": chosen.anim}


## What conditions are tested against: time of day, affection level, mood, outfit and
## bedtime phase (day, wind_down, night).
func current_context() -> Dictionary:
	return {
		"time": time_of_day(Time.get_datetime_dict_from_system().hour),
		"level": Affection.get_level(),
		"mood": Mood.today(),
		"outfit": Settings.get_value(&"wardrobe/outfit"),
		"phase": SleepSchedule.PHASE_NAMES[SleepSchedule.current_phase()],
	}


## Whether a line's "when" conditions hold in `context` (see current_context()).
static func matches(when: Dictionary, context: Dictionary) -> bool:
	for key: String in when:
		var want: Variant = when[key]
		match key:
			"level_min":
				if context.level < int(want):
					return false
			"level_max":
				if context.level > int(want):
					return false
			"level":
				if context.level != int(want):
					return false
			"memory":
				if not SaveData.get_value(&"talk/memories").has(want):
					return false
			"time", "mood", "outfit", "phase":
				var options: Array = want if want is Array else [want]
				if not options.has(context.get(key)):
					return false
			_:
				push_warning("Dialogue: unknown condition '%s'" % key)
				return false
	return true


static func time_of_day(hour: int) -> String:
	if hour >= 5 and hour < 12:
		return "morning"
	if hour >= 12 and hour < 18:
		return "afternoon"
	if hour >= 18 and hour < 22:
		return "evening"
	return "night"


## Loads a JSON data file (as data, not a resource, so it works the same when exported).
static func load_json(path: String) -> Variant:
	var json := load(path) as JSON
	if json == null:
		push_error("Dialogue: couldn't load %s" % path)
		return null
	return json.data


static func _normalise(line: Variant, default_anim: StringName) -> Dictionary:
	if line is String:
		line = {"text": line}
	return {
		"text": String(line.get("text", "")),
		"anim": StringName(line.get("anim", default_anim)),
		"when": line.get("when", {}),
		"weight": float(line.get("weight", 1.0)),
	}
