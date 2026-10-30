extends Node
## Self-check for the desk extras: repeating reminders and countdowns, the Reminders
## window, the folder watcher (with a real folder), and smarter perching (free spots,
## hopping onto windows, dodging dragged windows). Media keys aren't pressed: that would
## pause your music. Run this scene (F6), or godot --headless res://tests/desk_test.tscn
## (exit code 1 on failure). Settings and save data are put back afterwards.

## Friday 30 October 2026, 14:00, UTC.
var NOW := Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 10, "day": 30, "hour": 14, "minute": 0, "second": 0})

var _failures := 0


func _ready() -> void:
	var stores := [SaveData.snapshot(), Settings.snapshot()]
	Settings.set_value(&"schedule/bedtime", "")
	Reminders.clear()

	_test_repeats()
	_test_reminders()
	_test_reminders_window()
	await _test_folder_watcher()
	_test_spots()
	await _test_hop_and_dodge()

	for i in 2:
		await get_tree().process_frame
	SaveData.restore(stores[0])
	Settings.restore(stores[1])
	if _failures == 0:
		print("All desk checks passed.")
	else:
		printerr("%d desk check(s) failed." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _test_repeats() -> void:
	var daily := ReminderParser.parse("water the plants every day at 8", NOW, 0)
	_check("'every day' repeats daily", daily.repeat == "daily" and daily.text == "water the plants" and daily.due == NOW + 18 * 3600)
	var weekdays := ReminderParser.parse("standup weekdays 9:30", NOW, 0)
	_check("'weekdays' repeats on weekdays", weekdays.repeat == "weekdays" and weekdays.text == "standup")
	var monday := ReminderParser.parse("every monday gym", NOW, 0)
	_check("'every monday' repeats weekly from Monday", monday.repeat == "weekly" and monday.text == "gym" and monday.due == NOW - 5 * 3600 + 3 * 86400)
	_check("no repeat words, no repeat", ReminderParser.parse("call mom at 18:30", NOW, 0).repeat == "")
	var friday_9 := NOW - 5 * 3600
	_check("daily moves on a day", ReminderParser.next_due(friday_9, "daily", NOW, 0) == friday_9 + 86400)
	_check("weekdays skip the weekend", ReminderParser.next_due(friday_9, "weekdays", NOW, 0) == friday_9 + 3 * 86400)
	_check("weekly moves on a week", ReminderParser.next_due(friday_9, "weekly", NOW, 0) == friday_9 + 7 * 86400)
	_check("missed days are skipped", ReminderParser.next_due(friday_9 - 10 * 86400, "daily", NOW, 0) == friday_9 + 86400)


func _test_reminders() -> void:
	var now := int(Time.get_unix_time_from_system())
	var fired: Array = []
	var on_due := func(reminder: Dictionary) -> void: fired.append(reminder.text)
	Reminders.due.connect(on_due)
	var daily := Reminders.add("stretch", now - 5, Reminders.KIND_REMINDER, "daily")
	Reminders.check_due()
	_check("a repeating reminder fires", fired == ["stretch"])
	var kept := Reminders.list()
	_check("and stays, moved to tomorrow", kept.size() == 1 and int(kept[0].due) == int(daily.due) + 86400)
	Reminders.due.disconnect(on_due)
	Reminders.update(daily.id, {"text": "big stretch", "countdown": true})
	_check("update() changes fields", Reminders.list()[0].text == "big stretch")
	_check("the nearest countdown is found", Reminders.next_countdown().text == "big stretch")
	_check("countdowns read nicely", RemindersWindow.countdown_text(now + 3 * 86400, now) == "3 days to go"
		and RemindersWindow.countdown_text(now, now) == "today!")
	Reminders.clear()


func _test_reminders_window() -> void:
	var window: RemindersWindow = Desk.reminders
	window.open()
	_check("an empty list says so", window._list.item_count == 1 and window._list.is_item_disabled(0))
	window._on_add("nonsense")
	_check("text without a time is refused", Reminders.list().is_empty() and not window._status.text.is_empty())
	window._on_add("dentist friday 15:00")
	_check("adding from the box lists it", Reminders.list().size() == 1 and window._list.get_item_text(0).contains("dentist"))
	window._on_selected(0)
	window._text.text = "dentist (bring card)"
	window._when.text = "tomorrow 10:00"
	window._repeat.select(3)
	window._countdown.button_pressed = true
	window._on_save()
	var edited: Dictionary = Reminders.list()[0]
	_check("the editor saves changes", edited.text == "dentist (bring card)" and edited.repeat == "weekly" and edited.countdown)
	_check("including a new time", ReminderParser.describe(int(edited.due)) == "tomorrow at 10:00")
	_check("the list shows repeat and countdown", window._list.get_item_text(0).contains("every week") and window._list.get_item_text(0).contains("tomorrow!"))
	window._when.text = "whenever"
	window._on_save()
	_check("an unreadable time isn't saved", window._status.text.begins_with("Couldn't"))
	window._on_delete()
	_check("delete removes it", Reminders.list().is_empty())
	window.close()


func _test_folder_watcher() -> void:
	_check("downloads in progress don't count", not FolderWatcher.is_finished("movie.mp4.crdownload")
		and not FolderWatcher.is_finished("song.part") and not FolderWatcher.is_finished("~$doc.docx"))
	_check("finished files do", FolderWatcher.is_finished("movie.mp4") and FolderWatcher.is_finished("report.pdf"))
	var folder := ProjectSettings.globalize_path("user://watch_test")
	DirAccess.make_dir_recursive_absolute(folder)
	var watcher: FolderWatcher
	var pet: DesktopPet = load("res://scenes/DesktopPet.tscn").instantiate()
	add_child(pet)
	pet.setup(Rect2(0, 0, 800, 600))
	watcher = pet.get_node(^"FolderWatcher")
	pet.state_machine.process_mode = Node.PROCESS_MODE_DISABLED # No idle chatter over the line.
	pet.game_watcher.process_mode = Node.PROCESS_MODE_DISABLED
	var seen: Array = []
	watcher.file_appeared.connect(func(file_name: String) -> void: seen.append(file_name))
	Settings.set_value(&"tools/watch_folder", folder)
	_check("the setting starts the watcher", watcher.watching == folder)
	await get_tree().create_timer(3.0).timeout # PowerShell takes a moment to start.
	_write(folder + "/movie.mp4.crdownload")
	await get_tree().create_timer(0.5).timeout
	DirAccess.rename_absolute(folder + "/movie.mp4.crdownload", folder + "/movie.mp4")
	var waited := 0.0
	while seen.is_empty() and waited < 6.0:
		await get_tree().create_timer(0.2).timeout
		waited += 0.2
	_check("a finished download is noticed, not its temporary file", seen == ["movie.mp4"])
	await get_tree().create_timer(FolderWatcher.GATHER_TIME + 0.3).timeout
	_check("and she says so", pet.bubble.visible and pet.bubble.get_node(^"Label").text.contains("movie.mp4"))
	Settings.set_value(&"tools/watch_folder", "")
	_check("clearing the setting stops it", watcher.watching == "")
	DirAccess.remove_absolute(folder + "/movie.mp4")
	DirAccess.remove_absolute(folder)
	pet.queue_free()
	await get_tree().process_frame


func _test_spots() -> void:
	var tracker := WindowTracker.new() # Not in the tree: no helper, windows set by hand.
	tracker.windows = [
		{"id": 1, "rect": Rect2(300, 100, 200, 300)}, # In front.
		{"id": 2, "rect": Rect2(100, 200, 500, 300)}, # Behind, top partly covered by 1.
	]
	_check("an open title bar is free", tracker.is_spot_free(2, 150.0))
	_check("one covered by a window in front isn't", not tracker.is_spot_free(2, 400.0))
	_check("a closed window has no free spot", not tracker.is_spot_free(3, 150.0))
	var target := tracker.find_hop_target(Vector2(450, 500), Vector2(80, 480), 12.0)
	_check("she hops onto the frontmost window", target.id == 1 and target.x == 450.0)
	_check("a window too high up is skipped, and a covered spot isn't used",
		tracker.find_hop_target(Vector2(450, 500), Vector2(180, 480), 12.0).is_empty())
	target = tracker.find_hop_target(Vector2(150, 500), Vector2(180, 480), 12.0)
	_check("a free spot on a window behind is", target.id == 2 and target.x == 150.0)
	tracker.free()
	var hit := Rect2(400, 400, 92, 176)
	var before := {1: Rect2(100, 300, 200, 200)}
	_check("a still window isn't dodged", not WindowDodger.moving_over([{"id": 1, "rect": Rect2(380, 300, 200, 200)}], {1: Rect2(380, 300, 200, 200)}, hit, -1))
	_check("a moving one over her is", WindowDodger.moving_over([{"id": 1, "rect": Rect2(380, 300, 200, 200)}], before, hit, -1))
	_check("not the one she's sitting on", not WindowDodger.moving_over([{"id": 1, "rect": Rect2(380, 300, 200, 200)}], before, hit, 1))


func _test_hop_and_dodge() -> void:
	var pet: DesktopPet = load("res://scenes/DesktopPet.tscn").instantiate()
	add_child(pet)
	pet.setup(Rect2(0, 0, 800, 600))
	pet.game_watcher.process_mode = Node.PROCESS_MODE_DISABLED
	var tracker := pet.window_tracker
	# Let the helper's first real snapshot arrive, so it doesn't replace the fake one.
	await _signal_or_timeout(tracker.updated, 8.0)
	tracker.windows = [{"id": 77, "rect": Rect2(300, 300, 300, 200)}]
	pet.state_machine.transition_to(PetStateMachine.IDLE)
	pet.position = Vector2(350, 600)
	pet.state_machine.get_node(^"Idle")._hop()
	_check("she hops", pet.state_machine.current_state.name == PetStateMachine.HOP)
	var hop: Node = pet.state_machine.get_node(^"Hop")
	await get_tree().create_timer(hop.duration + 0.1).timeout
	_check("and lands on the title bar", pet.state_machine.current_state.name == PetStateMachine.PERCHED
		and pet.position.is_equal_approx(Vector2(350, 300)))

	pet.state_machine.transition_to(PetStateMachine.IDLE)
	var dodger: WindowDodger = pet.get_node(^"WindowDodger")
	var hit := pet.get_hit_rect()
	dodger._previous = {5: Rect2(hit.position - Vector2(400, 0), Vector2(300, 300))}
	tracker.windows = [{"id": 5, "rect": Rect2(hit.position - Vector2(100, 0), Vector2(300, 300))}]
	tracker.updated.emit()
	await get_tree().create_timer(0.3).timeout
	_check("a window dragged over her fades her out", dodger.dodging and pet.modulate.a < 0.5)
	await get_tree().create_timer(dodger.return_after + 0.5).timeout
	_check("she comes back once it's stopped", not dodger.dodging)
	pet.queue_free()


# --- Helpers ---------------------------------------------------------------------------

func _signal_or_timeout(sig: Signal, seconds: float) -> void:
	var done := [false]
	sig.connect(func() -> void: done[0] = true, CONNECT_ONE_SHOT)
	var waited := 0.0
	while not done[0] and waited < seconds:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1


func _write(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("test")
	file.close()


func _check(description: String, ok: bool) -> void:
	if ok:
		print("PASS  ", description)
	else:
		_failures += 1
		printerr("FAIL  ", description)
