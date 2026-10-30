extends Node
## Autoload `Reminders`: everything she keeps time for (reminders, timers, alarms), kept
## in SaveData's tools/reminders. Each one is {"id", "text", "due" (unix time), "kind",
## "repeat" ("", "daily", "weekdays", "weekly"), "countdown" (she counts down the days)}.
## A repeating one is moved to its next time when it fires instead of being removed.
## Due times are checked against the wall clock every second, so a reminder still fires
## after the PC slept, and one that came due while the app was closed fires at startup.

## Emitted after a reminder is added (by any means).
signal added(reminder: Dictionary)
## Emitted when a reminder comes due; it's already been removed from the list (or moved
## on to its next time, if it repeats).
signal due(reminder: Dictionary)

const KIND_REMINDER := "reminder"
const KIND_TIMER := "timer"
const KIND_ALARM := "alarm"
const KEY := &"tools/reminders"

var _check_timer: Timer
var _counter := 0


func _ready() -> void:
	_check_timer = Timer.new()
	_check_timer.wait_time = 1.0
	_check_timer.timeout.connect(check_due)
	add_child(_check_timer)
	_check_timer.start()
	# Let the pet connect first, then fire anything missed while closed.
	check_due.call_deferred()


func add(text: String, due_time: int, kind := KIND_REMINDER, repeat := "") -> Dictionary:
	_counter += 1
	var reminder := {
		"id": "%d-%d" % [Time.get_ticks_usec(), _counter],
		"text": text,
		"due": due_time,
		"kind": kind,
		"repeat": repeat,
		"countdown": false,
	}
	var list: Array = SaveData.get_value(KEY)
	list.append(reminder)
	SaveData.set_value(KEY, list)
	added.emit(reminder)
	return reminder


## Adds a reminder from plain text (see ReminderParser). Returns it, or {} if no time
## could be read from `input`.
func add_from_text(input: String) -> Dictionary:
	var parsed := ReminderParser.parse(input)
	if parsed.is_empty():
		return {}
	return add(parsed.text, parsed.due, KIND_REMINDER, parsed.get("repeat", ""))


func add_timer(seconds: int, label := "") -> Dictionary:
	if label.is_empty():
		label = "%d min timer" % roundi(seconds / 60.0) if seconds >= 60 else "%d sec timer" % seconds
	return add(label, int(Time.get_unix_time_from_system()) + seconds, KIND_TIMER)


## Every pending reminder, soonest first.
func list() -> Array:
	var pending: Array = SaveData.get_value(KEY)
	pending.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.due < b.due)
	return pending


## Changes some fields of a reminder (text, due, repeat, countdown).
func update(id: String, changes: Dictionary) -> void:
	var pending: Array = SaveData.get_value(KEY)
	for reminder: Dictionary in pending:
		if reminder.id == id:
			reminder.merge(changes, true)
	SaveData.set_value(KEY, pending)


## The countdown reminder due soonest, or {}.
func next_countdown() -> Dictionary:
	for reminder: Dictionary in list():
		if reminder.get("countdown", false):
			return reminder
	return {}


func remove(id: String) -> void:
	var pending: Array = SaveData.get_value(KEY)
	SaveData.set_value(KEY, pending.filter(func(r: Dictionary) -> bool: return r.id != id))


func clear() -> void:
	SaveData.set_value(KEY, [])


## Fires everything whose time has come (repeating ones move on to their next time).
## Runs every second; call it to check now.
func check_due() -> void:
	var now := int(Time.get_unix_time_from_system())
	var pending: Array = SaveData.get_value(KEY)
	var fired := pending.filter(func(r: Dictionary) -> bool: return int(r.due) <= now)
	if fired.is_empty():
		return
	var kept := pending.filter(func(r: Dictionary) -> bool: return int(r.due) > now)
	for reminder: Dictionary in fired:
		if not reminder.get("repeat", "").is_empty():
			var next := reminder.duplicate()
			next.due = ReminderParser.next_due(int(reminder.due), reminder.repeat, now)
			kept.append(next)
	SaveData.set_value(KEY, kept)
	fired.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.due < b.due)
	for reminder: Dictionary in fired:
		due.emit(reminder)
