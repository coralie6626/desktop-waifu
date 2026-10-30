class_name ReminderParser
## Reads a reminder typed in plain English and works out when it's due:
##   "call mom at 18:30", "meeting tomorrow 9am", "stretch in 20 min",
##   "dentist friday 14:00", "pay rent 01/12", "tea in 1h 30m".
## Understood: "in N sec/min/h" (also "in an hour", "in 1h 30m"), times as HH:MM, 18h30,
## 6pm, 6:30pm, "at 6", noon and midnight, and dates as today, tonight, tomorrow, weekday
## names (full or short) and dd/mm or dd/mm/yyyy. A date without a time means 9:00
## ("tonight" means 20:00); a time without a date that has already passed today means
## tomorrow. Everything is local time.

const WEEKDAYS: PackedStringArray = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
const DEFAULT_HOUR := 9
const TONIGHT_HOUR := 20

static var _relative := _regex("\\bin\\s+(an?|half an|\\d+(?:[.,]\\d+)?)\\s*(seconds?|secs?|s|minutes?|mins?|m|hours?|hrs?|h)\\b(?:\\s*(?:and\\s+)?(\\d+)\\s*(minutes?|mins?|m)\\b)?")
static var _clock := _regex("\\b(?:at\\s+)?(\\d{1,2})(?::|h|\\.)(\\d{2})\\s*(am|pm)?\\b")
static var _ampm := _regex("\\b(?:at\\s+)?(\\d{1,2})\\s*(am|pm)\\b")
static var _at_hour := _regex("\\bat\\s+(\\d{1,2})\\b(?![/:.])")
static var _named_time := _regex("\\b(?:at\\s+)?(noon|midday|midnight)\\b")
static var _day_word := _regex("\\b(today|tonight|tomorrow|tmrw)\\b")
static var _weekday := _regex("\\b(?:on\\s+|next\\s+)?(sun|mon|tue|tues|wed|thu|thur|thurs|fri|sat)(?:day|nesday|sday|urday|rsday)?\\b")
static var _date := _regex("\\b(?:on\\s+)?(\\d{1,2})/(\\d{1,2})(?:/(\\d{2,4}))?\\b")


## {"text": what to remind about, "due": unix time} or {} if no time was found.
## `now` and `tz_bias` (seconds east of UTC) default to the system clock and time zone.
static func parse(input: String, now: int = -1, tz_bias: Variant = null) -> Dictionary:
	if now < 0:
		now = int(Time.get_unix_time_from_system())
	var bias: int = system_bias() if tz_bias == null else tz_bias
	var lower := input.to_lower()
	var spans: Array[Vector2i] = []

	var relative := _relative.search(lower)
	if relative:
		spans.append(Vector2i(relative.get_start(), relative.get_end()))
		var due := now + _relative_seconds(relative)
		return {"text": _clean(input, spans), "due": due}

	var local_now := now + bias
	var today := local_now - posmod(local_now, 86400) # Local midnight, in local seconds.
	var day_offset := -1 # Days from today; -1 = not given.
	var from_weekday := false
	var date_match: RegExMatch = null # An explicit dd/mm(/yyyy).
	var hour := -1
	var minute := 0

	var m := _clock.search(lower)
	if m:
		hour = _hour_24(int(m.get_string(1)), m.get_string(3))
		minute = int(m.get_string(2))
	else:
		m = _ampm.search(lower)
		if m:
			hour = _hour_24(int(m.get_string(1)), m.get_string(2))
		else:
			m = _named_time.search(lower)
			if m:
				hour = 0 if m.get_string(1) == "midnight" else 12
			else:
				m = _at_hour.search(lower)
				if m:
					hour = int(m.get_string(1))
	if m:
		spans.append(Vector2i(m.get_start(), m.get_end()))
	if hour > 23 or minute > 59:
		return {}

	m = _day_word.search(lower)
	if m:
		spans.append(Vector2i(m.get_start(), m.get_end()))
		var word := m.get_string(1)
		day_offset = 0 if word in ["today", "tonight"] else 1
		if word == "tonight" and hour < 0:
			hour = TONIGHT_HOUR
	else:
		m = _weekday.search(lower)
		if m:
			spans.append(Vector2i(m.get_start(), m.get_end()))
			var target := _weekday_index(m.get_string(1))
			var current: int = Time.get_datetime_dict_from_unix_time(local_now).weekday
			day_offset = posmod(target - current, 7)
			from_weekday = true
		else:
			date_match = _date.search(lower)
			if date_match:
				spans.append(Vector2i(date_match.get_start(), date_match.get_end()))

	if hour < 0 and day_offset < 0 and date_match == null:
		return {}
	if hour < 0:
		hour = DEFAULT_HOUR
	var time_of_day := hour * 3600 + minute * 60
	var due_local: int
	if date_match:
		var day := int(date_match.get_string(1))
		var month := int(date_match.get_string(2))
		var year_text := date_match.get_string(3)
		var start := _date_start(day, month, year_text, local_now)
		if start < 0:
			return {}
		due_local = start + time_of_day
		if due_local <= local_now and year_text.is_empty():
			due_local = _date_start(day, month, "", local_now, 1) + time_of_day # Next year's.
	elif day_offset >= 0:
		due_local = today + day_offset * 86400 + time_of_day
		if due_local <= local_now and from_weekday:
			due_local += 7 * 86400 # "friday" on a Friday evening means next week.
	else:
		due_local = today + time_of_day
		if due_local <= local_now:
			due_local += 86400
	return {"text": _clean(input, spans), "due": due_local - bias}


