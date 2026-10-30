extends Node
## Self-check for the productivity tools: the plain-text reminder parser, durations,
## Reminders scheduling, the announcement when one comes due, and the notes file.
## Run this scene (F6), or godot --headless res://tests/tools_test.tscn (exit code 1 on
## failure). Reminders and notes it touches are put back afterwards.

## Friday 30 October 2026, 14:00, with the clock at UTC so results don't depend on the PC.
var NOW := Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 10, "day": 30, "hour": 14, "minute": 0, "second": 0})

var _failures := 0


func _ready() -> void:
	var stores := [SaveData.snapshot(), Settings.snapshot()]
	var saved_notes := NotesWindow.load_notes()
	var had_notes := FileAccess.file_exists(NotesWindow.PATH)
	Reminders.clear()

	_test_parser()
	_test_durations_and_descriptions()
	_test_reminders()
	_test_notes(saved_notes)
	await _test_announcement()

	# Let anything still pending (deferred calls, a queued announcement) happen first.
	for i in 2:
		await get_tree().process_frame
	SaveData.restore(stores[0])
	Settings.restore(stores[1])
	if had_notes:
		_write_notes(saved_notes)
	else:
		DirAccess.remove_absolute(NotesWindow.PATH)
	if _failures == 0:
		print("All tools checks passed.")
	else:
		printerr("%d tools check(s) failed." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _test_parser() -> void:
	_parse("call mom at 18:30", "call mom", _at(30, 18, 30))
	_parse("meeting tomorrow 9am", "meeting", _at(31, 9))
	_parse("stretch in 20 min", "stretch", NOW + 20 * 60)
	_parse("tea in 1h 30m", "tea", NOW + 90 * 60)
	_parse("in an hour check the oven", "check the oven", NOW + 3600)
	_parse("in half an hour leave", "leave", NOW + 1800)
	_parse("dentist friday 15:00", "dentist", _at(30, 15))
	_parse("dentist friday 14:00", "dentist", _at(30, 14) + 7 * 86400) # Now exactly: next week.
	_parse("gym monday", "gym", _at(30, 9) + 3 * 86400)
	_parse("meeting on wed at 10:15", "meeting", _at(30, 10, 15) + 5 * 86400)
	_parse("pay rent 01/12", "pay rent", _date(2026, 12, 1, 9))
	_parse("party 25/10", "party", _date(2027, 10, 25, 9)) # Already passed this year.
	_parse("trip 03/01/2027 7:00", "trip", _date(2027, 1, 3, 7))
	_parse("lunch at noon", "lunch", _at(31, 12)) # Noon has passed today.
	_parse("call at 9", "call", _at(31, 9))
	_parse("remind me to water the plants at 6pm", "water the plants", _at(30, 18))
	_parse("bed at 11:30pm", "bed", _at(30, 23, 30))
	_parse("12am snack", "snack", _at(31, 0))
	_parse("movie tonight", "movie", _at(30, 20))
	_parse("18h30 call", "call", _at(30, 18, 30))
	_parse("at 6pm", "Reminder", _at(30, 18))
	_check("no time means no reminder", ReminderParser.parse("buy milk", NOW, 0).is_empty())
	_check("an impossible date is rejected", ReminderParser.parse("party 31/04", NOW, 0).is_empty())
	_check("an impossible time is rejected", ReminderParser.parse("check at 25:00", NOW, 0).is_empty())
	_check("words containing day names aren't days", ReminderParser.parse("clean the fridge", NOW, 0).is_empty())
	var cet := ReminderParser.parse("call at 18:30", NOW, 3600)
	_check("times are local to the time zone", cet.due == _at(30, 18, 30) - 3600)


func _test_durations_and_descriptions() -> void:
	_check("a bare number is minutes", ReminderParser.parse_duration("10") == 600)
	_check("10 min", ReminderParser.parse_duration("10 min") == 600)
	_check("1h 30m", ReminderParser.parse_duration("1h 30m") == 5400)
	_check("1.5 h", ReminderParser.parse_duration("1.5 h") == 5400)
	_check("90 sec", ReminderParser.parse_duration("90 sec") == 90)
	_check("nonsense is 0", ReminderParser.parse_duration("soon") == 0)
	_describe(NOW + 600, "in 10 min")
	_describe(_at(30, 18, 30), "at 18:30")
	_describe(_at(31, 9), "tomorrow at 9:00")
	_describe(_at(30, 9) + 3 * 86400, "on Monday at 9:00")
	_describe(_date(2026, 12, 1, 9), "on 01/12 at 9:00")


func _test_reminders() -> void:
	var fired: Array = []
	var on_due := func(reminder: Dictionary) -> void: fired.append(reminder.text)
	Reminders.due.connect(on_due)
	var now := int(Time.get_unix_time_from_system())
	Reminders.add("later", now + 3600)
	Reminders.add("overdue", now - 10)
	Reminders.add("sooner", now + 60)
	_check("reminders are listed soonest first", Reminders.list().map(func(r: Dictionary) -> String: return r.text) == ["overdue", "sooner", "later"])
	Reminders.check_due()
	_check("only due ones fire", fired == ["overdue"])
	_check("a fired reminder is removed", Reminders.list().size() == 2)
	Reminders.remove(Reminders.list()[0].id)
	_check("remove() removes one", Reminders.list().size() == 1 and Reminders.list()[0].text == "later")
	var timer := Reminders.add_timer(300)
	_check("a timer is due after its duration", absi(int(timer.due) - (now + 300)) <= 1 and timer.kind == Reminders.KIND_TIMER)
	_check("a timer gets a label", timer.text == "5 min timer")
	_check("plain-text reminders work", not Reminders.add_from_text("stretch in 20 min").is_empty())
	_check("text without a time is refused", Reminders.add_from_text("stretch").is_empty())
	Reminders.clear()
	_check("clear() removes everything", Reminders.list().is_empty())
	Reminders.due.disconnect(on_due)


func _test_notes(original: String) -> void:
	var notes: NotesWindow = Desk.notes
	notes.open()
	_check("the notes window shows what's saved", notes._text.text == original)
	notes._text.text = "milk\neggs"
	notes.close()
	_check("closing saves the notes", NotesWindow.load_notes() == "milk\neggs")
	_check("closing hides the window", not notes.visible)


func _test_announcement() -> void:
	var pet: DesktopPet = load("res://scenes/DesktopPet.tscn").instantiate()
	add_child(pet)
	pet.setup(Rect2(0, 0, 800, 600))
	await get_tree().process_frame
	pet.state_machine.transition_to(PetStateMachine.IDLE)
	pet.position.x = 200.0
	pet.bubble.hide()

	var timer := {"kind": Reminders.KIND_TIMER, "text": "5 min timer", "due": int(Time.get_unix_time_from_system())}
	_check("a timer's message names it", pet.announcer.message_for(timer).contains("5 min timer"))
	timer.due -= 600
	_check("a late one says when it was due", pet.announcer.message_for(timer).contains("It was due at"))

	# Straight into the list, so there's no "I'll remind you" confirmation in the bubble.
	SaveData.set_value(&"tools/reminders", [{"id": "t", "text": "stretch", "due": int(Time.get_unix_time_from_system()) - 1, "kind": Reminders.KIND_REMINDER}])
	Reminders.check_due()
	await _frames(3)
	_check("a due reminder sends her to announce", pet.state_machine.current_state.name == PetStateMachine.ANNOUNCE)
	_check("and keeps her busy", pet.is_busy())
	var waited := 0.0
	while not _bubble_says(pet, "stretch") and waited < 6.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	_check("she walks to the middle first", absf(pet.position.x - 400.0) < 1.0)
	_check("then shows the reminder", _bubble_says(pet, "stretch"))
	pet.bubble.hide_message() # Click to dismiss.
	await _frames(2)
	_check("dismissing it sends her back to idle", pet.state_machine.current_state.name == PetStateMachine.IDLE and not pet.is_busy())

	pet.set_shown(false)
	Reminders.add("hidden test", int(Time.get_unix_time_from_system()) - 1)
	Reminders.check_due()
	_check("a reminder brings her back from hiding", pet.visible)
	pet.announcer._queue.clear()
	pet.queue_free()


# --- Helpers ---------------------------------------------------------------------------

## Unix time of `day` October 2026 at hour:minute (UTC), or later days via +86400.
func _at(day: int, hour: int, minute := 0) -> int:
	return _date(2026, 10, day, hour, minute) if day <= 31 else 0


func _date(year: int, month: int, day: int, hour: int, minute := 0) -> int:
	return Time.get_unix_time_from_datetime_dict({"year": year, "month": month, "day": day, "hour": hour, "minute": minute, "second": 0})


func _parse(input: String, text: String, due: int) -> void:
	var got := ReminderParser.parse(input, NOW, 0)
	var ok: bool = not got.is_empty() and got.text == text and got.due == due
	var shown := "nothing" if got.is_empty() else "\"%s\" at %s" % [got.text, Time.get_datetime_string_from_unix_time(got.due)]
	_check("\"%s\" -> \"%s\" at %s (got %s)" % [input, text, Time.get_datetime_string_from_unix_time(due), shown], ok)


func _describe(due: int, expected: String) -> void:
	var got := ReminderParser.describe(due, NOW, 0)
	_check("describe -> \"%s\" (got \"%s\")" % [expected, got], got == expected)


func _write_notes(text: String) -> void:
	var file := FileAccess.open(NotesWindow.PATH, FileAccess.WRITE)
	file.store_string(text)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _check(description: String, ok: bool) -> void:
	if ok:
		print("PASS  ", description)
	else:
		_failures += 1
		printerr("FAIL  ", description)


func _bubble_says(pet: DesktopPet, text: String) -> bool:
	return pet.bubble.visible and pet.bubble.get_node(^"Label").text.contains(text)
