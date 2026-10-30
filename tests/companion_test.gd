extends Node
## Self-check for the companion features: wardrobe unlocks and the daily streak, the
## Wardrobe and Memories windows, talking about feelings, tucking her in, and greetings.
## Run this scene (F6), or godot --headless res://tests/companion_test.tscn (exit code 1
## on failure). Settings and save data it touches are put back afterwards.

var _failures := 0
var _pet: DesktopPet


func _ready() -> void:
	var stores := [SaveData.snapshot(), Settings.snapshot()]
	Settings.set_value(&"schedule/bedtime", "")
	SaveData.set_value(&"talk/memories", {})
	SaveData.set_value(&"talk/unlocked_topics", PackedStringArray())
	SaveData.set_value(&"affection/points", 0)
	SaveData.set_value(&"stats/best_streak", 0)

	_test_unlocks()
	_test_streak()
	_pet = load("res://scenes/DesktopPet.tscn").instantiate()
	add_child(_pet)
	_pet.setup(Rect2(0, 0, 800, 600))
	_pet.game_watcher.process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().process_frame
	_test_wardrobe_window()
	await _test_memories()
	await _test_feelings()
	await _test_tuck_in()
	_test_greetings()

	# Let anything still pending (deferred calls, a queued announcement) happen first.
	for i in 2:
		await get_tree().process_frame
	SaveData.restore(stores[0])
	Settings.restore(stores[1])
	if _failures == 0:
		print("All companion checks passed.")
	else:
		printerr("%d companion check(s) failed." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _test_unlocks() -> void:
	_check("default items are always unlocked", Unlocks.is_unlocked("outfit/default") and Unlocks.is_unlocked("bedding/default"))
	_check("the beret needs affection", not Unlocks.is_unlocked("hat/beret") and Unlocks.missing("hat/beret").contains("affection level 2"))
	_check("sunglasses need a streak", Unlocks.missing("glasses/sunglasses").contains("3-day streak"))
	_check("round glasses need topics", Unlocks.missing("glasses/round").contains("3 Snack Time topics"))
	_check("unknown items are locked", not Unlocks.is_unlocked("hat/crown"))
	var announced: Array = []
	var on_unlock := func(item: String, _title: String) -> void: announced.append(item)
	Unlocks.item_unlocked.connect(on_unlock)
	SaveData.set_value(&"wardrobe/seen", Unlocks.unlocked_items())
	SaveData.set_value(&"affection/points", Affection.LEVELS[2])
	Unlocks.check()
	_check("reaching a level unlocks the beret", Unlocks.is_unlocked("hat/beret") and announced == ["hat/beret"])
	Unlocks.check()
	_check("an unlock is announced once", announced == ["hat/beret"])
	SaveData.set_value(&"talk/memories", {"first_sleep": 1})
	Unlocks.check()
	_check("a memory unlocks the nightcap", announced.has("hat/nightcap"))
	Unlocks.item_unlocked.disconnect(on_unlock)
	Settings.set_value(&"wardrobe/glasses", "round")
	_check("a locked choice falls back to nothing", Wardrobe.chosen("glasses") == "")
	Settings.set_value(&"wardrobe/hat", "beret")
	_check("an unlocked choice is worn", Wardrobe.chosen("hat") == "beret")
	Settings.set_value(&"wardrobe/glasses", "")
	Settings.set_value(&"wardrobe/hat", "")


func _test_streak() -> void:
	var day := 86400
	var now := int(Time.get_unix_time_from_system()) + ReminderParser.system_bias()
	SaveData.set_value(&"stats/last_day", Time.get_date_string_from_unix_time(now - day))
	SaveData.set_value(&"stats/streak", 4)
	Unlocks.update_streak()
	_check("coming back the next day continues the streak", SaveData.get_value(&"stats/streak") == 5)
	_check("the best streak follows", SaveData.get_value(&"stats/best_streak") == 5)
	Unlocks.update_streak()
	_check("twice the same day counts once", SaveData.get_value(&"stats/streak") == 5)
	SaveData.set_value(&"stats/last_day", Time.get_date_string_from_unix_time(now - 3 * day))
	Unlocks.update_streak()
	_check("a gap starts over", SaveData.get_value(&"stats/streak") == 1 and SaveData.get_value(&"stats/best_streak") == 5)


func _test_wardrobe_window() -> void:
	SaveData.set_value(&"stats/best_streak", 0)
	var window: WardrobeWindow = Desk.wardrobe
	window.open()
	var glasses: OptionButton = window._pickers["glasses"]
	_check("optional categories offer None", glasses.get_item_text(0) == "None")
	var sunglasses := _index_of(glasses, "sunglasses")
	_check("locked items are listed but disabled", sunglasses >= 0 and glasses.is_item_disabled(sunglasses)
		and glasses.get_item_text(sunglasses).contains("locked") and glasses.get_item_tooltip(sunglasses).contains("streak"))
	_check("rare items get a star", glasses.get_item_text(sunglasses).contains("★"))
	var hats: OptionButton = window._pickers["hat"]
	hats.select(_index_of(hats, "beret"))
	window._on_picked(hats.selected, "hat")
	var preview_hat := window._preview.get_skeleton().find_slot("hat").get_attachment()
	_check("the preview wears the pick", preview_hat != null)
	window._save()
	_check("saving sets the wardrobe", Settings.get_value(&"wardrobe/hat") == "beret" and not window.visible)
	_check("and she wears it", _pet.wardrobe.worn.has("hat/beret"))
	Settings.set_value(&"wardrobe/hat", "")


func _test_memories() -> void:
	SaveData.set_value(&"talk/memories", {"first_headpat": 1, "first_sleep": 1})
	SaveData.set_value(&"talk/unlocked_topics", PackedStringArray(["rainy_days"]))
	var window: MemoriesWindow = Desk.memories
	Desk.open_memories(_pet)
	var titles := PackedStringArray()
	for i in window._list.item_count:
		titles.append(window._list.get_item_text(i).strip_edges())
	_check("milestones and topics are listed under headings",
		titles == PackedStringArray(["Milestones", "The first headpat", "Good night", "Snack Time", "Rainy days"]))
	_check("headings can't be picked", window._list.is_item_disabled(0))
	var hidden := MemoriesWindow.all_memories().size() - 2 + SnackTime.all_topics().size() - 1
	_check("it says how many are left", window._count.text == "%d more to discover." % hidden)
	window._replay(1)
	await get_tree().process_frame
	_check("replaying plays it in her bubble", _pet.conversation.is_running() and _bubble_text().contains("patted my head"))
	_pet.conversation.cancel()
	await _frames(2)


func _test_feelings() -> void:
	SaveData.set_value(&"affection/gained_today", 0)
	SaveData.set_value(&"affection/day", Time.get_date_string_from_system())
	var before := Affection.get_points()
	var finished := [null]
	(func() -> void: finished[0] = await _pet.conversation.run(Dialogue.load_json(TalkMenu.FEELINGS_PATH).steps)).call()
	await get_tree().process_frame
	_check("feelings start with a question", _pet.choice_menu.visible and _pet.choice_menu.item_count == 5)
	_pet.choice_menu.id_pressed.emit(3) # "I'm proud of myself!"
	_pet.choice_menu.hide()
	for i in 4:
		await _frames(3)
		_pet.bubble.hide_message()
	await _frames(3)
	_check("talking it through finishes", finished[0] == true)
	_check("and is remembered", SaveData.get_value(&"talk/memories").has("first_feelings"))
	_check("and raises affection", Affection.get_points() == before + 1)


func _test_tuck_in() -> void:
	var machine := _pet.state_machine
	machine.transition_to(PetStateMachine.IDLE)
	_pet.sleep_schedule.doze_off()
	_check("past her limit she dozes off without a blanket", _pet.is_dozing() and _attachment("blanket") == "")
	await _frames(2)
	_pet.reactions._on_clicked(_pet.get_hit_rect().get_center())
	await _frames(2)
	_check("a click tucks her in", not _pet.is_dozing() and machine.current_state.name == PetStateMachine.SLEEPING)
	_check("with her blanket", _attachment("blanket") == "blanket")
	_check("and it's remembered", SaveData.get_value(&"talk/memories").has("first_tuck_in"))
	var clock := Time.get_time_dict_from_system()
	var hours_ago := func(hours: int) -> String: return "%02d:%02d" % [posmod(clock.hour - hours, 24), clock.minute]
	Settings.set_value(&"schedule/bedtime", hours_ago.call(3))
	_check("three hours past bedtime is past the limit", SleepSchedule.past_hard_limit())
	Settings.set_value(&"schedule/bedtime", hours_ago.call(1))
	_check("one hour past isn't", not SleepSchedule.past_hard_limit())
	Settings.set_value(&"schedule/bedtime", "")
	machine.transition_to(PetStateMachine.IDLE)


func _test_greetings() -> void:
	var greeter: Greeter = _pet.get_node(^"Greeter")
	_pet.bubble.hide()
	greeter.greet()
	_check("she says hello", _pet.bubble.visible and not _bubble_text().is_empty())
	_pet.bubble.hide()
	greeter._last_wall -= 3600.0 # As if the PC had slept for an hour.
	greeter._process(0.016)
	_check("waking the PC gets a welcome back", _pet.bubble.visible)


# --- Helpers ---------------------------------------------------------------------------

func _index_of(picker: OptionButton, value: String) -> int:
	for i in picker.item_count:
		if picker.get_item_metadata(i) == value:
			return i
	return -1


func _attachment(slot: String) -> String:
	var attachment := _pet.sprite.get_skeleton().find_slot(slot).get_attachment()
	return attachment.get_attachment_name() if attachment else ""


func _bubble_text() -> String:
	return _pet.bubble.get_node(^"Label").text if _pet.bubble.visible else ""


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _check(description: String, ok: bool) -> void:
	if ok:
		print("PASS  ", description)
	else:
		_failures += 1
		printerr("FAIL  ", description)
