extends Node
## Self-check for touch: body-part regions, gestures (click, double-click, drag, headpat),
## reactions and affection. Run this scene (F6) and read the Output, or from a terminal:
## godot --headless res://tests/pet_test.tscn (exit code 1 on failure).
## Save data it touches (affection, memories) is put back afterwards.

var _failures := 0
var _log: Array[String] = []
var _pet: DesktopPet
var _gestures: PetGestures


func _ready() -> void:
	var stores := [SaveData.snapshot(), Settings.snapshot()]

	_pet = load("res://scenes/DesktopPet.tscn").instantiate()
	add_child(_pet)
	_pet.setup(Rect2(0, 0, 800, 600))
	await _frames(2)
	# Keep her still and feed input by hand.
	_pet.state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	_pet.set_process_unhandled_input(false)
	_gestures = _pet.gestures
	_gestures.process_mode = Node.PROCESS_MODE_DISABLED
	for sig in ["drag_started", "clicked", "double_clicked", "pat_started", "patted", "pat_ended"]:
		_gestures.connect(sig, func(_a = null) -> void: _log.append(sig))

	_test_body_parts()
	_test_gestures()
	await _test_reactions()
	_test_affection()

	# Let anything still pending (deferred calls, a queued announcement) happen first.
	for i in 2:
		await get_tree().process_frame
	SaveData.restore(stores[0])
	Settings.restore(stores[1])
	if _failures == 0:
		print("All pet checks passed.")
	else:
		printerr("%d pet check(s) failed." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _test_body_parts() -> void:
	for part in [&"hands", &"face", &"head", &"chest", &"skirt"]:
		var point := _centre_of(part)
		_check("the middle of the %s region is %s" % [part, part], _pet.get_body_part(point) == part)
	var rect := _pet.get_hit_rect()
	_check("a corner of her hit box is just body", _pet.get_body_part(rect.position + Vector2(2, rect.size.y * 0.6)) == BodyParts.BODY)


func _test_gestures() -> void:
	var at := _centre_of(&"chest")
	var head := _centre_of(&"head")
	_case("click", "clicked", func() -> void:
		_press(at); _step(0.05); _release(at); _step(0.6))
	_case("double-click", "double_clicked", func() -> void:
		_press(at); _release(at); _step(0.2); _press(at); _release(at); _step(0.6))
	_case("slow second click is two clicks", "clicked,clicked", func() -> void:
		_press(at); _release(at); _step(0.6); _press(at); _release(at); _step(0.6))
	_case("moving past the threshold drags", "drag_started", func() -> void:
		_press(at); _move(at + Vector2(10, 0)); _release(at))
	_case("a small wiggle is still a click", "clicked", func() -> void:
		_press(at); _move(at + Vector2(3, 0)); _release(at); _step(0.6))
	_case("holding still drags", "drag_started", func() -> void:
		_press(at); _step(0.1); _step(0.15); _release(at))
	_case("a click then a hold drops the click", "drag_started", func() -> void:
		_press(at); _release(at); _step(0.1); _press(at); _step(0.3))
	_case("rubbing her head is a headpat", "pat_started,patted,patted,pat_ended", func() -> void:
		_press(head); _move(head + Vector2(12, 0)); _move(head + Vector2(20, 0))
		_move(head + Vector2(5, 0)); _move(head + Vector2(25, 0)); _step(0.5); _release(head))
	_case("moving up from her head still drags", "drag_started", func() -> void:
		_press(head); _move(head + Vector2(2, -12)); _release(head))
	_case("rubbing her chest drags", "drag_started", func() -> void:
		_press(at); _move(at + Vector2(12, 0)); _release(at))


func _test_reactions() -> void:
	var face := _centre_of(&"face")
	var reactions := _pet.reactions
	for i in reactions.annoy_pokes - 1:
		reactions._on_clicked(face)
	_check("a few face pokes don't annoy her", not reactions.is_annoyed())
	await _frames(2)
	_check("a face poke plays 'surprised'", _reaction_anim() == "surprised")
	var before := Affection.get_points()
	reactions._on_clicked(face)
	_check("one poke too many annoys her", reactions.is_annoyed())
	_check("getting annoyed costs affection", Affection.get_points() == maxi(0, before - reactions.annoyed_penalty))
	await _frames(2)
	_check("annoyed, she pouts", _reaction_anim() == "pout")
	reactions._on_pat_started()
	_check("a headpat forgives her", not reactions.is_annoyed())
	await _frames(2)
	_check("patting plays the 'pat' loop", _reaction_anim() == "pat")
	reactions._on_pat_ended()
	SaveData.set_value(&"talk/memories", {})
	reactions._on_pat_started()
	reactions._on_pat_ended()
	_check("the first headpat is remembered", SaveData.get_value(&"talk/memories").has("first_headpat"))


func _test_affection() -> void:
	var today := Time.get_date_string_from_system()
	SaveData.set_value(&"affection/day", today)
	SaveData.set_value(&"affection/gained_today", Affection.DAILY_GAIN_CAP - 1)
	_check("gains stop at the daily cap", Affection.add(5) == 1 and Affection.add(1) == 0)
	SaveData.set_value(&"affection/day", "2000-01-01")
	_check("a new day resets the cap", Affection.add(1) == 1)
	SaveData.set_value(&"affection/points", 3)
	_check("affection never goes below zero", Affection.add(-10) == -3 and Affection.get_points() == 0)
	_check("levels follow the thresholds",
		Affection.level_for(0) == 0 and Affection.level_for(Affection.LEVELS[1]) == 1 and Affection.level_for(Affection.LEVELS[1] - 1) == 0)
	var levels: Array[int] = []
	var on_level := func(level: int) -> void: levels.append(level)
	Affection.level_up.connect(on_level)
	SaveData.set_value(&"affection/points", Affection.LEVELS[1] - 1)
	SaveData.set_value(&"affection/gained_today", 0)
	Affection.add(1)
	Affection.level_up.disconnect(on_level)
	_check("crossing a threshold levels up", levels == [1])
	_check("a level-up is remembered", SaveData.get_value(&"talk/memories").has("affection_level_1"))


# --- Helpers ---------------------------------------------------------------------------

func _centre_of(part: StringName) -> Vector2:
	for region: Array in BodyParts.REGIONS:
		if region[0] == part:
			var polygon := BodyParts.polygon(_pet.sprite, region[1], region[2])
			var sum := Vector2.ZERO
			for p in polygon:
				sum += p
			return sum / polygon.size()
	return Vector2.ZERO


func _reaction_anim() -> String:
	var entry := _pet.sprite.get_animation_state().get_current(DesktopPet.REACTION_TRACK)
	return entry.get_animation().get_name() if entry else ""


func _case(name: String, expected: String, body: Callable) -> void:
	_log.clear()
	_gestures.cancel()
	_log.clear()
	body.call()
	var got := ",".join(_log)
	_check("%s (got [%s])" % [name, got], got == expected)
	Input.parse_input_event(_button(Vector2.ZERO, false))
	Input.flush_buffered_events()


func _button(position: Vector2, down: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.position = position
	return event


func _press(position: Vector2) -> void:
	_send(_button(position, true))


func _release(position: Vector2) -> void:
	_send(_button(position, false))


func _move(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	_gestures.handle_input(event)


## Also updates Input's button state, which the gestures check for lost releases.
func _send(event: InputEventMouseButton) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	_gestures.handle_input(event)


func _step(delta: float) -> void:
	_gestures._process(delta)


func _check(description: String, ok: bool) -> void:
	if ok:
		print("PASS  ", description)
	else:
		_failures += 1
		printerr("FAIL  ", description)


## Reactions are queued behind an empty animation, so they show up after the sprite's
## next update (process_frame fires before nodes process).
func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
