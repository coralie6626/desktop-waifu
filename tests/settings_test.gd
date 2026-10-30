extends Node
## Self-check for the settings side: audio buses and volumes, the tray menu's actions
## (always on top, click-through, volume, hiding with a timer), the Schedule and Game
## whitelist windows, and break reminders. Run this scene (F6), or
## godot --headless res://tests/settings_test.tscn (exit code 1 on failure).
## Settings it touches are put back afterwards.

const SAVED_SETTINGS: Array[StringName] = [
	&"audio/voice_volume", &"audio/sfx_volume", &"window/always_on_top", &"window/click_through",
	&"schedule/bedtime", &"schedule/wake_time", &"schedule/rest_reminder_minutes",
	&"games/whitelist", &"games/blacklist",
]

var _failures := 0


func _ready() -> void:
	var saved := {}
	for key in SAVED_SETTINGS:
		saved[key] = Settings.get_value(key)
	Settings.set_value(&"schedule/bedtime", "")

	_test_audio()
	await _test_tray()
	_test_schedule_window()
	_test_games_window()
	await _test_rest_nudge()

	for key in SAVED_SETTINGS:
		Settings.set_value(key, saved[key])
	Settings.flush()
	if _failures == 0:
		print("All settings checks passed.")
	else:
		printerr("%d settings check(s) failed." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _test_audio() -> void:
	var voice := AudioServer.get_bus_index(Sound.VOICE_BUS)
	var sfx := AudioServer.get_bus_index(Sound.SFX_BUS)
	_check("there are Voice and SFX buses", voice >= 0 and sfx >= 0)
	Settings.set_value(&"audio/voice_volume", 0.5)
	_check("the voice volume follows the setting", is_equal_approx(AudioServer.get_bus_volume_db(voice), linear_to_db(0.5)))
	Settings.set_value(&"audio/sfx_volume", 0.0)
	_check("zero volume mutes", AudioServer.is_bus_mute(sfx))
	Settings.set_value(&"audio/sfx_volume", 1.0)
	_check("and back up unmutes", not AudioServer.is_bus_mute(sfx))


func _test_tray() -> void:
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var tray: TrayIcon = main.get_node(^"TrayIcon")
	var pet: DesktopPet = main.get_node(^"DesktopPet")
	pet.game_watcher.process_mode = Node.PROCESS_MODE_DISABLED

	Settings.set_value(&"window/always_on_top", true)
	tray._on_menu_id_pressed(TrayIcon.MenuId.ALWAYS_ON_TOP)
	_check("the tray toggles always on top", Settings.get_value(&"window/always_on_top") == false)
	var headless := DisplayServer.get_name() == "headless" # Keeps no window flags.
	_check("and the window follows", headless or get_window().always_on_top == false)
	tray._on_menu_id_pressed(TrayIcon.MenuId.ALWAYS_ON_TOP)
	_check("toggling back works", headless or get_window().always_on_top == true)
	tray._on_menu_id_pressed(TrayIcon.MenuId.CLICK_THROUGH)
	_check("the tray toggles click-through", Settings.get_value(&"window/click_through") == true)
	tray._on_menu_id_pressed(TrayIcon.MenuId.CLICK_THROUGH)
	_check("and back", Settings.get_value(&"window/click_through") == false)

	tray._on_volume_picked(1, &"voice")
	_check("the volume menu sets 25%", is_equal_approx(Settings.get_value(&"audio/voice_volume"), 0.25))
	tray._refresh_menu()
	_check("and shows it checked", tray._volume_menus[&"voice"].is_item_checked(1) and not tray._volume_menus[&"voice"].is_item_checked(4))

	await tray.hide_pet(60)
	_check("'hide for a while' hides her", not pet.visible)
	_check("with a timer to come back", not tray._hide_timer.is_stopped() and is_equal_approx(tray._hide_timer.time_left, 60.0))
	tray._on_hide_timer_timeout()
	_check("she comes back when it's up", pet.visible and pet.bubble.visible)
	await tray.hide_pet(0)
	_check("'hide until restart' has no timer", not pet.visible and tray._hide_timer.is_stopped())
	tray._on_menu_id_pressed(TrayIcon.MenuId.TOGGLE)
	_check("the toggle brings her back", pet.visible)
	main.queue_free()
	await get_tree().process_frame


func _test_schedule_window() -> void:
	var window: ScheduleWindow = Desk.schedule
	window.open()
	window._bedtime.text = "25:00"
	window._save()
	_check("a bad bedtime isn't saved", Settings.get_value(&"schedule/bedtime") == "" and window.visible)
	window._bedtime.text = "22:30"
	window._wake.text = "06:45"
	window._rest.value = 45
	window._save()
	_check("a good schedule is saved", Settings.get_value(&"schedule/bedtime") == "22:30"
		and Settings.get_value(&"schedule/wake_time") == "06:45"
		and Settings.get_value(&"schedule/rest_reminder_minutes") == 45)
	_check("saving closes the window", not window.visible)
	Settings.set_value(&"schedule/bedtime", "")


func _test_games_window() -> void:
	var window: GamesWindow = Desk.games
	Settings.set_value(&"games/whitelist", PackedStringArray(["old.exe"]))
	window.open("game.exe")
	_check("the whitelist is loaded", window._whitelist.text == "old.exe")
	window._add_white.pressed.emit()
	window._add_white.pressed.emit()
	_check("the last app is added once", window._whitelist.text == "old.exe\ngame.exe")
	window._blacklist.text = "  vlc.exe \n\n"
	window._save()
	_check("lists are saved trimmed", Settings.get_value(&"games/whitelist") == PackedStringArray(["old.exe", "game.exe"])
		and Settings.get_value(&"games/blacklist") == PackedStringArray(["vlc.exe"]))
	window.open("")
	_check("without a last app the buttons are off", window._add_white.disabled)
	window.close()


func _test_rest_nudge() -> void:
	var pet: DesktopPet = load("res://scenes/DesktopPet.tscn").instantiate()
	add_child(pet)
	pet.setup(Rect2(0, 0, 800, 600))
	pet.game_watcher.process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().process_frame
	var nudge: RestNudge = pet.get_node(^"RestNudge")
	Settings.set_value(&"schedule/rest_reminder_minutes", 0)
	nudge._process(10.0)
	_check("break reminders can be off", nudge.elapsed == 0.0)
	Settings.set_value(&"schedule/rest_reminder_minutes", 1)
	pet.bubble.hide()
	nudge._process(59.0)
	_check("time counts towards the next break", nudge.elapsed > 58.0 and not pet.bubble.visible)
	nudge._process(2.0)
	_check("then she nudges you", nudge.elapsed == 0.0 and pet.bubble.visible)
	pet.state_machine.transition_to(PetStateMachine.SLEEPING)
	nudge._process(30.0)
	_check("asleep, the count starts over", nudge.elapsed == 0.0)
	pet.queue_free()


func _check(description: String, ok: bool) -> void:
	if ok:
		print("PASS  ", description)
	else:
		_failures += 1
		printerr("FAIL  ", description)