## A duration like "10", "10 min", "1h 30m", "90 sec" in seconds, or 0 if unreadable.
## A bare number means minutes.
static func parse_duration(input: String) -> int:
	var lower := input.strip_edges().to_lower()
	if lower.is_valid_float():
		return roundi(lower.to_float() * 60.0)
	var m := _relative.search("in " + lower)
	return _relative_seconds(m) if m else 0


## How a due time reads in a sentence: "in 10 min", "at 18:30", "tomorrow at 9:00",
## "on Friday at 14:00" or "on 01/12 at 9:00".
static func describe(due: int, now: int = -1, tz_bias: Variant = null) -> String:
	if now < 0:
		now = int(Time.get_unix_time_from_system())
	var bias: int = system_bias() if tz_bias == null else tz_bias
	var left := due - now
	if left >= 0 and left < 3600:
		return "in %d min" % maxi(1, roundi(left / 60.0)) if left >= 60 else "in %d sec" % left
	var local := Time.get_datetime_dict_from_unix_time(due + bias)
	var clock := "%d:%02d" % [local.hour, local.minute]
	var days := floori((due + bias) / 86400.0) - floori((now + bias) / 86400.0)
	if days == 0:
		return "at " + clock
	if days == 1:
		return "tomorrow at " + clock
	if days > 1 and days < 7:
		return "on %s at %s" % [WEEKDAYS[local.weekday].capitalize(), clock]
	return "on %02d/%02d at %s" % [local.day, local.month, clock]


## The system's offset from UTC in seconds (positive east of Greenwich).
static func system_bias() -> int:
	return int(Time.get_time_zone_from_system().bias) * 60


static func _relative_seconds(m: RegExMatch) -> int:
	var amount_text := m.get_string(1).replace(",", ".")
	var amount := 0.5 if amount_text == "half an" else (1.0 if amount_text in ["a", "an"] else amount_text.to_float())
	var seconds := amount * _unit_seconds(m.get_string(2))
	if not m.get_string(3).is_empty():
		seconds += int(m.get_string(3)) * 60
	return roundi(seconds)


static func _unit_seconds(unit: String) -> int:
	if unit.begins_with("h"):
		return 3600
	if unit.begins_with("m"):
		return 60
	return 1


static func _hour_24(hour: int, suffix: String) -> int:
	if suffix == "am":
		return 0 if hour == 12 else hour
	if suffix == "pm":
		return hour if hour == 12 else hour + 12
	return hour


static func _weekday_index(prefix: String) -> int:
	for i in WEEKDAYS.size():
		if WEEKDAYS[i].begins_with(prefix.substr(0, 3)):
			return i
	return -1


## Local midnight (in local seconds) of day/month, in the given year or this one, or the
## next year when `year_offset` is 1. -1 for an impossible date.
static func _date_start(day: int, month: int, year_text: String, local_now: int, year_offset := 0) -> int:
	var year: int = Time.get_datetime_dict_from_unix_time(local_now).year + year_offset
	if not year_text.is_empty():
		year = int(year_text) + (2000 if year_text.length() == 2 else 0)
	if month < 1 or month > 12 or day < 1 or day > _days_in_month(month, year):
		return -1
	return Time.get_unix_time_from_datetime_dict({"year": year, "month": month, "day": day, "hour": 0, "minute": 0, "second": 0})


static func _days_in_month(month: int, year: int) -> int:
	if month == 2:
		var leap := (year % 4 == 0 and year % 100 != 0) or year % 400 == 0
		return 29 if leap else 28
	return 30 if month in [4, 6, 9, 11] else 31


## The input without the time words, and without "remind me to" and dangling "at"/"on".
static func _clean(input: String, spans: Array[Vector2i]) -> String:
	spans.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x > b.x)
	var text := input
	for span in spans:
		text = text.substr(0, span.x) + " " + text.substr(span.y)
	text = " ".join(text.split(" ", false)).strip_edges()
	var lower := text.to_lower()
	for prefix in ["remind me to ", "remind me ", "to "]:
		if lower.begins_with(prefix):
			text = text.substr(prefix.length())
			lower = text.to_lower()
	for suffix in [" at", " on", " by", " in", ","]:
		if lower.ends_with(suffix):
			text = text.substr(0, text.length() - suffix.length())
			lower = text.to_lower()
	text = text.strip_edges().trim_suffix(",").trim_suffix("-").strip_edges()
	return text if not text.is_empty() else "Reminder"


static func _regex(pattern: String) -> RegEx:
	var regex := RegEx.new()
	regex.compile(pattern)
	return regex
