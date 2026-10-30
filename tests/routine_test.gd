extends Node
## Self-check for her daily routine: the bedtime schedule, sleeping, the wardrobe's
## skins, and watching games. Run this scene (F6), or
## godot --headless res://tests/routine_test.tscn (exit code 1 on failure).
## Settings it touches are put back afterwards.

const SAVED_SETTINGS: Array[StringName] = [
	&"schedule/bedtime", &"schedule/wake_time", &"wardrobe/hat", &"wardrobe/glasses",
	&"wardrobe/outfit", &"games/whitelist", &"games/blacklist",
]

var _failures := 0
var _pet: DesktopPet


func _ready() -> void:
	var saved := {}
	for key in SAVED_SETTINGS:
		saved[key] = Settings.get_value(key)
	# Start in the daytime whatever the real clock says: no schedule.
	Settings.set_value(&"schedule/bedtime", "")

	_test_phases()
	_test_games()
	_pet = load("res://scenes/DesktopPet.tscn").instantiate()
	add_child(_pet)
	_pet.setup(Rect2(0, 0, 800, 600))
	_pet.game_watcher.process_mode = Node.PROCESS_MODE_DISABLED
	await _frames(2)
	await _test_wardrobe()
	await _test_sleep()
	await _test_watching()

	for key in SAVED_SETTINGS:
		Settings.set_value(key, saved[key])
	Settings.flush()
	if _failures == 0:
		print("All routine checks passed.")
	else:
		printerr("%d routine check(s) failed." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _test_phases() -> void:
	var bed := 23 * 60
	var wake := 7 * 60
	var phase := func(h: int, m: int) -> int: return SleepSchedule.phase_at(h * 60 + m, bed, wake)
	_check("midday is day", phase.call(12, 0) == SleepSchedule.Phase.DAY)
	_check("two hours before bedtime winds down", phase.call(21, 0) == SleepSchedule.Phase.WIND_DOWN)
	_check("just before bedtime still winds down", phase.call(22, 59) == SleepSchedule.Phase.WIND_DOWN)
	_check("bedtime is night", phase.call(23, 0) == SleepSchedule.Phase.NIGHT)
	_check("past midnight is night", phase.call(3, 0) == SleepSchedule.Phase.NIGHT)
	_check("wake time is day", phase.call(7, 0) == SleepSchedule.Phase.DAY)
	_check("a bedtime after midnight works", SleepSchedule.phase_at(30, 60, 8 * 60) == SleepSchedule.Phase.WIND_DOWN
		and SleepSchedule.phase_at(23 * 60 + 30, 60, 8 * 60) == SleepSchedule.Phase.WIND_DOWN
		and SleepSchedule.phase_at(2 * 60, 60, 8 * 60) == SleepSchedule.Phase.NIGHT)
	_check("an empty bedtime turns it off", SleepSchedule.current_phase() == SleepSchedule.Phase.DAY)
	Settings.set_value(&"schedule/bedtime", "nonsense")
	_check("an unreadable bedtime turns it off", SleepSchedule.current_phase() == SleepSchedule.Phase.DAY)
	Settings.set_value(&"schedule/bedtime", "")


func _test_games() -> void:
	var none := PackedStringArray()
	_check("a full-screen app is a game", GameWatcher.is_game({"exe": "game.exe", "fullscreen": true}, none, none))
	_check("a windowed app isn't", not GameWatcher.is_game({"exe": "game.exe", "fullscreen": false}, none, none))
	_check("the desktop isn't", not GameWatcher.is_game({}, none, none))
	_check("the whitelist counts even windowed", GameWatcher.is_game({"exe": "Game.exe", "fullscreen": false}, PackedStringArray(["game"]), none))
	_check("the blacklist never counts", not GameWatcher.is_game({"exe": "vlc.exe", "fullscreen": true}, none, PackedStringArray(["VLC.EXE"])))


func _test_wardrobe() -> void:
	var wardrobe := _pet.wardrobe
	_check("daytime: just bedding", wardrobe.worn == PackedStringArray(["bedding/default"]))
	Settings.set_value(&"wardrobe/glasses", "round")
	Settings.set_value(&"wardrobe/hat", "nightcap")
	_check("glasses and a hat from the settings", wardrobe.worn == PackedStringArray(["hat/nightcap", "glasses/round", "bedding/default"]))
	_check("the hat is on her head", _attachment("hat") == "hat" and _attachment("glasses") == "glasses")
	Settings.set_value(&"wardrobe/glasses", "")
	Settings.set_value(&"wardrobe/hat", "")
	Settings.set_value(&"wardrobe/outfit", "no_such_outfit")
	_check("an outfit without a skin adds nothing", wardrobe.worn == PackedStringArray(["bedding/default"]))
	Settings.set_value(&"wardrobe/outfit", "default")
	_check("pajamas come with the nightcap", wardrobe.skin_names(true).has("outfit/pajamas") and wardrobe.skin_names(true).has("hat/nightcap"))


func _test_sleep() -> void:
	var machine := _pet.state_machine
	_pet.sleep_schedule.ask_to_sleep()
	await _frames(1)
	_check("at bedtime she asks to sleep", _pet.conversation.is_running() and _pet.choice_menu.visible)
	_pet.choice_menu.id_pressed.emit(1) # Stay up.
	_pet.choice_menu.hide()
	await _frames(3)
	_pet.bubble.hide_message()
	await _frames(3)
	_check("'stay up' keeps her awake", machine.current_state.name != PetStateMachine.SLEEPING)

	_pet.sleep_schedule.ask_to_sleep()
	await _frames(1)
	_pet.choice_menu.id_pressed.emit(0) # Yes.
	_pet.choice_menu.hide()
	await _frames(3)
	_pet.bubble.hide_message()
	await _frames(3)
	_check("'yes' puts her to sleep", machine.current_state.name == PetStateMachine.SLEEPING)
	_check("asleep she lies down in a wider box", _pet.lying and _pet.get_hit_rect().size.x > _pet.get_hit_rect().size.y)
	_check("asleep she wears pajamas", _pet.wardrobe.worn.has("outfit/pajamas"))
	_check("asleep she has her blanket", _attachment("blanket") == "blanket")
	await get_tree().create_timer(1.5).timeout
	_check("z's float up while she sleeps", _pet.zzz.get_child_count() > 1)
	_pet.reactions._on_clicked(_pet.get_hit_rect().get_center())
	_check("a click doesn't wake her", machine.current_state.name == PetStateMachine.SLEEPING and _pet.bubble.visible)

	SaveData.set_value(&"tools/reminders", [{"id": "alarm", "text": "Alarm", "due": int(Time.get_unix_time_from_system()) - 1, "kind": Reminders.KIND_ALARM}])
	Reminders.check_due()
	await _frames(3)
	_check("an alarm wakes her", machine.current_state.name != PetStateMachine.SLEEPING)
	_check("waking up ends the lying pose", not _pet.lying and _pet.zzz.get_child_count() == 1)
	var waited := 0.0
	while not _pet.announcer.is_active() or not _pet.bubble.visible:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
		if waited > 6.0:
			break
	_pet.bubble.hide_message()
	await _frames(3)
	_check("back in the daytime she's out of pajamas", not _pet.wardrobe.worn.has("outfit/pajamas"))


func _test_watching() -> void:
	var machine := _pet.state_machine
	machine.transition_to(PetStateMachine.IDLE)
	_pet.window_tracker.foreground = {"exe": "game.exe", "fullscreen": true}
	_pet.game_watcher.evaluate()
	_check("a full-screen game sends her to watch", machine.current_state.name == PetStateMachine.WATCHING)
	_check("watching, she lies down in pajamas", _pet.lying and _pet.wardrobe.worn.has("outfit/pajamas"))
	_pet.window_tracker.foreground = {"exe": "explorer.exe", "fullscreen": false}
	_pet.game_watcher.evaluate()
	_check("when the game goes she gets up", machine.current_state.name == PetStateMachine.IDLE and not _pet.lying)
	machine.transition_to(PetStateMachine.DRAGGED, {"grab_offset": Vector2.ZERO})
	_pet.window_tracker.foreground = {"exe": "game.exe", "fullscreen": true}
	_pet.game_watcher.evaluate()
	_check("she isn't pulled away while carried", machine.current_state.name == PetStateMachine.DRAGGED)
	_pet.window_tracker.foreground = {}


# --- Helpers ---------------------------------------------------------------------------

## The attachment name showing in `slot`, or "" if none.
func _attachment(slot: String) -> String:
	var attachment := _pet.sprite.get_skeleton().find_slot(slot).get_attachment()
	return attachment.get_attachment_name() if attachment else ""


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _check(description: String, ok: bool) -> void:
	if ok:
		print("PASS  ", description)
	else:
		_failures += 1
		printerr("FAIL  ", description)
