extends Node
## Self-check for talking: dialogue conditions and picking, the mood check-in, Snack
## Time's daily topics, and a Conversation run with a choice. Run this scene (F6), or
## godot --headless res://tests/talk_test.tscn (exit code 1 on failure).
## Save data it touches is put back afterwards.

const SAVED_KEYS: Array[StringName] = [
	&"affection/points", &"affection/day", &"affection/gained_today", &"talk/memories",
	&"talk/mood_history", &"talk/unlocked_topics", &"talk/snack_day", &"talk/snack_offer",
	&"talk/snack_done",
]

var _failures := 0
var _pet: DesktopPet


func _ready() -> void:
	var saved := {}
	for key in SAVED_KEYS:
		saved[key] = SaveData.get_value(key)

	_test_conditions()
	_test_dialogue_data()
	_test_mood()
	_test_snack_time()
	await _test_conversation()

	for key in SAVED_KEYS:
		SaveData.set_value(key, saved[key])
	SaveData.flush()
	if _failures == 0:
		print("All talk checks passed.")
	else:
		printerr("%d talk check(s) failed." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _test_conditions() -> void:
	var context := {"time": "morning", "level": 2, "mood": "tired", "outfit": "default"}
	_check("no conditions always match", Dialogue.matches({}, context))
	_check("time matches", Dialogue.matches({"time": "morning"}, context))
	_check("time from a list matches", Dialogue.matches({"time": ["night", "morning"]}, context))
	_check("wrong time doesn't match", not Dialogue.matches({"time": "night"}, context))
	_check("level_min works", Dialogue.matches({"level_min": 2}, context) and not Dialogue.matches({"level_min": 3}, context))
	_check("level_max works", Dialogue.matches({"level_max": 2}, context) and not Dialogue.matches({"level_max": 1}, context))
	_check("mood works", Dialogue.matches({"mood": "tired"}, context) and not Dialogue.matches({"mood": "great"}, context))
	_check("all conditions must hold", not Dialogue.matches({"time": "morning", "mood": "great"}, context))
	_check("times of day", Dialogue.time_of_day(7) == "morning" and Dialogue.time_of_day(13) == "afternoon"
		and Dialogue.time_of_day(19) == "evening" and Dialogue.time_of_day(23) == "night" and Dialogue.time_of_day(3) == "night")


func _test_dialogue_data() -> void:
	for trigger in [&"idle", &"grab", &"sit", &"perch", &"pat", &"pat_end", &"first_pat", &"head", &"face",
			&"flustered", &"hands", &"annoyed", &"forgiven", &"level_up", &"talk_open", &"talk_cancel",
			&"snack_intro", &"snack_quiet", &"snack_done_all", &"snack_end", &"mood_ask", &"mood_again"]:
		_check("there are lines for '%s'" % trigger, Dialogue.has_trigger(trigger))
	var face := Dialogue.pick(&"face")
	_check("a trigger's default reaction is used", face.anim == &"surprised")
	var repeats := 0
	var last := ""
	for i in 20:
		var text: String = Dialogue.pick(&"head").text
		if text == last:
			repeats += 1
		last = text
	_check("the same line never comes twice in a row", repeats == 0)
	_check("an unknown trigger gives nothing", Dialogue.pick(&"no_such_trigger").is_empty())
	_check("a level-up line only fits its level", _all_lines_match(&"level_up", {"level": 3}, 1))


func _test_mood() -> void:
	SaveData.set_value(&"talk/mood_history", {})
	SaveData.set_value(&"affection/day", "")
	var before := Affection.get_points()
	_check("no mood before checking in", Mood.today() == "")
	Mood.record("tired")
	_check("today's mood is recorded", Mood.today() == "tired")
	_check("the first check-in of the day raises affection", Affection.get_points() == before + Mood.CHECK_IN_AFFECTION)
	Mood.record("great")
	_check("checking in again updates the mood", Mood.today() == "great")
	_check("but doesn't raise affection again", Affection.get_points() == before + Mood.CHECK_IN_AFFECTION)
	_check("mood conditions see it", Dialogue.current_context().mood == "great")


func _test_snack_time() -> void:
	var seen := PackedStringArray()
	var a := SnackTime.pick_offer("2026-01-01", 0, seen)
	_check("a day offers %d topics" % SnackTime.PER_DAY, a.size() == SnackTime.PER_DAY)
	_check("the same day gives the same offer", a == SnackTime.pick_offer("2026-01-01", 0, seen))
	var differs := false
	for day in range(2, 9):
		if SnackTime.pick_offer("2026-01-%02d" % day, 0, seen) != a:
			differs = true
	_check("the offer changes from day to day", differs)
	var gated := true
	for id in SnackTime.pick_offer("2026-01-01", 0, seen) + SnackTime.pick_offer("2026-01-02", 0, seen):
		if int(SnackTime.find_topic(id).get("min_level", 0)) > 0:
			gated = false
	_check("topics above her level aren't offered", gated)
	var all_low := PackedStringArray()
	for topic: Dictionary in SnackTime.all_topics():
		if int(topic.get("min_level", 0)) == 0 and topic.id != a[0]:
			all_low.append(topic.id)
	_check("unseen topics come first", SnackTime.pick_offer("2026-01-01", 0, all_low)[0] == a[0])

	SaveData.set_value(&"talk/snack_day", "")
	var remaining := SnackTime.remaining_today()
	_check("today has topics", remaining.size() == SnackTime.PER_DAY)
	var id: String = remaining[0].id
	var before := Affection.get_points()
	SaveData.set_value(&"affection/gained_today", 0)
	SnackTime.finish(id)
	_check("a finished topic leaves today's list", SnackTime.remaining_today().size() == SnackTime.PER_DAY - 1)
	_check("a finished topic is unlocked", SaveData.get_value(&"talk/unlocked_topics").has(id))
	_check("finishing a topic raises affection", Affection.get_points() == before + SnackTime.TOPIC_AFFECTION)
	_check("every topic has steps", SnackTime.all_topics().all(func(t: Dictionary) -> bool: return not t.get("steps", []).is_empty()))


func _test_conversation() -> void:
	_pet = load("res://scenes/DesktopPet.tscn").instantiate()
	add_child(_pet)
	_pet.setup(Rect2(0, 0, 800, 600))
	await get_tree().process_frame
	var conversation := _pet.conversation
	var actions: Array = []
	conversation.action.connect(func(action: String, value: Variant) -> void: actions.append([action, value]))
	var steps := [
		{"say": "First line"},
		{"say": "Pick one", "choices": [
			{"text": "A", "steps": [{"say": "You picked A"}]},
			{"text": "B", "do": "set_flag", "value": "b", "steps": [{"say": "You picked B", "anim": "happy"}]},
		]},
		{"say": "Last line"},
	]
	var result := [null]
	var run := func() -> void: result[0] = await conversation.run(steps)
	run.call()
	await get_tree().process_frame
	_check("a running conversation keeps her busy", _pet.is_busy())
	_check("it shows the first line", _bubble_text() == "First line")
	_pet.bubble.hide_message() # Click to continue.
	await get_tree().process_frame
	_check("then asks the question", _bubble_text() == "Pick one" and _pet.choice_menu.visible)
	_pet.choice_menu.id_pressed.emit(1)
	_pet.choice_menu.hide()
	await _frames(3)
	_check("the choice's action runs", actions == [["set_flag", "b"]])
	_check("the chosen branch plays", _bubble_text() == "You picked B")
	_pet.bubble.hide_message()
	await get_tree().process_frame
	_check("then the conversation carries on", _bubble_text() == "Last line")
	_pet.bubble.hide_message()
	await _frames(2)
	_check("it finishes", result[0] == true and not conversation.is_running() and not _pet.is_busy())

	run.call()
	await get_tree().process_frame
	_pet.bubble.hide_message()
	await get_tree().process_frame
	_pet.choice_menu.hide() # Dismissed without answering.
	await _frames(3)
	_check("dismissing a question ends it", result[0] == false and not conversation.is_running())

	run.call()
	await get_tree().process_frame
	_pet.state_machine.transition_to(PetStateMachine.DRAGGED, {"grab_offset": Vector2.ZERO})
	await _frames(2)
	_check("picking her up cancels it", result[0] == false and not conversation.is_running())


# --- Helpers ---------------------------------------------------------------------------

## Whether every line of `trigger` that fits `context` (others filled in) is exactly `count`.
func _all_lines_match(trigger: StringName, context: Dictionary, count: int) -> bool:
	var full := {"time": "morning", "level": 0, "mood": "", "outfit": "default"}
	full.merge(context, true)
	var fitting := 0
	for line: Dictionary in Dialogue._lines.get(trigger, []):
		if Dialogue.matches(line.when, full):
			fitting += 1
	return fitting == count


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
